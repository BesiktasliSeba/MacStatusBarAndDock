// test-smpastedge.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a window moved partly past the screen's edges with our Stage Manager engine
// (1.8.8.3, GitHub #19: as Zetsu's and MilkyWay4's windows can: the drag follows the finger, only the top is held under the menu bar, a
// resize by hand leaves the window where it is). The rule is statusbar/SMPastEdge.h (the real header, or a made-to-fail copy, from the work folder).
// The real code is cut out of statusbar/StatusBar.x by test-smpastedge.sh (UIKit's main screen asked as TMainScreen(), the iPad's screen here): the
// title bar's drag (-[DMSMTitleBar dm_pan:] and its @interface), the past-edge glue (the record, its lookup, the drag's hold, the drop's record, our
// requests' keep, a resize by hand's follow), DMSMCardDesk and DMSMAttrsFitScreen (our requests' fit), and iPadOS 16's before / after around Stage
// Manager's stage-area constraint. iPadOS 17 and 18's pass (SMEngineAPI.h DMSM17PassEnd) is test-smlayout17's. SpringBoard's side -- the screens and their desktops, a window's attributes, the snap, the
// place asked for, Stage Manager's own constraint -- is the stand-ins below. Real UIKit views: the card's transform and its frame on the screen are
// UIKit's own.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "SMWindowKey.h"
#include "SMFit.h"
#include "SMPastEdge.h"

// ---- what the real code logs, marks and asks
static NSMutableArray<NSString *> *gTLog;
static void DMLog(NSString *s) { [gTLog addObject:s ?: @""]; }
static BOOL DMTestFlag(const char *path) { (void)path; return NO; }
static NSCountedSet<NSString *> *gTMarks;
#define DM_FEATURE_MARK(name) [gTMarks addObject:@name]
static BOOL gTFree = YES;
static BOOL DMSMEngine(void) { return gTFree; }
static BOOL DMSMFree(void) { return gTFree; }
#if defined(__x86_64__)
#define DMSM_MSG_STRET objc_msgSend_stret   // (as SMEngineAPI.h: a struct over 16 bytes comes back through this entry point on Intel)
#else
#define DMSM_MSG_STRET objc_msgSend
#endif
static int gTDockSide = 0;   // (Settings > Dock > Position: 0 the bottom, 1 left, 2 right -- in landscape only, as DockSide.h has it)
static int DMDockSideNow(CGSize screen) { return screen.width > screen.height ? gTDockSide : 0; }
enum { MSBDDockBottom = 0 };
static NSMutableArray<NSString *> *gTFront;
static void DMSMBringToFront(NSString *key) { [gTFront addObject:key ?: @"(nil)"]; }
static void DMTitleRecordMovedSM(NSString *key) { (void)key; }
static BOOL gTSnap; static CGPoint gTSnapAt;
static BOOL DMSMSnapMoveTarget(NSString *key, UIView *card, CGPoint t, CGPoint *at) { (void)key; (void)card; (void)t; if (gTSnap) *at = gTSnapAt; return gTSnap; }
#ifndef SPE_REAL_BAKE   // (1.8.8.4: a drag that starts on a title bar slid down with the menu bar -- the real one runs in test-autohidetop.sh; none is slid here)
static CGFloat DMAutoHideSMBake(UIView *bar) { (void)bar; return 0.0; }
#else
static CGFloat DMAutoHideSMBake(UIView *bar);
#endif

// ---- the screens: the iPad's (it is UIKit's main screen here) and a TV
@interface KScreen : UIScreen
@property (nonatomic) CGSize size;
@property (nonatomic, weak) UIWindow *space;
@end
@implementation KScreen
- (CGRect)bounds { return CGRectMake(0, 0, self.size.width, self.size.height); }
- (id<UICoordinateSpace>)coordinateSpace { return self.space; }
@end
@interface KWindow : UIWindow
@property (nonatomic, strong) KScreen *kscreen;
@end
@implementation KWindow
- (UIScreen *)screen { return self.kscreen; }
@end
static KScreen *gIPad, *gTV;
static KWindow *gWin;
// (UIKit's main screen as the real code asks it -- [UIScreen mainScreen], written TMainScreen() in the cut-out copy by test-smpastedge.sh: the iPad here)
static UIScreen *TMainScreen(void) { return gIPad; }
static BOOL gTAutoHide = NO;   // (the iPad's Dock hides itself: its desktop down to the screen's bottom)
// The desktop of a screen (whole windows: our title bar and the card), as DMSMUsableAreaForIdentity has it: the iPad's under its 24 pt menu bar and
// down to the Dock's line (117 pt Dock, 2 pt gap) -- with the Dock at a side, beside it and down to the bottom --; the TV's under its bar, above its
// 100 pt Dock.
static CGFloat gTIPadDock = 117.0, gTIPadTop = 24.0;
#ifdef SPE_REAL_DESK   // (test-pastedgeparity.sh: StatusBar.x's own desktop and stage top, below -- spe-desk.inc)
static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut);
#else
static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {
    if ([identity isEqual:@"tv"]) {
        CGSize s = gTV.size;
        if (screenOut) *screenOut = s;
        return CGRectMake(0, 24, s.width, s.height - 100 - 2 - 24);
    }
    CGSize s = gIPad.size;
    if (screenOut) *screenOut = s;
    int side = DMDockSideNow(s);
    if (side == 1) return CGRectMake(130, gTIPadTop, s.width - 130, s.height - gTIPadTop);
    if (side == 2) return CGRectMake(0, gTIPadTop, s.width - 130, s.height - gTIPadTop);
    CGFloat bottom = gTAutoHide ? s.height : s.height - gTIPadDock - 2.0;
    return CGRectMake(0, gTIPadTop, s.width, bottom - gTIPadTop);
}
#endif
static BOOL gTNoTVIdentity = NO;   // (the TV's display not read: no identity for it)
static id DMSMIdentityOfScreen(UIScreen *sc) { return sc == gTV ? (gTNoTVIdentity ? nil : @"tv") : @"main"; }
// The screen of a container's size (StatusBar.x DMSMScreenOfSize): the iPad's in either shape, or the TV's
static UIScreen *DMSMScreenOfSize(CGSize size) {
    if (CGSizeEqualToSize(size, gIPad.size) || CGSizeEqualToSize(size, CGSizeMake(gIPad.size.height, gIPad.size.width))) return gIPad;
    return CGSizeEqualToSize(size, gTV.size) ? gTV : nil;
}
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"main"]; }

// ---- a window's attributes (SBDisplayItemLayoutAttributes): its size as fractions of its reference, its centre as fractions of the screen
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;
@interface TAttrs : NSObject
@property (nonatomic) CGSize norm; @property (nonatomic) CGRect ref; @property (nonatomic) long long type; @property (nonatomic) CGPoint center; @property (nonatomic) long policy;
@end
@implementation TAttrs
- (TAttrs *)dup { TAttrs *a = [TAttrs new]; a.norm = _norm; a.ref = _ref; a.type = _type; a.center = _center; a.policy = _policy; return a; }
@end
static TAttrs *Attrs(CGSize pts, CGPoint centrePts, CGSize screen) {
    TAttrs *a = [TAttrs new];
    a.norm = CGSizeMake(pts.width / screen.width, pts.height / screen.height); a.ref = CGRectMake(0, 0, screen.width, screen.height); a.type = 0;
    a.center = CGPointMake(centrePts.x / screen.width, centrePts.y / screen.height);
    return a;
}
static BOOL DMSMIsAttrs(id a) { return [a isKindOfClass:[TAttrs class]]; }
static long DMSMPolicyOf(id attrs) { return DMSMIsAttrs(attrs) ? ((TAttrs *)attrs).policy : 0; }
static BOOL DMSMAttrsFullScreen(id attrs) { return DMSMIsAttrs(attrs) && ((TAttrs *)attrs).policy == 2; }
static BOOL DMSMAttrAttributedSize(id attrs, DMSMAttributedSize *out) {
    if (!DMSMIsAttrs(attrs) || !out) return NO;
    TAttrs *a = attrs; out->normalizedSize = a.norm; out->referenceBounds = a.ref; out->type = a.type; return YES;
}
static BOOL DMSMAttrCenter(id attrs, CGPoint *out) { if (!DMSMIsAttrs(attrs) || !out) return NO; *out = ((TAttrs *)attrs).center; return YES; }
static id DMSMAttrWith(id attrs, DMSMAttributedSize s, CGPoint c, long long policy, long long time) {
    (void)time;
    if (!DMSMIsAttrs(attrs) || !isfinite(c.x) || !isfinite(c.y)) return nil;
    TAttrs *a = [(TAttrs *)attrs dup]; a.norm = s.normalizedSize; a.ref = s.referenceBounds; a.type = s.type; a.center = c; a.policy = (long)policy;
    return a;
}
static BOOL DMSMSizeRefitPending(double *placedTop) { (void)placedTop; return NO; }
static id DMSMAttrsRefitTop(id attrs, NSString *who, BOOL old24, BOOL sized, double placedTop) { (void)attrs; (void)who; (void)old24; (void)sized; (void)placedTop; return nil; }
// the stages: each window key's attributes; the keys in SpringBoard's stages (nil: a stage not read whole)
static NSMutableDictionary<NSString *, TAttrs *> *gTWindows;
static NSSet<NSString *> *gTPresent;
static id DMSMStageOf(NSString *key) { return gTWindows[key] ? @"stage" : nil; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut) { TAttrs *a = stage ? gTWindows[key] : nil; if (attrsOut) *attrsOut = a; return a ? key : nil; }
static NSArray *DMSMRecentStages(void) { return @[@"stage"]; }
static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages) { (void)stages; return gTPresent; }
// the place asked for (normalized centre) and what our request then hands Stage Manager: the real DMSMAttrsFitScreen on the window's attributes
static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle);
static int gTPlaces; static CGPoint gTPlace; static TAttrs *gTAsked;
static BOOL DMSMSetWindowGeometry(NSString *key, CGPoint center, CGSize size) {
    (void)size;
    gTPlaces++; gTPlace = center;
    TAttrs *a = [gTWindows[key] dup];
    if (!a) return NO;
    a.center = center;
    gTAsked = DMSMAttrsFitScreen(a, gWin.kscreen == gTV ? @"tv" : nil, NO, key);   // (the display its stage is on, as DMSMRequestWindow asks)
    return YES;
}
// iPadOS 16's model (SBMutableChamoisOverlappingModel) and the checked calls the before / after use
static BOOL gSMLoneCenterNext = NO;
static BOOL DMSMRectSane(CGRect r) { return isfinite(r.origin.x) && isfinite(r.size.width) && r.size.width >= 100.0 && r.size.height >= 100.0; }
static BOOL DMSMSigOK(id obj, SEL sel, NSString *sig, const char *what) { (void)sig; (void)what; return [obj respondsToSelector:sel]; }
static NSString *DMSMSigObj(void) { return @""; }
static NSString *DMSMSigSizeFor(void) { return @""; }
static NSString *DMSMSigCenterFor(void) { return @""; }
static NSString *DMSMSigSetCenter(void) { return @""; }
static NSString *DMSMSigRect(void) { return @""; }
static NSString *DMSMItemBundle(id item) { return [item isKindOfClass:[NSString class]] ? item : nil; }
@interface TModel : NSObject
@property (nonatomic, strong) NSArray *items; @property (nonatomic) CGRect containerBounds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *centers, *sizes;
@property (nonatomic) int sets;
@end
@implementation TModel
- (CGSize)sizeForItem:(id)it { return [self.sizes[it] CGSizeValue]; }
- (CGPoint)centerForItem:(id)it { return [self.centers[it] CGPointValue]; }
- (void)setCenter:(CGPoint)c forItem:(id)it { self.sets++; self.centers[it] = [NSValue valueWithCGPoint:c]; }
@end
// Stage Manager's own step (-_constrainModelVertically: / Horizontally:toStageArea:): every window's centre kept inside the area on one axis
static void TAppleConstrain(TModel *m, CGRect area, int vertical) {
    for (id it in m.items) {
        CGPoint c = [m centerForItem:it]; CGSize s = [m sizeForItem:it];
        if (vertical) c.y = fmax(fmin(c.y, CGRectGetMaxY(area) - s.height / 2.0), CGRectGetMinY(area) + s.height / 2.0);
        else c.x = fmax(fmin(c.x, CGRectGetMaxX(area) - s.width / 2.0), CGRectGetMinX(area) + s.width / 2.0);
        m.centers[it] = [NSValue valueWithCGPoint:c];
    }
}

