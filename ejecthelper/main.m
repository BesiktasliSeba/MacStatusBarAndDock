// msbdeject -- ejects a connected drive for Finder (the Dock's Trash since 1.7.0; Finder's sidebar Eject, File > Eject and the drive's menu since
// 1.7.3). Since 1.7.3 it is run by MacStatusBar&Dock's root helper (sshtoggled, a launchd job), never by SpringBoard: iPadOS 18 refuses SpringBoard's
// spawn of it (EPERM). The request, its checks and the answer: common/DriveEject.h.
// The eject is the Files app's own where there is one: StorageKit asks storagekitd to eject the disk the volume is on (every volume of it is
// unmounted, then the disk is let go); storagekitd only takes that request from a client with its state-changing entitlement, which this helper
// has (entitlements.plist) and SpringBoard has not. iPadOS 15 has no StorageKit: there it is DiskArbitration's unmount and eject (DAEject.h, not
// tried on a real drive yet). Nothing is forced: a disk in use stays, and the answer says so.
//
// It checks the folder for itself, whoever started it: only a volume mounted exactly at /var/mobile/Library/LiveFiles/<provider>/<volume> from a
// local disk (a USB drive, an SD card -- the drives Finder lists), and only a disk the system calls external. Never the iPad's own storage.
//
//   msbdeject <volume folder>          eject; prints one line: "ok", "busy: <why>", "refused: <why>" or "error: <why>"; exit 0 / 3 / 2 / 1
//   msbdeject --check <volume folder>  the checks only, nothing is ejected ("drive <name> on <disk>" or "refused: ...")
//   msbdeject --info <path>            what the system says about the disk a path is on: StorageKit or DiskArbitration, and the volume's names
//                                      (read-only; for tests)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdlib.h>
#include "../common/DriveEject.h"
#include "DAEject.h"

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
// Where StorageKit is not there (iPadOS 15): DiskArbitration (DAEject.h). One line and the exit code, as for StorageKit's eject.
static int EjectWithoutStorageKit(NSString *vol, NSString *from) {
    NSString *bsd = MSBDDriveBSDName(from);
    if (!bsd) { printf("error: the system doesn't know that drive's disk\n"); return 1; }
    MSBDDAResult r = MSBDDAEject(bsd.UTF8String, vol.fileSystemRepresentation);
    if (r.code == 0) { printf("ok\n"); return 0; }
    if (r.code == 3) { printf("busy: %s\n", r.why[0] ? r.why : "in use"); return 3; }
    if (r.code == 2) { printf("refused: %s\n", r.why); return 2; }
    printf("error: %s\n", r.code < 0 ? "this iPadOS can't eject it here" : r.why);
    return 1;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        BOOL check = argc == 3 && !strcmp(argv[1], "--check"), info = argc == 3 && !strcmp(argv[1], "--info");
        const char *arg = check || info ? argv[2] : argc == 2 ? argv[1] : NULL;
        if (!arg || (argc == 3 && !check && !info) || arg[0] == '-') { printf("refused: usage: msbdeject [--check | --info] <volume folder>\n"); return 2; }
        if (info) {   // (read-only: never ejects)
            char real[PATH_MAX];
            if (!realpath(arg, real)) { printf("error: not there\n"); return 1; }
            struct statfs fs; BOOL fsOK = statfs(real, &fs) == 0;
            NSString *from = fsOK ? [NSString stringWithUTF8String:fs.f_mntfromname] : nil, *on = fsOK ? [NSString stringWithUTF8String:fs.f_mntonname] : nil;
            NSString *label = fsOK ? MSBDDriveVolumeLabel(fs.f_mntonname) : nil;
            printf("info: mounted on %s from %s (%s), label %s, Finder's name %s\n", on.UTF8String ?: "-", from.UTF8String ?: "-", fsOK ? fs.f_fstypename : "-",
                   label ? [NSString stringWithFormat:@"\"%@\"", label].UTF8String : "none", [NSString stringWithFormat:@"\"%@\"", MSBDDriveName(on, from, label) ?: @""].UTF8String);
            id m = StorageManager();
            if (!m) {   // (15: no StorageKit -- what DiskArbitration knows instead)
                char da[900]; MSBDDADescribe(MSBDDriveBSDName(from).UTF8String, da, sizeof da);
                printf("info: StorageKit NOT there; %s\n", da);
                return 0;
            }
            id d = DiskForPath(m, [NSString stringWithUTF8String:real]);
            id whole = WholeDisk(m, d);
            printf("info: manager yes, disk %s (%s), whole %s, internal %d, external %d, removable %d, mount point %s, volume name %s\n",
                   d ? "found" : "NOT found", [Call(d, @"diskIdentifier") description].UTF8String ?: "-", [Call(whole, @"diskIdentifier") description].UTF8String ?: "-",
                   CallB(d, @"isInternal"), CallB(d, @"isExternal"), CallB(d, @"isRemovable"), [Call(d, @"mountPoint") description].UTF8String ?: "-", [Call(d, @"volumeName") description].UTF8String ?: "-");
            return d ? 0 : 1;
        }
        NSString *why = nil, *from = nil;
        NSString *vol = MSBDEjectVolumeAt(arg, &from, &why);   // (common/DriveEject.h: the kernel's mount table)
        if (!vol) { printf("refused: %s\n", why.UTF8String); return 2; }
        if (check) { printf("drive %s on %s\n", MSBDDriveName(vol, from, MSBDDriveVolumeLabel(vol.fileSystemRepresentation)).UTF8String, from.UTF8String); return 0; }
        id m = StorageManager();
        if (!m) return EjectWithoutStorageKit(vol, from);
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
