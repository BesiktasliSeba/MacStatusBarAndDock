// BarReveal.h (included at the end of StatusBar.x) -- the menu bar over a full-screen app that hides it, on a deliberate gesture (1.8.4.3 item 12).
// The rules are common/BarReveal.h. How it shows: the same way as our bar over a game with a window in front of it (DMWatchBarOverHidingApp):
// SpringBoard is told the app's status bar is not hidden, so it draws ours, with the app's traffic lights, over the app; nothing is sent to the app.
// The pointer: its push against the top edge is seen by the Cover Sheet's pointer recogniser where the app lets it begin (refused then, as the
// auto-hiding bar does, so the push shows the bar instead of the Notification Center), and by backboardd's pointer place, read once per tick only
// while such an app is in front and a pointer is attached (an app that defers the system gestures may keep that recogniser from beginning).
// Touch: SpringBoard sees every touch (its system gesture window); a swipe down from the very top edge is watched there and never held back.
// Off for testing: /tmp/msb-nobarreveal.
#include "../common/BarReveal.h"

static NSString *gBarRevealApp = nil;        // the app whose bar shows now by this gesture
static NSString *gBarRevealCandidate = nil;  // the app in front that hides its bar (from the last tick): only then is anything watched
static int gBarRevealBy = 0;
static CFTimeInterval gBarRevealAt = 0, gBarRevealLeftAt = 0, gBarRevealLastUse = 0;
static BOOL gBarRevealTouchedBelow = NO;
static int gBarRevealZone = 0;
static CGPoint gBarRevealLastPt = {-1, -1};   // (the pointer's last place since this app came to the front: only a move to the edge counts)
static const void *kDMBarOrigHiddenKey = &kDMBarOrigHiddenKey;

// The app's own answer (before ours): DMBarHiddenAnswer notes it on the provider.
static void DMBarNoteOrigHidden(id provider, BOOL hidden) {
    NSNumber *was = objc_getAssociatedObject(provider, kDMBarOrigHiddenKey);
    if (was && was.boolValue == hidden) return;
    objc_setAssociatedObject(provider, kDMBarOrigHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL DMBarAppHidesBar(NSString *bundle) {
    if (!bundle.length) return NO;
    for (id p in gHiddenBarProviders.allObjects)
        if (DMBarProviderIsFor(p, bundle) && [objc_getAssociatedObject(p, kDMBarOrigHiddenKey) boolValue]) return YES;
    return NO;
}
static BOOL DMBarRevealAllowed(void) { return !gStockBar && !DMTestFlag("/tmp/msb-nobarreveal") && DMScreenOnAndUnlocked() && !DMSwitcherVisible(); }
static void DMBarRevealShow(NSString *bundle, int by, NSString *why) {
    if (!bundle.length || [gBarRevealApp isEqualToString:bundle]) { if (gBarRevealApp) gBarRevealLastUse = CACurrentMediaTime(); return; }
    gBarRevealApp = [bundle copy]; gBarRevealBy = by;
    gBarRevealAt = CACurrentMediaTime(); gBarRevealLastUse = 0; gBarRevealLeftAt = 0; gBarRevealTouchedBelow = NO;
    DM_FEATURE_MARK("bar-reveal-over-full-screen");
    DMLog([NSString stringWithFormat:@"[barreveal] %@: the menu bar shows over it (%@)", bundle, why]);
    DMBarOverHidingApply();   // (at once, not at the next tick)
}
static void DMBarRevealEnd(NSString *why) {
    if (!gBarRevealApp) return;
    DMLog([NSString stringWithFormat:@"[barreveal] %@: the menu bar goes again (%@)", gBarRevealApp, why]);
    gBarRevealApp = nil; gBarRevealBy = 0;
    DMBarOverHidingApply();
}
static BOOL DMBarRevealWants(NSString *front) { return front.length && [gBarRevealApp isEqualToString:front]; }

// The pointer's place, read off the main thread (one small query per tick while it matters).
static void DMBarRevealPollPointer(void) {
    static dispatch_queue_t q; static BOOL busy;
    if (busy) return;
    Class c = objc_getClass("BKSMousePointerService");
    if (!c || ![c respondsToSelector:@selector(sharedInstance)]) return;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.macstatusbar.barreveal", DISPATCH_QUEUE_SERIAL);
    busy = YES;
    dispatch_async(q, ^{
        id svc = ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance));
        SEL sel = sel_registerName("globalPointerPosition");
        Method m = svc ? class_getInstanceMethod(object_getClass(svc), sel) : NULL;
        BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{CGPoint=dd}16@0:8");
        CGPoint p = known ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, sel) : CGPointMake(-1, -1);
        dispatch_async(dispatch_get_main_queue(), ^{
            busy = NO;
            CGPoint n;   // (1.8.7: in the iPad's own region of backboardd's space, PointerRegion.h -- not at its origin while another display shares it)
            int z = known && DMPtrIPadNative(p, &n) > 0 ? MSBDRevealZone(DMAutoHidePointerY(n), DMMenuBarHeight()) : 0;
            if (z != gBarRevealZone && (z == 3 || z == 0)) gBarRevealLeftAt = CACurrentMediaTime();
            // (a pointer that was already resting at the edge when the app came to the front is no push: M1, 10 Nov, the bar showed as a game
            //  opened. Only a pointer seen somewhere else first and then at the edge counts)
            BOOL moved = gBarRevealLastPt.x >= 0 && (fabs(p.x - gBarRevealLastPt.x) > 0.5 || fabs(p.y - gBarRevealLastPt.y) > 0.5);
            gBarRevealLastPt = p;
            gBarRevealZone = z;
            if (z == 1 && moved && gBarRevealCandidate && DMBarRevealAllowed()) DMBarRevealShow(gBarRevealCandidate, kMSBDRevealByPointer, @"the pointer pushed against the top edge");
        });
    });
}

