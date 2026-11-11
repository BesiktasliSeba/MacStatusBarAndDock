// Mac test of which defaults entries an install writes (common/DefaultsRule.h): the root helper's FreezeOldDefaults asks it for every entry of
// OldDefaults. Above all the review of 1.8.6 case: a 1.8.5 user removes the tweak and installs 1.8.6 (dpkg names no old version, defaultsVersion 3
// survived the removal): an update for the defaults, so Show Trash in Dock (v4) gets its old default (off) where nothing is stored, as a plain
// update has it. And DefaultsForAll: a value every device gets once, over what is stored (1.8.6: Show Apps' Own Menus on for everyone, KT 10 Nov).
// Run by test-defaultsrule.sh.
#include <stdio.h>
#include "../common/DefaultsRule.h"
static int fails = 0, passes = 0;
#define CHECK(c, ...) do { if (c) passes++; else { fails++; printf("FAIL %s:%d ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)
// The entries of OldDefaults (main.m) by the version that changed them: v2 (showSeconds and the others), v3 (skipLockAfterRespring), v4 (showTrash).
static const long kEntries[] = {2, 2, 2, 2, 2, 3, 4};
#define N (sizeof kEntries / sizeof kEntries[0])
// How many entries an install writes, and whether it writes the v4 one (showTrash, last).
static int Frozen(int decisionFresh, long done, int *trash) {
    int first = MSBDDefaultsFirstInstall(decisionFresh, done), n = 0;
    *trash = 0;
    for (unsigned i = 0; i < N; i++) if (MSBDDefaultsFreezes(kEntries[i], done, first)) { n++; if (kEntries[i] == 4) *trash = 1; }
    return n;
}
int main(void) {
    int trash = 0;
    // a first install on a device that never had the tweak: the new defaults (nothing frozen), the first-install extras (Stage Manager engine)
    CHECK(MSBDDefaultsFirstInstall(1, 0), "a device that settled nothing, no old version: a first install");
    CHECK(Frozen(1, 0, &trash) == 0 && !trash, "  ... nothing frozen: the Trash shows (new default)");
    // the review's case: 1.8.5 removed (defaultsVersion 3 kept), 1.8.6 installed: dpkg passes no old version, FreezeReason finds nothing
    CHECK(!MSBDDefaultsFirstInstall(1, 3), "a reinstall after a removal (v3 settled, no old version from dpkg): not a first install");
    CHECK(Frozen(1, 3, &trash) == 1 && trash, "  ... showTrash gets NO where nothing is stored (the v4 entry only), as an update");
    // a plain update from 1.8.5
    CHECK(Frozen(0, 3, &trash) == 1 && trash, "an update from 1.8.5 (v3): the v4 entry only, showTrash NO");
    // a reinstall from an older line (v2 settled): v3 and v4 entries
    CHECK(Frozen(1, 2, &trash) == 2 && trash, "a reinstall with v2 settled: the v3 and v4 entries");
    // v4 settled already (FreezeOldDefaults returns before asking): nothing would be written either way
    CHECK(Frozen(1, 4, &trash) == 0 && Frozen(0, 4, &trash) == 0, "v4 settled: nothing");
    // an upgrade from the old separate packages (no defaultsVersion yet, a freeze reason): every entry
    CHECK(!MSBDDefaultsFirstInstall(0, 0) && Frozen(0, 0, &trash) == (int)N, "the old packages (nothing settled, a freeze reason): every entry");
    // a value for every device (v4: appOwnMenus YES): every install that has not settled v4, first install, update or reinstall; once (v4 settled:
    // a user who switches it off after that keeps it off)
    CHECK(MSBDDefaultsForAll(4, 0), "for every device: a first install");
    CHECK(MSBDDefaultsForAll(4, 3), "  ... an update from 1.8.5 (v3), a reinstall after a removal the same");
    CHECK(MSBDDefaultsForAll(4, 2), "  ... an older line (v2)");
    CHECK(!MSBDDefaultsForAll(4, 4), "  ... not again once v4 is settled (switched off after that: stays off)");
    printf("test-defaultsrule: %d pass, %d fail\n", passes, fails);
    return fails ? 1 : 0;
}
