// Finder.h -- a Mac Finder window for the iPad's files (2026-09-30), our first native window (NativeWindow.h), included into StatusBar.x.
// Files the iPad keeps anywhere SpringBoard can read: On My iPad, iCloud Drive, each app's Documents, the apps themselves, the whole file system.
// Sidebar (Favorites / Locations), a toolbar (back / forward, the folder's name, List / Icons, Search), a list or an icon grid, Quick Look for
// files, and the file actions of a Mac's Finder from a long-press (a right-click with a pointer): Open, Quick Look, Get Info, Rename, Duplicate,
// Copy / Paste, Move to Trash, Copy Path, Share, New Folder. Nothing is ever deleted at once: Move to Trash moves the item to the Finder's Trash
// (/var/mobile/.Trash), and only Empty Trash (with a question) deletes. Folders the iPad keeps closed to SpringBoard show a lock, not an error.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>
#import <PDFKit/PDFKit.h>   // (declarations only: PDFKit, AVKit and AVFoundation are opened at their first use, not linked -- SpringBoard
#import <AVKit/AVKit.h>     //  loaded them at every start for a window most people open rarely; see DMFinderClass)
#include <sys/clonefile.h>
#include <sys/xattr.h>
#include <sys/stat.h>
#include <copyfile.h>
#include <os/lock.h>
#include <sys/mount.h>
#include <sys/event.h>

static NSString *const kFinderTrash = @"/var/mobile/.Trash";
static NSString *const kFinderLiveFiles = @"/var/mobile/Library/LiveFiles";   // (external drives: <LiveFiles>/<provider>/<volume>, see DMFinderDrives)
static NSString *const kFinderICloud = @"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs";
// A class of a framework Finder needs only for some files (PDFKit, AVKit, AVFoundation): the framework is opened the first time.
static Class DMFinderClass(NSString *name) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *f in @[@"PDFKit", @"AVFoundation", @"AVKit"]) dlopen([NSString stringWithFormat:@"/System/Library/Frameworks/%@.framework/%@", f, f].UTF8String, RTLD_LAZY);
    });
    return NSClassFromString(name);
}

// ---- paths ------------------------------------------------------------------------------------------------------------------------------------
// One spelling for every comparison and classification: /private/var/... is /var/... (NSFileManager and realpath hand out either), no trailing
// slash. (Dropping a file into its own folder once renamed it: the two spellings compared as different folders, iPad 2 30 Sep.)
static NSString *DMFinderNorm(NSString *p) {
    if (!p.length) return p;
    NSString *s = p.stringByStandardizingPath;
    if ([s isEqualToString:@"/private/var"] || [s hasPrefix:@"/private/var/"]) s = [s substringFromIndex:8];
    while (s.length > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}
// The real place of a path (links followed), normalised; a path that does not exist yet: its deepest existing folder, resolved, plus the rest.
// The jailbreak's files keep their /var/jb spelling (it is a link into the preboot volume).
static NSString *DMFinderReal(NSString *p) {
    if (!p.length) return p;
    static NSString *jbReal; static dispatch_once_t once;
    dispatch_once(&once, ^{ char b[PATH_MAX]; if (realpath("/var/jb", b)) jbReal = DMFinderNorm([NSString stringWithUTF8String:b]); });
    char buf[PATH_MAX];
    NSString *out = nil;
    if (realpath(p.fileSystemRepresentation, buf)) out = DMFinderNorm([NSString stringWithUTF8String:buf]);
    else {
        NSString *n = DMFinderNorm(p);   // (not there (yet): "..", "." and "//" are resolved from the text first -- a ".." must never be kept)
        if (![n isEqualToString:p]) return DMFinderReal(n);
        NSString *parent = p.stringByDeletingLastPathComponent;
        if (!parent.length || [parent isEqualToString:p]) return DMFinderNorm(p);
        out = [DMFinderReal(parent) stringByAppendingPathComponent:p.lastPathComponent];
    }
    if (jbReal.length && ([out isEqualToString:jbReal] || [out hasPrefix:[jbReal stringByAppendingString:@"/"]])) out = [@"/var/jb" stringByAppendingString:[out substringFromIndex:jbReal.length]];
    return out;
}
// An item's own real place: its folder resolved, its name kept (an alias is the link itself, not what it points at).
static NSString *DMFinderRealItem(NSString *p) {
    NSString *parent = p.stringByDeletingLastPathComponent;
    return parent.length && ![parent isEqualToString:p] ? [DMFinderReal(parent) stringByAppendingPathComponent:p.lastPathComponent] : DMFinderReal(p);
}
static BOOL DMFinderInside(NSString *p, NSString *root) {   // p is root or inside it (both normalised)
    if (!p.length || !root.length) return NO;
    return [p isEqualToString:root] || [p hasPrefix:[root isEqualToString:@"/"] ? root : [root stringByAppendingString:@"/"]];
}
// A folder is the item itself or inside it: a move or copy there would put the item into itself (a Paste of a folder into its own subfolder
// copied it into itself level after level). Both sides resolved, so an alias or the /private spelling can't slip past.
static BOOL DMFinderIntoItself(NSString *item, NSString *destDir) {
    return DMFinderInside(DMFinderReal(destDir), DMFinderRealItem(item));
}

// ---- external drives ------------------------------------------------------------------------------------------------------------------------
// iPadOS mounts a USB drive's volumes through UserFS under LiveFiles: "fat://disk2s1/NO NAME on /private/var/mobile/Library/LiveFiles/
// com.apple.filesystems.userfsd/NO NAME (lifs, ..., mounted by mobile)" (M1, iPadOS 15.6.1). A drive is a volume the MOUNT TABLE (getfsstat) has
// exactly at <LiveFiles>/<provider>/<volume>, from a local disk ("<scheme>://diskN...", or /dev/diskN): any provider folder, not only userfsd, and
// a folder there that is not itself a mount point is never one (a leftover folder named like a volume stays read-only). Network shares
// (smb://...) are not drives. Read from any thread; the list is kept for half a second (the policy asks it for every check).
static os_unfair_lock gFinderDrivesLock = OS_UNFAIR_LOCK_INIT;
static NSArray<NSDictionary *> *gFinderDrivesCache; static CFTimeInterval gFinderDrivesAt = -100;
static BOOL DMFinderFromLocalDisk(NSString *from) {   // "fat://disk2s1/NO NAME", "exfat://disk3s1/X", "/dev/disk4s1"
    if ([from hasPrefix:@"/dev/disk"]) return YES;
    NSRange r = [from rangeOfString:@"://"];
    return r.location != NSNotFound && r.location > 0 && [[from substringFromIndex:r.location + 3] hasPrefix:@"disk"];
}
static NSArray<NSDictionary *> *DMFinderDrivesScan(void) {   // @[{t: volume name, p: mount point (normalised), fat: FAT12/16/32, from, type}]
    int n = getfsstat(NULL, 0, MNT_NOWAIT);
    if (n <= 0) return @[];
    n += 8;
    struct statfs *fs = calloc((size_t)n, sizeof *fs);
    if (!fs) return @[];
    n = getfsstat(fs, (int)(n * sizeof *fs), MNT_NOWAIT);
    NSMutableArray *out = [NSMutableArray array];
    NSString *lf = DMFinderNorm(kFinderLiveFiles);
    for (int i = 0; i < n; i++) {
        NSString *on = DMFinderNorm([NSString stringWithUTF8String:fs[i].f_mntonname] ?: @"");
        if (![on hasPrefix:[lf stringByAppendingString:@"/"]]) continue;
        NSArray *rest = [[on substringFromIndex:lf.length + 1] pathComponents];
        NSString *from = [NSString stringWithUTF8String:fs[i].f_mntfromname] ?: @"", *type = [NSString stringWithUTF8String:fs[i].f_fstypename] ?: @"";
        if (rest.count != 2 || !DMFinderFromLocalDisk(from)) continue;
#if DEBUG
        if (DMTestFlag("/tmp/msb-fdrive-hide")) continue;   // (tests: the drives look unplugged -- the windows' unplug handling, without touching the drive)
#endif
        NSString *scheme = [from containsString:@"://"] ? [from substringToIndex:[from rangeOfString:@"://"].location].lowercaseString : @"";
        BOOL fat = [@[@"fat", @"msdos", @"vfat", @"fat32"] containsObject:scheme] || [type isEqualToString:@"msdos"];   // (exFAT: "exfat", no 4 GB limit)
        [out addObject:@{@"t": on.lastPathComponent, @"p": on, @"fat": @(fat), @"from": from, @"type": type}];
    }
    free(fs);
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"t"] localizedStandardCompare:b[@"t"]]; }];
    return out;
}
static NSArray<NSDictionary *> *DMFinderDrives(void) {
    os_unfair_lock_lock(&gFinderDrivesLock);
    NSArray *have = gFinderDrivesCache; BOOL fresh = have && CACurrentMediaTime() - gFinderDrivesAt < 0.5;
    os_unfair_lock_unlock(&gFinderDrivesLock);
    if (fresh) return have;
    NSArray *now = DMFinderDrivesScan();
    os_unfair_lock_lock(&gFinderDrivesLock);
    gFinderDrivesCache = now; gFinderDrivesAt = CACurrentMediaTime();
    os_unfair_lock_unlock(&gFinderDrivesLock);
    return now;
}
static void DMFinderDrivesForget(void) { os_unfair_lock_lock(&gFinderDrivesLock); gFinderDrivesCache = nil; os_unfair_lock_unlock(&gFinderDrivesLock); }
// The drive a REAL path is on (its mount point), or nil.
static NSString *DMFinderDriveRoot(NSString *real) {
    if (!DMFinderInside(real, DMFinderNorm(kFinderLiveFiles))) return nil;
    for (NSDictionary *d in DMFinderDrives()) if (DMFinderInside(real, d[@"p"])) return d[@"p"];
    return nil;
}
static NSDictionary *DMFinderDriveInfo(NSString *root) { for (NSDictionary *d in DMFinderDrives()) if ([d[@"p"] isEqualToString:root]) return d; return nil; }
// A drive's Trash, as a Mac keeps it: <volume>/.Trashes/<uid> (501, mobile). Items moved to the Trash on a drive stay on it (a rename, instant).
static NSString *DMFinderDriveTrash(NSString *root) { return [root stringByAppendingPathComponent:[NSString stringWithFormat:@".Trashes/%u", getuid()]]; }
static NSArray<NSString *> *DMFinderDriveTrashes(void) { NSMutableArray *a = [NSMutableArray array]; for (NSDictionary *d in DMFinderDrives()) [a addObject:DMFinderDriveTrash(d[@"p"])]; return a; }
// A REAL path inside a drive's Trash folder (or that folder itself): the drive's own Trash -- the item's folder resolved, as for Finder's Trash.
static NSString *DMFinderDriveTrashOf(NSString *real) {
    NSString *root = DMFinderDriveRoot(real);
    if (!root) return nil;
    NSString *t = DMFinderDriveTrash(root);
    return DMFinderInside(real, t) ? t : nil;
}
// A drive's Trash is a real folder of its own (no link: Empty Trash must never erase where a link points).
static BOOL DMFinderDriveTrashIsSound(NSString *t) {
    struct stat st;
    // (not there yet: fine only if .Trashes is itself missing or a real folder ON the drive -- a .Trashes that is a link let a crafted drive
    //  have the trash made somewhere else, logic test 1.2.3)
    if (lstat(t.fileSystemRepresentation, &st) != 0) {
        if (errno != ENOENT) return NO;
        NSString *parent = t.stringByDeletingLastPathComponent;
        struct stat pst;
        if (lstat(parent.fileSystemRepresentation, &pst) != 0) return errno == ENOENT;
        return S_ISDIR(pst.st_mode) && [DMFinderReal(parent) isEqualToString:parent];
    }
    struct stat pst;   // (.Trashes, its folder, a real folder too)
    if (lstat(t.stringByDeletingLastPathComponent.fileSystemRepresentation, &pst) != 0 || !S_ISDIR(pst.st_mode)) return NO;
    return S_ISDIR(st.st_mode) && [DMFinderReal(t) isEqualToString:t];
}
// Files over 4 GB can't be stored on a FAT32 drive (its size field is 32 bits): the first such file in src (a file, or anything in a folder).
static const unsigned long long kFinderFATMax = 0xFFFFFFFFULL;
static NSString *DMFinderTooBigForFAT(NSString *src) {
    struct stat st;
    if (lstat(src.fileSystemRepresentation, &st) != 0) return nil;
    if (!S_ISDIR(st.st_mode)) return S_ISREG(st.st_mode) && (unsigned long long)st.st_size > kFinderFATMax ? src.lastPathComponent : nil;
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:src] includingPropertiesForKeys:@[NSURLFileSizeKey, NSURLIsRegularFileKey] options:0 errorHandler:nil];
    for (NSURL *u in en) {
        NSNumber *reg = nil, *size = nil; [u getResourceValue:&reg forKey:NSURLIsRegularFileKey error:nil]; [u getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (reg.boolValue && size.unsignedLongLongValue > kFinderFATMax) return u.lastPathComponent;
    }
    return nil;
}
// The FAT drive a folder is on (its info), or nil: the 4 GB rule applies there.
static NSDictionary *DMFinderFATDriveOf(NSString *dir) { NSString *root = DMFinderDriveRoot(DMFinderReal(dir)); NSDictionary *d = root ? DMFinderDriveInfo(root) : nil; return [d[@"fat"] boolValue] ? d : nil; }

// ---- places ---------------------------------------------------------------------------------------------------------------------------------
// On My iPad: the File Provider storage of the app group group.com.apple.FileProvider.LocalStorage (its container's metadata names it).
static NSString *DMFinderOnMyIPad(void) {
    static NSString *found; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *root = @"/var/mobile/Containers/Shared/AppGroup";
        for (NSString *uuid in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
            NSString *dir = [root stringByAppendingPathComponent:uuid];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
            if ([meta[@"MCMMetadataIdentifier"] isEqual:@"group.com.apple.FileProvider.LocalStorage"]) { found = [dir stringByAppendingPathComponent:@"File Provider Storage"]; break; }
        }
    });
    return found;
}
// A data container's app, for folder names that are only a UUID (Containers/Data/Application/<UUID>, Bundle/Application/<UUID>): its name and
// its bundle id. Asked from the listing's background queue and from the main thread at once (two windows loading, Back / Forward): the cache
// is behind a lock (a plain dictionary shared between threads could crash SpringBoard).
static os_unfair_lock gFinderNamesLock = OS_UNFAIR_LOCK_INIT;
static NSArray<NSString *> *DMFinderContainerInfo(NSString *path) {   // @[name, bundle id] ("" when unknown)
    static NSMutableDictionary<NSString *, NSArray *> *cache;
    os_unfair_lock_lock(&gFinderNamesLock);
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSArray *hit = cache[path];
    os_unfair_lock_unlock(&gFinderNamesLock);
    if (hit) return hit;
    NSString *name = @"", *bid = @"";
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
    NSString *mid = meta[@"MCMMetadataIdentifier"];
    if ([mid isKindOfClass:[NSString class]]) {
        bid = mid;
        NSString *n = DMCall(DMProxyForBundle(mid), @"localizedName");
        name = n.length ? n : mid;
    } else {   // (an app bundle folder: the .app inside)
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil]) if ([f hasSuffix:@".app"]) {
            name = [f stringByDeletingPathExtension];
            NSString *b = [NSDictionary dictionaryWithContentsOfFile:[[path stringByAppendingPathComponent:f] stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"];
            if ([b isKindOfClass:[NSString class]]) bid = b;
            break;
        }
    }
    NSArray *info = @[name, bid];
    os_unfair_lock_lock(&gFinderNamesLock);
    cache[path] = info;
    os_unfair_lock_unlock(&gFinderNamesLock);
    return info;
}
static NSString *DMFinderContainerName(NSString *path) { NSString *n = DMFinderContainerInfo(path)[0]; return n.length ? n : nil; }
// Apps the user hides with AppHider (its own list): Finder does not show their bundles or data containers either (they would give the hidden
// apps away by name). Read at most every 5 s, from any thread.
static NSSet<NSString *> *DMFinderHiddenApps(void) {
    static NSSet *hidden; static CFTimeInterval at = -100;
    os_unfair_lock_lock(&gFinderNamesLock);
    BOOL stale = CACurrentMediaTime() - at > 5.0; NSSet *have = hidden;
    os_unfair_lock_unlock(&gFinderNamesLock);
    if (!stale) return have ?: [NSSet set];
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *f in @[@"/var/jb/var/mobile/Library/Preferences/lilliana.apphider.plist", @"/var/mobile/Library/Preferences/lilliana.apphider.plist"]) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:f];
        if (!d) continue;
        id on = d[@"isEnabled"];
        if ([on respondsToSelector:@selector(boolValue)] && ![on boolValue]) break;
        id apps = d[@"apps"];
        if ([apps isKindOfClass:[NSArray class]]) for (id b in apps) if ([b isKindOfClass:[NSString class]]) [set addObject:b];
        break;
    }
    os_unfair_lock_lock(&gFinderNamesLock);
    hidden = [set copy]; at = CACurrentMediaTime();
    os_unfair_lock_unlock(&gFinderNamesLock);
    return set;
}
// The desktop's folder: "Desktop" in On My iPad (the Files app's own storage, one of the user's places), made when it is missing and `make` is set
// (as SpringBoard, the user's own: the Files app shows it like a folder made there). nil when On My iPad isn't there or it can't be made.
static NSString *DMFinderDesktopFolder(BOOL make) {
    NSString *mine = DMFinderOnMyIPad();
    if (!mine) return nil;
    NSString *d = DMFinderNorm([mine stringByAppendingPathComponent:@"Desktop"]);
    struct stat st;
    if (lstat(d.fileSystemRepresentation, &st) == 0) return S_ISDIR(st.st_mode) ? d : nil;   // (a file or a link named Desktop: not used, never replaced)
    if (!make) return nil;
    DM_FEATURE_MARK("finder-desktop-folder");
    NSError *e = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:NO attributes:nil error:&e]) { DMLog([NSString stringWithFormat:@"[desktop] the Desktop folder could not be made: %@", e.localizedDescription]); return nil; }
    DMLog(@"[desktop] the Desktop folder was made in On My iPad");
    return d;
}
static NSArray<NSDictionary *> *DMFinderSidebar(void) {
    NSMutableArray *favs = [NSMutableArray array], *locs = [NSMutableArray array];
    NSString *desk = DMFinderDesktopFolder(YES);   // (Desktop first, as on a Mac: the folder whose files the Home Screen's first page shows, Desktop.h)
    if (desk) [favs addObject:@{@"t": @"Desktop", @"p": desk, @"i": @"menubar.dock.rectangle", @"desktop": @YES}];
    NSString *mine = DMFinderOnMyIPad();
    if (mine) [favs addObject:@{@"t": @"On My iPad", @"p": mine, @"i": @"ipad"}];
    NSString *icloud = @"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs";
    if ([[NSFileManager defaultManager] fileExistsAtPath:icloud]) {
        [favs addObject:@{@"t": @"iCloud Drive", @"p": icloud, @"i": @"icloud"}];
        NSString *dl = [icloud stringByAppendingPathComponent:@"Downloads"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dl]) [favs addObject:@{@"t": @"Downloads", @"p": dl, @"i": @"arrow.down.circle"}];
    }
    [favs addObject:@{@"t": @"Documents", @"p": @"/var/mobile/Documents", @"i": @"doc"}];
    [favs addObject:@{@"t": @"App Documents", @"p": @"/var/mobile/Containers/Data/Application", @"i": @"folder.badge.person.crop"}];
    [favs addObject:@{@"t": @"Applications", @"p": @"/var/containers/Bundle/Application", @"i": @"square.grid.3x3"}];
    [locs addObject:@{@"t": @"Home", @"p": @"/var/mobile", @"i": @"house"}];
    [locs addObject:@{@"t": @"iPad", @"p": @"/", @"i": @"internaldrive"}];
    for (NSDictionary *d in DMFinderDrives()) [locs addObject:@{@"t": d[@"t"], @"p": d[@"p"], @"i": @"externaldrive", @"drive": @YES}];   // (connected drives, live)
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) [locs addObject:@{@"t": @"Jailbreak", @"p": @"/var/jb", @"i": @"lock.open"}];
    [locs addObject:@{@"t": @"Trash", @"p": kFinderTrash, @"i": @"trash"}];
    return @[@{@"h": @"Favorites", @"rows": favs}, @{@"h": @"Locations", @"rows": locs}];
}

// ---- where Finder may change things -----------------------------------------------------------------------------------------------------------
// SpringBoard runs unsandboxed: without a rule, a drag that drifted onto a folder could move /var/mobile/Library (Safe Mode, a respring loop).
// One policy for every write -- move, rename, trash, delete, new folder, paste, drop, duplicate --, like a Mac keeping the system's files out of a
// normal user's reach: Finder changes files ONLY inside the user's own places (On My iPad, Documents, iCloud Drive with its Downloads and the
// apps' iCloud folders, each app's Documents folder, Finder's Trash). Everywhere else it only reads: browsing and copying OUT stay possible,
// every write is refused with a short sheet ("... can't be changed"), and no sheet can override it. Default deny: a path is free only when its
// real place (links followed, /private/var spelled /var, ".." resolved) lies inside one of those places, so an alias, another spelling or a
// case difference can only ever make Finder more careful, never less. Also refused: items owned by root, folders Finder can't write to.
//  - free: inside the user's places;
//  - a connected drive (DMFinderDrives): everything INSIDE the mounted volume is free too -- the drive is the user's own, as on a Mac. Only
//    inside it: the volume's own folder (the mount point), its .Trashes structure, LiveFiles and every provider folder stay read-only, and the
//    real place decides (an alias on the drive pointing at the iPad's system is the system);
//  - critical: the places themselves and the folders above them, the desktop's folder (On My iPad's Desktop, as on a Mac), containers, app
//    bundles (named apart only for tests and messages);
//  - system: everything else outside the user's places. Critical and system are both read-only.
typedef NS_ENUM(int, DMFinderZone) { DMFinderZoneFree = 0, DMFinderZoneSystem = 1, DMFinderZoneCritical = 2 };
static NSArray<NSString *> *DMFinderFreeRoots(void) {
    static NSArray *roots; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray arrayWithObjects:kFinderICloud, @"/var/mobile/Documents", kFinderTrash, nil];
        NSString *mine = DMFinderOnMyIPad(); if (mine) [a addObject:DMFinderNorm(mine)];
        roots = [a copy];
    });
    return roots;
}
static BOOL DMFinderIsContainerDir(NSString *p) {   // a container folder: <...>/Containers/<Data|Bundle|Shared>/<kind>/<UUID>, /var/containers/...
    NSString *name = p.lastPathComponent, *parent = p.stringByDeletingLastPathComponent;
    return name.length == 36 && [name characterAtIndex:8] == '-' && ([parent hasPrefix:@"/var/mobile/Containers/"] || [parent hasPrefix:@"/var/containers/"]);
}
// What an operation may do with an ITEM at path p (moving it away, renaming it, trashing it). p: DMFinderRealItem of it.
static DMFinderZone DMFinderItemZone(NSString *p) {
    if (!p.length || [p isEqualToString:@"/"]) return DMFinderZoneCritical;
    for (NSDictionary *d in DMFinderDrives()) {   // (a connected drive: inside it free; the volume itself, the folders above it, its Trash folders not)
        NSString *r = d[@"p"], *t = DMFinderDriveTrash(r);
        if (DMFinderInside(r, p)) return DMFinderZoneCritical;
        if (!DMFinderInside(p, r)) continue;
        if (DMFinderInside(p, t.stringByDeletingLastPathComponent) && (!DMFinderInside(p, t) || [p isEqualToString:t])) return DMFinderZoneCritical;   // (.Trashes, other users' Trash)
        return DMFinderZoneFree;
    }
    // (the desktop's folder, On My iPad's Desktop, as a Mac's: it can't be trashed, renamed or moved -- the Home Screen's first page shows it --,
    //  what is in it is free; any spelling of its name, the file system ignores case)
    NSString *mine = DMFinderOnMyIPad();
    if (mine && [p caseInsensitiveCompare:[DMFinderNorm(mine) stringByAppendingPathComponent:@"Desktop"]] == NSOrderedSame) return DMFinderZoneCritical;
    for (NSString *r in DMFinderFreeRoots()) {
        if (DMFinderInside(r, p)) return DMFinderZoneCritical;    // (a place itself, or a folder above one)
        if (DMFinderInside(p, r)) return DMFinderZoneFree;
    }
    // an app's own Documents (Containers/Data/Application/<UUID>/Documents/...) and the apps' iCloud folders (Mobile Documents/<app>/Documents/...)
    NSArray *c = p.pathComponents;   // ("/", "var", "mobile", "Containers", "Data", "Application", <UUID>, "Documents", ...)
    if (c.count > 8 && [p hasPrefix:@"/var/mobile/Containers/Data/Application/"] && [c[7] isEqualToString:@"Documents"]) return DMFinderZoneFree;
    if (c.count > 7 && [p hasPrefix:@"/var/mobile/Library/Mobile Documents/"] && [c[6] isEqualToString:@"Documents"]) return DMFinderZoneFree;
    if (c.count <= 4) return DMFinderZoneCritical;   // (/var/x/y: /var/mobile/Library, /var/jb/usr, /var/containers/Bundle, ...)
    NSString *parent = p.stringByDeletingLastPathComponent;
    if ([parent isEqualToString:@"/var/mobile/Library"] || ([parent hasPrefix:@"/var/jb"] && c.count <= 5)) return DMFinderZoneCritical;
    if (DMFinderIsContainerDir(p) || DMFinderIsContainerDir(parent)) return DMFinderZoneCritical;   // (a container, or its Documents / Library / tmp)
    if ([p.pathExtension isEqualToString:@"app"] || [p containsString:@".app/"]) return DMFinderZoneCritical;
    return DMFinderZoneSystem;
}
// What an operation may do INTO a folder (a move, copy, paste, new copy there): free inside the user's places, else a system location.
static DMFinderZone DMFinderDestZone(NSString *dir) {
    NSString *d = DMFinderReal(dir);
    for (NSString *r in DMFinderFreeRoots()) if (DMFinderInside(d, r)) return DMFinderZoneFree;
    if (DMFinderDriveRoot(d)) return DMFinderZoneFree;   // (inside a connected drive, its own folder included)
    NSArray *c = d.pathComponents;
    if (c.count > 7 && [d hasPrefix:@"/var/mobile/Containers/Data/Application/"] && [c[7] isEqualToString:@"Documents"]) return DMFinderZoneFree;
    if (c.count > 6 && [d hasPrefix:@"/var/mobile/Library/Mobile Documents/"] && [c[6] isEqualToString:@"Documents"]) return DMFinderZoneFree;
    return DMFinderZoneSystem;
}
// iCloud Drive and On My iPad are File Provider storage: every write there goes through NSFileCoordinator, as the Files app's own do (a raw
// rename bypassed the sync daemon: iCloud saw a deletion on every device).
static BOOL DMFinderInICloud(NSString *p) { return DMFinderInside(DMFinderNorm(p), @"/var/mobile/Library/Mobile Documents"); }
static BOOL DMFinderCoordinated(NSString *p) {
    NSString *n = DMFinderNorm(p), *mine = DMFinderOnMyIPad();
    return DMFinderInICloud(n) || (mine && DMFinderInside(n, DMFinderNorm(mine)));
}
// (the item's own place, its folder resolved: an alias in the Trash is in the Trash -- it was Delete Immediately refused "not in the Trash" for a
//  link pointing outside, and Command-Delete moved it within the Trash; a folder path is the same either way)
// (a drive's Trash, <volume>/.Trashes/501, is Finder's Trash too: its items are shown in the Trash, deleted by Empty Trash / Delete Immediately)
static BOOL DMFinderInOwnTrash(NSString *p) { NSString *r = DMFinderRealItem(p); return DMFinderInside(r, kFinderTrash) || DMFinderDriveTrashOf(r) != nil; }
// Finder may change this item (move it away, rename it, trash it): in the user's places, not owned by root, its folder writable.
static BOOL DMFinderCanChange(NSString *path) {
    if (!path.length) return NO;
    NSString *r = DMFinderRealItem(path);
    if (DMFinderItemZone(r) != DMFinderZoneFree) return NO;
    struct stat st; if (lstat(r.fileSystemRepresentation, &st) == 0 && st.st_uid == 0) return NO;
    return access(r.stringByDeletingLastPathComponent.fileSystemRepresentation, W_OK) == 0;
}
// Finder may write into this folder (a new folder, a paste, a drop, a duplicate, a move's target): in the user's places, not the Trash (only
// Move to Trash puts things there), not owned by root, writable.
static BOOL DMFinderCanWriteInto(NSString *dir) {
    if (!dir.length || DMFinderDestZone(dir) != DMFinderZoneFree) return NO;
    NSString *r = DMFinderReal(dir);
    if (DMFinderInside(r, kFinderTrash) || DMFinderInside(r, [kFinderICloud stringByAppendingPathComponent:@".Trash"])) return NO;
    NSString *drive = DMFinderDriveRoot(r);   // (a drive's .Trashes, every user's: only Move to Trash puts things there)
    if (drive && DMFinderInside(r, [drive stringByAppendingPathComponent:@".Trashes"])) return NO;
    struct stat st; if (lstat(r.fileSystemRepresentation, &st) == 0 && st.st_uid == 0) return NO;
    return access(r.fileSystemRepresentation, W_OK) == 0;
}
static unsigned long long DMFinderFreeSpace(NSString *dir) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfFileSystemForPath:DMFinderReal(dir) error:nil];
    return a ? [a[NSFileSystemFreeSize] unsignedLongLongValue] : ULLONG_MAX;
}

