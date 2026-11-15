// test-battinsideink.m -- see test-battinsideink.sh. The number inside the battery icon (Battery Percentage in Icon), the real code cut out of
// statusbar/BatteryMenu.h (from gBattInsideOn to DMBattInsideApplyPref: bi-block.inc) with common/BatteryInside.h, on UIKit's own battery views
// (_UIBatteryView: shape layers; _UIStaticBatteryView: images, what 18.5's bar shows) in a bar of each appearance, rendered at 8x. Every pixel the
// number fully covers (its glyphs' core, over a part of the battery that is one colour there) is measured against what is behind it: the WCAG
// contrast ratio must be >= 3, and the pixel must be in the ink that reads on its side of the fill's edge (black or white, whichever reads better
// on the colour measured there). Stand-ins: DMLog (kept), DMBattNow (the level the test sets), DMBattItemViews (the bar's batteries), and the
// power state's notification (its handler kept, to be called as iPadOS would). The Charge Limit's hold of the battery glyph (bi-hold.inc: the real
// DMBattHoldOne, DMBattHoldBar, DMBattHoldEveryBar, DMBattHoldWatch, with common/BatteryMenu.h's plug place, bi-plug.inc) on stand-ins of the
// job (installed, its state word, its notification kept to be called as the job posts it).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include "BatteryInside.h"

