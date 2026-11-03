// TailspinGuard.h -- Keep Tailspin Off (Settings > Windows & Multitasking, after Prewarm Apps; key keepTailspinOff, 1.7.9, KT 2 Nov): iPadOS's
// perfdiagsselfenabled may not turn tailspin on. Plain C with CoreFoundation: the root helper (macsettings/sshtoggled/TailspinDaemon.h: it
// applies it), Settings (MSBRootListController.m: the switch, shown where it does something) and the Settings search and Spotlight's Tweak
// Settings (common/TweakSpotlight.h MTSShownRows) run this code; Mac test tools/test-tailspinguard.sh.
//  - Why that page. Next to Prewarm Apps: the other memory switch with a 2 GB default. Not Battery > Battery Health's Battery Use group, beside
//    Sleep Guard: that page is another tweak's where one owns it (KT's iPad 2: BatteryHealthEnabler), and then none of our rows are there. The
//    helper applies the switch whatever the status bar does, so its group has no stockHides and stays under the page's note with the stock
//    status bar or MacStatusBar off.
//  - What turns tailspin on. tailspin is iPadOS's always-on performance trace: a kernel buffer (wired memory) and a sample of every thread at a
//    fixed rate. Off on customer builds, but perfdiagsselfenabled (HangTracer's "performance diagnostics self-enablement", an XPC activity run
//    about once a day) turns it on by itself: each of its clients (HangTracer, third-party HangTracer, Sentry, app launch, CA tailspin, ...)
//    picks its own days from the device's InverseDeviceID and a period, and while a client is on, every daily run applies that client's tailspin
//    configuration again -- over a `tailspin disable` made since. iPad 2 (16.7.7, 2 GB): third-party HangTracer, whose want is "Share iPad
//    Analytics + Share With App Developers, or apps using MetricKit", on for 60 h from 1 Nov 00:31 with a 37 MB buffer and a full-system sample
//    every 50 ms; turned off by hand on 1 Nov 19:50, on again at the 2 Nov 00:31 run (plans/release-1.7.9.md).
//  - Where it is stopped. Every run ends in one call that applies a tailspin configuration: the client's own while PDSEPrefAllowEnableTailspin
//    (a preference of HangTracer's, default true) allows it, else the system default -- tailspin off. The preference is read for user mobile from
//    com.apple.da, the domain perfdiagsselfenabled keeps its own clients' settings in (no context prefix: the base value, which Apple's tasking
//    could still override with its own PLTasking. prefix). So the helper keeps PDSEPrefAllowEnableTailspin = false there while the switch is on:
//    no client turns tailspin on, and the next run turns off one that is on. The clients themselves (HangTracer's hang reports) are left as
//    iPadOS runs them. Read from the binaries of 15.6.1 (HangTracer-184.3), 16.7.7 (238.1), 17.5.1 (288) and 18.5 (354.4): the same key and
//    domain in all four.
//  - Shown only where it does something: the helper records whether this iPadOS's perfdiagsselfenabled names both the key and the domain (the
//    state file below); no record, or a binary without them: the row is left out.
//  - The default: on with 2 GB of RAM (the Prewarm Apps line, common/PrewarmDefault.h -- the 37 MB are 2 % of such an iPad), off with more, and
//    off when the RAM cannot be read. Only for a key never set: a boolean stored stays, and the default is never written.
#ifndef MSBD_TAILSPIN_GUARD_H
#define MSBD_TAILSPIN_GUARD_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "PrewarmDefault.h"   // (kMSBDPrewarmLowRAMBytes, MSBDPrewarmRAM: the same 2 GB line and RAM read)

#define kMSBDTailspinKey       "keepTailspinOff"                          // (our switch, com.besiktasliseba.macstatusbar)
#define kMSBDTailspinChanged   "com.besiktasliseba.tailspin.changed"      // (Settings: the switch changed -- the helper applies it now)
#define kMSBDTailspinUpdated   "com.besiktasliseba.tailspin.updated"      // (the helper: a new state file is there)
#ifndef kMSBDTailspinStateFile   // (overridable for the Mac test)
#define kMSBDTailspinStateFile "/var/jb/var/lib/sshtoggled-engines/tailspin.plist"
#endif
#define kMSBDPDSEPath          "/usr/libexec/perfdiagsselfenabled"
#define kMSBDPDSEDomain        "com.apple.da"
#define kMSBDPDSEAllowKey      "PDSEPrefAllowEnableTailspin"
#ifndef kMSBDTailspinConfig   // (overridable for the Mac test)
#define kMSBDTailspinConfig    "/var/db/tailspin_config.plist"           // (tailspind's configuration: Enabled, EnabledModifier "<process> [<pid>]")
#endif

// The default for this much RAM (bytes; 0: unknown): 1 on (2 GB), 0 off.
static inline int MSBDTailspinOffDefault(unsigned long long ramBytes) { return ramBytes != 0 && ramBytes < kMSBDPrewarmLowRAMBytes; }
// The stored value: 1 or 0 for a boolean, -1 for none or anything else (never set).
static inline int MSBDTailspinOffStored(CFTypeRef v) { return v && CFGetTypeID(v) == CFBooleanGetTypeID() ? (CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0) : -1; }
// Keep Tailspin Off on (1) or off (0): the stored boolean, else the default for the RAM.
static inline int MSBDTailspinOffOn(int stored, unsigned long long ramBytes) { return stored >= 0 ? stored != 0 : MSBDTailspinOffDefault(ramBytes); }

