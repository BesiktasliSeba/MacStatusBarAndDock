// Bounce.m -- Settings > Dock > Animate Opening Applications (MacStatusBar&Dock 1.8.4 item 2, macOS's own option of that name): a Dock icon bounces
// while its app opens, and stops once the app's window shows. The rules: common/DockBounce.h (plain C, tools/test-dockbounce.sh).
//
// Started from Dock.x's hook on -[SBIconView tapGestureDidChange:] (where every icon tap starts, on 15-18; installed only with its 15-18 shape) for a
// Dock icon of an app with no process yet: an app already running comes forward at once, as on a Mac, and does not bounce. The bounce is one Core
// Animation loop on the icon's own layer (an additive offset of its position: the magnification's scale and a side Dock's turn of its content stay
// as they are), so the render server draws it and SpringBoard's main thread does nothing per frame. "Its window shows" is SpringBoard's own process
// state of the app turning foreground (-[SBApplication processState] -isForeground, read in the shapes RunningIndicator.m reads it): that is the
// app's scene on screen, full screen or in any engine's window. A 0.2 s look runs only while an icon bounces. The icon then finishes the bounce it is
// in; the running dot under it (RunningIndicator.m) is held still meanwhile, as a Mac's light stays on the shelf.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DMLog.h"
#include "../common/DockBounce.h"
#include "../common/DockSide.h"
@interface UIWindow (DMBouncePrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

static BOOL gBounceOn = NO;   // the switch (Dock.x DMLoadPrefs: DMBounceSetOn)
static void DMBounceDropAll(NSString *why);
void DMBounceSetOn(BOOL on) {
    if (on == gBounceOn) return;
    gBounceOn = on;
    DMLog([NSString stringWithFormat:@"[bounce] Animate Opening Applications %@", on ? @"on" : @"off"]);
    if (!on) DMBounceDropAll(@"the switch went off");   // (an icon bouncing now lands at once: nothing of ours stays on it)
}

static BOOL DMBounceShape(Class c, const char *sel, const char *enc, BOOL meta) {
    Method m = !c ? NULL : meta ? class_getClassMethod(c, sel_registerName(sel)) : class_getInstanceMethod(c, sel_registerName(sel));
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    return e && !strcmp(e, enc);
}
// The app SpringBoard has for a bundle (SBApplicationController -applicationWithBundleIdentifier:), and its process: running (a pid) and on screen
// (foreground). Only in these shapes; anything else reads as "no app" (no bounce).
static id DMBounceApp(NSString *bid) {
    Class cc = objc_getClass("SBApplicationController");
    if (!bid.length || !DMBounceShape(cc, "sharedInstance", "@16@0:8", YES) || !DMBounceShape(cc, "applicationWithBundleIdentifier:", "@24@0:8@16", NO)) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)cc, sel_registerName("sharedInstance"));
    return controller ? ((id (*)(id, SEL, id))objc_msgSend)(controller, sel_registerName("applicationWithBundleIdentifier:"), bid) : nil;
}
static BOOL DMBounceProcess(id app, int *pid, BOOL *foreground) {
    *pid = 0; *foreground = NO;
    if (!app || !DMBounceShape(object_getClass(app), "processState", "@16@0:8", NO)) return NO;
    id st = ((id (*)(id, SEL))objc_msgSend)(app, sel_registerName("processState"));
    if (!st) return YES;   // (no process: not running)
    if (!DMBounceShape(object_getClass(st), "pid", "i16@0:8", NO) || !DMBounceShape(object_getClass(st), "isForeground", "B16@0:8", NO)) return NO;
    *pid = ((int (*)(id, SEL))objc_msgSend)(st, sel_registerName("pid"));
    *foreground = ((BOOL (*)(id, SEL))objc_msgSend)(st, sel_registerName("isForeground"));
    return YES;
}
static BOOL DMBounceIsDockIcon(UIView *icon) {   // (inside the Dock's platter: its own icons and its recents, as Dock.x's DMIsDockIcon)
    Class platter = objc_getClass("SBFloatingDockPlatterView");
    if (!platter) return NO;
    for (UIView *v = icon.superview; v; v = v.superview) if ([v isKindOfClass:platter]) return YES;
    return NO;
}
static id DMBounceObj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return o && [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static BOOL DMBounceBool(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o || !DMBounceShape(object_getClass(o), sel, "B16@0:8", NO)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s);
}
static BOOL DMBounceEditing(void) {   // (the Home Screen being edited: a tap launches nothing then)
    id ic = DMBounceObj((id)objc_getClass("SBIconController"), "sharedInstance");
    return DMBounceBool(DMBounceObj(ic, "iconManager"), "isEditing");
}

