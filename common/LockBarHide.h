// LockBarHide.h -- the Lock Screen's status bar (1.8.9: B113 and F49 rev 2, plans/design-mac-lock-screen.md 12.1): which status bar is drawn
// at the Lock Screen's top right, and SpringBoard's own call that hides it. Shared by macsettings/LockStatusBar.x (Hide Status Bar on Lock
// Screen) and macsettings/MacLockScreen.x (Mac Lock Screen's Wi-Fi and Battery); each payload has its own copy with its own reason
// (LBH_REASON, defined before the include): SpringBoard keeps a set of reasons, so the two never undo each other.
//
// Who draws there (25 Nov 2026; the 18.5 session's window list and A/B crops; the calls read from the 15.6.1, 16.7.7, 17.5.1 and 18.5
// IPSWs' SpringBoard and CoverSheet code):
// - the Cover Sheet's own copy of the bar (its "fake" status bar: CSCoverSheetViewController -_setFakeStatusBarEnabled:), on 15-17 the bar
//   seen at rest; LockStatusBar.x has always turned it off (KT's 17.5 shows no bar with the switch on);
// - SpringBoard's status bar window (SBStatusBarWindow, level 1070, above the Cover Sheet's window at 1050): on 18 the bar seen at rest. The
//   Cover Sheet asks for it with its status bar component (the active appearance's type 2: alpha and style) through
//   -[SBDashBoardStatusBarController setStatusBarAlpha:style:legibilitySettings:] and leaves its fake copy off, so -_setFakeStatusBarEnabled:NO
//   changed nothing on 18 and iPadOS's bar stayed while our log said "hidden" (B113, published in 1.8.8.4 too).
// SpringBoard's own call to hide that bar for the Lock Screen is -[SBDashBoardStatusBarController setStatusBarHidden:forReason:] (the Cover
// Sheet's context's statusBarController, 17.5.1 and 18.5): it keeps a set of reasons and holds one "hidden" settings assertion at the Lock
// Screen's level (8) while the set is not empty (18.5's code; the Cover Sheet's own -_invalidateStatusBarAssertions removes its own reason the
// same way). Ours is one more reason in that set: added while the Cover Sheet shows, removed at the start of its dismissal, at a switch-off, when
// iPadOS invalidates its own and when it is gone. iPadOS's own reasons are never touched; nothing is hidden by a view property.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---------------------------------------------------------------------------------------------------------------- the rules (Foundation only)
// The top-right band: the right quarter of the screen, the top 44 pt (where the Wi-Fi, battery and any bar icons are drawn).
static inline CGRect LBHBand(CGSize screen) { return CGRectMake(screen.width * 0.75, 0, screen.width * 0.25, 44); }
static inline BOOL LBHInBand(CGRect itemOnScreen, CGSize screen) {
    return itemOnScreen.size.width >= 1 && itemOnScreen.size.height >= 1 && CGRectIntersectsRect(itemOnScreen, LBHBand(screen));
}
// A status bar view counts as DRAWN there when all of these hold (model values: what a running animation ends at).
typedef struct {
    BOOL ownScreen;          // its window is on the iPad's own screen (not the TV's)
    BOOL windowShown;        // its window is not hidden
    CGFloat windowAlpha;
    CGFloat windowLevel, coverLevel;   // its window's level and the Cover Sheet window's
    BOOL chainShown;         // the view and every ancestor not hidden
    CGFloat effectiveAlpha;  // the product of the alphas up to the window
    BOOL itemInBand;         // at least one shown item meets the band
} LBHFacts;
static inline BOOL LBHDrawn(LBHFacts f) {
    return f.ownScreen && f.windowShown && f.windowAlpha > 0.01 && f.windowLevel >= f.coverLevel && f.chainShown && f.effectiveAlpha > 0.01 && f.itemInBand;
}
// Our reason in SpringBoard's set (B113): wanted while our switch is on, no other modification hides the bar, and the Cover Sheet shows
// (in its window, not dismissing). Returns the step: +1 add, -1 remove, 0 nothing.
static inline int LBHStep(BOOL reasonIn, BOOL switchOn, BOOL otherDoesIt, BOOL coverShown, BOOL dismissing) {
    BOOL want = switchOn && !otherDoesIt && coverShown && !dismissing;
    return want == reasonIn ? 0 : want ? 1 : -1;
}
// Mac Lock Screen's Wi-Fi and Battery (F49 rev 2, 12.1): exactly one status drawing at the top right. Our pair only where none is drawn because
// WE hid it for this appearance (Hide Status Bar on Lock Screen's runtime flag, or the part's own hide of iPadOS's bar, Q27), where iPadOS's
// current page wants a bar, and not over Today.
typedef struct { BOOL partOn, barDrawn, hidByLSB, hidByUs, pageWantsBar, today; } LBHPairFacts;
static inline BOOL LBHPairShows(LBHPairFacts f) { return f.partOn && !f.barDrawn && (f.hidByLSB || f.hidByUs) && f.pageWantsBar && !f.today; }
// Q27: the part hides iPadOS's own bar (through the same call) when a bar is drawn that is not our menu bar's copy, the part is on and no
// other modification owns the top right; a drawn copy of OUR menu bar (already the Mac's icons, 15-17) is left as it is and gets no pair.
// Only where our pair will draw (iPadOS's page wants a bar, not Today: review finding 5, else Today had no status drawing at all) and never
// while Hide Status Bar on Lock Screen hides it (its own request answers for it: two reasons in SpringBoard's set would keep its re-ask from
// re-making the hidden request, review finding 2).
static inline BOOL LBHPartHides(BOOL partOn, BOOL barDrawn, BOOL barIsOurMenuBar, BOOL alreadyHidByUs, BOOL hidByLSB, BOOL pageWantsBar, BOOL today) {
    if (!partOn || hidByLSB || !pageWantsBar || today) return NO;
    return alreadyHidByUs || (barDrawn && !barIsOurMenuBar);
}

