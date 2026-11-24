// test-smturnclosed.m -- 1.8.8 H5, our Stage Manager engine: a closed window's turn records go with it -- where it was in each shape of the screen
// (gSMTurnFrames, gSMTurnPlaced), the layout it was in (gSMTurnLayout) and its behind-the-Dock mark (gSMBehindDock) -- so the app's next window,
// which opens on the same scene and so with the same key ("com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default"), starts with none of them.
// The A12Z 18.5 (p05, rows C17 V2 and D5): after Clock's window closed as the iPad's last window, a new 1065 x 819 Clock window was put at the old
// iPhone window's portrait frame at a turn ("back where they were in this shape"), and a new iPhone window that nobody moved was "behind the Dock as
// the user left them" at both turns, from the closed window's mark, and ended 20 pt under the Dock's top. Three causes in the code: the mark had no
// forget at all (DMSMTurnForget took the notes only); the look for closed windows read SpringBoard's empty list of stages (the last window gone) as a
// list it could not read, so it saw no close; and the look runs only with nothing moving, so a window opened again before it ran took the old
// records. The fix: DMSMTurnForget takes the mark with the notes (DMSMForgetApp hands it the app's marks too), the look reads an empty list after the
// start as no window (DMSMWindowKeysAfterStart, as Fit's own look reads it), and the window opening -- SpringBoard's launch, our icon tap -- drops a
// closed window's records of its key before it is in a stage (DMSMTurnForgetOpening, as Fit forgets one where a window opens).
// The real code is cut out of statusbar/StatusBar.x by test-smturnclosed.sh (smturnclosed-decl.inc, smturnclosed-real.inc): the turn and its body
// (DMSMWatchTurn), the notes (DMSMTurnNote, DMSMLayoutsFor), the place applier and its helpers, the forget (DMSMTurnForget, DMSMWindowKeysIn,
// DMSMWindowKeysAfterStart, DMSMTurnForgetClosed, DMSMTurnForgetOpening, DMSMForgetPlacesOf, DMSMForgetApp, DMSMAppSizeForgetPlace) and
// SMFitPlan.h's DMSMFitClosedKeys, with the real SMWindowKey.h, SMFit.h and TurnPlace.h. SpringBoard's stages and its requests are stand-ins as in
// test-smturnbehind.m, with a list of stages: the stage on screen while it has windows, the hidden ones (a minimized window, another desktop's), a
// stage that can't be read, or no list at all. The geometry is the A12Z's: landscape 1366 x 1024 with the desktop's whole windows at 37..948, portrait
// 1024 x 1366 at 37..1303.6.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <limits.h>
#include "SMWindowKey.h"
#include "SMFit.h"
#include "TurnPlace.h"

