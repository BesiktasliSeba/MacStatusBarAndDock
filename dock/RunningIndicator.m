// RunningIndicator.m -- a small dot under a Dock icon whose app is currently running, like macOS's own Dock. Replicates Lynx's
// "showDockIndicators" (currently on, never changed).
//
// Reuses the exact mechanism MacStatusBar's own Force Quit panel already uses in production (DMUserRunningApps, in Tweak.x there):
// SBApplicationController.sharedInstance's -runningApplications, a real array of SBApplication objects each with -bundleIdentifier.
// Nothing here is alloc/init'd -- sharedInstance is a singleton accessor, and every object touched (the running SBApplications, this
// icon's own -icon) was already created by the OS.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import "../common/OtherTweaks.h"   // (Lynx 2 drawing its own Dock indicators: ours steps aside)

@interface UIWindow (DMPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

#define RI_DOMAIN CFSTR("com.besiktasliseba.dockrunningindicator")
static BOOL RIEnabled(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), RI_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return YES;   // default on, matching Lynx's current setting
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : YES;
    CFRelease(v);
    return on;
}
// The switch, kept (no preferences read per icon layout or per poll): re-read when Settings posts its change. Off as well while Lynx 2's own
// "showDockIndicators" is on (two dots otherwise; OtherTweaks.h).
#define RI_NOTIFY "com.besiktasliseba.dockrunningindicator/prefsChanged"
static int gRIWanted = -1;
static BOOL RIWanted(void) {
    if (gRIWanted < 0) {
        CFPreferencesAppSynchronize(RI_DOMAIN);
        gRIWanted = RIEnabled() && !MSBDOtherTweakDoing(kMSBDDupDockIndicators, YES);
    }
    return gRIWanted == 1;
}

// Same "is this icon inside the Dock's platter" check DockMagnification's own Tweak.x already uses (DMIsDockIcon) -- reimplemented
// locally rather than exported/shared across files, to keep this feature self-contained.
static BOOL RIIsDockIcon(UIView *icon) {
    Class platter = objc_getClass("SBFloatingDockPlatterView");
    if (!platter) return NO;
    for (UIView *v = icon.superview; v; v = v.superview) if ([v isKindOfClass:platter]) return YES;
    return NO;
}

