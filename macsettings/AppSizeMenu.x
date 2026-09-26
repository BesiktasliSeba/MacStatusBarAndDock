// AppSizeMenu.x -- adds a disabled, informational "App Size: X" row to a Home Screen icon's Haptic Touch menu. Replicates Lynx's
// "showAppSize" (currently on, never changed).
//
// The row is one of the icon's shortcut items (see the hook below for why).
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <unistd.h>
#import <objc/runtime.h>

#define ASM_DOMAIN CFSTR("com.besiktasliseba.macappsizemenu")
static BOOL ASMEnabled(void) {   // (Settings > Status Bar > App Menus; read when a menu opens, so the switch applies at once)
    CFPreferencesAppSynchronize(ASM_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), ASM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return YES;   // default on, matching Lynx's current setting
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : YES;
    CFRelease(v);
    return on;
}

static NSString *ASMSizeText(NSString *bundleID) {
    if (!bundleID.length) return nil;
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL make = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![(id)proxyClass respondsToSelector:make]) return nil;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)((id)proxyClass, make, bundleID);
    if (!proxy) return nil;
    long long total = 0;
    if ([proxy respondsToSelector:@selector(staticDiskUsage)]) total += [[proxy valueForKey:@"staticDiskUsage"] longLongValue];
    if ([proxy respondsToSelector:@selector(dynamicDiskUsage)]) total += [[proxy valueForKey:@"dynamicDiskUsage"] longLongValue];
    if (total <= 0) return nil;
    return [NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile];
}

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
static NSString * const kASMShortcutType = @"com.besiktasliseba.appsizemenu.size";
static NSString * const kASMTitlePrefix = @"App Size: ";

// The row is one of the icon's shortcut items, first in the menu (2026-09-25). It used to be appended through
// -_contextMenuInteraction:overrideSuggestedActionsForConfiguration:, which runs and returns the row, but whose result the Home Screen menu
// does not show (iPad 2, iPadOS 16: never seen; the owner never saw it on the iOS 15 M1 either). Shortcut items are what the menu is built
// from (Force Quit in App Menus is one too). Tapping it does nothing; it is drawn greyed out (UIAction below).
%hook SBIconView
- (NSArray *)applicationShortcutItems {
    NSArray *orig = %orig;
    if (!ASMEnabled()) return orig;
    NSString *bundleID = nil;
    for (NSString *key in @[@"applicationBundleIdentifier", @"applicationBundleIdentifierForShortcuts"]) {
        SEL sel = NSSelectorFromString(key);
        id me = self;
        if ([me respondsToSelector:sel]) { bundleID = ((id (*)(id, SEL))objc_msgSend)(me, sel); if (bundleID.length) break; }
    }
    NSString *sizeText = ASMSizeText(bundleID);
#if DEBUG
    { FILE *f = access("/tmp/macsettings-debug", F_OK) == 0 ? fopen("/tmp/macsettings.log", "a") : NULL;
      if (f) { fprintf(f, "[appsize] menu for %s: %s\n", bundleID.UTF8String ?: "?", sizeText.UTF8String ?: "(no size)"); fclose(f); } }
#endif
    Class itemClass = objc_getClass("SBSApplicationShortcutItem"), iconClass = objc_getClass("SBSApplicationShortcutCustomImageIcon");
    if (!sizeText || !itemClass) return orig;
    SBSApplicationShortcutItem *item = [[itemClass alloc] init];
    item.type = kASMShortcutType;
    item.localizedTitle = [kASMTitlePrefix stringByAppendingString:sizeText];
    item.bundleIdentifierToLaunch = bundleID;
    NSData *png = UIImagePNGRepresentation([UIImage systemImageNamed:@"internaldrive"]);
    if (png && iconClass) item.icon = [[iconClass alloc] initWithImageData:png dataType:0 isTemplate:1];
    return [orig isKindOfClass:[NSArray class]] ? [@[item] arrayByAddingObjectsFromArray:orig] : @[item];
}
+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView {
    if ([item respondsToSelector:@selector(type)] && [item.type isEqualToString:kASMShortcutType]) return;   // (informational only)
    %orig;
}
%end
%hook UIAction
- (UIMenuElementAttributes)attributes {
    UIMenuElementAttributes attrs = %orig;
    if ([self.title hasPrefix:kASMTitlePrefix]) attrs |= UIMenuElementAttributesDisabled;
    return attrs;
}
%end

%ctor {
    %init;
}
