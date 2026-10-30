// CCTileKeep.h -- iPadOS 18: RAM & CPU's tile keeps its place in Control Center through a SpringBoard that ran without our module.
// 18 keeps Control Center's layout in SpringBoardHome's icon state (ControlsIconState.plist: pages of tiles, each tile a module with a grid size)
// and drops every tile whose module is not there when SpringBoard reads it -- ours in the crash guard's safe mode, in ElleKit's Safe Mode (18.5
// enters it after one SpringBoard crash, before our guard has counted two), with the MacStatusBar line switched off in Choicy or iCleaner Pro, or
// while step 1b has RAM & CPU off. Back on, the module was there again but its tile was not (A12Z 18.5, 29 Oct: safe mode, then Turn Back On).
// So while our module is in Control Center's repository, SpringBoard keeps a note of where its tiles are -- each tile as the layout has it, its
// page, its neighbours there and in the page's rotated order -- taken from the layout whenever it is saved (CCGrabber.x); and when SpringBoard starts
// with our module again and the layout has lost a tile the note still has, the tile goes back where the note says, before Control Center reads the
// layout. A tile taken out while our module was there is noted as taken out, so it never comes back by itself. Only into a page that has nothing
// new since (a tile that came meanwhile could leave no room for ours). 15-17 keep the user's list of modules as it is (CCSModuleSettingsProvider,
// CCSupport's file): nothing to do there. Foundation only, so the Mac test (tools/test-cctile.sh) runs this very code.
#pragma once
#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/attr.h>
#include <sys/stat.h>

#define kMSBDCCTileStateFile @"/var/mobile/Library/ControlCenter/ControlsIconState.plist"   // (18.5: Control Center's layout, SpringBoard's)
#define kMSBDCCTileNoteFile @"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CCTile.plist"   // (ours: where the tiles were)

// A tile's identifier in the layout (nil when it has none).
static inline NSString *MSBDCCTileID(id icon) {
    id d = [icon isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)icon)[@"displayIdentifier"] : nil;
    return [d isKindOfClass:[NSString class]] && [(NSString *)d length] ? d : nil;
}
// The tile holds `moduleID` (one of its elements is that module).
static inline BOOL MSBDCCTileIsOurs(id icon, NSString *moduleID) {
    id elements = [icon isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)icon)[@"elements"] : nil;
    if (![elements isKindOfClass:[NSArray class]]) return NO;
    for (id e in (NSArray *)elements)
        if ([e isKindOfClass:[NSDictionary class]] && [((NSDictionary *)e)[@"moduleIdentifier"] isEqual:moduleID]) return YES;
    return NO;
}
// The layout's pages (each a list of tiles); nil when `state` is not a layout.
static inline NSArray<NSArray *> *MSBDCCTilePages(id state) {
    id pages = [state isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)state)[@"iconLists"] : nil;
    if (![pages isKindOfClass:[NSArray class]]) return nil;
    for (id p in (NSArray *)pages) if (![p isKindOfClass:[NSArray class]]) return nil;
    return pages;
}
// The pages' unique identifiers, one per page; nil when the layout has none (or not one per page).
static inline NSArray<NSString *> *MSBDCCTileListIDs(NSDictionary *state, NSUInteger pageCount) {
    id ids = state[@"listUniqueIdentifiers"];
    if (![ids isKindOfClass:[NSArray class]] || [(NSArray *)ids count] != pageCount) return nil;
    for (id i in (NSArray *)ids) if (![i isKindOfClass:[NSString class]]) return nil;
    return ids;
}
// A page's rotated order (its tiles' identifiers in the other orientation), nil when it has none.
static inline NSArray<NSString *> *MSBDCCTileRotated(NSDictionary *state, NSString *listID) {
    id meta = state[@"listMetadata"];
    id page = listID && [meta isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)meta)[listID] : nil;
    id order = [page isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)page)[@"rotatedOrder"] : nil;
    if (![order isKindOfClass:[NSArray class]]) return nil;
    for (id i in (NSArray *)order) if (![i isKindOfClass:[NSString class]]) return nil;
    return order;
}
static inline NSArray *MSBDCCTileIDsOf(NSArray *page) {   // (each tile's identifier, NSNull for one without)
    NSMutableArray *ids = [NSMutableArray arrayWithCapacity:page.count];
    for (id icon in page) [ids addObject:MSBDCCTileID(icon) ?: (id)[NSNull null]];
    return ids;
}
// The whole layout walked (its pages and anything else in it: SpringBoardHome's icon states can keep icons in other lists, e.g. the Home Screen's
// "ignored"): every tile identifier into `ids`, and the key path of every element of `moduleID` into `ours` ("/iconLists/<page>/<n>/elements/<m>").
static inline void MSBDCCTileWalk(id node, NSString *moduleID, NSMutableSet *ids, NSMutableArray *ours, NSString *path, int depth) {
    if (depth > 16) return;
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = node;
        NSString *tid = MSBDCCTileID(d);
        if (tid) [ids addObject:tid];
        if ([d[@"moduleIdentifier"] isEqual:moduleID]) [ours addObject:path];
        for (id k in d) MSBDCCTileWalk(d[k], moduleID, ids, ours, [NSString stringWithFormat:@"%@/%@", path, k], depth + 1);
    } else if ([node isKindOfClass:[NSArray class]]) {
        NSUInteger i = 0;
        for (id v in (NSArray *)node) MSBDCCTileWalk(v, moduleID, ids, ours, [NSString stringWithFormat:@"%@/%lu", path, (unsigned long)i++], depth + 1);
    }
}
// Where in `ids` a tile goes back: after the one that was before it, else before the one that was after it, else at its old place (at most the end).
static inline NSUInteger MSBDCCTileSlot(NSArray *ids, id after, id before, id index) {
    NSUInteger i;
    if ([after isKindOfClass:[NSString class]] && (i = [ids indexOfObject:after]) != NSNotFound) return i + 1;
    if ([before isKindOfClass:[NSString class]] && (i = [ids indexOfObject:before]) != NSNotFound) return i;
    long long at = [index isKindOfClass:[NSNumber class]] ? [(NSNumber *)index longLongValue] : (long long)ids.count;
    return at < 0 ? 0 : MIN((NSUInteger)at, ids.count);
}

