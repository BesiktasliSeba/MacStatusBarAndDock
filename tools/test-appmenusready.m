// test-appmenusready.m -- see test-appmenusready.sh. B12: the app's own menus come at a cold launch as soon as MacAppBridge can answer, not at
// the next minute's layout; and (B12's thin first answer, 20 Nov) what the app offers after its answer comes too, with no tap. The real code, cut
// out of statusbar/AppMenus.h (SpringBoard's side: gAMOn to DMAMFrontSeen, and DMAMApplyPref: sb-block.inc) and appbridge/AppMenus.h (the app's:
// the whole file but for where it finds the app's window, responders and main menu, and the pick: app-block.inc), both in this process, on the
// Mac's own notifyd and main run loop (real Darwin notifications, every name under a prefix of this run's, TPFX, so nothing else on the Mac hears
// them; real UIKeyCommand, UICommand, UIMenu, UIResponder and Mac Catalyst UIKit's own main menu system). The app's snapshot is the real one, on
// responders of the test's own (their key commands and the actions they take) and a main menu the test builds; it writes its real answer file.
// Stand-ins: the bar's app (DMActiveApp, its process's pid), its data container (a temp folder), the bar's copies (one view that counts layouts),
// the app's key window, its first responder and its main menu as UIKit would hand them (MABMenuKeyWindow, MABMenuStart, MABMenuRoot), DMLog,
// MABLog. One scenario per process (argv[1]); no UIApplicationMain, no window on screen.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <notify.h>
#include <sys/stat.h>
#include "AppMenuRules.h"

static NSString *gBundle, *gContainer;
static const char *TSwitchName(void) { static char n[96]; if (!n[0]) snprintf(n, sizeof n, TPFX "%d.appmenus", getpid()); return n; }
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; if (getenv("AMR_VERBOSE")) printf("  log %.3f %s\n", CACurrentMediaTime(), s.UTF8String); }
static CFTimeInterval gLaidAt;   // (the last time the bar was laid out again: SpringBoard took new titles)
@interface TView : UIView
@property (nonatomic) int layouts;
@end
@implementation TView
- (void)setNeedsLayout { self.layouts++; gLaidAt = CACurrentMediaTime(); }
@end
static NSHashTable *gCopies;
static UIView *gOverlay;   // (one of our menus open: SpringBoard's own, StatusBar.x)
@interface TProc : NSObject
@property (nonatomic) int pid;
@end
@implementation TProc
@end
@interface TApp : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, strong) TProc *processState;
@end
@implementation TApp
@end
@compatibility_alias SBApplication TApp;
static TApp *gFront;
static SBApplication *DMActiveApp(void) { return gFront; }
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return obj && [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
static NSURL *DMFDContainer(NSString *bundle) { return [bundle isEqualToString:gBundle] ? [NSURL fileURLWithPath:gContainer] : nil; }
#include "sb-block.inc"

// ---- the app's side --------------------------------------------------------------------------------------------------------------------------
// A responder of the app: its next responder, its key commands (made anew at every read, as most apps' getters do; a title can change at every
// read, as Play / Pause), and the actions it takes.
@interface TResp : UIResponder
@property (nonatomic, strong) UIResponder *up;
@property (nonatomic, copy) NSArray<NSArray *> *kc;   // (title, action name, input, modifiers)
@property (nonatomic, copy) NSSet<NSString *> *acts;
@property (nonatomic) BOOL toggles;                    // (its first command's title is Play, then Pause, at every read)
@property (nonatomic) int reads;
@end
@implementation TResp
- (UIResponder *)nextResponder { return self.up; }
- (NSArray<UIKeyCommand *> *)keyCommands {
    self.reads++;
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *k in self.kc) {
        NSString *title = self.toggles && !out.count ? (self.reads % 2 ? @"Play" : @"Pause") : k[0];
        [out addObject:[UIKeyCommand commandWithTitle:title image:nil action:NSSelectorFromString(k[1]) input:k[2] modifierFlags:[k[3] integerValue] propertyList:nil]];
    }
    return out;
}
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender { return [self.acts containsObject:NSStringFromSelector(action)]; }
- (void)validateCommand:(UICommand *)command {}
@end
static NSString *TBundle(void) { return gBundle; }
static NSString *TTmp(void) { return [gContainer stringByAppendingPathComponent:@"tmp"]; }
static UIWindow *gWin;
static UIResponder *gStart;
static UIMenu *gRoot;
static int gSnapshots, gPartialLeft, gKeyWindowCalls;
static BOOL gAway;   // (no window of the app in front: it is in the background)
static UIWindow *MABMenuKeyWindow(void) { gKeyWindowCalls++; return gPartialLeft > 0 || gAway ? nil : gWin; }
static UIResponder *MABMenuStart(UIWindow *key) { return gStart; }
static UIMenu *MABMenuRoot(void) { gSnapshots++; if (gPartialLeft > 0) { gPartialLeft--; return nil; } return gRoot; }   // (once per snapshot)
static void MABMenuPerform(uint64_t state) {}
#if DEBUG
static NSMutableArray<NSString *> *gMABLines;
static void MABLog(NSString *s) { if (!gMABLines) gMABLines = [NSMutableArray array]; [gMABLines addObject:s]; if (getenv("AMR_VERBOSE")) printf("  mab %.3f %s\n", CACurrentMediaTime(), s.UTF8String); }
static BOOL MSTestFlag(const char *p) { return NO; }
#endif
// (the app's reads of a notify state, counted: in these scenarios only MABMenusOn's of the switch. A look that stops at the switch reads nothing
//  else, so this is what sees it: B12 review, finding 2)
static int gSwitchReads;
static uint32_t TGetState(int token, uint64_t *state) { gSwitchReads++; return notify_get_state(token, state); }
#define notify_get_state TGetState
#include "app-block.inc"
#undef notify_get_state

