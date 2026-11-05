// CC18MacLayout.h -- iPadOS 18, Control Center Style Mac: the Mac panel's own layout of tiles (1.8.1 item 1, plans/cc18tiles-1.8.1.md). 18 keeps its
// layout in SpringBoardHome's icon state (ControlsIconState.plist: pages of tiles, each with a grid size). While Mac is the style Apple's grid
// reads and saves another file of the same kind (statusbar/CC18Shape.h, the store's URLs): iPadOS's layout is never touched, and edit mode and the
// gallery work on this one as on Apple's. It is made once, the first time Mac is in force, from the user's own layout: our four Mac tiles at the top
// of the first page in place of the Apple tiles they stand for (the 15-17 panel's look: Connectivity beside the tiles that fit there, then Display,
// Sound and Now Playing, wide; the user's other tiles after them in the user's order, those that no longer fit on a page of their own after it).
// Foundation only: tools/test-cc18maclayout.sh runs this very code on the A12Z's own layout.
#pragma once
#import <Foundation/Foundation.h>
#include "CCModuleList.h"   // (our identifiers, their sizes)

#define kMSBDCC18AppleLayoutFile @"/var/mobile/Library/ControlCenter/ControlsIconState.plist"
#define kMSBDCC18MacLayoutFile @"/var/mobile/Library/ControlCenter/MacStatusBarAndDock-ControlsIconState.plist"
#define kMSBDCC18MacDesiredFile @"/var/mobile/Library/ControlCenter/MacStatusBarAndDock-ControlsDesiredIconState.plist"
#define kMSBDCC18GridColumns 4

