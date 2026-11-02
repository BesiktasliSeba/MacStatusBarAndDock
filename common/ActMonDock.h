// ActMonDock.h -- Activity Monitor in the Dock (1.7.3 item 5): the rules that need no SpringBoard, Foundation only, so the Mac test
// (tools/test-actmondock.sh) runs the same code. SpringBoard's side: statusbar/ActMonDock.h.
//  - The Home Screen layout SpringBoard writes, without our icon (MSBDLayoutWithout): it is never saved, so no layout file of SpringBoard's ever
//    names it -- with the tweak removed, switched off, in Safe Mode or on an untested iPadOS there is no dead icon to clean up.
//  - Where it goes back into the Dock at start (MSBDActMonDockPlace), from our own record of its place.
//  - Its running entry (1.7.7 item 1b): where it shows while its window is open and it is not kept in the Dock (MSBDActMonRunningSpot), and its
//    menu's Dock row (MSBDActMonMenuRow).
//  - Its place in iPadOS's Command-Tab while its window exists (1.7.8 item 10, MSBDActMonCmdTabIndex).
#pragma once
#import <Foundation/Foundation.h>

// The layout dictionary (IconState.plist's: buttonBar = the Dock, iconLists = the pages, a folder's iconLists, ignored = the App Library's apps,
// listMetadata's rotatedOrder = a page's order when turned) with every list entry that names `ident` taken out -- the identifier itself, or an entry
// that ends with it after a space (a drag's stand-in, "Placeholder: Grabbed <identifier>", saved in a page's rotatedOrder while it was dragged over
// it: seen on 16.7.7); everything else as it was (a page's widgets, the folders' names and ids). An identifier stands in a list as a plain string, so
// only strings inside arrays are looked at. The same object comes back when nothing named it; *removed counts what was taken out.
static inline BOOL MSBDLayoutEntryNames(NSString *entry, NSString *ident) {
    return [entry isEqualToString:ident] || [entry hasSuffix:[@" " stringByAppendingString:ident]];
}
static id MSBDLayoutWithout(id node, NSString *ident, NSUInteger *removed) {
    if (![ident isKindOfClass:[NSString class]] || !ident.length) return node;
    if ([node isKindOfClass:[NSArray class]]) {
        NSArray *a = node;
        NSMutableArray *out = nil;
        for (NSUInteger i = 0; i < a.count; i++) {
            id x = a[i];
            id y = [x isKindOfClass:[NSString class]] ? (MSBDLayoutEntryNames(x, ident) ? nil : x) : MSBDLayoutWithout(x, ident, removed);
            if (y != x && !out) out = [[a subarrayWithRange:NSMakeRange(0, i)] mutableCopy];   // (the first change: the entries before it, as they were)
            if (!y) { if (removed) (*removed)++; continue; }
            if (out) [out addObject:y];
        }
        return out ? [out copy] : node;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = node;
        NSMutableDictionary *out = nil;
        for (id k in d) {
            id x = d[k];
            if (![x isKindOfClass:[NSArray class]] && ![x isKindOfClass:[NSDictionary class]]) continue;
            id y = MSBDLayoutWithout(x, ident, removed);
            if (y != x) { if (!out) out = [d mutableCopy]; out[k] = y; }
        }
        return out ? [out copy] : node;
    }
    return node;
}

// The place it goes back to: the recorded place among the Dock's own icons, or the Dock's end when it keeps fewer icons now; -1 = not at all (no
// record, or no room left in the Dock).
static inline NSInteger MSBDActMonDockPlace(NSInteger recorded, NSUInteger kept, NSUInteger room) {
    if (recorded < 0 || kept >= room) return -1;
    return recorded < (NSInteger)kept ? recorded : (NSInteger)kept;
}

// A record read back from the preferences: a number 0...64 is a place, anything else (absent, another type, out of range) is "not in the Dock".
static inline NSInteger MSBDActMonDockRecord(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return -1;
    double v = [value doubleValue];
    if (!(v >= 0.0) || v > 64.0 || v != floor(v)) return -1;
    return (NSInteger)v;
}

