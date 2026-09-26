// MacPointer: the Mac pointer, a macOS-style cursor for the iPad (M1 pipeline C6, 2026-09-24; our own implementation).
// Loads only into pointeruid, the daemon that draws the iPad pointer. How it works (all found by looking at pointeruid's own classes at runtime):
//  - PUIDPointerShapeView is the pointer. For the plain pointer its PSPointerShape has shapeType 1 and the renderer's state has empty content
//    bounds; its frame origin is the pointer position. While the pointer hovers something (buttons get a highlight, icons "lift", text gets a beam),
//    the state has content bounds or a different shape, and the system morphs its own pointer into that effect.
//  - So: while the pointer is plain we hide the system's round pointer (its _pointerView) and draw the Mac pointer (a CAShapeLayer whose origin is the
//    pointer position, i.e. the cursor's tip); during every hover effect the Mac pointer goes away and the system's effect is left exactly as it is.
//  - pointeruid draws in the display's native portrait space; the Mac pointer is turned for the current interface orientation, which SpringBoard (Mac
//    Status Bar) publishes with the settings as Darwin notification states (pointeruid is sandboxed: no files, no preferences of ours).
//  - Settings > Pointer: Pointer Style (Mac/iPadOS) and Hide in Virtual Mac; the size is the system's own Pointer Size.
//  - Stands down entirely when another tweak also changes pointeruid's pointer (two custom pointers would fight): MPOtherPointerTweak.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#if __has_include(<ptrauth.h>)
#include <ptrauth.h>
#endif
#include <notify.h>
#include "MPDisplayGeometry.h"
@interface PSPointerShape : NSObject
- (long long)shapeType; - (CGRect)bounds; - (double)cornerRadius; - (CGPathRef)path;
@end

