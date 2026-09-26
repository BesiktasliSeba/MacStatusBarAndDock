// test-crashfeature.m -- Mac test of the crash guard's step 1b lookup (common/CrashFeature.h): which switch or part a crash report points at.
// Run: tools/test-crashstep.sh. Uses tools/crash-fixtures/test-crashmap.txt (synthetic map, test preference domain com.besiktasliseba.test-crashstep,
// removed again by the script) and the step1b-*.ips fixtures; with a map path + fixture + expected answer as arguments it checks a real build's map.
#import "../common/CrashFeature.h"
static int fails = 0;
static NSString *Answer(NSString *fixture, NSString *map) {
    NSString *action = nil, *detail = nil;
    BOOL ok = MSBDFeatureForReport([NSData dataWithContentsOfFile:fixture], map, &action, &detail);
    return ok ? action : [@"NO: " stringByAppendingString:action];
}
static void Expect(NSString *what, NSString *fixture, NSString *map, NSString *want) {
    NSString *got = Answer(fixture, map);
    BOOL pass = [want hasSuffix:@"*"] ? [got hasPrefix:[want substringToIndex:want.length - 1]] : [got isEqualToString:want];
    printf("%s  %-58s %s%s\n", pass ? "PASS" : "FAIL", what.UTF8String, got.UTF8String, pass ? "" : [NSString stringWithFormat:@"   (want %@)", want].UTF8String);
    if (!pass) fails++;
}
static void SetPref(NSString *key, id value) {
    CFPreferencesSetValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, CFSTR("com.besiktasliseba.test-crashstep"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.besiktasliseba.test-crashstep"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 4) {   // (a real build's map: <map> <fixture> <expected answer>)
            Expect([NSString stringWithFormat:@"built map: %s", strrchr(argv[2], '/') ? strrchr(argv[2], '/') + 1 : argv[2]], @(argv[2]),
                   [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil], @(argv[3]));
            return fails ? 1 : 0;
        }
        NSString *dir = argc > 1 ? @(argv[1]) : @"crash-fixtures";
        NSString *map = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"test-crashmap.txt"] encoding:NSUTF8StringEncoding error:nil];
        NSString *(^fx)(NSString *) = ^(NSString *n) { return [dir stringByAppendingPathComponent:n]; };
        NSString *D = @"com.besiktasliseba.test-crashstep";
        SetPref(@"macBanners", nil); SetPref(@"stockStatusBar", nil); SetPref(@"showDownloads", nil); SetPref(@"forceQuitEnabled", nil);
        Expect(@"MacDock: the Dock part as a whole", fx(@"step1b-dock.ips"), map, @"part DockMagnification - - 0 the Dock|MacDock");
        Expect(@"MacDock: Downloads code -> Show Downloads off", fx(@"step1b-dock-downloads.ips"), map, [NSString stringWithFormat:@"pref DockMagnification %@ showDownloads 0 Show Downloads in Dock|the Dock's Downloads", D]);
        Expect(@"small part without a switch -> the part", fx(@"step1b-small-part.ips"), map, @"part MixAudio - - 0 its part MixAudio|MixAudio");
        Expect(@"small part with a switch -> its switch", fx(@"step1b-small-part-switch.ips"), map, [NSString stringWithFormat:@"pref ForceQuitMenu %@ forceQuitEnabled 0 Force Quit in App Menus|the Force Quit menu item", D]);
        Expect(@"core, banners function -> Mac-Style Banners off", fx(@"step1b-core-banners.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ macBanners 0 Mac-Style Banners|the Mac-style banners", D]);
        Expect(@"core, banners (exception backtrace) -> banners off", fx(@"step1b-core-banners-exception.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ macBanners 0 Mac-Style Banners|the Mac-style banners", D]);
        Expect(@"core, menu function -> Stock status bar", fx(@"step1b-core-menu.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        Expect(@"core, another build (UUID not in map) -> fallback Stock", fx(@"step1b-core-other-build.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        Expect(@"core, offset outside the map -> fallback Stock", fx(@"step1b-core-outside-map.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        Expect(@"loader on top -> nothing (step 2)", fx(@"step1b-loader.ips"), map, @"NO: MacStatusBar cannot be turned off on its own");
        Expect(@"Apple-only report -> nothing (step 2)", fx(@"apple-only-our-class-in-reason.ips"), map, @"NO: none of our code on the crash stacks*");
        Expect(@"another tweak's crash -> nothing", fx(@"other-tweak.ips"), map, @"NO: not pinned on us*");
        Expect(@"no map shipped -> nothing (step 2)", fx(@"step1b-core-banners.ips"), nil, @"NO: no crash map");
        Expect(@"unreadable report -> nothing", fx(@"test-crashmap.txt"), map, @"NO: not pinned on us*");
        SetPref(@"macBanners", @NO);
        Expect(@"banners already off -> Stock status bar instead", fx(@"step1b-core-banners.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        SetPref(@"stockStatusBar", @YES);
        Expect(@"already Stock status bar -> the part instead", fx(@"step1b-core-menu.ips"), map, @"part MacStatusBarCore - - 0 the status bar|the Mac status bar");
        Expect(@"banners off and Stock on -> the part", fx(@"step1b-core-banners.ips"), map, @"part MacStatusBarCore - - 0 the status bar|the Mac status bar");
        SetPref(@"forceQuitEnabled", @NO);
        Expect(@"small part's switch already off -> the part", fx(@"step1b-small-part-switch.ips"), map, @"part ForceQuitMenu - - 0 its part ForceQuitMenu|ForceQuitMenu");
        SetPref(@"forceQuitEnabled", nil);
        SetPref(@"macBanners", nil); SetPref(@"stockStatusBar", nil);
    }
    return fails ? 1 : 0;
}
