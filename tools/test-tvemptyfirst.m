// test-tvemptyfirst.m -- Mac test (Mac Catalyst) of the TV desktop's last window closing (1.8.8.2, B86): the TV goes to its own empty desktop and
// every app launch still works after. B86's first version took the window's stage out of Stage Manager's model first and then asked the TV for its
// empty desktop; SpringBoard began that transition from a layout state naming a stage no longer in its switcher's model and raised inside it ("Trying
// to add an icon overlay but the item container for this app layout doesn't exist"), and the transition it had begun never finished: from then on it
// refused every app launch anywhere until a SpringBoard restart (iPadOS 18.5, twice). Runs the REAL code, cut out by test-tvemptyfirst.sh into
// te-real.inc: DMSMWindowActionAs (statusbar/StatusBar.x) with the TV's close (DMSMTVEmptyFirst, DMSMTVTakeOut; in the code before the fix
// DMSMTVEmptyAfterLastWindow), the request (statusbar/MacSwitcherSM.h DMMSWSMRequestEmpty, DMMSWSMStateNamesGone), and statusbar/SMAfterHome.h
// whole (the end of SpringBoard's transitions, the TV's wait, the force quit's clean-up held). SpringBoard is a world model: the switcher's model
// (the stages), each display's settled layout state, a workspace whose transition raises -- and then refuses every later request and launch, as seen
// on iPadOS 18.5 -- when it begins from a state naming a stage the model no longer has, a transition in flight that queues a request, its end.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../statusbar/SMWindowKey.h"

#define DM_FEATURE_MARK(name) do { } while (0)
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s ?: @""]; }
static BOOL Logged(NSString *part) { for (NSString *l in gLog) if ([l rangeOfString:part].location != NSNotFound) return YES; return NO; }
static BOOL DMTestFlag(const char *path) { (void)path; return NO; }

// ---- the world ----
@interface KStage : NSObject
@property (nonatomic, strong) NSDictionary *map;   // (item -> attributes; an item is "item:<window key>")
@property (nonatomic, copy) NSString *ident;       // ("ipad" / "tv")
@end
@implementation KStage
@end
@interface KItem : NSObject <NSCopying>
@property (nonatomic, copy) NSString *key;
@end
@implementation KItem
- (NSString *)bundleIdentifier { return DMSMKeyBundle(self.key); }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[KItem class]] && [((KItem *)o).key isEqualToString:self.key]; }
- (NSUInteger)hash { return self.key.hash; }
- (id)copyWithZone:(NSZone *)z { return self; }
@end
static NSMutableArray<KStage *> *gStages;   // (Stage Manager's model: the switcher's stages)
static KStage *gIPadShown;
static KStage *gTVNamed; static long long gTVEnv = 3;   // (the TV's settled layout state: its environment and the stage it names)
static BOOL gStuck;          // (a transition begun and never finished: every later request and launch waits behind it)
static BOOL gBusy;           // (another transition in flight: a request is queued until it ends)
static BOOL gNoRequest;      // (the request method missing: nothing can be asked)
static BOOL gNoEnd;          // (the TV's transition never ends / its end is not seen)
static BOOL gSkipped;        // (the per-display bar's crash guard piece off)
static BOOL gTVGone;         // (the TV unplugged: no scene of it any more)
static BOOL gCardOff;        // (the window's card no longer on screen there -- faded or hidden while its transition runs -- its stage still named)
static int gRequests, gRaised, gDeleted, gNamedGoneAtStart;
static NSMutableArray *gQueued;
static NSMutableArray<NSString *> *gOrder;

