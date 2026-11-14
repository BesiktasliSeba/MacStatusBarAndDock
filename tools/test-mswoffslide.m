// test-mswoffslide.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the Mac Switcher switched off while a desktop slides in (1.8.7.3, audit L81
// of 1.8.7.2). Settings off makes the iPad's desktops one (DMMSWCollapse); a switch still on its way then read the desktop places it began with in
// the one desktop left -- gMSWDesks[1] raised NSRangeException in DMMSWChangeDesktop (Aerial, Zetsu, MilkyWay4) or DMMSWSMAimChange (Stage
// Manager) and SpringBoard crashed. The off block now ends the running switch first (DMMSWGiveUpSwitch), and every later step of the switch checks
// the aim it belongs to.
// Runs the real switch of the other engines (DMMSWSwitchRun, DMMSWRunPendingLaunch, DMMSWSwAim, DMMSWSwitchGo, DMMSWSwChange, DMMSWSwWait,
// DMMSWSwEnd), Stage Manager's (DMMSWSMSwitch, DMMSWSMSwitchEnd, DMMSWSMAbort, DMMSWSMAimChange), the off block (DMMSWApplyPref, DMMSWCollapse) and
// the give-up (DMMSWGiveUpSwitch, when the file has it), cut out of statusbar/MacSwitcher.h and MacSwitcherSM.h by test-mswoffslide.sh into
// msw-real.inc. Time is a clock of the test's own (CACurrentMediaTime, DMMSWAfter, DMMSWAsync and the slide's animations below): every step runs
// in time order, nothing waits on the wall clock. The slide's pictures and animations, the engines' windows and SpringBoard are the stand-ins
// below, which record what they are asked; DMMSWChangeDesktop's stand-in begins as the real one does, reading both desktop places (the audit's
// crash site; the site check in the .sh keeps that true).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- the test's clock: the code's times, its delayed and next-turn steps, the slide's animations
static double gT = 1000.0;
#define CACurrentMediaTime() (gT)
static NSMutableArray<NSArray *> *gQ;
static NSUInteger gSeq;
static NSException *gCaught;   // (the first exception a step raised: SpringBoard would have crashed there)
static void Later(double d, dispatch_block_t b) { if (b) [gQ addObject:@[@(gT + MAX(0.0, d)), @(gSeq++), [b copy]]]; }
static void Guard(dispatch_block_t b) { @try { b(); } @catch (NSException *e) { if (!gCaught) gCaught = e; } }
static void RunTo(double t) {   // everything due by t, in time order (the same time: in the order asked)
    for (;;) {
        NSArray *next = nil;
        for (NSArray *e in gQ) {
            double at = [e[0] doubleValue];
            if (at > t) continue;
            if (!next || at < [next[0] doubleValue] || (at == [next[0] doubleValue] && [e[1] unsignedIntegerValue] < [next[1] unsignedIntegerValue])) next = e;
        }
        if (!next) break;
        [gQ removeObjectIdenticalTo:next];
        gT = [next[0] doubleValue];
        Guard(next[2]);
    }
    if (t > gT) gT = t;
}
static void RunFor(double s) { RunTo(gT + s); }

// ---- what the real code logs
static NSMutableArray<NSString *> *gLog;
#define DMLog(...) [gLog addObject:(__VA_ARGS__) ?: @""]
#define DMMSWMark(...) do { } while (0)
#define DM_FEATURE_MARK(x) do { } while (0)
static NSUInteger LogHas(NSString *part) { NSUInteger n = 0; for (NSString *l in gLog) if ([l rangeOfString:part].location != NSNotFound) n++; return n; }

