// FinderFolders.h -- Home Screen folders in the menu bar's Finder menu (1.7.9 item 3, KT 2 Nov 2026), included into StatusBar.x:
//  - a folder's Haptic Touch menu -- on a Home Screen page or in the Dock, iPadOS's own look or our Mac one -- has "Show in Finder Menu", and
//    "Remove from Finder Menu" once it is attached (DMFFMenuWithRow, from the icon menu hook, StatusBar.x ZetsuIconItems);
//  - the Finder menu lists the attached folders right after the jailbreak folder, in the order attached (DMFFRows); a tap opens the folder the way
//    the jailbreak folder's row does (DMOpenHomeFolder: its page shown, then the folder opened).
// The record is the folders' own identity (common/FinderFolders.h, Mac-tested): it survives renames, moves to other pages and resprings; a folder
// that is deleted drops out of the menu, and out of the record at its next change. The jailbreak folder (DMFindJailbreakFolderIcon) is in the
// menu by itself, as before: its own Haptic Touch menu has no row, and the menu never lists it twice.


// A method of exactly these types here (digits left out, as AddToFolder.x checks SpringBoard's folder calls).
static BOOL DMFFHas(id obj, NSString *sel, const char *types) {
    Method m = obj ? class_getInstanceMethod(object_getClass(obj), NSSelectorFromString(sel)) : NULL;
    if (!m) return NO;
    NSMutableString *bare = [NSMutableString string];
    for (const char *p = method_getTypeEncoding(m) ?: ""; *p; p++) if (!isdigit((unsigned char)*p)) [bare appendFormat:@"%c", *p];
    return [bare isEqualToString:@(types)];
}
static NSArray *DMFFArray(id o) { return [o isKindOfClass:[NSArray class]] ? o : ([o respondsToSelector:@selector(allObjects)] ? [o allObjects] : @[]); }
static BOOL DMFFIsFolderIcon(id icon) { return [DMBoolStr(icon, @"isFolderIcon") isEqualToString:@"Y"]; }
// A folder icon's identity: its folder's -uniqueIdentifier, the one IconState.plist keeps (read on 15.6.1, 16.7.7, 17.5.1 and 18.5; -[SBFolder
// uniqueIdentifier] @@:, 18.5). nil: none here.
static NSString *DMFFUID(id folderIcon) {
    id folder = DMFFIsFolderIcon(folderIcon) ? DMCall(folderIcon, @"folder") : nil;
    if (!DMFFHas(folder, @"uniqueIdentifier", "@@:")) return nil;
    id uid = DMCall(folder, @"uniqueIdentifier");
    return [uid isKindOfClass:[NSString class]] && [(NSString *)uid length] ? uid : nil;
}
static NSString *DMFFName(id folderIcon) {
    id n = DMCall(folderIcon, @"displayName") ?: DMCall(DMCall(folderIcon, @"folder"), @"displayName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}
// Every folder of the Home Screen: its pages in order, hidden ones too (their folders are kept, not shown), then the Dock's. Each: the icon, its
// identity, its page (1 = the first shown page, 0 = the Dock, -1 = a hidden page).
static NSArray<NSDictionary *> *DMFFFolders(void) {
    id root = DMCall(DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconModel"), @"rootFolder");
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSInteger page = 0;
    for (id list in DMFFArray(DMCall(root, @"lists"))) {
        BOOL hidden = [DMBoolStr(list, @"isHidden") isEqualToString:@"Y"];
        if (!hidden) page++;
        for (id icon in DMFFArray(DMCall(list, @"icons"))) {
            NSString *uid = DMFFUID(icon);
            if (uid) [out addObject:@{@"icon": icon, @"uid": uid, @"page": @(hidden ? -1 : page)}];
        }
    }
    for (id icon in DMFFArray(DMCall(DMCall(root, @"dock"), @"icons"))) {
        NSString *uid = DMFFUID(icon);
        if (uid) [out addObject:@{@"icon": icon, @"uid": uid, @"page": @0}];
    }
    return out;
}
static BOOL DMFFModelReady(void) {   // (the Home Screen's model is there: only then can a folder be missing from it)
    id root = DMCall(DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconModel"), @"rootFolder");
    return DMFFArray(DMCall(root, @"lists")).count > 0;
}

// A folder in the Dock opens from the Dock, as a tap on it does: the floating Dock's own -presentFolderForIcon:location:animated:completion: (18.5:
// SBHIconManager's -openFolderIcon:location:animated:withCompletion: with the Dock's location left it closed). The Dock's controller as
// dock/Downloads.m finds it: SBIconController's own on 15, the Dock window's scene's on 16+.
static id DMFFFloatingDockController(void) {
    id ic = DMCall(objc_getClass("SBIconController"), @"sharedInstance");
    Ivar iv = ic ? class_getInstanceVariable(object_getClass(ic), "_floatingDockController") : NULL;
    id ctrl = iv ? object_getIvar(ic, iv) : nil;
    if (ctrl) return ctrl;
    Class dockWindow = objc_getClass("SBFloatingDockWindow");
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) if (dockWindow && [w isKindOfClass:dockWindow] && (ctrl = DMCall(sc, @"floatingDockController"))) return ctrl;
    }
    return nil;
}
static BOOL DMFFOpenDockFolder(id icon, NSString *what) {
    id ctrl = DMFFFloatingDockController();
    if (!DMFFHas(ctrl, @"presentFolderForIcon:location:animated:completion:", "v@:@@B@?")) {
        DMLog([NSString stringWithFormat:@"[folder] %@ is in the Dock: no Dock controller to open it (%@)", what, ctrl ? NSStringFromClass([ctrl class]) : @"none"]);
        return NO;
    }
    DMLog([NSString stringWithFormat:@"[folder] opening %@ in the Dock", what]);
    ((void (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(ctrl, NSSelectorFromString(@"presentFolderForIcon:location:animated:completion:"), icon, @"SBIconLocationFloatingDock", YES, nil);
    return YES;
}

// ---- the record (Settings has no row for it: written here only, read when the Finder menu or a folder's menu is made) ----
static NSArray<NSString *> *DMFFRecord(void) {
    CFPreferencesAppSynchronize(MSB_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_FINDER_FOLDERS_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return MSBDFinderFoldersRecord(v ? CFBridgingRelease(v) : nil);
}
static void DMFFSetAttached(NSString *uid, BOOL attach) {
    NSArray<NSDictionary *> *folders = DMFFFolders();
    NSMutableSet<NSString *> *present = [NSMutableSet set];
    for (NSDictionary *f in folders) [present addObject:f[@"uid"]];
    NSSet *known = DMFFModelReady() ? present : nil;   // (a deleted folder's identifier goes now; nothing goes while the model is not there)
    NSArray<NSString *> *before = DMFFRecord();
    NSArray<NSString *> *after = attach ? MSBDFinderFoldersAttach(before, uid, known) : MSBDFinderFoldersDetach(before, uid, known);
    CFPreferencesSetValue(CFSTR(MSBD_FINDER_FOLDERS_KEY), after.count ? (__bridge CFPropertyListRef)after : NULL, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    DM_FEATURE_MARK("finder-menu-folders");
    NSString *name = nil;
    for (NSDictionary *f in folders) if ([f[@"uid"] isEqualToString:uid]) name = DMFFName(f[@"icon"]);
    DMLog([NSString stringWithFormat:@"[finderfolders] \"%@\" (%@) %@ the Finder menu: %lu attached (%lu before)", name ?: @"?", uid,
           attach ? @"shown in" : @"removed from", (unsigned long)after.count, (unsigned long)before.count]);
}

// ---- a folder's Haptic Touch menu ----
// The folder an icon view's menu is for, when its row belongs there: a folder on a Home Screen page or in the Dock (not the App Library's
// categories or our desktop's items), with its identity, and not the jailbreak folder the Finder menu lists by itself.
static id DMFFMenuFolder(UIView *iconView) {
    id icon = DMCall(iconView, @"icon");
    NSString *loc = DMCall(iconView, @"location");
    if (!DMFFUID(icon) || ![loc isKindOfClass:[NSString class]] || [loc containsString:@"AppLibrary"]) return nil;
    if (![loc isEqualToString:@"SBIconLocationRoot"] && ![loc containsString:@"Dock"]) return nil;
    if ([DMFFUID(DMFindJailbreakFolderIcon(NULL)) isEqualToString:DMFFUID(icon)]) return nil;
    return icon;
}
// The row goes at the end of the menu, in a section of its own: iPadOS's folder rows have no fixed identifiers to place it by (18.5: one flat
// list -- the folder's apps (Folder Apps in Folder Menus), Rename, Edit Home Screen, Remove Folder --, each "com.apple.action.dynamic.<UUID>").
static UIMenu *DMFFMenuWithRow(UIMenu *m, id folderIcon) {
    NSString *uid = DMFFUID(folderIcon);
    if (![m isKindOfClass:[UIMenu class]] || !uid) return m;
    BOOL attached = [DMFFRecord() containsObject:uid];
    UIAction *ours = [UIAction actionWithTitle:MSBDFinderFolderMenuTitle(attached) image:[UIImage systemImageNamed:attached ? @"pin.slash" : @"pin"]
                                    identifier:@"com.besiktasliseba.finderfolder" handler:^(UIAction *a) { DMFFSetAttached(uid, !attached); }];
    for (UIMenuElement *e in m.children) if ([e isKindOfClass:[UIMenu class]] && [((UIMenu *)e).identifier isEqualToString:@"com.besiktasliseba.finderfolders"]) return m;   // (once)
    UIMenu *section = [UIMenu menuWithTitle:@"" image:nil identifier:@"com.besiktasliseba.finderfolders" options:UIMenuOptionsDisplayInline children:@[ours]];
    return [m menuByReplacingChildren:[m.children arrayByAddingObject:section]];
}

// ---- the Finder menu's rows ----
// The attached folders on the Home Screen now, in the order attached, after the jailbreak folder's row (jbIcon, listed by the menu itself). A tap
// opens the folder, found again by its identity (it may have moved since the menu opened).
static NSArray<DMRow *> *DMFFRows(id jbIcon) {
    NSArray<NSString *> *record = DMFFRecord();
    if (!record.count) return @[];
    NSMutableDictionary<NSString *, NSDictionary *> *byUID = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *shown = [NSMutableSet set];
    for (NSDictionary *f in DMFFFolders()) { byUID[f[@"uid"]] = f; if ([f[@"page"] integerValue] >= 0) [shown addObject:f[@"uid"]]; }
    NSArray<NSString *> *listed = MSBDFinderFoldersListed(record, shown, DMFFUID(jbIcon));
    NSMutableArray *names = [NSMutableArray array], *pages = [NSMutableArray array];
    for (NSString *uid in listed) { [names addObject:DMFFName(byUID[uid][@"icon"]) ?: @""]; [pages addObject:byUID[uid][@"page"]]; }
    NSArray<NSString *> *titles = MSBDFinderFolderTitles(names, pages);
    NSMutableArray<DMRow *> *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < listed.count; i++) {
        NSString *uid = listed[i];
        [rows addObject:[[DMRow alloc] initWithTitle:titles[i] enabled:YES handler:DMCloseThen(^{
            id icon = nil;
            for (NSDictionary *f in DMFFFolders()) if ([f[@"uid"] isEqualToString:uid]) icon = f[@"icon"];
            DMOpenHomeFolder(icon, @"an attached folder");
        })]];
    }
    if (record.count != listed.count) DMLog([NSString stringWithFormat:@"[finderfolders] %lu attached, %lu listed (the others deleted, on a hidden page, or the jailbreak folder)",
                                            (unsigned long)record.count, (unsigned long)listed.count]);
    return rows;
}

#if DEBUG
// ---- debug triggers: ffstate, ffattach_<uid>, ffdetach_<uid>, ffopen_<uid>, ffmove_<uid>_<page>, ffrename_<uid>_<name>, ffmenu (the next icon menu's
// tree is logged) ----
static BOOL gFFLogMenu = NO;
static void DMFFLogMenuTree(UIMenuElement *e, int depth, NSMutableString *out) {
    if ([e isKindOfClass:[UIMenu class]]) {
        UIMenu *m = (UIMenu *)e;
        [out appendFormat:@"\n[finderfolders]   %*smenu \"%@\" id %@ options %lu (%lu)", depth * 2, "", m.title, m.identifier, (unsigned long)m.options, (unsigned long)m.children.count];
        for (UIMenuElement *k in m.children) DMFFLogMenuTree(k, depth + 1, out);
    } else if ([e isKindOfClass:[UIAction class]]) {
        UIAction *a = (UIAction *)e;
        [out appendFormat:@"\n[finderfolders]   %*saction \"%@\" id %@ attributes %lu", depth * 2, "", a.title, a.identifier, (unsigned long)a.attributes];
    } else [out appendFormat:@"\n[finderfolders]   %*s%@ \"%@\"", depth * 2, "", NSStringFromClass([e class]), e.title];
}
static void DMFFDebugMenu(UIMenu *m, UIView *iconView) {
    if (!gFFLogMenu || !m) return;
    gFFLogMenu = NO;
    NSMutableString *out = [NSMutableString stringWithFormat:@"[finderfolders] icon menu of %@ at %@:", NSStringFromClass([DMCall(iconView, @"icon") class]), DMCall(iconView, @"location")];
    DMFFLogMenuTree(m, 0, out);
    DMLog(out);
}
static id DMFFFolderByUID(NSString *uid) { for (NSDictionary *f in DMFFFolders()) if ([f[@"uid"] isEqualToString:uid]) return f[@"icon"]; return nil; }
static void DMFFSaveLayout(void) {   // (as after any change of the Home Screen: SpringBoard's own save, as AddToFolder.x)
    id model = DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconModel");
    if ([model respondsToSelector:NSSelectorFromString(@"markIconStateDirty")]) ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"markIconStateDirty"));
    if ([model respondsToSelector:NSSelectorFromString(@"saveIconStateIfNeeded")]) ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
}
static BOOL DMFFTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"ffstate"]) {   // the record, every folder, and the Finder menu's folder rows now (read-only)
        NSArray<NSString *> *record = DMFFRecord();
        NSMutableString *o = [NSMutableString stringWithFormat:@"[finderfolders] record (%lu): %@; jailbreak folder %@; folders:", (unsigned long)record.count,
                              [record componentsJoinedByString:@", "], DMFFUID(DMFindJailbreakFolderIcon(NULL)) ?: @"none"];
        for (NSDictionary *f in DMFFFolders())
            [o appendFormat:@" [\"%@\" %@ page %@%@]", DMFFName(f[@"icon"]), f[@"uid"], f[@"page"], [record containsObject:f[@"uid"]] ? @" ATTACHED" : @""];
        NSMutableArray *titles = [NSMutableArray array];
        for (DMRow *r in DMFFRows(DMFindJailbreakFolderIcon(NULL))) [titles addObject:r.label.text ?: @"?"];
        [o appendFormat:@"; the Finder menu lists: %@", titles.count ? [titles componentsJoinedByString:@" | "] : @"(none)"];
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"ffshow"]) {   // whether the windows step aside for an open folder now, and why (StatusBar.x DMHomeFolderShowing; read-only)
        DMLog([NSString stringWithFormat:@"[finderfolders] hasOpenFolder %d; rule: was open %d, showing %d, front at open %016llx; front now %@ (%016llx), full-screen app %@, engine fade %d",
               DMHomeFolderOpenNow(), gHomeFolder.wasOpen, gHomeFolder.showing, gHomeFolder.frontAtOpen, [DMActiveApp() bundleIdentifier] ?: @"none",
               MSBDHomeFolderFrontID([DMActiveApp() bundleIdentifier].UTF8String), [DMFrontApp() bundleIdentifier] ?: @"none", gWindowsHiddenForLibrary || DMSMDeskIsFaded()]);
        return YES;
    }
    if ([cmd hasPrefix:@"ffattach_"] || [cmd hasPrefix:@"ffdetach_"]) { DMFFSetAttached([cmd substringFromIndex:9], [cmd hasPrefix:@"ffattach_"]); return YES; }   // as the folder's row does
    if ([cmd hasPrefix:@"ffopen_"]) { DMOpenHomeFolder(DMFFFolderByUID([cmd substringFromIndex:7]), @"a folder (test)"); return YES; }   // as the Finder menu's row does
    if ([cmd isEqualToString:@"ffmenu"]) { gFFLogMenu = YES; DMLog(@"[finderfolders] the next icon menu's tree is logged"); return YES; }
    if ([cmd hasPrefix:@"ffmove_"]) {   // ffmove_<uid>_<page>: the folder moved to the end of that page (1 = the first; 0 = the Dock) through the model -- a move
        // between pages without an icon drag (tests); saved as any change of the Home Screen
        NSArray *q = [[cmd substringFromIndex:7] componentsSeparatedByString:@"_"];
        id icon = q.count == 2 ? DMFFFolderByUID(q[0]) : nil;
        id root = DMCall(DMCall(DMCall(DMCall(objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager"), @"iconModel"), @"rootFolder");
        NSArray *lists = DMFFArray(DMCall(root, @"lists"));
        id dock = DMCall(root, @"dock");
        NSInteger want = q.count == 2 ? [q[1] integerValue] : -1;
        id target = want == 0 ? dock : (want >= 1 && want <= (NSInteger)lists.count ? lists[want - 1] : nil);
        SEL has = NSSelectorFromString(@"directlyContainsIcon:"), rm = NSSelectorFromString(@"removeIcon:"), add = NSSelectorFromString(@"addIcon:");
        if (!icon || !target || ![target respondsToSelector:add]) { DMLog([NSString stringWithFormat:@"[finderfolders] ffmove: folder %@, page %ld of %lu: not moved", icon ? @"found" : @"not found", (long)want, (unsigned long)lists.count]); return YES; }
        for (id list in dock ? [lists arrayByAddingObject:dock] : lists) if ([list respondsToSelector:has] && [list respondsToSelector:rm] && ((BOOL (*)(id, SEL, id))objc_msgSend)(list, has, icon)) ((void (*)(id, SEL, id))objc_msgSend)(list, rm, icon);
        ((id (*)(id, SEL, id))objc_msgSend)(target, add, icon);
        DMFFSaveLayout();
        DMLog([NSString stringWithFormat:@"[finderfolders] ffmove: \"%@\" moved to page %ld", DMFFName(icon), (long)want]);
        return YES;
    }
    if ([cmd hasPrefix:@"ffrename_"]) {   // ffrename_<uid>_<name>: the folder renamed as Rename does (its folder's -setDisplayName:), saved
        NSString *rest = [cmd substringFromIndex:9];
        NSRange u = [rest rangeOfString:@"_"];
        id icon = u.location != NSNotFound ? DMFFFolderByUID([rest substringToIndex:u.location]) : nil;
        id folder = DMCall(icon, @"folder");
        if (!DMFFHas(folder, @"setDisplayName:", "v@:@")) { DMLog(@"[finderfolders] ffrename: no folder or no -setDisplayName:"); return YES; }
        ((void (*)(id, SEL, id))objc_msgSend)(folder, NSSelectorFromString(@"setDisplayName:"), [rest substringFromIndex:u.location + 1]);
        DMFFSaveLayout();
        DMLog([NSString stringWithFormat:@"[finderfolders] ffrename: now \"%@\"", DMFFName(icon)]);
        return YES;
    }
    return NO;
}
#endif
