// FolderSize.h -- a folder's size for Finder's list and Get Info (1.8.4.2 item 1, KT 8 Nov 2026), as a Mac's Finder shows it with View Options >
// Calculate all sizes: "--" until it is worked out, then the size; Get Info says "Calculating…" meanwhile. Plain C, so the Mac test
// (tools/test-foldersize.c) runs this very code on real folders; Finder.h (DMFinderSizes) schedules it.
// The walk (MSBDFolderSizeWalk) never follows a link (a link counts its own few bytes, as on a Mac, and a link to "/" is not a way round the
// caps), never leaves the folder's volume (the root's /dev, a drive mounted under LiveFiles, the jailbreak's preboot volume behind /var/jb: each is
// its own walk, never a part of another), counts a file with several hard links once, and gives up at a cap:
//  - kMSBDFolderSizeMaxEntries entries (files, folders, links): 100,000. A user's folders are far smaller (a Photos library of 20,000 pictures
//    is ~45,000 entries with its thumbnails); the trees over it are the system's own (/, /System, /usr, /private/var, /var/jb), whose size
//    no one asks Finder for. fts reads ~60,000 entries a second on an A12Z's flash (~25,000 on older iPads), so the cap is 2-4 s of one core.
//  - kMSBDFolderSizeMaxSeconds seconds: 4. The time cap is for slow places: a USB drive, a FAT stick, a folder of the UserFS or FSKit server,
//    where 100,000 entries may take a minute. Folders are worked out one at a time, so a slow one must not hold the others for long.
// A capped folder shows "Calculating…" (KT: the size is not known, and Finder doesn't pretend it is) and is not walked again until it changes.
#ifndef MSBD_FOLDER_SIZE_H
#define MSBD_FOLDER_SIZE_H
#include <fts.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>

#define kMSBDFolderSizeMaxEntries 100000UL
#define kMSBDFolderSizeMaxSeconds 4.0
#define kMSBDFolderSizeMaxAge 600.0   // (a size kept this long is checked by a new walk even if the folder's own date didn't change -- see MSBDFolderSizeFresh)

enum { MSBD_FS_NONE = 0, MSBD_FS_DONE = 1, MSBD_FS_CAPPED = 2, MSBD_FS_CANCELLED = 3, MSBD_FS_UNREADABLE = 4 };
typedef struct {
    unsigned long long bytes;   // (the files' own sizes, as a Mac's list shows them: not the blocks they take)
    unsigned long entries;      // (everything walked: files, folders, links)
    int state;                  // (MSBD_FS_*)
} MSBDFolderSizeResult;

// (hard links counted once: a small set of (device, inode) of files with more than one link -- most folders have none)
typedef struct { uint64_t *keys; size_t cap, n; } MSBDFSInodeSet;
static inline int MSBDFSInodeAdd(MSBDFSInodeSet *s, dev_t dev, ino_t ino) {   // 1: new, 0: seen before (or no memory: counted, as a Mac would)
    uint64_t k = ((uint64_t)(uint32_t)dev << 40) ^ (uint64_t)ino ^ 0x9E3779B97F4A7C15ULL;
    if (!k) k = 1;
    if ((s->n + 1) * 2 > s->cap) {
        size_t nc = s->cap ? s->cap * 2 : 256;
        uint64_t *nk = (uint64_t *)calloc(nc, sizeof *nk);
        if (!nk) return 1;
        for (size_t i = 0; i < s->cap; i++) if (s->keys[i]) { size_t j = (size_t)(s->keys[i] * 0x2545F4914F6CDD1DULL) & (nc - 1); while (nk[j]) j = (j + 1) & (nc - 1); nk[j] = s->keys[i]; }
        free(s->keys); s->keys = nk; s->cap = nc;
    }
    size_t j = (size_t)(k * 0x2545F4914F6CDD1DULL) & (s->cap - 1);
    while (s->keys[j]) { if (s->keys[j] == k) return 0; j = (j + 1) & (s->cap - 1); }
    s->keys[j] = k; s->n++;
    return 1;
}
static inline double MSBDFSNow(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec + (double)t.tv_nsec / 1e9; }

