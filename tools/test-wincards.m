// Mac test of the plan behind the windows' App Switcher cards (statusbar/WindowCardPlan.h, used by statusbar/WindowCards.h): when SpringBoard is
// asked for a window's card, and when the front window's card goes first. Cases from the M1 (15.6.1) measurements of 28 Oct; where it runs (17.5.1, 16.7.7, 18.5, 29 Oct);
// which windows are pictured as the App Switcher comes, and in which order (one per turn of the run loop, the front window first).
#import <Foundation/Foundation.h>
#include "../statusbar/WindowCardPlan.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
int main(void) {
    @autoreleasepool {
        NSArray *none = @[];
        NSArray *tips = @[@[@"com.apple.tips"]];
        NSArray *split = @[@[@"com.apple.mobilesafari", @"com.apple.mobilenotes"]];
        NSArray *three = @[@[@"com.apple.AppStore"], @[@"com.apple.tips"], @[@"com.apple.mobiletimer"]];
        // asking SpringBoard for a card
        CHECK(MSBDWinCardShouldAsk(@"com.apple.mobiletimer", NO, NO, YES, none), "a window with no card at all is asked for");
        CHECK(MSBDWinCardShouldAsk(@"com.apple.mobiletimer", NO, NO, YES, tips), "a window whose app has no card is asked for (other cards there)");
        CHECK(!MSBDWinCardShouldAsk(@"com.apple.tips", NO, NO, YES, tips), "full screen first, then a window: its card is there, nothing asked");
        CHECK(!MSBDWinCardShouldAsk(@"com.apple.mobilenotes", NO, NO, YES, split), "an app in a Split View card has a card: nothing asked");
        CHECK(!MSBDWinCardShouldAsk(@"com.apple.mobiletimer", YES, NO, YES, none), "asked once already: not again");
        CHECK(!MSBDWinCardShouldAsk(@"com.apple.mobiletimer", NO, YES, YES, none), "a window on its way out (closing): not asked");
        CHECK(!MSBDWinCardShouldAsk(@"com.apple.mobiletimer", NO, NO, NO, none), "no scene yet (the app still starting): not yet");
        CHECK(!MSBDWinCardShouldAsk(@"", NO, NO, YES, none) && !MSBDWinCardShouldAsk(nil, NO, NO, YES, none), "no app: never");
        CHECK(MSBDWinCardHasCard(@"com.apple.mobiletimer", three) && !MSBDWinCardHasCard(@"com.apple.Maps", three), "card lookup by app");
        // where it runs: the versions read and checked
        CHECK(MSBDWinCardOSChecked(15) && MSBDWinCardOSChecked(16) && MSBDWinCardOSChecked(17) && MSBDWinCardOSChecked(18), "15 (M1 15.6.1), 16 (iPad 2 16.7.7), 17 (17.5.1) and 18 (A12Z 18.5): windows get their cards");
        CHECK(!MSBDWinCardOSChecked(14) && !MSBDWinCardOSChecked(19) && !MSBDWinCardOSChecked(26), "any other: iPadOS's cards as they are");
        // the front window's card first
        CHECK(MSBDWinCardFrontPlan(@"com.apple.mobiletimer", three, NO, NO) == MSBDWinCardFrontMove, "front window's card third: goes first");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.AppStore", three, NO, NO) == MSBDWinCardFrontNothing, "already first: nothing");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.tips", three, YES, NO) == MSBDWinCardFrontWait, "the App Switcher is up: waits");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.tips", three, NO, YES) == MSBDWinCardFrontWait, "a transaction / gesture runs: waits");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.Maps", three, NO, NO) == MSBDWinCardFrontNothing, "no card yet: nothing (it is asked for first)");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.mobilenotes", @[@[@"com.apple.tips"], split[0]], NO, NO) == MSBDWinCardFrontNothing, "a Split View card is left where SpringBoard has it");
        CHECK(MSBDWinCardFrontPlan(nil, three, NO, NO) == MSBDWinCardFrontNothing, "no window in front: nothing");
        CHECK(MSBDWinCardFrontPlan(@"com.apple.mobiletimer", none, NO, NO) == MSBDWinCardFrontNothing, "an empty list: nothing");
        // a card's picture as the App Switcher comes: current or taken again (review of 1.7.0: all were taken inside SpringBoard's transition)
        NSString *s3 = @"3 {481, 650}";
        CHECK(MSBDWinCardPictureCurrent(100.0, 90.0, 102.0, s3, s3), "taken 2 s ago, not in front since, same shape: current");
        CHECK(!MSBDWinCardPictureCurrent(100.0, 90.0, 105.0, s3, s3) && !MSBDWinCardPictureCurrent(100.0, 90.0, 200.0, s3, s3), "5 s or more ago: taken again (a window that plays or counts)");
        CHECK(!MSBDWinCardPictureCurrent(100.0, 101.0, 102.0, s3, s3) && !MSBDWinCardPictureCurrent(100.0, 100.0, 102.0, s3, s3), "in front since (in use): taken again");
        CHECK(!MSBDWinCardPictureCurrent(100.0, 90.0, 102.0, s3, @"4 {481, 650}"), "the screen turned since: taken again (a turned picture is not found)");
        CHECK(!MSBDWinCardPictureCurrent(100.0, 90.0, 102.0, s3, @"3 {320, 324}"), "the window resized since: taken again");
        CHECK(!MSBDWinCardPictureCurrent(0.0, 0.0, 2.0, nil, s3) && !MSBDWinCardPictureCurrent(100.0, 0.0, 101.0, nil, s3), "never pictured, or no shape kept: taken");
        CHECK(!MSBDWinCardPictureCurrent(100.0, 0.0, 99.0, s3, s3), "a clock that went back: taken again");
        CHECK(MSBDWinCardPictureCurrent(100.0, 0.0, 101.0, s3, s3), "never in front, pictured a second ago: current");
        // which windows, in which order (back to front in; front first, then the rest from the front back, out)
        NSUInteger ord[8], k;
        MSBDWinCardPicWindow four[4] = {   // back to front: Tips (shows, stale), Clock (front, stale), Notes (minimized, pictured), Maps (shows, current)
            { YES, YES, YES, NO, NO }, { YES, YES, YES, NO, YES }, { YES, NO, YES, NO, NO }, { YES, YES, YES, YES, NO } };
        k = MSBDWinCardPictureOrder(four, 4, ord);
        CHECK(k == 2 && ord[0] == 1 && ord[1] == 0, "the front window first, then the stale ones front to back; current and hidden-with-a-picture left");
        MSBDWinCardPicWindow fresh[3] = { { YES, YES, NO, NO, NO }, { YES, NO, NO, NO, NO }, { NO, YES, NO, NO, NO } };   // new, hidden new, no app
        k = MSBDWinCardPictureOrder(fresh, 3, ord);
        CHECK(k == 2 && ord[0] == 1 && ord[1] == 0, "never pictured, shown or not: taken (front to back); no app yet: left out");
        MSBDWinCardPicWindow two[3] = { { YES, YES, NO, NO, YES }, { YES, YES, NO, NO, NO }, { YES, YES, NO, NO, YES } };   // two windows of the front app
        k = MSBDWinCardPictureOrder(two, 3, ord);
        CHECK(k == 3 && ord[0] == 2 && ord[1] == 1 && ord[2] == 0, "two windows of the front app: its frontmost first, the other in its place");
        MSBDWinCardPicWindow frontCurrent[2] = { { YES, YES, NO, NO, NO }, { YES, YES, YES, YES, YES } };
        k = MSBDWinCardPictureOrder(frontCurrent, 2, ord);
        CHECK(k == 1 && ord[0] == 0, "the front window's picture current: only the others");
        CHECK(MSBDWinCardPictureOrder(NULL, 0, ord) == 0, "no windows: nothing");
    }
    printf("%s: %d checks, %d failed\n", fails ? "FAILED" : "ok", checks, fails);
    return fails ? 1 : 0;
}
