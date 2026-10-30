// TrashIcon.m -- the Trash at the Dock's right end, like a Mac (1.7.0; Settings > Dock > Show Trash in Dock, off by default). Dock.x makes room
// for it after the Downloads stack (the Dock's end, after the second divider) and calls DMTrashAttach with its slot; it magnifies with the others.
// Finder owns the Trash (Mac Status Bar's statusbar/DockTrash.h, another library in SpringBoard): it publishes how many items the Trash holds
// (kMSBDTrashStateName: the empty or the full bin), a tap or Open shows the Trash in a Finder window, and Empty Trash is Finder's own question and
// erase. Finder's drags (a Finder window's items, the desktop's, the Downloads stack's) find this view by its class, as they find the Downloads
// stack: -dm_setDropHover: lights it while a drag is over it, -dm_setEject: shows the Eject sign while drives are dragged, and the drop itself is
// Finder's (Move to Trash, or the drives ejected). An app dragged off the Dock onto it (SpringBoard's own icon drag) leaves the Dock: a drop
// interaction here, the app goes to the Home Screen as Remove from Dock in its menu does (Dock.x).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#import "DMLog.h"
#import "../common/DockTrash.h"
#import "../common/ReduceMotion.h"
#import "../common/MacPointerActive.h"   // (the Mac pointer: no lift under it, as the Dock's other icons)
static BOOL DMTrashIconLift(void) { return MSBDIPadPointerEffects(); }
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

@interface UIWindow (DMPrivateTrash)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

