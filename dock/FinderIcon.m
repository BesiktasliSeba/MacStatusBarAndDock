// FinderIcon.m -- Finder in the Dock, like a Mac (2026-09-30). The first item of the Dock: Tweak.x reserves the slot in the Dock's layout numbers
// (before the apps) and calls DMFinderIconAttach with its rectangle; the icon magnifies with the others (DMFinderIcon).
// Finder itself lives in Mac Status Bar (statusbar/Finder.h, another library in SpringBoard): a tap is sent there as a Darwin notification
// (com.besiktasliseba.macstatusbar.finder.dock: open windows come forward, a minimized one comes back, none -> a new window), and Finder
// publishes how many windows it has open (the state of com.besiktasliseba.macstatusbar.finder.windows) for the dot under the icon.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>

#define kFinderDockTap   "com.besiktasliseba.macstatusbar.finder.dock"
#define kFinderDockNew   "com.besiktasliseba.macstatusbar.finder.new"
#define kFinderWindows   "com.besiktasliseba.macstatusbar.finder.windows"
#define kFinderDockRemove "com.besiktasliseba.macstatusbar.finder.remove"

// The Finder face, drawn (no picture file), in the current macOS style: a vivid blue left half and a pale grey-white right half, split by the
// nose line (down from the top, a notch for the nose, then on to the bottom), two thin dark eyes and one thin smile across both halves.
// K-4: the face fills the whole slot, as an app's picture fills its own (it used to be drawn 6% in from every side: 88% of the apps' size, measured
// 76 vs 85 px on the iPad 2 and 74 vs 82 px on the M1). Its corners are cut by the view's layer with SpringBoard's own app icon corner (below).
static UIImage *DMFinderFaceImage(CGSize size) {
    if (size.width < 4 || size.height < 4) return nil;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGFloat w = size.width, h = size.height, s = MIN(w, h), ox = (w - s) / 2.0, oy = (h - s) / 2.0;
        CGRect tile = CGRectMake(ox, oy, s, s);
        CGFloat tx = CGRectGetMinX(tile), ty = CGRectGetMinY(tile), tw = tile.size.width, th = tile.size.height;
        CGPoint (^P)(CGFloat, CGFloat) = ^CGPoint(CGFloat x, CGFloat y) { return CGPointMake(tx + tw * x, ty + th * y); };   // (tile-relative 0..1)
        UIBezierPath *clip = [UIBezierPath bezierPathWithRect:tile];
        CGContextSaveGState(c);
        [clip addClip];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat blue[] = { 0.33, 0.80, 0.99, 1,   0.05, 0.33, 0.86, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, blue, NULL, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, ty), CGPointMake(0, ty + th), 0);
        CGGradientRelease(g);
        // the right half, from the nose line on
        UIBezierPath *right = [UIBezierPath bezierPath];
        [right moveToPoint:P(0.53, 0.0)];
        [right addCurveToPoint:P(0.42, 0.56) controlPoint1:P(0.49, 0.18) controlPoint2:P(0.43, 0.38)];   // (down and in, to the tip of the nose)
        [right addLineToPoint:P(0.50, 0.575)];                                                              // (the notch under the nose)
        [right addCurveToPoint:P(0.585, 1.0) controlPoint1:P(0.50, 0.75) controlPoint2:P(0.54, 0.90)];     // (on down to the bottom edge)
        [right addLineToPoint:P(1.0, 1.0)];
        [right addLineToPoint:P(1.0, 0.0)];
        [right closePath];
        CGFloat pale[] = { 0.97, 0.97, 0.98, 1,   0.80, 0.82, 0.86, 1 };
        g = CGGradientCreateWithColorComponents(cs, pale, NULL, 2);
        CGContextSaveGState(c);
        [right addClip];
        CGContextDrawLinearGradient(c, g, CGPointMake(0, ty), CGPointMake(0, ty + th), 0);
        CGContextRestoreGState(c);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);
        // eyes and smile, thin and dark, the same on both halves
        UIColor *ink = [UIColor colorWithRed:0.09 green:0.10 blue:0.13 alpha:1];
        [ink setFill]; [ink setStroke];
        CGFloat ew = tw * 0.036, eh = th * 0.115;
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(P(0.29, 0).x - ew / 2.0, P(0, 0.235).y, ew, eh) cornerRadius:ew / 2.0] fill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(P(0.73, 0).x - ew / 2.0, P(0, 0.235).y, ew, eh) cornerRadius:ew / 2.0] fill];
        UIBezierPath *smile = [UIBezierPath bezierPath];
        smile.lineWidth = tw * 0.03; smile.lineCapStyle = kCGLineCapRound;
        [smile moveToPoint:P(0.19, 0.615)];
        [smile addQuadCurveToPoint:P(0.81, 0.615) controlPoint:P(0.50, 0.86)];
        [smile stroke];
        CGContextRestoreGState(c);
    }];
}

