// WindowKeys.h -- Window Tiling Keys (Settings > Keyboard, 1.8.3 item 3, off unless switched on): macOS 15's fixed tiling shortcuts, the Globe key for
// the Mac's Fn (the set, the clashes and why: WindowKeysRule.h). Included at the end of StatusBar.x, after WindowAPI.h, whose ways they use: the
// Window menu's layouts for the front window, the arrangements of two and three windows, Return to Previous Size.
// Also here: Return to Previous Size's records (taken by the Window menu's layouts, StatusBar.x DMWindowLayout, and WindowAPI.h DMNativeLayout, only
// while something can go back with them: DMWinPrevWanted), the way back, Center at the window's own size, and the arrangements of two and three
// windows.
// The keys come from SpringBoard's own presses (below: Globe chords are handed to SpringBoard, never to its key commands), while the switch is on
// and a window engine of ours runs, or one of our own windows is the front one (the keys offered: told to the volume and backlight chords,
// DMWindowKeysPublish; our own windows with no engine as the Window menu and the window API lay them out, review 1.8.3 P2-9); iPadOS's own handling of the
// same keys (15's Split View for Globe-Control-Left / Right) does not run under them. Each key tells the chords it ran (common/ModifierTap.h: no
// volume step for the Globe and Control it began with).
#pragma once
#include "WindowKeysRule.h"
#include "../common/ModifierTap.h"