static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static NSHashTable *gCopies, *gAllBarCopies;
#include "bi-types.inc"
#include "bi-info.inc"
static DMBattInfo gFake;
static DMBattInfo DMBattNow(void) { return gFake; }
static const void *kTestBatteries = &kTestBatteries;
static NSArray<UIView *> *DMBattItemViews(UIView *fg) { return objc_getAssociatedObject(fg, kTestBatteries) ?: @[]; }
// (one switch, 1.8.7.4 round 2: what the block's leave-out of iPadOS's own number needs; its bars here are never ours, and there is no battery
//  item to add the method to -- tools/test-battinsideone.sh tests that part)
static const void *kLogoKey __attribute__((unused)) = &kLogoKey, *kHoldKey __attribute__((unused)) = &kHoldKey;
static const void *kNoClockLayoutKey __attribute__((unused)) = &kNoClockLayoutKey;
static id DMCall(id obj, NSString *name) __attribute__((unused));
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return obj && [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
static void DMStockVPNRecheck(UIView *fg) __attribute__((unused));
static void DMStockVPNRecheck(UIView *fg) {}
#define DMTestFlag(path) 0
static Class DMBattItemClass(void) __attribute__((unused));
static Class DMBattItemClass(void) { return Nil; }
static notify_handler_t gPowerSources, gChargeState;
#define MSBD_CHARGE_STATE "com.besiktasliseba.chargelimit.state"   // (common/ChargeLimit.h)
static uint32_t BIRegister(const char *name, int *token, dispatch_queue_t q, notify_handler_t h) {
    if (name && !strcmp(name, "com.apple.system.powersources") && !gPowerSources) gPowerSources = h;   // (the number's: registered first)
    if (name && !strcmp(name, MSBD_CHARGE_STATE)) gChargeState = h;
    if (token) *token = 1;
    return 0;
}
#define notify_register_dispatch BIRegister
#include "bi-block.inc"
// (the Charge Limit's hold of the glyph, BatteryMenu.h 1.8.6: the job installed, its word on hold or not, the crash guard's skip list empty)
static BOOL gJob = YES; static uint64_t gWord;
static BOOL DMBattChargeJob(void) { return gJob; }
static uint64_t DMBattChargeWord(void) { return gWord; }
static int MSBDBattHoldPlug(uint64_t word) { return word != 0; }   // (common/BatteryMenu.h: on the adapter, held at the limit)
#define MSBD_BATT_HOLD_PIECE "batteryHoldPlug"
static int MSBDCrashSkipped(const char *piece) { return 0; }
#include "bi-plug.inc"
#include "bi-hold.inc"
static void DMBattHoldHookInit(void) {}   // (StatusBar.x: iOS's own later -setChargingState: calls kept at 0 -- none come here)
#undef notify_register_dispatch

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the battery in a bar --------------------------------------------------------------------------------------------------------------------
static const double kScale = 8, kMargin = 2;
static UIColor *BarColour(BOOL dark) { return dark ? [UIColor colorWithWhite:0.12 alpha:1] : [UIColor colorWithWhite:0.94 alpha:1]; }
typedef struct { const char *cls; BOOL dark; int percent; long long charging; BOOL saver; BOOL rtl; } Spec;
static void SetLevel(UIView *v, int percent) { ((void (*)(id, SEL, double))objc_msgSend)(v, sel_registerName("setChargePercent:"), percent / 100.0); }
static void SetSaver(UIView *v, BOOL on) { ((void (*)(id, SEL, BOOL))objc_msgSend)(v, sel_registerName("setSaverModeActive:"), on); }
// This Mac is x86_64, where BOOL is 'c'; on the iPad (arm64) it is 'B', the types the code reads the charging bolt's switch with. A battery that
// charges is made of a subclass with that switch's two methods in the iPad's types (UIKit's own code), so the code sees what it sees there.
static Class BIiPadBools(Class c) {
    SEL set = sel_registerName("setShowsInlineChargingIndicator:"), get = sel_registerName("showsInlineChargingIndicator");
    const char *t = method_getTypeEncoding(class_getInstanceMethod(c, set));
    if (!t || strcmp(t, "v20@0:8c16")) return c;
    char name[128]; snprintf(name, sizeof name, "%s_iPadBOOL", class_getName(c));
    Class sub = objc_getClass(name);
    if (sub) return sub;
    sub = objc_allocateClassPair(c, name, 0);
    class_addMethod(sub, set, method_getImplementation(class_getInstanceMethod(c, set)), "v20@0:8B16");
    class_addMethod(sub, get, method_getImplementation(class_getInstanceMethod(c, get)), "B16@0:8");
    objc_registerClassPair(sub);
    return sub;
}
static UIView *MakeBar(Spec s, UIView **battery) {
    Class c = NSClassFromString(@(s.cls));
    UIView *v = [[(s.charging ? BIiPadBools(c) : c) alloc] initWithFrame:CGRectZero];
    if (s.rtl) v.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    ((void (*)(id, SEL, double))objc_msgSend)(v, sel_registerName("setLowBatteryChargePercentThreshold:"), 0.2);   // (the iPad's: red at 20 % and below)
    ((void (*)(id, SEL, id))objc_msgSend)(v, sel_registerName("setFillColor:"), s.dark ? UIColor.whiteColor : UIColor.blackColor);
    SetLevel(v, s.percent);
    ((void (*)(id, SEL, long long))objc_msgSend)(v, sel_registerName("setChargingState:"), s.charging);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(v, sel_registerName("setShowsInlineChargingIndicator:"), s.charging != 0);   // (as the bar sets it)
    SetSaver(v, s.saver);
    CGSize size = v.intrinsicContentSize;
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size.width + 2 * kMargin, size.height + 2 * kMargin)];
    bar.backgroundColor = BarColour(s.dark);
    v.frame = CGRectMake(kMargin, kMargin, size.width, size.height);
    [bar addSubview:v];
    if (s.rtl) ((void (*)(id, SEL))objc_msgSend)(v, sel_registerName("_updateTransform"));   // (as UIKit does when the direction is set: the body drawn mirrored)
    [bar layoutIfNeeded];
    objc_setAssociatedObject(bar, kTestBatteries, @[v], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (battery) *battery = v;
    return bar;
}
static void Pass(UIView *bar, int percent, BOOL charging) {   // (the bar's layout: DMBattInsideBar, the level read anew)
    gFake = (DMBattInfo){ percent, charging, charging, YES };
    gBattInsideReadAt = -100;
    DMBattInsideBar(bar);
    [bar layoutIfNeeded];
}
static NSArray<UILabel *> *Numbers(UIView *v) {
    NSMutableArray *a = [NSMutableArray array];
    for (UIView *s in v.subviews) if ([s isKindOfClass:[UILabel class]] && !s.hidden) [a addObject:s];
    return a;
}
static void Sharp(UIView *v) {   // (the labels drawn at the pictures' scale, as a window on a screen has them drawn at the screen's: not out of window here)
    for (UIView *s in v.subviews) if ([s isKindOfClass:[UILabel class]] && s.layer.contentsScale != kScale) { s.layer.contentsScale = kScale; [s.layer setNeedsDisplay]; [s.layer displayIfNeeded]; }
}

