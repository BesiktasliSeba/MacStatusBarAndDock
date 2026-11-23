// test-stickygeometry.m -- Mac test of the geometry a sticky note gives its views (1.8.8.2): the rules in common/StickyNotes.h, run as written.
// A note's name field was made from its top bar's bounds with CGRectInset before the bar was laid out: CGRectInset of a zero rect is CGRectNull, an
// infinite origin, and UIKit's selection grabbers over that field got a NaN position (SpringBoard raised CALayerInvalidGeometry). The field's rect
// is now MSBDStickyNameFieldRect, finite for any bar.
#import <Foundation/Foundation.h>
#include <math.h>
#include "common/StickyNotes.h"

static int fails;
#define T(c, msg) do { if (c) printf("PASS    %s\n", msg); else { printf("FAIL    %s\n", msg); fails = 1; } } while (0)
static BOOL Same(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 1e-9 && fabs(a.origin.y - b.origin.y) < 1e-9 && fabs(a.size.width - b.size.width) < 1e-9 && fabs(a.size.height - b.size.height) < 1e-9; }

// The free area every note is placed in: Desktop.h's -dm_area, cut out by test-stickygeometry.sh (sg-area.inc) and run in a stand-in desktop whose
// bounds and native desktop the test sets. The desktop is made with a zero frame and gets its page's frame only once page 1 is there (-dm_tick):
// a store read or a store change before that (page 1 torn down under a full-screen window, a desktop made again from Settings) placed its notes in
// this area. CGRectInset of a zero rect is CGRectNull, so the area was CGRectNull, and every note made then got a frame that is not finite.
static CGRect gNativeDesktop;
static CGRect DMNativeDesktop(void) { return gNativeDesktop; }
@interface SGDesk : NSObject
@property (nonatomic) CGRect bounds;
- (CGRect)dm_area;
@end
@implementation SGDesk
#include "sg-area.inc"
@end
static CGRect OldArea(CGRect d, CGRect b) { CGRect a = CGRectIntersection(CGRectInset(d, 6.0, 4.0), b); return CGRectIsNull(a) || a.size.height < 100.0 ? CGRectInset(b, 6.0, 30.0) : a; }   // (1.8.8.1.1's rule)