// The note for a layout: placed (any of our tiles in it) and, for each tile in order, the tile itself, its page (identifier and number), its place
// there and its neighbours, the other tiles of that page, and its place in the page's rotated order. nil when `state` is not a layout.
static inline NSDictionary *MSBDCCTileNote(NSDictionary *state, NSString *moduleID) {
    NSArray<NSArray *> *pages = MSBDCCTilePages(state);
    if (!pages || !moduleID.length) return nil;
    NSArray<NSString *> *listIDs = MSBDCCTileListIDs(state, pages.count);
    NSMutableArray *tiles = [NSMutableArray array];
    for (NSUInteger p = 0; p < pages.count; p++) {
        NSArray *page = pages[p], *ids = MSBDCCTileIDsOf(page);
        for (NSUInteger i = 0; i < page.count; i++) {
            NSString *tid = MSBDCCTileID(page[i]);
            if (!tid || !MSBDCCTileIsOurs(page[i], moduleID)) continue;
            NSMutableDictionary *t = [@{@"icon": page[i], @"page": @(p), @"index": @(i)} mutableCopy];
            if (listIDs) t[@"list"] = listIDs[p];
            if (i > 0 && [ids[i - 1] isKindOfClass:[NSString class]]) t[@"after"] = ids[i - 1];
            if (i + 1 < ids.count && [ids[i + 1] isKindOfClass:[NSString class]]) t[@"before"] = ids[i + 1];
            NSMutableArray *others = [NSMutableArray array];
            for (NSUInteger j = 0; j < ids.count; j++) if (j != i && [ids[j] isKindOfClass:[NSString class]]) [others addObject:ids[j]];
            t[@"others"] = others;
            NSArray<NSString *> *rot = listIDs ? MSBDCCTileRotated(state, listIDs[p]) : nil;
            NSUInteger r = rot ? [rot indexOfObject:tid] : NSNotFound;
            if (r != NSNotFound) {
                NSMutableDictionary *rp = [@{@"index": @(r)} mutableCopy];
                if (r > 0) rp[@"after"] = rot[r - 1];
                if (r + 1 < rot.count) rp[@"before"] = rot[r + 1];
                t[@"rotated"] = rp;
            }
            [tiles addObject:t];
        }
    }
    return @{@"version": @1, @"placed": @(tiles.count > 0), @"tiles": tiles};
}