// ---- pictures and pixels ---------------------------------------------------------------------------------------------------------------------
typedef struct { uint8_t *px; int w, h; } Img;
static Img Render(UIView *bar, void (^draw)(CGContextRef ctx)) {
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = kScale; f.opaque = NO;
    f.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:bar.bounds.size format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) { draw(c.CGContext); }];
    Img o = { NULL, (int)CGImageGetWidth(img.CGImage), (int)CGImageGetHeight(img.CGImage) };
    o.px = calloc((size_t)o.w * o.h, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(o.px, o.w, o.h, 8, o.w * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, o.w, o.h), img.CGImage);
    CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return o;
}
static Img RenderAll(UIView *bar) { return Render(bar, ^(CGContextRef ctx) { [bar.layer renderInContext:ctx]; }); }
static Img RenderBehind(UIView *bar, UIView *v) {   // (the battery as it is under the number: our labels hidden)
    NSArray *n = Numbers(v);
    for (UILabel *l in n) l.hidden = YES;
    Img o = RenderAll(bar);
    for (UILabel *l in n) l.hidden = NO;
    return o;
}
static Img RenderNumber(UIView *bar, UIView *v) {   // (the number alone, on nothing, where it is drawn: its alpha is how much of each pixel it covers)
    NSMutableArray<CALayer *> *own = [NSMutableArray array], *ours = [NSMutableArray array];
    for (UILabel *l in Numbers(v)) [ours addObject:l.layer];
    for (CALayer *l in v.layer.sublayers) if (![ours containsObject:l] && !l.hidden) { [own addObject:l]; l.hidden = YES; }
    UIColor *bg = bar.backgroundColor; bar.backgroundColor = UIColor.clearColor;
    Img o = RenderAll(bar);
    bar.backgroundColor = bg;
    for (CALayer *l in own) l.hidden = NO;
    return o;
}
static double Lin(double c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static double LumAt(Img m, int x, int y) { uint8_t *p = m.px + ((size_t)y * m.w + x) * 4; return 0.2126 * Lin(p[0] / 255.0) + 0.7152 * Lin(p[1] / 255.0) + 0.0722 * Lin(p[2] / 255.0); }
static double Ratio(double a, double b) { return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05); }
static int BlackReads(double l) { return Ratio(l, 0) >= Ratio(l, 1); }
static CGRect FillRect(UIView *bar, UIView *v) {   // (UIKit's own fill, in the bar)
    CALayer *f = ((CALayer *(*)(id, SEL))objc_msgSend)(v, sel_registerName("fillLayer"));
    return f && !f.hidden && f.bounds.size.width > 0 ? [bar.layer convertRect:f.bounds fromLayer:f] : CGRectNull;
}

typedef struct { int core, low, wrong, skipped; double worst; double split; } Measure;
// Every pixel the number covers by 85 % or more, over a part of the battery of one colour (its 5 x 5 pixels: luminance within 0.02; the edges
// of the battery's own outline, fill and corners are blends whatever is on them) and not on the fill's edge itself (one pixel each side).
static Measure Measured(UIView *bar, UIView *v) {
    Measure m = { 0, 0, 0, 0, 99, -1 };
    Sharp(v);
    Img all = RenderAll(bar), behind = RenderBehind(bar, v), number = RenderNumber(bar, v);
    CGRect fill = FillRect(bar, v);
    BOOL rtl = v.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft;
    if (!CGRectIsNull(fill)) m.split = rtl ? CGRectGetMinX(fill) - kMargin : CGRectGetMaxX(fill) - kMargin;
    // the inks that read on each side, as measured: the fill's colour at its middle, the empty part's (the bar) between the fill and the body's end
    int fillBlack = -1, restBlack = BlackReads(LumAt(behind, (int)(kMargin * kScale / 2), (int)(behind.h / 2)));
    if (!CGRectIsNull(fill)) fillBlack = BlackReads(LumAt(behind, (int)(CGRectGetMidX(fill) * kScale), (int)(CGRectGetMidY(fill) * kScale)));
    for (int y = 2; y < all.h - 2; y++) for (int x = 2; x < all.w - 2; x++) {
        if (number.px[((size_t)y * number.w + x) * 4 + 3] < 217) continue;
        m.core++;
        double lo = 9, hi = -9;
        for (int dy = -2; dy <= 2; dy++) for (int dx = -2; dx <= 2; dx++) { double l = LumAt(behind, x + dx, y + dy); lo = MIN(lo, l); hi = MAX(hi, l); }
        double px = (x + 0.5) / kScale, py = (y + 0.5) / kScale;
        BOOL onEdge = !CGRectIsNull(fill) && (fabs(px - CGRectGetMaxX(fill)) < 1.0 / kScale || fabs(px - CGRectGetMinX(fill)) < 1.0 / kScale);
        if (hi - lo > 0.02 || onEdge) { m.skipped++; continue; }
        double lt = LumAt(all, x, y), r = Ratio(lt, LumAt(behind, x, y));
        if (r < m.worst) m.worst = r;
        if (r < 3) m.low++;
        BOOL inFill = !CGRectIsNull(fill) && CGRectContainsPoint(fill, CGPointMake(px, py));
        int black = inFill ? fillBlack : restBlack;
        if (black ? lt > 0.2 : lt < 0.45) m.wrong++;   // (85 % of the ink at least: black's luminance under 0.2, white's over 0.45)
    }
    free(all.px); free(behind.px); free(number.px);
    return m;
}
static NSString *Describe(Spec s) {
    return [NSString stringWithFormat:@"%s, %@ bar, %d %%%@%@%@", s.cls, s.dark ? @"dark" : @"light", s.percent, s.charging ? @", charging (green)" : @"",
            s.saver ? @", Low Power (yellow)" : @"", s.rtl ? @", right to left" : @""];
}
static BOOL Reads(Measure m) { return m.core >= 40 && m.low == 0 && m.wrong == 0; }
static void CheckReads(Spec s, Measure m, NSString *extra) {
    Check(Reads(m), [NSString stringWithFormat:@"%@%@: %d glyph pixels measured (%d on edges), worst ratio %.2f, %d below 3, %d not in their side's ink%@",
                     Describe(s), extra ?: @"", m.core - m.skipped, m.skipped, m.worst, m.low, m.wrong, m.split >= 0 ? [NSString stringWithFormat:@" (the fill's edge at %.2f pt)", m.split] : @""]);
}
static const int kLevels[] = { 5, 20, 35, 50, 55, 65, 75, 90, 100 };

