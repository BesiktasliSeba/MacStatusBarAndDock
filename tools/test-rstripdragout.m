// test-rstripdragout.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a card dragged out of the Recent Windows Strip (1.8.8.4, F29b), through
// statusbar/RecentStrip.h's real code: the card's press (DMRStripPressed), the drag's begin, follow, end and return (DMRStripCardDragBegin,
// DMRStripDragFollow, DMRStripCardDragEnd, DMRStripCardDragReturn), the strip's layout and its cards' going (DMRStripRelayout, DMRStripLayoutCards,
// DMRStripCardGoes, DMRStripCardPlace) and the strip's show (DMRStripApplyShow), cut out by test-rstripdragout.sh.
// The first 1.8.8.4 device pass (iPadOS 15.6.1, Aerial 5.1; Zetsu and MilkyWay4 run the same code): no card could ever be dragged out -- "<app>'s card
// back to its slot (the touch was cancelled)" 1 to 5 ms BEFORE "<app>'s card dragged out (a finger)", then nothing. The drag's begin laid the strip
// out without the dragged card, the layout let that card go, and a card with no alpha left its window at once; its view carries the press
// recogniser that drives the drag, and UIKit cancels a recogniser whose view leaves the window. Here the card (TCard) does what UIKit does: taken
// off its window, its press, if live, is cancelled and its action runs (TPress: the real DMRStripPress, its state a stand-in's).
// The list is the real DMRStripCollect's, on the engines' windows and our own windows the test sets up.
//  1. a card dragged out of a strip of two: the drag lives (no cancel), the others close the gap, the card follows the finger, and let go over the
//     desktop its window comes back there (placed, raised) and the card goes -- only then, its drag over;
//  2. let go back in the band: the same card back in its slot, shown;
//  3. the strip's last card dragged out: the strip stays out while the drag lives (stepping aside cuts a drag short), and the drop works;
//  4. a card of our own windows (native:): its windows kept for its drop while it is out of the list, shown again where it is let go;
//  5. the strip stepping aside mid-drag (its window kept up for the handle): the held card back and stepped aside with the others;
//  6. a drag that ends as gone while its card is still in the strip: the held card shown again, never left hidden.
// Exit status: the number of failed checks.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include "../common/DockSide.h"
// (ReduceMotion.h's, as the device has them with Reduce Motion off; the animations' ends at once: their model values are what is read)
static const CGFloat kMSBRMScale = 0.98;
static BOOL MSBReduceMotion(void) { return NO; }
static void MSBAnimate(NSTimeInterval d, NSTimeInterval delay, CGFloat damping, UIViewAnimationOptions o, void (^animations)(void), void (^completion)(BOOL)) {
    (void)d; (void)delay; (void)damping; (void)o;
    [UIView performWithoutAnimation:animations];
    if (completion) completion(YES);
}
static int gFails = 0, gChecks = 0;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static NSMutableArray<NSString *> *gTLog;
#define DMLog(...) [gTLog addObject:(__VA_ARGS__)]
#define DM_FEATURE_MARK(name) do { } while (0)
static BOOL TLogHas(NSString *s) { for (NSString *l in gTLog) if ([l containsString:s]) return YES; return NO; }
static NSInteger TLogAt(NSString *s) { for (NSUInteger i = 0; i < gTLog.count; i++) if ([gTLog[i] containsString:s]) return (NSInteger)i; return -1; }
// ---- the engines' side, as the strip reads it ----
typedef enum { DMEngineNone = 0, DMEngineAerial, DMEngineZetsu, DMEngineMilkyWay } DMEngine;
static DMEngine DMActiveEngine(void) { return DMEngineZetsu; }
@interface DMNativeWindow : UIView
@property (nonatomic) CGSize minSize;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, assign) BOOL dm_wasMinimized;
- (void)show; - (void)close;
@end
static UIView *gNativeRotator; static BOOL gNativeActive;
static CGRect DMNativeClamp(CGRect f, CGSize s) { (void)s; return f; }
static void DMNativeSetActive(id w) { (void)w; }
static BOOL gStockBar = NO;
static CGSize TScreenSize(void) { return CGSizeMake(1024, 768); }   // (the iPad's screen in landscape)
static CGRect DMUsableArea(void) { return CGRectMake(0, 24, 1024, 670); }
static unsigned gDMDockGen = 1, gDMDockPlaceGen = 1;
static int DMDockSideNow(CGSize s) { (void)s; return MSBDDockBottom; }
static CGFloat DMDesiredWindowLevel(void) { return 1000.0; }
static NSMutableDictionary<NSString *, UIView *> *gTStages;   // (the windows waiting in the strip: hidden by our minimize)
static NSMutableArray<NSString *> *gTList;                    // (the strip's list as the engines have it: most recent first)
static NSMutableArray<NSString *> *gTRaised; static NSMutableDictionary<NSString *, NSValue *> *gTPlaced;
static UIView *DMStageForBundle(NSString *k) { return gTStages[k]; }
static NSMutableSet *gTNativeHidden;
static BOOL DMRStripHiddenByUs(UIView *st) { return st && ([gTNativeHidden containsObject:st] || ([gTStages.allValues containsObject:st] && [gTList containsObject:st.accessibilityIdentifier])); }   // (our minimize hid it)
static CGRect DMSnapWindowOfFrame(UIView *st, CGRect f) { (void)st; return f; }
static CGRect DMSnapEngineWindow(UIView *st, CGRect w, unsigned how) { (void)st; (void)how; return w; }
static CGRect DMSnapEngineFrameFor(UIView *st, CGRect w) { (void)st; return w; }
static CGRect DMA5StageFromWindow(CGRect r) { return r; }
enum { MSBDSnapMove = 1 };
static void DMRStripPlaceHidden(UIView *st, CGRect f) { gTPlaced[st.accessibilityIdentifier] = [NSValue valueWithCGRect:f]; }
static void DMFitGroupForget(NSString *k) { (void)k; }
static void DMTitleRecordMovedView(UIView *st) { (void)st; }
static BOOL DMSurfaceWindowForApp(NSString *k) { (void)k; return NO; }
static void DMRaiseStageForBundle(NSString *k) { [gTRaised addObject:k]; [gTList removeObject:k]; }   // (its window back on the desktop: out of the list)
static void DMRememberStageFrame(UIView *st) { (void)st; }
static void DMSaveWindowState(void) {}
static void DMRStripRelaunchNow(NSString *b, CGRect f) { (void)b; (void)f; }
// Our own windows (Finder, TextEdit...) waiting in the strip: their app's card ("native:<app>") -> its windows, most recent first; the ones our
// minimize hid; the ones shown again (a drop's -show).
static NSMutableDictionary<NSString *, NSArray<DMNativeWindow *> *> *gTNative; static NSMutableSet *gTNativeHidden; static NSMutableArray<DMNativeWindow *> *gTNativeShown;
@implementation DMNativeWindow
- (void)show { self.hidden = NO; self.dm_wasMinimized = NO; [gTNativeHidden removeObject:self]; [gTNativeShown addObject:self]; for (NSString *k in gTNative) if ([gTNative[k] containsObject:self]) [gTList removeObject:k]; }
- (void)close {}
@end
#include "../common/RecentStripRule.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#include "rsd-glob.inc"   // (RecentStrip.h: its globals)
// (the strip's other parts, not what this test is about)
static void DMRStripPick(DMRStripCard *card, BOOL shift, NSString *how) { (void)card; (void)shift; (void)how; }
static void DMRStripCardMenu(DMRStripCard *c, NSString *how) { (void)c; (void)how; }
static void DMRStripLiftTo(DMRStripCard *c) { (void)c; }
static void DMRStripCardPicture(DMRStripCard *c) { (void)c; }
static BOOL DMRStripIsNativeKey(NSString *k) { return [k hasPrefix:@"native:"]; }   // (RecentStrip.h's)
static BOOL DMRStripCalm(void) { return YES; }
static BOOL DMRStripEnsureWindow(void) { return YES; }
static void DMRStripTurnIn(void) {}
static void DMRStripWatchMemory(void) {}
static NSValue *DMRStripPlaceOf(UIView *st) { return [NSValue valueWithCGRect:st ? st.frame : CGRectMake(200, 100, 600, 420)]; }
// What RecentStrip.h's real DMRStripCollect reads (cut out with it): the engines' windows, our own windows, each one's time in the strip -- the
// test's list order, most recent first --, which wait in it (hidden by our minimize, on this desktop).
static NSMutableArray<DMNativeWindow *> *gNativeWindows;
static NSArray<UIView *> *DMAerialStages(void) { return gTStages.allValues; }
static NSString *DMStageBundle(UIView *st) { return st.accessibilityIdentifier; }
static BOOL DMRStripStageOnScreen(UIView *st) { return st && !st.hidden && ![gTList containsObject:st.accessibilityIdentifier]; }
static BOOL DMRStripOffDesktop(UIView *st) { return [gTList containsObject:st.accessibilityIdentifier]; }
static NSString *DMRStripNativeKey(DMNativeWindow *w) { return [@"native:" stringByAppendingString:w.appName.length ? w.appName : @"Window"]; }   // (RecentStrip.h's)
static BOOL DMRStripNativeAway(DMNativeWindow *w) { (void)w; return NO; }
static BOOL DMRStripEntryOf(UIView *st, double *at, int *why) {
    NSString *k = [st isKindOfClass:[DMNativeWindow class]] ? DMRStripNativeKey((DMNativeWindow *)st) : st.accessibilityIdentifier;
    NSUInteger i = [gTList indexOfObject:k];
    if (i == NSNotFound) return NO;
    if (at) *at = 1000.0 - i - ([st isKindOfClass:[DMNativeWindow class]] ? [gTNative[k] indexOfObject:(DMNativeWindow *)st] * 0.1 : 0.0);
    if (why) *why = MSBDRStripWhyMinimized;
    return YES;
}
static void DMRStripSetEntry(UIView *st, double at, int why) { (void)st; (void)at; (void)why; }
static double DMRStripClock(void) { return 1000.0; }
#include "rsd-decl.inc"   // (RecentStrip.h: @interface DMRStripCard, DMRStripPress and its @implementation, DMRStripDrag)
@interface DMRStripTarget : NSObject
+ (instancetype)shared; - (void)press:(DMRStripPress *)g; - (void)memoryWarning:(NSNotification *)n;
@end
static void DMRStripPressed(DMRStripPress *g);
@implementation DMRStripTarget
+ (instancetype)shared { static DMRStripTarget *t; if (!t) t = [DMRStripTarget new]; return t; }
- (void)press:(DMRStripPress *)g { DMRStripPressed(g); }
- (void)memoryWarning:(NSNotification *)n { (void)n; }
@end
// The card's press with a state of the test's own (no UIKit gesture machinery runs here: the test hands it its states, as UIKit's touches would).
@interface TPress : DMRStripPress
@property (nonatomic) UIGestureRecognizerState kState;
@end
@implementation TPress
- (UIGestureRecognizerState)state { return self.kState; }
- (void)setState:(UIGestureRecognizerState)s { self.kState = s; }
@end
// UIKit: a view taken off its window has its recognisers' touches cancelled -- a live press (began or changed) goes to Cancelled and its action
// runs at once (the device log: the cancel's line inside the drag's begin).
static int gTCancels = 0;
@implementation DMRStripCard
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) return;
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if (![g isKindOfClass:[TPress class]]) continue;
        TPress *p = (TPress *)g;
        if (p.kState != UIGestureRecognizerStateBegan && p.kState != UIGestureRecognizerStateChanged) continue;
        gTCancels++;
        p.kState = UIGestureRecognizerStateCancelled;
        DMRStripPressed(p);
    }
}
@end
// A card as RecentStrip.h's DMRStripCardFor makes it, for what this test reads: its lift, shadow, picture and icon, and its press.
static DMRStripCard *DMRStripCardFor(NSString *k) {
    if (!gRStripCards) gRStripCards = [NSMutableDictionary dictionary];
    DMRStripCard *c = gRStripCards[k];
    if (c) return c;
    c = [[DMRStripCard alloc] initWithFrame:CGRectZero];
    c.key = k; c.bundle = k;
    c.lift = [[UIView alloc] initWithFrame:CGRectZero]; [c addSubview:c.lift];
    c.shadow = [[UIView alloc] initWithFrame:CGRectZero]; [c.lift addSubview:c.shadow];
    c.pic = [[UIView alloc] initWithFrame:CGRectZero]; [c.lift addSubview:c.pic];
    c.icon = [[UIImageView alloc] initWithImage:nil]; [c.lift addSubview:c.icon];
    [c addGestureRecognizer:[[TPress alloc] initWithTarget:[DMRStripTarget shared] action:@selector(press:)]];
    gRStripCards[k] = c;
    return c;
}
static void DMRStripCardDragReturn(NSString *why, BOOL gone);
static void DMRStripKeysTake(BOOL take) { (void)take; }
static BOOL gTHandle = NO;   // (the finger's handle keeps the strip's window up while it has stepped aside: no pointer, something over the strip)
static BOOL DMRStripHandleWanted(void) { return gTHandle; }
#include "rsd-real.inc"   // (RecentStrip.h: the real code)