// The layout with the tiles of the note put back, or nil (with *why) when there is nothing to put back or it cannot be done safely: one of our tiles
// is on a page (it is there), our module is anywhere else in the layout (kept in another list: never a second copy), the note has none (not
// placed, or taken out), or for each tile: its page is gone (unless it held only our tiles: then it comes back, at its old place), the page has a
// tile it did not have then, or its identifier is in use anywhere in the layout. Every other part of the layout is left as it is.
static inline NSDictionary *MSBDCCTilePutBack(NSDictionary *state, NSDictionary *note, NSString *moduleID, NSString **why) {
    NSString *reason = nil; NSDictionary *out = nil;
    NSArray<NSArray *> *pages = MSBDCCTilePages(state);
    NSArray *tiles = [note isKindOfClass:[NSDictionary class]] && [note[@"tiles"] isKindOfClass:[NSArray class]] ? note[@"tiles"] : nil;
    BOOL placed = [note isKindOfClass:[NSDictionary class]] && [note[@"placed"] isKindOfClass:[NSNumber class]] && [note[@"placed"] boolValue];
    NSMutableSet *inUse = [NSMutableSet set]; NSMutableArray *ourPaths = [NSMutableArray array];
    if (pages && moduleID.length) MSBDCCTileWalk(state, moduleID, inUse, ourPaths, @"", 0);
    NSString *onPage = nil, *elsewhere = nil;
    for (NSString *p in ourPaths) { if ([p hasPrefix:@"/iconLists/"]) onPage = onPage ?: p; else elsewhere = elsewhere ?: p; }
    if (!pages || !moduleID.length) reason = @"no layout to put it in";
    else if (onPage) reason = @"the tile is there";
    else if (elsewhere) reason = [NSString stringWithFormat:@"the layout keeps our module elsewhere (%@): not put back", elsewhere];
    else if (!placed || !tiles.count) reason = @"not noted as placed (none then, or taken out)";
    else {
        NSArray<NSString *> *listIDs = MSBDCCTileListIDs(state, pages.count);
        NSMutableArray<NSString *> *ids = [listIDs mutableCopy];   // (the pages' identifiers as they become: a page that comes back gets its old one)
        NSMutableArray<NSMutableArray *> *newPages = [NSMutableArray arrayWithCapacity:pages.count];
        for (NSArray *page in pages) [newPages addObject:[page mutableCopy]];
        NSMutableDictionary *meta = [state[@"listMetadata"] isKindOfClass:[NSDictionary class]] ? [state[@"listMetadata"] mutableCopy] : nil;
        NSMutableSet *noted = [NSMutableSet set];   // (our noted tiles' identifiers: a page that held only these comes back with them)
        for (id t in tiles) { NSString *x = [t isKindOfClass:[NSDictionary class]] ? MSBDCCTileID(((NSDictionary *)t)[@"icon"]) : nil; if (x) [noted addObject:x]; }
        NSMutableArray *done = [NSMutableArray array], *not = [NSMutableArray array];
        for (id t in tiles) {
            NSDictionary *icon = [t isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)t)[@"icon"] : nil;
            NSString *tid = MSBDCCTileID(icon);
            if (!tid || !MSBDCCTileIsOurs(icon, moduleID)) { [not addObject:@"a noted tile is not one of ours"]; continue; }
            if ([inUse containsObject:tid]) { [not addObject:@"its identifier is in use"]; continue; }
            id list = t[@"list"], pageNum = t[@"page"];
            NSArray *then = [t[@"others"] isKindOfClass:[NSArray class]] ? t[@"others"] : nil;
            NSInteger p = -1;   // (its page: by identifier; by number only in a layout without identifiers, as the note was taken from)
            BOOL newPage = NO;
            if ([list isKindOfClass:[NSString class]]) { NSUInteger at = ids ? [ids indexOfObject:list] : NSNotFound; if (at != NSNotFound) p = (NSInteger)at; }
            else if (!ids && [pageNum isKindOfClass:[NSNumber class]] && [pageNum longLongValue] >= 0 && [pageNum unsignedLongLongValue] < newPages.count) p = [pageNum integerValue];
            if (p < 0 && ids && [list isKindOfClass:[NSString class]] && [pageNum isKindOfClass:[NSNumber class]] && then) {
                // its page is gone: one that held only our tiles then (a page left empty when 18 dropped them may go with them, as an empty Home
                // Screen page does) comes back at its old place, with its old identifier -- never a page that had anything else
                BOOL alone = YES;
                for (id o in then) alone &= [o isKindOfClass:[NSString class]] && [noted containsObject:o];
                if (alone) {
                    long long want = [pageNum longLongValue];
                    NSUInteger at = want < 0 ? 0 : MIN((NSUInteger)want, newPages.count);
                    [newPages insertObject:[NSMutableArray array] atIndex:at];
                    [ids insertObject:list atIndex:at];
                    if (meta && [t[@"rotated"] isKindOfClass:[NSDictionary class]] && ![meta[list] isKindOfClass:[NSDictionary class]]) meta[list] = @{@"rotatedOrder": @[]};
                    p = (NSInteger)at; newPage = YES;
                }
            }
            if (p < 0) { [not addObject:@"its page is gone"]; continue; }
            NSMutableArray *page = newPages[(NSUInteger)p];
            NSSet *thenSet = then ? [NSSet setWithArray:then] : [NSSet set];
            BOOL fits = YES;
            for (id icon2 in page) { NSString *o = MSBDCCTileID(icon2); fits &= o && [thenSet containsObject:o]; }
            if (!fits) { [not addObject:@"its page has a tile it did not have then"]; continue; }
            NSUInteger at = MSBDCCTileSlot(MSBDCCTileIDsOf(page), t[@"after"], t[@"before"], t[@"index"]);
            [page insertObject:icon atIndex:at];
            // its place in the page's rotated order (the order as it is now, with the tiles put back on this page so far)
            NSString *lid = ids ? ids[(NSUInteger)p] : nil;
            id pm0 = lid && meta ? meta[lid] : nil;
            id order0 = [pm0 isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)pm0)[@"rotatedOrder"] : nil;
            BOOL strings = [order0 isKindOfClass:[NSArray class]];
            for (id i in (strings ? order0 : @[])) strings &= [i isKindOfClass:[NSString class]];
            NSDictionary *rp = [t[@"rotated"] isKindOfClass:[NSDictionary class]] ? t[@"rotated"] : nil;
            if (rp && strings && ![(NSArray *)order0 containsObject:tid]) {
                NSMutableArray *order = [order0 mutableCopy];
                [order insertObject:tid atIndex:MSBDCCTileSlot(order, rp[@"after"], rp[@"before"], rp[@"index"])];
                NSMutableDictionary *pm = [pm0 mutableCopy];
                pm[@"rotatedOrder"] = order;
                meta[lid] = pm;
            }
            [inUse addObject:tid];
            [done addObject:[NSString stringWithFormat:@"page %ld at %lu%@", (long)p + 1, (unsigned long)at + 1, newPage ? @", the page back too" : @""]];
        }
        if (done.count) {
            NSMutableDictionary *m = [state mutableCopy];
            m[@"iconLists"] = newPages;
            if (ids) m[@"listUniqueIdentifiers"] = ids;
            if (meta) m[@"listMetadata"] = meta;
            out = m;
            reason = [NSString stringWithFormat:@"%lu tile(s) put back (%@)%@", (unsigned long)done.count, [done componentsJoinedByString:@", "],
                      not.count ? [NSString stringWithFormat:@"; not %lu: %@", (unsigned long)not.count, [not componentsJoinedByString:@", "]] : @""];
        } else reason = [@"not put back: " stringByAppendingString:[not componentsJoinedByString:@", "]];
    }
    if (why) *why = reason;
    return out;
}

