// sshtoggled: the root helper of MacSettings (started by launchd as root, com.besiktasliseba.sshtoggled). Two jobs:
//
//  1. SSH: Settings (which runs as "mobile") cannot start or stop OpenSSH, so it posts a Darwin notification and this daemon loads or unloads OpenSSH's
//     launch daemon (com.openssh.sshd, which also covers the sftp subsystem) with launchctl -w (-w remembers the choice across reboots). The current state
//     is written to a file Settings can read.
//
//  2. Window-engine exclusivity for setups WITHOUT Choicy that have iCleaner Pro (2026-09-24). Only one window engine may be loaded in SpringBoard
//     (two break Full Screen mirroring over AirPlay / HDMI and fight over the windows). With Choicy, Mac Status Bar edits Choicy's deny list and this does
//     nothing. Without Choicy, the only way is iCleaner's own mechanism: <Engine>.dylib renamed to <Engine>.disabled in TweakInject (iCleaner's Tweaks page
//     then shows the true state), which needs root. Mac Status Bar asks with the Darwin notification com.besiktasliseba.msb.engines.apply (when an engine is picked
//     and at every SpringBoard start); "sshtoggled --restore-engines" (run by the prerm of Mac Status Bar and of MacSettings) renames back exactly what it
//     renamed. Safety rules (requested: "as safe as possible, no issues with updated packages, the engine switched off as rarely as possible"):
//      - acts only when Mac Status Bar is installed, Choicy is NOT and iCleaner Pro IS (with Choicy installed, anything we renamed earlier is given back);
//      - a hard-coded list of engine library names (Aerial, MilkyWay4 + MilkyWay3SubModule, Zetsu); no paths from outside, no shell, no symlinks followed:
//        every file is checked with lstat to be a regular file, and <name>.dylib must be in the owning engine package's dpkg file list;
//      - the notification carries nothing: every time, the CHOSEN engine is re-read from Mac Status Bar's own preferences and only the OTHER installed
//        engines are disabled. The chosen engine is never disabled (if WE had disabled it earlier, it is enabled again). A spoofed or repeated notification
//        can at most re-apply the correct state. No engine chosen or installed: everything we disabled is enabled again. Windowing switched off:
//        every installed engine is disabled (no engine loads; every app opens full screen), given back when it is on again;
//      - package updates: an engine update that brings back <Engine>.dylib while our old <Engine>.disabled is still there -> the new .dylib is renamed over
//        the stale .disabled in one atomic rename (the new build wins);
//      - a record of what WE renamed (/var/jb/var/lib/sshtoggled-engines/renamed); files the user renamed in iCleaner are never touched;
//      - anything unexpected (a file of another type, a file not owned by its package, an unexpected tweak folder...) -> left alone, reason logged.
//     Log: /var/jb/var/log/sshtoggled-engines.log (kept under 64 KB). Debug: a ROOT-owned file /var/jb/etc/sshtoggled-pretend-nochoicy makes it act as if
//     Choicy were not installed (for testing without uninstalling Choicy; mobile cannot create it).
#import <Foundation/Foundation.h>
#include <notify.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>
#include <dispatch/dispatch.h>
#include <sys/sysctl.h>
#include <CoreFoundation/CoreFoundation.h>
#include <sys/kauth.h>
#include <pthread.h>
#include "../../common/DeviceGate.h"
#include "../../common/EngineBuilds.h"
#include "../../common/VersionGate.h"
#include "../../common/DpkgState.h"
#include "../../common/StageManagerAvailable.h"

extern char **environ;

// ---- 1. SSH ----------------------------------------------------------------------------------------------------------------------------------------
#define LAUNCHCTL "/var/jb/usr/bin/launchctl"
#define SSHD_PLIST "/var/jb/Library/LaunchDaemons/com.openssh.sshd.plist"
#define STATE_FILE "/var/jb/var/mobile/.sshtoggle-state"

static int run(char *const argv[]) {
    pid_t pid;
    if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0) return -1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
static int sshdLoaded(void) {
    char *argv[] = { LAUNCHCTL, "list", "com.openssh.sshd", NULL };
    FILE *dn = freopen("/dev/null", "w", stdout); (void)dn;
    int rc = run(argv);
    return rc == 0;
}
// Hardening (release plan 3d-2): the state file now lives in a ROOT-owned folder (nothing to chown, mobile cannot swap in a link). The old file in
// mobile's home is still written for one release (Mac Status Bar's menu bar reads it), but only through a descriptor opened with O_NOFOLLOW and checked
// to be a plain file with one link before anything is changed: a symlink or hard link planted there by mobile is refused, never followed.
#define STATE_DIR "/var/jb/var/lib/sshtoggled-engines"
#define STATE_FILE_NEW STATE_DIR "/ssh-state"
static void writeStateNew(int on) {
    mkdir(STATE_DIR, 0755);
    char tmp[] = STATE_DIR "/.ssh-state.XXXXXX";
    int fd = mkstemp(tmp);
    if (fd < 0) return;
    BOOL ok = write(fd, on ? "1" : "0", 1) == 1;
    fchmod(fd, 0644);
    close(fd);
    if (!ok || rename(tmp, STATE_FILE_NEW) != 0) unlink(tmp);
}
static void writeStateLegacy(int on) {
    int fd = open(STATE_FILE, O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0644);   // (no O_TRUNC before the checks: a hard link must not be truncated)
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_nlink == 1 && (st.st_uid == 0 || st.st_uid == 501)) {
        if (ftruncate(fd, 0) == 0 && write(fd, on ? "1" : "0", 1) == 1) { fchmod(fd, 0644); fchown(fd, 501, 501); }   // (on the descriptor, never the path)
    }
    close(fd);
}
static void writeState(int on) {
    writeStateNew(on);
    writeStateLegacy(on);
}
static void apply(int on) {
    if (on) { char *argv[] = { LAUNCHCTL, "load", "-w", SSHD_PLIST, NULL }; run(argv); }
    else    { char *argv[] = { LAUNCHCTL, "unload", "-w", SSHD_PLIST, NULL }; run(argv); }
    writeState(sshdLoaded());
}
// Hardening (release plan 3d-1): the notification only says "look"; WHAT to do comes from MacSettings' own preference (com.besiktasliseba.macsettings sshWanted,
// written by Settings before it posts), which a sandboxed app cannot write. A spoofed post therefore only re-applies the user's choice. Compatibility for
// one release: while sshWanted has never been written (an older Settings build), the old enable/disable notifications still mean what they say.
static int SSHWanted(int legacy) {   // 1/0 from the preference; `legacy` (1/0, or -1 = none) when the preference is absent
    CFPreferencesSynchronize(CFSTR("com.besiktasliseba.macsettings"), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("sshWanted"), CFSTR("com.besiktasliseba.macsettings"), CFSTR("mobile"), kCFPreferencesAnyHost);
    int wanted = legacy;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) wanted = CFBooleanGetValue(v) ? 1 : 0;
    if (v) CFRelease(v);
    return wanted;
}
// ---- a fresh copy of mobile's settings after cfprefsd restarts (1.3.3, logic test) ----
// This helper reads mobile's settings as root (CFPreferencesCopyValue with user "mobile"), and its process keeps its own copy of them. After cfprefsd
// restarted (killall cfprefsd: a step of the test restore, and what many package scripts run) that copy was never refreshed: the engine picked before
// the restart went on being applied to Choicy at every SpringBoard start -- also after the choice was changed again through cfprefsd -- until the
// helper itself restarted (iPad 2, 16.7.7: "Choicy set to load only aerial" while SpringBoard ran Stage Manager). Reading the files instead is no
// answer: cfprefsd writes a change to its file only seconds later. So the helper notes the cfprefsd processes it started with, and when they are
// not the same any more it starts over as a fresh process (exec: same pid, launchd keeps it) and does again what it was asked, with settings read
// fresh. (This works around CoreFoundation, which does not refresh another user's settings in a long-running process after such a restart.)
static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static NSString *PrefsDaemonSignature(void) {   // every running cfprefsd as "pid@start/uid", sorted; nil when the process list cannot be read
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0 || len == 0) return nil;
    len += 32 * sizeof(struct kinfo_proc);   // (room for processes started in between)
    struct kinfo_proc *procs = malloc(len);
    if (!procs) return nil;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    BOOL ok = sysctl(mib, 3, procs, &len, NULL, 0) == 0;
    if (ok) for (size_t i = 0; i < len / sizeof(struct kinfo_proc); i++) {
        if (strcmp(procs[i].kp_proc.p_comm, "cfprefsd") != 0) continue;
        [found addObject:[NSString stringWithFormat:@"%d@%ld/%u", procs[i].kp_proc.p_pid, (long)procs[i].kp_proc.p_starttime.tv_sec, procs[i].kp_eproc.e_pcred.p_ruid]];
    }
    free(procs);
    if (!ok) return nil;
    [found sortUsingSelector:@selector(compare:)];
    return [found componentsJoinedByString:@","];
}
static NSString *gPrefsDaemons = nil;   // (the cfprefsd processes this helper's settings copy belongs to; set when the daemon starts)
static char gSelfPath[PATH_MAX] = "/var/jb/usr/libexec/sshtoggled";
// The work that can be asked for, and is still to be done (a request waiting out its 2 s burst limit, or a package transaction): it is done again
// after starting over too, whoever notices the restart first (the 10 s check included).
enum { kWorkEngines = 1, kWorkLines = 2, kWorkSSH = 4 };
static unsigned gPendingWork = 0;
static void StartOverIfPrefsDaemonRestarted(unsigned work) {
    if (!gPrefsDaemons.length) return;   // (not the daemon, or its start could not read the process list)
    NSString *now = PrefsDaemonSignature();
    if (!now.length || [now isEqualToString:gPrefsDaemons]) return;
    work |= gPendingWork;
    NSMutableArray *kinds = [NSMutableArray array];
    if (work & kWorkEngines) [kinds addObject:@"engines"];
    if (work & kWorkLines) [kinds addObject:@"lines"];
    if (work & kWorkSSH) [kinds addObject:@"ssh"];
    NSString *resume = kinds.count ? [kinds componentsJoinedByString:@","] : @"none";
    ELog(@"settings: cfprefsd restarted since this helper started (%@ -> %@) -- starting over as a fresh process so mobile's settings are read anew, then: %@", gPrefsDaemons, now, resume);
    char *args[] = { gSelfPath, "--resume", (char *)resume.UTF8String, NULL };
    execv(gSelfPath, args);
    ELog(@"settings: starting over failed (%s) -- carrying on with the settings as this process has them", strerror(errno));
    gPrefsDaemons = now;   // (not tried again for this restart)
}
// Hardening (release plan 3d-5): a burst of posts runs the work at most once per 2 s (the last request wins; later ones are coalesced into one run).
static void Debounced(CFAbsoluteTime *last, BOOL *pending, void (^work)(void)) {
    if (*pending) return;
    CFAbsoluteTime wait = *last + 2.0 - CFAbsoluteTimeGetCurrent();
    if (wait <= 0) { *last = CFAbsoluteTimeGetCurrent(); work(); return; }
    *pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ *pending = NO; *last = CFAbsoluteTimeGetCurrent(); work(); });
}
static void SSHRequest(int legacy) {
    static CFAbsoluteTime last = 0; static BOOL pending = NO; static int lastLegacy = -1;
    if (legacy >= 0) lastLegacy = legacy;
    gPendingWork |= kWorkSSH;
    Debounced(&last, &pending, ^{ StartOverIfPrefsDaemonRestarted(kWorkSSH); gPendingWork &= ~kWorkSSH; int w = SSHWanted(lastLegacy); lastLegacy = -1; if (w >= 0) apply(w); else writeState(sshdLoaded()); });
}

// ---- 2. window-engine exclusivity (iCleaner Pro without Choicy) -----------------------------------------------------------------------------------
#define TWEAKDIR "/var/jb/usr/lib/TweakInject"
#define ESTATEDIR "/var/jb/var/lib/sshtoggled-engines"
#define ESTATEFILE ESTATEDIR "/renamed"
#define ELOGFILE "/var/jb/var/log/sshtoggled-engines.log"

