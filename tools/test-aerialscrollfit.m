// test-aerialscrollfit.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Aerial 3.0's window drag and resize hooks (1.8.7.3, audit M5 of 1.8.7.2).
// Aerial's window drag recogniser also begins from a finger dragging inside the app (a page scrolled); DMAerialPanBefore refuses that drag at its
// start by switching the recogniser off and on, which cancels it, and UIKit then sends the recogniser's action once more, with the Cancelled state.
// That call came to the hook like the end of a move by hand: the window left Fit to Window's tiles (DMFitGroupForget), its place was remembered and
// saved, and the title bar's way back (Fill / Zoom) was dropped, on every scroll inside a tiled window. Only the end of a drag or a resize whose
// start was taken may act.
// Runs the real DMAerialPanBefore and DMAerialGestureAfter (with what lies between them), DMTitleRecordHandEnded, DMFitGroupForget with Fit's
// gFitGroup / gFitSlots, kStageBarHeight, the %hook AerialStage bodies of -handlePan: and -handleResizeBR: (%orig made a call that records it) and the
// 5.0 reference functions h5_pan / h5_resizeBR, all cut out of statusbar/StatusBar.x by test-aerialscrollfit.sh. Aerial's recogniser is a real
// UIPanGestureRecognizer whose state, touches and travel the test sets; switched off while it recognises, it cancels and sends its action with that
// state, as UIKit does ("If you change this property to NO while a gesture recognizer is currently recognizing a gesture, the gesture recognizer
// transitions to a cancelled state"), either inside the switch (at once) or after the current call returns (as the next run loop turn does).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- what the real code logs and asks
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
static const void *kStageGestureKey = &kStageGestureKey;   // (StatusBar.x: a drag / resize by hand is in progress)
static CGFloat gKShift;   // (how far the auto-hiding status bar has slid the title bar down)
static CGFloat DMAutoHideTitleShiftOf(UIView *stage) { return gKShift; }
static BOOL DMA5MacGeometry(void) { return NO; }   // (Aerial 3.0)
static CGFloat DMTopLimit(void) { return 24.0; }
static int gKMovedRec, gKCovered, gKSnaps, gKRemembered, gKSaved;
static void DMTitleRecordMovedView(UIView *v) { gKMovedRec++; }   // (the title bar's frame from before is dropped: no way back by Fill / Zoom)
static void DMKeepCoveredByHand(UIView *v) { gKCovered++; }
static void DMSnapMoveEnded(UIView *st) { gKSnaps++; }
static void DMRememberStageFrame(UIView *stage) { gKRemembered++; }
static void DMSaveWindowState(void) { gKSaved++; }

// ---- an Aerial window (AerialStage): Aerial's own -handlePan: / -handleResizeBR: record the states they are called with
@interface KStage : UIView
@property (nonatomic, copy) NSString *bundle;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *origPan, *origResize;
- (void)k_origPan:(id)g;
- (void)k_origResize:(id)g;
@end
static NSString *DMStageBundle(UIView *stage) { return [stage isKindOfClass:[KStage class]] ? ((KStage *)stage).bundle : nil; }

#include "asf-real.inc"   // (kStageBarHeight, gFitGroup, gFitSlots, DMFitGroupForget, DMTitleRecordHandEnded, then DMAerialPanBefore ... DMAerialGestureAfter)

static void (*o5_pan)(id, SEL, id), (*o5_resizeBR)(id, SEL, id);
static void KO5Pan(id self, SEL _cmd, id g) { [(KStage *)self k_origPan:g]; }
static void KO5Resize(id self, SEL _cmd, id g) { [(KStage *)self k_origResize:g]; }
#include "asf-h5.inc"     // (h5_pan, h5_resizeBR)

@implementation KStage
- (void)k_origPan:(id)g { [self.origPan addObject:@([(UIGestureRecognizer *)g state])]; }
- (void)k_origResize:(id)g { [self.origResize addObject:@([(UIGestureRecognizer *)g state])]; }
#include "asf-hooks.inc"  // (-handlePan:, -handleResizeBR:: the %hook AerialStage bodies)
- (void)k5Pan:(id)g { h5_pan(self, _cmd, g); }
- (void)k5Resize:(id)g { h5_resizeBR(self, _cmd, g); }
@end

