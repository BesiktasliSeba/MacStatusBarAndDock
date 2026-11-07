// IconTheme.h -- the Dock's own items as app icons an icon theme can change (1.7.5 item 7, KT 31 Oct: "fully compatible with SnowBoard theming
// like any icon is"). Included once per library: dock/IconTheme.m (Finder, Launchpad, Downloads, the Trash) and statusbar/AppLibraryApps.h
// (Activity Monitor). The identifiers and rules: common/IconThemeIDs.h.
//
// How (read on 17.5.1, with SnowBoard 1.5.37's hooks; release-1.7.5.md "v175 SnowBoard-themable Dock icons"): SpringBoard draws an app's icon with
// SBApplicationIcon (: SBHApplicationIcon on 17 : SBLeafIcon : SBIcon): -iconImageWithInfo: -> -generateIconImageWithInfo:, which asks the icon's
// data source -icon:imageWithInfo: (-unmaskedIconImageWithInfo: -> -icon:unmaskedImageWithInfo:). A theme engine themes app icons on that class
// (SnowBoard replaces exactly those methods of SBApplicationIcon and keys them by -applicationBundleID). So each item here is an
// SBApplicationIcon of its own (MSBDThemableIcon, a subclass made at run time that overrides no image method) with its own bundle identifier,
// and a data source of ours (MSBDIconPictureSource) draws our picture as "the app's own icon": with a theme the engine's picture comes back,
// without one our picture as the engine shapes any app's own icon (its mask, corner radius, effects), and with no engine our picture as drawn.
// Both classes are made by name, so the two libraries share them. Never put in SpringBoard's icon model: nothing is saved, nothing is listed.
//
// Safety: the shapes are checked once (classes, methods and their type strings, the data source protocol) and a probe icon runs SpringBoard's own
// -[SBLeafIcon generateIconImageWithInfo:] / -unmaskedIconImageWithInfo: once: the path is on only when both come back with the probe's own
// pictures. Otherwise, and on iPadOS 18 (KT 1 Nov: no theming there, our pictures stay), the callers draw their pictures themselves as before.
#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#import "IconThemeIDs.h"

typedef struct { CGSize size; double scale; double continuousCornerRadius; } MSBDIconImageInfo;   // SpringBoard's SBIconImageInfo (15-18)
// Draws an item's own picture at a size (points) and scale: masked = as an app icon shows it (with its corners; the bin has none), unmasked =
// its whole square canvas (what an engine masks itself). Called on the main thread (the source says so to SpringBoard).
typedef UIImage *(^MSBDIconDrawer)(CGSize size, CGFloat scale, CGFloat radius, BOOL masked);

