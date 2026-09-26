// VersionGate.h -- the iPadOS versions MacStatusBar&Dock is tested on: 15.x and 16.x (2026-09-25). On any other version the loaders load no part
// (only the two Settings rows, so the pages and their "Enable Anyway" switch stay reachable) unless that switch is on. On 15/16 the same "rows
// only" state is the crash guard's safe mode (crashSafeMode, CrashGuard.h), switched back on from either page.
// Plain C (used by loader/Loader.c too). CoreFoundation is looked up at run time, so the loaders still link nothing but libSystem; outside
// SpringBoard it costs one sysctl and one notify state read.
#pragma once
#include <sys/sysctl.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <notify.h>
#if DEBUG
#include <stdio.h>
#endif

#define MSBD_GATE_DOMAIN "com.besiktasliseba.macstatusbaranddock"
#define MSBD_GATE_KEY "enableOnUntestedVersion"
#define MSBD_SAFE_KEY "crashSafeMode"   // (15/16: set by the crash guard after SpringBoard crashed twice; "Turn Back On" clears it)
#define MSBD_GATE_STATE "com.besiktasliseba.macstatusbaranddock.untested"   // SpringBoard's decision at its start: 1 off, 2 on (the others follow it)
#if DEBUG
// Test builds only: /tmp/msb-fakeversion holding a major number (e.g. 17) makes the tweak act as on that version. Sandboxed processes cannot read
// /tmp, so SpringBoard's loader passes the number on in this state.
#define MSBD_GATE_FAKE_STATE "com.besiktasliseba.macstatusbaranddock.fakeversion"
static inline int MSBDFakeMajorFile(void) {
    FILE *f = fopen("/tmp/msb-fakeversion", "r");
    int m = 0;
    if (f) { if (fscanf(f, "%d", &m) != 1) m = 0; fclose(f); }
    return m > 0 ? m : 0;
}
#endif

static inline uint64_t MSBDGateReadState(const char *name) {
    int t = 0; uint64_t v = 0;
    if (notify_register_check(name, &t) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(t, &v);
    notify_cancel(t);
    return v;
}
static inline void MSBDGatePublish(const char *name, uint64_t v) {   // (the token is kept, so the state lives as long as SpringBoard)
    int t = 0;
    if (notify_register_check(name, &t) == NOTIFY_STATUS_OK) notify_set_state(t, v);
}

// The major version (15, 16, ...), 0 if unknown.
static inline int MSBDOSMajor(void) {
    static int major = -1;
    if (major >= 0) return major;
#if DEBUG
    int fake = MSBDFakeMajorFile();
    if (!fake) fake = (int)MSBDGateReadState(MSBD_GATE_FAKE_STATE);
    if (fake) return major = fake;
#endif
    char v[32]; size_t n = sizeof(v) - 1;
    memset(v, 0, sizeof(v));
    if (sysctlbyname("kern.osproductversion", v, &n, NULL, 0) == 0 && atoi(v) > 0) return major = atoi(v);
    n = sizeof(v) - 1; memset(v, 0, sizeof(v));
    if (sysctlbyname("kern.osrelease", v, &n, NULL, 0) == 0 && atoi(v) > 6) return major = atoi(v) - 6;   // (Darwin 21 = iPadOS 15)
    return major = 0;
}
// Unknown counts as tested: never turn off what ran before because of a failed lookup.
static inline int MSBDVersionTested(void) { int m = MSBDOSMajor(); return m == 0 || m == 15 || m == 16; }

// A boolean of ours (CFPreferences, looked up at run time): "Enable Anyway", or the safe mode.
static inline int MSBDGatePrefOn(const char *keyName) {
    void *cf = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY | RTLD_NOLOAD);
    if (!cf) return 0;
    const void *(*mk)(const void *, const char *, unsigned int) = (const void *(*)(const void *, const char *, unsigned int))dlsym(cf, "CFStringCreateWithCString");
    const void *(*copy)(const void *, const void *, const void *, const void *) = (const void *(*)(const void *, const void *, const void *, const void *))dlsym(cf, "CFPreferencesCopyValue");
    void (*rel)(const void *) = (void (*)(const void *))dlsym(cf, "CFRelease");
    const void **user = (const void **)dlsym(cf, "kCFPreferencesCurrentUser"), **host = (const void **)dlsym(cf, "kCFPreferencesAnyHost"), **yes = (const void **)dlsym(cf, "kCFBooleanTrue");
    int on = 0;
    if (mk && copy && rel && user && host && yes) {
        const void *key = mk(NULL, keyName, 0x08000100), *domain = mk(NULL, MSBD_GATE_DOMAIN, 0x08000100);   // (kCFStringEncodingUTF8)
        const void *v = key && domain ? copy(key, domain, *user, *host) : NULL;
        on = v && v == *yes;
        if (v) rel(v);
        if (key) rel(key);
        if (domain) rel(domain);
    }
    dlclose(cf);
    return on;
}

static inline int MSBDUntestedOptIn(void) { return MSBDGatePrefOn(MSBD_GATE_KEY); }
static inline int MSBDSafeMode(void) { return MSBDGatePrefOn(MSBD_SAFE_KEY); }
// The switch that decides: untested version -> "Enable Anyway" on; 15/16 -> not in the crash guard's safe mode.
static inline int MSBDGateWanted(void) { return MSBDVersionTested() ? !MSBDSafeMode() : MSBDUntestedOptIn(); }

// May the parts run in this process? SpringBoard reads the switch and publishes its decision; every other process follows SpringBoard (so a switch
// changed without a respring never splits them), or reads the switch itself when SpringBoard has not decided yet.
static inline int MSBDVersionAllowed(int springboard) {
    if (springboard) {
        int on = MSBDGateWanted();
        MSBDGatePublish(MSBD_GATE_STATE, on ? 2 : 1);
        return on;
    }
    uint64_t s = MSBDGateReadState(MSBD_GATE_STATE);
    return s ? s == 2 : MSBDGateWanted();
}
