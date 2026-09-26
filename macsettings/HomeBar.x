// HomeBar.x -- hides the home indicator (the pill at the bottom edge), everywhere: the Home Screen and every app. Replicates Trim's
// "Remove Home Bar" (on by default there, the owner has never changed it) so Trim can eventually be removed.
//
// Only the INDICATOR is hidden — the swipe-up-from-the-bottom-edge gesture itself (to go home, or hold to open the app switcher) is
// untouched. iOS keeps the two completely separate: -prefersHomeIndicatorAutoHidden only controls whether the little pill is drawn, never
// whether the system gesture recognizer at the bottom edge responds to a touch, so this has no effect on that at all.
//
// -prefersHomeIndicatorAutoHidden is a PUBLIC, documented UIKit API (an app is meant to override it in its own view controllers) — not a
// private class or method, so (learned the hard way tonight, see the ipad-tweak-dev-setup memory) this is safe to install in any process
// that merely links UIKit without ever becoming a real app: a headless daemon has no view controllers ever put on screen, so the method is
// simply never invoked there, exactly like MacLargeTitles' hooks (same filter, same reasoning) never fire outside a real UI process.
#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <dlfcn.h>

// Settings > Mac Settings > Home Bar (a switch next to the SSH one, added in Tweak.x) — labelled and read as "is the home bar showing",
// not "is it being hidden": OFF (the default — matching Trim's own default, which is hidden) means no home bar; ON shows it normally.
// A separate key from an earlier "enabled means hide" version of this switch, deliberately: reinterpreting the same stored value under
// flipped semantics would have silently inverted anyone who had already set it. Read live, not cached, so switching it in Settings takes
// effect on the next natural re-check (a rotation, a view controller transition, ...) with no respring needed.
#define HB_DOMAIN CFSTR("com.besiktasliseba.machomebar")
static BOOL HBShowing(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("showHomeBar"), HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;   // default off (hidden), matching Trim's own default
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : NO;
    CFRelease(v);
    return on;
}

%hook UIViewController
- (BOOL)prefersHomeIndicatorAutoHidden {
    if (!HBShowing()) return YES;
    return %orig;
}
%end

// -prefersHomeIndicatorAutoHidden only makes the pill fade out after a few idle seconds (it came straight back on every touch, and was
// fully visible for the first seconds of every app -- measured on the M1 after Trim's "Remove Home Bar" was switched off, Phase 2b). The pill
// itself is SpringBoard's MTLumaDodgePillView (in SBMainDisplaySceneLayoutWindow), the view Trim hides too: in SpringBoard it is kept hidden
// outright while the setting is off. Only its visibility is touched; the swipe-up gesture lives elsewhere and keeps working.
@interface MTLumaDodgePillView : UIView
@end
// Does this device have a home bar at all? Published for MacSettings' Settings row (hidden where there is nothing to switch):
// "com.besiktasliseba.machomebar.pill" = 1 none, 2 yes (0 = not known yet, the row then shows). Yes as soon as SpringBoard makes a pill view (this also
// catches gesture tweaks that draw one on Home-button devices), or when MobileGestalt's HomeButtonType says there is no Home button (2).
// Only the HOME pill: SpringBoard uses the same pill view for other things too (the corner resize grabbers of app windows, seen on the iPad 2),
// which must stay as they are. Home pills live in a home grabber (apps, Home Screen) or the Lock Screen's home affordance.
static BOOL HBIsHomePill(UIView *pill) {
    for (UIView *u = pill.superview; u; u = u.superview) {
        NSString *n = NSStringFromClass([u class]);
        if ([n containsString:@"HomeGrabber"] || [n containsString:@"HomeAffordance"]) return YES;
        if ([n containsString:@"ResizeGrabber"]) return NO;
    }
    return NO;
}
static uint64_t gHBPillPublished = 0;
static void HBPublishPill(uint64_t v, NSString *why) {
    static int token = 0; static uint64_t last = 0;
    if (!token) notify_register_check("com.besiktasliseba.machomebar.pill", &token);
    if (v == last || (last == 2 && v != 2)) return;   // (once a pill has been seen, the answer stays yes)
    last = v; gHBPillPublished = v;
    notify_set_state(token, v);
    notify_post("com.besiktasliseba.machomebar.pill.changed");
    if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "[homebar] pill state %llu (%s)\n", v, why.UTF8String); fclose(f); } }
}
// A pill counts only where it is really in use: SpringBoard keeps pill views even on Home-button iPads, inside home grabbers that are hidden for
// good (in the Control Center and alert windows: seen on the iPad 2). So: none of its parents hidden (the pill itself may be, by us), checked a
// moment after it arrives.
static void HBCheckPillInUse(UIView *pill) {
    if (gHBPillPublished == 2) return;
    __weak UIView *weakPill = pill;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *p = weakPill;
        if (!p || !p.window || p.window.hidden || gHBPillPublished == 2) return;
        for (UIView *u = p.superview; u; u = u.superview) if (u.hidden) return;
        HBPublishPill(2, [NSString stringWithFormat:@"a pill in use in %@", NSStringFromClass([p.window class])]);
    });
}
%group HBSpringBoard
%hook MTLumaDodgePillView
- (void)didMoveToWindow {
    %orig;
    if (!HBIsHomePill((UIView *)self)) return;
    if (((UIView *)self).window) HBCheckPillInUse((UIView *)self);
    if (!HBShowing()) self.hidden = YES;
}
- (void)layoutSubviews {
    %orig;
    if (!HBIsHomePill((UIView *)self)) return;
    HBCheckPillInUse((UIView *)self);
    if (!HBShowing() && !self.hidden) self.hidden = YES;
}
- (void)setHidden:(BOOL)hidden {
    BOOL want = (HBShowing() || !HBIsHomePill((UIView *)self)) ? hidden : YES;
    %orig(want);
}
%end
// With the Home Bar OFF the pointer must not use the (invisible) bar either: no snap, hover or click at the bottom edge. The grabber asks
// its delegate-style hook whether a pointer interaction may begin (SpringBoard's system pointer interaction); saying no only affects the
// pointer -- finger gestures at the bottom edge are separate recognisers and stay untouched. ON: the stock answer.
@interface SBHomeGrabberView : UIView
@end
%hook SBHomeGrabberView
- (BOOL)shouldBeginPointerInteractionRequest:(id)request atLocation:(CGPoint)location forView:(id)view {
    if (!HBShowing()) return NO;
    return %orig;
}
%end
%end
static void HBRefreshPills(UIView *v, BOOL show) {
    if ([v isKindOfClass:objc_getClass("MTLumaDodgePillView")]) { if (HBIsHomePill(v)) v.hidden = !show; return; }
    for (UIView *s in v.subviews) HBRefreshPills(s, show);
}

