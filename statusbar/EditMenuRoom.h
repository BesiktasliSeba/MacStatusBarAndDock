// statusbar/EditMenuRoom.h: UIKit's edit menu over the keyboard in a turned SpringBoard (1.8.8.2): the keyboard's room under an edit menu worked
// out in one space. Included by StatusBar.x (SpringBoard only), put in by its %ctor (DMEditMenuRoomInit). The rule: common/EditMenuRoom.h. Mac test
// tools/test-editmenuroom.sh.
//
// The fault is UIKit's, in SpringBoard: an edit menu (Cut, Copy, Paste: a name renamed on the desktop, a sticky note, Finder's and TextEdit's
// fields, a Home Screen folder's name) gets its container's bounds less -[_UIEditMenuPresentation _preferredContentInsetsForContainerView]
// (iPadOS 16) or -[_UIEditMenuContentPresentation _preferredContentInsetsForContainerViewWithConfiguration:] (iPadOS 18, the same formula and
// one more guard). For a container in a text effects window that takes the keyboard from -[UIKeyboardSceneDelegate
// visibleInputViewFrameInView:], which converts it from the keyboard window's screen space into view.window.windowScene.coordinateSpace and
// stops there. In an app the scene's space is the window's. SpringBoard's window scene stays in the screen's fixed portrait space while its
// interface is turned: in landscape the docked keyboard {0, 360, 1024, 408} arrived as {0, 0, 408, 1024}, its top 0, the bottom inset 774 in a
// 768 point container, and UIKit pinned the menu above the top edge, under the menu bar (read on iPadOS 16.7.7 in landscape: 774 exactly).
// UIKit's other branch (any other window: -verticalOverlapForView:usingKeyboardInfo:) converts on from the scene's space into the view and is
// right in every space.
//
// So, in SpringBoard only, a pass-through of that method keeps UIKit's answer except where the two spaces differ (landscape either way, upside
// down) on the iPad's own screen, UIKit's own conditions for the keyboard branch hold and UIKit's bottom inset is its formula on the frame it read
// (MSBDEditMenuIsUIKits: an answer made another way, a guard or formula of an iPadOS not read here, or another tweak's change, is kept): there the
// bottom inset is UIKit's formula again with the keyboard taken the last step into the container, the call UIKit's other branch makes
// ([scene.coordinateSpace convertRect:toCoordinateSpace:]). Top, left and right stay UIKit's. A container on another display (the TV, which never
// turns; SpringBoard's keyboard is on the iPad's own screen) keeps UIKit's answer whatever its spaces. Both shapes are checked at the start by
// class, selector and type encoding, and so is every UIKit call the fix makes; anything missing or of another shape: no hook, UIKit's own. A piece
// of the status bar for the crash guard (tools/crashmap-rules.txt, editMenuRoom): its decision and start-up check are the piece's, the two
// pass-throughs transparent (on every SpringBoard edit menu's layout once in). It patches Apple's code inside SpringBoard: every SpringBoard edit
// menu in a turned SpringBoard benefits.
#include "../common/EditMenuRoom.h"
#define MSBD_EDIT_MENU_PIECE "editMenuRoom"   // (no Settings row: the crash guard turns it off as a piece, its target in tools/crashmap-rules.txt, until Turn Back On)

@protocol DMEditMenuKeyboard   // (UIKit's keyboard scene delegate as the fix calls it; checked at the start, DMEditMenuRoomInit)
- (BOOL)isOnScreen;
- (CGRect)visibleInputViewFrameInView:(UIView *)view;
@end
static Class gDMEditMenuKeyboardClass;   // (UIKeyboardSceneDelegate, once its calls are checked)
static NSString *gDMEditMenuSigObj, *gDMEditMenuSigBool;   // (the shapes of an object getter and a BOOL getter as the fix calls them, made at the start)

