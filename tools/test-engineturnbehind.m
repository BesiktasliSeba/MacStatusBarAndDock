// test-engineturnbehind.m -- Aerial (3.0 and 5.x), Zetsu and MilkyWay4: a window the user left partly behind the Dock stays behind it when the iPad
// turns and turns back, as the Stage Manager engine keeps one (1.8.7.5, engine parity with SMBEHIND: test-smturnbehind). These engines kept no record of
// such a window, and their turn fitted every window into the desktop above the Dock (DMRelayoutForOrientation: DMFitInto(f, DMLayoutFrame(@"fill"))),
// so a Clock window at 601..1024 came back at 515..938 after a turn and back. Now the end of a move by hand records it (gBehindDock, DMSnapMoveEnded),
// the turn, a window landing after it, the green light's places and a window from a desktop left in the other shape keep a marked window inside the
// screen down to its bottom edge, every placement of ours takes the mark (DMTitleRecordEngineTo), and the title bar's Back gives back the mark Fill and
// Zoom took (the record keeps it). App Window Sizes (1.8.8, review R1 of its port onto 1.8.7.7): its forget takes an app's place while its window
// is open and leaves the mark with that window; the green light's way back with no place kept puts the window where a new window opens, a place of
// ours, and takes the mark (WindowKeys.h DMTitleRecordEngineTo; a window that opens anew: test-appwindowsize.sh c_behind).
// The real code is cut out by test-engineturnbehind.sh (engineturnbehind-*.inc): from StatusBar.x the record (gBehindDock and its functions),
// DMSnapMoveEnded, DMSnapWindowOf(Frame), DMSnapScreenOf, DMDockSideKeepsOut, the turn (DMRelayoutForOrientation, DMRelayoutStageWhenLanded,
// DMNoteWindowLayouts), DMFitInto, DMScaleFrame, DMRememberStageFrame, DMSetStageIntent, DMKeepStagePlace, DMOrientKey, DMLayoutFrame(Window),
// DMEngineWindowMin and Aerial 5.x's stage geometry; from WindowKeys.h the title bar's records; from TitleBarTap.h DMTitleTapEngineWindow; from
// MacSwitcher.h DMMSWFitTurned. With the real TurnPlace.h, TitleBarRule.h, WindowKeysRule.h, WindowMinSize.h, FitPlan.h and common/DockSide.h. The
// windows are stand-ins with a frame (an Aerial 5.x stage is the window grown by the M1's margins, 13 / 6 / 12 / 6), a Zetsu window is a UIWindow; a
// move of ours puts the frame and remembers it, as DMAerialMoveStage does at its end. The geometry is the M1's (iPad Pro 12.9", 1366 x 1024): the
// desktop under the 24 pt bar down to 938 in landscape (the Dock's top at 940) and to 1292 in portrait.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include "TurnPlace.h"
#include "TitleBarRule.h"
#include "WindowKeysRule.h"
#include "WindowMinSize.h"
#include "WindowSnap.h"
#include "FitPlan.h"
#include "../common/DockSide.h"
#include "../common/AppWindowSize.h"   // (MSBDOpensFree: DMWindowLayout's 1.8.8 G2 line)

static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit, as far as the cut code uses it, on Foundation ----
@interface NSValue (ETBGeometry)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
+ (NSValue *)valueWithCGSize:(CGSize)s; - (CGSize)CGSizeValue;
@end
@implementation NSValue (ETBGeometry)
+ (NSValue *)valueWithCGRect:(CGRect)r { return [NSValue valueWithBytes:&r objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect r; [self getValue:&r]; return r; }
+ (NSValue *)valueWithCGSize:(CGSize)s { return [NSValue valueWithBytes:&s objCType:@encode(CGSize)]; }
- (CGSize)CGSizeValue { CGSize s; [self getValue:&s]; return s; }
@end
static NSString *NSStringFromCGRect(CGRect r) { return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
static NSString *NSStringFromCGSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
static CGSize CGSizeFromString(NSString *s) { double w = 0, h = 0; if (s) sscanf(s.UTF8String, "{%lf, %lf}", &w, &h); return CGSizeMake(w, h); }
typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic) CGRect bounds;
@property (nonatomic, readonly) id coordinateSpace;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
- (id)coordinateSpace { return self; }
@end
@class UIWindow;
@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, strong) UIView *superview;
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, copy) NSString *bundle;      // (the stand-in's app: DMStageBundle)
@property (nonatomic) BOOL minimized;             // (DMStageMinimized)
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space;
@end
@implementation UIView
- (CGRect)convertRect:(CGRect)r toCoordinateSpace:(id)space { (void)space; return r; }   // (the engines' layers are the screen's size, at its origin)
- (void)layoutIfNeeded { }
- (void)bringSubviewToFront:(UIView *)v { (void)v; }
@end
@interface UIWindow : UIView
@property (nonatomic, strong) UIScreen *screen;
@end
@implementation UIWindow
@end

