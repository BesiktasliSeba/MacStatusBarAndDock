// Mac test of a sticky note's resize against the page's app icons, widgets and page dots (1.8.8.2 B72 full fix, B83's corner findings).
// test-stickyclear.sh makes TNoteResized from -dm_noteResize:'s frame lines as written (DMNativeResized, then, where the source has it, the stop at
// the occupied rects). The let go is the layout's own rule: the note stored as its centre's share and its rounded size, then MSBDStickyFrameAt
// and MSBDStickyPlaceClear (DesktopNotes.h -dm_noteLayoutIn:), which moves a note that lies over a rect to the nearest clear place, carrying its
// size. The device passes saw that move: a note's right edge moved when the left grip went into the app icons' columns (B72), a note
// jumped up off the page dots or slid sideways after a corner drag to the area's bottom (B83).
#import <Foundation/Foundation.h>
#include "common/StickyNotes.h"
#include "resized.h"
#include "noteresize.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; printf("PASS  "); } else { fails++; printf("FAIL  "); } printf(__VA_ARGS__); printf("\n"); } while (0)
static NSString *R(CGRect f) { return [NSString stringWithFormat:@"{%.2f, %.2f, %.2f x %.2f}", f.origin.x, f.origin.y, f.size.width, f.size.height]; }
static BOOL near(double a, double b, double e) { return fabs(a - b) < e; }
static BOOL inside(CGRect f, CGRect a) { return CGRectGetMinX(f) >= CGRectGetMinX(a) - 0.001 && CGRectGetMinY(f) >= CGRectGetMinY(a) - 0.001 && CGRectGetMaxX(f) <= CGRectGetMaxX(a) + 0.001 && CGRectGetMaxY(f) <= CGRectGetMaxY(a) + 0.001; }
static int overCount(CGRect f, const CGRect *r, int n) { int c = 0; for (int k = 0; k < n; k++) if (MSBDStickyRectsOverlap(f, r[k])) c++; return c; }
static CGRect Note(CGRect start, CGPoint tr, int tag, CGRect area, const CGRect *r, int n) { return TNoteResized(start, tr, tag, area, r, n); }
static CGRect NoteNoRects(CGRect start, CGPoint tr, int tag, CGRect area) { return TNoteResized(start, tr, tag, area, NULL, 0); }
// -dm_noteResize:'s let go and the layout pass after it (the Dock at the bottom: the places area is the free area)
static CGRect Stored(CGRect f, CGRect area) {
    double fx = MAX(0.0, MIN(1.0, (CGRectGetMidX(f) - area.origin.x) / MAX(1.0, area.size.width))), fy = MAX(0.0, MIN(1.0, (CGRectGetMidY(f) - area.origin.y) / MAX(1.0, area.size.height)));
#ifdef T_HAS_CLEAR
    CGSize z = f.size;   // (the size as shown)
#else
    CGSize z = CGSizeMake(round(f.size.width), round(f.size.height));   // (1.8.8.1.1 stored it rounded)
#endif
    return MSBDStickyFrameAt(area, CGPointMake(area.origin.x + fx * area.size.width, area.origin.y + fy * area.size.height), z);
}
#ifdef T_HAS_FIT
static CGRect LetGo(CGRect f, CGRect area, const CGRect *r, int n) { return MSBDStickyPlaceClearFit(Stored(f, area), area, r, n, CGSizeMake(MSBD_NOTE_MIN_W, MSBD_NOTE_MIN_H), MSBD_NOTE_CLEAR_TESTS, NULL); }
#else
static CGRect LetGo(CGRect f, CGRect area, const CGRect *r, int n) { return MSBDStickyPlaceClear(Stored(f, area), area, r, n, MSBD_NOTE_CLEAR_TESTS, NULL); }
#endif

typedef struct { const char *name; CGFloat w, h; } Screen;
static const Screen screens[] = { {"11-inch landscape", 1194, 834}, {"11-inch portrait", 834, 1194}, {"12.9 landscape", 1366, 1024}, {"12.9 portrait", 1024, 1366},
                                  {"10.2 landscape", 1080, 810}, {"10.2 portrait", 810, 1080} };
