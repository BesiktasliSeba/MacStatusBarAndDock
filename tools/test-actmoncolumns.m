// Mac test of the Activity Monitor window's columns (statusbar/ActMonColumns.h, used by statusbar/ActivityMonitor.h): in every tab, at the window's
// smallest width (520 pt) and its largest first width (900 pt), every column title fits its label with the sort arrow on it (as the window draws
// it: the system font, 11 pt semibold, and bold as with Bold Text on), and the widest figures of each column fit its cells (12 pt, monospaced
// digits); the columns keep their order and the Process column keeps room. The 29 Oct case: "Memory ↓" and "Network ↓" in 54 pt.
#import <AppKit/AppKit.h>
#include "../statusbar/ActMonColumns.h"
static int fails = 0, checks = 0;
#define CHECK(cond, ...) do { checks++; if (!(cond)) { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static double W(NSString *s, NSFont *f) { return [s sizeWithAttributes:@{NSFontAttributeName: f}].width; }
int main(void) {
    @autoreleasepool {
        NSFont *head = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold], *headBold = [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
        NSFont *cell = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
        const double margin = 2.0;   // (room left over: iPadOS's system font is not exactly the Mac's)
        const char *names[] = { "CPU", "Memory", "Energy", "Disk", "Network" };
        // the widest figure each figure column shows (common/SystemStats.h MSBDFormatBytes: "%.0f MB" under 1000 MB, then "%.1f GB")
        NSArray *wide[] = { @[@"800.0", @"100.0", @"–"], @[@"999 MB", @"16.0 GB", @"–"], @[@"–"], @[@"999 MB", @"999.9 GB", @"–"], @[@"–"] };
        for (int tab = MSBD_AM_CPU; tab <= MSBD_AM_NETWORK; tab++) {
            const char *t[MSBD_AM_MAX_COLUMNS]; int n = MSBDActMonTitles(tab, t);
            CHECK(n == (tab == MSBD_AM_CPU ? 5 : 4), "%s: %d columns", names[tab], n);
            CHECK(!strcmp(t[0], "Process") && !strcmp(t[n - 1], "PID") && !strcmp(t[n - 2], "Threads"), "%s: Process first, Threads and PID last", names[tab]);
            for (int wi = 0; wi < 2; wi++) {
                double w = wi ? 900.0 : 520.0, e[MSBD_AM_MAX_COLUMNS];
                int m = MSBDActMonColumnEdges(tab, w, e);
                CHECK(m == n, "%s at %.0f: edges for every title (%d of %d)", names[tab], w, m, n);
                for (int i = 0; i < n; i++) {
                    double next = i + 1 < n ? e[i + 1] : w - kMSBDAMRightInset, label = next - e[i] - kMSBDAMColumnGap;
                    if (i + 1 < n) CHECK(e[i + 1] > e[i], "%s at %.0f: column %d after column %d", names[tab], w, i + 1, i);
                    for (int bold = 0; bold < 2; bold++) for (int arrow = 0; arrow < 2; arrow++) {
                        NSString *title = [NSString stringWithFormat:@"%s%@", t[i], arrow ? @" ↓" : @""];
                        double tw = W(title, bold ? headBold : head);
                        CHECK(tw + margin <= label, "%s at %.0f: \"%s\" (%.1f pt%s) fits its %.1f pt label", names[tab], w, title.UTF8String, tw, bold ? ", bold" : "", label);
                    }
                    if (i == 1) for (NSString *v in wide[tab]) CHECK(W(v, cell) + margin <= label, "%s at %.0f: the figure \"%s\" (%.1f pt) fits its %.1f pt cell", names[tab], w, v.UTF8String, W(v, cell), label);
                    if (tab == MSBD_AM_CPU && i == 2) CHECK(W(@"999:59.99", cell) + margin <= label, "CPU at %.0f: a long CPU Time fits", w);
                    if (i == n - 1) CHECK(W(@"99999", cell) + margin <= label, "%s at %.0f: a five-digit PID fits", names[tab], w);
                    if (i == n - 2) CHECK(W(@"9999", cell) + margin <= label, "%s at %.0f: thread counts fit", names[tab], w);
                }
                CHECK(e[1] - e[0] - kMSBDAMColumnGap >= 180.0, "%s at %.0f: the Process column keeps room (%.0f pt)", names[tab], w, e[1] - e[0] - kMSBDAMColumnGap);
            }
        }
        // the figure columns other than % CPU are as wide as CPU Time (92 pt), % CPU stays 60 pt, PID 64 pt
        double c[MSBD_AM_MAX_COLUMNS], m[MSBD_AM_MAX_COLUMNS];
        MSBDActMonColumnEdges(MSBD_AM_CPU, 900, c); MSBDActMonColumnEdges(MSBD_AM_MEMORY, 900, m);
        CHECK(c[2] - c[1] == 60 && c[3] - c[2] == 92 && c[4] - c[3] == 92 && 900 - kMSBDAMRightInset - c[4] == 64, "CPU: 60 / 92 / 92 / 64 pt");
        CHECK(m[2] - m[1] == 92 && m[3] - m[2] == 92 && 900 - kMSBDAMRightInset - m[3] == 64, "Memory: 92 / 92 / 64 pt");
        CHECK(c[3] == m[2] && c[4] == m[3], "Threads and PID sit in the same place in every tab");
    }
    printf("%s: %d of %d checks passed\n", fails ? "FAIL" : "PASS", checks - fails, checks);
    return fails ? 1 : 0;
}
