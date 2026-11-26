// LockStatusBar.x -- hides the status bar on the Lock Screen. Replicates Lynx's "hideStatusOnLockScreen" (on, for the owner specifically —
// see the note below on the default).
//
// CSCoverSheetViewController (the Lock Screen's own controller) already has an official-feeling toggle for exactly this,
// -_setFakeStatusBarEnabled: (found via a full method dump — a real API, not a view visibility hack), so this hooks that instead of
// reaching into the private _fakeStatusBar view directly.
//
// Default is OFF (status bar shown, stock behavior) — the owner explicitly asked for this to default off for anyone else installing the
// tweak fresh, even though he currently has the equivalent Lynx setting on; his own device's pref is seeded to ON once, separately,
// outside this code (a one-time `defaults write`), not by changing this default.
// Settings > Status Bar > Lock Screen > "Hide Status Bar on Lock Screen" (2026-09-25) switches it; read each time the Lock Screen sets its bar, so
// it applies the next time the Lock Screen shows (no respring). A missing value is off, so updaters keep what they had (no freeze needed).
//
// 1.8.9 (B113): the Cover Sheet's own copy is the bar seen at rest on 15-17 only. On 18 the bar seen on the Lock Screen is SpringBoard's status
// bar window (above the Cover Sheet's window), which the Cover Sheet asks for through SpringBoard's Lock Screen status bar controller, so turning
// the copy off changed nothing there and the bar stayed (18.5, 25 Nov; published 1.8.8.4 too) while the log said "hidden". The switch now
// also hides that bar through SpringBoard's own call for it (common/LockBarHide.h: our reason in its set while the Cover Sheet shows, given back
// at the start of its dismissal, when iPadOS invalidates its own, when it is gone and at a switch-off), on every iPadOS that has the call
// (15-18), and the log says what is drawn at the top right after it, read from the bars themselves.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#import "../common/OtherTweaks.h"
#define LBH_REASON @"com.besiktasliseba.maclockstatusbar"
#include "../common/LockBarHide.h"
#include "../common/HookTypes.h"
#define LSB_NOTIFY "com.besiktasliseba.maclockstatusbar/prefsChanged"

#define LSB_DOMAIN CFSTR("com.besiktasliseba.maclockstatusbar")
static int gLSBHiddenCache = -1;   // (the last reading, for the per-frame page scroll below: refreshed whenever the Lock Screen sets its bar)
static BOOL LSBHidden(void) {
    CFPreferencesAppSynchronize(LSB_DOMAIN);   // (a change made in Settings is seen at once; this runs only when the Lock Screen sets its bar)
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("hideStatusBar"), LSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) { gLSBHiddenCache = 0; return NO; }   // default off — see the file header
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : NO;
    CFRelease(v);
    gLSBHiddenCache = on;
    return on;
}
static BOOL LSBHiddenCached(void) { return gLSBHiddenCache < 0 ? LSBHidden() : gLSBHiddenCache == 1; }

// Hooked on UIViewController generically, filtered by a fresh isKindOfClass: check at call time, not on CSCoverSheetViewController
// directly — the same lesson learned the hard way with the Ethernet crash fix tonight: a CoverSheet-specific class may well belong to a
// plugin bundle SpringBoard has not loaded yet at %ctor time, in which case hooking it by name directly silently installs nothing.
@interface CSCoverSheetViewController : UIViewController
@end

