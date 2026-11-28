// test-recentstrip.m: the Recent Windows Strip's rules (common/RecentStripRule.h: 1.8.8.2 F29, reworked in 1.8.8.4), run on the Mac.
// RSTRIP_RULE: the header to test (a made-to-fail copy from test-recentstrip.sh). Exit status: the number of failed checks (0: all pass).
#import <Foundation/Foundation.h>
#ifndef RSTRIP_RULE
#define RSTRIP_RULE "../common/RecentStripRule.h"
#endif
#include RSTRIP_RULE

static int gFails = 0, gChecks = 0, gQuiet = 0;
static void check(BOOL ok, NSString *what) {
    gChecks++;
    if (!ok) gFails++;
    if (!gQuiet || !ok) printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
}
static NSString *J(NSArray *a) { return [a componentsJoinedByString:@" "]; }
static NSArray *W(NSString *s) { return s.length ? [s componentsSeparatedByString:@" "] : @[]; }
// an oracle of the show rule, written apart from the header's
static int oracle(MSBDRStripState s) {
    if (!(s.on && s.calm && s.windowsFront)) return 0;
    if (s.dropTarget) return 2;
    if (s.items <= 0) return 0;
    if (s.revealed) return 2;
    if (s.covered) return 0;
    return s.windowShown || s.homeBand ? 1 : 0;
}
// 1.8.8.2's show rule as it shipped (the new one must give its answers wherever the new inputs are off)
static int shipped(MSBDRStripState s) {
    if (!s.on || s.items <= 0 || !s.calm || !s.windowsFront) return 0;
    if (s.revealed) return 2;
    if (!s.windowShown || s.covered) return 0;
    return 1;
}
static BOOL near(double a, double b) { return fabs(a - b) < 0.51; }
static NSString *L(NSString *off, NSDictionary *at) { return J(MSBDRStripList(W(off), at)); }
static BOOL nearR(MSBDRRect a, MSBDRRect b) { return fabs(a.x - b.x) < 0.51 && fabs(a.y - b.y) < 0.51 && fabs(a.w - b.w) < 0.51 && fabs(a.h - b.h) < 0.51; }

