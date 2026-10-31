// DAEject.h -- the eject where StorageKit is not there: iPadOS 15 (1.7.3, item 6; NOT tried on a real drive yet -- the M1 has none). The way a
// Mac's `diskutil eject` does it, with DiskArbitration: every volume of the disk unmounted, never forced (a file open on it keeps it, and the answer
// says "busy"), then the disk let go. UserFS mounts the drive's LiveFiles folder itself, so DiskArbitration may not count that mount as its own:
// after its unmount the folder is looked at again, and a mount still there is unmounted here (not forced either) -- the disk is never let go
// under a mounted volume. What was written to the drive goes first (sync). DiskArbitration is opened at run time (a private framework on iPadOS,
// a public one on macOS): plain C and CoreFoundation, so the Mac test runs this very code against a disk image (tools/test-driveeject.sh).
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/mount.h>
#include <stdbool.h>
#include <stdlib.h>
#include <limits.h>

typedef struct { int code; char why[256]; } MSBDDAResult;   // code: 0 ejected, 3 in use, 2 refused, 1 failed, -1 no DiskArbitration here
typedef struct __DASession *MSBDDASession;
typedef struct __DADisk *MSBDDADisk;
typedef struct __DADissenter *MSBDDADissenter;
typedef void (*MSBDDADone)(MSBDDADisk, MSBDDADissenter, void *);
typedef struct {
    MSBDDASession (*sessionCreate)(CFAllocatorRef);
    void (*setQueue)(MSBDDASession, dispatch_queue_t);
    MSBDDADisk (*fromBSDName)(CFAllocatorRef, MSBDDASession, const char *);
    MSBDDADisk (*wholeDisk)(MSBDDADisk);
    CFDictionaryRef (*describe)(MSBDDADisk);
    void (*unmount)(MSBDDADisk, uint32_t, MSBDDADone, void *);
    void (*eject)(MSBDDADisk, uint32_t, MSBDDADone, void *);
    int32_t (*status)(MSBDDADissenter);
    CFStringRef (*statusString)(MSBDDADissenter);
    const CFStringRef *internalKey;   // (kDADiskDescriptionDeviceInternalKey)
} MSBDDAFuncs;
#define kMSBDDAUnmountWhole 0x00000001u   // (kDADiskUnmountOptionWhole; never kDADiskUnmountOptionForce)
#define kMSBDDABusy 0xF8DA0002            // (kDAReturnBusy)
#define kMSBDDAExclusive 0xF8DA0004       // (kDAReturnExclusiveAccess)
#define kMSBDDANotMounted 0xF8DA0007      // (kDAReturnNotMounted)

