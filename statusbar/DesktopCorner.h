// DesktopCorner.h -- the corners of the desktop's app icons (1.7.9 item 4, KT 2 Nov), included into Desktop.h: Settings > Desktop > App Icon
// Corner Radius (common/DesktopAppCorner.h: the stored fraction, what Settings shows, the reading of a theme's mask -- plain C, Mac-tested).
//  - Never set: the desktop's app icons are as they always were (the app's icon as the Home Screen shows it, an icon theme's included: Finder.h
//    DMFinderIcon). SpringBoard publishes that shape for Settings' slider to start from: an icon theme engine's mask, read from what the engine
//    makes of an opaque square handed to SpringBoard's own app icon chain as an app's own icon (an app icon of our own, common/IconTheme.h: the
//    engine shapes it as every app it has no theme picture for -- SnowBoard: its corner radius, its mask), else iPadOS's own corner for the Home
//    Screen's icon size (SpringBoard's SBIconImageInfo). On iPadOS 18 no app icon of our own runs (common/IconTheme.h: 15-17), and an engine
//    there shapes the pictures SpringBoard asks IconServices for (FrostBoard 0.0.1~beta5: ISIcon's), so the shape is read from the Home Screen's
//    own app icons as SpringBoard draws them; one that shows iPadOS's own mask means no engine shapes them.
//  - Set: the app's own picture before any mask -- SpringBoard's own app icon for that app (-unmaskedIconImageWithInfo:, which an icon theme
//    engine answers with its theme's picture: SnowBoard 1.5.37 hands back the theme's square PNG as it is, 256 px on KT's M1), else the .app's
//    own icon files -- with the user's corner. Where SpringBoard's picture does not show what the Home Screen shows (SnowBoard themes the live
//    Clock apart: SpringBoard's is Apple's), the Home Screen's own picture, masked as it is. A theme's picture with a painted frame (a tile inside
//    a band the engine's mask cuts away: KT's iOSX) is trimmed to its tile (KT 2 Nov): our square shows only as much of the tile as stays inside
//    the tile's own shape at that corner, so neither the band nor its edge ever shows (common/DesktopAppCorner.h MSBDPaintedTileFind /
//    MSBDTileWindow). Only an engine's pictures are read so (where an engine shapes the app icons: the probe says so on 15-17, the Home Screen's
//    own app icons on 18); without an engine, and for the .app's own files, the picture is drawn whole.
// The shape is common/DesktopAppCorner.h's (MSBDDesktopCornerPathCreate): iPadOS's own corner, smoothed into the sides, up to an exact circle --
// KT's SnowBoard mask reads as 0.39 of the side with it, 0.2 to 0.4 px from it at 120 to 240 px.
// A theme engine's refresh (SnowBoard's refreshComplete) reads the shape again and draws the desktop's app icons again, set or not.
#include "../common/DesktopAppCorner.h"
#include "../common/IconTheme.h"   // (the app icon of our own the shape is read with; Activity Monitor's too: #pragma once)

static double gDesktopAppCorner = -1;   // (Settings' corner, a fraction of the side; -1 never set: the Home Screen's shape, as always)
static NSUInteger gDesktopCornerGen;    // (+1 when an icon theme engine refreshed its pictures: everything below is asked again -- and Finder's
                                        //  app icons, Finder.h gFinderAppIconGen)
#if DEBUG
static int gDesktopCornerForce;   // (tests: 1 the .app's own files only, 2 no picture before the mask -- the Home Screen's picture, rounder only)
#endif

