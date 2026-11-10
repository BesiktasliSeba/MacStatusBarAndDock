// Mac test of common/DesktopSettle.h: when the desktop lists its folder again for an item still arriving.
#include <stdio.h>
#include "../common/DesktopSettle.h"
static int fails;
static void t(const char *what, int got, int want) { int ok = !!got == !!want; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    double now = 1000.0;
    t("a file written just now is still arriving", MSBDDesktopStillArriving(now, 999.0, 0, 1, 0, 0, 0), 1);
    t("a file last written 7 s ago too", MSBDDesktopStillArriving(now, 993.0, 0, 1, 0, 0, 0), 1);
    t("a file last written 8 s ago no longer", MSBDDesktopStillArriving(now, 992.0, 0, 1, 0, 0, 0), 0);
    t("an old file no longer", MSBDDesktopStillArriving(now, 10.0, 0, 1, 0, 0, 0), 0);
    t("a date in the future, kept by a copy: no endless listing", MSBDDesktopStillArriving(now, 5000.0, 0, 1, 0, 0, 0), 0);
    t("an .app without its Info.plist yet, with an old date, is waited for", MSBDDesktopStillArriving(now, 10.0, 1, 0, 10.0, 0, 0), 1);
    t("  ... for up to 3 minutes", MSBDDesktopStillArriving(now, 10.0, 1, 0, 179.0, 0, 0), 1);
    t("  ... then given up: a folder merely named .app", MSBDDesktopStillArriving(now, 10.0, 1, 0, 180.0, 0, 0), 0);
    t("a whole .app, old date: nothing to wait for", MSBDDesktopStillArriving(now, 10.0, 1, 1, 10.0, 0, 0), 0);
    t("a whole .app written just now: the copy may still be going", MSBDDesktopStillArriving(now, 998.0, 1, 1, 10.0, 0, 0), 1);
    t("a document saving again and again: arriving for 30 s of writes", MSBDDesktopStillArriving(now, 999.0, 0, 1, 0, 29.0, 0), 1);
    t("  ... then no more listings, however often it saves", MSBDDesktopStillArriving(now, 999.0, 0, 1, 0, 30.0, 0), 0);
    t("  ... unless it keeps growing, a download", MSBDDesktopStillArriving(now, 999.0, 0, 1, 0, 300.0, 1), 1);
    return fails;
}
