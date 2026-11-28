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
    {   // 1.8.9.1 (B127): Window > Bring All to Front with a big window in front and smaller covered windows behind it
        CGRect big = CGRectMake(0, 24, 1024, 700), s1 = CGRectMake(120, 80, 420, 320), s2 = CGRectMake(260, 140, 400, 300), med = CGRectMake(60, 50, 760, 520), side = CGRectMake(500, 40, 520, 680);
        bool sh4[] = { true, true, true, true }, sh3[] = { true, true, true };
        // Same app with [Other, Small1, Small2, Big]: Big was already in front of Small1 and Small2 (so MSBDOrderAppToFront saw no move at [0, 1, 1, 1]!).
        // Now Small1 and Small2 rise above Big, keeping [Small1, Small2] order, while Other stays at the back.
        int apps1[] = { 0, 1, 1, 1 };
        CGRect fr1[] = { side, s1, s2, big };
        int n = MSBDOrderBringAllToFront(apps1, fr1, sh4, 4, 1, out);
        int want1[] = { 0, 3, 1, 2 };
        Seq("1.8.9.1 Bring All to Front: two smaller windows of the app behind its big front window rise above it, keeping their relative order", out, n, want1, 4);
        // Asked again once [Other, Big, Small1, Small2] is settled: idempotent (nothing moves).
        int apps1b[] = { 0, 1, 1, 1 };
        CGRect fr1b[] = { side, big, s1, s2 };
        n = MSBDOrderBringAllToFront(apps1b, fr1b, sh4, 4, 1, out);
        int same4[] = { 0, 1, 2, 3 };
        Seq("  ... asked again once the smaller windows are in front: nothing moves", out, n, same4, 4);
        // Nested covering [Small1, Medium, Big] of the same app (Big covers Medium & Small1; Medium covers Small1): ends [Big, Medium, Small1].
        int apps2[] = { 1, 1, 1 };
        CGRect fr2[] = { s1, med, big };
        n = MSBDOrderBringAllToFront(apps2, fr2, sh3, 3, 1, out);
        int want2[] = { 2, 1, 0 };
        Seq("  ... nested sizes [Small, Medium, Big] end [Big, Medium, Small] so all three show", out, n, want2, 3);
        // Uncovered sibling stays behind BigLeft while covered sibling rises above BigLeft: [Small1, SideUncovered, BigLeft] -> [SideUncovered, BigLeft, Small1].
        CGRect bigLeft = CGRectMake(0, 24, 700, 700);
        CGRect fr3[] = { s1, side, bigLeft };
        n = MSBDOrderBringAllToFront(apps2, fr3, sh3, 3, 1, out);
        int want3[] = { 1, 2, 0 };
        Seq("  ... an uncovered sibling behind the big window keeps its relative place while the covered one rises above", out, n, want3, 3);
        // Single-window front app (Aerial / Zetsu / MilkyWay4, or 1 window per app on Stage Manager) covering smaller windows: un-buries them in order.
        int appsSingle[] = { 2, 3, 1 };
        CGRect frSingle[] = { s1, s2, big };
        n = MSBDOrderBringAllToFront(appsSingle, frSingle, sh3, 3, 1, out);
        int wantSingle[] = { 2, 0, 1 };
        Seq("  ... single-window front app covering smaller windows: lifts covered smaller windows in their relative order", out, n, wantSingle, 3);
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
