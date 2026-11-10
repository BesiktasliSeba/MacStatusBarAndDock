// FinderSort.h -- sorting in Finder (1.8.4.2 item 4, KT 8 Nov 2026), as a Mac's Finder sorts: by Name, Kind, Date Added, Date Modified, Date Created
// or Size, or None (the order the folder lists its items in), either way. A column header's click sorts by that column, a second one turns the
// order round; the View menu's Sort By picks a key and keeps its direction. A key's first direction is the Mac's: names and kinds A to Z, dates
// newest first, sizes largest first. Items whose date or size isn't known (a drive without creation dates, a folder whose size isn't worked out
// yet) go last either way; equal items go by name, then by the listing's order, so the order never depends on the sort's own steps. Keep Folders
// on Top (Finder's setting, off by default) puts folders before files when sorting by name, as macOS's "In windows when sorting by name".
// Not offered: Date Last Opened (macOS reads it from Spotlight's kMDItemLastUsedDate; iPadOS keeps no such date for a file, and the access time
// is not it: reading a file for a thumbnail or a size changes it, and the system's volumes don't keep it), Application and Tags.
// Plain C, so the Mac test (tools/test-findersort.c) runs this very code; Finder.h (DMFinderSorted, the list's headers, the menus) feeds it:
// the names and kinds come ranked (Foundation's localizedStandardCompare), the rest as numbers.
#ifndef MSBD_FINDER_SORT_H
#define MSBD_FINDER_SORT_H
#include <stdlib.h>
#include <string.h>

enum { MSBD_SORT_NONE = 0, MSBD_SORT_NAME, MSBD_SORT_KIND, MSBD_SORT_ADDED, MSBD_SORT_MODIFIED, MSBD_SORT_CREATED, MSBD_SORT_SIZE, MSBD_SORT_COUNT };

// The View menu's Sort By, in the Mac's order (Date Last Opened, Application and Tags left out: see above).
static const int kMSBDSortMenuKeys[] = { MSBD_SORT_NONE, MSBD_SORT_NAME, MSBD_SORT_KIND, MSBD_SORT_ADDED, MSBD_SORT_MODIFIED, MSBD_SORT_CREATED, MSBD_SORT_SIZE };
#define MSBD_SORT_MENU_COUNT ((int)(sizeof(kMSBDSortMenuKeys) / sizeof(kMSBDSortMenuKeys[0])))

static inline const char *MSBDSortTitle(int key) {   // (the menus' words)
    switch (key) {
        case MSBD_SORT_NONE: return "None";
        case MSBD_SORT_NAME: return "Name";
        case MSBD_SORT_KIND: return "Kind";
        case MSBD_SORT_ADDED: return "Date Added";
        case MSBD_SORT_MODIFIED: return "Date Modified";
        case MSBD_SORT_CREATED: return "Date Created";
        case MSBD_SORT_SIZE: return "Size";
        default: return "";
    }
}
// The list's column headers, left to right (Name, Date Modified, Size, Kind): the key each one sorts by.
static inline int MSBDSortColumnKey(int column) {
    static const int keys[] = { MSBD_SORT_NAME, MSBD_SORT_MODIFIED, MSBD_SORT_SIZE, MSBD_SORT_KIND };
    return column >= 0 && column < 4 ? keys[column] : -1;
}
// A key's first direction (1: ascending -- A to Z, oldest first, smallest first): names and kinds A to Z, dates newest first, sizes largest first.
static inline int MSBDSortFirstAscending(int key) { return key == MSBD_SORT_NAME || key == MSBD_SORT_KIND || key == MSBD_SORT_NONE; }

typedef struct { int key, ascending; } MSBDSortChoice;
static const MSBDSortChoice kMSBDSortDefault = { MSBD_SORT_NAME, 1 };   // (a folder never sorted otherwise: Name, A to Z)
static inline int MSBDSortValid(MSBDSortChoice c) { return c.key >= 0 && c.key < MSBD_SORT_COUNT; }

// A column header clicked (its key): the same key again turns the order round; another key starts with its first direction.
static inline MSBDSortChoice MSBDSortClick(MSBDSortChoice now, int key) {
    MSBDSortChoice c = now;
    if (key < 0 || key >= MSBD_SORT_COUNT) return now;
    if (now.key == key && key != MSBD_SORT_NONE) c.ascending = !now.ascending;
    else { c.key = key; c.ascending = MSBDSortFirstAscending(key); }
    return c;
}
// Sort By in a menu: the key; picked again, nothing changes (as on a Mac -- the direction is the header's); another starts with its first direction.
static inline MSBDSortChoice MSBDSortPick(MSBDSortChoice now, int key) {
    if (key < 0 || key >= MSBD_SORT_COUNT || now.key == key) return now;
    MSBDSortChoice c = { key, MSBDSortFirstAscending(key) };
    return c;
}
// The header showing the chevron: its column (-1: none -- None, or a key without a column); it points up when ascending, as on a Mac.
static inline int MSBDSortChevronColumn(MSBDSortChoice c) {
    for (int i = 0; i < 4; i++) if (MSBDSortColumnKey(i) == c.key) return i;
    return -1;
}

