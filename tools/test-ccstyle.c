// Mac test of Control Center Style's rule (common/CCStyle.h, 1.8.0 item 3): the stored value as every side reads it, the rule (a stored style that
// can be had; never set: BigSurCenter where it is installed and not switched off by the user, else iPadOS -- Mac only when picked), the style in
// force in SpringBoard, SpringBoard's word for Settings and the note it gives, and the Style page's Mac and BigSurCenter rows. Run by
// test-ccstyle.sh.
#include <stdio.h>
#include "../common/CCStyle.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
enum { M = kMSBDCCStyleMac, S = kMSBDCCStyleStock, B = kMSBDCCStyleBigSurCenter, N = kMSBDCCStyleNone };
int main(void) {
    // ---- what is stored ----
    CFNumberRef zero = CFNumberCreate(NULL, kCFNumberIntType, &(int){0}), one = CFNumberCreate(NULL, kCFNumberIntType, &(int){1});
    CFNumberRef zeroD = CFNumberCreate(NULL, kCFNumberDoubleType, &(double){0.0});
    CHECK(MSBDCCStyleFromStored(NULL) == N, "nothing stored: never set");
    CHECK(MSBDCCStyleFromStored(CFSTR("mac")) == M && MSBDCCStyleFromStored(CFSTR("stock")) == S && MSBDCCStyleFromStored(CFSTR("bigsurcenter")) == B, "the three values");
    CHECK(MSBDCCStyleFromStored(CFSTR("Mac")) == N && MSBDCCStyleFromStored(CFSTR("ipados")) == N && MSBDCCStyleFromStored(CFSTR("")) == N, "any other text: never set (the values are exact)");
    CHECK(MSBDCCStyleFromStored(kCFBooleanFalse) == S, "false -- the crash guard's -- is iPadOS's");
    CHECK(MSBDCCStyleFromStored(zero) == S && MSBDCCStyleFromStored(zeroD) == S, "  ... and 0, as a number of either kind");
    CHECK(MSBDCCStyleFromStored(kCFBooleanTrue) == N && MSBDCCStyleFromStored(one) == N, "true or 1: never set (no style of its own)");
    for (int st = 1; st <= 3; st++) {   // (the row's values read back as the style they name)
        CFStringRef v = CFStringCreateWithCString(NULL, MSBDCCStyleValue(st), kCFStringEncodingUTF8);
        CHECK(MSBDCCStyleFromStored(v) == st, "a style's value reads back as itself");
        CFRelease(v);
    }
    CHECK(MSBDCCStyleValue(N) == NULL && MSBDCCStyleValue(9) == NULL, "no value for none");
    // ---- where Mac runs ----
    CHECK(MSBDCCMacRuns(15, 1, 0) && MSBDCCMacRuns(16, 1, 0) && MSBDCCMacRuns(17, 1, 0), "Mac runs on 15-17 where the check passed");
    CHECK(MSBDCCMacRuns(18, 1, 0), "  ... and on 18 where its own check passed (Apple's 18 grid re-shaped into the Mac panel, CC18Shape.h)");
    CHECK(!MSBDCCMacRuns(18, 0, 0) && !MSBDCCMacRuns(18, -1, 0) && !MSBDCCMacRuns(18, 1, 1), "  ... not on 18 where that check failed, was not run on this build yet, or with Status Bar Style Stock");
    CHECK(!MSBDCCMacRuns(19, 1, 0) && !MSBDCCMacRuns(26, 1, 0) && !MSBDCCMacRuns(14, 1, 0), "  ... never after 18 (a Control Center never read), nor before 15");
    CHECK(!MSBDCCMacRuns(16, 0, 0) && !MSBDCCMacRuns(16, -1, 0), "  ... not where it failed or was not checked on this build yet");
    CHECK(!MSBDCCMacRuns(15, 1, 1) && !MSBDCCMacRuns(16, 1, 1) && !MSBDCCMacRuns(17, 1, 1), "  ... not with Status Bar Style Stock (the panel starts on our status bar's path only)");
    CHECK(MSBDCCStyleChosen(M, 0, 0, MSBDCCMacRuns(17, 1, 1)) == S && MSBDCCStyleChosen(N, 0, 0, MSBDCCMacRuns(17, 1, 1)) == S, "  ... so Mac stored or never set falls back to iPadOS's there");
    CHECK(MSBDCCStyleChosen(N, 1, 0, MSBDCCMacRuns(16, 1, 1)) == B, "  ... BigSurCenter installed stays the default with the stock bar (as before)");
    // ---- the rule: MSBDCCStyleChosen(stored, BigSurCenter installed, switched off by the user, Mac runs) ----
    CHECK(MSBDCCStyleChosen(N, 1, 0, 1) == B, "never set, BigSurCenter installed: BigSurCenter (updaters who have it keep it)");
    CHECK(MSBDCCStyleChosen(N, 1, 0, 0) == B, "  ... where Mac does not run too");
    CHECK(MSBDCCStyleChosen(N, 1, 1, 1) == S, "never set, BigSurCenter switched off by the user: iPadOS, also where Mac runs (Mac only when picked)");
    CHECK(MSBDCCStyleChosen(N, 1, 1, 0) == S, "  ... and where it does not");
    CHECK(MSBDCCStyleChosen(N, 0, 0, 1) == S, "never set, no BigSurCenter: iPadOS, also where Mac runs (everyone keeps the Control Center they have -- KT 3 Nov)");
    CHECK(MSBDCCStyleChosen(N, 0, 0, 0) == S, "  ... and where Mac does not run (iPadOS 18, a failed check, a build without it)");
    CHECK(MSBDCCStyleChosen(M, 1, 0, 1) == M && MSBDCCStyleChosen(M, 0, 0, 1) == M, "Mac stored, Mac runs: Mac (BigSurCenter or not)");
    CHECK(MSBDCCStyleChosen(M, 1, 0, 0) == S && MSBDCCStyleChosen(M, 0, 0, 0) == S, "Mac stored where it can't run: iPadOS, never BigSurCenter (chosen against)");
    CHECK(MSBDCCStyleChosen(S, 1, 0, 1) == S && MSBDCCStyleChosen(S, 0, 0, 0) == S, "iPadOS stored: iPadOS, always");
    CHECK(MSBDCCStyleChosen(B, 1, 0, 1) == B && MSBDCCStyleChosen(B, 1, 1, 0) == B, "BigSurCenter stored and installed: BigSurCenter (the pick wins over the user's own switch-off)");
    CHECK(MSBDCCStyleChosen(B, 0, 0, 1) == S && MSBDCCStyleChosen(B, 0, 0, 0) == S, "BigSurCenter stored but gone: the default without it, iPadOS");
    CHECK(MSBDCCStyleLoadsBigSurCenter(B) && !MSBDCCStyleLoadsBigSurCenter(M) && !MSBDCCStyleLoadsBigSurCenter(S), "BigSurCenter loads only with its own style");
    for (int st = 0; st <= 3; st++) for (int i = 0; i < 2; i++) for (int u = 0; u < 2; u++) for (int r = 0; r < 2; r++) {
        int c = MSBDCCStyleChosen(st, i, u, r);
        CHECK(c >= M && c <= B, "the rule always gives a style");
        CHECK(c != B || i, "  ... BigSurCenter only where it is installed");
        CHECK(c != M || r, "  ... Mac only where it runs");
        CHECK(c != M || st == M, "  ... and only where it is stored (the user picked it: never the default)");
    }
    // ---- in force in SpringBoard ----
    CHECK(MSBDCCStyleInForce(M, 1) == B && MSBDCCStyleInForce(S, 1) == B, "BigSurCenter's classes loaded: BigSurCenter whatever is chosen (ours never goes in next to it)");
    CHECK(MSBDCCStyleInForce(B, 0) == S, "BigSurCenter chosen but not loaded yet: iPadOS's until the respring");
    CHECK(MSBDCCStyleInForce(M, 0) == M && MSBDCCStyleInForce(S, 0) == S && MSBDCCStyleInForce(B, 1) == B, "otherwise the chosen one");
    // ---- SpringBoard's word for Settings, and the note ----
    CHECK(MSBDCCStyleStateInForce(0) == N && !MSBDCCStyleStateBSCLoaded(0), "no word: nothing known");
    for (int st = 1; st <= 3; st++) for (int l = 0; l < 2; l++) {
        uint64_t w = MSBDCCStyleStateMake(st, l);
        CHECK(w && MSBDCCStyleStateInForce(w) == st && MSBDCCStyleStateBSCLoaded(w) == l, "the word reads back (style in force, BigSurCenter loaded)");
    }
    CHECK(MSBDCCStyleRespringNote(S, 1, MSBDCCStyleStateMake(B, 1)) == 1, "iPadOS chosen, BigSurCenter still loaded: \"stays loaded until you respring\"");
    CHECK(MSBDCCStyleRespringNote(M, 1, MSBDCCStyleStateMake(B, 1)) == 1, "  ... Mac chosen the same");
    CHECK(MSBDCCStyleRespringNote(B, 1, MSBDCCStyleStateMake(S, 0)) == 2, "BigSurCenter chosen, not loaded yet: \"loads after a respring\"");
    CHECK(MSBDCCStyleRespringNote(B, 0, MSBDCCStyleStateMake(S, 0)) == 0, "  ... not when it is not installed (nothing would load)");
    CHECK(MSBDCCStyleRespringNote(B, 1, MSBDCCStyleStateMake(B, 1)) == 0 && MSBDCCStyleRespringNote(S, 1, MSBDCCStyleStateMake(S, 0)) == 0, "as chosen: no note");
    CHECK(MSBDCCStyleRespringNote(S, 1, 0) == 0 && MSBDCCStyleRespringNote(B, 1, 0) == 0, "no word from SpringBoard: no note");
    // ---- the Style page's rows ----
    CHECK(MSBDCCMacRowState(16, 1, 1, 0) == 0 && MSBDCCMacRowState(15, 1, 1, 0) == 0 && MSBDCCMacRowState(17, 1, 1, 0) == 0, "Mac row: can be picked on 15-17 where the check passed");
    CHECK(MSBDCCMacRowState(18, 1, 1, 0) == 0, "  ... on 18 where its check passed (1.8.0 P5b)");
    CHECK(MSBDCCMacRowState(18, 0, 1, 0) == 1 && MSBDCCMacRowState(18, -1, 1, 0) == 2, "  ... on 18 \"Not Supported Yet\" where it failed, \"Respring to Check\" before its first check");
    CHECK(MSBDCCMacRowState(19, 1, 1, 0) == 1 && MSBDCCMacRowState(26, 1, 1, 0) == 1, "  ... greyed \"Not Supported Yet\" after 18");
    CHECK(MSBDCCMacRowState(16, 0, 1, 0) == 1, "  ... \"Not Supported Yet\" where the check failed");
    CHECK(MSBDCCMacRowState(16, -1, 1, 0) == 2, "  ... \"Respring to Check\" where this build was not checked yet");
    CHECK(MSBDCCMacRowState(16, 1, 0, 0) == 1, "  ... \"Not Supported Yet\" in a build without our Control Center");
    CHECK(MSBDCCMacRowState(16, 1, 1, 1) == 3 && MSBDCCMacRowState(15, -1, 1, 1) == 3 && MSBDCCMacRowState(17, 0, 1, 1) == 3, "  ... \"Needs Mac Status Bar\" with Status Bar Style Stock, whatever the check said");
    CHECK(MSBDCCMacRowState(18, 1, 1, 1) == 3, "  ... on 18 too");
    CHECK(MSBDCCMacRowState(26, 1, 1, 1) == 1 && MSBDCCMacRowState(16, 1, 0, 1) == 1, "  ... but \"Not Supported Yet\" first where it can't run at all");
    CHECK(MSBDCCBigSurCenterRowState(16, 1) == 2 && MSBDCCBigSurCenterRowState(18, 1) == 2, "BigSurCenter row: installed, it can be picked (on 18 too)");
    CHECK(MSBDCCBigSurCenterRowState(15, 0) == 0 && MSBDCCBigSurCenterRowState(16, 0) == 0, "  ... not installed on 15 / 16: greyed with GET");
    CHECK(MSBDCCBigSurCenterRowState(17, 0) == -1 && MSBDCCBigSurCenterRowState(18, 0) == -1, "  ... not installed on 17 and later: left off (its page offers it up to 16.3.1)");
    CFRelease(zero); CFRelease(one); CFRelease(zeroD);
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
