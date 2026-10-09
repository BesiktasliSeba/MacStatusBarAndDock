// TweakSearch.x -- tweak settings in the Settings search and in Spotlight (MacStatusBar&Dock 1.4.3). Settings.
//  - Settings search ("Include Tweak Settings", while "Search Field in Settings" is on): the pages tweaks add to Settings (PreferenceLoader), their
//    rows, our own pages' rows and our own rows of the main list are listed under Apple's results, in Apple's results list with Apple's look:
//    one section per page with its icon, each row with Apple's breadcrumb. Apple's results stay first and untouched. In the sidebar's field and
//    in Apple's own search bar (a narrow window) alike.
//  - Spotlight ("Tweak Settings" in the Spotlight group of the Status Bar page): the same rows donated into Settings' own CoreSpotlight index
//    (common/TweakSpotlight.h; spot-143's Spotlight hook lists them in a section after Apple's, else Spotlight ranks them with the lowest hint).
//    Off: everything donated is deleted.
// One index for both: common/TweakIndex.h (reads PreferenceLoader's entry plists and the bundles' plists and strings; no bundle is loaded).
//
// Read in Apple's binaries (15.6.1 19G82, 16.7.7 20H330, 17.5.1 21F90; the same design on all three):
//  - the Settings query (PSCoreSpotlightIndexer -topHitSearchForString:...) hands Apple's results controller (SUIKSearchResultsCollectionViewController)
//    the items it found (-searchQueryFoundItems:, on the query's own queue), then -searchQueryCompleted (main queue). Found items REPLACE what is
//    shown; a query that finds nothing hands over nothing (and -searchQueryCompleted is empty: the older results stay). -setResults: waits for the
//    main queue (dispatch_sync) when there are results, so a hand-over must never come from the main thread. The controller shows one section per
//    item category (attributeSet.theme), asks its delegate (the sidebar list) for the order of the categories, their icons and whether to show
//    them, and sorts a section by ranking hint, then title;
//  - picking a result: the delegate's -searchResultsCollectionViewController:didSelectURL: -> -[PreferencesAppController processURL:animated:
//    fromSearch:]; a Spotlight result of Settings opens Settings with the CoreSpotlight activity, whose item identifier Settings turns into a URL
//    for that same method. Our identifiers become Settings' own URLs there (TweakIndex.h MTIPrefsURL: Apple's form, pages in "path", the row after
//    "#"), and Apple's URL manager opens the pages and scrolls to the row (Shuffle's own rewrite finds the pages it moved into its Tweaks list).
// Defensive: every private class and method is checked once at load (TweakSearchCheck.h); a mismatch and that part is not hooked (the Settings
// search as before; nothing donated). Our identifiers all start with "msbd-tweaksetting:".
#import <UIKit/UIKit.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <pthread.h>
#import <stdatomic.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static void MTSLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    NSData *d = [[NSString stringWithFormat:@"[tweaks] %@\n", line] dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];   // (never -UTF8String: NULL for a tweak's text without a UTF-8 form)
    if (d.length) fwrite(d.bytes, 1, d.length, f);
    fclose(f);
#else
    (void)line;
#endif
}
#define MTS_LOG(...) MTSLog(__VA_ARGS__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../common/TweakSpotlight.h"
#import "TweakSearchCheck.h"   // (SidebarSearch.x's check functions come with it; this file uses only its own)
#pragma clang diagnostic pop

#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

@interface PSUIPrefsListController : UIViewController
@end
@interface PreferencesAppController : UIApplication
@end
BOOL MSPointerDeviceAttached(void);   // PointerSettings.x
BOOL MSKeyboardAttached(void);        // KeyboardSettings.x

static const NSUInteger kMTSMaxResults = 100;   // (rows of ours in one Settings search, at most)

// ---- the check ------------------------------------------------------------------------------------------------------------------------------
static Class gMTSList, gMTSResults, gMTSApp;
static BOOL gMTSResultsOK, gMTSOpeningOK;
static NSString *gMTSWhyResults, *gMTSWhyOpening;

