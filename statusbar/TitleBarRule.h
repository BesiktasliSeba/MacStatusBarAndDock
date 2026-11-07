// TitleBarRule.h -- a double tap on a window's title bar (Settings > Windows & Multitasking, 1.8.3 item 8, KT 6 Nov), as macOS's Desktop & Dock
// setting "Double-click a window's title bar to". Plain C, so the Mac test (tools/test-titlebar.c) runs this very rule; statusbar/TitleBarTap.h
// does it in SpringBoard, the same on every engine (Aerial, Zetsu, MilkyWay4, Stage Manager) and on our own windows (Finder, TextEdit).
// macOS 15's choices, from Apple's guide (Mac User Guide, "Change Desktop & Dock settings on Mac", macOS Sequoia 15):
//   Fill: expand the window to fill the space between the menu bar and the Dock (beside a Dock at the side of the screen);
//   Zoom: zoom the window (to the largest size its desktop gives, and back to the size it had);
//   Minimize: minimize the window into the Dock;
//   Do Nothing: nothing.
// The guide gives no default (AppKit's own, with the setting never changed -- AppleActionOnDoubleClick unset, macOS 15.7.7 read on 6 Nov -- is
// Zoom). Never set here (KT, 7 Nov, review 1.8.3 P2-3): an app's window does nothing, as in 1.8.2.2 on every engine, and our own windows (Finder,
// TextEdit) keep the Zoom their title bar always had; once a choice is made, every window follows it. One setting: its never-set state is its own.
// Fill and Zoom go back the way a Mac does: a second double tap on a window that is still at Fill gives it the frame it had just before -- before
// whichever placement put it at Fill (MSBDTitleRecordOnPlace).
#ifndef MSBD_TITLE_BAR_RULE_H
#define MSBD_TITLE_BAR_RULE_H
#include <stdbool.h>
#include <string.h>

