// DockColor.m -- Settings > Dock > Dock Background (1.8.8.1 DOCKCOLOR, KT 15 Nov: "lets also add ability to color the dock"): the colour the
// user picks, at its opacity, on the Dock; the rule of which marks go on it is common/DockColor.h's (plain C, Mac-tested).
//  - Dock Style Default: one plain view of ours INSIDE Apple's material (the platter's -backgroundView, an MTMaterialView), filling it (critique
//    B1): it takes the material's frame, its resize animation, its fades, hidden state and transforms by itself, and Dock Style's empty mask
//    hides it together with the material. Apple's blur shows under a see-through colour; 100 % is solid (KT's decision 2). Only the corners are
//    copied onto it. Nothing of Apple's is masked, moved or restyled for the colour.
//  - Frosted: the same view takes the place of Frosted's tint, over its blur and under its border (DockStyle.m DMDockStyleFrostedColor, P5).
//  - Glass Shelf (and its side panel): nothing of ours; the shelf keeps its glass (KT's decision 1).
//  - Automatic, or the Dock part off: nothing; a platter that never had anything of ours is not read at all (P7).
// The marks (B2, P8): decided for what is drawn on that platter (our view on iPadOS's material, or on Frosted's blur, or nothing), in its own
// Light / Dark Mode. iPadOS's own answer leaves its marks untouched; a differing one puts ours on: the running dots black or white (DockStyle.m
// DMDockStyleDot asks DMDockColorDot), Apple's divider hidden by an empty mask of ours with a line of ours at its place, never restyled (B3), and
// our second divider in that line's colour. Back to iPadOS's answer, or Automatic: the mask goes (the one Apple's divider had is given back), our
// line goes, the second divider copies Apple's look again, the dots take labelColor again (only those we coloured): stock, with no call into
// Apple's styling.
// Live: the Dock page's list row posts prefsChanged (DMLoadPrefs reads the keys with the Dock part's switch, DMDockColorLoad; DMDockStyleRefreshAll
// applies every platter); the colour well and the opacity slider post the light note colorChanged, at most every 0.15 s (B4): the three keys only,
// the colour set on the platters ours is on, and only when the marks' answer changed, the dots and the dividers once. No DMLoadPrefs, no relayout.
// Every engine and iPadOS 15 to 18: one path, the platter, as Dock Style's; the TV's Dock is another platter and takes the iPad's colour (decision 4).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "DMLog.h"
#include "../common/DockColor.h"
#include "../common/DockStyle.h"
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

