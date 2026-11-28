// WindowFront.h -- windows brought to the front as on a Mac, on every engine (1.8.4.1 item 6; the order and why: common/WindowOrder.h). Included at
// the end of StatusBar.x, after TitleBarTap.h. The ways in, all here: an app's Dock icon, Command-Tab and the Mac Switcher's pick (DMSurfaceWindowForApp,
// through DMEngineRaise), a click or a tap in a window (DMRaiseStageForBundle), Window > Bring All to Front and the Window menu's list of windows.
// Stage Manager's own ways (a tap, a click, the Dock: DMSMBringToFront, GitHub #10) are unchanged; Bring All to Front and the list ask it as it does.
#pragma once
#include "../common/WindowOrder.h"

// One window of Aerial, Zetsu or MilkyWay4 to the front, reliably: the engine's own raise first -- Aerial's -_bringStageToFrontIfNeeded, Zetsu's order
// (ours: DMZetsuRaise), MilkyWay4's view order --, then, where Aerial's did not take (it answers by its own record of the front window: KT 8 Nov, the
// M1, a small window stayed behind a big one clicked before it), the stage put in front by its place among its layer's views, where every engine's
// front window is read from (DMTopStageOn). Nothing for a window that does not show.
static void DMKeepCoveredAfterRaise(UIView *w, NSString *why);   // (KeepCovered.h: Keep Covered Windows in Front, 1.8.4.1 item 7 -- off unless switched on)
static void DMEngineRaise(UIView *stage, NSString *why) {
    if (!stage) return;
    if (DMIsZetsuWindow(stage)) DMZetsuRaise((UIWindow *)stage);
    else if (DMActiveEngine() == DMEngineMilkyWay) [stage.superview bringSubviewToFront:stage];
    else {
        SEL front = DMAerialSel(@"_bringStageToFrontIfNeeded");
        if ([stage respondsToSelector:front]) ((void (*)(id, SEL))objc_msgSend)(stage, front);
        BOOL shown = !stage.hidden && stage.alpha > 0.05 && !DMStageMinimized(stage) && ![objc_getAssociatedObject(stage, kStageClosingKey) boolValue];
        if (MSBDRaiseNeedsOrder(DMTopStageOn(DMSnapScreenOf(stage)) == stage, shown) && stage.superview) {
            [stage.superview bringSubviewToFront:stage];
            DM_FEATURE_MARK("window-raise-by-order");
            DMLog([NSString stringWithFormat:@"[front] %@: Aerial's own raise left %@ behind: put in front by its place", why, DMStageBundle(stage)]);
        }
    }
    DMKeepCoveredAfterRaise(stage, why);   // (the windows it covers completely stay above it, while that switch is on)
}
// Stage Manager: every window of the app above the other apps' windows (MSBDOrderAppToFront), in one request as Stage Manager asks it (DMSMBringToFront):
// each keeps its place among its own, the newest the active one. A full-screen window of the app is left where it is. YES: asked, or in front already.
static BOOL DMSMAppWindowsForward(NSString *bundle, NSString *why) {
    id stage = DMSMWorkingStage();
    NSDictionary *map = DMSMStageItemsMap(stage);
    if (!bundle.length || !map.count) return NO;
    NSSet *onScreen = [NSSet setWithArray:DMSMWindowKeys() ?: @[]];
    NSArray *items = [[map allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {   // (back to front: the oldest interaction first)
        long long ta = DMSMAttrTimeOr(map[a], 0), tb = DMSMAttrTimeOr(map[b], 0);
        return ta < tb ? NSOrderedAscending : (ta > tb ? NSOrderedDescending : NSOrderedSame);
    }];
    int n = (int)MIN(items.count, (NSUInteger)64), apps[64], order[64];
    long long newest = 0;
    for (int i = 0; i < n; i++) {
        NSString *k = DMSMItemKey(items[i]);
        apps[i] = k && [onScreen containsObject:k] && [DMSMKeyBundle(k) isEqualToString:bundle] && !DMSMAttrsFullScreen(map[items[i]]) ? 1 : 0;
        newest = MAX(newest, DMSMAttrTimeOr(map[items[i]], 0));
    }
    int m = MSBDOrderAppToFront(apps, n, 1, order);
    BOOL moves = NO;
    for (int i = 0; i < m; i++) if (order[i] != i) moves = YES;
    if (!moves) return YES;   // (its windows are in front already)
    NSMutableDictionary *times = [NSMutableDictionary dictionary];
    id front = nil; long long t = newest;
    for (int i = 0; i < m; i++) if (apps[order[i]]) { times[items[order[i]]] = @(++t); front = items[order[i]]; }
    BOOL ok = front && DMSMRequestStageOrderAs(stage, times, front, YES);
    DMLog([NSString stringWithFormat:@"[front] %@: %@'s %lu window(s) above the others (%@)", why, bundle, (unsigned long)times.count, ok ? @"asked" : @"refused"]);
    return ok;
}
// An app's windows above the others, as its Dock icon and Command-Tab do on a Mac (and Bring All to Front for the front app): the engines' one window
// per app through DMEngineRaise, Stage Manager's every window of the app.
static void DMBringAppWindowsForward(NSString *bundle, NSString *why) {
    if (!bundle.length) return;
    if (DMSMEngine()) { DMSMAppWindowsForward(bundle, why); return; }
    UIView *stage = DMActiveEngine() == DMEngineMilkyWay ? DMFindMilkyWayWindow(bundle) : DMStageForBundle(bundle);
    if (stage) DMEngineRaise(stage, why);
}
static CGRect DMKeepCoveredFrame(UIView *s);
static BOOL DMKeepCoveredShows(UIView *s, UIScreen *scr);
// Stage Manager, Window > Bring All to Front (1.8.9.1, B127): all of the front app's shown windows above other apps' windows, with any smaller
// window of that app covered (MSBDFrameCoveredBy) by a larger window of that app placed above the larger window in relative order (and if the front
// app has a single big window already in front, covered smaller windows lifted into view).
static BOOL DMSMBringAllToFront(NSString *bundle) {
    id stage = DMSMWorkingStage();
    NSDictionary *map = DMSMStageItemsMap(stage);
    NSDictionary<NSString *, NSValue *> *open = DMSMOpenWindowFrames();
    if (!bundle.length || !map.count) return NO;
    NSSet *onScreen = [NSSet setWithArray:DMSMWindowKeys() ?: @[]];
    NSArray *items = [[map allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        long long ta = DMSMAttrTimeOr(map[a], 0), tb = DMSMAttrTimeOr(map[b], 0);
        return ta < tb ? NSOrderedAscending : (ta > tb ? NSOrderedDescending : NSOrderedSame);
    }];
    int n = (int)MIN(items.count, (NSUInteger)64), apps[64], order[64];
    CGRect frames[64]; bool shown[64];
    long long newest = 0;
    for (int i = 0; i < n; i++) {
        NSString *k = DMSMItemKey(items[i]);
        NSValue *fv = k ? open[k] : nil;
        bool vis = k && [onScreen containsObject:k] && !DMSMAttrsFullScreen(map[items[i]]);
        shown[i] = vis;
        frames[i] = (vis && fv) ? fv.CGRectValue : CGRectNull;
        apps[i] = (vis && [DMSMKeyBundle(k) isEqualToString:bundle]) ? 1 : 0;
        newest = MAX(newest, DMSMAttrTimeOr(map[items[i]], 0));
    }
    int m = MSBDOrderBringAllToFront(apps, frames, shown, n, 1, order);
    int start = m;
    for (int i = 0; i < m; i++) if (order[i] != i) { start = i; break; }
    if (start >= m) return YES;
    NSMutableDictionary *times = [NSMutableDictionary dictionary];
    id front = nil; long long t = newest;
    for (int i = start; i < m; i++) { times[items[order[i]]] = @(++t); front = items[order[i]]; }
    BOOL ok = front && DMSMRequestStageOrderAs(stage, times, front, YES);
    DMLog([NSString stringWithFormat:@"[front] Bring All to Front: %@ (%lu window(s) reordered, %@)", bundle, (unsigned long)times.count, ok ? @"asked" : @"refused"]);
    return ok;
}
// Aerial, Zetsu, MilkyWay4 (1 window per app): after raising the front app's window, also lift any shown smaller windows completely covered by it
// when Keep Covered Windows in Front is off (when on, DMEngineRaise already kept them above).
static void DMEngineSurfaceCoveredByFront(NSString *bundle) {
    if (gKeepCoveredInFront || !bundle.length || DMSMEngine() || DMActiveEngine() == DMEngineNone) return;
    UIView *frontStage = DMActiveEngine() == DMEngineMilkyWay ? DMFindMilkyWayWindow(bundle) : DMStageForBundle(bundle);
    if (!frontStage) return;
    NSArray<UIView *> *stages = DMAerialStages();
    int n = (int)MIN(stages.count, (NSUInteger)64), apps[64], order[64];
    CGRect frames[64]; bool shown[64];
    UIScreen *scr = DMSnapScreenOf(frontStage);
    for (int i = 0; i < n; i++) {
        shown[i] = DMKeepCoveredShows(stages[i], scr);
        frames[i] = shown[i] ? DMKeepCoveredFrame(stages[i]) : CGRectNull;
        apps[i] = (stages[i] == frontStage) ? 1 : 0;
    }
    int m = MSBDOrderBringAllToFront(apps, frames, shown, n, 1, order);
    BOOL past = NO;
    for (int i = 0; i < m; i++) {
        if (stages[order[i]] == frontStage) { past = YES; continue; }
        if (past && shown[order[i]]) DMEngineRaise(stages[order[i]], @"Bring All to Front (covered smaller window)");
    }
}
// Window > Bring All to Front, as on a Mac: the front app's windows above the other apps' windows (and covered smaller windows un-buried above a
// bigger one, B127). The windows behind a full-screen app come over it
// first, as this row did before 1.8.4.1 (the engines' gWindowsPinnedForward; Stage Manager's DMSMWindowsForward: one request at a time there).
static void DMBringAllToFrontNow(void) {
    DM_FEATURE_MARK("window-bring-all-to-front");
    NSString *front = [DMActiveApp() bundleIdentifier];
    if (DMSMEngine()) {
        if (DMSMFullScreenBundle().length && DMSMWindowsBehindFullScreen()) { DMSMWindowsForward(YES); return; }
        if (front.length) DMSMBringAllToFront(front);
        return;
    }
    if ((gWindowsBehindApps || gFullScreenRaised) && !gWindowsPinnedForward) DMToggleWindowsForward();   // (over the full-screen app, as before)
    if (front.length) { DMBringAppWindowsForward(front, @"Bring All to Front"); DMEngineSurfaceCoveredByFront(front); }
}
// The Window menu's list of windows, as on a Mac: the front app's windows, the front one ticked; a pick brings that one to the front (Stage Manager:
// as a tap on it does, DMSMBringToFront; the engines' one window: DMEngineRaise). Two windows of one app (Stage Manager) by the app's name and a
// number, in the order they are listed in.
static NSArray *DMWindowListRows(void) {
    NSMutableArray *rows = [NSMutableArray array];
    NSString *front = [DMActiveApp() bundleIdentifier];
    if (!front.length || DMNativeActiveApp()) return rows;
    NSString *name = [DMAppForBundle(front) displayName] ?: front;
    if (DMSMEngine()) {
        NSString *frontKey = DMSMFrontWindowKey();
        int count = 0;
        for (NSString *k in DMSMWindowKeys()) {
            if (![DMSMKeyBundle(k) isEqualToString:front]) continue;
            NSString *key = [k copy];
            count++;
            DMRow *r = [[DMRow alloc] initWithTitle:(count == 1 ? name : [NSString stringWithFormat:@"%@ %d", name, count]) enabled:YES handler:DMCloseThen(^{ DMSMBringToFront(key); })];
            r.checked = [key isEqualToString:frontKey];
            [rows addObject:r];
        }
        return rows;
    }
    UIView *stage = DMActiveEngine() == DMEngineMilkyWay ? DMFindMilkyWayWindow(front) : DMStageForBundle(front);
    if (!stage || stage.hidden || DMStageMinimized(stage)) return rows;
    __weak UIView *weakStage = stage;
    DMRow *r = [[DMRow alloc] initWithTitle:name enabled:YES handler:DMCloseThen(^{ UIView *s = weakStage; if (s) DMEngineRaise(s, @"the Window menu's list"); })];
    r.checked = YES;   // (the front app's window is the front one: DMActiveApp)
    [rows addObject:r];
    return rows;
}
