// test-fitminimized-sm.m -- Mac test of KT's decision A (19 Nov, 1.8.8 H2) on our Stage Manager engine: the arrangement's minimized windows keep
// their tiles (DMSMFitKeptAway), in the launch's open-in-tile (DMSMAddToStage's plan block as written, KJoinPlan / KJoinAfter) and at Fit's look
// (DMSMFitTick). Aerial, Zetsu and MilkyWay4: test-fitminimized.m. Rows of p03:
//  - C15 on the A12Z (Home Minimizes Windows off): Settings and Clock as halves, Clock's green, Home (Clock sent to the background, counted as
//    minimized), App Store from the Dock, Clock from the Dock. Before: App Store took the pair with Settings and Clock's Dock icon was asked where it
//    goes. Now: App Store takes the left half, Settings the top right quarter, Clock keeps the bottom right one for its return: no question, three tiles.
//  - C15 on the 17.5 (Home Minimizes Windows on): Settings minimized too, Maps opened alone, Clock from the Dock: Maps joins, Settings keeps a tile.
//  - C14 on the 17.5: three tiles, Clock full screen, Home, Clock back by its green, Safari from the Dock. Before: Safari the left half, Clock the
//    right one, Settings' tile gone, then the question for Settings. Now: Safari back top right, Settings left kept, no question.
//  - a window opened some other way (Fit's look), counters (no window of the arrangement on screen: a new set; G1's full screen out of sight kept as
//    its way back, not as a tile; another desktop's or a closed window not kept).
//  - R2 of p07 on the iPad 2 (20 Nov): Stage Manager's own Close (or ours) lays the windows left out in its own transition (DMSMPlacesInClose as
//    written, with a stand-in context), before Fit's look. Four tiles, Clock minimized, App Store closes. Before: the plan had the windows on screen
//    only, Clock's tile went and its Dock icon was asked where it goes. Now: Settings left, Safari top right, Clock keeps the bottom right (FitPlan.h's
//    close-up rule, as on Zetsu), and comes back into it; the counters as before (none minimized, the minimized window's own app quits, O1 with
//    one and two minimized, a regular window over the tiles, a new pair after every tile minimized, Fit off, the TV).
// Fit's code is cut out of statusbar/StatusBar.x by test-fitminimized.sh into fms-real.inc, with the real SMFitPlan.h, FitPlan.h, SMWindowKey.h
// and common/AppWindowSize.h; SpringBoard's stages are stand-ins (test-smfitfullaway.m's: a stage is window key -> full screen, interaction time).
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include "../statusbar/SMFitPlan.h"
#include "../common/AppWindowSize.h"

