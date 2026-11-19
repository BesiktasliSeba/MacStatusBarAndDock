// test-barlayoutorder.m -- UIKit's layout order around a held status bar copy's ask (1.8.7.9 W2 and its review), run on the Mac (Mac Catalyst):
// the real UIKit. B = the bar, F = the copy (its subview), R = a region in F, I = an item in R. B's -updateConstraints moves I by 18 pt, as the bar
// places its trailing region in its constraint pass; F's -layoutSubviews reads I's place, as our layout does (our icons follow it). The held ask is
// a data update with no animation: it only asks for B's constraint pass (setNeedsUpdateConstraints: the 17 decompile's branch with no animations).
// What tools/test-wifirecheck.m's stand-in of UIKit assumes, checked here on the real one:
//   T1 -layoutIfNeeded on B with nothing marked runs nothing, its constraint pass due or not;
//   T2 a marked F's -layoutIfNeeded runs B's constraint pass first, and F reads the old place: R places I in its own layout, after F's;
//   T3 the commit (the window's layout) with F marked: the same; T4 with nothing marked but the pass due: the pass runs, R places I.
// Then the real code's bar layout right after the ask (DMBarItemsAskBeforeOurs, cut out by test-barlayoutorder.sh), at both kinds of call site:
//   T5 F not marked (the next-turn and pre-commit sites: [F setNeedsLayout]; [F layoutIfNeeded] after) and
//   T6 F marked first (DMClockBackLayout's "now": [F layoutIfNeeded] after): the call site's layout of F must read the final place;
//   T7 no ask (it found no bar or no data): nothing is laid out.
#import <UIKit/UIKit.h>
#include <stdio.h>

static NSMutableArray<NSString *> *gLog;
static void L(NSString *s) { [gLog addObject:s]; }
@interface BView : UIView
@property BOOL placeOther;
@property (strong) NSLayoutConstraint *k;
@property (strong) UIView *item;
@end
@interface FView : UIView
@property double lastRead;
@end
@implementation BView
- (void)updateConstraints { L(@"B.updateConstraints"); self.k.constant = self.placeOther ? 18 : 0; [super updateConstraints]; }
- (void)layoutSubviews { L(@"B.layoutSubviews"); [super layoutSubviews]; }
@end
@implementation FView
- (void)layoutSubviews {
    [super layoutSubviews];
    BView *b = (BView *)self.superview;
    self.lastRead = [b.item convertRect:b.item.bounds toView:self].origin.x;
    L([NSString stringWithFormat:@"F reads %.0f", self.lastRead]);
}
@end

static BView *B;
static FView *F;
static UIWindow *Win;
static void build(void) {   // a fresh window: B > F > R > I, I at 200 in F; everything laid out, nothing marked
    if (Win) Win.hidden = YES;
    Win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 400, 300)];
    B = [[BView alloc] initWithFrame:CGRectMake(0, 0, 400, 24)]; [Win addSubview:B];
    F = [[FView alloc] initWithFrame:B.bounds]; [B addSubview:F];
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(200, 0, 200, 24)]; [F addSubview:r];
    UIView *item = [UIView new]; item.translatesAutoresizingMaskIntoConstraints = NO; [r addSubview:item]; B.item = item;
    B.k = [item.leadingAnchor constraintEqualToAnchor:r.leadingAnchor constant:0];
    [NSLayoutConstraint activateConstraints:@[B.k, [item.topAnchor constraintEqualToAnchor:r.topAnchor],
                                              [item.widthAnchor constraintEqualToConstant:10], [item.heightAnchor constraintEqualToConstant:10]]];
    Win.hidden = NO;
    [Win layoutIfNeeded]; [B layoutIfNeeded]; [F layoutIfNeeded];
    gLog = [NSMutableArray array];
}
static double place(void) { return [B.item convertRect:B.item.bounds toView:F].origin.x; }   // (where R has I now)
static void ask(void) { B.placeOther = YES; [B setNeedsUpdateConstraints]; }   // (the held ask: a data update with no animation)
static void afterAsk(UIView *fg, BOOL asked) {   // (DMBarItemsAskBeforeOurs: the real code right after its ask, inside the same no-animation block)
    (void)fg; (void)asked;
#include "blo-after.inc"
}
static int gFails;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }
static NSString *logs(void) { return gLog.count ? [gLog componentsJoinedByString:@" | "] : @"nothing"; }
static NSUInteger at(NSString *s) { return [gLog indexOfObject:s]; }

int main(void) {
    @autoreleasepool {
        build(); ask(); [B layoutIfNeeded];
        check(gLog.count == 0 && place() == 200, [NSString stringWithFormat:@"T1 the bar's -layoutIfNeeded with only its constraint pass due runs nothing (%@; I at %.0f)", logs(), place()]);
        build(); [B layoutIfNeeded];
        check(gLog.count == 0, [NSString stringWithFormat:@"T1 ... nor with nothing due (%@)", logs()]);

        build(); ask(); [F setNeedsLayout]; [F layoutIfNeeded];
        check(at(@"B.updateConstraints") == 0 && F.lastRead == 200 && place() == 218,
              [NSString stringWithFormat:@"T2 a marked copy's layout runs the bar's constraint pass first, then reads the old place; the region places it after (%@; then I at %.0f)", logs(), place()]);

        build(); ask(); [F setNeedsLayout]; [Win layoutIfNeeded];
        check(at(@"B.updateConstraints") != NSNotFound && at(@"B.updateConstraints") < at(@"F reads 200") && F.lastRead == 200 && place() == 218,
              [NSString stringWithFormat:@"T3 the commit (the window's layout) with the copy marked: the pass, then the copy reads the old place (%@; then I at %.0f)", logs(), place()]);
        build(); ask(); [Win layoutIfNeeded];
        check(at(@"B.updateConstraints") != NSNotFound && place() == 218 && at(@"F reads 200") == NSNotFound,
              [NSString stringWithFormat:@"T4 the commit with only the pass due: the pass runs, the region places its item, the copy is not laid out (%@; I at %.0f)", logs(), place()]);

        build(); ask(); afterAsk(F, YES); [gLog addObject:@"--"]; [F setNeedsLayout]; [F layoutIfNeeded];
        NSUInteger m = at(@"--");
        check(at(@"B.updateConstraints") < m && m + 1 < gLog.count && [gLog.lastObject isEqualToString:@"F reads 218"],
              [NSString stringWithFormat:@"T5 the copy not marked at the ask (the next-turn and pre-commit sites): the bar's pass runs in the ask, the call site's layout reads the final place (%@)", logs()]);

        build(); [F setNeedsLayout]; ask(); afterAsk(F, YES); [gLog addObject:@"--"]; [F layoutIfNeeded];
        m = at(@"--");
        check(at(@"B.updateConstraints") < m && m + 1 < gLog.count && [gLog.lastObject isEqualToString:@"F reads 218"],
              [NSString stringWithFormat:@"T6 the copy marked first (DMClockBackLayout's \"now\"): laid out again at the call site, reading the final place (%@)", logs()]);

        build(); afterAsk(F, NO); [gLog addObject:@"--"];
        check(gLog.count == 1, [NSString stringWithFormat:@"T7 no ask (no bar or no data): nothing laid out (%@)", logs()]);

        printf("%d check(s) fail\n", gFails);
    }
    return gFails > 90 ? 90 : gFails;
}
