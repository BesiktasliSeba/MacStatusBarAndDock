// MonitorGuard.h -- MacStatusBar&Dock 1.7.3 (item 11): what is left of a window controller that is deallocated without its own close, found from the
// scene monitor it drops (StatusBar.x %group SceneMonitorGuard). Plain Foundation and the Objective-C runtime: the Mac test tools/test-monitorguard.m
// runs this very code with stand-in classes (a monitor with a weak delegate, an owner that observes a layer manager's "layers" by KVO).
// Zetsu's three window controllers (ZetsuAppController, StageController, ZetsuSplitController; Zetsu 1.6.6) each pair an FBSceneMonitor, whose delegate
// they are, with a KVO observation of the scene's layer manager ("layers", their -setHost: / -reloadHostAfterDelay: / -CreateSplitView), and undo both
// only in their close (-CloseAppWindow: / -closeWindow / -CloseAppView); none of them has a -dealloc. A controller freed without its close drops a
// monitor that is still valid -- FrontBoard asserts in -[FBSceneMonitor dealloc] -- AND leaves itself registered as an observer of the layer manager:
// the next change of the scene's layers sends the KVO notification to freed memory (M1 15.6.1, 31 Oct 07:07: EXC_BAD_ACCESS in
// KVO_IS_RETAINING_ALL_OBSERVERS_OF_THIS_OBJECT_IF_IT_CRASHES_AN_OBSERVER_WAS_OVERRELEASED_OR_SMASHED from -[FBScene client:didUpdateClientSettings:...],
// x0 = the ZetsuAppController the log had named; 160 ms after our guard had invalidated its monitor). Invalidating the monitor alone only moved
// SpringBoard's end from FrontBoard's assert to that KVO crash. So when a monitor reaches -dealloc still valid, its owner is looked at: if it is being
// deallocated right now (the monitor is one of its ivars, released by its .cxx_destruct), each registration it still has for that key path on the
// object it observed -- its own ivar (Zetsu's _manager, released after _sceneMonitor) and the monitor's scene's layer manager -- is removed, as its
// close would have done, before it is gone.
// The delegate is a WEAK reference (-[FBSceneMonitor delegate]: objc_loadWeakRetained on the ivar at 104, 17.5.1), and a weak load answers nil once
// its object is being deallocated -- so the pointer is read from the ivar's own storage, which holds it until the runtime clears it after the
// object's .cxx_destruct. It is only used while that object is still mid-deallocation (its memory not freed yet), never retained (retain and
// release do nothing on an object being deallocated, iOS 15+), and only to call KVO's own -removeObserver:forKeyPath:.
#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kMSBDMonitorOwnerKeyPath = @"layers";   // (the one key path Zetsu's controllers observe: its CFString at 0x5da60, all six add/remove sites)

// The object an object-typed ivar of obj points to, read from the ivar's storage as it is (no retain, no weak load): NULL when there is no such ivar,
// it is not an object ivar, or it is empty. A plain pointer, so ARC never retains or releases it.
static inline void *MSBDIvarRaw(id obj, const char *name) {
    if (!obj || !name) return NULL;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!t || t[0] != '@') return NULL;
    return *(void **)((uint8_t *)(__bridge void *)obj + ivar_getOffset(iv));
}

// YES while the object at p is being deallocated (NSObject's own -_isDeallocating; NO for one that does not answer it).
static inline BOOL MSBDObjectDeallocating(void *p) {
    SEL s = sel_registerName("_isDeallocating");
    if (!p || !class_respondsToSelector(object_getClass((__bridge id)p), s)) return NO;
    return ((BOOL (*)(void *, SEL))objc_msgSend)(p, s);
}

// The monitor's delegate when it is being deallocated right now -- the owner that is dropping the monitor --, else NULL.
static inline void *MSBDMonitorOwnerGoing(id monitor) {
    void *owner = MSBDIvarRaw(monitor, "_delegate");
    return MSBDObjectDeallocating(owner) ? owner : NULL;
}

// Every registration of the observer at p for keyPath on observed removed (KVO keeps a registration made twice twice): how many were. KVO raises
// when there is none (left), which ends the loop.
static inline int MSBDRemoveObservations(id observed, void *p, NSString *keyPath) {
    int n = 0;
    if (!observed || !p || !keyPath) return 0;
    SEL rm = @selector(removeObserver:forKeyPath:);
    for (int i = 0; i < 16; i++) {
        @try { ((void (*)(id, SEL, void *, NSString *))objc_msgSend)(observed, rm, p, keyPath); n++; }
        @catch (NSException *e) { break; }
    }
    return n;
}

// The cleanup for a monitor that reached -dealloc still valid: its owner, when that is being deallocated, stops observing keyPath on the object its
// ivar ownerIvar points to (Zetsu's "_manager") and on also (the monitor's scene's layer manager; nil: none), each once. Returns how many
// registrations were removed (0: no owner going, or nothing registered); *ownerClass the owner's class name when there is one.
static inline int MSBDMonitorOwnerCleanup(id monitor, const char *ownerIvar, id also, NSString *keyPath, NSString **ownerClass) {
    void *owner = MSBDMonitorOwnerGoing(monitor);
    if (ownerClass) *ownerClass = owner ? NSStringFromClass(object_getClass((__bridge id)owner)) : nil;
    if (!owner) return 0;
    void *ownRaw = MSBDIvarRaw((__bridge id)owner, ownerIvar);
    id own = (__bridge id)ownRaw;   // (alive: the scene keeps its layer manager; Zetsu's .cxx_destruct releases _manager after _sceneMonitor)
    int n = MSBDRemoveObservations(own, owner, keyPath);
    if (also && also != own) n += MSBDRemoveObservations(also, owner, keyPath);
    return n;
}
