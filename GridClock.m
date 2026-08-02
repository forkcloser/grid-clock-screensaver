#import "GridClock.h"
#import <CoreText/CoreText.h>

// The clock is a 16 x 15 grid of letters. Reading the lit letters left-to-right,
// top-to-bottom spells out the time. Every word the clock can say is a run of
// consecutive cells in that grid, so the whole thing is a letter table plus a
// table of (offset, length) spans.

#define kCols 16
#define kRows 15
#define kGlyphCount (kCols * kRows)

static const char * const kLetters =
    "ONETWOTHREEFOURS"
    "ATFIVESIXSEVENBE"
    "EIGHTNINETENSOON"
    "ELEVENTWELVEHALF"
    "QUARTERMINUTESTO"
    "TWENTYTHIRTEENAT"
    "FOURTEENFIFTEENS"
    "PASTTOSIXTEENCKN"
    "SEVENTEENTWENTYA"
    "EIGHTEENNINETEEN"
    "THIRTYFORTYFIFTY"
    "OCLOCKONETWOMOON"
    "THREEFOURFIVESIX"
    "SEVENEIGHTNINEIO"
    "TENELEVENTWELVES";

typedef NS_ENUM(NSUInteger, GCWord) {
    // The numerals in the top half of the grid, used as the leading value.
    GCWordPrefixOne, GCWordPrefixTwo, GCWordPrefixThree, GCWordPrefixFour,
    GCWordPrefixFive, GCWordPrefixSix, GCWordPrefixSeven, GCWordPrefixEight,
    GCWordPrefixNine, GCWordPrefixTen, GCWordPrefixEleven, GCWordPrefixTwelve,
    // The numerals in the bottom half, used as the trailing value.
    GCWordSuffixOne, GCWordSuffixTwo, GCWordSuffixThree, GCWordSuffixFour,
    GCWordSuffixFive, GCWordSuffixSix, GCWordSuffixSeven, GCWordSuffixEight,
    GCWordSuffixNine, GCWordSuffixTen, GCWordSuffixEleven, GCWordSuffixTwelve,

    GCWordThirteen, GCWordFourteen, GCWordSixteen,
    GCWordSeventeen, GCWordEighteen, GCWordNineteen,

    GCWordTwenty,        // "twenty past" / "twenty to"
    GCWordMinutesTwenty, // the tens digit of a bare minute count
    GCWordMinutesThirty, GCWordMinutesForty, GCWordMinutesFifty,

    GCWordHalf, GCWordQuarter, GCWordMinute, GCWordMinutes,
    GCWordPast, GCWordTo, GCWordOClock,

    GCWordCount
};

// Indexed by GCWord; FIFTEEN (row 6) is deliberately unreachable — quarter past
// wins at :15 — but stays in the grid as filler.
static const struct { uint16_t offset, length; } kWords[GCWordCount] = {
    {   0, 3 }, {   3, 3 }, {   6, 5 }, {  11, 4 },  // one two three four
    {  18, 4 }, {  22, 3 }, {  25, 5 }, {  32, 5 },  // five six seven eight
    {  37, 4 }, {  41, 3 }, {  48, 6 }, {  54, 6 },  // nine ten eleven twelve

    { 182, 3 }, { 185, 3 }, { 192, 5 }, { 197, 4 },  // one two three four
    { 201, 4 }, { 205, 3 }, { 208, 5 }, { 213, 5 },  // five six seven eight
    { 218, 4 }, { 224, 3 }, { 227, 6 }, { 233, 6 },  // nine ten eleven twelve

    {  86, 8 }, {  96, 8 }, { 118, 7 },              // thirteen fourteen sixteen
    { 128, 9 }, { 144, 8 }, { 152, 8 },              // seventeen eighteen nineteen

    {  80, 6 },                                      // twenty
    { 137, 6 }, { 160, 6 }, { 166, 5 }, { 171, 5 },  // twenty thirty forty fifty

    {  60, 4 }, {  64, 7 }, {  71, 6 }, {  71, 7 },  // half quarter minute minutes
    { 112, 4 }, { 116, 2 }, { 176, 6 },              // past to oclock
};

// Matches the CSS the web version used: #222 unlit, #fff lit, 400ms crossfade.
static const CGFloat kUnlitLevel      = 0x22 / 255.0;
static const CGFloat kTransition      = 0.4;
static const CGFloat kGridScale       = 0.92;  // fraction of the short edge
static const CGFloat kFontSizeRatio   = 0.45;  // point size as a fraction of a cell