// ---- Aerial's recogniser: a real UIPanGestureRecognizer; its state, touches and travel set by the test, its action sent by the test as UIKit would
@interface KPan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState kState;
@property (nonatomic) NSUInteger kTouches;
@property (nonatomic) CGPoint kHere, kMoved;   // (in the window)
@property (nonatomic, weak) id kTarget;
@property (nonatomic) SEL kAction;
@property (nonatomic) BOOL kOn, kLater, kPending;
@property (nonatomic) int kCancels;
- (void)send;
@end
@implementation KPan
- (UIGestureRecognizerState)state { return self.kState; }
- (NSUInteger)numberOfTouches { return self.kTouches; }
- (CGPoint)locationInView:(UIView *)v { return self.kHere; }
- (CGPoint)translationInView:(UIView *)v { return self.kMoved; }
- (BOOL)isEnabled { return self.kOn; }
- (void)setEnabled:(BOOL)on {
    BOOL was = self.kOn; self.kOn = on;
    if (was && !on && (self.kState == UIGestureRecognizerStateBegan || self.kState == UIGestureRecognizerStateChanged)) {
        self.kState = UIGestureRecognizerStateCancelled; self.kCancels++;   // (UIKit: cancelled, and the action is sent with that state)
        if (self.kLater) self.kPending = YES;
        else { [self send]; self.kState = UIGestureRecognizerStatePossible; }
    }
}
- (void)send { ((void (*)(id, SEL, id))objc_msgSend)(self.kTarget, self.kAction, self); }
@end
static KPan *NewPan(KStage *st, SEL action, BOOL later) {
    KPan *g = [[KPan alloc] initWithTarget:nil action:NULL];
    g.kTarget = st; g.kAction = action; g.kLater = later; g.kOn = YES; g.kTouches = 1;
    return g;
}
static void Send(KPan *g, UIGestureRecognizerState s) {
    g.kState = s; [g send];
    if (g.kPending) { g.kPending = NO; [g send]; g.kState = UIGestureRecognizerStatePossible; }   // (the Cancelled call after the current one)
}
// A drag that went down at `down` (in the window) and began 15 pt lower (the recogniser's threshold); touches 0 = a trackpad scroll (no finger)
static void Begin(KPan *g, CGPoint down, NSUInteger touches) {
    g.kTouches = touches;
    g.kMoved = touches ? CGPointMake(0, 15) : CGPointZero;
    g.kHere = touches ? CGPointMake(down.x, down.y + 15) : down;
    Send(g, UIGestureRecognizerStateBegan);
}

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static NSString *const kNotes = @"com.apple.mobilenotes", *const kSafari = @"com.apple.mobilesafari";
static KStage *gStage;
static void Setup(void) {
    gKLog = [NSMutableArray array];
    gFitGroup = [NSMutableArray arrayWithObjects:kNotes, kSafari, nil];   // (Fit to Window: Notes and Safari as halves)
    gFitSlots = [@{ kNotes: @"left", kSafari: @"right" } mutableCopy];
    gKMovedRec = gKCovered = gKSnaps = gKRemembered = gKSaved = 0; gKShift = 0;
    gStage = [[KStage alloc] initWithFrame:CGRectMake(0, 24, 683, 1000)];
    gStage.bundle = kNotes; gStage.origPan = [NSMutableArray array]; gStage.origResize = [NSMutableArray array];
    o5_pan = KO5Pan; o5_resizeBR = KO5Resize;
}
static BOOL Tiled(NSString *b) { return [gFitGroup containsObject:b] && gFitSlots[b] != nil; }
static BOOL Untouched(void) { return Tiled(kNotes) && Tiled(kSafari) && !gKMovedRec && !gKCovered && !gKSnaps && !gKRemembered && !gKSaved; }
static BOOL Moving(void) { return [objc_getAssociatedObject(gStage, kStageGestureKey) boolValue]; }
static BOOL OrigWas(NSArray<NSNumber *> *got, NSArray<NSNumber *> *want) { return [got isEqualToArray:want]; }
#define B @(UIGestureRecognizerStateBegan)
#define C @(UIGestureRecognizerStateChanged)
#define E @(UIGestureRecognizerStateEnded)
#define X @(UIGestureRecognizerStateCancelled)

