// Relaunch.h -- SpringBoard's restart, asked for the way sbreload asks for it (MacStatusBar&Dock 1.7.4 item 6).
// sbreload (uikittools-ng 2.1.7 / 2.1.8, disassembled 31 Oct 2026) does not kill anything: it sends SpringBoard one SBSRelaunchAction through
// FBSSystemService -- reason "respring", options 5 (the render server restarted too, a fade to black) -- and SpringBoard's restart manager carries
// it out in order (its own state written, then the restart). Only when SpringBoard or backboardd has not restarted 2 s later does it stop them through
// launchd -- and on 16-18 that stop hits the new ones (a second start every respring: pid poll on the A12Z, 10 Nov). Our Respring sends that same
// action itself on every iPadOS (statusbar/StatusBar.x DMRespring): SpringBoard's restart manager takes it from SpringBoard as from sbreload, one start.
// Mac test: tools/test-relaunch.sh.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>

#define kMSBDRelaunchRestartRenderServer 1UL   // (SBSRelaunchActionOptions: RestartRenderServer = 1 << 0, SnapshotTransition = 1 << 1,
#define kMSBDRelaunchFadeToBlack         4UL   //  FadeToBlackTransition = 1 << 2)

// One SBSRelaunchAction sent to SpringBoard; NO when this iPadOS has no such action or service (every call is checked first: nothing is sent then).
static inline BOOL MSBDSendRelaunchAction(NSString *reason, NSUInteger options) {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    Class actionClass = objc_getClass("SBSRelaunchAction"), serviceClass = objc_getClass("FBSSystemService");
    SEL make = NSSelectorFromString(@"actionWithReason:options:targetURL:"), shared = NSSelectorFromString(@"sharedService");
    SEL send = NSSelectorFromString(@"sendActions:withResult:");
    id action = [actionClass respondsToSelector:make] ? ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(actionClass, make, reason, options, nil) : nil;
    id service = [serviceClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(serviceClass, shared) : nil;
    if (!action || ![service respondsToSelector:send]) return NO;
    ((void (*)(id, SEL, id, id))objc_msgSend)(service, send, [NSSet setWithObject:action], nil);
    return YES;
}
// The respring sbreload asks for: the same reason and options.
static inline BOOL MSBDRelaunchLikeSbreload(void) {
    return MSBDSendRelaunchAction(@"respring", kMSBDRelaunchRestartRenderServer | kMSBDRelaunchFadeToBlack);
}
