// EditProxy.m -- the Dock's own items in Edit Home Screen (1.8.3 item 5): Finder, Launchpad, Downloads and the Trash act as Apple's Dock icons do
// while the Home Screen is in edit mode. The rule and its reasons: EditProxyRule.h; how SnowBoard finds an icon: there and plans/v183.md item 5.
// Each item gets an icon view of SpringBoard's own (SBIconView) while editing: made as SpringBoard makes the Dock's (its list layout provider and
// location, read off an Apple icon of the same Dock), showing the item's app icon (DMIconTheme.h DMIconThemeIcon: common/IconTheme.h's
// MSBDThemableIcon, by the item's own identifier), editing (SpringBoard's jiggle), its picture the size of the item (its image matches its bounds,
// no content scaling of its own), no label, no close box, no drag, no delegate (a tap or a double tap opens nothing; SnowBoard's touchesBegan:
// hook sees an editing icon view and opens its menu for that icon). Finder's, Downloads' and the Trash's views are ours: the icon view goes inside,
// so it moves, grows (the hover magnification) and turns (Settings > Dock > Position) with the view, whose own picture, taps and menus wait. The
// App Library icon (Launchpad) is SpringBoard's own: the icon view goes beside it in the Dock, in its place, and it hides until editing ends.
// Where no icon view can be made (the icon path off: iPadOS 18, SpringBoard's classes not as read): the views jiggle themselves, taking no tap.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import "DMLog.h"
#import "DMIconTheme.h"
#import "EditProxyRule.h"

extern UIView *DMFinderIcon(UIView *platter);
extern UIView *DMDownloadsIcon(UIView *platter);
extern UIView *DMTrashIcon(UIView *platter);
extern UIView *DMLaunchpadOverlayOf(UIView *iconView);   // (Launchpad.m: our Launchpad picture over the App Library icon)