// SpringBoard's own app icon corner: its continuous corner radius as a share of the icon's width, from the Dock's icon image info (Dock.x sets it at
// every Dock layout; iPad 2 / M1: 17.12 / 76 = 0.225). The Finder picture's corners are cut with it, as continuous corners, like the apps' pictures.
CGFloat gDMIconCornerRatio = 0.2253;

// An icon theme's Finder picture, when an active SnowBoard theme has one: IconBundles/com.apple.finder-large.png (the macOS Finder's id, as icon
// themes name their pictures) or com.besiktasliseba.finder-large.png, checked in SnowBoard's own order (its active themes list), then SnowBoard's
// per-icon overrides for those ids. It is cut with the same corners as the apps' themed pictures. Looked up again only when SnowBoard's settings
// file changes (a theme switched on or off); nil = no theme has one: the drawn face.
static UIImage *DMFinderThemedImage(void) {
    static NSDate *seenDate = nil; static UIImage *cached = nil; static BOOL looked = NO;
    NSString *prefs = @"/var/jb/var/mobile/Library/Preferences/com.spark.snowboardprefs.plist";
    if (![[NSFileManager defaultManager] fileExistsAtPath:prefs]) prefs = @"/var/mobile/Library/Preferences/com.spark.snowboardprefs.plist";
    NSDate *date = [[[NSFileManager defaultManager] attributesOfItemAtPath:prefs error:nil] fileModificationDate];
    if (looked && ((!date && !seenDate) || [date isEqualToDate:seenDate])) return cached;
    looked = YES; seenDate = date; cached = nil;
    NSDictionary *d = date ? [NSDictionary dictionaryWithContentsOfFile:prefs] : nil;
    NSArray *ids = @[@"com.besiktasliseba.finder", @"com.apple.finder"];
    NSArray *themes = [d[@"ActiveMenuItems"] isKindOfClass:[NSArray class]] ? d[@"ActiveMenuItems"] : @[];
    for (NSString *theme in themes) {
        if (![theme isKindOfClass:[NSString class]]) continue;
        // (themes ship the plain name, or only scale variants: -large@2x.png, -large@3x.png)
        for (NSString *ident in ids) for (NSString *suffix in @[@"-large.png", @"-large@3x.png", @"-large@2x.png", @".png", @"@3x.png", @"@2x.png"]) {
            NSString *path = [[theme stringByAppendingPathComponent:@"IconBundles"] stringByAppendingPathComponent:[ident stringByAppendingString:suffix]];
            UIImage *img = [[NSFileManager defaultManager] fileExistsAtPath:path] ? [UIImage imageWithContentsOfFile:path] : nil;
            if (img.size.width >= 8.0) { cached = img; return cached; }
        }
    }
    NSDictionary *overrides = [d[@"IconOverrides"] isKindOfClass:[NSDictionary class]] ? d[@"IconOverrides"] : nil;
    for (NSString *ident in ids) {
        NSString *path = [overrides[ident] isKindOfClass:[NSString class]] ? overrides[ident] : nil;
        UIImage *img = path ? [UIImage imageWithContentsOfFile:path] : nil;
        if (img.size.width >= 8.0) { cached = img; return cached; }
    }
    return nil;
}

