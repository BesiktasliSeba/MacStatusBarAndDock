// Mac test of common/CCModuleList.h (run by test-ccmodule.sh).
#import <Foundation/Foundation.h>
#include "../common/CCModuleList.h"
#include "../ccmodule/RAMCPULayout.h"

static int fails = 0, passes = 0;
#define CHECK(cond, ...) do { if (cond) { passes++; } else { fails++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    @autoreleasepool {
        // 18.5's directories (URLs, as -_initWithDirectoryURLs: gets them)
        NSArray *urls = @[[NSURL fileURLWithPath:@"/System/Library/ControlCenter/Bundles"], [NSURL fileURLWithPath:@"/System/Cryptexes/App/System/Library/ControlCenter/Bundles"]];
        NSArray *u2 = MSBDCCWithOurDirectory(urls);
        CHECK(u2.count == 3, "one folder added (%lu)", (unsigned long)u2.count);
        CHECK([u2.lastObject isKindOfClass:[NSURL class]] && [[u2.lastObject path] isEqualToString:kMSBDCCModuleDir], "ours, as a URL");
        CHECK([u2[0] isEqual:urls[0]] && [u2[1] isEqual:urls[1]], "Apple's folders kept, in order");
        CHECK(MSBDCCWithOurDirectory(u2).count == 3, "added once (the list already has it)");
        // paths (a list of strings)
        NSArray *paths = @[@"/System/Library/ControlCenter/Bundles"];
        NSArray *p2 = MSBDCCWithOurDirectory(paths);
        CHECK(p2.count == 2 && [p2.lastObject isKindOfClass:[NSString class]] && [p2.lastObject isEqualToString:kMSBDCCModuleDir], "ours, as a path");
        CHECK(MSBDCCWithOurDirectory([paths arrayByAddingObject:[kMSBDCCModuleDir stringByAppendingString:@"/"]]).count == 2, "a trailing slash is the same folder");
        CHECK(MSBDCCWithOurDirectory(nil) == nil, "no list: none made");
        // allowed list: a set (17.5 / 18.5) or an array
        NSSet *allowed = [NSSet setWithArray:@[@"com.apple.control-center.MuteModule", @"com.apple.FocusUIModule"]];
        NSSet *a2 = MSBDCCWithOurIdentifier(allowed);
        CHECK(a2.count == 3 && [a2 containsObject:kMSBDCCModuleID] && [allowed isSubsetOfSet:a2], "set: ours added, Apple's kept");
        CHECK(MSBDCCWithOurIdentifier(a2) == a2, "set: added once");
        NSArray *arr = @[@"com.apple.control-center.MuteModule"];
        NSArray *arr2 = MSBDCCWithOurIdentifier(arr);
        CHECK(arr2.count == 2 && [arr2.lastObject isEqualToString:kMSBDCCModuleID], "array: ours added at the end");
        CHECK(MSBDCCWithOurIdentifier(nil) == nil, "no allowed list (everything loads): nothing added");
        // RAM & CPU in Memory Magic's place (the tile drawn over Memory Magic's, 1.6.2): the M1's own list (15.6.1, CCSupport + BigSurCenter, 29 Oct)
        NSArray *m1 = @[@"com.apple.control-center.ConnectivityModule", @"com.apple.mediaremote.controlcenter.nowplaying", @"com.apple.control-center.OrientationLockModule",
            @"com.apple.mediaremote.controlcenter.airplaymirroring", @"com.apple.control-center.DisplayModule", @"com.apple.mediaremote.controlcenter.audio",
            @"com.apple.control-center.MuteModule", @"com.apple.control-center.FlashlightModule", @"com.apple.control-center.CameraModule",
            @"com.apple.donotdisturb.DoNotDisturbModule", @"com.mtac.uptimemodule", @"com.0xkuj.ccadsbegone", @"com.apple.keyboard.KeyboardBrightnessModule",
            @"com.apple.replaykit.controlcenter.screencapture", @"com.apple.control-center.LowPowerModule", @"jp.akusio.backgrounderaction15", kMSBDMemoryMagicID,
            @"com.KingPuffaddi.control-center.CCWiFiQR", @"com.ginsu.pockettranslatorcc", @"com.uzra.aerial.togglecc"];
        NSArray *s1 = MSBDCCInPlaceOf(m1, kMSBDMemoryMagicID);
        BOOL same = s1.count == m1.count;
        for (NSUInteger i = 0; same && i < m1.count; i++) same = i == 16 ? [s1[i] isEqualToString:kMSBDCCModuleID] : [s1[i] isEqualToString:m1[i]];
        CHECK(same, "M1's list: RAM & CPU at Memory Magic's place (16), the 19 others where they were");
        NSArray *withOurs = [@[@"com.apple.control-center.MuteModule", kMSBDMemoryMagicID, @"com.apple.control-center.CameraModule"] arrayByAddingObject:kMSBDCCModuleID];
        NSArray *s2 = MSBDCCInPlaceOf(withOurs, kMSBDMemoryMagicID);
        CHECK([s2 isEqualToArray:(@[@"com.apple.control-center.MuteModule", kMSBDCCModuleID, @"com.apple.control-center.CameraModule"])], "RAM & CPU already further down: moved to Memory Magic's place, once");
        CHECK(MSBDCCInPlaceOf(@[@"com.apple.control-center.MuteModule", kMSBDCCModuleID], kMSBDMemoryMagicID) == nil, "no Memory Magic in the list: nothing to do");
        CHECK(MSBDCCInPlaceOf(@[], kMSBDMemoryMagicID) == nil && MSBDCCInPlaceOf(nil, kMSBDMemoryMagicID) == nil && MSBDCCInPlaceOf((NSArray *)@{}, kMSBDMemoryMagicID) == nil, "an empty list, none, or not a list: nothing to do");
        NSArray *s3 = MSBDCCInPlaceOf(@[kMSBDMemoryMagicID, @"a", kMSBDMemoryMagicID], kMSBDMemoryMagicID);
        CHECK([s3 isEqualToArray:(@[kMSBDCCModuleID, @"a"])], "Memory Magic twice: RAM & CPU at the first place, the second one gone");
        CHECK(!MSBDCCModuleSkipped(), "no crash guard skip list on the Mac: RAM & CPU loads");
        // 1.7.6: two controls, each in a folder of its own -- both added once, in the list's own kind
        NSArray *two = @[kMSBDCCModuleDir, kMSBDCCSSHModuleDir];
        NSArray *u3 = MSBDCCWithOurDirectories(urls, two);
        CHECK(u3.count == 4 && [[u3[2] path] isEqualToString:kMSBDCCModuleDir] && [[u3[3] path] isEqualToString:kMSBDCCSSHModuleDir], "two folders of ours added, as URLs, after Apple's");
        CHECK(MSBDCCWithOurDirectories(u3, two).count == 4, "  ... once");
        CHECK(MSBDCCWithOurDirectories(u2, two).count == 4, "RAM & CPU's already there (an older list): only SSH's added");
        CHECK(MSBDCCWithOurDirectories(urls, @[]) == urls, "no control of ours to load: the list itself");
        NSSet *a3 = MSBDCCWithOurIdentifiers(allowed, @[kMSBDCCModuleID, kMSBDCCSSHModuleID]);
        CHECK(a3.count == 4 && [a3 containsObject:kMSBDCCSSHModuleID] && [a3 containsObject:kMSBDCCModuleID], "set: both identifiers added");
        CHECK(MSBDCCWithOurIdentifiers(a3, @[kMSBDCCModuleID, kMSBDCCSSHModuleID]) == a3, "set: added once");
        NSArray *arr3 = MSBDCCWithOurIdentifiers(arr2, @[kMSBDCCModuleID, kMSBDCCSSHModuleID]);
        CHECK(arr3.count == 3 && [arr3.lastObject isEqualToString:kMSBDCCSSHModuleID], "array: SSH added after RAM & CPU, which was there");
        // which controls load: the bundle in place, SSH only with OpenSSH, neither on step 1b's skip list (a folder of the test's own as the root)
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ccmodule-%d", getpid()]];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *ramPlist = [root stringByAppendingString:@"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenter/MacRAMCPU.bundle/Info.plist"];
        NSString *sshPlist = [root stringByAppendingString:@"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenterSSH/MacSSH.bundle/Info.plist"];
        NSString *sshd = [root stringByAppendingString:@"/var/jb/usr/sbin/sshd"], *step = [root stringByAppendingPathComponent:@"step.txt"];
        for (NSString *f in @[ramPlist, sshPlist, sshd]) { [fm createDirectoryAtPath:f.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]; [@"x" writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        NSMutableArray *folders = [NSMutableArray array], *ids = [NSMutableArray array];
        MSBDCCActiveControls(root, step.UTF8String, folders, ids);
        CHECK([ids isEqualToArray:(@[kMSBDCCModuleID, kMSBDCCSSHModuleID])] && [folders isEqualToArray:(@[kMSBDCCModuleDir, kMSBDCCSSHModuleDir])], "both bundles, OpenSSH installed: both load, each with its folder");
        [fm removeItemAtPath:sshd error:nil]; [folders removeAllObjects]; [ids removeAllObjects];
        MSBDCCActiveControls(root, step.UTF8String, folders, ids);
        CHECK([ids isEqualToArray:(@[kMSBDCCModuleID])] && [folders isEqualToArray:(@[kMSBDCCModuleDir])], "no OpenSSH: RAM & CPU only (SSH's folder not added: never offered)");
        [@"x" writeToFile:sshd atomically:YES encoding:NSUTF8StringEncoding error:nil]; [fm removeItemAtPath:ramPlist error:nil]; [folders removeAllObjects]; [ids removeAllObjects];
        MSBDCCActiveControls(root, step.UTF8String, folders, ids);
        CHECK([ids isEqualToArray:(@[kMSBDCCSSHModuleID])], "RAM & CPU's bundle not there: SSH only");
        // step 1b's skip list: a part by its whole name, with its title or without
        [@"row 1730000000\nskip MacSSH the SSH control in Control Center\n" writeToFile:step atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK(MSBDCCStepListsPart(step.UTF8String, "MacSSH") && !MSBDCCStepListsPart(step.UTF8String, "MacRAMCPU"), "the step file lists MacSSH (with its title), not MacRAMCPU");
        [@"skip MacSSHX\nskip MacRAMCPU\n" writeToFile:step atomically:YES encoding:NSUTF8StringEncoding error:nil];
        CHECK(!MSBDCCStepListsPart(step.UTF8String, "MacSSH") && MSBDCCStepListsPart(step.UTF8String, "MacRAMCPU"), "another part whose name starts the same is not MacSSH; MacRAMCPU without a title is listed");
        CHECK(!MSBDCCStepListsPart(NULL, "MacSSH") && !MSBDCCStepListsPart([root stringByAppendingPathComponent:@"none"].UTF8String, "MacSSH"), "no step file: nothing listed");
        [fm removeItemAtPath:root error:nil];
        // the removal: our controls out of a 15-17 list (the M1's CCSupport list, 29 Oct), every one of its lists, nothing else changed
        NSDictionary *cfg = @{@"module-identifiers": [m1 arrayByAddingObject:kMSBDCCSSHModuleID], @"disabled-module-identifiers": @[@"com.apple.FocusUIModule", kMSBDCCModuleID],
                              @"userenabled-fixed-module-identifiers": @[], @"version": @1};
        NSDictionary *clean = MSBDCCListWithoutOurs(cfg);
        NSMutableArray *m1less = [m1 mutableCopy]; [m1less removeObject:kMSBDCCModuleID];
        CHECK([clean[@"module-identifiers"] isEqualToArray:m1less] && [clean[@"disabled-module-identifiers"] isEqualToArray:@[@"com.apple.FocusUIModule"]]
              && [clean[@"version"] isEqual:@1] && [clean[@"userenabled-fixed-module-identifiers"] isEqualToArray:@[]], "removal: RAM & CPU and SSH out of every list, the rest as it was");
        CHECK(MSBDCCListWithoutOurs(clean) == nil && MSBDCCListWithoutOurs(nil) == nil && MSBDCCListWithoutOurs((NSDictionary *)@[]) == nil, "removal: nothing of ours, or no list: nothing to write");
        // 18's "Add a Control" (1.7.6 review S1): RAM & CPU's app is Activity Monitor whenever the status bar part names that section -- Show in
        // App Library on or off --, SpringBoard only without that part; SSH's is Settings either way
        CHECK([MSBDCCContainerForModule(kMSBDCCModuleID, YES) isEqualToString:kMSBDCCActivityMonitorID], "RAM & CPU: Activity Monitor while its section is named");
        CHECK([MSBDCCContainerForModule(kMSBDCCModuleID, NO) isEqualToString:@"com.apple.springboard"], "  ... SpringBoard without the status bar part (as before 1.7.6)");
        CHECK([MSBDCCContainerForModule(kMSBDCCSSHModuleID, YES) isEqualToString:kMSBDCCSettingsAppID] && [MSBDCCContainerForModule(kMSBDCCSSHModuleID, NO) isEqualToString:kMSBDCCSettingsAppID],
              "SSH: Settings either way");
        // which section is named Activity Monitor: the one holding only RAM & CPU, never SpringBoard's (Zetsu's, Aerial's toggles share that one).
        // Module sections come with no application identifier (a bare leaf icon of a fresh UUID, A12Z 18.5): the controls tell.
        NSString *zetsu = @"jp.dcsyhi.zetsu.ccmodule", *aerial = @"com.uzra.aerial.togglecc";
        CHECK(MSBDCCGallerySectionIsActivityMonitor(nil, @[kMSBDCCModuleID]), "a module section holding only RAM & CPU (Activity Monitor's): named");
        CHECK(!MSBDCCGallerySectionIsActivityMonitor(nil, @[zetsu, kMSBDCCModuleID, aerial]), "SpringBoard's section holding RAM & CPU with other tweaks' controls: left as SpringBoard's");
        CHECK(!MSBDCCGallerySectionIsActivityMonitor(nil, @[kMSBDCCModuleID, [NSNull null]]), "  ... nor with a control that has no module identifier");
        CHECK(!MSBDCCGallerySectionIsActivityMonitor(nil, @[]) && !MSBDCCGallerySectionIsActivityMonitor(nil, nil), "an empty section: not named");
        CHECK(!MSBDCCGallerySectionIsActivityMonitor(nil, @[kMSBDCCSSHModuleID]), "SSH's section: not Activity Monitor's");
        CHECK(!MSBDCCGallerySectionIsActivityMonitor(@"com.apple.Preferences", @[kMSBDCCModuleID]) && MSBDCCGallerySectionIsActivityMonitor(kMSBDCCActivityMonitorID, @[kMSBDCCModuleID]),
              "an icon made for an installed app: that app's section (Activity Monitor's only by its identifier)");
    }
    // the tile's lines (ccmodule/RAMCPULayout.h): Control Center's own 2 x 1 tile (142 x 66, iPad 2 16.7.7) as before 1.6.0's square layout;
    // BigSurCenter's square tile (75 x 75): every line at least 50 points wide (laid out for 2 x 1 there: 18 and 15 points, "..." on the screen)
    CGRect f[kRCCount];
    CHECK(!MSBDRAMCPUSquare(CGSizeMake(142, 66)) && !MSBDRAMCPUSquare(CGSizeMake(153, 69)), "2 x 1 tiles (16.7.7, 17.5) are laid out as 2 x 1");
    MSBDRAMCPUFrames(CGRectMake(0, 0, 142, 66), f);
    CHECK(fabs(f[kRCRamValue].size.width - 60.7616) < 0.01 && fabs(f[kRCCpuValue].size.width - 40.9184) < 0.01, "2 x 1: the widths 16.7.7 showed (%.4f, %.4f)", f[kRCRamValue].size.width, f[kRCCpuValue].size.width);
    CHECK(f[kRCUsed].size.width > 0 && f[kRCDivider].size.width == 0, "2 x 1: the used line, no divider");
    CHECK(CGRectGetMaxX(f[kRCCpuValue]) <= 142 && CGRectGetMaxY(f[kRCUsed]) <= 66, "2 x 1: inside the tile");
    CHECK(MSBDRAMCPUSquare(CGSizeMake(75, 75)), "BigSurCenter's 75 x 75 tile is square");
    MSBDRAMCPUFrames(CGRectMake(0, 0, 75, 75), f);
    int wide = 1, inside = 1;
    for (int i = 0; i < kRCCount; i++) {
        if (i == kRCUsed) { CHECK(f[i].size.width == 0, "square: no used line"); continue; }
        if (i != kRCDivider && f[i].size.width < 50.0) wide = 0;
        if (CGRectGetMaxX(f[i]) > 75.0 || CGRectGetMaxY(f[i]) > 75.0 || f[i].origin.x < 0 || f[i].origin.y < 0) inside = 0;
    }
    CHECK(wide, "square: every line at least 50 points wide");
    CHECK(inside, "square: every line inside the tile");
    CHECK(CGRectGetMaxY(f[kRCRamValue]) <= f[kRCDivider].origin.y && f[kRCDivider].origin.y < f[kRCCpuCaption].origin.y, "square: the memory, the line, then the CPU");
    printf("test-ccmodule: %d passed, %d failed\n", passes, fails);
    return fails ? 1 : 0;
}
