// test-dockapplibrary.c -- Mac test of common/DockAppLibrary.h (1.8.4.1 item 2): Apple's "Show App Library in Dock" on our Dock page applies at
// once -- when the Dock's parked icon updates run, and the passes after a change. Run by test-dockapplibrary.sh.
#include <stdio.h>
#include <string.h>
#include "../common/DockAppLibrary.h"
static int fails = 0, checks = 0;
static void Int(const char *what, long got, long want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %ld, want %ld)\n", what, got, want); } }
int main(void) {
    Int("parked icon updates, no transition running: run now (what a full-screen transition's end does; window engines never make one)", MSBDDockRunParked(1, false), 1);
    Int("  ... several parked: run now", MSBDDockRunParked(3, false), 1);
    Int("  ... a transition running: left to its own end, as before", MSBDDockRunParked(2, true), 0);
    Int("  ... nothing parked: nothing run", MSBDDockRunParked(0, false), 0);
    Int("  ... the list unreadable: nothing run", MSBDDockRunParked(-1, false), 0);
    Int("three passes after a change", kMSBDDockAppLibraryPassCount, 3);
    Int("  ... the first at once", kMSBDDockAppLibraryPassAt[0] == 0.0, 1);
    int rising = 1;
    for (int i = 1; i < kMSBDDockAppLibraryPassCount; i++) if (!(kMSBDDockAppLibraryPassAt[i] > kMSBDDockAppLibraryPassAt[i - 1])) rising = 0;
    Int("  ... each later than the one before", rising, 1);
    Int("  ... the last within two seconds (the Dock follows while the user still looks at the switch)", kMSBDDockAppLibraryPassAt[kMSBDDockAppLibraryPassCount - 1] <= 2.0, 1);
    Int("the notification is the Dock part's own domain's", !strncmp(kMSBDDockAppLibraryNote, "com.besiktasliseba.dockmagnification/", 37), 1);
    Int("  ... not the Dock settings' own (which lays out without running SpringBoard's parked updates)", strcmp(kMSBDDockAppLibraryNote, "com.besiktasliseba.dockmagnification/prefsChanged") != 0, 1);
    Int("Apple's row is SHOW_APP_LIBRARY (common/NativeEmbed.h)", !strcmp(kMSBDDockAppLibraryRowID, "SHOW_APP_LIBRARY"), 1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
