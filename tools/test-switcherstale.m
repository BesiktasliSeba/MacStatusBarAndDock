// Mac test of the stale-card rule of the App Switcher clean-up (statusbar/SwitcherStale.h, used by StatusBar.x DMCleanStaleSwitcherCards): the
// cards iPadOS brings back after a respring stay (the 17.5.1 case of 29 Oct: Stage Manager -> Aerial, the sweeps 20 s and 35 s after the start
// took Weather, App Store and Settings), the card of an app that went away while SpringBoard ran goes after the grace, and the old rules for the
// grace, the app in front and a card that is gone still hold.
#import <Foundation/Foundation.h>
#include "../statusbar/SwitcherStale.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static NSSet *S(NSArray *a) { return [NSSet setWithArray:a]; }
int main(void) {
    @autoreleasepool {
        NSString *clock = @"com.apple.mobiletimer", *weather = @"com.apple.weather", *store = @"com.apple.AppStore", *prefs = @"com.apple.Preferences", *tips = @"com.apple.tips";
        // KT's 17.5 after the switch to Aerial: four cards brought back, Clock's window restored (running, in front), nothing else opened yet
        NSSet *kt = S(@[clock, weather, store, prefs]);
        NSMutableDictionary *since = [NSMutableDictionary dictionary];
        NSArray *out = nil; BOOL any = NO;
        for (double t = 8; t <= 600; t += 15) { out = MSBDStaleCards(kt, S(@[clock]), S(@[clock]), clock, since, t); if (out.count) any = YES; }
        CHECK(!any, "after a respring (an engine switch): the cards brought back stay, sweep after sweep for 10 minutes");
        CHECK(since.count == 0, "  ... and none of them is even followed as stale");
        out = MSBDStaleCards(kt, S(@[clock]), S(@[clock]), nil, since, 700);
        CHECK(out.count == 0, "  ... also with no app in front (the Home Screen)");
        // dasd prewarmed Weather (running a while, never in front), then it ended: its card stays
        since = [NSMutableDictionary dictionary];
        MSBDStaleCards(kt, S(@[clock, weather]), S(@[clock]), clock, since, 10);
        out = MSBDStaleCards(kt, S(@[clock]), S(@[clock]), clock, since, 25);
        out = [out arrayByAddingObjectsFromArray:MSBDStaleCards(kt, S(@[clock]), S(@[clock]), clock, since, 40)];
        CHECK(out.count == 0, "an app only dasd started (a prewarm), gone again: its card stays");
        // an app the user had in front, gone since (it crashed, or was ended by something that left its card): goes after the grace
        since = [NSMutableDictionary dictionary];
        NSSet *cards = S(@[tips, weather]), *used = S(@[tips]);
        out = MSBDStaleCards(cards, S(@[]), used, nil, since, 100);
        CHECK(out.count == 0 && since[tips] && !since[weather], "first seen stale: followed, nothing goes yet (and the card brought back is not followed)");
        out = MSBDStaleCards(cards, S(@[]), used, nil, since, 103.9);
        CHECK(out.count == 0, "within the grace (3.9 s): not yet");
        out = MSBDStaleCards(cards, S(@[]), used, nil, since, 104.0);
        CHECK(out.count == 1 && [out[0] isEqualToString:tips], "after 4 s still gone: its card goes (and only that one)");
        CHECK(!since[tips], "  ... and is no longer followed");
        // running again within the grace: the clock starts over
        since = [NSMutableDictionary dictionary];
        MSBDStaleCards(cards, S(@[]), used, nil, since, 0);
        out = MSBDStaleCards(cards, S(@[tips]), used, nil, since, 2);
        CHECK(out.count == 0 && !since[tips], "running again (a launch the list had not caught up with): no longer followed");
        MSBDStaleCards(cards, S(@[]), used, nil, since, 5);
        out = MSBDStaleCards(cards, S(@[]), used, nil, since, 8);
        CHECK(out.count == 0, "gone again: a new grace (3 s of it so far)");
        out = MSBDStaleCards(cards, S(@[]), used, nil, since, 9);
        CHECK(out.count == 1, "  ... and the card goes 4 s after it went again");
        // the app in front is never stale, even while its process is still starting
        since = [NSMutableDictionary dictionary];
        MSBDStaleCards(cards, S(@[]), used, tips, since, 0);
        out = MSBDStaleCards(cards, S(@[]), used, tips, since, 30);
        CHECK(out.count == 0 && since.count == 0, "the app in front: never stale");
        // a card that went meanwhile (swiped away) is no longer followed
        since = [NSMutableDictionary dictionary];
        MSBDStaleCards(cards, S(@[]), used, nil, since, 0);
        out = MSBDStaleCards(S(@[weather]), S(@[]), used, nil, since, 10);
        CHECK(out.count == 0 && since.count == 0, "its card gone (swiped away): nothing followed, nothing to take");
        // several at once, sorted; a Split View card counts each app on it
        since = [NSMutableDictionary dictionary];
        NSSet *many = S(@[tips, prefs, store, weather]), *usedMany = S(@[tips, prefs, store]);
        MSBDStaleCards(many, S(@[store]), usedMany, nil, since, 0);
        out = MSBDStaleCards(many, S(@[store]), usedMany, nil, since, 4);
        CHECK(out.count == 2 && [out[0] isEqualToString:prefs] && [out[1] isEqualToString:tips], "two gone (sorted), the running one and the one never in front stay");
        // no record of apps in front (nil, the stock status bar start): nothing is ever taken
        since = [NSMutableDictionary dictionary];
        MSBDStaleCards(cards, S(@[]), nil, nil, since, 0);
        out = MSBDStaleCards(cards, S(@[]), nil, nil, since, 60);
        CHECK(out.count == 0 && since.count == 0, "no apps in front noted at all: nothing taken");
        // nothing shown, nothing running: nothing
        CHECK(MSBDStaleCards(S(@[]), S(@[]), used, nil, [NSMutableDictionary dictionary], 0).count == 0, "no cards: nothing");
        CHECK(kMSBDStaleCardGrace == 4.0, "the grace is 4 s, as before");
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
