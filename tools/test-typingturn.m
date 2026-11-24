// test-typingturn.m -- see test-typingturn.sh. The desktop's typing window told of a turn (1.8.8.2): the real code cut out of statusbar/Desktop.h
// (DMDesktopRenameHost and the window's methods it adds: DMDesktopRenameHitTest, DMDesktopRenameYes, DMDesktopRenameLayout, DMDesktopTurnArgs,
// DMDesktopRenameTurned, and in DEBUG DMDesktopTurnDockNote), run on the Mac (Mac Catalyst, headless) on a stand-in of SpringBoard's
// SBMainScreenActiveInterfaceOrientationWindow as read in the 17.6.1 and 18.2 decompiles (-initWithRole:debugName:, the active orientation
// observer's -activeInterfaceOrientationDidChangeToOrientation:willAnimateWithDuration:fromOrientation:). The fit itself (DMDesktopRenameFit,
// unchanged since 1.8.8.1) is counted here, not run.
//  T_SHAPE 0: SpringBoard's call as read: the typing window answers it, SpringBoard's own handling first with the same arguments, then the fit
//    at once, in the window's next layout pass and on the next main-queue turn; a hidden typing window only SpringBoard's;
//  T_SHAPE 1: the call of another shape (a float for an orientation), 2: no such call: not answered, a line says which, the fit as before (its
//    own layout pass only).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL DMTestFlag(const char *path) { (void)path; return NO; }
static NSArray<UIWindow *> *DMAllWindows(void) { return @[]; }
static BOOL DMViewNearlyScreen(UIView *v) { (void)v; return NO; }
static void DMSnapInvalidate(void) {}
#define DM_FEATURE_MARK(name) do { } while (0)
static int gFits = 0;
static void DMDesktopRenameFit(void);   // (counted below, as the real one only for the shown window)
static CGFloat DMDesktopRenameLevel(void) { return 26.0; }
static BOOL DMDesktopTypingWindowCan(void) { return objc_getClass("SBMainScreenActiveInterfaceOrientationWindow") != nil; }
// (1.8.8.3: the turn's time and iPadOS 15's edit menu watch, Desktop.h DMDesktopEditMenuFollow's; stand-ins here)
static CFTimeInterval gDesktopTurnToldAt __attribute__((unused)) = 0, gDesktopEditMenuHidAt __attribute__((unused)) = 0;
static int gEditMenuWatches __attribute__((unused)) = 0;
static void DMDesktopEditMenuWatch(void) { gEditMenuWatches++; }

static int gBaseCalls __attribute__((unused)) = 0, gFitsAtBase __attribute__((unused)) = -1;   // (what SpringBoard's stand-in was called with; T_SHAPE 2 has none)
static long long gBaseTo __attribute__((unused)) = 0, gBaseFrom __attribute__((unused)) = 0; static double gBaseDuration __attribute__((unused)) = 0;
@interface SBMainScreenActiveInterfaceOrientationWindow : UIWindow
- (instancetype)initWithRole:(NSString *)role debugName:(NSString *)name;
@end
@implementation SBMainScreenActiveInterfaceOrientationWindow
- (instancetype)initWithRole:(NSString *)role debugName:(NSString *)name { (void)role; (void)name; return [super initWithFrame:CGRectMake(0, 0, 768, 1024)]; }
#if T_SHAPE == 0
- (void)activeInterfaceOrientationDidChangeToOrientation:(long long)to willAnimateWithDuration:(double)d fromOrientation:(long long)from {
    gBaseCalls++; gFitsAtBase = gFits; gBaseTo = to; gBaseDuration = d; gBaseFrom = from;
}
#elif T_SHAPE == 1
- (void)activeInterfaceOrientationDidChangeToOrientation:(long long)to willAnimateWithDuration:(double)d fromOrientation:(float)from {
    gBaseCalls++; gBaseTo = to; gBaseDuration = d; gBaseFrom = (long long)from;
}
#endif
@end
#include "tt-desk.inc"   // (Desktop.h: the typing window, its methods, the turn)
static void DMDesktopRenameFit(void) { if (!gDesktopRenameWindow || gDesktopRenameWindow.hidden) return; gFits++; }

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static int LogCount(NSString *part) { int n = 0; for (NSString *l in gLog) if ([l containsString:part]) n++; return n; }

