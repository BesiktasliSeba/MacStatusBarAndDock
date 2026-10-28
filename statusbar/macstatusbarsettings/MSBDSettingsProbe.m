// MSBDSettingsProbe.m -- DEBUG builds only: a small test driver inside the Settings app, so the Settings pages can be checked from the Mac even
// when nothing of ours runs in SpringBoard (an untested iPadOS version: only the Settings rows load, so SpringBoard's triggers and captures are
// gone). Loaded with the Status Bar row (MacStatusBarSettings), which loads in that state too.
//
// On while /tmp/msbd-settings-debug exists. Commands are written to /tmp/msbd-settings-trigger (read by its modification time; a file left over
// from before Settings started is only noted, never run). Output: /tmp/msbd-settings.log, /tmp/msbd-settings.png.
//   shot                  the Settings window as it is drawn -> /tmp/msbd-settings.png
//   open <row id>         selects that row of the main list the way a tap does (MAC_STATUS_BAR, DOCK_MAGNIFICATION, HOME_SCREEN_DOCK, ...)
//   dump                  every page on screen: its rows (title, value, identifier) and group footers
//   set <spec id> <0|1>   sets that switch through its page the way flipping it does
//   alert <button title>  presses that button of the alert on screen
//   tap <spec id>         selects that row of a page on screen the way a tap does (a button row runs its action, e.g. MSBD_SAFE_ON)
//   back [n]              the key window's top navigation stack back to its first page, or n pages back (as Back does)
//   rootids               the main list's rows (15-17: PSUIPrefsListController), shown or not: identifier, name, page class or bundle
//   sidebar               the window's size class, the split view (sidebar or one column), the selected main-list row and whether it is on screen
//   embed <class> [bundle] Apple's page made as our pages make it (common/NativeEmbed.h, never shown) and its rows listed: identifier, name, cell
//                         type, detail class, footer (read-only; for 1.6.0's Windows & Multitasking page)
#if DEBUG
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <unistd.h>

@interface PSSpecifier : NSObject
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSString *name;
- (id)propertyForKey:(NSString *)key;
@end

static NSArray<UIWindow *> *MSBDWindows(void) {
    NSMutableArray *all = [NSMutableArray array];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) if ([sc isKindOfClass:[UIWindowScene class]]) [all addObjectsFromArray:((UIWindowScene *)sc).windows];
    return all;
}
static void MSBDProbeLog(NSString *s) {
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:[NSDate date]], s];
    FILE *f = fopen("/tmp/msbd-settings.log", "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}

static void MSBDCollectControllers(UIViewController *vc, NSMutableArray *out) {
    if (!vc || [out containsObject:vc]) return;
    [out addObject:vc];
    for (UIViewController *c in vc.childViewControllers) MSBDCollectControllers(c, out);
    if (vc.presentedViewController) MSBDCollectControllers(vc.presentedViewController, out);
}
static NSArray *MSBDControllers(void) {
    NSMutableArray *all = [NSMutableArray array];
    for (UIWindow *w in MSBDWindows()) MSBDCollectControllers(w.rootViewController, all);
    return all;
}
static UIViewController *MSBDFind(BOOL (^match)(UIViewController *)) {
    for (UIViewController *vc in MSBDControllers()) if (match(vc)) return vc;
    return nil;
}
static BOOL MSBDIsList(UIViewController *vc) {
    Class c = NSClassFromString(@"PSListController");
    return c && [vc isKindOfClass:c] && vc.isViewLoaded && vc.view.window;
}

static void MSBDShot(void) {
    UIWindow *win = nil;
    for (UIWindow *w in MSBDWindows()) if (!w.hidden && (!win || w.isKeyWindow)) win = w;
    if (!win) { MSBDProbeLog(@"[shot] no window"); return; }
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat]; fmt.scale = 1.0;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:win.bounds format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        for (UIWindow *w in MSBDWindows()) if (!w.hidden && w.alpha > 0.01) [w drawViewHierarchyInRect:w.frame afterScreenUpdates:NO];
    }];
    BOOL ok = [UIImagePNGRepresentation(img) writeToFile:@"/tmp/msbd-settings.png" atomically:YES];
    MSBDProbeLog([NSString stringWithFormat:@"[shot] %@ -> %d", NSStringFromCGSize(win.bounds.size), ok]);
}

