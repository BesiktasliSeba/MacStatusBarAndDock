// ForceQuitMenu (SpringBoard) -- a red "Force Quit" row in every app icon's Haptic Touch menu. On by default; the switch is Settings > Status Bar >
// App Menus.
#import <UIKit/UIKit.h>
#include <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>

extern void BKSTerminateApplicationForReasonAndReportWithDescription(NSString *bundleID, int reasonID, bool report, NSString *description);

@interface SBSApplicationShortcutIcon : NSObject
@end

@interface SBSApplicationShortcutCustomImageIcon : SBSApplicationShortcutIcon
- (id)initWithImageData:(id)imageData dataType:(long long)dataType isTemplate:(bool)isTemplate;
@end

@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) SBSApplicationShortcutIcon *icon;
@property (nonatomic, copy) NSString *bundleIdentifierToLaunch;
@end

@interface SBMainSwitcherViewController : UIViewController
+ (instancetype)sharedInstance;
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)bundleID;
@end

@interface SBIconView : UIView
- (NSString *)applicationBundleIdentifier;
- (NSString *)applicationBundleIdentifierForShortcuts;
@end

static NSString * const kForceQuitShortcutType = @"com.besiktasliseba.forcequitmenu.forcequit";
static NSString * const kForceQuitTitle = @"Force Quit";

#define kPrefsChanged "com.besiktasliseba.forcequitmenu/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain  CFSTR("com.besiktasliseba.forcequitmenu")
static BOOL gEnabled = YES;
static void ReadSwitch(void) {
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = YES;   // on until switched off
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v); CFRelease(v); }
    gEnabled = enabled;
}

// Killing the process leaves SpringBoard's "recent apps" entry behind, which is
// why the card stays in the app switcher. Swiping a card away does a second
// step we would otherwise skip: deleting that entry. Do the same here. The
// second call catches SpringBoard re-adding the card as the process dies; it
// does nothing if the card is already gone.
static void removeFromAppSwitcher(NSString *bundleID) {
    void (^remove)(void) = ^{
        // iOS 15: SBMainSwitcherViewController. iOS 16 has no such class; its SBMainSwitcherControllerCoordinator has the same delete call.
        id switcher = [%c(SBMainSwitcherViewController) sharedInstance];
        if (!switcher) {
            Class co = objc_getClass("SBMainSwitcherControllerCoordinator");
            SEL ifExists = NSSelectorFromString(@"sharedInstanceIfExists");
            if (co && [(id)co respondsToSelector:ifExists]) switcher = ((id (*)(id, SEL))objc_msgSend)(co, ifExists);
            else if (co && [(id)co respondsToSelector:@selector(sharedInstance)]) switcher = ((id (*)(id, SEL))objc_msgSend)(co, @selector(sharedInstance));
        }
        if ([switcher respondsToSelector:@selector(_deleteAppLayoutsMatchingBundleIdentifier:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(switcher, @selector(_deleteAppLayoutsMatchingBundleIdentifier:), bundleID);
        }
    };
    dispatch_async(dispatch_get_main_queue(), remove);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), remove);
}

%hook SBIconView

- (NSArray *)applicationShortcutItems {
    NSArray *orig = %orig;
    if (!gEnabled) return orig;

    NSString *applicationID = nil;
    if ([self respondsToSelector:@selector(applicationBundleIdentifier)]) {
        applicationID = [self applicationBundleIdentifier];
    } else if ([self respondsToSelector:@selector(applicationBundleIdentifierForShortcuts)]) {
        applicationID = [self applicationBundleIdentifierForShortcuts];
    }

    if (!applicationID) {
        return orig;
    }
    SBSApplicationShortcutItem *forceQuitItem = [[%c(SBSApplicationShortcutItem) alloc] init];
    forceQuitItem.type = kForceQuitShortcutType;
    forceQuitItem.localizedTitle = kForceQuitTitle;
    forceQuitItem.bundleIdentifierToLaunch = applicationID;
#if DEBUG
    if (access("/tmp/msb-ctx-subtitle-test", F_OK) == 0) { @try { [forceQuitItem setValue:@"Subtitle test" forKey:@"localizedSubtitle"]; } @catch (id e) {} }   // (debug: a two-line row, for the menu theme)
#endif

    // Bake red into the glyph ourselves, and mark it non-template so
    // iOS doesn't override our color with its own default tint.
    // (made once per light/dark look and kept: it was encoded for every menu -- part of the Dock menu's slow first open, 2026-09-28)
    static NSData *pngs[3];
    UIUserInterfaceStyle style = [UITraitCollection currentTraitCollection].userInterfaceStyle;
    NSUInteger slot = style == UIUserInterfaceStyleDark ? 2 : style == UIUserInterfaceStyleLight ? 1 : 0;
    if (!pngs[slot]) {
        UIImage *symbolImage = [UIImage systemImageNamed:@"xmark.circle"];
        UIImage *redSymbolImage = [symbolImage imageWithTintColor:[UIColor systemRedColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        pngs[slot] = UIImagePNGRepresentation(redSymbolImage);
    }
    NSData *imageData = pngs[slot];
    forceQuitItem.icon = [[%c(SBSApplicationShortcutCustomImageIcon) alloc] initWithImageData:imageData dataType:0 isTemplate:0];

    if (!orig) {
        return @[forceQuitItem];
    }
    return [orig arrayByAddingObject:forceQuitItem];
}

+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView {
    if ([item.type isEqualToString:kForceQuitShortcutType]) {
        BKSTerminateApplicationForReasonAndReportWithDescription(bundleID, 5, false, @"ForceQuitMenu - force touch, killed");
        removeFromAppSwitcher(bundleID);
        return;
    }

    %orig;
}

%end

// On iOS 15 the icon menu is a regular UIKit context menu, and UIKit draws
// an action's title and icon red when the UIAction is marked destructive
// (this is how the built-in "Remove App" looks). Our shortcut item ends up as
// a UIAction by the time the menu is built, so report it as destructive.
%hook UIAction

- (UIMenuElementAttributes)attributes {
	UIMenuElementAttributes attrs = %orig;
	if ([self.title isEqualToString:kForceQuitTitle]) {
		attrs |= UIMenuElementAttributesDestructive;
	}
	return attrs;
}

%end

%ctor {
    %init;
    ReadSwitch();
    static int token = 0;
    notify_register_dispatch(kPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) { ReadSwitch(); });
}
