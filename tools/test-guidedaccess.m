// Mac test (Mac Catalyst: UIKit on the Mac) of the Guided Access answer every part of ours asks (common/GuidedAccess.h, 1.3.7, audit M-7), and of
// the alert rule built on it (common/AlertQueue.h: alerts wait while a session runs). Built twice by test-guidedaccess.sh:
//  - WITH_SB=1: the binary exports SpringBoard's names (SBGuidedAccessIsActive, SBGuidedAccessActivationChangedNotification), as SpringBoard does:
//    the answer must be that function's, and the change block must run for SpringBoard's notification and for UIKit's.
//  - WITH_SB=0, WITH_LISTENER=1: no function, but SpringBoard's listener class (SBGuidedAccessListener): its flag is the answer.
//  - WITH_SB=0, WITH_LISTENER=0: neither (another process): UIKit's public answer (NO here), no crash.
#import <UIKit/UIKit.h>
#include "../common/GuidedAccess.h"
#include "../common/AlertQueue.h"

static int fails = 0, checks = 0;
static void ok(BOOL c, NSString *what) { checks++; if (!c) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static BOOL gFake = NO;

#if WITH_SB
__attribute__((visibility("default"), used)) BOOL SBGuidedAccessIsActive(void) { return gFake; }
__attribute__((visibility("default"), used)) NSString *const SBGuidedAccessActivationChangedNotification = @"SBGuidedAccessActivationChangedNotification";
#endif
#if WITH_LISTENER
@interface SBGuidedAccessListener : NSObject
+ (instancetype)sharedGuidedAccessListener;
- (BOOL)isGuidedAccessActive;
@end
@implementation SBGuidedAccessListener
+ (instancetype)sharedGuidedAccessListener { static SBGuidedAccessListener *l; static dispatch_once_t o; dispatch_once(&o, ^{ l = [SBGuidedAccessListener new]; }); return l; }
- (BOOL)isGuidedAccessActive { return gFake; }
@end
#endif

static void spin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

int main(void) {
    @autoreleasepool {
        gFake = NO;
        ok(!MSBDGuidedAccessActive(), @"inactive: NO");
        ok(!MSBDAlertLockedOrCovered(), @"inactive: alerts may show (not locked, no session)");
#if WITH_SB || WITH_LISTENER
        gFake = YES;
        ok(MSBDGuidedAccessActive(), @"active: YES (SpringBoard's own answer)");
        ok(MSBDAlertLockedOrCovered(), @"active: alerts wait");
        gFake = NO;
        ok(!MSBDGuidedAccessActive(), @"inactive again: NO");
#else
        gFake = YES;
        ok(!MSBDGuidedAccessActive(), @"no SpringBoard answer: UIKit's (NO on the Mac)");
#endif
        __block int calls = 0;
        MSBDGuidedAccessObserve(^{ calls++; });
        [[NSNotificationCenter defaultCenter] postNotificationName:UIAccessibilityGuidedAccessStatusDidChangeNotification object:nil];
        spin();
        ok(calls == 1, [NSString stringWithFormat:@"UIKit's notification runs the block once (%d)", calls]);
#if WITH_SB
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SBGuidedAccessActivationChangedNotification" object:nil];
        spin();
        ok(calls == 2, [NSString stringWithFormat:@"SpringBoard's notification runs the block too (%d)", calls]);
#endif
        MSBDGuidedAccessObserve(nil);   // (nothing registered, no crash)
        ok(YES, @"nil block ignored");
    }
    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
}
