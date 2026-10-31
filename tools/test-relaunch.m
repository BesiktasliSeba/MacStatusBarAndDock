// Mac test of common/Relaunch.h (1.7.4 item 6): our Respring's request where SpringBoard may not start sbreload (iPadOS 18) is the one sbreload
// sends -- an SBSRelaunchAction with reason "respring" and options 5 (the render server too, a fade to black), one action in the set, through
// FBSSystemService's -sendActions:withResult: with no result block -- and nothing is sent (no crash, NO) where a class or a method is missing.
// Built four ways by test-relaunch.sh: stand-ins for the two classes with everything (WITH_ACTION=1 WITH_SEND=1), with no action factory, with a
// service that cannot send, and with neither class (another iPadOS, or the Mac itself).
#import <Foundation/Foundation.h>
#include "../common/Relaunch.h"
static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

__attribute__((unused)) static NSString *gReason; __attribute__((unused)) static NSUInteger gOptions = 99; __attribute__((unused)) static id gURL = @"unset";
__attribute__((unused)) static NSSet *gSent; __attribute__((unused)) static id gResult = @"unset"; static int gSends = 0;
#if WITH_CLASSES
@interface SBSRelaunchAction : NSObject @end
@implementation SBSRelaunchAction
#if WITH_ACTION
+ (id)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)url { gReason = reason; gOptions = options; gURL = url; return [self new]; }
#endif
@end
@interface FBSSystemService : NSObject @end
@implementation FBSSystemService
+ (instancetype)sharedService { static FBSSystemService *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [FBSSystemService new]; }); return s; }
#if WITH_SEND
- (void)sendActions:(NSSet *)actions withResult:(id)result { gSent = actions; gResult = result; gSends++; }
#endif
@end
#endif

int main(void) {
    @autoreleasepool {
        BOOL sent = MSBDRelaunchLikeSbreload();
#if WITH_CLASSES && WITH_ACTION && WITH_SEND
        CHECK(sent, "both classes as on iPadOS 15-18: sent");
        CHECK([gReason isEqualToString:@"respring"], "the reason sbreload gives: \"respring\" (got %s)", gReason.UTF8String);
        CHECK(gOptions == 5, "sbreload's options: 5 = the render server restarted (1) + a fade to black (4) (got %lu)", (unsigned long)gOptions);
        CHECK(gURL == nil, "no target URL");
        CHECK(gSends == 1 && gSent.count == 1 && [[gSent anyObject] isKindOfClass:objc_getClass("SBSRelaunchAction")], "one set with the one action, sent once");
        CHECK(gResult == nil, "no result block (as sbreload)");
        gSends = 0;
        CHECK(MSBDSendRelaunchAction(@"RestartRenderServer", kMSBDRelaunchFadeToBlack) && gOptions == 4 && [gReason isEqualToString:@"RestartRenderServer"] && gSends == 1,
              "any reason and options pass through unchanged (our Settings pages' request: 4)");
#else
        CHECK(!sent, "a class or a method missing: NO");
        CHECK(gSends == 0, "nothing sent");
#endif
    }
    printf("test-relaunch (classes %d, action %d, send %d): %d passed, %d failed\n", WITH_CLASSES, WITH_ACTION, WITH_SEND, passes, fails);
    return fails ? 1 : 0;
}