// ---- the pictures -------------------------------------------------------------------------------------------------------------------------
// The bin as macOS draws it since Big Sur: a frosted grey mesh can, a little narrower at the bottom, its opening seen from slightly above; full,
// crumpled paper shows above the rim. The Eject sign (a drag of drives) is the triangle over the bar, in the same metal grey. Drawn in code at
// the Dock's own size and the screen's scale (crisp at 2x and 3x, like the Finder face and the Downloads folder); a drag over it darkens it.
typedef NS_ENUM(int, DMTrashLook) { DMTrashLookEmpty = 0, DMTrashLookFull = 1, DMTrashLookEject = 2 };
static UIColor *DMTGray(CGFloat w, CGFloat a) { return [UIColor colorWithWhite:w alpha:a]; }
static void DMTrashLinearFill(CGContextRef c, CGPathRef clip, CGPoint from, CGPoint to, const CGFloat *rgba, const CGFloat *locs, size_t n) {
    CGContextSaveGState(c);
    CGContextAddPath(c, clip); CGContextClip(c);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, rgba, locs, n);
    CGContextDrawLinearGradient(c, g, from, to, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    CGContextRestoreGState(c);
}
// the can's outline: the rim's ellipse at the top, the sides narrowing to a rounded bottom (s: the square's side, ox/oy its origin)
static UIBezierPath *DMTrashBodyPath(CGFloat s, CGFloat ox, CGFloat oy, CGFloat topY, CGFloat topHalf, CGFloat botY, CGFloat botHalf, CGFloat bend) {
    CGFloat cx = ox + s * 0.5;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(cx - topHalf, topY)];
    [p addLineToPoint:CGPointMake(cx - botHalf, botY - bend * 1.2)];
    [p addQuadCurveToPoint:CGPointMake(cx - botHalf + bend * 1.4, botY) controlPoint:CGPointMake(cx - botHalf + bend * 0.1, botY - bend * 0.05)];
    [p addQuadCurveToPoint:CGPointMake(cx + botHalf - bend * 1.4, botY) controlPoint:CGPointMake(cx, botY + bend * 0.9)];
    [p addQuadCurveToPoint:CGPointMake(cx + botHalf, botY - bend * 1.2) controlPoint:CGPointMake(cx + botHalf - bend * 0.1, botY - bend * 0.05)];
    [p addLineToPoint:CGPointMake(cx + topHalf, topY)];
    [p closePath];
    return p;
}
static void DMTrashDrawBin(CGContextRef c, CGFloat s, CGFloat ox, CGFloat oy, BOOL full) {
    CGFloat cx = ox + s * 0.5;
    CGFloat topY = oy + s * 0.150, topHalf = s * 0.365, rimRY = s * 0.066;   // (as tall as the other icons' pictures: the rim near the top, the bottom near the end)
    CGFloat botY = oy + s * 0.965, botHalf = s * 0.285, bend = s * 0.035;
    UIBezierPath *body = DMTrashBodyPath(s, ox, oy, topY, topHalf, botY, botHalf, bend);
    // a soft shadow under the can, so it stands on a light Dock too
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, s * 0.012), s * 0.035, DMTGray(0.0, 0.28).CGColor);
    [DMTGray(0.80, 1.0) setFill]; [body fill];
    CGContextRestoreGState(c);
    // the frosted body: darker at the sides, light in the middle (a cylinder), a touch darker towards the bottom
    const CGFloat side[] = { 0.62, 0.64, 0.68, 1,   0.86, 0.87, 0.89, 1,   0.95, 0.95, 0.96, 1,   0.84, 0.85, 0.87, 1,   0.58, 0.60, 0.64, 1 };
    const CGFloat sideLocs[] = { 0.0, 0.25, 0.48, 0.74, 1.0 };
    DMTrashLinearFill(c, body.CGPath, CGPointMake(cx - topHalf, 0), CGPointMake(cx + topHalf, 0), side, sideLocs, 5);
    const CGFloat shade[] = { 1, 1, 1, 0.0,   0.2, 0.22, 0.26, 0.20 };
    const CGFloat shadeLocs[] = { 0.0, 1.0 };
    DMTrashLinearFill(c, body.CGPath, CGPointMake(0, topY), CGPointMake(0, botY), shade, shadeLocs, 2);
    // the mesh: ribs from the rim to the bottom, following the taper, and faint rings around the can
    CGContextSaveGState(c);
    CGContextAddPath(c, body.CGPath); CGContextClip(c);
    const int ribs = 9;
    for (int i = 1; i < ribs; i++) {
        CGFloat t = (CGFloat)i / ribs, a = 0.10 + 0.16 * (1.0 - fabs(t - 0.5) * 2.0);
        CGFloat xt = cx - topHalf + 2 * topHalf * t, xb = cx - botHalf + 2 * botHalf * t;
        UIBezierPath *rib = [UIBezierPath bezierPath];
        [rib moveToPoint:CGPointMake(xt, topY + rimRY * 0.6)]; [rib addLineToPoint:CGPointMake(xb, botY - bend * 0.4)];
        rib.lineWidth = MAX(0.5, s * 0.010);
        [DMTGray(0.32, a) setStroke]; [rib stroke];
        UIBezierPath *hl = [UIBezierPath bezierPath];   // (each rib's lit edge)
        [hl moveToPoint:CGPointMake(xt + s * 0.009, topY + rimRY * 0.6)]; [hl addLineToPoint:CGPointMake(xb + s * 0.008, botY - bend * 0.4)];
        hl.lineWidth = MAX(0.4, s * 0.006);
        [DMTGray(1.0, 0.45) setStroke]; [hl stroke];
    }
    for (int k = 1; k <= 5; k++) {
        CGFloat t = k / 6.0, y = topY + (botY - topY) * t, half = topHalf + (botHalf - topHalf) * t;
        UIBezierPath *ring = [UIBezierPath bezierPath];
        [ring moveToPoint:CGPointMake(cx - half, y)];
        [ring addQuadCurveToPoint:CGPointMake(cx + half, y) controlPoint:CGPointMake(cx, y + rimRY * 1.3)];
        ring.lineWidth = MAX(0.4, s * 0.006);
        [DMTGray(0.35, 0.12) setStroke]; [ring stroke];
    }
    CGContextRestoreGState(c);
    // the opening, seen from slightly above: the dark inside, then (full) the paper, then the rim's front edge over it
    CGRect rim = CGRectMake(cx - topHalf, topY - rimRY, 2 * topHalf, 2 * rimRY);
    UIBezierPath *opening = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(rim, s * 0.018, s * 0.012)];
    const CGFloat inside[] = { 0.30, 0.32, 0.36, 1,   0.52, 0.54, 0.58, 1 };
    const CGFloat insideLocs[] = { 0.0, 1.0 };
    DMTrashLinearFill(c, opening.CGPath, CGPointMake(0, CGRectGetMinY(rim)), CGPointMake(0, CGRectGetMaxY(rim)), inside, insideLocs, 2);
    if (full) {
        // crumpled sheets rising out of the can: three overlapping white blobs with soft folds
        CGContextSaveGState(c);
        UIBezierPath *mouth = [UIBezierPath bezierPathWithRect:CGRectMake(ox, oy, s, topY - oy + rimRY * 0.15)];
        [mouth appendPath:opening];   // (above the rim's middle, and inside the opening: never in front of the can's body)
        mouth.usesEvenOddFillRule = NO;
        [mouth addClip];
        struct { CGFloat x, y, w, h, tilt; } sheets[] = {   // (x from the middle, y from the rim's middle, as shares of the side)
            { -0.23, -0.125, 0.33, 0.22, -0.30 }, { 0.05, -0.135, 0.34, 0.24, 0.25 }, { -0.08, -0.090, 0.31, 0.20, 0.05 },
        };
        for (int i = 0; i < 3; i++) {
            CGFloat bx = cx + s * sheets[i].x, by = topY + s * sheets[i].y, bw = s * sheets[i].w, bh = s * sheets[i].h;
            UIBezierPath *p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(bx, by + bh * 0.55)];
            [p addCurveToPoint:CGPointMake(bx + bw * 0.45, by) controlPoint1:CGPointMake(bx - bw * 0.05, by + bh * 0.15) controlPoint2:CGPointMake(bx + bw * 0.18, by - bh * 0.06)];
            [p addCurveToPoint:CGPointMake(bx + bw, by + bh * 0.42) controlPoint1:CGPointMake(bx + bw * 0.72, by + bh * 0.04) controlPoint2:CGPointMake(bx + bw * 1.04, by + bh * 0.12)];
            [p addCurveToPoint:CGPointMake(bx + bw * 0.55, by + bh) controlPoint1:CGPointMake(bx + bw * 0.98, by + bh * 0.78) controlPoint2:CGPointMake(bx + bw * 0.80, by + bh * 1.02)];
            [p addCurveToPoint:CGPointMake(bx, by + bh * 0.55) controlPoint1:CGPointMake(bx + bw * 0.25, by + bh * 1.0) controlPoint2:CGPointMake(bx + bw * 0.02, by + bh * 0.86)];
            [p closePath];
            CGAffineTransform t = CGAffineTransformMakeTranslation(bx + bw / 2.0, by + bh / 2.0);
            t = CGAffineTransformRotate(t, sheets[i].tilt); t = CGAffineTransformTranslate(t, -(bx + bw / 2.0), -(by + bh / 2.0));
            [p applyTransform:t];
            CGContextSaveGState(c);
            CGContextSetShadowWithColor(c, CGSizeMake(0, s * 0.006), s * 0.012, DMTGray(0.0, 0.25).CGColor);
            [DMTGray(0.985, 1.0) setFill]; [p fill];
            CGContextRestoreGState(c);
            const CGFloat paper[] = { 1, 1, 1, 1,   0.80, 0.81, 0.84, 1 };
            const CGFloat paperLocs[] = { 0.0, 1.0 };
            DMTrashLinearFill(c, p.CGPath, CGPointMake(bx, by), CGPointMake(bx + bw * 0.6, by + bh), paper, paperLocs, 2);
            UIBezierPath *fold = [UIBezierPath bezierPath];   // (a crease or two)
            [fold moveToPoint:CGPointMake(bx + bw * 0.22, by + bh * 0.35)];
            [fold addQuadCurveToPoint:CGPointMake(bx + bw * 0.70, by + bh * 0.62) controlPoint:CGPointMake(bx + bw * 0.52, by + bh * 0.28)];
            [fold moveToPoint:CGPointMake(bx + bw * 0.50, by + bh * 0.12)];
            [fold addQuadCurveToPoint:CGPointMake(bx + bw * 0.42, by + bh * 0.78) controlPoint:CGPointMake(bx + bw * 0.62, by + bh * 0.45)];
            [fold applyTransform:t];
            fold.lineWidth = MAX(0.4, s * 0.008);
            [DMTGray(0.62, 0.55) setStroke]; [fold stroke];
        }
        CGContextRestoreGState(c);
    }
    // the rim: a light band around the opening with a thin darker outer edge, its front half drawn last (in front of any paper)
    UIBezierPath *outer = [UIBezierPath bezierPathWithOvalInRect:rim];
    UIBezierPath *band = [UIBezierPath bezierPathWithOvalInRect:rim];
    [band appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(rim, s * 0.018, s * 0.012)]];
    band.usesEvenOddFillRule = YES;
    const CGFloat rimc[] = { 0.98, 0.98, 0.99, 1,   0.80, 0.81, 0.84, 1,   0.97, 0.97, 0.98, 1 };
    const CGFloat rimLocs[] = { 0.0, 0.5, 1.0 };
    CGContextSaveGState(c);
    [band addClip];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, rimc, rimLocs, 3);
    CGContextDrawLinearGradient(c, g, CGPointMake(CGRectGetMinX(rim), 0), CGPointMake(CGRectGetMaxX(rim), 0), 0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    CGContextRestoreGState(c);
    outer.lineWidth = MAX(0.5, s * 0.008);
    [DMTGray(0.40, 0.55) setStroke]; [outer stroke];
    // the can's own outline, faint, so the frosted body reads on a light Dock
    body.lineWidth = MAX(0.5, s * 0.008);
    [DMTGray(0.35, 0.40) setStroke]; [body stroke];
}
static void DMTrashDrawEject(CGContextRef c, CGFloat s, CGFloat ox, CGFloat oy) {
    CGFloat cx = ox + s * 0.5;
    UIBezierPath *tri = [UIBezierPath bezierPath];
    CGFloat ty = oy + s * 0.16, tb = oy + s * 0.60, th = s * 0.36, r = s * 0.035;
    [tri moveToPoint:CGPointMake(cx, ty)];
    [tri addLineToPoint:CGPointMake(cx + th, tb)];
    [tri addLineToPoint:CGPointMake(cx - th, tb)];
    [tri closePath];
    CGPathRef stroked = CGPathCreateCopyByStrokingPath(tri.CGPath, NULL, r * 2.0, kCGLineCapRound, kCGLineJoinRound, 10);   // (rounded corners)
    UIBezierPath *round = [UIBezierPath bezierPathWithCGPath:stroked];
    CGPathRelease(stroked);
    [round appendPath:tri];
    UIBezierPath *bar = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - th - r, oy + s * 0.69, 2 * (th + r), s * 0.14) cornerRadius:s * 0.04];
    UIBezierPath *both = [UIBezierPath bezierPath]; [both appendPath:round]; [both appendPath:bar];
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, s * 0.012), s * 0.035, DMTGray(0.0, 0.30).CGColor);
    [DMTGray(0.55, 1.0) setFill]; [both fill];
    CGContextRestoreGState(c);
    const CGFloat metal[] = { 0.90, 0.91, 0.93, 1,   0.62, 0.64, 0.68, 1,   0.42, 0.44, 0.48, 1 };
    const CGFloat metalLocs[] = { 0.0, 0.55, 1.0 };
    DMTrashLinearFill(c, both.CGPath, CGPointMake(0, ty), CGPointMake(0, oy + s * 0.83), metal, metalLocs, 3);
    both.lineWidth = MAX(0.5, s * 0.010);
    [DMTGray(0.25, 0.55) setStroke]; [both stroke];
}
static UIImage *DMTrashImage(CGSize size, DMTrashLook look, BOOL dark) {
    if (size.width < 4 || size.height < 4) return nil;
    static NSCache *cache; if (!cache) { cache = [NSCache new]; cache.countLimit = 24; }
    NSString *key = [NSString stringWithFormat:@"%@|%d|%d", NSStringFromCGSize(size), look, dark];
    UIImage *hit = [cache objectForKey:key]; if (hit) return hit;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];   // (the screen's scale: sharp at 2x and 3x)
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGFloat s = MIN(size.width, size.height), ox = (size.width - s) / 2.0, oy = (size.height - s) / 2.0;
        CGContextBeginTransparencyLayer(c, NULL);
        if (look == DMTrashLookEject) DMTrashDrawEject(c, s, ox, oy); else DMTrashDrawBin(c, s, ox, oy, look == DMTrashLookFull);
        if (dark) {   // (a drag over it: darkened where it is drawn, as a Mac's Dock shows the target)
            CGContextSetBlendMode(c, kCGBlendModeSourceAtop);
            [DMTGray(0.0, 0.38) setFill]; CGContextFillRect(c, CGRectMake(0, 0, size.width, size.height));
        }
        CGContextEndTransparencyLayer(c);
    }];
    if (img) [cache setObject:img forKey:key];
    return img;
}

