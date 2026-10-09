// Mac Settings (inside the Settings app):
//  1. no large "Settings" title and no bar that fades in when the sidebar is scrolled (macOS System Settings has neither);
//  2. no alert banners (iCloud storage, Software Update) on top of the sidebar;
//  3. Accessibility and everything below it in a section of its own;
//  4. an SSH switch between Bluetooth and VPN that turns OpenSSH on and off (the root helper sshtoggled does the actual work).
//
// Other tweaks change this same list (Shuffle reorders and removes rows, PreferenceLoader and QuickPrefs add rows, this and that insert rows at fixed
// positions), so everything here is defensive: rows are added or dropped in the specifier array at the moment it is handed out, before the table
// sees it, nothing is looked up by a fixed index, and no table callbacks are hooked (those crashed Settings when other tweaks changed rows).
#import <UIKit/UIKit.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <dlfcn.h>

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end
@interface PSListController : UIViewController @end
@interface PSUIPrefsListController : PSListController @end
// PointerSettings.x: the "Pointer" row (only while a trackpad or mouse is attached) and its page
BOOL MSPointerDeviceAttached(void);
PSSpecifier *MSPointerRowSpecifier(id target);
void MSPointerWatchSidebar(PSListController *sidebar);
// KeyboardSettings.x: the "Keyboard" row (only while a hardware keyboard is attached) and its page
BOOL MSKeyboardAttached(void);
PSSpecifier *MSKeyboardRowSpecifier(id target);
void MSKeyboardWatchSidebar(PSListController *sidebar);
// Home Bar (HomeBar.x, SpringBoard): whether this device has a home bar (pill) at all -- 0 not known yet, 1 none (a Home-button iPad with no
// gesture tweak drawing one), 2 yes. Where there is no pill the switch would do nothing, so the row is left out.
static uint64_t HBPillState(void) {
    static int token = 0;
    if (!token) notify_register_check("com.besiktasliseba.machomebar.pill", &token);
    uint64_t v = 0; notify_get_state(token, &v);
    return v;
}

#define kStateFile "/var/jb/var/lib/sshtoggled-engines/ssh-state"   // (root-owned since the hardening; the old file below is the fallback)
#define kStateFileOld "/var/jb/var/mobile/.sshtoggle-state"
#define kSwitchID @"SSH_TOGGLE"
#define kHomeBarSwitchID @"HOMEBAR_TOGGLE"
#define kAccessibilityGroupID @"MAC_SETTINGS_ACCESSIBILITY_GROUP"
#define HB_DOMAIN CFSTR("com.besiktasliseba.machomebar")

static void MLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "%s\n", line.UTF8String); fclose(f);
#endif
}

// ---- SSH ----
static BOOL SSHOn(void) {
    FILE *f = fopen(kStateFile, "r");
    if (!f) f = fopen(kStateFileOld, "r");
    if (!f) return YES;   // the helper has not written its state yet: OpenSSH is on unless it has been switched off
    int c = fgetc(f); fclose(f);
    return c != '0';
}
// A 29 pt rounded square with a terminal glyph, like the icons of the other Settings rows.
static UIImage *SSHIcon(void) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithWhite:0.32 alpha:1.0] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:6.5] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage *glyph = [[UIImage systemImageNamed:@"terminal.fill" withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (glyph) [glyph drawInRect:CGRectMake((29 - glyph.size.width) / 2.0, (29 - glyph.size.height) / 2.0, glyph.size.width, glyph.size.height)];
    }];
}
// Same shape, a home-indicator-like glyph, for the Home Bar row.
static UIImage *HomeBarIcon(void) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithWhite:0.32 alpha:1.0] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 29, 29) cornerRadius:6.5] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage *glyph = [[UIImage systemImageNamed:@"rectangle.bottomthird.inset.filled" withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (glyph) [glyph drawInRect:CGRectMake((29 - glyph.size.width) / 2.0, (29 - glyph.size.height) / 2.0, glyph.size.width, glyph.size.height)];
    }];
}
// "Home Bar" reads as "is it showing" — OFF (the default) means hidden, matching Trim's own default and the owner's current setup.
static BOOL HomeBarOn(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("showHomeBar"), HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : NO;
    CFRelease(v);
    return on;
}

