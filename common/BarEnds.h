// BarEnds.h -- the menu bar's two ends never meet (1.8.8.1; the owner, 21 Nov: "Currently what happens with the app menus in status bar when ipad is
// turned to portrait, on smaller iPads especially? They don't clash with the right side right?"). Plain C, so the Mac test (tools/test-barends.sh)
// runs these very numbers. Every x is in leading coordinates (from the bar's leading edge: the left in English, the right in a right-to-left
// language; StatusBar.x DMBarRTL).
//  - The left end: the Apple logo, the traffic lights, then the menu titles (the app's name, File, Edit, the app's own menus, then ours: Go,
//    Window, Display, Audio). They keep to the bar's left half as before (the middle less 24 pt, StatusBar.x titleMaxRight: D62, the owner's to change),
//    and now also end a title gap before the right end.
//  - The right end: the status icons (iPadOS's, and ours left of them: Wi-Fi, VPN, mute, SSH), the Spotlight and Control Center icons and the
//    clock (the date, then the time). It is laid out first; the titles take the room it leaves.
//  - Room short (a narrow bar in portrait, many status icons): the date goes first, and only when the titles need its room (as a Mac's menu
//    extras give way to an app's menus), then the app's own titles from the end, ours last (AppMenus.h's room kept for ours, as before). The
//    time stays.
// The Live Activities' pills are not part of the right end here: they never start before 12 pt past the bar's middle (LiveActivities.h MSBDLARoom),
// so the titles, which end 24 pt before it, never reach them.
#ifndef MSBD_BAR_ENDS_H
#define MSBD_BAR_ENDS_H
#include <float.h>

// Where the right end starts, from one layout of it: iconsEnd -- where the status icons have to end (the Spotlight or the Control Center icon,
// or the clock with neither) --; trailLead -- where iPadOS's status icons start (none: DBL_MAX) --; regionLead -- iPadOS's items in its other
// regions in the bar's right half (none: DBL_MAX) --; ours -- the room our icons take left of those. shift: the same layout with the clock that
// much shorter (+, the date gone) or longer (-, the date back): the status icons and everything from them to the clock move with it, the other
// regions' items stay where iPadOS put them, our icons stay left of whichever starts first. shift 0: the layout's own.
static inline double MSBDBarEndLead(double iconsEnd, double trailLead, double regionLead, double ours, double shift) {
    double icons = trailLead < DBL_MAX ? trailLead + shift : DBL_MAX;
    if (regionLead < icons) icons = regionLead;
    if (icons < DBL_MAX) icons -= ours;
    double e = iconsEnd + shift;
    return icons < e ? icons : e;
}

// The end of the menu titles' room: the left half's end (halfEnd, 0 on the Lock Screen) or a title gap before the right end without the date
// (leadNoDate), whichever comes first.
static inline double MSBDBarTitlesEnd(double halfEnd, double leadNoDate, double gap) {
    double e = leadNoDate - gap;
    return e < halfEnd ? e : halfEnd;
}

// Whether the date shows: the titles, laid out in the room the right end leaves without the date (they end at titlesEnd), and a title gap still
// fit before the right end with the date (leadWithDate). shown: the date in this layout; half a point either way, so titles that end right at the
// edge do not switch the date at every layout. timeShown: the date only goes while the time shows (the clock stays).
static inline int MSBDBarDateShows(int timeShown, int shown, double titlesEnd, double leadWithDate, double gap) {
    if (!timeShown) return 1;
    double need = titlesEnd + gap;
    return shown ? need <= leadWithDate + 0.5 : need <= leadWithDate - 0.5;
}

#endif
