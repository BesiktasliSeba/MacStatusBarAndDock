// Mac test of the Activity Monitor window's columns (statusbar/ActMonColumns.h, used by statusbar/ActivityMonitor.h): in every tab, at the window's
// smallest width (520 pt) and its largest first width (900 pt), every column title fits its label with the sort arrow on it (as the window draws
// it: the system font, 11 pt semibold, and bold as with Bold Text on), and the widest figures of each column fit its cells (12 pt, monospaced
// digits); the columns keep their order and the Process column keeps room. The 29 Oct case: "Memory ↓" and "Network ↓" in 54 pt.
#import <AppKit/AppKit.h>
#include "../statusbar/ActMonColumns.h"
static int fails = 0, checks = 0;
#define CHECK(cond, ...) do { checks++; if (!(cond)) { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static double W(NSString *s, NSFont *f) { return [s sizeWithAttributes:@{NSFontAttributeName: f}].width; }

#ifdef AM_SORT
// The rows' sort (1.8.7.5, audit L77 of 1.8.7.2: sorting by CPU Time sorted by % CPU): the real comparator of -[DMActivityMonitor dm_rowsNow], the
// tab's metric (-dm_metric:), the tabs and the process record, cut out of ActivityMonitor.h and ProcList.h by actmonsort-cut.py, run on a stand-in
// window holding the four ivars they read. In every tab, for every column and both directions, the order must follow what that column shows: its
// figure (a missing one, shown "–", below every figure), equal figures by name, then pid.
#include "amsort-procinfo.h"
#include "amsort-tab.h"
@interface AMSortWindow : NSObject { @public DMAMTab _tab; NSInteger _sortCol, _colCount; BOOL _sortDesc; }
@end
@implementation AMSortWindow
#include "amsort-metric.h"
- (void)sortRows:(NSMutableArray<DMProcInfo *> *)rows {
#include "amsort-sort.h"
}
@end
static DMProcInfo *Proc(NSString *name, int pid, double cpu, uint64_t ns, int threads, uint64_t mem, uint64_t disk, BOOL stats) {
    DMProcInfo *p = [DMProcInfo new];
    p.name = name; p.pid = pid; p.cpuPercent = cpu; p.cpuNs = ns; p.threads = threads; p.footprint = mem; p.disk = disk; p.haveStats = stats;
    return p;
}
// What a column shows, as a number to order by (NAN: the name); a missing figure as -1 (below 0).
static double Shown(DMProcInfo *p, int tab, int col, int n) {
    if (col == 0) return NAN;
    if (col == n - 1) return p.pid;
    if (tab == MSBD_AM_CPU) return col == 1 ? p.cpuPercent : col == 2 ? (p.haveStats ? (double)p.cpuNs : -1) : p.threads;
    if (col == 2) return p.threads;
    return tab == MSBD_AM_MEMORY ? (double)p.footprint : tab == MSBD_AM_DISK ? (double)p.disk : 0;   // (Energy, Network: no per-process figure)
}
static NSArray<NSString *> *Names(NSArray<DMProcInfo *> *rows) { NSMutableArray *a = [NSMutableArray array]; for (DMProcInfo *p in rows) [a addObject:[NSString stringWithFormat:@"%@/%d", p.name, p.pid]]; return a; }
static void SortChecks(void) {
    const char *names[] = { "CPU", "Memory", "Energy", "Disk", "Network" };
    NSArray<DMProcInfo *> *all = @[
        Proc(@"Delta", 50, 5.0, 300000000ULL, 3, 400ULL << 20, 20ULL << 20, YES), Proc(@"alpha", 10, 1.0, 900000000ULL, 9, 100ULL << 20, 50ULL << 20, YES),
        Proc(@"Charlie", 30, 9.0, 100000000ULL, 1, 300ULL << 20, 40ULL << 20, YES), Proc(@"bravo", 20, 3.0, 500000000ULL, 7, 500ULL << 20, 10ULL << 20, YES),
        Proc(@"echo", 45, 7.0, 700000000ULL, 5, 200ULL << 20, 30ULL << 20, YES), Proc(@"echo", 40, 7.0, 700000000ULL, 5, 200ULL << 20, 30ULL << 20, YES),
        Proc(@"zebra", 60, 0.0, 0, 1, 50ULL << 20, 0, YES),            // (just started: 0 CPU time, a figure)
        Proc(@"aardvark", 70, -1.0, 0, -1, 0, 0, NO),                 // (no figures: "–" everywhere but its name and pid)
    ];
    AMSortWindow *win = [AMSortWindow new];
    for (int tab = MSBD_AM_CPU; tab <= MSBD_AM_NETWORK; tab++) {
        const char *t[MSBD_AM_MAX_COLUMNS]; int n = MSBDActMonTitles(tab, t);
        for (int col = 0; col < n; col++) for (int desc = 0; desc < 2; desc++) {
            win->_tab = (DMAMTab)tab; win->_colCount = n; win->_sortCol = col; win->_sortDesc = desc;
            NSMutableArray<DMProcInfo *> *rows = [all mutableCopy];
            [win sortRows:rows];
            BOOL ok = rows.count == all.count;
            for (NSUInteger i = 0; ok && i + 1 < rows.count; i++) {
                DMProcInfo *x = rows[i], *y = rows[i + 1];
                double kx = Shown(x, tab, col, n), ky = Shown(y, tab, col, n);
                NSComparisonResult c = col == 0 ? [x.name localizedCaseInsensitiveCompare:y.name] : (kx < ky ? NSOrderedAscending : kx > ky ? NSOrderedDescending : NSOrderedSame);
                if (c == (desc ? NSOrderedAscending : NSOrderedDescending)) ok = NO;   // (out of the column's order)
                else if (c == NSOrderedSame) {   // (equal: by name, then pid, whichever way the column goes)
                    NSComparisonResult nm = [x.name localizedCaseInsensitiveCompare:y.name];
                    if (nm == NSOrderedDescending || (nm == NSOrderedSame && x.pid > y.pid)) ok = NO;
                }
            }
            CHECK(ok, "%s tab, sorted by \"%s\" %s: the rows follow that column (%s)", names[tab], t[col], desc ? "largest first" : "smallest first",
                  [[Names(rows) componentsJoinedByString:@" "] UTF8String]);
        }
    }
    // The audit's case, as the device row has it: the CPU tab, the CPU Time title tapped (largest first), then again (smallest first).
    win->_tab = DMAMTabCPU; win->_colCount = 5; win->_sortCol = 2; win->_sortDesc = YES;
    NSMutableArray<DMProcInfo *> *rows = [all mutableCopy]; [win sortRows:rows];
    CHECK([[Names(rows) componentsJoinedByString:@" "] isEqualToString:@"alpha/10 echo/40 echo/45 bravo/20 Delta/50 Charlie/30 zebra/60 aardvark/70"],
          "CPU Time, largest first: by CPU time, the row without figures last (%s)", [[Names(rows) componentsJoinedByString:@" "] UTF8String]);
    BOOL cpuInOrder = YES;
    for (NSUInteger i = 0; i + 1 < rows.count; i++) if (rows[i].cpuPercent < rows[i + 1].cpuPercent) cpuInOrder = NO;
    CHECK(!cpuInOrder, "  ... the %% CPU column is not in order there (the rows' %% CPU and CPU Time orders differ)");
    win->_sortDesc = NO; rows = [all mutableCopy]; [win sortRows:rows];
    CHECK([[Names(rows) componentsJoinedByString:@" "] isEqualToString:@"aardvark/70 zebra/60 Charlie/30 Delta/50 bravo/20 echo/40 echo/45 alpha/10"],
          "CPU Time, smallest first: the row without figures first, then 0 (%s)", [[Names(rows) componentsJoinedByString:@" "] UTF8String]);
    win->_sortCol = 1; win->_sortDesc = YES; rows = [all mutableCopy]; [win sortRows:rows];
    CHECK([[Names(rows) componentsJoinedByString:@" "] isEqualToString:@"Charlie/30 echo/40 echo/45 Delta/50 bravo/20 alpha/10 zebra/60 aardvark/70"],
          "%% CPU, largest first: as before (%s)", [[Names(rows) componentsJoinedByString:@" "] UTF8String]);
}
#endif

int main(void) {
    @autoreleasepool {
#ifdef AM_SORT
        SortChecks();
#endif
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