// The walk, on a queue of its own (never the main thread). `cancel` (may be NULL) is looked at for every entry: non-zero stops it at once.
// maxEntries / maxSeconds: the caps (0: the defaults above). The time is looked at every 64 entries.
static inline MSBDFolderSizeResult MSBDFolderSizeWalk(const char *path, unsigned long maxEntries, double maxSeconds, volatile int *cancel) {
    MSBDFolderSizeResult r = { 0, 0, MSBD_FS_UNREADABLE };
    if (!path || !*path) return r;
    if (!maxEntries) maxEntries = kMSBDFolderSizeMaxEntries;
    if (!(maxSeconds > 0)) maxSeconds = kMSBDFolderSizeMaxSeconds;
    struct stat st;
    if (lstat(path, &st) != 0 || !S_ISDIR(st.st_mode)) return r;   // (a link to a folder is not walked: it is an alias)
    char *const roots[2] = { (char *)path, NULL };
    FTS *fts = fts_open(roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL);
    if (!fts) return r;
    double start = MSBDFSNow();
    MSBDFSInodeSet links = { NULL, 0, 0 };
    r.state = MSBD_FS_DONE;
    FTSENT *e;
    while ((e = fts_read(fts))) {
        if (cancel && *cancel) { r.state = MSBD_FS_CANCELLED; break; }
        if (e->fts_level == 0 && (e->fts_info == FTS_DNR || e->fts_info == FTS_ERR || e->fts_info == FTS_NS)) { r.state = MSBD_FS_UNREADABLE; break; }
        if (e->fts_info == FTS_DP) continue;   // (a folder seen again on the way out)
        if (e->fts_level > 0 && e->fts_info != FTS_DNR) r.entries++;   // (a folder it can't read comes again as FTS_DNR: counted once)
        if (r.entries > maxEntries || (r.entries && (r.entries & 63) == 0 && MSBDFSNow() - start > maxSeconds)) { r.state = MSBD_FS_CAPPED; break; }
        switch (e->fts_info) {
            case FTS_F: case FTS_SL: case FTS_SLNONE: case FTS_DEFAULT:
                if (!e->fts_statp) break;
                if (S_ISREG(e->fts_statp->st_mode) && e->fts_statp->st_nlink > 1 && !MSBDFSInodeAdd(&links, e->fts_statp->st_dev, e->fts_statp->st_ino)) break;
                if (S_ISREG(e->fts_statp->st_mode) || S_ISLNK(e->fts_statp->st_mode)) r.bytes += (unsigned long long)e->fts_statp->st_size;
                break;
            case FTS_D:
                if (e->fts_level > 0 && e->fts_statp && e->fts_statp->st_dev != st.st_dev) fts_set(fts, e, FTS_SKIP);   // (FTS_XDEV, made sure of)
                break;
            default: break;   // (a folder Finder may not read: what it holds is not counted, as on a Mac)
        }
    }
    free(links.keys);
    fts_close(fts);
    return r;
}

// A kept size still holds when the folder's own date is the one it was worked out at (to the millisecond: NSDate and stat round differently)
// and it isn't older than maxAge. A folder's date changes when something is added, removed or renamed right in it; a change deeper down shows
// at the next look after maxAge (a Mac's Finder too shows a deep change late).
// The kept sizes are bounded by evicting, never by emptying (a window sorted by size reads them all: review 1.8.4.2 M1). Past the limit, how many of the
// removable ones (kept sizes of folders no window lists) go, oldest first, and the count at which to look again: with every kept size in use, not at
// each new one.
#define MSBD_FS_KEPT_LIMIT 4000
static inline long MSBDFolderSizeEvictCount(long count, long removable) { long q = count / 4; return removable < q ? removable : q; }
static inline long MSBDFolderSizeNextTrim(long count) { return count + 500 > MSBD_FS_KEPT_LIMIT ? count + 500 : MSBD_FS_KEPT_LIMIT; }
static inline int MSBDFolderSizeFresh(int have, double keptDate, double date, double keptAt, double now, double maxAge) {
    if (!have) return 0;
    if (keptDate - date > 0.001 || date - keptDate > 0.001) return 0;
    return now - keptAt >= 0 && now - keptAt < maxAge;
}

// Whether a row's size is worked out at all: a folder, not an alias to one, not one the iPad keeps closed, not one only in iCloud.
static inline int MSBDFolderSizeWanted(int dir, int alias, int locked, int cloud) { return dir && !alias && !locked && !cloud; }

// What the Size column (info 0) or Get Info (info 1) shows for a folder: its size, "--" or "Calculating…".
enum { MSBD_FS_SHOW_BYTES = 0, MSBD_FS_SHOW_DASH = 1, MSBD_FS_SHOW_CALCULATING = 2 };
static inline int MSBDFolderSizeShow(int wanted, int state, int info) {
    if (!wanted) return MSBD_FS_SHOW_DASH;
    switch (state) {
        case MSBD_FS_DONE: return MSBD_FS_SHOW_BYTES;
        case MSBD_FS_CAPPED: return MSBD_FS_SHOW_CALCULATING;
        case MSBD_FS_UNREADABLE: return MSBD_FS_SHOW_DASH;
        default: return info ? MSBD_FS_SHOW_CALCULATING : MSBD_FS_SHOW_DASH;   // (not worked out yet, or stopped: the list waits with "--")
    }
}
#endif
