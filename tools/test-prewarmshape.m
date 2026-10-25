// Mac test of prewarmblock/PrewarmShape.h (1.5.1, logic test C1): only a method with an object return and one object argument is hooked -- the
// refusal returns nil, which means "nothing" only there.
#import <Foundation/Foundation.h>
#include "../prewarmblock/PrewarmShape.h"
static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface MSBShapes : NSObject @end
@implementation MSBShapes
- (id)prewarmLaunchAppFromBundleID:(id)b { return b; }               // (dasd's shape: @24@0:8@16)
- (void)voidWith:(id)b { (void)b; }                                  // (void return: refused since C1)
- (id)intArg:(int)n { return @(n); }                                 // (not an object argument)
- (id)noArg { return nil; }                                          // (no argument)
- (id)two:(id)a args:(id)b { return a ?: b; }                        // (two arguments)
- (BOOL)boolWith:(id)b { return b != nil; }                          // (a BOOL return)
- (Class)classWith:(id)b { return [b class]; }                       // (a Class return: '#', not '@')
@end

int main(void) {
    @autoreleasepool {
        Class c = [MSBShapes class];
        Method m = class_getInstanceMethod(c, @selector(prewarmLaunchAppFromBundleID:));
        CHECK(DMPrewarmShapeOK(m), "dasd's shape (%s): hooked", method_getTypeEncoding(m));
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(voidWith:))), "a void return: never hooked (C1)");
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(intArg:))), "an int argument: never hooked");
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(noArg))), "no argument: never hooked");
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(two:args:))), "two arguments: never hooked");
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(boolWith:))), "a BOOL return: never hooked");
        CHECK(!DMPrewarmShapeOK(class_getInstanceMethod(c, @selector(classWith:))), "a Class return: never hooked");
        CHECK(!DMPrewarmShapeOK(NULL), "no method: never hooked");
    }
    printf("test-prewarmshape: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
