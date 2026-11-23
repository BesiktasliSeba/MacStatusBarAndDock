// RecentStrip.h: the recent windows strip (1.8.8.2 F29), included by StatusBar.x after WindowCards.h. KT, 20 Nov: "We can make it a 1.8.8.2
// feature, and it can be like on macos": the recent windows wait at the side of the desktop as small pictures, as with Stage Manager on a Mac; a tap
// or click on one brings it forward and the one that was in front takes its slot; the strip steps aside when a window covers it and comes back with
// the pointer at the edge. Aerial, Zetsu and MilkyWay4 (their windows are our engine code's stages, DMAerialStages, one per app), on iPadOS 15
// (common/RecentStripRule.h MSBDRecentStripOS: the pictures without SpringBoard waiting are read there only). Settings > Windows & Multitasking >
// Recent Windows Strip (recentStrip, on unless switched off). The rules are common/RecentStripRule.h (Mac test tools/test-recentstrip.sh).
//  - No timer and no poll of its own: DMRStripTick rides the 0.2 s window watcher (DMSyncWindowsForLibraryBody). The pointer comes from one hover
//    recognizer on SpringBoard's system gestures window of the iPad (PointerRegion.h's DMPtrHoverRecognizer: it only watches), there only while the
//    strip has stepped aside with a trackpad or mouse attached.
//  - Still pictures, never a portal (a portal has the render server draw the window again in every frame): the render server's picture of the
//    window's layer at the card's size, from a background queue (MacSwitcher.h's lookups, queue and slot holder), taken when a window has left the
//    front and SpringBoard is calm, before our minimize, and as the strip comes for a window on screen with none or an old one.
//  - Our window (the Mac Switcher's window class) just above the windows' level; only the cards take touches.
//  - A crash in this file or its rules turns the switch off (tools/crashmap-rules.txt, recentStrip).
#include "../common/RecentStripRule.h"

static BOOL gRStripPref = YES;   // Settings > Windows & Multitasking > Recent Windows Strip (recentStrip): on unless switched off (DMLoadPrefs)
static BOOL gDMPointerAttached;  // (a trackpad or mouse attached: StatusBar.x, DMPointerDeviceCheck)
@class DMRStripCard;
static UIWindow *gRStripWindow;                                  // our window, made the first time the strip shows; hidden while it is
static UIView *gRStripRoot;                                      // its content, turned with the screen (DMRStripTurnIn only)
static UIView *gRStripSlide;                                     // the cards, the whole of gRStripRoot: its transform and alpha are the strip's step
                                                                 //  aside and return (DMRStripShowAs only), so the turn never undoes a step aside
static unsigned gRStripLayouts;                                  // (how often the cards were laid out: the debug trigger rstrip says)
static NSMutableArray<NSString *> *gRStripOrder;                 // the recent windows' apps, most recent first (never the one in front)
static NSString *gRStripFront = @"";                             // the app whose window was in front at the last look ("" none)
static NSString *gRStripPicked; static CFTimeInterval gRStripPickedAt;   // a pick on its way: the window in front takes its slot
static NSMutableDictionary<NSString *, UIView *> *gRStripPics;   // app -> its window's picture (a view of a render server slot), card size
static NSMutableDictionary<NSString *, NSNumber *> *gRStripPicAt;    // app -> when it was taken
static NSMutableDictionary<NSString *, NSNumber *> *gRStripPicDue;   // app -> when its picture after leaving the front is due
static NSMutableSet<NSString *> *gRStripPicAsking;               // asked, the answer not here yet
static NSMutableDictionary<NSString *, DMRStripCard *> *gRStripCards;   // app -> its card
static NSArray<NSString *> *gRStripItems;                        // the cards shown now, in order
static MSBDRStripShow gRStripShown = MSBDRStripHidden;
static int gRStripReveal = 0;                                    // 0: none; 1: the pointer at the edge; 2: Window > Show Recent Windows
static CFTimeInterval gRStripTouchedAt = 0, gRStripPointerOutAt = 0;
static BOOL gRStripMayRevealNow = NO;                            // (the last look: the strip stepped aside with something to show)
static MSBDRRect gRStripBand, gRStripSpan;
static BOOL gRStripRight = NO;
static NSString *gRStripLayoutSig;
static UIHoverGestureRecognizer *gRStripSysHover;
static __weak UIWindow *gRStripSysHoverWindow;

static BOOL DMRStripOn(void) {
    if (!gRStripPref || gStockBar) return NO;
    DMEngine e = DMActiveEngine();
    if (e != DMEngineAerial && e != DMEngineZetsu && e != DMEngineMilkyWay) return NO;   // (Stage Manager and windowing off: DMEngineNone)
    static int os = -1;
    if (os < 0) os = MSBDRecentStripOS([NSProcessInfo processInfo].operatingSystemVersion.majorVersion) ? 1 : 0;
    return os && DMMSWAsyncPicturesOK();
}
// The app of the window in front now ("" none): the engine's top window on screen, as the tick's own look has it.
static NSString *DMRStripFrontNow(void) {
    BOOL stageEngine = DMActiveEngine() == DMEngineAerial || DMActiveEngine() == DMEngineZetsu;
    UIView *top = stageEngine ? DMTopStage() : DMTopWindow();
    NSString *b = top ? (stageEngine ? DMStageBundle(top) : [(AXWindowView *)top bundleIdentifier]) : nil;
    return [b isKindOfClass:[NSString class]] && b.length ? b : @"";
}
static BOOL DMRStripStageOnScreen(UIView *st) {
    return st && !st.hidden && st.alpha > 0.05 && !DMStageMinimized(st) && ![objc_getAssociatedObject(st, kStageClosingKey) boolValue];
}
static MSBDRRect DMRStripRectOf(CGRect r) { return (MSBDRRect){ r.origin.x, r.origin.y, r.size.width, r.size.height }; }
static CGRect DMRStripCGRect(MSBDRRect r) { return CGRectMake(r.x, r.y, r.w, r.h); }

