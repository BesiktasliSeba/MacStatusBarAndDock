// CCGiveBack.h -- what our own Control Center hands back to Apple's when iPadOS's look comes back without a respring (Control Center Style Mac ->
// iPadOS while running, or BigSurCenter loaded late; 1.8.0, regression F1). Plain C, so the Mac test (tools/test-ccgiveback.c) runs this very
// code; statusbar/CCPanel.h keeps and hands back with it.
// The Mac panel changes a few things on Apple's own Control Center objects, which iPadOS's look shows too: the header's copy of the status icons
// held at alpha 0, the full-screen backdrop hidden, each adopted module's container out of Apple's grid (its place among the grid's views, its
// hidden flag, Apple's presentation values on its views). Each is kept as Apple had it when ours first replaced it -- or as Apple asked for it
// since, while ours held it -- and handed back as it was kept: iPadOS's look after a live switch is the one a start with iPadOS shows. Apple's
// iPad Control Center sets some of them once and never again by itself: the header's status bar alpha is set by -[CCUIHeaderPocketView
// initWithFrame:] (1.0) only -- just the iPhone's slide-up provider animates it (15.6.1's code) --, so a 0 left there hid iPadOS's status icons
// row until the next respring (15.6.1, 16.7.7, 17.5.1).
#ifndef MSBD_CC_GIVE_BACK_H
#define MSBD_CC_GIVE_BACK_H
#include <math.h>

typedef struct { int kept; double apple; } MSBDCCApple;   // one value of Apple's while ours replaces it: kept, and Apple's value

// Ours is about to replace it: Apple's value now is the one to hand back -- unless one is kept already (ours replaced it before: what is there
// now is ours).
static inline void MSBDCCKeepBefore(MSBDCCApple *k, double now) { if (k && !k->kept && isfinite(now)) { k->kept = 1; k->apple = now; } }
// Apple asked for a value while ours held it (ours went in its place): that one is Apple's now.
static inline void MSBDCCKeepAsked(MSBDCCApple *k, double asked) { if (k && isfinite(asked)) { k->kept = 1; k->apple = asked; } }
// iPadOS's look back: 1 and the value to set, or 0 (ours never replaced it: nothing to hand back). Handed back once: the next time ours
// replaces it, Apple's value is read again.
static inline int MSBDCCGiveBack(MSBDCCApple *k, double *out) {
    if (!k || !k->kept) return 0;
    if (out) *out = k->apple;
    k->kept = 0; k->apple = 0;
    return 1;
}
// A value Apple may set again by itself while ours held it, without telling us (a view's transform or alpha): handed back only while it is still
// the one ours set -- else it is Apple's already.
static inline int MSBDCCStillOurs(double now, double ours) { return isfinite(now) && fabs(now - ours) < 1e-6; }
// Apple's views back in Apple's order: each take keeps the views that came before it among its siblings then; put back in the reverse order of
// the takes, each goes right after the last of those that its parent holds now (prevAt: their indices there, -1 for one not there), else
// first. Exact whatever Apple added or took away meanwhile (a module removed while ours: its view is simply not there).
static inline long MSBDCCPutBackAt(const long *prevAt, long nPrev) {
    long at = 0;
    for (long i = 0; prevAt && i < nPrev; i++) if (prevAt[i] >= 0 && prevAt[i] + 1 > at) at = prevAt[i] + 1;
    return at;
}

#endif