// DiskArbitration's functions, or false when this system has not got them all (then nothing is tried).
static inline bool MSBDDALoad(MSBDDAFuncs *f) {
    memset(f, 0, sizeof *f);
    void *h = dlopen("/System/Library/PrivateFrameworks/DiskArbitration.framework/DiskArbitration", RTLD_NOW);   // (iPadOS)
    if (!h) h = dlopen("/System/Library/Frameworks/DiskArbitration.framework/DiskArbitration", RTLD_NOW);       // (macOS: the Mac test)
    if (!h) return NO;
    f->sessionCreate = (MSBDDASession (*)(CFAllocatorRef))dlsym(h, "DASessionCreate");
    f->setQueue = (void (*)(MSBDDASession, dispatch_queue_t))dlsym(h, "DASessionSetDispatchQueue");
    f->fromBSDName = (MSBDDADisk (*)(CFAllocatorRef, MSBDDASession, const char *))dlsym(h, "DADiskCreateFromBSDName");
    f->wholeDisk = (MSBDDADisk (*)(MSBDDADisk))dlsym(h, "DADiskCopyWholeDisk");
    f->describe = (CFDictionaryRef (*)(MSBDDADisk))dlsym(h, "DADiskCopyDescription");
    f->unmount = (void (*)(MSBDDADisk, uint32_t, MSBDDADone, void *))dlsym(h, "DADiskUnmount");
    f->eject = (void (*)(MSBDDADisk, uint32_t, MSBDDADone, void *))dlsym(h, "DADiskEject");
    f->status = (int32_t (*)(MSBDDADissenter))dlsym(h, "DADissenterGetStatus");
    f->statusString = (CFStringRef (*)(MSBDDADissenter))dlsym(h, "DADissenterGetStatusString");
    f->internalKey = (const CFStringRef *)dlsym(h, "kDADiskDescriptionDeviceInternalKey");
    return f->sessionCreate && f->setQueue && f->fromBSDName && f->wholeDisk && f->describe && f->unmount && f->eject && f->status && f->internalKey;
}
// One DiskArbitration request's outcome (its callback, on the session's queue).
typedef struct { dispatch_semaphore_t done; int32_t status; char text[160]; MSBDDAFuncs *f; } MSBDDAWait;
static void MSBDDACallback(MSBDDADisk disk, MSBDDADissenter dissenter, void *context) {
    MSBDDAWait *w = (MSBDDAWait *)context;
    w->status = dissenter ? w->f->status(dissenter) : 0;
    w->text[0] = 0;
    CFStringRef s = dissenter && w->f->statusString ? w->f->statusString(dissenter) : NULL;
    if (s) CFStringGetCString(s, w->text, sizeof w->text, kCFStringEncodingUTF8);
    dispatch_semaphore_signal(w->done);
}
static inline bool MSBDDABusyStatus(int32_t st) {   // (in use: DiskArbitration's busy / exclusive access, or the kernel's EBUSY carried as unix_err)
    return st == (int32_t)kMSBDDABusy || st == (int32_t)kMSBDDAExclusive || st == (int32_t)(0xC000 | EBUSY);
}
static inline bool MSBDDAStillMounted(const char *mountPoint) {   // (the folder is still a mount's own -- as the kernel spells it: /var is /private/var)
    struct statfs fs; char real[PATH_MAX];
    return mountPoint && realpath(mountPoint, real) && statfs(real, &fs) == 0 && !strcmp(fs.f_mntonname, real);
}
// The eject: bsdName = the volume's disk ("disk2s1"), mountPoint = its folder as the kernel spells it (checked by the caller). 20 s per step at most.
static inline MSBDDAResult MSBDDAEject(const char *bsdName, const char *mountPoint) {
    MSBDDAResult r = { 1, "" };
    MSBDDAFuncs f;
    if (!MSBDDALoad(&f)) { r.code = -1; snprintf(r.why, sizeof r.why, "this iPadOS has no DiskArbitration to eject it with"); return r; }
    sync();   // (what was written to the drive is on it before anything is unmounted)
    MSBDDASession s = f.sessionCreate(kCFAllocatorDefault);
    if (!s) { snprintf(r.why, sizeof r.why, "the system's disk service isn't there"); return r; }
    dispatch_queue_t q = dispatch_queue_create("msbd.eject.da", DISPATCH_QUEUE_SERIAL);
    f.setQueue(s, q);
    MSBDDADisk disk = f.fromBSDName(kCFAllocatorDefault, s, bsdName), whole = disk ? f.wholeDisk(disk) : NULL;
    if (!whole && disk) { whole = disk; CFRetain(whole); }
    MSBDDAWait w = { dispatch_semaphore_create(0), 0, "", &f };
    if (!whole) { snprintf(r.why, sizeof r.why, "the system doesn't know that drive"); goto out; }
    {   // never the iPad's own storage (DiskArbitration says what the device is, as StorageKit does on 16 on)
        CFDictionaryRef d = f.describe(whole);
        CFTypeRef internal = d ? CFDictionaryGetValue(d, *f.internalKey) : NULL;
        bool isInternal = internal && CFGetTypeID(internal) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)internal);
        if (d) CFRelease(d);
        if (isInternal) { r.code = 2; snprintf(r.why, sizeof r.why, "it is the iPad's own storage"); goto out; }
    }
    f.unmount(whole, kMSBDDAUnmountWhole, MSBDDACallback, &w);   // (every volume of the disk; not forced)
    if (dispatch_semaphore_wait(w.done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0) { snprintf(r.why, sizeof r.why, "unmounting it didn't finish in time"); goto out; }
    if (MSBDDABusyStatus(w.status)) { r.code = 3; snprintf(r.why, sizeof r.why, "%s", w.text[0] ? w.text : "in use"); goto out; }
    if (MSBDDAStillMounted(mountPoint) && unmount(mountPoint, 0) != 0) {   // (UserFS's own mount, if DiskArbitration left it: unmounted here, not forced)
        if (errno == EBUSY) { r.code = 3; snprintf(r.why, sizeof r.why, "in use"); }
        else snprintf(r.why, sizeof r.why, "it couldn't be unmounted (%d%s%s)", errno, w.status ? ", " : "", w.status ? (w.text[0] ? w.text : "DiskArbitration said no") : "");
        goto out;
    }
    if (MSBDDAStillMounted(mountPoint)) { snprintf(r.why, sizeof r.why, "it is still mounted"); goto out; }
    w.status = 0; w.text[0] = 0;
    f.eject(whole, 0, MSBDDACallback, &w);   // (kDADiskEjectOptionDefault: the disk let go)
    if (dispatch_semaphore_wait(w.done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC)) != 0) { snprintf(r.why, sizeof r.why, "it was unmounted, but letting it go didn't finish in time"); goto out; }
    if (w.status && w.status != (int32_t)kMSBDDANotMounted) {
        if (MSBDDABusyStatus(w.status)) r.code = 3;
        snprintf(r.why, sizeof r.why, "it was unmounted, but the system didn't let it go (%s)", w.text[0] ? w.text : "no reason given");
        goto out;
    }
    r.code = 0;
