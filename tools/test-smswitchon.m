// Mac test of when and how the Stage Manager engine switches Stage Manager on (statusbar/SMSwitchOn.h, used by StatusBar.x DMStageManagerWatch):
// never in SpringBoard's first 12 s, never on the Lock Screen or under the Cover Sheet; Apple's first-time path (its introduction) only when no key
// says Stage Manager was ever on -- SpringBoard's own reading (TrollPad's copy of the keys while TrollPad is loaded) nor the stored keys, Apple's
// and TrollPad's. The stored values below are the ones read on the three test iPads on 24 Oct 2026.
// 1.5.1 (consent, Havoc rule 2.5): nothing is switched on or written without a yes -- our one-time question first; a no (Not Now, Apple's
// introduction declined, or the user switching it off) is never undone; an iPad where it is on already is not asked. And keeping Stage Manager off
// while another engine runs needs the same yes once (a pick in Settings, or the question for an engine nobody picked).
#import <Foundation/Foundation.h>
#include "../statusbar/SMSwitchOn.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const char *StepName(DMSMOnStep s) {
    switch (s) {
        case DMSMOnNothing: return "nothing"; case DMSMOnWait: return "wait"; case DMSMOnFirstTime: return "first-time"; case DMSMOnWrite: return "write";
        case DMSMOnAsk: return "ask"; case DMSMOnDeclined: return "declined"; case DMSMOnUserOff: return "user-off"; case DMSMOnLeftOff: return "left-off";
        case DMSMOnGiveBack: return "give-back";
    }
    return "?";
}

