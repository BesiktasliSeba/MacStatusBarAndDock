// test-layoutnote.m -- Mac test of the layouts noted for windows across a respring (1.8.2.1, plans/v1821-f1.md; regression 1.8.2 M1 F1). It runs the code as
// built: test-layoutnote.sh cuts out of statusbar/StatusBar.x the window state's entry for a window (DMSaveWindowState) and what the restore does with it where
// it places the window (DMRestoreStep), the note's checks, and Stage Manager's state file (DMSMStateWrite, DMSMTurnLayouts) into layoutnote-gen.h; this file
// gives them stand-ins for UIKit and SpringBoard's stages. The windows as on the M1 (1194 x 834, the Medium bar 30 pt): at the bottom the desktop is
// {0, 30, 1194, 732.27}, with the Dock at the right {0, 30, 1142, 804}. Before 1.8.2.1 a window's layout was in memory only (its view), and a window not shown
// is never noted again until it is: after a respring Tips, Fill on Desktop 2, was in no layout, and a Position round left it 1142 wide at the bottom.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <CoreGraphics/CoreGraphics.h>
#include <unistd.h>
#include "TurnPlace.h"            // (the source's own, copied by test-layoutnote.sh)
#include "../common/DockSide.h"   // (the Position change's keep-out for a window in no layout: MSBDDockSideKeepOut)
#include "SMWindowKey.h"          // (the source's own: DMSMKeysGone, DMSMKeyText)
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit, as far as these read it -----------------------------------------------------------------------------------------------------------------
@interface UIView : NSObject @end
@implementation UIView @end
static NSString *NSStringFromCGRect(CGRect r) { return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s]; }

// ---- Stage Manager's model and our state file, as the writer reads them: a stage is its items, an item its window's key -------------------------------
static NSArray *gStages;
static NSArray *DMSMRecentStages(void) { return gStages; }
static NSDictionary *DMSMStageItemsMap(id al) { return [al isKindOfClass:[NSDictionary class]] ? al : nil; }   // (a stage that can't be read: none)
static NSString *DMSMItemKey(id it) { return it; }
static BOOL DMSMPerWindow(void) { return YES; }
static NSMutableSet<NSString *> *gMin;
static NSMutableSet<NSString *> *DMSMMinimizedSet(void) { return gMin; }
static NSMutableDictionary<NSString *, NSDictionary *> *gSMPreZoomPlaces;
static NSMutableDictionary<NSString *, NSDictionary *> *DMSMPreZoomPlaces(void) { return gSMPreZoomPlaces; }
static NSString *gPath;
static NSString *DMSMStatePath(void) { return gPath; }
static BOOL gMinOnMain = YES;   // (DMSMMinimizedSet asked on the main thread: where the writer makes its dictionary)
static NSMutableSet<NSString *> *DMSMMinimizedSetOnMain(void) { if (![NSThread isMainThread]) gMinOnMain = NO; return gMin; }
#define DMSMMinimizedSet DMSMMinimizedSetOnMain
static NSMutableDictionary<NSString *, id> *gSMPreZoom;   // (DMSMForgetApp's own: the attributes before full screen)
static NSMutableArray<NSString *> *gUnminimized;
static void DMSMSetMinimized(NSString *key, BOOL on) { if (!on) [gUnminimized addObject:key]; }
#define DM_FEATURE_MARK(name) do { } while (0)
static CFTimeInterval CACurrentMediaTime(void) { return CFAbsoluteTimeGetCurrent(); }   // (QuartzCore's, as far as the look's once a second goes)

