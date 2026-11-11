// LightMagnify.h -- Magnify Traffic Lights (1.8.6, KT 10 Nov): a finger down on a set of red / yellow / green grows them into a small frosted pill
// with their symbols, the light under the finger the biggest; sliding along picks another; lifting on a light does what that light does (its own
// button's actions, run as a tap on it would run them); lifting away from the pill does nothing. The pill grows from the lights' own corner to the
// right and down and stays inside the window or bar they sit in (the layout and the pick: common/LightMagnify.h, tools/test-lightmagnify.sh).
// Every set of lights goes through DMLightGroupAttach (the stage windows', Zetsu's, MilkyWay's, Stage Manager's title bars, our own windows', the
// menu bar's for a full-screen app), so every one of them gets it there. Only a finger: the pointer keeps the Mac's hover (the symbols show), and a
// pointer's click is a click as before. Off (Settings > Windows & Multitasking > Magnify Traffic Lights): the recognizer takes no touch, and every
// light behaves exactly as before.
#include "../common/LightMagnify.h"
static BOOL DMDesktopPointerTouch(UITouch *t, UIEvent *e);   // (Desktop.h: a pointer's click, whatever type its touch has -- SpringBoard does not opt into
                                                            //  indirect input, so a mouse or trackpad click comes as a DIRECT touch, type 0)

static BOOL gLightMagnify = YES;   // (Magnify Traffic Lights, key magnifyTrafficLights: on unless switched off -- DMLoadPrefs)
static const void *kLightMagnifierKey = &kLightMagnifierKey;

@interface DMLightMagnifier : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *container;
@property (nonatomic, strong) NSArray<UIControl *> *buttons;
@property (nonatomic, strong) NSArray<UIView *> *dots;
@property (nonatomic, strong) UILongPressGestureRecognizer *press;
// while the pill is out
@property (nonatomic, weak) UIView *host;
@property (nonatomic, strong) UIView *space;          // in the host, laid exactly over the lights' container (its turn and scale too): the pill's coordinates
@property (nonatomic, strong) UIView *outer;           // the pill's shadow and place (in the host)
@property (nonatomic, strong) UIVisualEffectView *pill;
@property (nonatomic, strong) NSArray<NSNumber *> *shown;   // which of self.dots are in the pill (the visible ones, in order)
@property (nonatomic, strong) NSMutableArray<UIView *> *bigDots;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *dotAlphas;
@property (nonatomic) CGPoint anchor;
@property (nonatomic) CGFloat base;
@property (nonatomic) CGRect box;
@property (nonatomic) NSInteger pick;
@property (nonatomic) CGFloat offset;         // the finger -> the point the pill follows (relative: the light first touched stands for the finger)
@property (nonatomic) MSBDLightMag drawn;   // the layout last drawn: the lift picks against what the finger sees
@end

