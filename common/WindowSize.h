// WindowSize.h -- the size an app's window opens at (Settings > Windows & Multitasking > Window Size, 1.8.0 item 4, KT 2 Nov): Small, Default or
// Large, the same on every window engine (Aerial, Zetsu, MilkyWay4, our Stage Manager engine), and where it goes among the windows already there.
// Plain C on CoreGraphics, so the Mac test (tools/test-windowsize.sh) runs this very code; StatusBar.x's DMNewWindowFrame (and DMSMNewWindowFrameIn
// for Stage Manager) hands it the desktop.
//  - It sizes a window that opens without a place of its own: an app's first window, its next one once the app has quit (its place is forgotten
//    then, AppExitForget), a full-screen app sent to a window it never had. A window that comes back where it last was keeps that place and size
//    (1.7.5 item 13), and the layouts keep theirs (Fill Screen, the halves and quarters, Fit to Window's tiles, the Window menu's places).
//  - Default: the size new windows have always had, never written. The engines' middle place ("center", the Window menu's Center): 78% of the
//    screen's width, centred, 12 pt under the menu bar, 80% of the screen's height and never past the Dock -- our Stage Manager engine's too (1.8.0,
//    KT 3 Nov: one Default on every engine; it had one of its own, 60% x 72% of the screen, or the front window's size cascaded from it).
//  - Small and Large: shares of the desktop between the menu bar and the Dock (the area every layout is cut from), centred in it, so they follow the
//    screen's size and its orientation. Small: half its width and 58% of its height. Large: 92% x 96%, a little of the desktop left around it. Never
//    smaller than a window may be (WindowMinSize.h: the app 320 x 300 under our 24 pt title bar; a smaller desktop gives all of it), never bigger
//    than the desktop, Small never bigger than Default and Large never smaller (a very tall Dock leaves Default the desktop's whole height under its
//    12 pt: Large gets that height too). The Window menu's Small and Large are these very windows (MSBDWindowSizeShapeIn: one definition; its Large
//    was 86% x 92% of the desktop until 1.8.0).
//  - Among the other windows (MSBDWindowCascadeIn): one rule on every engine, as on a Mac -- a window opening over another is moved on so both
//    title bars show. Our Stage Manager engine gave a window joining a desktop the front window's size and cascaded it from the front window.
//  - No Fit's free window (Fit to Window's third window kept out of the tiles, MSBDWindowNoFitIn): at Default the middle place centred in the
//    desktop with room around it, at Small and Large Window Size's own window -- every engine.
#ifndef MSBD_WINDOW_SIZE_H
#define MSBD_WINDOW_SIZE_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <string.h>
#include "../statusbar/WindowMinSize.h"

#define kMSBDWindowSizeKey "windowSize"   // (com.besiktasliseba.macstatusbar: "small" or "large"; never set -- the default -- is Default)
enum { MSBDWindowSizeDefault = 0, MSBDWindowSizeSmall = 1, MSBDWindowSizeLarge = 2 };

// The shares of the desktop (width, height): Window Size's and the Window menu's Small and Large (StatusBar.x DMLayoutFrameInArea "small" /
// "large" are MSBDWindowSizeShapeIn below).
#define kMSBDWindowSmallW 0.50
#define kMSBDWindowSmallH 0.58
#define kMSBDWindowLargeW 0.92
#define kMSBDWindowLargeH 0.96

