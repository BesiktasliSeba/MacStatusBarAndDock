// test-stickygeometry-ui.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a sticky note's name field over its top bar (1.8.8.2, a device pass of its test build:
// Rename from an idle note's menu raised in SpringBoard, CALayerInvalidGeometry "CALayer position contains NaN" on a selection grabber dot).
// (a) UIKit's own answer to the construction that crashed: the field made with CGRectInset of a bar not laid out yet (flexible width and height),
//     the bar then laid out: the field keeps an infinite origin, its points in the window are NaN, and a view placed at one raises UIKit's
//     CALayerInvalidGeometry, the device's exception word for word.
// (b) The real DMNoteBar, cut out of statusbar/DesktopNotes.h by test-stickygeometry.sh (sg-bar.inc), with the field's rect from the real
//     MSBDStickyNameFieldRect: finite before and after the bar's layout, laid out by the bar itself, a view placed at its points never raises.
#import <UIKit/UIKit.h>
#include <math.h>
#include "common/StickyNotes.h"

static void DMStickyDrawName(NSString *name, CGRect bar) { (void)name; (void)bar; }   // (the drawing: not this test's)
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s ?: @""]; }
#include "sg-set.inc"   // (DMStickyGeometryRefused, DMStickySetFrame, DMStickyFrame, DMStickySetCenter, DMStickySetTransform, DMStickySetBottomInset)
#include "sg-bar.inc"   // (DMNoteBar, as statusbar/DesktopNotes.h has it)

static int fails;
static void Check(BOOL ok, NSString *what) { if (!ok) fails = 1; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
static BOOL Finite(CGRect r) { return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height); }
static BOOL FinitePoint(CGPoint p) { return isfinite(p.x) && isfinite(p.y); }
// A view placed at a point converted out of the field, as UIKit places a selection grabber dot: nil when it was placed, else the exception's text.
static NSString *PlaceDotFrom(UIView *field, UIWindow *w) {
    UIView *dot = [UIView new]; [w addSubview:dot];
    NSString *r = nil;
    @try { dot.center = [w convertPoint:CGPointMake(1, 1) fromView:field]; } @catch (NSException *x) { r = [NSString stringWithFormat:@"%@: %@", x.name, x.reason]; }
    [dot removeFromSuperview];
    return r;
}

