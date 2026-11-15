// test-smturnbehind.m -- the Stage Manager engine: a window the user put behind the Dock keeps that place and its mark when the iPad turns and turns
// back (1.8.7.4 round 2, the 1.8.7.3 device check: the M4 row on the A12Z 18.5). The turn put the window back where it was in that shape, but kept
// every window above the Dock (its own fit) and took the window out of gSMBehindDock as it placed it (DMSMApplyPlacesMarkedIn: "placed by a
// layout"), so a Clock window at 601..1024, 76 pt under the Dock's line, came back at 525..948, above it, and stayed there. A window the user puts
// in a layout, or Centre, loses the mark as before; a window that is not behind the Dock and that the turn leaves partly under it is still lifted
// above it. 1.8.7.5 (engine parity, as Aerial, Zetsu and MilkyWay4 move it back exactly): the title bar's double tap Back after Fill or Zoom put such
// a window back lifted above the Dock -- Fill took the mark, as every place of ours does, and the title record kept none, so the request's own fit put
// the frame from before above the Dock; now the record keeps the mark and Back gives it back. The Window menu's places (DMWindowLayout) take the mark
// as every other place of ours: they kept it, so a window centred from the menu went back behind the Dock in the other shape.
// The real code is cut out of statusbar/StatusBar.x by test-smturnbehind.sh (smturnbehind-decl.inc, smturnbehind-real.inc): DMSMWatchTurn (the
// turn and its body), DMSMTurnNote and DMSMLayoutsFor (the places and layouts noted while the iPad is still), DMSMApplyPlacesMarkedIn and its
// wrappers, DMSMAttrsForLayoutIn / ForFrameIn / SamePlace, DMSMCardDesk, DMSMAttrsFitScreen, DMSMPlanFitted, DMSMRequestOn and DMSMItemFor, with
// the real SMWindowKey.h, SMFit.h and TurnPlace.h. SpringBoard's stage and its request are stand-ins: a stage holds each window's attributes
// (a size as fractions of its reference, a centre as fractions of the screen), a request puts the attributes it names into the stage, and a turn
// keeps every window's attributes (Stage Manager's own: the size in points of its reference, the centre in proportion). The geometry is the
// A12Z's from the device check: landscape 1366 x 1024 with the desktop's whole windows at 37..948, portrait 1024 x 1366 at 37..1303.6.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <limits.h>
#include "SMWindowKey.h"
#include "SMFit.h"
#include "TurnPlace.h"
#include "TitleBarRule.h"
#include "WindowKeysRule.h"
#include "WindowMinSize.h"

static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's geometry helpers, on Foundation ----
@interface NSValue (SBTGeometry)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
@end
@implementation NSValue (SBTGeometry)
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
static CFTimeInterval gNow = 1000.0;
static CFTimeInterval CACurrentMediaTime(void) { return gNow; }
// (the turn's body runs 0.9 s later on the main queue, and again 0.3 s later while the turn settles: queued here with their time, and run by the
//  scenario in time order, the clock moved to each one's time -- as the iPad runs them, so the body runs from its retry once the turn has settled)
static NSMutableArray<NSArray *> *gQueue;   // ([time, block])
static void TQueue(double delay, dispatch_block_t b) { [gQueue addObject:@[@(gNow + delay), [b copy]]]; }
#define dispatch_time(base, delta) ((double)(delta) / (double)NSEC_PER_SEC)
#define dispatch_after(when, queue, ...) TQueue((when), __VA_ARGS__)

// ---- the real declarations (StatusBar.x's: the attributed size, our title bar's height, the behind-the-Dock set, when the screen last turned) ----
#include "smturnbehind-decl.inc"
static NSMutableDictionary<NSString *, NSString *> *gSMTurnLayout;
static NSDictionary<NSString *, NSString *> *gSMTurnLayoutWritten;
static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gSMTurnFrames;
static NSMutableDictionary<NSString *, NSValue *> *gSMTurnPlaced;
static BOOL gSMTurnStartSettled = NO;
static NSMutableDictionary *gSidePromptCtx;
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows;
static BOOL gMSWSwitching = NO;

