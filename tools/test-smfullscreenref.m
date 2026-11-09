// test-smfullscreenref.m -- Mac test of the green light on the TV with the Stage Manager engine (A12Z TV rows, KT 9 Nov): a window opened on the TV carries the iPad's
// reference rectangle ({1366, 1024}), and full screen is "the whole of the reference": the first press came out 1366 x 1024 on the TV, only a second one full screen.
// The code as built: DMSMSetFullScreenInStage cut out of statusbar/StatusBar.x (test-smfullscreenref.sh), with stand-ins for the stage and its attributes.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long type; } DMSMAttributedSize;
static DMSMAttributedSize gHad, gAsked; static CGSize gScreen; static CGPoint gCentre; static long gPolicy = -1; static BOOL gAskedAny = NO;
static NSString *NSStringFromCGRectStub(CGRect r) { return [NSString stringWithFormat:@"%g x %g", r.size.width, r.size.height]; }
#define DMLog(...) do { (void)(__VA_ARGS__); } while (0)
static id DMSMStageOf(NSString *k) { (void)k; return @"stage"; }
static id DMSMItemFor(id stage, NSString *k, id *attrs) { (void)stage; (void)k; if (attrs) *attrs = @"attrs"; return @"item"; }
static BOOL DMSMAttrAttributedSize(id a, DMSMAttributedSize *s) { (void)a; *s = gHad; return YES; }
static NSString *DMSMItemKey(id it) { (void)it; return @"k"; }
static NSDictionary *DMSMStageItemsMap(id s) { (void)s; return @{}; }
static long long DMSMAttrTimeOr(id a, long long d) { (void)a; return d; }
static id DMSMAttrWith(id a, DMSMAttributedSize s, CGPoint c, long p, long t) { (void)a; (void)t; gAsked = s; gCentre = c; gPolicy = p; gAskedAny = YES; return @"new attrs"; }
static id DMSMStageWithAttrs(id s, id a, id it) { (void)s; (void)a; (void)it; return nil; }
static BOOL DMSMReplaceStage(id s, id n) { (void)s; (void)n; return YES; }
static void DMSMDismissOtherFullScreen(id s, NSString *k) { (void)s; (void)k; }
static BOOL DMSMRequestWindow(NSString *k, id a, long t) { (void)k; (void)a; (void)t; return YES; }
static CGRect DMSMUsableAreaForStage(id s, CGSize *scr) { (void)s; if (scr) *scr = gScreen; return CGRectZero; }
static BOOL DMSMAttrsFullScreen(id a) { (void)a; return YES; }
static NSString *DMSMKeyText(NSString *k) { return k; }
static id DMSMStageDisplayIdentity(id s) { (void)s; return @"display"; }
static NSArray *DMSMRecentStages(void) { return @[]; }
#include "smfullscreenref-gen.h"
int main(void) { @autoreleasepool {
    gHad = (DMSMAttributedSize){ CGSizeMake(0.5, 0.6), CGRectMake(0, 0, 1366, 1024), 0 };
    gScreen = CGSizeMake(2560, 1440);
    DMSMSetFullScreenInStage(@"k", YES);
    Expect(gAskedAny && gAsked.normalizedSize.width == 1 && gAsked.normalizedSize.height == 1 && gAsked.type == 3 && gPolicy == 2, @"full screen: the whole of the reference, maximized, as before");
    Expect(CGSizeEqualToSize(gAsked.referenceBounds.size, CGSizeMake(2560, 1440)), [NSString stringWithFormat:@"a window opened on the TV carrying the iPad's reference: full screen is the TV's whole (%@; before: 1366 x 1024 at the first press)", NSStringFromCGRectStub(gAsked.referenceBounds)]);
    gScreen = CGSizeMake(1366, 1024); DMSMSetFullScreenInStage(@"k", YES);
    Expect(CGSizeEqualToSize(gAsked.referenceBounds.size, CGSizeMake(1366, 1024)), @"  ... on the iPad: its own, as it was");
    gScreen = CGSizeZero; DMSMSetFullScreenInStage(@"k", YES);
    Expect(CGSizeEqualToSize(gAsked.referenceBounds.size, CGSizeMake(1366, 1024)), @"  ... the stage's screen not known: the reference the window had");
    printf("%s: %d checks, %d failed\n", fails ? "test-smfullscreenref FAILED" : "test-smfullscreenref: all pass", checks, fails);
    return fails ? 1 : 0;
} }
