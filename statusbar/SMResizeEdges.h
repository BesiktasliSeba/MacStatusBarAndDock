// SMResizeEdges.h -- a window's top resize zone at our title bar's outer edge, as on a Mac (1.5.2, item 7). Included by StatusBar.x after
// SMAfterHome.h; DMSMTitleBar (StatusBar.x) asks DMSMPointerOnResizeEdge before its drag takes a pointer press.
//   Stage Manager resizes a window with the pointer from bands around its content. SpringBoard's system pointer interaction
//   (SBSystemPointerInteractionManager) asks a window's page view (SBAppSwitcherPageView, registered with it) only for pointer positions within the
//   page's bounds grown by -pointerInteractionHitTestInsetsForView: (5 pt each side), and the page asks
//   +[SBEdgeResizeSystemPointerInteractionHelper shouldBeginPointerInteractionAtLocation:frame:...] with its own bounds as the frame (bands 5 pt
//   inside, 12.5 pt outside, corners 25 pt; read on 18.5 with synthetic region requests, ptrask_ / ptrtrace_). A hovered band marks the window's
//   container (-[SBFluidSwitcherItemContainer _updateForPointerHoveringOverEdge:] -> the switcher's -pointerBeganResizingItemContainer:), and the
//   next pointer press anywhere starts the live resize of that container (-[SBFluidSwitcherGestureManager
//   _shouldLiveResizeItemContainerGestureWithPointer:receiveTouch:] only asks -itemContainerToResizeUsingPointer). Our title bar sits above the
//   content and is part of the window, so the top band lay across the bar's LOWER edge and the window's real top edge had none (KT, 26 Oct: "it
//   feels like the window ends below the bar").
//   While our bar is on a window: the page's pointer hit area and the helper's frame reach up to the bar's top edge, so the top band and the top
//   corners are at the bar's outer edge (5 pt into the bar) and the bar's sides resize sideways; never over our traffic lights (their buttons are
//   theirs); the content's top edge is inside the window again. Our bar's own drag takes no pointer press while the pointer marks a resize band, so
//   the live resize takes it (a finger still moves the window).
//   Front to back (item 9): a window's zones answer only where no window in front of it covers the spot (DMSMEdgesCoveredBy, below). The same
//   for a FINGER's corner (1.7.9.2, GitHub #10: DMSMTouchCornersInstall, below).
//   Capability-checked: all three of Apple's methods with the signatures written for, else the zones stay Apple's (logged once).
#pragma once
#include "SMFrontRule.h"

static BOOL gSMEdgesHooked = NO;
static CGFloat gSMEdgesGrow = 0;   // (while a page with our bar answers a pointer request: how far the window's top is above its content)

