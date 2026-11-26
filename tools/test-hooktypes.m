// test-hooktypes.m -- Mac test of common/HookTypes.h as built (test-hooktypes.sh): the type string's reduction and the check a hook group
// passes before its %init. Its stand-in classes carry the shapes iPadOS's methods have (read from the IPSWs, tools/hooktypes-ipados.txt).
// Built with -D__OBJC_BOOL_IS_BOOL=1 so BOOL encodes as on iPadOS ("B").
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include HT_HEADER
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static NSString *Bare(const char *e) { char b[160]; return MSBDHookBareTypes(e, b, sizeof b) ? @(b) : nil; }

// SpringBoard's controller as 15.6.1-18.5 have it ("v40@0:8@16q24@32": the alpha an NSNumber), and the Lock Screen manager
@interface HTSBDashBoardStatusBarController : NSObject
- (void)setStatusBarAlpha:(NSNumber *)alpha style:(long long)style legibilitySettings:(id)ls;
- (void)setStatusBarHidden:(BOOL)hidden forReason:(id)reason;
@end
@implementation HTSBDashBoardStatusBarController
- (void)setStatusBarAlpha:(NSNumber *)alpha style:(long long)style legibilitySettings:(id)ls {}
- (void)setStatusBarHidden:(BOOL)hidden forReason:(id)reason {}
@end
@interface HTSBLockScreenManager : NSObject - (void)lockUIFromSource:(int)source withOptions:(id)options completion:(void (^)(void))completion; @end
@implementation HTSBLockScreenManager - (void)lockUIFromSource:(int)source withOptions:(id)options completion:(void (^)(void))completion {} @end
@interface HTView : NSObject - (void)setAlpha:(CGFloat)a; @end
@implementation HTView - (void)setAlpha:(CGFloat)a {} @end
@interface HTLabel : HTView @end   // (inherits -setAlpha:, as SBUICallToActionLabel does UIView's)
@implementation HTLabel @end
// the shape the test build's hook was written for
@interface HTOldHook : NSObject - (void)setStatusBarAlpha:(double)alpha style:(long long)style legibilitySettings:(id)ls; @end
@implementation HTOldHook - (void)setStatusBarAlpha:(double)alpha style:(long long)style legibilitySettings:(id)ls {} @end

int main(void) { @autoreleasepool {
    Expect(strcmp(@encode(BOOL), "B") == 0, @"(BOOL encodes as on iPadOS)");
    // ---- the reduction ----
    Expect([Bare("v40@0:8@16q24@32") isEqualToString:@"v@:@q@"], @"18.5's -setStatusBarAlpha:style:legibilitySettings: -> v@:@q@");
    Expect([Bare("v36@0:8i16@20@?28") isEqualToString:@"v@:i@@"], @"a block argument (@?) counts as an object: -lockUIFromSource:withOptions:completion: -> v@:i@@");
    Expect([Bare("v28@0:8B16@20") isEqualToString:@"v@:B@"] && [Bare("v28@0:8B16B20i24") isEqualToString:@"v@:BBi"], @"BOOL and int arguments kept apart");
    Expect([Bare("{CGPoint=dd}84@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16d48B56{CGSize=dd}60o^B76") isEqualToString:@"{dd}@:{{dd}{dd}}dB{dd}^B"], @"struct names, offsets and an out qualifier dropped");
    Expect([Bare("v24@0:8@\"NSNumber\"16") isEqualToString:@"v@:@"] && [Bare("v20@0:8r*16") isEqualToString:@"v@:*"], @"a quoted class name and a const qualifier dropped");
    Expect([Bare("v24@0:8^{x=[4c]}16") isEqualToString:@"v@:^{[4c]}"] && ![Bare("v24@0:8^{x=[4c]}16") isEqualToString:Bare("v24@0:8^{x=[8c]}16")] && [Bare("v28@0:8[12i]16") isEqualToString:@"v@:[12i]"], @"an array's length kept (only the offsets dropped)");
    char tiny[4];
    Expect(!MSBDHookBareTypes("v40@0:8@16q24@32", tiny, sizeof tiny) && tiny[0] == 0 && !MSBDHookBareTypes(NULL, tiny, sizeof tiny), @"too long for the buffer, or no string: refused, empty");
    Method mo = class_getInstanceMethod([HTOldHook class], @selector(setStatusBarAlpha:style:legibilitySettings:));
    Method mn = class_getInstanceMethod([HTSBDashBoardStatusBarController class], @selector(setStatusBarAlpha:style:legibilitySettings:));
    Expect([Bare(method_getTypeEncoding(mo)) isEqualToString:@"v@:dq@"] && [Bare(method_getTypeEncoding(mn)) isEqualToString:@"v@:@q@"], @"the test build's declaration (a double alpha) and iPadOS's (an NSNumber) differ");
    // ---- the check before a group's %init ----
    MSBDHookSig ours[] = {
        {"HTSBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:@q@"},
        {"HTSBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:B@"},
        {"HTSBLockScreenManager", "lockUIFromSource:withOptions:completion:", "v@:i@@"},
        {"HTLabel", "setAlpha:", "v@:d"},
    };
    Expect(MSBD_HOOK_SIGS_WRONG(ours) == nil, @"a group written for iPadOS's types goes in (an inherited method checked by the class that has it)");
    MSBDHookSig old[] = { {"HTSBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:dq@"} };
    NSString *w = MSBD_HOOK_SIGS_WRONG(old);
    Expect(w != nil && [w containsString:@"v40@0:8@16q24@32"] && [w containsString:@"v@:dq@"], [NSString stringWithFormat:@"the test build's hook (a double alpha) is kept out where iPadOS passes an NSNumber: %@", w]);
    MSBDHookSig gone[] = { {"HTNoSuchClass", "setStatusBarAlpha:style:legibilitySettings:", "v@:dq@"}, {"HTSBDashBoardStatusBarController", "noSuchMethod:", "v@:d"} };
    Expect(MSBD_HOOK_SIGS_WRONG(gone) == nil, @"a class or method that is not there is Logos's case (nothing hooked for it): not a refusal");
    MSBDHookSig later[] = { {"HTSBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:B@"}, {"HTSBLockScreenManager", "lockUIFromSource:withOptions:completion:", "v@:q@@"} };
    w = nil;
    BOOL ok = MSBDHookGroupTypesOK(later, 2, "test", "HTGroup", &w);
    Expect(!ok && [w containsString:@"lockUIFromSource:withOptions:completion:"], @"one method of a group with other types (long long where iPadOS has int) keeps the whole group out, and says which");
    w = @"x"; ok = MSBDHookGroupTypesOK(ours, 4, "test", "HTGroup", &w);
    Expect(ok && w == nil, @"a group that matches: YES, nothing to say");
    printf("test-hooktypes (HookTypes.h): %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
} }
