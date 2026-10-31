// AddToFolder.x -- "Add to Folder" in an app icon's Haptic Touch menu (1.7.2 item 3, KT 30 Oct): a submenu with the Home Screen's folders and
// New Folder; the app moves into the folder picked. Our own code (KT used a third-party tweak for this and will use ours instead).
//  - Where: an app's icon on the Home Screen, in a folder (to another folder) and in the App Library (its category tiles, the expanded categories,
//    its search: the app goes into a Home Screen folder, and leaves its Home Screen place if it had one). Never on the Dock's own icons, a folder's
//    icon (iPadOS has no folders in folders), a widget or anything that is not an app.
//  - The folders: every folder on the Home Screen's pages, page by page in reading order, then the Dock's; the one the app is in already is left
//    out; a full one is shown greyed out ("Full"); two with one name are told apart by their page. Hidden pages are left out (they are not shown).
//  - New Folder: a folder with iPadOS's own name for it (the name it gives a folder made by dropping the app on another, from the app's App Store
//    category), where the app was on its page; an app from a folder or the App Library gets it in the place iPadOS gives a new app.
//  - The move is SpringBoard's own once the menu has closed (-[SBHIconManager performAfterIconContextMenuDismissesUsingBlock:], then the drop of
//    icons on a folder, -addIcons:intoFolderIcon:openFolderOnFinish:completion:), and the Home Screen's layout is saved as after any change.
//  - The submenu sits right before Force Quit (Settings > Status Bar > App Menus), or at the end of the app's own items without it.
// Settings > Status Bar > App Menus > Add to Folder in App Menus (com.besiktasliseba.macaddtofolder enabled, on by default). While the tweak
// AddToFolder (com.anthopak.addtofolder, its rootless package too) is installed, ours stays out: one Add to Folder, not two.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <sys/stat.h>
#include "../common/DpkgState.h"   // (MSBDPackageOnDisk: the other AddToFolder tweak installed)

#define ATF_DOMAIN CFSTR("com.besiktasliseba.macaddtofolder")
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

static void ATFLog(NSString *line) {
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (!f) return;
    fprintf(f, "[addtofolder] %s\n", line.UTF8String ?: "");
    fclose(f);
#endif
}
static id ATFCall(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static BOOL ATFBool(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return [o respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(o, s); }
static NSString *ATFBareTypes(const char *enc) {
    if (!enc) return @"";
    NSMutableString *s = [NSMutableString string];
    for (const char *p = enc; *p; p++) if (!isdigit((unsigned char)*p)) [s appendFormat:@"%c", *p];
    return s;
}
static BOOL ATFHasMethod(id o, NSString *sel, NSString *types) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), NSSelectorFromString(sel)) : NULL;
    return m && [ATFBareTypes(method_getTypeEncoding(m)) isEqualToString:types];
}

// ---- on or off: the switch (read once, again when it changes), and the other tweak ----
static int gATFOn = -1;
static void ATFPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) { gATFOn = -1; }
static BOOL ATFSwitchOn(void) {
    if (gATFOn >= 0) return gATFOn;
    CFPreferencesAppSynchronize(ATF_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), ATF_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : YES);   // (on unless switched off)
    if (v) CFRelease(v);
    gATFOn = on;
    return on;
}
// The AddToFolder tweak installed (dpkg's own record, read again only when the file changes; common/DpkgState.h, Mac-tested): ours steps aside --
// the same item twice otherwise.
static BOOL ATFOtherTweakInstalled(void) {
    static struct timespec seen; static BOOL other = NO, read = NO;
    const char *path = "/var/jb/var/lib/dpkg/status";
    struct stat st;
    if (stat(path, &st) != 0) return NO;
    if (read && st.st_mtimespec.tv_sec == seen.tv_sec && st.st_mtimespec.tv_nsec == seen.tv_nsec) return other;
    read = YES; seen = st.st_mtimespec; other = NO;
    NSString *status = [NSString stringWithContentsOfFile:@(path) encoding:NSUTF8StringEncoding error:nil];
    for (NSString *pkg in @[@"com.anthopak.addtofolder-rootless", @"com.anthopak.addtofolder", @"com.anthopak.addtofolder-roothide"])
        if (MSBDPackageOnDisk(status, pkg)) { other = YES; break; }
    ATFLog([NSString stringWithFormat:@"the AddToFolder tweak is %@installed: ours %@", other ? @"" : @"not ", other ? @"stays out" : @"is offered"]);
    return other;
}

