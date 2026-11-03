// test-finderfolders.m: the Finder menu's attached Home Screen folders (common/FinderFolders.h, 1.7.9 item 3): the record by the folders' identity --
// in the order attached, kept through renames and moves, a deleted folder dropped --, the menu's rows (shown folders only, the jailbreak folder
// once) and their titles, and the folder's own Haptic Touch row.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "../common/FinderFolders.h"
static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static NSSet *S(NSArray *a) { return [NSSet setWithArray:a]; }
int main(void) {
    @autoreleasepool {
        // ---- the record as stored
        check("nothing stored, or not an array: none attached", MSBDFinderFoldersRecord(nil).count == 0 && MSBDFinderFoldersRecord(@"A").count == 0 && MSBDFinderFoldersRecord(@{@"A": @1}).count == 0);
        check("  ... its strings, each once, in their order (anything else left out)",
              [MSBDFinderFoldersRecord(@[@"B", @1, @"A", @"", @"B", [NSNull null], @"C"]) isEqualToArray:@[@"B", @"A", @"C"]]);

        // ---- attached: in the order attached (a Mac's sidebar order)
        NSArray *r = MSBDFinderFoldersAttach(@[], @"F1", nil);
        r = MSBDFinderFoldersAttach(r, @"F2", nil);
        r = MSBDFinderFoldersAttach(r, @"F3", nil);
        check("three folders attached one after another: F1, F2, F3", [r isEqualToArray:@[@"F1", @"F2", @"F3"]]);
        check("  ... attaching one again changes nothing (no copy, no move)", [MSBDFinderFoldersAttach(r, @"F1", nil) isEqualToArray:@[@"F1", @"F2", @"F3"]]);
        check("  ... removed: the others keep their order", [MSBDFinderFoldersDetach(r, @"F2", nil) isEqualToArray:@[@"F1", @"F3"]]);
        check("  ... removed, then attached again: at the end", [MSBDFinderFoldersAttach(MSBDFinderFoldersDetach(r, @"F1", nil), @"F1", nil) isEqualToArray:@[@"F2", @"F3", @"F1"]]);
        check("  ... removing one that is not attached changes nothing", [MSBDFinderFoldersDetach(r, @"F9", nil) isEqualToArray:r]);
        check("  ... no identifier (a folder without one): nothing attached", [MSBDFinderFoldersAttach(r, nil, nil) isEqualToArray:r] && [MSBDFinderFoldersAttach(r, @"", nil) isEqualToArray:r]);

        // ---- a deleted folder: out of the menu at once, out of the record at its next change; nothing dropped while the Home Screen is not known
        check("F2 deleted: dropped when another folder is attached (present: F1, F3, F4)",
              [MSBDFinderFoldersAttach(r, @"F4", S(@[@"F1", @"F3", @"F4"])) isEqualToArray:@[@"F1", @"F3", @"F4"]]);
        check("  ... and when one is removed", [MSBDFinderFoldersDetach(r, @"F1", S(@[@"F1", @"F3"])) isEqualToArray:@[@"F3"]]);
        check("  ... the Home Screen not known (nil): nothing dropped", [MSBDFinderFoldersAttach(r, @"F4", nil) isEqualToArray:@[@"F1", @"F2", @"F3", @"F4"]]);
        check("  ... the Finder menu leaves it out at once (not on the Home Screen)",
              [MSBDFinderFoldersListed(r, S(@[@"F1", @"F3"]), nil) isEqualToArray:@[@"F1", @"F3"]]);

        // ---- the menu's rows: by identity -- a rename or a move to another page keeps the folder and its place
        NSArray *listed = MSBDFinderFoldersListed(r, S(@[@"F3", @"F1", @"F2", @"F7"]), nil);
        check("the rows in the order attached, whatever the Home Screen's order (F3, F1, F2, F7 there)", [listed isEqualToArray:@[@"F1", @"F2", @"F3"]]);
        check("  ... a folder renamed or moved to another page: the same identifier, the same row and place",
              [MSBDFinderFoldersListed(r, S(@[@"F2", @"F3", @"F1"]), nil) isEqualToArray:@[@"F1", @"F2", @"F3"]]);
        check("  ... a folder on a hidden page (not shown): not listed, still attached",
              [MSBDFinderFoldersListed(r, S(@[@"F1", @"F3"]), nil) isEqualToArray:@[@"F1", @"F3"]] && [r containsObject:@"F2"]);
        check("  ... the jailbreak folder, attached too: listed once (the menu lists it by itself, first)",
              [MSBDFinderFoldersListed(r, S(@[@"F1", @"F2", @"F3"]), @"F2") isEqualToArray:@[@"F1", @"F3"]]);
        check("  ... none attached: no rows", MSBDFinderFoldersListed(@[], S(@[@"F1"]), nil).count == 0);

        // ---- the rows' titles: the folder's name, two of one name told apart by where they are
        check("names as they are", [MSBDFinderFolderTitles(@[@"Games", @"Work"], @[@2, @0]) isEqualToArray:@[@"Games", @"Work"]]);
        check("  ... two of one name: \"Games (Page 2)\", \"Games (Dock)\"",
              [MSBDFinderFolderTitles(@[@"Games", @"Work", @"Games"], @[@2, @1, @0]) isEqualToArray:@[@"Games (Page 2)", @"Work", @"Games (Dock)"]]);
        check("  ... a folder without a name: \"Folder\" (two of them told apart)",
              [MSBDFinderFolderTitles(@[@"", (id)[NSNull null]], @[@1, @3]) isEqualToArray:@[@"Folder (Page 1)", @"Folder (Page 3)"]]);
        check("  ... fewer places than names: the name alone", [MSBDFinderFolderTitles(@[@"A", @"A"], @[@1]) isEqualToArray:@[@"A (Page 1)", @"A"]]);

        // ---- the folder's own row
        check("not attached: \"Show in Finder Menu\"; attached: \"Remove from Finder Menu\"",
              [MSBDFinderFolderMenuTitle(NO) isEqualToString:@"Show in Finder Menu"] && [MSBDFinderFolderMenuTitle(YES) isEqualToString:@"Remove from Finder Menu"]);
    }
    if (fails) { printf("test-finderfolders (compiled): FAILED\n"); return 1; }
    printf("test-finderfolders (compiled): all checks pass\n"); return 0;
}
