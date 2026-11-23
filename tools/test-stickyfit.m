// Mac test of where a sticky note is shown when its page has no clear frame of its size (1.8.8.2): common/StickyNotes.h's MSBDStickyPlaceClearFit
// and MSBDStickyTrimClear, run as written. MSBDStickyPlaceClear moves a note that lies over an app icon, a widget or the page dots to the nearest
// clear frame of its size; where there is none it kept the frame inside the area: over the icon. A device pass of 1.8.8.2's test build (iPadOS 16.7.7,
// landscape, 1024 x 768) had a note on Home Screen page 2 at 205 to 1018 (the free area's right edge) in a band between rows of icons, its left edge
// against an app icon; the Dock set at the left moved the icons 27 pt right, into the note, and it stayed under the icon at every layout after.
#import <Foundation/Foundation.h>
#include "common/StickyNotes.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)
static NSString *R(CGRect f) { return [NSString stringWithFormat:@"{%.2f, %.2f, %.2f x %.2f}", f.origin.x, f.origin.y, f.size.width, f.size.height]; }
static BOOL same(CGRect a, CGRect b) { return fabs(a.origin.x - b.origin.x) < 1e-6 && fabs(a.origin.y - b.origin.y) < 1e-6 && fabs(a.size.width - b.size.width) < 1e-6 && fabs(a.size.height - b.size.height) < 1e-6; }
static BOOL inside(CGRect f, CGRect a) { return CGRectGetMinX(f) >= CGRectGetMinX(a) - 0.001 && CGRectGetMinY(f) >= CGRectGetMinY(a) - 0.001 && CGRectGetMaxX(f) <= CGRectGetMaxX(a) + 0.001 && CGRectGetMaxY(f) <= CGRectGetMaxY(a) + 0.001; }
static const CGSize kMin = { MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H };
static CGRect Fit(CGRect f, CGRect area, const CGRect *r, int n, CGRect *anchor) { return MSBDStickyPlaceClearFit(f, area, r, n, kMin, MSBD_NOTE_CLEAR_TESTS, anchor); }
static CGRect Old(CGRect f, CGRect area, const CGRect *r, int n) { return MSBDStickyPlaceClear(f, area, r, n, MSBD_NOTE_CLEAR_TESTS, NULL); }

// The page of that pass, as -dm_occupied gives it (each icon 4 pt larger all round): six columns of icons 140 pt apart, rows 110 pt apart, the
// first column at x 124 with the Dock at the bottom (x 151 with it at the left: 27 pt right); row 1 full, row 2 one icon (the note in the rest of
// its band), rows 3 and 4 full, row 5 one icon; the page dots above where the Dock was.
static int page2(CGFloat shift, CGRect *r) {
    int n = 0;
    for (int row = 0; row < 5; row++) for (int col = 0; col < 6; col++) {
        if ((row == 1 || row == 4) && col > 0) continue;
        r[n++] = CGRectInset(CGRectMake(124 + shift + 140 * col, 36 + 110 * row, 76, 100), -4, -4);
    }
    r[n++] = CGRectInset(CGRectMake(444, 622, 136.5, 40), -4, -4);
    return n;
}

