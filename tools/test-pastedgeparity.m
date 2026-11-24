// test-pastedgeparity.m: Mac test (Mac Catalyst: UIKit on the Mac) that the same title-bar drag ends in the same place on every window engine
// (1.8.8.3, GitHub #19; KT 23 Nov: "We should match the other engines in this version"). Built three times by test-pastedgeparity.sh, PAR_ENGINE:
//  1 our Stage Manager engine: test-smpastedge.m's harness (its own checks left out) runs the real -[DMSMTitleBar dm_pan:] (and its touch filter,
//    where the finger went down: 1.8.8.3) and the past-edge glue;
//    the place is where the drop asks Stage Manager to put the window (DMSMAttrsFitScreen), then where its layout passes keep it (iPadOS 16's
//    constraint step and the 17 / 18 pass end ask DMSMPastEdgeHeldAt; a window past an edge that it does not keep would be clamped inside);
//  2 Aerial: test-aerialpastedge.m's harness (its own checks left out) runs the real drag code with Aerial's own steps as they read in its binaries:
//    5.x by its stage recogniser and by 5.1's drag area, 3.0 by our -handlePan: hook; the place after Aerial's fit pass (5.x: its own, which puts its
//    remembered frame back; 3.0: ours, which puts our kept place back);
//  3 Zetsu (our title-bar pan, DMZetsuBarPan, and where it reads the finger) and MilkyWay4 (our catch-up's touch-down note and its target on
//    MilkyWay4's title-bar recogniser; MilkyWay4's own move is a stand-in: its window from where its recogniser began by the finger's way since).
// Each prints, per case, the window as drawn (title bar and app) where it ends, and whether its place is kept (ours, or Aerial's own memory);
// test-pastedgeparity.sh compares them: every engine within 2 pt of the others and of the finger's travel with only the top held under the menu bar.
// The screen: 1194 x 834 pt (an 11-inch iPad in landscape), the menu bar 24 pt, the Dock at the bottom; the window 600 x 400 pt as drawn at
// (297, 200); the finger goes down on its title bar, the recogniser begins further on, then four steps to the end, let go there. Every case is
// played with the recogniser begun 12, 28, 52 and 59 pt after the touch-down (1.8.8.3 review: UIKit's own begin, as the iPads showed it -- up to
// 17.5 pt on the iPad 2, 28 on the A12Z, 52 on the 17.5.1 for a quick finger -- and just inside every engine's 60 pt limit), its travel counted
// from there (none at its start, as UIKit counts a pan's) for every engine.