extern int DMDockStyleLookOn(UIView *platter);                          // (DockStyle.m: the look this platter shows now)
extern BOOL DMDockStyleFrostedColor(UIView *platter, UIView *colorView);   // (DockStyle.m: our view in place of Frosted's tint, or nil: the tint again)
extern void DMRunningIndicatorResyncAll(void);                          // (RunningIndicator.m: every app icon's dot placed and drawn again)
extern UIView *DMDockNativeDivider(UIView *dockView);                   // (Dock.x: the Dock's own divider, SBFloatingDockView's dividerView)
extern UIView *DMDockSecondDivider(UIView *dockView);                   // (Dock.x: ours, between the recents and Downloads / the Trash)
extern void DMDockSecondDividerLook(UIView *dockView);                  // (Dock.x: the second divider's one writer -- ours, or the Dock's own look copied)
@interface UIWindow (DMDockColorPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

#ifndef MSBD_DOCK_COLOR_DOMAIN   // (the Mac test, tools/test-dockcolor.sh, gives scratch domains of its own)
#define MSBD_DOCK_COLOR_DOMAIN "com.besiktasliseba.dockmagnification"
#define MSBD_DOCK_COLOR_BAR_DOMAIN kMSBDBarColorDomain
#endif
#define DC_DOMAIN CFSTR(MSBD_DOCK_COLOR_DOMAIN)
#define DC_BAR_DOMAIN CFSTR(MSBD_DOCK_COLOR_BAR_DOMAIN)
static BOOL gDCOn = NO;                 // Color, with the Dock part on (DMDockColorLoad, DMDockColorChanged)
static BOOL gDCTweakOn = YES;           // the Dock part's switch as DMLoadPrefs read it last (the light path keeps it)
static double gDCRGB[3] = { 0x24 / 255.0, 0x22 / 255.0, 0x25 / 255.0 }, gDCAlpha = MSBD_DOCK_COLOR_OPACITY;
static BOOL gDCEver = NO;               // our colour was drawn on a Dock since SpringBoard started: before that the dots' and dividers' calls read nothing
static NSHashTable<UIView *> *gDCSeen;  // the platters our colour is drawn on (the light path's list: no walk of the windows per change)
#if DEBUG
static BOOL gDCSibling = NO;            // debug "dockcolorsibling": the design's first way, a sibling above Apple's material copying its frame, corners,
                                        // alpha and hidden at each layout (the fallback if the first iPad shows B1's view under the blur or unclipped)
#endif
static const void *kDCStateKey = &kDCStateKey;       // (on a platter: what of ours is on it, DMDockColorState)
static const void *kDCDockMarksKey = &kDCDockMarksKey;   // (on a Dock view: the marks its dividers take, while they are not Apple's)
static const void *kDCDotKey = &kDCDotKey;           // (on a dot: the marks we coloured it for)
static const void *kDCMaskKey = &kDCMaskKey, *kDCWasKey = &kDCWasKey, *kDCLineKey = &kDCLineKey;   // (on Apple's divider: our empty mask, its own, our line)
static const void *kDCSecondKey = &kDCSecondKey;     // (on our second divider: the marks of ours on it)

// ---- the choice: the three keys (and Status Bar Background's colour while the Dock's was never stored) ----
static BOOL DCString(CFStringRef key, CFStringRef domain, char *buf, size_t n) {
    CFPropertyListRef v = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL ok = v && CFGetTypeID(v) == CFStringGetTypeID() && CFStringGetCString((CFStringRef)v, buf, (CFIndex)n, kCFStringEncodingUTF8);
    if (v) CFRelease(v);
    if (!ok) buf[0] = 0;
    return ok;
}
static BOOL DCRead(void) {   // YES: the choice changed
    char mode[16], hex[16], bar[16];
    DCString(CFSTR(kMSBDDockBackgroundKey), DC_DOMAIN, mode, sizeof mode);
    BOOL on = gDCTweakOn && MSBDDockBackgroundOn(mode);
    double rgb[3] = { gDCRGB[0], gDCRGB[1], gDCRGB[2] }, a = gDCAlpha;
    if (on) {
        BOOL own = DCString(CFSTR(kMSBDDockBackgroundColorKey), DC_DOMAIN, hex, sizeof hex);
        bar[0] = 0;
        if (!own || !MSBDDockColorParse(hex, rgb)) {   // (never stored: the menu bar's as stored now -- Settings stores it the first time Color is chosen)
            CFPreferencesAppSynchronize(DC_BAR_DOMAIN);
            DCString(CFSTR(kMSBDBarColorKey), DC_BAR_DOMAIN, bar, sizeof bar);
        }
        MSBDDockColorStart(own ? hex : NULL, bar, rgb);
        CFPropertyListRef o = CFPreferencesCopyValue(CFSTR(kMSBDDockBackgroundOpacityKey), DC_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        double stored = 0;
        BOOL has = o && CFGetTypeID(o) == CFNumberGetTypeID() && CFNumberGetValue((CFNumberRef)o, kCFNumberDoubleType, &stored);
        if (o) CFRelease(o);
        a = MSBDDockColorOpacity(has, stored);
    }
    BOOL changed = on != gDCOn || rgb[0] != gDCRGB[0] || rgb[1] != gDCRGB[1] || rgb[2] != gDCRGB[2] || a != gDCAlpha;
    gDCOn = on; gDCRGB[0] = rgb[0]; gDCRGB[1] = rgb[1]; gDCRGB[2] = rgb[2]; gDCAlpha = a;
    return changed;
}

// ---- what of ours is on a platter ----
@interface DMDockColorView : UIView
@property (nonatomic) double r, g, b, a;   // (the colour set last: a drag sets it only when it changed)
@end
@interface DMDockColorState : NSObject
@property (nonatomic, strong) DMDockColorView *view;
@property (nonatomic) int shown;   // 0 nothing drawn, 1 on iPadOS's material, 2 on Frosted's blur
@property (nonatomic) int marks;   // MSBDDockMarksApple, or ours (MSBDDockMarksLight / MSBDDockMarksDark)
@end
@implementation DMDockColorState
@end
static UIView *DCPlatterOf(UIView *v) {
    Class pc = objc_getClass("SBFloatingDockPlatterView");
    for (; v && pc; v = v.superview) if ([v isKindOfClass:pc]) return v;
    return nil;
}
static UIView *DCDockOf(UIView *platter) {   // (the platter's Dock view, SBFloatingDockView: its dividers)
    Class dc = objc_getClass("SBFloatingDockView");
    int up = 0;
    for (UIView *v = platter.superview; v && dc && up < 8; v = v.superview, up++) if ([v isKindOfClass:dc]) return v;
    return nil;
}
static void DCMarksAgain(UIView *platter);
@implementation DMDockColorView
- (void)traitCollectionDidChange:(UITraitCollection *)previous {   // (Light / Dark Mode: the marks are worked out again for this platter)
    [super traitCollectionDidChange:previous];
    if (previous && previous.userInterfaceStyle == self.traitCollection.userInterfaceStyle) return;
    UIView *platter = DCPlatterOf(self.superview);
    if (platter) DCMarksAgain(platter);
}
@end

static BOOL DCShape(id o, const char *sel, const char *enc) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), sel_registerName(sel)) : NULL;
    const char *e = m ? method_getTypeEncoding(m) : NULL;
    return e && !strcmp(e, enc);
}
static UIView *DCBackground(UIView *platter) {   // (Apple's material: the platter's -backgroundView, in its getter's shape only, as Dock Style reads it)
    if (!DCShape(platter, "backgroundView", "@16@0:8")) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(platter, sel_registerName("backgroundView"));
    return [v isKindOfClass:[UIView class]] ? v : nil;
}
static double DCCorner(UIView *bg) {
    double r = bg.layer.cornerRadius;
    if (r < 0.5 && DCShape(bg, "_continuousCornerRadius", "d16@0:8")) r = ((double (*)(id, SEL))objc_msgSend)(bg, sel_registerName("_continuousCornerRadius"));
    return isfinite(r) && r > 0 ? r : 0;
}
static void DCColorOn(DMDockColorView *cv) {
    if (cv.r == gDCRGB[0] && cv.g == gDCRGB[1] && cv.b == gDCRGB[2] && cv.a == gDCAlpha && cv.backgroundColor) return;
    cv.r = gDCRGB[0]; cv.g = gDCRGB[1]; cv.b = gDCRGB[2]; cv.a = gDCAlpha;
    cv.backgroundColor = [UIColor colorWithRed:gDCRGB[0] green:gDCRGB[1] blue:gDCRGB[2] alpha:gDCAlpha];
}
// B1: inside Apple's material, on top of what it holds, filling it, its corners. (No frame of ours fights a resize: the autoresizing mask follows the
// material's own bounds as they animate; the frame is set only when it is not the material's bounds, e.g. the first time.)
static void DCPlaceInside(DMDockColorView *cv, UIView *bg) {
    if (cv.superview != bg) [bg addSubview:cv];
    else if (bg.subviews.lastObject != cv) [bg bringSubviewToFront:cv];
    if (!CGAffineTransformIsIdentity(cv.transform)) cv.transform = CGAffineTransformIdentity;
    if (!CGRectEqualToRect(cv.frame, bg.bounds)) cv.frame = bg.bounds;
    if (cv.alpha != 1.0) cv.alpha = 1.0;
    if (cv.hidden) cv.hidden = NO;
    double r = DCCorner(bg);
    if (cv.layer.cornerRadius != r) cv.layer.cornerRadius = r;
    if (![cv.layer.cornerCurve isEqualToString:bg.layer.cornerCurve]) cv.layer.cornerCurve = bg.layer.cornerCurve;
    if (cv.layer.maskedCorners != bg.layer.maskedCorners) cv.layer.maskedCorners = bg.layer.maskedCorners;
}
#if DEBUG
static void DCPlaceSibling(DMDockColorView *cv, UIView *bg) {   // (debug only: the fallback, decided on the first iPad with "dockcolor")
    UIView *host = bg.superview;
    if (!host) { [cv removeFromSuperview]; return; }
    NSUInteger at = [host.subviews indexOfObject:bg];
    if (cv.superview != host || [host.subviews indexOfObject:cv] != at + 1) [host insertSubview:cv aboveSubview:bg];
    cv.transform = bg.transform; cv.bounds = bg.bounds; cv.center = bg.center;
    cv.alpha = bg.alpha; cv.hidden = bg.hidden;
    cv.layer.cornerRadius = DCCorner(bg); cv.layer.cornerCurve = bg.layer.cornerCurve; cv.layer.maskedCorners = bg.layer.maskedCorners;
}
#endif

