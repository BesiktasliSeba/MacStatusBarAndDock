// ResizeFact.h -- macOS's resize pointers, SpringBoard's half (1.8.9, F51; plans/design-mac-resize-pointers.md). Included by StatusBar.x after
// SMResizeEdges.h; the rules and the glyphs are common/MacResizeCursor.h's, the drawing is MacPointer's (statusbar/macpointer/MacPointer.x).
//   SpringBoard knows which resize place the pointer is on and says it in one Darwin notification state (MSBD_RZ_NOTE: kind, position, the way the
//   window can go, the display); pointeruid draws macOS's resize cursor for it while iPadOS's pointer shows its own resize shape there.
//  - iPadOS 16-18, Apple's Stage Manager and our Stage Manager engine: a window's container marks the edge its resize band has under the pointer
//    (-[SBFluidSwitcherItemContainer _updateForPointerHoveringOverEdge:], 1 top, 2 bottom, 3 left, 4 right, 5-8 the corners; read on 18.5 in B0:
//    every pointer move over a window calls it, so only a change does anything). Edge 0 clears only the fact this container set (another window's
//    band may have begun first).
//  - Our window engines' grips (Aerial 3.0 / 5.x, Zetsu, MilkyWay4's handle; 1.8.9, F51b, KT 25 Nov "All engines in 1.8.9"; design section 12):
//    iPadOS gives SpringBoard no hover in an engine's window (B0, 15.6.1: every hover arrives in its system gestures window), so a watching
//    recognizer there reads each hover's point against the grips (below: DMRZGripHover). Its fact is its own evidence in pointeruid while fresh.
//  - Nothing at rest: the band hook goes in at the first switch-on (Mac Resize Pointers on -- Settings > Pointer, by default on iPadOS 18 and off
//    on 15-17, KT 25 Nov --, Pointer Style Mac, a trackpad or mouse attached, MacPointer drawing, the crash guard's piece not off) and passes
//    straight through while off; with the switch off from the start (DMRZFollow) nothing of this file runs: no hook, no recognizer, no word said.
//    A window that goes away clears its fact at the bridge's 2 s check (and pointeruid draws a band's glyph only over iPadOS's own resize shape or
//    a drag it latched, whatever the fact says; a grip's fact needs no shape there but lives on its lease -- MSBDResizeGripFresh -- and every
//    clear below).
// The crash guard's piece "resizePointers" (tools/crashmap-rules.txt): off, nothing of this runs (but the one clear of an earlier SpringBoard's
// word, DMRZFollow) and, with Mac Resize Pointers on, the pointer shows the Mac arrow at the edges (with it off: 1.8.8.4's look). A piece, not the
// switch: the switch's default is per iPadOS, which a crash map's pref target cannot say; Turn Back On ends it.
#pragma once
#include "../common/MacResizeCursor.h"
#include "../common/PointerFade.h"   // (F51b: the pointer's fade, said by pointeruid: a grip's fact goes with it)

