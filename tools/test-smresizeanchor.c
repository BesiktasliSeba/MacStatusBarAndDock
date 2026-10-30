// Mac test of statusbar/SMResizeAnchorMath.h: a window resized by a corner or side keeps its opposite corner on iPadOS 16 (SMResizeAnchor.h).
// Model of -[SBItemResizeGestureSwitcherModifier _responseForGestureUpdateAtGestureEnd:] as read on the iPad 2 (16.7.7, 29 Oct): the proposed
// width / height from the finger, the anchor and the area for resizing; the grid (our engine's: every whole point from 320 x 300, as
// -_nearestGridSizeForSize: answers); a rubber band towards the grid size; the window's centre for a size (the step's block). Run once as Apple
// has it (the window grows around its centre: what the iPad 2 showed) and once with the step given what SMResizeAnchor.h gives it.
#include <stdio.h>
#include <stdlib.h>
#include "../statusbar/SMResizeAnchorMath.h"

static int fails = 0, checks = 0;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; if (fails < 25) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } } while (0)
static bool near(double a, double b) { return fabs(a - b) < 1e-6; }

typedef struct { CGRect drawn; CGSize scene; CGPoint sceneCenter; double proposedW, proposedH; } Step;
static double rubber(double v, double target, double range) {   // (a monotone pull towards the grid size, as Apple's rubber band: at it, the value)
    double d = v - target;
    if (fabs(d) < 1e-9) return v;
    return target + (d > 0 ? 1 : -1) * range * tanh(fabs(d) / range);
}
// One step of 16.7.7's resize. frame: _initialFrameInScreenCoordinates as the step reads it; area: the area for resizing it is given.
static Step apple16(CGPoint loc, unsigned long long anchor, unsigned long long edge, CGRect frame, CGRect area, CGSize container, double padding,
                    double maxHWithDock, bool restrictionsNil, double gridW0, double gridH0, double rubberRange) {
    double cx = frame.origin.x + frame.size.width / 2, cy = frame.origin.y + frame.size.height / 2;
    double sx = area.origin.x, sy = area.origin.y, sw = area.size.width, sh = area.size.height;
    double W = frame.size.width, H = frame.size.height;
    bool L = anchor == 1, R = anchor == 2, T = false, B = false;
    if (anchor == 1) W = loc.x - sx;
    else if (anchor == 2) W = sx + sw - loc.x;
    else if (anchor == 0) {
        if (edge == 3 || edge == 5 || edge == 7) { double m = 2 * cx - loc.x; if (m > sx + sw && restrictionsNil) { R = true; m = sx + sw; } W = m - loc.x; }
        else if (edge == 4 || edge == 6 || edge == 8) { double m = 2 * cx - loc.x; if (m < sx && restrictionsNil) { L = true; m = sx; } W = loc.x - m; }
    } else { L = R = false; }
    if (edge == 1 || edge == 5 || edge == 6) { double m = 2 * cy - loc.y; if (m > sy + sh) { B = true; m = sy + sh; } H = m - loc.y; }
    else if (edge == 2 || edge == 7 || edge == 8) {
        double m = 2 * cy - loc.y; if (m < sy) { T = true; m = sy; } H = loc.y - m;
        if (frame.size.height >= container.height - 2 * padding) {   // (the full-height path, the Dock shown)
            if (H > maxHWithDock) { H = loc.y - sy; T = true; } else { cy = maxHWithDock / 2 + sy; }
        }
    }
    Step s; s.proposedW = W; s.proposedH = H;
    CGSize g = CGSizeMake(fmin(fmax(W, gridW0), container.width), fmin(fmax(H, gridH0), container.height));   // (whole points: our grid's every size)
    double dw = rubber(W, g.width, rubberRange), dh = rubber(H, g.height, rubberRange);
    CGPoint (^centerFor)(CGSize) = ^CGPoint(CGSize z) {
        return CGPointMake(L ? sx + z.width / 2 : R ? sx + sw - z.width / 2 : cx, T ? sy + z.height / 2 : B ? sy + sh - z.height / 2 : cy);
    };
    CGPoint dc = centerFor(CGSizeMake(dw, dh));
    s.drawn = CGRectMake(dc.x - dw / 2, dc.y - dh / 2, dw, dh);
    s.scene = g; s.sceneCenter = centerFor(g);
    return s;
}
// The same step for our engine: the step given SMResizeAnchor.h's anchor, frame and area; the scene's centre from MSBDResizeCenterKeeping.
static Step ours16(CGPoint loc, unsigned long long edge, CGRect start, CGRect stage, CGSize container, double padding, double maxHWithDock, bool restrictionsNil, double rr) {
    MSBDResizeFake16 f = MSBDResizeFake16For(edge, start, container.height, padding);
    CGRect area = stage;
    area.origin.x = f.areaX; area.size.width = f.areaW;
    if (f.vertical) { area.origin.y = f.areaY; area.size.height = f.areaH; }
    Step s = apple16(loc, f.anchor, edge, f.frame, area, container, padding, maxHWithDock, restrictionsNil, 320, 300, rr);
    CGPoint kept = MSBDResizeCenterKeeping(edge, start, s.scene, s.sceneCenter, f.vertical);
    CHECK(near(kept.x, s.sceneCenter.x) && near(kept.y, s.sceneCenter.y), "edge %llu: the step's own centre for the scene's size is the kept corner (%.3f,%.3f vs %.3f,%.3f)",
          edge, s.sceneCenter.x, s.sceneCenter.y, kept.x, kept.y);
    return s;
}
static double rnd(double a, double b) { return a + (b - a) * (double)random() / (double)RAND_MAX; }

