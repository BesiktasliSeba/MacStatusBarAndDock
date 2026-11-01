// SidebarGroups.x -- Settings' sidebar decluttered (1.7.5 item 2, KT 31 Oct; MacSettings, Settings app, iPadOS 15-17): "Notifications & Sounds" and
// "Focus & Screen Time". Each is one row of the sidebar in place of Apple's two, and opens a page of ours (MSSGPageController) with Apple's two rows
// at its top -- Apple's own specifiers, so a tap opens Apple's own page exactly as the sidebar did, and Apple's pages stay entirely Apple's (their
// links, app lists and sub-pages). Not Apple's content of both on one page: Notifications builds its app list later and opens its own sub-pages,
// which only works from its own page. KT 31 Oct ~23:00: always so, no switch.
//  - The rows (common/SidebarGroups.h MSSGPlan): Apple's two go through the list's own calls (replace / remove) when the sidebar appears or is built
//    again, and when something asks for our row before it appeared (a link at a cold start) -- only when both of a group's rows are there. Apple's
//    rows are kept for our page; our row has the first one's icon.
//  - Links (search results, Spotlight, other apps, Control Center's Focus): Settings' URL handler gets prefs:root=<our row>&path=<Apple's row>/...
//    instead (MSSGRewrite), for a group in the sidebar then: our page opens Apple's page by its row and Apple's own URL handling takes the rest.
//  - Settings' search: Apple's result sections are named after the main list's rows; for Apple's grouped rows the list is asked about our row
//    (shown, order) and the section keeps Apple's own icon.
//  - Defensive: every private method used is checked with its types first; anything missing and nothing is grouped (Apple's sidebar as it is).
// 18: the sidebar is Apple's SwiftUI list (no PSUIPrefsListController): nothing here runs there.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <os/lock.h>
#import <notify.h>
#import "../common/SidebarGroups.h"
#import "../common/General18Group.h"   // (MSBDG18Types: a method's return and argument types as expected)

@interface PSSpecifier : NSObject
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(long long)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (NSString *)name;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (Class)detailControllerClass;
@end
@interface PSListController : UIViewController { NSMutableArray *_specifiers; }
- (NSMutableArray *)specifiers;
- (PSSpecifier *)specifier;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion;
- (BOOL)prepareHandlingURLForSpecifierID:(NSString *)specID resourceDictionary:(NSDictionary *)dict animatePush:(BOOL *)animate withCompletion:(id)completion;
@end

static void SGLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "[sidebargroups] %s\n", line.UTF8String); fclose(f);
#else
    (void)line;
#endif
}

static BOOL gSGOK = NO;                                 // (the sidebar's calls are there with their types: grouping on)
static NSMutableDictionary<NSNumber *, NSArray *> *gSGMembers;   // (group -> Apple's two rows, in Apple's order, kept for our page; changed on the
static os_unfair_lock gSGLock = OS_UNFAIR_LOCK_INIT;             //  main thread only, read under the lock -- Settings' search may ask from its queue)
static __weak id gSGRoot;                               // (the sidebar: PSUIPrefsListController)
static NSArray *SGMembers(int g) { os_unfair_lock_lock(&gSGLock); NSArray *m = g >= 0 ? gSGMembers[@(g)] : nil; os_unfair_lock_unlock(&gSGLock); return m; }
static void SGSetMembers(int g, NSArray *m) {
    os_unfair_lock_lock(&gSGLock);
    if (!gSGMembers) gSGMembers = [NSMutableDictionary dictionary];
    if (m.count == 2) gSGMembers[@(g)] = m; else [gSGMembers removeObjectForKey:@(g)];
    os_unfair_lock_unlock(&gSGLock);
}

static NSString *SGIdent(id sp) { id i = [sp respondsToSelector:@selector(identifier)] ? [sp identifier] : nil; return [i isKindOfClass:[NSString class]] ? i : nil; }
static NSArray *SGSpecs(id list) { id s = list ? ((id (*)(id, SEL))objc_msgSend)(list, @selector(specifiers)) : nil; return [s isKindOfClass:[NSArray class]] ? s : nil; }

