// DisplayRows.h -- the per-display settings' rows (MacStatusBar&Dock 1.8.7 commit 11; plans/design-1.8.7-displays.md sections 4 and 6). Plain C:
// one table drives the Display Settings window (statusbar/DisplaySettings.h, on the iPad and on the TV), the Settings page (Settings > Desktop >
// Displays, statusbar/macstatusbarprefs/MSBRootListController.m MSBDisplayListController) and the Mac test (tools/test-displayrows.c), so the window and Settings show the
// same rows and write the same keys.
//
// Each row is judged "does this mean something on a TV?" (KT 10 Nov ~19:40): Home Minimizes Windows, Dock Position, Larger Dock in Portrait, Open
// Apps as Windows and Gap to Screen Edge are not rows. A row has its title, its footer (public text: short, plain sentences, no em dash), its kind,
// the part and key of the iPad's setting it overrides (common/DisplayPrefs.h: part msb or dock; disp for a display-only row), the iPad's value when
// that was never set (the iPad's own Settings default), when it shows (the iPadOS floor and what the display has: our menu bar, our Dock, a Stage
// Manager desktop, Finder on, more than one scale) and when a change applies. Rows of a later release (slot) are in the table and never shown.
// Show Trash in Dock's display default (ON) is the rule's (DisplayPrefs.h MSBDDispDisplayDefault), not the table's.
#pragma once
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <math.h>

enum { kMSBDRowSwitch = 1, kMSBDRowChoice = 2, kMSBDRowSlider = 3, kMSBDRowScale = 4 };
enum { kMSBDRowAppliesNow = 0, kMSBDRowAppliesNextConnect = 1, kMSBDRowAppliesNextWindow = 2 };
// What a row needs of the display (all of its bits).
enum {
    kMSBDRowNeedsBar    = 1 << 0,   // our menu bar on that display (Mac Status Bar on, not the stock bar)
    kMSBDRowNeedsDock   = 1 << 1,   // our Dock (the Dock part on)
    kMSBDRowNeedsSM     = 1 << 2,   // a Stage Manager desktop (the Stage Manager engine: A / Z / M windows never reach the TV)
    kMSBDRowNeedsFinder = 1 << 3,   // Finder on (the Trash is Finder's)
    kMSBDRowNeedsScales = 1 << 4,   // iPadOS lists more than one scale for that display (S2: Apple's own call, no hooks)
};
#define MSBD_DISP_RELEASE 187   // (the rows of this release; a row with a later slot stays in the table, hidden)
#define MSBD_DISP_ROW_CHOICES 3

typedef struct {
    const char *rowId;        // the row's identifier (the window's row, Settings' specifier id)
    const char *title;
    const char *footer;       // public text, or NULL
    int kind;
    const char *part, *key;   // the iPad's setting it overrides (DisplayPrefs.h flat keys)
    int needs;                // kMSBDRowNeeds... bits
    int minOS;                // iPadOS floor (a display is its own desktop from 16; 15 mirrors on every engine)
    int applies;              // kMSBDRowApplies...
    int slot;                 // the release it belongs to (187 = 1.8.7; 190 = 1.9.0, hidden until then)
    double ipadDefault;       // the iPad's value when it was never set (switch 0 / 1, slider, a numeric choice's index)
    double lo, hi, step;      // a slider's range and step (inside what its reader takes: Dock.x DMDockIconSizeOn 0.4-1.5, DMDockMagOf 1.0-3.0)
    int choices;              // a choice's count
    const char *choiceTitles[MSBD_DISP_ROW_CHOICES];
    const char *choiceValues[MSBD_DISP_ROW_CHOICES];   // stored as text ("small"...), or all NULL: stored as its index (0, 1, 2)
    const char *dependsOn;    // a switch of the same part this row follows (greyed while it is off), or NULL
} MSBDDispRow;

