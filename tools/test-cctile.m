// Mac test of common/CCTileKeep.h (run by test-cctile.sh): RAM & CPU's tile noted in an iPadOS 18 Control Center layout and put back after a
// SpringBoard without our module dropped it. The layout below has the shape of the A12Z's (18.5, 29 Oct: three pages, the tiles with their grid
// sizes, each page's rotated order), with identifiers of its own. "start <state> <note> [then]" runs one SpringBoard start of the keeper on those
// files (the script runs one process per start); "then" is what happens while it runs: "remove" (the user takes the tile out: the layout saved
// without it, as a new file), "inplace" (saved over the old file), "twice" (taken out as a new file, then back over that new file), "other"
// (another file of that folder written), "resave" (the layout saved again as it is), "quick" (taken out, SpringBoard gone 0.1 s later), "move"
// (the tile moved to page 3).
#import <Foundation/Foundation.h>
#include "../common/CCTileKeep.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
#define OURS @"com.besiktasliseba.macstatusbaranddock.ramcpu"

static NSDictionary *Tile(NSString *tid, NSString *module, NSString *grid) {
    return @{@"allowsExternalSuggestions": @YES, @"allowsSuggestions": @YES, @"displayIdentifier": tid, @"gridSize": grid, @"iconType": @"custom",
             @"elements": @[@{@"containerBundleIdentifier": @"com.apple.springboard", @"dataSourceUniqueIdentifier": [tid stringByAppendingString:@"-DS"],
                              @"elementType": @"module", @"moduleIdentifier": module}]};
}
// Page 1: 15 tiles, ours (R) after Low Power (L), last; its rotated order puts R between L and Focus (F). Pages 2 and 3: one big tile each.
static NSDictionary *Layout(void) {
    NSArray *p1 = @[Tile(@"C", @"com.apple.control-center.ConnectivityModule", @"medium"), Tile(@"N", @"com.apple.mediaremote.controlcenter.nowplaying", @"medium"),
        Tile(@"O", @"com.apple.control-center.OrientationLockModule", @"small"), Tile(@"A", @"com.apple.mediaremote.controlcenter.airplaymirroring", @"small"),
        Tile(@"D", @"com.apple.control-center.DisplayModule", @"smallTall"), Tile(@"U", @"com.apple.mediaremote.controlcenter.audio", @"smallTall"),
        Tile(@"F", @"com.apple.FocusUIModule", @"smallWide"), Tile(@"M", @"com.apple.control-center.MuteModule", @"small"),
        Tile(@"S", @"com.apple.springboard.ContinuousExposeModule", @"small"), Tile(@"Q", @"com.apple.mobilenotes.control", @"small"),
        Tile(@"K", @"com.apple.control-center.CameraModule", @"small"), Tile(@"X", @"com.apple.control-center.CalculatorModule", @"small"),
        Tile(@"T", @"com.apple.mobiletimer.control", @"small"), Tile(@"L", @"com.apple.control-center.LowPowerModule", @"small"), Tile(@"R", OURS, @"smallWide")];
    NSArray *p2 = @[Tile(@"N2", @"com.apple.mediaremote.controlcenter.nowplaying", @"largeExtraTall")];
    NSArray *p3 = @[Tile(@"C2", @"com.apple.control-center.ConnectivityModule", @"largeExtraTall")];
    return @{@"buttonBar": @[], @"displayName": @"Control Center Root", @"iconLists": @[p1, p2, p3],
             @"listMetadata": @{@"P1": @{@"rotatedOrder": @[@"C", @"N", @"M", @"S", @"Q", @"K", @"X", @"T", @"O", @"A", @"D", @"U", @"L", @"R", @"F"]},
                                @"P3": @{@"rotatedOrder": @[@"C2"]}, @"P2": @{@"rotatedOrder": @[@"N2"]}},
             @"listUniqueIdentifiers": @[@"P1", @"P2", @"P3"], @"uniqueIdentifier": @"control-center-root", @"widgetVersion": @1000};
}
// What 18 does in a SpringBoard without our module: every tile of ours goes, from its page and from the page's rotated order.
static NSDictionary *Pruned(NSDictionary *state, BOOL rotatedToo) {
    NSMutableDictionary *m = [state mutableCopy];
    NSMutableArray *pages = [NSMutableArray array]; NSMutableSet *gone = [NSMutableSet set];
    for (NSArray *page in state[@"iconLists"]) {
        NSMutableArray *np = [NSMutableArray array];
        for (NSDictionary *icon in page) { if (MSBDCCTileIsOurs(icon, OURS)) [gone addObject:icon[@"displayIdentifier"]]; else [np addObject:icon]; }
        [pages addObject:np];
    }
    m[@"iconLists"] = pages;
    if (rotatedToo) {
        NSMutableDictionary *meta = [state[@"listMetadata"] mutableCopy];
        for (NSString *k in [meta allKeys]) {
            NSMutableArray *order = [meta[k][@"rotatedOrder"] mutableCopy]; [order removeObjectsInArray:gone.allObjects];
            meta[k] = @{@"rotatedOrder": order};
        }
        m[@"listMetadata"] = meta;
    }
    return m;
}
static NSArray *IDs(NSDictionary *state, NSUInteger page) { return MSBDCCTileIDsOf(state[@"iconLists"][page]); }
static NSDictionary *WithPage(NSDictionary *state, NSUInteger page, NSArray *tiles) {
    NSMutableDictionary *m = [state mutableCopy]; NSMutableArray *pages = [state[@"iconLists"] mutableCopy];
    pages[page] = tiles; m[@"iconLists"] = pages; return m;
}
static NSArray *Without(NSArray *page, NSString *tid) {
    NSMutableArray *a = [NSMutableArray array]; for (NSDictionary *i in page) if (![i[@"displayIdentifier"] isEqual:tid]) [a addObject:i]; return a;
}
static BOOL Write(NSDictionary *d, NSString *path, BOOL inPlace) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:d format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!inPlace) return [data writeToFile:path options:NSDataWritingAtomic error:NULL];
    FILE *f = fopen(path.fileSystemRepresentation, "r+"); if (!f) return NO;   // (the same file, rewritten: as a store that does not replace it)
    BOOL ok = fwrite(data.bytes, 1, data.length, f) == data.length && ftruncate(fileno(f), (off_t)data.length) == 0;
    fclose(f); return ok;
}