int main(void) {
    @autoreleasepool {
        for (int later = 0; later <= 1; later++) {
            NSString *how = later ? @"the Cancelled call after the start's" : @"the Cancelled call inside the switch";
            // -- the audit's case: Fit to Window, two halves, a page scrolled in the left window
            Setup();
            { KPan *g = NewPan(gStage, @selector(handlePan:), later); Begin(g, CGPointMake(300, 400), 1);
              Check(g.kCancels == 1 && Untouched() && !Moving(),
                    [NSString stringWithFormat:@"Aerial 3.0, %@: a page scrolled in a tiled window: the drag is refused and the window keeps its tile (Fit's group and slot), no place remembered or saved, the title bar's way back kept, no snap", how]);
              Check(OrigWas(gStage.origPan, @[X]), [NSString stringWithFormat:@"  ... Aerial's own drag never sees the start and gets the Cancelled call (unchanged, %@)", how]);
              if (!later) Check(gKLog.count == 1 && [gKLog[0] containsString:@"does not move it"], @"  ... logged: \"a drag that started inside the window (y 400, scroll 0) does not move it\" (unchanged)"); }
            // -- a trackpad's two-finger scroll (no touch)
            Setup();
            { KPan *g = NewPan(gStage, @selector(handlePan:), later); Begin(g, CGPointMake(300, 10), 0);
              Check(g.kCancels == 1 && g.allowedScrollTypesMask == 0 && Untouched(), [NSString stringWithFormat:@"  ... a trackpad scroll, even over the title bar: refused, scrolling kept off the drag, the window keeps its tile (%@)", how]); }
            // -- every scroll: ten in a row
            Setup();
            { KPan *g = NewPan(gStage, @selector(handlePan:), later); for (int i = 0; i < 10; i++) Begin(g, CGPointMake(200, 300 + 20 * i), 1);
              Check(g.kCancels == 10 && Untouched(), [NSString stringWithFormat:@"  ... ten scrolls in a row: still tiled, nothing saved (%@)", how]); }
        }
        // -- a move by its title bar, let go: the move by hand ends as before
        Setup();
        { KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 10), 1);
          BOOL moving = Moving();
          g.kMoved = CGPointMake(40, 200); Send(g, UIGestureRecognizerStateChanged); Send(g, UIGestureRecognizerStateEnded);
          Check(g.kCancels == 0 && moving && !Moving() && !Tiled(kNotes) && Tiled(kSafari) && gKSnaps == 1 && gKRemembered == 1 && gKSaved == 1 && gKMovedRec == 1 && gKCovered == 1
                && OrigWas(gStage.origPan, @[B, C, E]),
                @"a title-bar drag let go: a drag by hand while it runs, then it snaps, its place is remembered and saved, it leaves the tiles (Safari keeps its), the way back is dropped (unchanged)"); }
        // -- the title bar slid down by the auto-hiding status bar: a drag from lower in it is still the title bar's
        Setup();
        { gKShift = 20; KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 40), 1);
          Send(g, UIGestureRecognizerStateEnded);
          Check(g.kCancels == 0 && !Tiled(kNotes) && gKRemembered == 1, @"  ... the title bar slid 20 pt down: a drag from y 40 moves the window (unchanged)"); }
        Setup();
        { KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 40), 1);
          Check(g.kCancels == 1 && Untouched(), @"  ... not slid: a drag from y 40 is inside the window and the window keeps its tile"); }
        // -- a move by hand cut short (the system cancels it after its start): ended all the same (review 1.8.3 L2)
        Setup();
        { KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 10), 1);
          g.kMoved = CGPointMake(0, 120); Send(g, UIGestureRecognizerStateChanged); Send(g, UIGestureRecognizerStateCancelled);
          Check(!Moving() && !Tiled(kNotes) && gKSnaps == 0 && gKRemembered == 1 && gKSaved == 1 && gKMovedRec == 1 && gKCovered == 1,
                @"  ... a title-bar drag cut short after its start: no snap, but its place is remembered and saved, it leaves the tiles, the way back is dropped (unchanged)"); }
        // -- a resize by Aerial's corner
        Setup();
        { KPan *r = NewPan(gStage, @selector(handleResizeBR:), NO); Send(r, UIGestureRecognizerStateBegan);
          BOOL moving = Moving();
          Send(r, UIGestureRecognizerStateChanged); Send(r, UIGestureRecognizerStateEnded);
          Check(moving && !Moving() && !Tiled(kNotes) && gKRemembered == 1 && gKMovedRec == 1 && gKCovered == 1 && gKSaved == 0 && gKSnaps == 0 && OrigWas(gStage.origResize, @[B, C, E]),
                @"a resize by the corner: a gesture by hand while it runs, then its place is remembered, it leaves the tiles, the way back is dropped, not saved here, no move snap (unchanged)"); }
        // -- a page scrolled while the corner is being dragged: the resize goes on and ends as one
        Setup();
        { KPan *r = NewPan(gStage, @selector(handleResizeBR:), NO), *g = NewPan(gStage, @selector(handlePan:), NO);
          Send(r, UIGestureRecognizerStateBegan); Begin(g, CGPointMake(200, 500), 1);
          BOOL during = Moving() && Tiled(kNotes) && gKRemembered == 0;
          Send(r, UIGestureRecognizerStateEnded);
          Check(during && !Moving() && !Tiled(kNotes) && gKRemembered == 1 && gKMovedRec == 1,
                @"a page scrolled while the corner is dragged: the resize is still a gesture by hand until its own end, which then acts once"); }
        // -- the mark is written at each start: a drag whose end never came is not a later refused drag's
        Setup();
        { KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 10), 1); Send(g, UIGestureRecognizerStateChanged);   // (no end)
          g.kState = UIGestureRecognizerStatePossible; Begin(g, CGPointMake(300, 400), 1);
          Check(g.kCancels == 1 && Untouched(), @"a drag whose end never came, then a page scrolled with the same recogniser: the scroll still moves nothing (the mark is written at each start)"); }
        // -- a refused drag, then a real one with the same recogniser
        Setup();
        { KPan *g = NewPan(gStage, @selector(handlePan:), NO); Begin(g, CGPointMake(300, 400), 1);
          Begin(g, CGPointMake(300, 8), 1); Send(g, UIGestureRecognizerStateEnded);
          Check(g.kCancels == 1 && !Tiled(kNotes) && gKRemembered == 1 && gKSnaps == 1 && gKSaved == 1, @"  ... a page scrolled, then a title-bar drag with the same recogniser: only the drag acts, once"); }
        // -- the 5.0 reference functions (never installed: Aerial 5.0 is not hooked) behave the same
        Setup();
        { KPan *g = NewPan(gStage, @selector(k5Pan:), NO); Begin(g, CGPointMake(300, 400), 1);
          Check(g.kCancels == 1 && Untouched() && OrigWas(gStage.origPan, @[X]), @"h5_pan (5.0 reference): a page scrolled in a tiled window: refused, the window keeps its tile"); }
        Setup();
        { KPan *g = NewPan(gStage, @selector(k5Pan:), NO); Begin(g, CGPointMake(300, 10), 1); Send(g, UIGestureRecognizerStateEnded);
          Check(!Tiled(kNotes) && gKSnaps == 1 && gKRemembered == 1 && gKSaved == 1 && OrigWas(gStage.origPan, @[B, E]), @"  ... a title-bar drag let go acts as before (unchanged)"); }
        Setup();
        { KPan *r = NewPan(gStage, @selector(k5Resize:), NO); Send(r, UIGestureRecognizerStateBegan); BOOL moving = Moving(); Send(r, UIGestureRecognizerStateEnded);
          Check(moving && !Moving() && !Tiled(kNotes) && gKRemembered == 1 && gKSaved == 0 && OrigWas(gStage.origResize, @[B, E]), @"  ... h5_resizeBR: a resize by the corner acts as before (unchanged)"); }
    }
    printf("test-aerialscrollfit: %d of %d checks pass\n", gChecks - gFails, gChecks);
    return gFails;
}
