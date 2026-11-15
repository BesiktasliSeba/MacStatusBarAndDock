// Mac test of the App Switcher clean-up (statusbar/SwitcherStale.h and StatusBar.x DMCleanStaleSwitcherCards), built by test-switcherstale.sh.
// A: the stale-card rule. The cards iPadOS brings back after a respring stay (the 17.5.1 case of 29 Oct: Stage Manager -> Aerial, the sweeps 20 s
//    and 35 s after the start took Weather, App Store and Settings); the card of an app that went away while SpringBoard ran goes after the grace
//    only when the user quit it or it crashed; the card of an app iPadOS ended (for memory, a time-out, the watchdog) stays, as iPadOS keeps it
//    (1.8.7.4, audit M3 of 1.8.7.2); the old rules for the grace, the app in front and a card that is gone still hold.
// B: how an app ended, read off FrontBoard's exit context: only a fault signal is a crash, the same as RunningBoard's own -isCrash on every
//    namespace, run on this Mac's RunningBoard and FrontBoard (macOS has both), and FrontBoard's crash bit agrees.
// C: the real DMCleanStaleSwitcherCards, DMNoteAppExit, DMNoteAppQuitting, DMPrewarmQuitAddFromKill (the kill hook), DMNoteAppInFront,
//    DMStaleCandidates and DMSwitcherBundleIDs (cut out of StatusBar.x into sst-real.inc) with SpringBoard's side as stand-ins (the switcher's
//    cards and its delete, the running apps, the app in front, FrontBoard's kill) and real exit contexts: an app the user had in front, ended by
//    iPadOS, keeps its card sweep after sweep; one the user quit or that crashed loses it. The quit is the app's end after a kill for the user's
//    quit: an app quit, then running again without coming in front (Slide Over, Split View's second app), ended by iPadOS keeps its card (review
//    of the M3 fix: the prewarm quit set, which it was still on, took it).
// SST_OLD_RULE / SST_NO_EXIT_RULE / SST_NO_EXIT_NOTE: the code before the fix (MSBDStaleCards without the quit set, no exit rule, no exit note);
// SST_NO_QUIT_END: the M3 fix before its review (the quit read off the prewarm quit set).
// Exit status: the number of failed checks (at most 98).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include "../statusbar/SwitcherStale.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static NSSet *S(NSArray *a) { return [NSSet setWithArray:a]; }
#ifdef SST_OLD_RULE
#define STALE(shown, running, inFront, quit, front, since, now) MSBDStaleCards(shown, running, inFront, front, since, now)
#else
#define STALE MSBDStaleCards
#endif

// ---- the real exit contexts of this Mac (RunningBoard, FrontBoard)
@interface NSObject (SSTExitAPI)
+ (id)exitContextForNamespace:(unsigned)ns code:(unsigned long long)code wait4Status:(int)status;
- (id)initWithUnderlyingContext:(id)context;
- (unsigned long long)exitReason;
+ (id)statusWithDomain:(unsigned)domain code:(unsigned long long)code;
- (BOOL)isCrash;
@end
static Class gFBExit, gRBSExit, gRBSStatus;
static BOOL SSTRealOK(void) {
    static int ok = -1;
    if (ok < 0) {
        dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard", RTLD_NOW);
        gFBExit = objc_getClass("FBProcessExitContext"); gRBSExit = objc_getClass("RBSProcessExitContext"); gRBSStatus = objc_getClass("RBSProcessExitStatus");
        ok = gFBExit && gRBSExit && gRBSStatus && [gRBSExit respondsToSelector:@selector(exitContextForNamespace:code:wait4Status:)]
             && [gFBExit instancesRespondToSelector:@selector(initWithUnderlyingContext:)] && [gFBExit instancesRespondToSelector:@selector(exitReason)]
             && [gRBSStatus respondsToSelector:@selector(statusWithDomain:code:)] && [gRBSStatus instancesRespondToSelector:@selector(isCrash)];
    }
    return ok;
}
// (stand-ins shaped as FrontBoard's: FBProcessExitContext.underlyingContext -> RBSProcessExitContext.status -> RBSProcessExitStatus domain, code)
@interface SSTStatus : NSObject
@property (nonatomic) unsigned domain;
@property (nonatomic) unsigned long long code;
@end
@implementation SSTStatus
- (NSString *)description { return [NSString stringWithFormat:@"<stand-in status %u/0x%llx>", self.domain, self.code]; }
@end
@interface SSTRBSContext : NSObject
@property (nonatomic, strong) id status;
@end
@implementation SSTRBSContext
@end
@interface SSTFBContext : NSObject
@property (nonatomic, strong) id underlyingContext;
@end
@implementation SSTFBContext
@end
static id SSTStandInExit(unsigned domain, unsigned long long code) {
    SSTStatus *st = [SSTStatus new]; st.domain = domain; st.code = code;
    SSTRBSContext *r = [SSTRBSContext new]; r.status = st;
    SSTFBContext *f = [SSTFBContext new]; f.underlyingContext = r;
    return f;
}
static id SSTExit(unsigned domain, unsigned long long code, int w4) {   // the real one where this Mac has FrontBoard, else the stand-in
    if (SSTRealOK()) return [[gFBExit alloc] initWithUnderlyingContext:[gRBSExit exitContextForNamespace:domain code:code wait4Status:w4]];
    return SSTStandInExit(domain, code);
}

