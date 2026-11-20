// LightMagnify.h -- Magnify Traffic Lights (1.8.6, KT 10 Nov): a finger down on a set of red / yellow / green grows them into a small frosted pill
// with their symbols, the light under the finger the biggest; sliding along picks another; lifting on a light does what that light does (its own
// button's actions, run as a tap on it would run them); lifting away from the pill does nothing. The pill grows from the lights' own corner to the
// right and down and stays inside the window or bar they sit in (the layout and the pick: common/LightMagnify.h, tools/test-lightmagnify.sh).
// Every set of lights goes through DMLightGroupAttach (the stage windows', Zetsu's, MilkyWay's, Stage Manager's title bars, our own windows', the
// menu bar's for a full-screen app), so every one of them gets it there. The pill is a finger's only. A trackpad's or mouse's pointer (1.8.8, KT 19 Nov:
// "apply to cursor too but less") grows the lights where they are, a little: the light under the pointer 1.4 times its size, its neighbours less,
// no pill; the symbols show as before, and a pointer's click is the light's own click as before (the block "the pointer" below). Off (Settings >
// Windows & Multitasking > Magnify Traffic Lights, one switch for both): the recognizer takes no touch, nothing grows, and every light behaves
// exactly as before.
#include "../common/LightMagnify.h"
static BOOL DMDesktopPointerTouch(UITouch *t, UIEvent *e);   // (Desktop.h: a pointer's click, whatever type its touch has -- SpringBoard does not opt into
                                                            //  indirect input, so a mouse or trackpad click comes as a DIRECT touch, type 0)
