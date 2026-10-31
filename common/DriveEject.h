// DriveEject.h -- a connected drive's eject and its name (1.7.3): the rules Finder (statusbar/DriveEject.h), the root helper (macsettings/sshtoggled)
// and the eject helper (ejecthelper/, msbdeject) share. Foundation and libc only, so the Mac test (tools/test-driveeject.sh) runs this very code.
//
// The eject runs in the root helper's launchd job, never in a process SpringBoard starts: iPadOS 18 refuses SpringBoard's posix_spawn of anything
// under /var/jb (EPERM, "The eject helper could not be started (1)", 1.7.2 item 21), and one path on every version is one path to trust.
//  - Finder writes the request into our own preferences (kMSBDEjectDomain, kMSBDEjectRequestKey: an id and the drive's volume folder) and posts
//    kMSBDEjectRequestName. Who may ask: a process that can write mobile's preferences of ours -- SpringBoard, or root; a sandboxed app can't. The
//    post carries nothing (anyone may post one): the helper reads the request, takes it away at once (no replay), and accepts only what
//    MSBDEjectRequestFrom does -- an id and one volume folder, no other keys, no arguments.
//  - The helper checks the folder itself (MSBDEjectVolumeAt: the kernel's mount table -- a connected drive's own mount point under LiveFiles, from
//    a local disk, never the iPad's own storage) and runs msbdeject with that one argument, as the kernel spells it; msbdeject checks it once more
//    and ejects (StorageKit from 16 on; 15: DiskArbitration, ejecthelper/DAEject.h).
//  - The answer: msbdeject's one line ("ok", "busy: ...", "refused: ...", "error: ..."), written with the request's id into a root-owned file
//    (kMSBDEjectAnswerFile: only root writes in that folder) and kMSBDEjectAnswerName posted. Finder takes only the answer with its own id.
//  - Finder looks first that the helper is there (its pid in kMSBDEjectHelperState, a live "sshtoggled") and then waits kMSBDEjectWait seconds at
//    most: either way the user is told in a Mac's words, never a silent nothing.
#pragma once
#import <Foundation/Foundation.h>
#include <sys/mount.h>
#include <sys/attr.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <limits.h>
#include <notify.h>
#include <math.h>

#define kMSBDEjectDomain      "com.besiktasliseba.macstatusbaranddock"
#define kMSBDEjectRequestKey  "ejectRequest"                               // @{id: 32 hex digits, volume: the drive's volume folder, at: when}
#define kMSBDEjectRequestName "com.besiktasliseba.msbd.eject.request"      // Finder: "look at the request" (it carries nothing)
#define kMSBDEjectAnswerName  "com.besiktasliseba.msbd.eject.answered"     // the helper: "look at the answer"
#define kMSBDEjectHelperState "com.besiktasliseba.msbd.eject.helper"       // state: the root helper's pid while it takes ejects
#define kMSBDEjectHelperName  "sshtoggled"                                 // (that pid's process name: the root helper's launchd job)
#define kMSBDEjectAnswerFile  "/var/jb/var/lib/sshtoggled-engines/eject-answer"
#define kMSBDEjectHelperPath  "/var/jb/usr/libexec/msbdeject"
#define kMSBDLiveFiles        "/var/mobile/Library/LiveFiles"             // (connected drives: <LiveFiles>/<provider>/<volume>)
static const double kMSBDEjectHelperTimeout = 30.0;   // the root helper gives msbdeject this long, then stops it (an eject takes a few seconds)
static const double kMSBDEjectWait = 40.0;            // Finder waits this long for the answer (longer than the helper's own limit: its answer comes first)
// The answers Finder makes up itself (MSBDEjectMessage turns them into the dialog's words like any other).
#define kMSBDEjectNoHelperLine @"error: MacStatusBar&Dock’s helper isn’t running. Try again in a moment; if it keeps happening, reinstall MacStatusBar&Dock"
#define kMSBDEjectNoAnswerLine @"error: MacStatusBar&Dock’s helper didn’t answer. Try again in a moment"