// ---- items ----------------------------------------------------------------------------------------------------------------------------------
@interface DMFinderItem : NSObject
@property (nonatomic, copy) NSString *path, *name, *display, *kind;
@property (nonatomic, copy) NSString *app;   // an app's container folder (Applications): the .app inside -- shown and opened as that app
@property (nonatomic) BOOL dir, locked, package, alias;   // alias: a symbolic link (shown with a Mac alias arrow; a link to a folder opens it)
@property (nonatomic) BOOL cloud;            // an iCloud Drive file that is not downloaded: only its placeholder (.name.icloud) is here
@property (nonatomic, copy) NSString *stub;  // (that placeholder's path; `path` is where the file will be once downloaded)
@property (nonatomic) unsigned long long size;
@property (nonatomic, strong) NSDate *date;
@end
@implementation DMFinderItem
@end
static NSString *DMFinderKind(NSString *path, BOOL dir) {
    NSDictionary *la = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([la[NSFileType] isEqual:NSFileTypeSymbolicLink]) return dir ? @"Alias (folder)" : @"Alias";
    if (dir) return [path.pathExtension isEqualToString:@"app"] ? @"Application" : @"Folder";
    UTType *t = [UTType typeWithFilenameExtension:path.pathExtension];
    return t.localizedDescription ?: (path.pathExtension.length ? [path.pathExtension.uppercaseString stringByAppendingString:@" file"] : @"Document");
}
// An iCloud placeholder's real name: ".Report.pdf.icloud" -> "Report.pdf" (nil: not a placeholder).
static NSString *DMFinderStubName(NSString *name) {
    if (name.length > 8 && [name hasPrefix:@"."] && [name hasSuffix:@".icloud"]) return [name substringWithRange:NSMakeRange(1, name.length - 8)];
    return nil;
}
static NSArray<DMFinderItem *> *DMFinderList(NSString *path, BOOL hidden, NSError **err) {
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsPackageKey, NSURLIsSymbolicLinkKey];
    path = DMFinderNorm(path);
    BOOL icloud = DMFinderInICloud(path);   // (iCloud Drive: the placeholders of files not downloaded are hidden files -- shown by their real names)
    NSDirectoryEnumerationOptions o = hidden || icloud ? 0 : NSDirectoryEnumerationSkipsHiddenFiles;
    // (a folder reached through a link -- the sidebar's Jailbreak place /var/jb is one, an alias folder another -- is listed at the place it points
    //  to: the listing does not follow a link as its last part ("Not a directory"), and those folders showed "The iPad doesn't let Finder open
    //  this folder". The items keep the path the window shows; every rule looks at their real place anyway.)
    struct stat lst; char rb[PATH_MAX]; NSString *real = path;   // (realpath itself: DMFinderReal spells the jailbreak's files /var/jb again)
    if (lstat(path.fileSystemRepresentation, &lst) == 0 && S_ISLNK(lst.st_mode) && realpath(path.fileSystemRepresentation, rb)) real = [NSString stringWithUTF8String:rb] ?: path;
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:real] includingPropertiesForKeys:keys options:o error:err];
    if (!urls) return nil;
    NSString *rn = DMFinderReal(path);
    BOOL containers = [rn hasPrefix:@"/var/mobile/Containers/"] || [rn isEqualToString:@"/var/containers/Bundle/Application"];
    NSSet *hiddenApps = containers ? DMFinderHiddenApps() : nil;
    // (a drive's top folder: Windows' system folders are hidden files there, as a Mac's Finder shows the drive; dot files -- .Spotlight-V100,
    //  .Trashes, .fseventsd, "._" AppleDouble files -- are hidden files everywhere)
    BOOL driveTop = !hidden && [DMFinderDriveRoot(rn) isEqualToString:rn];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *u in urls) {
        if (driveTop && [@[@"System Volume Information", @"$RECYCLE.BIN", @"$Recycle.Bin", @"RECYCLER"] containsObject:u.lastPathComponent]) continue;
        NSString *stubName = icloud ? DMFinderStubName(u.lastPathComponent) : nil;
        if (icloud && !hidden && !stubName && [u.lastPathComponent hasPrefix:@"."]) continue;
        if (containers && u.lastPathComponent.length == 36 && hiddenApps.count && [hiddenApps containsObject:DMFinderContainerInfo(DMFinderNorm(u.path))[1]]) continue;
        NSDictionary *v = [u resourceValuesForKeys:keys error:nil];
        DMFinderItem *it = [DMFinderItem new];
        it.path = DMFinderNorm([path stringByAppendingPathComponent:u.lastPathComponent]); it.name = u.lastPathComponent;
        if (stubName) {   // (the placeholder is a small plist: the file's size is in it)
            NSDictionary *pl = [NSDictionary dictionaryWithContentsOfFile:it.path];
            it.cloud = YES; it.stub = it.path; it.name = stubName; it.path = [path stringByAppendingPathComponent:stubName];
            it.size = [pl[@"NSURLFileSizeKey"] unsignedLongLongValue]; it.date = v[NSURLContentModificationDateKey];
            it.kind = DMFinderKind(it.path, NO); it.display = it.name;
            [out addObject:it];
            continue;
        }
        it.dir = [v[NSURLIsDirectoryKey] boolValue];
        it.alias = [v[NSURLIsSymbolicLinkKey] boolValue];
        if (it.alias) { BOOL d = NO; if ([[NSFileManager defaultManager] fileExistsAtPath:u.path isDirectory:&d]) it.dir = d; }   // (follows the link)
        it.package = [v[NSURLIsPackageKey] boolValue];
        it.size = [v[NSURLFileSizeKey] unsignedLongLongValue];
        it.date = v[NSURLContentModificationDateKey];
        it.kind = DMFinderKind(it.path, it.dir);
        it.display = it.name;
        if (containers && it.dir && it.name.length == 36) { NSString *n = DMFinderContainerName(it.path); if (n) it.display = n; }
        if (it.dir && it.name.length == 36 && [rn isEqualToString:@"/var/containers/Bundle/Application"]) {   // (Applications: the app itself, as on a Mac)
            for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:it.path error:nil]) if ([f hasSuffix:@".app"]) { it.app = [it.path stringByAppendingPathComponent:f]; break; }
            if (it.app) it.kind = @"Application";
        }
        if (it.dir) it.locked = access(it.path.fileSystemRepresentation, R_OK | X_OK) != 0;
        [out addObject:it];
    }
    if ([path isEqualToString:kFinderTrash])   // (the Trash shows the connected drives' Trashes too, as a Mac's does; each item keeps its place on the drive)
        for (NSString *t in DMFinderDriveTrashes()) { if (!DMFinderDriveTrashIsSound(t)) continue; NSArray *more = DMFinderList(t, hidden, NULL); if (more) [out addObjectsFromArray:more]; }
    [out sortUsingComparator:^NSComparisonResult(DMFinderItem *a, DMFinderItem *b) { return [a.display localizedStandardCompare:b.display]; }];
    return out;
}
// One item from its path, as a listing makes it (a drag that starts outside a Finder window: the Dock's Downloads stack), or nil when it is gone.
static DMFinderItem *DMFinderItemFor(NSString *path) {
    path = DMFinderNorm(path);
    struct stat lst; if (!path.length || lstat(path.fileSystemRepresentation, &lst) != 0) return nil;
    NSURL *u = [NSURL fileURLWithPath:path];
    NSDictionary *v = [u resourceValuesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey, NSURLContentModificationDateKey, NSURLIsPackageKey] error:nil];
    DMFinderItem *it = [DMFinderItem new];
    it.path = path; it.name = path.lastPathComponent; it.display = it.name;
    it.alias = S_ISLNK(lst.st_mode);
    BOOL d = NO; it.dir = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&d] && d;   // (follows a link, as the listing does)
    it.package = [v[NSURLIsPackageKey] boolValue];
    it.size = [v[NSURLFileSizeKey] unsignedLongLongValue];
    it.date = v[NSURLContentModificationDateKey];
    it.kind = DMFinderKind(path, it.dir);
    if (it.dir) it.locked = access(path.fileSystemRepresentation, R_OK | X_OK) != 0;
    return it;
}
static UIImage *DMFinderIcon(DMFinderItem *it, CGFloat side);
static UIImage *DMFinderAppIcon(DMFinderItem *it, CGFloat side) {
    if (!it.app) return nil;
    DMFinderItem *a = [DMFinderItem new]; a.path = it.app; a.name = it.app.lastPathComponent; a.dir = YES;
    return DMFinderIcon(a, side);
}
static UIImage *DMFinderIcon(DMFinderItem *it, CGFloat side) {
    if (it.app) { UIImage *ai = DMFinderAppIcon(it, side); if (ai) return ai; }
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.8 weight:UIImageSymbolWeightRegular];
    if (it.dir && ![it.name hasSuffix:@".app"]) {
        UIImage *f = [UIImage systemImageNamed:it.locked ? @"lock.fill" : @"folder.fill" withConfiguration:cfg];
        return [f imageWithTintColor:it.locked ? [UIColor systemGrayColor] : [UIColor colorWithRed:0.33 green:0.66 blue:0.96 alpha:1] renderingMode:UIImageRenderingModeAlwaysOriginal];
    }
    if ([it.name hasSuffix:@".app"]) {   // an app: its own icon (read once per app and size: the Applications folder asked for each row, every scroll)
        static NSCache *appIcons; if (!appIcons) appIcons = [NSCache new];
        NSString *ck = [NSString stringWithFormat:@"%@|%.0f", it.path, side];
        UIImage *cached = [appIcons objectForKey:ck]; if (cached) return cached;
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[it.path stringByAppendingPathComponent:@"Info.plist"]];
        NSString *bid = info[@"CFBundleIdentifier"];
        SEL s = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if (bid && [UIImage respondsToSelector:s]) { UIImage *i = ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)([UIImage class], s, bid, 2, [UIScreen mainScreen].scale); if (i) { [appIcons setObject:i forKey:ck]; return i; } }
    }
    // (a file type's icon: the same for every file with that extension, made once per size -- a big folder asked for it per row)
    static NSCache *typeIcons; if (!typeIcons) typeIcons = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@|%.0f", it.path.pathExtension.lowercaseString, side];
    UIImage *hit = [typeIcons objectForKey:key]; if (hit) return hit;
    UIDocumentInteractionController *dic = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:it.path]];
    UIImage *best = nil;
    for (UIImage *i in dic.icons) if (!best || fabs(i.size.width - side) < fabs(best.size.width - side)) best = i;
    best = best ?: [UIImage systemImageNamed:@"doc" withConfiguration:cfg];
    if (best) [typeIcons setObject:best forKey:key];
    return best;
}
static NSCache *gFinderThumbs;
static BOOL DMFinderThumbable(DMFinderItem *it) {
    if (it.dir || it.cloud || it.size > 80 * 1024 * 1024) return NO;
    UTType *t = [UTType typeWithFilenameExtension:it.path.pathExtension];
    return [t conformsToType:UTTypeImage] || [t conformsToType:UTTypePDF];
}
static NSString *DMFinderThumbKey(DMFinderItem *it, CGFloat side) { return [NSString stringWithFormat:@"%@|%.0f|%.0f", it.path, it.date.timeIntervalSince1970, side]; }
// Thumbnails are made two at a time (a folder of big photos scrolled fast started dozens of decodes at once: threads and memory), and a row that
// scrolls away before its turn cancels its thumbnail (DMFinderThumbCancel, from the list's "did end displaying").
static NSOperationQueue *DMFinderThumbQueue(void) {
    static NSOperationQueue *q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = [NSOperationQueue new]; q.maxConcurrentOperationCount = 2; q.qualityOfService = NSQualityOfServiceUtility; q.name = @"com.besiktasliseba.finder.thumbs"; });
    return q;
}
static NSMutableDictionary<NSString *, NSOperation *> *gFinderThumbOps;   // (main thread only)
// The thumbnail if it is made already; otherwise it is made in the background and `done` runs on the main queue once it is there.
static UIImage *DMFinderThumb(DMFinderItem *it, CGFloat side, void (^done)(void)) {
    if (!DMFinderThumbable(it)) return nil;
    if (!gFinderThumbs) { gFinderThumbs = [NSCache new]; gFinderThumbs.countLimit = 400; }
    if (!gFinderThumbOps) gFinderThumbOps = [NSMutableDictionary dictionary];
    NSString *key = DMFinderThumbKey(it, side);
    id hit = [gFinderThumbs objectForKey:key];
    if ([hit isKindOfClass:[UIImage class]]) return hit;
    if (hit || gFinderThumbOps[key]) return nil;   // (being made, or could not be made)
    NSString *path = it.path; CGFloat px = side * [UIScreen mainScreen].scale, scale = [UIScreen mainScreen].scale;
    NSBlockOperation *op = [NSBlockOperation new];
    __weak NSBlockOperation *wop = op;
    [op addExecutionBlock:^{
        if (wop.isCancelled) return;
        UIImage *img = nil;
        if ([[UTType typeWithFilenameExtension:path.pathExtension] conformsToType:UTTypePDF]) {
            id doc = [[DMFinderClass(@"PDFDocument") alloc] initWithURL:[NSURL fileURLWithPath:path]];
            id pg = [doc pageCount] ? [doc pageAtIndex:0] : nil;
            img = pg ? [pg thumbnailOfSize:CGSizeMake(px, px) forBox:kPDFDisplayBoxCropBox] : nil;
        } else {
            CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache: @NO});
            CGImageRef cg = src ? CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @(px), (id)kCGImageSourceCreateThumbnailWithTransform: @YES}) : NULL;
            if (cg) { img = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp]; CGImageRelease(cg); }
            if (src) CFRelease(src);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [gFinderThumbOps removeObjectForKey:key];
            if (img) { [gFinderThumbs setObject:img forKey:key]; if (done) done(); }
            else [gFinderThumbs setObject:[NSNull null] forKey:key];   // (could not be made: not asked again)
        });
    }];
    gFinderThumbOps[key] = op;
    [DMFinderThumbQueue() addOperation:op];
    return nil;
}
static void DMFinderThumbCancel(DMFinderItem *it, CGFloat side) {
    if (!it || !gFinderThumbOps) return;
    NSString *key = DMFinderThumbKey(it, side);
    NSOperation *op = gFinderThumbOps[key];
    if (op && !op.isExecuting) { [op cancel]; [gFinderThumbOps removeObjectForKey:key]; }
}
static UIImage *DMFinderIconWithAlias(DMFinderItem *it, CGFloat side) {
    UIImage *base = DMFinderIcon(it, side);
    if (!it.alias || !base) return base;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:base.size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [base drawAtPoint:CGPointZero];
        CGFloat a = base.size.width * 0.38;
        UIImage *arrow = [[UIImage systemImageNamed:@"arrow.up.forward.square.fill"] imageWithTintColor:[UIColor blackColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        [[UIColor whiteColor] setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, base.size.height - a - 1, a, a) cornerRadius:a * 0.2] fill];
        [arrow drawInRect:CGRectMake(1, base.size.height - a - 1, a, a)];
    }];
}
// The list's columns for its width, like a Mac's list view keeping Name and dropping the others that no longer fit: x of Date, Size, Kind
// (a negative x: that column is hidden) and the Name column's width.
typedef struct { CGFloat date, size, kind, nameW; } DMFinderCols;
static DMFinderCols DMFinderColumns(CGFloat w) {
    DMFinderCols c = { -1, -1, -1, w - 52.0 };
    CGFloat right = w - 4.0;
    if (w >= 300) { c.kind = right - 86.0; right = c.kind; }
    if (w >= 360) { c.size = right - 64.0; right = c.size; }
    if (w >= 460) { c.date = right - 176.0; right = c.date; }
    c.nameW = right - 44.0 - 6.0;
    return c;
}
static NSString *DMFinderSize(DMFinderItem *it) { return it.dir ? @"--" : [NSByteCountFormatter stringFromByteCount:(long long)it.size countStyle:NSByteCountFormatterCountStyleFile]; }
static NSString *DMFinderDate(NSDate *d) {
    static NSDateFormatter *f; if (!f) { f = [NSDateFormatter new]; f.dateStyle = NSDateFormatterMediumStyle; f.timeStyle = NSDateFormatterShortStyle; f.doesRelativeDateFormatting = YES; }
    return d ? [f stringFromDate:d] : @"--";
}
// Taken, also by a link that points nowhere (fileExistsAtPath follows links: a dangling link's name looked free and the move then failed).
static BOOL DMFinderTaken(NSString *p) { struct stat st; return lstat(p.fileSystemRepresentation, &st) == 0; }
// A name split the Mac way for "name copy.ext": a folder keeps its dots ("Photos.2024" -> "Photos.2024 2"; packages like .app split);
// double extensions stay whole ("archive.tar.gz" -> "archive copy.tar.gz").
static void DMFinderSplitName(NSString *name, BOOL dir, NSString **base, NSString **ext) {
    static NSSet *packages, *inner;
    if (!packages) { packages = [NSSet setWithArray:@[@"app", @"appex", @"bundle", @"framework", @"plugin", @"pages", @"numbers", @"key", @"rtfd", @"playground"]];
                     inner = [NSSet setWithArray:@[@"tar"]]; }
    NSString *e = name.pathExtension.lowercaseString;
    if (!e.length || ([name hasPrefix:@"."] && [name rangeOfString:@"." options:0 range:NSMakeRange(1, name.length - 1)].location == NSNotFound) || (dir && ![packages containsObject:e])) { *base = name; *ext = @""; return; }
    NSString *b = name.stringByDeletingPathExtension, *x = name.pathExtension;
    if ([inner containsObject:b.pathExtension.lowercaseString] && b.stringByDeletingPathExtension.length) { x = [b.pathExtension stringByAppendingPathExtension:x]; b = b.stringByDeletingPathExtension; }
    *base = b; *ext = x;
}
// a free name next to the original: "name copy.ext", "name copy 2.ext"; "name 2" for the Trash
static NSString *DMFinderFreeName(NSString *dir, NSString *name, NSString *suffix) {
    struct stat st; BOOL isDir = lstat([dir stringByAppendingPathComponent:name].fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode);
    NSString *base = nil, *ext = nil; DMFinderSplitName(name, isDir, &base, &ext);
    NSString *try = name; int n = 1;
    while (DMFinderTaken([dir stringByAppendingPathComponent:try])) {
        NSString *b = n == 1 && suffix.length ? [base stringByAppendingFormat:@" %@", suffix] : [base stringByAppendingFormat:@" %@%d", suffix.length ? [suffix stringByAppendingString:@" "] : @"", n + (suffix.length ? 0 : 1)];
        if (n > 999) b = [base stringByAppendingFormat:@" %@", [NSUUID UUID].UUIDString];   // (never a taken name)
        try = ext.length ? [b stringByAppendingFormat:@".%@", ext] : b; n++;
    }
    return [dir stringByAppendingPathComponent:try];
}


// ---- Quick Look: our own window ------------------------------------------------------------------------------------------------------------
// Apple's QLPreviewController shows its content from another process (QuickLookUIService); inside SpringBoard's windows the touches for it went
// nowhere (a tap on its Done button reached no window at all), so it could not even be closed. Our own Quick Look is a native window, like a
// Mac's Quick Look window, that shows what a Finder needs in-process: pictures, text (plists -- binary ones too --, JSON, logs, scripts, code),
// PDFs (PDFKit), audio and video (AVKit). Anything else shows its icon, kind and size, with Share.
@class DMFinderWindow;
static DMFinderWindow *DMFinderFront(void);
@interface DMQuickLookWindow : DMNativeWindow
@property (nonatomic, copy) NSString *file;
@end
static BOOL DMQLIsText(NSString *path, UTType *t) {
    struct stat st; if (stat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return NO;   // (a FIFO or a device: never read)
    if ([t conformsToType:UTTypeText] || [t conformsToType:UTTypePropertyList] || [t conformsToType:UTTypeJSON] || [t conformsToType:UTTypeXML] || [t conformsToType:UTTypeSourceCode]) return YES;
    NSSet *ext = [NSSet setWithArray:@[@"log", @"conf", @"cfg", @"ini", @"sh", @"strings", @"md", @"yml", @"yaml", @"entitlements", @"control", @"list", @"txt", @"x", @"xm", @"h", @"m", @"c"]];
    if ([ext containsObject:path.pathExtension.lowercaseString]) return YES;
    if (path.pathExtension.length) return NO;
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];   // (no extension: text when small and valid UTF-8)
    if ([a fileSize] > 512 * 1024) return NO;
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d && [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] != nil;
}
// The text Quick Look shows for a file: at most 512 KB of it (a binary plist as its XML), read off the main thread.
static const NSUInteger kQLTextCap = 512 * 1024;
static NSString *DMQLText(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    BOOL cut = NO;
    if (data.length >= 6 && memcmp(data.bytes, "bplist", 6) == 0 && data.length <= 8 * 1024 * 1024) {   // (a binary plist: shown as its XML)
        id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
        NSData *xml = plist ? [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil] : nil;
        if (xml) data = xml;
    }
    if (data.length > kQLTextCap) { data = [data subdataWithRange:NSMakeRange(0, kQLTextCap)]; cut = YES; }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for (NSUInteger k = 1; !text && cut && k <= 3 && data.length > k; k++) text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, data.length - k)] encoding:NSUTF8StringEncoding];   // (cut inside a character)
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (cut && text) text = [text stringByAppendingString:@"\n\n… (only the first 512 KB are shown)"];
    return text ?: @"";
}
@implementation DMQuickLookWindow {
    AVPlayer *_player;
}
- (instancetype)initWithFile:(NSString *)path {
    CGRect d = DMNativeDesktop();
    CGFloat w = MIN(680.0, d.size.width - 60.0), h = MIN(560.0, d.size.height - 40.0);
    self = [super initWithTitle:path.lastPathComponent frame:CGRectMake(CGRectGetMidX(d) - w / 2.0, CGRectGetMidY(d) - h / 2.0, w, h)];
    if (!self) return nil;
    _file = [path copy];
    self.appName = @"Finder";
    self.minSize = CGSizeMake(300.0, 220.0);
    UIView *c = self.contentView;
    UTType *t = [UTType typeWithFilenameExtension:path.pathExtension];
    UIView *v = nil;
    if ([t conformsToType:UTTypeImage]) {
        UIImageView *iv = [UIImageView new]; iv.contentMode = UIViewContentModeScaleAspectFit; iv.backgroundColor = [UIColor systemBackgroundColor]; iv.accessibilityIgnoresInvertColors = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{   // (a thumbnail of at most 2048 px: a big photo never loads whole)
            CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
            CGImageRef cg = src ? CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES, (id)kCGImageSourceThumbnailMaxPixelSize: @2048, (id)kCGImageSourceCreateThumbnailWithTransform: @YES}) : NULL;
            UIImage *img = cg ? [UIImage imageWithCGImage:cg] : nil;
            if (cg) CGImageRelease(cg);
            if (src) CFRelease(src);
            dispatch_async(dispatch_get_main_queue(), ^{ iv.image = img; });
        });
        v = iv;
    } else if ([t conformsToType:UTTypePDF] && DMFinderClass(@"PDFView")) {   // (the document is opened in the background, then shown)
        PDFView *pv = [DMFinderClass(@"PDFView") new]; pv.autoScales = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            id doc = [[DMFinderClass(@"PDFDocument") alloc] initWithURL:[NSURL fileURLWithPath:path]];
            dispatch_async(dispatch_get_main_queue(), ^{ pv.document = doc; });
        });
        v = pv;
    } else if ([t conformsToType:UTTypeAudiovisualContent] && DMFinderClass(@"AVPlayerViewController")) {
        AVPlayerViewController *pvc = [DMFinderClass(@"AVPlayerViewController") new];
        _player = [DMFinderClass(@"AVPlayer") playerWithURL:[NSURL fileURLWithPath:path]];
        pvc.player = _player;
        objc_setAssociatedObject(self, @selector(initWithFile:), pvc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (kept alive with the window)
        v = pvc.view;
    } else if (DMQLIsText(path, t)) {   // (read in the background, at most 512 KB: a 4 MB log parsed on the main thread held SpringBoard)
        UITextView *tv = [UITextView new]; tv.editable = NO;
        tv.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
        tv.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
        tv.text = @"";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *text = DMQLText(path);
            dispatch_async(dispatch_get_main_queue(), ^{ tv.text = text; });
        });
        v = tv;
    } else {   // (no preview: the icon, the kind and the size, like a Mac's Quick Look for a file it can't show)
        UIView *box = [UIView new]; box.backgroundColor = [UIColor systemBackgroundColor];
        DMFinderItem *it = [DMFinderItem new]; it.path = path; it.name = path.lastPathComponent;
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        it.size = [a fileSize]; it.kind = DMFinderKind(path, NO);
        UIImageView *iv = [[UIImageView alloc] initWithImage:DMFinderIcon(it, 128.0)]; iv.contentMode = UIViewContentModeScaleAspectFit; iv.tag = 1; iv.accessibilityIgnoresInvertColors = YES;
        UILabel *l = [UILabel new]; l.numberOfLines = 0; l.textAlignment = NSTextAlignmentCenter; l.tag = 2;
        l.text = [NSString stringWithFormat:@"%@\n%@ – %@", it.name, it.kind, DMFinderSize(it)]; l.font = [UIFont systemFontOfSize:13.0];
        [box addSubview:iv]; [box addSubview:l];
        v = box;
    }
    v.tag = 100;
    [c addSubview:v];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *v = [self.contentView viewWithTag:100];
    v.frame = self.contentView.bounds;
    UIView *iv = [v viewWithTag:1], *l = [v viewWithTag:2];
    if (iv && l) { CGRect b = v.bounds; iv.frame = CGRectMake(CGRectGetMidX(b) - 64, CGRectGetMidY(b) - 110, 128, 128); l.frame = CGRectMake(20, CGRectGetMidY(b) + 30, b.size.width - 40, 60); }
}
- (void)close { [_player pause]; _player = nil; [super close]; }
- (BOOL)dm_handleKey:(UIKey *)key {   // (Space, Esc or Command-W close it again, as on a Mac)
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
    long c = (long)key.keyCode;
    if ((m == 0 && (c == UIKeyboardHIDUsageKeyboardSpacebar || c == UIKeyboardHIDUsageKeyboardEscape)) || (m == UIKeyModifierCommand && c == UIKeyboardHIDUsageKeyboardW)) {
        [self close];
        DMNativeWindow *f = (DMNativeWindow *)DMFinderFront(); if (f && !f.hidden) [f activate];
        return YES;
    }
    return NO;
}
@end
static void DMQuickLookOpen(NSString *path) {
    DM_FEATURE_MARK("finder-quick-look");
    for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMQuickLookWindow class]] && [((DMQuickLookWindow *)w).file isEqualToString:path]) { [w show]; return; }
    [[[DMQuickLookWindow alloc] initWithFile:path] show];
}

// ---- the window -----------------------------------------------------------------------------------------------------------------------------
@interface DMFinderWindow : DMNativeWindow <UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate,
                                             UIContextMenuInteractionDelegate, UISearchBarDelegate, UIGestureRecognizerDelegate, UITextFieldDelegate>
@property (nonatomic, copy) NSString *path;
- (void)go:(NSString *)path;
- (void)goBack; - (void)goForward; - (void)goUp;
- (void)emptyTrash;
- (DMFinderItem *)dm_selectedItem;
- (NSArray<DMFinderItem *> *)dm_selectedItems;              // the selection (every selected item, in the folder's order)
- (void)dm_goToFolder;                                      // (Go > Go to Folder…, Shift-Command-G)
- (void)dm_selectPathsWhenListed:(NSArray<NSString *> *)paths;   // (these items become the selection once the folder shows them)
- (void)dm_newFolder; - (void)dm_openSelected; - (void)dm_quickLookSelected; - (void)dm_infoSelected;
- (void)open:(DMFinderItem *)it; - (void)getInfo:(DMFinderItem *)it; - (void)newFolder; - (void)dm_newTextFile;   // (one item; New Folder in this window's folder)
- (void)dm_renameSelected; - (void)dm_duplicateSelected; - (void)dm_trashSelected;
- (void)dm_setIcons:(BOOL)icons; - (BOOL)dm_showsHidden; - (void)dm_toggleHidden;
- (NSArray<UIKeyCommand *> *)dm_keyCommands;
- (BOOL)dm_handleKey:(UIKey *)key;
- (void)refresh;
- (void)fileWork:(NSString *)what work:(NSError *(^)(void))work;
- (NSString *)dm_folderAtScreenPoint:(CGPoint)sp;
// File operations on any number of items (the selection, a drag, Undo): each follows the protected-path policy (DMFinderItemZone: a sheet asks
// or says no), runs on the file queue, can be undone (Cmd-Z), and refreshes every window showing a folder it changed.
- (void)dm_moveItems:(NSArray<NSString *> *)paths to:(NSString *)dir copy:(BOOL)copy;
- (void)dm_trashItems:(NSArray<NSString *> *)paths;
- (void)dm_duplicateItems:(NSArray<NSString *> *)paths;
- (void)dm_putBackItems:(NSArray<NSString *> *)paths;
- (void)dm_deleteItems:(NSArray<NSString *> *)paths;        // (in the Trash: Delete Immediately, asked first)
- (void)dm_renameItem:(NSString *)path to:(NSString *)name;
- (void)dm_pasteInto:(NSString *)dir;
- (BOOL)dm_canUndo; - (NSString *)dm_undoTitle; - (void)dm_undo;
- (BOOL)dm_canWriteHere; - (BOOL)dm_canChangeSelection;
- (void)dm_keyCopy:(id)k; - (void)dm_keyPaste:(id)k; - (void)dm_keyFind:(id)k;
#if DEBUG
- (void)dm_debugDo:(NSString *)spec;
#endif
@end
static NSString *DMFDFolderIn(DMFinderWindow *w, CGPoint sp) { return [w dm_folderAtScreenPoint:sp]; }
static DMFinderWindow *DMFinderOps(void);   // (Finder's file operations for drops outside a Finder window, see DMFinderOpsHost)
static BOOL DMTextWindowOpen(NSString *path, dispatch_block_t otherwise);   // (TextWindow.h: a plain text file opens in a TextEdit-style window)
static void DMFinderOpen(NSString *path, BOOL newWindow);

