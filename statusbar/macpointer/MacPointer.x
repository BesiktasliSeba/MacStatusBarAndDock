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
//  - Stands aside while another tweak draws its own pointer in pointeruid (two pointers would fight): MPAsideLook, MPAside.h.
//  - macOS's resize pointers (1.8.9, F51; common/MacResizeCursor.h): where SpringBoard says a window can be resized and iPadOS's pointer carries
//    its resize arrows there, the Mac pointer's layer draws macOS's resize cursor instead of the arrow; a pointer state with arrows around it is
//    never the text beam (the grey circle with arrows at a window's edge on 18.5, KT 25 Nov). The window engines' grips (Aerial, Zetsu,
//    MilkyWay4; 1.8.9, F51b): iPadOS has no resize shape there, SpringBoard's fact is its own evidence while it is fresh (its lease and no shape
//    change since, MSBDResizeGripFresh). Settings > Pointer > Mac Resize Pointers (on by default on iPadOS 18, off on 15-17; MPResizeOn): off,
//    the pointer looks as in 1.8.8.4 and none of this is read.
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
#include "../../common/PointerFade.h"   // (1.8.8, D48: the pointer's fade said to SpringBoard -- the traffic lights' hold ends at it)
#include "MPAside.h"   // (1.8.8.2, GitHub #17: does another library draw the pointer; what the Mac pointer is doing, said: common/MacPointerStatus.h)
#include "../../common/MacResizeCursor.h"   // (1.8.9, F51: the resize fact, the look, the latch and the glyphs)
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
static BOOL gMPStandDown = NO;          // the Mac pointer does not draw: another pointer is drawn, or not looked at yet (gMPAside)
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
// Another pointer drawn in pointeruid would fight the Mac pointer (two pointers at once). pointeruid's pointer classes are read once, at the first
// pointer update or 2 s after the start (every tweak is loaded by then). No other jailbreak library changes them, the usual case: the Mac pointer
// draws, decided for the run (ALONE). One does: until 1.8.8.1.1 that alone made the Mac pointer stand down for the run, also for a hook that draws
// nothing, and nothing said so (GitHub #17). Now it only means the pointer is looked at (MPAsideLook): standing aside while another pointer shows
// (ASIDE), drawing while nothing of the other library's does (SHARED); the round pointer is left as it is until the first look (WAITING).
// The verdict, what was seen and the parts of iPadOS's pointer not found go to SpringBoard and Settings (MPPublishStatus, common/MacPointerStatus.h).
static unsigned gMPAside = MSBD_MP_V_NONE, gMPAsideSeen = 0, gMPMissing = 0, gMPNow = MSBD_MP_NOW_NONE;
static int gMPAsideClean = 0;   // (clean looks in a row while standing aside, MSBDMPAsideNext)
static char gMPOtherPath[512];  // the first other library found changing the pointer's classes
static void MPPublishPresence(void);
// The word for SpringBoard and Settings (MSBD_MP_STATUS): this pointeruid's pid, the verdict, what was seen, the parts not found, why the arrow is
// not shown on the iPad's display; set and posted only when it changes. The token is kept: the word lives as long as this pointeruid.
static void MPPublishStatus(void) {
    static int token = 0; static uint64_t said = 0;
    if (!token && notify_register_check(MSBD_MP_STATUS, &token) != NOTIFY_STATUS_OK) token = 0;
    uint64_t w = MSBDMPPack((uint32_t)getpid(), gMPAside, gMPAsideSeen, gMPMissing, gMPNow);
    if (!token || w == said) return;
    said = w; notify_set_state(token, w); notify_post(MSBD_MP_STATUS);
}
// The other library's file name for Report a Problem (32 bytes in four states; MSBDMPOtherName reads them). Tokens kept, as the status's.
static void MPSayOtherName(const char *path) {
    static int tokens[4];
    const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
    char bytes[32]; memset(bytes, 0, sizeof bytes); strlcpy(bytes, base, sizeof bytes);
    for (int i = 0; i < 4; i++) {
        char nm[64]; snprintf(nm, sizeof nm, MSBD_MP_OTHER_FMT, i);
        if (!tokens[i] && notify_register_check(nm, &tokens[i]) != NOTIFY_STATUS_OK) { tokens[i] = 0; continue; }
        uint64_t v = 0; memcpy(&v, bytes + i * 8, 8); notify_set_state(tokens[i], v);
    }
}
static void MPAsideTimerFollow(void);
static void MPSetAside(unsigned verdict, unsigned seen) {
    if (verdict == gMPAside && seen == gMPAsideSeen) return;
    unsigned was = gMPAside;
    gMPAside = verdict; gMPAsideSeen = seen;
    gMPStandDown = !MSBDMPVerdictDraws(verdict);
    const char *base = strrchr(gMPOtherPath, '/'); base = base ? base + 1 : gMPOtherPath;
    // (release builds too: one line at each change of the verdict, for a report; nothing while the pointer simply moves)
    if (verdict == MSBD_MP_V_ASIDE && was != MSBD_MP_V_ASIDE)
        NSLog(@"[MacPointer] standing aside: another pointer is drawn (seen: %s%s%s; the other library changing the pointer: %s)", (seen & MSBD_MP_SEEN_CLASS) ? "its class " : "",
              (seen & MSBD_MP_SEEN_LAYER) ? "a layer on the pointer " : "", (seen & MSBD_MP_SEEN_ROUND_HIDDEN) ? "the round pointer hidden" : "", base);
    else if (verdict == MSBD_MP_V_SHARED && was == MSBD_MP_V_ASIDE) NSLog(@"[MacPointer] drawing again: the other pointer is no longer shown");
    else if (verdict == MSBD_MP_V_SHARED && was == MSBD_MP_V_WAITING) NSLog(@"[MacPointer] another library changes the pointer (%s) but draws no pointer: the Mac pointer draws", base);
#if DEBUG
    MPLog([NSString stringWithFormat:@"%.3f aside: verdict %u -> %u, seen %u", CACurrentMediaTime(), was, verdict, seen]);
#endif
    MPPublishStatus();
    if (was != MSBD_MP_V_NONE) MPPublishPresence();   // (SpringBoard's icons and Pointer Animations follow at once; the first verdict: as before, at 2 s)
    MPAsideTimerFollow();   // (standing aside: its own look every 2 s while the pointer is in use; any other verdict: none)
}
static BOOL gMPStandDownChecked = NO;
static void MPCheckStandDown(void) {
    if (gMPStandDownChecked) return;
    gMPStandDownChecked = YES;
    gMPMissing = MPAsideMissing();
    if (gMPMissing) NSLog(@"[MacPointer] parts of iPadOS's pointer not found on this version: 0x%x", gMPMissing);
    unsigned hooks = MPAsideOtherHooks(gMPOtherPath, sizeof gMPOtherPath,
#if DEBUG
        ^(const char *cls, SEL sel, const char *path) { MPLog([NSString stringWithFormat:@"other library: -[%s %@] is changed by %s", cls, NSStringFromSelector(sel), path]); }
#else
        nil
#endif
    );
    if (hooks) MPSayOtherName(gMPOtherPath);
    MPSetAside(hooks ? MSBD_MP_V_WAITING : MSBD_MP_V_ALONE, 0);
}
// SpringBoard's buttons and icons drop iPadOS's pointer effects only while this pointer is the Mac arrow: it is told whether we stand down for another
// pointer tweak (common/MacPointerActive.h: 1 present, 2 standing down; logic test W5, 25 Oct). The token is kept, so the state lives with pointeruid.
// Not said while the pointer was not looked at yet (WAITING): SpringBoard keeps what it has (MSBDMacPointerStateKept) until the first look.
static void MPPublishPresence(void) {
    static int token = 0;
    if (!token && notify_register_check("com.besiktasliseba.macpointer.active", &token) != NOTIFY_STATUS_OK) token = 0;
    if (!token) return;
    MPCheckStandDown();
    if (gMPAside == MSBD_MP_V_WAITING) return;
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
// The system's own pointer views of a pointer view (its round pointer, iPadOS 18's morphing path-shape view under resize bands, and its
// accessibility ring and dot), read each time (ivar and subview reads: a view the system adds or replaces for a shape is never missed, while
// views of another library are left alone for MPAsideSeen).
static NSArray<UIView *> *MPNativeViews(UIView *view) {
    NSMutableArray<UIView *> *m = [NSMutableArray arrayWithCapacity:4];
    const char *names[] = {"_pointerView", "_pointerShapeMorphingView", "_axColorStroke", "_axCenterDot"};
    for (int i = 0; i < 4; i++) {
        UIView *v = MPIvar(view, names[i]);
        if (!v && i != 1) { @try { v = [view valueForKey:@(names[i])]; } @catch (id e) {} }
        if ([v isKindOfClass:[UIView class]] && !MPAsideClassIsOther(object_getClass(v)) && ![m containsObject:v]) [m addObject:v];
    }
    const void *held[64];
    int nh = MPAsideHeldBy(view, [UIView class], held, 0, 64);
    for (UIView *sub in view.subviews) {
        if ([m containsObject:sub] || MPAsideClassIsOther(object_getClass(sub))) continue;
        if (MPAsideIn((__bridge const void *)sub, held, nh) || MPAsideClassIsPUID(object_getClass(sub))) [m addObject:sub];
    }
    return m;
}
// Why the arrow is not shown on the iPad's own display (1.8.8.2, MSBD_MP_NOW_*, for Report a Problem): from the reads MPUpdate made (enabled is
// MPEnabled()); the config and orientation read again only when the Mac pointer is not enabled. Only for the pointer view on the iPad's display (kept
// per view and window); said only when it changes.
static const void *kMPOwnDisplayKey = &kMPOwnDisplayKey;
static BOOL MPOnOwnDisplay(UIView *view) {
    UIWindow *w = view.window; if (!w) return NO;
    NSArray *k = objc_getAssociatedObject(view, kMPOwnDisplayKey);
    if (k.count == 2 && [k[0] unsignedLongValue] == (uintptr_t)w) return [k[1] boolValue];   // (the window by its address only, as MPCursorTransform)
    BOOL own = MPDisplayInfoFor(view).reason == 0;
    objc_setAssociatedObject(view, kMPOwnDisplayKey, @[@((uintptr_t)w), @(own)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return own;
}
static void MPSayNow(UIView *view, BOOL enabled, BOOL sysHid, BOOL vmHid) {
    unsigned now;
    if (enabled) now = sysHid ? MSBD_MP_NOW_SYSTEM_HID : vmHid ? MSBD_MP_NOW_VIRTUAL_MAC : MSBD_MP_NOW_SHOWN;   // (the arrow, or the system's text beam)
    else if (gMPStandDown) now = MSBD_MP_NOW_ASIDE;
    else { uint64_t c = MPState(gMPConfigToken); now = (c == 0 || ((c & 1) && MPState(gMPOrientToken) == 0)) ? MSBD_MP_NOW_NO_BRIDGE : MSBD_MP_NOW_STYLE; }
    if (now == gMPNow || !MPOnOwnDisplay(view)) return;
    gMPNow = now;
    MPPublishStatus();
}
// The look at the pointer while another library changes its classes (WAITING, SHARED, ASIDE; never for ALONE), only at a plain pointer the user can
// see whose shape iPadOS has left alone for a moment: the other pointer, if there is one, shows then (common/MacPointerStatus.h MSBDMPAsideCanLook).
// When (1.8.8.2, after a device pass on iPadOS 17.5.1, where the Mac pointer never came back): after a pointer update, a main-queue turn later at the
// earliest, so the other library's own update of the pointer has run by then wherever its hook sits around ours -- at once while waiting, else 2 s
// after the last look that looked, a request inside that time kept for its end, never dropped; and while standing aside, every 2 s on a timer of its
// own while the pointer is in use (plain moves give pointeruid no update on 17.5.1), stopped at rest. Nothing of this runs for ALONE.
static void MPApplyVisibility(void);
static CFTimeInterval gMPShapeAt = -10;   // (when iPadOS last changed the pointer view's shape: a look waits until it has settled)
static CFTimeInterval gMPLookedAt = -10;  // (when a look last looked)
static BOOL gMPLooking = NO;              // (a look is running: the updates it makes ask for no other look)
static dispatch_source_t gMPAsideTimer;   // (standing aside, while the pointer is in use: a look every 2 s)
// The pointer is not in use: auto-hidden, hidden by iPadOS (another display has it, no trackpad or mouse), in Virtual Mac, or no pointer view shown.
static BOOL MPAtRest(void) {
    PUIDPointerShapeView *view = gMPShapeView;
    return !view || !view.window || gMPAutoHidden || MPHiddenBySystem(view) || MPState(gMPHideToken) == 1;
}
// One look. -1: it looked; 0: not a plain pointer now (its next update asks again); > 0: its shape is settling, ask again in that many seconds.
static double MPAsideLook(void) {
    PUIDPointerShapeView *view = gMPShapeView;
    if (!view || !view.window) return 0.0;
    PSPointerShape *shape = MPIvar(view, "_pointerShape");
    if (!shape) { @try { shape = [(id)view valueForKey:@"pointerShape"]; } @catch (id e) {} }
    BOOL plain = !(shape && shape.shapeType != 1) && !gMPHovering && !MPAtRest();
    double can = MSBDMPAsideCanLook(plain, CACurrentMediaTime(), gMPShapeAt);
    if (can >= 0.0) return can;
    gMPLookedAt = CACurrentMediaTime();
    UIViewController *c = MPControllerOf(view);
    UIView *root = MPIvar(c, "_pointerRootView");
    unsigned seen = MPAsideSeen(view, c, [root isKindOfClass:[UIView class]] ? root : nil, objc_getAssociatedObject(view, kMPCursorKey), objc_getAssociatedObject(view, kMPHidNativeKey));
    unsigned next = MSBDMPAsideNext(gMPAside, seen != 0, &gMPAsideClean);
#if DEBUG
    static unsigned lastSeen = UINT_MAX; if (seen != lastSeen || next != gMPAside || (next == MSBD_MP_V_ASIDE && !seen)) { lastSeen = seen; MPLog([NSString stringWithFormat:@"%.3f aside look: seen %u, verdict %u -> %u (clean looks %d)", CACurrentMediaTime(), seen, gMPAside, next, gMPAsideClean]); }
#endif
    if (next == gMPAside && (next != MSBD_MP_V_ASIDE || !seen || seen == gMPAsideSeen)) return -1.0;
    gMPLooking = YES;
    MPSetAside(next, next == MSBD_MP_V_ASIDE ? seen : 0);
    MPUpdateAll();
    MPApplyVisibility();
    gMPLooking = NO;
    return -1.0;
}
// One look queued at a time, in delay seconds (0: the main queue's next turn); one whose pointer is settling asks again once it has.
static void MPAsideLookIn(double delay) {
    static BOOL queued = NO;
    if (queued) return;
    queued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        queued = NO;
        if (gMPAside != MSBD_MP_V_WAITING && gMPAside != MSBD_MP_V_SHARED && gMPAside != MSBD_MP_V_ASIDE) return;
        double r = MPAsideLook();
        if (r > 0.0) MPAsideLookIn(r);
    });
}
static void MPAsideTimerSet(BOOL on);
static void MPAsideTick(void) {
    if (!MSBDMPAsideTimerWanted(gMPAside, MPAtRest())) { MPAsideTimerSet(NO); return; }   // (at rest, or no longer aside: the next update starts it again)
    double r = MPAsideLook();
    if (r > 0.0 && r < MSBD_MP_LOOK_EVERY) MPAsideLookIn(r);   // (settling: once it has, not 2 s later)
}
static void MPAsideTimerSet(BOOL on) {
    if (on == (gMPAsideTimer != nil)) return;
    if (!on) {
        dispatch_source_t t = gMPAsideTimer; gMPAsideTimer = nil;
        dispatch_source_cancel(t);
#if DEBUG
        MPLog([NSString stringWithFormat:@"%.3f aside timer stopped (verdict %u, at rest %d)", CACurrentMediaTime(), gMPAside, MPAtRest()]);
#endif
        return;
    }
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!t) return;
    uint64_t every = (uint64_t)(MSBD_MP_LOOK_EVERY * NSEC_PER_SEC);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)every), every, NSEC_PER_SEC / 5);
    dispatch_source_set_event_handler(t, ^{ MPAsideTick(); });
    gMPAsideTimer = t;
    dispatch_resume(t);
