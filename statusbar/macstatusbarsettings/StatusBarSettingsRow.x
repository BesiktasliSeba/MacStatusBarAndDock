// MacStatusBarSettings — a "Status Bar" row in Settings' own main list, next to Dock Magnification and above
// Accessibility, so Mac Status Bar's settings look built in instead of hiding in the Tweaks folder.
//
// Loaded only into the Settings app. The usual PreferenceLoader entry would be moved into the Tweaks folder by
// Shuffle (it rebuilds the whole main list), so the row is added here instead, AFTER the list has been built:
// whenever the main list appears or reloads, insert our row unless it is already there. It goes in front of the
// Dock Magnification row when that exists (same trick, same anchor) and otherwise in front of Accessibility, so
// the order is Status Bar, Dock Magnification, Accessibility whichever tweak inserts first.
// The page itself is the MacStatusBarPrefs bundle; it is loaded here so its class exists when the row is tapped.
//
// The list's own row identifiers (found by dumping it on the device): ... HOME_SCREEN_DOCK, ACCESSIBILITY, Wallpaper ...

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../../common/LineSwitch.h"
#pragma clang diagnostic pop

#define kRowID        @"MAC_STATUS_BAR"
#define kDockRowID    @"DOCK_MAGNIFICATION"
#define kAnchorID     @"ACCESSIBILITY"
#define kBundlePath   @"/var/jb/Library/PreferenceBundles/MacStatusBarPrefs.bundle"
#define kPSLinkListCell 2
#define kPSLinkCell   1

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSString *name;
@end

@interface PSListController : UIViewController
- (NSArray *)specifiers;
- (void)reloadSpecifierID:(NSString *)identifier;
- (void)insertSpecifier:(PSSpecifier *)specifier atIndex:(NSInteger)index animated:(BOOL)animated;
- (void)removeSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
- (NSIndexPath *)indexPathForSpecifier:(PSSpecifier *)specifier;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end

static NSBundle *PrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleWithPath:kBundlePath];
        [bundle load];
    });
    return bundle;
}

// Where our rows go: right below General, in General's own block -- General, Status Bar, Dock, Control Center. Found by the rows' identifiers
// (ControlCenter, General), never by a fixed index, since other tweaks (Shuffle, PreferenceLoader) change the list. Status Bar goes in front of the
// Dock row when that is already there (both rows insert themselves, in whichever order); without Control Center and General, before Accessibility.
// No known row found (an iPadOS whose main list we have not seen: iPadOS 17 tester, 2026-09-26, got no rows at all, so not even Enable Anyway):
// the rows go near the top instead -- the start of the list's second block, below the Apple account -- so they always show, on any version.
static NSInteger TopIndex(NSArray *specs) {
    SEL cellType = NSSelectorFromString(@"cellType");
    for (NSUInteger i = 1; i < specs.count; i++)
        if ([specs[i] respondsToSelector:cellType] && ((long long (*)(id, SEL))objc_msgSend)(specs[i], cellType) == 0) return (NSInteger)i + 1;   // (0: PSGroupCell)
    return specs.count ? 1 : 0;
}
static NSInteger AnchorIndex(NSArray *specs, NSString *before, NSString *after) {
    NSInteger cc = NSNotFound, general = NSNotFound, accessibility = NSNotFound, own = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) {
        NSString *ident = [specs[i] identifier];
        if (![ident isKindOfClass:[NSString class]]) continue;
        if (before && [ident isEqualToString:before]) own = (NSInteger)i;
        if (after && [ident isEqualToString:after]) own = (NSInteger)i + 1;
        if (cc == NSNotFound && [ident caseInsensitiveCompare:@"ControlCenter"] == NSOrderedSame) cc = (NSInteger)i;
        if (general == NSNotFound && [ident caseInsensitiveCompare:@"General"] == NSOrderedSame) general = (NSInteger)i + 1;
        if (accessibility == NSNotFound && [ident caseInsensitiveCompare:kAnchorID] == NSOrderedSame) accessibility = (NSInteger)i;
    }
    if (own != NSNotFound) return own;
    if (cc != NSNotFound) return cc;
    if (general != NSNotFound) return general;
    return accessibility;
}