static NSString *DMSMItemKey(id item) { return [item isKindOfClass:[KItem class]] ? ((KItem *)item).key : nil; }
static NSString *DMSMItemBundle(id item) { return DMSMKeyBundle(DMSMItemKey(item)); }
static KItem *It(NSString *key) { KItem *i = [KItem new]; i.key = key; return i; }
static KStage *Stage(NSString *ident, NSArray<NSString *> *keys) { KStage *s = [KStage new]; s.ident = ident; NSMutableDictionary *m = [NSMutableDictionary dictionary]; for (NSString *k in keys) m[It(k)] = @1; s.map = m; return s; }
static NSArray *DMSMRecentStages(void) { return [gStages copy]; }
static NSDictionary *DMSMStageItemsMap(id stage) { return [stage isKindOfClass:[KStage class]] ? ((KStage *)stage).map : nil; }
static id DMSMItemFor(id stage, NSString *key, id *attrsOut) {
    NSDictionary *m = DMSMStageItemsMap(stage);
    for (id it in m) if ([DMSMItemKey(it) isEqualToString:key] || [DMSMKeyBundle(DMSMItemKey(it)) isEqualToString:key]) { if (attrsOut) *attrsOut = m[it]; return it; }
    return nil;
}
static id DMSMStageOf(NSString *key) { for (KStage *s in gStages) if (DMSMItemFor(s, key, NULL)) return s; return nil; }
static id DMSMIPadStageShown(void) { return gIPadShown; }
static id DMSMShownMainStage(void) { return gIPadShown; }
static id DMSMStageDisplayIdentity(id stage) { return ((KStage *)stage).ident; }
static BOOL DMSMIsMainIdentity(id identity) { return !identity || [identity isEqual:@"ipad"]; }
static BOOL DMSMStageShownOnDisplay(id al, id identity) { return !gCardOff && [identity isEqual:@"tv"] && gTVEnv == 3 && al && al == gTVNamed; }
static BOOL DMSMGestureHoldsStage(id stage) { return NO; }
static BOOL DMSMGestureLive(void) { return NO; }
static void DMSMAfterGestureUsers(NSString *what, dispatch_block_t block) { }
static void DMSMAfterGesture(NSString *what, dispatch_block_t block) { }
static BOOL DMSMStripHoldsBack(NSString *what, dispatch_block_t act) { return NO; }
static id DMSMTopAffordanceFor(NSString *key) { return @"vc"; }
static NSMutableSet<NSString *> *gMin;
static void DMSMSetMinimized(NSString *key, BOOL on) { if (on) [gMin addObject:key]; else [gMin removeObject:key]; }
static void DMSMNoteRemoving(NSString *key, id stage) { }
static void DMSMFlyToDock(NSString *key) { }
static void DMSMEndGrowNow(NSString *key) { }
static void DMSMRunAction(UIAction *action, id sender) { [gOrder addObject:@"own close"]; }
static void DMSMGoHomeForReal(NSString *why) { [gOrder addObject:@"home"]; }
static void DMSnapForgetSMFront(void) { }
static BOOL DMBarFrontSkipped(void) { return gSkipped; }
static void DMSMAPIFail(NSString *what, NSString *why) { DMLog([NSString stringWithFormat:@"[smapi] REFUSED %@: %@", what, why]); }
static NSString *DMSMExpect(const char *ret, ...) { return @""; }
static BOOL DMSMSigOK(id obj, SEL sel, NSString *want, const char *what) { return YES; }
static NSString *DMSMSigObj(void) { return @""; }
static NSString *DMSMSigObjObj(void) { return @""; }
static NSString *DMSMSigVoidObj(void) { return @""; }
static NSString *DMSMSigRequestOnDisplay(void) { return @""; }
static NSString *DMSMSigOfMethod(Method m) { return @""; }
static id DMSMEmptyEntity(void) { return @"empty"; }
static const long long *DMSMRepairRoleList(size_t *n) { static const long long l[] = {1, 2, 3, 4, 5, 6, 7, 8}; *n = 8; return l; }
static BOOL DMSMCtxCanWrite(id ctx) { return YES; }
static void DMSMCtxMarkOurs(id ctx) { }
static BOOL DMSMEntityFlag(id e, NSString *flag) { return NO; }
static NSUInteger gSMRealHomeAskedGen = 0;
static NSUInteger DMSMRealHomeGenOf(id ctx) { return 0; }
static void MSHookMessageEx(Class c, SEL s, IMP i, IMP *o) { }