// ---- the desktops (MacSwitcher.h's model in use: the iPad's)
static NSMutableArray<NSNumber *> *gMSWDesks;
static NSUInteger gMSWCur;
static NSArray<NSNumber *> *gSQKept;   // (the desktops kept at the off for when it is on again: DMMSWKeepForLater / DMMSWLoad)
static BOOL gMSWOn, gMSWOpen, gMSWSwitching, gMSWDesksDirty, gMSWTrackCommit, gMSWSwInChange, gMSWChangeAskedWS, gMSWPendingLaunchTap, gIconTapLaunch;
static int gMSWTrack;
static UIView *gMSWTrackPic, *gMSWLiftPic, *gMSWCutShot;
static NSInteger gMSWCutShotId, gMSWPendingSide;
static NSString *gMSWQuietAsked, *gMSWPendingLaunch;
static UIWindow *gMSWWindow;
static NSMutableDictionary<NSString *, NSString *> *gMSWFullScreen;
static NSMutableDictionary<NSString *, UIView *> *gMSWWinShots, *gMSWFreshPics;
static NSMutableDictionary<NSString *, NSNumber *> *gMSWWinDesk;
static NSMutableDictionary<NSNumber *, UIView *> *gMSWShots;
static NSMutableDictionary<NSNumber *, NSArray *> *gMSWShotSet;
static NSMutableDictionary<NSString *, NSDictionary *> *gMSWFit;
static const void *kMSWNotKeptKey = &kMSWNotKeptKey;
static const NSTimeInterval kMSWRevealFade = 0.15, kMSWViewFade = 0.18;
// (the running switch of the other engines, MacSwitcher.h)
static NSUInteger gMSWSwFrom, gMSWSwTo, gMSWSwGen, gMSWSwRedirects, gMSWSwRun;
static NSInteger gMSWSwToSlot, gMSWSwFromId, gMSWSwQueued;
static UIView *gMSWSwOld;
static BOOL gMSWSwLanded, gMSWSwRevealing, gMSWSwRedirectable, gMSWSwChanged, gMSWSwFromGesture;
static NSString *gMSWSwWhy;
static CFTimeInterval gMSWSwT0, gMSWSwViewGoneAt;
static void (^gMSWSwDone)(void);
// (Stage Manager's, MacSwitcherSM.h)
static NSUInteger gMSWSMSwFrom, gMSWSMSwRedirects, gMSWSMAimGen, gMSWSMAimTo;
static NSInteger gMSWSMSwFromId, gMSWSMAimSlot, gMSWSMQueued;
static UIView *gMSWSMSwOld, *gMSWSMHomeShot;
static BOOL gMSWSMSwLeftHome, gMSWSMSwChanged, gMSWSMAimRedirectable, gMSWSMAimSlid, gMSWSMAimHasPic;
static CFTimeInterval gMSWSMSwT0, gMSWSMSwT1, gMSWSMQuietUntil;
static CGFloat gMSWSMSwV;
static NSString *gMSWSMSwWhy, *gMSWSMSwLaunching;
static void (^gMSWSMSwDone)(void);
static NSMutableDictionary<NSNumber *, NSNumber *> *gMSWSMLeftAt;
static unsigned gMSWSMDiag[5];
static NSMutableDictionary *gSMFitSlots;
static NSMutableSet<NSString *> *gSMFreeWindows;
static id gNativeActive;