int main(void) { @autoreleasepool {
    CGRect r[40];
    CGRect areaBottom = CGRectMake(6, 24, 1012, 669), areaLeft = CGRectMake(62.5, 24, 955.5, 720);   // (the free area with the Dock at the bottom, at the left)
    CGRect note = CGRectMake(205, 141, 813, 110);
    // ---- the device's case ----
    {
        int n = page2(0, r);
        CGRect a, f = Fit(note, areaBottom, r, n, &a);
        CGRect dop = r[6];
        CHECK(same(dop, CGRectMake(120, 142, 84, 108)) && same(f, note) && same(a, note) && !MSBDStickyOverAny(f, r, n),
              "the Dock at the bottom: the note at 205 against the icon (its rect to 204) is clear at its size: kept as it is, as before %s", R(f).UTF8String);
        n = page2(27, r);
        CGRect old = Old(note, areaLeft, r, n);
        CHECK(MSBDStickyOverAny(old, r, n) && same(old, note), "the Dock at the left (the icons 27 pt right, into the note): no clear frame of its size on the page; the nearest-place rule alone keeps it UNDER the icon %s (the device's 205)", R(old).UTF8String);
        f = Fit(note, areaLeft, r, n, &a);
        CHECK(!MSBDStickyOverAny(f, r, n) && fabs(f.origin.x - 232) < 1e-6 && fabs(CGRectGetMaxX(f) - 1018) < 1e-6 && same(CGRectMake(f.origin.x, f.origin.y, 0, f.size.height), CGRectMake(232, 141, 0, 110)),
              "  ... now: shown smaller where it is, its left side pulled in to the icon's right (+1 pt, as a resize stops: B72), right edge, top and height kept %s", R(f).UTF8String);
        CHECK(same(a, note), "  ... its own size's frame is what it came from (a drop or a move stores that centre; the layout keeps the stored size)");
        CGRect again = Fit(MSBDStickyFrameAt(areaLeft, CGPointMake(CGRectGetMidX(a), CGRectGetMidY(a)), a.size), areaLeft, r, n, NULL);
        CHECK(same(again, f), "  ... laid out again from that centre and its size: the same frame (nothing moves at the next layout)");
        n = page2(0, r);
        CHECK(same(Fit(note, areaBottom, r, n, NULL), note), "  ... the Dock back at the bottom: at its full size again, where it was (nothing stored changed)");
    }
    // ---- the rule's cases ----
    {
        CGRect area = CGRectMake(0, 0, 1000, 700), one[1] = { CGRectMake(400, 300, 100, 100) };
        CHECK(same(Fit(CGRectMake(100, 100, 220, 180), area, one, 1, NULL), CGRectMake(100, 100, 220, 180)), "a note clear of everything: as it is");
        CHECK(same(Fit(CGRectMake(380, 280, 220, 180), area, one, 1, NULL), Old(CGRectMake(380, 280, 220, 180), area, one, 1)), "a note over an icon with room around: moved clear at its size, exactly as before (MSBDStickyPlaceClear)");
        CGRect wall[3] = { CGRectMake(0, 0, 1000, 100), CGRectMake(0, 300, 1000, 400), CGRectMake(700, 100, 50, 200) };   // (a band 200 tall, a block in it)
        CGRect b = CGRectMake(100, 100, 800, 200), fb = Fit(b, area, wall, 3, NULL);
        CHECK(MSBDStickyOverAny(Old(b, area, wall, 3), wall, 3) && !MSBDStickyOverAny(fb, wall, 3) && same(fb, CGRectMake(100, 100, 599, 200)), "a band with a block at its right: the right side pulled in (1 pt short), the most of the note kept %s", R(fb).UTF8String);
        CGRect tall[2] = { CGRectMake(0, 0, 1000, 100), CGRectMake(0, 600, 1000, 100) };   // (room 500 tall, the note 560)
        CGRect ft = Fit(CGRectMake(100, 120, 300, 560), area, tall, 2, NULL);
        CHECK(!MSBDStickyOverAny(ft, tall, 2) && ft.size.width == 300 && ft.size.height >= MSBD_NOTE_MIN_H && inside(ft, area), "a note taller than the room: its bottom pulled up %s", R(ft).UTF8String);
        CGRect grid[30]; int g = 0;
        for (int i = 0; i < 6; i++) for (int j = 0; j < 5; j++) grid[g++] = CGRectMake(i * 170, j * 140, 160, 130);   // (gaps of 10 pt only: no 120 x 80 anywhere)
        CGRect fg = Fit(CGRectMake(200, 200, 220, 180), area, grid, g, NULL);
        CHECK(same(fg, CGRectMake(200, 200, 220, 180)), "a page with no room even for the smallest note: kept inside the area as before (nothing better exists)");
        CGRect cramped[31]; int nc = 0;   // (icons 10 pt apart over the left 500 pt, a wall at the right: room only in a strip 140 pt wide between)
        for (int i = 0; i < 3; i++) for (int j = 0; j < 5; j++) cramped[nc++] = CGRectMake(i * 170, j * 140, 160, 130);
        cramped[nc++] = CGRectMake(640, 0, 360, 700);
        CGRect fc = CGRectMake(100, 100, 300, 200), fm = Fit(fc, area, cramped, nc, NULL);
        CHECK(MSBDStickyOverAny(Old(fc, area, cramped, nc), cramped, nc) && CGRectIsNull(MSBDStickyTrimClear(fc, cramped, nc, kMin)) && !MSBDStickyOverAny(fm, cramped, nc)
              && fm.size.width == MSBD_NOTE_MIN_W && fm.size.height == MSBD_NOTE_MIN_H && fm.origin.x >= 500 && CGRectGetMaxX(fm) <= 640 && inside(fm, area),
              "a note among icons 10 pt apart, no room of its size anywhere and none in place: the smallest size at the nearest clear place (the strip) %s", R(fm).UTF8String);
        CHECK(CGRectIsNull(MSBDStickyTrimClear(CGRectMake(100, 100, 200, 100), (CGRect[]){ CGRectMake(150, 90, 100, 120) }, 1, kMin)), "trimming that would leave less than 120 x 80: none (CGRectNull)");
        CHECK(same(MSBDStickyTrimClear(CGRectMake(100, 100, 200, 100), NULL, 0, kMin), CGRectMake(100, 100, 200, 100)), "trimming a frame that meets nothing: itself");
    }
    // ---- every page, note and place: never a regression, never under an icon when any room exists, stable ----
    {
        long cases = 0, differ = 0, over = 0, out = 0, unstable = 0, fitted = 0; char first[4][300] = {{0}};
        for (int layout = 0; layout < 4; layout++) {
            CGRect area = layout < 2 ? areaBottom : areaLeft;
            int n = page2(layout < 2 ? 0 : 27, r);
            if (layout % 2) { n = 0; for (int i = 0; i < 6; i++) for (int j = 0; j < 4; j++) if ((i + j) % 3) r[n++] = CGRectInset(CGRectMake(124 + (layout > 1 ? 27 : 0) + 140 * i, 36 + 140 * j, 76, 100), -4, -4); }
            for (int wi = 0; wi < 5; wi++) for (int xi = 0; xi <= 12; xi++) for (int yi = 0; yi <= 8; yi++) {
                CGFloat w = (CGFloat[]){ 120, 220, 380, 600, 900 }[wi], h = (CGFloat[]){ 80, 180, 110, 300, 240 }[wi];
                CGRect f = CGRectMake(area.origin.x + (area.size.width - w) * xi / 12.0, area.origin.y + (area.size.height - h) * yi / 8.0, w, h), a;
                CGRect old = Old(f, area, r, n), now = Fit(f, area, r, n, &a);
                cases++;
                if (!MSBDStickyOverAny(old, r, n)) { if (!same(old, now) && !differ++) snprintf(first[0], 300, "%s -> %s, was %s", R(f).UTF8String, R(now).UTF8String, R(old).UTF8String); continue; }
                fitted++;
                CGSize s = CGSizeMake(MIN(kMin.width, f.size.width), MIN(kMin.height, f.size.height));
                BOOL smallRoom = !MSBDStickyOverAny(Old(CGRectMake(CGRectGetMidX(f) - s.width / 2, CGRectGetMidY(f) - s.height / 2, s.width, s.height), area, r, n), r, n);
                if (MSBDStickyOverAny(now, r, n) && smallRoom && !over++) snprintf(first[1], 300, "%s -> %s", R(f).UTF8String, R(now).UTF8String);
                if ((!inside(now, area) || now.size.width > f.size.width + 1e-9 || now.size.height > f.size.height + 1e-9 || (!MSBDStickyOverAny(now, r, n) && (now.size.width < kMin.width - 1e-9 || now.size.height < kMin.height - 1e-9))) && !out++)
                    snprintf(first[2], 300, "%s -> %s", R(f).UTF8String, R(now).UTF8String);
                CGRect again = Fit(MSBDStickyFrameAt(area, CGPointMake(CGRectGetMidX(a), CGRectGetMidY(a)), f.size), area, r, n, NULL);
                if (!same(again, now) && !unstable++) snprintf(first[3], 300, "%s -> %s, again %s", R(f).UTF8String, R(now).UTF8String, R(again).UTF8String);
            }
        }
        CHECK(!differ, "every note that has a clear frame of its size: exactly the nearest-place rule's frame, as before (%ld cases; %ld differ)%s%s", cases, differ, differ ? "; first: " : "", first[0]);
        CHECK(!over && fitted > 100, "every note with no clear frame of its size (%ld): never left over an icon where even the smallest note has room (%ld over)%s%s", fitted, over, over ? "; first: " : "", first[1]);
        CHECK(!out, "  ... inside the free area, never larger than the note, at least 120 x 80 when clear (%ld wrong)%s%s", out, out ? "; first: " : "", first[2]);
        CHECK(!unstable, "  ... laid out again from its stored centre and size: the same frame (%ld unstable)%s%s", unstable, unstable ? "; first: " : "", first[3]);
    }
    printf("test-stickyfit: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
