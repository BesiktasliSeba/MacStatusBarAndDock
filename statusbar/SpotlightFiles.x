// SpotlightFiles.x -- SpringBoard's part of the Spotlight additions of 1.4.3 (the Spotlight group of the Status Bar page; each off unless on).
//  1. "Desktop and Downloads" (spotlightFiles): files in our Finder's Desktop folder (On My iPad/Desktop) and in Downloads (On My iPad/Downloads,
//     iCloud Drive/Downloads) reach Spotlight at once.
//     Root cause: Spotlight's file results are the File Provider's own index (On My iPad: com.apple.FileProvider.LocalStorage), and the File
//     Provider indexes a file when something asks it about the file -- the Files app showing it. A file saved straight into the folder (by our
//     Finder, by Safari, by an app; coordinated write or not) was not in that index until then. So when a file appears or changes there,
//     SpringBoard asks the File Provider about it, as the Files app does (FPItemManager -fetchItemForURL:; SpringBoard has
//     com.apple.fileprovider.fetch-url): on 15.6.1 it was in Spotlight about 6 s later -- Apple's own result in Apple's own Files section, opened
//     by Files. A file removed is dropped from the index by listing its folder through the File Provider. With Files excluded from Search
//     (Settings > Siri & Search > Files) nothing is done: Spotlight shows no files then. That setting is read again whenever Settings changes it
//     (it posts com.apple.spotlightui.prefschanged, 15 and 16), so turning Files back on starts at once.
//     iPadOS 16 (16.7.7, best effort): the lookup takes the file in (an item of com.apple.FileProvider.LocalStorage, listed by a Files-style
//     enumeration), but it did not reach the index within 4.5 minutes with Files allowed in Search, nor after the daemon's indexing scheduler was
//     forced (debug probe "fpindex" below). There the index is brought up to date later, on the system's own schedule.
//  2. "Tweak Settings" (spotlightTweakSettings) while Settings is closed: the rows Settings donates (common/TweakSpotlight.h) brought up to date
//     when a tweak is installed or removed, and once a short while after SpringBoard starts (a tweak installed with a respring); written into
//     Settings' own index (CoreSpotlight's bundle identifier initializer; SpringBoard has com.apple.private.corespotlight.internal).
//  3. MacStatusBar&Dock removed: the root helper's --uninstall posts kMTSRemoveAllNote; every row we donated is deleted (nothing of ours stays in
//     Spotlight after the removal).
#import <UIKit/UIKit.h>
#import <CoreSpotlight/CoreSpotlight.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static void SFLog(NSString *line) {   // (debug builds only)
#if DEBUG
    if (access("/tmp/macstatusbar-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macstatusbar.log", "a"); if (!f) return;
    NSData *d = [[NSString stringWithFormat:@"[spotfiles] %@\n", line] dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];   // (never -UTF8String: NULL for a tweak's text without a UTF-8 form)
    if (d.length) fwrite(d.bytes, 1, d.length, f);
    fclose(f);
#else
    (void)line;
#endif
}
#define MTS_LOG(...) SFLog(__VA_ARGS__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#import "../common/TweakSpotlight.h"
#pragma clang diagnostic pop

#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see StatusBar.x)

static dispatch_queue_t gSFQueue;   // (one at a time: hand-overs to the File Provider, tweak index builds, donations)

