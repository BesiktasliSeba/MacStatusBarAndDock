// SMCardPlan.h -- which App Switcher cards iPadOS's App Switcher shows with the Stage Manager engine (statusbar/SMCards.h), plain Foundation so the
// Mac test (tools/test-smcards.m) runs this very code.
//  - SpringBoard's App Switcher list is its recent stages (SBAppLayout), most recent first; a stage of several windows is one card ("Clock and
//    Tips"). With our engine a stage is a desktop, so one card held every app of a desktop -- unlike Aerial, Zetsu and MilkyWay4, where every app
//    with a window has a card of its own (KT, 30 Oct: "We don't group apps like that").
//  - Shown instead: each window of a stage as a card of its own (its leaf app layout: the window alone, as SpringBoard shows a window of a stage on
//    its own in App Expose), in the stage's place in the list, the window used last first. A card of one window, and a card of another environment
//    than the main one (Slide Over's), stays as it is.
#ifndef MSBD_SM_CARD_PLAN_H
#define MSBD_SM_CARD_PLAN_H
#import <Foundation/Foundation.h>

// The versions where SpringBoard's switcher calls behind it were read and the cards checked: 16 (iPad 2 16.7.7), 17 (17.5.1) and 18 (A12Z 18.5:
// its gesture modifiers hold the stage under the finger in "Gesture" classes too, SMCards.h). Any other: the cards as iPadOS has them (debug
// builds try them with /tmp/msb-smcards-anyos).
static inline BOOL MSBDSMCardsOSChecked(NSInteger major) { return major >= 16 && major <= 18; }

// cards: SpringBoard's cards in its order (0 = most recent), each @{@"env": its environment (1 = the main one), @"t": @[each window's last
// interaction time, in the card's own item order]} -- a time SpringBoard could not tell is NSNull (such a card stays whole). Returns what is shown,
// in order, each @[@(card), @(window)] (window -1: the card as it is), or nil when nothing is split (SpringBoard's list as it is).
static inline NSArray<NSArray<NSNumber *> *> *MSBDSMCardsSplit(NSArray<NSDictionary *> *cards) {
    if (![cards isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray<NSArray<NSNumber *> *> *out = [NSMutableArray arrayWithCapacity:cards.count + 4];
    BOOL split = NO;
    for (NSUInteger c = 0; c < cards.count; c++) {
        NSDictionary *card = cards[c];
        NSArray *t = [card isKindOfClass:[NSDictionary class]] ? card[@"t"] : nil;
        id env = [card isKindOfClass:[NSDictionary class]] ? card[@"env"] : nil;
        BOOL whole = ![env isKindOfClass:[NSNumber class]] || [env integerValue] != 1 || ![t isKindOfClass:[NSArray class]] || t.count < 2;
        for (id x in (whole ? @[] : t)) if (![x isKindOfClass:[NSNumber class]]) { whole = YES; break; }
        if (whole) { [out addObject:@[@(c), @(-1)]]; continue; }
        NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:t.count];
        for (NSUInteger i = 0; i < t.count; i++) [order addObject:@(i)];
        [order sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {   // (newest first; equals keep their order)
            long long ta = [t[a.unsignedIntegerValue] longLongValue], tb = [t[b.unsignedIntegerValue] longLongValue];
            return ta > tb ? NSOrderedAscending : (ta < tb ? NSOrderedDescending : NSOrderedSame);
        }];
        for (NSNumber *i in order) [out addObject:@[@(c), i]];
        split = YES;
    }
    return split ? out : nil;
}
#endif
