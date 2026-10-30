// Mac test of common/SystemStats.h (run by test-systemstats.sh).
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "../common/SystemStats.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    const uint64_t GB = 1073741824ull, MB = 1048576ull, page = 16384;
    // 4 GB iPad (17.5 iPad7,1): 1.1 GB active, 0.9 GB wired, 0.2 GB compressed, 0.7 GB free, 1.1 GB inactive
    MSBDMemory m = MSBDMemoryFromCounts(4 * GB, page, (1100 * MB) / page, (1100 * MB) / page, (900 * MB) / page, (200 * MB) / page, (700 * MB) / page);
    CHECK(m.used == 2200 * MB, "used = active + wired + compressed (%llu MB)", m.used / MB);
    CHECK(m.available == 4 * GB - 2200 * MB, "available = total - used (%llu MB)", m.available / MB);
    CHECK(m.used + m.available == m.total, "used + available = total");
    CHECK(m.available > m.freeBytes, "available counts more than the free pages (Memory Magic's Free RAM)");
    // more counted than there is (a counter racing the others): never negative
    MSBDMemory over = MSBDMemoryFromCounts(1 * GB, page, (900 * MB) / page, 0, (300 * MB) / page, 0, 0);
    CHECK(over.used == 1 * GB && over.available == 0, "used capped at the total, available 0");
    // CPU: 8 cores' ticks
    MSBDCPUTicks a = { 1000, 500, 0, 8500, 8 }, b = { 1100, 550, 0, 9350, 8 };
    double u = -1, s = -1, l = MSBDCPULoadBetween(a, b, &u, &s);
    CHECK(l > 0.149 && l < 0.151, "load 150 busy of 1000 = 15%% (%.3f)", l);
    CHECK(u > 0.099 && u < 0.101 && s > 0.049 && s < 0.051, "user 10%%, system 5%% (%.3f %.3f)", u, s);
    CHECK(MSBDCPULoadBetween(b, a, NULL, NULL) < 0.0, "a counter that went back: no value");
    CHECK(MSBDCPULoadBetween(a, a, NULL, NULL) < 0.0, "no time between the samples: no value");
    MSBDCPUTicks c = { 1000, 500, 0, 8500, 8 }, d = { 2000, 1500, 0, 8500, 8 };
    CHECK(MSBDCPULoadBetween(c, d, NULL, NULL) == 1.0, "all busy = 100%%");
    // formatting
    char buf[32];
    MSBDFormatBytes(820 * MB, buf, sizeof buf); CHECK(!strcmp(buf, "820 MB"), "820 MB -> %s", buf);
    MSBDFormatBytes((uint64_t)(1.9 * GB), buf, sizeof buf); CHECK(!strcmp(buf, "1.9 GB"), "1.9 GB -> %s", buf);
    MSBDFormatBytes(16 * GB, buf, sizeof buf); CHECK(!strcmp(buf, "16.0 GB"), "16 GB -> %s", buf);   // (1.7.0: one decimal at every size)
    MSBDFormatBytes((uint64_t)(11.6 * GB), buf, sizeof buf); CHECK(!strcmp(buf, "11.6 GB"), "11.6 GB -> %s (as the tile drawn over Memory Magic's)", buf);
    MSBDFormatBytes(11878 * MB, buf, sizeof buf); CHECK(!strcmp(buf, "11.6 GB"), "11878 MB -> %s (= the old tile's %.1f of MB / 1024)", buf, 11878.0 / 1024.0);
    MSBDFormatBytes(10240 * MB, buf, sizeof buf); CHECK(!strcmp(buf, "10.0 GB"), "10 GB -> %s (no jump at 10 GB)", buf);
    MSBDFormatBytes(150 * GB, buf, sizeof buf); CHECK(!strcmp(buf, "150.0 GB"), "150 GB -> %s", buf);
    MSBDFormatBytes(999 * MB, buf, sizeof buf); CHECK(!strcmp(buf, "999 MB"), "999 MB -> %s", buf);
    MSBDFormatBytes(1000 * MB, buf, sizeof buf); CHECK(!strcmp(buf, "1.0 GB"), "1000 MB -> %s", buf);
    // live on this Mac
    MSBDMemory live;
    CHECK(MSBDMemoryNow(&live), "memory read on this Mac");
    CHECK(live.total > 1 * GB && live.used > 0 && live.available > 0 && live.used + live.available == live.total, "live memory adds up (total %llu MB, used %llu, available %llu)", live.total / MB, live.used / MB, live.available / MB);
    MSBDCPUTicks t1, t2;
    CHECK(MSBDCPUTicksNow(&t1) && t1.cores > 0, "CPU ticks read on this Mac (%u cores)", t1.cores);
    usleep(300000);
    CHECK(MSBDCPUTicksNow(&t2), "CPU ticks again");
    double ll = MSBDCPULoadBetween(t1, t2, NULL, NULL);
    CHECK(ll >= 0.0 && ll <= 1.0, "live load within 0...1 (%.3f)", ll);
    printf("test-systemstats: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