static NSSet<NSString *> *RIRunningBundleIDs(void) {
    Class controllerClass = objc_getClass("SBApplicationController");
    if (!controllerClass) return nil;
    SEL sharedSel = NSSelectorFromString(@"sharedInstance");
    if (![(id)controllerClass respondsToSelector:sharedSel]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, sharedSel);
    SEL runningSel = NSSelectorFromString(@"runningApplications");
    if (!controller || ![controller respondsToSelector:runningSel]) return nil;
    id running = ((id (*)(id, SEL))objc_msgSend)(controller, runningSel);
    if (![running respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) return nil;
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    for (id app in (id<NSFastEnumeration>)running) {
        if ([app respondsToSelector:@selector(bundleIdentifier)]) {
            NSString *bid = [app valueForKey:@"bundleIdentifier"];
            if (bid.length) [ids addObject:bid];
        }
    }
    return ids;
}

static const void *kDotKey = &kDotKey;

// Called from Tweak.x's EXISTING `%hook SBIconView -layoutSubviews` (which already exists there for the Launchpad icon overlay) —
// deliberately NOT a second %hook of the same method in this file: Logos generates its hook scaffolding per class+selector, and two
// separate %hook blocks for the SAME method within the SAME dylib (unlike across separate dylibs, which chain fine at runtime) would
// very likely collide at link time. One shared call site in Tweak.x avoids that entirely.
static void RIUpdate(UIView *iconView, NSSet<NSString *> *running);
void DMUpdateRunningIndicator(UIView *iconView) { RIUpdate(iconView, nil); }
static void RIUpdate(UIView *iconView, NSSet<NSString *> *running) {   // (running: the set read once for the whole Dock, or nil = read it here)
    if (!RIWanted() || !RIIsDockIcon(iconView)) {
        UIView *dot = objc_getAssociatedObject(iconView, kDotKey);
        dot.hidden = YES;
        return;
    }
    id icon = nil;
    SEL iconSel = NSSelectorFromString(@"icon");
    id me = iconView;
    if ([me respondsToSelector:iconSel]) icon = ((id (*)(id, SEL))objc_msgSend)(me, iconSel);
    NSString *bundleID = nil;
    for (NSString *key in @[@"bundleIdentifier", @"applicationBundleID", @"leafIdentifier"]) {
        if ([icon respondsToSelector:NSSelectorFromString(key)]) { bundleID = [icon valueForKey:key]; if (bundleID.length) break; }
    }
    if (!running) running = RIRunningBundleIDs();
    BOOL isRunning = bundleID.length && [running containsObject:bundleID];

    UIView *dot = objc_getAssociatedObject(iconView, kDotKey);
    if (!isRunning) { dot.hidden = YES; return; }
    if (!dot) {
        dot = [[UIView alloc] init];
        dot.backgroundColor = [UIColor labelColor];
        dot.userInteractionEnabled = NO;
        objc_setAssociatedObject(iconView, kDotKey, dot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [iconView addSubview:dot];
    }
    CGFloat d = MAX(4.0, iconView.bounds.size.width * 0.045);
    dot.frame = CGRectMake((iconView.bounds.size.width - d) / 2.0, iconView.bounds.size.height - d - 1.0, d, d);
    dot.layer.cornerRadius = d / 2.0;
    dot.hidden = NO;
    [iconView bringSubviewToFront:dot];
}

// SYNC FIX (2026-09-23): the dot only updated from SBIconView's existing -layoutSubviews hook, which the OS calls when a view's
// OWN layout is invalidated -- not automatically just because some OTHER app's running state changed elsewhere in the system. That made
// it correct on first paint but stale afterward: force-quitting an app (from our own Force Quit panel, a 3D-Touch/Haptic-Touch menu, or
// the App Switcher) never touches the Dock icon's layout, so its dot could keep showing long after the app was actually gone. Catching
// every individual quit PATH with its own hook would be fragile (there are several, and some are Apple's own private code we can't see
// into) -- a periodic poll sidesteps that entirely: recheck the real running-app set on a short interval and re-apply directly, so the
// dots are eventually correct regardless of what caused the change, matching how Lynx's own version apparently worked.
static void DMCollectDockIconViews(UIView *root, NSMutableArray *out) {
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:objc_getClass("SBIconView")]) [out addObject:v];
        else DMCollectDockIconViews(v, out);
    }
}
static void RIResyncDock(void) {
    Class platterClass = objc_getClass("SBFloatingDockPlatterView");
    if (!platterClass) return;
    NSMutableArray *icons = [NSMutableArray array];
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        DMCollectDockIconViews(w, icons);
    }
    NSSet *running = RIWanted() ? RIRunningBundleIDs() ?: [NSSet set] : nil;   // (once per pass, not once per icon)
    for (UIView *iconView in icons) RIUpdate(iconView, running);
}
// The poll runs only while it has something to do: the switch on (and Lynx not drawing its own) and the screen on. It is suspended otherwise, and
// resumed (with one pass at once) when the screen comes back or the switch changes.
void DMStartRunningIndicatorPoll(void) {
    static dispatch_source_t timer;
    static BOOL running = NO;
    static int blankToken = 0;
    if (timer) return;   // only ever started once
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), (uint64_t)(0.75 * NSEC_PER_SEC), 100 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ RIResyncDock(); });
    void (^apply)(BOOL) = ^(BOOL passNow) {
        uint64_t blank = 0;
        if (blankToken) notify_get_state(blankToken, &blank);
        BOOL want = RIWanted() && !blank;
        if (want && !running) { dispatch_resume(timer); running = YES; }
        else if (!want && running) { dispatch_suspend(timer); running = NO; }
        if (passNow && !blank) RIResyncDock();   // (after a change: the dots follow at once, hidden too when switched off)
    };
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blankToken, dispatch_get_main_queue(), ^(int t) { apply(YES); });
    int prefsToken = 0;
    notify_register_dispatch(RI_NOTIFY, &prefsToken, dispatch_get_main_queue(), ^(int t) { gRIWanted = -1; apply(YES); });
    apply(NO);
}