// ---- state (read from the query's queue too: atomics, and the index behind a lock) -----------------------------------------------------------
static _Atomic bool gMTSSearchOn;     // "Search Field in Settings" and "Include Tweak Settings"
static _Atomic bool gMTSSpotOn;       // "Tweak Settings" (Spotlight)
static os_unfair_lock gMTSLock = OS_UNFAIR_LOCK_INIT;
static NSArray<MTIEntry *> *gMTSIndex;                         // (guarded) the last index built
static NSDictionary<NSString *, MTIEntry *> *gMTSPanes;        // (guarded) category -> the page's own entry (title, icon)
static NSString *gMTSQuery;                                    // (guarded) the text of the Settings search now running
static _Atomic uint64_t gMTSGeneration, gMTSDelivered;         // a query per generation; the generation found items were last handed over for
static _Atomic uint64_t gMTSForceGen;                          // a generation whose (empty) result is handed over even with the switch off
static dispatch_queue_t gMTSQueue;                             // builds and donations, one at a time
static pthread_mutex_t gMTSDeliverLock;                        // (recursive) one hand-over of found items at a time: Apple's and ours
static __weak UIViewController *gMTSListSeen;                  // the sidebar list last searched
static NSCache<NSString *, UIImage *> *gMTSIcons;

static NSArray<MTIEntry *> *MTSIndex(void) { os_unfair_lock_lock(&gMTSLock); NSArray *a = gMTSIndex; os_unfair_lock_unlock(&gMTSLock); return a; }
static NSString *MTSQueryText(void) { os_unfair_lock_lock(&gMTSLock); NSString *q = gMTSQuery; os_unfair_lock_unlock(&gMTSLock); return q; }
static BOOL MTSIsOurs(id s) { return [s isKindOfClass:[NSString class]] && [(NSString *)s hasPrefix:kMTIPrefix]; }
static void MTSReadSwitches(void) {
    atomic_store(&gMTSSearchOn, MTSBool(CFSTR("sidebarSearch"), kMTSSettingsDomain, YES) && MTSBool(CFSTR("sidebarTweaks"), kMTSSettingsDomain, NO));
    atomic_store(&gMTSSpotOn, MTSSpotlightSwitch());
}

