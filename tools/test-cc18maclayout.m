// Mac test of common/CC18MacLayout.h (run by test-cc18maclayout.sh): the Mac panel's own layout on iPadOS 18, made from the user's.
#import <Foundation/Foundation.h>
#include "../common/CC18MacLayout.h"
static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); printf(__VA_ARGS__); printf("\n"); } else { fails++; printf("FAIL  "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static int gN = 0;
static NSString *U(void) { return [NSString stringWithFormat:@"U-%d", ++gN]; }
static NSDictionary *Tile(NSString *mid, NSString *size) {
    return @{ @"displayIdentifier": U(), @"gridSize": size, @"iconType": @"custom", @"elements": @[@{ @"elementType": @"module", @"moduleIdentifier": mid, @"dataSourceUniqueIdentifier": U(), @"containerBundleIdentifier": @"com.apple.springboard" }] };
}
static NSDictionary *Ctl(NSString *kind, NSString *size) {
    return @{ @"displayIdentifier": U(), @"gridSize": size, @"iconType": @"custom", @"elements": @[@{ @"elementType": @"control", @"controlKind": kind, @"dataSourceUniqueIdentifier": U() }] };
}
static NSString *Name(id t) {
    if (![t isKindOfClass:[NSDictionary class]]) return [t description];
    NSString *m = MSBDCC18TileModule(t);
    return m ?: t[@"elements"][0][@"controlKind"];
}
static NSArray *Names(NSArray *page) { NSMutableArray *a = [NSMutableArray array]; for (id t in page) [a addObject:Name(t)]; return a; }
#define CONN @"com.apple.control-center.ConnectivityModule"
#define NOW @"com.apple.mediaremote.controlcenter.nowplaying"
#define DISP @"com.apple.control-center.DisplayModule"
#define AUD @"com.apple.mediaremote.controlcenter.audio"
int main(void) {
    @autoreleasepool {
        // The grid
        int w = 0, h = 0;
        CHECK(MSBDCC18GridCells(@"smallExtraWide", &w, &h) && w == 4 && h == 1, "4 x 1 is smallExtraWide (the page layout's sizes, 18.5)");
        CHECK(MSBDCC18GridCells(@"largeExtraTall", &w, &h) && w == 4 && h == 8, "a full page is largeExtraTall, 4 x 8");
        CHECK(!MSBDCC18GridCells(@"nonsense", &w, &h) && !MSBDCC18GridCells((NSString *)@1, &w, &h), "an unknown size: not known");
        unsigned char c[8] = { 0 };
        CHECK(MSBDCC18GridPlace(c, 4, 2, 2, 2) && c[0] && c[1] && c[4] && c[5] && !c[2], "first fit: a 2 x 2 at the top left");
        CHECK(MSBDCC18GridPlace(c, 4, 2, 1, 1) && c[2] && !c[3], "  ... the next tile beside it");
        CHECK(MSBDCC18GridPlace(c, 4, 2, 2, 1) && c[6] && c[7], "  ... a 2 x 1 where it fits (the row below), not over anything");
        CHECK(!MSBDCC18GridPlace(c, 4, 2, 2, 1), "  ... no room: no");
        CHECK(MSBDCC18GridPlace(c, 4, 2, 1, 1) && c[3], "  ... a 1 x 1 still in the last free cell");
        // Which tiles go
        CHECK(MSBDCC18TileStoodFor(Tile(CONN, @"medium")), "Apple's Connectivity tile goes");
        CHECK(!MSBDCC18TileStoodFor(Tile(CONN, @"largeExtraTall")), "  ... its full page stays the user's");
        CHECK(MSBDCC18TileStoodFor(Tile(NOW, @"medium")) && MSBDCC18TileStoodFor(Tile(NOW, @"smallExtraWide")) && MSBDCC18TileStoodFor(Tile(NOW, @"mediumWide")), "Apple's Now Playing tile goes, up to 4 x 2");
        CHECK(!MSBDCC18TileStoodFor(Tile(NOW, @"large")) && !MSBDCC18TileStoodFor(Tile(NOW, @"largeExtraTall")), "  ... its full pages stay");
        CHECK(MSBDCC18TileStoodFor(Tile(DISP, @"smallTall")) && MSBDCC18TileStoodFor(Tile(AUD, @"smallTall")), "Apple's Display and Sound go (1 x 2 is all they have)");
        CHECK(MSBDCC18TileStoodFor(Tile(kMSBDCCMacSoundID, @"smallExtraWide")), "one of ours already there: put back at the top, once");
        CHECK(!MSBDCC18TileStoodFor(Tile(@"com.apple.FocusUIModule", @"smallWide")) && !MSBDCC18TileStoodFor(Ctl(@"com.apple.camera.deeplink.button", @"small")), "the user's other tiles and controls stay");
        // KT's own layout (A12Z 18.5: page 1, Now Playing's page, Connectivity's page)
        NSArray *p1 = @[Tile(CONN, @"medium"), Tile(NOW, @"medium"), Tile(@"com.apple.control-center.OrientationLockModule", @"small"), Tile(@"com.apple.mediaremote.controlcenter.airplaymirroring", @"small"),
            Tile(DISP, @"smallTall"), Tile(AUD, @"smallTall"), Tile(@"com.apple.FocusUIModule", @"smallWide"), Tile(@"com.apple.control-center.MuteModule", @"small"), Tile(@"com.apple.springboard.ContinuousExposeModule", @"small"),
            Tile(@"com.apple.control-center.QuickNoteModule", @"small"), Ctl(@"com.apple.camera.deeplink.button", @"small"), Ctl(@"calculator", @"small"), Tile(@"com.apple.replaykit.controlcenter.screencapture", @"small"),
            Tile(@"com.apple.keyboard.KeyboardBrightnessModule", @"small"), Tile(@"com.apple.mobiletimer.controlcenter.timer", @"small"), Tile(@"com.apple.control-center.LowPowerModule", @"small"),
            Tile(kMSBDCCModuleID, @"smallWide"), Tile(@"com.apple.accessibility.controlcenter.hearingdevices", @"small"), Tile(kMSBDCCSSHModuleID, @"small")];
        NSArray *p2 = @[Tile(NOW, @"largeExtraTall")], *p3 = @[Tile(CONN, @"largeExtraTall")];
        NSDictionary *state = @{ @"iconLists": @[p1, p2, p3], @"listUniqueIdentifiers": @[@"L1", @"L2", @"L3"], @"uniqueIdentifier": @"control-center-root", @"widgetVersion": @1000, @"buttonBar": @[], @"displayName": @"Control Center Root",
            @"listMetadata": @{ @"L1": @{ @"rotatedOrder": @[@"x"] }, @"L2": @{ @"rotatedOrder": @[p2[0][@"displayIdentifier"]] }, @"L3": @{ @"rotatedOrder": @[p3[0][@"displayIdentifier"]] } } };
        NSDictionary *mac = MSBDCC18MacLayoutFrom(state, 8, ^NSString *{ return U(); });
        NSArray *pages = mac[@"iconLists"];
        CHECK(mac != nil && pages.count == 4, "made: page 1, the tile that no longer fits on a page of its own, the two full pages (%lu)", (unsigned long)pages.count);
        NSArray *first = Names(pages[0]);
        NSArray *wantFirst = @[kMSBDCCMacConnectivityID, @"com.apple.control-center.OrientationLockModule", @"com.apple.mediaremote.controlcenter.airplaymirroring", @"com.apple.FocusUIModule", kMSBDCCMacDisplayID, kMSBDCCMacSoundID, kMSBDCCMacNowPlayingID,
            @"com.apple.control-center.MuteModule", @"com.apple.springboard.ContinuousExposeModule", @"com.apple.control-center.QuickNoteModule", @"com.apple.camera.deeplink.button", @"calculator", @"com.apple.replaykit.controlcenter.screencapture",
            @"com.apple.keyboard.KeyboardBrightnessModule", @"com.apple.mobiletimer.controlcenter.timer", @"com.apple.control-center.LowPowerModule", kMSBDCCModuleID, @"com.apple.accessibility.controlcenter.hearingdevices"];
        CHECK([first isEqualToArray:wantFirst], "page 1 as the 15-17 panel's: Connectivity, the tiles that fit beside it, Display, Sound, Now Playing wide, then the user's order");
        CHECK([Names(pages[1]) isEqualToArray:@[kMSBDCCSSHModuleID]], "  ... what does not fit in its 8 rows on a new page right after it");
        CHECK([Names(pages[2]) isEqualToArray:@[NOW]] && [Names(pages[3]) isEqualToArray:@[CONN]], "the user's full pages stay, after it, in order");
        CHECK([mac[@"listUniqueIdentifiers"] count] == 4 && [mac[@"listUniqueIdentifiers"][0] isEqual:@"L1"] && [mac[@"listUniqueIdentifiers"][2] isEqual:@"L2"] && [mac[@"listUniqueIdentifiers"][3] isEqual:@"L3"], "each page keeps its identifier, the new one has its own");
        NSMutableArray *order = [NSMutableArray array]; for (NSDictionary *t in pages[0]) [order addObject:t[@"displayIdentifier"]];
        CHECK([mac[@"listMetadata"][@"L1"][@"rotatedOrder"] isEqualToArray:order], "the other orientation's order follows");
        CHECK([mac[@"listMetadata"][mac[@"listUniqueIdentifiers"][1]][@"rotatedOrder"] count] == 1, "  ... the new page's too");
        NSDictionary *ours = pages[0][0];
        CHECK([ours[@"gridSize"] isEqual:@"medium"] && [pages[0][4][@"gridSize"] isEqual:@"smallExtraWide"] && [ours[@"iconType"] isEqual:@"custom"] && [ours[@"allowsSuggestions"] boolValue] && [ours[@"elements"][0][@"containerBundleIdentifier"] isEqual:kMSBDCCSettingsAppID], "our tiles as Apple's archive writes one (2 x 2 and 4 x 1, Settings' section)");
        CHECK([mac[@"uniqueIdentifier"] isEqual:@"control-center-root"] && [mac[@"widgetVersion"] isEqual:@1000] && mac[@"buttonBar"] && [mac[@"displayName"] isEqual:@"Control Center Root"], "the rest of the state as the user's");
        CHECK(state[@"iconLists"] == (id)state[@"iconLists"] && [state[@"iconLists"][0] count] == 19, "the user's own layout untouched");
        unsigned char *cells = calloc(8 * 4, 1); BOOL allFit = YES;
        for (NSDictionary *t in pages[0]) { MSBDCC18GridCells(t[@"gridSize"], &w, &h); allFit = allFit && MSBDCC18GridPlace(cells, 4, 8, w, h); }
        free(cells);
        CHECK(allFit, "page 1 fits its 8 rows by Apple's first fit");
        // Other layouts
        NSDictionary *made = MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[]], @"listUniqueIdentifiers": @[@"A"] }, 8, ^NSString *{ return U(); });
        CHECK(Names(made[@"iconLists"][0]).count == 4 && [Names(made[@"iconLists"][0])[0] isEqual:kMSBDCCMacConnectivityID], "an empty layout: our four");
        made = MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[Tile(DISP, @"smallTall")], @[Tile(AUD, @"smallTall")], @[Tile(@"x", @"small")]], @"listUniqueIdentifiers": @[@"A", @"B", @"C"], @"listMetadata": @{ @"B": @{} } }, 8, ^NSString *{ return U(); });
        CHECK([made[@"iconLists"] count] == 2 && [made[@"listUniqueIdentifiers"][1] isEqual:@"C"] && !made[@"listMetadata"][@"B"], "a page left empty goes, with its identifier and its metadata");
        made = MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[Tile(kMSBDCCMacDisplayID, @"smallExtraWide"), Tile(kMSBDCCMacDisplayID, @"smallWide")]], @"listUniqueIdentifiers": @[@"A"] }, 8, ^NSString *{ return U(); });
        int disp = 0; for (NSString *n in Names(made[@"iconLists"][0])) if ([n isEqual:kMSBDCCMacDisplayID]) disp++;
        CHECK(disp == 1, "ours once each, however many the user's has");
        made = MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[Tile(@"big", @"large")]], @"listUniqueIdentifiers": @[@"A"] }, 8, ^NSString *{ return U(); });
        NSArray *four = @[kMSBDCCMacConnectivityID, kMSBDCCMacDisplayID, kMSBDCCMacSoundID, kMSBDCCMacNowPlayingID];
        CHECK([Names(made[@"iconLists"][0]) isEqualToArray:four] && [Names(made[@"iconLists"][1]) isEqualToArray:@[@"big"]], "a tile too large for the room left: on the new page");
        made = MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[Tile(@"odd", @"tomorrowsSize")]], @"listUniqueIdentifiers": @[@"A"] }, 8, ^NSString *{ return U(); });
        CHECK([Names(made[@"iconLists"][0]).lastObject isEqual:@"odd"], "a tile of an unknown size stays on the page (Apple's model places it)");
        // A page's entry that is no tile (code review 1.8.1, 4: SpringBoardHome's icon state allows a bare identifier for a leaf icon; a dictionary read of it took SpringBoard down at Control Center's build)
        NSDictionary *bare = @{ @"iconLists": @[@[@"com.example.leaf", Tile(@"com.apple.FocusUIModule", @"smallWide"), @7, Tile(DISP, @"smallTall")], @[@"com.example.other"]], @"listUniqueIdentifiers": @[@"A", @"B"] };
        @try {
            made = MSBDCC18MacLayoutFrom(bare, 8, ^NSString *{ return U(); });
            CHECK(made != nil, "a bare identifier and a number on page 1: the layout is made");
            NSArray *n1 = Names(made[@"iconLists"][0]);
            NSArray *want1 = @[kMSBDCCMacConnectivityID, @"com.apple.FocusUIModule", kMSBDCCMacDisplayID, kMSBDCCMacSoundID, kMSBDCCMacNowPlayingID, @"com.example.leaf", @"7"];
            CHECK([n1 isEqualToArray:want1], "  ... each stays on the page after our tiles (with the rest), in the user's order; the tile that fits goes beside Connectivity");
            CHECK([Names(made[@"iconLists"][1]) isEqualToArray:@[@"com.example.other"]], "  ... on another page too");
            CHECK([made[@"listMetadata"][@"A"][@"rotatedOrder"] containsObject:@"com.example.leaf"] && ![made[@"listMetadata"][@"A"][@"rotatedOrder"] containsObject:@7] && [made[@"listMetadata"][@"B"][@"rotatedOrder"] isEqualToArray:@[@"com.example.other"]], "  ... the other orientation's order has the identifier, never the number");
            CHECK([NSPropertyListSerialization dataWithPropertyList:made format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil] != nil, "  ... and it can be written");
            int a, b;
            CHECK(!MSBDCC18EntryCells(@"com.example.leaf", &a, &b) && !MSBDCC18EntryCells(@7, &a, &b) && !MSBDCC18EntryCells(nil, &a, &b) && !MSBDCC18EntryCells(@{ @"gridSize": @3 }, &a, &b), "  ... no cells for what is no tile");
            CHECK(MSBDCC18EntryCells(Tile(CONN, @"medium"), &a, &b) && a == 2 && b == 2, "  ... a tile's own");
            CHECK([MSBDCC18RotatedOrder(@[@"id", @5, @{ @"displayIdentifier": @"D" }, @{ @"displayIdentifier": @9 }, @{}]) isEqualToArray:(@[@"id", @"D"])], "  ... the rotated order takes identifiers only");
        } @catch (NSException *e) { CHECK(NO, "a page's entry that is no tile threw %s: SpringBoard would crash at every start", e.name.UTF8String); }
        CHECK(!MSBDCC18MacLayoutFrom(nil, 8, ^NSString *{ return U(); }) && !MSBDCC18MacLayoutFrom((NSDictionary *)@[], 8, ^NSString *{ return U(); }), "nothing to read: none made");
        CHECK(!MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[]] }, 8, ^NSString *{ return U(); }), "  ... pages and identifiers that do not match: none made");
        CHECK(!MSBDCC18MacLayoutFrom(@{ @"iconLists": @[@[]], @"listUniqueIdentifiers": @[@"A"] }, 3, ^NSString *{ return U(); }), "  ... nonsense rows: none made");
        // May it be read now?
        NSArray *mine = @[kMSBDCCMacConnectivityID, kMSBDCCMacDisplayID, kMSBDCCMacSoundID, kMSBDCCMacNowPlayingID], *all = [mine arrayByAddingObjectsFromArray:@[kMSBDCCModuleID, kMSBDCCSSHModuleID]];
        NSDictionary *withBoth = @{ @"iconLists": @[@[Tile(kMSBDCCMacDisplayID, @"smallExtraWide")], @[Tile(kMSBDCCModuleID, @"smallWide"), Tile(kMSBDCCSSHModuleID, @"small")]], @"listUniqueIdentifiers": @[@"A", @"B"] };
        NSDictionary *withNeither = @{ @"iconLists": @[@[Tile(kMSBDCCMacDisplayID, @"smallExtraWide")]], @"listUniqueIdentifiers": @[@"A"] };
        CHECK(MSBDCC18MacLayoutReadable(withBoth, all, YES), "the Mac layout is read with our modules all in the repository");
        CHECK(MSBDCC18MacLayoutReadable(nil, mine, YES), "  ... no file yet: the four are enough (it is made then)");
        CHECK(!MSBDCC18MacLayoutReadable(withNeither, nil, YES), "not without MacCCGrabber (18 would drop the tiles from it, and save that)");
        for (NSString *m in mine) { NSMutableArray *less = [all mutableCopy]; [less removeObject:m]; CHECK(!MSBDCC18MacLayoutReadable(withNeither, less, YES), "not without one of the four (a crash guard's skip list): %s", m.UTF8String); }
        NSMutableArray *noRAM = [all mutableCopy]; [noRAM removeObject:kMSBDCCModuleID];
        CHECK(!MSBDCC18MacLayoutReadable(withBoth, noRAM, YES), "not without RAM & CPU's module while its tile is in the file");
        CHECK(MSBDCC18MacLayoutReadable(withNeither, noRAM, YES), "  ... with no such tile in the file it is read");
        NSMutableArray *noSSH = [all mutableCopy]; [noSSH removeObject:kMSBDCCSSHModuleID];
        CHECK(!MSBDCC18MacLayoutReadable(withBoth, noSSH, YES), "not without SSH's module while OpenSSH is there and its tile is in the file (the skip list)");
        CHECK(MSBDCC18MacLayoutReadable(withBoth, noSSH, NO), "  ... without OpenSSH it is read (no passing state: 18 drops the tile, as in the user's own layout)");
        // May the first one be made now? (code review 1.8.1, 5: the guard's RAM & CPU or SSH off lost that tile from the Mac layout)
        CHECK(MSBDCC18MacLayoutMayBeMade(all, YES), "the first Mac layout is made with our controls all in the repository");
        CHECK(!MSBDCC18MacLayoutMayBeMade(noRAM, YES) && !MSBDCC18MacLayoutMayBeMade(noRAM, NO), "  ... not with RAM & CPU off (the crash guard): 18 would drop its tile from the new file and save that");
        CHECK(!MSBDCC18MacLayoutMayBeMade(noSSH, YES), "  ... not with SSH off while OpenSSH is there");
        CHECK(MSBDCC18MacLayoutMayBeMade(noSSH, NO), "  ... without OpenSSH it is (no passing state: its tile is dropped as in the user's own)");
        CHECK(!MSBDCC18MacLayoutMayBeMade(nil, YES) && !MSBDCC18MacLayoutMayBeMade((NSArray *)@"x", NO), "  ... not without MacCCGrabber's word");
        NSDictionary *userNoRAM = @{ @"iconLists": @[@[Tile(CONN, @"medium")]], @"listUniqueIdentifiers": @[@"A"] };
        NSDictionary *madeNoRAM = MSBDCC18MacLayoutFrom(userNoRAM, 8, ^NSString *{ return U(); });
        CHECK(MSBDCC18MacLayoutReadable(madeNoRAM, noRAM, YES) && !MSBDCC18MacLayoutMayBeMade(noRAM, YES), "  ... also where the user's own has lost the tile for that while: what is made would read clean, and never have it again");
        // The file as it is now (and the same review: a file that reads but does not parse was made again over the user's edits)
        CHECK(MSBDCC18MacFileStep(YES, @{}) == kMSBDCC18MacFileUse && MSBDCC18MacFileStep(YES, withBoth) == kMSBDCC18MacFileUse, "a Mac file that parses: used");
        CHECK(MSBDCC18MacFileStep(YES, nil) == kMSBDCC18MacFileAppleForNow, "  ... there but not read or not parsed: Apple's file for now, nothing made over it");
        CHECK(MSBDCC18MacFileStep(YES, @[]) == kMSBDCC18MacFileAppleForNow && MSBDCC18MacFileStep(YES, @"text") == kMSBDCC18MacFileAppleForNow, "  ... a plist of another kind: the same");
        CHECK(MSBDCC18MacFileStep(NO, nil) == kMSBDCC18MacFileMake, "  ... no file: to be made");
        // "Add a Control"
        NSSet *allSet = [NSSet setWithArray:all], *noneSet = [NSSet setWithObjects:kMSBDCCModuleID, @"x", nil];
        NSSet *twoSet = [NSSet setWithObjects:kMSBDCCModuleID, kMSBDCCSSHModuleID, nil];
        CHECK([MSBDCCWithoutMacTiles(allSet) isEqual:twoSet], "the gallery's list without the Mac tiles: a set stays a set, our other controls stay");
        CHECK(MSBDCCWithoutMacTiles(noneSet) == noneSet, "  ... a set with none of them: the same object");
        NSArray *twoList = @[kMSBDCCModuleID, kMSBDCCSSHModuleID];
        CHECK([MSBDCCWithoutMacTiles(all) isEqual:twoList], "  ... an array stays an array, in its order");
        CHECK(MSBDCCWithoutMacTiles((id)@"text") != nil && MSBDCCWithoutMacTiles(nil) == nil, "  ... anything else as it came");
        NSArray *oneMac = @[kMSBDCCMacDisplayID], *mixed = @[kMSBDCCMacDisplayID, kMSBDCCSSHModuleID], *noModule = @[[NSNull null]], *none = @[];
        CHECK(MSBDCCGallerySectionIsMacTiles(oneMac) && MSBDCCGallerySectionIsMacTiles(mine), "a gallery section of ours alone is shown as one");
        CHECK(!MSBDCCGallerySectionIsMacTiles(mixed) && !MSBDCCGallerySectionIsMacTiles(noModule) && !MSBDCCGallerySectionIsMacTiles(none) && !MSBDCCGallerySectionIsMacTiles(nil), "  ... none with another control, none empty");
        CHECK(MSBDCCMacTileOrder(kMSBDCCMacConnectivityID) == 0 && MSBDCCMacTileOrder(kMSBDCCMacNowPlayingID) == 3 && MSBDCCMacTileOrder(@"x") == NSNotFound, "  ... in the panel's order");
        // The module list
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        for (NSString *b in @[@"MacConnectivity", @"MacDisplay", @"MacSound", @"MacNowPlaying"]) { NSString *d = [root stringByAppendingPathComponent:[kMSBDCCMacTilesDir stringByAppendingPathComponent:[b stringByAppendingString:@".bundle"]]]; [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil]; [@"x" writeToFile:[d stringByAppendingPathComponent:@"Info.plist"] atomically:NO encoding:NSUTF8StringEncoding error:nil]; }
        NSMutableArray *fo = [NSMutableArray array], *id18 = [NSMutableArray array];
        MSBDCCActiveControlsOn(18, root, "/nonexistent", fo, id18);
        CHECK(id18.count == 4 && fo.count == 1 && [fo[0] isEqual:kMSBDCCMacTilesDir], "on 18: the four, from one folder of ours (%lu)", (unsigned long)id18.count);
        NSMutableArray *fo17 = [NSMutableArray array], *id17 = [NSMutableArray array];
        MSBDCCActiveControlsOn(17, root, "/nonexistent", fo17, id17);
        CHECK(id17.count == 0 && fo17.count == 0, "on 15-17: none (the panel draws its own)");
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
        CHECK(MSBDCCIsMacTile(kMSBDCCMacNowPlayingID) && !MSBDCCIsMacTile(kMSBDCCModuleID), "ours are ours");
        CHECK([MSBDCCContainerForModule(kMSBDCCMacSoundID, YES) isEqual:kMSBDCCSettingsAppID], "the gallery lists them under Settings");
        CHECK(MSBDCCMacTileDefaultClass(kMSBDCCMacConnectivityID) == 4 && MSBDCCMacTileDefaultClass(kMSBDCCMacDisplayID) == 3 && kMSBDCCMacSliderSizes == 0xC, "Control Center's classes: 2 x 2 (4), 4 x 1 (3) and 2 x 1 (2)");
    }
    printf("%d checks, %d failed\n", passes + fails, fails);
    return fails ? 1 : 0;
}
