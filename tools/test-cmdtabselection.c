// Mac test of whether the Command-Tab switcher's selected item can be asked (common/CmdTabSelection.h).
#include <stdio.h>
#include "../common/CmdTabSelection.h"
static int fails = 0;
static void t(const char *what, bool got, bool want) { printf("%s  %s\n", got == want ? "PASS" : "FAIL", what); if (got != want) fails++; }
int main(void) {
    t("an empty list is not asked (the M1's NSRangeException)", MSBDCmdTabSelectionReadable(true, 0, true, 0), false);
    t("no list object yet counts as empty", MSBDCmdTabSelectionReadable(true, 0, false, 0), false);
    t("a selection in the list is asked", MSBDCmdTabSelectionReadable(true, 3, true, 2), true);
    t("a selection past the list's end is not asked", MSBDCmdTabSelectionReadable(true, 3, true, 3), false);
    t("the list known, the selection's ivar not: asked", MSBDCmdTabSelectionReadable(true, 3, false, 0), true);
    t("a list we can't read: asked as before", MSBDCmdTabSelectionReadable(false, 0, false, 0), true);
    return fails ? 1 : 0;
}
