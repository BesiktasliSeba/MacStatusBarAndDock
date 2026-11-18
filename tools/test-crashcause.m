// test-crashcause.m -- one child process for tools/test-crashcause.sh (1.8.7.7, GitHub #14): our death record (common/CrashCause.h) installed as
// SpringBoard's loader installs it, then an uncaught exception of the given kind. Another tweak's handler is installed BEFORE ours (prev): it
// writes "<path>.prev" -- how often it was called, and whether a frame of our handler was on its stack (it must not be: ours hands over with a
// tail call, so a handler that aborts never has our code on the crashing stack).
//   test-crashcause <record file> <main|thread|string|nilreason|long|utf8|reentry|noprev|twice> [noinstall]
#import <Foundation/Foundation.h>
#include <execinfo.h>
#include <dlfcn.h>
#include <string.h>
#include "../common/CrashCause.h"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
static const char *gOut;
static int gPrevCalls;
static void OtherTweakHandler(NSException *e) {
    gPrevCalls++;
    void *f[64]; int n = backtrace(f, 64), ours = 0;
    for (int i = 0; i < n; i++) { Dl_info di; if (dladdr(f[i], &di) && di.dli_sname && strstr(di.dli_sname, "MSBDCauseHandler")) ours = 1; }
    FILE *o = fopen([[NSString stringWithFormat:@"%s.prev", gOut] UTF8String], "a");
    if (o) { fprintf(o, "prev %d ours-frame %d\n", gPrevCalls, ours); fclose(o); }
    if (getenv("CAUSE_REENTER") && gPrevCalls < 3) {   // (a handler that calls "the current handler" -- ours now -- with the same exception)
        NSUncaughtExceptionHandler *cur = NSGetUncaughtExceptionHandler();
        if (cur) cur(e);
    }
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) return 2;
        gOut = argv[1];
        NSString *mode = @(argv[2]);
        if (![mode isEqual:@"noprev"]) NSSetUncaughtExceptionHandler(OtherTweakHandler);
        if (argc < 4) {
            int a = MSBDCauseInstall(), b = [mode isEqual:@"twice"] ? MSBDCauseInstall() : 1;   // (a second install: no second link in the chain)
            if (!a || !b) return 3;
        }
        if ([mode isEqual:@"reentry"]) setenv("CAUSE_REENTER", "1", 1);
        if ([mode isEqual:@"main"] || [mode isEqual:@"twice"] || [mode isEqual:@"noprev"] || [mode isEqual:@"reentry"])
            [(id)[NSObject new] performSelector:NSSelectorFromString(@"stateService:didReceiveDoNotDisturbStateUpdate:") withObject:nil withObject:nil];
        if ([mode isEqual:@"thread"] || [mode isEqual:@"long"] || [mode isEqual:@"utf8"]) {
            NSString *pad = [mode isEqual:@"utf8"] ? [@"" stringByPaddingToLength:300 withString:@"çğış€" startingAtIndex:0] : [@"" stringByPaddingToLength:2000 withString:@"x" startingAtIndex:0];
            BOOL onThread = ![mode isEqual:@"long"];
            void (^throwIt)(void) = ^{ [NSException raise:NSInternalInconsistencyException format:@"line one\nline\ttwo x%@", pad]; };
            if (onThread) { [NSThread detachNewThreadWithBlock:throwIt]; sleep(5); }
            else throwIt();
        }
        if ([mode isEqual:@"string"]) @throw @"a thrown string";
        if ([mode isEqual:@"nilreason"]) @throw [NSException exceptionWithName:@"NoReason" reason:nil userInfo:nil];
    }
    return 0;
}
