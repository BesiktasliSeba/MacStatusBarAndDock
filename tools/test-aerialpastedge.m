// test-aerialpastedge.m: Mac test (Mac Catalyst: UIKit on the Mac) of an Aerial window dragged past the screen's left, right and bottom edges, as on
// every engine (1.8.8.3, GitHub #19): the window follows the finger from where it was at touch-down on both axes, only its title bar's
// top held under the menu bar; the place it is let go at (or a drag cut short leaves it at) is kept at once, ours and Aerial's own remembered frame
// for the screen's shape, so Aerial's fit pass keeps it there; Aerial's Lock moves nothing; Aerial's Trim baseline goes with the window.
// Runs the real code cut out of statusbar/StatusBar.x by test-aerialpastedge.sh: Aerial 5's drag section (the guard that notes where a touch went
// down, DMA5DragFollow and what it uses, -dragTrace: on Aerial's stage recogniser, -areaDrag: on 5.1's drag area), Aerial 3.0's drag hooks (the
// %hook AerialStage body of -handlePan:, DMAerialPanBefore ... DMAerialGestureAfter), DMRememberStageFrame with DMSetStageIntent, DMKeepStagePlace
// and DMAerial5SyncState, DMA5WindowFromStage. Aerial's own steps are played by KStage as they read in Aerial's binaries: its drag step (3.0's
// -handlePan:, the same min / max pair in 5.0's and 5.1's): the centre moved by the recogniser's travel, then clamped to half the stage's size from
// each edge of its window, x and y; nothing while it is locked; the trim baseline offset by its move; the frame saved for the screen's shape at the
// end. Its fit pass: a saved frame that fits by size is put back as it is. Aerial 5's step lags the finger at its start (it moves only from there).
// Aerial's recogniser is a real UIPanGestureRecognizer whose state, touches and travel the test sets, its targets sent in UIKit's order (Aerial's
// own first, then ours).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define DM_FEATURE_MARK(name) do { } while (0)
#define DMTestFlag(path) 0
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
static UIView *gRoot;   // (Aerial's window: the screen, 1194 x 834, an 11-inch iPad in landscape)
static CGRect KScreenBounds(void) { return gRoot.bounds; }
static int gAerialFlavor = 5;
static BOOL gKMacGeometry = YES;   // (Aerial 5's Mac look: its stage is the window grown by its margins)
static BOOL DMA5MacGeometry(void) { return gAerialFlavor == 5 && gKMacGeometry; }
static UIEdgeInsets gA5Insets = {13.0, 6.0, 20.0, 6.0};
static CGFloat DMA5StageShift(void) { return MAX(0.0, 24.0 - gA5Insets.top); }
static UIEdgeInsets DMA5InsetsOf(UIView *stage) { return gA5Insets; }   // (the code before 1.8.8.3 used it in the drag)
static const CGFloat kStageBarHeight = 24.0;
static CGFloat DMTopLimit(void) { return 24.0; }   // (right under the 24 pt menu bar)
static CGFloat DMAutoHideTitleShiftOf(UIView *stage) { return 0.0; }
static CGFloat DMAutoHideShiftOf(UIView *stage) { return 0.0; }
static BOOL DMAutoHideTopEdgeTouch(UITouch *t) { return NO; }
static BOOL DMTopEdgeTitleBarTouch(UITouch *t) { return NO; }
static const void *kStageGestureKey = &kStageGestureKey, *kStageEnteringKey = &kStageEnteringKey, *kStageClosingKey = &kStageClosingKey;
static const void *kStageIntentKey = &kStageIntentKey, *kStageIntentSizeKey = &kStageIntentSizeKey, *kStageByOrientKey = &kStageByOrientKey;
static const void *kA5BornKey = &kA5BornKey, *kA5EntranceTargetKey = &kA5EntranceTargetKey;
static NSMutableDictionary<NSString *, NSValue *> *gLastWindowFrames;
static BOOL DMStageMinimized(UIView *stage) { return NO; }
static void DMA5HoldStageAt(UIView *stage, CGRect target, CFTimeInterval until) { }
static NSString *DMOrientKey(void) { CGSize s = KScreenBounds().size; return s.width > s.height ? @"L" : @"P"; }
static int gKSnaps, gKTitleRec, gKBehind, gKForget, gKSaved;
static void DMSnapMoveEnded(UIView *st) { gKSnaps++; }
static void DMTitleRecordHandEnded(UIView *v, UIGestureRecognizerState s) { gKTitleRec++; }
static void DMBehindDockMoveEnded(UIView *st) { gKBehind++; }
static void DMFitGroupForget(NSString *b) { gKForget++; }
static void DMSaveWindowState(void) { gKSaved++; }
static NSMutableArray<UIView *> *gKStages;
static NSArray<UIView *> *DMAerialStages(void) { return gKStages; }
static SEL DMAerialSel(NSString *name) { return NSSelectorFromString(name); }
static const void *kKInnerKey = &kKInnerKey;
static UIView *DMStageInnerView(UIView *stage) { return objc_getAssociatedObject(stage, kKInnerKey); }
static NSString *DMStageBundle(UIView *stage);
static void DMKeepStagePlace(UIView *stage, CGRect frame);
static void DMSetStageIntent(UIView *stage, CGRect frame);
static void DMRememberStageFrame(UIView *stage);