// The stored text as SpringBoard and Settings read it: "small" Small, "large" Large; anything else -- never set, "default", false (the crash
// guard's off), another value -- Default.
static inline int MSBDWindowSizeFromName(const char *name) {
    if (!name) return MSBDWindowSizeDefault;
    if (!strcmp(name, "small")) return MSBDWindowSizeSmall;
    if (!strcmp(name, "large")) return MSBDWindowSizeLarge;
    return MSBDWindowSizeDefault;
}
static inline const char *MSBDWindowSizeName(int size) { return size == MSBDWindowSizeSmall ? "small" : size == MSBDWindowSizeLarge ? "large" : "default"; }
// ... from the stored value itself (StatusBar.x DMLoadPrefs, MSBRootListController.m): a string as above, anything else (none, false) Default.
static inline int MSBDWindowSizeFromStored(CFTypeRef v) {
    char name[16] = "";
    if (!v || CFGetTypeID(v) != CFStringGetTypeID() || !CFStringGetCString((CFStringRef)v, name, sizeof name, kCFStringEncodingUTF8)) return MSBDWindowSizeDefault;
    return MSBDWindowSizeFromName(name);
}

// The engines' middle place (the "center" layout, today's new window): 11% in from the screen's sides, `top` (12 pt under the iPad's menu bar,
// MenuBarHeight.h MSBDMenuBarCenterTop; a TV's 36) and 80% of the screen's height, never past the desktop's bottom (the Dock).
static inline CGRect MSBDWindowCenterIn(CGRect u, CGSize screen, double top) {
    double x = u.size.width < screen.width - 0.5 ? round(u.origin.x + (u.size.width - round(screen.width * 0.78)) / 2.0) : round(screen.width * 0.11);   // (a desktop narrower than the screen, the Dock at a side: in its middle)
    return CGRectMake(x, top, round(screen.width * 0.78), fmin(round(screen.height * 0.80), CGRectGetMaxY(u) - top));
}
// A share of the desktop, centred in it (the Window menu's Medium; Window Size's Small and Large start from it).
static inline CGRect MSBDWindowShareIn(CGRect u, double fw, double fh) {
    CGFloat w = round(u.size.width * fw), h = round(u.size.height * fh);
    return CGRectMake(round(u.origin.x + (u.size.width - w) / 2.0), round(u.origin.y + (u.size.height - h) / 2.0), w, h);
}
// The window at `size` (the whole window, our title bar on top) in the desktop u of a screen of `screen`, before it is grown to a minimum: Default the
// middle place; Small / Large their share, held at most / at least Default's width and height, centred again -- inside u. The Window menu's Small and
// Large (StatusBar.x DMLayoutFrameInArea, each engine's minimum after it as for every layout) and Window Size's (MSBDWindowSizeFrameIn). A desktop that
// is not one (null, empty), no screen or no top: CGRectNull.
static inline CGRect MSBDWindowSizeShapeIn(int size, CGRect u, CGSize screen, double top) {
    if (CGRectIsNull(u) || CGRectIsEmpty(u) || !(screen.width > 0) || !(screen.height > 0) || !isfinite(top)) return CGRectNull;
    CGRect dflt = MSBDWindowCenterIn(u, screen, top);
    if (size != MSBDWindowSizeSmall && size != MSBDWindowSizeLarge) return dflt;
    int small = size == MSBDWindowSizeSmall;
    CGRect f = MSBDWindowShareIn(u, small ? kMSBDWindowSmallW : kMSBDWindowLargeW, small ? kMSBDWindowSmallH : kMSBDWindowLargeH);
    CGFloat w = small ? fmin(f.size.width, dflt.size.width) : fmax(f.size.width, dflt.size.width);
    CGFloat h = small ? fmin(f.size.height, dflt.size.height) : fmax(f.size.height, dflt.size.height);
    w = fmin(w, u.size.width); h = fmin(h, u.size.height);
    if (w != f.size.width || h != f.size.height)
        f = CGRectMake(round(u.origin.x + (u.size.width - w) / 2.0), round(u.origin.y + (u.size.height - h) / 2.0), w, h);
    return f;
}
// The window a new window opens at in the desktop u for `size`. min: the smallest window there (WindowMinSize.h MSBDWindowMinSize, or Stage
// Manager's where it is wider): the shape above grown to min around its middle where it is smaller (as every layout is, StatusBar.x
// DMWindowSlotInArea), inside u. A desktop that is not one: CGRectNull.
static inline CGRect MSBDWindowSizeFrameIn(int size, CGRect u, CGSize screen, double top, CGSize min) {
    CGRect f = MSBDWindowSizeShapeIn(size, u, screen, top);
    return CGRectIsNull(f) ? f : MSBDWindowMinSlotOf(f, 0, u, min);
}
// A Stage Manager window as Stage Manager is handed it (StatusBar.x DMSMJoinAttributes): its card, the app under our title bar of `bar` (kSMBarH).
static inline CGRect MSBDWindowCardOf(CGRect window, double bar) {
    return CGRectIsNull(window) ? CGRectNull : CGRectMake(window.origin.x, window.origin.y + bar, window.size.width, window.size.height - bar);
}
// ... and the window of a card of size `card` around `centre` (the other windows of a stage, as DMSMJoinAttributes reads them).
static inline CGRect MSBDWindowOfCard(CGPoint centre, CGSize card, double bar) {
    return CGRectMake(centre.x - card.width / 2.0, centre.y - card.height / 2.0 - bar, card.width, card.height + bar);
}

