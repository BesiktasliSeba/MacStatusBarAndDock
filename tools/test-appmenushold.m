// test-appmenushold.m -- see test-appmenushold.sh. F-7: while one of our menus or panels is open, the bar's app titles stay where they are, and
// what came meanwhile is laid out once it is gone. The real code, cut out of statusbar/AppMenus.h (SpringBoard's side: gAMOn to DMAMFrontSeen,
// DMAMApplyPref, DMAMTitles and the hold: sb-block.inc), statusbar/StatusBar.x (the bar layout's own lines from its app to the titles it lays out:
// layout.inc; what DMCloseOverlay and DMRemoveOverlayNow do for the app's titles: close.inc, remove.inc) and appbridge/AppMenus.h (the app's: the
// whole file but for where it finds its window, responders and main menu, and the pick: app-block.inc), all in this process, on the Mac's own
// notifyd and main run loop (real Darwin notifications under a prefix of this run's, TPFX). Stand-ins: the bar's app (DMActiveApp, its pid), its
// data container, the bar's copies (two on one screen, as an app's own copy beside SpringBoard's: views that run the layout's lines at the end of the turn
// after setNeedsLayout, as UIKit does, and keep the titles laid out; one in a window of its own, the other in none: both on the screen of the
// menu, which is in a window of its own too), one of our menus (gOverlay: a view), the app's key window, first responder and main menu, DMLog, MABLog.
// F-7b: a title of a copy is a real UIButton with the lines DMLayoutTitle adds for it (touch.inc: StatusBar.x's own); a finger on it is UIKit's
// tracking (the button's isTracking), the end of its touch UIKit's sending of its actions. One scenario per process (argv[1]); no UIApplicationMain,
// no window on screen.
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
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; if (getenv("AMH_VERBOSE")) printf("  log %.3f %s\n", CACurrentMediaTime(), s.UTF8String); }
static UIView *gOverlay;   // (one of our menus or panels open: SpringBoard's own, StatusBar.x)
static void TLayout(UIView *fg);
// A copy of the bar: setNeedsLayout runs its layout at the end of the turn (once for any number of calls), as UIKit's layout pass does; what it
// laid out is kept, with when it last changed and how often it changed while one of our menus was open
@interface TView : UIView
@property (nonatomic) int layouts, movedUnder;
@property (nonatomic) BOOL pending;
@property (nonatomic, copy) NSArray<NSString *> *laid;
@property (nonatomic) CFTimeInterval laidAt;
@end
@implementation TView
- (void)setNeedsLayout {
    if (self.pending) return;
    self.pending = YES;
    __weak TView *w = self;
    dispatch_async(dispatch_get_main_queue(), ^{ TView *v = w; if (!v || !v.pending) return; v.pending = NO; TLayout(v); });
}
- (void)layoutIfNeeded { if (!self.pending) return; self.pending = NO; TLayout(self); }
@end
static NSHashTable *gCopies;
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
// The bar's layout of a copy, as -dm_layoutLogoBody runs it for the app's titles: its app in front, not our Finder window, room for the app's name;
// then its own lines (layout.inc) to the titles it lays out
static void TLayout(UIView *fgv) {
    TView *fg = (TView *)fgv;
    SBApplication *frontApp = DMActiveApp(); BOOL finderTitles = NO; CGFloat appRight = 40.0;
#include "layout.inc"
    fg.layouts++;
    if (![fg.laid isEqualToArray:amWant]) {
        if (fg.laid && gOverlay) fg.movedUnder++;
        fg.laid = amWant; fg.laidAt = CACurrentMediaTime();
        if (getenv("AMH_VERBOSE")) printf("  bar %p %.3f laid %s%s\n", fg, CACurrentMediaTime(), [amWant componentsJoinedByString:@", "].UTF8String, gOverlay ? " (a menu open)" : "");
    }
}
// One of our menus or panels: opened (gOverlay set, as DMMakeOverlayFor does), closed (DMCloseOverlay), removed at once (DMRemoveOverlayNow: for the
// next menu, or the menu's display gone): gOverlay nil, then what each does for the app's titles (close.inc, remove.inc: StatusBar.x's own lines)
static UIWindow *gMenuWin;
static void TOpen(void) { gOverlay = [UIView new]; if (!gMenuWin) gMenuWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1000, 700)]; [gMenuWin addSubview:gOverlay]; }
static void TClose(void) {
    [gOverlay removeFromSuperview]; gOverlay = nil;
#include "close.inc"
}
static void TRemoveNow(void) {
    [gOverlay removeFromSuperview]; gOverlay = nil;
#include "remove.inc"
}
// A title of a copy, as DMLayoutTitle makes it: its tap's action (onTap: one of our menus opens), then what DMLayoutTitle adds for the hold
// (touch.inc). A finger on it: down (UIKit tracks the touch); its end (TEnd): UIKit sends its actions while the button may still read as
// tracking, and a layout may be forced in that same turn (some of ours force one); once the turn is over it no longer tracks
@interface TButton : UIButton
@property (nonatomic) BOOL down;
@end
@implementation TButton
- (BOOL)isTracking { return self.down; }
@end
static TButton *TTitle(UIView *fg, void (^onTap)(void)) {
    TButton *btn = [TButton buttonWithType:UIButtonTypeCustom];
    if (onTap) [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { onTap(); }] forControlEvents:UIControlEventTouchUpInside];
