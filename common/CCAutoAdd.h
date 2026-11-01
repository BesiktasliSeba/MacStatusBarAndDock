// CCAutoAdd.h -- RAM & CPU (ccmodule/, our Activity Monitor tile) put in Control Center by itself, once per iPad, where there is room for it (1.7.7
// item 8; KT: "if a user has a space in their control center for our activity monitor tile in an install, whether it's an existing or a new user,
// let's add the tile"). The decisions only, Foundation, so the Mac test (tools/test-ccautoadd.sh) runs this very code; SpringBoard measures
// Control Center and adds the control through Control Center's own path (statusbar/StatusBar.x, DMCCAutoAdd...).
//
// When: the first time Control Center is opened and closed after SpringBoard starts with a version that has not looked yet -- a new install and
// the first start after an update alike: measured while it shows (only a Control Center that is laid out and on screen tells its real sizes and
// which one shows; asking its objects before SpringBoard makes them would make them early), added once it has closed. Added the way Settings >
// Control Center's + adds a control: at the end of the user's list, through Control Center's own settings provider, which saves it in its own
// file (Apple's, or CCSupport's where it is installed) and lays it out.
//
// Room, per Control Center (nothing pushed, moved or resized, nothing made to scroll, no new page; where it cannot be told for sure: not added):
//  - Apple's Control Center on 15-17, with Apple's list or CCSupport's (CCSupport changes the list, not the grid): Control Center's own position
//    provider packs the controls into a grid CCUICompactModuleColumns() wide that grows downwards, in Control Center's order (its fixed controls,
//    then the user's list); on iPad one packing serves both orientations. The overlay shows the grid under its header and scrolls once grid and
//    header are taller than the screen. Room: with RAM & CPU (2 x 1) at the end of the list, the same packing leaves every control in its place at
//    its size, the grid grows by one row at most, and grid and header still fit the screen's shorter side (the overlay's height on its side, the
//    smaller of the two), so it scrolls in neither orientation. A free 2 x 1 place in a row the grid has already counts the same (no growth).
//  - BigSurCenter (15/16 with CCSupport: the M1, the iPad 2): its panel at the right has its own rows (connectivity, grouped toggles, sliders,
//    media, power) above a grid of square tiles -- every other control in CCSupport's list, in its order --, a few to a row. The panel grows with
//    the grid up to the screen's shorter side less 40 pt (one limit for both orientations; with our Control Center Size, the height StatusBar.x's
//    BSCHeightFix gives it) and scrolls beyond. Room: RAM & CPU as the grid's last tile, in the last row's free place or in one more row the panel
//    can still grow by. BigSurCenter reads the list only when SpringBoard starts: the tile shows from the next start, as any change made in
//    Settings > Control Center does with BigSurCenter.
//  - 18: pages of a fixed grid (SpringBoardHome's icon lists, ControlsIconState.plist; the grid per orientation from Control Center's own layout,
//    ControlCenterUI.ControlsIconModelLoader -iconModel:maxColumnCountForListInRootFolderWithInterfaceOrientation: / ...maxRowCount...), tiles of
//    fixed sizes that can sit anywhere. Room would be an existing page with a free 2 x 1 place in both orientations' grids that leaves every tile
//    where it is -- never a new page. Its add path is Control Center's own "Add to Control Center" (-[CCUIPagingViewController
//    handleIconElementRequest:completionHandler:] with a CCSIconElementRequest, read on 18.5), whose placement can only be learned by trying it on an
//    iPad: so 1.7.7 adds nothing on 18; it only marks an iPad whose layout has the tile already, so a later add never puts it back after removal.
//
// Once only (our main preferences: kept through updates and the package's removal, as the Memory Magic offer's Not Now):
//  - kMSBDCCAutoAddDone: done for good on this iPad, with why -- "added" (put there by this), "there" (it was in Control Center already),
//    "memory-magic" (Memory Magic's tile is in Control Center with ours drawn over it: the user has it), "removed" (taken out in Settings > Control
//    Center at some time: it is among the list's disabled controls). Never added after that, whatever becomes of the tile: removed by the user, the
//    package removed and installed again -- except where the package's removal itself takes it out of Control Center (MSBDCCAutoAddForgetOnRemoval):
//    an "added" or "there" marker goes with it, so the next install puts it back where there is room.
//  - kMSBDCCAutoAddNoRoom: the version that found no room; looked at again only when another version starts (the next update).
#pragma once
#import <Foundation/Foundation.h>
#include <math.h>
#include "CCModuleList.h"   // (kMSBDCCModuleID, kMSBDMemoryMagicID)