@interface MSSGPageController : PSListController
@end

// Our row's title: Apple's two rows' own names joined ("Notifications" & "Sounds" -- in the iPad's language), else ours.
static NSString *SGTitle(int g, NSArray *members) {
    NSString *a = members.count == 2 ? [members[0] name] : nil, *b = members.count == 2 ? [members[1] name] : nil;
    if ([a isKindOfClass:[NSString class]] && [b isKindOfClass:[NSString class]] && a.length && b.length) return [NSString stringWithFormat:@"%@ & %@", a, b];
    return @(kMSSGGroups[g].title);
}
// Our row: Apple's first row's place, its icon (the image, or the keys its cell loads it lazily by -- 17), a link to our page.
static PSSpecifier *SGMakeRow(int g, NSArray *members) {
    PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:SGTitle(g, members) target:nil set:NULL get:NULL detail:[MSSGPageController class] cell:1 edit:Nil];   // (1: PSLinkCell)
    [row setIdentifier:@(kMSSGGroups[g].ident)];
    [row setProperty:@(kMSSGGroups[g].ident) forKey:@"id"];
    [row setProperty:@YES forKey:@"hasSelectionStyle"];
    [row setProperty:@YES forKey:@"enabled"];
    NSDictionary *props = nil;
    @try { props = [members.firstObject valueForKey:@"properties"]; } @catch (NSException *e) { props = nil; }
    if ([props isKindOfClass:[NSDictionary class]]) for (id k in props)
        if ([k isKindOfClass:[NSString class]] && [(NSString *)k rangeOfString:@"icon" options:NSCaseInsensitiveSearch].location != NSNotFound) [row setProperty:props[k] forKey:k];
    return row;
}
// Apple's rows of each group leave the sidebar for our row, through the list's own calls (common/SidebarGroups.h MSSGApplyPlan: from a copy of the
// list, each row looked for again before its call -- 1.7.5 review); a group's Apple row that came back next to our row goes too (kept for our page
// instead); a group whose row is not in the list keeps nothing. Main thread only, never inside itself (Apple asks for rows while it reloads).
static void SGApply(id list) {
    static BOOL applying = NO;
    if (!gSGOK || !list || applying || ![NSThread isMainThread]) return;
    applying = YES;
    gSGRoot = list;
    MSSGApplyPlan(list, ^id(int g, NSArray *members) { return SGMakeRow(g, members); }, ^(int g, NSArray *members) {
        SGSetMembers(g, members);
        SGLog([NSString stringWithFormat:@"%s: %@ and %@ grouped in the sidebar", kMSSGGroups[g].title, SGIdent(members[0]), SGIdent(members[1])]);
    });
    NSArray *specs = [SGSpecs(list) copy];
    NSMutableSet *ours = [NSMutableSet set];
    for (id sp in specs) { int g = MSSGGroupOfOurs(SGIdent(sp)); if (g >= 0) [ours addObject:@(g)]; }
    for (int g = 0; g < MSSG_COUNT; g++) if (![ours containsObject:@(g)] && SGMembers(g)) { SGSetMembers(g, nil); SGLog([NSString stringWithFormat:@"%s: our row is not in the list: nothing kept", kMSSGGroups[g].title]); }
    SEL remove = NSSelectorFromString(@"removeSpecifier:animated:");
    for (id sp in specs) {
        int m = -1, g = MSSGGroupOfApple(SGIdent(sp), &m);
        if (g < 0 || ![ours containsObject:@(g)]) continue;
        NSMutableArray *members = [(SGMembers(g) ?: @[]) mutableCopy];
        @try { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(list, remove, sp, NO); } @catch (NSException *e) { continue; }
        if (members.count == 2) { members[m] = sp; SGSetMembers(g, members); }
        SGLog([NSString stringWithFormat:@"%@ came back next to our row: kept for our page", SGIdent(sp)]);
    }
    applying = NO;
}
// Settings takes one of Apple's grouped rows away itself (it is not in the list, ours stands for it): the group goes -- the other row back in our
// row's place, Apple's own row again, nothing kept. NO: not one of ours.
static BOOL SGAppleRowGone(id list, id spec, NSString *ident) {
    if (![NSThread isMainThread]) return NO;
    for (int g = 0; g < MSSG_COUNT; g++) {
        NSArray *members = SGMembers(g);
        NSUInteger m = members.count == 2 ? (spec ? [members indexOfObjectIdenticalTo:spec] : NSNotFound) : NSNotFound;
        if (m == NSNotFound && ident && members.count == 2) for (NSUInteger k = 0; k < 2; k++) { NSString *mi = SGIdent(members[k]); if (mi && [mi caseInsensitiveCompare:ident] == NSOrderedSame) m = k; }
        if (m == NSNotFound) continue;
        id row = nil;
        for (id sp in SGSpecs(list)) if (MSSGGroupOfOurs(SGIdent(sp)) == g) { row = sp; break; }
        id other = members[1 - m];
        SGSetMembers(g, nil);
        if (row) @try { ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(list, NSSelectorFromString(@"replaceContiguousSpecifiers:withSpecifiers:animated:"), @[row], @[other], NO); } @catch (NSException *e) {}
        SGLog([NSString stringWithFormat:@"Settings took %@ away: %s ends, %@ is Apple's row again", SGIdent(members[m]), kMSSGGroups[g].title, SGIdent(other)]);
        return YES;
    }
    return NO;
}
// Settings puts a row after one of Apple's grouped rows: after our row, which stands for it now.
static NSString *SGAfterID(id list, NSString *ident) {
    int g = MSSGGroupOfApple(ident, NULL);
    if (g < 0 || !SGMembers(g)) return ident;
    for (id sp in SGSpecs(list)) if (MSSGGroupOfApple(SGIdent(sp), NULL) == g && [SGIdent(sp) caseInsensitiveCompare:ident] == NSOrderedSame) return ident;   // (Apple's row is there itself)
    return @(kMSSGGroups[g].ident);
}
// The sidebar, found from the windows (a link handled before it appeared: Settings has made it by then), else the one seen last.
static void SGFindRoot(UIViewController *vc, id *out) {
    if (!vc || *out) return;
    if ([vc isKindOfClass:objc_getClass("PSUIPrefsListController")]) { *out = vc; return; }
    for (UIViewController *c in vc.childViewControllers) SGFindRoot(c, out);
}
static id SGRoot(void) {
    id root = gSGRoot;
    if (root) return root;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) SGFindRoot(w.rootViewController, &root);
    }
    return root;
}
// Is a group in the sidebar now (grouped first where it can be)?
static BOOL SGGrouped(int g) {
    id root = SGRoot();
    if (!root) return NO;
    SGApply(root);
    for (id sp in SGSpecs(root)) if (MSSGGroupOfOurs(SGIdent(sp)) == g) return YES;
    return NO;
}
static NSURL *SGRoute(NSURL *url, NSString *how) {
    NSString *s = [url isKindOfClass:[NSURL class]] ? url.absoluteString : nil;
    NSString *r = MSSGRewrite(s, ^BOOL(int g) { return SGGrouped(g); });
    if (!r || [r isEqualToString:s]) return url;
    NSURL *u = [NSURL URLWithString:r];
    SGLog([NSString stringWithFormat:@"link (%@): %@ -> %@", how, s, u ? r : @"(not a URL: left)"]);
    return u ?: url;
}
// A search category of Apple's grouped rows: our row's identifier (asked of the list instead), else the category as it is.
static NSString *SGCategory(NSString *category) {
    int g = MSSGGroupOfApple(category, NULL);
    return g >= 0 && SGMembers(g) ? @(kMSSGGroups[g].ident) : category;
}

