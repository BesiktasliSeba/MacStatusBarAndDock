// BatteryHealthLink.x -- links straight to Settings > Battery > Battery Health (Battery Health & Charging from 16) on iPad, at one of our groups
// on it (1.7.9, KT 2 Nov: the battery menu's Charge Limit and Sleep Guard rows opened Settings > Battery, as no link reached the page on iPad).
// The link: prefs:root=BATTERY_USAGE&path=BATTERY_HEALTH[/<group>] (common/BatteryHealthLink.h). Settings' own link handling opens a page's row by
// its identifier, and on iPad the page's row (BatteryHealth.x) is not BATTERY_HEALTH, the page's name in Apple's iPhone link: BATTERY_HEALTH_TITLE on
// 18.5 (read with the specifier dump). So the Battery page takes the link to its row, whichever identifier the row has here -- the one whose page is
// BatteryHealthUIController -- and Settings opens it as it opens any row of a link (its own push, cold or warm); then the Battery Health page shows
// the group asked for at its top, as our own pages show a row (MSBRootListController -msb_scrollToRowID:). With another battery health tweak too,
// as BatteryHealth.x: the page is ours either way.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <unistd.h>
#import "../common/BatteryHealthLink.h"

NSString *MTSShuffleRoute(NSString *prefs);   // (TweakSearch.x, this library: where Shuffle has a page of the main list, by its own rewrite)

@interface PSSpecifier : NSObject
- (NSString *)identifier;
- (long long)cellType;
@end
@interface UIViewController (MSBHLPage)
- (NSArray *)specifiers;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
- (NSIndexPath *)indexPathForSpecifier:(PSSpecifier *)specifier;
- (UITableView *)table;
@end

static void MSBHLLog(NSString *line) {   // (debug builds only, with /tmp/macsettings-debug)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a");
    if (!f) return;
    fprintf(f, "batteryhealthlink: %s\n", line.UTF8String);
    fclose(f);
#endif
}

// The Battery page's row whose page is Battery Health, as the page lists it now (BATTERY_HEALTH_TITLE on 18.5); nil: none (another iPadOS, or the
// row left out).
static NSString *MSBHLRowID(UIViewController *battery) {
    Class health = objc_getClass("BatteryHealthUIController");
    SEL dc = NSSelectorFromString(@"detailControllerClass");
    NSArray *specs = [battery respondsToSelector:@selector(specifiers)] ? [battery specifiers] : nil;
    for (PSSpecifier *sp in [specs isKindOfClass:[NSArray class]] ? specs : @[]) {
        if (![sp respondsToSelector:dc] || ![sp respondsToSelector:@selector(identifier)]) continue;
        Class d = ((Class (*)(id, SEL))objc_msgSend)(sp, dc);
        if (health && d && [d isSubclassOfClass:health] && [sp identifier].length) return [sp identifier];
    }
    return nil;
}

#if DEBUG
// (debug, with /tmp/macsettings-debug: the page's list offset in the moments after the group was shown -- how it found the page's own animation)
@interface MSBHLOffsetWatch : NSObject
@end
@implementation MSBHLOffsetWatch
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)obj change:(NSDictionary *)change context:(void *)ctx {
    MSBHLLog([NSString stringWithFormat:@"list offset now %.1f", [change[NSKeyValueChangeNewKey] CGPointValue].y]);
}
@end
static void MSBHLWatchOffset(UITableView *t) {
    if (access("/tmp/macsettings-debug", F_OK) != 0 || !t) return;
    static MSBHLOffsetWatch *w; if (!w) w = [MSBHLOffsetWatch new];
    static __weak UITableView *watched;
    if (watched == t) return;   // (one watch per list at a time)
    watched = t;
    [t addObserver:w forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:NULL];
    __weak UITableView *weakT = t;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ UITableView *tt = weakT; if (tt) [tt removeObserver:w forKeyPath:@"contentOffset"]; if (watched == tt) watched = nil; });
}
#endif