static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ELog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt); NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap);
    struct stat st;
    if (stat(ELOGFILE, &st) == 0 && st.st_size > 64 * 1024) rename(ELOGFILE, ELOGFILE ".old");
    FILE *f = fopen(ELOGFILE, "a"); if (!f) return;
    NSDateFormatter *df = [NSDateFormatter new]; df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fprintf(f, "%s %s\n", [df stringFromDate:[NSDate date]].UTF8String, line.UTF8String); fclose(f);
}
// engine key (Mac Status Bar's windowEngine preference) -> its libraries, and its package
static NSDictionary<NSString *, NSArray<NSString *> *> *EngineLibs(void) {
    return @{ @"aerial": @[@"Aerial"], @"milkyway": @[@"MilkyWay4", @"MilkyWay3SubModule"], @"zetsu": @[@"Zetsu"] };
}
static NSDictionary<NSString *, NSString *> *EnginePackage(void) {
    return @{ @"aerial": @"jp.uzra.aerial", @"milkyway": @"jp.akusio.milkyway4", @"zetsu": @"jp.dcsyhi.zetsu" };
}
// dpkg's status file (often 1-3 MB): read again only when it changed (dpkg replaces it with a rename, so a new inode, mtime or size means new contents).
static NSString *DpkgStatus(void) {
    static NSString *cache; static struct timespec mtime; static ino_t ino; static off_t size;
    struct stat st;
    if (stat("/var/jb/var/lib/dpkg/status", &st) != 0) return @"";
    if (cache && st.st_ino == ino && st.st_size == size && st.st_mtimespec.tv_sec == mtime.tv_sec && st.st_mtimespec.tv_nsec == mtime.tv_nsec) return cache;
    NSString *s = [NSString stringWithContentsOfFile:@"/var/jb/var/lib/dpkg/status" encoding:NSUTF8StringEncoding error:nil];
    if (!s) return cache ?: @"";
    cache = s; ino = st.st_ino; size = st.st_size; mtime = st.st_mtimespec;
    return cache;
}
// dpkg (or apt in front of it) is in the middle of a transaction: it holds a write lock on one of these files. During an install, an upgrade from the
// old separate packages or a removal, libraries appear and disappear and our own package is only "half-configured", so nothing may be decided from what
// is seen then (it would look like "not installed" or "switched off"). Callers wait and look again once the lock is free.
static BOOL DpkgBusy(void) {
    for (const char *p = "/var/jb/var/lib/dpkg/lock-frontend"; p; p = strcmp(p, "/var/jb/var/lib/dpkg/lock") ? "/var/jb/var/lib/dpkg/lock" : NULL) {
        int fd = open(p, O_RDONLY | O_NOFOLLOW);
        if (fd < 0) continue;
        struct flock fl = { .l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 0 };
        BOOL held = fcntl(fd, F_GETLK, &fl) == 0 && fl.l_type != F_UNLCK;
        close(fd);
        if (held) return YES;
    }
    return NO;
}
static BOOL PackageInstalled(NSString *status, NSString *pkg) {
    NSRange r = [status rangeOfString:[NSString stringWithFormat:@"Package: %@\n", pkg]];
    if (r.location == NSNotFound) return NO;
    NSRange end = [status rangeOfString:@"\n\n" options:0 range:NSMakeRange(r.location, status.length - r.location)];
    NSString *block = [status substringWithRange:NSMakeRange(r.location, (end.location == NSNotFound ? status.length : end.location) - r.location)];
    return [block containsString:@"Status: install ok installed"];
}
#if DEBUG   // (--dry-run-engines --old: the rule before 1.4.1, "install ok installed" only -- the device comparison of M-1)
static BOOL gDryOldRule = NO;
#define MSBDPackageOnDisk(s, p) (gDryOldRule ? PackageInstalled((s), (p)) : MSBDPackageOnDisk((s), (p)))
#endif
static BOOL ChoicyInstalled(NSString *status) {
#if DEBUG   // (test switch: never in a release build)
    struct stat st;
    if (lstat("/var/jb/etc/sshtoggled-pretend-nochoicy", &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == 0) return NO;
#endif
    return MSBDPackageOnDisk(status, @"com.opa334.choicy");   // (on disk: installed, or being set up in the dpkg run of the postinst, M-1)
}
static BOOL ICleanerInstalled(NSString *status) {
    return MSBDPackageOnDisk(status, @"com.exile90.icleanerpro") || MSBDPackageOnDisk(status, @"xyz.cypwn.icleanerpro");
}
static BOOL IsRegular(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode); }
static BOOL Exists(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation, &st) == 0; }
static BOOL OwnedByPackage(NSString *pkg, NSString *name) {
    NSString *list = [NSString stringWithContentsOfFile:[NSString stringWithFormat:@"/var/jb/var/lib/dpkg/info/%@.list", pkg] encoding:NSUTF8StringEncoding error:nil];
    if (!list) return NO;
    NSString *a = [NSString stringWithFormat:@"/var/jb/Library/MobileSubstrate/DynamicLibraries/%@.dylib", name], *b = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", name];
    for (NSString *line in [list componentsSeparatedByString:@"\n"]) if ([line isEqualToString:a] || [line isEqualToString:b]) return YES;
    return NO;
}
static NSMutableOrderedSet<NSString *> *LoadRecord(void) {
    NSString *s = [NSString stringWithContentsOfFile:@ESTATEFILE encoding:NSUTF8StringEncoding error:nil];
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSet];
    for (NSString *l in [s componentsSeparatedByString:@"\n"]) if (l.length && [@[@"Aerial", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu"] containsObject:l]) [set addObject:l];
    return set;
}
static void SaveRecord(NSOrderedSet<NSString *> *set) {
    if (set.count == 0) { unlink(ESTATEFILE); return; }
    mkdir(ESTATEDIR, 0755);
    NSString *tmp = @ESTATEFILE ".tmp";
    [[[set array] componentsJoinedByString:@"\n"] writeToFile:tmp atomically:NO encoding:NSUTF8StringEncoding error:nil];
    rename(tmp.fileSystemRepresentation, ESTATEFILE);
}
static BOOL gStageManagerChosen = NO;   // (set by ChosenEngine: Stage Manager is the engine -- no third-party engine loads, as with windowing off)
static NSString *OffWhy(void) { return gStageManagerChosen ? @"Stage Manager is the engine" : @"windowing off"; }   // (the log's words for "no engine loads")
static NSString *ChosenEngine(BOOL *windowing) {   // read from Mac Status Bar's own preferences, never from the request
    CFPreferencesSynchronize(CFSTR("com.besiktasliseba.macstatusbar"), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef e = CFPreferencesCopyValue(CFSTR("windowEngine"), CFSTR("com.besiktasliseba.macstatusbar"), CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef w = CFPreferencesCopyValue(CFSTR("windowingEnabled"), CFSTR("com.besiktasliseba.macstatusbar"), CFSTR("mobile"), kCFPreferencesAnyHost);
    NSString *engine = (e && CFGetTypeID(e) == CFStringGetTypeID()) ? [(__bridge NSString *)e copy] : nil;
    *windowing = !(w && CFGetTypeID(w) == CFBooleanGetTypeID() && !CFBooleanGetValue(w));
    if (!w && [engine isEqualToString:@"off"]) *windowing = NO;   // (the old picker's "Off", before the switch existed: SpringBoard honours it too)
    // Stage Manager as the engine (iPadOS 16+): Apple's own windowing, so none of the third-party engines may load -- the same as windowing off here
    // (SpringBoard keeps Stage Manager on itself: StatusBar.x DMSMEngine). On iPadOS 15 it is not offered; a stored pick there counts as none.
    // (logic test F6: Stage Manager picked where it can't run -- TrollPad removed -- counts as not picked: the default engine, not "no windows")
    if ([engine isEqualToString:@"stagemanager"] && !MSBDStageManagerAvailable()) { ELog(@"engines: Stage Manager is picked but can't run on this iPad -- the default engine instead"); engine = nil; }
    // (and where SpringBoard's self-check of the engine's private API failed on this iPadOS build -- the same verdict SpringBoard and Settings go
    //  by, common/StageManagerAvailable.h: SpringBoard keeps the engine off, so the default engine must load, as if Stage Manager were not there)
    NSString *why = nil;
    int smVerdict = [engine isEqualToString:@"stagemanager"] ? MSBDStageManagerVerdict(&why, NULL) : 1;
    if (smVerdict == -1) why = @"not checked on this iPadOS build yet";   // (SpringBoard checks at its next start; until then the default engine)
    if ([engine isEqualToString:@"stagemanager"] && smVerdict != 1) { ELog(@"engines: Stage Manager is picked but not supported on this iPadOS version (%@) -- the default engine instead", why ?: @"self-check failed"); engine = nil; }
    BOOL stageManager = [engine isEqualToString:@"stagemanager"] && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 16;
    gStageManagerChosen = stageManager;
    if (stageManager) *windowing = NO;
    // Stock status bar: the chosen engine always runs on its own (Settings > Status Bar Style says so, and the Enable Windowing switch is hidden
    // there), so a windowing switch left off from Mac mode does not stop it. Back in Mac mode the switch counts again.
    CFPropertyListRef st = CFPreferencesCopyValue(CFSTR("stockStatusBar"), CFSTR("com.besiktasliseba.macstatusbar"), CFSTR("mobile"), kCFPreferencesAnyHost);
    // (not with Stage Manager as the engine, logic test F3: in stock mode this undid the rule above and Aerial loaded next to Stage Manager)
    if (!stageManager && st && CFGetTypeID(st) == CFBooleanGetTypeID() && CFBooleanGetValue(st)) *windowing = YES;
    if (st) CFRelease(st);
    if (e) CFRelease(e);
    if (w) CFRelease(w);
    return engine;
}
// The engine to keep loading: the one picked in Settings while its package is installed (not MilkyWay4 on iPadOS 16: SpringBoard ignores that pick
// there); otherwise the one SpringBoard uses when nothing is picked (EngineBuilds.h), so a fresh install with two engines gets exclusivity from its
// first start. An engine the user switched off in Choicy or iCleaner Pro themselves (not by us) is never made the default. *picked says which.
#define CHOICYRECORD_PATH "/var/jb/var/mobile/Library/Preferences/MacStatusBar-ChoicyChanges.plist"
static NSString *EngineToKeep(NSString *status, BOOL *windowing, BOOL *picked) {
    NSString *stored = ChosenEngine(windowing);
    NSDictionary *libs = EngineLibs(), *pkgs = EnginePackage();
    BOOL ios16 = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 16;
    *picked = stored && pkgs[stored] && MSBDPackageOnDisk(status, pkgs[stored]) && !(ios16 && [stored isEqualToString:@"milkyway"]);
    if (*picked) return stored;
    NSDictionary *choicy = [NSDictionary dictionaryWithContentsOfFile:@"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"];
    NSArray *denied = [choicy[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? choicy[@"globalDeniedTweaks"] : @[];
    NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:@CHOICYRECORD_PATH];
    NSDictionary *ours = [record[@"globalDeniedTweaks"] isKindOfClass:[NSDictionary class]] ? record[@"globalDeniedTweaks"] : @{};
    NSOrderedSet *renamed = LoadRecord();
    NSString *(^path)(NSString *) = ^NSString *(NSString *lib) {
        NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", lib];
        return Exists(dylib) ? dylib : [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", lib];
    };
    return MSBDDefaultEngine(^BOOL(NSString *e) {
        if (!MSBDPackageOnDisk(status, pkgs[e])) return NO;
        NSString *lib = libs[e][0];
        if ([denied containsObject:lib] && ![ours[lib] isEqual:@"added"]) return NO;   // (denied in Choicy by the user)
        if (!Exists([NSString stringWithFormat:@TWEAKDIR "/%@.dylib", lib]) && ![renamed containsObject:lib]) return NO;   // (switched off in iCleaner by the user)
        return YES;
    }, path);
}
// SpringBoard asks at every start; when this really changed which engines load, it is told (the state names that SpringBoard), and only then does it
// ask for the respring that finishes the switch (StatusBar.x, DMCheckEngineWarnings).
static int SpringBoardPid(time_t *started);   // (section 3)
static BOOL gTellSpringBoard = YES;   // (NO in the postinst's run, ApplyEnginesAtInstall: the SpringBoard running then is the one being replaced)
static void TellSpringBoardEnginesChanged(void) {
    if (!gTellSpringBoard) return;
    static int token = 0;
    if (!token && notify_register_check("com.besiktasliseba.msb.engines.changed", &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    notify_set_state(token, (uint64_t)SpringBoardPid(NULL));
    notify_post("com.besiktasliseba.msb.engines.changed");
}
static void EnableOurs(NSString *name, NSMutableOrderedSet *record, NSString *why) {   // only a library WE disabled is renamed back
    if (![record containsObject:name]) return;
    NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", name], *disabled = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", name];
    if (IsRegular(disabled) && !Exists(dylib)) {
        if (rename(disabled.fileSystemRepresentation, dylib.fileSystemRepresentation) != 0) { ELog(@"%@: could not enable (%s) -- left as it is", name, strerror(errno)); return; }
        ELog(@"%@: enabled again (%@)", name, why);
    } else if (IsRegular(disabled) && IsRegular(dylib)) {
        unlink(disabled.fileSystemRepresentation);   // (an update brought the library back meanwhile: the old disabled copy is stale)
        ELog(@"%@: already back (an update); the stale .disabled copy removed (%@)", name, why);
    } else ELog(@"%@: nothing to enable (%@)", name, why);
    [record removeObject:name];
}
static void GiveBackAll(NSString *why) {
    NSMutableOrderedSet *record = LoadRecord();
    for (NSString *n in [record array]) EnableOurs(n, record, why);
    SaveRecord(record);
}
static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how);   // (section 3)
static void ChoicyApplyChosenEngine(NSString *why);                      // (section 3)
// Is the tweak meant to run (VersionGate.h)? Not on an untested iPadOS without "Enable Anyway", not in the crash guard's safe mode: then only the
// Settings rows load, and no other engine may be kept from loading. SpringBoard's decision at its start wins (what really runs); before it has
// decided (the daemon's start at boot), the switches are read -- as mobile, since this helper runs as root (VersionGate's own reader reads the
// current user's preferences).
static void ApplyEngineRenames(NSString *reason, NSString *status);
static BOOL TweakMeantToRun(void) {
    uint64_t sb = MSBDGateReadState(MSBD_GATE_STATE);
    if (sb) return sb == 2;
    CFStringRef domain = CFSTR(MSBD_GATE_DOMAIN);
    CFPreferencesSynchronize(domain, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFStringRef key = MSBDVersionTested() ? CFSTR(MSBD_SAFE_KEY) : CFSTR(MSBD_GATE_KEY);
    CFPropertyListRef v = CFPreferencesCopyValue(key, domain, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL on = v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return MSBDVersionTested() ? !on : on;   // (tested: on unless in safe mode; untested: only with Enable Anyway)
}
static void ApplyEngines(NSString *reason) {
    static BOOL retryPending = NO, logged = NO;
    BOOL asked = [reason isEqualToString:@"request"] || [reason isEqualToString:@"manual"];
    StartOverIfPrefsDaemonRestarted(asked ? kWorkEngines : 0);   // (also for a retry after a package transaction, which can restart cfprefsd itself)
    if (DpkgBusy()) {   // (mid-transaction our own package looks "not installed": decided once it is over)
        if (asked) gPendingWork |= kWorkEngines;
        if (!logged) ELog(@"%@: a package transaction is running -- looked at again once it is over", reason);
        logged = YES;
        if (!retryPending) {
            retryPending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ retryPending = NO; ApplyEngines(reason); });
        }
        return;
    }
    logged = NO;
    if (asked) gPendingWork &= ~kWorkEngines;
    NSString *status = DpkgStatus();
    if (!PackageInstalled(status, @"com.besiktasliseba.macstatusbaranddock")) { GiveBackAll(@"Mac Status Bar is not installed"); ELog(@"%@: Mac Status Bar not installed -- nothing to do", reason); return; }
    if (!TweakMeantToRun()) { GiveBackAll(@"MacStatusBar&Dock is off (untested iPadOS or safe mode)"); ELog(@"%@: MacStatusBar&Dock is off (untested iPadOS without Enable Anyway, or the crash guard's safe mode) -- no engine kept from loading", reason); return; }
    if (ChoicyInstalled(status)) {   // (Mac Status Bar asks at every SpringBoard start: its engine choice is made sure of in Choicy too -- safety net for a
                                     //  switch-on the watcher could not prepare before the respring; only our recorded engine entries change)
        GiveBackAll(@"Choicy is installed");
        NSString *how = nil;
        if (([reason isEqualToString:@"request"] || [reason isEqualToString:@"manual"]) && !MacStatusBarSwitchedOff(status, &how)) ChoicyApplyChosenEngine([reason isEqualToString:@"manual"] ? @"manual" : @"Mac Status Bar started");
        return;
    }
    if (!ICleanerInstalled(status)) { ELog(@"%@: neither Choicy nor iCleaner Pro installed -- nothing to do", reason); return; }
    ApplyEngineRenames(reason, status);
}
// iCleaner Pro setups (no Choicy): every installed engine but the chosen one renamed to .disabled, as iCleaner does (ApplyEngines, and the postinst's
// run: ApplyEnginesAtInstall).
static void ApplyEngineRenames(NSString *reason, NSString *status) {
    // (not while Mac Status Bar itself is switched off in iCleaner Pro: then the engines are the user's own -- RestoreForOff gave them back -- and the
    //  helper's start at the next boot renamed them again, so the user's other engines stayed off while Mac Status Bar was off)
    NSString *how = nil;
    if (MacStatusBarSwitchedOff(status, &how)) { GiveBackAll(@"Mac Status Bar is switched off"); ELog(@"%@: Mac Status Bar is switched off in %@ -- no engine kept from loading", reason, how); return; }
    char real[PATH_MAX], tweakdir[PATH_MAX];   // (DynamicLibraries must be the same folder as TweakInject; /var/jb itself is a symlink into /private/preboot)
    if (!realpath("/var/jb/Library/MobileSubstrate/DynamicLibraries", real) || !realpath(TWEAKDIR, tweakdir) || strcmp(real, tweakdir) != 0) {
        ELog(@"%@: unexpected tweak folder -- nothing done", reason); return;
    }
    BOOL windowing = YES, picked = NO;
    NSString *chosen = EngineToKeep(status, &windowing, &picked);
    NSDictionary *libs = EngineLibs(), *pkgs = EnginePackage();
    NSOrderedSet *before = LoadRecord();
    if (!windowing) chosen = nil;   // (Enable Windowing off: no engine loads at all, every app opens full screen)
    if (windowing && (!chosen || !libs[chosen])) {
        GiveBackAll(@"no engine installed");
        if (![LoadRecord() isEqual:before]) TellSpringBoardEnginesChanged();
        ELog(@"%@: no engine installed -- nothing kept from loading", reason); return;
    }
    if (!windowing) ELog(@"%@: %@ -- every installed engine is kept from loading", reason, OffWhy());
    else if (!picked) ELog(@"%@: no engine picked -- %@ is the default, as in SpringBoard", reason, chosen);
    NSMutableOrderedSet *record = LoadRecord();
    if (chosen) for (NSString *n in libs[chosen]) EnableOurs(n, record, [NSString stringWithFormat:@"%@ is the chosen engine", chosen]);
    for (NSString *engine in libs) {
        if ([engine isEqualToString:chosen] || !MSBDPackageOnDisk(status, pkgs[engine])) continue;
        for (NSString *name in libs[engine]) {
            NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", name], *disabled = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", name];
            if (!Exists(dylib)) continue;   // (already disabled, by us or by the user)
            if (!IsRegular(dylib)) { ELog(@"%@: not a plain file -- left alone", name); continue; }
            if (!OwnedByPackage(pkgs[engine], name)) { ELog(@"%@: not in %@'s file list -- left alone", name, pkgs[engine]); continue; }
            if (Exists(disabled) && !IsRegular(disabled)) { ELog(@"%@: its .disabled name is taken by something else -- left alone", name); continue; }
            BOOL stale = Exists(disabled);
            if (rename(dylib.fileSystemRepresentation, disabled.fileSystemRepresentation) != 0) { ELog(@"%@: rename failed (%s) -- left alone", name, strerror(errno)); continue; }
            [record addObject:name];
            ELog(@"%@: disabled (%@; %@)%@", name, chosen ? [chosen stringByAppendingString:@" is the chosen engine"] : OffWhy(), reason, stale ? @" -- an update had brought it back: the new build replaced the stale .disabled copy" : @"");
        }
    }
    SaveRecord(record);
    if (![record isEqual:before]) TellSpringBoardEnginesChanged();
}

// ---- 3. Mac Status Bar switched off without uninstalling it (2026-09-24) ------------------------------------------------------------------------
// When Mac Status Bar is removed, its prerm gives the window engines back their user's own settings. Switched OFF in Choicy or iCleaner Pro instead,
// nothing of it would run any more, so Aerial/MilkyWay4/Zetsu would keep the values we hold them at and the other engines would stay denied.
// So this daemon WATCHES Choicy's settings file and TweakInject (kernel file events, plus a 2 s check as a backup): the moment Mac Status Bar is
// switched off, the engines get their user's own settings back (from Mac Status Bar's copies) and our recorded Choicy engine entries are undone
// (only ours, only where still as we left them), and a marker tells the still-running Mac Status Bar to stop holding anything -- so the user's one
// respring finishes everything. Switched on again, our engine choice is put back into Choicy (recorded) right away, and Mac Status Bar takes the
// engines over again when it starts. Slow fallback (a switch-off noticed only after a respring): 20-25 s after SpringBoard starts, Mac Status Bar
// not running (no heartbeat) AND the configuration saying it is off -> the same give-back, and the Dock's SpringBoard part offers a respring.
// Never on a guess: Safe Mode, a crash or anything else without an explicit switch-off in Choicy/iCleaner does nothing.
#define PREFSDIR "/var/jb/var/mobile/Library/Preferences"
#define OFFMARKER ESTATEDIR "/msb-off-restored"
static int SpringBoardPid(time_t *started) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t len = 0;
    if (sysctl(mib, 3, NULL, &len, NULL, 0) != 0 || len == 0) return 0;
    struct kinfo_proc *procs = malloc(len);
    if (!procs) return 0;
    int pid = 0;
    if (sysctl(mib, 3, procs, &len, NULL, 0) == 0) {
        for (size_t i = 0; i < len / sizeof(struct kinfo_proc); i++) {
            if (strcmp(procs[i].kp_proc.p_comm, "SpringBoard") == 0) { pid = procs[i].kp_proc.p_pid; if (started) *started = procs[i].kp_proc.p_starttime.tv_sec; break; }
        }
    }
    free(procs);
    return pid;
}
static NSInteger ChoicyMode(NSDictionary *sb) {   // Choicy's allow/deny mode: 1 (allow list) or 2 (deny list); missing = 1; anything else = 0 (unknown)
    id m = sb[@"allowDenyMode"];
    if (!m) return 1;
    if (![m isKindOfClass:[NSNumber class]]) return 0;
    NSInteger v = [m integerValue];
    return (v == 1 || v == 2) ? v : 0;
}
static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how) {
    NSString *dylib = @TWEAKDIR "/MacStatusBar.dylib", *disabled = @TWEAKDIR "/MacStatusBar.disabled";
    if (!Exists(dylib) && IsRegular(disabled)) { *how = @"iCleaner Pro"; return YES; }
    if (!MSBDPackageOnDisk(status, @"com.opa334.choicy")) return NO;
    NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:@PREFSDIR "/com.opa334.choicyprefs.plist"];
    if ([c[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] && [c[@"globalDeniedTweaks"] containsObject:@"MacStatusBar"]) { *how = @"Choicy (all processes)"; return YES; }
    NSDictionary *sb = [c[@"appSettings"] isKindOfClass:[NSDictionary class]] ? c[@"appSettings"][@"com.apple.springboard"] : nil;
    if ([sb isKindOfClass:[NSDictionary class]] && [sb[@"customTweakConfigurationEnabled"] boolValue]) {
        if ([sb[@"tweakInjectionDisabled"] boolValue]) return NO;   // (all tweaks off in SpringBoard: not a Mac Status Bar switch-off)
        NSInteger mode = ChoicyMode(sb);
        if (!mode) return NO;   // (an unknown mode: not a switch-off we can read, so nothing is done)
        NSArray *list = mode == 2 ? sb[@"deniedTweaks"] : sb[@"allowedTweaks"];
        BOOL listed = [list isKindOfClass:[NSArray class]] && [list containsObject:@"MacStatusBar"];
        if (mode == 2 ? listed : !listed) { *how = @"Choicy (SpringBoard)"; return YES; }
    }
    return NO;
}
// Hardening (release plan 3d-2): files in mobile-owned folders are written AS mobile (this thread's user and group switched to 501 for the write),
// never as root followed by a chown. The kernel then applies mobile's own permissions, so a link planted by mobile can gain it nothing.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"   // (per-thread credentials are exactly what is wanted here, for one write)
static BOOL AsMobile(BOOL (^work)(void)) {
    if (getuid() != 0) return work();   // (run by hand as a normal user: nothing to switch)
    if (pthread_setugid_np(501, 501) != 0) return NO;   // (no root write into mobile's folders, ever)
    BOOL ok = work();
    pthread_setugid_np(KAUTH_UID_NONE, KAUTH_GID_NONE);
    return ok;
}
#pragma clang diagnostic pop
static void SetMobilePrefs(NSString *domain, NSDictionary *user) {   // the domain exactly as `user`, through cfprefsd (as mobile) and on disk
    CFStringRef d = (__bridge CFStringRef)domain;
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFArrayRef keys = CFPreferencesCopyKeyList(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    for (NSString *k in (__bridge NSArray *)keys) if (!user[k]) CFPreferencesSetValue((__bridge CFStringRef)k, NULL, d, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (keys) CFRelease(keys);
    for (NSString *k in user) CFPreferencesSetValue((__bridge CFStringRef)k, (__bridge CFPropertyListRef)user[k], d, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    NSString *path = [NSString stringWithFormat:@PREFSDIR "/%@.plist", domain];
    AsMobile(^BOOL{ return [user writeToFile:path atomically:YES]; });
}
static BOOL GiveBackDomain(NSString *dir, NSString *domain, NSString *notifyName) {
    NSString *backup = [dir stringByAppendingPathComponent:[domain stringByAppendingPathExtension:@"plist"]];
    if (!IsRegular(backup)) return NO;
    NSDictionary *user = [NSDictionary dictionaryWithContentsOfFile:backup];
    if (!user) { ELog(@"MSB off: the copy of %@ is unreadable -- left as it is", domain); return NO; }
    SetMobilePrefs(domain, user);
    if (notifyName) notify_post(notifyName.UTF8String);
    ELog(@"MSB off: %@ is the user's own again (%lu keys)", domain, (unsigned long)user.count);
    return YES;
}
static void CopyAsMobile(NSString *from, NSString *to) {
    NSData *d = [NSData dataWithContentsOfFile:from];
    if (d) AsMobile(^BOOL{ return [d writeToFile:to atomically:YES]; });
}
static void GiveBackEngineSettings(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *a = @PREFSDIR "/MacStatusBar-AerialUserSettings";   // Aerial 5.0: its settings and its two per-app lists
    if (GiveBackDomain(a, @"jp.uzra.aerial", @"jp.uzra.aerial/ReloadPrefs")) {
        for (NSString *f in @[@"FlexResizeBlacklist.plist", @"KeyboardAvoidanceWhitelist.plist"]) {
            NSString *saved = [a stringByAppendingPathComponent:f], *live = [@"/var/jb/var/mobile/Library/Aerial" stringByAppendingPathComponent:f];
            if (IsRegular(saved)) CopyAsMobile(saved, live); else if (IsRegular(live)) AsMobile(^BOOL{ return unlink(live.fileSystemRepresentation) == 0; });
        }
        AsMobile(^BOOL{ return [fm removeItemAtPath:a error:nil]; });
    }
    NSString *m = @PREFSDIR "/MacStatusBar-MilkyWayUserSettings";
    if (GiveBackDomain(m, @"jp.akusio.milkyway4.scalemode", nil)) AsMobile(^BOOL{ return [fm removeItemAtPath:m error:nil]; });
    NSString *z = @PREFSDIR "/MacStatusBar-ZetsuUserSettings";
    BOOL z1 = GiveBackDomain(z, @"jp.dcsyhi.zetsu", @"jp.dcsyhi.zetsuprefs/prefsupdated"), z2 = GiveBackDomain(z, @"jp.dcsyhi.zetsuothers", @"jp.dcsyhi.zetsuprefs/prefsupdated");
    if (z1 || z2) AsMobile(^BOOL{ return [fm removeItemAtPath:z error:nil]; });
}
// Choicy: our own changes only. Mac Status Bar's Settings records every change it makes to Choicy's lists (MacStatusBar-ChoicyChanges.plist:
// list -> entry -> "added"/"removed", the net effect). Each is undone only if the entry is still as we left it; nothing else in Choicy is touched
// (entries the user added, removed or changed later stay as they are). No record = Choicy is left alone.
#define CHOICYPREFS PREFSDIR "/com.opa334.choicyprefs.plist"
#define CHOICYRECORD PREFSDIR "/MacStatusBar-ChoicyChanges.plist"
static NSMutableArray *ChoicyList(NSMutableDictionary *prefs, NSString *listKey, BOOL create) {   // (mutable, stored back into prefs)
    if ([listKey isEqualToString:@"globalDeniedTweaks"]) {
        NSMutableArray *l = [prefs[listKey] isKindOfClass:[NSArray class]] ? [prefs[listKey] mutableCopy] : (create ? [NSMutableArray array] : nil);
        if (l) prefs[listKey] = l;
        return l;
    }
    NSString *key = [listKey hasPrefix:@"springboard."] ? [listKey substringFromIndex:12] : nil;
    if (!key) return nil;
    NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
    NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
    if (!sb) return nil;
    NSMutableArray *l = [sb[key] isKindOfClass:[NSArray class]] ? [sb[key] mutableCopy] : (create ? [NSMutableArray array] : nil);
    if (!l) return nil;
    sb[key] = l; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps;
    return l;
}
static NSArray *UndoOurChoicyChanges(NSMutableDictionary *prefs, NSDictionary *record) {   // returns what was undone (and what was left as the user has it)
    NSMutableArray *log = [NSMutableArray array];
    NSArray *engines = @[@"Aerial", @"MilkyWay4", @"MilkyWay3SubModule", @"Zetsu"];
    for (NSString *listKey in record) {
        NSDictionary *entries = [record[listKey] isKindOfClass:[NSDictionary class]] ? record[listKey] : nil;
        for (NSString *entry in entries) {
            if (![engines containsObject:entry]) { [log addObject:[NSString stringWithFormat:@"%@ %@: not a window engine -- left alone", listKey, entry]]; continue; }
            NSString *did = entries[entry];
            NSMutableArray *l = ChoicyList(prefs, listKey, [did isEqual:@"removed"]);
            BOOL present = [l containsObject:entry];
            if ([did isEqual:@"added"]) {
                if (present) { [l removeObject:entry]; while ([l containsObject:entry]) [l removeObject:entry]; [log addObject:[NSString stringWithFormat:@"%@: removed %@ (we had added it)", listKey, entry]]; }
                else [log addObject:[NSString stringWithFormat:@"%@: %@ already gone -- left as the user has it", listKey, entry]];
            } else if ([did isEqual:@"removed"]) {
                if (!present && l) { [l addObject:entry]; [log addObject:[NSString stringWithFormat:@"%@: added %@ back (we had removed it)", listKey, entry]]; }
                else [log addObject:[NSString stringWithFormat:@"%@: %@ is back already -- left as the user has it", listKey, entry]];
            }
        }
    }
    return log;
}
static void GiveBackChoicyEngines(void) {
    NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:@CHOICYRECORD];
    if (!record) { ELog(@"MSB off: no record of our Choicy changes -- Choicy left as it is"); return; }
    NSMutableDictionary *cur = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYPREFS] mutableCopy];
    if (!cur) { ELog(@"MSB off: Choicy's settings unreadable -- left as they are"); return; }
    NSDictionary *before = [cur copy];
    NSArray *log = UndoOurChoicyChanges(cur, record);
    ELog(@"MSB off: Choicy: %@", log.count ? [log componentsJoinedByString:@"; "] : @"nothing recorded");
    if (![cur isEqualToDictionary:before]) {
        AsMobile(^BOOL{ return [cur writeToFile:@CHOICYPREFS atomically:YES]; });
        notify_post("com.opa334.choicyprefs/ReloadPrefs");
    }
    AsMobile(^BOOL{ return unlink(CHOICYRECORD) == 0; });   // (Mac Status Bar makes a new record when it is on again and an engine is applied)
}
#if DEBUG   // (a test tool: never in a release build)
static void DryRunChoicy(const char *recordPath, const char *inPath, const char *outPath) {   // --dry-run-choicy <record> <choicy in> <out>: no real writes
    NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:@(recordPath)];
    NSMutableDictionary *cur = [[NSDictionary dictionaryWithContentsOfFile:@(inPath)] mutableCopy];
    if (!record || !cur) { printf("dry run: record %s, choicy %s\n", record ? "ok" : "MISSING", cur ? "ok" : "MISSING"); return; }
    NSArray *log = UndoOurChoicyChanges(cur, record);
    for (NSString *l in log) printf("dry run: %s\n", l.UTF8String);
    [cur writeToFile:@(outPath) atomically:YES];
}
// Switched on again: our engine choice is put back into Choicy right away (the same change Mac Status Bar's Settings makes when an engine is picked,
// recorded the same way), so the user's one respring comes up with only the chosen engine loaded.
#endif
static void RecordChange(NSMutableDictionary *record, NSString *listKey, NSString *entry, BOOL added) {
    NSMutableDictionary *l = [record[listKey] isKindOfClass:[NSDictionary class]] ? [record[listKey] mutableCopy] : [NSMutableDictionary dictionary];
    NSString *before = l[entry];
    if ((added && [before isEqual:@"removed"]) || (!added && [before isEqual:@"added"])) [l removeObjectForKey:entry]; else l[entry] = added ? @"added" : @"removed";
    if (l.count) record[listKey] = l; else [record removeObjectForKey:listKey];
}
static BOOL SetMembershipRecorded(NSMutableArray *list, NSArray *add, NSArray *remove, NSString *listKey, NSMutableDictionary *record) {
    BOOL changed = NO;
    for (NSString *n in add) if (![list containsObject:n]) { [list addObject:n]; changed = YES; RecordChange(record, listKey, n, YES); }
    for (NSString *n in remove) if ([list containsObject:n]) { while ([list containsObject:n]) [list removeObject:n]; changed = YES; RecordChange(record, listKey, n, NO); }
    return changed;
}
static void ChoicyApplyChosenEngine(NSString *why) {
    BOOL windowing = YES, picked = NO;
    NSString *status = DpkgStatus();
    NSString *chosen = EngineToKeep(status, &windowing, &picked);
    NSDictionary *libs = EngineLibs();
    if (!windowing) chosen = nil;   // (Enable Windowing off: every installed engine is denied, so every app opens full screen)
    if (windowing && (!chosen || !libs[chosen])) { ELog(@"MSB on (%@): no engine installed -- Choicy left as it is", why); return; }
    if (!windowing) ELog(@"MSB on (%@): %@ -- every installed engine kept from loading", why, OffWhy());
    else if (!picked) ELog(@"MSB on (%@): no engine picked -- %@ is the default, as in SpringBoard", why, chosen);
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYPREFS] mutableCopy];
    if (!prefs) { ELog(@"MSB on (%@): Choicy's settings unreadable -- left as they are", why); return; }
    NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYRECORD] mutableCopy] ?: [NSMutableDictionary dictionary];
    // only engines that are really installed are kept from loading (iPad 2: MilkyWay4 is not installed there, but its entries were added); an entry we
    // added earlier for an engine that is not installed is taken out again (our own record says so)
    NSDictionary *pkgs = EnginePackage();
    NSArray *keep = chosen ? libs[chosen] : @[]; NSMutableArray *deny = [NSMutableArray array], *notInstalled = [NSMutableArray array];
    for (NSString *e in libs) if (![e isEqualToString:chosen]) [MSBDPackageOnDisk(status, pkgs[e]) ? deny : notInstalled addObjectsFromArray:libs[e]];
    NSMutableArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? [prefs[@"globalDeniedTweaks"] mutableCopy] : [NSMutableArray array];
    BOOL changed = SetMembershipRecorded(global, deny, keep, @"globalDeniedTweaks", record);
    NSDictionary *ours = [record[@"globalDeniedTweaks"] isKindOfClass:[NSDictionary class]] ? record[@"globalDeniedTweaks"] : @{};
    NSMutableArray *undo = [NSMutableArray array];
    for (NSString *n in notInstalled) if ([ours[n] isEqual:@"added"] && [global containsObject:n]) [undo addObject:n];
    if (undo.count && SetMembershipRecorded(global, @[], undo, @"globalDeniedTweaks", record)) { changed = YES; ELog(@"MSB on (%@): not installed, our entries taken out again: %@", why, [undo componentsJoinedByString:@", "]); }
    prefs[@"globalDeniedTweaks"] = global;
    NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
    NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
    NSInteger mode = ChoicyMode(sb);
    if ([sb[@"customTweakConfigurationEnabled"] boolValue] && !mode) ELog(@"MSB on (%@): Choicy's SpringBoard mode is unknown -- its SpringBoard list left as it is", why);
    if ([sb[@"customTweakConfigurationEnabled"] boolValue] && mode) {
        NSString *listKey = mode == 2 ? @"deniedTweaks" : @"allowedTweaks";
        NSMutableArray *list = [sb[listKey] isKindOfClass:[NSArray class]] ? [sb[listKey] mutableCopy] : [NSMutableArray array];
        NSString *rk = [@"springboard." stringByAppendingString:listKey];
        BOOL c = mode == 2 ? SetMembershipRecorded(list, [sb[@"overwriteGlobalTweakConfiguration"] boolValue] ? deny : @[], keep, rk, record) : SetMembershipRecorded(list, keep, deny, rk, record);
        if (c) { sb[listKey] = list; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps; changed = YES; }
    }
    AsMobile(^BOOL{ return [record writeToFile:@CHOICYRECORD atomically:YES]; });
    if (!changed) { ELog(@"MSB on (%@): Choicy already keeps %@ loading", why, chosen ? [@"only " stringByAppendingString:chosen] : @"no engine"); return; }
    AsMobile(^BOOL{ return [prefs writeToFile:@CHOICYPREFS atomically:YES]; });
    notify_post("com.opa334.choicyprefs/ReloadPrefs");
    TellSpringBoardEnginesChanged();
    ELog(@"MSB on (%@): Choicy set to load %@ (recorded)", why, chosen ? [@"only " stringByAppendingString:chosen] : @"no engine");
}
// The fallback's alert (a system alert from this daemon is not shown on iOS 15): the Dock's SpringBoard part (common/OffAlert.h, MacDock line) shows it,
// with the reason in the file below.
static void OfferRespring(NSString *how) {
    NSString *msg = [NSString stringWithFormat:@"MacStatusBar is switched off in %@. Your window engine's own settings are back. Respring to finish.", how];
    if ([msg writeToFile:@ESTATEDIR "/msb-off-alert" atomically:YES encoding:NSUTF8StringEncoding error:nil]) chmod(ESTATEDIR "/msb-off-alert", 0644);
    notify_post("com.besiktasliseba.msb.offrestored");
    ELog(@"MSB off: asked SpringBoard to offer a respring");
}
// Stage Manager (StatusBar.x, DMStageManagerWatch) is held off while our engine runs, the user's wish kept in stageManagerUserOn. Removed or switched
// off: that wish comes back now, as mobile, in Apple's key (with TrollPad installed, in the TP-prefixed key it moves Apple's key to), and our note goes.
// A running SpringBoard does the same itself when it sees the off marker; the respring that follows reads it.
static void GiveBackStageManager(NSString *why) {
    CFStringRef ours = CFSTR("com.besiktasliseba.macstatusbar"), sb = CFSTR("com.apple.springboard");
    CFPreferencesSynchronize(ours, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL trollPad = Exists(@TWEAKDIR "/TrollPadSB.dylib");
    // (on only because Stage Manager was OUR engine: given back OFF -- logic test F5; this could only ever write "on")
    CFPropertyListRef mine = CFPreferencesCopyValue(CFSTR("stageManagerOnForEngine"), ours, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (mine) {
        CFRelease(mine);
        CFPreferencesSetValue(trollPad ? CFSTR("TPSBChamoisWindowingEnabled") : CFSTR("SBChamoisWindowingEnabled"), kCFBooleanFalse, sb, CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPreferencesSynchronize(sb, CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPreferencesSetValue(CFSTR("stageManagerOnForEngine"), NULL, ours, CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPreferencesSynchronize(ours, CFSTR("mobile"), kCFPreferencesAnyHost);
        ELog(@"%@: Stage Manager was on only as the window engine -- switched back off%@", why, trollPad ? @" (TrollPad's key)" : @"");
    }
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("stageManagerUserOn"), ours, CFSTR("mobile"), kCFPreferencesAnyHost);
    if (!v) return;
    CFRelease(v);
    CFPreferencesSetValue(trollPad ? CFSTR("TPSBChamoisWindowingEnabled") : CFSTR("SBChamoisWindowingEnabled"), kCFBooleanTrue, sb, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(sb, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSetValue(CFSTR("stageManagerUserOn"), NULL, ours, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(ours, CFSTR("mobile"), kCFPreferencesAnyHost);
    ELog(@"%@: Stage Manager is back on, as the user had it%@", why, trollPad ? @" (TrollPad's key)" : @"");
}
static void RestoreForOff(NSString *how, NSString *why) {
    NSString *status = DpkgStatus();
    ELog(@"MSB off (%@): switched off in %@ -- giving the engines back now, so the next respring comes up without Mac Status Bar's changes", why, how);
    mkdir(ESTATEDIR, 0755);   // the marker FIRST: Mac Status Bar, still running until the respring, sees it and stops holding the engines' settings
    { FILE *m = fopen(OFFMARKER, "w"); if (m) { fputs(how.UTF8String, m); fclose(m); } chmod(OFFMARKER, 0644); }
    GiveBackEngineSettings();
    if (MSBDPackageOnDisk(status, @"com.opa334.choicy")) GiveBackChoicyEngines();
    GiveBackAll(@"Mac Status Bar is switched off");
    GiveBackStageManager(@"MSB off");
    mkdir(ESTATEDIR, 0755);
    FILE *f = fopen(OFFMARKER, "w"); if (f) { fputs(how.UTF8String, f); fclose(f); }
}
static void PrepareForOn(NSString *why) {
    NSString *status = DpkgStatus();
    unlink(OFFMARKER);
    unlink(ESTATEDIR "/msb-off-alert");   // (plan 3d-7: switched on again, so no "Mac Status Bar Is Off" alert may be shown any more)
    if (!TweakMeantToRun()) { ELog(@"%@: MacStatusBar&Dock is off (untested iPadOS or safe mode) -- no engine choice applied", why); return; }
    if (MSBDPackageOnDisk(status, @"com.opa334.choicy")) ChoicyApplyChosenEngine(why);
    else ApplyEngines(why);   // (iCleaner Pro setups: the other engines renamed again)
}
// The slow fallback (a switch-off the watcher missed, e.g. a respring before Choicy's change reached the disk): 95 s after SpringBoard starts, if Mac
// Status Bar is not running and the configuration says it is off, the engines are given back and SpringBoard offers a respring.
static void CheckMacStatusBarOff(NSString *reason) {
    if (DpkgBusy()) return;
    NSString *status = DpkgStatus();
    if (!PackageInstalled(status, @"com.besiktasliseba.macstatusbaranddock")) return;
    time_t started = 0; int sbpid = SpringBoardPid(&started);
    if (!sbpid || time(NULL) - started < 20) return;   // SpringBoard (re)starting: too early to tell (the configuration check below is what decides)
    if (Exists(@"/var/mobile/.eksafemode")) return;   // Safe Mode: no tweak runs, that says nothing about Mac Status Bar
    int token = 0; uint64_t alive = 0;
    if (notify_register_check("com.besiktasliseba.macstatusbar.alive", &token) == NOTIFY_STATUS_OK) { notify_get_state(token, &alive); notify_cancel(token); }
    NSString *how = nil;
    BOOL off = MacStatusBarSwitchedOff(status, &how);
    if (alive == (uint64_t)sbpid || !off) return;   // running, or not switched off: nothing to do
    if (Exists(@OFFMARKER)) return;   // already given back for this switch-off (by the watcher)
    RestoreForOff(how, [NSString stringWithFormat:@"%@, fallback: not loaded in SpringBoard %d, heartbeat %llu", reason, sbpid, alive]);
    OfferRespring(how);
}
// What the watcher's decision depends on: Choicy's file, TweakInject (iCleaner's renames), dpkg's status, the off marker, Safe Mode. Unchanged since
// the last look -> nothing to decide (the 2 s check and every event from the preferences folder then cost a few stat calls, no plist read).
static BOOL ConfigMayHaveChanged(void) {
    static struct { struct timespec m[3]; ino_t i[3]; off_t z[3]; int e[3]; } last;
    static BOOL have = NO;
    const char *paths[3] = { CHOICYPREFS, TWEAKDIR, "/var/jb/var/lib/dpkg/status" };
    __typeof__(last) now; memset(&now, 0, sizeof(now));
    for (int i = 0; i < 3; i++) {
        struct stat st;
        if (stat(paths[i], &st) == 0) { now.m[i] = st.st_mtimespec; now.i[i] = st.st_ino; now.z[i] = st.st_size; }
    }
    now.e[0] = Exists(@OFFMARKER); now.e[1] = Exists(@"/var/mobile/.eksafemode"); now.e[2] = Exists(@ESTATEDIR "/msb-config");
    BOOL changed = !have || memcmp(&now, &last, sizeof(now)) != 0;
    last = now; have = YES;
    return changed;
}
// The watcher: Choicy's settings file and TweakInject (iCleaner's renames) are watched with kernel file events, so a switch-off or switch-on is
// prepared within milliseconds of the change reaching the disk (many users tap Respring right after the switch); a 2 s poll stays as a backup. The
// state last seen is kept in a file, so a daemon restart does not replay anything.
static void EvaluateMacStatusBarConfig(NSString *source) {
    @autoreleasepool {
        if (DpkgBusy()) return;   // (a package transaction: the 2 s check looks again once it is over)
        if (!ConfigMayHaveChanged()) return;   // (nothing it reads changed since the last look: a few stat calls)
        static BOOL installed = NO; static __unsafe_unretained NSString *seen;
        NSString *statusCache = DpkgStatus();
        if (statusCache != seen) { seen = statusCache; installed = PackageInstalled(statusCache, @"com.besiktasliseba.macstatusbaranddock"); }
        if (!installed || Exists(@"/var/mobile/.eksafemode")) return;
        NSString *how = nil;
        BOOL off = MacStatusBarSwitchedOff(statusCache, &how);
        NSString *last = [NSString stringWithContentsOfFile:@ESTATEDIR "/msb-config" encoding:NSUTF8StringEncoding error:nil];
        NSString *now = off ? @"off" : @"on";
        if (!off && Exists(@OFFMARKER)) { unlink(OFFMARKER); unlink(ESTATEDIR "/msb-off-alert"); }   // (a stale marker must never keep a running Mac Status Bar from holding its engine)
        if ([last isEqualToString:now]) return;
        mkdir(ESTATEDIR, 0755);
        [now writeToFile:@ESTATEDIR "/msb-config" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (!last) { ELog(@"MSB watcher: Mac Status Bar is %@ (first look)", now); return; }
        ELog(@"MSB watcher: Mac Status Bar switched %@ (noticed by %@)", now, source);
        if (off) { if (!Exists(@OFFMARKER)) RestoreForOff(how, source); }
        else PrepareForOn(@"switched on again");
    }
}
static dispatch_source_t WatchPath(const char *path, unsigned long mask, NSString *name, void (^rearm)(void)) {
    int fd = open(path, O_EVTONLY | O_CLOEXEC);   // (CLOEXEC: starting over after a cfprefsd restart runs no cancel handler -- not carried into the fresh process)
    if (fd < 0) return nil;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, mask, dispatch_get_main_queue());
    dispatch_source_set_event_handler(src, ^{
        unsigned long got = dispatch_source_get_data(src);
        EvaluateMacStatusBarConfig(name);
        if (got & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE)) { dispatch_source_cancel(src); if (rearm) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), rearm); }
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    return src;
}
static void WatchChoicyFile(void) {   // the file itself (written in place) -- re-armed after an atomic replace (a new file under the same name)
    static dispatch_source_t fileSrc;
    fileSrc = WatchPath(CHOICYPREFS, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE, @"Choicy's settings file", ^{ WatchChoicyFile(); });
    if (!fileSrc) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ WatchChoicyFile(); });
}
static dispatch_source_t gConfigTimer, gSpringBoardTimer;   // (the 2 s and 10 s checks: paused while the screen is off, see WatchScreen)
static void WatchMacStatusBarConfig(void) {
    static dispatch_source_t prefsDir, tweakDir;
    prefsDir = WatchPath(PREFSDIR, DISPATCH_VNODE_WRITE, @"the preferences folder", nil);   // (an atomic replace of Choicy's file changes the folder)
    tweakDir = WatchPath(TWEAKDIR, DISPATCH_VNODE_WRITE, @"TweakInject (iCleaner)", nil);    // (iCleaner renames MacStatusBar.dylib here)
    WatchChoicyFile();
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(t, ^{ EvaluateMacStatusBarConfig(@"the 2 s check"); });
    dispatch_resume(t);
    gConfigTimer = t; (void)prefsDir; (void)tweakDir;
}
static void WatchForMacStatusBarOff(void) {   // SpringBoard's pid is looked at every 30 s; each new SpringBoard gets a check 95 s after it started
    static int lastPid = 0;
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        @autoreleasepool {
            StartOverIfPrefsDaemonRestarted(0);   // (a cfprefsd restart noticed while nothing was asked: a fresh process before the next request; pending work is resumed)
            time_t started = 0; int pid = SpringBoardPid(&started);
            if (!pid) return;
            if (pid != lastPid && time(NULL) - started >= 25 && !DpkgBusy()) { lastPid = pid; CheckMacStatusBarOff(@"SpringBoard started"); }
        }
    });
    dispatch_resume(t);
    gSpringBoardTimer = t;   // (kept for the life of the daemon)
}
// Screen off (SpringBoard's own com.apple.springboard.hasBlankedScreen, state 1 = blank): the two checks rest, so the helper does not wake every
// 2 s all night. The kernel file events stay armed (they cost nothing until something changes). Screen on: one look at once, then the checks go on.
static void WatchScreen(void) {
    static int token = 0; static BOOL paused = NO;
    void (^apply)(int) = ^(int t) {
        uint64_t blank = 0; notify_get_state(t, &blank);
        if (blank && !paused) { paused = YES; if (gConfigTimer) dispatch_suspend(gConfigTimer); if (gSpringBoardTimer) dispatch_suspend(gSpringBoardTimer); }
        else if (!blank && paused) { paused = NO; if (gConfigTimer) dispatch_resume(gConfigTimer); if (gSpringBoardTimer) dispatch_resume(gSpringBoardTimer); EvaluateMacStatusBarConfig(@"the screen came on"); }
    };
    if (notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &token, dispatch_get_main_queue(), ^(int t) { apply(t); }) == NOTIFY_STATUS_OK) apply(token);
}

// ---- 4. MacStatusBar&Dock's two lines, the move from the old separate packages, and removal --------------------------------------------------------
// The package shows two lines in Choicy / iCleaner Pro: MacStatusBar (everything except the Dock) and MacDock (the Dock). Settings has one switch for
// each at the top of its page. With Choicy, Settings edits Choicy's own list itself (as mobile, recorded in LINERECORD). With iCleaner Pro only, the
// switch is iCleaner's rename in TweakInject, which needs root: Settings writes the wanted state (lineMacStatusBar / lineMacDock) into our preferences
// and posts com.besiktasliseba.lines.apply; this renames only our two loaders, only if they are our package's own regular files.
#define OURPKG @"com.besiktasliseba.macstatusbaranddock"
#define OURDOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")
#define MIGDIR "/var/jb/var/lib/macstatusbaranddock"
#define LINERECORD PREFSDIR "/MacStatusBar-LineChanges.plist"
static NSArray<NSString *> *OurLines(void) { return @[@"MacStatusBar", @"MacDock"]; }
static BOOL TweakFolderIsSane(void) {   // (DynamicLibraries must be the same folder as TweakInject; /var/jb itself is a symlink into /private/preboot)
    char real[PATH_MAX], tweakdir[PATH_MAX];
    return realpath("/var/jb/Library/MobileSubstrate/DynamicLibraries", real) && realpath(TWEAKDIR, tweakdir) && strcmp(real, tweakdir) == 0;
}
static int LineWanted(NSString *line) {   // 1/0 as Settings asked, -1 = no request
    CFStringRef key = (__bridge CFStringRef)[@"line" stringByAppendingString:line];
    CFPreferencesSynchronize(OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(key, OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    int wanted = (v && CFGetTypeID(v) == CFBooleanGetTypeID()) ? (CFBooleanGetValue(v) ? 1 : 0) : -1;
    if (v) CFRelease(v);
    return wanted;
}
static void ForgetLineWanted(NSString *line) {   // (done: a later spoofed post cannot replay an old request)
    CFPreferencesSetValue((__bridge CFStringRef)[@"line" stringByAppendingString:line], NULL, OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
}
static void ApplyLines(NSString *why) {
    StartOverIfPrefsDaemonRestarted(kWorkLines);
    gPendingWork &= ~kWorkLines;
    if (DpkgBusy()) { ELog(@"lines (%@): a package transaction is running -- nothing done", why); return; }
    NSString *status = DpkgStatus();
    if (!PackageInstalled(status, OURPKG) || ChoicyInstalled(status) || !ICleanerInstalled(status)) return;   // (with Choicy, Settings edits Choicy itself)
    if (!TweakFolderIsSane()) { ELog(@"lines (%@): unexpected tweak folder -- nothing done", why); return; }
    for (NSString *line in OurLines()) {
        int want = LineWanted(line);
        if (want < 0) continue;
        NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", line], *disabled = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", line];
        if (want == 0 && IsRegular(dylib) && !Exists(disabled) && OwnedByPackage(OURPKG, line)) {
            if (rename(dylib.fileSystemRepresentation, disabled.fileSystemRepresentation) == 0) ELog(@"lines (%@): %@ switched off (renamed to .disabled, as iCleaner Pro does)", why, line);
            else ELog(@"lines (%@): %@ could not be switched off (%s)", why, line, strerror(errno));
        } else if (want == 1 && IsRegular(disabled) && !Exists(dylib)) {
            if (rename(disabled.fileSystemRepresentation, dylib.fileSystemRepresentation) == 0) ELog(@"lines (%@): %@ switched on", why, line);
            else ELog(@"lines (%@): %@ could not be switched on (%s)", why, line, strerror(errno));
        } else ELog(@"lines (%@): %@ already %@", why, line, want ? @"on" : @"off");
        ForgetLineWanted(line);
    }
}
// After every install or upgrade of our package: a line switched off in iCleaner Pro stays off (dpkg has just written a fresh <Line>.dylib next to the
// old <Line>.disabled; the new build replaces the old one under the .disabled name, the same rule as for the engines).
static void KeepLinesDisabledAfterUpdate(void) {
    if (!TweakFolderIsSane()) return;
    for (NSString *line in OurLines()) {
        NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", line], *disabled = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", line];
        if (IsRegular(dylib) && IsRegular(disabled) && OwnedByPackage(OURPKG, line) && rename(dylib.fileSystemRepresentation, disabled.fileSystemRepresentation) == 0)
            ELog(@"install: %@ was switched off in iCleaner Pro -- the new build stays switched off", line);
    }
}
// After every install or upgrade (the postinst, before the install's respring): the engine choice is made sure of in Choicy (or by iCleaner Pro's
// renames) NOW. A removal gives it back (the prerm's --uninstall), so after a remove-then-install -- a reinstall, or a switch between the release and
// the beta package -- nothing kept the other engines from loading until SpringBoard's first start asked for it: that start ran every engine next to
// the pick (Stage Manager held off, its windows lost, an old window state restored) and a second respring was needed (1.4 logic test L-6). The
// same decision as at SpringBoard's start (ApplyEngines "request"); after an upgrade it is in place already and nothing changes. Not while
// MacStatusBar&Dock is not meant to run (untested iPadOS without Enable Anyway, the crash guard's safe mode) or is switched off in Choicy or iCleaner
// Pro (after KeepLinesDisabledAfterUpdate, so a line switched off in iCleaner Pro is seen as off). Our own package is only being configured here,
// so its dpkg state is not asked; an engine, Choicy or iCleaner Pro installed or upgraded in the same dpkg run (a Sileo queue) is counted as
// installed though it is only unpacked now (MSBDPackageOnDisk, DpkgState.h: its files are on the device; 1.4.1 logic test M-1).
static void ApplyEnginesAtInstall(void) {
    if (!TweakMeantToRun()) { ELog(@"install: MacStatusBar&Dock is off (untested iPadOS without Enable Anyway, or the crash guard's safe mode) -- no engine choice applied"); return; }
    NSString *status = DpkgStatus(), *how = nil;
    if (MacStatusBarSwitchedOff(status, &how)) { ELog(@"install: Mac Status Bar is switched off in %@ -- no engine choice applied", how); return; }
    if (ChoicyInstalled(status)) { GiveBackAll(@"Choicy is installed"); ChoicyApplyChosenEngine(@"install"); return; }
    if (!ICleanerInstalled(status)) { ELog(@"install: neither Choicy nor iCleaner Pro installed -- nothing to do"); return; }
    ApplyEngineRenames(@"install", status);
}

// The move from the old separate packages (once, from the postinst). Everything is copied or added, nothing of the user's is overwritten:
//  1. every old preference file (com.kaan.<name>.plist, in both Preferences folders) is copied to com.besiktasliseba.<name>.plist unless that exists;
//  2. Choicy: a list that named the old Dock library (DockMagnification) gets the new one (MacDock) too (recorded in LINERECORD, undone on removal);
//     an old small feature switched off for every process is switched off in our Settings instead; per-app entries of the old parts can't be mapped to
//     one line without guessing, so they are only logged (they name libraries that no longer exist and do nothing);
//  3. iCleaner Pro: an old library left renamed to .disabled means that part was switched off: DockMagnification -> MacDock switched off the same way,
//     MacStatusBar stays off, a small feature is switched off in our Settings; the dead .disabled file of the removed package is taken away;
//  4. the small keyboard features and Force Quit: ON where the old package was installed and running (MIGDIR/old-packages, written by the preinst),
//     otherwise the new defaults (keyboard features off, Force Quit on).
static NSString *MigOldPrefix(void) { return [@"com." stringByAppendingString:@"kaan."]; }   // (the old identifiers, only ever read here)
static BOOL WriteMobilePrefsKey(NSString *domain, NSString *key, id value, BOOL onlyIfAbsent) {
    CFStringRef d = (__bridge CFStringRef)domain;
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef cur = CFPreferencesCopyValue((__bridge CFStringRef)key, d, CFSTR("mobile"), kCFPreferencesAnyHost);
    BOOL had = cur != NULL; if (cur) CFRelease(cur);
    if (had && onlyIfAbsent) return NO;
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, d, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
    return YES;
}
static void MigratePrefFiles(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *old = MigOldPrefix();
    for (NSString *dir in @[@PREFSDIR, @"/var/mobile/Library/Preferences"]) {
        for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if (![name hasPrefix:old] || ![name hasSuffix:@".plist"]) continue;
            NSString *from = [dir stringByAppendingPathComponent:name];
            NSString *to = [dir stringByAppendingPathComponent:[@"com.besiktasliseba." stringByAppendingString:[name substringFromIndex:old.length]]];
            if (!IsRegular(from) || Exists(to)) { if (Exists(to)) ELog(@"migrate: %@ exists already -- kept", to.lastPathComponent); continue; }
            NSData *data = [NSData dataWithContentsOfFile:from];
            if (!data) continue;
            BOOL ok = AsMobile(^BOOL{ return [data writeToFile:to atomically:YES]; });
            ELog(@"migrate: %@ -> %@ %@", name, to.lastPathComponent, ok ? @"copied" : @"NOT copied");
        }
    }
}
// old library -> (its old package, the domain and keys of its switch in our Settings, the value that means "off")
static NSDictionary<NSString *, NSArray *> *MigSmallFeatures(void) {
    NSString *o = MigOldPrefix();
    return @{ @"GraveEscapeTweak": @[[o stringByAppendingString:@"graveescapetweak"], @"com.besiktasliseba.graveescapetweak", @[@"enabled"]],
              @"TabMuteTweak": @[[o stringByAppendingString:@"tabmutetweak"], @"com.besiktasliseba.tabmutetweak", @[@"enabled"]],
              @"VolumeGlobeTweak": @[[o stringByAppendingString:@"volumeglobetweak"], @"com.besiktasliseba.volumeglobetweak", @[@"enabled"]],
              @"BrightnessKeyTweak": @[@"brightnesskeytweak", @"com.besiktasliseba.brightnesskeytweak", @[@"screenKeysEnabled", @"backlightKeysEnabled"]],
              @"ForceQuitMenu": @[[o stringByAppendingString:@"forcequitmenu"], @"com.besiktasliseba.forcequitmenu", @[@"enabled"]],
              @"MixAudio": @[[o stringByAppendingString:@"mixaudio"], @"com.besiktasliseba.macstatusbar", @[@"mixAudio"]] };
}
// every other library of the old packages (for the logs and the dead .disabled files)
static NSArray<NSString *> *MigOtherOldLibraries(void) {
    return @[@"MacAppBridge", @"MacAppSizeMenu", @"MacCCGrabber", @"MacEthernetFix", @"MacFolderMenu", @"MacHomeBar", @"MacIconLabels", @"MacLargeTitles",
             @"MacLockStatusBar", @"MacPageDots", @"MacPointer", @"MacSettings", @"MacSettingsBadge", @"MacStatusBarSettings", @"DockMagnificationSettings"];
}
static void RecordLineChange(NSMutableDictionary *record, NSString *listKey, NSString *entry) {
    NSMutableDictionary *l = [record[listKey] isKindOfClass:[NSDictionary class]] ? [record[listKey] mutableCopy] : [NSMutableDictionary dictionary];
    l[entry] = @"added";
    record[listKey] = l;
}
static NSSet<NSString *> *MigrateChoicy(void) {   // returns the old small-feature libraries denied for every process
    NSMutableSet *globallyOff = [NSMutableSet set];
    if (!ChoicyInstalled(DpkgStatus())) return globallyOff;
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYPREFS] mutableCopy];
    if (!prefs) { ELog(@"migrate: Choicy's settings unreadable -- left as they are"); return globallyOff; }
    NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:@LINERECORD] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSArray *small = [MigSmallFeatures() allKeys], *others = MigOtherOldLibraries();
    __block BOOL changed = NO;
    // one list: DockMagnification -> MacDock added; old parts logged
    NSMutableArray *(^fix)(NSArray *, NSString *) = ^NSMutableArray *(NSArray *list, NSString *listKey) {
        NSMutableArray *l = [list mutableCopy];
        if ([l containsObject:@"DockMagnification"] && ![l containsObject:@"MacDock"]) {
            [l addObject:@"MacDock"]; RecordLineChange(record, listKey, @"MacDock"); changed = YES;
            ELog(@"migrate: Choicy %@: DockMagnification is listed -> MacDock added", listKey);
        }
        for (NSString *n in l) if ([small containsObject:n] || [others containsObject:n]) ELog(@"migrate: Choicy %@ names the old part %@ (no library of that name any more)%@", listKey, n,
                                                                                               [listKey isEqualToString:@"globalDeniedTweaks"] && [small containsObject:n] ? @" -> its switch in Settings is set off" : @" -- left as it is");
        return l;
    };
    if ([prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]]) {
        prefs[@"globalDeniedTweaks"] = fix(prefs[@"globalDeniedTweaks"], @"globalDeniedTweaks");
        for (NSString *n in prefs[@"globalDeniedTweaks"]) if ([small containsObject:n]) [globallyOff addObject:n];
    }
    NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
    for (NSString *app in [apps allKeys]) {
        NSMutableDictionary *a = [apps[app] isKindOfClass:[NSDictionary class]] ? [apps[app] mutableCopy] : nil;
        if (!a) continue;
        for (NSString *k in @[@"deniedTweaks", @"allowedTweaks"]) if ([a[k] isKindOfClass:[NSArray class]]) a[k] = fix(a[k], [NSString stringWithFormat:@"app.%@.%@", app, k]);
        apps[app] = a;
    }
    if (apps) prefs[@"appSettings"] = apps;
    if (changed) {
        AsMobile(^BOOL{ return [record writeToFile:@LINERECORD atomically:YES]; });
        AsMobile(^BOOL{ return [prefs writeToFile:@CHOICYPREFS atomically:YES]; });
        notify_post("com.opa334.choicyprefs/ReloadPrefs");
    }
    return globallyOff;
}
static NSSet<NSString *> *MigrateICleaner(void) {   // returns the old small-feature libraries that were switched off in iCleaner Pro
    NSMutableSet *off = [NSMutableSet set];
    if (!TweakFolderIsSane()) return off;
    NSString *(^path)(NSString *, NSString *) = ^NSString *(NSString *n, NSString *ext) { return [NSString stringWithFormat:@TWEAKDIR "/%@.%@", n, ext]; };
    if (IsRegular(path(@"DockMagnification", @"disabled")) && !Exists(path(@"DockMagnification", @"dylib"))) {
        if (IsRegular(path(@"MacDock", @"dylib")) && !Exists(path(@"MacDock", @"disabled")) && rename(path(@"MacDock", @"dylib").fileSystemRepresentation, path(@"MacDock", @"disabled").fileSystemRepresentation) == 0)
            ELog(@"migrate: iCleaner Pro had DockMagnification off -> MacDock switched off the same way");
    }
    NSMutableArray *dead = [NSMutableArray arrayWithArray:[MigSmallFeatures() allKeys]];
    [dead addObjectsFromArray:MigOtherOldLibraries()]; [dead addObject:@"DockMagnification"];
    for (NSString *n in dead) {
        NSString *d = path(n, @"disabled");
        if (!IsRegular(d) || Exists(path(n, @"dylib"))) continue;
        if (MigSmallFeatures()[n]) { [off addObject:n]; ELog(@"migrate: iCleaner Pro had %@ off -> its switch in Settings is set off", n); }
        if (unlink(d.fileSystemRepresentation) == 0) ELog(@"migrate: the old package's leftover %@.disabled removed", n);
    }
    return off;
}
static void Migrate(void) {
    mkdir(MIGDIR, 0755);
    if (Exists(@MIGDIR "/migrated")) { ELog(@"migrate: done before -- nothing to do"); return; }
    MigratePrefFiles();
    NSMutableSet *off = [NSMutableSet setWithSet:MigrateChoicy()];
    [off unionSet:MigrateICleaner()];
    NSString *recorded = [NSString stringWithContentsOfFile:@MIGDIR "/old-packages" encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray *was = [recorded componentsSeparatedByString:@"\n"];
    NSDictionary *features = MigSmallFeatures();
    for (NSString *lib in features) {
        NSArray *f = features[lib]; NSString *pkg = f[0], *domain = f[1]; NSArray *keys = f[2];
        BOOL installed = [was containsObject:pkg];
        for (NSString *key in keys) {
            if ([off containsObject:lib]) { WriteMobilePrefsKey(domain, key, @NO, NO); ELog(@"migrate: %@ %@ = off (the old part was switched off)", domain, key); }
            else if (installed && ![lib isEqualToString:@"MixAudio"] && ![lib isEqualToString:@"ForceQuitMenu"]) {
                if (WriteMobilePrefsKey(domain, key, @YES, YES)) ELog(@"migrate: %@ %@ = on (the old package was installed)", domain, key);
                else ELog(@"migrate: %@ %@ kept as the user had it", domain, key);
            }
        }
    }
    // the old separate on/off entries (MacStatusBarToggle / DockMagnificationToggle) wrote tweakEnabled = NO; the lines replace them
    for (NSArray *p in @[@[@"com.besiktasliseba.macstatusbar", @"MacStatusBar"], @[@"com.besiktasliseba.dockmagnification", @"MacDock"]]) {
        CFStringRef d = (__bridge CFStringRef)p[0];
        CFPreferencesSynchronize(d, CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("tweakEnabled"), d, CFSTR("mobile"), kCFPreferencesAnyHost);
        BOOL wasOff = v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v);
        if (v) CFRelease(v);
        if (!wasOff) continue;
        // (it stays off, now the same way Choicy / iCleaner Pro switch a line off, so the switch at the top of its page shows it and turns it back on)
        NSString *line = p[1];
        BOOL done = NO;
        if (ChoicyInstalled(DpkgStatus())) {
            NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYPREFS] mutableCopy];
            NSMutableDictionary *record = [[NSDictionary dictionaryWithContentsOfFile:@LINERECORD] mutableCopy] ?: [NSMutableDictionary dictionary];
            if (prefs) {
                NSMutableArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? [prefs[@"globalDeniedTweaks"] mutableCopy] : [NSMutableArray array];
                if (![global containsObject:line]) { [global addObject:line]; RecordLineChange(record, @"globalDeniedTweaks", line); }
                prefs[@"globalDeniedTweaks"] = global;
                done = AsMobile(^BOOL{ return [record writeToFile:@LINERECORD atomically:YES] && [prefs writeToFile:@CHOICYPREFS atomically:YES]; });
                notify_post("com.opa334.choicyprefs/ReloadPrefs");
            }
        } else if (TweakFolderIsSane()) {
            NSString *dylib = [NSString stringWithFormat:@TWEAKDIR "/%@.dylib", line], *disabled = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", line];
            done = IsRegular(dylib) && !Exists(disabled) && rename(dylib.fileSystemRepresentation, disabled.fileSystemRepresentation) == 0;
        }
        if (done) WriteMobilePrefsKey(p[0], @"tweakEnabled", nil, NO);
        ELog(@"migrate: %@ was switched off with the old on/off entry -> %@ %@", p[0], line, done ? @"switched off in Choicy / iCleaner Pro instead" : @"left switched off the old way");
    }
    [@"1" writeToFile:@MIGDIR "/migrated" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ELog(@"migrate: finished");
}
// The one-time welcome alert (2026-09-25), decided here before anything of ours is written (the postinst runs this first): only a FIRST install gets
// MIGDIR/welcome-pending, which Mac Status Bar's SpringBoard part needs to show it. Anything that shows the package or its settings were here before
// -- an upgrade (dpkg's old version), an earlier install of this package (the migration marker), the old separate packages, or any preference file
// of ours or of the old com.kaan.* tweaks -- marks it as already shown instead (welcomeShown), silently.
#define WELCOMEFILE MIGDIR "/welcome-pending"
static NSString *NotFirstInstallReason(const char *oldVersion) {   // nil: a first install (nothing of ours or of the old packages was here)
    if (oldVersion && *oldVersion) return [NSString stringWithFormat:@"upgrade from %s", oldVersion];
    if (Exists(@MIGDIR "/migrated")) return @"installed before";
    if ([[NSString stringWithContentsOfFile:@MIGDIR "/old-packages" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return @"the old packages were installed";
    NSString *old = MigOldPrefix();
    for (NSString *dir in @[@PREFSDIR, @"/var/mobile/Library/Preferences"])
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
            if ([name hasPrefix:@"com.besiktasliseba."] || [name hasPrefix:old] || [name hasPrefix:@"MacStatusBar"]) return [@"settings found: " stringByAppendingString:name];
    return nil;
}
static void WelcomeCheck(const char *oldVersion) {
    mkdir(MIGDIR, 0755);
    if (Exists(@WELCOMEFILE)) { ELog(@"welcome: still pending from the first install -- kept"); return; }
    NSString *why = NotFirstInstallReason(oldVersion);
    if (why) {
        WriteMobilePrefsKey(@"com.besiktasliseba.macstatusbaranddock", @"welcomeShown", @YES, YES);
        ELog(@"welcome: not a first install (%@) -- marked as shown", why);
        return;
    }
    BOOL ok = [@"1" writeToFile:@WELCOMEFILE atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ELog(@"welcome: first install -- the welcome alert %@", ok ? @"will be shown once" : @"could NOT be marked (not shown)");
}
// New defaults for new installs only (2026-09-25). A setting nobody has touched is not stored, so its default decides -- and a changed default would
// change it on every iPad that updates. So, once, on an update, every setting whose default changed gets the OLD default written in where nothing
// is stored yet; what the user set stays. A first install only notes that it started with the new defaults. Two steps in the postinst: the decision
// right after the welcome check (the same test, before anything of ours is written), the writes after the move from the old packages (so a moved
// setting wins). Done at most once: the marker file, and defaultsVersion in our settings (which survives a purge). What was written is logged and
// listed in MIGDIR/defaults-frozen. Each entry names the version that changed its default: an update freezes only what changed after the version
// it had already settled (v2 keys are not written again on a device that ran v2; a v2 first install keeps its new v2 defaults).
#define DEFAULTSVERSION 3
#define DEFAULTSDECISION MIGDIR "/defaults-decision"
static NSArray<NSArray *> *OldDefaults(void) {   // domain, key, the value it had before, the version that changed it
    // (the Go menu's old app list is not frozen: the only devices that ever had it have their list stored, so new installs get the neutral seed)
    return @[ @[@"com.besiktasliseba.macstatusbar", @"showSeconds", @YES, @2],
              @[@"com.besiktasliseba.macstatusbar", @"tidyKeyboardPill", @YES, @2],
              @[@"com.besiktasliseba.dockmagnification", @"dockRecentsCount", @4, @2],
              @[@"com.besiktasliseba.macpagedots", @"enabled", @YES, @2],       // (YES = page dots hidden)
              @[@"com.besiktasliseba.maciconlabels", @"enabled", @YES, @2],     // (YES = app names hidden)
              @[@"com.besiktasliseba.macstatusbar", @"skipLockAfterRespring", @YES, @3] ];   // (every build before v3 skipped it, with no passcode)
}
static NSString *DefaultsMarker(int version) { return [NSString stringWithFormat:@MIGDIR "/defaults-v%d", version]; }
static NSInteger DefaultsDone(void) {   // the newest defaults version this device has settled (0: none)
    CFPreferencesSynchronize(OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("defaultsVersion"), OURDOMAIN, CFSTR("mobile"), kCFPreferencesAnyHost);
    NSInteger have = (v && CFGetTypeID(v) == CFNumberGetTypeID()) ? [(__bridge NSNumber *)v integerValue] : 0;
    if (v) CFRelease(v);
    for (int n = DEFAULTSVERSION; n > have && n >= 2; n--) if (Exists(DefaultsMarker(n))) { have = n; break; }
    return have;
}
static BOOL DefaultsSettled(void) { return DefaultsDone() >= DEFAULTSVERSION; }
// Old defaults are frozen only on a REAL upgrade: dpkg names an old version of this package, or the old separate packages were here (their marker
// or their settings). Leftover files of ours alone (a reinstall after removal, settings a cleaner left behind) get the new defaults: public users
// only ever had the new ones (every public install settles v3 at its first install).
static NSString *FreezeReason(const char *oldVersion) {
    if (oldVersion && *oldVersion) return [NSString stringWithFormat:@"upgrade from %s", oldVersion];
    if ([[NSString stringWithContentsOfFile:@MIGDIR "/old-packages" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return @"the old packages were installed";
    NSString *old = MigOldPrefix();
    for (NSString *dir in @[@PREFSDIR, @"/var/mobile/Library/Preferences"])
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
            if ([name hasPrefix:old]) return [@"old packages' settings found: " stringByAppendingString:name];
    return nil;
}
static void DefaultsCheck(const char *oldVersion) {
    mkdir(MIGDIR, 0755);
    unlink(DEFAULTSDECISION);
    if (DefaultsSettled()) return;
    NSString *why = FreezeReason(oldVersion);
    [(why ? [@"freeze: " stringByAppendingString:why] : @"fresh") writeToFile:@DEFAULTSDECISION atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void FreezeOldDefaults(void) {
    NSInteger done = DefaultsDone();
    // (a reinstall after a removal lands here too: defaultsVersion survives a purge, so it gets no Stage Manager default and, on iPadOS 16,
    //  the "update" notice instead of the first-install welcome -- intended: that iPad had the tweak before, logic test F12)
    if (done >= DEFAULTSVERSION) { ELog(@"defaults: v%d settled before (an update, or a reinstall after removal) -- nothing to do", DEFAULTSVERSION); return; }
    NSString *decision = [NSString stringWithContentsOfFile:@DEFAULTSDECISION encoding:NSUTF8StringEncoding error:nil];
    unlink(DEFAULTSDECISION);
    if (!decision) decision = @"freeze: no decision recorded";   // (when in doubt, the user keeps what they had)
    BOOL fresh = [decision isEqualToString:@"fresh"];
    NSMutableArray *frozen = [NSMutableArray array];
    if (!fresh) for (NSArray *e in OldDefaults())
        if ([e[3] integerValue] > done && WriteMobilePrefsKey(e[0], e[1], e[2], YES)) [frozen addObject:[NSString stringWithFormat:@"%@ %@", e[0], e[1]]];
    WriteMobilePrefsKey(@"com.besiktasliseba.macstatusbaranddock", @"defaultsVersion", @DEFAULTSVERSION, NO);
    NSString *list = frozen.count ? [[frozen componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"] : @"";
    [list writeToFile:DefaultsMarker(DEFAULTSVERSION) atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (frozen.count) {   // (added to the list of earlier versions)
        NSString *before = [NSString stringWithContentsOfFile:@MIGDIR "/defaults-frozen" encoding:NSUTF8StringEncoding error:nil] ?: @"";
        [[before stringByAppendingString:list] writeToFile:@MIGDIR "/defaults-frozen" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    if (fresh) {
        // (1.1.0-1.1.2 made Stage Manager the engine here on iPads that can run it; 1.1.3: Aerial 5.0 is the recommended engine for everyone again
        //  -- a first install keeps the normal default. The update notice about Stage Manager is still never shown after a first install.)
        WriteMobilePrefsKey(@"com.besiktasliseba.macstatusbaranddock", @"stageManagerEngineNoticeShown", @YES, YES);
    }
    if (fresh) ELog(@"defaults: first install -- the new defaults apply");
    else ELog(@"defaults: %@ (from v%ld) -- the old defaults kept for %lu untouched setting(s): %@", decision, (long)done, (unsigned long)frozen.count, frozen.count ? [frozen componentsJoinedByString:@", "] : @"none");
}
// Removal (the prerm, not on an upgrade): everything we changed is given back -- the engines' own settings, our Choicy entries for the engines and
// for the lines, the engines we renamed for iCleaner Pro -- and our lines' own .disabled files go (dpkg does not know them).
static void Uninstall(void) {
    ELog(@"removal: giving everything back");
    // Spotlight: the rows of tweak settings we donated into Settings' index are deleted by the running SpringBoard (statusbar/SpotlightFiles.x,
    // common/TweakSpotlight.h kMTSRemoveAllNote); a moment for it before the files go.
    notify_post("com.besiktasliseba.msbd.spotlight.removeall");
    usleep(800000);
    mkdir(ESTATEDIR, 0755);
    { FILE *m = fopen(OFFMARKER, "w"); if (m) { fputs("removal", m); fclose(m); } chmod(OFFMARKER, 0644); }   // (the running SpringBoard stops holding the engines)
    GiveBackEngineSettings();
    GiveBackStageManager(@"removal");
    NSString *status = DpkgStatus();
    if (MSBDPackageOnDisk(status, @"com.opa334.choicy")) {
        GiveBackChoicyEngines();
        NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:@LINERECORD];
        NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:@CHOICYPREFS] mutableCopy];
        if (record && prefs) {
            BOOL changed = NO;
            for (NSString *listKey in record) {
                NSDictionary *entries = [record[listKey] isKindOfClass:[NSDictionary class]] ? record[listKey] : nil;
                NSMutableArray *list = nil; NSMutableDictionary *apps = nil, *a = nil; NSString *key = nil;
                if ([listKey isEqualToString:@"globalDeniedTweaks"]) list = [prefs[listKey] isKindOfClass:[NSArray class]] ? [prefs[listKey] mutableCopy] : nil;
                else if ([listKey hasPrefix:@"app."]) {
                    NSString *rest = [listKey substringFromIndex:4];
                    NSRange dot = [rest rangeOfString:@"." options:NSBackwardsSearch];
                    if (dot.location == NSNotFound) continue;
                    NSString *app = [rest substringToIndex:dot.location]; key = [rest substringFromIndex:dot.location + 1];
                    apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
                    a = [apps[app] isKindOfClass:[NSDictionary class]] ? [apps[app] mutableCopy] : nil;
                    list = [a[key] isKindOfClass:[NSArray class]] ? [a[key] mutableCopy] : nil;
                    if (list) { for (NSString *e in entries) if ([entries[e] isEqual:@"added"] && [OurLines() containsObject:e]) { [list removeObject:e]; changed = YES; }
                                a[key] = list; apps[app] = a; prefs[@"appSettings"] = apps; }
                    continue;
                }
                if (!list) continue;
                for (NSString *e in entries) if ([entries[e] isEqual:@"added"] && [OurLines() containsObject:e] && [list containsObject:e]) { [list removeObject:e]; changed = YES; }
                prefs[listKey] = list;
            }
            if (changed) { AsMobile(^BOOL{ return [prefs writeToFile:@CHOICYPREFS atomically:YES]; }); notify_post("com.opa334.choicyprefs/ReloadPrefs"); ELog(@"removal: our Choicy entries for the lines taken out"); }
        }
        AsMobile(^BOOL{ return unlink(LINERECORD) == 0; });
    }
    GiveBackAll(@"MacStatusBar&Dock removed");
    // The crash guard's state goes with its record (the postrm deletes the record files): a reinstall must never come back in safe mode, or with a
    // footer about a part "turned off", with nothing left to explain it. The user's own settings stay (as usual on removal).
    CFStringRef gd = CFSTR(MSBD_GATE_DOMAIN);
    CFPreferencesSetValue(CFSTR(MSBD_SAFE_KEY), NULL, gd, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSetValue(CFSTR("crashGuardAction"), NULL, gd, CFSTR("mobile"), kCFPreferencesAnyHost);   // (MSBD_GUARD_ACTION_KEY, CrashGuard.h)
    // "Enable Anyway" (untested iPadOS) goes too: it is an at-your-own-risk choice for this install, and the guard may have turned it off itself
    // (its record, which explained that, is gone): a reinstall asks again instead of coming back half-decided.
    CFPreferencesSetValue(CFSTR(MSBD_GATE_KEY), NULL, gd, CFSTR("mobile"), kCFPreferencesAnyHost);
    CFPreferencesSynchronize(gd, CFSTR("mobile"), kCFPreferencesAnyHost);
    ELog(@"removal: the crash guard's safe mode and note, and Enable Anyway, cleared");
    {   // Number of Recent Apps "None" switched Apple's own "Show Suggested and Recent Apps in Dock" off (DMRootListController.m): given back
        CFPreferencesSynchronize(CFSTR("com.besiktasliseba.dockmagnification"), CFSTR("mobile"), kCFPreferencesAnyHost);
        CFPropertyListRef n = CFPreferencesCopyValue(CFSTR("dockRecentsCount"), CFSTR("com.besiktasliseba.dockmagnification"), CFSTR("mobile"), kCFPreferencesAnyHost);
        BOOL none = n && CFGetTypeID(n) == CFNumberGetTypeID() && [(__bridge NSNumber *)n integerValue] == 0;
        if (n) CFRelease(n);
        if (none && WriteMobilePrefsKey(@"com.apple.springboard", @"SBRecentsEnabled", nil, NO)) ELog(@"removal: Apple's recent apps in the Dock back to its default (on)");
    }
    if (TweakFolderIsSane()) for (NSString *line in OurLines()) {
        NSString *d = [NSString stringWithFormat:@TWEAKDIR "/%@.disabled", line];
        if (IsRegular(d) && unlink(d.fileSystemRepresentation) == 0) ELog(@"removal: %@.disabled removed", line);
    }
}

#if DEBUG
// --dry-run-engines <status file> [--old]: the engine choice the postinst would make with that dpkg status text (the real preferences, Choicy's
// settings and the tweak folder are read; nothing is written) -- an engine "unpacked" in it is the same Sileo run as ours (M-1).
static void DryRunEngines(const char *statusPath, BOOL oldRule) {
    gDryOldRule = oldRule;
    NSString *status = [NSString stringWithContentsOfFile:@(statusPath) encoding:NSUTF8StringEncoding error:nil] ?: @"";
    BOOL windowing = YES, picked = NO;
    NSString *chosen = EngineToKeep(status, &windowing, &picked);
    if (!windowing) chosen = nil;
    NSDictionary *libs = EngineLibs(), *pkgs = EnginePackage();
    NSMutableArray *deny = [NSMutableArray array], *notInstalled = [NSMutableArray array];
    for (NSString *e in libs) if (![e isEqualToString:chosen]) [MSBDPackageOnDisk(status, pkgs[e]) ? deny : notInstalled addObjectsFromArray:libs[e]];
    printf("dry run (%s rule): Choicy %s, windowing %d, engine kept loading: %s (picked %d), kept from loading: %s, counted as not installed: %s\n", oldRule ? "the old" : "the 1.4.1",
        ChoicyInstalled(status) ? "on the device" : "not counted", windowing, (chosen ?: @"none").UTF8String, picked,
        [deny componentsJoinedByString:@" "].UTF8String, [notInstalled componentsJoinedByString:@" "].UTF8String);
    gDryOldRule = NO;
}
#endif
int main(int argc, char **argv) {
    @autoreleasepool {
        // Not an iPad (common/DeviceGate.h): nothing but giving back. The daemon stays idle (launchd would restart it if it quit).
        if (argc > 1 && strcmp(argv[1], "--os-major") == 0) { printf("%ld\n", (long)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion); return 0; }   // (postinst: the iPadOS 17+ Settings entries)
        if (argc > 1 && strcmp(argv[1], "--is-ipad") == 0) return MSBDIsIPad() ? 0 : 2;   // (postinst: 2, not 1, so a failed start never reads as "not an iPad")
        if (!MSBDIsIPad()) {
            if (argc < 2) dispatch_main();
            if (strcmp(argv[1], "--uninstall") != 0 && strcmp(argv[1], "--restore-engines") != 0 && strcmp(argv[1], "--restore-msb-off") != 0) return 0;
        }
        if (argc > 1 && strcmp(argv[1], "--restore-engines") == 0) { GiveBackAll(@"package removed"); return 0; }
        if (argc > 1 && strcmp(argv[1], "--apply-engines") == 0) { ApplyEngines(@"manual"); return 0; }
        if (argc > 1 && strcmp(argv[1], "--check-msb-off") == 0) { CheckMacStatusBarOff(@"manual"); return 0; }
        if (argc > 1 && strcmp(argv[1], "--restore-msb-off") == 0) { NSString *how = nil; if (MacStatusBarSwitchedOff(DpkgStatus(), &how)) RestoreForOff(how, @"manual"); else printf("Mac Status Bar is not switched off\n"); return 0; }
#if DEBUG
        if (argc > 4 && strcmp(argv[1], "--dry-run-choicy") == 0) { DryRunChoicy(argv[2], argv[3], argv[4]); return 0; }
        if (argc > 2 && strcmp(argv[1], "--dry-run-engines") == 0) { DryRunEngines(argv[2], argc > 3 && strcmp(argv[3], "--old") == 0); return 0; }
        if (argc > 1 && strcmp(argv[1], "--dpkg-busy") == 0) { printf("%s\n", DpkgBusy() ? "busy" : "free"); return 0; }   // (test of the package-transaction check)
#endif
        if (argc > 1 && strcmp(argv[1], "--welcome-check") == 0) { WelcomeCheck(argc > 2 ? argv[2] : NULL); return 0; }   // (postinst, first: first install or not)
        if (argc > 1 && strcmp(argv[1], "--defaults-check") == 0) { DefaultsCheck(argc > 2 ? argv[2] : NULL); return 0; }   // (postinst, after the welcome check)
        if (argc > 1 && strcmp(argv[1], "--freeze-defaults") == 0) { FreezeOldDefaults(); return 0; }   // (postinst, after the migration)
        if (argc > 1 && strcmp(argv[1], "--migrate") == 0) { Migrate(); return 0; }                      // (postinst, once: from the old separate packages)
        if (argc > 1 && strcmp(argv[1], "--after-install") == 0) { gTellSpringBoard = NO; KeepLinesDisabledAfterUpdate(); ApplyEnginesAtInstall(); return 0; }   // (postinst, every install/upgrade)
        if (argc > 1 && strcmp(argv[1], "--uninstall") == 0) { Uninstall(); return 0; }                    // (prerm, on removal only)
        // (--resume <what>: this daemon started over after a cfprefsd restart, StartOverIfPrefsDaemonRestarted -- the same start, then that work again)
        const char *resume = (argc > 2 && strcmp(argv[1], "--resume") == 0) ? argv[2] : NULL;
        if (argc > 0 && argv[0] && argv[0][0] == '/' && strlen(argv[0]) < sizeof(gSelfPath)) strcpy(gSelfPath, argv[0]);
        gPrefsDaemons = PrefsDaemonSignature();
        if (resume) ELog(@"settings: started over as a fresh process (cfprefsd %@); doing again: %s", gPrefsDaemons ?: @"?", resume);
#if DEBUG
        if (resume) { int open_fds = 0; for (int fd = 0; fd < 1024; fd++) if (fcntl(fd, F_GETFD) != -1) open_fds++; ELog(@"settings: (debug) %d file descriptors open at the fresh start", open_fds); }
#endif
        writeState(sshdLoaded());
        int t3, t4, t5;
        notify_register_dispatch("com.besiktasliseba.sshtoggle.changed", &t4, dispatch_get_main_queue(), ^(int t) { SSHRequest(-1); });
        notify_register_dispatch("com.besiktasliseba.msb.engines.apply", &t3, dispatch_get_main_queue(), ^(int t) {
            static CFAbsoluteTime last = 0; static BOOL pending = NO;
            gPendingWork |= kWorkEngines;
            Debounced(&last, &pending, ^{ @autoreleasepool { ApplyEngines(@"request"); } });
        });
        notify_register_dispatch("com.besiktasliseba.lines.apply", &t5, dispatch_get_main_queue(), ^(int t) {
            static CFAbsoluteTime last = 0; static BOOL pending = NO;
            gPendingWork |= kWorkLines;
            Debounced(&last, &pending, ^{ @autoreleasepool { ApplyLines(@"Settings"); } });
        });
        ApplyEngines(resume && strstr(resume, "engines") ? @"request" : @"daemon start");   // (waits by itself while a package transaction is running)
        if (resume && strstr(resume, "lines")) ApplyLines(@"Settings");
        if (resume && strstr(resume, "ssh")) SSHRequest(-1);
        WatchForMacStatusBarOff();
        WatchMacStatusBarConfig();
        WatchScreen();
        dispatch_main();
    }
    return 0;
}
