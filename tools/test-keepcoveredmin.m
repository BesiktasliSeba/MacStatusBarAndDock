// test-keepcoveredmin.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the App menu's Minimize with Keep Covered Windows in Front (1.8.7.3, audit
// M10 of 1.8.7.2): Minimize minimizes the window of the app the menu bar names. With the switch on, a big Notes window tapped over a small Calculator
// window it covers completely comes forward and Calculator is kept above it; Notes stays the active one (the menu bar's app, the keyboard's). The
// App menu's Minimize took the top window instead: Calculator went away and Notes stayed.
// Runs the real DMMinimizeActiveApp and DMActiveApp, DMTopStageOn, DMTopStage, DMTopWindow, DMWindowsInFront and DMWindowsOwnStatusBar
// (statusbar/StatusBar.x), and Keep Covered's state, DMKeepCoveredFrame, DMKeepCoveredShows, DMKeepCoveredForget, DMKeepCoveredAfterRaise,
// DMKeepCoveredActive and DMKeepCoveredTouched (statusbar/KeepCovered.h), cut out of the sources by test-keepcoveredmin.sh into kcm-real.inc,
// with the real common/WindowOrder.h. SpringBoard's side (the windows of one engine in their layer, back to front; a window's own minimize; Home;
// the apps) is the stand-ins below, which record what they are asked.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "../common/WindowOrder.h"

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gKLog, *gKMarks;
static void KLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DMLog(...) KLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name) [gKMarks addObject:@name]

// ---- the apps
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static NSMutableDictionary<NSString *, SBApplication *> *gKApps;
static SBApplication *DMAppForBundle(NSString *bundleID) {
    if (!bundleID.length) return nil;
    SBApplication *a = gKApps[bundleID];
    if (!a) { a = [SBApplication new]; a.bundleIdentifier = bundleID; gKApps[bundleID] = a; }
    return a;
}

// ---- the engine and its windows: one layer, its subviews the windows back to front (Aerial's stages, Zetsu's windows, MilkyWay4's AXWindowViews)
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;   // (StatusBar.x's)
static DMEngine gKEngine; static BOOL gKSM;
static DMEngine DMActiveEngine(void) { return gKEngine; }
static BOOL DMSMEngine(void) { return gKSM; }
static BOOL gKeepCoveredInFront = NO, gMSWOpen = NO;
static UIView *gKLayer;
static const void *kKBundleKey = &kKBundleKey, *kKMinKey = &kKMinKey;
@interface AXWindowView : UIView   // (MilkyWay4's window)
- (NSString *)bundleIdentifier;
@end
@implementation AXWindowView
- (NSString *)bundleIdentifier { return objc_getAssociatedObject(self, kKBundleKey); }
@end
@interface KStage : UIView @end            // (an Aerial stage)
@implementation KStage @end
@interface KZetsuWindow : UIView @end      // (a Zetsu window)
@implementation KZetsuWindow @end
static NSArray<UIView *> *DMAerialStages(void) { return [gKLayer.subviews copy]; }   // (this desktop's windows, back to front)
static UIView *DMMilkyWayLayer(void) { return gKLayer; }
static NSString *DMStageBundle(UIView *stage) { return stage ? objc_getAssociatedObject(stage, kKBundleKey) : nil; }
static BOOL DMStageMinimized(UIView *stage) { return [objc_getAssociatedObject(stage, kKMinKey) boolValue]; }
static BOOL DMWindowMinimized(UIView *window) { return [objc_getAssociatedObject(window, kKMinKey) boolValue]; }
static const void *kStageClosingKey = &kStageClosingKey;
static UIScreen *DMSnapScreenOf(UIView *v) { return nil; }   // (one screen)
static BOOL DMIsZetsuWindow(UIView *v) { return [v isKindOfClass:[KZetsuWindow class]]; }
static CGRect DMA5WindowFromStage(CGRect f) { return f; }
static void DMApplyWindowLevel(void) {}
static double gKLevel;   // the windows' level: above the apps (1000), or behind a full-screen app (0)
static double DMDesiredWindowLevel(void) { return gKLevel; }
static SBApplication *gKFrontApp;   // the full-screen app (nil: the Home Screen)
static SBApplication *DMFrontApp(void) { return gKFrontApp; }
static NSString *gFullScreenActivatedBundle = nil;
static NSString *gPendingFrontBundle = nil;
static CFTimeInterval gPendingFrontUntil = 0;
static NSArray<UIWindow *> *DMZetsuWindows(void) { return @[]; }   // (no Zetsu windows next to another engine)
static NSString *DMZetsuWindowBundle(UIWindow *w) { return nil; }
static UIView *DMA5ComingBackTop(void) { return nil; }
// (the Stage Manager engine: its front window, by its key)
static NSString *gKSMFront;
static NSMutableArray<NSString *> *gKSMActions;
static NSString *DMSMFrontWindowBundle(void) { return gKSMFront; }
static NSString *DMSMFrontWindowKey(void) { return gKSMFront; }
static BOOL DMSMFrontIsFullScreen(void) { return NO; }
static NSString *DMSMKeyText(NSString *k) { return k; }
static BOOL DMSMWindowAction(NSString *key, NSString *name) { [gKSMActions addObject:[NSString stringWithFormat:@"%@ %@", name, key]]; return YES; }
// ---- what is asked: a window's own minimize (each as it ends: hidden), Home
static NSMutableArray<NSString *> *gKMinimized;
static void DMKeepCoveredAfterRaise(UIView *w, NSString *why);
static void DMEngineRaise(UIView *stage, NSString *why) {   // (WindowFront.h's: the engine's own raise puts it in front, then the Keep Covered rule)
    if (!stage) return;
    [stage.superview bringSubviewToFront:stage];
    DMKeepCoveredAfterRaise(stage, why);
}
static void DMMinimizeStage(UIView *stage) {
    [gKMinimized addObject:[NSString stringWithFormat:@"stage %@", DMStageBundle(stage)]];
    objc_setAssociatedObject(stage, kKMinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); stage.hidden = YES;
}
static void DMMinimizeWindow(UIView *window) {
    [gKMinimized addObject:[NSString stringWithFormat:@"window %@", DMStageBundle(window)]];
    objc_setAssociatedObject(window, kKMinKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); window.hidden = YES;
}
static void DMMinimize(void) { [gKMinimized addObject:@"home"]; }

