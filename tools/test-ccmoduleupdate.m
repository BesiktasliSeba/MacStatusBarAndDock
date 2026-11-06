// test-ccmoduleupdate.m -- Mac test of a module's own size change in our 15-17 Control Center (1.8.2.1, plans/v1821-uptime.md). It runs the code as built:
// test-ccmoduleupdate.sh cuts the panel's controller (DMCCPPanelController, statusbar/CCPanel.h) and DMCCTypes (StatusBar.x) out of the sources into
// ccmoduleupdate-gen.h, and this file gives them stand-ins for UIKit and Apple's Control Center: the overlay's children as 15.6.1, 16.7.7 and 17.5.1 have them
// (Apple's sensor list, status label and grid, then ours: the ccgiveback dumps), and Uptime's Module Size action as UptimeModule 1.0.1 does it
// (-[UptimeModuleContentViewController setModuleSize:]): the size saved, then Apple's -_updateModuleControllers sent, unchecked, to
// presentingViewController.childViewControllers.lastObject. On 1.8.2 that was our controller, which did not answer it: SpringBoard aborted (M1 15.6.1).
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's controller, as far as these read it -----------------------------------------------------------------------------------------------
@interface UIViewController : NSObject
@property (nonatomic, strong) NSMutableArray<UIViewController *> *kids;
@property (nonatomic, weak) UIViewController *presenter;
- (NSArray<UIViewController *> *)childViewControllers;
- (UIViewController *)presentingViewController;
- (BOOL)shouldAutomaticallyForwardAppearanceMethods;
- (void)dm_addChild:(UIViewController *)c;
@end
@implementation UIViewController
- (NSArray<UIViewController *> *)childViewControllers { return _kids ? [_kids copy] : @[]; }
- (UIViewController *)presentingViewController { return _presenter; }
- (BOOL)shouldAutomaticallyForwardAppearanceMethods { return YES; }
- (void)dm_addChild:(UIViewController *)c { if (!_kids) _kids = [NSMutableArray array]; [_kids addObject:c]; }   // (-addChildViewController:'s order: at the end)
@end

// ---- Apple's Control Center -----------------------------------------------------------------------------------------------------------------------
static NSMutableArray<NSString *> *gEvents;   // (what happened, in order)
static int gSaved = 1;                        // (Uptime's saved displaySize: 0 = 1x1, 1 = 1x2)
static int gAppleW = 2;                       // (Uptime's width in Apple's grid: what its sizes were when it last read them)
@interface CCUIModularControlCenterOverlayViewController : UIViewController @end
@implementation CCUIModularControlCenterOverlayViewController @end
@interface CCUISensorAttributionExpandedViewController : UIViewController @end
@implementation CCUISensorAttributionExpandedViewController @end
@interface CCUIStatusLabelViewController : UIViewController @end
@implementation CCUIStatusLabelViewController @end
@interface CCUIModuleCollectionViewController : UIViewController @end
@implementation CCUIModuleCollectionViewController
- (void)_updateModuleControllers { [gEvents addObject:@"apple update"]; gAppleW = gSaved ? 2 : 1; }   // (15.6.1: its module controllers, its position providers -- CCSupport's sizes --, its layout)
- (void)_refreshPositionProviders { [gEvents addObject:@"apple refresh"]; }
- (id)moduleViewForIdentifier:(NSString *)mid { return [mid isEqualToString:@"com.mtac.uptimemodule"] ? @"Uptime's container" : nil; }
@end
@interface DMTestGridWithout : UIViewController @end   // (a grid on an iPadOS build without the call)
@implementation DMTestGridWithout @end

// ---- the rest of the panel: what the controller and DMCCPDidFinish read ------------------------------------------------------------------------
static __weak UIViewController *gCCPGrid, *gCCPOverlay;
static BOOL gCCPHaveUpdate = YES, gCCPOn = YES, gCCPLaidSkipped = NO;
static int gLaidW = 0;   // (Uptime's width the panel was laid out at)
static void DMLog(NSString *s) { (void)s; }
static void DMCCPLayout(NSString *why) { [gEvents addObject:[@"layout: " stringByAppendingString:why]]; gLaidW = gAppleW; }
static void AppleFinish(id self, SEL _cmd, id grid, id module) { [gEvents addObject:@"apple finish"]; }   // (Apple's overlay: told after the container's ignoreFrameUpdates went off)
static void (*o_DMCCPDidFinish)(id, SEL, id, id) = AppleFinish;

#include "ccmoduleupdate-gen.h"   // (the code as built)

