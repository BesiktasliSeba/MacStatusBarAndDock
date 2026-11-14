// test-smdropdock.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a Stage Manager title-bar drop and "put behind the Dock" (1.8.7.3, audit M4 of
// 1.8.7.2). Stage Manager engine, Dock at the bottom: a window let go with its bottom more than 4 pt under the Dock's line is put behind the Dock by
// hand (gSMBehindDock: the stage area then reaches the screen's bottom and the window is fitted there); one let go above it is not. The record read
// the card's frame on the screen as it was at the drag's end, which already carries the drag (the transform of its last move), and added the drag
// again: a window let go 300 pt lower, its bottom well above the Dock, was taken for one behind it; one behind it nudged up was taken out.
// Runs the real -[DMSMTitleBar dm_pan:] with its @interface and the globals it uses (statusbar/StatusBar.x), cut out by test-smdropdock.sh into
// smd-real.inc, with the real statusbar/SMWindowKey.h and real UIKit views (the card's transform and its frame on the screen are UIKit's own).
// SpringBoard's side (the screen, bringing a window forward, the snap target, the place asked for) is the stand-ins below, which record what they
// are asked.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include "../statusbar/SMWindowKey.h"

// ---- what the real code logs and asks
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
static BOOL DMTestFlag(const char *path) { return NO; }
static NSMutableArray<NSString *> *gKFront;
static void DMSMBringToFront(NSString *key) { [gKFront addObject:key ?: @"(nil)"]; }
static int gKMoved;
static void DMTitleRecordMovedSM(NSString *key) { gKMoved++; }
static int gKDockSide;   // (Settings > Dock > Position: 0 at the bottom)
static int DMDockSideNow(CGSize screen) { return gKDockSide; }
static BOOL gKSnap; static CGPoint gKSnapAt, gKSnapT; static int gKSnapAsked;
static BOOL DMSMSnapMoveTarget(NSString *key, UIView *card, CGPoint t, CGPoint *at) { gKSnapAsked++; gKSnapT = t; if (gKSnap) *at = gKSnapAt; return gKSnap; }
static NSString *gKPlaceKey; static CGPoint gKPlace; static int gKPlaces;
static BOOL DMSMSetWindowGeometry(NSString *key, CGPoint center, CGSize size) { gKPlaces++; gKPlaceKey = key; gKPlace = center; return YES; }

// ---- the iPad's screen: its size in points, its coordinate space the (full-screen) window's
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

// ---- the drag: a pan whose state and travel the test sets
@interface KPan : UIPanGestureRecognizer
@property (nonatomic) UIGestureRecognizerState kState;
@property (nonatomic) CGPoint kT;
@end
@implementation KPan
- (UIGestureRecognizerState)state { return self.kState; }
- (CGPoint)translationInView:(UIView *)v { return self.kT; }
@end

#include "smd-real.inc"   // (the @interface DMSMTitleBar, gSMDragUntil, gSMBehindDock, gSMDockHeightBySize)
@implementation DMSMTitleBar
#include "smd-pan.inc"    // (-dm_pan:)
@end

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }

static NSString *const kNotes = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-6C1F0A2E";   // (a window's key)
static KWindow *gWin; static UIView *gSup, *gCard; static DMSMTitleBar *gBar;

// A screen of `size` (the Dock's height recorded for it, or none: -1), the stage view at `supFrame` in it, the window's card at `card` in that view.
static void Setup(CGSize size, CGFloat dockHeight, CGRect supFrame, CGRect card) {
    gKLog = [NSMutableArray array]; gKFront = [NSMutableArray array]; gKMoved = 0; gKDockSide = 0;
    gKSnap = NO; gKSnapAsked = 0; gKSnapT = CGPointZero; gKPlaceKey = nil; gKPlace = CGPointZero; gKPlaces = 0;
    gSMDragUntil = 0; gSMBehindDock = nil;
    gSMDockHeightBySize = [NSMutableDictionary dictionary];
    if (dockHeight >= 0) gSMDockHeightBySize[NSStringFromCGSize(size)] = @(dockHeight);
    gWin = [[KWindow alloc] initWithFrame:CGRectMake(0, 0, size.width, size.height)];
    KScreen *s = [KScreen new]; s.size = size; s.space = gWin; gWin.kscreen = s;
    gSup = [[UIView alloc] initWithFrame:supFrame]; [gWin addSubview:gSup];
    gCard = [[UIView alloc] initWithFrame:card]; [gSup addSubview:gCard];
    gBar = [DMSMTitleBar new]; gBar.bundle = DMSMKeyBundle(kNotes); gBar.key = kNotes; gBar.card = gCard;
}
static void Behind(NSString *key) { if (!gSMBehindDock) gSMBehindDock = [NSMutableSet set]; [gSMBehindDock addObject:key]; }
// The drag: Began, a Changed at each of `moves` (the card follows the finger), then `end` (Ended or Cancelled) at `last`.
static void Drag(NSArray<NSValue *> *moves, CGPoint last, UIGestureRecognizerState end) {
    KPan *g = [KPan new];
    g.kState = UIGestureRecognizerStateBegan; g.kT = CGPointZero; [gBar dm_pan:g];
    for (NSValue *m in moves) { g.kState = UIGestureRecognizerStateChanged; g.kT = m.CGPointValue; [gBar dm_pan:g]; }
    g.kState = end; g.kT = last; [gBar dm_pan:g];
}
static NSArray<NSValue *> *Down(CGFloat dy) { return @[[NSValue valueWithCGPoint:CGPointMake(0, dy / 3)], [NSValue valueWithCGPoint:CGPointMake(0, dy * 2 / 3)], [NSValue valueWithCGPoint:CGPointMake(0, dy)]]; }
static BOOL IsBehind(void) { return DMSMKeySetHas(gSMBehindDock, kNotes); }

