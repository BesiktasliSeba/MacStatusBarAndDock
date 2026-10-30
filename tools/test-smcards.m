// Mac test of the Stage Manager engine's App Switcher cards (statusbar/SMCardPlan.h, used by statusbar/SMCards.h): a stage of several windows is
// shown as one card per window, in the stage's place, the window used last first; one-window cards, other environments and unreadable stages stay
// as SpringBoard has them. Cases from the iPad 2 (16.7.7) and the 17.5 (17.5.1), 30 Oct; 18 checked on the A12Z (18.5) the same day.
#import <Foundation/Foundation.h>
#include "../statusbar/SMCardPlan.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
static NSString *Text(NSArray<NSArray<NSNumber *> *> *plan) {   // ("0.1 0.0 1" = card 0 window 1, card 0 window 0, card 1 whole)
    if (!plan) return @"nil";
    NSMutableArray *p = [NSMutableArray array];
    for (NSArray<NSNumber *> *x in plan) [p addObject:x[1].integerValue < 0 ? x[0].stringValue : [NSString stringWithFormat:@"%@.%@", x[0], x[1]]];
    return [p componentsJoinedByString:@" "];
}
static NSDictionary *Card(NSInteger env, NSArray *t) { return @{@"env": @(env), @"t": t}; }
int main(void) {
    @autoreleasepool {
        CHECK(MSBDSMCardsSplit(nil) == nil && MSBDSMCardsSplit(@[]) == nil, "no cards: SpringBoard's list as it is");
        CHECK(MSBDSMCardsSplit(@[Card(1, @[]), Card(1, @[@1045]), Card(1, @[@1126])]) == nil, "only one-window cards (KT's iPad 2 list): nothing split");
        // the iPad 2, 30 Oct: Clock (t 1127) and Tips (t 1129, in front) on the desktop = one card "Clock and Tips"
        CHECK([Text(MSBDSMCardsSplit(@[Card(1, @[@1127, @1129])])) isEqualToString:@"0.1 0.0"], "Clock and Tips: two cards, Tips (used last) first");
        CHECK([Text(MSBDSMCardsSplit(@[Card(1, @[@1127, @1129]), Card(1, @[@1045]), Card(1, @[@1200, @1100, @1150])])) isEqualToString:@"0.1 0.0 1 2.0 2.2 2.1"],
              "the stages' places kept, each stage's windows newest first, a one-window card as it is");
        CHECK([Text(MSBDSMCardsSplit(@[Card(1, @[@5, @5, @5])])) isEqualToString:@"0.0 0.1 0.2"], "equal times keep SpringBoard's item order");
        CHECK([Text(MSBDSMCardsSplit(@[Card(2, @[@1, @2]), Card(1, @[@3, @4])])) isEqualToString:@"0 1.1 1.0"], "Slide Over's (environment 2) card stays whole");
        CHECK(MSBDSMCardsSplit(@[Card(2, @[@1, @2])]) == nil, "only another environment's card: nothing split");
        CHECK([Text(MSBDSMCardsSplit(@[Card(1, @[@3, [NSNull null]]), Card(1, @[@1, @2])])) isEqualToString:@"0 1.1 1.0"], "a stage whose times can't be read stays one card");
        CHECK([Text(MSBDSMCardsSplit(@[@{@"t": @[@1, @2]}, Card(1, @[@1, @2])])) isEqualToString:@"0 1.1 1.0"], "no environment read: whole");
        CHECK([Text(MSBDSMCardsSplit((NSArray *)@[(id)@"junk", Card(1, @[@1, @2])])) isEqualToString:@"0 1.1 1.0"], "something that is not a card: as it is");
        NSMutableArray *seven = [NSMutableArray array]; for (int i = 0; i < 7; i++) [seven addObject:@(100 + (i * 3) % 7)];
        NSArray *plan7 = MSBDSMCardsSplit(@[Card(1, seven)]);
        BOOL desc = plan7.count == 7; long long last = LLONG_MAX;
        for (NSArray<NSNumber *> *x in plan7) { long long t = [seven[x[1].unsignedIntegerValue] longLongValue]; if (t > last) desc = NO; last = t; }
        CHECK(desc, "a full desktop (7 windows, iPad 2 16.7.7): seven cards, newest first");
        CHECK(MSBDSMCardsOSChecked(16) && MSBDSMCardsOSChecked(17), "16 (iPad 2 16.7.7) and 17 (17.5.1): one card per window");
        CHECK(MSBDSMCardsOSChecked(18), "18 (A12Z 18.5, read and checked 30 Oct): one card per window");
        CHECK(!MSBDSMCardsOSChecked(15) && !MSBDSMCardsOSChecked(19) && !MSBDSMCardsOSChecked(26), "any other: iPadOS's cards as they are (15 has no Stage Manager)");
        printf("smcards: %d checks, %d failed\n", checks, fails);
    }
    return fails ? 1 : 0;
}
