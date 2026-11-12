// SceneLayer.h -- the per-scene layer helper (MacStatusBar&Dock 1.8.7 commit 9; plans/design-1.8.7-displays.md section 6). Included by StatusBar.x.
// One kind of window for our UI on another display: a pass-through window of ours in SpringBoard's window scene on that display, one per scene and
// role, made on first use and let go when its display or scene goes (UIScreenDidDisconnectNotification, UISceneDidDisconnectNotification, and
// again once UIKit has let the scene go). Grown out of the external display's menu window (1.8.4, DMExtMenuWindowFor), which is its first role and
// keeps its behaviour: the same class (MSBExtMenuWindow), level, hit test and log lines. 1.8.7's other roles: the TV's auto-hide strip (commit 10),
// the TV's Display Settings panel and the TV's Mac Switcher layer (later commits). The native windows' layer per display is 1.8.8's step.
//  - "a display's screen" is the screen of SpringBoard's window scene on it (the shell UI one, S1 reading: the first non-main UIScreen of the TV has
//    no scene), so a layer is asked for by that scene, or by a screen whose scene is looked up among the connected window scenes;
//  - a role's kind: its class (made once, a UIWindow subclass with that hit test and, when given, the escape gesture), its log tag, and what to do
//    before its windows go (the menu: a menu open there closes).
#pragma once

typedef struct {
    const char *cls;   // (the window class, made once: a UIWindow subclass)
    IMP hitTest;       // (-hitTest:withEvent:, "@@:{CGPoint=dd}@": what of the window takes events; nil there passes them through)
    IMP axEscape;      // (-accessibilityPerformEscape, "B@:", or NULL)
    const char *tag;   // (its log lines: "[<tag>] ...")
} DMSceneLayerKind;

static NSMutableDictionary<NSString *, NSMutableArray<UIWindow *> *> *gDMSceneLayers;   // role -> its windows, one per scene
static NSMutableDictionary<NSString *, void (^)(NSArray<UIWindow *> *)> *gDMSceneLayerGone;   // role -> what to do before its windows go
static NSMutableDictionary<NSString *, NSString *> *gDMSceneLayerTags;