// ---- the Dock icon ------------------------------------------------------------------------------------------------------------------------
// The view Finder's drags look for (statusbar/Finder.h DMFDTrashIconAt, by its class name and -dm_trashTarget).
@interface DMTrashIconView : UIView <UIPointerInteractionDelegate, UIContextMenuInteractionDelegate, UIDropInteractionDelegate>
@property (nonatomic, strong) UIImageView *image;
@property (nonatomic) NSUInteger count;      // items in Finder's Trash (its published state)
@property (nonatomic) BOOL eject, hover;     // a drag of drives under way / a drag over the bin
@property (nonatomic, strong) id pendingIcon;   // an app dropped on the bin by SpringBoard's own icon drag: leaves the Dock once that drag has ended
- (void)tapped;
- (void)dm_refreshLook:(BOOL)animated;
@end

extern BOOL DMTrashRemoveIconFromDock(id icon);           // (Dock.x: Remove from Dock, the app to the Home Screen)
extern BOOL DMTrashIconDragInfo(id session, MSBDTrashIconDrag *info, id *icon);   // (Dock.x: what SpringBoard's icon drag carries)

static NSUInteger DMTrashPublishedCount(void) {
    static int token = 0;
    if (!token && notify_register_check(kMSBDTrashStateName, &token) != NOTIFY_STATUS_OK) { token = 0; return 0; }
    uint64_t n = 0; notify_get_state(token, &n);
    return (NSUInteger)n;
}

