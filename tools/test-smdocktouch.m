// test-smdocktouch.m -- Mac test of a touch on the Dock with the Stage Manager engine (1.8.9, GitHub #20, the second report): the code as built.
// test-smdocktouch.sh cuts DMSMScreenPointOnDock, DMSMTouchOnDock, DMSMGestureOnDock and Stage Manager's window gesture gates (the tap and the
// pointer's click that bring a window forward, the live resize, the window drag) out of statusbar/StatusBar.x into smdocktouch-gen.h; this file gives
// them stand-ins for UIKit and SpringBoard. A tap on a Dock icon over a window behind another also brought that window forward (Stage Manager's
// tap-to-front sees every touch and asks only which window card lies under the point): a touch the Dock takes is no window's.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- UIKit's parts these functions read (a view is its origin on its screen and its size) -------------------------------------------------------------
@interface UIScreen : NSObject + (UIScreen *)mainScreen; - (id)coordinateSpace; @end
@implementation UIScreen + (UIScreen *)mainScreen { static UIScreen *s; if (!s) s = [UIScreen new]; return s; } - (id)coordinateSpace { return self; } @end
@class UIWindow, UIEvent;
@interface UIView : NSObject
@property (nonatomic, weak) UIView *superview;
@property (nonatomic, strong) UIWindow *ownWindow;
@property (nonatomic) CGPoint origin;   // (on the screen)
@property (nonatomic) CGRect bounds;
@property (nonatomic) BOOL hidden;
@property (nonatomic) CGFloat alpha;
@property (nonatomic, strong) NSArray<UIView *> *subviews;
- (UIWindow *)window;
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id)s;
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id)s;
@end
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _alpha = 1.0; _subviews = @[]; } return self; }
- (UIWindow *)window { return self.ownWindow ?: self.superview.window; }
- (CGPoint)convertPoint:(CGPoint)p fromCoordinateSpace:(id)s { return CGPointMake(p.x - self.origin.x, p.y - self.origin.y); }
- (CGPoint)convertPoint:(CGPoint)p toCoordinateSpace:(id)s { return CGPointMake(p.x + self.origin.x, p.y + self.origin.y); }
@end
// A window: a full-screen root that passes every point through but its `takes` rectangle (window points), where `content` is hit
@interface UIWindow : UIView
@property (nonatomic, strong) UIScreen *screen;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic) CGRect takes;
@property (nonatomic, strong) UIView *content;
@property (nonatomic) BOOL selfOutside;   // (a root that answers itself off its rectangle, not nil)
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e;
@end
@implementation UIWindow
- (instancetype)init { if ((self = [super init])) { _userInteractionEnabled = YES; _content = [UIView new]; _content.superview = self; } return self; }
- (UIWindow *)window { return self; }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return CGRectContainsPoint(self.takes, p) ? self.content : (self.selfOutside ? self : nil); }
@end
@interface SBFloatingDockWindow : UIWindow @end @implementation SBFloatingDockWindow @end
@interface SBFloatingDockPlatterView : UIView @end @implementation SBFloatingDockPlatterView @end
@interface SBMainSwitcherWindow : UIWindow @end @implementation SBMainSwitcherWindow @end
@interface _UISystemGestureWindow : UIWindow @end @implementation _UISystemGestureWindow @end
@interface UITouch : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic) CGPoint at;
- (CGPoint)locationInView:(id)v;
@end
@implementation UITouch - (CGPoint)locationInView:(id)v { return self.at; } @end
@interface UIGestureRecognizer : NSObject @property (nonatomic, strong) UIView *view; @property (nonatomic) CGPoint at; - (CGPoint)locationInView:(id)v; @end
@implementation UIGestureRecognizer - (CGPoint)locationInView:(id)v { return self.at; } @end
@interface UIPanGestureRecognizer : UIGestureRecognizer @property (nonatomic) CGPoint moved; - (CGPoint)translationInView:(id)v; @end
@implementation UIPanGestureRecognizer - (CGPoint)translationInView:(id)v { return self.moved; } @end