#if DEBUG   // (the whole debug channel below -- in-memory log, dumps, pointer capture, the cmd/page notifications -- exists only in debug builds)
// pointeruid is sandboxed and cannot write files: debug text goes into an in-memory buffer that SpringBoard (MacStatusBar's mpdump_ trigger) pulls
// through Darwin notification states, 64 x 8 bytes a page.
static NSMutableData *gMPOut;
static NSMutableString *gMPLive;   // a running log, kept to the last 64 KB
static void MPLog(NSString *line) {
    if (!gMPLive) gMPLive = [NSMutableString string];
    [gMPLive appendString:line]; [gMPLive appendString:@"\n"];
    if (gMPLive.length > 65536) [gMPLive deleteCharactersInRange:NSMakeRange(0, gMPLive.length - 65536)];
}
static void MPServePage(void) {
    static int tReq, tAck, tBuf[64]; static BOOL ready;
    if (!ready) { ready = YES; notify_register_check("com.besiktasliseba.macpointer.pagereq", &tReq); notify_register_check("com.besiktasliseba.macpointer.pageack", &tAck);
        for (int i = 0; i < 64; i++) { char nm[64]; snprintf(nm, sizeof nm, "com.besiktasliseba.macpointer.buf.%d", i); notify_register_check(nm, &tBuf[i]); } }
    uint64_t page = 0; notify_get_state(tReq, &page);
    for (int i = 0; i < 64; i++) {
        uint64_t v = 0; NSUInteger off = (NSUInteger)page * 512 + i * 8;
        if (off < gMPOut.length) memcpy(&v, (const uint8_t *)gMPOut.bytes + off, MIN((NSUInteger)8, gMPOut.length - off));
        notify_set_state(tBuf[i], v);
    }
    notify_set_state(tAck, page + 1);
}
static void MPDumpClass(Class c) {
    NSMutableString *m = [NSMutableString stringWithFormat:@"CLASS %s : %s\n", class_getName(c), class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "-"];
    unsigned n = 0; Ivar *iv = class_copyIvarList(c, &n);
    for (unsigned i = 0; i < n; i++) [m appendFormat:@"  ivar %s %s\n", ivar_getName(iv[i]), ivar_getTypeEncoding(iv[i])];
    free(iv);
    Method *ms = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) [m appendFormat:@"  - %@ %s\n", NSStringFromSelector(method_getName(ms[i])), method_getTypeEncoding(ms[i])];
    free(ms);
    objc_property_t *ps = class_copyPropertyList(c, &n);
    for (unsigned i = 0; i < n; i++) [m appendFormat:@"  @prop %s %s\n", property_getName(ps[i]), property_getAttributes(ps[i])];
    free(ps);
    MPLog(m);
}
static void MPDumpAll(void);
static void MPDumpTree(void);
static NSData *MPPointerCapture(BOOL stateOnly);
static void MPHandleCommand(void) {
    static int tCmd, tLen; static BOOL ready;
    if (!ready) { ready = YES; notify_register_check("com.besiktasliseba.macpointer.cmdarg", &tCmd); notify_register_check("com.besiktasliseba.macpointer.len", &tLen); }
    uint64_t c = 0; notify_get_state(tCmd, &c);
    NSString *saved = gMPLive; gMPLive = [NSMutableString string];
    if (c == 1) MPDumpAll(); else if (c == 2) MPDumpTree();
    if (c == 4 || c == 5) {   // 4: a 2x picture of the 90 x 90 pt around the pointer (layers only: system backdrops draw blank); 5: Mac pointer state
        gMPLive = [saved mutableCopy] ?: [NSMutableString string];
        NSData *out = MPPointerCapture(c == 5);
        gMPOut = [out mutableCopy] ?: [NSMutableData data];
        notify_set_state(tLen, MAX((uint64_t)1, (uint64_t)gMPOut.length));
        return;
    }
    NSString *text = (c == 3 || c == 0) ? (saved ?: @"") : gMPLive;
    if (c == 1 || c == 2) gMPLive = [saved mutableCopy] ?: [NSMutableString string]; else gMPLive = [NSMutableString string];
    gMPOut = [[text dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    notify_set_state(tLen, MAX((uint64_t)1, (uint64_t)gMPOut.length));
}
static void MPTreeLayer(CALayer *l, int depth, NSMutableString *m) {
    [m appendFormat:@"%*s%@ %p frame %@ hidden %d opacity %.2f%@\n", depth * 2, "", NSStringFromClass([l class]), l, NSStringFromCGRect(l.frame), l.hidden, l.opacity,
        [l.delegate isKindOfClass:[UIView class]] ? [NSString stringWithFormat:@" (view %@)", NSStringFromClass([(id)l.delegate class])] : @""];
    if ([l isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer *)l).path) { CAShapeLayer *sl = (CAShapeLayer *)l; CATransform3D t = l.transform;
        [m appendFormat:@"%*s  path box %@ line %.2f fill %@ stroke %@ transform a%.2f b%.2f c%.2f d%.2f shadow %.2f r%.1f\n", depth * 2, "", NSStringFromCGRect(CGPathGetBoundingBox(sl.path)), sl.lineWidth, sl.fillColor ? [UIColor colorWithCGColor:sl.fillColor] : nil, sl.strokeColor ? [UIColor colorWithCGColor:sl.strokeColor] : nil, t.m11, t.m12, t.m21, t.m22, l.shadowOpacity, l.shadowRadius]; }
    if (depth < 12) for (CALayer *s in l.sublayers) MPTreeLayer(s, depth + 1, m);
}
static void MPDumpTree(void) {
    NSMutableString *m = [NSMutableString string];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIApplication sharedApplication].windows) { [m appendFormat:@"WINDOW %@ %@ hidden %d\n", NSStringFromClass([w class]), NSStringFromCGRect(w.frame), w.hidden]; MPTreeLayer(w.layer, 1, m); }
