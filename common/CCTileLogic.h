// CCTileLogic.h -- our own Control Center's Mac tiles (1.8.0 P3, plans/control-center-1.8.0.md 1.1 / 2.4 / 2.6): what each tile shows and where
// its parts go, as plain C, so the Mac test (tools/test-cctiles.c) runs this very code; statusbar/CCTiles.h draws the tiles with it. The tiles:
//   Connectivity (2 x 2): three rows -- Airplane Mode, Wi-Fi, Bluetooth --, each a round button (its switch), the name and a line under it (On /
//     Off, the network); Wi-Fi and Bluetooth with a chevron (their page);
//   Display, Sound (4 x 1): the title and a chevron (Apple's Display module expanded / our Sound page), a macOS slider under it;
//   Now Playing (4 x 1): the artwork, the title and the artist, play / pause and next.
// Sizes are Apple's grid's (the tile's frame comes from common/CCLayout.h); our text and symbols grow with Menu Bar Size's scale (1, 1.125, 1.25).
#ifndef MSBD_CC_TILE_LOGIC_H
#define MSBD_CC_TILE_LOGIC_H
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline double MSBDCCTClamp01(double v) { return isfinite(v) ? fmax(0.0, fmin(1.0, v)) : 0.0; }

// ---- the sliders (Display, Sound) ----
// A slider's track runs from x0 to x1 (its leading and trailing ends) and its knob, d across, stays inside it: the knob's centre goes from x0 + d/2
// (value 0) to x1 - d/2 (value 1), and the fill runs from x0 to the knob's trailing edge (the macOS look: the fill is never shorter than the knob).
static inline double MSBDCCTSliderKnobX(double value, double x0, double x1, double d) {
    double lo = x0 + d / 2.0, hi = x1 - d / 2.0;
    if (!(hi > lo)) return (x0 + x1) / 2.0;
    return lo + MSBDCCTClamp01(value) * (hi - lo);
}
// The value under a touch at x (a tap on the track sets it there): the inverse of the knob's place, clamped to 0...1.
static inline double MSBDCCTSliderValueAt(double x, double x0, double x1, double d) {
    double lo = x0 + d / 2.0, hi = x1 - d / 2.0;
    if (!(hi > lo) || !isfinite(x)) return 0.0;
    return MSBDCCTClamp01((x - lo) / (hi - lo));
}
// A drag moves the value by the distance moved over the knob's travel (as Apple's sliders: the knob does not jump to the finger).
static inline double MSBDCCTSliderDragged(double startValue, double dx, double x0, double x1, double d) {
    double travel = (x1 - x0) - d;
    if (!(travel > 0.0) || !isfinite(dx)) return MSBDCCTClamp01(startValue);
    return MSBDCCTClamp01(startValue + dx / travel);
}
// VoiceOver's swipe up / down (an adjustable element): one notch of `notches` (16: the volume buttons' step) up or down from the value, to the
// next notch when it lies between two, clamped.
static inline double MSBDCCTSliderStep(double value, int up, int notches) {
    if (notches < 1) notches = 16;
    double v = MSBDCCTClamp01(value) * notches;
    double at = up ? floor(v + 1e-6) + 1.0 : ceil(v - 1e-6) - 1.0;
    return MSBDCCTClamp01(at / notches);
}
// "65%": the value read aloud and in logs (rounded to whole per cent).
static inline int MSBDCCTPercent(double value) { return (int)lround(MSBDCCTClamp01(value) * 100.0); }
// The Sound slider's speaker: 0 muted (speaker.slash), 1-3 waves (speaker.wave.1 ... 3), as Apple's volume glyph grows with the level.
static inline int MSBDCCTVolumeWaves(double value) {
    double v = MSBDCCTClamp01(value);
    if (v <= 0.0001) return 0;
    return v < 1.0 / 3.0 ? 1 : v < 2.0 / 3.0 ? 2 : 3;
}