// ---- the scenarios -------------------------------------------------------------------------------------------------------------------------
static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Run(double s) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, s, false); }   // (one call: the run loop waits between what comes)
static uint32_t Hash(NSString *b) { uint32_t h = 2166136261u; for (const char *c = b.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 16777619u; } return h; }
static int gAsks, gHellos, gChanged;
static NSMutableArray<NSNumber *> *gChangedAt, *gAskedAt;   // (when each menuschanged and each ask was heard)
static void Count(const char *what, int *n) {   // (a listener of our own, as nwatch on the M1: counts the posts of one name)
    char name[128]; snprintf(name, sizeof name, TPFX "%s.%08x", what, Hash(gBundle));
    NSMutableArray *at = !strcmp(what, "menuschanged") ? gChangedAt : !strcmp(what, "menus") ? gAskedAt : nil;
    int t = 0; notify_register_dispatch(name, &t, dispatch_get_main_queue(), ^(int tok) { (*n)++; [at addObject:@(CACurrentMediaTime())]; });
}
// The shortest time between two menuschanged heard since `from` (99: fewer than two)
static double MinGap(CFTimeInterval from) {
    double gap = 99, prev = -1;
    for (NSNumber *n in gChangedAt) { if (n.doubleValue < from) continue; if (prev >= 0 && n.doubleValue - prev < gap) gap = n.doubleValue - prev; prev = n.doubleValue; }
    return gap;
}
static void Post(const char *what) { char name[128]; snprintf(name, sizeof name, TPFX "%s.%08x", what, Hash(gBundle)); notify_post(name); }
static NSArray<NSString *> *Titles(void) { return DMAMTitlesIn(gAMSnap[gBundle]); }
static NSString *TitlesText(void) { return Titles().count ? [Titles() componentsJoinedByString:@", "] : @"none"; }
static BOOL HasMenus(void) { return [Titles() containsObject:@"File"]; }
// Waits up to s seconds for the titles; the time it took (-1: they never came)
static double WaitMenus(double s) {
    CFTimeInterval t0 = CACurrentMediaTime();
    while (!HasMenus() && CACurrentMediaTime() - t0 < s) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
    return HasMenus() ? CACurrentMediaTime() - t0 : -1;
}
static TApp *App(NSString *b) { TApp *a = [TApp new]; a.bundleIdentifier = b; a.processState = [TProc new]; a.processState.pid = getpid(); return a; }
static TResp *Resp(UIResponder *up, NSArray *acts, NSArray *kc) { TResp *r = [TResp new]; r.up = up; r.acts = [NSSet setWithArray:acts ?: @[]]; r.kc = kc ?: @[]; return r; }
static UICommand *Cmd(NSString *t, NSString *a) { return [UICommand commandWithTitle:t image:nil action:NSSelectorFromString(a) propertyList:nil]; }
static UIMenu *Top(UIMenuIdentifier ident, NSArray *children) { return [UIMenu menuWithTitle:@"" image:nil identifier:ident options:0 children:children]; }
static UIMenu *Root(NSArray *tops) { return [UIMenu menuWithTitle:@"" image:nil identifier:UIMenuRoot options:0 children:tops]; }
// Something of the app's own on its main queue every `every` s for s seconds (a layout, a timer of its own): its run loop is busy, then waits.
static void Busy(double every, double s) {
    for (double t = every; t < s; t += every) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{});
    Run(s);
}
static int Looks(void) { return gKeyWindowCalls - gSnapshots; }   // (each snapshot asks for the key window once; a look does the rest)
static NSString *Took(double t) { return t < 0 ? @"never" : [NSString stringWithFormat:@"%.3f s", t]; }
// Where its commands start moves every 0.5 s (a carousel's pages: a new responder each time, under `up`) until gFlapStop
static BOOL gFlapStop;
static void Flap(UIResponder *up) {
    if (gFlapStop) return;
    gStart = Resp(up, nil, nil);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Flap(up); });
}

