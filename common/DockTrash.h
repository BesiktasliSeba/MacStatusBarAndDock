// DockTrash.h -- the Dock's Trash (1.7.0): the rules both sides share, Foundation only, so the Mac test (tools/test-docktrash.sh) runs the same
// code. The Dock draws the bin (dock/TrashIcon.m); Finder owns the Trash itself (statusbar/DockTrash.h, Finder.h): it counts what is in it, opens
// a window on it, empties it with its own question, and carries the drags that end on the bin.
#pragma once
#import <Foundation/Foundation.h>

// The Darwin names between the two libraries in SpringBoard (the Dock's and Mac Status Bar's).
#define kMSBDTrashStateName "com.besiktasliseba.macstatusbar.finder.trash"         // state: how many items Finder's Trash holds (0: empty)
#define kMSBDTrashOpenName  "com.besiktasliseba.macstatusbar.finder.trash.open"    // the bin tapped, or Open in its menu: a Finder window on the Trash
#define kMSBDTrashEmptyName "com.besiktasliseba.macstatusbar.finder.trash.empty"   // Empty Trash in its menu: Finder asks first, then erases

// One entry of a Trash folder counts as an item the Trash holds -- everything but a folder's own bookkeeping: "." and "..", a Mac's .DS_Store, and
// the "._" AppleDouble files a drive keeps beside its items (they go with their item). Hidden items count: Empty Trash erases them too.
static inline BOOL MSBDTrashEntryCounts(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || !name.length) return NO;
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."] || [name isEqualToString:@".DS_Store"]) return NO;
    return ![name hasPrefix:@"._"];
}
static inline NSUInteger MSBDTrashCountNames(NSArray *names) {
    NSUInteger n = 0;
    for (id x in names) if (MSBDTrashEntryCounts(x)) n++;
    return n;
}

// What a drop on the bin does with the items of a Finder drag (a Finder window's, the desktop's, the Downloads stack's).
typedef NS_ENUM(NSInteger, MSBDTrashDrop) {
    MSBDTrashDropNone = 0,   // nothing to do: no items, or each one is in the Trash already (the picture just goes back, as on a Mac)
    MSBDTrashDropRefuse,     // not allowed: an item Finder may not change (outside the user's own places), or drives and files together ("no" sign)
    MSBDTrashDropTrash,      // Move to Trash, Finder's operation (the policy's questions, Undo, Put Back); items already in the Trash are left as they are
    MSBDTrashDropEject,      // every item is a connected drive itself (its volume's folder): the drives are ejected -- only where this iPadOS can eject
};
typedef struct {
    BOOL driveRoot;   // the item is a connected drive's own folder (its mount point)
    BOOL inTrash;     // already in Finder's Trash (its own, or a drive's .Trashes/<uid>)
    BOOL canChange;   // Finder's policy lets it move this item (DMFinderCanChange)
} MSBDTrashItem;
// canEject: this iPadOS has the drive eject (StorageKit, the Files app's own eject: 16 on; 15 has neither StorageKit nor storagekitd). Without it a
// drive is refused like an item Finder may not move: a drive never goes to the Trash, and nothing eject-related is offered (1.7.0, KT).
static inline MSBDTrashDrop MSBDTrashDropFor(const MSBDTrashItem *items, NSUInteger n, BOOL canEject) {
    if (!items || !n) return MSBDTrashDropNone;
    NSUInteger drives = 0, trashed = 0;
    for (NSUInteger i = 0; i < n; i++) { if (items[i].driveRoot) drives++; else if (items[i].inTrash) trashed++; }
    if (drives == n) return canEject ? MSBDTrashDropEject : MSBDTrashDropRefuse;
    if (drives) return MSBDTrashDropRefuse;
    if (trashed == n) return MSBDTrashDropNone;
    for (NSUInteger i = 0; i < n; i++) if (!items[i].inTrash && !items[i].canChange) return MSBDTrashDropRefuse;
    return MSBDTrashDropTrash;
}
// The bin turns into the Eject sign for the whole of a drag of drives (from its start, as on a Mac), not only while the drag is over it -- never
// where the drives can't be ejected.
static inline BOOL MSBDTrashDragEjects(const MSBDTrashItem *items, NSUInteger n, BOOL canEject) { return MSBDTrashDropFor(items, n, canEject) == MSBDTrashDropEject; }

