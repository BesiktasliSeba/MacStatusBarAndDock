#import <dlfcn.h>
// MacSpotlight.x -- our sections in Apple's Spotlight (MacStatusBar&Dock 1.4.3, S-3 #2 "Actions" and #3 "Windows"), inside the Spotlight app
// (com.apple.Spotlight: loader/Loader.c loads this part there and nowhere else). SpringBoard's half is statusbar/SpotlightBridge.h.
//
// Apple's results stay untouched: our sections come after all of Apple's -- the Actions before them when the typed text names one, after Apple's
// Top Hit if it has one (1.7.0, KT: "activ" shows Activity Monitor first; MacSpotlightMove.h MSPPlaceOurs) --, each only when the typed text
// matches one of its rows (MacSpotlightMatch.h), and nothing at all is added while the switches are off -- not even a hook: the hooks go in the
// first time a switch is on (Settings > Status Bar > Spotlight, off unless switched on), and do nothing while every switch is off again.
//  - Actions: Show Desktop, Desktop N (the Mac Switcher's desktops), Downloads, New Finder Window, Lock Screen, Force Quit (asks first);
//  - Windows: the open windows of every engine and Finder's, on this desktop and the others; picking one brings it forward (its desktop first);
//  - Tweak Settings (search-143, S-3 #1): its rows are Apple's own results (CoreSpotlight items of Settings, identifiers "msbd-tweaksetting:");
//    they are moved out of Apple's sections and its Top Hit into a section of their own after Apple's, and open the way Apple opens them.
// How (read in Apple's binaries of 15.6.1 19G82 and 16.7.7 20H330; MacSpotlightCheck.h says it in full): the results list (SPUIResultsViewController)
// shows its sections through -updateWithResultSections:resetScrollPoint:; ours are appended to what it is given. A row of ours is a plain
// SFSearchResult (title, a line under it, an SF Symbol or an app's icon), which SearchUI draws as its standard row. Tapping or Return on one asks
// SearchUI's tap factory (16: +[SearchUICommandHandler handlerForRowModel:environment:]; 15: +[SearchUICommand tapCommandForRowModel:environment:]),
// which hands our rows a handler of ours (a subclass of Apple's) that tells SpringBoard which row it was (notify state); Apple's rows get Apple's.
// What to list comes from SpringBoard as a small file in the jailbreak's root, written when this app asks (as Spotlight comes up).
// Every private class, selector and type encoding is checked first (MSPCheckClasses): anything missing or different and nothing is hooked, so
// Spotlight is exactly Apple's.
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "MacSpotlightCheck.h"
#import "MacSpotlightMatch.h"
#import "MacSpotlightMove.h"

#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

#define MSP_STATE   "com.besiktasliseba.macstatusbar.spotlight.state"    // SpringBoard: 1 Actions, 2 Windows, 4 Tweak Settings (the switches)
#define MSP_REQUEST "com.besiktasliseba.macstatusbar.spotlight.request"  // us: write the list, please
#define MSP_READY   "com.besiktasliseba.macstatusbar.spotlight.ready"    // SpringBoard: the list is written; state = its generation
#define MSP_PICK    "com.besiktasliseba.macstatusbar.spotlight.pick"     // us: state = generation << 32 | the row's place in the list
#define MSP_REPORT  "com.besiktasliseba.macstatusbar.spotlight.report"   // us, debug builds: state = kind << 32 | value, for SpringBoard's log
#define MSP_LIST    @"/var/jb/var/mobile/Library/Caches/com.besiktasliseba.macstatusbar/Spotlight.plist"
#define MSP_OURS    @"msbd-spot:"              // (our rows' identifiers: msbd-spot:<generation>:<row>)

static BOOL gMSPChecked = NO, gMSPCheckOK = NO, gMSPHooked = NO;
static MSPTapKind gMSPTap = MSPTapNone;
static const char *gMSPModelSel = NULL;      // (the results controller's rows, as the check found them: "collectionModel" on 16, "tableModel" on 17)
static Class gMSPResult, gMSPSection, gMSPText, gMSPRich, gMSPSymbol, gMSPAppIcon;
static uint64_t gMSPState = 0;                 // the switches, as SpringBoard published them
static NSDictionary *gMSPList;                 // the list last read: @{gen, rows[, outside]} -- one presentation's only (MSPDropList)
static uint64_t gMSPListGen = 0;
static CFTimeInterval gMSPListAt = 0, gMSPAskedAt = 0;
static NSString *gMSPCacheKey; static id gMSPCacheActions, gMSPCacheWindows; static BOOL gMSPCacheLead; static NSUInteger gMSPCacheA, gMSPCacheW;   // (MSPOurSections' last answer)
// The list and the sections made from it go when the app's scene leaves the screen: a list never outlives the Spotlight it was written for (the
// Today view and the Lock Screen's Today view host this app too, and get an empty one from SpringBoard -- no rows of ours there).
static void MSPDropList(void) { gMSPList = nil; gMSPListGen = 0; gMSPListAt = 0; gMSPCacheKey = nil; gMSPCacheActions = gMSPCacheWindows = nil; gMSPCacheLead = NO; }
static __weak UIViewController *gMSPLastResults;   // (the results list last seen: shown again when a fresh list comes)