#if PAR_ENGINE == 1
#define main spe_harness_main
#include "test-smpastedge.m"
#undef main
#elif PAR_ENGINE == 2
#define main ape_harness_main
#include "test-aerialpastedge.m"
#undef main
#else
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
static void DMLog(NSString *s) { (void)s; }
static BOOL DMTestFlag(const char *path) { (void)path; return NO; }
#define DM_FEATURE_MARK(name) do { } while (0)
static CGFloat DMTopLimit(void) { return 24.0; }   // (right under the 24 pt menu bar, as every other part of this test)
static const void *kStageGestureKey = &kStageGestureKey;
static int gPRemembered;
static void DMSnapMoveEnded(UIView *st) { (void)st; }   // (the snap: one step on every engine, not this test's)
static void DMTitleRecordHandEnded(UIView *v, UIGestureRecognizerState s) { (void)v; (void)s; }
static void DMBehindDockMoveEnded(UIView *st) { (void)st; }
static void DMZetsuFixScale(UIWindow *w) { (void)w; }
static void DMRememberStageFrame(UIView *st) { (void)st; gPRemembered++; }   // (Zetsu: its place kept)
static void DMMWRememberSoon(UIView *win) { (void)win; gPRemembered++; }      // (MilkyWay4: its place kept)
static void DMFitGroupForget(NSString *b) { (void)b; }
static void DMSaveWindowState(void) { }
static NSString *DMZetsuWindowBundle(UIWindow *w) { (void)w; return @"com.apple.mobilenotes"; }
// ---- the screen (its coordinate space: a fixed view), a Zetsu window (a UIWindow whose frame is in the screen's points), a MilkyWay4 window
static UIView *gPSpace;
@interface PScreen : UIScreen
@end
@implementation PScreen
- (CGRect)bounds { return CGRectMake(0, 0, 1194, 834); }
- (id<UICoordinateSpace>)coordinateSpace { return gPSpace; }
@end
static PScreen *gPScreen;
@interface PZWindow : UIWindow
@end
@implementation PZWindow
- (UIScreen *)screen { return gPScreen; }
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id<UICoordinateSpace>)s {
    if (s == (id<UICoordinateSpace>)gPSpace) return CGPointMake(p.x + self.frame.origin.x, p.y + self.frame.origin.y);
    return [super convertPoint:p toCoordinateSpace:s];
}
@end
static CGPoint PIn(CGPoint onScreen, UIView *v) {   // (a point of the screen in a view: a Zetsu window by its frame, a view on the screen's space by UIKit)
    if ([v isKindOfClass:[PZWindow class]]) return CGPointMake(onScreen.x - v.frame.origin.x, onScreen.y - v.frame.origin.y);
    if (v && v != gPSpace && [v isDescendantOfView:gPSpace]) return [gPSpace convertPoint:onScreen toView:v];
    return onScreen;
}
@interface PTouch : UITouch
@property (nonatomic) CGPoint at;   // (in the screen)
@end
@implementation PTouch
- (CGPoint)locationInView:(UIView *)v { return PIn(self.at, v); }
@end
@interface PPan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState kState;
@property (nonatomic) CGPoint at;   // (in the screen)
@end
@implementation PPan
- (UIGestureRecognizerState)state { return self.kState; }
- (CGPoint)locationInView:(UIView *)v { return PIn(self.at, v); }
- (NSUInteger)numberOfTouches { return 1; }
@end
@interface AXWindowView : UIView   // (MilkyWay4's window, as our code finds it by its class name)
@end
@implementation AXWindowView
@end
@interface TMWCatchUp : NSObject <UIGestureRecognizerDelegate>
@end
#include "par-zetsu.inc"   // (StatusBar.x: the touch-down and touch-now notes, DMZetsuPanPointOnScreen, DMPanDownPointOnScreen, DMZetsuBarPan)
static void DMZetsuRaise(UIWindow *w) { (void)w; }
#include "par-mw.inc"      // (StatusBar.x: kMWDownKey..., DMMWResizeCatchUp's touch-down note and -dragged:, as TMWCatchUp)
#endif

// ---- the cases, every engine: where the finger goes down on the title bar and where it is let go
typedef struct { const char *name; CGFloat dx, dy, tx, ty; const char *what; } PCase;
static const PCase kPCases[] = {
    {"left", 857, 210, 20, 210, "held 40 pt in from the bar's right end, to x 20: 540 pt past the left edge"},
    {"right", 337, 210, 1174, 210, "held 40 pt in from the bar's left end, to x 1174: 540 pt past the right edge"},
    {"bottom", 857, 210, 857, 804, "down to y 804: the title bar behind the Dock, the window past the bottom"},
    {"sliver", 893, 210, 2, 210, "held 4 pt from the bar's right end, to x 2: a 6 pt sliver left on the screen"},
    {"top", 857, 210, 700, 5, "up into the menu bar: the title bar held right under it"},
    {"corner", 857, 210, 100, 800, "to the bottom-left corner: past the left edge and the bottom"},
    {"inside", 857, 210, 700, 300, "a drag inside the screen, above the Dock"},
};
static const CGRect kPStart = {{297, 200}, {600, 400}};
static CGFloat gPBegin = 12.0;   // (how far from the touch-down UIKit begins the pan, this round)
static void POut(const char *engine, const PCase *c, CGRect r, BOOL kept) {
    printf("FRAME %s %s@%g %.3f %.3f %.3f %.3f\nKEPT %s %s@%g %d\n", engine, c->name, gPBegin, r.origin.x, r.origin.y, r.size.width, r.size.height, engine, c->name, gPBegin, kept ? 1 : 0);
}
static CGPoint PStep(const PCase *c, int i) {   // (the finger: 0 where the recogniser begins, gPBegin pt along x from the touch-down; 1 to 4 on to the end)
    CGPoint b = CGPointMake(c->dx - gPBegin, c->dy);
    return CGPointMake(b.x + (c->tx - b.x) * i / 4.0, b.y + (c->ty - b.y) * i / 4.0);
}