// ---- stand-ins: SpringBoard's attributes and stage ----
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
static TStage *gStage;
static BOOL gEngine = YES;
static int gRequests = 0;
static NSArray<NSArray *> *gLastPlan;
static NSMutableArray<NSString *> *gLog;

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
static id DMSMEntityForStageItem(id stage, id item) { (void)stage; return item; }   // (the window's own scene: here its item)
static NSString *DMSMEntityKey(id entity) { return DMSMItemKey(entity); }
static id DMSMStageDisplayIdentity(id stage) { return stage ? @"main" : nil; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"main"]; }
static id DMSMWorkingStage(void) { return gStage; }
static BOOL DMSMSizeRefitPending(double *placedTop) { (void)placedTop; return NO; }
static id DMSMAttrsRefitTop(id attrs, NSString *who, BOOL old24, BOOL sized, double placedTop) { (void)attrs; (void)who; (void)old24; (void)sized; (void)placedTop; return nil; }
// The desktop of the screen as it is (whole windows: our title bar and the card), as the A12Z had it in the device check: under the menu bar at 37,
// down to the Dock's line (948 in landscape, 1303.6 in portrait).
static const CGSize kLand = {1366, 1024}, kPort = {1024, 1366};
static CGRect DMSMUsableAreaForIdentity(id identity, CGSize *screenOut) {
    (void)identity;
    CGSize scr = [UIScreen mainScreen].bounds.size;
    if (screenOut) *screenOut = scr;
    return scr.width > scr.height ? CGRectMake(0, 37, 1366, 911) : CGRectMake(0, 37, 1024, 1266.6);
}
static CGRect DMSMUsableAreaForStage(id stage, CGSize *screenOut) { (void)stage; return DMSMUsableAreaForIdentity(nil, screenOut); }
static CGRect DMUsableArea(void) { return DMSMUsableAreaForIdentity(nil, NULL); }
// the Window menu's places, whole windows inside u (the real ones keep a gap; the same frames are used to note and to place here)
static CGRect TLayout(NSString *name, CGRect u) {
    CGFloat x = u.origin.x, y = u.origin.y, w = u.size.width, h = u.size.height;
    NSDictionary<NSString *, NSValue *> *m = @{ @"fill": [NSValue valueWithCGRect:u], @"left": [NSValue valueWithCGRect:CGRectMake(x, y, w / 2, h)],
        @"right": [NSValue valueWithCGRect:CGRectMake(x + w / 2, y, w / 2, h)], @"top": [NSValue valueWithCGRect:CGRectMake(x, y, w, h / 2)],
        @"bottom": [NSValue valueWithCGRect:CGRectMake(x, y + h / 2, w, h / 2)], @"topleft": [NSValue valueWithCGRect:CGRectMake(x, y, w / 2, h / 2)],
        @"topright": [NSValue valueWithCGRect:CGRectMake(x + w / 2, y, w / 2, h / 2)], @"bottomleft": [NSValue valueWithCGRect:CGRectMake(x, y + h / 2, w / 2, h / 2)],
        @"bottomright": [NSValue valueWithCGRect:CGRectMake(x + w / 2, y + h / 2, w / 2, h / 2)],
        @"center": [NSValue valueWithCGRect:CGRectMake(x + (w - 615) / 2, y + 244, 615, 423)] };
    NSValue *v = [name isKindOfClass:[NSString class]] ? m[name] : nil;
    return v ? v.CGRectValue : CGRectNull;
}
static CGRect DMSMLayoutFrameIn(NSString *name, CGRect u, CGSize screen) { (void)screen; return TLayout(name, u); }
static CGRect DMLayoutFrameInArea(NSString *name, CGRect u, CGSize screen) { (void)screen; return TLayout(name, u); }
static CGRect DMA5StageFromWindow(CGRect r) { return r; }
// SpringBoard's request: the attributes it names go into the stage (what it shows next)
static BOOL DMSMRequestPlan(id identity, BOOL onMain, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity, BOOL whole) {
    (void)identity; (void)onMain; (void)label; (void)allowed; (void)frontEntity; (void)whole;
    gRequests++; gLastPlan = plan;
    for (NSArray *row in plan) if (row.count == 3 && gStage.items[row[0]]) gStage.items[row[0]] = row[2];
    return YES;
}
// the stage's windows on the screen as it is now (whole windows, by window key)
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
// the rest of the world: still, nothing in the way
static id DMFrontApp(void) { return @"an app in front"; }
static BOOL DMSMSpotlightHolds(void) { return NO; }
static BOOL DMSMWorkspaceBusy(void) { return NO; }
static BOOL DMSwitcherVisible(void) { return NO; }
static BOOL DMSMGestureLive(void) { return NO; }
static void DMSMTurnForgetClosed(void) { }
static void DMSMMinimizedLook(void) { }   // (DMSMWatchTurn's look for gone minimized windows, 1.8.7.5 audit L37: the real one in test-smminpictures)
static BOOL DMFitEnabled(void) { return NO; }
static BOOL DMDockRoomChangedSinceSave(void) { return NO; }
static int DMDockSideNow(CGSize screen) { (void)screen; return 0; }
static BOOL DMLayoutNotesHeld(void) { return NO; }
static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) { if (!gSMTurnLayout) gSMTurnLayout = [NSMutableDictionary dictionary]; return gSMTurnLayout; }
static NSDictionary<NSString *, NSString *> *DMSMRoomWaitMerged(NSDictionary<NSString *, NSString *> *notes) { return notes; }
static void DMSMRoomWaitNote(NSDictionary<NSString *, NSValue *> *frames) { (void)frames; }
static void DMSMRoomWaitLift(void) { }
static void DMSMStateWrite(void) { gSMTurnLayoutWritten = [gSMTurnLayout copy]; }
static NSArray *DMSMRecentStages(void) { return gStage ? @[gStage] : @[]; }
static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages) { (void)stages; return nil; }
static NSSet<NSString *> *DMSMFitClosedKeys(id<NSFastEnumeration> keys, NSSet<NSString *> *present, NSSet<NSString *> *pending) { (void)keys; (void)present; (void)pending; return nil; }
static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) { (void)keys; (void)why; }
static int gHiddenFits = 0;
static void DMSMFitHiddenStages(id onScreen, NSDictionary<NSString *, NSString *> *layouts, NSDictionary<NSString *, NSDictionary *> *places) { (void)onScreen; (void)layouts; (void)places; gHiddenFits++; }
// (the title bar's double tap and the Window menu, 1.8.7.5: Stage Manager's window of a key is on the one stage here)
static int gTitleDoubleTap = kMSBDTitleFill;
static NSString *gFrontKey;
static id DMSMStageOf(NSString *key) { (void)key; return gStage; }
static NSString *DMSMFrontWindowKey(void) { return gFrontKey; }
static BOOL DMSMWindowAction(NSString *key, NSString *name) { (void)key; (void)name; return NO; }
static CGFloat DMSMMinWindowWidth(CGSize scr) { (void)scr; return 320.0; }
static void DMSMStripPresentationEnd(NSString *why) { (void)why; }
static void DMSMFitLetGo(NSString *key) { (void)key; }
static void DMWinPrevNoteSM(NSString *key, id stage) { (void)key; (void)stage; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut);
static BOOL gTNotPlaced = NO;   // (the request refused: "not in the stage")
static BOOL DMSMSetWindowGeometry(NSString *key, CGPoint center, CGSize size) {   // (its request: the window's centre and size, fractions of the screen)
    if (gTNotPlaced) return NO;
    id attrs = nil, item = DMSMItemFor(gStage, key, &attrs);
    if (!item || !attrs) return NO;
    CGSize scr = [UIScreen mainScreen].bounds.size;
    TAttrs *a = [(TAttrs *)attrs dup];
    a.center = center; a.norm = size; a.ref = CGRectMake(0, 0, scr.width, scr.height); a.type = 0; a.policy = 0;
    gStage.items[item] = a; gRequests++;
    return YES;
}

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
static void DMTitleRecordSMTo(NSString *key, id stage, CGRect to);
#include "smturnbehind-real.inc"
#include "smturnbehind-wk.inc"
#include "smturnbehind-tb.inc"
#include "smturnbehind-layout.inc"