// ---- our page: Apple's two rows ----
@implementation MSSGPageController
- (int)msbd_group { return MSSGGroupOfOurs(SGIdent([self specifier])); }
- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        int g = [self msbd_group];
        NSMutableArray *s = [NSMutableArray arrayWithObject:[PSSpecifier groupSpecifierWithName:nil]];
        if (g >= 0) [s addObjectsFromArray:SGMembers(g) ?: @[]];
        _specifiers = s;
    }
    return _specifiers;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    int g = [self msbd_group];
    if (g >= 0) self.title = SGTitle(g, SGMembers(g));
}
// A row of Apple's: its page made by our own list from the row (-controllerForSpecifier:, as Settings makes any row's page: Apple's Notifications,
// Focus and Screen Time rows load their bundle that way -- BulletinBoardController, FCUISettingsListController, STRootViewController on 17.5.1),
// shown on top of our page. Never the generic tap of such a row from another list, nor the sidebar's own "special bundle" loader: both send
// -initWithParentListController: to Apple's page and throw (17.5.1, 1 Nov). nil: no page.
- (UIViewController *)msbd_show:(PSSpecifier *)sp animated:(BOOL)animated {
    UIViewController *c = nil;
    @try { c = ((id (*)(id, SEL, id))objc_msgSend)(self, @selector(controllerForSpecifier:), sp); } @catch (NSException *e) { SGLog([NSString stringWithFormat:@"%@: no page (%@)", SGIdent(sp), e.reason]); return nil; }
    if (![c isKindOfClass:[UIViewController class]]) { SGLog([NSString stringWithFormat:@"%@: no page", SGIdent(sp)]); return nil; }
    @try { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(self, @selector(showController:animate:), c, animated); } @catch (NSException *e) { SGLog([NSString stringWithFormat:@"%@: not shown (%@)", SGIdent(sp), e.reason]); return nil; }
    return c;
}
- (PSSpecifier *)msbd_row:(NSString *)ident {
    if (![ident isKindOfClass:[NSString class]] || !ident.length) return nil;
    for (PSSpecifier *sp in [self specifiers]) { NSString *i = SGIdent(sp); if (i && [i caseInsensitiveCompare:ident] == NSOrderedSame) return sp; }
    return nil;
}
// A link through our row (prefs:root=<our row>&path=<Apple's row>[/...]): once our page is in its navigation stack and Settings has stopped moving
// its pages (a cold start brings the link twice), Apple's page is shown as a tap shows it -- or, when it is already above our page, gone back to
// (its own pages above it closed), never a second copy -- and gets the rest of the link (its path and the row to show), as Apple's nested pages are
// linked.
- (void)msbd_open:(PSSpecifier *)sp rest:(NSDictionary *)rest completion:(id)completion attempt:(int)attempt {
    UINavigationController *nav = self.navigationController;
    UIViewController *mine = self;
    while (mine.parentViewController && mine.parentViewController != nav) mine = mine.parentViewController;
    NSArray *stack = nav.viewControllers;
    NSUInteger at = stack ? [stack indexOfObjectIdenticalTo:mine] : NSNotFound;
    if (!nav || nav.transitionCoordinator || at == NSNotFound || (at == stack.count - 1 && !self.view.window)) {
        __weak MSSGPageController *weakSelf = self;
        if (attempt < 20) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSSGPageController *me = weakSelf; if (me) [me msbd_open:sp rest:rest completion:completion attempt:attempt + 1]; else if (completion) ((void (^)(void))completion)(); }); return; }
        SGLog([NSString stringWithFormat:@"%@: our page did not settle for the link", SGIdent(sp)]);
        if (completion) ((void (^)(void))completion)();
        return;
    }
    UIViewController *above = at + 1 < stack.count ? stack[at + 1] : nil, *c = nil;
    BOOL there = above && [above respondsToSelector:@selector(specifier)] && ((id (*)(id, SEL))objc_msgSend)(above, @selector(specifier)) == sp;
    if (there) { if (nav.topViewController != above) [nav popToViewController:above animated:NO]; c = above; }
    else { if (nav.topViewController != mine) [nav popToViewController:mine animated:NO]; c = [self msbd_show:sp animated:NO]; }
    BOOL more = rest[@"path"] != nil;
    for (id k in rest) if (![k isEqual:@"animate"] && ![k isEqual:@"fromSearch"] && ![k isEqual:@"path"]) more = YES;
    SGLog([NSString stringWithFormat:@"link: %@ %@ (try %d), the rest %@", SGIdent(sp), there ? @"was there" : c ? @"shown" : @"not shown", attempt, more ? rest : @"none"]);
    if (c && more && [c respondsToSelector:@selector(handleURL:withCompletion:)]) { [(PSListController *)c handleURL:rest withCompletion:completion]; return; }
    if (completion) ((void (^)(void))completion)();
}
// Settings' URL handler on our page while it is shown (a search result or a link while it is open): it asks the page to prepare the next row of the
// link instead of handing it the link (as on Apple's General, StatusBarSettingsRow.x MSAMPrepare): the same way as a link. YES = handled here.
- (BOOL)prepareHandlingURLForSpecifierID:(NSString *)specID resourceDictionary:(NSDictionary *)dict animatePush:(BOOL *)animate withCompletion:(id)completion {
    PSSpecifier *row = [self msbd_row:specID];
    if (!row) return [super prepareHandlingURLForSpecifierID:specID resourceDictionary:dict animatePush:animate withCompletion:completion];
    NSMutableDictionary *rest = [dict isKindOfClass:[NSDictionary class]] ? [dict mutableCopy] : [NSMutableDictionary dictionary];
    [rest removeObjectForKey:@"root"];
    SGLog([NSString stringWithFormat:@"our page %@: prepare %@ %@", SGIdent([self specifier]), specID, dict]);
    [self msbd_open:row rest:rest completion:completion attempt:0];
    return YES;
}
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
    NSString *path = [url isKindOfClass:[NSDictionary class]] && [url[@"path"] isKindOfClass:[NSString class]] ? url[@"path"] : nil;
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    NSString *first = parts.firstObject;
    NSRange hash = first ? [first rangeOfString:@"#"] : NSMakeRange(NSNotFound, 0);
    PSSpecifier *row = [self msbd_row:hash.location == NSNotFound ? first : [first substringToIndex:hash.location]];
    SGLog([NSString stringWithFormat:@"our page %@: link %@", SGIdent([self specifier]), url]);
    if (!row) { [super handleURL:url withCompletion:completion]; return; }
    NSMutableDictionary *rest = [url mutableCopy];
    NSString *restPath = parts.count > 1 ? [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"/"] : @"";
    if (hash.location != NSNotFound) restPath = [restPath stringByAppendingString:[first substringFromIndex:hash.location]];
    if (restPath.length) rest[@"path"] = restPath; else [rest removeObjectForKey:@"path"];
    [rest removeObjectForKey:@"root"];
    [self msbd_open:row rest:rest completion:completion attempt:0];
}
// A tap on a row: Apple's page, the same way.
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger i = ((NSInteger (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"indexForIndexPath:"), ip);
    PSSpecifier *sp = i >= 0 && i < (NSInteger)_specifiers.count ? _specifiers[i] : nil;
    if (sp && SGIdent(sp) && MSSGGroupOfApple(SGIdent(sp), NULL) >= 0) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        [self msbd_show:sp animated:YES];
        return;
    }
    [super tableView:tv didSelectRowAtIndexPath:ip];
}
@end

