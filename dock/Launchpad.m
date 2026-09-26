// Launchpad.m -- makes the Dock's App Library icon look like macOS's Launchpad.
//
// The App Library icon in the Dock is an SBIconView for an SBHLibraryPodIndicatorIcon (the accessory icon at the right end).
// Rather than replacing the icon (which would lose its tap, drop and pointer behaviour), a Launchpad picture is laid over
// its image view: a silver rounded square with a grid of colourful app tiles, drawn in code so it is sharp at any size.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "DMLog.h"

static const void *kOverlayKey = &kOverlayKey;

static UIColor *DMRGB(CGFloat r, CGFloat g, CGFloat b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0]; }

// Silver gradient tile with a 3 x 3 grid of colourful app tiles, like the Big Sur-era Launchpad icon.
static UIImage *DMLaunchpadImage(CGSize size) {
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromCGSize(size);
    if (cache[key]) return cache[key];
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat w = size.width, h = size.height;
        CGContextRef c = ctx.CGContext;
        CGRect full = CGRectMake(0, 0, w, h);
        UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:full cornerRadius:w * 0.2237];
        CGContextSaveGState(c);
        [shape addClip];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = { 0.93, 0.94, 0.95, 1.0,   0.66, 0.68, 0.72, 1.0 };   // light silver at the top, darker at the bottom
        CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
        CGContextDrawLinearGradient(c, grad, CGPointMake(0, 0), CGPointMake(0, h), 0);
        CGGradientRelease(grad); CGColorSpaceRelease(space);
        CGContextRestoreGState(c);

        NSArray<UIColor *> *colors = @[ DMRGB(255, 95, 87), DMRGB(254, 188, 46), DMRGB(40, 200, 64),
                                        DMRGB(10, 132, 255), DMRGB(191, 90, 242), DMRGB(255, 159, 10),
                                        DMRGB(90, 200, 250), DMRGB(255, 55, 95), DMRGB(120, 122, 130) ];
        CGFloat tile = w * 0.205, gap = w * 0.055;
        CGFloat total = 3 * tile + 2 * gap;
        CGFloat x0 = (w - total) / 2.0, y0 = (h - total) / 2.0;
        for (int row = 0; row < 3; row++) {
            for (int col = 0; col < 3; col++) {
                CGRect r = CGRectMake(x0 + col * (tile + gap), y0 + row * (tile + gap), tile, tile);
                UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:tile * 0.27];
                CGContextSaveGState(c);
                CGContextSetShadowWithColor(c, CGSizeMake(0, w * 0.008), w * 0.02, [UIColor colorWithWhite:0.0 alpha:0.22].CGColor);
                [colors[row * 3 + col] setFill];
                [p fill];
                CGContextRestoreGState(c);
            }
        }
        // a thin inner edge so the tile reads against a dark Dock
        [[UIColor colorWithWhite:1.0 alpha:0.35] setStroke];
        UIBezierPath *edge = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(full, 0.5, 0.5) cornerRadius:w * 0.2237];
        edge.lineWidth = 1.0;
        [edge stroke];
    }];
    cache[key] = img;
    return img;
}

