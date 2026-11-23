// test-pointeraside-other.m: the "other library" of tools/test-pointeraside.sh, built as a library of its own under a "/var/jb/" path (as a tweak's
// is on the iPad): a view and a layer class of its own, a function used as a hook on pointeruid's (fake) pointer classes, and one that makes a plain
// shape layer, a class of the system's (only its place on the pointer tells it is another pointer).
#import <UIKit/UIKit.h>
@interface PointerOtherArrowView : UIView
@end
@implementation PointerOtherArrowView
@end
@interface PointerOtherLayer : CALayer
@end
@implementation PointerOtherLayer
@end
void PointerOtherHook(id self, SEL _cmd) { (void)self; (void)_cmd; }
CAShapeLayer *PointerOtherShapeLayer(void) {
    CAShapeLayer *l = [CAShapeLayer layer];
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, 0, 0); CGPathAddLineToPoint(p, NULL, 0, 17); CGPathAddLineToPoint(p, NULL, 12, 12); CGPathCloseSubpath(p);
    l.path = p; CGPathRelease(p);
    l.fillColor = [UIColor blackColor].CGColor;
    l.bounds = CGRectZero;   // (a zero-size layer whose path draws outside it)
    return l;
}