// The windows of a role (the same array while the helper lives: a role's own list, e.g. gExtMenuWindows, can hold it).
static NSMutableArray<UIWindow *> *DMSceneLayersOf(NSString *role) {
    if (!gDMSceneLayers) gDMSceneLayers = [NSMutableDictionary dictionary];
    NSMutableArray *a = gDMSceneLayers[role];
    if (!a) gDMSceneLayers[role] = a = [NSMutableArray array];
    return a;
}
// A role's windows whose scene or screen went (or is `what`, the screen or scene a note named; nil: only those already gone) are let go, after its
// own "gone" step.
static void DMSceneLayersRelease(id what, NSString *why) {
    for (NSString *role in [gDMSceneLayers.allKeys copy]) {
        NSMutableArray<UIWindow *> *list = gDMSceneLayers[role];
        if (!list.count) continue;
        NSMutableArray *gone = [NSMutableArray array];
        for (UIWindow *w in list) {
            UIWindowScene *sc = nil; UIScreen *scr = nil;
            @try { sc = w.windowScene; scr = sc.screen; } @catch (id e) {}
            if (!sc || !scr || (what && (what == sc || what == scr))) [gone addObject:w];
        }
        if (!gone.count) continue;
        void (^before)(NSArray<UIWindow *> *) = gDMSceneLayerGone[role];
        if (before) before(gone);
        for (UIWindow *w in gone) { w.hidden = YES; [list removeObjectIdenticalTo:w]; }
        DMSnapInvalidate();
        NSString *tag = gDMSceneLayerTags[role] ?: @"scenelayer";
        if ([role isEqualToString:@"menu"]) DMLog([NSString stringWithFormat:@"[%@] %lu external menu window(s) released (%@)", tag, (unsigned long)gone.count, why]);
        else DMLog([NSString stringWithFormat:@"[%@] %lu %@ window(s) released (%@)", tag, (unsigned long)gone.count, role, why]);
    }
}
// SpringBoard's window scene on a screen (nil for none: a screen with no scene of its own, or the iPad's when asked for another display).
static UIWindowScene *DMSceneLayerSceneOf(UIScreen *screen) {
    if (!screen) return nil;
    @try {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
            if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == screen) return (UIWindowScene *)sc;
    } @catch (NSException *e) {}
    return nil;
}
// The window of `role` in `scene` (made the first time, hidden, clear, at `level`); nil on the iPad's own screen, which has its own windows.
static UIWindow *DMSceneLayerInScene(UIWindowScene *scene, NSString *role, CGFloat level, DMSceneLayerKind kind, void (^gone)(NSArray<UIWindow *> *)) {
    if (![scene isKindOfClass:[UIWindowScene class]] || !role.length || !kind.cls || !kind.hitTest) return nil;
    UIScreen *scr = nil; @try { scr = scene.screen; } @catch (id e) {}
    if (!scr || scr == [UIScreen mainScreen]) return nil;
    static BOOL observing = NO;
    if (!observing) {
        // (registered once, the first time a layer is asked for: without one nothing is observed. Its own flag, not "no list yet": every role's
        // owner asks for its list first (DMSceneLayersOf: gExtMenuWindows, the strip), which makes the helper's dictionary, and keyed on that the observers
        // were never added -- a TV menu stayed open with its keys and focus after an unplug, its window kept; review of 1.8.7 commit 9)
        observing = YES;
        for (NSString *n in @[UIScreenDidDisconnectNotification, UISceneDidDisconnectNotification])
            [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                id what = note.object; NSString *why = note.name;
                DMSceneLayersRelease(what, why);
                dispatch_async(dispatch_get_main_queue(), ^{ DMSceneLayersRelease(nil, why); });   // (again once UIKit has let the scene go)
            }];
    }
    NSMutableArray<UIWindow *> *list = DMSceneLayersOf(role);
    if (!gDMSceneLayerGone) gDMSceneLayerGone = [NSMutableDictionary dictionary];
    if (!gDMSceneLayerTags) gDMSceneLayerTags = [NSMutableDictionary dictionary];
    if (gone && !gDMSceneLayerGone[role]) gDMSceneLayerGone[role] = [gone copy];
    NSString *tag = kind.tag ? @(kind.tag) : @"scenelayer";
    gDMSceneLayerTags[role] = tag;
    DMSceneLayersRelease(nil, [role isEqualToString:@"menu"] ? @"checked before a menu" : [NSString stringWithFormat:@"checked before the %@", role]);
    for (UIWindow *w in list) if (w.windowScene == scene) return w;
    UIWindow *w = nil;
    @try {
        Class sub = objc_getClass(kind.cls);
        if (!sub) {
            sub = objc_allocateClassPair([UIWindow class], kind.cls, 0);
            if (!sub) return nil;
            class_addMethod(sub, @selector(hitTest:withEvent:), kind.hitTest, "@@:{CGPoint=dd}@");
            if (kind.axEscape) class_addMethod(sub, @selector(accessibilityPerformEscape), kind.axEscape, "B@:");
            objc_registerClassPair(sub);
        }
        w = [(UIWindow *)[sub alloc] initWithWindowScene:scene];
        w.windowLevel = level;
        w.backgroundColor = [UIColor clearColor];
        w.hidden = YES;
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[%@] exception %@", tag, e]); return nil; }
    if (!w) return nil;
    [list addObject:w];
    DMSnapInvalidate();
    if ([role isEqualToString:@"menu"])
        DMLog([NSString stringWithFormat:@"[%@] menu window made for the external display (scene %@, screen %@, window %@)", tag, NSStringFromClass([scene class]), NSStringFromCGRect(scene.screen.bounds), NSStringFromCGRect(w.bounds)]);
    else DMLog([NSString stringWithFormat:@"[%@] %@ window made for the external display (screen %@, window %@, level %.1f)", tag, role, NSStringFromCGRect(scene.screen.bounds), NSStringFromCGRect(w.bounds), level]);
    return w;
}
// The same by a display's screen: its scene looked up (never a screen with no scene: S1).
__attribute__((unused)) static UIWindow *DMSceneLayer(UIScreen *screen, NSString *role, CGFloat level, DMSceneLayerKind kind, void (^gone)(NSArray<UIWindow *> *)) {
    return DMSceneLayerInScene(DMSceneLayerSceneOf(screen), role, level, kind, gone);
}
// Is this view one of a role's windows?
__attribute__((unused)) static BOOL DMSceneLayerIs(UIView *v, NSString *role) {
    NSArray *list = gDMSceneLayers[role];
    return v && list && [list indexOfObjectIdenticalTo:(UIWindow *)v] != NSNotFound;
}
