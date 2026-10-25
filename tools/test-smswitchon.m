// Mac test of when and how the Stage Manager engine switches Stage Manager on (statusbar/SMSwitchOn.h, used by StatusBar.x DMStageManagerWatch):
// never in SpringBoard's first 12 s, never on the Lock Screen or under the Cover Sheet; Apple's first-time path (its introduction) only when no key
// says Stage Manager was ever on -- SpringBoard's own reading (TrollPad's copy of the keys while TrollPad is loaded) nor the stored keys, Apple's
// and TrollPad's. The stored values below are the ones read on the three test iPads on 24 Oct 2026.
#import <Foundation/Foundation.h>
#include "../statusbar/SMSwitchOn.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const char *StepName(DMSMOnStep s) { return s == DMSMOnNothing ? "nothing" : s == DMSMOnWait ? "wait" : s == DMSMOnFirstTime ? "first-time" : s == DMSMOnWrite ? "write" : "?"; }

// One SpringBoard start: the screen locked until unlockAt (seconds after the start), Stage Manager off; Stage Manager comes on when the engine writes
// it (write) or when the user answers Apple's introduction after answerAfter seconds (first-time; < 0: never answers). Steps every 0.4 s, as the
// watcher. Returns the step that switched it on (or the last one), and when; *sawFirstTimeLocked if the first-time path ran while locked.
static DMSMOnStep RunStart(double unlockAt, int everSB, NSString *everKey, double answerAfter, double *onAt, BOOL *firstTimeLocked, BOOL *firstTime) {
    BOOL on = NO; double askedAt = -1.0; *onAt = -1.0; *firstTimeLocked = NO; *firstTime = NO;
    DMSMOnStep last = DMSMOnWait;
    for (double t = 0.0; t < 200.0 && !on; t += 0.4) {
        BOOL unlocked = t >= unlockAt;
        if (askedAt >= 0.0 && answerAfter >= 0.0 && t - askedAt >= answerAfter) { on = YES; *onAt = t; break; }
        last = DMSMSwitchOnStep(on, t, unlocked, everSB, everKey, askedAt >= 0.0 ? t - askedAt : -1.0);
        if (last == DMSMOnFirstTime) { *firstTime = YES; if (!unlocked) *firstTimeLocked = YES; askedAt = t; everSB = 1; }
        if (last == DMSMOnWrite) { on = YES; *onAt = t; }
    }
    return last;
}

