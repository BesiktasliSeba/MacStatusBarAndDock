// test-popupguard.m -- Mac test of the LNPopupController race guard (common/PopupGuard.h, installed by appbridge/AppBridge.x MABInstallPopupGuard;
// 1.8.8.1 B68). Built by test-popupguard.sh in two forms:
//   scenarios (GUARD_INC = MacAppBridge's guard section cut out of AppBridge.x, any tree): a stand-in for the library as Sileo 2.5.1 and Zebra 1.1.36
//     carry it -- the designated present (openPopup:) does the work, the 3-argument present only forwards to it, the dismiss's late "finished" step
//     hides the bar -- and the calls each app makes: Zebra the designated present, Sileo the 3-argument one. "nolib" runs them with no library
//     class in the process (no guard: the race shows).
//   units (UNITS): PopupGuard.h's own rules: which present a class gets, the argument types it is known by.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
#include <string.h>

static int fails = 0, checks = 0;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
// MSHookMessageEx as substrate does it for a method the class has itself
static void MSHookMessageEx(Class c, SEL s, IMP imp, IMP *orig) {
    Method m = class_getInstanceMethod(c, s);
    if (!m) { if (orig) *orig = NULL; return; }
    IMP old = method_setImplementation(m, imp);
    if (orig) *orig = old;
}

// ---- the stand-in for the library (as the UIViewController category Sileo and Zebra carry) ----
static const double kAnim = 0.20;   // the bar's animation
@interface FakeVC : NSObject
@property BOOL barShown, lastOpen;
@property int presents, dismisses;
@property (strong) NSMutableArray<NSString *> *order;
@end
@implementation FakeVC
- (instancetype)init { if ((self = [super init])) _order = [NSMutableArray array]; return self; }
- (void)presentPopupBarWithContentViewController:(id)content openPopup:(BOOL)open animated:(BOOL)animated completion:(void (^)(void))completion {
    self.presents++; self.barShown = YES; self.lastOpen = open; [self.order addObject:open ? @"present+open" : @"present"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAnim * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self.order addObject:@"presented"]; if (completion) completion(); });
}
- (void)presentPopupBarWithContentViewController:(id)content animated:(BOOL)animated completion:(void (^)(void))completion {
    // (the library's 3-argument present: only a forward to the designated one, through the runtime)
    ((void (*)(id, SEL, id, BOOL, BOOL, id))objc_msgSend)(self, @selector(presentPopupBarWithContentViewController:openPopup:animated:completion:), content, NO, animated, completion);
}
- (void)dismissPopupBarAnimated:(BOOL)animated completion:(void (^)(void))completion {
    self.dismisses++; [self.order addObject:@"dismiss"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAnim * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.barShown = NO;   // (the late "dismiss finished" step: hides the bar, also one presented meanwhile -- the library's overlap)
        [self.order addObject:@"dismissed"];
        if (completion) completion();
    });
}
@end
// A class whose designated present has other argument types (a library copy that changed it): only its 3-argument one is known
@interface OddVC : NSObject @end
@implementation OddVC
- (void)presentPopupBarWithContentViewController:(id)content openPopup:(int)open animated:(BOOL)animated completion:(void (^)(void))completion {}
- (void)presentPopupBarWithContentViewController:(id)content animated:(BOOL)animated completion:(void (^)(void))completion {}
- (void)dismissPopupBarAnimated:(BOOL)animated completion:(void (^)(void))completion {}
@end
@interface BareVC : NSObject @end
@implementation BareVC
- (void)dismissPopupBarAnimated:(BOOL)animated completion:(void (^)(void))completion {}
@end

