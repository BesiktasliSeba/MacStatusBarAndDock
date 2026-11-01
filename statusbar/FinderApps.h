// FinderApps.h -- Finder's Applications place (the sidebar's row, /var/containers/Bundle/Application) shows each installed app as the app itself
// (1.7.6 item 2, KT). Each app is installed in a bundle container named by a UUID (<UUID>/Tips.app beside the installer's own files:
// iTunesMetadata.plist, BundleMetadata.plist, SC_Info). The row is that .app -- its path, its name --, so everything done with the row is done with
// the app, as a Mac's /Applications shows Clock.app: dragged onto the desktop, the Dock's Downloads stack or into a folder, copied and pasted,
// handed to another app, its Get Info. Until 1.7.6 the row only LOOKED like the app (its icon and name) while its path stayed the container: a
// drag to the desktop copied the UUID folder, a folder with the .app inside, which had to be opened to drag the .app out (KT, all four iPads).
// The copy is the user's own (an APFS clone of the bundle on the same volume); removing it never touches the installed app, which stays where
// it is (the Applications place is read only: an app is always copied out, never moved). Foundation and POSIX only: Finder.h runs it,
// tools/test-finderapps.m checks it on the Mac.
#pragma once
#import <Foundation/Foundation.h>
#include <sys/stat.h>

// The app in a bundle container: the full path of its .app -- a real folder (not a link, not a file) named "<something>.app", not a hidden
// one --, or nil when there is none (an empty or half-removed container). A container holds one; were there more, the first by name (the same
// one every time). Read without following links, so a row never leads out of the container.
static NSString *DMFinderBundleApp(NSString *container) {
    if (!container.length) return nil;
    NSArray<NSString *> *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:container error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *f in names) {
        if (f.length <= 4 || [f hasPrefix:@"."] || ![f.pathExtension isEqualToString:@"app"]) continue;
        NSString *p = [container stringByAppendingPathComponent:f];
        struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode)) return p;
    }
    return nil;
}