#include "touch.inc"
    [fg addSubview:btn];
    return btn;
}
static void TEnd(TButton *b, UIControlEvents how) {
    [b sendActionsForControlEvents:how];
    for (TView *v in gCopies.allObjects) [v layoutIfNeeded];
    b.down = NO;
}

// ---- the app's side (as test-appmenusready.m: its real snapshot on responders of the test's own) --------------------------------------------
@interface TResp : UIResponder
@property (nonatomic, strong) UIResponder *up;
@property (nonatomic, copy) NSArray<NSArray *> *kc;   // (title, action name, input, modifiers)
@property (nonatomic, copy) NSSet<NSString *> *acts;
@end
@implementation TResp
- (UIResponder *)nextResponder { return self.up; }
- (NSArray<UIKeyCommand *> *)keyCommands {
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *k in self.kc) [out addObject:[UIKeyCommand commandWithTitle:k[0] image:nil action:NSSelectorFromString(k[1]) input:k[2] modifierFlags:[k[3] integerValue] propertyList:nil]];
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
static int gSnapshots;
static UIWindow *MABMenuKeyWindow(void) { return gWin; }
static UIResponder *MABMenuStart(UIWindow *key) { return gStart; }
static UIMenu *MABMenuRoot(void) { gSnapshots++; return gRoot; }
static void MABMenuPerform(uint64_t state) {}
#if DEBUG
static void MABLog(NSString *s) {}
static BOOL MSTestFlag(const char *p) { return NO; }
#endif
#include "app-block.inc"

