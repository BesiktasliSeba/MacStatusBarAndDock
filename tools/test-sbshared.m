// test-sbshared.m -- Mac test of how SpringBoard's controllers are asked for (common/SBShared.h, used by common/CCController.h): 1.8.0.1. A shared
// instance is never made by us: the stand-in classes below record whether the making call ran. SpringBoard crashed at its start on the iPad 2
// (16.7.7) when our constructor asked +[SBControlCenterController sharedInstance] before SpringBoard's launch had made its main workspace.
#import <Foundation/Foundation.h>
#include "../common/SBShared.h"
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static int gMade = 0;            // (how often a making call ran)
static id gThere = nil;          // (what a class "made by SpringBoard" answers)
static int gAskedWithNo = 0, gAskedWithYes = 0;

@interface FakeIfExists : NSObject @end   // (16.7.7's SBControlCenterController: all three calls)
@implementation FakeIfExists
+ (id)sharedInstanceIfExists { return gThere; }
+ (id)_sharedInstanceCreatingIfNeeded:(bool)make { if (make) { gAskedWithYes++; gMade++; return [NSObject new]; } gAskedWithNo++; return gThere; }
+ (id)sharedInstance { gMade++; return gThere ?: [NSObject new]; }
@end
@interface FakeCreatingOnly : NSObject @end   // (no +sharedInstanceIfExists: the creating call with NO)
@implementation FakeCreatingOnly
+ (id)_sharedInstanceCreatingIfNeeded:(bool)make { if (make) { gAskedWithYes++; gMade++; return [NSObject new]; } gAskedWithNo++; return gThere; }
+ (id)sharedInstance { gMade++; return [NSObject new]; }
@end
@interface FakeSharedOnly : NSObject @end   // (neither: +sharedInstance alone)
@implementation FakeSharedOnly
+ (id)sharedInstance { gMade++; return [NSObject new]; }
@end
@interface FakeOddIfExists : NSObject @end   // (an +sharedInstanceIfExists of another shape: not ours to call)
@implementation FakeOddIfExists
+ (id)sharedInstanceIfExists:(id)x { gMade++; return [NSObject new]; }
+ (id)sharedInstance { gMade++; return [NSObject new]; }
@end
static id gWorkspace = nil;   // (SpringBoard's main workspace, as the stand-in SBMainWorkspace answers)
static id WorkspaceIfExists(id self, SEL _cmd) { return gWorkspace; }
static void Reset(void) { gMade = 0; gThere = nil; gAskedWithNo = gAskedWithYes = 0; }

int main(void) {
    @autoreleasepool {
        Reset();
        Expect(MSBDSBSharedIfExists([FakeIfExists class]) == nil && gMade == 0, @"not made yet (our constructor, before SpringBoard's launch): nil, and never made by us -- the iPad 2's crash");
        gThere = [NSObject new];
        Expect(MSBDSBSharedIfExists([FakeIfExists class]) == gThere && gMade == 0, @"  ... made by SpringBoard: that one, still never a making call");
        Reset();
        Expect(MSBDSBSharedIfExists([FakeCreatingOnly class]) == nil && gMade == 0 && gAskedWithNo == 1 && gAskedWithYes == 0, @"no +sharedInstanceIfExists: +_sharedInstanceCreatingIfNeeded:NO");
        gThere = [NSObject new];
        Expect(MSBDSBSharedIfExists([FakeCreatingOnly class]) == gThere && gMade == 0, @"  ... made by SpringBoard: that one");
        Reset();
        Expect(MSBDSBSharedIfExists([FakeSharedOnly class]) == nil && gMade == 0, @"+sharedInstance alone, no main workspace class: nil, not made");
        Class ws = objc_allocateClassPair([NSObject class], "SBMainWorkspace", 0);
        class_addMethod(object_getClass(ws), NSSelectorFromString(@"sharedInstanceIfExists"), (IMP)WorkspaceIfExists, "@16@0:8");
        objc_registerClassPair(ws);
        Expect(MSBDSBSharedIfExists([FakeSharedOnly class]) == nil && gMade == 0, @"  ... SpringBoard's main workspace not made yet (its launch to come): nil, not made");
        gWorkspace = [NSObject new];
        Expect(MSBDSBSharedIfExists([FakeSharedOnly class]) != nil && gMade == 1, @"  ... once SpringBoard's launch made its workspace: +sharedInstance (what its -init asks for is there)");
        Reset();
        Expect(MSBDSBSharedIfExists([FakeOddIfExists class]) != nil && gMade == 1, @"an +sharedInstanceIfExists of another shape is not called (only the plain one), the workspace there: +sharedInstance");
        gWorkspace = nil; Reset();
        Expect(MSBDSBSharedIfExists([FakeOddIfExists class]) == nil && gMade == 0, @"  ... and with the workspace not made: nil");
        Expect(MSBDSBSharedIfExists(Nil) == nil, @"no such class: nil");
        Expect(MSBDSBClassMethodIs([FakeIfExists class], NSSelectorFromString(@"_sharedInstanceCreatingIfNeeded:"), "@@:B")
               && !MSBDSBClassMethodIs([FakeIfExists class], NSSelectorFromString(@"sharedInstanceIfExists"), "@@:B")
               && !MSBDSBClassMethodIs([FakeIfExists class], NSSelectorFromString(@"noSuchMethod"), "@@:"), @"the types are compared without their offsets (SpringBoard's \"@20@0:8B16\" is \"@@:B\")");
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
