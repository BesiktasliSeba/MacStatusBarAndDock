// StartupAssertion.h -- SpringBoard's start-up power assertion given back once SpringBoard is up (battery drain F1b, MacStatusBar&Dock 1.7.8).
// iPadOS 16-18: BacklightServices takes a "SystemIsActive" assertion, BacklightServices.backlightActiveOn.startup, as SpringBoard starts and
// gives it back only at the display's first sleep or wake. A SpringBoard that dies before that -- a respring with the screen kept on (every
// install's sbreload, our Respring, Safe Mode), a crash -- leaves it with powerd, owned by a process that is gone, and the iPad never idle-sleeps
// again (iPad 2 16.7.7 three days, 17.5 a day and a half; plans/battery-drain.md, 1 Nov). Nothing in powerd lets another process drop it.
// So SpringBoard gives its own back as soon as it is up -- one minute after it started -- and right before any respring of ours: a later death
// then leaves nothing behind, whatever ends it. While the screen is on the display's own assertions keep the iPad awake anyway; with the screen
// off at that minute the iPad may sleep, as it would after the display's first sleep. 15 has no such assertion: nothing is found, nothing done.
// powerd's own list names it (IOPMCopyAssertionsByProcess: our pid, the name); IOPMAssertionRelease from its owner process gives it back.
// (The Sleep Guard, sshtoggled, clears what is left by a SpringBoard that dies within its first minute.)
#pragma once
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

#define kMSBDStartupAssertionName @"BacklightServices.backlightActiveOn.startup"

// Our own process's start-up assertions given back; the count, and what was done in *what.
static int MSBDGiveBackStartupAssertion(NSString **what) {
    static int (*byProc)(CFDictionaryRef *); static int (*rel)(uint32_t);
    if (!byProc) {
        void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        byProc = io ? (int (*)(CFDictionaryRef *))dlsym(io, "IOPMCopyAssertionsByProcess") : NULL;
        rel = io ? (int (*)(uint32_t))dlsym(io, "IOPMAssertionRelease") : NULL;
    }
    CFDictionaryRef all = NULL;
    if (!byProc || !rel || byProc(&all) != 0 || !all) { if (what) *what = @"powerd's list not read"; return 0; }
    NSArray *mine = ((__bridge NSDictionary *)all)[@(getpid())];
    NSMutableArray *done = [NSMutableArray array];
    int n = 0;
    for (NSDictionary *a in [mine isKindOfClass:[NSArray class]] ? mine : @[]) {
        if (![a isKindOfClass:[NSDictionary class]] || ![a[@"AssertName"] isEqual:kMSBDStartupAssertionName]) continue;
        id idv = a[@"AssertionId"] ?: a[@"AssertionID"] ?: a[@"AssertID"];
        if (![idv respondsToSelector:@selector(unsignedIntValue)]) { [done addObject:@"(no id)"]; continue; }
        int r = rel([idv unsignedIntValue]);
        [done addObject:[NSString stringWithFormat:@"id %u: %s (0x%x)", [idv unsignedIntValue], r == 0 ? "given back" : "refused", (unsigned)r]];
        if (r == 0) n++;
    }
    CFRelease(all);
    if (what) *what = done.count ? [done componentsJoinedByString:@", "] : @"none held";
    return n;
}
