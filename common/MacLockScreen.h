// MacLockScreen.h -- Mac Lock Screen (F49, 1.8.9; plans/design-mac-lock-screen.md rev 1 and rev 2, section 12): the plain rules SpringBoard's payload
// (macsettings/MacLockScreen.x) and Settings (statusbar/macstatusbarprefs/MSBMacLockScreenController.m) share, Mac-tested by
// tools/test-maclockscreen.sh. Foundation only (no UIKit): CGRect / CGFloat math, the event machine, the settings and their per-version
// defaults, the backdrop's key, the name rule, the card look's record/restore rule.
//
// The feature in one line: a full macOS lock screen over the iPad's own Lock Screen by default (rev 2, KT 25 Nov ~11:45: "it doesn't look or feel
// like a serious feature"), in five parts, each its own setting (Clock Style, Background, Mac-Style Cards, Picture and Name, Wi-Fi and Battery)
// so any part can go back to iPadOS's own; master switch off by default; widgets never hidden. A part at its iPadOS value installs no hook.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <string.h>
#include "MacLockCoexist.h"   // (the parts, the state file)

#define MLS_DOMAIN "com.besiktasliseba.maclockscreen"
#define MLS_NOTIFY "com.besiktasliseba.maclockscreen/prefsChanged"
#define MLS_STATE_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-LockParts.plist"
#define MLS_BACKDROP_FILE_FMT "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-LockBackdrop-%c.png"   // (L / P)
#define MLS_BACKDROP_KEY_FMT "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-LockBackdrop-%c.key"
#define MLS_PICTURE_FILE "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-LockPicture.png"

// ---- the settings (3.1). Absent = default: no migration; an updater gets the feature off. ----
enum { kMLClockMac = 0, kMLClockIPadOS = 1, kMLClockNone = 2 };
enum { kMLBackWallpaper = 0, kMLBackBlurred = 1, kMLBackDesktop = 2 };
enum { kMLPictureInitials = 0, kMLPictureFile = 1 };   // ("Use My Card" stores its photo as the picture file: kMLPictureFile, with cardName)
typedef struct {
    BOOL enabled;          // the master switch (absent: off)
    int clockStyle;        // kMLClock*
    int background;        // kMLBack*
    BOOL cards, showUser, statusPair;   // (absent: on)
    int picture;
    char name[128];        // typed name (empty: automatic)
} MLSettings;