@interface DMBounce : NSObject
@property (nonatomic, weak) UIView *icon, *dot;
@property (nonatomic, strong) CALayer *iconLayer, *dotLayer;   // (the layers that carry the bounce: reached also once their views are gone -- review 1.8.4 M3)
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic) CFTimeInterval start, layerStart;   // (CACurrentMediaTime; the same moment in the icon layer's own time)
@property (nonatomic) double height;
@property (nonatomic) BOOL launched, ending;
@end
@implementation DMBounce
@end
static NSMutableArray<DMBounce *> *gBounces;
static dispatch_source_t gBounceLook;
static NSString *const kDMBounceKey = @"msbd.bounce";
// An entry that ends without landing -- its icon left the window, its view shows another app now (SpringBoard reuses icon views), the switch went
// off --: its bounce comes off the icon's layer and the dot's at once, so no view keeps an endless bounce of ours (review 1.8.4 M3).
static void DMBounceDrop(DMBounce *b, NSString *why) {
    [b.iconLayer removeAnimationForKey:kDMBounceKey];
    [b.dotLayer removeAnimationForKey:kDMBounceKey];
    [gBounces removeObject:b];
    DMLog([NSString stringWithFormat:@"[bounce] %@: stopped (%@)", b.bundleID, why]);
}
static void DMBounceDropAll(NSString *why) {
    for (DMBounce *b in [gBounces copy]) DMBounceDrop(b, why);
    if (gBounceLook) { dispatch_source_cancel(gBounceLook); gBounceLook = nil; }
}
extern UIView *DMRunningDotOf(UIView *iconView);   // (RunningIndicator.m: the icon's running dot, nil when it has none)

