// ZetsuReopen.h -- when an app whose Zetsu window was just closed is asked for its window again (StatusBar.x DMZetsuLaunch / DMZetsuAskWhenClosed),
// plain C so the Mac test (tools/test-zetsureopen.c) runs this very rule.
// 1.7.4 item 16 (1.7.3 R2 final regression, iPad 2 and 17.5): Zetsu's "ZetsuSwitcher" observer builds nothing for an app while the controller of
// the window just closed is still alive -- it is torn down ~0.7 s after -CloseAppWindow: --, so a reopen 0.2 s after a close showed no window at
// all (a second request later worked). The request now waits until that controller is gone (looked at every 50 ms: a weak reference taken at the
// close), at most 2 s from the close, and then goes to Zetsu as before.
#ifndef MSBD_ZETSU_REOPEN_H
#define MSBD_ZETSU_REOPEN_H

enum { MSBDZetsuAskNow = 0, MSBDZetsuWaitForClose = 1 };
#define MSBD_ZETSU_CLOSE_WAIT 2.0     // seconds from the close: asked then whatever (a controller Zetsu keeps longer never blocks for good)
#define MSBD_ZETSU_CLOSE_POLL 0.05    // seconds between looks

// closedControllerAlive: the controller of the app's window closed last is still alive (1), gone or no close seen (0); sinceClose: seconds.
static inline int MSBDZetsuReopenStep(int closedControllerAlive, double sinceClose) {
    return (closedControllerAlive && sinceClose < MSBD_ZETSU_CLOSE_WAIT) ? MSBDZetsuWaitForClose : MSBDZetsuAskNow;
}

// 1.7.4 item 18 (1.7.3 R1): a controller whose close ran (8599d01's closed mark, StatusBar.x -[ZetsuAppController setHost:]) is let through at
// -setHost: when that is Zetsu reopening the app in it: a later ask for the app (DMZetsuLaunch), the -setHost: within 1 s of that ask -- and
// only when the ask came 0.5 s or more after the close. The controller's own launch retry turns every ~0.25 s and the mark stops it at its
// first turn after the close; an ask sooner than that, after a close Zetsu made itself (the app quit or crashed during its cold start in a
// window: no item 16 wait), let that pending turn through as a "reopen" -- the closed controller went on, and went later with an observer and a
// scene monitor still registered: 8599d01's case (1.7.3 item 11, Safe Mode; 1.7.4 review). After our own close (DMZetsuClose) the ask waits for
// the controller to go (item 16), so the only ask that can still meet it is the one at the 2 s limit.
#define MSBD_ZETSU_REUSE_AFTER_ASK 1.0     // seconds: a -setHost: within this of the ask is Zetsu taking that ask
#define MSBD_ZETSU_REUSE_AFTER_CLOSE 0.5   // seconds: the ask at least this long after the close (two turns of the old retry)
// asked: an ask for the app was seen; askedAt, closedAt, now: seconds, one clock.
static inline int MSBDZetsuReusesClosed(int asked, double askedAt, double closedAt, double now) {
    return (asked && askedAt - closedAt >= MSBD_ZETSU_REUSE_AFTER_CLOSE && now - askedAt < MSBD_ZETSU_REUSE_AFTER_ASK) ? 1 : 0;
}

#endif