// ---- the group asked for, at the top of the Battery Health page once it is on screen and Settings' navigation has settled ----
static NSString *gMSBHLGroup;   // (the group the last link asked for; nil once shown)
// (the page on top of its navigation stack, directly or inside the controller that hosts it on 18, and no transition running for it: a list scrolled
//  during its push is moved again as the push ends)
static BOOL MSBHLSettled(UIViewController *page) {
    UINavigationController *nav = page.navigationController;
    UIViewController *mine = page;
    while (mine.parentViewController && mine.parentViewController != nav) mine = mine.parentViewController;
    return page.view.window && !page.transitionCoordinator && (!nav || (nav.topViewController == mine && !nav.transitionCoordinator));
}
static void MSBHLKeepGroup(UITableView *t, UIViewController *page, NSString *group, double y, double last, int tick, int again);
static void MSBHLShowGroup(UIViewController *page, NSString *group, int attempt) {
    if (!page || !group.length || ![gMSBHLGroup isEqualToString:group]) return;   // (shown already, or another link came since)
    PSSpecifier *g = [page specifierForID:group];
    NSArray *specs = [page specifiers];
    NSUInteger at = g ? [specs indexOfObjectIdenticalTo:g] : NSNotFound;
    PSSpecifier *first = at != NSNotFound && at + 1 < specs.count && [specs[at + 1] cellType] != 0 ? specs[at + 1] : nil;   // (the group's first row)
    NSIndexPath *ip = first ? [page indexPathForSpecifier:first] : nil;
    UITableView *t = [page respondsToSelector:@selector(table)] ? [page table] : nil;
    if (!ip || ![t isKindOfClass:[UITableView class]] || !MSBHLSettled(page) || ip.section >= t.numberOfSections) {
        __weak UIViewController *weakPage = page;
        if (attempt < 16) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBHLShowGroup(weakPage, group, attempt + 1); });
        else MSBHLLog([NSString stringWithFormat:@"%@: not shown (group %d, row %d, settled %d)", group, g != nil, ip != nil, MSBHLSettled(page)]);
        return;
    }
    gMSBHLGroup = nil;
    [t layoutIfNeeded];
    UIEdgeInsets in = t.adjustedContentInset;
    double y = MSBDScrollOffsetForGroup(CGRectGetMinY([t rectForSection:ip.section]), in.top, in.bottom, t.contentSize.height, t.bounds.size.height);
    [t setContentOffset:CGPointMake(t.contentOffset.x, y) animated:NO];
    MSBHLLog([NSString stringWithFormat:@"%@ shown (try %d, section %ld, offset %.0f of %.0f, view %.0f, inset %.0f)", group, attempt, (long)ip.section, y, t.contentSize.height, t.bounds.size.height, in.top]);
#if DEBUG
    MSBHLWatchOffset(t);
#endif
    MSBHLKeepGroup(t, page, group, y, y, 0, 0);
}
// Watched for 2.5 s: the page's own scroll animation as it appears moved the list again after ours (18.5, with a watch on its offset: an ease-out
// to near the page's top, over about 0.6 s). Once the list is at rest elsewhere the group is shown again (twice at most); a touch on the list ends the
// watch, so the user's own scroll is never undone.
static void MSBHLKeepGroup(UITableView *t, UIViewController *page, NSString *group, double y, double last, int tick, int again) {
    if (!t.window || !page || gMSBHLGroup || tick > 10) return;   // (gone, another link since, or long enough)
    if (t.isTracking || t.isDragging || t.isDecelerating) { MSBHLLog([NSString stringWithFormat:@"%@: the list is touched: left as the user puts it", group]); return; }
    double now = t.contentOffset.y;
    if (fabs(now - y) >= 1.0 && fabs(now - last) < 0.5 && tick > 0) {   // (moved away, and at rest there)
        if (again >= 2) return;
        UIEdgeInsets in = t.adjustedContentInset;
        PSSpecifier *g = [page specifierForID:group];
        NSArray *specs = [page specifiers];
        NSUInteger at = g ? [specs indexOfObjectIdenticalTo:g] : NSNotFound;
        PSSpecifier *first = at != NSNotFound && at + 1 < specs.count && [specs[at + 1] cellType] != 0 ? specs[at + 1] : nil;
        NSIndexPath *ip = first ? [page indexPathForSpecifier:first] : nil;
        if (!ip || ip.section >= t.numberOfSections) return;
        y = MSBDScrollOffsetForGroup(CGRectGetMinY([t rectForSection:ip.section]), in.top, in.bottom, t.contentSize.height, t.bounds.size.height);
        [t setContentOffset:CGPointMake(t.contentOffset.x, y) animated:NO];
        MSBHLLog([NSString stringWithFormat:@"%@: the list moved to %.0f since: shown again at %.0f", group, now, y]);
        again++; now = y;
    }
    __weak UITableView *weakT = t; __weak UIViewController *weakPage = page;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBHLKeepGroup(weakT, weakPage, group, y, now, tick + 1, again); });
}
// The Battery Health page Settings opens for the link: found in the Battery page's navigation stack once it is there, then its group shown.
static void MSBHLAwait(UIViewController *battery, NSString *group, int attempt) {
    if (!group.length || ![gMSBHLGroup isEqualToString:group]) return;
    Class health = objc_getClass("BatteryHealthUIController");
    UIViewController *page = nil;
    for (UIViewController *vc in battery.navigationController.viewControllers) {
        if ([vc isKindOfClass:health]) page = vc;
        for (UIViewController *child in vc.childViewControllers) if ([child isKindOfClass:health]) page = child;   // (18: inside its host)
    }
    if (page) { MSBHLShowGroup(page, group, 0); return; }
    __weak UIViewController *weakBattery = battery;
    if (attempt < 16) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MSBHLAwait(weakBattery, group, attempt + 1); });
    else MSBHLLog([NSString stringWithFormat:@"%@: the Battery Health page did not come", group]);
}