// ---- time and the main queue (queued with their time, run in time order by the scenario) ----
static CFTimeInterval gNow = 1000.0;
static CFTimeInterval CACurrentMediaTime(void) { return gNow; }
static NSMutableArray<NSArray *> *gQueue;
static void TQueue(double delay, dispatch_block_t b) { [gQueue addObject:@[@(gNow + delay), [b copy]]]; }
#define dispatch_time(base, delta) ((double)(delta) / (double)NSEC_PER_SEC)
#define dispatch_after(when, queue, ...) TQueue((when), __VA_ARGS__)
static void RunQueue(void) {
    while (gQueue.count) {
        NSUInteger first = 0;
        for (NSUInteger i = 1; i < gQueue.count; i++) if ([gQueue[i][0] doubleValue] < [gQueue[first][0] doubleValue]) first = i;
        NSArray *e = gQueue[first]; [gQueue removeObjectAtIndex:first];
        if ([e[0] doubleValue] > gNow) gNow = [e[0] doubleValue];
        ((dispatch_block_t)e[1])();
    }
}

// ---- StatusBar.x's declarations the cut code reads (as there) ----
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;
static DMEngine gEngine = DMEngineAerial;
static DMEngine DMActiveEngine(void) { return gEngine; }
static int gAerialFlavor = 3;
static BOOL gA5ThemeOff = NO;
static UIEdgeInsets gA5Insets = {13.0, 6.0, 12.0, 6.0};   // (the M1's Aerial 5.1 margins)
static const void *kStageIntentKey = &kStageIntentKey, *kStageIntentSizeKey = &kStageIntentSizeKey, *kStageEnteringKey = &kStageEnteringKey;
static const void *kStageClosingKey = &kStageClosingKey, *kStageGestureKey = &kStageGestureKey, *kA5BornKey = &kA5BornKey, *kA5EntranceTargetKey = &kA5EntranceTargetKey;
static const void *kStageByOrientKey = &kStageByOrientKey, *kStageLayoutNameKey = &kStageLayoutNameKey;
static char kStageTurnPlacedKey;
static BOOL gStageFrameBypass = NO, gMoveKeepsOrder = NO, gMSWSwitching = NO, gPreferRememberedFrame = NO;
static int gDMTouchWatchArm = 0; static NSString *gDMTouchWatchWhy;
static NSMutableArray<NSString *> *gFitGroup; static NSMutableDictionary<NSString *, NSString *> *gFitSlots; static NSMutableSet<NSString *> *gFreeWindows;
static NSMutableDictionary<NSString *, NSValue *> *gLastWindowFrames;
static NSMutableDictionary<NSString *, NSString *> *gMSWLeftSize;
static int gTitleDoubleTap = kMSBDTitleFill;
static NSMutableArray<NSString *> *gLog;
#define DM_FEATURE_MARK(x) do { } while (0)
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }

// ---- the world around: the windows on this desktop, the desktop, the Dock ----
static NSMutableArray<UIView *> *gStages;
static NSArray<UIView *> *DMAerialStages(void) { return [gStages copy]; }
static NSString *DMStageBundle(UIView *stage) { return stage.bundle; }
static UIView *DMStageForBundle(NSString *b) { for (UIView *s in gStages) if ([s.bundle isEqualToString:b]) return s; return nil; }
static UIWindow *DMZetsuWindowFor(NSString *b) { UIView *s = DMStageForBundle(b); return [s isKindOfClass:[UIWindow class]] ? (UIWindow *)s : nil; }
static UIView *DMFindMilkyWayWindow(NSString *b) { return DMStageForBundle(b); }
static BOOL DMStageMinimized(UIView *stage) { return stage.minimized; }
static BOOL DMWindowMinimized(UIView *w) { return w.minimized; }
static void DMMinimizeWindow(UIView *w) { w.minimized = YES; }
static void DMMinimizeStage(UIView *s) { s.minimized = YES; }
static int gDockSide = 0;   // (Settings > Dock > Position: 0 the bottom, MSBDDockLeft in landscape)
static BOOL gAutoHide = NO;
static int DMDockSideNow(CGSize screen) { return screen.width > screen.height ? gDockSide : 0; }
static CGRect DMUsableArea(void) {   // (the desktop: under the 24 pt bar, 2 pt above the Dock's top)
    CGSize scr = [UIScreen mainScreen].bounds.size;
    if (gAutoHide) return CGRectMake(0, 24, scr.width, scr.height - 24);
    if (DMDockSideNow(scr)) return CGRectMake(96, 24, scr.width - 96, scr.height - 24);
    return scr.width > scr.height ? CGRectMake(0, 24, 1366, 914) : CGRectMake(0, 24, 1024, 1268);
}
// the Window menu's places, whole windows inside u (the real ones keep a 6 pt gap between tiles; the same frames are used to note and to place here)
static CGRect DMWindowSlotInArea(NSString *name, CGRect u, CGSize screen) {
    (void)screen;
    CGFloat x = u.origin.x, y = u.origin.y, w = u.size.width, h = u.size.height;
    if ([name isEqualToString:@"fill"]) return u;
    if ([name isEqualToString:@"left"]) return CGRectMake(x, y, floor(w / 2), h);
    if ([name isEqualToString:@"right"]) return CGRectMake(x + floor(w / 2), y, w - floor(w / 2), h);
    if ([name isEqualToString:@"top"]) return CGRectMake(x, y, w, floor(h / 2));
    if ([name isEqualToString:@"bottom"]) return CGRectMake(x, y + floor(h / 2), w, h - floor(h / 2));
    if ([name isEqualToString:@"topleft"]) return CGRectMake(x, y, floor(w / 2), floor(h / 2));
    if ([name isEqualToString:@"topright"]) return CGRectMake(x + floor(w / 2), y, w - floor(w / 2), floor(h / 2));
    if ([name isEqualToString:@"bottomleft"]) return CGRectMake(x, y + floor(h / 2), floor(w / 2), h - floor(h / 2));
    if ([name isEqualToString:@"bottomright"]) return CGRectMake(x + floor(w / 2), y + floor(h / 2), w - floor(w / 2), h - floor(h / 2));
    if ([name isEqualToString:@"center"]) return CGRectMake(x + floor((w - 615) / 2), y + 12, 615, 423);
    return CGRectNull;
}
static CGFloat DMAutoHideShiftOf(UIView *stage) { (void)stage; return 0.0; }
static void DMAerial5SyncState(UIView *stage, CGRect frame) { (void)stage; (void)frame; }
static void DMA5HoldStageAt(UIView *stage, CGRect target, CFTimeInterval until) { (void)stage; (void)target; (void)until; }
static void DMLayoutNoteHold(CFTimeInterval seconds) { (void)seconds; }
static BOOL DMLayoutNotesHeld(void) { return NO; }
static BOOL DMSwitcherVisible(void) { return NO; }
static void DMAssignTilesKeepingPlaces(NSString *fresh) { (void)fresh; }
static NSString *DMTilesText(NSArray<NSString *> *order, NSDictionary<NSString *, NSString *> *slots) { (void)order; (void)slots; return @""; }
static CGRect DMSlotFrame(NSString *b) { (void)b; return CGRectNull; }
static BOOL DMStageTakesPartInFit(UIView *s) { return s && !s.hidden && !s.minimized; }
static void DMSaveWindowState(void) { }
static void DMKeepCoveredByHand(UIView *v) { (void)v; }
static BOOL gSnapOff = YES;
static BOOL DMSnapOff(void) { return gSnapOff; }
static int DMSnapOthers(UIView *except, CGRect *out, int max) { (void)except; (void)out; (void)max; return 0; }   // (no window near to snap to)
static CGRect DMA5StageFromWindow(CGRect r);
static void DMSnapMoveEngineTo(UIView *st, CGRect s) { st.frame = DMA5StageFromWindow(s); }   // (the engine moves it to its snapped place)
static void DMWinPrevNoteView(UIView *v, BOOL tiledNow, CGRect now) { (void)v; (void)tiledNow; (void)now; }
static BOOL DMWinTiledEngine(CGRect f) { (void)f; return NO; }
static void DMFitGroupForget(NSString *b) { if (b.length) { [gFitGroup removeObject:b]; [gFitSlots removeObjectForKey:b]; } }
static int gMoves = 0;
static void DMRememberStageFrame(UIView *stage);
static void DMAerialMoveStage(UIView *stage, CGRect target, void (^done)(void)) {   // (animated on the iPad; its end remembers the place, then done)
    gMoves++;
    stage.frame = target;
    DMRememberStageFrame(stage);
    if (done) done();
}

// ---- what the Window menu's layouts call on the engines' side (DMWindowLayout from its engines' part: TWindowLayoutEngines) ----
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static SBApplication *gTFront;   // (the app in full screen in front, or nil)
static SBApplication *DMFrontApp(void) { return gTFront; }
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *a; if (!a) a = [UIApplication new]; return a; }
@end
typedef NSUInteger UIViewAnimationOptions;
enum { UIViewAnimationOptionBeginFromCurrentState = 1 << 2, UIViewAnimationOptionAllowUserInteraction = 1 << 1 };
static void MSBAnimate(NSTimeInterval duration, NSTimeInterval delay, CGFloat damping, UIViewAnimationOptions options, void (^animations)(void), void (^completion)(BOOL)) {
    (void)duration; (void)delay; (void)damping; (void)options; if (animations) animations(); if (completion) completion(YES);
}
static BOOL gWindowsPinnedForward = NO;
static CGRect gPendingWindowFrame;
static NSString *gA5EntranceBundle, *gAerialGreenNewBundle;
static CGRect gA5EntranceFrame;
static CFTimeInterval gA5EntranceAt, gAerialGreenNewAt;
static NSMutableArray<NSString *> *gTOpened;   // (apps asked to open a window from full screen)
static void DMFitForgetFullScreenTile(NSString *b, NSString *why) { (void)b; (void)why; }
// (1.8.8 G2: the green light's way back as a free window closes its old Fit tile up, DMWindowLayout's line before the engines' part -- the Fit
//  record is test-fitgreen's, not played here: Fit off)
static BOOL DMFitEnabled(void) { return NO; }
static BOOL gNewWindowsFill = NO;
static int DMAppSizeOf(NSString *b) { (void)b; return MSBDAppSizeNone; }
static void DMFitFullScreenBackFree(NSString *b) { (void)b; }
static CGRect gTOpening = {{376, 200}, {615, 423}};   // (where a new window opens, the engine's frame: Fresh sets it back)
static CGRect DMOpeningWindowFrameFor(NSString *b) { (void)b; return gTOpening; }   // (App Window Sizes, 1.8.8: the app's own size, else Window Size)
static void DMApplyWindowLevel(void) { }
static void DMZetsuMove(UIWindow *w, CGRect target, BOOL animated, void (^done)(void)) { (void)animated; gMoves++; w.frame = target; DMRememberStageFrame(w); if (done) done(); }
static void DMZetsuAskFrame(NSString *b, CGRect f) { (void)b; (void)f; }
static void DMMilkyWayAskFrame(NSString *b, CGRect f) { (void)b; (void)f; }
static void DMSendToWindow(NSString *b) { [gTOpened addObject:b]; }
static void DMFitRejoinAfterFullScreen(NSString *b) { (void)b; }
static void DMStageCoverPrepare(BOOL forEntrance) { (void)forEntrance; }
static void DMAerialTrigger(NSString *b, CGRect f) { (void)f; [gTOpened addObject:b]; }
static NSString *DMCurrentLayoutName(void) { return @""; }
static void DMOwnHome(void (^home)(void)) { if (home) home(); }
static BOOL DMMSWQuietTransition(NSString *open, NSString *why) { (void)open; (void)why; return NO; }
static BOOL DMWorkspaceIdle(void) { return YES; }
static void DMShowMilkyWayVeil(UIView *w) { (void)w; }

