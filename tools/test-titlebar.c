// test-titlebar.c -- Mac test of statusbar/TitleBarRule.h (1.8.3 item 8): a double tap on a window's title bar as macOS's "Double-click a
// window's title bar to" -- the four choices, Zoom when never set (AppKit's own default), Fill and Zoom and their way back; Zoom keeping the
// window's shape (1.8.4.1 item 1). Run by test-titlebar.sh.
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <CoreGraphics/CoreGraphics.h>
#include "../statusbar/TitleBarRule.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }

// ---- review 1.8.3 P4-1: the frame from before kept in step with every placement of ours (MSBDTitleRecordOnPlace / MSBDTitleRecordHolds) ----
// A small model of one window: where it is (a frame by name), its frame from before and the Fill frame that was kept with, and the Fill frame
// where it is now (a turn changes it). Each path of the tweak's code is one of these calls: the title bar's double tap, a placement of ours (the
// Window menu, the window keys, the window API, Center, Return to Previous Size, the arrangements, Swap, Fit to Window), a move by hand, and a
// move of the engine's own that runs no code of ours.
// (1.8.4.1 item 1) Zoom's frame of each place, as MSBDTitleZoomFrame gives it (checked on real frames below): F_Z<x> is <x> grown to fit with its
// shape, centred; a frame shaped like the desktop (Fill) zooms to itself, and so does a zoomed frame (it is its own zoomed frame).
enum { F_NONE = 0, F_A, F_B, F_HALF, F_TILE, F_FILL, F_FILL2, F_M, F_ZA, F_ZB, F_ZHALF, F_ZTILE, F_ZM };
static int ZoomOf(int f) {
    switch (f) {
        case F_A: return F_ZA;
        case F_B: return F_ZB;
        case F_HALF: return F_ZHALF;
        case F_TILE: return F_ZTILE;
        case F_M: return F_ZM;
        default: return f;   // (Fill, and every zoomed frame: their own)
    }
}
typedef struct { int at, before, keptFill, fill, setting; } Win;
// (the record kept with frame k -- Fill's, or the title bar's zoomed frame -- and a placement to `to`: WindowKeys.h DMTitleRecordView)
static void Record(Win *w, int to, int k) {
    bool stays = w->before != F_NONE && to == w->keptFill && w->at == w->keptFill;
    switch (MSBDTitleRecordOnPlaceAt(MSBDTitleKeepsFrames(w->setting), to == k, w->at == k, stays)) {
        case kMSBDTitleRecordTake: w->before = w->at; w->keptFill = k; break;
        case kMSBDTitleRecordDrop: w->before = F_NONE; w->keptFill = F_NONE; break;
        default: break;
    }
    w->at = to;
}
static void Place(Win *w, int to) { Record(w, to, w->fill); }   // (any placement of ours, before it moves the window)
static void ZoomTo(Win *w, int z) { Record(w, z, z); }   // (the title bar's own Zoom: its zoomed frame is the frame its record is kept with)
static void ByHand(Win *w, int to) { w->before = F_NONE; w->keptFill = F_NONE; w->at = to; }   // (DMTitleRecordMovedView / ...SM)
static void EngineOwn(Win *w, int to) { w->at = to; }   // (no code of ours runs)
static void DoubleTap(Win *w) {
    int holds = MSBDTitleRecordHolds(w->before != F_NONE, w->at == w->keptFill);
    if (!holds) { w->before = F_NONE; w->keptFill = F_NONE; }   // (DMTitleRecordHeld...: a frame that no longer holds is dropped)
    int action = MSBDTitleActionFor(w->setting, false);
    int target = action == kMSBDTitleZoom ? ZoomOf(w->at) : w->fill;   // (TitleBarTap.h: Fill's frame, or the zoomed frame of where it is)
    int step = MSBDTitleStep(action, w->at == target, holds);
    if (step == kMSBDTitleBack) Place(w, w->before);
    else if (step == kMSBDTitleToFill) Place(w, w->fill);
    else if (step == kMSBDTitleToZoom) ZoomTo(w, target);
}
static Win Fresh(int at) { Win w = { at, F_NONE, F_NONE, F_FILL, kMSBDTitleFill }; return w; }
static Win FreshZoom(int at) { Win w = Fresh(at); w.setting = kMSBDTitleZoom; return w; }
// ---- Zoom's frame on real frames (MSBDTitleZoomFrame) ----
static int Frame(const char *what, CGRect got, CGRect want) {
    checks++;
    int ok = (CGRectIsNull(got) && CGRectIsNull(want)) || CGRectEqualToRect(got, want);
    if (ok) printf("PASS  %s\n", what);
    else { fails++; printf("FAIL  %s (got {%g, %g, %g, %g}, want {%g, %g, %g, %g})\n", what, got.origin.x, got.origin.y, got.size.width, got.size.height, want.origin.x, want.origin.y, want.size.width, want.size.height); }
    return ok;
}
static int Inside(CGRect f, CGRect d) { return f.origin.x >= d.origin.x - 0.001 && f.origin.y >= d.origin.y - 0.001 && CGRectGetMaxX(f) <= CGRectGetMaxX(d) + 0.001 && CGRectGetMaxY(f) <= CGRectGetMaxY(d) + 0.001; }
int main(void) {
    Int("never set: its own state (KT, 7 Nov: review 1.8.3 P2-3)", MSBDTitleActionFromStored(NULL), kMSBDTitleNeverSet);
    Int("  ... an app's window does nothing, on every engine (as 1.8.2.2)", MSBDTitleActionFor(kMSBDTitleNeverSet, false), kMSBDTitleNothing);
    Int("  ... our own windows (Finder, TextEdit) zoom, as their title bar always did", MSBDTitleActionFor(kMSBDTitleNeverSet, true), kMSBDTitleZoom);
    Int("a choice made: every window follows it (Zoom, Do Nothing, Fill, Minimize)", MSBDTitleActionFor(kMSBDTitleZoom, false) == kMSBDTitleZoom && MSBDTitleActionFor(kMSBDTitleNothing, true) == kMSBDTitleNothing
        && MSBDTitleActionFor(kMSBDTitleFill, false) == kMSBDTitleFill && MSBDTitleActionFor(kMSBDTitleMinimize, true) == kMSBDTitleMinimize, 1);
    Int("stored fill: Fill", MSBDTitleActionFromStored("fill"), kMSBDTitleFill);
    Int("stored zoom: Zoom", MSBDTitleActionFromStored("zoom"), kMSBDTitleZoom);
    Int("stored minimize: Minimize", MSBDTitleActionFromStored("minimize"), kMSBDTitleMinimize);
    Int("stored none: Do Nothing", MSBDTitleActionFromStored("none"), kMSBDTitleNothing);
    Int("anything else: as never set (the defaults)", MSBDTitleActionFromStored("Fill"), kMSBDTitleNeverSet);
    Int("four choices, as macOS 15's: Fill, Zoom, Minimize, Do Nothing", kMSBDTitleCount, 4);
    Int("  ... named as Apple names them", !strcmp(MSBDTitleActionName(kMSBDTitleFill), "Fill") && !strcmp(MSBDTitleActionName(kMSBDTitleZoom), "Zoom")
        && !strcmp(MSBDTitleActionName(kMSBDTitleMinimize), "Minimize") && !strcmp(MSBDTitleActionName(kMSBDTitleNothing), "Do Nothing"), 1);
    Int("Fill on a window in no tile: to Fill", MSBDTitleStep(kMSBDTitleFill, false, false), kMSBDTitleToFill);
    Int("  ... again, at Fill with its frame from before: back (as a Mac toggles)", MSBDTitleStep(kMSBDTitleFill, true, true), kMSBDTitleBack);
    Int("  ... at Fill with no frame from before (it opened there): it stays", MSBDTitleStep(kMSBDTitleFill, true, false), kMSBDTitleToFill);
    Int("  ... moved off Fill by hand since: to Fill again", MSBDTitleStep(kMSBDTitleFill, false, true), kMSBDTitleToFill);
    Int("Zoom: to its zoomed frame (its shape kept, not Fill: 1.8.4.1 item 1), then back", MSBDTitleStep(kMSBDTitleZoom, false, false) == kMSBDTitleToZoom && MSBDTitleStep(kMSBDTitleZoom, true, true) == kMSBDTitleBack, 1);
    Int("  ... at its zoomed frame with no frame from before (it opened there): it stays", MSBDTitleStep(kMSBDTitleZoom, true, false), kMSBDTitleToZoom);
    Int("  ... Fill stays Fill: edge to edge", MSBDTitleStep(kMSBDTitleFill, false, false), kMSBDTitleToFill);
    Int("  ... Fill's and Zoom's frame from before taken at every fill from a frame that is not Fill -- free, a half, a Fit to Window tile: back to it (1.8.3 regression F2)", MSBDTitleBackTakes(false), 1);
    Int("  ... not at Fill already (nothing to keep)", MSBDTitleBackTakes(true), 0);
    Int("  ... a window in a tile filled, then the double tap again: back (the tile's frame kept)", MSBDTitleStep(kMSBDTitleFill, true, MSBDTitleBackTakes(false)), kMSBDTitleBack);
    Int("Minimize: minimized", MSBDTitleStep(kMSBDTitleMinimize, true, true), kMSBDTitleDoMinimize);
    Int("Do Nothing: nothing", MSBDTitleStep(kMSBDTitleNothing, false, false), kMSBDTitleDoNothing);
    Int("the frames from before kept for Fill and Zoom", MSBDTitleKeepsFrames(kMSBDTitleFill) && MSBDTitleKeepsFrames(kMSBDTitleZoom), 1);
    Int("  ... not for Minimize, Do Nothing or never set (dropped)", MSBDTitleKeepsFrames(kMSBDTitleMinimize) || MSBDTitleKeepsFrames(kMSBDTitleNothing) || MSBDTitleKeepsFrames(kMSBDTitleNeverSet), 0);
    Int("a double tap with SpringBoard free: now", MSBDTitleTapWhen(false, false, 0), kMSBDTitleTapNow);
    Int("  ... in a transition (its own first tap brought the window forward): it waits", MSBDTitleTapWhen(true, true, 0), kMSBDTitleTapWait);
    Int("  ... and acts once it is over", MSBDTitleTapWhen(false, false, 7), kMSBDTitleTapNow);
    Int("  ... two seconds at most (a tenth at a time)", MSBDTitleTapWhen(true, true, kMSBDTitleTapMaxTries) == kMSBDTitleTapGiveUp && MSBDTitleTapWhen(true, true, kMSBDTitleTapMaxTries - 1) == kMSBDTitleTapWait
        && (int)(kMSBDTitleTapMaxTries * kMSBDTitleTapWaitSeconds * 10 + 0.5) == 20, 1);
    Int("  ... the Lock Screen, a switcher or a menu of ours: refused at once", MSBDTitleTapWhen(true, false, 0), kMSBDTitleTapGiveUp);
    // ---- P4-1: the rule ----
    Int("a placement of ours to Fill from a frame that is not Fill: that frame kept as the way back", MSBDTitleRecordOnPlace(true, true, false), kMSBDTitleRecordTake);
    Int("  ... to Fill where it is already: kept as it was", MSBDTitleRecordOnPlace(true, true, true), kMSBDTitleRecordKeep);
    Int("  ... anywhere else (a half, a tile, Center, Return to Previous Size): dropped", MSBDTitleRecordOnPlace(true, false, true) == kMSBDTitleRecordDrop && MSBDTitleRecordOnPlace(true, false, false) == kMSBDTitleRecordDrop, 1);
    Int("  ... a setting that keeps no frames: dropped, whatever the placement", MSBDTitleRecordOnPlace(false, true, false) == kMSBDTitleRecordDrop && MSBDTitleRecordOnPlace(false, true, true) == kMSBDTitleRecordDrop, 1);
    Int("a frame from before holds while the window is at the Fill it was kept with", MSBDTitleRecordHolds(true, true), 1);
    Int("  ... not once it is elsewhere (the engine's own move, a turn, the Dock), nor without one", MSBDTitleRecordHolds(true, false) || MSBDTitleRecordHolds(false, true), 0);
    // ---- P4-1: each path, as the review's examples ----
    Win w = Fresh(F_A); DoubleTap(&w);
    Int("the title bar's Fill from A: at Fill, A kept", w.at == F_FILL && w.before == F_A, 1);
    Place(&w, F_HALF); Place(&w, F_FILL); DoubleTap(&w);
    Int("  ... then Globe-Control-Left and Globe-Control-F (or the Window menu's, the window API's): a double tap goes back to the half, not to A (P4-1)", w.at, F_HALF);
    w = Fresh(F_A); DoubleTap(&w); ByHand(&w, F_B); Place(&w, F_FILL); DoubleTap(&w);
    Int("the title bar's Fill, a move by hand, the Window menu's Fill: back to where the hand put it (the review's row)", w.at, F_B);
    w = Fresh(F_A); DoubleTap(&w); ByHand(&w, F_B); EngineOwn(&w, F_FILL); DoubleTap(&w);
    Int("the title bar's Fill, a move by hand, then the engine's own maximize to our Fill: no way back to A, two moves ago -- it stays at Fill", w.at == F_FILL && w.before == F_NONE, 1);
    w = Fresh(F_A); DoubleTap(&w); EngineOwn(&w, F_M); DoubleTap(&w);
    Int("the engine's own move off Fill (to its own maximize): the double tap fills from there, and goes back there next", w.at == F_FILL && w.before == F_M, 1);
    DoubleTap(&w);
    Int("  ... back to the engine's frame", w.at, F_M);
    w = Fresh(F_A); DoubleTap(&w); EngineOwn(&w, F_M); EngineOwn(&w, F_FILL); DoubleTap(&w);
    Int("left (TitleBarRule.h): the engine's own move off our very Fill frame and back to it, no hand between, still goes back to A", w.at, F_A);
    w = Fresh(F_A); DoubleTap(&w); Place(&w, F_FILL); DoubleTap(&w);
    Int("a Fill of ours while at Fill (Center at its size, the Window menu's Fill again): the frame kept, back to A", w.at, F_A);
    w = Fresh(F_A); DoubleTap(&w); Place(&w, F_A); DoubleTap(&w);
    Int("Return to Previous Size from the title bar's Fill: dropped there, so the next double tap fills again", w.at == F_FILL && w.before == F_A, 1);
    w = Fresh(F_TILE); Place(&w, F_FILL); DoubleTap(&w);
    Int("Fit to Window fills its one window from a tile: a double tap goes back to the tile", w.at, F_TILE);
    w = Fresh(F_A); DoubleTap(&w); Place(&w, F_TILE); EngineOwn(&w, F_FILL); DoubleTap(&w);
    Int("Fit to Window tiles a filled window (dropped), then the engine fills it: no way back to A", w.at == F_FILL && w.before == F_NONE, 1);
    w = Fresh(F_A); DoubleTap(&w); w.fill = F_FILL2; EngineOwn(&w, F_FILL2); DoubleTap(&w);
    Int("a turn (the Fill frame is another now): the frame from before no longer holds -- dropped, it stays at the new Fill", w.at == F_FILL2 && w.before == F_NONE, 1);
    w = Fresh(F_A); DoubleTap(&w); w.fill = F_FILL2; EngineOwn(&w, F_FILL2); w.fill = F_FILL; EngineOwn(&w, F_FILL); DoubleTap(&w);
    Int("  ... turned back before any double tap: it holds again, back to A", w.at, F_A);
    w = Fresh(F_A); DoubleTap(&w); w.setting = kMSBDTitleMinimize; Place(&w, F_HALF); Place(&w, F_FILL); w.setting = kMSBDTitleFill; DoubleTap(&w);
    Int("placements made while the setting keeps no frames drop it: Fill chosen again, no way back to A", w.at == F_FILL && w.before == F_NONE, 1);
    w = Fresh(F_A); w.setting = kMSBDTitleZoom; DoubleTap(&w); Place(&w, F_HALF); Place(&w, F_FILL); DoubleTap(&w);
    Int("Zoom's record the same: back to the half", w.at, F_HALF);
    // ---- 1.8.4.1 item 1: Zoom keeps the window's shape (KT 7 Nov ~21:50); both go back ----
    w = FreshZoom(F_A); DoubleTap(&w);
    Int("Zoom from A: at A's zoomed frame (its shape, centred), not at Fill; A kept", w.at == F_ZA && w.before == F_A, 1);
    DoubleTap(&w);
    Int("  ... a second double tap: back to A", w.at == F_A && w.before == F_NONE, 1);
    w = Fresh(F_A); DoubleTap(&w);
    Int("Fill from A: edge to edge (Fill, not A's zoomed frame)", w.at, F_FILL);
    w = FreshZoom(F_HALF); DoubleTap(&w); DoubleTap(&w);
    Int("Zoom from a half: zoomed, then back to the half", w.at, F_HALF);
    w = FreshZoom(F_FILL); DoubleTap(&w);
    Int("Zoom on a window at Fill with no frame from before (shaped like the desktop): it stays at Fill", w.at == F_FILL && w.before == F_NONE, 1);
    w = FreshZoom(F_A); Place(&w, F_FILL); DoubleTap(&w);
    Int("the Window menu's Fill, then Zoom: Fill is its own zoomed frame, so back to A", w.at, F_A);
    w = FreshZoom(F_A); DoubleTap(&w); Place(&w, F_FILL); DoubleTap(&w);
    Int("Zoom, then the Window menu's Fill (or the window keys', the window API's): a double tap goes back to the zoomed frame, the frame before Fill", w.at, F_ZA);
    w = FreshZoom(F_A); DoubleTap(&w); Place(&w, F_ZA); DoubleTap(&w);
    Int("Zoom, then Center at its size (a zoomed window is centred already: nothing moves): its record kept, back to A", w.at, F_A);
    w = FreshZoom(F_A); DoubleTap(&w); Place(&w, F_HALF); DoubleTap(&w);
    Int("Zoom, then a half of ours: dropped there; Zoom zooms the half", w.at == F_ZHALF && w.before == F_HALF, 1);
    w = FreshZoom(F_A); DoubleTap(&w); ByHand(&w, F_B); DoubleTap(&w);
    Int("Zoom, then a move by hand: dropped; Zoom zooms from where the hand put it", w.at == F_ZB && w.before == F_B, 1);
    DoubleTap(&w);
    Int("  ... and back there", w.at, F_B);
    w = FreshZoom(F_A); DoubleTap(&w); EngineOwn(&w, F_M); DoubleTap(&w);
    Int("Zoom, then the engine's own move: Zoom zooms from the engine's frame, and goes back there next", w.at == F_ZM && w.before == F_M, 1);
    w = FreshZoom(F_A); DoubleTap(&w); Place(&w, F_TILE); EngineOwn(&w, F_ZA); DoubleTap(&w);
    Int("Zoom, then Fit to Window tiles it (dropped), then the engine puts it at the zoomed frame: no way back to A, it stays", w.at == F_ZA && w.before == F_NONE, 1);
    w = FreshZoom(F_A); DoubleTap(&w); w.setting = kMSBDTitleMinimize; Place(&w, F_ZA); w.setting = kMSBDTitleZoom; DoubleTap(&w);
    Int("placements made while the setting keeps no frames drop Zoom's too", w.at == F_ZA && w.before == F_NONE, 1);
    Int("a placement to the frame the record was kept with, where the window is: kept (the zoomed frame, and Fill as before)", MSBDTitleRecordOnPlaceAt(true, false, false, true) == kMSBDTitleRecordKeep
        && MSBDTitleRecordOnPlaceAt(true, true, true, true) == kMSBDTitleRecordKeep, 1);
    Int("  ... not while the setting keeps no frames", MSBDTitleRecordOnPlaceAt(false, false, false, true), kMSBDTitleRecordDrop);
    Int("  ... otherwise as before: to Fill from elsewhere taken, anywhere else dropped", MSBDTitleRecordOnPlaceAt(true, true, false, false) == kMSBDTitleRecordTake
        && MSBDTitleRecordOnPlaceAt(true, false, true, false) == kMSBDTitleRecordDrop && MSBDTitleRecordOnPlaceAt(true, true, true, false) == kMSBDTitleRecordKeep, 1);
    // ---- Zoom's frame (MSBDTitleZoomFrame): the M1's landscape desktop, 1194 x 834, under the 24 pt menu bar, above a Dock 76 pt tall ----
    CGRect desk = CGRectMake(0, 24, 1194, 734);
    CGSize min = CGSizeMake(320, 324);   // (WindowMinSize.h: the app 320 x 300 under our 24 pt bar)
    Frame("a 3:2 window grows until it reaches the desktop's top and bottom, its shape kept, centred across", MSBDTitleZoomFrame(CGRectMake(100, 100, 600, 400), desk, min), CGRectMake(47, 24, 1101, 734));
    Frame("a tall window: as tall as the desktop, centred across", MSBDTitleZoomFrame(CGRectMake(200, 100, 400, 700), desk, min), CGRectMake(388, 24, 419, 734));
    Frame("a wide window: as wide as the desktop, centred down", MSBDTitleZoomFrame(CGRectMake(0, 300, 1000, 330), desk, min), CGRectMake(0, 194, 1194, 394));
    Frame("a window shaped like the desktop: Fill exactly", MSBDTitleZoomFrame(CGRectMake(10, 30, 597, 367), desk, min), desk);
    Frame("a left half (as tall as the desktop already): centred at its size", MSBDTitleZoomFrame(CGRectMake(0, 24, 594, 734), desk, min), CGRectMake(300, 24, 594, 734));
    Frame("a window bigger than the desktop (after a turn): shrunk to fit, its shape kept", MSBDTitleZoomFrame(CGRectMake(0, 0, 1300, 900), desk, min), CGRectMake(67, 24, 1060, 734));
    Frame("a very wide, low window: its height grown to the smallest a window may be (the shape gives way only there), centred", MSBDTitleZoomFrame(CGRectMake(0, 0, 1194, 200), desk, min), CGRectMake(0, 229, 1194, 324));
    Frame("the Dock at the left side (its strip kept out): inside the desktop beside it", MSBDTitleZoomFrame(CGRectMake(200, 100, 600, 400), CGRectMake(90, 24, 1104, 810), min), CGRectMake(90, 61, 1104, 736));
    Frame("Stage Manager's stage area (a TV's, or the iPad's with the Dock hiding itself): the same rule", MSBDTitleZoomFrame(CGRectMake(300, 200, 640, 480), CGRectMake(0, 24, 1920, 1032), CGSizeMake(320, 324)), CGRectMake(272, 24, 1376, 1032));
    Frame("a desktop with a fractional height (the Dock measured): reached exactly, top to bottom", MSBDTitleZoomFrame(CGRectMake(100, 100, 400, 600), CGRectMake(0, 24, 1024, 919.2), min), CGRectMake(206, 24, 613, 919.2));
    Frame("no window, or no desktop: nothing", MSBDTitleZoomFrame(CGRectNull, desk, min), CGRectNull);
    Frame("  ... an empty desktop", MSBDTitleZoomFrame(CGRectMake(0, 0, 400, 300), CGRectMake(0, 0, 0, 0), min), CGRectNull);
    Frame("a smallest window bigger than the desktop (a tiny area): the desktop", MSBDTitleZoomFrame(CGRectMake(0, 0, 100, 400), CGRectMake(0, 24, 300, 200), CGSizeMake(320, 324)), CGRectMake(0, 24, 300, 200));
    {   // (every shape, every place: inside the desktop, its shape kept to the rounding, and a zoomed frame is its own zoomed frame)
        int inside = 1, shape = 1, fixed = 1, edge = 1;
        for (int i = 1; i <= 60; i++) for (int j = 1; j <= 40; j++) {
            CGRect win = CGRectMake(i * 7, j * 11, 320 + i * 13, 324 + j * 17);
            CGRect z = MSBDTitleZoomFrame(win, desk, min);
            if (!Inside(z, desk)) inside = 0;
            // (one side is the desktop's, the other rounded to a whole point: half a point at most)
            if (z.size.width > min.width && z.size.height > min.height && fabs(z.size.width * win.size.height - z.size.height * win.size.width) > 0.5 * fmax(win.size.width, win.size.height) + 1e-6) shape = 0;
            if (!CGRectEqualToRect(MSBDTitleZoomFrame(z, desk, min), z)) fixed = 0;
            if (!(fabs(z.size.width - desk.size.width) < 0.001 || fabs(z.size.height - desk.size.height) < 0.001)) edge = 0;
        }
        Int("2400 windows: every zoomed frame inside the desktop", inside, 1);
        Int("  ... its shape kept (to half a point either side)", shape, 1);
        Int("  ... reaching the desktop's edges on one side", edge, 1);
        Int("  ... and its own zoomed frame (a second Zoom from there moves nothing)", fixed, 1);
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