static NSMutableArray<NSString *> *gKLog, *gKMarks, *gKAsked;
static NSMutableArray<NSDictionary *> *gKApplied;
static void DMLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DM_FEATURE_MARK(name) [gKMarks addObject:@name]
#define DMTestFlag(path) 0
@class UIView;
static NSMutableDictionary *gSidePromptCtx;
static NSMutableDictionary<NSString *, NSString *> *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows, *gSMFitLoose, *gSMFitWentFull;
static NSMutableDictionary<NSString *, NSNumber *> *gSMFitPending;
static NSDictionary<NSString *, NSString *> *gSMFitSlotsBeforeFull;
static NSMutableDictionary<NSString *, NSDictionary *> *gSMFitByDesk;
static NSMutableArray<NSString *> *gSMFitByDeskOrder;
static NSArray<NSString *> *gSMFitAdopt;
static CFTimeInterval gSMFitAdoptUntil;
static BOOL gMSWSwitching = NO, gNewWindowsFill = NO, gSMSkipFitAsk = NO, gSMFitLookAgain = NO, gKFitOff = NO;
static unsigned gSMTurns;
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@property (nonatomic) CGRect bounds;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; if (!s) { s = [UIScreen new]; s.bounds = CGRectMake(0, 0, 1366, 1024); } return s; }
@end
static NSString *NSStringFromCGSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
// ---- SpringBoard's stages: each a dictionary window key -> @{full, t}, a new object at every change; the iPad's first, "tv:" stages on the TV
static NSArray<NSDictionary *> *gKStages;
static NSMutableSet<NSString *> *gKMin, *gKTV;
static NSArray *DMSMRecentStages(void) { return gKStages; }
static id DMSMFrontStage(void) { return gKStages.firstObject; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[NSDictionary class]] ? stage : nil; }
static id DMSMStageDisplayIdentity(id stage) { for (NSString *k in (NSDictionary *)stage) if ([gKTV containsObject:k]) return @"tv"; return stage ? @"main" : nil; }
static BOOL DMSMIsMainIdentity(id identity) { return [identity isEqual:@"main"]; }
static NSString *DMSMItemKey(id item) { return item; }
static BOOL DMSMAttrsFullScreen(id attrs) { return [attrs[@"full"] boolValue]; }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { NSNumber *t = attrs[@"t"]; return t ? t.longLongValue : dflt; }
static NSString *KFrontKey(void) {
    NSDictionary *m = DMSMFrontStage(); NSString *best = nil; long long t = LLONG_MIN;
    for (NSString *k in m) if (DMSMAttrTimeOr(m[k], 0) > t) { t = DMSMAttrTimeOr(m[k], 0); best = k; }
    return best;
}
static NSString *DMFrontApp(void) { return DMSMKeyBundle(KFrontKey()); }
static BOOL DMSMFrontIsFullScreen(void) { NSString *k = KFrontKey(); return k && DMSMAttrsFullScreen(((NSDictionary *)DMSMFrontStage())[k]); }
static NSArray<NSString *> *DMSMWindowKeys(void) {
    NSMutableArray *a = [NSMutableArray array]; NSDictionary *m = DMSMFrontStage();
    for (NSString *k in m) if (!DMSMAttrsFullScreen(m[k])) [a addObject:k];
    return a;
}
static BOOL DMSMIsMinimized(NSString *key) { return DMSMKeySetHas(gKMin, key); }
static BOOL DMSMEngine(void) { return YES; }
static BOOL DMFitEnabled(void) { return !gKFitOff; }
static BOOL DMSMWorkspaceBusy(void) { return NO; }
static BOOL DMSMTurnSettling(void) { return NO; }
static BOOL DMSMSpotlightHolds(void) { return NO; }
static BOOL DMSwitcherVisible(void) { return NO; }
static BOOL DMSMGestureLive(void) { return NO; }
static void DMTitleRecordSMPlan(NSDictionary *plan, id stage) { }
static BOOL DMSMApplyLayoutsIn(NSDictionary<NSString *, NSString *> *plan, id stage) { [gKApplied addObject:[plan copy]]; return YES; }
static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *plan, id stage) { [gKApplied addObject:[plan copy]]; return YES; }
static void DMSMBringToFront(NSString *key) { }
static id DMSMNoFitPlace(id stage) { return @"center"; }
static void DMPromptForSideApply(UIView *stage, NSString *newBundle, NSString *leftBundle, NSString *rightBundle, void (^apply)(NSString *side)) { [gKAsked addObject:newBundle ?: @"?"]; }
static BOOL DMSMFitWindowsInTilesNow(NSArray<NSString *> *keys) { return NO; }
static NSArray<NSString *> *DMSMFitWindowsSittingInTiles(NSArray<NSString *> *keys) { return @[]; }
static NSDictionary<NSString *, NSString *> *DMSMFitTilesFromPlaces(NSDictionary *map, NSArray *items, NSArray<NSString *> *keys) { return nil; }
static int DMAppSizeOf(NSString *bundle) { return 0; }
static BOOL DMSMOpensAtOwnSize(NSString *key) { return NO; }
// ---- the join's request (DMSMAddToStage): a window's attributes laid out in a tile, its entity and role
static id DMSMAttrsForLayoutIn(id attrs, NSString *slot, id stage) { return slot ? @{@"slot": slot} : nil; }
static id DMSMEntityForStageItem(id stage, id item) { return item; }
static long long DMSMRoleOr(id stage, id item, long long dflt) { return 1; }
// ---- Stage Manager's own Close (DMSMPlacesInClose, cut with DMSMItemFor): a transition context naming the windows that stay in their roles, the
//      ones going in its removal list and the stage on screen before it; an entity is a window key; the attributes written for each window kept
@interface KCloseCtx : NSObject
@property (nonatomic, copy) NSArray *removals;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *roles;
@property (nonatomic, strong) id before;
@property (nonatomic, strong) NSMutableDictionary *written;
@end
@implementation KCloseCtx
- (id)entitiesWithRemovalContexts { return self.removals; }
- (void)setRequestedLayoutAttributes:(id)attrs forEntity:(id)entity { if (!self.written) self.written = [NSMutableDictionary dictionary]; self.written[entity] = attrs; }
@end
static BOOL DMSMCtxIsOurs(id ctx) { return NO; }
static NSString *DMSMSigObj(void) { return @"@"; }
static BOOL DMSMSigOK(id obj, SEL sel, NSString *want, const char *what) { return [obj respondsToSelector:sel]; }
static id DMSMStageShownBefore(id ctx) { return ((KCloseCtx *)ctx).before; }
static BOOL DMSMIsEntity(id e) { return [e isKindOfClass:[NSString class]]; }
static NSString *DMSMEntityKey(id entity) { return entity; }
static long long DMSMRoleTop(void) { return 4; }
static id DMSMCtxEntityForRole(id ctx, long long role, BOOL *ok) { if (ok) *ok = YES; return ((KCloseCtx *)ctx).roles[@(role)]; }
static BOOL DMSMCtxCanWrite(id ctx) { return YES; }
static void DMSMAPIFail(NSString *what, NSString *why) { DMLog([NSString stringWithFormat:@"[smapi] %@: %@", what, why]); }

