// BatteryInside.h -- the battery percentage inside the battery icon (Settings > Status Bar, 1.8.4.2, KT 8 Nov; off by default): our number on top of iPadOS's battery view
// on every iPadOS, and these rules. Plain C: tools/test-batteryinside.c runs this code.
#ifndef MSBD_BATTERY_INSIDE_H
#define MSBD_BATTERY_INSIDE_H
#include <stdio.h>

#define kMSBDBatteryInsideKey "batteryPercentInside"   // (com.besiktasliseba.macstatusbar: a boolean; never set -- the default -- is off)

static inline int MSBDBattInsidePercent(double level) {   // (level 0..1)
    if (level != level || level < 0) level = 0;
    if (level > 1) level = 1;
    return (int)(level * 100.0 + 0.5);
}
static inline void MSBDBattInsideText(double level, char *buf, size_t n) { snprintf(buf, n, "%d", MSBDBattInsidePercent(level)); }
// Shown: the switch on and iPadOS's own Battery Percentage not already beside the icon (one number, never two). Our number on top of the view also
// gives way to the charging bolt, which sits where it would go.
static inline int MSBDBattInsideShows(int on, int iosOwnShown, int ourOverlay, int boltShown) {
    if (!on || iosOwnShown) return 0;
    return !(ourOverlay && boltShown);
}
// The number over the icon's fill when the fill reaches its middle: the opposite of the icon's colour there; over the empty part, the icon's colour.
static inline int MSBDBattInsideTextIsDark(double level, int iconIsLight) {
    int overFill = level >= 0.55;
    return overFill ? iconIsLight : !iconIsLight;
}
#define MSBD_BATT_INSIDE_BODY_SHARE 0.905   // (the body's share of the view's width: the pin takes the rest)
#define MSBD_BATT_INSIDE_FONT_SHARE 0.72    // (the number's size against the body's height)
#endif