// ---- scenarios -------------------------------------------------------------------------------------------------------------------------------
static void Levels(const char *cls) {   // KT's levels, a light and a dark bar
    DMBattInsideApplyPref(YES);
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 9; i++) {
        Spec s = { cls, dark, kLevels[i], 0, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        Pass(bar, s.percent, NO);
        CheckReads(s, Measured(bar, v), nil);
    }
}
static void States(const char *cls) {   // the fill's other colours: green while charging (the bolt off while the number shows), yellow in Low Power Mode
    DMBattInsideApplyPref(YES);
    const int levels[] = { 35, 55, 65, 90 };
    for (int dark = 0; dark < 2; dark++) for (int st = 0; st < 2; st++) for (int i = 0; i < 4; i++) {
        Spec s = { cls, dark, levels[i], st == 0 ? 1 : 0, st == 1, NO };
        UIView *v, *bar = MakeBar(s, &v);
        Pass(bar, s.percent, st == 0);
        Measure m = Measured(bar, v);
        if (st == 0) {
            BOOL bolt = ((BOOL (*)(id, SEL))objc_msgSend)(v, sel_registerName("showsInlineChargingIndicator"));
            CheckReads(s, m, bolt ? @" [the bolt still on]" : nil);
            if (bolt) Check(NO, @"  the bolt gives way to the number");
        } else CheckReads(s, m, nil);
    }
}
// Right to left the battery draws its fill from the right, all of its layers mirrored by its own sublayer transform (our two copies of the
// number with them: their glyphs mirrored, as before this change, a matter of its own): the split follows the fill there.
static void RightToLeft(void) {
    DMBattInsideApplyPref(YES);
    const int levels[] = { 35, 55, 65, 90 };
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 4; i++) {
        Spec s = { "_UIStaticBatteryView", dark, levels[i], 0, NO, YES };
        UIView *v, *bar = MakeBar(s, &v);
        Pass(bar, s.percent, NO);
        CheckReads(s, Measured(bar, v), nil);
    }
}
static void RunFor(double seconds) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
// After a power state change iPadOS's bar redraws its battery on its own, with no layout of the bar, and that can come after our pass: the
// number's split and colours must follow it. Two bars (the main screen's and the TV's, one list each), one of each appearance.
static void Follow(void) {
    gCopies = [NSHashTable weakObjectsHashTable]; gAllBarCopies = [NSHashTable weakObjectsHashTable];
    Spec sa = { "_UIStaticBatteryView", YES, 55, 0, NO, NO }, sb = { "_UIBatteryView", NO, 55, 0, NO, NO };
    UIView *va, *vb, *a = MakeBar(sa, &va), *b = MakeBar(sb, &vb);
    [gCopies addObject:a]; [gAllBarCopies addObject:b];
    gFake = (DMBattInfo){ 55, NO, NO, YES };
    DMBattInsideApplyPref(YES);
    RunFor(0.1);
    CheckReads(sa, Measured(a, va), @" (switched on)"); CheckReads(sb, Measured(b, vb), @" (switched on)");
    // the level: SpringBoard has 65 % when the notification comes; the bars' batteries take it after our pass
    gFake = (DMBattInfo){ 65, NO, NO, YES };
    if (gPowerSources) gPowerSources(1); else Check(NO, @"the power sources' notification is listened to");
    SetLevel(va, 65); SetLevel(vb, 65);
    RunFor(1.4);
    sa.percent = sb.percent = 65;
    CheckReads(sa, Measured(a, va), @" (55 -> 65 %, the battery redrawn after our pass)"); CheckReads(sb, Measured(b, vb), @" (55 -> 65 %, the battery redrawn after our pass)");
    // Low Power Mode on (ProcessInfo's notification), then off: the fill turns yellow and back after our pass
    for (int on = 1; on >= 0; on--) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NSProcessInfoPowerStateDidChangeNotification object:nil];
        RunFor(0.05);
        SetSaver(va, on); SetSaver(vb, on);
        RunFor(1.4);
        sa.saver = sb.saver = on;
        NSString *t = on ? @" (Low Power Mode on, the battery redrawn after our pass)" : @" (Low Power Mode off, the battery redrawn after our pass)";
        CheckReads(sa, Measured(a, va), t); CheckReads(sb, Measured(b, vb), t);
    }
}
// Switched off: the battery exactly as iPadOS draws it (both copies of the number gone, the bolt back while charging).
static void Off(void) {
    for (int charging = 0; charging < 2; charging++) {
        Spec s = { "_UIStaticBatteryView", YES, 65, charging, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        Img before = RenderAll(bar);
        DMBattInsideApplyPref(YES); Pass(bar, 65, charging);
        BOOL shown = Numbers(v).count > 0;
        DMBattInsideApplyPref(NO); Pass(bar, 65, charging);
        Img after = RenderAll(bar);
        BOOL same = before.w == after.w && before.h == after.h && !memcmp(before.px, after.px, (size_t)before.w * before.h * 4);
        Check(shown && same && Numbers(v).count == 0, [NSString stringWithFormat:@"%@: on, then off: the battery as iPadOS draws it, pixel for pixel%@", Describe(s), shown ? @"" : @" [the number never showed]"]);
        free(before.px); free(after.px);
    }
}
// A battery whose fill can't be read (-fillLayer not of the types read): the number in one colour by the level, said once in the log.
static id BINoFill(id self, SEL _cmd) { return nil; }
// A battery whose fill layer is hidden (it draws no fill: the body empty): no copy over a fill, the whole number in the empty part's ink.
static void BIHideFill(UIView *v) { ((CALayer *(*)(id, SEL))objc_msgSend)(v, sel_registerName("fillLayer")).hidden = YES; }
static void BIHiddenFillLayout(id self, SEL _cmd) {
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    BIHideFill(self);
}
static void HiddenFill(void) {
    Class c = objc_allocateClassPair(NSClassFromString(@"_UIBatteryView"), "BIHiddenFillBatteryView", 0);
    class_addMethod(c, sel_registerName("layoutSubviews"), (IMP)BIHiddenFillLayout, "v16@0:8");
    objc_registerClassPair(c);
    DMBattInsideApplyPref(YES);
    const int levels[] = { 35, 65, 90 };
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 3; i++) {
        Spec s = { "BIHiddenFillBatteryView", dark, levels[i], 0, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        BIHideFill(v);
        Pass(bar, s.percent, NO);
        BOOL hidden = ((CALayer *(*)(id, SEL))objc_msgSend)(v, sel_registerName("fillLayer")).hidden;
        unsigned long n = (unsigned long)Numbers(v).count;
        CheckReads(s, Measured(bar, v), [NSString stringWithFormat:@" (its fill layer hidden%@: one copy, the empty part's ink -- %lu shown)", hidden ? @"" : @" [not hidden]", n]);
        if (n != 1 || !hidden) Check(NO, @"  one copy of the number over a battery whose fill is hidden");
    }
}
// A battery whose -fillLayer is not one of its own layers (types as read, but a layer elsewhere): not taken as its fill -- one colour by the
// level, said once in the log -- as a fill that can't be read.
static CALayer *gForeignFill;
static id BIForeignFill(id self, SEL _cmd) { return gForeignFill; }
static void ForeignFill(void) {
    CALayer *root = [CALayer layer]; root.frame = CGRectMake(0, 0, 40, 20);
    gForeignFill = [CALayer layer]; gForeignFill.frame = CGRectMake(2, 2, 19.5 * 0.65, 7.5); [root addSublayer:gForeignFill];
    Class odd = objc_allocateClassPair(NSClassFromString(@"_UIStaticBatteryView"), "BIForeignFillBatteryView", 0);
    class_addMethod(odd, sel_registerName("fillLayer"), (IMP)BIForeignFill, "@16@0:8");
    objc_registerClassPair(odd);
    DMBattInsideApplyPref(YES);
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 2; i++) {
        Spec s = { "BIForeignFillBatteryView", dark, i ? 90 : 20, 0, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        [gLog removeAllObjects];
        Pass(bar, s.percent, NO); Pass(bar, s.percent, NO);
        NSArray<UILabel *> *n = Numbers(v);
        CGFloat w = -1, a = 0; [n.firstObject.textColor getWhite:&w alpha:&a];
        BOOL want = i ? dark : !dark;   // (90 %: the fill's ink, the opposite of the icon; 20 %: the icon's shade)
        NSUInteger said = [gLog indexesOfObjectsPassingTest:^BOOL(NSString *l, NSUInteger k, BOOL *stop) { return [l containsString:@"no fill layer as read (-fillLayer @16@0:8): the number in one colour"]; }].count;
        Check(n.count == 1 && (w < 0.5) == want && said == 1, [NSString stringWithFormat:@"%@, its -fillLayer a layer outside the battery: not taken as its fill -- one copy, %@, said once in the log (%lu copies, white %.0f, %lu lines)",
                                                               Describe(s), want ? @"black" : @"white", (unsigned long)n.count, w, (unsigned long)said]);
    }
}
static void NoFill(void) {
    Class odd = objc_allocateClassPair(NSClassFromString(@"_UIStaticBatteryView"), "BIOddBatteryView", 0);
    class_addMethod(odd, sel_registerName("fillLayer"), (IMP)BINoFill, "v16@0:8");
    objc_registerClassPair(odd);
    DMBattInsideApplyPref(YES);
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 2; i++) {
        Spec s = { "BIOddBatteryView", dark, i ? 90 : 20, 0, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        [gLog removeAllObjects];
        Pass(bar, s.percent, NO); Pass(bar, s.percent, NO);
        NSArray<UILabel *> *n = Numbers(v);
        CGFloat w = -1, a = 0; [n.firstObject.textColor getWhite:&w alpha:&a];
        BOOL want = i ? dark : !dark;   // (90 %: the fill's ink, the opposite of the icon; 20 %: the icon's shade)
        NSUInteger said = [gLog indexesOfObjectsPassingTest:^BOOL(NSString *l, NSUInteger k, BOOL *stop) { return [l containsString:@"no fill layer as read (-fillLayer v16@0:8): the number in one colour"]; }].count;
        Check(n.count == 1 && (w < 0.5) == want && said == 1, [NSString stringWithFormat:@"%@, its fill not readable: one copy, %@, said once in the log (%lu copies, white %.0f, %lu lines)",
                                                               Describe(s), want ? @"black" : @"white", (unsigned long)n.count, w, (unsigned long)said]);
    }
}
// The two copies' masks: the copy over the fill takes exactly the fill's shape as UIKit draws it, its rounded corners too (a point in the
// fill's corner outside its rounding is the rest's), the other copy everything else; one copy for each point.
static void Masks(void) {
    DMBattInsideApplyPref(YES);
    for (int k = 0; k < 2; k++) for (int i = 0; i < 3; i++) {
        const int levels[] = { 35, 65, 90 };
        Spec s = { k ? "_UIStaticBatteryView" : "_UIBatteryView", YES, levels[i], 0, NO, NO };
        UIView *v, *bar = MakeBar(s, &v);
        Pass(bar, s.percent, NO);
        CALayer *f = ((CALayer *(*)(id, SEL))objc_msgSend)(v, sel_registerName("fillLayer"));
        CGRect own; double r = 0; ((void (*)(id, SEL, CGRect *, double *))objc_msgSend)(v, sel_registerName("_fillLayerFrame:cornerRadius:"), &own, &r);
        NSArray<UILabel *> *n = Numbers(v);
        int bad = n.count == 2 ? 0 : 100;
        NSString *where = @"";
        if (!bad) {
            CGRect fr = [n[0].layer convertRect:f.bounds fromLayer:f];
            CGPoint pts[] = { CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr)), CGPointMake(CGRectGetMaxX(fr) - 0.15 * r, CGRectGetMinY(fr) + 0.15 * r),
                              CGPointMake(CGRectGetMaxX(fr) - 0.15 * r, CGRectGetMaxY(fr) - 0.15 * r), CGPointMake(CGRectGetMaxX(fr) + 0.3, CGRectGetMidY(fr)),
                              CGPointMake(CGRectGetMaxX(fr) - 0.3, CGRectGetMidY(fr)) };
            BOOL overFill[] = { YES, NO, NO, NO, YES };
            for (int p = 0; p < 5; p++) {
                int in[2];
                for (int j = 0; j < 2; j++) { CAShapeLayer *m = (CAShapeLayer *)n[j].layer.mask; in[j] = [m isKindOfClass:[CAShapeLayer class]] && m.path && CGPathContainsPoint(m.path, NULL, pts[p], [m.fillRule isEqual:kCAFillRuleEvenOdd]); }
                // n[0]: the copy made first (the rest), n[1]: the one on top (over the fill)
                if (in[0] + in[1] != 1 || in[1] != overFill[p]) { bad++; where = [where stringByAppendingFormat:@" point %d (%.2f, %.2f): rest %d, fill %d;", p, pts[p].x, pts[p].y, in[0], in[1]]; }
            }
        }
        Check(!bad, [NSString stringWithFormat:@"%@: the copy over the fill masked to the fill's shape (corners rounded %.2f pt as UIKit's), the other to the rest, each point once (%lu copies)%@",
                     Describe(s), r, (unsigned long)n.count, where]);
    }
}
// The Charge Limit's hold (the -reg build's job): the battery kept at state 0 while the job holds it at the limit, given iOS's state back at the
// hold's end. The fill's colour goes with the state (green while charging, the icon's at 0), so the number's inks must follow -- whether the
// hold starts from the job's notification or at the bar's layout (StatusBar.x: the number's pass first, then the hold's). A light bar (black
// icon), as charging at 79 % with the limit at 80: black over the green fill; on hold: white over the black fill; the hold over: black again.
static long long State(UIView *v) { return ((long long (*)(id, SEL))objc_msgSend)(v, sel_registerName("chargingState")); }
static void LayoutPass(UIView *bar, int percent, BOOL charging) { Pass(bar, percent, charging); DMBattHoldBar(bar); [bar layoutIfNeeded]; }   // (StatusBar.x's order)
static void Hold(const char *cls) {
    gCopies = [NSHashTable weakObjectsHashTable]; gAllBarCopies = [NSHashTable weakObjectsHashTable];
    DMBattInsideApplyPref(YES);
    Spec s = { cls, NO, 79, 1, NO, NO };
    UIView *v, *bar = MakeBar(s, &v);
    [gCopies addObject:bar];
    gWord = 0; LayoutPass(bar, 79, YES);
    CheckReads(s, Measured(bar, v), @" (charging, no hold yet)");
    gWord = 1;   // (the job reaches the limit and holds: its notification, no layout of the bar)
    if (gChargeState) gChargeState(1); else Check(NO, @"the job's notification is listened to");
    [bar layoutIfNeeded];
    s.charging = 0;
    CheckReads(s, Measured(bar, v), [NSString stringWithFormat:@" (the hold from the job's notification: state %lld, the fill the icon's black)", State(v)]);
    gWord = 0;   // (the hold ends: iOS's state back)
    if (gChargeState) gChargeState(1);
    [bar layoutIfNeeded];
    s.charging = 1;
    CheckReads(s, Measured(bar, v), [NSString stringWithFormat:@" (the hold's end from the job's notification: state %lld, the fill green again)", State(v)]);
    Spec t = { cls, NO, 79, 1, NO, NO };
    UIView *w, *other = MakeBar(t, &w);
    [gCopies addObject:other];
    gWord = 1; LayoutPass(other, 79, YES);   // (a bar laid out while the job holds: the number's pass sees the green fill, the hold's comes after)
    t.charging = 0;
    CheckReads(t, Measured(other, w), [NSString stringWithFormat:@" (held from the bar's own layout: state %lld)", State(w)]);
    gWord = 0; LayoutPass(other, 79, YES);
    t.charging = 1;
    CheckReads(t, Measured(other, w), [NSString stringWithFormat:@" (the hold's end at the bar's layout: state %lld)", State(w)]);
}
static void Logged(void) {   // the debug log: how it is drawn, once per change
    DMBattInsideApplyPref(YES);
    Spec s = { "_UIStaticBatteryView", YES, 65, 0, NO, NO };
    UIView *v, *bar = MakeBar(s, &v);
    [gLog removeAllObjects];
    for (int i = 0; i < 5; i++) Pass(bar, 65, NO);
    NSArray *lines = [gLog filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS 'over the fill'"]];
    BOOL ok = lines.count == 1 && [lines[0] hasPrefix:@"[battinside] _UIStaticBatteryView at 65 %: black over the fill (1.00 1.00 1.00), white over the rest, split at 14.5 of 23.1 pt"];
    SetSaver(v, YES); Pass(bar, 65, NO); Pass(bar, 65, NO);
    lines = [gLog filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS 'over the fill'"]];
    Check(ok && lines.count == 1, [NSString stringWithFormat:@"the log: one line for 5 layouts (\"%@\"); Low Power Mode on a dark bar keeps black over the fill: no new line", lines.firstObject ?: @"none"]);
    s.dark = NO; bar = MakeBar(s, &v);
    [gLog removeAllObjects];
    Pass(bar, 65, NO); SetSaver(v, YES); Pass(bar, 65, NO); Pass(bar, 65, NO);
    lines = [gLog filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS 'over the fill'"]];
    Check(lines.count == 2 && [lines[0] containsString:@": white over the fill (0.00 0.00 0.00), black over the rest"] && [lines[1] containsString:@": black over the fill (1.00 0.80 0.00), black over the rest"],
          [NSString stringWithFormat:@"the log: a light bar, Low Power Mode on: a second line, black over the yellow fill (%@)", [lines componentsJoinedByString:@" | "]]);
}

// ---- pictures (BI_PICTURES): the bar with the battery at 8x (UIKit's shape-layer battery: drawn sharp at any scale), and a sheet of them ---------------------------------------------------------------
static UIImage *Picture(Spec s) {
    UIView *v, *bar = MakeBar(s, &v);
    Pass(bar, s.percent, s.charging != 0);
    Sharp(v);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = kScale; f.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:bar.bounds.size format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) { [bar.layer renderInContext:c.CGContext]; }];
}
static void Pictures(const char *dir, const char *tag) {
    DMBattInsideApplyPref(YES);
    for (int dark = 0; dark < 2; dark++) for (int i = 0; i < 9; i++) {
        UIImage *img = Picture((Spec){ "_UIBatteryView", dark, kLevels[i], 0, NO, NO });
        [UIImagePNGRepresentation(img) writeToFile:[NSString stringWithFormat:@"%s/%s-%s-%03d.png", dir, tag, dark ? "dark" : "light", kLevels[i]] atomically:YES];
    }
    const int lv[] = { 35, 65, 90 };
    for (int dark = 0; dark < 2; dark++) for (int st = 0; st < 2; st++) for (int i = 0; i < 3; i++) {
        UIImage *img = Picture((Spec){ "_UIBatteryView", dark, lv[i], st == 0, st == 1, NO });
        [UIImagePNGRepresentation(img) writeToFile:[NSString stringWithFormat:@"%s/%s-%s-%s-%03d.png", dir, tag, dark ? "dark" : "light", st ? "lowpower" : "charging", lv[i]] atomically:YES];
    }
}
// compose <out.png> <title> <columns> <file|label:text>...: a sheet, the pictures in a grid with their labels above each column's
static void Compose(int argc, char **argv) {
    NSString *out = @(argv[2]), *title = @(argv[3]); int cols = atoi(argv[4]);
    NSMutableArray *cells = [NSMutableArray array];
    for (int i = 5; i < argc; i++) [cells addObject:@(argv[i])];
    CGFloat cw = 0, ch = 0;
    for (NSString *c in cells) { if ([c hasPrefix:@"label:"]) continue; UIImage *im = [UIImage imageWithContentsOfFile:c]; cw = MAX(cw, im.size.width); ch = MAX(ch, im.size.height); }
    CGFloat pad = 14, head = 26, lab = 18;
    NSInteger rows = (cells.count + cols - 1) / cols;
    CGSize size = CGSizeMake(pad + cols * (cw + pad), head + rows * (ch + lab + pad) + pad);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 1; f.opaque = YES;
    UIImage *sheet = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[UIColor colorWithWhite:0.5 alpha:1] setFill]; UIRectFill(CGRectMake(0, 0, size.width, size.height));
        NSDictionary *big = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:15], NSForegroundColorAttributeName: UIColor.whiteColor };
        NSDictionary *small = @{ NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: UIColor.whiteColor };
        [title drawAtPoint:CGPointMake(pad, 5) withAttributes:big];
        for (NSUInteger i = 0; i < cells.count; i++) {
            CGFloat x = pad + (i % cols) * (cw + pad), y = head + (i / cols) * (ch + lab + pad);
            NSString *cell = cells[i];
            if ([cell hasPrefix:@"label:"]) { [[cell substringFromIndex:6] drawAtPoint:CGPointMake(x, y + ch / 2) withAttributes:big]; continue; }
            [[[cell lastPathComponent] stringByDeletingPathExtension] drawAtPoint:CGPointMake(x, y) withAttributes:small];
            [[UIImage imageWithContentsOfFile:cell] drawInRect:CGRectMake(x, y + lab, cw, ch)];
        }
    }];
    [UIImagePNGRepresentation(sheet) writeToFile:out atomically:YES];
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        NSString *s = argc > 1 ? @(argv[1]) : @"list";
        if ([s isEqual:@"list"]) { printf("levels-shape levels-static states-shape states-static rtl follow masks off nofill hiddenfill foreignfill hold-shape hold-static log\n"); return 0; }
        if ([s isEqual:@"png"] && argc > 3) { Pictures(argv[2], argv[3]); return 0; }
        if ([s isEqual:@"compose"] && argc > 5) { Compose(argc, argv); return 0; }
        if ([s isEqual:@"levels-shape"]) Levels("_UIBatteryView");
        else if ([s isEqual:@"levels-static"]) Levels("_UIStaticBatteryView");
        else if ([s isEqual:@"states-shape"]) States("_UIBatteryView");
        else if ([s isEqual:@"states-static"]) States("_UIStaticBatteryView");
        else if ([s isEqual:@"rtl"]) RightToLeft();
        else if ([s isEqual:@"follow"]) Follow();
        else if ([s isEqual:@"masks"]) Masks();
        else if ([s isEqual:@"off"]) Off();
        else if ([s isEqual:@"nofill"]) NoFill();
        else if ([s isEqual:@"hiddenfill"]) HiddenFill();
        else if ([s isEqual:@"foreignfill"]) ForeignFill();
        else if ([s isEqual:@"hold-shape"]) Hold("_UIBatteryView");
        else if ([s isEqual:@"hold-static"]) Hold("_UIStaticBatteryView");
        else if ([s isEqual:@"log"]) Logged();
        else { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
    }
    return gFails ? 1 : 0;
}
