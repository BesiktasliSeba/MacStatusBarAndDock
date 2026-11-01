// test-displayturn.c -- Mac test of statusbar/DisplayTurn.h (1.7.7 items 2 and 3, the code review's tests): a window's scene frame turned into the
// display's space for its app and back (iPadOS 15, Aerial, landscape scenes), and the turn a still of the display needs on each panel and
// interface orientation -- both against iOS's fixed coordinate space (the display's point under a screen point, ToFixed below). Displays as on the
// iPads: the M1 (834 x 1194 points; its panel drawn landscape, interface orientation 3 up), the iPad 2 (768 x 1024; panel drawn portrait), the 17.5
// (1024 x 1366). Frames seen on the M1: Settings' and Maps' windows (1 Nov), a Bottom Half window (8fa2b25), the S1 double turn. Run by
// test-displayturn.sh.
#include <stdio.h>
#include <math.h>
#include "../statusbar/DisplayTurn.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static int sameRect(CGRect a, CGRect b) { return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(a.size.width, b.size.width) && near(a.size.height, b.size.height); }
static void Check(const char *what, int ok) { checks++; if (ok) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s\n", what); } }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if (sameRect(got, want)) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
// iOS's fixed coordinate space: the display's point (portrait, w x h) under the screen point s of a screen in interface orientation o, and back.
static CGPoint ToFixed(CGPoint s, long o, double w, double h) {
    if (o == 2) return CGPointMake(w - s.x, h - s.y);
    if (o == 3) return CGPointMake(w - s.y, s.x);
    if (o == 4) return CGPointMake(s.y, h - s.x);
    return s;
}
static CGPoint FromFixed(CGPoint p, long o, double w, double h) {
    if (o == 2) return CGPointMake(w - p.x, h - p.y);
    if (o == 3) return CGPointMake(p.y, w - p.x);
    if (o == 4) return CGPointMake(h - p.y, p.x);
    return p;
}
static const struct { const char *name; double w, h; } kDisplays[3] = { { "M1", 834, 1194 }, { "iPad 2", 768, 1024 }, { "17.5", 1024, 1366 } };

int main(void) {
    char what[256];
    // ---- a window's frame for its app: the frames seen on the M1 (landscape 3) ----
    Frame("M1, Bottom Half: {{0, 422}, {339.8, 1194}} on the screen is {{72.2, 0}, {339.8, 1194}} in the display's space (8fa2b25)",
          MSBDFrameForApp(CGRectMake(0, 422, 339.8, 1194), 3, 834, 1194), CGRectMake(72.2, 0, 339.8, 1194));
    Frame("M1, Settings' window {{131, 66}, {643, 931}} is {{125, 131}, {643, 931}} (the log, 1 Nov)", MSBDFrameForApp(CGRectMake(131, 66, 643, 931), 3, 834, 1194), CGRectMake(125, 131, 643, 931));
    Frame("M1, Maps' window {{181, 110}, {643, 931}} is {{81, 181}, {643, 931}}", MSBDFrameForApp(CGRectMake(181, 110, 643, 931), 3, 834, 1194), CGRectMake(81, 181, 643, 931));
    Frame("  ... and back on the screen", MSBDFrameOnScreen(CGRectMake(81, 181, 643, 931), 3, 834, 1194), CGRectMake(181, 110, 643, 931));
    CGRect moved = CGRectMake(191, 110, 643, 931), once = MSBDFrameForApp(moved, 3, 834, 1194), twice = MSBDFrameForApp(once, 3, 834, 1194);
    Frame("the S1 frame: {{191, 110}, {643, 931}} turned once is {{81, 191}}", once, CGRectMake(81, 191, 643, 931));
    Frame("  ... turned twice {{0, 81}} -- what Maps' scene got through the pass-on in 1.7.7's v177 (w - x - W, w - y - W)", twice, CGRectMake(0, 81, 643, 931));
    Check("  ... which is not the frame turned once (the pass-on's check sees it is not as sent: S1's loop)", !sameRect(once, twice));
    Frame("landscape 4 (the M1 turned round): {{181, 110}, {643, 931}} is {{110, 82}, {643, 931}}", MSBDFrameForApp(CGRectMake(181, 110, 643, 931), 4, 834, 1194), CGRectMake(110, 82, 643, 931));
    Frame("portrait (1) and upside down (2): as it is (not turned: landscape scenes only)", MSBDFrameForApp(CGRectMake(5, 6, 300, 400), 2, 834, 1194), CGRectMake(5, 6, 300, 400));

    // ---- for every display and orientation: back on the screen is the inverse, and a landscape window's corners are iOS's fixed space's ----
    for (int k = 0; k < 3; k++) {
        double w = kDisplays[k].w, h = kDisplays[k].h;
        for (long o = 1; o <= 4; o++) {
            int inverse = 1, corners = 1, n = 0;
            for (double x = -40; x <= h; x += 97) for (double y = -30; y <= h; y += 89) for (double fw = 60; fw <= 900; fw += 211) for (double fh = 80; fh <= 1200; fh += 263) {
                CGRect f = CGRectMake(x, y, fw, fh); n++;
                if (!sameRect(MSBDFrameOnScreen(MSBDFrameForApp(f, o, w, h), o, w, h), f) || !sameRect(MSBDFrameForApp(MSBDFrameOnScreen(f, o, w, h), o, w, h), f)) inverse = 0;
                if (o == 3 || o == 4) {   // (the window on the screen: the frame's size turned back; its corners in the display's space span the frame for the app)
                    CGRect s = CGRectMake(x, y, fh, fw), d = MSBDFrameForApp(f, o, w, h);
                    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
                    CGPoint c[4] = { s.origin, CGPointMake(CGRectGetMaxX(s), s.origin.y), CGPointMake(s.origin.x, CGRectGetMaxY(s)), CGPointMake(CGRectGetMaxX(s), CGRectGetMaxY(s)) };
                    for (int i = 0; i < 4; i++) { CGPoint p = ToFixed(c[i], o, w, h); minX = fmin(minX, p.x); minY = fmin(minY, p.y); maxX = fmax(maxX, p.x); maxY = fmax(maxY, p.y); }
                    if (!sameRect(CGRectMake(minX, minY, maxX - minX, maxY - minY), d)) corners = 0;
                }
            }
            snprintf(what, sizeof what, "%s, orientation %ld: back on the screen undoes the turn, both ways (%d frames)", kDisplays[k].name, o, n);
            Check(what, inverse);
            if (o == 3 || o == 4) { snprintf(what, sizeof what, "%s, orientation %ld: the window's corners on the screen are the frame for the app in iOS's fixed space", kDisplays[k].name, o); Check(what, corners); }
        }
    }

    // ---- the still: the picture turned onto the screen, for a panel drawn portrait (the iPad 2) and one drawn landscape, 3 up (the M1) ----
    struct { const char *name; double w, h, nativeW, nativeH; int landscapePanel; } panels[3] = {
        { "iPad 2 (panel portrait)", 768, 1024, 768, 1024, 0 }, { "M1 (panel landscape, 3 up)", 834, 1194, 1194, 834, 1 }, { "17.5 (panel portrait)", 1024, 1366, 1024, 1366, 0 } };
    for (int k = 0; k < 3; k++) {
        double w = panels[k].w, h = panels[k].h, nw = panels[k].nativeW, nh = panels[k].nativeH;
        for (long o = 1; o <= 4; o++) {
            double a = MSBDStillAngle(o, nw, nh);
            int quarter = MSBDStillQuarter(a);
            double sw = (o == 3 || o == 4) ? h : w, sh = (o == 3 || o == 4) ? w : h;   // (the screen's bounds in that orientation)
            double shownW = quarter ? nh : nw, shownH = quarter ? nw : nh;
            snprintf(what, sizeof what, "%s, orientation %ld: the picture, %s, has the screen's shape (%.0f x %.0f)", panels[k].name, o, quarter ? "turned a quarter" : "not a quarter turn", sw, sh);
            Check(what, near(shownW, sw) && near(shownH, sh));
            int lands = 1;   // every pixel where the display has it: the image's point (in iOS's fixed space as the panel draws it) on the screen's point of it
            for (double px = 0; px <= nw; px += nw / 4) for (double py = 0; py <= nh; py += nh / 4) {
                CGPoint fixed = panels[k].landscapePanel ? ToFixed(CGPointMake(px, py), 3, w, h) : CGPointMake(px, py);
                CGPoint want = FromFixed(fixed, o, w, h);
                double dx = px - nw / 2, dy = py - nh / 2;   // (UIKit's rotation about the picture's middle, set in the screen's middle)
                CGPoint got = CGPointMake(sw / 2 + dx * cos(a) - dy * sin(a), sh / 2 + dx * sin(a) + dy * cos(a));
                if (!near(got.x, want.x) || !near(got.y, want.y)) lands = 0;
            }
            snprintf(what, sizeof what, "%s, orientation %ld: turned %.0f degrees, every point of the picture lands on the screen's point of it", panels[k].name, o, a * 180 / M_PI);
            Check(what, lands);
        }
    }
    Check("the quarter-turn rule: a quarter either way is one, none and a half turn either way are not", MSBDStillQuarter(M_PI_2) && MSBDStillQuarter(-M_PI_2) && !MSBDStillQuarter(0) && !MSBDStillQuarter(M_PI) && !MSBDStillQuarter(-M_PI));
    Check("  ... and the M1 in its keyboard's landscape (3) needs no turn at all (its panel is drawn that way up)", near(MSBDStillAngle(3, 1194, 834), 0) && !MSBDStillQuarter(MSBDStillAngle(3, 1194, 834)));
    printf("%s: %d of %d checks pass\n", fails ? "test-displayturn FAILED" : "test-displayturn", checks - fails, checks);
    return fails ? 1 : 0;
}
