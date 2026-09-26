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
// Hiding the value was not enough (the icon view still drew a badge), so also hide the badge view.
static NSString *IconViewBundleID(UIView *iconView) {
    for (NSString *name in @[@"applicationBundleIdentifier", @"applicationBundleIdentifierForShortcuts"]) {
        id v = Call(iconView, name);
        if ([v isKindOfClass:[NSString class]] && [v length]) return v;
    }
    return nil;
}

// Is this badge view inside an icon view for one of the hidden apps?
static BOOL IsHiddenBadge(UIView *badge) {
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
            return hide;
        }
    }
    return NO;
}

%hook SBIconBadgeView

- (void)didMoveToSuperview {
    %orig;
    if (IsHiddenBadge((UIView *)self)) ((UIView *)self).hidden = YES;
}

- (void)layoutSubviews {
    %orig;
    if (IsHiddenBadge((UIView *)self) && !((UIView *)self).hidden) ((UIView *)self).hidden = YES;
}

- (void)setHidden:(BOOL)hidden {
    %orig(IsHiddenBadge((UIView *)self) ? YES : hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(IsHiddenBadge((UIView *)self) ? 0.0 : alpha);
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
