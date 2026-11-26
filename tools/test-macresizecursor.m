// Mac test of the Mac resize pointers' rules and glyphs (1.8.9, F51; common/MacResizeCursor.h). Run by test-macresizecursor.sh.
//  - the fact's word (every valid fact round trip, invalid words read as none), SpringBoard's edge numbers, the one-way table (design 4.5), the
//    evidence (angle classes with any quarter turn), the look (the root fix: a state with accessories is never the beam), the drag latch;
//  - every glyph against macOS's own cursor (NSCursor's frame / column / row resize cursors, macOS 15+; skipped with a notice on an older macOS):
//    both rendered at 8x over mid grey, the black only (luminance under 25), ours at macOS's size (our units / MSBD_RZ_UNIT) with our hotspot on
//    macOS's (the frame cursors' calibrated as our arrow's: macOS's hotspot sits 0.875 pt before its black, ours on it): intersection over union
//    >= 0.85 and the black's middle within 0.5 pt;
//  - a sheet of every glyph at Pointer Size 1 to 5 (argv[1]: a folder to write it to);
//  - Settings > Pointer > Mac Resize Pointers (1.8.9, KT 25 Nov): never set, on on iPadOS 18 and later and off on 15-17; the user's choice wins; off,
//    the look is 1.8.8.4's for every shape (LOOK1884_INC: 1.8.8.4's own two lines, cut out of its MacPointer.x by the .sh; else a copy of them).
// MSBD_RZ_FAIL_GLYPH (made-to-fail copy): a glyph turned the wrong way must fail.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#include <stdio.h>
#include "../common/MacResizeCursor.h"

static int fails = 0, checks = 0;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static const unsigned kPos[8] = { MSBD_RZ_TOP, MSBD_RZ_LEFT, MSBD_RZ_BOTTOM, MSBD_RZ_RIGHT, MSBD_RZ_TOP | MSBD_RZ_LEFT, MSBD_RZ_TOP | MSBD_RZ_RIGHT,
                                  MSBD_RZ_BOTTOM | MSBD_RZ_LEFT, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT };
static MSBDResizeFact F(unsigned kind, unsigned pos, unsigned dir) { MSBDResizeFact f = { kind, pos, dir, 0, MSBD_RZ_SRC_BAND, 1 }; return f; }