#include "ape-chain.inc"   // (DMAerial5SyncState, DMKeepStagePlace, DMSetStageIntent, DMRememberStageFrame, DMA5WindowFromStage)
#include "ape-30.inc"      // (Aerial 3.0's drag: DMAerialPanBefore ... DMAerialGestureAfter)
#include "ape-drag.inc"    // (Aerial 5's drag section: the guard, DMA5DragFollow and what it uses, -dragTrace:, -areaDrag:)

// ---- an Aerial window: its stage, with Aerial's own ivars (the names and types our code reads), its drag step and its fit pass
@interface KStage : UIView {
@public
    BOOL _lockMode, _trimMode, _hasLandscapeState, _hasPortraitState;
    CGRect _trimBaselineFrame, _landscapeFrame, _portraitFrame;
    CGAffineTransform _landscapeTransform, _portraitTransform;
}
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic) BOOL lagsStart;   // (Aerial 5: its step moves only from its start on)
- (void)aerialPan:(UIPanGestureRecognizer *)g;
- (void)aerialFit;
- (void)k_origPan:(id)g;
- (void)handlePan:(id)gesture;
@end
static NSString *DMStageBundle(UIView *stage) { return [stage isKindOfClass:[KStage class]] ? ((KStage *)stage).bundle : nil; }
@implementation KStage
- (void)aerialPan:(UIPanGestureRecognizer *)g {
    if (_lockMode) return;   // (locked: its step does nothing)
    UIView *sv = self.superview;
    if (!sv) return;
    UIGestureRecognizerState s = g.state;
    if (s == UIGestureRecognizerStateBegan && self.lagsStart) { [g setTranslation:CGPointZero inView:sv]; return; }
    CGPoint c0 = self.center, t = [g translationInView:sv], c = CGPointMake(c0.x + t.x, c0.y + t.y);
    CGSize B = sv.bounds.size;
    CGFloat hw = self.bounds.size.width / 2.0, hh = self.bounds.size.height / 2.0;
    c.x = hw <= B.width - hw ? fmin(fmax(c.x, hw), B.width - hw) : B.width / 2.0;
    c.y = hh <= B.height - hh ? fmin(fmax(c.y, hh), B.height - hh) : B.height / 2.0;
    self.center = c;
    if (_trimMode && !CGRectIsEmpty(_trimBaselineFrame)) _trimBaselineFrame = CGRectOffset(_trimBaselineFrame, c.x - c0.x, c.y - c0.y);
    [g setTranslation:CGPointZero inView:sv];
    if (s == UIGestureRecognizerStateEnded || s == UIGestureRecognizerStateCancelled) {   // (-_saveCurrentStateForOrientation)
        if (B.width > B.height) { _landscapeFrame = self.frame; _landscapeTransform = CGAffineTransformIdentity; _hasLandscapeState = YES; }
        else { _portraitFrame = self.frame; _portraitTransform = CGAffineTransformIdentity; _hasPortraitState = YES; }
    }
}
- (void)aerialFit {   // (-_adjustStageToFitScreenIfNeeded: a remembered frame for this shape that fits by size goes back as it is)
    CGSize B = self.superview.bounds.size;
    BOOL land = B.width > B.height;
    CGRect f = land ? _landscapeFrame : _portraitFrame;
    if (!(land ? _hasLandscapeState : _hasPortraitState) || f.size.width > B.width - 20.0 || f.size.height > B.height - 20.0) return;
    self.frame = f;
}
- (void)k_origPan:(id)g { [self aerialPan:g]; }
#include "ape-hook.inc"   // (the %hook AerialStage body of -handlePan:, Aerial 3.0)
@end

