// ActMonDock.h -- Activity Monitor in the Dock (1.7.3 item 5): the rules that need no SpringBoard, Foundation only, so the Mac test
// (tools/test-actmondock.sh) runs the same code. SpringBoard's side: statusbar/ActMonDock.h.
//  - The Home Screen layout SpringBoard writes, without our icon (MSBDLayoutWithout): it is never saved, so no layout file of SpringBoard's ever
//    names it -- with the tweak removed, switched off, in Safe Mode or on an untested iPadOS there is no dead icon to clean up.
//  - Where it goes back into the Dock at start (MSBDActMonDockPlace), from our own record of its place.
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