%group SGSidebar
%hook PSUIPrefsListController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGApply(self);
}
- (void)reloadSpecifiers {
    %orig;
    SGApply(self);
}
// (a link at a cold start asks for our row before the sidebar first appeared: grouped the moment it is asked for, as our other rows)
- (id)specifierForID:(NSString *)identifier {
    static BOOL inside = NO;
    id r = %orig;
    if (r || inside || MSSGGroupOfOurs(identifier) < 0) return r;
    inside = YES; SGApply(self); inside = NO;
    return %orig;
}
// (Settings taking one of Apple's grouped rows away, or putting a row after one: through our row, which stands for it)
- (void)removeSpecifier:(id)spec animated:(BOOL)animated {
    if (spec && [SGSpecs(self) indexOfObjectIdenticalTo:spec] == NSNotFound && SGAppleRowGone(self, spec, nil)) return;
    %orig;
}
- (void)removeSpecifierID:(NSString *)ident animated:(BOOL)animated {
    BOOL inList = ((id (*)(id, SEL, id))objc_msgSend)(self, @selector(specifierForID:), ident) != nil;
    if (!inList && MSSGGroupOfApple(ident, NULL) >= 0 && SGAppleRowGone(self, nil, ident)) return;
    %orig;
}
%end
%end
%group SGAfter
%hook PSUIPrefsListController
- (void)insertSpecifier:(id)spec afterSpecifierID:(NSString *)ident animated:(BOOL)animated {
    %orig(spec, SGAfterID(self, ident), animated);
}
- (void)insertContiguousSpecifiers:(NSArray *)specs afterSpecifierID:(NSString *)ident animated:(BOOL)animated {
    %orig(specs, SGAfterID(self, ident), animated);
}
%end
%end
%group SGRootURL
%hook PSUIPrefsListController
// (a link that reaches the sidebar without Settings' URL handler -- another way in -- naming one of Apple's grouped rows as its root: sent through
//  our row as the handler would; anything else as it is)
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
    NSString *root = [url isKindOfClass:[NSDictionary class]] && [url[@"root"] isKindOfClass:[NSString class]] ? url[@"root"] : nil;
    int m = -1, g = MSSGGroupOfApple(root, &m);
    SGLog([NSString stringWithFormat:@"sidebar link: keys %@, root %@", [url isKindOfClass:[NSDictionary class]] ? [[url allKeys] componentsJoinedByString:@","] : @"-", root ?: @"-"]);
    if (g >= 0 && SGGrouped(g)) {
        NSMutableDictionary *d = [url mutableCopy];
        NSString *path = [url[@"path"] isKindOfClass:[NSString class]] ? url[@"path"] : nil;
        d[@"root"] = @(kMSSGGroups[g].ident);
        d[@"path"] = path.length ? [NSString stringWithFormat:@"%s/%@", kMSSGGroups[g].apple[m], path] : @(kMSSGGroups[g].apple[m]);
        SGLog([NSString stringWithFormat:@"sidebar link to %@: through our row (%@)", root, d[@"path"]]);
        %orig(d, completion);
        return;
    }
    %orig;
}
%end
%end

