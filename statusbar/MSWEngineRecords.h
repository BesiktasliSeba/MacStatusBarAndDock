// MSWEngineRecords.h -- the Mac Switcher's window records across an engine change. Plain Foundation: MacSwitcher.h and MacSwitcherSM.h call this very
// code, and the Mac test tools/test-mswenginerecords.m runs it.
// The desktops stay when the engine changes, and neither kind of engine sees the other's windows. Stage Manager's stay in its stages, Apple's, while
// another engine runs; it records each by its key, "<bundle>|<scene>" (SMWindowKey.h). Aerial's, Zetsu's and MilkyWay4's stay in their saved window
// state while Stage Manager runs (StatusBar.x DMSaveWindowState); they record one window per app. So a record of the other kind is no closed window.
// Taken for one, the current desktop's windows were forgotten within a second of the change and the desktop was empty when Stage Manager came back,
// its windows off the screen in their stages (A12Z, re-check of 1.8.1, and the same on published 1.8.0.1; a window key used to be moved to its app).
//  - Another engine takes over from Stage Manager: each window keeps its record, and its app gets a copy, as these engines look a window up by its app
//    (two windows of one app on two desktops: the first by key, they have one window per app). Once per stay: their rule for closed windows then
//    forgets the copy of the current desktop's, and a copy made again would come back with every start. Made right before the engine's restore, after what
//    was put aside has come back (MacSwitcher.h DMMSWRecordsBeforeRestore).
//  - Their rule for closed windows: an app with no window here, on the current desktop. A window key is never one: that window is in its stage.
//  - Stage Manager's first tick in a start, windows known by window (the engine's DMSMPerWindow): each app's record in the file is another engine's window
//    (its copy of a window's record too: the saved state tells them apart below): put aside, also with a Stage Manager window of that app, each engine its
//    own. An entry already aside stays: no such engine has run since it was put there, so the record that came now is Stage Manager's. App records written
//    later are Stage Manager's own -- a launch by app before its scene, DMMSWSMJoin -- and are not kept: their windows get their own records, and a
//    user who never changes engine has nothing aside (code review 1.8.1.1, finding 1: put aside at the forgetting, they overwrote the other engine's record).
//  - Stage Manager's check of a record whose window is in no stage, as it always was: closed, or an app's record whose windows have their own: it goes.
//    Where windows are known by app (DMSMPerWindow off) a window's record goes to its app's when the app is there.
//  - An engine of windows by app is back: what was put aside comes back for the windows its saved state is about to bring back, on a desktop that is still
//    there; a record the app has by now stays. The rest goes: those windows are gone.
#pragma once
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"

// Each window's record stays, its app gets a copy unless it has one (with the frame). Returns how many window records there are; 0: nothing to do.
static NSUInteger MSWRecordsCopyToApps(NSMutableDictionary<NSString *, NSNumber *> *windows, NSMutableDictionary<NSString *, NSString *> *frames) {
    NSUInteger n = 0;
    for (NSString *k in [windows.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (DMSMKeyIsApp(k)) continue;
        n++;
        NSString *b = DMSMKeyBundle(k);
        if (!b.length || windows[b]) continue;
        windows[b] = windows[k];
        if (frames[k]) frames[b] = frames[k];
    }
    return n;
}
// Does this record name a window of the engine that runs? (appsOnly: an engine of windows by app, MacSwitcher.h DMMSWAppKeysOnly: a Stage Manager window's is no window
// here -- a desktop's window set, the Dock's running dot of a window on another desktop)
static BOOL MSWRecordIsWindowHere(NSString *k, BOOL appsOnly) { return !appsOnly || DMSMKeyIsApp(k); }
// Aerial's, Zetsu's and MilkyWay4's rule: is this record a window closed here? (cur: the current desktop's id; alive: the apps with a window here)
static BOOL MSWRecordClosedHere(NSString *k, NSInteger desk, NSInteger cur, NSSet<NSString *> *alive) {
    return DMSMKeyIsApp(k) && desk == cur && ![alive containsObject:k];
}
// Stage Manager's first tick: every app's record is copied aside, an entry already there stays. Returns how many were put aside.
static NSUInteger MSWRecordsPutAside(NSDictionary<NSString *, NSNumber *> *windows, NSDictionary<NSString *, NSString *> *frames,
                                     NSMutableDictionary<NSString *, NSNumber *> *aside, NSMutableDictionary<NSString *, NSString *> *asideFrames) {
    NSUInteger n = 0;
    for (NSString *k in windows) {
        if (!DMSMKeyIsApp(k) || aside[k]) continue;
        aside[k] = windows[k];
        if (frames[k]) asideFrames[k] = frames[k];
        n++;
    }
    return n;
}
// Stage Manager's check, for a record whose window is in no stage (aliveApps: the apps with a window in a stage; perWindow: DMSMPerWindow).
typedef enum {
    MSWSMRecordClosed = 0,   // (forgotten)
    MSWSMRecordTaken,        // (an app's record, its windows have their own: it goes)
    MSWSMRecordToApp,        // (a window's record while windows are known by app, its app there: goes to its app's record)
} MSWSMRecordFate;
static MSWSMRecordFate MSWSMRecordFateOf(NSString *k, BOOL perWindow, NSSet<NSString *> *aliveApps) {
    if (DMSMKeyIsApp(k)) return [aliveApps containsObject:k] ? MSWSMRecordTaken : MSWSMRecordClosed;
    return !perWindow && [aliveApps containsObject:DMSMKeyBundle(k)] ? MSWSMRecordToApp : MSWSMRecordClosed;
}
// What is aside, read from the desktops file or the copy kept while the Mac Switcher is off (st): its two fields, checked. Nothing there: as they are.
static void MSWAsideRead(NSDictionary *st, NSMutableDictionary<NSString *, NSNumber *> *aside, NSMutableDictionary<NSString *, NSString *> *asideFrames) {
    NSDictionary *aw = st[@"asideWindows"], *af = st[@"asideFrames"];
    if ([aw isKindOfClass:[NSDictionary class]]) for (id k in aw) if ([k isKindOfClass:[NSString class]] && [aw[k] isKindOfClass:[NSNumber class]]) aside[k] = aw[k];
    if ([af isKindOfClass:[NSDictionary class]]) for (id k in af) if ([k isKindOfClass:[NSString class]] && [af[k] isKindOfClass:[NSString class]]) asideFrames[k] = af[k];
}
// What was put aside comes back for the apps in savedApps, on a desktop in desks. Returns how many; the caller lets the rest go.
static NSUInteger MSWRecordsFromAside(NSMutableDictionary<NSString *, NSNumber *> *windows, NSMutableDictionary<NSString *, NSString *> *frames,
                                      NSDictionary<NSString *, NSNumber *> *aside, NSDictionary<NSString *, NSString *> *asideFrames,
                                      NSArray<NSString *> *savedApps, NSArray<NSNumber *> *desks) {
    NSUInteger n = 0;
    for (NSString *b in savedApps) {
        NSNumber *d = aside[b];
        if (!d || windows[b] || ![desks containsObject:d]) continue;
        windows[b] = d;
        if (asideFrames[b]) frames[b] = asideFrames[b];
        n++;
    }
    return n;
}