@implementation DMTrashIconView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.image = [[UIImageView alloc] initWithFrame:self.bounds];
    self.image.accessibilityIgnoresInvertColors = YES;   // (Smart Invert leaves pictures as they are, like Apple's own icons)
    self.image.contentMode = UIViewContentModeScaleAspectFit;
    self.image.userInteractionEnabled = NO;
    [self addSubview:self.image];
    self.clipsToBounds = NO;
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
    [self addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];
    [self addInteraction:[[UIDropInteraction alloc] initWithDelegate:self]];   // (SpringBoard's own icon drags: an app off the Dock)
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.count = DMTrashPublishedCount();
    return self;
}
- (BOOL)dm_trashTarget { return YES; }
- (BOOL)accessibilityActivate { [self tapped]; return YES; }
- (NSString *)accessibilityLabel { return MSBDTrashAXLabel(self.eject); }
- (NSString *)accessibilityValue { return MSBDTrashAXValue(self.count, self.eject); }
- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {   // (VoiceOver: Open is the activation; Empty Trash when there is something to erase)
    if (self.eject || !self.count) return nil;
    return @[[[UIAccessibilityCustomAction alloc] initWithName:@"Empty Trash" actionHandler:^BOOL(UIAccessibilityCustomAction *a) { notify_post(kMSBDTrashEmptyName); return YES; }]];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.image.bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    self.image.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self dm_refreshLook:NO];
}
- (DMTrashLook)dm_look { return self.eject ? DMTrashLookEject : self.count ? DMTrashLookFull : DMTrashLookEmpty; }
- (void)dm_refreshLook:(BOOL)animated {
    UIImage *want = DMTrashImage(self.bounds.size, [self dm_look], self.hover);
    if (!want || self.image.image == want) return;
    if (animated && self.image.image && self.window) {   // (empty <-> full, bin <-> Eject: a short cross-fade, also with Reduce Motion)
        [UIView transitionWithView:self.image duration:MSBReduceMotion() ? kMSBRMDuration : 0.18 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ self.image.image = want; } completion:nil];
    } else self.image.image = want;
}
- (void)dm_setCount:(NSUInteger)n {
    if (n == self.count) return;
    BOOL was = self.count > 0; self.count = n;
    if (was != (n > 0)) { DMLog([NSString stringWithFormat:@"[trash] the Trash is %@ (%lu item(s))", n ? @"full" : @"empty", (unsigned long)n]); [self dm_refreshLook:YES]; }
}
// Finder's drag over the bin (DMFDIconHover): darker, and a little larger unless Reduce Motion is on.
- (void)dm_setDropHover:(BOOL)on {
    DM_FEATURE_MARK("dock-trash-drop-target");
    if (on == self.hover) return;
    self.hover = on;
    DMLog([NSString stringWithFormat:@"[trash] a drag is %@ the bin%@", on ? @"over" : @"no longer over", self.eject ? @" (Eject)" : @""]);
    [self dm_refreshLook:NO];
    BOOL rm = MSBReduceMotion();
    [UIView animateWithDuration:rm ? kMSBRMDuration : 0.15 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        self.image.transform = on && !rm ? CGAffineTransformMakeScale(1.12, 1.12) : CGAffineTransformIdentity;
    } completion:nil];
}
// A drag of drives (Finder.h, from its start to its end): the bin shows the Eject sign, as a Mac's Trash does.
- (void)dm_setEject:(BOOL)on {
    if (on == self.eject) return;
    DM_FEATURE_MARK("dock-trash-eject-look");
    self.eject = on;
    DMLog([NSString stringWithFormat:@"[trash] a drag of drives %@: the bin %@", on ? @"began" : @"ended", on ? @"shows Eject" : @"is the Trash again"]);
    [self dm_refreshLook:YES];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}
