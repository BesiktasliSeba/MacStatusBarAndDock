// statusbar/PointerRegion.h -- the pointer's place while another display shares it (1.8.7, the iPad 2's AirPlay B pass: rows 14 and 6.6; the rules in
// common/PointerRegion.h, Mac test tools/test-pointerregion.sh). Included by StatusBar.x before the Mac Switcher.
//  - the iPad's own region in backboardd's pointer space, learned from a hover on the iPad's own screen (DMPtrIPadNative): what the auto-hiding menu bar
//    (DMAutoHidePollPointer), the menu bar over a full-screen app (BarReveal.h) and the Dock part (exported, MSBDPointerOnIPad) read the pointer by;
//  - when the pointer was last on another display (DMPtrOtherDisplayAt): a push at the iPad's bottom edge right after it is not the Mac Switcher's.
// Both from one hover recognizer on SpringBoard's system gestures window of each display (_UISystemGestureWindow: every pointer move on that display
// reaches it, over app windows too -- read on the A12Z's TV, 11 Nov), there only while another display has one: with the iPad alone nothing is added and
// the iPad's region is the space's origin, as before. A piece of the status bar for the crash guard (tools/crashmap-rules.txt, pointerRegion): turned
// off after a crash in it, and then nothing here runs (the iPad's region read as before 1.8.7).
#include "../common/PointerRegion.h"
#define MSBD_PTR_REGION_PIECE "pointerRegion"   // (no Settings row: the crash guard turns it off as a piece, its target in tools/crashmap-rules.txt, until Turn Back On)
static MSBDPtrRegion gDMPtrRegion = { 1, 0, 0.0, 0.0, 0, 0.0, 0.0 };   // (no other display: the iPad's region at the origin)
static CFTimeInterval gDMPtrOtherAt = 0;   // the pointer last on another display (a hover there, or its leaving it)
static CGPoint gDMPtrIPadLast = {NAN, NAN};   // the iPad's own hover: its last native point (the screen's fixed portrait space) ...
static CFTimeInterval gDMPtrIPadLastAt = 0;   // ... and when
static CFTimeInterval gDMPtrAnyAt = 0;   // the last hover on any display (a reading counts only with none since: the pointer did not move)
static void DMAutoHideIPadHover(CGPoint n, BOOL inside);   // (StatusBar.x: the iPad's auto-hide zone from its own hover while the region is not known)
static BOOL DMPtrSkipped(void) { static int s = -1; if (s < 0) s = MSBDCrashSkipped(MSBD_PTR_REGION_PIECE); return s != 0; }
static CGSize DMPtrIPadNativeSize(void) { return [UIScreen mainScreen].fixedCoordinateSpace.bounds.size; }
// backboardd's position as the iPad's own native point: 1 on the iPad (n), 0 elsewhere, -1 not known yet (another display attached, not learned).
static int DMPtrIPadNative(CGPoint g, CGPoint *n) {
    double x = NAN, y = NAN; CGSize s = DMPtrIPadNativeSize();
    int r = MSBDPtrOnIPad(&gDMPtrRegion, g.x, g.y, s.width, s.height, &x, &y);
    if (n) *n = CGPointMake(x, y);
    return r;
}
static CFTimeInterval DMPtrOtherDisplayAt(void) { return gDMPtrOtherAt; }
// For the Dock part (dock/Dock.x, looked up once): the same answer in plain C.
__attribute__((visibility("default"))) int MSBDPointerOnIPad(double gx, double gy, double *nx, double *ny) {
    CGPoint n; int r = DMPtrIPadNative(CGPointMake(gx, gy), &n);
    if (nx) *nx = n.x;
    if (ny) *ny = n.y;
    return r;
}
// A reading of the region: backboardd's position, off the main thread, against the iPad's hover point it was asked for; counted only if no newer hover
// came meanwhile (the pointer did not move). A first reading waits for a second of the same rest (0.3 s later). Unknown: at most 5 a second; known: one
// every 2 s, which also follows an arrangement changed in Settings.
static void DMPtrLearnRead(void) {
    static dispatch_queue_t q; static BOOL busy; static CFTimeInterval lastAt = -10;
    if (busy || DMPtrSkipped() || !gDMPtrRegion.other || isnan(gDMPtrIPadLast.x)) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastAt < (gDMPtrRegion.known && !gDMPtrRegion.cand ? 2.0 : 0.2)) return;
    lastAt = now; busy = YES;
    CGPoint n0 = gDMPtrIPadLast; CFTimeInterval t0 = gDMPtrAnyAt;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.macstatusbar.pointerregion", DISPATCH_QUEUE_SERIAL);
    dispatch_async(q, ^{
        Class c = objc_getClass("BKSMousePointerService");
        id svc = c && [(id)c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)c, @selector(sharedInstance)) : nil;
        SEL gp = sel_registerName("globalPointerPosition");
        Method m = svc ? class_getInstanceMethod(object_getClass(svc), gp) : NULL;
        BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{CGPoint=dd}16@0:8");
        CGPoint g = known ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, gp) : CGPointMake(NAN, NAN);
        dispatch_async(dispatch_get_main_queue(), ^{
            busy = NO;
            if (gDMPtrAnyAt != t0 || isnan(g.x) || !gDMPtrRegion.other) return;   // (it moved meanwhile, on any display, or the display went: the next hover asks again)
            if (MSBDPtrRegionLearn(&gDMPtrRegion, g.x, g.y, n0.x, n0.y))
                DMLog([NSString stringWithFormat:@"[ptrregion] the iPad's region in the pointer's space starts at {%.0f, %.0f} (backboardd %@, the iPad's own %@)", gDMPtrRegion.ox, gDMPtrRegion.oy, NSStringFromCGPoint(g), NSStringFromCGPoint(n0)]);
            if (gDMPtrRegion.cand) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gDMPtrAnyAt == t0) { lastAt = -10; DMPtrLearnRead(); }   // (the same rest: its second reading)
            });
        });
    });
}
static unsigned long gDMPtrSeen[2];   // (debug counts: hovers on the iPad, on another display)
// A hover of a view of ours or of SpringBoard's (g.view): on another display, when the pointer was there; on the iPad, its own native point -- the
// auto-hide zone while the region is not known and, from a system gestures window (learn), a reading of the region. Fed by those windows' hovers below
// and by the iPad's own menu bar copies and top-edge strip (StatusBar.x DMStatusBarHover, DMPtrStripHover), which see the pointer where the bar is shown
// or hidden: zone only, as the strip's window lies turned on the screen and its point across the edge came back wrong (d22: its x along the edge).
// A system gestures window is a UIWindow, whose -window is nil: its own screen (d21 / d22: every such hover was dropped for that).
static void DMPtrHoverSeen(UIHoverGestureRecognizer *g, BOOL learn) {
    UIView *v = g.view;
    UIWindow *w = [v isKindOfClass:[UIWindow class]] ? (UIWindow *)v : v.window;
    UIScreen *s = w.screen;
    if (!s || DMPtrSkipped()) return;
    BOOL inside = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    CFTimeInterval now = CACurrentMediaTime();
    gDMPtrAnyAt = now;
    if (s != [UIScreen mainScreen]) { gDMPtrSeen[1]++; gDMPtrOtherAt = now; return; }   // (another display's: the pointer there until now, its leaving included)
    if (!gDMPtrRegion.other) return;   // (the iPad alone: its region is the origin, nothing to learn or stand in for)
    gDMPtrSeen[0]++;
    if (!inside) { gDMPtrIPadLastAt = now; DMAutoHideIPadHover(CGPointZero, NO); return; }
    CGPoint n = [v convertPoint:[g locationInView:v] toCoordinateSpace:s.fixedCoordinateSpace];
    DMAutoHideIPadHover(n, YES);
    if (!learn) return;
    gDMPtrIPadLast = n; gDMPtrIPadLastAt = now;
    // (read only once the pointer has rested 0.2 s: backboardd's position runs a frame or so ahead of the hover UIKit hands us, so a reading taken
    //  while it moves is off by the move -- d24 learned {-1433, 597} for a moment from two such readings at one speed)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gDMPtrAnyAt == now) DMPtrLearnRead(); });
}
// Our hover on a system gestures window never stands in the way of iPadOS's own gestures there: a recognizer that begins may keep another on its view
// from beginning, and with ours on the iPad's window iPadOS's pointer push at the bottom edge (its indirect pan) no longer began (A12Z, d21-d23). It can
// prevent none and be prevented by none: it only watches.
@interface DMPtrHoverRecognizer : UIHoverGestureRecognizer
@end
@implementation DMPtrHoverRecognizer
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
@end
@interface DMPtrHover : NSObject
- (void)hover:(UIHoverGestureRecognizer *)g;
@end
@implementation DMPtrHover
- (void)hover:(UIHoverGestureRecognizer *)g { DMPtrHoverSeen(g, YES); }
@end
static const void *kDMPtrHoverKey = &kDMPtrHoverKey;
// The hovers on each display's system gestures window while another display has one; none (and the region at the origin) with the iPad alone. A
// display that came or went (screensChanged): the region is learned again.
static void DMPtrHoversUpdate(BOOL screensChanged) {
    if (DMPtrSkipped()) return;
    NSMutableArray<UIWindow *> *wins = [NSMutableArray array];
    BOOL other = NO;
    for (UIWindow *w in DMAllWindows()) {
        if (!w.screen || ![NSStringFromClass([w class]) isEqualToString:@"_UISystemGestureWindow"]) continue;
        [wins addObject:w];
        if (w.screen != [UIScreen mainScreen]) other = YES;
    }
    if (screensChanged || (other ? 1 : 0) != gDMPtrRegion.other) {
        BOOL was = gDMPtrRegion.other || gDMPtrRegion.ox != 0 || gDMPtrRegion.oy != 0;
        MSBDPtrRegionReset(&gDMPtrRegion, other);
        if (other || was) DMLog([NSString stringWithFormat:@"[ptrregion] %@: the iPad's region in the pointer's space %@", other ? @"another display shares the pointer" : @"the iPad alone", other ? @"to be learned from its own hover" : @"at the origin"]);
    }
    static DMPtrHover *sink;
    if (!sink) sink = [DMPtrHover new];
    for (UIWindow *w in wins) {
        UIHoverGestureRecognizer *h = objc_getAssociatedObject(w, kDMPtrHoverKey);
        if (other && !h) {
            h = [[DMPtrHoverRecognizer alloc] initWithTarget:sink action:@selector(hover:)];
            h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;
            [w addGestureRecognizer:h];
            objc_setAssociatedObject(w, kDMPtrHoverKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (!other && h) {
            [w removeGestureRecognizer:h];
            objc_setAssociatedObject(w, kDMPtrHoverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}
#if DEBUG
// ptrinfo (debug, read-only): the region, the last hovers, and the hovers' windows.
static void DMPtrInfo(void) {
    CFTimeInterval now = CACurrentMediaTime();
    NSMutableString *o = [NSMutableString stringWithFormat:@"[ptrregion] info: skipped %d other %d known %d origin {%.0f, %.0f} cand %d {%.0f, %.0f}; hovers seen iPad %lu other %lu; last on another display %.1f s ago, the iPad's last %@ %.1f s ago",
        DMPtrSkipped(), gDMPtrRegion.other, gDMPtrRegion.known, gDMPtrRegion.ox, gDMPtrRegion.oy, gDMPtrRegion.cand, gDMPtrRegion.cx, gDMPtrRegion.cy, gDMPtrSeen[0], gDMPtrSeen[1],
        gDMPtrOtherAt > 0 ? now - gDMPtrOtherAt : -1.0, NSStringFromCGPoint(gDMPtrIPadLast), gDMPtrIPadLastAt > 0 ? now - gDMPtrIPadLastAt : -1.0];
    for (UIWindow *w in DMAllWindows()) {
        if (![NSStringFromClass([w class]) containsString:@"Gesture"]) continue;
        UIHoverGestureRecognizer *h = objc_getAssociatedObject(w, kDMPtrHoverKey);
        [o appendFormat:@"\n  %@ %p on %@ hidden %d level %.0f: our hover %@ (state %ld, enabled %d)", NSStringFromClass([w class]), w, w.screen == [UIScreen mainScreen] ? @"the iPad" : @"another display", w.hidden, w.windowLevel, h ? @"on" : @"none", (long)h.state, h.enabled];
    }
    DMLog(o);
}
#endif
// At the start and whenever a display comes or goes (its system gestures window comes a moment after the screen: asked again).
static void DMPtrStart(void) {
    static BOOL started = NO;
    if (started || DMPtrSkipped()) return;
    started = YES;
    DMPtrHoversUpdate(YES);
    for (NSString *name in @[UIScreenDidConnectNotification, UIScreenDidDisconnectNotification])
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            DMPtrHoversUpdate(YES);
            for (NSNumber *d in @[@0.6, @2.5, @6.0]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMPtrHoversUpdate(NO); });
        }];
}
