// TitleBarTap.h -- a double tap on a window's title bar (Settings > Windows & Multitasking > Double-Tap a Title Bar to, 1.8.3 item 8): Fill (and
// back), Zoom (and back), Minimize or nothing, as macOS's own setting (the choices, the default and why: TitleBarRule.h). The same on every engine
// and on our own windows. Included at the end of StatusBar.x, after WindowKeys.h, whose ways it shares (Fill and Zoom go back with their own frame
// from before, kept in step with every placement of ours: TitleBarRule.h, WindowKeys.h DMTitleRecord...).
// Where each title bar is, and what was there before (read on the iPads, plans/v183.md item 8):
//  - our own windows (Finder, TextEdit: NativeWindow.h): their title bar zoomed on a double tap -- it still does while the setting is never set,
//    and follows it once a choice is made (app windows do nothing then: review 1.8.3 P2-3);
//  - Stage Manager: the title bar is ours (DMSMTitleBar): nothing before;
//  - Aerial 5.x and 3.0: the title strip of the window's stage (where a drag moves the window, DMA5DragAllowedAt / Aerial 3.0's top bar): Aerial 5.0
//    did nothing on a double tap there (M1, 15.6.1);
//  - MilkyWay4: its title bar (AXWindowView -titleBar) had none: its own double tap (-sizeChangeDoubleTap:) is on the resize grip in the
//    window's corner, which keeps it; it turns MilkyWay4's aspect-ratio lock on or off and is no maximize (MilkyWay4's maximize is its green
//    light, -maxButtonAction:, which ours turns into full screen) (M1, 15.6.1, 7 Nov);
//  - Zetsu: its top bar (the controller's -menu, where our lights are) had none either (M1, 7 Nov).
//  A double tap of the engine's own on the bar itself, should a version add one, is switched off while ours is there: one double tap, one action.
// Each gets one double-tap recogniser of ours, which waits for nothing and lets every other recogniser go on (the window's drag, a tap that
// brings it forward) and never takes a touch on a traffic light.
#pragma once
#include "TitleBarRule.h"

static char kTitleTapKindKey, kTitleTapMineKey;   // (the frame from before: kWinZoomKey, WindowKeys.h)