// One drawing for every corner: ours, and the model a theme's mask is measured against (the same shape, the same rasteriser). A picture (upright in
// a UIKit context; `from`: the part of it that fills the square, in fractions of its size -- all of it, or a theme's tile) or a colour in a square
// of `side` with the corner, at the context's origin.
static void DMDesktopCornerRender(CGContextRef c, CGFloat side, double fraction, UIImage *picture, CGRect from, CGColorRef fill) {
    if (!c || !(side > 0)) return;
    CGPathRef shape = MSBDDesktopCornerPathCreate(side, fraction);
    CGContextSaveGState(c);
    CGContextAddPath(c, shape);
    CGContextClip(c);
    if (picture && from.size.width > 0 && from.size.height > 0) {
        CGFloat kx = side / from.size.width, ky = side / from.size.height;
        UIGraphicsPushContext(c);
        [picture drawInRect:CGRectMake(-from.origin.x * kx, -from.origin.y * ky, kx, ky)];
        UIGraphicsPopContext();
    } else if (!picture) { CGContextSetFillColorWithColor(c, fill); CGContextFillRect(c, CGRectMake(0, 0, side, side)); }
    CGContextRestoreGState(c);
    CGPathRelease(shape);
}
#define kDMDesktopWhole CGRectMake(0, 0, 1, 1)
static void DMDesktopCornerModel(void *ctx, double fraction, int n, unsigned char *alpha) {
    memset(alpha, 0, (size_t)n * n);
    CGContextRef c = CGBitmapContextCreate(alpha, n, n, 8, n, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!c) return;
    DMDesktopCornerRender(c, n, fraction, nil, kDMDesktopWhole, [UIColor blackColor].CGColor);
    CGContextRelease(c);
}
// A picture's alpha, drawn into n x n.
static BOOL DMDesktopPictureAlpha(UIImage *img, int n, unsigned char *alpha) {
    CGImageRef cg = img.CGImage;
    if (!cg || n < 8) return NO;
    memset(alpha, 0, (size_t)n * n);
    CGContextRef c = CGBitmapContextCreate(alpha, n, n, 8, n, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!c) return NO;
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    CGContextDrawImage(c, CGRectMake(0, 0, n, n), cg);
    CGContextRelease(c);
    return YES;
}

// ---- the Home Screen's shape -------------------------------------------------------------------------------------------------------------------
// The Home Screen's app icon size, scale and corner as SpringBoard lays its icons out (SBIconImageInfo; read on 15.6.1 / 18.5 with this shape):
// page 1's list layout, the list itself, an app icon view of it -- whichever answers first with a sane value.
static BOOL DMDesktopInfoSane(MSBDIconImageInfo i) {
    return i.size.width > 20.0 && i.size.width < 400.0 && fabs(i.size.width - i.size.height) < 1.0 && i.scale >= 1.0 && i.scale <= 4.0
        && isfinite(i.continuousCornerRadius) && i.continuousCornerRadius >= 0.0 && i.continuousCornerRadius <= i.size.width / 2.0;
}
static BOOL DMDesktopAskIconInfo(id obj, MSBDIconImageInfo *out) {
    SEL s = NSSelectorFromString(@"iconImageInfo");
    Method m = obj ? class_getInstanceMethod([obj class], s) : NULL;
    if (!m || !MSBDIconTypesAre(method_getTypeEncoding(m), @"" kMSBDIconImageInfoType "@:")) return NO;
    MSBDIconImageInfo i = ((MSBDIconImageInfo (*)(id, SEL))objc_msgSend)(obj, s);
    if (!DMDesktopInfoSane(i)) return NO;
    *out = i;
    return YES;
}
static NSString *DMDesktopHomeIconInfo(UIView *list, UIView *iconView, CGFloat measured, MSBDIconImageInfo *out) {
    if (DMDesktopAskIconInfo(DMCall(list, @"layout"), out)) return @"the list's layout";
    if (DMDesktopAskIconInfo(list, out)) return @"the list";
    if (DMDesktopAskIconInfo(iconView, out)) return @"an icon view";
    if (!(measured > 20.0)) return nil;
    MSBDIconImageInfo i = { CGSizeMake(measured, measured), [UIScreen mainScreen].scale, MSBDDesktopCornerRadius(MSBD_DESKTOP_CORNER_IPADOS, measured) };
    *out = i;
    return @"the picture's size (iPadOS's usual corner)";
}

