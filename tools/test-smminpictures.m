// test-smminpictures.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the Stage Manager engine's minimized windows: their marks (the saved
// minimized set) and their pictures for the grow back out of the Dock (gSMMinPictures), 1.8.7.5, audit L37, L38 and O6 of 1.8.7.2.
// L37: a minimized window quit from the App Switcher (its stage removed: a window's scene ends with it) kept its mark and its picture for the rest of
// that SpringBoard -- opened again, the app's new window (its default scene: the same key) was taken for it and the old picture grew out of the Dock
// over the fresh window; the mark gave the app a running dot. Now the look (DMSMMinimizedForgetClosed, run by DMSMMinimizedLook from DMSMWatchTurn
// and at an icon tap) drops the mark and the picture of a window in no recent stage, only with every stage read whole, windows told apart, the start
// settled, and nothing moving -- no Mac Switcher slide, switcher gesture or workspace transaction; the App Switcher up or not (review of track f,
// finding 1: it waited for the App Switcher to close, and the Dock tapped there read the stale mark and picture). L38 / O6: up to eight
// window-sized picture pairs were held: taken under Reduce Motion (never used then), kept after a force quit, not freed on a memory warning, the
// ninth pushing out whichever the dictionary listed first. Now: none under Reduce Motion, freed at memory pressure (a growing one is out of the
// store, on screen), dropped with the app's force quit (DMSMForgetApp) and with their marks (DMSMMinimizedDrop), the oldest pushed out.
// Runs the real code cut out of statusbar/StatusBar.x by test-smminpictures.sh into smp-real.inc, with the real statusbar/SMWindowKey.h; SpringBoard
// (its stages, the state file, the grow) is the stand-ins below.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "../statusbar/SMWindowKey.h"

#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
// ---- the saved minimized set and its file
static NSMutableSet<NSString *> *gKMin;
static NSMutableSet<NSString *> *DMSMMinimizedSet(void) { return gKMin; }
static int gKWrites;
static void DMSMStateWrite(void) { gKWrites++; }
// ---- SpringBoard's stages: a stage is a KStage, its items window keys (an item without a key: NSNull), its map nil when it can't be read
@interface KStage : NSObject
@property (nonatomic, strong) NSDictionary *map;
@end
@implementation KStage
@end
static NSArray *gKStages;
static NSArray *DMSMRecentStages(void) { return gKStages; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[KStage class]] ? ((KStage *)stage).map : nil; }
static BOOL gKPerWindow = YES;
static BOOL DMSMPerWindow(void) { return gKPerWindow; }
// ---- what is moving: the App Switcher, a Mac Switcher slide, a switcher gesture, a workspace transaction
static BOOL gKSwitcher = NO, gMSWSwitching = NO, gKGesture = NO, gKBusy = NO;
static BOOL DMSwitcherVisible(void) { return gKSwitcher; }
static BOOL DMSMGestureLive(void) { return gKGesture; }
static BOOL DMSMWorkspaceBusy(void) { return gKBusy; }
static NSString *DMSMItemKey(id item) {   // (windows by app when they are not told apart, as the real one)
    if (![item isKindOfClass:[NSString class]] || ![(NSString *)item length]) return nil;
    return gKPerWindow ? item : DMSMKeyBundle(item);
}
// ---- the grow back out of the Dock, Reduce Motion, the interface's turn
static NSMutableArray<NSString *> *gKGrown;
static void DMSMGrowFromDock(NSString *key, int tries) { [gKGrown addObject:key ?: @"(nil)"]; }
static BOOL gKRM = NO;
static BOOL MSBReduceMotion(void) { return gKRM; }
static long DMRealInterfaceOrientation(void) { return 1; }
// ---- what DMSMForgetApp also clears (its other records)
static NSMutableDictionary<NSString *, id> *gSMPreZoom;
static NSMutableDictionary<NSString *, NSDictionary *> *gSMPreZoomPlaces;
static NSMutableDictionary<NSString *, NSDictionary *> *DMSMPreZoomPlaces(void) { return gSMPreZoomPlaces; }
static NSMutableDictionary<NSString *, NSString *> *gKLayouts;
static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) { return gKLayouts; }
static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gSMTurnFrames;
static NSMutableSet<NSString *> *gSMBehindDock;   // (1.8.8 H5: DMSMForgetApp hands the app's behind-the-Dock marks to DMSMTurnForget too -- test-smturnclosed)
static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) { }
// ---- a window card: its picture is a fresh view (counted)
static int gKShots;
@interface KCard : UIView
@end
@implementation KCard
- (UIView *)snapshotViewAfterScreenUpdates:(BOOL)after { gKShots++; return [[UIView alloc] initWithFrame:self.bounds]; }
@end