static int DMPtrIPadNative(CGPoint g, CGPoint *n);   // (PointerRegion.h: backboardd's place as the iPad's own native point -- the pointer's hold, 1.8.8)
static BOOL DMScreenOnAndUnlocked(void);   // (StatusBar.x: a hold ends with the screen off or locked)
static void DMLightMagnifyWatchTouches(void);   // (below: SpringBoard's touches noted from the first hover over a set of lights, 1.8.8)
static double gLightPtrTouchAt = 0;   // (... the last one: a hover's cancel right after a touch is the touch's, never held)
static BOOL gLightPtrTouchesNoted = NO;   // (... and they are: the hook is in -- without it a hold could not end at a touch, and none is made)
static unsigned long long DMLightPtrFadeState(void);   // (below: pointeruid's word on the pointer's fade, common/PointerFade.h -- a hold ends at it, D48)
static void DMLightMagnifyWatchFade(void);   // (below: ... watched from the first hold)

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
// the pointer (1.8.8): its state (common/LightMagnify.h, MSBDLightPtr) and what it last drew -- the block "the pointer" below
@interface DMLightMagnifier () {
    MSBDLightPtr _lp;
}
@property (nonatomic, strong) NSArray<NSNumber *> *ptrTarget;       // each light's size last set (one per self.dots; nil at rest)
@property (nonatomic, strong) NSArray<NSNumber *> *ptrLastTarget;   // ... and at the last rest by a hover's end (a click right after puts them back)
@property (nonatomic, weak) UIHoverGestureRecognizer *ptrHover;     // the lights' hover (DMLightGroup's), read live: is it hovering now
@property (nonatomic) BOOL ptrOver;               // its last report was over the lights (the symbols show)
@property (nonatomic) CGRect ptrBox;              // the window box in the container's space, taken once per visit to the lights (ptrBoxValid)
@property (nonatomic) BOOL ptrBoxValid;
@property (nonatomic) CGPoint ptrAt;              // the pointer's last place, in its screen's fixed space (a window moved, hid or went under it)
@property (nonatomic, weak) UIScreen *ptrScreen;
@property (nonatomic) NSInteger ptrBig;           // the light drawn biggest (the log), -1 none
@property (nonatomic) unsigned ptrHoldGen;        // each hold's own chain of looks (a look of an earlier hold's stops)
@property (nonatomic) int ptrHoldLooks;
@property (nonatomic) long ptrLogState;           // the hover's state last logged
@end
static __weak DMLightMagnifier *gLightPtrHolder;   // the set whose hover is held (one pointer: one at a time)
static BOOL gLightPtrLive = NO;   // a set has something of the pointer's on it (MSBDLightPtrWantsTouches): the sendEvent: pass-through's gate, a plain load
static __weak DMLightMagnifier *gLightPtrLiveSet;   // ... the set that turned it on last (one pointer: one at a time)

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
    MSBDLightPtrMark(&_lp, touch.type == UITouchTypeIndirectPointer || [why isEqualToString:@"not a finger (pointer)"], CACurrentMediaTime());   // (1.8.8: the pointer's own click, marked)
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
    if (_lp.grown || _lp.held) { _lp.held = 0; [self pointerRest:NO why:@"a finger"]; }   // (1.8.8: a finger after the pointer: the lights at their own size first, its animation gone, so the pill opens from their size)
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
// ---- the pointer (1.8.8): grown where they are, a little, under a trackpad's or mouse's pointer ----
// The lights' hover (DMLightGroup -hover:) hands every report to the magnifier (DMLightMagnifyHover, below the class). Inside a usable light's own
// button every shown light gets its size from common/LightMagnify.h (MSBDLightPtrScales: 1.4x under the pointer, its neighbours a little, each kept
// inside its own button and its window, never below 1), as its dot's transform. Nothing else is written here: no frame, bounds, centre or alpha, no
// recognizer; a click is the light's own as before, and the light drawn biggest is the one it hits. 0.16 s to grow, 0.12 s to follow, 0.22 s back,
// ease-out / in-out, no spring (an overshoot would pass a capped light's edge); a new animation only when a size moves by more than kMSBDLightPtrMove.
// The state and its decisions are plain C (MSBDLightPtr, Mac-tested): a click in either order with UIKit's cancel; a finger after the pointer
// (openAt's first statement); a stale grow (-apply's look: the pointer's last place in its screen's fixed space, every view up to the window shown);
// UIKit's cancel under a resting pointer held as the Dock holds it (backboardd's place, on the iPad's own screen) until the pointer fades (D48).
// Logs "[lights] pointer:".
- (BOOL)pointerVisible {   // on screen: the container and every view up to its window shown, the window too
    UIView *c = self.container;
    if (!c.window || c.window.hidden) return NO;
    for (UIView *v = c; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;
    return YES;
}
- (CGRect)pointerDotRect:(UIView *)d inView:(UIView *)v {   // a light's own rect as if not grown (its centre and bounds: a transform moves neither)
    CGSize s = d.bounds.size;
    CGRect r = CGRectMake(d.center.x - s.width / 2.0, d.center.y - s.height / 2.0, s.width, s.height);
    return d.superview ? [d.superview convertRect:r toView:v] : CGRectNull;
}
// The box a grown light stays in: findBoxView's walk (the nearest view round them that clips, is rounded or masked, else the UIWindow), holding the
// lights themselves, not their container -- with Aerial 5.x's own theme off the lights' view sticks out of the stage, and the box was the screen.
- (UIView *)pointerBoxView:(CGRect)lights {
    UIView *c = self.container, *v = c.superview;
    while (v) {
        BOOL edge = v.clipsToBounds || v.layer.cornerRadius > 1.0 || v.layer.mask || [v isKindOfClass:[UIWindow class]];
        if (edge && CGRectContainsRect(CGRectInset(v.bounds, -1.0, -1.0), [c convertRect:lights toView:v])) return v;
        v = v.superview;
    }
    return c.window;
}
// The shown lights as common/LightMagnify.h reads them, in the container's space (map: each one's index in self.dots); with the window box when asked
// (taken once per visit to the lights: a window moves with its lights; the hover leaving them, or a rest, has it taken again the next time).
- (void)pointerRow:(MSBDLightRow *)r map:(NSUInteger *)map box:(BOOL)withBox {
    UIView *c = self.container;
    memset(r, 0, sizeof *r);
    CGRect u = CGRectNull;
    for (NSNumber *n in [self visibleLights]) {
        NSUInteger i = n.unsignedIntegerValue;
        int k = r->n;
        if (k >= kMSBDLightMagMaxDots) break;
        UIControl *b = self.buttons[i];
        UIView *d = self.dots[i];
        CGRect dr = [self pointerDotRect:d inView:c], br = [b convertRect:b.bounds toView:c];
        if (CGRectIsNull(dr)) continue;
        r->cx[k] = CGRectGetMidX(dr); r->cy[k] = CGRectGetMidY(dr); r->size[k] = dr.size.width;
        r->cellMinX[k] = CGRectGetMinX(br); r->cellMinY[k] = CGRectGetMinY(br); r->cellMaxX[k] = CGRectGetMaxX(br); r->cellMaxY[k] = CGRectGetMaxY(br);
        r->usable[k] = b.enabled && ![objc_getAssociatedObject(d, kLightDisabledKey) boolValue];   // (the bar's green greyed for a full-screen-only app: never)
        map[k] = i;
        r->n++;
        u = CGRectUnion(u, dr);
    }
    if (!withBox || CGRectIsNull(u) || !c.window) return;
    if (!self.ptrBoxValid) {
        UIView *bv = [self pointerBoxView:u], *h = c.window;
        CGRect win = [h convertRect:h.bounds toView:c];
        CGRect box = CGRectIntersection(CGRectInset([bv convertRect:bv.bounds toView:c], kMSBDLightPtrMargin, kMSBDLightPtrMargin), win);
        self.ptrBox = CGRectIsNull(box) ? win : box;
        self.ptrBoxValid = YES;
    }
    r->boxMinX = CGRectGetMinX(self.ptrBox); r->boxMinY = CGRectGetMinY(self.ptrBox); r->boxMaxX = CGRectGetMaxX(self.ptrBox); r->boxMaxY = CGRectGetMaxY(self.ptrBox);
}
- (void)pointerDraw:(NSArray<NSNumber *> *)t over:(NSTimeInterval)duration curve:(UIViewAnimationOptions)curve {   // each light's size as its dot's transform
    NSArray<UIView *> *dots = self.dots;
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | curve animations:^{
        for (NSUInteger i = 0; i < dots.count && i < t.count; i++) {
            CGFloat k = t[i].doubleValue;
            dots[i].transform = k > 1.0 ? CGAffineTransformMakeScale(k, k) : CGAffineTransformIdentity;
        }
    } completion:nil];
}
- (NSString *)pointerSizes {   // each light's size read back from its dot's transform (a capture may miss a grown view: the log tells)
    NSMutableArray *a = [NSMutableArray array];
    for (UIView *d in self.dots) [a addObject:[NSString stringWithFormat:@"%.2f", d.transform.a]];
    return [a componentsJoinedByString:@" / "];
}
// The pointer at p (the container's space) over the lights, or held there: the sizes under it, or back to rest off the buttons.
- (void)pointerAt:(CGPoint)p {
    UIView *c = self.container;
    UIScreen *sc = c.window.screen;
    self.ptrScreen = sc;
    self.ptrAt = sc ? [c convertPoint:p toCoordinateSpace:sc.fixedCoordinateSpace] : p;   // (-apply's look: the window may move under a still pointer)
    if (!gLightMagnify || gGALightsInert || self.outer || !c.window) {
        if (_lp.grown) [self pointerRest:YES why:self.outer ? @"the finger's pill is out" : @"switched off"];
        return;
    }
    MSBDLightRow r;
    NSUInteger map[kMSBDLightMagMaxDots] = {0};
    [self pointerRow:&r map:map box:YES];
    double s[kMSBDLightMagMaxDots];
    int under = MSBDLightPtrScales(&r, p.x, p.y, s);
    double top = 1.0;
    for (int k = 0; k < r.n; k++) top = fmax(top, s[k]);
    if (under < 0 || !(top > 1.0 + 1e-6)) {
        if (_lp.grown) [self pointerRest:YES why:under < 0 ? @"the pointer is off the buttons" : @"no room to grow here"];
        return;
    }
    NSMutableArray<NSNumber *> *t = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.dots.count; i++) [t addObject:@1.0];
    for (int k = 0; k < r.n; k++) if (map[k] < t.count) t[map[k]] = @(s[k]);
    BOOL first = !_lp.grown, moved = first || self.ptrTarget.count != t.count;
    for (NSUInteger i = 0; !moved && i < t.count; i++) if (fabs(t[i].doubleValue - self.ptrTarget[i].doubleValue) > kMSBDLightPtrMove) moved = YES;
    if (!moved) return;   // (a pointer moving straight up and down starts nothing)
    _lp.grown = 1;
    self.ptrTarget = t;
    [self pointerDraw:t over:first ? 0.16 : 0.12 curve:UIViewAnimationOptionCurveEaseOut];
    NSInteger big = (NSInteger)map[under];
    if (first) DM_FEATURE_MARK("lights-pointer-grow");
    if (first || big != self.ptrBig) {
        self.ptrBig = big;
        DMLog([NSString stringWithFormat:@"[lights] pointer: %@ light %ld under the pointer: sizes %@ (read back), box %@, in %@", first ? @"grown," : @"now",
               (long)(self.dots[big].tag - 300), [self pointerSizes], NSStringFromCGRect(self.ptrBox), NSStringFromClass([c.window class])]);
    }
}
// Back to their own size: over 0.22 s, or at once -- then a grow still running is taken off too (setting the transform does not take it off, and it
// kept drawing the grow on a visible window). Its last sizes are kept for a click right after (ptrLastTarget).
- (void)pointerRest:(BOOL)animated why:(NSString *)why {
    if (self.ptrTarget) self.ptrLastTarget = self.ptrTarget;
    _lp.grown = 0;
    self.ptrBoxValid = NO; self.ptrBig = -1; self.ptrTarget = nil;
    [self pointerLiveOff];
    NSArray<UIView *> *dots = self.dots;
    void (^back)(void) = ^{ for (UIView *d in dots) if (!CGAffineTransformIsIdentity(d.transform)) d.transform = CGAffineTransformIdentity; };
    if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:back completion:nil];
    else {
        [UIView performWithoutAnimation:back];
        for (UIView *d in dots) for (NSString *k in d.layer.animationKeys) {
            CAAnimation *a = [d.layer animationForKey:k];
            if ([a isKindOfClass:[CAPropertyAnimation class]] && [((CAPropertyAnimation *)a).keyPath hasPrefix:@"transform"]) [d.layer removeAnimationForKey:k];
        }
    }
    DMLog([NSString stringWithFormat:@"[lights] pointer: back to rest%@ (%@)", animated ? @"" : @" at once", why]);
}
- (void)pointerRegrow {   // a pointer click right after the hover's end (UIKit's cancel came first): the sizes back for the click, over 0.08 s
    NSArray<NSNumber *> *t = self.ptrLastTarget;
    if (t.count != self.dots.count) { _lp.grown = 0; return; }
    [self pointerLiveOn];
    self.ptrTarget = t;
    [self pointerDraw:t over:0.08 curve:UIViewAnimationOptionCurveEaseOut];
    DMLog([NSString stringWithFormat:@"[lights] pointer: held for a click (its touch down came after UIKit's cancel): the sizes back, %@", [self pointerSizes]]);
}
- (BOOL)pointerClicking {   // a pointer click in progress on the set, read live: a light's button tracking, the press's last touch the pointer's
    if (!_lp.markPointer) return NO;
    for (NSNumber *i in [self visibleLights]) if (self.buttons[i.unsignedIntegerValue].isTracking) return YES;
    return NO;
}
- (BOOL)pointerHovering {   // the lights' hover now (UIKit's Began or Changed), read live
    UIHoverGestureRecognizer *g = self.ptrHover;
    return g && (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged);
}
- (BOOL)pointerInBand:(CGPoint)q {   // over the lights as DMLightGroup -hover: counts it: a light's cell, 2 pt wider each side, 4 pt taller
    if (!isfinite(q.x) || !isfinite(q.y)) return NO;
    for (UIView *dot in self.dots) {
        UIView *cell = dot.superview ?: dot;
        if (CGRectContainsPoint(CGRectInset([cell convertRect:cell.bounds toView:self.container], -2.0, -4.0), q)) return YES;
    }
    return NO;
}
- (void)pointerUnlight {   // the symbols off with a hold's end (the light group's lit), unless UIKit's hover is over them again
    if ([self pointerHovering]) return;
    DMLightGroup *g = objc_getAssociatedObject(self.container, kLightGroupKey);
    g.lit = NO;
}
// SpringBoard's touches matter to this set only while it has something of the pointer's on it (MSBDLightPtrWantsTouches: the symbols shown, a grow,
// a hold), so the pass-through of -[SpringBoard sendEvent:] notes them only then (gLightPtrLive, read before any message). On at each report over the
// lights, a grow put back for a click, a hold's start and each look that keeps it; off once the set that turned it on has nothing left (a rest, the
// hover off the lights), and the note checks it too.
- (BOOL)pointerWantsTouches { return MSBDLightPtrWantsTouches(&_lp, self.ptrOver) != 0; }
- (void)pointerLiveOn {
    if (gLightPtrLive && gLightPtrLiveSet == self) return;
    gLightPtrLive = YES; gLightPtrLiveSet = self;
    DMLog([NSString stringWithFormat:@"[lights] pointer: SpringBoard's touches noted for this set (in %@)", NSStringFromClass([self.container.window class])]);
}
- (void)pointerLiveOff {
    if (!gLightPtrLive || gLightPtrLiveSet != self || [self pointerWantsTouches]) return;
    gLightPtrLive = NO; gLightPtrLiveSet = nil;
    DMLog(@"[lights] pointer: SpringBoard's touches no longer noted (nothing of the pointer's on the lights)");
}
- (void)pointerLogState:(UIGestureRecognizerState)st over:(BOOL)over now:(double)now {   // the hover's state changes (not each move)
    if ((long)st == self.ptrLogState) return;
    self.ptrLogState = (long)st;
    NSString *name = st == UIGestureRecognizerStateBegan ? @"began" : st == UIGestureRecognizerStateChanged ? @"changed" : st == UIGestureRecognizerStateEnded ? @"ended"
                   : st == UIGestureRecognizerStateCancelled ? @"cancelled" : [NSString stringWithFormat:@"state %ld", (long)st];
    DMLog([NSString stringWithFormat:@"[lights] pointer: hover %@ (%@; %.3f s after SpringBoard's last touch; a light tracking a pointer's click: %@; in %@)", name,
           over ? @"over the lights" : @"not over them", gLightPtrTouchAt > 0 ? now - gLightPtrTouchAt : -1.0, [self pointerClicking] ? @"yes" : @"no",
           NSStringFromClass([self.container.window class])]);
}
// Every report of the lights' hover: over (the sizes under the pointer, a hold ends: UIKit has it again) or not (MSBDLightPtrHoverOff's answer).
// YES: the lights stay as they are, lit -- kept for a click, or held under a resting pointer.
- (BOOL)pointerHover:(UIHoverGestureRecognizer *)g over:(BOOL)over at:(CGPoint)p {
    double now = CACurrentMediaTime();
    [self pointerLogState:g.state over:over now:now];
    if (MSBDLightPtrIdle(&_lp, over, self.ptrOver)) return NO;   // (off the lights with nothing of the pointer's on them -- a move over the title bar round them: no work)
    self.ptrHover = g;
    if (over) {
        if (MSBDLightPtrHoverOver(&_lp)) { if (gLightPtrHolder == self) gLightPtrHolder = nil; DMLog(@"[lights] pointer: UIKit has the pointer again (the hold ends)"); }
        self.ptrOver = YES;
        if (gLightMagnify && !gGALightsInert) { [self pointerLiveOn]; DMLightMagnifyWatchTouches(); }
        [self pointerAt:p];
        return NO;
    }
    BOOL shown = self.ptrOver || _lp.grown;
    self.ptrOver = NO;
    self.ptrBoxValid = NO;   // (the window box is taken once per visit to the lights: they may move against it before the next)
    if (!gLightMagnify || gGALightsInert) {
        _lp.held = 0;
        if (_lp.grown) [self pointerRest:YES why:@"switched off"];
        [self pointerLiveOff];
        return NO;
    }
    UIScreen *sc = self.container.window.screen;
    BOOL own = (!sc || sc == [UIScreen mainScreen]) && gLightPtrTouchesNoted;   // (backboardd's place is the iPad's; a touch must be seen to end a hold)
    switch (MSBDLightPtrHoverOff(&_lp, (long)g.state, [self pointerClicking], shown, own, self.outer != nil, now, gLightPtrTouchAt)) {
        case MSBDLightPtrKeep:
            DMLog(@"[lights] pointer: held for a click (UIKit's cancel came after the click's touch)");
            return YES;
        case MSBDLightPtrHold:
            [self pointerHoldStart];
            return _lp.held != 0;   // (its first look may end it at once -- the lights hidden or gone, the screen off or locked: then unlit, as before)
        case MSBDLightPtrRest:
            [self pointerRest:YES why:g.state == UIGestureRecognizerStateCancelled ? @"UIKit cancelled the hover" : g.state == UIGestureRecognizerStateEnded ? @"the hover ended" : @"the pointer left the lights"];
            return NO;
        default:
            [self pointerLiveOff];   // (nothing of the pointer's left on the set: SpringBoard's touches no longer noted for it)
            return NO;
    }
}
// A light's touch down (TouchDown, TouchDragEnter) or up (TouchUpInside / Outside, TouchCancel, TouchDragExit).
- (void)pointerClick:(BOOL)down {
    double now = CACurrentMediaTime();
    if (down) {
        if (MSBDLightPtrClickDown(&_lp, gLightMagnify && !gGALightsInert, self.outer != nil, self.press.state == UIGestureRecognizerStatePossible, now) == MSBDLightPtrRegrow) [self pointerRegrow];
        else if (_lp.grown && [self pointerClicking]) DMLog(@"[lights] pointer: a click's touch down on the grown lights (before UIKit's cancel): their sizes stay for the click");
        return;
    }
    if (MSBDLightPtrClickUp(&_lp, [self pointerHovering]) == MSBDLightPtrRest) [self pointerRest:YES why:@"a click ended"];
}
// -apply's look: a grown or held set goes back at once when the pointer's last place is no longer on one of its buttons (its window moved, by the
// Window menu, a shortcut, KeyPilot or Fit, under a still pointer whose hover still says Changed), it is hidden (an ancestor too: a stage hidden, not
// removed) or gone, switched off, or nothing hovers or holds it. Never during a click or a live hover on a light.
- (void)pointerCheck {
    if (!_lp.grown && !_lp.held) return;
    UIView *c = self.container;
    UIScreen *sc = c.window.screen;
    BOOL visible = [self pointerVisible], onButton = NO, held = _lp.held;
    if (visible && sc == self.ptrScreen) {
        CGPoint q = sc ? [c convertPoint:self.ptrAt fromCoordinateSpace:sc.fixedCoordinateSpace] : self.ptrAt;
        MSBDLightRow r;
        NSUInteger map[kMSBDLightMagMaxDots] = {0};
        [self pointerRow:&r map:map box:NO];
        onButton = MSBDLightPtrButtonAt(&r, q.x, q.y, 0.5) >= 0;   // (half a point of slop: the place went to the screen's space and back)
    }
    if (MSBDLightPtrCheck(&_lp, [self pointerClicking], [self pointerHovering], visible, gLightMagnify && !gGALightsInert, onButton) != MSBDLightPtrRestNow) return;
    [self pointerRest:NO why:!visible ? @"no hover: the lights hid or went" : (!onButton ? @"no hover: the window moved under the pointer" : @"no hover or hold, or switched off")];
    if (held) { if (gLightPtrHolder == self) gLightPtrHolder = nil; [self pointerUnlight]; }
}
// A resting pointer (H, 1.8.8: the Dock's hold, common/DockHover.h): UIKit's cancel with no touch before it is held while backboardd has the pointer
// over the lights -- read off the main thread, in its shape only, as the Dock's hold and the side Dock's reveal read it, in the iPad's own region
// (PointerRegion.h) --, often at first, less while it rests; UIKit's hover beginning again takes over; a touch, the pointer elsewhere, not known, no
// pointing device, the screen off or locked, the lights hidden or gone end it. So does the pointer's fade (D48, 1.8.8): iPadOS hides a resting pointer
// (on the test iPads UIKit's cancel here IS that fade, about 8 s after the last move), and pointeruid says so (common/PointerFade.h) -- at each look
// and the moment it changes (pointerFadeNote), so the lights are back at rest with the fade, not grown and lit under no pointer.
- (void)pointerHoldStart {
    self.ptrHoldGen++;
    self.ptrHoldLooks = 0;
    gLightPtrHolder = self;
    [self pointerLiveOn];
    DMLog([NSString stringWithFormat:@"[lights] pointer: UIKit cancelled the hover with no touch before it (%.3f s after the last): held while the pointer is over the lights",
           gLightPtrTouchAt > 0 ? CACurrentMediaTime() - gLightPtrTouchAt : -1.0]);
    DMLightMagnifyWatchFade();   // (once: from the first hold on, pointeruid's word on the fade is heard -- before the first look reads it)
    [self pointerHoldLook:self.ptrHoldGen];
}
- (void)pointerHoldDone:(NSString *)why {   // the hold is over (the state already says so): back to rest, the symbols off
    if (gLightPtrHolder == self) gLightPtrHolder = nil;
    [self pointerRest:YES why:[@"the hold ends: " stringByAppendingString:why]];
    [self pointerUnlight];
}
- (void)pointerTouched {   // SpringBoard saw a touch (a finger hides the pointer, a click is the user's): a hold ends
    if (MSBDLightPtrTouchBegan(&_lp, CACurrentMediaTime()) == MSBDLightPtrUnhold) [self pointerHoldDone:@"a touch or a click"];
}
- (void)pointerFadeNote {   // pointeruid said the pointer faded or shows again (D48): a hold ends at the fade, unless UIKit's hover began again
    if (MSBDLightPtrFade(&_lp, [self pointerHovering], DMLightPtrFadeState(), CACurrentMediaTime()) == MSBDLightPtrUnhold) [self pointerHoldDone:@"the pointer faded"];
}
- (void)pointerHoldLook:(unsigned)gen {
    if (!_lp.held || gen != self.ptrHoldGen) return;   // (ended, or a later hold has its own looks: one backboardd read at a time)
    NSString *gone = !gLightMagnify || gGALightsInert ? @"switched off" : (self.outer ? @"the finger's pill is out" : (![self pointerVisible] ? @"the lights hid or went"
                   : (!DMScreenOnAndUnlocked() ? @"the screen is off or locked" : nil)));
    if (gone) { MSBDLightPtrHoldLook(&_lp, MSBDHoverHoldEnd, CACurrentMediaTime()); [self pointerHoldDone:gone]; return; }
    if ([self pointerHovering]) { MSBDLightPtrHoldLook(&_lp, MSBDHoverHoldUIKit, CACurrentMediaTime()); if (gLightPtrHolder == self) gLightPtrHolder = nil; DMLog(@"[lights] pointer: UIKit has the pointer again"); return; }
    if (MSBDLightPtrFade(&_lp, NO, DMLightPtrFadeState(), CACurrentMediaTime()) == MSBDLightPtrUnhold) { [self pointerHoldDone:@"the pointer faded"]; return; }   // (UIKit's hover not begun: just above)
    id app = [UIApplication sharedApplication];
    SEL pms = NSSelectorFromString(@"mousePointerManager"), att = NSSelectorFromString(@"isHardwarePointingDeviceAttached");
    id pm = [app respondsToSelector:pms] ? ((id (*)(id, SEL))objc_msgSend)(app, pms) : nil;
    BOOL attached = ![pm respondsToSelector:att] || ((BOOL (*)(id, SEL))objc_msgSend)(pm, att);
    static dispatch_queue_t q;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.macstatusbar.lights.hoverhold", DISPATCH_QUEUE_SERIAL);
    __weak DMLightMagnifier *ws = self;
    dispatch_async(q, ^{
        Class k = objc_getClass("BKSMousePointerService");
        id svc = k && [(id)k respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)k, @selector(sharedInstance)) : nil;
        SEL gp = sel_registerName("globalPointerPosition");
        Method mt = svc ? class_getInstanceMethod(object_getClass(svc), gp) : NULL;
        BOOL known = mt && !strcmp(method_getTypeEncoding(mt) ?: "", "{CGPoint=dd}16@0:8");
        CGPoint g = known ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, gp) : CGPointMake(NAN, NAN);
        dispatch_async(dispatch_get_main_queue(), ^{
            DMLightMagnifier *m = ws;
            if (!m || !m->_lp.held || gen != m.ptrHoldGen || !m.container.window) return;
            CGPoint n = CGPointMake(NAN, NAN), p = CGPointMake(NAN, NAN);
            if (known && DMPtrIPadNative(g, &n) > 0) p = [m.container convertPoint:n fromCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace];
            double now = CACurrentMediaTime();
            switch (MSBDLightPtrHoldLook(&m->_lp, MSBDHoverHoldStep([m pointerHovering], known, attached, [m pointerInBand:p]), now)) {
                case MSBDLightPtrKeep: {
                    DM_FEATURE_MARK("lights-pointer-held");
                    [m pointerLiveOn];
                    [m pointerAt:p];
                    double next = MSBDHoverHoldInterval(m.ptrHoldLooks++);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(next * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws pointerHoldLook:gen]; });
                    break;
                }
                case MSBDLightPtrUnhold:
                    [m pointerHoldDone:known ? @"the pointer is no longer over the lights" : @"the pointer's place can't be read here"];
                    break;
                default:
                    if (gLightPtrHolder == m) gLightPtrHolder = nil;
                    DMLog(@"[lights] pointer: UIKit has the pointer again");
                    break;
            }
        });
    });
}
// ---- end of the pointer
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

