// DesktopSettle.h -- an item of the desktop still arriving (1.8.4.2, KT 9 Nov: an app dragged from Finder to the Desktop showed a white icon until the
// next icon was added). The Desktop folder is watched, so an item is listed as soon as its name exists: a copied .app before its Info.plist has come, so
// with no app to ask for its picture. Nothing told the desktop when the copy went on: writes inside an item are no change to the folder, and the
// copy's last step (the item's date set to the original's) isn't either. So the desktop lists again while an item may still be arriving: written to
// in the last few seconds, or an .app that doesn't yet say which app it is (for a while: a folder merely named .app stays like that for good).
// Plain C, so the Mac test (tools/test-desktopsettle.c) runs this very code; Desktop.h feeds it.
#ifndef MSBD_DESKTOP_SETTLE_H
#define MSBD_DESKTOP_SETTLE_H

#define MSBD_SETTLE_RECENT 8.0      // (seconds since the last write)
#define MSBD_SETTLE_APP_MAX 180.0   // (seconds an .app is waited for, from when it was first seen without its Info.plist)
#define MSBD_SETTLE_EVERY 1.5       // (seconds between the listings meanwhile)
#define MSBD_SETTLE_WRITE_MAX 30.0  // (seconds one item's writes keep the listings going, unless it is still growing: a document that autosaves isn't arriving)
#define MSBD_SETTLE_WRITE_FORGET 60.0   // (seconds with no write before an item's writes count as a new arrival)

// now and modified: the wall clock (an item's date). waitedForApp, writtenFor: seconds on a clock that can't be set back. A date in the future (kept
// from the original by a copy) says nothing about now.
static inline int MSBDDesktopRecentlyWritten(double now, double modified) { double age = now - modified; return age >= 0.0 && age < MSBD_SETTLE_RECENT; }
static inline int MSBDDesktopStillArriving(double now, double modified, int isApp, int appComplete, double waitedForApp, double writtenFor, int sizeGrew) {
    if (isApp && !appComplete) return waitedForApp < MSBD_SETTLE_APP_MAX;
    return MSBDDesktopRecentlyWritten(now, modified) && (writtenFor < MSBD_SETTLE_WRITE_MAX || sizeGrew);
}
#endif