#if DEBUG
static void MSPReport(uint32_t kind, uint32_t value) {   // (SpringBoard logs it: "[spotlight] Spotlight app reports: kind, value")
    static int t = 0;
    if (!t && notify_register_check(MSP_REPORT, &t) != NOTIFY_STATUS_OK) t = 0;
    if (t) notify_set_state(t, ((uint64_t)kind << 32) | value);
    notify_post(MSP_REPORT);
}
#else
#define MSPReport(kind, value) do { } while (0)
#endif
enum { kMSPRepCheck = 1, kMSPRepHooked = 2, kMSPRepList = 3, kMSPRepShown = 4, kMSPRepPick = 5, kMSPRepMoved = 6, kMSPRepListError = 7, kMSPRepException = 8 };


// ---- the check: once, in this process ----
static BOOL MSPCheck(void) {
    if (gMSPChecked) return gMSPCheckOK;
    gMSPChecked = YES;
    gMSPResult = objc_getClass("SFSearchResult"); gMSPSection = objc_getClass("SFResultSection"); gMSPText = objc_getClass("SFText");
    gMSPRich = objc_getClass("SFRichText"); gMSPSymbol = objc_getClass("SFSymbolImage"); gMSPAppIcon = objc_getClass("SFAppIconImage");
    NSMutableArray *why = [NSMutableArray array];
    gMSPTap = MSPCheckClasses(objc_getClass("SPUIResultsViewController"), objc_getClass("SearchUIRowModel"), gMSPResult, gMSPSection, gMSPText, gMSPRich,
                              gMSPSymbol, gMSPAppIcon, objc_getClass("SearchUICommandHandler"), objc_getClass("SearchUICollectionViewController"),
                              objc_getClass("SearchUICollectionModel"), objc_getClass("SearchUICommand"), objc_getClass("SearchUITapCommand"),
                              objc_getClass("SearchUITableModel"), &gMSPModelSel, why);
    gMSPCheckOK = gMSPTap != MSPTapNone && !why.count;
    if (!gMSPCheckOK) NSLog(@"[MacSpotlight] check failed, Spotlight stays Apple's: %@", [why componentsJoinedByString:@"; "]);
#if DEBUG
    {   // (debug: the reasons where they can be read from the Mac -- the Spotlight app's own temporary folder; SpringBoard's log only gets their count)
        NSMutableString *t = [NSMutableString stringWithFormat:@"check %@ (tap %ld)\n%@\n", gMSPCheckOK ? @"passed" : @"FAILED", (long)gMSPTap, [why componentsJoinedByString:@"\n"]];
        // (and the classes the check reads, as tools/spotcheck-fixtures has them: "<class> <superclass> <+|-><selector> <shape>", for the Mac test)
        NSMutableString *fx = [NSMutableString stringWithFormat:@"# spotcheck fixture from the running Spotlight app (MacSpotlight debug build), iPadOS %@: class superclass +/-selector shape\n", [[NSProcessInfo processInfo] operatingSystemVersionString]];
        for (NSString *cn in @[@"SFAppIconImage", @"SFImage", @"SFResultSection", @"SFRichText", @"SFSearchResult", @"SFSymbolImage", @"SFText", @"SPUIResultsViewController",
                               @"SearchUICollectionModel", @"SearchUITableModel", @"SearchUICollectionViewController", @"SearchUICommandHandler", @"SearchUICommand", @"SearchUITapCommand",
                               @"SearchUIKeyboardableCollectionViewController", @"SearchUIResultsViewController", @"SearchUIRowModel"]) {
            Class c = objc_getClass(cn.UTF8String);
            if (!c) continue;
            const char *sup = class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "NSObject";
            for (int meta = 1; meta >= 0; meta--) {
                unsigned mc = 0; Method *ms = class_copyMethodList(meta ? object_getClass(c) : c, &mc);
                for (unsigned j = 0; j < mc; j++) [fx appendFormat:@"%@ %s %c%s %@\n", cn, sup, meta ? '+' : '-', sel_getName(method_getName(ms[j])), MSPShape(method_getTypeEncoding(ms[j]))];
                free(ms);
            }
        }
        [fx writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"macspotlight-fixture.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [t writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"macspotlight-check.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
#endif
    MSPReport(kMSPRepCheck, gMSPCheckOK ? (uint32_t)gMSPTap : 0x10000u | (uint32_t)MIN(why.count, 0xFFFFu));
    return gMSPCheckOK;
}

// ---- the list from SpringBoard ----
static void MSPAsk(void) {   // (once per half second: Spotlight coming up sends a scene's and the app's own notice at once; any switch: SpringBoard's guard
                              //  learns the app came up with our code in it, and writes a list only for Actions and Windows)
    if (!(gMSPState & 7) || CACurrentMediaTime() - gMSPAskedAt < 0.5) return;
    gMSPAskedAt = CACurrentMediaTime();
    notify_post(MSP_REQUEST);
}
static void MSPReadList(uint64_t gen) {
    NSError *e = nil;
    NSData *d = [NSData dataWithContentsOfFile:MSP_LIST options:0 error:&e];
    if (!d) { MSPReport(kMSPRepListError, (uint32_t)(e ? e.code : 0)); return; }
    NSDictionary *p = [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:nil];
    if (![p isKindOfClass:[NSDictionary class]] || ![p[@"rows"] isKindOfClass:[NSArray class]] || ![p[@"gen"] isKindOfClass:[NSNumber class]]) { MSPReport(kMSPRepListError, 0xFFFF); return; }
    gMSPList = p; gMSPListGen = [p[@"gen"] unsignedLongLongValue]; gMSPListAt = CACurrentMediaTime();
    MSPReport(kMSPRepList, (uint32_t)(((gMSPListGen & 0xFFFF) << 16) | MIN([p[@"rows"] count], (NSUInteger)0xFFFF)));
    (void)gen;
}

// ---- our rows and sections ----
static id MSPText(Class c, NSString *s) { return ((id (*)(id, SEL, id))objc_msgSend)(c, sel_registerName("textWithString:"), s ?: @""); }
static id MSPRow(NSDictionary *r, uint64_t gen, NSUInteger place) {
    id res = [[gMSPResult alloc] init];
    MSPSet(res, "setIdentifier:", [NSString stringWithFormat:@"%@%llu:%lu", MSP_OURS, gen, (unsigned long)place]);
    MSPSet(res, "setTitle:", MSPText(gMSPText, r[@"t"]));
    NSString *d = [r[@"d"] isKindOfClass:[NSString class]] ? r[@"d"] : nil;
    if (d.length) MSPSet(res, "setDescriptions:", @[MSPText(gMSPRich, d)]);
    id pic = nil;
    if ([r[@"b"] isKindOfClass:[NSString class]]) { pic = [[gMSPAppIcon alloc] init]; MSPSet(pic, "setBundleIdentifier:", r[@"b"]); }
    else if ([r[@"s"] isKindOfClass:[NSString class]]) { pic = [[gMSPSymbol alloc] init]; MSPSet(pic, "setSymbolName:", r[@"s"]); }
    if (pic) MSPSet(res, "setThumbnail:", pic);
    return res;
}
// app: the app the section's rows belong to. A section's header offers "Search in App" when its first row carries a search-continuation punchout
// (Settings' own items do) and opens the app the SECTION names (-[SearchUITableHeaderView(Shared) moreButtonPressed], 15 and 16), so the moved
// Tweak Settings name Settings: a made-up identifier there sent the search to whichever app takes continuation (Podcasts on the iPad 2, 1.4.3 RC1).
static id MSPSection(NSString *title, NSString *ident, NSString *app, NSArray *results) {
    id s = [[gMSPSection alloc] init];
    MSPSet(s, "setTitle:", title);
    MSPSet(s, "setBundleIdentifier:", app ?: ident);
    MSPSet(s, "setIdentifier:", ident);
    MSPSet(s, "setResults:", results);
    return s;
}
// Actions and Windows for this text, each nil without a row, and whether the text names an action (MSPNamesOne: then the Actions lead; cached:
// Apple shows its sections several times while one search answers, and the same rows keep their place).
static NSUInteger gMSPShownActions = 0, gMSPShownWindows = 0;   // (how many rows of each the last sections had: the debug report)
static BOOL MSPOurSections(NSString *q, id *actions, id *windows) {
    *actions = nil; *windows = nil;
    if (!(gMSPState & 3) || q.length < 2) return NO;
    CFTimeInterval age = CACurrentMediaTime() - gMSPListAt;   // (an "outside" list -- the Today view, locked -- is asked again soon: Spotlight's own window may follow)
    if ((!gMSPList || age > 30.0 || ([gMSPList[@"outside"] boolValue] && age > 2.0)) && CACurrentMediaTime() - gMSPAskedAt > 2.0) MSPAsk();
    if (!gMSPList) return NO;
    NSString *key = [NSString stringWithFormat:@"%llu|%llu|%@", gMSPListGen, gMSPState, q];
    if ([key isEqualToString:gMSPCacheKey]) {
        gMSPShownActions = gMSPCacheA; gMSPShownWindows = gMSPCacheW; *actions = gMSPCacheActions; *windows = gMSPCacheWindows;
        return gMSPCacheLead;
    }
    NSArray *rows = gMSPList[@"rows"];
    id made[2] = { nil, nil };
    NSUInteger counts[2] = { 0, 0 };
    BOOL lead = NO;
    NSArray *groups = @[@[@1, @"a", @"Actions", @"com.besiktasliseba.macstatusbar.spotlight.actions"], @[@2, @"w", @"Windows", @"com.besiktasliseba.macstatusbar.spotlight.windows"]];
    for (NSUInteger k = 0; k < groups.count; k++) {
        NSArray *g = groups[k];
        if (!(gMSPState & [g[0] unsignedLongLongValue])) continue;
        NSArray<NSNumber *> *hits = MSPMatches(q, rows, g[1], 8);
        NSMutableArray *res = [NSMutableArray array];
        for (NSNumber *i in hits) [res addObject:MSPRow(rows[i.unsignedIntegerValue], gMSPListGen, i.unsignedIntegerValue)];
        if (res.count) made[k] = MSPSection(g[2], g[3], nil, res);
        if (k == 0) lead = res.count && MSPNamesOne(q, rows, hits);
        counts[k] = res.count;
    }
    gMSPCacheKey = key; gMSPCacheActions = made[0]; gMSPCacheWindows = made[1]; gMSPCacheLead = lead;
    gMSPCacheA = gMSPShownActions = counts[0]; gMSPCacheW = gMSPShownWindows = counts[1];
    *actions = made[0]; *windows = made[1];
    return lead;
}
// Our sections' identifiers (MSPOurSections, MSPWithOurs): every one starts with this; the Tweak Settings section is the one made of Apple's rows.
#define MSP_SECTION_PREFIX @"com.besiktasliseba.macstatusbar.spotlight."
#define MSP_TWEAK_SECTION  @"com.besiktasliseba.macstatusbar.spotlight.tweaksettings"
static NSString *MSPSectionIdent(id sec) {
    NSString *ident = nil;
    @try { ident = [sec respondsToSelector:sel_registerName("identifier")] ? MSPCall(sec, "identifier") : nil; } @catch (NSException *e) { ident = nil; }
    return [ident isKindOfClass:[NSString class]] ? ident : nil;
}
#if DEBUG
static void MSPDebugLine(NSString *line);   // (below, with the hooks)
#endif
// A list that already carries sections of ours (iPadOS 17's two- and three-argument updates may pass through each other, and Apple may push a list
// it kept, with our sections for an earlier query, again -- logic test F4): our Actions and Windows are taken out and made again for the text typed
// now, so the answer is the same however often it is asked and always for the current text. The Tweak Settings section is kept where it is: its
// rows were taken out of Apple's Settings section when it was made, so moving again would find nothing. Where each goes: MSPPlaceOurs.
static NSArray *MSPWithOurs(UIViewController *vc, NSArray *sections) {
    if (sections && ![sections isKindOfClass:[NSArray class]]) return sections;
    gMSPLastResults = vc;
    NSString *q = MSPCall(vc, "queryString");
    if (![q isKindOfClass:[NSString class]]) q = nil;
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger tweakAt = NSNotFound, stale = 0;
    for (id sec in sections ?: @[]) {
        NSString *ident = MSPSectionIdent(sec);
        if ([ident isEqualToString:MSP_TWEAK_SECTION]) { tweakAt = out.count; [out addObject:sec]; continue; }   // (already moved: kept)
        if ([ident hasPrefix:MSP_SECTION_PREFIX]) { stale++; continue; }   // (ours, for whatever text it was made -- the Actions at the top too: made again below)
        [out addObject:sec];
    }
    NSArray *moved = (gMSPState & 4) && tweakAt == NSNotFound ? MSPTakeTweakSettings(out) : @[];
    id actions = nil, windows = nil;
    BOOL lead = MSPOurSections(q, &actions, &windows);
    if (!moved.count && !actions && !windows && !stale) return sections;
    NSUInteger topAt = actions && lead ? MSPTopHitAt(out) : NSNotFound;
#if DEBUG
    {   // (debug: how Apple marks its sections -- identifiers and top-hit flags only, never a title)
        NSMutableString *m = [NSMutableString stringWithFormat:@"sections for %lu letters, Top Hit at %ld:", (unsigned long)q.length, topAt == NSNotFound ? -1L : (long)topAt];
        for (NSUInteger i = 0; i < out.count; i++) {
            id sec = out[i]; NSArray *rs = MSPCall(sec, "results"); id first = [rs isKindOfClass:[NSArray class]] ? rs.firstObject : nil;
            SEL th = sel_registerName("topHit"), la = sel_registerName("isLocalApplicationResult");
            [m appendFormat:@" [%lu %@ | %@ | %lu, topHit %d app %d]", (unsigned long)i, MSPCall(sec, "identifier"), MSPCall(sec, "bundleIdentifier"), (unsigned long)([rs isKindOfClass:[NSArray class]] ? rs.count : 0),
                first && [first respondsToSelector:th] ? ((int (*)(id, SEL))objc_msgSend)(first, th) : -1, first && [first respondsToSelector:la] ? ((BOOL (*)(id, SEL))objc_msgSend)(first, la) : -1];
        }
        MSPDebugLine(m);
    }
#endif
    NSArray *shown = MSPPlaceOurs(out, tweakAt, topAt, actions, lead, windows, moved.count ? MSPSection(@"Tweak Settings", MSP_TWEAK_SECTION, @"com.apple.Preferences", moved) : nil);
    DM_FEATURE_MARK("spotlight-sections");
    if (actions && lead) DM_FEATURE_MARK("spotlight-actions-first");
    MSPReport(kMSPRepShown, (uint32_t)((actions && lead ? (topAt == NSNotFound ? 1u << 24 : 2u << 24) : 0u) | (MIN(actions ? gMSPShownActions : 0, (NSUInteger)0xFF) << 16)
                                       | (MIN(windows ? gMSPShownWindows : 0, (NSUInteger)0xFF) << 8) | MIN(moved.count, (NSUInteger)0xFF)));
    return shown;
}

// ---- the hooks ----
static void (*oMSPUpdate)(id, SEL, id, BOOL);
static Class gMSPResultsClass;   // (SPUIResultsViewController: the hook sits on SearchUI's class that has the method, and acts for this one only)
#if DEBUG
static void MSPDebugLine(NSString *line) {   // (debug: the Spotlight app's own temporary folder, read from the Mac)
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"macspotlight-trace.txt"];
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) { fprintf(f, "%.3f %s\n", CACurrentMediaTime(), line.UTF8String); fclose(f); }
}
static void (*oMSPDbgSections)(id, SEL, id);
static void MSPDbgSections(id self, SEL _cmd, id sections) {
    MSPDebugLine([NSString stringWithFormat:@"-[%@ %s] %lu sections", NSStringFromClass([self class]), sel_getName(_cmd), (unsigned long)([sections respondsToSelector:@selector(count)] ? [sections count] : 0)]);
    oMSPDbgSections(self, _cmd, sections);
}
static void (*oMSPDbgObj[8])(id, SEL, id);
static const char *gMSPDbgObjSel[8];
#define MSP_DBG_OBJ(n) static void MSPDbgObj##n(id self, SEL _cmd, id a) { MSPDebugLine([NSString stringWithFormat:@"-[%@ %s] %@", NSStringFromClass([self class]), sel_getName(_cmd), a ? NSStringFromClass([a class]) : @"nil"]); oMSPDbgObj[n](self, _cmd, a); }
MSP_DBG_OBJ(0) MSP_DBG_OBJ(1) MSP_DBG_OBJ(2) MSP_DBG_OBJ(3)
static void (*oMSPDbgPush)(id, SEL);
static void MSPDbgPush(id self, SEL _cmd) { MSPDebugLine([NSString stringWithFormat:@"-[%@ %s]", NSStringFromClass([self class]), sel_getName(_cmd)]); oMSPDbgPush(self, _cmd); }
#endif
static void MSPUpdate(id self, SEL _cmd, id sections, BOOL reset) {
#if DEBUG
    MSPDebugLine([NSString stringWithFormat:@"-[%@ updateWithResultSections:resetScrollPoint:] %lu sections, state %llu, ours %d", NSStringFromClass([self class]), (unsigned long)([sections respondsToSelector:@selector(count)] ? [sections count] : 0), gMSPState, [self isKindOfClass:gMSPResultsClass]]);
#endif
    id shown = sections;
    if ((gMSPState & 7) && [self isKindOfClass:gMSPResultsClass]) {
        @try { shown = MSPWithOurs(self, sections); }
        @catch (NSException *e) { shown = sections; MSPReport(kMSPRepException, 1); NSLog(@"[MacSpotlight] sections left as Apple's: %@", e); }
    }
    oMSPUpdate(self, _cmd, shown, reset);
}
// iPadOS 17: the results list's sections come through -updateWithResultSections:resetScrollPoint:animated: (new in 17; 15/16's _pushSectionsUpdate
// called the two-argument one, which 17 still has but its push no longer uses: 17.5.1 trace, round 2 -- eight pushes, no two-argument call)
static void (*oMSPUpdate3)(id, SEL, id, BOOL, BOOL);
static void MSPUpdate3(id self, SEL _cmd, id sections, BOOL reset, BOOL animated) {
#if DEBUG
    MSPDebugLine([NSString stringWithFormat:@"-[%@ updateWithResultSections:resetScrollPoint:animated:] %lu sections, state %llu", NSStringFromClass([self class]), (unsigned long)([sections respondsToSelector:@selector(count)] ? [sections count] : 0), gMSPState]);
#endif
    id shown = sections;
    if ((gMSPState & 7) && [self isKindOfClass:gMSPResultsClass]) {
        @try { shown = MSPWithOurs(self, sections); }
        @catch (NSException *e) { shown = sections; MSPReport(kMSPRepException, 1); NSLog(@"[MacSpotlight] sections left as Apple's: %@", e); }
    }
    oMSPUpdate3(self, _cmd, shown, reset, animated);
}
static NSString *MSPOurIdentifier(id rowModel) {   // (a row of ours: its result's identifier; nil for every other row)
    if (!(gMSPState & 3) || !rowModel || ![rowModel respondsToSelector:sel_registerName("identifyingResult")]) return nil;
    id ident = nil;
    @try { ident = MSPCall(MSPCall(rowModel, "identifyingResult"), "identifier"); } @catch (NSException *e) { return nil; }
    return [ident isKindOfClass:[NSString class]] && [ident hasPrefix:MSP_OURS] ? ident : nil;
}
static void MSPPicked(id rowModel) {
    NSString *ident = MSPOurIdentifier(rowModel);
    NSArray *f = [[ident substringFromIndex:MSP_OURS.length] componentsSeparatedByString:@":"];
    if (f.count != 2) return;
    uint64_t gen = (uint64_t)[f[0] longLongValue], row = (uint64_t)[f[1] longLongValue];
    static int t = 0;
    if (!t && notify_register_check(MSP_PICK, &t) != NOTIFY_STATUS_OK) t = 0;
    if (!t) return;
    notify_set_state(t, (gen << 32) | (row & 0xFFFFFFFFull));
    notify_post(MSP_PICK);
    DM_FEATURE_MARK("spotlight-pick-sent");
    MSPReport(kMSPRepPick, (uint32_t)row);
}
// 16: our handler -- Apple's class with the tap told to SpringBoard (no feedback to Spotlight's ranking, no copy, share or menu)
static void MSPHandlerExecute(id self, SEL _cmd, unsigned long long event) { MSPPicked(MSPCall(self, "rowModel")); }
static BOOL MSPYes(id self, SEL _cmd) { return YES; }
static BOOL MSPNo(id self, SEL _cmd) { return NO; }
static Class gMSPHandlerClass, gMSPCommandClass;
static id (*oMSPHandlerFor)(id, SEL, id, id);
static id MSPHandlerFor(id cls, SEL _cmd, id rowModel, id env) {
    if (gMSPHandlerClass && MSPOurIdentifier(rowModel)) {
        id h = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)([gMSPHandlerClass alloc], sel_registerName("initWithCommand:rowModel:button:environment:"), nil, rowModel, nil, env);
        if (h) return h;
    }
    return oMSPHandlerFor(cls, _cmd, rowModel, env);
}
// (16: a row is highlighted -- so tapped, or reached with the arrow keys -- only when this says so; Apple's answer is whether Apple's factory
//  has a handler for it, which ours have only in ours. Answered here, where the highlight is asked, not in that factory question: the long press
//  asks it too, and our rows have no preview menu)
static BOOL (*oMSPCanHighlight)(id, SEL, id);
static BOOL MSPCanHighlight(id self, SEL _cmd, id indexPath) {
    if (oMSPCanHighlight(self, _cmd, indexPath)) return YES;
    if (!gMSPHandlerClass || !indexPath) return NO;
    id model = gMSPModelSel ? MSPCall(self, gMSPModelSel) : nil, row = nil;   // (16: -collectionModel, 17: -tableModel -- as the check found it)
    SEL rowAt = sel_registerName("rowModelForIndexPath:");
    @try { row = model && [model respondsToSelector:rowAt] ? ((id (*)(id, SEL, id))objc_msgSend)(model, rowAt, indexPath) : nil; }
    @catch (NSException *e) { return NO; }
    return MSPOurIdentifier(row) != nil;
}
// 15: our tap command -- Apple's class with the tap told to SpringBoard; its completion runs as Apple's would
static void MSPCommandPerform(id self, SEL _cmd, void (^completion)(void)) { MSPPicked(MSPCall(self, "rowModel")); if (completion) completion(); }
static id (*oMSPTapCommandFor)(id, SEL, id, id);
static id MSPTapCommandFor(id cls, SEL _cmd, id rowModel, id env) {
    if (gMSPCommandClass && MSPOurIdentifier(rowModel)) {
        id c = ((id (*)(id, SEL, id, id, id))objc_msgSend)([gMSPCommandClass alloc], sel_registerName("initWithRowModel:command:environment:"), rowModel, nil, env);
        if (c) return c;
    }
    return oMSPTapCommandFor(cls, _cmd, rowModel, env);
}
static Class MSPSubclass(Class base, const char *name, NSDictionary<NSString *, NSValue *> *imps) {
    Class c = objc_getClass(name);
    if (c) return c;
    c = objc_allocateClassPair(base, name, 0);
    if (!c) return nil;
    for (NSString *sel in imps) {
        Method m = class_getInstanceMethod(base, NSSelectorFromString(sel));   // (Apple's own encoding: checked by MSPCheckClasses)
        if (!m) { objc_disposeClassPair(c); return nil; }
        class_addMethod(c, NSSelectorFromString(sel), (IMP)[imps[sel] pointerValue], method_getTypeEncoding(m));
    }
    objc_registerClassPair(c);
    return c;
}
static void MSPInstall(void) {
    if (gMSPHooked || !MSPCheck()) return;
    gMSPHooked = YES;
    if (gMSPTap == MSPTapHandler16) {
        Class base = objc_getClass("SearchUICommandHandler");
        gMSPHandlerClass = MSPSubclass(base, "MSBDSpotlightHandler", @{ @"executeWithTriggerEvent:": [NSValue valueWithPointer:(void *)MSPHandlerExecute],
            @"shouldDeselectAfterExecution": [NSValue valueWithPointer:(void *)MSPYes], @"supportsCopy": [NSValue valueWithPointer:(void *)MSPNo],
            @"supportsShare": [NSValue valueWithPointer:(void *)MSPNo], @"prefersContextMenu": [NSValue valueWithPointer:(void *)MSPNo] });
        if (!gMSPHandlerClass) { MSPReport(kMSPRepHooked, 0); return; }
        MSHookMessageEx(object_getClass(base), sel_registerName("handlerForRowModel:environment:"), (IMP)MSPHandlerFor, (IMP *)&oMSPHandlerFor);
        MSHookMessageEx(objc_getClass("SearchUICollectionViewController"), sel_registerName("canHighlightRowAtIndexPath:"), (IMP)MSPCanHighlight, (IMP *)&oMSPCanHighlight);
    } else {
        gMSPCommandClass = MSPSubclass(objc_getClass("SearchUITapCommand"), "MSBDSpotlightCommand", @{ @"performCommandWithCompletion:": [NSValue valueWithPointer:(void *)MSPCommandPerform],
            @"presentsViewController": [NSValue valueWithPointer:(void *)MSPNo] });
        if (!gMSPCommandClass) { MSPReport(kMSPRepHooked, 0); return; }
        MSHookMessageEx(object_getClass(objc_getClass("SearchUICommand")), sel_registerName("tapCommandForRowModel:environment:"), (IMP)MSPTapCommandFor, (IMP *)&oMSPTapCommandFor);
    }
    // (on SearchUIResultsViewController, which has the method in both builds -- the results list inherits it; a hook on the class that owns the
    //  method needs no inherited-method handling from the hooking library)
    gMSPResultsClass = objc_getClass("SPUIResultsViewController");
    Class owner = gMSPResultsClass;
    SEL upd = sel_registerName("updateWithResultSections:resetScrollPoint:");
    for (Class k = gMSPResultsClass; k; k = class_getSuperclass(k)) {
        unsigned n = 0; BOOL own = NO; Method *ms = class_copyMethodList(k, &n);
        for (unsigned i = 0; i < n; i++) if (method_getName(ms[i]) == upd) { own = YES; break; }
        free(ms);
        if (own) { owner = k; break; }
    }
    MSHookMessageEx(owner, upd, (IMP)MSPUpdate, (IMP *)&oMSPUpdate);
    {   // (iPadOS 17: the three-argument update its push uses -- checked by MSPCheckClasses where it exists)
        SEL upd3 = sel_registerName("updateWithResultSections:resetScrollPoint:animated:");
        Class owner3 = Nil;
        for (Class k = gMSPResultsClass; k && !owner3; k = class_getSuperclass(k)) {
            unsigned n = 0; Method *ms = class_copyMethodList(k, &n);
            for (unsigned i = 0; i < n; i++) if (method_getName(ms[i]) == upd3) { owner3 = k; break; }
            free(ms);
        }
        if (owner3) { MSHookMessageEx(owner3, upd3, (IMP)MSPUpdate3, (IMP *)&oMSPUpdate3); DM_FEATURE_MARK("spotlight-sections-17"); }
    }
#if DEBUG
    {   // (debug: which update path this iPadOS's Spotlight takes)
        Class cvc = objc_getClass("SearchUICollectionViewController");
        if (cvc && class_getInstanceMethod(cvc, sel_registerName("updateWithResultSections:"))) MSHookMessageEx(cvc, sel_registerName("updateWithResultSections:"), (IMP)MSPDbgSections, (IMP *)&oMSPDbgSections);
        if (gMSPResultsClass && class_getInstanceMethod(gMSPResultsClass, sel_registerName("_pushSectionsUpdate"))) MSHookMessageEx(gMSPResultsClass, sel_registerName("_pushSectionsUpdate"), (IMP)MSPDbgPush, (IMP *)&oMSPDbgPush);
        IMP dbg[4] = { (IMP)MSPDbgObj0, (IMP)MSPDbgObj1, (IMP)MSPDbgObj2, (IMP)MSPDbgObj3 };
        const char *sels[4] = { "setTableModel:", "updateWithTableModel:", "updateWithSnapshot:", "setTableModelWithoutReset:" };
        for (int i = 0; i < 4; i++) if (cvc && class_getInstanceMethod(cvc, sel_registerName(sels[i]))) { gMSPDbgObjSel[i] = sels[i]; MSHookMessageEx(cvc, sel_registerName(sels[i]), dbg[i], (IMP *)&oMSPDbgObj[i]); }
        MSPDebugLine([NSString stringWithFormat:@"hooked: update on %s, state %llu", class_getName(owner), gMSPState]);
    }
#endif
    MSPReport(kMSPRepHooked, (uint32_t)gMSPTap | (owner == gMSPResultsClass ? 0x100u : 0x200u));
}