%group MSBHLBattery
%hook BatteryUIController
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {
    NSString *path = [url isKindOfClass:[NSDictionary class]] ? url[@"path"] : nil, *group = nil;
    NSString *mapped = MSBDBatteryHealthPathForRow(path, MSBHLRowID((UIViewController *)self), &group);
    if (!mapped) {
        %orig;
        return;
    }
    MSBHLLog([NSString stringWithFormat:@"link %@ -> %@ (handleURL)", path, mapped]);
    gMSBHLGroup = [group copy];
    NSMutableDictionary *u = [url mutableCopy];
    u[@"path"] = mapped;
    %orig(u, completion);
    if (group) MSBHLAwait((UIViewController *)self, group, 0);
}
%end
%end
%group MSBHLPrepare
%hook BatteryUIController
// (Settings' link handling on a page already shown can ask it to prepare the next row of the path instead of handing it the link)
// (its resource dictionary carries the whole path, first part included: 18.5 "BATTERY_HEALTH/MSBD_BATTERY_USE_GROUP")
- (BOOL)prepareHandlingURLForSpecifierID:(NSString *)specID resourceDictionary:(NSDictionary *)dict animatePush:(BOOL *)animate withCompletion:(id)completion {
    NSString *rowID = MSBHLRowID((UIViewController *)self);
    if (![specID isEqual:@MSBD_BH_PAGE] || !rowID) return %orig;
    NSString *path = [dict isKindOfClass:[NSDictionary class]] && [dict[@"path"] isKindOfClass:[NSString class]] ? dict[@"path"] : nil, *group = nil;
    NSString *mapped = MSBDBatteryHealthPathForRow(path, rowID, &group);
    MSBHLLog([NSString stringWithFormat:@"link %@ (path %@) -> %@ (prepare)", specID, path, rowID]);
    gMSBHLGroup = [group copy];
    NSDictionary *d = dict;
    if (mapped) { NSMutableDictionary *m = [dict mutableCopy]; m[@"path"] = mapped; d = m; }
    BOOL r = %orig(rowID, d, animate, completion);
    if (group) MSBHLAwait((UIViewController *)self, group, 0);
    return r;
}
%end
%end
%group MSBHLHealth
%hook BatteryHealthUIController
- (void)handleURL:(NSDictionary *)url withCompletion:(id)completion {   // (the rest of the link, where Settings hands it on to the page it opened: our groups only)
    NSString *path = [url isKindOfClass:[NSDictionary class]] ? url[@"path"] : nil;
    UIViewController *page = (UIViewController *)self;
    if (![@[@MSBD_BH_CHARGING_GROUP, @MSBD_BH_BATTERY_USE_GROUP] containsObject:path ?: @""] || ![page specifierForID:path] || [[page specifierForID:path] cellType] != 0) {
        %orig;
        return;
    }
    MSBHLLog([NSString stringWithFormat:@"the page's handleURL: group %@", path]);
    gMSBHLGroup = [path copy];
    MSBHLShowGroup(page, path, 0);
    if (completion) ((void (^)(void))completion)();
}
%end
%end