static NSString * const kModuleName          = @"com.chrstphrknwtn.grid-clock";
static NSString * const kDisplayModeKey      = @"displayMode";
static NSString * const kLegacyDisplayKey    = @"screenDisplayOption";

typedef NS_ENUM(NSInteger, GCDisplayMode) {
    GCDisplayModeMainOnly = 0,
    GCDisplayModeAllDisplays = 1,
};

#pragma mark - Time -> lit cells

static void GCLight(BOOL *lit, GCWord word) {
    for (uint16_t i = 0; i < kWords[word].length; i++) {
        lit[kWords[word].offset + i] = YES;
    }
}

// hour is 1...12
static void GCLightPrefixHour(BOOL *lit, NSInteger hour) {
    GCLight(lit, (GCWord)(GCWordPrefixOne + (hour - 1)));
}

// hour is 1...13, where 13 wraps back around to one
static void GCLightSuffixHour(BOOL *lit, NSInteger hour) {
    if (hour == 13) hour = 1;
    GCLight(lit, (GCWord)(GCWordSuffixOne + (hour - 1)));
}

static void GCComputeLitCells(NSInteger hour24, NSInteger minute, BOOL *lit) {
    memset(lit, NO, sizeof(BOOL) * kGlyphCount);

    NSInteger hour = hour24 % 12;
    if (hour == 0) hour = 12;

    // "one minute past four"
    if (minute == 1) {
        GCLight(lit, GCWordPrefixOne);
        GCLight(lit, GCWordMinute);
        GCLight(lit, GCWordPast);
        GCLightSuffixHour(lit, hour);
        return;
    }

    // "seven minutes past four"
    if (minute >= 2 && minute <= 12) {
        GCLightPrefixHour(lit, minute);
        GCLight(lit, GCWordMinutes);
        GCLight(lit, GCWordPast);
        GCLightSuffixHour(lit, hour);
        return;
    }

    switch (minute) {
        case  0: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordOClock);    return;
        case 13: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordThirteen);  return;
        case 14: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordFourteen);  return;
        case 16: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordSixteen);   return;
        case 17: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordSeventeen); return;
        case 18: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordEighteen);  return;
        case 19: GCLightPrefixHour(lit, hour); GCLight(lit, GCWordNineteen);  return;

        case 15: GCLight(lit, GCWordQuarter); GCLight(lit, GCWordPast); GCLightSuffixHour(lit, hour); return;
        case 20: GCLight(lit, GCWordTwenty);  GCLight(lit, GCWordPast); GCLightSuffixHour(lit, hour); return;
        case 30: GCLight(lit, GCWordHalf);    GCLight(lit, GCWordPast); GCLightSuffixHour(lit, hour); return;

        case 40: GCLight(lit, GCWordTwenty);    GCLight(lit, GCWordTo); GCLightSuffixHour(lit, hour + 1); return;
        case 45: GCLight(lit, GCWordQuarter);   GCLight(lit, GCWordTo); GCLightSuffixHour(lit, hour + 1); return;
        case 50: GCLight(lit, GCWordPrefixTen); GCLight(lit, GCWordTo); GCLightSuffixHour(lit, hour + 1); return;
        case 55: GCLight(lit, GCWordPrefixFive);GCLight(lit, GCWordTo); GCLightSuffixHour(lit, hour + 1); return;
    }

    // Anything left over is read as a bare number: "four thirty seven"
    GCLightPrefixHour(lit, hour);
    switch (minute / 10) {
        case 2: GCLight(lit, GCWordMinutesTwenty); break;
        case 3: GCLight(lit, GCWordMinutesThirty); break;
        case 4: GCLight(lit, GCWordMinutesForty);  break;
        case 5: GCLight(lit, GCWordMinutesFifty);  break;
    }
    NSInteger units = minute % 10;
    if (units != 0) {
        GCLight(lit, (GCWord)(GCWordSuffixOne + (units - 1)));
    }
}

#pragma mark -

@implementation GridClock {
    BOOL            _lit[kGlyphCount];      // where the grid is heading
    BOOL            _wasLit[kGlyphCount];   // where it came from
    NSTimeInterval  _transitionStart;
    long long       _minuteIndex;
    BOOL            _animating;
    BOOL            _visibleOnThisScreen;

    NSFont         *_font;
    CGGlyph         _glyphs[kGlyphCount];
    CGFloat         _advances[kGlyphCount];
    CGFloat         _capHeight;

    NSWindow       *_configSheet;
    NSPopUpButton  *_displayModePopUp;
}

