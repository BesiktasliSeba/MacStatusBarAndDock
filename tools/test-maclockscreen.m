// test-maclockscreen.m -- Mac test of Mac Lock Screen's plain rules (common/MacLockScreen.h, F49 1.8.9; plans/design-mac-lock-screen.md 2.4-2.7,
// 3.1 and rev 2's section 12): the settings and their per-version defaults (rev 2: the full Mac look everywhere), which parts install hooks, the
// event machine (one case per sequence of 2.7 and 12.2 (3)), the poster switcher's bounded state (12.2 (2)), the first appearance's face
// (12.2 (1)), the name rule, the Mac clock's sizes and clamp on the four test iPads' screens in both orientations (12.4, 12.5, with the
// EXPECTED values L33 measures against), the macOS user block (12.6: sizes, the field's place and yield, the hint pick, the look, the glyph),
// the pair's place, the legibility pick, the backdrop's key, crop and size (12.2 (4)), the depth stand-down (12.7), the state file. Built by
// test-maclockscreen.sh (also against made-to-fail copies of the header: each must fail).
#import <Foundation/Foundation.h>
#include MLS_HEADER

static int gFail, gPass;
#define CHECK(cond, ...) do { if (cond) gPass++; else { gFail++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)

// ---- stand-ins for the 17/18 lock poster's configuration (1.8.9 pass: the black backdrop), shaped as Apple's IPSWs show the classes: on 17.5.1 and 18.5 the
// configuration (PRSPosterConfiguration) has -serverUUID and -_path (and an ivar _path) but NO -posterUUID; the path has -serverIdentity; the
// identity has -posterUUID, -version and -supplement (unsigned long long) ----
@interface TPosterIdentity : NSObject
@property (nonatomic, strong) NSUUID *posterUUID;
@property (nonatomic) unsigned long long version, supplement;
@end
@implementation TPosterIdentity
@end
@interface TPosterPath : NSObject
@property (nonatomic, strong) TPosterIdentity *serverIdentity;
@end
@implementation TPosterPath
@end
@interface TPosterConfig18 : NSObject { TPosterPath *_path; }   // (17.5.1 / 18.5: -serverUUID, -_path and the ivar)
- (instancetype)initWithPath:(TPosterPath *)path;
@end
@implementation TPosterConfig18
- (instancetype)initWithPath:(TPosterPath *)path { if ((self = [super init])) _path = path; return self; }
- (NSUUID *)serverUUID { return _path.serverIdentity.posterUUID; }
- (TPosterPath *)_path { return _path; }
@end
@interface TPosterConfigIvarOnly : NSObject { TPosterPath *_path; }   // (the path by its ivar alone)
- (instancetype)initWithPath:(TPosterPath *)path;
@end
@implementation TPosterConfigIvarOnly
- (instancetype)initWithPath:(TPosterPath *)path { if ((self = [super init])) _path = path; return self; }
@end
@interface TPosterConfigOdd : NSObject   // (routes with other types: never read, never thrown)
@end
@implementation TPosterConfigOdd
- (int)posterUUID { return 7; }
- (NSUUID *)serverUUID:(int)x { (void)x; return [NSUUID UUID]; }
- (NSString *)version { return @"9"; }
@end
@interface TPosterConfigOld : NSObject   // (a configuration with -posterUUID itself, as rev 2 expected)
@property (nonatomic, strong) NSUUID *posterUUID;
@end
@implementation TPosterConfigOld
@end
static TPosterConfig18 *TConfig(NSUUID *u, unsigned long long v, unsigned long long sup) {
    TPosterIdentity *i = [TPosterIdentity new]; i.posterUUID = u; i.version = v; i.supplement = sup;
    TPosterPath *p = [TPosterPath new]; p.serverIdentity = i;
    return [[TPosterConfig18 alloc] initWithPath:p];
}
// ---- stand-ins for what draws iPadOS's clock (1.8.9 pass: two clocks on 16): 15.6.1 has SBFLockScreenDateView only; 16.7.7, 17.5.1 and 18.5 have CoverSheetKit's
// CSProminentDisplayView (with _timeView) and CSProminentTimeView (-setDate:) beside the date view ----
@interface TDateView : NSObject { id _timeLabel; }
- (void)setCustomSubtitleView:(id)v; - (void)_updateLabelAlpha;
@end
@implementation TDateView
- (void)setCustomSubtitleView:(id)v { (void)v; }
- (void)_updateLabelAlpha {}
@end
@interface TProminent : NSObject { id _timeView; }
- (void)layoutSubviews;
@end
@implementation TProminent
- (void)layoutSubviews {}
@end
@interface TProminentNoTime : NSObject
- (void)layoutSubviews;
@end
@implementation TProminentNoTime
- (void)layoutSubviews {}
@end
@interface TTimeView : NSObject
- (void)setDate:(id)d;
@end
@implementation TTimeView
- (void)setDate:(id)d { (void)d; }
@end

