// MPAside.h: does another library draw the pointer? (MacPointer in pointeruid, 1.8.8.2, GitHub #17.) Until 1.8.8.1.1 the Mac pointer stood down for
// the whole run as soon as any other jailbreak library had a method on pointeruid's three pointer classes, even a hook that draws nothing, and nothing
// said so: Settings still showed Mac and the round pointer stayed. Such a hook is now only the reason to look; the Mac pointer stands aside while the
// pointer shows something of another library's (MPAsideLook), as two pointers would fight. What counts, on a plain pointer the user can see:
//  - a view or layer of another library's own class in the pointer's views that shows something;
//  - a layer or view directly on the pointer view that shows something and that pointeruid itself does not hold in an object ivar of the pointer
//    view or of its controller (the usual way another pointer is drawn: a shape layer added to the pointer view; ours is left out);
//  - iPadOS's round pointer view hidden by someone else than the Mac pointer.
// Nothing here messages what an ivar holds (read by address only) or uses key-value lookups, and nothing is retained: a crash in pointeruid would
// leave the iPad with no pointer at all. Included by MacPointer.x; the Mac test (tools/test-pointeraside.m) runs it on fake pointer views with a
// library of its own under a "/var/jb/" path, as a tweak's.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif
#include <string.h>
#include "../../common/MacPointerStatus.h"

