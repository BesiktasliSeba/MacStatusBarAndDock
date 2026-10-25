// ZetsuGuard.h -- MacStatusBar&Dock 1.5.0: a narrow WORKAROUND for a crash inside Zetsu (jp.dcsyhi.zetsu 1.6.x), not a fix of ours.
// Zetsu observes its own "CloseSwitcherRemoveAlert" notification with a block that captures its ZetsuAlertHostController without keeping it
// alive, and does not remove that observer when the controller goes. Zetsu posts the notification at the start of every layout transition (its
// own hook of -[SBLayoutStateTransitionCoordinator beginTransitionForWorkspaceTransaction:]), so the first transition after the controller was
// freed sends -alertController to freed memory and SpringBoard crashes (the M1, iOS 15, 13 Oct: two crash reports, the second with no frame of
// ours; release-1.4.5.md "M1 device pass (RC3)", ipados17-port.md 4f).
// With Zetsu as the window engine only (StatusBar.x installs the hook then): when Zetsu registers that one observer, its block is wrapped so it
// holds the controller weakly, and once the controller is gone the block is not run. The controller is recognised by pointer: one of the words
// the block captured equals one of the live ZetsuAlertHostController objects (tracked from their allocation); unknown memory is never read as an
// object. Plain Foundation and the Objective-C runtime: the Mac test tools/test-zetsuguard.m runs it with a stand-in class.
#pragma once
#if !__has_feature(objc_arc)
#error "ZetsuGuard.h needs ARC (-fobjc-arc): its wrapper holds the controller with a __weak reference"
#endif
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

static NSString *const kMSBDZetsuRemoveAlertNote = @"CloseSwitcherRemoveAlert";
static NSHashTable *gMSBDZetsuHosts;   // (the live ZetsuAlertHostController objects, weakly)

// The pointer-sized words a block keeps in its captured variables (everything after its descriptor), at most max of them; 0 when it has none.
// Only the block's own memory is read (its descriptor says its size); the words found are compared, never dereferenced.
static inline NSUInteger MSBDBlockCaptureWords(id block, const void **out, NSUInteger max) {
    if (!block || !out || !max) return 0;
    const uint8_t *b = (const uint8_t *)(__bridge const void *)block;
    // struct Block_layout { void *isa; int32_t flags; int32_t reserved; void *invoke; struct Block_descriptor *descriptor; ...captured variables }
    const void *d = *(const void *const *)(b + sizeof(void *) + 2 * sizeof(int32_t) + sizeof(void *));
#if __has_feature(ptrauth_calls)
    d = ptrauth_strip(d, ptrauth_key_asda);   // (descriptor pointers may be signed on arm64e)
#endif
    if (!d) return 0;
    uintptr_t size = ((const uintptr_t *)d)[1];   // (struct Block_descriptor { uintptr_t reserved; uintptr_t size; ... })
    size_t first = sizeof(void *) + 2 * sizeof(int32_t) + 2 * sizeof(void *);
    if (size < first + sizeof(void *) || size > 1024) return 0;   // (no capture; or not a size a block literal has: nothing read)
    NSUInteger n = 0;
    for (size_t o = first; o + sizeof(void *) <= size && n < max; o += sizeof(void *)) out[n++] = *(const void *const *)(b + o);
    return n;
}

// Zetsu's observer block for kMSBDZetsuRemoveAlertNote, wrapped: nil when none of its captured words is one of the live controllers (left as it
// is then). The wrapper keeps the controller alive while the original block runs, and skips it once the controller is gone.
static inline id MSBDZetsuGuardBlock(id block, NSHashTable *hosts) {
    const void *words[64];
    NSUInteger n = MSBDBlockCaptureWords(block, words, 64);
    if (!n) return nil;
    id host = nil;
    @autoreleasepool {   // (the copied list goes at once: it held every controller)
        for (id h in hosts.allObjects) {
            for (NSUInteger i = 0; i < n && !host; i++) if ((__bridge const void *)h == words[i]) host = h;
            if (host) break;
        }
    }
    if (!host) return nil;
    // (a weak reference names the object, not its address: it is cleared when that controller is deallocated, so a new object made later at the
    //  same address -- even another controller -- never passes as it; the class is checked again at each call all the same)
    __weak id weakHost = host;
    Class hostClass = object_getClass(host);
    void (^original)(NSNotification *) = [block copy];
    return [^(NSNotification *note) {
        id alive = weakHost;
        if (!alive || object_getClass(alive) != hostClass) return;   // (the controller is gone: the block would message freed memory)
        original(note);
    } copy];
}

// The live controllers, from their allocation to their deallocation (a weak table: an entry goes when its controller is deallocated):
// +allocWithZone: added to that class alone (calls its superclass's; never replaces one the class has).
// The super lookup starts above the class the method was ADDED to, never above the receiver: a subclass's +alloc reaches this same method with
// the subclass as self, and its superclass is the hooked class itself, whose metaclass holds this method -- the lookup found it again and
// recursed until the stack overflowed (external logic test C1, 25 Oct; Zetsu 1.6.6 has no subclass, so it never happened).
static Class gMSBDZetsuHostClass;   // (the class MSBDZetsuTrackHosts added the method to)
static id MSBDZetsuHostAlloc(id self, SEL _cmd, struct _NSZone *zone) {
    Class base = gMSBDZetsuHostClass ?: (Class)self;
    struct objc_super sup = { self, object_getClass(class_getSuperclass(base)) };   // (a class method: the lookup starts in that superclass's metaclass)
    id obj = ((id (*)(struct objc_super *, SEL, struct _NSZone *))objc_msgSendSuper)(&sup, _cmd, zone);
    if (obj) @synchronized ([NSHashTable class]) { if (!gMSBDZetsuHosts) gMSBDZetsuHosts = [NSHashTable weakObjectsHashTable]; [gMSBDZetsuHosts addObject:obj]; }
    return obj;
}
static inline BOOL MSBDZetsuTrackHosts(Class hostClass) {
    if (!hostClass) return NO;
    Class meta = object_getClass(hostClass);
    Method own = NULL; unsigned int n = 0; Method *ms = class_copyMethodList(meta, &n);
    for (unsigned int i = 0; i < n; i++) if (method_getName(ms[i]) == @selector(allocWithZone:)) own = ms[i];
    free(ms);
    if (own) return NO;   // (the class allocates its own way: left alone)
    Method base = class_getClassMethod(hostClass, @selector(allocWithZone:));
    if (gMSBDZetsuHostClass && gMSBDZetsuHostClass != hostClass) return NO;   // (one class only: the method knows its class by this static)
    gMSBDZetsuHostClass = hostClass;
    return class_addMethod(meta, @selector(allocWithZone:), (IMP)MSBDZetsuHostAlloc, base ? method_getTypeEncoding(base) : "@@:^{_NSZone=}");
}