// ---- the slide (its pictures and animations: the spring's landing, the reveal and the live slide end whatever happened to the slide meanwhile)
static UIView *gMSWSlRoot, *gMSWSlOld, *gMSWSlSide[2];
static NSMutableDictionary<NSNumber *, NSNumber *> *gMSWSlPlaces;
static CFTimeInterval gMSWSlQuietAt;
static int gSlBegins, gReveals;
static BOOL DMMSWSlBegin(UIView *old, UIView *leftPic, UIView *rightPic) {
    gSlBegins++; gMSWSlRoot = [UIView new]; gMSWSlOld = old; gMSWSlSide[0] = leftPic; gMSWSlSide[1] = rightPic;
    [gLog addObject:@"(test) the slide comes up"];
    return YES;
}
static void DMMSWSlDrop(void) { if (!gMSWSlRoot) return; gMSWSlRoot = nil; gMSWSlOld = nil; gMSWSlSide[0] = gMSWSlSide[1] = nil; gMSWSlPlaces = nil; }
static void DMMSWSlFinishTo(NSInteger k, CGFloat v, void (^landed)(void)) { Later(0.35, landed); }
static void DMMSWSlFinish(NSInteger side, CGFloat v, void (^landed)(void)) { DMMSWSlFinishTo(side, v, landed); }
static void DMMSWSlReveal(NSTimeInterval fade, void (^done)(void)) { gReveals++; if (!gMSWSlRoot) { if (done) done(); return; } Later(fade, done); }   // (no slide: at once, as the real one)
static void DMMSWSlLive(NSInteger side, CGFloat v, void (^done)(void)) { gReveals++; Later(0.35, done); }
static void DMMSWSlSetPlace(NSInteger k, NSUInteger place) { if (!gMSWSlPlaces) gMSWSlPlaces = [NSMutableDictionary dictionary]; gMSWSlPlaces[@(k)] = @(place); }
static UIView *DMMSWSlPicOfPlace(NSUInteger place) { return place == gMSWSwFrom ? gMSWSwOld : nil; }
static void DMMSWWhenDrawn(NSString *wantFront, BOOL (^landed)(void), BOOL (^gone)(void), void (^then)(NSString *how)) {   // (each frame until landed)
    __block void (^poll)(void);
    void (^p)(void) = ^{
        if (gone && gone()) { poll = nil; return; }
        if (!landed()) { Later(1.0 / 120.0, poll); return; }
        poll = nil;
        then(@"drawn");
    };
    poll = p;
    Later(0, poll);
}

// ---- the left and coming desktops' pictures
static UIView *gSQKeptPic;                                   // (a left picture kept from the view's opening or the gesture's start; nil: none)
static void (^gSQPicDone)(UIView *pic, double ms);            // (a picture asked without waiting, still on its way)
static UIView *DMMSWLeftPictureKept(BOOL wasOpen, NSString **src) { if (src) *src = @"kept (test)"; return gSQKeptPic; }
static BOOL DMMSWAsyncScreenOn(void) { return YES; }
static BOOL DMMSWAsyncPicturesOK(void) { return YES; }
static BOOL DMMSWScreenPictureAsync(NSArray<UIWindow *> *exclude, void (^done)(UIView *pic, double ms)) { gSQPicDone = [done copy]; return YES; }
static BOOL DMMSWPictureAsync(UIView *v, void (^done)(UIView *pic, double ms)) { gSQPicDone = [done copy]; return YES; }
static UIView *DMMSWLeftPictureNow(BOOL wasOpen, NSString **src) { if (src) *src = @"now (test)"; return [UIView new]; }
static UIView *DMMSWLeftFromParts(UIView *fsPic, UIView *fsSrc) { return [UIView new]; }
static UIView *DMMSWDeskPicture(NSUInteger i, CGRect b) { return [UIView new]; }
static UIView *DMMSWSMDeskPicture(NSInteger did, CGRect b) { return [UIView new]; }
static UIView *DMMSWLeftPicture(BOOL wasOpen) { return [UIView new]; }
static UIView *DMMSWFullScreenView(NSString *bundle, BOOL logAll) { return bundle ? [UIView new] : nil; }
static UIView *DMMSWFullScreenWithBar(UIView *fsv) { return fsv; }
static UIScreen *DMMSWScreen(void) { return nil; }

