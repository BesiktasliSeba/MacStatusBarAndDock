// test-crashsteppages.m -- the Settings pages' side of a crash guard note that keeps a part skipped (1.8.7.5, audit L104 of 1.8.7.2), for
// tools/test-crashstep.sh: run right after its "l104" scenario, on the record and the note the real guard left (step 1 after an earlier step 1b,
// the Dock still on the skip list). The real CrashExplain.h, and cut out by the script: LineSwitch.h from MSBDGuardAction to the end of
// MSBDNoteSwitch (the footers, the rule for ending the note, the note of a switch), the condition of Turn Back On in its specifiers, and the
// Mac / Stock picker's lines that end the note (MSBRootListController.m). Run: test-crashsteppages [untested] (untested: a DEBUG build acting as
// iPadOS 26). Preferences: the note in com.besiktasliseba.macstatusbaranddock (test-crashstep.sh removes the domain at the end).
#ifndef MSBD_TEST_EXPLAIN_H
#define MSBD_TEST_EXPLAIN_H "../common/CrashExplain.h"
#endif
#import MSBD_TEST_EXPLAIN_H
#define MSBD_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")   // (LineSwitch.h's)
#include MSBD_TEST_LINESWITCH_CUT   // (static int MSBDGuardAction ... MSBDNoteSwitch, from LineSwitch.h)
static BOOL TurnBackOnOffered(void) {   // (msbd_untestedSpecifiers on 15/16: no footer, no group; safe mode: the button; else its condition)
    if (!MSBDVersionTested() || !MSBDSafeModeFooter()) return NO;
    if (MSBDSafeMode()) return YES;
    return MSBD_TEST_TURNBACKON_COND;
}
static void PickerBackTo(BOOL on) {   // (the Status Bar Style picker: on = Stock picked, off = back to Mac)
#include MSBD_TEST_PICKER_CUT
}
static int fails = 0, total = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    total++; if (!ok) fails++;
    printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", what.UTF8String, got ? "\n      " : "", got ? got.UTF8String : "");
}
static void SetNote(int action) {
    CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), action ? (__bridge CFNumberRef)@(action) : NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void SetSafe(BOOL on) {
    CFPreferencesSetValue(CFSTR(MSBD_SAFE_KEY), on ? kCFBooleanTrue : NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void Record(NSString *text) { [text writeToFile:@MSBD_GUARD_RECORD atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
static NSString *Recent(void) { return [NSString stringWithContentsOfFile:@MSBD_GUARD_RECENT encoding:NSUTF8StringEncoding error:nil] ?: @""; }
int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL untested = argc > 1 && !strcmp(argv[1], "untested");
#if DEBUG
        if (untested) MSBDGatePublish(MSBD_GATE_FAKE_STATE, 26);
#endif
        if (untested != !MSBDVersionTested()) { printf("FAIL  the Mac reads as %s iPadOS\n", MSBDVersionTested() ? "a tested" : "an untested"); return 1; }
        NSString *guardRecord = [NSString stringWithContentsOfFile:@MSBD_GUARD_RECORD encoding:NSUTF8StringEncoding error:nil];
        NSDictionary *r = MSBDCrashRecord();
        Check(@"the guard's note: step 1 (action 1), with its record", MSBDGuardAction() == 1 && [r[@"action"] intValue] == 1, nil);
        Check(@"the record names the switch and the Dock part", [r[@"switches"] count] == 1 && [r[@"parts"] count] == 1 && [r[@"parts"][0][0] isEqualToString:@"DockMagnification"], nil);
        Check(@"MSBDStepPartsOff: YES (a part is no longer loaded)", MSBDStepPartsOff(r), nil);
        NSString *footer = untested ? MSBDUntestedFooter() : MSBDSafeModeFooter();
        if (!untested) {
            Check(@"footer: the switch AND the Dock, and the way back", [footer isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. After an earlier crash, the Dock is still turned off. Tap Turn Back On to try again, or Report a Problem."], footer);
            NSString *alert = MSBDGuardExplanation(1, NO, YES);
            Check(@"notice: the same, with Settings' button", [alert isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. After an earlier crash, the Dock is still turned off. To try again, tap Turn Back On in Settings."], alert);
            Check(@"notice title: two things off", [MSBDGuardAlertTitle(1) isEqualToString:@"Features Turned Off"], MSBDGuardAlertTitle(1));
            Check(@"Report a Problem: the switch and the part", [MSBDGuardActionWords(r) isEqualToString:@"turned off “Recent Switch”, still not loading the Dock (DockMagnification)"], MSBDGuardActionWords(r));
            Check(@"Turn Back On offered", TurnBackOnOffered(), nil);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES);
            Check(@"a switch turned on: the note stays (the Dock stays skipped, said so)", MSBDGuardAction() == 1 && MSBDSafeModeFooter() != nil, nil);
            Check(@"  ... and the switch is noted for the guard, as before", [Recent() containsString:@" com.besiktasliseba.test-crashstep otherSwitch Other Switch\n"], Recent());
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", YES, NO);
            Check(@"a switch turned off: the note stays", MSBDGuardAction() == 1, nil);
            PickerBackTo(NO);
            Check(@"Status Bar Style back to Mac: the note stays", MSBDGuardAction() == 1, nil);
            // As before: step 1's note without a part ends with a switch change (and the picker's way back to Mac); step 1b's without a part on any
            // version; step 1b's with a part never; nothing in safe mode.
            Record([guardRecord stringByReplacingOccurrencesOfString:@"part DockMagnification the Dock|the Dock\n" withString:@""]); SetNote(1);
            Check(@"(a step 1 record without the part)", !MSBDStepPartsOff(MSBDCrashRecord()) && [MSBDCrashRecord()[@"switches"] count] == 1, nil);
            Check(@"  its footer as before", [MSBDSafeModeFooter() isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. If this keeps happening, tap Report a Problem."], MSBDSafeModeFooter());
            Check(@"  no Turn Back On", !TurnBackOnOffered(), nil);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES);
            Check(@"  a switch change ends it, as before", MSBDGuardAction() == 0, nil);
            SetNote(1); PickerBackTo(YES);
            Check(@"  Stock picked: the note stays", MSBDGuardAction() == 1, nil);
            PickerBackTo(NO);
            Check(@"  back to Mac: it ends, as before", MSBDGuardAction() == 0, nil);
            Record(@"time 1\naction 4\ntested 1\nios 16.5\nbuild 1\nverdict 1\nblamed x\npart DockMagnification the Dock|the Dock\n"); SetNote(4);
            Check(@"step 1b's note with a part: Turn Back On", TurnBackOnOffered(), nil);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES); PickerBackTo(NO);
            Check(@"  a switch change or back to Mac: it stays, as before", MSBDGuardAction() == 4, nil);
            Record(@"time 1\naction 4\ntested 1\nios 16.5\nbuild 1\nverdict 1\nblamed x\nfeature com.besiktasliseba.macstatusbar macBanners 0 Mac-Style Banners|the Mac-style banners\n");
            Check(@"step 1b's note without a part: no Turn Back On", !TurnBackOnOffered(), nil);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES);
            Check(@"  a switch change ends it, as before", MSBDGuardAction() == 0, nil);
            Record(guardRecord); SetNote(1); SetSafe(YES);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES); PickerBackTo(NO);
            Check(@"safe mode: nothing ends the note, Turn Back On offered", MSBDGuardAction() == 1 && TurnBackOnOffered(), nil);
            SetSafe(NO);
            Record(guardRecord); SetNote(1);   // (as the guard left it, for the script's next look)
        } else {
            Check(@"untested footer: the switch AND the Dock, and Enable Anyway as the way back", [footer isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. After an earlier crash, the Dock is still turned off. Turn Enable Anyway off and on to try again, or tap Report a Problem."], footer);
            NSString *alert = MSBDGuardExplanation(1, YES, YES);
            Check(@"untested notice", [alert isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. After an earlier crash, the Dock is still turned off. To try again, turn Enable Anyway off and on in Settings."], alert);
            MSBDNoteSwitch(@"com.besiktasliseba.test-crashstep", @"otherSwitch", @"Other Switch", NO, YES);
            Check(@"a switch change: the note stays, as before on an untested iPadOS", MSBDGuardAction() == 1, nil);
            Record([guardRecord stringByReplacingOccurrencesOfString:@"part DockMagnification the Dock|the Dock\n" withString:@""]); SetNote(1);
            Check(@"  without the part: the footer as before", [MSBDUntestedFooter() isEqualToString:@"SpringBoard crashed twice after “Recent Switch” was turned on, so it was turned off. If this keeps happening, tap Report a Problem."], MSBDUntestedFooter());
            Record(guardRecord);
        }
    }
    printf("%d/%d passed%s\n", total - fails, total, argc > 1 ? " (untested iPadOS)" : "");
    return fails ? 1 : 0;
}
