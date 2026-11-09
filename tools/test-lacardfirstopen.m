// test-lacardfirstopen.m -- Mac test of a Live Activity card's first open (the M1, 15.6.1, Zetsu and MilkyWay4, 9 Nov): the menu window turns itself only once it is shown, and DMLAOpenCard measured
// the pill's place before showing it. So the first card of a SpringBoard came out at y 824 in landscape, off the bottom of the screen; every later one was right. The code as built: DMLAOpenCard and
// DMLACardFrame cut out of statusbar/LiveActivities.h (test-lacardfirstopen.sh), with stand-ins for the menu window (portrait while hidden, the screen's shape once shown) and the bar.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
static int fails = 0, checks = 0;
static void Expect(BOOL ok, NSString *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }
typedef NSUInteger UIControlEvents; static const UIControlEvents UIControlEventTouchUpInside = 1 << 6;
@interface UIAction : NSObject + (instancetype)actionWithHandler:(void (^)(__kindof UIAction *))h; @end
@implementation UIAction + (instancetype)actionWithHandler:(void (^)(__kindof UIAction *))h { return [self new]; } @end
@interface UIView : NSObject
@property (nonatomic) CGRect frame; @property (nonatomic) CGRect bounds; @property (nonatomic) CGFloat alpha; @property (nonatomic) CGAffineTransform transform; @property (nonatomic, weak) UIView *superview; @property (nonatomic) BOOL hidden;
- (void)addSubview:(UIView *)v; + (void)animateWithDuration:(double)d animations:(void (^)(void))a;
+ (void)animateWithDuration:(double)d delay:(double)dl usingSpringWithDamping:(double)s initialSpringVelocity:(double)v options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c;
@end
@implementation UIView
- (void)addSubview:(UIView *)v { v.superview = self; }
+ (void)animateWithDuration:(double)d animations:(void (^)(void))a { }
+ (void)animateWithDuration:(double)d delay:(double)dl usingSpringWithDamping:(double)s initialSpringVelocity:(double)v options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c { }
@end
@interface UIControl : UIView - (void)addAction:(UIAction *)a forControlEvents:(UIControlEvents)e; @end
@implementation UIControl - (void)addAction:(UIAction *)a forControlEvents:(UIControlEvents)e { } @end
@interface DMLAPill : UIControl @property (nonatomic) BOOL lit; @property (nonatomic, copy) NSString *uid; @end
@implementation DMLAPill @end
// The menu window: its portrait shape until an overlay has shown it, then the screen's (the iPad in landscape)
static BOOL gShown; static int gOverlays, gRemoved, gStepsOverlay, gStepsAnchor, gStepsMake, gStep; static CGFloat gMaxH; static BOOL gCardNil;
@interface FakeHost : UIView @end
@implementation FakeHost - (CGRect)bounds { return gShown ? CGRectMake(0, 0, 1194, 834) : CGRectMake(0, 0, 834, 1194); } @end
static UIView *gHost; static NSArray<NSString *> *gUids; static NSDictionary *gLAItems;
static UIView *gLACard; static DMLAPill *gLACardPill; static NSString *gLACardSignature; static NSTimer *gLACardTimer; static BOOL gLACardRebuildPending;
#define DMLog(...) do { (void)(__VA_ARGS__); } while (0)
#define DM_FEATURE_MARK(x) do { } while (0)
static BOOL DMTitleTapWithMenuOpen(id p) { return NO; }
static id DMSBManager(const char *n) { return nil; }
static BOOL DMLockUp(id m) { return NO; }
static BOOL DMCoverSheetShown(void) { return NO; }
static BOOL DMGARefuses(NSString *w) { return NO; }
static UIView *DMHostFor(UIView *fg) { return gHost; }
static NSArray<NSString *> *DMLACardUids(DMLAPill *p) { return gUids; }
static CGRect DMConvertToHost(UIView *fg, CGRect r, UIView *host) { gStepsAnchor = ++gStep; return gShown ? CGRectMake(755, 5, 65, 20) : CGRectMake(809, 755, 20, 65); }   // (on the bar: the screen's shape; measured against the portrait window: turned)
static UIView *DMLAMakeCard(NSArray<NSString *> *uids, CGFloat maxH, NSString **sig, NSSet **hosting) { gStepsMake = ++gStep; gMaxH = maxH; BOOL any = NO; for (NSString *u in uids) if (gLAItems[u]) any = YES; if (gCardNil || !any) return nil; UIView *c = [UIView new]; c.frame = CGRectMake(0, 0, 321.5, 73); if (sig) *sig = @"s"; return c; }
static UIControl *DMMakeOverlayFor(UIView *host, CGFloat d, BOOL m) { gStepsOverlay = ++gStep; gOverlays++; gShown = YES; return [UIControl new]; }
static void DMCloseOverlay(void) { }
static void DMRemoveOverlayNow(void) { gRemoved++; }
static void DMAttachMenuHover(UIControl *o, UIView *fg, UIView *h, id b) { }
static void DMLAAppsHostsAppear(void) { }
static void DMLARebuildOpenCard(void) { }
static BOOL DMLACardDragging(UIView *c) { return NO; }
static void DMLACardRefresh(void) { }
static void DMGateTimer(NSTimer *t) { }
static BOOL MSBReduceMotion(void) { return YES; }
static BOOL DMIsMenuWindowHost(UIView *h) { return YES; }
static CGFloat DMMenuHostWidth(UIView *h) { return 1194; }
#include "lacardfirstopen-gen.h"
static void Reset(void) { gShown = NO; gOverlays = gRemoved = gStep = gStepsOverlay = gStepsAnchor = gStepsMake = 0; gMaxH = 0; gLACard = nil; gCardNil = NO; [gLACardTimer invalidate]; gLACardTimer = nil; }
int main(void) { @autoreleasepool {
    gHost = [FakeHost new];
    DMLAPill *pill = [DMLAPill new]; pill.uid = @"a"; pill.frame = CGRectMake(755, 5, 65, 20); UIView *bar = [UIView new]; pill.superview = bar;
    gLAItems = @{ @"a": @YES }; gUids = @[@"a"];
    Reset(); DMLAOpenCard(pill);
    Expect(gOverlays == 1 && gStepsOverlay < gStepsAnchor, [NSString stringWithFormat:@"the card is the first overlay of a SpringBoard: the overlay is made before the pill's place is read (overlay step %d, place step %d)", gStepsOverlay, gStepsAnchor]);
    Expect(gStepsOverlay < gStepsMake, @"  ... and before the card is built (an open card's teardown, its live views too, comes first)");
    Expect(fabs(gLACard.frame.origin.y - 29) < 0.5, [NSString stringWithFormat:@"  ... the card hangs under the pill, on the screen: y %.1f (the portrait shape gave 824 on the M1)", gLACard.frame.origin.y]);
    Expect(fabs(gMaxH - (834 - 25 - 12)) < 0.5, [NSString stringWithFormat:@"  ... the room it may use is the screen's: %.0f pt", gMaxH]);
    Expect(pill.lit && gLACardPill == pill && gLACardTimer != nil, @"  ... the pill is lit and its refresh runs, as before");
    Reset(); gShown = YES; pill.lit = NO; DMLAOpenCard(pill);
    Expect(gLACard && fabs(gLACard.frame.origin.y - 29) < 0.5 && fabs(gMaxH - 797) < 0.5, @"a later open, the window already turned: the same place and the same room");
    Reset(); pill.lit = NO; gUids = @[]; DMLAOpenCard(pill);
    Expect(gOverlays == 0 && !gLACard, @"nothing to show (no uids): returned before any overlay is made");
    Reset(); gUids = @[@"gone"]; DMLAOpenCard(pill);
    Expect(gOverlays == 0 && !gLACard, @"  ... its items gone: the same");
    Reset(); gUids = @[@"a"]; gCardNil = YES; DMLAOpenCard(pill);
    Expect(gOverlays == 1 && gRemoved == 1 && !gLACard && !pill.lit, [NSString stringWithFormat:@"no card could be built after the overlay: the overlay is taken down the normal way (removed %d), nothing left lit", gRemoved]);
    [gLACardTimer invalidate];
    printf("%s: %d checks, %d failed\n", fails ? "test-lacardfirstopen FAILED" : "test-lacardfirstopen: all pass", checks, fails);
    return fails ? 1 : 0;
} }
