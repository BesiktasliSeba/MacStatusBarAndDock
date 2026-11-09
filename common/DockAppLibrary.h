// DockAppLibrary.h -- Apple's "Show App Library in Dock" on our Dock page applies at once (1.8.4.1 item 2, KT 7 Nov ~22:00: on the M1, 15.6.1 with
// Aerial, switched off, the App Library icon stayed until a respring). Plain C, so the Mac test (tools/test-dockapplibrary.c) runs these very rules;
// the Settings page (dock/dockmagnificationprefs/DMRootListController.m) and the Dock part (dock/Dock.x DMAppLibraryInDockChanged) share the name.
// What was found (plans: release-1.8.4.1.md, V1841-NOTES.md):
//  - The row is Apple's own (DBSHomeScreenPadListController's SHOW_APP_LIBRARY, its own target and setter, common/NativeEmbed.h): it writes
//    exactly what Apple's page writes. Nothing of ours runs when it changes, on either side.
//  - 17.5.1 and 18.5: SpringBoard lays the Dock out without the icon at once, and with it again, on every engine (device checks 1.8.2.1 D-6 on the
//    17.5, 1.8.2.2 S-3 on the A12Z: Stage Manager, Aerial, Zetsu).
//  - 15.6.1 (the M1): the change waited for a respring, and SpringBoard's own setter of it changed nothing in the Dock for two minutes (1.8.2.1 M1
//    check, 10:22). SpringBoard parks a change of the Dock's icons until a full-screen layout transition ends (its deferred icon updates: Dock.x,
//    "Why the Dock showed one recent app too few", iPad 2, 25 Sep). Leaving Apple's page in a full-screen Settings app is such a transition;
//    with a window engine Settings is a window over the Home Screen and no such transition comes, so the change waited for the next full-screen
//    app or a respring.
// So our page tells SpringBoard when Apple's switch has changed (the switch's own control gets one more target, after Apple's), and the Dock part
// then does what the end of a full-screen transition does for the Dock -- each of the Dock's view controllers runs the icon updates it has parked
// (MSBDDockRunParked) -- and lays the Dock out again (Finder, Downloads, the Trash, the Launchpad picture, a side Dock's room, Edit Home Screen's
// stand-ins follow that layout), a few times over the next second, as SpringBoard hears of Apple's write in its own time.
#ifndef MSBD_DOCK_APP_LIBRARY_H
#define MSBD_DOCK_APP_LIBRARY_H
#include <stdbool.h>

#define kMSBDDockAppLibraryNote "com.besiktasliseba.dockmagnification/appLibraryInDock"   // (posted by our Dock page after Apple's switch changed)
#define kMSBDDockAppLibraryRowID "SHOW_APP_LIBRARY"   // (Apple's row's identifier, on iPadOS 15 and 16: common/NativeEmbed.h)

// The passes after a change, in seconds from the notification: at once, and twice more while Apple's write reaches SpringBoard's own defaults
// (cfprefsd) and SpringBoard parks its icon update.
#define kMSBDDockAppLibraryPassCount 3
static const double kMSBDDockAppLibraryPassAt[kMSBDDockAppLibraryPassCount] = { 0.0, 0.35, 1.2 };

// A Dock view controller's parked icon updates run now when it has some and no layout transition of SpringBoard's is running (that transition's
// own end runs them, as before). pending < 0: its list could not be read -- nothing is run.
static inline bool MSBDDockRunParked(long pending, bool transitioning) { return pending > 0 && !transitioning; }

#endif