int main(int argc, char **argv) {
    @autoreleasepool {
        gQuiet = argc > 1 && !strcmp(argv[1], "-q");
        // ---- the list: the windows off the desktop, by their entry times (KT's choice) ----
        {
            NSDictionary *at = @{ @"A": @(100), @"B": @(300), @"C": @(200) };
            check([L(@"A B C", at) isEqualToString:@"B C A"], @"the list: most recent first by entry time (B 300, C 200, A 100), whatever the stage order");
            check([L(@"A B C D", at) isEqualToString:@"B C A D"], @"... a window with no time after every one with a time");
            check([L(@"D A E", @{ @"A": @(5) }) isEqualToString:@"A D E"], @"... several with none keep the stage order among them");
            check([L(@"A B", @{ @"A": @(7), @"B": @(7) }) isEqualToString:@"A B"], @"... equal times keep the stage order");
            check([L(@"A A B", at) isEqualToString:@"B A"] && [L(@"", at) isEqualToString:@""], @"... each window once; none: an empty list");
            double s0 = MSBDRStripEntryAt(MSBDRStripWhySeeded, 1000, NAN, 0), s1 = MSBDRStripEntryAt(MSBDRStripWhySeeded, 1000, NAN, 1);
            check(MSBDRStripEntryAt(MSBDRStripWhyMinimized, 1000, 50, 3) == 1000 && MSBDRStripEntryAt(MSBDRStripWhyDragged, 1000, 50, 0) == 1000,
                  @"a minimize or a drag in: its time is now (the top)");
            check(MSBDRStripEntryAt(MSBDRStripWhySwapped, 1000, 50, 0) == 50 && MSBDRStripEntryAt(MSBDRStripWhySwapped, 1000, NAN, 0) == 1000,
                  @"a swap: the window that leaves takes the picked card's time (its slot); no card time known: now");
            check(s0 < 0 && s1 < s0 && s0 < MSBDRStripEntryAt(MSBDRStripWhyMinimized, 1, NAN, 0),
                  @"a window found minimized (before the switch, a respring with no time): older than any real time, the front one first");
            NSDictionary *at2 = @{ @"A": @(s1), @"B": @(s0), @"C": @(10) };
            check([L(@"A B C", at2) isEqualToString:@"C B A"], @"... so a found window waits below the ones that came in, the stage's front one first among them");
        }
        {
            NSArray *list = W(@"B C A");
            NSDictionary *at = @{ @"A": @(100), @"B": @(300), @"C": @(200) };
            check(MSBDRStripSlotOf(list, at, @"N", 400) == 0 && MSBDRStripSlotOf(list, at, @"N", 250) == 1 && MSBDRStripSlotOf(list, at, @"N", 50) == 3,
                  @"the slot a window takes: the top for now, between by its time, the end for the oldest");
            check(MSBDRStripSlotOf(list, at, @"C", 200) == 1, @"... a window already in: its own place");
            // a swap of C (slot 1) with the front window F: C leaves, F takes C's time, so F lands in slot 1
            NSMutableDictionary *after = [at mutableCopy]; [after removeObjectForKey:@"C"];
            double tf = MSBDRStripEntryAt(MSBDRStripWhySwapped, 999, [at[@"C"] doubleValue], 0); after[@"F"] = @(tf);
            NSArray *without = W(@"B A");
            check(MSBDRStripSlotOf(without, after, @"F", tf) == 1 && [L(@"B F A", after) isEqualToString:@"B F A"], @"a swap of the card in slot 1: the window in front lands in slot 1, the others keep theirs");
            // Minimize All: every window's time first (the one in front newest), then each flight's slot from the final list
            NSMutableDictionary *burst = [at mutableCopy];
            NSArray *goes = @[@"X", @"Y", @"Z"];   // (back to front: Z in front)
            for (NSUInteger i = 0; i < goes.count; i++) burst[goes[i]] = @(1000 + i * 0.001);
            NSArray *fin = MSBDRStripList(W(@"B C A X Y Z"), burst);
            check([J(fin) isEqualToString:@"Z Y X B C A"] && MSBDRStripSlotOf(fin, burst, @"Z", [burst[@"Z"] doubleValue]) == 0 && MSBDRStripSlotOf(fin, burst, @"X", [burst[@"X"] doubleValue]) == 2,
                  @"Minimize All: the one in front on top, each window's flight to its final slot (Z 0, Y 1, X 2), the waiting ones below");
        }
        {   // a sweep: every list is sorted by time and each slot is where the window ends up in it
            BOOL ok = YES; unsigned seed = 11;
            for (int round = 0; round < 3000; round++) {
                NSMutableArray *off = [NSMutableArray array]; NSMutableDictionary *at = [NSMutableDictionary dictionary];
                int n = (int)((seed >> 4) % 9);
                for (int i = 0; i < n; i++) {
                    seed = seed * 1103515245u + 12345u;
                    NSString *k = [NSString stringWithFormat:@"w%d", i]; [off addObject:k];
                    if ((seed >> 9) & 3) at[k] = @((double)((seed >> 12) % 50));
                }
                seed = seed * 1103515245u + 12345u;
                NSArray *list = MSBDRStripList(off, at);
                if (list.count != off.count) ok = NO;
                for (NSUInteger i = 1; i < list.count; i++) {
                    NSNumber *a = at[list[i - 1]], *b = at[list[i]];
                    if (!a && b) ok = NO;
                    if (a && b && a.doubleValue < b.doubleValue) ok = NO;
                    if ((!a && !b) || (a && b && a.doubleValue == b.doubleValue)) if ([off indexOfObject:list[i - 1]] > [off indexOfObject:list[i]]) ok = NO;
                }
                double t = (double)((seed >> 8) % 60);
                NSUInteger slot = MSBDRStripSlotOf(list, at, @"new", t);
                NSMutableDictionary *with = [at mutableCopy]; with[@"new"] = @(t);
                NSMutableArray *off2 = [NSMutableArray arrayWithObject:@"new"]; [off2 addObjectsFromArray:off];
                if ([MSBDRStripList(off2, with) indexOfObject:@"new"] != slot) ok = NO;
            }
            check(ok, @"a sweep of 3000 lists: most recent first, no time last, ties in the stage order, and a window going in lands exactly in the slot it was given");
        }
        check([J(MSBDRStripShown(W(@"A B C D E F G H"), 3)) isEqualToString:@"A B C"] && [J(MSBDRStripShown(W(@"A B C D E F G H"), 20)) isEqualToString:@"A B C D E F"]
              && MSBDRStripShown(W(@"A B"), 0).count == 0, @"the cards: the first of the list, as many as fit, at most 6 (the rest wait and move up)");
        {
            BOOL f1 = YES, f2 = NO;
            check(MSBDRStripFlightSlot(2, 6, &f1) == 2 && !f1 && MSBDRStripFlightSlot(7, 6, &f2) == 5 && f2 && MSBDRStripFlightSlot(0, 0, NULL) == 0,
                  @"a flight lands in its slot; past the cap in the last one, faded");
            check(MSBDRStripBurstDelay(0) == 0 && near(MSBDRStripBurstDelay(3) * 1000, 90), @"Minimize All and Home: 30 ms between the windows' flights");
        }
        check(MSBDRStripPickSwaps(YES, NO, YES, YES, NO), @"a tap or click on a card with a window in front: a swap (as Stage Manager)");
        check(!MSBDRStripPickSwaps(NO, NO, YES, YES, NO), @"... the Dock icon, Command-Tab, the App Switcher, Spotlight, a notification: only back");
        check(!MSBDRStripPickSwaps(YES, YES, YES, YES, NO), @"... Shift held: only back (the Mac's Shift-click)");
        check(!MSBDRStripPickSwaps(YES, NO, NO, YES, NO), @"... no window in front (the Home Screen): only back");
        check(!MSBDRStripPickSwaps(YES, NO, YES, NO, NO) && !MSBDRStripPickSwaps(YES, NO, YES, YES, YES), @"... a front window that cannot wait in the strip, or the picked one itself: only back");
        check(MSBDRStripPickTakes(10.0, 9.5, 9.0) && !MSBDRStripPickTakes(10.0, 10.2, 9.0) && !MSBDRStripPickTakes(10.0, 9.0, 9.7) && MSBDRStripPickTakes(10.0, 9.0, 9.54),
              @"a pick is taken once its card settled and 0.45 s after the last pick (a double tap never swaps back)");
        check(MSBDRStripBackAtOff(MSBDRStripWhySwapped) && MSBDRStripBackAtOff(MSBDRStripWhyDragged) && !MSBDRStripBackAtOff(MSBDRStripWhyMinimized) && !MSBDRStripBackAtOff(MSBDRStripWhySeeded),
              @"the switch off: swapped and dragged windows come back to the desktop, minimized ones stay minimized");
        check(MSBDRStripKeepsGone(NO, NO) && !MSBDRStripKeepsGone(YES, NO) && !MSBDRStripKeepsGone(NO, YES), @"a waiting window whose app iPadOS ended keeps its card; closed, quit or crashed: it goes");
        check(MSBDRStripIsOff(YES, NO, NO, NO) && !MSBDRStripIsOff(NO, NO, NO, NO), @"in the strip: a window our minimize hid (Aerial's lock chip and Zetsu's own pill stay on the desktop: not hid by us)");
        check(!MSBDRStripIsOff(YES, YES, NO, NO) && !MSBDRStripIsOff(YES, NO, YES, NO) && !MSBDRStripIsOff(YES, NO, NO, YES), @"... not one closing, going full screen, or of another Mac Switcher desktop");
        {
            double a0 = MSBDRStripBurstAt(1000, 0), a1 = MSBDRStripBurstAt(1000, 1), a2 = MSBDRStripBurstAt(1000, 2);
            check(a0 == 1000 && a1 > a0 && a2 > a1 && a2 - a0 < 0.01 && MSBDRStripBurstAt(1000, -3) == 1000, @"a burst's times: in the loop's order (back to front), each a little later, so the one in front is the newest");
            NSDictionary *at = @{ @"A": @(5), @"X": @(a0), @"Y": @(a1), @"Z": @(a2) };
            NSArray *fin = MSBDRStripList(W(@"Z Y X A"), at);
            check([J(fin) isEqualToString:@"Z Y X A"] && MSBDRStripSlotOf(fin, at, @"X", a0) == 2, @"... each window's flight to its slot of the final list (Z on top, X third, the one waiting below)");
        }
        {
            double t = 0; int why = 0;
            BOOL ok = MSBDRStripSavedEntry(@(123.5), @(MSBDRStripWhySwapped), &t, &why) && t == 123.5 && why == MSBDRStripWhySwapped;
            BOOL bad = !MSBDRStripSavedEntry(@(NAN), @(1), &t, &why) && !MSBDRStripSavedEntry(@(5), @(0), &t, &why) && !MSBDRStripSavedEntry(@(5), @(9), &t, &why)
                    && !MSBDRStripSavedEntry(@"5", @(1), &t, &why) && !MSBDRStripSavedEntry(nil, @(1), &t, &why) && !MSBDRStripSavedEntry(@(5), nil, &t, &why) && !MSBDRStripSavedEntry(@(INFINITY), @(1), NULL, NULL);
            check(ok, @"an entry back from the windows' state file after a respring: its time and why as saved");
            check(bad, @"... none for a time that is not a finite number, an unknown reason, or anything not a number (the window is seeded when found)");
        }
        check(MSBDRStripFliesIn(YES, YES, YES) && !MSBDRStripFliesIn(NO, YES, YES) && !MSBDRStripFliesIn(YES, NO, YES) && !MSBDRStripFliesIn(YES, YES, NO),
              @"a minimize flies into the strip with the switch on, nothing over the windows and the windows in front; else into its Dock icon");
        check(MSBDRStripGrowsOut(YES, YES, NO) && !MSBDRStripGrowsOut(NO, YES, NO) && !MSBDRStripGrowsOut(YES, NO, NO) && !MSBDRStripGrowsOut(YES, YES, YES),
              @"a way back (the Dock icon, Command-Tab, a pick) grows out of the window's card when the card is on screen and landed; else out of the Dock icon");
        check(MSBDRStripGoneStep(0.5, NO, NO, NO, NO) == MSBDRStripGoneWait && MSBDRStripGoneStep(1.1, NO, NO, NO, NO) == MSBDRStripGoneKeep,
              @"a waiting window whose window went: decided a second later (the app's end is noted then), kept when iPadOS ended its app");
        check(MSBDRStripGoneStep(0.5, NO, YES, NO, NO) == MSBDRStripGoneWait && MSBDRStripGoneStep(0.5, NO, NO, YES, NO) == MSBDRStripGoneWait,
              @"... an earlier end's quit or crash noted for its app waits for this end's note (it replaces them)");
        check(MSBDRStripGoneStep(1.1, NO, YES, NO, NO) == MSBDRStripGoneDrop && MSBDRStripGoneStep(1.1, NO, NO, YES, NO) == MSBDRStripGoneDrop && MSBDRStripGoneStep(0.1, NO, NO, NO, YES) == MSBDRStripGoneDrop
              && MSBDRStripGoneStep(0.1, YES, NO, NO, NO) == MSBDRStripGoneDrop,
              @"... let go for the user's quit or a crash, at once for a quit asked just now (the App Switcher's swipe, Force Quit) or when its app has a window again");

        // ---- when it shows ----
        {
            BOOL ok = YES, same = YES; int n = 0;
            for (int m = 0; m < 512; m++) {
                MSBDRStripState s = { m & 1, (m >> 1) & 1 ? 3 : 0, (m >> 2) & 1, (m >> 3) & 1, (m >> 4) & 1, (m >> 5) & 1, (m >> 6) & 1, (m >> 7) & 1, (m >> 8) & 1 };
                if ((int)MSBDRStripShowFor(s) != oracle(s)) ok = NO;
                BOOL may = MSBDRStripMayReveal(s), want = s.on && s.items > 0 && s.calm && s.windowsFront && !s.dropTarget && (s.covered || (!s.windowShown && !s.homeBand));
                if (may != want) ok = NO;
                if (!s.homeBand && !s.dropTarget && (int)MSBDRStripShowFor(s) != shipped(s)) same = NO;
                n++;
            }
            check(ok, [NSString stringWithFormat:@"the show rule over all %d states, against an oracle: on its own with nothing over the cards (on the desktop, or the Home Screen with its band); out over the windows when brought or as a drop target; never without the switch, calm or the windows in front", n]);
            check(same, @"... with no Home Screen band and no drop target, 1.8.8.2's own answers in every state");
        }
        MSBDRStripState base = { 1, 2, 1, 1, 1, 0, 0, 0, 0 };
        check(MSBDRStripShowFor(base) == MSBDRStripOnDesktop, @"a window on screen, the desktop free beside it: the strip shows on the desktop");
        { MSBDRStripState s = base; s.covered = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && MSBDRStripMayReveal(s), @"a window over the cards: it steps aside, and the pointer, the menu or the handle may bring it"); }
        { MSBDRStripState s = base; s.covered = 1; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripOverWindows, @"... brought: out over the windows"); }
        { MSBDRStripState s = base; s.windowShown = 0; s.homeBand = 1; check(MSBDRStripShowFor(s) == MSBDRStripOnDesktop && !MSBDRStripMayReveal(s), @"every window minimized, the Home Screen keeps its band: the strip shows there, its home"); }
        { MSBDRStripState s = base; s.windowShown = 0; check(MSBDRStripShowFor(s) == MSBDRStripHidden, @"... with no band on the Home Screen: it stays aside (its icons stay free)"); }
        { MSBDRStripState s = base; s.items = 0; s.dropTarget = 1; check(MSBDRStripShowFor(s) == MSBDRStripOverWindows, @"a window dragged to the edge: out as a drop target, an empty strip too"); }
        { MSBDRStripState s = base; s.covered = 1; s.dropTarget = 1; check(MSBDRStripShowFor(s) == MSBDRStripOverWindows && !MSBDRStripMayReveal(s), @"... over a window that covers it"); }
        { MSBDRStripState s = base; s.windowsFront = 0; s.revealed = 1; s.dropTarget = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"the windows behind a full-screen app: no strip, not even brought or as a target"); }
        { MSBDRStripState s = base; s.calm = 0; s.revealed = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"the App Switcher, a lock, Spotlight, a keyboard...: no strip"); }
        { MSBDRStripState s = base; s.items = 0; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"nothing in it: no strip"); }
        { MSBDRStripState s = base; s.on = 0; s.revealed = 1; s.dropTarget = 1; check(MSBDRStripShowFor(s) == MSBDRStripHidden && !MSBDRStripMayReveal(s), @"switched off: never"); }
        check(!MSBDRStripMayReveal(base), @"already on the desktop: nothing to bring");
        check(MSBDRStripRevealEnds(MSBDRStripRevealPointer, 100, 0.41, NO) && !MSBDRStripRevealEnds(MSBDRStripRevealPointer, 100, 0.3, NO), @"a pointer reveal ends 0.4 s after the pointer left the band");
        check(MSBDRStripRevealEnds(MSBDRStripRevealMenu, 6.1, 0, NO) && !MSBDRStripRevealEnds(MSBDRStripRevealMenu, 5.0, 0, NO) && MSBDRStripRevealEnds(MSBDRStripRevealHandle, 6.1, 0, NO),
              @"the Window menu's and the handle's after 6 s untouched");
        check(!MSBDRStripRevealEnds(MSBDRStripRevealMenu, 600, 0, YES) && !MSBDRStripRevealEnds(MSBDRStripRevealHandle, 600, 0, YES) && !MSBDRStripRevealEnds(MSBDRStripRevealNone, 600, 9, NO),
              @"... never by time while VoiceOver or Switch Control run");
        // (review of 1.8.8.4: a reveal needs the step only while it can end by time)
        check(MSBDRStripRevealTimed(MSBDRStripRevealPointer, YES, NO) && !MSBDRStripRevealTimed(MSBDRStripRevealPointer, NO, NO) && !MSBDRStripRevealTimed(MSBDRStripRevealPointer, NO, YES),
              @"a pointer reveal needs the step once the pointer has left the band, not while it is held in it (nothing at rest)");
        check(MSBDRStripRevealTimed(MSBDRStripRevealMenu, NO, NO) && MSBDRStripRevealTimed(MSBDRStripRevealHandle, NO, NO) && !MSBDRStripRevealTimed(MSBDRStripRevealMenu, NO, YES) && !MSBDRStripRevealTimed(MSBDRStripRevealHandle, YES, YES),
              @"... the Window menu's and the handle's while they can end by time (not under VoiceOver or Switch Control)");
        check(MSBDRStripRevealTimed(MSBDRStripRevealFlight, NO, NO) && MSBDRStripRevealTimed(MSBDRStripRevealFlight, NO, YES) && !MSBDRStripRevealTimed(MSBDRStripRevealNone, YES, NO),
              @"... a flight's peek always; none: never");
        check(MSBDRStripRevealEnds(MSBDRStripRevealFlight, 1.3, 0, NO) && !MSBDRStripRevealEnds(MSBDRStripRevealFlight, 1.0, 0, NO) && MSBDRStripRevealEnds(MSBDRStripRevealFlight, 1.3, 0, YES),
              @"a window flown into a strip that had stepped aside: it stays out 1.2 s after the landing or the last touch, then steps aside again");

        // ---- the place ----
        struct { const char *name; double w, h; } pads[] = { { "iPad Air 2 / 9.7\"", 768, 1024 }, { "iPad mini 6", 744, 1133 }, { "10.2\"", 810, 1080 }, { "10.9\" / Air 4", 820, 1180 },
                                                              { "11\"", 834, 1194 }, { "12.9\"", 1024, 1366 }, { "a small screen", 600, 800 } };
        double wantW[] = { 73, 72, 77, 78, 79, 97, 72 };
        BOOL widthsOK = YES, bandsOK = YES;
        for (int i = 0; i < 7; i++) {
            if (!near(MSBDRStripCardW(pads[i].w, pads[i].h), wantW[i]) || !near(MSBDRStripCardW(pads[i].h, pads[i].w), wantW[i])) widthsOK = NO;
            double bw = MSBDRStripBandW(pads[i].w, pads[i].h);
            if (bw < 96 - 0.01 || bw > 128 + 0.01 || !near(bw, wantW[i] + 24)) bandsOK = NO;
        }
        check(widthsOK, @"a card's width: 9.5 % of the screen's short side, 72 to 104 pt (Air 2 73, mini 72, 10.2\" 77, 10.9\" 78, 11\" 79, 12.9\" 97), the same in both turns (smaller than 1.8.8.2's)");
        check(bandsOK && near(MSBDRStripBandW(768, 1024), 97) && near(MSBDRStripBandW(1194, 834), 103), @"the band: the card and 12 pt each side, 96 to 128 pt (Air 2 97, 11\" 103)");
        check(near(MSBDRStripCardH(768, 1024), 57) && near(MSBDRStripCardH(1366, 1024), 76), @"its height 78 % of that (Air 2 57 pt, 12.9\" 76 pt)");
        BOOL placesOK = YES, centredOK = YES, fitOK = YES; int layouts = 0;
        for (int i = 0; i < 7; i++) for (int turn = 0; turn < 2; turn++) for (int dock = 0; dock < 3; dock++) for (int n = 0; n <= 8; n++) {
            double sw = turn ? pads[i].h : pads[i].w, sh = turn ? pads[i].w : pads[i].h;
            MSBDRRect usable = dock == 1 ? (MSBDRRect){ 90, 24, sw - 90, sh - 24 } : dock == 2 ? (MSBDRRect){ 0, 24, sw - 90, sh - 24 } : (MSBDRRect){ 0, 24, sw, sh - 24 - 86 };
            BOOL right = MSBDRStripOnRight(dock == 1);
            double aspect[8]; for (int k = 0; k < 8; k++) aspect[k] = k % 3 == 0 ? 1.6 : (k % 3 == 1 ? 0.7 : 0.0);
            MSBDRRect band, cards[8];
            int fit = MSBDRStripFit(sw, sh, usable), got = MSBDRStripLayout(sw, sh, usable, right, n, aspect, &band, cards);
            layouts++;
            if (got != MIN(n, fit) || fit > kMSBDRStripMax || fit < 4) fitOK = NO;
            if (band.x < usable.x - 0.01 || MSBDRMaxX(band) > MSBDRMaxX(usable) + 0.01 || (right ? !near(MSBDRMaxX(band), MSBDRMaxX(usable)) : !near(band.x, usable.x))) placesOK = NO;
            if (!nearR(band, MSBDRStripBand(sw, sh, usable, right))) placesOK = NO;
            double top = 1e9, bottom = -1e9;
            for (int k = 0; k < got; k++) {
                MSBDRRect c = cards[k];
                if (c.x < band.x + kMSBDRStripEdgeGap - 0.01 || MSBDRMaxX(c) > MSBDRMaxX(band) - kMSBDRStripEdgeGap + 0.01) placesOK = NO;
                if (c.y < usable.y + kMSBDRStripEnds - 0.6 || MSBDRMaxY(c) > MSBDRMaxY(usable) - kMSBDRStripEnds + 0.6) placesOK = NO;
                if (c.w > MSBDRStripCardW(sw, sh) + 0.01 || c.h > MSBDRStripCardH(sw, sh) + 0.01 || c.w < 10 || c.h < 10) placesOK = NO;
                if (k && c.y < MSBDRMaxY(cards[k - 1]) + kMSBDRStripCardGap - 0.6) placesOK = NO;
                double box = MSBDRStripCardH(sw, sh);
                top = MIN(top, c.y - floor((box - c.h) / 2.0)); bottom = MAX(bottom, c.y - floor((box - c.h) / 2.0) + box);
            }
            if (got && fabs((top + bottom) / 2.0 - (usable.y + usable.h / 2.0)) > 1.01) centredOK = NO;
        }
        check(fitOK, [NSString stringWithFormat:@"how many fit: as many as the desktop's height takes, at least 4 and at most 6, on every iPad size, both turns, every Dock side (%d layouts)", layouts]);
        check(placesOK, @"every card inside the band, 12 pt from its edges, inside the desktop's height with 24 pt to spare, 16 pt apart, no bigger than its box; the band at its side's edge of the desktop");
        check(centredOK, @"the cards' run centred in the desktop's height");
        {
            MSBDRRect band, cards[2]; double aspect[2] = { 2.0, 0.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 2, aspect, &band, cards);
            check(near(cards[0].w, 73) && near(cards[0].h, 37) && near(cards[1].h, 57) && near(cards[1].w, 29) && near(band.w, 97) && near(band.x, 0),
                  @"a card keeps its window's shape in its box (a wide window 73 x 37, a tall one 29 x 57 on an Air 2), the band 97 pt at the left");
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 1, (double[]){ 0.0 }, &band, cards);
            check(near(cards[0].w, 73) && near(cards[0].h, 55), @"a window's shape not known: a 4:3 card");
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 1, (double[]){ 50.0 }, &band, cards);
            check(near(cards[0].w, 73) && near(cards[0].h, 24), @"an extreme shape is held to 3:1 (and 1:3)");
        }
        check(MSBDRStripOnRight(YES) && !MSBDRStripOnRight(NO), @"the left edge, the right one with the Dock at Left (as macOS)");
        {
            MSBDRRect band, cards[3]; double aspect[3] = { 1.5, 1.5, 1.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 90, 24, 934, 744 }, YES, 3, aspect, &band, cards);
            check(near(band.x, 927) && near(MSBDRMaxX(band), 1024) && near(cards[0].x, 939), @"... at the right edge: the band 927 to 1024, the cards 12 pt in");
        }
        {   // a slot opened for a window coming in (a flight's or a drop's target)
            MSBDRRect usable = { 0, 24, 1024, 658 }, band, plain[4], with[3], gapR = { 0, 0, 0, 0 }, gap0[3], g0 = { 0, 0, 0, 0 };
            double aspect[4] = { 1.5, 1.5, 1.5, 1.5 };
            MSBDRStripLayout(1024, 768, usable, NO, 4, aspect, &band, plain);
            int got = MSBDRStripLayoutGap(1024, 768, usable, NO, 3, aspect, 1, &band, with, &gapR);
            BOOL ok = got == 3 && nearR(with[0], plain[0]) && nearR(with[1], plain[2]) && nearR(with[2], plain[3]) && near(gapR.y, plain[1].y - floor((MSBDRStripCardH(1024, 768) - plain[1].h) / 2.0));
            check(ok, @"a slot open at 1 among 3 cards: the cards where 4 would lie, skipping the slot's box (the flight lands exactly there)");
            MSBDRStripLayoutGap(1024, 768, usable, NO, 3, aspect, 0, &band, gap0, &g0);
            check(near(gap0[0].y, plain[1].y) && g0.y < gap0[0].y && near(g0.w, MSBDRStripCardW(1024, 768)), @"... at the top: every card one slot down");
            MSBDRRect none[1], gn = { 0, 0, 0, 0 };
            check(MSBDRStripLayoutGap(1024, 768, usable, NO, 0, aspect, 0, &band, none, &gn) == 0 && gn.h > 0 && fabs((gn.y + gn.h / 2.0) - (usable.y + usable.h / 2.0)) < 1.01,
                  @"... an empty strip as a drop target: one slot, in the middle of the desktop's height");
            int fit = MSBDRStripFit(1024, 768, usable);
            MSBDRRect full[8], gf = { 0, 0, 0, 0 }; double asp[8] = { 0 };
            check(MSBDRStripLayoutGap(1024, 768, usable, NO, fit, asp, 0, &band, full, &gf) == fit - 1 && gf.h > 0, @"... with the strip full: the slot at the top, the last card out of sight (it waits in the list)");
            check(MSBDRStripLayoutGap(1024, 768, usable, NO, 2, asp, 9, &band, full, &gf) == 2 && gf.y > full[1].y, @"... a slot asked past the end: after the last card");
        }

        // ---- a window over the cards, and the room on the Home Screen ----
        {
            MSBDRRect band, cards[3]; double aspect[3] = { 1.5, 1.5, 1.5 };
            MSBDRStripLayout(1024, 768, (MSBDRRect){ 0, 24, 1024, 658 }, NO, 3, aspect, &band, cards);
            MSBDRRect span = MSBDRStripCardsSpan(band, cards, 3);
            check(near(span.y, cards[0].y - 8) && near(MSBDRMaxY(span), MSBDRMaxY(cards[2]) + 10) && near(span.w, band.w), @"the cards' part: the band across the cards, with the corner icons below the last");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 97, 60, 700, 500 }), @"a window beside the band: no cover");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 93, 60, 700, 500 }), @"... overlapping it by 4 pt: no cover (the slack)");
            check(MSBDRStripCovers(span, (MSBDRRect){ 92, 60, 700, 500 }), @"... by 5 pt: it covers");
            check(!MSBDRStripCovers(span, (MSBDRRect){ 0, 24, 600, span.y - 24 }), @"a window over the band above the cards: no cover");
            check(MSBDRStripCovers(span, (MSBDRRect){ 0, 24, 1024, 658 }), @"a window that fills the desktop: it covers");
            check(!MSBDRStripCovers((MSBDRRect){ 0, 0, 97, 0 }, (MSBDRRect){ 0, 24, 1024, 658 }), @"no cards: nothing to cover");
        }
        check(near(MSBDRStripHomeRoom(YES, 1024, 768), 97) && MSBDRStripHomeRoom(NO, 1024, 768) == 0, @"the Home Screen's room: the band's width while the switch is on, none while off");
        check(MSBDRStripBandIdle(NO, 0) && !MSBDRStripBandIdle(NO, 97) && !MSBDRStripBandIdle(YES, 0),
              @"the band's step: idle while off with no band handed on (nothing read or handed, any iPadOS), not with a band to take away, not while on");
        check(MSBDRStripBandHandsOn(97, 0, NO, NO) && MSBDRStripBandHandsOn(0, 97, NO, NO) && !MSBDRStripBandHandsOn(97, 97, NO, NO)
              && MSBDRStripBandHandsOn(97, 97, YES, NO) && !MSBDRStripBandHandsOn(0, 0, YES, NO),
              @"  ... the room handed on once per change, a new side only while there is a band (a side Dock's Home Screen not laid out again for none)");
        check(MSBDRStripTodayKeepsOff(YES, NO) && !MSBDRStripTodayKeepsOff(YES, YES) && !MSBDRStripTodayKeepsOff(NO, NO),
              @"the Today View on the Home Screen (at the left): the strip keeps off it at the left, not at the right (the Dock at Left)");
        {
            MSBDRRect area = { 6, 28, 1012, 650 }, bandL = { 0, 24, 97, 658 }, bandR = { 927, 24, 97, 658 };
            MSBDRRect l = MSBDRStripAreaBeside(area, bandL, NO), r = MSBDRStripAreaBeside(area, bandR, YES);
            check(near(l.x, 97) && near(MSBDRMaxX(l), MSBDRMaxX(area)) && near(l.y, area.y) && near(l.h, area.h), @"the desktop files' and notes' area beside the band at the left (from x 97)");
            check(near(r.x, area.x) && near(MSBDRMaxX(r), 927), @"... at the right (to x 927)");
            check(nearR(MSBDRStripAreaBeside(area, (MSBDRRect){ 0, 0, 0, 0 }, NO), area) && nearR(MSBDRStripAreaBeside((MSBDRRect){ 0, 0, 150, 300 }, bandL, NO), (MSBDRRect){ 0, 0, 150, 300 }),
                  @"... no band: as it was; no sensible room beside it: as it was");
        }

        // ---- a window dragged over it; a card dragged out ----
        {
            MSBDRRect bandL = { 0, 24, 97, 658 }, bandR = { 927, 24, 97, 658 };
            check(MSBDRStripInDropZone(50, 300, bandL, NO) && MSBDRStripInDropZone(121, 300, bandL, NO) && !MSBDRStripInDropZone(122, 300, bandL, NO), @"the drop zone: the band and 24 pt past it");
            check(MSBDRStripInDropZone(903, 300, bandR, YES) && !MSBDRStripInDropZone(902, 300, bandR, YES), @"... at the right");
            check(!MSBDRStripInDropZone(50, -1, bandL, NO) && !MSBDRStripInDropZone(50, 707, bandL, NO) && MSBDRStripInDropZone(50, 0, bandL, NO), @"... the desktop's height and 24 pt more, not further");
            check(!MSBDRStripInDropZone(50, 300, (MSBDRRect){ 0, 0, 0, 0 }, NO), @"... no band: no zone");
            check(near(MSBDRStripPastBand(140, bandL, NO), 43) && near(MSBDRStripPastBand(884, bandR, YES), 43) && MSBDRStripPastBand(40, bandL, NO) < 0, @"how far past the band, either side");
            check(MSBDRStripDropsBack(90, bandL, NO) && !MSBDRStripDropsBack(98, bandL, NO) && MSBDRStripDropsBack(930, bandR, YES), @"let go inside the band: back to its slot (no reorder by drag)");
        }
        check(MSBDRStripDropTakes(YES, YES, YES) && !MSBDRStripDropTakes(NO, YES, YES) && !MSBDRStripDropTakes(YES, NO, YES) && !MSBDRStripDropTakes(YES, YES, NO),
              @"a window let go over the drop zone goes in when the strip can show and the window can wait there; any other drop is the drop it always was");
        check(MSBDRStripPressFor(0.1, 2, YES, NO) == MSBDRStripPressTap && MSBDRStripPressFor(0.6, 2, YES, NO) == MSBDRStripPressMenu && MSBDRStripPressFor(0.3, 2, NO, NO) == MSBDRStripPressUndecided,
              @"a finger: let go at once a tap, held 0.45 s and let go the menu, still down: not decided");
        check(MSBDRStripPressFor(0.1, 10, NO, NO) == MSBDRStripPressDrag && MSBDRStripPressFor(0.9, 12, NO, NO) == MSBDRStripPressDrag && MSBDRStripPressFor(0.1, 9, NO, NO) == MSBDRStripPressUndecided,
              @"... moved 10 pt a drag, after a hold too (hold then drag, as iPadOS's strip)");
        check(MSBDRStripPressFor(0.1, 4, NO, YES) == MSBDRStripPressDrag && MSBDRStripPressFor(0.9, 1, YES, YES) == MSBDRStripPressTap,
              @"a pointer: moved 4 pt a drag; a long click is still a click (its menu is the secondary click)");
        {
            MSBDRRect desk = { 0, 24, 1024, 658 };
            double w = 0, h = 0;
            MSBDRStripProxySize(73, 55, 600, 400, desk, 10, &w, &h);
            BOOL in = near(w, 73) && near(h, 55);
            MSBDRStripProxySize(73, 55, 600, 400, desk, 40, &w, &h); in = in && near(w, 73);
            MSBDRStripProxySize(73, 55, 150, 100, desk, 200, &w, &h);
            BOOL out = near(w, 150) && near(h, 100);
            MSBDRStripProxySize(73, 55, 600, 400, desk, 200, &w, &h);
            BOOL sharp = near(w, 73 * 2.6) && near(h, 73 * 2.6 * 400 / 600.0) && w <= 73 * 2.6 + 0.01 && h <= 55 * 2.6 + 0.01;
            MSBDRStripProxySize(73, 55, 2000, 1000, desk, 400, &w, &h);
            BOOL shape = near(w / h, 2.0) && w <= 73 * 2.6 + 0.01;
            double prev = 0; BOOL mono = YES;
            for (double p = -20; p <= 260; p += 5) { MSBDRStripProxySize(73, 55, 600, 400, desk, p, &w, &h); if (w + 0.001 < prev) mono = NO; prev = w; }
            check(in && out && mono, @"a dragged card: its own size until 40 pt past the band, then it grows smoothly to its window's size (160 pt further)");
            MSBDRStripProxySize(73, 55, 600, 400, (MSBDRRect){ 0, 0, 100, 80 }, 400, &w, &h);
            check(near(w, 100) && near(h, 400 * 100 / 600.0), @"... never larger than the desktop (a small one: the window's shape held to it)");
            check(sharp && shape, @"... at most 2.6 times the card (its picture stays sharp; the window grows out of it where it is let go), its window's shape kept, a window larger than the desktop too");
        }
        {
            MSBDRRect desk = { 0, 24, 1024, 658 };
            MSBDRRect f = MSBDRStripDropFrame(600, 400, 0.25, 0.1, 500, 300, desk);
            check(near(f.x, 350) && near(f.y, 260) && near(f.w, 600) && near(f.h, 400), @"let go: the window's frame with the grab point under the drop point (a quarter across, near its top)");
            f = MSBDRStripDropFrame(600, 400, 0.5, 0.5, 500, 30, desk);
            check(near(f.y, 24), @"... never above the desktop (the title bar under the menu bar)");
            f = MSBDRStripDropFrame(600, 400, 0.5, 0.05, 500, 760, desk);
            check(near(f.y, 642), @"... let go over the Dock: as at the desktop's nearest point above it, the title bar 40 pt above the desktop's end");
            f = MSBDRStripDropFrame(600, 400, 0.5, 0.5, 500, 760, desk);
            check(near(f.y, 482), @"... grabbed by its middle and let go over the Dock: its middle at the desktop's end (not under the Dock)");
            f = MSBDRStripDropFrame(600, 400, 0.5, 0.0, 500, 670, desk);
            check(f.y <= 682 - 40 + 0.01, @"... the title bar at least 40 pt above the desktop's end");
            f = MSBDRStripDropFrame(600, 400, 0.99, 0.5, 1020, 300, desk);
            check(MSBDRMaxX(f) >= 80 && f.x <= 1024 - 80 + 0.01, @"... at least 80 pt of it on the desktop across");
            f = MSBDRStripDropFrame(2000, 1000, 0.5, 0.5, 512, 353, desk);
            check(f.w <= 1024.01 && f.h <= 658.01 && near(f.w / f.h, 2.0), @"... a window larger than the desktop: held to it, its shape kept");
            double ox = 0, oy = 0; MSBDRStripFlickTo(300, 300, 1000, -200, &ox, &oy);
            check(near(ox, 450) && near(oy, 270), @"a card thrown: it lands where its speed takes it in 0.15 s");
        }

        // ---- the pointer and the finger ----
        check(MSBDRStripPointerAtEdge(0, 1024, NO) && MSBDRStripPointerAtEdge(2, 1024, NO) && !MSBDRStripPointerAtEdge(2.5, 1024, NO)
              && MSBDRStripPointerAtEdge(1022, 1024, YES) && !MSBDRStripPointerAtEdge(1021.5, 1024, YES) && !MSBDRStripPointerAtEdge(0, 1024, YES), @"the pointer at the strip's edge: within 2 pt of it, that side only");
        check(MSBDRStripPointerLeft(157, (MSBDRRect){ 0, 24, 116, 658 }, NO) && !MSBDRStripPointerLeft(150, (MSBDRRect){ 0, 24, 116, 658 }, NO)
              && MSBDRStripPointerLeft(867, (MSBDRRect){ 908, 24, 116, 658 }, YES) && !MSBDRStripPointerLeft(870, (MSBDRRect){ 908, 24, 116, 658 }, YES), @"the pointer has left it 40 pt past the band, either side");
        check(MSBDRStripHandleShown(YES, NO) && !MSBDRStripHandleShown(YES, YES) && !MSBDRStripHandleShown(NO, NO), @"the finger's handle: only while stepped aside with cards and no trackpad or mouse");
        {
            MSBDRRect span = { 0, 200, 97, 300 };
            MSBDRRect h = MSBDRStripHandleRect(1024, span, NO), t = MSBDRStripHandleTouch(1024, span, NO), hr = MSBDRStripHandleRect(1024, span, YES), tr = MSBDRStripHandleTouch(1024, span, YES);
            check(near(h.w, 4) && near(h.h, 44) && near(h.x, 2) && near(h.y + 22, 350) && near(hr.x, 1018), @"... 4 x 44 pt at the edge, centred on the cards");
            check(near(t.x, 0) && near(t.w, 20) && near(t.y, h.y - 22) && near(t.h, 88) && near(tr.x, 1004) && near(MSBDRMaxX(tr), 1024),
                  @"... its touch area 20 pt wide at the edge and only the handle's height and 22 pt above and below (an app's own edge swipe elsewhere stays the app's)");
            check(MSBDRStripInRect(t, 5, 350) && !MSBDRStripInRect(t, 5, 250) && !MSBDRStripInRect(t, 21, 350), @"... a touch there is the handle's, none elsewhere");
        }
        check(MSBDRStripKeyStep(-1, 4, 1) == 0 && MSBDRStripKeyStep(-1, 4, -1) == 3 && MSBDRStripKeyStep(1, 4, 1) == 2 && MSBDRStripKeyStep(3, 4, 1) == 3 && MSBDRStripKeyStep(0, 4, -1) == 0 && MSBDRStripKeyStep(0, 0, 1) == -1,
              @"the keys on a menu reveal: Down from none the top card, Up the last; held at the ends");

        // ---- nothing at rest ----
        {
            uint64_t h0 = 1469598103934665603ull;
            BOOL apart = YES, order = YES; unsigned seed = 5;
            for (int i = 0; i < 20000; i++) {
                seed = seed * 1103515245u + 12345u; uint64_t a = seed; seed = seed * 1103515245u + 12345u; uint64_t b = ((uint64_t)seed << 32) | a;
                if (MSBDRStripSigMix(h0, b) == MSBDRStripSigMix(h0, b ^ (1ull << (seed % 64)))) apart = NO;   // (one bit of a window's frame or mark)
                if (a != b && MSBDRStripSigMix(MSBDRStripSigMix(h0, a), b) == MSBDRStripSigMix(MSBDRStripSigMix(h0, b), a)) order = NO;
            }
            check(apart, @"the step's signature changes with any one bit of what it reads (20000 random words: a window moved by a point, hidden, minimized)");
            check(order, @"... and with the order of the windows (two windows trading places)");
            check(!MSBDRStripTickWorks(NO, NO) && MSBDRStripTickWorks(YES, NO) && MSBDRStripTickWorks(NO, YES), @"the step works only when something it reads changed, or something time-bound waits");
        }

        // ---- the motion ----
        check(near(kMSBDRStripShowTime * 100, 42) && near(kMSBDRStripShowDamp * 100, 86) && near(kMSBDRStripAsideTime * 100, 22) && near(kMSBDRStripHoverScale * 100, 105)
              && near(kMSBDRStripPressScale * 100, 96) && near(kMSBDRStripHoverTilt, 5) && near(kMSBDRStripHoverShadow, 12) && near(kMSBDRStripShadow, 7), @"the motion's numbers as designed (show 0.42 s spring 0.86, aside 0.22 s, hover 1.05 with a 5 degree tilt, press 0.96)");
        check(MSBDRStripStaggerAt(0) == 0 && near(MSBDRStripStaggerAt(2) * 1000, 50) && near(MSBDRStripStaggerAt(9) * 1000, 125), @"the cards slide in 25 ms apart, 125 ms at most");

        // ---- the pictures ----
        check(near(MSBDRStripPicScale(1000, 700, 88, 69) * 1000, 88) && MSBDRStripPicScale(50, 40, 88, 69) == 1.0 && MSBDRStripPicScale(0, 700, 88, 69) == 0.0,
              @"a picture at its card's size: the window fitted into the box (1000 x 700 at 0.088), never above its own size, none of an empty view");
        check(MSBDRStripPicScale(1366, 1024, 104, 81) * 1366 * 2 < 240.0, @"... a full-screen window on a 12.9\" at 2x: under 240 px wide (about 150 KB)");
        check(MSBDRStripPicAtEntry(NO, 0, NO, NO) && MSBDRStripPicAtEntry(YES, 3, NO, NO) && !MSBDRStripPicAtEntry(YES, 0.2, NO, NO),
              @"a window going in by itself is pictured right before (what you saw as you sent it), any window, not only the one in front");
        check(MSBDRStripPicAtEntry(NO, 0, YES, NO) && MSBDRStripPicAtEntry(YES, 11, YES, YES) && !MSBDRStripPicAtEntry(YES, 9, YES, YES) && !MSBDRStripPicAtEntry(YES, 600, YES, NO),
              @"... in a burst (Minimize All, Home): the one in front and any with none (one render, not one per window)");
        check(MSBDRStripPicKept(8, 6) && !MSBDRStripPicKept(9, 6) && MSBDRStripPicKept(0, 0), @"pictures kept: the cards shown and 3 more down the list");

        // ---- our own windows: one card per app ----
        check(MSBDRStripStackShown(1) == 1 && MSBDRStripStackShown(3) == 3 && MSBDRStripStackShown(7) == 3 && MSBDRStripStackShown(0) == 0 && !MSBDRStripStackBadge(3) && MSBDRStripStackBadge(4),
              @"a group's card: up to 3 pictures stacked, a count over 3");
        {
            MSBDRRect f = { 10, 100, 80, 60 }, d1 = MSBDRStripStackRect(f, 1), d2 = MSBDRStripStackRect(f, 2), d0 = MSBDRStripStackRect(f, 0);
            check(nearR(d0, f) && near(d1.w, 76.8) && near(MSBDRMaxY(d1), MSBDRMaxY(f) + 6) && near(d1.x + d1.w / 2, 50) && near(MSBDRMaxY(d2), MSBDRMaxY(f) + 12) && d2.w < d1.w,
                  @"... each picture behind 6 pt lower and 4 % smaller, centred (macOS's piles)");
        }
        {   // (review of 1.8.8.4: the trim and a memory warning keep a card of our own windows' stack, its windows' pictures by their own keys)
            NSArray *list = W(@"a native:Finder b c");
            NSDictionary *g = @{ @"native:Finder": W(@"nw:1 nw:2 nw:3 nw:4") };
            NSArray *(^S)(NSSet *) = ^NSArray *(NSSet *x) { return [[x allObjects] sortedArrayUsingSelector:@selector(compare:)]; };
            check([J(S(MSBDRStripPicsFor(list, 2, g))) isEqualToString:@"a nw:1 nw:2 nw:3"], @"pictures kept for our own windows' card: its stack's (up to 3), by their own keys, never its app's key");
            check([J(S(MSBDRStripPicsFor(list, 9, g))) isEqualToString:@"a b c nw:1 nw:2 nw:3"] && MSBDRStripPicsFor(list, 0, g).count == 0 && [J(S(MSBDRStripPicsFor(list, 1, g))) isEqualToString:@"a"],
                  @"... the list's first cards only (a card further down keeps none); an engine window's card keeps its own");
            check([J(S(MSBDRStripPicsFor(W(@"native:Finder"), 1, @{ @"native:Finder": W(@"nw:9") }))) isEqualToString:@"nw:9"] && [J(S(MSBDRStripPicsFor(list, 4, @{}))) isEqualToString:@"a b c native:Finder"],
                  @"... a one-window card its one picture; with no group known, the keys as they are");
        }

        // ---- where it runs ----
        check(MSBDRStripTickNeeded(YES, NO) && MSBDRStripTickNeeded(NO, YES) && !MSBDRStripTickNeeded(NO, NO),
              @"the watcher skips the strip's step while it is off and nothing of it is active");
        check(MSBDRecentStripOS(15) && !MSBDRecentStripOS(14) && !MSBDRecentStripOS(16) && !MSBDRecentStripOS(17) && !MSBDRecentStripOS(18), @"iPadOS 15 only in this build (the pictures without waiting are read there)");
        check(kMSBDRStripMax == 6, @"at most 6 cards");
        printf("%d of %d checks passed\n", gChecks - gFails, gChecks);
    }
    return gFails > 250 ? 250 : gFails;
}