// Maps (this Mac's Maps 3.0 read for the B12 record, and the iPads' rows): its main menu, File, Edit and View, whole at once; its home card's
// sections' key commands, which its card sets once its library is in (HomeSection -keyCommand), sorted into Bookmarks and Actions
static NSArray *MapsActs(void) { return @[@"newWindow:", @"printMap:", @"dropPin:", @"exploreMap:", @"zoomIn:", @"seeAll:"]; }
static UIMenu *MapsRoot(void) {
    return Root(@[Top(UIMenuFile, @[Cmd(@"New Window", @"newWindow:"), Cmd(@"Print", @"printMap:")]),
                  Top(UIMenuEdit, @[Cmd(@"Undo", @"undoMap:"), Cmd(@"Drop Pin", @"dropPin:")]),
                  Top(UIMenuView, @[Cmd(@"Explore Map", @"exploreMap:"), Cmd(@"Zoom In", @"zoomIn:")])]);
}
static NSArray *MapsCard(void) {
    long m = UIKeyModifierCommand | UIKeyModifierAlternate;
    return @[@[@"See All Favorites", @"seeAll:", @"1", @(m)], @[@"See All My Guides", @"seeAll:", @"2", @(m)], @[@"See All Recents", @"seeAll:", @"3", @(m)]];
}
static NSArray *kMapsThin, *kMapsFull, *kFilesThin, *kFilesFull;
// Files: its key command "Go to Folder" (Actions) at once; its File (New Folder) and View (as Icons, as List) later -- either from a main menu it
// asks UIKit to rebuild once its browser is up, or from a main menu whose commands only its browser takes, once the browser is where its commands
// start (Files is not on this Mac: both cases, the record's two readings)
static UIMenu *FilesRoot(void) {
    return Root(@[Top(UIMenuFile, @[Cmd(@"New Folder", @"newFolder:")]), Top(UIMenuView, @[Cmd(@"as Icons", @"asIcons:"), Cmd(@"as List", @"asList:")])]);
}
static NSArray *FilesKeys(void) { return @[@[@"Go to Folder", @"goToFolder:", @"G", @(UIKeyModifierCommand | UIKeyModifierShift)]]; }

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) return 2;
        NSString *sc = @(argv[1]);
        gBundle = [NSString stringWithFormat:@"test.b12.app.%d", getpid()];
        gContainer = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"amr-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:[gContainer stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
        gCopies = [NSHashTable weakObjectsHashTable];
        TView *bar = [[TView alloc] initWithFrame:CGRectMake(0, 0, 1000, 24)];
        [gCopies addObject:bar];
        gChangedAt = [NSMutableArray array]; gAskedAt = [NSMutableArray array];
        Count("menus", &gAsks); Count("menushere", &gHellos); Count("menuschanged", &gChanged);
        kMapsThin = @[@"File", @"Edit", @"View"]; kMapsFull = @[@"File", @"Edit", @"View", @"Bookmarks", @"Actions"];
        kFilesThin = @[@"Actions"]; kFilesFull = @[@"File", @"View", @"Actions"];
        gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];   // (its scene, as Mac Catalyst UIKit gives one here, reads as in front)
        UIResponder *appR = Resp(nil, nil, nil);
        // the default app (B12's first scenarios): File (New Tab) and View (Reload), both from its main menu
        gRoot = Root(@[Top(UIMenuFile, @[Cmd(@"New Tab", @"newTab:")]), Top(UIMenuView, @[Cmd(@"Reload", @"reload:")])]);
        gStart = Resp(appR, @[@"newTab:", @"reload:"], nil);
        DMAMApplyPref(YES);   // (published for the app, as SpringBoard's DMLoadPrefs does)
        TApp *app = App(gBundle);
        if ([sc isEqualToString:@"cold"]) {
            // Reynard cold on the M1 (r1, r6, r9): the bar sees it in front 0.1-0.3 s after the launch and asks; MacAppBridge registers ~1.1 s
            // after the launch. No layout of the bar after that (an idle bar lays out once a minute).
            gFront = app; DMAMFrontSeen(app);
            Run(1.0);
            Check(gSnapshots == 0 && !HasMenus(), @"cold: the ask sent when it came to the front is lost (nobody registered yet)");
            MABRegisterMenus();
            double t = WaitMenus(3.0);
            Check(t >= 0 && t <= 0.5, [NSString stringWithFormat:@"cold: the titles come within 0.5 s of MacAppBridge's registration, with no layout of the bar (took %@)", t < 0 ? @"never, 3 s" : [NSString stringWithFormat:@"%.3f s", t]]);
            Run(2.0);
            Check(gHellos == 1, [NSString stringWithFormat:@"cold: the app says once that it can answer (%d)", gHellos]);
            Check(gAsks <= 2 && gSnapshots <= 1, [NSString stringWithFormat:@"cold: no more asks than the front change and the one after the app's word (%d asks, %d snapshots)", gAsks, gSnapshots]);
            Check(bar.layouts >= 1, @"cold: the bar is laid out again with the titles");
        } else if ([sc isEqualToString:@"warm"]) {
            MABRegisterMenus();   // (the app was running: its handlers are in)
            Run(0.3);
            gFront = app; DMAMFrontSeen(app);
            double t = WaitMenus(1.0);
            Check(t >= 0 && t <= 0.5, [NSString stringWithFormat:@"warm: the switch's ask is answered at once, as before (%.3f s)", t]);
            Run(2.0);
            Check(gAsks == 1 && gChanged == 0, [NSString stringWithFormat:@"warm: one ask, no menuschanged after it (%d asks, %d menuschanged)", gAsks, gChanged]);
        } else if ([sc isEqualToString:@"early"]) {
            // the app registers before the bar has ever asked it (its word goes unheard: SpringBoard listens once it has asked it); then it comes forward
            MABRegisterMenus();
            Run(0.3);
            Check(gSnapshots == 0, @"early: its word, unheard, makes no snapshot");
            gFront = app; DMAMFrontSeen(app);
            double t = WaitMenus(1.0);
            Check(t >= 0 && t <= 0.5, [NSString stringWithFormat:@"early: the ask when it comes to the front is answered at once (%.3f s)", t]);
        } else if ([sc isEqualToString:@"notfront"]) {
            // it was asked, then another app came to the front before MacAppBridge registered in it: its word asks nothing
            gFront = app; DMAMFrontSeen(app);
            Run(0.2);
            TApp *other = App(@"test.b12.other"); gFront = other; DMAMFrontSeen(other);
            Run(0.8);
            MABRegisterMenus();
            Run(2.5);
            Check(gHellos == 1 && gSnapshots == 0 && !HasMenus(), [NSString stringWithFormat:@"notfront: not the app in front: no ask after its word, no snapshot (%d words, %d snapshots)", gHellos, gSnapshots]);
        } else if ([sc isEqualToString:@"off"]) {
            DMAMApplyPref(NO);   // (Show Apps' Own Menus off: published as 2)
            gFront = app; DMAMFrontSeen(app);
            Run(0.5);
            MABRegisterMenus();
            Busy(0.1, 2.0);
            Check(gHellos == 0 && gAsks == 0 && gSnapshots == 0 && !HasMenus(), [NSString stringWithFormat:@"off: no word, no ask, no snapshot, no titles (%d, %d, %d)", gHellos, gAsks, gSnapshots]);
            Check(gKeyWindowCalls == 0, [NSString stringWithFormat:@"off: the app never looks at what it offers (%d)", gKeyWindowCalls]);
        } else if ([sc isEqualToString:@"once"]) {
            gFront = app; DMAMFrontSeen(app);
            Run(0.5);
            MABRegisterMenus();
            WaitMenus(1.0);
            for (NSNotificationName nn in @[UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification]) {
                [[NSNotificationCenter defaultCenter] postNotificationName:nn object:nil];
                Run(0.4);
            }
            Run(1.5);
            Check(gHellos == 1, [NSString stringWithFormat:@"once: the word once per process, not at a window or scene change (%d)", gHellos]);
            Check(gChanged == 2, [NSString stringWithFormat:@"once: a window or scene change still posts menuschanged, as before (%d)", gChanged]);
        } else if ([sc isEqualToString:@"partial"]) {
            // its first answer is thin (no window of it in front yet): asked again 1 s later, as before (review M5)
            gPartialLeft = 1;
            gFront = app; DMAMFrontSeen(app);
            Run(1.0);
            MABRegisterMenus();
            double t = WaitMenus(2.5);
            Check(t >= 0.9 && t <= 1.8, [NSString stringWithFormat:@"partial: a thin first answer is asked again 1 s later and the titles come (%@)", t < 0 ? @"never" : [NSString stringWithFormat:@"%.3f s", t]]);
        } else if ([sc isEqualToString:@"relaunch"]) {
            // its process relaunched while in front (the old process's answer is in, from another pid): dropped, and the new one's titles come
            // at its registration
            gFront = app; DMAMFrontSeen(app);   // (lost)
            NSDictionary *old = @{@"b": gBundle, @"m": @[@{@"t": @"Tabs", @"r": @[@{@"t": @"Old", @"x": @9, @"e": @YES}]}], @"n": @1, @"p": @(1), @"partial": @NO};
            if (!gAMSnap) gAMSnap = [NSMutableDictionary dictionary];
            gAMSnap[gBundle] = old;
            Run(0.3);
            DMAMFrontSeen(app);   // (a layout: the answer is from a process that has gone)
            Check(!gAMSnap[gBundle], @"relaunch: the old process's answer is dropped");
            Run(0.7);
            MABRegisterMenus();
            double t = WaitMenus(2.0);
            Check(t >= 0 && t <= 0.5, [NSString stringWithFormat:@"relaunch: the new process's titles come at its registration (%@)", t < 0 ? @"never" : [NSString stringWithFormat:@"%.3f s", t]]);
        } else {
            // ---- B12's thin first answer: a cold launch whose answer is right for its moment, then what the app offers moves with no tap --------
            TResp *chrome = Resp(appR, MapsActs(), nil), *card = nil, *browser = nil;
            BOOL files = [sc hasPrefix:@"files"];
            if (files) {
                gRoot = [sc isEqualToString:@"filesrebuild"] ? nil : FilesRoot();
                chrome = Resp(appR, [sc isEqualToString:@"filesrebuild"] ? @[@"goToFolder:", @"newFolder:", @"asIcons:", @"asList:"] : @[@"goToFolder:"], FilesKeys());
                browser = Resp(chrome, @[@"newFolder:", @"asIcons:", @"asList:"], nil);
            } else if ([sc isEqualToString:@"nomenus"] || [sc isEqualToString:@"flap"]) {
                gRoot = nil;
                chrome = Resp(appR, nil, nil);
            } else if ([sc isEqualToString:@"steady"]) {
                // Reynard / Safari: their whole set at once (here File and View from its main menu, Tabs and Actions from key commands made anew
                // at every read, one of whose titles changes at every read, Play / Pause)
                long m = UIKeyModifierCommand;
                chrome = Resp(appR, @[@"newTab:", @"reload:", @"playPause:", @"nextTab:"], @[@[@"Play", @"playPause:", @"P", @(m | UIKeyModifierAlternate)], @[@"Show Next Tab", @"nextTab:", @"]", @(m | UIKeyModifierShift)]]);
                chrome.toggles = YES;
            } else {
                gRoot = MapsRoot();
                card = Resp(chrome, @[@"seeAll:"], nil);
            }
            gStart = chrome;
            gFront = app; DMAMFrontSeen(app);   // (lost: it isn't listening yet)
            Run(0.3);
            MABRegisterMenus();
            Run(2.0);   // (its answer, ~15 ms after its word)
            NSArray *first = Titles();
            int asks0 = gAsks, changed0 = gChanged, snaps0 = gSnapshots;
            if ([sc isEqualToString:@"grows"] || [sc isEqualToString:@"moves"] || [sc isEqualToString:@"openmenu"] || [sc isEqualToString:@"away"] || [sc isEqualToString:@"offlater"]) {
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer, a moment after it opened: File, Edit, View (%@)", sc, TitlesText()]);
                if ([sc isEqualToString:@"moves"]) card.kc = MapsCard();   // (the card's commands are there, not yet where its commands start)
                // something of its own at -0.3 s, the card's commands at 0, then nothing at all (an idle app: its run loop waits)
                Busy(0.05, 0.3);
                if ([sc isEqualToString:@"openmenu"]) gOverlay = [UIView new];   // (our Go menu opened)
                if ([sc isEqualToString:@"away"]) gAway = YES;
                if ([sc isEqualToString:@"offlater"]) DMAMApplyPref(NO);
                int looks0 = Looks();
                CFTimeInterval c = CACurrentMediaTime(); gLaidAt = 0;
                if ([sc isEqualToString:@"moves"]) gStart = card;   // (fork b: where its commands start moved to the card)
                else chrome.kc = MapsCard();                         // (fork a: the card's commands, on the chain, came with its library)
                if ([sc isEqualToString:@"openmenu"]) {
                    Run(3.0);
                    Check(gAsks == asks0 && [Titles() isEqualToArray:kMapsThin], [NSString stringWithFormat:@"openmenu: not asked while one of our menus is open, the titles not moved under it (%d asks, %@)", gAsks - asks0, TitlesText()]);
                    Check(gChanged - changed0 == 1, [NSString stringWithFormat:@"openmenu: the app said so once (%d menuschanged)", gChanged - changed0]);
                    c = CACurrentMediaTime(); gOverlay = nil;   // (closed)
                    Run(2.5);
                    double t = gLaidAt > 0 ? gLaidAt - c : -1;
                    // (SpringBoard's wait under one of our menus looks again once a second, so the ask after a close comes up to 1 s after it, plus
                    //  the answer and the Mac's load: 1.6 s, not 1.3 -- the B12 review fixes' review, note 4)
                    Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 1.6, [NSString stringWithFormat:@"openmenu: once it is closed, the full set within 1.6 s (%@, %@)", TitlesText(), Took(t)]);
                    Check(gAsks - asks0 == 1, [NSString stringWithFormat:@"openmenu: one ask for it (%d)", gAsks - asks0]);
                } else if ([sc isEqualToString:@"away"]) {
                    Busy(0.1, 3.0);
                    Check(gChanged == changed0 && gAsks == asks0, [NSString stringWithFormat:@"away: with no window of it in front, no menuschanged and no ask (%d, %d)", gChanged - changed0, gAsks - asks0]);
                    gAway = NO; c = CACurrentMediaTime(); gLaidAt = 0;
                    Busy(0.1, 3.0);
                    double t = gLaidAt > 0 ? gLaidAt - c : -1;
                    Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 2.5, [NSString stringWithFormat:@"away: in front again, the full set within 2.5 s (%@, %@)", TitlesText(), Took(t)]);
                } else if ([sc isEqualToString:@"offlater"]) {
                    int reads0 = gSwitchReads;
                    Busy(0.1, 3.0);
                    Check(gChanged == changed0 && gAsks == asks0 && gSnapshots == snaps0, [NSString stringWithFormat:@"offlater: switched off after its answer: no menuschanged, no ask, no snapshot (%d, %d, %d)", gChanged - changed0, gAsks - asks0, gSnapshots - snaps0]);
                    Check(Looks() - looks0 <= 1 && gSwitchReads - reads0 <= 1, [NSString stringWithFormat:@"offlater: and it stops looking (%d looks, %d reads of the switch in 3 s of activity)", Looks() - looks0, gSwitchReads - reads0]);
                } else {
                    Run(4.0);
                    double t = gLaidAt > 0 ? gLaidAt - c : -1;
                    Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 2.5, [NSString stringWithFormat:@"%@: the full set (File, Edit, View, Bookmarks, Actions) within 2.5 s, with no tap and nothing else happening (%@, %@)", sc, TitlesText(), Took(t)]);
                    Check(gChanged - changed0 == 1 && gAsks - asks0 == 1, [NSString stringWithFormat:@"%@: one menuschanged and one ask for it (%d, %d)", sc, gChanged - changed0, gAsks - asks0]);
                    asks0 = gAsks; changed0 = gChanged;
                    Busy(0.1, 4.0);
                    Check(gAsks == asks0 && gChanged == changed0, [NSString stringWithFormat:@"%@: then nothing more while it stays busy: no ask, no menuschanged in 4 s (%d, %d)", sc, gAsks - asks0, gChanged - changed0]);
