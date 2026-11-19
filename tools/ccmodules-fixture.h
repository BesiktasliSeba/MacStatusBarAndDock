// ccmodules-fixture.h -- for the Mac tests of Control Center's module lists (test-ccmodule.m, test-ccautoadd.m, test-cclayout.c): reads a list as
// read on one of the test iPads. Those lists are private (tools/crash-fixtures/installed/<iPad>/ccmodules.txt; that folder is not in the public
// tree), so each test runs its checks on a placeholder list of the same shape in its own code (com.example.* for other tweaks' modules) and,
// where the folder is here, on the real lists too; without it that part prints SKIP (1.8.7.9).
// The file: one module a line, "<list> <module identifier> [<columns> <rows>]"; a line starting with # is a comment.
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

typedef struct { char mid[160]; int w, h; } MSBDTestCCModule;   // (w, h: 0 where the line gives no size)

// Whether the private folder is here (no: the public tree; that part of the test is a SKIP).
static inline int MSBDTestCCFixturesHere(const char *installed) {
    struct stat st;
    return installed && stat(installed, &st) == 0 && S_ISDIR(st.st_mode);
}

// The modules of one list of one iPad, in the file's order; how many there are: 0 when the file or the list is not there, or the list has more
// than max (the test then fails on the count).
static inline int MSBDTestCCList(const char *installed, const char *dev, const char *list, MSBDTestCCModule *out, int max) {
    char path[1024], line[512];
    snprintf(path, sizeof path, "%s/%s/ccmodules.txt", installed, dev);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    int n = 0, over = 0;
    while (fgets(line, sizeof line, f)) {
        char name[64], mid[160];
        int w = 0, h = 0, got;
        if (line[0] == '#') continue;
        got = sscanf(line, "%63s %159s %d %d", name, mid, &w, &h);
        if (got < 2 || strcmp(name, list)) continue;
        if (n == max) { over = 1; break; }
        snprintf(out[n].mid, sizeof out[n].mid, "%s", mid);
        out[n].w = got == 4 ? w : 0; out[n].h = got == 4 ? h : 0;
        n++;
    }
    fclose(f);
    return over ? 0 : n;
}

#ifdef __OBJC__
// The same list as identifiers (nil when it is not there).
static inline NSArray<NSString *> *MSBDTestCCListIDs(const char *installed, const char *dev, const char *list) {
    MSBDTestCCModule m[64];
    int n = MSBDTestCCList(installed, dev, list, m, 64);
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (int i = 0; i < n; i++) [ids addObject:[NSString stringWithUTF8String:m[i].mid]];
    return n ? ids : nil;
}
#endif
