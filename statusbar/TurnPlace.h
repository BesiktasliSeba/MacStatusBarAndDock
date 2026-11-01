// TurnPlace.h -- one rule for every engine when the screen changes shape, and when Fit to Window ends (1.7.4 items 4, 5, 7, 11, 14). Plain C on
// CoreGraphics, so the Mac test (tools/test-turnplace.c) runs this very code. StatusBar.x calls it from each engine's own turn handling: Aerial,
// Zetsu and MilkyWay4 (DMRelayoutForOrientation, also for a Mac Switcher desktop that comes back turned) and our Stage Manager engine (DMSMWatchTurn
// for the stage on screen, DMSMFitHiddenStages for the stages that are not: other desktops, minimized windows).
// Where a window goes when the iPad turns (portrait <-> landscape), in this order:
//  1. Fit to Window's tiles are tiled again for the new shape (each engine's Fit, as before);
//  2. a window in a layout -- Fill, a half, a quarter: the Window menu's places, as the layouts were while the iPad was still -- goes into the same
//     layout of the new shape (Stage Manager did it since 1.3; the other engines scaled it: a left half came back 2-14 pt off its half, item 5);
//  3. any other window goes back where it was the last time the screen had that shape (the other engines did it; Stage Manager kept the size it
//     was squeezed to: a tall Clock 1248 pt in portrait came back 883 pt tall after a landscape round trip, item 7);
//  4. else it keeps its size and place in proportion (the other engines scale it; Stage Manager does it itself), always inside the desktop.
// Fit to Window switched off (item 4): every engine spreads the tiled windows back to a normal window size, as a Mac does when tiling ends -- a
// window leaving a tiled arrangement on macOS returns to a free window of its own size --; Aerial, Zetsu and MilkyWay4 did it, Stage Manager kept
// them tiled. The windows go to the Window menu's Medium size, from the desktop's top-left corner (the oldest, at the back) to its bottom-right
// corner (the newest, in front), each one's title bar showing above the next one's.
#ifndef MSBD_TURN_PLACE_H
#define MSBD_TURN_PLACE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <math.h>

#define kMSBDTurnLayoutCount 9
#define kMSBDTurnLayoutTolerance 6.0   // (a window counts as in a layout within 6 pt on each side: the Window menu's tick, DMCurrentLayoutName)
// The layouts a turn puts a window back into (the Window menu's places that are cut from the desktop's edges; the centred sizes scale anyway).
static const char *const kMSBDTurnLayouts[kMSBDTurnLayoutCount] = { "fill", "left", "right", "top", "bottom", "topleft", "topright", "bottomleft", "bottomright" };

// The layout a window's frame is in: the index of the first of the n layout frames (kMSBDTurnLayouts' order, as the screen is now) that f matches
// within tol on its four numbers, else -1. A null or empty layout frame never matches.
static inline int MSBDTurnLayoutIndex(CGRect f, const CGRect *layouts, int n, CGFloat tol) {
    if (CGRectIsNull(f) || CGRectIsEmpty(f) || !layouts) return -1;
    for (int i = 0; i < n; i++) {
        CGRect t = layouts[i];
        if (CGRectIsNull(t) || CGRectIsEmpty(t)) continue;
        if (fabs(t.origin.x - f.origin.x) < tol && fabs(t.origin.y - f.origin.y) < tol && fabs(t.size.width - f.size.width) < tol && fabs(t.size.height - f.size.height) < tol) return i;
    }
    return -1;
}