#if PAR_ENGINE == 1
static void PPlay(const PCase *c) {
    const CGSize ipad = CGSizeMake(1194, 834);
    ClearRecords();
    Setup(ipad, kNotes, CGRectMake(kPStart.origin.x, kPStart.origin.y + kSMBarH, kPStart.size.width, kPStart.size.height - kSMBarH), NO);
    // (the finger as UIKit reports it: down on the bar -- the bar's touch filter sees it --, the pan begun 12 pt further and its translation from
    //  there, four steps, let go at the last; the screen is the window's space here)
    NSMutableArray<NSValue *> *finger = [NSMutableArray array];
    for (int i = 0; i <= 4; i++) [finger addObject:[NSValue valueWithCGPoint:PStep(c, i)]];
    [finger addObject:finger.lastObject];
    DragTouch(DownOn(CGPointMake(c->dx, c->dy), UITouchTypeDirect), finger, UIGestureRecognizerStateEnded, 1);
    DMSMAttributedSize sz;
    if (!gTAsked || !DMSMAttrAttributedSize(gTAsked, &sz)) { POut("sm", c, CGRectNull, NO); return; }
    CGSize s = CGSizeMake(sz.normalizedSize.width * sz.referenceBounds.size.width, sz.normalizedSize.height * sz.referenceBounds.size.height);
    CGPoint at = CGPointMake(gTAsked.center.x * ipad.width, gTAsked.center.y * ipad.height), keep = at;
    CGRect asked = CGRectMake(at.x - s.width / 2.0, at.y - s.height / 2.0 - kSMBarH, s.width, s.height + kSMBarH);
    // (Stage Manager's layout passes then: a window past an edge stays only where the lookup keeps it; inside the screen nothing is asked)
    BOOL past = DMSMPastEdgeOut(asked, CGRectMake(0, 0, ipad.width, ipad.height)), held = DMSMPastEdgeHeldAt(at, s, ipad, &keep);
    if (held) at = keep;
    POut("sm", c, CGRectMake(at.x - s.width / 2.0, at.y - s.height / 2.0 - kSMBarH, s.width, s.height + kSMBarH), !past || held);
}
static void PPlayAll(void) { for (size_t i = 0; i < sizeof kPCases / sizeof kPCases[0]; i++) PPlay(&kPCases[i]); }
#elif PAR_ENGINE == 2
static void PPlayHow(const PCase *c, int how, const char *engine) {
    int fl = how == KHook30 ? 3 : 5;
    gKBegin = gPBegin;   // (the Aerial harness's recogniser begun as far on)
    Setup(fl, fl == 5);
    KPan *g = Down(how, CGPointMake(c->dx, c->dy));
    for (int i = 1; i <= 4; i++) Move(g, how, PStep(c, i));
    End(g, how, UIGestureRecognizerStateEnded);
    NSValue *in = objc_getAssociatedObject(gStage, kStageIntentKey);
    BOOL kept = in && RectIs(in.CGRectValue, gStage.frame);
    if (fl == 5) { [gStage aerialFit]; kept = kept && RectIs(gStage.frame, in.CGRectValue); }   // (Aerial 5's fit pass: a light or dark change, a window opening)
    POut(engine, c, Drawn(), kept);
}
static void PPlayAll(void) {
    for (size_t i = 0; i < sizeof kPCases / sizeof kPCases[0]; i++) {
        PPlayHow(&kPCases[i], KStageRec, "aerial5"); PPlayHow(&kPCases[i], KAreaRec, "aerial51"); PPlayHow(&kPCases[i], KHook30, "aerial30");
    }
}
#else
static void PZetsu(const PCase *c) {
    gPRemembered = 0;
    PZWindow *w = [[PZWindow alloc] initWithFrame:kPStart];
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPStart.size.width, 24)]; [w addSubview:bar];
    PPan *g = [[PPan alloc] initWithTarget:nil action:NULL]; [bar addGestureRecognizer:g];
    PTouch *t = [PTouch new]; t.at = CGPointMake(c->dx, c->dy);
    DMZetsuNoteTouchDown(w, [NSSet setWithObject:t]);   // (its touch watcher: where the finger went down)
    g.kState = UIGestureRecognizerStateBegan; g.at = PStep(c, 0); [[DMZetsuBarPan shared] pan:g];
    for (int i = 1; i <= 4; i++) { g.kState = UIGestureRecognizerStateChanged; g.at = PStep(c, i); [[DMZetsuBarPan shared] pan:g]; }
    g.kState = UIGestureRecognizerStateEnded; [[DMZetsuBarPan shared] pan:g];
    POut("zetsu", c, w.frame, gPRemembered > 0);
}
static void PMilkyWay(const PCase *c) {
    gPRemembered = 0;
    AXWindowView *win = [[AXWindowView alloc] initWithFrame:kPStart]; [gPSpace addSubview:win];
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kPStart.size.width, 24)]; [win addSubview:bar];
    PPan *g = [[PPan alloc] initWithTarget:nil action:NULL]; [bar addGestureRecognizer:g];
    UIGestureRecognizer *note = [[UIGestureRecognizer alloc] initWithTarget:nil action:NULL]; [bar addGestureRecognizer:note];
    TMWCatchUp *ours = [TMWCatchUp new];
    PTouch *t = [PTouch new]; t.at = CGPointMake(c->dx, c->dy);
    [ours gestureRecognizer:note shouldReceiveTouch:t];   // (our note of where the finger went down on the bar)
    CGRect start = win.frame; CGPoint began = PStep(c, 0);
    for (int i = 0; i <= 5; i++) {   // (MilkyWay4's own target first -- its window from where its recogniser began --, then ours, in UIKit's order)
        g.kState = i == 0 ? UIGestureRecognizerStateBegan : i == 5 ? UIGestureRecognizerStateEnded : UIGestureRecognizerStateChanged;
        if (i <= 4) g.at = PStep(c, i);
        if (i > 0) win.frame = CGRectOffset(start, g.at.x - began.x, g.at.y - began.y);
        [ours dragged:g];
    }
    POut("milkyway4", c, win.frame, gPRemembered > 0);
    [win removeFromSuperview];
}
static void PPlayAll(void) {
    gPSpace = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1194, 834)];
    gPScreen = [PScreen new];
    for (size_t i = 0; i < sizeof kPCases / sizeof kPCases[0]; i++) { PZetsu(&kPCases[i]); PMilkyWay(&kPCases[i]); }
}
#endif

int main(void) {
    @autoreleasepool {
        const CGFloat begins[] = {12.0, 28.0, 52.0, 59.0};
        for (size_t j = 0; j < sizeof begins / sizeof begins[0]; j++) {
            gPBegin = begins[j];
            for (size_t i = 0; i < sizeof kPCases / sizeof kPCases[0]; i++) {
                const PCase *c = &kPCases[i];
                printf("CASE %s@%g %.3f %.3f %.3f %.3f %s, the pan begun %g pt on\n", c->name, gPBegin, kPStart.origin.x + c->tx - c->dx, fmax(24.0, kPStart.origin.y + c->ty - c->dy), kPStart.size.width, kPStart.size.height, c->what, gPBegin);
            }
            PPlayAll();
        }
    }
    return 0;
}