// The app icon of our own the shape is read with (common/IconTheme.h's app icon class and data source, 15-17 where the icon theme path is on):
// its own picture is an opaque square -- masked with SpringBoard's corner when SpringBoard asks for the masked one (no engine shapes app icons),
// whole when an engine asks for the unmasked one to shape it itself.
static int gDesktopProbeAsked;      // (bits: 1 the masked picture was asked, 2 the unmasked one)
static BOOL gDesktopProbeEngine;    // (the last answer: an engine's cached picture asks for nothing)
static UIImage *DMDesktopCornerProbe(MSBDIconImageInfo info, BOOL *engine) {
    static id probe, source;
    if (!MSBDIconThemeReady()) return nil;
    if (!probe) {
        NSString *pid = @"com.besiktasliseba.macstatusbar.cornerprobe";
        id icon = ((id (*)(id, SEL, id, id))objc_msgSend)([MSBDIconThemableClass() alloc], @selector(initWithLeafIdentifier:applicationBundleID:), pid, pid);
        source = MSBDIconAttachSource(icon, MSBDIconItemCount, ^UIImage *(CGSize size, CGFloat scale, CGFloat radius, BOOL masked) {
            gDesktopProbeAsked |= masked ? 1 : 2;
            UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
            fmt.scale = scale; fmt.opaque = NO;
            return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
                DMDesktopCornerRender(ctx.CGContext, size.width, masked && size.width > 0 ? radius / size.width : 0.0, nil, kDMDesktopWhole, [UIColor whiteColor].CGColor);
            }];
        });
        if (!icon || !source) { source = nil; return nil; }
        probe = icon;
    }
    gDesktopProbeAsked = 0;
    UIImage *img = nil;
    @try { img = ((UIImage *(*)(id, SEL, MSBDIconImageInfo))objc_msgSend)(probe, @selector(iconImageWithInfo:), info); } @catch (NSException *e) { img = nil; }
    if (![img isKindOfClass:[UIImage class]] || !img.CGImage) return nil;
    if (gDesktopProbeAsked) gDesktopProbeEngine = (gDesktopProbeAsked & 2) != 0;
    *engine = gDesktopProbeEngine;
    return img;
}
// The shape read, its source, and the Home Screen's icon info and theme refresh it was read for (read again when either changes).
static double gDesktopThemeCorner = -1; static BOOL gDesktopThemeCustom; static NSString *gDesktopThemeFrom;
static MSBDIconImageInfo gDesktopThemeInfo; static NSUInteger gDesktopThemeGen = NSUIntegerMax;
static double DMDesktopReadEngineMask(UIImage *pic, double *gapOut) {
    int n = (int)lround(MIN(pic.size.width, pic.size.height) * pic.scale);
    n = MAX(32, MIN(256, n));
    unsigned char *a = calloc((size_t)n * n, 1), *s = calloc((size_t)n * n, 1);
    double f = -1, gap = 1e9;
    if (a && s && DMDesktopPictureAlpha(pic, n, a)) f = MSBDCornerFit(a, n, DMDesktopCornerModel, NULL, s, &gap);
    free(a); free(s);
    if (gapOut) *gapOut = gap;
    return f;
}
// The Home Screen's own app icons as SpringBoard draws them, where no app icon of our own can be read (iPadOS 18): the first app icons of its
// pages in their order (SpringBoard's icon model, the root folder's icons: page 1 can be the desktop's empty page, KT's A12Z), an app's icon
// only (no folder, no widget), each one's picture at the Home Screen's own size and corner (-[SBIcon iconImageWithInfo:]: what the Home Screen
// shows, an engine's mask over its theme's picture included), its mask read as the probe's. The readings go into r (their number returned),
// a line of them into said.
static int DMDesktopReadHomeApps(MSBDIconImageInfo info, MSBDCornerReading *r, int max, NSMutableString *said) {
    id icons = DMCall(DMCall(DMCall(DMCall(DMSBManager("SBIconController"), @"iconManager"), @"iconModel"), @"rootFolder"), @"icons");
    if (![icons isKindOfClass:[NSArray class]]) return 0;
    SEL isApp = @selector(isApplicationIcon), image = @selector(iconImageWithInfo:);
    int n = 0;
    for (id icon in (NSArray *)icons) {
        if (n >= max) break;
        Method ma = class_getInstanceMethod([icon class], isApp), mi = class_getInstanceMethod([icon class], image);
        if (!ma || !MSBDIconTypesAre(method_getTypeEncoding(ma), @"B@:") || !((BOOL (*)(id, SEL))objc_msgSend)(icon, isApp)) continue;
        if (!mi || !MSBDIconTypesAre(method_getTypeEncoding(mi), MSBDIconImageMethodTypes())) continue;
        UIImage *img = nil;
        @try { img = ((UIImage *(*)(id, SEL, MSBDIconImageInfo))objc_msgSend)(icon, image, info); } @catch (NSException *e) { img = nil; }
        if (![img isKindOfClass:[UIImage class]] || !img.CGImage || fabs(img.size.width - img.size.height) > 0.5 || img.size.width < 20.0) continue;
        double gap = 1e9, f = DMDesktopReadEngineMask(img, &gap);
        if (f < 0) continue;
        r[n].fraction = f; r[n].gap = gap; n++;
        [said appendFormat:@"%@%.3f (%.2f px)", n > 1 ? @", " : @"", f, gap];
    }
    return n;
}
static BOOL gDesktopHomeEngine;   // (iPadOS 18: the Home Screen's own app icons show an engine's shape, not iPadOS's -- what the probe tells on 15-17)
static BOOL DMDesktopEngineShapes(void) { return gDesktopProbeEngine || gDesktopHomeEngine; }   // (an engine shapes the app icons: its pictures may have a painted frame)
static void DMDesktopThemeCornerRead(MSBDIconImageInfo home, NSString *infoFrom) {
    if (gDesktopThemeGen == gDesktopCornerGen && gDesktopThemeCorner >= 0 && fabs(gDesktopThemeInfo.size.width - home.size.width) < 0.01
        && fabs(gDesktopThemeInfo.continuousCornerRadius - home.continuousCornerRadius) < 0.01) return;
    gDesktopThemeGen = gDesktopCornerGen; gDesktopThemeInfo = home;
    CFTimeInterval t0 = CACurrentMediaTime();
    double f = home.continuousCornerRadius / home.size.width, gap = 0;
    BOOL custom = NO, engine = NO;
    NSString *from = @"iPadOS's own corner", *read = @", no reading picture (no icon theme path)";
    UIImage *pic = DMDesktopCornerProbe(home, &engine);
    if (pic && engine) {
        double fit = DMDesktopReadEngineMask(pic, &gap);
        if (fit >= 0) { f = fit; custom = MSBDCornerIsCustom(gap); from = custom ? @"an icon theme's own shape (the nearest rounded square)" : @"an icon theme's mask"; }
        else from = @"iPadOS's own corner (the theme's mask could not be read)";
    } else if (!pic) {   // (no app icon of our own -- iPadOS 18 --: the Home Screen's own app icons, as SpringBoard draws them)
        MSBDCornerReading r[7]; NSMutableString *said = [NSMutableString string];
        int n = DMDesktopReadHomeApps(home, r, 7, said);
        MSBDCornerReading m = MSBDCornerMedian(r, n);
        static BOOL toldNone, readOnce;
        if (!n) {   // (no app icon to read yet: what was read before stays -- SpringBoard's corner until then --, read again at the next look)
            gDesktopThemeGen = NSUIntegerMax;
            if (toldNone || readOnce) return;
            toldNone = YES; from = @"iPadOS's own corner (no app icon of the Home Screen read yet)";
        } else {
            readOnce = YES;
            if (MSBDCornerIsSpringBoards(m, f)) from = @"iPadOS's own corner (the Home Screen's app icons show iPadOS's mask)";
            else { f = m.fraction; gap = m.gap; custom = MSBDCornerIsCustom(gap); engine = YES; from = custom ? @"an icon theme's own shape (the nearest rounded square)" : @"an icon theme's mask"; }
            gDesktopHomeEngine = engine;
        }
        read = n ? [NSString stringWithFormat:@", read from %d of the Home Screen's app icons (the median of %@)", n, said] : @", no Home Screen app icon to read";
    }
    gDesktopThemeCorner = f; gDesktopThemeCustom = custom; gDesktopThemeFrom = from;
    static int token = 0;
    if (token || notify_register_check(MSBD_DESKTOP_THEMECORNER_STATE, &token) == NOTIFY_STATUS_OK) notify_set_state(token, MSBDDesktopThemeCornerState(f, custom));
    DMLog([NSString stringWithFormat:@"[desktop] the Home Screen's app icon shape: corner %.4f of the side (%.2f of %.1f pt), %@ -- icon info from %@%@ (%.1f ms)", f, f * home.size.width,
           home.size.width, from, infoFrom, pic ? [NSString stringWithFormat:@", read %@ (outline gap %.2f px)", engine ? @"from the engine's picture" : @"without an engine", gap] : read,
           (CACurrentMediaTime() - t0) * 1000.0]);
}

