// test-editproxy.c -- Mac test of dock/EditProxyRule.h (1.8.3 item 5): the Dock's own items in Edit Home Screen -- the app icon each one shows,
// covered by SpringBoard's icon view or jiggling itself, no tap while editing, no remove badge, no drag. Run by test-editproxy.sh.
#include <stdio.h>
#include "../dock/EditProxyRule.h"
static int fails = 0, checks = 0;
static void Int(const char *what, int got, int want) { checks++; if (got == want) printf("PASS  %s\n", what); else { fails++; printf("FAIL  %s (got %d, want %d)\n", what, got, want); } }
int main(void) {
    // (the values of common/IconThemeIDs.h MSBDIconItem: Finder 0, Launchpad 1, classic Launchpad 2, Downloads 3, empty Trash 4, full Trash 5)
    Int("Finder shows Finder's icon (a theme names it com.besiktasliseba.finder)", MSBDEditIconItem(kMSBDEditFinder, true, false), 0);
    Int("Launchpad, the round rocket: the classic Launchpad icon", MSBDEditIconItem(kMSBDEditLaunchpad, true, false), 2);
    Int("  ... the grid tile: the Launchpad icon", MSBDEditIconItem(kMSBDEditLaunchpad, false, false), 1);
    Int("Downloads: its folder", MSBDEditIconItem(kMSBDEditDownloads, false, true), 3);
    Int("the Trash, empty: the empty bin (a theme chosen for it is for the bin on screen)", MSBDEditIconItem(kMSBDEditTrash, false, false), 4);
    Int("  ... with something in it: the full bin", MSBDEditIconItem(kMSBDEditTrash, false, true), 5);
    Int("no other view", MSBDEditIconItem(kMSBDEditCount, false, false), -1);
    Int("editing, SpringBoard's icon view made: covered (it jiggles, SnowBoard's menu finds it)", MSBDEditHow(true, true), kMSBDEditCover);
    Int("  ... none can be made (iPadOS 18, the icon path off): it jiggles itself", MSBDEditHow(true, false), kMSBDEditOwnJiggle);
    Int("  ... not editing: as before", MSBDEditHow(false, true), kMSBDEditNone);
    Int("no tap or double tap while editing (a double tap on Finder opened a Finder window)", MSBDEditTakesTaps(true), 0);
    Int("  ... taps again once editing ends", MSBDEditTakesTaps(false), 1);
    Int("no remove badge (they come and go with Settings > Dock's switches)", MSBDEditCloseBox(), 0);
    Int("no drag (no place in SpringBoard's icon model to go to)", MSBDEditDrag(), 0);
    Int("own jiggle: 1.5 degrees each way", (int)(kMSBDEditJiggleRadians * 1800.0 / M_PI + 0.5), 15);
    Int("  ... the views not in step (each starts at another point of the swing)", MSBDEditJigglePhase(kMSBDEditFinder) != MSBDEditJigglePhase(kMSBDEditTrash), 1);
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
