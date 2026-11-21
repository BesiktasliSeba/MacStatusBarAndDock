// test-downloadsstack.m -- Mac test of the Dock's Downloads stack (1.8.8.1, KT 21 Nov: "in our dock downloads stack, the newest downloaded item
// should come to the bottom, and the items should be able to be shared easily etc by the long press finger or the trackpad menu").
// Runs, cut out of the sources by test-downloadsstack.sh (DS_DL_M / DS_FINDER_H: other copies, e.g. the code before the fix):
// - dock/Downloads.m's model and listings (ds-model.inc): DMDownload, DMDownloadSource, the order's helpers where the code has them (DMDownloadKeys,
//   DMDownloadDate, DMDownloadNewerFirst, DMDownloadRowTop), DMScan, DMFold and DMSearchIndex. They list folders of made-up files on this Mac's
//   APFS volume, which keeps a Date Added as the iPad's does: the stack must come in the order of a Mac's Downloads stack (Sort By Date Added,
//   its default), the newest first -- shown at the bottom, next to the stack --, also for items that came with older dates of their own (moved
//   in, AirDropped, dated by a server).
// - Downloads.m's press rules for an item's menu (ds-press.inc): kDMDLHoldMenu, DMDLPressTake, DMDLReleaseOpens, DMDLHoldEndOpens.
// - statusbar/Finder.h's rows of a stack item's menu (ds-finder.inc): DMFinderStackMenuRows, DMFinderStackMenuTitle.
// Where the code has none of these, the script says so (DS_NO_*) and those checks fail. No file of the user's: every file here is made up, in a
// folder of the test's own, removed after.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <sys/time.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

static int gKFails, gKPasses;
static void KCheck(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (ok) gKPasses++; else gKFails++; }
#define DMLog(...) do { } while (0)
#define DM_FEATURE_MARK(name) do { } while (0)

#include "ds-model.inc"
#include "ds-press.inc"
#include "ds-finder.inc"

// ---- the made-up folders
static NSString *gRoot;
static void KWrite(NSString *path) { [@"made up for the test" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]; }
static void KDate(NSString *path, time_t when) { struct timeval tv[2] = { { when, 0 }, { when, 0 } }; utimes(path.fileSystemRepresentation, tv); }
static void KStep(void) { usleep(60000); }   // (each item comes in a moment after the last: their Date Added differ)
static NSString *KNames(NSArray *items) {
    NSMutableArray *n = [NSMutableArray array];
    for (DMDownload *d in items) [n addObject:d.url.lastPathComponent ?: @"?"];
    return [n componentsJoinedByString:@", "];
}
static DMDownloadSource *KSource(NSString *name, NSString *folder, BOOL viaFiles) {
    DMDownloadSource *s = [DMDownloadSource new]; s.name = name; s.folder = [NSURL fileURLWithPath:folder isDirectory:YES]; s.viaFiles = viaFiles; return s;
}