// A property list file as a dictionary and its format; nil when it is not there, could not be read, or is not a dictionary. *unreadable (when
// asked for) is YES only for a file that is there but could not be read -- an I/O error, or a protection class whose key is not there yet (before
// the first unlock) --: what it holds may still matter, so it is not "none" (code review, 30 Oct). A file read whole that is no dictionary is
// damaged: NO.
static inline NSDictionary *MSBDCCTileRead(NSString *path, NSPropertyListFormat *format, BOOL *unreadable) {
    if (unreadable) *unreadable = NO;
    NSData *d = path ? [NSData dataWithContentsOfFile:path options:0 error:NULL] : nil;
    if (!d) {   // (not read: not there only when the path itself says so)
        struct stat st;
        if (unreadable && path) *unreadable = stat(path.fileSystemRepresentation, &st) == 0 || errno != ENOENT;
        return nil;
    }
    if (!d.length) return nil;
    NSPropertyListFormat f = NSPropertyListBinaryFormat_v1_0;
    id plist = [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:&f error:NULL];
    if (![plist isKindOfClass:[NSDictionary class]]) return nil;
    if (format) *format = f;
    return plist;
}
// The data protection class of the file at `path` (1 Complete, 2 Complete Unless Open, 3 Until First User Authentication, 4 None, and any newer
// one as it is); 0 when it has none or it cannot be told.
static inline int MSBDCCTileClassOf(NSString *path) {
    struct attrlist al; memset(&al, 0, sizeof(al));
    al.bitmapcount = ATTR_BIT_MAP_COUNT; al.commonattr = ATTR_CMN_DATA_PROTECT_FLAGS;
    struct { uint32_t length; uint32_t cls; } __attribute__((aligned(4), packed)) out = { 0, 0 };
    return path && getattrlist(path.fileSystemRepresentation, &al, &out, sizeof(out), 0) == 0 && out.length >= sizeof(out) ? (int)out.cls : 0;
}
// Written whole, in its own format (binary for the old text one, which can only be read), and put in place at once (readers see the old or the new).
// A file that is there keeps its data protection class and its permissions: an atomic write puts a new file in its place, which gets the writer's
// default class, not the one the file's owner gave it (code review, 30 Oct; measured on 16.7.7 and 18.5 the same day: Foundation's atomic write
// made a file of class 1, 2 or 3 one of class 4, the permissions it kept). Control Center's layout is class 4 on 18.5, as Apple's other files
// there, so it lost nothing so far; a layout of another class keeps it now. The new file is made with that class (open_dprotected_np, as
// Foundation's own protection options do it); a class it cannot be made with now (its key not there): not written. A new file, or one without a
// class (the jailbreak's folder, on the Preboot volume): as before.
static inline BOOL MSBDCCTileWrite(NSDictionary *plist, NSString *path, NSPropertyListFormat format) {
    if (format != NSPropertyListXMLFormat_v1_0) format = NSPropertyListBinaryFormat_v1_0;
    NSData *d = [NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:NULL];
    if (!d || !path.length) return NO;
    struct stat st;
    int cls = stat(path.fileSystemRepresentation, &st) == 0 ? MSBDCCTileClassOf(path) : 0;
    if (cls <= 0) return [d writeToFile:path options:NSDataWritingAtomic error:NULL];
    NSString *tmp = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.msbd-%d", path.lastPathComponent, getpid()]];
    unlink(tmp.fileSystemRepresentation);   // (a new file: a class is given only to a file being made)
    int fd = open_dprotected_np(tmp.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, cls, 0, st.st_mode & 07777);
    if (fd < 0) return NO;
    BOOL ok = fchmod(fd, st.st_mode & 07777) == 0;   // (the permissions as they were, whatever the writer's umask)
    const uint8_t *p = d.bytes; size_t left = d.length;
    while (ok && left) { ssize_t n = write(fd, p, left); if (n > 0) { p += n; left -= (size_t)n; } else ok = n < 0 && errno == EINTR; }
    if (close(fd) != 0) ok = NO;
    if (ok && rename(tmp.fileSystemRepresentation, path.fileSystemRepresentation) == 0) return YES;
    unlink(tmp.fileSystemRepresentation);
    return NO;
}

