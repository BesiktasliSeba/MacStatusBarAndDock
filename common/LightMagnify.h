// LightMagnify.h -- Magnify Traffic Lights (1.8.6, KT 10 Nov): the layout and the pick rule of the lights grown under a finger. Plain C, Mac-tested
// (tools/test-lightmagnify.sh); statusbar/LightMagnify.h draws it.
//
// A finger down on a window's red / yellow / green grows the lights into a small frosted pill with their symbols: the light under the finger the
// biggest, its neighbours less (the Dock's swell). The pill grows from the lights' own top-left (the window's corner side) to the right and down,
// never past the box it is kept in (the window or the bar it sits in): it is shifted inside that box, and made smaller if it can't fit at full size.
// A lift on a light picks it; a lift away from the pill picks nothing.
#pragma once
#include <math.h>

#define kMSBDLightMagMaxDots   3
#define kMSBDLightMagGrow      1.50   // every light at least this times its size while the pill is out
#define kMSBDLightMagSwell     0.50   // ... the one under the finger this much more (2.0 times), its neighbours less
#define kMSBDLightMagGapK      0.72   // gap between two lights, times the base size (8.6 pt at 12 pt dots)
#define kMSBDLightMagPadK      0.40   // the pill's padding round the lights, times the base size
#define kMSBDLightMagSlopK     0.90   // how far off the pill a lift still counts as on it, times the base size

typedef struct {
    int n;                                  // lights in the pill (2 when the green one is hidden)
    double cx[kMSBDLightMagMaxDots];        // each light's centre (x), in the box's coordinates
    double size[kMSBDLightMagMaxDots];      // each light's diameter
    double cy;                              // the lights' common centre (y)
    double pillX, pillY, pillW, pillH;      // the pill
    double base;                            // the base size the layout was made with (after a fit)
} MSBDLightMag;

// The swell of one light: 1 for the light under the finger, falling off with the distance in light pitches (a Gaussian, as the Dock's).
static inline double MSBDLightMagSwellAt(double distance, double pitch) {
    if (!(pitch > 0)) return 0;
    double t = distance / pitch;
    return exp(-(t * t));
}

static inline MSBDLightMag MSBDLightMagLayoutRaw(int n, double anchorX, double anchorY, double base, double fingerX, int hasFinger) {
    MSBDLightMag L; L.n = n < 1 ? 1 : (n > kMSBDLightMagMaxDots ? kMSBDLightMagMaxDots : n); L.base = base;
    double gap = base * kMSBDLightMagGapK, pad = base * kMSBDLightMagPadK;
    L.pillX = anchorX - pad; L.pillY = anchorY - pad;
    // (where each light would be at an even size: the finger's distance to it decides its swell)
    double even = base * (kMSBDLightMagGrow + kMSBDLightMagSwell * 0.5), pitch = even + gap, nominal[kMSBDLightMagMaxDots];
    for (int i = 0; i < L.n; i++) nominal[i] = L.pillX + pad + even / 2.0 + i * pitch;
    double cursor = L.pillX + pad, maxS = 0;
    for (int i = 0; i < L.n; i++) {
        double m = kMSBDLightMagGrow + (hasFinger ? kMSBDLightMagSwell * MSBDLightMagSwellAt(fabs(fingerX - nominal[i]), pitch) : kMSBDLightMagSwell * 0.3);
        L.size[i] = base * m;
        L.cx[i] = cursor + L.size[i] / 2.0;
        cursor += L.size[i] + gap;
        if (L.size[i] > maxS) maxS = L.size[i];
    }
    L.pillW = (cursor - gap + pad) - L.pillX;
    L.pillH = maxS + 2.0 * pad;
    L.cy = L.pillY + pad + maxS / 2.0;
    return L;
}

// The layout for n lights whose first one's top-left is (anchorX, anchorY) at base size `base`, the finger at fingerX (hasFinger 0: none yet),
// kept inside the box (minX, minY)-(maxX, maxY). Too big for the box: the whole pill is made smaller (never below the lights' own size: then it is
// only shifted and may be clipped by the box); then it is shifted inside the box.
static inline MSBDLightMag MSBDLightMagLayout(int n, double anchorX, double anchorY, double base, double fingerX, int hasFinger,
                                              double minX, double minY, double maxX, double maxY) {
    MSBDLightMag L = MSBDLightMagLayoutRaw(n, anchorX, anchorY, base, fingerX, hasFinger);
    double availW = maxX - minX, availH = maxY - minY, k = 1.0, pad = base * kMSBDLightMagPadK;
    double smallest = 1.0 / (kMSBDLightMagGrow + kMSBDLightMagSwell);   // (k below this would make the biggest light smaller than it is now)
    // (a smaller pill moves its lights, so the finger's swell changes a little: a few rounds until it fits; the anchor -- the top-left -- stays)
    for (int round = 0; round < 6 && availW > 0 && availH > 0 && (L.pillW > availW + 1e-9 || L.pillH > availH + 1e-9) && k > smallest; round++) {
        k *= fmin(availW / L.pillW, availH / L.pillH) * 0.999;
        if (k < smallest) k = smallest;
        L = MSBDLightMagLayoutRaw(n, anchorX - pad + pad * k, anchorY - pad + pad * k, base * k, fingerX, hasFinger);
    }
    double dx = 0, dy = 0;
    if (L.pillX + L.pillW > maxX) dx = maxX - (L.pillX + L.pillW);
    if (L.pillX + dx < minX) dx = minX - L.pillX;
    if (L.pillY + L.pillH > maxY) dy = maxY - (L.pillY + L.pillH);
    if (L.pillY + dy < minY) dy = minY - L.pillY;
    L.pillX += dx; L.pillY += dy; L.cy += dy;
    for (int i = 0; i < L.n; i++) L.cx[i] += dx;
    return L;
}

// Which light a lift at (px, py) picks: -1 off the pill (with a little slop round it), else the light whose part of the pill it is in (the parts
// split half way between two lights' edges).
static inline int MSBDLightMagPick(MSBDLightMag L, double px, double py) {
    double slop = L.base * kMSBDLightMagSlopK;
    if (px < L.pillX - slop || px > L.pillX + L.pillW + slop || py < L.pillY - slop || py > L.pillY + L.pillH + slop) return -1;
    for (int i = 0; i < L.n - 1; i++) {
        double split = ((L.cx[i] + L.size[i] / 2.0) + (L.cx[i + 1] - L.size[i + 1] / 2.0)) / 2.0;
        if (px < split) return i;
    }
    return L.n - 1;
}

// The pill follows the finger relatively (m05, the M1: a finger held on green and lifted picked yellow, since the grown lights spread to the right):
// at touch down the light under the finger (`first`, by the lights' own places) is drawn the biggest and stands for the finger; a slide moves that
// point by as much as the finger moves. The point for a finger at fingerX: the drawn centre of `first` in the layout made around it (a few rounds).
// Use: offset = MSBDLightMagVirtualX(...) - fingerX at touch down; then the layout and the pick at (finger + offset).
static inline double MSBDLightMagVirtualX(int n, int first, double anchorX, double anchorY, double base, double fingerX,
                                          double minX, double minY, double maxX, double maxY) {
    double vx = fingerX;
    if (first < 0 || first >= n) return vx;
    for (int round = 0; round < 4; round++) {
        MSBDLightMag L = MSBDLightMagLayout(n, anchorX, anchorY, base, vx, 1, minX, minY, maxX, maxY);
        vx = L.cx[first];
    }
    return vx;
}