// ---- where a new window goes among the windows already on the desktop: one rule on every engine (1.8.0, KT 3 Nov) ----------------------------
// StatusBar.x DMCascadeStage (Aerial, Zetsu, MilkyWay4) and DMSMJoinAttributes (our Stage Manager engine) ask this with the engine's own frames
// (Aerial 5.x: its stages, the window grown by Aerial's margins; the others: the whole window) and the desktop in the same space. As on a Mac,
// each window keeps its title bar in sight: a window covering no other one by more than 45% (of the smaller window) stays where it opens; one
// that does is moved on in steps of 50 pt right and 44 pt down -- each step tried down and right, then up and left, up to 8 steps out -- to the
// first place where its top-left corner is 34 pt or more from every other window's, across or down, kept inside the desktop (never past the
// Dock: a step that would reach under it is lifted, as Stage Manager's windows always were); no such place: where it opened. own: it opens where
// it last was (1.7.5 item 13) -- it stays there over what it covers, moved on only when its corner sits on another window's (its title bar hidden
// under the other's). Until 1.8.0 the other engines' steps could reach 30 pt past the desktop's bottom, under the Dock, and our Stage Manager
// engine opened a joining window at the front window's size, cascaded 5% x 6% of the screen from the front window's centre.
// *how: MSBDCascadeStays (it covers no other window), MSBDCascadeOwnKept (own, its corner clear), MSBDCascadeNoRoom (no clear place), else the
// step taken (1..8 down and right, -1..-8 up and left).
#define kMSBDCascadeStepX 50.0
#define kMSBDCascadeStepY 44.0
#define kMSBDCascadeNear 34.0     // (top-left corners closer than this, across and down: one title bar under the other)
#define kMSBDCascadeCovers 0.45   // (the share of the smaller window covered: "over another window")
enum { MSBDCascadeStays = 0, MSBDCascadeNoRoom = 99, MSBDCascadeOwnKept = 100 };
// The share of the smaller of two windows that the other covers (0 apart, 1 one inside the other).
static inline double MSBDWindowOverlap(CGRect a, CGRect b) {
    CGRect i = CGRectIntersection(a, b);
    if (CGRectIsNull(i)) return 0.0;
    double smaller = fmin(a.size.width * a.size.height, b.size.width * b.size.height);
    return smaller > 0.0 ? (i.size.width * i.size.height) / smaller : 0.0;
}
static inline int MSBDWindowCornerTaken(CGRect f, const CGRect *others, int n) {
    for (int i = 0; i < n; i++) if (fabs(others[i].origin.x - f.origin.x) < kMSBDCascadeNear && fabs(others[i].origin.y - f.origin.y) < kMSBDCascadeNear) return 1;
    return 0;
}
static inline CGRect MSBDWindowCascadeIn(CGRect base, const CGRect *others, int n, CGRect desk, int own, int *how) {
    if (how) *how = MSBDCascadeStays;
    if (CGRectIsNull(base) || CGRectIsEmpty(base) || CGRectIsNull(desk) || !others || n <= 0) return base;
    int covers = 0;
    for (int i = 0; i < n && !covers; i++) if (MSBDWindowOverlap(base, others[i]) > kMSBDCascadeCovers) covers = 1;
    if (!covers) return base;
    if (own && !MSBDWindowCornerTaken(base, others, n)) { if (how) *how = MSBDCascadeOwnKept; return base; }
    for (int k = 1; k <= 8; k++) for (int sign = 1; sign >= -1; sign -= 2) {
        CGRect f = CGRectOffset(base, sign * k * kMSBDCascadeStepX, sign * k * kMSBDCascadeStepY);
        f.origin.x = fmax(desk.origin.x, fmin(f.origin.x, CGRectGetMaxX(desk) - f.size.width));   // (on the screen; a window wider than it keeps the left edge)
        f.origin.y = fmax(desk.origin.y, fmin(f.origin.y, CGRectGetMaxY(desk) - f.size.height));   // (under the menu bar, above the Dock; its top wins)
        if (!MSBDWindowCornerTaken(f, others, n)) { if (how) *how = sign * k; return f; }
    }
    if (how) *how = MSBDCascadeNoRoom;
    return base;
}