// ---- the alert banners ("follow-ups") ----
static BOOL IsFollowUp(id spec) { return [[spec identifier] hasPrefix:@"FollowUp"]; }
static NSArray *WithoutFollowUps(NSArray *specs) {
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:specs.count];
    for (id sp in specs) if (!IsFollowUp(sp)) [kept addObject:sp];
    return kept.count == specs.count ? specs : kept;
}

static void NoteFollowUps(NSArray *specs, NSString *how) {   // (debug log: which way an alert banner came)
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    NSUInteger n = 0; for (id sp in specs) if (IsFollowUp(sp)) n++;
    if (n) MLog([NSString stringWithFormat:@"alert banners (%lu) arrived via %@: left out", (unsigned long)n, how]);
}
// The Status Bar and Dock rows (Mac Status Bar, Mac Dock) add themselves "just before Accessibility", after the section marker put there, which would pull
// them into the new section. Only those two rows are inserted in front of the marker instead. (Nothing else is touched: other tweaks insert whole
// groups here, and moving those puts the table's section count out of step.) The list is read from a copy kept when it was handed out, not asked
// for again, because asking for it in the middle of a table update is what crashed Settings before.
static const void *kSpecsKey = &kSpecsKey;
static NSInteger AdjustedIndex(id controller, NSArray *insertedSpecs, NSInteger index) {
    if (!insertedSpecs.count) return index;
    for (id sp in insertedSpecs) { NSString *i = [sp identifier]; if (![i isEqualToString:@"MAC_STATUS_BAR"] && ![i isEqualToString:@"DOCK_MAGNIFICATION"]) return index; }
    NSArray *all = objc_getAssociatedObject(controller, kSpecsKey);
    NSInteger group = NSNotFound, accessibility = NSNotFound;
    for (NSUInteger i = 0; i < all.count; i++) {
        NSString *ident = [all[i] identifier];
        if ([ident isEqualToString:kAccessibilityGroupID]) group = i;
        else if (group != NSNotFound && accessibility == NSNotFound && [ident caseInsensitiveCompare:@"ACCESSIBILITY"] == NSOrderedSame) accessibility = i;
    }
    if (group != NSNotFound && accessibility != NSNotFound && index > group && index <= accessibility) return group;
    return index;
}

// The Settings sidebar is a column of a split view. With a wide window it stays on screen next to the detail pane, so its bar can go; in a narrow
// (collapsed) window the same navigation controller also pushes the detail pages and its bar holds the Back button, so it stays.
// (SidebarSearch.x shows its search field exactly where this hides the bar: Apple's own search field lives in that bar.)
void MSSearchSidebarChanged(UIViewController *list);
static const void *kBarCanGoKey = &kBarCanGoKey;   // (what the rule said when last applied, while the sidebar is shown)
BOOL MSSidebarBarCanGo(UIViewController *vc) {
    UISplitViewController *split = vc.splitViewController;
    return split && !split.isCollapsed && vc.navigationController.viewControllers.firstObject == vc;
}

