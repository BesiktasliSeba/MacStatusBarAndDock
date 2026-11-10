// Mac test of common/BatteryInside.h.
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "../common/BatteryInside.h"
static int fails;
static void t(const char *what, int got, int want) { int ok = got == want; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    t("0 %", MSBDBattInsidePercent(0), 0); t("100 %", MSBDBattInsidePercent(1), 100); t("rounded", MSBDBattInsidePercent(0.456), 46);
    t("out of range and unknown stay in range", MSBDBattInsidePercent(-1) + MSBDBattInsidePercent(2) + MSBDBattInsidePercent(NAN), 100);
    char b[8]; MSBDBattInsideText(0.07, b, sizeof b); t("the text has no percent sign, as iPadOS's", strcmp(b, "7"), 0);
    t("off: no number", MSBDBattInsideShows(0, 0, 0, 0), 0);
    t("on: the number", MSBDBattInsideShows(1, 0, 0, 0), 1);
    t("iPadOS's own beside it: not two numbers", MSBDBattInsideShows(1, 1, 0, 0), 0);
    t("iPadOS's own drawing keeps the number while charging", MSBDBattInsideShows(1, 0, 0, 1), 1);
    t("our number gives way to the charging bolt", MSBDBattInsideShows(1, 0, 1, 1), 0);
    t("high level on a light icon: dark text over the fill", MSBDBattInsideTextIsDark(0.9, 1), 1);
    t("low level on a light icon: light text on the empty part", MSBDBattInsideTextIsDark(0.2, 1), 0);
    t("high level on a dark icon: light text", MSBDBattInsideTextIsDark(0.9, 0), 0);
    t("low level on a dark icon: dark text", MSBDBattInsideTextIsDark(0.2, 0), 1);
    return fails;
}