@interface DMFinderIconView : UIView <UIPointerInteractionDelegate, UIContextMenuInteractionDelegate>
@property (nonatomic, strong) UIImageView *image;
@property (nonatomic, strong) UIView *dot;
- (void)tapped;
- (void)updateDot;
@end
@implementation DMFinderIconView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.image = [[UIImageView alloc] initWithFrame:self.bounds];
    self.image.accessibilityIgnoresInvertColors = YES;   // (Smart Invert leaves pictures as they are, like Apple's own icons: 1.3.3, audit L-3)
    self.image.contentMode = UIViewContentModeScaleAspectFit;
    self.image.userInteractionEnabled = NO;
    [self addSubview:self.image];
    self.dot = [UIView new];
    self.dot.backgroundColor = [UIColor labelColor];
    self.dot.userInteractionEnabled = NO;
    self.dot.hidden = YES;
    [self addSubview:self.dot];
    self.clipsToBounds = NO;   // (the dot hangs below the picture)
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    [self addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
    // (assistive features, 1.3.7 audit M-3: "Finder, button", used as a tap is -- its menu through the context menu action, as for Apple's icons)
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Finder";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (BOOL)accessibilityActivate { [self tapped]; return YES; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.image.frame = self.bounds;
    // (the corners: SpringBoard's own app icon corner for this size, continuous, cut by the layer -- the face fills the slot, K-4)
    CALayer *l = self.image.layer;
    l.cornerRadius = gDMIconCornerRatio * MIN(self.bounds.size.width, self.bounds.size.height);
    l.cornerCurve = kCACornerCurveContinuous;
    l.masksToBounds = YES;
    UIImage *themed = DMFinderThemedImage();
    if (themed) {
        if (self.image.image != themed) { self.image.contentMode = UIViewContentModeScaleAspectFill; self.image.image = themed; }
    } else if (!self.image.image || self.image.contentMode != UIViewContentModeScaleAspectFit || !CGSizeEqualToSize(self.image.image.size, self.bounds.size)) {
        self.image.contentMode = UIViewContentModeScaleAspectFit;
        self.image.image = DMFinderFaceImage(self.bounds.size);
    }
    [self updateDot];
}
- (void)updateDot {   // (the running dot: Finder has a window open -- Finder publishes the count)
    static int token = 0;
    if (!token) notify_register_check(kFinderWindows, &token);
    uint64_t n = 0; if (token) notify_get_state(token, &n);
    CGFloat d = MAX(4.0, self.bounds.size.width * 0.045);
    extern CGFloat gDMDotGapBelowImage;   // (RunningIndicator.m: where the apps' dots sit below their pictures -- this view is only the picture)
    self.dot.frame = CGRectMake((self.bounds.size.width - d) / 2.0, self.bounds.size.height + gDMDotGapBelowImage, d, d);
    self.dot.layer.cornerRadius = d / 2.0;
    self.dot.hidden = n == 0;
    [self bringSubviewToFront:self.dot];
}
- (void)tapped { notify_post(kFinderDockTap); }
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region {
    return [UIPointerStyle styleWithEffect:[UIPointerLiftEffect effectWithPreview:[[UITargetedPreview alloc] initWithView:self]] shape:nil];
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)p {
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        return [UIMenu menuWithTitle:@"" children:@[
            [UIAction actionWithTitle:@"New Finder Window" image:[UIImage systemImageNamed:@"macwindow.badge.plus"] identifier:nil handler:^(UIAction *a) { notify_post(kFinderDockNew); }],
            [UIAction actionWithTitle:@"Show Finder" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) { notify_post(kFinderDockTap); }],
            // (never removes it: Finder always stays in the Dock, as on a Mac -- Mac Status Bar asks, and offers the Settings switch that hides it)
            [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
                [UIAction actionWithTitle:@"Remove from Dock" image:[UIImage systemImageNamed:@"minus.circle"] identifier:nil handler:^(UIAction *a) { notify_post(kFinderDockRemove); }]]],
        ]];
    }];
}
@end

// ---- called from Tweak.x ----
static const void *kFinderIconKey = &kFinderIconKey;
void DMFinderIconAttach(UIView *platter, CGRect slot, BOOL show) {
    DMFinderIconView *icon = objc_getAssociatedObject(platter, kFinderIconKey);
    if (!show || slot.size.width < 8.0) { icon.hidden = YES; return; }
    if (!icon) {
        icon = [[DMFinderIconView alloc] initWithFrame:CGRectMake(0, 0, slot.size.width, slot.size.height)];
        objc_setAssociatedObject(platter, kFinderIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [platter addSubview:icon];
        static int token = 0;   // (the dot follows Finder's window count as it changes)
        __weak DMFinderIconView *wi = icon;
        if (!token) notify_register_dispatch(kFinderWindows, &token, dispatch_get_main_queue(), ^(int t) { [wi updateDot]; });
    }
    icon.hidden = NO;
    icon.transform = CGAffineTransformIdentity;   // (hover magnification re-applies its own)
    icon.bounds = CGRectMake(0, 0, slot.size.width, slot.size.height);
    icon.center = CGPointMake(CGRectGetMidX(slot), CGRectGetMidY(slot));
    [icon setNeedsLayout];
    [platter bringSubviewToFront:icon];
}
UIView *DMFinderIcon(UIView *platter) {
    DMFinderIconView *icon = objc_getAssociatedObject(platter, kFinderIconKey);
    return (icon && !icon.hidden) ? icon : nil;
}