// One bounce, up and back: up slowing, down speeding, as a ball's; `repeat` times (HUGE_VALF: until it is ended), from the layer time `begin`.
static CAKeyframeAnimation *DMBounceAnimation(double dy, CFTimeInterval begin, float repeat) {
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"position.y"];
    a.additive = YES;
    a.values = @[@0.0, @(dy), @0.0];
    a.keyTimes = @[@0.0, @0.5, @1.0];
    a.timingFunctions = @[[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
    a.duration = MSBD_BOUNCE_PERIOD;
    a.beginTime = begin;
    a.repeatCount = repeat;
    a.removedOnCompletion = YES;
    return a;
}
// The icon's picture height, for the bounce's height: its icon image view where there is one (17+ draws the picture there), else the view.
static double DMBouncePictureHeight(UIView *icon) {
    for (UIView *sub in icon.subviews)
        if ([NSStringFromClass([sub class]) rangeOfString:@"IconImageView"].location != NSNotFound && !sub.hidden && sub.bounds.size.height > 8.0) return sub.bounds.size.height;
    return icon.bounds.size.height * 0.8;
}
static void DMBounceLook(void);
static void DMBounceStart(UIView *icon, NSString *bid) {
    if (!icon.window || icon.hidden) return;
    if (!gBounces) gBounces = [NSMutableArray array];
    for (DMBounce *b in gBounces) if (b.icon == icon) return;   // (already bouncing: a second tap does not start another)
    DM_FEATURE_MARK("dock-launch-bounce");
    DMBounce *b = [DMBounce new];
    b.icon = icon; b.bundleID = bid; b.iconLayer = icon.layer;
    b.start = CACurrentMediaTime();
    b.layerStart = [icon.layer convertTime:b.start fromLayer:nil];
    b.height = MSBDBounceHeight(DMBouncePictureHeight(icon));
    [icon.layer addAnimation:DMBounceAnimation(-b.height, b.layerStart, HUGE_VALF) forKey:kDMBounceKey];
    [gBounces addObject:b];
    DMLog([NSString stringWithFormat:@"[bounce] %@'s icon bounces while it opens (%.0f pt)", bid, b.height]);
    if (!gBounceLook) {
        gBounceLook = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(gBounceLook, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), (uint64_t)(0.2 * NSEC_PER_SEC), 50 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(gBounceLook, ^{ DMBounceLook(); });
        dispatch_resume(gBounceLook);
    }
}
// The running dot stays on the shelf: the same bounce the other way on its layer, while the icon bounces (it appears once the app runs).
static void DMBounceHoldDot(DMBounce *b) {
    UIView *icon = b.icon, *dot = DMRunningDotOf(icon);
    if (!dot || dot.hidden || dot == b.dot) return;
    [b.dotLayer removeAnimationForKey:kDMBounceKey];   // (a dot that was swapped: its old layer lands too)
    b.dot = dot; b.dotLayer = dot.layer;
    CFTimeInterval begin = [dot.layer convertTime:[icon.layer convertTime:b.layerStart toLayer:nil] fromLayer:nil];
    [dot.layer addAnimation:DMBounceAnimation(b.height, begin, b.ending ? (float)ceil((CACurrentMediaTime() - b.start) / MSBD_BOUNCE_PERIOD) : HUGE_VALF) forKey:kDMBounceKey];
}
// Every 0.2 s while an icon bounces: has its app's window shown (or did it never start, or has it gone on too long)? Then it finishes the bounce
// it is in: the endless loop is swapped for one of a set number of bounces from the same start, so the icon lands without a jump.
static void DMBounceLook(void) {
    CFTimeInterval now = CACurrentMediaTime();
    for (DMBounce *b in [gBounces copy]) {
        UIView *icon = b.icon;
        if (!icon || !icon.window) { DMBounceDrop(b, @"its icon left the window"); continue; }
        if (![DMBounceObj(DMBounceObj(icon, "icon"), "applicationBundleID") isEqual:b.bundleID]) { DMBounceDrop(b, @"its icon view shows another app now"); continue; }
        if (b.ending) { if (![b.iconLayer animationForKey:kDMBounceKey]) { [b.dotLayer removeAnimationForKey:kDMBounceKey]; [gBounces removeObject:b]; } continue; }
        int pid = 0; BOOL fg = NO;
        DMBounceProcess(DMBounceApp(b.bundleID), &pid, &fg);
        if (pid > 0) b.launched = YES;
        BOOL gone = b.launched && pid == 0;   // (its process came and went before its window showed: it crashed or quit while opening -- review 1.8.4 Pass 4 L4)
        DMBounceHoldDot(b);
        double ends = MSBDBounceEndsAt(b.start, now, fg, b.launched, gone, MSBD_BOUNCE_PERIOD, MSBD_BOUNCE_CAP, MSBD_BOUNCE_NO_LAUNCH);
        if (ends <= 0.0) continue;
        b.ending = YES;
        float cycles = (float)llround((ends - b.start) / MSBD_BOUNCE_PERIOD);
        [b.iconLayer addAnimation:DMBounceAnimation(-b.height, b.layerStart, cycles) forKey:kDMBounceKey];
        CALayer *dotLayer = b.dotLayer;
        if (dotLayer) [dotLayer addAnimation:DMBounceAnimation(b.height, [dotLayer convertTime:[b.iconLayer convertTime:b.layerStart toLayer:nil] fromLayer:nil], cycles) forKey:kDMBounceKey];
        DMLog([NSString stringWithFormat:@"[bounce] %@: %@ -- lands after %.0f bounce(s)", b.bundleID, fg ? @"its window shows" : gone ? @"its app quit before its window showed" : !b.launched ? @"no app started" : @"too long", cycles]);
    }
    if (!gBounces.count && gBounceLook) { dispatch_source_cancel(gBounceLook); gBounceLook = nil; }
}

// Dock.x's tap hook asks before the tap is passed on (the app may be started by it): the bundle to bounce for, or nil.
NSString *DMBounceTapWanted(UIView *iconView, UIGestureRecognizer *g) {
    if (!gBounceOn || ![g isKindOfClass:[UIGestureRecognizer class]] || g.state != UIGestureRecognizerStateEnded) return nil;
    if (!DMBounceIsDockIcon(iconView)) return nil;
    id icon = DMBounceObj(iconView, "icon");
    if (DMBounceBool(icon, "isFolderIcon")) return nil;
    id bid = DMBounceObj(icon, "applicationBundleID");
    if (![bid isKindOfClass:[NSString class]] || ![bid length]) return nil;
    id app = DMBounceApp(bid);
    int pid = 0; BOOL fg = NO;
    BOOL known = DMBounceProcess(app, &pid, &fg);
    BOOL want = MSBDBounceWanted(gBounceOn, UIAccessibilityIsReduceMotionEnabled(), app != nil && known, pid > 0, DMBounceEditing());
    return want ? bid : nil;
}
void DMBounceTapped(UIView *iconView, NSString *bid) { if (bid) DMBounceStart(iconView, bid); }

#if DEBUG
// (debug: "bounce_<bundle>" in /tmp/dockmag-escape -- that app's Dock icon bounces as if tapped, its app opened or not: the look, the dot, the landing)
void DMBounceDebug(NSString *bid) {
    Class ic = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *todo = [NSMutableArray array];
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) if ([NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) [todo addObject:w];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (ic && [v isKindOfClass:ic] && DMBounceIsDockIcon(v) && [DMBounceObj(DMBounceObj(v, "icon"), "applicationBundleID") isEqual:bid]) { DMBounceStart(v, bid); return; }
        [todo addObjectsFromArray:v.subviews];
    }
    DMLog([NSString stringWithFormat:@"[bounce] no Dock icon of %@", bid]);
}
#endif