// No Fit's free window at Default (StatusBar.x DMNoFitFrame, DMSMNoFitPlace): the middle place `center` (the engine's own, its minimum in) made no
// bigger than the desktop u less 48 pt each way and centred in it -- the middle place is top-aligned and reached into the Dock on the iPad 2 in
// landscape. At Small / Large the callers take Window Size's window, centred already. A null center or desktop: center.
static inline CGRect MSBDWindowNoFitIn(CGRect center, CGRect u) {
    if (CGRectIsNull(u) || CGRectIsNull(center)) return center;
    CGFloat w = fmin(center.size.width, u.size.width - 48.0), h = fmin(center.size.height, u.size.height - 48.0);
    return CGRectIntegral(CGRectMake(CGRectGetMidX(u) - w / 2.0, CGRectGetMidY(u) - h / 2.0, w, h));
}

// ---- New Windows Open at Fill (Settings > Windows & Multitasking, 1.8.3 item 2; KeyPilot's author's design, wanghuangjie; off unless switched on) ----
// A window that opens with no place of its own (as Window Size sizes it: an app's first window, its next one once the app has quit, a full-screen app
// sent to a window it never had) opens at the Fill layout -- the desktop between the menu bar and the Dock, beside a side Dock -- instead of Window
// Size's window, on every engine. Applied where a window opens: the windowed launch, Aerial's cascade, Zetsu's and MilkyWay4's new window, the Stage
// Manager join -- never on a layout pass, so a layout picked afterwards (the Window menu, the window keys, KeyPilot) stays. It is in the Fill layout:
// it follows the Dock and the screen as Fill does. A window coming back to its own place keeps it, and one asked to a frame goes there, as before.
// Fit to Window: its switch stays the user's. A window that opens at Fill is not tiled by it -- no side question, never another window's tile taken --
// and stays out of its tiles as No Fit's window does (each engine's free windows); every other window as before.
#define kMSBDNewWindowsFillKey "newWindowsFill"   // (com.besiktasliseba.macstatusbar: a boolean; never set -- the default -- is off)
// Where a window that opens goes: YES the Fill layout, NO as before (Window Size's window, or its own place, or the frame asked for).
static inline bool MSBDNewWindowAtFill(bool fillOn, bool ownPlace, bool askedFor) { return fillOn && !ownPlace && !askedFor; }
// Whether Fit to Window takes a window that opens into its tiles (or asks the side question for it): not one that opens at Fill.
static inline bool MSBDFitTakesOpening(bool fitOn, bool atFill) { return fitOn && !atFill; }

#endif