// An app dragged off the Dock (SpringBoard's own icon drag) and dropped on the bin leaves the Dock; the app stays installed and goes to the Home
// Screen, as Remove from Dock in its menu does. Only one app kept in the Dock itself: not a recent or suggested app, not a folder, not a widget.
typedef struct {
    NSUInteger count;   // icons in the drag
    BOOL isApp;         // the icon is an app's (it has a bundle identifier)
    BOOL isFolder;      // a folder icon
    BOOL fromDock;      // the drag started on an icon of the Dock's own list (its location is the Dock's, not the recents' / suggestions')
    BOOL keptInDock;    // the icon is in the Dock list of the icon model
} MSBDTrashIconDrag;
static inline BOOL MSBDTrashRemovesFromDock(MSBDTrashIconDrag d) {
    return d.count == 1 && d.isApp && !d.isFolder && d.fromDock && d.keptInDock;
}
// The icon's location name (SBIconLocation...) is the Dock's own list: SBIconLocationDock / SBIconLocationFloatingDock, not the floating Dock's
// recents (SBIconLocationFloatingDockSuggestions) and not the App Library or a folder.
static inline BOOL MSBDTrashLocationIsDock(NSString *location) {
    if (![location isKindOfClass:[NSString class]]) return NO;
    return [location containsString:@"Dock"] && ![location containsString:@"Suggestions"] && ![location containsString:@"Recent"];
}

// The Dock's end, after the second divider: the Downloads stack, then the Trash -- one icon and one spacing apart, from where Downloads has always
// gone (the App Library icon's old place, the end of the Dock with Launchpad at its start, or a place of its own when the Dock shows no App Library
// icon). In the Dock's unscaled layout units: first = the first item's left edge, side = an icon, ownFirst >= 0 = the platter's growth for a
// first item with a place of its own (Dock.x works it out), else one icon and one spacing. With the Trash off it is exactly the Downloads slot of
// before. x is -1 for an item that is off; growth is what the platter grows by for the items (the divider's own gap not included).
typedef struct { double downloadsX, trashX, growth; int count; } MSBDDockEnd;
static inline MSBDDockEnd MSBDDockEndLayout(double first, double side, double spacing, double ownFirst, BOOL downloads, BOOL trash) {
    MSBDDockEnd e = { -1.0, -1.0, 0.0, 0 };
    double x = first;
    if (downloads) { e.downloadsX = x; e.growth += (e.count == 0 && ownFirst >= 0.0) ? ownFirst : side + spacing; e.count++; x += side + spacing; }
    if (trash) { e.trashX = x; e.growth += (e.count == 0 && ownFirst >= 0.0) ? ownFirst : side + spacing; e.count++; x += side + spacing; }
    return e;
}

// The words VoiceOver reads for the bin.
static inline NSString *MSBDTrashAXLabel(BOOL eject) { return eject ? @"Eject" : @"Trash"; }
static inline NSString *MSBDTrashAXValue(NSUInteger count, BOOL eject) {
    if (eject) return nil;
    return count ? @"Full" : @"Empty";
}

// Finder's eject helper run for its answer (statusbar/DockTrash.h, ejecthelper/: msbdeject prints one line), here so the Mac test runs this very
// spawn. The helper gets only the descriptors it uses -- stdin and stderr on /dev/null, stdout a pipe read to its end (8 KB kept at most) -- and
// is then waited for. Without POSIX_SPAWN_CLOEXEC_DEFAULT it got every descriptor SpringBoard had open (files, sockets, other pipes: a second
// eject's among them, whose answer then waited for this helper to end too). Spawned from a queue's thread, which blocks signals: none blocked
// in the helper. Any thread; blocks until the helper's output ends. Returns posix_spawn's result (0: it ran), -1 without a pipe; *status: the
// helper's wait status, -1 when there is none (SpringBoard may reap its children itself).
#include <spawn.h>
#include <signal.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/wait.h>
extern char **environ;
static inline int MSBDTrashRunHelper(const char *path, char *const argv[], NSData **output, int *status) {
    if (output) *output = nil;
    if (status) *status = -1;
    int out[2] = { -1, -1 };
    if (pipe(out) != 0) return -1;
    posix_spawnattr_t at; posix_spawnattr_init(&at);
    posix_spawnattr_setflags(&at, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK);
    sigset_t none; sigemptyset(&none); posix_spawnattr_setsigmask(&at, &none);
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&fa, out[1], 1);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    pid_t pid = 0;
    int rc = posix_spawn(&pid, path, &fa, &at, argv, environ);
    posix_spawn_file_actions_destroy(&fa); posix_spawnattr_destroy(&at);
    close(out[1]);
    if (rc == 0) {
        NSMutableData *buf = [NSMutableData data]; char chunk[512]; ssize_t got;
        while (((got = read(out[0], chunk, sizeof chunk)) > 0 || (got < 0 && errno == EINTR)) && buf.length < 8192) if (got > 0) [buf appendBytes:chunk length:(NSUInteger)got];
        close(out[0]); out[0] = -1;   // (before the wait: a helper with more to say than is kept ends, instead of waiting on a full pipe)
        int st = 0; pid_t w;
        do { w = waitpid(pid, &st, 0); } while (w < 0 && errno == EINTR);
        if (status && w == pid) *status = st;
        if (output) *output = buf;
    }
    if (out[0] >= 0) close(out[0]);
    return rc;
}
