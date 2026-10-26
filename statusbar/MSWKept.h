// MSWKept.h -- the Mac Switcher's desktops kept while it is off, and what of them comes back when it is on again (1.5.2 item 14, KT: a feature
// turned off and on again gives back what it had, as the engine settings do). Plain Foundation: MacSwitcher.h gathers what is there now and
// applies the answer (DMMSWBringBack), and the Mac test tools/test-mswkept.m runs this very code.
//
// Kept (MacSwitcher.h DMMSWKeepForLater, as the Mac Switcher goes off): the desktops file's own fields -- "desktops" (ids), "current" (an id),
// "windows" (window key -> desktop id; SMWindowKey.h: Aerial / Zetsu / MilkyWay4 by app, Stage Manager by window), "frames", "fullscreen" (desktop
// id -> app), "leftSizes" (desktop id -> screen size), "fit" (desktop id -> its Fit to Window arrangement, the one on screen's too).
//
// Back (MSWKeptBringBack): every kept desktop, in its place (Desktop 1 first); each kept window on its desktop unless it went meanwhile, and each
// other desktop's full-screen app unless the user quit it meanwhile. What went is told apart from what merely is not running: a respring, a
// reboot or memory pressure while off end app processes too, and those come back as before (an away window by its relaunch when its desktop
// comes, MacSwitcher.h DMMSWRelaunchClosed; a full-screen app by its desktop). A quit is what records one -- the prewarm quit set (StatusBar.x:
// our red light, Force Quit, the App Switcher's swipe-up; kept across a respring; an app opened again leaves it) -- and only with the app gone
// now: Stage Manager, a window in no stage (Stage Manager keeps the windows of apps iPadOS closes in their stages: only a close takes one out);
// the other engines, an app on the quit set with no window now; a full-screen app, one on the quit set not running now. The quit set not known:
// kept (1.5.2 logic recheck R1: "not running" taken for "quit" dropped every full-screen app after "off, respring, on"). Told: what is there now
// can be told; not told -- the engine's windows or the stages not back yet after a start (MacSwitcher.h: the window restore's own state, Stage
// Manager's stages) --, everything kept comes back and the usual rules forget a closed one later. A window new since then: Desktop 1's. With Stage Manager a desktop is a stage, and a window opened
// meanwhile joined one (Stage Manager's own join): it goes to the desktop of the kept windows it is with -- Desktop 1 when they are of none or
// of several desktops --, and a minimized one to Desktop 1. The current desktop: Desktop 1, the one desktop of the time off; with Stage Manager the
// desktop of the stage on screen (Desktop 1 when it holds no kept window or kept windows of several desktops). What the screen shows stays the
// current desktop's own: its full-screen app and Fit to Window arrangement are not taken from the kept copy; the other desktops' are. Their screen
// size when left: kept with Stage Manager (their stages were not on screen); the screen as it is now with the other engines (every window was on
// screen while off, turned with it).
#pragma once
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"

// The desktop a window is recorded on in `windows`: its own key's record, else its app's (an app's record stands for its windows). An app key with
// no record of its own (windows known by app now, the engine's DMSMPerWindow off): a window of that app recorded by its own key, the first in key
// order (*byWindow: that key).
static NSNumber *MSWKeptRecordOf(NSDictionary<NSString *, NSNumber *> *windows, NSString *k, NSString **byWindow) {
    if (byWindow) *byWindow = nil;
    if (!k.length) return nil;
    NSNumber *d = windows[k];
    if (!d && !DMSMKeyIsApp(k)) d = windows[DMSMKeyBundle(k)];
    if (!d && DMSMKeyIsApp(k))
        for (NSString *w in [windows.allKeys sortedArrayUsingSelector:@selector(compare:)])
            if (!DMSMKeyIsApp(w) && [DMSMKeyBundle(w) isEqualToString:k]) { d = windows[w]; if (byWindow) *byWindow = w; break; }
    return d;
}

