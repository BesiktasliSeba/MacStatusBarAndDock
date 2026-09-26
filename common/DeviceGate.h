// DeviceGate.h -- MacStatusBar&Dock is for iPad only (2026-09-25). Tweaks like TrollPad make an iPhone's UIKit report the iPad idiom, so the
// hardware model decides (hw.machine: "iPad13,1", "iPhone14,2", "iPod9,1"): on anything that is not an iPad the loaders load nothing (no Settings
// rows, no opt-in) and the root helper does nothing. Plain C, libSystem only (loader/Loader.c, sshtoggled); one sysctl per image and process, cached.
#pragma once
#include <sys/sysctl.h>
#include <string.h>
#include <stdint.h>
#include <notify.h>
#if DEBUG
#include <stdio.h>
#include <errno.h>
#endif

#if DEBUG
// Test builds only: /tmp/msb-fakemodel holding a model (e.g. iPhone14,2) makes the tweak act as on that device. The apps are sandboxed and cannot read
// /tmp, so every process that can read it (SpringBoard, Settings, the helper) passes its verdict on in this state (1 = no iPad) and the apps follow it.
#define MSBD_DEVICE_FAKE_STATE "com.besiktasliseba.macstatusbaranddock.fakemodel"
static inline int MSBDFakeModelFile(char *m, size_t size) {   // 1 read, 0 no file, -1 not readable here (sandbox)
    FILE *f = fopen("/tmp/msb-fakemodel", "r");
    if (!f) return errno == ENOENT ? 0 : -1;
    int ok = fgets(m, (int)size, f) != NULL;
    fclose(f);
    if (ok) m[strcspn(m, "\r\n ")] = 0;
    return ok && m[0] ? 1 : 0;
}
static inline uint64_t MSBDFakeModelState(void) {
    int t = 0; uint64_t v = 0;
    if (notify_register_check(MSBD_DEVICE_FAKE_STATE, &t) != NOTIFY_STATUS_OK) return 0;
    notify_get_state(t, &v);
    notify_cancel(t);
    return v;
}
#endif

// 1 on an iPad. A failed lookup counts as no iPad (it cannot fail on a real device).
static inline int MSBDIsIPad(void) {
    static int ipad = -1;
    if (ipad >= 0) return ipad;
    char m[64]; size_t n = sizeof(m) - 1;
    memset(m, 0, sizeof(m));
#if DEBUG
    int fake = MSBDFakeModelFile(m, sizeof(m));
    if (fake >= 0) {
        uint64_t no = fake && strncmp(m, "iPad", 4) != 0;
        if (MSBDFakeModelState() != no) { int t = 0; if (notify_register_check(MSBD_DEVICE_FAKE_STATE, &t) == NOTIFY_STATUS_OK) notify_set_state(t, no); }   // (token kept)
        if (fake) return ipad = !no;
    } else if (MSBDFakeModelState()) return ipad = 0;
    memset(m, 0, sizeof(m));
#endif
    if (sysctlbyname("hw.machine", m, &n, NULL, 0) != 0) return ipad = 0;
    return ipad = strncmp(m, "iPad", 4) == 0;   // ("iPhone...", "iPod...": no)
}