// ---- C: StatusBar.x's side, around the real clean-up
static NSMutableArray<NSString *> *gSSTLog;
static void SSTLogLine(NSString *s) { [gSSTLog addObject:s ?: @""]; }
#define DMLog(...) SSTLogLine(__VA_ARGS__)
#define DMTestFlag(path) 0
static double gSSTNow;
#define CACurrentMediaTime() gSSTNow
static id DMCall(id obj, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static SBApplication *gSSTFront;
static SBApplication *DMFrontApp(void) { return gSSTFront; }
static BOOL gSSTSM;
static BOOL DMSMEngine(void) { return gSSTSM; }
static NSMutableSet<NSString *> *gSSTRunning;
static NSSet<NSString *> *DMLiveRunningBundleIDs(void) { return [gSSTRunning copy]; }
static NSMutableArray<NSString *> *gPrewarmQuitSet;   // (the prewarm quit set: DMPrewarmQuitAdd's, below; test-switcherquit runs the real one)
static NSMutableSet<NSString *> *gAppsInFrontSinceStart;
static NSMutableSet<NSString *> *gAppsEndedInCrash, *gAppsEndedByQuit, *gAppsQuitting;
// (the kill hook's other calls: the prewarm quit set as DMPrewarmQuitAdd keeps it, the Mac Switcher's records -- test-switcherquit's)
static void DMPrewarmQuitAdd(NSString *b) { if (b.length && ![gPrewarmQuitSet containsObject:b]) [gPrewarmQuitSet addObject:b]; }
static void DMMSWForgetApp(NSString *b) {}
static void DMMSWMWCloseQuitAway(NSString *b) {}
// (SBMainSwitcherViewController: its cards as app layouts of display items, and the delete it is asked for)
@interface SSTItem : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SSTItem
@end
@interface SSTLayout : NSObject
@property (nonatomic, copy) NSArray *allItems;
@end
@implementation SSTLayout
@end
@interface SSTSwitcher : NSObject
@property (nonatomic, strong) NSMutableArray<NSString *> *cards, *deleted;
@end
@implementation SSTSwitcher
- (NSArray *)recentAppLayouts {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *b in self.cards) { SSTItem *i = [SSTItem new]; i.bundleIdentifier = b; SSTLayout *l = [SSTLayout new]; l.allItems = @[i]; [a addObject:l]; }
    return a;
}
- (void)_deleteAppLayoutsMatchingBundleIdentifier:(NSString *)b { [self.deleted addObject:b]; [self.cards removeObject:b]; }
@end
#ifdef SST_NO_EXIT_NOTE
static void DMNoteAppExit(NSString *bid, id context) {}   // (the code before the fix noted no exit)
#endif
#include "sst-real.inc"   // (the real DMSwitcherBundleIDs, DMStaleCandidates, DMNoteAppInFront, DMCleanStaleSwitcherCards, DMNoteAppExit,
                         //  DMNoteAppQuitting, DMPrewarmQuitAddFromKill)