// The classic round Launchpad (the gray one from OS X Yosemite to Mojave): a gray disc with a light rim and a flat charcoal
// rocket flying up and to the right. The rocket, its porthole and its flame were traced from a picture of that icon and are
// stored as outlines in a unit circle (-1...1 in both directions, y down), so they draw sharply at any size. The colours were
// measured from the same picture.
static const double kRocketBody[] = { -0.0725, 0.7292, -0.0545, 0.7157, 0.0086, 0.6354, 0.0677, 0.5382, 0.0857, 0.5000, 0.1075, 0.4479, 0.1265, 0.3854, 0.1441, 0.3056, 0.1517, 0.2222, 0.1559, 0.2083, 0.2704, 0.0972, 0.3173, 0.0415, 0.3878, -0.0565, 0.4615, -0.1909, 0.5128, -0.3183, 0.5407, -0.4167, 0.5661, -0.5556, 0.5659, -0.6215, 0.5597, -0.6354, 0.5000, -0.6389, 0.4744, -0.6300, 0.4295, -0.6262, 0.4071, -0.6158, 0.2937, -0.5833, 0.2660, -0.5668, 0.2436, -0.5599, 0.2019, -0.5404, 0.1912, -0.5312, 0.1282, -0.4977, 0.0417, -0.4380, -0.0032, -0.4026, -0.0850, -0.3229, -0.1328, -0.2674, -0.1482, -0.2431, -0.1955, -0.1868, -0.2083, -0.1820, -0.2628, -0.1807, -0.2821, -0.1750, -0.3205, -0.1699, -0.4355, -0.1250, -0.5128, -0.0838, -0.5929, -0.0270, -0.6797, 0.0590, -0.6795, 0.0739, -0.6667, 0.0854, -0.5737, 0.0611, -0.5353, 0.0558, -0.4904, 0.0545, -0.4455, 0.0562, -0.3910, 0.0650, -0.3429, 0.0837, -0.3367, 0.0938, -0.3368, 0.1076, -0.3528, 0.1701, -0.3739, 0.2153, -0.3724, 0.2257, -0.3642, 0.2396, -0.3187, 0.2743, -0.2853, 0.3089, -0.2534, 0.3507, -0.2320, 0.3854, -0.2212, 0.3947, -0.2083, 0.3963, -0.1795, 0.3912, -0.1026, 0.3635, -0.0929, 0.3665, -0.0876, 0.3750, -0.0780, 0.4028, -0.0697, 0.4757, -0.0698, 0.5451, -0.0757, 0.6042, -0.0907, 0.6562, -0.1001, 0.7049, -0.0974, 0.7153, -0.0897, 0.7265, -0.0801, 0.7304, -0.0725, 0.7292 };
static const int kRocketBodyCount = 77;
static const double kRocketWindow[] = { 0.2276, -0.1180, 0.2051, -0.1158, 0.1699, -0.1182, 0.1378, -0.1336, 0.1186, -0.1472, 0.1019, -0.1667, 0.0882, -0.1875, 0.0822, -0.2049, 0.0825, -0.2292, 0.0903, -0.2639, 0.0974, -0.2812, 0.1128, -0.3056, 0.1449, -0.3368, 0.1827, -0.3519, 0.2019, -0.3538, 0.2212, -0.3513, 0.2596, -0.3368, 0.2917, -0.3068, 0.3024, -0.2882, 0.3182, -0.2708, 0.3249, -0.2500, 0.3263, -0.2326, 0.3225, -0.2118, 0.3002, -0.1667, 0.2660, -0.1332, 0.2468, -0.1220, 0.2276, -0.1180 };
static const int kRocketWindowCount = 27;
static const double kRocketFlame[] = { -0.5440, 0.6146, -0.4744, 0.6028, -0.4006, 0.5670, -0.3509, 0.5278, -0.3216, 0.4931, -0.2929, 0.4479, -0.2870, 0.4201, -0.2917, 0.4099, -0.3013, 0.4059, -0.3173, 0.4070, -0.3365, 0.4203, -0.3590, 0.4222, -0.3814, 0.4326, -0.4006, 0.4327, -0.4103, 0.4273, -0.4125, 0.4132, -0.4100, 0.3785, -0.3882, 0.3090, -0.3899, 0.2951, -0.3974, 0.2862, -0.4295, 0.2995, -0.4487, 0.3209, -0.4743, 0.3403, -0.5050, 0.3819, -0.5151, 0.4062, -0.5335, 0.4375, -0.5502, 0.4757, -0.5545, 0.4935, -0.5673, 0.5086, -0.5794, 0.5694, -0.5790, 0.5833, -0.5720, 0.6007, -0.5641, 0.6110, -0.5440, 0.6146 };
static const int kRocketFlameCount = 34;