int main(void) {
    @autoreleasepool {
        const CGSize ipad = CGSizeMake(1366, 1024);   // (12.9", landscape; the Dock's line at 1024 - 117 - 2 = 905: behind it below 909)
        const CGRect full = CGRectMake(0, 0, 1366, 1024);

        // -- the audit's case: dragged 300 pt down, its bottom (500 -> 800) well above the Dock
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(300), CGPointMake(0, 300), UIGestureRecognizerStateEnded);
        Check(!IsBehind(), @"a window let go 300 pt lower, its bottom (800) well above the Dock's line (905): not put behind the Dock (the audit's case)");
        Check(gKPlaces == 1 && [gKPlaceKey isEqualToString:kNotes] && Near(gKPlace.x, 600.0 / 1366) && Near(gKPlace.y, 600.0 / 1024),
              @"  ... the place asked for is the dropped card's middle (600, 600) as a share of the screen (unchanged)");
        Check(CGAffineTransformIsIdentity(gCard.transform) && Near(gCard.center.x, 600) && Near(gCard.center.y, 600) && gKMoved == 1 && gKSnapAsked == 1 && Near(gKSnapT.y, 300),
              @"  ... the card is put in place at once (no transform, its centre moved by the drag), the move recorded, the snap asked with the drag (unchanged)");
        Check(gSMDragUntil > CACurrentMediaTime() + 0.5 && gSMDragUntil < CACurrentMediaTime() + 1.5 && gKFront.count == 1, @"  ... the stage area held 1 s more, the window brought forward at the start (unchanged)");

        // -- let go under the line: behind the Dock
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(450), CGPointMake(0, 450), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"a window let go 450 pt lower, its bottom (950) under the Dock's line: put behind the Dock (unchanged)");

        // -- the line itself: more than 4 pt under it
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(409), CGPointMake(0, 409), UIGestureRecognizerStateEnded);
        Check(!IsBehind(), @"its bottom let go at 909 (4 pt under the line): not behind the Dock");
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(411), CGPointMake(0, 411), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"its bottom let go at 911: behind the Dock");

        // -- the reverse: a window behind the Dock nudged up a little stays behind it
        Setup(ipad, 117, full, CGRectMake(300, 580, 600, 400)); Behind(kNotes);
        Drag(@[[NSValue valueWithCGPoint:CGPointMake(0, -20)], [NSValue valueWithCGPoint:CGPointMake(0, -40)]], CGPointMake(0, -40), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"a window behind the Dock (bottom 980) nudged up 40 pt (bottom 940, still under the line): stays behind the Dock (the audit's reverse case)");
        Setup(ipad, 117, full, CGRectMake(300, 580, 600, 400)); Behind(kNotes);
        Drag(Down(-200), CGPointMake(0, -200), UIGestureRecognizerStateEnded);
        Check(!IsBehind(), @"a window behind the Dock dragged up 200 pt (bottom 780): out of the set (unchanged)");
        Setup(ipad, 117, full, CGRectMake(300, 580, 600, 400)); Behind(DMSMKeyBundle(kNotes));   // (an entry for the app's windows, an older version's)
        Drag(Down(-200), CGPointMake(0, -200), UIGestureRecognizerStateEnded);
        Check(!gSMBehindDock.count, @"  ... the app's entry goes too (DMSMKeySetRemove, unchanged)");

        // -- the end's travel a little past the last move (the finger moved on as it lifted)
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(280), CGPointMake(0, 300), UIGestureRecognizerStateEnded);
        Check(!IsBehind() && Near(gKPlace.y, 600.0 / 1024), @"last move at 280 pt, let go at 300 pt (bottom 800): not behind the Dock, the place from 300 pt");
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(400), CGPointMake(0, 420), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"last move at 400 pt, let go at 420 pt (bottom 920): behind the Dock");

        // -- an end with no move before it: the card carries no transform; the same answer
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(@[], CGPointMake(0, 300), UIGestureRecognizerStateEnded);
        Check(!IsBehind() && Near(gKPlace.y, 600.0 / 1024), @"an end straight after the start at 300 pt (no move drawn): not behind the Dock, the same place");
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(@[], CGPointMake(0, 450), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"  ... at 450 pt: behind the Dock");

        // -- a cancelled drag ends the same way
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        Drag(Down(300), CGPointMake(0, 300), UIGestureRecognizerStateCancelled);
        Check(!IsBehind() && gKPlaces == 1, @"a cancelled drag 300 pt down: not behind the Dock, the place asked for");

        // -- no Dock height recorded for the screen: 117 pt (11", landscape: the line at 820 - 117 - 2 = 701)
        const CGSize ipad11 = CGSizeMake(1180, 820);
        Setup(ipad11, -1, CGRectMake(0, 0, 1180, 820), CGRectMake(200, 100, 500, 300));
        Drag(Down(250), CGPointMake(0, 250), UIGestureRecognizerStateEnded);
        Check(!IsBehind(), @"11\", no Dock height recorded: let go 250 pt lower (bottom 650, above 701): not behind the Dock");
        Setup(ipad11, -1, CGRectMake(0, 0, 1180, 820), CGRectMake(200, 100, 500, 300));
        Drag(Down(320), CGPointMake(0, 320), UIGestureRecognizerStateEnded);
        Check(IsBehind(), @"  ... 320 pt lower (bottom 720): behind the Dock");

        // -- the Dock at a side: nothing lies behind it
        Setup(ipad, 117, full, CGRectMake(300, 580, 600, 400)); Behind(kNotes); gKDockSide = 1;
        Drag(Down(20), CGPointMake(0, 20), UIGestureRecognizerStateEnded);
        Check(!IsBehind(), @"the Dock at a side: a window let go at the screen's bottom is not behind the Dock, and leaves the set (unchanged)");

        // -- the screen's frame, not the stage view's: a stage view 40 pt down the screen
        Setup(ipad, 117, CGRectMake(0, 40, 1366, 984), CGRectMake(300, 100, 600, 400));   // (bottom 540 on the screen)
        Drag(Down(380), CGPointMake(0, 380), UIGestureRecognizerStateEnded);
        Check(IsBehind() && Near(gKPlace.y, 680.0 / 984), @"a stage view 40 pt down: let go 380 pt lower, bottom 920 on the screen (880 in the view): behind the Dock; the place in the view's share");

        // -- the place is the dropped card's middle, not its anchor's point (1.7.4 item 13: Stage Manager lifts a window by the finger)
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        gCard.layer.anchorPoint = CGPointMake(0.47, -0.02); gCard.frame = CGRectMake(300, 100, 600, 400);
        Drag(Down(200), CGPointMake(0, 200), UIGestureRecognizerStateEnded);
        Check(!IsBehind() && Near(gKPlace.x, 600.0 / 1366) && Near(gKPlace.y, 500.0 / 1024), @"a lifted card (anchor at the title bar): the place asked for is its dropped middle (600, 500), not the anchor (unchanged)");

        // -- a snap wins over the middle (unchanged)
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400)); gKSnap = YES; gKSnapAt = CGPointMake(0.25, 0.5);
        Drag(Down(300), CGPointMake(0, 300), UIGestureRecognizerStateEnded);
        Check(gKPlaces == 1 && Near(gKPlace.x, 0.25) && Near(gKPlace.y, 0.5), @"a drop that snaps asks for the snapped place (unchanged)");

        // -- the card gone at the end: the area let go, nothing recorded (logic review L4, unchanged)
        Setup(ipad, 117, full, CGRectMake(300, 100, 600, 400));
        { KPan *g = [KPan new]; g.kState = UIGestureRecognizerStateBegan; [gBar dm_pan:g]; g.kState = UIGestureRecognizerStateChanged; g.kT = CGPointMake(0, 450); [gBar dm_pan:g];
          [gCard removeFromSuperview]; g.kState = UIGestureRecognizerStateEnded; [gBar dm_pan:g]; }
        Check(gSMDragUntil == 0 && !IsBehind() && gKPlaces == 0, @"the card gone before the end: the stage area let go at once, nothing recorded (unchanged)");
    }
    printf("test-smdropdock: %d of %d checks pass\n", gChecks - gFails, gChecks);
    return gFails;
}
