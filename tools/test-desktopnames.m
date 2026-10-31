// Mac test of statusbar/DesktopNames.h (the code Desktop.h runs, 1.7.2 item 16): an icon's own Hide Name kept by name -- through a move on the
// desktop, a respring, a rename (the desktop's own, or one made elsewhere and found by the file's inode) --, forgotten when the item leaves the
// desktop, kept while the Desktop folder itself is missing; the menu's row; Settings' switch for every name. Run by test-desktopnames.sh.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include "../statusbar/DesktopNames.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSSet *S(NSArray *a) { return [NSSet setWithArray:a]; }
static BOOL Is(NSSet *got, NSArray *want) { return [got isEqualToSet:S(want)]; }
static NSString *D(NSSet *s) { return [[[s allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]; }

// The desktop as Desktop.h keeps it: the record, the last listing's inodes, the folder missing or not -- driven the way its methods drive it.
@interface Desk : NSObject
@property (nonatomic, strong) NSMutableSet<NSString *> *hidden;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *inodes;   // (the last listing's, nil before the first)
@property (nonatomic, strong) NSArray *stored;                                // (the plist's "hiddenNames")
@property (nonatomic) int saves;
@end
@implementation Desk
- (instancetype)initFromStored:(NSArray *)stored { if ((self = [super init])) { _stored = stored; _hidden = DMNamesHiddenFromStored(stored); } return self; }
- (void)save { _stored = DMNamesHiddenToStore(_hidden); _saves++; }
// -dm_setItems:: a listing (name -> inode); missing: the folder is not there (no items)
- (void)list:(NSDictionary<NSString *, NSNumber *> *)now missing:(BOOL)missing {
    if (DMNamesHiddenFollowListing(_hidden, S(now.allKeys), now, _inodes, missing)) [self save];
    _inodes = now;
}
- (void)list:(NSDictionary *)now { [self list:now missing:NO]; }
// the menu's row for these icons: its title, and choosing it
- (NSString *)rowFor:(NSArray *)names every:(BOOL)every { return every || DMNamesHiddenEvery(_hidden, names) ? @"Show" : @"Hide"; }
- (void)choose:(NSArray *)names { if (DMNamesHiddenSet(_hidden, names, !DMNamesHiddenEvery(_hidden, names))) [self save]; }
// -dm_endRename: (the rename asked for; the listing that follows says whether it was made)
- (void)renameOwn:(NSString *)from to:(NSString *)to { if (DMNamesHiddenRenaming(_hidden, from, to, S(_inodes.allKeys))) [self save]; }
@end

int main(void) {
    @autoreleasepool {
        // ---- the stored record ----
        CHECK(DMNamesHiddenFromStored(nil).count == 0, "no record: none hidden");
        CHECK(DMNamesHiddenFromStored(@{@"a": @1}).count == 0 && DMNamesHiddenFromStored(@"a").count == 0, "a record of another type: none hidden");
        CHECK(Is(DMNamesHiddenFromStored(@[@"b", @3, @"", [NSNull null], @"a", @"b"]), @[@"a", @"b"]), "only names are read (numbers, empty strings, nulls left out; a name twice once)");
        CHECK(DMNamesHiddenToStore([NSSet set]) == nil, "none hidden: nothing written (the key removed)");
        CHECK([DMNamesHiddenToStore(S(@[@"c", @"a", @"b"])) isEqualToArray:(@[@"a", @"b", @"c"])], "written sorted: the same record writes the same array");
        CHECK(Is(DMNamesHiddenFromStored(DMNamesHiddenToStore(S(@[@"x y.txt", @"Ü.pdf", @"F"]))), @[@"x y.txt", @"Ü.pdf", @"F"]), "written and read back: the same names (spaces, accents)");

        // ---- Settings' switch and the icon's own record ----
        CHECK(DMNameShows(S(@[@"a"]), @"b", NO) && !DMNameShows(S(@[@"a"]), @"a", NO), "the switch off: an icon's name shows unless its own Hide Name was chosen");
        CHECK(!DMNameShows([NSSet set], @"b", YES) && !DMNameShows(S(@[@"a"]), @"a", YES), "the switch on: no name shows");
        CHECK(DMNameShows(nil, @"b", NO), "no record yet: every name shows");

        // ---- the menu's row ----
        {
            Desk *d = [[Desk alloc] initFromStored:nil];
            [d list:@{@"A": @10, @"B": @11, @"C": @12}];
            CHECK([[d rowFor:@[@"A"] every:NO] isEqualToString:@"Hide"], "an icon with its name: Hide Name");
            [d choose:@[@"A"]];
            CHECK(Is(d.hidden, @[@"A"]) && [d.stored isEqualToArray:(@[@"A"])] && d.saves == 1, "Hide Name: that icon only, saved at once");
            CHECK([[d rowFor:@[@"A"] every:NO] isEqualToString:@"Show"], "  ... its row now: Show Name");
            CHECK(([[d rowFor:@[@"A", @"B"] every:NO] isEqualToString:@"Hide"]), "a selection with a name still shown: Hide Names");
            [d choose:@[@"A", @"B"]];
            CHECK(Is(d.hidden, @[@"A", @"B"]), "  ... chosen: every one of them hidden");
            CHECK(([[d rowFor:@[@"A", @"B"] every:NO] isEqualToString:@"Show"]), "every one hidden: Show Names");
            [d choose:@[@"A", @"B"]];
            CHECK(d.hidden.count == 0 && d.stored == nil, "  ... chosen: every one shown again, nothing left in the record");
            int before = d.saves;
            CHECK(!DMNamesHiddenSet(d.hidden, @[@"C"], NO) && d.saves == before, "showing a name that shows: no change, nothing written");
            CHECK(!DMNamesHiddenSet(d.hidden, @[@"", (NSString *)@5], YES) && d.hidden.count == 0, "an empty name, or not a name: left alone");
            CHECK(!DMNamesHiddenEvery(d.hidden, @[]), "no icons: not 'every one hidden'");
        }

        // ---- kept: a move on the desktop, a respring ----
        {
            Desk *d = [[Desk alloc] initFromStored:nil];
            [d list:@{@"A": @10, @"B": @11}];
            [d choose:@[@"A"]];
            int saves = d.saves;
            [d list:@{@"A": @10, @"B": @11}];   // (a drag to another spot: the folder lists the same; the place is the places' record)
            CHECK(Is(d.hidden, @[@"A"]) && d.saves == saves, "a move on the desktop (the same names): kept, nothing written");
            Desk *after = [[Desk alloc] initFromStored:d.stored];   // (a respring: the record read back, no listing yet)
            CHECK(Is(after.hidden, @[@"A"]), "a respring: the record read back");
            [after list:@{@"A": @10, @"B": @11}];
            CHECK(Is(after.hidden, @[@"A"]) && after.saves == 0, "  ... the first listing after it (no last listing to compare): kept, nothing written");
            [after list:@{@"A": @99, @"B": @11}];
            CHECK(Is(after.hidden, @[@"A"]), "the same name, another file (an app saved it again: a new inode): kept, as the place is");
        }

        // ---- a rename made elsewhere (the Files app, a Finder window): the inode followed ----
        {
            Desk *d = [[Desk alloc] initFromStored:@[@"A"]];
            [d list:@{@"A": @10, @"B": @11}];
            [d list:@{@"A2": @10, @"B": @11}];
            CHECK(Is(d.hidden, @[@"A2"]) && [d.stored isEqualToArray:(@[@"A2"])], "a hidden icon renamed elsewhere: hidden under its new name, saved");
            [d list:@{@"A2": @10, @"B2": @11}];
            CHECK(Is(d.hidden, @[@"A2"]), "a shown icon renamed elsewhere: still shown (nothing to follow)");
            [d choose:@[@"B2"]];
            [d list:@{@"X": @10, @"Y": @11}];
            CHECK(Is(d.hidden, @[@"X", @"Y"]), "two hidden icons renamed in one listing: each by its own inode");
            [d list:@{@"X": @10, @"Y": @11, @"Z": @12}];
            [d list:@{@"Y": @11, @"Z": @12, @"W": @13}];
            CHECK(Is(d.hidden, @[@"Y"]), "a hidden icon gone and another new file (another inode) in the same listing: forgotten, the new file shows its name");
            [d list:@{@"Y": @11, @"Z": @12, @"W": @13}];
            [d list:@{@"Z": @11, @"W": @13}];   // (Y renamed to Z while Z itself went: Z was in the last listing)
            CHECK(Is(d.hidden, @[]), "renamed onto a name the last listing had (another file then): not followed -- the record follows names, as the places do");
        }
        {
            Desk *d = [[Desk alloc] initFromStored:@[@"A"]];
            [d list:@{@"A": @10}];
            [d list:@{@"B": @10, @"A": @10}];   // (a second name for the same file: a hard link)
            CHECK(Is(d.hidden, @[@"A"]), "the same file under a second name while the old one stays: the old name keeps it, the new one shows its name");
            [d list:@{@"B": @10}];
            CHECK(Is(d.hidden, @[]), "  ... the old name gone later (B was listed before): forgotten");
        }
        {
            Desk *d = [[Desk alloc] initFromStored:@[@"A"]];
            [d list:@{@"A": @10}];
            if (DMNamesHiddenFollowListing(d.hidden, S(@[@"B"]), @{}, d.inodes, NO)) [d save];   // (lstat failed for the new name: no inode for it)
            CHECK(Is(d.hidden, @[]), "a new name without an inode (it could not be read): nothing to follow, the old name forgotten");
        }

        // ---- the desktop's own rename (in place) ----
        {
            Desk *d = [[Desk alloc] initFromStored:@[@"A"]];
            [d list:@{@"A": @10, @"C": @12}];
            [d renameOwn:@"A" to:@"B"];
            CHECK(Is(d.hidden, @[@"A", @"B"]) && d.saves == 1, "renamed here: the new name hidden at once (the old one kept until the listing)");
            [d list:@{@"B": @10, @"C": @12}];
            CHECK(Is(d.hidden, @[@"B"]) && [d.stored isEqualToArray:(@[@"B"])], "  ... the listing shows it made: only the new name");
            [d renameOwn:@"B" to:@"Q"];
            [d list:@{@"B": @10, @"C": @12}];   // (refused: the name taken in the meantime, no permission)
            CHECK(Is(d.hidden, @[@"B"]), "a rename refused: the record as it was");
            int saves = d.saves;
            [d renameOwn:@"B" to:@"C"];
            CHECK(Is(d.hidden, @[@"B"]) && d.saves == saves, "renamed to the name of another icon there (refused anyway): that icon's name is not hidden");
            [d renameOwn:@"C" to:@"R"];
            CHECK(Is(d.hidden, @[@"B"]) && d.saves == saves, "a shown icon renamed: nothing to keep");
            [d renameOwn:@"B" to:@"B"];
            CHECK(d.saves == saves, "the same name typed again: nothing");
        }

        // ---- forgotten when the item leaves the desktop; kept while the folder is missing ----
        {
            Desk *d = [[Desk alloc] initFromStored:@[@"A", @"B"]];
            [d list:@{@"A": @10, @"B": @11}];
            [d list:@{@"B": @11}];
            CHECK(Is(d.hidden, @[@"B"]) && [d.stored isEqualToArray:(@[@"B"])], "an item gone from the desktop (to the Trash, another folder): forgotten, saved");
            [d list:@{@"A": @10, @"B": @11}];
            CHECK(Is(d.hidden, @[@"B"]), "  ... back again (Put Back, Undo): its name shows (it was forgotten)");
            [d list:@{} missing:YES];
            CHECK(Is(d.hidden, @[@"B"]), "the Desktop folder missing (no items): kept");
            [d list:@{@"A": @20, @"B": @21} missing:NO];
            CHECK(Is(d.hidden, @[@"B"]), "  ... the folder back (new inodes, nothing to compare): kept");
            Desk *boot = [[Desk alloc] initFromStored:@[@"A"]];
            [boot list:@{@"A2": @10}];
            CHECK(Is(boot.hidden, @[]), "renamed while SpringBoard was not running (the first listing has nothing to compare): forgotten -- as the place is");
        }

        // ---- the whole story, as KT asked for it ----
        {
            Desk *d = [[Desk alloc] initFromStored:nil];
            [d list:@{@"Report.pdf": @10, @"Photos": @11, @"notes.txt": @12}];
            [d choose:@[@"Photos"]];                                         // Hide Name
            [d list:@{@"Report.pdf": @10, @"Photos": @11, @"notes.txt": @12}]; // moved on the desktop
            d = [[Desk alloc] initFromStored:d.stored];                       // respring
            [d list:@{@"Report.pdf": @10, @"Photos": @11, @"notes.txt": @12}];
            [d renameOwn:@"Photos" to:@"Pictures"];                          // renamed on the desktop
            [d list:@{@"Report.pdf": @10, @"Pictures": @11, @"notes.txt": @12}];
            [d list:@{@"Report.pdf": @10, @"Holiday": @11, @"notes.txt": @12}]; // renamed again in the Files app
            CHECK(Is(d.hidden, @[@"Holiday"]) && DMNameShows(d.hidden, @"Report.pdf", NO) && !DMNameShows(d.hidden, @"Holiday", NO), "hidden through a move, a respring and two renames; the other icons keep their names");
            [d list:@{@"Report.pdf": @10, @"notes.txt": @12}];               // moved into a folder
            [d list:@{@"Report.pdf": @10, @"notes.txt": @12, @"Holiday": @11}];
            CHECK(d.hidden.count == 0 && d.stored == nil, "  ... left the desktop and came back: forgotten, the record empty");
        }
        printf("test-desktopnames: %d checks passed, %d failed\n", passes, fails);
    }
    return fails ? 1 : 0;
}