// ---- the scenarios ----
static NSString *const kClock = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-6A1F0C2E";
static NSString *const kSettings = @"com.apple.Preferences|sceneID:com.apple.Preferences-0B7D44A1";
static NSString *const kTips = @"com.apple.tips|sceneID:com.apple.tips-91C2E5D7";
static NSString *const kFiles = @"com.apple.DocumentsApp|sceneID:com.apple.DocumentsApp-3D8B21F0";
static long long gTime = 100;
static NSString *Item(NSString *key) { return [@"item:" stringByAppendingString:key]; }
// a window put at a whole frame on the screen as it is (its attributes as Stage Manager keeps them: fractions of this screen)
static void Put(NSString *key, CGRect whole) {
    CGSize scr = [UIScreen mainScreen].bounds.size;
    TAttrs *a = gStage.items[Item(key)] ?: [TAttrs new];
    CGRect card = CGRectMake(whole.origin.x, whole.origin.y + kSMBarH, whole.size.width, whole.size.height - kSMBarH);
    a.norm = CGSizeMake(card.size.width / scr.width, card.size.height / scr.height); a.ref = CGRectMake(0, 0, scr.width, scr.height); a.type = 0;
    a.center = CGPointMake(CGRectGetMidX(card) / scr.width, CGRectGetMidY(card) / scr.height); a.policy = 0;
    if (!gStage.items[Item(key)]) a.time = ++gTime;
    gStage.items[Item(key)] = a;
}
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
// the iPad is still: the windows noted as they are (DMSMWatchTurn's note, once a second)
static void Still(void) { gNow += 3.0; DMSMWatchTurn(); }
// the iPad turns: SpringBoard keeps each window's attributes (its size by its reference, its centre in proportion), the watcher sees the new shape,
// the body runs once the turn has settled; then the iPad is still again
static void Turn(CGSize to) {
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, to.width, to.height);
    gNow += 0.2; DMSMWatchTurn();
    RunQueue();
    Still();
}
static void Fresh(CGSize shape) {
    gEngine = NO; DMSMWatchTurn(); gEngine = YES;   // (the watcher's own memory of the screen, as when the engine goes off and on)
    gSMTurnFrames = nil; gSMTurnPlaced = nil; gSMTurnLayout = nil; gSMTurnLayoutWritten = nil; gSMBehindDock = [NSMutableSet set];
    gStage = [TStage new]; gStage.items = [NSMutableDictionary dictionary];
    [gQueue removeAllObjects]; [gLog removeAllObjects]; gRequests = 0; gLastPlan = nil;
    [UIScreen mainScreen].bounds = CGRectMake(0, 0, shape.width, shape.height);
    DMSMWatchTurn();   // (the first look: the screen as it is)
}
static BOOL Behind(NSString *key) { return DMSMKeySetHas(gSMBehindDock, key); }
static NSString *R(CGRect r) { return NSStringFromCGRect(r); }
static NSString *LogWith(NSString *part) { for (NSString *l in gLog.reverseObjectEnumerator) if ([l rangeOfString:part].location != NSNotFound) return l; return nil; }   // (the last such line)
static BOOL Has(NSString *line, NSString *part) { return line && [line rangeOfString:part].location != NSNotFound; }
// the attributes the last request asked for a window, as a whole frame on the screen as it is (after the request's own fit, DMSMPlanFitted)
static CGRect Asked(NSString *key) {
    for (NSArray *row in gLastPlan) if ([DMSMItemKey(row[0]) isEqualToString:key]) return TWhole(row[2], [UIScreen mainScreen].bounds.size);
    return CGRectNull;
}

