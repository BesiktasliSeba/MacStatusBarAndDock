// test-ctornouikit-back.m -- see test-ctornouikit.sh (c). The Mac Switcher on at SpringBoard's start with desktops kept from its last off still in
// their file (DMMSWApplyPref from StatusBar.x's %ctor -> DMMSWBringBack): the real code cut out of statusbar/MacSwitcher.h (ct-back.inc: from
// DMMSWBringBack to the end of what it runs), with the real MSWKept.h deciding what comes back, run on stand-ins: UIScreen (a class of that name
// here, no UIKit: every +mainScreen counted, inside the constructor or after it), the engine (DMSMEngine: as the constructor reads it and as it
// reads later), SpringBoard's stages and the engine's windows (DMMSWSMStagesNow, DMMSWSMAlive, DMAerialStagesAll: counted; nothing there while the
// constructor runs, as before SpringBoard's main; half restored by the first main-queue turn -- the coordinator made by SpringBoard's launch, one of
// the kept windows back, one window new), the kept file, DMMSWApply and DMMSWSave (counted).
// The start must ask no screen from the constructor (GitHub #16) and bring back what it brought back from the constructor in 1.8.7.5: the engine
// as read there, nothing told and no stage or window read (none was there), so every kept window comes back and DMMSWApply is left to the tick
// (review of the #16 fix, F1: read at the first main-queue turn, a half-restored stage list dropped the kept windows not in it yet, and DMMSWApply
// asked SpringBoard for stage transitions while it started). The switch-on later (no constructor) reads and tells as before.
// A scenario: start.sm (Stage Manager, its switch readable in the constructor), start.sm-late (Stage Manager, not readable yet in the constructor:
// the engine as the constructor read it, NO), start.aerial, start.off (switched off again before the main queue turns), start.sm-nokept (no kept
// copy) and start.sm-desks2 (the desktops file holds two already: the kept copy goes) -- there the constructor reads no engine, as before --,
// live.sm, live.aerial.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include "MSWKept.h"   // (the tree's own, copied beside the cut: SMWindowKey.h with it)

static BOOL gDMInCtor = NO;   // (StatusBar.x's: set by the constructor below)
static BOOL gMSWOn = NO;
static NSMutableArray<NSString *> *gLog;
static void TLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; if (getenv("CT_LOG")) printf("   log: %s\n", s.UTF8String); }
#if DEBUG
#define DMLog(...) TLog(__VA_ARGS__)
#else
#define DMLog(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)   // (as StatusBar.x's release DMLog)
#endif
#define DM_FEATURE_MARK(x) do {} while (0)

// ---- UIScreen: the iPad's, landscape now; every ask counted
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
@property (nonatomic, readonly) CGRect bounds;
@end
static int gAskedInCtor, gAskedAfter;
@implementation UIScreen
+ (UIScreen *)mainScreen { if (gDMInCtor) gAskedInCtor++; else gAskedAfter++; static UIScreen *s; if (!s) s = [UIScreen new]; return s; }
- (CGRect)bounds { return CGRectMake(0, 0, 1366, 1024); }
@end
static NSString *TSize(CGSize s) { return [NSString stringWithFormat:@"{%g, %g}", s.width, s.height]; }
#define NSStringFromCGSize(s) TSize(s)

// ---- an engine window (Aerial / Zetsu / MilkyWay4): a view of an app
@interface UIView : NSObject
@property (nonatomic, copy) NSString *bundle;
@end
@implementation UIView
@end
static NSString *DMStageBundle(UIView *s) { return s.bundle; }

