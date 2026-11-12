// DockAutoHide.m -- Settings > Dock > Automatically Hide and Show the Dock (MacStatusBar&Dock 1.8.4 item 4, KT's yes 7 Nov): off by default, as on
// macOS. The rules are common/DockAutoHide.h's.
//
// How iPadOS decides where the Dock is: SBFloatingDockController keeps behavior assertions by level and derives the Dock's progress (1 out, 0 away)
// and whether a gesture may bring it from the active one. In an app the switcher's in-app assertion says away with the gesture possible: the swipe
// up from the bottom edge or the pointer at it brings the Dock, a touch elsewhere or the pointer leaving puts it away -- macOS's auto-hide exactly.
// On the Home Screen (where Aerial, Zetsu and MilkyWay4 show their windows) the controller's own assertion says out, no gesture (level 0, reason
// "homescreen": read on 18.5, plans/v184.md item 4). While the switch is on, that one assertion answers away with the gesture possible, so
// SpringBoard treats the Home Screen as it treats an app: its own reveal and dismissal, on every engine. Nothing of ours is created (an assertion of
// ours crashed SpringBoard before: Dock.x's note); only two getters of Apple's assertion are read again, in their shapes, for that assertion only.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <substrate.h>
#import "DMLog.h"
#include "../common/DockAutoHide.h"
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