// ---- the real code ----
static CGRect DMA5StageFromWindow(CGRect r);
static CGRect DMA5WindowFromStage(CGRect f);
static BOOL DMA5MacGeometry(void) { return gAerialFlavor == 5 && DMActiveEngine() == DMEngineAerial && !gA5ThemeOff; }
static CGRect DMLayoutFrame(NSString *name);
static CGRect DMLayoutFrameWindow(NSString *name);
static void DMSetStageIntent(UIView *stage, CGRect frame);
static void DMKeepStagePlace(UIView *stage, CGRect frame);
static CGRect DMFitInto(CGRect f, CGRect usable);
static void DMRelayoutStageWhenLanded(UIView *stage, CGSize oldSize, CGSize newSize, int attempt);
static void DMTitleRecordMovedView(UIView *v);
static void DMTitleRecordEngineTo(UIView *v, CGRect to);
static void DMBehindDockMoveEnded(UIView *st);
#include "engineturnbehind-sb.inc"
#include "engineturnbehind-wk.inc"
#include "engineturnbehind-tb.inc"
#include "engineturnbehind-msw.inc"
#include "engineturnbehind-reset.inc"   // (TForgetMarks: the record's own set emptied, where the code has one)
#include "engineturnbehind-layout.inc"  // (StatusBar.x DMWindowLayout, its engines' part: TWindowLayoutEngines)

// ---- the scenarios ----
static const CGSize kLand = {1366, 1024}, kPort = {1024, 1366};
static const CGFloat kLandLine = 938.0, kPortLine = 1292.0;   // (the desktop's bottom: 2 pt above the Dock's top)
static NSString *const kClock = @"com.apple.mobiletimer", *const kTips = @"com.apple.tips", *const kNotes = @"com.apple.mobilenotes";
static UIView *gLayer;
static NSString *gEngineName = @"";
static UIView *Stage(NSString *b) { return DMStageForBundle(b); }
static UIView *Window(NSString *b, CGRect drawn) {   // (a window of the engine in use, at that place as drawn on the screen)
    UIView *v = gEngine == DMEngineZetsu ? [UIWindow new] : [UIView new];
    if (gEngine != DMEngineZetsu) v.superview = gLayer;
    UIWindow *w = [UIWindow new]; w.screen = [UIScreen mainScreen]; v.window = gEngine == DMEngineZetsu ? (UIWindow *)v : w;
    v.bundle = b; v.alpha = 1.0;
    v.frame = DMA5StageFromWindow(drawn);
    [gStages addObject:v];
    DMRememberStageFrame(v);
    return v;
}
static CGRect Drawn(NSString *b) { UIView *s = Stage(b); return s ? DMA5WindowFromStage(s.frame) : CGRectNull; }
// a move by hand let go there: the engine has the window there, its drag ends (DMSnapMoveEnded), the place is remembered (as each engine's drag end does)
static void Drop(NSString *b, CGRect drawn) {
    UIView *s = Stage(b);
    s.frame = DMA5StageFromWindow(drawn);
    DMSnapMoveEnded(s);
    DMRememberStageFrame(s);
}
// a placement of ours (the Window menu's layouts, the window keys' Centre): the title bar's record and the mark follow it, then the move (DMWindowLayout)
static void PlaceOurs(NSString *b, CGRect drawn) { UIView *s = Stage(b); CGRect t = DMA5StageFromWindow(drawn); DMTitleRecordEngineTo(s, t); DMAerialMoveStage(s, t, nil); }
static void Still(void) { gNow += 3.0; DMNoteWindowLayouts(); }
static void Turn(CGSize to) {
    CGSize was = [UIScreen mainScreen].bounds.size;
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, to.width, to.height);
    gNow += 0.4;
    DMRelayoutForOrientation(was, to);
    RunQueue();
    Still();
}
static void Fresh(CGSize shape) {
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, shape.width, shape.height);
    gStages = [NSMutableArray array]; gLayer = [UIView new];
    gFitGroup = [NSMutableArray array]; gFitSlots = [NSMutableDictionary dictionary]; gFreeWindows = [NSMutableSet set];
    gLastWindowFrames = [NSMutableDictionary dictionary]; gMSWLeftSize = [NSMutableDictionary dictionary];
    gQueue = [NSMutableArray array]; gLog = [NSMutableArray array];
    gDockSide = 0; gAutoHide = NO; gSnapOff = YES; gPreferRememberedFrame = NO; gTitleDoubleTap = kMSBDTitleFill; gTFront = nil; gTOpened = [NSMutableArray array];
    TForgetMarks();   // (the apps of the last scenario exited: their marks went with them, as at an app's exit)
    gMoves = 0; gTOpening = CGRectMake(376, 200, 615, 423);
}
static BOOL Near(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 1.0 && fabs(a.origin.y - b.origin.y) < 1.0 && fabs(a.size.width - b.size.width) < 1.0 && fabs(a.size.height - b.size.height) < 1.0; }
static NSString *R(CGRect r) { return NSStringFromCGRect(r); }
static NSString *LogWith(NSString *part) { for (NSString *l in gLog.reverseObjectEnumerator) if ([l rangeOfString:part].location != NSNotFound) return l; return nil; }
static BOOL Has(NSString *line, NSString *part) { return line && [line rangeOfString:part].location != NSNotFound; }
static NSString *E(NSString *s) { return [NSString stringWithFormat:@"%@: %@", gEngineName, s]; }