// ---- Uptime's expanded view: its Module Size action as its binary does it ------------------------------------------------------------------------
@interface DMTestUptime : UIViewController @end
@implementation DMTestUptime
- (void)setModuleSize:(int)index {
    gSaved = index;   // (-[NSUserDefaults setObject:forKey:inDomain:] first: the size is kept even when the next call aborts)
    id vc = [[[self presentingViewController] childViewControllers] lastObject];
    if (vc) ((void (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"_updateModuleControllers"));
}
@end

static UIViewController *gKeepGrid, *gKeepOverlay, *gKeepOurs;   // (strong: gCCPGrid is weak, as in the panel)
static DMTestUptime *World(Class grid, BOOL ours) {
    gEvents = [NSMutableArray array]; gSaved = 1; gAppleW = 2; gLaidW = 0; gCCPHaveUpdate = YES;
    gKeepOverlay = [CCUIModularControlCenterOverlayViewController new];
    [gKeepOverlay dm_addChild:[CCUISensorAttributionExpandedViewController new]];
    [gKeepOverlay dm_addChild:[CCUIStatusLabelViewController new]];
    gKeepGrid = [grid new]; [gKeepOverlay dm_addChild:gKeepGrid];
    gCCPGrid = gKeepGrid;
    gKeepOurs = nil;
    if (ours) { gKeepOurs = [DMCCPPanelController new]; [gKeepOverlay dm_addChild:gKeepOurs]; }   // (DMCCPEnsurePanel: after Apple's grid)
    DMTestUptime *u = [DMTestUptime new];
    u.presenter = gKeepOverlay;   // (the expanded view's presenting controller: the overlay, the controller defining the presentation context)
    return u;
}
static NSString *Raised(void (^b)(void)) {
    @try { b(); } @catch (NSException *e) { return [NSString stringWithFormat:@"%@: %@", e.name, e.reason]; }
    return nil;
}

int main(void) {
    @autoreleasepool {
        // iPadOS's look: nothing of ours under the overlay, the module works as Uptime's maker meant
        DMTestUptime *u = World([CCUIModuleCollectionViewController class], NO);
        NSString *r = Raised(^{ [u setModuleSize:0]; });
        Expect(!r && [gEvents isEqualToArray:@[@"apple update"]] && gAppleW == 1, @"iPadOS's look: the overlay's last child is Apple's grid; Uptime's 1x1 reaches it, nothing raises");

        // Mac: ours is the last child (the 15.6.1, 16.7.7 and 17.5.1 dumps), the call comes to it
        u = World([CCUIModuleCollectionViewController class], YES);
        Expect([[gKeepOverlay.childViewControllers lastObject] isKindOfClass:[DMCCPPanelController class]], @"Mac: our controller is the overlay's last child, after Apple's grid (the case Uptime's call meets)");
        r = Raised(^{ [u setModuleSize:0]; });
        Expect(!r, [NSString stringWithFormat:@"Mac: Uptime's Module Size 1x1 does not raise (1.8.2: unrecognized selector, SpringBoard aborted)%@", r ? [@" -- raised " stringByAppendingString:r] : @""]);
        Expect([gEvents isEqualToArray:@[@"apple update", @"layout: a module's size changed"]], [NSString stringWithFormat:@"  ... Apple's grid reads the sizes again first, then the panel is laid out once (%@)", [gEvents componentsJoinedByString:@", "]]);
        Expect(gLaidW == 1, @"  ... the panel laid out at the new size: Uptime 1 wide");
        gEvents = [NSMutableArray array];
        r = Raised(^{ [u setModuleSize:1]; });
        Expect(!r && [gEvents isEqualToArray:@[@"apple update", @"layout: a module's size changed"]] && gLaidW == 2, @"  ... and back to 1x2 the same way: 2 wide");

        // Apple's type for the call, and what our controller says it answers
        Method m = class_getInstanceMethod([DMCCPPanelController class], NSSelectorFromString(@"_updateModuleControllers"));
        Expect(m && !strcmp(method_getTypeEncoding(m), "v16@0:8"), @"our -_updateModuleControllers has Apple's types (v16@0:8, 15.6.1 and 16.7.7)");
        Expect(![gKeepOurs respondsToSelector:NSSelectorFromString(@"_refreshPositionProviders")], @"  ... respondsToSelector: unchanged for Apple's other calls (a module that asks first sees no change)");

        // An iPadOS build without the call, the part left out by the table
        u = World([DMTestGridWithout class], YES);
        r = Raised(^{ [u setModuleSize:0]; });
        Expect(!r && [gEvents isEqualToArray:@[@"layout: a module's size changed"]], @"a grid without the call (another build): nothing raises, nothing of Apple's is sent, the panel still laid out");
        u = World([CCUIModuleCollectionViewController class], YES);
        gCCPHaveUpdate = NO;
        r = Raised(^{ [u setModuleSize:0]; });
        Expect(!r && [gEvents isEqualToArray:@[@"layout: a module's size changed"]], @"  ... the same with the table's row missing (gCCPHaveUpdate off): Apple's call only where the table found it");
        gCCPHaveUpdate = YES;

        // Apple's other calls on the last child: Apple's grid answers them; one no one answers still raises
        u = World([CCUIModuleCollectionViewController class], YES);
        id last = [gKeepOverlay.childViewControllers lastObject];
        r = Raised(^{ ((void (*)(id, SEL))objc_msgSend)(last, NSSelectorFromString(@"_refreshPositionProviders")); });
        Expect(!r && [gEvents isEqualToArray:@[@"apple refresh"]], @"a call only Apple's grid answers (-_refreshPositionProviders) goes to Apple's grid");
        __block id got = nil;
        r = Raised(^{ got = ((id (*)(id, SEL, id))objc_msgSend)(last, NSSelectorFromString(@"moduleViewForIdentifier:"), @"com.mtac.uptimemodule"); });
        Expect(!r && [got isEqual:@"Uptime's container"], @"  ... one that returns a value returns Apple's (-moduleViewForIdentifier:)");
        r = Raised(^{ ((void (*)(id, SEL))objc_msgSend)(last, NSSelectorFromString(@"dm_noOneAnswersThis")); });
        Expect(r && [r hasPrefix:NSInvalidArgumentException], @"  ... a call no one answers still raises (unrecognized selector, as for any object: nothing swallowed)");
        Expect(![last shouldAutomaticallyForwardAppearanceMethods] && [[last childViewControllers] count] == 0, @"  ... UIKit's own calls stay ours (appearance, its children)");

        // Before Apple's build (no grid known yet)
        u = World([CCUIModuleCollectionViewController class], YES);
        gKeepGrid = nil; gCCPGrid = nil;
        last = [gKeepOverlay.childViewControllers lastObject];
        r = Raised(^{ [u setModuleSize:0]; });
        Expect(!r && [gEvents isEqualToArray:@[@"layout: a module's size changed"]], @"no grid known: Uptime's call does not raise");
        r = Raised(^{ ((void (*)(id, SEL))objc_msgSend)(last, NSSelectorFromString(@"_refreshPositionProviders")); });
        Expect(r && [r hasPrefix:NSInvalidArgumentException], @"  ... and Apple's other calls raise as before (nothing to pass them to)");

        // Apple lets go of the container it held while Uptime was expanded (the size change's layout kept its new frame, not set then)
        World([CCUIModuleCollectionViewController class], YES); gCCPOverlay = gKeepOverlay;
        SEL fin = NSSelectorFromString(@"moduleCollectionViewController:didFinishInteractionWithModule:");
        gCCPLaidSkipped = YES; gEvents = [NSMutableArray array];
        DMCCPDidFinish(gKeepOverlay, fin, gKeepGrid, nil);
        Expect([gEvents isEqualToArray:@[@"apple finish", @"layout: Apple let go of a module"]], [NSString stringWithFormat:@"a layout passed a container Apple held: when Apple lets go (after its own call) the panel is laid out again, the container to its new frame (%@)", [gEvents componentsJoinedByString:@", "]]);
        gCCPLaidSkipped = NO; gEvents = [NSMutableArray array];
        DMCCPDidFinish(gKeepOverlay, fin, gKeepGrid, nil);
        Expect([gEvents isEqualToArray:@[@"apple finish"]], @"  ... nothing passed while it was held (a press, an expanded view with no change): Apple's call only, no layout");
        gCCPLaidSkipped = YES; gEvents = [NSMutableArray array];
        DMCCPDidFinish([CCUIModularControlCenterOverlayViewController new], fin, gKeepGrid, nil);
        gCCPOn = NO; DMCCPDidFinish(gKeepOverlay, fin, gKeepGrid, nil); gCCPOn = YES;
        Expect([gEvents isEqualToArray:@[@"apple finish", @"apple finish"]], @"  ... another overlay, or the panel off (iPadOS's look): Apple's call only");

        printf("%d checks, %d failed\n", checks, fails);
        return fails ? 1 : 0;
    }
}