static void DMAddOutline(UIBezierPath *path, const double *pts, int count, CGPoint centre, CGFloat radius) {
    for (int i = 0; i < count; i++) {
        CGPoint p = CGPointMake(centre.x + pts[2 * i] * radius, centre.y + pts[2 * i + 1] * radius);
        if (i == 0) [path moveToPoint:p]; else [path addLineToPoint:p];
    }
    [path closePath];
}

static UIImage *DMLaunchpadRocketImage(CGSize size) {
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = NSStringFromCGSize(size);
    if (cache[key]) return cache[key];
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat D = MIN(size.width, size.height);
        CGFloat R = D / 2.0;
        CGPoint centre = CGPointMake(size.width / 2.0, size.height / 2.0);
        CGContextRef c = ctx.CGContext;
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

        // light rim: nearly white at the top, light gray at the bottom
        CGRect outer = CGRectMake(centre.x - R, centre.y - R, D, D);
        CGContextSaveGState(c);
        [[UIBezierPath bezierPathWithOvalInRect:outer] addClip];
        CGFloat rim[8] = { 0.94, 0.98, 1.0, 1.0,   0.59, 0.59, 0.59, 1.0 };
        CGGradientRef rimGrad = CGGradientCreateWithColorComponents(space, rim, NULL, 2);
        CGContextDrawLinearGradient(c, rimGrad, CGPointMake(0, outer.origin.y), CGPointMake(0, CGRectGetMaxY(outer)), 0);
        CGGradientRelease(rimGrad);
        CGContextRestoreGState(c);

        // the gray disc: pale blue-gray at the top, neutral gray at the bottom
        CGRect inner = CGRectInset(outer, D * 0.034, D * 0.034);
        CGContextSaveGState(c);
        [[UIBezierPath bezierPathWithOvalInRect:inner] addClip];
        CGFloat disc[12] = { 0.82, 0.90, 0.92, 1.0,   0.64, 0.68, 0.69, 1.0,   0.47, 0.47, 0.47, 1.0 };
        CGFloat locs[3] = { 0.0, 0.5, 1.0 };
        CGGradientRef discGrad = CGGradientCreateWithColorComponents(space, disc, locs, 3);
        CGContextDrawLinearGradient(c, discGrad, CGPointMake(0, inner.origin.y), CGPointMake(0, CGRectGetMaxY(inner)), 0);
        CGGradientRelease(discGrad);
        CGContextRestoreGState(c);

        // the rocket (body with the porthole cut out) and its flame, charcoal with a slight fade downward
        UIBezierPath *rocket = [UIBezierPath bezierPath];
        rocket.usesEvenOddFillRule = YES;
        DMAddOutline(rocket, kRocketBody, kRocketBodyCount, centre, R);
        DMAddOutline(rocket, kRocketWindow, kRocketWindowCount, centre, R);
        UIBezierPath *flame = [UIBezierPath bezierPath];
        DMAddOutline(flame, kRocketFlame, kRocketFlameCount, centre, R);
        CGFloat ink[8] = { 0.30, 0.33, 0.35, 1.0,   0.21, 0.21, 0.22, 1.0 };
        CGGradientRef inkGrad = CGGradientCreateWithColorComponents(space, ink, NULL, 2);
        for (UIBezierPath *shape in @[rocket, flame]) {
            CGContextSaveGState(c);
            [shape addClip];
            CGContextDrawLinearGradient(c, inkGrad, CGPointMake(0, centre.y - R * 0.7), CGPointMake(0, centre.y + R * 0.7), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
            CGContextRestoreGState(c);
        }
        CGGradientRelease(inkGrad);
        CGColorSpaceRelease(space);
    }];
    cache[key] = img;
    return img;
}

