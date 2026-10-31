// Mac test of the Dock's Trash rules (common/DockTrash.h, 1.7.0): what counts as an item in a Trash folder (the bin's empty / full state), what a
// drop on the bin does (Move to Trash, Eject, refused, nothing), which icon drags leave the Dock, where Downloads and the Trash go at the Dock's end
// (the Downloads slot of before when the Trash is off), the words VoiceOver reads, and the eject helper's spawn (only the descriptors it uses).
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include "../common/DockTrash.h"
#include "../common/DriveEject.h"   // (the eject helper's spawn, MSBDRunHelperTimed: the root helper runs it since 1.7.3)
extern char **environ;

static int fails = 0, checks = 0;
static void ok(NSString *what, BOOL cond) { checks++; if (!cond) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static void eqd(NSString *what, double got, double want) { checks++; if (fabs(got - want) > 1e-9) { fails++; printf("FAIL %s: got %.4f, want %.4f\n", what.UTF8String, got, want); } }
static void eqs(NSString *what, NSString *got, NSString *want) { checks++; if (!(got == want || [got isEqualToString:want])) { fails++; printf("FAIL %s: got %s, want %s\n", what.UTF8String, got.UTF8String ?: "(nil)", want.UTF8String ?: "(nil)"); } }
static MSBDTrashDrop dropOn(NSArray<NSArray<NSNumber *> *> *spec, BOOL canEject) {   // each item: @[driveRoot, inTrash, canChange]
    MSBDTrashItem items[16]; NSUInteger n = 0;
    for (NSArray<NSNumber *> *x in spec) { items[n].driveRoot = x[0].boolValue; items[n].inTrash = x[1].boolValue; items[n].canChange = x[2].boolValue; n++; }
    return MSBDTrashDropFor(n ? items : NULL, n, canEject);
}
static MSBDTrashDrop drop(NSArray<NSArray<NSNumber *> *> *spec) { return dropOn(spec, YES); }   // (16 on: StorageKit there)

// This test is also the eject helper's stand-in (MSBDRunHelperTimed, common/DriveEject.h): run as "--child", it prints the descriptors above 2 it was started with,
// whether its stdin and its stderr are /dev/null (looked at, never read: the control's stdin is the test's own), writes a line to stderr (never part
// of the answer) and exits 7.
static BOOL IsDevNull(int fd) {
    struct stat a, b;
    return fstat(fd, &a) == 0 && stat("/dev/null", &b) == 0 && S_ISCHR(a.st_mode) && a.st_rdev == b.st_rdev;
}
static int Child(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"fds:"];
    for (int fd = 3; fd < 1024; fd++) if (fcntl(fd, F_GETFD) != -1) [s appendFormat:@" %d", fd];
    fprintf(stderr, "stderr text\n");
    printf("%s\nstdin %s\nstderr %s\n", s.UTF8String, IsDevNull(0) ? "null" : "other", IsDevNull(2) ? "null" : "other");
    return 7;
}
// The spawn as it was before the review of 1.7.0 (no attributes, stdout only): the control that shows the check sees inherited descriptors.
static NSString *OldSpawn(const char *path, char *const argv[]) {
    int out[2]; if (pipe(out) != 0) return nil;
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, out[1], 1); posix_spawn_file_actions_addclose(&fa, out[0]);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);   // (only to keep its stderr line out of this test's output)
    pid_t pid = 0; int rc = posix_spawn(&pid, path, &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa); close(out[1]);
    NSMutableData *buf = [NSMutableData data]; char chunk[512]; ssize_t got;
    if (rc == 0) { while ((got = read(out[0], chunk, sizeof chunk)) > 0) [buf appendBytes:chunk length:(NSUInteger)got]; int st; waitpid(pid, &st, 0); }
    close(out[0]);
    return [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
}
static NSSet<NSString *> *FdsIn(NSString *answer) {   // (the "fds:" line's numbers)
    for (NSString *l in [answer componentsSeparatedByString:@"\n"]) if ([l hasPrefix:@"fds:"]) {
        NSMutableSet *set = [NSMutableSet set];
        for (NSString *x in [[l substringFromIndex:4] componentsSeparatedByString:@" "]) if (x.length) [set addObject:x];
        return set;
    }
    return nil;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--child")) return Child();
    @autoreleasepool {
        // ---- the bin's state: what a Trash folder holds ----
        ok(@"a file counts", MSBDTrashEntryCounts(@"report.pdf"));
        ok(@"a folder counts", MSBDTrashEntryCounts(@"untitled folder"));
        ok(@"a hidden item counts (Empty Trash erases it)", MSBDTrashEntryCounts(@".hidden-note"));
        ok(@"a name with spaces and accents counts", MSBDTrashEntryCounts(@"Café notes 2.txt"));
        ok(@". does not count", !MSBDTrashEntryCounts(@"."));
        ok(@".. does not count", !MSBDTrashEntryCounts(@".."));
        ok(@".DS_Store does not count", !MSBDTrashEntryCounts(@".DS_Store"));
        ok(@"an AppleDouble file does not count", !MSBDTrashEntryCounts(@"._report.pdf"));
        ok(@"an empty name does not count", !MSBDTrashEntryCounts(@""));
        ok(@"nil does not count", !MSBDTrashEntryCounts(nil));
        ok(@"a number does not count", !MSBDTrashEntryCounts((NSString *)(id)@3));
        ok(@"an empty Trash is empty", MSBDTrashCountNames(@[]) == 0);
        ok(@"nil list is empty", MSBDTrashCountNames(nil) == 0);
        ok(@"only bookkeeping: empty", MSBDTrashCountNames(@[@".DS_Store", @"._a", @"._b"]) == 0);
        ok(@"a drive's Trash: items and their ._ files", MSBDTrashCountNames(@[@"a.jpg", @"._a.jpg", @"b", @"._b", @".DS_Store"]) == 2);
        ok(@"three items", MSBDTrashCountNames(@[@"x", @"y", @".z"]) == 3);

        // ---- a drop on the bin ----
        ok(@"no items: nothing", drop(@[]) == MSBDTrashDropNone);
        ok(@"one file of the user's: Move to Trash", drop(@[@[@0, @0, @1]]) == MSBDTrashDropTrash);
        ok(@"several files of the user's: Move to Trash", drop(@[@[@0, @0, @1], @[@0, @0, @1], @[@0, @0, @1]]) == MSBDTrashDropTrash);
        ok(@"a file outside the user's places: refused", drop(@[@[@0, @0, @0]]) == MSBDTrashDropRefuse);
        ok(@"one of several outside the user's places: refused", drop(@[@[@0, @0, @1], @[@0, @0, @0]]) == MSBDTrashDropRefuse);
        ok(@"items already in the Trash: nothing to do", drop(@[@[@0, @1, @1], @[@0, @1, @1]]) == MSBDTrashDropNone);
        ok(@"an item in the Trash that can't change: still nothing", drop(@[@[@0, @1, @0]]) == MSBDTrashDropNone);
        ok(@"some in the Trash, some not: the others go to the Trash", drop(@[@[@0, @1, @1], @[@0, @0, @1]]) == MSBDTrashDropTrash);
        ok(@"some in the Trash and one that can't change: refused", drop(@[@[@0, @1, @1], @[@0, @0, @0]]) == MSBDTrashDropRefuse);
        ok(@"one drive: Eject", drop(@[@[@1, @0, @0]]) == MSBDTrashDropEject);
        ok(@"two drives: Eject", drop(@[@[@1, @0, @0], @[@1, @0, @0]]) == MSBDTrashDropEject);
        ok(@"a drive and a file: refused", drop(@[@[@1, @0, @0], @[@0, @0, @1]]) == MSBDTrashDropRefuse);
        ok(@"a drive and an item in the Trash: refused", drop(@[@[@1, @0, @0], @[@0, @1, @1]]) == MSBDTrashDropRefuse);
        { MSBDTrashItem d1 = { YES, NO, NO }, f1 = { NO, NO, YES };
          MSBDTrashItem both[2] = { d1, f1 };
          ok(@"a drag of a drive shows Eject", MSBDTrashDragEjects(&d1, 1, YES));
          ok(@"a drag of a file does not", !MSBDTrashDragEjects(&f1, 1, YES));
          ok(@"a drag of a drive and a file does not", !MSBDTrashDragEjects(both, 2, YES));
          ok(@"nothing dragged does not", !MSBDTrashDragEjects(NULL, 0, YES));
          // (1.7.0) no eject on this iPadOS (15: no StorageKit): never the Eject sign, a drive dropped on the bin is refused, the rest as before
          ok(@"no eject here: a drag of a drive does not show Eject", !MSBDTrashDragEjects(&d1, 1, NO));
          ok(@"no eject here: a drag of a file does not either", !MSBDTrashDragEjects(&f1, 1, NO)); }
        ok(@"no eject here: one drive refused", dropOn(@[@[@1, @0, @0]], NO) == MSBDTrashDropRefuse);
        ok(@"no eject here: two drives refused", dropOn(@[@[@1, @0, @0], @[@1, @0, @0]], NO) == MSBDTrashDropRefuse);
        ok(@"no eject here: a drive and a file refused", dropOn(@[@[@1, @0, @0], @[@0, @0, @1]], NO) == MSBDTrashDropRefuse);
        ok(@"no eject here: files go to the Trash as before", dropOn(@[@[@0, @0, @1], @[@0, @0, @1]], NO) == MSBDTrashDropTrash);
        ok(@"no eject here: items in the Trash: nothing", dropOn(@[@[@0, @1, @1]], NO) == MSBDTrashDropNone);
        ok(@"no eject here: a file outside the user's places refused", dropOn(@[@[@0, @0, @0]], NO) == MSBDTrashDropRefuse);
        ok(@"no eject here: nothing dragged: nothing", dropOn(@[], NO) == MSBDTrashDropNone);

        // ---- SpringBoard's own icon drag: leaves the Dock ----
        MSBDTrashIconDrag app = { 1, YES, NO, YES, YES };
        ok(@"an app kept in the Dock leaves it", MSBDTrashRemovesFromDock(app));
        MSBDTrashIconDrag x = app; x.count = 2; ok(@"two icons at once: no", !MSBDTrashRemovesFromDock(x));
        x = app; x.count = 0; ok(@"no icon: no", !MSBDTrashRemovesFromDock(x));
        x = app; x.isApp = NO; ok(@"not an app (a widget, a web clip without a bundle): no", !MSBDTrashRemovesFromDock(x));
        x = app; x.isFolder = YES; ok(@"a folder: no", !MSBDTrashRemovesFromDock(x));
        x = app; x.fromDock = NO; ok(@"from the Home Screen or the recents: no", !MSBDTrashRemovesFromDock(x));
        x = app; x.keptInDock = NO; ok(@"no longer in the Dock list: no", !MSBDTrashRemovesFromDock(x));
        ok(@"SBIconLocationDock is the Dock", MSBDTrashLocationIsDock(@"SBIconLocationDock"));
        ok(@"SBIconLocationFloatingDock is the Dock", MSBDTrashLocationIsDock(@"SBIconLocationFloatingDock"));
        ok(@"the floating Dock's suggestions are not", !MSBDTrashLocationIsDock(@"SBIconLocationFloatingDockSuggestions"));
        ok(@"a recents location is not", !MSBDTrashLocationIsDock(@"SBIconLocationDockRecents"));
        ok(@"the Home Screen is not", !MSBDTrashLocationIsDock(@"SBIconLocationRoot"));
        ok(@"the App Library is not", !MSBDTrashLocationIsDock(@"SBIconLocationAppLibrary"));
        ok(@"no location is not", !MSBDTrashLocationIsDock(nil));

        // ---- the Dock's end: Downloads, then the Trash ----
        // (iPad-like numbers: an icon of 64, a spacing of 12, the first end slot at 700)
        MSBDDockEnd e = MSBDDockEndLayout(700, 64, 12, -1, YES, NO);
        eqd(@"Downloads alone: at the first slot (as before)", e.downloadsX, 700); eqd(@"Downloads alone: one icon + one spacing (as before)", e.growth, 76);
        ok(@"Downloads alone: no Trash", e.trashX < 0 && e.count == 1);
        e = MSBDDockEndLayout(700, 64, 12, 70, YES, NO);
        eqd(@"Downloads in a place of its own: its own growth (as before)", e.growth, 70);
        e = MSBDDockEndLayout(700, 64, 12, -1, YES, YES);
        eqd(@"both: Downloads first", e.downloadsX, 700); eqd(@"both: the Trash one icon + one spacing after it", e.trashX, 776);
        eqd(@"both: two icons + two spacings", e.growth, 152); ok(@"both: two items", e.count == 2);
        e = MSBDDockEndLayout(700, 64, 12, 70, YES, YES);
        eqd(@"both, a place of its own: the first item's own growth + one more icon and spacing", e.growth, 146);
        eqd(@"both, a place of its own: the Trash after Downloads", e.trashX, 776);
        e = MSBDDockEndLayout(700, 64, 12, -1, NO, YES);
        eqd(@"the Trash alone: Downloads' slot", e.trashX, 700); eqd(@"the Trash alone: one icon + one spacing", e.growth, 76);
        ok(@"the Trash alone: no Downloads", e.downloadsX < 0 && e.count == 1);
        e = MSBDDockEndLayout(700, 64, 12, 70, NO, YES);
        eqd(@"the Trash alone, a place of its own: that growth", e.growth, 70);
        e = MSBDDockEndLayout(700, 64, 12, -1, NO, NO);
        ok(@"neither: nothing", e.count == 0 && e.growth == 0 && e.downloadsX < 0 && e.trashX < 0);

        // ---- VoiceOver ----
        eqs(@"label", MSBDTrashAXLabel(NO), @"Trash"); eqs(@"label while drives are dragged", MSBDTrashAXLabel(YES), @"Eject");
        eqs(@"value, empty", MSBDTrashAXValue(0, NO), @"Empty"); eqs(@"value, full", MSBDTrashAXValue(5, NO), @"Full");
        eqs(@"value while Eject", MSBDTrashAXValue(5, YES), nil);
        // ---- the names between the two libraries ----
        ok(@"state name", !strcmp(kMSBDTrashStateName, "com.besiktasliseba.macstatusbar.finder.trash"));
        ok(@"open / empty names are distinct", strcmp(kMSBDTrashOpenName, kMSBDTrashEmptyName) != 0 && strcmp(kMSBDTrashOpenName, kMSBDTrashStateName) != 0);

        // ---- the eject helper's spawn: only the descriptors it uses (review of 1.7.0; the root helper spawns it since 1.7.3) ----
        // The spawner's own open descriptors, stood in for by a file and a pipe of this test (no close-on-exec), at numbers a starting process
        // never takes for itself; the pipe's write end is "a second eject's", whose answer must not wait for this helper
        int f = open("/dev/null", O_RDONLY), q[2] = { -1, -1 };
        ok(@"spawn test: its descriptors made", f >= 0 && pipe(q) == 0 && dup2(f, 200) == 200 && dup2(q[0], 201) == 201 && dup2(q[1], 202) == 202);
        char self[PATH_MAX]; if (!realpath(argv[0], self)) strlcpy(self, argv[0], sizeof self);
        char *cargv[] = { self, (char *)"--child", NULL };
        NSString *old = OldSpawn(self, cargv);
        NSSet *oldFds = FdsIn(old);
        ok(@"control: spawned as before the review, the helper had its spawner's descriptors (the file, a second eject's pipe)", [oldFds containsObject:@"200"] && [oldFds containsObject:@"202"]);
        NSData *outData = nil; int st = -1;
        BOOL late = YES;
        int rc = MSBDRunHelperTimed(self, cargv, 30.0, &outData, &st, &late);
        NSString *answer = [[NSString alloc] initWithData:outData ?: [NSData data] encoding:NSUTF8StringEncoding];
        NSSet *fds = FdsIn(answer);
        ok(@"the helper ran", rc == 0 && fds != nil);
        ok([NSString stringWithFormat:@"the helper had no descriptor of its spawner's, none at all above 2 (it had: %@)", [fds.allObjects componentsJoinedByString:@" "]], fds && fds.count == 0);
        ok(@"its stdin and its stderr are /dev/null", [answer containsString:@"stdin null"] && [answer containsString:@"stderr null"]);
        ok(@"what it writes to stderr is not part of the answer", ![answer containsString:@"stderr text"]);
        ok(@"its exit status comes back, in time", WIFEXITED(st) && WEXITSTATUS(st) == 7 && !late);
        close(202); close(q[1]);   // (this test's own write ends gone: a reader sees the end at once, nothing else holds the pipe)
        fcntl(201, F_SETFL, O_NONBLOCK);   // (never a hang: a write end still held somewhere reads as "would block", not as the end)
        char c; ok(@"a second eject's pipe ends as soon as its own side closes (no helper holds it)", read(201, &c, 1) == 0);
        close(f); close(q[0]); close(200); close(201);
        rc = MSBDRunHelperTimed("/nonexistent/msbdeject", cargv, 30.0, &outData, &st, NULL);
        ok(@"a helper that is not there: posix_spawn's error, no answer, no status", rc != 0 && outData == nil && st == -1);
    }
    printf("%s: %d checks, %d failed\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
}