#define MSBD_RZ_PIECE "resizePointers"   // (the crash guard turns it off as a piece until Turn Back On, whatever Mac Resize Pointers says)
static BOOL DMRZSkipped(void) { static int s = -1; if (s < 0) s = MSBDCrashSkipped(MSBD_RZ_PIECE); return s != 0; }
static BOOL gRZOn = NO;            // (the Mac pointer draws: facts are said)
static uint64_t gRZSaid = UINT64_MAX;   // (the word last said; 0 nothing; not known at the start: notifyd may still hold the last SpringBoard's word)
static __weak id gRZOwner = nil;   // (who set it: a window's container)
static unsigned gRZGen = 0;
static void DMRZSay(uint64_t w) {
    static int token = 0;
    if (w == gRZSaid) return;
    if (!token && notify_register_check(MSBD_RZ_NOTE, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    gRZSaid = w;
    notify_set_state(token, w);
    notify_post(MSBD_RZ_NOTE);
}
static unsigned DMRZDisplayOf(UIView *v) { UIScreen *s = v.window.screen; return s && s != [UIScreen mainScreen] ? 1 : 0; }
static CFTimeInterval gRZSaidAt = 0;   // (when a fact was last said: a grip's is said again every MSBD_RZ_GRIP_RESAY s, its lease)
static void DMRZSetAgain(id owner, MSBDResizeFact f, BOOL again) {   // (again: a new generation even for the same place -- a grip's lease)
    if (!gRZOn || !owner) return;
    if (!again && gRZOwner == owner && gRZSaid && MSBDResizeSamePlace(MSBDResizeUnpack(gRZSaid), f)) return;   // (the same place again)
    gRZSaidAt = CACurrentMediaTime();
    if (!++gRZGen) ++gRZGen;
    f.generation = gRZGen & 0xFFFF; if (!f.generation) f.generation = 1;
    gRZOwner = owner;
    DM_FEATURE_MARK("mac-resize-pointers");
    DMRZSay(MSBDResizePack(f));
#if DEBUG
    if (DMTestFlag("/tmp/msb-resizedebug") && !again) DMLog([NSString stringWithFormat:@"[resize] fact: kind %u position %u directions %u display %u source %u (%@ %p)", f.kind, f.position, f.directions, f.display, f.source, NSStringFromClass([owner class]), owner]);
#endif
}
static void DMRZSet(id owner, MSBDResizeFact f) { DMRZSetAgain(owner, f, NO); }
static void DMRZClear(id owner) {   // (only the fact this owner set; one whose owner is gone, by anyone)
    if (!gRZSaid) return;
    id cur = gRZOwner;
    if (owner && cur && owner != cur) return;
    gRZOwner = nil;
    DMRZSay(0);
#if DEBUG
    if (DMTestFlag("/tmp/msb-resizedebug")) DMLog([NSString stringWithFormat:@"[resize] fact cleared (%@ %p)", owner ? NSStringFromClass([owner class]) : @"-", owner]);
#endif
}

// ---- 16-18: a window's resize bands (Apple's Stage Manager and our engine) ----
// The way a band's edge can go (macOS's one-way arrows, common/MacResizeCursor.h MSBDResizeDirectionsFor): a window at Stage Manager's smallest
// width (320 pt: -[SBSwitcherChamoisLayoutAttributes minimumWindowWidth] on 16.7.7, 17.5.1 and 18.5) only grows that way; at our engine's smallest
// height on 17+ (300 pt, SMEngineAPI.h kSM17MinWindowHeight) only taller (Apple's own engine: its smallest height is not read, never one-way
// there); an edge at the screen's edge (the switcher's content view) only inward. The top never inward-only: how far a window's top may go under
// the menu bar is not known here.
static unsigned DMRZBandDirections(UIView *c, unsigned pos) {
    UIView *sup = c.superview;
    if (!sup || !CGAffineTransformIsIdentity(c.transform)) return MSBD_RZ_ALL;   // (a scaled window: its frame is not its size -- no one-way claim)
    CGRect f = [c convertRect:c.bounds toView:sup], area = sup.bounds;
    CGSize ws = c.window.bounds.size;   // (the screen's limits only when the container's parent is the whole window -- B0 18.5: the switcher's
                                        //  content view, 1366 x 1024; anything else: no inward claim)
    if (!c.window || fabs(area.size.width - ws.width) > 1.0 || fabs(area.size.height - ws.height) > 1.0 || fabs(area.origin.x) > 1.0 || fabs(area.origin.y) > 1.0) area = CGRectNull;
    else { area.origin.y -= 100000.0; area.size.height += 100000.0; }   // (no top limit)
    CGSize mn = CGSizeMake(kMSBDWindowMinWidth, DMSMEngine() && DMSMLayoutGen() == 17 ? kSM17MinWindowHeight : 0);
    return MSBDResizeDirectionsFor(pos, f, mn, area, 1.0);
}
static void (*o_RZHoverEdge)(id, SEL, unsigned long long);
static void DMRZHoverEdge(id self, SEL _cmd, unsigned long long edge) {
    o_RZHoverEdge(self, _cmd, edge);
    if (!gRZOn) return;   // (off: straight through)
    static __weak id lastC; static unsigned long long lastE = 0; static CGRect lastF;
    // (every pointer move over a window comes here: a change only -- of the window, its edge, or its size or place while its band is hovered, so a
    //  one-way arrow follows a resize in the same band)
    CGRect fr = edge && [self isKindOfClass:[UIView class]] ? ((UIView *)self).frame : CGRectZero;
    if (self == lastC && edge == lastE && (!edge || (gRZOwner == self && CGRectEqualToRect(fr, lastF)))) return;
    lastC = self; lastE = edge; lastF = fr;
    unsigned pos = MSBDResizePosOfSBEdge(edge);
    if (!pos || ![self isKindOfClass:[UIView class]]) { DMRZClear(self); return; }
    MSBDResizeFact f = { MSBD_RZ_FRAME, pos, DMRZBandDirections((UIView *)self, pos), DMRZDisplayOf((UIView *)self), MSBD_RZ_SRC_BAND, 0 };
    DMRZSet(self, f);
}
static void DMRZInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class ic = objc_getClass("SBFluidSwitcherItemContainer");
    SEL s = sel_registerName("_updateForPointerHoveringOverEdge:");
    Method m = ic ? class_getInstanceMethod(ic, s) : NULL;
    if (!m) { DMLog(@"[resize] no window resize bands to follow here (iPadOS 15, or the container's method is not here): the Mac arrow at every resize place"); return; }
    if (![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(unsigned long long), NULL)]) {
        DMLog([NSString stringWithFormat:@"[resize] the windows' hovered edge is not as written for here (%s): the Mac arrow at the edges", method_getTypeEncoding(m)]);
        return;
    }
    MSHookMessageEx(ic, s, (IMP)DMRZHoverEdge, (IMP *)&o_RZHoverEdge);
    DMLog(o_RZHoverEdge ? @"[resize] following the windows' resize bands (macOS's resize pointers)" : @"[resize] the hovered edge's hook did not go in");
}

