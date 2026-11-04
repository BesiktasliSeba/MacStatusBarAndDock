// SBShared.h -- a SpringBoard controller's shared instance as SpringBoard has made it, never made by us (1.8.0.1). Foundation only, so the Mac test
// (tools/test-sbshared.m) runs this very code with stand-in classes; common/CCController.h asks it for Control Center's controller.
// Why: +sharedInstance makes the controller when it is not there yet, and SpringBoard's own -init of it asks for its main workspace, which
// SpringBoard makes in its own launch: asked before that -- from our constructor, in dyld's initializers -- the workspace's nil check raised and
// SpringBoard went down at its start (iPad 2 16.7.7, 4 Nov: our Control Center's start, -[SBControlCenterController init] ->
// +[SBMainWorkspace _sharedInstanceWithNilCheckPolicy:], SIGABRT, then ElleKit's Safe Mode). Made by SpringBoard, the same call just answers.
//  - +sharedInstanceIfExists where the class has it (SpringBoard's own non-making call, 15-18's controllers and managers);
//  - else +_sharedInstanceCreatingIfNeeded:NO (what +sharedInstance calls with YES);
//  - else, a class with +sharedInstance alone, only once SpringBoard's main workspace exists (asked the same way): its -init has what it asks for.
// nil: not made yet (or no such class), as SpringBoard would answer.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>

// (a class method of that name and type encoding -- the types without their offsets, as "@@:B")
static inline BOOL MSBDSBClassMethodIs(Class c, SEL sel, const char *want) {
    Method m = c ? class_getClassMethod(c, sel) : NULL;
    const char *enc = m ? method_getTypeEncoding(m) : NULL;
    if (!enc) return NO;
    char plain[32]; size_t n = 0;
    for (const char *p = enc; *p && n + 1 < sizeof plain; p++) if (!(*p >= '0' && *p <= '9')) plain[n++] = *p;
    plain[n] = 0;
    return strcmp(plain, want) == 0;
}
static inline id MSBDSBSharedIfExistsDepth(Class c, int depth) {
    if (!c || depth > 1) return nil;
    SEL ifExists = NSSelectorFromString(@"sharedInstanceIfExists"), creating = NSSelectorFromString(@"_sharedInstanceCreatingIfNeeded:"), shared = NSSelectorFromString(@"sharedInstance");
    if (MSBDSBClassMethodIs(c, ifExists, "@@:")) return ((id (*)(id, SEL))objc_msgSend)((id)c, ifExists);
    if (MSBDSBClassMethodIs(c, creating, "@@:B")) return ((id (*)(id, SEL, BOOL))objc_msgSend)((id)c, creating, NO);
    if (!MSBDSBClassMethodIs(c, shared, "@@:")) return nil;
    Class ws = objc_getClass("SBMainWorkspace");
    if (!ws || ws == c || !MSBDSBSharedIfExistsDepth(ws, depth + 1)) return nil;   // (SpringBoard's launch has not made its workspace yet)
    return ((id (*)(id, SEL))objc_msgSend)((id)c, shared);
}
static inline id MSBDSBSharedIfExists(Class c) { return MSBDSBSharedIfExistsDepth(c, 0); }
