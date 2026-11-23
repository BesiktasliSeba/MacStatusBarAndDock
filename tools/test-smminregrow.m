// test-smminregrow.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a Stage Manager window minimized again while it still grows out of its Dock
// icon (1.8.7.5, audit L39 of 1.8.7.2). While a restored window's picture grows (gSMGrowing), its page and our title bar are held at alpha 0
// (DMSMGrowWatch, DMSMHoldGrowingCard); a minimize then (the menu bar's lights, the Window menu, the shortcut) took its pictures of that card --
// the one that flies into the Dock and the one kept for the next restore (DMSMKeepMinPicture) -- empty and without the title bar, and the growing
// picture stayed over the stage. Now DMSMFlyToDock ends that grow first (DMSMEndGrowNow): picture taken away, held views shown, entry gone.
// Review of track f, finding 2: the desktop's last window takes another way -- its minimize is the Home Screen, no DMSMFlyToDock -- so its grow went
// on over the Home Screen and the card went Home empty, its page and title bar still held out of sight; now DMSMWindowActionAs ends it first there
// too. Runs the real DMSMWindowActionAs (the window's stage, the Home and the action are stand-ins below that record what was asked),
// DMSMFlyToDock, DMSMEndGrowNow, DMSMKeepMinPicture and DMSMScreenRootOf with their globals (statusbar/StatusBar.x), cut out by
// test-smminregrow.sh into smr-real.inc, with the real statusbar/SMWindowKey.h, on real UIKit views in a window; every picture taken of the card
// and the bar is recorded with what the views showed at that moment.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/SMWindowKey.h"

#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
static BOOL MSBReduceMotion(void) { return NO; }
static long DMRealInterfaceOrientation(void) { return 3; }   // (landscape: the screen-sized view is 1366 x 1024)
static UIView *gKCard, *gKIcon;
static UIView *DMSMCardFor(NSString *key) { return gKCard; }
static UIView *DMSMDockIconViewFor(NSString *bundle) { return gKIcon; }
static UIView *DMSMDockViewForTarget(void) { return nil; }

// ---- what each picture showed: the card's page and our title bar (their alpha), whether a picture still grew over the stage
typedef struct { CGFloat page, bar, card; BOOL growing; NSUInteger entries; } KShot;
static KShot gKShots[16]; static int gKShotN;
static UIView *gKPage, *gKBar, *gKGrowPic;
static void KRecord(void) {
    if (gKShotN >= 16) return;
    gKShots[gKShotN++] = (KShot){ gKPage.alpha, gKBar.alpha, gKCard.alpha, gKGrowPic.superview != nil, 0 };
}
@interface KCard : UIView
@end
@implementation KCard
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)after { KRecord(); return [[UIView alloc] initWithFrame:self.bounds]; }
@end
@interface KBar : UIView
@end
@implementation KBar
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)after { KRecord(); return [[UIView alloc] initWithFrame:self.bounds]; }
@end

