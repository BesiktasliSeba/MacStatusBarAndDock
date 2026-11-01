// Mac test of statusbar/FinderApps.h (the code Finder.h runs, 1.7.6 item 2): an Applications row is the app's .app inside its bundle container --
// built here as real folders the way installd lays them out (<UUID>/Tips.app beside iTunesMetadata.plist, BundleMetadata.plist, SC_Info) --, never
// a link, a file or a hidden entry, nothing for an empty container. Then what a drop does with that row (Finder.h -dm_run: copy): the copy's name
// is the .app's, so the desktop gets "Tips.app", an app item, not the UUID folder. Run by test-finderapps.sh.
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>
#include "../statusbar/FinderApps.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)
static NSFileManager *FM;
static NSString *Root;
static NSString *Container(NSString *uuid, NSArray<NSString *> *dirs, NSArray<NSString *> *files) {
    NSString *c = [Root stringByAppendingPathComponent:uuid];
    [FM createDirectoryAtPath:c withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *d in dirs) [FM createDirectoryAtPath:[c stringByAppendingPathComponent:d] withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *f in files) [FM createFileAtPath:[c stringByAppendingPathComponent:f] contents:[@"x" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
    return c;
}
static BOOL Is(NSString *got, NSString *container, NSString *app) { return app ? [got isEqualToString:[container stringByAppendingPathComponent:app]] : got == nil; }

int main(void) {
    @autoreleasepool {
        FM = [NSFileManager defaultManager];
        char tmpl[] = "/tmp/test-finderapps.XXXXXX";
        if (!mkdtemp(tmpl)) { printf("FAIL: no temp folder\n"); return 1; }
        Root = [NSString stringWithUTF8String:tmpl];

        // ---- an installed app's container, as installd makes it ----
        NSString *tips = Container(@"982FC431-99D3-4C49-AE2B-58DEBC866A18", @[@"Tips.app", @"Tips.app/_CodeSignature", @"SC_Info"], @[@"iTunesMetadata.plist", @"BundleMetadata.plist", @"Tips.app/Info.plist"]);
        CHECK(Is(DMFinderBundleApp(tips), tips, @"Tips.app"), "the container's .app is the row: %s", DMFinderBundleApp(tips).UTF8String);
        NSString *clock = Container(@"204D15AB-D8F7-459F-B815-C733FE102687", @[@"MobileTimer.app"], @[@".com.apple.mobile_container_manager.metadata.plist"]);
        CHECK(Is(DMFinderBundleApp(clock), clock, @"MobileTimer.app"), "the bundle's own folder name (Clock is MobileTimer.app), as the .app items on the A12Z's desktop: %s", DMFinderBundleApp(clock).UTF8String);
        NSString *spaced = Container(@"C8C2E9C1-4AF8-4E0D-8FCB-9C910BF017DF", @[@"Photo Booth.app"], @[@"iTunesMetadata.plist"]);
        CHECK(Is(DMFinderBundleApp(spaced), spaced, @"Photo Booth.app"), "a name with a space");

        // ---- no app in it: the row stays the folder it is ----
        NSString *empty = Container(@"00000000-0000-0000-0000-000000000001", @[], @[]);
        CHECK(Is(DMFinderBundleApp(empty), empty, nil), "an empty container: no app");
        NSString *half = Container(@"00000000-0000-0000-0000-000000000002", @[@"SC_Info"], @[@"iTunesMetadata.plist", @"BundleMetadata.plist"]);
        CHECK(Is(DMFinderBundleApp(half), half, nil), "a container without its .app (being installed or removed): no app");
        CHECK(DMFinderBundleApp([Root stringByAppendingPathComponent:@"gone"]) == nil && DMFinderBundleApp(nil) == nil && DMFinderBundleApp(@"") == nil, "a container that isn't there: no app");

        // ---- only a real .app folder ----
        NSString *file = Container(@"00000000-0000-0000-0000-000000000003", @[], @[@"Fake.app"]);
        CHECK(Is(DMFinderBundleApp(file), file, nil), "a FILE named .app is no app");
        NSString *link = Container(@"00000000-0000-0000-0000-000000000004", @[], @[]);
        symlink(tips.fileSystemRepresentation, [link stringByAppendingPathComponent:@"Linked.app"].fileSystemRepresentation);
        CHECK(Is(DMFinderBundleApp(link), link, nil), "a LINK named .app is no app (a row never leads out of its container)");
        NSString *hidden = Container(@"00000000-0000-0000-0000-000000000005", @[@".Hidden.app", @".app"], @[]);
        CHECK(Is(DMFinderBundleApp(hidden), hidden, nil), "a hidden .app, or one named only \".app\", is no app");
        NSString *ext = Container(@"00000000-0000-0000-0000-000000000006", @[@"Tips.appex", @"Tips.application", @"app"], @[]);
        CHECK(Is(DMFinderBundleApp(ext), ext, nil), "only the .app extension (not .appex, .application, a folder named app)");
        NSString *mixed = Container(@"00000000-0000-0000-0000-000000000007", @[@"Real.app"], @[@"A.app"]);
        symlink(tips.fileSystemRepresentation, [mixed stringByAppendingPathComponent:@"0.app"].fileSystemRepresentation);
        CHECK(Is(DMFinderBundleApp(mixed), mixed, @"Real.app"), "a link and a file before it by name are passed over: the real folder");

        // ---- two (never made by installd): the first by name, every time ----
        NSString *two = Container(@"00000000-0000-0000-0000-000000000008", @[@"Zeta.app", @"Alpha.app"], @[]);
        CHECK(Is(DMFinderBundleApp(two), two, @"Alpha.app"), "two apps: the first by name");
        BOOL same = YES; for (int i = 0; i < 20; i++) same = same && Is(DMFinderBundleApp(two), two, @"Alpha.app");
        CHECK(same, "  ... the same one every time");

        // ---- the drop: Finder.h -dm_run: copies src to DMFinderFreeName(dir, src.lastPathComponent, ...) -- the row's path is the .app, so the
        //      desktop gets the app item with the .app's name; the installed app is only read ----
        NSString *desk = [Root stringByAppendingPathComponent:@"Desktop"]; [FM createDirectoryAtPath:desk withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *src = DMFinderBundleApp(tips), *dst = [desk stringByAppendingPathComponent:src.lastPathComponent];
        CHECK([FM copyItemAtPath:src toPath:dst error:nil], "the drop's copy");
        BOOL isDir = NO;
        CHECK([dst.lastPathComponent isEqualToString:@"Tips.app"] && [FM fileExistsAtPath:dst isDirectory:&isDir] && isDir && [FM fileExistsAtPath:[dst stringByAppendingPathComponent:@"Info.plist"]], "  ... the desktop has Tips.app, the app's own folder with its Info.plist (its icon and its opening read it)");
        CHECK(![FM fileExistsAtPath:[desk stringByAppendingPathComponent:@"982FC431-99D3-4C49-AE2B-58DEBC866A18"]] && ![FM fileExistsAtPath:[desk stringByAppendingPathComponent:@"iTunesMetadata.plist"]], "  ... not the UUID folder, nothing of the container around it");
        CHECK([FM removeItemAtPath:dst error:nil] && [FM fileExistsAtPath:[src stringByAppendingPathComponent:@"Info.plist"]] && [FM fileExistsAtPath:[tips stringByAppendingPathComponent:@"iTunesMetadata.plist"]], "  ... removing the desktop's copy leaves the installed app as it was");

        [FM removeItemAtPath:Root error:nil];
    }
    printf("test-finderapps: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
