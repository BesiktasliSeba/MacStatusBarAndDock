// test-smgesturemodifier.m -- Mac test of GitHub #12 (16.3.1, plans/rootcause-issue12.md): SIGABRT in the App Switcher with the Stage Manager engine. After a hold
// into the App Switcher the gesture's transaction is over but its modifier stays in the switcher's tree until it has settled, and goes on looking its stage up with no
// not-found check. A card tapped then, joined to the desktop, made a new stage sharing that stage's windows; SpringBoard dropped the held one, and
// -[NSArray subarrayWithRange:] threw. The code as built: statusbar/SMGestureHold.h whole, and the snapshot cache's guard cut out of SMGestureHook.h (test-smgesturemodifier.sh,
// smgesturemodifier-gen.h), with stand-ins for the modifier tree (DMSMCardsHeld) and the clock. An older source: what is not in it is stood in for by what that code did.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <QuartzCore/QuartzCore.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static double gNow = 1000.0;
#define CACurrentMediaTime() (gNow)
static NSMutableArray<NSString *> *gLog;
#define DMLog(...) [gLog addObject:(__VA_ARGS__)]
static BOOL DMTestFlag(const char *p) { (void)p; return NO; }
static BOOL DMSMIsStage(id s) { return s != nil; }
static NSDictionary *DMSMStageItemsMap(id s) { (void)s; return @{}; }
static NSString *DMSMItemUid(id i) { (void)i; return nil; }
static NSSet *gHeldNow;
static int gHeldAsked = 0;
static NSSet *DMSMCardsHeld(void) { gHeldAsked++; return gHeldNow; }
#include "../statusbar/SMGestureHold.h"
#include "smgesturemodifier-gen.h"
@interface FakeRequest : NSObject @property (nonatomic, copy) NSString *eventLabel; @end @implementation FakeRequest @end
@interface FakeCtx : NSObject @property (nonatomic, strong) FakeRequest *request; @end @implementation FakeCtx @end
@interface FakeTx : NSObject @property (nonatomic) BOOL isComplete; @end @implementation FakeTx @end
@interface FakeMod : NSObject @property (nonatomic, strong) NSArray *appLayouts; @end @implementation FakeMod @end
@interface FakeOther : NSObject @end @implementation FakeOther @end
// (the install's classes: SpringBoard's SBSwitcherModifier as 16.7.7 has it -- its list and the range method --, one with another count type, one with no list)
static int gOwnCalls = 0;
@interface SBSwitcherModifier : NSObject @property (nonatomic, strong) NSArray *appLayouts; @end
@implementation SBSwitcherModifier
- (id)appLayoutsToCacheSnapshotsWithVisibleRange:(NSRange)r numberOfSnapshotsToCache:(unsigned long long)n biasForward:(BOOL)b {
    (void)n; (void)b; gOwnCalls++;
    return [self.appLayouts subarrayWithRange:r];   // (SpringBoard's own: throws for a range past the list, as on the iPad)
}
@end
@interface TestModWrongArgs : NSObject @property (nonatomic, strong) NSArray *appLayouts; @end
@implementation TestModWrongArgs
- (id)appLayoutsToCacheSnapshotsWithVisibleRange:(NSRange)r numberOfSnapshotsToCache:(long long)n biasForward:(BOOL)b { (void)r; (void)n; (void)b; return nil; }
@end
@interface TestModNoList : NSObject @end
@implementation TestModNoList
- (id)appLayoutsToCacheSnapshotsWithVisibleRange:(NSRange)r numberOfSnapshotsToCache:(unsigned long long)n biasForward:(BOOL)b { (void)r; (void)n; (void)b; return nil; }
@end
static int gOriginals = 0;
static id FakeOriginal(id self, SEL _cmd, NSRange r, unsigned long long n, BOOL b) { (void)self; (void)_cmd; (void)r; (void)n; (void)b; gOriginals++; return @[@"SpringBoard's own"]; }
static void Pump(double seconds) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false); }
int main(void) { @autoreleasepool {
    setvbuf(stdout, NULL, _IOLBF, 0);   // (a made-to-fail copy may end in a crash: its lines before are kept)
    gLog = [NSMutableArray array];
    gSMGestureHooked = YES;   // (the transaction's hooks are in, as on every iPadOS the engine runs on)
    NSSet *stage = [NSSet setWithObject:@"Tips+Files"];
    FakeCtx *plain = [FakeCtx new]; plain.request = [FakeRequest new]; plain.request.eventLabel = @"a card's tap";

    // ---- a stage a gesture's modifier holds counts as held ----
    gSMGestureEndedAt = 0; gHeldNow = nil;
    Expect(!DMSMGestureCtx(plain), @"no gesture, nothing held: an ordinary context");
    gSMGestureEndedAt = gNow - 0.3; gHeldNow = stage;
    Expect(DMSMGestureCtx(plain), @"#12: the gesture's transaction over, its modifier still holding a stage 0.3 s later: the context counts as the gesture's");
    gHeldNow = nil;
    Expect(!DMSMGestureCtx(plain), @"  ... the modifier gone: an ordinary context again (a card tapped once the switcher has settled joins at once)");
    gHeldNow = stage; gSMGestureEndedAt = gNow - kSMModifierHoldMax - 0.1;
    Expect(!DMSMGestureCtx(plain), @"  ... a modifier still there long after the gesture's end holds nothing back (one kept for good on an iPadOS not read)");
    gSMGestureEndedAt = 0; gHeldAsked = 0;
    Expect(!DMSMGestureCtx(plain) && gHeldAsked == 0, @"  ... no gesture ended yet: the tree is not even read (a context at every transition)");
    FakeTx *tx = [FakeTx new]; gSMGestureTxs = [NSHashTable weakObjectsHashTable]; [gSMGestureTxs addObject:tx]; gHeldNow = nil;
    Expect(DMSMGestureCtx(plain), @"a transaction running: as before");
    [gSMGestureTxs removeObject:tx];
    FakeCtx *final = [FakeCtx new]; final.request = [FakeRequest new]; final.request.eventLabel = @"FinalFluidSwitcherGestureAction";
    Expect(DMSMGestureCtx(final), @"a gesture's own end by its label: as before");

    // ---- what waits for the gesture waits for its modifier too ----
    __block int joins = 0;
    gHeldNow = stage; gSMGestureEndedAt = gNow - 0.2;
    DMSMAfterGestureOnce(@"the desktop join", ^{ joins++; });
    Pump(0.35);
    Expect(joins == 0, @"#12: the join queued for after the gesture does not run while the modifier holds the stage (it would drop that stage from under it)");
    gHeldNow = nil;
    Pump(0.35);
    Expect(joins == 1, @"  ... it runs, once, as soon as the modifier has gone");
    __block int users = 0;
    gHeldNow = stage; gSMGestureEndedAt = gNow;
    DMSMAfterGestureUsers(@"a real Home", ^{ users++; });
    Pump(0.25);
    Expect(users == 0, @"  ... the user's own action waits for it the same way");
    gNow += kSMModifierHoldMax + 0.5;
    Pump(0.35);
    Expect(users == 1, @"  ... and a modifier that never goes keeps it no longer than the cap: the action runs");
    gHeldNow = nil;

    // ---- the snapshot cache's guard, iPadOS 16 ----
    o_SMCacheRange = FakeOriginal; gSMCacheList = @selector(appLayouts);
    FakeMod *mod = [FakeMod new]; mod.appLayouts = @[@"Clock", @"Tips+Files"];
    NSUInteger logged = gLog.count;
    id got = DMSMCacheRange(mod, _cmd_stub, NSMakeRange(NSNotFound, 1), 3, YES);
    Expect([got isEqual:@[]] && gOriginals == 0, @"the guard: a visible range from a stage not found (NSNotFound): no snapshots cached, SpringBoard's method (and its range exception) not reached");
    Expect(gLog.count == logged + 1, @"  ... logged");
    got = DMSMCacheRange(mod, _cmd_stub, NSMakeRange(2, 1), 3, NO);
    Expect([got isEqual:@[]] && gOriginals == 0 && gLog.count == logged + 2, @"  ... a range starting at the list's end: the same, and logged every time it fires");
    got = DMSMCacheRange(mod, _cmd_stub, NSMakeRange(1, 1), 3, YES);
    Expect([got isEqual:@[@"SpringBoard's own"]] && gOriginals == 1 && gLog.count == logged + 2, @"  ... a range inside the list: SpringBoard's own, nothing logged");
    got = DMSMCacheRange([FakeOther new], _cmd_stub, NSMakeRange(9, 1), 3, YES);
    Expect([got isEqual:@[@"SpringBoard's own"]] && gOriginals == 2, @"  ... a modifier with no list of that shape: SpringBoard's own");

    // ---- the guard's install (1.8.7: the iPad 2 16.7.7 logged "not as read on 16.7.7 here" at every start -- the guard was never in) ----
    o_SMCacheRange = NULL; gSMCacheList = NULL; gHooks = 0;
    Expect([DMSMNormEncoding("@44@0:8{_NSRange=QQ}16Q32B40") isEqualToString:@"@@:{QQ}QB"] && [DMSMNormEncoding("@48@0:8{_NSRange=QQ}16Q32B40") isEqualToString:@"@@:{QQ}QB"],
           @"the install compares argument types: the iOS compiler's encoding (@44, a BOOL counted 4) and the one read wrongly before (@48) are the same shape");
    gTestClass = "TestModWrongArgs"; gTestMajor = 16; DMSMCacheRangeInstall();
    Expect(gHooks == 0 && !o_SMCacheRange, @"  ... a method of another shape (a signed count): not hooked, SpringBoard's as it is");
    gTestClass = "TestModNoList"; DMSMCacheRangeInstall();
    Expect(gHooks == 0 && !o_SMCacheRange, @"  ... a modifier with no list to read: not hooked");
    gTestClass = "SBSwitcherModifier"; gTestMajor = 17; DMSMCacheRangeInstall(); gTestMajor = 18; DMSMCacheRangeInstall();
    Expect(gHooks == 0 && !o_SMCacheRange, @"  ... iPadOS 17 and 18: not hooked (18.5's SpringBoard checks NSNotFound itself; 17 not read)");
    gTestMajor = 16; DMSMCacheRangeInstall();
    Expect(gHooks == 1 && o_SMCacheRange && gSMCacheList == @selector(appLayouts), @"iPadOS 16, the method as SpringBoard's (its argument types, whatever the frame offsets): hooked, the list it reads set");
    SBSwitcherModifier *sb = [SBSwitcherModifier new]; sb.appLayouts = @[@"Tips", @"Clock", @"Files"];
    id r = nil; BOOL threw = NO; gOwnCalls = 0;
    @try { r = [sb appLayoutsToCacheSnapshotsWithVisibleRange:NSMakeRange(NSNotFound, 1) numberOfSnapshotsToCache:3 biasForward:YES]; } @catch (NSException *e) { threw = YES; }
    Expect(!threw && [r isEqual:@[]] && gOwnCalls == 0, @"  ... the d41 crash's call (range {NSNotFound, 1} over 3 app layouts): none cached, no NSRangeException");
    @try { r = [sb appLayoutsToCacheSnapshotsWithVisibleRange:NSMakeRange(1, 2) numberOfSnapshotsToCache:3 biasForward:NO]; } @catch (NSException *e) { threw = YES; }
    Expect(!threw && [r isEqual:@[@"Clock", @"Files"]] && gOwnCalls == 1, @"  ... a range inside the list: SpringBoard's own answer");
    printf("%s: %d checks, %d failed\n", fails ? "test-smgesturemodifier run FAILED" : "test-smgesturemodifier run: all pass", checks, fails);
    return fails ? 1 : 0;
} }