// ---- the drag: a pan whose state and travel the test sets: kT UIKit's translation (from where it began the pan), kAt the finger (in the window's
//      points), kTouches its touches; and a touch on the bar (where it went down, its window and phase), for the bar's -gestureRecognizer:shouldReceiveTouch:
@interface KPan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState kState;
@property (nonatomic) CGPoint kT, kAt;
@property (nonatomic) NSUInteger kTouches;
@end
@implementation KPan
- (UIGestureRecognizerState)state { return self.kState; }
- (CGPoint)translationInView:(UIView *)v { (void)v; return self.kT; }
- (CGPoint)locationInView:(UIView *)v { return v ? [v convertPoint:self.kAt fromView:nil] : self.kAt; }
- (NSUInteger)numberOfTouches { return self.kTouches; }
@end
@interface KTouch : UITouch
@property (nonatomic) CGPoint kAt;
@property (nonatomic) UITouchPhase kPhase;
@property (nonatomic) UITouchType kType;
@property (nonatomic, weak) UIWindow *kWin;
@end
@implementation KTouch
- (CGPoint)locationInView:(UIView *)v { return v ? [v convertPoint:self.kAt fromView:nil] : self.kAt; }
- (UIWindow *)window { return self.kWin; }
- (UITouchPhase)phase { return self.kPhase; }
- (UITouchType)type { return self.kType; }
@end
static BOOL gTOnResizeEdge;   // (the pointer marks a resize band: SpringBoard's live resize, not the bar's drag)
static BOOL DMSMPointerOnResizeEdge(UIView *card) { (void)card; return gTOnResizeEdge; }

#include "spe-decl.inc"   // (kSMBarH, the drag's globals, the @interface DMSMTitleBar: StatusBar.x's)
#ifdef SPE_REAL_DESK
#include "spe-desk.inc"   // (StatusBar.x's DMTopLimit, DMSMUsableAreaForIdentity, the _statusBarHeight answer and DMSMStageTopByDisplay)
#endif
#include "spe-glue.inc"   // (the past-edge glue, DMSMCardDesk, DMSMAttrsFitScreen, iPadOS 16's before / after: StatusBar.x's)
@implementation DMSMTitleBar
#include "spe-pan.inc"    // (-gestureRecognizer:shouldReceiveTouch: and -dm_pan:)
@end

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }
static BOOL NearPt(CGPoint a, CGFloat x, CGFloat y) { return fabs(a.x - x) < 0.01 && fabs(a.y - y) < 0.01; }