// ---- our window engines' grips: Aerial 3.0 / 5.x, Zetsu, MilkyWay4, on every iPadOS they run (1.8.9, F51b; design section 12) ----
// iPadOS gives SpringBoard no hover in an engine's window, and pointeruid no resize shape at a grip (B0, 15.6.1: every hover SpringBoard gets
// arrives in its system gestures window -- also over the grips, as Began / Changed, Cancelled when the pointer fades; none while a button is down,
// one at once at the button-up; pointeruid's state stays the round pointer or the app's own shape). So SpringBoard watches the hovers it does get:
// a recognizer on each display's system gestures window (PointerRegion.h's DMPtrHoverRecognizer: it prevents nothing and is prevented by nothing),
// each hover's point read against the views that take our grips' touches, the front-most one only. Its fact (source GRIP) is its own evidence in
// pointeruid, on a lease (common/MacResizeCursor.h MSBDResizeGripFresh), so every way it could outlive the pointer on the grip is closed:
//  - a hover off every grip (on any display) clears it at once;
//  - while it stands, the last point is checked again every 0.2 s (the window closed, minimized, moved, covered, its desktop left: gone within
//    0.2 s; also after UIKit cancelled the hover for a layout) and the fact said again every 0.4 s (its lease: a SpringBoard that died or hangs
//    leaves no glyph after 1.2 s); a turn of the screen or a long rest on another display ends it (MSBDResizeGripCheckKeeps);
//  - during a drag of a grip (no hovers come then) the point is the drag's own, from our engines' drag code (DMRZGripDrag), and at its end the
//    grip is decided again at the release point (review 1.8.9 F51b, finding 1: a corner that could not follow left the press point on the grip);
//  - the pointer fading (pointeruid's word, common/PointerFade.h) clears it; the next hover decides again;
//  - off (Pointer Style iPadOS, no trackpad or mouse, MacPointer not drawing, the crash guard, no engine window with a live grip): no recognizer.
// Nothing of Aerial, Zetsu or MilkyWay4 is hooked, changed or added to: their views are read (frames, hidden, hit test) only.
@interface DMRZTaker : NSObject { @public __weak UIView *view; __weak UIView *win; __weak UIView *handle; unsigned pos; int kind; CGRect at, local; __weak UIScreen *screen; }
@end
@implementation DMRZTaker
@end
enum { DMRZKindAerial = 0, DMRZKindZetsu = 1, DMRZKindMilkyWay = 2 };
static NSArray<DMRZTaker *> *gRZTakers;    // (made at a hover's start and at most every 0.5 s while hovers come; their frames kept with them)
static CFTimeInterval gRZTakersAt = -10;
static BOOL gRZGripsOn = NO;               // (the recognizers are on the system gestures windows)
static CGPoint gRZGripLast;                // (the last hover's or drag's point, in its screen's space ...)
static CGRect gRZGripLastBounds;           // (... that screen's bounds then: a turn changes them)
static __weak UIScreen *gRZGripLastScreen;
static CFTimeInterval gRZHoverAt = -10;    // (the last hover on any display)
static __weak DMRZTaker *gRZGripShown;     // (the grip whose fact stands, by its last full test ...)
static CFTimeInterval gRZGripFullAt = -10; // (... and when that test ran: inside the same grip again within 0.05 s, no hit tests -- finding 5)
static BOOL gRZGripDragging = NO;          // (a drag of a grip whose fact stood at its start: its points are the drag's)
static NSTimer *gRZGripTimer;
#if DEBUG
static unsigned long gRZGripN; static double gRZGripUs, gRZGripMax;
#endif
// A window or a view's own window (a UIWindow's -window is nil: Zetsu's windows are UIWindows).
static UIWindow *DMRZWindowOf(UIView *v) { return [v isKindOfClass:[UIWindow class]] ? (UIWindow *)v : v.window; }
static void DMRZTakerAdd(NSMutableArray *out, UIView *v, UIView *win, UIView *handle, unsigned pos, int kind) {
    if (![v isKindOfClass:[UIView class]] || !v.window || v.hidden) return;
    DMRZTaker *t = [DMRZTaker new];
    t->view = v; t->win = win; t->handle = handle; t->pos = pos; t->kind = kind;
    t->screen = v.window.screen;
    t->at = t->screen ? [v convertRect:v.bounds toCoordinateSpace:t->screen.coordinateSpace] : CGRectNull;
    t->local = CGRectNull;
    [out addObject:t];
}
// The views a grip's touch goes to (each about 32 pt), for the windows of the desktop on screen that are shown (not minimized, not closing or
// flying in): Aerial 5.x our DMA5GripBox at its stage's bottom corners (its hit test hands the touch to Aerial's own handle) and that handle itself
// (it stays touchable, alpha 0.011); Aerial 3.0 Aerial's own handles (our grip is only drawn there, DMStyleStage); Zetsu our DMZetsuGripBox; MilkyWay4
// its "sizeChanger", which our restyle makes the 32 pt box at the bottom right (DMRestyleWindowButtons). The same associations every engine's pass
// keeps (DMWindowedGripsOf).
static NSArray<DMRZTaker *> *DMRZTakersFind(void) {
    NSMutableArray<DMRZTaker *> *out = [NSMutableArray array];
    DMEngine e = DMActiveEngine();
    if (e == DMEngineNone) return out;
    Class mw = objc_getClass("AXWindowView");
    for (UIView *w in DMAerialStages()) {
        UIWindow *ww = DMRZWindowOf(w);
        if (!ww || ww.hidden || w.hidden || w.alpha < 0.05 || DMStageMinimized(w) || [objc_getAssociatedObject(w, kStageClosingKey) boolValue] || [objc_getAssociatedObject(w, kStageEnteringKey) boolValue]) continue;
        for (int side = 0; side < 2; side++) {
            unsigned pos = side == 0 ? (MSBD_RZ_BOTTOM | MSBD_RZ_LEFT) : (MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT);
            if (e == DMEngineAerial) {
                UIView *h = DMStageValue(w, @[side == 0 ? @"_handleBL" : @"_handleBR"]);
                if (![h isKindOfClass:[UIView class]]) h = nil;
                DMA5GripBox *box = objc_getAssociatedObject(w, side == 0 ? kA5GripBLKey : kA5GripBRKey);
                if ([box isKindOfClass:[DMA5GripBox class]]) DMRZTakerAdd(out, box, w, box.handle ?: h, pos, DMRZKindAerial);   // (5.x)
                if (h && (box || objc_getAssociatedObject(w, side == 0 ? kStageGripBLKey : kStageGripBRKey))) DMRZTakerAdd(out, h, w, nil, pos, DMRZKindAerial);   // (5.x and 3.0)
            } else if (e == DMEngineZetsu) {
                DMRZTakerAdd(out, objc_getAssociatedObject(w, side == 0 ? kZetsuGripLKey : kZetsuGripRKey), w, nil, pos, DMRZKindZetsu);
            } else if (e == DMEngineMilkyWay && side == 1 && mw && [w isKindOfClass:mw]) {
                UIView *sc = nil; @try { sc = [w valueForKey:@"sizeChanger"]; } @catch (id x) {}
                if ([sc isKindOfClass:[UIView class]] && objc_getAssociatedObject(sc, kMWGripKey)) DMRZTakerAdd(out, sc, w, nil, pos, DMRZKindMilkyWay);   // (only once our restyle made it the corner box)
            }
        }
    }
    return out;
}
// A window's hit test at a screen point, read only; another tweak's -hitTest:withEvent: that throws counts as an answer (review 1.8.9 F51b,
// finding 7: a covered grip, never a crash).
static UIView *DMRZHitAt(UIWindow *w, CGPoint p, UIScreen *s, BOOL *threw) {
    if (threw) *threw = NO;
    @try { return [w hitTest:[w convertPoint:p fromCoordinateSpace:s.coordinateSpace] withEvent:nil]; } @catch (id x) { if (threw) *threw = YES; }
    return nil;
}
// A window above the grip's own that really takes a touch at this point of its screen: our Dock, a menu, an alert, a native window, Control Center,
// Zetsu's windows in front (each one back is 0.01 lower) -- NativeWindow.h DMNativeWindowTaking's rule, with the native layer counted and only that
// screen's windows. The engines' keyboard windows (AerialKeyboardWindow, ZetsuKeyboard, MilkyWay4's) hold a keyboard host as big as the screen: a
// keyboard view is never the answer, the keyboard on the screen is (its height, DMPlaceKeyboardPill's measure: the engines' keyboards span the
// screen's bottom edge over the windows).
static BOOL DMRZCoveredAt(CGPoint p, UIScreen *s, CGFloat level) {
    if (s == [UIScreen mainScreen] && gSoftKeyboardH > 1.0 && p.y >= s.bounds.size.height - gSoftKeyboardH) return YES;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w.screen != s || w.windowLevel <= level || w.alpha < 0.01) continue;
        NSString *c = NSStringFromClass([w class]);
        if (DMSBIsBarWindowName(c) || [c isEqualToString:@"_UISystemGestureWindow"] || [c containsString:@"Recording"] || [c containsString:@"TextEffects"]
            || [c containsString:@"RemoteKeyboard"] || [c containsString:@"InputWindow"]) continue;
        BOOL threw = NO;
        UIView *h = DMRZHitAt(w, p, s, &threw);
        if (threw) return YES;
        if (!h || h == w || h == w.rootViewController.view) continue;
        NSString *hc = NSStringFromClass([h class]);
        if ([hc containsString:@"PassThrough"] || [hc containsString:@"Passthrough"] || [hc isEqualToString:@"SBFluidSwitcherContentView"] || [hc containsString:@"Keyboard"]) continue;