static BOOL LSBIsCoverSheet(id controller) { Class c = objc_getClass("CSCoverSheetViewController"); return c && [controller isKindOfClass:c]; }
static void LSBApplyGrabberHidden(NSArray<UIView *> *views);
static NSArray<UIView *> *LSBGrabberViews(UIViewController *coverSheet);
static BOOL gLSBCoverOwn;   // (the Cover Sheet's own -_setFakeStatusBarEnabled: hooked: 17+, and 15/16 where it overrides UIViewController's)
static BOOL LSBForceOff(id controller) {
    Class coverSheetClass = objc_getClass("CSCoverSheetViewController");
    return coverSheetClass && [controller isKindOfClass:coverSheetClass] && LSBHidden() && !MSBDOtherTweakDoing(kMSBDDupLockStatusBar, YES);   // (Lynx does it: left to it)
}
%group LSBGeneric
%hook UIViewController
- (void)_setFakeStatusBarEnabled:(BOOL)enabled {
    %orig(LSBForceOff(self) ? NO : enabled);
    if (LSBIsCoverSheet(self)) LSBApplyGrabberHidden(LSBGrabberViews((UIViewController *)self));
}
%end
%end
// iPadOS 17+: -_setFakeStatusBarEnabled: is no longer UIViewController's; only CSCoverSheetViewController has it (17.5.1 probe: missing on
// UIViewController; 18.5: v20@0:8B16 on CSCoverSheetViewController), so the generic hook above installed nothing and the switch did nothing on 17/18.
// There it is hooked on the Lock Screen's controller itself, once that class is loaded (deferred like LSBGrabber below).
%group LSBCover
%hook CSCoverSheetViewController
- (void)_setFakeStatusBarEnabled:(BOOL)enabled {
    %orig(LSBForceOff(self) ? NO : enabled);
    if (LSBIsCoverSheet(self)) LSBApplyGrabberHidden(LSBGrabberViews((UIViewController *)self));
}
%end
%end