// ---- the pictures ----
// v's picture at k of its size (its points times the screen's scale times k), handed to done on the main thread: a view of that size showing it,
// or nil. MacSwitcher.h DMMSWPictureAsync's request (read on 15.6.1) with the scale in its transform, so the server draws a card's size, not the
// window's. NO: nothing was asked.
static BOOL DMRStripPictureAsync(UIView *v, double k, void (^done)(UIView *pic, double ms)) {
    if (!v || !done || k <= 0.0 || !DMMSWAsyncPicturesOK()) return NO;
    CALayer *l = v.layer;
    id ctx = DMCall(l, @"context");
    if (!ctx) return NO;
    if ([l respondsToSelector:NSSelectorFromString(@"hasBeenCommitted")] && !((BOOL (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"hasBeenCommitted"))) return NO;
    uint32_t cid = ((uint32_t (*)(id, SEL))objc_msgSend)(ctx, NSSelectorFromString(@"contextId"));
    CGRect b = v.bounds;
    if (!cid || b.size.width < 1 || b.size.height < 1) return NO;
    double s = [UIScreen mainScreen].scale * k;
    CGSize px = CGSizeMake(ceil(b.size.width * s), ceil(b.size.height * s)), pt = CGSizeMake(b.size.width * k, b.size.height * k);
    CATransform3D t = CATransform3DConcat(CATransform3DMakeTranslation(-b.origin.x, -b.origin.y, 0), CATransform3DMakeScale(s, s, 1));
    id name = DMCall([UIScreen mainScreen], @"_name");
    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    opts[gMSWSnapKeyMode] = gMSWSnapModeLayer;
    if ([name isKindOfClass:[NSString class]]) opts[gMSWSnapKeyName] = name;
    opts[gMSWSnapKeyCtx] = @(cid);
    opts[gMSWSnapKeyLayer] = @((unsigned long long)(uintptr_t)(__bridge void *)l);
    opts[gMSWSnapKeyTransform] = [NSValue valueWithCATransform3D:t];
    if (gMSWSnapKeyReuse) opts[gMSWSnapKeyReuse] = @YES;
    if (gMSWSnapKeyIgnoreAX) opts[gMSWSnapKeyIgnoreAX] = @YES;
    CFTimeInterval t0 = CACurrentMediaTime();
    UIView *keep = v;   // (the layer stays alive until the server has drawn it)
    dispatch_async(DMMSWPicQueue(), ^{
        uint32_t slot = 0; BOOL ok = NO;
        @try { slot = ((uint32_t (*)(id, SEL, CGSize, BOOL))objc_msgSend)(ctx, NSSelectorFromString(@"createImageSlot:hasAlpha:"), px, YES); } @catch (id e) { slot = 0; }
        if (slot) { opts[gMSWSnapKeyDest] = @(slot); ok = gMSWSnapFn(MACH_PORT_NULL, opts); }
        dispatch_async(dispatch_get_main_queue(), ^{
            (void)keep;
            double ms = (CACurrentMediaTime() - t0) * 1000.0;
            DMMSWSlotHolder *h = nil;
            if (slot) { h = [DMMSWSlotHolder new]; h.context = ctx; h.slot = slot; }
            id contents = ok ? ((id (*)(id, SEL, unsigned int))objc_msgSend)(objc_getClass("CAContext"), NSSelectorFromString(@"objectForSlot:"), slot) : nil;
            if (!contents) { done(nil, ms); return; }   // (h goes: its slot is deleted)
            UIView *pic = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pt.width, pt.height)];
            pic.userInteractionEnabled = NO;
            pic.layer.contents = contents;
            objc_setAssociatedObject(pic, kMSWSlotKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            done(pic, ms);
        });
    });
    return YES;
}
static void DMRStripCardRefresh(NSString *b);   // (below, with the cards)
static void DMRStripPicture(UIView *stage, NSString *b, NSString *why) {
    if (!stage || !b.length || [gRStripPicAsking containsObject:b] || DMTestFlag("/tmp/msb-rstrip-nopics")) return;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    CGRect bb = stage.bounds;
    double k = MSBDRStripPicScale(bb.size.width, bb.size.height, MSBDRStripCardW(sc.width, sc.height), MSBDRStripCardH(sc.width, sc.height));
    if (k <= 0.0) return;
    if (!gRStripPicAsking) gRStripPicAsking = [NSMutableSet set];
    [gRStripPicAsking addObject:b];
    NSString *bb2 = [b copy], *why2 = [why copy];
    BOOL asked = DMRStripPictureAsync(stage, k, ^(UIView *pic, double ms) {
        [gRStripPicAsking removeObject:bb2];
        if (!pic) { static int told = 0; if (told++ < 3) DMLog([NSString stringWithFormat:@"[recentstrip] %@: no picture of its window (%@, %.1f ms)", bb2, why2, ms]); return; }
        if (!DMRStripOn()) return;
        if (!gRStripPics) gRStripPics = [NSMutableDictionary dictionary];
        if (!gRStripPicAt) gRStripPicAt = [NSMutableDictionary dictionary];
        gRStripPics[bb2] = pic; gRStripPicAt[bb2] = @(CACurrentMediaTime());
        DM_FEATURE_MARK("recent-strip-picture");
        if (ms > 30.0 || DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[recentstrip] %@: its window pictured (%@): %.1f ms, %.0f x %.0f pt", bb2, why2, ms, pic.bounds.size.width, pic.bounds.size.height]);
        DMRStripCardRefresh(bb2);
    });
    if (!asked) [gRStripPicAsking removeObject:b];
}
// Our minimize (the yellow light, Minimize All, Home Minimizes Windows, the keys: StatusBar.x DMMinimizeStage and DMMinimizeWindow), before its
// animation: a picture of the window as it was when it has none, or it is the one in front with no recent one (RecentStripRule.h).
static void DMRStripWillMinimize(UIView *stage) {
    if (!stage || !DMRStripOn()) return;
    NSString *b = DMStageBundle(stage);
    if (!b.length || stage.hidden || stage.alpha < 0.05) return;
    NSNumber *at = gRStripPicAt[b];
    if (!MSBDRStripPicAtMinimize(gRStripPics[b] != nil, at ? CACurrentMediaTime() - at.doubleValue : 1e9, [b isEqualToString:gRStripFront])) return;
    DMRStripPicture(stage, b, @"it is being minimized");
}

// ---- the cards ----
@interface DMRStripCard : UIView
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, strong) UIView *frameView;    // the picture's place: its shadow and its rounded clip
@property (nonatomic, strong) UIView *clip;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic) CGRect picRect;               // the picture's place in the card
@end
@implementation DMRStripCard
@end
static void DMRStripPick(DMRStripCard *card);
static void DMRStripTouched(void) { gRStripTouchedAt = CACurrentMediaTime(); gRStripPointerOutAt = 0; }
@interface DMRStripTarget : NSObject
+ (instancetype)shared;
- (void)tap:(UITapGestureRecognizer *)g;
- (void)hover:(UIHoverGestureRecognizer *)g;
- (void)sysHover:(UIHoverGestureRecognizer *)g;
@end
static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g);
@implementation DMRStripTarget
+ (instancetype)shared { static DMRStripTarget *t; static dispatch_once_t once; dispatch_once(&once, ^{ t = [DMRStripTarget new]; }); return t; }
- (void)tap:(UITapGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateEnded && [g.view isKindOfClass:[DMRStripCard class]]) DMRStripPick((DMRStripCard *)g.view); }
- (void)hover:(UIHoverGestureRecognizer *)g {   // (the card under the pointer grows a little, as on a Mac)
    BOOL inside = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    UIView *c = g.view;
    if (inside) DMRStripTouched();
    if (g.state != UIGestureRecognizerStateBegan && inside) return;
    MSBAnimate(0.18, 0, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{
        c.transform = inside ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
    }, nil);
}
- (void)sysHover:(UIHoverGestureRecognizer *)g { DMRStripSysHoverSeen(g); }
@end
static UIView *DMRStripWindowHit(id self, SEL _cmd, CGPoint p, UIEvent *e) {   // (only a card takes a touch: between them it goes on to what is under)
    if (gRStripShown == MSBDRStripHidden || !gRStripRoot) return nil;
    for (DMRStripCard *c in gRStripCards.allValues) {
        if (c.hidden || c.alpha < 0.05 || !c.superview) continue;
        CGPoint q = [(UIView *)self convertPoint:p toView:c];
        if ([c pointInside:q withEvent:e]) return c;
    }
    return nil;
}
static UIWindow *DMRStripEnsureWindow(void) {
    if (gRStripWindow) return gRStripWindow;
    @try {
        Class base = objc_getClass("SBMainScreenActiveInterfaceOrientationWindow");
        SEL initRole = NSSelectorFromString(@"initWithRole:debugName:");
        if (!base || ![base instancesRespondToSelector:initRole]) return nil;
        Class sub = objc_getClass("MSBRecentStripWindow");
        if (!sub) {
            sub = objc_allocateClassPair(base, "MSBRecentStripWindow", 0);
            if (!sub) return nil;
            class_addMethod(sub, @selector(hitTest:withEvent:), (IMP)DMRStripWindowHit, "@@:{CGPoint=dd}@");
            objc_registerClassPair(sub);
        }
        UIWindow *w = ((id (*)(id, SEL, id, id))objc_msgSend)([sub alloc], initRole, @"SBFTraitsParticipantRoleRecordingIndicator", @"MacStatusBarRecentStrip");
        DMSnapInvalidate();
        w.backgroundColor = [UIColor clearColor];
        w.hidden = YES;
        UIView *root = [[UIView alloc] initWithFrame:w.bounds];
        root.backgroundColor = [UIColor clearColor];
        [w addSubview:root];
        UIView *slide = [[UIView alloc] initWithFrame:root.bounds];
        slide.backgroundColor = [UIColor clearColor];
        [root addSubview:slide];
        gRStripWindow = w; gRStripRoot = root; gRStripSlide = slide;
        DMLog([NSString stringWithFormat:@"[recentstrip] window made: %@ frame %@", NSStringFromClass([w class]), NSStringFromCGRect(w.frame)]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recentstrip] window failed: %@", e]); gRStripWindow = nil; gRStripRoot = nil; gRStripSlide = nil; }
    return gRStripWindow;
}
// The content's bounds and turn: the screen as it is seen now (this window class turns with the screen on 15; the turn is read, as the Mac
// Switcher's DMMSWTurnIn reads it). The root's transform is the turn and nothing else: the step aside moves gRStripSlide inside it. (When both
// were the root's, every tick of a strip stepped aside read its offset as a stale turn: the offset was undone under the step aside's animation, which
// could then end with the strip back in its place for a frame before the window hid, and the cards were laid out again every 0.2 s while it
// stayed aside.)
static void DMRStripTurnIn(void) {
    UIWindow *l = gRStripWindow; UIView *root = gRStripRoot, *slide = gRStripSlide;
    if (!l || !root || !slide) return;
    UIScreen *on = [UIScreen mainScreen];
    CGSize screen = on.bounds.size, win = l.bounds.size;
    id<UICoordinateSpace> scr = on.coordinateSpace;
    CGPoint o = [l convertPoint:CGPointZero toCoordinateSpace:scr], x = [l convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    CGFloat angle = hypot(x.x - o.x, x.y - o.y) > 50.0 ? -round(atan2(x.y - o.y, x.x - o.x) / M_PI_2) * M_PI_2 : 0;
    BOOL turned = fabs(angle) > 0.01;
    CGRect want = CGRectMake(0, 0, turned ? screen.width : win.width, turned ? screen.height : win.height);
    if (CGRectEqualToRect(root.bounds, want) && CGAffineTransformEqualToTransform(root.transform, turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity)) return;
    root.transform = CGAffineTransformIdentity;
    root.bounds = want;
    root.center = CGPointMake(win.width / 2.0, win.height / 2.0);
    root.transform = turned ? CGAffineTransformMakeRotation(angle) : CGAffineTransformIdentity;
    slide.bounds = CGRectMake(0, 0, want.size.width, want.size.height);   // (bounds and center: right whatever the slide's own transform is now)
    slide.center = CGPointMake(want.size.width / 2.0, want.size.height / 2.0);
    gRStripLayoutSig = nil;
}
static DMRStripCard *DMRStripCardFor(NSString *b) {
    if (!gRStripCards) gRStripCards = [NSMutableDictionary dictionary];
    DMRStripCard *c = gRStripCards[b];
    if (c) return c;
    c = [[DMRStripCard alloc] initWithFrame:CGRectZero];
    c.bundle = b;
    c.backgroundColor = [UIColor clearColor];
    c.frameView = [[UIView alloc] initWithFrame:CGRectZero];
    c.frameView.userInteractionEnabled = NO;
    c.frameView.layer.shadowColor = [UIColor blackColor].CGColor;
    c.frameView.layer.shadowOpacity = 0.32;
    c.frameView.layer.shadowRadius = 7.0;
    c.frameView.layer.shadowOffset = CGSizeMake(0, 3);
    c.clip = [[UIView alloc] initWithFrame:CGRectZero];
    c.clip.userInteractionEnabled = NO;
    c.clip.clipsToBounds = YES;
    c.clip.layer.cornerRadius = 7.0;
    c.clip.backgroundColor = [UIColor colorWithWhite:0.86 alpha:1.0];   // (a card without a picture yet: the icon on a plain card)
    [c.frameView addSubview:c.clip];
    [c addSubview:c.frameView];
    c.icon = [[UIImageView alloc] initWithImage:DMAppIcon(b)];
    c.icon.userInteractionEnabled = NO;
    c.icon.contentMode = UIViewContentModeScaleAspectFit;
    [c addSubview:c.icon];
    DMRStripTarget *t = [DMRStripTarget shared];
    [c addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:t action:@selector(tap:)]];
    [c addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:t action:@selector(hover:)]];
    gRStripCards[b] = c;
    return c;
}
// A card's picture (or none yet) in its clip, filling the picture's place.
static void DMRStripCardPicture(DMRStripCard *c) {
    UIView *pic = gRStripPics[c.bundle];
    for (UIView *v in [c.clip.subviews copy]) if (v != pic) [v removeFromSuperview];
    if (!pic) return;
    if (pic.superview != c.clip) [c.clip addSubview:pic];
    pic.transform = CGAffineTransformIdentity;
    pic.frame = c.clip.bounds;
}
static void DMRStripCardPlace(DMRStripCard *c, MSBDRRect r) {
    CGFloat icon = 26.0;
    CGRect pr = DMRStripCGRect(r);
    CGRect ir = CGRectMake(CGRectGetMinX(pr) - 6.0, CGRectGetMaxY(pr) - icon + 8.0, icon, icon);   // (the app's icon over the picture's lower left corner)
    CGRect all = CGRectUnion(pr, ir);
    c.transform = CGAffineTransformIdentity;
    c.frame = all;
    c.picRect = CGRectOffset(pr, -all.origin.x, -all.origin.y);
    c.frameView.frame = c.picRect;
    c.frameView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:c.frameView.bounds cornerRadius:7.0].CGPath;
    c.clip.frame = c.frameView.bounds;
    c.icon.frame = CGRectOffset(ir, -all.origin.x, -all.origin.y);
    DMRStripCardPicture(c);
}
static void DMRStripCardRefresh(NSString *b) {   // (a picture came: its card shows it, if it is shown)
    DMRStripCard *c = gRStripCards[b];
    if (c && c.superview) DMRStripCardPicture(c);
}
// The strip's offset while away: past its side's edge.
static CGAffineTransform DMRStripAway(void) {
    if (MSBReduceMotion()) return CGAffineTransformMakeScale(kMSBRMScale, kMSBRMScale);
    CGFloat d = gRStripBand.w + 24.0;
    return CGAffineTransformMakeTranslation(gRStripRight ? d : -d, 0);
}
// The cards for items, at the rules' places (sig: what they are laid out for; the same: nothing is done).
static void DMRStripLayoutCards(NSArray<NSString *> *items, NSDictionary<NSString *, UIView *> *stageOf, CGSize sc, MSBDRRect usable, BOOL animated) {
    int n = (int)MIN(items.count, (NSUInteger)kMSBDRStripMax);
    double aspect[kMSBDRStripMax]; MSBDRRect cards[kMSBDRStripMax];
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%.0fx%.0f %.0f,%.0f,%.0f,%.0f %d", sc.width, sc.height, usable.x, usable.y, usable.w, usable.h, gRStripRight];
    for (int i = 0; i < n; i++) {
        CGSize s = stageOf[items[(NSUInteger)i]].bounds.size;
        aspect[i] = s.height > 1.0 ? s.width / s.height : 0.0;
        [sig appendFormat:@" %@:%.2f", items[(NSUInteger)i], aspect[i]];
    }
    if ([sig isEqualToString:gRStripLayoutSig ?: @""]) return;
    gRStripLayoutSig = [sig copy];
    gRStripLayouts++;
    n = MSBDRStripLayout(sc.width, sc.height, usable, gRStripRight, n, aspect, &gRStripBand, cards);
    gRStripSpan = MSBDRStripCardsSpan(gRStripBand, cards, n);
    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    for (int i = 0; i < n; i++) {
        NSString *b = items[(NSUInteger)i];
        [keep addObject:b];
        DMRStripCard *c = DMRStripCardFor(b);
        BOOL fresh = c.superview != gRStripSlide;
        if (fresh) { [gRStripSlide addSubview:c]; c.alpha = animated ? 0.0 : 1.0; }
        MSBDRRect r = cards[i];
        void (^place)(void) = ^{ DMRStripCardPlace(c, r); c.alpha = 1.0; };
        if (animated && !fresh) MSBAnimate(0.24, 0, 0.9, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, place, nil);
        else if (animated) { DMRStripCardPlace(c, r); MSBAnimate(0.22, 0.05, 0, UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction, ^{ c.alpha = 1.0; }, nil); }
        else place();
    }
    for (NSString *b in [gRStripCards allKeys]) {
        if ([keep containsObject:b]) continue;
        DMRStripCard *c = gRStripCards[b];
        [gRStripCards removeObjectForKey:b];
        if (!animated || !c.superview) { [c removeFromSuperview]; continue; }
        MSBAnimate(0.18, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ c.alpha = 0.0; }, ^(BOOL f) { [c removeFromSuperview]; });
    }
    gRStripItems = [items subarrayWithRange:NSMakeRange(0, (NSUInteger)n)];
}