// One SpringBoard start, as the watcher sees it (0.4 s ticks): the screen locked until unlockAt; Stage Manager off at first (startsOn: on).
// Our question, when asked, is answered after answerAsk seconds with yesToAsk (answerAsk < 0: never answered). Apple's introduction (first-time path)
// is answered after answerIntro seconds with yesToIntro (< 0: never). The caller's side as StatusBar.x does it: Nothing -> consent done; Ask -> the
// question; Declined / UserOff -> consent no; FirstTime -> the ever mark; Write -> on. Returns the final consent; *onAt when it came on (-1: never);
// counts of questions, first-time paths and writes, and whether anything was asked or written while locked or before 12 s.
typedef struct { int consent; double onAt; int asks, firstTimes, writes; BOOL actedLocked, actedEarly; DMSMOnStep last; } Run;
static Run RunStart(double unlockAt, int consent, BOOL startsOn, int everSB, NSString *everKey, double answerAsk, BOOL yesToAsk, double answerIntro, BOOL yesToIntro, double userOffAt) {
    Run r = { consent, -1.0, 0, 0, 0, NO, NO, DMSMOnWait };
    BOOL on = startsOn, asking = NO; double askAt = -1.0, introAt = -1.0;
    for (double t = 0.0; t < 300.0; t += 0.4) {
        BOOL unlocked = t >= unlockAt;
        if (on && userOffAt >= 0.0 && t >= userOffAt) { on = NO; userOffAt = -1.0; }   // (the user switches it off in Control Center)
        if (asking && answerAsk >= 0.0 && t - askAt >= answerAsk) { asking = NO; r.consent = yesToAsk ? DMSMConsentYes : DMSMConsentNo; }
        if (introAt >= 0.0 && answerIntro >= 0.0 && t - introAt >= answerIntro && yesToIntro && !on) { on = YES; r.onAt = t; answerIntro = -1.0; }
        if (asking) continue;   // (the question is up: the watcher waits for its answer)
        DMSMOnStep s = DMSMSwitchOnStep(on, r.consent, t, unlocked, everSB, everKey, introAt >= 0.0 ? t - introAt : -1.0, YES, NO);
        r.last = s;
        BOOL acts = s == DMSMOnAsk || s == DMSMOnFirstTime || s == DMSMOnWrite;
        if (acts && !unlocked) r.actedLocked = YES;
        if (acts && t < 12.0) r.actedEarly = YES;
        switch (s) {
            case DMSMOnNothing: if (r.consent != DMSMConsentDone) r.consent = DMSMConsentDone; break;
            case DMSMOnAsk: asking = YES; askAt = t; r.asks++; break;
            case DMSMOnFirstTime: introAt = t; everSB = 1; r.firstTimes++; break;
            case DMSMOnWrite: on = YES; r.onAt = t; r.writes++; break;
            case DMSMOnDeclined: case DMSMOnUserOff: r.consent = DMSMConsentNo; break;
            default: break;
        }
    }
    return r;
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

        // ---- stored consent values ----
        CHECK(DMSMConsentFrom(nil) == DMSMConsentUnasked && DMSMConsentFrom(@0) == DMSMConsentUnasked && DMSMConsentFrom(@7) == DMSMConsentUnasked, "absent / 0 / out of range: unasked");
        CHECK(DMSMConsentFrom(@1) == DMSMConsentYes && DMSMConsentFrom(@2) == DMSMConsentDone && DMSMConsentFrom(@3) == DMSMConsentNo, "1 yes, 2 done, 3 no");
        CHECK(DMSMConsentFrom(@"3") == DMSMConsentNo && DMSMConsentFrom([NSDate date]) == DMSMConsentUnasked, "a string \"3\" counts; another type is unasked");

        // ---- the step table (with a yes, the switch-on itself as before 1.5.1) ----
        int Y = DMSMConsentYes;
        CHECK(DMSMSwitchOnStep(YES, Y, 0.0, NO, 0, nil, -1.0, YES, NO) == DMSMOnNothing, "on: nothing");
        CHECK(DMSMSwitchOnStep(NO, Y, 5.0, YES, 0, nil, -1.0, YES, NO) == DMSMOnWait, "starting: wait");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, NO, 0, nil, -1.0, YES, NO) == DMSMOnWait, "locked: wait, no first-time path");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, NO, 1, @"SBChamoisWindowingEverEnabled", -1.0, YES, NO) == DMSMOnWait, "locked: no write either");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, 0, nil, -1.0, YES, NO) == DMSMOnFirstTime, "unlocked, never on anywhere: first-time path");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, 0, @"SBChamoisWindowingEverEnabled", -1.0, YES, NO) == DMSMOnWrite, "A12Z: SpringBoard says never, Apple's key says it was: written directly");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, 1, nil, -1.0, YES, NO) == DMSMOnWrite, "ever on in SpringBoard: written");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, -1, nil, -1.0, YES, NO) == DMSMOnWrite, "no ever mark to ask: written (as before)");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, 1, nil, 10.0, YES, NO) == DMSMOnWait, "introduction 10 s ago: wait");
        CHECK(DMSMSwitchOnStep(NO, Y, 30.0, YES, 1, nil, 45.0, YES, NO) == DMSMOnDeclined, "introduction 45 s ago and still off: declined -- NOT written (1.5.0 wrote it)");
        CHECK(DMSMSwitchOnStep(NO, Y, 80.0, NO, 1, nil, 50.0, YES, NO) == DMSMOnWait, "introduction long ago but locked: wait");
        // ---- consent ----
        for (int c = DMSMConsentUnasked; c <= DMSMConsentNo; c++) CHECK(DMSMSwitchOnStep(YES, c, 30.0, YES, 1, nil, -1.0, YES, NO) == DMSMOnNothing, "on with consent %d: nothing", c);
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentUnasked, 30.0, YES, 0, nil, -1.0, YES, NO) == DMSMOnAsk, "unasked, unlocked: our question (not Apple's path)");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentUnasked, 30.0, YES, 1, @"SBChamoisWindowingEverEnabled", -1.0, YES, NO) == DMSMOnAsk, "unasked, ever on: our question (not a write)");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentUnasked, 30.0, NO, 0, nil, -1.0, YES, NO) == DMSMOnWait, "unasked, locked: the question waits for the unlock");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentUnasked, 8.0, YES, 0, nil, -1.0, YES, NO) == DMSMOnWait, "unasked, SpringBoard starting: the question waits");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentNo, 30.0, YES, 1, nil, -1.0, YES, NO) == DMSMOnLeftOff, "a no: left off");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentNo, 30.0, YES, 0, nil, 60.0, YES, NO) == DMSMOnLeftOff, "a no after a declined introduction: left off");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentDone, 30.0, YES, 1, nil, -1.0, YES, NO) == DMSMOnUserOff, "it was on, off now: the user's switch-off");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentDone, 5.0, YES, 1, nil, -1.0, YES, NO) == DMSMOnWait, "off read in SpringBoard's first seconds: not taken for the user's switch-off");
        // sweep: nothing is ever written or set without a yes, never on the Lock Screen or in the first 12 s; the question only when unasked
        int sweep = 0, bad = 0;
        NSArray *keys = @[[NSNull null], @"SBChamoisWindowingEverEnabled", @"TPSBChamoisWindowingEnabled"];
        for (int on = 0; on <= 1; on++) for (int c = DMSMConsentUnasked; c <= DMSMConsentNo; c++) for (double age = 0.0; age <= 30.0; age += 1.5) for (int u = 0; u <= 1; u++)
            for (int e = -1; e <= 1; e++) for (id k in keys) for (double asked = -1.0; asked <= 60.0; asked += 7.5) {
                NSString *key = k == [NSNull null] ? nil : k;
                DMSMOnStep s = DMSMSwitchOnStep(on, c, age, u, e, key, asked, YES, NO);
                BOOL writes = s == DMSMOnWrite || s == DMSMOnFirstTime;
                BOOL wrong = (writes && c != DMSMConsentYes) || (s == DMSMOnAsk && c != DMSMConsentUnasked) || ((writes || s == DMSMOnAsk) && (!u || age < 12.0))
                          || (on && s != DMSMOnNothing) || (s == DMSMOnFirstTime && (e != 0 || key || asked >= 0.0)) || (c == DMSMConsentNo && !on && s != DMSMOnLeftOff);
                if (wrong) { bad++; if (bad < 5) printf("  sweep: on %d consent %d age %.1f unlocked %d ever %d key %s asked %.1f -> %s\n", on, c, age, u, e, key.UTF8String ?: "-", asked, StepName(s)); }
                sweep++;
            }
        CHECK(bad == 0, "sweep: %d of %d cases wrong", bad, sweep);

        // ---- whole starts (0.4 s ticks) ----
        // A12Z as found, an existing user with the engine and Stage Manager off (SpringBoard reads TrollPad's empty copy, Apple's key says it was on)
        // and a yes from before 1.5.1 does not exist: asked after the unlock; Turn On -> written right away, no introduction
        Run r = RunStart(30.0, DMSMConsentUnasked, NO, 0, DMSMEverKeyIn(a12z), 2.0, YES, -1.0, NO, -1.0);
        CHECK(r.asks == 1 && r.firstTimes == 0 && r.writes == 1 && r.onAt >= 32.0 && r.onAt < 33.0 && r.consent == DMSMConsentDone && !r.actedLocked,
              "A12Z: asked once after the unlock, Turn On -> written, no introduction (asks %d writes %d on at %.1f consent %d)", r.asks, r.writes, r.onAt, r.consent);
        // a fresh TrollPad iPad (never on anywhere), Lock Screen until 40 s: our question after the unlock, Turn On after 3 s, Apple's introduction, Continue after 5 s
        r = RunStart(40.0, DMSMConsentUnasked, NO, 0, nil, 3.0, YES, 5.0, YES, -1.0);
        CHECK(r.asks == 1 && r.firstTimes == 1 && r.writes == 0 && r.onAt >= 48.0 && r.onAt < 49.5 && r.consent == DMSMConsentDone && !r.actedLocked && !r.actedEarly,
              "fresh iPad: question, then Apple's introduction, on from its Continue (asks %d first-time %d on at %.1f consent %d)", r.asks, r.firstTimes, r.onAt, r.consent);
        // ... Not Now to our question: nothing written, ever, and asked only once
        r = RunStart(20.0, DMSMConsentUnasked, NO, 0, nil, 2.0, NO, -1.0, NO, -1.0);
        CHECK(r.asks == 1 && r.firstTimes == 0 && r.writes == 0 && r.onAt < 0.0 && r.consent == DMSMConsentNo && r.last == DMSMOnLeftOff,
              "Not Now: nothing written, asked once (asks %d writes %d consent %d last %s)", r.asks, r.writes, r.consent, StepName(r.last));
        // ... Turn On to ours, but Apple's introduction declined (never answered): a no 45 s later, nothing written
        r = RunStart(20.0, DMSMConsentUnasked, NO, 0, nil, 1.0, YES, -1.0, NO, -1.0);
        CHECK(r.asks == 1 && r.firstTimes == 1 && r.writes == 0 && r.onAt < 0.0 && r.consent == DMSMConsentNo,
              "declined introduction: a no, nothing written (asks %d first-time %d writes %d consent %d)", r.asks, r.firstTimes, r.writes, r.consent);
        // an existing user with Stage Manager on: never asked, consent done
        r = RunStart(0.0, DMSMConsentUnasked, YES, 1, DMSMEverKeyIn(ipad17), 1.0, YES, -1.0, NO, -1.0);
        CHECK(r.asks == 0 && r.writes == 0 && r.consent == DMSMConsentDone, "already on: not asked (asks %d consent %d)", r.asks, r.consent);
        // ... who then switches it off in Control Center at 60 s: left off, never written again
        r = RunStart(0.0, DMSMConsentUnasked, YES, 1, DMSMEverKeyIn(ipad17), 1.0, YES, -1.0, NO, 60.0);
        CHECK(r.asks == 0 && r.writes == 0 && r.consent == DMSMConsentNo && r.last == DMSMOnLeftOff, "switched off by the user: stays off (asks %d writes %d consent %d)", r.asks, r.writes, r.consent);
        // a yes from Settings' Turn On Stage Manager (consent yes stored), iPad where it was on before: written at 12 s, no question
        r = RunStart(0.0, DMSMConsentYes, NO, 1, DMSMEverKeyIn(ipad17), -1.0, NO, -1.0, NO, -1.0);
        CHECK(r.asks == 0 && r.writes == 1 && r.onAt >= 12.0 && r.onAt < 12.5, "Settings' Turn On: written at 12 s, no question (%.1f)", r.onAt);
        // never unlocked: nothing happens at all
        r = RunStart(1000.0, DMSMConsentUnasked, NO, 0, nil, 1.0, YES, 1.0, YES, -1.0);
        CHECK(r.asks == 0 && r.firstTimes == 0 && r.writes == 0 && r.onAt < 0.0, "never unlocked: not asked, Stage Manager not touched");

        // ---- 1.5.1 logic test: who switched it off (B2), an introduction that never shows (W1), Settings' Turn On during the wait (W2) ----
        // An engine period, step by step as the watcher does it: what the caller does is modelled here (StatusBar.x / sshtoggled): Nothing -> done;
        // GiveBack -> on, key cleared, done; Ask -> answered yes; FirstTime -> the introduction (if it appears: seen, then answered); Write -> on;
        // Declined / UserOff -> no. ourOff: WE switch it off at that time (windowing off, the tweak off or removed, another engine, a failed check):
        // done goes back to yes. userOff: the user switches it off. button: Settings' Turn On Stage Manager (yes, the wait reset).
        typedef struct { int consent; BOOL on, userSaved; int asks, writes, firstTimes, giveBacks; double noAt; } Seq;   // (noAt: when a no was recorded, 0 none)
        __block BOOL seeable = YES;   // (N3: the iPadOS lets the check see Apple's introduction; NO: the caller passes -1 during the wait)
        Seq (^period)(Seq, BOOL, double, BOOL, double, double, double) = ^Seq(Seq q, BOOL introAppears, double introAnswer, BOOL introYes, double ourOffAt, double userOffAt, double buttonAt) {
            double introAt = -1.0; int intro = 0; int everSB = 1;   // (intro: 0 not seen, 2 on screen, 1 seen and gone -- SMSwitchOn.h)
            if (q.consent == DMSMConsentUnasked || q.consent == DMSMConsentYes) everSB = q.writes || q.firstTimes ? 1 : 0;
            for (double t = 0.0; t < 200.0; t += 0.4) {
                if (ourOffAt >= 0.0 && t >= ourOffAt && q.on) { q.on = NO; if (q.consent == DMSMConsentDone) q.consent = DMSMConsentYes; ourOffAt = -1.0; break; }   // (the period ends with our off)
                if (userOffAt >= 0.0 && t >= userOffAt && q.on) { q.on = NO; userOffAt = -1.0; }
                if (buttonAt >= 0.0 && t >= buttonAt) { q.consent = DMSMConsentYes; introAt = -1.0; intro = 0; buttonAt = -1.0; }
                if (introAt >= 0.0 && introAppears && t - introAt >= 1.0 && intro == 0) intro = 2;
                if (intro == 2 && introAnswer >= 0.0 && t - introAt >= introAnswer) { if (introYes) q.on = YES; intro = 1; introAnswer = -1.0; }
                DMSMOnStep st = DMSMSwitchOnStep(q.on, q.consent, t, YES, everSB, nil, introAt >= 0.0 ? t - introAt : -1.0, introAt >= 0.0 && !seeable ? -1 : intro, q.userSaved);
                switch (st) {
                    case DMSMOnNothing: q.consent = DMSMConsentDone; q.userSaved = NO; break;   // (on as the engine: a kept "user had it on" is satisfied, N2)
                    case DMSMOnGiveBack: q.on = YES; q.userSaved = NO; q.consent = DMSMConsentDone; q.giveBacks++; break;
                    case DMSMOnAsk: q.asks++; q.consent = DMSMConsentYes; break;
                    case DMSMOnFirstTime: introAt = t; everSB = 1; q.firstTimes++; break;
                    case DMSMOnWrite: q.on = YES; q.writes++; break;
                    case DMSMOnDeclined: case DMSMOnUserOff: q.consent = DMSMConsentNo; if (q.noAt == 0.0) q.noAt = t; break;
                    default: break;
                }
            }
            return q;
        };
        // B2: fresh 18 install, the question, Turn On, Apple's introduction, Continue: on. Then windowing off (OUR off), windowing on again: on again, no question
        Seq q = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        q = period(q, YES, 3.0, YES, 60.0, -1.0, -1.0);
        CHECK(!q.on && q.consent == DMSMConsentYes && q.asks == 1 && q.firstTimes == 1, "fresh install: yes, on, then our own off -> consent back to yes (consent %d)", q.consent);
        q = period(q, YES, -1.0, NO, -1.0, -1.0, -1.0);
        CHECK(q.on && q.consent == DMSMConsentDone && q.asks == 1 && q.writes == 1, "windowing on again: switched on again, no second question (asks %d writes %d consent %d)", q.asks, q.writes, q.consent);
        // ... the tweak off then on, removal and reinstall, another engine and back, a failed self-check start: each is our off -> the same
        for (int round = 0; round < 4; round++) { q = period(q, YES, -1.0, NO, 20.0, -1.0, -1.0); q = period(q, YES, -1.0, NO, -1.0, -1.0, -1.0); }
        CHECK(q.on && q.consent == DMSMConsentDone && q.asks == 1, "four more of our own offs and back: on each time, never asked again, never a no (asks %d consent %d)", q.asks, q.consent);
        // ... and the user's OWN off is still their no
        q = period(q, YES, -1.0, NO, -1.0, 30.0, -1.0);
        CHECK(!q.on && q.consent == DMSMConsentNo, "the user's own switch-off: a no, left off (consent %d)", q.consent);
        // B2 (2): the user had Stage Manager on, another engine held it off (stageManagerUserOn), then Stage Manager is picked as the engine: given back
        Seq u = { DMSMConsentUnasked, NO, YES, 0, 0, 0, 0 };
        u = period(u, YES, -1.0, NO, -1.0, -1.0, -1.0);
        CHECK(u.on && u.giveBacks == 1 && u.asks == 0 && u.consent == DMSMConsentDone && !u.userSaved, "the user's own on, held off for another engine: given back, no question (asks %d)", u.asks);
        Seq un = { DMSMConsentNo, NO, YES, 0, 0, 0, 0 };
        un = period(un, YES, -1.0, NO, -1.0, -1.0, -1.0);
        CHECK(un.on && un.giveBacks == 1, "... also over an old no: their own earlier on comes first");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentNo, 5.0, YES, 1, nil, -1.0, NO, YES) == DMSMOnWait, "the give-back waits for SpringBoard's first seconds too");
        // W1: a yes, Apple's first-time path, and SpringBoard never shows the introduction: the yes stands -- written after the wait, not a no
        Seq w = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        w = period(w, NO, -1.0, NO, -1.0, -1.0, -1.0);
        CHECK(w.on && w.firstTimes == 1 && w.writes == 1 && w.consent == DMSMConsentDone, "no introduction shown: written after the wait (writes %d consent %d)", w.writes, w.consent);
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentYes, 80.0, YES, 1, nil, 45.0, 0, NO) == DMSMOnWrite && DMSMSwitchOnStep(NO, DMSMConsentYes, 80.0, YES, 1, nil, 45.0, 1, NO) == DMSMOnDeclined,
              "45 s after the first-time path: not seen -> written, seen and gone -> declined");
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentYes, 200.0, YES, 1, nil, 150.0, 2, NO) == DMSMOnWait, "the introduction still on screen after 150 s: still waiting (never a no while the user reads it)");
        // ... an introduction left open for a minute, then Continue: on, never a no on the way
        Seq wl = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        wl = period(wl, YES, 60.0, YES, -1.0, -1.0, -1.0);
        CHECK(wl.on && wl.writes == 0 && wl.consent == DMSMConsentDone, "introduction open 60 s, then Continue: on from Apple's Continue, consent done (writes %d consent %d)", wl.writes, wl.consent);
        // ... open for 70 s, then closed without Continue: a no only after it is gone
        Seq wn = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        wn = period(wn, YES, 70.0, NO, -1.0, -1.0, -1.0);
        CHECK(!wn.on && wn.writes == 0 && wn.consent == DMSMConsentNo && wn.noAt >= 70.0, "introduction open 70 s, then closed: a no once it is gone (at %.1f), nothing written (writes %d)", wn.noAt, wn.writes);
        // ... and a shown introduction that the user declines: still a no, nothing written
        Seq wd = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        wd = period(wd, YES, 5.0, NO, -1.0, -1.0, -1.0);
        CHECK(!wd.on && wd.writes == 0 && wd.consent == DMSMConsentNo, "introduction shown and declined: a no, nothing written (writes %d consent %d)", wd.writes, wd.consent);
        // N3: where the check can't see the introduction (-1): the rule before it -- still off 45 s later is a no, never a blind write
        CHECK(DMSMSwitchOnStep(NO, DMSMConsentYes, 80.0, YES, 1, nil, 30.0, -1, NO) == DMSMOnWait && DMSMSwitchOnStep(NO, DMSMConsentYes, 80.0, YES, 1, nil, 45.0, -1, NO) == DMSMOnDeclined,
              "introduction not seeable: wait 45 s, then declined (not written)");
        seeable = NO;
        Seq ns = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        ns = period(ns, YES, 5.0, NO, -1.0, -1.0, -1.0);
        CHECK(!ns.on && ns.writes == 0 && ns.consent == DMSMConsentNo, "not seeable, declined: a no, nothing written (writes %d consent %d)", ns.writes, ns.consent);
        Seq nn = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        nn = period(nn, NO, -1.0, NO, -1.0, -1.0, -1.0);
        CHECK(!nn.on && nn.writes == 0 && nn.consent == DMSMConsentNo, "not seeable, no introduction at all: a no as before the check, never a blind write (writes %d)", nn.writes);
        Seq nc = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        nc = period(nc, YES, 4.0, YES, -1.0, -1.0, -1.0);
        CHECK(nc.on && nc.writes == 0 && nc.consent == DMSMConsentDone, "not seeable, Continue in the introduction: on from Apple's switch, consent done");
        seeable = YES;
        // N2: a kept "user had it on" left over while Stage Manager is on (it came on another way): cleared, so the user's own switch-off is their no
        Seq st2 = { DMSMConsentDone, YES, YES, 0, 0, 0, 0 };
        st2 = period(st2, NO, -1.0, NO, -1.0, 30.0, -1.0);
        CHECK(!st2.on && st2.giveBacks == 0 && st2.consent == DMSMConsentNo && !st2.userSaved, "stale kept on, then the user's switch-off: their no, not given back (give-backs %d)", st2.giveBacks);
        // W2: declined in the introduction, then Turn On Stage Manager in Settings within the 45 s: not lost -- written at once
        Seq b = { DMSMConsentUnasked, NO, NO, 0, 0, 0, 0 };
        b = period(b, YES, 3.0, NO, -1.0, -1.0, 30.0);
        CHECK(b.on && b.writes == 1 && b.consent == DMSMConsentDone, "Turn On in Settings during the wait: switched on (writes %d consent %d)", b.writes, b.consent);

        // ---- keeping it off while another engine runs ----
        CHECK(DMSMHoldStepFor(NO, YES, DMSMConsentUnasked, NO, 30.0, YES) == DMSMHoldNothing, "no engine of ours: nothing");
        CHECK(DMSMHoldStepFor(YES, NO, DMSMConsentUnasked, NO, 30.0, YES) == DMSMHoldNothing, "Stage Manager off: nothing");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentUnasked, YES, 30.0, YES) == DMSMHoldOff, "the engine picked in Settings: switched off (its confirmation said so)");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentYes, NO, 30.0, YES) == DMSMHoldOff, "a yes: switched off");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentNo, YES, 30.0, YES) == DMSMHoldLeave, "a no: left on, even with a pick");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentUnasked, NO, 30.0, YES) == DMSMHoldAsk, "a default engine nobody picked: asked");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentUnasked, NO, 30.0, NO) == DMSMHoldWait, "... not on the Lock Screen");
        CHECK(DMSMHoldStepFor(YES, YES, DMSMConsentUnasked, NO, 6.0, YES) == DMSMHoldWait, "... not in SpringBoard's first seconds");
        int hs = 0, hbad = 0;
        for (int er = 0; er <= 1; er++) for (int on = 0; on <= 1; on++) for (int c = 0; c <= 3; c++) for (int pk = 0; pk <= 1; pk++) for (double age = 0; age <= 30; age += 3) for (int u = 0; u <= 1; u++) {
            DMSMHoldStep h = DMSMHoldStepFor(er, on, c, pk, age, u);
            BOOL wrong = (h == DMSMHoldOff && !(c == DMSMConsentYes || c == DMSMConsentDone || pk)) || (h == DMSMHoldOff && c == DMSMConsentNo) || (h == DMSMHoldAsk && (!u || age < 12.0 || c != DMSMConsentUnasked || pk))
                      || ((!er || !on) && h != DMSMHoldNothing);
            if (wrong) hbad++;
            hs++;
        }
        CHECK(hbad == 0, "hold sweep: %d of %d cases wrong", hbad, hs);
    }
    printf("test-smswitchon: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