static SSTSwitcher *gSW;
static void SSTReset(NSArray<NSString *> *cards) {
    gSW = [SSTSwitcher new]; gSW.cards = [cards mutableCopy]; gSW.deleted = [NSMutableArray array];
    gSSTRunning = [NSMutableSet set]; gPrewarmQuitSet = [NSMutableArray array]; gAppsInFrontSinceStart = nil; gAppsEndedInCrash = nil; gAppsEndedByQuit = nil; gAppsQuitting = nil;
    gSSTFront = nil; gSSTSM = NO; gSSTNow = 0; gSSTLog = [NSMutableArray array];
    [DMStaleCandidates() removeAllObjects];
}
static void SSTFront(NSString *b) {   // b comes in front (running), as DMTickBody notes it
    if (b) { [gSSTRunning addObject:b]; DMNoteAppInFront(b); SBApplication *a = [SBApplication new]; a.bundleIdentifier = b; gSSTFront = a; }
    else gSSTFront = nil;
}
static void SSTSweep(double t) { gSSTNow = t; DMCleanStaleSwitcherCards(gSW, @"periodic"); }
static void SSTSweeps(double from, double to) { for (double t = from; t <= to; t += 15) SSTSweep(t); }
// FrontBoard's kill of b's process for `reason` (1: the user's quit -- the App Switcher's swipe-up, our Force Quit and red light), as both of
// -[FBApplicationProcess killForReason:...] hand it to the hook (test-switcherquit checks they do)
static void SSTKill(NSString *b, long long reason) { SSTItem *proc = [SSTItem new]; proc.bundleIdentifier = b; DMPrewarmQuitAddFromKill(proc, reason); }
static const NSUInteger kSSTQuitCode = 0xdeadfa11;   // (FrontBoard's user quit, as its end may read)
// b was in front, the user went to the Home Screen, then b ended (userQuit: the user quit it -- FrontBoard's kill for the user's quit first) with
// the exit context ctx; sweeps every 15 s for 10 minutes. YES when its card was deleted.
static BOOL SSTEnded(NSString *b, id ctx, BOOL userQuit) {
    SSTReset(@[b, @"com.apple.weather"]);
    SSTFront(b); SSTSweep(0); SSTFront(nil);
    if (userQuit) SSTKill(b, 1);
    [gSSTRunning removeObject:b]; DMNoteAppExit(b, ctx);
    SSTSweeps(10, 610);
    return [gSW.deleted containsObject:b];
}

