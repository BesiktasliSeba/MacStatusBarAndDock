// test-fitquestion.m -- Mac test of what waits for Fit's question for a third window (statusbar/FitPlan.h): a link's URL and a Spotlight result's actions start with the launch the question
// holds, not with the request (code review 1.8.1, 2). Run by test-fitquestion.sh, as a run of the delivery's own clock: its 100 tries, 0.1 s apart, on a made-up timeline.
#import <Foundation/Foundation.h>
#include "../statusbar/FitPlan.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, BOOL ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
// The delivery as StatusBar.x runs it: from `start`, a try each 0.1 s, 100 of them. The scene is there sceneUp seconds after the launch. YES: delivered.
static BOOL DeliveredFrom(double start, double launchAt, double sceneUp) {
    for (int attempt = 0; attempt <= 100; attempt++) if (start + attempt * 0.1 >= launchAt + sceneUp) return YES;
    return NO;
}
int main(void) {
    @autoreleasepool {
        void (^launch)(CGRect) = ^(CGRect f) {};
        NSMutableDictionary *ctx = [@{ @"new": @"com.apple.Maps", @"left": @"a", @"right": @"b", @"prelaunch": launch } mutableCopy];
        __block int ran = 0;
        void (^one)(void) = ^{ ran++; };
        Expect("the question holding this app's launch: the hand-over waits", MSBDFitHoldAfterLaunch(ctx, @"com.apple.Maps", one));
        Expect("  ... nothing runs yet", ran == 0);
        Expect("  ... an open's second part waits too (the URL and the actions, or a second link)", MSBDFitHoldAfterLaunch(ctx, @"com.apple.Maps", one));
        Expect("  ... another app's: it does not wait (it opens at once)", !MSBDFitHoldAfterLaunch(ctx, @"com.apple.tips", one));
        MSBDFitRunAfterLaunch(ctx);
        Expect("the answer's launch: they run, each once", ran == 2);
        MSBDFitRunAfterLaunch(ctx);
        Expect("  ... not again", ran == 2 && !ctx[@"afterLaunch"]);
        Expect("no question: it does not wait", !MSBDFitHoldAfterLaunch(nil, @"com.apple.Maps", one));
        NSMutableDictionary *up = [@{ @"new": @"com.apple.Maps", @"left": @"a", @"right": @"b", @"stageRef": @"a window" } mutableCopy];
        Expect("a question about a window already up (no launch held): it does not wait", !MSBDFitHoldAfterLaunch(up, @"com.apple.Maps", one));
        NSMutableDictionary *done = [@{ @"new": @"com.apple.Maps", @"prelaunch": launch, @"decided": @YES } mutableCopy];
        Expect("a question already decided: it does not wait", !MSBDFitHoldAfterLaunch(done, @"com.apple.Maps", one));
        Expect("  ... nothing asked of nonsense", !MSBDFitHoldAfterLaunch(ctx, nil, one) && !MSBDFitHoldAfterLaunch(ctx, @"com.apple.Maps", nil));
        // The review's scenario, on the delivery's own clock: a link at 0, the app's scene 1.5 s after its launch
        Expect("before: not answered, the default at 12 s, tried from the request: lost", !DeliveredFrom(0, 12, 1.5));
        Expect("before: answered at 10 s, tried from the request: lost", !DeliveredFrom(0, 10, 1.5));
        Expect("now: not answered, tried from the launch: delivered", DeliveredFrom(12, 12, 1.5));
        Expect("now: answered at 10 s: delivered", DeliveredFrom(10, 10, 1.5));
        Expect("now: a turn made it 20 s: delivered", DeliveredFrom(20, 20, 1.5));
    }
    printf("fitquestion: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