// Whether perfdiagsselfenabled's binary names the key and the domain it is read from (both as whole strings): 1 yes, 0 no.
static inline int MSBDPDSESupportsBytes(const unsigned char *buf, size_t len) {
    static const char *const need[] = { kMSBDPDSEAllowKey, kMSBDPDSEDomain };
    for (size_t k = 0; k < sizeof need / sizeof need[0]; k++) {
        size_t n = strlen(need[k]) + 1;   // (with its terminator: "com.apple.da" alone, not a longer name that starts with it)
        int found = 0;
        for (size_t i = 0; !found && n <= len && i <= len - n; i++)
            if (buf[i] == (unsigned char)need[k][0] && memcmp(buf + i, need[k], n) == 0 && (i == 0 || buf[i - 1] == 0)) found = 1;
        if (!found) return 0;
    }
    return 1;
}
// ... of the file at path (at most 8 MB read; no file, or unreadable: 0).
static inline int MSBDPDSESupportsAt(const char *path) {
    FILE *f = path ? fopen(path, "rb") : NULL;
    if (!f) return 0;
    size_t cap = 8u << 20, len = 0;
    unsigned char *buf = (unsigned char *)malloc(cap);
    if (buf) len = fread(buf, 1, cap, f);
    fclose(f);
    int ok = buf && len > 0 && MSBDPDSESupportsBytes(buf, len);
    free(buf);
    return ok;
}

// Apple's preference as read: 1 true, 0 false, -1 none or not a boolean.
static inline int MSBDPDSEAllowRead(CFTypeRef v) { return v && CFGetTypeID(v) == CFBooleanGetTypeID() ? (CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0) : -1; }

// What the helper does with Apple's preference. owned: our record says the false there is ours (written by us and not changed since).
//  - the switch on, and the false not there: write it (ours from now on). A true someone stored is replaced too: the switch is the say.
//  - the switch on, the false there: nothing (someone else's false stays theirs).
//  - the switch off, or perfdiagsselfenabled not reading the key any more: our false taken away (iPadOS's default back); a value changed by
//    anyone else since is left, and no longer ours.
typedef enum { kMSBDTGLeave = 0, kMSBDTGWriteFalse = 1, kMSBDTGRemove = 2 } MSBDTGAction;
static inline MSBDTGAction MSBDTailspinDecide(int supported, int wantOff, int apple, int owned, int *ownedAfter) {
    int own = owned && apple == 0;   // (ours only while our false is still there)
    MSBDTGAction a = kMSBDTGLeave;
    if (supported && wantOff) { if (apple != 0) { a = kMSBDTGWriteFalse; own = 1; } }
    else if (own) { a = kMSBDTGRemove; own = 0; }
    if (ownedAfter) *ownedAfter = own;
    return a;
}

// Whether tailspin's configuration says it is on and was turned on by perfdiagsselfenabled (its EnabledModifier, "<process> [<pid>]"): then the
// helper turns it off at once (where the tailspin tool is there) instead of waiting for the next daily run. A configuration someone made by hand
// (the tool, a profile) is left alone.
static inline int MSBDTailspinOnBySelfEnablement(int enabled, const char *modifier) {
    return enabled == 1 && modifier && strncmp(modifier, "perfdiagsselfenabled", 20) == 0 && (modifier[20] == 0 || modifier[20] == ' ');
}

// Settings and the search: the switch is shown when the helper's state file says perfdiagsselfenabled reads the key (no file: not shown).
static inline int MSBDTailspinRowShownFrom(CFPropertyListRef state) {
    if (!state || CFGetTypeID(state) != CFDictionaryGetTypeID()) return 0;
    CFTypeRef v = CFDictionaryGetValue((CFDictionaryRef)state, CFSTR("supported"));
    return v && CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)v);
}
static inline CFPropertyListRef MSBDTailspinStateCopyAt(const char *path) {
    CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
    CFReadStreamRef s = u ? CFReadStreamCreateWithFile(NULL, u) : NULL;
    CFPropertyListRef p = NULL;
    if (s && CFReadStreamOpen(s)) { p = CFPropertyListCreateWithStream(NULL, s, 0, kCFPropertyListImmutable, NULL, NULL); CFReadStreamClose(s); }
    if (s) CFRelease(s);
    if (u) CFRelease(u);
    return p;
}
static inline int MSBDTailspinRowShownAt(const char *path) {
    CFPropertyListRef p = MSBDTailspinStateCopyAt(path);
    int shown = MSBDTailspinRowShownFrom(p);
    if (p) CFRelease(p);
    return shown;
}
static inline int MSBDTailspinRowShown(void) { return MSBDTailspinRowShownAt(kMSBDTailspinStateFile); }
#endif
