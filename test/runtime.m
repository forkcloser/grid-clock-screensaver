// Runtime test: what the parity test cannot see.
//
//  1. Time zone. The clock reads the hour in the zone the system is in NOW,
//     not the one it was in when the process started — a saver runs for hours
//     and may cross a zone. Verified by moving the zone under a running
//     process (TZ, which CFTimeZone consults for the system zone) and checking
//     the clock follows libc.
//  2. Timer cadence. Settled, the saver's timer sleeps until the next minute;
//     across a boundary it runs the crossfade at 30 Hz and then settles again.
//     Verified by checking the interval handed to the setter, by counting
//     animateOneFrame calls over a run-loop window while settled, and by
//     forcing a minute change and watching the cadence go up and come back.
//     ScreenSaverView's setter fires animateOneFrame once immediately, so an
//     implementation that re-arms from a settled frame spins at full speed —
//     the count is what catches that.
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

@interface CountingClock : GridClock { @public NSInteger frames; }
@end
@implementation CountingClock
- (void)animateOneFrame { frames++; [super animateOneFrame]; }
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

        // 2. Timer. Stay clear of a minute boundary so the crossfade cannot
        // land inside the measurement window.
        NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
        NSTimeInterval toBoundary = 60.0 - fmod(now, 60.0);
        if (toBoundary < 4.0) {
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

        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
        // startAnimation's own first fire plus the echo of arming: two at most.
        CHECK(view->frames <= 3,
              "%ld animateOneFrame call(s) in 2s while settled (30 Hz would be ~60, a re-arming echo loop ~100,000)",
              (long)view->frames);

        // Force a minute change without waiting for one: back-date the minute
        // the view believes it is showing (KVC reaches the ivar), then let the
        // timer run. Expect the 30 Hz cadence for the 400 ms crossfade, then
        // the coarse interval again.
        long long shown = [[view valueForKey:@"minuteIndex"] longLongValue];
        [view setValue:@(shown - 1) forKey:@"minuteIndex"];
        view->frames = 0;
        [view animateOneFrame];
        // (The private _animating flag is not observable through KVC — the key
        // "animating" resolves to ScreenSaverView's isAnimating, the timer's
        // state — so the interval is the witness for both transitions.)
        CHECK(fabs(view.animationTimeInterval - kFrameInterval) < 1e-9,
              "a minute change starts the crossfade at 30 Hz (%.4fs)", view.animationTimeInterval);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        CHECK(view->frames >= 8 && view->frames <= 40,
              "%ld frame(s) drawn for the 400 ms crossfade (expect ~12–16 at 30 Hz)", (long)view->frames);
        CHECK(view.animationTimeInterval > 1.0,
              "the crossfade has settled after 1s, back at a coarse interval (%.2fs)", view.animationTimeInterval);
        [view stopAnimation];
    }
    if (failures) {
        printf("runtime: %d check(s) failed\n", failures);
        return 1;
    }
    printf("runtime: all checks passed\n");
    return 0;
}