// ---- showing and stepping aside ----
static void DMRStripSysHoverUpdate(BOOL want);
static void DMRStripShowAs(MSBDRStripShow show, NSString *why) {
    MSBDRStripShow was = gRStripShown;
    if (show == was) return;
    gRStripShown = show;
    UIWindow *w = gRStripWindow; UIView *slide = gRStripSlide;   // (the slide moves; the root keeps the turn: DMRStripTurnIn)
    if (show == MSBDRStripHidden) {
        if (!w || w.hidden) return;
        DMLog([NSString stringWithFormat:@"[recentstrip] steps aside (%@)", why]);
        MSBAnimate(0.2, 0, 0, UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState, ^{ slide.transform = DMRStripAway(); slide.alpha = MSBReduceMotion() ? 0.0 : 1.0; }, ^(BOOL f) {
            if (gRStripShown == MSBDRStripHidden) { w.hidden = YES; slide.alpha = 1.0; }
        });
        return;
    }
    DM_FEATURE_MARK("recent-strip-shown");
    DMLog([NSString stringWithFormat:@"[recentstrip] %@ (%@): %@", show == MSBDRStripOverWindows ? @"comes out over the windows" : @"shows on the desktop", why, [gRStripItems componentsJoinedByString:@", "]]);
    if (!w || !slide) return;
    if (was == MSBDRStripHidden && (w.hidden || CGAffineTransformIsIdentity(slide.transform))) { slide.transform = DMRStripAway(); slide.alpha = MSBReduceMotion() ? 0.0 : 1.0; }
    w.hidden = NO;
    MSBAnimate(0.26, 0, 0.92, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, ^{ slide.transform = CGAffineTransformIdentity; slide.alpha = 1.0; }, nil);
}
static void DMRStripRevealEnd(NSString *why) {
    if (!gRStripReveal) return;
    DMLog([NSString stringWithFormat:@"[recentstrip] its reveal ends (%@)", why]);
    gRStripReveal = 0; gRStripPointerOutAt = 0;
}
// Everything of it goes (switched off, another engine, the strip's iPadOS left): the window hidden, the cards and pictures let go.
static void DMRStripReset(NSString *why) {
    if (gRStripWindow && !gRStripWindow.hidden) DMLog([NSString stringWithFormat:@"[recentstrip] off (%@)", why]);
    gRStripShown = MSBDRStripHidden; gRStripReveal = 0; gRStripMayRevealNow = NO;
    gRStripWindow.hidden = YES;
    for (DMRStripCard *c in gRStripCards.allValues) [c removeFromSuperview];
    [gRStripCards removeAllObjects]; [gRStripPics removeAllObjects]; [gRStripPicAt removeAllObjects]; [gRStripPicDue removeAllObjects]; [gRStripOrder removeAllObjects];
    gRStripItems = nil; gRStripLayoutSig = nil; gRStripFront = @""; gRStripPicked = nil;
    DMRStripSysHoverUpdate(NO);
}
// Nothing of the system's or ours over the windows (the window cards' and the menus' readings).
static BOOL DMRStripCalm(void) {
    if (!DMScreenOnAndUnlocked() || DMSwitcherVisible() || gMSWOpen || gMSWClosing || !DMMSWSessionIdle()) return NO;
    if (gWindowsHiddenForLibrary || gHomeMenuOpen || gDockMenuOpen || gSoftKeyboardH >= 100.0) return NO;
    if (DMActiveEngine() == DMEngineZetsu && gZetsuHiddenForSwitcherFlag) return NO;
    if (DMActiveEngine() == DMEngineMilkyWay && gMilkyWayHiddenForSwitcher) return NO;
    if (MSBDGuidedAccessActive() || DMLibraryVisible() || DMSpotlightShown() || DMCoverSheetShown()) return NO;
    return YES;
}
static void DMRStripTick(void) {
    if (!DMRStripOn()) {
        if ((gRStripWindow && !gRStripWindow.hidden) || gRStripOrder.count || gRStripPics.count || gRStripCards.count || gRStripSysHover) DMRStripReset(@"switched off, or not this engine");
        return;
    }
    if (!DMWindowWorkNeeded()) { DMRStripShowAs(MSBDRStripHidden, @"no window"); DMRStripSysHoverUpdate(NO); return; }
    CFTimeInterval now = CACurrentMediaTime();
    // the windows of the desktop on screen, from the front one back (minimized ones too)
    NSArray<UIView *> *stages = DMAerialStages();
    NSMutableArray<NSString *> *present = [NSMutableArray arrayWithCapacity:stages.count];
    NSMutableDictionary<NSString *, UIView *> *stageOf = [NSMutableDictionary dictionaryWithCapacity:stages.count];
    BOOL anyShown = NO;
    for (UIView *st in [stages reverseObjectEnumerator]) {
        NSString *b = DMStageBundle(st);
        if (!b.length || stageOf[b] || [objc_getAssociatedObject(st, kStageClosingKey) boolValue] || [objc_getAssociatedObject(st, kStageGoingFullKey) boolValue]) continue;
        stageOf[b] = st; [present addObject:b];
        if (DMRStripStageOnScreen(st)) anyShown = YES;
    }
    // the order: a pick swaps, any other change of the front puts the window that left it at the top (RecentStripRule.h)
    NSString *front = DMRStripFrontNow();
    if (gRStripPicked && now - gRStripPickedAt > 1.5) gRStripPicked = nil;   // (a pick that did not take)
    if (!gRStripOrder) gRStripOrder = [NSMutableArray array];
    NSString *was = gRStripFront;
    MSBDRStripOrderStep(gRStripOrder, was, front, gRStripPicked, present);
    if (![front isEqualToString:was]) {
        if ([front isEqualToString:gRStripPicked ?: @""]) gRStripPicked = nil;
        if (was.length && stageOf[was]) { if (!gRStripPicDue) gRStripPicDue = [NSMutableDictionary dictionary]; gRStripPicDue[was] = @(now + 0.6); }
        gRStripFront = [front copy];
    }
    // (a picture goes with its window, and once its window is far down the order: the cards' and two more are kept, and the one in front's)
    for (NSString *b in [gRStripPics allKeys]) {
        NSUInteger at = [gRStripOrder indexOfObject:b];
        if (stageOf[b] && ([b isEqualToString:front] || (at != NSNotFound && at < (NSUInteger)kMSBDRStripMax + 2))) continue;
        [gRStripPics removeObjectForKey:b]; [gRStripPicAt removeObjectForKey:b];
    }
    // the picture of a window that left the front: once SpringBoard is calm (the window cards' rule), if it is still on screen
    BOOL calmForPic = !DMSwitcherVisible() && !gMSWOpen && !gMSWClosing && DMMSWSessionIdle() && !DMWinCardBusy();
    for (NSString *b in [gRStripPicDue allKeys]) {
        if ([gRStripPicDue[b] doubleValue] > now) continue;
        UIView *st = stageOf[b];
        if (st && !calmForPic) continue;   // (asked again at the next tick)
        [gRStripPicDue removeObjectForKey:b];
        if (DMRStripStageOnScreen(st) && ![b isEqualToString:front]) DMRStripPicture(st, b, @"it left the front");
    }
    // what it would show, and whether it shows (the desktop's place and the cards only while it could show: one window, something over the
    // windows or the windows behind a full-screen app leave it hidden whatever else)
    BOOL calm = gRStripOrder.count && DMRStripCalm();   // (one window: nothing to show, nothing more is read)
    BOOL windowsFront = calm && DMDesiredWindowLevel() > 10.0;   // (above the apps: not behind a full-screen app, as DMWindowsInFront)
    NSArray<NSString *> *items = @[];
    if (calm && windowsFront && gRStripOrder.count) {
        CGSize sc = [UIScreen mainScreen].bounds.size;
        // (the desktop below the menu bar and above the Dock: read again for a new screen shape, a Dock change, or once a second)
        static CGRect u; static CGSize uFor; static unsigned uDock = ~0u, uPlace = ~0u; static CFTimeInterval uAt = -10;
        if (!CGSizeEqualToSize(uFor, sc) || uDock != gDMDockGen || uPlace != gDMDockPlaceGen || now - uAt > 1.0) { u = DMUsableArea(); uFor = sc; uDock = gDMDockGen; uPlace = gDMDockPlaceGen; uAt = now; }
        MSBDRRect usable = DMRStripRectOf(u);
        gRStripRight = MSBDRStripOnRight(DMDockSideNow(sc) == MSBDDockLeft);
        items = MSBDRStripItems(gRStripOrder, (NSUInteger)MSBDRStripFit(sc.width, sc.height, usable));
        if (items.count && DMRStripEnsureWindow()) { DMRStripTurnIn(); DMRStripLayoutCards(items, stageOf, sc, usable, gRStripShown != MSBDRStripHidden); }
        else items = @[];
    }
    BOOL covered = items.count && DMFrontApp() != nil && DMFullScreenAppInFront();   // (a full-screen app behind the windows lies over the whole edge)
    id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
    for (UIView *st in stageOf.allValues) {
        if (covered || !items.count) break;
        if (!DMRStripStageOnScreen(st)) continue;
        if (MSBDRStripCovers(gRStripSpan, DMRStripRectOf([st convertRect:st.bounds toCoordinateSpace:scr]))) covered = YES;
    }
    if (!covered && items.count && gNativeLayer && !gNativeLayer.hidden)
        for (DMNativeWindow *nw in gNativeWindows) if (!nw.hidden && nw.superview && nw.alpha > 0.05 && MSBDRStripCovers(gRStripSpan, DMRStripRectOf([nw convertRect:nw.bounds toCoordinateSpace:scr]))) { covered = YES; break; }
    // the reveals' ends: the Window menu's after 6 s with no touch or hover on it; the pointer's 0.4 s after it moved past the band
    if (gRStripReveal == 2 && now - gRStripTouchedAt > 6.0) DMRStripRevealEnd(@"untouched for 6 s");
    if (gRStripReveal == 1 && gRStripPointerOutAt > 0 && now - gRStripPointerOutAt > 0.4) DMRStripRevealEnd(@"the pointer moved away");
    MSBDRStripState s = { 1, (int)items.count, calm, windowsFront, anyShown, covered, gRStripReveal != 0 };
    if (gRStripReveal && (!calm || !windowsFront || !items.count)) DMRStripRevealEnd(@"the windows went, or something came over them");
    s.revealed = gRStripReveal != 0;
    gRStripMayRevealNow = MSBDRStripMayReveal(s);
    MSBDRStripShow show = MSBDRStripShowFor(s);
    if (show != MSBDRStripHidden && gRStripWindow) {
        CGFloat level = DMDesiredWindowLevel() + 0.5;   // (just above the windows: over every engine window, under the Dock's floor, Finder and our menus)
        if (fabs(gRStripWindow.windowLevel - level) > 0.01) gRStripWindow.windowLevel = level;
    }
    DMRStripShowAs(show, !gRStripOrder.count ? @"nothing to show" : !calm ? @"something is over the windows" : !windowsFront ? @"the windows are behind a full-screen app" : !items.count ? @"nothing to show"
                         : !anyShown ? @"no window on screen" : covered ? @"a window covers it" : gRStripReveal == 1 ? @"the pointer at the edge" : gRStripReveal == 2 ? @"Window > Show Recent Windows" : @"the desktop is free");
    // a picture for a card that has none, or an old one of a window on screen, as the strip shows (one per tick)
    if (show != MSBDRStripHidden && calmForPic)
        for (NSString *b in items) {
            UIView *st = stageOf[b];
            NSNumber *at = gRStripPicAt[b];
            BOOL on = DMRStripStageOnScreen(st);
            if (on && MSBDRStripPicDue(gRStripPics[b] != nil, at ? now - at.doubleValue : 1e9, on) && ![gRStripPicAsking containsObject:b]) { DMRStripPicture(st, b, @"the strip shows"); break; }
        }
    DMRStripSysHoverUpdate(gDMPointerAttached && (gRStripMayRevealNow || gRStripReveal == 1));
}