int main(void) {
    @autoreleasepool {
        NSString *clock = @"com.apple.mobiletimer", *weather = @"com.apple.weather", *store = @"com.apple.AppStore", *prefs = @"com.apple.Preferences", *tips = @"com.apple.tips", *maps = @"com.apple.Maps", *safari = @"com.apple.mobilesafari";
        printf("-- A: the stale-card rule (SwitcherStale.h)\n");
        // KT's 17.5 after the switch to Aerial: four cards brought back, Clock's window restored (running, in front), nothing else opened yet --
        // even with all four on the quit set (it is kept across resprings)
        NSSet *kt = S(@[clock, weather, store, prefs]);
        NSMutableDictionary *since = [NSMutableDictionary dictionary];
        NSArray *out = nil; BOOL any = NO;
        for (double t = 8; t <= 600; t += 15) { out = STALE(kt, S(@[clock]), S(@[clock]), kt, clock, since, t); if (out.count) any = YES; }
        CHECK(!any, "after a respring (an engine switch): the cards brought back stay, sweep after sweep for 10 minutes (quit before it or not)");
        CHECK(since.count == 0, "  ... and none of them is even followed as stale");
        out = STALE(kt, S(@[clock]), S(@[clock]), kt, nil, since, 700);
        CHECK(out.count == 0, "  ... also with no app in front (the Home Screen)");
        // dasd prewarmed Weather (running a while, never in front), then it ended: its card stays
        since = [NSMutableDictionary dictionary];
        STALE(kt, S(@[clock, weather]), S(@[clock]), S(@[weather]), clock, since, 10);
        out = STALE(kt, S(@[clock]), S(@[clock]), S(@[weather]), clock, since, 25);
        out = [out arrayByAddingObjectsFromArray:STALE(kt, S(@[clock]), S(@[clock]), S(@[weather]), clock, since, 40)];
        CHECK(out.count == 0, "an app only dasd started (a prewarm), gone again: its card stays");
        // an app the user had in front, ended by iPadOS (for memory, a time-out, the watchdog: not on the quit set): its card stays (audit M3)
        since = [NSMutableDictionary dictionary];
        NSSet *cards = S(@[tips, weather]), *used = S(@[tips]), *quit = S(@[tips]);
        any = NO;
        for (double t = 0; t <= 600; t += 15) { out = STALE(cards, S(@[]), used, S(@[]), nil, since, t); if (out.count) any = YES; }
        CHECK(!any, "an app the user had in front, ended by iPadOS (not quit, no crash): its card stays, sweep after sweep for 10 minutes");
        CHECK(since.count == 0, "  ... and is not even followed as stale");
        out = STALE(cards, S(@[]), used, nil, nil, since, 700);
        CHECK(out.count == 0 && since.count == 0, "  ... nor with no quit set at all (nil: none)");
        // an app the user had in front, gone since because the user quit it or it crashed: goes after the grace
        since = [NSMutableDictionary dictionary];
        out = STALE(cards, S(@[]), used, quit, nil, since, 100);
        CHECK(out.count == 0 && since[tips] && !since[weather], "quit (or crashed), first seen stale: followed, nothing goes yet (and the card brought back is not followed)");
        out = STALE(cards, S(@[]), used, quit, nil, since, 103.9);
        CHECK(out.count == 0, "within the grace (3.9 s): not yet");
        out = STALE(cards, S(@[]), used, quit, nil, since, 104.0);
        CHECK(out.count == 1 && [out[0] isEqualToString:tips], "after 4 s still gone: its card goes (and only that one)");
        CHECK(!since[tips], "  ... and is no longer followed");
        // running again within the grace: the clock starts over
        since = [NSMutableDictionary dictionary];
        STALE(cards, S(@[]), used, quit, nil, since, 0);
        out = STALE(cards, S(@[tips]), used, quit, nil, since, 2);
        CHECK(out.count == 0 && !since[tips], "running again (a launch the list had not caught up with): no longer followed");
        STALE(cards, S(@[]), used, quit, nil, since, 5);
        out = STALE(cards, S(@[]), used, quit, nil, since, 8);
        CHECK(out.count == 0, "gone again: a new grace (3 s of it so far)");
        out = STALE(cards, S(@[]), used, quit, nil, since, 9);
        CHECK(out.count == 1, "  ... and the card goes 4 s after it went again");
        // the app in front is never stale, even while its process is still starting
        since = [NSMutableDictionary dictionary];
        STALE(cards, S(@[]), used, quit, tips, since, 0);
        out = STALE(cards, S(@[]), used, quit, tips, since, 30);
        CHECK(out.count == 0 && since.count == 0, "the app in front: never stale");
        // a card that went meanwhile (swiped away) is no longer followed
        since = [NSMutableDictionary dictionary];
        STALE(cards, S(@[]), used, quit, nil, since, 0);
        out = STALE(S(@[weather]), S(@[]), used, quit, nil, since, 10);
        CHECK(out.count == 0 && since.count == 0, "its card gone (swiped away): nothing followed, nothing to take");
        // several at once, sorted; a Split View card counts each app on it
        since = [NSMutableDictionary dictionary];
        NSSet *many = S(@[tips, prefs, store, weather, maps]), *usedMany = S(@[tips, prefs, store, maps]), *quitMany = S(@[tips, prefs, store]);
        STALE(many, S(@[store]), usedMany, quitMany, nil, since, 0);
        out = STALE(many, S(@[store]), usedMany, quitMany, nil, since, 4);
        CHECK(out.count == 2 && [out[0] isEqualToString:prefs] && [out[1] isEqualToString:tips],
              "two quit (sorted) go; the running one, the one never in front and the one iPadOS ended (Maps) stay");
        // no record of apps in front (nil, the stock status bar start): nothing is ever taken
        since = [NSMutableDictionary dictionary];
        STALE(cards, S(@[]), nil, quit, nil, since, 0);
        out = STALE(cards, S(@[]), nil, quit, nil, since, 60);
        CHECK(out.count == 0 && since.count == 0, "no apps in front noted at all: nothing taken");
        // nothing shown, nothing running: nothing
        CHECK(STALE(S(@[]), S(@[]), used, quit, nil, [NSMutableDictionary dictionary], 0).count == 0, "no cards: nothing");
        CHECK(kMSBDStaleCardGrace == 4.0, "the grace is 4 s, as before");

        printf("-- B: how an app ended (MSBDExitStatusIsCrash, MSBDExitContextIsCrash)\n");
#ifdef SST_NO_EXIT_RULE
        printf("   (not in this SwitcherStale.h: the code before the fix read no exit)\n");
#else
        {
            int crashSig[] = { SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS, SIGSEGV, SIGSYS };
            BOOL ok = YES;
            for (unsigned i = 0; i < sizeof crashSig / sizeof crashSig[0]; i++) ok = ok && MSBDExitStatusIsCrash(2, crashSig[i]);
            CHECK(ok, "the fault signals (SIGILL, SIGTRAP, SIGABRT, SIGFPE, SIGBUS, SIGSEGV, SIGSYS) are a crash");
            int notSig[] = { 0, SIGHUP, SIGINT, SIGQUIT, 7, SIGKILL, SIGUSR1, SIGPIPE, SIGALRM, SIGTERM, SIGXCPU, SIGUSR2 };
            ok = YES;
            for (unsigned i = 0; i < sizeof notSig / sizeof notSig[0]; i++) ok = ok && !MSBDExitStatusIsCrash(2, notSig[i]);
            CHECK(ok, "a kill or another signal (SIGKILL, SIGTERM, SIGQUIT, SIGEMT, SIGXCPU, ...) is no crash");
            ok = YES;
            for (unsigned long long c = 0; c <= 64; c++) ok = ok && !MSBDExitStatusIsCrash(1, c) && !MSBDExitStatusIsCrash(0, c) && !MSBDExitStatusIsCrash(10, c) && !MSBDExitStatusIsCrash(15, c);
            ok = ok && !MSBDExitStatusIsCrash(10, 0xdeadfa11) && !MSBDExitStatusIsCrash(10, 0x8badf00d) && !MSBDExitStatusIsCrash(15, 0xdead10cc) && !MSBDExitStatusIsCrash(1, 0x8badf00d);
            CHECK(ok, "an end for memory (jetsam), a quit (0xdeadfa11), the watchdog (0x8badf00d), a time-out (0xdead10cc), the app's own exit: no crash");
            if (SSTRealOK()) {
                unsigned long long special[] = { 0xdeadfa11, 0x8badf00d, 0xdead10cc, 0xbaadca11, 0xc00010ff, 0xbad22222, 0xbada5e47, 0xfa11fa11, 0xffffffffffffffffULL };
                int same = 0, total = 0;
                for (unsigned d = 0; d <= 64; d++)
                    for (unsigned k = 0; k < 65 + 9; k++) {
                        unsigned long long c = k < 65 ? k : special[k - 65];
                        BOOL theirs = [[gRBSStatus statusWithDomain:d code:c] isCrash];
                        total++; if (theirs == MSBDExitStatusIsCrash(d, c)) same++;
                        else if (total - same <= 5) printf("   differs: namespace %u code 0x%llx: RunningBoard %d, ours %d\n", d, c, theirs, MSBDExitStatusIsCrash(d, c));
                    }
                printf("   (RunningBoard's -isCrash on this Mac: %d of %d exit statuses the same)\n", same, total);
                CHECK(same == total, "the crash rule is RunningBoard's own -isCrash, every namespace 0-64 x codes 0-64 and the special codes");
            } else printf("   SKIP  RunningBoard's -isCrash: no RunningBoard/FrontBoard exit classes on this Mac (the stand-ins below still run)\n");
            // (realOnly: as launchd reports a signal to RunningBoard, namespace 0 and the signal in the wait4 status -- "termination reported by
            //  launchd (0, 0, 6)" in a device log of 12 Nov: RunningBoard makes it a SIGNAL status, which only the real classes show)
            struct { unsigned dom; unsigned long long code; int w4; BOOL crash; const char *what; BOOL realOnly; } ends[] = {
                { 1, 2, 9, NO, "an end for memory (jetsam, high-water)" }, { 1, 7, 9, NO, "an end for memory (jetsam, per-process limit)" },
                { 2, SIGKILL, SIGKILL, NO, "a kill (SIGKILL)" }, { 2, SIGTERM, SIGTERM, NO, "SIGTERM" }, { 10, 0xdeadfa11, 9, NO, "a quit (user-quit, 0xdeadfa11)" },
                { 10, 0x8badf00d, 9, NO, "the watchdog (0x8badf00d)" }, { 15, 0xdead10cc, 9, NO, "a background time-out (0xdead10cc)" }, { 0, 0, 0, NO, "the app's own exit" },
                { 2, SIGSEGV, SIGSEGV, YES, "SIGSEGV" }, { 2, SIGABRT, SIGABRT, YES, "SIGABRT" }, { 2, SIGTRAP, SIGTRAP, YES, "SIGTRAP" }, { 2, SIGBUS, SIGBUS, YES, "SIGBUS" },
                { 2, SIGILL, SIGILL, YES, "SIGILL" }, { 2, SIGFPE, SIGFPE, YES, "SIGFPE" }, { 2, SIGSYS, SIGSYS, YES, "SIGSYS" },
                { 0, 0, SIGABRT, YES, "SIGABRT as launchd reports it (0, 0, 6)", YES }, { 0, 0, 0x80 | SIGSEGV, YES, "SIGSEGV with a core, as launchd reports it", YES },
                { 0, 0, SIGKILL, NO, "a kill as launchd reports it (0, 0, 9)", YES }, { 0, 0, 0x100, NO, "exit(1) as launchd reports it", YES },
            };
            BOOL standIn = YES, real = YES, bit = YES;
            for (unsigned i = 0; i < sizeof ends / sizeof ends[0]; i++) {
                if (!ends[i].realOnly && MSBDExitContextIsCrash(SSTStandInExit(ends[i].dom, ends[i].code)) != ends[i].crash) { standIn = NO; printf("   stand-in: %s read wrong\n", ends[i].what); }
                if (!SSTRealOK()) continue;
                id fb = SSTExit(ends[i].dom, ends[i].code, ends[i].w4);
                if (MSBDExitContextIsCrash(fb) != ends[i].crash) { real = NO; printf("   FrontBoard's context: %s read wrong (%s)\n", ends[i].what, [[fb description] UTF8String]); }
                if ((([fb exitReason] & 4) != 0) != ends[i].crash) { bit = NO; printf("   FrontBoard's crash bit differs for %s\n", ends[i].what); }
            }
            CHECK(standIn, "the exit context read (underlyingContext -> status -> domain, code): only the fault signals are a crash (stand-ins)");
            if (SSTRealOK()) {
                CHECK(real, "  ... and on this Mac's real FBProcessExitContext / RBSProcessExitContext: the same for every end");
                CHECK(bit, "  ... and FrontBoard's own crash bit (exitReason 4) agrees for every end");
            }
            SSTRBSContext *noStatus = [SSTRBSContext new]; SSTFBContext *f = [SSTFBContext new]; f.underlyingContext = noStatus;
            CHECK(!MSBDExitContextIsCrash(nil) && !MSBDExitContextIsCrash([NSObject new]) && !MSBDExitContextIsCrash(f) && !MSBDExitContextIsCrash(@"SIGSEGV"),
                  "no context, another object, or no exit status to read: no crash (the card stays)");
        }
#endif

        printf("-- C: the real clean-up (StatusBar.x DMCleanStaleSwitcherCards, DMNoteAppExit) on %s exit contexts\n", SSTRealOK() ? "this Mac's real" : "stand-in");
        CHECK(!SSTEnded(safari, SSTExit(1, 7, 9), NO), "Safari in front, then ended by iPadOS for memory: its card stays for 10 minutes of sweeps");
        CHECK(!SSTEnded(safari, SSTExit(1, 2, 9), NO), "  ... the same for the high-water end");
        CHECK(!SSTEnded(safari, SSTExit(2, SIGKILL, SIGKILL), NO), "ended by a kill (SIGKILL): its card stays");
        CHECK(!SSTEnded(safari, SSTExit(10, 0x8badf00d, 9), NO), "ended by the watchdog: its card stays");
        CHECK(!SSTEnded(safari, SSTExit(15, 0xdead10cc, 9), NO), "ended at a background time-out: its card stays");
        CHECK(!SSTEnded(safari, SSTExit(0, 0, 0), NO), "the app's own exit: its card stays");
        CHECK(!SSTEnded(safari, nil, NO) && !SSTEnded(safari, [NSObject new], NO), "an exit with no context to read: its card stays");
        BOOL gone = SSTEnded(safari, SSTExit(2, SIGSEGV, SIGSEGV), NO);
        CHECK(gone, "Safari crashed (SIGSEGV): its card goes, as before");
        CHECK(gone && [gSW.deleted isEqualToArray:@[safari]], "  ... only that card");
        BOOL logged = NO; for (NSString *l in gSSTLog) if ([l containsString:@"removing 1 stale switcher card(s)"] && [l containsString:safari]) logged = YES;
        CHECK(logged, "  ... and the log names it");
        CHECK(SSTEnded(safari, SSTExit(2, SIGABRT, SIGABRT), NO) && SSTEnded(safari, SSTExit(2, SIGTRAP, SIGTRAP), NO) && SSTEnded(safari, SSTExit(2, SIGBUS, SIGBUS), NO),
              "  ... and after SIGABRT, SIGTRAP and SIGBUS");
        if (SSTRealOK()) {
            CHECK(SSTEnded(safari, SSTExit(0, 0, SIGABRT), NO), "  ... and after SIGABRT as launchd reports it (0, 0, 6)");
            CHECK(!SSTEnded(safari, SSTExit(0, 0, SIGKILL), NO), "a kill as launchd reports it (0, 0, 9): its card stays");
        }
        // the grace: the card of a crash goes 4 s after it was first seen stale, not before
        SSTReset(@[safari]); SSTFront(safari); SSTSweep(0); SSTFront(nil);
        [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(2, SIGSEGV, SIGSEGV));
        SSTSweep(10); SSTSweep(13.9);
        BOOL early = gSW.deleted.count > 0;
        SSTSweep(14);
        CHECK(!early && gSW.deleted.count == 1, "a crash's card: followed at the first sweep, gone 4 s later (the grace, as before)");
        CHECK(SSTEnded(safari, SSTExit(10, kSSTQuitCode, 9), YES), "Safari quit by the user (the kill for the user's quit, then its end): its card goes");
        CHECK(SSTEnded(safari, SSTExit(2, SIGKILL, SIGKILL), YES), "quit by the user, its exit read as a kill: its card goes (the quit decides)");
        CHECK(SSTEnded(safari, nil, YES), "quit by the user, no exit context: its card goes");
        // a crash, then the app opened again and ended for memory: its last end is no crash any more
        SSTReset(@[safari, weather]); SSTFront(safari); SSTSweep(0); SSTFront(nil);
        [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(2, SIGSEGV, SIGSEGV));
        SSTSweep(1); SSTFront(safari); SSTSweep(3); SSTFront(nil);
        [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(1, 7, 9));
        SSTSweeps(10, 610);
        CHECK(gSW.deleted.count == 0, "crashed, opened again within the grace, then ended for memory: its card stays");
        // a quit, then the app opened again (off the quit set, as DMPrewarmQuitClear takes it) and ended for memory: its card stays
        SSTReset(@[safari]); SSTFront(safari); SSTFront(nil);
        SSTKill(safari, 1); [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(10, kSSTQuitCode, 9));
        SSTFront(safari); [gPrewarmQuitSet removeObject:safari]; SSTSweep(5); SSTFront(nil);
        [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(1, 7, 9));
        SSTSweeps(10, 610);
        CHECK(gSW.deleted.count == 0, "quit, opened again, then ended for memory: its card stays");
        // (review of the M3 fix) Notes quit, then running again without ever being the active app -- dragged from the Dock into Slide Over or
        // as Split View's second app: no icon tap, none of our launches, not in front, so still on the prewarm quit set --, then ended by iPadOS
        // for memory: its card (the pair's, Slide Over's) stays
        NSString *notes = @"com.apple.mobilenotes";
        SSTReset(@[notes, weather]); SSTFront(notes); SSTSweep(0); SSTFront(nil);
        SSTKill(notes, 1); [gSSTRunning removeObject:notes]; DMNoteAppExit(notes, SSTExit(10, kSSTQuitCode, 9));
        SSTSweeps(10, 40);
        BOOL quitGone = [gSW.deleted containsObject:notes];
        [gSW.deleted removeAllObjects]; [gSW.cards addObject:notes]; [gSSTRunning addObject:notes];   // (Slide Over: running, a card, not in front)
        SSTSweeps(50, 110);
        BOOL onSet = [gPrewarmQuitSet containsObject:notes];
        [gSSTRunning removeObject:notes]; DMNoteAppExit(notes, SSTExit(1, 7, 9));
        SSTSweeps(120, 720);
        CHECK(quitGone, "Notes quit (a card left behind): its card goes after the grace");
        CHECK(onSet && ![gSW.deleted containsObject:notes] && [gSW.cards containsObject:notes],
              "  ... then running again in Slide Over (never in front: still on the prewarm quit set), ended by iPadOS for memory: its card stays");
        // the same, but the user quits it again while it runs: that end is a quit, its card goes
        SSTReset(@[notes]); SSTFront(notes); SSTSweep(0); SSTFront(nil);
        SSTKill(notes, 1); [gSSTRunning removeObject:notes]; DMNoteAppExit(notes, SSTExit(10, kSSTQuitCode, 9));
        [gSSTRunning addObject:notes]; SSTSweeps(10, 40);
        SSTKill(notes, 1); [gSSTRunning removeObject:notes]; DMNoteAppExit(notes, SSTExit(10, kSSTQuitCode, 9));
        SSTSweeps(50, 110);
        CHECK([gSW.deleted containsObject:notes], "  ... quit again while it runs (Slide Over's card swiped away): that end is a quit, its card goes");
        // on the prewarm quit set from an earlier SpringBoard session (it is kept), in front since, ended for memory: its card stays
        SSTReset(@[maps]); [gPrewarmQuitSet addObject:maps];
        SSTFront(maps); SSTSweep(0); SSTFront(nil);
        [gSSTRunning removeObject:maps]; DMNoteAppExit(maps, SSTExit(1, 2, 9));
        SSTSweeps(10, 610);
        CHECK(gSW.deleted.count == 0, "on the quit set from before the respring, in front since, ended by iPadOS for memory: its card stays");
        // a kill for another reason (not the user's quit), then the end: no quit, the card stays
        SSTReset(@[maps]); SSTFront(maps); SSTSweep(0); SSTFront(nil);
        SSTKill(maps, 5); [gSSTRunning removeObject:maps]; DMNoteAppExit(maps, SSTExit(2, SIGKILL, SIGKILL));
        SSTSweeps(10, 610);
        CHECK(gSW.deleted.count == 0, "a kill for another reason (5), then its end: no quit, its card stays");
        // unchanged: the Stage Manager engine keeps its own cards; an app never in front keeps its card; the app in front is never taken
        SSTReset(@[safari]); SSTFront(safari); SSTSweep(0); SSTFront(nil); gSSTSM = YES;
        SSTKill(safari, 1); [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(2, SIGSEGV, SIGSEGV));
        SSTSweeps(10, 610);
        CHECK(gSW.deleted.count == 0, "the Stage Manager engine: nothing taken, quit or crash (as before)");
        SSTReset(@[safari, weather]); SSTFront(safari);
        DMNoteAppExit(weather, SSTExit(2, SIGSEGV, SIGSEGV)); SSTKill(weather, 1); DMNoteAppExit(weather, SSTExit(10, kSSTQuitCode, 9));
        SSTSweeps(0, 600);
        CHECK(gSW.deleted.count == 0, "an app never in front since the start (its card brought back), crashed or quit: its card stays (as before)");
        SSTReset(@[safari]); SSTFront(safari); SSTKill(safari, 1); [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(2, SIGSEGV, SIGSEGV));
        SSTSweeps(0, 600);
        CHECK(gSW.deleted.count == 0, "the app in front, not listed as running: never taken (as before)");
#ifndef SST_NO_EXIT_NOTE
        // FrontBoard may call the exit back off the main thread: the record is changed on the main thread only
        SSTReset(@[safari]);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        id segv = SSTExit(2, SIGSEGV, SIGSEGV);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ DMNoteAppExit(safari, segv); dispatch_semaphore_signal(done); });
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        BOOL offMain = [gAppsEndedInCrash containsObject:safari];
        for (int i = 0; i < 100 && ![gAppsEndedInCrash containsObject:safari]; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        CHECK(!offMain && [gAppsEndedInCrash containsObject:safari], "an exit called back off the main thread: noted on the main thread");
#endif
#ifndef SST_NO_QUIT_END
        // FrontBoard may kill off the main thread: the quit is noted on the main thread, before the end that follows
        SSTReset(@[safari]); SSTFront(safari); SSTSweep(0); SSTFront(nil);
        dispatch_semaphore_t killed = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ SSTKill(safari, 1); dispatch_semaphore_signal(killed); });
        dispatch_semaphore_wait(killed, DISPATCH_TIME_FOREVER);
        BOOL quitOffMain = [gAppsQuitting containsObject:safari];
        for (int i = 0; i < 100 && ![gAppsQuitting containsObject:safari]; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        BOOL quitOnMain = [gAppsQuitting containsObject:safari];
        [gSSTRunning removeObject:safari]; DMNoteAppExit(safari, SSTExit(10, kSSTQuitCode, 9));
        SSTSweeps(10, 40);
        CHECK(!quitOffMain && quitOnMain && ![gAppsQuitting containsObject:safari] && [gSW.deleted containsObject:safari],
              "a kill for the user's quit off the main thread: noted on the main thread, its end is the quit (the card goes), the note used up");
#endif
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails > 98 ? 98 : fails;
}
