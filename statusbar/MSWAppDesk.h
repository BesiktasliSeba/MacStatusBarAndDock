// MSWAppDesk.h -- where an app opens when its windows are on other Mac Switcher desktops (1.7.1 item 5; KT, 30 Oct: "when i try to launch an app
// from the dock that is open on another desktop, it takes me to that desktop. Instead it should come up on whichever desktop I am on"). Plain
// Foundation: MacSwitcher.h (Aerial, Zetsu, MilkyWay4) and MacSwitcherSM.h (Stage Manager) gather the app's windows and act on the answer; the Mac
// test tools/test-mswappdesk.m runs this very code.
// Opening an app -- the Dock, the Home Screen, Command-Tab, the Go menu, Spotlight's apps, a link, a notification, an App Switcher card -- whose
// windows are all on other desktops:
//  - Bring (the default): its newest window comes to the desktop on screen and comes forward there; the desktop stays;
//  - Go (Settings > Windows & Multitasking > Go to the App's Desktop on): that window's desktop comes, the window in front there -- a Mac's "switch
//    to a Space with open windows for the application", and what every version before 1.7.1 did.
// A window of the app on the desktop on screen: Stay -- nothing moves, the launch brings that window forward as always. A full-screen app left on
// another desktop and a window whose app iPadOS closed while its desktop was away (Aerial, Zetsu, MilkyWay4: its record stays) are windows there
// too: the caller lists them, how recent they are says which one comes.
// (Spotlight's Windows rows are not launches: a row names its window's desktop, and picking it goes there -- SpotlightBridge.h.)
#pragma once
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"

typedef enum { DMMSWAppDeskStay = 0, DMMSWAppDeskGo = 1, DMMSWAppDeskBring = 2 } DMMSWAppDeskWay;
// windows: the app's windows on every desktop, each @{@"k": its key (SMWindowKey.h; Aerial / Zetsu / MilkyWay4: the app), @"d": its desktop's id,
// @"t": how recent (larger: newer)}. cur: the id of the desktop on screen. key: what the launch names -- a window key (that window), or an app key
// (the app's windows). goToDesktop: the Settings switch. *pick: the window that comes (Go, Bring) -- the newest of those the key names, the first
// of equals --, else NSNotFound.
static DMMSWAppDeskWay DMMSWAppDeskDecide(NSArray<NSDictionary *> *windows, NSInteger cur, NSString *key, BOOL goToDesktop, NSUInteger *pick) {
    if (pick) *pick = NSNotFound;
    if (![key isKindOfClass:[NSString class]] || !key.length || ![windows isKindOfClass:[NSArray class]]) return DMMSWAppDeskStay;
    NSUInteger best = NSNotFound; long long bestT = LLONG_MIN;
    for (NSUInteger i = 0; i < windows.count; i++) {
        NSDictionary *w = windows[i];
        if (![w isKindOfClass:[NSDictionary class]]) continue;
        NSString *k = w[@"k"];
        id d = w[@"d"], t = w[@"t"];
        if (![k isKindOfClass:[NSString class]] || ![d isKindOfClass:[NSNumber class]] || !(DMSMKeyCovers(key, k) || DMSMKeyCovers(k, key))) continue;
        if ([d integerValue] == cur) return DMMSWAppDeskStay;   // (a window here: it comes forward here, as always)
        long long tt = [t isKindOfClass:[NSNumber class]] ? [t longLongValue] : 0;
        if (best == NSNotFound || tt > bestT) { best = i; bestT = tt; }
    }
    if (best == NSNotFound) return DMMSWAppDeskStay;   // (no window anywhere: a launch, on this desktop)
    if (pick) *pick = best;
    return goToDesktop ? DMMSWAppDeskGo : DMMSWAppDeskBring;
}