static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's geometry helpers, on Foundation ----
@interface NSValue (STCGeometry)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
@end
@implementation NSValue (STCGeometry)
+ (NSValue *)valueWithCGRect:(CGRect)r { return [NSValue valueWithBytes:&r objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect r; [self getValue:&r]; return r; }
@end
static NSString *NSStringFromCGRect(CGRect r) { return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
static NSString *NSStringFromCGSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic) CGRect bounds;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
@end
@interface UIView : NSObject
@end
@implementation UIView
@end
static CFTimeInterval gNow = 1000.0;
static CFTimeInterval CACurrentMediaTime(void) { return gNow; }
// (the turn's body runs 0.9 s later on the main queue, and again 0.3 s later while the turn settles: queued with their time, run in time order)
static NSMutableArray<NSArray *> *gQueue;   // ([time, block])
static void TQueue(double delay, dispatch_block_t b) { [gQueue addObject:@[@(gNow + delay), [b copy]]]; }
#define dispatch_time(base, delta) ((double)(delta) / (double)NSEC_PER_SEC)
#define dispatch_after(when, queue, ...) TQueue((when), __VA_ARGS__)

// ---- the real declarations (StatusBar.x's) ----
#include "smturnclosed-decl.inc"
static NSMutableDictionary *gSidePromptCtx;
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows;
static NSMutableSet<NSString *> *gSMFitWentFull;
static NSDictionary<NSString *, NSString *> *gSMFitSlotsBeforeFull;
static NSMutableDictionary<NSString *, NSDictionary *> *gSMPreZoomPlaces;
static NSMutableDictionary<NSString *, id> *gSMMinPictures;
static BOOL gMSWSwitching = NO;

// ---- stand-ins: SpringBoard's attributes and stages ----
@interface TAttrs : NSObject
@property (nonatomic) CGSize norm; @property (nonatomic) CGRect ref; @property (nonatomic) long long type;
@property (nonatomic) CGPoint center; @property (nonatomic) long policy; @property (nonatomic) long long time; @property (nonatomic) BOOL byUser;
@end
@implementation TAttrs
- (TAttrs *)dup { TAttrs *a = [TAttrs new]; a.norm = _norm; a.ref = _ref; a.type = _type; a.center = _center; a.policy = _policy; a.time = _time; a.byUser = _byUser; return a; }
@end
@interface TStage : NSObject
@property (nonatomic, strong) NSMutableDictionary *items;   // ("item:<window key>" -> TAttrs)
@end
@implementation TStage
@end
static TStage *gStage;                       // (the stage on screen: in SpringBoard's list while it has a window)
static NSMutableArray<TStage *> *gHidden;    // (hidden stages: a minimized window's, another Mac Switcher desktop's)
static int gList = 0;                        // (0: the list as it is; 1: no list, SpringBoard's switcher not there; 2: one stage of it can't be read)
static BOOL gEngine = YES, gBusy = NO, gGesture = NO;
static int gRequests = 0, gWrites = 0;
static NSArray<NSArray *> *gLastPlan;
static NSMutableArray<NSString *> *gLog;
static NSMutableArray<NSString *> *gUnminimized;

#define DM_FEATURE_MARK(x) do { } while (0)
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static BOOL DMSMEngine(void) { return gEngine; }
static id DMSMCardFor(NSString *key) { (void)key; return nil; }
static BOOL DMSMIsAttrs(id a) { return [a isKindOfClass:[TAttrs class]]; }
static long DMSMPolicyOf(id attrs) { return DMSMIsAttrs(attrs) ? ((TAttrs *)attrs).policy : 0; }
static BOOL DMSMAttrsFullScreen(id attrs) { return DMSMIsAttrs(attrs) && ((TAttrs *)attrs).policy == 2; }
static BOOL DMSMAttrAttributedSize(id attrs, DMSMAttributedSize *out) {
    if (!DMSMIsAttrs(attrs) || !out) return NO;
    TAttrs *a = attrs; out->normalizedSize = a.norm; out->referenceBounds = a.ref; out->type = a.type; return YES;
}
static BOOL DMSMAttrCenter(id attrs, CGPoint *out) { if (!DMSMIsAttrs(attrs) || !out) return NO; *out = ((TAttrs *)attrs).center; return YES; }
static id DMSMAttrWith(id attrs, DMSMAttributedSize s, CGPoint c, long long policy, long long time) {
    if (!DMSMIsAttrs(attrs) || !isfinite(c.x) || !isfinite(c.y) || !(s.normalizedSize.width > 0) || !(s.normalizedSize.height > 0)) return nil;
    TAttrs *a = [(TAttrs *)attrs dup];
    a.norm = s.normalizedSize; a.ref = s.referenceBounds; a.type = s.type; a.center = c; a.policy = (long)policy;
    if (time >= 0) a.time = time;
    return a;
}
static id DMSMAttrPlacedByUser(id attrs) { if (!DMSMIsAttrs(attrs)) return attrs; TAttrs *a = [(TAttrs *)attrs dup]; a.byUser = YES; return a; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { return DMSMIsAttrs(attrs) ? ((TAttrs *)attrs).time : dflt; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[TStage class]] ? [((TStage *)stage).items copy] : nil; }
static NSString *DMSMItemKey(id item) { return [item isKindOfClass:[NSString class]] && [item hasPrefix:@"item:"] ? [item substringFromIndex:5] : nil; }
static long long DMSMRoleOr(id stage, id item, long long dflt) {
    NSArray *keys = [[DMSMStageItemsMap(stage) allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger i = [keys indexOfObject:item];
    static const long long roles[] = {1, 2, 5, 6, 7, 8, 9};
    return i == NSNotFound || i >= 7 ? dflt : roles[i];
}
static id DMSMEntityForStageItem(id stage, id item) { (void)stage; return item; }
static NSString *DMSMEntityKey(id entity) { return DMSMItemKey(entity); }
static id DMSMStageDisplayIdentity(id stage) { return stage ? @"main" : nil; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"main"]; }
static id DMSMWorkingStage(void) { return gStage; }
static BOOL DMSMSizeRefitPending(double *placedTop) { (void)placedTop; return NO; }
static id DMSMAttrsRefitTop(id attrs, NSString *who, BOOL old24, BOOL sized, double placedTop) { (void)attrs; (void)who; (void)old24; (void)sized; (void)placedTop; return nil; }
// (1.8.8.3: a window the user let go past the screen's edge keeps that place -- test-smpastedge.sh runs the real ones; none is recorded here)
static BOOL DMSMPastEdgeHeld(CGPoint c, CGSize s, CGSize scr) { (void)c; (void)s; (void)scr; return NO; }
static BOOL DMSMPastEdgeKeepIn(CGPoint *cp, CGSize pts, CGSize scr, CGRect u) { (void)cp; (void)pts; (void)scr; (void)u; return NO; }
static const CGSize kLand = {1366, 1024}, kPort = {1024, 1366};
static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {
    (void)identity;
    CGSize scr = [UIScreen mainScreen].bounds.size;
    if (screenOut) *screenOut = scr;
    return scr.width > scr.height ? CGRectMake(0, 37, 1366, 911) : CGRectMake(0, 37, 1024, 1266.6);
}
static CGRect DMSMUsableAreaForStage(id stage, CGSize *screenOut) { (void)stage; return DMSMUsableAreaForIdentity(nil, screenOut); }
static CGRect DMUsableArea(void) { return DMSMUsableAreaForIdentity(nil, NULL); }
static CGRect TLayout(NSString *name, CGRect u) {
    CGFloat x = u.origin.x, y = u.origin.y, w = u.size.width, h = u.size.height;
    NSDictionary<NSString *, NSValue *> *m = @{ @"fill": [NSValue valueWithCGRect:u], @"left": [NSValue valueWithCGRect:CGRectMake(x, y, w / 2, h)],
        @"right": [NSValue valueWithCGRect:CGRectMake(x + w / 2, y, w / 2, h)] };
    NSValue *v = [name isKindOfClass:[NSString class]] ? m[name] : nil;
    return v ? v.CGRectValue : CGRectNull;
}
static CGRect DMSMLayoutFrameIn(NSString *name, CGRect u, CGSize screen) { (void)screen; return TLayout(name, u); }
static CGRect DMLayoutFrameInArea(NSString *name, CGRect u, CGSize screen) { (void)screen; return TLayout(name, u); }
static CGRect DMA5StageFromWindow(CGRect r) { return r; }
static BOOL DMSMRequestPlan(id identity, BOOL onMain, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity, BOOL whole) {
    (void)identity; (void)onMain; (void)label; (void)allowed; (void)frontEntity; (void)whole;
    gRequests++; gLastPlan = plan;
    for (NSArray *row in plan) if (row.count == 3 && gStage.items[row[0]]) gStage.items[row[0]] = row[2];
    return YES;
}
static CGRect TWhole(TAttrs *a, CGSize scr) {
    if (a.policy == 2) return CGRectMake(0, -kSMBarH, scr.width, scr.height + kSMBarH);
    CGSize pts = DMSMFitSizeInPoints(a.norm, a.ref, a.type, scr);
    CGPoint c = CGPointMake(a.center.x * scr.width, a.center.y * scr.height);
    return CGRectMake(c.x - pts.width / 2.0, c.y - pts.height / 2.0 - kSMBarH, pts.width, pts.height + kSMBarH);
}
static NSDictionary<NSString *, NSValue *> *DMSMOpenWindowFrames(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    CGSize scr = [UIScreen mainScreen].bounds.size;
    for (NSString *it in gStage.items) out[DMSMItemKey(it)] = [NSValue valueWithCGRect:TWhole(gStage.items[it], scr)];
    return out;
}
// SpringBoard's list of stages: the one on screen while it holds a window (the desktop's last window closed: the Home Screen, no stage of it), the
// hidden ones; no list; or one stage that can't be read
static NSArray *DMSMRecentStages(void) {
    if (gList == 1) return nil;
    NSMutableArray *l = [NSMutableArray array];
    if (gStage.items.count) [l addObject:gStage];
    for (TStage *s in gHidden) if (s.items.count) [l addObject:s];
    if (gList == 2) [l addObject:[NSNull null]];
    return l;
}
static id DMSMStageOf(NSString *key) {
    for (TStage *s in DMSMRecentStages()) if ([s isKindOfClass:[TStage class]]) for (NSString *it in s.items) if (DMSMKeyCovers(key, DMSMItemKey(it))) return s;
    return gStage;
}
static id DMFrontApp(void) { return gStage.items.count ? @"an app in front" : nil; }   // (none at the Home Screen)
static BOOL DMSMSpotlightHolds(void) { return NO; }
static BOOL DMSMWorkspaceBusy(void) { return gBusy; }
static BOOL DMSwitcherVisible(void) { return NO; }
static BOOL DMSMGestureLive(void) { return gGesture; }
static void DMSMMinimizedLook(void) { }   // (the minimized marks' own look: test-smminpictures)
static BOOL DMFitEnabled(void) { return NO; }
static BOOL DMDockRoomChangedSinceSave(void) { return NO; }
static int DMDockSideNow(CGSize screen) { (void)screen; return 0; }
static BOOL DMLayoutNotesHeld(void) { return NO; }
static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) { if (!gSMTurnLayout) gSMTurnLayout = [NSMutableDictionary dictionary]; return gSMTurnLayout; }
static NSDictionary<NSString *, NSString *> *DMSMRoomWaitMerged(NSDictionary<NSString *, NSString *> *notes) { return notes; }
static void DMSMRoomWaitNote(NSDictionary<NSString *, NSValue *> *frames) { (void)frames; }
static void DMSMRoomWaitLift(void) { }
static void DMSMStateWrite(void) { gWrites++; gSMTurnLayoutWritten = [gSMTurnLayout copy]; }
static void DMSMFitHiddenStages(id onScreen, NSDictionary<NSString *, NSString *> *layouts, NSDictionary<NSString *, NSDictionary *> *places) { (void)onScreen; (void)layouts; (void)places; }
static NSString *DMSMFrontWindowKey(void) { return nil; }
static NSMutableDictionary<NSString *, NSDictionary *> *DMSMPreZoomPlaces(void) { if (!gSMPreZoomPlaces) gSMPreZoomPlaces = [NSMutableDictionary dictionary]; return gSMPreZoomPlaces; }
static void DMAppSizeWriteSMPreZoom(void) { }
static void DMSMSetMinimized(NSString *key, BOOL on) { if (!on) [gUnminimized addObject:key ?: @"(nil)"]; }

// ---- the real code (StatusBar.x declares these ahead the same way) ----
static void DMSMTurnNote(void);
static BOOL DMSMTurnSettling(void);
static NSDictionary<NSString *, NSString *> *DMSMLayoutsFor(NSDictionary<NSString *, NSValue *> *frames);
static NSString *DMSMShapeKey(CGSize s);
static BOOL DMSMApplyLayouts(NSDictionary<NSString *, NSString *> *keyToLayout);
static BOOL DMSMApplyLayoutsIn(NSDictionary<NSString *, NSString *> *keyToLayout, id stage);
static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *keyToPlace, id stage);
static BOOL DMSMApplyPlacesMarkedIn(NSDictionary<NSString *, id> *keyToPlace, id stage, NSSet<NSString *> *placedByUser);
static id DMSMAttrsForLayoutIn(id attrs, NSString *name, id stage);
static id DMSMAttrsForFrameIn(id attrs, CGRect w, id stage);
static BOOL DMSMAttrsSamePlace(id a, id b, CGSize screen);
static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock);
static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle);
static NSArray<NSArray *> *DMSMPlanFitted(id identity, NSArray<NSArray *> *plan);
static BOOL DMSMRequestOn(id identity, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity);
static id DMSMItemFor(id stage, NSString *key, id *attrsOut);
static void DMSMWatchTurn(void);
static NSString *DMSMWindowKeyOf(NSString *key);
static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why);
static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages);
static void DMSMTurnForgetClosed(void);
static void DMSMTurnForgetOpening(NSString *opening);
static BOOL DMSMForgetPlacesOf(NSString *bundle);
static void DMSMForgetApp(NSString *bundle);
static void DMSMAppSizeForgetPlace(NSString *bundle);
#include "smturnclosed-real.inc"