- (void)tapped { DM_FEATURE_MARK("dock-trash-open"); DMLog(@"[trash] tapped: Finder opens the Trash"); notify_post(kMSBDTrashOpenName); }
- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region {
    if (!DMTrashIconLift()) return nil;
    return [UIPointerStyle styleWithEffect:[UIPointerLiftEffect effectWithPreview:[[UITargetedPreview alloc] initWithView:self]] shape:nil];
}
// A held finger or a right click: Open and Empty Trash, as the Trash's menu on a Mac (Empty Trash greyed when there is nothing in it).
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)p {
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *s) {
        DM_FEATURE_MARK("dock-trash-menu");
        NSUInteger n = DMTrashPublishedCount();
        UIAction *open = [UIAction actionWithTitle:@"Open" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) { notify_post(kMSBDTrashOpenName); }];
        UIAction *empty = [UIAction actionWithTitle:@"Empty Trash" image:[UIImage systemImageNamed:@"trash.slash"] identifier:nil handler:^(UIAction *a) {
            DMLog(@"[trash] Empty Trash from the Dock: Finder asks first"); notify_post(kMSBDTrashEmptyName); }];
        empty.attributes = n ? UIMenuElementAttributesDestructive : UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:@"" children:@[open, [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[empty]]]];
    }];
}
- (UITargetedPreview *)dm_menuPreview {
    UIPreviewParameters *pp = [UIPreviewParameters new];
    pp.backgroundColor = [UIColor clearColor];   // (the bin stands free: no platter of the menu's behind it)
    CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) * 0.2253;
    pp.visiblePath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r];
    return [[UITargetedPreview alloc] initWithView:self parameters:pp];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_menuPreview]; }
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_menuPreview]; }
// ---- SpringBoard's own icon drag: an app off the Dock onto the bin ----
- (BOOL)dropInteraction:(UIDropInteraction *)interaction canHandleSession:(id<UIDropSession>)session {
    MSBDTrashIconDrag info = {0}; id icon = nil;
    BOOL yes = DMTrashIconDragInfo(session, &info, &icon) && MSBDTrashRemovesFromDock(info);
    DMLog([NSString stringWithFormat:@"[trash] an icon drag over the bin: %lu icon(s), app %d, folder %d, from the Dock %d, kept in the Dock %d -> %@",
           (unsigned long)info.count, info.isApp, info.isFolder, info.fromDock, info.keptInDock, yes ? @"it can leave the Dock here" : @"not taken"]);
    return yes;
}
- (UIDropProposal *)dropInteraction:(UIDropInteraction *)interaction sessionDidUpdate:(id<UIDropSession>)session {
    if (!self.hover) [self dm_setDropHover:YES];
    return [[UIDropProposal alloc] initWithDropOperation:UIDropOperationMove];
}
- (void)dropInteraction:(UIDropInteraction *)interaction sessionDidExit:(id<UIDropSession>)session { [self dm_setDropHover:NO]; }
- (void)dropInteraction:(UIDropInteraction *)interaction performDrop:(id<UIDropSession>)session {
    DM_FEATURE_MARK("dock-trash-remove-from-dock");
    MSBDTrashIconDrag info = {0}; id icon = nil;
    if (DMTrashIconDragInfo(session, &info, &icon) && MSBDTrashRemovesFromDock(info)) self.pendingIcon = icon;
    DMLog([NSString stringWithFormat:@"[trash] an app was dropped on the bin: %@", self.pendingIcon ? @"it leaves the Dock when SpringBoard's drag has ended" : @"not one that can leave the Dock"]);
}
// (the app's picture goes into the bin: it shrinks into it -- a fade with Reduce Motion)
- (UITargetedPreview *)dropInteraction:(UIDropInteraction *)interaction previewForDroppingItem:(UIDragItem *)item withDefault:(UITargetedPreview *)preview {
    if (!preview || !self.window) return nil;
    UIPreviewTarget *target = [[UIPreviewTarget alloc] initWithContainer:self center:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds) - self.bounds.size.height * 0.12)
                                                               transform:MSBReduceMotion() ? CGAffineTransformMakeScale(0.9, 0.9) : CGAffineTransformMakeScale(0.08, 0.08)];
    return [preview retargetedPreviewWithTarget:target];
}
- (void)dropInteraction:(UIDropInteraction *)interaction sessionDidEnd:(id<UIDropSession>)session {
    [self dm_setDropHover:NO];
    id icon = self.pendingIcon; self.pendingIcon = nil;
    if (!icon) return;
    // (after SpringBoard has finished its own drag -- the app's place in the Dock settled -- it leaves the Dock through the icon model, as Remove
    //  from Dock in its menu does; nothing is ever uninstalled)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL ok = DMTrashRemoveIconFromDock(icon);
        DMLog([NSString stringWithFormat:@"[trash] the app dropped on the bin %@", ok ? @"left the Dock (to the Home Screen)" : @"stayed in the Dock (no free place on the Home Screen, or not in the Dock any more)"]);
    });
}
@end