#include "fms-real.inc"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) {
    gChecks++; if (!ok) gFails++;
    printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) printf("      tiles %s; asked %s; last layout %s\n", [gSMFitSlots.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String,
                    [gKAsked componentsJoinedByString:@", "].UTF8String, [gKApplied.lastObject.description stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String);
}
static BOOL Logged(NSString *part) { for (NSString *l in gKLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }
static NSArray *E(NSString *k, long long t) { return @[k, @NO, @(t)]; }
static NSArray *EF(NSString *k, long long t) { return @[k, @YES, @(t)]; }
static NSDictionary *Stage(NSArray<NSArray *> *wins) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSArray *w in wins) m[w[0]] = @{@"full": w[1], @"t": w[2]};
    return [m copy];
}
static void Stages(NSArray<NSDictionary *> *s) { gKStages = [s copy]; }
static void Clear(void) { gKLog = [NSMutableArray array]; gKMarks = [NSMutableArray array]; gKAsked = [NSMutableArray array]; gKApplied = [NSMutableArray array]; }
static void Tick(void) { DMSMFitTick(NO); }
static void Reset(NSDictionary *slots, NSArray<NSDictionary *> *stages) {
    gKFitOff = YES; DMSMFitTick(NO); gKFitOff = NO;
    gSMFitSlots = [slots mutableCopy]; gSMFreeWindows = [NSMutableSet set]; gSMFitLoose = nil; gSMFitWentFull = nil; gSMFitSlotsBeforeFull = nil;
    gSMFitByDesk = nil; gSMFitByDeskOrder = nil; gSMFitPending = nil; gKMin = [NSMutableSet set]; gKTV = [NSMutableSet set];
    Stages(stages); Clear(); Tick(); Clear();
}
static BOOL Laid(NSDictionary *want) { return [gKApplied.lastObject isEqualToDictionary:want]; }
static BOOL Tiles(NSDictionary *want) { return [gSMFitSlots isEqualToDictionary:want]; }
// An icon tapped in the Dock with the desktop on screen (DMSMAddToStage on the iPad, apps opening as windows): the question before the launch
// (DMSMFitAsksAbout), then the open-in-tile as written -- the plan, the request's tiles (who is laid out where), the arrangement it leaves
static NSDictionary *gKJoinLaid;
static BOOL Join(NSString *key) {
    NSDictionary *map = DMSMFrontStage();
    NSString *l = nil, *r = nil;
    if (DMSMFitAsksAbout(DMSMKeyBundle(key), map.allKeys, &l, &r)) { [gKAsked addObject:key]; return NO; }
    DMSMFitForgetClosed(key);
    NSDictionary *fitPlan = nil;
    NSMutableArray *addPlan = KJoinPlan(DMSMKeyBundle(key), key, map, map, @{@"own": @YES}, key, 7, &fitPlan);
    NSMutableDictionary *laid = [NSMutableDictionary dictionary];
    for (NSArray *e in addPlan) laid[e[0]] = e[2][@"slot"] ?: @"own";
    gKJoinLaid = laid;
    KJoinAfter(key, fitPlan, addPlan.count);
    [gKMin removeObject:key];   // (DMSMSetMinimized(newKey, NO))
    return YES;
}
// Stage Manager's own Close (also ours, which asks for it; the iPad 2's R2 and R2sb of p07) with the stage on screen before it in front: the
// context's transition (DMSMPlacesInClose as written) -- the windows of that stage that stay are in its roles, the ones going (going) in its removal
// list --; what it wrote for each window (its tile, or "own": as it is); then SpringBoard's stages after it, every window that went in none
static NSDictionary *gKCloseWrote;
static void Close(NSArray<NSString *> *going, BOOL rolesReversed) {
    NSDictionary *front = DMSMFrontStage();
    NSMutableArray<NSString *> *stay = [NSMutableArray array];
    for (NSString *k in front) if (![going containsObject:k]) [stay addObject:k];
    [stay sortUsingSelector:@selector(compare:)];
    if (rolesReversed) stay = [[[stay reverseObjectEnumerator] allObjects] mutableCopy];
    NSMutableDictionary<NSNumber *, NSString *> *roles = [NSMutableDictionary dictionary];
    long r = 1;
    for (NSString *k in stay) roles[@(r++)] = k;
    KCloseCtx *c = [KCloseCtx new]; c.removals = going; c.roles = roles; c.before = front;
    DMSMPlacesInClose(c);
    NSMutableDictionary *wrote = [NSMutableDictionary dictionary];
    for (NSString *k in c.written) wrote[k] = c.written[k][@"slot"] ?: @"own";
    gKCloseWrote = wrote;
    NSMutableArray<NSDictionary *> *after = [NSMutableArray array];
    for (NSDictionary *st in gKStages) {
        NSMutableDictionary *m = [st mutableCopy]; [m removeObjectsForKeys:going];
        if (m.count || !st.count) [after addObject:[m copy]];
    }
    Stages(after);
    for (NSString *k in going) [gKMin removeObject:k];
}
static BOOL Wrote(NSDictionary *want) { return [gKCloseWrote isEqualToDictionary:want]; }

