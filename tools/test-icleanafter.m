// test-icleanafter.m -- Mac test of Clean and Respring's result after the respring (1.8.8.1). Two parts, run as they are:
//  A. common/ICleaner.h's rules: the record kept just before the respring, a SpringBoard's look at it (whose it is, how old, which start), the
//     10 minutes, the crash reports since the respring (a folder of the test's own).
//  B. the glue, cut out of statusbar/ICleanerPanel.h by test-icleanafter.sh (ia-glue.inc: the keep, the hold, the respring's two blocks, the look
//     and the tick's part, without the five functions that reach outside), over simulated SpringBoards: our preferences are one dictionary, each
//     SpringBoard's pid and start, the clock, the blocker (locked, a menu...) and the crash look are the test's. It shows the result kept before the
//     respring, taken by the respring's SpringBoard and shown once after the unlock (never over the Lock Screen, never twice), not after 10 min,
//     not after a crash in between, not by a later start, by the asking SpringBoard when its respring never came, and at once when the VPN
//     warning's Cancel leaves the respring undone.
#import <Foundation/Foundation.h>
#include <unistd.h>
#include "common/ICleaner.h"

static int fails = 0, checks = 0;
static void ok(NSString *what, BOOL cond) { checks++; if (!cond) { fails++; printf("FAIL %s\n", what.UTF8String); } }

// ---- what the glue reaches outside, stood in for ------------------------------------------------------------------------------------------------
static BOOL gFinderOn = YES;
static NSMutableDictionary *gStore;   // our preferences (kMSBDEjectDomain)
static double gNow = 0, gStarted = 0;  // the clock; this SpringBoard's start
static int gPid = 0;                   // this SpringBoard's pid
static NSString *gBlocker = nil;       // what DMFinderICleanAfterBlocker says (nil: nothing in the way)
static BOOL gCrashed = NO;             // a SpringBoard crash report since the respring
static int gCrashLooks = 0, gMarks = 0, gRespringsAsked = 0;
static dispatch_block_t gRespringFirst, gRespringOtherwise;
static NSMutableArray<NSArray *> *gPanels;   // (state, text, Respring offered) of each panel shown
#define DMLog(...) do { if (getenv("IA_VERBOSE")) printf("    log: %s\n", [(NSString *)(__VA_ARGS__) UTF8String]); } while (0)
#define DM_FEATURE_MARK(name) do { gMarks++; } while (0)
#define DMTestFlag(path) 0
#define getpid() gPid
static id DMFinderICleanStoreRead(void) { return gStore[@kMSBDICleanAfterKey]; }
static void DMFinderICleanStoreWrite(NSDictionary *rec) { if (rec) gStore[@kMSBDICleanAfterKey] = rec; else [gStore removeObjectForKey:@kMSBDICleanAfterKey]; }
static double DMFinderICleanNow(void) { return gNow; }
static double DMFinderICleanStarted(void) { return gStarted; }
static BOOL DMFinderICleanCrashSince(double since) { gCrashLooks++; return gCrashed; }
static NSString *DMFinderICleanAfterBlocker(void) { return gBlocker; }
static void DMRespringCheckedOr(dispatch_block_t first, dispatch_block_t otherwise) { gRespringsAsked++; gRespringFirst = first; gRespringOtherwise = otherwise; }
static void DMICleanShowPanel(int state, NSString *text, BOOL offerRespring) { [gPanels addObject:@[@(state), text ?: @"", @(offerRespring)]]; }
#include "ia-glue.inc"