// ---- the data source: our picture for SpringBoard's chain -----------------------------------------------------------------------------------
// Per instance (associated objects, keyed by selectors: the same keys in both libraries): the item, its drawer, how many pictures it drew.
#define kMSBDIconKeyItem   @selector(msbd_iconItem)
#define kMSBDIconKeyDrawer @selector(msbd_iconDrawer)
#define kMSBDIconKeyDrew   @selector(msbd_iconDrew)
static NSUInteger MSBDIconSourceDrew(id src) {
    if (!src) return 0;
    @synchronized (src) { return [objc_getAssociatedObject(src, kMSBDIconKeyDrew) unsignedIntegerValue]; }
}
// The unmasked picture of an item with transparent margins marks its canvas (IconThemeIDs.h MSBDIconHasMargins / MSBDIconCanvasMarks).
static UIImage *MSBDIconMarkCanvas(UIImage *img) {
    CGImageRef cg = img.CGImage;
    if (!cg) return img;
    int w = (int)CGImageGetWidth(cg), h = (int)CGImageGetHeight(cg);
    if (w < 2 || h < 2) return img;
    MSBDCanvasMarks m = MSBDIconCanvasMarks(w, h);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = img.scale; fmt.opaque = NO;
    CGFloat px = 1.0 / img.scale;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:img.size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [img drawAtPoint:CGPointZero];
        CGContextRef c = ctx.CGContext;
        CGContextSetBlendMode(c, kCGBlendModeNormal);
        CGContextSetRGBFillColor(c, 0, 0, 0, 1.0 / 255.0);
        CGContextFillRect(c, CGRectMake(m.x0 * px, m.y0 * px, px, px));
        CGContextFillRect(c, CGRectMake(m.x1 * px, m.y1 * px, px, px));
    }];
}
static UIImage *MSBDIconSourceDraw(id self, MSBDIconImageInfo info, BOOL masked) {
    MSBDIconDrawer d = objc_getAssociatedObject(self, kMSBDIconKeyDrawer);
    NSInteger item = [objc_getAssociatedObject(self, kMSBDIconKeyItem) integerValue];
    if (!d || !(info.size.width >= 2.0) || !(info.size.height >= 2.0) || !isfinite(info.size.width) || !isfinite(info.size.height)) return nil;
    CGFloat scale = info.scale > 0.5 && info.scale < 5.0 ? info.scale : [UIScreen mainScreen].scale;
    CGFloat radius = isfinite(info.continuousCornerRadius) && info.continuousCornerRadius >= 0.0 ? info.continuousCornerRadius : 0.0;
    UIImage *img = d(info.size, scale, radius, masked);
    if (img && !masked && MSBDIconHasMargins((MSBDIconItem)item)) img = MSBDIconMarkCanvas(img);
    if (img) @synchronized (self) { objc_setAssociatedObject(self, kMSBDIconKeyDrew, @([objc_getAssociatedObject(self, kMSBDIconKeyDrew) unsignedIntegerValue] + 1), OBJC_ASSOCIATION_RETAIN); }
    return img;
}
static id MSBDIconSourceImage(id self, SEL _cmd, id icon, MSBDIconImageInfo info) { return MSBDIconSourceDraw(self, info, YES); }
static id MSBDIconSourceUnmasked(id self, SEL _cmd, id icon, MSBDIconImageInfo info) { return MSBDIconSourceDraw(self, info, NO); }
static id MSBDIconSourceName(id self, SEL _cmd, id icon, id location) { return MSBDIconName((MSBDIconItem)[objc_getAssociatedObject(self, kMSBDIconKeyItem) integerValue]); }
static unsigned long long MSBDIconSourcePriority(id self, SEL _cmd, id icon) { return 0; }
static BOOL MSBDIconSourceNo(id self, SEL _cmd, id icon) { return NO; }
static BOOL MSBDIconSourceYes(id self, SEL _cmd, id icon) { return YES; }

// The protocol's method with that selector, required or not, and its type string ('\0' when the protocol has no such method).
static const char *MSBDIconProtoTypes(Protocol *p, SEL s) {
    struct objc_method_description d = protocol_getMethodDescription(p, s, YES, YES);
    if (!d.name) d = protocol_getMethodDescription(p, s, NO, YES);
    return d.name ? d.types : NULL;
}
static Class MSBDIconSourceClass(NSMutableArray *why) {
    Class have = objc_getClass("MSBDIconPictureSource");   // (the other library made it already)
    if (have) return have;
    Protocol *p = objc_getProtocol("SBLeafIconDataSource");
    if (!p) { [why addObject:@"no SBLeafIconDataSource protocol"]; return Nil; }
    // Every required method of the protocol is answered (read on 17.5.1: -icon:displayNameForLocation:, -priorityForIcon: in SpringBoard's copy)
    // -- an unknown required one keeps the path off.
    NSDictionary *mine = @{ @"icon:imageWithInfo:": MSBDIconSourceMethodTypes(), @"icon:unmaskedImageWithInfo:": MSBDIconSourceMethodTypes(),
                            @"icon:displayNameForLocation:": @"@@:@@", @"priorityForIcon:": @"Q@:@", @"iconSupportsUninstall:": @"B@:@",
                            @"iconCompleteUninstall:": @"B@:@", @"canGenerateIconsInBackgroundForIcon:": @"B@:@", @"iconAllowsLaunch:": @"B@:@" };
    unsigned n = 0;
    struct objc_method_description *req = protocol_copyMethodDescriptionList(p, YES, YES, &n);
    for (unsigned i = 0; i < n; i++) if (!mine[NSStringFromSelector(req[i].name)]) [why addObject:[NSString stringWithFormat:@"required %@", NSStringFromSelector(req[i].name)]];
    free(req);
    for (NSString *s in @[@"icon:imageWithInfo:", @"icon:unmaskedImageWithInfo:"])
        if (!MSBDIconTypesAre(MSBDIconProtoTypes(p, NSSelectorFromString(s)), mine[s])) [why addObject:[NSString stringWithFormat:@"%@ not as read", s]];
    if (why.count) return Nil;
    Class k = objc_allocateClassPair([NSObject class], "MSBDIconPictureSource", 0);
    if (!k) return objc_getClass("MSBDIconPictureSource");
    NSDictionary *imps = @{ @"icon:imageWithInfo:": [NSValue valueWithPointer:(void *)MSBDIconSourceImage],
                            @"icon:unmaskedImageWithInfo:": [NSValue valueWithPointer:(void *)MSBDIconSourceUnmasked],
                            @"icon:displayNameForLocation:": [NSValue valueWithPointer:(void *)MSBDIconSourceName],
                            @"priorityForIcon:": [NSValue valueWithPointer:(void *)MSBDIconSourcePriority],
                            @"iconSupportsUninstall:": [NSValue valueWithPointer:(void *)MSBDIconSourceNo],
                            @"iconCompleteUninstall:": [NSValue valueWithPointer:(void *)MSBDIconSourceNo],
                            @"canGenerateIconsInBackgroundForIcon:": [NSValue valueWithPointer:(void *)MSBDIconSourceNo],   // (our drawers: main thread)
                            @"iconAllowsLaunch:": [NSValue valueWithPointer:(void *)MSBDIconSourceYes] };
    for (NSString *s in imps) {
        const char *t = MSBDIconProtoTypes(p, NSSelectorFromString(s));
        if (t && !MSBDIconTypesAre(t, mine[s])) continue;   // (a method of the protocol in another shape here: not answered)
        if (!t && ![s isEqualToString:@"icon:displayNameForLocation:"] && ![s isEqualToString:@"priorityForIcon:"]) continue;   // (not in this protocol)
        class_addMethod(k, NSSelectorFromString(s), (IMP)[imps[s] pointerValue], t ?: [mine[s] UTF8String]);   // (the protocol's own type string)
    }
    class_addProtocol(k, p);
    objc_registerClassPair(k);
    return k;
}

