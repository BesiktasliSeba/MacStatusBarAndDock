// SMFitPlan.h -- which windows Fit to Window tiles on a Stage Manager desktop, and where (sm-nolimit, 4 Oct 2026). Plain Foundation: StatusBar.x's
// DMSMFitTick and the Mac tests tools/test-smroles.m and tools/test-smfitclosed.m (the windows that closed) run this very code.
// Until sm-nolimit a desktop held four windows, so the tiles (2: halves, 3: a half and two quarters, 4: quarters) always covered every window.
// With more windows the other engines' rule applies (Aerial / Zetsu / MilkyWay4, StatusBar.x: "four windows are already tiled, X opens as a
// regular window over them"): while four windows are tiled and all still open, a fifth and every one after it is a regular window over them and
// the four keep their places; before, the default arrangement was laid out again for the four NEWEST, so the new window took a quarter and the
// oldest tile lost its place. Once a tile closes, the newest windows (at most four) are tiled again, each keeping its place (FitPlan.h).
#pragma once
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"   // (a window's key, or its app's: DMSMKeyCovers -- which windows are still there, DMSMFitClosedKeys)
#include "FitPlan.h"       // (where the windows go when the set changes: a window keeps its place, the one rule of every engine -- 1.8.0)

enum { DMSMFitDefault = 0, DMSMFitKept = 1, DMSMFitFourKept = 2 };
// slots: the arrangement kept (window key -> slot name, SMWindowKey.h: two windows of one app are two tiles), or nil; bundles: the desktop's
// windows that take part (their keys), newest first; defaults: the default slot names for MIN(4, bundles.count) windows (StatusBar.x
// DMDefaultSlotNames): how many are tiled. Returns the plan (window key -> slot); *how: DMSMFitKept = the
// arrangement as it is (it covers exactly these windows), DMSMFitFourKept = four tiles kept and the windows past them left as they are (nothing
// to lay out), DMSMFitDefault = the newest windows tiled again, each keeping its place in slots and a new one taking the first tile (FitPlan.h
// MSBDFitPlanKeepingPlaces; the caller keeps it as the new arrangement). Before 1.8.0 the windows took the default tiles in the order of their last
// use, the other engines' in the order they had joined (iPad 2 16.7.7, M1 15.6.1, 3 Nov: on a fourth window, Maps went from the left half to the
// bottom-left quarter here and to the bottom-right one with Aerial).
static NSDictionary<NSString *, NSString *> *DMSMFitPlanDecide(NSDictionary<NSString *, NSString *> *slots, NSArray<NSString *> *bundles, NSArray<NSString *> *defaults, int *how) {
    BOOL keep = slots.count == bundles.count;
    for (NSString *b in bundles) if (!slots[b]) keep = NO;
    if (keep) { if (how) *how = DMSMFitKept; return [slots copy]; }
    if (slots.count >= 4 && bundles.count > slots.count) {
        BOOL allOpen = YES;
        for (NSString *b in slots) if (![bundles containsObject:b]) allOpen = NO;
        if (allOpen) { if (how) *how = DMSMFitFourKept; return [slots copy]; }
    }
    if (how) *how = DMSMFitDefault;
    NSUInteger n = MIN(bundles.count, defaults.count);
    return n ? MSBDFitPlanKeepingPlaces([bundles subarrayWithRange:NSMakeRange(0, n)], slots) : @{};
}
// The windows Fit to Window tiles at a look (1.8.0 engine parity, KT 3 Nov): the other engines' rule, one window at a time as they opened (FitPlan.h
// MSBDFitWhenOneOpens). A window with a tile is tiled. A window Fit knows nothing of (it opened since the last look) joins the tiles while fewer
// than four other windows take part on the desktop -- the regular windows there joining with it --, or is a regular window over the tiles itself. A
// regular window (loose: Fit left it out, four taking part when it opened) stays where it is, also when a tile closes. A set Fit knows nothing of
// -- Fit switched on with windows open, the first windows of a desktop, one come back with no arrangement to read -- is tiled as such: the newest
// four, the rest regular (the other engines' DMTileOpenWindows). Before 1.8.0 the newest four windows were tiled again at every change of the set:
// with five windows a tile that closed was taken by the fifth, a regular window over the four, where the other engines leave it (iPad 2 16.7.7
// against M1 15.6.1, 3 Nov), and two windows opening at once took a tile from a window tiled before them.
// bundles: the desktop's windows that take part (not No Fit), newest first; slots: the arrangement; loose: the regular windows (keys). Returns the
// windows to tile (MSBDFitPlanKeepingPlaces' order: the new and joining ones first), at most four; *looseOut: the regular windows after this look
// (loose with the ones that joined taken out and the new ones left out added; windows not on screen now stay as they are).
static NSArray<NSString *> *DMSMFitTakingPart(NSArray<NSString *> *bundles, NSDictionary<NSString *, NSString *> *slots, NSSet<NSString *> *loose, NSSet<NSString *> **looseOut) {
    NSMutableArray<NSString *> *tiled = [NSMutableArray array], *regular = [NSMutableArray array], *fresh = [NSMutableArray array];
    NSMutableSet<NSString *> *after = loose ? [loose mutableCopy] : [NSMutableSet set];
    for (id b in bundles) {
        if (![b isKindOfClass:[NSString class]] || ![(NSString *)b length] || [tiled containsObject:b] || [regular containsObject:b] || [fresh containsObject:b]) continue;
        if ([slots isKindOfClass:[NSDictionary class]] && slots[b]) { [tiled addObject:b]; [after removeObject:b]; }
        else if ([loose containsObject:b]) [regular addObject:b];
        else [fresh addObject:b];
    }
    NSArray<NSString *> *part = tiled;
    if (!tiled.count && !regular.count) {   // (nothing of the set known: tiled as a new set, the newest four)
        part = fresh.count > 4 ? [fresh subarrayWithRange:NSMakeRange(0, 4)] : [fresh copy];
        for (NSString *f in fresh) if (![part containsObject:f]) [after addObject:f];
    } else for (NSString *f in fresh.reverseObjectEnumerator) {   // (oldest first: as they opened)
        NSArray<NSString *> *joined = MSBDFitWhenOneOpens(f, part, regular);
        if (joined) { for (NSString *r in regular) [after removeObject:r]; [regular removeAllObjects]; part = joined; }
        else { [regular insertObject:f atIndex:0]; [after addObject:f]; }
    }
    if (looseOut) *looseOut = after;
    return part;
}
// The arrangement remembered for a desktop -- keyed by its windows (their keys, sorted): another stage on screen in between (a window of its own, a
// leftover stage) used to replace or drop the one global arrangement, and back on the desktop the default arrangement was laid out again for the
// four newest -- with seven windows the three tiled before were then buried under the new tiles (1.3.6 logic test L-7). memory: key -> slots.
static NSString *DMSMFitDeskKey(NSArray<NSString *> *bundles) { return [[bundles sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"]; }
// The slots to decide with: the current ones when they still cover these windows (DMSMFitPlanDecide keeps them, or keeps four tiles), else the
// arrangement remembered for exactly these windows, else the current ones (the default arrangement follows).
static NSDictionary<NSString *, NSString *> *DMSMFitSlotsFor(NSDictionary<NSString *, NSString *> *current, NSDictionary<NSString *, NSDictionary *> *memory, NSArray<NSString *> *bundles) {
    int how = DMSMFitDefault;
    DMSMFitPlanDecide(current, bundles, @[], &how);
    if (how != DMSMFitDefault) return current;
    NSDictionary *mem = memory[DMSMFitDeskKey(bundles)];
    return mem.count ? mem : current;
}
// A window Fit to Window remembers that has CLOSED is forgotten, its tile with it, as the other engines' closure watcher forgets a closed window's
// tile (StatusBar.x DMWatchFitClosures): the app's next window is a new window -- Window Size's place, or tiled with the desktop's windows as any
// new window. Closed: no stage of SpringBoard's has it any more. A window only out of sight keeps what Fit has for it: present holds every window of
// every recent stage, the hidden ones too -- a minimized window waits in a hidden stage of its own and comes back into its tile (or as No Fit), a
// window of another Mac Switcher desktop in that desktop's stage, one in full screen in its own. Before 1.8.0 a closed window's tile stayed: the
// desktop's last tiled window (filling the space) closed, and the app's next window -- its default scene, so the same key -- opened filling the
// desktop instead of at Window Size's place (iPad 2, 16.7.7, the 1.8.0 engine parity pass). keys: what Fit remembers (window keys; app keys for an
// app asked about before its window existed); a window key is there when present has it or its app's key (windows told apart by app,
// SMWindowKey.h), an app key while one of the app's windows is there; pending: app keys asked about before their launch, whose window is still to
// come. Returns the keys that closed.
static NSSet<NSString *> *DMSMFitClosedKeys(id<NSFastEnumeration> keys, NSSet<NSString *> *present, NSSet<NSString *> *pending) {
    NSMutableSet<NSString *> *closed = [NSMutableSet set];
    for (NSString *k in keys) {
        if (![k isKindOfClass:[NSString class]] || !k.length) continue;
        NSString *app = DMSMKeyBundle(k);
        if ([pending containsObject:k] || (app && [pending containsObject:app])) continue;
        BOOL there = [present containsObject:k];
        if (!there) for (NSString *p in present) if (DMSMKeyCovers(k, p) || DMSMKeyCovers(p, k)) { there = YES; break; }
        if (!there) [closed addObject:k];
    }
    return closed;
}
// The windows of an arrangement left once some of its windows closed, newest first -- times: each window's last interaction (Stage Manager's own
// order of a desktop's windows, as the Fit tick reads it); one with no time read goes after them, by key. They close up as when a tiled window
// closes on every engine, each keeping its place (FitPlan.h MSBDFitPlanKeepingPlaces: one fills the space, the others grow into the tile that
// closed), the plan Stage Manager's own Close lays out in its transition (DMSMPlacesInClose) and a window leaving for another desktop leaves
// (DMMSWSMMoveFinish); this order only parts two windows that had one tile. (Before 1.8.0 it gave the default tiles: the window used last took the
// left half.) Empty: none left, nothing to remember.
static NSArray<NSString *> *DMSMFitLeftAfterClose(NSDictionary<NSString *, NSString *> *slots, NSSet<NSString *> *closed, NSDictionary<NSString *, NSNumber *> *times) {
    NSMutableArray<NSString *> *left = [NSMutableArray array];
    for (NSString *k in slots) if ([k isKindOfClass:[NSString class]] && ![closed containsObject:k]) [left addObject:k];
    [left sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSNumber *ta = times[a], *tb = times[b];
        if (ta && tb && [ta longLongValue] != [tb longLongValue]) return [ta longLongValue] > [tb longLongValue] ? NSOrderedAscending : NSOrderedDescending;
        if (ta && !tb) return NSOrderedAscending;
        if (!ta && tb) return NSOrderedDescending;
        return [a compare:b];
    }];
    return left;
}
// The arrangements remembered per desktop (DMSMFitSlotsFor) without every one that held a window that closed -- by its tiles or its set of windows
// (DMSMFitDeskKey): that set is gone, and the app's next window, the same key again, would take the closed window's tile from there. Returns the
// same object when nothing goes.
static NSDictionary<NSString *, NSDictionary *> *DMSMFitMemoryWithout(NSDictionary<NSString *, NSDictionary *> *memory, NSSet<NSString *> *closed) {
    if (!memory.count || !closed.count) return memory;
    NSMutableDictionary<NSString *, NSDictionary *> *out = nil;
    for (NSString *desk in memory) {
        NSDictionary *tiles = [memory[desk] isKindOfClass:[NSDictionary class]] ? memory[desk] : nil;
        NSArray<NSString *> *windows = [desk isKindOfClass:[NSString class]] ? [desk componentsSeparatedByString:@"\n"] : @[];
        BOOL held = NO;
        for (NSString *k in closed) if (tiles[k] || [windows containsObject:k]) { held = YES; break; }
        if (!held) continue;
        if (!out) out = [memory mutableCopy];
        [out removeObjectForKey:desk];
    }
    return out ?: memory;
}
// The desktop brought back after a respring, laid out for another screen shape (the iPad turned while SpringBoard restarted): its windows'
// sizes are of the old shape, but where they sit against each other is kept, and that names their tiles -- one window: the whole space; two:
// side by side (left / right) or one above the other (top / bottom), whichever way they are further apart; three: the side with one window is
// its half, the other side's two are its quarters, top and bottom (Fit's three-window arrangement); four: the quarters. centres: window key ->
// @[x, y], its centre as fractions of the screen. nil when they do not read as distinct tiles (Fit then lays them out as a new set).
static inline NSDictionary<NSString *, NSString *> *DMSMFitTilesFromCentres(NSDictionary<NSString *, NSArray<NSNumber *> *> *centres) {
    NSArray<NSString *> *keys = [centres.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger n = keys.count;
    if (!n || n > 4) return nil;
    for (NSString *k in keys) {
        NSArray *p = centres[k];
        if (![p isKindOfClass:[NSArray class]] || p.count != 2) return nil;
        double x = [p[0] doubleValue], y = [p[1] doubleValue];
        if (!(x >= -0.25 && x <= 1.25) || !(y >= -0.25 && y <= 1.25)) return nil;   // (not finite, or far off the screen)
    }
    double (^X)(NSString *) = ^double(NSString *k) { return [centres[k][0] doubleValue]; };
    double (^Y)(NSString *) = ^double(NSString *k) { return [centres[k][1] doubleValue]; };
    if (n == 1) return @{ keys[0]: @"fill" };
    if (n == 2) {
        NSString *a = keys[0], *b = keys[1];
        double dx = fabs(X(a) - X(b)), dy = fabs(Y(a) - Y(b));
        if (dx < 0.05 && dy < 0.05) return nil;   // (one on the other: no tiles to read)
        if (dx >= dy) return X(a) < X(b) ? @{ a: @"left", b: @"right" } : @{ a: @"right", b: @"left" };
        return Y(a) < Y(b) ? @{ a: @"top", b: @"bottom" } : @{ a: @"bottom", b: @"top" };
    }
    NSMutableArray<NSString *> *left = [NSMutableArray array], *right = [NSMutableArray array];
    for (NSString *k in keys) [(X(k) < 0.5 ? left : right) addObject:k];
    NSComparisonResult (^byY)(NSString *, NSString *) = ^NSComparisonResult(NSString *a, NSString *b) { return Y(a) < Y(b) ? NSOrderedAscending : (Y(a) > Y(b) ? NSOrderedDescending : [a compare:b]); };
    NSMutableDictionary<NSString *, NSString *> *plan = [NSMutableDictionary dictionary];
    if (n == 3) {
        if (left.count == 1 && right.count == 2) { [right sortUsingComparator:byY]; plan[left[0]] = @"left"; plan[right[0]] = @"topright"; plan[right[1]] = @"bottomright"; }
        else if (left.count == 2 && right.count == 1) { [left sortUsingComparator:byY]; plan[right[0]] = @"right"; plan[left[0]] = @"topleft"; plan[left[1]] = @"bottomleft"; }
        else return nil;
        return plan;
    }
    if (left.count != 2 || right.count != 2) return nil;   // (four: two on each side)
    [left sortUsingComparator:byY]; [right sortUsingComparator:byY];
    if (fabs(Y(left[0]) - Y(left[1])) < 0.05 || fabs(Y(right[0]) - Y(right[1])) < 0.05) return nil;
    plan[left[0]] = @"topleft"; plan[left[1]] = @"bottomleft"; plan[right[0]] = @"topright"; plan[right[1]] = @"bottomright";
    return plan;
}