static const void *kEPProxyKey = &kEPProxyKey;   // (on our view, or on the App Library icon: the icon view standing in for it)
static const void *kEPSavedKey = &kEPSavedKey;   // (what editing set aside: recognizers' enabled, interactions, subviews' hidden)
static const void *kEPItemKey = &kEPItemKey;     // (the item the icon view shows)
static NSString *const kEPJiggleKey = @"MSBDEditJiggle";
// Per Dock (its platter, one per SBFloatingDockViewController -- review 1.8.3 P3-1: a second Dock ending its editing undid the first's): whether it
// is editing, and every view edit mode changed in it -- our three views, the App Library icon -- kept weakly, so the end puts each back from there
// (review P2-7: the App Library icon stayed hidden, and the flag on, when the platter was not found again at the end; Dock.x hands the end the
// platter its controller had). A platter that goes takes its views with it.
static const void *kEPEditingKey = &kEPEditingKey;   // (on a platter: @YES while its Dock edits)
static const void *kEPOursKey = &kEPOursKey, *kEPLibraryKey = &kEPLibraryKey;   // (on a platter: NSHashTable, weak, of its changed views)
static NSHashTable<UIView *> *gEPEditingPlatters;   // (the platters editing now, weakly)
static const void *kEPHidKey = &kEPHidKey;   // (on the App Library icon: hidden by us while editing)
static NSHashTable<UIView *> *EPChanged(UIView *platter, const void *key, BOOL make) {
    NSHashTable *t = platter ? objc_getAssociatedObject(platter, key) : nil;
    if (!t && make && platter) { t = [NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(platter, key, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return t;
}

// ---- calls on SpringBoard's icon view, each only with the type read here ----
static BOOL EPHas(id o, NSString *sel, const char *types) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), NSSelectorFromString(sel)) : NULL;
    return m && !strcmp(method_getTypeEncoding(m) ?: "", types);
}
static BOOL EPObj(id o, NSString *sel, id arg) {
    if (!EPHas(o, sel, "v24@0:8@16")) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(o, NSSelectorFromString(sel), arg);
    return YES;
}
static BOOL EPBool(id o, NSString *sel, BOOL arg) {
    if (!EPHas(o, sel, "v20@0:8B16")) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(o, NSSelectorFromString(sel), arg);
    return YES;
}
static BOOL EPDouble(id o, NSString *sel, double arg) {
    if (!EPHas(o, sel, "v24@0:8d16")) return NO;
    ((void (*)(id, SEL, double))objc_msgSend)(o, NSSelectorFromString(sel), arg);
    return YES;
}
// (no label: the Dock's icons have none -- the first icon views showed their names under the Dock in edit mode, M1)
static void EPNoLabel(UIView *v) {
    EPBool(v, @"configureForLabelAllowed:", NO);
    EPBool(v, @"setLabelHidden:", YES);
    EPDouble(v, @"setIconLabelAlpha:", 0.0);
}
static BOOL EPEditing(id o, BOOL editing, BOOL animated) {
    if (!EPHas(o, @"setEditing:animated:", "v24@0:8B16B20")) return NO;
    ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(o, @selector(setEditing:animated:), editing, animated);
    return YES;
}
static id EPGet(id o, NSString *key) { @try { return [o valueForKey:key]; } @catch (NSException *e) { return nil; } }
// (no drag: its drag interaction, where SpringBoard made one, switched off -- looked at again after each change of its state -- and no tap)
static void EPNoTaps(UIView *v);
static void EPNoDrag(UIView *v) {
    for (id i in [v.interactions copy]) if ([i isKindOfClass:[UIDragInteraction class]]) ((UIDragInteraction *)i).enabled = MSBDEditDrag();
    EPNoTaps(v);
    EPNoLabel(v);
}
// Its picture the item's size on screen. SpringBoard lays an icon view out at its own size -- the Dock's icon size with the label's room under it,
// whatever bounds it is given (read on the M1: given 42 x 42, it came out 61 x 78, its picture a size too big) --, so it keeps that size and is
// scaled down to ours as a whole, its picture (-iconImageFrame) centred where our view's picture is. No content scale of its own over it
// (setIconContentScalingEnabled: NO: Atria's Dock scale on the M1). Worked out again at every Dock layout while editing.
typedef struct { CGSize size; double scale; double continuousCornerRadius; } EPImageInfo;
static void EPFit(UIView *proxy, CGRect want, CGAffineTransform over) {
    if (!(want.size.width > 4.0) || !(want.size.height > 4.0)) return;
    proxy.transform = CGAffineTransformIdentity;
    CGSize natural = CGSizeZero;
    if (EPHas(proxy, @"iconImageInfo", "{SBIconImageInfo={CGSize=dd}dd}16@0:8")) natural = ((EPImageInfo (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"iconImageInfo")).size;
    if (!(natural.width > 4.0) || !(natural.height > 4.0)) natural = want.size;
    if (!CGSizeEqualToSize(proxy.bounds.size, natural)) proxy.bounds = CGRectMake(0, 0, natural.width, natural.height);
    [proxy layoutIfNeeded];
    CGRect img = proxy.bounds;
    if (EPHas(proxy, @"iconImageFrame", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8")) {
        CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"iconImageFrame"));
        if (f.size.width > 4.0 && f.size.height > 4.0) img = f;
    }
    CGFloat k = want.size.width / img.size.width;
    CGPoint bc = CGPointMake(CGRectGetMidX(proxy.bounds), CGRectGetMidY(proxy.bounds)), ic = CGPointMake(CGRectGetMidX(img), CGRectGetMidY(img));
    proxy.center = CGPointMake(CGRectGetMidX(want) + (bc.x - ic.x) * k, CGRectGetMidY(want) + (bc.y - ic.y) * k);
    proxy.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(k, k), over);
}