// ---- the rest of the tweak at that moment ----------------------------------------------------------------------------------------------------------------
static NSArray<UIWindow *> *gWindows;
static NSArray<UIWindow *> *DMAllWindows(void) { return gWindows ?: @[]; }
static BOOL gFree = YES, gAsBuilt = NO, gOnBar = NO, gOnLights = NO, gFullOwn = NO, gMenuOpen = NO, gOverWindows = NO, gGuided = NO, gAppleAnswer = YES;
static int gAppleAsked = 0;
static BOOL DMTestFlag(const char *f) { return gAsBuilt && !strcmp(f, "/tmp/msb-sm-docktouch-asbuilt"); }
static BOOL DMSMFree(void) { return gFree; }
static BOOL DMSMOverWindows(void) { return gOverWindows; }
static BOOL MSBDGuidedAccessActive(void) { return gGuided; }
static BOOL DMSMGestureOnOurLights(UIGestureRecognizer *g) { return gOnLights; }
static BOOL DMSMTouchOnOurLights(UITouch *t) { return gOnLights; }
static BOOL DMSMGestureOnMenuBar(UIGestureRecognizer *g) { return gOnBar; }
static BOOL DMSMTouchOnMenuBar(UITouch *t) { return gOnBar; }
static BOOL DMSMGestureFullScreenOwn(UIGestureRecognizer *g) { return gFullOwn; }
static BOOL DMSMTouchFullScreenOwn(UITouch *t) { return gFullOwn; }
static UIScreen *DMSMGestureScreen(id g) { return [UIScreen mainScreen]; }
static UIScreen *DMSMTouchScreen(id t) { return [UIScreen mainScreen]; }
static BOOL DMSMOurMenuOpenOn(UIScreen *screen) { return gMenuOpen; }
static NSString *gSMFullActive;
static NSString *DMSMFullScreenUnderWindows(void) { return nil; }
static void DMSMFullScreenActivate(NSString *k) { }
static UIGestureRecognizer *gDragRecognizer;
static BOOL DMSMIsWindowDrag(id manager, UIGestureRecognizer *g) { return g == gDragRecognizer; }
static NSCountedSet *gMarks;
#define DM_FEATURE_MARK(x) [gMarks addObject:@x]
static void DMLog(NSString *s) { }
static BOOL (*o_SMTapForwardBegin)(id, SEL, id), (*o_SMLiveResizeBegin)(id, SEL, id), (*o_SMClickForwardBegin)(id, SEL, id);
static BOOL (*o_SMTapForwardTouch)(id, SEL, id, id);
static BOOL AppleBegin(id self, SEL _cmd, id g) { gAppleAsked++; return gAppleAnswer; }
static BOOL AppleTouch(id self, SEL _cmd, id g, id t) { gAppleAsked++; return gAppleAnswer; }
#include "smdocktouch-gen.h"