@implementation DMLightMagnifier
// Visible lights: a hidden green (windowing off, an app that has no full-screen) is left out of the pill.
- (NSArray<NSNumber *> *)visibleLights {
    NSMutableArray *v = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.dots.count && i < self.buttons.count; i++) {
        UIView *b = self.buttons[i], *d = self.dots[i];
        if (b.hidden || b.alpha < 0.01 || d.hidden || !d.window) continue;
        [v addObject:@(i)];
        if (v.count == kMSBDLightMagMaxDots) break;
    }
    return v;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    NSString *why = nil;
    UIView *c = self.container;
    NSArray *vis = nil;
    if (!gLightMagnify) why = @"switched off";
    else if (gGALightsInert) why = @"Guided Access";
    else if (touch.type != UITouchTypeDirect) why = @"not a finger";
    else if (DMDesktopPointerTouch(touch, nil)) why = @"not a finger (pointer)";   // (a click on a light is the light's own click, as before)
    else if (!c || !c.window || !c.userInteractionEnabled) why = @"no window";
    else if ((vis = [self visibleLights]).count < 2) why = @"fewer than two lights shown";
    else {
        CGRect u = CGRectNull;
        for (NSNumber *i in vis) { UIView *b = self.buttons[i.unsignedIntegerValue]; u = CGRectUnion(u, [b convertRect:b.bounds toView:c]); }
        if (!CGRectContainsPoint(CGRectInset(u, -4.0, -4.0), [touch locationInView:c])) why = @"off the lights";
    }
    if (why && gLightMagnify) DMLog([NSString stringWithFormat:@"[lights] magnify: not for this touch (%@, in %@)", why, NSStringFromClass([c.window class])]);
    return why == nil;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    DMLog([NSString stringWithFormat:@"[lights] magnify: the press may begin (in %@)", NSStringFromClass([self.container.window class])]);
    return YES;
}
// The box the pill stays in: the window round the lights -- the nearest view round them that clips, is rounded or masked (an engine's window, e.g.
// an Aerial stage) and holds them whole -- so it never goes past the window's edge (1.5 pt in from it). The pill
// itself is drawn in the lights' UIWindow: an engine's window lays its own subviews out (an Aerial stage moved it under its title bar, m02).
- (UIView *)findBoxView {
    UIView *c = self.container, *v = c.superview;
    while (v) {
        BOOL edge = v.clipsToBounds || v.layer.cornerRadius > 1.0 || v.layer.mask || [v isKindOfClass:[UIWindow class]];
        if (edge && CGRectContainsRect(CGRectInset(v.bounds, -1.0, -1.0), [c convertRect:c.bounds toView:v])) return v;
        v = v.superview;
    }
    return c.window;
}
- (MSBDLightMag)layoutAt:(CGFloat)fingerX finger:(BOOL)has {
    return MSBDLightMagLayout((int)self.shown.count, self.anchor.x, self.anchor.y, self.base, fingerX, has ? 1 : 0,
                              CGRectGetMinX(self.box), CGRectGetMinY(self.box), CGRectGetMaxX(self.box), CGRectGetMaxY(self.box));
}
- (void)applyLayout:(MSBDLightMag)L {
    self.outer.frame = CGRectMake(L.pillX, L.pillY, L.pillW, L.pillH);
    self.pill.frame = self.outer.bounds;
    self.pill.layer.cornerRadius = L.pillH / 2.0;
    self.outer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.outer.bounds cornerRadius:L.pillH / 2.0].CGPath;
    for (NSUInteger k = 0; k < self.bigDots.count && k < (NSUInteger)L.n; k++) {
        UIView *d = self.bigDots[k];
        CGFloat s = L.size[k];
        d.bounds = CGRectMake(0, 0, s, s);
        d.center = CGPointMake(L.cx[k] - L.pillX, L.cy - L.pillY);
        d.layer.cornerRadius = s / 2.0;
        UIView *glyph = d.subviews.firstObject;
        glyph.frame = CGRectInset(d.bounds, s * 0.2, s * 0.2);
        glyph.alpha = self.pick < 0 ? 0.55 : ((NSInteger)k == self.pick ? 1.0 : 0.7);
    }
}
// The pill as it starts and ends: each light where it is now, the pill round them (outer, its pill and big lights given: a closing pill keeps its own
// while a new one may open).
- (void)collapse:(UIView *)outer pill:(UIView *)pill big:(NSArray<UIView *> *)big {
    UIView *h = outer.superview ?: self.space;
    CGRect u = CGRectNull;
    NSMutableArray *rects = [NSMutableArray array];
    for (NSNumber *i in self.shown) { UIView *d = self.dots[i.unsignedIntegerValue]; CGRect r = [d convertRect:d.bounds toView:h]; [rects addObject:[NSValue valueWithCGRect:r]]; u = CGRectUnion(u, r); }
    if (CGRectIsNull(u)) return;
    u = CGRectInset(u, -2.0, -2.0);
    outer.frame = u; pill.frame = outer.bounds; pill.layer.cornerRadius = u.size.height / 2.0;
    outer.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:outer.bounds cornerRadius:u.size.height / 2.0].CGPath;
    for (NSUInteger k = 0; k < big.count && k < rects.count; k++) {
        CGRect r = [rects[k] CGRectValue];
        UIView *d = big[k];
        d.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
        d.center = CGPointMake(CGRectGetMidX(r) - u.origin.x, CGRectGetMidY(r) - u.origin.y);
        d.layer.cornerRadius = r.size.width / 2.0;
        UIView *glyph = d.subviews.firstObject;
        glyph.frame = CGRectInset(d.bounds, r.size.width * 0.2, r.size.width * 0.2);
        glyph.alpha = 0.0;
    }
}
- (void)openAt:(CGPoint)p {
    UIView *c = self.container, *h = c.window, *bv = [self findBoxView];
    NSArray *vis = [self visibleLights];
    if (!h || !bv || vis.count < 2) return;
    self.host = h; self.shown = vis; self.pick = -1;
    // (the pill is laid out in the container's own coordinates and drawn in the UIWindow through a view laid exactly over the container: the window may
    //  not be turned as the interface is -- the menu bar's lights for a full-screen app sit in SpringBoard's switcher window, in the screen's portrait
    //  space -- and an engine's window lays its own subviews out)
    CGPoint o = [c convertPoint:CGPointZero toView:h], ux = [c convertPoint:CGPointMake(1, 0) toView:h], uy = [c convertPoint:CGPointMake(0, 1) toView:h];
    CGAffineTransform U = CGAffineTransformMake(ux.x - o.x, ux.y - o.y, uy.x - o.x, uy.y - o.y, 0, 0);
    UIView *space = [[UIView alloc] initWithFrame:CGRectZero];
    space.userInteractionEnabled = NO;
    space.bounds = c.bounds;
    space.transform = U;
    CGPoint mid = CGPointMake(CGRectGetMidX(c.bounds), CGRectGetMidY(c.bounds));   // (o is the container's point (0, 0): the centre is its bounds' mid from there)
    CGPoint um = CGPointApplyAffineTransform(mid, U);
    space.center = CGPointMake(o.x + um.x, o.y + um.y);
    [h addSubview:space];
    self.space = space;
    UIView *first = self.dots[[vis.firstObject unsignedIntegerValue]];
    CGRect fr = [first convertRect:first.bounds toView:c];
    self.anchor = fr.origin; self.base = fr.size.width > 0 ? fr.size.width : kLightDot;
    CGFloat corner = 1.5;   // (a flat margin: the pill's own round ends sit inside a window's round corner -- 30 % of the radius pushed it 8 pt down, m03)
    CGRect box = CGRectIntersection(CGRectInset([bv convertRect:bv.bounds toView:c], corner, corner), [h convertRect:h.bounds toView:c]);
    self.box = CGRectIsNull(box) ? [h convertRect:h.bounds toView:c] : box;
    self.outer = [[UIView alloc] initWithFrame:CGRectZero];
    self.outer.userInteractionEnabled = NO;
    self.outer.layer.shadowColor = UIColor.blackColor.CGColor; self.outer.layer.shadowOpacity = 0.22; self.outer.layer.shadowRadius = 6.0; self.outer.layer.shadowOffset = CGSizeMake(0, 2);
    self.pill = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.pill.clipsToBounds = YES;
    self.pill.layer.borderWidth = 0.5; self.pill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    [self.outer addSubview:self.pill];
    self.bigDots = [NSMutableArray array]; self.dotAlphas = [NSMutableArray array];
    for (NSNumber *i in vis) {
        UIView *real = self.dots[i.unsignedIntegerValue];
        NSInteger which = real.tag - 300;
        BOOL disabled = [objc_getAssociatedObject(real, kLightDisabledKey) boolValue];
        UIView *d = [[UIView alloc] initWithFrame:CGRectZero];
        d.backgroundColor = disabled ? real.backgroundColor : DMLightColor(which >= 0 && which <= 2 ? which : (NSInteger)i.unsignedIntegerValue);
        UIImageView *rg = nil;
        for (UIView *s in real.subviews) if ([s isKindOfClass:[UIImageView class]]) { rg = (UIImageView *)s; break; }
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:roundf(self.base * 1.2) weight:UIImageSymbolWeightHeavy];
        UIImage *img = rg.image ? [rg.image imageByApplyingSymbolConfiguration:cfg] : [UIImage systemImageNamed:DMLightSymbolName(which, NO) withConfiguration:cfg];
        UIImageView *g = [[UIImageView alloc] initWithImage:img];
        g.contentMode = UIViewContentModeScaleAspectFit;
        g.tintColor = [UIColor colorWithWhite:0.0 alpha:disabled ? 0.3 : 0.62];
        [d addSubview:g];
        [self.outer addSubview:d];
        [self.bigDots addObject:d];
        [self.dotAlphas addObject:@(real.alpha < 0.01 ? 1.0 : real.alpha)];   // (0: an earlier pill still going: the light's own is 1)
    }
    [space addSubview:self.outer];
    [self collapse:self.outer pill:self.pill big:self.bigDots];
    for (NSNumber *i in vis) self.dots[i.unsignedIntegerValue].alpha = 0.0;   // (the real lights wait under the pill: they come back as it goes)
    CGPoint fp = [self.press locationInView:c];
    // (the light under the finger by the lights' own places stands for the finger: drawn the biggest, and a lift without a slide picks it)
    int touched = 0; CGFloat best = CGFLOAT_MAX;
    for (NSUInteger k = 0; k < vis.count; k++) {
        UIView *d = self.dots[[vis[k] unsignedIntegerValue]];
        CGFloat dx = fabs(CGRectGetMidX([d convertRect:d.bounds toView:c]) - fp.x);
        if (dx < best) { best = dx; touched = (int)k; }
    }
    CGFloat vx = MSBDLightMagVirtualX((int)vis.count, touched, self.anchor.x, self.anchor.y, self.base, fp.x,
                                      CGRectGetMinX(self.box), CGRectGetMinY(self.box), CGRectGetMaxX(self.box), CGRectGetMaxY(self.box));
    self.offset = vx - fp.x;
    MSBDLightMag L = [self layoutAt:vx finger:YES];
    self.pick = MSBDLightMagPick(L, vx, fp.y);
    self.drawn = L;
    [UIView animateWithDuration:0.36 delay:0 usingSpringWithDamping:0.74 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ [self applyLayout:L]; } completion:nil];
    DMLog([NSString stringWithFormat:@"[lights] magnify: %lu lights out under a finger (base %.1f pt, pill %@, in %@)", (unsigned long)vis.count, self.base,
           NSStringFromCGRect(CGRectMake(L.pillX, L.pillY, L.pillW, L.pillH)), NSStringFromClass([h class])]);
    DMLog([NSString stringWithFormat:@"[lights] magnify: kept inside %@ %@ (the lights' own space; turned %.0f deg in the window)", NSStringFromClass([bv class]), NSStringFromCGRect(self.box), atan2(U.b, U.a) * 180.0 / M_PI]);
}
- (void)moveTo:(CGPoint)p {
    if (!self.outer || !self.space) return;
    CGFloat vx = p.x + self.offset;
    MSBDLightMag L = [self layoutAt:vx finger:YES];
    self.pick = MSBDLightMagPick(L, vx, p.y);
    self.drawn = L;
    [UIView animateWithDuration:0.14 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                     animations:^{ [self applyLayout:L]; } completion:nil];
}
- (void)closeRunning:(NSInteger)pick {
    UIView *outer = self.outer, *pill = self.pill, *space = self.space;
    NSArray *big = [self.bigDots copy];
    NSArray *shown = self.shown, *alphas = [self.dotAlphas copy];
    NSArray *dots = self.dots, *buttons = self.buttons;
    self.outer = nil; self.pill = nil; self.bigDots = nil; self.space = nil;
    if (outer) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn animations:^{
            [self collapse:outer pill:pill big:big];
            outer.alpha = 0.0;
        } completion:^(BOOL done) {
            [outer removeFromSuperview]; [space removeFromSuperview];
            for (NSUInteger k = 0; k < shown.count && k < alphas.count; k++) if ([shown[k] unsignedIntegerValue] < dots.count) ((UIView *)dots[[shown[k] unsignedIntegerValue]]).alpha = [alphas[k] doubleValue];
        }];
    }
    if (pick < 0 || pick >= (NSInteger)shown.count) { DMLog(@"[lights] magnify: let go away from the lights: nothing"); return; }
    NSUInteger i = [shown[pick] unsignedIntegerValue];
    if (i >= buttons.count) return;
    UIControl *b = buttons[i];
    UIView *dot = dots[i];
    if ([objc_getAssociatedObject(dot, kLightDisabledKey) boolValue] || !b.enabled || b.hidden) { DMLog(@"[lights] magnify: let go on a light that does nothing here"); return; }
    DMLog([NSString stringWithFormat:@"[lights] magnify: let go on light %ld: its own action", (long)(dot.tag - 300)]);
    dispatch_async(dispatch_get_main_queue(), ^{ [b sendActionsForControlEvents:UIControlEventTouchUpInside]; });   // (as a tap on that light runs it)
}
- (void)pressed:(UILongPressGestureRecognizer *)g {
    switch (g.state) {
        case UIGestureRecognizerStateBegan: [self openAt:[g locationInView:self.container]]; break;
        case UIGestureRecognizerStateChanged: if (self.outer) [self moveTo:[g locationInView:self.container]]; break;
        case UIGestureRecognizerStateEnded: {
            NSInteger pick = -1;
            if (self.outer) { CGPoint p = [g locationInView:self.container]; pick = MSBDLightMagPick(self.drawn, p.x + self.offset, p.y); }
            [self closeRunning:pick];
            break;
        }
        case UIGestureRecognizerStateCancelled: case UIGestureRecognizerStateFailed: [self closeRunning:-1]; break;
        default: break;
    }
}
@end

// Called by DMLightGroupAttach for every set of lights (once per container; later calls refresh the buttons and dots).
static void DMLightMagnifyAttach(UIView *container, NSArray<UIControl *> *buttons, NSArray<UIView *> *dots) {
    if (!container || buttons.count < 2 || buttons.count != dots.count) return;
    DMLightMagnifier *m = objc_getAssociatedObject(container, kLightMagnifierKey);
    if (!m) {
        m = [DMLightMagnifier new];
        m.container = container;
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:m action:@selector(pressed:)];
        press.minimumPressDuration = 0.0;
        press.allowableMovement = CGFLOAT_MAX;
        press.cancelsTouchesInView = YES;   // (the light's own tap is cancelled: the pill decides what the lift does)
        press.allowedTouchTypes = @[@(UITouchTypeDirect)];   // (a pointer's click comes as type 0 too: -gestureRecognizer:shouldReceiveTouch: refuses it)
        press.delegate = m;
        m.press = press;
        [container addGestureRecognizer:press];
        objc_setAssociatedObject(container, kLightMagnifierKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    m.buttons = buttons;
    m.dots = dots;
}