// A jailbreak's library (rootless: /var/jb, which is /private/preboot/<id>/... on disk).
static inline BOOL MPAsideJailbreakPath(const char *path) { return path && (strstr(path, "/var/jb/") || strstr(path, "/private/preboot/")); }
// This library (MacPointer): its load address.
static inline const void *MPAsideSelfBase(void) {
    static const void *base; static int got;
    if (!got) { Dl_info me; got = 1; base = dladdr((const void *)&MPAsideSelfBase, &me) ? me.dli_fbase : NULL; }
    return base;
}
// The path of the jailbreak library other than ours that holds this address (code, or a class compiled into it); NULL for ours, the system's and
// memory that is in no library (a class made at run time).
static inline const char *MPAsideOtherImageOf(const void *addr) {
    const void *me = MPAsideSelfBase(); Dl_info di;
    if (!me || !addr || !dladdr(addr, &di) || !di.dli_fname || di.dli_fbase == me) return NULL;
    return MPAsideJailbreakPath(di.dli_fname) ? di.dli_fname : NULL;
}
// The methods of pointeruid's pointer classes that lead into another jailbreak library (a hook, or a method added there): how many; the first one's
// library path into firstPath; each one to `each` (the debug log). Read once a run: every tweak is loaded as the process starts.
static inline unsigned MPAsideOtherHooks(char *firstPath, size_t pathSize, void (^each)(const char *cls, SEL sel, const char *path)) {
    static const char *const names[] = { "PUIDPointerShapeView", "PUIDPointerRenderingRootViewController", "PUIDPointerController" };
    unsigned hits = 0;
    if (firstPath && pathSize) firstPath[0] = 0;
    for (int k = 0; k < 3; k++) {
        Class c = objc_getClass(names[k]); if (!c) continue;
        unsigned n = 0; Method *ms = class_copyMethodList(c, &n);
        for (unsigned i = 0; i < n; i++) {
            const void *imp = (const void *)method_getImplementation(ms[i]);
#if __has_feature(ptrauth_calls)
            imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
            const char *path = MPAsideOtherImageOf(imp);
            if (!path) continue;
            if (!hits && firstPath && pathSize) strlcpy(firstPath, path, pathSize);
            hits++;
            if (each) each(names[k], method_getName(ms[i]), path);
        }
        free(ms);
    }
    return hits;
}
// A class compiled into another jailbreak library (kept per class: the lookup walks the loaded libraries).
static inline BOOL MPAsideClassIsOther(Class c) {
    static CFMutableDictionaryRef known;
    if (!c) return NO;
    if (!known) known = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    const void *v = NULL;
    if (CFDictionaryGetValueIfPresent(known, (__bridge const void *)c, &v)) return v == (const void *)1;
    BOOL other = MPAsideOtherImageOf((__bridge const void *)c) != NULL;
    CFDictionarySetValue(known, (__bridge const void *)c, other ? (const void *)1 : (const void *)2);
    return other;
}
// A layer that shows something: not hidden or see-through, with an image, a fill, a border, a path, text, or such a layer inside it.
static inline BOOL MPAsideLayerShows(CALayer *l, int depth) {
    if (!l || l.hidden || l.opacity < 0.01f || depth > 6) return NO;
    if (l.contents) return YES;
    if (l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0.01) return YES;
    if (l.borderWidth > 0 && l.borderColor && CGColorGetAlpha(l.borderColor) > 0.01) return YES;
    if ([l isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *s = (CAShapeLayer *)l;
        if (s.path && !CGPathIsEmpty(s.path) && ((s.fillColor && CGColorGetAlpha(s.fillColor) > 0.01) || (s.strokeColor && CGColorGetAlpha(s.strokeColor) > 0.01 && s.lineWidth > 0))) return YES;
    }
    if ([l isKindOfClass:[CATextLayer class]] && ((CATextLayer *)l).string) return YES;
    for (CALayer *sub in l.sublayers) if (MPAsideLayerShows(sub, depth + 1)) return YES;
    return NO;
}
static inline BOOL MPAsideViewShows(UIView *v) {
    if (!v || v.hidden || v.alpha < 0.01) return NO;
    if ([v isKindOfClass:[UIImageView class]] && ((UIImageView *)v).image) return YES;
    return MPAsideLayerShows(v.layer, 0);
}
// What an object's own classes hold in their object ivars (from its class down to, not including, `stop`): the addresses, read straight from the
// ivars (nothing retained or messaged: an unretained ivar may point at an object already gone).
static inline int MPAsideHeldBy(id obj, Class stop, const void **out, int n, int max) {
    if (!obj) return n;
    for (Class c = object_getClass(obj); c && c != stop && n < max; c = class_getSuperclass(c)) {
        unsigned count = 0; Ivar *iv = class_copyIvarList(c, &count);
        for (unsigned i = 0; i < count && n < max; i++) {
            const char *t = ivar_getTypeEncoding(iv[i]);
            if (!t || t[0] != '@') continue;
            const void *raw = *(const void *const *)((const uint8_t *)(__bridge const void *)obj + ivar_getOffset(iv[i]));
            if (raw) out[n++] = raw;
        }
        free(iv);
    }
    return n;
}
static inline BOOL MPAsideIn(const void *p, const void *const *set, int n) { if (!p) return NO; for (int i = 0; i < n; i++) if (set[i] == p) return YES; return NO; }
// A view or layer of another library's class that shows something, in the tree under `layer` (at most *left layers looked at).
static inline BOOL MPAsideTreeHasOther(CALayer *layer, int depth, int *left) {
    if (!layer || depth > 12 || *left <= 0) return NO;
    (*left)--;
    id d = layer.delegate;   // (weak: the layer's view, or nil)
    BOOL isView = [d isKindOfClass:[UIView class]];
    if (MPAsideClassIsOther(object_getClass(layer)) || (isView && MPAsideClassIsOther(object_getClass(d)))) {
        if (isView ? MPAsideViewShows(d) : MPAsideLayerShows(layer, 0)) return YES;
    }
    for (CALayer *sub in layer.sublayers) if (MPAsideTreeHasOther(sub, depth + 1, left)) return YES;
    return NO;
}
// One look (MSBD_MP_SEEN_* bits; 0: nothing of another pointer). view: the pointer view (PUIDPointerShapeView); controller: its rendering
// controller or nil; root: the controller's root view (or nil: the pointer view's tree only); ours: the Mac pointer's own layer on it; weHid: the
// views the Mac pointer hid itself. Main thread.
static inline unsigned MPAsideSeen(UIView *view, UIViewController *controller, UIView *root, CALayer *ours, NSArray *weHid) {
    if (!view) return 0;
    unsigned seen = 0;
    int left = 400;
    if (MPAsideTreeHasOther((root ?: view).layer, 0, &left)) seen |= MSBD_MP_SEEN_CLASS;
    const void *held[96]; int n = MPAsideHeldBy(view, [UIView class], held, 0, 96);
    n = MPAsideHeldBy(controller, [UIViewController class], held, n, 96);
    for (CALayer *l in view.layer.sublayers) {
        if (l == ours) continue;
        id d = l.delegate;
        if (MPAsideIn((__bridge const void *)l, held, n) || MPAsideIn((__bridge const void *)d, held, n)) continue;
        if ([d isKindOfClass:[UIView class]] ? MPAsideViewShows(d) : MPAsideLayerShows(l, 0)) { seen |= MSBD_MP_SEEN_LAYER; break; }
    }
    Ivar iv = class_getInstanceVariable(object_getClass(view), "_pointerView");
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    UIView *round = (t && t[0] == '@') ? object_getIvar(view, iv) : nil;
    if ([round isKindOfClass:[UIView class]] && (round.hidden || round.layer.hidden) && ![weHid containsObject:round]) seen |= MSBD_MP_SEEN_ROUND_HIDDEN;
    return seen;
}
// The parts of iPadOS's pointer that MacPointer uses, for these classes (MSBD_MP_MISS_* bits of the ones not there).
static inline BOOL MPAsideHasIvar(Class c, const char *name) { return c && class_getInstanceVariable(c, name) != NULL; }
static inline unsigned MPAsideMissingIn(Class shapeView, Class rootVC, Class controller) {
    unsigned m = 0;
    if (!shapeView) m |= MSBD_MP_MISS_SHAPEVIEW | MSBD_MP_MISS_SETSHAPE | MSBD_MP_MISS_ROUNDVIEW | MSBD_MP_MISS_SHAPE;
    else {
        if (!class_getInstanceMethod(shapeView, NSSelectorFromString(@"setPointerShape:animated:completion:"))) m |= MSBD_MP_MISS_SETSHAPE;
        // (as MacPointer finds it: the ivar, or what a key-value lookup of "_pointerView" would read)
        if (!MPAsideHasIvar(shapeView, "_pointerView") && !MPAsideHasIvar(shapeView, "__pointerView") && !class_getInstanceMethod(shapeView, NSSelectorFromString(@"_pointerView"))) m |= MSBD_MP_MISS_ROUNDVIEW;
        if (!MPAsideHasIvar(shapeView, "_pointerShape") && !class_getInstanceMethod(shapeView, NSSelectorFromString(@"pointerShape"))) m |= MSBD_MP_MISS_SHAPE;
    }
    if (!rootVC) m |= MSBD_MP_MISS_ROOTVC | MSBD_MP_MISS_SETSTATE | MSBD_MP_MISS_HIDE | MSBD_MP_MISS_MAINVIEW | MSBD_MP_MISS_VISIBILITY | MSBD_MP_MISS_ROOTVIEW;
    else {
        if (!class_getInstanceMethod(rootVC, NSSelectorFromString(@"setPointerState:options:updateHandlerCollection:error:"))) m |= MSBD_MP_MISS_SETSTATE;
        if (!class_getInstanceMethod(rootVC, NSSelectorFromString(@"hidePointer"))) m |= MSBD_MP_MISS_HIDE;
        if (!MPAsideHasIvar(rootVC, "_pointerShapeView")) m |= MSBD_MP_MISS_MAINVIEW;
        if (!MPAsideHasIvar(rootVC, "_visibilityState")) m |= MSBD_MP_MISS_VISIBILITY;
        if (!MPAsideHasIvar(rootVC, "_pointerRootView")) m |= MSBD_MP_MISS_ROOTVIEW;
    }
    if (!controller) m |= MSBD_MP_MISS_CONTROLLER;
    return m;
}
static inline unsigned MPAsideMissing(void) {
    return MPAsideMissingIn(objc_getClass("PUIDPointerShapeView"), objc_getClass("PUIDPointerRenderingRootViewController"), objc_getClass("PUIDPointerController"));
}