// ---- the finger: a touch where it went down, and Aerial's recogniser (its state, place and travel set here; its targets sent in UIKit's order)
@interface KTouch : UITouch
@property (nonatomic) CGPoint kAt;   // (in the screen)
@end
@implementation KTouch
- (CGPoint)locationInView:(UIView *)v { return v ? [gRoot convertPoint:self.kAt toView:v] : self.kAt; }
@end
@interface KPan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState kState;
@property (nonatomic) NSUInteger kTouches;
@property (nonatomic) CGPoint kHere, kMoved;   // (in the screen; the travel since Aerial's last step)
@property (nonatomic) BOOL kOn;
@property (nonatomic, copy) void (^kSend)(void);
@end
@implementation KPan
- (UIGestureRecognizerState)state { return self.kState; }
- (NSUInteger)numberOfTouches { return self.kTouches; }
- (CGPoint)locationInView:(UIView *)v { return v ? [gRoot convertPoint:self.kHere toView:v] : self.kHere; }
- (CGPoint)translationInView:(UIView *)v { return self.kMoved; }
- (void)setTranslation:(CGPoint)t inView:(UIView *)v { self.kMoved = t; }
- (BOOL)isEnabled { return self.kOn; }
- (void)setEnabled:(BOOL)on {
    BOOL was = self.kOn; self.kOn = on;
    if (was && !on && (self.kState == UIGestureRecognizerStateBegan || self.kState == UIGestureRecognizerStateChanged)) {   // (UIKit: cancelled, the action sent)
        self.kState = UIGestureRecognizerStateCancelled; if (self.kSend) self.kSend(); self.kState = UIGestureRecognizerStatePossible;
    }
}
@end

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL RectIs(CGRect r, CGRect w) { return Near(r.origin.x, w.origin.x) && Near(r.origin.y, w.origin.y) && Near(r.size.width, w.size.width) && Near(r.size.height, w.size.height); }
static NSString *R(CGRect r) { return NSStringFromCGRect(r); }
static KStage *gStage; static UIView *gArea; static UIGestureRecognizer *gGuard;
enum { KStageRec, KAreaRec, KHook30 };
static CGRect Drawn(void) { return DMA5WindowFromStage(gStage.frame); }
static CGRect StageForWindow(CGRect w) {   // (Aerial 5's stage for a drawn window: grown by its margins; 3.0 and Aerial's own look: the window)
    if (!DMA5MacGeometry()) return w;
    return CGRectMake(w.origin.x - 6.0, w.origin.y, w.size.width + 12.0, w.size.height + 9.0);
}
static void Setup(int flavor, BOOL mac) {
    gKLog = [NSMutableArray array]; gLastWindowFrames = [NSMutableDictionary dictionary];
    gAerialFlavor = flavor; gKMacGeometry = mac;
    gKSnaps = gKTitleRec = gKBehind = gKForget = gKSaved = 0;
    gRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1194, 834)];
    gStage = [[KStage alloc] initWithFrame:StageForWindow(CGRectMake(297, 200, 600, 400))];
    gStage.bundle = @"com.apple.mobilenotes"; gStage.lagsStart = flavor == 5;
    [gRoot addSubview:gStage];
    UIView *inner = [[UIView alloc] initWithFrame:DMA5MacGeometry() ? CGRectMake(6, 13, 600, 376) : CGRectMake(0, 24, 600, 376)];
    [gStage addSubview:inner]; objc_setAssociatedObject(gStage, kKInnerKey, inner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gArea = [[UIView alloc] initWithFrame:CGRectMake(0, 0, gStage.bounds.size.width, 33)]; [gStage addSubview:gArea];   // (5.1's drag area over the top strip)
    gGuard = [[UIGestureRecognizer alloc] initWithTarget:nil action:NULL]; [gStage addGestureRecognizer:gGuard];
    objc_setAssociatedObject(gStage, kA5DragGuardKey, gGuard, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (the stage's own guard, as DMAerial5DragGuard sets it)
    gKStages = [NSMutableArray arrayWithObject:gStage];
}
static void Send(KPan *g, int how, UIGestureRecognizerState s) {
    g.kState = s;
    if (how == KHook30) [gStage handlePan:g];
    else if (how == KStageRec) { [gStage aerialPan:g]; [[DMA5DragGuard shared] dragTrace:g]; }   // (Aerial's target first, then ours)
    else { [gStage aerialPan:g]; [[DMA5DragGuard shared] areaDrag:g]; }   // (5.1's area calls the stage's step, then our target)
    if (s == UIGestureRecognizerStateEnded || s == UIGestureRecognizerStateCancelled) g.kState = UIGestureRecognizerStatePossible;
}
// A drag by the title bar: the finger goes down at `down` (the screen), the recogniser begins gKBegin pt further along x (its threshold: 12 here;
// test-pastedgeparity.m plays the ways the iPads showed), then moves. Its travel is counted from there, as UIKit counts a pan's (none at its start:
// 1.8.8.3 review -- the A12Z's and the M1's reads; this harness had the way before the start in it, which only Aerial 3.0's start read). The touch is
// offered first to our guard (Aerial 5) or to our title strip's double tap, which notes it on Aerial 3.0 (DMAerial30NoteDown).
static CGFloat gKBegin = 12.0;
static KPan *Down(int how, CGPoint down) {
    KPan *g = [[KPan alloc] initWithTarget:nil action:NULL];
    g.kOn = YES; g.kTouches = 1;
    [(how == KAreaRec ? gArea : gStage) addGestureRecognizer:g];
    __weak KPan *wg = g; g.kSend = ^{ KPan *s = wg; if (s) { if (how == KHook30) [gStage handlePan:s]; } };
    KTouch *t = [[KTouch alloc] init]; t.kAt = down;
    if (how != KHook30)   // (Aerial 5: every touch in the window is offered to our guard first; on its recogniser as that one's delegate, on the area through the stage's guard)
        [[DMA5DragGuard shared] gestureRecognizer:(how == KStageRec ? g : gGuard) shouldReceiveTouch:t];
    else DMAerial30NoteDown(gStage, t);   // (Aerial 3.0: our title strip's double tap is offered it, TitleBarTap.h)
    g.kHere = CGPointMake(down.x - gKBegin, down.y); g.kMoved = CGPointZero;
    Send(g, how, UIGestureRecognizerStateBegan);
    return g;
}
static void Move(KPan *g, int how, CGPoint p) {
    g.kMoved = CGPointMake(g.kMoved.x + p.x - g.kHere.x, g.kMoved.y + p.y - g.kHere.y); g.kHere = p;
    Send(g, how, UIGestureRecognizerStateChanged);
}
static void Path(KPan *g, int how, CGPoint to) {   // (a few steps on the way, then there)
    CGPoint a = g.kHere;
    for (int i = 1; i <= 4; i++) Move(g, how, CGPointMake(a.x + (to.x - a.x) * i / 4.0, a.y + (to.y - a.y) * i / 4.0));
}
static void End(KPan *g, int how, UIGestureRecognizerState s) { Send(g, how, s); }
static int PastLines(void) { int n = 0; for (NSString *l in gKLog) if ([l containsString:@"past the screen's edge"]) n++; return n; }
// (the place it ends at is kept: ours, and on Aerial 5 its own remembered frame for this shape, which its fit pass puts back as it is; on Aerial 3.0
//  our hook on that pass answers it with ours, DMEnforceStageFrame, so only ours is read there)
static BOOL Kept(void) {
    NSValue *in = objc_getAssociatedObject(gStage, kStageIntentKey);
    CGRect f = gStage.frame;
    if (!in || !RectIs(in.CGRectValue, f)) return NO;
    if (gAerialFlavor == 3) return YES;
    BOOL ok = gStage->_hasLandscapeState && RectIs(gStage->_landscapeFrame, f);
    [gStage aerialFit];
    return ok && RectIs(gStage.frame, f);
}
static NSString *What(int how) { return how == KStageRec ? @"Aerial 5, its stage recogniser" : how == KAreaRec ? @"Aerial 5.1, its drag area" : @"Aerial 3.0, our -handlePan: hook"; }

int main(void) {
    @autoreleasepool {
        CGPoint bar = CGPointMake(857, 210);   // (on the title bar, 40 pt in from its right end: the window is 297..897 x 200..600 as drawn)
        for (int how = KStageRec; how <= KHook30; how++) {
            int fl = how == KHook30 ? 3 : 5;
            NSString *w = What(how);
            // left: about 9/10 of the window past the left edge
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(20, 210)); End(g, how, UIGestureRecognizerStateEnded);
              CGRect d = Drawn();
              Check(RectIs(d, CGRectMake(-540, 200, 600, 400)), [NSString stringWithFormat:@"%@: dragged to x 20, let go: the window where the finger has it, 540 pt past the left edge (%@; Aerial's own step stops it %@)", w, R(d), fl == 5 ? @"6 pt in, at its stage's margin" : @"at the edge"]);
              Check(Kept(), [NSString stringWithFormat:@"  ... its place kept at once, ours and Aerial's own remembered frame: Aerial's fit pass (a light or dark change, a window opening) leaves it there (%@)", w]);
              Check(PastLines() == 1, [NSString stringWithFormat:@"  ... logged once: \"let go past the screen's edge\" (%@)", w]);
              Check(gKSnaps == 1 && gKTitleRec == (how == KHook30 ? 1 : 0), [NSString stringWithFormat:@"  ... the end of a move as before: the snap's step once (%@)", w]); }
            // right
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(1190, 210)); End(g, how, UIGestureRecognizerStateEnded);
              Check(RectIs(Drawn(), CGRectMake(630, 200, 600, 400)) && Kept(), [NSString stringWithFormat:@"%@: to x 1190: past the right edge where the finger has it (%@), kept", w, R(Drawn())]); }
            // bottom: the title bar down near the screen's bottom (behind a Dock there)
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(857, 804)); End(g, how, UIGestureRecognizerStateEnded);
              Check(RectIs(Drawn(), CGRectMake(297, 794, 600, 400)) && Kept(), [NSString stringWithFormat:@"%@: down to y 804: the title bar at y 794, the window past the bottom (%@; Aerial's own step keeps the stage inside), kept", w, R(Drawn())]); }
            // the extreme: held by the bar's far end, a sliver left at the side
            Setup(fl, fl == 5);
            { KPan *g = Down(how, CGPointMake(893, 210)); Path(g, how, CGPointMake(2, 210)); End(g, how, UIGestureRecognizerStateEnded);
              CGRect d = Drawn();
              Check(RectIs(d, CGRectMake(-594, 200, 600, 400)) && Kept(), [NSString stringWithFormat:@"%@: held 4 pt from the bar's right end, to x 2: 6 pt of the window left on the screen, the point held under the finger (%@)", w, R(d)]); }
            // the top: under the menu bar, during the drag and at the end
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(700, -40));
              CGRect mid = Drawn();
              End(g, how, UIGestureRecognizerStateEnded);
              Check(Near(mid.origin.y, 24.0) && Near(Drawn().origin.y, 24.0) && Near(Drawn().origin.x, 140.0),
                    [NSString stringWithFormat:@"%@: up into the menu bar: the title bar held right under it (y 24) while it moves and at the end, x where the finger has it (%@)", w, R(Drawn())]); }
            // cut short past the edge (a system gesture took the touch)
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(20, 210)); End(g, how, UIGestureRecognizerStateCancelled);
              Check(RectIs(Drawn(), CGRectMake(-540, 200, 600, 400)) && Kept() && gKSnaps == 0 && gKBehind == 1 && PastLines() == 1,
                    [NSString stringWithFormat:@"%@: a drag cut short past the left edge: left where the finger had it (%@, not Aerial's cancel step inside), kept, no snap, behind the Dock judged", w, R(Drawn())]); }
            // Aerial's Lock
            Setup(fl, fl == 5); gStage->_lockMode = YES;
            { CGRect f0 = gStage.frame; KPan *g = Down(how, bar); Path(g, how, CGPointMake(20, 400)); End(g, how, UIGestureRecognizerStateEnded);
              Check(RectIs(gStage.frame, f0) && PastLines() == 0, [NSString stringWithFormat:@"%@: a window in Aerial's Lock: neither Aerial's step nor ours moves it (%@)", w, R(gStage.frame)]); }
            // Aerial's Trim mode: its baseline goes with the window
            Setup(fl, fl == 5); gStage->_trimMode = YES; gStage->_trimBaselineFrame = gStage.frame;
            { CGRect f0 = gStage.frame; KPan *g = Down(how, bar); Path(g, how, CGPointMake(20, 600)); End(g, how, UIGestureRecognizerStateEnded);
              CGRect b = gStage->_trimBaselineFrame, f = gStage.frame;
              Check(Near(b.origin.x - f0.origin.x, f.origin.x - f0.origin.x) && Near(b.origin.y - f0.origin.y, f.origin.y - f0.origin.y) && Near(b.size.width, f0.size.width),
                    [NSString stringWithFormat:@"%@: in Aerial's Trim mode the trim baseline moved as far as the window (%@ for %@)", w, R(b), R(f)]); }
            // an ordinary drag inside the screen: exactly the finger's way, nothing logged
            Setup(fl, fl == 5);
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(700, 400)); End(g, how, UIGestureRecognizerStateEnded);
              Check(RectIs(Drawn(), CGRectMake(140, 390, 600, 400)) && PastLines() == 0 && Kept(), [NSString stringWithFormat:@"%@: a drag inside the screen goes the finger's way (%@), no past-the-edge line", w, R(Drawn())]); }
        }
        // Aerial 5: a start point that is not this drag's (60 pt or more off as the recogniser begins, every engine's limit): Aerial's own move, as before
        Setup(5, YES);
        { KPan *g = [[KPan alloc] initWithTarget:nil action:NULL]; g.kOn = YES; g.kTouches = 1; [gStage addGestureRecognizer:g];
          KTouch *t = [[KTouch alloc] init]; t.kAt = CGPointMake(787, 210); [[DMA5DragGuard shared] gestureRecognizer:g shouldReceiveTouch:t];
          g.kHere = CGPointMake(857, 210); g.kMoved = CGPointZero; Send(g, KStageRec, UIGestureRecognizerStateBegan);
          Path(g, KStageRec, CGPointMake(20, 210)); End(g, KStageRec, UIGestureRecognizerStateEnded);
          Check(Near(Drawn().origin.x, 6.0) && PastLines() == 0, [NSString stringWithFormat:@"Aerial 5: a touch-down 70 pt from where the drag began is not its start: no follow, Aerial's own step stops the window at its margin (%@, as before)", R(Drawn())]); }
        // (1.8.8.3 review) a quick finger: UIKit begins the pan 52 pt after the touch-down (the 17.5.1 device pass): the window the finger's whole way,
        // past the left edge, each way of Aerial's (40 pt was the limit before: Aerial 5's own step kept it inside, Aerial 3.0's trailed by 52)
        for (int how = KStageRec; how <= KHook30; how++) {
            int fl = how == KHook30 ? 3 : 5;
            Setup(fl, fl == 5); gKBegin = 52.0;
            { KPan *g = Down(how, bar); Path(g, how, CGPointMake(20, 210)); End(g, how, UIGestureRecognizerStateEnded);
              Check(RectIs(Drawn(), CGRectMake(-540, 200, 600, 400)) && Kept(), [NSString stringWithFormat:@"%@: a quick finger (the pan begun 52 pt after the touch-down): the finger's whole way past the left edge (%@)", What(how), R(Drawn())]); }
            gKBegin = 12.0;
        }
        // Aerial 3.0: no touch-down noted (none offered to our title strip's double tap): from where UIKit began the pan, as before the review
        Setup(3, NO);
        { KPan *g = [[KPan alloc] initWithTarget:nil action:NULL]; g.kOn = YES; g.kTouches = 1; [gStage addGestureRecognizer:g];
          __weak KPan *wg = g; g.kSend = ^{ KPan *s = wg; if (s) [gStage handlePan:s]; };
          g.kHere = CGPointMake(845, 210); g.kMoved = CGPointZero; Send(g, KHook30, UIGestureRecognizerStateBegan);
          Path(g, KHook30, CGPointMake(20, 210)); End(g, KHook30, UIGestureRecognizerStateEnded);
          Check(RectIs(Drawn(), CGRectMake(-528, 200, 600, 400)), [NSString stringWithFormat:@"Aerial 3.0: no touch-down noted: followed from where its recogniser began (%@)", R(Drawn())]); }
        // Aerial 5 in its own look (debug: our theme off): the stage is the window, its top Aerial's own (the screen's top)
        Setup(5, NO);
        { KPan *g = Down(KStageRec, bar); Path(g, KStageRec, CGPointMake(20, -40)); End(g, KStageRec, UIGestureRecognizerStateEnded);
          Check(RectIs(gStage.frame, CGRectMake(-540, 0, 600, 400)), [NSString stringWithFormat:@"Aerial 5 in its own look: past the left edge too, the top at the screen's (Aerial's own) (%@)", R(gStage.frame)]); }
        // Aerial 3.0: a drag that starts inside the app is refused at its start: nothing of ours moves the window
        Setup(3, NO);
        { CGRect f0 = gStage.frame; KPan *g = [[KPan alloc] initWithTarget:nil action:NULL]; g.kOn = YES; g.kTouches = 1; [gStage addGestureRecognizer:g];
          __weak KPan *wg = g; g.kSend = ^{ KPan *s = wg; if (s) [gStage handlePan:s]; };
          g.kHere = CGPointMake(857, 412); g.kMoved = CGPointMake(0, 12); Send(g, KHook30, UIGestureRecognizerStateBegan);
          Check(RectIs(gStage.frame, CGRectOffset(f0, 0, 12)) && !objc_getAssociatedObject(g, &kA5DragDownKey) && !objc_getAssociatedObject(gStage, &kA5DragDownKey) && gKSnaps == 0,
                [NSString stringWithFormat:@"Aerial 3.0: a drag from inside the app is cancelled at its start: only Aerial's own cancel step moved it (%@), no follow of ours", R(gStage.frame)]); }
    }
    printf("test-aerialpastedge: %d of %d checks pass\n", gChecks - gFails, gChecks);
    return gFails;
}
