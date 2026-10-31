// test-autolocklong.m -- Mac test of the longer Auto-Lock times' SpringBoard side (macsettings/AutoLockLongest.h, 1.7.2 item 18): which results of
// SpringBoard's own step are given our time back. SpringBoard takes any Auto-Lock over its MAX_TOTAL_INTERVAL (3600 s on 15.6.1) for Never and
// leaves the timer's total at DBL_MAX; our 2 hours (7200 s) was Never. And (1.7.3, item 9) when a stored 2 hours goes down to 1 hour because
// nothing of ours will keep it -- removed, switched off, the keeping part not in SpringBoard -- and when it is given back.
#import <Foundation/Foundation.h>
#import <float.h>
#import "../macsettings/AutoLockLongest.h"

static int gFail = 0, gN = 0;
static void Expect(NSString *what, double t, double total, BOOL want) {
    gN++;
    BOOL got = MSAutoLockKeepsTime(t, total);
    if (got != want) { gFail++; printf("FAIL  %s: got %d, want %d\n", what.UTF8String, got, want); }
    else printf("PASS  %s\n", what.UTF8String);
}
static void Step(NSString *what, double stored, BOOL kept, BOOL leaving, BOOL removing, double record, MSAutoLockStep want) {
    gN++;
    MSAutoLockStep got = MSAutoLockDecide(stored, kept, leaving, removing, record);
    if (got != want) { gFail++; printf("FAIL  %s: got %d, want %d\n", what.UTF8String, got, want); }
    else printf("PASS  %s\n", what.UTF8String);
}
int main(void) {
    @autoreleasepool {
        Expect(@"2 hours made never by the step: kept", 7200, DBL_MAX, YES);
        Expect(@"2 hours, total infinite (another way to say never): kept", 7200, INFINITY, YES);
        Expect(@"30 minutes made never (a SpringBoard with a lower cap): kept", 1800, DBL_MAX, YES);
        Expect(@"1 hour made never (a lower cap): kept", 3600, DBL_MAX, YES);
        Expect(@"1 hour kept by SpringBoard itself: left alone", 3600, 3600, NO);
        Expect(@"2 hours already kept (halved on the Home Screen later): left alone", 7200, 3600, NO);
        Expect(@"Never (2147483647): stays never", 2147483647.0, DBL_MAX, NO);
        Expect(@"longer than our longest: stays never", MS_AUTOLOCK_LONGEST + 1, DBL_MAX, NO);
        Expect(@"no Auto-Lock read (NAN): left alone", NAN, DBL_MAX, NO);
        Expect(@"zero: left alone", 0, DBL_MAX, NO);
        Expect(@"negative (the list's -1 for Never): left alone", -1, DBL_MAX, NO);
        Expect(@"infinite time: left alone", INFINITY, DBL_MAX, NO);
        Expect(@"a total that is not a number: left alone", 7200, NAN, NO);
        Expect(@"Apple's 2 minutes: left alone", 120, 120, NO);
        Expect(@"our longest is 2 hours", MS_AUTOLOCK_LONGEST, DBL_MAX, MS_AUTOLOCK_LONGEST == 7200.0);

        // ---- 2 hours left behind (1.7.3, item 9): MSAutoLockDecide(stored, kept here, leaving, removing, record) ----
        Step(@"kept here, on: 2 hours stays", 7200, YES, NO, NO, 0, MSAutoLockStay);
        Step(@"a SpringBoard of ours that doesn't keep it (MacStatusBar off, part held back): lowered to 1 hour, recorded", 7200, NO, NO, NO, 0, MSAutoLockLowerAndRecord);
        Step(@"switched off while our part still runs: lowered, recorded (given back when switched on)", 7200, YES, YES, NO, 0, MSAutoLockLowerAndRecord);
        Step(@"being removed: lowered, nothing recorded", 7200, YES, YES, YES, 0, MSAutoLockLower);
        Step(@"being removed, not kept here either: lowered", 7200, NO, YES, YES, 0, MSAutoLockLower);
        Step(@"being removed after a switch-off had lowered it: the record forgotten", 3600, YES, YES, YES, 7200, MSAutoLockForget);
        Step(@"kept here again, still at our 1 hour: 2 hours given back", 3600, YES, NO, NO, 7200, MSAutoLockGiveBack);
        Step(@"kept here again, another time picked meanwhile: the user's stays, the record forgotten", 1800, YES, NO, NO, 7200, MSAutoLockForget);
        Step(@"  ... Never picked meanwhile: stays Never", 2147483647.0, YES, NO, NO, 7200, MSAutoLockForget);
        Step(@"not kept here, lowered before: waits for a SpringBoard that keeps it", 3600, NO, NO, NO, 7200, MSAutoLockStay);
        Step(@"switched off, lowered before: stays", 3600, YES, YES, NO, 7200, MSAutoLockStay);
        Step(@"Never, not kept here: stays Never (stock SpringBoard keeps Never)", 2147483647.0, NO, NO, NO, 0, MSAutoLockStay);
        Step(@"Apple's own times, not kept here: left alone", 300, NO, YES, NO, 0, MSAutoLockStay);
        Step(@"1 hour, not kept here: left alone (stock keeps it)", 3600, NO, NO, NO, 0, MSAutoLockStay);
        Step(@"a stored time ManagedConfiguration didn't give (NAN): left alone", NAN, NO, YES, YES, 0, MSAutoLockStay);
        Step(@"over 1 hour but not over our 2 (anything stock takes for Never and we would keep): lowered", 5400, NO, NO, NO, 0, MSAutoLockLowerAndRecord);
        Step(@"longer than our longest: not ours, left alone", 7201, NO, NO, NO, 0, MSAutoLockStay);
        Step(@"a record that isn't a time of ours (-1, something else stored): forgotten, nothing set", 3600, YES, NO, NO, -1, MSAutoLockForget);
        Step(@"a record out of range: forgotten, nothing set", 3600, YES, NO, NO, 99999, MSAutoLockForget);
        Step(@"removed with a bad record: forgotten", 1800, NO, YES, YES, -1, MSAutoLockForget);
    }
    printf("test-autolocklong: %d/%d passed\n", gN - gFail, gN);
    return gFail ? 1 : 0;
}
