// test-autohidetop.m -- Mac test (Mac Catalyst: UIKit on the Mac) of one window top for every engine while the menu bar hides itself (1.8.8.4,
// engine parity, KT 23 Nov: "We should match the other engines in this version"): with "Automatically Hide and Show the Menu Bar" on and a pointer
// attached, Aerial's, Zetsu's and MilkyWay4's windows reach the screen's top edge, are moved up there when it turns on and back under the bar when it
// turns off, and their title bars slide down with the bar when it comes in; our Stage Manager engine now does exactly the same.
// Built by test-autohidetop.sh on test-smpastedge.m's harness (its own checks left out: its main is renamed), with StatusBar.x's real code cut out:
//  1. the retop, both ways, of the same windows through the other engines' DMAutoHideRetopAll (their windows: views moved by DMAerialMoveStage) and
//     through ours, DMAutoHideSMRetop (Stage Manager's windows: their attributes, the request a stand-in that hands them to Stage Manager through the
//     real DMSMAttrsForFrameIn and DMSMAttrsFitScreen, as our requests' DMSMPlanFitted does): the same frames; ours also when Stage Manager's own pass
//     moved a window down first, a window past an edge (F47's record follows it), Fit's tiles, a TV's stage, a switch that has to wait, the 4 tries;
//  2. our title bars: the slide (DMAutoHideSMSlideBars, DMAutoHideSMSlideFor, DMSMBarFrameNow) by the rule the other engines' step uses
//     (BarAutoHide.h MSBDBarAHTitleSlide), and a drag on a slid title bar through the real -[DMSMTitleBar dm_pan:] (DMAutoHideSMBake), on a card
//     built as SpringBoard's (TSBCard: the title bar in its inner clipping view; DMAutoHideSMCardOf);
//  3. Stage Manager's stage top: our _statusBarHeight answer (the real hook's body) and DMSMStageTopByDisplay for the iPad and a TV, the desktop
//     (DMSMUsableAreaForIdentity) and the size grid's top (DMSMTopBarOf);
//  5. the tick after the setting goes off (DMAutoHideStopTimerLater): on while our windows wait to go under the bar, stopped at once when it is on again.
#define SPE_REAL_DESK 1
#define SPE_REAL_BAKE 1
#define main spe_harness_main
#include "test-smpastedge.m"
#undef main
#include "../common/MenuBarSize.h"

// ---- the other engines' side (DMAutoHideRetopAll): their windows are views; DMAerialMoveStage puts one at its frame ----
static NSMutableArray<UIView *> *gOStages;
static UIWindow *gOWin;   // (their windows are in a window of SpringBoard's: on screen)
static NSMutableArray<NSString *> *gFitGroup;
static NSArray<UIView *> *DMAerialStages(void) { return gOStages; }
static NSString *DMStageBundle(UIView *st) { return st.accessibilityIdentifier; }
static BOOL DMStageMinimized(UIView *st) { (void)st; return NO; }
static CFTimeInterval gSBTurnAt = -10;
static CGRect DMLayoutFrame(NSString *name) { (void)name; return DMUsableArea(); }   // (Fill: the whole desktop)
static CGFloat DMAutoHideShiftOf(UIView *st) { (void)st; return 0.0; }
static void DMAutoHideUnshift(UIView *st) { (void)st; }
static void DMAerialMoveStage(UIView *st, CGRect f, id how) { (void)how; st.frame = f; }

