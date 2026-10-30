// Mac test of common/ActMonText.h (run by test-actmontext.sh): the exact plain lines the Activity Monitor window shows where a figure is missing.
#include <stdio.h>
#include <string.h>
#include "../common/ActMonText.h"

static int fails = 0, passes = 0;
#define EQ(a, b, ...) do { if (!strcmp((a), (b))) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf(" got \"%s\"\n", (a)); } } while (0)

int main(void) {
    // CPU / Memory / Disk: the note only when a system (no-figure) row is in view.
    EQ(MSBDActMonFooterNote(MSBD_AM_CPU, 1), "System processes show no figures", "CPU with a system row");
    EQ(MSBDActMonFooterNote(MSBD_AM_CPU, 0), "", "CPU, all rows have figures: no note");
    EQ(MSBDActMonFooterNote(MSBD_AM_MEMORY, 1), "System processes show no figures", "Memory with a system row");
    EQ(MSBDActMonFooterNote(MSBD_AM_DISK, 0), "", "Disk, no missing: no note");
    // Energy / Network: always the plain "not shown here" line (no per-process figure in this build).
    EQ(MSBDActMonFooterNote(MSBD_AM_ENERGY, 0), "Per-process energy is not shown here", "Energy footer");
    EQ(MSBDActMonFooterNote(MSBD_AM_ENERGY, 1), "Per-process energy is not shown here", "Energy footer (missing flag ignored)");
    EQ(MSBDActMonFooterNote(MSBD_AM_NETWORK, 0), "Per-process network is not shown here", "Network footer");
    // Quit reason.
    EQ(MSBDActMonQuitReason(1), "", "an app: no reason, Quit on");
    EQ(MSBDActMonQuitReason(0), "Only apps can be quit", "not an app: reason, Quit off");
    // Inspect note.
    EQ(MSBDActMonInspectNote(1), "", "a readable process: no Inspect note");
    EQ(MSBDActMonInspectNote(0), "System processes show no figures", "a system process: Inspect note");
    // No line ever hints the data is coming or broken.
    const char *all[] = { MSBDActMonFooterNote(MSBD_AM_ENERGY, 0), MSBDActMonFooterNote(MSBD_AM_NETWORK, 0),
                          MSBDActMonFooterNote(MSBD_AM_CPU, 1), MSBDActMonQuitReason(0), MSBDActMonInspectNote(0) };
    for (int i = 0; i < 5; i++) {
        int bad = strstr(all[i], "coming") || strstr(all[i], "soon") || strstr(all[i], "broken") || strstr(all[i], "later") || strstr(all[i], "helper");
        if (bad) { fails++; printf("FAIL: a line hints data is coming/broken: \"%s\"\n", all[i]); } else passes++;
    }
    printf("test-actmontext: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