int main(int argc, char **argv) {
    @autoreleasepool {
        (void)argc; (void)argv;
        SEL turn = NSSelectorFromString(@"activeInterfaceOrientationDidChangeToOrientation:willAnimateWithDuration:fromOrientation:");
        UIView *host = DMDesktopRenameHost();
        UIWindow *w = gDesktopRenameWindow;
        Class sub = objc_getClass("MSBDesktopRenameWindow"), base = objc_getClass("SBMainScreenActiveInterfaceOrientationWindow");
        Method mine = sub ? class_getInstanceMethod(sub, turn) : NULL, theirs = class_getInstanceMethod(base, turn);
        Check(host && w && [w isKindOfClass:sub] && !w.hidden && host.superview == w, @"the typing window made (SpringBoard's orientation window class), shown at its level, its container in it");
#if T_SHAPE == 0
        Check(mine && mine != theirs && !strcmp(method_getTypeEncoding(mine), method_getTypeEncoding(theirs)) && LogCount(@"turn call is") == 0,
              @"SpringBoard's turn call of the shape read (v@:qdq): the typing window answers it itself, with SpringBoard's type encoding");
        [w layoutIfNeeded]; [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];   // (settled first)
        int fits0 = gFits;
        ((void (*)(id, SEL, long long, double, long long))objc_msgSend)(w, turn, 3, 0.4, 1);
        BOOL superFirst = gBaseCalls == 1 && gFitsAtBase == fits0 && gBaseTo == 3 && gBaseFrom == 1 && fabs(gBaseDuration - 0.4) < 1e-9;
        Check(superFirst, @"  ... at a turn: SpringBoard's own handling first, once, with the same arguments (to 3, 0.4 s, from 1)");
        Check(gFits == fits0 + 1 && LogCount(@"[desktop] the typing window is told of the turn 1 -> 3") == 1, @"  ... then the container fitted again at once, its line said");
        int fits1 = gFits;
        [w layoutIfNeeded];
        Check(gFits == fits1 + 1, @"  ... again in the window's next layout pass (asked for at the turn: the window keeps its bounds through a turn)");
        int fits2 = gFits;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(gFits == fits2 + 1, @"  ... and on the next main-queue turn (SpringBoard's turn applied by then)");
        w.hidden = YES; int fits3 = gFits, base3 = gBaseCalls;
        ((void (*)(id, SEL, long long, double, long long))objc_msgSend)(w, turn, 1, 0.4, 3);
        [w layoutIfNeeded];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(gBaseCalls == base3 + 1 && gFits == fits3, @"  ... hidden (no typing): only SpringBoard's own handling, no fit");
        w.hidden = NO;
        UIView *again = DMDesktopRenameHost();
        Check(again == host && class_getInstanceMethod(object_getClass(w), turn) == mine, @"  ... shown again for the next typing: the same window and container, the method once");
#else
        Check((!mine || mine == theirs) && LogCount(T_SHAPE == 1 ? @"rename window: SpringBoard's turn call is v@:qdf here: fitted in its own layout pass only" : @"rename window: SpringBoard's turn call is missing here: fitted in its own layout pass only") == 1,
              T_SHAPE == 1 ? @"SpringBoard's turn call of another shape: not answered by the typing window, a line says which (its own layout pass only, as before)"
                           : @"no such call here: not answered, a line says so (as before)");
        int fits0 = gFits;
        [w setNeedsLayout]; [w layoutIfNeeded];
        Check(gFits == fits0 + 1, @"  ... its own layout pass still fits the container (1.8.8.1's way)");
#endif
        printf("test-typingturn (shape %d, %s): %d checks, %d fail\n", T_SHAPE,
#if DEBUG
               "DEBUG",
#else
               "release",
#endif
               gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