#define NSCREENS ((int)(sizeof(screens) / sizeof(screens[0])))
static CGRect areaOf(Screen s) { return CGRectInset(CGRectMake(0, 26, s.w, s.h - (s.w < s.h ? 96 : 84) - 26), 6, 4); }
// a page of app icons in a grid (as test-stickynotes' page 1), a widget, and the page dots above the Dock -- each a little larger, as -dm_occupied
static int pageRects(Screen s, CGRect area, CGRect *out, int apps, BOOL widget) {
    int n = 0, cols = s.w > s.h ? 6 : 4, rows = s.w > s.h ? 4 : 6;
    CGFloat mx = s.w < s.h ? 70 : 110, my = 50, stepX = (s.w - 2 * mx - 84) / (cols - 1), stepY = (CGRectGetMaxY(area) - 60 - my - 100) / (rows - 1);
    for (int i = 0; i < apps && i < cols * rows; i++) out[n++] = CGRectInset(CGRectMake(mx + (i % cols) * stepX, my + (i / cols) * stepY, 84, 100), -4, -4);
    if (widget) out[n++] = CGRectInset(CGRectMake(s.w - mx - 340, my + 2 * stepY, 340, 160), -4, -4);
    out[n++] = CGRectInset(CGRectMake(s.w / 2 - 68, CGRectGetMaxY(area) - 40, 136.5, 40), -4, -4);   // (the page dots)
    return n;
}

