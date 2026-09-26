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

static void MSBDRun(NSString *cmd) {
    MSBDProbeLog([NSString stringWithFormat:@"[trigger] %@", cmd]);
    NSArray *p = [cmd componentsSeparatedByString:@" "];
    if ([cmd isEqualToString:@"shot"]) MSBDShot();
    else if ([cmd isEqualToString:@"dump"]) MSBDDump();
    else if ([p[0] isEqualToString:@"open"] && p.count == 2) MSBDOpen(p[1]);
    else if ([p[0] isEqualToString:@"set"] && p.count >= 3) MSBDSet([[p subarrayWithRange:NSMakeRange(1, p.count - 2)] componentsJoinedByString:@" "], [p.lastObject boolValue]);   // (ids may contain spaces)
    else if ([p[0] isEqualToString:@"tap"] && p.count >= 2) MSBDTap([[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@" "]);
    else if ([p[0] isEqualToString:@"alert"] && p.count >= 2) MSBDAlert([[p subarrayWithRange:NSMakeRange(1, p.count - 1)] componentsJoinedByString:@" "]);
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