+ (ScreenSaverDefaults *)defaults {
    static ScreenSaverDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = [ScreenSaverDefaults defaultsForModuleWithName:kModuleName];
        // 0.0.5 stored 0 = primary, 1 = last focused, 2 = all. "Last focused"
        // is meaningless now that macOS hosts each display in its own process,
        // so it collapses into "main display".
        if ([defaults objectForKey:kDisplayModeKey] == nil) {
            id legacy = [defaults objectForKey:kLegacyDisplayKey];
            if (legacy != nil) {
                [defaults setInteger:([legacy integerValue] >= 2 ? GCDisplayModeAllDisplays
                                                                 : GCDisplayModeMainOnly)
                              forKey:kDisplayModeKey];
                [defaults synchronize];
            }
        }
        [defaults registerDefaults:@{ kDisplayModeKey: @(GCDisplayModeMainOnly) }];
    });
    return defaults;
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (!self) return nil;

    self.animationTimeInterval = 1.0 / 30.0;
    _visibleOnThisScreen = YES;
    [self refreshLitCells];
    memcpy(_wasLit, _lit, sizeof(_lit));  // start settled, don't fade in
    _animating = NO;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(screenParametersChanged:)
                                               name:NSApplicationDidChangeScreenParametersNotification
                                             object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - ScreenSaverView

- (BOOL)isOpaque { return YES; }

- (void)startAnimation {
    [super startAnimation];
    [self updateVisibility];
    [self refreshLitCells];
    memcpy(_wasLit, _lit, sizeof(_lit));
    _animating = NO;
    [self setNeedsDisplay:YES];
}

- (void)animateOneFrame {
    long long minuteIndex = (long long)floor(NSDate.timeIntervalSinceReferenceDate / 60.0);
    if (minuteIndex != _minuteIndex) {
        memcpy(_wasLit, _lit, sizeof(_lit));
        [self refreshLitCells];
        _transitionStart = NSDate.timeIntervalSinceReferenceDate;
        _animating = YES;
    }
    if (!_animating) return;

    // Draw this frame first, then settle — so the frame that lands on progress
    // 1.0 is the one that paints the final colours.
    [self setNeedsDisplay:YES];
    if ([self transitionProgress] >= 1.0) _animating = NO;
}

- (void)refreshLitCells {
    NSDate *now = NSDate.date;
    _minuteIndex = (long long)floor(now.timeIntervalSinceReferenceDate / 60.0);
    NSDateComponents *c = [NSCalendar.currentCalendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                                       fromDate:now];
    GCComputeLitCells(c.hour, c.minute, _lit);
}

// Linear progress through the crossfade, eased. smoothstep is a close enough
// stand-in for the CSS `ease-in-out` the web version used.
- (CGFloat)transitionProgress {
    if (kTransition <= 0) return 1.0;
    CGFloat t = (NSDate.timeIntervalSinceReferenceDate - _transitionStart) / kTransition;
    return t <= 0 ? 0.0 : (t >= 1 ? 1.0 : t);
}

#pragma mark - Display selection

- (void)screenParametersChanged:(NSNotification *)note { [self updateVisibility]; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self updateVisibility];
}

- (void)updateVisibility {
    BOOL visible = YES;
    if (!self.isPreview &&
        [GridClock.defaults integerForKey:kDisplayModeKey] == GCDisplayModeMainOnly) {
        // The main display is the one anchored at the origin of the global
        // coordinate space. Comparing origins rather than NSScreen identity
        // holds up even though macOS 14+ runs a separate saver process per
        // display. If we can't tell, show it rather than leaving a black screen.
        NSScreen *screen = self.window.screen;
        visible = (screen == nil) || CGPointEqualToPoint(screen.frame.origin, CGPointZero);
    }
    if (visible != _visibleOnThisScreen) {
        _visibleOnThisScreen = visible;
        [self setNeedsDisplay:YES];
    }
}

#pragma mark - Drawing