int main(void) { @autoreleasepool {
    gQueue = [NSMutableArray array]; gLog = [NSMutableArray array];
    const CGFloat landDock = 948.0, portDock = 1303.6;   // (the desktop's bottom: the Dock's line)

    printf("-- 1. the A12Z's M4 step 3: Clock pushed behind the Dock in landscape, the iPad turned to portrait and back (twice)\n");
    Fresh(kPort);
    CGRect clockP = CGRectMake(204.5, 532, 615, 423);   // (portrait, above the Dock: the step 2 turn's place)
    Put(kClock, clockP);
    Put(kSettings, TLayout(@"left", DMUsableArea()));   // (a window in a layout beside it)
    Still();
    Turn(kLand);
    Expect(!Behind(kClock) && Frame(kClock).origin.y + Frame(kClock).size.height <= landDock + 0.5, [NSString stringWithFormat:@"landscape: Clock above the Dock, not marked (%@)", R(Frame(kClock))]);
    CGRect clockL = CGRectMake(376, 601, 615, 423);   // (dragged down: its bottom on the screen's bottom edge, 76 pt under the Dock's line)
    Put(kClock, clockL); [gSMBehindDock addObject:kClock];   // (the drop's record, -dm_pan: -- tools/test-smdropdock.sh)
    Still();
    Expect(Near([gSMTurnFrames[kClock][@"L"] CGRectValue], clockL), [NSString stringWithFormat:@"the landscape place noted is the one behind the Dock (%@)", R([gSMTurnFrames[kClock][@"L"] CGRectValue])]);
    Turn(kPort);
    Expect(Near(Frame(kClock), clockP), [NSString stringWithFormat:@"portrait: Clock back where it was in portrait (%@)", R(Frame(kClock))]);
    Expect(Behind(kClock), @"portrait: Clock keeps its behind-the-Dock mark (the turn put it back where the user had it)");
    Expect(Near(Frame(kSettings), TLayout(@"left", DMUsableArea())) && !Behind(kSettings), [NSString stringWithFormat:@"portrait: Settings in its layout, not marked (%@)", R(Frame(kSettings))]);
    Turn(kLand);
    CGRect back = Frame(kClock);
    Expect(Near(back, clockL), [NSString stringWithFormat:@"landscape again: Clock back behind the Dock where the user left it, %@ (want %@; the A12Z had 525..948)", R(back), R(clockL)]);
    Expect(CGRectGetMaxY(back) > landDock + 4.0, [NSString stringWithFormat:@"  ... its bottom %.1f under the Dock's line %.0f", CGRectGetMaxY(back), landDock]);
    Expect(Behind(kClock), @"  ... and still marked: its stage area keeps reaching the screen's bottom");
    Expect(Near(Asked(kClock), clockL), [NSString stringWithFormat:@"  ... the request asked for that place after its own fit (%@)", R(Asked(kClock))]);
    Expect(Has(LogWith(@"back where they were in this shape:"), @"back where they were in this shape: com.apple.mobiletimer/6A1F0C2E {{376, 601}, {615, 423}}"), [NSString stringWithFormat:@"  ... logged as back where it was: %@", LogWith(@"the iPad turned: windows back") ?: @"(none)"]);
    Expect(Has(LogWith(@"behind the Dock as the user left them"), @"behind the Dock as the user left them (down to the screen's bottom): com.apple.mobiletimer/6A1F0C2E {{376, 601}, {615, 423}}"), [NSString stringWithFormat:@"  ... logged as kept behind the Dock: %@", LogWith(@"behind the Dock as the user left") ?: @"(none)"]);
    Expect(Near(Frame(kSettings), TLayout(@"left", DMUsableArea())) && !Behind(kSettings), @"  ... Settings in its landscape layout, not marked");
    Expect(Near([gSMTurnFrames[kClock][@"L"] CGRectValue], clockL), [NSString stringWithFormat:@"  ... the landscape note keeps the place behind the Dock (turninfo; the A12Z kept {{376,525}}): %@", R([gSMTurnFrames[kClock][@"L"] CGRectValue])]);
    Turn(kPort); Turn(kLand);
    Expect(Near(Frame(kClock), clockL) && Behind(kClock), [NSString stringWithFormat:@"a second round trip: the same, behind the Dock and marked (%@)", R(Frame(kClock))]);

    printf("-- 2. the A12Z's M4 step 4, on from step 3: nudged up 29 pt, still under the Dock (the drop keeps the mark), then turned and back\n");
    CGRect nudged = CGRectMake(376, 572, 615, 423);   // (bottom 995: under the Dock's line by 47 pt)
    Put(kClock, nudged); [gSMBehindDock addObject:kClock];   // (the drop's record: 995 > 948 - 2 + 4)
    Still();
    Turn(kPort);
    Expect(Near(Frame(kClock), clockP) && Behind(kClock), [NSString stringWithFormat:@"portrait: back where it was in portrait, marked still (%@)", R(Frame(kClock))]);
    Turn(kLand);
    Expect(Near(Frame(kClock), nudged) && Behind(kClock), [NSString stringWithFormat:@"landscape again: at %@ under the Dock, marked (want %@; the A12Z had 525..948)", R(Frame(kClock)), R(nudged)]);
    printf("-- 2b. the same nudge with no portrait place noted (Stage Manager's own portrait place, inside the desktop)\n");
    Fresh(kLand);
    Put(kClock, nudged); [gSMBehindDock addObject:kClock];
    Still();
    Turn(kPort);
    Expect(Behind(kClock) && CGRectGetMaxY(Frame(kClock)) <= portDock + 0.5, [NSString stringWithFormat:@"portrait: left where Stage Manager put it, marked still (%@)", R(Frame(kClock))]);
    Turn(kLand);
    Expect(Near(Frame(kClock), nudged) && Behind(kClock), [NSString stringWithFormat:@"landscape again: at %@ under the Dock, marked (want %@)", R(Frame(kClock)), R(nudged)]);

    printf("-- 3. behind the Dock with no place noted in the new shape (Stage Manager's own place lies past the screen's bottom), beside a window that is not behind it\n");
    Fresh(kPort);
    CGRect tipsP = CGRectMake(204.5, 1000, 615, 366);   // (portrait, its bottom on the screen's bottom edge: behind the portrait Dock)
    CGRect filesP = CGRectMake(204.5, 950, 615, 350);   // (portrait, its bottom 3.6 pt above the Dock: not behind it)
    Put(kTips, tipsP); [gSMBehindDock addObject:kTips];
    Put(kFiles, filesP);
    Still();
    Turn(kLand);
    CGRect tl = Frame(kTips), fl = Frame(kFiles);
    Expect(fabs(CGRectGetMaxY(tl) - 1024.0) < 1.0 && CGRectGetMinY(tl) >= 37.0 - 0.5 && fabs(tl.size.height - 366) < 1.0, [NSString stringWithFormat:@"Tips kept inside the screen down to its bottom edge, its size kept: %@ (before: lifted to 582..948)", R(tl)]);
    Expect(Behind(kTips), @"  ... still behind the Dock, marked");
    Expect(fabs(CGRectGetMaxY(fl) - landDock) < 1.0 && fabs(fl.size.height - 350) < 1.0 && !Behind(kFiles), [NSString stringWithFormat:@"Files (not behind the Dock) left partly under the Dock by the turn: lifted above it as before, %@", R(fl)]);
    Turn(kPort);
    Expect(Near(Frame(kTips), tipsP) && Behind(kTips), [NSString stringWithFormat:@"back to portrait: Tips where it was, behind the portrait Dock (%@)", R(Frame(kTips))]);
    Expect(Near(Frame(kFiles), filesP) && CGRectGetMaxY(Frame(kFiles)) <= portDock + 0.5, [NSString stringWithFormat:@"  ... Files where it was in portrait (%@)", R(Frame(kFiles))]);

    printf("-- 3b. as before: a window that is not behind the Dock, alone, left partly under the Dock by the turn: the turn itself lifts it above the Dock\n");
    Fresh(kPort);
    Put(kFiles, filesP);
    Still();
    gRequests = 0;
    Turn(kLand);
    Expect(fabs(CGRectGetMaxY(Frame(kFiles)) - landDock) < 1.0 && gRequests == 1 && !Behind(kFiles), [NSString stringWithFormat:@"Files asked for above the Dock: %@ (%d request)", R(Frame(kFiles)), gRequests]);

    printf("-- 3c. behind the Dock, alone, and Stage Manager's own place after the turn is behind the new Dock inside the screen: left there, not asked for\n");
    Fresh(kPort);
    CGRect lowP = CGRectMake(204.5, 1008, 615, 300);   // (portrait: its bottom at 1308, under the portrait Dock's line)
    Put(kTips, lowP); [gSMBehindDock addObject:kTips];
    Still();
    gRequests = 0;
    Turn(kLand);
    CGRect lowL = Frame(kTips);
    Expect(CGRectGetMaxY(lowL) > landDock + 4.0 && CGRectGetMaxY(lowL) <= 1024.0 + 0.5 && Behind(kTips), [NSString stringWithFormat:@"Tips where Stage Manager put it, behind the landscape Dock: %@", R(lowL)]);
    Expect(gRequests == 0, [NSString stringWithFormat:@"  ... inside its desktop (down to the screen's bottom): not asked for (%d request(s); each one holds SpringBoard's main thread)", gRequests]);

    printf("-- 4. as before: a layout the user chooses (Window > Left) or Centre takes the mark, and the turn keeps such a window above the Dock\n");
    Fresh(kLand);
    Put(kClock, clockL); [gSMBehindDock addObject:kClock];
    Still();
    DMSMApplyLayouts(@{kClock: @"left"});
    Expect(!Behind(kClock) && Near(Frame(kClock), TLayout(@"left", DMUsableArea())), [NSString stringWithFormat:@"Window > Left: in the left half, no longer marked (%@)", R(Frame(kClock))]);
    Still(); Turn(kPort); Turn(kLand);
    Expect(!Behind(kClock) && Near(Frame(kClock), TLayout(@"left", DMUsableArea())), [NSString stringWithFormat:@"  ... after a turn and back: in its layout, not marked (%@)", R(Frame(kClock))]);
    Fresh(kLand);
    Put(kClock, clockL); [gSMBehindDock addObject:kClock];
    Still();
    CGRect centred = CGRectMake(375.5, 281, 615, 423);
    DMSMApplyPlacesIn(@{kClock: [NSValue valueWithCGRect:centred]}, gStage);   // (Window > Centre, the window keys' way)
    Expect(!Behind(kClock) && Near(Frame(kClock), centred), [NSString stringWithFormat:@"Centre: centred, no longer marked (%@)", R(Frame(kClock))]);
    Still(); Turn(kPort);
    CGRect cp = Frame(kClock);
    Expect(!Behind(kClock) && CGRectGetMaxY(cp) <= portDock + 0.5, [NSString stringWithFormat:@"  ... portrait: above the Dock, not marked (%@)", R(cp)]);
    Turn(kLand);
    Expect(!Behind(kClock) && Near(Frame(kClock), centred), [NSString stringWithFormat:@"  ... landscape again: back at its centred place (%@)", R(Frame(kClock))]);

    printf("-- 5. as before: a window the turn puts back into its layout is in no place behind the Dock (a mark on it goes)\n");
    Fresh(kLand);
    Put(kSettings, TLayout(@"right", DMUsableArea())); [gSMBehindDock addObject:kSettings];   // (a mark left from a drop that snapped into the half)
    Put(kClock, clockL); [gSMBehindDock addObject:kClock];
    Still();
    Turn(kPort);
    Expect(Near(Frame(kSettings), TLayout(@"right", DMUsableArea())) && !Behind(kSettings), [NSString stringWithFormat:@"Settings back in its right half, its mark gone (%@)", R(Frame(kSettings))]);
    Expect(Behind(kClock), @"  ... Clock, at a place of its own, keeps its mark");
    Turn(kLand);
    Expect(Near(Frame(kClock), clockL) && Behind(kClock) && !Behind(kSettings), [NSString stringWithFormat:@"  ... landscape again: Clock behind the Dock (%@), Settings not marked", R(Frame(kClock))]);

    printf("-- 6. the title bar's Fill and Back, then Zoom and Back (1.8.7.5): back behind the Dock where the user left it, with its mark, also after a turn\n");
    for (int z = 0; z < 2; z++) {
        Fresh(kLand);
        gTitleDoubleTap = z ? kMSBDTitleZoom : kMSBDTitleFill; gSMWinZoom = nil;
        Put(kClock, clockL); [gSMBehindDock addObject:kClock];
        Still();
        DMTitleTapSMWindow(kClock, @"test double tap");
        Expect(!Behind(kClock) && CGRectGetMaxY(Frame(kClock)) <= landDock + 0.5, [NSString stringWithFormat:@"%@: above the Dock, no longer marked (%@)", z ? @"Zoom" : @"Fill", R(Frame(kClock))]);
        Still();
        gRequests = 0;
        DMTitleTapSMWindow(kClock, @"test double tap");
        Expect(Near(Frame(kClock), clockL), [NSString stringWithFormat:@"  ... Back: where the user left it behind the Dock, %@ (want %@; before: lifted to 525..948, the other engines' place)", R(Frame(kClock)), R(clockL)]);
        Expect(Behind(kClock), @"  ... marked again: its stage area reaches the screen's bottom");
        Expect(gRequests == 1 && Near(Asked(kClock), clockL), [NSString stringWithFormat:@"  ... the request asked for that place after its own fit (%@)", R(Asked(kClock))]);
        Expect(Has(LogWith(@"[titlebar] test double tap"), @"behind the Dock again as the user left it"), [NSString stringWithFormat:@"  ... logged: %@", LogWith(@"[titlebar] test double tap") ?: @"(none)"]);
        Still(); Turn(kPort); Turn(kLand);
        Expect(Near(Frame(kClock), clockL) && Behind(kClock), [NSString stringWithFormat:@"  ... after a turn and back: still there, marked (%@)", R(Frame(kClock))]);
    }
    Fresh(kLand);
    gTitleDoubleTap = kMSBDTitleFill; gSMWinZoom = nil;
    CGRect free1 = CGRectMake(376, 200, 615, 423);
    Put(kClock, free1);
    Still();
    DMTitleTapSMWindow(kClock, @"test double tap"); Still(); DMTitleTapSMWindow(kClock, @"test double tap");
    Expect(Near(Frame(kClock), free1) && !Behind(kClock), [NSString stringWithFormat:@"as before: a window above the Dock, Fill and Back: at its place, not marked (%@)", R(Frame(kClock))]);

    printf("-- 7. the Window menu's Centre takes the mark (1.8.7.5), as Window > Left and the window keys' Centre do (scenario 4)\n");
    Fresh(kPort);
    CGRect clockPBehind = CGRectMake(204.5, 943, 615, 423);   // (portrait, dragged down: its bottom on the screen's bottom edge, under the portrait Dock)
    Put(kClock, clockPBehind); [gSMBehindDock addObject:kClock];
    Still();
    Turn(kLand);
    Expect(Behind(kClock), [NSString stringWithFormat:@"landscape: marked still (%@)", R(Frame(kClock))]);
    gFrontKey = kClock;
    TWindowLayoutSM(@"center", @"com.apple.mobiletimer");
    Expect(!Behind(kClock) && Near(Frame(kClock), TLayout(@"center", DMUsableArea())), [NSString stringWithFormat:@"Window > Centre: centred, no longer marked (%@)", R(Frame(kClock))]);
    Still();
    Turn(kPort);
    CGRect pc = Frame(kClock);
    Expect(CGRectGetMaxY(pc) <= portDock + 0.5 && !Behind(kClock), [NSString stringWithFormat:@"  ... portrait: its portrait place kept above the Dock, as for any window (%@; before: back behind the portrait Dock, still marked)", R(pc)]);
    Fresh(kPort);
    Put(kClock, clockPBehind); [gSMBehindDock addObject:kClock];
    Still();
    gFrontKey = kClock; gTNotPlaced = YES;
    TWindowLayoutSM(@"center", @"com.apple.mobiletimer");
    gTNotPlaced = NO;
    Expect(Behind(kClock) && Near(Frame(kClock), clockPBehind), [NSString stringWithFormat:@"a Window menu place not placed (not in the stage): left where it is, still marked (%@; round 1: the mark taken first)", R(Frame(kClock))]);

    printf("%s: %d checks, %d failed\n", fails ? "test-smturnbehind FAILED" : "test-smturnbehind: all pass", checks, fails);
    return fails > 98 ? 98 : fails;
} }
