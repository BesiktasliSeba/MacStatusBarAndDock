// test-kbnokeyboard.m -- the keyboard-behind pass with no hardware keyboard attached (1.8.7.4, audit O3 and L52 of 1.8.7.2).
// The pass (StatusBar.x DMKeyboardFocusBehindWindows) keeps every window behind the active app from the hardware keyboard. It runs 5 times a second
// from the watcher's tick. With no hardware keyboard no window is kept from anything (MSBDKeyboardBehind gives none), yet the pass walked every
// window and looked up its scene each time, for nothing (O3). And it went on giving apps "back" a keyboard after one had been attached and removed
// (L52): an app brought to the front without a tap got SpringBoard's focus request (its on-screen keyboard came up), and the apps the gate held back
// while a keyboard was attached got it when they came to the front. Now: with no keyboard and nothing to undo the pass only notes the active app;
// the give-back needs a hardware keyboard; and the held-back apps are let go when there is none.
// The real code is cut out of statusbar/StatusBar.x by test-kbnokeyboard.sh (kbnokeyboard-real.inc: from #include "KeyboardBehind.h" to the end of
// DMKeyboardFocusBehindWindows -- the gate's state and lock, the arbiter's hooks and their install, the give-back and the pass; DMCall; and
// MSBDFocusHas from common/FocusLock.h). Stand-ins: the windows (DMAerialStagesAll, DMStageBundle, DMStageScene: each counted), the active app, the
// hardware keyboard, the engine, SpringBoard's keyboard focus controller and its keyboard arbiter (a class of the same name with the same type
// encodings, hooked by the real install), MSHookMessageEx, and dispatch_async on the test's own queue (the arbiter's and the main queue, in order).
//   t                  the scenarios (each in a child process of its own: the cut code's state starts fresh)
//   t trace A|B|C n    n random sequences of that class, one line per pass (for the .sh to compare with the code before the fix)
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <os/lock.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/wait.h>

// ---- the world ----
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;
static BOOL gKeyboard;                 // a hardware keyboard is attached
static DMEngine gEngine = DMEngineAerial;
static BOOL gSM, gStockBar;            // the Stage Manager engine; the stock status bar
static long gOS = 16;                  // the iPadOS major version
static double gNow;
static NSString *gActive;              // the active app (nil: none)
static BOOL gNativeFront;              // a window of ours (Finder) in front
static int gWalks, gSceneLooks, gHooks;
static NSMutableArray<NSString *> *gLog, *gFocus, *gPrevent, *gInval, *gFwdReq, *gFwdStat;
static NSMutableArray<NSNumber *> *gFocusKB;   // the keyboard at each focus request
static NSMutableArray<dispatch_block_t> *gQueue;
static void TAsync(dispatch_block_t b) { [gQueue addObject:[b copy]]; }
#define dispatch_async(queue, ...) TAsync(__VA_ARGS__)
static void Drain(void) { while (gQueue.count) { dispatch_block_t b = gQueue.firstObject; [gQueue removeObjectAtIndex:0]; b(); } }
static long TOSMajor(void) { return gOS; }
static double CACurrentMediaTime(void) { return gNow; }
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static BOOL DMHardwareKeyboardAttached(void) { return gKeyboard; }
static BOOL DMSMEngine(void) { return gSM; }
static DMEngine DMActiveEngine(void) { return gEngine; }
static void MSHookMessageEx(Class c, SEL s, IMP h, IMP *o) { Method m = class_getInstanceMethod(c, s); IMP old = method_setImplementation(m, h); if (o) *o = old; gHooks++; }

