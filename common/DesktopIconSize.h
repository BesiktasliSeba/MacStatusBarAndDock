// DesktopIconSize.h -- the desktop icons' size (1.7.5 item 4, KT 31 Oct): Settings > Desktop > Icon Size, desktopIconSize in
// com.besiktasliseba.macstatusbar, in points. Never set = the size the desktop always had: the Home Screen's own app icon size (Desktop.h
// -dm_measure), followed as the Home Screen changes. Set, it is the icons' side, from 40 to 96 pt in 4 pt steps (as macOS's View Options slider,
// 16 to 512 by 4; the Home Screen's icons on our iPads, 64 to 83.5 pt, lie inside). The Home Screen's app icons never change with it.
// SpringBoard publishes the Home Screen's size it measured (notify state, quarter points) so that Settings' slider shows the size in force while
// nothing is set. Plain C: Settings (statusbar/macstatusbarprefs) and SpringBoard (statusbar/Desktop.h) share it; tools/test-desktopiconsize.sh.
#ifndef MSBD_DESKTOP_ICON_SIZE_H
#define MSBD_DESKTOP_ICON_SIZE_H
#include <math.h>

#define MSBD_DESKTOP_ICON_KEY "desktopIconSize"
#define MSBD_DESKTOP_ICON_MIN 40.0
#define MSBD_DESKTOP_ICON_MAX 96.0
#define MSBD_DESKTOP_ICON_STEP 4.0
#define MSBD_DESKTOP_ICON_FALLBACK 64.0   // (the desktop's own stand-in when no app icon of page 1 could be measured, as before)
#define MSBD_DESKTOP_HOMESIDE_STATE "com.besiktasliseba.macstatusbar.desktop.homeside"   // (notify state: the Home Screen's icon side x 4, 0 unknown)

// A stored or dragged value as the size it stands for: inside the range, on a 4 pt step. 0 for no number at all (NaN, infinite).
static inline double MSBDDesktopIconSnap(double v) {
    if (!isfinite(v)) return 0.0;
    double s = MSBD_DESKTOP_ICON_MIN + round((v - MSBD_DESKTOP_ICON_MIN) / MSBD_DESKTOP_ICON_STEP) * MSBD_DESKTOP_ICON_STEP;
    return fmin(MSBD_DESKTOP_ICON_MAX, fmax(MSBD_DESKTOP_ICON_MIN, s));
}
// The icons' side in force: the stored size (snapped) when there is one, else the Home Screen's measured side as it is (not snapped: exactly
// the size the desktop always had), else the last side used, else the stand-in.
static inline double MSBDDesktopIconSide(int stored, double storedValue, double home, double last) {
    if (stored) { double s = MSBDDesktopIconSnap(storedValue); if (s > 0.0) return s; }
    if (home > 20.0) return home;
    return last > 0.0 ? last : MSBD_DESKTOP_ICON_FALLBACK;
}
// An icon's cell (the icon with its name under it), the same formula as before 1.7.5 at every size: at least 84 pt wide (a name stays readable
// under a small icon), 30 more than the icon; the icon, 4 pt, the name's line, and margins. The grid's gaps (8 and 6, DesktopPlace.h) come on top.
static inline void MSBDDesktopIconCell(double side, double lineHeight, double *w, double *h) {
    if (w) *w = fmax(side + 30.0, 84.0);
    if (h) *h = 2.0 + side + 4.0 + ceil(lineHeight) + 2.0 + 4.0;
}
// The Home Screen's side as published (quarter points) and back.
static inline unsigned long long MSBDDesktopHomeSideState(double side) { return side > 20.0 && side < 1000.0 ? (unsigned long long)llround(side * 4.0) : 0ULL; }
static inline double MSBDDesktopHomeSideFromState(unsigned long long state) { double s = (double)state / 4.0; return s > 20.0 && s < 1000.0 ? s : 0.0; }
// What Settings' slider shows: the size in force (the stored one, else the Home Screen's as published, else the stand-in), kept inside the slider.
static inline double MSBDDesktopIconShown(int stored, double storedValue, unsigned long long homeState) {
    double s = MSBDDesktopIconSide(stored, storedValue, MSBDDesktopHomeSideFromState(homeState), 0.0);
    return fmin(MSBD_DESKTOP_ICON_MAX, fmax(MSBD_DESKTOP_ICON_MIN, s));
}
#endif