// ---- the icon view for one item ----
// A class of ours under SBIconView, made by name at run time, whose tap does nothing: an icon view's tap (-_handleTap) launches its icon --
// with no delegate too: read on the M1 (15.6.1, Aerial 5.0), a tap on Finder's icon view in edit mode was handed to Aerial's icon tap, which
// launched "com.besiktasliseba.finder", an app that does not exist, and kept trying for 11 s with an empty window up. Its own recognisers are
// switched off too (EPNoTaps); SnowBoard's menu comes from -touchesBegan:withEvent:, which stays SBIconView's (and SnowBoard's hook of it).
static void EPNoTap(id self, SEL _cmd) {}
static BOOL EPNo(id self, SEL _cmd) { return NO; }
static Class EPProxyClass(void) {
    Class have = objc_getClass("MSBDEditProxyIconView");
    if (have) return have;
    Class ivc = objc_getClass("SBIconView");
    Method tap = ivc ? class_getInstanceMethod(ivc, NSSelectorFromString(@"_handleTap")) : NULL;
    if (!tap || strcmp(method_getTypeEncoding(tap) ?: "", "v16@0:8")) return Nil;   // (not as read: no icon view of ours here)
    Class c = objc_allocateClassPair(ivc, "MSBDEditProxyIconView", 0);
    if (!c) return objc_getClass("MSBDEditProxyIconView");
    class_addMethod(c, NSSelectorFromString(@"_handleTap"), (IMP)EPNoTap, "v16@0:8");
    Method atw = class_getInstanceMethod(ivc, NSSelectorFromString(@"allowsTapWhileEditing"));
    if (atw && !strcmp(method_getTypeEncoding(atw) ?: "", "B16@0:8")) class_addMethod(c, NSSelectorFromString(@"allowsTapWhileEditing"), (IMP)EPNo, "B16@0:8");
    objc_registerClassPair(c);
    return c;
}
// (its own recognisers off -- tap, long press, the editing gesture -- looked at again after each change of its state; its touches still come)
static void EPNoTaps(UIView *v) { for (UIGestureRecognizer *g in v.gestureRecognizers) if (g.enabled) g.enabled = NO; }
// model: an Apple icon of this Dock (its provider and location: the Dock's own size, corners and jiggle).
static UIView *EPMakeProxy(int item, UIView *model) {
    Class ivc = EPProxyClass();
    SEL init = NSSelectorFromString(@"initWithConfigurationOptions:listLayoutProvider:");
    Method m = ivc ? class_getInstanceMethod(ivc, init) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "@32@0:8Q16@24")) return nil;
    id icon = DMIconThemeIcon((MSBDIconItem)item);
    id provider = EPGet(model, @"listLayoutProvider"), location = EPGet(model, @"location");
    if (!icon || !provider || ![location isKindOfClass:[NSString class]]) return nil;
    UIView *v = nil;
    @try {
        v = ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)([ivc alloc], init, 0ULL, provider);
        if (![v isKindOfClass:ivc]) return nil;
        if (!EPObj(v, @"setLocation:", location) || !EPObj(v, @"setIcon:", icon)) return nil;
        EPNoLabel(v);
        EPBool(v, @"setAllowsCloseBox:", MSBDEditCloseBox());
        EPBool(v, @"setAllowsEditingAnimation:", YES);
        EPBool(v, @"setIconContentScalingEnabled:", NO);        // (no scale of its own over it: our view's own picture has none)
    } @catch (NSException *e) {
        DMLog([NSString stringWithFormat:@"[editmode] the icon view for item %d was refused: %@", item, e.reason]);
        return nil;
    }
    objc_setAssociatedObject(v, kEPItemKey, @(item), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.accessibilityElementsHidden = NO;
    return v;
}
// An Apple icon of this Dock (an app's; else the App Library icon): the model for ours.
static UIView *EPModelIcon(UIView *platter, UIView **libraryOut) {
    Class ivc = objc_getClass("SBIconView");
    UIView *app = nil, *library = nil;
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:platter];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        if (ivc && [v isKindOfClass:ivc]) {
            if (objc_getAssociatedObject(v, kEPItemKey)) continue;   // (one of ours)
            NSString *ic = NSStringFromClass([EPGet(v, @"icon") class]);
            if ([ic isEqualToString:@"SBHLibraryPodIndicatorIcon"]) { if (!library && v.superview == platter) library = v; }
            else if (!app && ![NSStringFromClass([v.superview class]) isEqualToString:@"SBDockSuggestionsIconListView"]) app = v;
            continue;
        }
        [todo addObjectsFromArray:v.subviews];
    }
    if (libraryOut) *libraryOut = library;
    return app ?: library;
}

