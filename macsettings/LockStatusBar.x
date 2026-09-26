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
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../common/OtherTweaks.h"

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

%hook UIViewController
- (void)_setFakeStatusBarEnabled:(BOOL)enabled {
    Class coverSheetClass = objc_getClass("CSCoverSheetViewController");
    BOOL forceOff = coverSheetClass && [self isKindOfClass:coverSheetClass] && LSBHidden() && !MSBDOtherTweakDoing(kMSBDDupLockStatusBar, YES);   // (Lynx does it: left to it)
    %orig(forceOff ? NO : enabled);
}
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

%ctor {
    %init;
    // (CSCoverSheetViewController may not be loaded yet when we start: hook it once it is, as the note above explains)
    __block int tries = 0;
    __block void (^attempt)(void);
    void (^a)(void) = ^{
        Class c = objc_getClass("CSCoverSheetViewController");
        if (c && [c instancesRespondToSelector:NSSelectorFromString(@"scrollablePageViewController:scrollViewDidScroll:")]) { %init(LSBGrabber); attempt = nil; return; }
        if (++tries < 30) { void (^again)(void) = attempt; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), again); }
        else attempt = nil;
    };
    attempt = a;
    attempt();
}