// ---- Connectivity's rows ----
// Airplane Mode first, then Wi-Fi and Bluetooth (KT 3 Nov: AirDrop out of the block, Airplane Mode in, at the top as BigSurCenter's block and
// macOS-style lists have it; AirDrop stays in Apple's Connectivity module, which a hold on the block opens expanded).
enum { kMSBDCCTRowAirplane = 0, kMSBDCCTRowWiFi = 1, kMSBDCCTRowBluetooth = 2, kMSBDCCTRows = 3 };
// Wi-Fi's and Bluetooth's rows open a page (their chevron); Airplane Mode's has none, as Apple's Connectivity module has no page for it.
static inline int MSBDCCTRowHasPage(int kind) { return kind == kMSBDCCTRowWiFi || kind == kMSBDCCTRowBluetooth; }
// A round button's colour when on: Airplane Mode's Apple's orange (its Connectivity module's own, +[UIColor systemOrangeColor]: 255,149,0 light,
// 255,159,10 dark), the others macOS's blue.
enum { kMSBDCCTTintBlue = 0, kMSBDCCTTintOrange = 1 };
static inline int MSBDCCTRowTint(int kind) { return kind == kMSBDCCTRowAirplane ? kMSBDCCTTintOrange : kMSBDCCTTintBlue; }
// What a row's second line says: Wi-Fi -- 0 "Off", 1 "Not Connected" (on, no network), 2 the network's name; Bluetooth -- 0 "Off", 1 "On",
// 3 "Unavailable" (Bluetooth's daemon not attached yet, or no Bluetooth here); Airplane Mode -- 0 "Off", 1 "On", 3 "Unavailable" (its setting
// not read yet, or not readable on this iPadOS).
static inline int MSBDCCTWiFiLine(int powered, int associated, int hasName) { return !powered ? 0 : associated && hasName ? 2 : 1; }
static inline int MSBDCCTBluetoothLine(int available, int powered) { return !available ? 3 : powered ? 1 : 0; }
static inline int MSBDCCTAirplaneLine(int known, int on) { return !known ? 3 : on ? 1 : 0; }
// The second line keeps its own size (11 pt x k) unless the names, at their share f of theirs (13 pt x k x f), got smaller than it: then it is as
// large as they are (the M1's block at Medium: the names at 0.77 of 15 pt, the lines at 0.91 of 12 -- 11.55 and 10.9 pt, not 9.2).
static inline double MSBDCCTLineFit(double f) {
    if (!isfinite(f) || f <= 0.0 || f > 1.0) f = 1.0;
    return fmin(1.0, f * 13.0 / 11.0);
}
// Where a row's parts go in the w x h block at scale k: three rows of equal height inside a 10 pt margin (top and bottom); the round button
// (28 pt x k, never taller than its row) 12 pt in at the leading side, the name and its line beside it, the chevron 8 pt in at the trailing side
// (a row without a page has none: its name takes that room too). f: the names' type size as a part of their own (MSBDCCTTextFit: the block's
// longest name fitting; the lines by MSBDCCTLineFit), the two lines kept together in the middle of the row.
typedef struct { CGRect row, circle, title, line, chevron; } MSBDCCTConnRow;
static inline void MSBDCCTConnLayout(double w, double h, double k, double f, MSBDCCTConnRow out[kMSBDCCTRows]) {
    if (!isfinite(k) || k <= 0.0) k = 1.0;
    if (!isfinite(f) || f <= 0.0 || f > 1.0) f = 1.0;
    double mx = 12.0, my = 10.0;
    double rowH = fmax(0.0, (h - 2.0 * my) / kMSBDCCTRows);
    double c = fmin(round(28.0 * k), fmax(0.0, rowH - 4.0));
    double chevW = round(8.0 * k), gap = round(8.0 * k), cm = 8.0;
    double titleH = ceil(15.0 * k * f), lineH = ceil(13.0 * k * MSBDCCTLineFit(f));
    for (int i = 0; i < kMSBDCCTRows; i++) {
        double y = my + i * rowH;
        int page = MSBDCCTRowHasPage(i);
        double tx = mx + c + gap, tw = fmax(0.0, w - tx - cm - (page ? chevW + 4.0 : 0.0));
        double ty = y + fmax(0.0, (rowH - titleH - lineH) / 2.0);
        out[i].row = CGRectMake(0, y, w, rowH);
        out[i].circle = CGRectMake(mx, y + (rowH - c) / 2.0, c, c);
        out[i].title = CGRectMake(tx, ty, tw, titleH);
        out[i].line = CGRectMake(tx, ty + titleH, tw, lineH);
        out[i].chevron = page ? CGRectMake(w - cm - chevW, y + (rowH - round(12.0 * k)) / 2.0, chevW, round(12.0 * k)) : CGRectMake(w - cm, y + rowH / 2.0, 0, 0);
    }
}
// The block's names at one type size, as macOS's lists have them: the largest part of their own size (13 pt x k) at which every name fits its
// room -- "Airplane Mode" in the M1's 142 pt block wants about 103 pt at Medium's 15 pt and has 81 --, never under kMSBDCCTTextMinFit (below
// that a label's own shrink-to-fit takes over). natural[i]: row i's name at its own size; rows: MSBDCCTConnLayout's (the rooms do not depend on f).
#define kMSBDCCTTextMinFit 0.7
static inline double MSBDCCTTextFit(const double natural[kMSBDCCTRows], const MSBDCCTConnRow rows[kMSBDCCTRows]) {
    double f = 1.0;
    for (int i = 0; i < kMSBDCCTRows; i++) if (isfinite(natural[i]) && natural[i] > 0.0) f = fmin(f, fmax(0.0, rows[i].title.size.width) / natural[i]);
    f = floor(f * 100.0) / 100.0;   // (a whole hundredth: the same size for the same names at every layout)
    return fmax(kMSBDCCTTextMinFit, fmin(1.0, f));
}