%group SGLinks
%hook PreferencesAppController
- (void)processURL:(NSURL *)url animated:(BOOL)animated fromSearch:(BOOL)fromSearch withCompletion:(id)completion {
    %orig(SGRoute(url, fromSearch ? @"search" : @"link"), animated, fromSearch, completion);
}
%end
%end
%group SGLinks1
%hook PreferencesAppController
- (void)processURL:(NSURL *)url {
    %orig(SGRoute(url, @"open"));
}
%end
%end

%group SGSearch
%hook PSUIPrefsListController
// (a section of one of Apple's grouped rows is never asked of the list by Apple's own identifier: its row is not in the list any more -- the list
//  answers "hidden" for it, and its icon lookup takes the row's sidebar cell and throws, which crashed Settings, 17.5.1 1 Nov -- but by our row's)
- (BOOL)searchResultsCollectionViewController:(id)controller shouldShowCategory:(NSString *)category {
    NSString *ours = SGCategory(category);
    if (ours == category) return %orig;
    return %orig(controller, ours);
}
- (long long)searchResultsCollectionViewController:(id)controller sortCategory1:(NSString *)a sortCategory2:(NSString *)b {
    int ma = -1, mb = -1, ga = MSSGGroupOfApple(a, &ma), gb = MSSGGroupOfApple(b, &mb);
    if (ga >= 0 && ga == gb && SGMembers(ga)) return ma < mb ? NSOrderedAscending : ma > mb ? NSOrderedDescending : NSOrderedSame;   // (Apple's order inside a group)
    return %orig(controller, SGCategory(a), SGCategory(b));
}
- (id)searchResultsCollectionViewController:(id)controller iconForCategory:(NSString *)category {
    int m = -1, g = MSSGGroupOfApple(category, &m);
    NSArray *members = SGMembers(g);
    if (members.count != 2) return %orig;
    id img = [members[m] propertyForKey:@"iconImage"];   // (Apple's row's own icon, kept with the row for our page)
    return [img isKindOfClass:[UIImage class]] ? img : %orig(controller, @(kMSSGGroups[g].ident));
}
%end
%end

