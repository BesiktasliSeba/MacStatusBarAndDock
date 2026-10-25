// prewarmblock/PrewarmShape.h -- MacStatusBar&Dock 1.5.1: the shape a dasd method must have before PrewarmBlock.x hooks it. Plain Objective-C
// runtime; Mac test tools/test-prewarmshape.sh.
// An object return and one object argument after self/_cmd ("@24@0:8@16"): anything else is never hooked. Refusing is returning nil, which says
// "nothing" only for an object return -- a void method (accepted until 1.5.1's logic test, C1) is not hooked. Checked for EACH method (until 1.5.0
// only the first one's shape was, and %init hooked the second blindly: external logic test W6, 25 Oct).
#pragma once
#import <objc/runtime.h>

static BOOL DMPrewarmShapeOK(Method m) {
    const char *enc = m ? method_getTypeEncoding(m) : NULL;
    if (!enc || enc[0] != '@' || method_getNumberOfArguments(m) != 3) return NO;
    char arg[8] = {0};
    method_getArgumentType(m, 2, arg, sizeof(arg));
    return arg[0] == '@';
}