#define K(app) @"com.apple." app "|sceneID:com.apple." app "-default"
int main(void) {
    @autoreleasepool {
        NSString *A = K("Preferences"), *B = K("mobilesafari"), *C = K("mobilenotes"), *D = K("Maps"), *F = K("mobiletimer"), *S = K("AppStore"), *T = K("tips");
        NSDictionary *three = @{S: @"left", A: @"topright", F: @"bottomright"};

        // C15, A12Z (Home Minimizes Windows off): Settings left, Clock right; Clock's green; Home: Clock to the background (counted as minimized),
        // Settings stays on screen; App Store from the Dock; Clock from the Dock
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(F, 3)])]); Tick();   // (Clock's green)
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(F, 3)])]); Tick();   // (Home)
        Check(Tiles(@{A: @"left", F: @"right"}) && Logged(@"1 minimized window(s) keep their tiles -- the 1 on screen keep theirs"), @"C15 (Home Minimizes Windows off): Home sends Clock to the background, counted as minimized: the tiles kept (unchanged)");
        Clear(); Join(S); Stages(@[Stage(@[E(A, 4), E(S, 5)]), Stage(@[EF(F, 3)])]); Tick();
        Check(!gKAsked.count && Tiles(three) && [gKJoinLaid isEqualToDictionary:@{S: @"left", A: @"topright"}] && Logged(@"opens in its tile (left), 2 window(s) tiled in the same transition -- 1 minimized window(s) keep their tiles"),
              @"C15 (Home Minimizes Windows off): App Store from the Dock: no question, it takes the left half and Settings the top right quarter in one transition; Clock keeps a tile (the bottom right one)");
        Check(Laid(@{S: @"left", A: @"topright"}) && Logged(@"1 minimized window(s) keep their tiles -- the 2 on screen keep theirs"), @"C15 ... Fit's next look: the tiles kept, Clock's empty for its return");
        Clear();
        BOOL joined = Join(F);
        Check(joined && !gKAsked.count, @"C15 ... Clock's Dock icon: no question (before: \"Where should Clock go?\")");
        Stages(@[Stage(@[E(A, 4), E(S, 5), E(F, 6)])]); Tick();
        Check(Tiles(three) && [gKJoinLaid isEqualToDictionary:three] && Laid(three) && Logged(@"back from full screen -- its tile again") && !gKAsked.count,
              @"C15 ... Clock back into its tile (the bottom right quarter): three tiles, its tile again");

        // C15, 17.5 (Home Minimizes Windows on): Settings left, Clock right; Clock's green; Home: Settings minimized, Clock to the background; Maps
        // opened from the Home Screen's Dock (alone, a stage of its own); Clock from the Dock; Settings from the Dock
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(F, 3)])]); Tick();
        [gKMin addObjectsFromArray:@[A, F]]; Stages(@[Stage(@[]), Stage(@[E(A, 1)]), Stage(@[EF(F, 3)])]); Tick();
        Stages(@[Stage(@[E(D, 4)]), Stage(@[E(A, 1)]), Stage(@[EF(F, 3)])]); Clear(); Tick();
        Check(Tiles(@{A: @"left", F: @"right"}) && !gKApplied.count && !gKAsked.count, @"C15 (Home Minimizes Windows on): Maps opened alone: nothing tiled, the arrangement kept (unchanged)");
        Clear(); Join(F); Stages(@[Stage(@[E(D, 4), E(F, 5)]), Stage(@[E(A, 1)])]); Tick();
        Check(!gKAsked.count && Tiles(@{D: @"left", A: @"topright", F: @"bottomright"}) && [gKJoinLaid isEqualToDictionary:@{D: @"left", F: @"bottomright"}],
              @"C15 (Home Minimizes Windows on): Clock from the Dock: Maps joins as a new window (the left half), Clock in the bottom right quarter, Settings keeps a tile (the top right one)");
        Clear();
        joined = Join(A);
        Stages(@[Stage(@[E(D, 4), E(F, 5), E(A, 6)])]); Tick();
        Check(joined && !gKAsked.count && Tiles(@{D: @"left", A: @"topright", F: @"bottomright"}) && [gKJoinLaid isEqualToDictionary:@{D: @"left", A: @"topright", F: @"bottomright"}],
              @"C15 ... Settings from the Dock: into its tile, no question (before: the third window's question)");

        // C14, 17.5: Settings left, Safari top right, Clock bottom right; Clock's green; Home (all three minimized); Clock from the Home Screen's Dock
        // (full screen); Clock's green (back in its tile); Safari from the Dock; Settings from the Dock
        NSDictionary *c14 = @{A: @"left", B: @"topright", F: @"bottomright"};
        Reset(c14, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        Stages(@[Stage(@[E(A, 1), E(B, 2), EF(F, 4)])]); Tick();
        [gKMin addObjectsFromArray:@[A, B, F]]; Stages(@[Stage(@[]), Stage(@[E(A, 1)]), Stage(@[E(B, 2)]), Stage(@[EF(F, 4)])]); Tick();
        [gKMin removeObject:F]; Stages(@[Stage(@[EF(F, 5)]), Stage(@[E(A, 1)]), Stage(@[E(B, 2)])]); Tick();
        Stages(@[Stage(@[E(F, 6)]), Stage(@[E(A, 1)]), Stage(@[E(B, 2)])]); Clear(); Tick();
        Check(Tiles(c14) && Laid(@{F: @"bottomright"}), @"C14 (17.5): Clock back by its green, Settings and Safari minimized: Clock in its tile (unchanged)");
        Clear(); Join(B); Stages(@[Stage(@[E(F, 6), E(B, 7)]), Stage(@[E(A, 1)])]); Tick();
        Check(!gKAsked.count && Tiles(c14) && [gKJoinLaid isEqualToDictionary:@{B: @"topright", F: @"bottomright"}] && Laid(@{B: @"topright", F: @"bottomright"}),
              @"C14 (17.5): Safari from the Dock: back top right, Clock stays bottom right, Settings keeps the left half (before: Safari the left half, Clock the right one, Settings' tile gone)");
        Clear();
        joined = Join(A);
        Stages(@[Stage(@[E(F, 6), E(B, 7), E(A, 8)])]); Tick();
        Check(joined && !gKAsked.count && Tiles(c14) && [gKJoinLaid isEqualToDictionary:c14], @"C14 ... Settings from the Dock: into its tile, no question");

        // A window opened some other way (Spotlight, a link: Fit's look, no join): Settings on screen, Clock minimized by its yellow light
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Stages(@[Stage(@[E(A, 1), E(D, 3)]), Stage(@[E(F, 2)])]); Clear(); Tick();
        Check(!gKAsked.count && Tiles(@{D: @"left", A: @"topright", F: @"bottomright"}) && Laid(@{D: @"left", A: @"topright"}) && Logged(@"2 windows tiled -- 1 minimized window(s) keep their tiles"),
              @"Fit's look, Maps opened some other way next to Settings, Clock minimized: Maps the left half, Settings the top right, Clock keeps the bottom right; only the two on screen laid out");
        [gKMin removeObject:F]; Stages(@[Stage(@[E(A, 1), E(D, 3), E(F, 4)])]); Clear(); Tick();
        Check(!gKAsked.count && Tiles(@{D: @"left", A: @"topright", F: @"bottomright"}) && Laid(@{D: @"left", A: @"topright", F: @"bottomright"}), @"... Clock back: into its tile, no question");
        // ... four take part already (two on screen, two minimized): a window opened some other way is a regular window over them
        Reset(@{A: @"topleft", B: @"topright", C: @"bottomleft", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(C, 3), E(F, 4)])]);
        [gKMin addObjectsFromArray:@[C, F]]; Stages(@[Stage(@[E(A, 1), E(B, 2)]), Stage(@[E(C, 3)]), Stage(@[E(F, 4)])]); Tick();
        Stages(@[Stage(@[E(A, 1), E(B, 2), E(D, 5)]), Stage(@[E(C, 3)]), Stage(@[E(F, 4)])]); Clear(); Tick();
        Check(Tiles(@{A: @"topleft", B: @"topright", C: @"bottomleft", F: @"bottomright"}) && [gSMFitLoose containsObject:D] && Logged(@"four windows take part already"),
              @"... four tiles, two minimized: Maps opened some other way is a regular window over them, the four keep their tiles (as Aerial's \"four windows take part already\")");

        // Counters
        // No window of the arrangement among those laid out: Settings and Clock minimized, Maps then Tips open alone: a new set, the minimized tiles go
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        [gKMin addObjectsFromArray:@[A, F]]; Stages(@[Stage(@[]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Stages(@[Stage(@[E(D, 3)]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Clear(); Join(T); Stages(@[Stage(@[E(D, 3), E(T, 4)]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Check(Tiles(@{T: @"left", D: @"right"}) && [gKJoinLaid isEqualToDictionary:@{T: @"left", D: @"right"}] && !gKAsked.count,
              @"counter: every tiled window minimized, Maps alone, Tips from the Dock: the two tiled as a new set (as Aerial), no quarters for the minimized ones");
        // G1: a window full screen out of sight, not minimized: its way back kept, not a tile (Maps opens next to Settings: the pair)
        Reset(@{A: @"left", C: @"right"}, @[Stage(@[E(A, 1), E(C, 2)])]);
        Stages(@[Stage(@[E(A, 1), EF(C, 3)])]); Tick();
        Stages(@[Stage(@[E(A, 4)]), Stage(@[EF(C, 3)])]); Tick();
        Clear(); Join(D); Stages(@[Stage(@[E(A, 4), E(D, 5)]), Stage(@[EF(C, 3)])]); Tick();
        Check(gSMFitSlots.count == 2 && gSMFitSlots[A] && gSMFitSlots[D] && [gSMFitWentFull containsObject:C], @"counter (G1): Notes full screen out of sight, not minimized: Maps tiles with Settings, Notes keeps its way back (unchanged)");
        // The H2-H5 review, finding 2 (the reference for Aerial, Zetsu and MilkyWay4's R2 rows, unchanged here): four tiles, Clock minimized, Notes
        // closes: the two on screen and Clock close the tile up, each keeping its place; Clock keeps the bottom right for its return. (Fit's look
        // after a close it sees only there, DMSMFitForgetClosed; a close by Stage Manager's Close is laid out in its own transition first: below)
        Reset(@{A: @"topleft", B: @"topright", C: @"bottomleft", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(C, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1), E(B, 2), E(C, 3)]), Stage(@[E(F, 4)])]); Tick();
        Stages(@[Stage(@[E(A, 1), E(B, 2)]), Stage(@[E(F, 4)])]); Clear(); Tick();
        Check(Tiles(@{A: @"left", B: @"topright", F: @"bottomright"}) && Laid(@{A: @"left", B: @"topright"}),
              @"R2 (the reference): four tiles, Clock minimized, Notes closes: Settings the left half, Safari the top right, Clock keeps the bottom right");
        // ... and the same close by Stage Manager's own Close (or ours), which lays the windows left out in its own transition, before Fit's look
        // (DMSMPlacesInClose): R2 of p07 on the iPad 2 -- App Store top left, Settings bottom left, Safari top right, Clock bottom right; Clock's yellow;
        // App Store closed. Before: "2 window(s) left take their tiles in the same transition (left, right)", Clock's tile gone, its Dock icon asked
        NSDictionary *four = @{S: @"topleft", A: @"bottomleft", B: @"topright", F: @"bottomright"}, *r2 = @{A: @"left", B: @"topright", F: @"bottomright"};
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        Clear(); Close(@[S], NO);
        Check(Tiles(r2) && Wrote(@{A: @"left", B: @"topright"}) && Logged(@"a tiled window closes -- 2 window(s) left take their tiles in the same transition")
              && Logged(@"-- 1 minimized window(s) keep their tiles (com.apple.mobiletimer") && [gKMarks containsObject:@"sm-fit-in-close-keeps-minimized"],
              @"R2 (Stage Manager's own Close): four tiles, Clock minimized, App Store closes: Settings the left half, Safari the top right in the Close's transition, Clock keeps the bottom right");
        Clear(); Tick();
        Check(Tiles(r2) && Laid(@{A: @"left", B: @"topright"}) && Logged(@"1 minimized window(s) keep their tiles -- the 2 on screen keep theirs"),
              @"R2 ... Fit's next look: the tiles kept, Clock's empty for its return");
        Clear();
        joined = Join(F);
        Check(joined && !gKAsked.count && [gKJoinLaid isEqualToDictionary:r2], @"R2 ... Clock's Dock icon: into its tile (the bottom right quarter), no question");
        Stages(@[Stage(@[E(A, 2), E(B, 3), E(F, 5)])]); Clear(); Tick();
        Check(Tiles(r2) && !gKAsked.count, @"R2 ... then three tiles: Settings left, Safari top right, Clock bottom right");
        // ... R2sb: by our close (it asks for Stage Manager's Close: the same transition), Safari used last, the roles the other way round
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 4), E(F, 3)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 4)]), Stage(@[E(F, 3)])]); Tick();
        Clear(); Close(@[S], YES);
        Check(Tiles(r2) && Wrote(@{A: @"left", B: @"topright"}) && Logged(@"-- 1 minimized window(s) keep their tiles"), @"R2sb (our close): the same, Clock keeps the bottom right");
        Clear(); Tick(); Clear();
        joined = Join(F);
        Check(joined && !gKAsked.count && [gKJoinLaid isEqualToDictionary:r2], @"R2sb ... Clock's Dock icon: into its tile, no question");
        // ... the tile next to the minimized one closes: Clock grows into it while minimized, and comes back into the right half
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        Clear(); Close(@[B], NO);
        NSDictionary *r2b = @{S: @"topleft", A: @"bottomleft", F: @"right"};
        Check(Tiles(r2b) && Wrote(@{S: @"topleft", A: @"bottomleft"}), @"R2 (Stage Manager's own Close): four tiles, Clock minimized, Safari closes: App Store and Settings keep the left quarters, Clock's tile grows into the right half");
        Clear(); Tick(); Clear();
        joined = Join(F);
        Check(joined && !gKAsked.count && [gKJoinLaid isEqualToDictionary:r2b], @"R2 ... Clock's Dock icon: into the right half, no question");
        // ... Home Minimizes Windows off (H2 row 10's way): Clock full screen, Home sends it to the background (counted as minimized), App Store closes
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3), EF(F, 5)])]); Tick();
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 6), E(A, 7), E(B, 8)]), Stage(@[EF(F, 5)])]); Tick();
        Clear(); Close(@[S], NO);
        Check(Tiles(r2) && Wrote(@{A: @"left", B: @"topright"}), @"R2 (Home Minimizes Windows off): Clock sent to the background by Home, App Store closes: Clock keeps the bottom right");
        Clear(); Tick(); Clear();
        joined = Join(F);
        Stages(@[Stage(@[E(A, 7), E(B, 8), E(F, 9)])]); Tick();
        Check(joined && !gKAsked.count && Tiles(r2) && [gKJoinLaid isEqualToDictionary:r2] && Logged(@"back from full screen -- its tile again"), @"R2 (Home Minimizes Windows off) ... Clock's Dock icon: its tile again, no question");
        // Counters of the Close (as before): no window minimized; the minimized window's own app quits; one window left on screen (O1, also with
        // two minimized); a regular window over the tiles; every tile minimized then a new pair; Fit off; the TV's stage
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        Clear(); Close(@[S], NO);
        Check(Tiles(r2) && Wrote(r2) && !Logged(@"minimized window(s) keep their tiles ("), @"counter: four tiles, none minimized, App Store closes: the three close the tile up in the Close's transition (unchanged)");
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        Clear(); Close(@[F], NO);
        Check(Tiles(@{S: @"topleft", A: @"bottomleft", B: @"right"}) && Wrote(@{S: @"topleft", A: @"bottomleft", B: @"right"}) && !Logged(@"minimized window(s) keep their tiles ("),
              @"counter: four tiles, Clock minimized, Clock itself quits (its app quit with the desktop on screen): its tile goes, Safari grows into it (unchanged)");
        Reset(@{A: @"left", B: @"topright", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1), E(B, 2)]), Stage(@[E(F, 3)])]); Tick();
        Clear(); Close(@[B], NO);
        Check(Tiles(@{A: @"fill"}) && Wrote(@{A: @"fill"}) && Logged(@"1 window(s) left take their tiles in the same transition (fill)") && !Logged(@"minimized window(s) keep their tiles ("),
              @"counter (O1): three tiles, Clock minimized, Safari closes: Settings fills alone, Clock's tile goes (unchanged)");
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObjectsFromArray:@[B, F]]; Stages(@[Stage(@[E(S, 1), E(A, 2)]), Stage(@[E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        Clear(); Close(@[S], NO);
        Check(Tiles(@{A: @"fill"}) && Wrote(@{A: @"fill"}), @"counter (O1, two minimized): four tiles, Safari and Clock minimized, App Store closes: Settings fills alone (unchanged)");
        Reset(@{A: @"left", B: @"topright", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1), E(B, 2), E(D, 4)]), Stage(@[E(F, 3)])]);
        gSMFitLoose = [NSMutableSet setWithObject:D];
        Clear(); Close(@[B], NO);
        Check(Tiles(@{A: @"fill"}) && Wrote(@{A: @"fill", D: @"own"}) && Logged(@"1 regular window(s) over them keep their places"), @"counter: a regular window over the tiles keeps its place, one tiled window left on screen fills (O1, unchanged)");
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        [gKMin addObjectsFromArray:@[A, F]]; Stages(@[Stage(@[]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Stages(@[Stage(@[E(D, 3)]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Clear(); Join(T); Stages(@[Stage(@[E(D, 3), E(T, 4)]), Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Clear(); Close(@[T], NO);
        Check(Tiles(@{D: @"fill"}) && Wrote(@{D: @"fill"}), @"counter (H2 row 13): every tile minimized, Maps and Tips a new pair, Tips closes: Maps fills, the old minimized windows are not in this arrangement (unchanged)");
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        gKFitOff = YES; Clear(); Close(@[S], NO);
        Check(Wrote(@{A: @"own", B: @"own"}) && Logged(@"a window closes -- 2 window(s) left keep their own places and sizes") && !Logged(@"Fit to Window: a tiled window closes"), @"counter: Fit to Window off: each window left as it is (unchanged)");
        gKFitOff = NO;
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]); Tick();
        [gKTV addObject:S]; Clear(); Close(@[S], NO);
        Check(Tiles(four) && !gKCloseWrote.count && !gKLog.count, @"counter: a Close on the TV's stage: nothing written, the iPad's tiles as they were (unchanged)");
        [gKTV removeAllObjects];
        Reset(four, @[Stage(@[E(S, 1), E(A, 2), E(B, 3), E(F, 4)])]);
        [gKMin addObject:F]; [gKTV addObject:F]; Stages(@[Stage(@[E(S, 1), E(A, 2), E(B, 3)]), Stage(@[E(F, 4)])]);
        Clear(); Close(@[S], NO);
        Check(!gSMFitSlots[F] && Wrote(@{A: @"left", B: @"right"}), @"counter: a minimized window whose stage is on the TV keeps no tile here (as the join and Fit's look: DMSMFitMinimizedIn)");
        [gKTV removeAllObjects];
        // The H2-H5 review, finding 3 (the Mac Switcher): a tiled window dragged to another desktop (DMMSWSMMoveFinish's Fit block as written): the
        // tiles left close up by the rule of every close-up -- the arrangement's minimized windows (each in a hidden stage of its own) keep theirs
        Reset(@{A: @"topleft", B: @"topright", C: @"bottomleft", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(C, 3), E(F, 4)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1), E(B, 2), E(C, 3)]), Stage(@[E(F, 4)])]); Tick();
        Clear(); KSMMoveFit(C);
        Check(Tiles(@{A: @"left", B: @"topright", F: @"bottomright"}), @"R3 (Stage Manager): four tiles, Clock minimized, Notes dragged to another desktop: Settings left, Safari top right, Clock keeps the bottom right");
        Reset(@{A: @"left", F: @"right"}, @[Stage(@[E(A, 1), E(F, 2)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1)]), Stage(@[E(F, 2)])]); Tick();
        Clear(); KSMMoveFit(A);
        Check(Tiles(@{F: @"fill"}), @"R3 (Stage Manager): Settings and Clock, Clock minimized, Settings dragged away: Clock keeps the plan, at Fill for its return");
        Reset(@{A: @"left", B: @"topright", F: @"bottomright"}, @[Stage(@[E(A, 1), E(B, 2), E(F, 3)])]);
        [gKMin addObject:F]; Stages(@[Stage(@[E(A, 1), E(B, 2)]), Stage(@[E(F, 3)])]); Tick();
        Clear(); KSMMoveFit(B);
        Check(Tiles(@{A: @"fill"}), @"counter (O1, Stage Manager): three tiles, Clock minimized, Safari dragged away: Settings fills alone (unchanged)");
#ifdef K_HAS_MIN_IN
        Reset(@{A: @"left", F: @"right", B: @"bottomleft"}, @[Stage(@[E(A, 1)]), Stage(@[E(F, 2)]), Stage(@[E(B, 3)])]);
        [gKMin addObjectsFromArray:@[F, B]]; [gKTV addObject:B];
        Check([DMSMFitMinimizedIn(@[], gSMFitSlots) isEqualToArray:@[F]] && [DMSMFitMinimizedIn(@[F], gSMFitSlots) isEqualToArray:@[]] && [DMSMFitKeptAway(@[D], gSMFitSlots) isEqualToArray:@[]],
              @"DMSMFitMinimizedIn: the arrangement's minimized windows on the iPad, none of keys, with no window of it among keys too (DMSMFitKeptAway: none then)");
#endif
        // DMSMFitKeptAway: only minimized windows of the arrangement still in a stage of the iPad, with one of the windows laid out in it
#ifdef K_HAS_KEPT_AWAY
        Reset(@{A: @"left", F: @"right", B: @"bottomleft"}, @[Stage(@[E(A, 1)]), Stage(@[E(F, 2)]), Stage(@[E(B, 3)])]);
        [gKMin addObjectsFromArray:@[F, B]]; [gKTV addObject:B];
        Check([DMSMFitKeptAway(@[A], gSMFitSlots) isEqualToArray:@[F]], @"DMSMFitKeptAway: Clock minimized on the iPad kept; Safari minimized on the TV not");
        Stages(@[Stage(@[E(A, 1)])]);
        Check(DMSMFitKeptAway(@[A], gSMFitSlots).count == 0 && DMSMFitKeptAway(@[D], @{A: @"left", F: @"right"}).count == 0,
              @"DMSMFitKeptAway: a window in no stage (closed) not kept; none with no window of the arrangement among the keys");
#endif
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