#if DEBUG
// ---- debug builds: a test channel (echo '<cmd> <row id>' > /tmp/msb-sgtest, then post com.besiktasliseba.msb.sgtest): props (a kept row's
// properties), rootctl / pagectl [show] (the page the sidebar or our page makes for it; show: shown from our page). Nothing here changes a row. ----
static PSSpecifier *SGDebugMember(NSString *ident) {
    for (int g = 0; g < MSSG_COUNT; g++) for (id sp in SGMembers(g) ?: @[]) { NSString *i = SGIdent(sp); if (i && [i caseInsensitiveCompare:ident] == NSOrderedSame) return sp; }
    return nil;
}
static UIViewController *SGDebugTop(void) {
    id root = SGRoot(); UIViewController *vc = [root splitViewController] ?: [root navigationController];
    UIViewController *found = nil; NSMutableArray *q = vc ? [NSMutableArray arrayWithObject:vc] : [NSMutableArray array];
    for (NSUInteger k = 0; k < q.count && k < 60; k++) { UIViewController *c = q[k]; if ([c isKindOfClass:[MSSGPageController class]]) found = c; [q addObjectsFromArray:c.childViewControllers]; }
    return found;
}
static NSString *SGDebugProps(PSSpecifier *sp) {
    NSDictionary *props = nil; @try { props = [sp valueForKey:@"properties"]; } @catch (NSException *e) {}
    NSMutableArray *keys = [NSMutableArray array]; for (id k in props) if (![k isEqual:@"cellObject"] && ![k isEqual:@"iconImage"]) [keys addObject:[NSString stringWithFormat:@"%@=%@", k, [[props[k] description] substringToIndex:MIN((NSUInteger)60, [[props[k] description] length])]]];
    return [NSString stringWithFormat:@"detailClass %@ | %@", [sp detailControllerClass] ? NSStringFromClass([sp detailControllerClass]) : @"nil", [keys componentsJoinedByString:@"; "]];
}
static void SGDebugRun(NSString *cmd) {
    NSArray *p = [cmd componentsSeparatedByString:@" "];
    if (p.count < 2) return;
    PSSpecifier *sp = SGDebugMember(p[1]); id root = SGRoot(); UIViewController *page = SGDebugTop();
    SGLog([NSString stringWithFormat:@"test %@: spec %d root %d page %@", cmd, sp != nil, root != nil, page ? NSStringFromClass([page class]) : @"none"]);
    if (!sp) return;
    @try {
        if ([p[0] isEqualToString:@"props"]) SGLog(SGDebugProps(sp));
        else if ([p[0] isEqualToString:@"rootctl"]) { id c = ((id (*)(id, SEL, id))objc_msgSend)(root, NSSelectorFromString(@"controllerForSpecifier:"), sp); SGLog([NSString stringWithFormat:@"root controllerForSpecifier: %@", c ? NSStringFromClass([c class]) : @"nil"]); }
        else if ([p[0] isEqualToString:@"pagectl"]) {
            id c = page ? ((id (*)(id, SEL, id))objc_msgSend)(page, NSSelectorFromString(@"controllerForSpecifier:"), sp) : nil;
            SGLog([NSString stringWithFormat:@"page controllerForSpecifier: %@", c ? NSStringFromClass([c class]) : @"nil"]);
            if ([c isKindOfClass:[UIViewController class]] && p.count >= 3 && [p[2] isEqualToString:@"show"]) { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(page, NSSelectorFromString(@"showController:animate:"), c, YES); SGLog(@"shown from our page"); }
        }
    } @catch (NSException *e) { SGLog([NSString stringWithFormat:@"test %@ threw %@: %@", cmd, e.name, e.reason]); }
}
#endif

