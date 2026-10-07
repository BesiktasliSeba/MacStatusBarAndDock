// Mac test of the Stage Manager engine's window keys (statusbar/SMWindowKey.h, M-2: each window known by its own scene, not by its app) and of
// Fit to Window with two windows of one app (statusbar/SMFitPlan.h with window keys). Run by test-smwindowkey.sh.
//  1. keys: made from a bundle and a scene identifier, taken apart again, read from a window card's name ("card:<bundle>:<uniqueIdentifier>",
//     the identifier has colons of its own), an app key when the identifier is not known.
//  2. which window a key names: the very window; an app key -> the app's newest window; a window that is gone -> none (never another window of
//     its app); windows known by app only (the optional rows missing) -> a window key still finds its app's window.
//  3. sets (minimized, behind the Dock, No Fit) and keyed dictionaries (the place before full screen): per window, an entry by app (saved by an
//     older version) covers the app's windows, taking a window back takes its app's entry too.
//  4. an arrangement made before its window existed (Fit's question before a launch) goes to the window once it is there.
//  5. Fit to Window: two windows of one app take two tiles (by app they shared one), the question's choice is kept for the new window; a sweep.
//  6. (1.3.9) a desktop "holds" a window asked for (the desktop choice), and the saved marks of windows that no longer exist (pruned after a start).
#import <Foundation/Foundation.h>
#include "../statusbar/SMWindowKey.h"
#include "../statusbar/SMFitPlan.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSDictionary *Win(NSString *k, long long t) { return @{@"k": k, @"t": @(t)}; }
static NSArray<NSString *> *Defaults(NSUInteger n) {   // (StatusBar.x DMDefaultSlotNames)
    if (n <= 1) return @[@"fill"];
    if (n == 2) return @[@"left", @"right"];
    if (n == 3) return @[@"left", @"topright", @"bottomright"];
    return @[@"topleft", @"topright", @"bottomleft", @"bottomright"];
}