// ---- the window action's world (DMSMWindowActionAs): SpringBoard's stages (a stage's items are "item:<window key>"), the stage shown, the Home
@interface KStage : NSObject
@property (nonatomic, strong) NSDictionary *map;
@end
@implementation KStage
@end
static NSArray<KStage *> *gKStages; static KStage *gKShown;
static NSMutableSet<NSString *> *gKMin; static int gKHomes, gKRuns; static NSMutableArray<NSString *> *gKOrder;
typedef struct { CGFloat page, bar; BOOL growing; NSUInteger entries; } KAtHome;
static KAtHome gKAtHome;
static NSArray *DMSMRecentStages(void) { return gKStages; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[KStage class]] ? ((KStage *)stage).map : nil; }
static NSString *DMSMItemKey(id item) { return [item isKindOfClass:[NSString class]] && [item hasPrefix:@"item:"] ? [item substringFromIndex:5] : nil; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {
    NSDictionary *m = DMSMStageItemsMap(stage);
    for (id it in m) if ([DMSMItemKey(it) isEqualToString:key] || [DMSMKeyBundle(DMSMItemKey(it)) isEqualToString:key]) { if (attrsOut) *attrsOut = m[it]; return it; }
    return nil;
}
static id DMSMStageOf(NSString *key) { for (KStage *s in gKStages) if (DMSMItemFor(s, key, NULL)) return s; return nil; }
static id DMSMIPadStageShown(void) { return gKShown; }
static BOOL DMSMGestureHoldsStage(id stage) { return NO; }
static BOOL DMSMGestureLive(void) { return NO; }
static void DMSMAfterGestureUsers(NSString *what, dispatch_block_t block) { [gKOrder addObject:@"after gesture"]; }
static void DMSMAfterGesture(NSString *what, dispatch_block_t block) { [gKOrder addObject:@"after gesture"]; }
static BOOL DMSMStripHoldsBack(NSString *what, dispatch_block_t act) { return NO; }
static id DMSMTopAffordanceFor(NSString *key) { return @"vc"; }
static id DMCall(id obj, NSString *name) { return [name hasSuffix:@"Action"] ? [UIAction actionWithTitle:@"Minimize" image:nil identifier:nil handler:^(UIAction *a) {}] : nil; }
static void DMSMRunAction(UIAction *action, id sender) { gKRuns++; [gKOrder addObject:@"action"]; }
static void DMSMSetMinimized(NSString *key, BOOL on) { if (on) [gKMin addObject:key]; else [gKMin removeObject:key]; }
static void DMSMNoteRemoving(NSString *key, id stage) { }
static void DMSMGoHomeForReal(NSString *why);   // (below the real code: it reads what the window shows as the Home takes it)
static id DMSMStageDisplayIdentity(id stage) { return @"main"; }
static BOOL DMSMIsMainIdentity(id identity) { return YES; }
static BOOL DMSMStageShownOnDisplay(id al, id identity) { return NO; }
static void DMSMTVEmptyAfterLastWindow(id identity, NSString *what) { }   // (1.8.8.2, B86's first version: the TV's empty desktop after its last window; never reached here, the iPad alone)
static BOOL DMSMTVEmptyFirst(id identity, id item, NSString *wk) { return NO; }   // (1.8.8.2, B86: the TV's empty desktop first; never reached here, the iPad alone)
static id DMSMCoordinator(void) { return nil; }
static NSString *DMSMExpect(const char *ret, ...) { return @""; }
static BOOL DMSMSigOK(id obj, SEL sel, NSString *want, const char *what) { return NO; }
static void DMSMAPIFail(NSString *what, NSString *why) { }
static void DMSMAfterOurHome(NSString *what, id item, dispatch_block_t block) { }
static BOOL DMSMAfterHomeEnded(void) { return NO; }
static BOOL DMSMWindowActionAs(NSString *key, NSString *name, BOOL users);

#include "smr-real.inc"
static void DMSMGoHomeForReal(NSString *why) {   // (what the window shows as the Home takes it: its page, its title bar, a picture still over it)
    gKHomes++; [gKOrder addObject:@"home"];
    gKAtHome = (KAtHome){ gKPage.alpha, gKBar.alpha, gKGrowPic.superview != nil, gSMGrowing.count };
}

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Spin(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

static NSString *const kNotes = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";
static NSString *const kMaps = @"com.apple.Maps|sceneID:com.apple.Maps-default";
static UIWindow *gWin; static UIView *gStage;

// The stage: a screen-sized window, the switcher's stage view in it, Notes' card (its page inside) with our title bar above it, its Dock icon.
static void Setup(void) {
    gKLog = [NSMutableArray array]; gKShotN = 0;
    gSMMinPictures = [NSMutableDictionary dictionary]; gSMGrowing = [NSMutableDictionary dictionary];
    gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    gStage = [[UIView alloc] initWithFrame:gWin.bounds]; [gWin addSubview:gStage];
    gKCard = [[KCard alloc] initWithFrame:CGRectMake(300, 230, 600, 500)]; [gStage addSubview:gKCard];
    gKPage = [[UIView alloc] initWithFrame:gKCard.bounds]; [gKCard addSubview:gKPage];
    gKBar = [[KBar alloc] initWithFrame:CGRectMake(300, 200, 600, 30)]; [gStage addSubview:gKBar];
    objc_setAssociatedObject(gKCard, kSMBarKey, gKBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gKIcon = [[UIView alloc] initWithFrame:CGRectMake(640, 950, 64, 64)]; [gWin addSubview:gKIcon];
    gKGrowPic = nil;
    gKStages = @[]; gKShown = nil; gKMin = [NSMutableSet set]; gKHomes = gKRuns = 0; gKOrder = [NSMutableArray array]; gKAtHome = (KAtHome){ -1, -1, NO, 99 };
}
static KStage *Stage(NSArray<NSString *> *keys) { KStage *s = [KStage new]; NSMutableDictionary *m = [NSMutableDictionary dictionary]; for (NSString *k in keys) m[[@"item:" stringByAppendingString:k]] = @1; s.map = m; return s; }
// Its restore in progress (DMSMGrowFromDock): its picture growing over the stage, and `held` held out of sight by the grow's watch.
static UIView *Growing(NSString *key, NSArray<UIView *> *held) {
    UIView *keep = [[UIView alloc] initWithFrame:CGRectMake(300, 200, 600, 530)];
    NSHashTable *h = [NSHashTable weakObjectsHashTable];
    for (UIView *v in held) { v.alpha = 0.0; [h addObject:v]; }
    objc_setAssociatedObject(keep, &kSMHeldKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gStage addSubview:keep];
    gSMGrowing[key] = keep;
    return keep;
}
static BOOL AllShots(BOOL (^ok)(KShot s)) { if (!gKShotN) return NO; for (int i = 0; i < gKShotN; i++) if (!ok(gKShots[i])) return NO; return YES; }
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }

int main(void) {
    @autoreleasepool {
        // L39: Notes restored, its picture still growing (page and title bar held at alpha 0); minimized again from the menu bar's lights
        Setup();
        gKGrowPic = Growing(kNotes, @[gKPage, gKBar]);
        DMSMFlyToDock(kNotes);
        Check(gKShotN == 4, [NSString stringWithFormat:@"L39: the card and its title bar are both pictured, for the flight and for the next restore (%d pictures, 4 wanted)", gKShotN]);
        Check(AllShots(^BOOL(KShot s) { return s.page > 0.99; }), @"L39: every picture of the card shows its page (not the grow's alpha 0: an empty picture)");
        Check(AllShots(^BOOL(KShot s) { return s.bar > 0.99; }), @"L39: ... and our title bar with it");
        Check(AllShots(^BOOL(KShot s) { return !s.growing; }), @"L39: the growing picture is off the stage before any picture is taken");
        Check(gSMGrowing.count == 0 && !gKGrowPic.superview, @"L39: the grow has ended: its entry gone, its picture out of the view tree (its watch stops)");
        UIView *kept = gSMMinPictures[kNotes];
        Check(kept.subviews.count == 2, @"L39: the picture kept for the next restore holds the card and its title bar");
        Check(gKPage.alpha > 0.99 && gKBar.alpha > 0.99, @"L39: the views the grow held are shown again");
        Check(Logged(@"during its restore: the grow ends first"), @"L39: the log says so");

        // L39: the grow's watch held the card itself (no page found): it too is shown for the pictures, and given back after the minimize's own hide
        Setup();
        gKGrowPic = Growing(kNotes, @[gKCard, gKBar]);
        DMSMFlyToDock(kNotes);
        Check(AllShots(^BOOL(KShot s) { return s.card > 0.99 && s.bar > 0.99; }), @"L39: a card held itself by the grow is shown for its pictures");
        Check(gKCard.alpha < 0.01, @"... then out of sight while Stage Manager's own minimize runs (as before)");
        Spin(0.9);
        Check(gKCard.alpha > 0.99, @"... and given back after 0.8 s (as before)");

        // another window's grow is not touched
        Setup();
        UIView *otherPage = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)]; [gStage addSubview:otherPage];
        UIView *other = Growing(kMaps, @[otherPage]);
        DMSMFlyToDock(kNotes);
        Check(gSMGrowing[kMaps] == other && other.superview == gStage && otherPage.alpha < 0.01, @"another window's grow goes on (its picture, entry and held page as they were)");
        Check(AllShots(^BOOL(KShot s) { return s.page > 0.99 && s.bar > 0.99; }) && gKShotN == 4, @"... and this window's pictures are as without a grow");

        // review finding 2: the desktop's last window, restored and minimized again (the menu bar's lights, the Window menu, the shortcut) during
        // its grow: its minimize is the Home Screen (no flight, no picture kept) -- the grow ends before the Home is asked
        Setup();
        gKShown = Stage(@[kNotes]); gKStages = @[gKShown];
        gKGrowPic = Growing(kNotes, @[gKPage, gKBar]);
        BOOL took = DMSMWindowActionAs(kNotes, @"removeFromSet", YES);
        Check(took && gKHomes == 1 && [gKMin containsObject:kNotes] && gKRuns == 0, @"finding 2: the desktop's last window minimized: the Home Screen, its mark set (as before)");
        Check(gKAtHome.growing == NO && gKAtHome.entries == 0, @"finding 2: the grow has ended before the Home is asked (its picture off the screen, its entry gone)");
        Check(gKAtHome.page > 0.99 && gKAtHome.bar > 0.99, @"finding 2: ... the window's page and title bar are shown again as the Home takes it (not an empty card)");
        Check(!gKGrowPic.superview && gSMGrowing.count == 0 && Logged(@"during its restore: the grow ends first"), @"finding 2: ... nothing left over the Home Screen, and the log says so");
        Check(!gSMMinPictures[kNotes] && gKShotN == 0, @"finding 2: no picture taken or kept for the last window (its minimize is the Home, as before)");
        // the same window action with a second window on the desktop: the flight into the Dock, its grow ended first (DMSMFlyToDock), then the action
        Setup();
        gKShown = Stage(@[kNotes, kMaps]); gKStages = @[gKShown];
        gKGrowPic = Growing(kNotes, @[gKPage, gKBar]);
        took = DMSMWindowActionAs(kNotes, @"removeFromSet", YES);
        Check(took && gKHomes == 0 && gKRuns == 1 && gSMGrowing.count == 0 && !gKGrowPic.superview, @"a window with another on its desktop, minimized during its grow: its grow ends, it flies into the Dock, the action runs (no Home)");
        Check(gKShotN == 4 && AllShots(^BOOL(KShot s) { return s.page > 0.99 && s.bar > 0.99 && !s.growing; }), @"... its pictures show its page and title bar");
        // the last window, no grow: the Home as before, nothing ended
        Setup();
        gKShown = Stage(@[kNotes]); gKStages = @[gKShown];
        took = DMSMWindowActionAs(kNotes, @"removeFromSet", YES);
        Check(took && gKHomes == 1 && gKAtHome.page > 0.99 && !Logged(@"during its restore"), @"the desktop's last window minimized with no grow: the Home Screen, nothing ended (as before)");
        // the last window minimized while ANOTHER window grows (Maps, on a stage of its own): that grow goes on
        Setup();
        gKShown = Stage(@[kNotes]); gKStages = @[gKShown, Stage(@[kMaps])];
        UIView *mapsPage = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)]; [gStage addSubview:mapsPage];
        UIView *mapsGrow = Growing(kMaps, @[mapsPage]);
        took = DMSMWindowActionAs(kNotes, @"removeFromSet", YES);
        Check(took && gKHomes == 1 && gSMGrowing[kMaps] == mapsGrow && mapsGrow.superview == gStage && mapsPage.alpha < 0.01, @"the desktop's last window minimized while another window grows: that grow goes on");

        // as before: no grow
        Setup();
        DMSMFlyToDock(kNotes);
        Check(gKShotN == 4 && AllShots(^BOOL(KShot s) { return s.page > 0.99 && s.bar > 0.99; }), @"no grow: the card and its title bar pictured as they are (as before)");
        Check(gSMMinPictures[kNotes].subviews.count == 2 && gKCard.alpha < 0.01 && !Logged(@"during its restore"), @"no grow: the picture kept, the card out of sight for Stage Manager's own minimize, nothing ended (as before)");
        NSUInteger boxes = 0; for (UIView *v in gWin.subviews) if (v != gStage && v != gKIcon) boxes++;
        Check(boxes == 1, @"no grow: one picture flies into the Dock over the stage (as before)");
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