static NSString *const kNotes = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-6C1F0A2E";
static NSString *const kClock = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-11AA22BB";
static UIView *gSup, *gCard; static DMSMTitleBar *gBar;
static KScreen *Screen(CGSize size, KWindow **win) {
    KWindow *w = [[KWindow alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    KScreen *s = [KScreen new]; s.size = size; s.space = w; w.kscreen = s;
    if (win) *win = w;
    return s;
}
// The iPad at `ipad`, a window `key` with its card at `card` (the stage view covers the screen), on the iPad or on the TV (1920 x 1080).
static void Setup(CGSize ipad, NSString *key, CGRect card, BOOL onTV) {
    gTLog = [NSMutableArray array]; gTMarks = [NSCountedSet set]; gTFront = [NSMutableArray array];
    gTSnap = NO; gTPlaces = 0; gTPlace = CGPointZero; gTAsked = nil; gTFree = YES; gTAutoHide = NO; gTIPadDock = 117.0; gTIPadTop = 24.0; gTNoTVIdentity = NO; gTOnResizeEdge = NO;
    gSMDragUntil = 0; gSMBehindDock = nil; gSMDockHeightBySize = [NSMutableDictionary dictionary];
    KWindow *iw = nil, *tw = nil;
    gIPad = Screen(ipad, &iw); gTV = Screen(CGSizeMake(1920, 1080), &tw);
    gWin = onTV ? tw : iw;
    CGSize scr = gWin.kscreen.size;
    gSup = [[UIView alloc] initWithFrame:CGRectMake(0, 0, scr.width, scr.height)]; [gWin addSubview:gSup];
    gCard = [[UIView alloc] initWithFrame:card]; [gSup addSubview:gCard];
    gBar = [DMSMTitleBar new]; gBar.bundle = DMSMKeyBundle(key); gBar.key = key; gBar.card = gCard;
    if (!gTWindows) gTWindows = [NSMutableDictionary dictionary];
    gTWindows[key] = Attrs(card.size, CGPointMake(CGRectGetMidX(card), CGRectGetMidY(card)), scr);
}
static void ClearRecords(void) { gSMPastEdge = nil; gSMPastEdgeOrder = nil; gSMPastEdgeResizeKey = nil; gTWindows = [NSMutableDictionary dictionary]; gTPresent = nil; }
// The drag: Began, a Changed at each of `moves`, then Ended at `last`. Returns the card's transform after the last move.
static CGAffineTransform gTLastMove;
static void Drag(NSArray<NSValue *> *moves, CGPoint last) {
    KPan *g = [KPan new];
    g.kState = UIGestureRecognizerStateBegan; g.kT = CGPointZero; [gBar dm_pan:g];
    for (NSValue *m in moves) { g.kState = UIGestureRecognizerStateChanged; g.kT = m.CGPointValue; [gBar dm_pan:g]; }
    gTLastMove = gCard.transform;
    g.kState = UIGestureRecognizerStateEnded; g.kT = last; [gBar dm_pan:g];
}
static NSArray<NSValue *> *Steps(CGPoint to) {
    return @[[NSValue valueWithCGPoint:CGPointMake(to.x / 3, to.y / 3)], [NSValue valueWithCGPoint:CGPointMake(to.x * 2 / 3, to.y * 2 / 3)], [NSValue valueWithCGPoint:to]];
}
// A drag as UIKit reports it (1.8.8.3): the finger goes down at `down` (the window's points; the bar is asked -gestureRecognizer:shouldReceiveTouch:
// for it), UIKit begins the pan at at[0] -- its hysteresis on --, its translation counted from there; a Changed at each point after it; let go at
// the last (end: Ended or Cancelled). touches: the pan's (1, or 2 for a second finger). The card's transform after each step: gTSteps; where the drop
// put the card (its centre's way): Moved().
static NSMutableArray<NSValue *> *gTSteps;
static CGPoint gTCentre0;
static KTouch *DownOn(CGPoint down, UITouchType type) {
    KTouch *t = [KTouch new]; t.kAt = down; t.kPhase = UITouchPhaseBegan; t.kType = type; t.kWin = gWin;
    return t;
}
static BOOL DragTouch(KTouch *t, NSArray<NSValue *> *at, UIGestureRecognizerState end, NSUInteger touches) {
    KPan *g = [KPan new]; g.kTouches = touches;
    BOOL took = t ? [gBar gestureRecognizer:g shouldReceiveTouch:t] : YES;
    if (t) t.kPhase = UITouchPhaseMoved;
    gTSteps = [NSMutableArray array]; gTCentre0 = gCard.center;
    CGPoint b = at[0].CGPointValue;
    for (NSUInteger i = 0; i < at.count; i++) {
        CGPoint p = at[i].CGPointValue;
        g.kState = i == 0 ? UIGestureRecognizerStateBegan : i + 1 == at.count ? end : UIGestureRecognizerStateChanged;
        g.kAt = p; g.kT = CGPointMake(p.x - b.x, p.y - b.y);
        if (t) t.kAt = p;
        if (i + 1 == at.count) gTLastMove = gCard.transform;
        [gBar dm_pan:g];
        [gTSteps addObject:[NSValue valueWithCGAffineTransform:gCard.transform]];
    }
    if (t) t.kPhase = UITouchPhaseEnded;
    return took;
}
static CGPoint Moved(void) { return CGPointMake(gCard.center.x - gTCentre0.x, gCard.center.y - gTCentre0.y); }
static CGAffineTransform StepAt(NSUInteger i) { return gTSteps[i].CGAffineTransformValue; }
static NSArray<NSValue *> *Pts(int n, ...) {   // (n points, x and y each)
    NSMutableArray *a = [NSMutableArray array]; va_list v; va_start(v, n);
    for (int i = 0; i < n; i++) { double x = va_arg(v, double), y = va_arg(v, double); [a addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]]; }
    va_end(v);
    return a;
}
static NSArray<NSValue *> *Rec(NSString *key) { return gSMPastEdge[key]; }
static BOOL RecIs(NSString *key, CGFloat cx, CGFloat cy, CGFloat w, CGFloat h, CGFloat sw, CGFloat sh) {
    NSArray<NSValue *> *r = Rec(key);
    return r.count == 3 && NearPt(r[0].CGPointValue, cx, cy) && Near(r[1].CGSizeValue.width, w) && Near(r[1].CGSizeValue.height, h) && Near(r[2].CGSizeValue.width, sw) && Near(r[2].CGSizeValue.height, sh);
}
static int LogCount(NSString *part) { int n = 0; for (NSString *l in gTLog) if ([l containsString:part]) n++; return n; }
// iPadOS 16's step around one window `A` (Stage Manager's own constraint on one axis between our before and after): where it ends
static CGPoint Step16(CGPoint c, CGSize s, CGRect area, int vertical, NSArray **heldOut) {
    TModel *m = [TModel new];
    m.items = @[@"A"]; m.containerBounds = CGRectMake(0, 0, 1366, 1024);
    m.centers = [@{@"A": [NSValue valueWithCGPoint:c]} mutableCopy]; m.sizes = [@{@"A": [NSValue valueWithCGSize:s]} mutableCopy];
    NSArray *held = DMSMPastEdgeBefore16(m, area);
    TAppleConstrain(m, area, vertical);
    DMSMPastEdgeAfter16(m, held);
    if (heldOut) *heldOut = held;
    return [m centerForItem:@"A"];
}

int main(void) {
    @autoreleasepool {
        const CGSize land = CGSizeMake(1366, 1024);   // (12.9", landscape: the desktop 24..905, the Dock's line at 1024 - 117 - 2)
        const CGRect card = CGRectMake(300, 200, 600, 400);   // (the whole window 300..900 x 176..600)

        // ==== 1. the rule (SMPastEdge.h): as Zetsu's and MilkyWay4's drags -- the top under the menu bar, nothing else held ====
        CGRect desk = CGRectMake(0, 24, 1366, 881);
        CGRect w = CGRectMake(300, 176, 600, 424);
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(w, desk), w), @"rule: a window inside the desktop stays where it is");
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectOffset(w, -700, 0), desk), CGRectOffset(w, -700, 0)), @"rule: 400 of 600 pt past the left edge: stays");
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectOffset(w, -898, 0), desk), CGRectOffset(w, -898, 0)), @"rule: 598 of 600 pt past the left edge (2 pt left on the screen, as the other engines let it): stays, no grab area held");
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectOffset(w, 1064, 0), desk), CGRectOffset(w, 1064, 0)), @"rule: past the right edge with 2 pt on the screen: stays");
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectOffset(w, 0, 800), desk), CGRectOffset(w, 0, 800)), @"rule: down past the bottom, the title bar behind the Dock (top 976): stays, as on the other engines");
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectOffset(w, 0, 840), desk), CGRectOffset(w, 0, 840)), @"rule: down until 8 pt of the title bar are left on the screen: stays");
        Check(Near(DMSMPastEdgeKeep(CGRectOffset(w, 0, -300), desk).origin.y, 24) && Near(DMSMPastEdgeKeep(CGRectOffset(w, 0, -300), desk).origin.x, 300),
              @"rule: up: never above the desktop's top (under the menu bar), x as it is");
        CGRect corner = DMSMPastEdgeKeep(CGRectOffset(w, -890, 830), desk);
        Check(Near(corner.origin.x, -590) && Near(corner.origin.y, 1006), @"rule: past the bottom-left corner: stays");
        CGRect upLeft = DMSMPastEdgeKeep(CGRectOffset(w, -890, -300), desk);
        Check(Near(upLeft.origin.x, -590) && Near(upLeft.origin.y, 24), @"rule: up and past the left edge: only the top held");
        Check(isnan(DMSMPastEdgeKeep(CGRectMake(NAN, 0, 600, 424), desk).origin.x) && CGRectEqualToRect(DMSMPastEdgeKeep(w, CGRectMake(0, 0, 0, 0)), w),
              @"rule: anything not a number, or no desktop: as it is");
        CGRect tvDesk = CGRectMake(0, 24, 1920, 954);
        Check(CGRectEqualToRect(DMSMPastEdgeKeep(CGRectMake(1900, 300, 600, 424), tvDesk), CGRectMake(1900, 300, 600, 424))
              && CGRectEqualToRect(DMSMPastEdgeKeep(CGRectMake(300, 1050, 600, 424), tvDesk), CGRectMake(300, 1050, 600, 424))
              && Near(DMSMPastEdgeKeep(CGRectMake(300, 10, 600, 424), tvDesk).origin.y, 24), @"rule: the TV's own desktop: past its right edge and its bottom stays, the top held under its bar");
        Check(NearPt(DMSMPastEdgeCardCenter(CGPointMake(-500, 400), CGSizeMake(600, 400), desk, 24), -500, 400), @"rule: a card's centre (our 24 pt bar on top) by the same rule: (-500, 400) stays");
        Check(NearPt(DMSMPastEdgeCardCenter(CGPointMake(600, 1200), CGSizeMake(600, 400), desk, 24), 600, 1200), @"rule: a card past the bottom, its bar behind the Dock: stays");
        Check(NearPt(DMSMPastEdgeCardCenter(CGPointMake(-500, 200), CGSizeMake(600, 400), desk, 24), -500, 248), @"rule: a card whose bar is over the menu bar: down under it (centre y 248)");
        CGRect scr = CGRectMake(0, 0, 1366, 1024);
        Check(!DMSMPastEdgeOut(w, scr) && DMSMPastEdgeOut(CGRectOffset(w, -301, 0), scr) && !DMSMPastEdgeOut(CGRectOffset(w, -300.4, 0), scr) && DMSMPastEdgeOut(CGRectOffset(w, 467, 0), scr)
              && DMSMPastEdgeOut(CGRectOffset(w, 0, 425), scr) && !DMSMPastEdgeOut(CGRectOffset(w, 0, -400), scr),
              @"rule: past the screen: the left, right and bottom edges by more than half a point; never the top");
        Check(DMSMPastEdgeSame(CGPointMake(10, 20), CGSizeMake(600, 400), CGSizeMake(1366, 1024), CGPointMake(10.9, 19.1), CGSizeMake(600.9, 399.1), CGSizeMake(1366, 1024))
              && !DMSMPastEdgeSame(CGPointMake(10, 20), CGSizeMake(600, 400), CGSizeMake(1366, 1024), CGPointMake(11.5, 20), CGSizeMake(600, 400), CGSizeMake(1366, 1024))
              && !DMSMPastEdgeSame(CGPointMake(10, 20), CGSizeMake(600, 400), CGSizeMake(1366, 1024), CGPointMake(10, 20), CGSizeMake(602, 400), CGSizeMake(1366, 1024))
              && !DMSMPastEdgeSame(CGPointMake(10, 20), CGSizeMake(600, 400), CGSizeMake(1024, 1366), CGPointMake(10, 20), CGSizeMake(600, 400), CGSizeMake(1366, 1024)),
              @"rule: the same place: centre and size within a point, on a screen of the same size");
        Check(DMSMPastEdgeTurnedAway(CGSizeMake(1366, 1024), CGSizeMake(1024, 1366)) && !DMSMPastEdgeTurnedAway(CGSizeMake(1366, 1024), CGSizeMake(1366, 1024))
              && !DMSMPastEdgeTurnedAway(CGSizeMake(1920, 1080), CGSizeMake(1024, 1366)) && !DMSMPastEdgeTurnedAway(CGSizeMake(1000, 1000), CGSizeMake(1000, 1000)),
              @"rule: a record of the iPad's other shape (it turned since); a TV's never; a square screen never");
        // (a resize by hand: the card as it began is a record's, within 3 pt; the card now keeps the sides not dragged)
        Check(DMSMPastEdgeSameCard(CGRectMake(-202.5, 197.6, 604, 401), CGPointMake(100, 400), CGSizeMake(600, 400))
              && !DMSMPastEdgeSameCard(CGRectMake(-196, 200, 600, 400), CGPointMake(100, 400), CGSizeMake(600, 400))
              && !DMSMPastEdgeSameCard(CGRectMake(-200, 200, 600, 404), CGPointMake(100, 400), CGSizeMake(600, 400))
              && !DMSMPastEdgeSameCard(CGRectMake(NAN, 200, 600, 400), CGPointMake(100, 400), CGSizeMake(600, 400)),
              @"rule: a resize began on a recorded window's card: every side within 3 pt (4 pt off: another)");
        CGRect from = CGRectMake(-200, 200, 600, 400);
        unsigned BR = kDMSMPastEdgeRight | kDMSMPastEdgeBottom;
        Check(DMSMPastEdgeResized(CGPointMake(150, 425), CGSizeMake(700, 450), from, BR) && DMSMPastEdgeResized(CGPointMake(0.5, 350), CGSizeMake(401, 300), from, BR)
              && !DMSMPastEdgeResized(CGPointMake(175, 425), CGSizeMake(700, 450), from, BR) && !DMSMPastEdgeResized(CGPointMake(150, 450), CGSizeMake(700, 450), from, BR),
              @"rule: the bottom-right corner dragged: the left and top sides held (bigger or smaller); a left or top side moved: not that window");
        Check(DMSMPastEdgeResized(CGPointMake(150, 400), CGSizeMake(700, 400), from, kDMSMPastEdgeRight) && !DMSMPastEdgeResized(CGPointMake(150, 425), CGSizeMake(700, 450), from, kDMSMPastEdgeRight)
              && DMSMPastEdgeResized(CGPointMake(100, 375), CGSizeMake(600, 450), from, kDMSMPastEdgeTop) && DMSMPastEdgeResized(CGPointMake(75, 425), CGSizeMake(650, 450), from, kDMSMPastEdgeLeft | kDMSMPastEdgeBottom),
              @"rule: a side dragged holds the other three; the top dragged (the pointer) holds the bottom and the sides; the bottom-left corner holds the right and the top");
        Check(!DMSMPastEdgeResized(CGPointMake(100, 400), CGSizeMake(600, 400), from, 0) && !DMSMPastEdgeResized(CGPointMake(100, 400), CGSizeMake(600, 400), from, kDMSMPastEdgeLeft | kDMSMPastEdgeRight)
              && !DMSMPastEdgeResized(CGPointMake(100, 400), CGSizeMake(600, 400), from, kDMSMPastEdgeTop | kDMSMPastEdgeBottom) && !DMSMPastEdgeResized(CGPointMake(100, 400), CGSizeMake(0, 400), from, BR),
              @"rule: no side, both sides of an axis, or no size: not a resize");

        // ==== 2. the drag and the drop (the real -dm_pan: with the real glue) ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(Near(gTLastMove.tx, -500) && Near(gTLastMove.ty, 0), @"drag: 500 pt to the left (200 pt left on the screen): the card follows the finger");
        Check(RecIs(kNotes, 100, 400, 600, 400, 1366, 1024), @"drop: past the left edge: recorded at its place (centre (100, 400), 600 x 400, on 1366 x 1024)");
        Check(gTPlaces == 1 && NearPt(gTPlace, 100.0 / 1366, 400.0 / 1024), @"drop: the place asked for is its middle as before (100, 400)");
        Check(gTAsked && NearPt(gTAsked.center, 100.0 / 1366, 400.0 / 1024) && [gTMarks containsObject:@"sm-past-edge-drop"],
              @"drop: our request keeps it there (DMSMAttrsFitScreen: not fitted inside)");
        Check(!DMSMKeySetHas(gSMBehindDock, kNotes) && gTFront.count == 1, @"drop: not behind the Dock; brought forward at the start (as before)");

        Setup(land, kNotes, card, NO);
        gTWindows[kNotes] = Attrs(CGSizeMake(601, 402), CGPointMake(600, 400), land);   // (the size Stage Manager lays it out at, a little off the card's)
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(RecIs(kNotes, 100, 400, 601, 402, 1366, 1024), @"drop: the record's size is the one its attributes give (as our requests and the passes read it), not the card's");
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-800, 0)), CGPointMake(-820, 0));
        Check(Near(gTLastMove.tx, -800), [NSString stringWithFormat:@"drag: 800 pt to the left (100 pt left on the screen): it follows the finger, no grab area holds it (travel -800, was %.1f)", gTLastMove.tx]);
        Check(RecIs(kNotes, -220, 400, 600, 400, 1366, 1024) && NearPt(gTPlace, -220.0 / 1366, 400.0 / 1024), @"drop: ... let go where the finger went on to (-820): recorded and asked there (-220, 400)");
        Check([gTMarks countForObject:@"sm-past-edge-limit"] == 0, @"drag: no stop at the sides (only the top is ever held)");
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-898, 0)), CGPointMake(-898, 0));
        Check(Near(gTLastMove.tx, -898) && RecIs(kNotes, -298, 400, 600, 400, 1366, 1024) && gTAsked && NearPt(gTAsked.center, -298.0 / 1366, 400.0 / 1024),
              @"drag and drop: held by its title bar's right end until 2 pt are left on the screen (the point the finger holds): followed, recorded, kept there, as on Zetsu");

        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(1000, 0)), CGPointMake(1000, 0));
        Check(Near(gTLastMove.tx, 1000) && RecIs(kNotes, 1600, 400, 600, 400, 1366, 1024), @"drag and drop: past the right edge (66 pt left on the screen): followed, recorded there");

        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(0, 800)), CGPointMake(0, 800));
        Check(Near(gTLastMove.ty, 800) && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024), @"drag and drop: down past the screen's bottom, its title bar behind the Dock (top 976): followed, recorded");
        Check(DMSMKeySetHas(gSMBehindDock, kNotes), @"drop: ... and it is behind the Dock too (as before)");
        Check(gTAsked && NearPt(gTAsked.center, 600.0 / 1366, 1200.0 / 1024), @"drop: our request keeps it past the bottom");
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(0, 840)), CGPointMake(0, 840));
        Check(Near(gTLastMove.ty, 840) && RecIs(kNotes, 600, 1240, 600, 400, 1366, 1024), @"drag and drop: down until 8 pt of the title bar are on the screen: followed, recorded");

        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(0, -300)), CGPointMake(0, -300));
        Check(Near(gTLastMove.ty, -152) && !Rec(kNotes), @"drag: up: held under the menu bar (top 24; it went over the menu bar before), nothing past an edge");
        Check([gTMarks countForObject:@"sm-past-edge-limit"] == 1, @"drag: the stop under the menu bar noted once per drag");
        Check(!gSMPastEdge[kNotes], @"drop: back inside the screen: the window's record goes");
        Check(gTAsked && NearPt(gTAsked.center, 600.0 / 1366, 248.0 / 1024), @"drop: ... asked at the held place (no jump at the drop)");

        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(Rec(kNotes) != nil, @"a second window past the edge recorded ...");
        Setup(land, kNotes, CGRectMake(-200, 200, 600, 400), NO);
        Drag(Steps(CGPointMake(400, 0)), CGPointMake(400, 0));
        Check(!Rec(kNotes) && gTAsked && NearPt(gTAsked.center, 500.0 / 1366, 400.0 / 1024), @"... dragged back inside: its record goes, its place asked as dropped");

        gTDockSide = 1;
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-800, -300)), CGPointMake(-800, -300));
        Check(Near(gTLastMove.tx, -800) && Near(gTLastMove.ty, -152) && !Rec(kNotes), @"the Dock at a side: the drag holds only the top, nothing is recorded");
        Check(gTAsked && Near(gTAsked.center.x * 1366, 130 + 300), @"... the drop is fitted into the desktop beside the Dock as before (every engine)");
        gTDockSide = 0;

        Setup(land, kNotes, card, NO);
        gTAutoHide = YES;
        Drag(Steps(CGPointMake(0, 830)), CGPointMake(0, 830));
        Check(Near(gTLastMove.ty, 830) && RecIs(kNotes, 600, 1230, 600, 400, 1366, 1024), @"the Dock hiding itself: down past the bottom as far as the finger goes (18 pt of its bar on the screen, no 44 pt held), recorded");
        gTAutoHide = NO;

        ClearRecords();
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(1500, 0)), CGPointMake(1500, 0));
        Check(Near(gTLastMove.tx, 1500) && RecIs(kNotes, 2100, 400, 600, 400, 1920, 1080), @"the TV: 1500 pt to the right (120 pt on the TV): recorded on the TV's own screen");
        Check(gTAsked && NearPt(gTAsked.center, 2100.0 / 1920, 400.0 / 1080), @"the TV: our request for the TV's window keeps it there");
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(0, 880)), CGPointMake(0, 880));
        Check(Near(gTLastMove.ty, 880), @"the TV: down past the TV's own Dock as far as the pointer goes (20 pt of its bar on the TV)");
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(0, -300)), CGPointMake(0, -300));
        Check(Near(gTLastMove.ty, -152), @"the TV: up: held under the TV's own menu bar");
        Setup(land, kNotes, card, YES);
        gTNoTVIdentity = YES; gTIPadTop = 100.0;
        Drag(Steps(CGPointMake(0, -100)), CGPointMake(0, -100));
        Check(Near(gTLastMove.ty, -100), [NSString stringWithFormat:@"the TV whose display is not read: its drag is never held to the iPad's desktop (under a 100 pt bar there; it follows the finger: travel %.1f)", gTLastMove.ty]);
        gTNoTVIdentity = NO; gTIPadTop = 24.0;

        ClearRecords();
        Setup(land, kNotes, card, NO);
        gTSnap = YES; gTSnapAt = CGPointMake(-100.0 / 1366, 400.0 / 1024);
        Drag(Steps(CGPointMake(-380, 0)), CGPointMake(-380, 0));
        Check(RecIs(kNotes, -100, 400, 600, 400, 1366, 1024) && NearPt(gTPlace, -100.0 / 1366, 400.0 / 1024), @"a drop that snaps: recorded where the snap puts it");
        Setup(land, kNotes, card, NO);
        gTSnap = YES; gTSnapAt = CGPointMake(300.0 / 1366, 400.0 / 1024);
        Drag(Steps(CGPointMake(-330, 0)), CGPointMake(-330, 0));
        Check(!Rec(kNotes), @"a drop 30 pt past the edge that snaps back onto it (the snap's 45 pt, every engine's): inside, its record gone");

        Setup(land, kNotes, card, NO);
        gTFree = NO;
        Drag(Steps(CGPointMake(-800, -300)), CGPointMake(-800, -300));
        Check(Near(gTLastMove.tx, -800) && Near(gTLastMove.ty, -300) && !Rec(kNotes), @"Stage Manager's own layout (debug): no hold, no record, as before");
        gTFree = YES;

        // ==== 2b. the drag follows the finger from where it went down (1.8.8.3): UIKit begins the pan 12 pt on and counts its translation from there ====
        //      (the card (300, 200) 600 x 400 under our 24 pt bar: the finger down on the bar at (700, 188); the window's way is the finger's whole way)
        ClearRecords();
        Setup(land, kNotes, card, NO);
        BOOL took = DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(6, 688.0, 188.0, 680.0, 188.0, 664.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(took && NearPt(Moved(), -500, 0), [NSString stringWithFormat:@"follow: down at x 700, UIKit's pan from x 688, let go at x 200: the window moved the finger's whole way, -500 (UIKit's translation alone: -488; moved %.1f)", Moved().x]);
        Check(CGAffineTransformIsIdentity(StepAt(0)), @"follow: no jump as the pan begins (the card still where it was)");
        Check(StepAt(1).tx < -8.0 - 0.01 && StepAt(1).tx > -12.0 - 0.01, [NSString stringWithFormat:@"follow: the first 8 pt after: the window moves more than the finger to take the 12 pt in, never more than half as much again (%.2f for 8)", StepAt(1).tx]);
        Check(Near(StepAt(2).tx, -36) && Near(StepAt(3).tx, -212) && Near(StepAt(4).tx, -500), [NSString stringWithFormat:@"follow: from 24 pt after the pan began, exactly with the finger (%.1f, %.1f, %.1f for -36, -212, -500)", StepAt(2).tx, StepAt(3).tx, StepAt(4).tx]);
        Check(RecIs(kNotes, 100, 400, 600, 400, 1366, 1024) && NearPt(gTPlace, 100.0 / 1366, 400.0 / 1024), @"follow: the drop is recorded and asked where the finger took the window (centre (100, 400))");
        Check(LogCount(@"the finger's whole way from where it went down") == 1, @"follow: the drop's log line says it followed from the touch-down");
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 670.0, 188.0, 640.0, 188.0, 610.0, 188.0, 610.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(StepAt(1).tx < -30.0 - 0.01 && StepAt(1).tx > -45.0 - 0.01 && Near(StepAt(2).tx, -90) && NearPt(Moved(), -90, 0),
              [NSString stringWithFormat:@"follow: a quick finger (UIKit's pan 30 pt on): taken in over twice that (%.1f for 30, then -90 with the finger), let go exactly there", StepAt(1).tx]);
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(3, 688.0, 188.0, 684.0, 188.0, 678.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), -22, 0), [NSString stringWithFormat:@"follow: a short drag let go 10 pt after the pan began: the whole way at the let go (-22; moved %.1f)", Moved().x]);
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 688.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateCancelled, 1);
        Check(NearPt(Moved(), -500, 0), @"follow: a drag cut short (Cancelled) moves the window the whole way too");
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 700.0, 176.0, 600.0, 100.0, 500.0, 0.0, 500.0, 0.0), UIGestureRecognizerStateEnded, 1);
        Check(Near(gTLastMove.tx, -200) && Near(gTLastMove.ty, -152) && NearPt(Moved(), -200, -152), [NSString stringWithFormat:@"follow: up into the menu bar: the whole way across, held under the menu bar (%.1f, %.1f)", Moved().x, Moved().y]);
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 700.0, 200.0, 700.0, 600.0, 700.0, 988.0, 700.0, 988.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), 0, 800) && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024) && DMSMKeySetHas(gSMBehindDock, kNotes), @"follow: down past the bottom, the whole way: recorded there, behind the Dock");
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeIndirectPointer), Pts(4, 690.0, 188.0, 400.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), -500, 0), @"follow: the pointer's press and drag (UIKit's pan 10 pt on): the pointer's whole way");
        Setup(land, kNotes, card, NO);
        gTOnResizeEdge = YES;
        took = DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeIndirectPointer), Pts(4, 690.0, 188.0, 400.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(!took, @"follow: a pointer press on a resize band is not the bar's (SpringBoard's live resize), as before");
        gTOnResizeEdge = NO;
        ClearRecords();
        Setup(land, kNotes, card, YES);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 712.0, 188.0, 1500.0, 188.0, 2200.0, 188.0, 2200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), 1500, 0) && RecIs(kNotes, 2100, 400, 600, 400, 1920, 1080), @"follow: the TV's window: the finger's whole way, recorded on the TV");
        Setup(land, kNotes, card, NO);
        {   // (a second finger put on the bar during the drag: the pan's point is the two fingers' middle; the window stays with the first finger)
            KPan *g = [KPan new]; g.kTouches = 1;
            KTouch *t = DownOn(CGPointMake(700, 188), UITouchTypeDirect);
            (void)[gBar gestureRecognizer:g shouldReceiveTouch:t]; t.kPhase = UITouchPhaseMoved; gTCentre0 = gCard.center;
            g.kState = UIGestureRecognizerStateBegan; g.kAt = t.kAt = CGPointMake(688, 188); g.kT = CGPointZero; [gBar dm_pan:g];
            g.kState = UIGestureRecognizerStateChanged; g.kAt = t.kAt = CGPointMake(600, 188); g.kT = CGPointMake(-88, 0); [gBar dm_pan:g];
            CGFloat before2 = gCard.transform.tx;
            g.kTouches = 2; g.kAt = CGPointMake(700, 300); g.kT = CGPointMake(-88, 0); [gBar dm_pan:g];   // (the second finger down at (800, 412): the middle (700, 300))
            CGFloat with2 = gCard.transform.tx, with2y = gCard.transform.ty;
            g.kAt = CGPointMake(650, 300); t.kAt = CGPointMake(550, 188); g.kT = CGPointMake(-138, 0); [gBar dm_pan:g];
            g.kTouches = 1; g.kState = UIGestureRecognizerStateEnded; g.kAt = t.kAt = CGPointMake(500, 188); g.kT = CGPointMake(-188, 0); [gBar dm_pan:g];
            Check(Near(before2, -100) && Near(with2, -100) && Near(with2y, 0) && NearPt(Moved(), -200, 0),
                  [NSString stringWithFormat:@"follow: a second finger put on the bar during the drag moves nothing; the window stays with the first finger to its let go (%.1f, %.1f -> %.1f, %.1f)", before2, with2, Moved().x, Moved().y]);
        }
        // (review: the first finger lifted while a second goes on with the pan -- UIKit goes on with the second, its translation carried on across
        //  the lift: the window goes on with the second finger from where it is, no jump; a third touch put down on the bar meanwhile is not followed)
        for (int freed = 0; freed <= 1; freed++) {
            Setup(land, kNotes, card, NO);
            KPan *g = [KPan new]; g.kTouches = 1;
            KTouch *a = nil, *b2 = nil, *c3 = nil;
            @autoreleasepool { a = DownOn(CGPointMake(700, 188), UITouchTypeDirect); b2 = DownOn(CGPointMake(800, 412), UITouchTypeDirect); c3 = DownOn(CGPointMake(300, 188), UITouchTypeDirect); }
            (void)[gBar gestureRecognizer:g shouldReceiveTouch:a]; a.kPhase = UITouchPhaseMoved; gTCentre0 = gCard.center;
            g.kState = UIGestureRecognizerStateBegan; g.kAt = a.kAt = CGPointMake(688, 188); g.kT = CGPointZero; [gBar dm_pan:g];
            g.kState = UIGestureRecognizerStateChanged; g.kAt = a.kAt = CGPointMake(600, 188); g.kT = CGPointMake(-88, 0); [gBar dm_pan:g];   // (the window -100)
            (void)[gBar gestureRecognizer:g shouldReceiveTouch:b2]; b2.kPhase = UITouchPhaseMoved;
            g.kTouches = 2; g.kAt = CGPointMake(700, 300); [gBar dm_pan:g];   // (the two fingers' middle; UIKit's translation as it was)
            a.kPhase = UITouchPhaseEnded;
            __weak KTouch *wa = a;
            if (freed) a = nil;   // (UIKit let the lifted finger's touch go: no one holds it any more)
            (void)[gBar gestureRecognizer:g shouldReceiveTouch:c3]; c3.kPhase = UITouchPhaseStationary;   // (a third finger down on the bar, still)
            g.kTouches = 1; g.kAt = b2.kAt; [gBar dm_pan:g];
            CGFloat atLift = gCard.transform.tx, atLiftY = gCard.transform.ty;
            g.kAt = b2.kAt = CGPointMake(700, 412); g.kT = CGPointMake(-188, 0); [gBar dm_pan:g];
            CGFloat on = gCard.transform.tx, onY = gCard.transform.ty;
            g.kState = UIGestureRecognizerStateEnded; g.kAt = b2.kAt = CGPointMake(650, 412); g.kT = CGPointMake(-238, 0); [gBar dm_pan:g];
            Check((!freed || !wa) && Near(atLift, -100) && Near(atLiftY, 0) && Near(on, -200) && Near(onY, 0) && NearPt(Moved(), -250, 0) && LogCount(@"another finger went on with the drag") == 1,
                  [NSString stringWithFormat:@"follow: the first finger lifted while a second goes on (%@): the window stays where it is, then goes on with the second finger to its let go, a third touch put down meanwhile not followed (%.1f, %.1f -> %.1f, %.1f -> %.1f, %.1f; want -100, -200, -250)",
                   freed ? @"its touch let go by UIKit" : @"its touch kept, ended", atLift, atLiftY, on, onY, Moved().x, Moved().y]);
        }
        // (review: the way taken in is never given back: out 40 pt from where the pan began, then back to there and to the touch-down: the window
        //  exactly with the finger all the way back, no step at the let go)
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(5, 688.0, 188.0, 648.0, 188.0, 688.0, 188.0, 700.0, 188.0, 700.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(Near(StepAt(1).tx, -52) && Near(StepAt(2).tx, -12) && Near(StepAt(3).tx, 0) && NearPt(Moved(), 0, 0),
              [NSString stringWithFormat:@"follow: the finger out 40 pt and back: the window with it all the way back (%.1f, %.1f, %.1f for -52, -12, 0), let go where it is", StepAt(1).tx, StepAt(2).tx, StepAt(3).tx]);
        // (not followed -- UIKit's translation, as before -- where the touch-down is not this drag's one finger)
        ClearRecords();
        Setup(land, kNotes, card, NO);
        KTouch *first = DownOn(CGPointMake(650, 188), UITouchTypeDirect);
        (void)[gBar gestureRecognizer:[KPan new] shouldReceiveTouch:first]; first.kPhase = UITouchPhaseStationary;
        DragTouch(DownOn(CGPointMake(750, 188), UITouchTypeDirect), Pts(4, 688.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 2);
        Check(NearPt(Moved(), -488, 0), [NSString stringWithFormat:@"not followed: a second finger down while the first is (a two-finger pan): UIKit's translation (%.1f)", Moved().x]);
        Setup(land, kNotes, card, NO);
        KTouch *gone = DownOn(CGPointMake(700, 188), UITouchTypeDirect);
        (void)[gBar gestureRecognizer:[KPan new] shouldReceiveTouch:gone]; gone.kPhase = UITouchPhaseEnded;
        DragTouch(nil, Pts(4, 688.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), -488, 0) && LogCount(@"no touch-down to follow from") == 1, @"not followed: the touch-down noted was another touch's, ended since: UIKit's translation, as its drop line says");
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 630.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), -430, 0), @"not followed: a touch-down 70 pt from where the pan began (60 pt at most, Zetsu's): UIKit's translation");
        Setup(land, kNotes, card, NO);
        KWindow *otherWin = [[KWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        KTouch *elsewhere = DownOn(CGPointMake(700, 188), UITouchTypeDirect); elsewhere.kWin = otherWin;
        DragTouch(elsewhere, Pts(4, 688.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), -488, 0), @"not followed: a touch-down in another window: UIKit's translation");
        Setup(land, kNotes, card, NO);
        DragTouch(DownOn(CGPointMake(700, 188), UITouchTypeDirect), Pts(4, 688.0, 188.0, 488.0, 188.0, 200.0, 188.0, 200.0, 188.0), UIGestureRecognizerStateEnded, 1);
        DragTouch(nil, Pts(4, 300.0, 188.0, 400.0, 188.0, 500.0, 188.0, 500.0, 188.0), UIGestureRecognizerStateEnded, 1);
        Check(NearPt(Moved(), 200, 0), @"not followed: the next drag with no touch-down seen (the last one's ended): UIKit's translation, nothing of the last drag carried over");

        // ==== 3. the records: the lookup, a turn, the Dock at a side, the cap ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(DMSMPastEdgeHeld(CGPointMake(100.5, 399.5), CGSizeMake(600, 400), land), @"lookup: the recorded place (within a point)");
        Check(!DMSMPastEdgeHeld(CGPointMake(102, 400), CGSizeMake(600, 400), land) && !DMSMPastEdgeHeld(CGPointMake(100, 400), CGSizeMake(620, 400), land)
              && !DMSMPastEdgeHeld(CGPointMake(100, 400), CGSizeMake(600, 400), CGSizeMake(1920, 1080)), @"lookup: another place, another size, another screen: no");
        gTDockSide = 2;
        Check(!DMSMPastEdgeHeld(CGPointMake(100, 400), CGSizeMake(600, 400), land) && Rec(kNotes), @"lookup: the Dock moved to a side: no (kept inside as every engine), the record stays");
        gTDockSide = 0;
        gTFree = NO;
        Check(!DMSMPastEdgeHeld(CGPointMake(100, 400), CGSizeMake(600, 400), land), @"lookup: Stage Manager's own layout (debug): no");
        gTFree = YES;
        Setup(land, kClock, card, YES);
        Drag(Steps(CGPointMake(1500, 0)), CGPointMake(1500, 0));
        Check(Rec(kNotes) && Rec(kClock), @"lookup: an iPad record and a TV record");
        gIPad.size = CGSizeMake(1024, 1366);   // (the iPad turned)
        Check(!DMSMPastEdgeHeld(CGPointMake(100, 400), CGSizeMake(600, 400), land) && !Rec(kNotes) && Rec(kClock), @"a turn: the other shape's record goes at the next lookup (every engine fits windows inside at a turn); the TV's stays");
        Check(DMSMPastEdgeHeld(CGPointMake(2100, 400), CGSizeMake(600, 400), CGSizeMake(1920, 1080)), @"... the TV's window keeps its place");
        gIPad.size = land;

        ClearRecords();
        for (int i = 0; i < 17; i++) {
            NSString *k = [NSString stringWithFormat:@"com.example.app%d|sceneID:%d", i, i];
            Setup(land, k, card, NO);
            Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        }
        Check(gSMPastEdge.count == 16 && !gSMPastEdge[@"com.example.app0|sceneID:0"] && gSMPastEdge[@"com.example.app16|sceneID:16"], @"cap: at most 16 records, the oldest goes");
        gTPresent = [NSSet setWithObjects:@"com.example.app16|sceneID:16", @"com.example.app17|sceneID:17", nil];
        Setup(land, @"com.example.app17|sceneID:17", card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(gSMPastEdge.count == 2 && gSMPastEdge[@"com.example.app16|sceneID:16"] && gSMPastEdge[@"com.example.app17|sceneID:17"], @"a new record drops those of windows no longer in any stage");
        Setup(land, @"com.example.app18", card, NO);   // (a record under an app's key: windows told apart by app)
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        gTPresent = [NSSet setWithObjects:@"com.example.app16|sceneID:16", @"com.example.app17|sceneID:17", @"com.example.app18|sceneID:18", @"com.example.app19|sceneID:19", nil];
        Setup(land, @"com.example.app19|sceneID:19", card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));
        Check(gSMPastEdge.count == 4 && gSMPastEdge[@"com.example.app18"], @"... a record under the app's key stays while a window of that app is in a stage");
        gTPresent = nil;

        // ==== 4. our requests (DMSMAttrsFitScreen) ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(0, 800)), CGPointMake(0, 800));   // (recorded at (600, 1200): its bar's top at 976, behind the Dock)
        TAttrs *at = Attrs(CGSizeMake(600, 400), CGPointMake(600, 1200), land);
        Check(DMSMAttrsFitScreen(at, nil, NO, @"t") == at, @"request: a recorded window is handed over as it is (no rewrite)");
        gTIPadDock = 160.0;   // (the Dock grew: its line at 862)
        Check(DMSMAttrsFitScreen(at, nil, NO, @"t") == at && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024),
              @"request: the Dock grew since: it stays where it was let go (its bar behind the bigger Dock), as the other engines' windows stay");
        gTIPadDock = 117.0;
        Setup(land, kClock, card, NO);
        Drag(Steps(CGPointMake(-500, -300)), CGPointMake(-500, -300));   // (up to the menu bar and past the left edge: recorded at (100, 248))
        Check(RecIs(kClock, 100, 248, 600, 400, 1366, 1024), @"request: a window held under the menu bar and past the left edge: recorded at (100, 248)");
        gTIPadTop = 40.0;   // (a taller menu bar since)
        TAttrs *under = DMSMAttrsFitScreen(Attrs(CGSizeMake(600, 400), CGPointMake(100, 248), land), nil, NO, @"t");
        Check(under && NearPt(CGPointMake(under.center.x * 1366, under.center.y * 1024), 100, 264) && RecIs(kClock, 100, 264, 600, 400, 1366, 1024),
              @"request: a taller menu bar since: moved down only as far as its top needs, still past the left edge; the record follows");
        gTIPadTop = 24.0;
        TAttrs *other = Attrs(CGSizeMake(600, 400), CGPointMake(-100, 400), land);
        TAttrs *fitted = DMSMAttrsFitScreen(other, nil, NO, @"t");
        Check(fitted != other && Near(fitted.center.x * 1366, 300), @"request: a window past the left edge that is not recorded there (a turn's, Stage Manager's) is fitted inside as before");
        TAttrs *recSize = Attrs(CGSizeMake(640, 400), CGPointMake(600, 1200), land);
        Check(Near(((TAttrs *)DMSMAttrsFitScreen(recSize, nil, NO, @"t")).center.y * 1024, 905 - 200), @"request: the recorded place with another size (no resize by hand): fitted inside");
        TAttrs *full = Attrs(CGSizeMake(1366, 1024), CGPointMake(600, 1200), land); full.policy = 2;
        Check(DMSMAttrsFitScreen(full, nil, NO, @"t") == full, @"request: full screen: as before (untouched)");

        // ==== 5. iPadOS 16: around Stage Manager's own stage-area constraint ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));   // (recorded at (100, 400), 600 x 400)
        TModel *m = [TModel new];
        m.items = @[@"A", @"B", @"C"]; m.containerBounds = CGRectMake(0, 0, 1366, 1024);
        m.centers = [@{@"A": [NSValue valueWithCGPoint:CGPointMake(100, 400)], @"B": [NSValue valueWithCGPoint:CGPointMake(700, 400)], @"C": [NSValue valueWithCGPoint:CGPointMake(50, 400)]} mutableCopy];
        m.sizes = [@{@"A": [NSValue valueWithCGSize:CGSizeMake(600, 400)], @"B": [NSValue valueWithCGSize:CGSizeMake(400, 300)], @"C": [NSValue valueWithCGSize:CGSizeMake(600, 400)]} mutableCopy];
        CGRect area = CGRectMake(0, 48, 1366, 857);
        NSArray *held = DMSMPastEdgeBefore16(m, area);
        TAppleConstrain(m, area, 0);
        Check(NearPt([m centerForItem:@"A"], 300, 400), @"16: Stage Manager's own step pulls the recorded window in (stand-in)");
        gSMLoneCenterNext = YES;
        DMSMPastEdgeAfter16(m, held);
        Check(NearPt([m centerForItem:@"A"], 100, 400) && held.count == 1, @"16: ... ours puts it back at its recorded place");
        Check(NearPt([m centerForItem:@"C"], 300, 400) && NearPt([m centerForItem:@"B"], 700, 400), @"16: a window not recorded stays inside (Stage Manager's), the other untouched");
        Check(gSMLoneCenterNext && [gTMarks containsObject:@"sm-past-edge-kept16"], @"16: the lone window's flag as it was around our move");
        TModel *m2 = [TModel new];
        m2.items = @[@"A"]; m2.containerBounds = CGRectMake(0, 0, 1366, 1024);
        m2.centers = [@{@"A": [NSValue valueWithCGPoint:CGPointMake(100, 400)]} mutableCopy]; m2.sizes = [@{@"A": [NSValue valueWithCGSize:CGSizeMake(600, 400)]} mutableCopy];
        Check(DMSMPastEdgeBefore16(m2, area).count == 1, @"16: the recorded window alone is read");
        Check(DMSMPastEdgeBefore16(m2, CGRectMake(0, 250, 1366, 655)) == nil, @"16: a recorded window whose top is above the area's (a taller bar since) is not kept there");
        {   // (1.8.8.4) let go past the left edge at the screen's top edge while the menu bar hid itself (card top 24), the bar back since (the stage area at 48)
            TModel *m3 = [TModel new];
            m3.items = @[@"A"]; m3.containerBounds = CGRectMake(0, 0, 1366, 1024);
            m3.centers = [@{@"A": [NSValue valueWithCGPoint:CGPointMake(100, 224)]} mutableCopy]; m3.sizes = [@{@"A": [NSValue valueWithCGSize:CGSizeMake(600, 400)]} mutableCopy];
            NSArray<NSValue *> *rec0 = gSMPastEdge[kNotes];
            gSMPastEdge[kNotes] = @[[NSValue valueWithCGPoint:CGPointMake(100, 224)], [NSValue valueWithCGSize:CGSizeMake(600, 400)], [NSValue valueWithCGSize:CGSizeMake(1366, 1024)]];
            CGRect a48 = CGRectMake(0, 48, 1366, 857);
            NSArray *h3 = DMSMPastEdgeBefore16(m3, a48);
            TAppleConstrain(m3, a48, 0); TAppleConstrain(m3, a48, 1);
            DMSMPastEdgeAfter16(m3, h3);
            Check(h3.count == 1 && NearPt([m3 centerForItem:@"A"], 100, 248) && RecIs(kNotes, 100, 248, 600, 400, 1366, 1024),
                  @"16: recorded at the top edge while the bar hid itself, the bar back: kept under it again (centre y 248), still past the left edge, the record with it");
            gSMPastEdge[kNotes] = rec0;
        }
        m2.containerBounds = CGRectMake(0, 0, 1024, 1366);
        Check(DMSMPastEdgeBefore16(m2, area) == nil, @"16: another container size (another screen or shape): not kept");
        ClearRecords();
        m2.containerBounds = CGRectMake(0, 0, 1366, 1024);
        Check(DMSMPastEdgeBefore16(m2, area) == nil, @"16: no record: nothing read, nothing kept");
        DMSMPastEdgeAfter16(m2, nil);
        Check(m2.sets == 0, @"16: ... and nothing set");

        // ==== 6. Stage Manager's own passes keep a recorded window where it was let go, by the rule against the desktop as it is now: its top under
        //      the menu bar, nothing else -- a Dock grown since (Icon Size, fewer apps) or no longer hiding itself moves nothing, as on the other engines ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(0, 800)), CGPointMake(0, 800));   // (recorded at (600, 1200): its bar's top at 976, behind the Dock's line at 905)
        Check(NearPt(Step16(CGPointMake(600, 1200), CGSizeMake(600, 400), area, 1, NULL), 600, 1200) && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024),
              @"16: kept past the bottom where it was let go, its bar behind the Dock");
        gTIPadDock = 160.0;   // (the Dock grew: its line at 862)
        Check(NearPt(Step16(CGPointMake(600, 1200), CGSizeMake(600, 400), area, 1, NULL), 600, 1200) && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024),
              @"16: the Dock grew since the drop: still where it was let go (nothing lifts it above the Dock, as with Aerial, Zetsu and MilkyWay4)");
        CGPoint k17 = CGPointZero;
        gTIPadDock = 200.0;   // (17 and 18: the pass's callback; the Dock grew again, its line at 822)
        Check(DMSMPastEdgeHeldAt(CGPointMake(600, 1200), CGSizeMake(600, 400), land, &k17) && NearPt(k17, 600, 1200) && RecIs(kNotes, 600, 1200, 600, 400, 1366, 1024),
              [NSString stringWithFormat:@"17: the pass's callback keeps it where it was let go with the bigger Dock (%.1f)", k17.y]);
        gTIPadDock = 117.0;
        Check(!DMSMPastEdgeHeldAt(CGPointMake(700, 1200), CGSizeMake(600, 400), land, &k17), @"17: another place: not kept (clamped into the stage area as before)");
        Setup(land, kClock, card, NO);
        gTAutoHide = YES;   // (the Dock hiding itself)
        Drag(Steps(CGPointMake(0, 830)), CGPointMake(0, 830));
        gTAutoHide = NO;   // (switched off: the Dock is back at the bottom)
        Check(DMSMPastEdgeHeldAt(CGPointMake(600, 1230), CGSizeMake(600, 400), land, &k17) && NearPt(k17, 600, 1230),
              [NSString stringWithFormat:@"the Dock no longer hides itself: the pass keeps it where it was let go (%.1f)", k17.y]);
        ClearRecords();
        Setup(land, kClock, card, NO);
        Drag(Steps(CGPointMake(-500, -300)), CGPointMake(-500, -300));   // (recorded at (100, 248): its bar right under the menu bar)
        gTIPadTop = 40.0;   // (a taller menu bar since)
        Check(DMSMPastEdgeHeldAt(CGPointMake(100, 248), CGSizeMake(600, 400), land, &k17) && NearPt(k17, 100, 264) && RecIs(kClock, 100, 264, 600, 400, 1366, 1024),
              [NSString stringWithFormat:@"17: a taller menu bar: the callback keeps its top under it (down 16, still past the left edge), the record follows (%.1f)", k17.y]);
        Check(NearPt(Step16(CGPointMake(100, 264), CGSizeMake(600, 400), area, 0, NULL), 100, 264), @"16: ... the next step finds it at its record and keeps it there");
        gSMPastEdge[kClock] = @[[NSValue valueWithCGPoint:CGPointMake(100, 248)], [NSValue valueWithCGSize:CGSizeMake(600, 400)], [NSValue valueWithCGSize:land]];   // (as let go under the 24 pt bar)
        Check(NearPt(Step16(CGPointMake(100, 248), CGSizeMake(600, 400), area, 0, NULL), 100, 264), @"16: a taller menu bar: Stage Manager's step leaves it where the lookup keeps it (top under the bar), not at the old place");
        gTIPadTop = 24.0;
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(1500, 0)), CGPointMake(1500, 0));
        Check(DMSMPastEdgeHeldAt(CGPointMake(2100, 400), CGSizeMake(600, 400), CGSizeMake(1920, 1080), &k17) && NearPt(k17, 2100, 400), @"the TV: the pass's callback keeps its window at its place on the TV's own desktop");

        // ==== 7. a resize by hand of a window past an edge: it stays where it is, as Aerial's, Zetsu's and MilkyWay4's resizes leave it ====
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(-500, 0)), CGPointMake(-500, 0));   // (recorded at (100, 400), 600 x 400: its card (-200, 200) .. (400, 600))
        Check(!DMSMPastEdgeHeld(CGPointMake(150, 425), CGSizeMake(700, 450), land), @"resize: a new size at the same left and top with no resize by hand begun: not kept (fitted inside as before)");
        [gTLog removeAllObjects];
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeRight | kDMSMPastEdgeBottom, CGRectMake(-199.2, 201, 600.5, 399.6));   // (its bottom-right corner, the card as drawn)
        Check([gTMarks containsObject:@"sm-past-edge-resize"] && [gSMPastEdgeResizeKey isEqualToString:kNotes], @"resize: begun on the recorded window's card (within 3 pt): followed");
        NSArray *h7 = nil;
        CGPoint r16 = Step16(CGPointMake(150, 425), CGSizeMake(700, 450), area, 0, &h7);
        Check(NearPt(r16, 150, 425) && h7.count == 1 && RecIs(kNotes, 150, 425, 700, 450, 1366, 1024),
              [NSString stringWithFormat:@"resize, 16: bigger by its bottom-right corner, its left still 200 pt past the edge: Stage Manager's step pulled it in, ours keeps it where it is; the record follows (%.1f)", r16.x]);
        Check(NearPt(Step16(CGPointMake(140, 415), CGSizeMake(680, 430), area, 0, NULL), 140, 415) && RecIs(kNotes, 140, 415, 680, 430, 1366, 1024), @"resize, 16: the next step (smaller again): kept, the record follows");
        Check(DMSMPastEdgeHeldAt(CGPointMake(140, 415), CGSizeMake(680, 430), land, &k17) && NearPt(k17, 140, 415), @"resize, 17: the pass's callback keeps it at its new size where it is");
        TAttrs *ra = Attrs(CGSizeMake(680, 430), CGPointMake(140, 415), land);
        Check(DMSMAttrsFitScreen(ra, nil, NO, @"t") == ra, @"resize: our request for it at its new size: handed over as it is (not fitted inside)");
        Check(DMSMPastEdgeHeldAt(CGPointMake(145, 420), CGSizeMake(690, 440), land, &k17) && RecIs(kNotes, 145, 420, 690, 440, 1366, 1024),
              @"resize: a size that settles after the finger lifts (Stage Manager's snap or grid), its left and top where they were: still followed");
        Check(LogCount(@"resized by hand past the screen's edge") == 1, [NSString stringWithFormat:@"resize: one log line for the resize (%d)", LogCount(@"resized by hand past the screen's edge")]);
        Check(!DMSMPastEdgeHeld(CGPointMake(700, 420), CGSizeMake(690, 440), land) && !DMSMPastEdgeHeld(CGPointMake(195, 420), CGSizeMake(690, 440), land)
              && !DMSMPastEdgeHeld(CGPointMake(145, 420), CGSizeMake(690, 440), CGSizeMake(1920, 1080)),
              @"resize: another window at that size elsewhere, one whose left moved, one on another screen: not that window");
        DMSMPastEdgeDragBegin(gCard);
        Check(!gSMPastEdgeResizeKey && !DMSMPastEdgeHeld(CGPointMake(155, 430), CGSizeMake(710, 460), land) && DMSMPastEdgeHeld(CGPointMake(145, 420), CGSizeMake(690, 440), land),
              @"resize: a drag begins: the follow ends (a new size no longer kept), the window's place at its last size still is");
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeRight | kDMSMPastEdgeBottom, CGRectMake(500, 300, 400, 300));
        Check(!gSMPastEdgeResizeKey && !DMSMPastEdgeHeld(CGPointMake(155, 430), CGSizeMake(710, 460), land), @"resize: another window's resize (its card no record's): nothing followed");
        [gTLog removeAllObjects];
        DMSMPastEdgeResizeBegan(0, CGRectNull);
        Check(!gSMPastEdgeResizeKey && LogCount(@"could not be read") == 1, @"resize: its edge or card not read: nothing followed, said in the log");
        gTFree = NO;
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeRight | kDMSMPastEdgeBottom, CGRectMake(-200, 200, 690, 440));
        Check(!gSMPastEdgeResizeKey, @"resize: Stage Manager's own layout (debug): nothing followed");
        gTFree = YES;
        gSMPastEdge[kClock] = gSMPastEdge[kNotes]; [gSMPastEdgeOrder addObject:kClock];
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeRight | kDMSMPastEdgeBottom, CGRectMake(-200, 200, 690, 440));
        Check(!gSMPastEdgeResizeKey, @"resize: two records at that card: not followed");
        DMSMPastEdgeRemove(kClock);
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeTop, CGRectMake(-200, 200, 690, 440));
        Check([gSMPastEdgeResizeKey isEqualToString:kNotes] && DMSMPastEdgeHeld(CGPointMake(145, 390), CGSizeMake(690, 500), land) && RecIs(kNotes, 145, 390, 690, 500, 1366, 1024),
              @"resize: its top dragged up by the pointer (the bottom and sides held): kept, the record follows");
        DMSMPastEdgeRemove(kNotes);
        Check(!Rec(kNotes) && !gSMPastEdgeResizeKey, @"resize: the window's record gone (a drop inside the screen): the follow goes with it");
        ClearRecords();
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(1500, 0)), CGPointMake(1500, 0));   // (the TV: recorded at (2100, 400) on 1920 x 1080)
        DMSMPastEdgeResizeBegan(kDMSMPastEdgeLeft | kDMSMPastEdgeBottom, CGRectMake(1800, 200, 600, 400));
        Check(DMSMPastEdgeHeld(CGPointMake(2050, 425), CGSizeMake(700, 450), CGSizeMake(1920, 1080)) && RecIs(kNotes, 2050, 425, 700, 450, 1920, 1080)
              && !DMSMPastEdgeHeld(CGPointMake(2000, 425), CGSizeMake(800, 450), land),
              @"resize, the TV: bigger by its bottom-left corner (its right side past the TV's edge held): kept on the TV, never an iPad window");

        // ==== 8. a window comes back at its own place (1.8.8.3): minimized and opened again, as the join hands Stage Manager its own attributes ====
        //      (DMSMJoinOwnPlace: where the user left it -- past an edge, behind the Dock --, as on the other engines; any other place fitted inside)
        CGRect desk8 = CGRectMake(0, 24, 1366, 881);   // (the iPad's desktop: under the menu bar, above the Dock's line at 905)
        ClearRecords();
        Setup(land, kNotes, card, NO);
        Drag(Steps(CGPointMake(806 - 300, 0)), CGPointMake(806 - 300, 0));   // (past the right edge: its card (806, 200) .. (1406, 600), recorded at (1106, 400))
        CGSize zp = CGSizeMake(600, 400); CGPoint zc = CGPointMake(1106, 400);
        DMSMJoinOwnPlace(kNotes, &zp, &zc, land, desk8);
        Check(NearPt(zc, 1106, 400) && Near(zp.width, 600) && [gTMarks containsObject:@"sm-past-edge-join"] && LogCount(@"comes back at its place past the screen's edge") == 1,
              [NSString stringWithFormat:@"join: a window let go past the right edge, minimized and opened again: back at its place (%.1f; fitted inside it was 1066)", zc.x]);
        zp = CGSizeMake(600, 400); zc = CGPointMake(1106, 350);
        DMSMJoinOwnPlace(kNotes, &zp, &zc, land, desk8);
        Check(NearPt(zc, 1066, 350), @"join: another place past the edge (no record there): fitted inside as before");
        zp = CGSizeMake(600, 400); zc = CGPointMake(400, 1000);
        DMSMJoinOwnPlace(kClock, &zp, &zc, land, desk8);
        Check(NearPt(zc, 400, 705), [NSString stringWithFormat:@"join: a window low under the Dock's line, not put there by the user: above the Dock as before (%.1f)", zc.y]);
        if (!gSMBehindDock) gSMBehindDock = [NSMutableSet set];
        [gSMBehindDock addObject:kClock];
        zp = CGSizeMake(600, 400); zc = CGPointMake(400, 800);
        DMSMJoinOwnPlace(kClock, &zp, &zc, land, desk8);
        Check(NearPt(zc, 400, 800), [NSString stringWithFormat:@"join: a window the user put behind the Dock: back behind it, as on the other engines (%.1f)", zc.y]);
        zp = CGSizeMake(600, 400); zc = CGPointMake(400, 1000);
        DMSMJoinOwnPlace(kClock, &zp, &zc, land, desk8);
        Check(NearPt(zc, 400, 824), @"join: ... never past the screen's bottom unless let go there (kept inside the screen)");
        [gSMBehindDock removeObject:kClock];
        Setup(land, kClock, card, NO);
        Drag(Steps(CGPointMake(-500, -300)), CGPointMake(-500, -300));   // (recorded at (100, 248): its bar right under the 24 pt menu bar)
        gTIPadTop = 40.0;   // (a taller menu bar since)
        zp = CGSizeMake(600, 400); zc = CGPointMake(100, 248);
        DMSMJoinOwnPlace(kClock, &zp, &zc, land, CGRectMake(0, 40, 1366, 865));
        Check(NearPt(zc, 100, 264) && RecIs(kClock, 100, 264, 600, 400, 1366, 1024), [NSString stringWithFormat:@"join: a taller menu bar since: its top under it, still past the left edge, the record follows (%.1f, %.1f)", zc.x, zc.y]);
        gTIPadTop = 24.0;
        gTDockSide = 2;
        zp = CGSizeMake(600, 400); zc = CGPointMake(1106, 400);
        DMSMJoinOwnPlace(kNotes, &zp, &zc, land, CGRectMake(0, 24, 1236, 1000));
        Check(Near(zc.x, 936), [NSString stringWithFormat:@"join: the Dock moved to a side since: fitted into the desktop beside it, as every engine (%.1f)", zc.x]);
        gTDockSide = 0;
        Setup(land, kNotes, card, YES);
        Drag(Steps(CGPointMake(1500, 0)), CGPointMake(1500, 0));   // (the TV: recorded at (2100, 400) on 1920 x 1080)
        zp = CGSizeMake(600, 400); zc = CGPointMake(2100, 400);
        DMSMJoinOwnPlace(kNotes, &zp, &zc, CGSizeMake(1920, 1080), CGRectMake(0, 24, 1920, 954));
        Check(NearPt(zc, 2100, 400), @"join: the TV's window back at its place past the TV's edge");
    }
    printf("test-smpastedge: %d of %d checks pass\n", gChecks - gFails, gChecks);
    return gFails;
}
