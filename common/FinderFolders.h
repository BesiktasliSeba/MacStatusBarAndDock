// FinderFolders.h -- Home Screen folders in the Finder menu (1.7.9 item 3, KT 2 Nov 2026): "Show in Finder Menu" / "Remove from Finder Menu" in a
// folder's Haptic Touch menu, and the menu bar's Finder menu lists the folders attached, as it lists the jailbreak folder (statusbar/FinderFolders.h).
// The record is the folders' own identity: SpringBoard's -[SBFolder uniqueIdentifier], the one IconState.plist keeps for each folder on 15, 16, 17
// and 18 (and Atria's copy of the layout, M1), so a folder keeps its place in the menu when it is renamed or moved to another page, and across
// resprings. In the order attached. Plain Foundation, Mac-tested (tools/test-finderfolders.sh).
#pragma once
#import <Foundation/Foundation.h>

#define MSBD_FINDER_FOLDERS_KEY "finderFolders"   // (com.besiktasliseba.macstatusbar: the attached folders' identifiers, an array, in the order attached)

// The record as stored: its strings, each once, in their order; anything else in it is left out (nothing stored: none attached).
static inline NSArray<NSString *> *MSBDFinderFoldersRecord(id stored) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    if (![stored isKindOfClass:[NSArray class]]) return out;
    for (id uid in (NSArray *)stored) if ([uid isKindOfClass:[NSString class]] && [(NSString *)uid length] && ![out containsObject:uid]) [out addObject:uid];
    return out;
}
// The record without the folders the Home Screen no longer has (deleted). present: every folder there now, hidden pages and the Dock included;
// nil when that is not known (nothing dropped then).
static inline NSArray<NSString *> *MSBDFinderFoldersPruned(NSArray<NSString *> *record, NSSet<NSString *> *present) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *uid in MSBDFinderFoldersRecord(record)) if (!present || [present containsObject:uid]) [out addObject:uid];
    return out;
}
// Attached: at the end, after the ones attached before (one attached again after its removal goes to the end). Folders no longer there go.
static inline NSArray<NSString *> *MSBDFinderFoldersAttach(NSArray<NSString *> *record, NSString *uid, NSSet<NSString *> *present) {
    NSMutableArray<NSString *> *out = [MSBDFinderFoldersPruned(record, present) mutableCopy];
    if ([uid isKindOfClass:[NSString class]] && uid.length && ![out containsObject:uid]) [out addObject:uid];
    return out;
}
// Removed: the others keep their order. Folders no longer there go.
static inline NSArray<NSString *> *MSBDFinderFoldersDetach(NSArray<NSString *> *record, NSString *uid, NSSet<NSString *> *present) {
    NSMutableArray<NSString *> *out = [MSBDFinderFoldersPruned(record, present) mutableCopy];
    if ([uid isKindOfClass:[NSString class]]) [out removeObject:uid];
    return out;
}
// The Finder menu's folder rows: the record's folders the Home Screen shows now (shown: on a page that is not hidden, or in the Dock), in the order
// attached; the jailbreak folder (jbUID) only once -- the menu lists it by itself, first.
static inline NSArray<NSString *> *MSBDFinderFoldersListed(NSArray<NSString *> *record, NSSet<NSString *> *shown, NSString *jbUID) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *uid in MSBDFinderFoldersRecord(record))
        if ([shown containsObject:uid] && !(jbUID && [uid isEqualToString:jbUID])) [out addObject:uid];
    return out;
}
// The rows' titles: each folder's name ("Folder" for one without); two rows of one name told apart by where they are -- "Games (Page 2)",
// "Games (Dock)" -- as Add App to Folder's list does. pages: each folder's page, 1 for the first shown one, 0 for the Dock.
static inline NSArray<NSString *> *MSBDFinderFolderTitles(NSArray<NSString *> *names, NSArray<NSNumber *> *pages) {
    NSMutableArray<NSString *> *plain = [NSMutableArray array];
    for (id n in names) [plain addObject:[n isKindOfClass:[NSString class]] && [(NSString *)n length] ? n : @"Folder"];
    NSCountedSet *seen = [[NSCountedSet alloc] initWithArray:plain];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < plain.count; i++) {
        NSInteger page = i < pages.count ? pages[i].integerValue : -1;
        if ([seen countForObject:plain[i]] < 2 || page < 0) { [out addObject:plain[i]]; continue; }
        [out addObject:[NSString stringWithFormat:@"%@ (%@)", plain[i], page ? [NSString stringWithFormat:@"Page %ld", (long)page] : @"Dock"]];
    }
    return out;
}
// The folder's own Haptic Touch row: what a tap on it does.
static inline NSString *MSBDFinderFolderMenuTitle(BOOL attached) { return attached ? @"Remove from Finder Menu" : @"Show in Finder Menu"; }