// the TV's layout state and SpringBoard's transition context at a transition's end
@interface KState : NSObject
@property (nonatomic) long long env; @property (nonatomic, strong) id stage;
@end
@implementation KState
@end
static BOOL DMSMHomeStateOf(id state, long long *env, id *stage) { if (![state isKindOfClass:[KState class]]) return NO; *env = ((KState *)state).env; *stage = ((KState *)state).stage; return YES; }
@interface KReq : NSObject
@property (nonatomic, copy) NSString *eventLabel; @property (nonatomic, copy) void (^modify)(id ctx);
@end
@implementation KReq
- (void)modifyApplicationContext:(void (^)(id))b { self.modify = b; }
@end
@interface KCtx : NSObject
@property (nonatomic, strong) NSMutableDictionary *roles;
@end
@implementation KCtx
- (void)setEntity:(id)e forLayoutRole:(long long)r { if (!self.roles) self.roles = [NSMutableDictionary dictionary]; self.roles[@(r)] = e; }
@end
@interface KAppCtx : NSObject
@property (nonatomic, copy) NSString *displayIdentity; @property (nonatomic, strong) KReq *request;
@end
@implementation KAppCtx
@end
@interface KEndCtx : NSObject
@property (nonatomic, strong) KState *toLayoutState; @property (nonatomic, strong) KAppCtx *applicationTransitionContext;
@end
@implementation KEndCtx
@end
@interface KCoord : NSObject
@end
@implementation KCoord
- (BOOL)deleteAppLayoutForDisplayItem:(id)item {   // (the App Switcher's own close of one window: its stage leaves the model; the layout state is untouched)
    for (KStage *s in [gStages copy]) if (s.map[item]) { [gStages removeObject:s]; gDeleted++; [gOrder addObject:@"taken out"]; return YES; }
    return NO;
}
- (id)switcherControllerForWindowScene:(id)scene { return [scene valueForKey:@"ctl"]; }
@end
static KCoord *gCoord;
static id DMSMCoordinator(void) { return gCoord; }
static void (*o_SMTransitionDidEnd)(id, SEL, id, id);
static void TOrigEnd(id s, SEL c, id co, id ctx) { }
static void TEnd(id ctx);   // (below: SMAfterHome.h's hook)

