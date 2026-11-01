// test-turnplace.c -- Mac test of statusbar/TurnPlace.h (1.7.4 items 4, 5, 7, 11, 14): which layout a window is in, where a window goes when the
// screen turns (its layout, else where it was in that shape, else in proportion), Fit to Window's spread when it is switched off, and a saved
// window's frame across an engine switch (Aerial 5.x's stage <-> the window). Desktops as on the iPads: the 17.5 (1024 x 1366 portrait, 1366 x
// 1024 landscape, menu bar 24) and the M1 (1194 x 834 landscape, Dock line 761.8); Aerial 5.x's margins as measured: 13 / 6 / 20 / 6 (iPad 2,
// 17.5), 13 / 6 / 12 / 6 (M1). Run by test-turnplace.sh.
#include <stdio.h>
#include <string.h>
#include "../statusbar/TurnPlace.h"
static int fails = 0, checks = 0;
static int near(double a, double b) { return fabs(a - b) < 0.01; }
static void Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    if ((CGRectIsNull(got) && CGRectIsNull(want)) || (!CGRectIsNull(got) && !CGRectIsNull(want) && near(got.origin.x, want.origin.x) && near(got.origin.y, want.origin.y) && near(got.size.width, want.size.width) && near(got.size.height, want.size.height))) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%.2f, %.2f, %.2f, %.2f}, want {%.2f, %.2f, %.2f, %.2f})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
}
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
// The nine layouts of a desktop u, cut as StatusBar.x DMLayoutFrameInArea cuts them (6 pt gap, the far tiles take the rest).
static void Cut(CGRect u, CGRect *t) {
    CGFloat g = 6.0, halfW = floor((u.size.width - g) / 2.0), halfH = floor((u.size.height - g) / 2.0);
    CGFloat rightX = u.origin.x + halfW + g, bottomY = u.origin.y + halfH + g, rightW = CGRectGetMaxX(u) - rightX, bottomH = CGRectGetMaxY(u) - bottomY;
    t[0] = u;
    t[1] = CGRectMake(u.origin.x, u.origin.y, halfW, u.size.height);  t[2] = CGRectMake(rightX, u.origin.y, rightW, u.size.height);
    t[3] = CGRectMake(u.origin.x, u.origin.y, u.size.width, halfH);   t[4] = CGRectMake(u.origin.x, bottomY, u.size.width, bottomH);
    t[5] = CGRectMake(u.origin.x, u.origin.y, halfW, halfH);          t[6] = CGRectMake(rightX, u.origin.y, rightW, halfH);
    t[7] = CGRectMake(u.origin.x, bottomY, halfW, bottomH);           t[8] = CGRectMake(rightX, bottomY, rightW, bottomH);
}
int main(void) {
    // ---- the layouts' names and order: what StatusBar.x's nine were (DMSMLayoutsNow before 1.7.4) ----
    const char *want[9] = { "fill", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright" };
    int same = 1; for (int i = 0; i < 9; i++) if (strcmp(kMSBDTurnLayouts[i], want[i])) same = 0;
    Int("the nine layouts a turn puts back, in the order Stage Manager's turn used", same, 1);
    // ---- which layout a frame is in (17.5 portrait desktop: under the 24 pt bar, down to the Dock line 1292.37) ----
    CGRect p = CGRectMake(0, 24, 1024, 1292.37 - 24), tp[9]; Cut(p, tp);
    CGRect l = CGRectMake(0, 24, 1366, 941.47 - 24), tl[9]; Cut(l, tl);
    Int("portrait: the left half is 'left'", MSBDTurnLayoutIndex(CGRectMake(0, 24, 509, 1268.37), tp, 9, kMSBDTurnLayoutTolerance), 1);
    Int("  ... 5.9 pt off on every number: still 'left' (the Window menu's tick, 6 pt)", MSBDTurnLayoutIndex(CGRectMake(5.9, 29.9, 503.1, 1262.47), tp, 9, kMSBDTurnLayoutTolerance), 1);
    Int("  ... 6 pt narrower: no layout", MSBDTurnLayoutIndex(CGRectMake(0, 24, 503, 1268.37), tp, 9, kMSBDTurnLayoutTolerance), -1);
    Int("portrait: Fill", MSBDTurnLayoutIndex(p, tp, 9, kMSBDTurnLayoutTolerance), 0);
    Int("portrait: the bottom-right quarter", MSBDTurnLayoutIndex(tp[8], tp, 9, kMSBDTurnLayoutTolerance), 8);
    Int("landscape: the right half", MSBDTurnLayoutIndex(tl[2], tl, 9, kMSBDTurnLayoutTolerance), 2);
    Int("a portrait left half read against landscape's layouts: none (the turn reads the layouts BEFORE it)", MSBDTurnLayoutIndex(tp[1], tl, 9, kMSBDTurnLayoutTolerance), -1);
    Int("a free window (Clock, 600 x 1248 at 100, 40): none", MSBDTurnLayoutIndex(CGRectMake(100, 40, 600, 1248), tp, 9, kMSBDTurnLayoutTolerance), -1);
    CGRect holes[9]; memcpy(holes, tp, sizeof holes); holes[0] = CGRectNull; holes[1] = CGRectZero;
    Int("a layout that can't be cut (null / empty) never matches: the next one does", MSBDTurnLayoutIndex(tp[5], holes, 9, kMSBDTurnLayoutTolerance), 5);
    Int("  ... a null frame matches nothing", MSBDTurnLayoutIndex(CGRectNull, tp, 9, kMSBDTurnLayoutTolerance), -1);
    // ---- the turn's rule ----
    int why = -1;
    CGRect remembered = CGRectMake(100, 40, 600, 1248), scaled = CGRectMake(133, 30, 800, 936);
    Frame("in a layout: its layout of the new shape, also when it has a place remembered there (landscape's left half)", MSBDTurnPlaceFor(tl[1], remembered, scaled, &why), tl[1]);
    Int("  ... why: its layout", why, MSBDTurnLayout);
    Frame("no layout, a place remembered in the new shape (the 17.5's Clock back in portrait, 1248 pt tall: item 7)", MSBDTurnPlaceFor(CGRectNull, remembered, scaled, &why), remembered);
    Int("  ... why: where it was in this shape", why, MSBDTurnRemembered);
    Frame("no layout, nothing remembered: in proportion", MSBDTurnPlaceFor(CGRectNull, CGRectNull, scaled, &why), scaled);
    Int("  ... why: in proportion", why, MSBDTurnProportional);
    Frame("nothing at all (Stage Manager's own proportion): none -- left to the engine", MSBDTurnPlaceFor(CGRectNull, CGRectNull, CGRectNull, &why), CGRectNull);
    Int("  ... why: none", why, MSBDTurnNone);
    Frame("an empty layout frame does not count: the remembered place", MSBDTurnPlaceFor(CGRectZero, remembered, scaled, &why), remembered);
    Int("  ... why", why, MSBDTurnRemembered);
    Frame("a round trip of a Fill window (hidden desktop, item 11): landscape -> portrait -> landscape gives landscape's Fill, not portrait's width", MSBDTurnPlaceFor(tl[0], CGRectMake(0, 24, 1024, 917.47), CGRectNull, &why), l);
    // ---- 1.7.5 item 14: a window a turn put back where it was in this shape keeps no layout while it stays there ----
    {
        bool keep = true;
        CGRect quarter = tp[8];   // (Tips' old portrait place, the bottom-right quarter's frame: 1.7.4 R2 F1)
        Int("a free window put back by a turn at a quarter's frame: no layout (not 'bottomright')", MSBDTurnNoteIndex(quarter, 8, quarter, kMSBDTurnPlacedTolerance, &keep), -1);
        Int("  ... the record stays", keep, 1);
        Int("  ... 1.5 pt off (the engine's rounding): still no layout", MSBDTurnNoteIndex(CGRectOffset(quarter, 1.5, -1.5), 8, quarter, kMSBDTurnPlacedTolerance, &keep), -1);
        Int("moved since (8 pt): its frame tells again -- the quarter it is in", MSBDTurnNoteIndex(CGRectOffset(quarter, 0, 0), 8, CGRectOffset(quarter, 8, 0), kMSBDTurnPlacedTolerance, &keep), 8);
        Int("  ... and the record goes", keep, 0);
        Int("moved elsewhere, in no layout: none", MSBDTurnNoteIndex(CGRectMake(174, 108, 676, 501), -1, quarter, kMSBDTurnPlacedTolerance, &keep), -1);
        Int("  ... the record goes", keep, 0);
        Int("no record: the layout its frame is in", MSBDTurnNoteIndex(quarter, 8, CGRectNull, kMSBDTurnPlacedTolerance, &keep), 8);
        Int("  ... nothing to keep", keep, 0);
        Int("an empty record counts as none", MSBDTurnNoteIndex(quarter, 8, CGRectZero, kMSBDTurnPlacedTolerance, &keep), 8);
    }
    // ---- Fit to Window off: the spread (the same numbers as the engines' spread before 1.7.4, DMSpreadFitGroup's formula) ----
    CGRect m1 = CGRectMake(0, 24, 1194, 761.8 - 24);
    CGSize medium = CGSizeMake(round(m1.size.width * 0.66), round(m1.size.height * 0.74));
    for (int n = 2; n <= 4; n++) {
        CGFloat dx = fmax(0.0, m1.size.width - medium.width), dy = fmax(0.0, m1.size.height - medium.height);
        for (int i = 0; i < n; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)(n - 1);
            char what[160]; snprintf(what, sizeof what, "spread of %d on the M1: window %d as the engines spread it before (whole points)", n, i);
            Frame(what, MSBDSpreadFrame(i, n, m1, medium), CGRectMake(round(m1.origin.x + dx * t), round(m1.origin.y + dy * t), medium.width, medium.height));
        }
    }
    Frame("spread of 2: the oldest at the desktop's top-left corner", MSBDSpreadFrame(0, 2, m1, medium), CGRectMake(0, 24, 788, 546));
    Frame("  ... the newest at its bottom-right corner", MSBDSpreadFrame(1, 2, m1, medium), CGRectMake(406, 216, 788, 546));
    Frame("spread of 3, the middle one halfway", MSBDSpreadFrame(1, 3, m1, medium), CGRectMake(203, 120, 788, 546));
    Frame("a window bigger than the desktop stays at its top-left corner", MSBDSpreadFrame(1, 2, m1, CGSizeMake(1300, 900)), CGRectMake(0, 24, 1300, 900));
    Frame("one window: the top-left corner", MSBDSpreadFrame(0, 1, m1, medium), CGRectMake(0, 24, 788, 546));
    Frame("out of range: none", MSBDSpreadFrame(2, 2, m1, medium), CGRectNull);
    Frame("no size: none", MSBDSpreadFrame(0, 2, m1, CGSizeZero), CGRectNull);
    // ---- a saved frame across an engine switch (item 14) ----
    MSBDStageMargins pad = { 13, 6, 20, 6 }, m1m = { 13, 6, 12, 6 };
    CGRect win = CGRectMake(100, 40, 600, 500);
    CGRect stage = MSBDStageFromWindowFrame(win, pad);
    Frame("Aerial 5.x's stage for a window (13 / 6 / 20 / 6): 6 pt left, 12 wider, 9 taller, its top where the window's is (drawn 11 lower)", stage, CGRectMake(94, 40, 612, 509));
    Frame("  ... and back: the window exactly", MSBDWindowFromStageFrame(stage, pad), win);
    Frame("the M1's margins (13 / 6 / 12 / 6): 12 wider, 1 taller", MSBDStageFromWindowFrame(win, m1m), CGRectMake(94, 40, 612, 501));
    Frame("  ... and back", MSBDWindowFromStageFrame(MSBDStageFromWindowFrame(win, m1m), m1m), win);
    bool conv = true;
    Frame("Aerial 5.x -> Zetsu: the saved stage becomes the window it drew (the 1.7.3 snap pass: Zetsu windows came back 12 pt wider, 9 taller)", MSBDSavedFrameForEngine(stage, true, pad, false, pad, &conv), win);
    Int("  ... converted", conv, 1);
    Frame("Zetsu -> Aerial 5.x: the saved window becomes the stage that draws it, with this Aerial's margins", MSBDSavedFrameForEngine(win, false, pad, true, m1m, &conv), CGRectMake(94, 40, 612, 501));
    Int("  ... converted", conv, 1);
    Frame("Aerial 5.x -> Aerial 5.x: byte for byte as saved (also when the margins learnt since differ)", MSBDSavedFrameForEngine(stage, true, pad, true, m1m, &conv), stage);
    Int("  ... not converted", conv, 0);
    Frame("Zetsu -> MilkyWay4 (both the window itself): as saved", MSBDSavedFrameForEngine(win, false, pad, false, pad, &conv), win);
    Int("  ... not converted", conv, 0);
    Frame("a null frame stays null", MSBDSavedFrameForEngine(CGRectNull, true, pad, false, pad, &conv), CGRectNull);
    // the rounding the restore keeps: a frame converted twice (Aerial -> Zetsu -> Aerial, saved in between) comes back exactly
    Frame("Aerial -> Zetsu -> Aerial: the same stage", MSBDSavedFrameForEngine(MSBDSavedFrameForEngine(stage, true, pad, false, pad, NULL), false, pad, true, pad, NULL), stage);
    printf("%s: %d checks, %d failed\n", fails ? "test-turnplace FAILED" : "test-turnplace: all pass", checks, fails);
    return fails ? 1 : 0;
}
