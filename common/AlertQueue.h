// AlertQueue.h -- one rule for every alert of ours in SpringBoard (layering audit F7, 2026-09-26).
// Our alerts (engine warnings and "Respring to Finish Switching Engines" in the status bar part, the welcome, the crash guard's notice in the
// loader, "MacStatusBar Is Off" in the Dock part) each sit on a window of their own above everything, the Lock Screen included. Two rules:
//  - one at a time: every alert window is marked (MSBD_ALERT_ID), and an alert waits while another marked window is up. The parts are separate
//    libraries, so the shared state is SpringBoard's own window list, not a variable.
//  - never over the Lock Screen: an alert is not shown while locked, and one that is up closes as soon as the iPad locks, the screen goes off or
//    the Cover Sheet (Lock Screen / Notification Center) comes down; the caller decides whether it comes back after the unlock.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <notify.h>

#define MSBD_ALERT_ID @"MSBDAlertWindow"

static inline NSArray<UIWindow *> *MSBDAlertAllWindows(void) {
    SEL allSel = NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:");   // (UIKit's private list: every window of the process)
    if ([UIWindow respondsToSelector:allSel]) return ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class], allSel, YES, NO);
    NSMutableArray *all = [NSMutableArray array];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) if ([sc isKindOfClass:[UIWindowScene class]]) [all addObjectsFromArray:((UIWindowScene *)sc).windows];
    return all;
}
// Is an alert of ours on screen (from any of our libraries)? `except`: the caller's own window, not counted.
static inline BOOL MSBDAlertBusy(UIWindow *except) {
    for (UIWindow *w in MSBDAlertAllWindows())
        if (w != except && !w.hidden && [w.accessibilityIdentifier isEqualToString:MSBD_ALERT_ID]) return YES;
    return NO;
}
static inline BOOL MSBDAlertCallBool(id obj, NSString *name) {
    SEL s = NSSelectorFromString(name);
    return obj && [obj respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(obj, s);
}
static inline id MSBDAlertShared(const char *cls) {
    Class c = objc_getClass(cls);
    SEL s = NSSelectorFromString(@"sharedInstance");
    return c && [c respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)((id)c, s) : nil;
}
// Locked, screen off, or the Cover Sheet (Lock Screen / Notification Center) showing.
static inline BOOL MSBDAlertLockedOrCovered(void) {
    static int lockToken = 0, blankToken = 0;
    if (!lockToken) notify_register_check("com.apple.springboard.lockstate", &lockToken);
    if (!blankToken) notify_register_check("com.apple.springboard.hasBlankedScreen", &blankToken);
    uint64_t locked = 0, blank = 0;
    if (lockToken) notify_get_state(lockToken, &locked);
    if (blankToken) notify_get_state(blankToken, &blank);
    if (blank) return YES;
    // com.apple.springboard.lockstate stays 1 after a respring with "Skip Lock Screen After Respring" (the passcode has not been entered since, but
    // the Home Screen is up and usable): taken as "locked", the engine warning and the "Respring to Finish Switching Engines" question never showed
    // after a respring until a lock and unlock (iPad 2, 26 Sep). SpringBoard's own UI lock state decides when it is available; the raw lock state
    // only when it is not.
    id lm = MSBDAlertShared("SBLockScreenManager");
    if (lm && [lm respondsToSelector:NSSelectorFromString(@"isUILocked")]) { if (MSBDAlertCallBool(lm, @"isUILocked")) return YES; }
    else if (locked) return YES;
    id cs = MSBDAlertShared("SBCoverSheetPresentationManager");
    return MSBDAlertCallBool(cs, @"isVisible") || MSBDAlertCallBool(cs, @"isPresented");
}
// SpringBoard's window scene on the iPad's own screen. With an external display (iPadOS 16: TrollPad's extended display or Stage Manager) SpringBoard
// also has scenes on the TV, and "the first window scene" could be one of those: an alert (or another window of ours) then opened on the TV, or on
// a TV scene nobody looks at. The first window scene on the main screen is taken; without an external display every scene is on the main screen,
// so this is the same scene as before. Falls back to the first window scene of any screen.
static inline UIWindowScene *MSBDMainWindowScene(void) {
    UIWindowScene *first = nil;
    UIScreen *main = [UIScreen mainScreen];
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        if (!first) first = (UIWindowScene *)sc;
        UIScreen *s = nil;
        @try { s = ((UIWindowScene *)sc).screen; } @catch (id e) {}
        if (!s || s == main) return (UIWindowScene *)sc;
    }
    return first;
}
// A marked alert window at `level`, shown (empty: the caller presents its UIAlertController on the root view controller). On the iPad's own screen.
static inline UIWindow *MSBDMakeAlertWindow(CGFloat level) {
    UIWindowScene *scene = MSBDMainWindowScene();
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    w.accessibilityIdentifier = MSBD_ALERT_ID;
    w.windowLevel = level;
    w.backgroundColor = [UIColor clearColor];
    w.rootViewController = [UIViewController new];
    w.hidden = NO;
    return w;
}
// Watches a shown alert window (twice a second, only while it is up): when the iPad locks, the screen goes off or the Cover Sheet comes down, the
// alert is put away without animation and its window hidden, and `closed` runs (the caller clears its own reference and decides about showing it
// again after the unlock). Nothing runs once the window is hidden or gone by other means (a button).
static inline void MSBDAlertCloseOnLock(UIWindow *window, void (^closed)(void)) {
    __weak UIWindow *weakW = window;
    __block void (^check)(void);
    void (^body)(void) = ^{
        UIWindow *w = weakW;
        if (!w || w.hidden) { check = nil; return; }
        if (MSBDAlertLockedOrCovered()) {
            UIViewController *root = w.rootViewController;
            if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:nil];
            w.hidden = YES;
            check = nil;
            if (closed) closed();
            return;
        }
        void (^again)(void) = check;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), again);
    };
    check = body;
    dispatch_async(dispatch_get_main_queue(), body);
}
