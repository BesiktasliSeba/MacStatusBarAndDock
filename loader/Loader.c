// Loader.c -- the two libraries Choicy and iCleaner Pro show for MacStatusBar&Dock: MacStatusBar.dylib and MacDock.dylib (built from this one file,
// MSBD_LINE_DOCK picks the table). Each is only a small loader: it looks at which process it is in and loads the parts ("payloads", in
// /var/jb/usr/lib/MacStatusBarAndDock) that belong there -- exactly the processes each part was loaded into when it was a tweak of its own (the same
// filters), in the same alphabetical order the tweak loader used. Switching a line off in Choicy or iCleaner Pro stops its loader, and with it every
// part behind it.
//
// Cost in a process where no part applies: one executable-path read and a few string compares (no Objective-C, no allocation) -- microseconds.
// On an iPadOS version other than 15/16 only the Settings rows load, unless "Enable Anyway" is on (common/VersionGate.h); on 15/16 the same after
// the crash guard switched its safe mode on. Whenever the parts are meant to run, SpringBoard's loader runs the crash guard first
// (common/CrashGuard.h). On anything that is not an iPad nothing loads at all (common/DeviceGate.h).
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <mach-o/dyld.h>
#include <notify.h>
#include "../common/VersionGate.h"
#include "../common/CrashGuard.h"
#include "../common/DeviceGate.h"
#include "../common/PrewarmQuitSet.h"   // (only its path in C: the prewarm block's quit set, below)
#include "../common/BundledPath.h"      // (MSBDBundledProcess / MSBDAppExtension: which processes get the app-side parts, Mac-tested)
#include "../common/MacPointerStatus.h"   // (1.8.8.2, GitHub #17: in pointeruid, the word that MacPointer is not loaded there, and why)
#include <os/log.h>
#include <unistd.h>
#if MSBD_PERFPROBE
#include <unistd.h>
#endif
#if DEBUG
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <mach/mach_time.h>
#endif

#define MSBD_PAYLOAD_DIR "/var/jb/usr/lib/MacStatusBarAndDock/"

enum { kSpringBoard = 1, kSettings = 2, kUIKit = 4, kPointerUID = 8, kRow = 16, kSpotlight = 32, kDasd = 64, kPopupGuard = 128 };   // kRow: a Settings row, loaded on untested versions too
                                                                                                    // kSpotlight: the Spotlight app (com.apple.Spotlight) only; kDasd: the Duet Activity Scheduler (prewarm) only
                                                                                                    // kPopupGuard: a recovery app that contains LNPopupController (Sileo, Zebra): the popup guard only
typedef struct { const char *name; unsigned where; } Payload;

#if MSBD_LINE_DOCK
// MacDock: the Dock (SpringBoard) and its Settings row. The Status Bar row is loaded here too (and the Dock row by MacStatusBar), so either line
// switched off still leaves the other's page -- with its on/off switch -- in Settings.
static const Payload kPayloads[] = {
    { "DockMagnification", kSpringBoard },
    { "DockMagnificationSettings", kSettings | kRow },
    { "MacStatusBarSettings", kSettings | kRow },
};
#else
// MacStatusBar: everything except the Dock. The old filters: springboard / Preferences = that app only, UIKit = every bundled process that has UIKit
// loaded (SpringBoard, Settings, the apps, their extensions and XPC services; not the bare daemons that merely link it, below), pointeruid = the
// pointer daemon.
static const Payload kPayloads[] = {
    { "BrightnessKeyTweak", kUIKit },
    { "DockMagnificationSettings", kSettings | kRow },
    { "ForceQuitMenu", kSpringBoard },
    { "GraveEscapeTweak", kUIKit },
    { "MacAddToFolder", kSpringBoard },
    { "MacAppBridge", kUIKit },
    { "MacAppSizeMenu", kSpringBoard },
    { "MacCCGrabber", kSpringBoard },
    { "MacEthernetFix", kSettings },
    { "MacFolderMenu", kSpringBoard },
    { "MacHomeBar", kSpringBoard },   // (SpringBoard's home pill only: its %ctor returns at once anywhere else)
    { "MacIconLabels", kSpringBoard },
    { "MacLargeTitles", kUIKit },
    { "MacLockScreen", kSpringBoard },   // (1.8.9 F49: off by default; with its switch off its %ctor installs no hook)
    { "MacLockStatusBar", kSpringBoard },
    { "MacPageDots", kSpringBoard },
    { "MacPointer", kPointerUID },
    { "MacPopupGuard", kPopupGuard },   // (1.8.8.1 B68: only there; every other app has the same guard in MacAppBridge)
    { "MacSettings", kSettings },
    { "MacSettingsBadge", kSpringBoard },
    { "MacSpotlight", kSpotlight },
    { "MacStatusBarCore", kSpringBoard },
    { "MacStatusBarSettings", kSettings | kRow },
    { "MixAudio", kUIKit },
    { "TabMuteTweak", kUIKit },
    { "VolumeGlobeTweak", kSpringBoard },
    { "PrewarmBlockTweak", kDasd },
};
#endif