int main(void) {
    @autoreleasepool {
        NSString *ff = @"com.apple.freeform", *clock = @"com.apple.mobiletimer";
        NSString *uA = @"sceneID:com.apple.freeform-1D6E1C0B-2F4A-4C1E-9B7A-0C5D3E2F1A90", *uB = @"sceneID:com.apple.freeform-7B3F0A11-55C2-4E8D-A1B4-9E0F6D2C8B37";
        NSString *kA = DMSMKeyMake(ff, uA), *kB = DMSMKeyMake(ff, uB), *kClock = DMSMKeyMake(clock, @"sceneID:com.apple.mobiletimer-default");

        // 1. keys
        CHECK(([kA isEqualToString:[ff stringByAppendingFormat:@"|%@", uA]]), "a window key: bundle|identifier (%s)", kA.UTF8String);
        CHECK([DMSMKeyBundle(kA) isEqualToString:ff] && [DMSMKeyUid(kA) isEqualToString:uA], "taken apart again");
        CHECK([DMSMKeyMake(ff, nil) isEqualToString:ff] && [DMSMKeyMake(ff, @"") isEqualToString:ff], "no identifier: the app key");
        CHECK(!DMSMKeyMake(nil, uA) && !DMSMKeyMake(@"", uA) && !DMSMKeyMake(@"a|b", uA), "no bundle (or a bundle with |): no key");
        CHECK(DMSMKeyIsApp(ff) && !DMSMKeyIsApp(kA) && !DMSMKeyIsApp(nil) && !DMSMKeyIsApp(@""), "app keys are bundles alone");
        CHECK([DMSMKeyBundle(ff) isEqualToString:ff] && !DMSMKeyUid(ff), "an app key's bundle is itself, no identifier");
        CHECK([DMSMKeyFromCardName([NSString stringWithFormat:@"card:%@:%@", ff, uA], YES) isEqualToString:kA], "a card's name: its window (the identifier's own colons kept)");
        CHECK([DMSMKeyFromCardName([NSString stringWithFormat:@"card:%@:%@", ff, uA], NO) isEqualToString:ff], "a card's name, windows by app: the app key");
        CHECK([DMSMKeyFromCardName(@"card:com.apple.Preferences:sceneID:com.apple.Preferences-default", YES) isEqualToString:@"com.apple.Preferences|sceneID:com.apple.Preferences-default"], "Settings' card");
        CHECK([DMSMKeyFromCardName(@"card:com.apple.Preferences", YES) isEqualToString:@"com.apple.Preferences"], "a card name without an identifier: the app key");
        CHECK(!DMSMKeyFromCardName(@"resize-grabber", YES) && !DMSMKeyFromCardName(nil, YES) && !DMSMKeyFromCardName(@"card:", YES), "not a card: no key");
        CHECK(DMSMKeyCovers(kA, kA) && DMSMKeyCovers(ff, kA) && DMSMKeyCovers(ff, kB) && !DMSMKeyCovers(kA, kB) && !DMSMKeyCovers(kA, ff) && !DMSMKeyCovers(clock, kA), "what covers what");

        // 2. picking a window
        NSArray *wins = @[Win(kClock, 30), Win(kA, 10), Win(kB, 20)];
        CHECK(DMSMKeyPick(wins, kA) == 1 && DMSMKeyPick(wins, kB) == 2, "a window key: that very window (A at 1, B at 2)");
        CHECK(DMSMKeyPick(wins, ff) == 2, "the app key: the app's newest window (B, t 20)");
        CHECK(DMSMKeyPick(wins, clock) == 0, "a one-window app by app key: its window");
        CHECK(DMSMKeyPick(@[Win(kClock, 30), Win(kB, 20)], kA) == NSNotFound, "A is gone: none -- never B instead");
        CHECK(DMSMKeyPick(wins, @"com.apple.Maps") == NSNotFound && DMSMKeyPick(wins, nil) == NSNotFound && DMSMKeyPick(@[], kA) == NSNotFound, "no such window: none");
        NSArray *byApp = @[Win(clock, 30), Win(ff, 10)];   // (windows known by app: the optional rows missing)
        CHECK(DMSMKeyPick(byApp, kA) == 1 && DMSMKeyPick(byApp, ff) == 1, "windows by app: a window key finds its app's window");
        CHECK(DMSMKeyPick(@[Win(kA, 5), Win(kA, 9)], kA) == 0, "two entries of one key (never seen): the first");

        // 3. sets and keyed dictionaries
        NSMutableSet *m = [NSMutableSet setWithObject:kA];
        CHECK(DMSMKeySetHas(m, kA) && !DMSMKeySetHas(m, kB), "minimized A: A is, B is not");
        CHECK(DMSMKeySetHas(m, ff), "asked by app: one of its windows is");
        CHECK(!DMSMKeySetHas(m, clock) && !DMSMKeySetHas(nil, kA) && !DMSMKeySetHas(m, nil), "nothing else");
        NSMutableSet *old = [NSMutableSet setWithObjects:ff, clock, nil];   // (saved by an older version: by app)
        CHECK(DMSMKeySetHas(old, kA) && DMSMKeySetHas(old, kB) && DMSMKeySetHas(old, kClock), "entries by app cover the app's windows");
        CHECK(DMSMKeySetRemove(old, kA) && ![old containsObject:ff] && [old containsObject:clock], "A opened again: the app's entry goes, the others stay");
        CHECK(!DMSMKeySetHas(old, kB), "and the app's other window is no longer covered by it");
        NSMutableSet *two = [NSMutableSet setWithObjects:kA, kB, kClock, nil];
        CHECK(DMSMKeySetRemove(two, kA) && [two containsObject:kB] && ![two containsObject:kA], "A taken back: B stays");
        CHECK(DMSMKeySetRemove(two, ff) && ![two containsObject:kB] && [two containsObject:kClock], "by app: every window of the app");
        CHECK(!DMSMKeySetRemove(two, kA), "nothing left to take: NO");
        NSDictionary *pre = @{kA: @"A's place", clock: @"Clock's place"};
        CHECK([DMSMKeyLookup(pre, kA) isEqualToString:kA] && !DMSMKeyLookup(pre, kB), "the place before full screen: A's for A, none for B");
        CHECK([DMSMKeyLookup(pre, ff) isEqualToString:kA], "by app: one of its windows' (A)");
        CHECK([DMSMKeyLookup(pre, kClock) isEqualToString:clock], "a window of an app saved by app: the app's entry");
        CHECK(!DMSMKeyLookup(pre, @"com.apple.Maps") && !DMSMKeyLookup(@{}, kA), "none");
        NSString *both = DMSMKeyLookup(@{kB: @1, kA: @2}, ff);
        CHECK([both isEqualToString:([kA compare:kB] == NSOrderedAscending ? kA : kB)], "by app with two windows' entries: a stable one");

        // 4. an arrangement made before its window existed
        NSDictionary *chosen = @{ff: @"topleft", clock: @"bottomleft", @"com.apple.weather|sceneID:com.apple.weather-default": @"right"};
        NSDictionary *ad = DMSMKeysAdopt(chosen, @[kA, kClock, @"com.apple.weather|sceneID:com.apple.weather-default"]);
        CHECK([ad[kA] isEqualToString:@"topleft"] && !ad[ff], "Freeform's window came: it takes the slot chosen for Freeform");
        CHECK([ad[kClock] isEqualToString:@"bottomleft"] && !ad[clock], "Clock's app key too (made by app)");
        CHECK(ad.count == 3, "nothing else changes (%lu)", (unsigned long)ad.count);
        NSDictionary *notYet = @{ff: @"topleft", kClock: @"left"};
        CHECK(DMSMKeysAdopt(notYet, @[kClock]) == notYet, "no window of the app yet: kept as it is (the same object)");
        NSDictionary *own = @{ff: @"topleft", kA: @"left"};
        ad = DMSMKeysAdopt(own, @[kB, kA]);
        CHECK([ad[kB] isEqualToString:@"topleft"] && [ad[kA] isEqualToString:@"left"] && !ad[ff], "A has its own slot: the app's slot goes to B");
        ad = DMSMKeysAdopt(@{ff: @"topleft"}, @[kB, kA]);
        CHECK([ad[kB] isEqualToString:@"topleft"] && !ad[kA], "two windows of the app, neither with a slot: the newest (B, first)");
        NSDictionary *appKeys = @{ff: @"left", clock: @"right"};
        CHECK(DMSMKeysAdopt(appKeys, @[ff, clock]) == appKeys, "windows by app: the app keys ARE the windows (unchanged)");
        NSSet *free0 = [NSSet setWithObject:ff];
        NSSet *free1 = DMSMKeySetAdopt(free0, @[kClock, kA]);
        CHECK([free1 containsObject:kA] && ![free1 containsObject:ff] && free1.count == 1, "No Fit chosen before the launch: the new window is the free one");
        CHECK(DMSMKeySetAdopt(free0, @[kClock]) == free0, "its window not there yet: kept");

        // 5. Fit to Window with window keys
        int how = -1;
        NSDictionary *p = DMSMFitPlanDecide(nil, @[kB, kA, kClock], Defaults(3), &how);
        CHECK(how == DMSMFitDefault && p.count == 3 && [p[kB] isEqualToString:@"left"] && [p[kA] isEqualToString:@"topright"] && [p[kClock] isEqualToString:@"bottomright"], "two Freeform windows and Clock: three tiles, one each");
        NSDictionary *byAppPlan = DMSMFitPlanDecide(nil, @[ff, clock], Defaults(2), &how);   // (what by app gave: Freeform once -- both of its windows in one tile)
        CHECK(byAppPlan.count == 2, "by app the two Freeform windows were one entry (%lu)", (unsigned long)byAppPlan.count);
        p = DMSMFitPlanDecide(p, @[kB, kA, kClock], Defaults(3), &how);
        CHECK(how == DMSMFitKept, "the same three windows again: the arrangement kept");
        // Fit's question before a launch: Clock left, Weather right, "Freeform goes on the left" -> Freeform top left, Clock bottom left
        NSString *kW = @"com.apple.weather|sceneID:com.apple.weather-default";
        NSDictionary *q = @{ff: @"topleft", kClock: @"bottomleft", kW: @"right"};
        NSArray *keysNow = @[kA, kW, kClock];   // (Freeform's new window is there, newest first)
        int how2 = -1;
        DMSMFitPlanDecide(q, keysNow, Defaults(3), &how2);
        CHECK(how2 == DMSMFitDefault, "without adopting, the choice would be lost (the default arrangement)");
        NSDictionary *qa = DMSMKeysAdopt(q, keysNow);
        p = DMSMFitPlanDecide(qa, keysNow, Defaults(3), &how);
        CHECK(how == DMSMFitKept && [p[kA] isEqualToString:@"topleft"] && [p[kClock] isEqualToString:@"bottomleft"] && [p[kW] isEqualToString:@"right"], "adopted: the chosen arrangement, Freeform's new window top left");
        //    A second Freeform window while the first is tiled: a window of its own (its key), the tiled one keeps its tile.
        NSDictionary *t2 = @{kA: @"left", kClock: @"right"};
        CHECK(DMSMKeysAdopt(t2, @[kB, kA, kClock]) == t2, "a second window of a tiled app: nothing adopted (no app key)");
        p = DMSMFitPlanDecide(t2, @[kB, kA, kClock], Defaults(3), &how);
        CHECK(how == DMSMFitDefault && p.count == 3 && p[kB] && p[kA] && p[kClock] && ![p[kA] isEqualToString:p[kB]], "three windows: three tiles, two of them Freeform's");
        //    The remembered arrangement for a desktop: keyed by its windows -- two Freeform windows are not one.
        CHECK(![DMSMFitDeskKey(@[kA, kClock]) isEqualToString:DMSMFitDeskKey(@[kB, kClock])], "a desktop with Freeform A is not one with Freeform B");
        CHECK([DMSMFitDeskKey(@[kA, kB, kClock]) isEqualToString:DMSMFitDeskKey(@[kClock, kB, kA])], "order free");

        // 6. sweep: random windows (scenes of a few apps, some with several), random arrangements and pending app keys
        srandom(7);
        NSArray *apps = @[ff, clock, @"com.apple.weather", @"com.apple.Maps", @"com.apple.stocks"];
        int adopted = 0;
        for (int n = 0; n < 20000; n++) {
            NSMutableArray<NSString *> *ws = [NSMutableArray array];
            int nw = 1 + (int)(random() % 7);
            for (int i = 0; i < nw; i++) {
                NSString *a = apps[random() % apps.count];
                NSString *k = DMSMKeyMake(a, [NSString stringWithFormat:@"sceneID:%@-%ld", a, random() % 4]);
                if (![ws containsObject:k]) [ws addObject:k];
            }
            NSMutableDictionary *slots = [NSMutableDictionary dictionary];
            NSArray *names = @[@"left", @"right", @"topleft", @"topright", @"bottomleft", @"bottomright"];
            for (NSString *w in ws) if (random() % 2) slots[w] = names[random() % names.count];
            NSString *pending = apps[random() % apps.count];
            if (random() % 2) slots[pending] = names[random() % names.count];
            NSDictionary *a = DMSMKeysAdopt(slots, ws);
            // an adopted app key goes to a window of that app that had no slot; nothing else changes; never two keys for one window
            NSUInteger appKeysBefore = 0, appKeysAfter = 0;
            for (NSString *k in slots) if (DMSMKeyIsApp(k)) appKeysBefore++;
            for (NSString *k in a) if (DMSMKeyIsApp(k)) appKeysAfter++;
            CHECK(a.count == slots.count, "sweep %d: as many entries (%lu / %lu)", n, (unsigned long)a.count, (unsigned long)slots.count);
            for (NSString *k in slots) if (!DMSMKeyIsApp(k)) CHECK([a[k] isEqual:slots[k]], "sweep %d: a window's own slot never moves", n);
            if (appKeysAfter < appKeysBefore) {
                adopted++;
                NSString *taker = nil;
                for (NSString *k in a) if (!slots[k]) taker = k;
                CHECK(taker && [DMSMKeyBundle(taker) isEqualToString:pending] && [a[taker] isEqual:slots[pending]], "sweep %d: the app's slot went to a window of that app", n);
                // ... its newest window without a slot of its own (ws is newest first)
                NSString *firstFree = nil; for (NSString *w in ws) if ([DMSMKeyBundle(w) isEqualToString:pending] && !slots[w]) { firstFree = w; break; }
                CHECK([taker isEqualToString:firstFree], "sweep %d: its newest window without a slot", n);
            } else if (slots[pending]) {
                BOOL anyFree = NO; for (NSString *w in ws) if ([DMSMKeyBundle(w) isEqualToString:pending] && !slots[w]) anyFree = YES;
                CHECK(!anyFree, "sweep %d: the app key stays only when no window of the app is free", n);
            }
            // a plan over these windows is per window: every window at most once, never an app key for a window that is there
            int h = -1;
            NSDictionary *plan = DMSMFitPlanDecide(a, ws, Defaults(MIN((NSUInteger)4, ws.count)), &h);
            for (NSString *k in plan) CHECK(h != DMSMFitDefault || [ws containsObject:k], "sweep %d: the default plan names windows on screen", n);
            // picking: a window key names its own window; the app key the app's newest
            NSMutableArray *withT = [NSMutableArray array];
            for (NSUInteger i = 0; i < ws.count; i++) [withT addObject:Win(ws[i], (long long)(100 - i))];
            for (NSUInteger i = 0; i < ws.count; i++) CHECK(DMSMKeyPick(withT, ws[i]) == i, "sweep %d: window %lu picks itself", n, (unsigned long)i);
            NSString *app = apps[random() % apps.count];
            NSUInteger want = NSNotFound; for (NSUInteger i = 0; i < ws.count; i++) if ([DMSMKeyBundle(ws[i]) isEqualToString:app]) { want = i; break; }
            CHECK(DMSMKeyPick(withT, app) == want, "sweep %d: the app key picks the app's newest window", n);
        }
        CHECK(adopted > 1000, "the sweep adopted enough: %d", adopted);

        // 6. (1.3.9) what a desktop holds of the windows asked for (DMSMKeysHold), and the saved marks of windows that are gone (DMSMKeysGone)
        NSSet *askA = [NSSet setWithObject:kA], *askApp = [NSSet setWithObject:ff];
        CHECK(DMSMKeysHold(askA, kA) && !DMSMKeysHold(askA, kB), "asked for window A: holds A, not the app's other window B");
        CHECK(DMSMKeysHold(askApp, kA) && DMSMKeysHold(askApp, kB) && !DMSMKeysHold(askApp, kClock), "asked for the app: holds any window of it, nothing else");
        CHECK(DMSMKeysHold(askA, ff), "a window known by app only (rows missing) holds a window of that app asked for");
        CHECK(!DMSMKeysHold(askA, nil) && !DMSMKeysHold(askA, @"") && !DMSMKeysHold(nil, kA) && !DMSMKeysHold([NSSet set], kA), "nothing asked or no window: no");
        CHECK((DMSMKeysHold([NSSet setWithObjects:kClock, kB, nil], kB)), "one of several asked");
        NSSet *saved = [NSSet setWithObjects:kA, kB, ff, clock, kClock, nil];
        NSSet *gone = DMSMKeysGone(saved, [NSSet setWithObjects:kB, kClock, nil]);
        CHECK([gone isEqualToSet:[NSSet setWithObject:kA]], "gone: only A's window key (B and Clock's window are there; the app keys stay): %s", gone.description.UTF8String);
        CHECK((DMSMKeysGone(saved, [NSSet setWithObjects:kA, kB, kClock, nil]).count == 0), "every window there: nothing gone");
        CHECK(([DMSMKeysGone(saved, [NSSet set]) isEqualToSet:[NSSet setWithObjects:kA, kB, kClock, nil]]), "no window anywhere: every window key gone, app keys kept");
        CHECK(DMSMKeysGone(nil, [NSSet set]).count == 0 && DMSMKeysGone([NSSet setWithObject:@""], [NSSet set]).count == 0, "an empty set or an empty entry: nothing");
        printf("test-smwindowkey: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