// ---- the Home Screen's model ----
static id ATFManager(void) { return ATFCall(ATFCall((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"); }
static id ATFModel(void) { return ATFCall(ATFManager(), @"iconModel"); }
static id ATFRoot(void) { return ATFCall(ATFModel(), @"rootFolder"); }
static NSArray *ATFArray(id o) { return [o isKindOfClass:[NSArray class]] ? o : ([o respondsToSelector:@selector(allObjects)] ? [o allObjects] : @[]); }
static BOOL ATFIsFolderIcon(id icon) { return icon && ATFBool(icon, @"isFolderIcon"); }
static BOOL ATFListHidden(id list) { return ATFBool(list, @"isHidden"); }
// The app icon an icon view is for, when "Add to Folder" belongs in its menu: an app's icon (not a folder, widget or anything else), not the Dock's
// own icons (the Dock's list, its recent apps, the App Library button), and the app in the Home Screen's model (the icon a folder can take).
static id ATFAppIconFor(UIView *iconView) {
    id icon = ATFCall(iconView, @"icon");
    NSString *bundle = ATFCall(icon, @"applicationBundleID");
    NSString *location = ATFCall(iconView, @"location");
    if (![bundle isKindOfClass:[NSString class]] || !bundle.length || ATFIsFolderIcon(icon) || ATFBool(icon, @"isWidgetIcon") || ATFBool(icon, @"isWidgetStackIcon")) return nil;
    if (![location isKindOfClass:[NSString class]]) return nil;
    BOOL library = [location containsString:@"AppLibrary"];   // (the App Library: full screen, or opened from its Dock button)
    if ([location containsString:@"Dock"] && !library) return nil;   // (never on the Dock's icons, KT: its own, its recent apps, a folder kept in it)
    if (!([location isEqualToString:@"SBIconLocationRoot"] || [location containsString:@"Folder"] || library)) return nil;
    id model = ATFModel();
    SEL leaf = NSSelectorFromString(@"leafIconForIdentifier:");
    id modelIcon = [model respondsToSelector:leaf] ? ((id (*)(id, SEL, id))objc_msgSend)(model, leaf, ATFCall(icon, @"leafIdentifier") ?: bundle) : nil;
    // (an app kept in the Dock, long-pressed in the App Library: no item either -- moving it into a folder would take it out of the Dock)
    SEL has = NSSelectorFromString(@"directlyContainsIcon:");
    id dock = ATFCall(ATFRoot(), @"dock");
    if (modelIcon && [dock respondsToSelector:has] && ((BOOL (*)(id, SEL, id))objc_msgSend)(dock, has, modelIcon)) return nil;
    return modelIcon;
}
// The folder icon the app is in now (nil: on a page, in the Dock, or only in the App Library).
static id ATFFolderHolding(id appIcon) {
    id root = ATFRoot();
    for (id list in [ATFArray(ATFCall(root, @"lists")) arrayByAddingObjectsFromArray:(ATFCall(root, @"dock") ? @[ATFCall(root, @"dock")] : @[])])
        for (id icon in ATFArray(ATFCall(list, @"icons")))
            if (ATFIsFolderIcon(icon)) {
                SEL has = NSSelectorFromString(@"containsIcon:");
                id folder = ATFCall(icon, @"folder");
                if ([folder respondsToSelector:has] && ((BOOL (*)(id, SEL, id))objc_msgSend)(folder, has, appIcon)) return icon;
            }
    return nil;
}
// Every folder icon of the Home Screen: its pages in order (hidden ones left out), then the Dock's. @[folder icon, page number (0 = the Dock)].
static NSArray<NSArray *> *ATFFolders(void) {
    id root = ATFRoot();
    NSMutableArray *out = [NSMutableArray array];
    NSInteger page = 0;
    for (id list in ATFArray(ATFCall(root, @"lists"))) {
        if (ATFListHidden(list)) continue;
        page++;
        for (id icon in ATFArray(ATFCall(list, @"icons"))) if (ATFIsFolderIcon(icon)) [out addObject:@[icon, @(page)]];
    }
    for (id icon in ATFArray(ATFCall(ATFCall(root, @"dock"), @"icons"))) if (ATFIsFolderIcon(icon)) [out addObject:@[icon, @0]];
    return out;
}

// ---- the move ----
static void ATFSaveLayout(id model) {   // (as after any change of the Home Screen: SpringBoard's own save)
    if ([model respondsToSelector:NSSelectorFromString(@"markIconStateDirty")]) ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"markIconStateDirty"));
    if ([model respondsToSelector:NSSelectorFromString(@"saveIconStateIfNeeded")]) ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
}
// Run once the Haptic Touch menu has closed (its preview animates the icon back into its place: moving it before that would pull the place away).
// (once, whichever comes first: SpringBoard's own call when the menu is gone, or 1.5 s -- a menu already gone may never call back)
static void ATFAfterMenu(void (^block)(void)) {
    __block BOOL ran = NO;
    void (^once)(void) = ^{ if (ran) return; ran = YES; block(); };
    id mgr = ATFManager();
    if (ATFHasMethod(mgr, @"performAfterIconContextMenuDismissesUsingBlock:", @"v@:@?"))
        ((void (*)(id, SEL, id))objc_msgSend)(mgr, NSSelectorFromString(@"performAfterIconContextMenuDismissesUsingBlock:"), ^{ dispatch_async(dispatch_get_main_queue(), once); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), once);
}
// Out of the folder it is in (SpringBoard's drop on a folder takes an icon off the Home Screen's pages and lists, not out of another folder: 16.7.7
// left Tips in both folders). A folder left empty goes, as when its last app is dragged out.
static void ATFTakeOutOfFolder(id appIcon) {
    id holder = ATFFolderHolding(appIcon);
    if (!holder) return;
    id folder = ATFCall(holder, @"folder");
    SEL has = NSSelectorFromString(@"directlyContainsIcon:"), rm = NSSelectorFromString(@"removeIcon:");
    for (id list in ATFArray(ATFCall(folder, @"lists")))
        if ([list respondsToSelector:has] && [list respondsToSelector:rm] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, appIcon)) ((void (*)(id, SEL, id))objc_msgSend)(list, rm, appIcon);
    if (!ATFBool(folder, @"isEmpty")) return;
    id root = ATFRoot();
    for (id list in [ATFArray(ATFCall(root, @"lists")) arrayByAddingObjectsFromArray:(ATFCall(root, @"dock") ? @[ATFCall(root, @"dock")] : @[])])
        if ([list respondsToSelector:has] && [list respondsToSelector:rm] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, holder)) { ((void (*)(id, SEL, id))objc_msgSend)(list, rm, holder); ATFLog(@"the folder it left is empty: it goes"); break; }
}
// The folder open on screen closes first when the app leaves it (as when its app is dragged out of it): a folder left empty goes, and must not be
// the one shown.
static void ATFCloseOpenFolderHolding(id appIcon) {
    id mgr = ATFManager(), holder = ATFFolderHolding(appIcon);
    if (!holder || !ATFBool(mgr, @"hasOpenFolder")) return;
    if (ATFCall(mgr, @"openedFolder") != ATFCall(holder, @"folder")) return;
    if (ATFHasMethod(mgr, @"closeFolderAnimated:withCompletion:", @"v@:B@?")) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(mgr, NSSelectorFromString(@"closeFolderAnimated:withCompletion:"), NO, nil);
        ATFLog(@"the folder it is in was open: closed first");
    }
}
// Is the folder still on the Home Screen (a page or the Dock)? It may have gone while the menu was open (its last app dragged out): the app is
// never put into a folder nobody can see.
static BOOL ATFFolderIconPlaced(id folderIcon) {
    id root = ATFRoot();
    SEL has = NSSelectorFromString(@"directlyContainsIcon:");
    for (id list in [ATFArray(ATFCall(root, @"lists")) arrayByAddingObjectsFromArray:(ATFCall(root, @"dock") ? @[ATFCall(root, @"dock")] : @[])])
        if ([list respondsToSelector:has] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, folderIcon)) return YES;
    return NO;
}
static BOOL ATFMoveInto(id appIcon, id folderIcon) {
    id mgr = ATFManager(), model = ATFModel();
    if (!ATFFolderIconPlaced(folderIcon)) { ATFLog(@"the folder is no longer on the Home Screen: nothing moved"); return NO; }
    id folder = ATFCall(folderIcon, @"folder");
    SEL can = NSSelectorFromString(@"canAddIcon:");
    if (!folder || ([folder respondsToSelector:can] && !((BOOL (*)(id, SEL, id))objc_msgSend)(folder, can, appIcon))) { ATFLog(@"the folder is full: nothing moved"); return NO; }
    ATFCloseOpenFolderHolding(appIcon);
    ATFTakeOutOfFolder(appIcon);
    if (ATFHasMethod(mgr, @"addIcons:intoFolderIcon:openFolderOnFinish:completion:", @"v@:@@B@?")) {   // (the drop of icons on a folder: SpringBoard takes them out of their places)
        ((void (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(mgr, NSSelectorFromString(@"addIcons:intoFolderIcon:openFolderOnFinish:completion:"), @[appIcon], folderIcon, NO, nil);
    } else {   // (iPadOS without it: out of its list on the Home Screen, into the folder)
        SEL has = NSSelectorFromString(@"directlyContainsIcon:"), rm = NSSelectorFromString(@"removeIcon:"), add = NSSelectorFromString(@"addIcon:");
        if (![folder respondsToSelector:add]) return NO;
        id root = ATFRoot();
        NSMutableArray *lists = [ATFArray(ATFCall(root, @"lists")) mutableCopy];
        for (NSString *k in @[@"dock", @"ignoredList"]) { id l = ATFCall(root, k); if (l) [lists addObject:l]; }
        for (id list in lists)
            if ([list respondsToSelector:has] && [list respondsToSelector:rm] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, appIcon)) ((void (*)(id, SEL, id))objc_msgSend)(list, rm, appIcon);
        ((id (*)(id, SEL, id))objc_msgSend)(folder, add, appIcon);
    }
    ATFSaveLayout(model);
    DM_FEATURE_MARK("add-to-folder");
    ATFLog([NSString stringWithFormat:@"%@ moved into the folder %@", ATFCall(appIcon, @"applicationBundleID"), ATFCall(folder, @"displayName")]);
    return YES;
}
// New Folder: iPadOS's own name for a folder made with this app, the folder where the app is on its page (else where iPadOS puts a new app), the app in it.
static BOOL ATFNewFolderWith(id appIcon) {
    id mgr = ATFManager(), model = ATFModel(), root = ATFRoot();
    NSString *name = nil;
    if (ATFHasMethod(mgr, @"_proposedFolderNameForGrabbedIcon:recipientIcon:", @"@@:@@")) name = ((id (*)(id, SEL, id, id))objc_msgSend)(mgr, NSSelectorFromString(@"_proposedFolderNameForGrabbedIcon:recipientIcon:"), appIcon, appIcon);
    if (![name isKindOfClass:[NSString class]] || !name.length) name = ATFCall(model, @"localizedDefaultFolderName");
    if (![name isKindOfClass:[NSString class]] || !name.length) name = @"Folder";
    if (!ATFHasMethod(model, @"makeFolderWithDisplayName:", @"@@:@")) { ATFLog(@"no -makeFolderWithDisplayName: here: no new folder"); return NO; }
    // (the model makes the folder -- SBFolder, with the model's own sizes and page count -- and the Home Screen shows a folder through its icon:
    //  SBFolderIcon -initWithFolder:, unless the folder has one already)
    id made = ((id (*)(id, SEL, id))objc_msgSend)(model, NSSelectorFromString(@"makeFolderWithDisplayName:"), name);
    id folder = nil, folderIcon = nil;
    if (ATFIsFolderIcon(made)) { folderIcon = made; folder = ATFCall(made, @"folder"); }
    else if (made) {
        folder = made; folderIcon = ATFCall(made, @"icon");
        Class fic = objc_getClass("SBFolderIcon");
        SEL initSel = NSSelectorFromString(@"initWithFolder:");
        if (!ATFIsFolderIcon(folderIcon) && fic && [fic instancesRespondToSelector:initSel]) folderIcon = ((id (*)(id, SEL, id))objc_msgSend)([fic alloc], initSel, folder);
    }
    if (!folder || !ATFIsFolderIcon(folderIcon)) { ATFLog([NSString stringWithFormat:@"the new folder was not made (%@)", made ? NSStringFromClass([made class]) : @"nothing"]); return NO; }
    if (![folder respondsToSelector:NSSelectorFromString(@"addIcon:")]) { ATFLog(@"the new folder takes no icon here: no new folder"); return NO; }
    BOOL placed = NO;
    SEL replace = NSSelectorFromString(@"replaceIcon:withIcon:"), has = NSSelectorFromString(@"directlyContainsIcon:");
    for (id list in ATFArray(ATFCall(root, @"lists"))) {   // (on a page: the folder takes the app's place, as when the app is dropped on another)
        if (![list respondsToSelector:has] || !((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, appIcon)) continue;
        if (ATFHasMethod(root, @"replaceIcon:withIcon:", @"B@:@@")) placed = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(root, replace, appIcon, folderIcon);
        if (placed) { ((id (*)(id, SEL, id))objc_msgSend)(folder, NSSelectorFromString(@"addIcon:"), appIcon); }
        break;
    }
    if (!placed) {   // (in a folder, or only in the App Library: the place iPadOS gives a new app, then the app moves in)
        ATFCloseOpenFolderHolding(appIcon);
        SEL opts = NSSelectorFromString(@"gridCellInfoOptions");
        unsigned long long o = [mgr respondsToSelector:opts] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(mgr, opts) : 0;
        if (ATFHasMethod(model, @"addIconToDesignatedLocation:options:listGridCellInfoOptions:", @"B@:@QQ"))
            placed = ((BOOL (*)(id, SEL, id, unsigned long long, unsigned long long))objc_msgSend)(model, NSSelectorFromString(@"addIconToDesignatedLocation:options:listGridCellInfoOptions:"), folderIcon, 0, o);
        if (!placed) { ATFLog(@"no place for a new folder on the Home Screen"); return NO; }
        if (!ATFMoveInto(appIcon, folderIcon)) {   // (no empty folder left behind wherever iPadOS put it)
            SEL has = NSSelectorFromString(@"directlyContainsIcon:"), rm = NSSelectorFromString(@"removeIcon:");
            NSMutableArray *lists = [ATFArray(ATFCall(root, @"lists")) mutableCopy];
            for (NSString *k in @[@"dock", @"ignoredList"]) { id l = ATFCall(root, k); if (l) [lists addObject:l]; }
            for (id list in lists)
                if ([list respondsToSelector:has] && [list respondsToSelector:rm] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, folderIcon)) ((void (*)(id, SEL, id))objc_msgSend)(list, rm, folderIcon);
            return NO;
        }
    }
    ATFSaveLayout(model);
    DM_FEATURE_MARK("add-to-folder-new");
    ATFLog([NSString stringWithFormat:@"%@ is in a new folder %@", ATFCall(appIcon, @"applicationBundleID"), name]);
    return YES;
}

// ---- the submenu ----
static UIMenu *ATFSubmenu(id appIcon) {
    id holder = ATFFolderHolding(appIcon);
    NSArray<NSArray *> *folders = ATFFolders();
    NSCountedSet *names = [NSCountedSet set];
    for (NSArray *f in folders) { NSString *n = ATFCall(ATFCall(f[0], @"folder"), @"displayName"); if (n) [names addObject:n]; }
    NSMutableArray *rows = [NSMutableArray array];
    SEL can = NSSelectorFromString(@"canAddIcon:");
    for (NSArray *f in folders) {
        id folderIcon = f[0], folder = ATFCall(folderIcon, @"folder");
        if (folderIcon == holder) continue;   // (the one it is in already)
        NSString *name = ATFCall(folder, @"displayName");
        if (![name isKindOfClass:[NSString class]] || !name.length) name = @"Folder";
        NSString *title = [names countForObject:name] > 1 ? [NSString stringWithFormat:@"%@ (%@)", name, [f[1] integerValue] ? [NSString stringWithFormat:@"Page %@", f[1]] : @"Dock"] : name;
        BOOL full = [folder respondsToSelector:can] && !((BOOL (*)(id, SEL, id))objc_msgSend)(folder, can, appIcon);
        __weak id wf = folderIcon, wa = appIcon;
        UIAction *a = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *x) {
            id fi = wf, ai = wa;
            if (fi && ai) ATFAfterMenu(^{ ATFMoveInto(ai, fi); });
        }];
        if (full) { a.attributes = UIMenuElementAttributesDisabled; if (@available(iOS 15.0, *)) a.subtitle = @"Full"; }
        [rows addObject:a];
    }
    __weak id wa = appIcon;
    UIAction *newFolder = [UIAction actionWithTitle:@"New Folder" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:nil handler:^(UIAction *x) {
        id ai = wa;
        if (ai) ATFAfterMenu(^{ ATFNewFolderWith(ai); });
    }];
    NSMutableArray *children = [NSMutableArray array];
    if (rows.count) [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:rows]];
    [children addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[newFolder]]];
    return [UIMenu menuWithTitle:@"Add to Folder" image:[UIImage systemImageNamed:@"folder.badge.plus"] identifier:@"com.besiktasliseba.addtofolder" options:0 children:children];
}
// Our submenu into the menu: right before Force Quit (ours, ForceQuitMenu.x), or after the app's own items -- the first section that has them.
static BOOL ATFIsForceQuit(UIMenuElement *e) { return [e isKindOfClass:[UIAction class]] && [((UIAction *)e).title isEqualToString:@"Force Quit"]; }
static UIMenu *ATFInsert(UIMenu *menu, UIMenu *ours, BOOL *done) {
    NSMutableArray *kids = [menu.children mutableCopy];
    for (NSUInteger i = 0; i < kids.count; i++) {
        if (*done) break;
        if (ATFIsForceQuit(kids[i])) { [kids insertObject:ours atIndex:i]; *done = YES; break; }
        if ([kids[i] isKindOfClass:[UIMenu class]]) {
            UIMenu *inner = ATFInsert(kids[i], ours, done);
            if (*done) { kids[i] = inner; break; }
        }
    }
    return *done ? [menu menuByReplacingChildren:kids] : menu;
}
static UIMenu *ATFWithSubmenu(UIMenu *menu, id appIcon) {
    if (![menu isKindOfClass:[UIMenu class]] || !appIcon) return menu;
    for (UIMenuElement *e in menu.children) if ([e isKindOfClass:[UIMenu class]] && [((UIMenu *)e).identifier isEqualToString:@"com.besiktasliseba.addtofolder"]) return menu;   // (once)
    UIMenu *ours = ATFSubmenu(appIcon);
    BOOL done = NO;
    UIMenu *m = ATFInsert(menu, ours, &done);
    if (done) return m;
    // (no Force Quit row: at the end of the first section, the app's own items)
    NSMutableArray *kids = [menu.children mutableCopy];
    NSUInteger at = kids.count;
    for (NSUInteger i = 0; i < kids.count; i++) if ([kids[i] isKindOfClass:[UIMenu class]] && (((UIMenu *)kids[i]).options & UIMenuOptionsDisplayInline)) { at = i; break; }
    if (at < kids.count) {
        UIMenu *first = kids[at];
        kids[at] = [first menuByReplacingChildren:[first.children arrayByAddingObject:ours]];
    } else [kids addObject:ours];
    return [menu menuByReplacingChildren:kids];
}

static const void *kATFWrappedKey = &kATFWrappedKey;
%hook SBIconView
- (id)contextMenuInteraction:(id)interaction configurationForMenuAtLocation:(CGPoint)location {
    id cfg = %orig;
    if (!cfg || objc_getAssociatedObject(cfg, kATFWrappedKey) || !ATFSwitchOn() || ATFOtherTweakInstalled()) return cfg;
    id appIcon = ATFAppIconFor((UIView *)self);
    if (!appIcon) return cfg;
    UIContextMenuActionProvider provider = nil; @try { provider = [cfg valueForKey:@"actionProvider"]; } @catch (id e) {}
    if (!provider) return cfg;
    __weak id wa = appIcon;
    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *m = provider(suggested);
        id ai = wa;
        @try { return ai ? ATFWithSubmenu(m, ai) : m; } @catch (id e) { return m; }
    };
    @try { [cfg setValue:wrapped forKey:@"actionProvider"]; objc_setAssociatedObject(cfg, kATFWrappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } @catch (id e) {}
    return cfg;
}
%end

%ctor {
    %init;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ATFPrefsChanged, CFSTR("com.besiktasliseba.macaddtofolder/prefsChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
