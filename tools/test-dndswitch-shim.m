// test-dndswitch-shim.m -- Mac test of common/DndSwitchShim.h (1.8.7.8, GitHub #14 crash 4): a WORKAROUND for a class named DndSwitch from another
// tweak, a Do Not Disturb state listener without the listener's method. Stand-ins: Do Not Disturb's DNDStateService as the crash shows it (its
// listeners held in a weak NSHashTable, each update sent to every listener on the serial queue com.apple.donotdisturb.StateService.call-out,
// nobody asked first: -remoteService:didReceiveDoNotDisturbStateUpdate:'s block_invoke_2), and the classes, made at run time so that each scenario
// (one process each, argv[1]) has only the ones it names: DndSwitch, the protocol SwitchProtocol, a base class. The real code is
// DndSwitchShim.h as test-dndswitch-shim.sh hands it in (-I: the tree's, or a made-to-fail copy).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "DndSwitchShim.h"

static int gChecks, gFails;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static SEL Sel(void) { return sel_registerName("stateService:didReceiveDoNotDisturbStateUpdate:"); }

// ---- Do Not Disturb, stood in
@interface TDNDStateService : NSObject
- (void)addStateUpdateListener:(id)listener error:(NSError **)error;
- (NSString *)deliver:(id)update;
@end
@implementation TDNDStateService { NSHashTable *_listeners; dispatch_queue_t _callout; }
- (instancetype)init {
    if ((self = [super init])) { _listeners = [NSHashTable weakObjectsHashTable]; _callout = dispatch_queue_create("com.apple.donotdisturb.StateService.call-out", DISPATCH_QUEUE_SERIAL); }
    return self;
}
- (void)addStateUpdateListener:(id)listener error:(NSError **)error { (void)error; @synchronized (self) { [_listeners addObject:listener]; } }
// (an update from donotdisturbd: on the call-out queue, each listener sent the method with no -respondsToSelector: first. There, an exception
//  aborts SpringBoard; here it is caught and its reason returned -- nil: none)
- (NSString *)deliver:(id)update {
    NSArray *now; @synchronized (self) { now = _listeners.allObjects; }
    __block NSString *thrown = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(_callout, ^{
        for (id l in now) {
            @try { ((void (*)(id, SEL, id, id))objc_msgSend)(l, Sel(), self, update); }
            @catch (NSException *x) { thrown = [NSString stringWithFormat:@"%@: %@", x.name, x.reason]; }
        }
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    return thrown;
}
- (NSUInteger)listeners { @synchronized (self) { return _listeners.allObjects.count; } }
@end
static TDNDStateService *gService;

// ---- the other tweak's classes, made at run time
static int gTheirUpdates, gBaseUpdates;
static BOOL TGetState(id self, SEL _cmd) { (void)_cmd; [gService addStateUpdateListener:self error:NULL]; return NO; }   // (its read: a listener from here on)
static void TSetState(id self, SEL _cmd, BOOL on) { (void)self; (void)_cmd; (void)on; }
static void TTheirUpdate(id self, SEL _cmd, id s, id u) { (void)self; (void)_cmd; (void)s; (void)u; gTheirUpdates++; }
static void TBaseUpdate(id self, SEL _cmd, id s, id u) { (void)self; (void)_cmd; (void)s; (void)u; gBaseUpdates++; }
static Protocol *TProtocol(void) {   // (SwitchProtocol, as the other tweak's image registers it)
    Protocol *p = objc_allocateProtocol("SwitchProtocol");
    if (!p) return objc_getProtocol("SwitchProtocol");
    protocol_addMethodDescription(p, @selector(getState), "B16@0:8", YES, YES);
    protocol_addMethodDescription(p, sel_registerName("setState:"), "v20@0:8B16", YES, YES);
    objc_registerProtocol(p);
    return p;
}
static Class TClass(const char *name, Class sup, Protocol *p, IMP update) {
    Class c = objc_allocateClassPair(sup ?: [NSObject class], name, 0);
    class_addMethod(c, @selector(getState), (IMP)TGetState, "B16@0:8");
    class_addMethod(c, sel_registerName("setState:"), (IMP)TSetState, "v20@0:8B16");
    if (update) class_addMethod(c, Sel(), update, "v32@0:8@16@24");
    if (p) class_addProtocol(c, p);
    objc_registerClassPair(c);
    return c;
}
static BOOL OwnMethod(Class c, SEL s) {   // (the class itself has it, not a superclass)
    unsigned n = 0; BOOL own = NO; Method *ms = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) if (method_getName(ms[i]) == s) own = YES;
    free(ms);
    return own;
}
static NSString *Res(MSBDDndShimResult r) { return @(MSBDDndShimText(r)); }

// One read of the other tweak's DND switch while an update lands: the object alive and a listener (the crash's moment). Returns the exception.
static NSString *ReadWhileUpdate(Class c, int *alive) {
    NSString *thrown = nil;
    @autoreleasepool {
        id sw = [c new];
        ((BOOL (*)(id, SEL))objc_msgSend)(sw, @selector(getState));
        *alive = (int)[gService listeners];
        thrown = [gService deliver:@"update"];
        sw = nil;
    }
    return thrown;
}

static void ScenarioBefore(void) {   // (the defect as it is: no guard)
    Class c = TClass("DndSwitch", Nil, TProtocol(), NULL);
    int alive = 0;
    NSString *t = ReadWhileUpdate(c, &alive);
    Check(alive == 1, @"before: the switch object is a DND listener during its read (as the other tweak's -getState makes it)");
    Check([t containsString:@"NSInvalidArgumentException"] && [t containsString:@"unrecognized selector"] && [t containsString:@"stateService:didReceiveDoNotDisturbStateUpdate:"],
          [NSString stringWithFormat:@"before: an update in that moment is an unrecognized selector on the call-out queue -- #14 crash 4 (%@)", t ?: @"no exception"]);
}
static void ScenarioAfter(void) {   // (the guard, then the same read and update)
    Class c = TClass("DndSwitch", Nil, TProtocol(), NULL);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(r == MSBDDndShimAdded, [NSString stringWithFormat:@"after: the guard adds the method (%@)", Res(r)]);
    Method m = class_getInstanceMethod(c, Sel());
    Check(m && OwnMethod(c, Sel()) && method_getImplementation(m) == (IMP)MSBDDndSwitchUpdateIgnored, @"after: DndSwitch has the empty method itself");
    Check(m && !strcmp(method_getTypeEncoding(m), "v32@0:8@16@24"), [NSString stringWithFormat:@"after: its types are v32@0:8@16@24, the listener method's (%s)", m ? method_getTypeEncoding(m) : "none"]);
    Check(![NSObject instancesRespondToSelector:Sel()], @"after: nothing added to NSObject (DndSwitch's superclass)");
    int alive = 0;
    NSString *t = ReadWhileUpdate(c, &alive);
    Check(alive == 1 && !t, [NSString stringWithFormat:@"after: the same update during a read is no exception (%@)", t ?: @"none"]);
    @autoreleasepool { id sw = [c new]; Check(((BOOL (*)(id, SEL))objc_msgSend)(sw, @selector(getState)) == NO, @"after: its own -getState still runs as it did"); }
    for (int i = 0; i < 3; i++) Check(![gService deliver:@"update"], [NSString stringWithFormat:@"after: update %d with the switch freed: no listener, nothing sent", i + 1]);
    MSBDDndShimResult again = MSBDDndSwitchShim();
    Check(again == MSBDDndShimHasIt && method_getImplementation(class_getInstanceMethod(c, Sel())) == (IMP)MSBDDndSwitchUpdateIgnored,
          [NSString stringWithFormat:@"after: a second run changes nothing (%@)", Res(again)]);
}
static void ScenarioOwn(void) {   // (a DndSwitch that has the method: a version without the defect)
    Class c = TClass("DndSwitch", Nil, TProtocol(), (IMP)TTheirUpdate);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(r == MSBDDndShimHasIt, [NSString stringWithFormat:@"own: a DndSwitch with the method is left alone (%@)", Res(r)]);
    Check(method_getImplementation(class_getInstanceMethod(c, Sel())) == (IMP)TTheirUpdate, @"own: it keeps its own implementation (never replaced)");
    int alive = 0;
    NSString *t = ReadWhileUpdate(c, &alive);
    Check(!t && gTheirUpdates == 1, [NSString stringWithFormat:@"own: the update reaches its own method, once (%d)", gTheirUpdates]);
}
static void ScenarioInherited(void) {   // (its superclass has the method)
    Class base = TClass("TSwitchBase", Nil, NULL, (IMP)TBaseUpdate);
    Class c = TClass("DndSwitch", base, TProtocol(), NULL);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(r == MSBDDndShimHasIt, [NSString stringWithFormat:@"inherited: a DndSwitch whose superclass has the method is left alone (%@)", Res(r)]);
    Check(!OwnMethod(c, Sel()) && method_getImplementation(class_getInstanceMethod(c, Sel())) == (IMP)TBaseUpdate, @"inherited: nothing added to DndSwitch: its superclass's method still answers");
    int alive = 0;
    NSString *t = ReadWhileUpdate(c, &alive);
    Check(!t && gBaseUpdates == 1, [NSString stringWithFormat:@"inherited: the update reaches the superclass's method (%d)", gBaseUpdates]);
}
static void ScenarioNoClass(void) {   // (the other tweak not installed; another class of the same protocol without the method)
    Class other = TClass("OtherSwitch", Nil, TProtocol(), NULL);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(r == MSBDDndShimNoClass, [NSString stringWithFormat:@"no class: nothing to do (%@)", Res(r)]);
    Check(!objc_getClass("DndSwitch") && ![other instancesRespondToSelector:Sel()] && ![NSObject instancesRespondToSelector:Sel()], @"no class: nothing added anywhere");
}
static void ScenarioNotAdopted(void) {   // (a DndSwitch of something else: the protocol exists, the class does not adopt it)
    TProtocol();
    Class c = TClass("DndSwitch", Nil, NULL, NULL);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(r == MSBDDndShimNotAdopted, [NSString stringWithFormat:@"not adopted: a DndSwitch without SwitchProtocol is left alone (%@)", Res(r)]);
    Check(![c instancesRespondToSelector:Sel()], @"not adopted: nothing added");
}
static void ScenarioNoProtocol(void) {   // (a DndSwitch, and no protocol named SwitchProtocol in the process)
    Class c = TClass("DndSwitch", Nil, NULL, NULL);
    MSBDDndShimResult r = MSBDDndSwitchShim();
    Check(!objc_getProtocol("SwitchProtocol") && r == MSBDDndShimNoProtocol, [NSString stringWithFormat:@"no protocol: left alone (%@)", Res(r)]);
    Check(![c instancesRespondToSelector:Sel()], @"no protocol: nothing added");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gService = [TDNDStateService new];
        NSString *s = argc > 1 ? @(argv[1]) : @"";
        if ([s isEqualToString:@"before"]) ScenarioBefore();
        else if ([s isEqualToString:@"after"]) ScenarioAfter();
        else if ([s isEqualToString:@"own"]) ScenarioOwn();
        else if ([s isEqualToString:@"inherited"]) ScenarioInherited();
        else if ([s isEqualToString:@"noclass"]) ScenarioNoClass();
        else if ([s isEqualToString:@"notadopted"]) ScenarioNotAdopted();
        else if ([s isEqualToString:@"noprotocol"]) ScenarioNoProtocol();
        else { printf("usage: %s before|after|own|inherited|noclass|notadopted|noprotocol\n", argv[0]); return 99; }
    }
    return gFails;
}
