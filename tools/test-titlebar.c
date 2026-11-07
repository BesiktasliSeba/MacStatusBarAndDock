// test-titlebar.c -- Mac test of statusbar/TitleBarRule.h (1.8.3 item 8): a double tap on a window's title bar as macOS's "Double-click a
// window's title bar to" -- the four choices, Zoom when never set (AppKit's own default), Fill and Zoom and their way back. Run by test-titlebar.sh.
#include <stdio.h>
#include <string.h>
#include "../statusbar/TitleBarRule.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }

// ---- review 1.8.3 P4-1: the frame from before kept in step with every placement of ours (MSBDTitleRecordOnPlace / MSBDTitleRecordHolds) ----
// A small model of one window: where it is (a frame by name), its frame from before and the Fill frame that was kept with, and the Fill frame
// where it is now (a turn changes it). Each path of the tweak's code is one of these calls: the title bar's double tap, a placement of ours (the
// Window menu, the window keys, the window API, Center, Return to Previous Size, the arrangements, Swap, Fit to Window), a move by hand, and a
// move of the engine's own that runs no code of ours.
enum { F_NONE = 0, F_A, F_B, F_HALF, F_TILE, F_FILL, F_FILL2, F_M };
typedef struct { int at, before, keptFill, fill, setting; } Win;
static void Place(Win *w, int to) {   // (any placement of ours, before it moves the window)
    switch (MSBDTitleRecordOnPlace(MSBDTitleKeepsFrames(w->setting), to == w->fill, w->at == w->fill)) {
        case kMSBDTitleRecordTake: w->before = w->at; w->keptFill = w->fill; break;
        case kMSBDTitleRecordDrop: w->before = F_NONE; w->keptFill = F_NONE; break;
        default: break;
    }
    w->at = to;
}
static void ByHand(Win *w, int to) { w->before = F_NONE; w->keptFill = F_NONE; w->at = to; }   // (DMTitleRecordMovedView / ...SM)
static void EngineOwn(Win *w, int to) { w->at = to; }   // (no code of ours runs)
static void DoubleTap(Win *w) {
    int holds = MSBDTitleRecordHolds(w->before != F_NONE, w->at == w->keptFill);
    if (!holds) { w->before = F_NONE; w->keptFill = F_NONE; }   // (DMTitleRecordHeld...: a frame that no longer holds is dropped)
    int step = MSBDTitleStep(MSBDTitleActionFor(w->setting, false), w->at == w->fill, holds);
    if (step == kMSBDTitleBack) Place(w, w->before);
    else if (step == kMSBDTitleToFill) Place(w, w->fill);
}
static Win Fresh(int at) { Win w = { at, F_NONE, F_NONE, F_FILL, kMSBDTitleFill }; return w; }
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
    Int("Zoom: to Fill, then back", MSBDTitleStep(kMSBDTitleZoom, false, false) == kMSBDTitleToFill && MSBDTitleStep(kMSBDTitleZoom, true, true) == kMSBDTitleBack, 1);
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
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