// (Settings > Dock > Automatically Hide and Show the Dock, 1.8.4 F2: the answer taken now, and the engine -- the reader takes the room the windows were
//  placed for from Stage Manager's file only with the Stage Manager engine)
static int gDMDockAutoHideTaken = -1;
static BOOL gTestSMEngine = YES;
static int gAsked = 0;   // (what Stage Manager's tick asked: the re-review's Low 2)
static BOOL DMSMEngine(void) { gAsked++; return gTestSMEngine; }
// (the review of the fixes, H1 and M1: the Dock part's answer -- -1 while it is not loaded --, and what the start's step and the tick call)
#include "../common/DockAutoHide.h"
static int gTestRoomNow = -1;
static int DMDockRoomNow(void) { return gTestRoomNow; }
static BOOL DMDockAutoHideLive(BOOL *loaded) { if (loaded) *loaded = gTestRoomNow >= 0; return gTestRoomNow > 0; }   // (what 1.8.4 b read instead)
static BOOL DMDockAutoHides(void) { return gTestRoomNow > 0; }
static BOOL gTestBusy = NO;
static BOOL DMSMWorkspaceBusy(void) { return gTestBusy; }
static BOOL DMSwitcherVisible(void) { return NO; }
static NSDictionary *gApplied; static int gPasses = 0, gMoves = 0;
static BOOL DMSMApplyLayouts(NSDictionary<NSString *, NSString *> *layouts) { gApplied = [layouts copy]; return YES; }
static void DMDockAutoHideSMPass(void) { gPasses++; }
static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) { (void)layouts; gMoves++; }
static BOOL gSMHomeOn = NO; static CFTimeInterval gSMHomeStart = 0; static BOOL gTestSMFree = NO;   // (SMHome.h's: an Aerial start below)
static BOOL DMSMFree(void) { gAsked++; return gTestSMFree; }
static double DMProcessAge(void) { gAsked++; return 30.0; }
static BOOL gDMScreenOff = NO;
static BOOL DMSMHomeUILocked(void) { gAsked++; return NO; }
static BOOL DMCoverSheetShown(void) { gAsked++; return NO; }
static void RunFor(double seconds) { CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false); }   // (the main queue's blocks: the step's retries)
#include "layoutnote-gen.h"   // (the code as built)

