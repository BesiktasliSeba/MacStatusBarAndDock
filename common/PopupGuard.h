// PopupGuard.h -- the LNPopupController race guard (M1 pipeline 24 Sep 2026, Sileo "queue gets stuck in a window"; 1.8.8.1 B68, Zebra's queue).
// Apps built on the LNPopupController library (Sileo, Zebra and others) show their queue as a popup bar. When a window changes size quickly
// (full screen -> window goes through a short in-between size; a fast resize does the same), or the queue changes quickly, the app asks the library
// to dismiss the bar and, before that animation is over, to present it again. The library does not handle the overlap: the late "dismiss finished"
// step hides the bar AFTER it was presented again, so the app believes the bar is up while it is hidden, and the next Queue tap opens an invisible
// popup over a dimmed window (stuck). Fix: present/dismiss calls on one controller are run one at a time; a call that arrives while the other one
// is still animating waits for it, and only the latest request runs. Every completion block the app passed is still called exactly once. A 2 s
// safety net runs the waiting call if a completion never comes.
// Which present is taken (1.8.8.1): the library's designated one, presentPopupBarWithContentViewController:openPopup:animated:completion:, which
// its 3-argument present only forwards to -- Zebra calls the designated one itself, Sileo the 3-argument one, so a guard on the 3-argument one
// (1.8.8 and before) never saw Zebra's presents. An older copy of the library without the designated one: its 3-argument present. Each only with
// the argument types it is known by (anything else is left alone). Objective-C runtime only (no UIKit): the includer brings MSHookMessageEx.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// A method's argument types, the frame offsets left out, as the library declares them ("v@:@BB@?"); BOOL reads as 'B' on arm64, 'c' on x86_64.
static inline BOOL MSBDPopupTypesAre(const char *types, const char *want) {
    if (!types || !want) return NO;
    for (; *types; types++) {
        if (*types >= '0' && *types <= '9') continue;
        char c = *types == 'c' ? 'B' : *types;
        if (c != *want) return NO;
        want++;
    }
    return *want == 0;
}
// The present the guard takes on that class: 4 (the designated one), 3 (an older copy's), or 0 (none it knows: no guard).
static inline int MSBDPopupPresentArgs(Class c) {
    Method m = class_getInstanceMethod(c, sel_registerName("presentPopupBarWithContentViewController:openPopup:animated:completion:"));
    if (m && MSBDPopupTypesAre(method_getTypeEncoding(m), "v@:@BB@?")) return 4;
    m = class_getInstanceMethod(c, sel_registerName("presentPopupBarWithContentViewController:animated:completion:"));
    if (m && MSBDPopupTypesAre(method_getTypeEncoding(m), "v@:@B@?")) return 3;
    return 0;
}
static inline BOOL MSBDPopupDismissKnown(Class c) {
    Method m = class_getInstanceMethod(c, sel_registerName("dismissPopupBarAnimated:completion:"));
    return m && MSBDPopupTypesAre(method_getTypeEncoding(m), "v@:B@?");
}

