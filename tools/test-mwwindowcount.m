// test-mwwindowcount.m -- Mac test (Mac Catalyst) of MilkyWay4's count of the windows on screen (1.8.7.5, audit L33 of 1.8.7.2). DMMilkyWayWindowCount
// counted every window on MilkyWay's layer that was not minimized: with Mac Switcher desktops the other desktops' windows (away, hidden) and the closing
// ones MilkyWay keeps in its layer for its animation counted too, so the Window menu's Minimize All stayed enabled and did nothing, a Dock tap on the
// full-screen app passed the "no windows" test, and Home Minimizes counted windows not on screen. Now only windows shown, not minimized, not away and
// not closing count. Runs the real DMMilkyWayWindowCount, DMVisibleWindowCount, DMMilkyWayLayer, DMWindowMinimized and their marks, cut out of
// statusbar/StatusBar.x by test-mwwindowcount.sh into mwc-real.inc, on stand-ins for MilkyWay's own classes (its layer and its windows).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface AXWindowView : UIView
@end
@implementation AXWindowView
@end
@interface AXPassthroughWindow : UIWindow
@end
static AXPassthroughWindow *gKLayer;
@implementation AXPassthroughWindow
+ (instancetype)sharedInstance { return gKLayer; }
@end
static BOOL gKSM = NO;
static BOOL DMSMEngine(void) { return gKSM; }
static NSArray<NSString *> *DMSMWindowKeys(void) { return @[@"com.apple.mobilenotes|sceneID:a", @"com.apple.Maps|sceneID:b"]; }
static int gKEngine;
static int DMActiveEngine(void) { return gKEngine; }
static NSMutableArray<UIView *> *gKStages;
static NSArray<UIView *> *DMAerialStages(void) { return gKStages; }
static BOOL DMStageMinimized(UIView *stage);
static NSArray<UIWindow *> *DMZetsuWindows(void) { return @[]; }

#include "mwc-real.inc"

static BOOL DMStageMinimized(UIView *stage) { return NO; }
static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

static AXWindowView *gA, *gB;
static void Setup(void) {   // MilkyWay4: Notes and Maps as windows on its layer (and a view of its own that is no window)
    gKSM = NO; gKEngine = DMEngineMilkyWay; gKStages = [NSMutableArray array];
    gKLayer = [[AXPassthroughWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    [gKLayer addSubview:[UIView new]];
    gA = [[AXWindowView alloc] initWithFrame:CGRectMake(100, 100, 500, 400)]; [gKLayer addSubview:gA];
    gB = [[AXWindowView alloc] initWithFrame:CGRectMake(700, 100, 500, 400)]; [gKLayer addSubview:gB];
}
static void Mark(UIView *v, const void *key) { objc_setAssociatedObject(v, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL Count(NSUInteger want) { return DMMilkyWayWindowCount() == want && DMVisibleWindowCount() == want; }

int main(void) {
    @autoreleasepool {
        Setup();
        Check(Count(2), @"two windows shown: 2 (as before)");
        Setup(); Mark(gA, kMSWAwayKey); gA.hidden = YES;
        Check(Count(1), @"L33: one on another Mac Switcher desktop (away, hidden): 1");
        Setup(); Mark(gA, kMSWAwayKey);
        Check(Count(1), @"L33: one marked away before it is hidden: 1");
        Setup(); Mark(gA, kMSWAwayKey); Mark(gB, kMSWAwayKey); gA.hidden = gB.hidden = YES;
        Check(Count(0), @"L33: both on Desktop 2, Desktop 1 shown: 0 (Minimize All greyed, Home minimizes nothing)");
        Setup(); Mark(gA, kStageClosingKey);
        Check(Count(1), @"L33: one closing (MilkyWay keeps it in its layer for its animation): 1");
        Setup(); gA.hidden = YES;
        Check(Count(1), @"L33: one hidden: 1");
        Setup(); Mark(gA, kMinimizedKey); gA.hidden = YES;
        Check(Count(1), @"one minimized: 1 (as before)");
        Setup(); Mark(gA, kMinimizedKey);
        Check(Count(1), @"one minimized while still shown: 1 (as before)");
        Setup(); gKLayer = nil;
        Check(Count(0), @"no MilkyWay layer: 0 (as before)");
        // the other engines' counts are their own (as before)
        Setup(); gKEngine = DMEngineAerial; [gKStages addObject:[UIView new]]; Mark(gA, kMSWAwayKey);
        Check(DMVisibleWindowCount() == 1, @"Aerial: its shown stages (as before)");
        Setup(); gKSM = YES;
        Check(DMVisibleWindowCount() == 2, @"Stage Manager engine: its windows (as before)");
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
