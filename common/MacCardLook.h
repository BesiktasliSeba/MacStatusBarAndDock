// MacCardLook.h -- the Mac card look of a notification platter (iPadOS's PLPlatterView): a 14 pt continuous corner and a hairline edge, the
// material and the shadow staying iPadOS's. One function for our Mac-style banners (statusbar/StatusBar.x, MacBanners) and for Mac Lock Screen's
// Mac-Style Cards (macsettings/MacLockScreen.x, F49), so both show the same card. The Lock Screen's cards are cells iPadOS keeps and reuses (in
// Notification Center too), so there iPadOS's own values are recorded before the first change and given back when the look goes (switch-off, a
// stand-down, the cell leaving the Lock Screen's list): MSBDMacCardRecord / MSBDMacCardRestore. Banners are made and dropped by iPadOS for each
// notification and keep the 1.8.0 behaviour (no record).
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define MSBD_CARD_RADIUS 14.0
static inline CGFloat MSBDMacCardEdgeAlpha(BOOL dark, BOOL contrast) { return contrast ? (dark ? 0.30 : 0.70) : (dark ? 0.14 : 0.45); }
// The look itself (contrast: Increase Contrast's stronger edge; our banners pass NO, as in 1.8.0)
static inline void MSBDMacCardApply(UIView *platter, BOOL dark, BOOL contrast) {
    if (!platter) return;
    if ([platter respondsToSelector:@selector(setCornerRadius:)]) ((void (*)(id, SEL, CGFloat))objc_msgSend)(platter, @selector(setCornerRadius:), MSBD_CARD_RADIUS);
    platter.layer.borderWidth = 0.5;
    platter.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:MSBDMacCardEdgeAlpha(dark, contrast)].CGColor;
    platter.layer.cornerRadius = MSBD_CARD_RADIUS; platter.layer.cornerCurve = kCACornerCurveContinuous;
}

// The same look, set only where it differs: the Lock Screen applies it from the platter's own -layoutSubviews, so a setter that lays the
// platter out again is never called on every pass (review 1.8.9 F49, finding 5).
static inline void MSBDMacCardApplyIfNeeded(UIView *platter, BOOL dark, BOOL contrast) {
    if (!platter) return;
    SEL get = @selector(cornerRadius);
    Method m = [platter respondsToSelector:get] ? class_getInstanceMethod(object_getClass(platter), get) : NULL;
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    CGFloat r = e && e[0] == 'd' ? ((CGFloat (*)(id, SEL))objc_msgSend)(platter, get) : -1;
    if ([platter respondsToSelector:@selector(setCornerRadius:)] && fabs(r - MSBD_CARD_RADIUS) > 0.01) ((void (*)(id, SEL, CGFloat))objc_msgSend)(platter, @selector(setCornerRadius:), MSBD_CARD_RADIUS);
    CALayer *l = platter.layer;
    if (fabs(l.borderWidth - 0.5) > 0.001) l.borderWidth = 0.5;
    CGFloat want = MSBDMacCardEdgeAlpha(dark, contrast), white = -1, alpha = -1;
    if (l.borderColor) { UIColor *c = [UIColor colorWithCGColor:l.borderColor]; if (![c getWhite:&white alpha:&alpha]) white = -1; }
    if (fabs(white - 1.0) > 0.001 || fabs(alpha - want) > 0.001) l.borderColor = [UIColor colorWithWhite:1.0 alpha:want].CGColor;
    if (fabs(l.cornerRadius - MSBD_CARD_RADIUS) > 0.01) l.cornerRadius = MSBD_CARD_RADIUS;
    if (![l.cornerCurve isEqualToString:kCACornerCurveContinuous]) l.cornerCurve = kCACornerCurveContinuous;
}

// ---- record / restore (the Lock Screen's cells) ----
// (a dictionary, not a class of ours: this header is in two of our parts, and one class name in two images is a clash)
static const void *const kMSBDCardRecordKey = &kMSBDCardRecordKey;
static inline BOOL MSBDMacCardRecorded(UIView *platter) { return platter && objc_getAssociatedObject(platter, kMSBDCardRecordKey) != nil; }
// iPadOS's values, once (a second call keeps the first record: our own look is never recorded as iPadOS's)
static inline void MSBDMacCardRecord(UIView *platter) {
    if (!platter || MSBDMacCardRecorded(platter)) return;
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    SEL get = @selector(cornerRadius);
    if ([platter respondsToSelector:get] && [platter respondsToSelector:@selector(setCornerRadius:)]) {
        Method m = class_getInstanceMethod(object_getClass(platter), get);
        const char *e = m ? method_getTypeEncoding(m) : NULL;
        if (e && e[0] == 'd') r[@"platterRadius"] = @(((CGFloat (*)(id, SEL))objc_msgSend)(platter, get));
    }
    r[@"layerRadius"] = @(platter.layer.cornerRadius);
    if (platter.layer.cornerCurve) r[@"curve"] = platter.layer.cornerCurve;
    r[@"borderWidth"] = @(platter.layer.borderWidth);
    if (platter.layer.borderColor) r[@"borderColor"] = (__bridge id)platter.layer.borderColor;
    objc_setAssociatedObject(platter, kMSBDCardRecordKey, r, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// iPadOS's values back (nothing when none was recorded)
static inline BOOL MSBDMacCardRestore(UIView *platter) {
    NSDictionary *r = platter ? objc_getAssociatedObject(platter, kMSBDCardRecordKey) : nil;
    if (![r isKindOfClass:[NSDictionary class]]) return NO;
    if (r[@"platterRadius"]) ((void (*)(id, SEL, CGFloat))objc_msgSend)(platter, @selector(setCornerRadius:), [r[@"platterRadius"] doubleValue]);
    platter.layer.cornerRadius = [r[@"layerRadius"] doubleValue];
    if (r[@"curve"]) platter.layer.cornerCurve = r[@"curve"];
    platter.layer.borderWidth = [r[@"borderWidth"] doubleValue];
    platter.layer.borderColor = (__bridge CGColorRef)r[@"borderColor"];
    objc_setAssociatedObject(platter, kMSBDCardRecordKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