#if DEBUG
    MPLog([NSString stringWithFormat:@"%.3f aside timer started", CACurrentMediaTime()]);
#endif
}
// The timer follows the verdict and the pointer's use (MPSetAside, and every pointer update while standing aside).
static void MPAsideTimerFollow(void) { MPAsideTimerSet(MSBDMPAsideTimerWanted(gMPAside, MPAtRest())); }
// After a pointer update.
static void MPAsideMaybeLook(void) {
    if (gMPLooking) return;
    if (gMPAside == MSBD_MP_V_ASIDE) { MPAsideTimerFollow(); return; }   // (standing aside: the timer looks)
    if (gMPAside != MSBD_MP_V_WAITING && gMPAside != MSBD_MP_V_SHARED) return;
    MPAsideLookIn(MSBDMPAsideLookDelay(gMPAside, CACurrentMediaTime(), gMPLookedAt));
}
#if DEBUG
static int gMPUpdates = 0; static double gMPUpdateMs = 0, gMPUpdateMax = 0; static CFTimeInterval gMPUpdateSince = 0;
#endif
// ---- macOS's resize pointers (1.8.9, F51; common/MacResizeCursor.h) ------------------------------------------------------------------------
// SpringBoard's fact (which resize place is under the pointer) arrives as a Darwin notification state, kept here from its note (MPResizeFollow):
// nothing is read per pointer update. iPadOS's own pointer state says whether its resize arrows (accessories) are there: recorded per rendering
// controller in -setPointerState:... BEFORE iPadOS's own update runs (MPUpdate runs inside that update, through -setPointerShape:...), as their
// number, their angles and the button: MPStateInfo.
static uint64_t gMPResizeWord = 0;
static MSBDResizeLatch gMPResizeLatch;   // (a resize drag: the glyph of the press until the button is let go)
// (1.8.9, F51b: a grip's fact -- when its last word came and iPadOS's shape count then; the shape count goes up at each real change of iPadOS's
//  pointer shape, the setPointerShape hook)
static CFTimeInterval gMPResizeGripAt = 0;
static unsigned long gMPShapeSeq = 0, gMPResizeGripSeq = 0;
@interface MPStateInfo : NSObject { @public int count, nAngles; double angles[4]; BOOL pressed; uint64_t shownWord; }   // (shownWord: the glyph this controller's pointer shows, as a fact word; 0 none)
@end
@implementation MPStateInfo
@end
static const void *kMPStateInfoKey = &kMPStateInfoKey, *kMPGlyphKeyKey = &kMPGlyphKeyKey;
// The state's accessories (an array), its button and an accessory's angle, found once per class (a method answering an object or a BOOL, else
// the ivar; never a key-value lookup: this runs with every pointer update). NULL / NO where this pointeruid has none of them.
typedef struct { Class cls; IMP imp; SEL sel; ptrdiff_t ivar; } MPGetter;   // (ivar -1: none)
static void MPGetterFind(MPGetter *g, Class c, const char *sel, const char *ivarName, char want) {
    g->cls = c; g->imp = NULL; g->sel = sel_registerName(sel); g->ivar = -1;
    Method m = c ? class_getInstanceMethod(c, g->sel) : NULL;
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    if (t && t[0] == want && method_getNumberOfArguments(m) == 2) { g->imp = method_getImplementation(m); return; }
    Ivar iv = NULL; for (Class k = c; k && !iv; k = class_getSuperclass(k)) iv = class_getInstanceVariable(k, ivarName);
    const char *it = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (it && it[0] == want) g->ivar = ivar_getOffset(iv);
}
// (*known: the state has accessories at all -- a getter or the ivar; then nil is none, B0 18.5)
static NSArray *MPStateAccessories(id state, BOOL *known) {
    static MPGetter g;
    *known = NO;
    if (!state) return nil;
    if (g.cls != object_getClass(state)) MPGetterFind(&g, object_getClass(state), "accessories", "_accessories", '@');
    *known = g.imp != NULL || g.ivar >= 0;
    id a = g.imp ? ((id (*)(id, SEL))g.imp)(state, g.sel) : g.ivar >= 0 ? (__bridge id)*(void *const *)((uint8_t *)(__bridge void *)state + g.ivar) : nil;
    return [a isKindOfClass:[NSArray class]] ? a : nil;
}
static BOOL MPStatePressed(id state) {
    static MPGetter g;
    if (!state) return NO;
    if (g.cls != object_getClass(state)) { MPGetterFind(&g, object_getClass(state), "pressed", "_pressed", 'B'); if (!g.imp && g.ivar < 0) MPGetterFind(&g, object_getClass(state), "isPressed", "_pressed", 'B'); }
    return g.imp ? ((BOOL (*)(id, SEL))g.imp)(state, g.sel) : g.ivar >= 0 ? *((BOOL *)((uint8_t *)(__bridge void *)state + g.ivar)) : NO;
}
static BOOL MPAccessoryAngle(id acc, double *out) {
    static Class cls; static ptrdiff_t off = -1;
    if (!acc) return NO;
    if (object_getClass(acc) != cls) {
        cls = object_getClass(acc); off = -1;
        Ivar iv = NULL; for (Class k = cls; k && !iv; k = class_getSuperclass(k)) iv = class_getInstanceVariable(k, "_angle");
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        if (t && t[0] == 'd') off = ivar_getOffset(iv);
    }
    if (off < 0) return NO;
    *out = *(double *)((uint8_t *)(__bridge void *)acc + off);
    return YES;
}
// (in -setPointerState:..., before iPadOS's update; c: the rendering controller)
static MPStateInfo *MPRecordState(UIViewController *c, id state) {
    MPStateInfo *i = objc_getAssociatedObject(c, kMPStateInfoKey);
    if (!i) { i = [MPStateInfo new]; objc_setAssociatedObject(c, kMPStateInfoKey, i, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    BOOL known = NO;
    NSArray *acc = MPStateAccessories(state, &known);
    i->count = known ? (int)acc.count : -1; i->nAngles = 0;   // (-1: this pointeruid's state has no accessories at all)
    for (NSUInteger k = 0; k < acc.count && i->nAngles < 4; k++) { double a = 0; if (MPAccessoryAngle(acc[k], &a)) i->angles[i->nAngles++] = a; }
    i->pressed = MPStatePressed(state);
    return i;
}
// Where the state cannot say (no accessories on this version's state at all): the accessories container's shown subviews (no angles), read only
// with a fact, only as the evidence for a glyph, never to take the beam away (review 1.8.9 F51, finding 2).
static int MPAccessoryViewsShown(UIViewController *c) {
    UIView *box = MPIvar(c, "_accessoryContainerView");
    if (![box isKindOfClass:[UIView class]]) return 0;
    int n = 0; for (UIView *v in box.subviews) if (!v.hidden && v.alpha > 0.01) n++;
    return n;
}
// Each glyph's path, made once (common/MacResizeCursor.h MSBDResizeGlyphCreate), kept for the run.
static CGPathRef MPResizeGlyph(MSBDResizeFact f) {
    static NSMutableDictionary<NSNumber *, id> *made;
    unsigned key = MSBDResizeGlyphKey(f);
    if (!key) return NULL;
    if (!made) made = [NSMutableDictionary dictionary];
    id p = made[@(key)];
    if (!p) { CGPathRef np = MSBDResizeGlyphCreate(f); if (!np) return NULL; p = (__bridge_transfer id)np; made[@(key)] = p; }
    return (__bridge CGPathRef)p;
}
// iPadOS's text beam (common/MacResizeCursor.h MSBDPointerBeamShape): the rule read in B0 on 18 (a sized type 4 is iPadOS's resize shape, not
// text); on 15-17, where a type 4 beam's size was never measured (17.5.1 over Finder's search field, 1.8.8), every type 4 stays the beam as in
// 1.8.8.4 (review 1.8.9 F51, finding 4) -- there a band shows macOS's resize cursor only with SpringBoard's fact, else iPadOS's own shape as before.
static BOOL MPBeamRuleFrom18(void) {
    static int v = -1;
    if (v < 0) v = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){18, 0, 0}] ? 1 : 0;
    return v == 1;
}
// Settings > Pointer > Mac Resize Pointers (1.8.9, KT 25 Nov; on by default on iPadOS 18, off on 15-17), said by SpringBoard in the config word
// (common/MacResizeCursor.h MSBD_RZ_CONFIG_BIT, with Pointer Style Mac). Off: MPUpdate shows 1.8.8.4's look (MSBDPointerLook1884) and nothing of
// the above is recorded, kept or read; switched off, what was kept goes at once (the drag's latch, every controller's record), so a switch-on
// starts from nothing. Read at the start and at each "changed" note (SpringBoard posts it with every change of the config word), never per
// pointer update (the switch's review, finding 4).
static BOOL gMPResizeOnNow = NO;
static void MPResizeForget(void) {
    memset(&gMPResizeLatch, 0, sizeof gMPResizeLatch);
    UIViewController *main = gMPController;
    if (main) objc_setAssociatedObject(main, kMPStateInfoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (PUIDPointerShapeView *v in [gMPShapeViews allObjects]) { UIViewController *c = MPControllerOf(v); if (c) objc_setAssociatedObject(c, kMPStateInfoKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static void MPResizeRead(void) {
    BOOL on = (MPState(gMPConfigToken) & MSBD_RZ_CONFIG_BIT) != 0;
    if (on == gMPResizeOnNow) return;
    gMPResizeOnNow = on;
    if (!on) MPResizeForget();
}
static BOOL MPResizeOn(void) { return gMPResizeOnNow; }
// What the pointer shows. The system's pointer shape (PSPointerShape) as seen on 15-17:
//  - type 1, the round pointer (also while it hovers an icon or our status bar, where the system only lifts or highlights the content): the arrow;
//  - type 3, a rounded rectangle: a button's or a control's highlight (17.5.1: the Clock tab bar's World Clock, 41 x 182 pt, radius 8; our traffic
//    lights, 20 x 20 radius 8 -- "the circle at the window edges", KT on 18.5) -- the arrow, as on a Mac; a thin one (4 pt or less) is the text beam
//    (15.6.1 and 18.5 over a search field: 3 x 24, radius 1.5, F51's B0): the system's beam;
//  - type 4, a path: the text beam of iPadOS 17 (17.5.1 over Finder's search field, 1.8.8) when it has no size of its own or is under 6 pt across:
//    the system's beam; with a size, iPadOS 18.5's shape for a window's resize band (35 x 14 pt along an edge, 25.8 pt square at a corner, its
//    arrowheads drawn in it; F51's B0): the Mac pointer, macOS's resize cursor there (1.8.9, F51);
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
    // (Hide in Virtual Mac hides the pointer's root view, MPApplyVisibility; the arrow in the top window is not under it, so it goes too)
    // (1.8.8.2: the same reads in the same order as one line before, kept apart for the word on why the arrow is not shown, MPSayNow)
    BOOL enabled = MPEnabled();
    // What shows (1.8.9, F51, common/MacResizeCursor.h MSBDPointerLook): iPadOS's text beam only for a beam's shape with no arrows around it --
    // on 18 a thin shape or a type 4 without a size of its own (MSBDPointerBeamShape): iPadOS 18.5 gives a window's resize band a sized type 4
    // path shape, which the old rule (any type 4) took for text and left to iPadOS, its grey capsule with arrowheads (KT, 25 Nov); on 15-17 any
    // type 4 too, as before (MPBeamRuleFrom18); macOS's resize cursor where SpringBoard's fact and iPadOS's own resize shape (or arrows) agree,
    // or a resize drag holds it; else the arrow. With Mac Resize Pointers off (Settings > Pointer; MPResizeOn): 1.8.8.4's look, nothing else read.
    UIViewController *ctl = MPControllerOf(view);
    BOOL rzOn = MPResizeOn();
    MPStateInfo *si = rzOn && ctl ? objc_getAssociatedObject(ctl, kMPStateInfoKey) : nil;
    int accessories = si && si->count > 0 ? si->count : 0;   // (the state's own arrows; unknown counts as none for the beam)
    CFTimeInterval now = CACurrentMediaTime();
    BOOL held = NO;
    MSBDResizeFact fact = { 0, 0, 0, 0, 0, 0 };
    int look;
    if (!rzOn) look = MSBDPointerLook1884(type, sb);   // (off: iPadOS's own shape for its text beam -- a thin shape, any type 4 --, else the arrow)
    else {
        BOOL beamShape = MPBeamRuleFrom18() ? MSBDPointerBeamShape(type, sb.size.width, sb.size.height) : (MSBDPointerBeamShape(type, sb.size.width, sb.size.height) || type == 4);
        held = MSBDResizeLatchHolds(&gMPResizeLatch, now);   // (a drag, or the moment after its button-up until SpringBoard's next word)
        fact = held ? gMPResizeLatch.fact : MSBDResizeUnpack(gMPResizeWord);
        BOOL factHere = NO, evidence = NO;
        if (fact.kind && !held) {   // (no fact: nothing more is read -- the usual case)
            factHere = (fact.display == 1) == !MPOnOwnDisplay(view);
            // (F51b: a grip's fact only while fresh -- its lease, and no change of iPadOS's own shape since its last word)
            if (factHere && fact.source == MSBD_RZ_SRC_GRIP && !MSBDResizeGripFresh(now, gMPResizeGripAt, gMPShapeSeq, gMPResizeGripSeq)) factHere = NO;
            if (factHere) {
                BOOL known = si && si->count >= 0;
                int n = known ? si->count : (!beamShape && ctl ? MPAccessoryViewsShown(ctl) : 0);
                evidence = MSBDResizeEvidence(fact, type, sb.size.width, sb.size.height, n, known ? si->angles : NULL, known ? si->nAngles : 0);
            }
        }
        look = MSBDPointerLook(beamShape, accessories, factHere, evidence, held);
    }
    BOOL systemShape = look == MSBD_PTR_BEAM;   // (only the text beam -- every other style gets the Mac pointer)
    BOOL sysHid = enabled && !systemShape && MPHiddenBySystem(view);
    BOOL vmHid = enabled && !systemShape && !sysHid && MPState(gMPHideToken) == 1;
    BOOL want = enabled && !systemShape && !sysHid && !vmHid;
    MPSayNow(view, enabled, sysHid, vmHid);
    MPAsideMaybeLook();
    CAShapeLayer *a = want ? MPCursorLayer(view) : objc_getAssociatedObject(view, kMPCursorKey);
    CGPathRef glyph = (want && look == MSBD_PTR_RESIZE) ? MPResizeGlyph(fact) : NULL;
    CGPathRef wantPath = glyph ?: MPCursorPath();   // (the arrow's layer draws the resize glyph: the same edge, shadow, size and turn)
    // (which path the layer has, by the glyph's key -- 0 the arrow: Core Animation keeps its own copy of a path, so the pointer never matches,
    //  review 1.8.9 F51 finding 1)
    unsigned wantKey = glyph ? MSBDResizeGlyphKey(fact) : 0;
    unsigned hasKey = a ? [objc_getAssociatedObject(a, kMPGlyphKeyKey) unsignedIntValue] : 0;
    if (si && enabled && (systemShape || !sysHid)) si->shownWord = glyph && !MSBDResizeLatchGraceOnly(&gMPResizeLatch, now) ? MSBDResizePack(fact) : 0;   // (this display's pointer: what a press there latches -- never the glyph a released drag's grace holds, review F51b finding 3)
    CALayer *host = view.layer;   // (the arrow rides the pointer view itself: its origin is the pointer's position)
    NSArray<UIView *> *natives = MPNativeViews(view);
    NSMutableArray *hid = objc_getAssociatedObject(view, kMPHidNativeKey);
    CGAffineTransform t = a ? MPCursorTransform(view) : CGAffineTransformIdentity;
    float fadeTarget = gMPAutoHidden ? 0.0f : 1.0f;
    // nothing to change (the usual case: this runs with the pointer's own updates): no transaction at all
    BOOL nativesShown = NO; for (UIView *v in natives) if (!v.layer.hidden) { nativesShown = YES; break; }
    BOOL settled = want ? (a.superlayer == host && host.sublayers.lastObject == a && !a.hidden && CGAffineTransformEqualToTransform(a.affineTransform, t) && !nativesShown && a.opacity == fadeTarget && hasKey == wantKey)
                        : ((!a || a.hidden) && !hid.count);
    if (!settled) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (a && !CGAffineTransformEqualToTransform(a.affineTransform, t)) a.affineTransform = t;   // (kept turned while hidden too -- the iPad turned while the pointer
                                                                                                    //  was on the TV left the hidden arrow at the old angle, 29 Sep)
        if (want) {
            if (hasKey != wantKey) {   // (the arrow, or one of macOS's resize cursors: the shadow from the same path)
                a.path = wantPath; a.shadowPath = wantPath;
                objc_setAssociatedObject(a, kMPGlyphKeyKey, @(wantKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if DEBUG
                MPLog([NSString stringWithFormat:@"%.3f resize: %@ (fact kind %u position %u directions %u display %u, arrows %d, latched %d)", CACurrentMediaTime(), glyph ? @"macOS's resize cursor" : @"the arrow", fact.kind, fact.position, fact.directions, fact.display, accessories, gMPResizeLatch.live]);
#endif
            }
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
    MPSpecular(ctl, want);
#if DEBUG
    double ms = (CACurrentMediaTime() - t0) * 1000.0;
    gMPUpdates++; gMPUpdateMs += ms; if (ms > gMPUpdateMax) gMPUpdateMax = ms;
    if (CACurrentMediaTime() - gMPUpdateSince > 2.0) {
        if (gMPUpdateSince > 0) MPLog([NSString stringWithFormat:@"%.3f updates: %d in %.1f s, avg %.3f ms, max %.3f ms (shape %lld, arrow %d, look %d)", CACurrentMediaTime(), gMPUpdates, CACurrentMediaTime() - gMPUpdateSince, gMPUpdates ? gMPUpdateMs / gMPUpdates : 0, gMPUpdateMax, type, want, look]);
        gMPUpdates = 0; gMPUpdateMs = 0; gMPUpdateMax = 0; gMPUpdateSince = CACurrentMediaTime();
    }
#endif
}
// Hide in Virtual Mac: never write the root view's hidden unless we hid it (the system fades the pointer out with it). Standing aside (1.8.8.2: that
// can now begin while the pointer runs): never hidden by us, and given back if we had hidden it.
static void MPApplyVisibility(void) {
    UIViewController *c = gMPController; if (!c) return;
    BOOL hide = !gMPStandDown && MPState(gMPHideToken) == 1;
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
    if (main && (!before || ![before isEqual:shapeObj])) {   // (let iPadOS set each native view's own visibility for the new shape; MPUpdate hides what stays shown)
        NSMutableArray *hid = objc_getAssociatedObject(self, kMPHidNativeKey);
        if (hid.count) {
            [CATransaction begin]; [CATransaction setDisableActions:YES];
            for (UIView *v in hid) v.layer.hidden = NO;
            [hid removeAllObjects];
            [CATransaction commit];
        }
    }
    %orig(shapeObj, morph, completion);
    if (!main) return;
    gMPShapeView = (PUIDPointerShapeView *)self;
    MPRemember((PUIDPointerShapeView *)self);
    if (before && [before isEqual:shapeObj]) return;   // (the same shape again -- 17 sets it every frame while a control is hovered: nothing to do)
    gMPShapeAt = CACurrentMediaTime();   // (1.8.8.2: a look at another pointer waits until the shape has settled, MSBDMPAsideCanLook)
    gMPShapeSeq++;   // (1.8.9, F51b: a grip's fact is not trusted past a change of iPadOS's own shape, MSBDResizeGripFresh)
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
    // (1.8.9, F51: iPadOS's arrows and the button, recorded before iPadOS's own update -- MPUpdate runs inside it; the latch from what shows now.
    //  Mac Resize Pointers off: nothing recorded, no latch -- 1.8.8.4's update)
    MPStateInfo *si = MPResizeOn() ? MPRecordState((UIViewController *)self, state) : nil;
    BOOL wasLive = gMPResizeLatch.live;
    if (si) {   // (only the display the pointer is on: another display's controller, hidden by iPadOS, never ends a drag on this one)
        PUIDPointerShapeView *ownNow = MPIvar(self, "_pointerShapeView");
        if (![ownNow isKindOfClass:[UIView class]] || !MPHiddenBySystem(ownNow))
            MSBDResizeLatchStepAt(&gMPResizeLatch, si->pressed, gMPAutoHidden, si->shownWord != 0, MSBDResizeUnpack(si->shownWord), CACurrentMediaTime());
        if (wasLive && !gMPResizeLatch.live && gMPResizeLatch.graceUntil > 0)   // (the grace's end draws again, unless a word came first)
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MSBD_RZ_LATCH_GRACE + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MPUpdateAll(); });
    }
#if DEBUG
    if (wasLive != gMPResizeLatch.live) MPLog([NSString stringWithFormat:@"%.3f resize: drag %@", CACurrentMediaTime(), gMPResizeLatch.live ? @"latched (the press's glyph until the button is let go)" : @"over"]);
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
        NSUInteger sig = (gMPAutoHidden ? 1 : 0) | (gMPHovering ? 2 : 0) | ((NSUInteger)(MPVisibilityState((UIViewController *)self) & 0xff) << 2)
                       | (si ? ((NSUInteger)((si->count + 1) & 0xF) << 10) | (gMPResizeLatch.live ? (1u << 14) : 0) : 0);   // (F51: the arrows and the latch change what shows; off: 1.8.8.4's)
        NSNumber *last = objc_getAssociatedObject(own, kMPStateSigKey);
        if (!last || last.unsignedIntegerValue != sig) {
            objc_setAssociatedObject(own, kMPStateSigKey, @(sig), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            MPRemember(own);
            if (!gMPShapeView) gMPShapeView = own;
            MPUpdate(own);
            // SpringBoard is told when iPadOS hides the pointer and when it shows again (common/PointerFade.h; 1.8.8, D48: Magnify Traffic Lights' hold
            // under a resting pointer ends at the fade): the iPad's own display only (that hold is the iPad's; with another display each has its own
            // controller and state), here, where this display's state changed, so only at a change. Whatever the Pointer Style, also standing down.
            if (MPDisplayInfoFor(own).reason == 0) {
                static int fadeToken = 0; static BOOL fadeTried = NO, fadeOK = NO; static uint64_t fadeSaid = MSBDPointerFadeUnsaid;
                if (!fadeTried) { fadeTried = YES; fadeOK = notify_register_check(kMSBDPointerFadeNote, &fadeToken) == NOTIFY_STATUS_OK; }   // (once)
                uint64_t fade = MSBDPointerFadeOf(gMPAutoHidden);
                if (fadeOK && fade != fadeSaid) { fadeSaid = fade; notify_set_state(fadeToken, fade); notify_post(kMSBDPointerFadeNote); }
            }
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
        MPStateInfo *si = gMPController ? objc_getAssociatedObject(gMPController, kMPStateInfoKey) : nil;
        NSString *rz = [NSString stringWithFormat:@" | resize fact 0x%llx shown 0x%llx latched %d, arrows %d (angles %d: %.3f %.3f), pressed %d, glyph %u", gMPResizeWord, si ? si->shownWord : 0ULL, gMPResizeLatch.live,
            si ? si->count : -2, si ? si->nAngles : 0, si && si->nAngles > 0 ? si->angles[0] : 0.0, si && si->nAngles > 1 ? si->angles[1] : 0.0, si ? si->pressed : 0, a ? [objc_getAssociatedObject(a, kMPGlyphKeyKey) unsignedIntValue] : 0u];
        NSString *st = [NSString stringWithFormat:@"view %@ at %@ top %@ | other display %d (window screen %@, main %@) | shape %lld %@ | hovering %d autohidden %d opacity %.2f | enabled %d size %.2f rot %.2f | cursor %@ hidden %d in view %d transform [%.2f %.2f %.2f %.2f] | native hidden %d weHid %d views | root hidden %d weHidRoot %d | stand down %d (aside verdict %u seen %u, missing 0x%x, now %u)%@",
            sv ? NSStringFromClass([sv class]) : @"-", NSStringFromCGRect(sv.frame), win ? [NSString stringWithFormat:@"%@ %@ window %p", NSStringFromClass([win class]), NSStringFromCGRect(win.frame), sv.window] : @"-",
            sv ? MPDisplayInfoFor(sv).reason != 0 : 0, sv.window.screen ? NSStringFromCGRect(sv.window.screen.bounds) : @"-", NSStringFromCGRect([UIScreen mainScreen].bounds),
            shape.shapeType, NSStringFromCGRect(shape.bounds), gMPHovering, gMPAutoHidden, a ? a.opacity : -1, MPEnabled(), MPSize(sv), sv ? MPRotationFor(sv) : MPRotation(),
            a ? @"yes" : @"no", a.hidden, a.superlayer == sv.layer, t.a, t.b, t.c, t.d, native.layer.hidden, (int)[objc_getAssociatedObject(sv, kMPHidNativeKey) count], [[gMPController valueForKey:@"_pointerRootView"] isHidden], gMPWeHidRoot, gMPStandDown, gMPAside, gMPAsideSeen, gMPMissing, gMPNow, rz];
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
    MPPublishStatus();   // (1.8.8.2: "loaded in this pointeruid" at once, its pid; SpringBoard compares it with the pointeruid that runs)
    MPInstallNoMagnetism();
    notify_register_check("com.besiktasliseba.macpointer.config", &gMPConfigToken);
    notify_register_check("com.besiktasliseba.macpointer.orient", &gMPOrientToken);
    notify_register_check("com.besiktasliseba.macpointer.hide", &gMPHideToken);
    int changed = 0;
    MPResizeRead();   // (1.8.9: Mac Resize Pointers, from the config word as it stands)
    notify_register_dispatch("com.besiktasliseba.macpointer.changed", &changed, dispatch_get_main_queue(), ^(int t) { MPResizeRead(); MPUpdateAll(); MPApplyVisibility(); MPPublishPresence(); });
    // (1.8.9, F51: SpringBoard's resize fact, kept at each change -- the order of it and the pointer's own update does not matter, whichever
    //  comes last decides)
    int resizeToken = 0;
    if (notify_register_dispatch(MSBD_RZ_NOTE, &resizeToken, dispatch_get_main_queue(), ^(int t) {
            uint64_t w = 0; notify_get_state(t, &w);
            if (w == gMPResizeWord) return;
            gMPResizeWord = w;
            if (!MPResizeOn()) return;   // (Mac Resize Pointers off: kept, never drawn -- 1.8.8.4's look; SpringBoard says no fact then anyway)
            MSBDResizeLatchWord(&gMPResizeLatch);   // (a word after a drag's button-up ends its grace)
            if (MSBDResizeUnpack(w).source == MSBD_RZ_SRC_GRIP) {   // (F51b: a grip's word starts its lease; past it, drawn again without it)
                gMPResizeGripAt = CACurrentMediaTime(); gMPResizeGripSeq = gMPShapeSeq;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MSBD_RZ_GRIP_LEASE + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (gMPResizeWord == w) MPUpdateAll();   // (no newer word: the lease is over)
                });
            }
#if DEBUG
            {   // (a change of place only: a grip's fact is said again every 0.4 s and at each hover in it -- review F51b, finding 12)
                static uint64_t lastLogged = 0;
                MSBDResizeFact f = MSBDResizeUnpack(w), g = MSBDResizeUnpack(lastLogged);
                if (!MSBDResizeSamePlace(f, g) || f.source != g.source)
                    MPLog([NSString stringWithFormat:@"%.3f resize fact: kind %u position %u directions %u display %u source %u", CACurrentMediaTime(), f.kind, f.position, f.directions, f.display, f.source]);
                lastLogged = w;
            }
#endif
            MPUpdateAll();
        }) == NOTIFY_STATUS_OK) notify_get_state(resizeToken, &gMPResizeWord);
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