static void Rules(void) {
    // the word
    int n = 0;
    for (unsigned kind = 1; kind <= 3; kind++) for (unsigned pos = 0; pos <= 15; pos++) for (unsigned dir = 0; dir <= 3; dir++) for (unsigned disp = 0; disp <= 1; disp++) {
        MSBDResizeFact f = { kind, pos, dir, disp, MSBD_RZ_SRC_GRIP, 0xBEEF };
        bool valid = MSBDResizeFactValid(f);
        uint64_t w = MSBDResizePack(f);
        if (!valid) { CHECK(w == 0, "invalid fact %u/%u/%u packs to 0", kind, pos, dir); continue; }
        n++;
        MSBDResizeFact g = MSBDResizeUnpack(w);
        CHECK(w != 0 && g.kind == kind && g.position == pos && g.directions == dir && g.display == disp && g.source == MSBD_RZ_SRC_GRIP && g.generation == 0xBEEF,
              "round trip %u/%u/%u/%u", kind, pos, dir, disp);
    }
    CHECK(n == (8 + 1 + 1) * 3 * 2, "valid facts: %d (8 frame positions + column + row, x 3 directions x 2 displays)", n);
    CHECK(MSBDResizeUnpack(0).kind == MSBD_RZ_NONE, "0 is none");
    CHECK(MSBDResizeUnpack(0x5 | (3 << 4) | (3 << 8)).kind == MSBD_RZ_NONE, "kind 5 is none");
    CHECK(MSBDResizeUnpack(1 | (5 << 4) | (3 << 8)).kind == MSBD_RZ_NONE, "top+bottom is no position");
    CHECK(MSBDResizeUnpack(1 | (1 << 4)).kind == MSBD_RZ_NONE, "no directions is none");
    CHECK(MSBDResizeUnpack(2 | (2 << 4) | (1 << 8)).kind == MSBD_RZ_NONE, "a column has no position");
    CHECK(MSBDResizeSamePlace(F(1, 8, 3), F(1, 8, 3)) && !MSBDResizeSamePlace(F(1, 8, 3), F(1, 8, 2)), "same place");
    // SpringBoard's edges
    CHECK(MSBDResizePosOfSBEdge(0) == 0 && MSBDResizePosOfSBEdge(9) == 0 && MSBDResizePosOfSBEdge(1ULL << 40) == 0, "no edge");
    CHECK(MSBDResizePosOfSBEdge(1) == MSBD_RZ_TOP && MSBDResizePosOfSBEdge(2) == MSBD_RZ_BOTTOM && MSBDResizePosOfSBEdge(3) == MSBD_RZ_LEFT && MSBDResizePosOfSBEdge(4) == MSBD_RZ_RIGHT, "edges");
    CHECK(MSBDResizePosOfSBEdge(5) == (MSBD_RZ_TOP | MSBD_RZ_LEFT) && MSBDResizePosOfSBEdge(6) == (MSBD_RZ_TOP | MSBD_RZ_RIGHT) && MSBDResizePosOfSBEdge(7) == (MSBD_RZ_BOTTOM | MSBD_RZ_LEFT)
          && MSBDResizePosOfSBEdge(8) == (MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT), "corners");
    for (unsigned e = 1; e <= 8; e++) CHECK(MSBDResizePositionValid(MSBD_RZ_FRAME, MSBDResizePosOfSBEdge(e)), "edge %u valid", e);
    // one-way (design 4.5): a 1194 x 834 screen, a 320 x 300 minimum
    CGRect area = CGRectMake(0, 24, 1194, 810); CGSize mn = CGSizeMake(320, 300);
    CGRect mid = CGRectMake(200, 200, 600, 400), narrow = CGRectMake(200, 200, 320, 400), small = CGRectMake(200, 200, 320.4, 300), wide = CGRectMake(0, 200, 1194, 400);
    CGRect full = CGRectMake(0, 24, 1194, 810), atRight = CGRectMake(594, 200, 600, 400);
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, mid, mn, area, 0.5) == MSBD_RZ_ALL, "room both ways: all");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, narrow, mn, area, 0.5) == MSBD_RZ_OUTWARD, "minimum width, right edge: outward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_LEFT, narrow, mn, area, 0.5) == MSBD_RZ_OUTWARD, "minimum width, left edge: outward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_TOP, narrow, mn, area, 0.5) == MSBD_RZ_ALL, "minimum width, top edge: all (height has room)");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, wide, mn, area, 0.5) == MSBD_RZ_INWARD, "full width, right edge: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_LEFT, wide, mn, area, 0.5) == MSBD_RZ_INWARD, "full width, left edge: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, atRight, mn, area, 0.5) == MSBD_RZ_INWARD && MSBDResizeDirectionsFor(MSBD_RZ_LEFT, atRight, mn, area, 0.5) == MSBD_RZ_ALL,
          "at the right limit: right inward, left all");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, small, mn, area, 0.5) == MSBD_RZ_OUTWARD, "minimum both ways, a corner: outward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, narrow, mn, area, 0.5) == MSBD_RZ_ALL, "minimum one way, a corner: all");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_TOP | MSBD_RZ_LEFT, full, mn, area, 0.5) == MSBD_RZ_INWARD, "the whole area, top-left corner: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_TOP, full, mn, area, 0.5) == MSBD_RZ_INWARD, "top at the limit: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, narrow, CGSizeZero, area, 0.5) == MSBD_RZ_ALL, "minimum not known: never outward-only");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, wide, mn, CGRectNull, 0.5) == MSBD_RZ_ALL, "area not known: never inward-only");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, CGRectMake(0, 24, 320, 810), mn, CGRectMake(0, 24, 320, 810), 0.5) == MSBD_RZ_ALL, "neither way: all, no claim");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_RIGHT, CGRectNull, mn, area, 0.5) == MSBD_RZ_ALL, "no frame: all");
    // evidence
    for (int q = -4; q <= 8; q++) {
        CHECK(MSBDResizeAngleClass(q * M_PI_2) == 1, "straight %d x 90", q);
        CHECK(MSBDResizeAngleClass(q * M_PI_2 + M_PI_4) == 2, "diagonal %d x 90 + 45", q);
        CHECK(MSBDResizeAngleClass(q * M_PI_2 + 0.15) == 1 && MSBDResizeAngleClass(q * M_PI_2 + M_PI_4 - 0.15) == 2, "small tilts %d", q);
        CHECK(MSBDResizeAngleClass(q * M_PI_2 + M_PI / 8) == 0, "22.5 degrees: neither %d", q);
    }
    CHECK(MSBDResizeAngleClass(NAN) == 0 && MSBDResizeAngleClass(INFINITY) == 0, "no angle");
    double ud[2] = { 0, M_PI }, diag[2] = { M_PI_4, 5 * M_PI_4 }, odd[1] = { 0.4 };
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 0, 0, 2, ud, 2) && MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 1, 0, 0, 2, ud, 2), "an edge: straight arrows (any turn)");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 0, 0, 2, diag, 2), "an edge: diagonal arrows are not its evidence");
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, 3), 1, 0, 0, 2, diag, 2) && !MSBDResizeEvidence(F(1, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, 3), 1, 0, 0, 2, ud, 2), "a corner: diagonal only");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 0, 0, 1, odd, 1), "an odd angle: no evidence");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 0, 0, 0, NULL, 0), "no accessories: no evidence");
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 0, 0, 2, NULL, 0), "accessories whose angles could not be read: taken");
    MSBDResizeFact none = MSBDResizeUnpack(0);
    CHECK(!MSBDResizeEvidence(none, 1, 0, 0, 2, ud, 2), "no fact: no evidence");
    CHECK(MSBDResizeEvidence(F(2, 0, 3), 1, 0, 0, 2, ud, 2) && MSBDResizeEvidence(F(3, 0, 1), 1, 0, 0, 1, ud, 1), "dividers: straight");
    // iPadOS's own resize shape as the evidence (18.5, B0: a band's style is a type 4 path, 35 x 14 along an edge, 25.8 square at a corner)
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 35.0, 13.96, -1, NULL, 0) && MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 13.96, 35.0, 0, NULL, 0), "18.5's edge shape, either way round");
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, 3), 4, 25.82, 25.82, 0, NULL, 0), "18.5's corner shape");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 3, 20, 20, 0, NULL, 0), "a traffic light's highlight (type 3, 20 x 20): no evidence");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 3, 41, 182, 0, NULL, 0) && !MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 1, 35, 14, 0, NULL, 0),
          "a long button highlight (type 3, 41 x 182: 17.5.1's Clock tab) or a type 1 shape: no evidence, whatever its proportions");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 3, 3, 24, 0, NULL, 0) && !MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 0, 0, 0, NULL, 0) && !MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 2, 24, 0, NULL, 0),
          "a text beam (thin type 3, a type 4 without a size or thin): no evidence");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 1, 0, 0, 0, NULL, 0), "the round pointer: no evidence");
    CHECK(!MSBDResizeEvidence(none, 4, 35, 14, 0, NULL, 0), "no fact: never");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 25.82, 25.82, 0, NULL, 0) && !MSBDResizeEvidence(F(1, MSBD_RZ_TOP, 3), 4, 30, 20, 0, NULL, 0),
          "an edge's fact over a square or short path (a corner's, an app's): no evidence (review finding 8)");
    CHECK(!MSBDResizeEvidence(F(1, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, 3), 4, 35, 13.96, 0, NULL, 0), "a corner's fact over an edge's path: no evidence");
    CHECK(MSBDResizeEvidence(F(1, MSBD_RZ_TOP | MSBD_RZ_LEFT, 3), 4, 25.0, 26.5, 0, NULL, 0) && MSBDResizeEvidence(F(1, MSBD_RZ_LEFT, 3), 4, 14, 28, 0, NULL, 0),
          "near-square at a corner, 2 to 1 along an edge: evidence");
    // the beam (B0: 15.6.1 and 18.5 search fields 3 x 24 type 3; 17.5.1 Finder's search field type 4, 1.8.8)
    CHECK(MSBDPointerBeamShape(3, 3, 24) && MSBDPointerBeamShape(3, 24, 3), "a thin type 3: the beam, either way round");
    CHECK(MSBDPointerBeamShape(4, 0, 0) && MSBDPointerBeamShape(4, 2.5, 22) && MSBDPointerBeamShape(4, 5.5, 30), "a type 4 without a size, or under 6 pt across: the beam");
    CHECK(!MSBDPointerBeamShape(4, 35, 13.96) && !MSBDPointerBeamShape(4, 13.96, 35) && !MSBDPointerBeamShape(4, 25.82, 25.82), "18.5's resize shapes: never the beam (the cause of the bug photo)");
    CHECK(!MSBDPointerBeamShape(1, 0, 0) && !MSBDPointerBeamShape(3, 20, 20) && !MSBDPointerBeamShape(3, 41, 182), "the round pointer and highlights: not the beam");
    CHECK(MSBDPointerLook(MSBDPointerBeamShape(4, 35, 13.96), -1, false, false, false) == MSBD_PTR_ARROW, "the bug photo: a band with no fact (an unknown version): our arrow, never iPadOS's capsule");
    CHECK(MSBDPointerLook(MSBDPointerBeamShape(4, 35, 13.96), -1, true, MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 4, 35, 13.96, -1, NULL, 0), false) == MSBD_PTR_RESIZE, "the bug photo with the fact: the resize cursor");
    CHECK(MSBDPointerLook(MSBDPointerBeamShape(3, 3, 24), 0, true, MSBDResizeEvidence(F(1, MSBD_RZ_RIGHT, 3), 3, 3, 24, 0, NULL, 0), false) == MSBD_PTR_BEAM, "a stale fact over a search field: the beam");
    // the look
    CHECK(MSBDPointerLook(true, 0, false, false, false) == MSBD_PTR_BEAM, "a beam with no accessories: iPadOS's beam");
    CHECK(MSBDPointerLook(true, 2, false, false, false) == MSBD_PTR_ARROW, "the root fix: a beam-like shape with accessories, no fact: our arrow, never iPadOS's blob");
    CHECK(MSBDPointerLook(true, 2, true, true, false) == MSBD_PTR_RESIZE, "a band with its fact and arrows: the resize glyph");
    CHECK(MSBDPointerLook(false, 0, true, false, false) == MSBD_PTR_ARROW, "a stale fact without arrows: the arrow");
    CHECK(MSBDPointerLook(true, 0, true, false, false) == MSBD_PTR_BEAM, "a stale fact over text: the beam");
    CHECK(MSBDPointerLook(false, 2, false, false, false) == MSBD_PTR_ARROW, "an app's own arrows, no fact: the arrow (Q3)");
    CHECK(MSBDPointerLook(false, 0, false, false, true) == MSBD_PTR_RESIZE && MSBDPointerLook(true, 0, false, false, true) == MSBD_PTR_RESIZE, "latched: the glyph wherever the pointer is");
    // the latch
    MSBDResizeLatch l = {0}; MSBDResizeFact tr = F(1, MSBD_RZ_RIGHT, 3);
    CHECK(!MSBDResizeLatchStep(&l, false, false, true, tr), "hover: not latched");
    CHECK(MSBDResizeLatchStep(&l, true, false, true, tr) && l.fact.position == MSBD_RZ_RIGHT, "press on the glyph: latched with it");
    CHECK(MSBDResizeLatchStep(&l, true, false, false, none), "the pointer runs off the band: still latched");
    CHECK(MSBDResizeLatchStep(&l, true, false, true, F(1, MSBD_RZ_TOP, 3)) && l.fact.position == MSBD_RZ_RIGHT, "another band during the drag: the press's glyph stays");
    CHECK(!MSBDResizeLatchStep(&l, false, false, false, none), "button up: unlatched");
    CHECK(!MSBDResizeLatchStep(&l, true, false, false, none), "a press on the arrow: not latched");
    CHECK(!MSBDResizeLatchStep(&l, true, false, true, tr), "already pressed when a band comes: not latched (no new press)");
    CHECK(!MSBDResizeLatchStep(&l, false, false, true, tr) && MSBDResizeLatchStep(&l, true, false, true, tr), "a new press: latched");
    CHECK(!MSBDResizeLatchStep(&l, true, true, false, none), "the pointer hidden: unlatched");
    CHECK(!MSBDResizeLatchStep(&l, true, false, true, tr), "  ... and not again until a new press");
    // the latch's grace after the button-up (F51b: the glyph stays until SpringBoard's word at the release)
    MSBDResizeLatch g2 = {0};
    MSBDResizeFact gtr = tr; gtr.source = MSBD_RZ_SRC_GRIP; gtr.position = MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT;
    MSBDResizeLatch b2 = {0};   // (a band's drag: no grace, F51 as it was -- review F51b finding 2)
    MSBDResizeLatchStepAt(&b2, false, false, true, tr, 10.0); MSBDResizeLatchStepAt(&b2, true, false, true, tr, 10.1);
    CHECK(!MSBDResizeLatchStepAt(&b2, false, false, false, none, 11.0) && !MSBDResizeLatchHolds(&b2, 11.0) && b2.graceUntil == 0, "grace: a band's drag has none");
    tr = gtr;
    CHECK(!MSBDResizeLatchStepAt(&g2, false, false, true, tr, 100.0) && !MSBDResizeLatchHolds(&g2, 100.0), "grace: hover, nothing held");
    CHECK(MSBDResizeLatchStepAt(&g2, true, false, true, tr, 100.1) && MSBDResizeLatchHolds(&g2, 100.1) && g2.graceUntil == 0, "grace: a press latches, no grace yet");
    CHECK(!MSBDResizeLatchStepAt(&g2, false, false, false, none, 101.0) && MSBDResizeLatchHolds(&g2, 101.0) && MSBDResizeLatchHolds(&g2, 101.0 + MSBD_RZ_LATCH_GRACE - 0.01),
          "grace: the button-up holds the press's glyph a moment");
    CHECK(MSBDResizeLatchGraceOnly(&g2, 101.05) && !MSBDResizeLatchGraceOnly(&g2, 101.2), "grace: only the grace holds (a press then never latches its glyph, finding 3)");
    CHECK(!MSBDResizeLatchHolds(&g2, 101.0 + MSBD_RZ_LATCH_GRACE + 0.001), "grace: over after MSBD_RZ_LATCH_GRACE");
    MSBDResizeLatchStepAt(&g2, true, false, true, tr, 102.0); MSBDResizeLatchStepAt(&g2, false, false, false, none, 102.5);
    MSBDResizeLatchWord(&g2);
    CHECK(!MSBDResizeLatchHolds(&g2, 102.51), "grace: SpringBoard's word ends it at once");
    MSBDResizeLatchStepAt(&g2, false, false, true, tr, 103.0); MSBDResizeLatchStepAt(&g2, true, false, true, tr, 103.1);
    CHECK(!MSBDResizeLatchStepAt(&g2, true, true, false, none, 103.2) && !MSBDResizeLatchHolds(&g2, 103.21), "grace: a hidden pointer has none");
    CHECK(MSBD_RZ_LATCH_GRACE > 0.05 && MSBD_RZ_LATCH_GRACE <= 0.25, "grace: a moment only (%.2f s)", MSBD_RZ_LATCH_GRACE);
    // F51b: our window engines' grips (Aerial, Zetsu, MilkyWay4) -- the fact is its own evidence while fresh
    MSBDResizeFact gbr = { MSBD_RZ_FRAME, MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, 3, 0, MSBD_RZ_SRC_GRIP, 7 }, gbl = gbr, gedge = gbr, bbr = gbr;
    gbl.position = MSBD_RZ_BOTTOM | MSBD_RZ_LEFT; gedge.position = MSBD_RZ_RIGHT; bbr.source = MSBD_RZ_SRC_BAND;
    CHECK(MSBDResizeEvidence(gbr, 1, 0, 0, 0, NULL, 0) && MSBDResizeEvidence(gbl, 1, 0, 0, -1, NULL, 0), "a grip's fact over the round pointer (B0 15.6.1): evidence");
    CHECK(MSBDResizeEvidence(gbr, 3, 3, 24, 0, NULL, 0) && MSBDResizeEvidence(gbr, 3, 41, 182, 0, NULL, 0), "a grip's fact over an app's beam or button: evidence (the grip takes the click)");
    CHECK(!MSBDResizeEvidence(gedge, 1, 0, 0, 0, NULL, 0), "a grip's fact at an edge (no engine resizes there): never");
    CHECK(!MSBDResizeEvidence(bbr, 1, 0, 0, 0, NULL, 0), "a band's fact over the round pointer: still none (F51 unchanged)");
    CHECK(MSBDPointerLook(MSBDPointerBeamShape(3, 3, 24), 0, true, MSBDResizeEvidence(gbr, 3, 3, 24, 0, NULL, 0), false) == MSBD_PTR_RESIZE, "a grip over text: the resize glyph, not the beam");
    CHECK(MSBDPointerLook(MSBDPointerBeamShape(3, 3, 24), 0, false, MSBDResizeEvidence(gbr, 3, 3, 24, 0, NULL, 0), false) == MSBD_PTR_BEAM, "a stale grip (not here): the beam again");
    { uint64_t w = MSBDResizePack(gbr); MSBDResizeFact u = MSBDResizeUnpack(w);
      CHECK(w && u.source == MSBD_RZ_SRC_GRIP && u.position == (MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT) && u.generation == 7, "a grip's word round trip (0x%llx)", (unsigned long long)w); }
    // ... and its lease: fresh only within MSBD_RZ_GRIP_LEASE s of its last word and with no change of iPadOS's shape since
    CHECK(MSBDResizeGripFresh(50.0, 50.0, 4, 4) && MSBDResizeGripFresh(51.1, 50.0, 4, 4), "lease: fresh");
    CHECK(!MSBDResizeGripFresh(50.0 + MSBD_RZ_GRIP_LEASE + 0.01, 50.0, 4, 4), "lease: a word nobody says again expires (a SpringBoard that died or hangs)");
    CHECK(!MSBDResizeGripFresh(50.2, 50.0, 5, 4), "lease: iPadOS's shape changed since the word: not fresh");
    CHECK(!MSBDResizeGripFresh(50.0, 0, 4, 4), "lease: no word yet: not fresh");
    {   // (the real interval: SpringBoard's 0.2 s check says it again at the first tick past MSBD_RZ_GRIP_RESAY, plus the timer's 0.04 s tolerance --
        //  finding 4: two words inside the lease even with one of them a tick late)
        double tick = ceil((MSBD_RZ_GRIP_RESAY - 0.01) / MSBD_RZ_GRIP_CHECK) * MSBD_RZ_GRIP_CHECK + 0.04;
        CHECK(2 * tick + MSBD_RZ_GRIP_CHECK < MSBD_RZ_GRIP_LEASE, "lease: said again every %.2f s in practice: twice inside the lease (%.1f s) with a tick to spare", tick, MSBD_RZ_GRIP_LEASE);
    }
    // SpringBoard's decision for a grip, as sequences (ResizeFact.h DMRZGripDecide; finding 14)
    CHECK(MSBDResizeGripAction(true, false, true, 5.0, false) == MSBD_RZ_GRIP_SAY, "seq: a hover onto a grip: said");
    CHECK(MSBDResizeGripAction(true, true, true, 0.01, true) == MSBD_RZ_GRIP_SAY_AGAIN, "seq: a hover inside it: said again at once (a hover is the freshest word)");
    CHECK(MSBDResizeGripAction(true, true, false, 0.2, true) == MSBD_RZ_GRIP_NOTHING, "seq: resting, the first check: nothing");
    CHECK(MSBDResizeGripAction(true, true, false, 0.4, true) == MSBD_RZ_GRIP_SAY_AGAIN && MSBDResizeGripAction(true, true, false, 0.395, true) == MSBD_RZ_GRIP_SAY_AGAIN, "seq: resting, the second check: said again (the lease)");
    CHECK(MSBDResizeGripAction(false, false, true, 0.1, true) == MSBD_RZ_GRIP_CLEAR, "seq: a hover off the grip: cleared");
    CHECK(MSBDResizeGripAction(false, false, false, 3.0, true) == MSBD_RZ_GRIP_CLEAR, "seq: the check finds no grip (closed, covered, moved, a drag that left it): cleared");
    CHECK(MSBDResizeGripAction(false, false, true, 3.0, false) == MSBD_RZ_GRIP_NOTHING, "seq: no grip, no grip fact (a band's or none): nothing of it touched");
    CHECK(MSBDResizeGripAction(true, false, false, 0.1, true) == MSBD_RZ_GRIP_SAY, "seq: another grip (or another place, a one-way change): said");
    CHECK(MSBDResizeGripCheckKeeps(true, 0, 3600.0), "check: the iPad's resting grip goes on (its fade clears it)");
    CHECK(!MSBDResizeGripCheckKeeps(false, 0, 0.5), "check: the screen turned under a resting pointer: cleared (finding 11)");
    CHECK(MSBDResizeGripCheckKeeps(true, 1, 9.0) && !MSBDResizeGripCheckKeeps(true, 1, MSBD_RZ_GRIP_OTHER_REST + 0.1), "check: another display's grip ends after a long rest there (finding 10)");
    // ... one-way arrows as ResizeFact.h DMRZGripDirections asks: Zetsu (its drag stops at the screen's edges: 1194 x 834), MilkyWay4 (minimum
    // only), Aerial 5.x as its stage (332 x 333 with its margins), where our minimum holds
    CGSize zmin = CGSizeMake(320, 324), amin = CGSizeMake(332, 333); CGRect scr = CGRectMake(0, 0, 1194, 834);
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(300, 200, 320, 324), zmin, scr, 1.0) == MSBD_RZ_OUTWARD, "Zetsu at its minimum: the outward diagonal");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_LEFT, CGRectMake(300, 200, 320.5, 324), zmin, scr, 1.0) == MSBD_RZ_OUTWARD, "... its bottom-left too");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(594, 434, 600, 400), zmin, scr, 1.0) == MSBD_RZ_INWARD, "Zetsu at the screen's bottom-right: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_LEFT, CGRectMake(0, 434, 600, 400), zmin, scr, 1.0) == MSBD_RZ_INWARD, "Zetsu at the screen's bottom-left: inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(594, 200, 600, 400), zmin, scr, 1.0) == MSBD_RZ_ALL, "Zetsu at the right edge only: the double arrow");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(874, 510, 320, 324), zmin, scr, 1.0) == MSBD_RZ_ALL, "Zetsu at its minimum AND at the edges: the double arrow (no claim)");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(594, 434, 600, 400), zmin, CGRectNull, 1.0) == MSBD_RZ_ALL, "MilkyWay4 / Aerial at the edges: never inward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(100, 100, 332, 333), amin, CGRectNull, 1.0) == MSBD_RZ_OUTWARD, "Aerial 5.x's stage at its minimum: outward");
    CHECK(MSBDResizeDirectionsFor(MSBD_RZ_BOTTOM | MSBD_RZ_RIGHT, CGRectMake(100, 100, 332, 333), CGSizeZero, CGRectNull, 1.0) == MSBD_RZ_ALL, "Aerial where our minimum does not hold: the double arrow");
    // keys
    CHECK(MSBDResizeGlyphKey(F(1, MSBD_RZ_TOP, 3)) == MSBDResizeGlyphKey(F(1, MSBD_RZ_BOTTOM, 3)) && MSBDResizeGlyphKey(F(1, MSBD_RZ_LEFT, 3)) == MSBDResizeGlyphKey(F(1, MSBD_RZ_RIGHT, 3)),
          "double arrows share a key per axis");
    CHECK(MSBDResizeGlyphKey(F(1, MSBD_RZ_TOP, 3)) != MSBDResizeGlyphKey(F(1, MSBD_RZ_LEFT, 3)) && MSBDResizeGlyphKey(F(1, MSBD_RZ_TOP, 1)) != MSBDResizeGlyphKey(F(1, MSBD_RZ_BOTTOM, 1)),
          "other glyphs, other keys");
    CHECK(MSBDResizeGlyphKey(none) == 0, "none: key 0");
}