// ---- the icon: SBApplicationIcon with only what an app icon without an app needs ------------------------------------------------------------
static id MSBDIconNil(id self, SEL _cmd) { return nil; }
static BOOL MSBDIconNo(id self, SEL _cmd) { return NO; }
static id MSBDIconCacheID(id self, SEL _cmd) {   // (SpringBoard's image caches key by this: the bundle identifier, as for an app)
    id b = ((id (*)(id, SEL))objc_msgSend)(self, @selector(applicationBundleID));
    return [b isKindOfClass:[NSString class]] ? b : @"com.besiktasliseba.macstatusbar.icon";
}
static BOOL MSBDIconAddIf(Class c, Class from, NSString *sel, NSString *types, IMP imp) {
    Method m = class_getInstanceMethod(from, NSSelectorFromString(sel));
    if (!m || !MSBDIconTypesAre(method_getTypeEncoding(m), types)) return NO;
    return class_addMethod(c, NSSelectorFromString(sel), imp, method_getTypeEncoding(m));
}
// What every class of ours under SBApplicationIcon overrides: an app icon without an app (-application nil, never "an application icon" for
// SpringBoard's app-only paths: split view drags, shortcuts, uninstall), cached by its own identifier. Never the image methods.
static void MSBDIconThemeAppOverrides(Class c, Class from) {
    MSBDIconAddIf(c, from, @"application", @"@@:", (IMP)MSBDIconNil);
    MSBDIconAddIf(c, from, @"applicationPlaceholder", @"@@:", (IMP)MSBDIconNil);
    MSBDIconAddIf(c, from, @"isApplicationIcon", @"B@:", (IMP)MSBDIconNo);
    MSBDIconAddIf(c, from, @"iconImageCacheIdentifier", @"@@:", (IMP)MSBDIconCacheID);
}
// A theme engine reloads one icon's picture itself (SnowBoard's per-icon menu: -reloadIconImage on the icon it was opened for, no refresh note):
// SpringBoard's reload, then every library of ours told (kMSBDIconThemeReloaded, below), once per turn of the main loop, so the views that draw
// these icons ask again -- live, as an app's own icon changes (1.8.3 item 5).
#define kMSBDIconThemeReloaded "com.besiktasliseba.macstatusbar.icontheme.reloaded"
static void MSBDIconReload(id self, SEL _cmd) {
    Class mine = objc_getClass("MSBDThemableIcon");
    struct objc_super sup = { self, mine ? class_getSuperclass(mine) : class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ pending = NO; notify_post(kMSBDIconThemeReloaded); });
}
static Class MSBDIconThemableClass(void) {
    Class have = objc_getClass("MSBDThemableIcon");
    if (have) return have;
    Class app = objc_getClass("SBApplicationIcon");
    Class k = app ? objc_allocateClassPair(app, "MSBDThemableIcon", 0) : Nil;
    if (!k) return objc_getClass("MSBDThemableIcon");
    MSBDIconThemeAppOverrides(k, app);
    for (NSString *s in @[@"isUninstallSupported", @"canBeAddedToMultiItemDrag", @"canBeAddedToSubfolder", @"isTimedOut", @"isProgressPaused"]) MSBDIconAddIf(k, app, s, @"B@:", (IMP)MSBDIconNo);
    MSBDIconAddIf(k, app, @"badgeNumberOrString", @"@@:", (IMP)MSBDIconNil);
    MSBDIconAddIf(k, app, @"reloadIconImage", @"v@:", (IMP)MSBDIconReload);   // (the picture reloaded by a theme engine: our views told)
    objc_registerClassPair(k);
    return k;
}