// ---- the Mac Switcher's state (MacSwitcher.h's, plain here: the iPad's model only, no other display)
@interface DMMSWModel : NSObject
@end
@implementation DMMSWModel
@end
static DMMSWModel *gMSWMain;
static NSMutableDictionary<NSString *, DMMSWModel *> *gMSWModels;
static DMMSWModel *MSWDispOwner(NSNumber *desk, DMMSWModel *main, NSDictionary<NSString *, DMMSWModel *> *displays) { return nil; }
static NSMutableArray<NSNumber *> *gMSWDesks;
static NSUInteger gMSWCur;
static NSDictionary *gMSWKept;
static NSMutableDictionary *gMSWWinDesk, *gMSWWinFrame, *gMSWFullScreen, *gMSWLeftSize, *gMSWFit, *gMSWAsideDesk, *gMSWAsideFrame, *gMSWShots, *gMSWShotSet;
static BOOL gMSWDesksDirty;
static const NSUInteger kMSWMaxDesks = 8;
static NSString *gKeptPath;
static NSString *DMMSWKeptPath(void) { return gKeptPath; }
static BOOL DMMSWForMain(void) { return YES; }
static NSString *DMMSWDeskName(NSUInteger i) { return [NSString stringWithFormat:@"Desktop %lu", (unsigned long)i + 1]; }
static void MSWAsideRead(NSDictionary *st, NSMutableDictionary *aside, NSMutableDictionary *asideFrames) {}
static NSDictionary *DMMSWFitWithout(NSDictionary *fit, NSString *b) { return nil; }
static NSMutableArray<NSString *> *gPrewarmQuitSet;
static BOOL gWindowSaveOn = NO, gRestoringWindows = NO;
static int gApplied, gApplyInCtor, gSaved;
static void DMMSWApply(void) { gApplied++; if (gDMInCtor) gApplyInCtor++; }
static void DMMSWSave(void) { gSaved++; }
static void DMMSWAsync(dispatch_block_t b) { dispatch_async(dispatch_get_main_queue(), b); }   // (MacSwitcher.h's runs it under the model it was asked under)

// ---- the engine and what SpringBoard has: nothing while the constructor runs (before SpringBoard's main); after it, half restored
static BOOL gSMInCtor, gSMLater, gSBUp;
static int gEngineReadsInCtor, gStageReads, gStageReadsInCtor;
static NSString *K(NSString *b) { return [NSString stringWithFormat:@"%@|sceneID:%@-1", b, b]; }
#define APP_A @"com.apple.mobilenotes"
#define APP_B @"com.apple.mobiletimer"
#define APP_C @"com.apple.calculator"
#define APP_D @"com.apple.weather"
#define APP_E @"com.apple.Maps"
#define APP_X @"com.apple.tips"
static BOOL DMSMEngine(void) { if (gDMInCtor) { gEngineReadsInCtor++; return gSMInCtor; } return gSMLater; }
static void StageRead(void) { gStageReads++; if (gDMInCtor) gStageReadsInCtor++; }
static NSUInteger DMMSWSMStagesNow(NSMutableArray<NSArray<NSString *> *> *stages) {
    StageRead();
    if (!gSBUp) return NSNotFound;
    [stages addObject:@[K(APP_A)]]; [stages addObject:@[K(APP_D)]];   // (A's stage back, D's new and on screen; B's and C's not restored yet)
    return 1;
}
static NSMutableSet<NSString *> *gMinimized;
static NSMutableSet<NSString *> *DMSMMinimizedSet(void) { return gMinimized; }
static BOOL DMMSWSMAlive(NSMutableSet<NSString *> *keys, NSMutableSet<NSString *> *apps) {
    StageRead();
    if (!gSBUp) return NO;
    for (NSString *k in @[K(APP_A), K(APP_D)]) { [keys addObject:k]; [apps addObject:DMSMKeyBundle(k)]; }
    for (NSString *k in gMinimized) { [keys addObject:k]; [apps addObject:DMSMKeyBundle(k)]; }
    return YES;
}
static NSArray<UIView *> *DMAerialStagesAll(void) {
    StageRead();
    if (!gSBUp) return @[];
    UIView *a = [UIView new], *d = [UIView new]; a.bundle = APP_A; d.bundle = APP_D;
    return @[a, d];
}
static NSSet<NSString *> *DMLiveRunningBundleIDs(void) { return [NSSet setWithArray:@[APP_A, APP_D]]; }

