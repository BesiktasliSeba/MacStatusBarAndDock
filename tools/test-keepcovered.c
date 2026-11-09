// test-keepcovered.c -- Mac test of Keep Covered Windows in Front (1.8.4.1 item 7; common/WindowOrder.h MSBDOrderKeepCovered, MSBDActiveWithKept):
// the windows a window that came forward covers completely stay above it; the window that came forward stays the active one. Run by test-keepcovered.sh.
#include <stdio.h>
#include <string.h>
#include <CoreGraphics/CoreGraphics.h>
#include "../common/WindowOrder.h"
static int fails = 0, checks = 0;
static void Int(const char *what, long got, long want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %ld, want %ld)\n", what, got, want); } }
static void Seq(const char *what, const int *got, int n, const int *want, int m) {
    checks++;
    int ok = n == m;
    for (int i = 0; ok && i < n; i++) if (got[i] != want[i]) ok = 0;
    if (ok) { printf("PASS  %s\n", what); return; }
    fails++; printf("FAIL  %s (got", what); for (int i = 0; i < n; i++) printf(" %d", got[i]); printf("; want"); for (int i = 0; i < m; i++) printf(" %d", want[i]); printf(")\n");
}
int main(void) {
    int out[16], kept = -1;
    CGRect big = CGRectMake(0, 24, 1194, 734), small = CGRectMake(300, 200, 400, 300), side = CGRectMake(900, 100, 400, 300), other = CGRectMake(50, 60, 500, 400);
    bool all[8] = { true, true, true, true, true, true, true, true };
    {   // KT's case: the small window in front, the big one clicked -- it came forward: back to front [small, big]
        CGRect f[] = { small, big };
        int n = MSBDOrderKeepCovered(f, all, 2, 1, out, &kept);
        int want[] = { 1, 0 };
        Seq("the big window came forward over the small one it covers completely: the small one stays in front of it", out, n, want, 2);
        Int("  ... one window kept above it", kept, 1);
    }
    {   // the small one partly outside the big one: an ordinary window
        CGRect f[] = { side, big };
        int n = MSBDOrderKeepCovered(f, all, 2, 1, out, &kept);
        int want[] = { 0, 1 };
        Seq("a window the big one covers only partly (moved out by a point or more): an ordinary window, behind it", out, n, want, 2);
        Int("  ... nothing kept", kept, 0);
    }
    {   // back to front [other, small, big, X?]: big came forward (on top); small and other both inside big; side not
        CGRect f[] = { other, side, small, big };
        int n = MSBDOrderKeepCovered(f, all, 4, 3, out, &kept);
        int want[] = { 1, 3, 0, 2 };
        Seq("several covered: all above the window that came forward, each in its own order; the others behind it as they were", out, n, want, 4);
        Int("  ... two kept", kept, 2);
    }
    {   // a minimized (not shown) small window inside the big one: left where it is
        CGRect f[] = { small, big };
        bool shown[] = { false, true };
        int n = MSBDOrderKeepCovered(f, shown, 2, 1, out, &kept);
        int want[] = { 0, 1 };
        Seq("a minimized or hidden window (or one of another desktop or screen) is left alone", out, n, want, 2);
        Int("  ... nothing kept", kept, 0);
    }
    {   // the small window itself came forward: nothing inside it
        CGRect f[] = { big, small };
        int n = MSBDOrderKeepCovered(f, all, 2, 1, out, &kept);
        int want[] = { 0, 1 };
        Seq("the small window came forward: it in front, nothing to keep", out, n, want, 2);
        Int("  ... nothing kept", kept, 0);
    }
    {   // Fit to Window's tiles: side by side, never inside one another
        CGRect l = CGRectMake(0, 24, 594, 734), r = CGRectMake(600, 24, 594, 734);
        CGRect f[] = { l, r };
        int n = MSBDOrderKeepCovered(f, all, 2, 0, out, &kept);
        int want[] = { 1, 0 };
        Seq("Fit to Window's tiles (side by side): the tile brought forward in front, as without the switch", out, n, want, 2);
        Int("  ... nothing kept", kept, 0);
    }
    {
        CGRect f[] = { small, big };
        bool shown[] = { true, false };
        int n = MSBDOrderKeepCovered(f, shown, 2, 1, out, &kept);
        int want[] = { 0, 1 };
        Seq("a window that came forward but does not show (on its way out): the order as it was", out, n, want, 2);
    }
    {   // review 1.8.4.1 H1: two apps at Fill (the title bar's Fill, Window > Fill, New Windows Open at Fill, a turn that refits both), back to front
        // [Settings, Clock]: Settings brought forward (its Dock icon, Command-Tab, the Mac Switcher) comes in front -- before, Clock was kept over it
        CGRect f[] = { big, big };
        int n = MSBDOrderKeepCovered(f, all, 2, 0, out, &kept);
        int want[] = { 1, 0 };
        Seq("two windows at Fill: the one brought forward comes in front of the other (one frame: neither covers the other)", out, n, want, 2);
        Int("  ... nothing kept", kept, 0);
        n = MSBDOrderKeepCovered(f, all, 2, 1, out, &kept);
        int want2[] = { 0, 1 };
        Seq("  ... a new window opened at Fill over a window at Fill: it stays in front", out, n, want2, 2);
        Int("  ... nothing kept", kept, 0);
        CGRect g[] = { CGRectMake(2, 26, 1190, 730), big };   // (an app's own smallest size, or rounding: two points short on each side)
        n = MSBDOrderKeepCovered(g, all, 2, 1, out, &kept);
        int want3[] = { 0, 1 };
        Seq("  ... one a few points smaller than the other (under 16 pt to spare on every side): the bigger one brought forward covers it", out, n, want3, 2);
        Int("  ... nothing kept", kept, 0);
    }
    Int("covered: not by the same frame (a window put exactly over another: neither could be brought in front of the other)", MSBDFrameCoveredBy(big, big), 0);
    Int("  ... nor inside with 16 pt or less to spare on every side", MSBDFrameCoveredBy(CGRectMake(10, 34, 1174, 714), big) || MSBDFrameCoveredBy(CGRectMake(0, 24, 1194, 718), big), 0);
    Int("  ... inside with more than 16 pt to spare on one side only (a strip of the big one to click): covered", MSBDFrameCoveredBy(CGRectMake(0, 24, 1194, 717), big), 1);
    Int("  ... a fraction of a point past the edge (frames are fractional)", MSBDFrameCoveredBy(CGRectMake(-0.5, 24, 400, 300), big), 1);
    Int("  ... a point or more past it: not inside", MSBDFrameCoveredBy(CGRectMake(-1.5, 24, 400, 300), big), 0);
    Int("  ... an empty or null frame: never", MSBDFrameCoveredBy(CGRectNull, big) || MSBDFrameCoveredBy(CGRectMake(10, 30, 0, 0), big), 0);
    {   // the active window: [small(kept), big(came forward)] drawn as [big, small]: back to front [big, small] with small kept
        bool shown[] = { true, true }, keptAbove[] = { false, true };
        CGRect fr[] = { big, small };
        Int("the window that came forward is the active one while only the windows it kept are above it (the menu bar's app, the keyboard's)", MSBDActiveWithKept(shown, keptAbove, fr, 2, 0), 0);
        bool keptNone[] = { false, false };
        Int("  ... another window came over it since: that one", MSBDActiveWithKept(shown, keptNone, fr, 2, 0), 1);
        Int("  ... none kept: the top window, as without the switch", MSBDActiveWithKept(shown, keptAbove, fr, 2, -1), 1);
        bool hidden[] = { false, true };
        Int("  ... it does not show any more: the top window", MSBDActiveWithKept(hidden, keptAbove, fr, 2, 0), 1);
        bool none[] = { false, false };
        Int("  ... no window shows: none", MSBDActiveWithKept(none, keptAbove, fr, 2, 0), -1);
        // review 1.8.4.1 M1: the kept window dragged by its title bar so that it sticks out of the big one -- an ordinary window again, the top one
        CGRect out1[] = { big, CGRectMake(1000, 500, 400, 300) };
        Int("  ... the kept window moved out of it since (a corner sticks out): the top window -- it -- is the active one", MSBDActiveWithKept(shown, keptAbove, out1, 2, 0), 1);
        CGRect out2[] = { CGRectMake(0, 24, 600, 734), small };   // (the big one made a left half: the small one no longer inside it)
        Int("  ... the window under it resized or moved so the kept one is outside it: the same", MSBDActiveWithKept(shown, keptAbove, out2, 2, 0), 1);
        CGRect in2[] = { big, CGRectMake(320, 220, 400, 300) };
        Int("  ... moved but still inside it: still the window that came forward", MSBDActiveWithKept(shown, keptAbove, in2, 2, 0), 0);
        Int("  ... no frames given: membership only", MSBDActiveWithKept(shown, keptAbove, NULL, 2, 0), 0);
    }
    Int("the switch's key", !strcmp(kMSBDKeepCoveredKey, "keepCoveredInFront"), 1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