// ---- the loop guard ---------------------------------------------------------------------------------------------------------------------------
// The index (and the donation) is built a moment after every Settings start. Should that ever crash Settings -- a tweak's malformed text once did
// (1.4.3 external test H-1) -- it would crash at every start and the switches could not be reached. A mark kept while that work runs counts the
// starts that ended during it; after two in a row, both switches that build the index (Include Tweak Settings and Spotlight's Tweak Settings) are
// turned off, as the crash guard turns a part off for SpringBoard.
static void MTSGuardMark(BOOL busy) {
    CFPreferencesSetAppValue(CFSTR("tweakIndexBusy"), busy ? kCFBooleanTrue : NULL, kMTSSettingsDomain);
    if (!busy) CFPreferencesSetAppValue(CFSTR("tweakIndexDeaths"), NULL, kMTSSettingsDomain);
    CFPreferencesAppSynchronize(kMTSSettingsDomain);
}
static void MTSGuardAtStart(void) {   // (%ctor: did the last start end while it built the index?)
    if (!MTSBool(CFSTR("tweakIndexBusy"), kMTSSettingsDomain, NO)) return;
    int deaths = 0;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("tweakIndexDeaths"), kMTSSettingsDomain);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &deaths);
    if (v) CFRelease(v);
    deaths++;
    CFPreferencesSetAppValue(CFSTR("tweakIndexBusy"), NULL, kMTSSettingsDomain);
    CFPreferencesSetAppValue(CFSTR("tweakIndexDeaths"), deaths >= 2 ? NULL : (__bridge CFNumberRef)@(deaths), kMTSSettingsDomain);
    if (deaths >= 2) CFPreferencesSetAppValue(CFSTR("sidebarTweaks"), kCFBooleanFalse, kMTSSettingsDomain);
    CFPreferencesAppSynchronize(kMTSSettingsDomain);
    if (deaths < 2) { MTSLog(@"guard: the last start ended while it built the index (once)"); return; }
    CFPreferencesSetValue(CFSTR("spotlightTweakSettings"), kCFBooleanFalse, kMTSBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(kMTSBarDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    notify_post("com.besiktasliseba.macsettings/searchChanged");
    notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
    MTSLog(@"guard: two starts in a row ended while they built the index: Include Tweak Settings and Spotlight's Tweak Settings switched off");
}

// ---- building the index ---------------------------------------------------------------------------------------------------------------------
static void MTSRequery(BOOL force);
// The index (off the main thread) when a switch needs it; then the Spotlight donation brought up to date (also deleted when switched off).
// The Settings search also finds Pointer and Keyboard (our pages while a trackpad / keyboard is attached); the donation never has them.
static void MTSRebuild(NSString *why) {
    BOOL search = atomic_load(&gMTSSearchOn), spot = atomic_load(&gMTSSpotOn) && gMTSOpeningOK;
    if (!search && !spot) { dispatch_async(gMTSQueue, ^{ MTSSyncSpotlight(nil, NO, why); }); return; }
    MTIConfig *donated = MTSBaseConfig(), *cfg = MTSBaseConfig();
    NSMutableArray *x = [cfg.extras mutableCopy];
    if (MSPointerDeviceAttached()) [x addObject:@{@"id": @"MAC_POINTER", @"title": @"Pointer", @"page": @YES}];
    if (MSKeyboardAttached()) [x addObject:@{@"id": @"MAC_KEYBOARD", @"title": @"Keyboard", @"page": @YES}];
    BOOL same = x.count == cfg.extras.count;
    cfg.extras = x;
    dispatch_async(gMTSQueue, ^{
        @autoreleasepool {
            MTSGuardMark(YES);
            CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
            NSArray<MTIEntry *> *all = MTIBuild(cfg);
            NSMutableDictionary *panes = [NSMutableDictionary dictionary];
            for (MTIEntry *e in all) if (e.depth == 1 && !panes[e.category]) panes[e.category] = e;
            os_unfair_lock_lock(&gMTSLock); gMTSIndex = all; gMTSPanes = panes; os_unfair_lock_unlock(&gMTSLock);
            MTSLog([NSString stringWithFormat:@"index built (%@): %lu rows, %lu pages, %.0f ms", why, (unsigned long)all.count, (unsigned long)panes.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000]);
            dispatch_async(dispatch_get_main_queue(), ^{ MTSRequery(NO); });
            if (spot) DM_FEATURE_MARK("spotlight-tweak-settings");
            MTSSyncSpotlight(spot ? (same ? all : MTIBuild(donated)) : nil, spot, why);
            MTSGuardMark(NO);
        }
    });
}

// ---- the Settings search ----------------------------------------------------------------------------------------------------------------------
// Apple's items as they came, without any of ours that the Spotlight donation put into Settings' index (those are listed by the lines below
// instead, only with the switch on, after Apple's), plus ours that match the text typed. On the query's queue, under gMTSDeliverLock.
static NSArray *MTSMerge(id controller, NSArray *items) {
    id delegate = [controller respondsToSelector:@selector(delegate)] ? ((id (*)(id, SEL))objc_msgSend)(controller, @selector(delegate)) : nil;
    if (![delegate isKindOfClass:gMTSList] || ![items isKindOfClass:[NSArray class]]) return items;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:items.count];
    NSUInteger dropped = 0;
    for (id it in items) {
        NSString *uid = [it isKindOfClass:[CSSearchableItem class]] ? ((CSSearchableItem *)it).uniqueIdentifier : nil;
        if (MTSIsOurs(uid)) { dropped++; continue; }
        [out addObject:it];
    }
    NSUInteger added = 0;
    NSString *q = MTSQueryText();
    if (atomic_load(&gMTSSearchOn) && q.length) {
        for (MTIEntry *e in MTIMatch(MTSIndex(), q, kMTSMaxResults)) { [out addObject:MTSItem(e, NO, nil)]; added++; }
    }
    atomic_store(&gMTSDelivered, atomic_load(&gMTSGeneration));
    if (added || dropped) MTSLog([NSString stringWithFormat:@"results: Apple's %lu, ours %lu (dropped %lu donated)", (unsigned long)(out.count - added), (unsigned long)added, (unsigned long)dropped]);
    return out;
}
// The query found nothing of Apple's (it handed over nothing): ours alone, if any match -- or, after a switch change, nothing (so no row of ours
// stays). Handed over the way Apple's query does it, off the main thread (-setResults: waits for the main queue: on the main thread it would
// deadlock -- two Settings crashes on 16.7.7 with the first build), never over a newer query's results: only while this query is still the
// current one and nothing was handed over for it, under the lock Apple's hand-overs take too.
static void MTSCompleted(id controller) {
    uint64_t gen = atomic_load(&gMTSGeneration);
    BOOL forced = atomic_load(&gMTSForceGen) == gen;
    if ((!atomic_load(&gMTSSearchOn) && !forced) || atomic_load(&gMTSDelivered) == gen || !MTSQueryText().length) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        pthread_mutex_lock(&gMTSDeliverLock);
        if (atomic_load(&gMTSGeneration) == gen && atomic_load(&gMTSDelivered) != gen && (atomic_load(&gMTSSearchOn) || atomic_load(&gMTSForceGen) == gen))
            ((void (*)(id, SEL, id))objc_msgSend)(controller, @selector(searchQueryFoundItems:), @[]);
        pthread_mutex_unlock(&gMTSDeliverLock);
    });
}
// The search showing now runs again: the index came after its first query, or a switch changed (force: then its result is handed over even when
// it is empty, so rows of ours shown before the switch went off go away).
static void MTSRequery(BOOL force) {
    UIViewController *list = gMTSListSeen;
    if (!list || !gMTSResultsOK || (!force && !atomic_load(&gMTSSearchOn))) return;
    id sc = ((id (*)(id, SEL))objc_msgSend)(list, @selector(spotlightSearchController));
    UISearchBar *bar = [sc isKindOfClass:[UISearchController class]] ? ((UISearchController *)sc).searchBar : nil;
    if (!bar.text.length) return;
    if (force) atomic_store(&gMTSForceGen, atomic_load(&gMTSGeneration) + 1);   // (the generation the call below starts)
    ((void (*)(id, SEL, id))objc_msgSend)(list, @selector(updateSearchResultsForSearchController:), sc);
    MTSLog(force ? @"search run again (a switch changed)" : @"search run again with the new index");
}
static NSComparisonResult MTSComparePanes(NSString *a, NSString *b) {
    os_unfair_lock_lock(&gMTSLock); NSString *ta = gMTSPanes[a].title, *tb = gMTSPanes[b].title; os_unfair_lock_unlock(&gMTSLock);
    return [(ta ?: a) localizedCaseInsensitiveCompare:(tb ?: b)];
}
static UIImage *MTSIconForCategory(NSString *category) {   // (main thread: the section header asks)
    UIImage *hit = [gMTSIcons objectForKey:category];
    if (hit) return hit;
    os_unfair_lock_lock(&gMTSLock); NSString *path = gMTSPanes[category].iconPath; os_unfair_lock_unlock(&gMTSLock);
    UIImage *img = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (img.size.width > 0) {   // (a page icon at the size of Apple's, 29 pt)
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29, 29)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [img drawInRect:CGRectMake(0, 0, 29, 29)]; }];
        [gMTSIcons setObject:img forKey:category];
    }
    return img;
}

