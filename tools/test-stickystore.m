// Mac test of the sticky notes' store across releases (1.8.8.2: the optional "page" and "name" keys of F36 and F37, a later release's keys kept):
// common/StickyNotes.h's MSBDStickyStoreRead and MSBDStickyStoreBuild, and 1.8.8.1's own copy of them (test-stickystore.sh builds this file a second
// time against 1.8.8.1's StickyNotes.h, -DT_OLD: the downgrade). Modes: "new <dir>" writes the stores and checks this release; "old <dir>" reads
// them as 1.8.8.1 does and writes back what 1.8.8.1 would; "back <dir>" reads 1.8.8.1's write with this release again.
#import <Foundation/Foundation.h>
#include "common/StickyNotes.h"
#define MSBD_NOTE_PAGE_MAX_T 200   // (the page key's cap this test holds the rule to: 1.8.8.1's header has none)

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)
static NSData *plist(id o) { return [NSPropertyListSerialization dataWithPropertyList:o format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL]; }
static id parse(NSData *d) { return d ? [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:NULL error:NULL] : nil; }
static NSString *const kA = @"0F2A6D1C-3B4E-4F5A-8B6C-7D8E9FA0B1C2", *const kB = @"1A2B3C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D", *const kC = @"2B3C4D5E-6F7A-4B8C-9DAE-1F2A3B4C5D6E";
static NSDictionary *store(void) {   // (a 1.8.8.2 store: a page 1 note, a note on another page with its own name, a note with a later release's keys)
    return @{@"version": @1, @"notes": @[
        @{@"id": kA, @"color": @"Yellow", @"x": @0.2, @"y": @0.3, @"w": @220, @"h": @180, @"text": @"MSB-TEST one"},
        @{@"id": kB, @"color": @"Blue", @"x": @0.6, @"y": @0.4, @"w": @260.5, @"h": @190, @"text": @"MSB-TEST two\nsecond line", @"page": @"home:7C0E2B54-1D3A-4C6E-9F80-A1B2C3D4E5F6", @"name": @"MSB-TEST Shopping"},
        @{@"id": kC, @"color": @"Pink", @"x": @0.5, @"y": @0.5, @"w": @220, @"h": @180, @"text": @"MSB-TEST three", @"page": @"display:tv-1", @"pinned": @YES, @"tags": @[@"MSB-TEST a", @2]}]};
}

