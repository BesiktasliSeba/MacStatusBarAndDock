// test-mswquithome.c: the Mac Switcher's view when the Home Screen comes while it is open (statusbar/MSWFlick.h MSBDMSWHomeCloses): it goes when
// the Home Screen comes by another way, and stays when the view asked for it, during a desktop switch, and when the app last in front was quit from
// the view by Swipe Up to Quit (1.8.8.4: with the Stage Manager engine a desktop's last window flicked up closed the view at once).
#include <stdio.h>
#include "../statusbar/MSWFlick.h"
static int fails = 0, n = 0;
static void check(const char *what, int got, int want) { n++; if (got != want) { fails++; printf("FAIL  %s: got %d, want %d\n", what, got, want); } else printf("PASS  %s\n", what); }
int main(void) {
    // (frontAtOpen, frontNow, switching, ownHome, lastFrontQuitHere)
    check("opened over an app, the Home gesture brings the Home Screen: the view closes", MSBDMSWHomeCloses(1, 0, 0, 0, 0), 1);
    check("opened over an app that then quits by itself: the view closes", MSBDMSWHomeCloses(1, 0, 0, 0, 0), 1);
    check("the desktop's last window (its app in front) quit from the view: the view stays (was: closed at once)", MSBDMSWHomeCloses(1, 0, 0, 0, 1), 0);
    check("a full-screen app's thumbnail quit from the view, any engine: the view stays", MSBDMSWHomeCloses(1, 0, 0, 0, 1), 0);
    check("the front window's app quit from the view, another window comes in front: the view stays", MSBDMSWHomeCloses(1, 1, 0, 0, 1), 0);
    check("a window behind quit from the view, the front app still in front: the view stays (as before)", MSBDMSWHomeCloses(1, 1, 0, 0, 0), 0);
    check("an app still in front, nothing quit: the view stays", MSBDMSWHomeCloses(1, 1, 0, 0, 0), 0);
    check("opened over the Home Screen (Aerial, Zetsu, MilkyWay4 windows; no app in front): never closed by the Home Screen", MSBDMSWHomeCloses(0, 0, 0, 0, 0), 0);
    check("opened over the Home Screen, a window quit from the view: the view stays", MSBDMSWHomeCloses(0, 0, 0, 0, 1), 0);
    check("the view sent the app Home itself (a full-screen app moved to another desktop): the view stays", MSBDMSWHomeCloses(1, 0, 0, 1, 0), 0);
    check("the view's own Home and a quit from it: the view stays", MSBDMSWHomeCloses(1, 0, 0, 1, 1), 0);
    check("a desktop switch under way (its desktop has no app in front): the view stays", MSBDMSWHomeCloses(1, 0, 1, 0, 0), 0);
    check("a desktop switch under way after a quit from the view: the view stays", MSBDMSWHomeCloses(1, 0, 1, 0, 1), 0);
    check("an app quit from the view earlier, then another app in front goes Home by the gesture: the view closes (only the app seen in front last counts)",
          MSBDMSWHomeCloses(1, 0, 0, 0, 0), 1);
    printf("test-mswquithome: %d pass, %d fail\n", n - fails, fails);
    return fails ? 1 : 0;
}
