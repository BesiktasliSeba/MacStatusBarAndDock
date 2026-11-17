// test-smentitynew.m -- DMSMEntityNew (statusbar/SMEngineAPI.h): an app entity made through Apple's own init, called by objc_msgSend under ARC.
// An init takes alloc's +1 and gives back its own; when it fails it frees the object itself (the Cocoa way: [self release]; return nil, or ARC's
// own when an ARC init returns nil). Called through a plain function type, ARC treated the call as any other: it released the alloc after the call
// and retained the result -- right while the init returns self, a second free of the object when the init fails (coexistence investigation of
// GitHub issue #14). Here the real DMSMIsEntity and DMSMEntityNew, cut out of SMEngineAPI.h by test-smentitynew.sh, make a stand-in
// SBDeviceApplicationSceneEntity (built without ARC: it counts its retains and releases and is never really freed), whose init succeeds or fails,
// through both of Apple's inits. Each time the object must be given back exactly once: releases - retains = 1 (alloc's +1).
// Built twice by test-smentitynew.sh: without ARC (SEN_STANDIN, the stand-in) and with ARC (the real code and the checks).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#ifdef SEN_STANDIN
extern int gSENRetains, gSENReleases;   // (the stand-in's retains and releases, every object; pool releases included)
extern BOOL gSENFail;                   // (Apple's init fails this time)
@interface SBDeviceApplicationSceneEntity : NSObject
@end
@implementation SBDeviceApplicationSceneEntity
- (id)initWithApplication:(id)app sceneHandleProvider:(id)provider displayIdentity:(id)identity {
    (void)app; (void)provider; (void)identity;
    if (gSENFail) { [self release]; return nil; }
    return self;
}
- (id)initWithApplicationForMainDisplay:(id)app { (void)app; if (gSENFail) { [self release]; return nil; } return self; }
- (id)retain { gSENRetains++; return self; }
- (oneway void)release { gSENReleases++; }   // (never really freed: a second release is counted, not a crash)
@end
#else
int gSENRetains, gSENReleases;
BOOL gSENFail;
static NSMutableArray<NSString *> *gFails;
static void DMSMAPIFail(NSString *what, NSString *why) { [gFails addObject:[NSString stringWithFormat:@"%@: %@", what, why]]; }
static NSString *DMSMSigObjObj(void) { return @"@@:@"; }
static NSString *DMSMSigOfMethod(Method m) { return m ? @"@@:@" : nil; }   // (the 15-18 shape of initWithApplicationForMainDisplay:)
#include "sen-cut.inc"

static int gChecks, gBad;
static void check(BOOL ok, NSString *what) { gChecks++; if (!ok) gBad++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
int main(void) {
    gFails = [NSMutableArray array];
    for (int other = 0; other < 2; other++)
        for (int fail = 0; fail < 2; fail++) {
            gSENFail = fail; gSENRetains = gSENReleases = 0;
            BOOL got;
            @autoreleasepool {
                id e = other ? DMSMEntityNew(@"app", @"provider", @"identity") : DMSMEntityNew(@"app", nil, nil);
                got = e != nil;
            }
            NSString *how = [NSString stringWithFormat:@"%@, the init %@", other ? @"another display (initWithApplication:sceneHandleProvider:displayIdentity:)"
                                                                              : @"the iPad's own display (initWithApplicationForMainDisplay:)", fail ? @"fails" : @"succeeds"];
            check(got == !fail, [NSString stringWithFormat:@"%@: %@", how, fail ? @"no entity" : @"the entity"]);
            int net = gSENReleases - gSENRetains;
            check(net == 1, [NSString stringWithFormat:@"%@: the object given back exactly once (releases %d - retains %d = %d%@)", how, gSENReleases,
                             gSENRetains, net, net > 1 ? @": freed twice" : net < 1 ? @": leaked" : @""]);
        }
    check(gFails.count == 0, [NSString stringWithFormat:@"no refusal logged (%lu)", (unsigned long)gFails.count]);
    printf("%d check(s), %d fail\n", gChecks, gBad);
    return gBad;
}
#endif