// ---- SpringBoard and the engines
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation SBApplication
@end
static SBApplication *gSQFront;   // (the app in front, full screen; nil: the Home Screen)
static SBApplication *DMFrontApp(void) { return gSQFront; }
static BOOL DMFullScreenAppInFront(void) { return gSQFront != nil; }
static BOOL gSQSM;   // the Stage Manager engine
static BOOL DMSMEngine(void) { return gSQSM; }
static BOOL DMMSWDesktopsHere(void) { return gMSWOn; }
static BOOL DMMSWIsMain(void) { return YES; }
static BOOL DMMSWForMain(void) { return YES; }
static BOOL DMTestFlag(const char *path) { return NO; }
static void DMMSWAfter(double seconds, dispatch_block_t b) { Later(seconds, b); }
static void DMMSWAsync(dispatch_block_t b) { Later(0, b); }
static NSMutableArray<NSString *> *gSQOpened;   // (apps opened: DMWindowedLaunch)
static BOOL DMWindowedLaunch(NSString *b) { [gSQOpened addObject:b]; return YES; }
static void DMOpenFullScreen(NSString *b) { [gSQOpened addObject:[@"full screen " stringByAppendingString:b]]; }
static void DMMinimize(void) {}
static NSMutableArray<NSString *> *gSQChanges;   // (the windows changes asked: "<from id> -> <to id>")
static NSString *DMMSWChangeDesktop(NSUInteger from, NSUInteger to) {
    NSInteger fromId = gMSWDesks[from].integerValue, toId = gMSWDesks[to].integerValue;   // (as the real one begins: the audit's crash site)
    [gSQChanges addObject:[NSString stringWithFormat:@"%ld -> %ld", (long)fromId, (long)toId]];
    gMSWCur = to;
    return nil;
}
static NSInteger DMMSWCurId(void) { return gMSWCur < gMSWDesks.count ? gMSWDesks[gMSWCur].integerValue : 0; }
static NSString *DMMSWDeskName(NSUInteger i) { return [NSString stringWithFormat:@"Desktop %lu", (unsigned long)i + 1]; }
static BOOL DMMSWSpringBoardIdle(void) { return YES; }
static BOOL DMMSWQuietOn(void) { return NO; }
static BOOL DMMSWSwRedirect(NSInteger side, CGFloat v, NSString *why) { return NO; }
static void DMMSWSpanBegin(void) {}
static void DMMSWSpanEnd(NSString *what) {}
static void DMMSWCutOutsFrom(UIView *old, NSInteger fromId) {}
static void DMMSWCutLetGo(void) { gMSWCutShot = nil; gMSWCutShotId = 0; }
static NSArray *DMMSWWindowSet(NSInteger did) { return @[]; }
static void DMMSWTrimPictures(NSInteger keepId) {}
static void DMMSWSMTrimPictures(NSInteger currentId) {}
static void DMMSWRecBegin(NSString *why) {}
static int gEnds;   // (a switch's end ran: DMMSWSwEnd and DMMSWSMSwitchEnd end its recording)
static void DMMSWRecEndAfter(double seconds) { gEnds++; }
static void DMMSWDropFinishNow(void) {}
static void DMMSWCloseUnderSlide(void) {}
static void DMMSWEndOtherDisplay(NSString *why) {}   // (no other display's session runs: the iPad's model in use)
static BOOL DMMSWIsOpen(void) { return gMSWOpen; }
static void DMMSWClose(id pick, BOOL animated) { gMSWOpen = NO; }
static void DMMSWOpenShotDrop(void) {}
static void DMMSWKeepForLater(void) { gSQKept = [gMSWDesks copy]; }
static void DMMSWClearMine(void) {}
static int gSQApplies;
static void DMMSWApply(void) { gSQApplies++; }
static void DMMSWSave(void) {}
static BOOL DMMSWOSOK(void) { return YES; }
static BOOL DMMSWSelfCheck(void) { return YES; }
static void DMMSWHookKeys(void) {}
static void DMMSWHookGestures(void) {}
static void DMMSWHookStockPaths(void) {}
static void DMMSWWatchMemory(void) {}
static void DMMSWLoad(void) { if (gSQKept.count) gMSWDesks = [gSQKept mutableCopy]; gMSWCur = 0; }   // (on again: the desktops kept at the off)
static void DMMSWBringBack(void) {}
static void DMMSWWatchDisplays(void) {}
static BOOL DMSMStripPresentationEnd(NSString *why) { return NO; }
static id DMMSWSMShownHere(void) { return nil; }
static id DMSMIPadStageShown(void) { return nil; }   // (the Home Screen: the coming desktop has no window)
static NSDictionary *DMSMStageItemsMap(id stage) { return @{}; }
static NSString *DMSMItemKey(id item) { return nil; }
static BOOL DMMSWSMSameWindow(NSString *a, NSString *b) { return [a isEqualToString:b]; }
static NSString *DMMSWSMCardsDrawn(void) { return @"(no cards)"; }
static void DMMSWSMLeave(NSInteger fromId) {}
static void DMMSWSMArrive(NSInteger toId) {}
static NSString *DMMSWSMShowDesk(NSInteger did, NSString *why) { return nil; }
static void DMNativeSetActive(id w) {}
static BOOL DMFitEnabled(void) { return NO; }
static void DMSMFitTick(BOOL now) {}
static void DMSM17DiagSoon(void) {}
static void DMMSWSwitchGo(NSUInteger to, NSString *why, CGFloat v, void (^done)(void), BOOL fromGesture, CFTimeInterval t0, UIView *old);
static void DMMSWSwChange(NSUInteger gen, CFTimeInterval since);
static void DMMSWSwWait(NSUInteger gen, NSString *fs, NSString *quiet, BOOL retry, NSString *head, CFTimeInterval t3);
static void DMMSWSwEnd(void);
static void DMMSWSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void));
static void DMMSWRunPendingLaunch(NSString *why);
static void DMMSWSMSwitch(NSUInteger to, NSString *why, NSString *launching, CGFloat v, void (^done)(void));
static void DMMSWSMAimChange(NSUInteger gen);
static void DMMSWSMAbort(void);
static void DMMSWCollapse(void);
static void DMMSWSMSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void)) { DMMSWSMSwitch(to, why, nil, v, done); }   // (MacSwitcherSM.h's one line)