// Where a window goes when the screen has turned (the rule above, steps 2-4; step 1 is each engine's Fit). layoutNew: its layout's frame in the new
// shape (CGRectNull: it was in no layout); remembered: where it was the last time the screen had the new shape (CGRectNull: never, or not known);
// proportional: its old frame in proportion to the new shape (CGRectNull: the engine keeps it in proportion itself -- Stage Manager). *why: 2, 3, 4
// (the step taken), 0 when none gives a frame (the caller leaves the window to the engine and keeps it inside the desktop). The caller fits the
// answer into the desktop (each engine's own fit: never bigger than it, never smaller than a window may be).
enum { MSBDTurnNone = 0, MSBDTurnLayout = 2, MSBDTurnRemembered = 3, MSBDTurnProportional = 4 };
static inline CGRect MSBDTurnPlaceFor(CGRect layoutNew, CGRect remembered, CGRect proportional, int *why) {
    int w = MSBDTurnNone; CGRect r = CGRectNull;
    if (!CGRectIsNull(layoutNew) && !CGRectIsEmpty(layoutNew)) { r = layoutNew; w = MSBDTurnLayout; }
    else if (!CGRectIsNull(remembered) && !CGRectIsEmpty(remembered)) { r = remembered; w = MSBDTurnRemembered; }
    else if (!CGRectIsNull(proportional) && !CGRectIsEmpty(proportional)) { r = proportional; w = MSBDTurnProportional; }
    if (why) *why = w;
    return r;
}
// A window a turn put back where it was in this shape (step 3) was in no layout before the turn, and that place can be a layout's frame (a window set
// free after a turn round trip as a quarter: its place in the other shape is still the quarter's). While it stays at the frame the turn gave it, it is
// still in no layout -- taken for the quarter, the next turn put it into that quarter's layout instead of back at its free place (1.7.5 item 14,
// 1.7.4 R2 F1: Tips free at {174, 108} in landscape came back as the bottom-right quarter after P -> L). i: the layout its frame matches now
// (MSBDTurnLayoutIndex); placed: the frame the turn gave it (CGRectNull: none). Returns the layout to note; *keep: whether it is still there (the
// record stays) -- moved or laid out since, the record goes and its frame tells again.
#define kMSBDTurnPlacedTolerance 2.0   // (still where the turn put it: within 2 pt on each number -- the engines' own rounding of a place)
static inline int MSBDTurnNoteIndex(CGRect f, int i, CGRect placed, CGFloat tol, bool *keep) {
    bool still = !CGRectIsNull(placed) && !CGRectIsEmpty(placed) && !CGRectIsNull(f) && fabs(f.origin.x - placed.origin.x) < tol && fabs(f.origin.y - placed.origin.y) < tol
                 && fabs(f.size.width - placed.size.width) < tol && fabs(f.size.height - placed.size.height) < tol;
    if (keep) *keep = still;
    return still ? -1 : i;
}
static inline const char *MSBDTurnWhyText(int w) {
    return w == MSBDTurnLayout ? "its layout" : w == MSBDTurnRemembered ? "where it was in this shape" : w == MSBDTurnProportional ? "in proportion" : "left to the engine";
}

// Fit to Window off: the i-th of n windows spread (i = 0 the oldest: the desktop's top-left corner; i = n - 1 the newest: its bottom-right corner),
// each `size` big (the Medium layout's), on a diagonal across the desktop u -- whole points. n = 1: the top-left corner.
static inline CGRect MSBDSpreadFrame(int i, int n, CGRect u, CGSize size) {
    if (n < 1 || i < 0 || i >= n || CGRectIsNull(u) || CGRectIsEmpty(u) || !(size.width > 0) || !(size.height > 0)) return CGRectNull;
    CGFloat dx = fmax(0.0, u.size.width - size.width), dy = fmax(0.0, u.size.height - size.height);
    CGFloat t = n > 1 ? (CGFloat)i / (CGFloat)(n - 1) : 0.0;
    return CGRectMake(round(u.origin.x + dx * t), round(u.origin.y + dy * t), size.width, size.height);
}

// The saved windows across an engine switch (item 14): Aerial 5.x keeps a STAGE frame per window -- the drawn window (our 24 pt title bar and the
// app) grown by Aerial's own margins around the app (top, left, bottom, right; 13 / 6 / 20 / 6 on the iPad 2, 13 / 6 / 12 / 6 on the M1) and drawn
// `shift` points lower (24 - top: the title bar is taller than Aerial's strip) -- while Zetsu, MilkyWay4 and Aerial 3.0 keep the window itself. The
// saved state names which kind its frames are (with the margins it was saved with); a frame of the other kind is turned into this engine's: after
// Aerial -> Zetsu the Zetsu windows came back with Aerial's stage frames, 12 pt wider and 9 pt taller, overlapping by 6.
typedef struct { CGFloat top, left, bottom, right; } MSBDStageMargins;
static inline CGFloat MSBDStageShiftFor(MSBDStageMargins m) { return fmax(0.0, 24.0 - m.top); }
static inline CGRect MSBDWindowFromStageFrame(CGRect f, MSBDStageMargins m) {
    if (CGRectIsNull(f)) return f;
    return CGRectMake(f.origin.x + m.left, f.origin.y - 24.0 + m.top + MSBDStageShiftFor(m), f.size.width - m.left - m.right, f.size.height + 24.0 - m.top - m.bottom);
}
static inline CGRect MSBDStageFromWindowFrame(CGRect r, MSBDStageMargins m) {
    if (CGRectIsNull(r)) return r;
    return CGRectMake(r.origin.x - m.left, r.origin.y + 24.0 - m.top - MSBDStageShiftFor(m), r.size.width + m.left + m.right, r.size.height - 24.0 + m.top + m.bottom);
}
// A saved frame for the engine running now. savedStage / nowStage: whether the frame was saved as an Aerial 5.x stage frame / this engine's frames
// are; the margins of each. The same kind: the frame as it was saved (byte for byte, as every restore before 1.7.4 -- the same engine, the same
// margins). *converted: whether it was turned.
static inline CGRect MSBDSavedFrameForEngine(CGRect f, bool savedStage, MSBDStageMargins savedM, bool nowStage, MSBDStageMargins nowM, bool *converted) {
    if (converted) *converted = false;
    if (CGRectIsNull(f) || savedStage == nowStage) return f;
    if (converted) *converted = true;
    return savedStage ? MSBDWindowFromStageFrame(f, savedM) : MSBDStageFromWindowFrame(f, nowM);
}
#endif
