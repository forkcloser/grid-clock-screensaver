// Runtime test: what the parity test cannot see.
//
//  1. Time zone. The clock reads the hour in the zone the system is in NOW,
//     not the one it was in when the process started — a saver runs for hours
//     and may cross a zone. Verified by moving the zone under a running
//     process (TZ, which CFTimeZone consults for the system zone) and checking
//     the clock follows libc.
//  2. Timer cadence. Settled, the saver's timer sleeps until the next minute;
//     across a boundary it runs the crossfade at 30 Hz and then settles again.
//     One run-loop window proves the coarse interval takes effect on a live
//     timer; the crossfade itself is stepped by calling animateOneFrame
//     directly and ageing _transitionStart, so no assertion depends on how many
//     timer fires the OS chose to deliver. ScreenSaverView's setter fires
//     animateOneFrame once immediately, so an implementation that re-arms from
//     a settled frame spins at full speed — the arm count is what catches that.
//     Counting delivered frames would not: a loaded machine drops timer fires
//     (NSTimer never makes up a missed one), which is a property of the
//     scheduler, not of the saver.
//
// GridClock.m is #included, as in parity.m, so the static helpers are reachable
// and the shipped source is what is under test.

#import "../GridClock.m"
#include <time.h>

static int failures = 0;
#define CHECK(cond, ...) do {                                        \
        if (cond) { printf("PASS: " __VA_ARGS__); printf("\n"); }    \
        else { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } \
    } while (0)

@interface CountingClock : GridClock { @public NSInteger frames; NSInteger arms; }
@end
@implementation CountingClock
- (void)animateOneFrame { frames++; [super animateOneFrame]; }
// Arming is the state change worth counting: the saver re-arms exactly twice
// per minute (into the crossfade, then back out). A third arm from a settled
// frame is the spin bug, and it is visible here without running a timer.
- (void)setAnimationTimeInterval:(NSTimeInterval)interval {
    arms++;
    [super setAnimationTimeInterval:interval];
}
@end

static void expectHourInZone(const char *zone) {
    setenv("TZ", zone, 1);
    tzset();
    NSDate *now = NSDate.date;
    NSInteger hour = -1, minute = -1;
    GCLocalHourMinute(now, &hour, &minute);
    time_t t = (time_t)now.timeIntervalSince1970;
    struct tm local;
    localtime_r(&t, &local);
    CHECK(hour == local.tm_hour && minute == local.tm_min,
          "zone %-19s clock says %02ld:%02ld, libc says %02d:%02d",
          zone, (long)hour, (long)minute, local.tm_hour, local.tm_min);
}