static TPress *PressOf(DMRStripCard *c) { for (UIGestureRecognizer *g in c.gestureRecognizers) if ([g isKindOfClass:[TPress class]]) return (TPress *)g; return nil; }
static CGPoint Mid(DMRStripCard *c) { CGRect r = DMRStripCardScreenRect(c); return CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r)); }
static UIWindow *gTWin;
// A fresh strip out on the screen with the windows `keys` waiting in it, most recent first.
static void Strip(NSArray<NSString *> *keys) {
    gTNative = [NSMutableDictionary dictionary]; gTNativeHidden = [NSMutableSet set]; gTNativeShown = [NSMutableArray array]; gTHandle = NO;
    for (NSString *k in keys) if (DMRStripIsNativeKey(k)) {
        DMNativeWindow *a = [[DMNativeWindow alloc] initWithFrame:CGRectMake(150, 90, 640, 440)], *b = [[DMNativeWindow alloc] initWithFrame:CGRectMake(260, 160, 520, 380)];
        for (DMNativeWindow *w in @[a, b]) { w.appName = [k substringFromIndex:7]; w.hidden = YES; w.dm_wasMinimized = YES; [gTNativeHidden addObject:w]; }
        gTNative[k] = @[a, b];
    }
    gNativeWindows = [NSMutableArray array]; for (NSString *k in gTNative) [gNativeWindows addObjectsFromArray:gTNative[k]];
    for (DMRStripCard *c in gRStripCards.allValues) [c removeFromSuperview];
    gRStripCards = nil; gRStripItems = nil; gRStripLayoutSig = nil; gRStripCardDrag = nil; gRStripDraggingKey = nil;
    gRStripLeaving = nil; gRStripLeavingAt = nil; gRStripGhosts = nil; gRStripGone = nil; gRStripGroups = nil;
    gTLog = [NSMutableArray array]; gTCancels = 0; gTRaised = [NSMutableArray array]; gTPlaced = [NSMutableDictionary dictionary];
    gTList = [keys mutableCopy]; gTStages = [NSMutableDictionary dictionary];
    for (NSString *k in keys) if (!gTNative[k]) { UIView *st = [[UIView alloc] initWithFrame:CGRectMake(200, 100, 600, 420)]; st.accessibilityIdentifier = k; st.hidden = YES; gTStages[k] = st; }
    { UIView *front = [[UIView alloc] initWithFrame:CGRectMake(320, 80, 600, 500)]; front.accessibilityIdentifier = @"com.apple.mobilesafari"; gTStages[front.accessibilityIdentifier] = front; }   // (a window on the desktop)
    gTWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]; gRStripWindow = gTWin;
    gRStripRoot = [[UIView alloc] initWithFrame:gTWin.bounds]; [gTWin addSubview:gRStripRoot];
    gRStripSlide = [[UIView alloc] initWithFrame:gRStripRoot.bounds]; [gRStripRoot addSubview:gRStripSlide];
    gRStripShown = MSBDRStripOverWindows;
    DMRStripApplyShow(DMRStripRelayout(NO), NO, nil);
}
// The finger down on the card and moved by (dx, dy) over 0.1 s: past the slop, the drag's begin.
static TPress *Lift(DMRStripCard *c, CGFloat dx, CGFloat dy) {
    TPress *g = PressOf(c);
    CGPoint p = Mid(c);
    g.down = g.last = g.prev = p; g.downAt = g.lastAt = g.prevAt = 10.0;
    g.kState = UIGestureRecognizerStateBegan; DMRStripPressed(g);
    g.prev = g.last; g.prevAt = g.lastAt; g.last = CGPointMake(p.x + dx, p.y + dy); g.lastAt = 10.1;
    g.kState = UIGestureRecognizerStateChanged; DMRStripPressed(g);
    return g;
}
static void MoveTo(TPress *g, CGPoint p, double t) { g.prev = g.last; g.prevAt = g.lastAt; g.last = p; g.lastAt = t; g.kState = UIGestureRecognizerStateChanged; DMRStripPressed(g); }
static void LetGo(TPress *g, CGPoint p, double t) { g.prev = g.last; g.prevAt = g.lastAt; g.last = p; g.lastAt = t; g.kState = UIGestureRecognizerStateEnded; DMRStripPressed(g); g.kState = UIGestureRecognizerStatePossible; }