// ---- Return to Previous Size: a window's frame before it was tiled (WindowKeysRule.h) ----
static char kWinPrevKey;   // (on an engine's window or one of ours: NSValue, its frame as the engine has it)
static NSMutableDictionary<NSString *, NSValue *> *gSMWinPrev;   // (Stage Manager: by window key, the whole window)
static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMWinZoom;   // (Stage Manager: a title bar's Fill or Zoom, the frame from before and the Fill it was kept with, by window key: DMTitleRecordSMTo)
static BOOL DMWinTileFor(CGRect f, CGRect (^tile)(NSString *name)) {
    for (int i = 0; i < kMSBDWinTileCount; i++) if (MSBDWinNear(f, tile(@(kMSBDWinTiles[i])))) return YES;
    return NO;
}
static BOOL DMWinTiledEngine(CGRect f) { return DMWinTileFor(f, ^CGRect(NSString *n) { return DMLayoutFrame(n); }); }   // (the engine's frames: Aerial 5.x's stages)
static BOOL DMWinTiledSM(CGRect f, id stage) {
    CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr);
    return DMWinTileFor(f, ^CGRect(NSString *n) { return DMSMLayoutFrameIn(n, u, scr); });
}
static BOOL DMWinTiledNative(CGRect f) { CGRect d = DMNativeDesktop(); CGSize s = [UIScreen mainScreen].bounds.size; return DMWinTileFor(f, ^CGRect(NSString *n) { return DMLayoutFrameInArea(n, d, s); }); }
// Taken only while something can go back with them: the window keys' Globe-Control-R. With the switch off nothing is read or kept, as in 1.8.2.2
// (review 1.8.3 F7: every Window menu layout read the window's frame and stage for a record nothing could use, and Stage Manager's map grew with the
// keys of closed windows).
static BOOL DMWinPrevWanted(void) { return gWindowKeysOn; }   // (a title bar's Fill goes back with its own frame from before: TitleBarRule.h, regression F2)
static void DMWinPrevNoteView(UIView *v, BOOL tiledNow, CGRect now) {
    if (!DMWinPrevWanted()) return;
    if (v && MSBDWinPrevTake(tiledNow) && !CGRectIsNull(now)) objc_setAssociatedObject(v, &kWinPrevKey, [NSValue valueWithCGRect:now], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void DMWinPrevNoteNative(DMNativeWindow *w) {   // (our own window, one of the Window menu's tiles: WindowAPI.h DMNativeLayout)
    if (w && DMWinPrevWanted()) DMWinPrevNoteView(w, DMWinTiledNative(w.frame), w.frame);
}
// (Stage Manager's maps hold the windows open now only: the records of closed windows go each time one is taken, read from every stage as Fit's
//  sweep reads them -- an app's key stays while a window of the app is there; a stage that cannot be read leaves the map as it is. Return to
//  Previous Size's, and the title bar's Zoom: review 1.8.3 P2-5)
static void DMSMRecordsPrune(NSMutableDictionary *map) {
    if (!map.count) return;
    NSArray *stages = DMSMRecentStages();
    if (!stages) return;
    NSMutableArray<NSString *> *present = [NSMutableArray array];
    for (id al in stages) {
        NSDictionary *m = DMSMStageItemsMap(al);
        if (!m) return;
        for (id it in m) { NSString *k = DMSMItemKey(it); if (!k.length) return; [present addObject:k]; }
    }
    for (NSString *k in [map allKeys]) {
        BOOL open = NO;
        for (NSString *w in present) if (DMSMKeyCovers(k, w)) { open = YES; break; }
        if (!open) [map removeObjectForKey:k];
    }
}
static void DMWinPrevPruneSM(void) { DMSMRecordsPrune(gSMWinPrev); }
static void DMWinPrevNoteSM(NSString *key, id stage) {
    if (!DMWinPrevWanted()) return;
    key = DMSMWindowKeyOf(key);   // (an app's key -- the front window was another app's: its newest window, as the open frames are keyed; audit 1.8.3 L3)
    NSValue *f = key ? DMSMOpenWindowFrames()[key] : nil;
    if (!f || !MSBDWinPrevTake(DMWinTiledSM(f.CGRectValue, stage))) return;
    DMWinPrevPruneSM();
    if (!gSMWinPrev) gSMWinPrev = [NSMutableDictionary dictionary];
    gSMWinPrev[key] = f;
}
// A layout of the Window menu's is about to move the active app's window (DMWindowLayout): its frame now, if it is in no tile.
static void DMWinPrevNoteActive(NSString *bundleID, NSString *smKey) {
    if (!bundleID.length || !DMWinPrevWanted()) return;
    if (DMSMEngine()) { DMWinPrevNoteSM(smKey, DMSMStageOf(smKey)); return; }
    UIView *v = DMActiveEngine() == DMEngineZetsu ? DMZetsuWindowFor(bundleID) : DMActiveEngine() == DMEngineAerial ? DMStageForBundle(bundleID) : DMFindMilkyWayWindow(bundleID);
    if (!v || v.hidden || DMStageMinimized(v) || DMWindowMinimized(v)) return;   // (full screen or away: no window to go back to)
    DMWinPrevNoteView(v, DMWinTiledEngine(v.frame), v.frame);
}
// ---- the title bar's frame from before (Fill's and Zoom's way back, TitleBarTap.h): in step with every placement of ours (TitleBarRule.h,
// review 1.8.3 P4-1) ----
// On an engine's window or one of ours (kWinZoomKey), and in gSMWinZoom by window key: @[the frame from before, the Fill frame it was kept with], in
// the frames the window's engine has (Aerial 5.x: its stage).
static char kWinZoomKey;
static NSArray<NSValue *> *DMTitleRecordPair(CGRect before, CGRect fill) { return @[[NSValue valueWithCGRect:before], [NSValue valueWithCGRect:fill]]; }
// A move or a resize by hand has ended: the frame from before is from before that move (dropped).
static void DMTitleRecordMovedView(UIView *v) { if (v) objc_setAssociatedObject(v, &kWinZoomKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL DMTitleRecordSMAny(void) { return gSMWinZoom.count > 0; }
static void DMTitleRecordMovedSM(NSString *key) {
    if (!gSMWinZoom.count) return;
    key = DMSMWindowKeyOf(key);
    if (key.length) [gSMWinZoom removeObjectForKey:key];
}
// A placement of ours is about to move this window from now to `to`; fill: the Fill frame where it is (the title bar's own Zoom: the zoomed frame,
// the one its record is kept with -- TitleBarRule.h, 1.8.4.1 item 1). (A setting that keeps no frames: dropped, and nothing read -- every placement
// of ours passes here.) Placed again at the very frame its record was kept with, while it is there (Center on a zoomed window): kept.
static void DMTitleRecordView(UIView *v, CGRect now, CGRect to, CGRect fill) {
    if (!v) return;
    NSArray<NSValue *> *had = objc_getAssociatedObject(v, &kWinZoomKey);
    BOOL stays = [had isKindOfClass:[NSArray class]] && had.count == 2 && MSBDWinNear(to, had[1].CGRectValue) && MSBDWinNear(now, had[1].CGRectValue);
    int r = (CGRectIsNull(fill) || CGRectIsNull(to)) ? kMSBDTitleRecordDrop
          : MSBDTitleRecordOnPlaceAt(MSBDTitleKeepsFrames(gTitleDoubleTap), MSBDWinNear(to, fill), MSBDWinNear(now, fill), stays);
    if (r == kMSBDTitleRecordTake) objc_setAssociatedObject(v, &kWinZoomKey, DMTitleRecordPair(now, fill), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    else if (r == kMSBDTitleRecordDrop) DMTitleRecordMovedView(v);
}
static void DMTitleRecordEngineTo(UIView *v, CGRect to) {   // (Aerial, Zetsu, MilkyWay4: the engine's frames)
    if (!v) return;
    if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) { DMTitleRecordMovedView(v); return; }
    DMTitleRecordView(v, v.frame, to, DMLayoutFrame(@"fill"));
}
static void DMTitleRecordNativeTo(DMNativeWindow *w, CGRect to) {   // (our own windows: their Fill in the desktop above the Dock)
    if (!w) return;
    if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) { DMTitleRecordMovedView(w); return; }
    DMTitleRecordView(w, w.frame, to, DMLayoutFrameInArea(@"fill", DMNativeDesktop(), [UIScreen mainScreen].bounds.size));
}
// (Stage Manager: the whole window, title bar included. fill: the stage's Fill, or -- the title bar's own Zoom -- the zoomed frame, as above;
//  CGRectNull: the stage's Fill)
static void DMTitleRecordSMAt(NSString *key, id stage, CGRect to, CGRect fill) {
    if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) { DMTitleRecordMovedSM(key); return; }
    key = DMSMWindowKeyOf(key);
    if (!key.length) return;
    NSValue *now = DMSMOpenWindowFrames()[key];
    if (!stage) stage = DMSMStageOf(key);
    if (CGRectIsNull(fill)) { CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr); fill = DMSMLayoutFrameIn(@"fill", u, scr); }
    NSArray<NSValue *> *had = gSMWinZoom[key];
    BOOL stays = now && [had isKindOfClass:[NSArray class]] && had.count == 2 && MSBDWinNear(to, had[1].CGRectValue) && MSBDWinNear(now.CGRectValue, had[1].CGRectValue);
    int r = (!now || CGRectIsNull(to) || CGRectIsNull(fill)) ? kMSBDTitleRecordDrop
          : MSBDTitleRecordOnPlaceAt(YES, MSBDWinNear(to, fill), MSBDWinNear(now.CGRectValue, fill), stays);
    if (r == kMSBDTitleRecordDrop) { [gSMWinZoom removeObjectForKey:key]; return; }
    if (r != kMSBDTitleRecordTake) return;
    DMSMRecordsPrune(gSMWinZoom);
    if (!gSMWinZoom) gSMWinZoom = [NSMutableDictionary dictionary];
    gSMWinZoom[key] = DMTitleRecordPair(now.CGRectValue, fill);
}
static void DMTitleRecordSMTo(NSString *key, id stage, CGRect to) { DMTitleRecordSMAt(key, stage, to, CGRectNull); }   // (every placement of ours: the stage's Fill)
// Stage Manager: a plan of layouts (key -> layout name) or places (key -> frame) about to be applied in a stage, each window as above.
static void DMTitleRecordSMPlan(NSDictionary *plan, id stage) {
    if (!plan.count || (!MSBDTitleKeepsFrames(gTitleDoubleTap) && !gSMWinZoom.count)) return;
    CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr);
    for (NSString *k in plan) {
        id v = plan[k];
        CGRect to = [v isKindOfClass:[NSValue class]] ? [v CGRectValue] : ([v isKindOfClass:[NSString class]] ? DMSMLayoutFrameIn(v, u, scr) : CGRectNull);
        DMTitleRecordSMTo(k, stage, to);
    }
}
// At a double tap: the frame from before, while it holds (MSBDTitleRecordHolds: the window still at the Fill frame it was kept with), else nil --
// and dropped.
static NSValue *DMTitleRecordHeldView(UIView *v, CGRect now, NSString *who) {
    NSArray<NSValue *> *rec = objc_getAssociatedObject(v, &kWinZoomKey);
    if (![rec isKindOfClass:[NSArray class]] || rec.count != 2) rec = nil;
    if (MSBDTitleRecordHolds(rec != nil, rec && MSBDWinNear(now, rec[1].CGRectValue))) return rec[0];
    if (rec) {
        objc_setAssociatedObject(v, &kWinZoomKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DMLog([NSString stringWithFormat:@"[titlebar] %@: its frame from before (%@) was kept at Fill %@, it is at %@ now: dropped", who, NSStringFromCGRect(rec[0].CGRectValue), NSStringFromCGRect(rec[1].CGRectValue), NSStringFromCGRect(now)]);
    }
    return nil;
}
static NSValue *DMTitleRecordHeldSM(NSString *key, CGRect now) {
    NSArray<NSValue *> *rec = key ? gSMWinZoom[key] : nil;
    if (![rec isKindOfClass:[NSArray class]] || rec.count != 2) rec = nil;
    if (MSBDTitleRecordHolds(rec != nil, rec && MSBDWinNear(now, rec[1].CGRectValue))) return rec[0];
    if (key && gSMWinZoom[key]) {
        [gSMWinZoom removeObjectForKey:key];
        if (rec) DMLog([NSString stringWithFormat:@"[titlebar] %@: its frame from before (%@) was kept at Fill %@, it is at %@ now: dropped", DMSMKeyText(key), NSStringFromCGRect(rec[0].CGRectValue), NSStringFromCGRect(rec[1].CGRectValue), NSStringFromCGRect(now)]);
    }
    return nil;
}

// ---- Return to Previous Size: the front window back to its frame before it was tiled ----
static void DMWindowBackFromTile(NSString *why) {
    DMNativeWindow *nw = DMNativeActiveApp();
    if (nw) {
        NSValue *rec = objc_getAssociatedObject(nw, &kWinPrevKey);
        int act = MSBDWinPrevOnReturn(DMWinTiledNative(nw.frame), rec != nil);
        if (act != kMSBDWinPrevNothing) objc_setAssociatedObject(nw, &kWinPrevKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (act != kMSBDWinPrevBack) { DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ has no size from before a tile to go back to", why, nw.title ?: @"our window"]); return; }
        nw.restoreFrame = CGRectNull; nw.layoutName = nil;
        CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMLayoutFrameInArea(@"fill", DMNativeDesktop(), [UIScreen mainScreen].bounds.size), nw.minSize);   // (inside today's desktop, audit 1.8.3 M5)
        DMTitleRecordNativeTo(nw, f);   // (a placement of ours: the title bar's frame from before follows it, P4-1)
        MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ nw.frame = f; }, nil);
        return;
    }
    NSString *bundleID = [DMActiveApp() bundleIdentifier];
    if (!bundleID.length) return;
    if (DMSMEngine()) {
        NSString *key = DMSMFrontWindowKey();
        if (![DMSMKeyBundle(key) isEqualToString:bundleID]) key = bundleID;
        key = DMSMWindowKeyOf(key);   // (the app's key: its newest window -- the open frames and the records are by window key; audit 1.8.3 L3)
        id stage = DMSMStageOf(key);
        NSValue *now = DMSMOpenWindowFrames()[key], *rec = gSMWinPrev[key];
        int act = MSBDWinPrevOnReturn(now && DMWinTiledSM(now.CGRectValue, stage), rec != nil);
        if (act != kMSBDWinPrevNothing) [gSMWinPrev removeObjectForKey:key];
        if (act != kMSBDWinPrevBack) { DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ has no size from before a tile to go back to", why, DMSMKeyText(key)]); return; }
        CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr);
        CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMSMLayoutFrameIn(@"fill", u, scr), CGSizeZero);   // (inside today's stage area -- Stage Manager keeps its own minimum --, audit 1.8.3 M5)
        DMTitleRecordSMTo(key, stage, f);   // (as above)
        BOOL ok = DMSMApplyPlacesIn(@{key: [NSValue valueWithCGRect:f]}, stage);
        if (ok) DMSMFitLetGo(key);   // (placed by the user: no longer one of Fit to Window's tiles, as below)
        DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ back to %@ (%@)", why, DMSMKeyText(key), NSStringFromCGRect(f), ok ? @"done" : @"not in the stage"]);
        return;
    }
    UIView *v = DMActiveEngine() == DMEngineZetsu ? DMZetsuWindowFor(bundleID) : DMActiveEngine() == DMEngineAerial ? DMStageForBundle(bundleID) : DMFindMilkyWayWindow(bundleID);
    if (!v || v.hidden || DMStageMinimized(v) || DMWindowMinimized(v)) return;
    NSValue *rec = objc_getAssociatedObject(v, &kWinPrevKey);
    int act = MSBDWinPrevOnReturn(DMWinTiledEngine(v.frame), rec != nil);
    if (act != kMSBDWinPrevNothing) objc_setAssociatedObject(v, &kWinPrevKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (act != kMSBDWinPrevBack) { DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ has no size from before a tile to go back to", why, bundleID]); return; }
    CGRect f = MSBDWinPrevBackFrame(rec.CGRectValue, DMLayoutFrame(@"fill"), DMEngineWindowMin());   // (inside today's desktop, audit 1.8.3 M5)
    DMFitGroupForget(bundleID);   // (placed by the user: no longer one of Fit to Window's tiles, as a layout of its own)
    DMTitleRecordEngineTo(v, f);   // (as above)
    DMAerialMoveStage(v, f, nil);
    if (DMActiveEngine() == DMEngineAerial && gAerialFlavor == 5 && !DMTestFlag("/tmp/msb-a5-nohold")) DMA5HoldStageAt(v, f, CACurrentMediaTime() + 1.5);   // (as a Window menu layout)
    DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ back to %@", why, bundleID, NSStringFromCGRect(f)]);
}

// ---- Center (Globe-Control-C, as macOS 15's): the front window at its own size, in the middle of the desktop (WindowKeysRule.h
// MSBDWinCenterKeepingSize). No tile: no record. The Window menu's Center and the window API's "center" stay the middle place at its size. ----
static void DMCenterFrontWindow(NSString *why) {
    DMNativeWindow *nw = DMNativeActiveApp();
    if (nw) {
        CGRect f = MSBDWinCenterKeepingSize(nw.frame, DMLayoutFrameInArea(@"fill", DMNativeDesktop(), [UIScreen mainScreen].bounds.size));
        if (CGRectIsNull(f)) return;
        nw.restoreFrame = CGRectNull; nw.layoutName = nil;   // (in no layout now: a turn leaves it where it is, as a window moved by hand)
        DMTitleRecordNativeTo(nw, f);   // (a placement of ours: the title bar's frame from before follows it, P4-1)
        DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ centred at its size, %@", why, nw.title ?: @"our window", NSStringFromCGRect(f)]);
        MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseOut, ^{ nw.frame = f; }, nil);
        return;
    }
    NSString *bundleID = [DMActiveApp() bundleIdentifier];
    if (!bundleID.length) return;
    if (DMSMEngine()) {
        NSString *key = DMSMFrontWindowKey();
        if (![DMSMKeyBundle(key) isEqualToString:bundleID]) key = bundleID;
        key = DMSMWindowKeyOf(key);   // (as above: Center found "no window" for an app's key, audit 1.8.3 L3)
        id stage = DMSMStageOf(key), attrs = nil;
        NSValue *now = DMSMOpenWindowFrames()[key];
        if (!now || !DMSMItemFor(stage, key, &attrs) || !attrs || DMSMAttrsFullScreen(attrs)) { DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ has no window to centre (full screen or away)", why, DMSMKeyText(key)]); return; }
        CGSize scr = CGSizeZero; CGRect u = DMSMUsableAreaForStage(stage, &scr);
        CGRect f = MSBDWinCenterKeepingSize(now.CGRectValue, DMSMLayoutFrameIn(@"fill", u, scr));
        if (CGRectIsNull(f)) return;
        for (NSString *k in [gSMTurnPlaced allKeys]) if (DMSMKeyCovers(key, k)) [gSMTurnPlaced removeObjectForKey:k];   // (placed now, as a layout)
        DMTitleRecordSMTo(key, stage, f);   // (as above)
        BOOL ok = DMSMApplyPlacesIn(@{key: [NSValue valueWithCGRect:f]}, stage);
        if (ok) DMSMFitLetGo(key);   // (placed by the user: no longer one of Fit to Window's tiles, as below)
        DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ centred at its size, %@ (%@)", why, DMSMKeyText(key), NSStringFromCGRect(f), ok ? @"done" : @"not in the stage"]);
        return;
    }
    UIView *v = DMActiveEngine() == DMEngineZetsu ? DMZetsuWindowFor(bundleID) : DMActiveEngine() == DMEngineAerial ? DMStageForBundle(bundleID) : DMFindMilkyWayWindow(bundleID);
    if (!v || v.hidden || DMStageMinimized(v) || DMWindowMinimized(v)) { DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ has no window to centre (full screen or away)", why, bundleID]); return; }
    CGRect f = MSBDWinCenterKeepingSize(v.frame, DMLayoutFrame(@"fill"));   // (the engine's frames: Aerial 5.x's stage in its Fill stage is the window in its Fill)
    if (CGRectIsNull(f)) return;
    objc_setAssociatedObject(v, &kStageTurnPlacedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (placed now, as a layout)
    DMFitGroupForget(bundleID);   // (placed by the user: no longer one of Fit to Window's tiles, as a layout of its own)
    DMTitleRecordEngineTo(v, f);   // (as above)
    DMAerialMoveStage(v, f, nil);
    if (DMActiveEngine() == DMEngineAerial && gAerialFlavor == 5 && !DMTestFlag("/tmp/msb-a5-nohold")) DMA5HoldStageAt(v, f, CACurrentMediaTime() + 1.5);   // (as a Window menu layout)
    DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ centred at its size, %@", why, bundleID, NSStringFromCGRect(f)]);
}

// ---- the arrangements: the front window and the windows behind it, each to its tile (Globe-Control-Shift / Option-Shift arrows) ----
// The front window and the next windows on the desktop, newest first, each to its tile; fewer windows than tiles: the ones there are. Stage Manager:
// one request for all of them (as Fit to Window's tiles: one stage transition). The other engines: the front window as a layout of the Window menu's
// (also from full screen), the others moved as Swap does. Our own window in front: only it (the engines' windows are not ours to arrange with it).
static void DMArrangeWindows(const char *const *slots, int count, NSString *why) {
    if (count < 1 || !slots[0]) return;
    if (count < 2 || DMNativeActiveApp()) { DMLayoutFrontWindow(@(slots[0]), why); return; }
    NSString *front = [DMActiveApp() bundleIdentifier];
    if (!front.length) return;
    if (DMSMEngine()) {
        NSString *frontKey = DMSMFrontWindowKey();
        if (![DMSMKeyBundle(frontKey) isEqualToString:front]) frontKey = front;
        frontKey = DMSMWindowKeyOf(frontKey);   // (as above, audit 1.8.3 L3)
        id stage = DMSMStageOf(frontKey);
        NSDictionary *map = DMSMStageItemsMap(stage);
        NSSet *onScreen = [NSSet setWithArray:DMSMWindowKeys()];
        NSMutableArray *items = [NSMutableArray array];
        // (the windows behind: other apps' only -- every window of the front app is left out, as the other engines leave it out below, where an app
        //  has one window; two Safari windows and Notes: Safari next to Notes on every engine. Audit 1.8.3 L4: here only the front window was)
        for (id it in map) { NSString *k = DMSMItemKey(it); if (k && [onScreen containsObject:k] && ![DMSMKeyBundle(k) isEqualToString:front] && !DMSMAttrsFullScreen(map[it])) [items addObject:it]; }
        [items sortUsingComparator:^NSComparisonResult(id a, id b) {   // (newest first: the window behind the front one first)
            long ta = DMSMAttrTimeOr(map[a], 0), tb = DMSMAttrTimeOr(map[b], 0);
            return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
        }];
        NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithObject:frontKey];
        for (id it in items) { NSString *k = DMSMItemKey(it); if (k && (int)keys.count < count) [keys addObject:k]; }
        NSMutableDictionary<NSString *, NSString *> *plan = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < keys.count; i++) {
            if (!slots[i]) continue;
            DMWinPrevNoteSM(keys[i], stage);
            for (NSString *k in [gSMTurnPlaced allKeys]) if (DMSMKeyCovers(keys[i], k)) [gSMTurnPlaced removeObjectForKey:k];   // (a layout now, as DMWindowLayout's)
            plan[keys[i]] = @(slots[i]);
        }
        DMTitleRecordSMPlan(plan, stage);   // (each a placement of ours: the title bar's frame from before follows it, P4-1)
        BOOL ok = DMSMApplyLayoutsIn(plan, stage);
        if (ok) for (NSString *k in plan) DMSMFitLetGo(k);   // (each placed by a layout of its own: out of Fit to Window's tiles, as below)
        DMLog([NSString stringWithFormat:@"[winkeys] %@: %@ (%@)", why, plan, ok ? @"done" : @"not in the stage"]);
        return;
    }
    DMLayoutFrontWindow(@(slots[0]), why);
    NSMutableArray<UIView *> *behind = [NSMutableArray array];   // (front first)
    for (UIView *s in [DMAerialStages() reverseObjectEnumerator]) {
        NSString *b = DMStageBundle(s);
        if (s.hidden || DMStageMinimized(s) || DMWindowMinimized(s) || !b.length || [b isEqualToString:front]) continue;
        if ([objc_getAssociatedObject(s, kStageClosingKey) boolValue]) continue;
        [behind addObject:s];
    }
    gMoveKeepsOrder = YES;   // (the front window stays in front)
    NSMutableArray *done = [NSMutableArray array];
    for (NSUInteger i = 0; i < behind.count && (int)i + 1 < count; i++) {
        UIView *s = behind[i];
        NSString *slot = slots[i + 1] ? @(slots[i + 1]) : nil;
        CGRect f = slot ? DMLayoutFrame(slot) : CGRectNull;
        if (CGRectIsNull(f)) continue;
        DMWinPrevNoteView(s, DMWinTiledEngine(s.frame), s.frame);
        objc_setAssociatedObject(s, &kStageTurnPlacedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (a layout now, as DMWindowLayout's)
        DMFitGroupForget(DMStageBundle(s));   // (placed by a layout of its own: out of Fit to Window's tiles, as the front one)
        DMTitleRecordEngineTo(s, f);   // (as above; the front one through DMWindowLayout)
        DMAerialMoveStage(s, f, nil);
        if (DMActiveEngine() == DMEngineAerial && gAerialFlavor == 5 && !DMTestFlag("/tmp/msb-a5-nohold")) DMA5HoldStageAt(s, f, CACurrentMediaTime() + 1.5);
        [done addObject:[NSString stringWithFormat:@"%@ %@", DMStageBundle(s), slot]];
    }
    gMoveKeepsOrder = NO;
    DMLog([NSString stringWithFormat:@"[winkeys] %@: the windows behind %@ -> %@", why, front, done.count ? [done componentsJoinedByString:@", "] : @"none"]);
}


// How the keys reach SpringBoard (read on the M1, 15.6.1, with the keys_ tool's HID events):
//  - With an app in front the keyboard is the app's: backboardd hands SpringBoard only the keys its registered key commands name (as the Mac
//    Switcher's Control-arrows, MacSwitcher.h DMMSWKeysRefresh) and iPadOS's own system shortcuts. Globe-Control-Left, -Right and -Down came to
//    SpringBoard (iPadOS 15's own); Globe-Control-F, -C, -R and the Shift arrows went to the app. So our fifteen are key commands of
//    SpringBoard's own (-[SpringBoard keyCommands]), registered with backboardd again whenever the keys are offered or taken back.
//  - In SpringBoard they come as presses (-[SpringBoard pressesBegan:withEvent:], as VolumeGlobe reads its chords): a key command of SpringBoard's
//    with the Globe key never ran (5269ef7), Globe-Control-Left came as a press of key 0x50 with modifiers 0x840000. Each press is read as macOS
//    reads its shortcuts: the arrows by their place, F, C and R by the letter the keyboard layout types (WindowKeysRule.h MSBDWinKeyFor). A key
//    command that does run (another iPadOS) runs the same row, once.
// A press that is one of ours runs its row and is not handed on, so iPadOS's own handling of the same keys (15's Split View tiles for
// Globe-Control-Left / Right) does not run under it -- unless the row can't act now, then it is handed on (audit 1.8.3 L2); presses that came
// with it and are none of ours are handed on without it (review 1.8.3 F1: the
// whole set went on, ours too). Offered while the switch is on and a window engine of ours runs, or our own window is in front (P2-9). One press may come twice (VolumeGlobe.x: with an
// app in front): once.
static void (*o_WinKeysPressesBegan)(id, SEL, NSSet *, UIPressesEvent *);
static NSArray *(*o_WinKeysKeyCommands)(id, SEL);
static NSArray<UIKeyCommand *> *gWinKeyCmds;   // (one per row, kMSBDWinKeyRows' order)
static BOOL DMWinKeysWanted(void) { return gWindowKeysOn && (DMActiveEngine() != DMEngineNone || DMSMEngine() || DMNativeActiveApp() != nil); }
// A row's action, unless SpringBoard is busy (WindowAPI.h: as the window API waits). Once per key: the same row asked again within 0.15 s is the
// same key, reported both as a key command and as a press. YES: the key is ours -- it acted, or it is that same key again; NO: it can't act now
// (the switch off, SpringBoard busy -- the App Switcher, Control Center, one of our menus --, no engine of ours and none of our own windows in
// front), so a press goes on to whoever else wants it: iPadOS 15's own Split View keys among them (audit 1.8.3 L2: swallowed, it did nothing).
static BOOL DMWinKeyRun(size_t i) {
    if (i >= kMSBDWinKeyRowCount || !gWindowKeysOn) return NO;
    MSBDWinKeyAction a = kMSBDWinKeyRows[i].act;
    NSString *title = @(a.title);
    notify_post(kMSBDModTapUsedNote);   // (the Globe and Control it began with are no volume or backlight tap)
    NSString *busy = DMWindowAPIBusyWhy();
    if (busy) { DMLog([NSString stringWithFormat:@"[winkeys] %@: not now (%@): the key goes on", title, busy]); return NO; }
    if (!DMNativeActiveApp() && !(DMActiveEngine() != DMEngineNone || DMSMEngine())) return NO;
    static size_t lastRow = (size_t)-1;
    static CFTimeInterval lastAt = -100;
    CFTimeInterval at = CACurrentMediaTime();
    if (i == lastRow && at - lastAt < 0.15) return YES;
    lastRow = i; lastAt = at;
    DM_FEATURE_MARK("window-tiling-keys");
    switch (a.kind) {
        case kMSBDWinKeyActLayout: DMLayoutFrontWindow(@(a.slots[0]), title); break;
        case kMSBDWinKeyActCenter: DMCenterFrontWindow(title); break;
        case kMSBDWinKeyActArrange: DMArrangeWindows(a.slots, a.count, title); break;
        case kMSBDWinKeyActPrevious: DMWindowBackFromTile(title); break;
        default: break;
    }
    return YES;
}
static void DMWinKeysPressesBegan(id self, SEL _cmd, NSSet<UIPress *> *presses, UIPressesEvent *event) {
    if (presses.count && DMWinKeysWanted()) {
        static NSTimeInterval lastTime = -1;
        static long lastCode = -1;
        NSMutableSet<UIPress *> *others = nil;   // (the presses that are none of ours: handed on)
        for (UIPress *p in presses) {
            UIKey *k = p.key;
            int row = k ? MSBDWinKeyRowFor(MSBDWinKeyFor((long)k.keyCode, k.charactersIgnoringModifiers.UTF8String), (unsigned long long)k.modifierFlags) : -1;
#if DEBUG
            if (k && ((unsigned long long)k.modifierFlags & (kMSBDModGlobe | kMSBDModControl))) DMLog([NSString stringWithFormat:@"[winkeys] press: key 0x%lx, types \"%@\", modifiers 0x%llx -> row %d", (long)k.keyCode, k.charactersIgnoringModifiers ?: @"", (unsigned long long)k.modifierFlags, row]);
#endif
            if (row < 0) { if (!others) others = [NSMutableSet set]; [others addObject:p]; continue; }
            // (the same press handed over again: its time and key -- not the object, which UIKit hands out again for a later press: read on 15.6.1,
            //  VolumeGlobe's log, one press object for two taps 4 s apart)
            if (p.timestamp == lastTime && (long)k.keyCode == lastCode) continue;
            lastTime = p.timestamp; lastCode = (long)k.keyCode;
            if (!DMWinKeyRun((size_t)row)) { if (!others) others = [NSMutableSet set]; [others addObject:p]; }   // (it can't act now: handed on)
        }
        if (others.count == presses.count) { o_WinKeysPressesBegan(self, _cmd, presses, event); return; }   // (none of ours: as it came)
        if (others.count) o_WinKeysPressesBegan(self, _cmd, others, event);   // (ours taken out, the others handed on)
        return;
    }
    o_WinKeysPressesBegan(self, _cmd, presses, event);
}
// Our key commands in SpringBoard's own list while the keys are offered (for backboardd: the keys an app in front does not get).
static NSArray *DMWinKeysKeyCommands(id self, SEL _cmd) {
    NSArray *orig = o_WinKeysKeyCommands(self, _cmd);
    if (gWinKeyCmds.count != kMSBDWinKeyRowCount || !DMWinKeysWanted()) return orig;
    NSMutableArray *all = [NSMutableArray arrayWithArray:[orig isKindOfClass:[NSArray class]] ? orig : @[]];
    [all addObjectsFromArray:gWinKeyCmds];
    return all;
}
// A key command of ours ran (its selector: dm_winKey<n>:): its row.
static void DMWinKeyCommandFired(id self, SEL _cmd, id sender) {
    NSString *s = NSStringFromSelector(_cmd);
    if (s.length < 11) return;
    NSInteger i = [[s substringWithRange:NSMakeRange(9, s.length - 10)] integerValue];   // ("dm_winKey" n ":")
#if DEBUG
    DMLog([NSString stringWithFormat:@"[winkeys] key command %@ ran", s]);
#endif
    if (i >= 0 && i < (NSInteger)kMSBDWinKeyRowCount) DMWinKeyRun((size_t)i);
}
static NSString *DMWinKeyInput(int key) {
    switch (key) {
        case kMSBDWinKeyLeft: return UIKeyInputLeftArrow;
        case kMSBDWinKeyRight: return UIKeyInputRightArrow;
        case kMSBDWinKeyUp: return UIKeyInputUpArrow;
        case kMSBDWinKeyDown: return UIKeyInputDownArrow;
        case kMSBDWinKeyF: return @"f";
        case kMSBDWinKeyC: return @"c";
        case kMSBDWinKeyR: return @"r";
        default: return nil;
    }
}
// backboardd takes SpringBoard's key commands only when UIKit registers them, at a first-responder change (-[UIApplication
// _updateSerializableKeyCommandsForResponder:], MacSwitcher.h): registered again each time the keys are offered or taken back (DMWindowKeysPublish).
// YES once done -- or when there is nothing to do here (no key commands of ours, UIKit's call not as read); NO while SpringBoard's application is
// not up yet (the switch is read in the constructor): asked again at the next tick.
static BOOL DMWindowKeysRegister(BOOL offered) {
    if (gWinKeyCmds.count != kMSBDWinKeyRowCount) return YES;
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return NO;
    if (!DMMSWHasMethod(object_getClass(app), @"_updateSerializableKeyCommandsForResponder:", @"v@:@")) return YES;
    @try { ((void (*)(id, SEL, id))objc_msgSend)(app, NSSelectorFromString(@"_updateSerializableKeyCommandsForResponder:"), nil); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[winkeys] the key commands' registration refused: %@", e.reason]); return YES; }
    DMLog([NSString stringWithFormat:@"[winkeys] key commands registered again: %@", offered ? @"Globe-Control with the arrows, F, C, R; with Shift; with Option-Shift" : @"none of ours"]);
    return YES;
}
// Once, the first time the switch is on: SpringBoard's presses hooked and our key commands added to its list (their exact types only).
static void DMWindowKeysInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class sb = objc_getClass("SpringBoard");
    if (!DMMSWHasMethod(sb, @"pressesBegan:withEvent:", @"v@:@@")) { DMLog(@"[winkeys] SpringBoard's key handler differs here: no Window Tiling Keys"); return; }
    MSHookMessageEx(sb, @selector(pressesBegan:withEvent:), (IMP)DMWinKeysPressesBegan, (IMP *)&o_WinKeysPressesBegan);
    if (DMMSWHasMethod(sb, @"keyCommands", @"@@:")) {
        NSMutableArray *cmds = [NSMutableArray array];
        SEL prio = NSSelectorFromString(@"setWantsPriorityOverSystemBehavior:");   // (iPadOS 15+: before a text field's own arrow handling)
        for (size_t i = 0; i < kMSBDWinKeyRowCount; i++) {
            SEL sel = NSSelectorFromString([NSString stringWithFormat:@"dm_winKey%zu:", i]);
            class_addMethod(sb, sel, (IMP)DMWinKeyCommandFired, "v@:@");
            UIKeyCommand *c = [UIKeyCommand keyCommandWithInput:DMWinKeyInput(kMSBDWinKeyRows[i].key) modifierFlags:(UIKeyModifierFlags)kMSBDWinKeyRows[i].mods action:sel];
            if (!c) { cmds = nil; break; }
            c.discoverabilityTitle = @(kMSBDWinKeyRows[i].act.title);
            if ([c respondsToSelector:prio]) ((void (*)(id, SEL, BOOL))objc_msgSend)(c, prio, YES);
            [cmds addObject:c];
        }
        if (cmds.count == kMSBDWinKeyRowCount) {
            gWinKeyCmds = cmds;
            MSHookMessageEx(sb, @selector(keyCommands), (IMP)DMWinKeysKeyCommands, (IMP *)&o_WinKeysKeyCommands);
        } else DMLog(@"[winkeys] a key command could not be made: the keys reach SpringBoard only while it has the keyboard");
    } else DMLog(@"[winkeys] SpringBoard has no key commands of its own here: the keys reach it only while it has the keyboard");
    DMLog([NSString stringWithFormat:@"[winkeys] SpringBoard's presses read for Globe-Control with the arrows, F, C, R; with Shift; with Option-Shift (%lu key commands)", (unsigned long)gWinKeyCmds.count]);
}
// Whether the keys are offered now -- the switch on and a window engine of ours running, or our own window in front --, for the volume and backlight chords, which wait for their
// key's release only then (common/ModifierTap.h; review 1.8.3 F8: they waited with the switch on and no engine, for keys that could not act). Set as
// a state with SpringBoard's pid, posted when it changes: the switch read (DMWindowKeysApply), the engine known or changed (each tick: it settles a
// few seconds after a respring, DMActiveEngine).
static void DMWindowKeysPublish(void) {
    static int token = 0, last = -1, registered = -1;
    if (!token && notify_register_check(kMSBDWindowKeysOfferedNote, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    int now = DMWinKeysWanted() ? 1 : 0;
    if (now != last) {
        last = now;
        notify_set_state(token, MSBDWindowKeysOfferedState(now, getpid()));
        notify_post(kMSBDWindowKeysOfferedNote);
        DMLog([NSString stringWithFormat:@"[winkeys] the keys are %@ (the volume and backlight chords %@)", now ? @"offered" : @"not offered", now ? @"act at their release" : @"act as their key goes down"]);
    }
    if (now != registered && DMWindowKeysRegister(now)) registered = now;   // (and backboardd told which keys SpringBoard takes from an app in front)
}
// The switch read (DMLoadPrefs): the hook installed when first on; each press asks the switch and the engine. Off, the records go too.
static void DMWindowKeysApply(void) {
    if (gWindowKeysOn) DMWindowKeysInstall();
    if (!DMWinPrevWanted()) gSMWinPrev = nil;
    if (!MSBDTitleKeepsFrames(gTitleDoubleTap)) gSMWinZoom = nil;   // (the title bar's Fill / Zoom records go with the setting: review 1.8.3 P2-5)
    DMWindowKeysPublish();
}

#if DEBUG
// winkeys: the switch, whether the keys are taken now, SpringBoard's key commands with Globe or Control (read only). winkey_<n>: row n run as if its
// key was pressed (n as in kMSBDWinKeyRows; the arrangements and Globe-Control-R need windows to act on).
static void DMWindowKeysDebug(NSString *cmd) {
    if ([cmd isEqualToString:@"winkeys"]) {
        int t = 0; uint64_t st = 0;
        BOOL read = notify_register_check(kMSBDWindowKeysOfferedNote, &t) == NOTIFY_STATUS_OK && notify_get_state(t, &st) == NOTIFY_STATUS_OK;
        if (t) notify_cancel(t);
        NSMutableString *o = [NSMutableString stringWithFormat:@"[winkeys] switch %d, taken now %d, hooked %d, offered to the chords %@, records %lu on Stage Manager; SpringBoard's key commands with Globe or Control:",
                              gWindowKeysOn, DMWinKeysWanted(), o_WinKeysPressesBegan != NULL, read ? (MSBDWindowKeysOfferedIn(st, getpid()) ? @"yes" : @"no") : @"unread", (unsigned long)gSMWinPrev.count];
        for (UIKeyCommand *c in [[UIApplication sharedApplication] keyCommands]) {
            if (![c isKindOfClass:[UIKeyCommand class]] || !((unsigned long long)c.modifierFlags & (kMSBDModGlobe | kMSBDModControl))) continue;
            [o appendFormat:@"\n  %@ mod 0x%llx -> %@%@", c.input, (unsigned long long)c.modifierFlags, NSStringFromSelector(c.action), c.discoverabilityTitle.length ? [NSString stringWithFormat:@" (%@)", c.discoverabilityTitle] : @""];
        }
        DMLog(o);
    } else if ([cmd hasPrefix:@"winkey_"]) {
        NSInteger i = [[cmd substringFromIndex:7] integerValue];
        if (i >= 0) DMWinKeyRun((size_t)i);
    }
}
#endif