// ---- ours (DMAutoHideSMRetop): the stage on screen is gTWindows (key -> its attributes, test-smpastedge.m's TAttrs) ----
static BOOL gSMRestoreDone = YES, gMSWSwitching = NO, gTBusy = NO, gTLiveGesture = NO, gDMScreenOff = NO;
static id gOverlay;
static NSMutableDictionary *gSMGrowing;
static BOOL DMSMHomeUILocked(void) { return NO; }
static BOOL DMCoverSheetShown(void) { return NO; }
static BOOL DMSMWorkspaceBusy(void) { return gTBusy; }
static BOOL DMSMTurnSettling(void) { return NO; }
static BOOL DMSMGestureLive(void) { return gTLiveGesture; }
static BOOL DMSwitcherVisible(void) { return NO; }
static BOOL DMSMSpotlightHolds(void) { return NO; }
static BOOL gTStageOnTV = NO;
static BOOL gTNoStage = NO;   // (the Home Screen: no stage of the iPad's shown)
static id DMSMIPadStageShown(void) { return gTNoStage ? nil : @"stage"; }
static id DMSMStageDisplayIdentity(id stage) { (void)stage; return gTStageOnTV ? @"tv" : @"main"; }
static CGRect DMSMLayoutFrameIn(NSString *name, CGRect u, CGSize screen) { (void)name; (void)screen; return u; }   // (Fill: the whole desktop)
static BOOL gTFit = NO;
static BOOL DMFitEnabled(void) { return gTFit; }
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSDictionary *DMSMStageItemsMap(id stage) { (void)stage; return gTWindows; }
// (DMSMItemKey: test-smpastedge.m's, 1.8.9 B114 -- the stage's items are their keys)
static UIView *DMSMCardFor(NSString *key) { (void)key; return nil; }
static BOOL DMSMCardIsFullSize(UIView *card) { (void)card; return NO; }
static int gTPlaced;
static id DMSMAttrPlacedByUser(id attrs) { return attrs; }
static CGRect DMSMUsableAreaForStage(id stage, CGSize *screenOut) { return DMSMUsableAreaForIdentity(DMSMStageDisplayIdentity(stage), screenOut); }
static id DMSMAttrsForFrameIn(id attrs, CGRect w, id stage);
static int gTRequests; static NSSet *gTUsers;
static BOOL gTPutBack = NO;   // (Stage Manager puts the window back where it was after each request)
// Our request (DMSMRequestOn): every window handed to Stage Manager fitted as DMSMPlanFitted fits it -- the real DMSMAttrsFitScreen.
static BOOL DMSMApplyPlacesMarkedIn(NSDictionary<NSString *, id> *places, id stage, NSSet<NSString *> *user) {
    gTRequests++; gTUsers = user;
    if (gTPutBack) return YES;
    for (NSString *k in places) {
        id a = DMSMAttrsForFrameIn(gTWindows[k], [places[k] CGRectValue], stage);
        id f = a ? DMSMAttrsFitScreen(a, gTStageOnTV ? @"tv" : nil, DMSMKeySetHas(gSMBehindDock, k), k) : nil;
        if (f) gTWindows[k] = f;
    }
    return YES;
}
static void DMTitleRecordFollowDesktopView(UIView *v, CGRect oldFill, CGRect newFill) { (void)v; (void)oldFill; (void)newFill; }
static void DMTitleRecordFollowDesktopSM(NSString *key, CGRect oldFill, CGRect newFill) { (void)key; (void)oldFill; (void)newFill; }
#include "aht-retop.inc"   // (StatusBar.x: DMAutoHideRetopAll and its keys; DMAutoHideSMRetop, DMAutoHideSMWindowFrame, its globals; DMSMPastEdgeMoved, DMSMAttrsForFrameIn)

// ---- our title bars: DMSMBarFrame as on iPadOS 16 (the bar on the card's top edge, 24 pt) ----
static CGRect DMSMBarFrame(UIView *card) { return CGRectMake(0, -kSMBarH, card.bounds.size.width, kSMBarH); }
static int gTChromeRaised = 0;
static void DMSMChromeOnTop(UIView *card, UIView *bar) { (void)card; if (bar.superview) { [bar.superview bringSubviewToFront:bar]; gTChromeRaised++; } }
static NSHashTable *gSMBars;
#include "aht-slide.inc"   // (StatusBar.x: gSMSlideBarH, DMAutoHideSMSlideFor, DMSMBarFrameNow, DMAutoHideSMSlideDrawn, DMAutoHideSMBarDragged, DMAutoHideSMSlideBars, DMAutoHideSMBake)
// ---- a new window: the other engines' DMNewWindowFrameWindowAt and ours, DMSMNewWindowDesk / DMSMNewWindowFrameAt ----
#include "../common/WindowSize.h"
#include "../common/AppWindowSize.h"
static CGFloat DMCenterTopFor(CGSize s) { (void)s; return 36.0; }   // (the middle place's top: 12 pt under the 24 pt bar)
static CGRect DMLayoutFrameWindow(NSString *name) { (void)name; return MSBDWindowCenterIn(DMUsableArea(), gIPad.size, DMCenterTopFor(gIPad.size)); }   // (the center layout: the middle place)
static CGFloat DMSMMinWindowWidth(CGSize s) { (void)s; return 320.0; }   // (Stage Manager's smallest window width)
#include "aht-newwin.inc"   // (StatusBar.x: DMNewWindowFrameWindowAt, DMSMNewWindowDesk, DMSMNewWindowFrameAt)