#include "msw-real.inc"   // (the real DMMSWSwitchRun ... DMMSWSwEnd, DMMSWCollapse, DMMSWGiveUpSwitch, DMMSWApplyPref; DMMSWSMSwitch ... DMMSWSMAimChange)

// ---- the checks
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static NSString *J(NSArray *a) { return a.count ? [a componentsJoinedByString:@", "] : @"none"; }
static int gDones;
static void (^Done(void))(void) { return ^{ gDones++; [gLog addObject:@"(test) the switch's follow-up ran"]; }; }
static void reset(BOOL sm, NSUInteger desks) {
    gQ = [NSMutableArray array]; gCaught = nil; gLog = [NSMutableArray array];
    gSQSM = sm; gMSWOn = YES; gMSWOpen = NO; gMSWSwitching = NO; gMSWTrack = 0; gMSWTrackCommit = NO;
    gMSWDesks = [NSMutableArray array]; for (NSUInteger i = 1; i <= desks; i++) [gMSWDesks addObject:@(i)];
    gMSWCur = 0; gSQKept = nil;
    gMSWFullScreen = [NSMutableDictionary dictionary]; gMSWWinShots = [NSMutableDictionary dictionary]; gMSWWinDesk = [NSMutableDictionary dictionary];
    gMSWShots = [NSMutableDictionary dictionary]; gMSWShotSet = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary];
    gMSWPendingLaunch = nil; gMSWPendingSide = 0; gMSWSwQueued = 0; gMSWSMQueued = 0;
    gSQKeptPic = [UIView new]; gSQPicDone = nil; gSQFront = nil;
    gSQOpened = [NSMutableArray array]; gSQChanges = [NSMutableArray array];
    gSlBegins = gReveals = gDones = gSQApplies = gEnds = 0;
    DMMSWSlDrop();
}
static void off(void) { Guard(^{ DMMSWApplyPref(NO); }); RunFor(0); }   // (Settings off: the off block runs at the next turn of the main thread)
static void on(void) { Guard(^{ DMMSWApplyPref(YES); }); }
static NSString *Crash(void) { return gCaught ? [NSString stringWithFormat:@"%@: %@", gCaught.name, gCaught.reason] : @"none"; }

