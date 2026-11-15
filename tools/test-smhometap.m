// test-smhometap.m -- the Stage Manager engine's icon tap at the Home Screen with Open Apps as Windows off (1.8.7.4, audit M13 of 1.8.7.2): a
// minimized WINDOW of the app comes back as that window, as with Open Apps as Windows on, from the Dock with a stage on screen and on the other
// engines; an app with no such window opens full screen as before. The real code is cut out of statusbar/StatusBar.x by test-smhometap.sh
// (smhometap-real.inc): DMSMAddToStage with DMSMAddNo and the fix's DMSMHomeTapBringsWindow, DMSMOpensAsWindow (1.4.5's rule, which the launch
// join asks too), DMSMIsMinimized, DMSMGrowFromDockAtTapForApp, DMSMStageOf, DMSMFrontStageOnDisplay, DMSMFrontStage and DMSMItemFor, with the real
// window keys (SMWindowKey.h). SpringBoard's stages, the full-screen stage request, the join's request and the picture's grow are stand-ins that
// record what was asked. Run against the code before the fix (no DMSMHomeTapBringsWindow) the Home Screen cases of a minimized window fail.
// 1.8.7.5 (review of audit track f, finding 1): the tap first looks for minimized windows that are gone (DMSMMinimizedLook, tested on its own in
// test-smminpictures: here a stand-in that drops the marks and pictures of windows in no stage, as it does), so a window quit from the App Switcher
// a moment ago -- its Dock icon tapped there, before the watch's next look -- is not taken for the app's new window: no old picture grows over it.
#import <Foundation/Foundation.h>
#include "SMWindowKey.h"

// ---- stand-ins: UIKit's few parts the code reads, SpringBoard's app ----
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
@end
@interface UIView : NSObject
@property (nonatomic, strong) UIView *window;
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic, strong) UIView *superview;
@end
@implementation UIView
@end
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
// A stage of SpringBoard's model: its windows (item -> attributes) and its display. An item is "item:<window key>"; attributes {full, t}.
@interface TStage : NSObject
@property (nonatomic, strong) NSMutableDictionary *items;
@property (nonatomic, strong) id identity;
@end
@implementation TStage
@end

// ---- the scenario's world ----
static NSMutableArray<TStage *> *gStages;        // (recent stages, newest first)
static TStage *gShown;                            // (the stage the iPad shows: nil at the Home Screen)
static NSMutableSet<NSString *> *gMin;            // (the minimized set, DMSMMinimizedSet)
static NSMutableDictionary<NSString *, UIView *> *gSMMinPictures;
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows, *gSMFitLoose;
static BOOL gSMRequestDeferred = NO;
static BOOL gWindowed;                            // (Open Apps as Windows)
static SBApplication *gFront;                     // (SpringBoard's front app: nil at the Home Screen)
static NSString *gNewEntityKey;                   // (the window SpringBoard's entity for the app names: its default scene)
// what the code asked for
static NSMutableArray<NSString *> *gFullStages, *gGrown, *gBrought, *gRequests, *gLog;
static int gJoinAsWindow;                         // (-1: no join attributes asked; else the windowed answer they were asked with)