#include "smp-real.inc"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

static NSString *const kSetA = @"com.apple.Preferences|sceneID:com.apple.Preferences-default";
static NSString *const kSetB = @"com.apple.Preferences|sceneID:com.apple.Preferences-6C1F0A2E";
static NSString *const kSafari = @"com.apple.mobilesafari|sceneID:com.apple.mobilesafari-default";
static NSString *const kNotes = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";
static NSString *const kMaps = @"com.apple.Maps|sceneID:com.apple.Maps-default";

static void Reset(void) {
    gKLog = [NSMutableArray array]; gKMin = [NSMutableSet set]; gKWrites = 0; gKStages = nil; gKPerWindow = YES; gKGrown = [NSMutableArray array]; gKRM = NO;
    gSMPreZoom = [NSMutableDictionary dictionary]; gSMPreZoomPlaces = [NSMutableDictionary dictionary]; gKLayouts = [NSMutableDictionary dictionary];
    gSMTurnFrames = [NSMutableDictionary dictionary]; gKShots = 0;
    gSMMinPictures = [NSMutableDictionary dictionary]; gSMGrowing = [NSMutableDictionary dictionary];
    gSMTurnStartSettled = YES;
    gKSwitcher = gMSWSwitching = gKGesture = gKBusy = NO;
}
static KStage *Stage(NSArray *keys) { KStage *s = [KStage new]; NSMutableDictionary *m = [NSMutableDictionary dictionary]; for (id k in keys) m[k] = @1; s.map = m; return s; }
static KStage *Unread(void) { return [KStage new]; }   // (its map can't be read)
static void Stages(NSArray *stages) { gKStages = stages; }   // (new stage objects every time: the look runs at once)
static void Keep(NSString *key) {   // (the minimize's own call, DMSMFlyToDock: a card of 400 x 300 with its 30 pt title bar)
    KCard *card = [[KCard alloc] initWithFrame:CGRectMake(100, 130, 400, 300)];
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(100, 100, 400, 30)];
    DMSMKeepMinPicture(key, card, bar, card.frame, bar.frame, CGRectUnion(card.frame, bar.frame), nil);
}
static void Minimized(NSString *key) { [gKMin addObject:key]; Keep(key); }
static BOOL Pic(NSString *key) { return gSMMinPictures[key] != nil; }
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }
static void Spin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