// ---- SpringBoard, 18 and later (CCGrabber.x), once our module is in Control Center's repository ----------------------------------------------------
// At the start: the tiles put back if the layout lost them while our module was not there; then the note, kept from the layout from now on -- the
// folder is watched (a layout saved as a new file put in place) and so is the file itself (one written in place); a change of the layout file
// (not of another file in that folder) is noted at once -- a SpringBoard that ends right after a save still leaves the note right -- and again half
// a second after the last one (a file written in parts), on a queue of its own; a note that could not be written is tried again. A note that is
// there but cannot be read at the start (an I/O error -- not its protection class: the jailbreak's folder is on the Preboot volume, which has
// none, 16.7.7 and 18.5) is neither used nor written over: kept, as a note whose tiles could not go back is, until the layout itself is saved (code
// review, 30 Oct: it was taken as no note, and a fresh one from a layout that had lost the tile said "not placed" -- the tile never came back).
// Paths and the log are arguments, so the Mac test runs this with files of its own; without a log (release builds) nothing is put in words.
typedef struct { BOOL present; long long ino, sec, nsec, size; } MSBDCCTileStamp;   // (the layout file: which one, when written, how long)
static inline MSBDCCTileStamp MSBDCCTileStampOf(NSString *path) {
    struct stat st; MSBDCCTileStamp s = { NO, 0, 0, 0, 0 };
    if (path && stat(path.fileSystemRepresentation, &st) == 0) { s.present = YES; s.ino = (long long)st.st_ino; s.sec = (long long)st.st_mtimespec.tv_sec; s.nsec = (long long)st.st_mtimespec.tv_nsec; s.size = (long long)st.st_size; }
    return s;
}
static inline BOOL MSBDCCTileStampSame(MSBDCCTileStamp a, MSBDCCTileStamp b) {
    return a.present == b.present && a.ino == b.ino && a.sec == b.sec && a.nsec == b.nsec && a.size == b.size;
}
static NSString *gMSBDCCTileState, *gMSBDCCTileNotePath, *gMSBDCCTileModule;
static void (^gMSBDCCTileLog)(NSString *);
#define MSBDCCTileLog(...) do { if (gMSBDCCTileLog) gMSBDCCTileLog([NSString stringWithFormat:__VA_ARGS__]); } while (0)
static dispatch_queue_t gMSBDCCTileQueue;
static dispatch_source_t gMSBDCCTileFolderWatch, gMSBDCCTileFileWatch;
static NSDictionary *gMSBDCCTileNoted;     // (on the queue: the note last written, or the one kept)
static MSBDCCTileStamp gMSBDCCTileSeen;    // (on the queue: the layout file the note stands for -- another change in the folder is not one of it)
static unsigned long gMSBDCCTileChanges;  // (on the queue: one per change seen, for the half second)
static int gMSBDCCTileRetries;            // (on the queue: a note that could not be written, tried again every 2 s, 5 times at most)
static void MSBDCCTileNoteFromLayout(NSString *when, BOOL always) {   // (on the queue)
    MSBDCCTileStamp now = MSBDCCTileStampOf(gMSBDCCTileState);
    if (!always && MSBDCCTileStampSame(now, gMSBDCCTileSeen)) return;   // (the layout file is as it was: another file of that folder changed)
    NSDictionary *note = MSBDCCTileNote(MSBDCCTileRead(gMSBDCCTileState, NULL, NULL), gMSBDCCTileModule);
    if (!note) { MSBDCCTileLog(@"%@: the layout could not be read -- the note stays as it was", when); return; }
    if ([note isEqual:gMSBDCCTileNoted]) { gMSBDCCTileSeen = now; return; }
    if (!MSBDCCTileWrite(note, gMSBDCCTileNotePath, NSPropertyListBinaryFormat_v1_0)) {
        MSBDCCTileLog(@"%@: the note could not be written%@", when, gMSBDCCTileRetries < 5 ? @" -- tried again in 2 s" : @"");
        if (gMSBDCCTileRetries++ < 5) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), gMSBDCCTileQueue, ^{ MSBDCCTileNoteFromLayout(@"again", YES); });
        return;
    }
    gMSBDCCTileNoted = note; gMSBDCCTileSeen = now; gMSBDCCTileRetries = 0;
    if (!gMSBDCCTileLog) return;
    NSMutableArray *where = [NSMutableArray array];
    for (NSDictionary *t in note[@"tiles"]) [where addObject:[NSString stringWithFormat:@"page %ld at %ld after %@", [t[@"page"] longValue] + 1, [t[@"index"] longValue] + 1, t[@"after"] ?: @"nothing"]];
    MSBDCCTileLog(@"%@: noted, placed %d%@%@", when, [note[@"placed"] boolValue], where.count ? @": " : @"", [where componentsJoinedByString:@"; "]);
}
static void MSBDCCTileChanged(void);
static void MSBDCCTileWatchFile(void) {   // (on the queue: the file that is there now -- after a change it may be a new one)
    if (gMSBDCCTileFileWatch) { dispatch_source_cancel(gMSBDCCTileFileWatch); gMSBDCCTileFileWatch = nil; }
    int fd = open(gMSBDCCTileState.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return;
    dispatch_source_t s = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, gMSBDCCTileQueue);
    if (!s) { close(fd); return; }
    dispatch_source_set_event_handler(s, ^{ MSBDCCTileChanged(); });
    dispatch_source_set_cancel_handler(s, ^{ close(fd); });
    gMSBDCCTileFileWatch = s;
    dispatch_resume(s);
}
static void MSBDCCTileChanged(void) {   // (on the queue)
    unsigned long mine = ++gMSBDCCTileChanges;
    MSBDCCTileWatchFile();
    MSBDCCTileNoteFromLayout(@"saved", NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), gMSBDCCTileQueue, ^{ if (mine == gMSBDCCTileChanges) MSBDCCTileNoteFromLayout(@"saved", NO); });
}
static void MSBDCCTileKeepStart(NSString *statePath, NSString *notePath, NSString *moduleID, void (^log)(NSString *)) {
    if (gMSBDCCTileQueue || !statePath.length || !notePath.length || !moduleID.length) return;
    gMSBDCCTileState = [statePath copy]; gMSBDCCTileNotePath = [notePath copy]; gMSBDCCTileModule = [moduleID copy]; gMSBDCCTileLog = [log copy];
    gMSBDCCTileQueue = dispatch_queue_create("com.besiktasliseba.macstatusbaranddock.cctile", DISPATCH_QUEUE_SERIAL);
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    BOOL noteUnreadable = NO;
    NSDictionary *state = MSBDCCTileRead(statePath, &format, NULL), *note = MSBDCCTileRead(notePath, NULL, &noteUnreadable);
    BOOL keep = NO;   // (a note whose tiles could not go back stays, for a later start -- until the layout itself is saved with our module there)
    if (state && note) {
        NSString *why = nil;
        NSDictionary *back = MSBDCCTilePutBack(state, note, moduleID, &why);
        if (back && MSBDCCTileWrite(back, statePath, format)) MSBDCCTileLog(@"start: %@", why);
        else if (back) { MSBDCCTileLog(@"start: the layout could not be written -- not put back"); keep = YES; }
        else { MSBDCCTileLog(@"start: %@", why); keep = [note[@"placed"] isKindOfClass:[NSNumber class]] && [note[@"placed"] boolValue] && ![why isEqualToString:@"the tile is there"]; }
    } else if (noteUnreadable) {   // (there, but not readable now: nothing put back, and not written over -- a later start reads it)
        MSBDCCTileLog(@"start: the note is there but could not be read -- nothing put back, the note kept as it is");
        keep = YES;
    } else MSBDCCTileLog(state ? @"start: no note yet" : @"start: no layout (Control Center has not saved one, or it could not be read)");
    dispatch_sync(gMSBDCCTileQueue, ^{
        if (keep) { gMSBDCCTileNoted = note; gMSBDCCTileSeen = MSBDCCTileStampOf(statePath); }   // (the layout as it is now: only a save of it replaces the note)
        else MSBDCCTileNoteFromLayout(@"start", YES);
        int fd = open(statePath.stringByDeletingLastPathComponent.fileSystemRepresentation, O_EVTONLY);
        dispatch_source_t s = fd >= 0 ? dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE, gMSBDCCTileQueue) : nil;
        if (s) {
            dispatch_source_set_event_handler(s, ^{ MSBDCCTileChanged(); });
            dispatch_source_set_cancel_handler(s, ^{ close(fd); });
            gMSBDCCTileFolderWatch = s;
            dispatch_resume(s);
        } else if (fd >= 0) close(fd);
        MSBDCCTileWatchFile();
    });
}
