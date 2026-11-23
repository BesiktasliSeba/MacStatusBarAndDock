// test-menustrip.c: the numbers of Scroll Menus That Don't Fit (common/MenuStrip.h, plain C), on many strips: a few titles to the most, narrow
// and wide titles, each Menu Bar Size's gap, rooms from too small to room for all. R1-R11 below; test-menustrip.sh builds it on the tree's
// common/MenuStrip.h and on made-to-fail copies of it, and runs it. The real layout with this code: test-barends.sh (S0-S8).
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "MenuStripC.h"

static int fails = 0, checks = 0;
static void check(int ok, const char *what, int strip, int f) {
    checks++;
    if (ok) return;
    if (++fails <= 30) printf("FAIL  %s (strip %d, first %d)\n", what, strip, f);
}
static unsigned seed = 12345;
static double rnd(double a, double b) { seed = seed * 1103515245u + 12345u; return a + (b - a) * ((seed >> 8) & 0xffff) / 65535.0; }
// whether the strip shown from f shows title i
static int shows(const MSBDStripIn *s, int f, int i) { MSBDStripOut o = MSBDStripAt(s, f); return i >= o.first && i < o.first + o.count; }

int main(void) {
    int strips = 0, tooSmall = 0, allFit = 0, scrolled = 0, cut = 0, firsts = 0;
    for (int t = 0; t < 40000; t++) {
        MSBDStripIn s; memset(&s, 0, sizeof s);
        s.n = 2 + (int)rnd(0, 8.99);                       // (2 to 10 titles: Edit and one of the app's, to File, Edit and eight)
        double k = t % 3 == 0 ? 1.0 : t % 3 == 1 ? 1.125 : 1.25;
        s.gap = 16.0 * k; s.chev = (t % 7 == 0 ? 6.0 : 8.0) * k; s.minShown = 30.0;
        for (int i = 0; i < s.n; i++) s.w[i] = t % 11 == 0 && i == 0 ? rnd(150, 300) : rnd(18, 90) * k;   // (now and then a first title wider than any room)
        s.start = rnd(60, 320);
        double need = 0; for (int i = 0; i < s.n; i++) need += s.w[i] + (i ? s.gap : 0);
        s.end = s.start + rnd(20, need * 1.2);
        // R10: room enough for a strip: both chevrons and a title shown at its least, and no more titles than a strip holds
        int ok = MSBDStripRoomOK(&s);
        check(ok == (s.end - s.start >= 2.0 * (s.chev + s.gap) + s.minShown), "R10 MSBDStripRoomOK: both chevrons and a title at its least", t, -1);
        if (!ok) { tooSmall++; continue; }
        strips++;
        int last = MSBDStripLastFirst(&s);
        // R1: every title fits: no strip to move, all from the start, no chevron
        if (MSBDStripAllFit(&s)) {
            allFit++;
            MSBDStripOut o = MSBDStripAt(&s, 3);
            check(last == 0 && o.first == 0 && o.count == s.n && !o.prev && !o.next, "R1 room for every title: all shown from the start, no chevron", t, 3);
            continue;
        }
        scrolled++;
        check(last >= 1 && last < s.n, "R4 the last first within the strip", t, last);
        // R4: the last first is the earliest from which the rest fits after the chevron before them
        check(MSBDStripFitsFrom(&s, last, s.start + s.chev + s.gap) || last == s.n - 1, "R4 the rest fits from the last first", t, last);
        if (last >= 2) check(!MSBDStripFitsFrom(&s, last - 1, s.start + s.chev + s.gap), "R4 the last first is the earliest", t, last);
        int seen[kMSBDStripMax]; memset(seen, 0, sizeof seen);
        for (int f = -2; f <= last + 2; f++) {
            MSBDStripOut o = MSBDStripAt(&s, f);
            int want = f < 0 ? 0 : f > last ? last : f;
            check(o.first == want, "R2 the first kept between 0 and the last first", t, f);
            if (f != want) continue;
            firsts++;
            // R2: the strip from f: the chevron before exactly when f > 0, the titles from f in order, a gap apart, whole but for a first one
            //  wider alone than the room, the chevron after exactly when titles are left, everything inside the room
            check(o.prev == (f > 0), "R2 a chevron before the titles exactly when there are titles before them", t, f);
            check(o.count >= 1, "R2 at least one title shows", t, f);
            double x = s.start;
            if (o.prev) { check(o.prevX == s.start, "R2 the chevron before them at the room's start", t, f); x += s.chev + s.gap; }
            for (int j = 0; j < o.count; j++) {
                int i = f + j;
                seen[i] = 1;
                check(o.x[j] >= x - 1e-9 && o.x[j] <= x + 1e-9, "R2 each title a gap after the item before it", t, f);
                double w = j == o.count - 1 ? o.lastW : s.w[i];
                if (j == o.count - 1 && o.lastW < s.w[i] - 1e-9) {
                    cut++;
                    check(o.count == 1 && o.lastW >= s.minShown - 1e-9, "R2 only a first title alone cut short, and never under the least", t, f);
                    check(s.w[i] > s.end - x - (o.next ? s.gap + s.chev : 0) + 1e-9, "R2 a title cut short with room for it", t, f);
                }
                x = o.x[j] + w + s.gap;
                check(o.x[j] + w <= s.end + 1e-6, "R2 a title past the room's end", t, f);
            }
            check(o.next == (f + o.count < s.n), "R2 a chevron after the titles exactly when titles are left after them", t, f);
            if (o.next) {
                check(o.nextX >= x - 1e-9 && o.nextX <= x + 1e-9, "R2 the chevron after them a gap after the last title", t, f);
                check(o.nextX + s.chev <= s.end + 1e-6, "R2 the chevron after them inside the room", t, f);
                // (as many as fit: the next title would not, with the chevron after it)
                int i = f + o.count;
                if (o.lastW >= s.w[f + o.count - 1] - 1e-9) check(x + s.w[i] > s.end - s.gap - s.chev + 1e-9 || (i == s.n - 1 && x + s.w[i] > s.end + 1e-9), "R2 a title left out that fits", t, f);
            }
            // R5: a page on: past the titles shown now (to the last first at most), and it shows the first one not shown now unless at the end
            if (f < last) {
                int p = MSBDStripPageNext(&s, f);
                check(p > f && p <= last && p <= f + o.count, "R5 a page on moves on, never past the first title not shown", t, f);
                check(p == last || p == f + o.count, "R5 a page on starts at the first title not shown", t, f);
                check(shows(&s, p, f + o.count), "R5 a page on shows the first title not shown before it", t, f);
            } else check(MSBDStripPageNext(&s, f) == last, "R5 a page on at the end stays", t, f);
            // R6: a page back: the earliest first that still shows the title before the first shown now
            if (f > 0) {
                int p = MSBDStripPagePrev(&s, f);
                check(p < f && shows(&s, p, f - 1), "R6 a page back shows the title before", t, f);
                for (int q = 0; q < p; q++) if (shows(&s, q, f - 1)) { check(0, "R6 a page back is not the earliest that shows it", t, f); break; }
            } else check(MSBDStripPagePrev(&s, f) == 0, "R6 a page back at the start stays", t, f);
            // R7: a notch: one title, kept between 0 and the last first
            check(MSBDStripStep(&s, f, 1) == (f < last ? f + 1 : last) && MSBDStripStep(&s, f, -1) == (f > 0 ? f - 1 : 0) && MSBDStripStep(&s, f, 0) == f, "R7 a notch moves one title", t, f);
            // R8: a swipe: none stays, the fingers taken one title's run on (or back) move one title, far on the last first, far back the start,
            //  further never fewer
            check(MSBDStripFirstAfterMove(&s, f, 0.0) == f, "R8 no move, no change", t, f);
            if (f < last) check(MSBDStripFirstAfterMove(&s, f, -(s.w[f] + s.gap)) == f + 1, "R8 a swipe of one title's run on moves one title on", t, f);
            if (f > 0) check(MSBDStripFirstAfterMove(&s, f, s.w[f - 1] + s.gap) == f - 1, "R8 a swipe of one title's run back moves one title back", t, f);
            check(MSBDStripFirstAfterMove(&s, f, -1e6) == last && MSBDStripFirstAfterMove(&s, f, 1e6) == 0, "R8 a long swipe ends at an end", t, f);
            int prevF = MSBDStripFirstAfterMove(&s, f, 400.0);
            for (double m = 400.0; m >= -400.0; m -= 7.0) {
                int g = MSBDStripFirstAfterMove(&s, f, m);
                if (g < prevF) { check(0, "R8 a longer swipe on moved fewer titles", t, f); break; }
                prevF = g;
            }
            // (half a title's run is where the next one takes over: under it the same first)
            if (f < last) check(MSBDStripFirstAfterMove(&s, f, -(s.w[f] + s.gap) * 0.45) == f, "R8 under half a title's run keeps the first", t, f);
            // R9: reveal: the first that shows title i, itself when i shows
            for (int i = 0; i < s.n; i++) {
                int r = MSBDStripReveal(&s, f, i);
                check(r >= 0 && r <= last && shows(&s, r, i), "R9 reveal shows the title", t, f);
                if (shows(&s, f, i)) check(r == f, "R9 reveal of a title shown keeps the strip", t, f);
            }
            check(MSBDStripReveal(&s, f, -1) == -1 && MSBDStripReveal(&s, f, s.n) == -1, "R9 reveal of no title of the strip", t, f);
        }
        // R3: every title shows from one of the firsts
        int all = 1; for (int i = 0; i < s.n; i++) all &= seen[i];
        check(all, "R3 every title reachable", t, -1);
    }
    // R11: more titles than a strip holds: no strip
    MSBDStripIn big; memset(&big, 0, sizeof big); big.n = kMSBDStripMax + 1; big.gap = 16; big.chev = 8; big.minShown = 30; big.start = 0; big.end = 2000;
    check(!MSBDStripRoomOK(&big), "R11 more titles than the strip holds: no strip", -1, -1);
    printf("%s  %d checks on %d strips with room (%d with room for every title, %d to scroll: %d firsts, %d first titles cut short) and %d without (R1-R11)\n",
           fails ? "FAIL" : "PASS", checks, strips, allFit, scrolled, firsts, cut, tooSmall);
    return fails ? 1 : 0;
}
