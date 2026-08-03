// Parity test: the port must say exactly what upstream 0.0.5 said, for every
// minute of the day.
//
// GridClock.m is #included rather than linked so the test reaches the static
// letter table and GCComputeLitCells directly — the shipped source is what is
// under test, not a copy of its logic.
//
// Output format, one line per minute: "HH:MM " followed by 240 characters,
// '1' where the cell is lit. The last line is the letter grid itself. That is
// compared byte for byte against test/golden.txt, which was generated from
// upstream's own Webview/index.js — see test/regenerate-golden.js.

#import "../GridClock.m"

int main(void) {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        BOOL lit[kGlyphCount];
        for (NSInteger h = 0; h < 24; h++) {
            for (NSInteger m = 0; m < 60; m++) {
                GCComputeLitCells(h, m, lit);
                [out appendFormat:@"%02ld:%02ld ", (long)h, (long)m];
                for (NSInteger i = 0; i < kGlyphCount; i++) {
                    [out appendString:lit[i] ? @"1" : @"0"];
                }
                [out appendString:@"\n"];
            }
        }
        [out appendFormat:@"LETTERS %s\n", kLetters];
        fputs(out.UTF8String, stdout);
    }
    return 0;
}