static NSString *Note(UIView *st) { return objc_getAssociatedObject(st, kStageLayoutNameKey); }
static void SetNote(UIView *st, NSString *n) { objc_setAssociatedObject(st, kStageLayoutNameKey, n, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL Same(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 0.01 && fabs(a.origin.y - b.origin.y) < 0.01 && fabs(a.size.width - b.size.width) < 0.01 && fabs(a.size.height - b.size.height) < 0.01; }
static NSString *Text(CGRect r) { return CGRectIsNull(r) ? @"null" : NSStringFromCGRect(r); }
// A window not shown at a Position change (StatusBar.x DMDockPositionMoved, pinned by test-dockside): into its layout of the new desktop (Fill: the desktop),
// else kept out of the Dock as a move keeps a window (common/DockSide.h). The windows here are as drawn.
static CGRect PositionChange(UIView *st, CGRect drawn, CGRect desktop) {
    NSString *name = Note(st);
    if (!name) return MSBDDockSideKeepOut(drawn, desktop, MSBDDockKeepMove);
    return [name isEqualToString:@"fill"] ? desktop : CGRectNull;
}
static void Respring(void) { gSMTurnLayout = nil; gSMTurnLayoutWritten = nil; gSMTurnFrames = nil; gSMTurnPlaced = nil; gSMTurnStartSettled = NO; }   // (SpringBoard's memory gone; the files stay)
static void Settle(void) { dispatch_sync(DMSMStateWriteQueue(), ^{}); }   // (the writes asked so far are on disk)
static NSDictionary *File(void) { Settle(); return [NSDictionary dictionaryWithContentsOfFile:gPath] ?: @{}; }
// (the state file's writes: on which thread -- swapped in for NSDictionary's own, which it calls)
static int gWritesOnMain = 0, gWritesOff = 0;
static BOOL (*o_writeToFile)(id, SEL, NSString *, BOOL);
static BOOL DMTestWriteToFile(id self, SEL _cmd, NSString *path, BOOL atomically) {
    if ([path isEqualToString:gPath]) { if ([NSThread isMainThread]) gWritesOnMain++; else gWritesOff++; }
    return o_writeToFile(self, _cmd, path, atomically);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gLog = [NSMutableArray array];
        gPath = argc > 1 ? @(argv[1]) : [NSTemporaryDirectory() stringByAppendingPathComponent:@"msbd-test-layoutnote.plist"];
        CGRect bottom = CGRectMake(0, 30, 1194, 732.27), right = CGRectMake(0, 30, 1142, 804);

        // ---- Aerial, Zetsu, MilkyWay4: the window state across a respring ----
        UIView *tips = [UIView new]; SetNote(tips, @"fill");   // (Fill on Desktop 2: noted when it was last on screen)
        NSDictionary *e = DMTestSavedEntry(tips, @"com.apple.tips", CGRectMake(-6, 30, 1206, 744.27), NO);
        Expect([e[@"layout"] isEqual:@"fill"], @"the window state keeps the layout of a window away on another desktop (Tips in Fill on Desktop 2)");
        Expect([e[@"bundle"] isEqual:@"com.apple.tips"] && [e[@"frame"] isEqual:@"{{-6, 30}, {1206, 744.27}}"] && [e[@"minimized"] isEqual:@NO], @"  ... its entry otherwise as before (app, frame, minimized)");
        UIView *tipsAfter = [UIView new];   // (the respring: its app's new window, placed by the restore)
        DMTestRestorePlaced(tipsAfter, e);
        Expect([Note(tipsAfter) isEqual:@"fill"], [NSString stringWithFormat:@"after the respring the restored window is in Fill again (layout %@; 1.8.2: none)", Note(tipsAfter) ?: @"-"]);
        CGRect atRight = PositionChange(tipsAfter, bottom, right), back = PositionChange(tipsAfter, atRight, bottom);
        Expect(Same(atRight, right) && Same(back, bottom), [NSString stringWithFormat:@"  ... so Bottom -> Right -> Bottom: Fill beside the Dock, then 1194 wide again (%@, %@)", Text(atRight), Text(back)]);
        UIView *clock = [UIView new];   // (a window in no layout: only kept out, the rule that left Tips 1142 wide -- F1's numbers)
        CGRect cRight = PositionChange(clock, bottom, right), cBack = PositionChange(clock, cRight, bottom);
        Expect(Same(cRight, CGRectMake(0, 30, 1142, 732.27)) && Same(cBack, CGRectMake(0, 30, 1142, 732.27)), [NSString stringWithFormat:@"a window in no layout is kept out of the Dock only: 1142 x 732.27 at the side and back at the bottom (%@)", Text(cBack)]);
        NSDictionary *ce = DMTestSavedEntry(clock, @"com.apple.mobiletimer", CGRectMake(300, 120, 594, 500), NO);
        UIView *clockAfter = [UIView new]; DMTestRestorePlaced(clockAfter, ce);
        Expect(!ce[@"layout"] && !Note(clockAfter), @"  ... saved and restored in no layout (no entry, none put back)");
        UIView *notes = [UIView new]; SetNote(notes, @"left");   // (minimized into the Dock from the left half)
        NSDictionary *ne = DMTestSavedEntry(notes, @"com.apple.mobilenotes", CGRectMake(-6, 30, 600, 744.27), YES);
        UIView *notesAfter = [UIView new]; DMTestRestorePlaced(notesAfter, ne);
        Expect([ne[@"layout"] isEqual:@"left"] && [ne[@"minimized"] isEqual:@YES] && [Note(notesAfter) isEqual:@"left"], [NSString stringWithFormat:@"a minimized window keeps its layout too (the left half; after the respring %@)", Note(notesAfter) ?: @"-"]);
        UIView *odd = [UIView new]; SetNote(odd, @"medium");   // (no layout of TurnPlace.h: a centred size scales anyway)
        Expect(!DMTestSavedEntry(odd, @"com.apple.Maps", CGRectMake(100, 100, 600, 400), NO)[@"layout"], @"a name that is no layout here is not saved");
        BOOL none = YES;
        for (id bad in @[@"medium", @"Fill", @"", @42, @[@"fill"]]) {
            UIView *st = [UIView new];
            DMTestRestorePlaced(st, @{@"bundle": @"com.apple.Maps", @"frame": @"{{0, 30}, {1194, 732.27}}", @"minimized": @NO, @"layout": bad});
            if (Note(st)) none = NO;
        }
        Expect(none, @"  ... nor put back from a damaged or another build's entry (the window is then in no layout, as one saved without)");

        // ---- Stage Manager: the state file across a respring ----
        Method wm = class_getInstanceMethod([NSDictionary class], @selector(writeToFile:atomically:));
        o_writeToFile = (BOOL (*)(id, SEL, NSString *, BOOL))method_setImplementation(wm, (IMP)DMTestWriteToFile);
        gUnminimized = [NSMutableArray array]; gSMPreZoom = [NSMutableDictionary dictionary];
        NSString *tipsK = @"com.apple.tips|sceneID:com.apple.tips-default", *clockK = @"com.apple.mobiletimer|sceneID:com.apple.mobiletimer-default";
        NSString *mapsK = @"com.apple.Maps|sceneID:com.apple.Maps-default", *notesK = @"com.apple.mobilenotes|sceneID:com.apple.mobilenotes-default";
        gStages = @[ @{clockK: @1}, @{tipsK: @1} ];   // (Desktop 1's stage on screen, Desktop 2's hidden)
        gMin = [NSMutableSet set]; gSMPreZoomPlaces = [NSMutableDictionary dictionary];
        unlink(gPath.fileSystemRepresentation); Respring();
        NSMutableDictionary *lays = DMSMTurnLayouts();
        lays[tipsK] = @"fill"; lays[clockK] = @"left";   // (noted while on screen)
        DMSMStateWrite();
        NSDictionary *file = File();
        Expect([file[@"layouts"][tipsK] isEqual:@"fill"] && [file[@"layouts"][clockK] isEqual:@"left"], @"Stage Manager: the state file keeps the layout of a window on another desktop (its stage hidden)");
        Expect([file[@"minimized"] isEqual:@[]] && !file[@"preZoom"], @"  ... the minimized set and the places before full screen written as before");
        Respring();
        Expect([DMSMTurnLayouts()[tipsK] isEqual:@"fill"], [NSString stringWithFormat:@"after the respring Tips' layout is read back (%@; 1.8.2: none): a Position change puts it into Fill beside the Dock, not only fits it", DMSMTurnLayouts()[tipsK] ?: @"-"]);
        Respring(); [gMin addObject:mapsK]; DMSMStateWrite();   // (a minimize right after the start, before any layout was read)
        file = File();
        Expect([file[@"minimized"] isEqual:@[mapsK]] && [file[@"layouts"][tipsK] isEqual:@"fill"], @"  ... a minimized-set write right after a start keeps the layouts (read first, the one writer)");
        [gMin removeAllObjects];
        // review finding 1: a write never drops a note on its own -- a window for a moment in no stage (a write inside a workspace transition: a full desktop's
        // oldest window left out) keeps its note, and memory, what was written and the file agree
        gStages = @[ @{tipsK: @1} ];
        DMSMStateWrite(); file = File();
        Expect([file[@"layouts"][clockK] isEqual:@"left"], [NSString stringWithFormat:@"review 1: a window for a moment in no stage keeps its note in the file (%@)", file[@"layouts"][clockK] ?: @"dropped"]);
        Expect([gSMTurnLayoutWritten isEqualToDictionary:DMSMTurnLayouts()] && [file[@"layouts"] isEqualToDictionary:DMSMTurnLayouts()], @"  ... memory, what was written and the file agree");
        // review finding 2: a closed window's records go with it, memory and the file together
        gStages = @[ @{clockK: @1}, @{tipsK: @1} ]; Respring(); (void)DMSMTurnLayouts();
        CGRect clockL = CGRectMake(0, 20, 680, 907); gSMTurnFrames = [@{clockK: @{@"L": [NSValue valueWithBytes:&clockL objCType:@encode(CGRect)]}} mutableCopy];
        gStages = @[ @{clockK: @1} ];   // (Tips quit from the App Switcher: no stage has it)
        DMSMTurnForgetClosed();
        Expect([DMSMTurnLayouts()[tipsK] isEqual:@"fill"], @"review 2: nothing is taken for closed before the start has settled");
        gSMTurnStartSettled = YES; DMSMTurnForgetClosed(); file = File();
        Expect(!DMSMTurnLayouts()[tipsK] && !file[@"layouts"][tipsK], [NSString stringWithFormat:@"review 2: a closed window's note goes from memory and the file (Tips, %@ / %@): its app's next window on that scene is a new one", DMSMTurnLayouts()[tipsK] ?: @"-", file[@"layouts"][tipsK] ?: @"-"]);
        Expect([DMSMTurnLayouts()[clockK] isEqual:@"left"] && [file[@"layouts"][clockK] isEqual:@"left"] && gSMTurnFrames[clockK], @"  ... a window still in a stage keeps its own (Clock's note and places)");
        DMSMTurnLayouts()[mapsK] = @"right"; gStages = @[ @{clockK: @1}, @{mapsK: @1} ]; DMSMTurnForgetClosed();
        Expect([DMSMTurnLayouts()[mapsK] isEqual:@"right"], @"  ... one in a hidden stage only (minimized, another desktop's) is not closed");
        gStages = @[ @{clockK: @1}, [NSNull null] ]; DMSMTurnLayouts()[notesK] = @"top"; DMSMTurnForgetClosed();
        BOOL keptAll = [DMSMTurnLayouts()[notesK] isEqual:@"top"] && [DMSMTurnLayouts()[mapsK] isEqual:@"right"];
        gStages = @[]; DMSMTurnForgetClosed();
        Expect(keptAll && [DMSMTurnLayouts()[notesK] isEqual:@"top"], @"  ... none is taken for closed when a stage can't be read or none is (SpringBoard's model not there)");
        gStages = @[ @{clockK: @1}, @{mapsK: @1}, @{notesK: @1} ];
        DMSMTurnLayouts()[tipsK] = @"fill"; DMSMStateWrite();
        DMSMForgetApp(@"com.apple.tips"); file = File();
        Expect(!DMSMTurnLayouts()[tipsK] && !file[@"layouts"][tipsK] && [gUnminimized containsObject:@"com.apple.tips"], @"review 2: a force quit (DMSMForgetApp) takes the app's notes along, memory and the file, as its minimized marks");
        // review finding 3: the file is written off the main thread, in order
        gWritesOnMain = gWritesOff = 0; [gMin addObject:clockK]; DMSMStateWrite(); [gMin removeAllObjects]; DMSMStateWrite(); file = File();
        Expect(gWritesOff == 2 && gWritesOnMain == 0, [NSString stringWithFormat:@"review 3: the file is written off the main thread (%d there, %d on it), as the window state is", gWritesOff, gWritesOnMain]);
        Expect([file[@"minimized"] isEqual:@[]], @"  ... in order: the last write is the one on disk");
        // review finding 4: a call from another thread is made on the main thread
        gMinOnMain = YES; __block BOOL returned = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [gMin addObject:notesK]; DMSMStateWrite(); returned = YES; });
        for (int i = 0; i < 200 && !returned; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
        for (int i = 0; i < 20; i++) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);   // (the main thread's turn)
        file = File();
        Expect(gMinOnMain && [file[@"minimized"] isEqual:@[notesK]], [NSString stringWithFormat:@"review 4: a call from another thread is made on the main thread, where the notes are kept (%@)", gMinOnMain ? @"main" : @"made off it"]);
        [gMin removeAllObjects];
        [@{@"minimized": @[], @"layouts": @{tipsK: @"fill", clockK: @"medium", mapsK: @3, @"": @"left", notesK: @"Right"}} writeToFile:gPath atomically:YES];
        Respring();
        Expect([DMSMTurnLayouts() isEqualToDictionary:@{tipsK: @"fill"}], [NSString stringWithFormat:@"a damaged or another build's entry is dropped as it is read, the good one kept (%lu read)", (unsigned long)DMSMTurnLayouts().count]);
        [@{@"minimized": @[], @"layouts": @[tipsK, @"fill"]} writeToFile:gPath atomically:YES];
        Respring();
        Expect(DMSMTurnLayouts().count == 0, @"  ... and \"layouts\" that are not a dictionary give none");
        // regression 1.8.4 F2: the Dock's room the windows are placed for (Automatically Hide and Show the Dock) is kept with the notes, and read back at
        // the start, so a start where it changed meanwhile -- the crash guard turned it off -- places the windows for the room as it is
        unlink(gPath.fileSystemRepresentation); Respring(); gDMWindowsRoomPending = -1; gDMDockAutoHideTaken = 1; gTestRoomNow = 1;   // (auto-hide on: Fill with the freed room)
        DMSMStateWrite(); file = File();
        Expect([file[@"dockAutoHide"] isEqual:@1], [NSString stringWithFormat:@"1.8.4 F2: the state file keeps the Dock's room the windows are placed for (auto-hide on: %@)", file[@"dockAutoHide"] ?: @"none"]);
        Respring(); gDMDockAutoHideTaken = 0; gTestRoomNow = 0;   // (the next start: the crash guard turned it off)
        (void)DMSMTurnLayouts();
        Expect(gDMWindowsRoomPending == 1, [NSString stringWithFormat:@"  ... read back at the start as the room they were placed for (%d), to tell it from the answer taken now (0)", gDMWindowsRoomPending]);
        DMSMStateWrite(); file = File();
        Expect([file[@"dockAutoHide"] isEqual:@1], @"  ... and written as that until the windows are placed for the room as it is (a write meanwhile keeps it)");
        gDMWindowsRoomPending = -1; DMSMStateWrite(); file = File();
        Expect([file[@"dockAutoHide"] isEqual:@0], @"  ... then as the answer taken now (0)");
        gTestSMEngine = NO; Respring(); gDMWindowsRoomPending = -1; (void)DMSMTurnLayouts();
        Expect(gDMWindowsRoomPending == -1, @"  ... read only with the Stage Manager engine (another engine's start leaves Stage Manager's file alone)");
        gTestSMEngine = YES; gDMDockAutoHideTaken = -1;
        // the review of the fixes, M1: the start's step for Stage Manager reads the room saved with the notes before it compares -- nothing read the file
        // before it (every window minimized or on another desktop: no note was taken)
        NSDictionary *saved = @{@"minimized": @[], @"layouts": @{tipsK: @"fill"}, @"dockAutoHide": @1};
        [saved writeToFile:gPath atomically:YES]; Respring(); gDMWindowsRoomPending = -1; gTestRoomNow = 0; gDMDockAutoHideTaken = 0; gApplied = nil; gMoves = gPasses = 0;
        DMDockRoomAfterStartSMTry(0); file = File();
        Expect([gApplied isEqualToDictionary:@{tipsK: @"fill"}] && gMoves == 1, [NSString stringWithFormat:@"M1: placed with the Dock hiding itself and shown now, the start's step puts Tips into Fill for the room as it is, the rest kept out of the Dock (layouts %@, moves %d)", gApplied ?: @"none", gMoves]);
        Expect(gDMWindowsRoomPending == -1 && [file[@"dockAutoHide"] isEqual:@0], [NSString stringWithFormat:@"  ... then nothing pending, and the answer they are placed for now written (%@)", file[@"dockAutoHide"] ?: @"none"]);
        [saved writeToFile:gPath atomically:YES]; Respring(); gDMWindowsRoomPending = -1; gTestRoomNow = -1; gDMDockAutoHideTaken = -1; gApplied = nil; gMoves = gPasses = 0;
        DMDockRoomAfterStartSMTry(30); file = File();   // (its last try)
        Expect(!gApplied && gMoves == 0 && gDMWindowsRoomPending == 1, [NSString stringWithFormat:@"M1: the Dock part's answer not known (not loaded): nothing placed, the room stays pending (%d)", gDMWindowsRoomPending]);
        DMSMStateWrite(); file = File();
        Expect([file[@"dockAutoHide"] isEqual:@1], [NSString stringWithFormat:@"  ... and a write meanwhile keeps the saved answer: the key is never dropped (%@)", file[@"dockAutoHide"] ?: @"dropped"]);
        [saved writeToFile:gPath atomically:YES]; Respring(); gDMWindowsRoomPending = -1; gTestRoomNow = 1; gDMDockAutoHideTaken = 1; gApplied = nil; gMoves = gPasses = 0;
        DMDockRoomAfterStartSMTry(0); file = File();
        Expect(!gApplied && gMoves == 0 && gPasses == 0 && gDMWindowsRoomPending == -1 && [file[@"dockAutoHide"] isEqual:@1], @"  ... the same answer as saved: nothing placed, nothing pending, the answer written as it was");
        // the review of the fixes, H1: Stage Manager's start tick runs on an iPad that can run Stage Manager whichever engine is picked -- an Aerial start's
        // restore has read the room (pending): the tick leaves it to that restore
        gTestSMEngine = NO; gTestSMFree = NO; gSMHomeOn = NO; gSMHomeStart = 0; gDMWindowsRoomPending = 1; gTestRoomNow = 0; gApplied = nil; gMoves = 0;
        for (int i = 0; i < 25; i++) DMSMRoomTick();
        Expect(gDMWindowsRoomPending == 1 && !gApplied && gMoves == 0, [NSString stringWithFormat:@"H1: an Aerial start: Stage Manager's tick leaves the room pending for Aerial's restore (%d after 25 ticks)", gDMWindowsRoomPending]);
        gTestSMEngine = YES; gTestSMFree = YES; gSMHomeOn = YES; gSMHomeStart = 1; DMSMRoomTick();
        Expect(gDMWindowsRoomPending == 1 && !gApplied, @"  ... the Stage Manager engine: kept for the desktop's own step (it follows once the desktop is back)");
        // the re-review of the fixes, Low 2: nothing pending, the tick asks nothing (it runs for SpringBoard's whole life)
        gDMWindowsRoomPending = -1; gAsked = 0;
        for (int i = 0; i < 25; i++) DMSMRoomTick();
        Expect(gAsked == 0, [NSString stringWithFormat:@"Low 2: nothing pending: the tick asks nothing (%d questions in 25 ticks)", gAsked]);
        // L3: where the desktop's own step does not run, the tick follows through the start step's own entry; while the Dock part does not answer, its
        // retries wait, then place the windows for the room as it is (the step's retry chain as built, from the room the file was read with)
        [saved writeToFile:gPath atomically:YES]; Respring(); gDMWindowsRoomPending = -1; (void)DMSMTurnLayouts();   // (the file read: pending 1)
        gTestSMEngine = YES; gTestSMFree = YES; gSMHomeOn = NO; gSMHomeStart = 0; gTestRoomNow = -1; gApplied = nil; gMoves = 0;
        DMSMRoomTick();
        Expect(gDMWindowsRoomPending == 1 && !gApplied && gMoves == 0, @"  ... where that step does not run here, the tick follows through the start step's entry: the Dock part not answering, nothing placed yet");
        RunFor(1.2); gTestRoomNow = 0; RunFor(1.5); file = File();
        Expect([gApplied isEqualToDictionary:@{tipsK: @"fill"}] && gMoves == 1 && gDMWindowsRoomPending == -1 && [file[@"dockAutoHide"] isEqual:@0],
               [NSString stringWithFormat:@"  ... its retries place the windows for the room as it is once it answers (Tips into Fill: %@), and write the answer (%@)", gApplied ?: @"nothing", file[@"dockAutoHide"] ?: @"none"]);
        gDMWindowsRoomPending = 1; gTestSMFree = NO; DMSMRoomTick();
        Expect(gDMWindowsRoomPending == -1, @"  ... Stage Manager's own placing (ours off): dropped, no layouts of ours to follow");
        gTestSMEngine = YES; gTestSMFree = NO; gSMHomeOn = NO; gSMHomeStart = 0; gTestRoomNow = -1; gDMDockAutoHideTaken = -1;
        method_setImplementation(wm, (IMP)o_writeToFile);
        unlink(gPath.fileSystemRepresentation);
    }
    printf("%s: %d checks, %d failed\n", fails ? "test-layoutnote run FAILED" : "test-layoutnote run: all pass", checks, fails);
    return fails ? 1 : 0;
}