#if !MSBD_LINE_DOCK
// "Use Stock Status Bar" (SpringBoard publishes it before any app starts, statusbar/StockBar.h): audio mixing is iPadOS's own then, so MixAudio is
// not loaded. Asked only when MixAudio is next in line (one notify lookup).
static int MSBDStockBar(void) {
    int token = 0; uint64_t state = 0;
    if (notify_register_check("com.besiktasliseba.macstatusbar.stock", &token) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(token, &state);
    notify_cancel(token);
    return state == 1;
}
#endif
#if DEBUG
// Test builds only: /tmp/msbd-loader-skip lists part names (one per line) that are not loaded -- for finding which part causes something.
static int MSBDSkipped(const char *name) {
    FILE *f = fopen("/tmp/msbd-loader-skip", "r");
    if (!f) return 0;
    char line[128]; int hit = 0;
    while (!hit && fgets(line, sizeof(line), f)) { line[strcspn(line, "\r\n ")] = 0; hit = strcmp(line, name) == 0; }
    fclose(f);
    return hit;
}
#endif
static int EndsWith(const char *s, const char *suffix) {
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}
// The apps a user needs to get out of trouble -- package managers, the jailbreak and TrollStore apps, the tweak switches, the file manager -- never
// get our app-side parts: if one of them ever crashed every app (an iPadOS point release nobody tested), these still open, so the tweak can be
// removed or switched off. (Choicy is a Settings page, not an app.)
static int MSBDRecoveryApp(const char *path) {
    static const char *apps[] = { "/Sileo.app/", "/Sileo-Nightly.app/", "/Sileo-Beta.app/", "/Zebra.app/", "/Saily.app/", "/chromatic.app/", "/Cydia.app/",
        "/Installer.app/", "/Filza.app/", "/iCleaner.app/", "/TrollStore.app/", "/Dopamine.app/", "/palera1nLoader.app/" };
    for (size_t i = 0; i < sizeof(apps) / sizeof(apps[0]); i++) if (strstr(path, apps[i])) return 1;
    return 0;
}
#if !MSBD_LINE_DOCK
// The one exception (1.8.8.1 B68): a recovery app built on the LNPopupController library -- Sileo, Zebra -- gets the library's race guard alone
// (MacPopupGuard, common/PopupGuard.h), so its queue still opens in a window: without it the queue bar ended up hidden while the app believed it was
// shown, and a Queue tap opened an invisible popup over a dimmed window. Nothing else of ours goes there; on an untested iPadOS or in the crash
// guard's safe mode not even that (rows only). The library is looked for in the app's own classes (the runtime's list, read by name: no UIKit
// code runs and no class is initialized; the loader links no Objective-C itself).
static int MSBDHasPopupLibrary(void) {
    void *(*getClass)(const char *) = (void *(*)(const char *))dlsym(RTLD_DEFAULT, "objc_getClass");
    return getClass && getClass("LNPopupBar") != NULL;
}
#endif
// What a process gets once it is known to be a recovery app: an app (the app-side parts) gets nothing, or with the library (askLibrary says
// whether that is looked for) the guard alone; any other kind of process is not changed. The library is looked for only in a recovery app.
static unsigned MSBDRecoveryKind(unsigned kind, int recoveryApp, int (*askLibrary)(void)) {
    if ((kind & ~kSpotlight) != kUIKit || !recoveryApp) return kind;
    return askLibrary && askLibrary() ? kPopupGuard : 0;
}

#if !MSBD_LINE_DOCK
// pointeruid (1.8.8.2, GitHub #17): when the Mac pointer's part is not loaded there, Settings > Pointer and Report a Problem say why: held back by
// the version gate or the crash guard (rows only), or its file did not open. MacPointer says its own word once it loads (common/MacPointerStatus.h);
// nothing at all from this process means our loader is not in it. The token is kept: the word lives as long as this pointeruid.
static void MSBDPointerProcessWord(unsigned verdict) {
    static int token = 0;
    if (!token && notify_register_check(MSBD_MP_STATUS, &token) != NOTIFY_STATUS_OK) { token = 0; return; }
    notify_set_state(token, MSBDMPPack((uint32_t)getpid(), verdict, 0, 0, 0));
    notify_post(MSBD_MP_STATUS);
}
#endif

__attribute__((constructor)) static void MSBDLoad(void) {
#if DEBUG
    uint64_t t0 = mach_absolute_time();
#endif
    char path[1024]; uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return;
    unsigned kind = 0;
    if (EndsWith(path, "/SpringBoard.app/SpringBoard")) kind = kSpringBoard;
    else if (EndsWith(path, "/Preferences.app/Preferences")) kind = kSettings;
    else if (EndsWith(path, "/pointeruid")) kind = kPointerUID;
    else if (EndsWith(path, "/Spotlight.app/Spotlight")) kind = kSpotlight;   // (and kUIKit below: the app-side parts load there as before)
    else if (EndsWith(path, "/dasd")) kind = kDasd;   // (the prewarm block: /usr/libexec/dasd, no UIKit)
    // (the Bundles filter com.apple.UIKit means "UIKit is loaded", as the tweak loader checks it; RTLD_NOLOAD only looks, it never loads anything)
    // The app-side parts are for processes inside a bundle (common/BundledPath.h): apps and SpringBoard (.app), app extensions (.appex) and XPC
    // services (.xpc: WebKit's GPU process plays Safari's web audio, which MixAudio's session rule makes mixable). Many daemons link UIKit without
    // ever starting an app (runningboardd, mediaserverd, locationd, CommCenter, a DriverKit HID driver, ...: 50 of the 59 processes with these
    // parts on the M1, 15.6.1) and paid ~0.8-1 MB each for parts that never run there (UniversalControl on the 17.5: 6.9 -> 5.9-6.1 MB; memory
    // audit, 1 Nov 2026).
    void *uikit = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_LAZY | RTLD_NOLOAD);
    if (uikit) { if (MSBDBundledProcess(path)) kind |= kUIKit; dlclose(uikit); }
#if !MSBD_LINE_DOCK
    if ((kind & ~kSpotlight) == kUIKit) kind = MSBDRecoveryKind(kind, MSBDRecoveryApp(path), MSBDHasPopupLibrary);   // (nothing of ours in the recovery apps but that guard)
#else
    if ((kind & ~kSpotlight) == kUIKit) kind = MSBDRecoveryKind(kind, MSBDRecoveryApp(path), NULL);   // (nothing of ours in the recovery apps)
#endif
    int noIPad = kind && !MSBDIsIPad();   // (an iPhone made to look like an iPad: nothing at all, not even the rows)
    if (noIPad) kind = 0;
#if DEBUG
    if (kind & kSpringBoard) MSBDGatePublish(MSBD_GATE_FAKE_STATE, (uint64_t)MSBDFakeMajorFile());   // (before the version is read)
#endif
    if ((kind & kSpringBoard) && MSBDGateWanted()) MSBDCrashGuardStart();   // (may switch "Enable Anyway" off, or the safe mode on)
    if (kind & kSpringBoard) MSBDGuardNoticeLoad();   // (the guard's one-time notice, also when it turned the tweak off: loader/CrashNotice.m)
    int rowsOnly = kind && !MSBDVersionAllowed((kind & kSpringBoard) != 0);   // (untested without "Enable Anyway", or the crash guard's safe mode)
    unsigned loaded = 0;
    int coreLoaded = 0;   // (MacStatusBarCore in SpringBoard: the part that keeps the prewarm quit set)
    for (size_t i = 0; i < sizeof(kPayloads) / sizeof(kPayloads[0]); i++) {
        if (!(kPayloads[i].where & kind)) continue;
        if (rowsOnly && !(kPayloads[i].where & kRow)) continue;
#if !MSBD_LINE_DOCK
        if (strcmp(kPayloads[i].name, "MixAudio") == 0 && (MSBDAppExtension(path) || MSBDStockBar())) continue;   // (and never in app extensions: widgets and keyboards would only pay for AVFoundation, audio audit F15c)
#endif
#if DEBUG
        if (MSBDSkipped(kPayloads[i].name)) continue;
#endif
        if ((kind & kSpringBoard) && MSBDCrashSkipped(kPayloads[i].name)) continue;   // (the crash guard's step 1b turned this part off, CrashStep.h)
        char lib[256];
        strlcpy(lib, MSBD_PAYLOAD_DIR, sizeof(lib));
        strlcat(lib, kPayloads[i].name, sizeof(lib));
        strlcat(lib, ".dylib", sizeof(lib));
        if (dlopen(lib, RTLD_NOW)) { loaded++; if (strcmp(kPayloads[i].name, "MacStatusBarCore") == 0) coreLoaded = 1; }
        else {
            // (1.8.8.2: in release builds too, one line in the system log: a part that does not open on a user's jailbreak is no longer silent)
            const char *why = dlerror();
            os_log_error(OS_LOG_DEFAULT, "MacStatusBar&Dock: %{public}s did not load: %{public}s", kPayloads[i].name, why ? why : "?");
#if !MSBD_LINE_DOCK
            if (kind & kPointerUID) MSBDPointerProcessWord(MSBD_MP_V_LOADFAIL);   // (MacPointer, the only part there)
#endif
#if DEBUG
            if (access("/tmp/msbd-loader-debug", F_OK) == 0) {
                FILE *f = fopen("/tmp/msbd-loader.log", "a");
                if (f) { fprintf(f, "%s: %s NOT loaded: %s\n", getprogname(), kPayloads[i].name, why ? why : "?"); fclose(f); }
            }
#endif
        }
    }
#if !MSBD_LINE_DOCK
    if ((kind & kPointerUID) && rowsOnly) MSBDPointerProcessWord(MSBD_MP_V_HELD);   // (untested iPadOS without Enable Anyway, or the crash guard's safe mode)
#endif
#if MSBD_PERFPROBE
    // (the smoothness audit's frame/stall probe, loader/PerfProbe.m, debug builds and measurement builds: only while /tmp/msb-perfprobe exists,
    // in SpringBoard and UIKit apps, also when every part is skipped -- so a measurement with and without our parts uses the same probe)
    if ((kind & (kSpringBoard | kUIKit)) && access("/tmp/msb-perfprobe", F_OK) == 0) dlopen(MSBD_PAYLOAD_DIR "MacPerfProbe.dylib", RTLD_NOW);
#endif
    int quitSetGone = 0;
#if !MSBD_LINE_DOCK
    // The prewarm block (dasd) refuses the apps in the quit set's file, and the status bar part keeps that file (StatusBar.x, common/PrewarmQuitSet.h).
    // A SpringBoard without that part -- the crash guard's safe mode or step 1b, an untested iPadOS without Enable Anyway -- keeps no set: the file
    // goes, and dasd (which looks at it at every prewarm) refuses nothing until the part runs again and writes it from the set it kept.
    if ((kind & kSpringBoard) && !coreLoaded) quitSetGone = unlink(kMSBDPrewarmQuitSetFile) == 0;
#else
    (void)coreLoaded;
#endif
#if DEBUG
    if (access("/tmp/msbd-loader-debug", F_OK) == 0) {
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        double us = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1000.0;
        FILE *f = fopen("/tmp/msbd-loader.log", "a");
        if (f) { fprintf(f, "%s: kind %u, iPadOS %d%s%s, %u parts loaded%s, %.1f us\n", getprogname(), kind, MSBDOSMajor(), rowsOnly ? (MSBDVersionTested() ? " (crash guard safe mode: rows only)" : " (untested: rows only)") : "", noIPad ? " (no iPad: nothing)" : "", loaded, quitSetGone ? " (no status bar part: the prewarm quit set's file removed)" : "", us); fclose(f); }
    }
#else
    (void)loaded; (void)noIPad; (void)quitSetGone;
#endif
}