// The defaults when the master is turned on (rev 2, 12.3 / 12.8; KT 25 Nov ~11:45 overrides rev 1's 17/18 "own clock and poster kept"): the Mac
// clock on every iPadOS; the blurred wallpaper on 15 and 16, the wallpaper as iPadOS draws it on 17 and later (1.8.9 pass: the black backdrop, KT 25 Nov ~22:15
// "Ship: sharp wallpaper on 17/18": the still 17.5.1 and 18.5 hand us for their posters is black in every pixel, so a Blurred default drew a black
// Lock Screen; the design's own fallback, 12.7). Blurred shows only where a still is readable (MLBlurredOffered; Settings offers Wallpaper only
// otherwise and SpringBoard draws Wallpaper), and on 17/18 a depth poster's subject is hidden through SpringBoard's own call while it shows; where
// that hide is seen not to work at run time the backdrop stands down for that appearance (MLDepthStandsDown). No new key: nothing was published
// with the rev 1 or rev 2 defaults.
static inline int MLDefaultClockStyle(int osMajor) { (void)osMajor; return kMLClockMac; }
static inline int MLDefaultBackground(int osMajor) { return osMajor >= 17 ? kMLBackWallpaper : kMLBackBlurred; }
static inline int MLClockStyleFromString(NSString *s, int osMajor) {
    if (![s isKindOfClass:[NSString class]]) return MLDefaultClockStyle(osMajor);
    if ([s isEqualToString:@"mac"]) return kMLClockMac;
    if ([s isEqualToString:@"ios"]) return kMLClockIPadOS;
    if ([s isEqualToString:@"none"]) return kMLClockNone;
    return MLDefaultClockStyle(osMajor);
}
static inline NSString *MLClockStyleString(int v) { return v == kMLClockMac ? @"mac" : v == kMLClockNone ? @"none" : @"ios"; }
static inline int MLBackgroundFromString(NSString *s, int osMajor) {
    if (![s isKindOfClass:[NSString class]]) return MLDefaultBackground(osMajor);
    if ([s isEqualToString:@"wallpaper"]) return kMLBackWallpaper;
    if ([s isEqualToString:@"blurred"]) return kMLBackBlurred;
    if ([s isEqualToString:@"desktop"]) return kMLBackDesktop;
    return MLDefaultBackground(osMajor);
}
static inline NSString *MLBackgroundString(int v) { return v == kMLBackBlurred ? @"blurred" : v == kMLBackDesktop ? @"desktop" : @"wallpaper"; }
static inline BOOL MLBoolOr(id v, BOOL dflt) { return [v respondsToSelector:@selector(boolValue)] && ![v isKindOfClass:[NSString class]] ? [v boolValue] : dflt; }
static inline MLSettings MLSettingsFrom(NSDictionary *d, int osMajor) {
    MLSettings s; memset(&s, 0, sizeof(s));
    if (![d isKindOfClass:[NSDictionary class]]) d = nil;
    s.enabled = MLBoolOr(d[@"enabled"], NO);
    s.clockStyle = MLClockStyleFromString(d[@"clockStyle"], osMajor);
    s.background = MLBackgroundFromString(d[@"background"], osMajor);
    s.cards = MLBoolOr(d[@"cards"], YES);
    s.showUser = MLBoolOr(d[@"showUser"], YES);
    s.statusPair = MLBoolOr(d[@"statusPair"], YES);
    s.picture = [d[@"picture"] isEqual:@"file"] ? kMLPictureFile : kMLPictureInitials;
    NSString *n = [d[@"name"] isKindOfClass:[NSString class]] ? [d[@"name"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : nil;
    if (n.length) strlcpy(s.name, n.UTF8String, sizeof(s.name));
    return s;
}

// ---- Blurred availability per iPadOS (2.4; B0 25 Nov): a still the payload can read off the main thread ----
// 15 / 16: the lock wallpaper view's displayed image (15.6.1: SBFStaticWallpaperView 1116 x 1116 @2). 17 / 18: the wallpaper server's
// thumbnail of the lock variant (17.5.1: 366 x 488, 6.8 ms, answered on the main thread, decoded and blurred off it; the same call is in 18.5's
// SpringBoard). A version where none is read at run time writes "noStill" to the state file: Settings then offers Wallpaper only.
// 17 / 18 (1.8.9 pass: the black backdrop): that thumbnail answers, but for 17.5.1's and 18.5's posters it has nothing in it (the fix round's build: every pixel black), so there
// Blurred is offered only once SpringBoard has read a real still on this iPad ("stillRead" in the state file, written when a still with a picture
// in it became a backdrop); 15 / 16 offer it until a version finds no still, as before.
static inline BOOL MLBlurredOffered(int osMajor, NSDictionary *state) {
    if (osMajor < 15 || osMajor > 18) return NO;
    NSDictionary *st = [state isKindOfClass:[NSDictionary class]] ? state : nil;
    if (MLBoolOr(st[@"noStill"], NO)) return NO;
    return osMajor < 17 || MLBoolOr(st[@"stillRead"], NO);
}
// The empty-still guard (the black backdrop, option b): a still with no picture in it is no still: never stored, never drawn (the wallpaper stays as
// iPadOS draws it), so Blurred never gives a black Lock Screen. px: the still as drawn into the backdrop's opaque context (MLBlurred: 4 bytes a
// pixel, B G R and an unused byte; the context zeroed first, so a clear pixel reads black). Empty = no colour byte above 3 anywhere (all black
// or all clear, with a decoder's rounding; a dark wallpaper with anything in it has more).
static inline BOOL MLStillEmpty(const uint8_t *px, size_t width, size_t height, size_t rowBytes) {
    if (!px || !width || !height || rowBytes < width * 4) return YES;
    for (size_t y = 0; y < height; y++) {
        const uint8_t *r = px + y * rowBytes;
        for (size_t x = 0; x < width; x++, r += 4) if (r[0] > 3 || r[1] > 3 || r[2] > 3) return NO;
    }
    return YES;
}

// ---- which parts are wanted (a part at its iPadOS value installs no hook: 2.1 0) ----
// Wi-Fi and Battery is wanted by its switch alone (rev 2, 12.1): whether the pair draws is decided at each appearance from what IS drawn at the
// top right (common/LockBarHide.h), never from a preference.
static inline BOOL MLPartWanted(const MLSettings *s, int part) {
    if (!s->enabled) return NO;
    switch (part) {
        case kMLPartClock: return s->clockStyle != kMLClockIPadOS;
        case kMLPartBackground: return s->background != kMLBackWallpaper;
        case kMLPartCards: return s->cards;
        case kMLPartUser: return s->showUser;
        case kMLPartPair: return s->statusPair;
    }
    return NO;
}
static inline BOOL MLAnyPartWanted(const MLSettings *s) {
    for (int p = 0; p < kMLPartCount; p++) if (MLPartWanted(s, p)) return YES;
    return NO;
}
// 17/18 depth poster (12.7): with our backdrop up, the floating layer must read hidden after SpringBoard's own call; a subject still drawn over
// the blur stands the backdrop down for the appearance (the wallpaper and its depth effect as iPadOS draws them, our clock kept).
static inline BOOL MLDepthStandsDown(BOOL backdropShown, BOOL depthLayerPresent, BOOL depthLayerDrawn) { return backdropShown && depthLayerPresent && depthLayerDrawn; }

// ---- the event machine (2.7, rev 2 12.2 (3)): does this appearance show the picture and name (LOCKFACE)? ----
// LOCKFACE = iPadOS's own read at the appearance and at each wake (-[SBCoverSheetPresentationManager hasBeenDismissedSinceKeybagLock] == 0: 0 at
// a lock and its wakes, 1 at a pull while unlocked; read on 15.6.1, 17.5.1 and 18.5) OR a lock seen for this appearance (MLOnLock: just before it,
// or while it is up: a pull -> Lock); the machine alone where the read is missing (-1). NO at any presentation while unlocked and lit.
// pendingLock and LOCKFACE are reset at every disappearance of the Cover Sheet and at every master switch: a lock seen while the master was off
// never reaches a later pull (18.5, 25 Nov 10:52, "appear: lock face 1 (dismissed since lock 1)" on a switch-on while unlocked).
typedef struct { BOOL down, lockFace, pendingLock, screenOff; } MLMachine;
static inline void MLOnLock(MLMachine *m) { if (m->down) m->lockFace = YES; else m->pendingLock = YES; }
// dismissedSinceLock: iPadOS's read (-1 when it could not be read)
static inline void MLOnAppear(MLMachine *m, int dismissedSinceLock) {
    if (m->down) return;   // (an appearance of an appearance: nothing new)
    m->down = YES;
    m->lockFace = m->pendingLock || dismissedSinceLock == 0;
    m->pendingLock = NO;
}
static inline void MLOnScreenOff(MLMachine *m) { m->screenOff = YES; }
// a wake: screen off -> on while the Cover Sheet is down (iPadOS's read then, -1 when missing)
static inline void MLOnScreenOn(MLMachine *m, int dismissedSinceLock) {
    if (m->down && (m->screenOff || dismissedSinceLock == 0)) m->lockFace = YES;
    m->screenOff = NO;
}
static inline void MLOnGone(MLMachine *m) { m->down = NO; m->lockFace = NO; m->pendingLock = NO; }
static inline void MLOnMasterSwitch(MLMachine *m) { m->down = NO; m->lockFace = NO; m->pendingLock = NO; }

// ---- the poster switcher (17/18, rev 2 12.2 (2)): a bounded state, never a flag that only one exit clears ----
// It starts at -_prepareForPosterSwitcherPresentation (our face dropped there, at the start of its zoom) and ends at the first of: iPadOS's own
// read (-_isPresentingPosterSwitcher) gone YES and then NO, the switcher's cleanup reporting it not presenting, the screen going off (a Lock press
// ends the switcher without that cleanup: 18.5 10:49-10:50 "switcher 1, face 0") and the Cover Sheet's disappearance. The face may come back
// only after it ended, so the first-layout retries below never re-form the face during the zoom.
typedef struct { BOOL pending, sawPresenting; } MLSwitcherState;
static inline void MLSwitcherBegin(MLSwitcherState *s) { s->pending = YES; s->sawPresenting = NO; }
static inline void MLSwitcherRead(MLSwitcherState *s, BOOL presenting) {
    if (!s->pending) return;
    if (presenting) s->sawPresenting = YES; else if (s->sawPresenting) s->pending = NO;
}
static inline void MLSwitcherCleanup(MLSwitcherState *s, BOOL presenting) { if (!presenting) s->pending = NO; }
static inline void MLSwitcherEnd(MLSwitcherState *s) { s->pending = NO; s->sawPresenting = NO; }   // (screen off, Cover Sheet gone)

// ---- the first appearance after a switch-on or a respring (rev 2 12.2 (1)) ----
// The face is decided when the Cover Sheet's view first has its window, before its first frame: at -viewWillAppear:, else at its first layout or
// -didMoveToWindow, else at -viewDidAppear: (the last chance, logged as late). Asked again while an appearance is in progress and the face is not
// up; never during the poster switcher, a dismissal or with the master off.
static inline BOOL MLFaceRetry(BOOL masterOn, BOOL appearing, BOOL faceUp, BOOL dismissing, BOOL switcherPending, BOOL inWindowOnMainScreen) {
    return masterOn && appearing && !faceUp && !dismissing && !switcherPending && inWindowOnMainScreen;
}

// ---- the user's name (2.5): typed, else the iPad's name without "'s iPad" / "\u2019s iPad", else the whole name, else "iPad" ----
static inline NSString *MLAutomaticName(NSString *deviceName) {
    NSString *d = [deviceName isKindOfClass:[NSString class]] ? [deviceName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : @"";
    for (NSString *suffix in @[ @"'s iPad", @"\u2019s iPad" ]) {
        if ([d hasSuffix:suffix] && d.length > suffix.length) return [d substringToIndex:d.length - suffix.length];
    }
    return d.length ? d : @"iPad";
}
static inline NSString *MLShownName(const MLSettings *s, NSString *deviceName) { return s->name[0] ? @(s->name) : MLAutomaticName(deviceName); }
static inline NSString *MLInitials(NSString *name) {
    NSMutableString *out = [NSMutableString string];
    for (NSString *w in [name componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (!w.length) continue;
        NSRange r = [w rangeOfComposedCharacterSequenceAtIndex:0];
        [out appendString:[[w substringWithRange:r] uppercaseString]];
        if (out.length >= 2 || [out lengthOfBytesUsingEncoding:NSUTF32StringEncoding] / 4 >= 2) break;
    }
    return out.length ? out : @"?";
}

// ---- the clock (2.6, A6) ----
// What draws iPadOS's own clock (1.8.9 pass: two clocks on 16, 25 Nov): the clock part's hooks and hosts follow it, never the major version. Where CoverSheetKit's
// CSProminentDisplayView is there, iPadOS draws its Lock Screen clock with it (its _timeView, a CSProminentTimeView, and its date line): 16.7.7
// (16.7.7's dump: CSProminentDisplayView over the whole screen, its time view drawn, SBFLockScreenDateView's own labels in no window; its
// methods read in the IPSW), 17.5.1 and 18.5. 15.6.1 has no such class (its CoverSheet; no CoverSheetKit image) and draws with
// SBFLockScreenDateView's own labels. A version with the class but not the shape ours draws with keeps iPadOS's clock (none): never the date
// view's labels there, which iPadOS does not draw (rev 2 chose by "17 or later": 16 took the 15 path and drew our clock over iPadOS's).
enum { kMLClockPathNone = 0, kMLClockPathDate = 1, kMLClockPathProminent = 2 };
static inline int MLClockPathOf(Class prominent, Class timeView, Class dateView) {
    if (prominent) return class_getInstanceVariable(prominent, "_timeView") && class_getInstanceMethod(prominent, sel_registerName("layoutSubviews"))
                          && timeView && class_getInstanceMethod(timeView, sel_registerName("setDate:")) ? kMLClockPathProminent : kMLClockPathNone;
    if (dateView && class_getInstanceVariable(dateView, "_timeLabel") && class_getInstanceMethod(dateView, sel_registerName("setCustomSubtitleView:"))
        && class_getInstanceMethod(dateView, sel_registerName("_updateLabelAlpha"))) return kMLClockPathDate;
    return kMLClockPathNone;
}
// The time format: the locale's hour and minutes ("jmm": 24-hour time follows the iPad), without the day period (macOS's lock clock has none).
static inline NSString *MLTimeFormat(NSString *templateFormat) {
    NSMutableString *f = [NSMutableString string];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < templateFormat.length; i++) {
        unichar c = [templateFormat characterAtIndex:i];
        if (c == '\'') quoted = !quoted;
        if (!quoted && (c == 'a' || c == 'b' || c == 'B')) continue;   // (the day period: AM/PM, noon/midnight, "in the evening")
        [f appendFormat:@"%C", c];
    }
    return [f stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}
// The top of our clock never above the padlock's drawn bottom (its frame's bottom + our Menu Bar Size shift, a sublayer transform) or the bar's.
static inline CGFloat MLClockTopLimit(CGFloat padlockBottom, CGFloat padlockShift, CGFloat barBottom) { return MAX(padlockBottom + padlockShift, barBottom); }
// 17/18: a date line iPadOS keeps (a widget in it, a custom or transient line that is not the hint we mirror) sits ABOVE the time: our time
// (drawn alone then) starts under that line's drawn bottom, 0.006 S apart (review finding 1: it started at 0.06 S, over the widget).
static inline CGFloat MLClockKeptTop(CGFloat topLimit, CGFloat keptLineBottom, CGFloat S) {
    return keptLineBottom > 0 ? MAX(topLimit, keptLineBottom + MAX(2, round(0.006 * S))) : topLimit;
}

// ---- the Mac clock (12.4, 12.5; sizes and places from the measured macOS reference, 12.4a, with KT's Q28 answer) ----
// From the screen's short side S, the same in both orientations. Date: Medium round(0.028 S) (Semibold with Bold Text), its cap top 0.097 S
// from the top. Time: Semibold round(0.15 S) (KT 25 Nov: "a bit larger" than macOS's 0.121 S; Bold with Bold Text), tracked -0.03 em,
// proportional digits (the system font's own), its cap top 0.027 S under the date's baseline (placed by baselines, as macOS). Each label is
// one line tall, its baseline `asc` under its top (dm / tm: the date's and the time's font metrics per 1 pt, read by the caller from UIFont;
// zero: SF's). The first line's top never above topLimit (the padlock's drawn bottom + 8, the bar's bottom + 8, the drawn bottom of iPadOS's
// hint line by the padlock + 8). It never leaves iPadOS's clock zone: up to zoneBottom (15/16 the time label's bottom; 17/18 the time view's,
// above the inline widget row), at least 24 pt from the sides and clear of the 17/18 landscape widget column (columnRight: its right edge, 0
// none); the sizes and the 0.027 S step shrink evenly to fit. Centred on the screen. The widths at 1 pt (timeWidth1 with its tracking,
// dateWidth1) are measured by the caller. The targets: S 768 22 / 115, S 834 23 / 125, S 1024 29 / 154.
typedef struct { CGFloat asc, cap, line; } MLFontMetrics;   // (per 1 pt of font size: ascender, cap height, line height)
static inline MLFontMetrics MLFontMetricsOr(MLFontMetrics m) { return m.asc > 0 && m.cap > 0 && m.line > 0 ? m : (MLFontMetrics){ 0.952, 0.705, 1.193 }; }
static inline CGFloat MLMacTimeKern(CGFloat timeSize) { return -0.03 * timeSize; }   // (macOS's tracking, 12.4a)
// The time's width at 1 pt with that tracking: between its glyphs only (none after the last, so it stays centred)
static inline CGFloat MLMacTimeWidth1(CGFloat plainWidth1, NSUInteger chars) { return plainWidth1 + (chars > 1 ? MLMacTimeKern(1) * (CGFloat)(chars - 1) : 0); }
#define kMLClockWhiteAlpha 0.80   // (the clock over our backdrop: white 0.80, 12.4a; was 0.88)
typedef struct { CGFloat dateSize, timeSize, gap, top, dateH, timeH, timeTop, scale, left, right; BOOL drawDate, fits; } MLMacClock;
static inline MLMacClock MLMacClockAt(CGFloat S, CGFloat topLimit, CGFloat k, BOOL drawDate, MLFontMetrics dm, MLFontMetrics tm) {
    MLMacClock c; memset(&c, 0, sizeof(c));
    c.drawDate = drawDate; c.scale = k;
    c.dateSize = drawDate ? floor(round(0.028 * S) * k) : 0; c.timeSize = floor(round(0.15 * S) * k);
    c.dateH = drawDate ? ceil(c.dateSize * dm.line) : 0; c.timeH = ceil(c.timeSize * tm.line);
    CGFloat capTop = 0.097 * S;
    if (drawDate) {
        c.top = MAX(round(capTop - c.dateSize * (dm.asc - dm.cap)), topLimit);
        c.timeTop = round(c.top + c.dateSize * dm.asc + 0.027 * S * k - c.timeSize * (tm.asc - tm.cap));
    } else c.top = c.timeTop = MAX(round(capTop - c.timeSize * (tm.asc - tm.cap)), topLimit);
    c.gap = drawDate ? c.timeTop - (c.top + c.dateH) : 0;   // (the time's frame top from the date's frame bottom; negative: the frames overlap, the glyphs never)
    return c;
}
static inline MLMacClock MLMacClockLayout(CGFloat S, CGFloat screenW, CGFloat topLimit, CGFloat zoneBottom, CGFloat columnRight, CGFloat timeWidth1, CGFloat dateWidth1, BOOL drawDate, MLFontMetrics dm, MLFontMetrics tm) {
    MLMacClock c; memset(&c, 0, sizeof(c));
    if (S <= 0 || screenW <= 0) return c;
    dm = MLFontMetricsOr(dm); tm = MLFontMetricsOr(tm);
    CGFloat ds = round(0.028 * S), ts = round(0.15 * S);
    // the width: centred on the screen, 24 pt from its sides and 8 pt clear of a widget column on the left
    CGFloat half = screenW / 2 - 24;
    if (columnRight > 0) half = MIN(half, screenW / 2 - columnRight - 8);
    CGFloat k = 1;
    if (timeWidth1 > 0 && ts * timeWidth1 > 2 * half) k = MIN(k, 2 * half / (ts * timeWidth1));
    if (drawDate && dateWidth1 > 0 && ds * dateWidth1 > 2 * half) k = MIN(k, 2 * half / (ds * dateWidth1));
    c = MLMacClockAt(S, topLimit, k, drawDate, dm, tm);
    // the zone: shrunk evenly until the time's bottom is inside (a few steps: the rounding is not linear)
    for (int i = 0; i < 6 && zoneBottom > 0 && c.timeTop + c.timeH > zoneBottom + 0.5 && c.timeSize > 0; i++) {
        CGFloat room = zoneBottom - c.top, extent = c.timeTop + c.timeH - c.top;
        CGFloat k2 = extent > 0 && room > 0 ? k * room / extent : 0;
        k = MAX(0, MIN(k2, k * 0.995));
        c = MLMacClockAt(S, topLimit, k, drawDate, dm, tm);
    }
    c.left = screenW / 2 - half; c.right = screenW / 2 + half;
    c.fits = c.timeSize >= 24 && (zoneBottom <= 0 || c.timeTop + c.timeH <= zoneBottom + 0.5);
    return c;
}

// ---- the user block (2.6; 12.4 / 12.6 / 12.4a: the macOS login block at rest, KT's Q28 answer "exactly like macOS") ----
// Picture round(0.09 S) clamped 72-112 pt (KT: "large", Q22), a soft shadow; name Semibold round(0.018 S) (Bold with Bold Text), round(0.019 S)
// under the picture; then iPadOS's own hint words as a plain line (no capsule, no glyph: macOS's resting look), Medium max(12, round(0.012 S)),
// as wide as its words, centred on iPadOS's own hint slot at the bottom (the one iPadOS keeps clear of its list), the name's centre about
// 0.033 S above the line's centre (the gap at least 6 pt).
static inline CGFloat MLPictureSide(CGSize screen) { CGFloat s = MIN(screen.width, screen.height) * 0.09; return round(MAX(72, MIN(112, s))); }
static inline CGFloat MLNameSize(CGSize screen) { return round(MIN(screen.width, screen.height) * 0.018); }
static inline CGFloat MLNameGap(CGSize screen) { return round(MIN(screen.width, screen.height) * 0.019); }
static inline CGFloat MLHintSize(CGSize screen) { return MAX(12, round(MIN(screen.width, screen.height) * 0.012)); }
static inline CGFloat MLHintLineH(CGFloat hintSize) { return ceil(hintSize * 1.25); }
static inline CGFloat MLHintLineWidth(CGFloat textWidth) { return ceil(MAX(0, textWidth)) + 2; }
static inline CGFloat MLHintGap(CGSize screen, CGFloat nameH, CGFloat lineH) { return MAX(6, round(MIN(screen.width, screen.height) * 0.033 - nameH / 2 - lineH / 2)); }
// The line's rect: centred on the hint slot's frame (its centre), one line tall (h); no slot (empty rect): its bottom at `fallbackBottom`.
// Never over iPadOS's home affordance (homeTop: its top, 0 none): at most 4 pt above it (15.6.1 and 18.5 keep the teachable slot just over
// the home bar: label y 802.5 / 992.5, home bar y 821 / 1011).
static inline CGRect MLHintRect(CGRect hintSlot, CGFloat screenW, CGFloat width, CGFloat h, CGFloat fallbackBottom, CGFloat homeTop) {
    CGFloat cy = CGRectIsEmpty(hintSlot) ? fallbackBottom - h / 2.0 : CGRectGetMidY(hintSlot);
    CGFloat y = round(cy - h / 2.0);
    if (homeTop > 0 && y + h > homeTop - 4) y = homeTop - 4 - h;
    return CGRectMake(round((screenW - width) / 2), y, width, h);
}
// The picture and name stack above the field; the field yields last: list content within 8 pt of its rect hides it too (iPadOS's own hint
// line then unmasked).
static inline BOOL MLFieldYields(CGRect field, CGFloat listBottom) { return listBottom > 0 && listBottom >= CGRectGetMinY(field) - 8; }
// iPadOS's hint candidates (15: the teachable container's label; 17.5.1 Touch ID: the footer's; 18.5: the teachable one at alpha 0 and the
// Face ID line by the padlock, the prominent display's transient line): the one DRAWN (effective alpha > 0.01, text not empty) is mirrored.
typedef struct { BOOL drawn; CGFloat alpha; BOOL hasText; } MLHintFacts;
static inline int MLHintPick(const MLHintFacts *h, int n) {
    for (int i = 0; i < n; i++) if (h[i].drawn && h[i].hasText && h[i].alpha > 0.01) return i;
    return -1;
}
enum { kMLUserWhole = 0, kMLUserSmall = 1, kMLUserNameOnly = 2, kMLUserHidden = 3 };
static inline CGFloat MLNameLineH(CGFloat nameSize) { return ceil(nameSize * 1.25); }
// The block's bottom line: 12 pt above iPadOS's call-to-action line's top; without one, above the home affordance; neither: 64 pt from the bottom.
// Also above the footer's status text (when it shows) and the quick actions' tops (a value <= 0 = none).
static inline CGFloat MLUserBottom(CGFloat screenH, CGFloat callToActionTop, CGFloat homeAffordanceTop, CGFloat statusTextTop, CGFloat quickActionsTop) {
    CGFloat b = callToActionTop > 0 ? callToActionTop - 12 : homeAffordanceTop > 0 ? homeAffordanceTop - 12 : screenH - 64;
    if (statusTextTop > 0) b = MIN(b, statusTextTop - 12);
    if (quickActionsTop > 0) b = MIN(b, quickActionsTop - 12);
    return b;
}
static inline CGFloat MLUserHeight(int mode, CGFloat side, CGFloat nameH, CGFloat nameGap) {
    switch (mode) {
        case kMLUserWhole: return side + nameGap + nameH;
        case kMLUserSmall: return 56 + 8 + nameH;
        case kMLUserNameOnly: return nameH;
    }
    return 0;
}
// It yields to iPadOS's list, never the other way (rev 1, Q19): room = from the lowest visible list content's bottom (listBottom; <= 0 none) to
// the block's bottom line. The whole block + 16 pt, else the 56 pt picture, else the name only, else hidden while that content is there.
static inline int MLUserMode(CGFloat bottom, CGFloat listBottom, CGFloat side, CGFloat topLimit, CGFloat nameH, CGFloat nameGap) {
    CGFloat top = MAX(listBottom > 0 ? listBottom : 0, topLimit);
    CGFloat room = bottom - top;
    if (room >= MLUserHeight(kMLUserWhole, side, nameH, nameGap) + 16) return kMLUserWhole;
    if (room >= MLUserHeight(kMLUserSmall, side, nameH, nameGap) + 16) return kMLUserSmall;
    if (room >= MLUserHeight(kMLUserNameOnly, side, nameH, nameGap) + 16) return kMLUserNameOnly;
    return kMLUserHidden;
}
// A centred block of width w with its bottom at `bottom`: moved by the yield steps until it meets no widget frame (frames in the same coordinates).
static inline BOOL MLRectMeetsAny(CGRect r, const CGRect *frames, int n) {
    for (int i = 0; i < n; i++) if (!CGRectIsEmpty(frames[i]) && CGRectIntersectsRect(r, frames[i])) return YES;
    return NO;
}
static inline int MLUserModeClear(CGFloat screenW, CGFloat bottom, int mode, CGFloat side, CGFloat nameWidth, CGFloat nameH, CGFloat nameGap, const CGRect *widgets, int n) {
    for (int m = mode; m < kMLUserHidden; m++) {
        CGFloat h = MLUserHeight(m, side, nameH, nameGap), w = MAX(m == kMLUserWhole ? side : m == kMLUserSmall ? 56 : 0, nameWidth);
        CGRect r = CGRectMake(round((screenW - w) / 2), bottom - h, w, h);
        if (!MLRectMeetsAny(r, widgets, n)) return m;
    }
    return kMLUserHidden;
}

// ---- Wi-Fi and battery (2.6): top right where the bar's icons would be, never over a widget ----
static inline CGRect MLPairFrame(CGFloat screenW, CGFloat barHeight, CGSize pair, const CGRect *widgets, int n) {
    CGRect r = CGRectMake(screenW - 12 - pair.width, round((MAX(barHeight, 24) - pair.height) / 2), pair.width, pair.height);
    return MLRectMeetsAny(r, widgets, n) ? CGRectZero : r;
}
// Inside the pair, macOS's order (12.4a): Wi-Fi rightmost, the battery to its left, 10 pt apart. The pair's size: MLPairSize.
static inline CGSize MLPairSize(CGSize wifi, CGSize battery) { return CGSizeMake(battery.width + 10 + wifi.width, MAX(wifi.height, battery.height)); }
static inline void MLPairPlaces(CGSize wifi, CGSize battery, CGRect *wifiR, CGRect *batteryR) {
    if (batteryR) *batteryR = CGRectMake(0, 0, battery.width, battery.height);
    if (wifiR) *wifiR = CGRectMake(battery.width + 10, 0, wifi.width, wifi.height);
}

// ---- legibility over iPadOS's own sharp wallpaper (2.6, rev 1) ----
// style: _UILegibilitySettings' style (1 = light content: white text with a dark shadow; 2 = dark content: dark text with a light shadow).
// Over our own darkened backdrop the text is white at 0.92 whatever the style.
typedef struct { CGFloat white, alpha, shadowWhite, shadowAlpha; } MLTextLook;
static inline MLTextLook MLTextLookFor(BOOL overOurBackdrop, long style) {
    if (overOurBackdrop || style != 2) return (MLTextLook){ 1.0, 0.92, 0.0, overOurBackdrop ? 0.0 : 0.30 };
    return (MLTextLook){ 0.0, 0.85, 1.0, 0.25 };
}

// ---- the backdrop (2.4): made once, never live; its key ----
// source: the wallpaper's identity (15/16: the wallpaper files' times and sizes; 17/18: the active lock poster's identity and version; our
// Desktop Picture's path and time); then the orientation, the appearance and Increase Contrast. v2 (1.8.9 pass: the black backdrop): a picture stored before the
// empty-still guard (the fix round's build stored 17.5.1's and 18.5's black ones) never matches again.
static inline NSString *MLBackdropKey(NSString *source, BOOL landscape, BOOL dark, BOOL contrast) {
    if (!source.length) return nil;
    return [NSString stringWithFormat:@"v2 %@ %c %c %c", source, landscape ? 'L' : 'P', dark ? 'd' : 'l', contrast ? 'c' : '-'];
}
// 17/18: the active lock poster's identity (1.8.9 pass: the black backdrop, 25 Nov). SBWallpaperController's _activeLockScreenPosterConfiguration (an ivar, a
// PRSPosterConfiguration) has NO -posterUUID on 17.5.1 or 18.5 (read in Apple's IPSWs, PosterBoardServices): the only route rev 2 read, so the
// key was nil at every appearance and Blurred never drew. What both versions have, all METHODS (read in the IPSWs, types as given): the
// configuration's -serverUUID (@, the poster's UUID) and -_path (@; also an ivar _path); the path's -serverIdentity (@: PRSPosterPath on 17.5.1,
// PosterFoundation's PFPosterPath on 18.5); the identity's -posterUUID (@), -version and -supplement (Q: PRSServerPosterIdentity on 17.5.1,
// PFServerPosterIdentity on 18.5). Every read is typed (the method is there, takes no argument and returns what we read; the ivar's type is an
// object): no KVC and no exception path at an appearance. The UUID: -posterUUID, else -serverUUID, else the path's identity's; the version and
// the supplement: the configuration's, else the identity's ("-" where none answers). A changed poster or version gives a new source. nil: none.
static inline id MLTypedObj(id o, SEL s) {
    if (!o || !s || ![o respondsToSelector:s]) return nil;
    Method m = class_getInstanceMethod(object_getClass(o), s);
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e || e[0] != '@' || method_getNumberOfArguments(m) != 2) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
static inline BOOL MLTypedUInt(id o, SEL s, unsigned long long *out) {
    if (!o || !s || !out || ![o respondsToSelector:s]) return NO;
    Method m = class_getInstanceMethod(object_getClass(o), s);
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e || method_getNumberOfArguments(m) != 2) return NO;
    if (e[0] == 'Q' || e[0] == 'q') { *out = ((unsigned long long (*)(id, SEL))objc_msgSend)(o, s); return YES; }
    if (e[0] == 'I' || e[0] == 'i') { *out = ((unsigned int (*)(id, SEL))objc_msgSend)(o, s); return YES; }
    return NO;
}
static inline id MLObjIvar(id o, const char *name) {
    if (!o) return nil;
    Ivar v = class_getInstanceVariable(object_getClass(o), name);
    const char *t = v ? ivar_getTypeEncoding(v) : NULL;
    return t && t[0] == '@' ? object_getIvar(o, v) : nil;
}
static inline NSString *MLUUIDText(id u) {
    if ([u isKindOfClass:[NSUUID class]]) return [(NSUUID *)u UUIDString];
    return [u isKindOfClass:[NSString class]] && [(NSString *)u length] ? (NSString *)u : nil;
}
static inline NSString *MLPosterSource(id cfg) {
    if (!cfg) return nil;
    id path = MLTypedObj(cfg, sel_registerName("_path")) ?: MLObjIvar(cfg, "_path");
    id ident = MLTypedObj(path, sel_registerName("serverIdentity"));
    NSString *u = MLUUIDText(MLTypedObj(cfg, sel_registerName("posterUUID"))) ?: MLUUIDText(MLTypedObj(cfg, sel_registerName("serverUUID")))
                  ?: MLUUIDText(MLTypedObj(ident, sel_registerName("posterUUID")));
    if (!u) return nil;
    unsigned long long ver = 0, sup = 0;
    BOOL hasVer = MLTypedUInt(cfg, sel_registerName("version"), &ver) || MLTypedUInt(ident, sel_registerName("version"), &ver);
    BOOL hasSup = MLTypedUInt(cfg, sel_registerName("supplement"), &sup) || MLTypedUInt(ident, sel_registerName("supplement"), &sup);
    return [NSString stringWithFormat:@"poster %@ %@ %@", u, hasVer ? [NSString stringWithFormat:@"%llu", ver] : @"-", hasSup ? [NSString stringWithFormat:@"%llu", sup] : @"-"];
}
static inline double MLBackdropTarget(BOOL contrast) { return contrast ? 0.36 : 0.48; }   // (mean luminance after darkening)
static inline double MLBackdropDim(double meanLuminance, BOOL contrast) { return meanLuminance > 0.01 ? MIN(0.9, MLBackdropTarget(contrast) / meanLuminance) : 0.9; }
// The still drawn into the backdrop (rev 2 12.2 (4)): an aspect FILL, centred, never stretched -- a portrait still (17/18's 366 x 488) on a
// landscape screen gives its centre band. Returns the rect to draw the still into, in the destination's pixels.
static inline CGRect MLAspectFillRect(CGSize still, CGSize dest) {
    if (still.width <= 0 || still.height <= 0 || dest.width <= 0 || dest.height <= 0) return CGRectZero;
    CGFloat k = MAX(dest.width / still.width, dest.height / still.height);
    CGFloat w = still.width * k, h = still.height * k;
    return CGRectMake((dest.width - w) / 2, (dest.height - h) / 2, w, h);
}
// The stored key names the still's own size too (for the logs and B0's landscape read); a stored picture matches the key whatever its still's
// size: only the lock variant's still is read in this build, so there is no second shape to replace it with yet.
static inline NSString *MLBackdropStoredKey(NSString *key, CGSize still) { return key ? [NSString stringWithFormat:@"%@ still %.0fx%.0f", key, still.width, still.height] : nil; }
static inline BOOL MLBackdropKeyMatches(NSString *stored, NSString *key) { return stored && key && ([stored isEqualToString:key] || [stored hasPrefix:[key stringByAppendingString:@" still "]]); }
// The picture's size: 256 px on the long side at the screen's aspect.
static inline CGSize MLBackdropPixels(CGSize screen) {
    CGFloat l = MAX(screen.width, screen.height), s = MIN(screen.width, screen.height);
    if (l <= 0) return CGSizeMake(256, 192);
    CGFloat w = 256, h = round(256 * s / l);
    return screen.width >= screen.height ? CGSizeMake(w, h) : CGSizeMake(h, w);
}

// ---- the hint line's look (12.4a: macOS's resting hint, plain text) ----
// Over our backdrop: white 0.80 (0.92 with Increase Contrast), no shadow. Over iPadOS's sharp wallpaper (Background Wallpaper): the slot's
// legibility style, as the name (dark content: dark text with a light shadow; light content: white with a dark shadow).
static inline MLTextLook MLHintLookFor(BOOL overOurBackdrop, BOOL contrast, long legibilityStyle) {
    if (overOurBackdrop) return (MLTextLook){ 1.0, contrast ? 0.92 : 0.80, 0.0, 0.0 };
    return MLTextLookFor(NO, legibilityStyle);
}

// ---- the picture and name's visibility (2.6): hidden while a modal piece is up ----
typedef struct { BOOL passcode, today, posterSwitcher, modal, mainPageHidden; } MLModal;
static inline BOOL MLUserVisible(BOOL lockFace, MLModal m) { return lockFace && !m.passcode && !m.today && !m.posterSwitcher && !m.modal && !m.mainPageHidden; }
