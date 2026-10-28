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
#import <unistd.h>
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../../common/LineSwitch.h"
#pragma clang diagnostic pop
#import "../../common/AppleMultitasking.h"   // (1.6.0: Apple's multitasking settings on the Windows & Multitasking page)
#import <mach-o/dyld.h>
#include <stdatomic.h>
#import "../../common/General18Group.h"
#import "../../common/SettingsRoot.h"
#import "../../common/SidebarScroll.h"   // (a page opened at launch keeps its row on screen in the sidebar)

#define kRowID        @"MAC_STATUS_BAR"
#define kWindowsRowID @"MAC_WINDOWS"   // (1.6.0: the Windows & Multitasking page, right after Status Bar -- the same bundle, MSBWindowsListController)
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
static __weak PSListController *gRowList;   // (the list our row is in: Settings' main list; on iPadOS 18 General's page)
static NSString *gRowID = kRowID;           // (our row's identifier there: on iPadOS 18 PreferenceLoader's, kPLRowID -- common/General18Group.h)
static void RefreshRowValue(void) {
    PSListController *l = gRowList;
    SEL r = NSSelectorFromString(@"reloadSpecifierID:");
    if (!l || ![l respondsToSelector:r]) return;
    for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:gRowID]) { ((void (*)(id, SEL, id))objc_msgSend)(l, r, gRowID); break; }
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