@interface UIWindow (DMAutoHidePrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

static BOOL gDockAutoHide = NO;   // (the switch, as DMLoadPrefs reads it: with the Dock part on only, and the hooks in place)
static BOOL gDockAutoHideEditing = NO;   // (the Home Screen is being edited: the Dock shows meanwhile -- DockAutoHide.h MSBDAutoHideHomeHides)
// (asked by the status bar part: the room for windows and Stage Manager's in-app answer follow the Dock as it really behaves -- StatusBar.x DMDockAutoHides)
__attribute__((visibility("default"))) BOOL MSBDDockAutoHides(void) { return gDockAutoHide; }
// 1.8.7 (per display, plans/design-1.8.7-displays.md section 5): one display's answer. The iPad's own screen (or none): the switch, as above. Another display (a
// TV): its own Automatically Hide and Show the Dock, the iPad's answer until changed for it, with the Dock part on (Dock.x DMDispDockBool, the Dock part's
// per-display layer). On a TV the Dock hides through Stage Manager's in-app answer for that display's stage (StatusBar.x), not through the Home Screen's
// assertion below, which stays the iPad's.
extern BOOL DMDispDockBool(UIScreen *s, const char *key, BOOL ipad);
__attribute__((visibility("default"))) BOOL MSBDDockAutoHidesOn(UIScreen *s) {
    if (!s || s == [UIScreen mainScreen]) return gDockAutoHide;
    return DMDispDockBool(s, kMSBDAutoHideKey, gDockAutoHide);
}

static BOOL DMAutoHideShape(id o, const char *sel, const char *enc) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), sel_registerName(sel)) : NULL;
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    return e && !strcmp(e, enc);
}
// The Home Screen's own assertion: level 0, reason "homescreen" (its level and reason read through their own getters, in their shapes).
static BOOL DMAutoHideIsHomeScreen(id a) {
    if (!DMAutoHideShape(a, "level", "Q16@0:8") || !DMAutoHideShape(a, "reason", "@16@0:8")) return NO;
    if (((unsigned long long (*)(id, SEL))objc_msgSend)(a, sel_registerName("level")) != 0) return NO;
    id r = ((id (*)(id, SEL))objc_msgSend)(a, sel_registerName("reason"));
    return [r isKindOfClass:[NSString class]] && [r isEqualToString:@"homescreen"];
}
static double (*o_DMAutoHideProgress)(id, SEL);
static BOOL (*o_DMAutoHideGesture)(id, SEL);
static double DMAutoHideProgress(id self, SEL _cmd) {
    double p = o_DMAutoHideProgress(self, _cmd);
    return MSBDAutoHideHomeHides(gDockAutoHide, gDockAutoHideEditing) && DMAutoHideIsHomeScreen(self) ? MSBDAutoHideHomeProgress(1, p) : p;
}
static BOOL DMAutoHideGesture(id self, SEL _cmd) {
    BOOL g = o_DMAutoHideGesture(self, _cmd);
    return MSBDAutoHideHomeHides(gDockAutoHide, gDockAutoHideEditing) && DMAutoHideIsHomeScreen(self) ? (BOOL)MSBDAutoHideHomeGesture(1, g) : g;
}
static int gDockAutoHideHooks = 0;   // (0 not tried yet, 1 hooked, -1 not as expected here: left as Apple has it)
// (asked by the status bar part: with hooks that could not be made here our switch can't act, so it is no change of the Dock for the windows and no reason to
//  write Stage Manager's tick -- DockAutoHide.h MSBDAutoHideCanAct, review 1.8.4 Pass 4 L3)
__attribute__((visibility("default"))) int MSBDDockAutoHideHooks(void) { return gDockAutoHideHooks; }
static BOOL DMAutoHideInstall(void) {
    if (gDockAutoHideHooks) return gDockAutoHideHooks > 0;
    Class c = objc_getClass("SBFloatingDockBehaviorAssertion");
    Method p = c ? class_getInstanceMethod(c, @selector(progress)) : NULL, g = c ? class_getInstanceMethod(c, sel_registerName("gesturePossible")) : NULL;
    Method l = c ? class_getInstanceMethod(c, sel_registerName("level")) : NULL, r = c ? class_getInstanceMethod(c, sel_registerName("reason")) : NULL;
    BOOL ok = p && g && l && r && !strcmp(method_getTypeEncoding(p), "d16@0:8") && !strcmp(method_getTypeEncoding(g), "B16@0:8")
           && !strcmp(method_getTypeEncoding(l), "Q16@0:8") && !strcmp(method_getTypeEncoding(r), "@16@0:8");
    if (!ok) { gDockAutoHideHooks = -1; DMLog(@"[autohide] the Dock's behavior assertions are not as expected here: the Dock stays as iPadOS has it"); return NO; }
    MSHookMessageEx(c, @selector(progress), (IMP)DMAutoHideProgress, (IMP *)&o_DMAutoHideProgress);
    MSHookMessageEx(c, sel_registerName("gesturePossible"), (IMP)DMAutoHideGesture, (IMP *)&o_DMAutoHideGesture);
    gDockAutoHideHooks = o_DMAutoHideProgress && o_DMAutoHideGesture ? 1 : -1;
    DMLog(gDockAutoHideHooks > 0 ? @"[autohide] the Home Screen's Dock assertion answers away with the gesture possible while the switch is on" : @"[autohide] the hooks could not be made");
    return gDockAutoHideHooks > 0;
}
// Whether the Home Screen's own assertion decides this Dock now: the highest assertion the controller holds, leaving out its own gesture one (the Dock a swipe,
// the pointer or a tap brought out or put away over the Home Screen), is the Home Screen's. Its assertions by level are a C array of pointer arrays in the
// controller (_floatingDockBehaviorAssertionsByLevel, [13@"NSPointerArray"] on 18.5), read at the ivar's offset only in that shape; otherwise the active
// assertion is asked, as before.
static BOOL DMAutoHideHomeScreenDecides(id ctrl, id gesture) {
    Ivar iv = class_getInstanceVariable(object_getClass(ctrl), "_floatingDockBehaviorAssertionsByLevel");
    int levels = MSBDAutoHideLevelsOf(iv ? ivar_getTypeEncoding(iv) : NULL);   // (0: not exactly that shape, not read -- DockAutoHide.h)
    if (levels > 0) {
        __unsafe_unretained id *byLevel = (__unsafe_unretained id *)(void *)((char *)(__bridge void *)ctrl + ivar_getOffset(iv));
        for (int i = levels - 1; i >= 0; i--) {
            id e = byLevel[i];
            if (![e isKindOfClass:[NSPointerArray class]]) continue;
            NSPointerArray *pa = e;
            for (NSUInteger k = pa.count; k-- > 0;) {
                id a = (__bridge id)[pa pointerAtIndex:k];
                if (!a || a == gesture) continue;
                return DMAutoHideIsHomeScreen(a);
            }
        }
        return NO;
    }
    id active = DMAutoHideShape(ctrl, "activeAssertion", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("activeAssertion")) : nil;
    return active && (active == gesture || DMAutoHideIsHomeScreen(active));
}
// SpringBoard's icon controller, only once SpringBoard has made it -- never made by us (review 1.8.4 Pass 4 H1: the switch on, a respring, and the constructor
// asked +sharedInstance before SpringBoard had set up). +sharedInstanceIfExists where the class has it, as SpringBoard asks (17+: an early +sharedInstance
// crashes there, issue #1); where it has not, +sharedInstance only once SpringBoard is up and its Dock's window is there (the Dock is the icon controller's own).
static id DMAutoHideIconController(BOOL dockWindowSeen) {
    Class icc = objc_getClass("SBIconController");
    if (!icc) return nil;
    Method ie = class_getClassMethod(icc, sel_registerName("sharedInstanceIfExists"));
    if (ie) return method_getTypeEncoding(ie) && !strcmp(method_getTypeEncoding(ie), "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)((id)icc, sel_registerName("sharedInstanceIfExists")) : nil;
    if (!dockWindowSeen || ![UIApplication sharedApplication]) return nil;
    SEL ss = sel_registerName("sharedInstance");
    Method sm = class_getClassMethod(icc, ss);
    const char *se = sm ? method_getTypeEncoding(sm) : NULL;
    return se && !strcmp(se, "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)((id)icc, ss) : nil;
}
// Every Dock's controller: each Dock window's own (its root's delegate: 16 to 18), and the iPad's from SpringBoard's icon controller -- on iPadOS 15 no Dock
// window answers its controller as that delegate (M1 15.6.1: the switch went on and nothing was applied until the next change of assertions). Shapes asked.
NSArray *DMDockAutoHideControllers(void) {
    NSMutableArray *out = [NSMutableArray array];
    Class dc = objc_getClass("SBFloatingDockController");
    if (!dc) return out;
    BOOL windowSeen = NO;
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        windowSeen = YES;
        id root = w.rootViewController;
        id c = [root respondsToSelector:@selector(delegate)] ? ((id (*)(id, SEL))objc_msgSend)(root, @selector(delegate)) : nil;
        if ([c isKindOfClass:dc] && ![out containsObject:c]) [out addObject:c];
    }
    id ic = DMAutoHideIconController(windowSeen);
    id main = DMAutoHideShape(ic, "floatingDockController", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ic, sel_registerName("floatingDockController")) : nil;
    if ([main isKindOfClass:dc] && ![out containsObject:main]) [out addObject:main];
    return out;
}
// Each Dock (the iPad's and a TV's) the Home Screen's assertion decides: the Dock goes away (on) or comes back (off) now, as SpringBoard itself does when an
// assertion goes -- its gesture assertion cleared (a Dock brought out or put away before stands no more) and the assertions evaluated again with the active one
// derived anew, which now reads the Home Screen's as the switch says (-_clearGestureAssertion and -_evaluateAssertions:1 interactive:NO withCompletion:, the
// steps of its own remove. Not -_updateFloatingDockBehaviorAssertionsInteractive:completion:, mode 2, which only re-reads the active assertion: with the
// gesture one cleared there was none, and the Dock stayed away after "off", M1 15.6.1). Where those are not there in their shapes: its own dismiss and
// present (asked first), as the Downloads panel sends them. Every completion an empty block, never nil: one called unchecked is a crash (review 1.8.4
// Pass 4 L1; Dock.x DMDockSideSend does the same).
// An app, the App Switcher, Spotlight, a folder: theirs, as before (the Home Screen's decides again when it is back).
static void DMAutoHideApplyNow(BOOL on) {
    for (id ctrl in DMDockAutoHideControllers()) {
        Ivar gi = class_getInstanceVariable(object_getClass(ctrl), "_activeGestureFloatingDockBehaviorAssertion");
        const char *gt = gi ? ivar_getTypeEncoding(gi) : NULL;
        id gesture = gt && gt[0] == '@' ? object_getIvar(ctrl, gi) : nil;
        if (!DMAutoHideHomeScreenDecides(ctrl, gesture)) continue;
        if (DMAutoHideShape(ctrl, "_clearGestureAssertion", "v16@0:8") && DMAutoHideShape(ctrl, "_evaluateAssertions:interactive:withCompletion:", "v36@0:8Q16B24@?28")) {
            if (gesture) ((void (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("_clearGestureAssertion"));
            ((void (*)(id, SEL, unsigned long long, BOOL, id))objc_msgSend)(ctrl, sel_registerName("_evaluateAssertions:interactive:withCompletion:"), 1, NO, ^{});
        } else {
            SEL s = on ? sel_registerName("dismissFloatingDockIfPresentedAnimated:completionHandler:") : sel_registerName("presentFloatingDockIfDismissedAnimated:completionHandler:");
            if (!DMAutoHideShape(ctrl, sel_getName(s), "v28@0:8B16@?20")) continue;
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctrl, s, YES, ^{});
        }
        DMLog([NSString stringWithFormat:@"[autohide] the Home Screen's Dock %@", on ? @"goes away (it comes back with a swipe up from the bottom edge or the pointer there)" : @"is shown again"]);
    }
}
// Edit Home Screen began or ended (Dock.x: the Dock's own controller is told, -[SBFloatingDockViewController setEditing:animated:]): with the switch on the
// Dock comes out for the editing and goes away again after it (review 1.8.4 Pass 4 M2). The room for windows stays as the switch says (MSBDDockAutoHides).
void DMDockAutoHideSetEditing(BOOL editing) {
    if (editing == gDockAutoHideEditing) return;
    gDockAutoHideEditing = editing;
    if (!gDockAutoHide) return;
    DMLog(editing ? @"[autohide] the Home Screen is being edited: the Dock shows until editing ends" : @"[autohide] editing ended: the Dock goes away again");
    if ([UIApplication sharedApplication]) DMAutoHideApplyNow(!editing);
}
void DMDockAutoHideSetOn(BOOL on) {
    if (on == gDockAutoHide) return;
    if (on && !DMAutoHideInstall()) return;
    gDockAutoHide = on;
    if (on) DM_FEATURE_MARK("dock-auto-hide");
    DMLog([NSString stringWithFormat:@"[autohide] Automatically Hide and Show the Dock %@", on ? @"on" : @"off"]);
    // (Before SpringBoard is up -- the switch read by the constructor at a respring -- there is no Dock to apply it to: the hooks answer its first layout. Applied
    //  then, SpringBoard's icon controller was asked for, and made, before SpringBoard had set up: review 1.8.4 Pass 4 H1)
    if ([UIApplication sharedApplication]) DMAutoHideApplyNow(MSBDAutoHideHomeHides(on, gDockAutoHideEditing));
    else DMLog(@"[autohide] SpringBoard is starting: the hooks answer the Dock's first layout");
}