// ==== 1. Desktop and Downloads ==================================================================================================================
static NSString *SFOnMyIPad(void) {   // (as Finder.h DMFinderOnMyIPad: the Files app's own storage)
    static NSString *found; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *root = @"/var/mobile/Containers/Shared/AppGroup";
        for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
            NSString *dir = [root stringByAppendingPathComponent:uuid];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([meta[@"MCMMetadataIdentifier"] isEqual:@"group.com.apple.FileProvider.LocalStorage"]) { found = [dir stringByAppendingPathComponent:@"File Provider Storage"]; break; }
        }
    });
    return found;
}
static BOOL SFIsDir(NSString *p) { struct stat st; return p && lstat(p.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode); }
static NSArray<NSString *> *SFFolders(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSString *mine = SFOnMyIPad();
    for (NSString *p in @[mine ? [mine stringByAppendingPathComponent:@"Desktop"] : @"", mine ? [mine stringByAppendingPathComponent:@"Downloads"] : @"",
                          @"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Downloads"])
        if (p.length && SFIsDir(p)) [out addObject:p];
    return out;
}
// The File Provider's own lookup of an item at a URL (what the Files app asks): nil when this iPadOS does not have it.
static id SFItemManager(void) {
    static id mgr; static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!objc_getClass("FPItemManager")) dlopen("/System/Library/Frameworks/FileProvider.framework/FileProvider", RTLD_LAZY);
        Class c = objc_getClass("FPItemManager");
        if (c && [c respondsToSelector:@selector(defaultManager)] && [c instancesRespondToSelector:NSSelectorFromString(@"fetchItemForURL:completionHandler:")])
            mgr = ((id (*)(id, SEL))objc_msgSend)(c, @selector(defaultManager));
    });
    return mgr;
}
// On gSFQueue: one file handed to the File Provider, waited for (5 s at most), so a folder full of files never floods fileproviderd.
static BOOL SFHandOver(NSString *path, NSString **detail) {
    id mgr = SFItemManager();
    if (!mgr) { if (detail) *detail = @"no File Provider lookup"; return NO; }
    DM_FEATURE_MARK("spotlight-files");
    __block id found = nil; __block NSError *err = nil;
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    ((void (*)(id, SEL, id, id))objc_msgSend)(mgr, NSSelectorFromString(@"fetchItemForURL:completionHandler:"), [NSURL fileURLWithPath:path],
        ^(id item, NSError *e) { found = item; err = e; dispatch_semaphore_signal(s); });
    BOOL inTime = dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0;
    if (detail) {
        NSString *dom = [found respondsToSelector:NSSelectorFromString(@"providerDomainID")] ? [found valueForKey:@"providerDomainID"] : nil;
        *detail = !inTime ? @"no answer" : err ? err.localizedDescription : [NSString stringWithFormat:@"item of %@", dom ?: @"?"];
    }
    return inTime && found && !err;
}
#if DEBUG
// (debug probe only, "fpindex": fileproviderd's indexing scheduler forced to run now. Not used by the feature: on 16.7.7 the assertion was given
// and started ("forced", stopped 15 s later) and the LocalStorage index still did not take the handed-over test file; on 15.6.1 the lookup alone
// is enough. What it does: the Files app makes that scheduler run while it is in front -- +[FPItemCollection addActiveCollection:] asks
// -[FPDaemonConnection forceIndexingInForeground:NO completionHandler:] for an indexing assertion (FPIndexingAssertion, -start / -stop) that
// forces the scheduler while the asking app is in the foreground; with forceForeground YES -start forces it at once
// (-[FPDDomainIndexerSchedulerAssertion start] -> -[FPDSharedScheduler forceRunningWithReason:]; needs com.apple.fileprovider.enumerate, which
// SpringBoard has). Stopped 15 s after the last ask; the daemon also stops it when the assertion goes away (its -dealloc calls -stop). The
// assertion handed back must be started: an earlier probe that only asked for it forced nothing. Next lead for 16: the LocalStorage index may be
// written by the provider's own FPSpotlightIndexer (FileProvider.framework) rather than by fileproviderd's domain indexer.)
static id gSFIndexing;             // (main queue) the started assertion (a proxy of fileproviderd's)
static BOOL gSFIndexingAsked;      // (main queue) asked for, no answer yet
static CFTimeInterval gSFIndexingUntil;
static void SFStopIndexing(void) {
    id a = gSFIndexing;
    gSFIndexing = nil;
    if (a && [a respondsToSelector:@selector(stop)]) ((void (*)(id, SEL))objc_msgSend)(a, @selector(stop));
    if (a) SFLog(@"index now: stopped");
}
static void SFIndexNow(NSString *why) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gSFIndexingUntil = CACurrentMediaTime() + 15.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (CACurrentMediaTime() >= gSFIndexingUntil) SFStopIndexing();   // (a later change keeps it on)
        });
        if (gSFIndexing || gSFIndexingAsked) return;
        Class conn = objc_getClass("FPDaemonConnection");
        SEL getProxy = NSSelectorFromString(@"sharedConnectionProxy"), force = NSSelectorFromString(@"forceIndexingInForeground:completionHandler:");
        id proxy = conn && [conn respondsToSelector:getProxy] ? ((id (*)(id, SEL))objc_msgSend)(conn, getProxy) : nil;
        if (!proxy) { SFLog(@"index now: no File Provider daemon connection"); return; }
        gSFIndexingAsked = YES;
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(proxy, force, YES, ^(id assertion, NSError *e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                gSFIndexingAsked = NO;
                BOOL usable = assertion && !e && [assertion respondsToSelector:@selector(start)] && [assertion respondsToSelector:@selector(stop)];
                if (!usable) { SFLog([NSString stringWithFormat:@"index now (%@): not given (%@)", why, e.localizedDescription ?: NSStringFromClass([assertion class]) ?: @"nothing"]); return; }
                if (CACurrentMediaTime() >= gSFIndexingUntil) return;   // (answered after its time: never started, released here)
                gSFIndexing = assertion;
                ((void (*)(id, SEL))objc_msgSend)(assertion, @selector(start));
                SFLog([NSString stringWithFormat:@"index now (%@): forced", why]);
            });
        });
    });
}
#endif
// A file removed from a folder stays in the File Provider's index until the folder is listed through it again (15.6.1: a deleted test file stayed
// until a Files-style listing of its folder took it out). So after a removal the folder is listed through it, as the Files app lists it (its
// collection observed for 3 s).
static NSMutableArray *gSFCollections;
static void SFRelistFolder(NSString *folder) {
    id mgr = SFItemManager();
    if (!mgr) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(mgr, NSSelectorFromString(@"fetchItemForURL:completionHandler:"), [NSURL fileURLWithPath:folder], ^(id item, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SEL make = NSSelectorFromString(@"collectionForFolderItem:");
            id col = item && [mgr respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)(mgr, make, item) : nil;
            if (!col || ![col respondsToSelector:@selector(startObserving)]) return;
            if (!gSFCollections) gSFCollections = [NSMutableArray array];
            [gSFCollections addObject:col];
            ((void (*)(id, SEL))objc_msgSend)(col, @selector(startObserving));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if ([col respondsToSelector:@selector(stopObserving)]) ((void (*)(id, SEL))objc_msgSend)(col, @selector(stopObserving));
                [gSFCollections removeObject:col];
                SFLog([NSString stringWithFormat:@"%@ listed through the File Provider (a file was removed)", folder.lastPathComponent]);
            });
        });
    });
}
static BOOL gSFFilesOn;
static NSMutableDictionary<NSString *, NSNumber *> *gSFSeen;   // (gSFQueue) file -> its time last handed over
// On gSFQueue: the folder's files that are new or changed since they were last handed over (all of them on the first look after the switch went
// on or SpringBoard started: files saved there earlier reach Spotlight too). Hidden files (".name") are not looked at.
static void SFScanFolder(NSString *folder, NSString *why) {
    if (!gSFSeen) gSFSeen = [NSMutableDictionary dictionary];
    NSUInteger handed = 0, failed = 0;
    NSMutableSet *present = [NSMutableSet set];
#if DEBUG
    // (device tests: with /tmp/msbd-spotfiles-testonly present only our own test files are handed over -- names starting with the prefix written in
    // it, "msbd-test" at the least -- and the owner's files are left alone; a test file named otherwise there is a control that is not handed over)
    NSString *testOnly = nil;
    if (access("/tmp/msbd-spotfiles-testonly", F_OK) == 0) {
        testOnly = [[NSString stringWithContentsOfFile:@"/tmp/msbd-spotfiles-testonly" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        if (![testOnly hasPrefix:@"msbd-test"]) testOnly = @"msbd-test";
    }
#endif
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil] ?: @[]) {
        if ([name hasPrefix:@"."]) continue;
#if DEBUG
        if (testOnly && ![name.lowercaseString hasPrefix:testOnly]) continue;
#endif
        NSString *p = [folder stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) != 0) continue;
        NSNumber *t = @((double)st.st_mtimespec.tv_sec + st.st_mtimespec.tv_nsec / 1e9);
        [present addObject:p];
        if ([gSFSeen[p] isEqual:t]) continue;
        NSString *detail = nil;
        if (SFHandOver(p, &detail)) { gSFSeen[p] = t; handed++; } else failed++;
#if DEBUG
        if ([name.lowercaseString containsString:@"msbd"]) SFLog([NSString stringWithFormat:@"handed over %@: %@", name, detail]);   // (only our test files are named)
#endif
    }
    NSUInteger removed = 0;
    for (NSString *p in gSFSeen.allKeys) if ([p.stringByDeletingLastPathComponent isEqualToString:folder] && ![present containsObject:p]) { [gSFSeen removeObjectForKey:p]; removed++; }
    if (handed || failed || removed) SFLog([NSString stringWithFormat:@"%@ (%@): %lu handed to the File Provider, %lu failed, %lu removed", folder.lastPathComponent, why, (unsigned long)handed, (unsigned long)failed, (unsigned long)removed]);
    if (removed) SFRelistFolder(folder);
}
static void SFScanAll(NSString *why) {
    dispatch_async(gSFQueue, ^{ @autoreleasepool { if (gSFFilesOn) for (NSString *f in SFFolders()) SFScanFolder(f, why); } });
}
// A folder watched while the switch is on: a write into it (a file added, removed or renamed) -> that folder looked at 0.5 s after the last one.
static NSMutableDictionary<NSString *, dispatch_source_t> *gSFWatches;
static void SFWatchFolders(BOOL on) {
    if (!gSFWatches) gSFWatches = [NSMutableDictionary dictionary];
    if (!on) { for (dispatch_source_t s in gSFWatches.allValues) dispatch_source_cancel(s); [gSFWatches removeAllObjects]; return; }
    for (NSString *folder in SFFolders()) {
        if (gSFWatches[folder]) continue;
        int fd = open(folder.fileSystemRepresentation, O_EVTONLY);
        if (fd < 0) continue;
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK, dispatch_get_main_queue());
        __block NSUInteger pending = 0;
        dispatch_source_set_event_handler(src, ^{
            NSUInteger mine = ++pending;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (mine != pending || !gSFFilesOn) return;
                dispatch_async(gSFQueue, ^{ @autoreleasepool { SFScanFolder(folder, @"changed"); } });
            });
        });
        dispatch_source_set_cancel_handler(src, ^{ close(fd); });
        dispatch_resume(src);
        gSFWatches[folder] = src;
    }
}
// Settings > Siri & Search > Files off ("Show Content in Search"): the person chose that Spotlight shows no files, so there is nothing to do (seen on
// the 16.7.7 test iPad: com.apple.DocumentsApp in SBSearchDisabledBundles, and nothing new reached the Files index).
static BOOL SFFilesExcludedFromSearch(void) {
    CFPreferencesAppSynchronize(CFSTR("com.apple.spotlightui"));
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("SBSearchDisabledBundles"), CFSTR("com.apple.spotlightui"));
    BOOL off = v && CFGetTypeID(v) == CFArrayGetTypeID() && [(__bridge NSArray *)v containsObject:@"com.apple.DocumentsApp"];
    if (v) CFRelease(v);
    return off;
}
static void SFReadFilesSwitch(NSString *why) {
    BOOL wanted = MTSBarInUse() && MTSBool(CFSTR("spotlightFiles"), kMTSBarDomain, NO), excluded = wanted && SFFilesExcludedFromSearch();   // (MTSBarInUse: TweakSpotlight.h)
    if (excluded) SFLog(@"Desktop and Downloads: Files is excluded from Search (Siri & Search), so nothing is handed over");
    BOOL on = wanted && !excluded && SFItemManager() != nil;
    if (on == gSFFilesOn) return;
    gSFFilesOn = on;
    SFWatchFolders(on);
    SFLog([NSString stringWithFormat:@"Desktop and Downloads %@ (%@), %lu folders", on ? @"on" : @"off", why, (unsigned long)gSFWatches.count]);
    if (on) SFScanAll(why);
    else dispatch_async(gSFQueue, ^{ [gSFSeen removeAllObjects]; });
}