// ---- the running entry (1.7.7 item 1b, KT 1 Nov: an open app is in the Dock, as on a Mac) ----
// While its window exists (open, minimized, or on another desktop) and the user has not kept it in the Dock, Activity Monitor shows in the Dock as
// an open app: in the Dock's recent apps while the Dock shows them (iPadOS's own place for an open app that is not kept there) and that path is in,
// else after the Dock's own apps (a Mac's Dock). Never recorded, never in a saved layout; it leaves with the window.
typedef NS_ENUM(NSInteger, MSBDActMonSpot) { MSBDActMonSpotNone = 0, MSBDActMonSpotRecents, MSBDActMonSpotDockEnd };
static inline MSBDActMonSpot MSBDActMonRunningSpot(BOOL on, BOOL kept, BOOL windowExists, BOOL recentsShown) {
    if (!on || kept || !windowExists) return MSBDActMonSpotNone;
    return recentsShown ? MSBDActMonSpotRecents : MSBDActMonSpotDockEnd;
}
// The recents the Dock's shown list is made from, with ours first (the app in use: where iPadOS puts an app just opened) -- a copy, so the list
// SpringBoard keeps and saves never holds it. nil when ours is in it already or it is not an ordered set.
static inline NSMutableOrderedSet *MSBDActMonRecentsWithOurs(id recents, id ours) {
    if (![recents isKindOfClass:[NSOrderedSet class]] || !ours || [(NSOrderedSet *)recents containsObject:ours]) return nil;
    NSMutableOrderedSet *m = [(NSOrderedSet *)recents mutableCopy];
    [m insertObject:ours atIndex:0];
    return m;
}
// Its menu's Dock row: kept in the Dock -> Remove from Dock; the running entry's own icon (after the Dock's apps, or in the recents) -> Keep in Dock;
// anywhere else (the App Library) -> Add to Dock. Keep and Add both make it a kept icon, and need room unless it is in the Dock's list already.
typedef NS_ENUM(NSInteger, MSBDActMonRow) { MSBDActMonRowAdd = 0, MSBDActMonRowKeep, MSBDActMonRowRemove };
static inline MSBDActMonRow MSBDActMonMenuRow(BOOL kept, BOOL runningEntryHere) {
    return kept ? MSBDActMonRowRemove : runningEntryHere ? MSBDActMonRowKeep : MSBDActMonRowAdd;
}
// No longer kept (Remove from Dock, a drag out of the Dock, the Trash) while its window exists: it stays in the Dock as the running entry -- in its
// place when that entry goes after the Dock's apps (a Mac's Dock: an open app no longer kept stays until it quits); else it leaves the Dock's list
// (for the recents, or for good).
static inline BOOL MSBDActMonUnkeptStaysInPlace(BOOL on, BOOL windowExists, BOOL recentsShown) {
    return MSBDActMonRunningSpot(on, NO, windowExists, recentsShown) == MSBDActMonSpotDockEnd;
}

// ---- Command-Tab (1.7.8 item 10, KT 2 Nov: in iPadOS's own Command-Tab while its window exists, ordered by recency as the apps are) ----
// iPadOS's list is its recents, the most recent first. Ours goes where it was last used among them: first while its window is the active one,
// else after the apps that came to the front since it last was. Those are told from the recents as they were then (snapshot) and as they are now
// (current), bundle identifiers: an app brought to the front moves to the front of the list, so the apps used since are a leading run of the
// current list, and the rest is the snapshot's order without them (apps quit since gone from it). The shortest such run is the answer; no
// snapshot (never active since the start): after them all.
// usedSince: the apps seen in front since its window was last the active one (statusbar/ActMonDock.h, DMAMCmdTabTick and Command-Tab's pick). They
// are more recent than it whatever the recents show: the app in front behind it brought forward again (a touch on its window, its Dock icon,
// Command-Tab) leaves them as they were, and so does an app used and then left for the one before it -- the recents alone kept Activity Monitor
// first, and Command-Tab picked the app in front (iPad 2, 16.7.7). It goes after the last of them.
static inline NSUInteger MSBDActMonCmdTabIndex(NSArray<NSString *> *current, NSArray<NSString *> *snapshot, NSArray<NSString *> *usedSince, BOOL activeNow) {
    if (activeNow) return 0;
    if (![snapshot isKindOfClass:[NSArray class]]) return current.count;
    NSUInteger at = current.count;
    for (NSUInteger k = 0; k <= current.count; k++) {
        NSArray *used = [current subarrayWithRange:NSMakeRange(0, k)], *rest = [current subarrayWithRange:NSMakeRange(k, current.count - k)];
        NSMutableArray *expected = [NSMutableArray array];
        for (NSString *b in snapshot) if ([current containsObject:b] && ![used containsObject:b]) [expected addObject:b];
        if ([rest isEqualToArray:expected]) { at = k; break; }
    }
    for (NSUInteger i = current.count; i > at; i--) if ([usedSince isKindOfClass:[NSArray class]] && [usedSince containsObject:current[i - 1]]) return i;
    return at;
}

// ---- the App Library's search (1.7.3 item 13, AppLibraryApps.h): Activity Monitor is in the list exactly when the list's own text matches it ----
static inline NSString *MSBDALTrim(NSString *t) { return [t isKindOfClass:[NSString class]] ? [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @""; }
// The engine answered the library (SBHTableViewIconLibrary -engine:queryResultsWereUpdated:): the list hears of an answer only when it differs from
// the last one (nothing found and nothing found again, or the same apps for "Ac" and "Act", tell it nothing -- read on 18.5: the library gets every
// answer, its dispatch drops the unchanged ones). So when the answer is the one for the field's text -- nothing found carries no text of its own (never
// the empty search's answer); else its own text is the field's -- and what the list shows of ours is not what the field's text says, the list is
// given that answer (ours added or left out by the field's text). An answer for an older text is never given again: the list takes a result's own
// text as its current one.
static inline BOOL MSBDALGiveAnswer(BOOL answerNothingFound, NSString *answerText, NSString *fieldText, BOOL matchesField, BOOL shownNow) {
    if (matchesField == shownNow) return NO;
    if (answerNothingFound) return MSBDALTrim(fieldText).length > 0;
    return [answerText isKindOfClass:[NSString class]] && [fieldText isKindOfClass:[NSString class]] && [MSBDALTrim(answerText) isEqualToString:MSBDALTrim(fieldText)];
}
// A result with ours may be made anew (sorted by the query) only when neither the result's text nor the list's is empty: the A-Z list of the empty
// search is never made anew (18.5 hydrates it off the main queue and asserts: the crash 1d4ac5a fixed).
static inline BOOL MSBDALMayMakeAnew(NSString *resultText, NSString *listText) {
    return MSBDALTrim(resultText).length > 0 && MSBDALTrim(listText).length > 0;
}
