// HomeBar.x -- hides the home indicator (the pill at the bottom edge), everywhere: the Home Screen and every app. Replicates Trim's
// "Remove Home Bar" (on by default there, the owner has never changed it) so Trim can eventually be removed.
//
// The pill is SpringBoard's own MTLumaDodgePillView (in SBMainDisplaySceneLayoutWindow for apps and the Home Screen; the Lock Screen's home
// affordance has one too), the view Trim hides: SpringBoard keeps it hidden outright while the setting is off (below). Only its visibility is
// touched; the swipe up from the bottom edge (go home, hold for the App Switcher) is a separate recogniser and keeps working.
// Until 1.6.0 every app (and SpringBoard) also answered YES to -prefersHomeIndicatorAutoHidden, the public API, which on its own only made the pill
// fade after a few idle seconds (Phase 2b, M1). SpringBoard takes that same answer for the multitasking dots of a full-screen app too
// (-[SBFullScreenSwitcherSceneLiveContentOverlay _updateTopAffordanceAutoHide] -> -[SBTopAffordanceViewController setAutoHides:], 16.7.7), so with
// Hide Multitasking Dots off the dots faded out 2.5 s after every touch, on every iPad, a Home-button one with no home bar at all too (iPad 2,
// 1.6.0, traced). Apps keep their own answer now (a video player still hides both, as Apple has it); nothing of this part runs outside SpringBoard.
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
// effect at once (the switch's notification, below) with no respring needed.
#define HB_DOMAIN CFSTR("com.besiktasliseba.machomebar")
static BOOL HBShowing(void) {   // (SpringBoard)
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("showHomeBar"), HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;   // default off (hidden), matching Trim's own default
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : NO;
    CFRelease(v);
    return on;
}

@interface MTLumaDodgePillView : UIView
@end
// The Cover Sheet's home affordance (CSHomeAffordanceView: the Lock Screen, and Notification Center pulled down) draws its pill with a second
// class, MTStaticColorPillView, next to an MTLumaDodgePillView that iOS keeps at alpha 0 there: with the Home Bar off that pill showed (M1 15.6.1,
// 1.6.0 -- it used to fade a few seconds in, when SpringBoard's own view controllers also answered YES to -prefersHomeIndicatorAutoHidden). Both
// classes are SpringBoard's home pills: the same rule for each (HBSpringBoardStatic, where the class exists).
@interface MTStaticColorPillView : UIView
@end
static BOOL HBIsPillView(UIView *v) {
    static Class luma, staticPill; static dispatch_once_t once;
    dispatch_once(&once, ^{ luma = objc_getClass("MTLumaDodgePillView"); staticPill = objc_getClass("MTStaticColorPillView"); });
    return (luma && [v isKindOfClass:luma]) || (staticPill && [v isKindOfClass:staticPill]);
}
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
%group HBSpringBoardStatic
%hook MTStaticColorPillView
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
%end
static void HBRefreshPills(UIView *v, BOOL show) {
    if (HBIsPillView(v)) { if (HBIsHomePill(v)) v.hidden = !show; return; }   // (either pill class)
    for (UIView *s in v.subviews) HBRefreshPills(s, show);
}

// Live switching: the Settings switch posts com.besiktasliseba.machomebar/changed; SpringBoard shows or hides the pill views at once.
%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;   // (the pill is SpringBoard's; apps keep their own answer)
    if (objc_getClass("MTLumaDodgePillView")) %init(HBSpringBoard);
    if (objc_getClass("MTStaticColorPillView")) %init(HBSpringBoardStatic);   // (the Cover Sheet's home affordance)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
        CFPreferencesSynchronize(HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);   // (the new value, not this process's cached one)
        BOOL show = HBShowing();
        if (MSTestFlag("/tmp/macsettings-debug")) { FILE *f = fopen("/tmp/macsettings.log", "a"); if (f) { fprintf(f, "[homebar] changed: showing %d\n", show); fclose(f); } }
        SEL allSel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSArray *all = [UIWindow respondsToSelector:allSel] ? ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], allSel, YES, NO) : [UIApplication sharedApplication].windows;
#pragma clang diagnostic pop
        for (UIWindow *w in all) HBRefreshPills(w, show);   // (the pill views themselves, in every window including internal ones)
    });
}