// ---- dragging files (our own drag, see -dm_dragPress:) --------------------------------------------------------------------------------------
// Targets: a Finder window (the folder under the point, else its own folder) -> the items are moved there, like a drag between folders on a Mac
// (copied with Option held, or when either side is a system location); an app's window -> the files are handed to the app: MacAppBridge in the
// app builds a real drag item and drives the app's own UIDropInteraction at the point (com.besiktasliseba.appbridge.tvtap.<hash> kind 6 over /
// 7 drop / 8 left; the app answers com.besiktasliseba.appbridge.report kind 10 with its proposal, kind 11 with the result).
//  - Exactly the window under the finger: the drop names the app's SCENE (its identifier, in the descriptor tmp/msb-drop.plist in the app's
//    container) and the app looks only in that scene -- with several windows of one app (Aerial keeps several Notes scenes in the foreground) a
//    drop once went into another, hidden note (M1 30 Sep).
//  - Nothing is copied while the finger only passes over apps: the descriptor names the files' types; the files are staged only when dropped,
//    off the main thread, as APFS clones (instant, independent of the original: a hard link let an app editing in place change the user's file)
//    in a folder of their own per drag (tmp/msb-drop/<token>), a real copy only across volumes and only up to a size cap. Every staged copy is
//    removed a minute after the app answered.
//  - A folder goes to an app as a zip, made only when it is dropped on an app (never for a move between Finder windows), after counting it
//    (a big one asks first, a huge one is refused), and deleted once staged.
//  - Every message carries a sequence number (bits 56-63: the app never runs one drop twice) and every drag a token (the app's answers name it:
//    an answer for an earlier drag can't finish this one, and an earlier drag's picture never stays behind).
// The picture on the finger shows a green "+" where the drop copies or is taken and a "no" sign where it is not.
@interface DMFDrag : NSObject
@property (nonatomic, strong) NSArray<DMFinderItem *> *items;
@property (nonatomic, copy) NSString *checkedDest;   // (the folder the checks below were made for, with checkedOption: the per-item checks run once per
@property (nonatomic) BOOL checkedOption, checkedInto;   //  target, not on every finger move -- thousands of items stuttered the drag, logic test 30 Sep)
@property (nonatomic) int checkedBadge;
@property (nonatomic, weak) DMFinderWindow *from;
@property (nonatomic) uint16_t token;
@property (nonatomic, strong) UIView *tile;
@property (nonatomic, strong) UIImageView *badge;
@property (nonatomic, copy) NSString *app, *scene, *describedFor;   // the app window under the finger (bundle, scene identifier)
@property (nonatomic) int proposal;
@property (nonatomic) CFTimeInterval queryAt, springAt;
@property (nonatomic) CGPoint springPoint;   // (where the finger came to rest on the folder: moving away more than 24 pt starts the second again)
@property (nonatomic, copy) void (^answered)(BOOL ok);
@property (nonatomic) BOOL finished, option;
@property (nonatomic) BOOL share;   // (Share…: the app puts it where its typing is -- the cursor, or the end of the text -- not at the drop point)
@property (atomic) BOOL cancelled;
@property (atomic, strong) NSFileCoordinator *zipper;
@property (nonatomic, copy) NSString *springFolder;
@property (nonatomic, weak) DMFinderWindow *springWindow;
@property (nonatomic, strong) NSMutableSet<NSString *> *containers;   // the app containers written into (cleaned after the answer)
@property (nonatomic, weak) UIView *hoverIcon;   // the Dock's Downloads stack under the finger (lit as a drop target), or nil
@property (nonatomic) CFTimeInterval iconAt;     // (since when it rests on that icon: a second opens the folder in a Finder window, spring-loaded)
@property (nonatomic) BOOL iconSprung, iconTimed;
@property (nonatomic) CGPoint grab;              // (a picture of the items themselves -- the desktop's icons --: where the finger holds it, from its centre)
@property (nonatomic) BOOL hasGrab;
@end
@implementation DMFDrag
@end
static DMFDrag *gFD;          // the drag under way, or the last one while it waits for its app's answer
static CGRect gFDFromRect;    // (the held row / icon on screen: the tile grows out of it instead of appearing under the finger)
static UIView *gFDCustomTile; static CGPoint gFDCustomGrab;   // (the next drag's picture, when its source draws its own: the desktop's icons, Desktop.h)
static uint8_t gFDSeq;
static uint16_t gFDTokens;
static const unsigned long long kFDCopyCap = 1024ULL * 1024 * 1024;        // a real copy (not a clone) to an app: at most 1 GB
static const unsigned long long kFDZipAsk = 200ULL * 1024 * 1024, kFDZipCap = 2048ULL * 1024 * 1024;   // a folder: asks above 200 MB, refused above 2 GB
static uint32_t DMFDHash(NSString *s) { uint32_t h = 2166136261u; for (const char *c = s.UTF8String; *c; c++) { h ^= (uint8_t)*c; h *= 16777619u; } return h; }
static NSString *DMBundleOfSceneID(id scene);
static NSString *DMFDSceneIdent(id scene) { NSString *i = nil; @try { i = [scene valueForKey:@"identifier"]; } @catch (id e) {} return [i isKindOfClass:[NSString class]] ? i : nil; }
static id DMFDSceneOfView(UIView *v) { id scene = nil; for (NSString *k in @[@"scene", @"_scene"]) { @try { scene = [v valueForKey:k]; } @catch (id e) {} if (scene) break; } return scene; }
// The app whose window is on top at a screen point, that point in the app's scene (points), and that scene's identifier: the topmost scene
// picture (a _UIScenePresentationView / scene layer host) under it, over every window but ours, the status bar, the keyboard and the gesture window.
static NSString *DMFDAppAt(CGPoint sp, CGPoint *scenePoint, NSString **sceneIdent) {
    NSArray *wins = [DMAllWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) { return a.windowLevel > b.windowLevel ? NSOrderedAscending : a.windowLevel < b.windowLevel ? NSOrderedDescending : NSOrderedSame; }];
    for (UIWindow *w in wins) {
        if (w.hidden || w.alpha < 0.01 || w == gNativeLayer) continue;
        NSString *wc = NSStringFromClass([w class]);
        if ([wc containsString:@"StatusBar"] || [wc containsString:@"TextEffects"] || [wc containsString:@"SystemGesture"] || [wc containsString:@"Keyboard"] || [wc hasPrefix:@"MSB"] || [wc containsString:@"FloatingDock"]) continue;
        CGPoint wp = [w convertPoint:sp fromCoordinateSpace:w.screen.coordinateSpace];
        if (![w pointInside:wp withEvent:nil]) continue;
        // (front-most first: a view's later subviews are above it)
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        UIView *found = nil;
        while (stack.count && !found) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if (v.hidden || v.alpha < 0.01) continue;
            NSString *cn = NSStringFromClass([v class]);
            if ([cn isEqualToString:@"_UIScenePresentationView"] || [cn isEqualToString:@"_UISceneLayerHostContainerView"]) {
                CGPoint p = [v convertPoint:sp fromCoordinateSpace:w.screen.coordinateSpace];
                if ([v pointInside:p withEvent:nil]) { found = v; if (scenePoint) *scenePoint = p; }
                continue;
            }
            for (UIView *c in v.subviews) [stack addObject:c];   // (pushed in order: the last subview is popped first)
        }
        if (!found) continue;
        id scene = DMFDSceneOfView(found);
        NSString *bundle = scene ? DMBundleOfSceneID(scene) : nil;
        if (bundle.length && ![bundle isEqualToString:@"com.apple.springboard"] && ![bundle containsString:@"keyboard"]) { if (sceneIdent) *sceneIdent = DMFDSceneIdent(scene); return bundle; }
    }
    return nil;
}
static BOOL DMFinderAppRefusesFiles(NSString *b) { return [b isEqualToString:@"com.apple.mobilesafari"]; }   // (see DMFinderAppTakesFiles)
static NSURL *DMFDContainer(NSString *bundle) {
    id proxy = DMProxyForBundle(bundle);
    id url = [proxy respondsToSelector:NSSelectorFromString(@"dataContainerURL")] ? [proxy valueForKey:@"dataContainerURL"] : nil;
    return [url isKindOfClass:[NSURL class]] ? url : nil;
}
static NSString *DMFDHandName(DMFinderItem *it) { return it.dir ? [it.name stringByAppendingPathExtension:@"zip"] : it.name; }
static NSString *DMFDUTI(DMFinderItem *it) {
    if (it.dir) return UTTypeZIP.identifier;
    NSString *real = DMFinderReal(it.path);
    UTType *t = [UTType typeWithFilenameExtension:real.pathExtension];
    return t.identifier ?: UTTypeData.identifier;
}
// The descriptor in the app's container: which drag (token), which of its windows (scene), and the files -- their names and types while the
// finger passes over (hover), their staged paths once dropped (ready).
static BOOL DMFDDescribe(DMFDrag *d, NSString *bundle, NSString *scene, NSArray<NSDictionary *> *staged) {
    NSURL *c = DMFDContainer(bundle);
    if (!c) { DMLog([NSString stringWithFormat:@"[finder] drag: no data container for %@", bundle]); return NO; }
    NSMutableArray *items = [NSMutableArray array];
    if (staged) [items addObjectsFromArray:staged];
    else for (DMFinderItem *it in d.items) [items addObject:@{@"name": DMFDHandName(it), @"uti": DMFDUTI(it)}];
    NSMutableDictionary *desc = [@{@"token": @(d.token), @"items": items, @"ready": @(staged != nil)} mutableCopy];
    if (scene.length) desc[@"scene"] = scene;
    if (d.share) desc[@"share"] = @YES;
    if (staged.count) { desc[@"path"] = staged[0][@"path"]; desc[@"name"] = staged[0][@"name"]; }   // (the single-file form older readers know)
    NSString *tmp = [c.path stringByAppendingPathComponent:@"tmp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil];
    if (![desc writeToFile:[tmp stringByAppendingPathComponent:@"msb-drop.plist"] atomically:YES]) { DMLog([NSString stringWithFormat:@"[finder] drag: could not write the descriptor for %@", bundle]); return NO; }
    if (!d.containers) d.containers = [NSMutableSet set];
    [d.containers addObject:c.path];
    d.describedFor = [NSString stringWithFormat:@"%@|%@|%d", bundle, scene ?: @"", staged != nil];
    return YES;
}
static void DMFDSend(NSString *bundle, CGPoint p, int kind) {
    char name[80]; snprintf(name, sizeof name, "com.besiktasliseba.appbridge.tvtap.%08x", DMFDHash(bundle));
    int t = 0; if (notify_register_check(name, &t) != NOTIFY_STATUS_OK) return;
    uint64_t x = (uint64_t)MAX(0, MIN(0xFFFFFF, llround(p.x * 4))), y = (uint64_t)MAX(0, MIN(0xFFFFFF, llround(p.y * 4)));
    gFDSeq = (uint8_t)(gFDSeq % 255 + 1);   // (never 0: 0 means "no sequence number" to the app)
    notify_set_state(t, x | (y << 24) | ((uint64_t)kind << 48) | ((uint64_t)gFDSeq << 56)); notify_post(name); notify_cancel(t);
}
static void DMFDBadge(DMFDrag *d, int proposal) {   // -1 none, 0/1 no, 2 copy, 3 move
    NSString *sym = proposal >= 2 ? @"plus.circle.fill" : proposal >= 0 ? @"nosign" : nil;
    d.badge.hidden = !sym;
    if (sym) { d.badge.image = [UIImage systemImageNamed:sym]; d.badge.tintColor = proposal >= 2 ? [UIColor systemGreenColor] : [UIColor systemGrayColor]; }
}
static void DMFDWatchReports(void) {
    static int tok = 0; if (tok) return;
    notify_register_dispatch("com.besiktasliseba.appbridge.report", &tok, dispatch_get_main_queue(), ^(int t) {
        uint64_t st = 0; notify_get_state(t, &st);
        uint32_t hash = (uint32_t)(st >> 32), kind = (uint32_t)((st >> 24) & 0xFF), value = (uint32_t)(st & 0xFFFFFF);
        DMFDrag *d = gFD;
        if (!d || !d.app || hash != DMFDHash(d.app) || ((value >> 12) & 0xFFF) != d.token) return;   // (another drag's, or another app's answer)
        if (kind == 10) { d.proposal = (int)(value & 0xFF); DMFDBadge(d, d.proposal); }
        else if (kind == 11 && d.answered) { void (^a)(BOOL) = d.answered; d.answered = nil; a((value & 1) != 0); }
    });
}
// Where the picture rides: a drag from a Finder window in the native layer, as always (above the app windows while Finder is active); a drag that
// starts anywhere else -- the Dock's Downloads stack, the desktop -- in our menu window, above every window and the Dock (the native layer may be
// behind the apps then, just above the Home Screen). The menu window lets every touch through unless a menu's catch-all is in it.
@class DMFinderOpsHost;
static BOOL DMFDFromFinderWindow(DMFDrag *d) { return d.from && ![d.from isKindOfClass:NSClassFromString(@"DMFinderOpsHost")]; }
// The menu window takes touches only through its own catch-all (DMMenuWindowHitTest), but for the render server a touch over it is SpringBoard's
// while its layer is flagged to hit-test as opaque (DMMakeOverlay sets that for a menu, and it stayed set): with the picture up, taps meant for
// the apps below went to SpringBoard -- up to ~2 s after a hand-over, while the picture waited for the app's answer. So for a picture the flag is
// cleared (the next menu sets it again), the picture itself is never hit-tested, and it leaves the menu window the moment it is dropped.
static void DMFDHitTestsOpaque(CALayer *layer, BOOL opaque) {
    SEL s = NSSelectorFromString(@"setHitTestsAsOpaque:");
    if ([layer respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(layer, s, opaque);
}
static UIView *DMFDTileHost(DMFDrag *d) {
    if (DMFDFromFinderWindow(d)) return gNativeRotator;
    UIView *host = DMMenuHost();
    if (host && gMenuWindow.hidden) gMenuWindow.hidden = NO;
    if (!gOverlay) DMFDHitTestsOpaque(gMenuWindow.layer, NO);
    return host;
}
static void DMFDNoTouches(UIView *tile) {   // (the picture: no hit testing of its own, in UIKit or in the render server)
    tile.userInteractionEnabled = NO;
    SEL s = NSSelectorFromString(@"setAllowsHitTesting:");
    if ([tile.layer respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(tile.layer, s, NO);
    DMFDHitTestsOpaque(tile.layer, NO);
}
// The dropped picture leaves the menu window at once (a hand-over to an app goes on without it): the window is hidden again unless a menu is in it.
static void DMFDReleasePicture(DMFDrag *d) {
    UIView *tile = d.tile;
    if (!tile || tile.window != gMenuWindow) return;
    d.tile = nil; d.badge = nil;
    [UIView animateWithDuration:0.15 animations:^{ tile.alpha = 0; tile.transform = CGAffineTransformMakeScale(0.6, 0.6); } completion:^(BOOL f) { [tile removeFromSuperview]; }];
    if (!gOverlay && gMenuWindow) gMenuWindow.hidden = YES;
    DMLog(@"[finder] drop: the picture leaves the menu window at once (the window is hidden again)");
}
static CGPoint DMFDHostPoint(UIView *host, CGPoint sp) {
    if (host == gMenuRotator) return sp;   // (its space is the screen's, see DMMenuHost)
    return [host convertPoint:sp fromCoordinateSpace:(host.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
}
static void DMFDPlaceTile(DMFDrag *d, CGPoint sp) {
    UIView *host = d.tile.superview;
    if (!d.tile || !host) return;
    CGPoint p = DMFDHostPoint(host, sp);
    CGSize t = d.tile.bounds.size, b = host.bounds.size;
    CGFloat x = p.x + t.width / 2.0 - 16.0, y = p.y + t.height / 2.0 - 16.0;
    if (d.hasGrab) { x = p.x - d.grab.x; y = p.y - d.grab.y; }
    if (b.width > t.width + 8.0) x = MIN(x, b.width - t.width / 2.0 - 4.0);   // (kept on the screen: at the Dock's right end -- the Downloads stack -- it was cut off)
    if (b.height > t.height + 8.0) y = MIN(y, b.height - t.height / 2.0 - 4.0);
    d.tile.center = CGPointMake(x, y);
}
// The Dock's Downloads stack as a drop target (dock/Downloads.m's icon, found by its class like Finder's own Dock icon): its view when the point
// is on it and it takes drops (it names its folder), else nil.
static UIView *DMFDDownloadsIconAt(CGPoint sp) {
    Class c = NSClassFromString(@"DMDownloadsIconView");
    if (!c || ![c instancesRespondToSelector:NSSelectorFromString(@"dm_dropFolder")]) return nil;
    for (UIWindow *w in DMAllWindows()) {
        if (w.hidden || w.alpha < 0.01 || ![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if (v.hidden || v.alpha < 0.01) continue;
            if ([v isKindOfClass:c]) {
                CGRect r = CGRectInset([v convertRect:v.bounds toCoordinateSpace:w.screen.coordinateSpace], -4.0, -4.0);
                return CGRectContainsPoint(r, sp) ? v : nil;
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return nil;
}
static NSString *DMFDIconFolder(UIView *icon) {
    NSString *f = nil;
    @try { f = ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"dm_dropFolder")); } @catch (NSException *e) {}
    return [f isKindOfClass:[NSString class]] && f.length ? f : nil;
}
static void DMFDIconHover(DMFDrag *d, UIView *icon) {   // (the stack lights up while a drag is over it, like a Mac's Dock folder)
    if (d.hoverIcon == icon) return;
    UIView *was = d.hoverIcon;
    SEL lit = NSSelectorFromString(@"dm_setDropHover:");
    if (was && [was respondsToSelector:lit]) ((void (*)(id, SEL, BOOL))objc_msgSend)(was, lit, NO);
    d.hoverIcon = icon; d.iconAt = CACurrentMediaTime(); d.iconSprung = NO; d.iconTimed = NO;
    if (icon && [icon respondsToSelector:lit]) ((void (*)(id, SEL, BOOL))objc_msgSend)(icon, lit, YES);
}
// Staged copies are removed a minute after the app answered (it may still be loading the file then); anything a respring left behind goes at
// the next start (DMFDSweep).
static void DMFDCleanLater(DMFDrag *d) {
    NSSet *containers = [d.containers copy]; uint16_t token = d.token;
    if (!containers.count) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *c in containers) {
            NSString *dir = [c stringByAppendingPathComponent:@"tmp/msb-drop"];
            [fm removeItemAtPath:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%u", token]] error:nil];
            if (![fm contentsOfDirectoryAtPath:dir error:nil].count) [fm removeItemAtPath:dir error:nil];
            NSString *plist = [c stringByAppendingPathComponent:@"tmp/msb-drop.plist"];
            if ([[NSDictionary dictionaryWithContentsOfFile:plist][@"token"] unsignedIntValue] == token) [fm removeItemAtPath:plist error:nil];
        }
    });
}
static void DMFDSweep(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager]; NSString *root = @"/var/mobile/Containers/Data/Application"; int n = 0;
        for (NSString *u in [fm contentsOfDirectoryAtPath:root error:nil]) {
            NSString *tmp = [[root stringByAppendingPathComponent:u] stringByAppendingPathComponent:@"tmp"];
            if ([fm removeItemAtPath:[tmp stringByAppendingPathComponent:@"msb-drop"] error:nil]) n++;
            [fm removeItemAtPath:[tmp stringByAppendingPathComponent:@"msb-drop.plist"] error:nil];
        }
        [fm removeItemAtPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"msb-finder-drag"] error:nil];
        if (n) DMLog([NSString stringWithFormat:@"[finder] drag: %d staged folders left from before were removed", n]);
    });
}
static void DMFDFinish(DMFDrag *d, BOOL ok) {
    if (!d || d.finished) return;
    d.finished = YES; d.cancelled = YES; [d.zipper cancel];
    DMFDIconHover(d, nil);
    UIView *tile = d.tile; d.tile = nil; d.badge = nil;
    BOOL inMenuWindow = tile.window && tile.window == gMenuWindow;
    [UIView animateWithDuration:ok ? 0.18 : 0.25 animations:^{ tile.alpha = 0; tile.transform = CGAffineTransformMakeScale(ok ? 0.4 : 0.8, ok ? 0.4 : 0.8); } completion:^(BOOL f) {
        [tile removeFromSuperview];
        if (inMenuWindow && !gOverlay && gMenuWindow && !(gFD && gFD.tile.window == gMenuWindow)) gMenuWindow.hidden = YES;   // (shown for the picture only: hidden again, as after a menu)
    }];
    d.answered = nil;
    DMFDCleanLater(d);
    if (gFD == d) gFD = nil;
}
static void DMFDBusy(DMFDrag *d, NSString *what) {   // (the picture waits at the drop point while the files are made ready)
    UILabel *l = [d.tile viewWithTag:2]; if (what && l) l.text = what;
    if (d.tile && ![d.tile viewWithTag:3]) {
        UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        sp.tag = 3; sp.center = CGPointMake(d.tile.bounds.size.width - 18.0, d.tile.bounds.size.height / 2.0); [sp startAnimating]; [d.tile addSubview:sp];
    }
}
static void DMFinderDragBegin(DMFinderWindow *from, NSArray<DMFinderItem *> *items, CGPoint sp) {
    DM_FEATURE_MARK("finder-drag");
    DMFDWatchReports();
    if (gFD) DMFDFinish(gFD, NO);   // (an earlier drag still waiting for its app: its picture goes now, it never stays behind)
    DMFDrag *d = [DMFDrag new];
    d.items = items; d.from = from; d.proposal = -1;
    gFDTokens = (uint16_t)(gFDTokens % 4095 + 1); d.token = gFDTokens;
    gFD = d;
    DMFinderItem *it = items.firstObject;
    UIView *custom = gFDCustomTile; gFDCustomTile = nil;
    UIView *tile = custom ?: [[UIView alloc] initWithFrame:CGRectMake(0, 0, 210, 44)];
    tile.userInteractionEnabled = NO;
    if (custom) {   // (the source's own picture -- the desktop's icons, lifted where they are: no growing in, it is already under the finger)
        d.grab = gFDCustomGrab; d.hasGrab = YES;
        d.badge = [[UIImageView alloc] initWithFrame:CGRectMake(-8, -8, 22, 22)]; d.badge.hidden = YES; [tile addSubview:d.badge];
        d.tile = tile;
        [DMFDTileHost(d) addSubview:tile];
        DMFDNoTouches(tile);
        DMFDPlaceTile(d, sp);
        gFDFromRect = CGRectZero;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        DMLog([NSString stringWithFormat:@"[finder] our drag began: %@ (%@), %lu item(s), token %u, its own picture", it.kind, it.dir ? @"folder" : @"file", (unsigned long)items.count, d.token]);
        return;
    }
    tile.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.85];
    tile.layer.cornerRadius = 10.0; tile.layer.borderWidth = 0.5; tile.layer.borderColor = [UIColor separatorColor].CGColor;
    tile.layer.shadowColor = [UIColor blackColor].CGColor; tile.layer.shadowOpacity = 0.3; tile.layer.shadowRadius = 10; tile.layer.shadowOffset = CGSizeMake(0, 4);
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 6, 32, 32)]; icon.contentMode = UIViewContentModeScaleAspectFit; icon.accessibilityIgnoresInvertColors = YES;
    icon.image = DMFinderIcon(it, 32.0); [tile addSubview:icon];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(46, 0, 156, 44)]; l.tag = 2;
    l.text = items.count > 1 ? [NSString stringWithFormat:@"%lu items", (unsigned long)items.count] : it.display;
    l.font = [UIFont systemFontOfSize:13.0]; l.lineBreakMode = NSLineBreakByTruncatingMiddle; [tile addSubview:l];
    d.badge = [[UIImageView alloc] initWithFrame:CGRectMake(-8, -8, 22, 22)]; d.badge.hidden = YES; [tile addSubview:d.badge];
    d.tile = tile;
    UIView *host = DMFDTileHost(d);
    [host addSubview:tile];
    DMFDNoTouches(tile);
    DMFDPlaceTile(d, sp);
    if (!CGRectIsEmpty(gFDFromRect) && host) {   // (it comes out of the held row / icon and glides to the finger: the pick-up is seen, not guessed)
        CGPoint f = DMFDHostPoint(host, CGPointMake(CGRectGetMidX(gFDFromRect), CGRectGetMidY(gFDFromRect)));
        CGFloat k = MAX(0.5, MIN(1.3, gFDFromRect.size.height / tile.bounds.size.height));
        tile.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(f.x - tile.center.x, f.y - tile.center.y), k, k);
        tile.alpha = 0.6;
        if (MSBReduceMotion()) { tile.transform = CGAffineTransformIdentity; tile.alpha = 0; }   // (Reduce Motion: it fades in under the finger, no glide -- 1.3.3, audit L-5)
        MSBAnimate(0.28, 0, 0.8, UIViewAnimationOptionAllowUserInteraction, ^{ tile.transform = CGAffineTransformIdentity; tile.alpha = 1; }, nil);
    } else {
        tile.transform = MSBReduceMotion() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.6, 0.6); tile.alpha = 0;
        [UIView animateWithDuration:0.15 animations:^{ tile.transform = CGAffineTransformIdentity; tile.alpha = 1; }];
    }
    gFDFromRect = CGRectZero;
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [haptic impactOccurred];
    DMLog([NSString stringWithFormat:@"[finder] our drag began: %@ (%@), %lu item(s), token %u", it.kind, it.dir ? @"folder" : @"file", (unsigned long)items.count, d.token]);
}
// The Finder window under a screen point (front-most first), or nil.
static DMFinderWindow *DMFDFinderAt(CGPoint sp) {
    for (DMNativeWindow *w in [gNativeWindows reverseObjectEnumerator]) {
        if (w.hidden || ![w isKindOfClass:NSClassFromString(@"DMFinderWindow")]) continue;
        CGPoint p = [w convertPoint:sp fromCoordinateSpace:w.window.screen.coordinateSpace];
        if ([w pointInside:p withEvent:nil]) return (DMFinderWindow *)w;
    }
    return nil;
}
// A Finder-to-Finder drop copies instead of moving with Option held, or when an item is outside the user's own places (read only there: it is
// copied out, never moved). Onto the Trash it is always Move to Trash.
static BOOL DMFDCopies(DMFDrag *d, NSString *dest) {
    if ([DMFinderReal(dest) isEqualToString:kFinderTrash]) return NO;
    if (d.option) return YES;
    for (DMFinderItem *it in d.items) if (!DMFinderCanChange(it.path)) return YES;
    // (to another volume -- the iPad and a drive, or two drives --: a copy, as a Mac's Finder does; the original stays where it was)
    NSString *to = DMFinderDriveRoot(DMFinderReal(dest)) ?: @"";
    for (DMFinderItem *it in d.items) if (![(DMFinderDriveRoot(DMFinderRealItem(it.path)) ?: @"") isEqualToString:to]) return YES;
    return NO;
}
static BOOL DMFDMayDrop(DMFDrag *d, NSString *dest, BOOL copy) {   // (the policy, for the badge: into the user's places only; onto the Trash only what may be trashed)
    if ([DMFinderReal(dest) isEqualToString:kFinderTrash]) { for (DMFinderItem *it in d.items) if (!DMFinderCanChange(it.path)) return NO; return !copy; }
    for (DMFinderItem *it in d.items) if (it.cloud) return NO;
    return DMFinderCanWriteInto(dest);
}
static BOOL DMFDNothingToDo(DMFDrag *d, NSString *dest, BOOL copy) {   // every item already there (a move), or into itself
    NSString *rd = DMFinderReal(dest);
    for (DMFinderItem *it in d.items) {
        if (DMFinderIntoItself(it.path, dest)) return YES;
        if (copy || ![DMFinderReal(it.path.stringByDeletingLastPathComponent) isEqualToString:rd]) return NO;
    }
    return YES;
}
// The badge for a drop into that folder (checked once per folder and Option state); YES when an item would go into itself.
static BOOL DMFDCheckDest(DMFDrag *d, NSString *dest, BOOL option) {
    if (![d.checkedDest isEqualToString:dest ?: @""] || d.checkedOption != option) {
        BOOL copy = DMFDCopies(d, dest), none = DMFDNothingToDo(d, dest, copy), into = NO;
        for (DMFinderItem *it in d.items) if (DMFinderIntoItself(it.path, dest)) { into = YES; break; }
        d.checkedDest = dest ?: @""; d.checkedOption = option; d.checkedInto = into;
        d.checkedBadge = into || !DMFDMayDrop(d, dest, copy) ? 0 : none ? -1 : copy ? 2 : -1;
    }
    DMFDBadge(d, d.checkedBadge);
    return d.checkedInto;
}
// The desktop (Desktop.h) as a drop target: the folder a drop at that screen point goes into -- a folder icon there (*icon), or the desktop's
// own folder -- or nil where the desktop isn't under the point; and the drop itself (repositions icons moved on the desktop, places dropped ones).
static NSString *DMDesktopFolderAt(CGPoint sp, UIView **icon);
static void DMDesktopTakeDrop(DMFDrag *d, CGPoint sp, NSString *dest, BOOL ontoFolderIcon);
// Resting a second on a folder outside a Finder window -- the Dock's Downloads stack, a folder icon on the desktop -- opens it in a new Finder
// window (spring-loaded), and the drag goes on into it. Timed, not only checked on the next move: a finger resting still sends no more moves.
static void DMFDSpringIcon(DMFDrag *d, UIView *icon, NSString *dir, NSString *what) {
    if (d.iconSprung || d.iconTimed || !icon || !dir.length) return;
    d.iconTimed = YES;
    CFTimeInterval at = d.iconAt; __weak DMFDrag *wd = d; __weak UIView *wicon = icon;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DMFDrag *dd = wd;
        if (!dd || dd.finished || dd != gFD || dd.iconSprung || dd.iconAt != at || !wicon || dd.hoverIcon != wicon) return;
        dd.iconSprung = YES;
        DMLog([NSString stringWithFormat:@"[finder] drag: rested on %@ -- its folder opens in a Finder window (spring-loaded)", what]);
        DMFinderOpen(dir, YES);
        if (dd.tile.superview) [dd.tile.superview bringSubviewToFront:dd.tile];   // (the new window must not cover the picture)
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    });
}
__attribute__((noinline)) static void DMFinderDragMove(CGPoint sp, BOOL option) {   // (kept a symbol of its own: the crash guard names it)
    DMFDrag *d = gFD;
    if (!d || d.finished || !d.tile) return;
    d.option = option;
    DMFDPlaceTile(d, sp);
    // (over the Dock's Downloads stack: its folder takes it, like a folder in the Dock on a Mac; resting on it a second opens that folder)
    UIView *icon = DMFDDownloadsIconAt(sp);
    NSString *iconDir = icon ? DMFDIconFolder(icon) : nil;
    if (iconDir) {
        DM_FEATURE_MARK("finder-drag-downloads-stack");
        DMFDIconHover(d, icon);
        if (d.app) { DMFDSend(d.app, CGPointZero, 8); d.app = nil; d.scene = nil; }
        d.springFolder = nil;
        DMFDCheckDest(d, iconDir, option);
        DMFDSpringIcon(d, icon, iconDir, @"the Downloads stack");
        return;
    }
    DMFinderWindow *fw = DMFDFinderAt(sp);
    if (fw) {   // (over a Finder window: its folder takes it, unless that is where the items already are, or an item itself)
        DMFDIconHover(d, nil);
        NSString *dest = DMFDFolderIn(fw, sp);
        if (d.app) { DMFDSend(d.app, CGPointZero, 8); d.app = nil; d.scene = nil; }
        BOOL into = DMFDCheckDest(d, dest, option);
        // spring-loaded folders: RESTING on a folder for a second opens it in that window, as on a Mac (a slow pass over a row or a sidebar place
        // opened it: the finger has to stay within 24 pt); the Trash place never opens (it is a drop target)
        if (!into && dest.length && ![DMFinderNorm(dest) isEqualToString:DMFinderNorm(fw.path)] && ![DMFinderReal(dest) isEqualToString:kFinderTrash]) {
            void (^spring)(void) = ^{
                DMLog([NSString stringWithFormat:@"[finder] drag: spring-loaded folder opened (%@)", dest.lastPathComponent]);
                d.springFolder = nil;
                [fw go:dest];
                [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
            };
            if (![dest isEqualToString:d.springFolder] || d.springWindow != fw || hypot(sp.x - d.springPoint.x, sp.y - d.springPoint.y) > 24.0) {
                d.springFolder = dest; d.springWindow = fw; d.springAt = CACurrentMediaTime(); d.springPoint = sp;
                // (a finger or pointer resting perfectly still sends no more moves: the second is also timed, not only checked on the next move --
                //  a still rest on a folder never opened it, iPad 2 30 Sep)
                CFTimeInterval at = d.springAt; __weak DMFDrag *wd = d; __weak DMFinderWindow *wfw = fw;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    DMFDrag *dd = wd;
                    if (dd && !dd.finished && dd == gFD && dd.springAt == at && [dd.springFolder isEqualToString:dest] && dd.springWindow == wfw && wfw) spring();
                });
            }
            else if (CACurrentMediaTime() - d.springAt > 1.0) spring();
        } else d.springFolder = nil;
        return;
    }
    d.springFolder = nil;
    CGPoint scene = CGPointZero; NSString *sceneId = nil;
    NSString *app = DMFDAppAt(sp, &scene, &sceneId);
    // (no app window there: the desktop, when the Home Screen's first page is under the point -- a folder icon on it takes the drop, else the
    //  desktop's own folder; icons already on the desktop just move)
    UIView *deskIcon = nil;
    NSString *deskDir = app ? nil : DMDesktopFolderAt(sp, &deskIcon);
    DMFDIconHover(d, deskIcon);
    if (deskDir) {
        if (d.app) { DMFDSend(d.app, CGPointZero, 8); d.app = nil; d.scene = nil; }
        DMFDCheckDest(d, deskDir, option);
        if (deskIcon) DMFDSpringIcon(d, deskIcon, deskDir, @"a folder on the desktop");
        return;
    }
    d.checkedDest = nil;
    if (app && DMFinderAppRefusesFiles(app)) app = nil;
    if (![app ?: @"" isEqualToString:d.app ?: @""] || ![sceneId ?: @"" isEqualToString:d.scene ?: @""]) {
        if (d.app) DMFDSend(d.app, CGPointZero, 8);
        d.app = app; d.scene = sceneId; d.proposal = -1; DMFDBadge(d, app ? 0 : -1);
    }
    if (!app || CACurrentMediaTime() - d.queryAt < 0.08) return;
    d.queryAt = CACurrentMediaTime();
    NSString *key = [NSString stringWithFormat:@"%@|%@|0", app, sceneId ?: @""];
    if ([d.describedFor isEqualToString:[key stringByAppendingString:@"|x"]]) return;   // (this app can't be handed anything -- no data container: asked once)
    if (![d.describedFor isEqualToString:key] && !DMFDDescribe(d, app, sceneId, nil)) { d.describedFor = [key stringByAppendingString:@"|x"]; DMFDBadge(d, 0); return; }
    DMFDSend(app, scene, 6);
}
// A folder's size, counted up to `stop` bytes (a huge tree is not walked to the end): -1 when it can't be read.
static long long DMFDFolderSize(NSString *path, unsigned long long stop) {
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:path] includingPropertiesForKeys:@[NSURLFileSizeKey] options:0 errorHandler:nil];
    if (!en) return -1;
    unsigned long long total = 0;
    for (NSURL *u in en) { NSNumber *n = nil; [u getResourceValue:&n forKey:NSURLFileSizeKey error:nil]; total += n.unsignedLongLongValue; if (total > stop) break; }
    return (long long)total;
}
static dispatch_queue_t DMFDStageQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.finder.stage", DISPATCH_QUEUE_SERIAL); });
    return q;
}
// One item into the app's container (on the stage queue): an APFS clone, else (another volume) a real copy up to the cap. A folder: zipped
// first, in SpringBoard's tmp, the zip removed once staged. Returns the descriptor entry, or nil with *why.
static NSDictionary *DMFDStageItem(DMFDrag *d, DMFinderItem *it, NSString *dir, NSString **why) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = DMFinderReal(it.path), *zip = nil, *name = DMFDHandName(it);
    const unsigned long long reserve = 200ULL * 1024 * 1024;   // (the iPad is never filled up for a hand-over: a full disk upsets the whole system)
    if (it.dir) {
        unsigned long long room = DMFinderFreeSpace(NSTemporaryDirectory());
        long long size = DMFDFolderSize(src, room);
        if (size < 0 || (unsigned long long)size + reserve > room) { *why = [NSString stringWithFormat:@"There isn't enough free space to compress “%@”.", it.name]; return nil; }
        NSString *zdir = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"msb-finder-drag"] stringByAppendingPathComponent:[NSString stringWithFormat:@"%u", d.token]];
        [fm createDirectoryAtPath:zdir withIntermediateDirectories:YES attributes:nil error:nil];
        zip = [zdir stringByAppendingPathComponent:name];
        __block BOOL ok = NO; NSError *err = nil;
        NSFileCoordinator *fc = [[NSFileCoordinator alloc] initWithFilePresenter:nil]; d.zipper = fc;
        [fc coordinateReadingItemAtURL:[NSURL fileURLWithPath:src] options:NSFileCoordinatorReadingForUploading error:&err byAccessor:^(NSURL *z) {
            if (!d.cancelled) ok = [fm copyItemAtURL:z toURL:[NSURL fileURLWithPath:zip] error:nil]; }];
        d.zipper = nil;
        if (!ok || d.cancelled) { [fm removeItemAtPath:zdir error:nil]; *why = d.cancelled ? @"cancelled" : [NSString stringWithFormat:@"the folder could not be compressed (%@)", err.localizedDescription ?: @"?"]; return nil; }
        src = zip;
    }
    NSString *dst = [dir stringByAppendingPathComponent:name];
    BOOL ok = clonefile(src.fileSystemRepresentation, dst.fileSystemRepresentation, 0) == 0;
    if (!ok) {   // (another volume -- the jailbreak's files --, or no clone support: a real copy, within the cap)
        struct stat st; unsigned long long size = stat(src.fileSystemRepresentation, &st) == 0 ? (unsigned long long)st.st_size : 0;
        if (size > kFDCopyCap) *why = [NSString stringWithFormat:@"“%@” is too large to hand over (%@)", name, [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile]];
        else if (size + reserve > DMFinderFreeSpace(dir)) *why = [NSString stringWithFormat:@"There isn't enough free space to hand over “%@”.", name];
        else { NSError *e = nil; ok = [fm copyItemAtPath:src toPath:dst error:&e]; if (!ok) *why = e.localizedDescription ?: @"the copy failed"; }
    }
    if (zip) [fm removeItemAtPath:zip.stringByDeletingLastPathComponent error:nil];
    if (!ok) return nil;
    chmod(dst.fileSystemRepresentation, 0644);
    return @{@"path": dst, @"name": name, @"uti": DMFDUTI(it)};
}
// The drop on an app's window (a drag, or Share): the files are made ready off the main thread, then the app is told to drop them at the point
// in that scene. done(ok) runs once the app answered (NO: not taken, no answer, or nothing could be handed over).
static void DMFDHandOver(DMFDrag *d, NSString *bundle, NSString *scene, CGPoint pt, DMFinderWindow *w, NSTimeInterval wait, void (^done)(BOOL ok)) {
    d.app = bundle; d.scene = scene;
    DMFDReleasePicture(d);   // (independent of the app's answer: nothing of ours stays over the app)
    void (^fail)(NSString *) = ^(NSString *why) {   // (a sheet only for what the user can act on: too large, not downloaded; an app that takes no files just doesn't, as on a Mac)
        DMLog([NSString stringWithFormat:@"[finder] drop into %@: not handed over (%@)", bundle, why]);
        DMFDSend(bundle, CGPointZero, 8);
        if (why.length && ![why isEqualToString:@"cancelled"] && ![why hasPrefix:@"the app"]) [w sheetTitle:@"The item couldn't be handed over" message:why field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
        DMFDFinish(d, NO); if (done) done(NO);
    };
    for (DMFinderItem *it in d.items) if (it.cloud) { fail([NSString stringWithFormat:@"“%@” is in iCloud and not downloaded yet. Open it first to download it.", it.name]); return; }
    NSURL *c = DMFDContainer(bundle);
    if (!c) { fail(@"the app has no data container"); return; }
    NSString *dir = [c.path stringByAppendingPathComponent:[NSString stringWithFormat:@"tmp/msb-drop/%u", d.token]];
    if (!d.containers) d.containers = [NSMutableSet set];
    [d.containers addObject:c.path];
    BOOL folders = NO; for (DMFinderItem *it in d.items) if (it.dir) folders = YES;
    DMFDBusy(d, folders ? @"Compressing…" : nil);
    void (^stage)(void) = ^{
        dispatch_async(DMFDStageQueue(), ^{
            NSMutableArray *staged = [NSMutableArray array]; NSString *why = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            for (DMFinderItem *it in d.items) {
                if (d.cancelled) { why = @"cancelled"; break; }
                NSDictionary *e = DMFDStageItem(d, it, dir, &why);
                if (!e) break;
                [staged addObject:e];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (d.finished) return;
                if (staged.count < d.items.count) { fail(why ?: @"?"); return; }
                if (!DMFDDescribe(d, bundle, scene, staged)) { fail(@"the app's container can't be written"); return; }
                __block BOOL answered = NO; __weak DMFDrag *wd = d;
                d.answered = ^(BOOL ok) { answered = YES; DMLog([NSString stringWithFormat:@"[finder] drop into %@: %@", bundle, ok ? @"taken" : @"not taken"]); DMFDFinish(wd, ok); if (done) done(ok); };
                DMFDSend(bundle, pt, 7);
                DMLog([NSString stringWithFormat:@"[finder] drop into %@ (scene %@): %lu item(s) staged, token %u", bundle, scene.length ? @"named" : @"unknown", (unsigned long)staged.count, d.token]);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (no answer: the app has no MacAppBridge)
                    if (answered || d.finished) return;
                    DMLog([NSString stringWithFormat:@"[finder] drop into %@: no answer (the app is not reachable)", bundle]);
                    DMFDFinish(d, NO); if (done) done(NO);
                });
            });
        });
    };
    if (!folders) { stage(); return; }
    NSArray *paths = [d.items valueForKey:@"path"];
    dispatch_async(DMFDStageQueue(), ^{   // (a folder: counted first -- a big one asks, a huge one is refused)
        unsigned long long total = 0; BOOL unreadable = NO;
        for (NSString *p in paths) { BOOL isDir = NO; [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&isDir]; if (!isDir) continue;
                                     long long s = DMFDFolderSize(p, kFDZipCap + 1); if (s < 0) unreadable = YES; else total += (unsigned long long)s; }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (d.finished) return;
            NSString *size = [NSByteCountFormatter stringFromByteCount:(long long)total countStyle:NSByteCountFormatterCountStyleFile];
            if (unreadable) { fail(@"The folder can't be read."); return; }
            if (total > kFDZipCap) { fail([NSString stringWithFormat:@"The folder is too large to compress and hand over (more than %@).", [NSByteCountFormatter stringFromByteCount:(long long)kFDZipCap countStyle:NSByteCountFormatterCountStyleFile]]); return; }
            if (total <= kFDZipAsk) { stage(); return; }
            [w sheetTitle:[NSString stringWithFormat:@"Compress %@ to hand it over?", size] message:@"The folder is handed to the app as a zip file, made first." field:nil action:@"Compress" destructive:NO
                     then:^(NSString *t) { stage(); } cancel:^{ fail(@"cancelled"); }];
        });
    });
}
// A drop into a folder (a Finder window's, the Dock's Downloads stack, the desktop): moved there, or copied (Option, or from a read-only place),
// through `host`'s file operations -- the policy, Undo, and its sheets for what goes wrong.
static void DMFDDropInto(DMFDrag *d, NSString *dest, DMFinderWindow *host, NSString *where) {
    BOOL copy = DMFDCopies(d, dest);
    if (!dest.length || DMFDNothingToDo(d, dest, copy)) { DMLog(@"[finder] drop: nothing to do there (already in that folder, or into itself)"); DMFDFinish(d, NO); return; }
    if (!DMFDMayDrop(d, dest, copy)) { DMLog(@"[finder] drop: refused (the folder, or an item, is outside the user's places)"); DMFDFinish(d, NO); return; }   // (the "no" badge showed it: the picture just goes back)
    if (!host) { DMLog(@"[finder] drop: no Finder to do it"); DMFDFinish(d, NO); return; }
    DMLog([NSString stringWithFormat:@"[finder] drop: %@ into %@", copy ? @"copied" : @"moved", where]);
    DMFDFinish(d, YES);
    [host dm_moveItems:[d.items valueForKey:@"path"] to:dest copy:copy];
}
static void DMFinderDragEnd(CGPoint sp, BOOL drop, BOOL option) {
    DMFDrag *d = gFD;
    if (!d || d.finished || !d.tile || d.answered) return;
    d.option = option;
    if (!drop) { if (d.app) DMFDSend(d.app, CGPointZero, 8); DMFDFinish(d, NO); return; }
    UIView *icon = DMFDDownloadsIconAt(sp);
    NSString *iconDir = icon ? DMFDIconFolder(icon) : nil;
    if (iconDir) { DMFDDropInto(d, iconDir, DMFDFromFinderWindow(d) ? d.from : DMFinderOps(), @"the Dock's Downloads stack"); return; }
    DMFinderWindow *fw = DMFDFinderAt(sp);
    if (fw) { DMFDDropInto(d, DMFDFolderIn(fw, sp), fw, [NSString stringWithFormat:@"a Finder folder (%@)", fw.title]); return; }
    CGPoint scene = CGPointZero; NSString *sceneId = nil;
    NSString *app = DMFDAppAt(sp, &scene, &sceneId);
    if (!app) {   // (the desktop: a folder icon there, or the desktop itself)
        UIView *deskIcon = nil;
        NSString *deskDir = DMDesktopFolderAt(sp, &deskIcon);
        if (deskDir) { if (d.app) DMFDSend(d.app, CGPointZero, 8); DMDesktopTakeDrop(d, sp, deskDir, deskIcon != nil); return; }
    }
    if (app && DMFinderAppRefusesFiles(app)) { DMLog(@"[finder] drop: Safari doesn't take files (it would open them as a local page)"); app = nil; }
    if (!app) { DMLog(@"[finder] drop: nothing takes it here"); if (d.app) DMFDSend(d.app, CGPointZero, 8); DMFDFinish(d, NO); return; }
    if (d.app && (![d.app isEqualToString:app] || ![d.scene ?: @"" isEqualToString:sceneId ?: @""])) DMFDSend(d.app, CGPointZero, 8);
    DMFDHandOver(d, app, sceneId, scene, d.from, 2.0, nil);
}