#include "kcm-real.inc"

// ---- the checks
static int gFails = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    printf("%s  %s%s\n", ok ? "PASS" : "FAIL", what.UTF8String, ok ? "" : [NSString stringWithFormat:@" (got: %@)", got].UTF8String);
    if (!ok) gFails++;
}
static NSString *Names(NSArray *a) { return a.count ? [a componentsJoinedByString:@", "] : @"nothing"; }

static NSString *const kNotes = @"com.apple.mobilenotes", *const kCalc = @"com.apple.calculator", *const kSafari = @"com.apple.mobilesafari";
static void Fresh(DMEngine e, BOOL keepCovered) {
    gKLog = [NSMutableArray array]; gKMarks = [NSMutableArray array]; gKMinimized = [NSMutableArray array]; gKSMActions = [NSMutableArray array];
    gKApps = [NSMutableDictionary dictionary];
    gKEngine = e; gKSM = NO; gKSMFront = nil; gKeepCoveredInFront = keepCovered; gMSWOpen = NO;
    gKLevel = 1000; gKFrontApp = nil; gFullScreenActivatedBundle = nil; gPendingFrontBundle = nil;
    gDMKeptUnder = nil; [gDMKeptAbove removeAllObjects]; gDMKeepLastTop = nil; gDMKeepCoveredBusy = NO;
    gKLayer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1180, 820)];
}
static UIView *Window(NSString *bundle, CGRect f) {   // a window of the engine, opened in front
    Class c = gKEngine == DMEngineMilkyWay ? [AXWindowView class] : gKEngine == DMEngineZetsu ? [KZetsuWindow class] : [KStage class];
    UIView *v = [[c alloc] initWithFrame:f];
    objc_setAssociatedObject(v, kKBundleKey, bundle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [gKLayer addSubview:v];
    gDMKeepLastTop = DMTopStage();
    return v;
}
// A tap in a window, as DMRaiseStageForBundle does it: one in front already is touched where it is; any other is raised by the engine.
static void Tap(UIView *w) { if (DMTopStage() == w) DMKeepCoveredTouched(w); else DMEngineRaise(w, @"a tap or click in it"); }
static NSString *Named(void) { return [DMActiveApp() bundleIdentifier] ?: @"(none)"; }
static NSString *Gone(void) {   // the one thing Minimize asked, as "<bundle>" (a window of it) or "home"
    if (gKMinimized.count != 1) return Names(gKMinimized);
    NSString *s = gKMinimized[0];
    NSRange r = [s rangeOfString:@" "];
    return r.location == NSNotFound ? s : [s substringFromIndex:r.location + 1];
}
static const char *EngineName(DMEngine e) { return e == DMEngineAerial ? "Aerial" : e == DMEngineZetsu ? "Zetsu" : "MilkyWay4"; }

int main(void) {
    @autoreleasepool {
        gDMKeptAbove = [NSHashTable weakObjectsHashTable];
        CGRect big = CGRectMake(100, 80, 900, 640), small = CGRectMake(400, 250, 300, 300), side = CGRectMake(820, 500, 300, 250);
        for (DMEngine e = DMEngineMilkyWay; e <= DMEngineZetsu; e++) {
            const char *en = EngineName(e);
            NSString *kind = e == DMEngineMilkyWay ? @"window" : @"stage";
            // (1) the audit's case: Notes tapped over the small Calculator it covers: Calculator kept above it, Notes the active one
            Fresh(e, YES);
            UIView *notes = Window(kNotes, big), *calc = Window(kCalc, small);
            Tap(notes);
            BOOL keptOver = DMTopStage() == calc && [gDMKeptAbove containsObject:calc] && gDMKeptUnder == notes;
            NSString *named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s, Keep Covered on: Notes tapped over the Calculator it covers: Calculator is kept above it, the menu bar names Notes", en],
                  keptOver && [named isEqualToString:kNotes], [NSString stringWithFormat:@"kept above %d, named %@", keptOver, named]);
            Check([NSString stringWithFormat:@"  ... %s: the App menu's Minimize minimizes Notes' %@ (the app the menu names), not Calculator's", en, kind],
                  [gKMinimized isEqualToArray:@[[NSString stringWithFormat:@"%@ %@", kind, kNotes]]], Names(gKMinimized));
            Check([NSString stringWithFormat:@"  ... %s: Calculator stays on screen, and the menu bar names it now", en],
                  !calc.hidden && !DMStageMinimized(calc) && !DMWindowMinimized(calc) && [Named() isEqualToString:kCalc], [NSString stringWithFormat:@"calc hidden %d, named %@", calc.hidden, Named()]);
            {
                NSString *line = nil; for (NSString *l in gKLog) if ([l hasPrefix:@"[action] minimize active app:"]) line = l;
                Check([NSString stringWithFormat:@"  ... %s: the log names the top window and the active one", en],
                      [line hasSuffix:[NSString stringWithFormat:@"top stage %@, active window %@", kCalc, kNotes]], line ?: @"no line");
            }
            // (2) the kept window touched: it is the active one now, and Minimize minimizes it
            Fresh(e, YES);
            notes = Window(kNotes, big); calc = Window(kCalc, small);
            Tap(notes); Tap(calc);
            named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s: the kept Calculator touched: the menu bar names it and Minimize minimizes it (Notes stays)", en],
                  [named isEqualToString:kCalc] && [Gone() isEqualToString:kCalc] && !notes.hidden, [NSString stringWithFormat:@"named %@, minimized %@", named, Names(gKMinimized)]);
            // (3) the kept window no longer inside Notes (moved partly out): an ordinary top window again, the active one, and the one minimized
            Fresh(e, YES);
            notes = Window(kNotes, big); calc = Window(kCalc, small);
            Tap(notes);
            calc.frame = CGRectMake(850, 250, 300, 300);   // (a corner out of Notes)
            named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s: the kept Calculator partly out of Notes: the menu bar names Calculator, and Minimize minimizes it", en],
                  [named isEqualToString:kCalc] && [Gone() isEqualToString:kCalc] && !notes.hidden, [NSString stringWithFormat:@"named %@, minimized %@", named, Names(gKMinimized)]);
            // (4) another window tapped over both since: that one is the active one and the one minimized
            Fresh(e, YES);
            notes = Window(kNotes, big); calc = Window(kCalc, small); UIView *safari = Window(kSafari, side);
            Tap(notes); Tap(safari);
            named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s: Safari tapped since (it covers neither completely): the menu bar names Safari, and Minimize minimizes it", en],
                  [named isEqualToString:kSafari] && [Gone() isEqualToString:kSafari] && !notes.hidden && !calc.hidden, [NSString stringWithFormat:@"named %@, minimized %@", named, Names(gKMinimized)]);
            // (5) unchanged: Keep Covered off, Notes tapped over Calculator: Notes on top, the one named and minimized
            Fresh(e, NO);
            notes = Window(kNotes, big); calc = Window(kCalc, small);
            Tap(notes);
            BOOL notesOnTop = DMTopStage() == notes;
            named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s, Keep Covered off (unchanged): Notes tapped over Calculator is on top; the menu bar names it, and Minimize minimizes it", en],
                  notesOnTop && [named isEqualToString:kNotes] && [Gone() isEqualToString:kNotes] && !calc.hidden, [NSString stringWithFormat:@"named %@, minimized %@", named, Names(gKMinimized)]);
            // (6) unchanged: the windows behind a full-screen app (not in front): Minimize goes Home, no window minimizes
            Fresh(e, YES);
            notes = Window(kNotes, big); calc = Window(kCalc, small);
            Tap(notes);
            gKLevel = 0; gKFrontApp = DMAppForBundle(kSafari);
            named = Named();
            DMMinimizeActiveApp();
            Check([NSString stringWithFormat:@"%s (unchanged): the windows behind a full-screen app: the menu bar names that app, and Minimize goes Home", en],
                  [named isEqualToString:kSafari] && [gKMinimized isEqualToArray:@[@"home"]] && !notes.hidden && !calc.hidden, [NSString stringWithFormat:@"named %@, minimized %@", named, Names(gKMinimized)]);
        }
        // (7) Stage Manager as the engine (unchanged; Keep Covered is off there for now): its front window minimizes, that very window
        Fresh(DMEngineNone, YES);
        gKSM = YES; gKSMFront = @"com.apple.mobilenotes|scene-2";
        DMMinimizeActiveApp();
        Check(@"Stage Manager (unchanged): Minimize minimizes the front window, that very one",
              [gKSMActions isEqualToArray:@[@"removeFromSet com.apple.mobilenotes|scene-2"]] && gKMinimized.count == 0, Names(gKSMActions));
    }
    printf("%s: %d check(s) failed\n", gFails ? "FAIL" : "PASS", gFails);
    return gFails;
}