#pragma clang diagnostic pop
    MPLog(m);
}
static void MPDumpAll(void) {
    MPLog([NSString stringWithFormat:@"=== dump pid %d", getpid()]);
    unsigned count = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *img = _dyld_get_image_name(i);
        if (!strstr(img, "PointerUI") && !strstr(img, "pointeruid")) continue;
        const char **names = objc_copyClassNamesForImage(img, &count);
        MPLog([NSString stringWithFormat:@"image %s: %u classes", img, count]);
        for (unsigned k = 0; k < count; k++) { Class c = objc_getClass(names[k]); if (c) MPDumpClass(c); }
        free(names);
    }
}
static void __attribute__((unused)) MPProbePaths(void) {
    NSArray *paths = @[@"/var/tmp/macpointer.log", @"/tmp/macpointer.log", [NSTemporaryDirectory() stringByAppendingPathComponent:@"macpointer.log"],
        @"/var/mobile/Library/Caches/macpointer.log", @"/var/mobile/Library/Logs/macpointer.log", @"/var/mobile/Library/Caches/com.apple.PointerUI.pointeruid/macpointer.log",
        [NSHomeDirectory() stringByAppendingPathComponent:@"macpointer.log"], @"/var/mobile/Library/Preferences/macpointer.log"];
    uint64_t bits = 0;
    for (NSUInteger i = 0; i < paths.count; i++) if ([@"x" writeToFile:paths[i] atomically:NO encoding:NSUTF8StringEncoding error:nil]) bits |= (1ULL << i);
    int t = 0; notify_register_check("com.besiktasliseba.macpointer.paths", &t); notify_set_state(t, bits | ((uint64_t)getpid() << 16));
}
#endif
// ===== the Mac pointer =============================================================================================================
@interface PUIDPointerShapeView : UIView @end
static int gMPConfigToken, gMPOrientToken, gMPHideToken;
static BOOL gMPStandDown = NO;          // another tweak changes the pointer in this process (MPOtherPointerTweak)
static BOOL gMPHovering = NO;           // the renderer's state has content (a hover effect is showing)
static __weak PUIDPointerShapeView *gMPShapeView;
static NSHashTable *gMPShapeViews;     // every pointer view seen (one per display with an external display), weak
static void MPRemember(PUIDPointerShapeView *v) { if (!gMPShapeViews) gMPShapeViews = [NSHashTable weakObjectsHashTable]; if (v) [gMPShapeViews addObject:v]; }
static void MPUpdate(PUIDPointerShapeView *view);
static void MPUpdateAll(void) { MPUpdate(gMPShapeView); for (PUIDPointerShapeView *v in [gMPShapeViews allObjects]) if (v != gMPShapeView) MPUpdate(v); }
#if DEBUG
static const void *kMPClientTurnKey = &kMPClientTurnKey;
#endif
static __weak UIViewController *gMPController;
static BOOL gMPWeHidRoot = NO;
static const void *kMPCursorKey = &kMPCursorKey, *kMPHidNativeKey = &kMPHidNativeKey;
static uint64_t MPState(int token) { uint64_t v = 0; if (token) notify_get_state(token, &v); return v; }
// 0 = Mac Status Bar's bridge in SpringBoard is not publishing (not started yet, or Mac Status Bar switched off in Choicy/iCleaner): the stock pointer.
// (Its orientation comes from the same bridge; without it the Mac pointer would be drawn sideways -- seen with Mac Status Bar switched off in Choicy.)
// Another tweak that also changes pointeruid's pointer would fight the Mac pointer: found by where pointeruid's own pointer classes' methods lead --
// into a jailbreak library other than this one (a hook) -> the Mac pointer stands down and the other tweak has the pointer. Checked once, at the
// first pointer update (every tweak is loaded by then).
static BOOL MPOtherPointerTweak(void) {
    Dl_info me; if (!dladdr((const void *)&MPOtherPointerTweak, &me)) return NO;
    for (NSString *cn in @[@"PUIDPointerShapeView", @"PUIDPointerRenderingRootViewController", @"PUIDPointerController"]) {
        Class c = objc_getClass(cn.UTF8String); if (!c) continue;
        unsigned n = 0; Method *ms = class_copyMethodList(c, &n);
        for (unsigned i = 0; i < n; i++) {
            const void *imp = (const void *)method_getImplementation(ms[i]);
#if __has_feature(ptrauth_calls)
            imp = ptrauth_strip(imp, ptrauth_key_function_pointer);
#endif
            Dl_info di;
            if (dladdr(imp, &di) && di.dli_fname && di.dli_fbase != me.dli_fbase && (strstr(di.dli_fname, "/var/jb/") || strstr(di.dli_fname, "/private/preboot/"))) {
#if DEBUG
                MPLog([NSString stringWithFormat:@"stand down: -[%@ %@] is changed by %s", cn, NSStringFromSelector(method_getName(ms[i])), di.dli_fname]);
#endif
                free(ms); return YES;
            }
        }
        free(ms);
    }
    return NO;
}
static BOOL MPEnabled(void) {
    static BOOL checked = NO;
    if (!checked) { checked = YES; gMPStandDown = MPOtherPointerTweak(); }
    uint64_t c = MPState(gMPConfigToken); return !gMPStandDown && c != 0 && (c & 1) && MPState(gMPOrientToken) != 0;
}
// The Mac pointer's size follows the system's own Pointer Size (Settings > Pointer, Apple's slider: com.apple.Accessibility PointerSizeMultiplier, 1-5),
// the same setting pointeruid sizes its round pointer by; our own size setting is gone (2026-09-25). Read once and again whenever pointeruid itself
// is told the size changed (-[PUIDPointerController _handleAccessibilityPointerSizePreferencesDidChange], hooked below).
static double gMPNativeSize = 0;   // 0 = read it again
static double MPSize(UIView *view) {
    if (gMPNativeSize <= 0) {
        CFPreferencesAppSynchronize(CFSTR("com.apple.Accessibility"));
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("PointerSizeMultiplier"), CFSTR("com.apple.Accessibility"));
        double m = 1.0;
        if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &m);
        if (v) CFRelease(v);
        gMPNativeSize = (m >= 1.0 && m <= 5.0) ? m : 1.0;
    }
    return gMPNativeSize;
}
// The cursor shape, drawn in points with its tip at (0, 0): the classic macOS shape (black with a white edge and a short tail).
static CGPathRef MPCursorPath(void) {
    static CGPathRef path;
    if (!path) {
        CGMutablePathRef p = CGPathCreateMutable();
        CGPoint pts[] = { {0, 0}, {0, 17.2}, {4.1, 13.3}, {6.9, 19.6}, {9.6, 18.4}, {6.9, 12.3}, {12.4, 12.3} };
        CGPathMoveToPoint(p, NULL, pts[0].x, pts[0].y);
        for (int i = 1; i < 7; i++) CGPathAddLineToPoint(p, NULL, pts[i].x, pts[i].y);
        CGPathCloseSubpath(p);
        path = p;
    }
    return path;
}
static CAShapeLayer *MPCursorLayer(UIView *view) {
    CAShapeLayer *a = objc_getAssociatedObject(view, kMPCursorKey);
    if (a) return a;
    a = [CAShapeLayer layer];
    a.path = MPCursorPath();
    a.fillColor = [UIColor blackColor].CGColor;
    a.strokeColor = [UIColor whiteColor].CGColor;
    a.lineWidth = 1.25;
    a.lineJoin = kCALineJoinRound;
    a.shadowColor = [UIColor blackColor].CGColor;
    a.shadowOpacity = 0.35;
    a.shadowRadius = 1.6;
    a.shadowOffset = CGSizeZero;   // (no offset: the layer is turned with the screen, an offset would point sideways in landscape)
    a.contentsScale = [UIScreen mainScreen].scale;
    a.zPosition = 1000;
    objc_setAssociatedObject(view, kMPCursorKey, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return a;
}
static CGFloat MPRotation(void) {   // interface orientation -> turn of the Mac pointer in pointeruid's portrait space
    switch (MPState(gMPOrientToken)) { case 3: return M_PI_2; case 4: return -M_PI_2; case 2: return M_PI; default: return 0; }
}
// External display (iPad 2 + TV on iPadOS 16, 2026-09-26: the Mac pointer was sideways on the TV and turned whenever the iPad was turned; after
// the first fix still sideways while the iPad was in landscape). The iPad's interface orientation only applies to the pointer drawn on the iPad's
// own display; on another display the pointer is drawn upright in that display's own fixed space. Which display: by the window's screen object, its
// pixel size, or the window's size either way round (MPOtherDisplayReason) -- nothing that changes when the iPad turns (the first fix's shape rule
// only held while pointeruid's main screen was portrait-shaped). Unknown (no window): the iPad.
typedef struct { int reason, inWindow, windowLayers, screen; BOOL inWindowOK, screenOK; } MPDisplayInfo;
static int MPTurnsBetween(CGPoint o, CGPoint x, BOOL *ok) { bool v = false; int q = MPQuarterTurns(x.x - o.x, x.y - o.y, &v); if (ok) *ok = v; return q; }
static MPDisplayInfo MPDisplayInfoFor(UIView *view) {
    MPDisplayInfo d = {0};
    UIWindow *w = view.window;
    if (!w) return d;
    UIScreen *main = [UIScreen mainScreen], *s = nil;
    @try { s = w.screen; } @catch (id e) {}
    CGSize sn = s ? s.nativeBounds.size : CGSizeZero, mn = main ? main.nativeBounds.size : CGSizeZero, ws = w.bounds.size, ms = main ? main.bounds.size : CGSizeZero;
    d.reason = MPOtherDisplayReason(YES, s != nil && main != nil, s == main, sn.width, sn.height, mn.width, mn.height, ws.width, ws.height, ms.width, ms.height);
    // the turns between the pointer and the display: inside the window (pointeruid's own views), the window's layer and any layer above it, and the
    // screen's interface turn (its coordinate space against its fixed space). Measured on the iPad too (for the debug dump); only another display uses them.
    d.inWindow = MPTurnsBetween([view convertPoint:CGPointZero toView:nil], [view convertPoint:CGPointMake(100.0, 0.0) toView:nil], &d.inWindowOK);
    double a = 0;
    for (CALayer *l = w.layer; l; l = l.superlayer) {
        CGAffineTransform t = l.affineTransform; a += atan2(t.b, t.a);
        if (l.superlayer) { CATransform3D st = l.superlayer.sublayerTransform; a += atan2(st.m12, st.m11); }
    }
    d.windowLayers = MPNormTurns((int)lround(a / M_PI_2));
    if (s) {
        id<UICoordinateSpace> cs = s.coordinateSpace, fs = s.fixedCoordinateSpace;
        d.screen = MPTurnsBetween([cs convertPoint:CGPointZero toCoordinateSpace:fs], [cs convertPoint:CGPointMake(100.0, 0.0) toCoordinateSpace:fs], &d.screenOK);
    }
    return d;
}
static CGFloat MPRotationFor(UIView *view) {
    MPDisplayInfo d = MPDisplayInfoFor(view);
    return d.reason ? MPOtherDisplayAngle(d.inWindow, d.windowLayers, d.screen) : MPRotation();
}
// What the pointer shows (observed on the M1 with the owner's Pointer Control settings):
//  - the round pointer (PSPointerShape type 1 -- also while it hovers a button, an icon or our status bar, where the system keeps the circle and
//    only lifts or highlights the content): the Mac pointer, the circle and its accessibility ring hidden;
//  - the text I-beam (type 3, a thin bar): the system's beam, no Mac pointer;
//  - any other shape the system morphs into (a button's highlight shape when Pointer Animations is on): the system's shape stays as a highlight
//    behind the Mac pointer.
// Auto-hide: when the system hides the pointer (idle, a touch on the screen, typing), the Mac pointer fades out with it, completely, and comes back at once.
static BOOL gMPAutoHidden = NO;
static void MPUpdate(PUIDPointerShapeView *view) {
    if (!view) return;
    PSPointerShape *shape = nil; @try { shape = [view valueForKey:@"pointerShape"]; } @catch (id e) {}
    long long type = shape ? shape.shapeType : 1;
    CGRect sb = shape ? shape.bounds : CGRectZero;
    BOOL beam = type == 3 || (!CGRectIsEmpty(sb) && MIN(sb.size.width, sb.size.height) <= 4.0);
    BOOL round = type == 1;
    BOOL want = MPEnabled() && !beam;
    BOOL hideNative = want && round;
    CAShapeLayer *a = want ? MPCursorLayer(view) : objc_getAssociatedObject(view, kMPCursorKey);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (want) {
        if (a.superlayer != view.layer) [view.layer addSublayer:a];
        a.position = CGPointZero;
        a.bounds = CGRectZero;
        a.anchorPoint = CGPointZero;
        CGFloat k = MPSize(view) * 1.12;   // 1.0 = about 22 pt tall on screen, the size the owner tuned the old cursor to
        a.affineTransform = CGAffineTransformScale(CGAffineTransformMakeRotation(MPRotationFor(view)), k, k);
        a.hidden = NO;
        [view.layer insertSublayer:a atIndex:(unsigned)view.layer.sublayers.count];   // (on top of a highlight shape)
    } else a.hidden = YES;
    // the system's round pointer and its accessibility ring/dot (Settings > Accessibility > Pointer Control) hidden only while the Mac pointer replaces it
    NSMutableArray *hid = objc_getAssociatedObject(view, kMPHidNativeKey) ?: [NSMutableArray array];
    if (hideNative) {
        for (NSString *k in @[@"_pointerView", @"_axColorStroke", @"_axCenterDot"]) {
            UIView *v = nil; @try { v = [view valueForKey:k]; } @catch (id e) {}
            if ([v isKindOfClass:[UIView class]] && !v.layer.hidden) { v.layer.hidden = YES; if (![hid containsObject:v]) [hid addObject:v]; }
        }
        objc_setAssociatedObject(view, kMPHidNativeKey, hid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (hid.count) {   // give the system pointer back: only what we hid
        for (UIView *v in hid) v.layer.hidden = NO;
        objc_setAssociatedObject(view, kMPHidNativeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction commit];
    // auto-hide: fade out completely with the system (0.35 s), back at once
    if (a && !a.hidden) {
        float target = gMPAutoHidden ? 0.0f : 1.0f;
        if (a.opacity != target) {
            if (gMPAutoHidden) {
                CABasicAnimation *f = [CABasicAnimation animationWithKeyPath:@"opacity"];
                f.fromValue = @(a.presentationLayer ? a.presentationLayer.opacity : a.opacity); f.toValue = @0; f.duration = 0.35;
                f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [a addAnimation:f forKey:@"mpfade"];
            } else [a removeAnimationForKey:@"mpfade"];
            [CATransaction begin]; [CATransaction setDisableActions:YES]; a.opacity = target; [CATransaction commit];
        }
    }
}
// Hide in Virtual Mac: never write the root view's hidden unless we hid it (the system fades the pointer out with it).
static void MPApplyVisibility(void) {
    UIViewController *c = gMPController; if (!c || gMPStandDown) return;
    UIView *root = nil; @try { root = [c valueForKey:@"_pointerRootView"]; } @catch (id e) {}
    if (![root isKindOfClass:[UIView class]]) return;
    if (MPState(gMPHideToken) == 1) { if (!root.hidden) root.hidden = YES; gMPWeHidRoot = YES; }
    else if (gMPWeHidRoot) { root.hidden = NO; gMPWeHidRoot = NO; }
}

// ---- where the pointer is, for Mac Status Bar's auto-hiding status bar (config bit 2 set by the bridge while that is on) ------------------------
%hook PUIDPointerShapeView
- (void)setIntensity:(double)i {
#if DEBUG
    MPLog([NSString stringWithFormat:@"%.3f setIntensity %.2f (was %.2f)", CACurrentMediaTime(), i, [[(id)self valueForKey:@"intensity"] doubleValue]]);
#endif
    %orig;
}
- (void)layoutSubviews {
    %orig;
    gMPShapeView = (PUIDPointerShapeView *)self;
    MPRemember((PUIDPointerShapeView *)self);
    MPUpdate((PUIDPointerShapeView *)self);
}
- (void)setPointerShape:(id)shapeObj animated:(BOOL)animated completion:(id)completion {
#if DEBUG
    PSPointerShape *shape = shapeObj;
    MPLog([NSString stringWithFormat:@"%.3f setPointerShape type %lld bounds %@ r%.1f animated %d at %@", CACurrentMediaTime(), shape.shapeType, NSStringFromCGRect(shape.bounds), shape.cornerRadius, animated, NSStringFromCGPoint(((UIView *)self).frame.origin)]);
#endif
    %orig;
    gMPShapeView = (PUIDPointerShapeView *)self;
    MPRemember((PUIDPointerShapeView *)self);
    MPUpdate((PUIDPointerShapeView *)self);
}
%end
%hook PUIDPointerRenderingRootViewController
- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error {
    CGRect content = CGRectZero; @try { content = [[state valueForKey:@"contentBounds"] CGRectValue]; } @catch (id e) {}
    gMPHovering = !CGRectIsEmpty(content);
    @try { gMPAutoHidden = [[state valueForKey:@"pointerAutoHidden"] boolValue]; } @catch (id e) {}
#if DEBUG
    static NSString *last;
    PSPointerShape *sh = [state valueForKey:@"pointerShape"];
    NSString *sig = [NSString stringWithFormat:@"shape %lld %@ r%.1f content %@ overlay %@ autohidden %@ pressed %@ client %@", sh.shapeType, NSStringFromCGRect(sh.bounds), sh.cornerRadius,
        NSStringFromCGRect(content), [state valueForKey:@"overlayEffectStyle"], [state valueForKey:@"pointerAutoHidden"], [state valueForKey:@"pressed"], [state valueForKey:@"debugRequestingClientString"]];
    if (![sig isEqualToString:last]) { last = sig; MPLog([NSString stringWithFormat:@"%.3f state %@", CACurrentMediaTime(), sig]); }
#endif
    BOOL r = %orig;
    gMPController = (UIViewController *)self;
    MPUpdate(gMPShapeView);
    // (with an external display each display has its own controller and pointer view: update this controller's own view too)
    PUIDPointerShapeView *own = nil; @try { own = [(id)self valueForKey:@"_pointerShapeView"]; } @catch (id e) {}
    if ([own isKindOfClass:[UIView class]] && own != gMPShapeView) { MPRemember(own); MPUpdate(own); }
#if DEBUG   // the turn of the client's coordinate space to the display (evidence for the external display: which way pointeruid thinks is up)
    if ([own isKindOfClass:[UIView class]]) { @try { CATransform3D ct = [[state valueForKey:@"clientCoordinateSpaceTransformToDisplay"] CATransform3DValue];
        bool ok = false; int q = MPQuarterTurns(ct.m11, ct.m12, &ok); objc_setAssociatedObject(own, kMPClientTurnKey, ok ? @(q) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } @catch (id e) {} }
#endif
    MPApplyVisibility();
    return r;
}
%end
// Apple's Pointer Size changed: the Mac pointer takes the new size at once (pointeruid is told through this same method).
%hook PUIDPointerController
- (void)_handleAccessibilityPointerSizePreferencesDidChange {
    %orig;
    gMPNativeSize = 0;
    dispatch_async(dispatch_get_main_queue(), ^{ MPUpdateAll(); });
}
%end

#if DEBUG
static NSData *MPPointerCapture(BOOL stateOnly) {
    UIView *sv = gMPShapeView; UIView *win = sv.window;
    if (!win) { win = sv; while (win.superview) win = win.superview; if (win == sv) win = nil; }
    CAShapeLayer *a = sv ? objc_getAssociatedObject(sv, kMPCursorKey) : nil;
    UIView *native = nil; @try { native = [sv valueForKey:@"_pointerView"]; } @catch (id e) {}
    PSPointerShape *shape = nil; @try { shape = [sv valueForKey:@"pointerShape"]; } @catch (id e) {}
    if (stateOnly && access("/dev/null", F_OK) == 0 && gMPShapeView) {   // (ancestor chain: model/presentation opacity and running animations)
        NSMutableString *chain = [NSMutableString string];
        for (UIView *v = gMPShapeView; v; v = v.superview) {
            CALayer *l = v.layer, *p = l.presentationLayer;
            [chain appendFormat:@" | %@ f%@ pos%@ ppos%@ t[%.1f %.1f] a%.2f o%.2f p%.2f h%d anim[%@]", NSStringFromClass([v class]), NSStringFromCGRect(v.frame), NSStringFromCGPoint(l.position), NSStringFromCGPoint(p ? p.position : CGPointZero), l.transform.m41, l.transform.m42, v.alpha, l.opacity, p ? p.opacity : -1, v.hidden, [[l animationKeys] componentsJoinedByString:@","]];
        }
        double pi = -1; @try { pi = [[gMPShapeView valueForKey:@"presentationIntensity"] doubleValue]; } @catch (id e) {}
        double in0 = -1; @try { in0 = [[gMPShapeView valueForKey:@"intensity"] doubleValue]; } @catch (id e) {}
        MPLog([NSString stringWithFormat:@"chain: intensity %.2f presentationIntensity %.2f%@", in0, pi, chain]);
    }
    if (stateOnly || !win) {
        CGAffineTransform t = a.affineTransform;
        NSString *st = [NSString stringWithFormat:@"view %@ at %@ top %@ | other display %d (window screen %@, main %@) | shape %lld %@ | hovering %d autohidden %d opacity %.2f | enabled %d size %.2f rot %.2f | cursor %@ hidden %d in view %d transform [%.2f %.2f %.2f %.2f] | native hidden %d weHid %d views | root hidden %d weHidRoot %d | stand down %d",
            sv ? NSStringFromClass([sv class]) : @"-", NSStringFromCGRect(sv.frame), win ? [NSString stringWithFormat:@"%@ %@ window %p", NSStringFromClass([win class]), NSStringFromCGRect(win.frame), sv.window] : @"-",
            sv ? MPDisplayInfoFor(sv).reason != 0 : 0, sv.window.screen ? NSStringFromCGRect(sv.window.screen.bounds) : @"-", NSStringFromCGRect([UIScreen mainScreen].bounds),
            shape.shapeType, NSStringFromCGRect(shape.bounds), gMPHovering, gMPAutoHidden, a ? a.opacity : -1, MPEnabled(), MPSize(sv), sv ? MPRotationFor(sv) : MPRotation(),
            a ? @"yes" : @"no", a.hidden, a.superlayer == sv.layer, t.a, t.b, t.c, t.d, native.layer.hidden, (int)[objc_getAssociatedObject(sv, kMPHidNativeKey) count], [[gMPController valueForKey:@"_pointerRootView"] isHidden], gMPWeHidRoot, gMPStandDown];
        // one line per pointer view (per display): which display and why, the turns between the pointer and that display, the final turn
        NSMutableString *all = [st mutableCopy];
        for (PUIDPointerShapeView *v in [gMPShapeViews allObjects]) {
            UIWindow *w = v.window; UIScreen *s = nil; @try { s = w.screen; } @catch (id e) {}
            MPDisplayInfo d = MPDisplayInfoFor(v);
            long sceneOrient = -1; if (@available(iOS 13.0, *)) { if (w.windowScene) sceneOrient = (long)w.windowScene.interfaceOrientation; }
            CAShapeLayer *cl = objc_getAssociatedObject(v, kMPCursorKey); CGAffineTransform ct = cl.affineTransform;
            NSNumber *client = objc_getAssociatedObject(v, kMPClientTurnKey);
            [all appendFormat:@"\n[display] view %p%@ | other display %d (reason %d: 1 other screen, 2 other pixel size, 3 other window size) | screen %p main %d native %@ bounds %@ | window %@ %@ scene orientation %ld | turns (x90): in window %d%@, window layers %d, screen %d%@, client->display %@ | final rot %.2f, cursor layer turn %.2f | iPad orientation %llu",
                v, v == gMPShapeView ? @" (last)" : @"", d.reason != 0, d.reason, s, s == [UIScreen mainScreen], s ? NSStringFromCGSize(s.nativeBounds.size) : @"-", s ? NSStringFromCGRect(s.bounds) : @"-",
                w ? NSStringFromClass([w class]) : @"-", w ? NSStringFromCGRect(w.bounds) : @"-", sceneOrient, d.inWindow, d.inWindowOK ? @"" : @"?", d.windowLayers, d.screen, d.screenOK ? @"" : @"?",
                client ?: @"-", MPRotationFor(v), atan2(ct.b, ct.a), MPState(gMPOrientToken)];
        }
        return [all dataUsingEncoding:NSUTF8StringEncoding];
    }
    CGPoint p = [sv convertPoint:CGPointZero toView:win];
    CGRect r = CGRectMake(p.x - 45, p.y - 45, 90, 90);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat]; f.scale = 2; f.opaque = YES;
    UIGraphicsImageRenderer *ren = [[UIGraphicsImageRenderer alloc] initWithSize:r.size format:f];
    UIImage *img = [ren imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:0.55 green:0.6 blue:0.7 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, r.size.width, r.size.height));
        CGContextTranslateCTM(ctx.CGContext, -r.origin.x, -r.origin.y);
        [win.layer renderInContext:ctx.CGContext];
        [[UIColor redColor] setFill]; UIRectFill(CGRectMake(p.x - 0.5, p.y - 0.5, 1, 1));   // the hotspot
    }];
    return UIImagePNGRepresentation(img);
}
#endif
%ctor {
    notify_register_check("com.besiktasliseba.macpointer.config", &gMPConfigToken);
    notify_register_check("com.besiktasliseba.macpointer.orient", &gMPOrientToken);
    notify_register_check("com.besiktasliseba.macpointer.hide", &gMPHideToken);
    int changed = 0;
    notify_register_dispatch("com.besiktasliseba.macpointer.changed", &changed, dispatch_get_main_queue(), ^(int t) { MPUpdateAll(); MPApplyVisibility(); });
#if DEBUG   // (release plan 3b: this unauthenticated command channel into pointeruid must not exist in a release build)
    MPLog([NSString stringWithFormat:@"MacPointer loaded in pid %d (%@)", getpid(), [[NSProcessInfo processInfo] processName]]);
    int t = 0, t2 = 0;
    notify_register_dispatch("com.besiktasliseba.macpointer.cmd", &t, dispatch_get_main_queue(), ^(int tok) { MPHandleCommand(); });
    // (on the main queue, like the command that fills gMPOut: served from a background queue it could read the buffer while the main queue replaced it)
    notify_register_dispatch("com.besiktasliseba.macpointer.page", &t2, dispatch_get_main_queue(), ^(int tok) { MPServePage(); });
#endif
}