static int Start(NSString *statePath, NSString *notePath, NSString *then) {
    MSBDCCTileKeepStart(statePath, notePath, OURS, ^(NSString *line) { printf("  [cctile] %s\n", line.UTF8String); fflush(stdout); });
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
    if (then.length) {
        NSDictionary *now = MSBDCCTileRead(statePath, NULL, NULL);
        if ([then isEqualToString:@"remove"]) Write(Pruned(now, YES), statePath, NO);
        else if ([then isEqualToString:@"inplace"]) Write(Pruned(now, YES), statePath, YES);
        else if ([then isEqualToString:@"twice"]) {   // (taken out, saved as a new file; then back, saved over that new file: the watch follows the file)
            Write(Pruned(now, YES), statePath, NO);
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
            Write(now, statePath, YES);
        }
        else if ([then isEqualToString:@"other"]) {   // (another file of that folder written: not a save of the layout)
            [@{@"x": @1} writeToFile:[statePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Other.plist"] atomically:YES];
        }
        else if ([then isEqualToString:@"resave"]) Write(now, statePath, NO);   // (the layout saved again as it is)
        else if ([then isEqualToString:@"quick"]) {   // (taken out, and SpringBoard ends a tenth of a second after the save)
            Write(Pruned(now, YES), statePath, NO);
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            return 0;
        }
        else if ([then isEqualToString:@"move"]) {
            NSDictionary *ours = nil; for (NSDictionary *i in now[@"iconLists"][0]) if (MSBDCCTileIsOurs(i, OURS)) ours = i;
            NSDictionary *moved = WithPage(Pruned(now, YES), 2, [@[ours] arrayByAddingObjectsFromArray:now[@"iconLists"][2]]);
            Write(moved, statePath, NO);
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];   // (the note comes half a second after the save)
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc >= 4 && !strcmp(argv[1], "start")) return Start(@(argv[2]), @(argv[3]), argc > 4 ? @(argv[4]) : nil);
        if (argc >= 3 && !strcmp(argv[1], "layout")) {   // (the script's files: the layout, or as a SpringBoard without our module leaves it)
            NSDictionary *l = Layout(); if (argc > 3 && !strcmp(argv[3], "pruned")) l = Pruned(l, YES);
            if (argc > 3 && !strcmp(argv[3], "added")) l = WithPage(Pruned(l, YES), 0, [Pruned(l, YES)[@"iconLists"][0] arrayByAddingObject:Tile(@"Z", @"com.apple.control-center.FlashlightModule", @"small")]);
            return MSBDCCTileWrite(l, @(argv[2]), NSPropertyListBinaryFormat_v1_0) ? 0 : 1;
        }
        NSDictionary *full = Layout(), *pruned = Pruned(full, YES);
        NSString *why = nil;
        // the note
        NSDictionary *note = MSBDCCTileNote(full, OURS);
        NSDictionary *t = [note[@"tiles"] firstObject];
        CHECK([note[@"placed"] boolValue] && [note[@"tiles"] count] == 1, "note: placed, one tile");
        CHECK([t[@"list"] isEqual:@"P1"] && [t[@"page"] isEqual:@0] && [t[@"index"] isEqual:@14] && [t[@"after"] isEqual:@"L"] && !t[@"before"], "note: page P1 (1), the 15th, after Low Power, last");
        CHECK([t[@"icon"] isEqual:full[@"iconLists"][0][14]], "note: the tile itself, as the layout has it (grid size, data source)");
        CHECK([t[@"others"] count] == 14 && ![t[@"others"] containsObject:@"R"], "note: the page's 14 other tiles");
        CHECK([t[@"rotated"][@"index"] isEqual:@13] && [t[@"rotated"][@"after"] isEqual:@"L"] && [t[@"rotated"][@"before"] isEqual:@"F"], "note: its place in the rotated order (between Low Power and Focus)");
        NSDictionary *none = MSBDCCTileNote(pruned, OURS);
        CHECK(none && ![none[@"placed"] boolValue] && [none[@"tiles"] count] == 0, "note of a layout without it: not placed");
        CHECK(MSBDCCTileNote(nil, OURS) == nil && MSBDCCTileNote((NSDictionary *)@[], OURS) == nil && MSBDCCTileNote(@{@"iconLists": @"x"}, OURS) == nil
              && MSBDCCTileNote(@{@"iconLists": @[@"x"]}, OURS) == nil, "note: no layout, not a dictionary, pages not lists: none (the old note stays)");
        // put back after 18 dropped it
        NSDictionary *back = MSBDCCTilePutBack(pruned, note, OURS, &why);
        CHECK([back isEqual:full], "dropped and put back: the layout exactly as before (%s)", why.UTF8String);
        CHECK([why hasPrefix:@"1 tile(s) put back (page 1 at 15)"], "  ... said so (%s)", why.UTF8String);
        NSDictionary *keptRot = Pruned(full, NO);
        CHECK([MSBDCCTilePutBack(keptRot, note, OURS, &why) isEqual:full], "dropped from the page only (the rotated order kept it): not twice in that order");
        CHECK(MSBDCCTilePutBack(full, note, OURS, &why) == nil && [why isEqualToString:@"the tile is there"], "the tile there: nothing done");
        CHECK(MSBDCCTilePutBack(pruned, none, OURS, &why) == nil && [why hasPrefix:@"not noted as placed"], "noted as not placed (taken out while our module was there): not put back");
        CHECK(MSBDCCTilePutBack(pruned, nil, OURS, &why) == nil && MSBDCCTilePutBack(pruned, (NSDictionary *)@"x", OURS, &why) == nil
              && MSBDCCTilePutBack(pruned, @{@"placed": @"yes", @"tiles": note[@"tiles"]}, OURS, &why) == nil, "no note, or not one: nothing done");
        // the page since
        NSArray *p1 = pruned[@"iconLists"][0];
        NSDictionary *added = WithPage(pruned, 0, [p1 arrayByAddingObject:Tile(@"Z", @"com.apple.control-center.FlashlightModule", @"small")]);
        CHECK(MSBDCCTilePutBack(added, note, OURS, &why) == nil && [why containsString:@"its page has a tile it did not have then"], "a tile added to its page meanwhile: not put back (no room, maybe)");
        NSDictionary *fewer = WithPage(pruned, 0, Without(p1, @"M"));
        NSDictionary *b2 = MSBDCCTilePutBack(fewer, note, OURS, &why);
        CHECK([[IDs(b2, 0) lastObject] isEqual:@"R"] && [IDs(b2, 0) count] == 14, "a tile taken out of its page meanwhile: put back after Low Power");
        NSMutableArray *moved = [Without(p1, @"L") mutableCopy]; [moved insertObject:p1[13] atIndex:2];   // (Low Power moved to the 3rd place)
        NSDictionary *b3 = MSBDCCTilePutBack(WithPage(pruned, 0, moved), note, OURS, &why);
        CHECK([IDs(b3, 0)[2] isEqual:@"L"] && [IDs(b3, 0)[3] isEqual:@"R"], "the tile before it moved: put back right after it again");
        NSDictionary *noAnchor = WithPage(pruned, 0, Without(p1, @"L"));
        NSDictionary *b4 = MSBDCCTilePutBack(noAnchor, note, OURS, &why);
        CHECK([[IDs(b4, 0) lastObject] isEqual:@"R"] && [b4[@"listMetadata"][@"P1"][@"rotatedOrder"] indexOfObject:@"R"] == 13, "the tile before it gone too: at its old place (the end), the rotated order by its neighbours");
        // a tile in the middle of a page, then the one before it gone: before the one that was after it
        NSDictionary *mid = WithPage(full, 0, ({ NSMutableArray *a = [Without(full[@"iconLists"][0], @"R") mutableCopy]; [a insertObject:full[@"iconLists"][0][14] atIndex:5]; a; }));
        NSDictionary *midNote = MSBDCCTileNote(mid, OURS);
        CHECK([[midNote[@"tiles"] firstObject][@"after"] isEqual:@"D"] && [[midNote[@"tiles"] firstObject][@"before"] isEqual:@"U"], "a tile in the middle: noted between its neighbours");
        NSDictionary *b5 = MSBDCCTilePutBack(WithPage(Pruned(mid, YES), 0, Without(Pruned(mid, YES)[@"iconLists"][0], @"D")), midNote, OURS, &why);
        CHECK([IDs(b5, 0)[4] isEqual:@"R"] && [IDs(b5, 0)[5] isEqual:@"U"], "  ... the one before it gone: put back before the one after it");
        // page gone, identifier in use, two tiles
        NSDictionary *pageGone = @{@"iconLists": @[pruned[@"iconLists"][1], pruned[@"iconLists"][2]], @"listUniqueIdentifiers": @[@"P2", @"P3"], @"listMetadata": pruned[@"listMetadata"]};
        CHECK(MSBDCCTilePutBack(pageGone, note, OURS, &why) == nil && [why containsString:@"its page is gone"], "its page gone: not put back");
        NSMutableArray *taken = [p1 mutableCopy]; [taken addObject:Tile(@"R", @"com.apple.control-center.FlashlightModule", @"small")];
        CHECK(MSBDCCTilePutBack(WithPage(pruned, 0, taken), note, OURS, &why) == nil, "its identifier taken by another tile: not put back");
        // a layout that keeps the tile in another list (as SpringBoardHome's Home Screen state keeps "ignored" icons): never a second copy
        NSMutableDictionary *parked = [pruned mutableCopy]; parked[@"ignored"] = @[full[@"iconLists"][0][14]];
        CHECK(MSBDCCTilePutBack(parked, note, OURS, &why) == nil && [why isEqualToString:@"the layout keeps our module elsewhere (/ignored/0/elements/0): not put back"], "our module kept in another list: not put back, and where it is said (%s)", why.UTF8String);
        NSMutableDictionary *idElsewhere = [pruned mutableCopy]; idElsewhere[@"ignored"] = @[Tile(@"R", @"com.apple.control-center.FlashlightModule", @"small")];
        CHECK(MSBDCCTilePutBack(idElsewhere, note, OURS, &why) == nil && [why containsString:@"its identifier is in use"], "its identifier used by a tile in another list: not put back");
        CHECK([MSBDCCTilePutBack(pruned, note, OURS, &why) isEqual:full], "  ... and a rotated order that still names it is no tile: put back");
        NSDictionary *two = WithPage(WithPage(full, 2, [@[Tile(@"R2", OURS, @"smallWide")] arrayByAddingObjectsFromArray:full[@"iconLists"][2]]), 0, [full[@"iconLists"][0] arrayByAddingObject:Tile(@"R3", OURS, @"smallWide")]);
        NSMutableDictionary *twoMeta = [two mutableCopy]; twoMeta[@"listMetadata"] = @{@"P1": @{@"rotatedOrder": [full[@"listMetadata"][@"P1"][@"rotatedOrder"] arrayByAddingObject:@"R3"]}, @"P2": @{@"rotatedOrder": @[@"N2"]}, @"P3": @{@"rotatedOrder": @[@"R2", @"C2"]}};
        NSDictionary *twoNote = MSBDCCTileNote(twoMeta, OURS);
        CHECK([twoNote[@"tiles"] count] == 3 && [[twoNote[@"tiles"][1] objectForKey:@"after"] isEqual:@"R"], "three of ours (two side by side, one on page 3): all noted, in order");
        CHECK([MSBDCCTilePutBack(Pruned(twoMeta, YES), twoNote, OURS, &why) isEqual:twoMeta], "  ... all put back, the layout as before (%s)", why.UTF8String);
        // a page that held only our tile, and 18 took the emptied page away too (as the Home Screen drops an empty page): the page comes back at its
        // old place with its old identifier and rotated order -- the layout exactly as before; with two of ours alone on it, both
        NSArray *bare = [full[@"iconLists"][0] subarrayWithRange:NSMakeRange(0, 14)];
        NSDictionary *alone = @{@"iconLists": @[bare, @[Tile(@"R", OURS, @"smallWide")], full[@"iconLists"][1], full[@"iconLists"][2]],
                                @"listUniqueIdentifiers": @[@"P1", @"PR", @"P2", @"P3"],
                                @"listMetadata": @{@"P1": @{@"rotatedOrder": [full[@"listMetadata"][@"P1"][@"rotatedOrder"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != 'R'"]]},
                                                   @"PR": @{@"rotatedOrder": @[@"R"]}, @"P2": @{@"rotatedOrder": @[@"N2"]}, @"P3": @{@"rotatedOrder": @[@"C2"]}},
                                @"uniqueIdentifier": @"control-center-root"};
        NSDictionary *aloneNote = MSBDCCTileNote(alone, OURS);
        NSDictionary *noPage = @{@"iconLists": @[bare, full[@"iconLists"][1], full[@"iconLists"][2]], @"listUniqueIdentifiers": @[@"P1", @"P2", @"P3"],
                                 @"listMetadata": @{@"P1": alone[@"listMetadata"][@"P1"], @"P2": @{@"rotatedOrder": @[@"N2"]}, @"P3": @{@"rotatedOrder": @[@"C2"]}},
                                 @"uniqueIdentifier": @"control-center-root"};
        CHECK([MSBDCCTilePutBack(noPage, aloneNote, OURS, &why) isEqual:alone] && [why containsString:@"the page back too"], "alone on its page, the page gone too: page and tile back as before (%s)", why.UTF8String);
        NSDictionary *aloneTwo = WithPage(alone, 1, @[Tile(@"R", OURS, @"smallWide"), Tile(@"R4", OURS, @"smallWide")]);
        NSMutableDictionary *aloneTwoM = [aloneTwo mutableCopy]; aloneTwoM[@"listMetadata"] = ({ NSMutableDictionary *mm = [alone[@"listMetadata"] mutableCopy]; mm[@"PR"] = @{@"rotatedOrder": @[@"R", @"R4"]}; mm; });
        CHECK([MSBDCCTilePutBack(noPage, MSBDCCTileNote(aloneTwoM, OURS), OURS, &why) isEqual:aloneTwoM], "  ... two of ours alone on it: both back, in order, one page");
        NSMutableDictionary *noPageMoved = [noPage mutableCopy]; noPageMoved[@"listUniqueIdentifiers"] = @[@"P1", @"PX", @"P3"];
        CHECK(MSBDCCTilePutBack(noPageMoved, aloneNote, OURS, &why) != nil && [MSBDCCTileListIDs(MSBDCCTilePutBack(noPageMoved, aloneNote, OURS, &why), 4) isEqualToArray:(@[@"P1", @"PR", @"PX", @"P3"])], "  ... the pages around it changed meanwhile: it comes back at its old number, with its own identifier");
        // a layout without page identifiers: by page number
        NSMutableDictionary *noIDs = [full mutableCopy]; [noIDs removeObjectForKey:@"listUniqueIdentifiers"];
        NSDictionary *noIDsNote = MSBDCCTilePutBack(Pruned(noIDs, YES), MSBDCCTileNote(noIDs, OURS), OURS, &why);
        CHECK([[IDs(noIDsNote, 0) lastObject] isEqual:@"R"], "no page identifiers: by its page number");
        // junk never throws
        BOOL threw = NO;
        @try {
            NSArray *junk = @[@{@"iconLists": @[@[@"x", @5, @{@"elements": @"y"}, @{@"displayIdentifier": @7, @"elements": @[@"z", @{@"moduleIdentifier": OURS}]}]]},
                              @{@"iconLists": @[@[]], @"listUniqueIdentifiers": @[@5]}, @{@"iconLists": @[@[]], @"listMetadata": @{@"P1": @"x"}, @"listUniqueIdentifiers": @[@"P1"]}];
            NSArray *junkNotes = @[@{@"placed": @YES, @"tiles": @[@"x", @{@"icon": @"y"}, @{@"icon": @{@"displayIdentifier": @"R"}}, @{@"icon": full[@"iconLists"][0][14], @"list": @5, @"page": @"x", @"others": @"x", @"rotated": @"x"}]}, note];
            for (NSDictionary *s in junk) { MSBDCCTileNote(s, OURS); for (NSDictionary *n in junkNotes) MSBDCCTilePutBack(s, n, OURS, &why); }
        } @catch (NSException *e) { threw = YES; printf("  threw: %s\n", e.reason.UTF8String); }
        CHECK(!threw, "damaged layouts and notes: nothing thrown");
        // the files: their own format kept
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tcct-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *f = [dir stringByAppendingPathComponent:@"x.plist"];
        NSPropertyListFormat fmt = 0;
        BOOL un = YES;
        CHECK(MSBDCCTileWrite(full, f, NSPropertyListBinaryFormat_v1_0) && [MSBDCCTileRead(f, &fmt, &un) isEqual:full] && fmt == NSPropertyListBinaryFormat_v1_0 && !un, "binary written and read back (18.5's layout is binary)");
        CHECK(MSBDCCTileWrite(full, f, NSPropertyListXMLFormat_v1_0) && [MSBDCCTileRead(f, &fmt, NULL) isEqual:full] && fmt == NSPropertyListXMLFormat_v1_0, "XML stays XML");
        // written over: the file keeps its permissions and its data protection class (the layout's class 4 on 18.5 -- on the Mac every file reads
        // as class 3, so here only that it is the one it had: the class itself is checked on the iPads), and no file of ours is left beside it
        chmod(f.fileSystemRepresentation, 0640);
        int was = MSBDCCTileClassOf(f); struct stat fst;
        CHECK(was > 0 && MSBDCCTileWrite(pruned, f, NSPropertyListBinaryFormat_v1_0) && [MSBDCCTileRead(f, NULL, NULL) isEqual:pruned] && stat(f.fileSystemRepresentation, &fst) == 0
              && (fst.st_mode & 07777) == 0640 && MSBDCCTileClassOf(f) == was, "written over: its permissions (0640) and its protection class (%d) kept", was);
        CHECK([[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL] isEqualToArray:@[@"x.plist"]], "  ... and nothing else left in its folder");
        // not read: "none" only when it is not there (code review, 30 Oct) -- a file that is there but cannot be read now is not "none"
        un = YES;
        CHECK(MSBDCCTileRead([dir stringByAppendingPathComponent:@"none"], NULL, &un) == nil && !un, "not there: nothing read, not unreadable (a note can be made)");
        chmod(f.fileSystemRepresentation, 0000);
        un = NO;
        CHECK(getuid() == 0 || (MSBDCCTileRead(f, NULL, &un) == nil && un), "there but not readable (here its permissions; on the iPad an I/O error or its class before the first unlock): unreadable");
        chmod(f.fileSystemRepresentation, 0644);
        NSString *closed = [dir stringByAppendingPathComponent:@"closed"], *inside = [closed stringByAppendingPathComponent:@"n.plist"];
        [[NSFileManager defaultManager] createDirectoryAtPath:closed withIntermediateDirectories:YES attributes:nil error:NULL];
        MSBDCCTileWrite(full, inside, NSPropertyListBinaryFormat_v1_0); chmod(closed.fileSystemRepresentation, 0000);
        un = NO;
        CHECK(getuid() == 0 || (MSBDCCTileRead(inside, NULL, &un) == nil && un), "  ... its folder not readable (whether it is there cannot be told): unreadable");
        chmod(closed.fileSystemRepresentation, 0755);
        [@"not a plist" writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        un = YES;
        CHECK(MSBDCCTileRead(f, NULL, &un) == nil && !un, "a damaged file: nothing read, not unreadable (it is written afresh)");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        CHECK([kMSBDCCTileStateFile isEqualToString:@"/var/mobile/Library/ControlCenter/ControlsIconState.plist"] && [kMSBDCCTileNoteFile hasPrefix:@"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-"], "the files: 18.5's layout, our note beside our other files");
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", passes, passes + fails);
    return fails ? 1 : 0;
}
