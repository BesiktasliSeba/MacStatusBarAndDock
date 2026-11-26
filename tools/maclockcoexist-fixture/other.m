// other.m -- test-maclockcoexist's stand-in for another modification (built as a dylib in a plain folder: "another's" by its path) and, built again
// with -DOURS into a .../MacStatusBarAndDock/ folder, for one of our own parts. It swizzles the test tool's watched classes the ways tweaks do:
// method_setImplementation with its own function, a block implementation, _objc_msgForward, a runtime subclass (an isa swizzle), a hook on a
// base class, and it defines a CALayer and an NSView class of its own for the layer walk.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#ifdef OURS
#define EXP(n) ours_##n
#else
#define EXP(n) other_##n
#endif
static void hookFn(id self, SEL _cmd) { (void)self; (void)_cmd; }
static id descFn(id self, SEL _cmd) { (void)self; (void)_cmd; return @"x"; }
__attribute__((visibility("default"))) IMP EXP(swizzle)(Class c, SEL s) { Method m = class_getInstanceMethod(c, s); return method_setImplementation(m, (IMP)hookFn); }
__attribute__((visibility("default"))) IMP EXP(swizzleBlock)(Class c, SEL s) { Method m = class_getInstanceMethod(c, s); return method_setImplementation(m, imp_implementationWithBlock(^(id me) { (void)me; })); }
__attribute__((visibility("default"))) IMP EXP(swizzleForward)(Class c, SEL s) { Method m = class_getInstanceMethod(c, s); return method_setImplementation(m, _objc_msgForward); }
__attribute__((visibility("default"))) IMP EXP(hookBase)(void) { Method m = class_getInstanceMethod([NSObject class], @selector(description)); return method_setImplementation(m, (IMP)descFn); }
__attribute__((visibility("default"))) Class EXP(runtimeSubclass)(Class sup) {
    Class k = objc_allocateClassPair(sup, "MLTestIsaSwizzle", 0);
    class_addMethod(k, @selector(layoutSubviews), (IMP)hookFn, "v@:");
    objc_registerClassPair(k);
    return k;
}
#ifndef OURS
@interface OtherLayer : CALayer
@end
@implementation OtherLayer
@end
@interface OtherView : NSView
@end
@implementation OtherView
@end
__attribute__((visibility("default"))) CALayer *EXP(layer)(void) { return [OtherLayer layer]; }
__attribute__((visibility("default"))) NSView *EXP(view)(void) { NSView *v = [[OtherView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]; v.wantsLayer = YES; return v; }
#endif
