// Mac test of a sticky note's resize grips at its free area's sides (1.8.8.2 B72), and of our own windows' resize, which keeps 1.8.8.1's maths.
// The code as written: test-stickygrip.sh cuts DMNativeResized out of NativeWindow.h and makes TNoteResized (-dm_noteResize:'s frame line,
// DesktopNotes.h), TWindowResized (-dm_resize:'s, NativeWindow.h) and TSidesFor (the sides DMDockSideKept keeps out of a side Dock, StatusBar.x).
// A note: the moving side stops at the free area's side it goes to and the other side never moves, whatever the finger does (1.8.8.1: pulled past
// the area's left side, the note grew to the right). A window: its other side never moves either, during the drag and after its let go.
#import <Foundation/Foundation.h>
#include "../common/StickyNotes.h"
#include "../statusbar/WindowSnap.h"
#include "../common/DockSide.h"
#include "resized.h"
#include "noteresize.h"
#include "winresize.h"
#include "sides.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)
static const double eps = 0.001;
static NSString *R(CGRect f) { return [NSString stringWithFormat:@"{%.2f, %.2f, %.2f x %.2f}", f.origin.x, f.origin.y, f.size.width, f.size.height]; }
static BOOL near(double a, double b) { return fabs(a - b) < eps; }
static BOOL inside(CGRect f, CGRect a) {
    return CGRectGetMinX(f) >= CGRectGetMinX(a) - eps && CGRectGetMinY(f) >= CGRectGetMinY(a) - eps && CGRectGetMaxX(f) <= CGRectGetMaxX(a) + eps && CGRectGetMaxY(f) <= CGRectGetMaxY(a) + eps;
}
static BOOL rectFinite(CGRect f) { return isfinite(f.origin.x) && isfinite(f.origin.y) && isfinite(f.size.width) && isfinite(f.size.height); }

// 1.8.8.1's DMNativeResized (NativeWindow.h at the 1.8.8.1 release, as it was): the maths our windows keep, and with MSBDStickyClampInside after
// it the note's 1.8.8.1 resize, which the device pass measured.
static CGRect Resized1881(CGRect start, CGPoint d, int tag, CGSize minSize, CGRect desk) {
    CGRect f = start;
    CGFloat right = CGRectGetMaxX(start);
    if (tag == 0) f.size.width -= d.x; else f.size.width += d.x;
    f.size.width = MAX(minSize.width, MIN(f.size.width, desk.size.width));
    if (tag == 0) f.origin.x = right - f.size.width;
    f.size.height = MAX(minSize.height, MIN(start.size.height + d.y, CGRectGetMaxY(desk) - f.origin.y));
    if (CGRectGetMaxY(f) > CGRectGetMaxY(desk)) f.origin.y = MAX(CGRectGetMinY(desk), CGRectGetMaxY(desk) - f.size.height);
    return f;
}
static CGRect Note1881(CGRect start, CGPoint tr, int tag, CGRect area) {
    return MSBDStickyClampInside(Resized1881(start, tr, tag, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), area), area);
}

// The iPads' screens in points with the Dock at the bottom, at the left and at the right (a side Dock only in landscape; its strip as wide as the
// Dock is with small and with large icons).
typedef struct { const char *name; CGFloat w, h; int dock; CGFloat strip; } Screen;
static const Screen screens[] = {
    {"11-inch landscape", 1194, 834, 0, 0}, {"11-inch portrait", 834, 1194, 0, 0}, {"12.9 landscape", 1366, 1024, 0, 0}, {"12.9 portrait", 1024, 1366, 0, 0},
    {"10.2 landscape", 1080, 810, 0, 0}, {"10.2 portrait", 810, 1080, 0, 0},
    {"11-inch, the Dock at the left", 1194, 834, MSBDDockLeft, 90}, {"11-inch, a large Dock at the left", 1194, 834, MSBDDockLeft, 217},
    {"12.9, the Dock at the right", 1366, 1024, MSBDDockRight, 90}, {"11-inch, a large Dock at the right", 1194, 834, MSBDDockRight, 217},
};
#define NSCREENS ((int)(sizeof(screens) / sizeof(screens[0])))
// The desktop a native window may use (NativeWindow.h DMNativeDesktop, StatusBar.x DMUsableArea): under the menu bar, above a bottom Dock or beside
// a side Dock. A note's free area (Desktop.h -dm_area): that, 6 pt in at the sides and 4 at the top and bottom.
static CGRect usable(Screen s) {
    if (s.dock == MSBDDockLeft) return CGRectMake(s.strip, 26, s.w - s.strip, s.h - 26 - 4);
    if (s.dock == MSBDDockRight) return CGRectMake(0, 26, s.w - s.strip, s.h - 26 - 4);
    return CGRectMake(0, 26, s.w, s.h - (s.w < s.h ? 96 : 84) - 26);
}
static CGRect noteArea(Screen s) { return CGRectInset(usable(s), 6, 4); }