// ---- Share (a Mac-style Share menu of our own) ----------------------------------------------------------------------------------------------
// The system share sheet cannot work from SpringBoard's windows (see the note at -getInfo:), so Share lists apps and hands the items to the chosen
// one the way a drag onto its window does: dropped in the middle of the app's window (the app opened first when it has none), through the app's
// own drop handling -- what the app then does with it is the app's own (Notes: into the open note).
static UIView *DMFDSceneViewOf(NSString *bundle, NSString **sceneIdent) {   // the app's front-most scene picture on screen (its window's content), or nil
    NSArray *wins = [DMAllWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) { return a.windowLevel > b.windowLevel ? NSOrderedAscending : a.windowLevel < b.windowLevel ? NSOrderedDescending : NSOrderedSame; }];
    for (UIWindow *w in wins) {
        if (w.hidden || w.alpha < 0.01 || w == gNativeLayer) continue;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if (v.hidden || v.alpha < 0.01) continue;
            NSString *cn = NSStringFromClass([v class]);
            if ([cn isEqualToString:@"_UIScenePresentationView"] || [cn isEqualToString:@"_UISceneLayerHostContainerView"]) {
                id scene = DMFDSceneOfView(v);
                if ([DMBundleOfSceneID(scene) isEqualToString:bundle] && v.bounds.size.width > 100) { if (sceneIdent) *sceneIdent = DMFDSceneIdent(scene); return v; }
                continue;
            }
            for (UIView *c in v.subviews) [stack addObject:c];   // (front-most first)
        }
    }
    return nil;
}
// Apps that take files: Notes, Mail, Messages and Files, and any app that says it opens documents (its Info.plist's document types / document
// browser). Share offered Clock, which can't take a file (iPad 2 30 Sep). Safari never: a file handed to it opened as a "local file" page it
// cannot show -- a drag over Safari's window is refused too (DMFinderAppRefusesFiles).
static BOOL DMFinderAppTakesFiles(NSString *b) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSNumber *known = cache[b]; if (known) return known.boolValue;
    BOOL yes = NO;
    if ([@[@"com.apple.mobilenotes", @"com.apple.mobilemail", @"com.apple.MobileSMS", @"com.apple.DocumentsApp"] containsObject:b]) yes = YES;
    else if (!DMFinderAppRefusesFiles(b)) {
        id url = nil; @try { url = [DMProxyForBundle(b) valueForKey:@"bundleURL"]; } @catch (NSException *e) {}
        NSDictionary *info = [url isKindOfClass:[NSURL class]] ? [NSDictionary dictionaryWithContentsOfURL:[(NSURL *)url URLByAppendingPathComponent:@"Info.plist"]] : nil;
        id types = info[@"CFBundleDocumentTypes"];
        yes = ([types isKindOfClass:[NSArray class]] && [types count] > 0) || [info[@"UISupportsDocumentBrowser"] boolValue] || [info[@"LSSupportsOpeningDocumentsInPlace"] boolValue];
    }
    cache[b] = @(yes);
    return yes;
}
static NSArray<NSString *> *DMFinderShareApps(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSSet *hidden = DMFinderHiddenApps();
    for (NSString *b in @[@"com.apple.mobilenotes", @"com.apple.mobilemail", @"com.apple.MobileSMS", @"com.apple.DocumentsApp"]) if (DMAppInstalled(b)) [out addObject:b];
    // (the apps with windows on screen: Stage Manager's, or the window engine's -- Aerial / MilkyWay / Zetsu)
    NSMutableArray *open = [NSMutableArray array];
    if (DMSMEngine()) [open addObjectsFromArray:DMSMWindowBundles()];
    else for (UIView *st in DMAerialStages()) { if (st.hidden || st.alpha < 0.01) continue; NSString *b = DMStageBundle(st); if (b.length) [open addObject:b]; }
    for (NSString *b in open) if (![out containsObject:b]) [out addObject:b];
    SBApplication *front = DMActiveApp(); NSString *fb = [front bundleIdentifier];
    if (fb.length && ![out containsObject:fb]) [out addObject:fb];
    [out filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *b, NSDictionary *x) { return ![hidden containsObject:b] && DMFinderAppTakesFiles(b); }]];
    return out;
}
static void DMFinderShareTo(NSArray<DMFinderItem *> *items, NSString *bundle, DMFinderWindow *from) {
    DM_FEATURE_MARK("finder-share-menu");
    DMFDWatchReports();
    if (gFD) DMFDFinish(gFD, NO);
    DMFDrag *d = [DMFDrag new];
    d.items = items; d.from = from; d.proposal = -1; d.share = YES;
    gFDTokens = (uint16_t)(gFDTokens % 4095 + 1); d.token = gFDTokens;
    gFD = d;
    __block int tries = 0; __block void (^attempt)(void);
    void (^a)(void) = ^{
        if (d.finished) { attempt = nil; return; }
        NSString *sceneId = nil;
        UIView *v = DMFDSceneViewOf(bundle, &sceneId);
        if (!v) {
            if (tries == 0) DMOpenApp(bundle);
            if (++tries > 40) { DMLog([NSString stringWithFormat:@"[finder] share to %@: its window never appeared", bundle]); DMFDFinish(d, NO); attempt = nil; return; }
            void (^n)(void) = attempt;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), n);
            return;
        }
        attempt = nil;
        CGPoint mid = CGPointMake(CGRectGetMidX(v.bounds), CGRectGetMidY(v.bounds));
        d.app = bundle; d.scene = sceneId;
        if (!DMFDDescribe(d, bundle, sceneId, nil)) { DMFDFinish(d, NO); return; }
        DMFDSend(bundle, mid, 6);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DMFDHandOver(d, bundle, sceneId, mid, from, 2.5, ^(BOOL ok) {
                DMLog([NSString stringWithFormat:@"[finder] share to %@: %@", bundle, ok ? @"taken" : @"not taken"]);
                if (!ok) [from sheetTitle:[NSString stringWithFormat:@"%@ didn't take the file", DMCall(DMProxyForBundle(bundle), @"localizedName") ?: bundle] message:@"Open the place in the app where it should go (a note, a message, a folder), then share again or drag the file there." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            });
        });
    };
    attempt = a;
    a();
}
// ---- a Mac context menu in the native layer -----------------------------------------------------------------------------------------------
// A UIMenu drawn as our menus are (DMMakePanel rows over a catch-all that closes it): inline groups between divider lines, a submenu (Share) as a
// row with › that opens beside it, disabled actions greyed. An action runs after the menu has closed, as a menu bar row does.
static void DMFinderRunAction(UIAction *a) {
    void (^h)(UIAction *) = nil;
    @try { h = [a valueForKey:@"handler"]; } @catch (NSException *e) {}
    if (h) h(a); else DMLog([NSString stringWithFormat:@"[finder] menu: no handler for %@", a.title]);
}
static NSArray *DMFinderMenuRows(UIMenu *menu, UIControl *o);
static void DMFinderMenuPanel(UIControl *o, NSArray *rows, CGRect anchor, BOOL beside, NSInteger tag) {
    for (UIView *v in [o.subviews copy]) if (v.tag >= tag) [v removeFromSuperview];
    UIView *panel = DMMakePanel(rows);
    panel.tag = tag;
    CGSize b = o.bounds.size; CGRect pf = panel.frame;
    if (beside) {   // (a submenu: to the right of its row, or to the left when there is no room)
        pf.origin = CGPointMake(CGRectGetMaxX(anchor) - 4.0, anchor.origin.y - kPanelPad);
        if (CGRectGetMaxX(pf) > b.width - 6.0) pf.origin.x = CGRectGetMinX(anchor) - pf.size.width + 4.0;
    } else {        // (at the finger / pointer, kept on the screen)
        pf.origin = CGPointMake(anchor.origin.x + 2.0, anchor.origin.y + 2.0);
        if (CGRectGetMaxX(pf) > b.width - 6.0) pf.origin.x = anchor.origin.x - pf.size.width - 2.0;
    }
    pf.origin.x = MAX(6.0, MIN(pf.origin.x, b.width - pf.size.width - 6.0));
    pf.origin.y = MAX(26.0, MIN(pf.origin.y, b.height - pf.size.height - 6.0));
    panel.frame = pf;
    [o addSubview:panel];
    panel.alpha = 0.0;
    [UIView animateWithDuration:0.10 animations:^{ panel.alpha = 1.0; }];
}
static NSArray *DMFinderMenuRows(UIMenu *menu, UIControl *o) {
    NSMutableArray *rows = [NSMutableArray array];
    for (UIMenuElement *e in menu.children) {
        if ([e isKindOfClass:[UIMenu class]] && (((UIMenu *)e).options & UIMenuOptionsDisplayInline)) {
            NSArray *sub = DMFinderMenuRows((UIMenu *)e, o);
            if (!sub.count) continue;
            if (rows.count) [rows addObject:[NSNull null]];
            [rows addObjectsFromArray:sub];
        } else if ([e isKindOfClass:[UIMenu class]]) {
            UIMenu *sm = (UIMenu *)e;
            __weak UIControl *wo = o; __block __weak DMRow *wr = nil;
            DMRow *r = [[DMRow alloc] initWithTitle:sm.title enabled:sm.children.count > 0 handler:^{
                UIControl *oo = wo; DMRow *row = wr; if (!oo || !row) return;
                DMFinderMenuPanel(oo, DMFinderMenuRows(sm, oo), [row convertRect:row.bounds toView:oo], YES, 2);
            }];
            r.hint = @"›"; wr = r;
            [rows addObject:r];
        } else if ([e isKindOfClass:[UIAction class]]) {
            UIAction *a = (UIAction *)e;
            [rows addObject:[[DMRow alloc] initWithTitle:a.title enabled:!(a.attributes & UIMenuElementAttributesDisabled) handler:DMCloseThen(^{ DMFinderRunAction(a); })]];
        }
    }
    return rows;
}
static void DMFinderShowMenuIn(UIView *host, UIMenu *menu, CGPoint screenPoint) {   // (host: the native layer's, or the menu window's for the desktop)
    if (!host || !menu) return;
    UIControl *o = DMMakeOverlay(host, 0.0);
    [o addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMCloseOverlay(); }] forControlEvents:UIControlEventTouchUpInside];
    NSArray *rows = DMFinderMenuRows(menu, o);
    if (!rows.count) { DMCloseOverlay(); return; }
    CGPoint p = host == gMenuRotator ? screenPoint : [host convertPoint:screenPoint fromCoordinateSpace:(host.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    DMFinderMenuPanel(o, rows, CGRectMake(p.x, p.y, 0, 0), NO, 1);
}
static void DMFinderShowMenu(UIMenu *menu, CGPoint screenPoint) { DMFinderShowMenuIn(gNativeRotator, menu, screenPoint); }
static NSMutableArray<NSString *> *gFinderClipboard;   // Copy / Paste of files between folders

// ---- file operations ------------------------------------------------------------------------------------------------------------------------
// They run off the main thread, on one serial queue (copying or deleting a big folder on SpringBoard's main thread could hold it long enough for
// the system watchdog to kill SpringBoard), coordinated where the files are File Provider storage (DMFinderCoordinated).
// The Trash: /var/mobile/.Trash; items from iCloud Drive go to iCloud Drive's own Trash instead (a move out of iCloud Drive would delete them
// from iCloud on every device), after a question. Each trashed item carries where it came from (an extended attribute), for Put Back.
static dispatch_queue_t DMFinderFileQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.finder.files", DISPATCH_QUEUE_SERIAL); });
    return q;
}
static const char *const kFinderOriginAttr = "com.besiktasliseba.finder.origin";
static NSString *DMFinderICloudTrash(void) { return [kFinderICloud stringByAppendingPathComponent:@".Trash"]; }
static BOOL DMFinderInTrash(NSString *p) { NSString *n = DMFinderNorm(p); return DMFinderInside(n, kFinderTrash) || DMFinderInside(n, DMFinderICloudTrash()) || DMFinderDriveTrashOf(DMFinderRealItem(n)) != nil; }
// Where Move to Trash puts an item: a drive's own Trash for an item on a drive (it never leaves the drive), iCloud Drive's for iCloud, else Finder's.
static NSString *DMFinderTrashFor(NSString *p) {
    NSString *drive = DMFinderDriveRoot(DMFinderRealItem(p));
    if (drive) return DMFinderDriveTrash(drive);
    return DMFinderInICloud(p) ? DMFinderICloudTrash() : kFinderTrash;
}
// (an item in a drive's Trash notes where it came from relative to its volume -- "volume:/folder/name" --: the drive may be mounted under another
//  name next time, e.g. "NO NAME 1"; Put Back finds the place on the volume the item is on now)
static NSString *const kFinderVolumeOrigin = @"volume:";
static void DMFinderSetOrigin(NSString *p, NSString *origin) {
    NSString *drive = origin.length ? DMFinderDriveRoot(DMFinderRealItem(p)) : nil;
    NSString *ro = drive ? DMFinderRealItem(origin) : nil;
    if (drive && DMFinderInside(ro, drive) && ![ro isEqualToString:drive]) origin = [kFinderVolumeOrigin stringByAppendingString:[ro substringFromIndex:drive.length]];
    if (origin.length) setxattr(p.fileSystemRepresentation, kFinderOriginAttr, origin.UTF8String, strlen(origin.UTF8String), 0, XATTR_NOFOLLOW);
    else removexattr(p.fileSystemRepresentation, kFinderOriginAttr, XATTR_NOFOLLOW);
}
static NSString *DMFinderOrigin(NSString *p) {
    char buf[4096]; ssize_t n = getxattr(p.fileSystemRepresentation, kFinderOriginAttr, buf, sizeof buf - 1, 0, XATTR_NOFOLLOW);
    if (n <= 0) return nil;
    buf[n] = 0; NSString *o = [NSString stringWithUTF8String:buf];
    if (![o hasPrefix:kFinderVolumeOrigin]) return o;
    NSString *drive = DMFinderDriveRoot(DMFinderRealItem(p)), *rest = [o substringFromIndex:kFinderVolumeOrigin.length];
    return drive && [rest hasPrefix:@"/"] ? DMFinderNorm([drive stringByAppendingString:rest]) : nil;   // (".." is resolved: the policy checks where it really leads)
}
// An item moved to the Trash from the desktop carries its place there (an extended attribute, "fx,fy" as fractions of the desktop's free area):
// Undo and Put Back bring it to the same spot (Desktop.h reads and removes it when the item is listed again). Asked of the desktop on the main
// thread when the operation starts (gFinderDesktopPlaceFor, set by Desktop.h; nil: not on the desktop).
static const char *const kFinderDesktopPlaceAttr = "com.besiktasliseba.desktop.place";
static NSString *(*gFinderDesktopPlaceFor)(NSString *path);
static void DMFinderSetDesktopPlace(NSString *p, NSString *place) {
    if (place.length) setxattr(p.fileSystemRepresentation, kFinderDesktopPlaceAttr, place.UTF8String, strlen(place.UTF8String), 0, XATTR_NOFOLLOW);
    else removexattr(p.fileSystemRepresentation, kFinderDesktopPlaceAttr, XATTR_NOFOLLOW);
}
static NSError *DMFinderError(NSString *text) { return [NSError errorWithDomain:@"Finder" code:1 userInfo:@{NSLocalizedDescriptionKey: text}]; }
// One move or copy (dst: a free name, worked out on this queue).
static NSError *DMFinderTransfer(NSString *src, NSString *dst, BOOL copy) {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block NSError *e = nil; NSError *ce = nil;
    if (!DMFinderCoordinated(src) && !DMFinderCoordinated(dst)) {
        if (copy) [fm copyItemAtPath:src toPath:dst error:&e]; else [fm moveItemAtPath:src toPath:dst error:&e];
        return e;
    }
    NSFileCoordinator *fc = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSURL *su = [NSURL fileURLWithPath:src], *du = [NSURL fileURLWithPath:dst];
    if (copy) [fc coordinateReadingItemAtURL:su options:0 writingItemAtURL:du options:NSFileCoordinatorWritingForReplacing error:&ce byAccessor:^(NSURL *r, NSURL *w) { [fm copyItemAtURL:r toURL:w error:&e]; }];
    else [fc coordinateWritingItemAtURL:su options:NSFileCoordinatorWritingForMoving writingItemAtURL:du options:NSFileCoordinatorWritingForReplacing error:&ce byAccessor:^(NSURL *a, NSURL *b) {
        if ([fm moveItemAtURL:a toURL:b error:&e]) [fc itemAtURL:a didMoveToURL:b]; }];
    return e ?: ce;
}
// Finder's Trash is a real folder of its own: were /var/mobile/.Trash ever a link (another tool made it one), Move to Trash would move the user's
// files through it and Empty Trash would erase wherever it points. Then the Trash is not used at all.
static BOOL DMFinderTrashIsSound(void) {
    struct stat st;
    if (lstat(kFinderTrash.fileSystemRepresentation, &st) != 0) return errno == ENOENT;   // (not there yet: made as a folder when first needed)
    return S_ISDIR(st.st_mode) && [DMFinderReal(kFinderTrash) isEqualToString:kFinderTrash];
}
// The Trash folder t made ready for Move to Trash (Finder's own or a drive's is made when first needed, and must be a real folder): nil or why not.
static NSError *DMFinderPrepareTrash(NSString *t) {
    BOOL drive = DMFinderDriveTrashOf(t) != nil;
    if (!drive && ![t isEqualToString:kFinderTrash]) return nil;   // (iCloud Drive's: kept by iCloud)
    if (drive ? !DMFinderDriveTrashIsSound(t) : !DMFinderTrashIsSound()) return DMFinderError(@"The Trash is not a folder of its own here.");
    if (drive) {   // (one level at a time with mkdir, each checked: never through a link -- logic test 1.2.3)
        NSString *parent = t.stringByDeletingLastPathComponent;
        struct stat pst;
        if (lstat(parent.fileSystemRepresentation, &pst) != 0) mkdir(parent.fileSystemRepresentation, 0755);
        if (lstat(parent.fileSystemRepresentation, &pst) != 0 || !S_ISDIR(pst.st_mode) || ![DMFinderReal(parent) isEqualToString:parent]) return DMFinderError(@"The Trash is not a folder of its own here.");
        struct stat tst;
        if (lstat(t.fileSystemRepresentation, &tst) != 0) mkdir(t.fileSystemRepresentation, 0700);
    } else [[NSFileManager defaultManager] createDirectoryAtPath:t withIntermediateDirectories:YES attributes:nil error:nil];
    if (drive ? !DMFinderDriveTrashIsSound(t) : !DMFinderTrashIsSound()) return DMFinderError(@"The Trash is not a folder of its own here.");
    return nil;
}
// A path on a drive that is no longer connected: inside LiveFiles at least as deep as a volume (<LiveFiles>/<provider>/<volume>...), and on no
// mounted drive. LiveFiles itself and a provider folder are not "a gone drive" (a window browsing them was sent away at every plug, logic test 1.2.3).
static BOOL DMFinderOnGoneDrive(NSString *p) {
    if (!p.length) return NO;
    NSString *n = DMFinderNorm(p), *lf = DMFinderNorm(kFinderLiveFiles);
    if (!DMFinderInside(n, lf) || n.pathComponents.count < lf.pathComponents.count + 2) return NO;
    return !DMFinderDriveRoot(DMFinderReal(p));
}
// After an error on a drive: was it unplugged meanwhile? Then that is the reason given (not the file system's own words).
static NSError *DMFinderDriveGoneError(NSError *e, NSArray<NSString *> *paths) {
    if (!e) return nil;
    DMFinderDrivesForget();
    for (NSString *p in paths) {
        if (!DMFinderInside(DMFinderNorm(p), DMFinderNorm(kFinderLiveFiles))) continue;
        NSArray *c = DMFinderNorm(p).pathComponents, *lf = DMFinderNorm(kFinderLiveFiles).pathComponents;
        if (c.count < lf.count + 2) continue;
        NSString *root = [NSString pathWithComponents:[c subarrayWithRange:NSMakeRange(0, lf.count + 2)]];
        if (!DMFinderDriveInfo(root)) return [NSError errorWithDomain:@"Finder" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The drive “%@” was disconnected.", root.lastPathComponent]}];
    }
    return e;
}
static NSError *DMFinderRemove(NSString *p) {   // (deletes ONLY inside Finder's own Trash: Empty Trash and Delete Immediately, nothing else)
    // (the item's own place: an alias in the Trash is deleted itself -- never followed to what it points at, and never refused for pointing outside)
    NSString *r = DMFinderRealItem(p), *dt = DMFinderDriveTrashOf(r);   // (or a drive's Trash: <volume>/.Trashes/501, a real folder, not the folder itself)
    BOOL ok = dt ? DMFinderDriveTrashIsSound(dt) && ![r isEqualToString:dt] : DMFinderTrashIsSound() && DMFinderInside(r, kFinderTrash) && ![r isEqualToString:kFinderTrash];
    if (!ok) return DMFinderError([NSString stringWithFormat:@"“%@” is not in the Trash.", p.lastPathComponent]);
    NSFileManager *fm = [NSFileManager defaultManager];
    __block NSError *e = nil; NSError *ce = nil;
    if (!DMFinderCoordinated(p)) { [fm removeItemAtPath:p error:&e]; return e; }
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateWritingItemAtURL:[NSURL fileURLWithPath:p] options:NSFileCoordinatorWritingForDeleting error:&ce byAccessor:^(NSURL *u) { [fm removeItemAtURL:u error:&e]; }];
    return e ?: ce;
}
// Every Finder window showing one of these folders reads it again.
static void DMFinderRefreshFolders(NSSet<NSString *> *dirs) {
    NSMutableSet *want = [NSMutableSet set];
    for (NSString *d in dirs) { [want addObject:DMFinderNorm(d)]; [want addObject:DMFinderReal(d)]; if (DMFinderDriveTrashOf(DMFinderReal(d))) [want addObject:kFinderTrash]; }   // (a drive's Trash: the Trash shows it)
    for (DMNativeWindow *w in [gNativeWindows copy]) {
        if (![w isKindOfClass:NSClassFromString(@"DMFinderWindow")]) continue;
        NSString *p = [(id)w path];
        if (p && ([want containsObject:DMFinderNorm(p)] || [want containsObject:DMFinderReal(p)])) [(id)w refresh];
    }
}
// Undo (Command-Z): the last operations, each with what undoes it -- moves, renames, Move to Trash and Put Back go back; copies, duplicates and
// new folders go to the Trash (as on a Mac). Delete Immediately and Empty Trash can't be undone (they say so first).
static NSMutableArray<NSDictionary *> *gFinderUndo;
static void DMFinderPushUndo(NSString *kind, NSString *what, NSArray<NSArray<NSString *> *> *pairs) {
    if (!pairs.count) return;
    if (!gFinderUndo) gFinderUndo = [NSMutableArray array];
    [gFinderUndo addObject:@{@"kind": kind, @"what": what, @"pairs": pairs}];
    if (gFinderUndo.count > 30) [gFinderUndo removeObjectAtIndex:0];
}
static NSString *DMFinderNames(NSArray<NSString *> *paths) {   // "“a.txt”", "“a.txt” and 2 more"
    NSString *first = [NSString stringWithFormat:@"“%@”", [paths.firstObject lastPathComponent] ?: @"?"];
    return paths.count > 1 ? [first stringByAppendingFormat:@" and %lu more", (unsigned long)paths.count - 1] : first;
}