out:
    // (the session off its queue, then the queue drained: an answer DiskArbitration has already sent -- one that came just after a step's 20 s --
    //  runs now, while `w` and `f`, on this stack, are still there; none can come after. Before, a late one would have written into a call that
    //  had returned. 1.7.3 review)
    f.setQueue(s, NULL);
    dispatch_sync(q, ^{});
    if (whole) CFRelease(whole);
    if (disk) CFRelease(disk);
    CFRelease(s);
    return r;
}
// What DiskArbitration says about the disk a volume is on (read-only, for --info): the description's keys that matter here, by their names.
static inline void MSBDDADescribe(const char *bsdName, char *out, size_t len) {
    MSBDDAFuncs f;
    if (!out || !len) return;
    if (!MSBDDALoad(&f)) { snprintf(out, len, "DiskArbitration NOT there"); return; }
    MSBDDASession s = f.sessionCreate(kCFAllocatorDefault);
    MSBDDADisk disk = s && bsdName ? f.fromBSDName(kCFAllocatorDefault, s, bsdName) : NULL, whole = disk ? f.wholeDisk(disk) : NULL;
    CFDictionaryRef d = disk ? f.describe(disk) : NULL, wd = whole ? f.describe(whole) : NULL;
    char a[700] = "";
    const char *keys[] = { "kDADiskDescriptionVolumeNameKey", "kDADiskDescriptionVolumePathKey", "kDADiskDescriptionVolumeKindKey", "kDADiskDescriptionVolumeLifsURLKey",
                           "kDADiskDescriptionMediaEjectableKey", "kDADiskDescriptionMediaRemovableKey", "kDADiskDescriptionDeviceProtocolKey" };
    void *h = dlopen("/System/Library/PrivateFrameworks/DiskArbitration.framework/DiskArbitration", RTLD_NOW) ?: dlopen("/System/Library/Frameworks/DiskArbitration.framework/DiskArbitration", RTLD_NOW);
    for (size_t i = 0; d && h && i < sizeof keys / sizeof keys[0]; i++) {
        const CFStringRef *k = (const CFStringRef *)dlsym(h, keys[i]);
        CFTypeRef v = k ? CFDictionaryGetValue(d, *k) : NULL;
        char one[200] = "-";
        if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) snprintf(one, sizeof one, "%s", CFBooleanGetValue((CFBooleanRef)v) ? "yes" : "no");
        else if (v && CFGetTypeID(v) == CFURLGetTypeID()) { CFStringRef t = CFURLGetString((CFURLRef)v); if (t) CFStringGetCString(t, one, sizeof one, kCFStringEncodingUTF8); }
        else if (v && CFGetTypeID(v) == CFStringGetTypeID()) CFStringGetCString((CFStringRef)v, one, sizeof one, kCFStringEncodingUTF8);
        else if (v) { CFStringRef t = CFCopyDescription(v); if (t) { CFStringGetCString(t, one, sizeof one, kCFStringEncodingUTF8); CFRelease(t); } }
        size_t at = strlen(a);
        snprintf(a + at, sizeof a - at, "%s%s=%s", at ? ", " : "", keys[i] + 18, k ? one : "(no such key)");   // (+18: past "kDADiskDescription")
    }
    CFTypeRef internal = wd ? CFDictionaryGetValue(wd, *f.internalKey) : NULL;
    bool known = internal && CFGetTypeID(internal) == CFBooleanGetTypeID();
    snprintf(out, len, "DiskArbitration there; disk %s: %s; whole disk %s, internal %s", bsdName ?: "-", d ? a : "NOT known", whole ? "found" : "NOT found",
             known ? (CFBooleanGetValue((CFBooleanRef)internal) ? "yes" : "no") : "?");
    if (d) CFRelease(d);
    if (wd) CFRelease(wd);
    if (whole) CFRelease(whole);
    if (disk) CFRelease(disk);
    if (s) CFRelease(s);
}
