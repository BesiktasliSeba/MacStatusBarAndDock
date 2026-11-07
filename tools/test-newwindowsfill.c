// test-newwindowsfill.c -- Mac test of New Windows Open at Fill (1.8.3 item 2; common/WindowSize.h): which window that opens goes to Fill, and that Fit to
// Window leaves it out (no side question). Run by test-newwindowsfill.sh, which then checks the sites on every engine.
#include <stdio.h>
#include "../common/WindowSize.h"
static int fails = 0, checks = 0;
static void Yes(const char *what, int ok) { checks++; if (ok) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } }
int main(void) {
    Yes("switch off (never set): no window goes to Fill (as before)", !MSBDNewWindowAtFill(false, false, false));
    Yes("on: a window that opens with no place of its own goes to Fill", MSBDNewWindowAtFill(true, false, false));
    Yes("  ... one back at its own place keeps it", !MSBDNewWindowAtFill(true, true, false));
    Yes("  ... one asked to a frame (a layout, the green light's way back to its place) goes there", !MSBDNewWindowAtFill(true, false, true));
    Yes("Fit to Window on: a window that opens is taken into its tiles (as before)", MSBDFitTakesOpening(true, false));
    Yes("  ... not one that opens at Fill: no side question, no tile taken", !MSBDFitTakesOpening(true, true));
    Yes("Fit off: nothing is tiled either way", !MSBDFitTakesOpening(false, false) && !MSBDFitTakesOpening(false, true));
    Yes("the key it is stored under", !strcmp(kMSBDNewWindowsFillKey, "newWindowsFill"));
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
