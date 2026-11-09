// test-turnplaceoneorder.m -- Mac test of the re-placement after a turn on the Stage Manager engine (1.8.4.1 item 14): windows that had to be moved were asked for one by one, and a
// request for one window names it as the stage's frontmost, so a window behind came in front of the one in use. The code as built: the placing part of DMSMWatchTurn cut out of
// statusbar/StatusBar.x (test-turnplaceoneorder.sh), with stand-ins for the stage.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "TurnPlace.h"
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
@interface NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r; - (CGRect)CGRectValue;
@end
@implementation NSValue (CGRectStandIn)
+ (NSValue *)valueWithCGRect:(CGRect)r { return [NSValue valueWithBytes:&r objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect r; [self getValue:&r]; return r; }
@end
static NSString *NSStringFromCGRect(CGRect r) { return [NSString stringWithFormat:@"%g %g %g %g", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
#define DM_FEATURE_MARK(x) do { } while (0)
static const CGFloat kSMBarH = 24.0;
static NSString *gFront; static CGRect gArea; static int gOneByOne, gWhole; static NSDictionary *gPlaces; static NSSet *gUsers;
static CGRect DMSMUsableAreaForIdentity(id i, CGSize *s) { (void)i; (void)s; return gArea; }
static BOOL DMSMApplyLayouts(NSDictionary *l) { gWhole++; gPlaces = l; return YES; }
static BOOL DMSMSetWindowGeometry(NSString *key, CGPoint c, CGSize s) { (void)c; (void)s; gOneByOne++; gFront = key; return YES; }
static BOOL DMSMApplyPlacesMarkedIn(NSDictionary *p, id stage, NSSet *u) { (void)stage; gWhole++; gPlaces = p; gUsers = u; return YES; }
static id DMSMWorkingStage(void) { return @"stage"; }
static NSString *DMSMKeyText(NSString *k) { return k; }
static id DMSMKeyLookup(NSDictionary *d, NSString *k) { return d[k]; }
static BOOL DMSMKeySetHas(NSSet *s, NSString *k) { return [s containsObject:k]; }
static NSMutableDictionary *gSMTurnPlaced; static NSDictionary *gSMFitSlots; static NSSet *gSMFreeWindows;
static BOOL gFit; static BOOL DMFitEnabled(void) { return gFit; }
static void Run(NSDictionary<NSString *, NSValue *> *frames, NSDictionary<NSString *, NSString *> *layouts, NSDictionary<NSString *, NSDictionary *> *places, CGSize scr, NSArray **outBack) {
    gFront = @"inuse"; gOneByOne = gWhole = 0; gPlaces = nil; gUsers = nil;
    NSString *shape = @"L";
    do {
#include "turnplace-gen.h"
        if (outBack) *outBack = back;
    } while (0);
}
static NSValue *R(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { return [NSValue valueWithCGRect:CGRectMake(x, y, w, h)]; }
int main(void) { @autoreleasepool {
    CGSize scr = CGSizeMake(1366, 1024); gArea = CGRectMake(0, 24, 1366, 900);
    NSDictionary *frames = @{ @"inuse": R(300, 100, 700, 700), @"behind": R(1100, 100, 700, 700), @"tile": R(0, 24, 683, 900) };
    NSArray *back = nil;
    Run(frames, @{ @"tile": @"left" }, @{}, scr, &back);
    Expect([gFront isEqualToString:@"inuse"], [NSString stringWithFormat:@"a window pushed off the desktop by the turn is moved back: the window in use stays in front (front: %@)", gFront]);
    Expect(gWhole == 1 && gOneByOne == 0, [NSString stringWithFormat:@"  ... one request for the whole stage (whole %d, alone %d)", gWhole, gOneByOne]);
    Expect([gPlaces[@"tile"] isEqual:@"left"], @"  ... a window in a layout is named with its layout in that same request");
    CGRect p = [gPlaces[@"behind"] CGRectValue];
    Expect(CGRectContainsRect(gArea, p) && p.size.width == 700, @"  ... the window off the desktop comes back inside it at its size, the whole window");
    Expect(gPlaces[@"inuse"] == nil, @"  ... a window inside the desktop is not named");
    Expect([gUsers containsObject:@"behind"] && ![gUsers containsObject:@"tile"], @"  ... marked as the user's place only for the window moved, not the layout's");
    Run(@{ @"inuse": R(300, 100, 700, 700) }, @{}, @{}, scr, NULL);
    Expect(gWhole == 0 && gOneByOne == 0, @"nothing to move: no request at all");
    Run(@{ @"full": R(0, -24, 1366, 1048), @"tile": R(0, 24, 683, 900) }, @{ @"tile": @"left" }, @{}, scr, NULL);
    Expect(gPlaces[@"full"] == nil && gWhole == 1, @"a full-screen window is not moved");
    printf("%s: %d checks, %d failed\n", fails ? "test-turnplaceoneorder FAILED" : "test-turnplaceoneorder: all pass", checks, fails);
    return fails ? 1 : 0;
} }
