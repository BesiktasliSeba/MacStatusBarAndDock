// Mac Settings, badge part (formerly the NoSettingsBadge tweak):
//
// The red badge on Settings comes from Settings itself (pending items), not from a normal app
// notification, so it cannot be turned off in Notification settings. Lynx can hide badges only
// globally. This hides it for the apps listed below and leaves every other badge alone.
//
// Hook: -[SBApplicationIcon badgeNumberOrString] (the icon model both the dock and the Home Screen
// read their badge from) returns nil for the listed bundle identifiers.

#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <stdio.h>

static NSSet *gHiddenBundleIDs = nil;

static void NLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (!f) return;
    fprintf(f, "%s\n", [line UTF8String]);
    fclose(f);
#endif
}

static id Call(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSString *BundleIDOfIcon(id icon) {
    for (NSString *name in @[@"applicationBundleID", @"leafIdentifier", @"nodeIdentifier"]) {
        id v = Call(icon, name);
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

static id (*orig_badgeNumberOrString)(id, SEL);
static id repl_badgeNumberOrString(id self, SEL _cmd) {
    id value = orig_badgeNumberOrString(self, _cmd);
    if (!value) return value;
    NSString *bid = BundleIDOfIcon(self);
    if (bid && [gHiddenBundleIDs containsObject:bid]) {
        static int logged = 0;
        if (logged++ < 5) NLog([NSString stringWithFormat:@"[hide] badge \"%@\" hidden for %@", value, bid]);
        return nil;
    }
    return value;
}

static BOOL installHook(void) {
    Class cls = objc_getClass("SBApplicationIcon");
    SEL sel = NSSelectorFromString(@"badgeNumberOrString");
    if (!cls || !class_getInstanceMethod(cls, sel)) return NO;
    MSHookMessageEx(cls, sel, (IMP)repl_badgeNumberOrString, (IMP *)&orig_badgeNumberOrString);
    return YES;
}

// ---- view level: hide the badge view itself inside the Settings icon view ----
// Hiding the value was not enough (the icon view still drew a badge), so also hide the badge view. (NoSettingsBadge 0.1.0, value only, on the
// M1's 15.6.1: the Dock still drew Settings' badge; the icon view decides on a badge by more than this value.)
static NSString *IconViewBundleID(UIView *iconView) {
    for (NSString *name in @[@"applicationBundleIdentifier", @"applicationBundleIdentifierForShortcuts"]) {
        id v = Call(iconView, name);
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

// The hide follows the view (1.8.7.7). SpringBoard keeps its badge views for reuse: the one taken off Settings' icon goes on another app's icon
// later. Our hide used to stay with the view, so that app's badge was not drawn (M1: Sileo's stored 7 missing from the Dock after a respring, its
// badge view hidden). Now, in a hidden app's icon view, the view is held hidden (and at alpha 0 for an alpha asked there), and what is ours
// is marked; once it is in another icon view (another app's, a folder's), what SpringBoard (or anyone but us) last asked for is put back. Only
// what we did is undone: a badge view SpringBoard itself hid stays hidden. Taken off (no superview: not drawn) and in between (in views that are
// no icon view, or in an icon view without an icon) nothing is changed, as before, so Settings' badge never shows on the way: also not when it
// comes back onto Settings' icon inside another view, a move that reaches none of our hooks.
typedef NS_ENUM(int, MSBadgePlace) { MSBadgeInHiddenApp, MSBadgeElsewhere, MSBadgeBetween };

// Where is this badge view: inside an icon view for one of the hidden apps, elsewhere, or in between?
static MSBadgePlace BadgePlace(UIView *badge) {
    if (!badge.superview) return MSBadgeBetween;   // (taken off: not drawn; ours stays with it until it is in another icon view)
    Class iconViewClass = objc_getClass("SBIconView");
    for (UIView *v = badge.superview; v; v = v.superview) {
        if (iconViewClass && [v isKindOfClass:iconViewClass]) {
            NSString *bid = IconViewBundleID(v);
            BOOL hide = bid && [gHiddenBundleIDs containsObject:bid];
            static int logged = 0;
            if (hide && logged++ < 3) {
                NSMutableString *chain = [NSMutableString string];
                for (UIView *x = badge; x && x != v.superview; x = x.superview) [chain appendFormat:@"%@ < ", NSStringFromClass([x class])];
                NLog([NSString stringWithFormat:@"[view] hiding badge view in icon view for %@ (chain: %@)", bid, chain]);
            }
            if (hide) return MSBadgeInHiddenApp;
            return Call(v, @"icon") ? MSBadgeElsewhere : MSBadgeBetween;   // (another app's or a folder's icon; none: the icon view is being reused)
        }
    }
    return MSBadgeBetween;
}

static const void *kBadgeOurHidden = &kBadgeOurHidden;     // (@YES: hidden by us; SpringBoard's own is shown, as it was then or asked since)
static const void *kBadgeOurAlpha = &kBadgeOurAlpha;       // (@YES: at alpha 0 by us)
static const void *kBadgeAskedAlpha = &kBadgeAskedAlpha;   // (NSNumber: the alpha SpringBoard last asked for)
static BOOL gBadgeOwnSet = NO;                             // (our own set is passed on as it is, never taken for SpringBoard's)

static void BadgeNote(UIView *badge, const void *key, id value) { objc_setAssociatedObject(badge, key, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void BadgeOwnHidden(UIView *badge, BOOL hidden) { BOOL was = gBadgeOwnSet; gBadgeOwnSet = YES; badge.hidden = hidden; gBadgeOwnSet = was; }
static void BadgeOwnAlpha(UIView *badge, CGFloat alpha) { BOOL was = gBadgeOwnSet; gBadgeOwnSet = YES; badge.alpha = alpha; gBadgeOwnSet = was; }

// Out of a hidden app's icon view: what we did undone, SpringBoard's own hidden and alpha back.
static void BadgeUndo(UIView *badge) {
    BOOL ourHidden = [objc_getAssociatedObject(badge, kBadgeOurHidden) boolValue], ourAlpha = [objc_getAssociatedObject(badge, kBadgeOurAlpha) boolValue];
    if (!ourHidden && !ourAlpha) return;
    NSNumber *alpha = objc_getAssociatedObject(badge, kBadgeAskedAlpha);
    if (ourHidden) { BadgeNote(badge, kBadgeOurHidden, nil); BadgeOwnHidden(badge, NO); }
    if (ourAlpha) { BadgeNote(badge, kBadgeOurAlpha, nil); if (alpha) BadgeOwnAlpha(badge, alpha.doubleValue); }
    static int logged = 0;
    if (logged++ < 5) NLog([NSString stringWithFormat:@"[view] badge view out of a hidden app's icon: undone:%@%@", ourHidden ? @" our hidden" : @"", ourAlpha ? [NSString stringWithFormat:@" our alpha 0 (SpringBoard's %@ back)", alpha] : @""]);
}

// The badge view where it is now: hidden in a hidden app's icon view (it showed: our hidden), our hide undone elsewhere.
static void BadgeFollow(UIView *badge) {
    MSBadgePlace place = BadgePlace(badge);
    if (place == MSBadgeInHiddenApp) {
        if (badge.hidden) return;
        BadgeNote(badge, kBadgeOurHidden, @YES);
        BadgeOwnHidden(badge, YES);
    } else if (place == MSBadgeElsewhere) BadgeUndo(badge);
}

%hook SBIconBadgeView

- (void)didMoveToSuperview {
    %orig;
    BadgeFollow((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    BadgeFollow((UIView *)self);
}

- (void)setHidden:(BOOL)hidden {
    if (gBadgeOwnSet) {   // (ours: passed on as it is)
        %orig;
        return;
    }
    UIView *badge = (UIView *)self;
    MSBadgePlace place = BadgePlace(badge);
    BOOL hide = place == MSBadgeInHiddenApp;
    BadgeNote(badge, kBadgeOurHidden, hide && !hidden ? @YES : nil);   // (asked to show there: our hidden; asked to hide: SpringBoard's own)
    %orig(hide ? YES : hidden);
    if (place == MSBadgeElsewhere) BadgeUndo(badge);   // (an alpha of ours left from a hidden app's icon)
}

- (void)setAlpha:(CGFloat)alpha {
    if (gBadgeOwnSet) {   // (ours: passed on as it is)
        %orig;
        return;
    }
    UIView *badge = (UIView *)self;
    MSBadgePlace place = BadgePlace(badge);
    BOOL hide = place == MSBadgeInHiddenApp;
    BadgeNote(badge, kBadgeAskedAlpha, @(alpha));
    BadgeNote(badge, kBadgeOurAlpha, hide && alpha != 0.0 ? @YES : nil);
    %orig(hide ? 0.0 : alpha);
    if (place == MSBadgeElsewhere) BadgeUndo(badge);   // (a hidden of ours left from a hidden app's icon)
}

%end

// The icon classes may not be loaded the instant tweaks load, so retry for a few seconds.
static void tryInstall(int attempt) {
    if (installHook()) {
        NLog([NSString stringWithFormat:@"[init] hook installed (attempt %d)", attempt + 1]);
    } else if (attempt < 9) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ tryInstall(attempt + 1); });
    } else {
        NLog(@"[init] SBApplicationIcon -badgeNumberOrString not found; badge NOT hidden");
    }
}


%ctor {
    gHiddenBundleIDs = [NSSet setWithObject:@"com.apple.Preferences"];
    tryInstall(0);
}