static void KOrder(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *safari = [gRoot stringByAppendingPathComponent:@"Safari Downloads"], *browser = [gRoot stringByAppendingPathComponent:@"Browser Downloads"];
    NSString *elsewhere = [gRoot stringByAppendingPathComponent:@"Elsewhere"];
    for (NSString *d in @[safari, browser, elsewhere]) [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    const time_t y2018 = 1514764800, y2019 = 1546300800, y2020 = 1577836800, y2021 = 1609459200;
    // t0: a download written in place (Safari's)
    KWrite([safari stringByAppendingPathComponent:@"first-download.pdf"]); KStep();
    // t1: a browser's file dated as its server dates it (written in place, then its dates set back)
    NSString *server = [browser stringByAppendingPathComponent:@"server-dated.bin"]; KWrite(server); KDate(server, y2020); KStep();
    // t2: a file that keeps its older dates as it comes in (moved in: from Finder, a drop on the stack)
    NSString *kept0 = [elsewhere stringByAppendingPathComponent:@"kept-old-date.zip"]; KWrite(kept0); KDate(kept0, y2019);
    rename(kept0.fileSystemRepresentation, [safari stringByAppendingPathComponent:@"kept-old-date.zip"].fileSystemRepresentation); KStep();
    // t3: the same, AirDropped (an older picture)
    NSString *air0 = [elsewhere stringByAppendingPathComponent:@"airdropped-photo.png"]; KWrite(air0); KDate(air0, y2021);
    rename(air0.fileSystemRepresentation, [safari stringByAppendingPathComponent:@"airdropped-photo.png"].fileSystemRepresentation); KStep();
    // t4: the browser's newest download, written in place
    KWrite([browser stringByAppendingPathComponent:@"browser-file.txt"]); KStep();
    // t5: a folder (an archive unpacked), t6: an older file moved into it
    NSString *folder = [safari stringByAppendingPathComponent:@"unpacked-archive"]; [fm createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:nil error:nil]; KStep();
    NSString *inner0 = [elsewhere stringByAppendingPathComponent:@"inner-old.txt"]; KWrite(inner0); KDate(inner0, y2018);
    rename(inner0.fileSystemRepresentation, [folder stringByAppendingPathComponent:@"inner-old.txt"].fileSystemRepresentation); KStep();
    // never listed: a download not finished, a hidden file
    KWrite([safari stringByAppendingPathComponent:@"still-coming.zip.crdownload"]); KWrite([safari stringByAppendingPathComponent:@".hidden-file"]);

    NSDictionary *v = [[NSURL fileURLWithPath:[safari stringByAppendingPathComponent:@"kept-old-date.zip"]] resourceValuesForKeys:@[NSURLAddedToDirectoryDateKey, NSURLContentModificationDateKey] error:nil];
    BOOL added = [v[NSURLAddedToDirectoryDateKey] isKindOfClass:[NSDate class]] && [v[NSURLAddedToDirectoryDateKey] timeIntervalSince1970] > y2021;
    KCheck(added, @"this Mac's volume keeps a Date Added (as the iPad's APFS does): a file moved in has it from the move, whatever its own dates");
    KCheck([v[NSURLContentModificationDateKey] timeIntervalSince1970] < y2020, @"  ... while it keeps its own older Date Modified (what the stack sorted by before)");

    NSArray *sources = @[ KSource(@"Safari", safari, YES), KSource(@"Browser", browser, NO) ];
    NSArray<DMDownload *> *scan = DMScan(sources, 40);
    NSString *want = @"unpacked-archive, browser-file.txt, airdropped-photo.png, kept-old-date.zip, server-dated.bin, first-download.pdf";
    KCheck([KNames(scan) isEqualToString:want], [NSString stringWithFormat:@"DMScan: every source's items by Date Added, the newest first, as a Mac's stack (got: %@)", KNames(scan)]);
    NSUInteger air = NSNotFound, first = NSNotFound;
    for (NSUInteger k = 0; k < scan.count; k++) { if ([scan[k].url.lastPathComponent isEqualToString:@"airdropped-photo.png"]) air = k; if ([scan[k].url.lastPathComponent isEqualToString:@"first-download.pdf"]) first = k; }
    KCheck(air != NSNotFound && first != NSNotFound && air < first, @"  ... an AirDropped file with an older date of its own comes after the download before it, not among the old ones");
    NSArray<DMDownload *> *three = DMScan(sources, 3);
    KCheck([KNames(three) isEqualToString:@"unpacked-archive, browser-file.txt, airdropped-photo.png"], [NSString stringWithFormat:@"DMScan with a limit of 3: the 3 that came last (got: %@)", KNames(three)]);
    BOOL dated = scan.count > 0; for (DMDownload *d in scan) dated = dated && [d.date timeIntervalSince1970] > y2021;
    KCheck(dated, @"  ... each item's date (its age in the row) is when it came in, not the older date it carries");
    BOOL marks = YES; for (DMDownload *d in scan) marks = marks && ((d.viaFiles && [d.source isEqualToString:@"Safari"]) || (!d.viaFiles && [d.source isEqualToString:@"Browser"]));
    KCheck(marks && scan.count == 6, @"  ... each from its source, Safari's opened with Files; nothing unfinished or hidden listed (as before)");
    NSArray<DMDownload *> *index = DMSearchIndex(sources);
    NSString *wantIndex = @"inner-old.txt, unpacked-archive, browser-file.txt, airdropped-photo.png, kept-old-date.zip, server-dated.bin, first-download.pdf";
    KCheck([KNames(index) isEqualToString:wantIndex], [NSString stringWithFormat:@"DMSearchIndex: the items and those one folder down, by Date Added, the newest first (got: %@)", KNames(index)]);
    DMDownload *inner = index.firstObject;
    KCheck([inner.source isEqualToString:@"Safari › unpacked-archive"] && [inner.folded isEqualToString:@"inner-old.txt"], @"  ... an item inside a folder says where it is, and its folded name is made (as before)");
    {   // a rename in place keeps the item's Date Added (APFS, as on a Mac), so it keeps its place in the stack (the device pass's row D2)
        NSString *was = [safari stringByAppendingPathComponent:@"first-download.pdf"], *now = [safari stringByAppendingPathComponent:@"first-download-renamed.pdf"];
        rename(was.fileSystemRepresentation, now.fileSystemRepresentation);
        NSArray<DMDownload *> *again = DMScan(sources, 40);
        KCheck([KNames(again) isEqualToString:@"unpacked-archive, browser-file.txt, airdropped-photo.png, kept-old-date.zip, server-dated.bin, first-download-renamed.pdf"],
               [NSString stringWithFormat:@"DMScan after a rename in place: the item keeps its place (a rename keeps the Date Added, as on a Mac; got: %@)", KNames(again)]);
    }
#ifndef DS_NO_ORDER
    {   // the same date: by name, so the order never depends on the folder's listing
        DMDownload *a = [DMDownload new], *b = [DMDownload new];
        a.url = [NSURL fileURLWithPath:@"/x/b-second.txt"]; b.url = [NSURL fileURLWithPath:@"/x/a-first.txt"];
        a.date = b.date = [NSDate dateWithTimeIntervalSince1970:y2021];
        KCheck(DMDownloadNewerFirst(a, b) == NSOrderedDescending && DMDownloadNewerFirst(b, a) == NSOrderedAscending, @"DMDownloadNewerFirst: the same date goes by name");
        b.date = [NSDate dateWithTimeIntervalSince1970:y2021 + 1];
        KCheck(DMDownloadNewerFirst(a, b) == NSOrderedDescending, @"DMDownloadNewerFirst: the newer one first");
        KCheck([DMDownloadDate(@{}) isEqualToDate:[NSDate distantPast]], @"DMDownloadDate: an item that says no date goes last");
        NSDate *c = [NSDate dateWithTimeIntervalSince1970:y2019], *m = [NSDate dateWithTimeIntervalSince1970:y2020];
        KCheck(DMDownloadDate(@{ NSURLCreationDateKey: c, NSURLContentModificationDateKey: m }) == c, @"DMDownloadDate: a volume without a Date Added gives the Date Created");
        KCheck(DMDownloadDate(@{ NSURLContentModificationDateKey: m }) == m, @"  ... then the Date Modified");
        NSArray *keys = DMDownloadKeys(@[NSURLFileSizeKey]);
        KCheck([keys.firstObject isEqual:NSURLAddedToDirectoryDateKey] && [keys containsObject:NSURLCreationDateKey] && [keys containsObject:NSURLContentModificationDateKey] && [keys.lastObject isEqual:NSURLFileSizeKey],
               @"DMDownloadKeys: the listing reads Date Added first, the other dates, and what the caller asks");
        // the fan: the newest at the bottom, next to the stack
        BOOL fan = YES; const CGFloat h = 56.0;
        for (NSUInteger n = 1; n <= 12; n++) for (NSUInteger k = 0; k < n; k++) {
            fan = fan && DMDownloadRowTop(k, n, h) == (CGFloat)(n - 1 - k) * h;
            if (k > 0) fan = fan && DMDownloadRowTop(k, n, h) < DMDownloadRowTop(k - 1, n, h);
        }
        KCheck(fan && DMDownloadRowTop(0, 5, h) == 4 * h && DMDownloadRowTop(4, 5, h) == 0.0, @"DMDownloadRowTop: the newest at the bottom of the list (next to the stack), each older one a row above");
    }
#else
    KCheck(NO, @"this code has no DMDownloadKeys / DMDownloadDate / DMDownloadNewerFirst / DMDownloadRowTop (the order by Date Added)");
#endif
}

static void KPress(void) {
#ifndef DS_NO_PRESS
    int taken = 0;
    KCheck(DMDLPressTake(2, &taken, 1, 1) == 1 && taken == 1, @"DMDLPressTake: a press that began with the secondary button, down, in the list: its menu (once)");
    KCheck(DMDLPressTake(2, &taken, 1, 1) == 0, @"  ... asked again for the same press: no second menu");
    taken = 0; KCheck(DMDLPressTake(0, &taken, 1, 1) == 0 && !taken, @"  ... a finger's press (no button): not taken (its menu comes from the hold)");
    taken = 0; KCheck(DMDLPressTake(1, &taken, 1, 1) == 0 && !taken, @"  ... a primary click: not taken (its menu comes from the hold, a click opens)");
    taken = 0; KCheck(DMDLPressTake(2, &taken, 0, 1) == 0, @"  ... a press that is over: not taken");
    taken = 0; KCheck(DMDLPressTake(2, &taken, 1, 0) == 0, @"  ... a press that began elsewhere: not taken");
    KCheck(DMDLPressTake(2, NULL, 1, 1) == 0, @"  ... no place for the mark: not taken");
    KCheck(DMDLReleaseOpens(0, 1) && DMDLReleaseOpens(1, 1), @"DMDLReleaseOpens: a finger's tap and a click open the item");
    KCheck(!DMDLReleaseOpens(2, 1), @"  ... a secondary click's release does not (its menu opens)");
    KCheck(DMDLReleaseOpens(2, 0), @"  ... an assistive feature's use (no event) opens it");
    KCheck(DMDLHoldEndOpens(0, 1), @"DMDLHoldEndOpens: a hold let go before its menu opens the item (as before)");
    KCheck(!DMDLHoldEndOpens(1, 1), @"  ... let go after its menu opened: nothing opens, the menu stays");
    KCheck(!DMDLHoldEndOpens(0, 0) && !DMDLHoldEndOpens(1, 0), @"  ... a hold cancelled opens nothing");
    KCheck(kDMDLHoldMenu >= 0.3 && kDMDLHoldMenu <= 0.6, [NSString stringWithFormat:@"kDMDLHoldMenu %.2f s after the hold: Finder's hold menu time", kDMDLHoldMenu]);
    KCheck(kDMDLSecondaryButton == 2, @"kDMDLSecondaryButton is UIEventButtonMaskSecondary (1 << 1)");
#else
    KCheck(NO, @"this code has no press rules for an item's menu (DMDLPressTake, DMDLReleaseOpens, DMDLHoldEndOpens)");
#endif
}

#ifndef DS_NO_FINDER
static NSString *KRows(unsigned what) {
    int rows[16], usable[16];
    int n = DMFinderStackMenuRows(what, rows, usable, 16);
    NSMutableArray *out = [NSMutableArray array];
    for (int k = 0; k < n && k < 16; k++) {
        if (rows[k] == kDMFSMDivider) { [out addObject:@"|"]; continue; }
        [out addObject:[NSString stringWithFormat:@"%s%s", DMFinderStackMenuTitle(rows[k]), usable[k] ? "" : " (greyed)"]];
    }
    return [out componentsJoinedByString:@", "];
}
#endif
static void KFinder(void) {
#ifndef DS_NO_FINDER
    NSString *file = KRows(kDMFSMCanChange | kDMFSMShareApps);
    KCheck([file isEqualToString:@"Open, Quick Look, Show in Enclosing Folder, |, Get Info, Rename, Share, |, Move to Trash"], [NSString stringWithFormat:@"a file's menu: %@", file]);
    NSString *dir = KRows(kDMFSMDir | kDMFSMCanChange | kDMFSMShareApps);
    KCheck([dir isEqualToString:@"Open, Show in Enclosing Folder, |, Get Info, Rename, |, Move to Trash"], [NSString stringWithFormat:@"a folder's (Finder's: no Quick Look, no Share): %@", dir]);
    NSString *app = KRows(kDMFSMDir | kDMFSMApp | kDMFSMCanChange | kDMFSMShareApps);
    KCheck([app isEqualToString:@"Open, Show in Enclosing Folder, |, Get Info, Rename, Share, |, Move to Trash"], [NSString stringWithFormat:@"an app's (Share hands it over as Finder does): %@", app]);
    NSString *cloud = KRows(kDMFSMCloud | kDMFSMCanChange | kDMFSMShareApps);
    KCheck([cloud isEqualToString:@"Open, Quick Look, Show in Enclosing Folder, |, Get Info, Rename, |, Move to Trash"], [NSString stringWithFormat:@"an iCloud placeholder's (nothing to share yet): %@", cloud]);
    NSString *locked = KRows(kDMFSMShareApps);
    KCheck([locked isEqualToString:@"Open, Quick Look, Show in Enclosing Folder, |, Get Info, Rename (greyed), Share, |, Move to Trash (greyed)"], [NSString stringWithFormat:@"where Finder may not change it: %@", locked]);
    NSString *noApps = KRows(kDMFSMCanChange);
    KCheck([noApps isEqualToString:@"Open, Quick Look, Show in Enclosing Folder, |, Get Info, Rename, Share (greyed), |, Move to Trash"], [NSString stringWithFormat:@"no app that takes files: Share greyed, as the desktop's (%@)", noApps]);
    int rows[3] = { -1, -1, -1 }, usable[3] = { -1, -1, -1 };
    int n = DMFinderStackMenuRows(kDMFSMCanChange | kDMFSMShareApps, rows, usable, 2);
    KCheck(n == 9 && rows[2] == -1 && usable[2] == -1 && rows[0] == kDMFSMOpen, @"DMFinderStackMenuRows: the count of every row, at most cap written");
    KCheck(DMFinderStackMenuRows(0, NULL, NULL, 0) == 9, @"  ... and only the count with nowhere to write");
    KCheck(!strcmp(DMFinderStackMenuTitle(kDMFSMEnclosing), "Show in Enclosing Folder") && !strcmp(DMFinderStackMenuTitle(kDMFSMTrash), "Move to Trash") && !strcmp(DMFinderStackMenuTitle(99), ""),
           @"DMFinderStackMenuTitle: the Mac's words");
#else
    KCheck(NO, @"this code has no rows for a Downloads stack item's menu (Finder.h DMFinderStackMenuRows)");
#endif
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { printf("FAIL  usage: test-downloadsstack <empty work folder>\n"); return 1; }
        gRoot = [NSString stringWithUTF8String:argv[1]];
        KOrder();
        KPress();
        KFinder();
        printf("%d passed, %d failed\n", gKPasses, gKFails);
    }
    return gKFails;
}
