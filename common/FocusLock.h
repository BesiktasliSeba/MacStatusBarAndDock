// FocusLock.h -- SpringBoard takes the keyboard focus for one of its own windows (our menus and panels, Finder's windows, the desktop's rename, the
// Wi-Fi password sheet, the Mac Switcher, the Dock's Downloads search) and gives it back when the returned lock is invalidated (MSBDFocusUnlock).
// SpringBoard only. Normally the front app holds the focus: without this, a hardware keyboard's keys go to the app, not to our field.
// Whichever call this iPadOS has, each checked (selector and type encoding) before it is made; the first that fits is used:
//   16/17: -[SBWorkspaceKeyboardFocusController/SBKeyboardFocusCoordinator lockFocusToSpringBoardWindowScene:forReason:] (a string reason)
//   15:    -lockFocusToSpringBoardForReason: (a string reason)
//   18:    -[SBKeyboardFocusCoordinator focusLockSpringBoardWindowScene:forReason:] (@32@0:8@16@24 on 18.5). Its reason is an
//          SBKeyboardFocusLockReason, a class with factory reasons only (+activeTransientOverlay, +systemModalAlert, +keyShortcutHUD, +floatingDock,
//          +appSwitcher, ...) and no initialiser that takes a string: a string there would be sent messages it does not answer. We take
//          +activeTransientOverlay (a transient overlay over the apps is what our windows are), else +systemModalAlert. The lock it returns is a
//          _BSCompoundAssertionAcquisitionReference: each holder invalidates its own.
// Anything missing or of another shape: nil, nothing is called (the field then simply gets no hardware keys while an app holds the focus).
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// A method's type encoding without frame offsets or quoted class names ("@32@0:8@16@24" -> "@@:@@").
__attribute__((unused)) static NSString *MSBDFocusBareTypes(Method m) {
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e) return nil;
    NSMutableString *s = [NSMutableString string];
    for (const char *p = e; *p; p++) {
        if (*p >= '0' && *p <= '9') continue;
        if (*p == '"') { p++; while (*p && *p != '"') p++; if (!*p) break; continue; }
        [s appendFormat:@"%c", *p];
    }
    return s;
}
__attribute__((unused)) static BOOL MSBDFocusHas(id obj, SEL sel, NSString *types) {
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    return [MSBDFocusBareTypes(class_getInstanceMethod(object_getClass(obj), sel)) isEqualToString:types];
}
// SpringBoard's keyboard focus controller (SBWorkspaceKeyboardFocusController on 15/16, SBKeyboardFocusCoordinator on 17+), or nil.
__attribute__((unused)) static id MSBDFocusController(void) {
    Class wsc = objc_getClass("SBMainWorkspace");
    if (!wsc || ![(id)wsc respondsToSelector:@selector(sharedInstance)]) return nil;
    id ws = ((id (*)(id, SEL))objc_msgSend)((id)wsc, @selector(sharedInstance));
    SEL k = NSSelectorFromString(@"keyboardFocusController");
    return [ws respondsToSelector:k] ? ((id (*)(id, SEL))objc_msgSend)(ws, k) : nil;
}
// The 18 reason's factories, in the order they are taken (one list for the lock and for its readiness check below).
__attribute__((unused)) static NSArray<NSString *> *MSBDFocusReasonFactories18(void) { return @[@"activeTransientOverlay", @"systemModalAlert"]; }
// The 18 reason object (see above), or nil.
__attribute__((unused)) static id MSBDFocusLockReason18(void) {
    Class rc = objc_getClass("SBKeyboardFocusLockReason");
    if (!rc) return nil;
    for (NSString *f in MSBDFocusReasonFactories18()) {
        SEL fs = NSSelectorFromString(f);
        Method fm = class_getClassMethod(rc, fs);
        if (!fm || ![MSBDFocusBareTypes(fm) isEqualToString:@"@@:"]) continue;
        id r = ((id (*)(id, SEL))objc_msgSend)((id)rc, fs);
        if ([r isKindOfClass:rc]) return r;
    }
    return nil;
}
// The lock for scene (the window's scene; the 15 call takes none). why names it in SpringBoard's own focus logs on 15-17. *how (optional) says
// which call was made, for our log: "16", "15", "18", or nil when none fits.
__attribute__((unused)) static id MSBDFocusLock(UIWindowScene *scene, NSString *why, NSString **how) {
    if (how) *how = nil;
    id kfc = MSBDFocusController();
    if (!kfc) return nil;
    SEL s16 = NSSelectorFromString(@"lockFocusToSpringBoardWindowScene:forReason:"), s15 = NSSelectorFromString(@"lockFocusToSpringBoardForReason:");
    SEL s18 = NSSelectorFromString(@"focusLockSpringBoardWindowScene:forReason:");
    id lock = nil;
    @try {
        if (scene && MSBDFocusHas(kfc, s16, @"@@:@@")) { lock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, s16, scene, why); if (how) *how = @"16"; }
        else if (MSBDFocusHas(kfc, s15, @"@@:@")) { lock = ((id (*)(id, SEL, id))objc_msgSend)(kfc, s15, why); if (how) *how = @"15"; }
        else if (scene && MSBDFocusHas(kfc, s18, @"@@:@@")) {
            id reason = MSBDFocusLockReason18();
            if (reason) { lock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, s18, scene, reason); if (how) *how = @"18"; }
        }
    } @catch (NSException *e) { lock = nil; }
    return lock;
}
// Gives a lock back (nil: nothing).
__attribute__((unused)) static void MSBDFocusUnlock(id lock) {
    if (lock && [lock respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(lock, @selector(invalidate));
}
// iPadOS 18+: is the typed call above there, with a reason to give it? Class lookups only (nothing is made, called or initialised), so it can be
// asked at any time, before SpringBoard is up. The features whose fields or keys need SpringBoard to hold the focus (the Mac Switcher, the Wi-Fi
// menu's password sheet, the desktop's rename) go on on 18+ only with it (15-17 keep their own calls, unchanged).
__attribute__((unused)) static BOOL MSBDFocusLock18Ready(void) {
    Class kc = objc_getClass("SBKeyboardFocusCoordinator"), rc = objc_getClass("SBKeyboardFocusLockReason");
    if (!kc || !rc) return NO;
    Method m = class_getInstanceMethod(kc, NSSelectorFromString(@"focusLockSpringBoardWindowScene:forReason:"));
    if (!m || ![MSBDFocusBareTypes(m) isEqualToString:@"@@:@@"]) return NO;
    for (NSString *f in MSBDFocusReasonFactories18()) {
        Method fm = class_getClassMethod(rc, NSSelectorFromString(f));
        if (fm && [MSBDFocusBareTypes(fm) isEqualToString:@"@@:"]) return YES;
    }
    return NO;
}