// The runtime flag "Hide Status Bar on Lock Screen hid the Lock Screen's bar for this appearance": an associated object on the Cover Sheet's
// controller under a selector key (selectors are one per process, so LockStatusBar.x writes it and MacLockScreen.x reads it), and an in-process
// note when it changes (MacLockScreen.x reads the bar again then, and once more a main-queue turn later).
#define LBH_FLAG_KEY @selector(msbdLockStatusBarHidByUs)
#define LBH_CHANGED_NOTE @"com.besiktasliseba.maclockstatusbar.changed"

#ifndef LBH_RULES_ONLY
// ---------------------------------------------------------------------------------------------------------------- the calls (UIKit)
#ifndef LBH_REASON
#error "define LBH_REASON (this payload's reason string) before including LockBarHide.h"
#endif
static BOOL gLBHIn;                 // our reason is in SpringBoard's set...
static __weak id gLBHController;    // ...of this controller (given back to the same one)
static id LBHIvarObj(id o, const char *name) {
    if (!o) return nil;
    Ivar v = class_getInstanceVariable(object_getClass(o), name);
    const char *t = v ? ivar_getTypeEncoding(v) : NULL;
    return t && t[0] == '@' ? object_getIvar(o, v) : nil;
}
static id LBHObjCall(id o, NSString *selName) {
    SEL s = NSSelectorFromString(selName);
    if (!o || ![o respondsToSelector:s]) return nil;
    Method m = class_getInstanceMethod(object_getClass(o), s);
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    if (!e || e[0] != '@' || method_getNumberOfArguments(m) != 2) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
// SpringBoard's status bar controller for the Lock Screen, only when its call has the shape read (BOOL, object); nil = this iPadOS has none.
static id LBHController(id cs) {
    id ctx = LBHObjCall(cs, @"coverSheetContext") ?: LBHIvarObj(cs, "_coverSheetContext");
    id c = LBHObjCall(ctx, @"statusBarController");
    SEL set = NSSelectorFromString(@"setStatusBarHidden:forReason:");
    Method m = c ? class_getInstanceMethod(object_getClass(c), set) : NULL;
    if (!m || method_getNumberOfArguments(m) != 4) return nil;
    char t[8] = {0};
    method_getArgumentType(m, 2, t, sizeof(t));
    if (t[0] != 'B' && t[0] != 'c') return nil;
    method_getArgumentType(m, 3, t, sizeof(t));
    return t[0] == '@' ? c : nil;
}
static BOOL LBHReasonIn(void) { return gLBHIn; }
// Balanced: our reason goes in once and comes out once, from the controller it went to. Returns the step taken (+1, -1, 0; -2: no call here).
static int LBHSet(id cs, BOOL hide) {
    SEL set = NSSelectorFromString(@"setStatusBarHidden:forReason:");
    // (the state is recorded BEFORE SpringBoard is messaged: a call coming back in through its observers never adds or removes twice)
    if (!hide) {
        if (!gLBHIn) return 0;
        id c = gLBHController;
        gLBHIn = NO; gLBHController = nil;
        if (c) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(c, set, NO, LBH_REASON);
        return -1;
    }
    id c = LBHController(cs);
    if (!c) return gLBHIn ? 0 : -2;
    if (gLBHIn && gLBHController == c) return 0;
    id old = gLBHIn ? gLBHController : nil;
    gLBHIn = YES; gLBHController = c;
    if (old) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(old, set, NO, LBH_REASON);
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(c, set, YES, LBH_REASON);
    return 1;
}

// ---- the VISIBLE BAR read (12.1): status bar views found by ivars and properties, never by walking the screen's trees ----
typedef struct {
    BOOL drawn;                       // a status bar is drawn at the top right
    BOOL ourMenuBar;                  // ...and it is our menu bar's copy (its Apple logo label is shown)
    __unsafe_unretained UIView *view; // (for the log and the observers of this pass only; never kept)
    __unsafe_unretained UIWindow *window;
    const char *what;                 // "the Cover Sheet's copy", "SpringBoard's status bar window", "a portal of a status bar"
} LBHBar;
static BOOL LBHIsStatusBarWindow(UIWindow *w) {
    NSString *c = NSStringFromClass([w class]);
    return [c isEqualToString:@"SBStatusBarWindow"] || [c isEqualToString:@"UIStatusBarWindow"];
}
// The status bar window on the Cover Sheet's own screen (its scene's windows: a short list, not a view tree)
static UIWindow *LBHStatusBarWindow(UIWindow *cover) {
    NSArray *ws = nil;
    @try { ws = [cover respondsToSelector:@selector(windowScene)] ? [[cover windowScene] windows] : nil; } @catch (NSException *e) { ws = nil; }
    for (UIWindow *w in ws) if (LBHIsStatusBarWindow(w) && w.screen == cover.screen) return w;
    return nil;
}
static UIView *LBHWindowBar(UIWindow *w) {
    if (!w) return nil;
    id b = LBHObjCall(w, @"statusBar") ?: LBHIvarObj(w, "_statusBar");
    return [b isKindOfClass:[UIView class]] ? b : nil;
}
// A shown item of the bar meets the band (a bounded look inside the found bar: its leaves, 7 levels at most)
static BOOL LBHItemInBand(UIView *v, UIScreen *screen, CGSize S, int depth, BOOL *ourLogo) {
    if (v.hidden || v.alpha <= 0.01) return NO;
    if ([v isKindOfClass:[UILabel class]] && [((UILabel *)v).text isEqualToString:@""]) *ourLogo = YES;   // (our menu bar's Apple logo)
    BOOL leaf = v.subviews.count == 0 || [v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UIImageView class]];
    if (leaf) {
        CGRect r = [v convertRect:v.bounds toCoordinateSpace:screen.coordinateSpace];
        return LBHInBand(r, S);
    }
    if (depth <= 0) return NO;
    BOOL any = NO;
    for (UIView *s in v.subviews) if (LBHItemInBand(s, screen, S, depth - 1, ourLogo)) any = YES;   // (all of them: the logo may sit left of the band)
    return any;
}
static BOOL LBHViewDrawn(UIView *v, UIWindow *cover, BOOL *ourLogo) {
    if (![v isKindOfClass:[UIView class]]) return NO;
    UIWindow *w = v.window;
    if (!w || !cover) return NO;
    LBHFacts f;
    f.ownScreen = w.screen == cover.screen && w.screen == [UIScreen mainScreen];
    f.windowShown = !w.hidden; f.windowAlpha = w.alpha;
    f.windowLevel = w.windowLevel; f.coverLevel = cover.windowLevel;
    f.chainShown = YES; f.effectiveAlpha = 1;
    for (UIView *x = v; x && x != w; x = x.superview) { if (x.hidden) f.chainShown = NO; f.effectiveAlpha *= x.alpha; }
    f.itemInBand = NO;
    if (f.ownScreen && f.windowShown && f.chainShown && f.effectiveAlpha > 0.01) {
        UIScreen *scr = w.screen;
        f.itemInBand = LBHItemInBand(v, scr, scr.coordinateSpace.bounds.size, 7, ourLogo);
    }
    return LBHDrawn(f);
}
static BOOL LBHPortalOf(UIView *p, NSArray *bars) {
    if (![NSStringFromClass([p class]) containsString:@"PortalView"]) return NO;
    id src = LBHObjCall(p, @"sourceView");
    return src && [bars containsObject:src];
}
// cs: the Cover Sheet's controller (its view in its window). Every candidate is read afresh at each call.
static LBHBar LBHVisibleBar(id cs) {
    LBHBar out; memset(&out, 0, sizeof(out));
    UIView *cv = [cs isViewLoaded] ? [cs view] : nil;
    UIWindow *cover = cv.window;
    if (!cover) return out;
    UIWindow *sbw = LBHStatusBarWindow(cover);
    NSMutableArray *bars = [NSMutableArray array];
    const char *whats[4]; int n = 0;
    UIView *b;
    if ((b = LBHIvarObj(cs, "_fakeStatusBar")) && [b isKindOfClass:[UIView class]]) { [bars addObject:b]; whats[n++] = "the Cover Sheet's copy"; }
    if ((b = LBHIvarObj(cv, "_fakeStatusBar")) && [b isKindOfClass:[UIView class]] && ![bars containsObject:b]) { [bars addObject:b]; whats[n++] = "the Cover Sheet's copy"; }
    if ((b = LBHWindowBar(sbw)) && ![bars containsObject:b]) { [bars addObject:b]; whats[n++] = "SpringBoard's status bar window"; }
    for (NSUInteger i = 0; i < bars.count; i++) {
        BOOL logo = NO;
        if (LBHViewDrawn(bars[i], cover, &logo)) { out.drawn = YES; out.ourMenuBar = logo; out.view = bars[i]; out.window = ((UIView *)bars[i]).window; out.what = whats[i]; return out; }
    }
    // portals of those bars, one level under the status bar window's root view and the Cover Sheet's fake-bar wrapper
    UIView *wrap = LBHIvarObj(cv, "_fakeStatusBarWrapperView");
    UIView *root = sbw.rootViewController.isViewLoaded ? sbw.rootViewController.view : nil;
    for (UIView *c in @[ [wrap isKindOfClass:[UIView class]] ? wrap : cv, [root isKindOfClass:[UIView class]] ? root : cv ]) {
        for (UIView *p in c.subviews) {
            BOOL logo = NO;
            if (LBHPortalOf(p, bars) && LBHViewDrawn(p, cover, &logo)) { out.drawn = YES; out.ourMenuBar = logo; out.view = p; out.window = p.window; out.what = "a portal of a status bar"; return out; }
        }
    }
    return out;
}
#endif
