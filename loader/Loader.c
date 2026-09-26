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
#if DEBUG
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <mach/mach_time.h>
#endif

#define MSBD_PAYLOAD_DIR "/var/jb/usr/lib/MacStatusBarAndDock/"

enum { kSpringBoard = 1, kSettings = 2, kUIKit = 4, kPointerUID = 8, kRow = 16 };   // kRow: a Settings row, loaded on untested versions too
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
// MacStatusBar: everything except the Dock. The old filters: springboard / Preferences = that app only, UIKit = every process that has UIKit
// loaded (SpringBoard, Settings and the apps), pointeruid = the pointer daemon.
static const Payload kPayloads[] = {
    { "BrightnessKeyTweak", kUIKit },
    { "DockMagnificationSettings", kSettings | kRow },
    { "ForceQuitMenu", kSpringBoard },
    { "GraveEscapeTweak", kUIKit },
    { "MacAppBridge", kUIKit },
    { "MacAppSizeMenu", kSpringBoard },
    { "MacCCGrabber", kSpringBoard },
    { "MacEthernetFix", kSettings },
    { "MacFolderMenu", kSpringBoard },
    { "MacHomeBar", kUIKit },
    { "MacIconLabels", kSpringBoard },
    { "MacLargeTitles", kUIKit },
    { "MacLockStatusBar", kSpringBoard },
    { "MacPageDots", kSpringBoard },
    { "MacPointer", kPointerUID },
    { "MacSettings", kSettings },
    { "MacSettingsBadge", kSpringBoard },
    { "MacStatusBarCore", kSpringBoard },
    { "MacStatusBarSettings", kSettings | kRow },
    { "MixAudio", kUIKit },
    { "TabMuteTweak", kUIKit },
    { "VolumeGlobeTweak", kSpringBoard },
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
    // (the Bundles filter com.apple.UIKit means "UIKit is loaded", as the tweak loader checks it; RTLD_NOLOAD only looks, it never loads anything)
    void *uikit = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_LAZY | RTLD_NOLOAD);
    if (uikit) { kind |= kUIKit; dlclose(uikit); }
    if (kind == kUIKit && MSBDRecoveryApp(path)) kind = 0;   // (nothing of ours in the recovery apps)
    int noIPad = kind && !MSBDIsIPad();   // (an iPhone made to look like an iPad: nothing at all, not even the rows)
    if (noIPad) kind = 0;
#if DEBUG
    if (kind & kSpringBoard) MSBDGatePublish(MSBD_GATE_FAKE_STATE, (uint64_t)MSBDFakeMajorFile());   // (before the version is read)
#endif
    if ((kind & kSpringBoard) && MSBDGateWanted()) MSBDCrashGuardStart();   // (may switch "Enable Anyway" off, or the safe mode on)
    if (kind & kSpringBoard) MSBDGuardNoticeLoad();   // (the guard's one-time notice, also when it turned the tweak off: loader/CrashNotice.m)
    int rowsOnly = kind && !MSBDVersionAllowed((kind & kSpringBoard) != 0);   // (untested without "Enable Anyway", or the crash guard's safe mode)
    unsigned loaded = 0;
    for (size_t i = 0; i < sizeof(kPayloads) / sizeof(kPayloads[0]); i++) {
        if (!(kPayloads[i].where & kind)) continue;
        if (rowsOnly && !(kPayloads[i].where & kRow)) continue;
#if !MSBD_LINE_DOCK
        if (strcmp(kPayloads[i].name, "MixAudio") == 0 && (strstr(path, ".appex/") || MSBDStockBar())) continue;   // (and never in app extensions: widgets and keyboards would only pay for AVFoundation, audio audit F15c)
#endif
#if DEBUG
        if (MSBDSkipped(kPayloads[i].name)) continue;
#endif
        if ((kind & kSpringBoard) && MSBDCrashSkipped(kPayloads[i].name)) continue;   // (the crash guard's step 1b turned this part off, CrashStep.h)
        char lib[256];
        strlcpy(lib, MSBD_PAYLOAD_DIR, sizeof(lib));
        strlcat(lib, kPayloads[i].name, sizeof(lib));
        strlcat(lib, ".dylib", sizeof(lib));
        if (dlopen(lib, RTLD_NOW)) loaded++;
#if DEBUG
        else if (access("/tmp/msbd-loader-debug", F_OK) == 0) {
            FILE *f = fopen("/tmp/msbd-loader.log", "a");
            if (f) { fprintf(f, "%s: %s NOT loaded: %s\n", getprogname(), kPayloads[i].name, dlerror()); fclose(f); }
        }
#endif
    }
#if DEBUG
    if (access("/tmp/msbd-loader-debug", F_OK) == 0) {
        mach_timebase_info_data_t tb; mach_timebase_info(&tb);
        double us = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1000.0;
        FILE *f = fopen("/tmp/msbd-loader.log", "a");
        if (f) { fprintf(f, "%s: kind %u, iPadOS %d%s%s, %u parts loaded, %.1f us\n", getprogname(), kind, MSBDOSMajor(), rowsOnly ? (MSBDVersionTested() ? " (crash guard safe mode: rows only)" : " (untested: rows only)") : "", noIPad ? " (no iPad: nothing)" : "", loaded, us); fclose(f); }
    }
#else
    (void)loaded; (void)noIPad;
#endif
}