#if DEBUG
        if (DMTestFlag("/tmp/msb-resizedebug")) { static NSString *last; NSString *l = [NSString stringWithFormat:@"%@ (%.1f) %@", c, w.windowLevel, hc]; if (![l isEqualToString:last]) { last = l; DMLog([NSString stringWithFormat:@"[resize] a grip covered by %@", l]); } }
#endif
        return YES;
    }
    return NO;
}
// The grip a click at this screen point would go to, or nil: inside a taker's box, its window's own hit test gives it (a view inside it, or the
// handle it hands to) and no window above takes the point. Inside the grip of the last full test, within 0.05 s, that answer stands (no hit tests
// on every move in a grip; something new over it is seen at most 0.05 s later -- finding 5); a covered grip likewise.
static __weak DMRZTaker *gRZCovered;
static DMRZTaker *DMRZGripAt(CGPoint p, UIScreen *s, BOOL full) {
    CFTimeInterval now = CACurrentMediaTime();
    for (DMRZTaker *t in gRZTakers) {
        UIView *v = t->view;
        UIWindow *w = v.window;
        if (!w || t->screen != s || w.screen != s || v.hidden) continue;
        if (!CGRectContainsPoint(CGRectInset(t->at, -2.0, -2.0), p)) continue;   // (the frame kept with the list: a quick no; a moved window's box is read now)
        CGRect live = [v convertRect:v.bounds toCoordinateSpace:s.coordinateSpace];
        t->at = live;
        if (!CGRectContainsPoint(live, p)) continue;
        if (!full && now - gRZGripFullAt < 0.05) { if (t == gRZGripShown) return t; if (t == gRZCovered) continue; }
        UIView *hit = DMRZHitAt(w, p, s, NULL);
        UIView *h = t->handle;
        if (!hit || !(hit == v || [hit isDescendantOfView:v] || (h && hit == h))) { gRZCovered = t; gRZGripFullAt = now; continue; }
        gRZGripFullAt = now;
        if (DMRZCoveredAt(p, s, w.windowLevel)) { gRZCovered = t; return nil; }
        gRZCovered = nil;
        return t;
    }
    return nil;
}
// The way a grip's corner can go (macOS's one-way arrows), only where our own drag keeps that limit: outward at the engine's minimum both ways
// (WindowMinSize.h: Zetsu our grip's drag; MilkyWay4 our step after its own, sizeChangePan:; Aerial where its corner handle is watched and its
// drag values are there, DMA5CornerMinWatch / DMA5CornerOffsetAt); inward only on Zetsu, whose drag our code stops at the screen's edges
// (MSBDWindowCornerDrag), with both moving sides there. Aerial's and MilkyWay4's drags go past the screen's edges: never inward there. A scaled
// window (its frame is not its size): the double arrow.
static unsigned DMRZGripDirections(DMRZTaker *t) {
    UIView *w = t->win;
    if (!w || !CGAffineTransformIsIdentity(w.transform)) return MSBD_RZ_ALL;
    BOOL isWin = [w isKindOfClass:[UIWindow class]];
    if (!isWin && !w.superview) return MSBD_RZ_ALL;
    CGSize mn = CGSizeZero; CGRect area = CGRectNull;
    if (t->kind == DMRZKindZetsu) { mn = MSBDWindowMinSize(); UIScreen *s = isWin ? ((UIWindow *)w).screen : w.window.screen; if (isWin && s) area = s.bounds; }
    else if (t->kind == DMRZKindMilkyWay) mn = MSBDWindowMinSize();
    else {
        UIView *h = t->handle ?: t->view;
        if (objc_getAssociatedObject(h, &kA5MinWatchedKey) && DMA5CornerOffsetAt(w) && DMA5ResizeStartAt(w)) mn = DMEngineWindowMin();
    }
    if (mn.width <= 0 && CGRectIsNull(area)) return MSBD_RZ_ALL;
    return MSBDResizeDirectionsFor(t->pos, w.frame, mn, area, 1.0);
}
static BOOL DMRZGripFactStands(void) { return gRZSaid && gRZSaid != UINT64_MAX && MSBDResizeUnpack(gRZSaid).source == MSBD_RZ_SRC_GRIP; }
static void DMRZGripClear(void) {   // (a grip's fact only)
    gRZGripShown = nil;
    if (DMRZGripFactStands()) DMRZClear(gRZOwner);
}
static void DMRZGripTimerSet(BOOL on);
// The decision at a point of a screen (common/MacResizeCursor.h MSBDResizeGripAction): the grip's fact said, said again, cleared, or nothing.
// again: a hover inside the grip (said again at once); full: the whole test even inside the grip the last one found.
static void DMRZGripDecide(CGPoint p, UIScreen *s, BOOL again, BOOL full) {
    DMRZTaker *t = s ? DMRZGripAt(p, s, full) : nil;
    MSBDResizeFact f = { MSBD_RZ_FRAME, t ? t->pos : 0, t ? DMRZGripDirections(t) : 0, s != [UIScreen mainScreen] ? 1u : 0u, MSBD_RZ_SRC_GRIP, 0 };
    BOOL same = t && gRZOwner == t->view && DMRZGripFactStands() && MSBDResizeSamePlace(MSBDResizeUnpack(gRZSaid), f);
    switch (MSBDResizeGripAction(t != nil, same, again, CACurrentMediaTime() - gRZSaidAt, DMRZGripFactStands())) {
        case MSBD_RZ_GRIP_CLEAR: DMRZGripClear(); DMRZGripTimerSet(NO); return;
        case MSBD_RZ_GRIP_NOTHING: if (!t) { gRZGripShown = nil; DMRZGripTimerSet(NO); return; } break;
        case MSBD_RZ_GRIP_SAY: DMRZSetAgain(t->view, f, NO); break;
        case MSBD_RZ_GRIP_SAY_AGAIN: DMRZSetAgain(t->view, f, YES); break;
    }
    gRZGripShown = t;
    DMRZGripTimerSet(YES);
}
static void DMRZGripPointSet(CGPoint p, UIScreen *s) { gRZGripLast = p; gRZGripLastScreen = s; gRZGripLastBounds = s.bounds; }
// While a grip's fact stands: the last point checked in full every 0.2 s, the fact said again every 0.4 s (its lease in pointeruid). No other
// timer; none without a grip's fact.
static void DMRZGripTimerSet(BOOL on) {
    if (on == (gRZGripTimer != nil)) return;
    if (!on) { [gRZGripTimer invalidate]; gRZGripTimer = nil; return; }
    gRZGripTimer = [NSTimer timerWithTimeInterval:MSBD_RZ_GRIP_CHECK repeats:YES block:^(NSTimer *timer) {
        if (!gRZOn || !gRZGripsOn || !DMRZGripFactStands()) { gRZGripShown = nil; DMRZGripTimerSet(NO); return; }
        UIScreen *s = gRZGripLastScreen;
        if (!s || !MSBDResizeGripCheckKeeps(CGRectEqualToRect(s.bounds, gRZGripLastBounds), MSBDResizeUnpack(gRZSaid).display, CACurrentMediaTime() - gRZHoverAt)) {
            DMRZGripClear(); DMRZGripTimerSet(NO); return;
        }
        DMRZGripDecide(gRZGripLast, s, NO, YES);
    }];
    gRZGripTimer.tolerance = 0.04;
    [[NSRunLoop mainRunLoop] addTimer:gRZGripTimer forMode:NSRunLoopCommonModes];
}
// From our engines' grip drags (StatusBar.x: Aerial's corner minimum step, Zetsu's grip box, MilkyWay4's resize step), the drag's point on its
// screen: no hover comes while a button is down, so the 0.2 s check uses this point, and the end decides at the release point at once. Only a
// drag that began with a grip's fact standing (a pointer on that grip: a finger's drag of a grip changes nothing here).
static void DMRZGripDrag(CGPoint p, UIScreen *s, UIGestureRecognizerState st) {
    if (!gRZGripsOn || !s) return;
    if (st == UIGestureRecognizerStateBegan) gRZGripDragging = DMRZGripFactStands();
    if (!gRZGripDragging) return;
    DMRZGripPointSet(p, s);
    if (st == UIGestureRecognizerStateEnded || st == UIGestureRecognizerStateCancelled || st == UIGestureRecognizerStateFailed) {
        gRZGripDragging = NO;
        DMRZGripDecide(p, s, NO, YES);
    }
}
static void DMRZGripHover(UIHoverGestureRecognizer *g) {
    if (!gRZOn || !gRZGripsOn) return;
#if DEBUG
    CFTimeInterval t0 = CACurrentMediaTime();
#endif
    UIView *v = g.view;
    UIWindow *w = DMRZWindowOf(v);   // (a system gestures window is a UIWindow: its own screen)
    UIScreen *s = w.screen;
    UIGestureRecognizerState st = g.state;
    if (s && (st == UIGestureRecognizerStateBegan || st == UIGestureRecognizerStateChanged)) {   // (Cancelled -- a fade, a layout -- has no point:
                                                                                                  //  the fact stays for the 0.2 s check and the fade)
        CFTimeInterval now = CACurrentMediaTime();
        gRZHoverAt = now; gRZGripDragging = NO;
        CGPoint lp = [g locationInView:v];
        if (st == UIGestureRecognizerStateBegan || now - gRZTakersAt > 0.5) {   // (the list, and each grip's frame in this window's own space)
            gRZTakers = DMRZTakersFind(); gRZTakersAt = now;
            for (DMRZTaker *t in gRZTakers) if (t->screen == s && !CGRectIsNull(t->at)) t->local = [v convertRect:t->at fromCoordinateSpace:s.coordinateSpace];
        }
        BOOL near = NO;   // (the quick no, in the window's own space: most hovers end here, no conversion at all -- cost, logic test 14)
        for (DMRZTaker *t in gRZTakers) if (t->screen == s && CGRectContainsPoint(CGRectInset(t->local, -4.0, -4.0), lp)) { near = YES; break; }
        if (!near && !DMRZGripFactStands()) { gRZGripShown = nil; DMRZGripTimerSet(NO); }
        else {
            CGPoint p = [v convertPoint:lp toCoordinateSpace:s.coordinateSpace];
            DMRZGripPointSet(p, s);
            DMRZGripDecide(p, s, YES, NO);
        }
    }
#if DEBUG
    double us = (CACurrentMediaTime() - t0) * 1e6; gRZGripN++; gRZGripUs += us; if (us > gRZGripMax) gRZGripMax = us;
#endif
}
@interface DMRZGripSink : NSObject
- (void)hover:(UIHoverGestureRecognizer *)g;
@end
@implementation DMRZGripSink
- (void)hover:(UIHoverGestureRecognizer *)g { DMRZGripHover(g); }
@end
static const void *kDMRZHoverKey = &kDMRZHoverKey;
// pointeruid's word on the pointer's fade (common/PointerFade.h): faded, the grip's fact goes (UIKit cancels the hover then too; the next hover
// decides again). Registered once, at the first switch-on.
static void DMRZGripWatchFade(void) {
    static BOOL done = NO; static int token = 0;
    if (done) return;
    done = YES;
    notify_register_dispatch(kMSBDPointerFadeNote, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t v = 0;
        if (notify_get_state(t, &v) == NOTIFY_STATUS_OK && v == MSBDPointerFadeHidden && gRZGripsOn) { DMRZGripClear(); DMRZGripTimerSet(NO); }
    });
}
// On (the Mac pointer draws and an engine of ours has a shown window with a grip on the desktop on screen) or off: every 2 s and at once with the
// pointer's switch (DMRZFollow). The recognizers on each display's system gestures window, or none. At rest nothing is walked: while on, the
// windows' grips are looked for again only when a hover came since the last look (the next hover makes the list anyway); while off, only when
// windows exist (DMWindowWorkNeeded) -- review 1.8.9 F51b, finding 9.
static void DMRZGripsFollow(void) {
    static CFTimeInterval lookedAt = -10;
    BOOL want = gRZGripsOn;
    if (!gRZOn || DMActiveEngine() == DMEngineNone) want = NO;
    else if (!gRZGripsOn ? DMWindowWorkNeeded() : gRZHoverAt > lookedAt) {
        lookedAt = CACurrentMediaTime();
        NSArray<DMRZTaker *> *ts = DMRZTakersFind();
        want = ts.count > 0;
    } else if (!gRZGripsOn) want = NO;
    static DMRZGripSink *sink;
    if (want && !sink) sink = [DMRZGripSink new];
    NSUInteger n = 0, have = 0;
    if (want || gRZGripsOn) for (UIWindow *w in DMAllWindows()) {   // (a display that came gets its recognizer here)
        if (![NSStringFromClass([w class]) isEqualToString:@"_UISystemGestureWindow"]) continue;
        UIHoverGestureRecognizer *h = objc_getAssociatedObject(w, kDMRZHoverKey);
        if (want && !h) {
            h = [[DMPtrHoverRecognizer alloc] initWithTarget:sink action:@selector(hover:)];
            h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;
            [w addGestureRecognizer:h];
            objc_setAssociatedObject(w, kDMRZHoverKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            n++;
        } else if (!want && h) {
            [w removeGestureRecognizer:h];
            objc_setAssociatedObject(w, kDMRZHoverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            n++;
        }
        if (want) have++;
    }
    if (want != gRZGripsOn) {
        gRZGripsOn = want;
        if (want) { DMRZGripWatchFade(); gRZTakersAt = -10; DM_FEATURE_MARK("mac-resize-pointers-grips"); }
        else { DMRZGripClear(); DMRZGripTimerSet(NO); gRZTakers = nil; gRZGripDragging = NO; }
        DMLog([NSString stringWithFormat:@"[resize] our window engine's grips %@ (%lu system gestures window(s))", want ? @"followed: macOS's resize pointers at their corners" : @"not followed", (unsigned long)(want ? have : n)]);
    } else if (want && n) DMLog([NSString stringWithFormat:@"[resize] grips: %lu more system gestures window(s) watched (a display came)", (unsigned long)n]);
#if DEBUG
    if (gRZGripN && DMTestFlag("/tmp/msb-resizedebug")) {
        DMLog([NSString stringWithFormat:@"[resize] grips: %lu hovers, avg %.1f us, max %.0f us; %lu takers", gRZGripN, gRZGripUs / gRZGripN, gRZGripMax, (unsigned long)gRZTakers.count]);
        gRZGripN = 0; gRZGripUs = 0; gRZGripMax = 0;
    }
#endif
}
#if DEBUG
// rzinfo (debug, read-only): the grips' takers, the recognizers, the fact.
static void DMRZInfo(void) {
    NSMutableString *o = [NSMutableString stringWithFormat:@"[resize] info: on %d grips %d engine %d said 0x%llx (source %u) shown %p timer %d dragging %d; last point %@", gRZOn, gRZGripsOn, (int)DMActiveEngine(),
        gRZSaid == UINT64_MAX ? 0ULL : gRZSaid, gRZSaid == UINT64_MAX ? 0 : MSBDResizeUnpack(gRZSaid).source, gRZGripShown, gRZGripTimer != nil, gRZGripDragging, NSStringFromCGPoint(gRZGripLast)];
    for (DMRZTaker *t in DMRZTakersFind())
        [o appendFormat:@"\n  taker %@ %p kind %d pos %u at %@ (window %@ %@ level %.2f) handle %p directions %u", NSStringFromClass([t->view class]), t->view, t->kind, t->pos, NSStringFromCGRect(t->at),
            NSStringFromClass([t->win class]), NSStringFromCGRect(t->win.frame), t->view.window.windowLevel, t->handle, DMRZGripDirections(t)];
    for (UIWindow *w in DMAllWindows()) if ([NSStringFromClass([w class]) isEqualToString:@"_UISystemGestureWindow"])
        [o appendFormat:@"\n  system gestures window %p on %@: our recognizer %@", w, w.screen == [UIScreen mainScreen] ? @"the iPad" : @"another display", objc_getAssociatedObject(w, kDMRZHoverKey) ? @"on" : @"none"];
    DMLog(o);
}
#endif

// ---- on / off: from the pointer bridge's 2 s check and at once after a Settings change (StatusBar.x DMPointerBridgeTick: Pointer Style and Mac
// Resize Pointers, gDMPtrResizeOn) ----
// MacPointer's word, read through a token kept for the run (MSBD_MP_STATUS, common/MacPointerStatus.h).
static uint64_t DMRZPointerStatus(void) {
    static int token = 0; uint64_t v = 0;
    if (!token && notify_register_check(MSBD_MP_STATUS, &token) != NOTIFY_STATUS_OK) { token = 0; return 0; }
    notify_get_state(token, &v);
    return v;
}
static void DMRZFollow(BOOL styleMac) {
    // (the first follow with Mac Resize Pointers on, whatever else is off -- the crash guard's piece too: whatever word an earlier SpringBoard left
    //  in notifyd goes, so pointeruid never draws it -- review 1.8.9 F51, finding 3; the switch's review, finding 1. Off: nothing said)
    static BOOL cleared = NO;
    if (!cleared && gDMPtrResizeOn) { cleared = YES; DMRZSay(0); }
    // (Mac Resize Pointers off -- Settings > Pointer, by default on iPadOS 15-17 -- or no trackpad or mouse: off, and nothing read, nothing said,
    //  nothing installed -- most iPads at rest)
    BOOL on = styleMac && gDMPtrResizeOn && gDMPointerAttached && !DMRZSkipped() && MSBDMPVerdictDraws(MSBDMPVerdict(DMRZPointerStatus()));
    if (on != gRZOn) {
        gRZOn = on;
        DMRZSay(0);   // (off: the fact goes; on: nothing left from before -- the clear above)
        if (on) DMRZInstall(); else gRZOwner = nil;
        DMLog([NSString stringWithFormat:@"[resize] macOS's resize pointers %@ (Mac Resize Pointers %@, Pointer Style %@, trackpad or mouse %@, MacPointer %@)", on ? @"on" : @"off",
            gDMPtrResizeOn ? @"on" : @"off", styleMac ? @"Mac" : @"iPadOS", gDMPointerAttached ? @"attached" : @"none", MSBDMPVerdictDraws(MSBDMPVerdict(DMRZPointerStatus())) ? @"draws" : @"does not draw"]);
        DMRZGripsFollow();   // (F51b: the engines' grips with it, at once)
        return;
    }
    if (!gRZOn) return;   // (off: nothing more -- no word, no window walked)
    if (gRZSaid) {   // (a window gone under the pointer, or taken out of its window: its fact goes)
        id o = gRZOwner;
        if (!o || ([o isKindOfClass:[UIView class]] && !((UIView *)o).window)) DMRZClear(nil);
    }
    DMRZGripsFollow();   // (F51b: an engine window with a grip came or went, a display came)
}