// Live switching (Phase 2b): the Settings switch posts com.besiktasliseba.machomebar/changed; every process with UI then asks each of its windows' view
// controllers (and the ones they present) to re-read -prefersHomeIndicatorAutoHidden right away, instead of waiting for a turn or a transition.
static void HBRefresh(UIViewController *vc) {
    if (!vc) return;
    [vc setNeedsUpdateOfHomeIndicatorAutoHidden];
    for (UIViewController *c in vc.childViewControllers) HBRefresh(c);
    if (vc.presentedViewController && vc.presentedViewController.presentingViewController == vc) HBRefresh(vc.presentedViewController);
}
%ctor {
    %init;
    BOOL springboard = [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"];
    if (springboard && objc_getClass("MTLumaDodgePillView")) %init(HBSpringBoard);
    if (springboard) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        void *mg = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
        int (*getInt)(CFStringRef, int) = mg ? (int (*)(CFStringRef, int))dlsym(mg, "MGGetSInt32Answer") : NULL;
        int type = getInt ? getInt(CFSTR("HomeButtonType"), -1) : -1;   // 2 = no Home button (the home bar is the way home)
        BOOL pillSeen = NO;
        SEL allSel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *all = [UIWindow respondsToSelector:allSel] ? ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], allSel, YES, NO) : [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
        Class pill = objc_getClass("MTLumaDodgePillView");
        NSMutableArray *todo = [all mutableCopy];
        while (todo.count && !pillSeen) { UIView *v = todo.lastObject; [todo removeLastObject]; if (pill && [v isKindOfClass:pill]) pillSeen = pillSeen || HBIsHomePill(v); else if (!v.hidden) [todo addObjectsFromArray:v.subviews]; }   // (not inside hidden grabbers)
        if (pillSeen || type == 2) HBPublishPill(2, [NSString stringWithFormat:@"HomeButtonType %d, pill view %d", type, pillSeen]);
        else if (type >= 0) HBPublishPill(1, [NSString stringWithFormat:@"HomeButtonType %d, no pill view", type]);
    });
    int token = 0;
    notify_register_dispatch("com.besiktasliseba.machomebar/changed", &token, dispatch_get_main_queue(), ^(int t) {
        UIApplication *app = [UIApplication sharedApplication];
        if (!app) return;
        CFPreferencesSynchronize(HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // (the new value, not this process's cached one)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *w in app.windows) HBRefresh(w.rootViewController);
        if (springboard) {   // (SpringBoard: the pill views themselves, in every window including internal ones)
            BOOL show = HBShowing();
            if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "[homebar] changed: showing %d\n", show); fclose(f); } }
            SEL allSel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
            NSArray *all = [UIWindow respondsToSelector:allSel] ? ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], allSel, YES, NO) : nil;
            for (UIWindow *w in all ?: app.windows) HBRefreshPills(w, show);
        }
#pragma clang diagnostic pop
    });
}