#define DM_FEATURE_MARK(x) do { } while (0)
static BOOL DMSMIsMinimized(NSString *key);   // (the real one, below)
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static BOOL DMSMEngine(void) { return YES; }
static BOOL DMWindowedLaunchOn(void) { return gWindowed; }
static BOOL DMFitEnabled(void) { return NO; }
static id DMSMIdentityOfScreen(UIScreen *sc) { (void)sc; return @"main"; }
static BOOL DMSMIsMainIdentity(id identity) { return [identity isEqual:@"main"]; }
static BOOL DMMSWSMElsewhereFor(id identity, NSString *key) { (void)identity; (void)key; return NO; }
static BOOL DMMSWSMTVDesktops(id identity) { (void)identity; return NO; }
static id DMMSWSMShownOn(id identity) { (void)identity; return nil; }
static SBApplication *DMFrontApp(void) { return gFront; }
static NSArray *DMSMRecentStages(void) { return gStages; }
static id DMSMShownMainStage(void) { return gShown; }
static id DMSMStageDisplayIdentity(id stage) { return [stage isKindOfClass:[TStage class]] ? ((TStage *)stage).identity : nil; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[TStage class]] ? [((TStage *)stage).items copy] : nil; }
static NSString *DMSMItemKey(id item) { return [item isKindOfClass:[NSString class]] && [item hasPrefix:@"item:"] ? [item substringFromIndex:5] : nil; }
static NSString *DMSMItemBundle(id item) { return DMSMKeyBundle(DMSMItemKey(item)); }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { return [attrs isKindOfClass:[NSDictionary class]] && attrs[@"t"] ? [attrs[@"t"] longLongValue] : dflt; }
static BOOL DMSMAttrsFullScreen(id attrs) { return [attrs isKindOfClass:[NSDictionary class]] && [attrs[@"full"] boolValue]; }
static NSMutableSet<NSString *> *DMSMMinimizedSet(void) { return gMin; }
static void DMSMSetMinimized(NSString *key, BOOL on) { if (on) [gMin addObject:key]; else DMSMKeySetRemove(gMin, key); }
static UIView *DMSMCardFor(NSString *key) { (void)key; return nil; }
static void DMSMGrowFromDockAtTap(NSString *key) { if (gSMMinPictures[key] && DMSMIsMinimized(key)) [gGrown addObject:key]; }   // (the real one: the picture grows when there and still minimized)
static BOOL DMSMOpenFullScreenStage(NSString *bundle, id template, id identity) { (void)template; (void)identity; [gFullStages addObject:bundle]; return YES; }
static void DMSMBringToFront(NSString *key) { [gBrought addObject:key]; }
static void DMSMFitForgetClosed(NSString *opening) { (void)opening; }
static BOOL DMSMFitAsksAbout(NSString *bundle, NSArray<NSString *> *stageKeys, NSString **l, NSString **r) { (void)bundle; (void)stageKeys; (void)l; (void)r; return NO; }
static void DMSMFitAskThen(NSString *bundle, NSString *l, NSString *r, void (^open)(void)) { (void)bundle; (void)l; (void)r; (void)open; }
static void DMOpenApp(NSString *bundleID) { (void)bundleID; }
static BOOL DMSMStageRoleOfItem(id stage, id item, long long *out) {
    NSArray *keys = [[DMSMStageItemsMap(stage) allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger i = [keys indexOfObject:item];
    if (i == NSNotFound) return NO;
    static const long long roles[] = {1, 2, 5, 6, 7, 8, 9};
    *out = i < 7 ? roles[i] : 0; return YES;
}
static long long DMSMRoleOr(id stage, id item, long long dflt) { long long r = dflt; return DMSMStageRoleOfItem(stage, item, &r) ? r : dflt; }
static size_t DMSMWindowCap(void) { return 7; }
static long long DMSMFirstFreeRole(NSSet<NSNumber *> *used) { static const long long roles[] = {1, 2, 5, 6, 7, 8, 9}; for (int i = 0; i < 7; i++) if (![used containsObject:@(roles[i])]) return roles[i]; return 0; }
static id DMSMNewEntity(NSString *bundle, id identity) { (void)identity; return @{@"b": bundle, @"k": gNewEntityKey ?: bundle}; }
static NSString *DMSMEntityKey(id entity) { return [entity isKindOfClass:[NSDictionary class]] ? entity[@"k"] : nil; }
static id DMSMJoinAttributes(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage) { (void)key; (void)frontAttrs; (void)stage; gJoinAsWindow = windowed; return @{@"full": @(!windowed), @"t": @(newest + 1)}; }
enum { DMSMFitDefault = 0, DMSMFitKept = 1, DMSMFitFourKept = 2 };
static NSArray<NSString *> *DMSMFitTakingPart(NSArray<NSString *> *b, NSDictionary<NSString *, NSString *> *s, NSSet<NSString *> *l, NSSet<NSString *> **lo) { (void)s; (void)l; (void)lo; return b; }
static NSDictionary<NSString *, NSString *> *DMSMFitPlanDecide(NSDictionary<NSString *, NSString *> *s, NSArray<NSString *> *b, NSArray<NSString *> *d, int *how) { (void)s; (void)b; (void)d; (void)how; return nil; }
static NSArray<NSString *> *DMDefaultSlotNames(NSUInteger n) { (void)n; return @[]; }
static id DMSMAttrsForLayoutIn(id attrs, id place, id stage) { (void)place; (void)stage; return attrs; }
static id DMSMEntityForStageItem(id stage, id item) { (void)stage; return item; }
static BOOL DMSMFrontIsFullScreen(void) { return NO; }
static NSSet<NSNumber *> *DMSMNewWindowRoles(void) { return [NSSet setWithArray:@[@1, @2, @5, @6, @7, @8, @9]]; }
static BOOL DMSMRequestOnKeeping(id identity, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity, NSSet<NSNumber *> *keep) {
    (void)identity; (void)plan; (void)allowed; (void)keep; [gRequests addObject:[NSString stringWithFormat:@"%@ %@", label ?: @"-", DMSMEntityKey(frontEntity)]]; return YES;
}
static void DMSMDismissOtherFullScreen(id stage, NSString *keep) { (void)stage; (void)keep; }
static void DMSMAfterGesture(NSString *what, dispatch_block_t block) { (void)what; block(); }
// The look for minimized windows that are gone (the real one: DMSMMinimizedLook -> DMSMMinimizedForgetClosed, test-smminpictures): a window key in
// no stage loses its mark and its picture; nothing when no stage is on record.
static int gLooks;
static void DMSMMinimizedLook(void) {
    gLooks++;
    if (!gStages.count) return;
    NSMutableSet<NSString *> *present = [NSMutableSet set], *keys = [gMin mutableCopy];
    for (TStage *st in gStages) for (id it in st.items) { NSString *k = DMSMItemKey(it); if (k) [present addObject:k]; }
    [keys addObjectsFromArray:gSMMinPictures.allKeys];
    NSSet<NSString *> *gone = DMSMKeysGone(keys, present);
    [gMin minusSet:gone];
    for (NSString *k in gone) [gSMMinPictures removeObjectForKey:k];
}

// the real code's own declarations (StatusBar.x declares them ahead the same way)
static id DMSMStageOf(NSString *key);
static id DMSMFrontStageOnDisplay(id identity);
static id DMSMFrontStage(void);
static id DMSMItemFor(id stage, NSString *key, id *attrsOut);
static BOOL DMSMOpensAsWindow(NSString *key, BOOL windowed, BOOL minimized);
#include "smhometap-real.inc"

// ---- the scenarios ----
static NSString *const kSafari = @"com.apple.mobilesafari", *const kNotes = @"com.apple.mobilenotes";
static NSString *W(NSString *bundle, NSString *scene) { return DMSMKeyMake(bundle, [NSString stringWithFormat:@"sceneID:%@-%@", bundle, scene]); }
static TStage *Stage(NSDictionary<NSString *, NSDictionary *> *windows) {   // (window key -> attributes)
    TStage *s = [TStage new]; s.identity = @"main"; s.items = [NSMutableDictionary dictionary];
    for (NSString *k in windows) s.items[[@"item:" stringByAppendingString:k]] = windows[k];
    return s;
}
static NSDictionary *Win(long long t) { return @{@"full": @NO, @"t": @(t)}; }
static NSDictionary *Full(long long t) { return @{@"full": @YES, @"t": @(t)}; }
static void Reset(void) {
    gStages = [NSMutableArray array]; gShown = nil; gMin = [NSMutableSet set]; gSMMinPictures = [NSMutableDictionary dictionary];
    gSMFitSlots = nil; gSMFreeWindows = nil; gSMFitLoose = nil; gWindowed = NO; gFront = nil; gNewEntityKey = nil;
    gFullStages = [NSMutableArray array]; gGrown = [NSMutableArray array]; gBrought = [NSMutableArray array]; gRequests = [NSMutableArray array];
    gLog = [NSMutableArray array]; gJoinAsWindow = -1; gLooks = 0;
}
static void Minimized(NSString *key, BOOL picture) { [gMin addObject:key]; if (picture) gSMMinPictures[key] = [UIView new]; }
static int fails = 0, checks = 0;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Tap(NSString *bundle) { return DMSMAddToStage(bundle, [UIView new]); }
static NSString *J(NSArray *a) { return [a componentsJoinedByString:@","]; }
// The window SpringBoard's own launch opens comes back as a window: the join asks DMSMOpensAsWindow(its key, Open Apps as Windows, its mark).
static BOOL JoinOpensAsWindow(NSString *key) { return DMSMOpensAsWindow(key, DMWindowedLaunchOn(), DMSMIsMinimized(key)); }
// "SpringBoard's own launch": the tap not added (NO), no full-screen stage of ours.
static BOOL NormalLaunch(BOOL added) { return !added && gFullStages.count == 0 && gRequests.count == 0; }
static BOOL OurFullScreen(BOOL added, NSString *bundle) { return added && [J(gFullStages) isEqualToString:bundle] && gRequests.count == 0; }

int main(void) {
    @autoreleasepool {
        NSString *saf = W(kSafari, @"default"), *saf2 = W(kSafari, @"3E2F1A90"), *notes = W(kNotes, @"default");
        BOOL r;
        printf("-- the Home Screen, Open Apps as Windows off: a minimized window comes back as that window (the audit's case)\n");
        // 1. The yellow light: Safari at Center, minimized -- the desktop's last window, so the Home Screen; its hidden stage is the most recent.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{saf: Win(10)})]; Minimized(saf, YES);
        r = Tap(kSafari);
        Check(NormalLaunch(r), [NSString stringWithFormat:@"minimized by its yellow light, tapped in the Dock at the Home Screen: SpringBoard's own launch, no full-screen stage of ours (added %d, full-screen stages [%@])", r, J(gFullStages)]);
        Check(JoinOpensAsWindow(saf), @"  ... and the launch join opens that window as a window (DMSMOpensAsWindow on its key and its mark)");
        Check([J(gGrown) isEqualToString:saf], [NSString stringWithFormat:@"  ... its picture grows out of the Dock from the tap on, as with Open Apps as Windows on (grown [%@])", J(gGrown)]);
        Check([gMin containsObject:saf], @"  ... the minimized mark stays until the join is written (the join takes it, F3)");
        // 2. Home with Home Minimizes Windows: the desktop's two windows minimized, its stage the most recent; Notes tapped.
        Reset(); gNewEntityKey = notes;
        [gStages addObject:Stage(@{saf: Win(10), notes: Win(11)})]; Minimized(saf, NO); Minimized(notes, NO);
        r = Tap(kNotes);
        Check(NormalLaunch(r), [NSString stringWithFormat:@"Home Minimizes Windows: Notes' window minimized by Home, tapped at the Home Screen: SpringBoard's own launch (added %d, full-screen stages [%@])", r, J(gFullStages)]);
        Check(JoinOpensAsWindow(notes), @"  ... and the join opens Notes' window as a window");
        Check([gMin containsObject:saf], @"  ... Safari's window stays minimized");
        // 3. An older version's entry by app ("com.apple.mobilesafari"): the app's window comes back as that window too.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{saf: Win(10)})]; [gMin addObject:kSafari]; gSMMinPictures[saf] = [UIView new];
        r = Tap(kSafari);
        Check(NormalLaunch(r) && JoinOpensAsWindow(saf), [NSString stringWithFormat:@"a minimized entry by app (saved by an older version), its window at a size of its own: SpringBoard's own launch, a window (added %d)", r]);
        // 4. Two windows of Safari: one full screen in the newest stage (not minimized), one minimized at a window size in an older hidden stage.
        //    Each window answers for itself: the app's key would read the full-screen one and answer full screen.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{saf: Full(20)})]; [gStages addObject:Stage(@{saf2: Win(12)})]; Minimized(saf2, YES);
        r = Tap(kSafari);
        Check(NormalLaunch(r), [NSString stringWithFormat:@"two Safari windows, the minimized one at a window size in an older stage: by its own key, SpringBoard's own launch (added %d, full-screen stages [%@])", r, J(gFullStages)]);
        Check(JoinOpensAsWindow(saf2) && !JoinOpensAsWindow(saf), @"  ... the join: the minimized window as a window, the other (full screen, not minimized) full screen");
        Check([J(gGrown) isEqualToString:saf2], [NSString stringWithFormat:@"  ... the minimized one's picture grows (grown [%@])", J(gGrown)]);

        printf("-- the Home Screen, Open Apps as Windows off: no minimized window to bring back, full screen as before\n");
        // 5. A full-screen app sent to the background (Home marks it minimized): full-screen attributes of its own, full screen again.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{saf: Full(10)})]; Minimized(saf, NO);
        r = Tap(kSafari);
        Check(OurFullScreen(r, kSafari), [NSString stringWithFormat:@"a full-screen app sent to the background, tapped: our full-screen stage, as before (added %d, full-screen stages [%@])", r, J(gFullStages)]);
        Check(gGrown.count == 0, @"  ... no picture grows");
        // 6. Not minimized: Safari's window in an older stage, Notes' desktop the most recent.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{notes: Win(20)})]; [gStages addObject:Stage(@{saf: Win(10)})];
        r = Tap(kSafari);
        Check(OurFullScreen(r, kSafari), [NSString stringWithFormat:@"Safari's window not minimized (an older stage): full screen, as apps open (added %d)", r]);
        // 7. Never opened: no window of the app anywhere.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{notes: Win(20)})];
        r = Tap(kSafari);
        Check(OurFullScreen(r, kSafari), [NSString stringWithFormat:@"an app with no window: full screen (added %d)", r]);
        // 8. Another app's minimized window, and an app whose name starts with Safari's.
        Reset(); gNewEntityKey = saf;
        NSString *other = W(@"com.apple.mobilesafari.extra", @"default");
        [gStages addObject:Stage(@{notes: Win(20), other: Win(21)})]; Minimized(notes, YES); Minimized(other, YES);
        r = Tap(kSafari);
        Check(OurFullScreen(r, kSafari) && gGrown.count == 0, [NSString stringWithFormat:@"only other apps' windows minimized (Notes, com.apple.mobilesafari.extra): Safari full screen, nothing grows (added %d, grown [%@])", r, J(gGrown)]);
        // 9. A stale mark: the window is in no stage any more.
        Reset(); gNewEntityKey = saf;
        [gStages addObject:Stage(@{notes: Win(20)})]; Minimized(saf, NO);
        r = Tap(kSafari);
        Check(OurFullScreen(r, kSafari), [NSString stringWithFormat:@"a minimized mark of a window that is gone: full screen (added %d)", r]);

        printf("-- unchanged: Open Apps as Windows on, nothing on record, a stage on screen\n");
        // 10. Open Apps as Windows on: SpringBoard's own launch, the picture grows (as before).
        Reset(); gWindowed = YES; gNewEntityKey = saf;
        [gStages addObject:Stage(@{saf: Win(10)})]; Minimized(saf, YES);
        r = Tap(kSafari);
        Check(NormalLaunch(r) && [J(gGrown) isEqualToString:saf] && JoinOpensAsWindow(saf), [NSString stringWithFormat:@"Open Apps as Windows on: SpringBoard's own launch, the picture grows, a window (added %d)", r]);
        // 11. Nothing on record (every stage gone): SpringBoard's own launch.
        Reset(); gNewEntityKey = saf;
        r = Tap(kSafari);
        Check(NormalLaunch(r), [NSString stringWithFormat:@"no stage on record: SpringBoard's own launch (added %d)", r]);
        // 12. A stage on screen (Notes in front), Safari minimized at a window size: added to the stage as a window (1.4.5's path, unchanged).
        Reset(); gNewEntityKey = saf;
        TStage *deskS = Stage(@{notes: Win(20)});
        [gStages addObject:deskS]; [gStages addObject:Stage(@{saf: Win(10)})]; Minimized(saf, YES);
        gShown = deskS; gFront = [SBApplication new]; gFront.bundleIdentifier = kNotes;
        r = Tap(kSafari);
        Check(r && gJoinAsWindow == 1 && gRequests.count == 1 && gFullStages.count == 0 && ![gMin containsObject:saf],
              [NSString stringWithFormat:@"a stage on screen: the minimized Safari window joins it as a window, its mark gone (added %d, as window %d, requests [%@])", r, gJoinAsWindow, J(gRequests)]);
        // 13. The same with Safari a full-screen app sent to the background: it joins full screen (as before).
        Reset(); gNewEntityKey = saf;
        deskS = Stage(@{notes: Win(20)});
        [gStages addObject:deskS]; [gStages addObject:Stage(@{saf: Full(10)})]; Minimized(saf, NO);
        gShown = deskS; gFront = [SBApplication new]; gFront.bundleIdentifier = kNotes;
        r = Tap(kSafari);
        Check(r && gJoinAsWindow == 0 && gFullStages.count == 0, [NSString stringWithFormat:@"a stage on screen, Safari a full-screen app sent away: it joins full screen (added %d, as window %d)", r, gJoinAsWindow]);
        // 14. Already in the stage on screen: forward (unchanged).
        Reset(); gNewEntityKey = saf;
        deskS = Stage(@{notes: Win(20), saf: Win(19)});
        [gStages addObject:deskS]; gShown = deskS; gFront = [SBApplication new]; gFront.bundleIdentifier = kNotes;
        r = Tap(kSafari);
        Check(r && [J(gBrought) isEqualToString:kSafari] && gRequests.count == 0, [NSString stringWithFormat:@"Safari already in the stage on screen: brought forward (added %d, forward [%@])", r, J(gBrought)]);

        printf("-- a minimized window quit from the App Switcher a moment ago, its Dock icon tapped there (1.8.7.5, review of track f, finding 1)\n");
        // 15. Open Apps as Windows on, nothing in front: Safari minimized (its picture kept), its card swiped away -- its stage gone, the watch's
        //     look not run yet (the App Switcher is up). The tap opens the app's new window on the same scene (the same key).
        Reset(); gWindowed = YES; gNewEntityKey = saf;
        [gStages addObject:Stage(@{notes: Win(20)})]; Minimized(saf, YES);
        r = Tap(kSafari);
        Check(NormalLaunch(r) && gGrown.count == 0, [NSString stringWithFormat:@"its window gone, tapped with nothing in front: SpringBoard's own launch and no old picture grows over the new window (added %d, grown [%@])", r, J(gGrown)]);
        Check(![gMin containsObject:saf] && !gSMMinPictures[saf] && gLooks == 1, @"  ... the tap looked first: the gone window's mark and picture are gone before anything reads them");
        // 16. The same with a desktop in front (Notes): the new window joins it as a new window, not as "the minimized one", no picture grows.
        Reset(); gWindowed = YES; gNewEntityKey = saf;
        deskS = Stage(@{notes: Win(20)});
        [gStages addObject:deskS]; Minimized(saf, YES);
        gShown = deskS; gFront = [SBApplication new]; gFront.bundleIdentifier = kNotes;
        r = Tap(kSafari);
        Check(r && gRequests.count == 1 && gGrown.count == 0 && ![gMin containsObject:saf], [NSString stringWithFormat:@"its window gone, tapped over a desktop: added as a window, no old picture grows over it, no stale mark (added %d, grown [%@])", r, J(gGrown)]);
        // 17. As before: the minimized window is still there (its hidden stage): it comes back as that window and its picture grows.
        Reset(); gWindowed = YES; gNewEntityKey = saf;
        deskS = Stage(@{notes: Win(20)});
        [gStages addObject:deskS]; [gStages addObject:Stage(@{saf: Win(10)})]; Minimized(saf, YES);
        gShown = deskS; gFront = [SBApplication new]; gFront.bundleIdentifier = kNotes;
        r = Tap(kSafari);
        Check(r && [J(gGrown) isEqualToString:saf] && gJoinAsWindow == 1, [NSString stringWithFormat:@"its window still in its hidden stage: it comes back as that window and its picture grows (as before; grown [%@])", J(gGrown)]);
        printf("test-smhometap: %d of %d checks pass\n", checks - fails, checks);
    }
    return fails;
}