// Every tick, from DMWatchBarOverHidingApp: what is in front, and whether a bar shown by a gesture goes.
static void DMBarRevealTick(NSString *front) {
    // (in front full screen: with the Stage Manager engine, the stage's full-screen window is the front one -- DMBarFrontBundle; the other engines'
    //  check looks for a window of theirs)
    BOOL full = DMSMEngine() ? DMSMFrontIsFullScreen() : DMFullScreenAppInFront();
    BOOL hides = front.length && gHiddenBarProviders.count && DMBarAppHidesBar(front) && full;
    if (!hides || ![gBarRevealCandidate isEqualToString:front]) gBarRevealLastPt = CGPointMake(-1, -1);   // (a new app in front: the pointer's place from now on)
    gBarRevealCandidate = hides ? [front copy] : nil;
    if (!hides && !gBarRevealApp) return;   // (nothing to watch: the usual case costs one look at the providers)
    if (gBarRevealApp && (![gBarRevealApp isEqualToString:front] || !hides || !DMBarRevealAllowed())) { DMBarRevealEnd(@"the app left the front, or the screen locked"); return; }
    if (hides && gDMPointerAttached && DMBarRevealAllowed()) DMBarRevealPollPointer();
    if (!gBarRevealApp) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (gBarRevealZone == 1 || gBarRevealZone == 2) gBarRevealLastUse = now;
    if (MSBDRevealEnds(gBarRevealBy, now, gBarRevealAt, gBarRevealZone, gBarRevealLeftAt, gOverlay != nil, gBarRevealLastUse, gBarRevealTouchedBelow))
        DMBarRevealEnd(gBarRevealTouchedBelow ? @"the app was touched" : (gBarRevealBy == kMSBDRevealByPointer ? @"the pointer left the bar" : @"not used for a moment"));
}