// ---- paths ----------------------------------------------------------------------------------------------------------------------------------
// One spelling, as Finder's (DMFinderNorm): /private/var is /var, no trailing slash, "." and ".." resolved from the text.
static inline NSString *MSBDEjectNorm(NSString *p) {
    if (![p isKindOfClass:[NSString class]] || !p.length) return p;
    NSString *s = p.stringByStandardizingPath;
    if ([s isEqualToString:@"/private/var"] || [s hasPrefix:@"/private/var/"]) s = [s substringFromIndex:8];
    while (s.length > 1 && [s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    return s;
}
// A mount's source is a disk of this iPad: "fat://disk2s1/NO NAME" (UserFS, 15), "exfat://disk3s1/X", "/dev/disk4s1" -- never a network share.
static inline BOOL MSBDEjectFromLocalDisk(NSString *from) {
    if (![from isKindOfClass:[NSString class]]) return NO;
    if ([from hasPrefix:@"/dev/disk"]) return YES;
    NSRange r = [from rangeOfString:@"://"];
    return r.location != NSNotFound && r.location > 0 && [[from substringFromIndex:r.location + 3] hasPrefix:@"disk"];
}
// A volume folder in the shape of a connected drive's: <LiveFiles>/<provider>/<volume>, nothing deeper or higher (the text alone; the kernel's
// mount table decides whether it is one, MSBDEjectCheckMount).
static inline BOOL MSBDEjectInLiveFiles(NSString *normalised) {
    NSString *lf = @kMSBDLiveFiles "/";
    if (![normalised hasPrefix:lf]) return NO;
    NSArray *rest = [[normalised substringFromIndex:lf.length] pathComponents];
    if (rest.count != 2) return NO;
    for (NSString *c in rest) if (!c.length || [c isEqualToString:@"."] || [c isEqualToString:@".."] || [c isEqualToString:@"/"]) return NO;
    return YES;
}

// ---- the request ----------------------------------------------------------------------------------------------------------------------------
// An id: 32 lowercase hex digits (Finder makes a random one per eject; the answer must carry it).
static inline BOOL MSBDEjectIsRequestID(id s) {
    if (![s isKindOfClass:[NSString class]] || [s length] != 32) return NO;
    for (NSUInteger i = 0; i < 32; i++) { unichar c = [s characterAtIndex:i]; if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return NO; }
    return YES;
}
static inline NSString *MSBDEjectNewRequestID(void) {
    uint8_t b[16]; arc4random_buf(b, sizeof b);
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}
// What the root helper accepts: a dictionary of exactly an id, a volume folder (a string, absolute, at most 1024 characters, no control
// characters, one the file system can spell -- a lone UTF-16 surrogate, which a property list carries, has none, and the helper's
// -fileSystemRepresentation of it raises: the root helper ended (1.7.3 review) --, in the shape of a connected drive's folder) and when it was asked
// (seconds since 1970: a request is good for kMSBDEjectWait only --
// one left behind, say by a SpringBoard that went away while it waited, is never carried out later, at the helper's next start). `now`: the
// same clock. YES: all good. NO with *rid set: the id is good, the rest is not (*why says why: answered "refused", so Finder is not left
// waiting). NO with *rid nil: not a request at all (nobody can be told; ignored).
static inline BOOL MSBDEjectRequestFrom(id plist, NSTimeInterval now, NSString **rid, NSString **volume, NSString **why) {
    if (rid) *rid = nil;
    if (volume) *volume = nil;
    if (why) *why = nil;
    if (![plist isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *d = plist;
    id i = d[@"id"], v = d[@"volume"], at = d[@"at"];
    if (!MSBDEjectIsRequestID(i)) return NO;
    if (rid) *rid = i;
    if (d.count != 3 || ![v isKindOfClass:[NSString class]] || ![at isKindOfClass:[NSNumber class]]) { if (why) *why = @"that isn't a request Finder makes"; return NO; }
    double age = now - [at doubleValue];
    if (!isfinite(age) || age < -5.0 || age > kMSBDEjectWait) { if (why) *why = @"the request is too old -- try again"; return NO; }
    NSString *s = v;
    char spelled[PATH_MAX];   // (-getFileSystemRepresentation:maxLength: says NO where -fileSystemRepresentation would raise)
    if (s.length < 2 || s.length > 1024 || ![s hasPrefix:@"/"] || [s rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound
        || ![s getFileSystemRepresentation:spelled maxLength:sizeof spelled] || !MSBDEjectInLiveFiles(MSBDEjectNorm(s))) { if (why) *why = @"it isn't a connected drive"; return NO; }
    if (volume) *volume = s;
    return YES;
}

// ---- the volume folder, checked against the kernel's mount table ----------------------------------------------------------------------------
// From statfs's answer for the folder (its real place): the folder must be the mount point itself, a connected drive's (<LiveFiles>/<provider>/
// <volume>), mounted from a local disk, and not the root file system. The mount point (normalised), or nil and *why.
static inline NSString *MSBDEjectCheckMount(NSString *real, NSString *mntOn, NSString *mntFrom, uint32_t flags, NSString **why) {
    NSString *p = MSBDEjectNorm(real), *on = MSBDEjectNorm(mntOn);
    if (!p.length || ![on isEqualToString:p]) { if (why) *why = @"it isn't a drive's own folder"; return nil; }
    if (!MSBDEjectInLiveFiles(p)) { if (why) *why = @"it isn't a connected drive"; return nil; }
    if (!MSBDEjectFromLocalDisk(mntFrom)) { if (why) *why = @"it isn't a drive connected to this iPad"; return nil; }
    if (flags & MNT_ROOTFS) { if (why) *why = @"it is the iPad's own storage"; return nil; }
    return p;
}
// The same for a folder on this device: its real place (links followed), then the kernel's mount table for it.
static inline NSString *MSBDEjectVolumeAt(const char *path, NSString **from, NSString **why) {
    char real[PATH_MAX];
    if (from) *from = nil;
    if (!path || !realpath(path, real)) { if (why) *why = @"that folder isn't there"; return nil; }
    struct statfs fs;
    if (statfs(real, &fs) != 0) { if (why) *why = [NSString stringWithFormat:@"its volume can't be read (%d)", errno]; return nil; }
    NSString *src = [NSString stringWithUTF8String:fs.f_mntfromname] ?: @"";
    NSString *p = MSBDEjectCheckMount([NSString stringWithUTF8String:real] ?: @"", [NSString stringWithUTF8String:fs.f_mntonname] ?: @"", src, fs.f_flags, why);
    if (p && from) *from = src;
    return p;
}

// ---- the answer -----------------------------------------------------------------------------------------------------------------------------
// The answer file: the request's id on its first line, msbdeject's line on the second (one line, at most 1 KB of it kept).
static inline NSData *MSBDEjectAnswerData(NSString *rid, NSString *line) {
    NSString *l = [[(line ?: @"") componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    if (l.length > 1024) l = [l substringToIndex:1024];
    return [[NSString stringWithFormat:@"%@\n%@\n", rid ?: @"", l] dataUsingEncoding:NSUTF8StringEncoding];
}
// The line of the answer to the request `rid`, or nil (another request's answer, or not an answer).
static inline NSString *MSBDEjectAnswerLine(NSData *data, NSString *rid) {
    if (![data isKindOfClass:[NSData class]] || data.length > 4096 || !MSBDEjectIsRequestID(rid)) return nil;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [s componentsSeparatedByString:@"\n"];
    if (lines.count < 2 || ![lines[0] isEqualToString:rid] || !lines[1].length) return nil;
    return lines[1];
}
// msbdeject's run, as the one line the answer carries: the helper's own last line, or what went wrong with running it.
static inline NSString *MSBDEjectHelperAnswer(int spawnResult, NSData *output, BOOL timedOut) {
    if (spawnResult < 0) return @"error: the eject helper couldn’t be started (no pipe)";
    if (spawnResult > 0) return [NSString stringWithFormat:@"error: the eject helper couldn’t be started (%d)", spawnResult];
    NSString *out = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
    NSString *line = [[[out ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsSeparatedByString:@"\n"] lastObject] ?: @"";
    if (timedOut) return line.length ? [@"error: the eject didn’t finish in time -- " stringByAppendingString:line] : @"error: the eject didn’t finish in time";
    return line.length ? line : @"error: the eject helper gave no answer";
}
// The dialog for an answer (nothing for "ok": the drive just leaves Finder's sidebar, as on a Mac). A Mac's words: in use -> "wasn't ejected
// because one or more programs may be using it", anything else -> "couldn't be ejected", with the helper's reason as a sentence under it.
static inline BOOL MSBDEjectMessage(NSString *line, NSString *name, NSString **title, NSString **message) {
    if (title) *title = nil;
    if (message) *message = nil;
    if ([line hasPrefix:@"ok"]) return NO;
    NSString *n = name.length ? name : @"Untitled";
    BOOL busy = [line hasPrefix:@"busy"];
    if (title) *title = busy ? [NSString stringWithFormat:@"The disk “%@” wasn’t ejected because one or more programs may be using it.", n]
                             : [NSString stringWithFormat:@"The disk “%@” couldn’t be ejected.", n];
    if (busy) { if (message) *message = @"Close the files on it and try again."; return YES; }
    NSRange colon = [line rangeOfString:@": "];
    NSString *why = colon.location != NSNotFound ? [line substringFromIndex:colon.location + 2] : nil;
    if (why.length) why = [[[why substringToIndex:1] uppercaseString] stringByAppendingFormat:@"%@%@", [why substringFromIndex:1], [why hasSuffix:@"."] ? @"" : @"."];   // (a sentence)
    if (message) *message = why.length ? why : nil;
    return YES;
}

// ---- the helper is there --------------------------------------------------------------------------------------------------------------------
// The pid published in kMSBDEjectHelperState is a live process of that name (a pid left from a helper that has gone does not count). Plain libc.
static inline BOOL MSBDEjectProcessNamed(uint64_t pid, const char *name) {
    if (!pid || pid > INT32_MAX || !name) return NO;
    struct kinfo_proc kp; size_t len = sizeof kp; int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    memset(&kp, 0, sizeof kp);
    return sysctl(mib, 4, &kp, &len, NULL, 0) == 0 && len == sizeof kp && kp.kp_proc.p_pid == (pid_t)pid && !strcmp(kp.kp_proc.p_comm, name);
}
static inline BOOL MSBDEjectHelperRunning(void) {
    int token = 0; uint64_t pid = 0;
    if (notify_register_check(kMSBDEjectHelperState, &token) != NOTIFY_STATUS_OK) return NO;
    notify_get_state(token, &pid);
    notify_cancel(token);
    return MSBDEjectProcessNamed(pid, kMSBDEjectHelperName);
}

// ---- running msbdeject, with a time limit ---------------------------------------------------------------------------------------------------
// The helper gets only the descriptors it uses -- stdin and stderr on /dev/null, stdout a pipe read to its end (8 KB kept at most) -- and no signal
// blocked (spawned from a queue's thread, which blocks them). Without POSIX_SPAWN_CLOEXEC_DEFAULT a child got every descriptor its parent had open
// (1.7.0 review: a second eject's answer waited for the first helper to end too). After `timeout` seconds it is stopped (SIGKILL) and *timedOut
// set. Returns posix_spawn's result (0: it ran), -1 without a pipe; *status: its wait status, -1 when there is none.
static inline int MSBDRunHelperTimed(const char *path, char *const argv[], double timeout, NSData **output, int *status, BOOL *timedOut) {
    extern char **environ;
    if (output) *output = nil;
    if (status) *status = -1;
    if (timedOut) *timedOut = NO;
    int out[2] = { -1, -1 };
    if (pipe(out) != 0) return -1;
    posix_spawnattr_t at; posix_spawnattr_init(&at);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);
    sigset_t none; sigemptyset(&none); posix_spawnattr_setsigmask(&at, &none);
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&fa, out[1], 1);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, path, &fa, &at, argv, environ);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
    close(out[1]);
    if (rc == 0) {
        NSMutableData *buf = [NSMutableData data]; char chunk[512];
        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + (timeout > 0 ? timeout : 1e9);
        BOOL late = NO;
        for (;;) {   // (its output, until it closes it or the time is up)
            double left = deadline - [NSDate timeIntervalSinceReferenceDate];
            if (left <= 0) { late = YES; break; }
            struct pollfd p = { out[0], POLLIN, 0 };
            int r = poll(&p, 1, (int)MIN(left * 1000.0 + 1.0, 60000.0));
            if (r < 0 && errno == EINTR) continue;
            if (r <= 0) continue;   // (no output yet: the deadline is looked at again)
            ssize_t got = read(out[0], chunk, sizeof chunk);
            if (got < 0 && errno == EINTR) continue;
            if (got <= 0) break;
            if (buf.length < 8192) [buf appendBytes:chunk length:(NSUInteger)MIN((size_t)got, 8192 - buf.length)];
        }
        close(out[0]); out[0] = -1;   // (before the wait: a helper with more to say than is kept ends, instead of waiting on a full pipe)
        int st = 0; pid_t w = 0;
        while (!late) {   // (it closed its output: it ends now -- or is stopped at the deadline)
            w = waitpid(pid, &st, WNOHANG);
            if (w == pid || (w < 0 && errno != EINTR)) break;
            if ([NSDate timeIntervalSinceReferenceDate] >= deadline) { late = YES; break; }
            usleep(20000);
        }
        if (late) { kill(pid, SIGKILL); do { w = waitpid(pid, &st, 0); } while (w < 0 && errno == EINTR); }
        if (status && w == pid) *status = st;
        if (timedOut) *timedOut = late;
        if (output) *output = buf;
    }
    if (out[0] >= 0) close(out[0]);
    return rc;
}

// ---- the drive's name -----------------------------------------------------------------------------------------------------------------------
// What Finder calls a drive: its volume's own name (the label: "NO NAME" for a FAT drive without one), as the Files app and a Mac do -- not the
// folder it is mounted on. On 15 UserFS mounts a drive on a folder of its name ("fat://disk2s1/NO NAME on .../userfsd/NO NAME"); 18's FSKit mounts
// it on a folder named by a UUID, which Finder showed (1.7.2 item 21). In order: the label the file system gives (getattrlist ATTR_VOL_NAME, read
// by MSBDDriveVolumeLabel), the name in the mount's source ("<scheme>://<disk>/<name>"), the folder's name.
static inline NSString *MSBDDriveName(NSString *mntOn, NSString *mntFrom, NSString *volName) {
    if ([volName isKindOfClass:[NSString class]] && [volName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return volName;
    if ([mntFrom isKindOfClass:[NSString class]]) {
        NSRange r = [mntFrom rangeOfString:@"://"];
        NSString *rest = r.location != NSNotFound && r.location > 0 ? [mntFrom substringFromIndex:NSMaxRange(r)] : nil;
        NSRange slash = rest ? [rest rangeOfString:@"/"] : NSMakeRange(NSNotFound, 0);
        if (slash.location != NSNotFound && slash.location > 0 && [rest hasPrefix:@"disk"]) {
            NSString *n = [rest substringFromIndex:slash.location + 1];
            NSString *decoded = [n containsString:@"%"] ? n.stringByRemovingPercentEncoding : nil;   // (a URL's spelling, when it is one)
            if (decoded.length) n = decoded;
            if (n.length && ![n containsString:@"/"] && [n stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return n;
        }
    }
    return [mntOn isKindOfClass:[NSString class]] ? mntOn.lastPathComponent : nil;
}
// The volume's label as its file system gives it (getattrlist on the mount point, ATTR_VOL_NAME), or nil when it gives none. It may ask the file
// system's own server (UserFS / FSKit): Finder reads it once per mount (Finder.h keeps it).
static inline NSString *MSBDDriveVolumeLabel(const char *mountPoint) {
    if (!mountPoint) return nil;
    struct attrlist al; memset(&al, 0, sizeof al);
    al.bitmapcount = ATTR_BIT_MAP_COUNT; al.commonattr = ATTR_CMN_RETURNED_ATTRS; al.volattr = ATTR_VOL_INFO | ATTR_VOL_NAME;
    struct { uint32_t length; attribute_set_t returned; attrreference_t name; char text[1024]; } __attribute__((aligned(4), packed)) b;
    memset(&b, 0, sizeof b);
    if (getattrlist(mountPoint, &al, &b, sizeof b, FSOPT_NOFOLLOW | FSOPT_REPORT_FULLSIZE) != 0) return nil;
    if (!(b.returned.volattr & ATTR_VOL_NAME) || b.name.attr_length <= 1) return nil;
    const char *s = (const char *)&b.name + b.name.attr_dataoffset, *end = (const char *)&b + MIN((size_t)b.length, sizeof b);
    if (s < (const char *)&b.text || s + b.name.attr_length > end) return nil;   // (the name must lie inside what came back)
    NSString *n = [[NSString alloc] initWithBytes:s length:strnlen(s, b.name.attr_length) encoding:NSUTF8StringEncoding];
    return n.length ? n : nil;
}
// The disk's BSD name in a mount's source, for DiskArbitration: "fat://disk2s1/NO NAME" -> "disk2s1", "/dev/disk4s1" -> "disk4s1"; nil otherwise.
static inline NSString *MSBDDriveBSDName(NSString *from) {
    if (![from isKindOfClass:[NSString class]]) return nil;
    NSString *s = nil;
    if ([from hasPrefix:@"/dev/"]) s = [from substringFromIndex:5];
    else { NSRange r = [from rangeOfString:@"://"]; if (r.location != NSNotFound && r.location > 0) s = [[from substringFromIndex:NSMaxRange(r)] componentsSeparatedByString:@"/"].firstObject; }
    if (![s hasPrefix:@"disk"] || s.length < 5 || s.length > 32) return nil;
    BOOL digit = NO;   // ("disk" digits, then any number of "s" digits)
    for (NSUInteger i = 4; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= '0' && c <= '9') { digit = YES; continue; }
        if (c == 's' && digit) { digit = NO; continue; }
        return nil;
    }
    return digit ? s : nil;
}