static PSSpecifier *MakeRow(Class detail, NSString *ident) {
    if (!gRowValue) gRowValue = [MSBStatusBarRowValue new];
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Status Bar" target:gRowValue set:NULL get:@selector(msbdLineValue:)
                                                      detail:detail cell:kPSLinkListCell edit:nil];
    row.identifier = ident;
    [row setProperty:ident forKey:@"id"];
    [row setProperty:@YES forKey:@"hasSelectionStyle"];
    UIImage *icon = [UIImage imageNamed:@"icon" inBundle:PrefsBundle() compatibleWithTraitCollection:nil];
    if (icon) [row setProperty:icon forKey:@"iconImage"];
    return row;
}
// The Windows & Multitasking row (1.6.0, KT: the window settings out of the Status Bar page): between Status Bar and Dock, a plain link to its page.
static PSSpecifier *MakeWindowsRow(Class detail) {
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:@"Windows & Multitasking" target:nil set:NULL get:NULL detail:detail cell:kPSLinkCell edit:nil];
    row.identifier = kWindowsRowID;
    [row setProperty:kWindowsRowID forKey:@"id"];
    [row setProperty:@YES forKey:@"hasSelectionStyle"];
    UIImage *icon = [UIImage imageNamed:@"windows" inBundle:PrefsBundle() compatibleWithTraitCollection:nil];
    if (icon) [row setProperty:icon forKey:@"iconImage"];
    return row;
}
// Whether the Windows & Multitasking row is in Settings' list (15-17: it went into the main list; 18: General's group is in use, so it goes in with
// General's list). The Status Bar page asks (dlsym: MSBRootListController.m MSBWindowsRowListed): where it is not, that page links to the new page.
static BOOL gWindowsRowListed = NO;
__attribute__((visibility("default"))) BOOL MSBDWindowsRowListed(void) {
#if DEBUG
    if (access("/tmp/msb-nowinrow", F_OK) == 0) return NO;   // (debug: the Status Bar page as if the row were not listed -- its link to the page)
#endif
    return gWindowsRowListed;
}
// Apple's row of that identifier in Settings' main list (15-17; nil on 18, whose root list is SwiftUI, or where it is not there): our Windows &
// Multitasking page's row that opens Apple's Multitasking & Gestures page by Apple's own link needs it there, and shows its title and icon
// (common/AppleMultitasking.h MSAMMainListRow, by dlsym).
__attribute__((visibility("default"))) id MSBDMainListRow(NSString *ident) {
    PSListController *l = gRowList;
    if (!l || MSBDG18Root() || ![ident isKindOfClass:[NSString class]] || ![NSStringFromClass([l class]) isEqualToString:@"PSUIPrefsListController"]) return nil;
    for (PSSpecifier *sp in [l specifiers]) if ([[sp identifier] isEqualToString:ident]) return sp;
    return nil;
}
static void MSAMRowListedNow(void);   // (Apple's pages that came up before our row was listed: their rows taken out now -- defined below)
static void SetWindowsRowListed(void) {
    if (gWindowsRowListed) return;
    gWindowsRowListed = YES;
    MSAMRowListedNow();
}
// Right after Status Bar (15-17's main list), unless it is there already.
static void InsertWindowsRow(PSListController *list) {
    NSArray *specs = [list specifiers];
    NSInteger statusBar = NSNotFound;
    for (NSUInteger i = 0; i < specs.count; i++) {
        NSString *ident = [specs[i] identifier];
        if ([ident isEqualToString:kWindowsRowID]) { SetWindowsRowListed(); return; }
        if ([ident isEqualToString:kRowID]) statusBar = (NSInteger)i;
    }
    Class detail = PrefsBundle() ? NSClassFromString(@"MSBWindowsListController") : Nil;
    if (statusBar == NSNotFound || !detail) return;
    [list insertSpecifier:MakeWindowsRow(detail) atIndex:statusBar + 1 animated:NO];
    SetWindowsRowListed();
}
static void InsertRow(PSListController *list) {
    NSArray *specs = [list specifiers];
    WatchRowValue(list);
    for (NSUInteger i = 0; i < specs.count; i++) if ([[specs[i] identifier] isEqualToString:kRowID]) { InsertWindowsRow(list); return; }   // already there
    NSInteger anchor = AnchorIndex(specs, kDockRowID, nil);
    BOOL newOS = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17;   // (15/16: exactly as before)
    if (anchor == NSNotFound && newOS) anchor = TopIndex(specs);   // (only ever the main list: this runs from PSUIPrefsListController alone)
    Class detail = PrefsBundle() ? NSClassFromString(@"MSBRootListController") : Nil;   // the class only exists once the bundle is loaded
    if (anchor == NSNotFound || !PrefsBundle() || !detail) return;         // not the main list, or the page is missing

    PSSpecifier *row = MakeRow(detail, kRowID);
    [list insertSpecifier:row atIndex:anchor animated:NO];
    if (newOS) {   // (the same page listed with the other tweaks by the postinst on 17+: hidden while our own row is there -- found by its id, or by our
        // bundle as it was listed before it had one; never another tweak's entry of the same name)
        for (PSSpecifier *sp in [[list specifiers] copy]) {
            if ([[sp identifier] isEqualToString:kRowID]) continue;
            BOOL ours = [[sp identifier] isEqualToString:@"MSBD_PL_MacStatusBarPrefs"];
            if (!ours && [[sp name] isEqualToString:@"Status Bar"]) { id b = [sp propertyForKey:@"bundle"] ?: [sp propertyForKey:@"lazy-bundle"]; ours = [b isKindOfClass:[NSString class]] && [(NSString *)b containsString:@"MacStatusBarPrefs"]; }
            if (ours) [list removeSpecifier:sp animated:NO];
        }
    }
    InsertWindowsRow(list);
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
// A link into our pages (prefs:root=MAC_STATUS_BAR / MAC_WINDOWS[...]: the Settings search's results, 1.6.0's links to the window rows): when Settings
// is started by the link itself, the link looks for our row before the list has first appeared -- so the rows are put in the moment one is asked
// for (as the Dock row does, DockSettingsRow.x).
- (id)specifierForID:(NSString *)identifier {
    static BOOL inserting = NO;
    id r = %orig;
    if (!r && !inserting && ([identifier isEqualToString:kRowID] || [identifier isEqualToString:kWindowsRowID])) {
        inserting = YES;
        InsertRow((PSListController *)self);
        inserting = NO;
        r = %orig;
    }
    return r;
}
%end

// ---- iPadOS 18: the row first in our group at the top of General (common/General18Group.h) ----
// With PreferenceLoader's identifier (its entry at the end of General goes while our row is there, so prefs:root=General&path=MSBD_PL_MacStatusBarPrefs
// reaches our row as it reached the entry), the line's On / Off as on 15-17, and the page from our bundle.
#define kPLRowID @"MSBD_PL_MacStatusBarPrefs"
static void InsertWindowsRow18(PSListController *page) {   // (right after Status Bar in our group, else first: General18Group.h MSBDG18Put)
    if (MSBDG18Has(page, kWindowsRowID)) return;
    Class detail = PrefsBundle() ? NSClassFromString(@"MSBWindowsListController") : Nil;
    if (detail) MSBDG18Put(page, @[MakeWindowsRow(detail)], @[kPLRowID]);
}
static void InsertRow18(PSListController *page) {
    gRowID = kPLRowID;
    WatchRowValue(page);
    if (MSBDG18Has(page, kPLRowID)) { MSBDG18RemoveListed(page, kPLRowID, @"MacStatusBarPrefs"); InsertWindowsRow18(page); return; }   // (ours in; PreferenceLoader's entry out)
    Class detail = PrefsBundle() ? NSClassFromString(@"MSBRootListController") : Nil;
    if (detail) MSBDG18PutInPlaceOf(page, MakeRow(detail, kPLRowID), @[], kPLRowID, @"MacStatusBarPrefs");   // (first in the group)
    InsertWindowsRow18(page);
}
%group General18
%hook PSGGeneralController
- (id)specifiers {
    id specs = %orig;
    if (![specs isKindOfClass:[NSArray class]]) return specs;
    BOOL ours = NO, listed = NO, windows = NO;   // (ours there and PreferenceLoader's gone: nothing to do -- read from the list handed out, never asked again here)
    for (id sp in specs) {
        if ([MSBDG18Ident(sp) isEqualToString:kPLRowID]) { if (MSBDG18IsOurs(sp)) ours = YES; else listed = YES; }
        if (MSBDG18IsOurs(sp) && [MSBDG18Ident(sp) isEqualToString:kWindowsRowID]) windows = YES;
    }
    if (ours && !listed && windows) return specs;
    // (once the list is handed out, on the next turn of the main loop; asked for again and again while it is built: one try a second at most)
    static const void *kTriedKey = &kTriedKey;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *tried = objc_getAssociatedObject(self, kTriedKey);
    if (tried && now - tried.doubleValue < 1.0) return specs;
    objc_setAssociatedObject(self, kTriedKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak PSListController *weakSelf = (PSListController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{ PSListController *l = weakSelf; if (l) InsertRow18(l); });
    return specs;
}
%end
%end
// (General's class comes with GeneralSettingsUI, which Settings links, so it is there at our start; else as soon as an image brings it -- the hook
//  goes in on the main queue, never inside dyld's callback, as DockSettingsRow.x's Home Screen rows)
static void General18TryInit(void) {
    static BOOL done = NO;
    if (done || !MSBDG18Root()) return;
    Class c = objc_getClass("PSGGeneralController");
    if (!c) return;
    done = YES;
    if (MSBDG18PageOK(c)) { %init(General18); gWindowsRowListed = YES; }   // (the Windows & Multitasking row goes in with General's list from now on)
}
static void General18ImageAdded(const struct mach_header *mh, intptr_t slide) {
    static atomic_int queued = 0;
    int expected = 0;
    if (!objc_getClass("PSGGeneralController") || !atomic_compare_exchange_strong(&queued, &expected, 1)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ General18TryInit(); });
}

// The welcome alert's "Take Me There" (2026-09-25): SpringBoard opens Settings full screen and publishes the time of the request in a notify state;
// Settings then opens this page, once, the way a tap on the row does -- when it becomes active (a cold launch, or back from the background) or, when
// it is active already, on the notification. A request older than 20 s is ignored. (Our page is a row added to the main list, not a PreferenceLoader
// entry, so a prefs:root= link cannot be relied on to find it.) Nothing else sets the state: otherwise one notify read per activation of Settings.
// The state's high 32 bits name a place on the page (0 the page itself, 1 Go Menu > Apps: the Go menu's "Edit Go Menu…", 2 the Window Engine
// picker: the 1.1.0 Stage Manager engine notice's "Choose Engine"); the low 32 bits the time.
#define kOpenPageState "com.besiktasliseba.macstatusbaranddock.openstatusbarpage"
// (by its own class: the Windows & Multitasking page's controller is a subclass of the Status Bar page's)
static BOOL ShowsPage(UIViewController *vc, Class page) {
    if (!vc || !page) return NO;
    if ([vc class] == page) return YES;
    for (UIViewController *c in vc.childViewControllers) if (ShowsPage(c, page)) return YES;
    return NO;
}
static UIViewController *FindController(UIViewController *vc, Class c) {
    if (!vc || !c) return nil;
    if ([vc class] == c) return vc;
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
// A row of our page opened the way a tap does (its list pushed on the page's navigation stack): 1 = Go Menu > Apps, 2 = Window Engine -- since 1.6.0
// on the Windows & Multitasking page (its own row in the main list, MAC_WINDOWS), the others on the Status Bar page. 3 = the Windows & Multitasking
// page itself (SpringBoard's notices that send to Enable Windowing), no row on it; 0 = the Status Bar page.
static Class InnerClass(uint32_t target) { return NSClassFromString(target == 2 ? @"MSBEngineListController" : @"MSBGoAppsController"); }
static Class PageClass(uint32_t target) { return NSClassFromString(target == 2 || target == 3 ? @"MSBWindowsListController" : @"MSBRootListController"); }
static NSString *PageRowID(uint32_t target) { return target == 2 || target == 3 ? kWindowsRowID : gRowID; }
static BOOL InnerRowMatches(PSSpecifier *sp, uint32_t target) {
    if (target == 2) return [[sp propertyForKey:@"key"] isEqual:@"windowEngine"];
    return [[sp identifier] isEqualToString:@"GO_APPS"];
}
// YES when the row's list is on the stack: shown (the page under it popped to when needed), and only once (a second copy is taken out)
static BOOL DedupeInner(UINavigationController *nav, uint32_t target) {
    Class c = InnerClass(target);
    NSArray<UIViewController *> *vcs = nav.viewControllers;
    UIViewController *first = nil; NSMutableArray *kept = [NSMutableArray array];
    for (UIViewController *vc in vcs) {
        if ([vc isKindOfClass:c]) { if (first) continue; first = vc; }
        [kept addObject:vc];
    }
    SBRowLog([NSString stringWithFormat:@"row %u check: %@", target, StackText(nav)]);
    if (!first) return NO;
    if (kept.count != vcs.count) { SBRowLog(@"a second copy taken out"); [nav setViewControllers:kept animated:NO]; }
    if (nav.topViewController != first) [nav popToViewController:first animated:NO];
    return YES;
}
static void OpenInnerRow(int attempt, uint32_t target) {
    PSListController *list = gRowList;
    UIViewController *top = list.splitViewController ?: list.navigationController;
    PSListController *page = (PSListController *)FindController(top, PageClass(target));
    UINavigationController *nav = page.navigationController;
    PSSpecifier *row = nil;
    for (PSSpecifier *sp in [page specifiers]) if (InnerRowMatches(sp, target)) { row = sp; break; }
    NSIndexPath *ip = row ? [page indexPathForSpecifier:row] : nil;
    UITableView *t = nil; @try { t = [page valueForKey:@"table"]; } @catch (NSException *e) {}
    // (another of the page's lists on top -- Go Menu > Apps when the Window Engine is asked for: the page's own view is off screen under it, so
    //  the check below took it for a page still being pushed until the tries ran out, and nothing happened; 17.5, M1 report 27 Oct): the asked
    //  list when it is on the stack already, else back to the page, whose row is then picked as usual
    if (page && nav && !page.view.window && [nav.viewControllers containsObject:page] && nav.topViewController != page) {
        if (DedupeInner(nav, target)) return;
        SBRowLog([NSString stringWithFormat:@"row %u: back to the page from %@", target, StackText(nav)]);
        [nav popToViewController:page animated:NO];
    }
    if (!page.view.window || !ip || ![t isKindOfClass:[UITableView class]]) {   // (the page is still being pushed)
        if (attempt < 16) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenInnerRow(attempt + 1, target); });
        return;
    }
    if (DedupeInner(nav, target)) return;   // (already there)
    if (nav.topViewController != page) [nav popToViewController:page animated:NO];
    [t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [page tableView:t didSelectRowAtIndexPath:ip];
    // a cold launch: Settings may still put back the page it showed last (that same list too), on top of ours -- two copies, and the first
    // Back only led to the other one. Looked at for 5 s.
    SBRowLog([NSString stringWithFormat:@"row %u opened: %@", target, StackText(nav)]);
    for (double at = 0.5; at <= 5.0; at += 0.5) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(at * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DedupeInner(nav, target); });
}
// Our row in the sidebar when the page asked for is shown already -- Settings put it back itself as it started (the page it showed last), or it
// was open: selected, and scrolled into the part of the list on screen when it is not there. The sidebar is marked as scrolled on purpose either
// way, so MacSettings' launch correction (common/SidebarScroll.h) leaves it alone: a cold launch that put our page back had its row selected and
// Settings had scrolled to it, then the correction put the sidebar back at its top and the row was off screen, and the next opens of a place on
// that page left it there (M1 15.6.1, Zetsu, 1.6.0 RC check; dedaf2d marked only a row our request picks itself).
static void ShowSidebarRow(UITableView *t, NSIndexPath *ip) {
    MSBDSidebarMarkScrolled(t);
    if (![t.indexPathForSelectedRow isEqual:ip]) [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionNone];
    CGRect seen = UIEdgeInsetsInsetRect(t.bounds, t.adjustedContentInset), r = [t rectForRowAtIndexPath:ip];
    if (CGRectContainsRect(seen, r)) return;
    [t scrollToRowAtIndexPath:ip atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    SBRowLog([NSString stringWithFormat:@"our row put on screen in the sidebar (the page was shown already; it was at y %.0f-%.0f, the list showed %.0f-%.0f)",
              CGRectGetMinY(r), CGRectGetMaxY(r), CGRectGetMinY(seen), CGRectGetMaxY(seen)]);
}
static void OpenPage(int attempt, uint32_t target) {
    // (iPadOS 18, SwiftUI root: SpringBoard opens the page and the place on it by Settings' own link -- common/SettingsRoot.h -- and asks nothing
    //  here; a request that still comes -- an older SpringBoard part -- has no main list to pick our row from: left)
    if (MSBDG18Root()) { SBRowLog(@"iPadOS 18: a page request without a link: left (SpringBoard links to the page)"); return; }
    PSListController *list = gRowList;
    PSSpecifier *row = nil;
    for (PSSpecifier *sp in [list specifiers]) if ([[sp identifier] isEqualToString:PageRowID(target)]) { row = sp; break; }
    NSIndexPath *ip = row ? [list indexPathForSpecifier:row] : nil;
    UITableView *t = nil; @try { t = [list valueForKey:@"table"]; } @catch (NSException *e) {}
    if (!ip || ![t isKindOfClass:[UITableView class]]) {   // (a cold launch: the main list may not be built yet)
        if (attempt < 12) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenPage(attempt + 1, target); });
        return;
    }
    UIViewController *top = list.splitViewController ?: list.navigationController;
    if (!ShowsPage(top, PageClass(target))) {
        MSBDSidebarMarkScrolled(t);   // (MacSettings' launch correction would put the sidebar back at its top: common/SidebarScroll.h)
        [t selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionMiddle];
        [list tableView:t didSelectRowAtIndexPath:ip];
    } else {
        ShowSidebarRow(t, ip);   // (the page is shown already: Settings put it back itself as it started, or it was open)
        if (target == 0 || target == 3) {
            // (already there: the page itself on top -- one of its lists put away, as its row's tap shows it: the Window Engine picker on the
            //  Windows & Multitasking page; Go Menu > Apps, Status Bar Style... on the Status Bar page. Until 1.6.0~rc4 the Status Bar page (place 0:
            //  Take Me There, the crash notice's Open Settings) counted as there while one of its lists was on top, and that list stayed: M1
            //  15.6.1, RC check)
            UIViewController *pg = FindController(top, PageClass(target));
            UINavigationController *nav = pg.navigationController;
            if (nav && nav.topViewController != pg && [nav.viewControllers containsObject:pg]) { SBRowLog([NSString stringWithFormat:@"row %u: back to the page from %@", target, StackText(nav)]); [nav popToViewController:pg animated:NO]; }
            return;
        }
        if (target != 1 && target != 2) return;   // (already there)
    }
    if (target == 1 || target == 2) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenInnerRow(0, target); });
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