// ---- the scenarios -------------------------------------------------------------------------------------------------------------------------
static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Run(double s) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, s, false); }
static uint32_t Hash(NSString *b) { uint32_t h = 2166136261u; for (const char *c = b.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 16777619u; } return h; }
static int gAsks;
static void CountAsks(void) {   // (a listener of our own, as nwatch on the iPads: the asks of the app under test)
    char name[128]; snprintf(name, sizeof name, TPFX "menus.%08x", Hash(gBundle));
    int t = 0; notify_register_dispatch(name, &t, dispatch_get_main_queue(), ^(int tok) { gAsks++; });
}
static NSString *Text(NSArray *a) { return a.count ? [a componentsJoinedByString:@", "] : @"none"; }
static NSArray<NSString *> *Snap(void) { return DMAMTitles(gBundle); }   // (what SpringBoard has from the app, as the bar would show it)
// Runs the run loop until the copy has laid out `want` (s seconds at most); the time it took (-1: not)
static double WaitLaid(TView *v, NSArray *want, double s) {
    CFTimeInterval t0 = CACurrentMediaTime();
    while (![v.laid isEqualToArray:want] && CACurrentMediaTime() - t0 < s) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.005, false);
    return [v.laid isEqualToArray:want] ? CACurrentMediaTime() - t0 : -1;
}
static NSString *Took(double t) { return t < 0 ? @"never" : [NSString stringWithFormat:@"%.3f s", t]; }
static int Lines(NSString *prefix, NSString *part) { int n = 0; for (NSString *l in gLog) if ([l hasPrefix:prefix] && (!part || [l containsString:part])) n++; return n; }
static TApp *App(NSString *b) { TApp *a = [TApp new]; a.bundleIdentifier = b; a.processState = [TProc new]; a.processState.pid = getpid(); return a; }
static TResp *Resp(UIResponder *up, NSArray *acts, NSArray *kc) { TResp *r = [TResp new]; r.up = up; r.acts = [NSSet setWithArray:acts ?: @[]]; r.kc = kc ?: @[]; return r; }
static UICommand *Cmd(NSString *t, NSString *a) { return [UICommand commandWithTitle:t image:nil action:NSSelectorFromString(a) propertyList:nil]; }
static UIMenu *Top(UIMenuIdentifier ident, NSArray *children) { return [UIMenu menuWithTitle:@"" image:nil identifier:ident options:0 children:children]; }
static UIMenu *Root(NSArray *tops) { return [UIMenu menuWithTitle:@"" image:nil identifier:UIMenuRoot options:0 children:tops]; }
static void Busy(double every, double s) {   // (something of the app's own on its main queue every `every` s: its run loop is busy, then waits)
    for (double t = every; t < s; t += every) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(t * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{});
    Run(s);
}
// Maps (as test-appmenusready.m): File, Edit and View from its main menu at once; its home card's key commands later (Bookmarks, Actions)
static UIMenu *MapsRoot(void) {
    return Root(@[Top(UIMenuFile, @[Cmd(@"New Window", @"newWindow:"), Cmd(@"Print", @"printMap:")]),
                  Top(UIMenuEdit, @[Cmd(@"Undo", @"undoMap:"), Cmd(@"Drop Pin", @"dropPin:")]),
                  Top(UIMenuView, @[Cmd(@"Explore Map", @"exploreMap:"), Cmd(@"Zoom In", @"zoomIn:")])]);
}
static NSArray *MapsCard(void) {
    long m = UIKeyModifierCommand | UIKeyModifierAlternate;
    return @[@[@"See All Favorites", @"seeAll:", @"1", @(m)], @[@"See All My Guides", @"seeAll:", @"2", @(m)], @[@"See All Recents", @"seeAll:", @"3", @(m)]];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) return 2;
        NSString *sc = @(argv[1]);
        gBundle = [NSString stringWithFormat:@"test.f7.app.%d", getpid()];
        gContainer = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"amh-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:[gContainer stringByAppendingPathComponent:@"tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
        gCopies = [NSHashTable weakObjectsHashTable];
        TView *bar = [[TView alloc] initWithFrame:CGRectMake(0, 0, 1000, 24)], *tv = [[TView alloc] initWithFrame:CGRectMake(0, 0, 1000, 24)];   // (two copies of the bar on one screen)
        [gCopies addObject:bar]; [gCopies addObject:tv];
        UIWindow *barWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1000, 24)]; [barWin addSubview:bar];   // (the first copy in a window of its own)
        CountAsks();
        gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        UIResponder *appR = Resp(nil, nil, nil);
        NSArray *maps = @[@"newWindow:", @"printMap:", @"dropPin:", @"exploreMap:", @"zoomIn:", @"seeAll:"];
        TResp *chrome = Resp(appR, maps, nil);
        gRoot = MapsRoot(); gStart = chrome;
        NSArray *thin = @[@"File", @"View"], *full = @[@"File", @"View", @"Bookmarks", @"Actions"], *fmt = @[@"File", @"Format", @"View"], *none = @[];   // (as the bar lays them out: Edit is ours)
        DMAMApplyPref(YES);
        TApp *app = App(gBundle);
        // (Maps cold: the bar sees it in front and lays out its copies; its ask is lost, MacAppBridge isn't in it yet)
        BOOL cold = [sc isEqualToString:@"word"] || [sc isEqualToString:@"switch"] || [sc isEqualToString:@"nohold"] || [sc isEqualToString:@"touch"] || [sc isEqualToString:@"touchend"];
        if (cold || [sc isEqualToString:@"tap"] || [sc isEqualToString:@"front"]) {
            gFront = app; [bar setNeedsLayout]; [tv setNeedsLayout];
            Run(0.3);
        }
        if ([sc isEqualToString:@"word"] || [sc isEqualToString:@"switch"]) {
            // F-7 as the 17.5 had it: Go opened ~0.3 s into the launch, before the first answer; then Maps' word, its ask at once, its answer
            Check([bar.laid isEqualToArray:none] && gAsks == 1, [NSString stringWithFormat:@"%@: Maps in front, nothing of its own on the bar yet (%@, %d asks)", sc, Text(bar.laid), gAsks]);
            TOpen();
            MABRegisterMenus();
            Run(1.0);
            Check([Snap() isEqualToArray:thin], [NSString stringWithFormat:@"%@: its first answer came in under the open menu (%@)", sc, Text(Snap())]);
            Check([bar.laid isEqualToArray:none] && [tv.laid isEqualToArray:none] && bar.movedUnder == 0 && tv.movedUnder == 0,
                  [NSString stringWithFormat:@"%@: no title moved under the open menu (the bar keeps %@, the second copy's %@; %d / %d changes)", sc, Text(bar.laid), Text(tv.laid), bar.movedUnder, tv.movedUnder]);
            int asks0 = gAsks;
            Check(asks0 == 2, [NSString stringWithFormat:@"%@: asked by its word at once, as B12 does (%d asks)", sc, asks0]);
            if ([sc isEqualToString:@"switch"]) {
                // another title tapped while it is open: the open menu removed at once and the next one opened in the same turn (DMTitleTapWithMenuOpen)
                TRemoveNow(); TOpen();
                Run(1.0);
                Check([bar.laid isEqualToArray:none] && bar.movedUnder == 0, [NSString stringWithFormat:@"switch: from one open title to another, still no title moved (%@, %d changes)", Text(bar.laid), bar.movedUnder]);
                // the next menu's display goes (a TV unplugged): removed at once with no menu after it
                TRemoveNow();
                double t = WaitLaid(bar, thin, 1.0);
                Check(t >= 0 && t <= 0.2 && [tv.laid isEqualToArray:thin], [NSString stringWithFormat:@"switch: removed with none after it, what waited is laid out at once (%@ within %@ of it; the second copy's %@)", Text(bar.laid), Took(t), Text(tv.laid)]);
            } else {
                // its home card fills in while the menu stays open (B12's thin first answer: a move, menuschanged, asked once it is closed)
                chrome.kc = MapsCard();
                Busy(0.1, 3.0);
                Check([bar.laid isEqualToArray:none] && bar.movedUnder == 0 && gAsks == asks0, [NSString stringWithFormat:@"word: its card's move under the open menu asks nothing and moves nothing (%@, %d changes, %d asks)", Text(bar.laid), bar.movedUnder, gAsks - asks0]);
                CFTimeInterval c = CACurrentMediaTime();
                TClose();
                double t1 = WaitLaid(bar, thin, 1.0);
                Check(t1 >= 0 && t1 <= 0.2 && [tv.laid isEqualToArray:thin], [NSString stringWithFormat:@"word: closed, the answer that waited is laid out at once (%@ within %@; the second copy's %@)", Text(bar.laid), Took(t1), Text(tv.laid)]);
                double t2 = WaitLaid(bar, full, 2.0);
                t2 = t2 < 0 ? -1 : CACurrentMediaTime() - c;
                // (asked by SpringBoard's wait under the menu, which looks again once a second: up to 1 s after the close, plus the answer and the
                //  Mac's load, as test-appmenusready's openmenu)
                Check(t2 >= 0 && t2 <= 1.6, [NSString stringWithFormat:@"word: and its card's titles within 1.6 s of the close (%@, %@)", Text(bar.laid), Took(t2)]);
                Run(2.0);
                Check(gAsks - asks0 == 1 && [bar.laid isEqualToArray:full], [NSString stringWithFormat:@"word: one ask after the close, no more (%d in 3.3 s; %@)", gAsks - asks0, Text(bar.laid)]);
                Check(Lines(@"[appmenus] ", @": menus File, View wait for our menu or panel to close (the bar keeps none)") == 1 && Lines(@"[appmenus] our menu or panel is gone: the bar is laid out again", nil) == 1,
                      [NSString stringWithFormat:@"word: the hold and its end are logged once each (%d, %d)", Lines(@"[appmenus] ", @"wait for our menu or panel to close"), Lines(@"[appmenus] our menu or panel is gone", nil)]);
            }
        } else if ([sc isEqualToString:@"tap"]) {
            // a title tapped (DMOpenAppOwnMenu): its ask, and the menu opened with the last answer before the fresh one came (the app slower than
            // 0.3 s, or a finger on Go while an ask is out); the fresh answer comes under it
            MABRegisterMenus();
            double t0 = WaitLaid(bar, thin, 1.0);
            Check(t0 >= 0, [NSString stringWithFormat:@"tap: its first answer on the bar (%@, %@)", Text(bar.laid), Took(t0)]);
            Run(1.5);
            int asks0 = gAsks;
            // (what it offers changed with nothing its looks see: a Format menu in its main menu, with no rebuild word)
            gRoot = Root([MapsRoot().children arrayByAddingObject:Top(UIMenuFormat, @[Cmd(@"Bold", @"boldMap:")])]);
            chrome.acts = [NSSet setWithArray:[maps arrayByAddingObject:@"boldMap:"]];
            DMAMAsk(gBundle, YES);   // (the title's ask)
            TOpen();                 // (its menu open before the answer is in)
            Run(1.5);
            Check([Snap() isEqualToArray:fmt], [NSString stringWithFormat:@"tap: the fresh answer came in under the open menu (%@)", Text(Snap())]);
            Check([bar.laid isEqualToArray:thin] && [tv.laid isEqualToArray:thin] && bar.movedUnder == 0, [NSString stringWithFormat:@"tap: no title moved under it (the bar keeps %@, the second copy's %@; %d changes)", Text(bar.laid), Text(tv.laid), bar.movedUnder]);
            TClose();
            double t = WaitLaid(bar, fmt, 1.0);
            Check(t >= 0 && t <= 0.2 && [tv.laid isEqualToArray:fmt], [NSString stringWithFormat:@"tap: closed, laid out at once (%@ within %@; the second copy's %@)", Text(bar.laid), Took(t), Text(tv.laid)]);
            Run(2.0);
            Check(gAsks - asks0 == 1, [NSString stringWithFormat:@"tap: no ask but the title's (%d)", gAsks - asks0]);
        } else if ([sc isEqualToString:@"minute"]) {
            // 1.8.7.9's minute layout under an open menu: Maps was asked at the front change (lost), MacAppBridge came while another app was the
            // bar's (its word asked nothing), Maps is the bar's app again with no layout; a menu open, the minute lays out every copy: its ask
            gFront = app; [bar setNeedsLayout]; Run(0.3);
            gFront = App(@"test.f7.other"); MABRegisterMenus(); Run(2.2);
            gFront = app;
            TOpen();
            int asks0 = gAsks;
            TLayout(bar); TLayout(tv);   // (hh:mm:00)
            Run(1.5);
            Check(gAsks - asks0 == 1 && [Snap() isEqualToArray:thin], [NSString stringWithFormat:@"minute: the minute's layout asked it and the answer came in under the open menu (%d asks, %@)", gAsks - asks0, Text(Snap())]);
            Check([bar.laid isEqualToArray:none] && [tv.laid isEqualToArray:none] && bar.movedUnder == 0 && tv.movedUnder == 0, [NSString stringWithFormat:@"minute: no title moved under it (%@, %@; %d / %d changes)", Text(bar.laid), Text(tv.laid), bar.movedUnder, tv.movedUnder]);
            TRemoveNow();   // (the menu removed at once with none after it)
            double t = WaitLaid(bar, thin, 1.0);
            Check(t >= 0 && t <= 0.2 && [tv.laid isEqualToArray:thin], [NSString stringWithFormat:@"minute: gone, laid out at once (%@ within %@; the second copy's %@)", Text(bar.laid), Took(t), Text(tv.laid)]);
            Run(2.0);
            Check(gAsks - asks0 == 1, [NSString stringWithFormat:@"minute: no ask after it (%d)", gAsks - asks0]);
        } else if ([sc isEqualToString:@"gone"]) {
            // the answer in is from a process that has gone (Maps relaunched while in front) and a menu is open: dropped (DMAMFrontSeen), then the
            // new process's word and answer; the bar keeps the old titles until it is closed
            if (!gAMSnap) gAMSnap = [NSMutableDictionary dictionary];
            gAMSnap[gBundle] = @{@"b": gBundle, @"m": @[@{@"t": @"Tabs", @"r": @[@{@"t": @"Old", @"x": @9, @"e": @YES}]}], @"n": @1, @"p": @(1), @"partial": @NO};
            app.processState.pid = 1;   // (the old process)
            gFront = app; [bar setNeedsLayout]; [tv setNeedsLayout]; Run(0.3);
            Check([bar.laid isEqualToArray:@[@"Tabs"]] && [tv.laid isEqualToArray:@[@"Tabs"]], [NSString stringWithFormat:@"gone: the old process's titles on the bar (%@, %@)", Text(bar.laid), Text(tv.laid)]);
            TOpen();
            app.processState.pid = getpid();   // (relaunched: a new process)
            TLayout(bar);   // (a layout: the answer is from a process that has gone)
            Run(0.3);
            Check(!gAMSnap[gBundle] || [Snap() isEqualToArray:thin], @"gone: the old process's answer dropped");
            MABRegisterMenus();
            Run(1.0);
            Check([Snap() isEqualToArray:thin] && [bar.laid isEqualToArray:@[@"Tabs"]] && [tv.laid isEqualToArray:@[@"Tabs"]] && bar.movedUnder == 0 && tv.movedUnder == 0,
                  [NSString stringWithFormat:@"gone: the new answer in, no title moved under the open menu (%@; the bar keeps %@, the second copy's %@)", Text(Snap()), Text(bar.laid), Text(tv.laid)]);
            TClose();
            double t = WaitLaid(bar, thin, 1.0);
            Check(t >= 0 && t <= 0.2, [NSString stringWithFormat:@"gone: closed, the new process's titles at once (%@, %@)", Text(bar.laid), Took(t)]);
        } else if ([sc isEqualToString:@"front"]) {
            // another app comes to the front under an open menu (a keyboard switch while our menu has the keys): neither Maps' titles for it nor its
            // own moving in; its own once the menu is closed
            MABRegisterMenus();
            WaitLaid(bar, thin, 1.0);
            Run(0.5);
            TApp *other = App(@"test.f7.other");
            if (!gAMSnap) gAMSnap = [NSMutableDictionary dictionary];
            gAMSnap[other.bundleIdentifier] = @{@"b": other.bundleIdentifier, @"m": @[@{@"t": @"History", @"r": @[@{@"t": @"Back", @"x": @3, @"e": @YES}]}], @"n": @1, @"p": @(getpid()), @"partial": @NO};
            TOpen();
            gFront = other; TLayout(bar); TLayout(tv);
            Run(0.5);
            Check([bar.laid isEqualToArray:none] && [tv.laid isEqualToArray:none], [NSString stringWithFormat:@"front: another app in front under the open menu: none of Maps' titles for it, none of its own yet (%@, %@)", Text(bar.laid), Text(tv.laid)]);
            TClose();
            double t = WaitLaid(bar, @[@"History"], 1.0);
            Check(t >= 0 && t <= 0.2, [NSString stringWithFormat:@"front: closed, its own titles at once (%@, %@)", Text(bar.laid), Took(t)]);
        } else if ([sc isEqualToString:@"touch"]) {
            // F-7b as p08's device rows had it: a finger on Go (UIKit tracking the touch) as Maps' first answer comes in, asked by its word. Before, the copy was
            // laid out under the finger: Go moved from under it, the touch ended outside it and opened nothing
            TButton *go = TTitle(bar, ^{ TOpen(); }), *tvGo = TTitle(tv, ^{ TOpen(); });
            (void)tvGo;
            Check([bar.laid isEqualToArray:none] && gAsks == 1, [NSString stringWithFormat:@"touch: Maps in front, nothing of its own on the bar yet (%@, %d asks)", Text(bar.laid), gAsks]);
            int layouts0 = bar.layouts;
            go.down = YES;   // (the finger on Go)
            MABRegisterMenus();
            Run(1.0);
            Check([Snap() isEqualToArray:thin] && bar.layouts > layouts0, [NSString stringWithFormat:@"touch: its first answer came in while the finger was on Go, and the copy was laid out (%@, %d layouts)", Text(Snap()), bar.layouts - layouts0]);
            Check([bar.laid isEqualToArray:none], [NSString stringWithFormat:@"touch: no title moved on the copy under the finger (it keeps %@)", Text(bar.laid)]);
            Check([tv.laid isEqualToArray:thin], [NSString stringWithFormat:@"touch: the other copy, with no finger on any of its titles, laid it out (%@)", Text(tv.laid)]);
            TEnd(go, UIControlEventTouchUpInside);   // (lifted on Go: its menu opens)
            Run(0.3);
            Check(gOverlay && [bar.laid isEqualToArray:none] && bar.movedUnder == 0, [NSString stringWithFormat:@"touch: lifted on Go, its menu opened, and still nothing moved under it (%@, %d changes)", Text(bar.laid), bar.movedUnder]);
            TClose();
            double t = WaitLaid(bar, thin, 1.0);
            Check(t >= 0 && t <= 0.2, [NSString stringWithFormat:@"touch: its menu closed, what waited is laid out at once (%@ within %@)", Text(bar.laid), Took(t)]);
            Check(Lines(@"[appmenus] ", @": menus File, View wait for the finger on a title to lift (the bar keeps none)") == 1 && Lines(@"[appmenus] the finger on a title lifted: the bar is laid out again", nil) == 1
                  && Lines(@"[appmenus] ", @"wait for our menu or panel to close") == 1 && Lines(@"[appmenus] our menu or panel is gone", nil) == 1,
                  [NSString stringWithFormat:@"touch: the finger's hold, its end, the menu's hold and its end are logged once each (%d, %d, %d, %d)", Lines(@"[appmenus] ", @"wait for the finger on a title to lift"),
                   Lines(@"[appmenus] the finger on a title lifted", nil), Lines(@"[appmenus] ", @"wait for our menu or panel to close"), Lines(@"[appmenus] our menu or panel is gone", nil)]);
        } else if ([sc isEqualToString:@"touchend"]) {
            // F-7b: a finger on Go as the first answer comes in, then the touch taken by a system gesture (Notification Center pulled down from the
            // bar: UIKit cancels it); then a finger on it again as its card's titles come (B12's look, asked a second later), lifted outside it
            TButton *go = TTitle(bar, ^{ TOpen(); });
            go.down = YES;
            MABRegisterMenus();
            Run(1.0);
            Check([Snap() isEqualToArray:thin] && [bar.laid isEqualToArray:none], [NSString stringWithFormat:@"touchend: the first answer in under the finger, held (%@, the bar keeps %@)", Text(Snap()), Text(bar.laid)]);
            TEnd(go, UIControlEventTouchCancel);
            double t = WaitLaid(bar, thin, 1.0);
            Check(t >= 0 && t <= 0.2 && !gOverlay, [NSString stringWithFormat:@"touchend: the touch taken by a system gesture: laid out at once, nothing opened (%@ within %@)", Text(bar.laid), Took(t)]);
            Run(1.0);
            go.down = YES;
            chrome.kc = MapsCard();
            Busy(0.1, 3.0);
            Check([Snap() isEqualToArray:full] && [bar.laid isEqualToArray:thin], [NSString stringWithFormat:@"touchend: its card's titles came in under the finger again, held (%@, the bar keeps %@)", Text(Snap()), Text(bar.laid)]);
            TEnd(go, UIControlEventTouchUpOutside);
            t = WaitLaid(bar, full, 1.0);
            Check(t >= 0 && t <= 0.2 && !gOverlay, [NSString stringWithFormat:@"touchend: lifted outside it: laid out at once, nothing opened (%@ within %@)", Text(bar.laid), Took(t)]);
        } else if ([sc isEqualToString:@"nohold"]) {
            // nothing of ours open: as before, the first answer and the card's titles reach the bar as they come (B12's thin first answer)
            CFTimeInterval c = CACurrentMediaTime();
            MABRegisterMenus();
            double t = WaitLaid(bar, thin, 1.0);
            Check(t >= 0 && t <= 0.3, [NSString stringWithFormat:@"nohold: the first answer on the bar within 0.3 s of the word (%@, %@)", Text(bar.laid), Took(t)]);
            Run(1.0);
            c = CACurrentMediaTime();
            chrome.kc = MapsCard();
            Busy(0.1, 3.0);
            double t2 = [bar.laid isEqualToArray:full] ? bar.laidAt - c : -1;
            Check(t2 >= 0 && t2 <= 2.5 && [tv.laid isEqualToArray:full], [NSString stringWithFormat:@"nohold: the card's titles within 2.5 s with nothing open, as B12's fix has them (%@, %@)", Text(bar.laid), Took(t2)]);
            // then a menu opened and closed with nothing coming meanwhile: the bar is not laid out again for it, nothing logged
            int layouts0 = bar.layouts, asks0 = gAsks;
            TOpen(); Run(1.0); TClose(); Run(0.5);
            TOpen(); Run(0.3); TRemoveNow(); TOpen(); Run(0.3); TClose(); Run(0.5);   // (and a switch)
            Check(bar.layouts == layouts0 && gAsks == asks0 && bar.movedUnder == 0, [NSString stringWithFormat:@"nohold: menus opened and closed with nothing new: no layout, no ask for them (%d, %d)", bar.layouts - layouts0, gAsks - asks0]);
            Check(Lines(@"[appmenus] ", @"wait for our menu or panel") == 0 && Lines(@"[appmenus] our menu or panel is gone", nil) == 0, @"nohold: no hold logged");
            // (F-7b) and a finger on a title, lifted inside it, outside it, or taken by a system gesture, with nothing new meanwhile: no layout for it
            TButton *go = TTitle(bar, nil);
            layouts0 = bar.layouts;
            UIControlEvents ends[3] = { UIControlEventTouchUpInside, UIControlEventTouchUpOutside, UIControlEventTouchCancel };
            for (int i = 0; i < 3; i++) { go.down = YES; Run(0.3); TEnd(go, ends[i]); Run(0.3); }
            Check(bar.layouts == layouts0 && Lines(@"[appmenus] ", @"finger") == 0, [NSString stringWithFormat:@"nohold: a finger on a title and its end with nothing new: no layout, nothing logged (%d)", bar.layouts - layouts0]);
        } else return 2;
        [[NSFileManager defaultManager] removeItemAtPath:gContainer error:nil];
        printf("%s: %d checks, %d failed\n", argv[1], gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