#define kMSBDCCAutoAddDone @"ccAutoAddRAMCPU"
#define kMSBDCCAutoAddNoRoom @"ccAutoAddRAMCPUNoRoom"
#define kMSBDCCAutoAddMemoryMagicBundle "/var/jb/Library/ControlCenter/Bundles/MemoryMagicCCBundle.bundle"   // (CCSupport's folder: Memory Magic's module loads)
#define kMSBDCCAutoAdd18LayoutFile @"/var/mobile/Library/ControlCenter/ControlsIconState.plist"   // (18.5: Control Center's layout = CCTileKeep.h's kMSBDCCTileStateFile)
// MacCCGrabber (macsettings/CCGrabber.x) answers whether RAM & CPU is in Control Center's module repository in SpringBoard now (found with dlsym:
// another of our parts; a SpringBoard without that part asks again and gets no)
#define kMSBDCCRAMCPURegisteredFn "MSBDCCRAMCPURegistered"

// Is a look due? done: the marker as stored (any value: done); noRoom: the version that found no room; version: the one running now.
static inline BOOL MSBDCCAutoAddDue(id done, id noRoom, NSString *version) {
    if (done) return NO;
    return !([noRoom isKindOfClass:[NSString class]] && [version isKindOfClass:[NSString class]] && [noRoom isEqualToString:version]);
}

// What the user's lists say (15-17: the settings provider's ordered list and its disabled controls). memoryMagicTile: Memory Magic's module loads
// and our status bar part draws RAM & CPU's numbers over its tile.
typedef enum { kMSBDCCListAbsent = 0, kMSBDCCListThere, kMSBDCCListRemoved, kMSBDCCListMemoryMagic } MSBDCCListState;
static inline MSBDCCListState MSBDCCAutoAddListState(NSArray *enabled, NSArray *disabled, BOOL memoryMagicTile) {
    if ([enabled isKindOfClass:[NSArray class]] && [enabled containsObject:kMSBDCCModuleID]) return kMSBDCCListThere;
    if ([disabled isKindOfClass:[NSArray class]] && [disabled containsObject:kMSBDCCModuleID]) return kMSBDCCListRemoved;   // (Settings' -: never back)
    if (memoryMagicTile && [enabled isKindOfClass:[NSArray class]] && [enabled containsObject:kMSBDMemoryMagicID]) return kMSBDCCListMemoryMagic;
    return kMSBDCCListAbsent;
}
static inline NSString *MSBDCCAutoAddDoneReason(MSBDCCListState s) {   // (the marker's value; nil: not done)
    return s == kMSBDCCListThere ? @"there" : s == kMSBDCCListRemoved ? @"removed" : s == kMSBDCCListMemoryMagic ? @"memory-magic" : nil;
}
// The user's list with RAM & CPU added where Settings' + adds a control: at the end, every other control in its order; nil when it is there.
static inline NSArray *MSBDCCAutoAddList(NSArray *enabled) {
    if (![enabled isKindOfClass:[NSArray class]] || [enabled containsObject:kMSBDCCModuleID]) return nil;
    return [enabled arrayByAddingObject:kMSBDCCModuleID];
}

// 18: the layout (ControlsIconState.plist as a dictionary) has a tile of RAM & CPU -- on a page or anywhere else in it (SpringBoardHome keeps
// icons in other lists too).
static inline BOOL MSBDCCAutoAddLayoutHasOurs(id node, int depth) {
    if (depth > 16) return NO;
    if ([node isKindOfClass:[NSDictionary class]]) {
        if ([((NSDictionary *)node)[@"moduleIdentifier"] isEqual:kMSBDCCModuleID]) return YES;
        for (id k in (NSDictionary *)node) if (MSBDCCAutoAddLayoutHasOurs(((NSDictionary *)node)[k], depth + 1)) return YES;
    } else if ([node isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)node) if (MSBDCCAutoAddLayoutHasOurs(v, depth + 1)) return YES;
    }
    return NO;
}