// Kept per folder (as Finder's view options): "<key>" for ascending, "<key>-" for descending ("name", "modified-", ...). Anything unknown reads
// as the default. Returns the number of bytes written (without the 0), 0 when it doesn't fit.
static const char *const kMSBDSortNames[MSBD_SORT_COUNT] = { "none", "name", "kind", "added", "modified", "created", "size" };
static inline size_t MSBDSortStore(MSBDSortChoice c, char *out, size_t cap) {
    if (!out || !cap || !MSBDSortValid(c)) return 0;
    const char *n = kMSBDSortNames[c.key];
    size_t len = strlen(n) + (c.ascending ? 0 : 1);
    if (len + 1 > cap) { out[0] = 0; return 0; }
    memcpy(out, n, strlen(n));
    if (!c.ascending) out[len - 1] = '-';
    out[len] = 0;
    return len;
}
static inline MSBDSortChoice MSBDSortRead(const char *s) {
    if (!s || !*s) return kMSBDSortDefault;
    size_t len = strlen(s);
    int asc = 1;
    if (s[len - 1] == '-') { asc = 0; len--; }
    for (int k = 0; k < MSBD_SORT_COUNT; k++)
        if (strlen(kMSBDSortNames[k]) == len && strncmp(kMSBDSortNames[k], s, len) == 0) { MSBDSortChoice c = { k, k == MSBD_SORT_NONE ? 1 : asc }; return c; }
    return kMSBDSortDefault;
}
static inline int MSBDSortIsDefault(MSBDSortChoice c) { return c.key == kMSBDSortDefault.key && (c.ascending != 0) == (kMSBDSortDefault.ascending != 0); }

// One item as the rule sees it.
typedef struct {
    long index;                 // its place in the folder's listing (None keeps it; the last tie-break)
    long nameRank, kindRank;    // its name's and kind's place among the folder's, by Foundation's localizedStandardCompare (Finder's order)
    int folder;                 // a folder (not an app or a document package): first with Keep Folders on Top
    int hasAdded, hasModified, hasCreated, hasSize;   // (0: not known -- last, either way)
    double added, modified, created;                  // (seconds, any epoch)
    unsigned long long size;    // bytes (a folder: its worked-out size)
} MSBDSortItem;

// Folders before files: only with Keep Folders on Top, and only when sorting by name (as macOS's Finder setting says).
static inline int MSBDSortFoldersFirst(int key, int keepFoldersOnTop) { return keepFoldersOnTop && key == MSBD_SORT_NAME; }

static inline int MSBDSortCmpNum(int ha, double a, int hb, double b, int ascending) {
    if (ha != hb) return ha ? -1 : 1;   // (not known: last, whichever way)
    if (!ha || a == b) return 0;
    return (a < b) == (ascending != 0) ? -1 : 1;
}
// <0: a before b. Never 0 for two different items (the listing's order decides last).
static inline int MSBDSortCompare(const MSBDSortItem *a, const MSBDSortItem *b, MSBDSortChoice c, int keepFoldersOnTop) {
    int asc = c.ascending != 0, r = 0;
    if (c.key == MSBD_SORT_NONE) return a->index < b->index ? -1 : a->index > b->index ? 1 : 0;
    if (MSBDSortFoldersFirst(c.key, keepFoldersOnTop) && (a->folder != 0) != (b->folder != 0)) return a->folder ? -1 : 1;
    switch (c.key) {
        case MSBD_SORT_NAME: r = a->nameRank < b->nameRank ? -1 : a->nameRank > b->nameRank ? 1 : 0; if (!asc) r = -r; break;
        case MSBD_SORT_KIND: r = a->kindRank < b->kindRank ? -1 : a->kindRank > b->kindRank ? 1 : 0; if (!asc) r = -r; break;
        case MSBD_SORT_ADDED: r = MSBDSortCmpNum(a->hasAdded, a->added, b->hasAdded, b->added, asc); break;
        case MSBD_SORT_MODIFIED: r = MSBDSortCmpNum(a->hasModified, a->modified, b->hasModified, b->modified, asc); break;
        case MSBD_SORT_CREATED: r = MSBDSortCmpNum(a->hasCreated, a->created, b->hasCreated, b->created, asc); break;
        case MSBD_SORT_SIZE: r = MSBDSortCmpNum(a->hasSize, (double)a->size, b->hasSize, (double)b->size, asc); break;
        default: break;
    }
    if (r) return r;
    if (a->nameRank != b->nameRank) return a->nameRank < b->nameRank ? -1 : 1;   // (equal: by name, A to Z, as on a Mac)
    return a->index < b->index ? -1 : a->index > b->index ? 1 : 0;
}
// The items in order: order[i] is the item (its position in `items`) shown i-th. A merge sort (stable, n log n, no qsort_r variants). 0: no memory
// (order is then the items' own order).
static inline int MSBDSortOrder(const MSBDSortItem *items, long n, MSBDSortChoice c, int keepFoldersOnTop, long *order) {
    for (long i = 0; i < n; i++) order[i] = i;
    if (n < 2) return 1;
    long *tmp = (long *)malloc((size_t)n * sizeof(long));
    if (!tmp) return 0;
    for (long w = 1; w < n; w *= 2) {
        for (long lo = 0; lo < n; lo += 2 * w) {
            long mid = lo + w < n ? lo + w : n, hi = lo + 2 * w < n ? lo + 2 * w : n, i = lo, j = mid, k = lo;
            while (i < mid && j < hi) tmp[k++] = MSBDSortCompare(&items[order[j]], &items[order[i]], c, keepFoldersOnTop) < 0 ? order[j++] : order[i++];
            while (i < mid) tmp[k++] = order[i++];
            while (j < hi) tmp[k++] = order[j++];
        }
        memcpy(order, tmp, (size_t)n * sizeof(long));
    }
    free(tmp);
    return 1;
}
#endif