// ---- the pointer ----
// The pointer's place from SpringBoard's system gestures window of the iPad (every pointer move on that display reaches it): at the strip's edge
// while it stepped aside, it comes out; past the band, its reveal ends a moment later. Only while wanted: a trackpad or mouse attached and the
// strip stepped aside with something to show, or out by the pointer.
static void DMRStripSysHoverSeen(UIHoverGestureRecognizer *g) {
    UIView *v = g.view;
    BOOL inside = g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
    CFTimeInterval now = CACurrentMediaTime();
    if (!inside) { if (gRStripReveal == 1 && !gRStripPointerOutAt) gRStripPointerOutAt = now; return; }
    UIScreen *s = [UIScreen mainScreen];
    CGPoint p = [v convertPoint:[g locationInView:v] toCoordinateSpace:s.coordinateSpace];
    if (gRStripReveal == 1) {
        if (MSBDRStripPointerLeft(p.x, gRStripBand, gRStripRight)) { if (!gRStripPointerOutAt) gRStripPointerOutAt = now; }
        else gRStripPointerOutAt = 0;
        return;
    }
    if (!gRStripMayRevealNow || !MSBDRStripPointerAtEdge(p.x, s.bounds.size.width, gRStripRight)) return;
    if (p.y < gRStripSpan.y - 40.0 || p.y > MSBDRMaxY(gRStripSpan) + 40.0) return;   // (at the edge beside the cards, not in the corners)
    gRStripReveal = 1; gRStripPointerOutAt = 0;
    DM_FEATURE_MARK("recent-strip-reveal-pointer");
    DMLog(@"[recentstrip] the pointer at the edge: the strip comes out");
    DMRStripTick();
}
static void DMRStripSysHoverUpdate(BOOL want) {
    UIWindow *w = gRStripSysHoverWindow;
    if (want && gRStripSysHover && w && !w.hidden) return;
    if (!want) {
        if (gRStripSysHover) { [gRStripSysHover.view removeGestureRecognizer:gRStripSysHover]; gRStripSysHover = nil; gRStripSysHoverWindow = nil; }
        return;
    }
    if (gRStripSysHover) { [gRStripSysHover.view removeGestureRecognizer:gRStripSysHover]; gRStripSysHover = nil; }
    for (UIWindow *x in DMAllWindows()) {
        if (x.screen != [UIScreen mainScreen] || ![NSStringFromClass([x class]) isEqualToString:@"_UISystemGestureWindow"]) continue;
        UIHoverGestureRecognizer *h = [[DMPtrHoverRecognizer alloc] initWithTarget:[DMRStripTarget shared] action:@selector(sysHover:)];
        h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;
        [x addGestureRecognizer:h];
        gRStripSysHover = h; gRStripSysHoverWindow = x;
        return;
    }
    static BOOL told = NO;   // (said once)
    if (!told) { told = YES; DMLog(@"[recentstrip] no system gestures window on the iPad's screen: the pointer at the edge cannot bring the strip out (Window > Show Recent Windows can)"); }
}