int main(void) {
    @autoreleasepool {
        // ---- the stored keys (com.apple.springboard), as read on the devices ----
        NSDictionary *a12z = @{@"SBChamoisWindowingEnabled": @YES, @"SBChamoisWindowingEverEnabled": @YES, @"SBChamoisHideDock": @NO};   // A12Z 18.5, native, TrollPad installed later
        NSDictionary *a12zAfter = @{@"SBChamoisWindowingEnabled": @YES, @"SBChamoisWindowingEverEnabled": @YES, @"TPSBChamoisWindowingEnabled": @YES, @"TPSBChamoisWindowingEverEnabled": @YES};
        NSDictionary *ipad2 = @{@"SBChamoisWindowingEverEnabled": @YES, @"TPSBChamoisWindowingEnabled": @YES, @"TPSBChamoisWindowingEverEnabled": @YES};   // iPad 2 16.7.7 + TrollPad
        NSDictionary *ipad17 = @{@"TPSBChamoisWindowingEnabled": @YES, @"TPSBChamoisWindowingEverEnabled": @YES};   // 17.5.1 A10X + TrollPad
        CHECK([DMSMEverKeyIn(a12z) isEqualToString:@"SBChamoisWindowingEverEnabled"], "A12Z: Apple's ever key (got %s)", DMSMEverKeyIn(a12z).UTF8String);
        CHECK([DMSMEverKeyIn(a12zAfter) isEqualToString:@"SBChamoisWindowingEverEnabled"], "A12Z after: Apple's ever key first");
        CHECK([DMSMEverKeyIn(ipad2) isEqualToString:@"SBChamoisWindowingEverEnabled"], "iPad 2: Apple's ever key");
        CHECK([DMSMEverKeyIn(ipad17) isEqualToString:@"TPSBChamoisWindowingEverEnabled"], "17.5: TrollPad's ever key (got %s)", DMSMEverKeyIn(ipad17).UTF8String);
        CHECK(DMSMEverKeyIn(@{}) == nil, "fresh iPad: no key");
        CHECK(DMSMEverKeyIn(@{@"SBChamoisWindowingEnabled": @NO, @"TPSBChamoisWindowingEverEnabled": @0}) == nil, "keys set to no: none");
        CHECK([DMSMEverKeyIn(@{@"TPSBChamoisWindowingEnabled": @1}) isEqualToString:@"TPSBChamoisWindowingEnabled"], "a number 1 counts");
        CHECK([DMSMEverKeyIn(@{@"SBChamoisWindowingEnabled": @"1"}) isEqualToString:@"SBChamoisWindowingEnabled"], "a string \"1\" counts");
        CHECK(DMSMEverKeyIn(@{@"SBChamoisWindowingEnabled": [NSDate date]}) == nil, "another type: not counted");
        CHECK(DMSMEverKeyIn((NSDictionary *)@[@1]) == nil && DMSMEverKeyIn(nil) == nil, "not a dictionary: none");
        CHECK(DMSMEverKeyIn(@{@"SBChamoisHideDock": @YES, @"SBChamoisHideStrips": @YES}) == nil, "other SBChamois keys do not count");

        // ---- the step table ----
        CHECK(DMSMSwitchOnStep(YES, 0.0, NO, 0, nil, -1.0) == DMSMOnNothing, "on: nothing");
        CHECK(DMSMSwitchOnStep(NO, 5.0, YES, 0, nil, -1.0) == DMSMOnWait, "starting: wait");
        CHECK(DMSMSwitchOnStep(NO, 30.0, NO, 0, nil, -1.0) == DMSMOnWait, "locked: wait, no first-time path");
        CHECK(DMSMSwitchOnStep(NO, 30.0, NO, 1, @"SBChamoisWindowingEverEnabled", -1.0) == DMSMOnWait, "locked: no write either");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, 0, nil, -1.0) == DMSMOnFirstTime, "unlocked, never on anywhere: first-time path");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, 0, @"SBChamoisWindowingEverEnabled", -1.0) == DMSMOnWrite, "A12Z: SpringBoard says never, Apple's key says it was: written directly");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, 1, nil, -1.0) == DMSMOnWrite, "ever on in SpringBoard: written");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, -1, nil, -1.0) == DMSMOnWrite, "no ever mark to ask: written (as before)");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, 1, nil, 10.0) == DMSMOnWait, "introduction 10 s ago: wait");
        CHECK(DMSMSwitchOnStep(NO, 30.0, YES, 1, nil, 45.0) == DMSMOnWrite, "introduction 45 s ago: written");
        CHECK(DMSMSwitchOnStep(NO, 80.0, NO, 1, nil, 50.0) == DMSMOnWait, "introduction long ago but locked: wait");
        // sweep: the first-time path only on an unlocked screen after 12 s, with no key and SpringBoard's own "never", never twice
        int sweep = 0, bad = 0;
        NSArray *keys = @[[NSNull null], @"SBChamoisWindowingEverEnabled", @"TPSBChamoisWindowingEnabled"];
        for (int on = 0; on <= 1; on++) for (double age = 0.0; age <= 30.0; age += 1.5) for (int u = 0; u <= 1; u++) for (int e = -1; e <= 1; e++)
            for (id k in keys) for (double asked = -1.0; asked <= 60.0; asked += 7.5) {
                NSString *key = k == [NSNull null] ? nil : k;
                DMSMOnStep s = DMSMSwitchOnStep(on, age, u, e, key, asked);
                BOOL ft = s == DMSMOnFirstTime, want = !on && age >= 12.0 && u && e == 0 && !key && asked < 0.0;
                BOOL writeLocked = s == DMSMOnWrite && !u, writeEarly = s == DMSMOnWrite && age < 12.0, actOn = on && s != DMSMOnNothing;
                if (ft != want || writeLocked || writeEarly || actOn) { bad++; if (bad < 5) printf("  sweep: on %d age %.1f unlocked %d ever %d key %s asked %.1f -> %s\n", on, age, u, e, key.UTF8String ?: "-", asked, StepName(s)); }
                sweep++;
            }
        CHECK(bad == 0, "sweep: %d of %d cases wrong", bad, sweep);

        // ---- whole starts (0.4 s ticks) ----
        double onAt; BOOL ftLocked, ft;
        // A12Z as found: respring onto the Lock Screen, unlocked at 30 s; SpringBoard reads TrollPad's empty copy (never), Apple's key says it was
        DMSMOnStep r = RunStart(30.0, 0, DMSMEverKeyIn(a12z), -1.0, &onAt, &ftLocked, &ft);
        CHECK(r == DMSMOnWrite && !ft && onAt >= 30.0 && onAt < 30.5, "A12Z start: written right after the unlock, no introduction (%s at %.1f, first-time %d)", StepName(r), onAt, ft);
        // a fresh TrollPad iPad (never on anywhere), Lock Screen until 40 s, the user answers the introduction after 5 s
        r = RunStart(40.0, 0, nil, 5.0, &onAt, &ftLocked, &ft);
        CHECK(ft && !ftLocked && onAt >= 45.0 && onAt < 45.9, "fresh iPad: introduction only after the unlock, on from its Continue (first-time %d locked %d, on at %.1f)", ft, ftLocked, onAt);
        // ... the user declines it (never answers): written 45 s after the introduction
        r = RunStart(20.0, 0, nil, -1.0, &onAt, &ftLocked, &ft);
        CHECK(ft && !ftLocked && r == DMSMOnWrite && onAt >= 65.0 && onAt < 65.9, "declined introduction: written 45 s later (%.1f)", onAt);
        // Skip Lock Screen After Respring on (unlocked from the start): as before -- the introduction at 12 s on a fresh iPad, a write elsewhere
        r = RunStart(0.0, 0, nil, 3.0, &onAt, &ftLocked, &ft);
        CHECK(ft && onAt >= 15.0 && onAt < 15.9, "unlocked start, fresh: introduction at 12 s (on at %.1f)", onAt);
        r = RunStart(0.0, 1, DMSMEverKeyIn(ipad17), -1.0, &onAt, &ftLocked, &ft);
        CHECK(!ft && r == DMSMOnWrite && onAt >= 12.0 && onAt < 12.5, "17.5 / iPad 2 (TrollPad keys set): written at 12 s, no introduction (%.1f)", onAt);
        // never unlocked: nothing happens at all
        r = RunStart(1000.0, 0, nil, 1.0, &onAt, &ftLocked, &ft);
        CHECK(!ft && onAt < 0.0 && r == DMSMOnWait, "never unlocked: Stage Manager not touched");
    }
    printf("test-smswitchon: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