static void DMFinderWatchDrives(void);
static void DMFinderDrivesCheck(NSString *why);
@implementation DMFinderWindow {
    UITableView *_sidebar, *_list;
    UICollectionView *_grid;
    UIView *_toolbar, *_toolbarBack, *_sideBack, *_pathBar;
    UIButton *_back, *_fwd, *_viewSwitch;
    UILabel *_folderLabel, *_status, *_empty;
    UIView *_header;
    DMFinderItem *_dragArmed; CGPoint _dragStart, _dragDown, _dragDownOffset; BOOL _dragLifted; __weak UIView *_dragCell;
    BOOL _fingerDown, _menuByHold, _pressActive; NSUInteger _pressSerial;   // (a finger's press: its menu opens from our hold, see -dm_dragPress:)
    UISearchBar *_search;
    NSArray<NSDictionary *> *_places;
    NSArray<DMFinderItem *> *_all, *_items;
    NSMutableArray<NSString *> *_history; NSInteger _hpos;
    BOOL _icons, _hidden;
    NSString *_selected;   // (the selection's anchor: the item clicked last -- Shift-click selects from it)
    NSMutableOrderedSet<NSString *> *_sel;   // (the selected items' paths: one, several (Command / Shift click, Command-A, Select, a pointer's band) or none)
    NSString *_lastClickPath; CFTimeInterval _lastClickAt; BOOL _pressHappened, _selectMode; UIButton *_selectButton; NSString *_statusBase;
    UIView *_band; CGPoint _bandStart; NSOrderedSet<NSString *> *_bandBase;   // (a pointer's selection rectangle, from empty space)
    UITextField *_renameField; NSString *_renamePath, *_renameWhenListed;   // (a name being edited in place, -dm_beginInlineRename:)
    NSArray<NSString *> *_selectWhenListed;
    dispatch_source_t _watch; BOOL _watchPending;   // (the open folder is watched: a change in it shows at once, whoever made it)
    NSMutableArray *_watchMore;   // (the Trash: the connected drives' Trashes are watched too)
    unsigned long long _free;     // (the free space where the open folder is, for the status line; ULLONG_MAX: unknown)
}
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    self = [super initWithTitle:title frame:frame];
    if (!self) return nil;
    self.minSize = CGSizeMake(520.0, 320.0);
    self.titleBarHeight = 52.0; self.fullSizeContent = YES; self.showsTitle = NO;   // (a Mac Finder: one unified toolbar, the sidebar up to the top)
    _history = [NSMutableArray array]; _hpos = -1;
    DMFinderWatchDrives();
    _places = DMFinderSidebar();
    UIView *c = self.contentView;
    c.backgroundColor = [UIColor clearColor];
    // sidebar (translucent, like a Mac's), under the title bar's traffic lights
    _sideBack = [UIView new];
    _sideBack.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.55];
    [c addSubview:_sideBack];
    _sidebar = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _sidebar.backgroundColor = [UIColor clearColor];
    _sidebar.separatorStyle = UITableViewCellSeparatorStyleNone;
    _sidebar.dataSource = self; _sidebar.delegate = self;
    _sidebar.rowHeight = 30.0; _sidebar.sectionHeaderHeight = 28.0;
    if (@available(iOS 15.0, *)) _sidebar.sectionHeaderTopPadding = 6.0;
    [c addSubview:_sidebar];
    _sidebar.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // toolbar: back / forward, the folder's name, List / Icons, Search
    _toolbar = [UIView new];
    _toolbar.backgroundColor = [UIColor clearColor];
    [self.titleBar addSubview:_toolbar];
    _toolbarBack = [UIView new]; _toolbarBack.backgroundColor = [UIColor systemBackgroundColor];
    [c addSubview:_toolbarBack];
    UIImageSymbolConfiguration *tc = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightMedium];
    _back = [UIButton buttonWithType:UIButtonTypeSystem]; [_back setImage:[UIImage systemImageNamed:@"chevron.left" withConfiguration:tc] forState:UIControlStateNormal];
    _fwd = [UIButton buttonWithType:UIButtonTypeSystem]; [_fwd setImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:tc] forState:UIControlStateNormal];
    [_back addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [_fwd addTarget:self action:@selector(goForward) forControlEvents:UIControlEventTouchUpInside];
    _folderLabel = [UILabel new]; _folderLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightBold];
    _viewSwitch = [UIButton buttonWithType:UIButtonTypeSystem];
    [_viewSwitch addTarget:self action:@selector(toggleView) forControlEvents:UIControlEventTouchUpInside];
    _search = [UISearchBar new]; _search.searchBarStyle = UISearchBarStyleMinimal; _search.placeholder = @"Search"; _search.delegate = self;
    _search.autocapitalizationType = UITextAutocapitalizationTypeNone; _search.autocorrectionType = UITextAutocorrectionTypeNo;   // (typed "filler 2" became "Filler 2")
    _search.spellCheckingType = UITextSpellCheckingTypeNo;
    _selectButton = [UIButton buttonWithType:UIButtonTypeSystem];   // (Select: taps then add / remove items, for several at once without a keyboard)
    _selectButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    [_selectButton setTitle:@"Select" forState:UIControlStateNormal];
    [_selectButton addTarget:self action:@selector(dm_toggleSelectMode) forControlEvents:UIControlEventTouchUpInside];
    _sel = [NSMutableOrderedSet orderedSet];
    for (UIView *v in @[_back, _fwd, _folderLabel, _viewSwitch, _selectButton, _search]) { v.tintColor = [UIColor secondaryLabelColor]; [_toolbar addSubview:v]; }
    // contents: a list or an icon grid
    _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _list.dataSource = self; _list.delegate = self; _list.rowHeight = 26.0;
    _list.separatorStyle = UITableViewCellSeparatorStyleNone;
    [c addSubview:_list];
    _header = [UIView new]; _header.backgroundColor = [UIColor systemBackgroundColor];
    for (NSString *t in @[@"Name", @"Date Modified", @"Size", @"Kind"]) {
        UILabel *h = [UILabel new]; h.text = t; h.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]; h.textColor = [UIColor secondaryLabelColor];
        [_header addSubview:h];
    }
    UIView *line = [UIView new]; line.backgroundColor = [UIColor separatorColor]; line.tag = 9; [_header addSubview:line];
    [c addSubview:_header];
    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.itemSize = CGSizeMake(96.0, 96.0); fl.minimumInteritemSpacing = 8.0; fl.minimumLineSpacing = 12.0; fl.sectionInset = UIEdgeInsetsMake(14, 14, 14, 14);
    _grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:fl];
    _grid.backgroundColor = [UIColor systemBackgroundColor];
    _grid.dataSource = self; _grid.delegate = self;
    [_grid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"i"];
    [c addSubview:_grid];
    _list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    if (@available(iOS 15.0, *)) _list.sectionHeaderTopPadding = 0;
    _grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _status = [UILabel new]; _status.font = [UIFont systemFontOfSize:11.0]; _status.textColor = [UIColor secondaryLabelColor]; _status.textAlignment = NSTextAlignmentCenter;
    _status.backgroundColor = [UIColor systemBackgroundColor];
    [c addSubview:_status];
    _empty = [UILabel new]; _empty.font = [UIFont systemFontOfSize:13.0]; _empty.textColor = [UIColor tertiaryLabelColor]; _empty.textAlignment = NSTextAlignmentCenter; _empty.numberOfLines = 0;
    [c addSubview:_empty];
    // Clicks are ours (-dm_click:): the list's own selection stays out (willSelect / shouldSelect refuse it), so a Command- or Shift-click, a double
    // tap and Select mode work the same in the list and the icons, and the selection shows what -dm_selectedItems acts on.
    _list.allowsMultipleSelection = YES; _grid.allowsMultipleSelection = YES;
    for (UIView *v in @[_list, _grid]) {
        UITapGestureRecognizer *click = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_click:)];
        click.name = @"dm.finder.click"; click.delegate = self; click.cancelsTouchesInView = NO;
        if (@available(iOS 13.4, *)) click.buttonMaskRequired = UIEventButtonMaskPrimary;
        [v addGestureRecognizer:click];
        UIPanGestureRecognizer *band = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_band:)];   // (a pointer drag from empty space)
        band.name = @"dm.finder.band"; band.delegate = self; band.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [v addGestureRecognizer:band];
    }
    for (UIView *v in @[_list, _grid]) {
        [v addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];   // (the menu's items: -dm_menuIn:at:; shown by DMFinderShowMenu)
        UITapGestureRecognizer *rc = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_secondaryClick:)];
        rc.buttonMaskRequired = UIEventButtonMaskSecondary;   // (a pointer's right click -- only a pointer's: for a finger the mask is not
        rc.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];   //  checked, and the release of a held finger fired it, closing the hold's menu)
        [v addGestureRecognizer:rc];
    }
    // Drag and drop: our own (DMFinderDrag, below). The system's drag service never delivered a drag that started in this SpringBoard window to
    // anything else -- not to another Finder window, not to an app (iPad 2 and M1, 30 Sep: the session began and ended, no drop target was ever
    // asked) -- so, like a Mac's window server, we carry the file: a long press lifts it, it follows the finger / pointer above every window,
    // and the window under it on release takes it (a Finder window: moved there; an app: handed to the app's own drop handling).
    // (press and MOVE lifts the item; press and hold without moving opens its menu -- the two used to fight: the menu's long press won and
    //  lifted the whole list as its preview, 30 Sep)
    for (UIView *v in @[_list, _grid]) {
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dm_dragPress:)];
        lp.minimumPressDuration = 0.3;   // (a real hold: at 0.18 s a touch that started a scroll became a drag and moved a file, M1 30 Sep -- now a scroll
                                         //  under way never arms one; at 0.5 s the menu's own long press came at the same moment and took the touch)
        lp.allowableMovement = CGFLOAT_MAX;
        lp.delegate = self;
        lp.name = @"dm.finder.drag";
        [v addGestureRecognizer:lp];
    }
    [self updateViewSwitch];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat side = MIN(190.0, MAX(130.0, b.size.width * 0.3)), tb = self.titleBarHeight, st = 22.0;
    _sideBack.frame = CGRectMake(0, 0, side, b.size.height);
    _sidebar.frame = CGRectMake(0, tb - 8.0, side, b.size.height - tb + 8.0);
    CGFloat x = side;
    _toolbarBack.frame = CGRectMake(x, 0, b.size.width - x, tb);
    _toolbar.frame = CGRectMake(x, 0, b.size.width - x, tb);
    CGFloat cy = (tb - 32.0) / 2.0;
    _back.frame = CGRectMake(8, cy, 30, 32); _fwd.frame = CGRectMake(38, cy, 30, 32);
    CGFloat sw = MIN(190.0, _toolbar.bounds.size.width * 0.34);
    _search.frame = CGRectMake(_toolbar.bounds.size.width - sw - 6, (tb - 36.0) / 2.0, sw, 36);
    _viewSwitch.frame = CGRectMake(CGRectGetMinX(_search.frame) - 38, cy, 34, 32);
    _selectButton.frame = CGRectMake(CGRectGetMinX(_viewSwitch.frame) - 56, cy, 54, 32);
    _folderLabel.frame = CGRectMake(76, 0, CGRectGetMinX(_selectButton.frame) - 80, tb);
    CGFloat hh = _icons ? 0.0 : 22.0;
    _header.hidden = _icons;
    _header.frame = CGRectMake(x, tb, b.size.width - x, hh);
    { CGFloat w = _header.bounds.size.width; DMFinderCols cols = DMFinderColumns(w);
      NSArray *xs = @[@(44.0), @(cols.date), @(cols.size), @(cols.kind)];
      NSInteger i = 0;
      for (UIView *v in _header.subviews) {
          if (v.tag == 9) { v.frame = CGRectMake(0, hh - 0.5, w, 0.5); continue; }
          CGFloat x = [xs[i] doubleValue]; v.hidden = x < 0; v.frame = CGRectMake(MAX(x, 0), 0, i == 0 ? cols.nameW : 140, hh); i++;
      } }
    CGRect area = CGRectMake(x, tb + hh, b.size.width - x, b.size.height - tb - hh - st);
    BOOL widthChanged = fabs(_list.frame.size.width - area.size.width) > 0.5;
    _list.frame = area;
    if (widthChanged) [_list reloadData];   // (the columns follow the width: cells laid out for the old one re-made)
    _grid.frame = CGRectMake(x, tb, b.size.width - x, b.size.height - tb - st);
    _list.hidden = _icons; _grid.hidden = !_icons;
    _status.frame = CGRectMake(x, b.size.height - st, b.size.width - x, st);
    _empty.frame = CGRectInset(area, 20, 40);
    _back.enabled = _hpos > 0; _fwd.enabled = _hpos >= 0 && _hpos < (NSInteger)_history.count - 1;
}
- (void)updateViewSwitch {
    UIImageSymbolConfiguration *tc = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIImageSymbolWeightMedium];
    [_viewSwitch setImage:[UIImage systemImageNamed:_icons ? @"list.bullet" : @"square.grid.2x2" withConfiguration:tc] forState:UIControlStateNormal];
}
- (void)toggleView { _icons = !_icons; [self updateViewSwitch]; [self setNeedsLayout]; [self reload]; }
- (void)go:(NSString *)path {
    if (!path.length) return;
    if (_hpos < (NSInteger)_history.count - 1) [_history removeObjectsInRange:NSMakeRange(_hpos + 1, _history.count - _hpos - 1)];
    [_history addObject:path]; _hpos = _history.count - 1;
    [self load:path];
}
- (void)goBack { if (_hpos > 0) { _hpos--; [self load:_history[_hpos]]; } }
- (void)goForward { if (_hpos < (NSInteger)_history.count - 1) { _hpos++; [self load:_history[_hpos]]; } }
- (void)goUp { NSString *up = self.path.stringByDeletingLastPathComponent; if (up.length && ![up isEqualToString:self.path]) [self go:up]; }
- (void)load:(NSString *)path {
    path = DMFinderNorm(path);
    self.path = path;
    NSString *name = [path isEqualToString:@"/"] ? @"iPad" : path.lastPathComponent;
    for (NSDictionary *sec in _places) for (NSDictionary *r in sec[@"rows"]) if ([r[@"p"] isEqualToString:path]) name = r[@"t"];
    if ([path.stringByDeletingLastPathComponent hasSuffix:@"/Application"] && path.lastPathComponent.length == 36) name = DMFinderContainerName(path) ?: name;
    self.title = name; _folderLabel.text = name;
    [self dm_endRename:YES];
    _search.text = @""; _selected = nil; [_sel removeAllObjects]; _lastClickPath = nil;
    if ([path isEqualToString:kFinderTrash]) [[NSFileManager defaultManager] createDirectoryAtPath:kFinderTrash withIntermediateDirectories:YES attributes:nil error:nil];
    [self dm_watch:path];
    [self dm_list];
    [self setNeedsLayout];
    [_sidebar reloadData];
}
// (read the folder again in the background; the search and the selection stay -- a refresh after a file operation or a change seen by the watch)
- (void)dm_list {
    NSString *path = self.path; if (!path) return;
    BOOL hidden = _hidden;
    __weak DMFinderWindow *ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        NSArray *items = DMFinderList(path, hidden, &err);
        unsigned long long free = items ? DMFinderFreeSpace(path) : ULLONG_MAX;
        dispatch_async(dispatch_get_main_queue(), ^{
            DMFinderWindow *s = ws; if (!s || ![s.path isEqualToString:path]) return;
            s->_free = free;
            [s setItems:items error:err];
        });
    });
}
// The open folder is watched (a vnode source on it, like Apple's DirectoryMonitor): files added, removed or renamed there by an app, a drop,
// another window or Undo show without a refresh. Several changes in a row are read once.
- (void)dm_watch:(NSString *)path {
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    for (dispatch_source_t m in _watchMore) dispatch_source_cancel(m);
    _watchMore = [NSMutableArray array];
    // (a drive unplugged: its folders' sources see REVOKE -- the open folder is then gone, see -dm_folderGone:)
    unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_REVOKE;
    __weak DMFinderWindow *ws = self;
    dispatch_source_t (^watch)(NSString *) = ^dispatch_source_t(NSString *dir) {
        int fd = dir.length ? open(dir.fileSystemRepresentation, O_EVTONLY) : -1;
        if (fd < 0) return nil;
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, mask, dispatch_get_main_queue());
        if (!src) { close(fd); return nil; }
        dispatch_source_set_event_handler(src, ^{
            DMFinderWindow *s = ws; if (!s || s->_watchPending) return;
            s->_watchPending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                DMFinderWindow *s2 = ws; if (!s2) return;
                s2->_watchPending = NO;
                if (![s2.path isEqualToString:path]) return;
                if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { [s2 dm_folderGone]; return; }
                if (![dir isEqualToString:path]) [s2 dm_watch:path];   // (a drive's Trash changed: watched again -- it may have been made just now)
                [s2 dm_list];
            });
        });
        dispatch_source_set_cancel_handler(src, ^{ close(fd); });
        dispatch_resume(src);
        return src;
    };
    _watch = watch(path);
    if ([path isEqualToString:kFinderTrash]) {   // (the Trash: each connected drive's Trash, or its .Trashes / the volume while it isn't made yet)
        for (NSString *t in DMFinderDriveTrashes()) {
            NSString *w = t;
            while (w.length > 1 && ![[NSFileManager defaultManager] fileExistsAtPath:w]) w = w.stringByDeletingLastPathComponent;
            dispatch_source_t m = DMFinderDriveRoot(w) ? watch(w) : nil;
            if (m) [_watchMore addObject:m];
        }
    }
}
// The open folder is no longer there: its enclosing folder, as on a Mac -- or, when it was on a drive that is no longer connected, On My iPad (never
// the folders the drive was mounted in, never an error loop).
- (void)dm_folderGone {
    DMFinderDrivesForget();   // (the mount table now, not the list kept for half a second)
    NSString *path = self.path;
    if (DMFinderOnGoneDrive(path)) { [self dm_driveGone]; return; }
    DMLog(@"[finder] the open folder is gone: showing its enclosing folder");
    [self go:path.stringByDeletingLastPathComponent];
}
- (void)dm_driveGone {
    DMLog(@"[finder] drive: the folder shown was on a drive that is no longer connected: showing On My iPad");
    [self dm_endRename:NO];
    NSMutableArray *keep = [NSMutableArray array];   // (Back / Forward never lead to the drive's folders again)
    NSInteger pos = _hpos;
    for (NSInteger i = 0; i < (NSInteger)_history.count; i++) {
        NSString *h = _history[i];
        if (DMFinderOnGoneDrive(h)) { if (i <= _hpos) pos--; continue; }
        [keep addObject:h];
    }
    _history = keep; _hpos = MIN(MAX(pos, -1), (NSInteger)_history.count - 1);
    NSString *safe = DMFinderOnMyIPad() ?: @"/var/mobile/Documents";
    [self go:safe];
}
// The connected drives changed (DMFinderWatchDrives): the sidebar shows them; a window showing a drive that is gone goes to a safe place; the Trash
// is read again (its drive items come and go with their drives).
- (void)dm_drivesChanged {
    _places = DMFinderSidebar();
    [_sidebar reloadData];
    NSString *p = self.path;
    if (DMFinderOnGoneDrive(p)) { [self dm_driveGone]; return; }
    if ([p isEqualToString:kFinderTrash]) { [self dm_watch:p]; [self dm_list]; }
}
- (void)close { [self dm_endRename:NO]; if (_watch) { dispatch_source_cancel(_watch); _watch = nil; } for (dispatch_source_t m in _watchMore) dispatch_source_cancel(m); _watchMore = nil; [super close]; }
- (void)setItems:(NSArray *)items error:(NSError *)err {
    _all = items ?: @[];
    _empty.text = items ? (items.count ? nil : @"This folder is empty.") : [NSString stringWithFormat:@"The iPad doesn't let Finder open this folder.\n%@", err.localizedDescription ?: @""];
    NSSet *here = [NSSet setWithArray:[_all valueForKey:@"path"]];   // (selected items that are gone leave the selection)
    for (NSString *x in [_sel array]) if (![here containsObject:x]) [_sel removeObject:x];
    if (_selected && ![here containsObject:_selected]) _selected = nil;
    if (_selectWhenListed.count) {   // (after Duplicate, a drop, Undo...: the new items become the selection, as on a Mac -- all of them)
        NSMutableArray *got = [NSMutableArray array];
        for (NSString *x in _selectWhenListed) if ([here containsObject:x]) [got addObject:x];
        if (got.count) { _selectWhenListed = nil; [_sel removeAllObjects]; [_sel addObjectsFromArray:got]; _selected = got.firstObject; }
    }
    [self applySearch];   // (it reloads, and the reload shows the selection)
    if (_selected) [self dm_scrollToPath:_selected];
    if (_renameWhenListed && [here containsObject:_renameWhenListed]) { NSString *r = _renameWhenListed; _renameWhenListed = nil; [self dm_beginInlineRename:r]; }
}
- (void)dm_selectPathsWhenListed:(NSArray<NSString *> *)paths { _selectWhenListed = [paths copy]; }
- (void)applySearch {
    NSString *q = _search.text;
    if (q.length) {
        NSMutableArray *m = [NSMutableArray array];
        for (DMFinderItem *it in _all) if ([it.display rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [m addObject:it];
        _items = m;
    } else _items = _all;
    _empty.hidden = _empty.text == nil || q.length;
    NSString *avail = _free && _free != ULLONG_MAX ? [NSString stringWithFormat:@", %@ available", [NSByteCountFormatter stringFromByteCount:(long long)_free countStyle:NSByteCountFormatterCountStyleFile]] : @"";   // (as on a Mac: "12 items, 93 GB available")
    _status.text = [NSString stringWithFormat:@"%lu item%@%@%@%@", (unsigned long)_items.count, _items.count == 1 ? @"" : @"s", avail, q.length ? [NSString stringWithFormat:@" matching “%@”", q] : @"",
                    self.path && !DMFinderCanWriteInto(self.path) && !DMFinderInOwnTrash(self.path) ? @" — Read Only" : @""];   // (a place Finder doesn't change, like a Mac's status bar says)
    _statusBase = _status.text;
    [self reload];
}
- (void)reload { [_list reloadData]; [_grid reloadData]; [self dm_showSelection]; }
- (void)refresh { [self dm_list]; }
- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)t { [self applySearch]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)sb { [gNativeLayer makeKeyWindow]; }

// sidebar + list (both tables)
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return tv == _sidebar ? _places.count : 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return tv == _sidebar ? [_places[s][@"rows"] count] : _items.count; }
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    if (tv != _sidebar) return nil;
    UILabel *l = [UILabel new]; l.text = [@"  " stringByAppendingString:_places[s][@"h"]];
    l.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold]; l.textColor = [UIColor tertiaryLabelColor];
    return l;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return tv == _sidebar ? 26.0 : 0.0; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:tv == _sidebar ? @"s" : @"l"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:tv == _sidebar ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault reuseIdentifier:tv == _sidebar ? @"s" : @"l"];
    cell.backgroundColor = [UIColor clearColor];
    UIView *sel = [UIView new]; sel.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:tv == _sidebar ? 0.18 : 0.9]; sel.layer.cornerRadius = 5.0;
    cell.selectedBackgroundView = sel;
    if (tv == _sidebar) {
        NSDictionary *r = _places[ip.section][@"rows"][ip.row];
        cell.textLabel.text = r[@"t"]; cell.textLabel.font = [UIFont systemFontOfSize:13.0];
        cell.imageView.image = [UIImage systemImageNamed:r[@"i"] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0]];
        cell.imageView.tintColor = [UIColor systemBlueColor];
        cell.detailTextLabel.text = nil;
        BOOL here = [self.path isEqualToString:r[@"p"]];
        cell.backgroundColor = here ? [[UIColor labelColor] colorWithAlphaComponent:0.08] : [UIColor clearColor];
        return cell;
    }
    DMFinderItem *it = _items[ip.row];
    // (columns at the header's places: Name, Date Modified, Size, Kind)
    CGFloat w = tv.bounds.size.width;
    UIImageView *iv = [cell.contentView viewWithTag:10];
    if (!iv) {
        iv = [UIImageView new]; iv.tag = 10; iv.contentMode = UIViewContentModeScaleAspectFit; iv.accessibilityIgnoresInvertColors = YES; [cell.contentView addSubview:iv];   // (Smart Invert leaves pictures as they are, like Apple's own icons: 1.3.3, audit L-3)
        for (NSInteger t = 11; t <= 14; t++) { UILabel *l = [UILabel new]; l.tag = t; l.font = [UIFont systemFontOfSize:t == 11 ? 13.0 : 11.5]; l.lineBreakMode = NSLineBreakByTruncatingMiddle; [cell.contentView addSubview:l]; }
    }
    CGFloat h = tv.rowHeight;
    iv.frame = CGRectMake(20, (h - 18) / 2.0, 18, 18);
    __weak UITableView *wtv = tv;
    iv.image = DMFinderThumb(it, 18.0, ^{ UITableView *t = wtv; if (t && ip.row < [t numberOfRowsInSection:0]) [t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone]; }) ?: DMFinderIconWithAlias(it, 18.0);
    UILabel *n = [cell.contentView viewWithTag:11], *d = [cell.contentView viewWithTag:12], *z = [cell.contentView viewWithTag:13], *k = [cell.contentView viewWithTag:14];
    DMFinderCols cols = DMFinderColumns(w);
    n.frame = CGRectMake(44, 0, cols.nameW, h);
    d.frame = CGRectMake(cols.date, 0, 172, h); z.frame = CGRectMake(cols.size, 0, 60, h); k.frame = CGRectMake(cols.kind, 0, 84, h);
    d.hidden = cols.date < 0; z.hidden = cols.size < 0; k.hidden = cols.kind < 0;
    n.text = it.display; d.text = DMFinderDate(it.date); z.text = DMFinderSize(it); k.text = it.kind;
    n.textColor = it.locked ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    for (UILabel *l in @[d, z, k]) l.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.text = nil; cell.detailTextLabel.text = nil; cell.imageView.image = nil;
    cell.backgroundColor = (ip.row % 2) ? [[UIColor labelColor] colorWithAlphaComponent:0.03] : [UIColor clearColor];
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (tv == _sidebar) { [tv deselectRowAtIndexPath:ip animated:YES]; [self go:_places[ip.section][@"rows"][ip.row][@"p"]]; return; }
}
// (the list's and the icons' own selection by touch stays out: -dm_click: decides, -dm_showSelection shows it)
- (NSIndexPath *)tableView:(UITableView *)tv willSelectRowAtIndexPath:(NSIndexPath *)ip { return tv == _sidebar ? ip : nil; }
- (NSIndexPath *)tableView:(UITableView *)tv willDeselectRowAtIndexPath:(NSIndexPath *)ip { return tv == _sidebar ? ip : nil; }
- (BOOL)collectionView:(UICollectionView *)cv shouldSelectItemAtIndexPath:(NSIndexPath *)ip { return NO; }
- (BOOL)collectionView:(UICollectionView *)cv shouldDeselectItemAtIndexPath:(NSIndexPath *)ip { return NO; }
// A click in the results moves the keyboard to them, as on a Mac: typing in Search ends, the search stays (Cmd-Delete after a tap on a result
// deleted the search text instead of trashing the item, M1 30 Sep).
- (void)dm_endSearchTyping {
    if (![self dm_typingInSearch]) return;
    [_search.searchTextField resignFirstResponder]; [_search resignFirstResponder];
    if (gNativeActive == self && !gNativeLayer.rootViewController.presentedViewController) [gNativeKeys becomeFirstResponder];
}
- (void)tableView:(UITableView *)tv didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    if (tv == _list && ip.row < (NSInteger)_items.count) DMFinderThumbCancel(_items[ip.row], 18.0);   // (scrolled away before its thumbnail was made)
}
- (void)collectionView:(UICollectionView *)cv didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)ip {
    if (ip.item < (NSInteger)_items.count) DMFinderThumbCancel(_items[ip.item], 56.0);
}
// icons
- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"i" forIndexPath:ip];
    UIImageView *iv = [cell.contentView viewWithTag:1]; UILabel *l = [cell.contentView viewWithTag:2];
    if (!iv) {
        iv = [[UIImageView alloc] initWithFrame:CGRectMake(20, 4, 56, 56)]; iv.tag = 1; iv.contentMode = UIViewContentModeScaleAspectFit; iv.accessibilityIgnoresInvertColors = YES; [cell.contentView addSubview:iv];
        l = [[UILabel alloc] initWithFrame:CGRectMake(0, 62, 96, 32)]; l.tag = 2; l.font = [UIFont systemFontOfSize:11.0]; l.numberOfLines = 2; l.textAlignment = NSTextAlignmentCenter; l.lineBreakMode = NSLineBreakByTruncatingMiddle; [cell.contentView addSubview:l];
        UIView *sel = [UIView new]; sel.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.25]; sel.layer.cornerRadius = 8.0; cell.selectedBackgroundView = sel;
    }
    DMFinderItem *it = _items[ip.item];
    __weak UICollectionView *wcv = cv;
    iv.image = DMFinderThumb(it, 56.0, ^{ if (ip.item < [wcv numberOfItemsInSection:0]) [wcv reloadItemsAtIndexPaths:@[ip]]; }) ?: DMFinderIconWithAlias(it, 56.0); l.text = it.display;
    l.textColor = it.locked ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    return cell;
}
// ---- the selection ---------------------------------------------------------------------------------------------------------------------------
// A click (tap or pointer click, -dm_click:): on an item it selects only that item, and a second one on it within the double-click time opens it;
// with Command (or in Select mode) it adds or removes the item; with Shift it selects from the anchor to it; on empty space it clears the
// selection. Command-A selects all; a pointer drag from empty space draws a selection rectangle. Every action on "the selection" takes them all.
- (void)dm_setSelection:(NSArray<NSString *> *)paths anchor:(NSString *)anchor {
    [_sel removeAllObjects]; [_sel addObjectsFromArray:paths ?: @[]];
    _selected = anchor ?: _sel.lastObject;
    [self dm_showSelection];
}
- (BOOL)dm_isSelected:(DMFinderItem *)it { return it && [_sel containsObject:it.path]; }
- (void)dm_showSelection {
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        BOOL on = [_sel containsObject:_items[i].path];
        NSIndexPath *r = [NSIndexPath indexPathForRow:i inSection:0], *c = [NSIndexPath indexPathForItem:i inSection:0];
        if (i < [_list numberOfRowsInSection:0]) { if (on) [_list selectRowAtIndexPath:r animated:NO scrollPosition:UITableViewScrollPositionNone]; else [_list deselectRowAtIndexPath:r animated:NO]; }
        if (i < [_grid numberOfItemsInSection:0]) { if (on) [_grid selectItemAtIndexPath:c animated:NO scrollPosition:UICollectionViewScrollPositionNone]; else [_grid deselectItemAtIndexPath:c animated:NO]; }
    }
    NSUInteger n = [self dm_selectedItems].count;
    _status.text = n > 1 ? [NSString stringWithFormat:@"%lu of %lu selected", (unsigned long)n, (unsigned long)_items.count] : _statusBase;
}
- (void)dm_scrollToPath:(NSString *)path {
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) if ([_items[i].path isEqualToString:path]) {
        if (_icons) [_grid scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0] atScrollPosition:UICollectionViewScrollPositionNone animated:NO];
        else [_list scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] atScrollPosition:UITableViewScrollPositionNone animated:NO];
        return;
    }
}
- (UIKeyModifierFlags)dm_clickFlags:(UIGestureRecognizer *)g {
    UIKeyModifierFlags m = 0;
    if (@available(iOS 13.4, *)) m = g.modifierFlags;
#if DEBUG
    if (DMTestFlag("/tmp/msb-fclick-cmd")) m |= UIKeyModifierCommand;     // (tests: a click with Command / Shift held, where the injected keys
    if (DMTestFlag("/tmp/msb-fclick-shift")) m |= UIKeyModifierShift;     //  and touches can't be sent together)
#endif
    return m;
}
- (void)dm_click:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    if (_pressHappened) { _pressHappened = NO; return; }   // (the end of a hold -- its menu or its drag -- is not a click)
    if (_renameField && CGRectContainsPoint(_renameField.frame, [g locationInView:g.view])) return;   // (a click in the name being edited: the field's)
    [self dm_endRename:YES];   // (a click elsewhere: the new name is kept, as on a Mac)
    [self dm_endSearchTyping];
    DMFinderItem *it = [self itemAt:[g locationInView:g.view] in:g.view];
    UIKeyModifierFlags m = [self dm_clickFlags:g];
    BOOL cmd = (m & UIKeyModifierCommand) || _selectMode, shift = (m & UIKeyModifierShift) != 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (!it) { if (!cmd && !shift) [self dm_setSelection:@[] anchor:nil]; _lastClickPath = nil; return; }
    NSInteger to = [_items indexOfObject:it], from = NSNotFound;
    for (NSInteger i = 0; _selected && i < (NSInteger)_items.count; i++) if ([_items[i].path isEqualToString:_selected]) from = i;
    if (shift && from != NSNotFound && to != NSNotFound) {   // (the range from the anchor is added to what is selected)
        NSMutableOrderedSet *s = [_sel mutableCopy];
        for (NSInteger i = MIN(from, to); i <= MAX(from, to); i++) [s addObject:_items[i].path];
        NSString *anchor = _selected;
        [self dm_setSelection:s.array anchor:anchor];
    } else if (cmd) {
        NSMutableOrderedSet *s = [_sel mutableCopy];
        if ([s containsObject:it.path]) [s removeObject:it.path]; else [s addObject:it.path];
        [self dm_setSelection:s.array anchor:it.path];
    } else {
        BOOL again = [_lastClickPath isEqualToString:it.path] && now - _lastClickAt < 0.45;   // (a double click / double tap: Open, as on a Mac)
        [self dm_setSelection:@[it.path] anchor:it.path];
        if (again) { _lastClickPath = nil; DMLog([NSString stringWithFormat:@"[finder] double click: open %@", it.kind]); [self open:it]; return; }
    }
    _lastClickPath = it.path; _lastClickAt = now;
    if ([self dm_selectedItems].count > 1) DMLog([NSString stringWithFormat:@"[finder] selection: %lu items", (unsigned long)[self dm_selectedItems].count]);
}
- (void)dm_selectAll { NSArray *all = [_items valueForKey:@"path"]; [self dm_setSelection:all anchor:all.firstObject]; DMLog([NSString stringWithFormat:@"[finder] select all: %lu items", (unsigned long)all.count]); }
- (void)dm_toggleSelectMode {
    _selectMode = !_selectMode;
    [_selectButton setTitle:_selectMode ? @"Done" : @"Select" forState:UIControlStateNormal];
    _selectButton.tintColor = _selectMode ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    DMLog([NSString stringWithFormat:@"[finder] Select mode %@", _selectMode ? @"on" : @"off"]);
}
// A pointer's drag from empty space: a selection rectangle; the items it touches are selected (with Command / Shift, added to the selection).
- (void)dm_band:(UIPanGestureRecognizer *)g {
    UIScrollView *v = (UIScrollView *)g.view;
    CGPoint p = [g locationInView:v];
    if (g.state == UIGestureRecognizerStateBegan) {
        _bandStart = p;
        UIKeyModifierFlags m = [self dm_clickFlags:g];
        _bandBase = (m & (UIKeyModifierCommand | UIKeyModifierShift)) ? [_sel copy] : [NSOrderedSet orderedSet];
        if ([v isKindOfClass:[UIScrollView class]]) { v.panGestureRecognizer.enabled = NO; v.panGestureRecognizer.enabled = YES; }   // (the list does not scroll under the rectangle)
        _band = [UIView new]; _band.userInteractionEnabled = NO;
        _band.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.15];
        _band.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.6].CGColor; _band.layer.borderWidth = 1.0;
        [v addSubview:_band];
    }
    CGRect r = CGRectMake(MIN(p.x, _bandStart.x), MIN(p.y, _bandStart.y), fabs(p.x - _bandStart.x), fabs(p.y - _bandStart.y));
    _band.frame = r;
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        NSMutableOrderedSet *s = [_bandBase mutableCopy] ?: [NSMutableOrderedSet orderedSet];
        for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
            CGRect f = v == _list ? [_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]] : [_grid layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame;
            if (v == _list) f.size.width = MIN(f.size.width, 44.0 + DMFinderColumns(_list.bounds.size.width).nameW);   // (a row counts by its name, as on a Mac)
            if (CGRectIntersectsRect(f, r)) [s addObject:_items[i].path];
        }
        [self dm_setSelection:s.array anchor:_selected];
        return;
    }
    [_band removeFromSuperview]; _band = nil; _bandBase = nil;
    DMLog([NSString stringWithFormat:@"[finder] selection rectangle: %lu items", (unsigned long)[self dm_selectedItems].count]);
}