// Like Bluetooth's "On", the row shows whether its line (MacStatusBar in Choicy / iCleaner Pro, the switch at the top of its page) is on -- redrawn when
// the switch or Choicy changes it (2026-09-25).
@interface MSBStatusBarRowValue : NSObject
@end
@implementation MSBStatusBarRowValue
- (id)msbdLineValue:(id)specifier { return MSBDLineRuns(@"MacStatusBar") ? @"On" : @"Off"; }
@end
static MSBStatusBarRowValue *gRowValue;
static __weak PSListController *gRowList;
static void RefreshRowValue(void) {
    PSListController *l = gRowList;
    SEL r = NSSelectorFromString(@"reloadSpecifierID:");
    if (!l || ![l respondsToSelector:r]) return;
    for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:kRowID]) { ((void (*)(id, SEL, id))objc_msgSend)(l, r, kRowID); break; }
}
static void WatchRowValue(PSListController *list) {
    gRowList = list;
    static int t1 = 0, t2 = 0, t3 = 0;
    if (t1) return;
    void (^h)(int) = ^(int t) {
        RefreshRowValue();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ RefreshRowValue(); });   // (iCleaner Pro: the helper renames a moment later)
    };
    notify_register_dispatch("com.opa334.choicyprefs/ReloadPrefs", &t1, dispatch_get_main_queue(), h);
    notify_register_dispatch("com.besiktasliseba.lines.apply", &t2, dispatch_get_main_queue(), h);
    notify_register_dispatch(MSBD_UNTESTED_CHANGED, &t3, dispatch_get_main_queue(), h);   // ("Enable Anyway", "Turn Back On")
}

static void InsertRow(PSListController *list) {
    NSArray *specs = [list specifiers];
    WatchRowValue(list);
    for (NSUInteger i = 0; i < specs.count; i++) if ([[specs[i] identifier] isEqualToString:kRowID]) return;   // already there
    NSInteger anchor = AnchorIndex(specs, kDockRowID, nil);
    BOOL newOS = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17;   // (15/16: exactly as before)
    if (anchor == NSNotFound && newOS) anchor = TopIndex(specs);   // (only ever the main list: this runs from PSUIPrefsListController alone)
    Class detail = PrefsBundle() ? NSClassFromString(@"MSBRootListController") : Nil;   // the class only exists once the bundle is loaded
    if (anchor == NSNotFound || !PrefsBundle() || !detail) return;         // not the main list, or the page is missing

    if (!gRowValue) gRowValue = [MSBStatusBarRowValue new];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Status Bar" target:gRowValue set:NULL get:@selector(msbdLineValue:)
                                                      detail:detail cell:kPSLinkListCell edit:nil];
    row.identifier = kRowID;
    [row setProperty:kRowID forKey:@"id"];
    [row setProperty:@YES forKey:@"hasSelectionStyle"];
    UIImage *icon = [UIImage imageNamed:@"icon" inBundle:PrefsBundle() compatibleWithTraitCollection:nil];
    if (icon) [row setProperty:icon forKey:@"iconImage"];
    [list insertSpecifier:row atIndex:anchor animated:NO];
    if (newOS) {   // (the same page listed with the other tweaks by the postinst on 17+: hidden while our own row is there)
        for (PSSpecifier *sp in [[list specifiers] copy])
            if (![[sp identifier] isEqualToString:kRowID] && [[sp name] isEqualToString:@"Status Bar"] && [sp propertyForKey:@"isController"]) [list removeSpecifier:sp animated:NO];
    }
}

%hook PSUIPrefsListController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    InsertRow((PSListController *)self);
}
- (void)reloadSpecifiers {
    %orig;
    InsertRow((PSListController *)self);
}
%end