// ---- the simulation ----------------------------------------------------------------------------------------------------------------------------
static const double T0 = 1800000000.0;
static NSString *const kLine = @"ok freed=123.4 MB deleted=5678 respring=1";   // (the helper's answer: the size's space is a no-break space)
static void Fresh(void) {   // a new scenario: nothing kept, nothing shown
    gStore = [NSMutableDictionary dictionary]; gPanels = [NSMutableArray array];
    gNow = T0; gBlocker = nil; gCrashed = NO; gCrashLooks = 0; gMarks = 0; gRespringsAsked = 0; gFinderOn = YES;
}
static void SBStart(int pid, double started) {   // a SpringBoard starts: the glue's own state is a new process's
    gPid = pid; gStarted = started;
    gICleanAfterLine = nil; gICleanAfterAt = 0; gICleanAfterResprung = NO; gICleanAfterLooked = NO; gICleanAfterAskedAt = 0;
    gRespringFirst = gRespringOtherwise = nil;
}
static void Seconds(double s) { for (int i = 0; i < (int)(s * 4 + 0.5); i++) { gNow += 0.25; DMFinderICleanAfterTick(); } }   // (the tick, every 0.25 s)
static NSDictionary *Kept(void) { return gStore[@kMSBDICleanAfterKey]; }
// The asking SpringBoard (pid 100, up an hour): its first look, then Clean and Respring after a clean that worked; the respring asked (go: YES) or
// left undone by the VPN warning (go: NO). Returns when it was asked.
static double AskCleanAndRespring(NSString *line, BOOL go) {
    SBStart(100, gNow - 3600.0);
    Seconds(1);
    DMFinderICleanRespring(line);
    double at = gNow;
    if (go && gRespringFirst) gRespringFirst();
    if (!go && gRespringOtherwise) gRespringOtherwise();
    return at;
}
static BOOL Panel(NSUInteger i, int state, NSString *text, BOOL offered) {
    return gPanels.count > i && [gPanels[i][0] intValue] == state && [gPanels[i][1] isEqualToString:text] && [gPanels[i][2] boolValue] == offered;
}