// ---- the switches ----
static void MSPStateChanged(int token) {
    uint64_t st = 0;
    notify_get_state(token, &st);
    gMSPState = st & 7;
    if (gMSPState) MSPInstall();
    if (gMSPState & 3) MSPAsk(); else MSPDropList();
}

%ctor {
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.Spotlight"]) return;   // (Loader.c loads it only here; a second guard)
        dispatch_async(dispatch_get_main_queue(), ^{
            static int state = 0, ready = 0;
            if (notify_register_dispatch(MSP_STATE, &state, dispatch_get_main_queue(), ^(int t) { MSPStateChanged(t); }) == NOTIFY_STATUS_OK) MSPStateChanged(state);
            notify_register_dispatch(MSP_READY, &ready, dispatch_get_main_queue(), ^(int t) {
                if (!(gMSPState & 3)) return;
                uint64_t gen = 0; notify_get_state(t, &gen);
                MSPReadList(gen);
                UIViewController *vc = gMSPLastResults;   // (a search on the screen: Apple's sections shown again, now with the fresh list)
                NSString *q = MSPCall(vc, "queryString");
                if (gMSPHooked && vc.viewIfLoaded.window && [q isKindOfClass:[NSString class]] && q.length >= 2) ((void (*)(id, SEL))objc_msgSend)(vc, sel_registerName("_pushSectionsUpdate"));
            });
            for (NSNotificationName n in @[UISceneDidEnterBackgroundNotification, UISceneDidDisconnectNotification, UIApplicationDidEnterBackgroundNotification])
                [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { MSPDropList(); }];
            for (NSNotificationName n in @[UISceneWillEnterForegroundNotification, UIApplicationWillEnterForegroundNotification])   // (Spotlight comes up: a fresh list)
                [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { MSPAsk(); }];
        });
    }
}