// ---- one double tap on one window ----
static void DMTitleTapNative(DMNativeWindow *w, NSString *why) {
    int action = MSBDTitleActionFor(gTitleDoubleTap, true);   // (our own window: Zoom while never set, as before 1.8.3)
    if (action == kMSBDTitleZoom) { [w zoom]; return; }   // (its own zoom: the desktop and back, as before)
    if (action == kMSBDTitleMinimize) { [w minimize]; return; }
    if (action != kMSBDTitleFill) return;
    CGRect fill = DMLayoutFrameInArea(@"fill", DMNativeDesktop(), [UIScreen mainScreen].bounds.size);
    BOOL atFill = MSBDWinNear(w.frame, fill);
    NSValue *rec = DMTitleRecordHeldView(w, w.frame, w.title ?: @"our window");   // (the frame it had just before Fill -- a tile too, regression F2 -- while it holds, P4-1)
    int step = MSBDTitleStep(action, atFill, rec != nil);
    if (step == kMSBDTitleBack) {
        w.restoreFrame = CGRectNull; w.layoutName = nil;
        CGRect f = rec.CGRectValue;
        DMTitleRecordNativeTo(w, f);   // (back: dropped)
        MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ w.frame = f; }, nil);
        DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ back to %@", why, w.title ?: @"our window", NSStringFromCGRect(f)]);
        return;
    }
    DMNativeLayout(w, @"fill");   // (the frame from before taken there, as for every Fill of ours; Return to Previous Size's too, while the window keys want it)
    DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ at Fill", why, w.title ?: @"our window"]);
}
static void DMTitleTapSMWindow(NSString *key, NSString *why) {
    int action = MSBDTitleActionFor(gTitleDoubleTap, false);   // (an app's window: nothing while never set, review 1.8.3 P2-3)
    if (!key.length || action == kMSBDTitleNothing) return;
    key = DMSMWindowKeyOf(key);   // (a bar that knows only its app: the app's newest window -- a record by the app's key outlived its window, P2-5)
    if (action == kMSBDTitleMinimize) { BOOL ok = DMSMWindowAction(key, @"removeFromSet"); DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ minimized (%@)", why, DMSMKeyText(key), ok ? @"done" : @"refused"]); return; }
    id stage = DMSMStageOf(key), attrs = nil;
    NSValue *now = DMSMOpenWindowFrames()[key];
    if (!now || !DMSMItemFor(stage, key, &attrs) || !attrs || DMSMAttrsFullScreen(attrs)) { DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ has no window to fill (full screen or away)", why, DMSMKeyText(key)]); return; }
    CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr);
    BOOL atFill = MSBDWinNear(now.CGRectValue, DMSMLayoutFrameIn(@"fill", u, scr));
    BOOL zoom = action == kMSBDTitleZoom;
    NSValue *rec = DMTitleRecordHeldSM(key, now.CGRectValue);   // (Fill's and Zoom's: the frame it had just before -- a Fit tile too, regression F2 -- while it holds, P4-1)
    int step = MSBDTitleStep(action, atFill, rec != nil);
    for (NSString *k in [gSMTurnPlaced allKeys]) if (DMSMKeyCovers(key, k)) [gSMTurnPlaced removeObjectForKey:k];   // (placed now, as a layout)
    if (step == kMSBDTitleBack) {
        DMTitleRecordSMTo(key, stage, rec.CGRectValue);   // (back: dropped)
        BOOL ok = DMSMApplyPlacesIn(@{key: rec}, stage);
        if (ok) DMSMFitLetGo(key);   // (placed by the user: no longer one of Fit to Window's tiles, as with the other engines)
        DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ back to %@ (%@)", why, DMSMKeyText(key), NSStringFromCGRect(rec.CGRectValue), ok ? @"done" : @"not in the stage"]);
        return;
    }
    DMTitleRecordSMTo(key, stage, DMSMLayoutFrameIn(@"fill", u, scr));   // (to Fill: the frame now kept, MSBDTitleBackTakes -- as for every Fill of ours)
    if (!zoom) DMWinPrevNoteSM(key, stage);   // (Fill: Return to Previous Size's record as the Window menu's Fill takes it, while the keys want it)
    BOOL ok = DMSMApplyLayoutsIn(@{key: @"fill"}, stage);
    if (ok) DMSMFitLetGo(key);   // (as above)
    DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ at Fill (%@%@)", why, DMSMKeyText(key), zoom ? @"Zoom" : @"Fill", ok ? @"" : @", not in the stage"]);
}
// Aerial's, Zetsu's and MilkyWay4's windows: the engine's window view of that app.
static void DMTitleTapEngineWindow(NSString *bundleID, NSString *why) {
    int action = MSBDTitleActionFor(gTitleDoubleTap, false);   // (an app's window: nothing while never set, review 1.8.3 P2-3)
    if (!bundleID.length || action == kMSBDTitleNothing) return;
    UIView *v = DMActiveEngine() == DMEngineZetsu ? DMZetsuWindowFor(bundleID) : DMActiveEngine() == DMEngineAerial ? DMStageForBundle(bundleID) : DMFindMilkyWayWindow(bundleID);
    if (!v || v.hidden || DMStageMinimized(v) || DMWindowMinimized(v)) return;
    if (action == kMSBDTitleMinimize) {
        if (DMActiveEngine() == DMEngineMilkyWay) DMMinimizeWindow(v); else DMMinimizeStage(v);
        DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ minimized", why, bundleID]);
        return;
    }
    CGRect fill = DMLayoutFrame(@"fill");   // (the engine's frames: Aerial 5.x's stage)
    if (CGRectIsNull(fill)) return;
    BOOL atFill = MSBDWinNear(v.frame, fill), zoom = action == kMSBDTitleZoom;
    NSValue *rec = DMTitleRecordHeldView(v, v.frame, bundleID);   // (Fill's and Zoom's: the frame it had just before -- a Fit tile too, regression F2 -- while it holds, P4-1)
    int step = MSBDTitleStep(action, atFill, rec != nil);
    CGRect to = step == kMSBDTitleBack ? rec.CGRectValue : fill;
    DMTitleRecordEngineTo(v, to);   // (to Fill: the frame now kept, MSBDTitleBackTakes; back: dropped -- as for every placement of ours)
    if (step != kMSBDTitleBack && !zoom) DMWinPrevNoteView(v, DMWinTiledEngine(v.frame), v.frame);   // (Fill: Return to Previous Size's record, as the Window menu's Fill)
    objc_setAssociatedObject(v, &kStageTurnPlacedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (placed now, as a layout)
    DMFitGroupForget(bundleID);   // (placed by the user: no longer one of Fit to Window's tiles, as a layout of its own)
    DMAerialMoveStage(v, to, nil);
    if (DMActiveEngine() == DMEngineAerial && gAerialFlavor == 5 && !DMTestFlag("/tmp/msb-a5-nohold")) DMA5HoldStageAt(v, to, CACurrentMediaTime() + 1.5);   // (as a Window menu layout)
    DMLog([NSString stringWithFormat:@"[titlebar] %@: %@ %@ %@ (%@)", why, bundleID, step == kMSBDTitleBack ? @"back to" : @"at Fill", NSStringFromCGRect(to), zoom ? @"Zoom" : @"Fill"]);
}

// ---- the recogniser ----
// The double tap's action now, or -- while SpringBoard is in a state that passes by itself, as the transition its own first tap can start --
// once that is over (TitleBarRule.h MSBDTitleTapWhen); refused in the other states.
static void DMTitleTapWhenFree(void (^act)(NSString *), int tries) {
    BOOL passing = NO;
    NSString *busy = DMWindowAPIBusyWhyPassing(&passing);
    switch (MSBDTitleTapWhen(busy != nil, passing, tries)) {
        case kMSBDTitleTapNow: {
            DM_FEATURE_MARK("title-bar-double-tap");
            if (tries) DM_FEATURE_MARK("title-bar-double-tap-waited");
            act([NSString stringWithFormat:@"double tap on the title bar (%s%@)", MSBDTitleActionName(gTitleDoubleTap), tries ? [NSString stringWithFormat:@", after %.1f s of a transition", tries * kMSBDTitleTapWaitSeconds] : @""]);
            return;
        }
        case kMSBDTitleTapWait: {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMSBDTitleTapWaitSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMTitleTapWhenFree(act, tries + 1); });
            return;
        }
        default: {
            DMLog([NSString stringWithFormat:@"[titlebar] double tap: not now (%@)%@", busy, tries ? @", still after two seconds" : @""]);
            return;
        }
    }
}
@interface DMTitleTapTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end
@implementation DMTitleTapTarget
+ (instancetype)shared { static DMTitleTapTarget *t; static dispatch_once_t once; dispatch_once(&once, ^{ t = [DMTitleTapTarget new]; }); return t; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    for (UIView *v = touch.view; v && v != g.view; v = v.superview) if ([v isKindOfClass:[UIControl class]]) return NO;   // (a traffic light, a button of the bar)
    if ([objc_getAssociatedObject(g, &kTitleTapKindKey) intValue] == kDMTitleAerial) {   // (the stage: its title strip only)
        UIView *stage = g.view;
        CGPoint p = [touch locationInView:stage];
        return gAerialFlavor == 5 ? DMA5DragAllowedAt(stage, p) : (p.y >= -12.0 && p.y < kStageBarHeight);
    }
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (void)doubleTap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    int kind = [objc_getAssociatedObject(g, &kTitleTapKindKey) intValue];
    if (MSBDTitleActionFor(gTitleDoubleTap, kind == kDMTitleNative) == kMSBDTitleNothing) return;   // (Do Nothing: nothing at all -- never set, an app's window)
    if (DMGARefuses(@"window title bar")) return;
    // (the window is the one tapped: read now, acted on now or once SpringBoard is free -- DMTitleTapWhenFree)
    void (^act)(NSString *) = nil;
    switch (kind) {
        case kDMTitleNative: {
            UIView *v = g.view; while (v && ![v isKindOfClass:[DMNativeWindow class]]) v = v.superview;
            __weak DMNativeWindow *w = (DMNativeWindow *)v;
            if (v) act = ^(NSString *why) { if (w) DMTitleTapNative(w, why); };
            break;
        }
        case kDMTitleSM: {
            NSString *key = nil; @try { key = [g.view valueForKey:@"key"] ?: [g.view valueForKey:@"bundle"]; } @catch (id e) {}
            if ([key isKindOfClass:[NSString class]]) act = ^(NSString *why) { DMTitleTapSMWindow(key, why); };
            break;
        }
        case kDMTitleAerial: { NSString *b = DMStageBundle(g.view); if (b.length) act = ^(NSString *why) { DMTitleTapEngineWindow(b, why); }; break; }
        case kDMTitleMilkyWay: {
            UIView *w = g.view; Class ax = objc_getClass("AXWindowView"); while (w && !(ax && [w isKindOfClass:ax])) w = w.superview;
            NSString *b = nil; @try { b = [w valueForKey:@"bundleIdentifier"]; } @catch (id e) {}
            if ([b isKindOfClass:[NSString class]] && b.length) act = ^(NSString *why) { DMTitleTapEngineWindow(b, why); };
            break;
        }
        case kDMTitleZetsu: { NSString *b = g.view.window ? DMZetsuWindowBundle(g.view.window) : nil; if (b.length) act = ^(NSString *why) { DMTitleTapEngineWindow(b, why); }; break; }
        default: break;
    }
    if (act) DMTitleTapWhenFree(act, 0);
}
@end
// One recogniser of ours on a title bar (once); the engine's own double taps on that bar switched off (MilkyWay4's, Zetsu's) only while ours acts
// on that bar -- a choice made, not Do Nothing --: one double tap, one action. At Do Nothing and never set, the engine's own stays exactly as in
// 1.8.2.2, and one we switched off goes back on (review 1.8.3 P3-2; today neither engine has one on the bar: read on the M1). Aerial's stage is
// left as it is but for ours (its title strip had no double tap of its own: read on the M1).
static char kTitleTapOffKey;   // (on an engine's own double tap we switched off)
static NSHashTable<UIView *> *gTitleTapBars;   // (every bar with ours, weakly: the setting's change looks at each again)
static void DMTitleTapAttach(UIView *bar, int kind) {
    if (![bar isKindOfClass:[UIView class]]) return;
    BOOL ours = MSBDTitleActionFor(gTitleDoubleTap, kind == kDMTitleNative) != kMSBDTitleNothing;   // (ours acts on this bar now)
    BOOL have = NO;
    for (UIGestureRecognizer *g in bar.gestureRecognizers) {
        if (objc_getAssociatedObject(g, &kTitleTapMineKey)) { have = YES; continue; }
        if ((kind == kDMTitleMilkyWay || kind == kDMTitleZetsu) && [g isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)g).numberOfTapsRequired >= 2) {
            BOOL offByUs = [objc_getAssociatedObject(g, &kTitleTapOffKey) boolValue];
            if (ours && g.enabled) {
                g.enabled = NO; objc_setAssociatedObject(g, &kTitleTapOffKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DMLog([NSString stringWithFormat:@"[titlebar] %@'s own double tap on its title bar switched off (%@): ours follows the setting", kind == kDMTitleMilkyWay ? @"MilkyWay4" : @"Zetsu", g]);
            } else if (!ours && offByUs) {
                g.enabled = YES; objc_setAssociatedObject(g, &kTitleTapOffKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                DMLog([NSString stringWithFormat:@"[titlebar] %@'s own double tap on its title bar back on (%@): the setting is Do Nothing", kind == kDMTitleMilkyWay ? @"MilkyWay4" : @"Zetsu", g]);
            }
        }
    }
    if (have) return;
    if (!gTitleTapBars) gTitleTapBars = [NSHashTable weakObjectsHashTable];
    [gTitleTapBars addObject:bar];
    UITapGestureRecognizer *t = [[UITapGestureRecognizer alloc] initWithTarget:[DMTitleTapTarget shared] action:@selector(doubleTap:)];
    t.numberOfTapsRequired = 2;
    t.cancelsTouchesInView = NO; t.delaysTouchesBegan = NO; t.delaysTouchesEnded = NO;
    t.delegate = [DMTitleTapTarget shared];
    objc_setAssociatedObject(t, &kTitleTapKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(t, &kTitleTapMineKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [bar addGestureRecognizer:t];
}
// The setting changed (DMLoadPrefs): every bar with ours is looked at again -- an engine's own double tap off or back on with it.
static void DMTitleTapSettingChanged(void) {
    for (UIView *bar in [gTitleTapBars allObjects])
        for (UIGestureRecognizer *g in bar.gestureRecognizers)
            if (objc_getAssociatedObject(g, &kTitleTapMineKey)) { DMTitleTapAttach(bar, [objc_getAssociatedObject(g, &kTitleTapKindKey) intValue]); break; }
}