// ---- Apple's multitasking settings on the Windows & Multitasking page (1.6.0, common/AppleMultitasking.h) ----
// While our page shows them (MSAMWanted, the same answer the page itself asks), Apple's rows that lead there are taken out of their page (16:
// General's Picture in Picture and Gestures), right after that page has built or rebuilt its list, through its own remove call (NativeEmbed.h);
// a link into them -- Settings' own search results, prefs:root=General&path=GESTURES... -- opens our page at those rows instead; and when one of
// Apple's pages made for our page reloads one of its rows itself (Gestures: the corner swipes' footer, finger or pencil), our page reloads it too.
static void OpenWindowsPageAt(NSString *rowID, int attempt) {
    if (attempt == 0) OpenPage(0, 3);
    PSListController *list = gRowList;
    UIViewController *top = list.splitViewController ?: list.navigationController;
    PSListController *page = (PSListController *)FindController(top, PageClass(3));
    if (!page || !page.view.window) {
        if (attempt < 24) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ OpenWindowsPageAt(rowID, attempt + 1); });
        else SBRowLog([NSString stringWithFormat:@"apple rows: the Windows & Multitasking page did not come for %@", rowID]);
        return;
    }
    SBRowLog([NSString stringWithFormat:@"apple rows: on the Windows & Multitasking page (try %d), to %@", attempt, rowID]);
    SEL h = NSSelectorFromString(@"handleURL:withCompletion:");
    if (rowID.length && [page respondsToSelector:h]) ((void (*)(id, SEL, id, id))objc_msgSend)(page, h, @{@"path": rowID}, nil);
}
#if DEBUG
%group MSAMDebugURL   // (debug builds: every link Settings' own URL handler opens, for the device checks of the redirect; 15-17 only)
%hook PreferencesAppController
- (void)processURL:(NSURL *)url animated:(BOOL)animated fromSearch:(BOOL)fromSearch withCompletion:(id)completion {
    SBRowLog([NSString stringWithFormat:@"processURL %@ (search %d)", url, fromSearch]);
    %orig;
}
%end
%end
#endif
// One redirect per link: Settings' URL handler can ask a page twice for the same link (its prepare step, then -handleURL:withCompletion:).
static void MSAMStartRedirect(NSString *row) {
    static NSString *lastRow; static CFAbsoluteTime lastAt;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (lastRow && [lastRow isEqualToString:row ?: @""] && now - lastAt < 1.5) return;
    lastRow = [row ?: @"" copy]; lastAt = now;
    dispatch_async(dispatch_get_main_queue(), ^{ OpenWindowsPageAt(row, 0); });
}
// Apple's pages whose rows our page shows (General's Picture in Picture and Gestures, 15/16) take them out only while our row is in Settings' list.
// A page that came up before the row was listed waits, and its rows go the moment the row is (MSAMRowListedNow, from SetWindowsRowListed): a cold
// launch that restores General brings it up through Settings' own URL handler (prefs:root=General#...) before the main list has appeared and
// taken our rows, and General then kept both rows next to our page's (iPad 2 16.7.7, 1.6.0, Zetsu, 2 of 2; a General opened later had none).
static NSHashTable *gMSAMWaiting;
static void MSAMHide(UIViewController *list) {
    BOOL listed = MSBDWindowsRowListed();
    NSArray *h = MSAMHiddenOn(list, listed);
    if (h.count) { MSNEHideRows(list, h); return; }
    if (listed || !MSAMHiddenOn(list, YES).count) return;   // (nothing to take out of this page, even once our row is listed)
    if (!gMSAMWaiting) gMSAMWaiting = [NSHashTable weakObjectsHashTable];
    if ([gMSAMWaiting containsObject:list]) return;
    [gMSAMWaiting addObject:list];
    SBRowLog([NSString stringWithFormat:@"apple rows: %@ came up before our row was listed: its rows wait for it", NSStringFromClass([list class])]);
}
static void MSAMRowListedNow(void) {
    NSArray *pages = gMSAMWaiting.allObjects;
    [gMSAMWaiting removeAllObjects];
    for (UIViewController *list in pages) {
        if (!list.isViewLoaded) continue;   // (its next appearance takes them out: viewWillAppear above)
        SBRowLog([NSString stringWithFormat:@"apple rows: our row is listed: %@'s rows taken out now", NSStringFromClass([list class])]);
        MSAMHide(list);
    }
}
%hook PSListController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    MSAMHide((UIViewController *)self);
}
- (void)reloadSpecifiers {
    %orig;
    MSAMHide((UIViewController *)self);
}
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
    NSString *path = [url isKindOfClass:[NSDictionary class]] ? url[@"path"] : nil;
    NSString *row = nil;
    int entry = [path isKindOfClass:[NSString class]] && MSAMSourcesFor(MSAMOS()).count
        ? MSAMRedirect(MSAMOS(), NSStringFromClass([self class]), path, ^NSArray<NSString *> *(int e) { return MSAMEntryRowIDs(e); }, &row) : -1;
    if (entry >= 0) SBRowLog([NSString stringWithFormat:@"apple rows: link %@ on %@ -> entry %d, row %@, ours %d", url, NSStringFromClass([self class]), entry, row, MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)]);
    if (entry >= 0 && MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)) {
        MSAMStartRedirect(row);
        if (completion) ((void (^)(void))completion)();
        return;
    }
    %orig;
}
- (void)reloadSpecifier:(id)spec animated:(BOOL)animated {
    %orig;
    if (!MSAMIsEntryPage(self)) return;
    UIViewController *host = MSNECall(self, @"parentController");
    if (host && host != (id)self && host.isViewLoaded && host.view.window && [host respondsToSelector:@selector(reloadSpecifier:animated:)])
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, @selector(reloadSpecifier:animated:), spec, animated);
}
- (void)reloadSpecifierID:(NSString *)ident animated:(BOOL)animated {
    %orig;
    if (!MSAMIsEntryPage(self)) return;
    UIViewController *host = MSNECall(self, @"parentController");
    if (host && host != (id)self && host.isViewLoaded && host.view.window && [host respondsToSelector:@selector(reloadSpecifierID:animated:)])
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(host, @selector(reloadSpecifierID:animated:), ident, animated);
}
%end
%group MSAMHighlight   // (a link to a row on a page -- prefs:root=General#Multitasking_Gesture_Switch, Settings' own "Gestures" result on 16.7.7)
%hook PSListController
- (void)highlightSpecifierWithID:(NSString *)ident {
    NSString *row = nil;
    int entry = [ident isKindOfClass:[NSString class]] && MSAMSourcesFor(MSAMOS()).count
        ? MSAMRedirect(MSAMOS(), NSStringFromClass([self class]), ident, ^NSArray<NSString *> *(int e) { return MSAMEntryRowIDs(e); }, &row) : -1;
    if (entry >= 0) SBRowLog([NSString stringWithFormat:@"apple rows: highlight %@ on %@ -> entry %d, row %@, ours %d", ident, NSStringFromClass([self class]), entry, row, MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)]);
    if (entry >= 0 && MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)) { MSAMStartRedirect(row); return; }
    %orig;
}
%end
%end
%group MSAMPrepare
%hook PSListController
// (Settings' URL handler on a page already shown -- a search result while General is open -- asks the page to prepare the next row of the path
//  instead of handing it the link: the same redirect there; YES = handled here, as a page that handles its own rows answers)
- (BOOL)prepareHandlingURLForSpecifierID:(NSString *)specID resourceDictionary:(NSDictionary *)dict animatePush:(BOOL *)animate withCompletion:(id)completion {
    NSString *row = nil;
    int entry = [specID isKindOfClass:[NSString class]] && MSAMSourcesFor(MSAMOS()).count
        ? MSAMRedirect(MSAMOS(), NSStringFromClass([self class]), [dict[@"path"] isKindOfClass:[NSString class]] && [dict[@"path"] length] ? [NSString stringWithFormat:@"%@/%@", specID, dict[@"path"]] : specID,
                       ^NSArray<NSString *> *(int e) { return MSAMEntryRowIDs(e); }, &row) : -1;
    if (entry >= 0) SBRowLog([NSString stringWithFormat:@"apple rows: prepare %@ (%@) on %@ -> entry %d, row %@, ours %d", specID, dict, NSStringFromClass([self class]), entry, row, MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)]);
    if (entry >= 0 && MSAMWanted(MSBDWindowsRowListed()) && MSAMEntryOK(entry)) {
        MSAMStartRedirect(row);
        if (completion) ((void (^)(void))completion)();
        return YES;
    }
    return %orig;
}
%end
%end