%ctor {
    Class root = objc_getClass("PSUIPrefsListController"), app = objc_getClass("PreferencesAppController"), list = objc_getClass("PSListController");
    if (!root || !app || !list) return;   // (18: the SwiftUI sidebar -- nothing here)
    BOOL calls = MSBDG18Types(root, @selector(specifiers), "@", @[])
        && MSBDG18Types(list, NSSelectorFromString(@"replaceContiguousSpecifiers:withSpecifiers:animated:"), "v", @[@"@", @"@", @"B"])
        && MSBDG18Types(list, NSSelectorFromString(@"removeSpecifier:animated:"), "v", @[@"@", @"B"])
        && MSBDG18Types(list, NSSelectorFromString(@"indexForIndexPath:"), "q", @[@"@"])
        && MSBDG18Types(list, @selector(specifierForID:), "@", @[@"@"])
        && MSBDG18Types(list, NSSelectorFromString(@"removeSpecifierID:animated:"), "v", @[@"@", @"B"]);
    BOOL links = MSBDG18Types(app, NSSelectorFromString(@"processURL:animated:fromSearch:withCompletion:"), "v", @[@"@", @"B", @"B", @"@?"])
        || MSBDG18Types(app, NSSelectorFromString(@"processURL:animated:fromSearch:withCompletion:"), "v", @[@"@", @"B", @"B", @"@"]);
    if (!calls || !links) { SGLog([NSString stringWithFormat:@"not grouped: the sidebar's calls %d, Settings' URL handler %d", calls, links]); return; }   // (a link could end on a missing row)
    gSGOK = YES;
    %init(SGSidebar);
    if (MSBDG18Types(list, NSSelectorFromString(@"insertSpecifier:afterSpecifierID:animated:"), "v", @[@"@", @"@", @"B"])
        && MSBDG18Types(list, NSSelectorFromString(@"insertContiguousSpecifiers:afterSpecifierID:animated:"), "v", @[@"@", @"@", @"B"])) %init(SGAfter);
    if (MSBDG18Types(list, NSSelectorFromString(@"handleURL:withCompletion:"), "v", @[@"@", @"@?"])
        || MSBDG18Types(list, NSSelectorFromString(@"handleURL:withCompletion:"), "v", @[@"@", @"@"])) %init(SGRootURL);
    %init(SGLinks);
    if (MSBDG18Types(app, NSSelectorFromString(@"processURL:"), "v", @[@"@"])) %init(SGLinks1);   // (other apps' links come this way first)
    if (MSBDG18Types(root, NSSelectorFromString(@"searchResultsCollectionViewController:shouldShowCategory:"), "B", @[@"@", @"@"])
        && MSBDG18Types(root, NSSelectorFromString(@"searchResultsCollectionViewController:sortCategory1:sortCategory2:"), "q", @[@"@", @"@", @"@"])
        && MSBDG18Types(root, NSSelectorFromString(@"searchResultsCollectionViewController:iconForCategory:"), "@", @[@"@", @"@"])) %init(SGSearch);
    SGLog(@"Notifications & Sounds, Focus & Screen Time: on");
#if DEBUG
    int t = 0;
    notify_register_dispatch("com.besiktasliseba.msb.sgtest", &t, dispatch_get_main_queue(), ^(int tok) {
        NSString *c = [[NSString stringWithContentsOfFile:@"/tmp/msb-sgtest" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (c.length) SGDebugRun(c);
    });
#endif
}