// ---- actions --------------------------------------------------------------------------------------------------------------------------------
- (DMFinderItem *)dm_selectedItem {   // (the anchor when it is selected, else the first selected item)
    NSArray<DMFinderItem *> *all = [self dm_selectedItems];
    for (DMFinderItem *it in all) if ([it.path isEqualToString:_selected]) return it;
    return all.firstObject;
}
- (NSArray<DMFinderItem *> *)dm_selectedItems { NSMutableArray *a = [NSMutableArray array]; for (DMFinderItem *it in _items) if ([_sel containsObject:it.path]) [a addObject:it]; return a; }
- (NSArray<NSString *> *)dm_selectedPaths { return [[self dm_selectedItems] valueForKey:@"path"]; }
- (void)dm_newFolder { [self newFolder]; }
- (void)dm_openSelected { for (DMFinderItem *it in [self dm_selectedItems]) [self open:it]; }
- (void)dm_quickLookSelected { DMFinderItem *it = [self dm_selectedItems].firstObject; if (it) [self quickLook:it]; }
- (void)dm_infoSelected { for (DMFinderItem *it in [self dm_selectedItems]) [self getInfo:it]; }
- (void)dm_renameSelected { if ([self dm_selectedItems].count != 1) return; DMFinderItem *it = [self dm_selectedItem]; if (it) [self dm_rename:it]; }
- (void)dm_duplicateSelected { NSArray *p = [self dm_selectedPaths]; if (p.count) [self dm_duplicateItems:p]; }
- (void)dm_trashSelected {   // (Command-Delete: Move to Trash; in the Trash, Put Back -- as on a Mac)
    NSArray *p = [self dm_selectedPaths]; if (!p.count) return;
    if ([self.path isEqualToString:kFinderTrash] || DMFinderInTrash(self.path)) [self dm_putBackItems:p]; else [self dm_trashItems:p];
}
- (void)dm_setIcons:(BOOL)icons { if (_icons != icons) [self toggleView]; }
- (BOOL)dm_showsHidden { return _hidden; }
- (void)dm_toggleHidden { _hidden = !_hidden; [self refresh]; }
// Keys, with a hardware keyboard, while this window is the active one (the layer's first responder asks, NativeWindow.h): a Mac Finder's.
- (void)dm_selectStep:(NSInteger)d {
    if (!_items.count) return;
    NSInteger i = -1; for (NSInteger k = 0; k < (NSInteger)_items.count; k++) if ([_items[k].path isEqualToString:_selected]) i = k;
    i = MAX(0, MIN((NSInteger)_items.count - 1, i < 0 ? 0 : i + d));
    [self dm_setSelection:@[_items[i].path] anchor:_items[i].path];
    [self dm_scrollToPath:_items[i].path];
}
- (NSArray<UIKeyCommand *> *)dm_keyCommands {
    static NSArray *cmds; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        void (^K)(NSString *, UIKeyModifierFlags, NSString *) = ^(NSString *in, UIKeyModifierFlags m, NSString *sel) {
            UIKeyCommand *k = [UIKeyCommand keyCommandWithInput:in modifierFlags:m action:NSSelectorFromString(sel)];
            if (@available(iOS 15.0, *)) k.wantsPriorityOverSystemBehavior = YES;
            [a addObject:k];
        };
        K(@"n", UIKeyModifierCommand, @"dm_keyNewWindow:"); K(@"n", UIKeyModifierCommand | UIKeyModifierShift, @"dm_keyNewFolder:");
        K(@"o", UIKeyModifierCommand, @"dm_keyOpen:"); K(UIKeyInputDownArrow, UIKeyModifierCommand, @"dm_keyOpen:"); K(@"\r", 0, @"dm_keyRename:");
        K(@"g", UIKeyModifierCommand | UIKeyModifierShift, @"dm_keyGoToFolder:"); K(@"d", UIKeyModifierCommand | UIKeyModifierShift, @"dm_keyDesktop:");
        K(@" ", 0, @"dm_keyQuickLook:"); K(@"y", UIKeyModifierCommand, @"dm_keyQuickLook:");
        K(@"i", UIKeyModifierCommand, @"dm_keyInfo:"); K(@"d", UIKeyModifierCommand, @"dm_keyDuplicate:");
        K(@"\b", UIKeyModifierCommand, @"dm_keyTrash:");
        K(@"[", UIKeyModifierCommand, @"dm_keyBack:"); K(@"]", UIKeyModifierCommand, @"dm_keyForward:"); K(UIKeyInputUpArrow, UIKeyModifierCommand, @"dm_keyUp:");
        K(@"1", UIKeyModifierCommand, @"dm_keyIcons:"); K(@"2", UIKeyModifierCommand, @"dm_keyList:");
        K(@".", UIKeyModifierCommand | UIKeyModifierShift, @"dm_keyHidden:");
        K(@"f", UIKeyModifierCommand, @"dm_keyFind:"); K(@"w", UIKeyModifierCommand, @"dm_keyClose:");
        K(UIKeyInputUpArrow, 0, @"dm_keyPrev:"); K(UIKeyInputDownArrow, 0, @"dm_keyNext:"); K(UIKeyInputLeftArrow, 0, @"dm_keyPrev:"); K(UIKeyInputRightArrow, 0, @"dm_keyNext:");
        K(@"c", UIKeyModifierCommand, @"dm_keyCopy:"); K(@"v", UIKeyModifierCommand, @"dm_keyPaste:"); K(@"z", UIKeyModifierCommand, @"dm_keyUndo:");
        K(@"a", UIKeyModifierCommand, @"dm_keySelectAll:");
        cmds = a;
    });
    return [self dm_typingInSearch] || [self hasSheet] || _renameField ? @[] : cmds;   // (typing in Search: the field has the keys; a sheet: nothing behind it acts)
}
// Typing in Search: the search bar's own text field holds the typing, not the bar (a check on the bar never matched: Esc did nothing, iPad 2 30 Sep)
- (BOOL)dm_typingInSearch { return _search.isFirstResponder || _search.searchTextField.isFirstResponder; }
// The keys straight from SpringBoard's press handling (DMNativeHandlePress): the same shortcuts as -dm_keyCommands, matched on the key itself.
- (BOOL)dm_handleKey:(UIKey *)key {
    DM_FEATURE_MARK("finder-keys");
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
    BOOL cmd = m == UIKeyModifierCommand, cmdShift = m == (UIKeyModifierCommand | UIKeyModifierShift), none = m == 0;
    BOOL esc = key.keyCode == UIKeyboardHIDUsageKeyboardEscape && none;
    if (gNativeLayer.rootViewController.presentedViewController) return NO;
    if (esc && gOverlay && gOverlay.superview == gNativeRotator) { DMCloseOverlay(); return YES; }   // (an item menu open: Esc closes it, as on a Mac)
    if ([self hasSheet]) {   // (a sheet first -- also one opened while Search had the typing: Return confirms it, Esc cancels it)
        DMNativeSheet *sh = nil; for (UIView *v in self.subviews) if ([v isKindOfClass:[DMNativeSheet class]]) sh = (DMNativeSheet *)v;
        if (m & (UIKeyModifierCommand | UIKeyModifierControl)) return NO;   // (Command-H, Command-Tab and the system's own shortcuts are not swallowed)
        if (sh.field.isFirstResponder) {
            if (esc) { [sh dm_cancel]; return YES; }
            return NO;
        }
        if (key.keyCode == UIKeyboardHIDUsageKeyboardReturnOrEnter && none) { [sh dm_ok]; return YES; }
        if (esc) { [sh dm_cancel]; return YES; }
        return YES;   // (nothing else reaches the window behind its sheet)
    }
    if (_renameField) {   // (a name being edited in place: its field has the keys, except Return (rename) and Esc (keep the old name))
        if (esc) { [self dm_endRename:NO]; return YES; }
        if (key.keyCode == UIKeyboardHIDUsageKeyboardReturnOrEnter && none) { [self dm_endRename:YES]; return YES; }
        return NO;
    }
    if ([self dm_typingInSearch]) {   // (typing in Search: the field has the keys, except Esc -- it clears the search and ends the typing, as on a Mac -- and Command-W)
        if (esc) { _search.text = @""; [self applySearch]; [self dm_endSearchTyping]; return YES; }
        if (cmd && key.keyCode == UIKeyboardHIDUsageKeyboardW) { [self close]; return YES; }
        // (the window's own Command shortcuts work while Search types, as on a Mac -- not the text ones: Command-A / C / V / X / Z, arrows, Delete)
        long k = (long)key.keyCode;
        BOOL windowKey = (cmd && (k == UIKeyboardHIDUsageKeyboardN || k == UIKeyboardHIDUsageKeyboard1 || k == UIKeyboardHIDUsageKeyboard2 || k == UIKeyboardHIDUsageKeyboardOpenBracket
                                  || k == UIKeyboardHIDUsageKeyboardCloseBracket || k == UIKeyboardHIDUsageKeyboardM))
                      || (cmdShift && (k == UIKeyboardHIDUsageKeyboardG || k == UIKeyboardHIDUsageKeyboardD || k == UIKeyboardHIDUsageKeyboardN || k == UIKeyboardHIDUsageKeyboardPeriod));
        if (!windowKey) return NO;
    }
    switch ((long)key.keyCode) {
        case UIKeyboardHIDUsageKeyboardN: if (cmd) { [self dm_keyNewWindow:nil]; return YES; } if (cmdShift) { [self newFolder]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardO: if (cmd) { [self dm_openSelected]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardReturnOrEnter: if (none) { [self dm_renameSelected]; return YES; } break;   // (Return renames, as on a Mac; Command-O / Command-Down open)
        case UIKeyboardHIDUsageKeyboardG: if (cmdShift) { [self dm_goToFolder]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardSpacebar: if (none) { [self dm_quickLookSelected]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardY: if (cmd) { [self dm_quickLookSelected]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardI: if (cmd) { [self dm_infoSelected]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardD: if (cmd) { [self dm_duplicateSelected]; return YES; } if (cmdShift) { [self dm_keyDesktop:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: if (cmd) { [self dm_trashSelected]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardOpenBracket: if (cmd) { [self goBack]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardCloseBracket: if (cmd) { [self goForward]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardUpArrow: if (cmd) { [self goUp]; return YES; } if (none) { [self dm_selectStep:-1]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardDownArrow: if (cmd) { [self dm_openSelected]; return YES; } if (none) { [self dm_selectStep:1]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardLeftArrow: if (none) { [self dm_selectStep:-1]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardRightArrow: if (none) { [self dm_selectStep:1]; return YES; } break;
        case UIKeyboardHIDUsageKeyboard1: if (cmd) { [self dm_setIcons:YES]; return YES; } break;
        case UIKeyboardHIDUsageKeyboard2: if (cmd) { [self dm_setIcons:NO]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardPeriod: if (cmdShift) { [self dm_toggleHidden]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardF: if (cmd) { [self dm_focusSearch]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardW: if (cmd) { [self close]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardM: if (cmd) { [self minimize]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardC: if (cmd) { [self dm_keyCopy:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardEscape:
            if (none && _search.text.length) { _search.text = @""; [self applySearch]; return YES; }
            if (none) { DMNativeEscToApps(); return YES; }   // (nothing of Finder's to cancel: Esc ends the typing in the app window behind, as it does with that app in front)
            break;
        case UIKeyboardHIDUsageKeyboardV: if (cmd) { [self dm_keyPaste:nil]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardZ: if (cmd) { [self dm_undo]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardA: if (cmd) { [self dm_selectAll]; return YES; } break;
        default: break;
    }
    return NO;
}
- (void)dm_keyNewWindow:(id)k { DMFinderOpen(self.path, YES); }
- (void)dm_keyNewFolder:(id)k { [self newFolder]; }
- (void)dm_keyOpen:(id)k { [self dm_openSelected]; }
- (void)dm_keyQuickLook:(id)k { [self dm_quickLookSelected]; }
- (void)dm_keyInfo:(id)k { [self dm_infoSelected]; }
- (void)dm_keyDuplicate:(id)k { [self dm_duplicateSelected]; }
- (void)dm_keyTrash:(id)k { [self dm_trashSelected]; }
- (void)dm_keyBack:(id)k { [self goBack]; }
- (void)dm_keyForward:(id)k { [self goForward]; }
- (void)dm_keyUp:(id)k { [self goUp]; }
- (void)dm_keyIcons:(id)k { [self dm_setIcons:YES]; }
- (void)dm_keyList:(id)k { [self dm_setIcons:NO]; }
- (void)dm_keyHidden:(id)k { [self dm_toggleHidden]; }
- (void)dm_keyFind:(id)k { [self dm_focusSearch]; }
- (void)dm_focusSearch {
    if (!gNativeLayer.isKeyWindow) [gNativeLayer makeKeyWindow];
    BOOL ok = [_search.searchTextField becomeFirstResponder];
    DMLog([NSString stringWithFormat:@"[finder] search focus: %d (layer key %d, can %d)", ok, gNativeLayer.isKeyWindow, _search.searchTextField.canBecomeFirstResponder]);
}
- (void)dm_keyClose:(id)k { [self close]; }
- (void)dm_keyPrev:(id)k { [self dm_selectStep:-1]; }
- (void)dm_keyNext:(id)k { [self dm_selectStep:1]; }
- (void)dm_keyCopy:(id)k { NSArray *p = [self dm_selectedPaths]; if (p.count) gFinderClipboard = [p mutableCopy]; }
- (void)dm_keyPaste:(id)k { if (gFinderClipboard.count) [self paste]; }
- (void)dm_keyUndo:(id)k { [self dm_undo]; }
- (void)dm_keySelectAll:(id)k { [self dm_selectAll]; }
- (void)dm_keyRename:(id)k { [self dm_renameSelected]; }
- (void)dm_keyGoToFolder:(id)k { [self dm_goToFolder]; }
- (void)dm_keyDesktop:(id)k { NSString *d = DMFinderDesktopFolder(YES); if (d) [self go:d]; }   // (Go > Desktop, Shift-Command-D)
- (void)dm_shareNamed:(NSString *)name {   // (debug trigger fshare_<name>[|<bundle>]: Share to that app, or the list of apps in the log)
    NSArray *parts = [name componentsSeparatedByString:@"|"];
    for (DMFinderItem *it in _items) if ([it.name isEqualToString:parts[0]]) {
        if (parts.count > 1) DMFinderShareTo(@[it], parts[1], self);
        else DMLog([NSString stringWithFormat:@"[finder] share: the menu would offer %@", [DMFinderShareApps() componentsJoinedByString:@", "]]);
        return;
    }
}
- (void)dm_openNamed:(NSString *)name { for (DMFinderItem *it in _items) if ([it.name isEqualToString:name]) { [self open:it]; return; } }
- (void)dm_selectNamed:(NSString *)name { for (DMFinderItem *it in _items) if ([it.name isEqualToString:name]) { [self dm_setSelection:@[it.path] anchor:it.path]; return; } }
- (void)dm_toggleView { [self toggleView]; }
#if DEBUG
// Test machinery (the fdo_ trigger): select:<name>, trash, putback, dup, copy, paste, undo, newfolder, rename:<new name>, move:<folder>,
// copyto:<folder>, delete, empty, sheetok, sheetcancel, hidden. The same methods the menus, keys and drags call.
- (void)dm_debugDo:(NSString *)spec {
    NSRange c = [spec rangeOfString:@":"];
    NSString *act = c.location == NSNotFound ? spec : [spec substringToIndex:c.location], *arg = c.location == NSNotFound ? nil : [spec substringFromIndex:c.location + 1];
    NSArray *sel = [self dm_selectedPaths];
    DMLog([NSString stringWithFormat:@"[finder] test: %@ %@ (selected %@)", act, arg ?: @"", [[sel valueForKey:@"lastPathComponent"] componentsJoinedByString:@", "]]);
    if ([act isEqualToString:@"select"]) [self dm_selectNamed:arg];
    else if ([act isEqualToString:@"trash"]) [self dm_trashSelected];
    else if ([act isEqualToString:@"putback"]) [self dm_putBackItems:sel];
    else if ([act isEqualToString:@"dup"]) [self dm_duplicateSelected];
    else if ([act isEqualToString:@"copy"]) [self dm_keyCopy:nil];
    else if ([act isEqualToString:@"paste"]) [self dm_keyPaste:nil];
    else if ([act isEqualToString:@"undo"]) [self dm_undo];
    else if ([act isEqualToString:@"newfolder"]) [self newFolder];
    else if ([act isEqualToString:@"newtext"]) [self dm_newTextFile];
    else if ([act isEqualToString:@"rename"]) { if (sel.count) [self dm_renameItem:sel[0] to:arg]; }
    else if ([act isEqualToString:@"move"]) [self dm_moveItems:sel to:arg copy:NO];
    else if ([act isEqualToString:@"copyto"]) [self dm_moveItems:sel to:arg copy:YES];
    else if ([act isEqualToString:@"delete"]) [self dm_deleteItems:sel];
    else if ([act isEqualToString:@"empty"]) [self emptyTrash];
    else if ([act isEqualToString:@"hidden"]) [self dm_toggleHidden];
    else if ([act isEqualToString:@"drives"]) {   // (the drives now, the sidebar's Locations, and the policy for this folder -- names of drives only)
        DMFinderDrivesForget();
        for (NSDictionary *d in DMFinderDrives()) DMLog([NSString stringWithFormat:@"[finder] test drive: %@ at %@ from %@ type %@ fat %@ trash %@", d[@"t"], d[@"p"], d[@"from"], d[@"type"], d[@"fat"], DMFinderDriveTrash(d[@"p"])]);
        NSMutableArray *locs = [NSMutableArray array]; for (NSDictionary *r in _places.lastObject[@"rows"]) [locs addObject:[NSString stringWithFormat:@"%@%@", r[@"t"], r[@"drive"] ? @"(drive)" : @""]];
        DMLog([NSString stringWithFormat:@"[finder] test sidebar Locations: %@; here writable %d", [locs componentsJoinedByString:@", "], [self dm_canWriteHere]]);
    }
    else if ([act isEqualToString:@"policy"]) {   // policy:<path>: what the policy says about a path (item may change / folder may be written into / in a Trash)
        DMLog([NSString stringWithFormat:@"[finder] test policy %@: change %d writeinto %d intrash %d owntrash %d zone %d dest %d", arg, DMFinderCanChange(arg), DMFinderCanWriteInto(arg), DMFinderInTrash(arg), DMFinderInOwnTrash(arg), DMFinderItemZone(DMFinderRealItem(arg)), DMFinderDestZone(arg)]);
    }
    else if ([act isEqualToString:@"drivescheck"]) DMFinderDrivesCheck(@"test");   // (the check a mount event runs; with /tmp/msb-fdrive-hide the drives look unplugged)
    else if ([act isEqualToString:@"origin"]) { if (sel.count) DMLog([NSString stringWithFormat:@"[finder] test origin of %@: %@", [sel[0] lastPathComponent], DMFinderOrigin(sel[0]) ?: @"-"]); }
    else if ([act isEqualToString:@"closeothers"]) { for (DMNativeWindow *w in [gNativeWindows copy]) if (w != self) [w close]; }
    else if ([act isEqualToString:@"frame"]) { NSArray *n = [arg componentsSeparatedByString:@","]; if (n.count == 4) { self.layoutName = nil; self.restoreFrame = CGRectNull; self.frame = DMNativeClamp(CGRectMake([n[0] doubleValue], [n[1] doubleValue], [n[2] doubleValue], [n[3] doubleValue]), self.minSize); } }
    else if ([act isEqualToString:@"sheetok"] || [act isEqualToString:@"sheetcancel"]) {
        for (UIView *v in self.subviews) if ([v isKindOfClass:[DMNativeSheet class]]) {
            DMNativeSheet *sh = (DMNativeSheet *)v;
            UILabel *t = nil; for (UIView *x in sh.panel.subviews) for (UIView *y in x.subviews) if ([y isKindOfClass:[UILabel class]] && !t) t = (UILabel *)y;
            DMLog([NSString stringWithFormat:@"[finder] test: sheet \"%@\" -> %@", t.text, act]);
            if ([act isEqualToString:@"sheetok"]) [sh dm_ok]; else [sh dm_cancel];
        }
    }
    else if ([act isEqualToString:@"state"]) {   // (every Finder window's state, front last, for the test log -- names only in the test folders)
        for (DMNativeWindow *nw in gNativeWindows) if ([nw isKindOfClass:[DMFinderWindow class]]) { DMFinderWindow *w = (DMFinderWindow *)nw;
            UILabel *t = nil; for (UIView *v in w.subviews) if ([v isKindOfClass:[DMNativeSheet class]]) for (UIView *x in ((DMNativeSheet *)v).panel.subviews) for (UIView *y in x.subviews) if ([y isKindOfClass:[UILabel class]] && !t) t = (UILabel *)y;
            DMLog([NSString stringWithFormat:@"[finder] test state%@: %@ items %lu read-only %d selected %@ undo '%@' sheet '%@' status '%@' active %d frame %@", w == self ? @" (front)" : @"", w.path.lastPathComponent, (unsigned long)w->_items.count, ![w dm_canWriteHere], w->_selected.lastPathComponent ?: @"-", [w dm_canUndo] ? [w dm_undoTitle] : @"-", [w hasSheet] ? t.text : @"-", w->_status.text, w == gNativeActive, NSStringFromCGRect(w.frame)]); }
    }
}
#endif
- (void)dm_dump {
    DMLog([NSString stringWithFormat:@"[finder] dump: %@ -- icons %d, items %lu (%@), selected %@, search '%@' typing %d, undo %lu, sheet %d, frame %@",
           self.path, _icons, (unsigned long)_items.count, [[_items valueForKey:@"name"] componentsJoinedByString:@", "].length > 300 ? @"..." : [[_items valueForKey:@"name"] componentsJoinedByString:@", "],
           _selected.lastPathComponent ?: @"-", _search.text, [self dm_typingInSearch], (unsigned long)gFinderUndo.count, [self hasSheet], NSStringFromCGRect(self.frame)]);
}
- (void)open:(DMFinderItem *)it {
    if (it.cloud) { [self dm_download:it]; return; }
    if (it.app) { NSString *bid = [NSDictionary dictionaryWithContentsOfFile:[it.app stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"]; if (bid) { DMOpenApp(bid); return; } }
    if (it.dir && ![it.name hasSuffix:@".app"]) { [self go:it.path]; return; }
    if ([it.name hasSuffix:@".app"]) {   // an app: open it
        NSString *bid = [NSDictionary dictionaryWithContentsOfFile:[it.path stringByAppendingPathComponent:@"Info.plist"]][@"CFBundleIdentifier"];
        if (bid) { DMOpenApp(bid); return; }
    }
    if (!it.dir && !it.cloud && DMTextWindowOpen(it.path, ^{ [self quickLook:it]; })) return;   // (plain text: TextEdit's window; anything else Quick Look)
    [self quickLook:it];
}
// An iCloud file that is not downloaded: iCloud is asked to download it (the folder watch shows it when it is there).
- (void)dm_download:(DMFinderItem *)it {
    NSError *e = nil;
    BOOL ok = [[NSFileManager defaultManager] startDownloadingUbiquitousItemAtURL:[NSURL fileURLWithPath:it.path] error:&e];
    DMLog([NSString stringWithFormat:@"[finder] iCloud download of a file: %@", ok ? @"started" : e.localizedDescription]);
    if (ok) { _status.text = [NSString stringWithFormat:@"Downloading “%@” from iCloud…", it.name]; return; }
    [self sheetTitle:[NSString stringWithFormat:@"“%@” is in iCloud", it.name] message:@"It isn't downloaded to this iPad yet, and Finder can't download it. Open it once in the Files app to download it." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
}
- (void)quickLook:(DMFinderItem *)it { if (it.cloud) { [self dm_download:it]; return; } DMQuickLookOpen(it.path); }
- (void)alertTitle:(NSString *)t message:(NSString *)m field:(NSString *)fieldText action:(NSString *)a destructive:(BOOL)d then:(void (^)(NSString *text))then {
    [self sheetTitle:t message:m field:fieldText action:a destructive:d then:then];   // (a sheet in the window, not a UIKit alert: see NativeWindow.h)
}
- (void)fileWork:(NSString *)what work:(NSError *(^)(void))work {
    __weak DMFinderWindow *ws = self;
    dispatch_async(DMFinderFileQueue(), ^{
        NSError *e = nil;
        @try { e = work(); } @catch (NSException *x) { e = [NSError errorWithDomain:@"Finder" code:1 userInfo:@{NSLocalizedDescriptionKey: x.reason ?: @"?"}]; }
        dispatch_async(dispatch_get_main_queue(), ^{ DMFinderWindow *s = ws; if (e) [s fail:e what:what]; [s refresh]; });
    });
}
- (void)fail:(NSError *)e what:(NSString *)what {
    if (!e) return;
    NSString *title = [e.userInfo[@"title"] isKindOfClass:[NSString class]] ? e.userInfo[@"title"] : [NSString stringWithFormat:@"%@ didn't work", what];
    [self alertTitle:title message:e.localizedDescription field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
}
// The protected-path policy, before an operation (verb: trash, move, copy, rename, duplicate, newfolder): outside the user's own places a sheet
// says no and nothing happens (no sheet can override it); an item into itself or an iCloud file not downloaded is refused too; iCloud Drive's
// Trash is asked about (it removes the item from iCloud Drive on every device); otherwise `go` runs at once.
- (void)dm_guard:(NSString *)verb paths:(NSArray<NSString *> *)paths into:(NSString *)dir then:(void (^)(void))go {
    DM_FEATURE_MARK("finder-file-safety");
    BOOL itemsMatter = [@[@"trash", @"move", @"rename"] containsObject:verb], destMatters = [@[@"move", @"copy", @"duplicate", @"newfolder", @"newfile"] containsObject:verb];
    NSString *verbPast = @{@"trash": @"moved to the Trash", @"move": @"moved", @"copy": @"copied", @"rename": @"renamed", @"duplicate": @"duplicated", @"newfolder": @"made", @"newfile": @"made"}[verb] ?: verb;
    NSString *own = @"Finder only changes your own files: On My iPad, Documents, iCloud Drive and each app's Documents folder. You can still copy from here into them.";
    BOOL icloudTrash = NO;
    for (NSString *p in paths) {
        if (!DMFinderTaken(p)) {
            NSString *stub = [p.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.icloud", p.lastPathComponent]];
            NSString *why = DMFinderTaken(stub) ? @"It is in iCloud and not downloaded to this iPad yet. Open it first to download it." : @"It is no longer there.";
            [self sheetTitle:[NSString stringWithFormat:@"“%@” can't be %@", p.lastPathComponent, verbPast] message:why field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        if (dir && [@[@"move", @"copy"] containsObject:verb] && DMFinderIntoItself(p, dir)) {
            [self sheetTitle:[NSString stringWithFormat:@"“%@” can't be %@ into itself", p.lastPathComponent, verbPast] message:nil field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        if (itemsMatter && !DMFinderCanChange(p)) {
            DMLog([NSString stringWithFormat:@"[finder] policy: %@ refused (outside the user's places)", verb]);
            [self sheetTitle:[NSString stringWithFormat:@"“%@” can't be %@", p.lastPathComponent, verbPast] message:own field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        if ([verb isEqualToString:@"trash"] && DMFinderInICloud(p)) icloudTrash = YES;
    }
    if (destMatters && !DMFinderCanWriteInto(dir)) {
        DMLog([NSString stringWithFormat:@"[finder] policy: %@ refused (the folder is outside the user's places)", verb]);
        NSString *title = [verb isEqualToString:@"newfolder"] ? [NSString stringWithFormat:@"A folder can't be made in “%@”", dir.lastPathComponent]
                        : [verb isEqualToString:@"newfile"] ? [NSString stringWithFormat:@"A file can't be made in “%@”", dir.lastPathComponent]
                        : [NSString stringWithFormat:@"%@ can't be %@ into “%@”", paths.count == 1 ? [NSString stringWithFormat:@"“%@”", [paths.firstObject lastPathComponent]] : @"Items", verbPast, dir.lastPathComponent];
        [self sheetTitle:title message:DMFinderInOwnTrash(dir) ? @"Only Move to Trash puts items into the Trash." : own field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
        return;
    }
    if (icloudTrash) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:DMFinderICloudTrash()]) {
            [self sheetTitle:[NSString stringWithFormat:@"%@ can't be moved to the Trash here", DMFinderNames(paths)] message:@"iCloud Drive's Trash isn't on this iPad. Use the Files app to delete iCloud Drive items." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        [self sheetTitle:[NSString stringWithFormat:@"Move %@ to the iCloud Drive Trash?", DMFinderNames(paths)] message:@"It is removed from iCloud Drive on all your devices. Undo (Command-Z) or Put Back brings it back."
                   field:nil action:@"Move to Trash" destructive:YES then:^(NSString *t) { go(); }];
        return;
    }
    go();
}
// Can this window change its folder / its selected items (menus grey out what can't be done here, as on a Mac for a read-only place)?
- (BOOL)dm_canWriteHere { return DMFinderCanWriteInto(self.path); }
- (BOOL)dm_canChangeSelection { NSArray *p = [self dm_selectedPaths]; if (!p.count) return NO; for (NSString *x in p) if (!DMFinderCanChange(x)) return NO; return YES; }
// The engine of the operations: kind move / copy / paste / duplicate / trash / putback on the file queue, then Undo, the windows showing the
// changed folders read them again, and this window selects what was made.
- (void)dm_run:(NSString *)kind what:(NSString *)what paths:(NSArray<NSString *> *)paths into:(NSString *)dir undoable:(BOOL)undoable {
    DM_FEATURE_MARK("finder-file-ops");
    __weak DMFinderWindow *ws = self;
    NSString *here = self.path;
    NSMutableDictionary<NSString *, NSString *> *deskPlaces = [NSMutableDictionary dictionary];   // (Move to Trash: where each item was on the desktop)
    if ([kind isEqualToString:@"trash"] && gFinderDesktopPlaceFor) for (NSString *src in paths) { NSString *pl = gFinderDesktopPlaceFor(src); if (pl) deskPlaces[src] = pl; }
    dispatch_async(DMFinderFileQueue(), ^{
        NSMutableArray *pairs = [NSMutableArray array]; NSMutableSet *touched = [NSMutableSet set]; NSError *first = nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *src in paths) {
            NSString *dst = nil, *name = src.lastPathComponent; BOOL copy = NO; NSError *e = nil;
            if ([kind isEqualToString:@"move"]) dst = DMFinderFreeName(dir, name, @"");
            else if ([kind isEqualToString:@"copy"] || [kind isEqualToString:@"paste"]) {
                BOOL sameFolder = [DMFinderReal(src.stringByDeletingLastPathComponent) isEqualToString:DMFinderReal(dir)];
                dst = DMFinderFreeName(dir, name, sameFolder || [kind isEqualToString:@"paste"] ? @"copy" : @""); copy = YES;
            } else if ([kind isEqualToString:@"duplicate"]) { dst = DMFinderFreeName(src.stringByDeletingLastPathComponent, name, @"copy"); copy = YES; }
            else if ([kind isEqualToString:@"trash"]) {
                NSString *t = DMFinderTrashFor(src);
                e = DMFinderPrepareTrash(t);
                if (!e) dst = DMFinderFreeName(t, name, @"");
            } else if ([kind isEqualToString:@"putback"]) {
                NSString *origin = DMFinderOrigin(src);
                if (!DMFinderCanChange(src)) e = DMFinderError([NSString stringWithFormat:@"“%@” can't be moved: it is outside your own files.", name]);   // (reached through an alias in the Trash)
                else if (!origin.length) e = DMFinderError([NSString stringWithFormat:@"Where “%@” came from isn't known.", name]);
                else if (![fm fileExistsAtPath:origin.stringByDeletingLastPathComponent]) e = DMFinderError([NSString stringWithFormat:@"The folder “%@” it came from is no longer there.", origin.stringByDeletingLastPathComponent.lastPathComponent]);
                else dst = DMFinderFreeName(origin.stringByDeletingLastPathComponent, origin.lastPathComponent, @"");
            }
            if (!e && dst && [kind isEqualToString:@"putback"] && !DMFinderCanWriteInto(dst.stringByDeletingLastPathComponent))   // (the origin is only a note on the item: it never leads outside the user's places)
                e = DMFinderError([NSString stringWithFormat:@"“%@” can't be put back there: that place is outside your own files.", name]);
            // (a move to another volume -- the iPad and a drive -- is a copy and a delete: it needs the room and the size rules of a copy)
            BOOL otherVolume = NO;
            if (!e && dst && !copy && [@[@"move", @"putback"] containsObject:kind]) {
                struct stat a, b; otherVolume = lstat(src.fileSystemRepresentation, &a) == 0 && stat(dst.stringByDeletingLastPathComponent.fileSystemRepresentation, &b) == 0 && a.st_dev != b.st_dev;
            }
            NSDictionary *fat = !e && dst && (copy || otherVolume) ? DMFinderFATDriveOf(dst.stringByDeletingLastPathComponent) : nil;
            NSString *big = fat ? DMFinderTooBigForFAT(src) : nil;
            if (big) {   // (FAT32 stores no file over 4 GB: refused before anything is written, never a half-written file on the drive)
                DMLog(@"[finder] drive: refused, a file over 4 GB onto a FAT32 drive");
                e = [NSError errorWithDomain:@"Finder" code:3 userInfo:@{@"title": [NSString stringWithFormat:@"“%@” can't be %@ to “%@”", name, copy ? @"copied" : @"moved", fat[@"t"]],
                     NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ is larger than 4 GB. The drive is formatted as FAT32, which can't store files larger than 4 GB.", [big isEqualToString:name] ? @"It" : [NSString stringWithFormat:@"“%@” in it", big]]}];
            }
            if (!e && dst && (copy || otherVolume)) {   // (room for it, before a copy starts -- a clone takes none, but a copy to another volume does)
                struct stat st; BOOL isDir = lstat(src.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode);
                unsigned long long need = isDir ? (unsigned long long)MAX(0LL, DMFDFolderSize(src, DMFinderFreeSpace(dst.stringByDeletingLastPathComponent))) : (unsigned long long)st.st_size;
                // (the 200 MB margin protects the iPad's own storage; a drive may be filled to the brim -- a 1 KB copy onto a small stick was
                //  refused, logic test 1.2.3)
                unsigned long long margin = DMFinderDriveRoot(DMFinderReal(dst.stringByDeletingLastPathComponent)) ? 0 : 200ULL * 1024 * 1024;
                if (need + margin > DMFinderFreeSpace(dst.stringByDeletingLastPathComponent)) e = DMFinderError([NSString stringWithFormat:@"There isn't enough free space for “%@”.", name]);
            }
            if (!e && dst) e = DMFinderDriveGoneError(DMFinderTransfer(src, dst, copy), @[src, dst]);
            if (!e && dst) {
                if ([kind isEqualToString:@"trash"]) { DMFinderSetOrigin(dst, DMFinderNorm(src)); DMFinderSetDesktopPlace(dst, deskPlaces[src]); }
                if ([kind isEqualToString:@"putback"]) DMFinderSetOrigin(dst, nil);
                [pairs addObject:@[DMFinderNorm(src), DMFinderNorm(dst)]];
                [touched addObject:src.stringByDeletingLastPathComponent]; [touched addObject:dst.stringByDeletingLastPathComponent];
            }
            if (e && !first) first = e;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            DMFinderWindow *s = ws;
            DMLog([NSString stringWithFormat:@"[finder] %@: %lu of %lu done%@", kind, (unsigned long)pairs.count, (unsigned long)paths.count, first ? [@", error: " stringByAppendingString:first.localizedDescription] : @""]);
            if (undoable) DMFinderPushUndo(kind, what, pairs);
            NSMutableArray *made = [NSMutableArray array];
            for (NSArray *pr in pairs) if ([DMFinderNorm([pr[1] stringByDeletingLastPathComponent]) isEqualToString:DMFinderNorm(here)]) [made addObject:pr[1]];
            if (made.count && ![kind isEqualToString:@"trash"]) [s dm_selectPathsWhenListed:made];
            DMFinderRefreshFolders(touched);
            if (first) [s fail:first what:what];
        });
    });
}
- (void)dm_moveItems:(NSArray<NSString *> *)paths to:(NSString *)dir copy:(BOOL)copy {
    NSMutableArray *todo = [NSMutableArray array];
    NSString *rd = DMFinderReal(dir);
    for (NSString *p in paths) if (copy || ![DMFinderReal(p.stringByDeletingLastPathComponent) isEqualToString:rd]) [todo addObject:p];   // (a move where it already is: nothing)
    if (!todo.count || !dir.length) return;
    if (!copy && [DMFinderReal(dir) isEqualToString:kFinderTrash]) { [self dm_trashItems:todo]; return; }   // (onto the Trash: Move to Trash, with Put Back)
    __weak DMFinderWindow *ws = self;
    [self dm_guard:copy ? @"copy" : @"move" paths:todo into:dir then:^{ [ws dm_run:copy ? @"copy" : @"move" what:copy ? @"Copy" : @"Move" paths:todo into:dir undoable:YES]; }];
}
- (void)dm_trashItems:(NSArray<NSString *> *)paths {
    if (!paths.count) return;
    NSMutableArray *inTrash = [NSMutableArray array], *todo = [NSMutableArray array];
    for (NSString *p in paths) [DMFinderInOwnTrash(p) ? inTrash : todo addObject:p];
    if (inTrash.count) { [self dm_deleteItems:inTrash]; return; }   // (already in the Trash: Delete Immediately, asked first)
    __weak DMFinderWindow *ws = self;
    [self dm_guard:@"trash" paths:todo into:nil then:^{ [ws dm_run:@"trash" what:@"Move to Trash" paths:todo into:nil undoable:YES]; }];
}
- (void)dm_duplicateItems:(NSArray<NSString *> *)paths {
    if (!paths.count) return;
    __weak DMFinderWindow *ws = self;
    [self dm_guard:@"duplicate" paths:paths into:[paths.firstObject stringByDeletingLastPathComponent] then:^{ [ws dm_run:@"duplicate" what:@"Duplicate" paths:paths into:nil undoable:YES]; }];
}
- (void)dm_putBackItems:(NSArray<NSString *> *)paths {
    NSMutableArray *todo = [NSMutableArray array];
    for (NSString *p in paths) if (DMFinderInTrash(p)) [todo addObject:p];
    if (todo.count) [self dm_run:@"putback" what:@"Put Back" paths:todo into:nil undoable:YES];
}
- (void)dm_deleteItems:(NSArray<NSString *> *)paths {
    if (!paths.count) return;
    for (NSString *p in paths) if (!DMFinderInOwnTrash(p)) {   // (Delete Immediately exists only in Finder's own Trash)
        [self sheetTitle:[NSString stringWithFormat:@"“%@” can't be deleted here", p.lastPathComponent] message:@"Finder deletes items only from its own Trash. Items in iCloud Drive's Trash can be deleted in the Files app." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
        return;
    }
    __weak DMFinderWindow *ws = self;
    [self alertTitle:[NSString stringWithFormat:@"Delete %@ immediately?", DMFinderNames(paths)] message:@"You can't undo this action." field:nil action:@"Delete" destructive:YES then:^(NSString *t) {
        [ws fileWork:@"Delete" work:^NSError *{ NSError *first = nil; for (NSString *p in paths) { NSError *e = DMFinderRemove(p); if (e && !first) first = e; } return first; }];
    }];
}
- (void)dm_renameItem:(NSString *)path to:(NSString *)name {
    if (!name.length || [name isEqualToString:path.lastPathComponent] || [name isEqualToString:@"."] || [name isEqualToString:@".."]) return;
    if ([name containsString:@"/"]) {   // (a name, never a path: it was ignored without a word and the old name came back)
        [self sheetTitle:[NSString stringWithFormat:@"The name “%@” can't be used", name] message:@"A name can't contain “/”. Please choose another name." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
        return;
    }
    if ([name hasPrefix:@"."] && ![path.lastPathComponent hasPrefix:@"."]) {   // (a leading dot hides the item: it seemed gone. A Mac refuses it too)
        [self sheetTitle:@"You can't use a name that begins with a dot “.”" message:@"These names are reserved for the system. Please choose another name." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
        return;
    }
    NSString *dst = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
    __weak DMFinderWindow *ws = self;
    [self dm_guard:@"rename" paths:@[path] into:nil then:^{
        if (DMFinderTaken(dst) && ![dst.lowercaseString isEqualToString:path.lowercaseString]) {
            [ws sheetTitle:[NSString stringWithFormat:@"The name “%@” is already taken", name] message:@"Please choose a different name." field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        dispatch_async(DMFinderFileQueue(), ^{
            NSError *e = DMFinderDriveGoneError(DMFinderTransfer(path, dst, NO), @[path]);
            dispatch_async(dispatch_get_main_queue(), ^{
                DMFinderWindow *s = ws;
                if (e) { [s fail:e what:@"Rename"]; return; }
                DMFinderPushUndo(@"rename", @"Rename", @[@[DMFinderNorm(path), DMFinderNorm(dst)]]);
                if ([s dm_selectedItem] && [[s dm_selectedItem].path isEqualToString:DMFinderNorm(path)]) [s dm_selectPathsWhenListed:@[DMFinderNorm(dst)]];
                DMFinderRefreshFolders([NSSet setWithObject:path.stringByDeletingLastPathComponent]);
            });
        });
    }];
}
- (void)dm_pasteInto:(NSString *)dir {
    NSArray *srcs = [gFinderClipboard copy];
    if (!srcs.count || !dir.length) return;
    __weak DMFinderWindow *ws = self;
    [self dm_guard:@"copy" paths:srcs into:dir then:^{ [ws dm_run:@"paste" what:@"Paste" paths:srcs into:dir undoable:YES]; }];
}
- (BOOL)dm_canUndo { return gFinderUndo.count > 0; }
- (NSString *)dm_undoTitle { NSString *w = gFinderUndo.lastObject[@"what"]; return w ? [@"Undo " stringByAppendingString:w] : @"Undo"; }
- (void)dm_undo {
    NSDictionary *u = gFinderUndo.lastObject;
    if (!u) return;
    [gFinderUndo removeLastObject];
    DM_FEATURE_MARK("finder-undo");
    NSString *kind = u[@"kind"]; NSArray *pairs = u[@"pairs"];
    BOOL back = [@[@"move", @"rename", @"trash", @"putback"] containsObject:kind];
    __weak DMFinderWindow *ws = self;
    NSString *here = self.path;
    dispatch_async(DMFinderFileQueue(), ^{
        NSMutableSet *touched = [NSMutableSet set]; NSMutableArray *made = [NSMutableArray array]; NSError *first = nil; NSUInteger n = 0;
        for (NSArray *pr in [pairs reverseObjectEnumerator]) {
            NSString *src = pr[0], *dst = pr[1]; NSError *e = nil;
            if (!DMFinderTaken(dst)) continue;   // (gone since: nothing to undo for it)
            // (what Undo moves is held to the same rule as every other move: a folder on its way that became an alias since can't lead it outside)
            if (!DMFinderCanChange(dst)) { if (!first) first = DMFinderError([NSString stringWithFormat:@"“%@” is outside your own files now.", dst.lastPathComponent]); continue; }
            NSString *to = nil;
            if (back) {   // (it goes back where it was)
                if (![[NSFileManager defaultManager] fileExistsAtPath:src.stringByDeletingLastPathComponent]) { if (!first) first = DMFinderError([NSString stringWithFormat:@"The folder “%@” is no longer there.", src.stringByDeletingLastPathComponent.lastPathComponent]); continue; }
                if (!DMFinderCanWriteInto(src.stringByDeletingLastPathComponent) && !DMFinderInTrash(src)) { if (!first) first = DMFinderError(@"That place is outside your own files."); continue; }
                to = DMFinderTaken(src) ? DMFinderFreeName(src.stringByDeletingLastPathComponent, src.lastPathComponent, @"") : src;
            } else {      // (what the operation made goes to the Trash)
                NSString *t = DMFinderTrashFor(dst);
                NSError *te = DMFinderPrepareTrash(t);
                if (te) { if (!first) first = te; continue; }
                to = DMFinderFreeName(t, dst.lastPathComponent, @"");
            }
            e = DMFinderDriveGoneError(DMFinderTransfer(dst, to, NO), @[dst, to]);
            if (e) { if (!first) first = e; continue; }
            if ([kind isEqualToString:@"trash"]) DMFinderSetOrigin(to, nil);
            else if ([kind isEqualToString:@"putback"]) DMFinderSetOrigin(to, dst);
            else if (!back) DMFinderSetOrigin(to, dst);
            n++; [made addObject:to];
            [touched addObject:dst.stringByDeletingLastPathComponent]; [touched addObject:to.stringByDeletingLastPathComponent];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            DMFinderWindow *s = ws;
            DMLog([NSString stringWithFormat:@"[finder] undo %@: %lu of %lu%@", kind, (unsigned long)n, (unsigned long)pairs.count, first ? [@", error: " stringByAppendingString:first.localizedDescription] : @""]);
            NSMutableArray *sel = [NSMutableArray array];
            for (NSString *m in made) if ([DMFinderNorm(m.stringByDeletingLastPathComponent) isEqualToString:DMFinderNorm(here)]) [sel addObject:m];
            if (sel.count && back) [s dm_selectPathsWhenListed:sel];
            DMFinderRefreshFolders(touched);
            if (first) [s fail:first what:[u[@"what"] stringByAppendingString:@" (Undo)"]];
        });
    });
}
- (void)newFolder {
    if (!DMFinderCanWriteInto(self.path)) { [self dm_guard:@"newfolder" paths:@[] into:self.path then:^{}]; return; }
    NSString *p = DMFinderFreeName(self.path, @"untitled folder", @"");
    NSError *e = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:NO attributes:nil error:&e]) { [self fail:e what:@"New Folder"]; return; }
    DMFinderPushUndo(@"new", @"New Folder", @[@[@"", DMFinderNorm(p)]]);
    [self dm_selectPathsWhenListed:@[DMFinderNorm(p)]];
    [self refresh];
    DMFinderItem *it = [DMFinderItem new]; it.path = DMFinderNorm(p); it.name = p.lastPathComponent;
    [self dm_rename:it];
}
// File > New Text File (and the folder's menu, the desktop's): an empty "untitled.txt" ("untitled 2.txt"...) in this folder -- only in the user's own
// places --, selected and named in place (the name without ".txt" selected); Undo moves it to the Trash, as for New Folder.
- (void)dm_newTextFile {
    DM_FEATURE_MARK("finder-new-text-file");
    if (!DMFinderCanWriteInto(self.path)) { [self dm_guard:@"newfile" paths:@[] into:self.path then:^{}]; return; }
    NSString *p = DMFinderFreeName(self.path, @"untitled.txt", @"");
    if (![[NSFileManager defaultManager] createFileAtPath:p contents:[NSData data] attributes:nil]) { [self fail:DMFinderError(@"The file could not be made.") what:@"New Text File"]; return; }
    DMFinderPushUndo(@"new", @"New Text File", @[@[@"", DMFinderNorm(p)]]);
    DMLog(@"[finder] new text file");
    [self dm_selectPathsWhenListed:@[DMFinderNorm(p)]];
    [self refresh];
    DMFinderItem *it = [DMFinderItem new]; it.path = DMFinderNorm(p); it.name = p.lastPathComponent;
    [self dm_rename:it];
}
- (void)dm_rename:(DMFinderItem *)it {
    if (it.cloud) { [self dm_guard:@"rename" paths:@[it.path] into:nil then:^{}]; return; }
    if (![self dm_beginInlineRename:it.path]) _renameWhenListed = it.path;   // (not shown yet -- a new folder: edited as soon as the folder lists it)
}
// Rename in place, as on a Mac: the name turns into a text field right in its row / under its icon, the name without its extension selected; Return
// (or a click elsewhere) renames, Esc keeps the old name. It replaces the Rename sheet.
- (BOOL)dm_beginInlineRename:(NSString *)path {
    DM_FEATURE_MARK("finder-inline-rename");
    [self dm_endRename:YES];
    NSInteger i = NSNotFound; for (NSInteger k = 0; k < (NSInteger)_items.count; k++) if ([_items[k].path isEqualToString:path]) i = k;
    if (i == NSNotFound) return NO;
    DMFinderItem *it = _items[i];
    [self dm_setSelection:@[path] anchor:path];
    [self dm_scrollToPath:path];
    UIScrollView *v = _icons ? (UIScrollView *)_grid : (UIScrollView *)_list;
    [v layoutIfNeeded];
    CGRect f;
    if (_icons) { CGRect c = [_grid layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]].frame; f = CGRectMake(c.origin.x - 8.0, c.origin.y + 62.0, c.size.width + 16.0, 22.0); }
    else { CGRect r = [_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]]; f = CGRectMake(40.0, r.origin.y + 2.0, MIN(DMFinderColumns(_list.bounds.size.width).nameW + 8.0, r.size.width - 44.0), r.size.height - 4.0); }
    UITextField *tf = [[UITextField alloc] initWithFrame:f];
    tf.font = [UIFont systemFontOfSize:_icons ? 11.0 : 13.0];
    tf.textAlignment = _icons ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    tf.backgroundColor = [UIColor systemBackgroundColor];
    tf.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8].CGColor; tf.layer.borderWidth = 1.5; tf.layer.cornerRadius = 3.0;
    tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 3, 3)]; tf.leftViewMode = UITextFieldViewModeAlways;
    tf.autocorrectionType = UITextAutocorrectionTypeNo; tf.autocapitalizationType = UITextAutocapitalizationTypeNone; tf.spellCheckingType = UITextSpellCheckingTypeNo;
    tf.smartQuotesType = UITextSmartQuotesTypeNo; tf.smartDashesType = UITextSmartDashesTypeNo; tf.returnKeyType = UIReturnKeyDone;
    tf.text = it.name; tf.delegate = self;
    [v addSubview:tf];
    _renameField = tf; _renamePath = path;
    if (!gNativeLayer.isKeyWindow) [gNativeLayer makeKeyWindow];
    [tf becomeFirstResponder];
    NSString *base = (!it.dir && it.name.pathExtension.length && it.name.stringByDeletingPathExtension.length) ? it.name.stringByDeletingPathExtension : it.name;
    UITextPosition *start = tf.beginningOfDocument, *end = [tf positionFromPosition:start offset:(NSInteger)base.length];
    if (end) tf.selectedTextRange = [tf textRangeFromPosition:start toPosition:end];
    DMLog([NSString stringWithFormat:@"[finder] rename in place: %@ (%lu of %lu characters selected)", it.kind, (unsigned long)base.length, (unsigned long)it.name.length]);
    return YES;
}
- (BOOL)dm_isRenaming { return _renameField != nil; }
- (void)dm_endRename:(BOOL)commit {
    UITextField *tf = _renameField; NSString *path = _renamePath;
    if (!tf) return;
    _renameField = nil; _renamePath = nil;
    NSString *t = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    [tf resignFirstResponder]; [tf removeFromSuperview];
    if (gNativeActive == self && !gNativeLayer.rootViewController.presentedViewController) [gNativeKeys becomeFirstResponder];
    BOOL change = commit && t.length && ![t isEqualToString:path.lastPathComponent];
    DMLog([NSString stringWithFormat:@"[finder] rename in place ended: %@", change ? @"renamed" : @"name kept"]);
    if (change) [self dm_renameItem:path to:t];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { if (tf == _renameField) { [self dm_endRename:YES]; return NO; } return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { if (tf == _renameField) [self dm_endRename:YES]; }
// A typed path found on the disk the way a Mac's Go to Folder finds it: a part that doesn't exist as typed matches a name that differs only in case
// ("~/documents" -> /var/mobile/Documents; the iPad's disk is case-sensitive, a Mac's is not). nil if a part isn't there at all.
static NSString *DMFinderResolveTyped(NSString *p) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:p]) return p;
    NSString *cur = @"/";
    for (NSString *part in p.pathComponents) {
        if ([part isEqualToString:@"/"]) continue;
        NSString *next = [cur stringByAppendingPathComponent:part];
        if (![fm fileExistsAtPath:next]) {
            next = nil;
            for (NSString *n in [fm contentsOfDirectoryAtPath:cur error:nil]) if ([n caseInsensitiveCompare:part] == NSOrderedSame) { next = [cur stringByAppendingPathComponent:n]; break; }
            if (!next) return nil;
        }
        cur = next;
    }
    return cur;
}
// Go > Go to Folder… (Shift-Command-G): a path -- absolute, ~ for Home, or relative to this folder. A folder opens; a file opens its folder with
// the file selected; anything else says so, as on a Mac.
- (void)dm_goToFolder {
    DM_FEATURE_MARK("finder-go-to-folder");
    __weak DMFinderWindow *ws = self;
    [self sheetTitle:@"Go to the folder:" message:nil field:self.path ?: @"/var/mobile" action:@"Go" destructive:NO then:^(NSString *text) {
        DMFinderWindow *s = ws; if (!s) return;
        NSString *p = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!p.length) return;
        if ([p hasPrefix:@"~"]) p = [@"/var/mobile" stringByAppendingString:[p substringFromIndex:1]];
        if (![p hasPrefix:@"/"]) p = [s.path ?: @"/var/mobile" stringByAppendingPathComponent:p];
        p = p.stringByStandardizingPath;
        BOOL dir = NO;
        NSString *found = DMFinderResolveTyped(p);
        if (found) p = found;
        if (!found || ![[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir]) {
            DMLog(@"[finder] go to folder: not found");
            [s sheetTitle:@"The folder can’t be found." message:p field:nil action:@"OK" destructive:NO then:^(NSString *t) {}];
            return;
        }
        DMLog([NSString stringWithFormat:@"[finder] go to folder: %@", dir ? @"a folder" : @"a file (its folder, the file selected)"]);
        if (dir) { [s go:p]; return; }
        [s go:p.stringByDeletingLastPathComponent];
        [s dm_selectPathsWhenListed:@[DMFinderNorm(p)]];
    }];
}
- (void)dm_duplicate:(DMFinderItem *)it { [self dm_duplicateItems:@[it.path]]; }
- (void)trash:(DMFinderItem *)it { [self dm_trashItems:@[it.path]]; }
- (void)emptyTrash {
    DM_FEATURE_MARK("finder-trash");
    [self alertTitle:@"Are you sure you want to permanently erase the items in the Trash?" message:@"You can't undo this action." field:nil action:@"Empty Trash" destructive:YES then:^(NSString *t) {
        [self fileWork:@"Empty Trash" work:^NSError *{
            NSError *first = nil; NSUInteger failed = 0;
            if (!DMFinderTrashIsSound()) return DMFinderError(@"The Trash is not a folder of its own here: nothing was erased.");
            // (Finder's Trash and every connected drive's Trash, <volume>/.Trashes/501 -- only what is inside those folders, as on a Mac)
            NSMutableArray *trashes = [NSMutableArray arrayWithObject:kFinderTrash];
            for (NSString *t in DMFinderDriveTrashes()) if (DMFinderDriveTrashIsSound(t)) [trashes addObject:t];
            for (NSString *t in trashes) for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:t error:nil]) {
                NSString *x = [t stringByAppendingPathComponent:f];
                if (!DMFinderTaken(x)) continue;   // (a "._" file on a drive goes with its item)
                NSError *e = DMFinderDriveGoneError(DMFinderRemove(x), @[x]);   // (the same rule as Delete Immediately)
                if (e) { failed++; if (!first) first = e; }
            }
            return failed ? DMFinderError([NSString stringWithFormat:@"%lu item%@ could not be erased: %@", (unsigned long)failed, failed == 1 ? @"" : @"s", first.localizedDescription ?: @"?"]) : nil;
        }];
    }];
}
- (void)paste { [self dm_pasteInto:self.path]; }
- (void)getInfo:(DMFinderItem *)it {
    if (it.dir) {   // (a folder's size: everything inside, counted off the main thread -- a big folder took seconds)
        __weak DMFinderWindow *ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            unsigned long long total = 0; NSUInteger n = 0;
            NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:it.path];
            while ([en nextObject]) { total += [en.fileAttributes fileSize]; if (++n > 50000) break; }
            dispatch_async(dispatch_get_main_queue(), ^{ [ws showInfo:it size:total]; });
        });
        return;
    }
    [self showInfo:it size:it.size];
}
// (Get Info is a sheet: the system share sheet and UIKit alerts can't be used from SpringBoard's windows -- presented from the layer the share
//  sheet came up off-screen on iPadOS 15 in landscape and took every touch; embedded in the turned container its presenter threw while
//  appearing and SpringBoard crashed (M1, 30 Sep 14:42). Share is our own menu, DMFinderShareTo.)
- (void)showInfo:(DMFinderItem *)it size:(unsigned long long)size {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:it.path error:nil];
    NSString *origin = DMFinderInTrash(it.path) ? DMFinderOrigin(it.path) : nil;
    NSString *m = [NSString stringWithFormat:@"Kind: %@\nSize: %@\nWhere: %@\nModified: %@\nOwner: %@ (%@)%@%@", it.kind,
                   [NSByteCountFormatter stringFromByteCount:(long long)size countStyle:NSByteCountFormatterCountStyleFile], DMFinderNorm(it.path.stringByDeletingLastPathComponent),
                   DMFinderDate(it.date), attrs[NSFileOwnerAccountName] ?: @"?", [NSString stringWithFormat:@"%lo", [attrs[NSFilePosixPermissions] unsignedLongValue]],
                   it.cloud ? @"\nIn iCloud, not downloaded" : @"", origin ? [@"\nFrom: " stringByAppendingString:origin.stringByDeletingLastPathComponent] : @""];
    [self alertTitle:it.display message:m field:nil action:@"Copy Path" destructive:NO then:^(NSString *t) { [UIPasteboard generalPasteboard].string = it.path; }];
}
// long-press / right-click menus: on an item, or on the folder's empty space
- (DMFinderItem *)itemAt:(CGPoint)p in:(UIView *)v {
    NSIndexPath *ip = v == _list ? [_list indexPathForRowAtPoint:p] : [_grid indexPathForItemAtPoint:p];
    NSInteger i = v == _list ? ip.row : ip.item;
    return ip && i < (NSInteger)_items.count ? _items[i] : nil;
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)cmi configurationForMenuAtLocation:(CGPoint)loc {
    // (a finger's press: the menu is opened by our own hold (-dm_dragPress:), never by the menu's own press -- that one starts at the touch-down and,
    //  while it runs, no other press in the list may begin: a still hold never armed the drag, the menu opened at ~0.85 s instead, and a hold that
    //  then moved slid through the menu's rows, iPad 2 + M1 30 Sep. The menu is ours (DMFinderShowMenu), for a pointer's secondary click too.)
    if (!_menuByHold) return nil;
    DMFinderItem *it = [self itemAt:loc in:cmi.view];
    (void)0;
    __weak DMFinderWindow *ws = self;
    if (_dragLifted) return nil;   // (a drag is under way: no menu)
    NSIndexPath *ipath = it ? (cmi.view == _list ? [_list indexPathForRowAtPoint:loc] : [_grid indexPathForItemAtPoint:loc]) : nil;
    return [UIContextMenuConfiguration configurationWithIdentifier:ipath previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        DMFinderWindow *w = ws;
        UIAction *(^A)(NSString *, NSString *, void (^)(void)) = ^UIAction *(NSString *t, NSString *img, void (^h)(void)) { return [UIAction actionWithTitle:t image:img ? [UIImage systemImageNamed:img] : nil identifier:nil handler:^(UIAction *a) { h(); }]; };
        NSMutableArray *top = [NSMutableArray array], *mid = [NSMutableArray array], *end = [NSMutableArray array];
        NSArray<DMFinderItem *> *many = (it && [w dm_isSelected:it] && [w dm_selectedItems].count > 1) ? [w dm_selectedItems] : nil;
        if (many) {   // (the item is one of several selected: the menu acts on them all, as on a Mac)
            NSArray<NSString *> *paths = [many valueForKey:@"path"];
            BOOL canChange = YES, files = YES, inTrash = YES, ownTrash = YES;
            for (DMFinderItem *x in many) { canChange = canChange && DMFinderCanChange(x.path); files = files && !x.dir && !x.cloud; inTrash = inTrash && DMFinderInTrash(x.path); ownTrash = ownTrash && DMFinderInOwnTrash(x.path); }
            NSString *n = [NSString stringWithFormat:@"%lu Items", (unsigned long)many.count];
            [top addObject:A(@"Open", nil, ^{ [w dm_openSelected]; })];
            UIAction *du = A(@"Duplicate", @"plus.square.on.square", ^{ [w dm_duplicateItems:paths]; }); if (![w dm_canWriteHere]) du.attributes = UIMenuElementAttributesDisabled; [mid addObject:du];
            [mid addObject:A([@"Copy " stringByAppendingString:n], @"doc.on.doc", ^{ gFinderClipboard = [paths mutableCopy]; })];
            if (files) {
                NSMutableArray *targets = [NSMutableArray array];
                for (NSString *b in DMFinderShareApps()) [targets addObject:[UIAction actionWithTitle:DMCall(DMProxyForBundle(b), @"localizedName") ?: b image:nil identifier:nil handler:^(UIAction *x) { DMFinderShareTo(many, b, w); }]];
                if (targets.count) [mid addObject:[UIMenu menuWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil options:0 children:targets]];
            }
            if (inTrash) [end addObject:A(@"Put Back", @"arrow.uturn.backward", ^{ [w dm_putBackItems:paths]; })];
            UIAction *t = A(ownTrash ? [NSString stringWithFormat:@"Delete %@ Immediately…", n] : [NSString stringWithFormat:@"Move %@ to Trash", n], @"trash", ^{ if (ownTrash) [w dm_deleteItems:paths]; else [w dm_trashItems:paths]; });
            t.attributes = canChange ? UIMenuElementAttributesDestructive : UIMenuElementAttributesDisabled;
            [end addObject:t];
        } else if (it) {
            [top addObject:A(@"Open", nil, ^{ [w open:it]; })];
            if (it.app || [it.name hasSuffix:@".app"]) [top addObject:A(@"Show Package Contents", @"shippingbox", ^{ [w go:it.app ?: it.path]; })];
            if (!it.dir) [top addObject:A(@"Quick Look", @"eye", ^{ [w quickLook:it]; })];
            BOOL canChange = DMFinderCanChange(it.path), canCopyHere = DMFinderCanWriteInto(it.path.stringByDeletingLastPathComponent);   // (read-only places: greyed, as on a Mac)
            [mid addObject:A(@"Get Info", @"info.circle", ^{ [w getInfo:it]; })];
            UIAction *rn = A(@"Rename", @"pencil", ^{ [w dm_rename:it]; }); if (!canChange) rn.attributes = UIMenuElementAttributesDisabled; [mid addObject:rn];
            UIAction *du = A(@"Duplicate", @"plus.square.on.square", ^{ [w dm_duplicate:it]; }); if (!canCopyHere) du.attributes = UIMenuElementAttributesDisabled; [mid addObject:du];
            [mid addObject:A(@"Copy", @"doc.on.doc", ^{ gFinderClipboard = [@[it.path] mutableCopy]; })];
            if (it.cloud) [top addObject:A(@"Download Now", @"icloud.and.arrow.down", ^{ [w dm_download:it]; })];
            [mid addObject:A(@"Copy Path", @"link", ^{ [UIPasteboard generalPasteboard].string = it.path; })];
            if (!it.dir && !it.cloud) {
                NSMutableArray *targets = [NSMutableArray array];
                for (NSString *b in DMFinderShareApps()) {
                    NSString *name = DMCall(DMProxyForBundle(b), @"localizedName") ?: b;
                    [targets addObject:[UIAction actionWithTitle:name image:nil identifier:nil handler:^(UIAction *x) { DMFinderShareTo(@[it], b, w); }]];
                }
                if (targets.count) [mid addObject:[UIMenu menuWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil options:0 children:targets]];
            }
            if (DMFinderInTrash(it.path)) {
                UIAction *pb = A(@"Put Back", @"arrow.uturn.backward", ^{ [w dm_putBackItems:@[it.path]]; });
                if (!DMFinderOrigin(it.path)) pb.attributes = UIMenuElementAttributesDisabled;
                [end addObject:pb];
            }
            UIAction *t = A(DMFinderInOwnTrash(it.path) ? @"Delete Immediately…" : @"Move to Trash", @"trash", ^{ [w trash:it]; });
            t.attributes = canChange ? UIMenuElementAttributesDestructive : UIMenuElementAttributesDisabled;
            [end addObject:t];
        } else {
            BOOL writable = [w dm_canWriteHere];
            UIAction *nf = A(@"New Folder", @"folder.badge.plus", ^{ [w newFolder]; }); if (!writable) nf.attributes = UIMenuElementAttributesDisabled; [top addObject:nf];
            UIAction *nt = A(@"New Text File", @"doc.badge.plus", ^{ [w dm_newTextFile]; }); if (!writable) nt.attributes = UIMenuElementAttributesDisabled; [top addObject:nt];
            UIAction *p = A(gFinderClipboard.count > 1 ? [NSString stringWithFormat:@"Paste %lu Items", (unsigned long)gFinderClipboard.count] : @"Paste Item", @"doc.on.clipboard", ^{ [w paste]; });
            if (!gFinderClipboard.count || !writable) p.attributes = UIMenuElementAttributesDisabled;
            [top addObject:p];
            [mid addObject:A(w->_hidden ? @"Hide Hidden Files" : @"Show Hidden Files", @"eye.slash", ^{ w->_hidden = !w->_hidden; [w refresh]; })];
            [mid addObject:A(w->_icons ? @"as List" : @"as Icons", w->_icons ? @"list.bullet" : @"square.grid.2x2", ^{ [w toggleView]; })];
            [mid addObject:A(@"Copy Path", @"link", ^{ [UIPasteboard generalPasteboard].string = w.path; })];
            if ([w dm_canUndo]) [top addObject:A([w dm_undoTitle], @"arrow.uturn.backward", ^{ [w dm_undo]; })];
            if ([w.path isEqualToString:kFinderTrash]) { UIAction *e = A(@"Empty Trash…", @"trash.slash", ^{ [w emptyTrash]; }); e.attributes = UIMenuElementAttributesDestructive; [end addObject:e]; }
        }
        NSMutableArray *groups = [NSMutableArray array];
        for (NSArray *g in @[top, mid, end]) if (g.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:g]];
        return [UIMenu menuWithTitle:@"" children:groups];
    }];
}
// ---- our own drag ---------------------------------------------------------------------------------------------------------------------------
// Option held on a hardware keyboard while dragging: a copy, as on a Mac (the recognizer's modifier flags; /tmp/msb-fdrag-option in debug tests).
- (BOOL)dm_optionHeld:(UIGestureRecognizer *)g {
    BOOL opt = NO;
    if (@available(iOS 13.4, *)) opt = (g.modifierFlags & UIKeyModifierAlternate) != 0;
    return opt || DMTestFlag("/tmp/msb-fdrag-option");
}
- (DMFinderItem *)dm_itemAtLongPress:(UILongPressGestureRecognizer *)g {
    UIView *v = g.view;
    return [self itemAt:[g locationInView:v] in:v];
}
- (NSString *)dm_folderAtScreenPoint:(CGPoint)sp {   // the folder this window would take a drop into at that point: a folder row / icon, or the window's own folder
    for (UIView *v in @[_list, _grid]) {
        if (v.hidden) continue;
        CGPoint p = [v convertPoint:sp fromCoordinateSpace:v.window.screen.coordinateSpace];
        if (![v pointInside:p withEvent:nil]) continue;
        DMFinderItem *it = [self itemAt:p in:v];
        if (it.dir && !it.app && ![it.name hasSuffix:@".app"] && !it.locked) return it.path;
    }
    for (NSInteger sec = 0; sec < (NSInteger)_places.count; sec++) {   // (a sidebar place)
        NSArray *rows = _places[sec][@"rows"];
        for (NSInteger r = 0; r < (NSInteger)rows.count; r++) {
            UITableViewCell *c = [_sidebar cellForRowAtIndexPath:[NSIndexPath indexPathForRow:r inSection:sec]];
            if (!c) continue;
            CGPoint p = [c convertPoint:sp fromCoordinateSpace:c.window.screen.coordinateSpace];
            if ([c pointInside:p withEvent:nil]) return rows[r][@"p"];
        }
    }
    return self.path;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g.name isEqualToString:@"dm.finder.band"]) {   // (the selection rectangle starts on empty space only; on an item a pointer drags the item)
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)g;
        CGPoint p = [pan locationInView:g.view], t = [pan translationInView:g.view];
        return [self itemAt:CGPointMake(p.x - t.x, p.y - t.y) in:g.view] == nil;
    }
    return [super gestureRecognizerShouldBegin:g];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if ([g.name isEqualToString:@"dm.finder.drag"]) {   // (where the finger came down, and where the list was: a hold that drifted a little is told from a scroll)
        _dragDown = [t.window convertPoint:[t locationInView:nil] toCoordinateSpace:t.window.screen.coordinateSpace];
        _fingerDown = t.type == UITouchTypeDirect; _pressSerial++; _pressHappened = NO;
        if ([g.view isKindOfClass:[UIScrollView class]]) { CGPoint o = ((UIScrollView *)g.view).contentOffset; _dragDownOffset = o; }
#if DEBUG
        if (DMTestFlag("/tmp/msb-grwatch")) {   // (which recognisers ours waits for, and what they do in the first second)
            unsigned n = 0; Ivar *ivs = class_copyIvarList([UIGestureRecognizer class], &n);
            NSMutableString *m = [NSMutableString stringWithString:@"[fdrag] ours:"];
            for (unsigned i = 0; i < n; i++) { const char *nm = ivar_getName(ivs[i]); if (!strstr(nm, "ailure") && !strstr(nm, "elationship")) continue;
                id v = nil; @try { v = object_getIvar(g, ivs[i]); } @catch (id e) {}
                if (![v respondsToSelector:@selector(count)]) { [m appendFormat:@" %s=%@", nm, v ? NSStringFromClass([v class]) : @"nil"]; continue; }
                NSMutableArray *cls = [NSMutableArray array]; for (id x in v) [cls addObject:[x respondsToSelector:@selector(state)] ? NSStringFromClass([x class]) : [[x description] substringToIndex:MIN((NSUInteger)60, [x description].length)]];
                [m appendFormat:@" %s=[%@]", nm, [cls componentsJoinedByString:@","]]; }
            free(ivs); DMLog(m);
            __weak UITouch *wt = t;
            for (NSNumber *d in @[@0.32, @0.6, @0.9]) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UITouch *tt = wt; NSMutableString *o = [NSMutableString stringWithFormat:@"[fdrag] +%.2f s phase %ld:", d.doubleValue, (long)tt.phase];
                for (UIGestureRecognizer *x in tt.gestureRecognizers) [o appendFormat:@" %@(%ld)", x.name ?: NSStringFromClass([x class]), (long)x.state];
                DMLog(o); });
        }
#endif
    }
    return YES;
}
- (void)dm_dragPress:(UILongPressGestureRecognizer *)g {
    CGPoint sp = [g.view convertPoint:[g locationInView:g.view] toCoordinateSpace:g.view.window.screen.coordinateSpace];
    if (g.state == UIGestureRecognizerStateBegan) {   // (armed: the item under the finger; nothing lifts until the finger moves)
        UIScrollView *sv = (UIScrollView *)g.view;
        // A scroll under way never becomes a drag (a flick still moving, or a finger that travelled). A finger that only drifted a little while
        // holding still counts as a hold: the scroll that drift started is undone (it won 7 presses out of 8 on the iPad 2, and the item's
        // menu opened instead of the drag, 30 Sep).
        if ([sv isKindOfClass:[UIScrollView class]] && (sv.isDecelerating || (sv.isDragging && hypot(sp.x - _dragDown.x, sp.y - _dragDown.y) > 24.0))) {
            _dragArmed = nil; DMLog(@"[finder] press during a scroll: no drag"); return;
        }
        if ([sv isKindOfClass:[UIScrollView class]] && sv.isDragging) [sv setContentOffset:_dragDownOffset animated:NO];
        [self dm_endRename:YES];   // (a hold elsewhere ends a rename in place, keeping the new name)
        // (the item where the finger came DOWN, not where it is now: a finger that drifted during the hold took the row above or below, 3 of 5)
        CGPoint down = [g.view convertPoint:_dragDown fromCoordinateSpace:g.view.window.screen.coordinateSpace];
        DMFinderItem *it = [self itemAt:down in:g.view];
        _dragArmed = (it && !it.locked) ? it : nil; _dragStart = sp; _dragLifted = NO; _pressActive = YES; _pressHappened = YES;
        {   // (held on without moving: the menu, as the item's (or the folder's) long press -- from here, so a hold that moves later still drags)
            NSUInteger serial = _pressSerial; __weak DMFinderWindow *ws = self; __weak UIView *view = g.view;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                DMFinderWindow *s = ws; UIView *v = view;
                if (!s || !v || s->_pressSerial != serial || !s->_pressActive || s->_dragLifted) return;
                [s dm_menuByHoldIn:v at:down];
            });
        }
        if (_dragArmed && [sv isKindOfClass:[UIScrollView class]]) { sv.panGestureRecognizer.enabled = NO; sv.panGestureRecognizer.enabled = YES; }   // (an item is held: moving now drags it, the list doesn't scroll away under it)
        if (_dragArmed) {   // (held: the row / icon rises a little -- the item is in hand, moving now carries it)
            UIView *cell = nil; CGPoint lp = down;
            if (g.view == _list) { NSIndexPath *ip = [_list indexPathForRowAtPoint:lp]; cell = ip ? [_list cellForRowAtIndexPath:ip] : nil; }
            else if (g.view == _grid) { NSIndexPath *ip = [_grid indexPathForItemAtPoint:lp]; cell = ip ? [_grid cellForItemAtIndexPath:ip] : nil; }
            _dragCell = cell;
            if (cell) {
                [cell.superview bringSubviewToFront:cell];
                MSBAnimate(0.22, 0, 0.6, UIViewAnimationOptionAllowUserInteraction, ^{ cell.transform = CGAffineTransformMakeScale(1.04, 1.04); }, nil);   // (Reduce Motion: no bounce, 1.3.3 audit L-5)
            }
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        }
        DMLog([NSString stringWithFormat:@"[finder] press held on %@ (item %ld, down at %.0f,%.0f in the list): %@", it ? it.kind : @"nothing", it ? (long)[_items indexOfObject:it] + 1 : 0L, down.x, down.y, _dragArmed ? @"armed" : @"not draggable"]);
    } else if (g.state == UIGestureRecognizerStateChanged) {
        if (!_dragLifted && _dragArmed && hypot(sp.x - _dragStart.x, sp.y - _dragStart.y) > 10.0) {
            _dragLifted = YES;
            for (id<UIInteraction> i in g.view.interactions) if ([i isKindOfClass:[UIContextMenuInteraction class]]) [(UIContextMenuInteraction *)i dismissMenu];
            if (gOverlay && gOverlay.superview == gNativeRotator) { DMCloseOverlay(); DMLog(@"[finder] moved with the menu open: the menu closes, the item lifts"); }
            for (UIGestureRecognizer *o in g.view.gestureRecognizers) if (o != g && o.state != UIGestureRecognizerStatePossible) { o.enabled = NO; o.enabled = YES; }   // (the menu's press preview -- the "3D Touch" look -- stops the moment the item lifts)
            UIView *cell = _dragCell;
            gFDFromRect = cell ? [cell convertRect:cell.bounds toCoordinateSpace:cell.window.screen.coordinateSpace] : CGRectZero;
            NSArray<DMFinderItem *> *sel = [self dm_selectedItems];   // (the held item; with it in a selection of several, all of them)
            BOOL inSel = NO; for (DMFinderItem *x in sel) if ([x.path isEqualToString:_dragArmed.path]) inSel = YES;
            DMFinderDragBegin(self, inSel && sel.count > 1 ? sel : @[_dragArmed], sp);
            if (cell) [UIView animateWithDuration:0.2 animations:^{ cell.transform = CGAffineTransformIdentity; cell.alpha = 0.45; }];   // (the item left its place: a ghost stays, like a Mac)
        }
        if (_dragLifted) DMFinderDragMove(sp, [self dm_optionHeld:g]);
    } else {
        BOOL drop = g.state == UIGestureRecognizerStateEnded;
        if (_dragArmed && !_dragLifted) DMLog([NSString stringWithFormat:@"[finder] press ended (state %ld) without a lift", (long)g.state]);
        if (_dragLifted) DMFinderDragEnd(sp, drop, [self dm_optionHeld:g]);
        UIView *cell = _dragCell; _dragCell = nil;
        if (cell) [UIView animateWithDuration:0.2 animations:^{ cell.transform = CGAffineTransformIdentity; cell.alpha = 1; }];
        _dragArmed = nil; _dragLifted = NO; _pressActive = NO;
    }
}
// The menu of a hold that stayed still, or of a pointer's secondary click: a Mac menu of our own at the finger / pointer, with the same items the
// long-press menu had (the menu interaction's own UIMenu). UIKit's menu took the finger over the moment it opened -- our press was cancelled,
// and a hold that then moved slid through the menu's rows instead of lifting the item (iPad 2 30 Sep); ours leaves the press alone: a move
// after it opened still lifts the item (-dm_dragPress: closes the menu then).
- (UIMenu *)dm_menuIn:(UIView *)v at:(CGPoint)loc {
    UIContextMenuInteraction *cmi = nil;
    for (id<UIInteraction> i in v.interactions) if ([i isKindOfClass:[UIContextMenuInteraction class]]) cmi = (UIContextMenuInteraction *)i;
    if (!cmi) return nil;
    _menuByHold = YES;
    UIContextMenuConfiguration *c = [self contextMenuInteraction:cmi configurationForMenuAtLocation:loc];
    _menuByHold = NO;
    UIContextMenuActionProvider ap = nil;
    @try { ap = [c valueForKey:@"actionProvider"]; } @catch (NSException *e) {}
    return ap ? ap(@[]) : nil;
}
- (void)dm_menuByHoldIn:(UIView *)v at:(CGPoint)loc {
    DMFinderItem *held = [self itemAt:loc in:v];   // (the item under it becomes the selection, unless it is already part of it -- as a Mac's right click)
    if (held && ![self dm_isSelected:held]) [self dm_setSelection:@[held.path] anchor:held.path];
    UIMenu *m = [self dm_menuIn:v at:loc];
    if (!m) { DMLog(@"[finder] hold: no menu here"); return; }
    UIView *cell = _dragCell;
    if (cell) [UIView animateWithDuration:0.15 animations:^{ cell.transform = CGAffineTransformIdentity; }];
    DMFinderShowMenu(m, [v convertPoint:loc toCoordinateSpace:v.window.screen.coordinateSpace]);
    DMLog(@"[finder] held still: the menu opened");
}
- (void)dm_secondaryClick:(UITapGestureRecognizer *)g {
    CGPoint loc = [g locationInView:g.view];
    DMFinderItem *clicked = [self itemAt:loc in:g.view];
    if (clicked && ![self dm_isSelected:clicked]) [self dm_setSelection:@[clicked.path] anchor:clicked.path];
    UIMenu *m = [self dm_menuIn:g.view at:loc];
    if (m) DMFinderShowMenu(m, [g.view convertPoint:loc toCoordinateSpace:g.view.window.screen.coordinateSpace]);
}
// The long-press menu's preview: the item's own row or icon, not the whole list (the default lifted the whole Finder page)
- (UITargetedPreview *)dm_previewFor:(UIContextMenuInteraction *)i config:(UIContextMenuConfiguration *)c {
    NSIndexPath *ip = (NSIndexPath *)c.identifier;
    if (![ip isKindOfClass:[NSIndexPath class]]) return nil;
    UIView *cell = i.view == _list ? [_list cellForRowAtIndexPath:ip] : [_grid cellForItemAtIndexPath:ip];
    if (!cell) return nil;
    UIPreviewParameters *pp = [UIPreviewParameters new];
    pp.visiblePath = [UIBezierPath bezierPathWithRoundedRect:cell.bounds cornerRadius:8.0];
    return [[UITargetedPreview alloc] initWithView:cell parameters:pp];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_previewFor:i config:c]; }
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_previewFor:i config:c]; }
@end

// ---- Finder's file operations outside a Finder window ---------------------------------------------------------------------------------------
// A drag out of the Dock's Downloads stack, a drop on that stack, the desktop's own files (DMDesktop): the same operations as in a Finder window
// -- the policy (DMFinderCanChange / DMFinderCanWriteInto, a sheet says no), Undo, free names, every window showing a changed folder refreshed --
// run by one Finder window that is never shown. Its questions and errors come as a dialog of our own over everything, like the menus' questions.
static void DMFinderLooseSheet(NSString *title, NSString *message, NSString *action, BOOL destructive, void (^then)(NSString *text), void (^cancel)(void)) {
    UIView *host = DMMenuHost();
    if (!host) { DMLog([NSString stringWithFormat:@"[finder] no place for the question \"%@\"", title]); if (cancel) cancel(); return; }
    BOOL single = !action.length || [action isEqualToString:@"OK"];
    UIControl *o = DMMakeOverlay(host, 0.30);
    const CGFloat W = 300.0, pad = 20.0, buttonH = 46.0;
    UILabel *t = [UILabel new];
    t.text = title; t.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold]; t.textColor = [UIColor labelColor];
    t.textAlignment = NSTextAlignmentCenter; t.numberOfLines = 0;
    UILabel *m = [UILabel new];
    m.text = message; m.font = [UIFont systemFontOfSize:13.0]; m.textColor = [UIColor secondaryLabelColor];
    m.textAlignment = NSTextAlignmentCenter; m.numberOfLines = 0;
    CGSize ts = [t sizeThatFits:CGSizeMake(W - 2 * pad, CGFLOAT_MAX)], ms = message.length ? [m sizeThatFits:CGSizeMake(W - 2 * pad, CGFLOAT_MAX)] : CGSizeZero;
    CGFloat y = 20.0;
    t.frame = CGRectMake(pad, y, W - 2 * pad, ts.height); y += ts.height + 6.0;
    m.frame = CGRectMake(pad, y, W - 2 * pad, ms.height); y += ms.height + 14.0;
    UIVisualEffectView *box = DMMakeBlur(14.0);
    box.frame = CGRectMake(0, 0, W, y + buttonH);
    box.center = CGPointMake(CGRectGetMidX(o.bounds), CGRectGetMidY(o.bounds));
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [box.contentView addSubview:t]; [box.contentView addSubview:m];
    UIView *hLine = [[UIView alloc] initWithFrame:CGRectMake(0, y, W, 0.5)]; hLine.backgroundColor = [UIColor separatorColor]; [box.contentView addSubview:hLine];
    void (^ok)(void) = ^{ DMCloseOverlay(); if (then) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ then(nil); }); };
    void (^no)(void) = ^{ DMCloseOverlay(); if (cancel) cancel(); };
    UIColor *actionColor = destructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
    if (single) [box.contentView addSubview:DMDialogButton(action.length ? action : @"OK", YES, actionColor, CGRectMake(0, y, W, buttonH), ok)];
    else {
        UIView *vLine = [[UIView alloc] initWithFrame:CGRectMake(W / 2.0, y, 0.5, buttonH)]; vLine.backgroundColor = [UIColor separatorColor]; [box.contentView addSubview:vLine];
        [box.contentView addSubview:DMDialogButton(@"Cancel", NO, [UIColor systemBlueColor], CGRectMake(0, y, W / 2.0, buttonH), no)];
        [box.contentView addSubview:DMDialogButton(action, YES, actionColor, CGRectMake(W / 2.0, y, W / 2.0, buttonH), ok)];
    }
    [o addSubview:box];
    box.alpha = 0.0;
    [UIView animateWithDuration:0.12 animations:^{ box.alpha = 1.0; }];
    DMLog([NSString stringWithFormat:@"[finder] question outside a window: \"%@\"", title]);
}
@interface DMFinderOpsHost : DMFinderWindow
@property (nonatomic, copy) void (^madeItems)(NSArray<NSString *> *paths);   // (what an operation made: the desktop selects it, see DMDesktop)
@end
@implementation DMFinderOpsHost
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then {
    [self sheetTitle:title message:message field:field action:action destructive:destructive then:then cancel:nil];
}
- (void)sheetTitle:(NSString *)title message:(NSString *)message field:(NSString *)field action:(NSString *)action destructive:(BOOL)destructive then:(void (^)(NSString *text))then cancel:(void (^)(void))cancel {
    if (field) DMLog(@"[finder] a question with a text field outside a window: shown without the field");   // (none of the operations used here asks for text)
    DMFinderLooseSheet(title, message, action, destructive, then, cancel);
}
- (BOOL)hasSheet { return NO; }
- (void)refresh {}   // (no list of its own: DMFinderRefreshFolders refreshes the windows, the desktop watches its folder)
- (void)dm_selectPathsWhenListed:(NSArray<NSString *> *)paths { if (self.madeItems) self.madeItems(paths); }
- (void)show {}      // (never on the screen)
- (void)activate {}
@end
static DMFinderWindow *DMFinderOps(void) {
    static DMFinderOpsHost *host;
    if (!host) { host = [[DMFinderOpsHost alloc] initWithTitle:@"Finder" frame:CGRectMake(0, 0, 600, 400)]; host.path = DMFinderOnMyIPad() ?: @"/var/mobile/Documents"; }
    return host;
}

// ---- drags that start in the Dock's Downloads stack (dock/Downloads.m, the Dock's library: it finds these with dlsym) ----------------------------
// The stack's items are carried by Finder's own drag: into a Finder window (moved, or copied with Option / from a read-only place), onto an app's
// window (handed over, a copy), onto the desktop. Begin answers NO when Finder is off or an item is gone: the stack then keeps the touch.
__attribute__((visibility("default"))) BOOL MSBDFinderDragBeginPaths(NSArray<NSString *> *paths, CGPoint sp, CGRect from) {
    if (!gFinderOn || ![paths isKindOfClass:[NSArray class]] || !paths.count) return NO;
    DM_FEATURE_MARK("finder-drag-from-downloads-stack");
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *p in paths) { DMFinderItem *it = [p isKindOfClass:[NSString class]] ? DMFinderItemFor(p) : nil; if (!it) return NO; [items addObject:it]; }
    gFDFromRect = from;
    DMFinderDragBegin(DMFinderOps(), items, sp);
    return gFD != nil && !gFD.finished;
}
__attribute__((visibility("default"))) void MSBDFinderDragMoveTo(CGPoint sp, BOOL option) { DMFinderDragMove(sp, option); }
__attribute__((visibility("default"))) void MSBDFinderDragEndAt(CGPoint sp, BOOL drop, BOOL option) { DMFinderDragEnd(sp, drop, option); }

// ---- opening Finder -------------------------------------------------------------------------------------------------------------------------
// A new Finder window (File > New Finder Window, the Go menu with nothing open), or the front one showing `path`.
// Drives plugged in or out: the kernel's file system events (a kqueue EVFILT_FS: VQ_MOUNT / VQ_UNMOUNT, what the Mac's disk arbitration listens
// to) -- no polling. Every Finder window then shows the drives connected now (DMFinderSidebar), at once, without a respring.
static NSArray<NSString *> *gFinderDrivesShown;
static void DMFinderDrivesCheck(NSString *why) {
    DMFinderDrivesForget();
    NSArray *drives = DMFinderDrives();
    NSArray *paths = [drives valueForKey:@"p"];
    if (gFinderDrivesShown && [paths isEqualToArray:gFinderDrivesShown]) return;
    BOOL first = gFinderDrivesShown == nil;
    gFinderDrivesShown = paths;
    NSMutableArray *desc = [NSMutableArray array];
    for (NSDictionary *d in drives) [desc addObject:[NSString stringWithFormat:@"%@/%@ (%@ via %@%@)", [d[@"p"] stringByDeletingLastPathComponent].lastPathComponent, d[@"t"], [d[@"from"] componentsSeparatedByString:@"/"].firstObject, d[@"type"], [d[@"fat"] boolValue] ? @", FAT: 4 GB file limit" : @""]];
    DMLog([NSString stringWithFormat:@"[finder] drives (%@): %lu connected%@%@", why, (unsigned long)drives.count, drives.count ? @": " : @"", [desc componentsJoinedByString:@"; "]]);
    if (first) return;
    for (DMNativeWindow *w in [gNativeWindows copy]) if ([w isKindOfClass:[DMFinderWindow class]]) [(DMFinderWindow *)w dm_drivesChanged];
}
// The second signal: LiveFiles and its provider folders are watched too (a volume's folder appears there when a drive is mounted, and goes when
// it is unmounted). Either signal leads to the same check, which only acts on a real change.
static NSMutableDictionary<NSString *, dispatch_source_t> *gFinderLiveWatch;
static void DMFinderWatchLiveFolders(void) {
    if (!gFinderLiveWatch) gFinderLiveWatch = [NSMutableDictionary dictionary];
    NSMutableArray *dirs = [NSMutableArray arrayWithObject:kFinderLiveFiles];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kFinderLiveFiles error:nil]) {
        NSString *d = [kFinderLiveFiles stringByAppendingPathComponent:f]; BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:d isDirectory:&isDir] && isDir) [dirs addObject:d];
    }
    for (NSString *d in gFinderLiveWatch.allKeys) if (![dirs containsObject:d]) { dispatch_source_cancel(gFinderLiveWatch[d]); [gFinderLiveWatch removeObjectForKey:d]; }
    for (NSString *d in dirs) {
        if (gFinderLiveWatch[d]) continue;
        int fd = open(d.fileSystemRepresentation, O_EVTONLY);
        if (fd < 0) continue;
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK | DISPATCH_VNODE_REVOKE, dispatch_get_main_queue());
        if (!src) { close(fd); continue; }
        dispatch_source_set_event_handler(src, ^{
            static BOOL pending; if (pending) return; pending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                pending = NO;
                DMFinderWatchLiveFolders();   // (a provider folder may have come or gone)
                DMFinderDrivesCheck(@"LiveFiles changed");
            });
        });
        dispatch_source_set_cancel_handler(src, ^{ close(fd); });
        dispatch_resume(src);
        gFinderLiveWatch[d] = src;
    }
}
static void DMFinderWatchDrives(void) {
    static dispatch_source_t src; static dispatch_once_t once;
    dispatch_once(&once, ^{
        DMFinderDrivesCheck(@"start");
        DMFinderWatchLiveFolders();
        int kq = kqueue();
        if (kq < 0) { DMLog(@"[finder] drives: no kqueue -- drives show when a Finder window opens"); return; }
        struct kevent ev; EV_SET(&ev, 0, EVFILT_FS, EV_ADD | EV_CLEAR, 0, 0, NULL);
        if (kevent(kq, &ev, 1, NULL, 0, NULL) < 0) { DMLog([NSString stringWithFormat:@"[finder] drives: file system events unavailable (%d)", errno]); close(kq); return; }
        src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)kq, 0, dispatch_get_main_queue());
        static BOOL pending;
        dispatch_source_set_event_handler(src, ^{
            struct kevent got[8]; struct timespec zero = {0, 0}; uint32_t flags = 0;
            int n = kevent(kq, NULL, 0, got, 8, &zero);
            for (int i = 0; i < n; i++) flags |= (uint32_t)got[i].fflags;
            DMLog([NSString stringWithFormat:@"[finder] drives: file system event 0x%x", flags]);   // (rare: a mount or unmount anywhere)
            DMFinderWatchLiveFolders();
            if (!(flags & (VQ_MOUNT | VQ_UNMOUNT | VQ_DEAD | VQ_NOTRESP | VQ_UPDATE)) || pending) return;
            pending = YES;   // (a plug-in mounts in steps: read once things settle, and again a little later)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                pending = NO;
                DMFinderDrivesCheck(flags & VQ_MOUNT ? @"mounted" : flags & VQ_UNMOUNT ? @"unmounted" : @"changed");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMFinderDrivesCheck(@"settled"); });
            });
        });
        dispatch_source_set_cancel_handler(src, ^{ close(kq); });
        dispatch_resume(src);
    });
}
static DMFinderWindow *DMFinderFront(void) {
    for (DMNativeWindow *w in [gNativeWindows reverseObjectEnumerator]) if ([w isKindOfClass:[DMFinderWindow class]]) return (DMFinderWindow *)w;
    return nil;
}
static void DMFinderOpen(NSString *path, BOOL newWindow) {
    DM_FEATURE_MARK("finder-window");
    if (!gFinderOn) { DMLog(@"[finder] Finder is switched off in Settings: no window"); return; }
    DMFinderWindow *f = newWindow ? nil : DMFinderFront();
    if (!f) {
        CGRect d = DMNativeDesktop();
        CGFloat w = MIN(760.0, d.size.width - 40.0), h = MIN(500.0, d.size.height - 40.0);
        NSUInteger n = gNativeWindows.count;
        f = [[DMFinderWindow alloc] initWithTitle:@"Finder" frame:CGRectMake(CGRectGetMidX(d) - w / 2.0 + 24.0 * n, CGRectGetMidY(d) - h / 2.0 + 24.0 * n, w, h)];
    }
    [f show];
    [f go:path.length ? path : (DMFinderOnMyIPad() ?: @"/var/mobile/Documents")];
    DMLog([NSString stringWithFormat:@"[finder] window for %@ (%lu native windows)", path, (unsigned long)gNativeWindows.count]);
}