int main(void) {
    @autoreleasepool {
        UIWindow *w = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
        // ---- (a) the construction of the first 1.8.8.2 build, in UIKit itself ----
        UIView *bar0 = [UIView new]; [w addSubview:bar0];
        UITextField *f0 = [[UITextField alloc] initWithFrame:CGRectInset(bar0.bounds, 6.0, 2.0)];
        f0.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [bar0 addSubview:f0];
        bar0.frame = CGRectMake(240, 273, 120, MSBD_NOTE_BAR); [bar0 layoutIfNeeded];
        Check(!Finite(f0.frame), [NSString stringWithFormat:@"(a) the first 1.8.8.2 build's field, made from a bar not laid out yet and autoresized: its frame stays not finite after the bar's layout (%@)", NSStringFromCGRect(f0.frame)]);
        CGPoint p0 = [f0 convertPoint:CGPointMake(10, 5) toView:w];
        Check(isnan(p0.x) && isnan(p0.y), [NSString stringWithFormat:@"  ... its points in the window are NaN (%@)", NSStringFromCGPoint(p0)]);
        NSString *x0 = PlaceDotFrom(f0, w);
        Check(x0 && [x0 hasPrefix:@"CALayerInvalidGeometry: CALayer position contains NaN: [nan nan]"], [NSString stringWithFormat:@"  ... and a view placed at one raises the device's exception (%@)", x0 ? [x0 substringToIndex:MIN((NSUInteger)64, x0.length)] : @"nothing raised"]);

        // ---- (b) the code's bar and field ----
        DMNoteBar *bar = [DMNoteBar new]; [w addSubview:bar];
        UITextField *f = [[UITextField alloc] initWithFrame:MSBDStickyNameFieldRect(bar.bounds)];
        bar.field = f; [bar addSubview:f];
        Check(Finite(f.frame) && CGRectEqualToRect(f.frame, CGRectZero), [NSString stringWithFormat:@"(b) the field made from a bar not laid out yet: finite, zero (%@)", NSStringFromCGRect(f.frame)]);
        Check(PlaceDotFrom(f, w) == nil, @"  ... a view placed at its points: placed, nothing raised");
        bar.frame = CGRectMake(240, 273, 120, MSBD_NOTE_BAR); [bar layoutIfNeeded];
        Check(CGRectEqualToRect(f.frame, CGRectMake(6, 2, 108, 18)), [NSString stringWithFormat:@"  ... the bar laid out (120 x 22): the bar lays its field out at 6, 2, 108 x 18 (%@)", NSStringFromCGRect(f.frame)]);
        CGPoint p = [f convertPoint:CGPointMake(10, 5) toView:w];
        Check(FinitePoint(p) && fabs(p.x - 256) < 1e-9 && fabs(p.y - 280) < 1e-9, [NSString stringWithFormat:@"  ... its points in the window finite and right (%@)", NSStringFromCGPoint(p)]);
        Check(PlaceDotFrom(f, w) == nil, @"  ... a view placed at its points: placed, nothing raised");
        bar.frame = CGRectMake(240, 273, 400, MSBD_NOTE_BAR); [bar layoutIfNeeded];
        Check(CGRectEqualToRect(f.frame, CGRectMake(6, 2, 388, 18)), @"  ... the note resized while the name is edited: the field follows its bar (388 pt)");
        bar.frame = CGRectZero; [bar layoutIfNeeded];
        Check(Finite(f.frame) && PlaceDotFrom(f, w) == nil, @"  ... a bar of no size again: the field finite, nothing raised");
        bar.field = nil; [f removeFromSuperview];
        UITextField *other = [[UITextField alloc] initWithFrame:CGRectMake(1, 2, 3, 4)]; [bar addSubview:other];
        bar.frame = CGRectMake(0, 0, 220, MSBD_NOTE_BAR); [bar layoutIfNeeded];
        Check(CGRectEqualToRect(other.frame, CGRectMake(1, 2, 3, 4)), @"  ... the bar lays out only its own name field (none set: another subview untouched)");

        // ---- (c) the setters every geometry of the notes goes through: finite values set, others refused ----
        gLog = [NSMutableArray array];
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(10, 20, 30, 40)]; [w addSubview:v];
        DMStickySetFrame(v, CGRectMake(1, 2, 3, 4), "a test site");
        DMStickySetCenter(v, CGPointMake(50, 60), "a test site");
        DMStickySetTransform(v, CGAffineTransformMakeRotation(M_PI_4), "a test site");
        Check(CGPointEqualToPoint(v.center, CGPointMake(50, 60)) && CGAffineTransformEqualToTransform(v.transform, CGAffineTransformMakeRotation(M_PI_4)) && gLog.count == 0, @"(c) finite values: set as given, nothing logged");
        v.transform = CGAffineTransformIdentity; v.frame = CGRectMake(10, 20, 30, 40);
        UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
        Check(CGRectEqualToRect(DMStickyFrame(CGRectMake(5, 6, 7, 8), "a test site"), CGRectMake(5, 6, 7, 8)), @"  ... a view made with a finite frame: that frame");
#if DEBUG
        // (a debug build only logs it: a raise stopped SpringBoard, and a device pass with it, for a value the release build skips -- 1.8.8.2's review)
        NSString *(^raised)(void (^)(void)) = ^NSString *(void (^b)(void)) { @try { b(); } @catch (NSException *x) { return [NSString stringWithFormat:@"%@: %@", x.name, x.reason]; } return nil; };
        NSString *r1 = raised(^{ DMStickySetFrame(v, CGRectInset(CGRectZero, 6, 2), "the name field in its bar"); });
        Check(r1 == nil && CGRectEqualToRect(v.frame, CGRectMake(10, 20, 30, 40)), [NSString stringWithFormat:@"  ... DEBUG: a frame that is not finite is refused, the view as it was, nothing raised (%@)", r1 ?: @"nothing"]);
        Check(gLog.count == 1 && [gLog[0] isEqualToString:@"[notes] ASSERTION: a geometry that is not finite ({{inf, inf}, {0, 0}}) refused at the name field in its bar"], [NSString stringWithFormat:@"  ... DEBUG: and the log says so, naming the value and the site (%@)", gLog.firstObject ?: @"no line"]);
        tv.contentInset = UIEdgeInsetsMake(1, 2, 3, 4);
        NSString *r2 = raised(^{ DMStickySetCenter(v, CGPointMake(NAN, 1), "a test site"); DMStickySetTransform(v, CGAffineTransformMakeScale(INFINITY, 1), "a test site");
                                 (void)DMStickyFrame(CGRectMake(0, 0, NAN, 1), "a test site"); DMStickySetBottomInset(tv, NAN, "a test site"); });
        Check(r2 == nil && gLog.count == 5 && CGRectEqualToRect(v.frame, CGRectMake(10, 20, 30, 40)) && CGAffineTransformIsIdentity(v.transform) && tv.contentInset.bottom == 3
              && CGRectEqualToRect(DMStickyFrame(CGRectNull, "a test site"), CGRectZero),
              @"  ... DEBUG: a centre, a transform, a made view's frame and an inset that are not finite: refused, one log line each, nothing raised (a made view: a zero frame)");
#else
        DMStickySetFrame(v, CGRectInset(CGRectZero, 6, 2), "a test site");
        DMStickySetFrame(v, CGRectMake(NAN, 0, 1, 1), "a test site");
        DMStickySetCenter(v, CGPointMake(NAN, 1), "a test site");
        DMStickySetTransform(v, CGAffineTransformMakeScale(INFINITY, 1), "a test site");
        Check(CGRectEqualToRect(v.frame, CGRectMake(10, 20, 30, 40)) && CGAffineTransformIsIdentity(v.transform), @"  ... release: a frame, a centre or a transform that is not finite is refused, the view as it was (nothing raised)");
        Check(CGRectEqualToRect(DMStickyFrame(CGRectNull, "a test site"), CGRectZero), @"  ... release: a view made with a frame that is not finite gets a zero frame");
        tv.contentInset = UIEdgeInsetsMake(1, 2, 3, 4);
        DMStickySetBottomInset(tv, NAN, "a test site");
        Check(tv.contentInset.bottom == 3, @"  ... release: an inset that is not finite is refused");
        DMStickySetBottomInset(tv, 12, "a test site");
        Check(tv.contentInset.bottom == 12 && tv.contentInset.top == 1 && tv.contentInset.left == 2 && tv.contentInset.right == 4, @"  ... a finite bottom inset: only the bottom set");
        Check(gLog.count == 0, @"  ... release: nothing raised (the log is a debug build's)");
#endif
    }
    printf("%s\n", fails ? "test-stickygeometry UIKit: FAILED" : "test-stickygeometry UIKit: all passed");
    return fails;
}