static const double kDX[] = {-6000, -1500, -700, -400, -214, -150, -90, -60, -17, -6, -1, 0, 1, 6, 17, 60, 90, 150, 214, 400, 700, 1500, 6000};
static const double kDY[] = {-800, -40, 0, 18, 60, 500, 6000};
#define NDX ((int)(sizeof(kDX) / sizeof(kDX[0])))
#define NDY ((int)(sizeof(kDY) / sizeof(kDY[0])))
static const double kW[] = {120, 160, 233, 323, 537, 900};
static const double kH[] = {80, 188, 400};

int main(void) { @autoreleasepool {
    const CGSize mn = CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H);

    // The device pass's own drags (1.8.8.1, an 11-inch iPad in landscape with a large Dock at the left; the check's F4):
    // (the pan's translation is the finger's travel less about 10 pt, the distance the pan takes to start; the free area's left side read 223, and
    //  217 while the finger was at the screen's very edge over the Dock)
    {
        CGRect a223 = CGRectMake(223, 30, 1188 - 223, 730.24366138811217), a217 = CGRectMake(217, 30, 1188 - 217, 730.24366138811217);
        struct { const char *what; CGRect start, area; CGPoint tr; CGRect seen; } c[] = {
            {"the left grip 100 pt left from {217, 233 wide} (right edge 450)", CGRectMake(217, 249.74366138811217, 233, 188), a223, {-90, 18}, CGRectMake(223, 249.74366138811217, 323, 206)},
            {"the left grip to the screen's edge from {223, 323 wide} (right edge 546)", CGRectMake(223, 249.74366138811217, 323, 206), a217, {-214, 0}, CGRectMake(217, 249.74366138811217, 537, 206)},
            {"the left grip 100 pt left from {217, 537 wide} (right edge 754)", CGRectMake(217, 249.74366138811217, 537, 206), a223, {-90, 0}, CGRectMake(223, 249.74366138811217, 627, 206)},
        };
        for (int i = 0; i < 3; i++) {
            CGRect old = Note1881(c[i].start, c[i].tr, 0, c[i].area);
            CHECK(near(old.origin.x, c[i].seen.origin.x) && near(old.size.width, c[i].seen.size.width) && near(old.size.height, c[i].seen.size.height),
                  "1.8.8.1's code gives the device's numbers: %s -> %s, the right edge moved %.0f pt", c[i].what, R(old).UTF8String, CGRectGetMaxX(old) - CGRectGetMaxX(c[i].start));
            CGRect f = TNoteResized(c[i].start, c[i].tr, 0, c[i].area);
            CHECK(near(CGRectGetMaxX(f), CGRectGetMaxX(c[i].start)) && near(CGRectGetMinX(f), CGRectGetMinX(c[i].area)) && inside(f, c[i].area) && near(f.size.height, c[i].seen.size.height),
                  "  ... the code as written: the note stops at the area's left side, its right edge stays at %.0f (%s)", CGRectGetMaxX(c[i].start), R(f).UTF8String);
        }
        // the same pass's drags that stay inside the area: as 1.8.8.1 (they passed there)
        CGRect st = CGRectMake(223, 249.74366138811217, 627, 206);
        CGRect f = TNoteResized(st, CGPointMake(140, 0), 0, a223);
        CHECK(CGRectEqualToRect(f, Note1881(st, CGPointMake(140, 0), 0, a223)) && near(f.origin.x, 363) && near(f.size.width, 487),
              "the left grip 150 pt right (smaller) inside the area: as 1.8.8.1, {363, 487 wide}, the right edge at 850 (%s)", R(f).UTF8String);
        st = CGRectMake(363, 249.74366138811217, 487, 206);
        f = TNoteResized(st, CGPointMake(-90, 0), 0, a223);
        CHECK(CGRectEqualToRect(f, Note1881(st, CGPointMake(-90, 0), 0, a223)) && near(f.origin.x, 273) && near(f.size.width, 577),
              "the left grip 100 pt left inside the area: as 1.8.8.1, {273, 577 wide} (%s)", R(f).UTF8String);
        st = CGRectMake(500, 250.24366138811217, 220, 180);
        f = TNoteResized(st, CGPointMake(463, 393), 1, a223);
        CHECK(CGRectEqualToRect(f, Note1881(st, CGPointMake(463, 393), 1, a223)) && near(f.size.width, 683) && near(f.size.height, 510),
              "the right grip to the screen's corner, inside the area's right side: as 1.8.8.1, 683 x 510 (%s)", R(f).UTF8String);
    }

    // The right grip past the area's right side: a Dock at the right (the finger goes on into it):
    {
        Screen s = screens[8]; CGRect area = noteArea(s);
        CGRect st = CGRectMake(900, 300, 220, 180);
        CGRect old = Note1881(st, CGPointMake(300, 0), 1, area), f = TNoteResized(st, CGPointMake(300, 0), 1, area);
        CHECK(CGRectGetMinX(old) < CGRectGetMinX(st) - 1, "1.8.8.1's code: the right grip pulled 300 pt into a right Dock grows the note to the LEFT (its left edge %.0f -> %.0f)", CGRectGetMinX(st), CGRectGetMinX(old));
        CHECK(near(CGRectGetMinX(f), CGRectGetMinX(st)) && near(CGRectGetMaxX(f), CGRectGetMaxX(area)) && inside(f, area),
              "  ... the code as written: it stops at the area's right side (%.0f), the left edge stays at %.0f (%s)", CGRectGetMaxX(area), CGRectGetMinX(st), R(f).UTF8String);
    }

    // A note: every grip, start, finger and screen:
    {
        long n = 0, otherSide = 0, outside = 0, follows = 0, heightKept = 0, asBefore = 0, asBeforeN = 0, bad = 0;
        char first[6][400] = {{0}};
        for (int si = 0; si < NSCREENS; si++) {
            CGRect area = noteArea(screens[si]);
            for (int wi = 0; wi < 6; wi++) for (int hi = 0; hi < 3; hi++) {
                CGFloat w = MIN(kW[wi], area.size.width), h = MIN(kH[hi], area.size.height);
                for (int xi = 0; xi <= 8; xi++) for (int yi = 0; yi <= 2; yi++) {
                    CGRect st = CGRectMake(CGRectGetMinX(area) + (area.size.width - w) * xi / 8.0, CGRectGetMinY(area) + (area.size.height - h) * yi / 2.0, w, h);
                    for (int tag = 0; tag < 2; tag++) for (int di = 0; di < NDX; di++) for (int dj = 0; dj < NDY; dj++) {
                        CGPoint tr = CGPointMake(kDX[di], kDY[dj]);
                        CGRect f = TNoteResized(st, tr, tag, area), old = Note1881(st, tr, tag, area);
                        n++;
                        // (the case in words, made only for the first wrong one of each check)
                        #define WHY(k, extra) snprintf(first[k], 400, "%s, %s grip, start %s, translation (%.0f, %.0f): %s%s", screens[si].name, tag ? "right" : "left", R(st).UTF8String, tr.x, tr.y, R(f).UTF8String, extra)
                        if (!rectFinite(f)) { if (!bad++) WHY(5, ""); continue; }
                        if (!(tag == 0 ? near(CGRectGetMaxX(f), CGRectGetMaxX(st)) : near(CGRectGetMinX(f), CGRectGetMinX(st)))) { if (!otherSide++) WHY(0, ""); }
                        if (!inside(f, area) || f.size.width < MSBD_NOTE_MIN_W - eps || f.size.height < MSBD_NOTE_MIN_H - eps) { if (!outside++) WHY(1, ""); }
                        double want = tag == 0 ? MAX(MSBD_NOTE_MIN_W, MIN(st.size.width - tr.x, CGRectGetMaxX(st) - CGRectGetMinX(area)))
                                               : MAX(MSBD_NOTE_MIN_W, MIN(st.size.width + tr.x, CGRectGetMaxX(area) - CGRectGetMinX(st)));
                        if (!near(f.size.width, want)) { if (!follows++) WHY(2, ([NSString stringWithFormat:@" (width %.2f wanted)", want].UTF8String)); }
                        if (!near(f.origin.y, old.origin.y) || !near(f.size.height, old.size.height)) { if (!heightKept++) WHY(3, ([NSString stringWithFormat:@" (1.8.8.1 %@)", R(old)].UTF8String)); }
                        CGRect raw = Resized1881(st, tr, tag, mn, area);
                        if (CGRectGetMinX(raw) >= CGRectGetMinX(area) - eps && CGRectGetMaxX(raw) <= CGRectGetMaxX(area) + eps) {
                            asBeforeN++;
                            if (!CGRectEqualToRect(f, old)) { if (!asBefore++) WHY(4, ([NSString stringWithFormat:@" (1.8.8.1 %@)", R(old)].UTF8String)); }
                        }
                        #undef WHY
                    }
                }
            }
        }
        CHECK(!bad, "a note: every frame finite (%ld cases)%s%s", n, bad ? "; first: " : "", bad ? first[5] : "");
        CHECK(!otherSide, "a note: the grip's other side never moves, the left grip keeps the right edge and the right grip the left edge, on every screen and Dock (%ld cases; %ld wrong)%s%s", n, otherSide, otherSide ? "; first: " : "", otherSide ? first[0] : "");
        CHECK(!outside, "a note: always inside the free area, never under 120 x 80 (%ld cases; %ld wrong)%s%s", n, outside, outside ? "; first: " : "", outside ? first[1] : "");
        CHECK(!follows, "a note: the moving side follows the finger to the area's side and stops there, or at the minimum (%ld cases; %ld wrong)%s%s", n, follows, follows ? "; first: " : "", follows ? first[2] : "");
        CHECK(!heightKept, "a note: the height and the top as 1.8.8.1's (the bottom rule unchanged) (%ld cases; %ld wrong)%s%s", n, heightKept, heightKept ? "; first: " : "", heightKept ? first[3] : "");
        CHECK(!asBefore && asBeforeN > 1000, "a note: a drag that keeps the moving side inside the area gives 1.8.8.1's frame exactly (%ld such cases; %ld differ)%s%s", asBeforeN, asBefore, asBefore ? "; first: " : "", asBefore ? first[4] : "");
    }

    // A note whose start is outside the area (the area changed during the drag: a turn, the Dock moved):
    {
        CGRect area = CGRectMake(96, 30, 1092, 716);
        CGRect starts[] = {CGRectMake(20, 300, 150, 100), CGRectMake(1150, 300, 150, 100), CGRectMake(40, 300, 1200, 100), CGRectMake(500, 700, 220, 180)};
        BOOL ok = YES; NSString *seen = @"";
        for (int i = 0; i < 4; i++) for (int tag = 0; tag < 2; tag++) for (int di = 0; di < NDX; di++) {
            CGRect f = TNoteResized(starts[i], CGPointMake(kDX[di], 30), tag, area);
            if (!rectFinite(f) || !inside(f, area) || f.size.width < MSBD_NOTE_MIN_W - eps || f.size.height < MSBD_NOTE_MIN_H - eps) { ok = NO; seen = R(f); }
        }
        CHECK(ok, "a note started outside the area: finite, inside it, at least the minimum (%s)", seen.length ? seen.UTF8String : "every case");
    }

    // A native window: 1.8.8.1's maths, byte for byte:
    {
        long n = 0, diff = 0; char first[400] = {0};
        for (int si = 0; si < NSCREENS; si++) {
            CGRect desk = usable(screens[si]);
            CGSize wmn = CGSizeMake(320, 220);
            for (int wi = 0; wi < 6; wi++) for (int hi = 0; hi < 3; hi++) {
                CGFloat w = MAX(wmn.width, kW[wi] * 1.3), h = MAX(wmn.height, kH[hi] * 1.5);
                for (int xi = -2; xi <= 10; xi++) {   // (a window may lie partly off the screen: all but 80 pt of it, DMNativeClamp)
                    CGRect st = CGRectMake(CGRectGetMinX(desk) - w + 80 + (desk.size.width + w - 160) * (xi + 2) / 12.0, CGRectGetMinY(desk) + 40, w, h);
                    for (int tag = 0; tag < 2; tag++) for (int di = 0; di < NDX; di++) for (int dj = 0; dj < NDY; dj++) {
                        CGPoint d = CGPointMake(kDX[di], kDY[dj]);
                        CGRect f = TWindowResized(st, d, tag, wmn, desk), ref = Resized1881(st, d, tag, wmn, desk);
                        n++;
                        if (memcmp(&f, &ref, sizeof f) != 0 && !diff++) snprintf(first, 400, "%s, %s grip, start %s, d (%.0f, %.0f): %s, 1.8.8.1 %s", screens[si].name, tag ? "right" : "left", R(st).UTF8String, d.x, d.y, R(f).UTF8String, R(ref).UTF8String);
                    }
                }
            }
        }
        CHECK(!diff && n > 10000, "a native window's resize is 1.8.8.1's, bit for bit, on every screen and Dock, also partly off the screen (%ld cases; %ld differ)%s%s", n, diff, diff ? "; first: " : "", diff ? first : "");
    }

    // A native window does not have B72's fault: its other side never moves, during the drag and after its let go:
    {
        long n = 0, during = 0, after = 0, reach = 0, reachN = 0; char f0[400] = {0}, f1[400] = {0}, f2[400] = {0};
        const double grip = 22.0 / 2.0 + 6.0;   // (test-stickygrip.sh: a grip's touch area reaches 17 pt past the window's side)
        for (int si = 0; si < NSCREENS; si++) {
            Screen s = screens[si]; CGRect desk = usable(s);
            CGSize wmn = CGSizeMake(320, 220);
            for (int wi = 0; wi < 4; wi++) {
                CGFloat w = MAX(wmn.width, kW[wi] * 1.5);
                for (int xi = 0; xi <= 8; xi++) {   // (a window inside the desktop)
                    CGRect st = CGRectMake(CGRectGetMinX(desk) + (desk.size.width - w) * xi / 8.0, CGRectGetMinY(desk) + 60, w, 300);
                    for (int tag = 0; tag < 2; tag++) for (int di = 0; di < NDX; di++) {
                        CGPoint d = CGPointMake(kDX[di], 0);
                        CGRect f = TWindowResized(st, d, tag, wmn, desk);
                        n++;
                        BOOL kept = tag == 0 ? near(CGRectGetMaxX(f), CGRectGetMaxX(st)) : near(CGRectGetMinX(f), CGRectGetMinX(st));
                        if (!kept && !during++) snprintf(f0, 400, "%s, %s grip, start %s, d %.0f: %s", s.name, tag ? "right" : "left", R(st).UTF8String, d.x, R(f).UTF8String);
                        // let go (-dm_keepOutOfSideDock: -> DMDockSideKept): a side Dock keeps the moved side and the bottom out; with the Dock at the bottom nothing
                        unsigned how = (tag == 0 ? MSBDSnapLeft : MSBDSnapRight) | MSBDSnapBottom;
                        CGRect g = s.dock ? MSBDDockSideKeepOut(f, desk, TSidesFor(how)) : f;
                        BOOL keptAfter = tag == 0 ? near(CGRectGetMaxX(g), CGRectGetMaxX(st)) : near(CGRectGetMinX(g), CGRectGetMinX(st));
                        BOOL out = !s.dock || (CGRectGetMinX(g) >= CGRectGetMinX(desk) - eps && CGRectGetMaxX(g) <= CGRectGetMaxX(desk) + eps);
                        if ((!keptAfter || !out) && !after++) snprintf(f1, 400, "%s, %s grip, start %s, d %.0f: let go at %s -> %s", s.name, tag ? "right" : "left", R(st).UTF8String, d.x, R(f).UTF8String, R(g).UTF8String);
                        // with the Dock at the bottom: a finger that stays on the screen takes the moved side at most the grip's reach past the screen's side
                        if (!s.dock) for (double t = -5; t <= 17; t += 11) {
                            double from = tag == 0 ? CGRectGetMinX(st) + t : CGRectGetMaxX(st) - t, to = tag == 0 ? 0 : s.w;
                            CGRect e = TWindowResized(st, CGPointMake(to - from, 0), tag, wmn, desk);
                            reachN++;
                            double past = tag == 0 ? -CGRectGetMinX(e) : CGRectGetMaxX(e) - s.w;
                            if (past > grip + eps && !reach++) snprintf(f2, 400, "%s, %s grip, start %s: %s, %.1f pt past", s.name, tag ? "right" : "left", R(st).UTF8String, R(e).UTF8String, past);
                        }
                    }
                }
            }
        }
        CHECK(!during, "a native window: while it is dragged the grip's other side never moves (%ld cases; %ld wrong)%s%s", n, during, during ? "; first: " : "", during ? f0 : "");
        CHECK(!after, "a native window: let go under a side Dock, the moved side comes out to the desktop's side and the other side stays (%ld cases; %ld wrong)%s%s", n, after, after ? "; first: " : "", after ? f1 : "");
        CHECK(!reach && reachN > 100, "a native window with the Dock at the bottom: a finger on the screen takes the moved side at most 17 pt past the screen's side (%ld cases; %ld past)%s%s", reachN, reach, reach ? "; first: " : "", reach ? f2 : "");
    }

    printf("test-stickygrip: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