int main(void) { @autoreleasepool {
    // ---- defaults (rev 2, 12.3 / 12.8; KT 25 Nov ~11:45: the full Mac look by default on every iPadOS; the master off) ----
    for (int os = 15; os <= 18; os++) {
        MLSettings s = MLSettingsFrom(@{}, os);
        CHECK(!s.enabled, "iPadOS %d: the master is off when never set", os);
        CHECK(s.clockStyle == kMLClockMac, "iPadOS %d: the clock default is the Mac clock", os);
        CHECK(s.background == (os >= 17 ? kMLBackWallpaper : kMLBackBlurred), "iPadOS %d: the background default is %s (1.8.9 pass: the black backdrop: the sharp wallpaper on 17/18)", os, os >= 17 ? "Wallpaper" : "Blurred");
        CHECK(s.cards && s.showUser && s.statusPair, "iPadOS %d: cards, picture and name, pair on when never set", os);
        CHECK(s.picture == kMLPictureInitials && s.name[0] == 0, "iPadOS %d: initials and the automatic name by default", os);
        // with the master off nothing is wanted, whatever the parts say
        MLSettings off = MLSettingsFrom(@{ @"clockStyle": @"mac", @"background": @"blurred" }, os);
        CHECK(!MLAnyPartWanted(&off), "iPadOS %d: master off = no part wanted (no hook at all)", os);
        MLSettings on = MLSettingsFrom(@{ @"enabled": @YES }, os);
        CHECK(MLPartWanted(&on, kMLPartClock), "iPadOS %d: the default clock is the Mac's (its hooks go in)", os);
        CHECK(MLPartWanted(&on, kMLPartBackground) == (os < 17), "iPadOS %d: the default background %s", os, os < 17 ? "is ours (the blurred wallpaper)" : "is iPadOS's own (no backdrop work at all, 1.8.9 pass: the black backdrop)");
        CHECK(MLPartWanted(&on, kMLPartCards) && MLPartWanted(&on, kMLPartUser), "iPadOS %d: cards and the user block on by default", os);
        CHECK(MLPartWanted(&on, kMLPartPair), "iPadOS %d: Wi-Fi and Battery wanted by its switch alone (what is drawn decides at run time, 12.1)", os);
    }
    MLSettings w = MLSettingsFrom(@{ @"enabled": @YES, @"clockStyle": @"ios", @"background": @"wallpaper", @"cards": @NO, @"showUser": @NO, @"statusPair": @NO }, 15);
    CHECK(!MLAnyPartWanted(&w), "every part at its iPadOS value: no part wanted (L25b)");
    MLSettings ipad17 = MLSettingsFrom(@{ @"enabled": @YES, @"clockStyle": @"ios", @"background": @"wallpaper" }, 17);
    CHECK(!MLPartWanted(&ipad17, kMLPartClock) && !MLPartWanted(&ipad17, kMLPartBackground), "17/18 with the iPadOS pick: no clock and no backdrop hooks (L25b)");
    MLSettings junk = MLSettingsFrom(@{ @"enabled": @"yes", @"clockStyle": @"weird", @"background": @7, @"cards": @"no" }, 18);
    CHECK(!junk.enabled && junk.clockStyle == kMLClockMac && junk.background == kMLBackWallpaper && junk.cards, "wrong types read as the defaults (18)");
    MLSettings junk16 = MLSettingsFrom(@{ @"background": @"weird" }, 16);
    CHECK(junk16.background == kMLBackBlurred && MLBackgroundFromString(nil, 15) == kMLBackBlurred && MLBackgroundFromString(nil, 17) == kMLBackWallpaper && MLBackgroundFromString(nil, 19) == kMLBackWallpaper,
          "a missing or unknown background reads as the version's default (15/16 Blurred, 17 and later Wallpaper)");
    CHECK(MLSettingsFrom(@{ @"enabled": @YES, @"background": @"blurred" }, 18).background == kMLBackBlurred, "a Blurred picked on 17/18 stays the user's pick (the empty-still guard keeps it from drawing black)");
    CHECK(MLClockStyleFromString(MLClockStyleString(kMLClockNone), 15) == kMLClockNone && MLBackgroundFromString(MLBackgroundString(kMLBackDesktop), 17) == kMLBackDesktop, "values round-trip");
    MLSettings named = MLSettingsFrom(@{ @"name": @"  Test Name \n" }, 16);
    CHECK(!strcmp(named.name, "Test Name"), "a typed name is trimmed");
    // ---- Blurred availability (2.4) ----
    CHECK(MLBlurredOffered(15, nil) && MLBlurredOffered(16, @{}), "Blurred offered on 15 / 16 until a version finds no still");
    CHECK(!MLBlurredOffered(17, nil) && !MLBlurredOffered(17, @{}) && !MLBlurredOffered(18, @{}) && !MLBlurredOffered(18, @{ @"stillRead": @NO }), "17 / 18: Blurred not offered until a real still was read (1.8.9 pass: the black backdrop)");
    CHECK(MLBlurredOffered(17, @{ @"stillRead": @YES }) && MLBlurredOffered(18, @{ @"stillRead": @YES }), "17 / 18: Blurred offered once a still with a picture in it was read");
    CHECK(!MLBlurredOffered(17, @{ @"noStill": @YES }) && !MLBlurredOffered(18, @{ @"noStill": @YES, @"stillRead": @YES }) && !MLBlurredOffered(16, @{ @"noStill": @YES }) && !MLBlurredOffered(19, @{ @"stillRead": @YES }),
          "no still on this iPadOS (or an untested one): Blurred not offered");
    CHECK(!MLBlurredOffered(18, @{ @"stillRead": @"yes" }) && !MLBlurredOffered(18, (id)@"x"), "junk in the state file: not offered on 17 / 18");
    // ---- the event machine (2.7): one case per sequence ----
    MLMachine m;
#define FRESH() memset(&m, 0, sizeof(m))
    FRESH(); MLOnLock(&m); MLOnScreenOff(&m); MLOnAppear(&m, 0); MLOnScreenOn(&m, 0);
    CHECK(m.lockFace, "lock: picture and name");
    FRESH(); MLOnAppear(&m, -1); CHECK(!m.lockFace, "an appearance with no lock and no iPadOS read: no picture and name"); MLOnScreenOff(&m); MLOnScreenOn(&m, -1);
    CHECK(m.lockFace, "wake (screen off -> on while the Cover Sheet is down): picture and name");
    FRESH(); MLOnAppear(&m, 1); CHECK(!m.lockFace, "pull while unlocked: no picture and name");
    MLOnLock(&m); CHECK(m.lockFace, "pull -> Lock (the Cover Sheet already down): picture and name");
    MLOnScreenOff(&m); MLOnScreenOn(&m, 1); CHECK(m.lockFace, "pull -> Lock -> wake (iPadOS still reads 1): picture and name (the lock seen while up)");
    FRESH(); MLOnAppear(&m, 1); MLOnLock(&m); MLOnScreenOff(&m); MLOnScreenOn(&m, 0); CHECK(m.lockFace, "pull -> Lock -> wake (iPadOS reads 0): picture and name");
    FRESH(); MLOnAppear(&m, 1); /* auto-dim: no screen-off event */ CHECK(!m.lockFace, "pull -> auto-dim -> touch: none (a dim is not a wake)");
    FRESH(); MLOnLock(&m); MLOnAppear(&m, 0); MLOnScreenOn(&m, 0); /* a swipe let go: no event */ CHECK(m.lockFace, "lock -> wake -> swipe let go: still shown");
    // rev 2 12.2 (3): a lock seen while the master was off never reaches a later pull; resets at every disappearance and master switch
    FRESH(); MLOnLock(&m); /* master off: no appearance consumes it */ MLOnGone(&m); /* unlock */ MLOnMasterSwitch(&m); /* switch on while unlocked: no appearance on a hidden Cover Sheet */
    MLOnAppear(&m, 1); CHECK(!m.lockFace, "lock while off -> unlock -> switch on while unlocked -> pull: no picture and name (18.5 10:52)");
    FRESH(); MLOnLock(&m); /* master off, the Lock Screen up */ MLOnMasterSwitch(&m); MLOnAppear(&m, 0); CHECK(m.lockFace, "lock while off -> switch on while locked: picture and name (iPadOS's read)");
    FRESH(); MLOnLock(&m); MLOnGone(&m); CHECK(!m.pendingLock, "a lock no appearance consumed is dropped when the Cover Sheet goes");
    FRESH(); MLOnLock(&m); MLOnMasterSwitch(&m); MLOnAppear(&m, -1); CHECK(!m.lockFace, "a lock before a master switch is dropped at it (with no iPadOS read: the machine alone)");
    FRESH(); MLOnLock(&m); MLOnAppear(&m, 0); MLOnMasterSwitch(&m); CHECK(!m.down && !m.lockFace, "a master switch while shown: the machine starts again");
    FRESH(); MLOnLock(&m); MLOnAppear(&m, 0); MLOnGone(&m); CHECK(!m.lockFace && !m.down, "unlock: reset");
    MLOnLock(&m); MLOnAppear(&m, 1); CHECK(m.lockFace, "unlock -> re-lock within a second: picture and name (the lock event wins over a stale read)");
    FRESH(); MLOnAppear(&m, 0); CHECK(m.lockFace, "the Lock Screen a respring shows (no lock event seen, iPadOS reads 0): picture and name");
    FRESH(); MLOnLock(&m); MLOnAppear(&m, 0); MLOnAppear(&m, 1); CHECK(m.lockFace, "a second appearance call while down changes nothing");
    FRESH(); MLOnLock(&m); MLOnAppear(&m, 0); /* poster switcher: the face goes; back = a fresh appearance */ m.down = NO; MLOnAppear(&m, 0);
    CHECK(m.lockFace, "poster switcher open -> close: shown again");
    FRESH(); MLOnScreenOff(&m); MLOnScreenOn(&m, 0); CHECK(!m.lockFace, "a wake with no Cover Sheet down: nothing");
    // ---- the poster switcher's bounded state (12.2 (2)) and the first appearance's face (12.2 (1)) ----
    MLSwitcherState sw = {0};
    MLSwitcherBegin(&sw); MLSwitcherRead(&sw, YES); CHECK(sw.pending, "switcher: pending from its prepare");
    CHECK(!MLFaceRetry(YES, YES, NO, NO, sw.pending, YES), "switcher: a layout pass during its zoom forms no face");
    MLSwitcherRead(&sw, NO); CHECK(!sw.pending && MLFaceRetry(YES, YES, NO, NO, sw.pending, YES), "switcher: iPadOS's read YES then NO ends it: the face comes back (Cancel)");
    memset(&sw, 0, sizeof(sw)); MLSwitcherBegin(&sw); MLSwitcherRead(&sw, YES); /* a Lock press: no cleanup */ MLSwitcherEnd(&sw); /* screen off */
    CHECK(!sw.pending && MLFaceRetry(YES, YES, NO, NO, sw.pending, YES), "switcher -> Lock -> wake: ended by the screen-off, the face at the wake (18.5 10:49)");
    memset(&sw, 0, sizeof(sw)); MLSwitcherBegin(&sw); MLSwitcherRead(&sw, NO); MLSwitcherRead(&sw, NO);
    CHECK(sw.pending, "switcher: a read that never went YES does not end it by itself");
    MLSwitcherCleanup(&sw, YES); CHECK(sw.pending, "switcher: a cleanup still presenting keeps it");
    MLSwitcherCleanup(&sw, NO); CHECK(!sw.pending, "switcher: the cleanup not presenting ends it");
    CHECK(MLFaceRetry(YES, YES, NO, NO, NO, YES) && !MLFaceRetry(YES, YES, NO, NO, NO, NO), "first appearance: no window at -viewWillAppear: -> none; the window at the first layout -> the face then");
    CHECK(!MLFaceRetry(NO, YES, NO, NO, NO, YES) && !MLFaceRetry(YES, NO, NO, NO, NO, YES) && !MLFaceRetry(YES, YES, YES, NO, NO, YES) && !MLFaceRetry(YES, YES, NO, YES, NO, YES),
          "no face try with the master off, outside an appearance, with the face up or during a dismissal");
    // ---- the name (2.5) ----
    CHECK([MLAutomaticName(@"Alex's iPad") isEqualToString:@"Alex"] && [MLAutomaticName(@"Alex\u2019s iPad") isEqualToString:@"Alex"], "\"'s iPad\" and \"\u2019s iPad\" go");
    CHECK([MLAutomaticName(@"iPad de Alex") isEqualToString:@"iPad de Alex"] && [MLAutomaticName(@"") isEqualToString:@"iPad"] && [MLAutomaticName(@"'s iPad") isEqualToString:@"'s iPad"], "no suffix: the whole name; empty: iPad");
    MLSettings typed = MLSettingsFrom(@{ @"name": @"Test User" }, 17);
    CHECK([MLShownName(&typed, @"X's iPad") isEqualToString:@"Test User"], "a typed name wins");
    CHECK([MLInitials(@"Test User") isEqualToString:@"TU"] && [MLInitials(@"single") isEqualToString:@"S"] && [MLInitials(@"a b c") isEqualToString:@"AB"] && [MLInitials(@"") isEqualToString:@"?"], "initials: up to two");
    CHECK([MLInitials(@"\u00e9mile zola") isEqualToString:@"\u00c9Z"], "initials of accented names");
    // ---- the time format (A6): no day period ----
    CHECK([MLTimeFormat(@"h:mm a") isEqualToString:@"h:mm"] && [MLTimeFormat(@"HH:mm") isEqualToString:@"HH:mm"] && [MLTimeFormat(@"a h:mm") isEqualToString:@"h:mm"], "AM/PM dropped, 24 h kept");
    CHECK([MLTimeFormat(@"h:mm B") isEqualToString:@"h:mm"] && [MLTimeFormat(@"h'h'mm a") isEqualToString:@"h'h'mm"], "day periods (B) dropped; quoted text kept");
    for (NSString *loc in @[ @"en_US", @"en_GB", @"tr_TR", @"es_ES", @"ja_JP", @"ko_KR", @"zh_CN", @"ar_EG", @"de_DE" ]) {
        NSString *f = MLTimeFormat([NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:[NSLocale localeWithLocaleIdentifier:loc]]);
        NSDateFormatter *df = [NSDateFormatter new]; df.locale = [NSLocale localeWithLocaleIdentifier:loc]; df.dateFormat = f;
        NSString *out = [df stringFromDate:[NSDate dateWithTimeIntervalSince1970:1795564800 + 15 * 3600]];
        CHECK(out.length >= 4 && [out rangeOfString:@"PM"].location == NSNotFound && [out rangeOfString:@"AM"].location == NSNotFound, "%s: the lock clock shows no AM/PM (%s)", loc.UTF8String, out.UTF8String);
    }
    // ---- the Mac clock (12.4, 12.5): the four iPads' screens x 2 orientations x 3 Menu Bar Sizes ----
    CGSize screens[] = { {768, 1024}, {1024, 1366}, {834, 1194}, {1024, 1366} };   // (16.7.7 9.7", 17.5.1 12.9", 15.6.1 11", 18.5 12.9")
    const char *names[] = { "16.7.7", "17.5.1", "15.6.1", "18.5" };
    // (the measured macOS reference, 12.4a, with KT's Q28 answer: date 0.028 S, time 0.15 S)
    CGFloat targetDate[] = { 22, 29, 23, 29 }, targetTime[] = { 115, 154, 125, 154 };
    MLFontMetrics sf = { 0, 0, 0 };   // (SF's metrics: MLFontMetricsOr)
    MLFontMetrics fm = MLFontMetricsOr(sf);
    for (int i = 0; i < 4; i++) for (int o = 0; o < 2; o++) for (int bar = 0; bar < 3; bar++) {
        CGSize S = o ? CGSizeMake(screens[i].height, screens[i].width) : screens[i];
        CGFloat sh = MIN(S.width, S.height), barH = 24 + 6 * bar;
        // a roomy zone: the 12.4 targets exactly, the same in both orientations
        MLMacClock c = MLMacClockLayout(sh, S.width, barH + 8, 600, 0, 2.4, 9.5, YES, sf, sf);
        CHECK(c.dateSize == targetDate[i] && c.timeSize == targetTime[i] && c.fits, "%s o%d bar%d: the Mac clock at macOS's proportions, the time a bit larger (date %.0f / time %.0f, targets %.0f / %.0f)", names[i], o, bar, c.dateSize, c.timeSize, targetDate[i], targetTime[i]);
        CGFloat dateCapTop = c.top + c.dateSize * (fm.asc - fm.cap), dateBase = c.top + c.dateSize * fm.asc, timeCapTop = c.timeTop + c.timeSize * (fm.asc - fm.cap);
        CHECK(fabs(dateCapTop - 0.097 * sh) < 0.6 || (c.top == barH + 8 && dateCapTop > 0.097 * sh), "%s o%d bar%d: the date's cap top 0.097 S from the top (%.1f), or under the bar", names[i], o, bar, dateCapTop);
        CHECK(fabs(timeCapTop - dateBase - 0.027 * sh) < 0.6, "%s o%d bar%d: the time's cap top 0.027 S under the date's baseline (%.1f)", names[i], o, bar, timeCapTop - dateBase);
        CHECK(c.dateH == ceil(c.dateSize * fm.line) && c.timeH == ceil(c.timeSize * fm.line) && c.gap == c.timeTop - (c.top + c.dateH), "%s: each line one line tall, the gap from the date's frame to the time's", names[i]);
        CHECK(fabs((c.left + c.right) / 2 - S.width / 2) < 0.01 && c.left >= 24, "%s o%d: centred on the screen, 24 pt from its sides", names[i], o);
        // a tight zone: shrunk evenly, never past its bottom
        CGFloat zone = c.top + 120;
        MLMacClock t = MLMacClockLayout(sh, S.width, barH + 8, zone, 0, 2.4, 9.5, YES, sf, sf);
        CHECK(t.top + t.dateH + t.gap + t.timeH <= zone + 0.5 && t.timeTop + t.timeH <= zone + 0.5 && t.scale < 1 && fabs(t.dateSize / MAX(t.timeSize, 1) - c.dateSize / c.timeSize) < 0.03, "%s o%d bar%d: a tight zone shrinks both evenly and stays inside (%.2f)", names[i], o, bar, t.scale);
        // a date-line widget: the time only
        MLMacClock wonly = MLMacClockLayout(sh, S.width, barH + 8, 600, 0, 2.4, 9.5, NO, sf, sf);
        CHECK(wonly.dateSize == 0 && wonly.dateH == 0 && wonly.timeSize == targetTime[i], "%s: a date line carrying a widget: our time only", names[i]);
        // the 17/18 landscape widget column (x 44, 165 wide): clear of it, centred
        if (o) { MLMacClock col = MLMacClockLayout(sh, S.width, barH + 8, 600, 44 + 165, 4.2, 12, YES, sf, sf); CHECK(col.left >= 44 + 165 + 8 - 0.01, "%s landscape: clear of the widget column", names[i]); }
        // 17/18: a date line iPadOS keeps (a widget in it) sits above the time: our time alone starts under it (review finding 1; 18.5's
        // B0 frames: date line y 72-108, time view y 110-245, the side column's right edge 209)
        CGFloat keptBottom = 108, top17 = MLClockKeptTop(barH + 8, keptBottom, sh);
        MLMacClock kw = MLMacClockLayout(sh, S.width, top17, 245, o ? 209 : 0, 2.4, 9.5, NO, sf, sf);
        CHECK(kw.top >= keptBottom + 2 && kw.timeTop == kw.top && (!kw.fits || kw.timeTop + kw.timeH <= 245.5), "%s o%d bar%d: with a date-line widget kept, our time starts under it (%.0f) and stays in the zone", names[i], o, bar, kw.top);
        CHECK(MLClockKeptTop(barH + 8, 0, sh) == barH + 8, "%s: no kept line: the top unchanged", names[i]);
        // the padlock's drawn bottom moves the top down
        MLMacClock pl = MLMacClockLayout(sh, S.width, 150, 600, 0, 2.4, 9.5, YES, sf, sf);
        CHECK(pl.top == 150, "%s: under the padlock's drawn bottom + 8", names[i]);
        CHECK(MLClockTopLimit(70, 6, barH) == MAX(76, barH), "the padlock's drawn bottom includes our Menu Bar Size shift");
        // ---- the macOS user block (12.4, 12.6) ----
        CGFloat side = MLPictureSide(S), nsz = MLNameSize(S), nameH = MLNameLineH(nsz), ngap = MLNameGap(S);
        CGFloat wantSide = round(MAX(72, MIN(112, 0.09 * sh))), wantName = round(0.018 * sh);
        CHECK(side == wantSide && nsz == wantName && ngap == round(0.019 * sh), "%s o%d: the picture %.0f pt (the large size, 0.09 S 72-112), the name %.0f pt 0.018 S, %.0f pt under the picture (0.019 S)", names[i], o, side, nsz, ngap);
        // the hint: a plain line (12.4a: macOS at rest, KT's Q28), as wide as its words, one line tall
        CGFloat hsz = MLHintSize(S), hH = MLHintLineH(hsz);
        CHECK(hsz == MAX(12, round(0.012 * sh)) && hH == ceil(hsz * 1.25) && MLHintLineWidth(120.3) == 123 && MLHintLineWidth(0) == 2, "%s: the hint line %.0f pt (0.012 S, at least 12), as wide as its words", names[i], hsz);
        CGFloat fw = MLHintLineWidth(120);
        CGRect slot = CGRectMake(S.width / 2 - 75, S.height - 62, 150, 20);
        CGRect fr = MLHintRect(slot, S.width, fw, hH, 0, 0);
        CHECK(fabs(CGRectGetMidY(fr) - CGRectGetMidY(slot)) < 0.6 && fabs(CGRectGetMidX(fr) - S.width / 2) < 0.6 && fr.size.height == hH, "%s o%d: the hint line centred on iPadOS's hint slot, one line tall", names[i], o);
        CGRect slot18 = CGRectMake(S.width / 2 - 75, S.height - 31.5, 150, 20.5);   // (18.5: the teachable slot over the home bar at y H - 13)
        CGRect fr18 = MLHintRect(slot18, S.width, fw, hH, 0, S.height - 13);
        CHECK(CGRectGetMaxY(fr18) <= S.height - 13 - 4 + 0.01, "%s o%d: the hint line never over iPadOS's home affordance", names[i], o);
        CGRect frNone = MLHintRect(CGRectZero, S.width, fw, hH, S.height - 40, 0);
        CHECK(CGRectGetMaxY(frNone) == S.height - 40, "%s: no hint slot: the line's bottom at the fallback line", names[i]);
        CGFloat hgap = MLHintGap(S, nameH, hH);
        CHECK(hgap >= 6 && (hgap == 6 || fabs(nameH / 2 + hgap + hH / 2 - 0.033 * sh) < 0.6), "%s: the name's centre 0.033 S above the line's (gap %.0f)", names[i], hgap);
        CGFloat bottom = CGRectGetMinY(fr) - hgap;
        CHECK(MLUserMode(bottom, 0, side, 0, nameH, ngap) == kMLUserWhole, "%s o%d: no list: the whole block", names[i], o);
        CHECK(MLUserMode(bottom, bottom - (56 + 8 + nameH + 20), side, 0, nameH, ngap) == kMLUserSmall, "%s: a list near the block: the small picture", names[i]);
        CHECK(MLUserMode(bottom, bottom - (nameH + 20), side, 0, nameH, ngap) == kMLUserNameOnly, "%s: closer: the name only", names[i]);
        CHECK(MLUserMode(bottom, bottom - 10, side, 0, nameH, ngap) == kMLUserHidden, "%s: cards at the block: the picture and name hidden, never over a card", names[i]);
        CHECK(!MLFieldYields(fr, bottom - 10) && MLFieldYields(fr, CGRectGetMinY(fr) - 4) && !MLFieldYields(fr, 0), "%s: the field yields last: only when list content comes within 8 pt of it", names[i]);
        // never over a widget: the 17/18 landscape side column (x 44, 165 pt wide) and the inline row under the clock
        CGRect widgets[2] = { CGRectMake(44, 72, 165, 880), CGRectMake(S.width / 2 - 187, 300, 374, 75) };
        int mode = MLUserModeClear(S.width, bottom, kMLUserWhole, side, 120, nameH, ngap, widgets, 2);
        CGFloat h = MLUserHeight(mode, side, nameH, ngap), wdt = MAX(side, 120);
        CGRect block = CGRectMake(round((S.width - wdt) / 2), bottom - h, wdt, h);
        CHECK(mode == kMLUserHidden || !MLRectMeetsAny(block, widgets, 2), "%s o%d: the block clear of every widget", names[i], o);
        CGRect over[1] = { CGRectMake(0, bottom - 200, S.width, 200) };
        CHECK(MLUserModeClear(S.width, bottom, kMLUserWhole, side, 120, nameH, ngap, over, 1) == kMLUserHidden, "%s: a widget across the block's place: hidden, never moved over it", names[i]);
        // the pair, top right, never over a widget
        CGRect pr = MLPairFrame(S.width, barH, CGSizeMake(56, 20), NULL, 0);
        CHECK(fabs(CGRectGetMaxX(pr) - (S.width - 12)) < 0.01 && pr.origin.y >= 0 && CGRectGetMaxY(pr) <= MAX(barH, 24), "%s o%d bar%d: the pair at the top right", names[i], o, bar);
        CGRect tr[1] = { CGRectMake(S.width - 100, 0, 100, 40) };
        CHECK(CGRectIsEmpty(MLPairFrame(S.width, barH, CGSizeMake(56, 20), tr, 1)), "%s: a widget there: no pair", names[i]);
        CGRect wr, br; MLPairPlaces(CGSizeMake(17, 20), CGSizeMake(29, 20), &wr, &br);
        CHECK(CGSizeEqualToSize(MLPairSize(CGSizeMake(17, 20), CGSizeMake(29, 20)), CGSizeMake(56, 20)) && CGRectGetMinX(wr) == CGRectGetMaxX(br) + 10 && br.origin.x == 0 && CGRectGetMaxX(wr) == 56,
              "%s: macOS's order: Wi-Fi rightmost, the battery to its left (12.4a)", names[i]);
        // the backdrop's size, and the still's crop (12.2 (4)): an aspect fill, centred, never stretched
        CGSize px = MLBackdropPixels(S);
        CHECK(MAX(px.width, px.height) == 256 && ((px.width >= px.height) == (S.width >= S.height)), "%s o%d: 256 px on the long side, the screen's aspect", names[i], o);
        CGSize stills[2] = { {366, 488}, {488, 366} };
        for (int k = 0; k < 2; k++) {
            CGRect r = MLAspectFillRect(stills[k], px);
            CGFloat kx = r.size.width / stills[k].width, ky = r.size.height / stills[k].height;
            CHECK(r.size.width >= px.width - 0.01 && r.size.height >= px.height - 0.01 && fabs(kx / ky - 1) < 0.005 && fabs(CGRectGetMidX(r) - px.width / 2) < 0.01 && fabs(CGRectGetMidY(r) - px.height / 2) < 0.01,
                  "%s o%d: a %.0f x %.0f still fills, centred, aspect kept (x%.3f / x%.3f)", names[i], o, stills[k].width, stills[k].height, kx, ky);
        }
    }
    // EXPECTED values for L33 (12.5): the Mac clock at each iPad's targets in a roomy zone; the device build logs its own (debug dump "EXPECTED
    // for L33") from its zone reads, and 15.6.1's (the date view 147 pt tall at the top) shrinks
    for (int i = 0; i < 4; i++) {
        CGFloat sh = MIN(screens[i].width, screens[i].height);
        MLMacClock c = MLMacClockLayout(sh, screens[i].width, 0, 0, 0, 2.4, 9.5, YES, sf, sf);
        printf("EXPECTED %-6s S %4.0f: date %2.0f pt Medium (cap top %.0f), time %3.0f pt Semibold -0.03 em (cap top %.0f, %.0f under the date's baseline); picture %.0f, name %.0f (%.0f under it), hint line %.0f pt, white %.2f\n",
               names[i], sh, c.dateSize, c.top + c.dateSize * (fm.asc - fm.cap), c.timeSize, c.timeTop + c.timeSize * (fm.asc - fm.cap), c.timeTop + c.timeSize * (fm.asc - fm.cap) - (c.top + c.dateSize * fm.asc),
               MLPictureSide(screens[i]), MLNameSize(screens[i]), MLNameGap(screens[i]), MLHintSize(screens[i]), kMLClockWhiteAlpha);
    }
    MLMacClock m1 = MLMacClockLayout(834, 834, 0, 147 + 30, 0, 2.4, 9.5, YES, sf, sf);
    printf("EXPECTED 15.6.1 (zone bottom %.0f): date %.0f, time %.0f (scale %.2f)\n", 147.0 + 30, m1.dateSize, m1.timeSize, m1.scale);
    CHECK(m1.fits && m1.scale < 1, "15.6.1's zone shrinks the clock and it stays inside");
    CHECK(!MLMacClockLayout(834, 834, 100, 120, 0, 2.4, 9.5, YES, sf, sf).fits, "no room in the zone: no Mac clock (iPadOS's stays)");
    CHECK(kMLClockWhiteAlpha == 0.80 && MLMacTimeKern(154) == -0.03 * 154, "the clock white 0.80 over our backdrop, the time tracked -0.03 em (12.4a)");
    CHECK(fabs(MLMacTimeWidth1(2.40, 5) - (2.40 - 0.03 * 4)) < 1e-9 && MLMacTimeWidth1(0.6, 1) == 0.6 && MLMacTimeWidth1(0, 0) == 0, "the tracking between the glyphs only (none after the last: the time stays centred)");
    // the stored key names the still's size; a still of another shape is a new picture
    NSString *key = MLBackdropKey(@"poster A 3", YES, NO, NO);
    CHECK(MLBackdropKeyMatches(MLBackdropStoredKey(key, CGSizeMake(366, 488)), key) && MLBackdropKeyMatches(key, key) && !MLBackdropKeyMatches(MLBackdropStoredKey(MLBackdropKey(@"poster B 1", YES, NO, NO), CGSizeMake(366, 488)), key),
          "the stored key: the source's key plus the still's size");
    // the hint pick, the field's look, the glyph (12.6)
    MLHintFacts hf[3] = { { YES, 0.0, YES }, { YES, 1.0, YES }, { YES, 1.0, YES } };
    CHECK(MLHintPick(hf, 3) == 1, "the hint mirrored: the first DRAWN one (18.5: the teachable label at alpha 0 skipped)");
    MLHintFacts hf2[3] = { { YES, 0.0, YES }, { YES, 0.0, YES }, { YES, 0.9, YES } };
    CHECK(MLHintPick(hf2, 3) == 2, "18.5 Face ID: the line by the padlock");
    MLHintFacts hf3[3] = { { YES, 1.0, NO }, { NO, 1.0, YES }, { YES, 0.0, YES } };
    CHECK(MLHintPick(hf3, 3) == -1, "no drawn hint with words: no field");
    MLTextLook ha = MLHintLookFor(YES, NO, 2), hb = MLHintLookFor(YES, YES, 1), hc = MLHintLookFor(NO, NO, 2), hd = MLHintLookFor(NO, NO, 1);
    CHECK(ha.white == 1 && ha.alpha == 0.80 && ha.shadowAlpha == 0 && hb.alpha == 0.92 && hc.white == 0 && hc.shadowWhite == 1 && hd.white == 1 && hd.shadowAlpha > 0,
          "the hint line: white 0.80 over our backdrop (0.92 with Increase Contrast), plain text; over a sharp wallpaper the slot's legibility (dark over a light one)");
    // the depth effect (12.7)
    CHECK(MLDepthStandsDown(YES, YES, YES) && !MLDepthStandsDown(YES, YES, NO) && !MLDepthStandsDown(YES, NO, NO) && !MLDepthStandsDown(NO, YES, YES),
          "a depth subject still drawn over our backdrop stands it down; hidden, absent or no backdrop: nothing");
    CHECK(MLUserBottom(1024, 0, 0, 0, 0) == 960 && MLUserBottom(1024, 0, 1000, 0, 0) == 988 && MLUserBottom(1024, 980, 0, 900, 0) == 888, "no line: the home affordance, else 64 pt; above the status text");
    // ---- legibility (2.6) ----
    MLTextLook a = MLTextLookFor(YES, 2), b = MLTextLookFor(NO, 1), c = MLTextLookFor(NO, 2);
    CHECK(a.white == 1 && a.shadowAlpha == 0, "over our darkened backdrop: white, no shadow");
    CHECK(b.white == 1 && b.shadowWhite == 0 && b.shadowAlpha > 0, "over iPadOS's wallpaper, light content: white with a dark shadow");
    CHECK(c.white == 0 && c.shadowWhite == 1, "over a light wallpaper (dark content): dark text with a light shadow");
    // ---- the backdrop (2.4) ----
    NSString *k1 = MLBackdropKey(@"poster A 3", YES, NO, NO), *k2 = MLBackdropKey(@"poster A 3", NO, NO, NO), *k3 = MLBackdropKey(@"poster A 3", YES, YES, NO), *k4 = MLBackdropKey(@"poster A 3", YES, NO, YES);
    CHECK(k1 && ![k1 isEqual:k2] && ![k1 isEqual:k3] && ![k1 isEqual:k4] && [k1 isEqual:MLBackdropKey(@"poster A 3", YES, NO, NO)], "the key: source, orientation, appearance, Increase Contrast");
    CHECK(MLBackdropKey(nil, YES, NO, NO) == nil && MLBackdropKey(@"", NO, NO, NO) == nil, "no source identity: no key (nothing cached)");
    CHECK([k1 hasPrefix:@"v2 "] && !MLBackdropKeyMatches(@"v1 poster A 3 L l - still 366x488", k1) && !MLBackdropKeyMatches(@"v1 poster A 3 L l -", k1),
          "a picture stored before the empty-still guard (key v1: the fix round's black ones) never matches again (1.8.9 pass: the black backdrop)");
    // ---- the empty-still guard (the black backdrop, option b): a still with no picture in it is never stored or drawn ----
    {
        size_t W = 32, H = 24, rb = W * 4 + 16;   // (a row with padding, as CoreGraphics may give)
        uint8_t *buf = calloc(H, rb);
        CHECK(MLStillEmpty(buf, W, H, rb), "all zero (a clear still in the opaque context, or a black one): empty");
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) { uint8_t *p = buf + y * rb + x * 4; p[0] = (x + y) % 4; p[1] = (x * 3 + y) % 4; p[2] = y % 4; p[3] = 255; }
        CHECK(MLStillEmpty(buf, W, H, rb), "black with a decoder's rounding (every colour byte 3 or less, the unused byte set): empty");
        buf[(H - 1) * rb + (W - 1) * 4 + 2] = 4;
        CHECK(!MLStillEmpty(buf, W, H, rb), "one pixel with a little red in it (the last pixel of the last row): not empty");
        memset(buf, 0, H * rb); buf[5 * rb + 7 * 4 + 0] = 200;
        CHECK(!MLStillEmpty(buf, W, H, rb), "a single blue pixel: not empty");
        memset(buf, 0, H * rb); for (size_t y = 0; y < H; y++) buf[y * rb + W * 4 + 3] = 255;   // (bytes past the row's pixels: padding, never read)
        CHECK(MLStillEmpty(buf, W, H, rb), "only the row padding set: still empty (the padding is not the picture)");
        for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) { uint8_t *p = buf + y * rb + x * 4; p[0] = 6 + x; p[1] = 8 + y; p[2] = 10; }
        CHECK(!MLStillEmpty(buf, W, H, rb), "a very dark wallpaper with a picture in it: not empty (it is blurred and drawn)");
        CHECK(MLStillEmpty(NULL, W, H, rb) && MLStillEmpty(buf, 0, H, rb) && MLStillEmpty(buf, W, 0, rb) && MLStillEmpty(buf, W, H, W * 4 - 1), "no buffer, no size or a short row: empty (nothing drawn)");
        free(buf);
        // the stills as MLBlurred draws them: an opaque 32-bit context zeroed first (kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little)
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        uint8_t (^drawn)(CGFloat, CGFloat, CGFloat, CGFloat, BOOL *) = ^uint8_t(CGFloat r, CGFloat g, CGFloat bl, CGFloat a, BOOL *emptyOut) {
            CGContextRef sc = CGBitmapContextCreate(NULL, 61, 81, 8, 61 * 4, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGContextClearRect(sc, CGRectMake(0, 0, 61, 81));
            CGContextSetRGBFillColor(sc, r, g, bl, a); CGContextFillRect(sc, CGRectMake(0, 0, 61, 81));
            CGImageRef still = CGBitmapContextCreateImage(sc); CGContextRelease(sc);
            size_t w = 26, h = 19;
            CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
            memset(CGBitmapContextGetData(ctx), 0, h * CGBitmapContextGetBytesPerRow(ctx));
            CGContextDrawImage(ctx, MLAspectFillRect(CGSizeMake(61, 81), CGSizeMake(w, h)), still);
            *emptyOut = MLStillEmpty(CGBitmapContextGetData(ctx), w, h, CGBitmapContextGetBytesPerRow(ctx));
            uint8_t mid = ((uint8_t *)CGBitmapContextGetData(ctx))[(h / 2) * CGBitmapContextGetBytesPerRow(ctx) + (w / 2) * 4 + 2];
            CGContextRelease(ctx); CGImageRelease(still);
            return mid;
        };
        BOOL e1 = NO, e2 = NO, e3 = NO, e4 = NO;
        drawn(1, 1, 1, 0, &e1); drawn(0, 0, 0, 1, &e2); uint8_t red = drawn(0.6, 0.1, 0.1, 1, &e3); drawn(0.08, 0.08, 0.1, 1, &e4);
        CGColorSpaceRelease(cs);
        CHECK(e1, "a fully clear still (white at alpha 0), drawn as MLBlurred draws it: empty");
        CHECK(e2, "an all-black still (the fix round: 17.5.1's and 18.5's poster thumbnails), drawn as MLBlurred draws it: empty");
        CHECK(!e3 && red > 100, "a real still drawn the same way: not empty (its red byte at the centre %u)", red);
        CHECK(!e4, "a very dark real still drawn the same way: not empty");
    }
    CHECK(fabs(MLBackdropDim(0.96, NO) - 0.5) < 1e-9 && fabs(MLBackdropDim(0.72, YES) - 0.5) < 1e-9 && MLBackdropDim(0.2, NO) == 0.9 && MLBackdropDim(0.0, NO) == 0.9, "darkened to 0.48 (0.36 with Increase Contrast), never brightened past 0.9");
    // ---- the visibility of the picture and name (2.6) ----
    MLModal none = {0};
    CHECK(MLUserVisible(YES, none) && !MLUserVisible(NO, none), "shown only with the lock face");
    MLModal mods[5] = { { .passcode = YES }, { .today = YES }, { .posterSwitcher = YES }, { .modal = YES }, { .mainPageHidden = YES } };
    for (int i = 0; i < 5; i++) CHECK(!MLUserVisible(YES, mods[i]), "hidden under modal piece %d (passcode, Today, switcher, alarm/call/Siri, camera)", i);
    // ---- the state file (3.4 5) ----
    int why[kMLPartCount] = { kMLWhyNone, kMLWhyMethod, kMLWhyNone, kMLWhyView, kMLWhyNone };
    NSDictionary *st = MLStateDict(why, YES, YES);
    CHECK(MLStateHandled(st, kMLPartBackground) && MLStateHandled(st, kMLPartUser) && !MLStateHandled(st, kMLPartClock) && [st[@"noStill"] boolValue] && [st[@"stillRead"] boolValue], "the state file: handled parts, noStill and stillRead");
    int none0[kMLPartCount] = {0};
    CHECK(MLBlurredOffered(18, MLStateDict(none0, NO, YES)) && !MLBlurredOffered(18, MLStateDict(none0, NO, NO)) && MLStateDict(none0, NO, NO)[@"stillRead"] == nil,
          "SpringBoard's state file round-trips to Settings' offer on 18 (stillRead written only once a still was read)");
    NSData *pl = [NSPropertyListSerialization dataWithPropertyList:st format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    NSString *txt = [[NSString alloc] initWithData:[NSPropertyListSerialization dataWithPropertyList:st format:NSPropertyListXMLFormat_v1_0 options:0 error:nil] encoding:NSUTF8StringEncoding];
    CHECK(pl.length && [txt rangeOfString:@".dylib"].location == NSNotFound && [txt rangeOfString:@"Lynx"].location == NSNotFound, "the state file holds part labels only, no file or tweak name");
    int none5[kMLPartCount] = {0};
    CHECK([MLStateDict(none5, NO, NO) count] == 0 && !MLStateHandled(@{}, 0) && !MLStateHandled(nil, 0) && !MLStateHandled((id)@"x", 0), "nothing handled: an empty file; junk reads as nothing");
    // ---- the 17/18 poster's identity (1.8.9 pass: the black backdrop): the routes 17.5.1 and 18.5 answer, typed, a new source when the poster or its version changes ----
    NSUUID *pa = [[NSUUID alloc] initWithUUIDString:@"6F0C2B1E-1111-4A2B-9C3D-000000000001"], *pb = [[NSUUID alloc] initWithUUIDString:@"6F0C2B1E-2222-4A2B-9C3D-000000000002"];
    TPosterConfig18 *c18 = TConfig(pa, 1, 0);
    CHECK(![c18 respondsToSelector:NSSelectorFromString(@"posterUUID")], "the 17.5.1 / 18.5 stand-in has no -posterUUID (as the IPSWs show)");
    NSString *src1 = MLPosterSource(c18);
    CHECK([src1 isEqualToString:@"poster 6F0C2B1E-1111-4A2B-9C3D-000000000001 1 0"], "17.5.1 / 18.5: a source identity from -serverUUID and the path's identity's version (%s)", src1.UTF8String ?: "nil");
    CHECK(MLBackdropKey(src1, YES, NO, NO) != nil, "17.5.1 / 18.5: a backdrop key at the appearance (Blurred draws)");
    CHECK([MLPosterSource(TConfig(pa, 1, 0)) isEqualToString:src1], "the same poster and version: the same source (the stored picture is reused)");
    CHECK(![MLPosterSource(TConfig(pa, 2, 0)) isEqualToString:src1], "the poster's version changed: a new source (a new picture)");
    CHECK(![MLPosterSource(TConfig(pb, 1, 0)) isEqualToString:src1], "another poster: a new source");
    CHECK(![MLPosterSource(TConfig(pa, 1, 1)) isEqualToString:src1], "the supplement changed: a new source");
    TPosterIdentity *iv = [TPosterIdentity new]; iv.posterUUID = pb; iv.version = 4;
    TPosterPath *pv = [TPosterPath new]; pv.serverIdentity = iv;
    NSString *srcIvar = MLPosterSource([[TPosterConfigIvarOnly alloc] initWithPath:pv]);
    CHECK([srcIvar isEqualToString:@"poster 6F0C2B1E-2222-4A2B-9C3D-000000000002 4 0"], "the path by its ivar alone: the identity's UUID and version (%s)", srcIvar.UTF8String ?: "nil");
    CHECK(MLPosterSource([[TPosterConfigIvarOnly alloc] initWithPath:nil]) == nil && MLPosterSource(nil) == nil, "no route answers: no source (no key, nothing cached)");
    CHECK(MLPosterSource([TPosterConfigOdd new]) == nil, "routes with other types are not read (no source, no exception)");
    TPosterConfigOld *old = [TPosterConfigOld new]; old.posterUUID = pa;
    CHECK([MLPosterSource(old) isEqualToString:@"poster 6F0C2B1E-1111-4A2B-9C3D-000000000001 - -"], "a configuration with -posterUUID itself still gives its source");
    // ---- what draws iPadOS's clock (1.8.9 pass: two clocks on 16): the prominent display wherever it is there (16-18), the date view's labels without it (15) ----
    CHECK(MLClockPathOf(Nil, Nil, [TDateView class]) == kMLClockPathDate, "15.6.1 (no prominent display): the date view's labels (MLClock15)");
    CHECK(MLClockPathOf([TProminent class], [TTimeView class], [TDateView class]) == kMLClockPathProminent, "16.7.7, 17.5.1, 18.5 (the prominent display beside the date view): the prominent display (MLClock17)");
    CHECK(MLClockPathOf([TProminentNoTime class], [TTimeView class], [TDateView class]) == kMLClockPathNone && MLClockPathOf([TProminent class], Nil, [TDateView class]) == kMLClockPathNone,
          "the prominent display without the shape ours draws with: iPadOS's clock stays (never the undrawn date view's labels)");
    CHECK(MLClockPathOf(Nil, Nil, [NSObject class]) == kMLClockPathNone && MLClockPathOf(Nil, Nil, Nil) == kMLClockPathNone, "neither: iPadOS's clock stays");
    {   // (the classes per version, as Apple's IPSWs show them: tools/hooktypes-ipados.txt)
        NSString *ht = [NSString stringWithContentsOfFile:@"hooktypes-ipados.txt" encoding:NSUTF8StringEncoding error:nil];
        NSDictionary *want = @{ @"15.6.1": @(kMLClockPathDate), @"16.7.7": @(kMLClockPathProminent), @"17.5.1": @(kMLClockPathProminent), @"18.5": @(kMLClockPathProminent) };
        for (NSString *v in want) {
            BOOL prom = [ht containsString:[v stringByAppendingString:@"\t-[CSProminentDisplayView layoutSubviews]"]] && [ht containsString:[v stringByAppendingString:@"\t-[CSProminentTimeView setDate:]"]];
            BOOL date = [ht containsString:[v stringByAppendingString:@"\t-[SBFLockScreenDateView _updateLabelAlpha]"]] && [ht containsString:[v stringByAppendingString:@"\t-[SBFLockScreenDateView setCustomSubtitleView:]"]];
            int got = MLClockPathOf(prom ? [TProminent class] : Nil, prom ? [TTimeView class] : Nil, date ? [TDateView class] : Nil);
            CHECK(ht && got == [want[v] intValue], "iPadOS %s's classes: the clock drawn by %s", v.UTF8String, got == kMLClockPathProminent ? "the prominent display" : got == kMLClockPathDate ? "the date view" : "nothing");
        }
    }
    printf("test-maclockscreen: %d passed, %d failed\n", gPass, gFail);
    return gFail ? 1 : 0;
} }
