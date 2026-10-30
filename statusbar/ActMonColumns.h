// ActMonColumns.h -- the Activity Monitor window's columns (ActivityMonitor.h): each tab's titles and where its columns sit, pure C so the Mac test
// (tools/test-actmoncolumns.m) checks that every title fits its column with the sort arrow, in every tab, at the window's smallest and largest
// widths. A wide Process column on the left, the tab's figures on the right: % CPU 60 pt, every other figure 92 pt, PID 64 pt. (Memory, Energy,
// Disk and Network had the 60 pt of % CPU; the figure a tab sorts by at first carries the arrow, and "Memory ↓" / "Network ↓" did not fit:
// "Memor...", "Networ...", 29 Oct.)
#ifndef MSBD_ACTMON_COLUMNS_H
#define MSBD_ACTMON_COLUMNS_H
#include "../common/ActMonText.h"   // (the tabs: MSBD_AM_CPU ...)

enum { MSBD_AM_MAX_COLUMNS = 5 };
// The tab's column titles, left to right; returns how many.
static inline int MSBDActMonTitles(int tab, const char **titles) {
    switch (tab) {
        case MSBD_AM_CPU:    titles[0] = "Process"; titles[1] = "% CPU"; titles[2] = "CPU Time"; titles[3] = "Threads"; titles[4] = "PID"; return 5;
        case MSBD_AM_MEMORY: titles[1] = "Memory"; break;
        case MSBD_AM_ENERGY: titles[1] = "Energy"; break;
        case MSBD_AM_DISK:   titles[1] = "Disk"; break;
        default:             titles[1] = "Network"; break;
    }
    titles[0] = "Process"; titles[2] = "Threads"; titles[3] = "PID";
    return 4;
}
// The columns' left edges in a table w pt wide, as many as the tab's titles. A column's label (and its cells) end 6 pt before the next column, the
// last one 10 pt before the table's right side.
static const double kMSBDAMColumnGap = 6.0, kMSBDAMRightInset = 10.0;
static inline int MSBDActMonColumnEdges(int tab, double w, double *edges) {
    const double right = w - kMSBDAMRightInset, pidW = 64, numW = 92, cpuW = 60;
    edges[0] = 12;
    if (tab == MSBD_AM_CPU) {
        edges[1] = right - pidW - numW - numW - cpuW; edges[2] = right - pidW - numW - numW; edges[3] = right - pidW - numW; edges[4] = right - pidW;
        return 5;
    }
    edges[1] = right - pidW - numW - numW; edges[2] = right - pidW - numW; edges[3] = right - pidW;
    return 4;
}

#endif