// ==== 2. Tweak Settings while Settings is closed ================================================================================================
static void SFTweakRefresh(NSString *why) {
    dispatch_async(gSFQueue, ^{
        @autoreleasepool {
            if (!MTSSpotlightSwitch()) { MTSSyncSpotlight(nil, NO, why); return; }   // (off, also by the stock bar or the guards: a donation made before goes)
            CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
            NSArray<MTIEntry *> *all = MTIBuild(MTSBaseConfig());
            SFLog([NSString stringWithFormat:@"tweak index (%@): %lu rows, %.0f ms", why, (unsigned long)all.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000]);
            MTSSyncSpotlight(all, YES, why);
        }
    });
}
static void SFWatchTweaks(void) {   // (PreferenceLoader's folder and the bundles folder: a tweak installed or removed -> 5 s after the last change)
    static NSMutableArray *keep;
    if (keep) return;
    keep = [NSMutableArray array];
    static NSUInteger pending = 0;
    for (NSString *dir in @[kMTSPLDir, kMTSBundleDir]) {
        int fd = open(dir.fileSystemRepresentation, O_EVTONLY);
        if (fd < 0) continue;
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK, dispatch_get_main_queue());
        dispatch_source_set_event_handler(src, ^{
            NSUInteger mine = ++pending;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (mine == pending) SFTweakRefresh(@"a tweak was installed or removed"); });
        });
        dispatch_source_set_cancel_handler(src, ^{ close(fd); });
        dispatch_resume(src);
        [keep addObject:src];
    }
}