// ---- glyphs against macOS ----
typedef struct { int w, h; unsigned char *black; } Mask;   // 8x, rows from the top
static const int S8 = 8;
static Mask MaskOfCursor(NSCursor *c) {
    NSSize sz = c.image.size; Mask m = { (int)ceil(sz.width * S8), (int)ceil(sz.height * S8), NULL };
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:m.w pixelsHigh:m.h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:32];
    rep.size = sz;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor colorWithWhite:0.5 alpha:1] set]; NSRectFill(NSMakeRect(0, 0, sz.width, sz.height));
    [c.image drawInRect:NSMakeRect(0, 0, sz.width, sz.height)];
    [NSGraphicsContext restoreGraphicsState];
    m.black = calloc((size_t)(m.w * m.h), 1);
    for (int y = 0; y < m.h; y++) for (int x = 0; x < m.w; x++) {
        NSUInteger p[4]; [rep getPixel:p atX:x y:y];
        m.black[y * m.w + x] = (p[0] + p[1] + p[2]) / 3.0 < 25;
    }
    return m;
}
// ours, in macOS points: hotspot at hot (+ cal)
static Mask MaskOfPath(CGPathRef path, int w, int h, CGPoint at, double scale) {
    Mask m = { w, h, calloc((size_t)(w * h), 1) };
    unsigned char *px = calloc((size_t)(w * h * 4), 1);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, (size_t)w, (size_t)h, 8, (size_t)w * 4, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 0.5, 0.5, 0.5, 1); CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGContextTranslateCTM(ctx, 0, h); CGContextScaleCTM(ctx, S8, -S8);   // (macOS points, y down)
    CGContextTranslateCTM(ctx, at.x, at.y); CGContextScaleCTM(ctx, scale, scale);
    CGContextAddPath(ctx, path); CGContextSetRGBFillColor(ctx, 0, 0, 0, 1); CGContextFillPath(ctx);
    for (int i = 0; i < w * h; i++) m.black[i] = (px[i * 4] + px[i * 4 + 1] + px[i * 4 + 2]) / 3.0 < 25;
    CGContextRelease(ctx); CGColorSpaceRelease(cs); free(px);
    return m;
}
static void BlackBox(Mask m, double *cx, double *cy, double *bw, double *bh) {
    int x0 = m.w, x1 = -1, y0 = m.h, y1 = -1;
    for (int y = 0; y < m.h; y++) for (int x = 0; x < m.w; x++) if (m.black[y * m.w + x]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) { *cx = *cy = *bw = *bh = -1; return; }
    *cx = (x0 + x1 + 1) / 2.0 / S8; *cy = (y0 + y1 + 1) / 2.0 / S8; *bw = (x1 + 1 - x0) / (double)S8; *bh = (y1 + 1 - y0) / (double)S8;
}
static double IoU(Mask a, Mask b) {
    long in = 0, un = 0;
    for (int i = 0; i < a.w * a.h; i++) { in += a.black[i] && b.black[i]; un += a.black[i] || b.black[i]; }
    return un ? (double)in / un : 0;
}
static void Glyphs(void) {
    if (@available(macOS 15.0, *)) {} else { printf("NOTICE: macOS 15 or later is needed for NSCursor's resize cursors: the glyph comparison is skipped\n"); return; }
    SEL fs = NSSelectorFromString(@"frameResizeCursorFromPosition:inDirections:"), cs = NSSelectorFromString(@"columnResizeCursorInDirections:"), rs = NSSelectorFromString(@"rowResizeCursorInDirections:");
    if (![NSCursor respondsToSelector:fs] || ![NSCursor respondsToSelector:cs] || ![NSCursor respondsToSelector:rs]) { printf("NOTICE: NSCursor's resize cursors not here: skipped\n"); return; }
    NSCursor *(*frame)(id, SEL, NSInteger, NSUInteger) = (void *)objc_msgSend;
    NSCursor *(*div)(id, SEL, NSUInteger) = (void *)objc_msgSend;
    // the calibration: macOS's arrow's hotspot sits before its black tip; our arrow's tip is our hotspot
    Mask am = MaskOfCursor(NSCursor.arrowCursor); int ax = am.w, ay = am.h;
    for (int y = 0; y < am.h; y++) for (int x = 0; x < am.w; x++) if (am.black[y * am.w + x]) { if (y < ay) ay = y; if (x < ax) ax = x; }
    double cal = ((ax + ay) / 2.0) / S8 - (NSCursor.arrowCursor.hotSpot.x + NSCursor.arrowCursor.hotSpot.y) / 2.0;
    CHECK(fabs(cal - 0.875) < 0.2, "the arrow's calibration %.3f (0.875 when measured)", cal);
    free(am.black);
    double worst = 1; int n = 0;
    for (int k = 0; k < 8 * 3 + 6; k++) {
        MSBDResizeFact f; NSCursor *c; NSString *name; double cl = cal;
        if (k < 24) { f = F(MSBD_RZ_FRAME, kPos[k / 3], (unsigned)(k % 3) + 1); c = frame(NSCursor.class, fs, (NSInteger)f.position, f.directions); name = [NSString stringWithFormat:@"frame p%u d%u", f.position, f.directions]; }
        else { unsigned dir = (unsigned)((k - 24) % 3) + 1; BOOL col = k < 27; f = F(col ? MSBD_RZ_COLUMN : MSBD_RZ_ROW, 0, dir); c = div(NSCursor.class, col ? cs : rs, dir); name = [NSString stringWithFormat:@"%@ d%u", col ? @"column" : @"row", dir]; cl = 0; }
        if (!c) { CHECK(0, "%s: macOS has no cursor", name.UTF8String); continue; }
#ifdef MSBD_RZ_FAIL_GLYPH
        if (k == 10) f.directions = f.directions == 1 ? 2 : 1;   // (made to fail: a one-way glyph the wrong way)
#endif
        CGPathRef p = MSBDResizeGlyphCreate(f);
        CHECK(p != NULL, "%s: a path", name.UTF8String);
        if (!p) continue;
        Mask mm = MaskOfCursor(c);
        Mask om = MaskOfPath(p, mm.w, mm.h, CGPointMake(c.hotSpot.x + cl, c.hotSpot.y + cl), 1.0 / MSBD_RZ_UNIT);
        double iou = IoU(mm, om), mx, my, mw, mh, ox, oy, ow, oh;
        BlackBox(mm, &mx, &my, &mw, &mh); BlackBox(om, &ox, &oy, &ow, &oh);
        double off = hypot(ox - mx, oy - my);
        printf("  %-16s IoU %.3f  black middle off by %.2f pt  (macOS %.2f x %.2f, ours %.2f x %.2f)\n", name.UTF8String, iou, off, mw, mh, ow, oh);
        CHECK(iou >= 0.85, "%s: IoU %.3f under 0.85", name.UTF8String, iou);
        CHECK(off <= 0.5, "%s: the black's middle %.2f pt from macOS's", name.UTF8String, off);
        if (iou < worst) worst = iou;
        n++;
        free(mm.black); free(om.black); CGPathRelease(p);
    }
    printf("glyphs: %d compared with macOS %s, worst IoU %.3f\n", n, NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String, worst);
}
// every glyph at Pointer Size 1 to 5 (as MacPointer draws it: x 1.12 x size, white edge 1.25, the arrow's shadow), over grey, 2x
static void Sheet(const char *dir) {
    if (!dir) return;
    int cols = 30; double cell = 26 * 1.12 * 5 + 10; int W = (int)(cols * cell * 2), H = (int)((5 * 10 + 26 * 1.12 * 15 + 40) * 2);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)W, (size_t)H, 8, 0, cs, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 0.55, 0.6, 0.7, 1); CGContextFillRect(ctx, CGRectMake(0, 0, W, H));
    CGContextTranslateCTM(ctx, 0, H); CGContextScaleCTM(ctx, 2, -2);
    double y = 0;
    for (int size = 1; size <= 5; size++) {
        double rowH = 16 + 26 * size * 1.12; y += rowH / 2 + 4;
        for (int k = 0; k < 30; k++) {
            MSBDResizeFact f = k < 24 ? F(MSBD_RZ_FRAME, kPos[k / 3], (unsigned)(k % 3) + 1) : F(k < 27 ? MSBD_RZ_COLUMN : MSBD_RZ_ROW, 0, (unsigned)((k - 24) % 3) + 1);
            CGPathRef p = MSBDResizeGlyphCreate(f); if (!p) continue;
            double s = 1.12 * size, step = 26 * 1.12 * size + 10;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, step * (k + 0.5), y); CGContextScaleCTM(ctx, s, s);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 1.6, [NSColor colorWithWhite:0 alpha:0.35].CGColor);
            CGContextAddPath(ctx, p); CGContextSetRGBFillColor(ctx, 0, 0, 0, 1); CGContextFillPath(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
            CGContextAddPath(ctx, p); CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1); CGContextSetLineWidth(ctx, 1.25); CGContextSetLineJoin(ctx, kCGLineJoinRound); CGContextStrokePath(ctx);
            CGContextSetRGBFillColor(ctx, 1, 0, 0, 1); CGContextFillRect(ctx, CGRectMake(-0.4 / s, -0.4 / s, 0.8 / s, 0.8 / s));   // (the hotspot)
            CGContextRestoreGState(ctx);
            CGPathRelease(p);
        }
        y += rowH / 2 + 4;
    }
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:img];
    NSString *out = [NSString stringWithFormat:@"%s/macresizecursor-sheet.png", dir];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:out atomically:YES];
    printf("sheet: %s\n", out.UTF8String);
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
}
// ---- Settings > Pointer > Mac Resize Pointers (1.8.9): the default per iPadOS, the user's choice, and the look while it is off ----
// 1.8.8.4's look (statusbar/macpointer/MacPointer.x MPUpdate at the release commit 182a8dc7, its own two lines when the .sh could cut them out).
static int Look1884(long long type, CGRect sb) {
#ifdef LOOK1884_INC
#include LOOK1884_INC
#else
    BOOL thin = !CGRectIsEmpty(sb) && MIN(sb.size.width, sb.size.height) <= 4.0;
    BOOL systemShape = thin || type == 4;   // (only the text beam: iPadOS 17/18's type 4, 15/16's thin type 3 -- every other style gets the arrow)
#endif
    return systemShape ? MSBD_PTR_BEAM : MSBD_PTR_ARROW;
}
static void Switch(void) {
    for (long os = 15; os <= 17; os++) CHECK(!MSBDResizePointersDefault(os) && !MSBDResizePointersOn(-1, os), "never set, iPadOS %ld: off", os);
    for (long os = 18; os <= 27; os++) CHECK(MSBDResizePointersDefault(os) && MSBDResizePointersOn(-1, os), "never set, iPadOS %ld: on", os);
    for (long os = 15; os <= 27; os++) CHECK(MSBDResizePointersOn(1, os) && !MSBDResizePointersOn(0, os), "the user's choice wins, iPadOS %ld", os);
    // what cfprefsd hands back: Settings' switch writes a boolean; a number as Settings would show it; anything else is the default
    CHECK(MSBDResizePointersStored(NULL) == -1, "nothing stored: the default");
    CHECK(MSBDResizePointersStored(kCFBooleanTrue) == 1 && MSBDResizePointersStored(kCFBooleanFalse) == 0, "a boolean: its value");
    // a number or a text: what Settings' switch shows for it (Foundation's own -boolValue, on this Mac), never the default
    NSArray *odd = @[@0, @1, @2, @(-1), @0.0, @0.25, @(NAN), @(INFINITY), @"YES", @"yes", @"NO", @"no", @"true", @"TRUE", @"false", @"t", @"Y", @"n", @"1", @"0",
                     @"00", @"007", @"-0", @"+1", @"-5", @"+-1", @" 1", @"\t1", @"  -0001", @"\n1", @"\r1", @"0x1", @"0.5", @".5", @"", @" ", @"abc", @"9lives",
                     @"0000000000000000000000000000000000000000000000000000000000000000001", @"                                                                1",
                     @"\u00a01", @"\u20031", @"\u30001", @"\u200b1", @"\u20281", @"\uff11"];
    int agree = 0;
    for (id o in odd) {
        int st = MSBDResizePointersStored((__bridge CFTypeRef)o);
        if (st == ([o boolValue] ? 1 : 0)) agree++; else printf("  differs from -boolValue: [%s] stored %d, boolValue %d\n", [[o description] UTF8String], st, [o boolValue]);
    }
    CHECK(agree == (int)odd.count, "a number or a text: as Settings' switch shows it (-boolValue), %d of %lu", agree, (unsigned long)odd.count);
    CHECK(MSBDResizePointersStored((__bridge CFTypeRef)@[@YES]) == -1 && MSBDResizePointersStored((__bridge CFTypeRef)[NSDate date]) == -1 && MSBDResizePointersStored((__bridge CFTypeRef)@{}) == -1,
          "an array, a date, a dictionary: the default");
    CHECK(!MSBDResizePointersOn(MSBDResizePointersStored(kCFBooleanFalse), 18) && MSBDResizePointersOn(MSBDResizePointersStored(kCFBooleanTrue), 15),
          "turned off on iPadOS 18: off; turned on on 15: on");
    CHECK(MSBD_RZ_CONFIG_BIT == 16 && !(MSBD_RZ_CONFIG_BIT & (1 | 4 | 8 | 0xFF00)), "the config word's bit 4: none of the bridge's other bits (Pointer Style, the auto-hiding bar, Pointer Control Style, the size)");
    CHECK(strcmp(MSBD_RZ_PREF_KEY, "macPointerResizePointers") == 0, "the key in our preferences");
    // off: 1.8.8.4's look, shape by shape (every type, bounds sizes either way round incl. zero, negative, not a number, infinite; null, infinite)
    const long long types[] = { -1, 0, 1, 2, 3, 4, 5, 9 };
    const double sz[] = { 0, -0.0, -3, 0.5, 2, 3, 3.9999, 4, 4.0001, 5.5, 6, 13.96, 20, 24, 25.82, 35, 41, 182, NAN, INFINITY, -INFINITY };
    const size_t nt = sizeof types / sizeof *types, ns = sizeof sz / sizeof *sz;
    int n = 0, same = 0;
    for (size_t t = 0; t < nt; t++) {
        CGRect special[] = { CGRectNull, CGRectInfinite, CGRectZero, CGRectMake(-50, 1e9, 3, 24) };
        for (size_t k = 0; k < 4; k++) { n++; if (MSBDPointerLook1884(types[t], special[k]) == Look1884(types[t], special[k])) same++; else printf("  differs: type %lld special %zu\n", types[t], k); }
        for (size_t i = 0; i < ns; i++) for (size_t j = 0; j < ns; j++) {
            CGRect r = CGRectMake(i % 3 ? 10 : -7, j % 2 ? 0 : 300, sz[i], sz[j]);
            n++;
            if (MSBDPointerLook1884(types[t], r) == Look1884(types[t], r)) same++;
            else printf("  differs: type %lld %g x %g\n", types[t], sz[i], sz[j]);
        }
    }
    CHECK(n == same && n > 3000, "off: 1.8.8.4's look for every shape (%d of %d the same)", same, n);
    CHECK(MSBDPointerLook1884(4, CGRectMake(0, 0, 35, 13.96)) == MSBD_PTR_BEAM && MSBDPointerLook1884(4, CGRectMake(0, 0, 25.82, 25.82)) == MSBD_PTR_BEAM,
          "off, iPadOS 18.5's band: iPadOS's own resize shape there, as in 1.8.8.4");
    CHECK(MSBDPointerLook1884(3, CGRectMake(0, 0, 3, 24)) == MSBD_PTR_BEAM && MSBDPointerLook1884(4, CGRectZero) == MSBD_PTR_BEAM && MSBDPointerLook1884(1, CGRectZero) == MSBD_PTR_ARROW
          && MSBDPointerLook1884(3, CGRectMake(0, 0, 20, 20)) == MSBD_PTR_ARROW, "off: the text beams iPadOS's, the round pointer and a control's highlight our arrow, as in 1.8.8.4");
#ifdef LOOK1884_INC
    printf("switch: 1.8.8.4's look from its own lines (182a8dc7)\n");
#else
    printf("NOTICE switch: 1.8.8.4's look from the test's copy of its lines (182a8dc7 not in this checkout's history)\n");
#endif
}
int main(int argc, char **argv) { @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    [NSApplication sharedApplication];   // (NSCursor's images; no window, no menu, nothing shown)
    Rules();
    Switch();
    Glyphs();
    Sheet(argc > 1 ? argv[1] : NULL);
    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
} }