// (the title bars SpringBoard's side knows: TitleBarTap.h)
enum { kDMTitleNative = 1, kDMTitleSM, kDMTitleAerial, kDMTitleMilkyWay, kDMTitleZetsu };
#define kMSBDTitleDoubleTapKey "titleBarDoubleTap"   // (com.besiktasliseba.macstatusbar: "fill" / "zoom" / "minimize" / "none"; never set: see above)
enum { kMSBDTitleNeverSet = -1, kMSBDTitleFill = 0, kMSBDTitleZoom, kMSBDTitleMinimize, kMSBDTitleNothing, kMSBDTitleCount };
// The setting as stored: one of the four, or never set (no value -- or one this version does not know: the defaults, as never set).
static inline int MSBDTitleActionFromStored(const char *stored) {
    if (!stored) return kMSBDTitleNeverSet;
    if (!strcmp(stored, "fill")) return kMSBDTitleFill;
    if (!strcmp(stored, "zoom")) return kMSBDTitleZoom;
    if (!strcmp(stored, "minimize")) return kMSBDTitleMinimize;
    if (!strcmp(stored, "none")) return kMSBDTitleNothing;
    return kMSBDTitleNeverSet;
}
// What a double tap does on a window: the choice made, else (never set) nothing on an app's window and Zoom on our own (ownWindow: Finder, TextEdit).
static inline int MSBDTitleActionFor(int setting, bool ownWindow) {
    if (setting < kMSBDTitleFill || setting >= kMSBDTitleCount) return ownWindow ? kMSBDTitleZoom : kMSBDTitleNothing;
    return setting;
}
static inline const char *MSBDTitleActionName(int action) {
    switch (action) {
        case kMSBDTitleFill: return "Fill";
        case kMSBDTitleZoom: return "Zoom";
        case kMSBDTitleMinimize: return "Minimize";
        case kMSBDTitleNothing: return "Do Nothing";
        case kMSBDTitleNeverSet: return "never set (app windows: Do Nothing; ours: Zoom)";
        default: return "?";
    }
}
// What one double tap does now: Fill and Zoom take the window to Fill, or -- at Fill already, with a frame from before kept -- back to that frame;
// Minimize minimizes it; Do Nothing nothing. (At Fill with no frame from before -- opened there --: Fill again, so it stays.)
enum { kMSBDTitleDoNothing = 0, kMSBDTitleToFill, kMSBDTitleBack, kMSBDTitleDoMinimize };
static inline int MSBDTitleStep(int action, bool atFill, bool hasRecord) {
    switch (action) {
        case kMSBDTitleFill:
        case kMSBDTitleZoom: return atFill && hasRecord ? kMSBDTitleBack : kMSBDTitleToFill;
        case kMSBDTitleMinimize: return kMSBDTitleDoMinimize;
        default: return kMSBDTitleDoNothing;
    }
}
// Fill and Zoom keep the frame the window had just before (macOS's user frame): taken at every double tap that fills it from a frame that is not
// Fill, whatever the window was -- free, a half, a Fit to Window tile --, so the next double tap gives that frame back. (1.8.3 regression F2, iPad 2:
// Fill went back through Return to Previous Size's record, which a window already in a tile -- every window Fit to Window tiles -- never takes
// (WindowKeysRule.h MSBDWinPrevTake): no way back on Stage Manager, an older tile's frame on Aerial.) Fill still takes Return to Previous Size's
// record as the Window menu's Fill does, for Globe-Control-R.
static inline bool MSBDTitleBackTakes(bool atFill) { return !atFill; }
// The settings whose double tap fills an app's window and goes back: their frames from before are kept (dropped for the others).
static inline bool MSBDTitleKeepsFrames(int setting) { return setting == kMSBDTitleFill || setting == kMSBDTitleZoom; }
// The frame from before is kept with the Fill frame the window was put at, and kept in step with every placement of ours, not only the title bar's
// own double tap (review 1.8.3 P4-1: a title-bar Fill from A, then Globe-Control-Left, then Globe-Control-F -- or the Window menu's Fill, or the
// window API's -- and a double tap went back to A, two placements ago, where a Mac goes back to the half). Each placement of ours -- the Window
// menu's layouts and Swap, the window keys (layouts, arrangements, Center, Return to Previous Size), the window API, Fit to Window, the title bar's
// double tap -- before it moves a window: to Fill from a frame that is not Fill, that frame is the one to go back to (taken); to Fill where it is
// already, nothing changes (kept); anywhere else, the window leaves the Fill the frame was kept for (dropped). A move or a resize by hand drops it
// too, so a frame from before is never older than the window's last move by hand. With a setting that keeps no frames, nothing is kept.
enum { kMSBDTitleRecordKeep = 0, kMSBDTitleRecordTake, kMSBDTitleRecordDrop };
static inline int MSBDTitleRecordOnPlace(bool keepsFrames, bool toFill, bool atFillNow) {
    if (!keepsFrames || !toFill) return kMSBDTitleRecordDrop;
    return MSBDTitleBackTakes(atFillNow) ? kMSBDTitleRecordTake : kMSBDTitleRecordKeep;
}
// At a double tap the frame from before counts only while the window is still at the Fill frame it was kept with. Moved since by something that is
// neither ours nor a hand -- a turn, the Dock moving, an engine's own move --, the window is somewhere the frame was not kept for: it is dropped,
// and the double tap fills (nothing to go back to). Left, as it cannot be known: a move that is neither ours nor a hand and takes the window off
// that very Fill frame and back to it, with no move by hand between, keeps the frame from before. None such is known on Aerial, Zetsu or
// MilkyWay4 (read on the M1, 15.6.1, 7 Nov): the lights and the title bars' double taps are ours on every engine; MilkyWay4's maximize is its
// green light (-maxButtonAction:), which ours turns into full screen, and its own double tap on the resize grip (-sizeChangeDoubleTap:) turns
// its aspect-ratio lock on or off.
static inline bool MSBDTitleRecordHolds(bool hasRecord, bool atRecordedFill) { return hasRecord && atRecordedFill; }
// A double tap while SpringBoard is busy: what passes by itself in a moment (a transition -- the first of the two taps can be what brought the
// window forward: Stage Manager's activation is a workspace transition, and the double tap came in the middle of it and was refused, iPad 2,
// 7 Nov --, a turn being applied, the windows coming back) is waited for, a tenth of a second at a time, two seconds at most, and the double tap
// acts once it is over, as a Mac's double click on a window behind brings it forward and zooms it. The rest (the Lock Screen, a switcher, a menu
// of ours) refuses it.
#define kMSBDTitleTapWaitSeconds 0.1
#define kMSBDTitleTapMaxTries 20
enum { kMSBDTitleTapGiveUp = 0, kMSBDTitleTapNow, kMSBDTitleTapWait };
static inline int MSBDTitleTapWhen(bool busy, bool passing, int tries) {
    if (!busy) return kMSBDTitleTapNow;
    if (!passing || tries >= kMSBDTitleTapMaxTries) return kMSBDTitleTapGiveUp;
    return kMSBDTitleTapWait;
}

#endif