- (void)prepareGlyphsForCellSize:(CGFloat)cell {
    CGFloat pointSize = cell * kFontSizeRatio;
    if (_font && fabs(pointSize - _font.pointSize) < 0.01) return;

    _font = [NSFont systemFontOfSize:pointSize weight:NSFontWeightLight];
    CTFontRef font = (__bridge CTFontRef)_font;

    UniChar chars[kGlyphCount];
    for (NSInteger i = 0; i < kGlyphCount; i++) chars[i] = (UniChar)kLetters[i];
    CTFontGetGlyphsForCharacters(font, chars, _glyphs, kGlyphCount);

    CGSize advances[kGlyphCount];
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, _glyphs, advances, kGlyphCount);
    for (NSInteger i = 0; i < kGlyphCount; i++) _advances[i] = advances[i].width;

    _capHeight = CTFontGetCapHeight(font);
}

- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.blackColor setFill];
    NSRectFill(dirtyRect);
    if (!_visibleOnThisScreen) return;

    NSRect bounds = self.bounds;
    CGFloat cell = MIN(NSWidth(bounds), NSHeight(bounds)) * kGridScale / kCols;
    if (cell <= 0) return;
    [self prepareGlyphsForCellSize:cell];

    CGFloat originX = NSMinX(bounds) + (NSWidth(bounds)  - cell * kCols) / 2.0;
    CGFloat originY = NSMinY(bounds) + (NSHeight(bounds) - cell * kRows) / 2.0;
    CGFloat baselineInset = (cell - _capHeight) / 2.0;

    CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);

    // Every cell is unlit, lighting up, going dark, or lit — and they all turn
    // over on the same minute boundary, so the grid needs at most four passes.
    CGFloat t = [self transitionProgress];
    CGFloat eased = t * t * (3.0 - 2.0 * t);
    const CGFloat levels[4] = { 0.0, eased, 1.0 - eased, 1.0 };

    CGGlyph glyphs[kGlyphCount];
    CGPoint positions[kGlyphCount];

    for (int pass = 0; pass < 4; pass++) {
        size_t n = 0;
        for (NSInteger i = 0; i < kGlyphCount; i++) {
            int state = (_wasLit[i] ? 2 : 0) | (_lit[i] ? 1 : 0);
            if (state != pass) continue;
            glyphs[n] = _glyphs[i];
            positions[n] = CGPointMake(originX + (i % kCols) * cell + (cell - _advances[i]) / 2.0,
                                       originY + (kRows - 1 - i / kCols) * cell + baselineInset);
            n++;
        }
        if (n == 0) continue;

        CGFloat v = kUnlitLevel + (1.0 - kUnlitLevel) * levels[pass];
        [[NSColor colorWithSRGBRed:v green:v blue:v alpha:1.0] setFill];
        CTFontDrawGlyphs((__bridge CTFontRef)_font, glyphs, positions, n, ctx);
    }
}

#pragma mark - Configure sheet

- (BOOL)hasConfigureSheet { return YES; }

- (NSWindow *)configureSheet {
    if (!_configSheet) [self buildConfigureSheet];
    [_displayModePopUp selectItemAtIndex:[GridClock.defaults integerForKey:kDisplayModeKey]];
    return _configSheet;
}

- (void)buildConfigureSheet {
    _configSheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 380, 124)
                                               styleMask:NSWindowStyleMaskTitled
                                                 backing:NSBackingStoreBuffered
                                                   defer:YES];
    NSView *content = _configSheet.contentView;

    NSTextField *label = [NSTextField labelWithString:@"Show on:"];
    label.frame = NSMakeRect(20, 74, 70, 20);
    label.alignment = NSTextAlignmentRight;
    [content addSubview:label];

    _displayModePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(96, 70, 264, 26) pullsDown:NO];
    [_displayModePopUp addItemsWithTitles:@[ @"Main display only", @"All displays" ]];
    [content addSubview:_displayModePopUp];

    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelClick:)];
    cancel.frame = NSMakeRect(180, 16, 88, 32);
    cancel.keyEquivalent = @"\033";
    [content addSubview:cancel];

    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(okClick:)];
    ok.frame = NSMakeRect(272, 16, 88, 32);
    ok.keyEquivalent = @"\r";
    [content addSubview:ok];
}

- (void)okClick:(id)sender {
    ScreenSaverDefaults *defaults = GridClock.defaults;
    [defaults setInteger:_displayModePopUp.indexOfSelectedItem forKey:kDisplayModeKey];
    [defaults synchronize];
    [self updateVisibility];
    [self endConfigureSheet];
}

- (void)cancelClick:(id)sender {
    [self endConfigureSheet];
}

- (void)endConfigureSheet {
    NSWindow *parent = _configSheet.sheetParent;
    if (parent) {
        [parent endSheet:_configSheet];
    } else {
        [_configSheet orderOut:nil];
    }
}

@end