// ---- the wide tiles (Display, Sound) ----
// The title at the top leading corner, the chevron at the top trailing corner (its touch area 36 pt square or the tile's top half), the slider
// under them across the tile, 12 pt in from each side.
typedef struct { CGRect title, chevron, chevronHit, slider; } MSBDCCTWideLayout;
static inline MSBDCCTWideLayout MSBDCCTWideFrames(double w, double h, double k) {
    MSBDCCTWideLayout L;
    if (!isfinite(k) || k <= 0.0) k = 1.0;
    double m = 12.0, titleH = ceil(16.0 * k), gap = round(6.0 * k);
    double sliderH = fmin(round(24.0 * k), fmax(0.0, h - 2.0 * 8.0 - titleH - gap));   // (8 pt over and under at least: a low tile's slider gets shorter)
    double top = fmax(8.0, (h - titleH - gap - sliderH) / 2.0);
    double chev = round(9.0 * k), chevH = round(13.0 * k);
    L.title = CGRectMake(m, top, fmax(0.0, w - 2.0 * m - chev - 8.0), titleH);
    L.chevron = CGRectMake(w - m - chev, top + (titleH - chevH) / 2.0, chev, chevH);
    double hit = fmin(36.0, h / 2.0 + 6.0);
    L.chevronHit = CGRectMake(w - hit, 0, hit, hit);
    L.slider = CGRectMake(m, top + titleH + gap, fmax(0.0, w - 2.0 * m), sliderH);
    return L;
}

// ---- Now Playing (4 x 1) ----
// The artwork (square, as tall as the tile less 12 pt each side), the title and the artist beside it, play / pause and next at the trailing side
// (44 pt touch areas, symbols 20 pt x k).
typedef struct { CGRect art, title, line, play, next; } MSBDCCTNowLayout;
static inline MSBDCCTNowLayout MSBDCCTNowFrames(double w, double h, double k) {
    MSBDCCTNowLayout L;
    if (!isfinite(k) || k <= 0.0) k = 1.0;
    double m = 12.0, art = fmax(0.0, h - 2.0 * m), btn = fmin(44.0, h);
    L.art = CGRectMake(m, (h - art) / 2.0, art, art);
    L.next = CGRectMake(w - m / 2.0 - btn, (h - btn) / 2.0, btn, btn);
    L.play = CGRectMake(L.next.origin.x - btn, (h - btn) / 2.0, btn, btn);
    double tx = m + art + 10.0, tw = fmax(0.0, L.play.origin.x - 4.0 - tx);
    double titleH = ceil(16.0 * k), lineH = ceil(15.0 * k), ty = (h - titleH - lineH) / 2.0;
    L.title = CGRectMake(tx, ty, tw, titleH);
    L.line = CGRectMake(tx, ty + titleH, tw, lineH);
    return L;
}
// What its two lines say, from what Now Playing has: the title (else the app's name, else "Not Playing"), then the artist (else the album, else the
// app's name when the title took neither, else nothing). 0 nothing, 1 the title, 2 the artist, 3 the album, 4 the app, 5 "Not Playing".
static inline void MSBDCCTNowLines(int hasApp, int hasTitle, int hasArtist, int hasAlbum, int *first, int *second) {
    int f, s;
    if (!hasApp && !hasTitle) { f = 5; s = 0; }
    else if (hasTitle) { f = 1; s = hasArtist ? 2 : hasAlbum ? 3 : hasApp ? 4 : 0; }
    else { f = 4; s = hasArtist ? 2 : hasAlbum ? 3 : 0; }
    if (first) *first = f;
    if (second) *second = s;
}
#endif
