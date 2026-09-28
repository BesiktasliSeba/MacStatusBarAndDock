// FolderMenu.x -- long-pressing a Home Screen FOLDER icon adds one row per app inside it to the same Haptic Touch context menu (tapping
// a row opens that app), so the folder's contents are reachable without opening the folder. Replicates Lynx's folder 3D-Touch/Haptic-Touch
// menu feature (currently on, never changed).
//
// Same extensibility point AppSizeMenu.x uses and already confirmed real: SBIconView's PRIVATE
// `-_contextMenuInteraction:overrideSuggestedActionsForConfiguration:`. Calling %orig first and appending to whatever it returns means
// this never has to touch or rebuild the menu's own action list from scratch, and coexists fine with AppSizeMenu.x's own hook of the
// same method (each tweak is a separate dylib; Logos chains %orig across them).
//
// Everything below was confirmed live on-device with the read-only classearch_/methsearch_ tools (never guessed):
//   - SBFolderIcon (superclass SBIcon) exists and is loaded; it has -isFolderIcon and -folder (returns an SBFolder).
//   - SBFolder exists; it has -lists (enumerable; each element is a list with its own -icons, same pattern already proven in
//     MacStatusBar's DMFindJailbreakFolderIcon, which walks a folder exactly this way: `for (list in folder.lists) for (icon in
//     list.icons)`) and -displayName.
//   - SBIcon (the base class, so also present on every icon inside a folder's lists) has -displayName, -leafIdentifier,
//     -applicationBundleID and -isFolderIcon -- the same key list AppSizeMenu.x already uses successfully to read a bundle ID off an
//     SBIconView's -icon.
// No private class is ever alloc/init'd here -- everything below is either read-only introspection/valueForKey on objects the OS itself
// already created (an existing SBIconView's -icon, an existing SBFolderIcon's -folder, existing SBIcon instances from -lists/-icons),
// or messaging LSApplicationWorkspace's `+defaultWorkspace` SINGLETON ACCESSOR (not alloc/init) to open an app, the same public-ish
// mechanism MacStatusBar's DMOpenApp already uses.
#import <UIKit/UIKit.h>
#import <objc/message.h>

#define FM_DOMAIN CFSTR("com.besiktasliseba.macfoldermenu")
// (Settings > Status Bar > App Menus.) Read once and kept; the switch's notification reads it again, so it still applies at once (it synchronized
// with the preferences daemon on every call -- iOS asks for every icon's shortcut items, several times per menu; 2026-09-28).
static int gFMOn = -1;
static void FMPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) { gFMOn = -1; }
static BOOL FMEnabled(void) {
    if (gFMOn >= 0) return gFMOn;
    CFPreferencesAppSynchronize(FM_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), FM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : YES);   // default on, matching Lynx's current setting
    if (v) CFRelease(v);
    gFMOn = on;
    return on;
}

// LSApplicationWorkspace's +defaultWorkspace is a singleton accessor (never alloc/init), the same mechanism MacStatusBar's DMOpenApp
// already uses in production to open apps from SpringBoard-side code.
static void FMOpenApp(NSString *bundleID) {
    if (!bundleID.length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Class wsClass = objc_getClass("LSApplicationWorkspace");
        SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
        if (!wsClass || ![(id)wsClass respondsToSelector:defaultSel]) return;
        id ws = ((id (*)(id, SEL))objc_msgSend)((id)wsClass, defaultSel);
        SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (ws && [ws respondsToSelector:openSel]) {
            ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSel, bundleID);
        }
    });
}

static NSString *FMIdentifierForIcon(id icon) {
    if (!icon) return nil;
    for (NSString *key in @[@"bundleIdentifier", @"applicationBundleID", @"leafIdentifier"]) {
        if ([icon respondsToSelector:NSSelectorFromString(key)]) {
            NSString *v = [icon valueForKey:key];
            if (v.length) return v;
        }
    }
    return nil;
}