// ---- the app's picture before any mask --------------------------------------------------------------------------------------------------------
static NSString *DMDesktopAppBundleID(NSString *appPath) {
    static NSCache *ids; if (!ids) ids = [NSCache new];
    id hit = [ids objectForKey:appPath];
    if (hit) return hit == [NSNull null] ? nil : hit;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *bid = [info isKindOfClass:[NSDictionary class]] && [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : nil;
    [ids setObject:bid ?: (id)[NSNull null] forKey:appPath];
    return bid;
}
// The .app's own icon files (its Info.plist's primary icon: CFBundleIcons~ipad / CFBundleIcons, the older CFBundleIconFiles / CFBundleIconFile):
// the largest square picture among the PNG files of its top folder named after them. What iPadOS masks itself.
static UIImage *DMDesktopAppBundleArtwork(NSString *appPath) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
    if (![info isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    void (^take)(id) = ^(id x) { if ([x isKindOfClass:[NSString class]] && [x length]) [names addObject:[x stringByDeletingPathExtension]]; };
    for (NSString *k in @[@"CFBundleIcons~ipad", @"CFBundleIcons"]) {
        NSDictionary *primary = [info[k] isKindOfClass:[NSDictionary class]] ? info[k][@"CFBundlePrimaryIcon"] : nil;
        if (![primary isKindOfClass:[NSDictionary class]]) continue;
        if ([primary[@"CFBundleIconFiles"] isKindOfClass:[NSArray class]]) for (id f in primary[@"CFBundleIconFiles"]) take(f);
        take(primary[@"CFBundleIconName"]);
    }
    if ([info[@"CFBundleIconFiles"] isKindOfClass:[NSArray class]]) for (id f in info[@"CFBundleIconFiles"]) take(f);
    take(info[@"CFBundleIconFile"]);
    if (!names.count) return nil;
    UIImage *best = nil;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:appPath error:nil]) {
        if (![f.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
        BOOL named = NO;
        for (NSString *n in names) if ([f hasPrefix:n]) { named = YES; break; }
        if (!named) continue;
        UIImage *img = [UIImage imageWithContentsOfFile:[appPath stringByAppendingPathComponent:f]];
        if (!img.CGImage || fabs(img.size.width - img.size.height) > 0.5) continue;
        if (!best || img.size.width * img.scale > best.size.width * best.scale) best = img;
    }
    return best;
}
// A theme picture's painted tile (common/DesktopAppCorner.h MSBDPaintedTileFind), read from its pixels at their own size (up to 512 a side).
static MSBDPaintedTile DMDesktopTileOf(UIImage *img) {
    MSBDPaintedTile none = { 0, 0, 0, 1, 1, 0 };
    CGImageRef cg = img.CGImage;
    if (!cg || CGImageGetWidth(cg) != CGImageGetHeight(cg)) return none;
    int n = (int)MIN((size_t)512, CGImageGetWidth(cg));
    if (n < 64) return none;
    unsigned char *px = calloc((size_t)n * n * 4, 1);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = px ? CGBitmapContextCreate(px, n, n, 8, n * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast) : NULL;
    MSBDPaintedTile t = none;
    if (c) {
        CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
        CGContextDrawImage(c, CGRectMake(0, 0, n, n), cg);   // (the picture's top row is the bitmap's first)
        t = MSBDPaintedTileFind(px, n, n * 4);
        CGContextRelease(c);
    }
    CGColorSpaceRelease(cs);
    free(px);
    return t;
}
// Two pictures drawn n x n (premultiplied RGBA): what MSBDPictureDifference compares.
static BOOL DMDesktopPixels(UIImage *img, int n, unsigned char *px) {
    CGImageRef cg = img.CGImage;
    if (!cg) return NO;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, n, n, 8, n * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return NO;
    memset(px, 0, (size_t)n * n * 4);
    CGContextSetInterpolationQuality(c, kCGInterpolationHigh);
    CGContextDrawImage(c, CGRectMake(0, 0, n, n), cg);
    CGContextRelease(c);
    return YES;
}
static double DMDesktopPictureDifference(UIImage *unmasked, UIImage *home) {
    enum { n = 48 };
    unsigned char a[n * n * 4], b[n * n * 4];
    if (!DMDesktopPixels(unmasked, n, a) || !DMDesktopPixels(home, n, b)) return 1.0;
    return MSBDPictureDifference(a, b, n);
}
// SpringBoard's own app icon for the app (the one the Home Screen and the App Library show, an icon theme engine's picture included), before its
// mask; else the .app's own files. nil: neither (the caller then rounds the Home Screen's picture, which can only get rounder). Asked once per app
// and theme refresh, at the largest Icon Size (one picture serves every size; SnowBoard hands back its theme's picture at its own size anyway).
// SpringBoard's picture must show what the Home Screen shows: where it does not (a live icon an engine themes apart, Clock), the Home Screen's
// own picture is the one, as its mask left it.
// tile: where an engine shapes the app icons and this is its picture, the tile painted in it (found or not); for any other picture, none.
static UIImage *DMDesktopAppArtwork(NSString *bid, NSString *appPath, CGFloat scale, NSString **from, MSBDPaintedTile *tile) {
    static NSCache *cache;
    if (!cache) { cache = [NSCache new]; cache.totalCostLimit = 8 << 20; }   // (bytes: a few apps on a desktop are 1 to 2 MB)
    int force = 0;
#if DEBUG
    force = gDesktopCornerForce;
#endif
    NSString *key = [NSString stringWithFormat:@"%@|%@|%.1f|%lu|%d|%d", bid ?: @"", appPath, scale, (unsigned long)gDesktopCornerGen, force, DMDesktopEngineShapes()];
    NSArray *hit = [cache objectForKey:key];
    if (hit) { if (from) *from = hit[1]; if (tile) [hit[2] getValue:tile]; return hit[0] == [NSNull null] ? nil : hit[0]; }
    UIImage *img = nil; NSString *src = @"none";
    if (bid.length && force == 0) {
        id model = DMCall(DMCall(DMSBManager("SBIconController"), @"iconManager"), @"iconModel");
        SEL byID = NSSelectorFromString(@"applicationIconForBundleIdentifier:");
        Method mb = model ? class_getInstanceMethod([model class], byID) : NULL;
        id icon = mb && MSBDIconTypesAre(method_getTypeEncoding(mb), @"@@:@") ? ((id (*)(id, SEL, id))objc_msgSend)(model, byID, bid) : nil;
        SEL um = NSSelectorFromString(@"unmaskedIconImageWithInfo:");
        Method mu = icon ? class_getInstanceMethod([icon class], um) : NULL;
        if (mu && MSBDIconTypesAre(method_getTypeEncoding(mu), MSBDIconImageMethodTypes())) {
            CGFloat side = MSBD_DESKTOP_ICON_MAX;
            MSBDIconImageInfo info = { CGSizeMake(side, side), scale, MSBDDesktopCornerRadius(MSBD_DESKTOP_CORNER_IPADOS, side) };
            id got = nil;
            @try { got = ((id (*)(id, SEL, MSBDIconImageInfo))objc_msgSend)(icon, um, info); } @catch (NSException *e) { got = nil; }
            if ([got isKindOfClass:[UIImage class]] && ((UIImage *)got).CGImage && ((UIImage *)got).size.width >= 4.0) { img = got; src = @"SpringBoard's app icon"; }
        }
    }
    if (img) {   // (what the Home Screen shows -- the desktop's own picture of the app while no corner is set, Finder.h DMFinderIcon)
        DMFinderItem *plain = [DMFinderItem new]; plain.path = appPath; plain.name = appPath.lastPathComponent; plain.dir = YES; plain.package = YES;
        UIImage *home = DMFinderIcon(plain, MSBD_DESKTOP_ICON_MAX);
        double diff = home ? DMDesktopPictureDifference(img, home) : 0;
        if (home && diff >= MSBD_DESKTOP_PICTURE_SAME) {
            DMLog([NSString stringWithFormat:@"[desktop] %@: SpringBoard's picture before the mask is not what the Home Screen shows (%.2f apart): the Home Screen's picture instead", bid, diff]);
            img = home; src = @"the Home Screen's picture";
        }
    }
    MSBDPaintedTile t = { 0, 0, 0, 1, 1, 0 };
    if (img && DMDesktopEngineShapes()) t = DMDesktopTileOf(img);   // (an engine's picture: a theme's tile in it is trimmed to)
    if (!img && force != 2) { img = DMDesktopAppBundleArtwork(appPath); if (img) src = @"the app's own icon files"; }
    NSUInteger cost = img ? (NSUInteger)(img.size.width * img.scale * img.size.height * img.scale * 4.0) : 64;
    [cache setObject:@[img ?: (id)[NSNull null], src, [NSValue valueWithBytes:&t objCType:@encode(MSBDPaintedTile)]] forKey:key cost:cost];
    if (from) *from = src;
    if (tile) *tile = t;
    return img;
}
// The part of a picture our square shows at a corner: its painted tile, as much of it as stays inside the tile's own shape there (1.5 px of the
// picture to spare all round), centred on the tile; the whole picture when it has none.
static CGRect DMDesktopTileWindow(MSBDPaintedTile t, double fraction, CGFloat picturePixels) {
    if (!t.found) return kDMDesktopWhole;
    double side = ((t.x1 - t.x0) + (t.y1 - t.y0)) / 2.0, cx = (t.x0 + t.x1) / 2.0, cy = (t.y0 + t.y1) / 2.0;
    double ws = side * MSBDTileWindow(t.fraction, fraction) - 3.0 / fmax(64.0, picturePixels);
    if (!(ws > 0.2)) return kDMDesktopWhole;
    return CGRectMake(cx - ws / 2.0, cy - ws / 2.0, ws, ws);
}

// ---- the desktop's app icon with the user's corner ---------------------------------------------------------------------------------------------
// An .app item with a bundle identifier, at a side (points) and a corner (a fraction of the side); nil when it is no app (the caller draws it as
// any item). Drawn each time it is asked (a new item, a new side, a new corner, a theme's refresh: well under a millisecond), so nothing is kept
// but the picture the icon shows.
static UIImage *DMDesktopAppCornerIcon(DMFinderItem *it, CGFloat side, double fraction) {
    if (![it.name hasSuffix:@".app"] || !(side >= 4.0) || fraction < 0) return nil;
    NSString *bid = DMDesktopAppBundleID(it.path);
    if (!bid.length) return nil;
    CGFloat scale = [UIScreen mainScreen].scale;
    NSString *from = nil;
    MSBDPaintedTile tile;
    UIImage *base = DMDesktopAppArtwork(bid, it.path, scale, &from, &tile);
    CGRect part = base ? DMDesktopTileWindow(tile, fraction, base.size.width * base.scale) : kDMDesktopWhole;
    if (!base) {   // (no picture before the mask: the Home Screen's picture -- its corner can only get rounder)
        DMFinderItem *plain = [DMFinderItem new]; plain.path = it.path; plain.name = it.name; plain.dir = YES; plain.package = YES;
        base = DMFinderIcon(plain, side);
        static BOOL told; if (!told && base) { told = YES; DMLog([NSString stringWithFormat:@"[desktop] %@: no app picture before its mask -- its corner rounds the Home Screen's picture", bid]); }
    }
    if (!base) return nil;
    DM_FEATURE_MARK("desktop-app-corner");
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scale; fmt.opaque = NO;
    UIImage *pic = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        DMDesktopCornerRender(ctx.CGContext, side, fraction, base, part, NULL);
    }];
    return it.alias ? DMFinderAliasArrow(pic) : pic;
}

// Settings' corner (desktopAppIconCorner, read as Settings writes it): a fraction of the side on a 1 % step; -1 never set.
static double DMDesktopCornerPref(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(MSBD_DESKTOP_CORNER_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL num = v && CFGetTypeID(v) == CFNumberGetTypeID();
    double f = MSBDDesktopCornerInForce(num, num ? [(__bridge NSNumber *)v doubleValue] : 0.0);
    if (v) CFRelease(v);
    return f;
}