// ---- the scenarios ----
static NSString *const kClock = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default";   // (the app's default scene: every new Clock window's key)
static NSString *const kSettings = @"com.apple.Preferences|sceneID:com.apple.Preferences-default";
static NSString *const kCalc = @"com.apple.calculator|sceneID:com.apple.calculator-default";
static long long gTime = 100;
static NSString *Item(NSString *key) { return [@"item:" stringByAppendingString:key]; }
static TStage *NewStage(void) { TStage *s = [TStage new]; s.items = [NSMutableDictionary dictionary]; return s; }
static TAttrs *AttrsAt(CGRect whole) {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    TAttrs *a = [TAttrs new];
    CGRect card = CGRectMake(whole.origin.x, whole.origin.y + kSMBarH, whole.size.width, whole.size.height - kSMBarH);
    a.norm = CGSizeMake(card.size.width / scr.width, card.size.height / scr.height); a.ref = CGRectMake(0, 0, scr.width, scr.height); a.type = 0;
    a.center = CGPointMake(CGRectGetMidX(card) / scr.width, CGRectGetMidY(card) / scr.height); a.policy = 0; a.time = ++gTime;
    return a;
}
// a window moved by the user on the stage on screen to a whole frame; behind: its drop ends under the Dock (the title bar's record, tools/test-smdropdock.sh)
static void Drag(NSString *key, CGRect whole, BOOL behind) {
    TAttrs *a = AttrsAt(whole); TAttrs *was = gStage.items[Item(key)]; if (was) a.time = was.time;
    gStage.items[Item(key)] = a;
    if (!gSMBehindDock) gSMBehindDock = [NSMutableSet set];
    if (behind) [gSMBehindDock addObject:key]; else DMSMKeySetRemove(gSMBehindDock, key);
}
// SpringBoard's launch of a window: the join sees the window opening while it is in no stage yet (DMSMJoinDesktop: DMSMTurnForgetOpening with its
// key), then the window is on the stage on screen at the place we give it
static void Launch(NSString *key, CGRect whole) {
    DMSMTurnForgetOpening(key);
    for (TStage *s in gHidden) [s.items removeObjectForKey:Item(key)];   // (a minimized window coming back: out of its hidden stage)
    gStage.items[Item(key)] = AttrsAt(whole);
}
static void Close(NSString *key) { [gStage.items removeObjectForKey:Item(key)]; for (TStage *s in gHidden) [s.items removeObjectForKey:Item(key)]; }   // (its stage gone with it)
static void Minimize(NSString *key) { id a = gStage.items[Item(key)]; [gStage.items removeObjectForKey:Item(key)]; TStage *h = NewStage(); h.items[Item(key)] = a; [gHidden addObject:h]; }
static CGRect Frame(NSString *key) { NSValue *v = DMSMOpenWindowFrames()[key]; return v ? v.CGRectValue : CGRectNull; }
static BOOL Near(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 1.0 && fabs(a.origin.y - b.origin.y) < 1.0 && fabs(a.size.width - b.size.width) < 1.0 && fabs(a.size.height - b.size.height) < 1.0; }
static void RunQueue(void) {
    while (gQueue.count) {
        NSUInteger first = 0;
        for (NSUInteger i = 1; i < gQueue.count; i++) if ([gQueue[i][0] doubleValue] < [gQueue[first][0] doubleValue]) first = i;
        NSArray *e = gQueue[first]; [gQueue removeObjectAtIndex:first];
        if ([e[0] doubleValue] > gNow) gNow = [e[0] doubleValue];
        ((dispatch_block_t)e[1])();
    }
}
static void Still(void) { gNow += 3.0; DMSMWatchTurn(); }   // (the iPad is still: the watcher's note and its look for closed windows)
static void Turn(CGSize to) {
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, to.width, to.height);
    gNow += 0.2; DMSMWatchTurn();
    RunQueue();
    Still();
}
static void Fresh(CGSize shape) {
    gEngine = NO; DMSMWatchTurn(); gEngine = YES;
    gSMTurnFrames = nil; gSMTurnPlaced = nil; gSMTurnLayout = nil; gSMTurnLayoutWritten = nil; gSMBehindDock = [NSMutableSet set];
    gSMPreZoom = nil; gSMPreZoomPlaces = nil; gSMFitWentFull = nil; gSMFitSlotsBeforeFull = nil; gSMMinPictures = nil;
    gStage = NewStage(); gHidden = [NSMutableArray array]; gList = 0; gBusy = NO; gGesture = NO; gMSWSwitching = NO;
    [gQueue removeAllObjects]; [gLog removeAllObjects]; gRequests = 0; gLastPlan = nil; gWrites = 0;
    gSMTurnStartSettled = YES;   // (the start has settled: SMHome.h's point, or the first note)
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, shape.width, shape.height);
    DMSMWatchTurn();
}
static BOOL Behind(NSString *key) { return DMSMKeySetHas(gSMBehindDock, key); }
static BOOL Records(NSString *key) { return gSMTurnFrames[key] || gSMTurnLayout[key] || gSMTurnPlaced[key] || [gSMBehindDock containsObject:key]; }
static NSString *R(CGRect r) { return NSStringFromCGRect(r); }
static NSString *LogWith(NSString *part) { for (NSString *l in gLog.reverseObjectEnumerator) if ([l rangeOfString:part].location != NSNotFound) return l; return nil; }
static BOOL Has(NSString *line, NSString *part) { return line && [line rangeOfString:part].location != NSNotFound; }
static NSString *TurnLine(void) { return LogWith(@"[sm] the iPad turned: windows back in their layouts"); }
static NSString *BehindLine(void) { return LogWith(@"[sm] the iPad turned: behind the Dock as the user left them"); }
static void ClearLog(void) { [gLog removeAllObjects]; }