// The package's removal (sshtoggled --uninstall, the prerm): does the marker go? It takes RAM & CPU out of Control Center -- out of the 15-17 lists
// of controls (the helper edits the files, SpringBoard its own list), and on 18 SpringBoard drops the tile of a module that is gone at its next start
// (the postrm drops CCTileKeep.h's record of its place) -- so a marker that says it was in Control Center, "added" or "there", would keep it out for
// good after a reinstall (1.7.7, the 17.5: removed and installed again, the tile was gone and never came back). It goes where the control is in
// Control Center now: in an enabled list of a 15-17 file (Apple's and CCSupport's, as dictionaries) and among no file's disabled controls -- the
// user's own removal stays one --, or a tile in 18's layout. "removed" and "memory-magic" always stay. Read before SpringBoard is told: its list
// saved without ours on the removal's note tells nothing any more.
static inline BOOL MSBDCCAutoAddForgetOnRemoval(id marker, NSArray *lists, id layout18) {
    if (![marker isEqual:@"added"] && ![marker isEqual:@"there"]) return NO;
    BOOL shown = NO;
    for (NSDictionary *list in [lists isKindOfClass:[NSArray class]] ? lists : @[]) {
        if (![list isKindOfClass:[NSDictionary class]]) continue;
        NSArray *off = list[@"disabled-module-identifiers"];
        if ([off isKindOfClass:[NSArray class]] && [off containsObject:kMSBDCCModuleID]) return NO;
        for (NSString *key in @[@"module-identifiers", @"userenabled-fixed-module-identifiers"]) {
            NSArray *ids = list[key];
            if ([ids isKindOfClass:[NSArray class]] && [ids containsObject:kMSBDCCModuleID]) shown = YES;
        }
    }
    return shown || ([layout18 isKindOfClass:[NSDictionary class]] && MSBDCCAutoAddLayoutHasOurs(layout18, 0));
}

// Apple's Control Center (15-17), as measured in SpringBoard (Control Center's own objects; StatusBar.x DMCCMeasureApple).
typedef struct {
    BOOL othersStay;                          // every control has the same place and size with ours added (both orientations' packings)
    unsigned long long rowsNow, rowsWith;     // the grid's rows now, and with ours
    double contentNow;                        // the overlay's content height now (points)
    double rowPitch;                          // what one more row adds to it (Control Center's own frame for the next row)
    double insets;                            // the overlay's top and bottom insets (its header)
    double heights[2];                        // the overlay's height upright and on its side
} MSBDCCAppleGrid;
static inline BOOL MSBDCCAppleGridRoom(MSBDCCAppleGrid g, NSString **why) {
    NSString *w; BOOL room = NO;
    double limit = fmin(g.heights[0], g.heights[1]), need = g.contentNow + (double)(g.rowsWith > g.rowsNow ? g.rowsWith - g.rowsNow : 0) * g.rowPitch + g.insets;
    if (!(limit > 0.0) || !(g.contentNow > 0.0) || !(g.rowPitch > 0.0) || !g.rowsNow || g.rowsWith < g.rowsNow) w = @"the measures do not add up: not told";
    else if (!g.othersStay) w = @"ours at the end would move or resize another control";
    else if (g.rowsWith > g.rowsNow + 1) w = [NSString stringWithFormat:@"ours would add %llu rows", g.rowsWith - g.rowsNow];
    else if (need > limit + 0.5) w = [NSString stringWithFormat:@"%.0f pt with ours (%@), the screen's shorter side gives %.0f: it would scroll", need,
        g.rowsWith > g.rowsNow ? @"one more row" : @"in a free place", limit];
    else { room = YES; w = [NSString stringWithFormat:@"%@: %.0f of %.0f pt", g.rowsWith > g.rowsNow ? @"one more row" : @"a free place in the rows there", need, limit]; }
    if (why) *why = w;
    return room;
}

// BigSurCenter's grid (StatusBar.x DMCCMeasureBSC): its tiles and columns, the panel height its grid needs now (BigSurCenter's own sum: the grid's
// top in the panel + its content + 20), one row more, and the height the panel can grow to.
typedef struct { unsigned long tiles, columns; double needNow, rowPitch, cap; } MSBDCCBSCGrid;
static inline BOOL MSBDCCBSCGridRoom(MSBDCCBSCGrid g, NSString **why) {
    NSString *w; BOOL room = NO;
    BOOL newRow = g.columns && g.tiles % g.columns == 0;   // (the last row is full, or there is none)
    double need = g.needNow + (newRow ? g.rowPitch : 0.0);
    if (!g.columns || !g.tiles || !(g.needNow > 0.0) || !(g.rowPitch > 0.0) || !(g.cap > 0.0)) w = @"the measures do not add up: not told";
    else if (g.needNow > g.cap + 0.5) w = [NSString stringWithFormat:@"the panel scrolls already (%.0f pt of %.0f)", g.needNow, g.cap];
    else if (need > g.cap + 0.5) w = [NSString stringWithFormat:@"one more row would need %.0f pt, the panel grows to %.0f: it would scroll", need, g.cap];
    else { room = YES; w = [NSString stringWithFormat:@"%@: %.0f of %.0f pt", newRow ? @"one more row" : @"the last row's free place", need, g.cap]; }
    if (why) *why = w;
    return room;
}