// ---- opening a result -----------------------------------------------------------------------------------------------------------------------
// Shuffle moves tweak pages into its own Tweaks list and finds them again by rewriting Settings URLs ("root=<page>" -> "root=Tweaks&path=<page>"),
// but only in the one-argument -[PreferencesAppController processURL:], which a search result never passes through (Apple's results and
// Spotlight call -processURL:animated:fromSearch:), and its rewrite does not expect a path already there (it made "path=Lynx&path=LOCKSCREEN...").
// So its own rewrite is asked about the page alone, and our pages and row are joined after it: "prefs:root=Tweaks&path=Lynx/LOCKSCREEN#..."
// (15.6.1 M1, 9 Oct). Without Shuffle, or for a page it did not move: the URL as it was.
static NSString *MTSShuffleRoute(NSString *prefs) {
    SEL shuffle = NSSelectorFromString(@"_shuffle_preprocessURL:");
    id app = [UIApplication sharedApplication];
    if (![prefs hasPrefix:@"prefs:root="] || ![app respondsToSelector:shuffle]) return prefs;
    NSString *rest = [prefs substringFromIndex:@"prefs:root=".length];
    NSUInteger cut = rest.length;
    for (NSString *mark in @[@"&", @"#", @"%23"]) { NSRange r = [rest rangeOfString:mark]; if (r.location != NSNotFound) cut = MIN(cut, r.location); }
    NSString *root = [rest substringToIndex:cut], *tail = [rest substringFromIndex:cut];
    if ([root hasPrefix:@"ROOT"] || !root.length) return prefs;   // (a row of the main list: not one of Shuffle's)
    NSURL *probe = [NSURL URLWithString:[@"prefs:root=" stringByAppendingString:root]];
    id r = nil;
    @try { r = probe ? ((id (*)(id, SEL, id))objc_msgSend)(app, shuffle, probe) : nil; } @catch (NSException *e) { r = nil; }
    NSString *rs = [r isKindOfClass:[NSURL class]] ? [(NSURL *)r absoluteString] : [r isKindOfClass:[NSString class]] ? r : nil;
    NSRange p = [rs rangeOfString:@"&path="];
    if (!rs || [rs isEqualToString:probe.absoluteString] || ![rs hasPrefix:@"prefs:root="] || p.location == NSNotFound) return prefs;   // (not moved by Shuffle)
    NSString *group = [rs substringWithRange:NSMakeRange(11, p.location - 11)], *page = [rs substringFromIndex:NSMaxRange(p)];
    group = MTIEnc(group.stringByRemovingPercentEncoding ?: group); page = MTIEnc(page.stringByRemovingPercentEncoding ?: page);   // (Shuffle hands them back decoded)
    NSString *below = @"", *row = @"";
    if ([tail hasPrefix:@"&path="]) {
        NSString *t = [tail substringFromIndex:6];
        NSUInteger c2 = t.length;
        for (NSString *mark in @[@"#", @"%23", @"&"]) { NSRange m = [t rangeOfString:mark]; if (m.location != NSNotFound) c2 = MIN(c2, m.location); }
        below = [@"/" stringByAppendingString:[t substringToIndex:c2]];
        row = [t substringFromIndex:c2];
    } else row = tail;
    NSString *routed = [NSString stringWithFormat:@"prefs:root=%@&path=%@%@%@", group, page, below, row];
    MTSLog([NSString stringWithFormat:@"Shuffle has the page in its list: %@", routed]);
    return routed;
}
// One of our identifiers as Settings' own URL; nil for anything else (Apple's URLs pass untouched). A page that is no longer there (its tweak
// removed since the donation) opens nothing; the index and the donation are brought up to date.
static NSURL *MTSOpenURL(NSURL *url, NSString *from) {
    NSString *s = [url isKindOfClass:[NSURL class]] ? url.absoluteString : nil;
    NSString *prefs = MTIPrefsURL(s);
    if (!prefs) return nil;
    NSString *pane = MTIPaneOf(s);
    NSArray *idx = MTSIndex();
    BOOL known = NO;
    for (MTIEntry *e in idx) if (MTISameUID(e.uid, s) || [e.paneID isEqualToString:pane] || [[@"ROOT#" stringByAppendingString:e.path.firstObject ?: @"?"] isEqualToString:pane]) { known = YES; break; }
    if (!known && idx) MTSRebuild(@"a result of a page that is gone");
    NSString *routed = MTSShuffleRoute(prefs);
    MTSLog([NSString stringWithFormat:@"open (%@): %@ -> %@%@", from, s, routed, known || !idx ? @"" : @" (not in the index now)"]);
    return [NSURL URLWithString:routed] ?: [NSURL URLWithString:prefs];
}