%ctor {
    %init;
    {   // (Apple's multitasking rows: the prepare step of Settings' URL handler, where it is there with its types -- 16.7.7: B@:@@^B@?)
        Class list = objc_getClass("PSListController");
        if (MSBDG18Types(list, NSSelectorFromString(@"prepareHandlingURLForSpecifierID:resourceDictionary:animatePush:withCompletion:"), "B", @[@"@", @"@", @"^B", @"@?"])) %init(MSAMPrepare);
        if (MSBDG18Types(list, NSSelectorFromString(@"highlightSpecifierWithID:"), "v", @[@"@"])) %init(MSAMHighlight);
#if DEBUG
        if (objc_getClass("PreferencesAppController")) %init(MSAMDebugURL);
#endif
    }
    if (MSBDG18Root()) { General18TryInit(); _dyld_register_func_for_add_image(General18ImageAdded); }   // (iPadOS 18's SwiftUI root; 15-17: the main list's row above)
    dispatch_async(dispatch_get_main_queue(), ^{ MSBDSettingsRootRecord(MSBDG18Root()); });   // (for links into our pages from outside Settings: common/SettingsRoot.h)
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) { CheckOpenPageRequest(); }];
    int t = 0;
    notify_register_dispatch(kOpenPageState, &t, dispatch_get_main_queue(), ^(int tok) {
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) CheckOpenPageRequest();
    });
}