// ---- our own view while editing: its taps, double taps and menus set aside, its picture under SpringBoard's ----
static void EPQuiet(UIView *v, BOOL quiet, UIView *keep, UIView *keepToo) {
    NSMutableDictionary *saved = objc_getAssociatedObject(v, kEPSavedKey);
    if (quiet) {
        if (saved) return;   // (set aside already)
        saved = [NSMutableDictionary dictionary];
        NSMutableArray *grs = [NSMutableArray array], *interactions = [NSMutableArray array], *hidden = [NSMutableArray array];
        for (UIGestureRecognizer *g in v.gestureRecognizers) { [grs addObject:@[g, @(g.enabled)]]; g.enabled = NO; }
        for (id i in [v.interactions copy]) if ([i isKindOfClass:[UIContextMenuInteraction class]]) { [interactions addObject:i]; [v removeInteraction:i]; }
        if (keep) for (UIView *s in v.subviews) if (s != keep && s != keepToo && !s.hidden) { [hidden addObject:s]; s.hidden = YES; }
        saved[@"grs"] = grs; saved[@"interactions"] = interactions; saved[@"hidden"] = hidden;
        objc_setAssociatedObject(v, kEPSavedKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!saved) return;
    for (NSArray *p in saved[@"grs"]) ((UIGestureRecognizer *)p[0]).enabled = [p[1] boolValue];
    for (id i in saved[@"interactions"]) if (![v.interactions containsObject:i]) [v addInteraction:i];
    for (UIView *s in saved[@"hidden"]) s.hidden = NO;
    objc_setAssociatedObject(v, kEPSavedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// (our own jiggle, where no icon view of SpringBoard's can be made: EditProxyRule.h)
static void EPOwnJiggle(UIView *v, int view, BOOL on) {
    if (!on) { [v.layer removeAnimationForKey:kEPJiggleKey]; return; }
    if ([v.layer animationForKey:kEPJiggleKey]) return;
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.values = @[@(-kMSBDEditJiggleRadians), @(kMSBDEditJiggleRadians), @(-kMSBDEditJiggleRadians)];
    a.duration = kMSBDEditJiggleSeconds * 2.0;
    a.repeatCount = HUGE_VALF;
    a.additive = YES;   // (over the hover magnification's and the side Dock's transforms)
    a.timeOffset = MSBDEditJigglePhase(view) * a.duration;
    [v.layer addAnimation:a forKey:kEPJiggleKey];
}
// Our view (Finder, Downloads, the Trash): covered, or jiggling itself.
static void EPCoverOurs(UIView *v, int view, int item, UIView *model, BOOL editing, BOOL animated, UIView *platter) {
    UIView *proxy = objc_getAssociatedObject(v, kEPProxyKey);
    if (proxy && editing && [objc_getAssociatedObject(proxy, kEPItemKey) intValue] != item) {   // (the Trash filled or emptied meanwhile: its picture now)
        [proxy removeFromSuperview]; objc_setAssociatedObject(v, kEPProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); proxy = nil;
    }
    if (editing && !proxy && model) {
        proxy = EPMakeProxy(item, model);
        if (proxy) {
            [v addSubview:proxy];
            objc_setAssociatedObject(v, kEPProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (proxy && editing) EPFit(proxy, v.bounds, CGAffineTransformIdentity);   // (also at every Dock layout while editing: our view's size now)
    int how = MSBDEditHow(editing, proxy != nil);
    UIView *dot = EPGet(v, @"dot");   // (Finder's running dot stays, as an app's does)
    if (how == kMSBDEditNone) {
        if (proxy) { EPEditing(proxy, NO, NO); [proxy removeFromSuperview]; objc_setAssociatedObject(v, kEPProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        EPOwnJiggle(v, view, NO);
        EPQuiet(v, NO, nil, nil);
        return;
    }
    [EPChanged(platter, kEPOursKey, YES) addObject:v];
    EPQuiet(v, YES, how == kMSBDEditCover ? proxy : nil, [dot isKindOfClass:[UIView class]] ? dot : nil);
    if (how == kMSBDEditCover) { [v bringSubviewToFront:proxy]; EPEditing(proxy, YES, animated); EPNoDrag(proxy); EPOwnJiggle(v, view, NO); }
    else EPOwnJiggle(v, view, YES);
}
// (the end of editing for one of our views, from what was kept of it: its icon view gone, its own jiggle stopped, its taps and pictures back)
static void EPUndoOurs(UIView *v) {
    UIView *proxy = objc_getAssociatedObject(v, kEPProxyKey);
    if (proxy) { EPEditing(proxy, NO, NO); [proxy removeFromSuperview]; objc_setAssociatedObject(v, kEPProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [v.layer removeAnimationForKey:kEPJiggleKey];
    EPQuiet(v, NO, nil, nil);
}
// The App Library icon (Launchpad): SpringBoard's own; ours goes beside it, in its place, while it hides.
static void EPFollow(UIView *proxy, UIView *library) {
    if (!proxy || !library || !library.superview) return;
    // (its place, our picture as big as the App Library icon's own picture is drawn -- that one has the Dock's scale over it --, the icon's own
    //  transform -- the hover magnification -- and turn on top, as the App Library icon has them)
    CGAffineTransform t = library.transform;
    CGRect box = CGRectMake(library.center.x - library.bounds.size.width / 2.0, library.center.y - library.bounds.size.height / 2.0, library.bounds.size.width, library.bounds.size.height);
    UIView *img = EPHas(library, @"_iconImageView", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(library, NSSelectorFromString(@"_iconImageView")) : nil;
    CGRect want = box;
    UIView *drawn = DMLaunchpadOverlayOf(library);   // (our Launchpad picture as it is drawn on it; else the App Library icon's own picture)
    if (drawn.window) img = drawn;
    if ([img isKindOfClass:[UIView class]]) {   // (the picture in the icon's own space, so without its transform: placed in its untransformed box)
        CGRect r = [img convertRect:img.bounds toView:library];
        want = CGRectMake(box.origin.x + r.origin.x - library.bounds.origin.x, box.origin.y + r.origin.y - library.bounds.origin.y, r.size.width, r.size.height);
    }
    EPFit(proxy, want, t);
    proxy.layer.sublayerTransform = library.layer.sublayerTransform;   // (its turn beside a side Dock)
}
// (the end of editing for the App Library icon: its icon view gone, shown again if we hid it, its own jiggle stopped, its taps back)
static void EPUndoLibrary(UIView *library) {
    UIView *proxy = objc_getAssociatedObject(library, kEPProxyKey);
    if (proxy) { EPEditing(proxy, NO, NO); [proxy removeFromSuperview]; objc_setAssociatedObject(library, kEPProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if ([objc_getAssociatedObject(library, kEPHidKey) boolValue]) { library.hidden = NO; objc_setAssociatedObject(library, kEPHidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [library.layer removeAnimationForKey:kEPJiggleKey];
    EPQuiet(library, NO, nil, nil);
}
static void EPCoverLibrary(UIView *library, int item, BOOL editing, BOOL animated, UIView *platter) {
    if (!library) return;
    UIView *proxy = objc_getAssociatedObject(library, kEPProxyKey);
    if (proxy && editing && [objc_getAssociatedObject(proxy, kEPItemKey) intValue] != item) {
        [proxy removeFromSuperview]; objc_setAssociatedObject(library, kEPProxyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); proxy = nil;
    }
    if (editing && !proxy && library.superview) {
        proxy = EPMakeProxy(item, library);
        if (proxy) {
            [library.superview insertSubview:proxy aboveSubview:library];
            objc_setAssociatedObject(library, kEPProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    int how = MSBDEditHow(editing, proxy != nil);
    if (how == kMSBDEditNone) { EPUndoLibrary(library); return; }
    [EPChanged(platter, kEPLibraryKey, YES) addObject:library];
    if (how == kMSBDEditCover) {
        EPFollow(proxy, library);
        if (!library.hidden) { library.hidden = YES; objc_setAssociatedObject(library, kEPHidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }   // (only what we hid comes back)
        EPEditing(proxy, YES, animated); EPNoDrag(proxy);
    }
    else { EPQuiet(library, YES, nil, nil); EPOwnJiggle(library, kMSBDEditLaunchpad, YES); }
}

// ---- the edit mode's start and end, and every Dock layout while it lasts ----
void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadClassic, BOOL logAlways) {
    UIView *library = nil, *model = nil, *finder = nil, *downloads = nil, *trash = nil;
    if (platter) {
        model = EPModelIcon(platter, &library);
        finder = DMFinderIcon(platter); downloads = DMDownloadsIcon(platter); trash = DMTrashIcon(platter);
        BOOL full = [EPGet(trash, @"count") integerValue] > 0;
        if (finder) EPCoverOurs(finder, kMSBDEditFinder, MSBDEditIconItem(kMSBDEditFinder, launchpadClassic, full), model, editing, animated, platter);
        if (downloads) EPCoverOurs(downloads, kMSBDEditDownloads, MSBDEditIconItem(kMSBDEditDownloads, launchpadClassic, full), model, editing, animated, platter);
        if (trash) EPCoverOurs(trash, kMSBDEditTrash, MSBDEditIconItem(kMSBDEditTrash, launchpadClassic, full), model, editing, animated, platter);
        EPCoverLibrary(library, MSBDEditIconItem(kMSBDEditLaunchpad, launchpadClassic, full), editing, animated, platter);
    }
    BOOL was = platter && [objc_getAssociatedObject(platter, kEPEditingKey) boolValue];
    if (!editing && platter) {   // (this Dock's end: every view editing changed in it, from what was kept of it; another Dock still editing keeps its own)
        for (UIView *v in [EPChanged(platter, kEPOursKey, NO) allObjects]) EPUndoOurs(v);
        for (UIView *l in [EPChanged(platter, kEPLibraryKey, NO) allObjects]) EPUndoLibrary(l);
        [EPChanged(platter, kEPOursKey, NO) removeAllObjects]; [EPChanged(platter, kEPLibraryKey, NO) removeAllObjects];
    }
    if (!editing && was) DMIconThemeAskAgain(@"Edit Home Screen ended");   // (a per-icon choice made in SnowBoard's menu meanwhile: our views show it now)
    if (editing != was || logAlways) {
        DMLog([NSString stringWithFormat:@"[editmode] %@: Finder %@, Downloads %@, Trash %@, Launchpad %@ (model %@)", editing ? @"on" : @"off",
               finder ? (objc_getAssociatedObject(finder, kEPProxyKey) ? @"covered" : editing ? @"jiggles itself" : @"as before") : @"-",
               downloads ? (objc_getAssociatedObject(downloads, kEPProxyKey) ? @"covered" : editing ? @"jiggles itself" : @"as before") : @"-",
               trash ? (objc_getAssociatedObject(trash, kEPProxyKey) ? @"covered" : editing ? @"jiggles itself" : @"as before") : @"-",
               library ? (objc_getAssociatedObject(library, kEPProxyKey) ? @"covered" : editing ? @"jiggles itself" : @"as before") : @"-",
               NSStringFromClass([EPGet(model, @"icon") class]) ?: @"none"]);
    }
    if (platter) {   // (this Dock's edit state: the layout hook follows it, Dock.x)
        objc_setAssociatedObject(platter, kEPEditingKey, editing ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gEPEditingPlatters) gEPEditingPlatters = [NSHashTable weakObjectsHashTable];
        if (editing) [gEPEditingPlatters addObject:platter]; else [gEPEditingPlatters removeObject:platter];
    }
}
BOOL DMEditProxiesOn(UIView *platter) { return platter && [objc_getAssociatedObject(platter, kEPEditingKey) boolValue]; }
// A theme engine refreshed its pictures while editing: each icon view asks its icon again.
void DMEditProxiesThemeChanged(UIView *platter) {
    if (!DMEditProxiesOn(platter)) return;
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:platter];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject];
        UIView *proxy = objc_getAssociatedObject(v, kEPProxyKey);
        if (proxy) { id icon = EPGet(proxy, @"icon"); if (icon) { EPObj(proxy, @"setIcon:", nil); EPObj(proxy, @"setIcon:", icon); EPEditing(proxy, YES, NO); EPNoDrag(proxy); } }
        [todo addObjectsFromArray:v.subviews];
    }
}
// A theme engine refreshed its pictures: every Dock editing now (Dock.x's theme observer).
void DMEditProxiesThemeChangedAll(void) { for (UIView *p in [gEPEditingPlatters allObjects]) DMEditProxiesThemeChanged(p); }