#include "ct-back.inc"   // (the real DMMSWBringBack and what it runs, MacSwitcher.h)

static int gPass, gFail;
static const char *gScen;
static void Check(BOOL ok, NSString *what) { if (ok) gPass++; else gFail++; printf("%s  %s: %s\n", ok ? "PASS" : "FAIL", gScen, what.UTF8String); }
static NSString *Desks(void) { return [gMSWDesks componentsJoinedByString:@","]; }
static NSString *D(NSDictionary *d) {   // (one line: key=value, sorted)
    NSMutableArray *o = [NSMutableArray array];
    for (id k in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) [o addObject:[NSString stringWithFormat:@"%@=%@", k, d[k]]];
    return [NSString stringWithFormat:@"{%@}", [o componentsJoinedByString:@" "]];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *all[] = { "start.sm", "start.sm-late", "start.aerial", "start.off", "start.sm-nokept", "start.sm-desks2", "live.sm", "live.aerial" };
        if (argc > 1 && !strcmp(argv[1], "list")) { for (int i = 0; i < 8; i++) printf("%s\n", all[i]); return 0; }
        if (argc < 2) { printf("FAIL  usage: %s list | <scenario>\n", argv[0]); return 2; }
        gScen = argv[1];
        NSString *scen = @(argv[1]);
        BOOL start = [scen hasPrefix:@"start."], smEngine = [scen hasSuffix:@".sm"] || [scen rangeOfString:@".sm-"].location != NSNotFound, off = [scen isEqualToString:@"start.off"];
        BOOL noKept = [scen isEqualToString:@"start.sm-nokept"], desks2 = [scen isEqualToString:@"start.sm-desks2"];
        if (![@[@"start.sm", @"start.sm-late", @"start.aerial", @"start.off", @"start.sm-nokept", @"start.sm-desks2", @"live.sm", @"live.aerial"] containsObject:scen]) { printf("FAIL  no scenario %s\n", argv[1]); return 2; }
        gSMInCtor = smEngine && ![scen hasSuffix:@".sm-late"]; gSMLater = smEngine;
        BOOL smThen = start ? gSMInCtor : gSMLater;   // (the engine as the bring-back must see it: the constructor's reading at the start)
        gMSWMain = [DMMSWModel new]; gMSWModels = [NSMutableDictionary dictionary];
        gMSWDesks = desks2 ? [@[@1, @2] mutableCopy] : [NSMutableArray arrayWithObject:@1]; gMSWCur = 0;   // (DMMSWLoad: one desktop, the Mac Switcher was off)
        NSString *desksBefore = desks2 ? @"1,2" : @"1";
        gMSWWinDesk = [NSMutableDictionary dictionary]; gMSWWinFrame = [NSMutableDictionary dictionary]; gMSWFullScreen = [NSMutableDictionary dictionary];
        gMSWLeftSize = [NSMutableDictionary dictionary]; gMSWFit = [NSMutableDictionary dictionary]; gMSWAsideDesk = [NSMutableDictionary dictionary];
        gMSWAsideFrame = [NSMutableDictionary dictionary]; gMSWShots = [NSMutableDictionary dictionary]; gMSWShotSet = [NSMutableDictionary dictionary];
        gMinimized = smEngine ? [NSMutableSet setWithObject:K(APP_E)] : [NSMutableSet set];
        // the kept copy (DMMSWKeepForLater at the last off): three desktops, A on 1, B on 2, C on 3, X full screen on 3, Desktop 2 current then
        NSString *(^key)(NSString *) = ^NSString *(NSString *b) { return smEngine ? K(b) : b; };
        NSDictionary *kept = @{@"desktops": @[@1, @2, @3], @"current": @2, @"windows": @{key(APP_A): @1, key(APP_B): @2, key(APP_C): @3},
                               @"frames": @{}, @"fullscreen": @{@"3": APP_X}, @"leftSizes": @{@"2": @"{1024, 1366}", @"3": @"{1024, 1366}"}, @"fit": @{}};
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ct-back.%d", getpid()]];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:tmp withIntermediateDirectories:YES attributes:nil error:nil]) { printf("FAIL  no temp dir\n"); return 2; }
        gKeptPath = [tmp stringByAppendingPathComponent:@"kept.plist"];
        if (!noKept) [kept writeToFile:gKeptPath atomically:YES];
        void (^done)(void) = ^{ [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil]; printf("%d passed, %d failed\n", gPass, gFail); exit(gFail ? 1 : 0); };

        if (!start) {
            // ---- the switch on later (no constructor): SpringBoard up, the stages and windows read, told -- as before the change
            gSBUp = YES; gMSWOn = YES; gWindowSaveOn = !smEngine;
            DMMSWBringBack();
            Check([Desks() isEqualToString:@"1,2,3"], [NSString stringWithFormat:@"the kept desktops back at once (%@)", Desks()]);
            Check(gStageReads >= 1, [NSString stringWithFormat:@"what is there now read (%d read(s))", gStageReads]);
            Check(gApplied == 1 && gSaved == 1, [NSString stringWithFormat:@"told: applied and saved once (%d, %d)", gApplied, gSaved]);
            Check([gMSWWinDesk[key(APP_A)] isEqual:@1] && [gMSWWinDesk[key(APP_D)] isEqual:@1], [NSString stringWithFormat:@"A back on Desktop 1, D new on Desktop 1 (%@)", D(gMSWWinDesk)]);
            if (smEngine) Check(!gMSWWinDesk[K(APP_B)] && !gMSWWinDesk[K(APP_C)], [NSString stringWithFormat:@"Stage Manager: B and C in no stage, left out (told) (%@)", D(gMSWWinDesk)]);
            else Check([gMSWWinDesk[APP_B] isEqual:@2] && [gMSWWinDesk[APP_C] isEqual:@3], [NSString stringWithFormat:@"Aerial: B and C not quit, kept (%@)", D(gMSWWinDesk)]);
            Check(gAskedAfter == 1, [NSString stringWithFormat:@"the screen asked once (%d)", gAskedAfter]);
            Check(![[NSFileManager defaultManager] fileExistsAtPath:gKeptPath], @"the kept file read once and gone");
            done();
        }

        // ---- the constructor (StatusBar.x %ctor -> DMLoadPrefs -> DMMSWApplyPref: DMMSWLoad, then DMMSWBringBack)
        gDMInCtor = YES; gMSWOn = YES;
        DMMSWBringBack();
        gDMInCtor = NO;
        Check(gAskedInCtor == 0, [NSString stringWithFormat:@"UIScreen not asked while the constructor runs (asked %d time(s))", gAskedInCtor]);
        Check(gApplyInCtor == 0, [NSString stringWithFormat:@"no apply (windows made or listed) from the constructor (%d)", gApplyInCtor]);
        Check(gStageReadsInCtor == 0, [NSString stringWithFormat:@"no stage or window read from the constructor (%d)", gStageReadsInCtor]);
        Check([Desks() isEqualToString:desksBefore] && [[NSFileManager defaultManager] fileExistsAtPath:gKeptPath] == !noKept, [NSString stringWithFormat:@"nothing brought back or read inside the constructor (desktops %@, the kept file %s)", Desks(), noKept ? "never there" : "there"]);
        // ---- SpringBoard's main and launch, before the first main-queue turn: the coordinator made, A's stage back, D new; B and C not yet
        gSBUp = YES;
        if (off) gMSWOn = NO;   // (switched off again before the main queue turned: its own off path, not this)

        dispatch_async(dispatch_get_main_queue(), ^{
            if (noKept || desks2) {   // (nothing to bring back: the engine never read in the constructor, as before -- 1.8.7.5 read it only with a kept copy and one desktop)
                Check(gEngineReadsInCtor == 0, [NSString stringWithFormat:@"%@: the engine not read in the constructor (%d)", noKept ? @"no kept copy" : @"two desktops already", gEngineReadsInCtor]);
                Check([Desks() isEqualToString:desksBefore] && gSaved == 0 && gApplied == 0 && gStageReads == 0, [NSString stringWithFormat:@"... nothing brought back, saved, applied or read (desktops %@)", Desks()]);
                Check(gAskedAfter == 0, [NSString stringWithFormat:@"... the screen not asked (%d)", gAskedAfter]);
                Check(![[NSFileManager defaultManager] fileExistsAtPath:gKeptPath], @"... no kept file left (two desktops: the kept copy goes, as before)");
                done();
            }
            if (off) {
                Check([Desks() isEqualToString:@"1"] && gSaved == 0 && gApplied == 0, [NSString stringWithFormat:@"switched off before the turn: nothing brought back (%@)", Desks()]);
                Check([[NSFileManager defaultManager] fileExistsAtPath:gKeptPath], @"... the kept file stays for the next on");
                done();
            }
            Check([Desks() isEqualToString:@"1,2,3"], [NSString stringWithFormat:@"after one main-queue turn the kept desktops are back (%@)", Desks()]);
            Check([gMSWWinDesk[key(APP_A)] isEqual:@1] && [gMSWWinDesk[key(APP_B)] isEqual:@2] && [gMSWWinDesk[key(APP_C)] isEqual:@3],
                  [NSString stringWithFormat:@"every kept window back on its desktop, B and C too though not back in SpringBoard yet (not told, as from the constructor) (%@)", D(gMSWWinDesk)]);
            Check(!gMSWWinDesk[key(APP_D)], [NSString stringWithFormat:@"no window taken as new since (none was there in the constructor) (%@)", D(gMSWWinDesk)]);
            Check(gMSWCur == 0, [NSString stringWithFormat:@"the current desktop is Desktop 1 (%lu)", (unsigned long)gMSWCur]);
            Check(gStageReads == 0, [NSString stringWithFormat:@"SpringBoard's stages and the engine's windows not read while it starts (%d read(s))", gStageReads]);
            Check(gApplied == 0, [NSString stringWithFormat:@"no apply at the start: the tick applies the desktops (%d)", gApplied]);
            Check(gSaved == 1, [NSString stringWithFormat:@"saved once (%d)", gSaved]);
            Check([gMSWFullScreen[@"3"] isEqual:APP_X], [NSString stringWithFormat:@"Desktop 3's full-screen app kept (%@)", D(gMSWFullScreen)]);
            Check(gEngineReadsInCtor == 1, [NSString stringWithFormat:@"the engine read in the constructor, where it was read before (%d)", gEngineReadsInCtor]);
            if (smThen) {
                Check([gMSWWinDesk[K(APP_E)] isEqual:@1], [NSString stringWithFormat:@"Stage Manager as the engine: the minimized window on Desktop 1 (%@)", D(gMSWWinDesk)]);
                Check([gMSWLeftSize isEqual:(@{@"2": @"{1024, 1366}", @"3": @"{1024, 1366}"})], [NSString stringWithFormat:@"... the other desktops' sizes as kept (%@)", D(gMSWLeftSize)]);
            } else {
                Check(!gMSWWinDesk[K(APP_E)], [NSString stringWithFormat:@"the engine as the constructor read it (%s): no Stage Manager minimized window added (%@)", smEngine ? "Stage Manager not readable yet" : "Aerial", D(gMSWWinDesk)]);
                Check([gMSWLeftSize isEqual:(@{@"2": @"{1366, 1024}", @"3": @"{1366, 1024}"})], [NSString stringWithFormat:@"... the other desktops at the screen as it is (%@)", D(gMSWLeftSize)]);
            }
            Check(gAskedAfter == 1, [NSString stringWithFormat:@"the screen asked once, after the constructor (%d)", gAskedAfter]);
            Check(![[NSFileManager defaultManager] fileExistsAtPath:gKeptPath], @"the kept file read once and gone");
            done();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ printf("FAIL  the main queue never turned\n"); exit(3); });
        dispatch_main();
    }
}