int main(void) {
    @autoreleasepool {
        o_SMTapForwardBegin = AppleBegin; o_SMLiveResizeBegin = AppleBegin; o_SMClickForwardBegin = AppleBegin; o_SMTapForwardTouch = AppleTouch;
        gMarks = [NSCountedSet set];
        UIScreen *ipad = [UIScreen mainScreen], *tv = [UIScreen new];
        // the iPad's Dock (landscape 1180 x 820): its window covers the screen, its platter takes 30..1150 x 745..815; the switcher's window with a
        // Settings window card at the bottom left (under the Dock's left icons); the system gesture window where Stage Manager's gestures live
        SBFloatingDockWindow *dock = [SBFloatingDockWindow new]; dock.screen = ipad; dock.takes = CGRectMake(30, 745, 1120, 70);
        UIView *dockView = [UIView new]; SBFloatingDockPlatterView *platter = [SBFloatingDockPlatterView new];   // (the platter as drawn: 30..1150 x 745..815)
        platter.origin = CGPointMake(30, 745); platter.bounds = CGRectMake(0, 0, 1120, 70); dockView.subviews = @[platter]; dock.subviews = @[dockView];
        SBMainSwitcherWindow *sw = [SBMainSwitcherWindow new]; sw.screen = ipad; sw.takes = CGRectMake(0, 0, 1180, 820);
        _UISystemGestureWindow *sys = [_UISystemGestureWindow new]; sys.screen = ipad;
        SBFloatingDockWindow *tvDock = [SBFloatingDockWindow new]; tvDock.screen = tv; tvDock.takes = CGRectMake(400, 980, 1120, 90);
        gWindows = @[sw, dock, sys, tvDock];
        CGPoint icon = CGPointMake(65, 780), above = CGPointMake(65, 700), mid = CGPointMake(600, 300);

        // ==== the question: a point the Dock takes ====
        Expect(DMSMScreenPointOnDock(icon, ipad), @"a point on a Dock icon (over a window behind it) is the Dock's");
        Expect(!DMSMScreenPointOnDock(above, ipad) && !DMSMScreenPointOnDock(mid, ipad), @"a point above the Dock, or in the middle of the screen: not the Dock's (its root passes it through)");
        Expect(!DMSMScreenPointOnDock(CGPointMake(10, 780), ipad), @"beside the platter at the screen's edge: not the Dock's");
        Expect(!DMSMScreenPointOnDock(CGPointMake(500, 1020), ipad) && DMSMScreenPointOnDock(CGPointMake(500, 1020), tv), @"each screen's own Dock: the TV's on the TV only");
        dock.hidden = YES;
        Expect(!DMSMScreenPointOnDock(icon, ipad), @"the Dock window hidden: not the Dock's");
        dock.hidden = NO; dock.alpha = 0.0;
        Expect(!DMSMScreenPointOnDock(icon, ipad), @"the Dock faded out (alpha 0): not the Dock's");
        dock.alpha = 1.0; dock.userInteractionEnabled = NO;
        Expect(!DMSMScreenPointOnDock(icon, ipad), @"the Dock window taking no touches: not the Dock's");
        dock.userInteractionEnabled = YES; dock.takes = CGRectMake(30, 900, 1120, 70);
        Expect(!DMSMScreenPointOnDock(icon, ipad), @"the Dock hidden by Automatically Hide (moved off the screen): not the Dock's");
        dock.takes = CGRectMake(30, 745, 1120, 70);
        Expect(!DMSMScreenPointOnDock(CGPointMake(NAN, 780), ipad) && !DMSMScreenPointOnDock(icon, nil), @"a point not a number, or no screen: not the Dock's");
        dock.selfOutside = YES;
        Expect(!DMSMScreenPointOnDock(above, ipad) && DMSMScreenPointOnDock(icon, ipad), @"a Dock window whose root answers itself off the platter: still only the platter is the Dock's");
        dock.selfOutside = NO;
        gAsBuilt = YES;
        Expect(!DMSMScreenPointOnDock(icon, ipad), @"debug /tmp/msb-sm-docktouch-asbuilt: as built before (not the Dock's)");
        gAsBuilt = NO;
        UITouch *t = [UITouch new]; t.window = sys; t.at = icon;
        UITouch *tw = [UITouch new]; tw.window = sys; tw.at = mid;
        Expect(DMSMTouchOnDock(t) && !DMSMTouchOnDock(tw) && !DMSMTouchOnDock(nil), @"a touch as Stage Manager's gestures get it (in the system gesture window): on the Dock or not");
        UIGestureRecognizer *g = [UIGestureRecognizer new]; g.view = sys; g.at = icon;
        UIGestureRecognizer *gw = [UIGestureRecognizer new]; gw.view = sys; gw.at = mid;
        Expect(DMSMGestureOnDock(g) && !DMSMGestureOnDock(gw), @"a gesture's point: on the Dock or not");

        // ==== Stage Manager's window gestures leave a touch on the Dock ====
        gAppleAsked = 0;
        Expect(!DMSMTapForwardTouch(nil, NULL, g, t) && gAppleAsked == 0 && [gMarks containsObject:@"sm-dock-touch-not-forward"],
               @"tap-to-front: a touch on a Dock icon over a window behind does not go to it (the window stays where it is)");
        gAppleAsked = 0;
        Expect(DMSMTapForwardTouch(nil, NULL, gw, tw) && gAppleAsked == 1, @"tap-to-front: a touch in a window behind: Apple's answer, as before");
        gAppleAnswer = NO; gAppleAsked = 0;
        Expect(!DMSMTapForwardTouch(nil, NULL, gw, tw) && gAppleAsked == 1, @"  ... whatever Apple answers");
        gAppleAnswer = YES;
        Expect(!DMSMTapForwardBegin(nil, NULL, g) && [gMarks containsObject:@"sm-dock-tap-not-forward"] && DMSMTapForwardBegin(nil, NULL, gw), @"tap-to-front's begin: not on the Dock; elsewhere Apple's");
        Expect(!DMSMClickForwardBegin(nil, NULL, g) && [gMarks containsObject:@"sm-dock-click-not-forward"] && DMSMClickForwardBegin(nil, NULL, gw), @"the pointer's click-down to front: not on the Dock; elsewhere Apple's");
        Expect(!DMSMLiveResizeBegin(nil, NULL, g) && [gMarks containsObject:@"sm-dock-no-live-resize"] && DMSMLiveResizeBegin(nil, NULL, gw), @"the live resize: not from the Dock (over a window's corner); elsewhere Apple's");
        {   // (the live resize is asked when its recogniser has moved past its hysteresis: where the finger went down decides, as for the window drag)
            UIPanGestureRecognizer *down = [UIPanGestureRecognizer new]; down.view = sys; down.at = CGPointMake(398, 760); down.moved = CGPointMake(0, 22);   // (began at 398, 738: a corner above the Dock)
            UIPanGestureRecognizer *up = [UIPanGestureRecognizer new]; up.view = sys; up.at = CGPointMake(65, 725); up.moved = CGPointMake(0, -55);       // (began at 65, 780: on a Dock icon)
            gAppleAsked = 0;
            Expect(DMSMLiveResizeBegin(nil, NULL, down) && gAppleAsked == 1, @"the live resize: a corner drag of a window above the Dock whose first move goes onto the Dock is the window's (Apple's answer)");
            Expect(!DMSMLiveResizeBegin(nil, NULL, up), @"the live resize: a drag begun on a Dock icon over a window's corner that moved up off the Dock is the Dock's");
            dock.takes = CGRectMake(30, 728, 1120, 87);   // (the Dock window takes touches 17 pt above its platter, as on 17.5.1)
            UIPanGestureRecognizer *band = [UIPanGestureRecognizer new]; band.view = sys; band.at = CGPointMake(398, 760); band.moved = CGPointMake(0, 24);   // (began at 398, 736)
            UIGestureRecognizer *bandTap = [UIGestureRecognizer new]; bandTap.view = sys; bandTap.at = CGPointMake(398, 736);
            Expect(DMSMLiveResizeBegin(nil, NULL, band) && !DMSMTapForwardBegin(nil, NULL, bandTap),
                   @"the band the Dock window takes above its platter: a window's corner drag begun there is the window's (the Dock as drawn), a tap there is the Dock's (UIKit gives it the Dock)");
            platter.hidden = YES;
            Expect(DMSMLiveResizeBegin(nil, NULL, up), @"the live resize: the platter hidden, a drag begun there is the window's");
            platter.hidden = NO; dock.takes = CGRectMake(30, 745, 1120, 70);
        }
        gDragRecognizer = g;
        Expect(DMSMWindowDragLeavesTouch(nil, g, t) && [gMarks containsObject:@"sm-dock-drag-not-window"] && !DMSMWindowDragLeavesTouch(nil, g, tw),
               @"the window drag: a touch on the Dock (over a window's top part) is left out; a touch on a window is the drag's, as before");
        gOnBar = YES;
        Expect(DMSMWindowDragLeavesTouch(nil, g, tw) && !DMSMTapForwardTouch(nil, NULL, gw, tw), @"the menu bar's touch: left out as before");
        gOnBar = NO;
        gFree = NO; gAppleAsked = 0;
        Expect(DMSMTapForwardTouch(nil, NULL, g, t) && DMSMTapForwardBegin(nil, NULL, g) && DMSMClickForwardBegin(nil, NULL, g) && DMSMLiveResizeBegin(nil, NULL, g) && !DMSMWindowDragLeavesTouch(nil, g, t),
               @"another engine (Stage Manager's own windowing): every gesture as Apple has it");
        gFree = YES;
        dock.hidden = YES;
        Expect(DMSMTapForwardTouch(nil, NULL, g, t) && !DMSMWindowDragLeavesTouch(nil, g, t), @"no Dock shown there: a touch at that point is the window's, as before");
        dock.hidden = NO;
    }
    printf("test-smdocktouch: %d of %d checks pass\n", checks - fails, checks);
    return fails;
}
