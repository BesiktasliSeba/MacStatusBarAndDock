// common/PointerRegion.h -- where the pointer is on the iPad's own screen while another display shares it (1.8.7, the iPad 2's AirPlay B pass, row 14).
// Plain C, Mac test tools/test-pointerregion.sh.
//
// backboardd's pointer position (BKSMousePointerService -globalPointerPosition) is one space for every display the pointer moves on: each display has
// a region in it. With no other display the iPad's region is the space's origin, in the iPad's native portrait points, so its position was read as the
// iPad's own. With another display iPadOS arranges the regions by the user's arrangement (backboardd's BKPointerRegionArrangementEdge), and the iPad's
// region moves: the TV above the iPad (both iPads, read on 11 Nov) puts the iPad at x -1440..-416 on the A12Z (a 2560 x 1440 pt HDMI TV) and at
// -1080..-312 on the iPad 2 (a 960 x 540 pt AirPlay TV, 1920 x 1080 in the space), and the TV's region over 0..1024 / 0..768. Read as the iPad's own,
// every iPad position was negative and dropped as unknown (the iPad's hidden menu bar never came back by the pointer), and a TV position read as an
// iPad one. No call gives a display's region, so the iPad's is learned: a hover on the iPad's own screen gives its own point n while backboardd gives
// the global g, and the region's origin is g - n, taken only when the pointer did not move between the two (no newer hover) and two such readings agree.
// Until then, with another display attached, a global position is not read as the iPad's at all (-1: the iPad's own hover decides meanwhile).
#ifndef MSBD_POINTER_REGION_H
#define MSBD_POINTER_REGION_H
#include <math.h>
#include <string.h>

typedef struct {
    int known;          // the iPad's region origin is known: with no other display, (0, 0)
    int other;          // another display shares the pointer (its region somewhere else in the space)
    double ox, oy;      // the iPad's region origin in backboardd's space
    int cand;           // a first reading waits for a second that agrees
    double cx, cy;
} MSBDPtrRegion;

// A display came or went: with no other display, the origin (0, 0) as before 1.8.7; with one, not known until learned again.
static inline void MSBDPtrRegionReset(MSBDPtrRegion *r, int otherDisplay) {
    if (!r) return;
    memset(r, 0, sizeof *r);
    r->other = otherDisplay ? 1 : 0;
    r->known = !r->other;
}

// A reading: g, backboardd's position, and n, the iPad's own native point of the same pointer (its hover, unmoved since). Origins are whole points
// (read: -1440, -1080, 0); a reading counts when a second one agrees within a point. Returns 1 when the origin it holds changed.
static inline int MSBDPtrRegionLearn(MSBDPtrRegion *r, double gx, double gy, double nx, double ny) {
    if (!r || !r->other || !isfinite(gx) || !isfinite(gy) || !isfinite(nx) || !isfinite(ny)) return 0;
    double cx = round(gx - nx), cy = round(gy - ny);
    if (r->known && fabs(cx - r->ox) <= 1.0 && fabs(cy - r->oy) <= 1.0) { r->cand = 0; return 0; }   // (the same place, within its rounding: kept -- d23 went -1440 / -1439 / -1440 on half points)
    if (r->cand && fabs(cx - r->cx) <= 1.0 && fabs(cy - r->cy) <= 1.0) {
        int changed = !r->known || r->ox != cx || r->oy != cy;
        r->known = 1; r->ox = cx; r->oy = cy;
        r->cand = 0;
        return changed;
    }
    r->cand = 1; r->cx = cx; r->cy = cy;
    return 0;
}

// The iPad's own native point of backboardd's position g (w x h: the iPad's native size): 1 on the iPad (n set; half a point of slack at its edges,
// where its region meets another display's), 0 elsewhere (another display's, or outside the space), -1 not known yet (another display, not learned).
static inline int MSBDPtrOnIPad(const MSBDPtrRegion *r, double gx, double gy, double w, double h, double *nx, double *ny) {
    if (!r || !isfinite(gx) || !isfinite(gy)) return 0;
    if (!r->known) return r->other ? -1 : 0;
    double x = gx - r->ox, y = gy - r->oy;
    if (x < -0.5 || y < -0.5 || (w > 0 && x > w + 0.5) || (h > 0 && y > h + 0.5)) return 0;
    x = fmax(x, 0.0); y = fmax(y, 0.0);
    if (w > 0) x = fmin(x, w);
    if (h > 0) y = fmin(y, h);
    if (nx) *nx = x;
    if (ny) *ny = y;
    return 1;
}

// iPadOS's own pointer push at the iPad's bottom edge (its indirect bottom-edge pan: the Dock, then Home or the App Switcher -- with the Mac Switcher
// on, ours) that began within kMSBDPtrArrivalWindow s of the pointer's last sight on another display came from that display: one push from the TV's
// bottom over AirPlay carried on across the iPad, below it, and opened the Mac Switcher there (iPad 2, row 6.6). It opens nothing of ours.
#define kMSBDPtrArrivalWindow 1.0
static inline int MSBDPtrArrivedFromOther(double lastOtherAt, double began) {
    return lastOtherAt > 0 && began >= lastOtherAt && began - lastOtherAt < kMSBDPtrArrivalWindow;
}

#endif