#if DEBUG
                    BOOL said = NO, snapLine = NO;
                    for (NSString *l in gMABLines) {
                        if ([l hasPrefix:@"appmenus: what it offers moved since its answer (start TResp "] && [l containsString:@"): menuschanged at "]) said = YES;
                        if ([l hasPrefix:@"appmenus: snapshot: of them "] && [l containsString:@" key commands; focused "]) snapLine = YES;
                    }
                    Check(said && snapLine, [NSString stringWithFormat:@"%@ (debug): the look's line and the snapshot's sources line are logged (%d, %d)", sc, said, snapLine]);
#endif
                }
            } else if (files) {
                Check([first isEqualToArray:kFilesThin], [NSString stringWithFormat:@"%@: its first answer: Actions only (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                CFTimeInterval c = CACurrentMediaTime(); gLaidAt = 0;
                if ([sc isEqualToString:@"filesrebuild"]) dispatch_async(dispatch_get_main_queue(), ^{ gRoot = FilesRoot(); [[UIMenuSystem mainSystem] setNeedsRebuild]; });   // (the app's own word)
                else gStart = browser;   // (its browser came: where its commands start moved)
                Run(4.0);
                double t = gLaidAt > 0 ? gLaidAt - c : -1;
                Check([Titles() isEqualToArray:kFilesFull] && t >= 0 && t <= 2.5, [NSString stringWithFormat:@"%@: File, View, Actions within 2.5 s, with no tap (%@, %@)", sc, TitlesText(), Took(t)]);
                Check(gAsks - asks0 == 1, [NSString stringWithFormat:@"%@: one ask for it (%d)", sc, gAsks - asks0]);
            } else if ([sc isEqualToString:@"steady"]) {
                Check([first isEqualToArray:@[@"File", @"View", @"Tabs", @"Actions"]], [NSString stringWithFormat:@"steady: its whole set at once (%@)", TitlesText()]);
                int looks0 = Looks(), reads0 = gSwitchReads;
                Busy(0.1, 5.0);
                Check(gAsks == asks0 && gChanged == changed0, [NSString stringWithFormat:@"steady: busy for 5 s with nothing it offers moving (new key command objects at every read, a title Play / Pause): no menuschanged, no ask (%d, %d)", gChanged - changed0, gAsks - asks0]);
                Check(Looks() - looks0 >= 3 && Looks() - looks0 <= 7, [NSString stringWithFormat:@"steady: it looks about once a second while busy (%d looks in 5 s)", Looks() - looks0]);
                // (each look reads the switch first, but its state only after SpringBoard posted it: no round trip to notifyd per look, review note 3)
                Check(gSwitchReads - reads0 <= 1, [NSString stringWithFormat:@"steady: and reads the switch's state at most once in those 5 s, not at every look (%d reads)", gSwitchReads - reads0]);
            } else if ([sc isEqualToString:@"idle"]) {
                int looks0 = Looks();
                Run(6.0);
                Check(Looks() - looks0 <= 1 && gAsks == asks0, [NSString stringWithFormat:@"idle: an app left alone is not woken to look again (%d looks in 6 s, %d asks)", Looks() - looks0, gAsks - asks0]);
            } else if ([sc isEqualToString:@"nomenus"]) {
                Check(first.count == 0, [NSString stringWithFormat:@"nomenus: an app with no menus: no titles (%@)", TitlesText()]);
                Busy(0.1, 3.0);
                Check(gAsks == asks0, [NSString stringWithFormat:@"nomenus: busy, nothing moved: no ask (%d)", gAsks - asks0]);
                gStart = Resp(appR, nil, nil);   // (where its commands start moved, once)
                Busy(0.1, 4.0);
                Check(gAsks - asks0 <= 1 && Titles().count == 0, [NSString stringWithFormat:@"nomenus: it moved once: at most one ask, still no titles (%d, %@)", gAsks - asks0, TitlesText()]);
            } else if ([sc isEqualToString:@"flap"]) {
                // an app whose commands start somewhere new every 0.5 s (a carousel's pages), with nothing it offers changing: looked at less often
                __block BOOL stop = NO;
                __block void (^next)(void);
                __weak __block void (^weakNext)(void);
                next = ^{ if (stop) return; gStart = Resp(appR, nil, nil); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), weakNext); };
                weakNext = next;
                next();
                Run(16.0);
                stop = YES;
                Check(gAsks - asks0 >= 2 && gAsks - asks0 <= 4, [NSString stringWithFormat:@"flap: moving every 0.5 s for 16 s with nothing to show for it: asked 2-4 times, not every 2 s (%d)", gAsks - asks0]);
                double after3 = gAsks - asks0 >= 4 ? gAskedAt[asks0 + 3].doubleValue - gAskedAt[asks0 + 2].doubleValue : 99;
                Check(after3 >= 6.0, [NSString stringWithFormat:@"flap: after its third answer that said the same, the next ask 8 s on at the soonest, not 2 (%@)", after3 > 90 ? @"none in 16 s" : [NSString stringWithFormat:@"%.3f s", after3]]);
                Check(Titles().count == 0, @"flap: no titles");
            } else if ([sc isEqualToString:@"flapnotfront"] || [sc isEqualToString:@"flapmenu"]) {
                // B12 review, finding 1: its word has no answer. flapnotfront: another app's window is the bar's app (Split View, Aerial, Zetsu,
                // MilkyWay4, our Stage Manager engine, the TV desktop) and this one, still in front beside it, moves where its commands start every
                // 0.5 s; flapmenu: it is the bar's app, with one of our menus or panels open over it all the while
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer: File, Edit, View (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                BOOL notFront = [sc isEqualToString:@"flapnotfront"];
                if (notFront) { TApp *other = App(@"test.b12.other"); gFront = other; DMAMFrontSeen(other); Run(0.3); }
                else gOverlay = [UIView new];
                asks0 = gAsks; changed0 = gChanged;
                CFTimeInterval from = CACurrentMediaTime();
                Flap(chrome);
                Run(16.0);
                gFlapStop = YES;
                printf("INFO %s: %d menuschanged, %d asks in 16 s, the shortest gap %.3f s\n", sc.UTF8String, gChanged - changed0, gAsks - asks0, MinGap(from));
                Check(gChanged - changed0 >= 1 && gChanged - changed0 <= 6, [NSString stringWithFormat:@"%@: a word no answer follows backs the looks off as an answer that showed nothing does: 1-6 menuschanged in 16 s, not one a second (%d)", sc, gChanged - changed0]);
                Check(MinGap(from) >= 2.5, [NSString stringWithFormat:@"%@: one word out at a time: none within 2.5 s of the last (shortest gap %.3f s)", sc, MinGap(from)]);
                Check(gAsks == asks0, [NSString stringWithFormat:@"%@: no ask meanwhile (%d)", sc, gAsks - asks0]);
#if DEBUG
                int lines8 = 0;
                for (NSString *l in gMABLines) if ([l hasPrefix:@"appmenus: what it offers moved since its answer ("] && [l hasSuffix:@"; looks every 8 s, its last word had no answer"]) lines8++;
                Check(lines8 >= 1, [NSString stringWithFormat:@"%@ (debug): the look's line says the looks wait 8 s now, its last word unanswered (%d lines)", sc, lines8]);
#endif
                if (!notFront) {
                    CFTimeInterval c = CACurrentMediaTime(); gOverlay = nil;   // (closed)
                    double t = -1;
                    while (CACurrentMediaTime() - c < 2.5) { if (t < 0 && gAsks > asks0) t = CACurrentMediaTime() - c; CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false); }
                    Check(gAsks - asks0 == 1 && t >= 0 && t <= 1.6, [NSString stringWithFormat:@"flapmenu: once it is closed, asked once, within 1.6 s (%d, %@)", gAsks - asks0, Took(t)]);   // (as openmenu's)
                }
            } else if ([sc isEqualToString:@"offstill"]) {
                // B12 review, finding 2: switched off after its answer, busy, nothing it offers moving: before, it walked its responders' key commands
                // once a second for the rest of its process (the switch was read only after a move)
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"offstill: its first answer: File, Edit, View (%@)", TitlesText()]);
                Busy(0.05, 0.3);
                DMAMApplyPref(NO);
                int walks0 = chrome.reads, reads0 = gSwitchReads;
                Busy(0.1, 5.0);
                printf("INFO offstill: %d walks, %d reads of the switch in 5 s of activity, switch off, nothing moved; %d asks, %d menuschanged\n", chrome.reads - walks0, gSwitchReads - reads0, gAsks - asks0, gChanged - changed0);
                Check(chrome.reads == walks0 && gSwitchReads - reads0 <= 1, [NSString stringWithFormat:@"offstill: off, its next look stops the looks before it reads anything: no walk of its responders, one read of the switch at most in 5 s (%d, %d)", chrome.reads - walks0, gSwitchReads - reads0]);
                Check(gAsks == asks0 && gChanged == changed0, [NSString stringWithFormat:@"offstill: no ask, no menuschanged (%d, %d)", gAsks - asks0, gChanged - changed0]);