int main(void) {
    srandom(29102026);
    // 1. the edge numbers and 17.5.1's anchor table (memory read on the 17.5: edges 3..8 -> 2 1 2 1 2 1)
    unsigned long long table[6] = { 2, 1, 2, 1, 2, 1 };
    for (unsigned long long e = 3; e <= 8; e++) CHECK(MSBDResizeAnchorFor(e) == table[e - 3], "anchor for edge %llu", e);
    CHECK(MSBDResizeAnchorFor(1) == 0 && MSBDResizeAnchorFor(2) == 0 && MSBDResizeAnchorFor(0) == 0 && MSBDResizeAnchorFor(9) == 0, "no anchor for top / bottom / none");
    MSBDResizeSides s5 = MSBDResizeSidesOf(5), s8 = MSBDResizeSidesOf(8), s3 = MSBDResizeSidesOf(3), s2 = MSBDResizeSidesOf(2);
    CHECK(s5.left && s5.top && !s5.right && !s5.bottom, "5 = top left");
    CHECK(s8.right && s8.bottom && !s8.left && !s8.top, "8 = bottom right");
    CHECK(s3.left && !s3.top && !s3.bottom, "3 = left");
    CHECK(s2.bottom && !s2.left && !s2.right, "2 = bottom");

    // iPad 2 landscape: container 1024 x 768, stage area under the bar and above the Dock (as our engine's), padding 10
    CGSize container = CGSizeMake(1024, 768);
    CGRect stage = CGRectMake(10, 50, 1004, 640);
    double padding = 10, maxH = 640;
    // 2. Apple's step as it is: the window grows around its centre (what the iPad 2 showed): bottom right dragged out by (60, 40)
    CGRect w = CGRectMake(300, 150, 400, 300);
    CGPoint corner = CGPointMake(700, 450);
    Step a = apple16(CGPointMake(corner.x + 60, corner.y + 40), 0, 8, w, stage, container, padding, maxH, true, 320, 300, 30);
    CHECK(near(a.sceneCenter.x, 500) && near(a.sceneCenter.y, 300), "Apple's centre stays (%.1f, %.1f)", a.sceneCenter.x, a.sceneCenter.y);
    CHECK(near(a.scene.width, 520) && near(a.scene.height, 380), "Apple's size grows twice the finger's travel (%.0f x %.0f)", a.scene.width, a.scene.height);
    CHECK(near(a.drawn.origin.x, 240) && near(a.drawn.origin.y, 110), "Apple's left and top move (%.1f, %.1f)", a.drawn.origin.x, a.drawn.origin.y);

    // 3. our step, every edge, many starts and fingers (inside, past the smallest size, past the container)
    int n = 0;
    for (int i = 0; i < 20000; i++) {
        unsigned long long edge = 1 + (unsigned long long)(random() % 8);
        double ww = rnd(320, 900), hh = rnd(300, 600);
        CGRect st = CGRectMake(rnd(10, 1014 - ww), rnd(50, 690 - hh), ww, hh);
        MSBDResizeSides sd = MSBDResizeSidesOf(edge);
        double fx = sd.left ? rnd(-200, st.origin.x + st.size.width + 100) : sd.right ? rnd(st.origin.x - 100, 1200) : rnd(0, 1024);
        double fy = sd.top ? rnd(-100, st.origin.y + st.size.height + 100) : sd.bottom ? rnd(st.origin.y - 100, 900) : rnd(0, 768);
        Step o = ours16(CGPointMake(fx, fy), edge, st, stage, container, padding, maxH, (random() & 1) != 0, 30);
        CGRect sc = CGRectMake(o.sceneCenter.x - o.scene.width / 2, o.sceneCenter.y - o.scene.height / 2, o.scene.width, o.scene.height);
        double l = st.origin.x, r = st.origin.x + st.size.width, t = st.origin.y, b = st.origin.y + st.size.height;
        // the opposite sides kept, for the scene and for the drawn frame
        if (sd.left) { CHECK(near(CGRectGetMaxX(sc), r) && near(CGRectGetMaxX(o.drawn), r), "edge %llu: right side kept (%.2f %.2f vs %.2f)", edge, CGRectGetMaxX(sc), CGRectGetMaxX(o.drawn), r);
                       CHECK(near(o.proposedW, r - fx), "edge %llu: width = finger to the right side", edge); }
        if (sd.right) { CHECK(near(sc.origin.x, l) && near(o.drawn.origin.x, l), "edge %llu: left side kept (%.2f %.2f vs %.2f)", edge, sc.origin.x, o.drawn.origin.x, l);
                        CHECK(near(o.proposedW, fx - l), "edge %llu: width = finger to the left side", edge); }
        if (sd.top) { CHECK(near(CGRectGetMaxY(sc), b) && near(CGRectGetMaxY(o.drawn), b), "edge %llu: bottom kept (%.2f vs %.2f)", edge, CGRectGetMaxY(sc), b);
                      CHECK(near(o.proposedH, b - fy), "edge %llu: height = finger to the bottom", edge); }
        if (sd.bottom) { CHECK(near(sc.origin.y, t) && near(o.drawn.origin.y, t), "edge %llu: top kept (%.2f vs %.2f)", edge, sc.origin.y, t);
                         CHECK(near(o.proposedH, fy - t), "edge %llu: height = finger to the top", edge); }
        // a side not dragged: its axis exactly as it was
        if (!sd.left && !sd.right) CHECK(near(sc.origin.x, l) && near(sc.size.width, st.size.width), "edge %llu: width untouched", edge);
        if (!sd.top && !sd.bottom) CHECK(near(sc.origin.y, t) && near(sc.size.height, st.size.height), "edge %llu: height untouched", edge);
        // the dragged side under the finger whenever the size is one the grid has (no rubber band then)
        if (sd.right && o.proposedW >= 320 && o.proposedW <= 1024) CHECK(near(CGRectGetMaxX(o.drawn), fx), "edge %llu: right side under the finger", edge);
        if (sd.left && o.proposedW >= 320 && o.proposedW <= 1024) CHECK(near(o.drawn.origin.x, fx), "edge %llu: left side under the finger", edge);
        if (sd.bottom && o.proposedH >= 300 && o.proposedH <= 768) CHECK(near(CGRectGetMaxY(o.drawn), fy), "edge %llu: bottom under the finger", edge);
        if (sd.top && o.proposedH >= 300 && o.proposedH <= 768) CHECK(near(o.drawn.origin.y, fy), "edge %llu: top under the finger", edge);
        // never smaller than the smallest window
        CHECK(o.scene.width >= 320 && o.scene.height >= 300, "edge %llu: at least 320 x 300", edge);
        n++;
    }
    // 4. in past the smallest size and back out, one drag (bottom right, then bottom left): the same frame as a drag straight there -- no lead
    for (int k = 0; k < 2; k++) {
        unsigned long long edge = k ? 7 : 8;
        CGRect st = CGRectMake(300, 150, 500, 400);
        double inX = k ? 800 - 150 : 300 + 150, outX = k ? 800 - 520 : 300 + 520;
        Step past = ours16(CGPointMake(inX, 150 + 120), edge, st, stage, container, padding, maxH, true, 30);
        CHECK(near(past.scene.width, 320) && near(past.scene.height, 300), "edge %llu: held at the smallest size past it (%.0f x %.0f)", edge, past.scene.width, past.scene.height);
        Step back = ours16(CGPointMake(outX, 150 + 450), edge, st, stage, container, padding, maxH, true, 30);
        CHECK(near(back.scene.width, 520) && near(back.scene.height, 450), "edge %llu: back out: the size the finger says (%.0f x %.0f)", edge, back.scene.width, back.scene.height);
        CHECK(near(k ? back.drawn.origin.x : CGRectGetMaxX(back.drawn), outX) && near(CGRectGetMaxY(back.drawn), 600), "edge %llu: the corner under the finger again", edge);
    }
    // 5. the grab offset (MSBDResizeGrabOffset): touched down a few points off the corner, the side keeps that distance from the finger for the
    //    whole drag -- the step is given the finger plus the offset (SMResizeAnchor.h) -- and never jumps onto the finger
    for (int i = 0; i < 5000; i++) {
        unsigned long long edge = 1 + (unsigned long long)(random() % 8);
        MSBDResizeSides sd = MSBDResizeSidesOf(edge);
        CGRect st = CGRectMake(rnd(100, 300), rnd(60, 200), rnd(400, 600), rnd(320, 450));
        double l = st.origin.x, r = l + st.size.width, t = st.origin.y, b = t + st.size.height;
        CGPoint g = CGPointMake(rnd(-25, 25), rnd(-25, 25));   // (the touch-down's distance from the side, either way)
        CGPoint down = CGPointMake((sd.left ? l : sd.right ? r : (l + r) / 2) - g.x, (sd.top ? t : sd.bottom ? b : (t + b) / 2) - g.y);
        CGPoint o = MSBDResizeGrabOffset(edge, st, down);
        CHECK(((sd.left || sd.right) ? near(o.x, g.x) : o.x == 0) && ((sd.top || sd.bottom) ? near(o.y, g.y) : o.y == 0), "edge %llu: the grab offset (%.2f, %.2f vs %.2f, %.2f)", edge, o.x, o.y, g.x, g.y);
        // at the touch-down itself the window is as it was; anywhere the size is one the grid has, the side is the finger plus the grab
        Step s0 = ours16(CGPointMake(down.x + o.x, down.y + o.y), edge, st, stage, container, padding, maxH, true, 30);
        CHECK(near(s0.scene.width, st.size.width) && near(s0.scene.height, st.size.height), "edge %llu: no jump at the touch-down (%.2f x %.2f)", edge, s0.scene.width, s0.scene.height);
        CGPoint f = CGPointMake(down.x + rnd(-60, 60), down.y + rnd(-60, 60));
        Step s1 = ours16(CGPointMake(f.x + o.x, f.y + o.y), edge, st, stage, container, padding, maxH, true, 30);
        if (sd.right && s1.proposedW >= 320) CHECK(near(CGRectGetMaxX(s1.drawn), f.x + g.x), "edge %llu: right side at finger + grab", edge);
        if (sd.left && s1.proposedW >= 320) CHECK(near(s1.drawn.origin.x, f.x + g.x), "edge %llu: left side at finger + grab", edge);
        if (sd.bottom && s1.proposedH >= 300) CHECK(near(CGRectGetMaxY(s1.drawn), f.y + g.y), "edge %llu: bottom at finger + grab", edge);
        if (sd.top && s1.proposedH >= 300) CHECK(near(s1.drawn.origin.y, f.y + g.y), "edge %llu: top at finger + grab", edge);
    }
    CHECK(MSBDResizeGrabOffset(8, CGRectMake(100, 100, 400, 300), CGPointMake(300, 200)).x == 0, "a touch-down far from the side: no offset");
    // 6. a full-height window dragged at its bottom: Apple's height (its full-height path); its width still held
    {
        CGRect tall = CGRectMake(200, 5, 500, 760);
        MSBDResizeFake16 f = MSBDResizeFake16For(8, tall, 768, 10);
        CHECK(!f.vertical && f.anchor == 1 && near(f.frame.origin.y, 5), "full-height window: bottom left to Apple");
        MSBDResizeFake16 g = MSBDResizeFake16For(6, tall, 768, 10);
        CHECK(g.vertical && near(g.frame.origin.y, 765), "full-height window: its top still held at the bottom");
        MSBDResizeFake16 h = MSBDResizeFake16For(8, CGRectMake(200, 100, 500, 400), NAN, 10);
        CHECK(!h.vertical, "unknown container: the bottom left to Apple");
    }
    printf("%s: %d checks (%d random drags), %d failed\n", fails ? "FAIL" : "PASS", checks, n, fails);
    return fails ? 1 : 0;
}
