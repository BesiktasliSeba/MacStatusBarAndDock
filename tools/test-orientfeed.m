// test-orientfeed.m: StatusBar.x's DMOrientationFeedApply / DMOrientationFeedWant (taken out by test-orientfeed.sh into feed.inc) against a
// stand-in UIDevice that counts begins and ends the way UIKit does (a negative count would be UIKit's unbalanced end).
#import <Foundation/Foundation.h>
#include <stdio.h>

static int gBegins = 0, gEnds = 0, gCount = 0, gUnder = 0;
@interface UIDevice : NSObject
+ (instancetype)currentDevice;
- (void)beginGeneratingDeviceOrientationNotifications;
- (void)endGeneratingDeviceOrientationNotifications;
@end
@implementation UIDevice
+ (instancetype)currentDevice { static UIDevice *d; if (!d) d = [UIDevice new]; return d; }
- (void)beginGeneratingDeviceOrientationNotifications { gBegins++; gCount++; }
- (void)endGeneratingDeviceOrientationNotifications { gEnds++; if (gCount == 0) gUnder++; else gCount--; }
@end

static BOOL gDMScreenOff = NO;
#include "feed.inc"   // (DMOrientationFeedApply and DMOrientationFeedWant, as in StatusBar.x)

static int fails = 0;
static void check(const char *what, BOOL ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static void screen(BOOL off) { gDMScreenOff = off; DMOrientationFeedApply(); }   // (as DMScreenPowerChanged / DMScreenPowerWatch do)

int main(void) {
    @autoreleasepool {
        screen(NO); DMOrientationFeedWant(YES);
        check("asked with the screen on: the feed starts (one begin)", gCount == 1 && gBegins == 1);
        screen(YES);
        check("screen off: the feed ends (UIKit's count back to 0)", gCount == 0 && gEnds == 1);
        screen(YES);
        check("  ... a second off signal ends nothing more", gEnds == 1 && gUnder == 0);
        screen(NO);
        check("screen on again: the feed starts again", gCount == 1 && gBegins == 2);
        DMOrientationFeedWant(YES);
        check("  ... asked again while on: no second begin (UIKit's count stays 1)", gCount == 1 && gBegins == 2);
        DMOrientationFeedWant(NO);
        check("the debug orientoff: the feed ends", gCount == 0);
        screen(YES); screen(NO);
        check("  ... and a screen cycle while not wanted starts nothing", gCount == 0 && gBegins == 2);
        DMOrientationFeedWant(YES); DMOrientationFeedWant(NO); DMOrientationFeedWant(YES);
        check("on, off, on: balanced (count 1)", gCount == 1);
        // a SpringBoard that starts with the screen off: asked first, the screen read after (the full start's order)
        gBegins = gEnds = gCount = gUnder = 0; gDMOrientFeedWanted = NO; gDMOrientFeedOn = NO; gDMScreenOff = NO;
        DMOrientationFeedWant(YES); screen(YES);
        check("started with the screen off: the feed asked for is ended at the first state read", gCount == 0);
        screen(NO);
        check("  ... and on at the first wake", gCount == 1);
        check("never an end without its begin (UIKit's count never below 0)", gUnder == 0);
    }
    if (fails) { printf("test-orientfeed (compiled): FAILED\n"); return 1; }
    printf("test-orientfeed (compiled): all checks pass\n");
    return 0;
}