// Settings opened straight onto a page (a prefs: link, e.g. Display & Brightness) builds the sidebar table while the system is still inserting its
// Ethernet and VPN rows; with our own rows (SSH, Home Bar, Pointer) in the list the table's rows then drift from the list itself: one row shown twice
// (two "Ethernet"), another missing (Pointer). After any such insert the sidebar table is simply redrawn from the list once things settle.
static void MSResyncSidebar(id controller) {
    static char kPending;
    if ([objc_getAssociatedObject(controller, &kPending) boolValue]) return;
    objc_setAssociatedObject(controller, &kPending, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weak = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id c = weak; if (!c) return;
        objc_setAssociatedObject(c, &kPending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITableView *t = nil; @try { t = [c valueForKey:@"table"]; } @catch (NSException *e) {}
        if (![t isKindOfClass:[UITableView class]]) return;
        // The highlighted row goes with a redraw (iPad 2: Settings opened full screen onto a page showed no row selected in the sidebar). In a
        // side-by-side layout it is put back: the row that was selected, or else the row of the page shown next to the sidebar.
        UISplitViewController *split = ((UIViewController *)c).splitViewController;
        BOOL sideBySide = split && !split.isCollapsed;
        id selSpec = nil;
        if (sideBySide) {
            NSIndexPath *selIP = t.indexPathForSelectedRow;
            UITableViewCell *cell = selIP ? [t cellForRowAtIndexPath:selIP] : nil;
            if (cell) { @try { selSpec = [cell valueForKey:@"specifier"]; } @catch (NSException *e) { selSpec = nil; } }
            if (!selSpec && split.viewControllers.count > 1) {
                UIViewController *detail = split.viewControllers.lastObject;
                if ([detail isKindOfClass:[UINavigationController class]]) detail = ((UINavigationController *)detail).viewControllers.firstObject;
                id shown = [detail respondsToSelector:@selector(specifier)] ? ((id (*)(id, SEL))objc_msgSend)(detail, @selector(specifier)) : nil;
                NSString *ident = [shown respondsToSelector:@selector(identifier)] ? [shown identifier] : nil;
                if (ident.length && [c respondsToSelector:@selector(specifierForID:)]) selSpec = ((id (*)(id, SEL, id))objc_msgSend)(c, @selector(specifierForID:), ident);
            }
        }
        [t reloadData];
        NSIndexPath *ip = selSpec && [c respondsToSelector:@selector(indexPathForSpecifier:)] ? ((id (*)(id, SEL, id))objc_msgSend)(c, @selector(indexPathForSpecifier:), selSpec) : nil;
        if ([ip isKindOfClass:[NSIndexPath class]] && ip.section < t.numberOfSections && ip.row < [t numberOfRowsInSection:ip.section]) [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
        MLog([NSString stringWithFormat:@"sidebar table redrawn after a system insert%@", ip ? [NSString stringWithFormat:@" (row %@ kept selected)", [selSpec identifier]] : @""]);
    });
}
%hook PSUIPrefsListController
- (NSMutableArray *)specifiers {
    NSMutableArray *specs = %orig;
    if (![specs isKindOfClass:[NSMutableArray class]]) return specs;
    static const void *kPreparedKey = &kPreparedKey;   // (a marker on the list itself: with no SSH and no Home Bar row there is no row to recognise it by)
    if (objc_getAssociatedObject(specs, kPreparedKey)) return specs;
    for (id s in specs) if ([[s identifier] isEqualToString:kSwitchID] || [[s identifier] isEqualToString:kHomeBarSwitchID]) return specs;   // already done for this list
    objc_setAssociatedObject(specs, kPreparedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Alert banners already in a freshly built list (they normally come a moment later through the insert methods below, which drop them). Taken out
    // here only, while the list is new and before any table shows it -- never from a list a table is using.
    NSArray *noFollowUps = WithoutFollowUps(specs);
    if (noFollowUps != specs) { MLog([NSString stringWithFormat:@"alert banners left out of the new list: %lu", (unsigned long)(specs.count - noFollowUps.count)]); [specs setArray:noFollowUps]; }
    NSUInteger bluetooth = NSNotFound, accessibility = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) {
        NSString *ident = [specs[i] identifier];
        if (bluetooth == NSNotFound && [ident caseInsensitiveCompare:@"BLUETOOTH"] == NSOrderedSame) bluetooth = i;   // the first one: some lists have another row with that name further down
        if (accessibility == NSNotFound && [ident caseInsensitiveCompare:@"ACCESSIBILITY"] == NSOrderedSame) accessibility = i;
    }
    // Accessibility and below: a section of its own (inserted first, it is further down, so the index of Bluetooth stays valid)
    if (accessibility != NSNotFound && accessibility > 0) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
        [group setIdentifier:kAccessibilityGroupID];
        [specs insertObject:group atIndex:accessibility];
    }
    if (bluetooth != NSNotFound) {
        // A normal row of the same block as Bluetooth and VPN, between the two -- only when OpenSSH is actually installed (requested: with no SSH on
        // the device the row should not be there at all; it used to be shown greyed out). openssh-server is no longer a hard Depends either.
        BOOL sshInstalled = access("/var/jb/usr/sbin/sshd", F_OK) == 0;
        NSUInteger next = bluetooth + 1;
        if (sshInstalled) {
            PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:@"SSH" target:self set:@selector(dm_setSSH:specifier:) get:@selector(dm_sshEnabled:) detail:nil cell:6 edit:nil];   // 6 = a switch cell
            [sw setIdentifier:kSwitchID];
            [sw setProperty:SSHIcon() forKey:@"iconImage"];
            [specs insertObject:sw atIndex:next++];
        }
        // Home Bar, right after SSH: OFF (the default) hides the home indicator pill everywhere (Home Screen and every app), the swipe
        // gesture itself untouched; ON shows it normally, like a stock, untweaked device.
        // Only where a home bar exists (a device with no pill, like a Home-button iPad without a gesture tweak, has nothing to switch).
        if (HBPillState() != 1) {
            PSSpecifier *hb = [PSSpecifier preferenceSpecifierNamed:@"Home Bar" target:self set:@selector(dm_setHomeBar:specifier:) get:@selector(dm_homeBarEnabled:) detail:nil cell:6 edit:nil];
            [hb setIdentifier:kHomeBarSwitchID];
            [hb setProperty:HomeBarIcon() forKey:@"iconImage"];
            [specs insertObject:hb atIndex:next++];
        }
        if (MSPointerDeviceAttached()) [specs insertObject:MSPointerRowSpecifier(self) atIndex:next++];   // Pointer: only with a trackpad or mouse
        if (MSKeyboardAttached()) [specs insertObject:MSKeyboardRowSpecifier(self) atIndex:next];   // Keyboard: only with a hardware keyboard
    }
    objc_setAssociatedObject(self, kSpecsKey, specs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MLog([NSString stringWithFormat:@"list prepared: bluetooth %ld accessibility %ld, home bar pill state %llu, pointer %d", (long)bluetooth, (long)accessibility, HBPillState(), MSPointerDeviceAttached()]);
    if (MSTestFlag("/tmp/macsettings-debug")) { NSMutableString *ids = [NSMutableString string]; for (id sp in specs) [ids appendFormat:@" %@", [sp identifier]]; MLog([@"list ids:" stringByAppendingString:ids]); }
    return specs;
}
// Bug (reported): the SSH row does read the live state fresh every time (dm_sshEnabled: opens the state file, not a cached value), but a PSSwitch cell
// only calls that getter when its row is built or the list reloads, not continuously -- so turning SSH off from Mac Status Bar's own icon menu while
// this list is already open left the switch showing stale (still on) until Settings was relaunched. Mac Status Bar's SSH menu posts the very same
// Darwin notifications sshtoggled itself listens for (com.besiktasliseba.sshtoggle.enable/disable, see DMOpenSSHMenu in its Tweak.x), so listening for those
// here and asking the list to redraw just that one row keeps the switch in step with whatever changed it, no relaunch needed. Read-only/UI-refresh
// only: no alloc/init of a private class, `reloadSpecifier:`/`specifierForID:` are called on a list controller the OS already created and is
// already showing, the same category as every other call in this file.
static __weak PSListController *gVisibleSSHList = nil;
static void DMRefreshSSHRow(void) {
    PSListController *vc = gVisibleSSHList;
    SEL specForID = NSSelectorFromString(@"specifierForID:"), reload = NSSelectorFromString(@"reloadSpecifier:");
    if (!vc || ![vc respondsToSelector:specForID] || ![vc respondsToSelector:reload]) return;
    id spec = ((id (*)(id, SEL, id))objc_msgSend)(vc, specForID, kSwitchID);
    if (spec) { ((void (*)(id, SEL, id))objc_msgSend)(vc, reload, spec); MLog(@"SSH row refreshed from an outside change"); }
}
static void DMRefreshSSHRowWhenDone(void) {
    static int generation = 0;
    int mine = ++generation;
    BOOL before = SSHOn();
    for (int i = 1; i <= 16; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            static int doneFor = 0;
            if (mine != generation || doneFor == mine) return;   // (a newer request took over, or this one is finished)
            if (SSHOn() != before || i == 16) { doneFor = mine; DMRefreshSSHRow(); }
        });
    }
}
static void DMRegisterSSHSync(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    static int tokenOn = 0, tokenOff = 0;
    // Keyboard Phase (iPad 2): switching SSH ON in this row turned SSH on, but the switch jumped back to off (not green). The request and
    // this refresh happen at the same moment, and the helper (sshtoggled) writes the new state a little later -- the row was redrawn from the OLD
    // state. Now the row waits for the helper: the state file is read every 0.25 s for up to 4 s and the row is redrawn once it has changed (and
    // once more at the end, so it always shows the real state even if the helper failed).
    notify_register_dispatch("com.besiktasliseba.sshtoggle.enable", &tokenOn, dispatch_get_main_queue(), ^(int t) { DMRefreshSSHRowWhenDone(); });
    notify_register_dispatch("com.besiktasliseba.sshtoggle.disable", &tokenOff, dispatch_get_main_queue(), ^(int t) { DMRefreshSSHRowWhenDone(); });
    static int tokenChanged = 0;
    notify_register_dispatch("com.besiktasliseba.sshtoggle.changed", &tokenChanged, dispatch_get_main_queue(), ^(int t) { DMRefreshSSHRowWhenDone(); });
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    NSArray *builtSpecs = objc_getAssociatedObject(self, kSpecsKey);
    for (id s in builtSpecs) if ([[s identifier] isEqualToString:kSwitchID]) { gVisibleSSHList = (PSListController *)self; DMRegisterSSHSync(); break; }
    if (builtSpecs) { MSPointerWatchSidebar((PSListController *)self); MSKeyboardWatchSidebar((PSListController *)self); }
    if (MSSidebarBarCanGo(vc)) [vc.navigationController setNavigationBarHidden:YES animated:NO];
    objc_setAssociatedObject(self, kBarCanGoKey, @(MSSidebarBarCanGo(vc)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MSSearchSidebarChanged(vc);   // (the search field where the bar was)
    // Reported bug (predates any of our own tweaks): on a cold launch, the sidebar sometimes opens already scrolled part way down,
    // cutting a row in half at the very top instead of starting at Wi-Fi/Bluetooth. Looks like a restored scroll offset from an earlier
    // session that no longer lines up with the current row layout (Shuffle reorders/adds rows, which would explain why an old raw pixel
    // offset stops landing on the same row) — not something to chase inside a private, third-party tweak's own code. Forced back to the
    // top once, the first time the sidebar appears each launch, regardless of the actual cause.
    static BOOL fixedThisLaunch = NO;
    if (!fixedThisLaunch) {
        fixedThisLaunch = YES;
        __weak UIViewController *weakVC = vc;
        // A single correction right here was not enough: it ran and found the stale offset (confirmed in the log), but something else —
        // almost certainly Settings' own state restoration, which typically finishes its work a moment AFTER -viewWillAppear:, in or after
        // -viewDidAppear: — put it right back afterward, so the screenshot still showed it cut off. Re-asserted a few times over the next
        // half second instead of once, so it wins that race regardless of exactly when the other side finishes.
        void (^correct)(void) = ^{
            UIViewController *strongVC = weakVC;
            if (!strongVC) return;
            UIScrollView *scroll = nil;
            for (NSString *key in @[@"tableView", @"table", @"_tableView", @"_table"]) {
                @try { id v = [strongVC valueForKey:key]; if ([v isKindOfClass:[UIScrollView class]]) { scroll = v; break; } } @catch (NSException *e) {}
            }
            if (scroll && scroll.contentOffset.y > 4.0) {
                MLog([NSString stringWithFormat:@"sidebar scrolled to y=%.0f, forcing back to the top", scroll.contentOffset.y]);
                [scroll setContentOffset:CGPointMake(0, -scroll.adjustedContentInset.top) animated:NO];
            }
        };
        correct();
        for (NSNumber *delay in @[@0.05, @0.15, @0.3, @0.6]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), correct);
        }
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    if (vc.navigationController.isNavigationBarHidden) [vc.navigationController setNavigationBarHidden:NO animated:NO];
    objc_setAssociatedObject(self, kBarCanGoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MSSearchSidebarChanged(vc);   // (the bar is back, with Apple's own field: ours goes)
}
// The window changing size while the sidebar is shown (a Stage Manager window or Split View made narrower or wider): the sidebar collapses into the
// page or comes out of it without appearing again, so the rule above is applied once more when that changes -- before, a narrow window made wide
// again kept its bar ("Settings" title, no search field) next to the page.
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *vc = (UIViewController *)self;
    NSNumber *before = objc_getAssociatedObject(self, kBarCanGoKey);
    if (!before || !vc.view.window) return;   // (not shown: -viewWillAppear: decides)
    BOOL can = MSSidebarBarCanGo(vc);
    if (before.boolValue == can) return;
    objc_setAssociatedObject(self, kBarCanGoKey, @(can), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (vc.navigationController.isNavigationBarHidden != can) [vc.navigationController setNavigationBarHidden:can animated:NO];
    MLog([NSString stringWithFormat:@"sidebar %@ the page: bar %@", can ? @"beside" : @"collapsed into", can ? @"hidden" : @"shown"]);
    MSSearchSidebarChanged(vc);
}
- (void)insertContiguousSpecifiers:(NSArray *)specs atIndex:(NSInteger)index animated:(BOOL)animated {
    if (MSTestFlag("/tmp/macsettings-debug")) { Dl_info di; const char *img = dladdr(__builtin_return_address(0), &di) ? di.dli_fname : "?"; NSMutableString *ids = [NSMutableString string]; for (id sp in specs) [ids appendFormat:@" %@", [sp identifier]]; MLog([NSString stringWithFormat:@"insert contiguous%@ at %ld from %s", ids, (long)index, img]); }
    NSArray *kept = WithoutFollowUps(specs);
    NSInteger at = AdjustedIndex(self, kept, index);
    %orig(kept, at, animated);
    MSResyncSidebar(self);
}
- (void)insertContiguousSpecifiers:(NSArray *)specs afterSpecifierID:(NSString *)ident animated:(BOOL)animated {
    NSArray *kept = WithoutFollowUps(specs);
    %orig(kept, ident, animated);
}
- (void)insertSpecifier:(id)spec atIndex:(NSInteger)index animated:(BOOL)animated {
    if (MSTestFlag("/tmp/macsettings-debug")) { Dl_info di; const char *img = dladdr(__builtin_return_address(0), &di) ? di.dli_fname : "?"; MLog([NSString stringWithFormat:@"insert %@ at %ld from %s", [spec identifier], (long)index, img]); }
    if (IsFollowUp(spec)) return;
    index = AdjustedIndex(self, spec ? @[spec] : nil, index);
    // Settings puts VPN "right after Bluetooth" a moment after the list is built, which would land it in front of the SSH row: it goes after it.
    if ([[spec identifier] isEqualToString:@"VPN"]) {
        NSArray *all = ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"specifiers"));
        for (NSUInteger i = 0; i < all.count; i++)
            if ([[all[i] identifier] isEqualToString:kSwitchID]) { if ((NSUInteger)index <= i) index = i + 1; break; }
    }
    %orig(spec, index, animated);
    MSResyncSidebar(self);
}
- (void)insertSpecifier:(id)spec afterSpecifierID:(NSString *)ident animated:(BOOL)animated {
    if (MSTestFlag("/tmp/macsettings-debug")) { Dl_info di; const char *img = dladdr(__builtin_return_address(0), &di) ? di.dli_fname : "?"; MLog([NSString stringWithFormat:@"insert %@ after %@ from %s", [spec identifier], ident, img]); }
    if (IsFollowUp(spec)) return;
    %orig;
}
// The other ways a list can be handed rows (iPad 2 / iOS 16: the alert banners still showed although the inserts above drop them). Each one drops
// the banners before Settings sees them, the same safe way: only the rows passed in are filtered, the live list is never edited. Debug builds log
// which way a banner came (/tmp/macsettings-debug), and whether one is in the list afterwards.
- (void)setSpecifiers:(NSArray *)specs {
    NoteFollowUps(specs, @"setSpecifiers");
    NSArray *kept = [specs isKindOfClass:[NSArray class]] ? WithoutFollowUps(specs) : specs;
    %orig(kept != specs && [specs isKindOfClass:[NSMutableArray class]] ? [kept mutableCopy] : kept);
}
- (void)addSpecifier:(id)spec animated:(BOOL)animated {
    if (IsFollowUp(spec)) { NoteFollowUps(@[spec], @"addSpecifier"); return; }
    %orig;
}
- (void)addSpecifiersFromArray:(NSArray *)specs animated:(BOOL)animated {
    NoteFollowUps(specs, @"addSpecifiersFromArray");
    NSArray *kept = WithoutFollowUps(specs);
    if (!kept.count && specs.count) return;
    %orig(kept, animated);
}
- (void)insertSpecifier:(id)spec afterSpecifier:(id)after animated:(BOOL)animated {
    if (IsFollowUp(spec)) { NoteFollowUps(@[spec], @"insertSpecifier:afterSpecifier"); return; }
    %orig;
}
- (void)insertSpecifier:(id)spec atEndOfGroup:(NSInteger)group animated:(BOOL)animated {
    if (IsFollowUp(spec)) { NoteFollowUps(@[spec], @"insertSpecifier:atEndOfGroup"); return; }
    %orig;
}
- (void)insertContiguousSpecifiers:(NSArray *)specs afterSpecifier:(id)after animated:(BOOL)animated {
    NoteFollowUps(specs, @"insertContiguousSpecifiers:afterSpecifier");
    NSArray *kept = WithoutFollowUps(specs);
    if (!kept.count && specs.count) return;
    %orig(kept, after, animated);
}
- (void)insertContiguousSpecifiers:(NSArray *)specs atEndOfGroup:(NSInteger)group animated:(BOOL)animated {
    NoteFollowUps(specs, @"insertContiguousSpecifiers:atEndOfGroup");
    NSArray *kept = WithoutFollowUps(specs);
    if (!kept.count && specs.count) return;
    %orig(kept, group, animated);
}
// A replace of banners (Settings refreshing them): the old ones were never let in, so with nothing of ours to replace nothing is done; new banners
// among the replacements are left out.
- (void)replaceContiguousSpecifiers:(NSArray *)old withSpecifiers:(NSArray *)specs animated:(BOOL)animated {
    NoteFollowUps(specs, [NSString stringWithFormat:@"replaceContiguousSpecifiers (replacing %lu rows, %lu of them not banners)", (unsigned long)old.count, (unsigned long)WithoutFollowUps(old).count]);
    NSArray *oldKept = WithoutFollowUps(old), *kept = WithoutFollowUps(specs);
    if (oldKept == old && kept == specs) {
        %orig(old, specs, animated);
        return;
    }
    if (!oldKept.count) { if (kept.count) MLog(@"alert banner replace with other rows skipped (nothing of it is in the list)"); return; }
    %orig(oldKept, kept, animated);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    NSArray *all = ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"specifiers"));
    NSUInteger n = 0; for (id sp in all) if (IsFollowUp(sp)) n++;
    MLog([NSString stringWithFormat:@"main list shown: %lu rows, alert banners in it: %lu", (unsigned long)all.count, (unsigned long)n]);
}
%new
- (id)dm_sshEnabled:(id)specifier { return @(SSHOn()); }
%new
- (void)dm_setSSH:(id)value specifier:(id)specifier {
    BOOL on = [value boolValue];
    // Hardening: the wanted state goes into our own preference FIRST; the helper reads it (a notification alone can no longer switch SSH).
    CFPreferencesSetValue(CFSTR("sshWanted"), on ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("com.besiktasliseba.macsettings"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.besiktasliseba.macsettings"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post("com.besiktasliseba.sshtoggle.changed");
    MLog([NSString stringWithFormat:@"SSH switched %@", on ? @"on" : @"off"]);
}
%new
- (id)dm_homeBarEnabled:(id)specifier { return @(HomeBarOn()); }
%new
- (void)dm_setHomeBar:(id)value specifier:(id)specifier {
    BOOL on = [value boolValue];
    CFPreferencesSetValue(CFSTR("showHomeBar"), on ? kCFBooleanTrue : kCFBooleanFalse, HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(HB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post("com.besiktasliseba.machomebar/changed");   // (every running app and SpringBoard re-ask their view controllers at once: HomeBar.x)
    MLog([NSString stringWithFormat:@"Home Bar switched %@", on ? @"on" : @"off"]);
}
%end
