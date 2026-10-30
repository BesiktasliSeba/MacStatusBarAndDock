// ActMonText.h -- the plain lines the Activity Monitor window shows where a figure is not available, kept as pure C so the Mac test
// (tools/test-actmontext.c) checks the exact wording. The window shows a dash in the cell; these give the one plain line for the tab's footer and
// for the Inspect panel. The wording states the fact plainly; it never says a figure is coming or broken.
#ifndef MSBD_ACTMON_TEXT_H
#define MSBD_ACTMON_TEXT_H

// The Darwin notification the RAM & CPU Control Center panel posts to open the Activity Monitor window (SpringBoard observes it, dismisses Control
// Center, then opens the window). Defined here so both the window's side (StatusBar.x) and the Control Center module (ccmodule) use one name.
#define MSBD_ACTMON_OPEN_NOTE "com.besiktasliseba.macstatusbar.actmon.open"

enum { MSBD_AM_CPU = 0, MSBD_AM_MEMORY, MSBD_AM_ENERGY, MSBD_AM_DISK, MSBD_AM_NETWORK };   // (match ActivityMonitor.h's DMAMTab)

// The footer line for a tab. On the CPU, Memory and Disk tabs some rows (system processes) have a dash: say so, but only when such a row is in view.
// On the Energy and Network tabs no per-process figure is shown at all: say so plainly. "" when there is nothing to say.
static inline const char *MSBDActMonFooterNote(int tab, int anyMissing) {
    if (tab == MSBD_AM_ENERGY)  return "Per-process energy is not shown here";
    if (tab == MSBD_AM_NETWORK) return "Per-process network is not shown here";
    return anyMissing ? "System processes show no figures" : "";
}

// Why the Quit button is off for the selected row: "" when the row is an app (Quit is on), a plain reason otherwise.
static inline const char *MSBDActMonQuitReason(int isApp) { return isApp ? "" : "Only apps can be quit"; }

// The Inspect panel's line for a process with no figures (a system process), "" otherwise.
static inline const char *MSBDActMonInspectNote(int haveStats) { return haveStats ? "" : "System processes show no figures"; }

#endif