int main(void) { @autoreleasepool {
    // (the iPad's iPadOS: 15, so that the Mac's own version does not choose the code's way)
    method_setImplementation(class_getInstanceMethod([NSProcessInfo class], @selector(operatingSystemVersion)),
                             imp_implementationWithBlock(^NSOperatingSystemVersion(id me) { return (NSOperatingSystemVersion){15, 6, 1}; }));

    // 1. Aerial (any engine but Stage Manager), two desktops: a switch to Desktop 2 starts; Settings off 5 ms later, before its windows change
    reset(NO, 2);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    RunFor(0.005);
    BOOL slideUp = gMSWSlRoot != nil, wasSwitching = gMSWSwitching;
    off();
    printf("-- the other engines: off 5 ms into a switch to Desktop 2, before its windows change\n");
    ok(slideUp && wasSwitching && gSQChanges.count == 0, @"set-up: the switch runs, its slide is up, no windows changed yet");
    ok(!gMSWSwitching && !gMSWSlRoot && gMSWDesks.count == 1 && LogHas(@"the Mac Switcher went off during a switch: the switch ends here") == 1,
       [NSString stringWithFormat:@"the off ends the switch there: no switch running, no slide left, one desktop (desktops: %lu)", (unsigned long)gMSWDesks.count]);
    RunFor(3.0);
    ok(!gCaught, [NSString stringWithFormat:@"nothing reads a desktop place past the one left (SpringBoard's crash: %@)", Crash()]);
    ok(gSQChanges.count == 0 && gReveals == 0 && gDones == 0 && !gMSWSwitching && !gMSWSlRoot && gMSWCur == 0,
       [NSString stringWithFormat:@"after it, the given-up switch changes no windows, reveals nothing, runs no follow-up (changes: %@; reveals %d; follow-ups %d)", J(gSQChanges), gReveals, gDones]);

    // 1b. The same, off after its windows changed, before the slide has landed (its wait for the landing runs)
    reset(NO, 2);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    RunFor(0.1);
    BOOL changed1b = [gSQChanges isEqualToArray:@[@"1 -> 2"]] && gMSWSwitching && gReveals == 0;
    off();
    RunFor(3.0);
    printf("-- the other engines: off after the windows changed, before the slide has landed\n");
    ok(changed1b, [NSString stringWithFormat:@"set-up: the windows changed (%@), the slide still on its way", J(gSQChanges)]);
    ok(!gCaught && gReveals == 0 && gEnds == 0 && gDones == 0 && !gMSWSwitching && gSQChanges.count == 1,
       [NSString stringWithFormat:@"after the off, its wait ends without a reveal or an end of the switch, no follow-up (reveals %d; ends %d; follow-ups %d; crash: %@)", gReveals, gEnds, gDones, Crash()]);

    // 2. The same, off while the slide fades to the live screen (the windows changed already); an app opened on the way and a side swipe made on
    //    the way were waiting for its end. Then on again (three desktops kept) and a new switch to Desktop 2 at once, while the old reveal still fades.
    reset(NO, 3);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    gMSWPendingLaunch = @"com.apple.mobilenotes"; gMSWPendingSide = 1;
    RunFor(0.40);   // (landed at 0.35, drawn: the reveal fades for 0.15 s)
    BOOL revealing = gReveals == 1 && gMSWSwitching && gSQChanges.count == 1;
    off();
    printf("-- the other engines: off while the slide fades in; on again and a new switch at once\n");
    ok(revealing, [NSString stringWithFormat:@"set-up: the windows changed (%@), the reveal fades", J(gSQChanges)]);
    ok(!gMSWSwitching && [gSQOpened isEqualToArray:@[@"com.apple.mobilenotes"]] && gMSWPendingSide == 0 && gDones == 0,
       [NSString stringWithFormat:@"the off ends it: the app opened on the way opens now, the side swipe and the follow-up go with it (opened: %@)", J(gSQOpened)]);
    on();
    gSQKeptPic = [UIView new];
    Guard(^{ DMMSWSwitchRun(1, @"after on again", 0, Done()); });
    BOOL newRuns = gMSWSwitching;
    RunFor(0.2);   // (the old reveal's end comes here, the new switch lands only at 0.35)
    BOOL stillRuns = gMSWSwitching;
    RunFor(3.0);
    ok(newRuns && stillRuns, @"on again, a new switch starts at once, and the old reveal's end does not end it");
    ok(!gCaught && gDones == 1 && !gMSWSwitching && gMSWCur == 1 && [gSQChanges isEqualToArray:(@[@"1 -> 2", @"1 -> 2"])] && [gSQOpened isEqualToArray:@[@"com.apple.mobilenotes"]],
       [NSString stringWithFormat:@"the new switch ends by itself, its follow-up once; no switch for the side swipe of the one given up, the app not opened again (changes: %@; follow-ups %d; crash: %@)", J(gSQChanges), gDones, Crash()]);

    // 3. The left desktop's picture asked without waiting is still on its way at the off; the Mac Switcher is on again before it comes
    reset(NO, 2);
    gSQKeptPic = nil;
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, nil); });
    BOOL waiting = gSQPicDone != nil && gSlBegins == 0 && gMSWSwitching;
    RunFor(0.05);
    off();
    on();
    RunFor(0.05);
    if (gSQPicDone) Guard(^{ gSQPicDone([UIView new], 1.0); });   // (the picture comes)
    RunFor(3.0);
    printf("-- the other engines: the left picture still on its way at the off, the Mac Switcher on again before it comes\n");
    ok(waiting, @"set-up: the switch waits for its left picture, no slide yet");
    ok(!gCaught && gSlBegins == 0 && gSQChanges.count == 0 && !gMSWSwitching && !gMSWSlRoot,
       [NSString stringWithFormat:@"the picture coming (or its 0.3 s fallback) begins no slide with no switch behind it, changes nothing (slides %d; changes: %@)", gSlBegins, J(gSQChanges)]);
    gSQKeptPic = [UIView new];
    Guard(^{ DMMSWSwitchRun(1, @"after on again", 0, nil); });
    RunFor(3.0);
    ok(!gCaught && [gSQChanges isEqualToArray:@[@"1 -> 2"]] && !gMSWSwitching && gMSWCur == 1,
       [NSString stringWithFormat:@"a switch asked after that runs as usual (changes: %@)", J(gSQChanges)]);

    // 4. The same with the Mac Switcher's view open (its left picture drawn from its parts, the full-screen app's picture on its way)
    reset(NO, 2);
    gSQKeptPic = nil; gMSWOpen = YES;
    gSQFront = [SBApplication new]; gSQFront.bundleIdentifier = @"com.apple.mobilesafari";
    Guard(^{ DMMSWSwitchRun(1, @"tap in the view", 0, nil); });
    BOOL waiting4 = gSQPicDone != nil && gSlBegins == 0;
    RunFor(0.05);
    off();
    on();
    RunFor(0.05);
    if (gSQPicDone) Guard(^{ gSQPicDone([UIView new], 1.0); });
    RunFor(3.0);
    printf("-- the other engines, the view open: the full-screen app's picture still on its way at the off\n");
    ok(waiting4 && !gCaught && gSlBegins == 0 && gSQChanges.count == 0 && !gMSWSwitching,
       [NSString stringWithFormat:@"the picture coming begins no slide and changes nothing (waiting at the off %d; slides %d; changes: %@)", waiting4, gSlBegins, J(gSQChanges)]);

    // 5. Stage Manager, two desktops: a switch to Desktop 2; Settings off 5 ms later, before its stage is asked for
    reset(YES, 2);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    BOOL smRuns = gMSWSwitching && gMSWSlRoot != nil;
    RunFor(0.005);
    off();
    RunFor(3.0);
    printf("-- Stage Manager: off 5 ms into a switch to Desktop 2, before its stage is asked for\n");
    ok(smRuns, @"set-up: the switch runs, its slide is up");
    ok(!gCaught, [NSString stringWithFormat:@"nothing reads a desktop place past the one left (SpringBoard's crash: %@)", Crash()]);
    ok(!gMSWSwitching && !gMSWSlRoot && gMSWCur == 0 && gReveals == 0 && gDones == 0 && gMSWDesks.count == 1,
       [NSString stringWithFormat:@"the switch ends at the off: no stage asked, no reveal, no follow-up (reveals %d; follow-ups %d)", gReveals, gDones]);

    // 5b. Stage Manager, off after its stage was asked for, before the slide has landed (its wait for the cards runs)
    reset(YES, 2);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    RunFor(0.1);
    BOOL asked5b = gMSWCur == 1 && gMSWSwitching && gReveals == 0;
    off();
    RunFor(3.0);
    printf("-- Stage Manager: off after the stage was asked for, before the slide has landed\n");
    ok(asked5b, @"set-up: the stage was asked for, the slide still on its way");
    ok(!gCaught && gReveals == 0 && gEnds == 0 && gDones == 0 && !gMSWSwitching,
       [NSString stringWithFormat:@"after the off, its wait ends without a reveal or an end of the switch, no follow-up (reveals %d; ends %d; follow-ups %d; crash: %@)", gReveals, gEnds, gDones, Crash()]);

    // 6. Stage Manager, off while the slide fades in; on again and a new switch at once, while the old reveal still fades
    reset(YES, 2);
    Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
    RunFor(0.40);
    BOOL smRevealing = gReveals == 1 && gMSWSwitching && gMSWCur == 1;
    off();
    on();
    Guard(^{ DMMSWSwitchRun(1, @"after on again", 0, Done()); });
    BOOL smNew = gMSWSwitching;
    RunFor(0.2);
    BOOL smStill = gMSWSwitching;
    RunFor(3.0);
    printf("-- Stage Manager: off while the slide fades in; on again and a new switch at once\n");
    ok(smRevealing, @"set-up: the stage was asked for, the reveal fades");
    ok(smNew && smStill && !gCaught && gDones == 1 && !gMSWSwitching && gMSWCur == 1,
       [NSString stringWithFormat:@"the old reveal's end does not end the new switch; the new one ends by itself, one follow-up in all (follow-ups %d; crash: %@)", gDones, Crash()]);

    // 7. Unchanged: a switch with no off runs to its end, on each engine
    for (int sm = 0; sm < 2; sm++) {
        reset(sm, 2);
        Guard(^{ DMMSWSwitchRun(1, @"test", 0, Done()); });
        RunFor(3.0);
        printf("-- unchanged: a switch to Desktop 2 with no off (%s)\n", sm ? "Stage Manager" : "the other engines");
        ok(!gCaught && gDones == 1 && gEnds == 1 && !gMSWSwitching && gMSWCur == 1 && gReveals == 1 && (sm || [gSQChanges isEqualToArray:@[@"1 -> 2"]]) && LogHas(@"during a switch") == 0,
           [NSString stringWithFormat:@"it changes, reveals and ends once, its follow-up once (changes: %@; follow-ups %d)", J(gSQChanges), gDones]);
    }

    // 8. Unchanged: off with no switch running
    reset(NO, 2);
    off();
    RunFor(1.0);
    printf("-- unchanged: off with no switch running\n");
    ok(!gCaught && gMSWDesks.count == 1 && LogHas(@"during a switch") == 0 && !gMSWSwitching, @"one desktop, nothing ended, no crash");
    return gFails;
}}