// ---- called from Dock.x ----
static const void *kTrashIconKey = &kTrashIconKey;
static NSHashTable *gTrashIcons;   // (every bin, weak: the state updates them all -- one per Dock, an external display has its own)
static void DMTrashStateChanged(void) {
    NSUInteger n = DMTrashPublishedCount();
    for (DMTrashIconView *v in gTrashIcons.allObjects) [v dm_setCount:n];
}
void DMTrashAttach(UIView *platter, CGRect slot, BOOL show) {
    DMTrashIconView *icon = objc_getAssociatedObject(platter, kTrashIconKey);
    if (!show || slot.size.width < 8.0) { icon.hidden = YES; if (icon) [icon dm_setDropHover:NO]; return; }
    if (!icon) {
        DM_FEATURE_MARK("dock-trash-icon");
        icon = [[DMTrashIconView alloc] initWithFrame:CGRectMake(0, 0, slot.size.width, slot.size.height)];
        objc_setAssociatedObject(platter, kTrashIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [platter addSubview:icon];
        if (!gTrashIcons) gTrashIcons = [NSHashTable weakObjectsHashTable];
        [gTrashIcons addObject:icon];
        static int token = 0;   // (the bin follows Finder's Trash as it changes: empty / full)
        if (!token) notify_register_dispatch(kMSBDTrashStateName, &token, dispatch_get_main_queue(), ^(int t) { DMTrashStateChanged(); });
        DMLog([NSString stringWithFormat:@"[trash] the bin is in the Dock (%lu item(s) in the Trash)", (unsigned long)icon.count]);
    }
    icon.hidden = NO;
    icon.transform = CGAffineTransformIdentity;   // (hover magnification re-applies its own)
    icon.bounds = CGRectMake(0, 0, slot.size.width, slot.size.height);
    icon.center = CGPointMake(CGRectGetMidX(slot), CGRectGetMidY(slot));
    [icon dm_setCount:DMTrashPublishedCount()];
    [icon setNeedsLayout];
    [platter bringSubviewToFront:icon];
}
UIView *DMTrashIcon(UIView *platter) {
    DMTrashIconView *icon = objc_getAssociatedObject(platter, kTrashIconKey);
    return (icon && !icon.hidden) ? icon : nil;
}

#if DEBUG   // (test helpers: never in a release build)
// "trash <cmd>" in /tmp/dockmag-escape (Dock.x's debug poll): tap, open, empty, hover1 / hover0, eject1 / eject0, state, frame, removeicon_<bundle>
void DMTrashDebug(NSString *cmd) {
    DMTrashIconView *v = nil;
    for (DMTrashIconView *x in gTrashIcons.allObjects) if (x.window && !x.hidden) v = x;
    if ([cmd isEqualToString:@"tap"]) { [v tapped]; }
    else if ([cmd isEqualToString:@"empty"]) notify_post(kMSBDTrashEmptyName);
    else if ([cmd isEqualToString:@"hover1"] || [cmd isEqualToString:@"hover0"]) [v dm_setDropHover:[cmd hasSuffix:@"1"]];
    else if ([cmd isEqualToString:@"eject1"] || [cmd isEqualToString:@"eject0"]) [v dm_setEject:[cmd hasSuffix:@"1"]];
    else if ([cmd hasPrefix:@"removeicon_"]) {   // (the drop's own removal, for one app of the Dock: what a drop of that app on the bin does after the drag)
        NSString *b = [cmd substringFromIndex:11];
        id icon = nil;
        @try {
            id ic = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("SBIconController"), @selector(sharedInstance));
            id dock = [[[ic valueForKey:@"iconManager"] valueForKey:@"rootFolder"] valueForKey:@"dock"];
            for (id x in [dock valueForKey:@"icons"]) if ([[x valueForKey:@"applicationBundleID"] isEqual:b]) icon = x;
        } @catch (id e) {}
        DMLog([NSString stringWithFormat:@"[trash] debug: remove %@ from the Dock -> %d", b, icon ? DMTrashRemoveIconFromDock(icon) : -1]);
    }
    CGRect f = v ? [v convertRect:v.bounds toCoordinateSpace:v.window.screen.coordinateSpace] : CGRectZero;
    DMLog([NSString stringWithFormat:@"[trash] debug %@: bin %@ on screen at %@, count %lu, eject %d, hover %d, look %d; VoiceOver \"%@\" / \"%@\", actions %@", cmd, v ? @"found" : @"NOT found", NSStringFromCGRect(f),
           (unsigned long)v.count, v.eject, v.hover, v ? (int)[v dm_look] : -1, v.accessibilityLabel, v.accessibilityValue, [[v.accessibilityCustomActions valueForKey:@"name"] componentsJoinedByString:@","]]);
}
#endif