static BOOL FMIsFolderIcon(id icon) {
    SEL sel = @selector(isFolderIcon);
    if (!icon || ![icon respondsToSelector:sel]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(icon, sel);
}

// One (bundle id, name) per app inside the folder. Read-only walk of objects the OS already created (an existing SBFolder's -lists,
// each list's -icons) -- nothing here is alloc/init'd.
@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) NSString *bundleIdentifierToLaunch;
@end
static NSString *const kFMType = @"com.besiktasliseba.macfoldermenu.open";
static NSArray<NSArray<NSString *> *> *FMAppsInFolder(id folder) {
    if (!folder) return nil;
    SEL listsSel = NSSelectorFromString(@"lists");
    if (![folder respondsToSelector:listsSel]) return nil;
    id lists = ((id (*)(id, SEL))objc_msgSend)(folder, listsSel);
    if (![lists respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) return nil;

    NSMutableArray<NSArray<NSString *> *> *actions = [NSMutableArray array];
    SEL iconsSel = NSSelectorFromString(@"icons");
    for (id list in (id<NSFastEnumeration>)lists) {
        if (![list respondsToSelector:iconsSel]) continue;
        id childIcons = ((id (*)(id, SEL))objc_msgSend)(list, iconsSel);
        if (![childIcons respondsToSelector:@selector(countByEnumeratingWithState:objects:count:)]) continue;
        for (id childIcon in (id<NSFastEnumeration>)childIcons) {
            if (FMIsFolderIcon(childIcon)) continue;   // nested subfolders: not recursed into, kept out of the row list
            NSString *bundleID = FMIdentifierForIcon(childIcon);
            if (!bundleID.length) continue;
            NSString *title = nil;
            if ([childIcon respondsToSelector:@selector(displayName)]) title = [childIcon valueForKey:@"displayName"];
            if (!title.length) title = bundleID;
            [actions addObject:@[bundleID, title]];
        }
    }
    return actions;
}

// The rows are app shortcut items (-effectiveApplicationShortcutItems: the list iPadOS 15 builds an icon's menu from, folders included -- "Edit
// Home Screen" / "Remove Folder" come from it), not extra "suggested actions": the icon menu never asks
// -_contextMenuInteraction:overrideSuggestedActionsForConfiguration:, so the rows never showed on a real long-press (M1, 2026-09-25).
%hook SBIconView
- (NSArray *)effectiveApplicationShortcutItems {
    NSArray *orig = %orig;
    if (!FMEnabled()) return orig;
    id me = self;
    SEL iconSel = NSSelectorFromString(@"icon");
    id icon = [me respondsToSelector:iconSel] ? ((id (*)(id, SEL))objc_msgSend)(me, iconSel) : nil;
    Class folderIconClass = objc_getClass("SBFolderIcon"), itemClass = objc_getClass("SBSApplicationShortcutItem");
    if (!icon || !folderIconClass || !itemClass || ![icon isKindOfClass:folderIconClass] || !FMIsFolderIcon(icon)) return orig;
    SEL folderSel = NSSelectorFromString(@"folder");
    id folder = [icon respondsToSelector:folderSel] ? ((id (*)(id, SEL))objc_msgSend)(icon, folderSel) : nil;
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *app in FMAppsInFolder(folder)) {
        SBSApplicationShortcutItem *item = [[itemClass alloc] init];
        item.type = kFMType;
        item.localizedTitle = app[1];
        item.bundleIdentifierToLaunch = app[0];
        [items addObject:item];
    }
    if (!items.count) return orig;
    return orig.count ? [orig arrayByAddingObjectsFromArray:items] : items;
}
+ (void)activateShortcut:(SBSApplicationShortcutItem *)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView {
    if ([item respondsToSelector:@selector(type)] && [item.type isEqualToString:kFMType]) { FMOpenApp(item.bundleIdentifierToLaunch); return; }
    %orig;
}
%end

%ctor {
    %init;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, FMPrefsChanged, CFSTR("com.besiktasliseba.macfoldermenu/prefsChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