// The pointer's entry points (1.8.8): from the light group (StatusBar.x DMLightGroup) and from SpringBoard's touches. Out of line, so a crash in them
// falls in this file, which the crash map gives to Magnify Traffic Lights (tools/crashmap-rules.txt), not to the status bar or the traffic lights.
// The lights' hover (DMLightGroup -hover:, every report): YES while the lights are kept as they are -- for a click, or held under a resting pointer
// (the group keeps them lit, the symbols on).
__attribute__((noinline)) static BOOL DMLightMagnifyHover(UIView *container, UIHoverGestureRecognizer *g, BOOL over, CGPoint p) {
    DMLightMagnifier *m = container ? objc_getAssociatedObject(container, kLightMagnifierKey) : nil;
    return m ? [m pointerHover:g over:over at:p] : NO;
}
// A light's touch down (TouchDown, TouchDragEnter: down YES) or up (TouchUpInside, TouchUpOutside, TouchCancel, TouchDragExit).
__attribute__((noinline)) static void DMLightMagnifyClick(UIView *container, BOOL down) {
    DMLightMagnifier *m = container ? objc_getAssociatedObject(container, kLightMagnifierKey) : nil;
    [m pointerClick:down];
}
// DMLightGroup -apply's look (every front change, every MilkyWay4 layout pass, the bar's lights' layout, each lighting): a stale grow goes back at once.
__attribute__((noinline)) static void DMLightMagnifyCheck(UIView *container) {
    DMLightMagnifier *m = container ? objc_getAssociatedObject(container, kLightMagnifierKey) : nil;
    [m pointerCheck];
}
// A touch SpringBoard sees (any type but a finger on the trackpad, as the Dock's hold notes them, dock/Dock.x): a hover's cancel right after it is the
// touch's, never held, and a hold running ends. Only while a set has something of the pointer's on it (gLightPtrLive): the set that turned it on gone
// or with nothing left turns it off here.
__attribute__((noinline)) static void DMLightMagnifyTouchNote(UIEvent *event) {
    if (![gLightPtrLiveSet pointerWantsTouches]) {
        gLightPtrLive = NO; gLightPtrLiveSet = nil;
        DMLog(@"[lights] pointer: SpringBoard's touches no longer noted (the set went or has nothing of the pointer's left)");
        return;
    }
    for (UITouch *t in event.allTouches) if (t.phase == UITouchPhaseBegan && t.type != UITouchTypeIndirect) {
        gLightPtrTouchAt = CACurrentMediaTime();
        [gLightPtrHolder pointerTouched];
        break;
    }
}
// -[SpringBoard sendEvent:] sees every touch (an app's too, through the system gestures' window): hooked once, at the first hover over a set of lights
// with the switch on, and only passed on (the crash map passes over it, as over the other sendEvent: hooks: tools/crashmap-rules.txt). It stays in for
// the rest of SpringBoard's life (another hook may sit on top of it), so it looks at an event only through plain loads first: switched off, in Guided
// Access, or with nothing of the pointer's on any set of lights, an event costs those loads and no message.
static void (*o_DMLightMagnifySendEvent)(id, SEL, UIEvent *);
__attribute__((noinline)) static void DMLightMagnifySendEvent(id self, SEL _cmd, UIEvent *event) {
    if (gLightMagnify && !gGALightsInert && gLightPtrLive && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);
    o_DMLightMagnifySendEvent(self, _cmd, event);
}
static void DMLightMagnifyWatchTouches(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class sb = objc_getClass("SpringBoard");
    SEL s = @selector(sendEvent:);
    if (sb && class_getInstanceMethod(sb, s)) {
        MSHookMessageEx(sb, s, (IMP)DMLightMagnifySendEvent, (IMP *)&o_DMLightMagnifySendEvent);
        gLightPtrTouchesNoted = o_DMLightMagnifySendEvent != NULL;
        DMLog(@"[lights] pointer: SpringBoard's touches noted from now on (a resting pointer's hold ends at a touch)");
    } else DMLog(@"[lights] pointer: no -[SpringBoard sendEvent:]: UIKit's cancel under a resting pointer is not held");
}
// The pointer's fade (D48, 1.8.8): MacPointer in pointeruid says when iPadOS hides the pointer and when it shows again (common/PointerFade.h), a Darwin
// notification and its state. Heard from the first hold on (never at a constructor): each change goes to the set held then (pointerFadeNote), and each
// look of a hold reads the state (one notifyd read, at most every 0.12 s while a hold runs). Not heard (the watch not in): nothing said, the hold as before.
static int gLightPtrFadeToken = 0;
static BOOL gLightPtrFadeHeard = NO;
static unsigned long long DMLightPtrFadeState(void) {
    uint64_t v = MSBDPointerFadeUnsaid;
    if (gLightPtrFadeHeard && notify_get_state(gLightPtrFadeToken, &v) != NOTIFY_STATUS_OK) v = MSBDPointerFadeUnsaid;
    return v;
}
static void DMLightMagnifyWatchFade(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    gLightPtrFadeHeard = notify_register_dispatch(kMSBDPointerFadeNote, &gLightPtrFadeToken, dispatch_get_main_queue(), ^(int t) {
        DMLog([NSString stringWithFormat:@"[lights] pointer: pointeruid says the pointer %@%@", DMLightPtrFadeState() == MSBDPointerFadeHidden ? @"faded" : @"shows",
               gLightPtrHolder ? @" (a set is held)" : @""]);
        [gLightPtrHolder pointerFadeNote];
    }) == NOTIFY_STATUS_OK;
    DMLog([NSString stringWithFormat:@"[lights] pointer: the pointer's fade heard from now on (pointeruid's word: %llu, 0 nothing said, 1 faded, 2 shows)", DMLightPtrFadeState()]);
}
