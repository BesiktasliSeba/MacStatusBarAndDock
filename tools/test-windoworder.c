// test-windoworder.c -- Mac test of common/WindowOrder.h (1.8.4.1 item 6): the order windows end in when an app's windows or one window come to the
// front, as on a Mac. Run by test-windoworder.sh.
#include <stdio.h>
#include <string.h>
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
    int out[16];
    {   // KT's case (8 Nov, the M1, Aerial): Notes small in front of Safari big; Safari clicked: Safari in front. Back to front: [Notes, Safari].
        int apps[] = { 1 /* Notes */, 2 /* Safari */ };
        int n = MSBDOrderAppToFront(apps, 2, 1, out);
        int want[] = { 1, 0 };
        Seq("a small window behind a big one: its Dock icon, Command-Tab or the Mac Switcher bring it above the big one", out, n, want, 2);
    }
    {   // three apps, the middle app with two windows (Stage Manager), back to front: [A, B1, C, B2]
        int apps[] = { 0, 1, 2, 1 };
        int n = MSBDOrderAppToFront(apps, 4, 1, out);
        int want[] = { 0, 2, 1, 3 };
        Seq("Bring All to Front: all of the front app's windows above the other apps' windows, each in its own order", out, n, want, 4);
        n = MSBDOrderAppToFront(apps, 4, 0, out);
        int want0[] = { 1, 2, 3, 0 };
        Seq("  ... an app with one window at the back: it alone comes up, the others keep their order", out, n, want0, 4);
        n = MSBDOrderAppToFront(apps, 4, 7, out);
        int same[] = { 0, 1, 2, 3 };
        Seq("  ... an app with no window there: nothing moves", out, n, same, 4);
        n = MSBDOrderAppToFront(apps, 4, 1, out);
        int again[4]; memcpy(again, out, sizeof again);
        int apps2[] = { apps[again[0]], apps[again[1]], apps[again[2]], apps[again[3]] };
        n = MSBDOrderAppToFront(apps2, 4, 1, out);
        Seq("  ... asked again: nothing moves (its windows are in front already)", out, n, same, 4);
    }
    {
        int n = MSBDOrderOneToFront(4, 1, out);
        int want[] = { 0, 2, 3, 1 };
        Seq("the Window menu's list picks one window: it alone to the front, the others as they were", out, n, want, 4);
        n = MSBDOrderOneToFront(4, 3, out);
        int same[] = { 0, 1, 2, 3 };
        Seq("  ... the front one picked: nothing moves", out, n, same, 4);
    }
    Int("no windows: nothing", MSBDOrderAppToFront(NULL, 0, 1, out) + MSBDOrderOneToFront(0, 0, out), 0);
    Int("an engine's own raise that did not take (Aerial 5's answer by its own record): the window put in front by its place", MSBDRaiseNeedsOrder(false, true), 1);
    Int("  ... it took: nothing more", MSBDRaiseNeedsOrder(true, true), 0);
    Int("  ... a window that does not show (minimized, on its way out): never put in front", MSBDRaiseNeedsOrder(false, false), 0);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
