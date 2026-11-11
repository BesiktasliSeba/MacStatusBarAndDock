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
        SetPref(@"macBanners", nil); SetPref(@"stockStatusBar", nil); SetPref(@"showDownloads", nil); SetPref(@"forceQuitEnabled", nil); SetPref(@"controlCenterStyle", nil); SetPref(@"dockStyle", nil);
        Expect(@"the Dock part as a whole", fx(@"step1b-dock.ips"), map, @"part DockMagnification - - 0 the Dock|the Dock");
        Expect(@"the Dock: Downloads code -> Show Downloads off", fx(@"step1b-dock-downloads.ips"), map, [NSString stringWithFormat:@"pref DockMagnification %@ showDownloads 0 Show Downloads in Dock|the Dock's Downloads", D]);
        // Dock Style (1.8.4, review P2-L1): Settings stores "default" for Default, read as off (the rule's offtext=default) -- a crash in its code with
        // Default is not Dock Style's, the part goes; "glass" reads as on, set back to Default. The platter's layout hook is transparent: alone under
        // Apple's crash, the part (never a style); over another frame of ours, that frame decides.
        NSString *dockPart = @"part DockMagnification - - 0 the Dock|the Dock", *dockStyle = [NSString stringWithFormat:@"pref DockMagnification %@ dockStyle 0 text=default Dock Style|the older Dock style", D];
        Expect(@"Dock Style's code, never set (Default) -> the part", fx(@"step1b-dock-style.ips"), map, dockPart);
        SetPref(@"dockStyle", @"default");
        Expect(@"  ... Default as Settings stores it (\"default\") -> the part", fx(@"step1b-dock-style.ips"), map, dockPart);
        SetPref(@"dockStyle", @"glass");
        Expect(@"  ... Glass Shelf -> Dock Style back to Default (\"default\" stored, as Settings stores it)", fx(@"step1b-dock-style.ips"), map, dockStyle);
        SetPref(@"dockStyle", @"frosted");
        Expect(@"  ... Frosted -> the same", fx(@"step1b-dock-style.ips"), map, dockStyle);
        SetPref(@"dockStyle", @NO);
        Expect(@"  ... set back by the guard before (false) -> the part", fx(@"step1b-dock-style.ips"), map, dockPart);
        SetPref(@"dockStyle", @"glass");
        Expect(@"the platter's layout hook alone under Apple's crash -> the part, never a style", fx(@"step1b-dock-hook.ips"), map, dockPart);
        SetPref(@"dockStyle", nil);
        Expect(@"  ... over Downloads' code -> Show Downloads (the frame below decides)", fx(@"step1b-dock-hook-downloads.ips"), map, [NSString stringWithFormat:@"pref DockMagnification %@ showDownloads 0 Show Downloads in Dock|the Dock's Downloads", D]);
        Expect(@"small part without a switch -> the part", fx(@"step1b-small-part.ips"), map, @"part MixAudio - - 0 its part MixAudio|MixAudio");
        Expect(@"small part with a switch -> its switch", fx(@"step1b-small-part-switch.ips"), map, [NSString stringWithFormat:@"pref ForceQuitMenu %@ forceQuitEnabled 0 Force Quit in App Menus|the Force Quit menu item", D]);
        Expect(@"core, banners function -> Mac-Style Banners off", fx(@"step1b-core-banners.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ macBanners 0 Mac-Style Banners|the Mac-style banners", D]);
        Expect(@"core, banners (exception backtrace) -> banners off", fx(@"step1b-core-banners-exception.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ macBanners 0 Mac-Style Banners|the Mac-style banners", D]);
        // A piece (review of 1.8.6: the battery icon's plug, no Settings row): on the skip list under its target's name, recorded as a part (Turn Back
        // On), whatever is stored; the same report with the banners' target made a piece of the core
        NSString *pieceMap = [map stringByReplacingOccurrencesOfString:@"T macBanners pref com.besiktasliseba.test-crashstep macBanners 0 1 Mac-Style Banners|the Mac-style banners"
                                                            withString:@"T macBanners piece the banners|the Mac-style banners"];
        Expect(@"core, a piece's code -> the piece as a part (its target's name)", fx(@"step1b-core-banners.ips"), pieceMap, @"part macBanners - - 0 the banners|the Mac-style banners");
        SetPref(@"macBanners", @NO);
        Expect(@"  ... a stored switch of the same name changes nothing", fx(@"step1b-core-banners.ips"), pieceMap, @"part macBanners - - 0 the banners|the Mac-style banners");
        SetPref(@"macBanners", nil);
        Expect(@"core, menu function -> Stock status bar", fx(@"step1b-core-menu.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        Expect(@"core, another build (UUID not in map) -> fallback Stock", fx(@"step1b-core-other-build.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        // A watchdog report (stacks only in a stackshot, CrashBlame.h): stuck in our core -> its part's fallback, like a crash there.
        gMSBDBlameUUIDOverride = @{@"2e3ea764-a57d-4cf0-a1e4-4263b5c18693": @"/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib"};
        Expect(@"watchdog, stuck in the core -> fallback Stock", fx(@"watchdog-stuck-main.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        gMSBDBlameUUIDOverride = @{@"2e3ea764-a57d-4cf0-a1e4-4263b5c18693": @"/var/jb/usr/lib/TweakInject/Aerial.dylib"};
        Expect(@"watchdog, stuck in another tweak -> nothing", fx(@"watchdog-stuck-main.ips"), map, @"NO: not pinned on us*");
        gMSBDBlameUUIDOverride = nil;
        Expect(@"core, offset outside the map -> fallback Stock", fx(@"step1b-core-outside-map.ips"), map, [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D]);
        Expect(@"loader on top -> nothing (step 2)", fx(@"step1b-loader.ips"), map, @"NO: MacStatusBar cannot be turned off on its own");
        // The shared Control Center lookups (1.8.0, CCController.h / StatusBar.x: transparent) on top of our Control Center's code, under a trap in
        // Apple's +sharedInstance (1.8.0~i11): the caller one frame lower decides -- Control Center Style back to iPadOS's, not Stock status bar mode.
        // Ours runs only with "mac" stored (KT 3 Nov: never ours unless picked): the rule's offtext=stock,bigsurcenter and nothing stored read as off.
        NSString *cc = [NSString stringWithFormat:@"pref MacStatusBarCore %@ controlCenterStyle 0 text=stock Control Center Style|our Control Center", D];   // (stored: "stock", its first off text)
        NSString *stockBar = [NSString stringWithFormat:@"pref MacStatusBarCore %@ stockStatusBar 1 Status Bar Style|the status bar", D];
        SetPref(@"controlCenterStyle", @"mac");   // (the Style page's text: ours, the guard can set it back)
        Expect(@"core, Control Center lookups on top -> the caller's", fx(@"step1b-core-cc-lookup.ips"), map, cc);
        Expect(@"  ... without the lookups passed over: Stock (the i11 case)", fx(@"step1b-core-cc-lookup.ips"),
               [map stringByReplacingOccurrencesOfString:@"R 12000 transparent" withString:@"R 12000 stock"], stockBar);
        SetPref(@"controlCenterStyle", @NO);
        Expect(@"  ... already iPadOS's (false) -> Stock status bar instead", fx(@"step1b-core-cc-lookup.ips"), map, stockBar);
        SetPref(@"controlCenterStyle", @"stock");
        Expect(@"  ... iPadOS's as the Style page stores it (\"stock\") -> the same", fx(@"step1b-core-cc-lookup.ips"), map, stockBar);
        SetPref(@"controlCenterStyle", @"bigsurcenter");
        Expect(@"  ... BigSurCenter (\"bigsurcenter\": ours does not run) -> the same", fx(@"step1b-core-cc-lookup.ips"), map, stockBar);
        SetPref(@"controlCenterStyle", nil);
        Expect(@"  ... nothing stored (never ours unless picked) -> the same", fx(@"step1b-core-cc-lookup.ips"), map, stockBar);
        // (nothing of ours but the lookups: as a pass-through hook alone, the part)
        Expect(@"core, only the Control Center lookups -> the part", fx(@"step1b-core-cc-lookup-only.ips"), map, @"part MacStatusBarCore - - 0 the status bar|the Mac status bar");
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
        SetPref(@"macBanners", nil); SetPref(@"stockStatusBar", nil); SetPref(@"controlCenterStyle", nil); SetPref(@"dockStyle", nil);
    }
    return fails ? 1 : 0;
}
