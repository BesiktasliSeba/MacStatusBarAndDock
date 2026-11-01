// InputDevices.h -- whether a trackpad or mouse and a hardware keyboard are attached, exactly as Settings' Pointer and Keyboard rows show them
// (macsettings/PointerSettings.x, KeyboardSettings.x), and the Ethernet row's rule that follows them (macsettings/EthernetFix.x; 1.7.5 item 3, KT
// 31 Oct): one place for both, so "our Pointer and Keyboard rows are showing" and "the Ethernet row is left out" can never disagree.
// Settings only (the pointer's state is SpringBoard's notify state; the keyboard's GraphicsServices' own answer).
#pragma once
#import <Foundation/Foundation.h>
#import <notify.h>
#import <dlfcn.h>
#import <unistd.h>

#define MSBD_POINTER_STATE "com.besiktasliseba.macpointer.device"            // (1 = a trackpad or mouse attached; SpringBoard's MacPointer bridge)
#define MSBD_POINTER_CHANGED "com.besiktasliseba.macpointer.device.changed"
#define MSBD_KEYBOARD_CHANGED "GSEventHardwareKeyboardAvailabilityChangedNotification"

// A trackpad or mouse: SpringBoard knows (the Settings app has no clean way of its own to ask) and publishes it.
static inline BOOL MSBDPointerAttached(void) {
#if DEBUG
    if (access("/tmp/msb-fakeptr", F_OK) == 0) return YES;   // (debug: as if a trackpad or mouse were attached -- the Pointer page without one)
    if (access("/tmp/msb-noptr", F_OK) == 0) return NO;      // (debug: as if none were attached -- the rows that follow one)
#endif
    static int token = 0;
    if (!token && notify_register_check(MSBD_POINTER_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t v = 0;
    if (token) notify_get_state(token, &v);
    return v == 1;
}
// A hardware keyboard: GraphicsServices' own answer.
static inline BOOL MSBDKeyboardAttached(void) {
#if DEBUG
    if (access("/tmp/msb-fakekb", F_OK) == 0) return YES;   // (debug: as if a hardware keyboard were attached)
    if (access("/tmp/msb-nokb", F_OK) == 0) return NO;      // (debug: as if none were attached)
#endif
    static BOOL (*attached)(void) = NULL; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *gs = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_LAZY);
        if (gs) attached = (BOOL (*)(void))dlsym(gs, "GSEventIsHardwareKeyboardAttached");
    });
    return attached ? attached() : NO;
}
// The Ethernet row of Settings' sidebar: listed while an adapter is connected (Apple's own answer), and without one too -- MacSettings' rule since
// 2026-09-24 -- unless both a trackpad or mouse and a keyboard are attached: then our Pointer and Keyboard rows are in the sidebar and the empty
// Ethernet row goes, to keep the sidebar short. It comes back as soon as either is detached or an adapter is connected.
static inline BOOL MSBDEthernetListed(BOOL adapter, BOOL pointer, BOOL keyboard) { return adapter || !(pointer && keyboard); }