// ---- a pick, and the Window menu's row ----
static void DMRStripPick(DMRStripCard *card) {
    NSString *b = card.bundle;
    if (!b.length || gRStripShown == MSBDRStripHidden) return;
    DMRStripTouched();
    gRStripPicked = [b copy]; gRStripPickedAt = CACurrentMediaTime();
    if (gRStripReveal == 2) DMRStripRevealEnd(@"a pick");
    DM_FEATURE_MARK("recent-strip-pick");
    DMLog([NSString stringWithFormat:@"[recentstrip] picked %@ (slot %lu): it comes forward, the window in front takes its slot", b, (unsigned long)[gRStripItems indexOfObject:b]]);
    if (gNativeActive) DMNativeSetActive(nil);   // (an app's window comes forward: the native windows step back, as the Mac Switcher's pick)
    // (what a Dock tap on that app does: shown again if minimized, that engine's own raise, over a full-screen app too)
    if (!DMSurfaceWindowForApp(b)) DMRaiseStageForBundle(b);
    dispatch_async(dispatch_get_main_queue(), ^{ DMRStripTick(); });   // (the swap at once, not at the next tick)
}
// Window > Show Recent Windows: offered while the strip has stepped aside with something to show.
static BOOL DMRStripMenuOffered(void) { return DMRStripOn() && gRStripMayRevealNow && gRStripItems.count > 0; }
static void DMRStripMenuReveal(void) {
    if (!DMRStripOn() || !gRStripMayRevealNow) return;
    gRStripReveal = 2; DMRStripTouched();
    DM_FEATURE_MARK("recent-strip-reveal-menu");
    DMLog(@"[recentstrip] Window > Show Recent Windows: the strip comes out");
    DMRStripTick();
}