static CGRect WholeOf(NSString *k) { return DMAutoHideSMWindowFrame(gTWindows[k], k, gIPad.size, YES); }   // (our window as Stage Manager lays it out)
static BOOL RectNear(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 0.01 && fabs(a.origin.y - b.origin.y) < 0.01 && fabs(a.size.width - b.size.width) < 0.01 && fabs(a.size.height - b.size.height) < 0.01; }
static NSString *R(CGRect r) { return NSStringFromCGRect(r); }
static NSString *const kA = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-1A", *const kB = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-2B";
static NSString *const kC = @"com.apple.Preferences|sceneID:com.apple.Preferences-3C", *const kD = @"com.apple.tips|sceneID:com.apple.tips-4D";
static void PutSM(NSString *k, CGRect whole) {   // (a Stage Manager window: its card under our 24 pt bar)
    gTWindows[k] = Attrs(CGSizeMake(whole.size.width, whole.size.height - kSMBarH), CGPointMake(CGRectGetMidX(whole), whole.origin.y + kSMBarH + (whole.size.height - kSMBarH) / 2.0), gIPad.size);
}
static UIView *PutOther(NSString *b, CGRect f) { UIView *v = [[UIView alloc] initWithFrame:f]; v.accessibilityIdentifier = b; [gOWin addSubview:v]; [gOStages addObject:v]; return v; }
// A window card as SpringBoard builds it (SBFluidSwitcherItemContainer): it hands the views added to it to its inner clipping view
// (_SBFActualClippingView, at the card's own bounds), so our title bar's superview is that view, never the card (StatusBar.x DMSMChromeOnTop, read on
// the iPad's view tree). The first 1.8.8.4 device passes: with the bar straight in a plain card here, the slide passed on the Mac while on the iPad every
// show and hide of the menu bar moved no title bar. Every slide and drag case below runs on such a card.
@interface TSBCard : UIView
@property (nonatomic, strong) UIView *clip;
@end
@implementation TSBCard
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _clip = [[UIView alloc] initWithFrame:self.bounds];
        _clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [super addSubview:_clip];
    }
    return self;
}
- (void)addSubview:(UIView *)v { if (v == _clip) [super addSubview:v]; else [_clip addSubview:v]; }
@end
static void SBCard(void) {   // (after Setup: its card replaced by SpringBoard's kind, at the same place; the bar is the new card's)
    TSBCard *c = [[TSBCard alloc] initWithFrame:gCard.frame];
    [gCard removeFromSuperview]; [gSup addSubview:c];
    gCard = c; gBar.card = c;
}
@interface TTapTouch : KTouch
@property (nonatomic, weak) UIView *kView;
@end
@implementation TTapTouch
- (UIView *)view { return self.kView; }
@end