static void Spin(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static void After(double s, void (^b)(void)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }
static void Present4(FakeVC *v, BOOL open, void (^c)(void)) { [v presentPopupBarWithContentViewController:nil openPopup:open animated:YES completion:c]; }
static void Present3(FakeVC *v, void (^c)(void)) { [v presentPopupBarWithContentViewController:nil animated:YES completion:c]; }
static void Dismiss(FakeVC *v, void (^c)(void)) { [v dismissPopupBarAnimated:YES completion:c]; }

#ifdef UNITS
#include "PopupGuard.h"
int main(void) {
    @autoreleasepool {
        Check(MSBDPopupTypesAre("v40@0:8@16B24B28@?32", "v@:@BB@?"), @"types: the designated present as arm64 encodes it is known");
        Check(MSBDPopupTypesAre("v32@0:8@16c24c28@?32", "v@:@BB@?"), @"types: ... and as x86_64 encodes BOOL ('c')");
        Check(!MSBDPopupTypesAre("v40@0:8@16i24B28@?32", "v@:@BB@?"), @"types: an int where a BOOL was: not known");
        Check(!MSBDPopupTypesAre("v40@0:8@16B24B28", "v@:@BB@?"), @"types: one argument fewer: not known");
        Check(!MSBDPopupTypesAre("v40@0:8@16B24B28@?32@40", "v@:@BB@?"), @"types: one argument more: not known");
        Check(!MSBDPopupTypesAre(NULL, "v@:@BB@?"), @"types: no types: not known");
        Check(MSBDPopupPresentArgs([FakeVC class]) == 4, @"the library as Sileo and Zebra carry it: the designated present (4 arguments) is taken");
        Check(MSBDPopupPresentArgs([OddVC class]) == 3, @"a copy whose designated present has other types: its 3-argument present is taken");
        Check(MSBDPopupPresentArgs([BareVC class]) == 0, @"no present it knows: nothing is taken");
        Check(MSBDPopupDismissKnown([FakeVC class]) && MSBDPopupDismissKnown([BareVC class]), @"the dismiss is known by its types");
        Check(!MSBDPopupGuardInstall([BareVC class]), @"no present it knows: no guard installed (nothing hooked)");
        Check(!MSBDPopupGuardInstall(Nil), @"no class: no guard");
    }
    printf("test-popupguard units: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
#else
// MacAppBridge's guard section, as cut out of AppBridge.x (test-popupguard.sh): UIViewController is the stand-in here
#define UIViewController FakeVC
static void MABLog(NSString *s) { (void)s; }
#include GUARD_INC
#undef UIViewController

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL nolib = argc > 1 && strcmp(argv[1], "nolib") == 0;
        if (!nolib) objc_registerClassPair(objc_allocateClassPair([NSObject class], "LNPopupBar", 0));   // (an app that contains the library)
        MABInstallPopupGuard();
        const char *tag = nolib ? "no library class (no guard)" : "guard";
        // Z1: Zebra's queue: the bar dismissed (a cleared queue, or an in-between size) and presented again 50 ms later, with the designated present
        {
            FakeVC *v = [FakeVC new]; v.barShown = YES; __block int dc = 0, pc = 0;
            Dismiss(v, ^{ dc++; });
            After(0.05, ^{ Present4(v, NO, ^{ pc++; }); });
            Spin(1.0);
            Check(v.barShown, [NSString stringWithFormat:@"%s, Zebra (designated present): dismiss then present 50 ms later: the bar is shown at the end (order %@)", tag, [v.order componentsJoinedByString:@" "]]);
            Check(dc == 1 && pc == 1, [NSString stringWithFormat:@"%s, Zebra: each completion ran once (dismiss %d, present %d)", tag, dc, pc]);
        }
        // Z2: Zebra's openQueue:YES (the queue opened at once): the open flag reaches the library
        {
            FakeVC *v = [FakeVC new]; v.barShown = YES;
            Dismiss(v, nil); After(0.05, ^{ Present4(v, YES, nil); });
            Spin(1.0);
            Check(v.barShown && v.lastOpen, [NSString stringWithFormat:@"%s, Zebra: dismiss then present with the popup open: shown, and open (order %@)", tag, [v.order componentsJoinedByString:@" "]]);
        }
        // S1: Sileo's queue (the 1.8.8 case): the 3-argument present
        {
            FakeVC *v = [FakeVC new]; v.barShown = YES; __block int pc = 0;
            Dismiss(v, nil); After(0.05, ^{ Present3(v, ^{ pc++; }); });
            Spin(1.0);
            Check(v.barShown, [NSString stringWithFormat:@"%s, Sileo (3-argument present): dismiss then present 50 ms later: the bar is shown at the end (order %@)", tag, [v.order componentsJoinedByString:@" "]]);
            Check(v.presents == 1 && pc == 1, [NSString stringWithFormat:@"%s, Sileo: presented once, its completion once (presents %d, completion %d)", tag, v.presents, pc]);
        }
        // C1: three requests in a row (present, dismiss, present): the latest wins after the first finishes, every completion once
        {
            FakeVC *v = [FakeVC new]; __block int a = 0, b = 0, c = 0;
            Present4(v, NO, ^{ a++; }); After(0.02, ^{ Dismiss(v, ^{ b++; }); }); After(0.04, ^{ Present4(v, NO, ^{ c++; }); });
            Spin(1.2);
            Check(v.barShown && a == 1 && b == 1 && c == 1, [NSString stringWithFormat:@"%s, present, dismiss, present within 40 ms: shown, every completion once (%d %d %d; order %@)", tag, a, b, c, [v.order componentsJoinedByString:@" "]]);
        }
        // P1: nothing overlapping: as the library does it (a present, later a dismiss)
        {
            FakeVC *v = [FakeVC new];
            Present4(v, NO, nil); Spin(0.5); Dismiss(v, nil); Spin(0.5);
            Check(!v.barShown && v.presents == 1 && v.dismisses == 1, [NSString stringWithFormat:@"%s, a present, then a dismiss 0.5 s later: as the library does it (order %@)", tag, [v.order componentsJoinedByString:@" "]]);
        }
        // B1: off the main thread: passed through at once (as before)
        {
            FakeVC *v = [FakeVC new]; v.barShown = YES;
            Dismiss(v, nil);
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(0, 0), ^{ Present4(v, NO, nil); dispatch_semaphore_signal(sem); });
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            Check(v.presents == 1, [NSString stringWithFormat:@"%s, a present off the main thread runs at once (presents %d)", tag, v.presents]);
            Spin(0.5);
        }
    }
    printf("test-popupguard scenarios: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
#endif