#if DEBUG
// ==== debug builds: a probe of Spotlight's index (echo '<command>' > /tmp/msbd-spotfiles-test, with /tmp/macstatusbar-debug present) =============
// Only results whose name or identifier contains "msbd" are printed (our test files, our donated rows); anything else is counted, never shown.
@interface CSSearchQuery (MSBDPrivate)
- (void)setBundleIDs:(NSArray *)ids;
@end
static NSMutableArray *gSFQueries;
static void SFQuery(NSString *bundles, NSString *query) {
    if (!gSFQueries) gSFQueries = [NSMutableArray array];
    CSSearchQuery *q = [[CSSearchQuery alloc] initWithQueryString:query attributes:@[@"displayName", @"title", @"contentType", @"contentURL", @"path"]];
    if (![bundles isEqualToString:@"*"] && [q respondsToSelector:@selector(setBundleIDs:)]) [q setBundleIDs:[bundles componentsSeparatedByString:@","]];
    __block NSUInteger total = 0, shown = 0;
    NSMutableString *lines = [NSMutableString string];
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    q.foundItemsHandler = ^(NSArray<CSSearchableItem *> *items) {
        for (CSSearchableItem *it in items) {
            total++;
            CSSearchableItemAttributeSet *a = it.attributeSet;
            NSString *name = a.displayName ?: a.title ?: @"";
            if (![name.lowercaseString containsString:@"msbd"] && ![it.uniqueIdentifier.lowercaseString containsString:@"msbd"]) continue;
            NSString *b = [it respondsToSelector:NSSelectorFromString(@"bundleID")] ? [it valueForKey:@"bundleID"] : @"?";
            if (++shown <= 20) [lines appendFormat:@"\n   %@ | %@ | bundle %@ | domain %@ | type %@", name, it.uniqueIdentifier, b, it.domainIdentifier ?: @"-", a.contentType ?: @"-"];
        }
    };
    __weak CSSearchQuery *wq = q;
    q.completionHandler = ^(NSError *e) {
        SFLog([NSString stringWithFormat:@"query (%@) [%@]: %lu found, %lu shown, %.0f ms%@%@", bundles, query, (unsigned long)total, (unsigned long)shown, (CFAbsoluteTimeGetCurrent() - t0) * 1000, e ? [@" error " stringByAppendingString:e.localizedDescription] : @"", lines]);
        dispatch_async(dispatch_get_main_queue(), ^{ CSSearchQuery *s = wq; if (s) [gSFQueries removeObject:s]; });
    };
    [gSFQueries addObject:q];
    [q start];
}
static void SFWrite(NSString *path, BOOL coordinated) {   // (a test file, written the way our Finder writes into File Provider storage, or raw)
    NSData *d = [@"MacStatusBar&Dock Spotlight test file\n" dataUsingEncoding:NSUTF8StringEncoding];
    __block BOOL ok = NO; __block NSError *e = nil;
    if (coordinated) {
        NSError *ce = nil;
        [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateWritingItemAtURL:[NSURL fileURLWithPath:path] options:NSFileCoordinatorWritingForReplacing error:&ce byAccessor:^(NSURL *u) { ok = [d writeToURL:u options:NSDataWritingAtomic error:&e]; }];
        if (ce) e = ce;
    } else ok = [d writeToFile:path options:NSDataWritingAtomic error:&e];
    SFLog([NSString stringWithFormat:@"write %@ (%@): %@%@", path.lastPathComponent, coordinated ? @"coordinated" : @"raw", ok ? @"ok" : @"failed", e ? [@" " stringByAppendingString:e.localizedDescription] : @""]);
}
static void SFRemove(NSString *path) {
    __block BOOL ok = NO; __block NSError *e = nil; NSError *ce = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateWritingItemAtURL:[NSURL fileURLWithPath:path] options:NSFileCoordinatorWritingForDeleting error:&ce byAccessor:^(NSURL *u) { ok = [[NSFileManager defaultManager] removeItemAtURL:u error:&e]; }];
    SFLog([NSString stringWithFormat:@"remove %@: %@%@", path.lastPathComponent, ok ? @"ok" : @"failed", (e ?: ce) ? [@" " stringByAppendingString:(e ?: ce).localizedDescription] : @""]);
}
static void SFOverride(BOOL add) {   // (can SpringBoard write into Settings' index? a test row, removed again)
    CSSearchableIndex *idx = MTSSpotIndex();
    if (!idx) { SFLog(@"override: no index"); return; }
    if (!add) { [idx deleteSearchableItemsWithIdentifiers:@[@"msbd-tweaksetting:root=MSBD_OVERRIDE_TEST"] completionHandler:^(NSError *e) { SFLog([NSString stringWithFormat:@"override delete: %@", e ? e.localizedDescription : @"ok"]); }]; return; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CSSearchableItemAttributeSet *a = [[CSSearchableItemAttributeSet alloc] initWithItemContentType:@"com.apple.Preferences.firstParty"];
#pragma clang diagnostic pop
    a.title = a.displayName = a.subject = @"msbd override test";
    CSSearchableItem *it = [[CSSearchableItem alloc] initWithUniqueIdentifier:@"msbd-tweaksetting:root=MSBD_OVERRIDE_TEST" domainIdentifier:kMTIDomain attributeSet:a];
    it.expirationDate = [NSDate dateWithTimeIntervalSinceNow:3600];
    [idx indexSearchableItems:@[it] completionHandler:^(NSError *e) { SFLog([NSString stringWithFormat:@"override index: %@", e ? e.localizedDescription : @"ok"]); }];
}
// The folder enumerated through the File Provider, as the Files app does when it shows a folder (fetch the folder's item, observe its collection
// for a few seconds): only counts are logged.
static void SFEnumerate(NSString *folder) {
    id mgr = SFItemManager();
    if (!mgr) { SFLog(@"fpenum: no File Provider lookup"); return; }
    ((void (*)(id, SEL, id, id))objc_msgSend)(mgr, NSSelectorFromString(@"fetchItemForURL:completionHandler:"), [NSURL fileURLWithPath:folder], ^(id item, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SEL make = NSSelectorFromString(@"collectionForFolderItem:");
            id col = item && [mgr respondsToSelector:make] ? ((id (*)(id, SEL, id))objc_msgSend)(mgr, make, item) : nil;
            if (!col) { SFLog([NSString stringWithFormat:@"fpenum %@: no collection (%@)", folder.lastPathComponent, e.localizedDescription ?: @"no item"]); return; }
            if (!gSFCollections) gSFCollections = [NSMutableArray array];
            [gSFCollections addObject:col];
            if ([col respondsToSelector:@selector(startObserving)]) ((void (*)(id, SEL))objc_msgSend)(col, @selector(startObserving));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSArray *items = [col respondsToSelector:@selector(items)] ? ((id (*)(id, SEL))objc_msgSend)(col, @selector(items)) : nil;
                NSUInteger ours = 0; for (id it in items) { NSString *n = [it respondsToSelector:NSSelectorFromString(@"filename")] ? [it valueForKey:@"filename"] : nil; if ([n.lowercaseString containsString:@"msbd"]) ours++; }
                SFLog([NSString stringWithFormat:@"fpenum %@: %lu items, %lu of them msbd test files", folder.lastPathComponent, (unsigned long)items.count, (unsigned long)ours]);
                if ([col respondsToSelector:@selector(stopObserving)]) ((void (*)(id, SEL))objc_msgSend)(col, @selector(stopObserving));
                [gSFCollections removeObject:col];
            });
        });
    });
}
static void SFTestCommand(NSString *cmd) {
    NSArray *w = [cmd componentsSeparatedByString:@" "];
    NSString *op = w.firstObject;
    NSString *rest = w.count > 1 ? [[w subarrayWithRange:NSMakeRange(1, w.count - 1)] componentsJoinedByString:@" "] : @"";
    if ([op isEqualToString:@"q"] && w.count >= 3) SFQuery(w[1], [[w subarrayWithRange:NSMakeRange(2, w.count - 2)] componentsJoinedByString:@" "]);
    else if ([op isEqualToString:@"write"] || [op isEqualToString:@"rawwrite"]) SFWrite(rest, [op isEqualToString:@"write"]);
    else if ([op isEqualToString:@"rm"]) SFRemove(rest);
    else if ([op isEqualToString:@"override"] || [op isEqualToString:@"overridedel"]) SFOverride([op isEqualToString:@"override"]);
    else if ([op isEqualToString:@"fpfetch"]) dispatch_async(gSFQueue, ^{ NSString *d = nil; BOOL ok = SFHandOver(rest, &d); SFLog([NSString stringWithFormat:@"fpfetch %@: %@ (%@)", rest.lastPathComponent, ok ? @"ok" : @"failed", d]); });
    else if ([op isEqualToString:@"scan"]) SFScanAll(@"test");
    else if ([op isEqualToString:@"fpenum"]) SFEnumerate(rest);
    else if ([op isEqualToString:@"fpindex"]) SFIndexNow(@"test");
    else if ([op isEqualToString:@"tweaks"]) SFTweakRefresh(@"test");
    else if ([op isEqualToString:@"removeall"]) notify_post(kMTSRemoveAllNote);
    else if ([op isEqualToString:@"state"]) SFLog([NSString stringWithFormat:@"state: files %d (lookup %@), folders %@, watched %lu, tweak switch %d, donated %@", gSFFilesOn, SFItemManager() ? @"ok" : @"missing",
        [SFFolders() valueForKey:@"lastPathComponent"], (unsigned long)gSFWatches.count, MTSSpotlightSwitch(), MTSStoredString(CFSTR("tweakSpotlightHash")) ?: @"nothing"]);
    else SFLog([NSString stringWithFormat:@"unknown command %@", op]);
}
static void SFTestPoll(void) {
    static time_t last = -1;
    struct stat sb;
    if (access("/tmp/macstatusbar-debug", F_OK) != 0 || stat("/tmp/msbd-spotfiles-test", &sb) != 0) { if (last == -1) last = 0; return; }
    if (sb.st_mtime == last) return;
    BOOL first = last == -1;
    last = sb.st_mtime;
    if (first) return;
    NSString *cmd = [[NSString stringWithContentsOfFile:@"/tmp/msbd-spotfiles-test" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *one in [cmd componentsSeparatedByString:@";"]) {
        NSString *c = [one stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (c.length) SFTestCommand(c);
    }
}
#endif

%ctor {
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    gSFQueue = dispatch_queue_create("com.besiktasliseba.msbd.spotlightfiles", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    int t1 = 0, t2 = 0, t3 = 0;
    notify_register_dispatch("com.besiktasliseba.macstatusbar/prefsChanged", &t1, dispatch_get_main_queue(), ^(int t) {
        SFReadFilesSwitch(@"switch");
        dispatch_async(gSFQueue, ^{ if (!MTSSpotlightSwitch()) MTSSyncSpotlight(nil, NO, @"switched off"); });   // (Tweak Settings off while Settings is closed: the
    });                                                                                                          //  stock bar, the Spotlight guard; a no-op without a donation)
    // (Settings > Siri & Search > an app > Show Content in Search: -[AssistantDetailController setWhileSearchingShowContentEnabled:specifier:] writes
    // com.apple.spotlightui SBSearchDisabledBundles and posts this, on 15.6.1 and 16.7.7)
    notify_register_dispatch("com.apple.spotlightui.prefschanged", &t3, dispatch_get_main_queue(), ^(int t) { SFReadFilesSwitch(@"Siri & Search changed"); });
    notify_register_dispatch(kMTSRemoveAllNote, &t2, dispatch_get_main_queue(), ^(int t) {   // (MacStatusBar&Dock is being removed)
        dispatch_async(gSFQueue, ^{ MTSDeleteSpotlight(@"MacStatusBar&Dock removed"); });
    });
    SFWatchTweaks();
    // (a short while after SpringBoard starts, out of the way of the start: the switches, and a tweak installed with this respring)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SFReadFilesSwitch(@"SpringBoard started");
        SFTweakRefresh(@"SpringBoard started");
    });
#if DEBUG
    static dispatch_source_t poll;
    poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(poll, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(poll, ^{ SFTestPoll(); });
    dispatch_resume(poll);
#endif
}
