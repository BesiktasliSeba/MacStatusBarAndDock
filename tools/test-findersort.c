// test-findersort.c: sorting in Finder (common/FinderSort.h, 1.8.4.2 item 4), as a Mac's Finder sorts: the keys and their first directions, a
// header's click and Sort By's pick, what is kept per folder, and the order itself -- unknown dates and sizes last either way, ties by name, Keep
// Folders on Top only when sorting by name, None in the folder's own order.
#include <stdio.h>
#include <string.h>
#include "../common/FinderSort.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }

// Six items, as a folder might list them (index = the folder's own order). Names by rank: Apps(0) beta(1) Docs(2) photo2(3) photo10(4) zeta(5).
//   idx name     folder kind(rank)       modified  created   added    size
//   0   zeta     file   Text(2)          300       100       -        50
//   1   Docs     folder Folder(1)        100       -         40       (not worked out)
//   2   photo10  file   JPEG image(0)    200       300       10       700
//   3   beta     file   Text(2)          -         200       30       50
//   4   Apps     folder Folder(1)        400       50        20       9000
//   5   photo2   file   JPEG image(0)    200       300       -        700
static MSBDSortItem items[6];
static void setup(void) {
    memset(items, 0, sizeof items);
    struct { long name, kind; int folder, hm; double m; int hc; double c; int ha; double a; int hs; unsigned long long s; } d[6] = {
        { 5, 2, 0, 1, 300, 1, 100, 0, 0, 1, 50 },
        { 2, 1, 1, 1, 100, 0, 0, 1, 40, 0, 0 },
        { 4, 0, 0, 1, 200, 1, 300, 1, 10, 1, 700 },
        { 1, 2, 0, 0, 0, 1, 200, 1, 30, 1, 50 },
        { 0, 1, 1, 1, 400, 1, 50, 1, 20, 1, 9000 },
        { 3, 0, 0, 1, 200, 1, 300, 0, 0, 1, 700 },
    };
    for (int i = 0; i < 6; i++) {
        items[i].index = i; items[i].nameRank = d[i].name; items[i].kindRank = d[i].kind; items[i].folder = d[i].folder;
        items[i].hasModified = d[i].hm; items[i].modified = d[i].m; items[i].hasCreated = d[i].hc; items[i].created = d[i].c;
        items[i].hasAdded = d[i].ha; items[i].added = d[i].a; items[i].hasSize = d[i].hs; items[i].size = d[i].s;
    }
}
static int order(int key, int asc, int top, const long *want) {
    long got[6]; MSBDSortChoice c = { key, asc };
    if (!MSBDSortOrder(items, 6, c, top, got)) return 0;
    int ok = memcmp(got, want, sizeof got) == 0;
    if (!ok) { printf("      got:"); for (int i = 0; i < 6; i++) printf(" %ld", got[i]); printf("\n"); }
    return ok;
}
int main(void) {
    setup();
    // ---- keys, words, directions
    check("Sort By offers None, Name, Kind, Date Added, Date Modified, Date Created, Size, in the Mac's order (no Date Last Opened)",
          MSBD_SORT_MENU_COUNT == 7 && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[0]), "None") && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[1]), "Name")
          && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[2]), "Kind") && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[3]), "Date Added")
          && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[4]), "Date Modified") && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[5]), "Date Created")
          && !strcmp(MSBDSortTitle(kMSBDSortMenuKeys[6]), "Size"));
    check("the list's headers, left to right: Name, Date Modified, Size, Kind", MSBDSortColumnKey(0) == MSBD_SORT_NAME && MSBDSortColumnKey(1) == MSBD_SORT_MODIFIED
          && MSBDSortColumnKey(2) == MSBD_SORT_SIZE && MSBDSortColumnKey(3) == MSBD_SORT_KIND && MSBDSortColumnKey(4) == -1 && MSBDSortColumnKey(-1) == -1);
    check("first directions as on a Mac: names and kinds A to Z, dates newest first, sizes largest first",
          MSBDSortFirstAscending(MSBD_SORT_NAME) && MSBDSortFirstAscending(MSBD_SORT_KIND) && !MSBDSortFirstAscending(MSBD_SORT_MODIFIED)
          && !MSBDSortFirstAscending(MSBD_SORT_CREATED) && !MSBDSortFirstAscending(MSBD_SORT_ADDED) && !MSBDSortFirstAscending(MSBD_SORT_SIZE));
    check("a folder never sorted: Name, A to Z", kMSBDSortDefault.key == MSBD_SORT_NAME && kMSBDSortDefault.ascending == 1);
    // ---- clicks and picks
    MSBDSortChoice name = { MSBD_SORT_NAME, 1 }, c;
    c = MSBDSortClick(name, MSBD_SORT_NAME);
    check("a click on the sorted column turns it round (Name: Z to A), again: back", c.key == MSBD_SORT_NAME && !c.ascending && MSBDSortClick(c, MSBD_SORT_NAME).ascending);
    c = MSBDSortClick(name, MSBD_SORT_MODIFIED);
    check("  ... another column: its key, its first direction (Date Modified: newest first)", c.key == MSBD_SORT_MODIFIED && !c.ascending);
    c = MSBDSortClick(c, MSBD_SORT_SIZE);
    check("  ... Size after it: largest first", c.key == MSBD_SORT_SIZE && !c.ascending);
    c = MSBDSortClick((MSBDSortChoice){ MSBD_SORT_SIZE, 1 }, MSBD_SORT_KIND);
    check("  ... Kind after an ascending Size: A to Z (not the last direction)", c.key == MSBD_SORT_KIND && c.ascending);
    check("  ... a column that is no key: nothing changes", MSBDSortClick(name, 99).key == MSBD_SORT_NAME && MSBDSortClick(name, -1).ascending);
    c = MSBDSortPick((MSBDSortChoice){ MSBD_SORT_SIZE, 1 }, MSBD_SORT_SIZE);
    check("Sort By picking the key it has: kept as it is (the direction is the header's)", c.key == MSBD_SORT_SIZE && c.ascending);
    c = MSBDSortPick(name, MSBD_SORT_CREATED);
    check("  ... another key: its first direction (Date Created: newest first)", c.key == MSBD_SORT_CREATED && !c.ascending);
    check("  ... None", MSBDSortPick(name, MSBD_SORT_NONE).key == MSBD_SORT_NONE && MSBDSortPick(name, MSBD_SORT_NONE).ascending);
    check("the chevron: in the sorted column's header; none for None, Date Added or Date Created (no column)",
          MSBDSortChevronColumn(name) == 0 && MSBDSortChevronColumn((MSBDSortChoice){ MSBD_SORT_KIND, 0 }) == 3 && MSBDSortChevronColumn((MSBDSortChoice){ MSBD_SORT_SIZE, 0 }) == 2
          && MSBDSortChevronColumn((MSBDSortChoice){ MSBD_SORT_NONE, 1 }) == -1 && MSBDSortChevronColumn((MSBDSortChoice){ MSBD_SORT_ADDED, 0 }) == -1);
    // ---- kept per folder
    char buf[32];
    check("kept as words: \"modified-\" (newest first), \"kind\" (A to Z)",
          MSBDSortStore((MSBDSortChoice){ MSBD_SORT_MODIFIED, 0 }, buf, sizeof buf) == 9 && !strcmp(buf, "modified-")
          && MSBDSortStore((MSBDSortChoice){ MSBD_SORT_KIND, 1 }, buf, sizeof buf) == 4 && !strcmp(buf, "kind"));
    check("  ... read back, every key both ways", ({ int ok = 1; for (int k = 0; k < MSBD_SORT_COUNT; k++) for (int a = 0; a < 2; a++) {
              MSBDSortChoice w = { k, k == MSBD_SORT_NONE ? 1 : a }, r; MSBDSortStore(w, buf, sizeof buf); r = MSBDSortRead(buf); if (r.key != w.key || r.ascending != w.ascending) ok = 0; } ok; }));
    check("  ... nothing, unknown words, a lone \"-\": the default", MSBDSortIsDefault(MSBDSortRead(NULL)) && MSBDSortIsDefault(MSBDSortRead(""))
          && MSBDSortIsDefault(MSBDSortRead("lastopened")) && MSBDSortIsDefault(MSBDSortRead("-")) && MSBDSortIsDefault(MSBDSortRead("names")));
    check("  ... no room: nothing written", MSBDSortStore((MSBDSortChoice){ MSBD_SORT_MODIFIED, 0 }, buf, 9) == 0 && buf[0] == 0);
    check("  ... the default is Name A to Z only", MSBDSortIsDefault(name) && !MSBDSortIsDefault((MSBDSortChoice){ MSBD_SORT_NAME, 0 }) && !MSBDSortIsDefault((MSBDSortChoice){ MSBD_SORT_SIZE, 1 }));
    // ---- the order
    check("Name A to Z: Apps, beta, Docs, photo2, photo10, zeta", order(MSBD_SORT_NAME, 1, 0, (long[]){ 4, 3, 1, 5, 2, 0 }));
    check("Name Z to A", order(MSBD_SORT_NAME, 0, 0, (long[]){ 0, 2, 5, 1, 3, 4 }));
    check("Keep Folders on Top, by name: Apps, Docs, then the files A to Z", order(MSBD_SORT_NAME, 1, 1, (long[]){ 4, 1, 3, 5, 2, 0 }));
    check("  ... Z to A: still the folders first (each part Z to A)", order(MSBD_SORT_NAME, 0, 1, (long[]){ 1, 4, 0, 2, 5, 3 }));
    check("  ... not when sorting by anything else (as macOS: \"when sorting by name\")", order(MSBD_SORT_SIZE, 0, 1, (long[]){ 4, 5, 2, 3, 0, 1 }));
    check("None: the folder's own order, whichever way and with folders on top", order(MSBD_SORT_NONE, 1, 0, (long[]){ 0, 1, 2, 3, 4, 5 })
          && order(MSBD_SORT_NONE, 0, 1, (long[]){ 0, 1, 2, 3, 4, 5 }));
    check("Kind A to Z (JPEG image, Folder, Text), each kind by name", order(MSBD_SORT_KIND, 1, 0, (long[]){ 5, 2, 4, 1, 3, 0 }));
    check("  ... Z to A: the kinds turned round, names still A to Z within a kind", order(MSBD_SORT_KIND, 0, 0, (long[]){ 3, 0, 4, 1, 5, 2 }));
    check("Date Modified newest first; the same date by name (photo2 before photo10); none known (beta) last", order(MSBD_SORT_MODIFIED, 0, 0, (long[]){ 4, 0, 5, 2, 1, 3 }));
    check("  ... oldest first: none known still last", order(MSBD_SORT_MODIFIED, 1, 0, (long[]){ 1, 5, 2, 0, 4, 3 }));
    check("Date Created newest first (Docs: unknown, last)", order(MSBD_SORT_CREATED, 0, 0, (long[]){ 5, 2, 3, 0, 4, 1 }));
    check("Date Added newest first (zeta and photo2: unknown, last, by name)", order(MSBD_SORT_ADDED, 0, 0, (long[]){ 1, 3, 4, 2, 5, 0 }));
    check("Size largest first; a folder not worked out yet (Docs) last", order(MSBD_SORT_SIZE, 0, 0, (long[]){ 4, 5, 2, 3, 0, 1 }));
    check("  ... smallest first: Docs still last", order(MSBD_SORT_SIZE, 1, 0, (long[]){ 3, 0, 5, 2, 4, 1 }));
    items[1].hasSize = 1; items[1].size = 800;
    check("  ... its size in: it takes its place (after Apps, before the photos)", order(MSBD_SORT_SIZE, 0, 0, (long[]){ 4, 1, 5, 2, 3, 0 }));
    setup();
    {   // the same name twice (two drives' Trashes): the folder's own order decides, never the sort's steps
        MSBDSortItem two[3] = { { .index = 2, .nameRank = 7 }, { .index = 0, .nameRank = 7 }, { .index = 1, .nameRank = 3 } };
        long got[3]; MSBDSortOrder(two, 3, (MSBDSortChoice){ MSBD_SORT_SIZE, 0 }, 0, got);
        check("equal in everything: by name, then the folder's own order", got[0] == 2 && got[1] == 1 && got[2] == 0);
        check("  ... compare is never 0 for two items", MSBDSortCompare(&two[0], &two[1], name, 0) != 0 && MSBDSortCompare(&two[0], &two[1], name, 0) == -MSBDSortCompare(&two[1], &two[0], name, 0));
    }
    {   // many items: sorted, and every item once (the merge sort's runs and their odd ends)
        enum { N = 1000 }; static MSBDSortItem many[N]; static long got[N]; static int seen[N]; int ok = 1;
        for (int i = 0; i < N; i++) { memset(&many[i], 0, sizeof many[i]); many[i].index = i; many[i].nameRank = (i * 7919) % N; many[i].hasSize = i % 13 != 0; many[i].size = (unsigned long long)((i * 104729) % 977); }
        MSBDSortChoice bySize = { MSBD_SORT_SIZE, 0 };
        if (!MSBDSortOrder(many, N, bySize, 0, got)) ok = 0;
        for (int i = 0; ok && i < N; i++) { if (got[i] < 0 || got[i] >= N || seen[got[i]]++) ok = 0; }
        for (int i = 1; ok && i < N; i++) if (MSBDSortCompare(&many[got[i - 1]], &many[got[i]], bySize, 0) >= 0) ok = 0;
        check("1000 items by size: in order, each once", ok);
        long one; check("  ... one item, none: nothing to do", MSBDSortOrder(many, 1, bySize, 0, &one) && one == 0 && MSBDSortOrder(many, 0, bySize, 0, got));
    }
    if (fails) { printf("test-findersort (compiled): FAILED\n"); return 1; }
    printf("test-findersort (compiled): all checks pass\n"); return 0;
}