static char kMSBDPopupBusy, kMSBDPopupPending, kMSBDPopupPendingCompletion;
static int gMSBDPopupArgs;   // (the present taken: 4 or 3)
static SEL gMSBDPopupPresentSel, gMSBDPopupDismissSel;
static void (*oMSBDPresentBar4)(id, SEL, id, BOOL, BOOL, id);
static void (*oMSBDPresentBar3)(id, SEL, id, BOOL, id);
static void (*oMSBDDismissBar)(id, SEL, BOOL, id);
static void MSBDPopupRun(id vc, int op, id content, BOOL open, BOOL animated, void (^completion)(void));
static void MSBDPopupFinished(id vc, NSNumber *token) {
    if (![objc_getAssociatedObject(vc, &kMSBDPopupBusy) isEqual:token]) return;   // already finished (completion or safety net)
    objc_setAssociatedObject(vc, &kMSBDPopupBusy, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    void (^next)(void) = objc_getAssociatedObject(vc, &kMSBDPopupPending);
    objc_setAssociatedObject(vc, &kMSBDPopupPending, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (next) next();
}
static void MSBDPopupRun(id vc, int op, id content, BOOL open, BOOL animated, void (^completion)(void)) {
    if (objc_getAssociatedObject(vc, &kMSBDPopupBusy)) {   // one is still animating: remember only the latest request (its completion, and any replaced request's completion, run after it)
        void (^oldCompletion)(void) = objc_getAssociatedObject(vc, &kMSBDPopupPendingCompletion);
        void (^merged)(void) = ^{ if (oldCompletion) oldCompletion(); if (completion) completion(); };
        objc_setAssociatedObject(vc, &kMSBDPopupPendingCompletion, merged, OBJC_ASSOCIATION_COPY_NONATOMIC);
        __weak id weakVC = vc;
        objc_setAssociatedObject(vc, &kMSBDPopupPending, ^{
            id strong = weakVC; if (!strong) return;
            void (^c)(void) = objc_getAssociatedObject(strong, &kMSBDPopupPendingCompletion);
            objc_setAssociatedObject(strong, &kMSBDPopupPendingCompletion, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            MSBDPopupRun(strong, op, content, open, animated, c);
        }, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    static long counter = 0;
    NSNumber *token = @(++counter);
    objc_setAssociatedObject(vc, &kMSBDPopupBusy, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakVC = vc;
    void (^done)(void) = ^{ if (completion) completion(); id strong = weakVC; if (strong) MSBDPopupFinished(strong, token); };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ id strong = weakVC; if (strong) MSBDPopupFinished(strong, token); });
    if (op == 1 && gMSBDPopupArgs == 4) oMSBDPresentBar4(vc, gMSBDPopupPresentSel, content, open, animated, done);
    else if (op == 1) oMSBDPresentBar3(vc, gMSBDPopupPresentSel, content, animated, done);
    else oMSBDDismissBar(vc, gMSBDPopupDismissSel, animated, done);
}
static void hMSBDPresentBar4(id self, SEL _cmd, id content, BOOL open, BOOL animated, void (^completion)(void)) {
    if (![NSThread isMainThread]) { oMSBDPresentBar4(self, _cmd, content, open, animated, completion); return; }
    MSBDPopupRun(self, 1, content, open, animated, completion);
}
static void hMSBDPresentBar3(id self, SEL _cmd, id content, BOOL animated, void (^completion)(void)) {
    if (![NSThread isMainThread]) { oMSBDPresentBar3(self, _cmd, content, animated, completion); return; }
    MSBDPopupRun(self, 1, content, NO, animated, completion);
}
static void hMSBDDismissBar(id self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    if (![NSThread isMainThread]) { oMSBDDismissBar(self, _cmd, animated, completion); return; }
    MSBDPopupRun(self, 2, nil, NO, animated, completion);
}
// Installs the guard on the class that carries the library's methods (UIViewController, its category): one present and the dismiss, or nothing.
// YES when installed. (Once per process: the includer calls it once, for apps that contain the library.)
static BOOL MSBDPopupGuardInstall(Class vc) {
    int args = vc ? MSBDPopupPresentArgs(vc) : 0;
    if (!args || !MSBDPopupDismissKnown(vc)) return NO;
    gMSBDPopupArgs = args;
    gMSBDPopupDismissSel = sel_registerName("dismissPopupBarAnimated:completion:");
    if (args == 4) {
        gMSBDPopupPresentSel = sel_registerName("presentPopupBarWithContentViewController:openPopup:animated:completion:");
        MSHookMessageEx(vc, gMSBDPopupPresentSel, (IMP)hMSBDPresentBar4, (IMP *)&oMSBDPresentBar4);
    } else {
        gMSBDPopupPresentSel = sel_registerName("presentPopupBarWithContentViewController:animated:completion:");
        MSHookMessageEx(vc, gMSBDPopupPresentSel, (IMP)hMSBDPresentBar3, (IMP *)&oMSBDPresentBar3);
    }
    MSHookMessageEx(vc, gMSBDPopupDismissSel, (IMP)hMSBDDismissBar, (IMP *)&oMSBDDismissBar);
    return YES;
}
