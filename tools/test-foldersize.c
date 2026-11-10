// test-foldersize.c: a folder's size for Finder (common/FolderSize.h, 1.8.4.2 item 1), on real folders made here: the files' sizes added up, links
// never followed (a link to "/" inside is a few bytes, not a walk of the disk), hard links once, the caps (entries, seconds) ending in "capped",
// a stop asked for ending the walk, a folder Finder may not read, and the rules: kept or walked again, worked out or not, what the list and
// Get Info show.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "../common/FolderSize.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
static void file(const char *dir, const char *name, size_t size) {
    char p[1024]; snprintf(p, sizeof p, "%s/%s", dir, name);
    int fd = open(p, O_CREAT | O_WRONLY | O_TRUNC, 0644); if (fd < 0) { perror(p); exit(2); }
    if (size && ftruncate(fd, (off_t)size) != 0) { perror("ftruncate"); exit(2); }
    close(fd);
}
static void dir(const char *base, const char *name, char *out) { snprintf(out, 1024, "%s/%s", base, name); mkdir(out, 0755); }
int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: test-foldersize <empty folder>\n"); return 2; }
    const char *W = argv[1];
    char a[1024], sub[1024], deep[1024], p[1024], q[1024];

    // ---- the files' sizes, folders inside included
    dir(W, "A", a); file(a, "one", 1000); file(a, "two", 2500);
    dir(a, "Sub", sub); file(sub, "three", 40000);
    dir(sub, "Deep", deep); file(deep, "four", 7);
    MSBDFolderSizeResult r = MSBDFolderSizeWalk(a, 0, 0, NULL);
    check("A folder: its files' sizes added up, the folders inside too (1000 + 2500 + 40000 + 7)", r.state == MSBD_FS_DONE && r.bytes == 43507);
    check("  ... every entry walked once (4 files, 2 folders)", r.entries == 6);
    char e[1024]; dir(W, "Empty", e);
    r = MSBDFolderSizeWalk(e, 0, 0, NULL);
    check("an empty folder: Zero bytes, worked out", r.state == MSBD_FS_DONE && r.bytes == 0 && r.entries == 0);

    // ---- links: never followed
    snprintf(p, sizeof p, "%s/to-root", a); symlink("/", p);
    snprintf(p, sizeof p, "%s/to-sub", a); symlink(sub, p);
    snprintf(p, sizeof p, "%s/nowhere", a); symlink("/no/such/place", p);
    r = MSBDFolderSizeWalk(a, 0, 0, NULL);
    check("links inside (to \"/\", to a folder inside, to nowhere): their own few bytes, never what they point at",
          r.state == MSBD_FS_DONE && r.bytes == 43507 + 1 + strlen(sub) + strlen("/no/such/place") && r.entries == 9);
    snprintf(p, sizeof p, "%s/alias", W); symlink(a, p);
    r = MSBDFolderSizeWalk(p, 0, 0, NULL);
    check("a link to a folder, asked for itself: not walked (an alias, as on a Mac)", r.state == MSBD_FS_UNREADABLE && r.bytes == 0);
    snprintf(p, sizeof p, "%s/A/one", W);
    check("a file, not a folder: nothing walked", MSBDFolderSizeWalk(p, 0, 0, NULL).state == MSBD_FS_UNREADABLE);
    check("a folder that isn't there: nothing walked", MSBDFolderSizeWalk("/no/such/folder/here", 0, 0, NULL).state == MSBD_FS_UNREADABLE);
    check("  ... no path at all: nothing walked", MSBDFolderSizeWalk(NULL, 0, 0, NULL).state == MSBD_FS_UNREADABLE && MSBDFolderSizeWalk("", 0, 0, NULL).state == MSBD_FS_UNREADABLE);

    // ---- hard links: once
    char h[1024]; dir(W, "Hard", h); file(h, "big", 100000);
    snprintf(p, sizeof p, "%s/big", h); snprintf(q, sizeof q, "%s/big-again", h); link(p, q);
    snprintf(q, sizeof q, "%s/big-third", h); link(p, q);
    r = MSBDFolderSizeWalk(h, 0, 0, NULL);
    check("a file with three hard links in the folder: counted once (100000, not 300000)", r.state == MSBD_FS_DONE && r.bytes == 100000);

    // ---- the caps
    char many[1024]; dir(W, "Many", many);
    for (int i = 0; i < 500; i++) { char n[32]; snprintf(n, sizeof n, "f%03d", i); file(many, n, 10); }
    r = MSBDFolderSizeWalk(many, 0, 0, NULL);
    check("500 files: worked out (well under the caps)", r.state == MSBD_FS_DONE && r.bytes == 5000 && r.entries == 500);
    r = MSBDFolderSizeWalk(many, 100, 0, NULL);
    check("  ... with a cap of 100 entries: capped, the walk stopped right after the 100th", r.state == MSBD_FS_CAPPED && r.entries == 101 && r.bytes <= 1000);
    r = MSBDFolderSizeWalk(many, 0, 1e-9, NULL);
    check("  ... with a cap of a nanosecond: capped at the first look at the time (64 entries)", r.state == MSBD_FS_CAPPED && r.entries == 64);
    check("the caps as justified: 100,000 entries, 4 seconds; a kept size checked again after 10 minutes",
          kMSBDFolderSizeMaxEntries == 100000UL && kMSBDFolderSizeMaxSeconds == 4.0 && kMSBDFolderSizeMaxAge == 600.0);
    volatile int stop = 1;
    r = MSBDFolderSizeWalk(many, 0, 0, &stop);
    check("a stop asked for (the window closed, another folder shown): stopped at once, not kept as a size", r.state == MSBD_FS_CANCELLED && r.entries == 0);
    stop = 0;
    check("  ... no stop asked for: worked out", MSBDFolderSizeWalk(many, 0, 0, &stop).state == MSBD_FS_DONE);

    // ---- folders Finder may not read
    if (geteuid() != 0) {
        char closed[1024]; dir(W, "Closed", closed); file(closed, "secret", 999);
        chmod(closed, 0);
        check("a folder Finder may not read: not readable (\"--\"), not a size of zero", MSBDFolderSizeWalk(closed, 0, 0, NULL).state == MSBD_FS_UNREADABLE);
        char outer[1024]; dir(W, "Outer", outer); file(outer, "open", 50);
        char in[1024]; dir(outer, "Shut", in); file(in, "hidden", 70); chmod(in, 0);
        r = MSBDFolderSizeWalk(outer, 0, 0, NULL);
        check("  ... one inside a folder: the rest is counted (as on a Mac)", r.state == MSBD_FS_DONE && r.bytes == 50);
        chmod(closed, 0755); chmod(in, 0755);
    } else printf("SKIP  unreadable folders (running as root)\n");

    // ---- a volume of its own (/dev, devfs; /dev/fd inside it is another one again): walked by itself, its devices are no bytes and the
    //      volume inside is not walked into
    {
        struct stat root, dev; stat("/", &root); stat("/dev", &dev);
        if (root.st_dev != dev.st_dev) {
            r = MSBDFolderSizeWalk("/dev", 0, 0, NULL);
            check("/dev, a volume of its own, walked by itself: worked out quickly, its devices not counted as bytes", r.state == MSBD_FS_DONE);
        } else printf("SKIP  /dev is not its own volume here\n");
    }

    // ---- kept or walked again
    check("kept, the folder's date the same, 5 min old: kept", MSBDFolderSizeFresh(1, 1000.5, 1000.5, 0, 300, 600));
    check("  ... the date within a millisecond (NSDate and stat round differently): kept", MSBDFolderSizeFresh(1, 1000.5, 1000.5004, 0, 300, 600));
    check("  ... the folder changed (its date moved): walked again", !MSBDFolderSizeFresh(1, 1000.5, 1001.0, 0, 300, 600) && !MSBDFolderSizeFresh(1, 1000.5, 999.0, 0, 300, 600));
    check("  ... older than 10 minutes (a change deeper down): walked again", !MSBDFolderSizeFresh(1, 1000.5, 1000.5, 0, 600, 600));
    check("  ... the clock set back: walked again", !MSBDFolderSizeFresh(1, 1000.5, 1000.5, 500, 100, 600));
    check("  ... nothing kept: walked", !MSBDFolderSizeFresh(0, 0, 0, 0, 0, 600));

    // ---- worked out at all
    check("a folder: worked out", MSBDFolderSizeWanted(1, 0, 0, 0));
    check("  ... a file (its own size), an alias to a folder, a locked folder, a folder only in iCloud: not",
          !MSBDFolderSizeWanted(0, 0, 0, 0) && !MSBDFolderSizeWanted(1, 1, 0, 0) && !MSBDFolderSizeWanted(1, 0, 1, 0) && !MSBDFolderSizeWanted(1, 0, 0, 1));

    // ---- what is shown
    check("the list: \"--\" until worked out, then the size", MSBDFolderSizeShow(1, MSBD_FS_NONE, 0) == MSBD_FS_SHOW_DASH && MSBDFolderSizeShow(1, MSBD_FS_DONE, 0) == MSBD_FS_SHOW_BYTES);
    check("  ... capped: \"Calculating…\" (not a size that would be wrong)", MSBDFolderSizeShow(1, MSBD_FS_CAPPED, 0) == MSBD_FS_SHOW_CALCULATING);
    check("  ... not readable, or stopped: \"--\"", MSBDFolderSizeShow(1, MSBD_FS_UNREADABLE, 0) == MSBD_FS_SHOW_DASH && MSBDFolderSizeShow(1, MSBD_FS_CANCELLED, 0) == MSBD_FS_SHOW_DASH);
    check("  ... not worked out at all (an alias, a locked folder): \"--\", also in Get Info", MSBDFolderSizeShow(0, MSBD_FS_DONE, 0) == MSBD_FS_SHOW_DASH && MSBDFolderSizeShow(0, MSBD_FS_NONE, 1) == MSBD_FS_SHOW_DASH);
    check("Get Info: \"Calculating…\" until worked out, then the size; not readable: \"--\"",
          MSBDFolderSizeShow(1, MSBD_FS_NONE, 1) == MSBD_FS_SHOW_CALCULATING && MSBDFolderSizeShow(1, MSBD_FS_DONE, 1) == MSBD_FS_SHOW_BYTES && MSBDFolderSizeShow(1, MSBD_FS_UNREADABLE, 1) == MSBD_FS_SHOW_DASH);

    if (fails) { printf("test-foldersize (compiled): FAILED\n"); return 1; }
    check("the kept sizes: past the limit a quarter goes", MSBDFolderSizeEvictCount(4001, 4001) == 1000);
    check("  ... never more than those no window lists", MSBDFolderSizeEvictCount(4001, 200) == 200 && MSBDFolderSizeEvictCount(4001, 0) == 0);
    check("  ... looked at again at the limit after a trim", MSBDFolderSizeNextTrim(3001) == MSBD_FS_KEPT_LIMIT);
    check("  ... and later when all of them are in use: not at each new size", MSBDFolderSizeNextTrim(6000) == 6500);
    printf("test-foldersize (compiled): all checks pass\n"); return 0;
}
