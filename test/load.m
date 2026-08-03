// Bundle test: load the built .saver the way the screensaver host does —
// NSBundle + principalClass — instantiate it, render offscreen, and check the
// frame looks like a lit grid on black.
//
// This is the check a unit test cannot make: that the thing we ship is a
// loadable bundle whose principal class is wired up, not just source that
// compiles. Usage: load <path-to-.saver> [output.png]

#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: load <path-to-.saver> [output.png]\n");
            return 2;
        }
        NSApplicationLoad();

        NSBundle *bundle = [NSBundle bundleWithPath:@(argv[1])];
        if (!bundle) { printf("FAIL: bundle not found at %s\n", argv[1]); return 1; }
        if (![bundle load]) { printf("FAIL: bundle would not load\n"); return 1; }
        printf("PASS: bundle loaded\n");

        Class cls = bundle.principalClass;
        if (!cls) { printf("FAIL: no principal class\n"); return 1; }
        printf("PASS: principal class = %s\n", NSStringFromClass(cls).UTF8String);
        if (![cls isSubclassOfClass:ScreenSaverView.class]) {
            printf("FAIL: principal class is not a ScreenSaverView\n"); return 1;
        }
        printf("PASS: is a ScreenSaverView subclass\n");

        NSRect frame = NSMakeRect(0, 0, 1600, 1000);
        ScreenSaverView *view = [[cls alloc] initWithFrame:frame isPreview:NO];
        if (!view) { printf("FAIL: init returned nil\n"); return 1; }
        printf("PASS: instantiated (animationTimeInterval = %.4f s)\n", view.animationTimeInterval);

        if (!view.hasConfigureSheet || !view.configureSheet) {
            printf("FAIL: configure sheet missing — Options... would do nothing\n"); return 1;
        }
        printf("PASS: configure sheet builds\n");

        [view startAnimation];
        [view animateOneFrame];

        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:frame];
        [view cacheDisplayInRect:frame toBitmapImageRep:rep];

        // Three populations are expected: the black surround, the #222 unlit
        // glyphs, and the near-white lit ones. Any missing population means the
        // face did not draw.
        NSInteger black = 0, unlit = 0, lit = 0, other = 0;
        for (NSInteger y = 0; y < rep.pixelsHigh; y += 2) {
            for (NSInteger x = 0; x < rep.pixelsWide; x += 2) {
                NSUInteger px[4];
                [rep getPixel:px atX:x y:y];
                NSUInteger v = px[0];
                if (v < 8)        black++;
                else if (v < 60)  unlit++;
                else if (v > 200) lit++;
                else              other++;
            }
        }
        printf("pixels: black=%ld unlit=%ld lit=%ld antialiased=%ld\n",
               (long)black, (long)unlit, (long)lit, (long)other);
        if (black == 0 || unlit == 0 || lit == 0) {
            printf("FAIL: rendered frame does not look like a lit grid on black\n");
            return 1;
        }
        printf("PASS: rendered a lit grid on a black background\n");

        if (argc > 2) {
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if (![png writeToFile:@(argv[2]) atomically:YES]) {
                printf("FAIL: could not write %s\n", argv[2]); return 1;
            }
            printf("wrote %s\n", argv[2]);
        }

        [view stopAnimation];
        printf("PASS: stopAnimation clean\n");
    }
    return 0;
}