int main(void) {
    @autoreleasepool {
        NSApplicationLoad();

        // 0. Brightness clamps to its range; the range never reaches black.
        CHECK(GCClampedBrightness(0) == kMinBrightness && GCClampedBrightness(-7) == kMinBrightness,
              "brightness below the floor clamps to %ld%%", (long)kMinBrightness);
        CHECK(GCClampedBrightness(250) == kMaxBrightness, "brightness above 100 clamps to 100%%");
        CHECK(GCClampedBrightness(42) == 42, "brightness in range is kept");

        // 1. Time zone: three zones with distinct offsets, changed after the
        // process has already read the clock once.
        NSInteger hour, minute;
        GCLocalHourMinute(NSDate.date, &hour, &minute);
        expectHourInZone("UTC");
        expectHourInZone("Asia/Tokyo");
        expectHourInZone("America/Los_Angeles");
        unsetenv("TZ");
        tzset();
        [NSTimeZone resetSystemTimeZone];

        // 2. Timer. Stay clear of a minute boundary so a real crossfade cannot
        // land inside the one measured window below. This is the only wait in
        // the file, it fires for about 3% of runs, and it removes a flake
        // rather than risking one.
        NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
        NSTimeInterval toBoundary = 60.0 - fmod(now, 60.0);
        if (toBoundary < 2.0) {
            printf("waiting %.1fs for the minute boundary to pass\n", toBoundary + 0.2);
            [NSThread sleepForTimeInterval:toBoundary + 0.2];
        }
        CountingClock *view = [[CountingClock alloc] initWithFrame:NSMakeRect(0, 0, 400, 250) isPreview:NO];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:view.frame
                                                       styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.contentView = view;
        [view startAnimation];

        now = NSDate.timeIntervalSinceReferenceDate;
        NSTimeInterval expected = 60.0 - fmod(now, 60.0);
        CHECK(fabs(view.animationTimeInterval - expected) < 0.5,
              "settled interval is %.2fs; the next minute is in %.2fs",
              view.animationTimeInterval, expected);
        CHECK(view.animationTimeInterval > 1.0,
              "settled interval is coarse, not 30 Hz (%.3fs)", view.animationTimeInterval);

        // The one window that needs a live timer: it proves a coarse interval
        // actually takes effect on a running one. The bound is an upper bound,
        // so a starved runner can only make it pass harder — the expected count
        // (startAnimation's first fire plus the echo of arming) does not grow
        // with the window, but a spin does: 30 Hz would be ~15 here, the
        // re-arming echo loop ~60,000.
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        CHECK(view->frames <= 3,
              "%ld animateOneFrame call(s) in 0.5s while settled", (long)view->frames);

        // Force a minute change without waiting for one: back-date the minute
        // the view believes it is showing (KVC reaches the ivar). From here the
        // crossfade is stepped by hand — every frame the saver would draw is a
        // call to animateOneFrame, and calling it directly is the same state
        // machine at a cadence the test chooses instead of one the scheduler
        // hands out. Nothing below waits for wall-clock time.
        long long shown = [[view valueForKey:@"minuteIndex"] longLongValue];
        [view setValue:@(shown - 1) forKey:@"minuteIndex"];
        view->frames = 0;
        view->arms = 0;
        [view animateOneFrame];
        // (The private _animating flag is not observable through KVC — the key
        // "animating" resolves to ScreenSaverView's isAnimating, the timer's
        // state — so the interval and the arm count are the witnesses.)
        CHECK(fabs(view.animationTimeInterval - kFrameInterval) < 1e-9,
              "a minute change starts the crossfade at 30 Hz (%.4fs)", view.animationTimeInterval);
        CHECK(view->arms == 1, "the minute change armed exactly once (%ld)", (long)view->arms);

        // Mid-crossfade: the transition is younger than kTransition, so every
        // frame must stay at 30 Hz and must not re-arm.
        NSInteger armsAtStart = view->arms;
        for (int i = 0; i < 5; i++) [view animateOneFrame];
        CHECK(view->arms == armsAtStart,
              "5 mid-crossfade frames re-armed nothing (%ld arm(s))", (long)(view->arms - armsAtStart));
        CHECK(fabs(view.animationTimeInterval - kFrameInterval) < 1e-9,
              "mid-crossfade the cadence is still 30 Hz (%.4fs)", view.animationTimeInterval);

        // Age the transition past its duration rather than sleeping through it:
        // transitionProgress is (now - _transitionStart) / kTransition, so
        // back-dating the start is exactly equivalent to 400 ms having elapsed.
        NSTimeInterval started = [[view valueForKey:@"transitionStart"] doubleValue];
        [view setValue:@(started - kTransition - 0.001) forKey:@"transitionStart"];
        [view animateOneFrame];
        CHECK(view.animationTimeInterval > 1.0,
              "the frame past the end of the crossfade settles to a coarse interval (%.2fs)",
              view.animationTimeInterval);
        CHECK(view->arms == armsAtStart + 1,
              "settling armed exactly once (%ld arm(s) for the whole crossfade)", (long)view->arms);

        // Settled: ScreenSaverView's setter fires animateOneFrame once
        // immediately, so a frame that re-arms while settled spins the timer at
        // full speed. Twenty settled frames must arm nothing at all.
        NSInteger armsAfterSettle = view->arms;
        for (int i = 0; i < 20; i++) [view animateOneFrame];
        CHECK(view->arms == armsAfterSettle,
              "20 settled frames re-armed nothing (%ld arm(s)) — a re-arming frame would spin the timer",
              (long)(view->arms - armsAfterSettle));
        [view stopAnimation];
    }
    if (failures) {
        printf("runtime: %d check(s) failed\n", failures);
        return 1;
    }
    printf("runtime: all checks passed\n");
    return 0;
}