static void Scenarios(void) {
    const CGRect clockL = CGRectMake(376, 601, 615, 423);     // (let go with its bottom on the screen's bottom edge, 86 pt under the Dock's line)
    const CGRect clockP = CGRectMake(204, 943, 615, 423);     // (the same in portrait: its bottom on the screen's bottom edge, under the portrait Dock)

    printf("-- %s 1. Clock let go behind the Dock in landscape, the iPad turned to portrait and back (twice)\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is behind the Dock as the user left it"), E([NSString stringWithFormat:@"the drop is recorded: %@", LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    Turn(kPort);
    CGRect p = Drawn(kClock);
    Expect(CGRectGetMaxY(p) <= 1366.5 && CGRectGetMinY(p) >= 24.0 - 0.5, E([NSString stringWithFormat:@"portrait: inside the screen (%@)", R(p)]));
    Expect(CGRectGetMaxY(p) > kPortLine + 4.0, E([NSString stringWithFormat:@"  ... still behind the portrait Dock, down to the screen's bottom (bottom %.1f; before: lifted above %.0f)", CGRectGetMaxY(p), kPortLine]));
    Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"landscape again: back behind the Dock where the user left it, %@ (want %@; before: 515..938)", R(Drawn(kClock)), R(clockL)]));
    Expect(Has(LogWith(@"behind the Dock as the user left them"), @"com.apple.mobiletimer {{"), E([NSString stringWithFormat:@"  ... logged: %@", LogWith(@"[orient] behind the Dock") ?: @"(no line)"]));
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"a second round trip: the same (%@)", R(Drawn(kClock))]));

    printf("-- %s 2. nudged up with its bottom still under the Dock; another window let go 2 pt under the Dock's line\n", gEngineName.UTF8String);
    CGRect nudged = CGRectMake(376, 572, 615, 423);   // (bottom 995)
    Drop(kClock, nudged);
    Window(kTips, CGRectMake(30, 150, 500, 400));
    Still();
    Drop(kTips, CGRectMake(30, 540, 500, 400));   // (bottom 940: 2 pt under the line, inside the drop's 4 pt)
    Still();
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), nudged), E([NSString stringWithFormat:@"Clock back at its place under the Dock (%@)", R(Drawn(kClock))]));
    CGRect t = Drawn(kTips);
    Expect(CGRectGetMaxY(t) <= kLandLine + 0.5 && fabs(t.size.height - 400) < 1.0, E([NSString stringWithFormat:@"Tips, not behind the Dock, kept above it as before (%@)", R(t)]));

    printf("-- %s 3. let go above the Dock again: the mark goes (as before: lifted at the turn)\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    Turn(kPort);
    Drop(kClock, CGRectMake(204, 300, 615, 423));   // (above the portrait Dock)
    Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock"), E([NSString stringWithFormat:@"the drop above the Dock takes the mark: %@", LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    Turn(kLand);
    CGRect c = Drawn(kClock);
    Expect(CGRectGetMaxY(c) <= kLandLine + 0.5 && fabs(c.origin.x - 376) < 1.0, E([NSString stringWithFormat:@"landscape: where it was in landscape, kept above the Dock as before (%@)", R(c)]));

    printf("-- %s 4. the Dock at a side (Settings > Dock > Position): a window let go low is no window behind the Dock\n", gEngineName.UTF8String);
    Fresh(kLand);
    gDockSide = MSBDDockLeft;
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, CGRectMake(376, 650, 615, 423));   // (its bottom 49 pt past the screen's: no Dock at the bottom to lie behind)
    Stage(kClock).frame = DMA5StageFromWindow(CGRectMake(376, 650, 615, 423)); DMBehindDockMoveEnded(Stage(kClock));   // (a move cut short there, too)
    Expect(!LogWith(@"[behind]"), E([NSString stringWithFormat:@"the Dock at a side: let go or left past the screen's bottom, not marked (%@)", LogWith(@"[behind]") ?: @"no [behind] line"]));
    Still();
    Turn(kPort);
    CGRect sp = Drawn(kClock);
    Expect(CGRectGetMaxY(sp) <= kPortLine + 0.5, E([NSString stringWithFormat:@"portrait (the Dock at the bottom there): above the Dock, as before (%@)", R(sp)]));

    printf("-- %s 5. a place of ours takes the mark (Centre; the Window menu's layouts), the turn putting one into its layout too\n", gEngineName.UTF8String);
    Fresh(kPort);
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, clockP);
    Still();
    Turn(kLand);
    PlaceOurs(kClock, DMWindowSlotInArea(@"center", DMUsableArea(), kLand));
    Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock (placed by a layout or a place of ours)"), E([NSString stringWithFormat:@"Centre takes the mark: %@", LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    Turn(kPort);
    CGRect cp = Drawn(kClock);
    Expect(CGRectGetMaxY(cp) <= kPortLine + 0.5, E([NSString stringWithFormat:@"  ... portrait: its portrait place kept above the Dock, as for any window (%@)", R(cp)]));
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    CGRect lowHalf = DMWindowSlotInArea(@"bottom", DMUsableArea(), kLand); lowHalf.origin.y += 5;   // (let go 5 pt under the bottom half: in its layout by the note's 6 pt)
    Drop(kClock, lowHalf);
    Still();
    Turn(kPort);
    Expect(Near(Drawn(kClock), DMWindowSlotInArea(@"bottom", DMUsableArea(), kPort)), E([NSString stringWithFormat:@"a window let go just under the bottom half: in that layout after the turn (%@)", R(Drawn(kClock))]));
    Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock (a turn put it back into its layout)"), E([NSString stringWithFormat:@"  ... and no longer marked: %@", LogWith(@"[behind]") ?: @"(no line)"]));

    printf("-- %s 6. the title bar's Fill and Back, then Zoom and Back: back behind the Dock exactly, and kept there at the next turn\n", gEngineName.UTF8String);
    for (int z = 0; z < 2; z++) {
        Fresh(kLand);
        gTitleDoubleTap = z ? kMSBDTitleZoom : kMSBDTitleFill;
        Window(kClock, CGRectMake(376, 200, 615, 423));
        Still();
        Drop(kClock, clockL);
        Still();
        DMTitleTapEngineWindow(kClock, @"test double tap");
        CGRect at = Drawn(kClock);
        Expect(CGRectGetMaxY(at) <= kLandLine + 0.5, E([NSString stringWithFormat:@"%@: above the Dock (%@)", z ? @"Zoom" : @"Fill", R(at)]));
        Still();
        DMTitleTapEngineWindow(kClock, @"test double tap");
        Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"  ... Back: where the user left it behind the Dock (%@)", R(Drawn(kClock))]));
        Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is behind the Dock as the user left it: a turn keeps it there (back from Fill or Zoom"), E([NSString stringWithFormat:@"  ... its mark given back: %@", LogWith(@"[behind]") ?: @"(no line)"]));
        Still();
        Turn(kPort); Turn(kLand);
        Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"  ... after a turn and back: still there (%@; before: 515..938)", R(Drawn(kClock))]));
    }
    Fresh(kPort);
    gTitleDoubleTap = kMSBDTitleZoom;
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, clockP);
    Still();
    Turn(kLand);
    DMTitleTapEngineWindow(kClock, @"test double tap");   // (Zoom in landscape: a place of ours)
    Still();
    Turn(kPort);
    Expect(CGRectGetMaxY(Drawn(kClock)) <= kPortLine + 0.5, E([NSString stringWithFormat:@"Zoom takes the mark: portrait, its portrait place kept above the Dock (%@)", R(Drawn(kClock))]));
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    DMTitleTapEngineWindow(kClock, @"test double tap"); Still(); DMTitleTapEngineWindow(kClock, @"test double tap");
    Expect(Near(Drawn(kClock), CGRectMake(376, 200, 615, 423)) && !LogWith(@"[behind]"), E([NSString stringWithFormat:@"a window above the Dock: Fill and Back as before, never marked (%@)", R(Drawn(kClock))]));

    printf("-- %s 7. the green light's way back to where the window was keeps the mark\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    gPreferRememberedFrame = YES; PlaceOurs(kClock, DMA5WindowFromStage(gLastWindowFrames[kClock].CGRectValue)); gPreferRememberedFrame = NO;   // (DMWindowLayout's green path)
    Still();
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"after a turn and back: behind the Dock where the user left it (%@)", R(Drawn(kClock))]));

    printf("-- %s 8. full screen while the iPad turns: the green light's place for it is kept down to the screen's bottom\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    [gStages removeObject:Stage(kClock)];   // (full screen: its window is gone, its place for the green light kept)
    Turn(kPort);
    CGRect gp = DMA5WindowFromStage(gLastWindowFrames[kClock].CGRectValue);
    Expect(CGRectGetMaxY(gp) > kPortLine + 4.0 && CGRectGetMaxY(gp) <= 1366.5, E([NSString stringWithFormat:@"portrait: its place behind the portrait Dock, inside the screen (%@)", R(gp)]));
    Turn(kLand);
    Expect(Near(DMA5WindowFromStage(gLastWindowFrames[kClock].CGRectValue), clockL), E([NSString stringWithFormat:@"landscape again: its place where the user left it (%@)", R(DMA5WindowFromStage(gLastWindowFrames[kClock].CGRectValue))]));

    printf("-- %s 9. flying in from full screen as the iPad turns back: placed once landed, behind the Dock where the user left it\n", gEngineName.UTF8String);
    Fresh(kLand);
    UIView *fly = Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    Turn(kPort);
    objc_setAssociatedObject(fly, kStageEnteringKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TQueue(0.85, ^{ objc_setAssociatedObject(fly, kStageEnteringKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); });   // (it lands)
    Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"landed: behind the Dock where it was in landscape (%@; before: 515..938)", R(Drawn(kClock))]));
    Expect(LogWith(@"landed after the turn") != nil, E(@"  ... placed by the landing (DMRelayoutStageWhenLanded)"));

    printf("-- %s 11. the Window menu's Fill, then Back by the title bar: back behind the Dock with its mark, kept there at a turn (round 1)\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    TWindowLayoutEngines(@"fill", kClock, DMLayoutFrame(@"fill"));
    Expect(Near(Drawn(kClock), DMLayoutFrameWindow(@"fill")) && Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock (placed by a layout or a place of ours)"),
           E([NSString stringWithFormat:@"Window > Fill: filled (%@), the mark taken: %@", R(Drawn(kClock)), LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    DMTitleTapEngineWindow(kClock, @"test double tap");
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"  ... Back by the title bar: where the user left it behind the Dock (%@)", R(Drawn(kClock))]));
    Expect(Has(LogWith(@"[behind] com.apple.mobiletimer"), @"back from Fill or Zoom to where the user left it"), E([NSString stringWithFormat:@"  ... its mark given back: %@", LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"  ... after a turn and back: still there (%@; before: 515..938)", R(Drawn(kClock))]));

    printf("-- %s 12. a Window menu layout for an app in full screen: its window opens there, the mark taken; one that moves nothing keeps it\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    UIView *fs = Stage(kClock);
    [gStages removeObject:fs];   // (full screen: its window gone, the app in front)
    gTFront = [SBApplication new]; gTFront.bundleIdentifier = kClock;
    TWindowLayoutEngines(@"center", kClock, DMLayoutFrame(@"center"));
    RunQueue();
    Expect([gTOpened containsObject:kClock] && Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock (placed by a layout of the Window menu)"),
           E([NSString stringWithFormat:@"its window opens at Centre, the mark taken: %@", LogWith(@"[behind]") ?: @"(no line)"]));
    if (gEngine != DMEngineAerial) {   // (Aerial moves a minimized window too: placed, the mark goes with the record)
        Fresh(kLand);
        Window(kClock, CGRectMake(376, 200, 615, 423));
        Still();
        Drop(kClock, clockL);
        Still();
        Stage(kClock).minimized = YES;   // (minimized, its app not in front: the layout moves nothing)
        [gLog removeAllObjects];
        TWindowLayoutEngines(@"center", kClock, DMLayoutFrame(@"center"));
        Expect(gMoves == 0 && !LogWith(@"[behind]"), E([NSString stringWithFormat:@"a minimized window, its app not in front: nothing moved, the mark kept (%@)", LogWith(@"[behind]") ?: @"no [behind] line"]));
        Stage(kClock).minimized = NO;
        Turn(kPort); Turn(kLand);
        Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"  ... brought back, turned and back: still behind the Dock (%@)", R(Drawn(kClock))]));
    }
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    gPreferRememberedFrame = YES; TWindowLayoutEngines(@"fill", kClock, DMLayoutFrame(@"fill")); gPreferRememberedFrame = NO;   // (the green light's way back: where it was)
    Still();
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"the green light's way back (DMWindowLayout): the mark kept, behind the Dock after a turn and back (%@)", R(Drawn(kClock))]));

    printf("-- %s 13. Snap Windows to Edges on: let go 20 pt under the Dock's line it snaps up onto it and is not behind the Dock; 60 pt under it is (round 1)\n", gEngineName.UTF8String);
    Fresh(kPort);
    gSnapOff = NO;
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, CGRectMake(204, kPortLine + 20 - 423, 615, 423));
    Expect(fabs(CGRectGetMaxY(Drawn(kClock)) - kPortLine) < 0.5 && !LogWith(@"[behind]"),
           E([NSString stringWithFormat:@"let go 20 pt under the line: snapped onto it (%@), not marked (%@)", R(Drawn(kClock)), LogWith(@"[behind]") ?: @"no [behind] line"]));
    Still();
    Turn(kLand);
    Expect(CGRectGetMaxY(Drawn(kClock)) <= kLandLine + 0.5, E([NSString stringWithFormat:@"  ... landscape: fitted above the Dock, as any window (%@; marked, it stayed partly behind it)", R(Drawn(kClock))]));
    Fresh(kPort);
    gSnapOff = NO;
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    CGRect deep = CGRectMake(204, kPortLine + 60 - 423, 615, 423);
    Drop(kClock, deep);
    Expect(Near(Drawn(kClock), deep) && Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is behind the Dock as the user left it"),
           E([NSString stringWithFormat:@"let go 60 pt under the line: not snapped (%@), marked", R(Drawn(kClock))]));
    Still();
    Turn(kLand); Turn(kPort);
    Expect(Near(Drawn(kClock), deep), E([NSString stringWithFormat:@"  ... a turn and back: still behind the Dock where the user left it (%@)", R(Drawn(kClock))]));

    printf("-- %s 10. a window brought from a desktop left in the other shape (Mac Switcher)\n", gEngineName.UTF8String);
    Fresh(kPort);
    UIView *away = Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, clockP);
    Still();
    Turn(kLand);
    gMSWLeftSize[@"7"] = NSStringFromCGSize(kLand);   // (its desktop left in landscape)
    [gStages removeObject:away];
    Turn(kPort);
    [gStages addObject:away];
    DMMSWFitTurned(away, 7);
    Expect(Near(Drawn(kClock), clockP), E([NSString stringWithFormat:@"portrait: where it was in portrait, behind the Dock (%@; before: lifted above %.0f)", R(Drawn(kClock)), kPortLine]));

    printf("-- %s 14. App Window Sizes forgot the place of a window left behind the Dock (its size changed while it was open): the window keeps its mark; the green light's way back puts it where a new window opens and takes it (review R1)\n", gEngineName.UTF8String);
    Fresh(kLand);
    Window(kClock, CGRectMake(376, 200, 615, 423));
    Still();
    Drop(kClock, clockL);
    Still();
    [gLastWindowFrames removeObjectForKey:kClock];   // (DMAppSizeForgetPlace: the place goes, an open window is not moved)
    Turn(kPort); Turn(kLand);
    Expect(Near(Drawn(kClock), clockL), E([NSString stringWithFormat:@"the forget alone: the open window keeps its mark, behind the Dock after a turn and back (%@)", R(Drawn(kClock))]));
    Fresh(kPort);
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, clockP);
    Still();
    [gLastWindowFrames removeObjectForKey:kClock];   // (the forget)
    const CGRect fresh = CGRectMake(204, kPortLine - 423, 615, 423);   // (where a new window opens at the app's new size: down to the Dock's line, above it)
    gTOpening = DMA5StageFromWindow(fresh);
    [gLog removeAllObjects];
    gPreferRememberedFrame = YES; TWindowLayoutEngines(@"center", kClock, DMLayoutFrame(@"center")); gPreferRememberedFrame = NO;   // (the green light's way back, DMLightAction)
    Expect(Near(Drawn(kClock), fresh) && !DMBehindDockHas(kClock) && Has(LogWith(@"[behind] com.apple.mobiletimer"), @"is no longer behind the Dock (the green light's way back with no place of its own kept"),
           E([NSString stringWithFormat:@"the way back with no place kept: where a new window opens (%@), the mark taken: %@", R(Drawn(kClock)), LogWith(@"[behind]") ?: @"(no line)"]));
    Still();
    Turn(kLand);
    Expect(CGRectGetMaxY(Drawn(kClock)) <= kLandLine + 0.5, E([NSString stringWithFormat:@"  ... landscape: fitted above the Dock as any window (%@; marked, it stayed partly behind it)", R(Drawn(kClock))]));
    Fresh(kPort);
    Window(kClock, CGRectMake(204, 300, 615, 423));
    Still();
    Drop(kClock, clockP);
    Still();
    gTOpening = DMA5StageFromWindow(fresh);
    gPreferRememberedFrame = YES; TWindowLayoutEngines(@"center", kClock, DMLayoutFrame(@"center")); gPreferRememberedFrame = NO;   // (no forget: its place is held)
    Expect(Near(Drawn(kClock), clockP) && DMBehindDockHas(kClock), E([NSString stringWithFormat:@"  ... with its place held (no forget): back where the user left it, the mark kept (%@)", R(Drawn(kClock))]));
}

int main(int argc, char **argv) { @autoreleasepool {
    struct { DMEngine e; int flavor; const char *name; } engines[] = { {DMEngineAerial, 3, "Aerial 3.0"}, {DMEngineAerial, 5, "Aerial 5.x"}, {DMEngineZetsu, 0, "Zetsu"}, {DMEngineMilkyWay, 0, "MilkyWay4"} };
    const char *only = argc > 1 ? argv[1] : NULL;
    for (unsigned i = 0; i < sizeof engines / sizeof engines[0]; i++) {
        if (only && strcmp(only, engines[i].name)) continue;
        gEngine = engines[i].e; gAerialFlavor = engines[i].flavor; gEngineName = @(engines[i].name);
        Scenarios();
    }
    printf("%s: %d checks, %d failed\n", fails ? "test-engineturnbehind FAILED" : "test-engineturnbehind: all pass", checks, fails);
    return fails > 98 ? 98 : fails;
} }