// A grid size's name in the state file -> its columns and rows (18.5, the page layout's iconGridSizeClassSizes). NO: not known.
static inline BOOL MSBDCC18GridCells(NSString *size, int *w, int *h) {
    static const struct { const char *name; int w, h; } t[] = {
        { "small", 1, 1 }, { "smallTall", 1, 2 }, { "smallWide", 2, 1 }, { "smallExtraWide", 4, 1 }, { "medium", 2, 2 }, { "mediumWide", 4, 2 },
        { "large", 4, 4 }, { "largeTall", 4, 6 }, { "largeExtraTall", 4, 8 },
    };
    if (![size isKindOfClass:[NSString class]]) return NO;
    for (size_t i = 0; i < sizeof(t) / sizeof(t[0]); i++) if ([size isEqualToString:@(t[i].name)]) { if (w) *w = t[i].w; if (h) *h = t[i].h; return YES; }
    return NO;
}
// A page's entry -> its columns and rows. NO: not known -- a size of another name, or no tile at all: SpringBoardHome's icon state allows a bare identifier for a leaf icon, 18's own
// file has none as read on 18.5, and a dictionary read of one would take SpringBoard down at Control Center's build, at every start. Such an entry stays with the page, in its order.
static inline BOOL MSBDCC18EntryCells(id entry, int *w, int *h) {
    return [entry isKindOfClass:[NSDictionary class]] && MSBDCC18GridCells(((NSDictionary *)entry)[@"gridSize"], w, h);
}
// First fit in reading order, as Apple's lists place their tiles: the place of a w x h tile on a grid of cols x rows (cells: rows x cols, 0 free), taken. NO: no room.
static inline BOOL MSBDCC18GridPlace(unsigned char *cells, int cols, int rows, int w, int h) {
    if (!cells || w < 1 || h < 1 || w > cols || h > rows) return NO;
    for (int r = 0; r + h <= rows; r++) for (int c = 0; c + w <= cols; c++) {
        BOOL free = YES;
        for (int y = r; free && y < r + h; y++) for (int x = c; free && x < c + w; x++) free = !cells[y * cols + x];
        if (!free) continue;
        for (int y = r; y < r + h; y++) for (int x = c; x < c + w; x++) cells[y * cols + x] = 1;
        return YES;
    }
    return NO;
}
// A tile's single module (nil: a control, or more than one element).
static inline NSString *MSBDCC18TileModule(NSDictionary *tile) {
    NSArray *e = [tile isKindOfClass:[NSDictionary class]] ? tile[@"elements"] : nil;
    if (![e isKindOfClass:[NSArray class]] || e.count != 1 || ![e[0] isKindOfClass:[NSDictionary class]] || ![e[0][@"elementType"] isEqual:@"module"]) return nil;
    NSString *m = e[0][@"moduleIdentifier"];
    return [m isKindOfClass:[NSString class]] ? m : nil;
}
// Does this tile go from the Mac layout? One of ours (they are put back at the top, once each), or an Apple tile a Mac tile stands for: Display and
// Sound at any size (1 x 2 is all they have), Connectivity and Now Playing up to 4 x 2 -- their full pages (4 x 4 and more) stay the user's pages.
static inline BOOL MSBDCC18TileStoodFor(NSDictionary *tile) {
    NSString *m = MSBDCC18TileModule(tile);
    if (!m) return NO;
    if (MSBDCCIsMacTile(m)) return YES;
    if ([m isEqualToString:@"com.apple.control-center.DisplayModule"] || [m isEqualToString:@"com.apple.mediaremote.controlcenter.audio"]) return YES;
    if (![m isEqualToString:@"com.apple.control-center.ConnectivityModule"] && ![m isEqualToString:@"com.apple.mediaremote.controlcenter.nowplaying"]) return NO;
    int h = 0;
    return MSBDCC18GridCells(tile[@"gridSize"], NULL, &h) && h <= 2;
}
// A new tile for one of our modules, as Apple's own archive writes one.
static inline NSDictionary *MSBDCC18NewTile(NSString *module, NSString *(^uuid)(void)) {
    return @{ @"displayIdentifier": uuid(), @"iconType": @"custom", @"allowsSuggestions": @YES, @"allowsExternalSuggestions": @YES, @"gridSize": MSBDCCMacTileDefaultSize(module),
              @"elements": @[@{ @"elementType": @"module", @"dataSourceUniqueIdentifier": uuid(), @"containerBundleIdentifier": kMSBDCCSettingsAppID, @"moduleIdentifier": module }] };
}
// May the Mac layout be read now? 18 drops from the layout it reads every tile whose module is not in the repository, and saves that -- so it is read only with our
// Mac modules all there (`registered`: our controls in the repository; nil: MacCCGrabber not loaded), and any other control of ours its tiles hold: a crash guard's step
// 1b, Choicy or a safe mode then shows the user's own layout in the panel for that while, and the Mac layout comes back whole. SSH without OpenSSH (`sshInstalled` NO)
// does not count: that is no passing state, 18 drops its tile as in the user's own layout. `state`: the file, or nil where there is none yet.
static inline BOOL MSBDCC18LayoutHolds(NSDictionary *state, NSString *module) {
    NSArray *pages = [state isKindOfClass:[NSDictionary class]] ? state[@"iconLists"] : nil;
    if (![pages isKindOfClass:[NSArray class]]) return NO;
    for (NSArray *page in pages) if ([page isKindOfClass:[NSArray class]]) for (NSDictionary *t in page) if ([MSBDCC18TileModule(t) isEqual:module]) return YES;
    return NO;
}
static inline BOOL MSBDCC18MacLayoutReadable(NSDictionary *state, NSArray *registered, BOOL sshInstalled) {
    if (![registered isKindOfClass:[NSArray class]]) return NO;
    for (NSString *m in @[kMSBDCCMacConnectivityID, kMSBDCCMacDisplayID, kMSBDCCMacSoundID, kMSBDCCMacNowPlayingID]) if (![registered containsObject:m]) return NO;
    if (![registered containsObject:kMSBDCCModuleID] && MSBDCC18LayoutHolds(state, kMSBDCCModuleID)) return NO;
    if (sshInstalled && ![registered containsObject:kMSBDCCSSHModuleID] && MSBDCC18LayoutHolds(state, kMSBDCCSSHModuleID)) return NO;
    return YES;
}
// May the first Mac layout be made now? It is made from the user's, and 18 drops from what it reads every tile whose module is not there, and saves that -- so not while a control of
// ours the user's layout may hold is off (RAM & CPU, or SSH with OpenSSH there: a crash guard's step 1b): the Mac layout would lose that tile for good, also where the user's own has
// lost it for that while (its note puts it back there only, common/CCTileKeep.h, at the start the guard is cleared; that start makes the Mac layout, from the tile back in place).
static inline BOOL MSBDCC18MacLayoutMayBeMade(NSArray *registered, BOOL sshInstalled) {
    if (![registered isKindOfClass:[NSArray class]] || ![registered containsObject:kMSBDCCModuleID]) return NO;
    return !sshInstalled || [registered containsObject:kMSBDCCSSHModuleID];
}
// The Mac file as it is now: read (a layout, as far as a dictionary tells), or there but of no use now -- it could not be read (before a first unlock, say) or does not parse --: never
// made again over what it holds, Apple's file for that while; or not there: to be made.
enum { kMSBDCC18MacFileUse, kMSBDCC18MacFileAppleForNow, kMSBDCC18MacFileMake };
static inline int MSBDCC18MacFileStep(BOOL there, id parsed) {
    if ([parsed isKindOfClass:[NSDictionary class]]) return kMSBDCC18MacFileUse;
    return there ? kMSBDCC18MacFileAppleForNow : kMSBDCC18MacFileMake;
}
static inline NSArray *MSBDCC18RotatedOrder(NSArray *page) {
    NSMutableArray *ids = [NSMutableArray array];
    for (id t in page) {   // (a bare identifier is its own, as in Apple's lists; nothing else has one)
        id d = [t isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)t)[@"displayIdentifier"] : t;
        if ([d isKindOfClass:[NSString class]]) [ids addObject:d];
    }
    return ids;
}
// The Mac layout from the user's own: `state` as Apple's file holds it, `rows` the most rows a page has (8 on 18.5; on a page with fewer Apple's model moves what does not fit),
// `uuid` a new identifier.
// nil when it is not a layout we can read: Mac then shows the user's own (nothing written).
static inline NSDictionary *MSBDCC18MacLayoutFrom(NSDictionary *state, int rows, NSString *(^uuid)(void)) {
    if (![state isKindOfClass:[NSDictionary class]] || !uuid || rows < 5 || rows > 32) return nil;
    NSArray *lists = state[@"iconLists"], *listIDs = state[@"listUniqueIdentifiers"];
    NSDictionary *meta = state[@"listMetadata"];
    if (![lists isKindOfClass:[NSArray class]] || ![listIDs isKindOfClass:[NSArray class]] || listIDs.count != lists.count || (meta && ![meta isKindOfClass:[NSDictionary class]])) return nil;
    NSMutableArray *pages = [NSMutableArray array], *ids = [NSMutableArray array];
    NSMutableDictionary *newMeta = [(meta ?: @{}) mutableCopy];
    for (NSUInteger i = 0; i < lists.count; i++) {   // (every page without the tiles that go; a page left empty goes too, the first one stays ours)
        if (![lists[i] isKindOfClass:[NSArray class]] || ![listIDs[i] isKindOfClass:[NSString class]]) return nil;
        NSMutableArray *kept = [NSMutableArray array];
        for (NSDictionary *t in lists[i]) if (!MSBDCC18TileStoodFor(t)) [kept addObject:t];
        if (!kept.count && i > 0) { [newMeta removeObjectForKey:listIDs[i]]; continue; }
        [pages addObject:kept]; [ids addObject:listIDs[i]];
    }
    if (!pages.count) { [pages addObject:[NSMutableArray array]]; [ids addObject:uuid()]; }
    // The first page: Connectivity, the tiles of the user's that fit beside it (the two rows it takes, in the user's order), the three wide ones, the rest.
    NSMutableArray *first = [NSMutableArray array], *rest = [NSMutableArray array];
    [first addObject:MSBDCC18NewTile(kMSBDCCMacConnectivityID, uuid)];
    unsigned char beside[2 * kMSBDCC18GridColumns] = { 1, 1, 0, 0, 1, 1, 0, 0 };   // (Connectivity's 2 x 2 at the left of the two rows)
    int w, h;
    for (id t in pages[0]) {
        if (MSBDCC18EntryCells(t, &w, &h) && MSBDCC18GridPlace(beside, kMSBDCC18GridColumns, 2, w, h)) [first addObject:t];
        else [rest addObject:t];
    }
    [first addObject:MSBDCC18NewTile(kMSBDCCMacDisplayID, uuid)]; [first addObject:MSBDCC18NewTile(kMSBDCCMacSoundID, uuid)]; [first addObject:MSBDCC18NewTile(kMSBDCCMacNowPlayingID, uuid)];
    [first addObjectsFromArray:rest];
    // What does not fit in the page's rows, in order, on a new page right after it (Apple's model would otherwise decide; a tile of an unknown size stays).
    unsigned char *cells = calloc((size_t)rows * kMSBDCC18GridColumns, 1);
    if (!cells) return nil;
    NSMutableArray *fit = [NSMutableArray array], *over = [NSMutableArray array];
    for (id t in first) {
        if (!MSBDCC18EntryCells(t, &w, &h) || MSBDCC18GridPlace(cells, kMSBDCC18GridColumns, rows, w, h)) [fit addObject:t];
        else [over addObject:t];
    }
    free(cells);
    pages[0] = fit;
    if (over.count) {
        NSString *pid = uuid();
        [pages insertObject:over atIndex:1]; [ids insertObject:pid atIndex:1];
    }
    for (NSUInteger i = 0; i < pages.count; i++) {   // (Apple's other orientation's order: this order, where we changed a page)
        NSDictionary *was = newMeta[ids[i]];
        NSMutableDictionary *m = [was isKindOfClass:[NSDictionary class]] ? [was mutableCopy] : [NSMutableDictionary dictionary];
        m[@"rotatedOrder"] = MSBDCC18RotatedOrder(pages[i]);
        newMeta[ids[i]] = m;
    }
    NSMutableDictionary *out = [state mutableCopy];
    out[@"iconLists"] = pages; out[@"listUniqueIdentifiers"] = ids; out[@"listMetadata"] = newMeta;
    return out;
}
