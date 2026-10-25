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
// Command 6: the pointer view's position every display frame for 3 s (model and on-screen), into the running log -- is the motion smooth?
@interface MPFrameSampler : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval until;
@property (nonatomic) int frames;
@end
@interface PUIDPointerShapeView : UIView @end
static __weak PUIDPointerShapeView *gMPShapeView;
@implementation MPFrameSampler
- (void)tick:(CADisplayLink *)l {
    UIView *v = gMPShapeView;
    CALayer *p = v.layer.presentationLayer;
    MPLog([NSString stringWithFormat:@"frame %.4f model %.2f %.2f shown %.2f %.2f anim[%@]", l.timestamp, v.layer.position.x, v.layer.position.y, p ? p.position.x : -1, p ? p.position.y : -1, [[v.layer animationKeys] componentsJoinedByString:@","]]);
    if (++self.frames > 600 || CACurrentMediaTime() > self.until) { [l invalidate]; self.link = nil; MPLog(@"frames: done"); }
}
@end
static MPFrameSampler *gMPSampler;
static void MPHandleCommand(void) {
    static int tCmd, tLen; static BOOL ready;
    if (!ready) { ready = YES; notify_register_check("com.besiktasliseba.macpointer.cmdarg", &tCmd); notify_register_check("com.besiktasliseba.macpointer.len", &tLen); }
    uint64_t c = 0; notify_get_state(tCmd, &c);
    NSString *saved = gMPLive; gMPLive = [NSMutableString string];
    if (c == 6) {
        gMPLive = [saved mutableCopy] ?: [NSMutableString string];
        if (!gMPSampler) gMPSampler = [MPFrameSampler new];
        [gMPSampler.link invalidate];
        gMPSampler.frames = 0; gMPSampler.until = CACurrentMediaTime() + 3.0;
        gMPSampler.link = [CADisplayLink displayLinkWithTarget:gMPSampler selector:@selector(tick:)];
        if (@available(iOS 15.0, *)) gMPSampler.link.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
        [gMPSampler.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        gMPOut = [[@"sampling 3 s" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        notify_set_state(tLen, MAX((uint64_t)1, (uint64_t)gMPOut.length));
        return;
    }
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
    NSString *src = @"";
    if ([NSStringFromClass([l class]) isEqualToString:@"CAPortalLayer"]) { id s = nil; @try { s = [l valueForKey:@"sourceLayer"]; } @catch (id e) {} src = [NSString stringWithFormat:@" source %@ %p", s ? NSStringFromClass([s class]) : @"-", s]; }
    [m appendFormat:@"%*s%@ %p frame %@ hidden %d opacity %.2f%@ bg %@ r%.1f clip %d contents %d anim[%@]%@\n", depth * 2, "", NSStringFromClass([l class]), l, NSStringFromCGRect(l.frame), l.hidden, l.opacity,
        [l.delegate isKindOfClass:[UIView class]] ? [NSString stringWithFormat:@" (view %@)", NSStringFromClass([(id)l.delegate class])] : @"",
        l.backgroundColor ? [UIColor colorWithCGColor:l.backgroundColor] : nil, l.cornerRadius, l.masksToBounds, l.contents != nil, [[l animationKeys] componentsJoinedByString:@","], src];
    if ([l isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer *)l).path) { CAShapeLayer *sl = (CAShapeLayer *)l; CATransform3D t = l.transform;
        [m appendFormat:@"%*s  path box %@ line %.2f fill %@ stroke %@ transform a%.2f b%.2f c%.2f d%.2f shadow %.2f r%.1f\n", depth * 2, "", NSStringFromCGRect(CGPathGetBoundingBox(sl.path)), sl.lineWidth, sl.fillColor ? [UIColor colorWithCGColor:sl.fillColor] : nil, sl.strokeColor ? [UIColor colorWithCGColor:sl.strokeColor] : nil, t.m11, t.m12, t.m21, t.m22, l.shadowOpacity, l.shadowRadius]; }
    for (NSString *k in [l animationKeys]) {   // (match-move animations: what they follow and how)
        CAAnimation *an = [l animationForKey:k];
        NSMutableString *d = [NSMutableString stringWithFormat:@"%*s  anim %@ %@", depth * 2, "", k, NSStringFromClass([an class])];
        for (NSString *prop in @[@"sourceLayer", @"sourceContextId", @"sourceLayerRenderId", @"sourcePoints", @"targetsSuperlayer", @"appliesX", @"appliesY", @"appliesScale", @"appliesRotation", @"usesNormalizedCoordinates", @"duration", @"fillMode", @"removedOnCompletion", @"additive"]) {
            id v = nil; @try { v = [an valueForKey:prop]; } @catch (id e) { continue; }
            if ([v isKindOfClass:[CALayer class]]) v = [NSString stringWithFormat:@"%@ %p frame %@", NSStringFromClass([v class]), v, NSStringFromCGRect(((CALayer *)v).frame)];
            [d appendFormat:@" %@=%@", prop, [[v description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        }
        [m appendFormat:@"%@\n", d];
    }
    if ([l.delegate isKindOfClass:objc_getClass("PUIDPointerShapeView")] || [l.delegate isKindOfClass:objc_getClass("_UILumaTrackingBackdropView")] || (l.bounds.size.width == 19 && l.bounds.size.height == 19)) {
        static uint64_t (*renderId)(CALayer *); static dispatch_once_t once; dispatch_once(&once, ^{ renderId = (uint64_t (*)(CALayer *))dlsym(RTLD_DEFAULT, "CALayerGetRenderId"); });
        id ctx = nil; @try { ctx = [l valueForKey:@"context"]; } @catch (id e) {}
        id cid = nil; @try { cid = [ctx valueForKey:@"contextId"]; } @catch (id e) {}
        [m appendFormat:@"%*s  ids: context %@ render 0x%llx\n", depth * 2, "", cid, renderId ? renderId(l) : 0ULL];
    }
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
#if !DEBUG
@interface PUIDPointerShapeView : UIView @end
#endif
static int gMPConfigToken, gMPOrientToken, gMPHideToken;
static BOOL gMPStandDown = NO;          // another tweak changes the pointer in this process (MPOtherPointerTweak)
static BOOL gMPHovering = NO;           // the renderer's state has content (a hover effect is showing)
#if !DEBUG
static __weak PUIDPointerShapeView *gMPShapeView;
#endif
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
static BOOL gMPStandDownChecked = NO;
static void MPCheckStandDown(void) { if (!gMPStandDownChecked) { gMPStandDownChecked = YES; gMPStandDown = MPOtherPointerTweak(); } }
// SpringBoard's buttons and icons drop iPadOS's pointer effects only while this pointer is the Mac arrow: it is told whether we stand down for another
// pointer tweak (common/MacPointerActive.h: 1 present, 2 standing down; logic test W5, 25 Oct). The token is kept, so the state lives with pointeruid.
static void MPPublishPresence(void) {
    static int token = 0;
    if (!token && notify_register_check("com.besiktasliseba.macpointer.active", &token) != NOTIFY_STATUS_OK) token = 0;
    if (!token) return;
    MPCheckStandDown();
    uint64_t want = gMPStandDown ? 2 : 1, cur = 0;
    notify_get_state(token, &cur);
    if (cur != want) { notify_set_state(token, want); notify_post("com.besiktasliseba.macpointer.active"); }
}
static BOOL MPEnabled(void) {
    MPCheckStandDown();
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
    a.shadowPath = MPCursorPath();   // (the shadow from the path itself: without it Core Animation works the shadow out of the drawn pixels, off screen, every frame)
    a.contentsScale = [UIScreen mainScreen].scale;
    a.zPosition = 1000;
    a.anchorPoint = CGPointZero;   // (its origin, the cursor's tip, sits on the pointer view's origin, the pointer position: set once, the layer rides the view)
    a.bounds = CGRectZero;
    a.position = CGPointZero;
    objc_setAssociatedObject(view, kMPCursorKey, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return a;
}
// Settings > Accessibility > Pointer Control on the Mac pointer (as macOS's pointer outline color): Color becomes the arrow's outline, Border Width its
// thickness, Increase Contrast a stronger edge. The colour is taken from the system's own colour ring (_axColorStroke, which the Mac pointer hides)
// rather than from the setting's number, so it is exactly the colour Apple draws, whatever the choice; the width and contrast come from the settings.
static CGColorRef MPRingColor(CALayer *l, int depth) {
    if (!l || depth > 4) return NULL;
    if ([l isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer *)l).path && ((CAShapeLayer *)l).strokeColor && CGColorGetAlpha(((CAShapeLayer *)l).strokeColor) > 0.05) return ((CAShapeLayer *)l).strokeColor;
    if (l.borderWidth > 0 && l.borderColor && CGColorGetAlpha(l.borderColor) > 0.05) return l.borderColor;
    for (CALayer *sub in l.sublayers) { CGColorRef c = MPRingColor(sub, depth + 1); if (c) return c; }
    if (l.backgroundColor && CGColorGetAlpha(l.backgroundColor) > 0.05) return l.backgroundColor;
    return NULL;
}
static double gMPAXWidth = 0; static BOOL gMPAXContrast = NO; static CFTimeInterval gMPAXRead = -10; static long gMPAXColor = -1;   // (-1 unknown)
static void MPReadAXStyle(void) {
    if (CACurrentMediaTime() - gMPAXRead < 2.0) return;
    gMPAXRead = CACurrentMediaTime();
    CFPreferencesAppSynchronize(CFSTR("com.apple.Accessibility"));
    double w = 0; CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("PointerStrokeColorWidth"), CFSTR("com.apple.Accessibility"));
    if (v) { if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &w); CFRelease(v); }
    gMPAXWidth = w;
    long ci = -1; v = CFPreferencesCopyAppValue(CFSTR("PointerStrokeColor"), CFSTR("com.apple.Accessibility"));   // (0 = None; 1 white, ...)
    if (v) { if (CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &ci); CFRelease(v); }
    gMPAXColor = ci;
    BOOL c = NO; v = CFPreferencesCopyAppValue(CFSTR("PointerIncreasedContrastEnabled"), CFSTR("com.apple.Accessibility"));
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) c = CFBooleanGetValue(v); else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int i = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &i); c = i != 0; } CFRelease(v); }
    gMPAXContrast = c;
}
static void MPApplyAXStyle(UIView *view, CAShapeLayer *a, BOOL ringHiddenByUs) {
    BOOL use = (MPState(gMPConfigToken) & 8) != 0;   // (Settings > Pointer > Use Pointer Control Style; off: the classic arrow)
    if (use) MPReadAXStyle();
    UIView *ring = nil; @try { ring = [view valueForKey:@"_axColorStroke"]; } @catch (id e) {}
    // (a ring the system itself hides -- Color: None -- gives no colour; one hidden by us for the Mac pointer still has its colour set)
    // (Color: None -- the setting, not the ring: a ring we hid keeps its last colour when None is picked, logic test F11)
    CGColorRef c = (use && gMPAXColor != 0 && [ring isKindOfClass:[UIView class]] && (!ring.layer.hidden || ringHiddenByUs)) ? MPRingColor(ring.layer, 0) : NULL;
    CGFloat line = 1.25, shadow = 0.35;
    if (c) line = MAX(1.25, MIN(3.0, (gMPAXWidth > 0 ? gMPAXWidth : 2.0) * 0.5));   // (the ring's width is around a 19 pt circle; the arrow's edge is in its own 20 pt drawing)
    if (use && gMPAXContrast) { line += 0.5; shadow = 0.6; }
    if (!c) c = [UIColor whiteColor].CGColor;
    if (!CGColorEqualToColor(a.strokeColor, c)) {
#if DEBUG
        MPLog([NSString stringWithFormat:@"%.3f outline %@ width %.2f contrast %d", CACurrentMediaTime(), [UIColor colorWithCGColor:c], line, gMPAXContrast]);
#endif
        a.strokeColor = c;
    }
    if (a.lineWidth != line) a.lineWidth = line;
    if (a.shadowOpacity != shadow) a.shadowOpacity = shadow;
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
// Another display: each display has its own rendering controller and pointer view. When the pointer moves to the other display, the system hides
// the pointer on the one it left (the controller's hidePointer: its visibility state changes and the pointer's content fades to alpha 0); the Mac
// pointer is a layer of its own beside that content, so it stayed on the iPad's status bar while the pointer was on the TV (iPad 2 + TV, 29 Sep).
// So the Mac pointer follows its controller: hidden from hidePointer until that controller's visibility state changes again (the pointer is back).
static const void *kMPSysHidKey = &kMPSysHidKey;
static UIViewController *MPControllerOf(UIView *v) {
    for (UIResponder *r = v; r; r = r.nextResponder) if ([r isKindOfClass:objc_getClass("PUIDPointerRenderingRootViewController")]) return (UIViewController *)r;
    return nil;
}
static long long MPVisibilityState(UIViewController *c) {
    Ivar iv = c ? class_getInstanceVariable([c class], "_visibilityState") : NULL;
    return iv ? *(long long *)((uint8_t *)(__bridge void *)c + ivar_getOffset(iv)) : -1;
}
static BOOL MPHiddenBySystem(UIView *view) {
    UIViewController *c = MPControllerOf(view);
    NSNumber *hidState = c ? objc_getAssociatedObject(c, kMPSysHidKey) : nil;
    if (!hidState) return NO;
    if (MPVisibilityState(c) == hidState.longLongValue) return YES;
    objc_setAssociatedObject(c, kMPSysHidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (shown again)
    return NO;
}
// An object ivar read straight (no key-value lookup: these run with the pointer's own updates). Nil when the class has no such ivar.
static id MPIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *t = ivar_getTypeEncoding(iv);
    return (t && t[0] == '@') ? object_getIvar(obj, iv) : nil;
}
// Only the pointer itself carries the arrow: its controller's _pointerShapeView. iPadOS 17's controller has a second pointer view,
// _specularEffectMaskPointerShapeView, the round mask of the "specular" light it shows on lifted content (an icon in the Dock, a button that lifts);
// the hooks below ran for it too, put the arrow into that mask and took it for the pointer.
static const void *kMPMainKey = &kMPMainKey;
static BOOL MPIsMainShapeView(UIView *v) {
    NSNumber *known = objc_getAssociatedObject(v, kMPMainKey);
    if (known) return known.boolValue;
    UIViewController *c = MPControllerOf(v);
    id main = MPIvar(c, "_pointerShapeView");
    if (!c || !main) return YES;   // (not known yet, or another layout: as before, and asked again next time)
    BOOL is = main == v;
    objc_setAssociatedObject(v, kMPMainKey, @(is), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return is;
}
// The specular light (a soft round spot that follows the pointer over lifted content, masked by the round pointer shape: "a little circle at its tip"
// over the Dock and lifted buttons -- KT, 24 Oct) is not drawn while the arrow is in use; a Mac pointer has no light. Its image view is inside a
// source that portals show elsewhere, so the image view's own layer is hidden (a portal draws its source's sublayers as they are).
// The same for the pointer's accessories (_accessoryContainerView: the little arrows iPadOS puts around its pointer at some regions).
static void MPHideControllerView(UIViewController *c, const char *ivar, const void *key, BOOL hide) {
    UIView *v = MPIvar(c, ivar);
    if (![v isKindOfClass:[UIView class]]) return;
    BOOL weHid = [objc_getAssociatedObject(c, key) boolValue];
    if (hide && !v.layer.hidden) { v.layer.hidden = YES; objc_setAssociatedObject(c, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    else if (!hide && weHid) { v.layer.hidden = NO; objc_setAssociatedObject(c, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static void MPSpecular(UIViewController *c, BOOL hide) {
    static const void *kMPSpecHidKey = &kMPSpecHidKey, *kMPAccHidKey = &kMPAccHidKey;
    MPHideControllerView(c, "_specularImageView", kMPSpecHidKey, hide);
    MPHideControllerView(c, "_accessoryContainerView", kMPAccHidKey, hide);
}
// The arrow's turn (the interface orientation, or another display's own) and size: worked out again only when something they depend on changes
// (the orientation state, the size setting, the view's window or screen) -- MPUpdate runs for every shape change, up to every display frame while
// the pointer hovers a control (17.5.1: setPointerShape about every 8 ms), and measuring the display every time was work on pointeruid's main
// thread, the thread that moves the pointer.
static const void *kMPTurnCacheKey = &kMPTurnCacheKey;
static CGAffineTransform MPCursorTransform(UIView *view) {
    NSArray *c = objc_getAssociatedObject(view, kMPTurnCacheKey);
    uint64_t orient = MPState(gMPOrientToken); double size = MPSize(view);
    UIWindow *w = view.window; UIScreen *s = nil; @try { s = w.screen; } @catch (id e) {}
    // (the window and screen by their addresses only: the view must not keep its own window alive)
    if (c.count == 5 && [c[0] unsignedLongLongValue] == orient && [c[1] doubleValue] == size && [c[2] unsignedLongValue] == (uintptr_t)w && [c[3] unsignedLongValue] == (uintptr_t)s)
        return [c[4] CGAffineTransformValue];
    CGFloat k = size * 1.12;   // 1.0 = about 22 pt tall on screen, the size the owner tuned the old cursor to
    CGAffineTransform t = CGAffineTransformScale(CGAffineTransformMakeRotation(MPRotationFor(view)), k, k);
    objc_setAssociatedObject(view, kMPTurnCacheKey, @[@(orient), @(size), @((uintptr_t)w), @((uintptr_t)s), [NSValue valueWithCGAffineTransform:t]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return t;
}
// The system's own pointer views of a pointer view (its round pointer and its accessibility ring and dot), read each time (straight ivar reads: a
// view the system replaces is never missed).
static NSArray<UIView *> *MPNativeViews(UIView *view) {
    NSMutableArray *m = [NSMutableArray arrayWithCapacity:3];
    const char *names[] = {"_pointerView", "_axColorStroke", "_axCenterDot"};
    for (int i = 0; i < 3; i++) { UIView *v = MPIvar(view, names[i]); if (!v) { @try { v = [view valueForKey:@(names[i])]; } @catch (id e) {} } if ([v isKindOfClass:[UIView class]]) [m addObject:v]; }
    return m;
}
#if DEBUG
static int gMPUpdates = 0; static double gMPUpdateMs = 0, gMPUpdateMax = 0; static CFTimeInterval gMPUpdateSince = 0;
#endif
// What the pointer shows. The system's pointer shape (PSPointerShape) as seen on 15-17:
//  - type 1, the round pointer (also while it hovers an icon or our status bar, where the system only lifts or highlights the content): the arrow;
//  - type 3, a rounded rectangle: a button's or a control's highlight (17.5.1: the Clock tab bar's World Clock, 41 x 182 pt, radius 8; our traffic
//    lights, 20 x 20 radius 8 -- "the circle at the window edges", KT on 18.5) -- the arrow, as on a Mac; a thin one (4 pt or less) is the text beam
//    of iPadOS 15/16: the system's beam;
//  - type 4, the text beam of iPadOS 17 and 18 (17.5.1 over Finder's search field; the only types 18.5 showed: 1, 3, 4): the system's beam;
//  - anything else: the arrow (a Mac shows the arrow everywhere but over text).
// Wherever the arrow shows, nothing of the system's own pointer is drawn: not the round pointer, not a control's highlight, not the accessibility
// ring (KT, 24 Oct: "a little circle at its tip" -- the round pointer came back for every highlight and beam and morphed out of its circle under the
// arrow). The system's shape changes are made without their morph while the arrow is in use (the setPointerShape hook below): a Mac pointer changes
// at once, and the morph started from the round pointer.
static void MPUpdate(PUIDPointerShapeView *view) {
    if (!view) return;
#if DEBUG
    CFTimeInterval t0 = CACurrentMediaTime();
#endif
    PSPointerShape *shape = MPIvar(view, "_pointerShape");
    if (!shape) { @try { shape = [view valueForKey:@"pointerShape"]; } @catch (id e) {} }
    long long type = shape ? shape.shapeType : 1;
    CGRect sb = shape ? shape.bounds : CGRectZero;
    BOOL thin = !CGRectIsEmpty(sb) && MIN(sb.size.width, sb.size.height) <= 4.0;
    BOOL systemShape = thin || type == 4;   // (only the text beam: iPadOS 17/18's type 4, 15/16's thin type 3 -- every other style gets the arrow)
    // (Hide in Virtual Mac hides the pointer's root view, MPApplyVisibility; the arrow in the top window is not under it, so it goes too)
    BOOL want = MPEnabled() && !systemShape && !MPHiddenBySystem(view) && MPState(gMPHideToken) != 1;
    CAShapeLayer *a = want ? MPCursorLayer(view) : objc_getAssociatedObject(view, kMPCursorKey);
    CALayer *host = view.layer;   // (the arrow rides the pointer view itself: its origin is the pointer's position)
    NSArray<UIView *> *natives = MPNativeViews(view);
    NSMutableArray *hid = objc_getAssociatedObject(view, kMPHidNativeKey);
    CGAffineTransform t = a ? MPCursorTransform(view) : CGAffineTransformIdentity;
    float fadeTarget = gMPAutoHidden ? 0.0f : 1.0f;
    // nothing to change (the usual case: this runs with the pointer's own updates): no transaction at all
    BOOL nativesShown = NO; for (UIView *v in natives) if (!v.layer.hidden) { nativesShown = YES; break; }
    BOOL settled = want ? (a.superlayer == host && host.sublayers.lastObject == a && !a.hidden && CGAffineTransformEqualToTransform(a.affineTransform, t) && !nativesShown && a.opacity == fadeTarget)
                        : ((!a || a.hidden) && !hid.count);
    if (!settled) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (a && !CGAffineTransformEqualToTransform(a.affineTransform, t)) a.affineTransform = t;   // (kept turned while hidden too -- the iPad turned while the pointer
                                                                                                    //  was on the TV left the hidden arrow at the old angle, 29 Sep)
        if (want) {
            if (a.superlayer != host || host.sublayers.lastObject != a) [host addSublayer:a];   // (on top; moved only when it is not -- out of the pointer view when it moves to the box)
            if (a.hidden) a.hidden = NO;
            for (UIView *v in natives) if (!v.layer.hidden) {   // the system's own pointer views hidden exactly while the arrow shows
                v.layer.hidden = YES;
                if (!hid) { hid = [NSMutableArray array]; objc_setAssociatedObject(view, kMPHidNativeKey, hid, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                if (![hid containsObject:v]) [hid addObject:v];
            }
        } else {
            if (a && !a.hidden) a.hidden = YES;
            if (hid.count) {   // given back (only what we hid) when the system's shape is wanted
                for (UIView *v in hid) v.layer.hidden = NO;
                objc_setAssociatedObject(view, kMPHidNativeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        [CATransaction commit];
        // auto-hide: fade out completely with the system (0.35 s), back at once
        if (want && a.opacity != fadeTarget) {
            if (gMPAutoHidden) {
                CABasicAnimation *f = [CABasicAnimation animationWithKeyPath:@"opacity"];
                f.fromValue = @(a.presentationLayer ? a.presentationLayer.opacity : a.opacity); f.toValue = @0; f.duration = 0.35;
                f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [a addAnimation:f forKey:@"mpfade"];
            } else [a removeAnimationForKey:@"mpfade"];
            [CATransaction begin]; [CATransaction setDisableActions:YES]; a.opacity = fadeTarget; [CATransaction commit];
        }
    }
    if (want) {
        static CFTimeInterval lastStyle = 0; static uint64_t lastConfig = UINT64_MAX;
        uint64_t config = MPState(gMPConfigToken);
        if (config != lastConfig || CACurrentMediaTime() - lastStyle > 1.0) {   // (the outline: once a second at most, at once when the settings change)
            lastConfig = config; lastStyle = CACurrentMediaTime();
            UIView *ring = MPIvar(view, "_axColorStroke");
            NSArray *hidNow = objc_getAssociatedObject(view, kMPHidNativeKey);
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            MPApplyAXStyle(view, a, ring && [hidNow containsObject:ring]);
            [CATransaction commit];
        }
    }
    MPSpecular(MPControllerOf(view), want);
#if DEBUG
    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    gMPUpdates++; gMPUpdateMs += ms; if (ms > gMPUpdateMax) gMPUpdateMax = ms;
    if (CACurrentMediaTime() - gMPUpdateSince > 2.0) {
        if (gMPUpdateSince > 0) MPLog([NSString stringWithFormat:@"%.3f updates: %d in %.1f s, avg %.3f ms, max %.3f ms (shape %lld, arrow %d)", CACurrentMediaTime(), gMPUpdates, CACurrentMediaTime() - gMPUpdateSince, gMPUpdates ? gMPUpdateMs / gMPUpdates : 0, gMPUpdateMax, type, want]);
        gMPUpdates = 0; gMPUpdateMs = 0; gMPUpdateMax = 0; gMPUpdateSince = CACurrentMediaTime();
    }
#endif
}
// Hide in Virtual Mac: never write the root view's hidden unless we hid it (the system fades the pointer out with it).
static void MPApplyVisibility(void) {
    UIViewController *c = gMPController; if (!c || gMPStandDown) return;
    BOOL hide = MPState(gMPHideToken) == 1;
    if (!hide && !gMPWeHidRoot) return;   // (the usual case, with the pointer's updates: nothing to read)
    UIView *root = MPIvar(c, "_pointerRootView");
    if (!root) { @try { root = [c valueForKey:@"_pointerRootView"]; } @catch (id e) {} }
    if (![root isKindOfClass:[UIView class]]) return;
    if (hide) { if (!root.hidden) root.hidden = YES; gMPWeHidRoot = YES; }
    else { root.hidden = NO; gMPWeHidRoot = NO; }
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
    if (!MPIsMainShapeView((UIView *)self)) return;   // (the specular light's mask: never the arrow's host)
    gMPShapeView = (PUIDPointerShapeView *)self;
    MPRemember((PUIDPointerShapeView *)self);
    MPUpdate((PUIDPointerShapeView *)self);   // (settled: no transaction, see MPUpdate)
}
- (void)setPointerShape:(id)shapeObj animated:(BOOL)animated completion:(id)completion {
    // (while the arrow is in use, the system's shape changes without its morph: a Mac pointer changes at once, and the morph out of or into the round
    //  pointer showed that circle under the arrow -- KT, 24 Oct, "a little circle at its tip")
    BOOL main = MPIsMainShapeView((UIView *)self);
    BOOL morph = animated && !MPEnabled();
    id before = main ? MPIvar(self, "_pointerShape") : nil;
#if DEBUG
    if (main) { PSPointerShape *shape = shapeObj; static NSString *last;
      NSString *sig = [NSString stringWithFormat:@"type %lld bounds %@ r%.1f", shape.shapeType, NSStringFromCGRect(shape.bounds), shape.cornerRadius];
      if (![sig isEqualToString:last]) { last = sig; MPLog([NSString stringWithFormat:@"%.3f setPointerShape %@ animated %d (passed on %d) at %@", CACurrentMediaTime(), sig, animated, morph, NSStringFromCGPoint(((UIView *)self).frame.origin)]); } }
#endif
    %orig(shapeObj, morph, completion);
    if (!main) return;
    gMPShapeView = (PUIDPointerShapeView *)self;
    MPRemember((PUIDPointerShapeView *)self);
    if (before && [before isEqual:shapeObj]) return;   // (the same shape again -- 17 sets it every frame while a control is hovered: nothing to do)
    MPUpdate((PUIDPointerShapeView *)self);
}
%end
%hook PUIDPointerRenderingRootViewController
- (void)hidePointer {
    long long before = MPVisibilityState((UIViewController *)self);
    %orig;
    long long after = MPVisibilityState((UIViewController *)self);
#if DEBUG
    MPLog([NSString stringWithFormat:@"%.3f hidePointer on %p: visibility %lld -> %lld", CACurrentMediaTime(), self, before, after]);
#endif
    // (only when the system really changed this display's pointer visibility -- logic test F10: a hidePointer that changes nothing must not
    //  leave the Mac pointer hidden with the pointer still on this display)
    if (after != before) objc_setAssociatedObject(self, kMPSysHidKey, @(after), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PUIDPointerShapeView *own = nil; @try { own = [(id)self valueForKey:@"_pointerShapeView"]; } @catch (id e) {}
    if ([own isKindOfClass:[UIView class]]) MPUpdate(own);
}
- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error {
    CGRect content = CGRectZero; @try { content = [[state valueForKey:@"contentBounds"] CGRectValue]; } @catch (id e) {}
    gMPHovering = !CGRectIsEmpty(content);
    @try { gMPAutoHidden = [[state valueForKey:@"pointerAutoHidden"] boolValue]; } @catch (id e) {}
#if DEBUG
    {   // (only when something changed: this is called with the pointer's updates, and the debug build is the one tested)
        static long long lastType = -2; static int lastFlags = -1;
        PSPointerShape *sh = [state valueForKey:@"pointerShape"];
        int flags = (gMPAutoHidden ? 1 : 0) | (gMPHovering ? 2 : 0);
        if (sh.shapeType != lastType || flags != lastFlags) {
            lastType = sh.shapeType; lastFlags = flags;
            MPLog([NSString stringWithFormat:@"%.3f state shape %lld %@ r%.1f content %@ overlay %@ autohidden %@ pressed %@ client %@", CACurrentMediaTime(), sh.shapeType, NSStringFromCGRect(sh.bounds), sh.cornerRadius,
                NSStringFromCGRect(content), [state valueForKey:@"overlayEffectStyle"], [state valueForKey:@"pointerAutoHidden"], [state valueForKey:@"pressed"], [state valueForKey:@"debugRequestingClientString"]]);
        }
    }
#endif
    BOOL r = %orig;
#if DEBUG
    { static long long lastVis = LLONG_MIN; long long v = MPVisibilityState((UIViewController *)self);
      if (v != lastVis) { lastVis = v; MPLog([NSString stringWithFormat:@"%.3f controller %p visibility %lld", CACurrentMediaTime(), self, v]); } }
#endif
    gMPController = (UIViewController *)self;
    // (this controller's own pointer view -- with an external display each display has its own controller and pointer view; only what changed for it
    //  is acted on: this is called with the pointer's updates)
    PUIDPointerShapeView *own = MPIvar(self, "_pointerShapeView");
    if ([own isKindOfClass:[UIView class]]) {
        static const void *kMPStateSigKey = &kMPStateSigKey;
        NSUInteger sig = (gMPAutoHidden ? 1 : 0) | (gMPHovering ? 2 : 0) | ((NSUInteger)(MPVisibilityState((UIViewController *)self) & 0xff) << 2);
        NSNumber *last = objc_getAssociatedObject(own, kMPStateSigKey);
        if (!last || last.unsignedIntegerValue != sig) {
            objc_setAssociatedObject(own, kMPStateSigKey, @(sig), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            MPRemember(own);
            if (!gMPShapeView) gMPShapeView = own;
            MPUpdate(own);
        }
    }
#if DEBUG   // the turn of the client's coordinate space to the display (evidence for the external display: which way pointeruid thinks is up)
    if ([own isKindOfClass:[UIView class]] && !objc_getAssociatedObject(own, kMPClientTurnKey)) { @try { CATransform3D ct = [[state valueForKey:@"clientCoordinateSpaceTransformToDisplay"] CATransform3DValue];
        bool ok = false; int q = MPQuarterTurns(ct.m11, ct.m12, &ok); objc_setAssociatedObject(own, kMPClientTurnKey, ok ? @(q) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); } @catch (id e) {} }
#endif
    MPApplyVisibility();
    return r;
}
%end
// No pull toward buttons while the arrow is in use (KT on 18.5 via the A12Z: the shown pointer trailed the real one by up to 66 pt while it was drawn
// to a button's centre -- iPadOS's magnetism; a Mac arrow never moves on its own). The position iPadOS gives the pointer over a target
// (-_positionForTargetWithCenter:modelCursorPosition:slip:) is the real one, the model cursor position, while the Mac pointer is on. Nothing else is
// done there: it is called with the pointer's moves over a target.
static CGPoint (*o_MPTargetPosition)(id, SEL, CGPoint, CGPoint, CGPoint);
static CGPoint MPTargetPosition(id self, SEL _cmd, CGPoint center, CGPoint model, CGPoint slip) {
    return MPEnabled() ? model : o_MPTargetPosition(self, _cmd, center, model, slip);
}
static void MPInstallNoMagnetism(void) {
    Class c = objc_getClass("PUIDPointerRenderingRootViewController");
    SEL s = NSSelectorFromString(@"_positionForTargetWithCenter:modelCursorPosition:slip:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) return;
    NSMutableString *shape = [NSMutableString string];   // (the types without the frame offsets)
    for (const char *t = method_getTypeEncoding(m); t && *t; t++) if (!isdigit((unsigned char)*t)) [shape appendFormat:@"%c", *t];
    if (![shape isEqualToString:@"{CGPoint=dd}@:{CGPoint=dd}{CGPoint=dd}{CGPoint=dd}"]) return;
    MSHookMessageEx(c, s, (IMP)MPTargetPosition, (IMP *)&o_MPTargetPosition);
}
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
    MPInstallNoMagnetism();
    notify_register_check("com.besiktasliseba.macpointer.config", &gMPConfigToken);
    notify_register_check("com.besiktasliseba.macpointer.orient", &gMPOrientToken);
    notify_register_check("com.besiktasliseba.macpointer.hide", &gMPHideToken);
    int changed = 0;
    notify_register_dispatch("com.besiktasliseba.macpointer.changed", &changed, dispatch_get_main_queue(), ^(int t) { MPUpdateAll(); MPApplyVisibility(); MPPublishPresence(); });
    // (whether we stand down is checked once every tweak is loaded -- a moment after start, on the main queue -- and published for SpringBoard)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MPPublishPresence(); });
#if DEBUG   // (release plan 3b: this unauthenticated command channel into pointeruid must not exist in a release build)
    MPLog([NSString stringWithFormat:@"MacPointer loaded in pid %d (%@)", getpid(), [[NSProcessInfo processInfo] processName]]);
    int t = 0, t2 = 0;
    notify_register_dispatch("com.besiktasliseba.macpointer.cmd", &t, dispatch_get_main_queue(), ^(int tok) { MPHandleCommand(); });
    // (on the main queue, like the command that fills gMPOut: served from a background queue it could read the buffer while the main queue replaced it)
    notify_register_dispatch("com.besiktasliseba.macpointer.page", &t2, dispatch_get_main_queue(), ^(int tok) { MPServePage(); });
#endif
}
