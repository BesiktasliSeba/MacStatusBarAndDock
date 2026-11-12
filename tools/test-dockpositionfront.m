// test-dockpositionfront.m -- Mac test of a Dock Position change on the Stage Manager engine (A12Z 18.5, regression 1.8.4, 9 Nov): picking Left brought the window behind Settings
// in front of it until Settings was tapped in the Dock. A window under the Dock's new place was moved out of it by a request for that window alone, and a request names its window
// as the stage's frontmost. The code as built: the Stage Manager branch of DMDockPositionMoved cut out of statusbar/StatusBar.x (test-dockpositionfront.sh), with stand-ins for the stage.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "DockSide.h"
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
@interface NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
@end
@implementation NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r { return [NSValue valueWithBytes:&r objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect r; [self getValue:&r]; return r; }
@end
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen; @property (nonatomic, readonly) CGRect bounds;
@end
static CGSize gScreen;
@implementation UIScreen
+ (UIScreen *)mainScreen { return [UIScreen new]; }
- (CGRect)bounds { return CGRectMake(0, 0, gScreen.width, gScreen.height); }
@end
#define DMLog(...) do { (void)(__VA_ARGS__); } while (0)
#define DM_FEATURE_MARK(x) do { } while (0)
static const CGFloat kSMBarH = 24.0;
// The stage, as SpringBoard answers: a request for one window makes it the frontmost; a request for the whole stage keeps the newest in front.
static NSString *gFront; static NSDictionary<NSString *, NSValue *> *gFrames; static CGRect gArea; static int gOneByOne, gWhole; static NSDictionary *gPlaces;
static BOOL DMSMEngine(void) { return YES; }
static NSDictionary<NSString *, NSValue *> *DMSMOpenWindowFrames(void) { return gFrames; }
static CGRect DMSMUsableAreaForIdentity(id i, CGSize *s) { (void)i; (void)s; return gArea; }
static BOOL DMSMSetWindowGeometry(NSString *key, CGPoint c, CGSize s) { (void)c; (void)s; gOneByOne++; gFront = key; return YES; }
static BOOL DMSMApplyPlacesIn(NSDictionary<NSString *, id> *places, id stage) { (void)stage; gWhole++; gPlaces = places; return YES; }
static int gSMIPadDesktopScope = 0;   // (1.8.7: the iPad's own stage while its desktop changes; DMSMWorkingStage answers it in StatusBar.x)
static id DMSMWorkingStage(void) { return @"stage"; }
static NSMutableDictionary *DMSMTurnLayouts(void) { return [NSMutableDictionary dictionary]; }
static void DMSMFitHiddenStages(id o, NSDictionary *l, NSDictionary *p) { (void)o; (void)l; (void)p; }
static void DMMSWDockMovedRecords(void) { }
static void Run(NSDictionary<NSString *, NSString *> *layouts) {
    gFront = @"settings"; gOneByOne = gWhole = 0; gPlaces = nil;
    do {
#include "dockpositionfront-gen.h"
    } while (0);
}
static NSValue *R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return [NSValue valueWithCGRect:CGRectMake(x, y, w, h)]; }
int main(void) { @autoreleasepool {
    gScreen = CGSizeMake(1366, 1024);
    gArea = CGRectMake(76, 24, 1290, 1000);   // (the desktop with the Dock on the left)
    CGRect under = CGRectMake(0, 100, 500, 600);
    gFrames = @{ @"settings": R(300, 100, 700, 700), @"behind": [NSValue valueWithCGRect:under] };
    Run(@{});
    Expect([gFront isEqualToString:@"settings"], [NSString stringWithFormat:@"Left picked, a window behind under the Dock's new place: the window in use stays in front (front: %@)", gFront]);
    Expect(gWhole == 1 && gOneByOne == 0, [NSString stringWithFormat:@"  ... one request for the whole stage, none for a window alone (whole %d, alone %d)", gWhole, gOneByOne]);
    CGRect want = MSBDDockSideKeepOut(under, gArea, MSBDDockKeepMove);
    Expect(CGRectEqualToRect([gPlaces[@"behind"] CGRectValue], want) && !CGRectEqualToRect(want, under), @"  ... the window under the Dock goes where it did: kept out of the Dock, the whole window");
    Expect(gPlaces[@"settings"] == nil, @"  ... the window that lies inside the desktop is not moved");
    // A window in a layout, placed a moment before (the request may not be in the model yet): named again with its layout
    gFrames = @{ @"settings": R(300, 100, 700, 700), @"behind": [NSValue valueWithCGRect:under], @"clock": R(76, 24, 645, 1000) };
    Run(@{ @"clock": @"left", @"gone": @"right" });
    Expect([gPlaces[@"clock"] isEqual:@"left"], @"a window in a layout is named with its layout in that request, not left to the model");
    Expect(gPlaces[@"gone"] == nil, @"  ... a layout of a window not on the desktop: not named");
    Expect([gFront isEqualToString:@"settings"], @"  ... the window in use stays in front");
    // Nothing under the Dock: no request at all
    gFrames = @{ @"settings": R(300, 100, 700, 700), @"clock": R(76, 24, 645, 1000) };
    Run(@{ @"clock": @"left" });
    Expect(gWhole == 0 && gOneByOne == 0, [NSString stringWithFormat:@"nothing under the Dock: no request here (whole %d, alone %d), a Position change back to the bottom", gWhole, gOneByOne]);
    // A full-screen window is left alone
    gFrames = @{ @"full": R(0, -24, 1366, 1048), @"behind": [NSValue valueWithCGRect:under] };
    Run(@{});
    Expect(gPlaces[@"full"] == nil && gPlaces[@"behind"] != nil, @"a full-screen window is not moved");
    printf("%s: %d checks, %d failed\n", fails ? "test-dockpositionfront FAILED" : "test-dockpositionfront: all pass", checks, fails);
    return fails ? 1 : 0;
} }