// ---- the marks ----
static NSHashTable<UIView *> *gDCDotsFor;   // (platters whose marks changed: their Finder's dot too)
static void DCDotsSoon(UIView *platter) {   // (the dots once, on the main run loop's next turn: one pass however many platters changed)
    static BOOL pending = NO;
    if (!gDCDotsFor) gDCDotsFor = [NSHashTable weakObjectsHashTable];
    if (platter) [gDCDotsFor addObject:platter];
    if (pending) return;
    pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending = NO;
        NSArray<UIView *> *platters = gDCDotsFor.allObjects;
        [gDCDotsFor removeAllObjects];
        DMRunningIndicatorResyncAll();
        Class finder = objc_getClass("DMFinderIconView");
        SEL updateDot = NSSelectorFromString(@"updateDot");
        for (UIView *p in platters) for (UIView *sub in p.subviews) if (finder && [sub isKindOfClass:finder] && [sub respondsToSelector:updateDot]) ((void (*)(id, SEL))objc_msgSend)(sub, updateDot);
    });
}
// Our line's look, and the second divider's while our marks are on (one rule, so the two lines side by side are the same strength): the colour carries
// the look, the alpha only shows or hides the line. Written only where it differs (a Dock laid out inside an animation animates every value set).
static void DCLineLook(UIView *v, int marks, BOOL shown) {
    double g, al; MSBDDockMarkLine(marks, &g, &al);
    CGFloat w = -1, a = -1;
    if (![v.backgroundColor getWhite:&w alpha:&a] || fabs(w - g) > 1e-6 || fabs(a - al) > 1e-6) v.backgroundColor = [UIColor colorWithWhite:g alpha:al];
    if (v.alpha != (shown ? 1.0 : 0.0)) v.alpha = shown ? 1.0 : 0.0;
}
static void DCLineOver(UIView *native, int marks) {   // (B3: Apple's divider hidden by our empty mask, our line at its place; or both given back)
    CALayer *ours = objc_getAssociatedObject(native, kDCMaskKey);
    UIView *line = objc_getAssociatedObject(native, kDCLineKey);
    if (marks == MSBDDockMarksApple) {
        if (ours && native.layer.mask == ours) { id was = objc_getAssociatedObject(native, kDCWasKey); native.layer.mask = was == [NSNull null] ? nil : was; }
        if (ours) { objc_setAssociatedObject(native, kDCMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); objc_setAssociatedObject(native, kDCWasKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (line) { [line removeFromSuperview]; objc_setAssociatedObject(native, kDCLineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    if (!ours) { ours = [CALayer layer]; objc_setAssociatedObject(native, kDCMaskKey, ours, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }   // (empty: nothing shows through it)
    if (native.layer.mask != ours) {   // (the mask it had -- normally none --, or one iPadOS set since: what is given back)
        objc_setAssociatedObject(native, kDCWasKey, native.layer.mask ?: [NSNull null], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        native.layer.mask = ours;
    }
    if (!line) { line = [UIView new]; line.userInteractionEnabled = NO; objc_setAssociatedObject(native, kDCLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    UIView *host = native.superview;
    if (host && (line.superview != host || [host.subviews indexOfObject:line] != [host.subviews indexOfObject:native] + 1)) [host insertSubview:line aboveSubview:native];
    if (!CGAffineTransformEqualToTransform(line.transform, native.transform)) line.transform = native.transform;
    if (!CGRectEqualToRect(line.bounds, native.bounds)) line.bounds = native.bounds;
    if (!CGPointEqualToPoint(line.center, native.center)) line.center = native.center;
    if (line.layer.cornerRadius != native.layer.cornerRadius) line.layer.cornerRadius = native.layer.cornerRadius;
    if (line.hidden != native.hidden) line.hidden = native.hidden;
    DCLineLook(line, marks, !(native.alpha < 0.01));   // (iPadOS hides its own line by its alpha with no recents: ours with it; its look is ours, not its alpha)
}
// The second divider while this Dock's marks are ours: our line's look (DCLineLook), no compositing filter; YES. NO, and nothing read or written,
// while the marks are Apple's or our colour was never drawn (P7): Dock.x copies Apple's look then. Called by the second divider's one writer
// (Dock.x DMSecondDividerLookOf: each Dock layout, Apple's restyle, and the marks changing here), so Apple's look is never copied over ours.
// shown: the second divider is to be seen (Apple's line shown, or ours the only one with no recents).
BOOL DMDockColorSecondLook(UIView *dockView, UIView *mine, BOOL shown) {
    if (!gDCEver || !dockView || !mine) return NO;
    NSNumber *m = objc_getAssociatedObject(dockView, kDCDockMarksKey);
    if (!m || m.intValue == MSBDDockMarksApple) return NO;
    DCLineLook(mine, m.intValue, shown);
    if (mine.layer.filters.count) mine.layer.filters = nil;
    id cf = nil;
    @try { cf = [mine.layer valueForKey:@"compositingFilter"]; if (cf) [mine.layer setValue:nil forKey:@"compositingFilter"]; } @catch (id e) {}
    if (![objc_getAssociatedObject(mine, kDCSecondKey) isEqual:m]) objc_setAssociatedObject(mine, kDCSecondKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
// A Dock's dividers as its platter's marks want them (Dock.x: after the Dock's layout and after Apple's own restyle).
void DMDockColorDividers(UIView *dockView) {
    if (!gDCEver || !dockView) return;   // (our colour never drawn: nothing read, every layout -- P7)
    NSNumber *m = objc_getAssociatedObject(dockView, kDCDockMarksKey);
    if (!m) return;   // (nothing of ours on this Dock's dividers)
    int marks = m.intValue;
    UIView *native = DMDockNativeDivider(dockView), *mine = DMDockSecondDivider(dockView);
    if (native) DCLineOver(native, marks);
    NSNumber *on = mine ? objc_getAssociatedObject(mine, kDCSecondKey) : nil;   // (the marks of ours the second divider carries, if any)
    BOOL change = mine && (marks == MSBDDockMarksApple ? on != nil : !on || on.intValue != marks);   // (a layout gave it its look just before: only a change here)
    if (change && marks == MSBDDockMarksApple) objc_setAssociatedObject(mine, kDCSecondKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (change) DMDockSecondDividerLook(dockView);   // (its one writer: ours, or Apple's look copied again)
    if (marks == MSBDDockMarksApple) objc_setAssociatedObject(dockView, kDCDockMarksKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (all Apple's: the next layouts read nothing)
}
static void DCSetMarks(UIView *platter, DMDockColorState *st, int marks) {
    if (marks == st.marks) return;
    st.marks = marks;
    UIView *dock = DCDockOf(platter);
    if (dock) { objc_setAssociatedObject(dock, kDCDockMarksKey, @(marks), OBJC_ASSOCIATION_RETAIN_NONATOMIC); DMDockColorDividers(dock); }
    DCDotsSoon(platter);
    DMLog([NSString stringWithFormat:@"[dockcolor] marks on a platter %@: %s", NSStringFromCGRect(platter.bounds),
           marks == MSBDDockMarksApple ? "iPadOS's own" : marks == MSBDDockMarksDark ? "ours, dark" : "ours, light"]);
}
static int DCMarksFor(UIView *platter, int shown) {
    BOOL dark = platter.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return MSBDDockMarks(shown != 0, gDCRGB[0], gDCRGB[1], gDCRGB[2], gDCAlpha, shown == 2 ? MSBDDockUnderFrosted : MSBDDockUnderMaterial, dark);
}
static void DCMarksAgain(UIView *platter) {
    DMDockColorState *st = objc_getAssociatedObject(platter, kDCStateKey);
    if (st) DCSetMarks(platter, st, DCMarksFor(platter, st.shown));
}
// A running dot (DockStyle.m DMDockStyleDot, Default and Frosted, after today's dot was put back -- reset: it took labelColor just now): black or
// white while its platter's marks are ours; labelColor again, once, when they are iPadOS's again. Nothing written while nothing changed.
void DMDockColorDot(UIView *dot, UIView *platter, BOOL reset) {
    if (!gDCEver || !dot) return;   // (our colour never drawn: today's dot, nothing read -- P7)
    NSNumber *had = reset ? nil : objc_getAssociatedObject(dot, kDCDotKey);
    DMDockColorState *st = platter ? objc_getAssociatedObject(platter, kDCStateKey) : nil;
    int marks = st ? st.marks : MSBDDockMarksApple;
    if (marks == MSBDDockMarksApple) {
        if (had) dot.backgroundColor = [UIColor labelColor];
        if (had || reset) objc_setAssociatedObject(dot, kDCDotKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (had && had.intValue == marks) return;
    double g, al; MSBDDockMarkDot(marks, &g, &al);
    dot.backgroundColor = [UIColor colorWithWhite:g alpha:al];
    objc_setAssociatedObject(dot, kDCDotKey, @(marks), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---- a platter: our colour on, or everything given back ----
// From the platter's -layoutSubviews (Dock.x, after Dock Style's), DMDockStyleRefreshAll's walk (prefsChanged) and the light path.
void DMDockColorApply(UIView *platter) {
    DMDockColorState *st = platter ? objc_getAssociatedObject(platter, kDCStateKey) : nil;
    if (!gDCOn && !st) return;   // (Automatic, and nothing of ours ever on this platter: nothing is asked, every layout -- P7, as Dock Style's Default)
    if (gDCOn && !platter.window) return;
    int look = DMDockStyleLookOn(platter);
    int shown = !gDCOn ? 0 : look == MSBDDockLookDefault ? 1 : look == MSBDDockLookFrosted ? 2 : 0;   // (Glass Shelf, its side panel: nothing -- P8)
    UIView *bg = shown == 1 ? DCBackground(platter) : nil;
    if (shown == 1 && !bg) shown = 0;   // (no material to go in: nothing of ours)
    if (!st) { st = [DMDockColorState new]; st.marks = MSBDDockMarksApple; objc_setAssociatedObject(platter, kDCStateKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (shown) {
        DM_FEATURE_MARK("dock-color");
        gDCEver = YES;
        if (!gDCSeen) gDCSeen = [NSHashTable weakObjectsHashTable];
        [gDCSeen addObject:platter];
        if (!st.view) {
            st.view = [DMDockColorView new];
            st.view.userInteractionEnabled = NO;
            st.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        }
        DCColorOn(st.view);
        if (shown == 1) {
            DMDockStyleFrostedColor(platter, nil);
#if DEBUG
            if (gDCSibling) DCPlaceSibling(st.view, bg); else
#endif
            DCPlaceInside(st.view, bg);
        } else DMDockStyleFrostedColor(platter, st.view);
    } else {
        [st.view removeFromSuperview];
        DMDockStyleFrostedColor(platter, nil);   // (Frosted's own tint again)
    }
    if (st.shown != shown) DMLog([NSString stringWithFormat:@"[dockcolor] a platter %@: %s", NSStringFromCGRect(platter.bounds),
                                  shown == 1 ? "our colour inside iPadOS's material" : shown == 2 ? "our colour on Frosted's blur" : "nothing of ours"]);
    st.shown = shown;
    DCSetMarks(platter, st, DCMarksFor(platter, shown));
    if (!gDCOn) {   // (Automatic: all given back -- the record goes, so the next layouts ask nothing)
        st.view = nil;
        objc_setAssociatedObject(platter, kDCStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDCSeen removeObject:platter];
    }
}
static NSArray<UIView *> *DCAllPlatters(void) {   // (every Dock's platter, the TV's too: only when Color is switched on by the light path)
    Class pc = objc_getClass("SBFloatingDockPlatterView");
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    if (!pc) return out;
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            if ([v isKindOfClass:pc]) { [out addObject:v]; continue; }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    return out;
}
// DMLoadPrefs (Dock.x): the keys with the Dock part's switch; DMPrefsChanged's DMDockStyleRefreshAll then applies every platter.
void DMDockColorLoad(BOOL tweakOn) {
    gDCTweakOn = tweakOn;
    if (DCRead()) DMLog([NSString stringWithFormat:@"[dockcolor] Dock Background: %@", gDCOn ? [NSString stringWithFormat:@"Color %.3f %.3f %.3f at %.2f", gDCRGB[0], gDCRGB[1], gDCRGB[2], gDCAlpha] : @"Automatic"]);
}
// The light note (B4): the colour well or the opacity slider moved. The three keys only, then the platters ours is on (all of them, once, when Color
// was switched on by it); the dots and dividers only where the marks' answer changed. No DMLoadPrefs, no DMRelayoutDock, no walk per change.
void DMDockColorChanged(void) {
    CFPreferencesAppSynchronize(DC_DOMAIN);
    BOOL was = gDCOn;
    if (!DCRead()) return;
    NSArray<UIView *> *platters = gDCOn && !was ? DCAllPlatters() : gDCSeen.allObjects;
    for (UIView *p in platters) DMDockColorApply(p);
}

#if DEBUG
// debug ("dockcolor" in /tmp/dockmag-escape): per platter, what B1 rests on -- Apple's material (class, its superview, frame against the platter,
// corners, mask, alpha, hidden, its layers and where ours is among them), our view, the dividers and the marks decided. "dockcolorsibling" /
// "dockcolorinside": the colour as a sibling above the material (the fallback) or inside it (B1), every platter at once.
void DMDockColorDebug(const char *word) {
    if (!strcmp(word, "dockcolorsibling") || !strcmp(word, "dockcolorinside")) {
        gDCSibling = !strcmp(word, "dockcolorsibling");
        DMLog([NSString stringWithFormat:@"[dockcolor] debug: our colour %@", gDCSibling ? @"as a sibling above iPadOS's material" : @"inside iPadOS's material"]);
        for (UIView *p in DCAllPlatters()) DMDockColorApply(p);
    }
    for (UIView *p in DCAllPlatters()) {
        DMDockColorState *st = objc_getAssociatedObject(p, kDCStateKey);
        UIView *bg = DCBackground(p), *dock = DCDockOf(p), *native = dock ? DMDockNativeDivider(dock) : nil, *mine = dock ? DMDockSecondDivider(dock) : nil;
        NSMutableString *layers = [NSMutableString string];
        for (CALayer *l in bg.layer.sublayers) [layers appendFormat:@" %@%@", NSStringFromClass([l class]), l == st.view.layer ? @"(OURS)" : @""];
        NSMutableString *filters = [NSMutableString string];   // (the material's own filters: a backdrop layer's apply to what is behind it, not to ours inside)
        for (id f in bg.layer.filters) { id name = nil; @try { name = [f valueForKey:@"name"]; } @catch (id e) {} [filters appendFormat:@" %@", name ?: NSStringFromClass([f class])]; }
        UIView *line = native ? objc_getAssociatedObject(native, kDCLineKey) : nil;
        DMLog([NSString stringWithFormat:@"[dockcolor] platter %p %@ in %@ (%@), look %d, %@ Mode, choice %@ %.3f %.3f %.3f at %.2f, shown %d, marks %d\n"
               "  material %@ in %@: frame %@ (platter bounds %@), corner %.2f (layer %.2f) %@ masked %lu, masksToBounds %d, mask %@, alpha %.2f hidden %d, layer %@, its filters:%@, sublayers:%@\n"
               "  ours %@: in %@, frame %@, corner %.2f, colour %@, alpha %.2f hidden %d, index %lu of %lu (sibling way %d)\n"
               "  Apple's divider %@: frame %@ alpha %.2f hidden %d, colour %@, filter %@, filters %lu, our mask %d, our line %@ %@\n"
               "  second divider %@: colour %@, alpha %.2f, filter %@, ours %d",
               p, NSStringFromCGRect(p.bounds), NSStringFromClass([p.window class]), p.window.screen == [UIScreen mainScreen] ? @"the iPad" : @"another display",
               DMDockStyleLookOn(p), p.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? @"Dark" : @"Light", gDCOn ? @"Color" : @"Automatic",
               gDCRGB[0], gDCRGB[1], gDCRGB[2], gDCAlpha, st ? st.shown : -1, st ? st.marks : -2,
               bg ? NSStringFromClass([bg class]) : @"(none)", NSStringFromClass([bg.superview class]), NSStringFromCGRect([bg convertRect:bg.bounds toView:p]), NSStringFromCGRect(p.bounds),
               DCCorner(bg), bg.layer.cornerRadius, bg.layer.cornerCurve, (unsigned long)bg.layer.maskedCorners, bg.layer.masksToBounds, bg.layer.mask, bg.alpha, bg.hidden,
               NSStringFromClass([bg.layer class]), filters.length ? filters : @" none", layers,
               st.view ? @"yes" : @"none", NSStringFromClass([st.view.superview class]), NSStringFromCGRect(st.view.frame), st.view.layer.cornerRadius, st.view.backgroundColor,
               st.view.alpha, st.view.hidden, (unsigned long)[st.view.superview.subviews indexOfObject:st.view], (unsigned long)st.view.superview.subviews.count, gDCSibling,
               native ? NSStringFromClass([native class]) : @"(none)", NSStringFromCGRect(native.frame), native.alpha, native.hidden, native.backgroundColor,
               native ? [native.layer valueForKey:@"compositingFilter"] : nil, (unsigned long)native.layer.filters.count, native && native.layer.mask == objc_getAssociatedObject(native, kDCMaskKey) && native.layer.mask,
               line ? NSStringFromCGRect(line.frame) : @"none", line.backgroundColor,
               mine ? @"yes" : @"none", mine.backgroundColor, mine.alpha, mine ? [mine.layer valueForKey:@"compositingFilter"] : nil, mine && objc_getAssociatedObject(mine, kDCSecondKey) != nil]);
    }
}
#endif