int main(void) {
    @autoreleasepool {
        // ==== 1. a card dragged out of a strip of two, let go over the desktop ====
        Strip(@[@"com.apple.mobiletimer", @"com.apple.tips"]);
        DMRStripCard *clock = gRStripCards[@"com.apple.mobiletimer"], *tips = gRStripCards[@"com.apple.tips"];
        Check(clock.window && tips.window && [gRStripItems isEqualToArray:@[@"com.apple.mobiletimer", @"com.apple.tips"]] && gRStripShown != MSBDRStripHidden,
              [NSString stringWithFormat:@"setup: the strip out with two cards (%@)", [gRStripItems componentsJoinedByString:@", "]]);
        CGFloat out = gRStripRight ? -40.0 : 40.0;   // (toward the desktop)
        TPress *g = Lift(tips, out, 0);
        Check(gRStripCardDrag != nil && [gRStripDraggingKey isEqualToString:@"com.apple.tips"] && gTCancels == 0 && !TLogHas(@"back to its slot"),
              [NSString stringWithFormat:@"drag out: the drag lives after its begin -- its card's press not cancelled (%d cancel(s); log: %@)", gTCancels, [gTLog componentsJoinedByString:@" | "]]);
        Check(tips.window != nil && gRStripCards[@"com.apple.tips"] == tips && tips.alpha < 0.01,
              @"  ... the dragged card stays on its window, hidden (its view carries the press that drives the drag)");
        Check([gRStripItems isEqualToArray:@[@"com.apple.mobiletimer"]], [NSString stringWithFormat:@"  ... the others close its gap (laid out: %@)", [gRStripItems componentsJoinedByString:@", "]]);
        CGPoint desk = CGPointMake(gRStripRight ? gRStripBand.x - 420.0 : MSBDRMaxX(gRStripBand) + 420.0, 330.0);
        MoveTo(g, CGPointMake((Mid(clock).x + desk.x) / 2.0, 320.0), 10.3);
        MoveTo(g, desk, 10.5);
        UIView *holder = gRStripCardDrag.holder;
        CGPoint hc = holder ? [holder.superview convertPoint:holder.center toView:gRStripRoot] : CGPointMake(NAN, NAN);
        Check(gRStripCardDrag && holder.superview == gRStripRoot && fabs(hc.y - desk.y) < holder.bounds.size.height && fabs(hc.x - desk.x) < holder.bounds.size.width && gTCancels == 0,
              [NSString stringWithFormat:@"  ... its picture follows the finger over the desktop (at %@, the finger at %@)", NSStringFromCGPoint(hc), NSStringFromCGPoint(desk)]);
        LetGo(g, desk, 10.6);
        NSValue *placed = gTPlaced[@"com.apple.tips"];
        Check(TLogHas(@"com.apple.tips's card let go at") && placed && CGRectContainsPoint(CGRectInset(placed.CGRectValue, -1, -1), desk) && [gTRaised containsObject:@"com.apple.tips"],
              [NSString stringWithFormat:@"drop: let go over the desktop, its window comes back there (placed at %@, raised %@)", placed ? NSStringFromCGRect(placed.CGRectValue) : @"-", [gTRaised componentsJoinedByString:@", "]]);
        Check(!gRStripCardDrag && !gRStripDraggingKey && !gRStripCards[@"com.apple.tips"] && !tips.window && gTCancels == 0 && clock.window && [gRStripItems isEqualToArray:@[@"com.apple.mobiletimer"]],
              @"  ... and its card goes only now, its drag over (nothing cancelled); the other card stays");
        Check(TLogAt(@"card dragged out") >= 0 && TLogAt(@"card dragged out") < TLogAt(@"card let go at"), @"  ... the log in order: dragged out, then let go");

        // ==== 2. let go back in the band: the same card back in its slot ====
        Strip(@[@"com.apple.mobiletimer", @"com.apple.tips"]);
        tips = gRStripCards[@"com.apple.tips"];
        g = Lift(tips, out, 0);
        Check(gRStripCardDrag && gTCancels == 0, @"back: the drag lives");
        CGPoint inBand = CGPointMake(gRStripBand.x + gRStripBand.w / 2.0, 330.0);
        MoveTo(g, inBand, 10.4);
        LetGo(g, inBand, 10.5);
        Check(!gRStripCardDrag && TLogHas(@"back to its slot (let go in the band)") && gRStripCards[@"com.apple.tips"] == tips && tips.window && tips.alpha > 0.99 && !tips.landing
              && [gRStripItems isEqualToArray:@[@"com.apple.mobiletimer", @"com.apple.tips"]] && !gTPlaced.count && gTCancels == 0,
              [NSString stringWithFormat:@"  ... let go in the band: the same card back in its slot, shown; no window moved (items %@)", [gRStripItems componentsJoinedByString:@", "]]);

        // ==== 3. the strip's last card dragged out ====
        Strip(@[@"com.apple.tips"]);
        tips = gRStripCards[@"com.apple.tips"];
        g = Lift(tips, out, 0);
        DMRStripApplyShow(DMRStripRelayout(YES), NO, nil);   // (the tick's look while the drag goes on)
        Check(gRStripCardDrag && gRStripShown != MSBDRStripHidden && gTCancels == 0 && tips.window && !TLogHas(@"steps aside"),
              [NSString stringWithFormat:@"last card: while its drag lives the strip stays out (the dragged card counts: stepping aside would cut the drag short) (%@)", [gTLog componentsJoinedByString:@" | "]]);
        desk = CGPointMake(gRStripRight ? gRStripBand.x - 420.0 : MSBDRMaxX(gRStripBand) + 420.0, 330.0);
        MoveTo(g, desk, 10.5);
        LetGo(g, desk, 10.6);
        Check(gTPlaced[@"com.apple.tips"] && [gTRaised containsObject:@"com.apple.tips"] && !gRStripCards[@"com.apple.tips"] && !gRStripCardDrag && gTCancels == 0,
              @"  ... and its drop brings its window back there, the card gone");
        DMRStripApplyShow(DMRStripRelayout(YES), NO, nil);
        Check(gRStripShown == MSBDRStripHidden, @"  ... then, nothing left to show, the strip steps aside");

        // ==== 4. a card of our own windows (Finder) dragged out: its windows come back where it is let go ====
        Strip(@[@"com.apple.mobiletimer", @"native:Finder"]);
        DMRStripCard *finder = gRStripCards[@"native:Finder"];
        g = Lift(finder, out, 0);
        Check(gRStripCardDrag && gTCancels == 0 && finder.window && gRStripGroups[@"native:Finder"].count == 2,
              [NSString stringWithFormat:@"own windows: the drag lives, its card's windows kept in its group while it is out of the list (%lu)", (unsigned long)gRStripGroups[@"native:Finder"].count]);
        desk = CGPointMake(gRStripRight ? gRStripBand.x - 420.0 : MSBDRMaxX(gRStripBand) + 420.0, 330.0);
        MoveTo(g, desk, 10.5);
        LetGo(g, desk, 10.6);
        Check(gTNativeShown.count == 2 && !TLogHas(@"went meanwhile") && !gRStripCards[@"native:Finder"] && !finder.window && !gRStripCardDrag && gTCancels == 0,
              [NSString stringWithFormat:@"  ... let go over the desktop: its windows shown again (%lu), the card gone, not taken for gone windows (%@)", (unsigned long)gTNativeShown.count, [gTLog componentsJoinedByString:@" | "]]);
        for (DMRStripCard *c in gRStripCards.allValues) if (c.window && c.alpha < 0.01 && !c.landing) { Check(NO, [NSString stringWithFormat:@"  ... no card left hidden in the strip (%@)", c.key]); break; }

        // ==== 6. a drag that ends as gone while its card stays in the strip (our own windows: the most recent one came back meanwhile, the other still
        //  waits): the card the drag held is shown again, never left hidden ====
        Strip(@[@"com.apple.mobiletimer", @"native:Finder"]);
        finder = gRStripCards[@"native:Finder"];
        g = Lift(finder, out, 0);
        DMNativeWindow *mostRecent = gTNative[@"native:Finder"].firstObject;
        mostRecent.hidden = NO; mostRecent.dm_wasMinimized = NO; [gTNativeHidden removeObject:mostRecent];   // (back by another way: a Dock tap)
        desk = CGPointMake(gRStripRight ? gRStripBand.x - 420.0 : MSBDRMaxX(gRStripBand) + 420.0, 330.0);
        MoveTo(g, desk, 10.5);
        LetGo(g, desk, 10.6);
        Check(TLogHas(@"went meanwhile") && gRStripCards[@"native:Finder"] == finder && finder.window && finder.alpha > 0.99 && [gRStripItems containsObject:@"native:Finder"] && !gRStripCardDrag,
              [NSString stringWithFormat:@"gone but still waiting: the held card shown again in its slot (alpha %.2f, items %@)", finder.alpha, [gRStripItems componentsJoinedByString:@", "]]);

        // ==== 5. the strip steps aside mid-drag, its window kept up for the finger's handle: the held card steps aside with the others ====
        Strip(@[@"com.apple.mobiletimer", @"com.apple.tips"]);
        tips = gRStripCards[@"com.apple.tips"]; clock = gRStripCards[@"com.apple.mobiletimer"];
        g = Lift(tips, out, 0);
        gTHandle = YES;
        DMRStripShowAs(MSBDRStripHidden, @"a window covers it");
        CGAffineTransform away = DMRStripAway();
        Check(!gRStripCardDrag && TLogHas(@"back to its slot (the strip steps aside") && gRStripCards[@"com.apple.tips"] == tips && tips.window
              && CGAffineTransformEqualToTransform(tips.transform, away) && CGAffineTransformEqualToTransform(clock.transform, away) && !gTWin.hidden,
              [NSString stringWithFormat:@"aside mid-drag: the drag cut short, its card back and stepped aside with the others (tx %.0f, the other %.0f), the window up for the handle", tips.transform.tx, clock.transform.tx]);

        printf("%d checks, %d failed\n", gChecks, gFails);
    }
    return gFails > 98 ? 98 : gFails;
}