// The Cover Sheet's pointer recogniser (StatusBar.x's PointerPull hook): a push against the top edge over such an app shows the bar instead.
static BOOL DMBarRevealPointerPull(void) {
    if (!gBarRevealCandidate || !DMBarRevealAllowed()) return NO;
    DMBarRevealShow(gBarRevealCandidate, kMSBDRevealByPointer, @"the pointer pushed against the top edge (Cover Sheet's pointer pull)");
    gBarRevealZone = 1;
    return YES;
}

// A finger: watched in SpringBoard's sendEvent:, never held back.
static struct { __unsafe_unretained UITouch *t; CGPoint start; NSTimeInterval at; BOOL live; } gBarRevealFinger;
static CGPoint DMBarRevealScreenPoint(UITouch *touch) {
    UIWindow *w = touch.window;
    if (!w || !w.screen) return CGPointMake(-1, -1);
    return [w convertPoint:[touch locationInView:w] toCoordinateSpace:w.screen.coordinateSpace];
}
static void DMBarRevealSeeTouches(UIEvent *event) {
    if (!gBarRevealCandidate && !gBarRevealApp) { gBarRevealFinger.live = NO; return; }   // (nothing to watch: no such app in front; a finger being watched is let go, review 1.8.4.3 M1)
    for (UITouch *t in event.allTouches) {
        if (t.type != UITouchTypeDirect && t.type != UITouchTypeIndirectPointer) continue;
        if (t.window.screen && t.window.screen != [UIScreen mainScreen]) continue;
        CGPoint p = DMBarRevealScreenPoint(t);
        if (p.y < 0) continue;
        if (t.phase == UITouchPhaseBegan) {
            if (gBarRevealApp) {
                if (p.y <= DMMenuBarHeight() + 2.0) gBarRevealLastUse = CACurrentMediaTime();   // (the bar or its menus in use)
                else if (!gOverlay) gBarRevealTouchedBelow = YES;                               // (the app touched: back to it)
            }
            if (gBarRevealFinger.live && t.timestamp - gBarRevealFinger.at > kMSBDRevealSwipeTime) gBarRevealFinger.live = NO;   // (a finger whose end was never seen: stale)
            if (t.type == UITouchTypeDirect && !gBarRevealFinger.live && p.y <= kMSBDRevealSwipeStart) {
                gBarRevealFinger.t = t; gBarRevealFinger.start = p; gBarRevealFinger.at = t.timestamp; gBarRevealFinger.live = YES;
            }
        } else if (gBarRevealFinger.live && t == gBarRevealFinger.t) {
            if (MSBDRevealSwipe(gBarRevealFinger.start.y, p.x - gBarRevealFinger.start.x, p.y - gBarRevealFinger.start.y, t.timestamp - gBarRevealFinger.at)) {
                gBarRevealFinger.live = NO;
                if (gBarRevealCandidate && DMBarRevealAllowed()) DMBarRevealShow(gBarRevealCandidate, kMSBDRevealByTouch, @"a swipe down from the top edge");
            }
            if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled || t.timestamp - gBarRevealFinger.at > kMSBDRevealSwipeTime) gBarRevealFinger.live = NO;
        }
    }
}
static void (*o_DMBarRevealSendEvent)(id, SEL, UIEvent *) = NULL;
static void DMBarRevealSendEvent(id self_, SEL cmd, UIEvent *event) {
    if (event.type == UIEventTypeTouches) DMBarRevealSeeTouches(event);   // (looked at only; the event goes on unchanged)
    o_DMBarRevealSendEvent(self_, cmd, event);
}
static void DMBarRevealInit(void) {
    Class sb = objc_getClass("SpringBoard");
    Method m = sb ? class_getInstanceMethod(sb, @selector(sendEvent:)) : NULL;
    if (gStockBar || !m || strcmp(method_getTypeEncoding(m) ?: "", "v24@0:8@16")) return;
    MSHookMessageEx(sb, @selector(sendEvent:), (IMP)DMBarRevealSendEvent, (IMP *)&o_DMBarRevealSendEvent);
}