static const MSBDDispRow kMSBDDispRows[] = {
    { "MENU_BAR_SIZE", "Menu Bar Size", "Applies the next time this display connects.", kMSBDRowChoice, "msb", "menuBarSize",
      kMSBDRowNeedsBar, 16, kMSBDRowAppliesNextConnect, 187, 0, 0, 0, 0, 3, { "Small", "Medium", "Large" }, { NULL, NULL, NULL }, NULL },
    { "AUTO_HIDE_MENU_BAR", "Automatically Hide and Show the Menu Bar", NULL, kMSBDRowSwitch, "msb", "autoHideStatusBar",
      kMSBDRowNeedsBar, 16, kMSBDRowAppliesNow, 187, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "DOCK_SIZE", "Dock Size", NULL, kMSBDRowSlider, "dock", "dockIconSize",
      kMSBDRowNeedsDock, 16, kMSBDRowAppliesNow, 187, 0.85, 0.5, 1.2, 0.01, 0, { NULL }, { NULL }, NULL },
    { "MAGNIFICATION", "Magnification", NULL, kMSBDRowSwitch, "dock", "enabled",
      kMSBDRowNeedsDock, 16, kMSBDRowAppliesNow, 187, 1, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "MAGNIFICATION_AMOUNT", "Magnification Amount", NULL, kMSBDRowSlider, "dock", "magnification",
      kMSBDRowNeedsDock, 16, kMSBDRowAppliesNow, 187, 1.22, 1.0, 2.5, 0.01, 0, { NULL }, { NULL }, "enabled" },
    { "AUTO_HIDE_DOCK", "Automatically Hide and Show the Dock", NULL, kMSBDRowSwitch, "dock", "autoHideDock",
      kMSBDRowNeedsDock | kMSBDRowNeedsSM, 16, kMSBDRowAppliesNow, 187, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "SHOW_TRASH", "Show Trash in Dock", "On for displays unless you switch it off here, even when it is off on the iPad.", kMSBDRowSwitch, "dock", "showTrash",
      kMSBDRowNeedsDock | kMSBDRowNeedsFinder, 16, kMSBDRowAppliesNow, 187, 1, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "WINDOW_SIZE", "Window Size", "The size a new window on this display opens at.", kMSBDRowChoice, "msb", "windowSize",
      kMSBDRowNeedsSM, 16, kMSBDRowAppliesNextWindow, 187, 1, 0, 0, 0, 3, { "Small", "Default", "Large" }, { "small", "default", "large" }, NULL },
    { "NEW_WINDOWS_FILL", "New Windows Open at Fill", NULL, kMSBDRowSwitch, "msb", "newWindowsFill",
      kMSBDRowNeedsSM, 16, kMSBDRowAppliesNextWindow, 187, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "RESOLUTION", "Resolution", "The sizes iPadOS offers for this display. More Space fits more on the screen, with smaller text.", kMSBDRowScale, "disp", "scale",
      kMSBDRowNeedsScales, 16, kMSBDRowAppliesNow, 187, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    // (1.9.0, in the table and hidden until then: the release's rows table, KT 10 Nov)
    { "DESKTOP_PICTURE", "Desktop Picture", NULL, kMSBDRowSwitch, "msb", "desktopPicture", kMSBDRowNeedsBar, 16, kMSBDRowAppliesNow, 190, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "DESKTOP_ICONS", "Show Desktop Icons", NULL, kMSBDRowSwitch, "msb", "desktopIcons", kMSBDRowNeedsFinder, 16, kMSBDRowAppliesNow, 190, 1, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "DIM_IPAD", "Dim the iPad", NULL, kMSBDRowSwitch, "disp", "dimIPad", 0, 16, kMSBDRowAppliesNow, 190, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
    { "FILL_WHEN_MIRRORING", "Fill the TV When Mirroring", NULL, kMSBDRowSwitch, "disp", "fillWhenMirroring", 0, 15, kMSBDRowAppliesNow, 190, 0, 0, 0, 0, 0, { NULL }, { NULL }, NULL },
};
#define MSBD_DISP_ROW_COUNT ((int)(sizeof(kMSBDDispRows) / sizeof(kMSBDDispRows[0])))

// Public text for the page and the window (the same words in both).
#define MSBD_DISP_TEXT_GROUP      "Settings for a TV or monitor connected to this iPad. A display starts with your iPad's settings and keeps following them until you change one for that display. Connect a display or start AirPlay to change its settings."
#define MSBD_DISP_TEXT_NONE       "No display is connected."
#define MSBD_DISP_TEXT_TOP        "Changes here apply to this display only."
#define MSBD_DISP_TEXT_USE_IPAD   "Use iPad Settings"
#define MSBD_DISP_TEXT_USE_IPAD_ASK "Every setting of this display goes back to your iPad's."
#define MSBD_DISP_TEXT_MIRROR     "This display shows the iPad's screen. Its own settings apply when it is a separate desktop."
#define MSBD_DISP_TEXT_OFF        "Display Settings is off. Every display uses your iPad's settings."
#define MSBD_DISP_TEXT_FORGET     "Forget This Display"
#define MSBD_DISP_TEXT_FORGET_ASK "Its settings are deleted. It starts with your iPad's settings the next time it connects."
#define MSBD_DISP_TEXT_NOT_CONNECTED "Not Connected"
#define MSBD_DISP_TEXT_OVERSCAN   "If the edges are cut off, set the TV's picture size to Just Scan or Screen Fit."
#define MSBD_DISP_TEXT_RESET      "Use the iPad's Setting"
#define MSBD_DISP_TEXT_DEFAULT_ON "Default: On"
#define MSBD_DISP_TEXT_SWITCH     "Display Settings"   // (the master switch's row: the crash guard's displaySettings target, its row title in crashmap-rules.txt)
#define MSBD_DISP_TEXT_SCALE_SWITCH "More Space"       // (More Space's own switch: the guard's displayScale target)
// The words on top of a display's rows, the same in the window and on Settings' page: Display Settings off; else the display gone (not connected:
// before the mirror's words, which a display gone would read as, its desktop gone with it); else a mirror; else "this display only".
static inline const char *MSBDDispTopText(int layerOn, int connected, int extended) {
    return !layerOn ? MSBD_DISP_TEXT_OFF : !connected ? MSBD_DISP_TEXT_NONE : !extended ? MSBD_DISP_TEXT_MIRROR : MSBD_DISP_TEXT_TOP;
}

// What the display has now, for "shown when".
typedef struct {
    int osMajor;      // iPadOS major version
    int extended;     // the display is its own desktop (16+: SpringBoard has a window scene on it); 0: it mirrors the iPad
    int ourBar;       // our menu bar (Mac Status Bar on, the Mac status bar in use)
    int ourDock;      // our Dock (the Dock part on)
    int smEngine;     // the Stage Manager engine
    int finder;       // Finder on
    int scales;       // how many scales iPadOS lists for it (S2; 0 not read)
    int release;      // MSBD_DISP_RELEASE (a test can ask for a later one)
} MSBDDispCtx;

static inline const MSBDDispRow *MSBDDispRowAt(int i) { return i >= 0 && i < MSBD_DISP_ROW_COUNT ? &kMSBDDispRows[i] : NULL; }
static inline const MSBDDispRow *MSBDDispRowFor(const char *part, const char *key) {
    if (!part || !key) return NULL;
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) if (strcmp(kMSBDDispRows[i].part, part) == 0 && strcmp(kMSBDDispRows[i].key, key) == 0) return &kMSBDDispRows[i];
    return NULL;
}
static inline const MSBDDispRow *MSBDDispRowById(const char *rowId) {
    if (!rowId) return NULL;
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) if (strcmp(kMSBDDispRows[i].rowId, rowId) == 0) return &kMSBDDispRows[i];
    return NULL;
}
// Is the row on the page or in the window: its release, its iPadOS floor (15 lists the rows, greyed: MSBDDispRowEnabled), and what it needs.
static inline bool MSBDDispRowShown(const MSBDDispRow *r, const MSBDDispCtx *c) {
    if (!r || !c || r->slot > c->release) return false;
    if (c->osMajor < 15) return false;
    if ((r->needs & kMSBDRowNeedsBar) && !c->ourBar) return false;
    if ((r->needs & kMSBDRowNeedsDock) && !c->ourDock) return false;
    if ((r->needs & kMSBDRowNeedsSM) && !c->smEngine) return false;
    if ((r->needs & kMSBDRowNeedsFinder) && !c->finder) return false;
    if ((r->needs & kMSBDRowNeedsScales) && c->scales < 2) return false;   // (one scale listed, or none read: nothing to choose, no row)
    return true;
}
// Can it be changed now: shown, on the row's iPadOS floor, with the display connected as its own desktop and the master switch on (iPadOS 15: the
// display mirrors on every engine, the rows are greyed with the mirror footer).
static inline bool MSBDDispRowEnabled(const MSBDDispRow *r, const MSBDDispCtx *c, int connected, int layerOn) {
    return MSBDDispRowShown(r, c) && c->osMajor >= r->minOS && c->extended && connected && layerOn;
}
// A choice's index from what is stored: a text choice by its value ("default" and any other text the middle one, as WindowSize.h reads it), a
// numeric one by its number (0 .. count - 1, a whole number); -1 when it is not this row's (the rule then reads the iPad's).
static inline int MSBDDispChoiceIndexText(const MSBDDispRow *r, const char *text) {
    if (!r || r->kind != kMSBDRowChoice || !r->choiceValues[0] || !text) return -1;
    for (int i = 0; i < r->choices; i++) if (r->choiceValues[i] && strcmp(r->choiceValues[i], text) == 0) return i;
    return (int)r->ipadDefault;
}
static inline int MSBDDispChoiceIndexNum(const MSBDDispRow *r, double v) {
    if (!r || r->kind != kMSBDRowChoice || r->choiceValues[0] || !isfinite(v) || v != floor(v) || v < 0 || v >= r->choices) return -1;
    return (int)v;
}
// A slider's value as written: on its step, inside its range (a value from the control never leaves it; NAN for none).
static inline double MSBDDispSliderValue(const MSBDDispRow *r, double v) {
    if (!r || r->kind != kMSBDRowSlider || !isfinite(v)) return NAN;
    if (v < r->lo) v = r->lo;
    if (v > r->hi) v = r->hi;
    if (r->step > 0) v = r->lo + round((v - r->lo) / r->step) * r->step;
    return round(v * 1000.0) / 1000.0;
}
// Public text rule (KT: no em dash, no "--", short plain sentences that end with a full stop): the footers and the page's texts.
static inline bool MSBDDispTextPublicOK(const char *t) {
    if (!t) return true;
    size_t n = strlen(t);
    if (!n || strstr(t, "\xE2\x80\x94") || strstr(t, "\xE2\x80\x93") || strstr(t, "--") || strstr(t, "  ")) return false;
    return t[n - 1] == '.' || t[n - 1] == ':' || (t[n - 1] >= 'A' && t[n - 1] <= 'z');   // (a sentence's full stop, or a title / button)
}