// The presentation's container: its -containerView (an object getter: 16's class, 18's in-process subclass), else its _containerView ivar.
static UIView *DMEditMenuContainer(id p) {
    SEL s = sel_registerName("containerView");
    Method m = p ? class_getInstanceMethod(object_getClass(p), s) : NULL;
    id c = nil;
    if (m && [DMSMSigOfMethod(m) isEqualToString:gDMEditMenuSigObj]) c = ((id (*)(id, SEL))objc_msgSend)(p, s);
    else if (p) {
        Ivar iv = class_getInstanceVariable(object_getClass(p), "_containerView");
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        if (t && t[0] == '@') c = object_getIvar(p, iv);
    }
    return [c isKindOfClass:[UIView class]] ? c : nil;
}
// A BOOL getter of UIKit's, asked only where it answers one (the window's two were checked at the start; the configuration's here).
static BOOL DMEditMenuAsk(id o, const char *name) {
    SEL s = sel_registerName(name);
    if (!o || ![o respondsToSelector:s]) return NO;
    Method m = class_getInstanceMethod(object_getClass(o), s);
    if (!m || ![DMSMSigOfMethod(m) isEqualToString:gDMEditMenuSigBool]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s);
}
#if DEBUG
// How the container lies on the iPad's screen (1.8.8.2, B75 on iPadOS 17): on 17.5.1 in landscape the container lies in SpringBoard's fixed
// portrait space like its scene ({1024, 1366}: "the scene's space is the container's") and UIKit's bottom inset, 1372, puts the menu off the
// screen. 17's insets method is 16's formula (read in the 17.6.1 decompile, -[_UIEditMenuContentPresentation _preferredContentInsetsForContainerView],
// hooked there): the keyboard's frame is already in the container's space, so the room is not this fault's. Whether that container is drawn
// turned on the screen (its window turned by a layer above its view, unseen by view conversions) or upright for portrait decides the 17 fix,
// read on the device from this line: its frame in the screen's turned space and in the fixed one, the turn of its x axis there, its window's
// bounds, interface orientation and the two layers above the window's own, SpringBoard's orientation (the keyboard's frame on the screen: the
// [kbdock] lines).
static NSString *DMEditMenuLie(UIView *c) {
    UIWindow *w = c.window; UIScreen *s = [UIScreen mainScreen];
    if (!w || w.screen != s) return @"";
    id<UICoordinateSpace> scr = s.coordinateSpace;
    CGPoint o = [c convertPoint:CGPointZero toCoordinateSpace:scr], x = [c convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    long (^orient)(id) = ^long (id obj) {
        SEL io = sel_registerName([obj isKindOfClass:[UIWindow class]] ? "interfaceOrientation" : "activeInterfaceOrientation");
        Method m = obj ? class_getInstanceMethod(object_getClass(obj), io) : NULL;
        const char *t = m ? method_getTypeEncoding(m) : NULL;
        return t && (t[0] == 'q' || t[0] == 'l') ? ((long (*)(id, SEL))objc_msgSend)(obj, io) : -1;
    };
    NSString *(^tf)(CALayer *) = ^NSString *(CALayer *l) {
        if (!l) return @"-";
        CATransform3D t = l.transform;
        return [NSString stringWithFormat:@"[%.2f %.2f %.2f %.2f | %.1f %.1f]", t.m11, t.m12, t.m21, t.m22, t.m41, t.m42];
    };
    CALayer *above = w.layer.superlayer;
    return [NSString stringWithFormat:@"; on the screen %@ (its x axis at %.0f deg), in the fixed space %@; window %@ orientation %ld, layers above it %@ %@; SpringBoard's orientation %ld, screen %@",
        NSStringFromCGRect([c convertRect:c.bounds toCoordinateSpace:scr]), atan2(x.y - o.y, x.x - o.x) * 180.0 / M_PI, NSStringFromCGRect([c convertRect:c.bounds toCoordinateSpace:s.fixedCoordinateSpace]),
        NSStringFromCGSize(w.bounds.size), orient(w), tf(above), tf(above.superlayer), orient([UIApplication sharedApplication]), NSStringFromCGSize(s.bounds.size)];
}
// One line per container and case (and bottom inset): the method runs on every layout pass of a menu.
static void DMEditMenuNote(UIView *c, MSBDEditMenuCase why, UIEdgeInsets uikit, UIEdgeInsets mine, CGRect kb, CGRect kbIn) {
    static __weak UIView *lastC; static int lastWhy = -1; static double lastBottom = NAN;
    if (c == lastC && (int)why == lastWhy && (mine.bottom == lastBottom || (isnan(mine.bottom) && isnan(lastBottom)))) return;
    lastC = c; lastWhy = (int)why; lastBottom = mine.bottom;
    UIWindow *w = c.window;
    NSString *more = why == MSBDEditMenuRedo ? [NSString stringWithFormat:@": keyboard %@ in the scene's space, %@ in the container; bottom inset %.1f (UIKit's %.1f)",
                                                NSStringFromCGRect(kb), NSStringFromCGRect(kbIn), mine.bottom, uikit.bottom]
                   : why == MSBDEditMenuNotUIKits ? [NSString stringWithFormat:@": keyboard %@ in the scene's space; UIKit's formula on it %.1f, its answer %.1f", NSStringFromCGRect(kb),
                                                     MSBDEditMenuBottom(c.safeAreaInsets.bottom, CGRectGetMaxY(c.bounds), CGRectGetMinY(kb)), uikit.bottom] : @"";
    if (why == MSBDEditMenuSpacesSame || why == MSBDEditMenuRedo || why == MSBDEditMenuKept) more = [more stringByAppendingString:DMEditMenuLie(c)];
    DMLog([NSString stringWithFormat:@"[editmenu] %s; container %@ in %@ at level %.1f, scene space %@, insets %@%@", MSBDEditMenuCaseText(why), c ? NSStringFromCGRect(c.bounds) : @"-",
           w ? NSStringFromClass([w class]) : @"no window", w.windowLevel, w.windowScene ? NSStringFromCGRect(w.windowScene.coordinateSpace.bounds) : @"-", NSStringFromUIEdgeInsets(uikit), more]);
}
#endif
// The decision, out of line (the piece's): UIKit's answer, or its bottom inset worked out again with the keyboard in the container's space.
__attribute__((noinline)) static UIEdgeInsets DMEditMenuRoom(id presentation, UIEdgeInsets uikit, id configuration) {
    if (!pthread_main_np()) return uikit;   // (UIKit lays its menus out on the main thread)
    MSBDEditMenuCase why = MSBDEditMenuRedo;
    UIEdgeInsets mine = uikit;
    UIView *c = nil; CGRect kb = CGRectNull, kbIn = CGRectNull;
    double safe = 0.0, maxY = 0.0;   // (the container's safe area bottom and bounds' bottom, as UIKit's formula took them)
    @try {
        c = DMEditMenuContainer(presentation);
        UIWindow *w = c.window;
        id<UICoordinateSpace> space = w.windowScene.coordinateSpace;
        CGRect probe = MSBDEditMenuProbe();
        id<DMEditMenuKeyboard> ksd = nil;
#if DEBUG
        if (DMTestFlag("/tmp/msb-editmenu-uikit")) why = MSBDEditMenuKept;   // (debug: UIKit's answer, as 1.8.8.1, for a before and after on the device)
        else
#endif
        if (!c || !w || !space) why = MSBDEditMenuNoContainer;
        else if (MSBDEditMenuSpacesAgree(probe, [space convertRect:probe toCoordinateSpace:c])) why = MSBDEditMenuSpacesSame;
        else if (w.screen != [UIScreen mainScreen]) why = MSBDEditMenuOtherDisplay;   // (the TV: SpringBoard's keyboard is on the iPad's own screen)
        else if (DMEditMenuAsk(w, "_isRemoteKeyboardWindow")) why = MSBDEditMenuRemoteKeyboard;
        else if (configuration && DMEditMenuAsk(configuration, "_ignoresKeyboardAvoidance")) why = MSBDEditMenuIgnoresKeyboard;
        else if (!(ksd = ((id (*)(id, SEL))objc_msgSend)(gDMEditMenuKeyboardClass, sel_registerName("activeKeyboardSceneDelegate"))) || ![ksd isOnScreen]) why = MSBDEditMenuKeyboardOff;
        else if (!DMEditMenuAsk(w, "_isTextEffectsWindow")) why = MSBDEditMenuOtherBranch;
        else if (!MSBDEditMenuKeyboardUsable(kb = [ksd visibleInputViewFrameInView:c])) why = MSBDEditMenuKeyboardUnusable;
        else if (!MSBDEditMenuIsUIKits(uikit.bottom, safe = c.safeAreaInsets.bottom, maxY = CGRectGetMaxY(c.bounds), CGRectGetMinY(kb))) why = MSBDEditMenuNotUIKits;
        else if (!MSBDEditMenuKeyboardUsable(kbIn = [space convertRect:kb toCoordinateSpace:c])) why = MSBDEditMenuKeyboardUnusable;
        else {
            mine.bottom = MSBDEditMenuBottom(safe, maxY, CGRectGetMinY(kbIn));
            DM_FEATURE_MARK("edit-menu-room");
        }
    } @catch (NSException *e) { return uikit; }
#if DEBUG
    DMEditMenuNote(c, why, uikit, mine, kb, kbIn);
#else
    (void)why;   // (the case is only named in a DEBUG line)
#endif
    return mine;
}
// The pass-throughs, one per shape: UIKit's method first (or whoever hooked it before us), then the decision. Transparent for the crash guard.
static UIEdgeInsets (*o_DMEditMenuInsets16)(id, SEL);
static UIEdgeInsets DMEditMenuInsets16(id self, SEL _cmd) {
    UIEdgeInsets uikit = o_DMEditMenuInsets16(self, _cmd);
    return DMEditMenuRoom(self, uikit, nil);
}
static UIEdgeInsets (*o_DMEditMenuInsets18)(id, SEL, id);
static UIEdgeInsets DMEditMenuInsets18(id self, SEL _cmd, id configuration) {
    UIEdgeInsets uikit = o_DMEditMenuInsets18(self, _cmd, configuration);
    return DMEditMenuRoom(self, uikit, configuration);
}
// The method where the class has it itself, not from its superclass: the one place to hook it (iOS 18's _UIEditMenuContentPresentation is a
// _UIEditMenuPresentation).
static Method DMEditMenuOwnMethod(Class c, SEL s) {
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    Class up = c ? class_getSuperclass(c) : Nil;
    return m && (!up || class_getInstanceMethod(up, s) != m) ? m : NULL;
}
// At SpringBoard's start (StatusBar.x %ctor, with the Mac status bar): UIKit's calls the fix makes, each with the shape it calls them with, then
// each shape of the method, where one of the two classes has it itself, with its own type encoding: iPadOS 16's (_UIEditMenuPresentation, no
// argument), the iOS 18 code base's (_UIEditMenuContentPresentation, the configuration), and 17's (read on no Mac here: one of the two, on
// either class), each shape hooked once. Not after a crash in it (the piece on the guard's skip list).
__attribute__((noinline)) static void DMEditMenuRoomInit(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    if (MSBDCrashSkipped(MSBD_EDIT_MENU_PIECE)) { DMLog(@"[editmenu] off after a crash in it (the crash guard's piece editMenuRoom): UIKit's own edit menu room"); return; }
    NSString *obj = DMSMExpect(@encode(id), NULL), *yes = DMSMExpect(@encode(BOOL), NULL), *rect = DMSMExpect(@encode(CGRect), @encode(id), NULL);
    Class ksd = objc_getClass("UIKeyboardSceneDelegate"), win = objc_getClass("UIWindow");
    struct { Class c; const char *sel; BOOL meta; NSString *want; } calls[] = {
        { ksd, "activeKeyboardSceneDelegate", YES, obj }, { ksd, "isOnScreen", NO, yes }, { ksd, "visibleInputViewFrameInView:", NO, rect },
        { win, "_isRemoteKeyboardWindow", NO, yes }, { win, "_isTextEffectsWindow", NO, yes }, { win, "windowScene", NO, obj },
    };
    for (size_t i = 0; i < sizeof(calls) / sizeof(calls[0]); i++) {
        Method m = !calls[i].c ? NULL : calls[i].meta ? class_getClassMethod(calls[i].c, sel_registerName(calls[i].sel)) : class_getInstanceMethod(calls[i].c, sel_registerName(calls[i].sel));
        if (!m || ![DMSMSigOfMethod(m) isEqualToString:calls[i].want]) {
            DMLog([NSString stringWithFormat:@"[editmenu] %s is %s here: UIKit's own edit menu room", calls[i].sel, m ? method_getTypeEncoding(m) : "missing"]);
            return;
        }
    }
    gDMEditMenuKeyboardClass = ksd; gDMEditMenuSigObj = obj; gDMEditMenuSigBool = yes;
    Class classes[2] = { objc_getClass("_UIEditMenuPresentation"), objc_getClass("_UIEditMenuContentPresentation") };
    SEL s16 = sel_registerName("_preferredContentInsetsForContainerView"), s18 = sel_registerName("_preferredContentInsetsForContainerViewWithConfiguration:");
    NSString *want16 = DMSMExpect(@encode(UIEdgeInsets), NULL), *want18 = DMSMExpect(@encode(UIEdgeInsets), @encode(id), NULL);
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (int i = 0; i < 2; i++) for (int k = 0; k < 2; k++) {
        SEL s = k ? s18 : s16;
        Method m = DMEditMenuOwnMethod(classes[i], s);
        if (!m) continue;
        BOOL shape = [DMSMSigOfMethod(m) isEqualToString:k ? want18 : want16], first = k ? !o_DMEditMenuInsets18 : !o_DMEditMenuInsets16;
        if (shape && first && !k) MSHookMessageEx(classes[i], s, (IMP)DMEditMenuInsets16, (IMP *)&o_DMEditMenuInsets16);
        if (shape && first && k) MSHookMessageEx(classes[i], s, (IMP)DMEditMenuInsets18, (IMP *)&o_DMEditMenuInsets18);
        [found addObject:[NSString stringWithFormat:@"-[%s %s] %@", class_getName(classes[i]), sel_getName(s), !shape ? [NSString stringWithFormat:@"of another shape (%s): not hooked", method_getTypeEncoding(m)]
                          : !first ? @"its shape hooked already" : (k ? (void *)o_DMEditMenuInsets18 : (void *)o_DMEditMenuInsets16) ? @"hooked" : @"NOT hooked"]];
    }
    if (o_DMEditMenuInsets16 || o_DMEditMenuInsets18) DM_FEATURE_MARK("edit-menu-room-hook");
    DMLog([NSString stringWithFormat:@"[editmenu] the edit menu's keyboard room in one space: %@", found.count ? [found componentsJoinedByString:@"; "] : @"none of UIKit's shapes here: UIKit's own"]);
}