// ---- debug (rstrip: the state, read-only; rstrip_reveal: as the Window menu's row; rstrip_edge: as the pointer at the edge; rstrip_pick_<n>: a
// tap on the nth card) ----
static BOOL DMRStripTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"rstrip"]) {
        NSMutableString *t = [NSMutableString stringWithFormat:@"[rstrip] on %d (pref %d), shown %d, reveal %d, may reveal %d, front %@, order %@, items %@, band {%.0f, %.0f, %.0f, %.0f}, cards' part {%.0f, %.0f, %.0f, %.0f}, right %d, pictures",
            DMRStripOn(), gRStripPref, (int)gRStripShown, gRStripReveal, gRStripMayRevealNow, gRStripFront.length ? gRStripFront : @"none", [gRStripOrder componentsJoinedByString:@" "],
            [gRStripItems componentsJoinedByString:@" "], gRStripBand.x, gRStripBand.y, gRStripBand.w, gRStripBand.h, gRStripSpan.x, gRStripSpan.y, gRStripSpan.w, gRStripSpan.h, gRStripRight];
        for (NSString *b in gRStripPics) [t appendFormat:@" %@ %.0fx%.0f %.0f s", b, gRStripPics[b].bounds.size.width, gRStripPics[b].bounds.size.height, CACurrentMediaTime() - [gRStripPicAt[b] doubleValue]];
        [t appendFormat:@"; window %@ level %.1f hidden %d; system hover %@; layouts %u", gRStripWindow ? @"made" : @"none", gRStripWindow.windowLevel, gRStripWindow.hidden, gRStripSysHover ? @"on" : @"off", gRStripLayouts];
        DMLog(t);
        return YES;
    }
    if ([cmd isEqualToString:@"rstrip_reveal"]) { DMRStripMenuReveal(); return YES; }
    if ([cmd isEqualToString:@"rstrip_edge"]) {
        if (gRStripMayRevealNow) { gRStripReveal = 1; gRStripPointerOutAt = 0; DMLog(@"[rstrip] as the pointer at the edge"); DMRStripTick(); }
        else DMLog(@"[rstrip] the strip has not stepped aside: nothing to bring out");
        return YES;
    }
    if ([cmd hasPrefix:@"rstrip_pick_"]) {
        NSInteger i = [[cmd substringFromIndex:12] integerValue];
        NSString *b = i >= 0 && i < (NSInteger)gRStripItems.count ? gRStripItems[(NSUInteger)i] : nil;
        DMRStripCard *c = b ? gRStripCards[b] : nil;
        if (c) DMRStripPick(c); else DMLog([NSString stringWithFormat:@"[rstrip] no card %ld", (long)i]);
        return YES;
    }
    return NO;
}
