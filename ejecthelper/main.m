// msbdeject -- ejects a connected drive, for the Dock's Trash (1.7.0). Finder (statusbar/DockTrash.h) spawns it when drives are dropped on the bin,
// with the drive's volume folder. The eject is the Files app's own: StorageKit asks storagekitd to eject the disk the volume is on (every volume of
// it is unmounted, then the disk is let go); storagekitd only takes that request from a client with its state-changing entitlement, which this
// helper has (entitlements.plist) and SpringBoard has not. Nothing is forced: a disk in use stays, and the answer says so.
//
// It checks the folder for itself, whoever spawned it: only a volume mounted exactly at /var/mobile/Library/LiveFiles/<provider>/<volume> from a
// local disk (a USB drive, an SD card -- the drives Finder lists), and only a disk StorageKit calls external. Never the iPad's own storage.
//
//   msbdeject <volume folder>          eject; prints one line: "ok", "busy: <why>", "refused: <why>" or "error: <why>"; exit 0 / 3 / 2 / 1
//   msbdeject --check <volume folder>  the checks only, nothing is ejected ("drive <name> on <disk>" or "refused: ...")
//   msbdeject --info <path>            what StorageKit says about the disk a path is on (read-only; for tests)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>

static NSString *Norm(NSString *p) {   // (/private/var is /var, no trailing slash: as Finder spells paths)
    NSString *s = p.stringByStandardizingPath;
    if ([s isEqualToString:@"/private/var"] || [s hasPrefix:@"/private/var/"]) s = [s substringFromIndex:8];
    while (s.length > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}
static BOOL LocalDisk(NSString *from) {   // "fat://disk2s1/NO NAME", "exfat://disk3s1/X", "/dev/disk4s1"
    if ([from hasPrefix:@"/dev/disk"]) return YES;
    NSRange r = [from rangeOfString:@"://"];
    return r.location != NSNotFound && r.location > 0 && [[from substringFromIndex:r.location + 3] hasPrefix:@"disk"];
}
// The volume folder, checked: nil and *why when it is not a connected drive's own mount point.
static NSString *CheckedVolume(const char *arg, NSString **from, NSString **why) {
    char real[PATH_MAX];
    if (!arg || !realpath(arg, real)) { *why = @"that folder isn't there"; return nil; }
    NSString *p = Norm([NSString stringWithUTF8String:real]);
    struct statfs fs;
    if (statfs(real, &fs) != 0) { *why = [NSString stringWithFormat:@"its volume can't be read (%d)", errno]; return nil; }
    NSString *on = Norm([NSString stringWithUTF8String:fs.f_mntonname] ?: @""), *src = [NSString stringWithUTF8String:fs.f_mntfromname] ?: @"";
    if (![on isEqualToString:p]) { *why = @"it isn't a drive's own folder"; return nil; }
    NSString *lf = @"/var/mobile/Library/LiveFiles/";
    if (![p hasPrefix:lf] || [[p substringFromIndex:lf.length] pathComponents].count != 2) { *why = @"it isn't a connected drive"; return nil; }
    if (!LocalDisk(src)) { *why = @"it isn't a drive connected to this iPad"; return nil; }
    if (fs.f_flags & MNT_ROOTFS) { *why = @"it is the iPad's own storage"; return nil; }
    if (from) *from = src;
    return p;
}
static id Call(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static BOOL CallB(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return [o respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(o, s); }
static id StorageManager(void) {
    dlopen("/System/Library/PrivateFrameworks/StorageKit.framework/StorageKit", RTLD_NOW);
    Class c = objc_getClass("SKManager");
    if (!c) return nil;
    id m = Call((id)c, @"syncSharedManager") ?: Call((id)c, @"sharedManager");   // (synchronous: the disks are listed when it returns)
    return m;
}
static id WholeDisk(id m, id disk) {   // (the whole disk a volume's disk is part of; nil where StorageKit has no such call or no answer)
    SEL s = NSSelectorFromString(@"wholeDiskForDisk:");
    return disk && [m respondsToSelector:s] ? ((id (*)(id, SEL, id))objc_msgSend)(m, s, disk) : nil;
}
static id DiskForPath(id m, NSString *path) {
    SEL s = NSSelectorFromString(@"diskForPath:");
    if (![m respondsToSelector:s]) return nil;
    for (int i = 0; i < 10; i++) {   // (the list may still be filling right after the start: up to 5 s)
        id d = ((id (*)(id, SEL, id))objc_msgSend)(m, s, path);
        if (d) return d;
        [NSThread sleepForTimeInterval:0.5];
    }
    return nil;
}
static BOOL BusyError(NSError *e) {   // (in use: a file open on it -- the kernel's EBUSY, DiskArbitration's kDAReturnBusy / kDAReturnExclusiveAccess)
    for (NSError *x = e; x; x = x.userInfo[NSUnderlyingErrorKey]) {
        if (x.code == EBUSY || x.code == (NSInteger)0xF8DA0002 || x.code == (NSInteger)(int32_t)0xF8DA0002 || x.code == (NSInteger)0xF8DA0004 || x.code == (NSInteger)(int32_t)0xF8DA0004) return YES;
        if ([x.localizedDescription.lowercaseString containsString:@"busy"] || [x.localizedDescription.lowercaseString containsString:@"in use"]) return YES;
    }
    return NO;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        BOOL check = argc == 3 && !strcmp(argv[1], "--check"), info = argc == 3 && !strcmp(argv[1], "--info");
        const char *arg = check || info ? argv[2] : argc == 2 ? argv[1] : NULL;
        if (!arg || (argc == 3 && !check && !info)) { printf("refused: usage: msbdeject [--check | --info] <volume folder>\n"); return 2; }
        if (info) {   // (read-only: never ejects)
            char real[PATH_MAX];
            if (!realpath(arg, real)) { printf("error: not there\n"); return 1; }
            id m = StorageManager();
            id d = m ? DiskForPath(m, [NSString stringWithUTF8String:real]) : nil;
            id whole = WholeDisk(m, d);
            printf("info: manager %s, disk %s (%s), whole %s, internal %d, external %d, removable %d, mount point %s\n", m ? "yes" : "NO",
                   d ? "found" : "NOT found", [Call(d, @"diskIdentifier") description].UTF8String ?: "-", [Call(whole, @"diskIdentifier") description].UTF8String ?: "-",
                   CallB(d, @"isInternal"), CallB(d, @"isExternal"), CallB(d, @"isRemovable"), [Call(d, @"mountPoint") description].UTF8String ?: "-");
            return d ? 0 : 1;
        }
        NSString *why = nil, *from = nil;
        NSString *vol = CheckedVolume(arg, &from, &why);
        if (!vol) { printf("refused: %s\n", why.UTF8String); return 2; }
        if (check) { printf("drive %s on %s\n", vol.lastPathComponent.UTF8String, from.UTF8String); return 0; }
        id m = StorageManager();
        if (!m) { printf("error: the system's storage service isn't there\n"); return 1; }
        id disk = DiskForPath(m, vol);
        if (!disk) { printf("error: the system doesn't know that drive\n"); return 1; }
        if (CallB(disk, @"isInternal") || !(CallB(disk, @"isExternal") || CallB(disk, @"isRemovable"))) { printf("refused: it is the iPad's own storage\n"); return 2; }
        id whole = WholeDisk(m, disk) ?: disk;
        if (CallB(whole, @"isInternal")) { printf("refused: it is the iPad's own storage\n"); return 2; }
        SEL ej = NSSelectorFromString(@"ejectWithError:");
        if (![whole respondsToSelector:ej]) { printf("error: this iPadOS can't eject it here\n"); return 1; }
        NSError *e = nil;
        BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(whole, ej, &e);   // (StorageKit's own synchronous eject: every volume, then the disk)
        if (ok) { printf("ok\n"); return 0; }
        if (BusyError(e)) { printf("busy: %s\n", (e.localizedDescription ?: @"in use").UTF8String); return 3; }
        printf("error: %s\n", (e.localizedDescription ?: @"the eject didn't work").UTF8String);
        return 1;
    }
}
