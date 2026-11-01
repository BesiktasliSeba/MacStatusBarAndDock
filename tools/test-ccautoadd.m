// Mac test of common/CCAutoAdd.h (run by test-ccautoadd.sh): RAM & CPU put in Control Center by itself, once per iPad, where there is room.
#import <Foundation/Foundation.h>
#include "../common/CCAutoAdd.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSDictionary *Tile(NSString *uid, NSString *mid, NSString *size) {   // (a tile as 18.5 saves it, ControlsIconState.plist)
    return @{@"allowsExternalSuggestions": @YES, @"allowsSuggestions": @YES, @"displayIdentifier": uid, @"gridSize": size, @"iconType": @"custom",
             @"elements": @[@{@"containerBundleIdentifier": @"com.apple.springboard", @"dataSourceUniqueIdentifier": [uid stringByAppendingString:@"-E"], @"elementType": @"module", @"moduleIdentifier": mid}]};
}

int main(void) {
    @autoreleasepool {
        // ---- once only: the marker ----
        CHECK(MSBDCCAutoAddDue(nil, nil, @"1.7.7"), "a new install (no marker): due");
        CHECK(!MSBDCCAutoAddDue(@"added", nil, @"1.7.7"), "added before: never again");
        CHECK(!MSBDCCAutoAddDue(@"there", nil, @"1.7.8"), "it was there: never, not after an update either");
        CHECK(!MSBDCCAutoAddDue(@"removed", nil, @"1.7.8") && !MSBDCCAutoAddDue(@"memory-magic", nil, @"1.7.8"), "removed before, or Memory Magic's tile: never");
        CHECK(!MSBDCCAutoAddDue(@1, nil, @"1.7.7") && !MSBDCCAutoAddDue(@"", nil, @"1.7.7"), "any marker at all: done (not looked at again)");
        CHECK(!MSBDCCAutoAddDue(nil, @"1.7.7", @"1.7.7"), "no room for this version: not looked at again in it");
        CHECK(MSBDCCAutoAddDue(nil, @"1.7.7", @"1.7.8"), "no room for 1.7.7: looked at again after the update");
        CHECK(MSBDCCAutoAddDue(nil, @"1.7.7", nil) && MSBDCCAutoAddDue(nil, @7, @"1.7.7"), "an unread version or a damaged record: due (the look itself waits for the version)");

        // ---- what the user's lists say: KT's own lists (1 Nov 2026) ----
        NSArray *ipad2 = @[@"com.apple.control-center.ConnectivityModule", @"com.apple.mediaremote.controlcenter.nowplaying", @"com.apple.control-center.OrientationLockModule",
            @"com.apple.mediaremote.controlcenter.airplaymirroring", @"com.apple.control-center.DisplayModule", @"com.apple.mediaremote.controlcenter.audio", @"com.mtac.uptimemodule",
            @"com.apple.control-center.MuteModule", @"com.0xkuj.ccadsbegone", @"com.apple.control-center.CameraModule", @"com.apple.replaykit.controlcenter.screencapture",
            @"com.apple.control-center.LowPowerModule", @"com.apple.springboard.ContinuousExposeModule", kMSBDMemoryMagicID, @"com.uzra.aerial.togglecc"];
        NSArray *ipad2Off = @[@"com.apple.BarcodeSupport.NFCControlCenterModule", @"com.apple.control-center.FlashlightModule", @"com.apple.control-center.QuickNoteModule",
            @"com.apple.donotdisturb.DoNotDisturbModule", @"com.apple.FocusUIModule", @"com.apple.shazamkit.controlcenter.ShazamModule", @"com.apple.springboard.SensitiveUIModule"];
        CHECK(MSBDCCAutoAddListState(ipad2, ipad2Off, YES) == kMSBDCCListMemoryMagic, "iPad 2 (16.7.7): Memory Magic's tile with ours drawn over it: the user has it");
        CHECK(MSBDCCAutoAddListState(ipad2, ipad2Off, NO) == kMSBDCCListAbsent, "  ... Memory Magic not loading, or our tile not drawn over it: absent");
        NSArray *ipad17 = @[@"com.apple.control-center.ConnectivityModule", @"com.apple.mediaremote.controlcenter.nowplaying", @"com.apple.control-center.MuteModule",
            @"com.apple.control-center.FlashlightModule", @"com.apple.control-center.QuickNoteModule", kMSBDCCModuleID, @"com.apple.control-center.CameraModule"];
        CHECK(MSBDCCAutoAddListState(ipad17, @[@"com.apple.FocusUIModule"], YES) == kMSBDCCListThere, "17.5: RAM & CPU in the list: there");
        NSArray *m1 = @[@"com.apple.control-center.ConnectivityModule", @"com.apple.control-center.LowPowerModule", kMSBDCCModuleID, @"com.uzra.aerial.togglecc"];
        CHECK(MSBDCCAutoAddListState(m1, @[kMSBDMemoryMagicID, @"com.yan.ringmodule"], YES) == kMSBDCCListThere, "M1 (15.6.1): ours in Memory Magic's old place, Memory Magic disabled: there");
        CHECK(MSBDCCAutoAddListState(ipad2, [ipad2Off arrayByAddingObject:kMSBDCCModuleID], YES) == kMSBDCCListRemoved, "taken out in Settings before (disabled): removed, before Memory Magic counts");
        CHECK(MSBDCCAutoAddListState(@[@"com.apple.control-center.MuteModule"], @[], YES) == kMSBDCCListAbsent, "Apple's own list: absent");
        CHECK(MSBDCCAutoAddListState(nil, nil, YES) == kMSBDCCListAbsent && MSBDCCAutoAddListState((NSArray *)@{}, (NSArray *)@"x", YES) == kMSBDCCListAbsent, "no lists, or not lists: absent");
        CHECK([MSBDCCAutoAddDoneReason(kMSBDCCListThere) isEqualToString:@"there"] && [MSBDCCAutoAddDoneReason(kMSBDCCListRemoved) isEqualToString:@"removed"]
              && [MSBDCCAutoAddDoneReason(kMSBDCCListMemoryMagic) isEqualToString:@"memory-magic"] && !MSBDCCAutoAddDoneReason(kMSBDCCListAbsent), "the marker says why");

        // ---- the add: where Settings' + puts a control ----
        NSArray *withOurs = MSBDCCAutoAddList(ipad2);
        CHECK(withOurs.count == ipad2.count + 1 && [withOurs.lastObject isEqual:kMSBDCCModuleID] && [[withOurs subarrayWithRange:NSMakeRange(0, ipad2.count)] isEqualToArray:ipad2],
              "at the end of the list, every other control in its order (the SSH control among them, untouched)");
        CHECK(MSBDCCAutoAddList(ipad17) == nil && MSBDCCAutoAddList(nil) == nil && MSBDCCAutoAddList((NSArray *)@{}) == nil, "there already, no list, or not a list: nothing");
        CHECK([MSBDCCAutoAddList(@[]) isEqualToArray:@[kMSBDCCModuleID]], "an empty list: ours alone");

        // ---- 18: the layout has a tile of ours ----
        NSDictionary *a12z = @{@"displayName": @"Control Center Root", @"uniqueIdentifier": @"control-center-root", @"buttonBar": @[],
            @"iconLists": @[@[Tile(@"A", @"com.apple.control-center.ConnectivityModule", @"medium"), Tile(@"B", @"com.apple.control-center.LowPowerModule", @"small"),
                              Tile(@"C", kMSBDCCModuleID, @"smallWide"), Tile(@"D", kMSBDCCSSHModuleID, @"small")], @[Tile(@"E", @"com.apple.mediaremote.controlcenter.nowplaying", @"largeExtraTall")]],
            @"listUniqueIdentifiers": @[@"P1", @"P2"]};
        CHECK(MSBDCCAutoAddLayoutHasOurs(a12z, 0), "A12Z (18.5): RAM & CPU on page 1: there");
        NSDictionary *noOurs = @{@"iconLists": @[@[Tile(@"A", @"com.apple.control-center.ConnectivityModule", @"medium"), Tile(@"D", kMSBDCCSSHModuleID, @"small")]]};
        CHECK(!MSBDCCAutoAddLayoutHasOurs(noOurs, 0), "only the SSH control: not ours");
        CHECK(MSBDCCAutoAddLayoutHasOurs(@{@"iconLists": @[@[]], @"ignored": @[Tile(@"Z", kMSBDCCModuleID, @"smallWide")]}, 0), "kept in another list of the layout: there");
        CHECK(!MSBDCCAutoAddLayoutHasOurs(nil, 0) && !MSBDCCAutoAddLayoutHasOurs(@"x", 0) && !MSBDCCAutoAddLayoutHasOurs(@{}, 0), "no layout: not there");

        // ---- the package's removal: the marker goes where the removal takes RAM & CPU out of Control Center (1.7.7, the 17.5's reinstall) ----
        // (KT's 17.5, 1 Nov: CCSupport's file with ours at 10 of 15, Apple's own file without it)
        NSDictionary *cc17 = @{@"disabled-module-identifiers": @[@"com.apple.FocusUIModule"], @"module-identifiers": [ipad17 arrayByAddingObject:@"com.apple.springboard.SensitiveUIModule"],
                               @"userenabled-fixed-module-identifiers": @[], @"version": @2};
        NSDictionary *apple17 = @{@"disabled-module-identifiers": @[], @"module-identifiers": @[@"com.apple.control-center.MuteModule", @"com.apple.control-center.CameraModule"],
                                  @"userenabled-fixed-module-identifiers": @[@"com.apple.Home.ControlCenter"], @"version": @2};
        CHECK(MSBDCCAutoAddForgetOnRemoval(@"there", @[apple17, cc17], nil), "17.5: \"there\", ours in CCSupport's list: the marker goes (the reinstall puts it back)");
        CHECK(MSBDCCAutoAddForgetOnRemoval(@"added", @[cc17], nil), "\"added\", ours in the list: the marker goes");
        CHECK(!MSBDCCAutoAddForgetOnRemoval(@"removed", @[cc17], nil) && !MSBDCCAutoAddForgetOnRemoval(@"memory-magic", @[cc17], nil), "\"removed\" and \"memory-magic\" always stay");
        CHECK(!MSBDCCAutoAddForgetOnRemoval(nil, @[cc17], nil) && !MSBDCCAutoAddForgetOnRemoval(@1, @[cc17], a12z), "no marker, or a damaged one: nothing to forget");
        NSDictionary *userOut = @{@"disabled-module-identifiers": @[@"com.apple.FocusUIModule", kMSBDCCModuleID], @"module-identifiers": ipad17};
        CHECK(!MSBDCCAutoAddForgetOnRemoval(@"there", @[userOut], nil), "\"there\" but the user took it out since (a disabled control): kept, never back");
        CHECK(!MSBDCCAutoAddForgetOnRemoval(@"there", @[cc17, @{@"disabled-module-identifiers": @[kMSBDCCModuleID]}], nil), "  ... disabled in the other file: kept (the user's removal wins)");
        CHECK(!MSBDCCAutoAddForgetOnRemoval(@"there", @[apple17], nil), "\"there\", ours in no list: kept (the removal takes nothing out)");
        CHECK(MSBDCCAutoAddForgetOnRemoval(@"there", @[@{@"userenabled-fixed-module-identifiers": @[kMSBDCCModuleID]}], nil), "ours among the enabled fixed controls: goes");
        CHECK(MSBDCCAutoAddForgetOnRemoval(@"there", @[], a12z) && !MSBDCCAutoAddForgetOnRemoval(@"there", @[], noOurs), "18: a tile of ours in the layout: goes; none: kept");
        CHECK(!MSBDCCAutoAddForgetOnRemoval(@"there", nil, nil) && !MSBDCCAutoAddForgetOnRemoval(@"there", (NSArray *)@"x", @[]) && !MSBDCCAutoAddForgetOnRemoval(@"there", @[@"x", @3], nil),
              "no lists, or lists that are not dictionaries: kept");

        // ---- room: Apple's Control Center (15-17) ----
        NSString *why = nil;
        MSBDCCAppleGrid g = { YES, 6, 6, 600.0, 84.0, 52.0, {1366.0, 1024.0} };
        CHECK(MSBDCCAppleGridRoom(g, &why) && [why hasPrefix:@"a free place"], "a free 2 x 1 place in the rows there, fits both ways: room (%s)", why.UTF8String);
        g.rowsWith = 7;
        CHECK(MSBDCCAppleGridRoom(g, &why) && [why hasPrefix:@"one more row"], "one more row, still on the screen in landscape: room (%s)", why.UTF8String);
        MSBDCCAppleGrid small = { YES, 7, 8, 640.0, 84.0, 52.0, {1024.0, 768.0} };
        CHECK(!MSBDCCAppleGridRoom(small, &why) && [why containsString:@"scroll"], "9.7-inch: one more row would go past the landscape height: no room (%s)", why.UTF8String);
        small.rowsWith = 7;
        CHECK(MSBDCCAppleGridRoom(small, &why), "  ... the same grid with a free place in its rows: room");
        MSBDCCAppleGrid scrolls = { YES, 9, 9, 800.0, 84.0, 52.0, {1024.0, 768.0} };
        CHECK(!MSBDCCAppleGridRoom(scrolls, &why), "it scrolls in landscape already: no room, not even in a free place");
        MSBDCCAppleGrid moved = g; moved.othersStay = NO;
        CHECK(!MSBDCCAppleGridRoom(moved, &why) && [why containsString:@"move"], "ours would move another control: no room");
        MSBDCCAppleGrid twoRows = g; twoRows.rowsWith = 8;
        CHECK(!MSBDCCAppleGridRoom(twoRows, &why), "two more rows: no room");
        MSBDCCAppleGrid edge = { YES, 6, 7, 1024.0 - 84.0 - 52.0, 84.0, 52.0, {1366.0, 1024.0} };
        CHECK(MSBDCCAppleGridRoom(edge, &why), "exactly the landscape height: room");
        edge.contentNow += 0.6;
        CHECK(!MSBDCCAppleGridRoom(edge, &why), "  ... 0.6 pt more: no room");
        MSBDCCAppleGrid bad1 = g; bad1.rowPitch = 0; MSBDCCAppleGrid bad2 = g; bad2.heights[1] = 0; MSBDCCAppleGrid bad3 = g; bad3.rowsNow = 0; MSBDCCAppleGrid bad4 = g; bad4.rowsWith = 5;
        MSBDCCAppleGrid bad5 = g; bad5.contentNow = NAN;
        CHECK(!MSBDCCAppleGridRoom(bad1, &why) && !MSBDCCAppleGridRoom(bad2, &why) && !MSBDCCAppleGridRoom(bad3, &why) && !MSBDCCAppleGridRoom(bad4, &why) && !MSBDCCAppleGridRoom(bad5, &why)
              && [why containsString:@"not told"], "measures that do not add up: not told, no room");

        // ---- room: BigSurCenter (15/16) ----
        MSBDCCBSCGrid b = { 9, 4, 835.0, 85.0, 888.0 };
        CHECK(MSBDCCBSCGridRoom(b, &why) && [why hasPrefix:@"the last row's free place"], "9 tiles, 4 to a row: the last row's free place (%s)", why.UTF8String);
        b.tiles = 12;
        CHECK(!MSBDCCBSCGridRoom(b, &why) && [why containsString:@"scroll"], "12 tiles, the last row full, one more row past the limit: no room (%s)", why.UTF8String);
        b.needNow = 700.0;
        CHECK(MSBDCCBSCGridRoom(b, &why) && [why hasPrefix:@"one more row"], "  ... with the panel short of its limit by more than a row: room");
        MSBDCCBSCGrid over = { 13, 4, 960.0, 85.0, 888.0 };
        CHECK(!MSBDCCBSCGridRoom(over, &why) && [why containsString:@"scrolls already"], "the panel scrolls already: no room, not even in the last row's free place");
        MSBDCCBSCGrid exact = { 8, 4, 803.0, 85.0, 888.0 };
        CHECK(MSBDCCBSCGridRoom(exact, &why), "one more row to exactly the limit: room");
        MSBDCCBSCGrid b0 = b; b0.columns = 0; MSBDCCBSCGrid b1 = b; b1.tiles = 0; MSBDCCBSCGrid b2 = b; b2.cap = 0; MSBDCCBSCGrid b3 = b; b3.rowPitch = NAN;
        CHECK(!MSBDCCBSCGridRoom(b0, &why) && !MSBDCCBSCGridRoom(b1, &why) && !MSBDCCBSCGridRoom(b2, &why) && !MSBDCCBSCGridRoom(b3, &why) && [why containsString:@"not told"],
              "BigSurCenter's measures that do not add up: not told, no room");

        printf("test-ccautoadd: %d passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