// In: kept (as written at the off), sm (Stage Manager is the engine), told, aliveKeys / aliveApps (the windows there now by key and by app; Stage
// Manager: stages' and minimized windows; other engines: apps with a window), stages (Stage Manager: each stage on the iPad's screen as the keys
// of its windows that are not minimized; front: the place of the one on screen, NSNotFound for none), minimized (Stage Manager's minimized
// windows' keys), windowApps (other engines: the apps with a window now), running (the apps running now; nil: not known), quit (the apps the
// user quit and has not opened since, the prewarm quit set; nil: not known -- nothing is taken for quit), screen (the screen's size now), maxDesks.
// Out: nil when nothing comes back (no kept copy, or one desktop); else desktops, current (a place), windows, frames, fullscreen, leftSizes, fit,
// gone (apps left out, each once), fresh (window key -> desktop id, the new ones), back (how many kept window records came back).
static NSDictionary *MSWKeptBringBack(NSDictionary *kept, BOOL sm, BOOL told, NSSet<NSString *> *aliveKeys, NSSet<NSString *> *aliveApps,
                                      NSArray<NSArray<NSString *> *> *stages, NSUInteger front, NSArray<NSString *> *minimized,
                                      NSArray<NSString *> *windowApps, NSSet<NSString *> *running, NSSet<NSString *> *quit, NSString *screen,
                                      NSUInteger maxDesks) {
    if (![kept isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray<NSNumber *> *desks = [NSMutableArray arrayWithObject:@1];
    NSArray *ids = kept[@"desktops"];
    if ([ids isKindOfClass:[NSArray class]])
        for (id n in ids) if ([n isKindOfClass:[NSNumber class]] && [n integerValue] > 1 && ![desks containsObject:@([n integerValue])] && desks.count < maxDesks) [desks addObject:@([n integerValue])];
    if (desks.count < 2) return nil;
    NSDictionary *w = [kept[@"windows"] isKindOfClass:[NSDictionary class]] ? kept[@"windows"] : nil, *f = [kept[@"frames"] isKindOfClass:[NSDictionary class]] ? kept[@"frames"] : nil;
    NSDictionary *fs = [kept[@"fullscreen"] isKindOfClass:[NSDictionary class]] ? kept[@"fullscreen"] : nil, *ls = [kept[@"leftSizes"] isKindOfClass:[NSDictionary class]] ? kept[@"leftSizes"] : nil;
    NSDictionary *fit = [kept[@"fit"] isKindOfClass:[NSDictionary class]] ? kept[@"fit"] : nil;
    NSMutableDictionary<NSString *, NSNumber *> *windows = [NSMutableDictionary dictionary], *fresh = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *frames = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    NSUInteger back = 0;
    for (id k in w) {
        if (![k isKindOfClass:[NSString class]] || ![k length] || ![w[k] isKindOfClass:[NSNumber class]] || ![desks containsObject:w[k]]) continue;
        NSString *b = DMSMKeyBundle(k);
        // (Stage Manager: that very window -- an app's record: any window of the app; a window's record where windows are known by app: the app's.
        //  Other engines: gone only when the user quit the app and it has no window now -- an app iPadOS closed is opened again by its desktop)
        BOOL here = !told || (sm ? ([aliveKeys containsObject:k] || (DMSMKeyIsApp(k) && [aliveApps containsObject:k]) || (!DMSMKeyIsApp(k) && [aliveKeys containsObject:b]))
                                 : (!quit || ![quit containsObject:b] || [aliveApps containsObject:b]));
        if (!here) { if (b.length && ![gone containsObject:b]) [gone addObject:b]; continue; }
        windows[k] = w[k];
        if ([f[k] isKindOfClass:[NSString class]]) frames[k] = f[k];
        back++;
    }
    NSUInteger cur = 0;
    if (sm) {
        for (NSUInteger i = 0; i < stages.count; i++) {
            NSMutableSet<NSNumber *> *on = [NSMutableSet set];
            NSMutableArray<NSString *> *mine = [NSMutableArray array];
            for (NSString *k in stages[i]) {
                if (![k isKindOfClass:[NSString class]] || !k.length) continue;
                NSString *byWindow = nil;
                NSNumber *d = MSWKeptRecordOf(windows, k, &byWindow);
                if (d && byWindow) windows[k] = d;   // (known by app now: the app's record, as the tick's DMMSWSMRecordOf reads it)
                if (d) [on addObject:d]; else if (!fresh[k] && ![mine containsObject:k]) [mine addObject:k];
            }
            NSNumber *to = on.count == 1 ? on.anyObject : @1;
            for (NSString *k in mine) { windows[k] = to; fresh[k] = to; }
            if (i == front) { NSUInteger p = [desks indexOfObject:to]; cur = p == NSNotFound ? 0 : p; }
        }
        for (NSString *k in minimized) if ([k isKindOfClass:[NSString class]] && k.length && !MSWKeptRecordOf(windows, k, NULL)) { windows[k] = @1; fresh[k] = @1; }
    } else {
        for (NSString *b in windowApps) {
            if (![b isKindOfClass:[NSString class]] || !b.length || fresh[b]) continue;
            BOOL known = NO;   // (an app's window recorded by a Stage Manager window key since an engine change is its app's: DMMSWFoldWindowKeys)
            for (NSString *k in windows) if ([DMSMKeyBundle(k) isEqualToString:b]) { known = YES; break; }
            if (!known) { windows[b] = @1; fresh[b] = @1; }
        }
    }
    NSString *curKey = [desks[cur] stringValue];
    NSMutableDictionary<NSString *, NSString *> *full = [NSMutableDictionary dictionary], *left = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *fits = [NSMutableDictionary dictionary];
    for (NSNumber *d in desks) {
        NSString *dk = d.stringValue;
        if ([dk isEqualToString:curKey]) continue;   // (the desktop on screen: what is there now is its own)
        if ([fs[dk] isKindOfClass:[NSString class]] && [fs[dk] length]) {
            // (out only when the user quit it -- on the quit set -- and it is not running now: its desktop must not launch it again. Not running
            //  alone -- a respring, memory -- is no quit: kept, and its desktop opens it again as before)
            BOOL quitNow = told && quit && [quit containsObject:fs[dk]] && !(running && [running containsObject:fs[dk]]);
            if (!quitNow) full[dk] = fs[dk];
            else if (![gone containsObject:fs[dk]]) [gone addObject:fs[dk]];
        }
        if (!sm) { if (screen.length) left[dk] = screen; }
        else if ([ls[dk] isKindOfClass:[NSString class]]) left[dk] = ls[dk];
        if ([fit[dk] isKindOfClass:[NSDictionary class]]) fits[dk] = fit[dk];
    }
    return @{@"desktops": desks, @"current": @(cur), @"windows": windows, @"frames": frames, @"fullscreen": full, @"leftSizes": left, @"fit": fits,
             @"gone": gone, @"fresh": fresh, @"back": @(back)};
}
