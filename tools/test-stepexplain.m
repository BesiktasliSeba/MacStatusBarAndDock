// test-stepexplain.m -- Mac test of the plain words for the crash guard's step 1b (common/CrashExplain.h, action 4): the pages' footer, the
// notice's text and title, and the Report a Problem line. Run: tools/test-crashstep.sh (MSBD_GUARD_RECORD points at a temp file).
#import "../common/CrashExplain.h"
static int fails = 0;
static void Expect(NSString *what, NSString *got, NSString *want) {
    BOOL ok = [got isEqualToString:want];
    printf("%s  %s\n      %s\n", ok ? "PASS" : "FAIL", what.UTF8String, got.UTF8String);
    if (!ok) { printf("      want: %s\n", want.UTF8String); fails++; }
}
static void Record(NSString *lines) {
    NSString *r = [NSString stringWithFormat:@"time %ld\naction 4\ntested 1\nios 16.5\nbuild 1.0.0\nverdict 1\nblamed MacStatusBarCore.dylib_(faulting_thread)\n%@", (long)time(NULL), lines];
    [r writeToFile:@MSBD_GUARD_RECORD atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
int main(void) {
    @autoreleasepool {
        Record(@"feature com.besiktasliseba.macstatusbar macBanners 0 Mac-Style Banners|the Mac-style banners\n");
        Expect(@"banners: footer", MSBDGuardExplanation(4, NO, NO), @"SpringBoard crashed twice in the Mac-style banners, so “Mac-Style Banners” was turned off. You can switch it back here; if this keeps happening, tap Report a Problem.");
        Expect(@"banners: notice title", MSBDGuardAlertTitle(4), @"Feature Turned Off");
        Expect(@"banners: Report a Problem line", MSBDGuardActionWords(MSBDCrashRecord()), @"turned off “Mac-Style Banners” (only what crashed)");
        Expect(@"banners: our part named", MSBDCrashPartName(MSBDCrashRecord()), @"MacStatusBarCore");
        Record(@"feature com.besiktasliseba.macstatusbar stockStatusBar 1 Status Bar Style|the status bar\n");
        Expect(@"status bar: footer", MSBDGuardExplanation(4, NO, NO), @"SpringBoard crashed twice in the status bar, so the stock status bar is used for now. Set Status Bar Style back to Mac to try again, or tap Report a Problem.");
        Expect(@"status bar: notice", MSBDGuardExplanation(4, NO, YES), @"SpringBoard crashed twice in the status bar, so the stock status bar is used for now. To try again, set Status Bar Style back to Mac in Settings.");
        Expect(@"status bar: notice title", MSBDGuardAlertTitle(4), @"Stock Status Bar in Use");
        Expect(@"status bar: Report a Problem line", MSBDGuardActionWords(MSBDCrashRecord()), @"switched to the stock status bar (only what crashed)");
        Record(@"part DockMagnification the Dock|MacDock\n");
        Expect(@"Dock: footer", MSBDGuardExplanation(4, NO, NO), @"SpringBoard crashed twice in the Dock, so MacDock was turned off for now. Tap Turn Back On to try again, or Report a Problem.");
        Expect(@"Dock: untested iPadOS footer", MSBDGuardExplanation(4, YES, NO), @"SpringBoard crashed twice in the Dock, so MacDock was turned off for now. Turn Enable Anyway off and on to try again, or tap Report a Problem.");
        Expect(@"Dock: Report a Problem line", MSBDGuardActionWords(MSBDCrashRecord()), @"stopped loading MacDock (DockMagnification) (only what crashed)");
        Record(@"part DockMagnification the Dock|MacDock\npart MixAudio the audio mixing|audio mixing\nagain 1\n");
        Expect(@"two parts, after step 1: footer", MSBDGuardExplanation(4, NO, NO), @"SpringBoard crashed again in the Dock and the audio mixing, so MacDock was turned off for now and audio mixing was turned off for now. Tap Turn Back On to try again, or Report a Problem.");
        Expect(@"two parts: notice title", MSBDGuardAlertTitle(4), @"Features Turned Off");
        Record(@"feature com.besiktasliseba.macstatusbar hideTrafficLights 1 Turn Off Traffic Lights|the traffic lights\n");
        Expect(@"a switch turned ON to turn a feature off", MSBDGuardExplanation(4, NO, NO), @"SpringBoard crashed twice in the traffic lights, so “Turn Off Traffic Lights” was turned on. You can switch it back here; if this keeps happening, tap Report a Problem.");
        Expect(@"the older actions still read the same", MSBDGuardExplanation(2, NO, NO), @"MacStatusBar&Dock was turned off after SpringBoard crashed twice. Tap Turn Back On to try again, or Report a Problem.");
    }
    return fails ? 1 : 0;
}