// ---- is the path there? -----------------------------------------------------------------------------------------------------------------
// Two steps. The shapes (MSBDIconThemeShapeOK) are runtime metadata only -- classes, methods, type strings, the protocol -- and may be read at
// SpringBoard's start, in a library's constructor (Activity Monitor's class is made there, statusbar/AppLibraryApps.h). The probe (MSBDIconThemeReady)
// makes one of SpringBoard's icons and runs its chain, so it waits for the first picture asked after the start; it uses no UIKit (plain objects
// stand for the pictures: SpringBoard's chain hands back whatever the data source gives).
static int gMSBDIconShape = -1, gMSBDIconReady = -1;
static BOOL MSBDIconThemeShapeOK(void) {
    if (gMSBDIconShape >= 0) return gMSBDIconShape;
    gMSBDIconShape = 0;
    NSMutableArray *why = [NSMutableArray array];
    NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    if (!MSBDIconThemeOS(major)) { DMLog([NSString stringWithFormat:@"[icontheme] off on iPadOS %ld: our items draw their own pictures", (long)major]); return NO; }
    Class leaf = objc_getClass("SBLeafIcon"), app = objc_getClass("SBApplicationIcon"), base = objc_getClass("SBIcon");
    if (!leaf || !app || ![app isSubclassOfClass:leaf]) [why addObject:@"SBApplicationIcon is not an SBLeafIcon"];
    NSDictionary *need = @{ @"initWithLeafIdentifier:applicationBundleID:": @"@@:@@", @"addIconDataSource:": @"v@:@", @"applicationBundleID": @"@@:",
                            @"generateIconImageWithInfo:": MSBDIconImageMethodTypes(), @"unmaskedIconImageWithInfo:": MSBDIconImageMethodTypes() };
    for (NSString *s in need) { Method m = leaf ? class_getInstanceMethod(leaf, NSSelectorFromString(s)) : NULL; if (!m || !MSBDIconTypesAre(method_getTypeEncoding(m), need[s])) [why addObject:s]; }
    Method ii = base ? class_getInstanceMethod(base, @selector(iconImageWithInfo:)) : NULL;
    if (!ii || !MSBDIconTypesAre(method_getTypeEncoding(ii), MSBDIconImageMethodTypes())) [why addObject:@"iconImageWithInfo:"];
    Class src = why.count ? Nil : MSBDIconSourceClass(why);
    Class icl = why.count ? Nil : MSBDIconThemableClass();
    if (!why.count && (!src || !icl)) [why addObject:@"classes not made"];
    if (why.count) { DMLog([NSString stringWithFormat:@"[icontheme] SpringBoard's icon classes are not as read (%@): our items draw their own pictures", [why componentsJoinedByString:@", "]]); return NO; }
    gMSBDIconShape = 1;
    return YES;
}
static id MSBDIconAttachSource(id icon, MSBDIconItem item, MSBDIconDrawer drawer);
static BOOL MSBDIconThemeReady(void) {
    if (gMSBDIconReady >= 0) return gMSBDIconReady;
    if (!MSBDIconThemeShapeOK()) { gMSBDIconReady = 0; return NO; }
    gMSBDIconReady = 0;
    NSMutableArray *why = [NSMutableArray array];
    Class leaf = objc_getClass("SBLeafIcon"), icl = MSBDIconThemableClass();
    // the probe: SpringBoard's own chain (SBLeafIcon's methods, under any engine's hooks of SBApplicationIcon) must hand back our source's objects
    static id probe;   // (kept: nothing of it is ever released while SpringBoard runs)
    NSObject *masked = [NSObject new], *unmasked = [NSObject new];
    NSString *pid = @"com.besiktasliseba.macstatusbar.iconprobe";
    probe = ((id (*)(id, SEL, id, id))objc_msgSend)([icl alloc], @selector(initWithLeafIdentifier:applicationBundleID:), pid, pid);
    MSBDIconAttachSource(probe, MSBDIconItemCount, ^UIImage *(CGSize size, CGFloat scale, CGFloat radius, BOOL m) { return (UIImage *)(m ? masked : unmasked); });
    MSBDIconImageInfo info = { CGSizeMake(60, 60), 2.0, 13.5 };
    id a = nil, b = nil;
    @try {
        a = ((id (*)(id, SEL, MSBDIconImageInfo))class_getMethodImplementation(leaf, @selector(generateIconImageWithInfo:)))(probe, @selector(generateIconImageWithInfo:), info);
        b = ((id (*)(id, SEL, MSBDIconImageInfo))class_getMethodImplementation(leaf, @selector(unmaskedIconImageWithInfo:)))(probe, @selector(unmaskedIconImageWithInfo:), info);
    } @catch (NSException *e) { [why addObject:[NSString stringWithFormat:@"probe threw %@", e.name]]; }
    if (a != masked || b != unmasked) [why addObject:[NSString stringWithFormat:@"probe pictures %@ / %@", a == masked ? @"ok" : (a ? @"other" : @"none"), b == unmasked ? @"ok" : (b ? @"other" : @"none")]];
    if (((id (*)(id, SEL))objc_msgSend)(probe, @selector(application))) [why addObject:@"the probe has an application"];
    if (why.count) { DMLog([NSString stringWithFormat:@"[icontheme] SpringBoard's icon chain did not take our picture (%@): our items draw their own pictures", [why componentsJoinedByString:@", "]]); return NO; }
    NSMutableArray *chain = [NSMutableArray array];
    for (Class c = icl; c && c != [NSObject class]; c = class_getSuperclass(c)) [chain addObject:NSStringFromClass(c)];
    DMLog([NSString stringWithFormat:@"[icontheme] on: our items are app icons of their own (%@)", [chain componentsJoinedByString:@" : "]]);
    gMSBDIconReady = 1;
    return YES;
}