int main(void) { @autoreleasepool {
#ifndef T_HAS_CLEAR
    printf("NOTE  -dm_noteResize: has no stop at the occupied rects here (1.8.8.1.1's code): the checks below show what that does\n");
#endif
    // ---- an 11-inch iPad (landscape, the Dock at the bottom; B72): app icons in the two left columns, up to x 219 ----
    {
        CGRect area = CGRectMake(6, 34, 1182, 726), r[16]; int n = 0;
        for (int row = 0; row < 4; row++) for (int col = 0; col < 2; col++) r[n++] = CGRectMake(col ? 134 : 40, 60 + row * 170, 85, 112);   // (up to 219: 134 + 85)
        r[n++] = CGRectMake(529, 716, 136.5, 48);   // (the page dots)
        // The probe: from left 225, a 30 pt pull ended at left 219 with the right edge 625 -> 649 (1.8.8.1.1). The layout's 8 pt rings give exactly that.
        CGRect st = CGRectMake(225, 300, 400, 200);
        CGRect old = NoteNoRects(st, CGPointMake(-30, 0), 0, area), oldGo = LetGo(old, area, r, n);
        CHECK(near(CGRectGetMinX(oldGo), 219, 0.01) && near(CGRectGetMaxX(oldGo), 649, 0.01), "1.8.8.1.1's chain gives the device's numbers: left 225 pulled 30 pt into the icons, let go at %s (left 219, right 625 -> 649)", R(oldGo).UTF8String);
        CGRect f = Note(st, CGPointMake(-30, 0), 0, area, r, n), go = LetGo(f, area, r, n);
        CHECK(near(CGRectGetMaxX(f), 625, 0.001) && near(CGRectGetMinX(f), 220, 0.001) && !overCount(f, r, n), "the code as written: the left grip stops 1 pt short of the icons' edge (left 220), the right edge stays at 625 (%s)", R(f).UTF8String);
        CHECK(near(CGRectGetMaxX(go), 625, 0.001) && near(CGRectGetMinX(go), CGRectGetMinX(f), 0.001) && near(go.origin.y, f.origin.y, 0.001), "  ... and the let go leaves it there: %s (was %s)", R(go).UTF8String, R(f).UTF8String);
        // R1 (b): the left grip to the screen's very edge (x 2)
        st = CGRectMake(300, 280, 233, 188);
        f = Note(st, CGPointMake(-298, 40), 0, area, r, n); go = LetGo(f, area, r, n);
        old = NoteNoRects(st, CGPointMake(-298, 40), 0, area); oldGo = LetGo(old, area, r, n);
        CHECK(CGRectGetMaxX(oldGo) > CGRectGetMaxX(st) + 100, "1.8.8.1.1's chain: the left grip to x 2 moves the right edge %.0f -> %.0f at the let go", CGRectGetMaxX(st), CGRectGetMaxX(oldGo));
        CHECK(near(CGRectGetMaxX(f), CGRectGetMaxX(st), 0.001) && near(CGRectGetMinX(f), 220, 0.001) && near(f.size.height, 228, 0.001) && near(CGRectGetMaxX(go), CGRectGetMaxX(st), 0.001) && !overCount(go, r, n),
              "the code as written: the left grip to x 2 stops at 220, the right edge stays at %.0f, through the let go (%s, then %s)", CGRectGetMaxX(st), R(f).UTF8String, R(go).UTF8String);
        // inside the free space right of the icons: 1.8.8.1.1's frame bit for bit
        st = CGRectMake(400, 200, 300, 200);
        CGPoint trs[] = {{-150, 0}, {-60, 80}, {200, 100}, {-20, -60}};
        BOOL same = YES;
        for (int i = 0; i < 4; i++) for (int tag = 0; tag < 2; tag++) { CGRect a = Note(st, trs[i], tag, area, r, n), b = NoteNoRects(st, trs[i], tag, area); if (memcmp(&a, &b, sizeof a)) same = NO; }
        CHECK(same, "drags that stay clear of every icon: the frame is 1.8.8.1.1's, bit for bit");
    }
    // ---- the 11-inch iPad with a large Dock at the LEFT (B72): the icons' edge at ~264 ----
    {
        CGRect area = CGRectMake(59.8, 30, 1128.2, 800), r[8]; int n = 0;
        for (int row = 0; row < 4; row++) r[n++] = CGRectMake(179, 60 + row * 170, 85, 112);
        CGRect st = CGRectMake(300, 300, 389, 200), f = Note(st, CGPointMake(-400, 0), 0, area, r, n), go = LetGo(f, area, r, n);
        CHECK(near(CGRectGetMinX(f), 265, 0.001) && near(CGRectGetMaxX(f), 689, 0.001) && near(CGRectGetMaxX(go), 689, 0.001), "the left grip into a left Dock stops at the icons' edge (265), the right edge 689 kept through the let go (%s)", R(go).UTF8String);
    }
    // ---- B83 (a 12.9-inch iPad in landscape): a corner dragged to the area's bottom over the page dots ----
    {
        Screen s = screens[2]; CGRect area = areaOf(s);
        CGRect dots = CGRectInset(CGRectMake(s.w / 2 - 68, CGRectGetMaxY(area) - 40, 136.5, 40), -4, -4), r[1] = {dots};
        CGRect st = CGRectMake(560, 500, 300, 200);
        CGRect old = NoteNoRects(st, CGPointMake(40, 600), 1, area), oldGo = LetGo(old, area, r, 1);
        CHECK(oldGo.origin.y < old.origin.y - 20 && near(oldGo.size.height, old.size.height, 0.6), "1.8.8.1.1's chain: the right corner to the area's bottom over the page dots jumps %.0f pt up at the let go, height kept (B83)", old.origin.y - oldGo.origin.y);
        CGRect f = Note(st, CGPointMake(40, 600), 1, area, r, 1), go = LetGo(f, area, r, 1);
        CHECK(near(f.origin.x, 560, 0.001) && near(f.origin.y, 500, 0.001) && near(CGRectGetMaxY(f), CGRectGetMinY(dots) - 1, 0.001) && near(f.size.width, 340, 0.001), "the code as written: the bottom stops 1 pt above the page dots, the top and the left edge stay (%s)", R(f).UTF8String);
        CHECK(near(go.origin.y, f.origin.y, 0.001) && near(go.origin.x, f.origin.x, 0.001) && !overCount(go, r, 1), "  ... and the let go leaves it there (%s)", R(go).UTF8String);
        // the nearest clear place sideways: it slid left, as if the left grip had been pulled (the one landscape corner drag seen)
        st = CGRectMake(400, 500, 216, 200);
        old = NoteNoRects(st, CGPointMake(30, 600), 1, area); oldGo = LetGo(old, area, r, 1);
        CHECK(CGRectGetMinX(oldGo) < CGRectGetMinX(st) - 20 && CGRectGetMaxX(oldGo) < CGRectGetMaxX(old) - 20, "1.8.8.1.1's chain: the RIGHT corner dragged down past the page dots' end, let go: the note slides left (left edge %.0f -> %.0f) as if the left grip was pulled", CGRectGetMinX(st), CGRectGetMinX(oldGo));
        f = Note(st, CGPointMake(30, 600), 1, area, r, 1); go = LetGo(f, area, r, 1);
        CHECK(near(CGRectGetMinX(f), 400, 0.001) && near(f.size.width, 246, 0.001) && near(CGRectGetMaxY(f), CGRectGetMinY(dots) - 1, 0.001) && near(CGRectGetMinX(go), 400, 0.001) && near(go.size.width, 246, 0.6),
              "the code as written: it acts as the right corner: the left edge stays at 400, it grows right to 646 and down to the dots (%s, let go %s)", R(f).UTF8String, R(go).UTF8String);
    }
    // ---- the nearer corner: width then height, or height then width ----
    {
        CGRect area = CGRectMake(6, 30, 1182, 800), r[1] = {CGRectMake(700, 520, 100, 100)};   // (a rect below and right of the note: diagonal)
        CGRect st = CGRectMake(400, 300, 220, 180);
        CGRect f = Note(st, CGPointMake(380, 60), 1, area, r, 1);   // (mostly sideways: wide and short)
        CHECK(near(f.size.width, 600, 0.001) && near(CGRectGetMaxY(f), 519, 0.001), "a diagonal rect, the finger mostly sideways: the note keeps its width and stops above the rect (%s)", R(f).UTF8String);
        f = Note(st, CGPointMake(100, 400), 1, area, r, 1);   // (mostly down: tall and narrow)
        CHECK(near(CGRectGetMaxX(f), 699, 0.001) && near(CGRectGetMaxY(f), CGRectGetMaxY(area), 0.001), "  ... the finger mostly down: it keeps its height (to the area's bottom) and stops left of the rect (%s)", R(f).UTF8String);
        CGRect over[1] = {CGRectMake(380, 280, 100, 100)};   // (a rect the note already lay over: the layout could not clear it either)
        f = Note(st, CGPointMake(100, 100), 1, area, over, 1);
        CHECK(CGRectEqualToRect(f, NoteNoRects(st, CGPointMake(100, 100), 1, area)), "a rect the note already lay over is passed over: it still resizes (%s)", R(f).UTF8String);
        CGRect two[2] = {CGRectMake(380, 280, 100, 100), CGRectMake(400, 560, 100, 60)};   // (one it lay over, one below it grows to)
        f = Note(st, CGPointMake(100, 300), 1, area, two, 2);
        CHECK(CGRectEqualToRect(f, CGRectMake(400, 300, 320, 259)), "  ... with another rect in reach: only that one stops it (its width grows to 320, its bottom stops above the other rect: %s)", R(f).UTF8String);
    }
    // ---- a note placed against an icon touches it: stored and laid out again, it stays (the round trip's few 1e-13 pt never count as over it) ----
    {
        CGRect area = CGRectMake(6, 34, 1182, 726);
        long n = 0, moved = 0;
        for (double edge = 100.0; edge < 1000.0; edge += 3.7) for (double w = 120.0; w < 600.0; w += 23.3) {
            CGRect r[1] = {CGRectMake(edge - 85, 300, 85, 112)}, f = CGRectMake(edge, 280, w, 150);   // (its left edge on the icon's right side)
            if (!inside(f, area)) continue;
            n++;
            CGRect go = LetGo(f, area, r, 1);
            if (!near(go.origin.x, f.origin.x, 0.001) || !near(go.origin.y, f.origin.y, 0.001)) moved++;
        }
        CHECK(!moved && n > 500, "a note touching an icon, stored and laid out again, stays where it is (%ld cases; %ld moved)", n, moved);
    }
    // ---- every screen, page, start, grip and finger ----
    {
        long cases = 0, fixed = 0, over = 0, moved = 0, outside = 0, same = 0, sameN = 0, small = 0; char first[5][400] = {{0}};
        static const double dx[] = {-900, -400, -160, -60, -12, 0, 12, 60, 160, 400, 900}, dy[] = {-300, -40, 0, 40, 160, 600};
        for (int si = 0; si < NSCREENS; si++) for (int page = 0; page < 3; page++) {
            Screen s = screens[si]; CGRect area = areaOf(s), r[40];
            int n = pageRects(s, area, r, page == 0 ? 4 : page == 1 ? 12 : 8, page == 2);
            for (int wi = 0; wi < 3; wi++) for (int xi = 0; xi <= 10; xi++) for (int yi = 0; yi <= 6; yi++) {
                CGFloat w = wi == 0 ? 140 : wi == 1 ? 220 : 380, h = wi == 0 ? 90 : wi == 1 ? 180 : 260;
                CGRect st = MSBDStickyPlaceClear(CGRectMake(area.origin.x + (area.size.width - w) * xi / 10.0, area.origin.y + (area.size.height - h) * yi / 6.0, w, h), area, r, n, MSBD_NOTE_CLEAR_TESTS, NULL);
                if (overCount(st, r, n)) continue;   // (a start the layout could not clear: not this rule's case)
                for (int tag = 0; tag < 2; tag++) for (int i = 0; i < 11; i++) for (int j = 0; j < 6; j++) {
                    CGPoint tr = CGPointMake(dx[i], dy[j]);
                    CGRect want = NoteNoRects(st, tr, tag, area), f = Note(st, tr, tag, area, r, n), go = LetGo(f, area, r, n);
                    cases++;
                    #define WHY(k) snprintf(first[k], 400, "%s, page %d, %s grip, start %s, tr (%.0f, %.0f): %s, let go %s", s.name, page, tag ? "right" : "left", R(st).UTF8String, tr.x, tr.y, R(f).UTF8String, R(go).UTF8String)
                    if (!(near(f.origin.y, want.origin.y, 1e-9) && (tag == 0 ? near(CGRectGetMaxX(f), CGRectGetMaxX(want), 1e-6) : near(f.origin.x, want.origin.x, 1e-9)))) { if (!fixed++) WHY(0); }
                    if (overCount(f, r, n)) { if (!over++) WHY(1); }
                    if (!(near(go.origin.x, f.origin.x, 0.001) && near(go.origin.y, f.origin.y, 0.001) && near(CGRectGetMaxX(go), CGRectGetMaxX(f), 0.001) && near(CGRectGetMaxY(go), CGRectGetMaxY(f), 0.001))) { if (!moved++) WHY(2); }
                    if (!inside(f, area) || f.size.width < MSBD_NOTE_MIN_W - 0.001 || f.size.height < MSBD_NOTE_MIN_H - 0.001 || f.size.width > want.size.width + 1e-9 || f.size.height > want.size.height + 1e-9) { if (!outside++) WHY(3); }
                    if (!overCount(want, r, n)) { sameN++; if (memcmp(&f, &want, sizeof f)) { if (!same++) WHY(4); } }
                    if ((want.size.width >= st.size.width && f.size.width < st.size.width - 1e-9) || (want.size.height >= st.size.height && f.size.height < st.size.height - 1e-9)) small++;
                    #undef WHY
                }
            }
        }
        CHECK(!fixed, "every case: the top and the grip's other side are the grip's own (DMNativeResized's), never moved by the stop (%ld cases; %ld wrong)%s%s", cases, fixed, fixed ? "; first: " : "", first[0]);
        CHECK(!over, "every case: the note never lies over an app icon, a widget or the page dots it started clear of (%ld cases; %ld over)%s%s", cases, over, over ? "; first: " : "", first[1]);
        CHECK(!moved, "every case: the let go (stored, laid out, placed clear) leaves the note where the drag left it (%ld cases; %ld moved)%s%s", cases, moved, moved ? "; first: " : "", first[2]);
        CHECK(!outside, "every case: inside the free area, at least 120 x 80, never larger than the grip's own frame (%ld cases; %ld wrong)%s%s", cases, outside, outside ? "; first: " : "", first[3]);
        CHECK(!same && sameN > 1000, "every drag that meets no rect: the grip's own frame, bit for bit (%ld such cases; %ld differ)%s%s", sameN, same, same ? "; first: " : "", first[4]);
        CHECK(!small, "every case: a dimension the drag grows never ends smaller than it started (%ld cases; %ld smaller)", cases, small);
    }
    printf("test-stickyclear: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
} }
