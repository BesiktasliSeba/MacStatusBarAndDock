// test-zetsureopen.c -- Mac test of a Zetsu reopen right after a close (statusbar/ZetsuReopen.h, used by StatusBar.x DMZetsuLaunch /
// DMZetsuAskWhenClosed): 1.7.4 item 16, a reopen 0.2 s after closing an app's Zetsu window showed no window (Zetsu builds nothing for the app
// while the closed window's controller is alive, ~0.7 s). The rule, then the wait as DMZetsuAskWhenClosed runs it (a look every 50 ms); then
// item 18's rule for a closed controller's -setHost: (MSBDZetsuReusesClosed: Zetsu's reopen, never the closed window's own pending retry); and
// 1.8.1 item 9: a new window is back at its own place only when the app had one before it opened (MSBDZetsuOpensAtOwnPlace), so a first window
// opening over another is moved off it 50 right and 44 down, as on Aerial and Stage Manager (common/WindowSize.h MSBDWindowCascadeIn).
#include <stdio.h>
#include "../statusbar/ZetsuReopen.h"
#include "../common/WindowSize.h"
static int fails = 0, checks = 0;
static void Expect(const char *what, int ok) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
// When Zetsu is asked (seconds after the close): a request at `request`, the closed controller gone at `gone` (-1: never).
static double AskedAt(double request, double gone) {
    double t = request;
    for (int i = 0; i < 1000; i++, t += MSBD_ZETSU_CLOSE_POLL) {
        int alive = gone < 0 || t < gone;
        if (MSBDZetsuReopenStep(alive, t) == MSBDZetsuAskNow) return t;
    }
    return -1;
}
int main(void) {
    Expect("no close seen (or its controller gone): asked at once", MSBDZetsuReopenStep(0, 0.2) == MSBDZetsuAskNow);
    Expect("0.2 s after a close, the closed controller still alive: waits", MSBDZetsuReopenStep(1, 0.2) == MSBDZetsuWaitForClose);
    Expect("2 s after the close, still alive (Zetsu kept it): asked all the same", MSBDZetsuReopenStep(1, 2.0) == MSBDZetsuAskNow);
    double a;
    a = AskedAt(0.2, 0.7);  printf("      reopen at 0.2 s, controller gone at 0.7 s: asked at %.2f s\n", a);
    Expect("reopen at 0.2 s (the bug's case): asked once the controller is gone (0.7 s), within one look after", a >= 0.7 - 1e-9 && a <= 0.75 + 1e-9);
    a = AskedAt(0.5, 0.7);  Expect("reopen at 0.5 s: asked at 0.7 s", a >= 0.7 - 1e-9 && a <= 0.75 + 1e-9);
    a = AskedAt(1.0, 0.7);  Expect("reopen at 1 s (gone already): asked at once", a == 1.0);
    a = AskedAt(0.2, -1);   Expect("a controller that never goes: asked at the 2 s limit, never later", a >= 2.0 - 1e-9 && a <= 2.05 + 1e-9);
    // 1.7.4 item 18 with the review's tightening: a closed controller's -setHost: is Zetsu reopening the app in it only after a later ask, made
    // 0.5 s or more after the close, and within 1 s of that ask (times in seconds, the close at 0).
    Expect("our own close, the controller kept to the 2 s limit and asked then: Zetsu's -setHost: on it 0.2 s later is the reopen", MSBDZetsuReusesClosed(1, 2.0, 0.0, 2.2) == 1);
    Expect("asked 0.6 s after the close, -setHost: 0.1 s later: the reopen", MSBDZetsuReusesClosed(1, 0.6, 0.0, 0.7) == 1);
    Expect("a close Zetsu made itself (no item 16 wait), asked 0.1 s later: the old retry's next turn at 0.25 s is NOT a reopen (1.7.3 item 11's case)", MSBDZetsuReusesClosed(1, 0.1, 0.0, 0.25) == 0);
    int leaked = 0;
    for (int i = 0; i < 10; i++) for (int j = 1; j <= 10; j++) { double ask = i * 0.05, turn = j * 0.05; if (turn > ask && MSBDZetsuReusesClosed(1, ask, 0.0, turn)) leaked++; }
    Expect("  ... no ask in the first 0.5 s lets a turn of the old retry within 0.5 s of the close through (every pair, 50 ms apart)", leaked == 0);
    Expect("-setHost: more than 1 s after the ask: not Zetsu taking that ask", MSBDZetsuReusesClosed(1, 0.6, 0.0, 1.65) == 0);
    Expect("no ask seen for the app: the mark stops it", MSBDZetsuReusesClosed(0, 0.0, 0.0, 0.3) == 0);
    Expect("an ask from before the close: the mark stops it", MSBDZetsuReusesClosed(1, -0.3, 0.0, 0.2) == 0);
    // 1.8.1 item 9: own place only with a place from before the window opened (the A12Z's F2: a new Zetsu window over another stayed on it)
    Expect("an app's first window (no place before it opened): not its own place", MSBDZetsuOpensAtOwnPlace(0, 0) == 0);
    Expect("a window that comes back where the app's window last was: its own place", MSBDZetsuOpensAtOwnPlace(0, 1) == 1);
    Expect("a frame asked for (the green light's way back, a Window menu layout): its own mark, not an own place", MSBDZetsuOpensAtOwnPlace(1, 1) == 0 && MSBDZetsuOpensAtOwnPlace(1, 0) == 0);
    {   // the M1's middle place {131, 42, 931, 667} over a window at {175, 94.8}: moved on 50 / 44 as on Aerial and Stage Manager
        CGRect desk = CGRectMake(0, 24, 1194, 740), base = CGRectMake(131, 42, 931, 667), other = CGRectMake(175, 94.8, 883, 609);
        int how = 0; CGRect f = MSBDWindowCascadeIn(base, &other, 1, desk, MSBDZetsuOpensAtOwnPlace(0, 0), &how);
        Expect("a first window opening over another is stepped off it (50 right, 44 down)", how != MSBDCascadeStays && how != MSBDCascadeOwnKept && !CGRectEqualToRect(f, base));
        f = MSBDWindowCascadeIn(base, &other, 1, desk, MSBDZetsuOpensAtOwnPlace(0, 1), &how);
        Expect("  ... a window back at its own place over another (corners apart) stays there, as before", how == MSBDCascadeOwnKept && CGRectEqualToRect(f, base));
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