// The welcome alert's "Take Me There" (2026-09-25): SpringBoard opens Settings full screen and publishes the time of the request in a notify state;
// Settings then opens this page, once, the way a tap on the row does -- when it becomes active (a cold launch, or back from the background) or, when
// it is active already, on the notification. A request older than 20 s is ignored. (Our page is a row added to the main list, not a PreferenceLoader
// entry, so a prefs:root= link cannot be relied on to find it.) Nothing else sets the state: otherwise one notify read per activation of Settings.
// The state's high 32 bits name a place on the page (0 the page itself, 1 Go Menu > Apps: the Go menu's "Edit Go Menu…"); the low 32 bits the time.
#define kOpenPageState "com.besiktasliseba.macstatusbaranddock.openstatusbarpage"
static BOOL ShowsPage(UIViewController *vc, Class page) {
    if (!vc || !page) return NO;
    if ([vc isKindOfClass:page]) return YES;
    for (UIViewController *c in vc.childViewControllers) if (ShowsPage(c, page)) return YES;
    return NO;
}
static UIViewController *FindController(UIViewController *vc, Class c) {
    if (!vc || !c) return nil;
    if ([vc isKindOfClass:c]) return vc;
    for (UIViewController *child in vc.childViewControllers) { UIViewController *f = FindController(child, c); if (f) return f; }
    return nil;
}
static void SBRowLog(NSString *line) {
#if DEBUG
    FILE *f = fopen("/tmp/msbd-settings.log", "a");
    if (f) { fprintf(f, "%.3f [sbrow] %s\n", CFAbsoluteTimeGetCurrent(), line.UTF8String); fclose(f); }
#else
    (void)line;
#endif
}
static NSString *StackText(UINavigationController *nav) {
    NSMutableArray *names = [NSMutableArray array];
    for (UIViewController *vc in nav.viewControllers) [names addObject:NSStringFromClass([vc class])];
    return [names componentsJoinedByString:@" > "];
}
// YES when Go Menu > Apps is on the stack: shown (the page under it popped to when needed), and only once (a second copy is taken out)
static BOOL DedupeGoApps(UINavigationController *nav) {
    Class c = NSClassFromString(@"MSBGoAppsController");
    NSArray<UIViewController *> *vcs = nav.viewControllers;
    UIViewController *first = nil; NSMutableArray *kept = [NSMutableArray array];
    for (UIViewController *vc in vcs) {
        if ([vc isKindOfClass:c]) { if (first) continue; first = vc; }
        [kept addObject:vc];
    }
    SBRowLog([NSString stringWithFormat:@"go apps check: %@", StackText(nav)]);
    if (!first) return NO;
    if (kept.count != vcs.count) { SBRowLog(@"a second Go Apps page taken out"); [nav setViewControllers:kept animated:NO]; }
    if (nav.topViewController != first) [nav popToViewController:first animated:NO];
    return YES;
}
// Go Menu > Apps: once the page is up, its Apps row is opened the way a tap does (its list is pushed on the page's navigation stack)
static void OpenGoApps(int attempt) {
    PSListController *list = gRowList;
    UIViewController *top = list.splitViewController ?: list.navigationController;
    PSListController *page = (PSListController *)FindController(top, NSClassFromString(@"MSBRootListController"));
    UINavigationController *nav = page.navigationController;
    PSSpecifier *row = nil;
    for (PSSpecifier *sp in [page specifiers]) if ([[sp identifier] isEqualToString:@"GO_APPS"]) { row = sp; break; }
    NSIndexPath *ip = row ? [page indexPathForSpecifier:row] : nil;
    UITableView *t = nil; @try { t = [page valueForKey:@"table"]; } @catch (NSException *e) {}
    if (!page.view.window || !ip || ![t isKindOfClass:[UITableView class]]) {   // (the page is still being pushed)
        if (attempt < 16) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenGoApps(attempt + 1); });
        return;
    }
    if (DedupeGoApps(nav)) return;   // (already there)
    if (nav.topViewController != page) [nav popToViewController:page animated:NO];
    [t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [page tableView:t didSelectRowAtIndexPath:ip];
    // a cold launch: Settings may still put back the page it showed last (Go Menu > Apps too), on top of ours -- two Apps pages, and the first
    // Back only led to the other one. Looked at for 5 s.
    SBRowLog([NSString stringWithFormat:@"go apps opened: %@", StackText(nav)]);
    for (double at = 0.5; at <= 5.0; at += 0.5) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DedupeGoApps(nav); });
}
static void OpenPage(int attempt, uint32_t target) {
    PSListController *list = gRowList;
    PSSpecifier *row = nil;
    for (PSSpecifier *sp in [list specifiers]) if ([[sp identifier] isEqualToString:kRowID]) { row = sp; break; }
    NSIndexPath *ip = row ? [list indexPathForSpecifier:row] : nil;
    UITableView *t = nil; @try { t = [list valueForKey:@"table"]; } @catch (NSException *e) {}
    if (!ip || ![t isKindOfClass:[UITableView class]]) {   // (a cold launch: the main list may not be built yet)
        if (attempt < 12) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenPage(attempt + 1, target); });
        return;
    }
    UIViewController *top = list.splitViewController ?: list.navigationController;
    if (!ShowsPage(top, NSClassFromString(@"MSBRootListController"))) {
        [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionMiddle];
        [list tableView:t didSelectRowAtIndexPath:ip];
    } else if (target != 1) return;   // (already there)
    if (target == 1) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenGoApps(0); });
    // Settings may put back the page it last showed right after launching: checked once more a moment later
    if (attempt < 100) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenPage(100, target); });
}
static void CheckOpenPageRequest(void) {
    static int token = 0; static uint64_t handled = 0;
    if (!token && notify_register_check(kOpenPageState, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    uint64_t v = 0; notify_get_state(token, &v);
    uint64_t now = (uint64_t)time(NULL), at = v & 0xffffffffULL;
    uint32_t target = (uint32_t)(v >> 32);
    if (!v || v == handled || at > now + 5 || now > at + 20) return;
    handled = v;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenPage(0, target); });
}

%ctor {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { CheckOpenPageRequest(); }];
    int t = 0;
    notify_register_dispatch(kOpenPageState, &t, dispatch_get_main_queue(), ^(int tok) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) CheckOpenPageRequest();
    });
}