int main(void) {
    @autoreleasepool {
        const CGSize pad = CGSizeMake(1194, 834);   // (an 11-inch iPad in landscape: the Dock's line at 834 - 117 - 2 = 715)
        Setup(pad, kA, CGRectMake(100, 48, 500, 376), NO);
        ClearRecords();
        gOWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, pad.width, pad.height)];
        gOStages = [NSMutableArray array]; gFitGroup = [NSMutableArray array]; gSMFitSlots = [NSMutableDictionary dictionary];

        // ==== 3 first (a fresh start: the answer without the bar's room not given yet). Stage Manager's stage top: our answer, a pass's top ====
        gTAH = NO;
        Check(Near(TSMStatusBarHeight(), 48), [NSString stringWithFormat:@"stage top: under the 24 pt bar, our 24 pt title bar under it: 48 (%.1f)", TSMStatusBarHeight()]);
        CGRect b = CGRectMake(0, 0, pad.width, pad.height), tvB = CGRectMake(0, 0, 1920, 1080);
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 48, 1194, 667), b).origin.y, 48), @"stage top: the iPad's pass at our answer: as it is");
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 24, 1194, 691), b).origin.y, 24), @"stage top: a pass at 24 before the bar ever hid itself (24 is also iOS's own height): left as it is -- nothing changes with auto-hide never on");
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 48, 1920, 900), tvB).origin.y, 48), @"stage top: a TV's pass (its bar the iPad's size): 48 as before");
        Check(Near(DMSMUsableAreaForIdentity(nil, NULL).origin.y, 24) && Near(DMSMTopBarOf(pad), 24), @"desktop: the iPad's under the bar (24), the size grid's top 24");
        gTAH = YES;   // (auto-hide on, a pointer attached)
        Check(Near(TSMStatusBarHeight(), 24), [NSString stringWithFormat:@"stage top, the bar hiding itself: our title bar at the screen's top edge, the window under it: 24 (%.1f), as every engine's windows reach the top", TSMStatusBarHeight()]);
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 24, 1194, 691), b).origin.y, 24), @"  ... the iPad's pass at the new answer: as it is");
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 48, 1194, 667), b).origin.y, 24), @"  ... a pass made from layout attributes of before the switch (48): the top for now, 24");
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 24, 1920, 1056), tvB).origin.y, 48), @"  ... a TV's pass carrying the iPad's 24: the TV keeps its bar's room, 48 (its bar the iPad's size)");
        gTTVSize = 2; gTTVBarH = 37.0;
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 24, 1920, 1056), tvB).origin.y, 61), @"  ... the TV's bar at Large (37): 37 + 24, the iPad's bar hiding or not");
        Check(Near(DMSMStageTopByDisplay(CGRectMake(0, 90, 1920, 990), tvB).origin.y, 90), @"  ... a top of Apple's own on the TV: as it is");
        gTTVSize = 0; gTTVBarH = 24.0;
        Check(Near(DMSMUsableAreaForIdentity(nil, NULL).origin.y, 0) && Near(DMSMTopBarOf(pad), 0) && Near(DMSMUsableAreaForIdentity(@"tv", NULL).origin.y, 24) && Near(DMSMTopBarOf(CGSizeMake(1920, 1080)), 24),
              @"desktop: the iPad's from the screen's top edge (0), as the other engines' DMUsableArea; the size grid's top 0 (a full-height window may grow); the TV's under its bar");
        gTAH = NO;
        Check(Near(TSMStatusBarHeight(), 48) && Near(DMSMStageTopByDisplay(CGRectMake(0, 24, 1194, 691), b).origin.y, 48), @"stage top, the bar shown again: 48, and a pass still carrying 24 gets 48");

        // ==== 1. the retop: the same windows on the other engines and on ours ====
        // (whole windows, title bars included: one at the bar's line, a full-height one, one lower on the screen, one past the left edge at the line)
        const CGRect wLine = CGRectMake(100, 24, 500, 400), wFull = CGRectMake(640, 24, 500, 691), wLow = CGRectMake(300, 300, 400, 300), wPast = CGRectMake(-300, 24, 500, 400);
        [gTWindows removeAllObjects]; PutSM(kA, wLine); PutSM(kB, wFull); PutSM(kC, wLow); PutSM(kD, wPast);
        gSMPastEdge = [NSMutableDictionary dictionary]; gSMPastEdgeOrder = [NSMutableArray arrayWithObject:kD];
        gSMPastEdge[kD] = @[[NSValue valueWithCGPoint:CGPointMake(-50, 236)], [NSValue valueWithCGSize:CGSizeMake(500, 376)], [NSValue valueWithCGSize:pad]];   // (let go past the left edge there)
        UIView *oLine = PutOther(@"a", wLine), *oFull = PutOther(@"b", wFull), *oLow = PutOther(@"c", wLow), *oPast = PutOther(@"d", wPast);
        gTAH = YES;
        DMAutoHideRetopAll(YES, NO, YES);
        gTRequests = 0; DMAutoHideSMRetop(YES, YES, YES);
        Check(RectNear(oLine.frame, CGRectMake(100, 0, 500, 400)) && RectNear(WholeOf(kA), oLine.frame), [NSString stringWithFormat:@"retop, on: a window at the bar's line up to the top edge, the same on both (theirs %@, ours %@)", R(oLine.frame), R(WholeOf(kA))]);
        Check(RectNear(oFull.frame, CGRectMake(640, 0, 500, 715)) && RectNear(WholeOf(kB), oFull.frame), [NSString stringWithFormat:@"retop, on: a full-height window up, its bottom kept on the Dock's line (theirs %@, ours %@)", R(oFull.frame), R(WholeOf(kB))]);
        Check(RectNear(oLow.frame, wLow) && RectNear(WholeOf(kC), wLow), @"retop, on: a window lower on the screen stays, on both");
        Check(RectNear(oPast.frame, CGRectMake(-300, 0, 500, 400)) && RectNear(WholeOf(kD), oPast.frame) && RecIs(kD, -50, 212, 500, 376, 1194, 834),
              [NSString stringWithFormat:@"retop, on: one past the left edge up too, still past it on ours (its record moved with it, so the request keeps it there) (theirs %@, ours %@)", R(oPast.frame), R(WholeOf(kD))]);
        Check(gTRequests == 1 && gTUsers.count == 3 && [gTUsers containsObject:kA] && ![gTUsers containsObject:kC], [NSString stringWithFormat:@"retop, on: ours in one request for the three that moved, each kept the user's (requests %d)", gTRequests]);
        DMAutoHideRetopAll(YES, NO, NO);
        gTRequests = 0; DMAutoHideSMRetop(YES, YES, NO);
        Check(gTRequests == 0 && RectNear(WholeOf(kA), oLine.frame), @"retop, the next second: nothing more to do on either");
        int reads = gTUsableReads; gSMRetopAt = 0; gTRequests = 0; DMAutoHideSMRetop(YES, YES, NO);
        Check(gTUsableReads == reads && gTRequests == 0, @"retop, once a second at rest (every window at the top edge or lower): only the stage read, not the desktop (its Dock measured from views) or Fill");
        gTAH = NO;
        DMAutoHideRetopAll(NO, NO, YES);
        gTRequests = 0; DMAutoHideSMRetop(NO, NO, YES);
        Check(RectNear(oLine.frame, wLine) && RectNear(WholeOf(kA), wLine), [NSString stringWithFormat:@"retop, off: back under the bar, the same on both (theirs %@, ours %@)", R(oLine.frame), R(WholeOf(kA))]);
        Check(RectNear(oFull.frame, wFull) && RectNear(WholeOf(kB), wFull), [NSString stringWithFormat:@"retop, off: the full-height window shrinks under the bar, its bottom kept (theirs %@, ours %@)", R(oFull.frame), R(WholeOf(kB))]);
        Check(RectNear(oPast.frame, wPast) && RectNear(WholeOf(kD), wPast) && RecIs(kD, -50, 236, 500, 376, 1194, 834), @"retop, off: the one past the edge under the bar again, still past it on ours, its record with it");
        // (taken back after Stage Manager's own pass moved our full-height window down whole -- the stage area is under the bar from the switch on: its
        //  bottom 24 pt past the Dock's line, no longer in the bar's room. Ours fits it as every request of ours does)
        gTAH = YES; DMAutoHideSMRetop(YES, YES, YES); gTAH = NO;
        PutSM(kB, CGRectMake(640, 24, 500, 715));
        gTRequests = 0; DMAutoHideSMRetop(NO, NO, YES);
        Check(RectNear(WholeOf(kB), wFull) && gTRequests == 1, [NSString stringWithFormat:@"retop, off: a full-height window Stage Manager's pass moved down first: fitted under the bar, its bottom on the Dock's line again (%@)", R(WholeOf(kB))]);
        // (a switch while a transition is in flight waits for the next tick, which runs on while it waits)
        PutSM(kA, CGRectMake(100, 0, 500, 400));
        gTBusy = YES; gTRequests = 0; DMAutoHideSMRetop(NO, NO, YES);
        Check(gTRequests == 0 && gSMRetopPending == 0, @"retop, off while a transition is in flight: waits (pending)");
        gTBusy = NO; DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 1 && RectNear(WholeOf(kA), wLine) && gSMRetopPending == -1, @"  ... done at the next tick");
        PutSM(kA, CGRectMake(100, 0, 500, 400));
        gTLiveGesture = YES; gTRequests = 0; DMAutoHideSMRetop(NO, NO, YES);
        Check(gTRequests == 0 && gSMRetopPending == 0, @"retop, while a Stage Manager resize or move gesture is live: waits (never yanks a dragged top edge)");
        gTLiveGesture = NO; DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 1 && RectNear(WholeOf(kA), wLine) && gSMRetopPending == -1, @"  ... done once the live gesture ends");
        // (a switch at the Home Screen, no stage shown: it waits for the stage to be shown again)
        PutSM(kA, CGRectMake(100, 0, 500, 400));
        gTNoStage = YES; gTRequests = 0; DMAutoHideSMRetop(NO, NO, YES); DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 0 && gSMRetopPending == 0, @"retop, off at the Home Screen (no stage shown): waits");
        gTNoStage = NO; DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 0 && gSMRetopPending == 0, @"  ... looked at again once a second there, not on every tick");
        gSMRetopAt = 0; DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 1 && RectNear(WholeOf(kA), wLine) && gSMRetopPending == -1, @"  ... done once the stage is shown again");
        // (Fit's tiles are Fit's own; a TV's stage keeps its bar's room)
        gTFit = YES; gSMFitSlots[kA] = @"left"; gSMFitSlots[kB] = @"right"; PutSM(kA, wLine);
        gTAH = YES; gTRequests = 0; DMAutoHideSMRetop(YES, YES, YES);
        Check(RectNear(WholeOf(kA), wLine) && gTRequests == 1, @"retop, on with Fit to Window: its tiles left to Fit (laid out again by Fit at the switch), the other windows moved");
        gTFit = NO; [gSMFitSlots removeAllObjects];
        gTStageOnTV = YES; PutSM(kA, wLine); gTRequests = 0; DMAutoHideSMRetop(YES, YES, YES);
        Check(gTRequests == 0 && RectNear(WholeOf(kA), wLine), @"retop: a TV's stage is left alone (its bar's room is kept)");
        gTStageOnTV = NO;
        // (at most 4 moves per window and mode, as the other engines: Stage Manager keeps putting it back)
        gTPutBack = YES; gTRequests = 0; DMAutoHideSMRetop(YES, YES, YES);
        for (int i = 0; i < 6; i++) { gSMRetopAt = 0; DMAutoHideSMRetop(YES, YES, NO); }
        Check(gTRequests == 4, [NSString stringWithFormat:@"retop: a window Stage Manager keeps putting back is asked for 4 times, then left alone (asked %d)", gTRequests]);
        gTPutBack = NO; gTAH = NO;
        gTRequests = 0; DMAutoHideSMRetop(NO, NO, NO);
        Check(gTRequests == 0, @"retop: auto-hide off, no switch waiting: nothing runs (nothing at rest)");

        // ==== 2. our title bars slide down with the bar, by the other engines' rule; a drag on a slid one ====
        ClearRecords();
        Setup(pad, kA, CGRectMake(100, 24, 500, 376), NO);   // (the whole window at the screen's top edge)
        SBCard(); [gCard addSubview:gBar]; gBar.frame = DMSMBarFrame(gCard);
        Check(gBar.superview != gCard && [gBar isDescendantOfView:gCard], @"slide: the title bar is in its card's inner clipping view, as SpringBoard's card holds it (not the card's own subview)");
        gSMBars = [NSHashTable weakObjectsHashTable]; [gSMBars addObject:gBar];
        gTAH = YES;
        DMAutoHideSMSlideBars(YES, 24.0, NO);
        Check(Near(gBar.frame.origin.y, 0) && Near(DMAutoHideSMSlideDrawn(gBar), 24) && Near(DMAutoHideSMSlideDrawn(gBar), MSBDBarAHTitleSlide(0, 24, 23, 1)),
              [NSString stringWithFormat:@"slide: the bar shows over a window at the top edge: its title bar 24 pt down over the app, as the other engines' (bar at %.1f)", gBar.frame.origin.y]);
        {
            UIView *content = [[UIView alloc] initWithFrame:gCard.bounds];
            [gCard addSubview:content];   // (SpringBoard puts _killScrollView above our bar in _SBFActualClippingView)
            UIButton *yellow = [UIButton buttonWithType:UIButtonTypeCustom]; yellow.frame = CGRectMake(28, 2, 20, 20); [gBar addSubview:yellow];
            DMAutoHideSMSlideBars(YES, 24.0, YES);
            UIView *hit = [gCard hitTest:CGPointMake(38, 12) withEvent:nil];
            UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
            TTapTouch *lt = [TTapTouch new];
            lt.kAt = CGPointMake(38, 12); lt.kPhase = UITouchPhaseBegan; lt.kType = UITouchTypeDirect; lt.kWin = gCard.window; lt.kView = yellow;
            BOOL tapTakesLight = [gBar gestureRecognizer:singleTap shouldReceiveTouch:lt];
            Check(((TSBCard *)gCard).clip.subviews.lastObject == gBar && hit == yellow && !tapTakesLight,
                  @"slide: a slid title bar stays above the card's content, hits its traffic light during the 0.25 s slide, and the bar's single-tap leaves UIControl touches to the light");
            [yellow removeFromSuperview]; [content removeFromSuperview];
        }
        Check(CGRectEqualToRect(DMSMBarFrameNow(gCard, gBar), gBar.frame), @"slide: ... and the card's own layout keeps it (the bar's frame worked out the same)");
        DMAutoHideSMSlideBars(NO, 0, NO);
        Check(Near(gBar.frame.origin.y, -24) && Near(DMAutoHideSMSlideDrawn(gBar), 0), @"slide: the bar hides: the title bar back up");
        // (auto-hide turned on while the bar shows: the window goes up to the top edge and its card's own layout slides its title bar -- DMSMChrome sets
        //  bar.frame = DMSMBarFrameNow --; the bar then hides: the slide is taken back. On the iPad it stayed down: a band of wallpaper above the window)
        gCard.frame = CGRectMake(100, 300, 500, 376); gBar.frame = DMSMBarFrame(gCard);
        DMAutoHideSMSlideBars(YES, 24.0, NO);   // (the bar shows; the window lower: nothing to slide yet)
        gCard.frame = CGRectMake(100, 24, 500, 376); gBar.frame = DMSMBarFrameNow(gCard, gBar);   // (the retop: the window up, its card laid out)
        Check(Near(gBar.frame.origin.y, 0), @"slide: the window moved up while the bar shows: its card's layout slides its title bar under the bar");
        DMAutoHideSMSlideBars(NO, 0, NO);
        Check(Near(gBar.frame.origin.y, -24) && Near(DMAutoHideSMSlideDrawn(gBar), 0), @"slide: ... and when the bar hides, that title bar goes back up to the top edge (no band of wallpaper above the window)");
        gCard.frame = CGRectMake(100, 34, 500, 376);   // (the whole window at 10)
        DMAutoHideSMSlideBars(YES, 24.0, NO);
        Check(Near(DMAutoHideSMSlideDrawn(gBar), 14) && Near(DMAutoHideSMSlideDrawn(gBar), MSBDBarAHTitleSlide(10, 24, 23, 1)), @"slide: a window at 10: 14 down, what the bar covers of it (the other engines' rule)");
        gCard.frame = CGRectMake(100, 300, 500, 376); [gCard setNeedsLayout];
        Check(Near(DMSMBarFrameNow(gCard, gBar).origin.y, -24), @"slide: the window moved down (a resize, a request): its bar's frame back at its place at the next layout");
        gCard.frame = CGRectMake(100, 24, 500, 376);
        gBar.userInteractionEnabled = NO;
        Check(Near(DMSMBarFrameNow(gCard, gBar).origin.y, -24), @"slide: a card scaled in the App Switcher (its bar takes no touch there): not slid");
        gBar.userInteractionEnabled = YES;
        KPan *held = [KPan new]; held.kState = UIGestureRecognizerStateChanged; [gBar addGestureRecognizer:held];
        Check(Near(DMSMBarFrameNow(gCard, gBar).origin.y, -24), @"slide: not while its own drag goes on");
        [gBar removeGestureRecognizer:held];
        DMAutoHideSMSlideBars(YES, 24.0, NO);
        Check(Near(gBar.frame.origin.y, 0), @"slide: slid again for the drag below");
        // (a drag that starts on the slid title bar: the window moves down to it, under the finger, then follows it -- the other engines' DMAutoHideBake)
        Drag(Steps(CGPointMake(0, 100)), CGPointMake(0, 100));
        Check(Near(gTLastMove.ty, 124) && Near(gBar.frame.origin.y, -24), [NSString stringWithFormat:@"drag on a slid title bar: the window 24 pt down to it, then the finger's 100 (travel %.1f), its bar back at its place", gTLastMove.ty]);
        Check(gTAsked && Near(gTAsked.center.y * pad.height, 24 + 376 / 2.0 + 124), [NSString stringWithFormat:@"  ... its drop asks for that place (the card's middle at %.1f)", gTAsked ? gTAsked.center.y * pad.height : -1]);
        Check([gTLog indexOfObjectPassingTest:^BOOL(NSString *l, NSUInteger i, BOOL *stop) { return [l containsString:@"moved down to its title bar"]; }] != NSNotFound, @"  ... and says so in the log");
        // (1.8.8.3's follow, as UIKit reports a drag: the finger goes down on the slid title bar, UIKit begins the pan 12 pt further down, the finger then
        //  goes 100 pt down in all: the window moves down to its title bar (24) AND follows the finger from where it went down -- no jump up under the menu
        //  bar at the start, the whole way at the let go)
        Setup(pad, kA, CGRectMake(100, 24, 500, 376), NO);   // (the whole window at the screen's top edge again)
        SBCard(); [gCard addSubview:gBar]; gBar.frame = DMSMBarFrame(gCard); gSMBars = [NSHashTable weakObjectsHashTable]; [gSMBars addObject:gBar];
        DMAutoHideSMSlideBars(YES, 24.0, NO);
        Check(Near(gBar.frame.origin.y, 0), @"slid again for the drag as UIKit reports it");
        CGRect before = gCard.frame;
        KTouch *ft = DownOn(CGPointMake(300, 12), UITouchTypeDirect);   // (on the slid bar: the screen's 0..24)
        DragTouch(ft, Pts(4, 300.0, 24.0, 300.0, 40.0, 300.0, 80.0, 300.0, 112.0), UIGestureRecognizerStateEnded, 1);
        Check(Near(StepAt(0).ty, 24) && Near(gTLastMove.ty, 24 + 68) && Near(gCard.frame.origin.y - before.origin.y, 24 + 100),
              [NSString stringWithFormat:@"drag on a slid title bar, followed from the touch-down: down to it at once (%.1f), then with the finger (%.1f at 80), the whole way at the let go (%.1f)", StepAt(0).ty, gTLastMove.ty, gCard.frame.origin.y - before.origin.y]);
        Setup(pad, kA, CGRectMake(100, 24, 500, 376), YES);   // (a window on the TV)
        SBCard(); [gCard addSubview:gBar]; gBar.frame = DMSMBarFrame(gCard); gSMBars = [NSHashTable weakObjectsHashTable]; [gSMBars addObject:gBar];
        DMAutoHideSMSlideBars(YES, 24.0, NO);
        Check(Near(gBar.frame.origin.y, -24), @"slide: a window on the TV is not slid (the TV keeps its bar's room: nothing is up there)");
        // ==== 4. a new window at Window Size's Default, Small and Large and at an app's iPhone size: the same window on both engines, the bar hiding itself or not ====
        for (int ah = 0; ah < 2; ah++) {
            gTAH = ah;
            int choice[4] = {MSBDWindowSizeDefault, MSBDWindowSizeSmall, MSBDWindowSizeLarge, kMSBDOpenIPhone};
            const char *nm[4] = {"Default", "Small", "Large", "iPhone"};
            for (int i = 0; i < 4; i++) {
                CGRect o = DMNewWindowFrameWindowAt(choice[i]), m = DMSMNewWindowFrameAt(choice[i], DMSMUsableAreaForIdentity(nil, NULL), gIPad.size);
                Check(RectNear(o, m) && o.origin.y >= 24.0, [NSString stringWithFormat:@"new window, the bar %s: %s the same on both, under the bar (theirs %@, ours %@)", ah ? "hiding itself" : "shown", nm[i], R(o), R(m)]);
            }
        }
        gTAH = NO;
        // ==== 5. the tick after the setting goes off (the real DMAutoHideStopTimerLater, on the main run loop): it runs on while our windows still wait to
        //      go back under the bar; turned on again meanwhile, the new tick takes the waiting switch on and the old one stops at once (review of 1.8.8.4:
        //      it ran on beside the new one, every tick twice, for up to 10 s, then dropped the new tick's waiting switch) ====
        {
            NSRunLoop *rl = [NSRunLoop mainRunLoop];
            NSTimer *old = [NSTimer timerWithTimeInterval:100 repeats:YES block:^(NSTimer *x) { (void)x; }];
            gAutoHideTimer = nil; gSMRetopPending = 0;   // (the setting off; our windows still to go under the bar)
            DMAutoHideStopTimerLater(old, 0);
            [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.9]];
            Check(old.valid && gSMRetopPending == 0, @"tick, the setting off while our windows still wait to go under the bar: it runs on (1.5 s and more)");
            gSMRetopPending = -1;   // (they went under it)
            [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
            Check(!old.valid && [gTLog.lastObject isEqualToString:@"[autohide] setting off: its tick stopped"], @"  ... and stops once they are under the bar");
            NSTimer *old2 = [NSTimer timerWithTimeInterval:100 repeats:YES block:^(NSTimer *x) { (void)x; }], *fresh = [NSTimer timerWithTimeInterval:100 repeats:YES block:^(NSTimer *x) { (void)x; }];
            gAutoHideTimer = nil; gSMRetopPending = 0;
            DMAutoHideStopTimerLater(old2, 0);
            gAutoHideTimer = fresh; gSMRetopPending = 1;   // (on again meanwhile: DMAutoHideRefreshTimer's new tick, its own switch -- the room given -- waiting)
            [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.9]];
            Check(!old2.valid && fresh.valid && gSMRetopPending == 1, [NSString stringWithFormat:@"tick, the setting on again while our windows waited: the old tick stops at 1.5 s as before (not beside the new one), the new tick and its waiting switch kept (old %d, new %d, waiting %d)", old2.valid, fresh.valid, gSMRetopPending]);
            [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.8]];
            Check(fresh.valid && gSMRetopPending == 1, @"  ... and nothing of it comes later");
            [fresh invalidate]; gAutoHideTimer = nil; gSMRetopPending = -1;
        }
        printf("%d checks, %d failed\n", gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
