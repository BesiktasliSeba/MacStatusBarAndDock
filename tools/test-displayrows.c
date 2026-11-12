// test-displayrows.c -- Mac test of the per-display settings' rows (1.8.7 commit 11; common/DisplayRows.h): the table the Display Settings window,
// Settings' Displays page and this test share. Titles and footers (public text), the rows left out of a TV, "shown when" per iPadOS, engine and what
// the display has, the controls' values, the flat keys. tools/test-displayrows.sh runs it, checks the sites and the crash map, then made-to-fail
// copies of the table's rules.
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../common/DisplayPrefs.h"
#include "../common/DisplayRows.h"

static int fails = 0, passes = 0;
#define EXPECT(c, msg) do { if (c) passes++; else { fails++; printf("FAIL  %s\n", msg); } } while (0)

static MSBDDispCtx full(void) { MSBDDispCtx c = { 18, 1, 1, 1, 1, 1, 1, MSBD_DISP_RELEASE }; return c; }
static int shownCount(MSBDDispCtx c) { int n = 0; for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) if (MSBDDispRowShown(MSBDDispRowAt(i), &c)) n++; return n; }
static bool shown(const char *id, MSBDDispCtx c) { return MSBDDispRowShown(MSBDDispRowById(id), &c); }

int main(void) {
    // ---- the table itself
    int r187 = 0;
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
        const MSBDDispRow *r = MSBDDispRowAt(i);
        EXPECT(r->rowId && *r->rowId && r->title && *r->title, "every row has an identifier and a title");
        for (int j = 0; j < i; j++) {
            EXPECT(strcmp(r->rowId, kMSBDDispRows[j].rowId) != 0, "identifiers are unique");
            EXPECT(strcmp(r->title, kMSBDDispRows[j].title) != 0, "titles are unique");
            EXPECT(strcmp(r->part, kMSBDDispRows[j].part) != 0 || strcmp(r->key, kMSBDDispRows[j].key) != 0, "one row per part and key");
        }
        EXPECT(MSBDDispPartValid(r->part) && MSBDDispNameValid(r->key), "a row's part and key are the layer's");
        char flat[200];
        EXPECT(MSBDDispFlatKey(flat, sizeof flat, "u-4C2D0372-0000-0000-0120-0103808E5078", r->part, r->key) > 0, "a row's flat key for the A12Z's TV is made (127 at most)");
        EXPECT(MSBDDispTextPublicOK(r->title) && MSBDDispTextPublicOK(r->footer), "titles and footers are public text (no em dash, no --)");
        if (r->footer) EXPECT(r->footer[strlen(r->footer) - 1] == '.', "a footer is a sentence");
        EXPECT(r->minOS >= 15 && (r->slot == 187 || r->slot == 190), "a row's iPadOS floor and release");
        if (r->slot == 187) r187++;
        if (r->kind == kMSBDRowSlider) EXPECT(r->lo < r->hi && r->ipadDefault >= r->lo && r->ipadDefault <= r->hi && r->step > 0, "a slider's range holds its default");
        if (r->kind == kMSBDRowChoice) EXPECT(r->choices >= 2 && r->choices <= MSBD_DISP_ROW_CHOICES && r->ipadDefault >= 0 && r->ipadDefault < r->choices, "a choice's count and default");
        if (r->dependsOn) EXPECT(MSBDDispRowFor(r->part, r->dependsOn) && MSBDDispRowFor(r->part, r->dependsOn)->kind == kMSBDRowSwitch, "a row follows a switch of its own part");
        int d = 0;
        if (MSBDDispDisplayDefault(r->part, r->key, &d)) EXPECT(strcmp(r->key, "showTrash") == 0 && d == 1 && r->footer && strstr(r->footer, "even when it is off on the iPad"),
                                                              "only Show Trash in Dock has a display default (ON), and its footer says so");
    }
    EXPECT(r187 == 10, "1.8.7's rows: Menu Bar Size, auto-hide, Dock Size, Magnification and its amount, Dock auto-hide, Trash, Window Size, Open at Fill, Resolution");
    const char *texts[] = { MSBD_DISP_TEXT_GROUP, MSBD_DISP_TEXT_NONE, MSBD_DISP_TEXT_TOP, MSBD_DISP_TEXT_USE_IPAD, MSBD_DISP_TEXT_USE_IPAD_ASK, MSBD_DISP_TEXT_MIRROR,
                            MSBD_DISP_TEXT_OFF, MSBD_DISP_TEXT_FORGET, MSBD_DISP_TEXT_FORGET_ASK, MSBD_DISP_TEXT_NOT_CONNECTED, MSBD_DISP_TEXT_OVERSCAN, MSBD_DISP_TEXT_RESET, MSBD_DISP_TEXT_DEFAULT_ON };
    for (size_t i = 0; i < sizeof texts / sizeof texts[0]; i++) EXPECT(MSBDDispTextPublicOK(texts[i]), "the page's and the window's texts are public text");
    EXPECT(!MSBDDispTextPublicOK("Menu Bar Size \xE2\x80\x94 Large.") && !MSBDDispTextPublicOK("a -- b.") && !MSBDDispTextPublicOK("a \xE2\x80\x93 b."), "an em dash, an en dash or -- is refused");
    EXPECT(strcmp(MSBDDispRowFor("msb", "menuBarSize")->footer, "Applies the next time this display connects.") == 0, "Menu Bar Size: applies at the next connect");
    // ---- the words on top (the window and the page): a display gone says so, never the mirror's words (review)
    EXPECT(strcmp(MSBDDispTopText(0, 1, 1), MSBD_DISP_TEXT_OFF) == 0 && strcmp(MSBDDispTopText(0, 0, 0), MSBD_DISP_TEXT_OFF) == 0, "Display Settings off: its words, whatever else");
    EXPECT(strcmp(MSBDDispTopText(1, 0, 0), MSBD_DISP_TEXT_NONE) == 0, "the display gone (its desktop gone with it): No display is connected");
    EXPECT(strcmp(MSBDDispTopText(1, 0, 1), MSBD_DISP_TEXT_NONE) == 0, "... also before its desktop is seen gone");
    EXPECT(strcmp(MSBDDispTopText(1, 1, 0), MSBD_DISP_TEXT_MIRROR) == 0, "connected, mirroring: the mirror's words");
    EXPECT(strcmp(MSBDDispTopText(1, 1, 1), MSBD_DISP_TEXT_TOP) == 0, "connected, its own desktop: this display only");
    // ---- left out of a TV (KT 10 Nov ~19:40)
    const char *absentTitles[] = { "Home Minimizes Windows", "Dock Position", "Position on Screen", "Larger Dock in Portrait", "Open Apps as Windows", "Gap to Screen Edge" };
    const char *absentKeys[] = { "homeMinimizesWindows", "dockPosition", "portraitLargerDock", "openAsWindows", "gapToEdge", "windowGap" };
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
        for (size_t j = 0; j < sizeof absentTitles / sizeof absentTitles[0]; j++) EXPECT(strcmp(kMSBDDispRows[i].title, absentTitles[j]) != 0, "a row that means nothing on a TV is not in the table");
        for (size_t j = 0; j < sizeof absentKeys / sizeof absentKeys[0]; j++) EXPECT(strcmp(kMSBDDispRows[i].key, absentKeys[j]) != 0, "... nor its key");
    }
    // ---- shown when
    MSBDDispCtx c = full();
    EXPECT(shownCount(c) == 9 && !shown("RESOLUTION", c), "18, our bar and Dock, Stage Manager, Finder, one scale (the A12Z's TV, S2): the 9 rows of 1.8.7 (no Resolution; 1.9.0's hidden)");
    c.scales = 2; EXPECT(shownCount(c) == 10 && shown("RESOLUTION", c), "a display listing two scales: the Resolution row too (commit 13)");
    c.scales = 0; EXPECT(!shown("RESOLUTION", c), "no scales read: no Resolution row");
    c = full(); c.release = 190; EXPECT(shownCount(c) == 13, "... a 1.9.0 build would show the 1.9.0 rows too");
    c = full(); c.ourBar = 0; EXPECT(!shown("MENU_BAR_SIZE", c) && !shown("AUTO_HIDE_MENU_BAR", c) && shown("DOCK_SIZE", c), "no Mac menu bar (stock bar): no menu bar rows");
    c = full(); c.ourDock = 0; EXPECT(!shown("DOCK_SIZE", c) && !shown("MAGNIFICATION", c) && !shown("SHOW_TRASH", c) && !shown("AUTO_HIDE_DOCK", c) && shown("MENU_BAR_SIZE", c), "the Dock part off: no Dock rows");
    c = full(); c.smEngine = 0; EXPECT(!shown("WINDOW_SIZE", c) && !shown("NEW_WINDOWS_FILL", c) && !shown("AUTO_HIDE_DOCK", c) && shown("DOCK_SIZE", c), "another engine: no window rows (A / Z / M windows never reach a TV), no Dock auto-hide (Stage Manager's)");
    c = full(); c.finder = 0; EXPECT(!shown("SHOW_TRASH", c) && shown("DOCK_SIZE", c), "Finder off: no Trash row");
    c = full(); c.osMajor = 15; c.extended = 0;
    EXPECT(shownCount(c) == 9, "iPadOS 15: the rows are listed");
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) EXPECT(!MSBDDispRowEnabled(MSBDDispRowAt(i), &c, 1, 1), "... and greyed (the display mirrors on every engine)");
    c = full(); c.extended = 0;
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) EXPECT(!MSBDDispRowEnabled(MSBDDispRowAt(i), &c, 1, 1), "a mirroring display: greyed");
    c = full();
    for (int i = 0; i < MSBD_DISP_ROW_COUNT; i++) {
        const MSBDDispRow *r = MSBDDispRowAt(i);
        EXPECT(!MSBDDispRowEnabled(r, &c, 0, 1), "a display not connected: greyed (only connected ones are editable)");
        EXPECT(!MSBDDispRowEnabled(r, &c, 1, 0), "Display Settings off: greyed");
        EXPECT(MSBDDispRowEnabled(r, &c, 1, 1) == MSBDDispRowShown(r, &c), "connected, its own desktop, the switch on: every shown row can be changed");
    }
    // ---- values
    const MSBDDispRow *ws = MSBDDispRowFor("msb", "windowSize"), *mb = MSBDDispRowFor("msb", "menuBarSize"), *ds = MSBDDispRowFor("dock", "dockIconSize");
    EXPECT(MSBDDispChoiceIndexText(ws, "small") == 0 && MSBDDispChoiceIndexText(ws, "large") == 2 && MSBDDispChoiceIndexText(ws, "default") == 1, "Window Size: stored as WindowSize.h's text");
    EXPECT(MSBDDispChoiceIndexText(ws, "huge") == 1, "... any other text is Default, as WindowSize.h reads it");
    EXPECT(MSBDDispChoiceIndexNum(ws, 1) == -1 && MSBDDispChoiceIndexText(mb, "large") == -1, "a text choice takes no number, a numeric one no text");
    EXPECT(MSBDDispChoiceIndexNum(mb, 2) == 2 && MSBDDispChoiceIndexNum(mb, 0) == 0, "Menu Bar Size: 0 Small .. 2 Large, as MenuBarSize.h");
    EXPECT(MSBDDispChoiceIndexNum(mb, 3) == -1 && MSBDDispChoiceIndexNum(mb, 1.5) == -1 && MSBDDispChoiceIndexNum(mb, -1) == -1, "... out of range or not whole: not this row's (never clamped)");
    EXPECT(MSBDDispSliderValue(ds, 0.3) == 0.5 && MSBDDispSliderValue(ds, 9) == 1.2 && fabs(MSBDDispSliderValue(ds, 0.8549) - 0.85) < 1e-9, "a slider's value on its step, in its range");
    EXPECT(ds->lo >= 0.4 && ds->hi <= 1.5, "Dock Size inside what the Dock's reader takes (0.4-1.5)");
    EXPECT(MSBDDispRowFor("dock", "magnification")->lo >= 1.0 && MSBDDispRowFor("dock", "magnification")->hi <= 3.0, "the amount inside its reader's 1.0-3.0");
    EXPECT(isnan(MSBDDispSliderValue(ws, 1)), "no slider value for a choice");
    printf("test-displayrows: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
