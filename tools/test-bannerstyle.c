// Mac test of Banner Style's rule (common/BannerStyle.h, 1.8.0 item 2): the stored value and the old Mac-Style Banners switch as every side reads
// them, the rule (a stored style that can be had; never set: ours for everyone, KT 3 Nov -- Mac, iPadOS where the old switch was turned off --,
// Destra installed and showing its banners or not), the style in force in SpringBoard, SpringBoard's word for Settings and the note it gives, and
// the Style page's Destra row (always there, greyed while not installed). Run by test-bannerstyle.sh.
#include <stdio.h>
#include "../common/BannerStyle.h"
static int fails = 0, checks = 0;
#define CHECK(cond, what) do { checks++; if (!(cond)) { fails++; printf("FAIL: %s\n", what); } } while (0)
enum { M = kMSBDBannerMac, S = kMSBDBannerStock, D = kMSBDBannerDestra, N = kMSBDBannerNone };
int main(void) {
    // ---- what is stored ----
    CFNumberRef zero = CFNumberCreate(NULL, kCFNumberIntType, &(int){0}), one = CFNumberCreate(NULL, kCFNumberIntType, &(int){1});
    CFNumberRef zeroD = CFNumberCreate(NULL, kCFNumberDoubleType, &(double){0.0});
    CHECK(MSBDBannerStyleFromStored(NULL) == N, "nothing stored: never set");
    CHECK(MSBDBannerStyleFromStored(CFSTR("mac")) == M && MSBDBannerStyleFromStored(CFSTR("stock")) == S && MSBDBannerStyleFromStored(CFSTR("destra")) == D, "the three values");
    CHECK(MSBDBannerStyleFromStored(CFSTR("Mac")) == N && MSBDBannerStyleFromStored(CFSTR("ipados")) == N && MSBDBannerStyleFromStored(CFSTR("")) == N
          && MSBDBannerStyleFromStored(CFSTR("bigsurcenter")) == N, "any other text: never set (the values are exact)");
    CHECK(MSBDBannerStyleFromStored(kCFBooleanFalse) == S, "false -- the crash guard's -- is iPadOS's");
    CHECK(MSBDBannerStyleFromStored(zero) == S && MSBDBannerStyleFromStored(zeroD) == S, "  ... and 0, as a number of either kind");
    CHECK(MSBDBannerStyleFromStored(kCFBooleanTrue) == N && MSBDBannerStyleFromStored(one) == N, "true or 1: never set (no style of its own)");
    for (int st = 1; st <= 3; st++) {   // (the row's values read back as the style they name)
        CFStringRef v = CFStringCreateWithCString(NULL, MSBDBannerStyleValue(st), kCFStringEncodingUTF8);
        CHECK(MSBDBannerStyleFromStored(v) == st, "a style's value reads back as itself");
        CFRelease(v);
    }
    CHECK(MSBDBannerStyleValue(N) == NULL && MSBDBannerStyleValue(9) == NULL, "no value for none");
    // ---- the old switch (macBanners) ----
    CHECK(MSBDBannerLegacyFromStored(NULL) == N, "the old switch never set: none (Mac by the rule)");
    CHECK(MSBDBannerLegacyFromStored(kCFBooleanTrue) == M && MSBDBannerLegacyFromStored(kCFBooleanFalse) == S, "on: Mac, off: iPadOS (KT 2 Nov)");
    CHECK(MSBDBannerLegacyFromStored(one) == M && MSBDBannerLegacyFromStored(zero) == S && MSBDBannerLegacyFromStored(zeroD) == S, "  ... as a number too");
    CHECK(MSBDBannerLegacyFromStored(CFSTR("mac")) == N && MSBDBannerLegacyFromStored(CFSTR("0")) == N, "  ... text: none (never written by the switch)");
    // ---- the rule: MSBDBannerStyleChosen(stored, old switch, Destra installed) ----
    CHECK(MSBDBannerStyleChosen(N, N, 0) == M, "never set, no Destra: Mac (new users)");
    CHECK(MSBDBannerStyleChosen(N, M, 0) == M, "updater with Mac-Style Banners on: Mac");
    CHECK(MSBDBannerStyleChosen(N, S, 0) == S, "updater with Mac-Style Banners off: iPadOS (the user's own choice)");
    CHECK(MSBDBannerStyleChosen(N, M, 1) == M && MSBDBannerStyleChosen(N, N, 1) == M,
          "never set, Destra installed: Mac all the same -- ours is the default for everyone, also where Destra showed its banners (KT 3 Nov), and KT's M1");
    CHECK(MSBDBannerStyleChosen(N, S, 1) == S, "  ... the old switch turned off: iPadOS, Destra installed or not");
    CHECK(MSBDBannerStyleChosen(M, S, 1) == M && MSBDBannerStyleChosen(M, N, 0) == M, "Mac stored: Mac (whatever the old switch and Destra)");
    CHECK(MSBDBannerStyleChosen(S, M, 1) == S && MSBDBannerStyleChosen(S, N, 0) == S, "iPadOS stored: iPadOS, always");
    CHECK(MSBDBannerStyleChosen(D, M, 1) == D && MSBDBannerStyleChosen(D, S, 1) == D && MSBDBannerStyleChosen(D, N, 1) == D,
          "Destra stored and installed: Destra (the pick decides, whatever the old switch)");
    CHECK(MSBDBannerStyleChosen(D, M, 0) == M && MSBDBannerStyleChosen(D, S, 0) == S && MSBDBannerStyleChosen(D, N, 0) == M, "Destra stored but gone: the old switch");
    CHECK(MSBDBannerLoadsDestra(D) && !MSBDBannerLoadsDestra(M) && !MSBDBannerLoadsDestra(S) && !MSBDBannerLoadsDestra(N), "Destra loads only with its own style");
    for (int st = 0; st <= 3; st++) for (int l = 0; l <= 2; l++) for (int i = 0; i < 2; i++) {
        int c = MSBDBannerStyleChosen(st, l, i);
        CHECK(c >= M && c <= D, "the rule always gives a style");
        CHECK(c != D || i, "  ... Destra only where it is installed");
        CHECK(c != D || st == D, "  ... and only where it is stored: never the default (ours for everyone, KT 3 Nov)");
        CHECK(st == M || st == S || (st == D && i) || c == (l == S ? S : M), "  ... never set (or Destra stored but gone): the old switch decides -- off iPadOS, on or never set Mac");
        CHECK((st != M && st != S) || c == st, "  ... a stored Mac or iPadOS is the style");
    }
    // ---- in force in SpringBoard: MSBDBannerInForce(chosen, Destra loaded, Destra on in its own settings) ----
    CHECK(MSBDBannerInForce(M, 1, 1) == D && MSBDBannerInForce(S, 1, 1) == D, "Destra loaded and on: Destra whatever is chosen (ours steps aside until the respring)");
    CHECK(MSBDBannerInForce(M, 1, 0) == M, "Destra loaded but off in its own settings, Mac chosen: ours (KT's M1 before 1.8.0)");
    CHECK(MSBDBannerInForce(D, 0, 1) == S && MSBDBannerInForce(D, 0, 0) == S, "Destra chosen but not loaded yet: iPadOS's until the respring");
    CHECK(MSBDBannerInForce(D, 1, 0) == S, "Destra chosen, loaded, off in its own settings: iPadOS's (ours never in for it)");
    CHECK(MSBDBannerInForce(D, 1, 1) == D && MSBDBannerInForce(M, 0, 0) == M && MSBDBannerInForce(S, 0, 1) == S, "otherwise the chosen one");
    // ---- SpringBoard's word for Settings, and the note ----
    CHECK(MSBDBannerStateInForce(0) == N && !MSBDBannerStateDestraLoaded(0), "no word: nothing known");
    for (int st = 1; st <= 3; st++) for (int l = 0; l < 2; l++) {
        uint64_t w = MSBDBannerStateMake(st, l);
        CHECK(w && MSBDBannerStateInForce(w) == st && MSBDBannerStateDestraLoaded(w) == l, "the word reads back (style in force, Destra loaded)");
    }
    CHECK(MSBDBannerRespringNote(S, 1, 1, MSBDBannerStateMake(D, 1)) == 1 && MSBDBannerRespringNote(M, 1, 1, MSBDBannerStateMake(M, 1)) == 1,
          "Mac or iPadOS chosen, Destra still loaded: \"stays loaded until you respring\"");
    CHECK(MSBDBannerRespringNote(M, 1, 0, MSBDBannerStateMake(D, 1)) == 3 && MSBDBannerRespringNote(S, 1, 0, MSBDBannerStateMake(M, 1)) == 3,
          "  ... with nothing to keep it out (no Choicy, no iCleaner Pro): no respring does it, Choicy is needed (a never-set style meets this with no pick)");
    CHECK(MSBDBannerRespringNote(D, 1, 1, MSBDBannerStateMake(S, 0)) == 2, "Destra chosen, not loaded yet: \"loads after a respring\"");
    CHECK(MSBDBannerRespringNote(D, 0, 1, MSBDBannerStateMake(S, 0)) == 0, "  ... not when it is not installed (nothing would load)");
    CHECK(MSBDBannerRespringNote(D, 1, 1, MSBDBannerStateMake(D, 1)) == 0 && MSBDBannerRespringNote(M, 1, 1, MSBDBannerStateMake(M, 0)) == 0
          && MSBDBannerRespringNote(D, 1, 0, MSBDBannerStateMake(D, 1)) == 0 && MSBDBannerRespringNote(M, 1, 0, MSBDBannerStateMake(M, 0)) == 0, "as chosen: no note (Choicy there or not)");
    CHECK(MSBDBannerRespringNote(M, 1, 1, 0) == 0 && MSBDBannerRespringNote(D, 1, 1, 0) == 0 && MSBDBannerRespringNote(M, 1, 0, 0) == 0, "no word from SpringBoard: no note");
    // ---- the Style page's Destra row ----
    CHECK(MSBDBannerDestraRowState(1) == 2, "Destra installed: it can be picked");
    CHECK(MSBDBannerDestraRowState(0) == 0, "  ... not installed: on the page all the same, greyed and not picked (KT 3 Nov; no page of its developer's to GET it from)");
    CFRelease(zero); CFRelease(one); CFRelease(zeroD);
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
