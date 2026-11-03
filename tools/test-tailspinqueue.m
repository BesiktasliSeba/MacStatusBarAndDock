// test-tailspinqueue.m -- Mac test of Keep Tailspin Off's `tailspin disable` in the root helper (macsettings/sshtoggled/TailspinDaemon.h, 1.7.9;
// code review): the tool runs off the main queue, so the helper's main queue (SSH, the engines, Sleep Guard) does not wait for it; one run at a
// time; when it ends, the state the look wrote gets tailspin's new configuration and keeps our record of the false. The helper's own code, with
// a fake tool that takes 1.5 s (a slow tailspind) and turns the configuration off as tailspind does. Built and run by test-tailspinguard.sh,
// with TG_TOOL, kMSBDTailspinStateFile, kMSBDTailspinConfig and ESTATEDIR pointing into its scratch folder.
#import <Foundation/Foundation.h>
#include <notify.h>
#include <spawn.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <unistd.h>
extern char **environ;
static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ELog(NSString *fmt, ...) { va_list ap; va_start(ap, fmt); NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap]; va_end(ap); printf("      log: %s\n", s.UTF8String); }
#include "../macsettings/sshtoggled/TailspinDaemon.h"
static int fails = 0, checks = 0;
static void check(const char *what, BOOL ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
static NSString *const kOn = @"perfdiagsselfenabled [123]";
static void writeConfig(BOOL on) { [@{ @"Enabled": @(on), @"EnabledModifier": on ? kOn : @"tailspin [9]" } writeToFile:@kMSBDTailspinConfig atomically:YES]; }
static NSUInteger toolRuns(void) { NSString *s = [NSString stringWithContentsOfFile:@ESTATEDIR "/tool-runs" encoding:NSUTF8StringEncoding error:nil]; return [s componentsSeparatedByString:@"\n"].count - 1; }
static void spin(double seconds) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
int main(void) {
    @autoreleasepool {
        // the fake tool: logs its argument, takes 1.5 s, then tailspind's configuration says off
        NSString *tool = [NSString stringWithFormat:@"#!/bin/sh\necho \"$1\" >> '%s/tool-runs'\nsleep 1.5\n/usr/bin/plutil -replace Enabled -bool NO '%s'\n/usr/bin/plutil -replace EnabledModifier -string 'tailspin [9]' '%s'\nexit 0\n", ESTATEDIR, kMSBDTailspinConfig, kMSBDTailspinConfig];
        [tool writeToFile:@TG_TOOL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        chmod(TG_TOOL, 0755);
        writeConfig(YES);
        TGWriteState(@{ @"supported": @YES, @"keepOff": @YES, @"owned": @YES, @"allow": @0, @"tailspinOn": @1, @"modifier": kOn, @"why": @"test" });   // (as the look writes it first)

        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        TGTurnOff(@"test", kOn);
        CFAbsoluteTime t1 = CFAbsoluteTimeGetCurrent();
        check("TGTurnOff returns at once: the main queue does not wait for the 1.5 s tool", t1 - t0 < 0.1);
        TGTurnOff(@"a second look", kOn);
        __block CFAbsoluteTime ranAt = 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ranAt = CFAbsoluteTimeGetCurrent(); });
        __block BOOL done = NO;
        for (int i = 0; i < 100 && !done; i++) { spin(0.05); done = [TGState()[@"tailspinOn"] integerValue] == 0; }
        CFAbsoluteTime t2 = CFAbsoluteTimeGetCurrent();
        check("  ... other work on the main queue runs while the tool does (a block due at 0.3 s ran before 0.8 s)", ranAt > 0 && ranAt - t0 < 0.8);
        check("  ... when the tool ends, the state says tailspin is off (within 5 s)", done);
        check("  ... and only after the tool ended (1.5 s)", t2 - t0 >= 1.4);
        NSDictionary *st = TGState();
        check("  ... the look's record kept: our false is still ours, the switch's state and the answer for Settings unchanged",
              [st[@"owned"] boolValue] && [st[@"keepOff"] boolValue] && [st[@"supported"] boolValue] && [st[@"allow"] integerValue] == 0);
        check("  ... tailspin's new configuration in it (its modifier)", [st[@"modifier"] isEqualToString:@"tailspin [9]"]);
        spin(0.3);
        check("a look while the tool runs leaves it to that run: the tool ran once", toolRuns() == 1);
        check("  ... with `disable`", [[NSString stringWithContentsOfFile:@ESTATEDIR "/tool-runs" encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"disable\n"]);
        writeConfig(YES);
        TGWriteState(@{ @"supported": @YES, @"keepOff": @YES, @"owned": @YES, @"allow": @0, @"tailspinOn": @1, @"modifier": kOn, @"why": @"test" });
        TGTurnOff(@"the next look", kOn);
        for (int i = 0; i < 100 && [TGState()[@"tailspinOn"] integerValue] != 0; i++) spin(0.05);
        check("after it ended, the next look runs it again", toolRuns() == 2 && [TGState()[@"tailspinOn"] integerValue] == 0);
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