// How far the window's top (our bar's outer edge) is above the page's own top, in the page's points; 0 when the window shows no bar of ours.
static CGFloat DMSMEdgesGrowFor(UIView *page) {
    if (!gSMEdgesHooked || !DMSMEngine() || !page) return 0;
    UIView *card = DMSMCardOfView(page);
    UIView *bar = card ? objc_getAssociatedObject(card, kSMBarKey) : nil;
    if (!bar || bar.hidden || bar.alpha < 0.01 || !bar.window || ![bar isDescendantOfView:card]) return 0;
    CGFloat top = [bar convertRect:bar.bounds toView:page].origin.y;
    return isfinite(top) && top < -1.0 && top > -60.0 ? -top : 0;
}
static UIEdgeInsets (*o_SMEdgesInsets)(id, SEL, id);
static UIEdgeInsets DMSMEdgesInsets(id self, SEL _cmd, id view) {
    UIEdgeInsets e = o_SMEdgesInsets(self, _cmd, view);
    CGFloat grow = DMSMEdgesGrowFor((UIView *)self);
    if (grow > 0) e.top -= grow;   // (insets are negative outward: the hit area reaches over the bar, to the same 5 pt above its top edge)
    return e;
}
static BOOL (*o_SMEdgesBegin)(id, SEL, id, CGPoint, id);
// (a pointer over one of our traffic lights is the light's, never a resize band: the top-left corner zone (25 pt) and the top band (5 pt) reach
//  over the lights once they are at the bar's edge -- the red light sits 8 pt in. Apple's own question is then asked for the window's middle, so
//  its answer is "no band" and the hovered edge it keeps for the window is cleared as for any other spot inside)
static BOOL DMSMEdgesOverLight(UIView *page, CGPoint location, UIView *view) {
    UIView *card = DMSMCardOfView(page);
    DMSMTitleBar *bar = card ? objc_getAssociatedObject(card, kSMBarKey) : nil;
    if (![bar isKindOfClass:[DMSMTitleBar class]] || !view) return NO;
    CGPoint p = [view convertPoint:location toView:bar];
    for (UIButton *b in bar.lights) if (!b.hidden && CGRectContainsPoint(b.frame, p)) return YES;
    return NO;
}
// Front to back (1.5.2 item 9, KT): SpringBoard's pointer manager asks the registered window pages in the order of its own table (an NSMapTable:
// no order on screen) and takes the first that answers yes, and a page asks only about its own window -- so a window BEHIND answered with its
// edges under the window in front (read on 18.5: -[SBSystemPointerInteractionManager pointerInteraction:window:regionForRequest:defaultRegion:]
// loops over _registeredViewsToDelegates; the page's container refuses only its own top affordance and floating elements). Every window page
// now answers only where no window in front of it covers the spot: that window's pointer area, i.e. where the manager would ask that window's
// page (its content, our bar, Apple's 5 pt ring for its own edges), so the window in front keeps all of its zones.
// a in front of b: at their common ancestor, the higher layer zPosition, then the later subview.
static BOOL DMSMViewInFrontOf(UIView *a, UIView *b) {
    if (!a || !b || a == b) return NO;
    NSMutableArray *chainB = [NSMutableArray array];
    for (UIView *v = b; v; v = v.superview) [chainB addObject:v];
    UIView *childA = a;
    for (UIView *v = a.superview; v; childA = v, v = v.superview) {
        NSUInteger j = [chainB indexOfObjectIdenticalTo:v];
        if (j == NSNotFound) continue;
        if (j == 0) return NO;   // (b holds a)
        UIView *childB = chainB[j - 1];
        if (childA.layer.zPosition != childB.layer.zPosition) return childA.layer.zPosition > childB.layer.zPosition;
        NSArray *subs = v.subviews;
        return [subs indexOfObjectIdenticalTo:childA] > [subs indexOfObjectIdenticalTo:childB];
    }
    return NO;   // (not in one window)
}
// The window card in front of this page's window whose pointer area holds the location (location in `view`'s points), or nil.
static UIView *DMSMEdgesCoveredBy(UIView *page, CGPoint location, UIView *view) {
    static SEL ins; if (!ins) ins = NSSelectorFromString(@"pointerInteractionHitTestInsetsForView:");
    UIView *card = DMSMCardOfView(page);
    if (!card || !card.window || !view) return nil;
    for (UIView *other in gSMCards.allObjects) {
        if (other == card || other.window != card.window || !DMSMViewShown(other) || !DMSMViewInFrontOf(other, card)) continue;   // (StatusBar.x: shown on screen)
        UIView *op = (UIView *)DMSMPageViewOf(other);
        if (!op || !DMSMViewShown(op)) continue;
        UIEdgeInsets e = [op respondsToSelector:ins] ? ((UIEdgeInsets (*)(id, SEL, id))objc_msgSend)(op, ins, op) : UIEdgeInsetsMake(-5, -5, -5, -5);
        if (CGRectContainsPoint(UIEdgeInsetsInsetRect(op.bounds, e), [view convertPoint:location toView:op])) return other;
    }
    return nil;
}
static BOOL DMSMEdgesBegin(id self, SEL _cmd, id request, CGPoint location, id view) {
    CGFloat was = gSMEdgesGrow;
    gSMEdgesGrow = DMSMEdgesGrowFor((UIView *)self);
    UIView *cover = DMSMEngine() && [view isKindOfClass:[UIView class]] ? DMSMEdgesCoveredBy((UIView *)self, location, (UIView *)view) : nil;
#if DEBUG
    if (cover && DMTestFlag("/tmp/msb-edges-anyorder")) cover = nil;   // (debug: SpringBoard's own pick, for a before / after on one build)
#endif
    if (cover) DM_FEATURE_MARK("sm-resize-front-to-back");
    if (cover || (gSMEdgesGrow > 0 && [view isKindOfClass:[UIView class]] && DMSMEdgesOverLight((UIView *)self, location, (UIView *)view))) {
        CGRect b = ((UIView *)self).bounds;   // (Apple's own answer for the window's middle: no band, and the hovered edge it keeps is cleared)
        location = [(UIView *)self convertPoint:CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b)) toView:(UIView *)view];
    }