int main(void) {
    @autoreleasepool {
        NSString *line = nil, *why = nil; double at = 0;
        // ==== A. the rules ====
        NSDictionary *r = MSBDICleanAfterRecord(kLine, T0, 100);
        ok(@"A record: the line, when, the pid (three keys, nothing else)", r.count == 3 && [r[@"line"] isEqualToString:kLine] && [r[@"at"] doubleValue] == T0 && [r[@"pid"] intValue] == 100);
        ok(@"A record: none for no line, an empty or too long one, no pid or no time", !MSBDICleanAfterRecord(nil, T0, 1) && !MSBDICleanAfterRecord(@"", T0, 1)
           && !MSBDICleanAfterRecord([@"" stringByPaddingToLength:401 withString:@"x" startingAtIndex:0], T0, 1) && !MSBDICleanAfterRecord(kLine, T0, 0) && !MSBDICleanAfterRecord(kLine, NAN, 1));
        ok(@"A look: nothing kept", MSBDICleanAfterLook(nil, 100, T0, T0, &line, &at, &why) == kMSBDICleanAfterNone && !line);
        NSArray *bad = @[@"x", @{@"line": kLine, @"at": @(T0)}, @{@"line": kLine, @"at": @(T0), @"pid": @100, @"more": @1}, @{@"line": @5, @"at": @(T0), @"pid": @100},
                         @{@"line": @"", @"at": @(T0), @"pid": @100}, @{@"line": [@"" stringByPaddingToLength:401 withString:@"x" startingAtIndex:0], @"at": @(T0), @"pid": @100},
                         @{@"line": kLine, @"at": @(NAN), @"pid": @100}, @{@"line": kLine, @"at": @"now", @"pid": @100}, @{@"line": kLine, @"at": @(T0), @"pid": @0}];
        BOOL allBad = YES;
        for (id b in bad) allBad = allBad && MSBDICleanAfterLook(b, 200, T0 + 2, T0 + 3, &line, &at, &why) == kMSBDICleanAfterDrop && !line && why.length;
        ok(@"A look: anything but our record is dropped (shape, types, an empty or long line, no time, no pid)", allBad);
        ok(@"A look: the respring's SpringBoard (started 2 s after the ask) shows it", MSBDICleanAfterLook(r, 200, T0 + 2, T0 + 3, &line, &at, &why) == kMSBDICleanAfterShow && [line isEqualToString:kLine] && at == T0);
        ok(@"A look: ... started 90 s after it, still", MSBDICleanAfterLook(r, 200, T0 + 90, T0 + 95, &line, &at, &why) == kMSBDICleanAfterShow);
        ok(@"A look: started 91 s after it: another start, dropped", MSBDICleanAfterLook(r, 200, T0 + 91, T0 + 95, &line, &at, &why) == kMSBDICleanAfterDrop && !line && [why containsString:@"another start"]);
        ok(@"A look: a SpringBoard of another pid that started before the ask: dropped", MSBDICleanAfterLook(r, 200, T0 - 30, T0 + 5, &line, &at, &why) == kMSBDICleanAfterDrop);
        ok(@"A look: the asking SpringBoard, 0 s and 59 s on: left for its respring", MSBDICleanAfterLook(r, 100, T0 - 3600, T0, &line, &at, &why) == kMSBDICleanAfterWait
           && MSBDICleanAfterLook(r, 100, T0 - 3600, T0 + 59, &line, &at, &why) == kMSBDICleanAfterWait && !line);
        ok(@"A look: the asking SpringBoard 60 s on: the respring never came, shown there", MSBDICleanAfterLook(r, 100, T0 - 3600, T0 + 60, &line, &at, &why) == kMSBDICleanAfterShowHere
           && [line isEqualToString:kLine] && [why containsString:@"never came"]);
        ok(@"A look: the same pid in a SpringBoard started after the ask is not the asker (a later process)", MSBDICleanAfterLook(r, 100, T0 + 3, T0 + 4, &line, &at, &why) == kMSBDICleanAfterShow);
        ok(@"A look: kept 600 s ago: still shown; 601 s: dropped", MSBDICleanAfterLook(r, 200, T0 + 2, T0 + 600, &line, &at, &why) == kMSBDICleanAfterShow
           && MSBDICleanAfterLook(r, 200, T0 + 2, T0 + 601, &line, &at, &why) == kMSBDICleanAfterDrop && [why containsString:@"10 minutes"]);
        ok(@"A look: kept in the future (the clock went back more than 5 s): dropped", MSBDICleanAfterLook(r, 200, T0 - 10, T0 - 6, &line, &at, &why) == kMSBDICleanAfterDrop
           && MSBDICleanAfterLook(r, 100, T0 - 3600, T0 - 4, &line, &at, &why) == kMSBDICleanAfterWait);
        ok(@"A due: 0 s and 600 s yes; 601 s, -6 s and NaN no", MSBDICleanAfterDue(T0, T0) && MSBDICleanAfterDue(T0 + 600, T0) && !MSBDICleanAfterDue(T0 + 601, T0)
           && !MSBDICleanAfterDue(T0 - 6, T0) && !MSBDICleanAfterDue(NAN, T0));
        {   // crash reports
            char dir[] = "/tmp/msbd-icleanafter.XXXXXX", name[256];
            ok(@"A crash: the test's report folder", mkdtemp(dir) != NULL);
            NSString *d = @(dir);
            double now = floor([[NSDate date] timeIntervalSince1970]);
            NSString *(^stamp)(double) = ^NSString *(double t) { time_t tt = (time_t)t; struct tm tm; localtime_r(&tt, &tm); char b[64]; strftime(b, sizeof(b), "%Y-%m-%d-%H%M%S", &tm); return @(b); };
            void (^put)(NSString *) = ^(NSString *n) { [[NSData data] writeToFile:[d stringByAppendingPathComponent:n] atomically:NO]; };
            ok(@"A crash: an empty folder, or none at all: no crash", !MSBDICleanCrashSince(dir, now - 60, name, sizeof(name)) && !MSBDICleanCrashSince("/tmp/msbd-icleanafter-none", now, name, sizeof(name)));
            put([NSString stringWithFormat:@"SpringBoard-%@.ips", stamp(now - 120)]);
            put([NSString stringWithFormat:@"SpringBoard.cpu_resource-%@.ips", stamp(now)]);
            put([NSString stringWithFormat:@"stacks+SpringBoard-%@.ips", stamp(now)]);
            put([NSString stringWithFormat:@"backboardd-%@.ips", stamp(now)]);
            ok(@"A crash: a crash before the respring, a cpu_resource report, a stackshot, another process: none since", !MSBDICleanCrashSince(dir, now - 60, name, sizeof(name)) && !name[0]);
            put([NSString stringWithFormat:@"SpringBoard-%@.ips.synced", stamp(now - 30)]);
            ok(@"A crash: a SpringBoard crash 30 s after the respring (by the time in its name, a synced report too)", MSBDICleanCrashSince(dir, now - 60, name, sizeof(name)) && strstr(name, ".ips.synced"));
            ok(@"A crash: ... none since a later time", !MSBDICleanCrashSince(dir, now - 20, name, sizeof(name)));
            ok(@"A crash: the same second counts", MSBDICleanCrashSince(dir, now - 30 + 0.7, name, sizeof(name)));
            put(@"SpringBoard-unnamed.ips");   // (no time in its name: when it was written, now)
            ok(@"A crash: a report with no time in its name counts by when it was written", MSBDICleanCrashSince(dir, now - 5, name, sizeof(name)) && !strcmp(name, "SpringBoard-unnamed.ips"));
            ok(@"A crash: no folder name, or no time: no crash", !MSBDICleanCrashSince(NULL, now, name, sizeof(name)) && !MSBDICleanCrashSince(dir, NAN, name, sizeof(name)));
            [[NSFileManager defaultManager] removeItemAtPath:d error:nil];
        }
        // ==== B. the glue, over simulated SpringBoards ====
        Fresh();
        at = AskCleanAndRespring(kLine, YES);
        ok(@"B Clean and Respring asks our respring once, with its before and otherwise", gRespringsAsked == 1 && gRespringFirst && gRespringOtherwise);
        ok(@"B kept just before the respring is asked: the line, when, the asking SpringBoard's pid", [Kept()[@"line"] isEqualToString:kLine] && [Kept()[@"at"] doubleValue] == at && [Kept()[@"pid"] intValue] == 100);
        Seconds(30);
        ok(@"B the asking SpringBoard leaves it for the respring (30 s): kept, not shown", Kept() && gPanels.count == 0);
        SBStart(200, gNow + 2.0); gNow += 3.0; gBlocker = @"SpringBoard starting";
        Seconds(0.25);
        ok(@"B the respring's SpringBoard takes it at its first tick: gone from our preferences", !Kept() && gICleanAfterLine);
        Seconds(6);
        ok(@"B ... not shown while it says no (SpringBoard starting)", gPanels.count == 0);
        gBlocker = nil; Seconds(1);
        ok(@"B shown once nothing is in the way: the panel's result in the panel's words, no Respring offered (it was just done)", gPanels.count == 1 && Panel(0, 2, @"Freed 123.4 MB (5,678 files).", NO) && gMarks == 1);
        ok(@"B ... the crash reports looked at once, as it was shown", gCrashLooks == 1);
        Seconds(60);
        ok(@"B never twice (a minute on)", gPanels.count == 1);
        SBStart(300, gNow + 1.0); gNow += 2.0; Seconds(15);
        ok(@"B never twice (the next SpringBoard)", gPanels.count == 1 && !Kept());

        Fresh();   // Skip Lock Screen After Respring off: the respring lands on the Lock Screen
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, gNow + 2.0); gNow += 2.5; gBlocker = @"locked or covered";
        Seconds(180);
        ok(@"B on the Lock Screen: not shown (3 minutes), held", gPanels.count == 0 && gICleanAfterLine && !Kept());
        gBlocker = nil; Seconds(1);
        ok(@"B shown after the unlock, within a second, once", gPanels.count == 1 && Panel(0, 2, @"Freed 123.4 MB (5,678 files).", NO));
        Seconds(10); ok(@"B ... and only once", gPanels.count == 1);

        Fresh();   // left on the Lock Screen for more than 10 minutes
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, gNow + 2.0); gNow += 2.5; gBlocker = @"locked or covered";
        Seconds(600.0 - (gNow - at) + 2.0);
        ok(@"B after 10 minutes on the Lock Screen: dropped", !gICleanAfterLine && gPanels.count == 0);
        gBlocker = nil; Seconds(5);
        ok(@"B ... the unlock then shows nothing", gPanels.count == 0 && !Kept());

        Fresh();   // SpringBoard crashes (or is restarted) while it holds the result on the Lock Screen
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, gNow + 2.0); gNow += 2.5; gBlocker = @"locked or covered"; Seconds(20);
        ok(@"B taken by the respring's SpringBoard on the Lock Screen", !Kept() && gICleanAfterLine);
        SBStart(300, gNow + 1.0); gNow += 1.5; gCrashed = YES; Seconds(15); gBlocker = nil; Seconds(15);
        ok(@"B the SpringBoard after it (a crash in between) shows nothing after the unlock", gPanels.count == 0 && !Kept());

        Fresh();   // the respring's SpringBoard crashed before its first look; the one after it starts 12 s after the ask
        at = AskCleanAndRespring(kLine, YES);
        SBStart(300, at + 12.0); gNow = at + 13.0; gCrashed = YES; Seconds(15);
        ok(@"B a SpringBoard crash since the respring: the result dropped as it was to be shown", gPanels.count == 0 && !gICleanAfterLine && !Kept() && gCrashLooks == 1);
        Fresh();
        at = AskCleanAndRespring(kLine, YES);
        SBStart(300, at + 12.0); gNow = at + 13.0; gCrashed = NO; Seconds(15);
        ok(@"B ... with no crash report (a start 12 s after the ask, within 90 s): taken as the respring's, shown", gPanels.count == 1);

        Fresh();   // the respring never came and the asking SpringBoard went (a crash much later): the next start is not the respring's
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, at + 120.0); gNow = at + 121.0; Seconds(15);
        ok(@"B a SpringBoard started 2 minutes after the ask: dropped, never shown", gPanels.count == 0 && !Kept() && !gICleanAfterLine);

        Fresh();   // the respring never came, the asking SpringBoard still runs
        at = AskCleanAndRespring(kLine, YES);
        Seconds(58);
        ok(@"B the asking SpringBoard, 58 s on: still left for the respring", gPanels.count == 0 && Kept());
        Seconds(4);
        ok(@"B ... 60 s on: shown there, with the panel's Respring (iCleaner says one is needed), and gone from our preferences",
           gPanels.count == 1 && Panel(0, 2, @"Freed 123.4 MB (5,678 files).", YES) && !Kept() && gCrashLooks == 0);
        Fresh();
        AskCleanAndRespring(@"ok freed=4 KB deleted=1 respring=0", YES); Seconds(62);
        ok(@"B ... no Respring offered when iCleaner says none is needed", Panel(0, 2, @"Freed 4 KB (1 file).", NO));

        Fresh();   // the VPN warning's Cancel (or VPN Settings, or a lock over it): no respring
        AskCleanAndRespring(kLine, NO);
        ok(@"B the respring not done after all: nothing kept in our preferences", !Kept());
        Seconds(1);
        ok(@"B ... the result shown here at once, as after a Clean (Respring offered)", gPanels.count == 1 && Panel(0, 2, @"Freed 123.4 MB (5,678 files).", YES));
        Fresh();
        AskCleanAndRespring(kLine, NO); gBlocker = @"locked or covered"; Seconds(30);
        ok(@"B ... held while the iPad is locked (the warning put away by the lock)", gPanels.count == 0);
        gBlocker = nil; Seconds(1);
        ok(@"B ... shown after the unlock", gPanels.count == 1);

        Fresh();   // Finder off
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, gNow + 2.0); gNow += 2.5; gFinderOn = NO; Seconds(15);
        ok(@"B Finder off at the start: not looked at, not shown", gPanels.count == 0 && Kept() && !gICleanAfterLine);
        Fresh();
        at = AskCleanAndRespring(kLine, YES);
        SBStart(200, gNow + 2.0); gNow += 2.5; gBlocker = @"locked or covered"; Seconds(5);
        gFinderOn = NO; Seconds(1); gFinderOn = YES; gBlocker = nil; Seconds(5);
        ok(@"B Finder turned off while it is held: dropped", gPanels.count == 0 && !gICleanAfterLine);

        Fresh();   // what is not ours, or not a result
        gStore[@kMSBDICleanAfterKey] = @"junk";
        SBStart(200, gNow - 5.0); Seconds(15);
        ok(@"B something else under our key: removed at the first look, nothing shown", !Kept() && gPanels.count == 0);
        Fresh();
        gStore[@kMSBDICleanAfterKey] = MSBDICleanAfterRecord(@"error: iCleaner couldn’t clean", gNow, 100);
        SBStart(200, gNow + 2.0); gNow += 3.0; Seconds(12);
        ok(@"B a kept error is shown the panel's way for errors", gPanels.count == 1 && Panel(0, 3, @"iCleaner couldn’t clean", NO));

        printf("%d checks, %d failed\n", checks, fails);
        return fails ? 1 : 0;
    }
}