static UIView *DMIconImageView(UIView *iconView) {
    SEL s = NSSelectorFromString(@"iconImageView");
    if ([iconView respondsToSelector:s]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(iconView, s);
        if ([v isKindOfClass:[UIView class]]) return v;
    }
    @try {
        id v = [iconView valueForKey:@"_iconImageView"];
        if ([v isKindOfClass:[UIView class]]) return v;
    } @catch (NSException *e) {}
    // The App Library icon has no ordinary image view: its picture (the mini app grid) is the view of a custom controller.
    Ivar iv = class_getInstanceVariable([iconView class], "_customIconImageViewController");
    id controller = iv ? object_getIvar(iconView, iv) : nil;
    if ([controller isKindOfClass:[UIViewController class]] && [(UIViewController *)controller isViewLoaded]) return [(UIViewController *)controller view];
    for (UIView *v in iconView.subviews) if ([NSStringFromClass([v class]) containsString:@"IconImageView"]) return v;
    return nil;
}

static const void *kSavedShapeKey = &kSavedShapeKey;

// Called from -[SBIconView layoutSubviews]: only the App Library indicator icon is touched. `classic` = the round rocket
// icon, otherwise the silver grid tile. The round one also clips the original (square) picture underneath to a circle.
void DMLaunchpadRefresh(UIView *iconView, BOOL enabled, BOOL classic) {
    SEL iconSel = NSSelectorFromString(@"icon");
    if (![iconView respondsToSelector:iconSel]) return;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, iconSel);
    if (![NSStringFromClass([icon class]) isEqualToString:@"SBHLibraryPodIndicatorIcon"]) return;
    UIView *imageView = DMIconImageView(iconView);
    if (!imageView) return;
    UIImageView *overlay = objc_getAssociatedObject(imageView, kOverlayKey);

    // remember how the picture was clipped before we touched it, so turning the feature off puts it back
    NSArray *saved = objc_getAssociatedObject(imageView, kSavedShapeKey);
    if (!saved) {
        saved = @[@(imageView.layer.cornerRadius), @(imageView.layer.masksToBounds), imageView.layer.cornerCurve];
        objc_setAssociatedObject(imageView, kSavedShapeKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!enabled) {
        if (overlay) { [overlay removeFromSuperview]; objc_setAssociatedObject(imageView, kOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        imageView.layer.cornerRadius = [saved[0] doubleValue]; imageView.layer.masksToBounds = [saved[1] boolValue]; imageView.layer.cornerCurve = saved[2];
        return;
    }
    CGRect bounds = imageView.bounds;
    if (bounds.size.width < 8.0) return;
    if (classic) {
        imageView.layer.cornerRadius = bounds.size.width / 2.0; imageView.layer.masksToBounds = YES; imageView.layer.cornerCurve = kCACornerCurveCircular;
    } else {
        imageView.layer.cornerRadius = [saved[0] doubleValue]; imageView.layer.masksToBounds = [saved[1] boolValue]; imageView.layer.cornerCurve = saved[2];
    }
    if (!overlay) {
        overlay = [[UIImageView alloc] initWithFrame:bounds];
        overlay.userInteractionEnabled = NO;
        overlay.clipsToBounds = YES;
        objc_setAssociatedObject(imageView, kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [imageView addSubview:overlay];
        DMLog([NSString stringWithFormat:@"[launchpad] overlay added on %@ bounds %@ (%@)", NSStringFromClass([imageView class]), NSStringFromCGRect(bounds), classic ? @"classic" : @"grid"]);
    }
    overlay.frame = bounds;
    overlay.layer.cornerCurve = classic ? kCACornerCurveCircular : kCACornerCurveContinuous;
    overlay.layer.cornerRadius = classic ? bounds.size.width / 2.0 : bounds.size.width * 0.2237;
    NSNumber *shown = objc_getAssociatedObject(overlay, kSavedShapeKey);   // which style the current image is
    if (!overlay.image || !CGSizeEqualToSize(overlay.image.size, bounds.size) || shown.boolValue != classic) {
        overlay.image = classic ? DMLaunchpadRocketImage(bounds.size) : DMLaunchpadImage(bounds.size);
        objc_setAssociatedObject(overlay, kSavedShapeKey, @(classic), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != imageView) [imageView addSubview:overlay];
    [imageView bringSubviewToFront:overlay];
}