#if DEBUG
    if (DMTestFlag("/tmp/msb-edgesdebug")) DMLog([NSString stringWithFormat:@"[edges] page %p asked at %@: grow %.2f%@", self, NSStringFromCGPoint(location), gSMEdgesGrow,
        cover ? [NSString stringWithFormat:@", covered by %@", DMSMCardKey(cover) ?: @"a window in front"] : @""]);
#endif
    BOOL r = NO;
    @try { r = o_SMEdgesBegin(self, _cmd, request, location, view); }
    @finally { gSMEdgesGrow = was; }
    return r;
}
static BOOL (*o_SMEdgesHelper)(id, SEL, CGPoint, CGRect, double, double, double, unsigned long long, unsigned long long *, CGRect *);
static BOOL DMSMEdgesHelper(id self, SEL _cmd, CGPoint location, CGRect frame, double inner, double outer, double corner, unsigned long long occupied, unsigned long long *edge, CGRect *region) {
#if DEBUG
    if (DMTestFlag("/tmp/msb-edgesdebug")) DMLog([NSString stringWithFormat:@"[edges] helper at %@ frame %@ grow %.2f", NSStringFromCGPoint(location), NSStringFromCGRect(frame), gSMEdgesGrow]);
#endif
    CGFloat grow = gSMEdgesGrow;
    if (grow <= 0 || CGRectIsNull(frame)) return o_SMEdgesHelper(self, _cmd, location, frame, inner, outer, corner, occupied, edge, region);
    // (only inside our page's own question. The helper measures from the frame's size alone -- its origin is not used (18.5: a frame moved up
    //  gave the same bands) -- so the window is given to it from our bar's top edge down: the location moved down by the bar, the frame as tall as
    //  bar and content, and the band it hands back moved up again into the page's points)
    DM_FEATURE_MARK("sm-resize-top-at-bar");
    CGRect whole = CGRectMake(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height + grow);
    BOOL r = o_SMEdgesHelper(self, _cmd, CGPointMake(location.x, location.y + grow), whole, inner, outer, corner, occupied, edge, region);
    if (region && !CGRectIsNull(*region)) region->origin.y -= grow;
    return r;
}
// The pointer's next press is SpringBoard's live resize of a window: our bar's drag leaves that press alone. While a resize band of a window is
// hovered, its container tells the switcher (its delegate: -pointerBeganResizingItemContainer:, and -pointerEndedResizingItemContainer: when the
// band is left), and every pointer press then resizes that window (-[SBFluidSwitcherGestureManager _shouldLiveResizeItemContainerGestureWithPointer:
// receiveTouch:] asks for a pointer touch and that container, not where the press is). That can be a band of a window BEHIND this one: Apple asks
// every window under the pointer, front to back, and only a window's own top affordance keeps its band away (18.5, read from
// -[SBFluidSwitcherItemContainer appSwitcherPageView:shouldBeginPointerInteractionAtLocation:window:]) -- so the switcher's answer is the one asked;
// this window's own hovered edge only where the switcher cannot be asked.
static BOOL DMSMPointerOnResizeEdge(UIView *card) {
    static SEL hov, del, res;
    if (!hov) { hov = NSSelectorFromString(@"pointerIsHoveringOverEdge"); del = NSSelectorFromString(@"delegate"); res = NSSelectorFromString(@"itemContainerToResizeUsingPointer"); }
    if (!gSMEdgesHooked || !card) return NO;
    NSString *obj = DMSMExpect(@encode(id), NULL);
    Method md = class_getInstanceMethod(object_getClass(card), del);
    id sw = md && [DMSMSigOfMethod(md) isEqualToString:obj] ? ((id (*)(id, SEL))objc_msgSend)(card, del) : nil;
    Method mr = sw ? class_getInstanceMethod(object_getClass(sw), res) : NULL;
    if (mr && [DMSMSigOfMethod(mr) isEqualToString:obj]) return ((id (*)(id, SEL))objc_msgSend)(sw, res) != nil;
    Method mh = class_getInstanceMethod(object_getClass(card), hov);
    if (!mh || ![DMSMSigOfMethod(mh) isEqualToString:DMSMExpect(@encode(unsigned long long), NULL)]) return NO;
    return ((unsigned long long (*)(id, SEL))objc_msgSend)(card, hov) != 0;
}
static void DMSMEdgesInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class page = objc_getClass("SBAppSwitcherPageView"), helper = objc_getClass("SBEdgeResizeSystemPointerInteractionHelper");
    SEL si = sel_registerName("pointerInteractionHitTestInsetsForView:"), sb = sel_registerName("shouldBeginPointerInteractionRequest:atLocation:forView:");
    SEL sh = sel_registerName("shouldBeginPointerInteractionAtLocation:frame:innerLengthOfInteractionRegion:outerLengthOfInteractionRegion:cornerLengthOfInteractionRegion:occupiedCorners:hoveringOverEdge:pointerRegion:");
    Method mi = page ? class_getInstanceMethod(page, si) : NULL, mb = page ? class_getInstanceMethod(page, sb) : NULL, mh = helper ? class_getClassMethod(helper, sh) : NULL;
    BOOL ok = mi && mb && mh
           && [DMSMSigOfMethod(mi) isEqualToString:DMSMExpect(@encode(UIEdgeInsets), @encode(id), NULL)]
           && [DMSMSigOfMethod(mb) isEqualToString:DMSMExpect(@encode(BOOL), @encode(id), @encode(CGPoint), @encode(id), NULL)]
           && [DMSMSigOfMethod(mh) isEqualToString:DMSMExpect(@encode(BOOL), @encode(CGPoint), @encode(CGRect), @encode(double), @encode(double), @encode(double), @encode(unsigned long long), "o^Q", "o^{CGRect={CGPoint=dd}{CGSize=dd}}", NULL)];
    if (!ok) {
        DMLog([NSString stringWithFormat:@"[smengine] the pointer's window-edge resize zones are not as expected here (page %d %d, helper %d): the top zone stays at the content's edge", mi != NULL, mb != NULL, mh != NULL]);
        return;
    }
    MSHookMessageEx(page, si, (IMP)DMSMEdgesInsets, (IMP *)&o_SMEdgesInsets);
    MSHookMessageEx(page, sb, (IMP)DMSMEdgesBegin, (IMP *)&o_SMEdgesBegin);
    MSHookMessageEx(object_getClass((id)helper), sh, (IMP)DMSMEdgesHelper, (IMP *)&o_SMEdgesHelper);
    gSMEdgesHooked = o_SMEdgesInsets && o_SMEdgesBegin && o_SMEdgesHelper;
    DMLog(gSMEdgesHooked ? @"[smengine] a window's top resize zone is at the title bar's outer edge (pointer)" : @"[smengine] the window-edge resize hooks did not all go in");
}
// ---- a finger's resize corner (1.7.9.2, GitHub #10) ----
// Stage Manager's finger resize (-[SBFluidSwitcherGestureManager _shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:], read on 16.3.1
// 20D67 and 17.5.1) asks the switcher for the window whose CORNER is nearest the finger (-[SBFluidSwitcherViewController _itemContainerNearestLocation:
// environment:prioritizeForegroundedItemContainers:]: the windows on screen sorted by the finger's distance to their nearest corner, the first one)
// and takes the touch when the finger is in that window's corner zone (a square of 50 pt and the screen edge padding, 10 pt in from the corner); the
// resize's own begin (-[SBLiveWindowResizeGestureWorkspaceTransaction _beginWithGesture:]) and its gesture's gates ask the same, and nothing else
// does (16.3.1, 17.5.1). Which window the finger is ON is not asked: only the windows Stage Manager marks occluded in its stage are passed over
// (-isOccludedInContinuousExposeStage, with "prioritize foregrounded"), and Stage Manager's own layout keeps a window's corners out from under the
// others. Ours places windows freely, so a
// small window behind a big one keeps its corners under it: a drag on the big window there resized the small one, which jumped to the front (GitHub
// #10, iPad Air 5 16.3.1; the same on 17.5.1). While the switcher looks for that window, a window covered at the finger by a window in front of it
// counts as occluded: Apple's own rule passes over it, and the nearest corner of the windows the finger can reach there is the one asked -- the window
// in front keeps every zone of its own, a back window's corner that shows still takes the finger, a touch on the front window is that window's.
// Optional: both methods with the signatures written for, else Apple's pick (logged once). Debug /tmp/msb-corners-anyorder: Apple's pick, to compare.
static struct { BOOL on; __unsafe_unretained UIView *space; CGPoint at; } gSMNearAsk;
// The card is covered at `at` (in space's points) by a window card in front of it, as drawn: the card and our title bar above it.
static BOOL DMSMCardCoveredAt(UIView *card, CGPoint at, UIView *space) {
    if (!card.window || !space || !isfinite(at.x) || !isfinite(at.y)) return NO;
    CGRect fronts[32]; int n = 0;
    for (UIView *other in gSMCards.allObjects) {
        if (n >= 32) break;
        if (other == card || other.window != card.window || !DMSMViewShown(other) || !DMSMViewInFrontOf(other, card)) continue;   // (StatusBar.x: shown on screen)
        CGRect r = [other convertRect:other.bounds toView:space];
        UIView *bar = objc_getAssociatedObject(other, kSMBarKey);
        if (bar && !bar.hidden && bar.alpha >= 0.01 && [bar isDescendantOfView:other]) r = CGRectUnion(r, [bar convertRect:bar.bounds toView:space]);
        fronts[n++] = r;
    }
    return MSBDSMCoveredAt(at, fronts, n);
}
static id (*o_SMNearest)(id, SEL, CGPoint, long long, BOOL);
static id DMSMNearest(id self, SEL _cmd, CGPoint at, long long env, BOOL fore) {
    if (!fore || gSMNearAsk.on || !DMSMFree() || ![self isKindOfClass:[UIViewController class]] || ![(UIViewController *)self isViewLoaded]) return o_SMNearest(self, _cmd, at, env, fore);
#if DEBUG
    if (DMTestFlag("/tmp/msb-corners-anyorder")) return o_SMNearest(self, _cmd, at, env, fore);
#endif
    gSMNearAsk.on = YES; gSMNearAsk.space = [(UIViewController *)self view]; gSMNearAsk.at = at;
    id r = nil;
    @try { r = o_SMNearest(self, _cmd, at, env, fore); }
    @finally { gSMNearAsk.on = NO; gSMNearAsk.space = nil; }
#if DEBUG
    if (DMTestFlag("/tmp/msb-edgesdebug")) DMLog([NSString stringWithFormat:@"[edges] finger at %@: the nearest corner's window %@", NSStringFromCGPoint(at), [r isKindOfClass:[UIView class]] ? (DMSMCardKey((UIView *)r) ?: @"(no key)") : @"none"]);
#endif
    return r;
}
static BOOL (*o_SMOccluded)(id, SEL);
static BOOL DMSMOccluded(id self, SEL _cmd) {
    BOOL r = o_SMOccluded(self, _cmd);
    if (r || !gSMNearAsk.on || ![self isKindOfClass:[UIView class]] || !DMSMCardCoveredAt((UIView *)self, gSMNearAsk.at, gSMNearAsk.space)) return r;
    DM_FEATURE_MARK("sm-touch-corner-front-to-back");
#if DEBUG
    if (DMTestFlag("/tmp/msb-edgesdebug")) DMLog([NSString stringWithFormat:@"[edges] finger at %@: %@ is covered there -- its corners are passed over", NSStringFromCGPoint(gSMNearAsk.at), DMSMCardKey((UIView *)self) ?: @"a window"]);
#endif
    return YES;
}
static void DMSMTouchCornersInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class vc = objc_getClass("SBFluidSwitcherViewController"), ic = objc_getClass("SBFluidSwitcherItemContainer");
    SEL sn = sel_registerName("_itemContainerNearestLocation:environment:prioritizeForegroundedItemContainers:"), so = sel_registerName("isOccludedInContinuousExposeStage");
    Method mn = vc ? class_getInstanceMethod(vc, sn) : NULL, mo = ic ? class_getInstanceMethod(ic, so) : NULL;
    BOOL ok = mn && mo
           && [DMSMSigOfMethod(mn) isEqualToString:DMSMExpect(@encode(id), @encode(CGPoint), @encode(long long), @encode(BOOL), NULL)]
           && [DMSMSigOfMethod(mo) isEqualToString:DMSMExpect(@encode(BOOL), NULL)];
    if (!ok) {
        DMLog([NSString stringWithFormat:@"[smengine] a finger's resize corner is not looked for as expected here (nearest %d, occluded %d): a covered window's corner keeps Apple's pick", mn != NULL, mo != NULL]);
        return;
    }
    MSHookMessageEx(vc, sn, (IMP)DMSMNearest, (IMP *)&o_SMNearest);
    MSHookMessageEx(ic, so, (IMP)DMSMOccluded, (IMP *)&o_SMOccluded);
    DMLog(o_SMNearest && o_SMOccluded ? @"[smengine] a finger's resize corner: only where no window in front covers it" : @"[smengine] the finger's resize corner hooks did not all go in");
}