// ---- refresh: the folders tweaks install into ----------------------------------------------------------------------------------------------
// A tweak installed or removed while Settings is open changes PreferenceLoader's folder (its entry plist) or the bundles folder: the index is
// built again 2 s after the last change. (Settings started later builds it anyway; SpringBoard keeps the donation current while Settings is closed.)
static void MTSWatch(NSString *dir) {
    int fd = open(dir.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK, dispatch_get_main_queue());
    static NSUInteger pending = 0;
    dispatch_source_set_event_handler(src, ^{
        NSUInteger mine = ++pending;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (mine == pending) MTSRebuild(@"a tweak was installed or removed"); });
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    static NSMutableArray *keep; if (!keep) keep = [NSMutableArray array];
    [keep addObject:src];
}

// ---- debug builds: test commands (from SidebarSearch.x's test channel: "tweaks <command>") ---------------------------------------------------
BOOL MTSTestCommand(NSString *cmd) {
#if DEBUG
    if (![cmd hasPrefix:@"tweaks"]) return NO;
    NSString *c = [[cmd substringFromIndex:6] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([c isEqualToString:@"state"]) {
        NSArray *idx = MTSIndex();
        MTSLog([NSString stringWithFormat:@"state: results check %@, opening check %@, search %d, spotlight %d, index %@, donated %@ at %@, query %lu chars, gen %llu delivered %llu",
            gMTSResultsOK ? @"ok" : gMTSWhyResults, gMTSOpeningOK ? @"ok" : gMTSWhyOpening, atomic_load(&gMTSSearchOn), atomic_load(&gMTSSpotOn), idx ? @(idx.count) : @"none",
            MTSStoredString(CFSTR("tweakSpotlightHash")) ?: @"nothing", MTSStoredString(CFSTR("tweakSpotlightDate")) ?: @"-", (unsigned long)MTSQueryText().length, atomic_load(&gMTSGeneration), atomic_load(&gMTSDelivered)]);
    } else if ([c isEqualToString:@"rebuild"]) MTSRebuild(@"test");
    else if ([c hasPrefix:@"match "]) {   // the rows the Settings search would add for a text (titles only)
        NSMutableString *o = [NSMutableString string];
        for (MTIEntry *e in MTIMatch(MTSIndex(), [c substringFromIndex:6], 30)) [o appendFormat:@" | %@ <%@>", e.title, e.crumb ?: @""];
        MTSLog([@"match:" stringByAppendingString:o]);
    } else if ([c hasPrefix:@"panes"]) {   // every page in the index with its row count
        NSCountedSet *n = [NSCountedSet set]; for (MTIEntry *e in MTSIndex()) [n addObject:e.paneTitle ?: @"?"];
        NSMutableString *o = [NSMutableString string];
        for (NSString *p in [n.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) [o appendFormat:@" | %@ %lu", p, (unsigned long)[n countForObject:p]];
        MTSLog([@"panes:" stringByAppendingString:o]);
    } else if ([c hasPrefix:@"uid "]) {   // the identifier of the first row matching a text
        MTIEntry *e = MTIMatch(MTSIndex(), [c substringFromIndex:4], 1).firstObject;
        MTSLog([NSString stringWithFormat:@"uid: %@", e.uid ?: @"none"]);
    } else if ([c hasPrefix:@"spotopen "]) {   // as Spotlight opens a result: Settings' own activity path with the first row matching a text
        MTIEntry *e = MTIMatch(MTSIndex(), [c substringFromIndex:9], 1).firstObject;
        if (!e) { MTSLog(@"spotopen: no row"); return YES; }
        NSUserActivity *a = [[NSUserActivity alloc] initWithActivityType:CSSearchableItemActionType];
        a.userInfo = @{CSSearchableItemActivityIdentifier: e.uid};
        SEL s = NSSelectorFromString(@"receivedApplicationContinueUserActivity:");
        id app = [UIApplication sharedApplication];
        if ([app respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(app, s, a);
        MTSLog([NSString stringWithFormat:@"spotopen: %@ (%@)", e.uid, [app respondsToSelector:s] ? @"through Settings' activity path" : @"no activity path"]);
    } else MTSLog(@"test: unknown tweaks command");
    return YES;
#else
    return NO;
#endif
}

%group MTSResultsHooks
%hook PSUIPrefsListController
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *text = [controller isKindOfClass:[UISearchController class]] ? [controller.searchBar.text copy] : nil;
    os_unfair_lock_lock(&gMTSLock); gMTSQuery = text; os_unfair_lock_unlock(&gMTSLock);
    atomic_fetch_add(&gMTSGeneration, 1);
    gMTSListSeen = (UIViewController *)self;
    %orig;
}
- (BOOL)searchResultsCollectionViewController:(id)controller shouldShowCategory:(NSString *)category {
    if (MTSIsOurs(category)) return atomic_load(&gMTSSearchOn);
    return %orig;
}
- (long long)searchResultsCollectionViewController:(id)controller sortCategory1:(NSString *)a sortCategory2:(NSString *)b {
    BOOL oa = MTSIsOurs(a), ob = MTSIsOurs(b);
    if (oa && ob) return MTSComparePanes(a, b);
    if (oa) return NSOrderedDescending;   // (Apple's sections first, ours after them)
    if (ob) return NSOrderedAscending;
    return %orig;
}
- (id)searchResultsCollectionViewController:(id)controller iconForCategory:(NSString *)category {
    if (!MTSIsOurs(category)) return %orig;
    id apple = %orig(controller, [category substringFromIndex:kMTIPrefix.length]);   // (the icon of the page's own row in the main list, as Apple finds it)
    return apple ?: MTSIconForCategory(category);
}
- (void)searchResultsCollectionViewController:(id)controller didSelectURL:(NSURL *)url {
    NSURL *open = MTSOpenURL(url, @"Settings search");
    %orig(controller, open ?: url);
}
%end
%hook SUIKSearchResultsCollectionViewController
- (void)searchQueryFoundItems:(NSArray *)items {
    pthread_mutex_lock(&gMTSDeliverLock);
    %orig(MTSMerge(self, items));
    pthread_mutex_unlock(&gMTSDeliverLock);
}
- (void)searchQueryCompleted {
    %orig;
    MTSCompleted(self);
}
%end
%end

%group MTSOpeningHooks
%hook PreferencesAppController
- (void)processURL:(NSURL *)url animated:(BOOL)animated fromSearch:(BOOL)fromSearch withCompletion:(id)completion {
    NSURL *open = MTSOpenURL(url, @"Spotlight");
    %orig(open ?: url, animated, fromSearch, completion);
}
%end
%end

%ctor {
    gMTSList = objc_getClass("PSUIPrefsListController");
    gMTSResults = objc_getClass("SUIKSearchResultsCollectionViewController");
    gMTSApp = objc_getClass("PreferencesAppController");
    NSMutableArray *why = [NSMutableArray array];
    MTSCheckResults(gMTSList, gMTSResults, why);
    gMTSResultsOK = why.count == 0; gMTSWhyResults = [why componentsJoinedByString:@"; "];
    why = [NSMutableArray array];
    MTSCheckOpening(gMTSApp, why);
    gMTSOpeningOK = why.count == 0 && MTSSpotIndex() != nil; gMTSWhyOpening = why.count ? [why componentsJoinedByString:@"; "] : (gMTSOpeningOK ? nil : @"no CoreSpotlight index");
    gMTSQueue = dispatch_queue_create("com.besiktasliseba.macsettings.tweaksearch", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    pthread_mutexattr_t ma; pthread_mutexattr_init(&ma); pthread_mutexattr_settype(&ma, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&gMTSDeliverLock, &ma); pthread_mutexattr_destroy(&ma);
    gMTSIcons = [NSCache new];
    if (gMTSResultsOK) { DM_FEATURE_MARK("settings-tweak-search"); %init(MTSResultsHooks); }
    if (gMTSOpeningOK) %init(MTSOpeningHooks);
    MTSLog([NSString stringWithFormat:@"check: results %@, opening %@", gMTSResultsOK ? @"ok" : gMTSWhyResults, gMTSOpeningOK ? @"ok" : gMTSWhyOpening]);
    MTSGuardAtStart();
    MTSReadSwitches();
    void (^changed)(int) = ^(int t) {
        BOOL search = atomic_load(&gMTSSearchOn), spot = atomic_load(&gMTSSpotOn);
        MTSReadSwitches();
        if (search == atomic_load(&gMTSSearchOn) && spot == atomic_load(&gMTSSpotOn)) return;
        MTSLog([NSString stringWithFormat:@"switches: search %d, spotlight %d", atomic_load(&gMTSSearchOn), atomic_load(&gMTSSpotOn)]);
        if (search != atomic_load(&gMTSSearchOn)) MTSRequery(YES);   // (rows of ours on screen go, or come, at once)
        MTSRebuild(@"a switch changed");
    };
    int t1 = 0, t2 = 0;
    notify_register_dispatch("com.besiktasliseba.macsettings/searchChanged", &t1, dispatch_get_main_queue(), changed);
    notify_register_dispatch("com.besiktasliseba.macstatusbar/prefsChanged", &t2, dispatch_get_main_queue(), changed);
    MTSWatch(kMTSPLDir);
    MTSWatch(kMTSBundleDir);
    // (a moment after Settings starts: the index, and the donation brought up to date -- also deleted if it was switched off elsewhere)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTSRebuild(@"Settings started"); });
}