// SpringBoard's workspace: a request begins its transition at once (queued while another is in flight); one that begins from a TV state naming a
// stage the model no longer has raises inside SpringBoard, which never finishes it.
static void TBegin(KReq *r) {
    KCtx *ctx = [KCtx new];
    if (r.modify) r.modify(ctx);
    if (gTVEnv != 1 && gTVNamed && ![gStages containsObject:gTVNamed]) {
        gStuck = YES; gRaised++;
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to add an icon overlay but the item container for this app layout doesn't exist: (null)" userInfo:nil];
    }
    [gOrder addObject:@"TV transition begins"];
    if (gNoEnd) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gTVEnv = 1; gTVNamed = nil;   // (its empty desktop: every stage of it stays in the model, hidden)
        [gOrder addObject:@"TV transition ends"];
        KEndCtx *e = [KEndCtx new]; e.toLayoutState = [KState new]; e.toLayoutState.env = 1;
        e.applicationTransitionContext = [KAppCtx new]; e.applicationTransitionContext.displayIdentity = @"tv"; e.applicationTransitionContext.request = r;
        TEnd(e);
    });
}
@interface SBMainWorkspace : NSObject
@end
@implementation SBMainWorkspace
+ (id)sharedInstance { static SBMainWorkspace *w; if (!w) w = [SBMainWorkspace new]; return w; }
- (BOOL)requestTransitionWithOptions:(unsigned long long)o displayConfiguration:(id)cfg builder:(void (^)(id))b {
    if (gStuck) return NO;
    gRequests++;
    if (gTVNamed && ![gStages containsObject:gTVNamed]) gNamedGoneAtStart++;
    KReq *r = [KReq new]; b(r);
    if (gBusy) { [gQueued addObject:r]; return YES; }
    TBegin(r);
    return YES;
}
@end
static BOOL TLaunch(void) { return !gStuck; }   // (an app launch: SpringBoard's openApplication -- refused while a transition hangs)
static void TBusyEnds(void) {   // (the transition in flight ends: the queued requests begin, as SpringBoard runs them; a raise there is caught nowhere of ours)
    gBusy = NO;
    NSArray *q = [gQueued copy]; [gQueued removeAllObjects];
    for (KReq *r in q) { @try { TBegin(r); } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[world] a queued transition raised: %@", e.reason]); } }
}
@interface KCfg : NSObject
@property (nonatomic, copy) NSString *identity;
@end
@implementation KCfg
@end
@interface KScreen : NSObject
@property (nonatomic, strong) KCfg *displayConfiguration;
@end
@implementation KScreen
@end
static NSArray *DMDispScreens(void) { KScreen *a = [KScreen new], *b = [KScreen new]; a.displayConfiguration = [KCfg new]; a.displayConfiguration.identity = @"ipad"; b.displayConfiguration = [KCfg new]; b.displayConfiguration.identity = @"tv"; return @[a, b]; }
static id DMCall(id obj, NSString *name) {
    if ([name hasSuffix:@"Action"]) return [UIAction actionWithTitle:@"Close" image:nil identifier:nil handler:^(UIAction *a) {}];
    SEL s = NSSelectorFromString(name);
    return [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil;
}
// the TV's switcher, as DMMSWSMStateNamesGone reads it: a scene on that screen -> its switcher controller -> content view controller -> layout
// context -> layout state (plain stand-ins; the real code's class tests answer for these)
@interface KLayoutCtx : NSObject
@end
@implementation KLayoutCtx
- (id)layoutState { KState *s = [KState new]; s.env = gTVEnv; s.stage = gTVNamed; return s; }
@end
@interface KCVC : NSObject
@end
@implementation KCVC
- (id)layoutContext { return [KLayoutCtx new]; }
@end
@interface KCtl : NSObject
@end
@implementation KCtl
- (id)contentViewController { return [KCVC new]; }
@end
@interface TScene : NSObject
@property (nonatomic, copy) NSString *screen; @property (nonatomic, strong) KCtl *ctl;
@end
@implementation TScene
@end
@interface TWindowScene : TScene
@end
@implementation TWindowScene
@end
@interface TApplication : NSObject
@end
@implementation TApplication
+ (instancetype)sharedApplication { static TApplication *a; if (!a) a = [TApplication new]; return a; }
- (NSSet *)connectedScenes { if (gTVGone) return [NSSet set]; TWindowScene *s = [TWindowScene new]; s.screen = @"tv"; s.ctl = [KCtl new]; return [NSSet setWithObject:s]; }
@end
static id DMSMIdentityOfScreen(id screen) { return screen; }
// (the code before the fix asked from DMSMTVEmptyAfterLastWindow, reading the TV's state through the per-display bar's functions)
static id DMBarFrontInUseScreen(id identity) { return [identity isEqual:@"tv"] ? @"tv" : nil; }
static BOOL DMBarFrontSwitcherOn(id screen, long long *env, id *stage) { *env = gTVEnv; *stage = gTVNamed; return YES; }

// ---- the real code ----
static BOOL DMSMWindowActionAs(NSString *key, NSString *name, BOOL users);
static BOOL DMSMAfterTVEmptyHolds(NSString *bundle, dispatch_block_t block);
#define UIApplication TApplication
#define UIScene TScene
#define UIWindowScene TWindowScene
#include "te-real.inc"
#undef UIApplication
#undef UIScene
#undef UIWindowScene
#if !TE_HOLDS
static BOOL DMSMAfterTVEmptyHolds(NSString *bundle, dispatch_block_t block) { return NO; }   // (the code before the fix has none)
#endif
static void TEnd(id ctx) { DMSMTransitionDidEnd(gCoord, @selector(description), nil, ctx); }

// The force quit's own end of the app 0.45 s after its window's close (StatusBar.x DMForceQuitBundle, not cut out here): the app's switcher clean-up
// (-_deleteAppLayoutsMatchingBundleIdentifier:, its stages where it is alone) -- held by the real DMSMAfterTVEmptyHolds -- and again 0.6 s later.
static void TKill(NSString *bundle) {
    void (^remove)(void) = ^{
        for (KStage *s in [gStages copy]) { BOOL has = NO; for (id it in s.map) if ([DMSMItemBundle(it) isEqualToString:bundle]) has = YES; if (has && s.map.count == 1) { [gStages removeObject:s]; [gOrder addObject:@"app's stages deleted"]; } }
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!DMSMAfterTVEmptyHolds(bundle, remove)) remove();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (!DMSMAfterTVEmptyHolds(bundle, remove)) remove(); });
    });
}

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static void Spin(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static NSString *const kTips = @"com.apple.tips|sceneID:com.apple.tips-default";
static NSString *const kSettings = @"com.apple.Preferences|sceneID:com.apple.Preferences-default";
static KStage *gTipsStage;
static void Setup(void) {
    gLog = [NSMutableArray array]; gOrder = [NSMutableArray array]; gQueued = [NSMutableArray array]; gMin = [NSMutableSet set];
    gCoord = [KCoord new]; o_SMTransitionDidEnd = TOrigEnd; gSMAfterHomeHooked = YES;
#if TE_HOLDS
    [gSMAfterTVEmpty removeAllObjects];
#endif
    gStuck = gBusy = gNoRequest = gNoEnd = gSkipped = gTVGone = gCardOff = NO; gRequests = gRaised = gDeleted = gNamedGoneAtStart = 0;
    gTipsStage = Stage(@"tv", @[kTips]);
    gIPadShown = Stage(@"ipad", @[kSettings]);
    gStages = [NSMutableArray arrayWithObjects:gTipsStage, gIPadShown, nil];
    gTVNamed = gTipsStage; gTVEnv = 3;
}

int main(void) {
    @autoreleasepool {
        // 1. Tips, the TV's only window (full screen or a window), closed by the TV bar's red / Force Quit: the app quits 0.45 s later
        Setup();
        BOOL r = DMSMWindowActionAs(kTips, @"close", YES);
        TKill(@"com.apple.tips");
        Spin(1.6);
        Check(r, @"the TV bar's red: the TV desktop's last window: the close is ours");
        Check(gRaised == 0, [NSString stringWithFormat:@"the TV bar's red: SpringBoard raised inside no transition of ours (%d raised)", gRaised]);
        Check(TLaunch(), @"the TV bar's red: an app opens afterwards (SpringBoard's transitions are not held)");
        Check(gRequests == 1 && gNamedGoneAtStart == 0, [NSString stringWithFormat:@"the TV bar's red: the TV's empty desktop asked for once, while its state named a stage of the model (%d asked, %d from a gone stage)", gRequests, gNamedGoneAtStart]);
        Check(gTVEnv == 1, @"the TV bar's red (B86): the TV at its own empty desktop (environment 1: its wallpaper, bar and Dock)");
        Check(![gStages containsObject:gTipsStage], @"the TV bar's red: Tips's stage out of the model (no hidden window of a quit app left there)");
        NSUInteger iBegin = [gOrder indexOfObject:@"TV transition begins"], iOut = [gOrder indexOfObject:@"taken out"], iDel = [gOrder indexOfObject:@"app's stages deleted"];
        Check(iBegin != NSNotFound && (iOut == NSNotFound || iOut > iBegin) && (iDel == NSNotFound || iDel > iBegin), [NSString stringWithFormat:@"the TV bar's red: the stage leaves the model only after the TV's transition began (%@)", [gOrder componentsJoinedByString:@", "]]);
        Check([gOrder containsObject:@"TV transition ends"] && iOut != NSNotFound && iOut > [gOrder indexOfObject:@"TV transition ends"], @"the TV bar's red: ... taken out once it ended (as the iPad's last window after its Home)");

        // 2. the same with another transition in flight: the TV's request is queued; the force quit's clean-up must wait for it too
        Setup();
        gBusy = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        TKill(@"com.apple.tips");
        Spin(1.2);
        Check(gStages.count == 2, @"queued: nothing leaves the model while the TV's transition is still to come");
        TBusyEnds();
        Spin(1.6);
        Check(gRaised == 0 && TLaunch(), [NSString stringWithFormat:@"queued: the TV's transition began from a state SpringBoard can begin from; launches work (%d raised)", gRaised]);
        Check(gTVEnv == 1 && ![gStages containsObject:gTipsStage], @"queued: the TV at its empty desktop, Tips's stage out after");

        // 2b. (review) queued for longer than 4 s (another transition in flight that long): the 4 s wait must not take the stage out while the TV
        //     still shows it -- the queued transition would then begin from a state naming a stage the model no longer has
        Setup();
        gBusy = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        TKill(@"com.apple.tips");
        Spin(4.7);
        Check([gStages containsObject:gTipsStage] && gRaised == 0, [NSString stringWithFormat:@"queued past 4 s: the stage stays while the TV still shows it (%@)", [gOrder componentsJoinedByString:@", "]]);
        TBusyEnds();
        Spin(1.6);
        Check(gRaised == 0 && TLaunch(), [NSString stringWithFormat:@"queued past 4 s: the TV's transition began from a state SpringBoard can begin from; launches work (%d raised)", gRaised]);
        Check(gTVEnv == 1 && ![gStages containsObject:gTipsStage], @"queued past 4 s: the TV at its empty desktop, Tips's stage out after");

        // 3. the TV's state already names a stage the model no longer has (an older close, an unplug): the Mac Switcher's empty desktop is not asked
        Setup();
        [gStages removeObject:gTipsStage];
        BOOL asked = DMMSWSMRequestEmpty(@"tv", @"test");
        Check(!asked && gRequests == 0, @"a stale TV state: no request (SpringBoard cannot begin a transition from it)");
        Check(TLaunch(), @"a stale TV state: launches work");

        // 4. nothing can be asked (no request method): the 1.8.6 close, at once; nothing asked later
        Setup();
        gNoRequest = YES;
        Method m = class_getInstanceMethod([SBMainWorkspace class], @selector(requestTransitionWithOptions:displayConfiguration:builder:));
        IMP keep = method_getImplementation(m);
        method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s, unsigned long long o, id c, id b) { return NO; }));
        r = DMSMWindowActionAs(kTips, @"close", YES);
        Spin(1.0);
        method_setImplementation(m, keep);
        Check(r && ![gStages containsObject:gTipsStage] && gRequests == 0, @"not asked: taken out at once, as 1.8.6");
        Check(gRaised == 0 && TLaunch(), @"not asked: launches work");

        // 5. the per-display bar's piece off after a crash in it: the 1.8.6 close, nothing asked
        Setup();
        gSkipped = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        Spin(0.8);
        Check(r && ![gStages containsObject:gTipsStage] && gRequests == 0 && TLaunch(), @"the piece off: taken out at once, nothing asked, launches work");

        // 6. the TV's transition begun but its end never seen and the TV still showing the stage (still running, or never begun): not taken out at
        //    4 s (review: a stage on screen is never taken out); at the longest wait left in the model, nothing run; no raise, launches work
        Setup();
        gNoEnd = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        Spin(1.0);
        Check([gStages containsObject:gTipsStage], @"no end seen: the stage stays for now");
        Spin(3.7);
        Check([gStages containsObject:gTipsStage] && gRaised == 0 && TLaunch(), @"no end seen, the TV still shows it: not taken out 4 s on; launches work");
        Spin(1.0);
        Check([gStages containsObject:gTipsStage] && Logged(@"left in the model, nothing run") && gRaised == 0 && TLaunch(), @"... still on screen at the longest wait: left in the model, nothing run; launches work");
        // 6a. (review) the same with the window's card already off the TV while its transition runs: the TV's state still names the stage -- kept
        Setup();
        gNoEnd = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        Spin(0.5);
        gCardOff = YES;
        Spin(4.2);
        Check([gStages containsObject:gTipsStage] && gRaised == 0, @"no end seen, its card off the TV but the TV's state still naming the stage: not taken out 4 s on");
        // 6b. its end not seen, but the TV went to its empty desktop: taken out 4 s on
        Setup();
        gNoEnd = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        Spin(1.0);
        gTVEnv = 1; gTVNamed = nil;
        Spin(3.7);
        Check(![gStages containsObject:gTipsStage] && gRaised == 0 && TLaunch(), @"its end not seen, the TV at its empty desktop: taken out 4 s on; launches work");
        // 6c. (review) the TV unplugged before its end: SpringBoard moved Tips's stage to the iPad, which shows it -- never taken out while the iPad
        //     shows it (the iPad's state would name a stage the model no longer has), the app's clean-up not run either
        Setup();
        gNoEnd = YES;
        r = DMSMWindowActionAs(kTips, @"close", YES);
        TKill(@"com.apple.tips");
        Spin(0.3);
        gTVGone = YES; gTVEnv = 1; gTVNamed = nil; gTipsStage.ident = @"ipad"; gIPadShown = gTipsStage;
        Spin(4.4);
        Check([gStages containsObject:gTipsStage], [NSString stringWithFormat:@"the TV unplugged meanwhile, the iPad shows its stage: not taken out (%@)", [gOrder componentsJoinedByString:@", "]]);
        Spin(1.0);
        Check([gStages containsObject:gTipsStage] && gRaised == 0 && TLaunch(), @"... nor at the longest wait; launches work");

#if TE_HOLDS
        // 7. the window opened there again before its removal ran (its stage shown at the end): left open
        Setup();
        gTVEnv = 3; gTVNamed = gTipsStage;
        DMSMTVTakeOut(@"tv", It(kTips), kTips, YES);
        Check([gStages containsObject:gTipsStage] && Logged(@"opened again"), @"opened again on the TV before its removal: left open");
        // ... and a stage that holds another window by then: left
        Setup();
        gTVEnv = 1; gTVNamed = nil;
        gTipsStage.map = @{It(kTips): @1, It(@"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default"): @2};
        DMSMTVTakeOut(@"tv", It(kTips), kTips, YES);
        Check([gStages containsObject:gTipsStage] && Logged(@"holds other windows"), @"its stage holds another window by then: left");
#else
        Check(NO, @"opened again on the TV before its removal: no removal after the TV's empty desktop in this code");
#endif
        printf("%s  %d of %d checks\n", gFails ? "FAIL" : "PASS", gChecks - gFails, gChecks);
    }
    return gFails;
}