int main(int argc, char **argv) { @autoreleasepool {
    NSString *mode = argc > 1 ? @(argv[1]) : @"new", *dir = argc > 2 ? @(argv[2]) : NSTemporaryDirectory();
#ifdef T_OLD
    if ([mode isEqualToString:@"old"]) {   // 1.8.8.1 reading a 1.8.8.2 store, and its first change written back
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array]; int skipped = -1;
        MSBDStickyStatus st = MSBDStickyStoreRead([NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"new.plist"]], 0, shown, kept, &skipped);
        CHECK(st == MSBDStickyOK && shown.count == 3 && skipped == 0 && [[shown valueForKey:@"id"] isEqualToArray:(@[kA, kB, kC])], "1.8.8.1 reads a 1.8.8.2 store: every note shown, none skipped, the same order (%lu notes)", (unsigned long)shown.count);
        BOOL bare = YES; for (NSDictionary *e in shown) if (e[@"page"] || e[@"name"] || e[@"pinned"]) bare = NO;
        CHECK(bare && [shown[1][@"text"] isEqualToString:@"MSB-TEST two\nsecond line"] && [shown[1][@"color"] isEqualToString:@"Blue"] && [shown[1][@"w"] doubleValue] == 260.5,
              "  ... without the page and the name (each note on page 1 with its default name), its text, colour, place and size as stored");
        [plist([parse(MSBDStickyStoreBuild(shown, kept)) copy]) writeToFile:[dir stringByAppendingPathComponent:@"old.plist"] atomically:YES];
        printf("test-stickystore (1.8.8.1's rules): %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
    return 2;
#else
    if ([mode isEqualToString:@"back"]) {   // back on 1.8.8.2 after 1.8.8.1 wrote the store
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array];
        MSBDStickyStatus st = MSBDStickyStoreRead([NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"old.plist"]], 0, shown, kept, NULL);
        BOOL bare = YES; for (NSDictionary *e in shown) if (e[@"page"] || e[@"name"]) bare = NO;
        CHECK(st == MSBDStickyOK && shown.count == 3 && bare, "back on 1.8.8.2 after 1.8.8.1 wrote the store: every note there, all on page 1 with their default names (none lost)");
        printf("test-stickystore (back): %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
    // ---- 1.8.8.1's notes: no page, no name -- read and written back with the very keys they had (no migration) ----
    {
        NSDictionary *old = @{@"version": @1, @"notes": @[@{@"id": kA, @"color": @"Green", @"x": @0.25, @"y": @0.75, @"w": @300, @"h": @200, @"text": @"MSB-TEST old"}]};
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array];
        CHECK(MSBDStickyStoreRead(plist(old), 0, shown, kept, NULL) == MSBDStickyOK && shown.count == 1 && !shown[0][@"page"] && !shown[0][@"name"], "a 1.8.8.1 note reads with no page (page 1) and no name of its own");
        CHECK([parse(MSBDStickyStoreBuild(shown, kept)) isEqual:old], "  ... and is written back as it was: the same keys and values, the version still 1");
    }
    // ---- a 1.8.8.2 store: the page and the name kept, and a later release's keys too ----
    {
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array]; int skipped = -1;
        CHECK(MSBDStickyStoreRead(plist(store()), 0, shown, kept, &skipped) == MSBDStickyOK && shown.count == 3 && skipped == 0, "a 1.8.8.2 store reads: three notes, none skipped");
        CHECK(shown.count == 3 && [shown[1][@"page"] isEqualToString:@"home:7C0E2B54-1D3A-4C6E-9F80-A1B2C3D4E5F6"] && [shown[1][@"name"] isEqualToString:@"MSB-TEST Shopping"] && !shown[0][@"page"] && !shown[0][@"name"],
              "  ... a note's page and own name are read; a note without them has none");
        CHECK(shown.count == 3 && [shown[2][@"page"] isEqualToString:@"display:tv-1"] && [shown[2][@"pinned"] isEqual:@YES] && [shown[2][@"tags"] isEqual:(@[@"MSB-TEST a", @2])],
              "  ... a page kind this release does not show yet and a later release's keys are kept as read");
        NSDictionary *back = parse(MSBDStickyStoreBuild(shown, kept));
        CHECK([back isEqual:store()], "  ... written back: the same store, every key and value");
        [plist(store()) writeToFile:[dir stringByAppendingPathComponent:@"new.plist"] atomically:YES];
        NSMutableArray *many = [NSMutableArray array];
        for (int i = 0; i < 31; i++) [many addObject:@{@"id": [NSUUID UUID].UUIDString, @"color": @"Gray", @"x": @0.5, @"y": @0.5, @"w": @220, @"h": @180, @"text": @"MSB-TEST", @"page": [NSString stringWithFormat:@"home:page-%d", i % 3]}];
        [shown removeAllObjects]; [kept removeAllObjects];
        MSBDStickyStoreRead(plist(@{@"version": @1, @"notes": many}), 0, shown, kept, NULL);
        CHECK(shown.count == 30 && kept.count == 1 && [kept[0][@"page"] isEqualToString:@"home:page-0"], "30 notes in total over every page: the 31st is kept as stored, its page with it");
    }
    // ---- bad values: a page that is no page reads as page 1, a name that is no name as the default; the note itself is kept ----
    {
        NSMutableString *longPage = [NSMutableString stringWithString:@"home:"]; while (longPage.length <= MSBD_NOTE_PAGE_MAX_T) [longPage appendString:@"x"];
        NSArray *bad = @[@{@"id": kA, @"x": @0.5, @"y": @0.5, @"w": @220, @"h": @180, @"page": @7, @"name": @5},
                         @{@"id": kB, @"x": @0.5, @"y": @0.5, @"w": @220, @"h": @180, @"page": @"", @"name": @"  \n\t "},
                         @{@"id": kC, @"x": @0.5, @"y": @0.5, @"w": @220, @"h": @180, @"page": longPage, @"name": @[@"x"]}];
        NSMutableArray *shown = [NSMutableArray array], *kept = [NSMutableArray array]; int skipped = -1;
        MSBDStickyStatus st = MSBDStickyStoreRead(plist(@{@"version": @1, @"notes": bad}), 0, shown, kept, &skipped);
        BOOL none = YES; for (NSDictionary *e in shown) if (e[@"page"] || e[@"name"]) none = NO;
        CHECK(st == MSBDStickyOK && shown.count == 3 && skipped == 0 && none, "a page or a name of the wrong kind, empty, blank or too long: the note shows on page 1 with its default name, never skipped");
        NSDictionary *back = parse(MSBDStickyStoreBuild(shown, kept));
        BOOL clean = YES; for (NSDictionary *e in back[@"notes"]) if (e[@"page"] || e[@"name"]) clean = NO;
        CHECK(clean, "  ... and is written back without them");
    }
#ifdef MSBD_NOTE_NAME_MAX
    // ---- the name's own rule (F37 keeps a typed name this way) ----
    {
        CHECK([MSBDStickyNameClean(@"  MSB-TEST\nlist\tB  ") isEqualToString:@"MSB-TEST list B"] && !MSBDStickyNameClean(@" \n ") && !MSBDStickyNameClean(@3) && !MSBDStickyNameClean(nil),
              "a name: line breaks and tabs made spaces, no spaces at its ends; blank or not a string: none (the default)");
        NSMutableString *lng = [NSMutableString string]; while (lng.length < 150) [lng appendString:@"n"];
        NSString *emoji = [[lng substringToIndex:MSBD_NOTE_NAME_MAX - 1] stringByAppendingString:@"\U0001F600 tail"];
        CHECK(MSBDStickyNameClean(lng).length == MSBD_NOTE_NAME_MAX && MSBDStickyNameClean(emoji).length == MSBD_NOTE_NAME_MAX - 1, "  ... at most 100 characters, never half of one (an emoji at the cut goes whole)");
        CHECK(MSBDStickyPageRead(@"home:x") && !MSBDStickyPageRead(@"") && !MSBDStickyPageRead(@4) && MSBD_NOTE_PAGE_MAX == MSBD_NOTE_PAGE_MAX_T, "a page key: a string of 1 to 200 characters");
    }
#endif
    printf("test-stickystore: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
#endif
} }
