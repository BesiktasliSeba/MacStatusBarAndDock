// test-autolocklong.m -- Mac test of the longer Auto-Lock times' SpringBoard side (macsettings/AutoLockLongest.h, 1.7.2 item 18): which results of
// SpringBoard's own step are given our time back. SpringBoard takes any Auto-Lock over its MAX_TOTAL_INTERVAL (3600 s on 15.6.1) for Never and
// leaves the timer's total at DBL_MAX; our 2 hours (7200 s) was Never.
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
    }
    printf("test-autolocklong: %d/%d passed\n", gN - gFail, gN);
    return gFail ? 1 : 0;
}