static void MSBDOpen(NSString *rowID) {
    UIViewController *list = MSBDFind(^BOOL(UIViewController *vc) { return [NSStringFromClass([vc class]) isEqualToString:@"PSUIPrefsListController"]; });
    if (!list) { MSBDProbeLog(@"[open] main list not found"); return; }
    id spec = ((id (*)(id, SEL, id))objc_msgSend)(list, NSSelectorFromString(@"specifierForID:"), rowID);
    NSIndexPath *ip = spec ? ((id (*)(id, SEL, id))objc_msgSend)(list, NSSelectorFromString(@"indexPathForSpecifier:"), spec) : nil;
    UITableView *table = ((id (*)(id, SEL))objc_msgSend)(list, NSSelectorFromString(@"table"));
    if (!ip || !table) { MSBDProbeLog([NSString stringWithFormat:@"[open] %@ not in the main list", rowID]); return; }
    [table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [table selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    ((void (*)(id, SEL, id, id))objc_msgSend)(list, @selector(tableView:didSelectRowAtIndexPath:), table, ip);
    MSBDProbeLog([NSString stringWithFormat:@"[open] %@ selected (row %ld.%ld)", rowID, (long)ip.section, (long)ip.row]);
}

static void MSBDDumpList(UIViewController *list) {
    NSArray *specs = ((id (*)(id, SEL))objc_msgSend)(list, NSSelectorFromString(@"specifiers"));
    MSBDProbeLog([NSString stringWithFormat:@"[dump] page %@ \"%@\" (%lu specifiers)", NSStringFromClass([list class]), list.title ?: list.navigationItem.title, (unsigned long)specs.count]);
    UITableView *table = ((id (*)(id, SEL))objc_msgSend)(list, NSSelectorFromString(@"table"));
    for (PSSpecifier *sp in specs) {
        NSString *value = @"";
        NSIndexPath *ip = ((id (*)(id, SEL, id))objc_msgSend)(list, NSSelectorFromString(@"indexPathForSpecifier:"), sp);
        UITableViewCell *cell = ip ? [table cellForRowAtIndexPath:ip] : nil;
        if (cell.detailTextLabel.text.length) value = cell.detailTextLabel.text;
        UISwitch *sw = [cell.accessoryView isKindOfClass:[UISwitch class]] ? (UISwitch *)cell.accessoryView : nil;
        if (sw) value = sw.on ? @"[switch on]" : @"[switch off]";
        NSString *footer = [sp propertyForKey:@"footerText"];
        MSBDProbeLog([NSString stringWithFormat:@"[dump]   %@ \"%@\" %@%@", sp.identifier ?: @"-", sp.name ?: @"", value, footer.length ? [NSString stringWithFormat:@" footer \"%@\"", footer] : @""]);
    }
}
static void MSBDDump(void) {
    for (UIViewController *vc in MSBDControllers()) if (MSBDIsList(vc)) MSBDDumpList(vc);
}

static void MSBDBack(int n) {
    UINavigationController *nav = nil;
    for (UIViewController *vc in MSBDControllers()) if ([vc isKindOfClass:[UINavigationController class]] && vc.view.window && ((UINavigationController *)vc).viewControllers.count > 1) nav = (UINavigationController *)vc;
    if (!nav) { MSBDProbeLog(@"[back] no navigation stack with a page to go back from"); return; }
    NSArray *vcs = nav.viewControllers;
    if (n <= 0 || (NSUInteger)n >= vcs.count) [nav popToRootViewControllerAnimated:NO];
    else [nav popToViewController:vcs[vcs.count - 1 - (NSUInteger)n] animated:NO];
    MSBDProbeLog([NSString stringWithFormat:@"[back] %lu -> %lu pages, top %@", (unsigned long)vcs.count, (unsigned long)nav.viewControllers.count, NSStringFromClass([nav.topViewController class])]);
}
static void MSBDRootIDs(void) {
    UIViewController *list = MSBDFind(^BOOL(UIViewController *vc) { return [NSStringFromClass([vc class]) isEqualToString:@"PSUIPrefsListController"]; });
    if (!list) { MSBDProbeLog(@"[rootids] no main list (iPadOS 18: SwiftUI)"); return; }
    NSArray *specs = ((id (*)(id, SEL))objc_msgSend)(list, NSSelectorFromString(@"specifiers"));
    NSMutableString *o = [NSMutableString string];
    for (PSSpecifier *sp in specs) {
        id detail = [sp respondsToSelector:NSSelectorFromString(@"detailControllerClass")] ? ((id (*)(id, SEL))objc_msgSend)(sp, NSSelectorFromString(@"detailControllerClass")) : nil;
        id bundle = [sp propertyForKey:@"bundle"] ?: [sp propertyForKey:@"lazy-bundle"];
        [o appendFormat:@" | %@ \"%@\" %@%@", sp.identifier ?: @"-", sp.name ?: @"", detail ? NSStringFromClass(detail) : @"", bundle ? [NSString stringWithFormat:@" (%@)", bundle] : @""];
    }
    MSBDProbeLog([NSString stringWithFormat:@"[rootids] %lu rows:%@", (unsigned long)specs.count, o]);
}
static void MSBDEmbed(NSString *className, NSString *bundlePath) {
    Class c = NSClassFromString(className);
    if (!c && bundlePath.length) { [[NSBundle bundleWithPath:bundlePath] load]; c = NSClassFromString(className); }
    if (!c || ![c isSubclassOfClass:NSClassFromString(@"PSListController")]) { MSBDProbeLog([NSString stringWithFormat:@"[embed] %@: no such list class", className]); return; }
    UIViewController *host = MSBDFind(^BOOL(UIViewController *vc) { return MSBDIsList(vc); });
    NSArray *specs = nil;
    @try {
        UIViewController *page = [[c alloc] init];
        if (host) {
            SEL rc = NSSelectorFromString(@"rootController"), src = NSSelectorFromString(@"setRootController:"), spc = NSSelectorFromString(@"setParentController:");
            if ([host respondsToSelector:rc] && [page respondsToSelector:src]) ((void (*)(id, SEL, id))objc_msgSend)(page, src, ((id (*)(id, SEL))objc_msgSend)(host, rc));
            if ([page respondsToSelector:spc]) ((void (*)(id, SEL, id))objc_msgSend)(page, spc, host);
        }
        specs = ((id (*)(id, SEL))objc_msgSend)(page, NSSelectorFromString(@"specifiers"));
    } @catch (NSException *e) { MSBDProbeLog([NSString stringWithFormat:@"[embed] %@ threw %@: %@", className, e.name, e.reason]); return; }
    MSBDProbeLog([NSString stringWithFormat:@"[embed] %@: %lu rows", className, (unsigned long)specs.count]);
    SEL ct = NSSelectorFromString(@"cellType"), dc = NSSelectorFromString(@"detailControllerClass");
    for (PSSpecifier *sp in specs) {
        long long type = [sp respondsToSelector:ct] ? ((long long (*)(id, SEL))objc_msgSend)(sp, ct) : -1;
        id detail = [sp respondsToSelector:dc] ? ((id (*)(id, SEL))objc_msgSend)(sp, dc) : nil;
        NSString *footer = [sp propertyForKey:@"footerText"];
        id key = [sp propertyForKey:@"key"], defaults = [sp propertyForKey:@"defaults"];
        MSBDProbeLog([NSString stringWithFormat:@"[embed]   %@ \"%@\" cell %lld%@%@%@", sp.identifier ?: @"-", sp.name ?: @"", type, detail ? [@" detail " stringByAppendingString:NSStringFromClass(detail)] : @"",
                      key ? [NSString stringWithFormat:@" key %@/%@", defaults ?: @"-", key] : @"", footer.length ? [NSString stringWithFormat:@" footer \"%@\"", footer] : @""]);
    }
}

static void MSBDSet(NSString *specID, BOOL on) {
    for (UIViewController *vc in MSBDControllers()) {
        if (!MSBDIsList(vc) || [NSStringFromClass([vc class]) isEqualToString:@"PSUIPrefsListController"]) continue;
        id spec = ((id (*)(id, SEL, id))objc_msgSend)(vc, NSSelectorFromString(@"specifierForID:"), specID);
        if (!spec) continue;
        // (the switch's own setter, the way flipping it calls it -- a page's custom setter is not reached through setPreferenceValue:specifier:)
        SEL perform = NSSelectorFromString(@"performSetterWithValue:");
        if ([spec respondsToSelector:perform]) ((void (*)(id, SEL, id))objc_msgSend)(spec, perform, @(on));
        else ((void (*)(id, SEL, id, id))objc_msgSend)(vc, NSSelectorFromString(@"setPreferenceValue:specifier:"), @(on), spec);
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(vc, NSSelectorFromString(@"reloadSpecifier:animated:"), spec, NO);
        MSBDProbeLog([NSString stringWithFormat:@"[set] %@ = %d on %@", specID, on, NSStringFromClass([vc class])]);
        return;
    }
    MSBDProbeLog([NSString stringWithFormat:@"[set] %@ not found on any page", specID]);
}

static void MSBDTap(NSString *specID) {
    for (UIViewController *vc in MSBDControllers()) {
        if (!MSBDIsList(vc) || [NSStringFromClass([vc class]) isEqualToString:@"PSUIPrefsListController"]) continue;
        id spec = ((id (*)(id, SEL, id))objc_msgSend)(vc, NSSelectorFromString(@"specifierForID:"), specID);
        NSIndexPath *ip = spec ? ((id (*)(id, SEL, id))objc_msgSend)(vc, NSSelectorFromString(@"indexPathForSpecifier:"), spec) : nil;
        UITableView *table = ((id (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"table"));
        if (!ip || !table) continue;
        [table scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [table selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];   // (as a real tap: some pages read the selection)
        @try { ((void (*)(id, SEL, id, id))objc_msgSend)(vc, @selector(tableView:didSelectRowAtIndexPath:), table, ip); }
        @catch (NSException *e) { MSBDProbeLog([NSString stringWithFormat:@"[tap] %@ on %@ threw %@: %@", specID, NSStringFromClass([vc class]), e.name, e.reason]); return; }
        MSBDProbeLog([NSString stringWithFormat:@"[tap] %@ on %@ (row %ld.%ld)", specID, NSStringFromClass([vc class]), (long)ip.section, (long)ip.row]);
        return;
    }
    MSBDProbeLog([NSString stringWithFormat:@"[tap] %@ not found on any page", specID]);
}

static void MSBDAlert(NSString *title) {
    UIAlertController *alert = (UIAlertController *)MSBDFind(^BOOL(UIViewController *vc) { return [vc isKindOfClass:[UIAlertController class]]; });
    if (!alert) { MSBDProbeLog(@"[alert] no alert on screen"); return; }
    MSBDProbeLog([NSString stringWithFormat:@"[alert] \"%@\" / \"%@\"", alert.title, alert.message]);
    for (UIAlertAction *a in alert.actions) {
        if (![a.title isEqualToString:title]) continue;
        void (^handler)(UIAlertAction *) = [a respondsToSelector:NSSelectorFromString(@"handler")] ? ((id (*)(id, SEL))objc_msgSend)(a, NSSelectorFromString(@"handler")) : nil;
        [alert dismissViewControllerAnimated:YES completion:^{ if (handler) handler(a); }];
        MSBDProbeLog([NSString stringWithFormat:@"[alert] pressed \"%@\" (handler %d)", title, handler != nil]);
        return;
    }
    MSBDProbeLog([NSString stringWithFormat:@"[alert] no button \"%@\"", title]);
}

// Read-only research (1.6.0, the 18 sidebar): ObjC runtime names only -- no instance made, no Swift metadata read.
//   images <part>        loaded images whose path contains <part>
//   classes <part>       the ObjC-visible class names of those images (with superclass)
//   methods <Class>      a class's ObjC methods (instance and class, with types) and ivar names
//   protos <part>        protocols whose name contains <part>
//   vctree               the key window's view controllers, by class (child and presented ones)
#include <mach-o/dyld.h>
static void MSBDImages(NSString *part, BOOL withClasses) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || ![@(name) localizedCaseInsensitiveContainsString:part]) continue;
        if (!withClasses) { MSBDProbeLog([NSString stringWithFormat:@"[images] %s", name]); continue; }
        unsigned n = 0; const char **cls = objc_copyClassNamesForImage(name, &n);
        NSMutableArray *names = [NSMutableArray array];
        for (unsigned k = 0; k < n; k++) { Class c = objc_getClass(cls[k]); [names addObject:[NSString stringWithFormat:@"%s<%s", cls[k], c && class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "-"]]; }
        free(cls);
        [names sortUsingSelector:@selector(compare:)];
        MSBDProbeLog([NSString stringWithFormat:@"[classes] %s (%u): %@", name, n, [names componentsJoinedByString:@" "]]);
    }
}
static void MSBDMethods(NSString *name) {
    Class c = objc_getClass(name.UTF8String);
    if (!c) { MSBDProbeLog([NSString stringWithFormat:@"[methods] %@: no such class", name]); return; }
    NSMutableArray *out = [NSMutableArray array];
    for (int meta = 1; meta >= 0; meta--) {
        unsigned n = 0; Method *m = class_copyMethodList(meta ? object_getClass((id)c) : c, &n);
        for (unsigned k = 0; k < n; k++) [out addObject:[NSString stringWithFormat:@"%s%s(%s)", meta ? "+" : "-", sel_getName(method_getName(m[k])), method_getTypeEncoding(m[k]) ?: ""]];
        free(m);
    }
    unsigned iv = 0; Ivar *ivs = class_copyIvarList(c, &iv);
    NSMutableArray *ivars = [NSMutableArray array];
    for (unsigned k = 0; k < iv; k++) [ivars addObject:[NSString stringWithFormat:@"%s(%s)", ivar_getName(ivs[k]), ivar_getTypeEncoding(ivs[k]) ?: ""]];
    free(ivs);
    unsigned pc = 0; Protocol * __unsafe_unretained *ps = class_copyProtocolList(c, &pc);
    NSMutableArray *protos = [NSMutableArray array];
    for (unsigned k = 0; k < pc; k++) [protos addObject:@(protocol_getName(ps[k]))];
    free(ps);
    MSBDProbeLog([NSString stringWithFormat:@"[methods] %@ < %s: %@ | ivars: %@ | protocols: %@", name, class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "-",
        [out componentsJoinedByString:@" "], [ivars componentsJoinedByString:@" "], [protos componentsJoinedByString:@" "]]);
}
static void MSBDProtos(NSString *part) {
    unsigned n = 0; Protocol * __unsafe_unretained *ps = objc_copyProtocolList(&n);
    NSMutableArray *out = [NSMutableArray array];
    for (unsigned k = 0; k < n; k++) { NSString *nm = @(protocol_getName(ps[k])); if ([nm localizedCaseInsensitiveContainsString:part]) [out addObject:nm]; }
    free(ps);
    [out sortUsingSelector:@selector(compare:)];
    MSBDProbeLog([NSString stringWithFormat:@"[protos] %@: %@", part, [out componentsJoinedByString:@" "]]);
}
static void MSBDVCTree(UIViewController *vc, int depth, NSMutableString *out) {
    if (!vc || depth > 14) return;
    [out appendFormat:@"\n%*s%@", depth * 2, "", NSStringFromClass([vc class])];
    for (UIViewController *ch in vc.childViewControllers) MSBDVCTree(ch, depth + 1, out);
    if (vc.presentedViewController && vc.presentedViewController.presentingViewController == vc) { [out appendFormat:@"\n%*s(presented)", depth * 2 + 2, ""]; MSBDVCTree(vc.presentedViewController, depth + 1, out); }
}

// sidebar: Settings' window and size class, whether its split view shows the sidebar or one column, the main list's selected row and whether it is
// fully on screen, and what the page column shows (read-only; 15-17, where the main list is PSUIPrefsListController).
static void MSBDSidebar(void) {
    UIViewController *list = MSBDFind(^BOOL(UIViewController *vc) { return [NSStringFromClass([vc class]) isEqualToString:@"PSUIPrefsListController"]; });
    UIWindow *win = nil;
    for (UIWindow *w in MSBDWindows()) if (!w.hidden && (!win || w.isKeyWindow)) win = w;
    if (!list) { MSBDProbeLog([NSString stringWithFormat:@"[sidebar] no main list (iPadOS 18: SwiftUI); window %@", NSStringFromCGSize(win.bounds.size)]); return; }
    UISplitViewController *split = list.splitViewController;
    UITableView *t = nil; @try { t = [list valueForKey:@"table"]; } @catch (NSException *e) {}
    NSIndexPath *sel = [t isKindOfClass:[UITableView class]] ? t.indexPathForSelectedRow : nil;
    id sp = sel ? ((id (*)(id, SEL, id))objc_msgSend)(list, NSSelectorFromString(@"specifierAtIndexPath:"), sel) : nil;
    CGRect row = sel ? [t rectForRowAtIndexPath:sel] : CGRectNull;
    CGRect seen = UIEdgeInsetsInsetRect(t.bounds, t.adjustedContentInset);   // (the part of the list on screen, in its content's coordinates)
    BOOL shown = list.view.window != nil && !list.view.hidden && (!split || !split.collapsed);
    BOOL onScreen = shown && sel && CGRectContainsRect(seen, row);
    UIViewController *detail = split && !split.collapsed && split.viewControllers.count > 1 ? split.viewControllers.lastObject : (split.viewControllers.firstObject ?: list.navigationController);
    UINavigationController *nav = [detail isKindOfClass:[UINavigationController class]] ? (UINavigationController *)detail : detail.navigationController;
    NSMutableArray *stack = [NSMutableArray array];
    for (UIViewController *vc in nav.viewControllers) [stack addObject:[NSString stringWithFormat:@"%@ \"%@\"", NSStringFromClass([vc class]), vc.title ?: vc.navigationItem.title ?: @""]];
    MSBDProbeLog([NSString stringWithFormat:@"[sidebar] window %@ (%@), split %@; sidebar %@; selected row %@ \"%@\" at y %.0f-%.0f, list shows y %.0f-%.0f: %@; page column: %@",
                  NSStringFromCGSize(win.bounds.size), win.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular ? @"regular width" : @"compact width",
                  !split ? @"none" : (split.collapsed ? @"collapsed (one column)" : @"expanded"), shown ? @"on screen" : @"not on screen",
                  [sp respondsToSelector:@selector(identifier)] ? [sp identifier] : @"-", [sp respondsToSelector:@selector(name)] ? [sp name] : @"",
                  CGRectGetMinY(row), CGRectGetMaxY(row), CGRectGetMinY(seen), CGRectGetMaxY(seen), onScreen ? @"ROW ON SCREEN" : @"row not on screen",
                  [stack componentsJoinedByString:@" > "] ?: @"-"]);
}

static void MSBDRun(NSString *cmd) {
    MSBDProbeLog([NSString stringWithFormat:@"[trigger] %@", cmd]);
    NSArray *p = [cmd componentsSeparatedByString:@" "];
    if ([cmd isEqualToString:@"shot"]) MSBDShot();
    else if ([cmd isEqualToString:@"dump"]) MSBDDump();
    else if ([p[0] isEqualToString:@"open"] && p.count == 2) MSBDOpen(p[1]);
    else if ([p[0] isEqualToString:@"set"] && p.count >= 3) MSBDSet([[p subarrayWithRange:NSMakeRange(1, p.count - 2)] componentsJoinedByString:@" "], [p.lastObject boolValue]);   // (ids may contain spaces)
    else if ([p[0] isEqualToString:@"tap"] && p.count >= 2) MSBDTap([[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@" "]);
    else if ([p[0] isEqualToString:@"alert"] && p.count >= 2) MSBDAlert([[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@" "]);
    else if ([p[0] isEqualToString:@"images"] && p.count == 2) MSBDImages(p[1], NO);
    else if ([p[0] isEqualToString:@"classes"] && p.count == 2) MSBDImages(p[1], YES);
    else if ([p[0] isEqualToString:@"methods"] && p.count == 2) MSBDMethods(p[1]);
    else if ([p[0] isEqualToString:@"protos"] && p.count == 2) MSBDProtos(p[1]);
    else if ([cmd isEqualToString:@"rootids"]) MSBDRootIDs();
    else if ([cmd isEqualToString:@"sidebar"]) MSBDSidebar();
    else if ([p[0] isEqualToString:@"back"]) MSBDBack(p.count >= 2 ? [p[1] intValue] : 0);
    else if ([p[0] isEqualToString:@"embed"] && p.count >= 2) MSBDEmbed(p[1], p.count >= 3 ? p[2] : nil);
    else if ([cmd isEqualToString:@"vctree"]) {
        NSMutableString *out = [NSMutableString stringWithString:@"[vctree]"];
        for (UIWindow *w in MSBDWindows()) if (w.isKeyWindow || w.rootViewController) MSBDVCTree(w.rootViewController, 0, out);
        MSBDProbeLog(out);
    }
}

static void MSBDPoll(void) {
    static double last = -1;
    struct stat st;
    if (access("/tmp/msbd-settings-debug", F_OK) == 0 && stat("/tmp/msbd-settings-trigger", &st) == 0) {
        double m = st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9;
        if (last < 0) last = m;   // (a file from before Settings started is not run)
        else if (m != last) {
            last = m;
            NSString *cmd = [[NSString stringWithContentsOfFile:@"/tmp/msbd-settings-trigger" encoding:NSUTF8StringEncoding error:nil]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (cmd.length) MSBDRun(cmd);
        }
    } else if (last < 0) last = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBDPoll(); });
}

__attribute__((constructor)) static void MSBDSettingsProbeStart(void) {
    if (access("/tmp/msbd-settings-debug", F_OK) != 0) return;   // (checked once at start: without the flag nothing runs at all)
    dispatch_async(dispatch_get_main_queue(), ^{ MSBDPoll(); });
}
#endif