// ---- Finder in the Dock (dock/FinderIcon.m, the Dock's library) ------------------------------------------------------------------------------
// A tap on the Dock's Finder icon, like a Mac: Finder's open windows come forward (the front one active); none open but some minimized -> the
// last one comes back; none at all -> a new window. The long-press menu's New Finder Window is its own notification. How many Finder windows
// exist (open or minimized) is published as the state of ...finder.windows, for the Dock's running dot.
static void DMFinderDockTapped(void) {
    if (!gFinderOn) return;
    DM_FEATURE_MARK("finder-dock-tap");
    NSMutableArray<DMNativeWindow *> *open = [NSMutableArray array], *mini = [NSMutableArray array];
    for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMFinderWindow class]]) [w.hidden ? mini : open addObject:w];
    if (open.count) { for (DMNativeWindow *w in open) [w.superview bringSubviewToFront:w]; [open.lastObject activate]; }
    else if (mini.count) [mini.lastObject show];
    else DMFinderOpen(nil, YES);
    DMLog([NSString stringWithFormat:@"[finder] Dock icon: %lu open, %lu minimized", (unsigned long)open.count, (unsigned long)mini.count]);
}
static void DMFinderPublishWindowCount(void) {
    static int token = 0; static uint64_t last = UINT64_MAX;
    if (!token && notify_register_check("com.besiktasliseba.macstatusbar.finder.windows", &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    uint64_t n = 0; for (DMNativeWindow *w in gNativeWindows) if ([w isKindOfClass:[DMFinderWindow class]]) n++;
    if (n == last) return;
    last = n;
    notify_set_state(token, n);
    notify_post("com.besiktasliseba.macstatusbar.finder.windows");
}
static void DMOpenSettingsLinkFullScreen(NSString *link, int attempt);   // (StatusBar.x)
// The Finder icon's "Remove from Dock": Finder never leaves the Dock (as on a Mac); a question says where it can be hidden instead.
static void DMFinderRemoveFromDockAsked(void) {
    DM_FEATURE_MARK("finder-remove-from-dock");
    UIView *host = DMMenuHost();
    if (!host) return;
    DMShowConfirm(host, @"Finder always stays in the Dock", @"You can hide it in Settings > Dock.", @"Open Settings", NO, ^{
        DMOpenSettingsLinkFullScreen(@"prefs:root=DOCK_MAGNIFICATION&path=FINDER", 0);
    });
}
static void DMFinderDockInit(void) {
    static int t1, t2, t3;
    notify_register_dispatch("com.besiktasliseba.macstatusbar.finder.dock", &t1, dispatch_get_main_queue(), ^(int t) { DMFinderDockTapped(); });
    notify_register_dispatch("com.besiktasliseba.macstatusbar.finder.new", &t2, dispatch_get_main_queue(), ^(int t) { DMFinderOpen(nil, YES); });
    notify_register_dispatch("com.besiktasliseba.macstatusbar.finder.remove", &t3, dispatch_get_main_queue(), ^(int t) { if (gFinderOn) DMFinderRemoveFromDockAsked(); });
    DMFinderPublishWindowCount();
    DMFDSweep();   // (files staged for apps before a respring)
}