int main(void) { @autoreleasepool {
    // ---- the cause, in CoreGraphics' own answer ----
    CGRect old = CGRectInset(CGRectZero, 6.0, 2.0);
    T(CGRectIsNull(old) && isinf(old.origin.x) && isinf(old.origin.y), "the cause: CGRectInset of a bar not laid out yet (zero) by 6 x 2 is CGRectNull, an infinite origin");
    T(!MSBDStickyRectOK(old) && !MSBDStickyRectOK(CGRectNull), "  ... MSBDStickyRectOK refuses it (CGRectNull)");
    T(!MSBDStickyRectOK(CGRectMake(NAN, 0, 10, 10)) && !MSBDStickyRectOK(CGRectMake(0, NAN, 10, 10)) && !MSBDStickyRectOK(CGRectMake(0, 0, NAN, 10)) && !MSBDStickyRectOK(CGRectMake(0, 0, 10, INFINITY)),
      "  ... and a NaN or an infinity in any of the four numbers");
    T(MSBDStickyRectOK(CGRectZero) && MSBDStickyRectOK(CGRectMake(-20, -30, 220, 22)) && MSBDStickyRectOK(CGRectMake(5, 5, -3, -3)), "  ... takes any finite rect (zero, negative origin, negative size: UIKit's to standardize)");
    // ---- the name field's rect ----
    T(Same(MSBDStickyNameFieldRect(CGRectMake(0, 0, 220, MSBD_NOTE_BAR)), CGRectMake(6, 2, 208, 18)), "the name field in a 220 pt note's bar: inset 6 x 2 (6, 2, 208, 18), as before");
    T(Same(MSBDStickyNameFieldRect(CGRectMake(0, 0, 120, MSBD_NOTE_BAR)), CGRectMake(6, 2, 108, 18)), "  ... in the smallest note's (120 pt): 108 x 18");
    T(Same(MSBDStickyNameFieldRect(CGRectZero), CGRectZero), "  ... in a bar not laid out yet (zero): a zero rect, never CGRectNull (the crash)");
    T(Same(MSBDStickyNameFieldRect(CGRectMake(0, 0, 8, 3)), CGRectMake(4, 1.5, 0, 0)), "  ... in a bar smaller than the insets: an empty rect at its middle, never a negative size");
    T(Same(MSBDStickyNameFieldRect(CGRectMake(10, 20, 220, 22)), CGRectMake(16, 22, 208, 18)), "  ... from the bar's origin (its bounds' origin moved)");
    T(Same(MSBDStickyNameFieldRect(CGRectNull), CGRectZero) && Same(MSBDStickyNameFieldRect(CGRectMake(NAN, 0, 220, 22)), CGRectZero) && Same(MSBDStickyNameFieldRect(CGRectMake(0, 0, INFINITY, 22)), CGRectZero),
      "  ... from a bar that is itself not finite: a zero rect");
    double w[] = { 0, 0.5, 1, 7, 11.9, 12, 12.1, 120, 220, 4096 }, h[] = { 0, 1, 3.9, 4, 4.1, 21.5, 22 };
    BOOL ok = YES;
    for (int i = 0; i < 10; i++) for (int j = 0; j < 7; j++) { CGRect r = MSBDStickyNameFieldRect(CGRectMake(0, 0, w[i], h[j])); if (!MSBDStickyRectOK(r) || r.size.width < 0 || r.size.height < 0 || CGRectGetMaxX(r) > w[i] + 1e-9 || CGRectGetMaxY(r) > h[j] + 1e-9) ok = NO; }
    T(ok, "  ... for every bar size from 0 to 4096 pt: finite, never a negative size, inside the bar");
    // ---- every geometry the notes give a view: finite only (DesktopNotes.h DMStickySetFrame and its siblings refuse any other) ----
    T(MSBDStickyPointOK(CGPointMake(0, 0)) && MSBDStickyPointOK(CGPointMake(-1e6, 1e6)) && !MSBDStickyPointOK(CGPointMake(NAN, 0)) && !MSBDStickyPointOK(CGPointMake(0, INFINITY)) && !MSBDStickyPointOK(CGPointMake(-INFINITY, NAN)),
      "a point: finite numbers only");
    CGAffineTransform t = CGAffineTransformMakeRotation(M_PI_4), bad = CGAffineTransformMakeScale(0, 0);
    T(MSBDStickyTransformOK(t) && MSBDStickyTransformOK(CGAffineTransformIdentity) && MSBDStickyTransformOK(bad), "a transform: a turn, the identity, even a zero scale (finite) are taken");
    BOOL each = YES;
    for (int k = 0; k < 6; k++) { CGAffineTransform x = t; CGFloat *f = (CGFloat *)&x; f[k] = NAN; if (MSBDStickyTransformOK(x)) each = NO; f[k] = INFINITY; if (MSBDStickyTransformOK(x)) each = NO; }
    T(each && !MSBDStickyTransformOK(CGAffineTransformInvert(bad)) == !(isfinite(CGAffineTransformInvert(bad).a)), "  ... a NaN or an infinity in any of its six numbers is refused");
    // ---- the free area a note is placed in (Desktop.h -dm_area): finite for a desktop not on its page yet ----
    SGDesk *desk = [SGDesk new];
    gNativeDesktop = CGRectMake(0, 24, 1024, 654);   // (a 1024 x 768 screen: the 24 pt menu bar, the Dock below)
    desk.bounds = CGRectMake(0, 0, 1024, 768);
    T(Same([desk dm_area], CGRectMake(6, 28, 1012, 646)), "the free area of a desktop on its page: the native desktop 6 / 4 pt in, as before");
    desk.bounds = CGRectZero;
    T(CGRectIsNull(OldArea(gNativeDesktop, CGRectZero)), "the cause: a desktop not on its page yet (made with a zero frame) had CGRectNull as its free area (CGRectInset of zero by 6 x 30)");
    CGRect za = [desk dm_area];
    NSString *zs = [NSString stringWithFormat:@"  ... now an empty area of finite numbers at its middle (%@)", NSStringFromRect(NSRectFromCGRect(za))];
    T(MSBDStickyRectOK(za) && CGRectIsEmpty(za) && Same(za, CGRectZero), zs.UTF8String);
    CGPoint zp = CGPointMake(za.origin.x + 0.3 * za.size.width, za.origin.y + 0.4 * za.size.height);   // (Desktop.h -dm_pointFor:area:, a stored note's centre)
    CGRect zf = MSBDStickyFrameAt(za, zp, CGSizeMake(220, 180));
    T(MSBDStickyRectOK(zf) && MSBDStickyRectOK(MSBDStickyPlaceClearFit(zf, za, NULL, 0, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), MSBD_NOTE_CLEAR_TESTS, NULL)),
      "  ... a note made then (-dm_noteStoreChanged, -dm_notePlace:of:) gets a finite frame, placed or not: none refused by the setters");
    CGRect nf = MSBDStickyFrameAt(OldArea(gNativeDesktop, CGRectZero), CGPointMake(INFINITY, INFINITY), CGSizeMake(220, 180));
    T(!MSBDStickyRectOK(nf), "  ... (with the old area it was {{inf, inf}, {0, 0}}: the debug build's setters refused it)");
    desk.bounds = CGRectMake(0, 0, 1024, 50);
    T(Same([desk dm_area], CGRectMake(512, 25, 0, 0)), "  ... a desktop too small for the insets: an empty area at its middle");
    gNativeDesktop = CGRectMake(2000, 0, 100, 100); desk.bounds = CGRectMake(0, 0, 1024, 768);
    T(Same([desk dm_area], CGRectMake(6, 30, 1012, 708)), "  ... the native desktop off this desktop: its own bounds 6 / 30 pt in, as before");
    BOOL areaOK = YES, sameAsOld = YES;
    double sz[] = { 0, 1, 11.9, 12, 13, 59.9, 60, 61, 99, 100, 101, 400, 768, 1024, 1366, 2560 };
    CGRect ds[] = { CGRectMake(0, 24, 1024, 654), CGRectMake(0, 24, 1366, 900), CGRectZero, CGRectMake(-50, -50, 40, 40), CGRectMake(0, 0, 2560, 1440) };
    for (int k = 0; k < 5; k++) for (int i = 0; i < 16; i++) for (int j = 0; j < 16; j++) {
        gNativeDesktop = ds[k]; desk.bounds = CGRectMake(0, 0, sz[i], sz[j]);
        CGRect a = [desk dm_area], o = OldArea(ds[k], desk.bounds);
        if (!MSBDStickyRectOK(a) || a.size.width < 0 || a.size.height < 0) areaOK = NO;
        if (!CGRectIsNull(o) && !Same(a, o)) sameAsOld = NO;
    }
    T(areaOK, "  ... for every desktop size from 0 to 2560 pt and five native desktops: finite, never a negative size");
    T(sameAsOld, "  ... and wherever the old rule gave an area, the same area (nothing else changes for the desktop's icons or the notes)");
    printf("%s\n", fails ? "test-stickygeometry rules: FAILED" : "test-stickygeometry rules: all passed");
} return fails; }