int main(void) {
    @autoreleasepool {
        UIWindow *win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];

        // L37: the App Switcher's swipe-up removes the minimized window's stage: its mark and its picture go at the next look
        Reset();
        Minimized(kSetA);
        Stages(@[Stage(@[kSafari]), Stage(@[kSetA])]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA) && gKWrites == 0, @"a minimized window in its hidden stage keeps its mark and its picture");
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedForgetClosed();
        Check(![gKMin containsObject:kSetA], @"L37: its stage removed (quit from the App Switcher): its minimized mark goes at the next look");
        Check(!Pic(kSetA), @"L37: ... and its picture with it (no old picture grows over the app's fresh window)");
        Check(gKWrites == 1 && Logged(@"1 minimized mark(s) and 1 picture(s) dropped"), @"L37: the saved set is written once, and the log says what went");
        Check(!DMSMIsMinimized(kSetA), @"L37: the app's next window on the same scene is not taken for the minimized one (no grow, no running dot)");

        // L37: another window of the same app stays as it is
        Reset();
        Minimized(kSetA); Minimized(kSetB);
        Stages(@[Stage(@[kSetA]), Stage(@[kSetB])]);
        DMSMMinimizedForgetClosed();
        Stages(@[Stage(@[kSetB])]);
        DMSMMinimizedForgetClosed();
        Check(![gKMin containsObject:kSetA] && !Pic(kSetA), @"L37: one of the app's two minimized windows closed: its mark and picture go");
        Check([gKMin containsObject:kSetB] && Pic(kSetB), @"L37: ... the app's other window keeps its mark and picture");

        // a picture whose mark went another way: gone with its window, kept while the window is there
        Reset();
        Keep(kNotes); Keep(kMaps);
        Stages(@[Stage(@[kMaps])]);
        DMSMMinimizedForgetClosed();
        Check(!Pic(kNotes) && Pic(kMaps), @"L38: a picture without a mark goes once its window is in no stage; one whose window is there stays");

        // stages not read whole: nothing is taken for gone
        Reset();
        Minimized(kSetA); Minimized(kNotes);
        Stages(@[Stage(@[kSafari]), Unread()]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA) && [gKMin containsObject:kNotes] && Pic(kNotes), @"a stage that can't be read: nothing dropped");
        Stages(@[Stage(@[kSafari, [NSNull null]])]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"a window without a key in a stage: nothing dropped");
        Stages(nil);
        DMSMMinimizedForgetClosed();
        Stages(@[]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA) && gKWrites == 0, @"no stages at all (SpringBoard's model not there): nothing dropped");
        Stages(@[Stage(@[kSafari, kNotes])]);
        DMSMMinimizedForgetClosed();
        Check(![gKMin containsObject:kSetA] && !Pic(kSetA) && [gKMin containsObject:kNotes] && Pic(kNotes), @"L37: read whole again: the gone window's go, the one there stays");

        // the gates: the start (SMHome.h's own prune first) and windows told apart
        Reset();
        Minimized(kSetA);
        gSMTurnStartSettled = NO;
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"before the start has settled: nothing dropped (the start's own prune comes first)");
        Reset();
        Minimized(kSetA);
        gKPerWindow = NO;
        Stages(@[Stage(@[kSetA])]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"windows told apart by app here: a window's mark is not compared with app keys (kept)");
        Reset();
        [gKMin addObject:@"com.apple.Preferences"];
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedForgetClosed();
        Check([gKMin containsObject:@"com.apple.Preferences"], @"an app's key (an older version's entry) stays, as at the start");

        // L37 (review of track f, finding 1): the look's moments -- the App Switcher still up counts; a slide, a gesture or a transaction does not
        Reset();
        Minimized(kSetA);
        gKSwitcher = YES;
        Stages(@[Stage(@[kSafari])]);   // (Settings' card swiped away; the App Switcher is still up, its Dock there to tap)
        DMSMMinimizedLook();
        Check(![gKMin containsObject:kSetA] && !Pic(kSetA), @"L37: the App Switcher still up, the minimized window's card swiped away: its mark and picture go at once (its Dock can be tapped there)");
        Reset();
        Minimized(kSetA);
        gKBusy = YES;
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedLook();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"a workspace transaction under way (a window can be in no stage for a moment): nothing dropped");
        gKBusy = NO;
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedLook();
        Check(![gKMin containsObject:kSetA] && !Pic(kSetA), @"... the next look once it is over: the gone window's mark and picture go");
        Reset();
        Minimized(kSetA);
        gKGesture = YES;
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedLook();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"a switcher gesture under way: nothing dropped");
        gKGesture = NO; gMSWSwitching = YES;
        Stages(@[Stage(@[kSafari])]);
        DMSMMinimizedLook();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"a Mac Switcher slide under way: nothing dropped");
        gMSWSwitching = NO;
        Stages(@[Stage(@[kSafari]), Stage(@[kSetA])]);
        gKSwitcher = YES;
        DMSMMinimizedLook();
        Check([gKMin containsObject:kSetA] && Pic(kSetA), @"the App Switcher up, the minimized window still in its stage: kept (as before)");

        // L38 / O6: Reduce Motion
        Reset();
        gKRM = YES;
        Keep(kNotes);
        Check(!Pic(kNotes) && gKShots == 0, @"L38: Reduce Motion: no picture taken for the restore (Stage Manager's own appearance)");
        Check(Logged(@"Reduce Motion -- no picture kept"), @"L38: ... and the log says so");
        gKRM = NO; Keep(kNotes); gKRM = YES; Keep(kNotes);
        Check(!Pic(kNotes), @"L38: minimized again under Reduce Motion: its older picture goes too");
        gKRM = NO; Keep(kNotes);
        Check(Pic(kNotes), @"Reduce Motion off: the picture is kept (as before)");

        // L38 / O6: a memory warning lets the kept pictures go; one growing now (on screen, out of the store) stays
        Reset();
        Keep(kNotes); Keep(kMaps); Keep(kSafari);
        UIView *growing = [UIView new]; [win addSubview:growing]; gSMGrowing[kSetA] = growing;
        [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        Spin();
        Check(gSMMinPictures.count == 0, @"L38: UIKit's memory warning: the kept pictures are let go");
        Check(gSMGrowing[kSetA] == growing && growing.superview == win, @"L38: ... a picture growing out of the Dock right now stays on screen");
        Check(Logged(@"UIKit's memory warning: 3 minimized window picture(s) let go"), @"L38: ... and the log says how many");
        Keep(kNotes);
        Check(Pic(kNotes), @"after the warning: the next minimize keeps its picture again");

        // L38 / O6: the ninth picture pushes out the oldest, every time (the dictionary's order is not the age)
        BOOL oldestOut = YES, othersKept = YES;
        for (int r = 0; r < 12; r++) {
            Reset();
            NSMutableArray<NSString *> *ks = [NSMutableArray array];
            for (int i = 0; i < 9; i++) [ks addObject:[NSString stringWithFormat:@"com.example.app%d|sceneID:com.example.app%d-%02d%c", (r * 7 + i * 3) % 11, i, r, 'A' + (char)((i * 5 + r) % 26)]];
            for (int i = 0; i < 8; i++) Keep(ks[i]);
            Keep(ks[8]);
            if (Pic(ks[0])) oldestOut = NO;
            for (int i = 1; i < 9; i++) if (!Pic(ks[i])) othersKept = NO;
        }
        Check(oldestOut, @"L38: a ninth minimized window pushes out the oldest picture (12 sets of windows)");
        Check(othersKept && gSMMinPictures.count == 8, @"L38: ... and only it: the other seven and the new one stay");
        {
            Reset();
            NSMutableArray<NSString *> *ks = [NSMutableArray array];
            for (int i = 0; i < 9; i++) [ks addObject:[NSString stringWithFormat:@"com.example.again%d|sceneID:com.example.again%d-default", i, i]];
            for (int i = 0; i < 8; i++) Keep(ks[i]);
            Keep(ks[0]);   // (the first window, restored and minimized again: a new picture)
            Keep(ks[8]);
            Check(Pic(ks[0]) && !Pic(ks[1]), @"L38: a window minimized again counts from then: the next oldest goes");
        }

        // DMSMMinimizedDrop takes its keys' pictures, only theirs; a growing picture is never touched
        Reset();
        Minimized(kSetA); Minimized(kSetB);
        UIView *g2 = [UIView new]; [win addSubview:g2]; gSMGrowing[kSetA] = g2;
        DMSMMinimizedDrop([NSSet setWithObject:kSetA]);
        Check(![gKMin containsObject:kSetA] && !Pic(kSetA) && Pic(kSetB) && [gKMin containsObject:kSetB], @"L37: DMSMMinimizedDrop takes the marks and the pictures of exactly its keys");
        Check(gSMGrowing[kSetA] == g2 && g2.superview == win, @"... a picture growing now is not touched");

        // DMSMForgetApp (force quit): the app's pictures go, another app's stay; by app no grow of the closed window
        Reset();
        Minimized(kSetA); Minimized(kSetB); Minimized(kSafari);
        DMSMForgetApp(@"com.apple.Preferences");
        Check(!Pic(kSetA) && !Pic(kSetB) && ![gKMin containsObject:kSetA] && ![gKMin containsObject:kSetB], @"L38: a force quit takes the app's minimized windows' marks and pictures");
        Check(Pic(kSafari) && [gKMin containsObject:kSafari] && gKGrown.count == 0, @"L38: ... another app's stay, nothing grows");
        Reset();
        gKPerWindow = NO;
        Minimized(@"com.apple.Preferences");   // (windows told apart by app: the picture under the app's key)
        DMSMForgetApp(@"com.apple.Preferences");
        Check(gKGrown.count == 0 && !Pic(@"com.apple.Preferences"), @"L38: windows by app: a force quit no longer grows the closed window's picture out of the Dock");

        // as before: a minimized window opened again grows out of its Dock icon
        Reset();
        Minimized(kNotes);
        DMSMSetMinimized(kNotes, NO);
        Check([gKGrown isEqualToArray:@[kNotes]] && ![gKMin containsObject:kNotes], @"a minimized window opened again: its picture grows out of the Dock (as before)");
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
