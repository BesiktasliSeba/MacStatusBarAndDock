// test-ownhome.m -- Mac test of our own Home's mark (statusbar/StatusBar.x DMOwnHome, DMHomeIsOurs): Home Minimizes Windows takes a Home of ours --
// Minimize, Aerial's way into a window -- for none of the user's. The code as built: test-homeaway.sh cuts it out of StatusBar.x into ownhome-gen.h;
// the clock is a stand-in. Marked while it runs and for a second from its start, and the mark ends whatever happens in it (regression 1.8.4 F3; the
// review of the fixes, L1: a window counted from the end held a user's Home a second after ours, and an exception left every later Home "ours").
#import <Foundation/Foundation.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static double gNow = 1000.0;
static double CACurrentMediaTime(void) { return gNow; }
#include "ownhome-gen.h"   // (the code as built)
int main(void) { @autoreleasepool {
    __block BOOL inside = NO;
    Expect(!DMHomeIsOurs(), @"no Home of ours yet: a Home is the user's");
    DMOwnHome(^{ gNow += 0.4; inside = DMHomeIsOurs(); });   // (our Home takes 0.4 s, SpringBoard's press inside it)
    Expect(inside, @"while our Home runs: ours (SpringBoard's press inside it)");
    gNow += 0.3;
    Expect(DMHomeIsOurs(), @"0.7 s from its start: still ours (SpringBoard's press right after it)");
    gNow += 0.5;
    Expect(!DMHomeIsOurs(), @"1.2 s from its start, 0.8 s after its end: the user's again (the second counts from the start: L1)");
    gNow += 5.0;
    @try { DMOwnHome(^{ gNow += 0.1; @throw [NSException exceptionWithName:@"test" reason:@"a throw inside our Home" userInfo:nil]; }); } @catch (NSException *e) { }
    gNow += 1.5;
    Expect(!DMHomeIsOurs(), @"an exception inside it: the mark ends with it, a Home 1.5 s later is the user's (L1: it stayed ours for good)");
    DMOwnHome(^{ });
    Expect(DMHomeIsOurs(), @"  ... and the next Home of ours is marked again");
    printf("%s: %d checks, %d failed\n", fails ? "test-ownhome FAILED" : "test-ownhome: all pass", checks, fails);
    return fails ? 1 : 0;
} }