// A data source of ours on an icon of SpringBoard's (Activity Monitor's, or one of ours): the item and its drawer. Returns the source.
static id MSBDIconAttachSource(id icon, MSBDIconItem item, MSBDIconDrawer drawer) {
    Class sc = objc_getClass("MSBDIconPictureSource");
    if (!icon || !sc || !drawer || ![icon respondsToSelector:@selector(addIconDataSource:)]) return nil;
    id src = [sc new];
    objc_setAssociatedObject(src, kMSBDIconKeyItem, @(item), OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(src, kMSBDIconKeyDrawer, [drawer copy], OBJC_ASSOCIATION_COPY);
    ((void (*)(id, SEL, id))objc_msgSend)(icon, @selector(addIconDataSource:), src);
    return src;
}

// ---- the pictures (main thread; the Dock's views -- unused in the status bar's library) -------------------------------------------------------------------------------------------------------------
static MSBDIconDrawer gMSBDIconDrawers[MSBDIconItemCount];
static NSMutableDictionary<NSString *, NSArray *> *gMSBDIconsByID;   // identifier -> @[icon, source]
static NSHashTable *gMSBDIconOurs;                                   // pictures an engine made from ours (weak: its own cache keeps them)
__attribute__((unused)) static void MSBDIconThemeSetDrawer(MSBDIconItem item, MSBDIconDrawer d) { if (item >= 0 && item < MSBDIconItemCount && d && !gMSBDIconDrawers[item]) gMSBDIconDrawers[item] = [d copy]; }
__attribute__((unused)) static NSArray *MSBDIconFor(NSString *ident) {
    MSBDIconItem item = MSBDIconItemForID(ident);
    if (item >= MSBDIconItemCount || !gMSBDIconDrawers[item] || !MSBDIconThemeReady()) return nil;
    if (!gMSBDIconsByID) gMSBDIconsByID = [NSMutableDictionary dictionary];
    NSArray *have = gMSBDIconsByID[ident];
    if (have) return have;
    id icon = ((id (*)(id, SEL, id, id))objc_msgSend)([MSBDIconThemableClass() alloc], @selector(initWithLeafIdentifier:applicationBundleID:), ident, ident);
    id src = MSBDIconAttachSource(icon, item, gMSBDIconDrawers[item]);
    if (!icon || !src) return nil;
    gMSBDIconsByID[ident] = @[icon, src];
    DMLog([NSString stringWithFormat:@"[icontheme] %@: an app icon of its own (%@)", ident, MSBDIconName(item)]);
    return gMSBDIconsByID[ident];
}
// One identifier's picture from SpringBoard's chain (and the engine in it), and whether a theme made it (IconThemeIDs.h MSBDIconPick).
__attribute__((unused)) static UIImage *MSBDIconAsk(NSArray *pair, MSBDIconImageInfo info, BOOL *themed) {
    if (!gMSBDIconOurs) gMSBDIconOurs = [NSHashTable weakObjectsHashTable];
    NSUInteger before = MSBDIconSourceDrew(pair[1]);
    UIImage *img = nil;
    @try { img = ((UIImage *(*)(id, SEL, MSBDIconImageInfo))objc_msgSend)(pair[0], @selector(iconImageWithInfo:), info); } @catch (NSException *e) { img = nil; }
    if (![img isKindOfClass:[UIImage class]]) img = nil;
    BOOL ours = MSBDIconSourceDrew(pair[1]) != before || (img && [gMSBDIconOurs containsObject:img]);
    if (img && ours) [gMSBDIconOurs addObject:img];
    *themed = img && !ours;
    return img;
}
// The picture for an item at a size (points), a scale and SpringBoard's corner for it: the theme's when a theme has one for any of its
// identifiers (in order), else ours as the engine shapes an app's own icon. nil when the path is off: the caller draws its own picture.
__attribute__((unused)) static UIImage *MSBDIconThemePicture(MSBDIconItem item, CGSize size, CGFloat scale, CGFloat radius, BOOL *themedOut) {
    if (themedOut) *themedOut = NO;
    if (![NSThread isMainThread] || !(size.width >= 4.0) || !(size.height >= 4.0) || !MSBDIconThemeReady()) return nil;
    NSArray<NSString *> *ids = MSBDIconLookup(item);
    MSBDIconImageInfo info = { size, scale, radius };
    UIImage *pics[4] = { nil, nil, nil, nil }; BOOL themed[4] = { NO, NO, NO, NO };
    NSUInteger n = 0;
    for (NSString *ident in ids) {
        if (n >= 4) break;
        NSArray *pair = MSBDIconFor(ident);
        if (!pair) return nil;
        pics[n] = MSBDIconAsk(pair, info, &themed[n]);
        if (!pics[n]) return nil;
        n++;
        if (themed[n - 1]) break;   // (the first themed one wins: the rest need not be asked)
    }
    if (!n) return nil;
    NSUInteger k = MSBDIconPick(themed, n);
    if (themedOut) *themedOut = themed[k];
    return pics[k];
}

// ---- when to ask again: an engine's pictures changed ----------------------------------------------------------------------------------------
#define kMSBDIconThemeChanged @"MSBDIconThemeChanged"
static NSUInteger gMSBDIconGeneration = 0;
__attribute__((unused)) static void MSBDIconThemeWatch(void) {
    static int token = 0, reloadToken = 0;
    if (!reloadToken) notify_register_dispatch(kMSBDIconThemeReloaded, &reloadToken, dispatch_get_main_queue(), ^(int t) {
        gMSBDIconGeneration++;
        DMLog([NSString stringWithFormat:@"[icontheme] a theme engine reloaded one of our icons' pictures: the items ask again (%lu)", (unsigned long)gMSBDIconGeneration]);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMSBDIconThemeChanged object:nil];
    });
    if (token) return;
    notify_register_dispatch(kMSBDIconThemeSnowBoardRefreshed, &token, dispatch_get_main_queue(), ^(int t) {
        gMSBDIconGeneration++;
        DMLog([NSString stringWithFormat:@"[icontheme] SnowBoard refreshed its icons: the Dock's items ask again (%lu)", (unsigned long)gMSBDIconGeneration]);
        [[NSNotificationCenter defaultCenter] postNotificationName:kMSBDIconThemeChanged object:nil];
    });
}