// (15-17: Settings' URL handler gets our link as Shuffle's rewrite misrouted it -- into one of its groups, our link a second path:
//  MSBDBatteryHealthLinkAsSent --: the link as it was sent again, routed where Shuffle's own answer for the Battery page alone puts it (the main
//  list, or the group Shuffle has it in), before Settings follows it. Shuffle rewrites in the one-argument -processURL:, which hands on to this one.)
%group MSBHLShuffle
%hook PreferencesAppController
- (void)processURL:(NSURL *)url animated:(BOOL)animated fromSearch:(BOOL)fromSearch withCompletion:(id)completion {
    NSString *sent = MSBDBatteryHealthLinkAsSent([url isKindOfClass:[NSURL class]] ? url.absoluteString : nil);
    NSString *routed = sent ? MTSShuffleRoute(sent) : nil;
    NSURL *u = routed ? [NSURL URLWithString:routed] : nil;
    if (u) MSBHLLog([NSString stringWithFormat:@"link %@ (Shuffle's) -> %@", url.absoluteString, routed]);
    %orig(u ?: url, animated, fromSearch, completion);
}
%end
%end

// The pages' link calls (PSListController's, inherited), each hooked only with the types StatusBarSettingsRow.x takes them with (the completion a
// block, or typed as an object).
static BOOL MSBHLTypes(Class c, const char *sel, NSArray<NSString *> *types) {
    Method m = c ? class_getInstanceMethod(c, sel_registerName(sel)) : NULL;
    if (!m) return NO;
    NSMutableString *bare = [NSMutableString string];
    for (const char *p = method_getTypeEncoding(m) ?: ""; *p; p++) if (!isdigit((unsigned char)*p)) [bare appendFormat:@"%c", *p];
    return [types containsObject:bare];
}
static void MSBHLTryInit(void) {
    static BOOL done; if (done) return;
    Class battery = objc_getClass("BatteryUIController"), health = objc_getClass("BatteryHealthUIController");
    if (!battery || !health) return;
    done = YES;
    NSArray *urlTypes = @[@"v@:@@?", @"v@:@@"];
    BOOL url = MSBHLTypes(battery, "handleURL:withCompletion:", urlTypes) && MSBHLTypes(health, "handleURL:withCompletion:", urlTypes);
    BOOL prepare = MSBHLTypes(battery, "prepareHandlingURLForSpecifierID:resourceDictionary:animatePush:withCompletion:", @[@"B@:@@^B@?", @"B@:@@^B@"]);
    if (!url || !class_getInstanceMethod(battery, @selector(specifiers))) { MSBHLLog(@"no link handler of the types read: links stay as they are"); return; }   // (a page we do not know)
    %init(MSBHLBattery);
    if (prepare) %init(MSBHLPrepare);
    %init(MSBHLHealth);
    MSBHLLog([NSString stringWithFormat:@"installed (prepare step %@)", prepare ? @"yes" : @"no"]);
}
static void MSBHLBundleLoaded(CFNotificationCenterRef center, void *observer, CFNotificationName name, const void *object, CFDictionaryRef info) { MSBHLTryInit(); }
static void MSBHLImageAdded(const struct mach_header *mh, intptr_t slide) {
    static BOOL queued; if (queued || !objc_getClass("BatteryHealthUIController")) return;
    queued = YES; dispatch_async(dispatch_get_main_queue(), ^{ MSBHLTryInit(); });
}
%ctor {
    {   // (Shuffle's misrouted link taken back from Settings' start: the link is what brings the Battery page in. 15-17; the types as the debug
        //  hook in StatusBarSettingsRow.x takes them)
        Class app = objc_getClass("PreferencesAppController");
        if (MSBHLTypes(app, "processURL:animated:fromSearch:withCompletion:", @[@"v@:@BB@?", @"v@:@BB@"])) %init(MSBHLShuffle);
    }
    MSBHLTryInit();
    CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), NULL, MSBHLBundleLoaded, (__bridge CFStringRef)NSBundleDidLoadNotification, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    _dyld_register_func_for_add_image(MSBHLImageAdded);
}