@interface TToken : NSObject
@property (copy) NSString *sid;
@end
@implementation TToken
@end
@interface TScene : NSObject
@property (copy) NSString *identifier, *bundle;
@property (strong) TToken *token;
- (id)identityToken;
@end
@implementation TScene
- (id)identityToken { return _token; }
@end
@interface UIView : NSObject   // (a window: Aerial's stage, a ZetsuWindow, MilkyWay's AXWindowView)
@property (copy) NSString *tBundle;
@property (strong) TScene *tScene;
@end
@implementation UIView
@end
static NSMutableArray<UIView *> *gWindows;
static int gSceneNo;
static NSArray<UIView *> *DMAerialStagesAll(void) { gWalks++; return gEngine == DMEngineNone ? @[] : [gWindows copy]; }
static NSString *DMStageBundle(UIView *st) { return st.tBundle; }
static id DMStageScene(UIView *st, NSString *b) { gSceneLooks++; return b.length ? st.tScene : nil; }
@interface DMNativeWindow : NSObject
@end
@implementation DMNativeWindow
@end
static DMNativeWindow *gNative;
static DMNativeWindow *DMNativeActiveApp(void) { return gNativeFront ? gNative : nil; }
static BOOL DMDesktopTypingNow(void) { return NO; }   // (1.8.8.1, Desktop.h: the desktop's typing counts as no app active; nothing types in these runs)
@interface SBApplication : NSObject
@property (copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static SBApplication *DMActiveApp(void) { if (!gActive) return nil; SBApplication *a = [SBApplication new]; a.bundleIdentifier = gActive; return a; }
static id DMSceneForBundle(NSString *b) { for (UIView *w in gWindows) if ([w.tBundle isEqualToString:b] && w.tScene) return w.tScene; return nil; }
static id DMFrontBoardSceneForBundle(NSString *b) {   // (a full-screen app: its default scene)
    if (!b.length) return nil;
    TScene *s = [TScene new]; s.bundle = b; s.identifier = [NSString stringWithFormat:@"sceneID:%@-default", b]; return s;
}

// SpringBoard's keyboard focus controller: the prevent-focus assertions and the focus request (15's 2-argument one), recorded
@interface TAssertion : NSObject
@property (copy) NSString *sid;
@property BOOL gone;
- (void)invalidate;
@end
@implementation TAssertion
- (void)invalidate { if (!_gone) { _gone = YES; [gInval addObject:_sid]; } }
@end
@interface TFocusController : NSObject
- (id)preventFocusForSceneWithIdentityToken:(id)token reason:(id)reason;
- (void)userFocusRequestForScene:(id)scene reason:(id)reason;
@end
@implementation TFocusController
- (id)preventFocusForSceneWithIdentityToken:(id)token reason:(id)reason { (void)reason; TAssertion *a = [TAssertion new]; a.sid = [token sid]; [gPrevent addObject:a.sid]; return a; }
- (void)userFocusRequestForScene:(id)scene reason:(id)reason { (void)reason; [gFocus addObject:[scene bundle]]; [gFocusKB addObject:@(gKeyboard)]; }
@end
static TFocusController *gKFC;
static id DMKeyboardFocusController(void) { return gKFC; }

// SpringBoard's keyboard arbiter (same class name and type encodings: the real install hooks it), its clients and their statuses
@interface THandler : NSObject
@property (copy) NSString *bundleIdentifier;
@property int pid;
@property unsigned long long wanted;
@property bool isActive;
- (bool)active;
- (unsigned long long)wantedState;
@end
@implementation THandler
- (bool)active { return _isActive; }
- (unsigned long long)wantedState { return _wanted; }
@end
@interface TStatus : NSObject
@property bool on;
- (bool)keyboardOnScreen;
@end
@implementation TStatus
- (bool)keyboardOnScreen { return _on; }
@end
static NSMutableDictionary<NSString *, THandler *> *gHandlers;
static int gPresenting;
@interface _UIKeyboardArbiter : NSObject {
    dispatch_queue_t _queue;
}
- (void)handlerRequestedFocus:(id)handler shouldStealKeyboard:(bool)steal;
- (void)updateKeyboardStatus:(id)status fromHandler:(id)handler;
- (id)handlerForBundleID:(id)bundle;
- (int)presentingKeyboardProcessIdentifier;
- (id)handlerForPID:(int)pid;
@end
@implementation _UIKeyboardArbiter
- (instancetype)init { if ((self = [super init])) _queue = dispatch_queue_create("test.keyboard-arbiter", DISPATCH_QUEUE_SERIAL); return self; }
- (void)handlerRequestedFocus:(id)handler shouldStealKeyboard:(bool)steal { [gFwdReq addObject:[NSString stringWithFormat:@"%@/%d", [handler bundleIdentifier], steal ? 1 : 0]]; }
- (void)updateKeyboardStatus:(id)status fromHandler:(id)handler { [gFwdStat addObject:[NSString stringWithFormat:@"%@/%d", [handler bundleIdentifier], [status keyboardOnScreen] ? 1 : 0]]; }
- (id)handlerForBundleID:(id)bundle { return gHandlers[bundle]; }
- (int)presentingKeyboardProcessIdentifier { return gPresenting; }
- (id)handlerForPID:(int)pid { for (THandler *h in gHandlers.allValues) if (h.pid == pid) return h; return nil; }
@end
static _UIKeyboardArbiter *gArb;

#include "kbnokeyboard-real.inc"

// ---- helpers ----
static NSString *const AMZ = @"com.amazon.Amazon", *const SET = @"com.apple.Preferences", *const MAP = @"com.apple.Maps", *const NOT = @"com.apple.mobilenotes",
                *const SAF = @"com.apple.mobilesafari";
static NSArray<NSString *> *Pool(void) { return @[AMZ, SET, MAP, NOT]; }
static THandler *Handler(NSString *b) {
    THandler *h = gHandlers[b];
    if (!h) { h = [THandler new]; h.bundleIdentifier = b; h.pid = 100 + (int)gHandlers.count; gHandlers[b] = h; }
    return h;
}
static void Setup(void) {
    gLog = [NSMutableArray array]; gFocus = [NSMutableArray array]; gPrevent = [NSMutableArray array]; gInval = [NSMutableArray array];
    gFwdReq = [NSMutableArray array]; gFwdStat = [NSMutableArray array]; gFocusKB = [NSMutableArray array]; gQueue = [NSMutableArray array];
    gWindows = [NSMutableArray array]; gHandlers = [NSMutableDictionary dictionary];
    gKFC = [TFocusController new]; gArb = [_UIKeyboardArbiter new]; gNative = [DMNativeWindow new];
    for (NSString *b in Pool()) Handler(b);
    Handler(SAF);
}
static UIView *Open(NSString *b, BOOL token) {
    UIView *w = [UIView new]; w.tBundle = b;
    TScene *s = [TScene new]; s.bundle = b; s.identifier = [NSString stringWithFormat:@"sceneID:%@-%d", b, ++gSceneNo];
    if (token) { s.token = [TToken new]; s.token.sid = s.identifier; }
    w.tScene = s; [gWindows addObject:w];
    return w;
}
static void Pass(void) { Drain(); gNow += 0.2; DMKeyboardFocusBehindWindows(); Drain(); }
static void PassNoDrain(void) { Drain(); gNow += 0.2; DMKeyboardFocusBehindWindows(); }
static void Request(NSString *b, bool steal) { [gArb handlerRequestedFocus:Handler(b) shouldStealKeyboard:steal]; }
static void Status(NSString *b, bool on) { TStatus *s = [TStatus new]; s.on = on; [gArb updateKeyboardStatus:s fromHandler:Handler(b)]; }
static NSString *Sorted(id<NSFastEnumeration> c) {
    NSMutableArray *a = [NSMutableArray array]; if (c) for (id x in c) [a addObject:[x description]];
    return [[a sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
}
static NSString *Held(void) { os_unfair_lock_lock(&gKBGateLock); NSString *s = Sorted(gKBHeldBack); os_unfair_lock_unlock(&gKBGateLock); return s; }
static NSString *GateBehind(void) { NSSet *b = nil; NSString *a = nil; DMKBGateList(&b, &a); return Sorted(b); }
static NSString *GateActive(void) { NSSet *b = nil; NSString *a = nil; DMKBGateList(&b, &a); return a ?: @"-"; }
static BOOL Gated(void) { for (NSString *l in gLog) if ([l hasPrefix:@"[kbbehind] the keyboard arbiter's requests are gated"]) return YES; return NO; }
static NSString *Sid(UIView *w) { return w.tScene.identifier; }

static int gFails;
static void Check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }
#define CHECK(cond, ...) Check((cond), [NSString stringWithFormat:__VA_ARGS__])

// ---- random sequences (trace mode, and class C's rules) ----
static uint64_t gRng;
static unsigned R(unsigned n) { gRng = gRng * 6364136223846793005ULL + 1442695040888963407ULL; return (unsigned)((gRng >> 33) % n); }
static int gViolations;   // (class C's rules, the new behaviour)
static NSString *Passed(void) {   // (class B) the app that asks, when the gate passes it on: the active app, unless a Finder window is in front or the app is on the gate's list
    NSSet *b = nil; NSString *a = nil; DMKBGateList(&b, &a);
    return gActive && !gNativeFront && ![b containsObject:gActive] ? gActive : nil;
}
static void TraceLine(int k) {
    printf("p%d kb%d %s act %s | prevent [%s] inval [%s] focus [%s] req [%s] stat [%s] hooks %d | list [%s] gate-active %s held [%s] last %s asserted [%s]\n",
           k, gKeyboard, gSM ? "sm" : [@[@"none", @"mw4", @"aerial", @"zetsu"][gEngine] UTF8String], (gNativeFront ? @"native" : gActive ?: @"-").UTF8String,
           [gPrevent componentsJoinedByString:@","].UTF8String, [gInval componentsJoinedByString:@","].UTF8String, [gFocus componentsJoinedByString:@","].UTF8String,
           [gFwdReq componentsJoinedByString:@","].UTF8String, [gFwdStat componentsJoinedByString:@","].UTF8String, gHooks,
           GateBehind().UTF8String, GateActive().UTF8String, Held().UTF8String, (gKBBehindLastActive ?: @"-").UTF8String, Sorted(gKBBehind.allKeys).UTF8String);
    [gPrevent removeAllObjects]; [gInval removeAllObjects]; [gFocus removeAllObjects]; [gFwdReq removeAllObjects]; [gFwdStat removeAllObjects]; [gFocusKB removeAllObjects];
}
// One random sequence. A: a hardware keyboard attached all along (everything else at random). B: the keyboard comes and goes, nothing is held
// back and no client keeps wanting the keys (only an app the gate passes on asks: the active app, no Finder window in front, not on the gate's
// list of the last pass), so the L52 cases are left out and the old and new code must do the same. C: everything at random (class C's rules are
// checked on each pass).
static void Sequence(char cls, uint64_t seed, BOOL print) {
    gRng = seed * 2654435761ULL + 1;
    gKeyboard = cls == 'A' ? YES : R(2);
    int passes = 0;
    for (int step = 0; step < 160; step++) {
        unsigned r = R(100);
        if (r < 40) {
            BOOL kbBefore = gKeyboard, nothingToUndo = !gKBBehind.count && !DMKBGateHolds();
            int walks = gWalks; NSUInteger focusAt = gFocusKB.count;
            if (R(10) < 7) Pass(); else PassNoDrain();
            passes++;
            if (cls == 'C') {
                for (NSUInteger i = focusAt; i < gFocusKB.count; i++) if (!gFocusKB[i].boolValue) gViolations++;   // (rule 1: no focus request without a keyboard)
                if (!kbBefore && nothingToUndo && gWalks != walks) gViolations++;                                // (rule 2: no walk without one and nothing to undo)
                if (!gKeyboard && Held().length) gViolations++;                                                    // (rule 3: nothing held back without one)
            }
            if (print) TraceLine(passes);
        } else if (r < 50) { if (cls != 'A') gKeyboard = !gKeyboard; }
        else if (r < 62) {
            if (R(10) == 0) gNativeFront = !gNativeFront;
            NSMutableArray *c = [NSMutableArray arrayWithObjects:SAF, @"", nil]; for (UIView *w in gWindows) [c addObject:w.tBundle];
            NSString *a = c[R((unsigned)c.count)]; gActive = a.length ? a : nil;
        } else if (r < 70) Open(Pool()[R(4)], R(100) < 85);
        else if (r < 75) { if (gWindows.count) [gWindows removeObjectAtIndex:R((unsigned)gWindows.count)]; }
        else if (r < 78) { unsigned e = R(10); gSM = e == 8; gEngine = e < 6 ? DMEngineAerial : e == 6 ? DMEngineZetsu : e == 7 ? DMEngineMilkyWay : e == 8 ? DMEngineAerial : DMEngineNone; }
        else if (r < 86) {
            NSString *b = cls == 'B' ? Passed() : (R(5) == 0 ? SAF : Pool()[R(4)]);
            BOOL steal = R(2);
            if (b) Request(b, steal);
        } else if (r < 92) {
            NSString *b = cls == 'B' ? Passed() : Pool()[R(4)];
            BOOL on = R(2);
            if (b) Status(b, on);
        } else if (r < 97) {
            THandler *h = Handler(Pool()[R(4)]);
            h.wanted = cls == 'B' ? 0 : R(2); h.isActive = R(2);
        } else { unsigned i = R(6); gPresenting = i < 4 ? Handler(Pool()[i]).pid : i == 4 ? Handler(SAF).pid : 0; }
    }
    if (print) printf("#cost walks %d scene-looks %d\n", gWalks, gSceneLooks);
}

// ---- the scenarios ----
static int Scenario(const char *title, void (^body)(void)) {
    fflush(stdout);
    pid_t p = fork();
    if (p == 0) { @autoreleasepool { printf("-- %s\n", title); Setup(); body(); } fflush(stdout); _exit(gFails > 250 ? 250 : gFails); }
    int st = 0; waitpid(p, &st, 0);
    if (WIFSIGNALED(st)) { printf("FAIL  %s: ended by signal %d\n", title, WTERMSIG(st)); return 1; }
    return WEXITSTATUS(st);
}
static void ShowsKeys(NSString *front, NSString *behind) {   // a keyboard attached, front's window in front of behind's, the gate on
    gKeyboard = YES; Open(behind, YES); Open(front, YES); gActive = front; Pass();
}
static void NoWalks(DMEngine engine, NSString *name) {
    gEngine = engine; gKeyboard = NO;
    Open(AMZ, YES); Open(SET, YES); Open(MAP, YES);
    NSArray *fronts = @[SET, AMZ, MAP, @"", SAF];
    BOOL lastOK = YES, gateOK = YES;
    for (int i = 0; i < 50; i++) {
        NSString *a = fronts[i % 5]; gActive = a.length ? a : nil;
        Pass();
        if (!(gActive ? [gKBBehindLastActive isEqualToString:gActive] : !gKBBehindLastActive)) lastOK = NO;
        if (!(gActive ? [GateActive() isEqualToString:gActive] : [GateActive() isEqualToString:@"-"]) || GateBehind().length) gateOK = NO;
    }
    CHECK(gWalks == 0 && gSceneLooks == 0, @"%@, no hardware keyboard, 3 windows, 50 passes as the active app changes: the windows are not walked (walks %d, scene looks %d; before: 50 / 150)", name, gWalks, gSceneLooks);
    CHECK(!gPrevent.count && !gFocus.count && !gInval.count, @"%@: nothing kept from the keys, nothing given back (as before)", name);
    CHECK(lastOK, @"%@: the active app is noted at each pass, as before (a keyboard attached later compares with it)", name);
    CHECK(gateOK, @"%@: the gate's list stays empty and names the active app, as before", name);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc >= 4 && !strcmp(argv[1], "trace")) {
            char cls = argv[2][0]; int n = atoi(argv[3]);
            for (int s = 1; s <= n; s++) {
                fflush(stdout);
                pid_t p = fork();
                if (p == 0) { @autoreleasepool { printf("## %c %d\n", cls, s); Setup(); Sequence(cls, (uint64_t)s, YES); } fflush(stdout); _exit(0); }
                int st = 0; waitpid(p, &st, 0);
                if (!WIFEXITED(st) || WEXITSTATUS(st)) { printf("CRASH %c %d\n", cls, s); return 1; }
            }
            return 0;
        }
        int fails = 0;
        fails += Scenario("the stand-ins", ^{
            ShowsKeys(SET, AMZ);
            CHECK(Gated() && gHooks == 2, @"the real install hooks the stand-in arbiter's request and status (SpringBoard's type encodings)");
            CHECK(DMKBArbiterQueue(gArb) != nil, @"the arbiter's queue is read from its _queue, as on the iPad");
        });
        fails += Scenario("O3: no hardware keyboard, nothing to undo", ^{
            NoWalks(DMEngineAerial, @"Aerial");
        });
        fails += Scenario("O3: the same with Zetsu", ^{ NoWalks(DMEngineZetsu, @"Zetsu"); });
        fails += Scenario("O3: the same with MilkyWay4", ^{ NoWalks(DMEngineMilkyWay, @"MilkyWay4"); });
        fails += Scenario("as before: a hardware keyboard attached", ^{
            ShowsKeys(SET, AMZ);
            UIView *amz = gWindows[0];
            CHECK([gPrevent isEqualToArray:@[Sid(amz)]] && [GateBehind() isEqualToString:AMZ] && [GateActive() isEqualToString:SET] && gWalks == 1,
                  @"Settings' window in front of Amazon's: Amazon's kept from the keys, the gate's list is Amazon (prevent [%@], list [%@], walks %d)", Sorted(gPrevent), GateBehind(), gWalks);
            for (int i = 0; i < 10; i++) Pass();
            CHECK(gWalks == 11 && gPrevent.count == 1, @"each pass with a keyboard walks the windows, as before (walks %d), one assertion only", gWalks);
            gActive = AMZ; Pass();
            CHECK([gInval isEqualToArray:@[Sid(amz)]] && [GateBehind() isEqualToString:SET] && gPrevent.count == 2 && !gFocus.count,
                  @"Amazon clicked to the front: its window may take the keys again, Settings' is kept (list [%@])", GateBehind());
        });
        fails += Scenario("as before, then O3: the keyboard goes", ^{
            ShowsKeys(SET, AMZ);
            UIView *amz = gWindows[0];
            for (int i = 0; i < 4; i++) Pass();
            int walks = gWalks;
            gKeyboard = NO; Pass();
            CHECK([gInval isEqualToArray:@[Sid(amz)]] && !GateBehind().length && !gKBBehind.count && gWalks == walks + 1,
                  @"the pass after the keyboard went gives Amazon's window back and empties the list, as before (inval [%@], walks +%d)", Sorted(gInval), gWalks - walks);
            for (int i = 0; i < 20; i++) Pass();
            CHECK(gWalks == walks + 1, @"after that, no walk while there is no keyboard (walks +%d over 20 passes; before: +21)", gWalks - walks);
            Request(AMZ, NO);
            CHECK([gFwdReq.lastObject isEqualToString:[AMZ stringByAppendingString:@"/0"]] && !Held().length, @"Amazon asking for the keyboard then is passed on (the gate is empty), as before");
            int before = gWalks;
            gKeyboard = YES; Pass();
            CHECK(gWalks == before + 1 && [GateBehind() isEqualToString:AMZ] && gPrevent.count == 2, @"a keyboard attached again: the next pass walks and keeps Amazon's window from the keys again, as before");
        });
        fails += Scenario("as before, then O3: a list with no assertion (a scene without an identity token)", ^{
            gKeyboard = YES; Open(AMZ, NO); Open(SET, YES); gActive = SET; Pass();
            CHECK([GateBehind() isEqualToString:AMZ] && !gPrevent.count && !gKBBehind.count, @"keyboard: Amazon's on the gate's list, no assertion (no token), as before");
            int walks = gWalks;
            gKeyboard = NO; Pass();
            CHECK(!GateBehind().length && gWalks == walks + 1, @"the keyboard gone: the next pass empties the list, as before (list [%@])", GateBehind());
            for (int i = 0; i < 10; i++) Pass();
            CHECK(gWalks == walks + 1, @"then no walk (walks +%d over 10 passes)", gWalks - walks);
        });
        fails += Scenario("L52: a keyboard attached once and removed; an app brought to the front without a tap", ^{
            ShowsKeys(SET, AMZ);
            Request(SET, NO);   // (the arbiter is seen through the gate's hook)
            gKeyboard = NO; Pass();
            Handler(AMZ).wanted = 1; Handler(AMZ).isActive = NO;   // (Amazon's search field keeps the keyboard)
            gActive = AMZ; Pass();
            CHECK(!gFocus.count, @"Amazon brought to the front with no keyboard: no focus request, its on-screen keyboard stays down (before: one for Amazon) [%@]", Sorted(gFocus));
        });
        fails += Scenario("L52: the same in the pass the keyboard goes (something still to undo)", ^{
            ShowsKeys(SET, AMZ);
            UIView *amz = gWindows[0];
            Request(SET, NO);
            Handler(AMZ).wanted = 1; Handler(AMZ).isActive = NO;
            gKeyboard = NO; gActive = AMZ; Pass();
            CHECK([gInval isEqualToArray:@[Sid(amz)]], @"the keyboard gone and Amazon in front: Amazon's window given back, as before");
            CHECK(!gFocus.count, @"... and no focus request for Amazon (before: one) [%@]", Sorted(gFocus));
        });
        fails += Scenario("L52: an app held back while a keyboard was attached", ^{
            ShowsKeys(SET, AMZ);
            Request(AMZ, NO);
            CHECK([Held() isEqualToString:AMZ] && !gFwdReq.count, @"keyboard: Amazon asking from behind is held back, not passed on, as before");
            gKeyboard = NO; Pass();
            CHECK(!Held().length, @"the keyboard gone: the held-back list is emptied (before: Amazon stayed on it) [%@]", Held());
            gActive = AMZ; Pass();
            CHECK(!gFocus.count, @"Amazon then brought to the front: no focus request (before: one) [%@]", Sorted(gFocus));
        });
        fails += Scenario("L52: held back, and in front in the pass the keyboard goes", ^{
            ShowsKeys(SET, AMZ);
            Request(AMZ, NO);
            gKeyboard = NO; gActive = AMZ; Pass();
            CHECK(!gFocus.count && !Held().length, @"no focus request, the held-back list emptied (before: a focus request for Amazon) [focus %@, held %@]", Sorted(gFocus), Held());
        });
        fails += Scenario("L52: the arbiter's answer comes after the keyboard went", ^{
            ShowsKeys(SET, AMZ);
            Request(SET, NO);
            Handler(AMZ).wanted = 1; Handler(AMZ).isActive = NO;
            gActive = AMZ; PassNoDrain();
            gKeyboard = NO; Drain();
            CHECK(!gFocus.count, @"Amazon came to the front with a keyboard, the keyboard went before the answer was acted on: no focus request (before: one) [%@]", Sorted(gFocus));
        });
        fails += Scenario("as before: the give-back with a keyboard", ^{
            ShowsKeys(SET, AMZ);
            Request(AMZ, NO);
            gActive = AMZ; Pass();
            CHECK([gFocus isEqualToArray:@[AMZ]] && !Held().length && [GateBehind() isEqualToString:SET], @"Amazon held back, clicked to the front: one focus request gives it its keys back (focus [%@])", Sorted(gFocus));
        });
        fails += Scenario("as before: an app whose field kept the keys comes to the front with a keyboard", ^{
            ShowsKeys(SET, AMZ);
            Request(SET, NO);
            Handler(AMZ).wanted = 1; Handler(AMZ).isActive = NO;
            gActive = AMZ; Pass();
            CHECK([gFocus isEqualToArray:@[AMZ]], @"Amazon brought to the front without a tap: the arbiter's queue says its field wants the keys, one focus request (focus [%@])", Sorted(gFocus));
            Pass(); Pass();
            CHECK(gFocus.count == 1, @"... once (not again while it stays in front)");
        });
        fails += Scenario("as before: the active app noted with no keyboard", ^{
            ShowsKeys(SET, AMZ);
            Request(SET, NO);
            gKeyboard = NO; Pass();
            gActive = AMZ; for (int i = 0; i < 5; i++) Pass();
            Handler(AMZ).wanted = 1; Handler(AMZ).isActive = NO;
            gKeyboard = YES; Pass();
            CHECK(!gFocus.count, @"Amazon in front all along with no keyboard, a keyboard attached: Amazon did not come to the front, no focus request [%@]", Sorted(gFocus));
            CHECK([GateBehind() isEqualToString:SET], @"... and Settings' window behind is kept from the keys (list [%@])", GateBehind());
        });
        fails += Scenario("as before: a Finder window in front with no keyboard", ^{
            gKeyboard = NO; Open(AMZ, YES); Open(SET, YES); gActive = SET; gNativeFront = YES;
            for (int i = 0; i < 5; i++) Pass();
            CHECK(!gKBBehindLastActive && [GateActive() isEqualToString:@"-"] && !gPrevent.count && !gFocus.count, @"no app is active (none noted), nothing done, as before");
            CHECK(gWalks == 0, @"... and no walk (walks %d; before: 5)", gWalks);
        });
        fails += Scenario("as before: the Stage Manager engine (the gate off)", ^{
            gSM = YES; gKeyboard = NO; Open(AMZ, YES); Open(SET, YES); gActive = SET;
            for (int i = 0; i < 5; i++) Pass();
            CHECK(gWalks == 0 && !gKBBehindLastActive, @"no keyboard: nothing done, the active app not noted (the gate-off return comes first, as before)");
            gKeyboard = YES; for (int i = 0; i < 5; i++) Pass();
            CHECK(gWalks == 0 && !gPrevent.count && !gKBBehindLastActive, @"with a keyboard: nothing done either, as before");
        });
        fails += Scenario("as before: the engine switched to Stage Manager with the keyboard attached", ^{
            ShowsKeys(SET, AMZ);
            UIView *amz = gWindows[0];
            Request(AMZ, NO);
            gSM = YES; Pass();
            CHECK([gInval isEqualToArray:@[Sid(amz)]] && !GateBehind().length && !Held().length && !gFocus.count, @"Amazon's window given back, the list and the held-back list emptied, no focus request");
        });
        fails += Scenario("class C: random sequences, the new rules", ^{
            int total = 0;
            for (uint64_t s = 1; s <= 300; s++) {
                pid_t p = fork();
                if (p == 0) { @autoreleasepool { Setup(); Sequence('C', s, NO); } _exit(gViolations > 250 ? 250 : gViolations); }
                int st = 0; waitpid(p, &st, 0);
                total += WIFEXITED(st) ? WEXITSTATUS(st) : 1000;
            }
            CHECK(total == 0, @"300 random sequences (keyboard, windows, engines, apps asking from behind, fields keeping the keys): no focus request without a keyboard, no walk without one and nothing to undo, nothing held back without one (%d broken)", total);
        });
        printf("%d check(s) failed\n", fails);
        return fails > 98 ? 98 : fails;
    }
}