// The Control Center grabber (the short line at the top right of the Lock Screen) is not part of the sliding pages: the Lock Screen places it
// under the status bar it follows (CSTeachableMomentsContainerView's statusBarToFollow). With the status bar hidden here it stayed in its spot
// alone while the page slid to the Today View or the camera (26 Sep). While the bar is hidden, the grabber now moves with the page: on
// every scroll of the Lock Screen's pages it is shifted by how far the pages are from the main page, and put back exactly when they rest there.
// Plain public UIView/UIScrollView properties on views SpringBoard already made; every private accessor is checked first (nothing happens
// if one is missing), and nothing changes while the status bar is shown (stock behaviour).
#if DEBUG
static void LSBLog(NSString *line) {
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macstatusbar.log", "a"); if (!f) return;
    fprintf(f, "[lockgrabber] %s\n", line.UTF8String); fclose(f);
}
#else
#define LSBLog(...) do { } while (0)
#endif
static NSArray<UIView *> *LSBGrabberViews(UIViewController *coverSheet) {
    UIViewController *tm = nil;
    @try { tm = [coverSheet valueForKey:@"_teachableMomentsContainerViewController"]; } @catch (NSException *e) { return @[]; }
    if (![tm isKindOfClass:[UIViewController class]] || !tm.isViewLoaded) return @[];
    UIView *container = tm.view;
    NSMutableArray *views = [NSMutableArray array];
    for (NSString *name in @[@"controlCenterGrabberContainerView", @"controlCenterGlyphContainerView"]) {
        SEL sel = NSSelectorFromString(name);
        if (![container respondsToSelector:sel]) continue;
        id v = ((id (*)(id, SEL))objc_msgSend)(container, sel);
        if ([v isKindOfClass:[UIView class]]) [views addObject:v];
    }
    return views;
}
static void LSBFollowPages(UIViewController *coverSheet, UIScrollView *sv) {
    static BOOL moved = NO;
    BOOL hidden = LSBHiddenCached();   // (no preferences read per frame: the value from when the Lock Screen last set its bar)
    if (!hidden && !moved) return;     // (the usual case, setting off: nothing to do, not even the view lookup)
    NSArray<UIView *> *views = LSBGrabberViews(coverSheet);
    if (!views.count) return;
    CGFloat dx = 0;
    SEL mainSel = NSSelectorFromString(@"_indexOfMainPage");
    CGFloat w = sv.bounds.size.width;
    if (hidden && w > 1 && [coverSheet respondsToSelector:mainSel] && [sv isKindOfClass:[UIScrollView class]]) {
        NSUInteger main = ((NSUInteger (*)(id, SEL))objc_msgSend)(coverSheet, mainSel);
        dx = main * w - sv.contentOffset.x;          // how far the pages are from the main page (> 0: slid right, toward the Today View)
        if (fabs(dx) < 0.5 || fabs(dx) > w * 1.05) dx = 0;   // (at rest on the main page, or an offset we don't understand: leave it where iOS put it)
    }
    if (dx == 0 && !moved) return;
    for (UIView *v in views) v.transform = dx == 0 ? CGAffineTransformIdentity : CGAffineTransformMakeTranslation(dx, 0);
    if ((dx != 0) != moved) LSBLog(dx != 0 ? [NSString stringWithFormat:@"pages sliding (%.0f pt): the Control Center grabber moves with them", dx] : @"pages back on the main page: grabber back in place");
    moved = dx != 0;
}
%group LSBGrabber
%hook CSCoverSheetViewController
- (void)scrollablePageViewController:(id)pvc scrollViewDidScroll:(UIScrollView *)sv {
    %orig;
    LSBFollowPages((UIViewController *)self, sv);
}
%end
%end
// ...and it goes with the Lock Screen's status bar: while that bar is hidden here, so is the grabber (and its teaching glyph). The teachable-moments
// view puts the grabber under the status bar it follows; with the Lock Screen's own bar off that is SpringBoard's bar -- ours -- and the line stayed
// right under our menu bar (A12Z 18.5, KT 31 Oct: statusBarToFollow STUIStatusBar_Wrapper, the grabber 61 x 2.5 pt at alpha 0.5; 15.6.1 showed it
// too, 26 Sep). Hidden by its own -hidden (iOS animates its alpha, not that), shown again when the bar is shown; checked whenever the view is laid
// out and whenever the Lock Screen sets its bar.
static const void *kLSBGrabberHiddenKey = &kLSBGrabberHiddenKey;
static void LSBApplyGrabberHidden(NSArray<UIView *> *views) {
    BOOL hide = LSBHiddenCached() && !MSBDOtherTweakDoing(kMSBDDupLockStatusBar, YES);
    for (UIView *v in views) {
        if (hide && !v.hidden) {
            v.hidden = YES;
            objc_setAssociatedObject(v, kLSBGrabberHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            LSBLog(@"Hide Status Bar on Lock Screen is on: the Control Center grabber goes with the bar");
        } else if (!hide && objc_getAssociatedObject(v, kLSBGrabberHiddenKey)) {
            v.hidden = NO;
            objc_setAssociatedObject(v, kLSBGrabberHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            LSBLog(@"Hide Status Bar on Lock Screen is off: the Control Center grabber is back");
        }
    }
}
static NSArray<UIView *> *LSBContainerGrabberViews(UIView *container) {   // (the same two views as LSBGrabberViews, from the teachable-moments view itself)
    NSMutableArray *views = [NSMutableArray array];
    for (NSString *name in @[@"controlCenterGrabberContainerView", @"controlCenterGlyphContainerView"]) {
        SEL sel = NSSelectorFromString(name);
        if (![container respondsToSelector:sel]) continue;
        id v = ((id (*)(id, SEL))objc_msgSend)(container, sel);
        if ([v isKindOfClass:[UIView class]]) [views addObject:v];
    }
    return views;
}
@interface CSTeachableMomentsContainerView : UIView
@end
%group LSBGrabberHide
%hook CSTeachableMomentsContainerView
- (void)layoutSubviews {
    %orig;
    LSBApplyGrabberHidden(LSBContainerGrabberViews((UIView *)self));
}
%end
%end

// ---- SpringBoard's own bar on the Lock Screen (B113, 1.8.9; common/LockBarHide.h) ----
// Our reason goes into SpringBoard's set while the Cover Sheet shows with the switch on (no other modification doing it), from its appearance and
// every status update iPadOS makes for it; it comes out at the start of the dismissal (the Cover Sheet then slides away with its own copy, turned
// off above, while SpringBoard's bar becomes the Home Screen's or the app's), when iPadOS invalidates its own Lock Screen bar requests, when the
// Cover Sheet is gone and at a switch-off. The flag "hid the bar for this appearance" (LBH_FLAG_KEY) is what Mac Lock Screen reads.
#if DEBUG
static void LSBBarLog(NSString *line) {
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macstatusbar.log", "a"); if (!f) return;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS";
    fprintf(f, "%s [lockbar] %s\n", [df stringFromDate:[NSDate date]].UTF8String, line.UTF8String); fclose(f);
}
#else
#define LSBBarLog(...) do { } while (0)
#endif
static BOOL gLSBDismissing;        // from the start of the Cover Sheet's dismissal until it appears again or is gone
static int gLSBHeals;              // re-asks since the Cover Sheet's last status request (at most 2 per request)
static BOOL gLSBTruthQueued;       // (one read queued at a time)
static BOOL gLSBNoCallLogged;
static BOOL LSBCoverShown(UIViewController *cs) { return cs.isViewLoaded && cs.view.window && !cs.view.window.hidden; }
static void LSBSetFlag(UIViewController *cs, BOOL hid) {
    BOOL was = objc_getAssociatedObject(cs, LBH_FLAG_KEY) != nil;
    if (was == hid) return;
    objc_setAssociatedObject(cs, LBH_FLAG_KEY, hid ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[NSNotificationCenter defaultCenter] postNotificationName:LBH_CHANGED_NOTE object:cs];   // (in-process: Mac Lock Screen reads the bar again)
}
static void LSBTruth(UIViewController *cs, const char *when);
// The one place the reason goes in or out. switchOn: the switch as just read (LSBHidden) or cached.
static void LSBRealBar(UIViewController *cs, BOOL switchOn, const char *when) {
    if (!LSBIsCoverSheet(cs)) return;
    BOOL other = switchOn && MSBDOtherTweakDoing(kMSBDDupLockStatusBar, YES);
    BOOL shown = LSBCoverShown(cs);
    int step = LBHStep(LBHReasonIn(), switchOn, other, shown, gLSBDismissing);
    LSBSetFlag(cs, switchOn && !other && shown && !gLSBDismissing);
    if (step > 0) {
        int r = LBHSet(cs, YES);
        if (r == -2) {
            if (!gLSBNoCallLogged) { gLSBNoCallLogged = YES; LSBBarLog(@"this iPadOS has no SpringBoard call for the Lock Screen's bar: only the Cover Sheet's own copy is turned off"); }
            LSBTruth(cs, when);
            return;
        }
        LSBBarLog([NSString stringWithFormat:@"SpringBoard asked to hide the Lock Screen's bar (%s)", when]);
        LSBTruth(cs, when);
    } else if (step < 0) {
        LBHSet(cs, NO);
        LSBBarLog([NSString stringWithFormat:@"the Lock Screen's bar given back to iPadOS (%s)", when]);
    }
}
// What is drawn at the top right, read one main-queue turn later (an animation SpringBoard starts with the change has set its end values
// by then). The log says what IS drawn, never what was asked. SpringBoard's bar still drawn with our reason in: our hidden request was made
// before the Cover Sheet's own one at the same level (applied in order), so it is made again (twice at most per request of the Cover Sheet's:
// a wake, a page change or a comeback inside one appearance makes a new request, review finding 2).
static void LSBTruth(UIViewController *cs, const char *when) {
    if (gLSBTruthQueued) return;
    gLSBTruthQueued = YES;
    __weak UIViewController *weakCs = cs;
    dispatch_async(dispatch_get_main_queue(), ^{
        gLSBTruthQueued = NO;
        UIViewController *c = weakCs;
        if (!c || !LSBCoverShown(c) || gLSBDismissing) return;
        LBHBar b = LBHVisibleBar(c);
        if (!b.drawn) { LSBBarLog([NSString stringWithFormat:@"the Lock Screen's status bar is hidden: nothing drawn at the top right (%s)", when]); return; }
        LSBBarLog([NSString stringWithFormat:@"the Lock Screen's status bar is STILL drawn at the top right: %s (%@, level %.0f)%s (%s)", b.what, NSStringFromClass([b.view class]),
                   b.window.windowLevel, b.ourMenuBar ? ", our menu bar's copy" : "", when]);
        if (LBHReasonIn() && gLSBHeals < 2 && b.window && LBHIsStatusBarWindow(b.window)) {
            gLSBHeals++;
            LBHSet(c, NO); LBHSet(c, YES);
            LSBBarLog(@"hidden request made again (after the Cover Sheet's own)");
            LSBTruth(c, "again");
        }
    });
}
static BOOL gLSBSwitchCache;   // the switch as read at the last appearance or note (the status updates in between read this)
static __weak UIViewController *gLSBCover;   // (the Cover Sheet's controller, for the switch's note)
// The Cover Sheet made a status request (its -_updateStatusBar, or the alpha request it sends SpringBoard's controller): our reason follows,
// and with it in, what is drawn is read a turn later and our request made again if the Cover Sheet's own came after it.
static void LSBStatusUpdated(UIViewController *cs, const char *when) {
    if (!gLSBSwitchCache && !LBHReasonIn()) return;
    gLSBHeals = 0;
    LSBRealBar(cs, gLSBSwitchCache, when);
    if (LBHReasonIn()) LSBTruth(cs, when);
}
// (each B113 group goes in only where its methods have the types its declarations compile to: common/HookTypes.h; the tables are read on
//  15.6.1, 16.7.7, 17.5.1 and 18.5 and checked by tools/test-hooktypes.sh. A version where one differs keeps the group out, said in the log)
static BOOL LSBTypesOK(const MSBDHookSig *sigs, size_t n, const char *group) {
    NSString *wrong = nil;
    if (MSBDHookGroupTypesOK(sigs, n, "Hide Status Bar on Lock Screen", group, &wrong)) return YES;
    LSBBarLog([NSString stringWithFormat:@"%s not hooked (only the Cover Sheet's own copy is turned off here): %@", group, wrong]);
    return NO;
}
#define LSB_TYPES_OK(G) LSBTypesOK(kHookSigs_##G, sizeof(kHookSigs_##G) / sizeof(kHookSigs_##G[0]), #G)
static const MSBDHookSig kHookSigs_LSBReal[] = {
    {"CSCoverSheetViewController", "viewDidLoad", "v@:"},
    {"CSCoverSheetViewController", "viewWillAppear:", "v@:B"},
    {"CSCoverSheetViewController", "viewDidAppear:", "v@:B"},
    {"CSCoverSheetViewController", "_updateStatusBar", "v@:"},
    {"CSCoverSheetViewController", "viewWillDisappear:", "v@:B"},
    {"CSCoverSheetViewController", "viewDidDisappear:", "v@:B"},
    {"CSCoverSheetViewController", "_invalidateStatusBarAssertions", "v@:"},
};
%group LSBReal
%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig; gLSBCover = (UIViewController *)self;
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gLSBCover = (UIViewController *)self;
    gLSBDismissing = NO; gLSBHeals = 0;
    gLSBSwitchCache = LSBHidden();
    LSBRealBar((UIViewController *)self, gLSBSwitchCache, "appearing");
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    gLSBDismissing = NO;
    LSBRealBar((UIViewController *)self, gLSBSwitchCache, "shown");
}
- (void)_updateStatusBar {
    %orig;
    LSBStatusUpdated((UIViewController *)self, "a status update");
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    gLSBDismissing = YES;
    LSBRealBar((UIViewController *)self, gLSBSwitchCache, "the dismissal starts");
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    gLSBDismissing = NO;
    if (LBHReasonIn()) { LBHSet(self, NO); LSBBarLog(@"the Lock Screen's bar given back to iPadOS (the Cover Sheet is gone)"); }
    LSBSetFlag((UIViewController *)self, NO);
}
- (void)_invalidateStatusBarAssertions {
    if (LBHReasonIn()) { LBHSet(self, NO); LSBBarLog(@"the Lock Screen's bar given back to iPadOS (iPadOS invalidates its own Lock Screen bar requests)"); }
    LSBSetFlag((UIViewController *)self, NO);
    %orig;
}
%end
%end
// (the Cover Sheet's alpha request reaches SpringBoard's controller also from blocks run after -_updateStatusBar returns: alongside animations).
// The alpha is an NSNumber (nil: the alpha left as it is), the style an integer (-1: left as it is), the legibility settings an object or nil:
// "v40@0:8@16q24@32" on 15.6.1, 16.7.7, 17.5.1 and 18.5. Declared as a double it was read from the wrong register: a 1.8.9 test build's Lock
// Screen crash (the style taken for the settings object and retained). The hook reads none of them; %orig passes them on as they came.
static const MSBDHookSig kHookSigs_LSBRealAlpha[] = {
    {"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:@q@"},
};
%group LSBRealAlpha
%hook SBDashBoardStatusBarController
- (void)setStatusBarAlpha:(id)alpha style:(long long)style legibilitySettings:(id)ls {
    %orig;
    UIViewController *cs = gLSBCover;
    if (cs && LBHReasonIn()) LSBStatusUpdated(cs, "the Cover Sheet's alpha request");
}
%end
%end
static void LSBPrefsChanged(void) {
    gLSBSwitchCache = LSBHidden();
    UIViewController *cs = gLSBCover;
    if (cs) LSBRealBar(cs, gLSBSwitchCache, gLSBSwitchCache ? "switched on" : "switched off");
    else if (!gLSBSwitchCache && LBHReasonIn()) { LBHSet(nil, NO); LSBBarLog(@"the Lock Screen's bar given back to iPadOS (switched off)"); }
}
%ctor {
    %init;
    SEL fake = NSSelectorFromString(@"_setFakeStatusBarEnabled:");
    BOOL generic = [UIViewController instancesRespondToSelector:fake];   // (15/16: UIViewController's own method, hooked there as before)
    if (generic) %init(LSBGeneric);
    // (CSCoverSheetViewController may not be loaded yet when we start: hook it once it is, as the note above explains)
    __block int tries = 0;
    __block BOOL coverDone = generic;   // (the Cover Sheet's own method: hooked too below when it overrides UIViewController's)
    __block void (^attempt)(void);
    void (^a)(void) = ^{
        Class c = objc_getClass("CSCoverSheetViewController");
        // (17+: the Lock Screen's controller itself. 15/16 too when that class has its own -_setFakeStatusBarEnabled: (16.7.7's and 15.6.1's do, and
        //  16.7.7's never calls UIViewController's): the generic hook alone never saw the Cover Sheet's own call there -- B113's 15/16 check)
        Method own = c ? class_getInstanceMethod(c, fake) : NULL, base = class_getInstanceMethod([UIViewController class], fake);
        BOOL coverHook = !coverDone ? (c && own) : (generic && c && own && base && method_getImplementation(own) != method_getImplementation(base));
        if (coverHook && !gLSBCoverOwn) { gLSBCoverOwn = YES; coverDone = YES; %init(LSBCover); }
        if (coverDone && c && [c instancesRespondToSelector:NSSelectorFromString(@"scrollablePageViewController:scrollViewDidScroll:")]) {
            // (B113: SpringBoard's own bar for the Lock Screen; the methods read on 15.6.1, 16.7.7, 17.5.1 and 18.5. A version missing one keeps
            //  only the Cover Sheet's copy turned off, as before, and the log says so)
            if ([c instancesRespondToSelector:NSSelectorFromString(@"_updateStatusBar")] && [c instancesRespondToSelector:NSSelectorFromString(@"_invalidateStatusBarAssertions")] && LSB_TYPES_OK(LSBReal)) {
                %init(LSBReal);
                Class sbc = objc_getClass("SBDashBoardStatusBarController");
                if ([sbc instancesRespondToSelector:NSSelectorFromString(@"setStatusBarAlpha:style:legibilitySettings:")] && LSB_TYPES_OK(LSBRealAlpha)) %init(LSBRealAlpha);
                int token = 0;
                notify_register_dispatch(LSB_NOTIFY, &token, dispatch_get_main_queue(), ^(int t) { LSBPrefsChanged(); });
            }
            %init(LSBGrabber);
            if (objc_getClass("CSTeachableMomentsContainerView")) %init(LSBGrabberHide);   // (the grabber hidden with the bar; its view's class missing: shown as before)
            attempt = nil; return;
        }
        if (++tries < 30) { void (^again)(void) = attempt; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), again); }
        else attempt = nil;
    };
    attempt = a;
    attempt();
}