#if DEBUG
                int stopped = 0;
                for (NSString *l in gMABLines) if ([l hasPrefix:@"appmenus: Show Apps' Own Menus off since its answer: no more looks (at "]) stopped++;
                Check(stopped == 1, [NSString stringWithFormat:@"offstill (debug): the looks stopped by the switch is logged once (%d)", stopped]);
#endif
            } else if ([sc isEqualToString:@"backswitch"] || [sc isEqualToString:@"backtap"]) {
                // B12 review, finding 5: the looks backed off (it is the bar's app; where its commands start moves every 0.5 s with nothing to show for
                // it, until its third answer that said the same: a look every 8 s then); then a switch away and back (backswitch) or a tap in it
                // (backtap), then its card's commands come. Before, only an answer that differed brought the looks back to once a second
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer: File, Edit, View (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                asks0 = gAsks;
                CFTimeInterval f0 = CACurrentMediaTime();
                Flap(chrome);
                while (gAsks - asks0 < 3 && CACurrentMediaTime() - f0 < 20.0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
                gFlapStop = YES;
                double backed = CACurrentMediaTime() - f0;
                Check(gAsks - asks0 == 3 && backed >= 5.0, [NSString stringWithFormat:@"%@: the looks backed off: its third ask %.3f s into the moves (%d asks), not every 2 s", sc, backed, gAsks - asks0]);
                Run(0.2);   // (that answer in: a look every 8 s now)
                if ([sc isEqualToString:@"backswitch"]) {
                    TApp *other = App(@"test.b12.other"); gFront = other; DMAMFrontSeen(other);
                    Run(0.3);
                    gFront = app; DMAMFrontSeen(app);   // (back: the bar's forced ask at the switch)
                    Run(0.3);
                } else {
                    Post("touched");   // (a tap in it: SpringBoard asks 1 s after its taps stop)
                    Run(1.3);
                }
                int asks1 = gAsks;
                CFTimeInterval c = CACurrentMediaTime(); gLaidAt = 0;
                chrome.kc = MapsCard();   // (its card's commands came)
                Busy(0.1, 3.5);
                double t = gLaidAt > 0 ? gLaidAt - c : -1;
                Check(asks1 - asks0 == 4, [NSString stringWithFormat:@"%@: the %@ was answered (%d asks)", sc, [sc isEqualToString:@"backswitch"] ? @"switch" : @"tap", asks1 - asks0]);
                Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 2.5, [NSString stringWithFormat:@"%@: then the full set within 2.5 s, as for grows, not up to 8 s later (%@, %@)", sc, TitlesText(), Took(t)]);
#if DEBUG
                NSString *lastLook = nil;
                for (NSString *l in gMABLines) if ([l hasPrefix:@"appmenus: what it offers moved since its answer ("]) lastLook = l;
                Check([lastLook hasSuffix:@"; looks every 1 s, its last word was answered"], [NSString stringWithFormat:@"%@ (debug): the growth's look line says the looks are back to once a second (%@)", sc, lastLook]);
#endif
            } else if ([sc isEqualToString:@"frontafterword"] || [sc isEqualToString:@"frontlate"] || [sc isEqualToString:@"fronttap"]) {
                // the review fixes' review, finding 1: a window beside the bar's app keeps moving where its commands start (as flapnotfront) until
                // its looks wait 8 s; then it becomes the bar's app (the bar's forced ask at a front change) 0.5 s (frontafterword: Cmd-Tab, its
                // Dock icon, the App Switcher, with no tap in it) or 3.5 s (frontlate) after its last word, or by a tap in it (fronttap: its own
                // "touched" too); its moves stop and its card's commands come. Before, frontafterword's answer counted as that word's and the
                // card's titles came ~8 s later, not ~2 s
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer: File, Edit, View (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                TApp *other = App(@"test.b12.other"); gFront = other; DMAMFrontSeen(other); Run(0.3);
                Flap(chrome);
                Run(10.0);   // (its words at ~0, 3, 7 and 11 s: the looks wait 8 s from the fourth)
                int c0 = gChanged; CFTimeInterval w0 = CACurrentMediaTime();
                while (gChanged == c0 && CACurrentMediaTime() - w0 < 10.0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
                CFTimeInterval word = CACurrentMediaTime();
                gFlapStop = YES;
                BOOL tap = [sc isEqualToString:@"fronttap"];
                Busy(0.1, [sc isEqualToString:@"frontlate"] ? 3.5 : 0.5);
                int asks1 = gAsks;
                CFTimeInterval front = CACurrentMediaTime();
                gFront = app; DMAMFrontSeen(app);     // (the bar's app now)
                if (tap) Post("touched");             // (the tap itself, heard once it is the bar's app)
                Busy(0.1, tap ? 1.5 : 0.5);
                int asks2 = gAsks;
                CFTimeInterval c = CACurrentMediaTime(); gLaidAt = 0;
                chrome.kc = MapsCard();   // (its card's commands came)
                while (![Titles() isEqualToArray:kMapsFull] && CACurrentMediaTime() - c < 4.0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
                double t = [Titles() isEqualToArray:kMapsFull] && gLaidAt > 0 ? gLaidAt - c : -1;
                printf("INFO %s: its last word %.3f s before it came forward; %d asks for that; the full set %s after its card\n", sc.UTF8String, front - word, asks2 - asks1, Took(t).UTF8String);
                Check(asks2 - asks1 >= 1 && c0 >= 2, [NSString stringWithFormat:@"%@: its words beside the bar's app, then asked as it came forward (%d words before, %d asks)", sc, c0, asks2 - asks1]);
                Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 2.5, [NSString stringWithFormat:@"%@: then its card: the full set within 2.5 s, as for grows, not ~8 s later (%@, %@)", sc, TitlesText(), Took(t)]);
#if DEBUG
                NSString *lastLook = nil;
                for (NSString *l in gMABLines) if ([l hasPrefix:@"appmenus: what it offers moved since its answer ("]) lastLook = l;
                Check([lastLook hasSuffix:@"; looks every 1 s, its last word was answered"], [NSString stringWithFormat:@"%@ (debug): the growth's look line says the looks are back to once a second (%@)", sc, lastLook]);
#endif
                if ([sc isEqualToString:@"frontafterword"]) {
                    // then, the bar's app now, it keeps moving with nothing new: the looks back off again (2, 4, 8 s), as for flap: the answers
                    // after that first one count as their words' again
                    Run(0.5);
                    int asks3 = gAsks; gFlapStop = NO;
                    Flap(chrome);
                    Run(14.0);
                    gFlapStop = YES;
                    double after3 = gAsks - asks3 >= 4 ? gAskedAt[asks3 + 3].doubleValue - gAskedAt[asks3 + 2].doubleValue : 99;
                    printf("INFO frontafterword: then %d asks in 14 s as the bar's app, the 4th %s after the 3rd\n", gAsks - asks3, after3 > 90 ? "none" : [NSString stringWithFormat:@"%.3f s", after3].UTF8String);
                    Check(gAsks - asks3 >= 2 && gAsks - asks3 <= 4 && after3 >= 6.0, [NSString stringWithFormat:@"frontafterword: then moving every 0.5 s for 14 s as the bar's app with nothing new: it backs off again, 2-4 asks and after the third none within 6 s, not one every 2 s (%d, %@)", gAsks - asks3, after3 > 90 ? @"none" : [NSString stringWithFormat:@"%.3f s", after3]]);
                }
            } else if ([sc isEqualToString:@"focustap"] || [sc isEqualToString:@"plaintap"]) {
                // three taps 2.5 s apart in the bar's app, each moving where its commands start (focustap: a field focused) or not (plaintap), with
                // nothing new to show; then its card's commands come with no input: the taps' answers did not leave the looks backed off to 8 s
                // (a tap whose move a look also said, answered once for both, counts as that look's: the looks may wait 2 s after them, so its
                // card can take ~2-3 s, not 8)
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer: File, Edit, View (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                asks0 = gAsks; changed0 = gChanged;
                for (int i = 0; i < 3; i++) {
                    if ([sc isEqualToString:@"focustap"]) gStart = Resp(chrome, nil, nil);
                    Post("touched");
                    Busy(0.1, 2.5);
                }
                int asks1 = gAsks;
                CFTimeInterval c = CACurrentMediaTime(); gLaidAt = 0;
                chrome.kc = MapsCard();
                while (![Titles() isEqualToArray:kMapsFull] && CACurrentMediaTime() - c < 5.0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
                double t = [Titles() isEqualToArray:kMapsFull] && gLaidAt > 0 ? gLaidAt - c : -1;
                printf("INFO %s: 3 taps: %d asks, %d menuschanged; then the full set %s after its card\n", sc.UTF8String, asks1 - asks0, gChanged - changed0, Took(t).UTF8String);
                Check(asks1 - asks0 >= 3, [NSString stringWithFormat:@"%@: each tap asked it (%d asks)", sc, asks1 - asks0]);
                Check([Titles() isEqualToArray:kMapsFull] && t >= 0 && t <= 3.5, [NSString stringWithFormat:@"%@: after 3 taps, its card: the full set within 3.5 s, not 8 (%@, %@)", sc, TitlesText(), Took(t)]);
            } else if ([sc isEqualToString:@"menuopenclose"]) {
                // the bar's app moving every 0.5 s with nothing new while one of our menus opens and closes every 4 s for 24 s: every close may let
                // an answer come (and the first after a word no answer followed puts the looks back), but the asks stay bounded
                Check([first isEqualToArray:kMapsThin], [NSString stringWithFormat:@"%@: its first answer: File, Edit, View (%@)", sc, TitlesText()]);
                Busy(0.05, 0.3);
                asks0 = gAsks; changed0 = gChanged;
                CFTimeInterval from = CACurrentMediaTime();
                Flap(chrome);
                for (int i = 0; i < 6; i++) { gOverlay = [UIView new]; Run(2.0); gOverlay = nil; Run(2.0); }
                gFlapStop = YES;
                printf("INFO %s: %d asks, %d menuschanged in 24 s, the shortest gap %.3f s\n", sc.UTF8String, gAsks - asks0, gChanged - changed0, MinGap(from));
                Check(gAsks - asks0 >= 1 && gAsks - asks0 <= 8, [NSString stringWithFormat:@"%@: our menu opened and closed 6 times over it: asked 1-8 times in 24 s, not at every close and every word (%d)", sc, gAsks - asks0]);
            } else return 2;
        }
        [[NSFileManager defaultManager] removeItemAtPath:gContainer error:nil];
        printf("%s: %d checks, %d failed\n", argv[1], gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
