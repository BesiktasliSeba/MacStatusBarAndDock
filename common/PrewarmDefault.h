// PrewarmDefault.h -- Prewarm Apps' default (Settings > Windows & Multitasking, key prewarmApps, 1.7.5 item 6): OFF on an iPad with 2 GB of RAM,
// ON with more (1.7.7, KT). One rule for both sides: SpringBoard (StatusBar.x DMLoadPrefs: while it is off, the quit set's file says "refuseAll"
// and dasd refuses every prewarm) and Settings (MSBRootListController.m: the switch shows the same). Plain C with CoreFoundation; Mac test
// tools/test-prewarmdefault.sh.
//  - Why by RAM. On the 2 GB iPad Pro 9.7" dasd kept up to ~40 prewarmed apps at once that nobody opened (~50 MB) while iOS killed daemons below
//    them for memory, and a prewarm saved 40-90 ms on the first open of an app it guessed right; on 4 GB and more the prewarmed apps are a
//    rounding error (plans/release-1.7.5.md, item 6).
//  - Only for a key never set: a boolean anyone stored stays, on or off, and the default is never written (only a tap on the switch stores a
//    value). A value that is no boolean counts as never set, as SpringBoard has read it since 1.7.5.
//  - The line, 2.5e9 bytes of hw.memsize. iPadOS reports a little less than the RAM fitted (the 4 GB iPad Pro 10.5"/12.9" 2nd generation:
//    4166696960, 97 % of 4 GiB), so a 2 GB iPad (iPad Air 2, iPad mini 4, iPad Pro 9.7", iPad 5th and 6th generation) reports at most 2 GiB
//    (2.15e9) and a 3 GB one (iPad 7th to 9th generation, iPad Air 3, iPad mini 5) about 3.1e9: room on both sides of the line. RAM that cannot
//    be read (0): on, the default before 1.7.7.
#ifndef MSBD_PREWARM_DEFAULT_H
#define MSBD_PREWARM_DEFAULT_H
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <sys/sysctl.h>

#define kMSBDPrewarmLowRAMBytes 2500000000ULL
#ifndef MSBD_PREWARM_FAKE_RAM   // (overridable for the Mac test)
#define MSBD_PREWARM_FAKE_RAM "/tmp/msb-fakeram"
#endif

// The default for this much RAM (bytes; 0: unknown): 0 off (2 GB), 1 on.
static inline int MSBDPrewarmAppsDefault(unsigned long long ramBytes) { return ramBytes == 0 || ramBytes >= kMSBDPrewarmLowRAMBytes; }
// The stored value as both sides read it: 1 or 0 for a boolean, -1 for none or anything else (never set).
static inline int MSBDPrewarmAppsStored(CFTypeRef v) { return v && CFGetTypeID(v) == CFBooleanGetTypeID() ? (CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0) : -1; }
// Prewarm Apps on (1) or off (0): the stored boolean, else the default for the RAM.
static inline int MSBDPrewarmAppsOn(int stored, unsigned long long ramBytes) { return stored >= 0 ? stored != 0 : MSBDPrewarmAppsDefault(ramBytes); }
// This iPad's RAM (hw.memsize, as SystemStats.h reads it), 0 when it cannot be read. Debug builds: MSBD_PREWARM_FAKE_RAM holding a number of
// GiB ("2") stands in for it -- read by SpringBoard and Settings alike, so the 2 GB default can be tried on a larger iPad.
static inline unsigned long long MSBDPrewarmRAM(void) {
#if DEBUG
    FILE *f = fopen(MSBD_PREWARM_FAKE_RAM, "r");
    double gib = 0;
    if (f) { if (fscanf(f, "%lf", &gib) != 1) gib = 0; fclose(f); }
    if (gib > 0) return (unsigned long long)(gib * 1073741824.0);
#endif
    unsigned long long bytes = 0; size_t len = sizeof bytes;
    return sysctlbyname("hw.memsize", &bytes, &len, NULL, 0) == 0 ? bytes : 0;
}
#endif