int main(void) { @autoreleasepool {
    gQueue = [NSMutableArray array]; gLog = [NSMutableArray array]; gUnminimized = [NSMutableArray array];
    const CGFloat landDock = 948.0;
    const CGRect iphoneL = CGRectMake(487, 56, 393, 876), iphoneP = CGRectMake(316, 225, 393, 876);   // (Clock at iPhone, whole windows, as on the A12Z)
    const CGRect sizeL = CGRectMake(150, 49, 1065, 819), sizeBehindL = CGRectMake(150, 205, 1065, 819);   // (Window Size's window; dragged down to the screen's bottom)

    printf("-- 1. C17 V2 (A12Z 18.5, 19:55 and 20:05): Clock at iPhone turned to portrait and back; App Window Sizes' entry removed; Clock closed as the iPad's last window; a new Clock window at Window Size's, dragged behind the Dock; the turn to portrait\n");
    Fresh(kLand);
    Launch(kClock, iphoneL); Still();
    Turn(kPort);
    Drag(kClock, iphoneP, NO); Still();   // (its portrait place, as the device had it)
    Turn(kLand);
    Expect(Near(Frame(kClock), iphoneL) && gSMTurnFrames[kClock][@"P"] && gSMTurnFrames[kClock][@"L"], [NSString stringWithFormat:@"Clock's places in both shapes noted, back at its landscape place (%@)", R(Frame(kClock))]);
    DMSMAppSizeForgetPlace(@"com.apple.mobiletimer");   // (aws none: Window Size from now on)
    Expect(gSMTurnFrames[kClock][@"P"] && gSMTurnFrames[kClock][@"L"], @"V1 as before: the entry's forget leaves the open window's own places (an open window is not moved, its turns are its own)");
    ClearLog();
    Close(kClock);   // (our close: the desktop's last window -- the Home Screen, SpringBoard lists no stage)
    Expect(DMSMRecentStages().count == 0, @"  (SpringBoard lists no stage: the iPad's last window closed)");
    Still();
    Expect(!Records(kClock), [NSString stringWithFormat:@"the close of the iPad's last window is seen: Clock's places per shape go (frames %lu, before H5: 2 kept)", (unsigned long)[gSMTurnFrames[kClock] count]]);
    Expect(Has(LogWith(@"were at a turn dropped"), @"where windows that are gone were at a turn dropped (closed): com.apple.mobiletimer/default (2 shape(s))"),
           [NSString stringWithFormat:@"  ... logged: %@", LogWith(@"were at a turn dropped") ?: @"(none)"]);
    Launch(kClock, sizeL); Still();
    Drag(kClock, sizeBehindL, YES); Still();
    ClearLog();
    Turn(kPort);
    CGRect p = Frame(kClock);
    Expect(Has(TurnLine(), @"back where they were in this shape: none"), [NSString stringWithFormat:@"the turn to portrait: the new window is back nowhere (no place of the closed window): %@", TurnLine() ?: @"(no turn line)"]);
    Expect(!Near(p, iphoneP) && p.size.width > 393.0 + 1.0, [NSString stringWithFormat:@"  ... not at the old iPhone window's portrait frame %@ (the A12Z: put there, 393 x 876): %@", R(iphoneP), R(p)]);
    Expect(Behind(kClock) && Has(BehindLine(), @"com.apple.mobiletimer/default"), @"  ... its own mark (dragged behind the Dock) kept: down to the screen's bottom, as the user left it");
    Turn(kLand);
    Expect(Near(Frame(kClock), sizeBehindL), [NSString stringWithFormat:@"  ... back in landscape where the user left it, 1065 x 819 (%@)", R(Frame(kClock))]);

    printf("-- 2. D5 (A12Z 18.5, 20:07 to 20:11): C17's counter window, behind the Dock, closed as the iPad's last window; the entry (iPhone) added while it is closed; a new Clock window at iPhone that nobody moves; the turns\n");
    ClearLog();
    Close(kClock); Still();
    Expect(!Records(kClock) && !Behind(kClock), @"the closed window's mark goes with its places (before H5: the mark stayed for good)");
    DMSMAppSizeForgetPlace(@"com.apple.mobiletimer");   // (aws iphone, Clock closed)
    Expect(!LogWith(@"Stage Manager's places forgotten"), @"  ... the entry's forget finds nothing of it left (as on the device: no line)");
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    ClearLog();
    Turn(kPort);
    Expect(!Behind(kClock) && !BehindLine(), [NSString stringWithFormat:@"the turn to portrait: the new iPhone window is not behind the Dock (the A12Z: \"behind the Dock as the user left them\" from the closed window's mark): %@", BehindLine() ?: @"no line"]);
    ClearLog();
    Turn(kLand);
    CGRect l = Frame(kClock);
    Expect(!Behind(kClock) && !BehindLine() && CGRectGetMaxY(l) <= landDock + 0.5, [NSString stringWithFormat:@"the turn back: above the Dock, bottom %.1f (the A12Z: 972, 20 pt under the Dock's top), %@", CGRectGetMaxY(l), BehindLine() ?: @"no line"]);

    printf("-- 3. D5's second close (20:09:58): Clock behind the Dock closed while Settings stays on the desktop\n");
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();   // (its bottom at the screen's bottom)
    Expect(Behind(kClock) && gSMTurnFrames[kClock], @"Clock dragged behind the Dock: marked, its place noted");
    ClearLog();
    Close(kClock); Still();
    Expect(!Records(kClock), @"its close: its places and its mark go (before H5: the places went, the mark stayed)");
    Expect(gSMTurnFrames[kSettings] && !Behind(kSettings), @"  ... Settings, still on the desktop, keeps its own");
    Launch(kClock, iphoneL); Still();
    ClearLog();
    Turn(kPort);
    Expect(!Behind(kClock) && !Has(BehindLine(), @"mobiletimer"), [NSString stringWithFormat:@"the app's next window at a turn: not named behind the Dock (%@)", BehindLine() ?: @"no line"]);

    printf("-- 4. a close and an open back to back, a workspace transition in flight all along (the look waits for it): the opening drops the closed window's records\n");
    Fresh(kLand);
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    Turn(kPort); Drag(kClock, CGRectMake(316, 490, 393, 876), YES); Still(); Turn(kLand);   // (portrait: behind the portrait Dock)
    Expect(Behind(kClock) && gSMTurnFrames[kClock][@"P"], @"Clock with a portrait place behind the Dock, marked");
    gBusy = YES; ClearLog();
    Close(kClock); Still();
    Expect(Records(kClock), @"  (the look waits for the transition: nothing forgotten yet)");
    Launch(kClock, iphoneL);   // (its Dock icon: SpringBoard's launch, the join)
    Expect(!Records(kClock), @"the launch: the closed window's places and mark go before the new window is in a stage (before H5: kept, its key is back)");
    Expect(Has(LogWith(@"were at a turn dropped"), @"(closed; com.apple.mobiletimer/default opens): com.apple.mobiletimer/default (2 shape(s), behind the Dock)"),
           [NSString stringWithFormat:@"  ... logged: %@", LogWith(@"were at a turn dropped") ?: @"(none)"]);
    gBusy = NO; Still();
    ClearLog();
    Turn(kPort);
    Expect(!Behind(kClock) && TurnLine() && !Has(TurnLine(), @"mobiletimer") && !Has(BehindLine(), @"mobiletimer"), [NSString stringWithFormat:@"  ... the turn: the new window put back at no place of the old one and not behind the Dock (%@)", TurnLine() ?: @"no line"]);
    printf("-- 4b. the same at an icon tap (DMSMAddToStage: the app's key, before its window exists)\n");
    Fresh(kLand);
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();
    gBusy = YES; Close(kClock); Still();
    DMSMTurnForgetOpening(@"com.apple.mobiletimer");
    Expect(!Records(kClock), @"the icon tap: Clock's closed window's records go");
    gBusy = NO;

    printf("-- 5. nothing is taken for closed that is not\n");
    Fresh(kLand);
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();
    Minimize(kClock); Still();   // (its yellow light: a hidden stage of its own)
    Expect(Records(kClock) && Behind(kClock), @"a minimized window (a hidden stage) keeps its places and its mark");
    Close(kSettings); Still();   // (the desktop's other window closes: only Clock's hidden stage is left)
    Expect(Records(kClock) && Behind(kClock) && !Records(kSettings), @"  ... also with no window on screen (only its hidden stage listed); Settings' records go");
    Launch(kClock, CGRectMake(487, 148, 393, 876));   // (back from the Dock: the join sees it in its hidden stage)
    Expect(Behind(kClock) && gSMTurnFrames[kClock], @"  ... its return: the join keeps them (it is in a stage)");
    ClearLog(); Turn(kPort);
    Expect(Has(BehindLine(), @"com.apple.mobiletimer/default"), @"  ... and the turn keeps it behind the Dock as the user left it");
    Fresh(kLand);
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();
    Close(kClock);
    gList = 1; Still(); BOOL keptNoList = Records(kClock);
    gNow += 2.0; gList = 2; Still(); BOOL keptUnread = Records(kClock);
    gNow += 2.0; gList = 0; gSMTurnStartSettled = NO; Still(); BOOL keptStart = Records(kClock);
    DMSMTurnForgetOpening(kClock); BOOL keptStartOpen = Records(kClock);
    Expect(keptNoList, @"no list (SpringBoard's switcher not there): nothing forgotten");
    Expect(keptUnread, @"a stage that can't be read: nothing forgotten");
    Expect(keptStart && keptStartOpen, @"an empty list before the start has settled (SpringBoard's model may not be there yet, SMHome.h): nothing forgotten, at the look or an opening");
    gSMTurnStartSettled = YES; gNow += 2.0; Still();
    Expect(!Records(kClock), @"  ... the same empty list once the start has settled: Clock's records go");
    Fresh(kLand);
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();
    gBusy = YES; Close(kClock); Still();
    Launch(kCalc, CGRectMake(400, 300, 393, 600));
    Expect(Records(kClock) && Behind(kClock), @"another app's window opening drops none of Clock's (only the keys of the window that opens; the look takes the others)");
    gBusy = NO; Still();
    Expect(!Records(kClock), @"  ... the look then does");
    Fresh(kLand);
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Still();
    gBusy = YES; Close(kClock); Still();
    gGesture = YES; DMSMTurnForgetOpening(kClock); BOOL keptGesture = Records(kClock); gGesture = NO;
    gMSWSwitching = YES; DMSMTurnForgetOpening(kClock); BOOL keptSlide = Records(kClock); gMSWSwitching = NO;
    Expect(keptGesture && keptSlide, @"an opening during a switcher gesture or a Mac Switcher slide drops nothing (the stages change under them, as Fit's)");
    gBusy = NO;
    printf("-- 5b. windows told apart by app (an app's key)\n");
    Fresh(kLand);
    Launch(kClock, iphoneL); Still();
    [gSMBehindDock addObject:@"com.apple.mobiletimer"];   // (a mark made where windows can't be told apart: the app's key)
    NSString *kClock2 = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-6A1F0C2E";
    Minimize(kClock); Still();
    Launch(kClock2, CGRectMake(400, 100, 393, 600)); Still();
    Expect([gSMBehindDock containsObject:@"com.apple.mobiletimer"], @"the app's key stays while a window of the app is in a stage (one minimized, one opening)");
    Close(kClock2); Still();
    Expect([gSMBehindDock containsObject:@"com.apple.mobiletimer"] && !gSMTurnFrames[kClock2], @"  ... one of the two closes: its own records go, the app's key stays for the other (each key exactly)");
    Close(kClock); Still();
    Expect(![gSMBehindDock containsObject:@"com.apple.mobiletimer"], @"  ... and goes once no window of the app is left");
    printf("-- 5c. the app quits (Force Quit, the red light on its last window: DMSMForgetApp)\n");
    Fresh(kLand);
    Launch(kSettings, CGRectMake(150, 61, 1065, 794));
    Launch(kClock, iphoneL); Still();
    Drag(kClock, CGRectMake(487, 148, 393, 876), YES); Drag(kSettings, CGRectMake(150, 200, 1065, 824), YES); Still();
    gSMTurnLayout[kClock] = @"left";
    [gSMBehindDock addObject:@"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-4B0E7F12"];   // (a window of it marked and not noted yet: its drop less than a second ago)
    gWrites = 0;
    DMSMForgetApp(@"com.apple.mobiletimer");
    Expect(!Records(kClock) && !Behind(@"com.apple.mobiletimer") && [gUnminimized containsObject:@"com.apple.mobiletimer"], @"its windows' places, layout and marks go, a mark with no place noted too (before H5: the marks stayed)");
    Expect(Behind(kSettings) && gSMTurnFrames[kSettings], @"  ... another app's stay");
    Expect(gWrites >= 1 && !gSMTurnLayoutWritten[kClock], @"  ... a layout dropped is written to the state file");
    Fresh(kLand);
    Launch(kClock, iphoneL); Still();
    gSMTurnLayout[kClock] = @"fill"; gWrites = 0;
    Close(kClock); Still();
    Expect(!gSMTurnLayout[kClock] && gWrites >= 1 && Has(LogWith(@"the layouts of windows that are gone dropped"), @"(closed): com.apple.mobiletimer/default fill"),
           [NSString stringWithFormat:@"the iPad's last window closed with a layout noted: the layout goes too, memory and the file (%@)", LogWith(@"the layouts of windows that are gone dropped") ?: @"no line"]);

    printf("%s: %d checks, %d failed\n", fails ? "test-smturnclosed FAILED" : "test-smturnclosed: all pass", checks, fails);
    return fails > 98 ? 98 : fails;
} }
