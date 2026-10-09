// JailbreakInfo.h -- which jailbreak this iPad runs (About This iPad > Jailbreak, and the Shut Down question), found by the marker each one leaves
// in its root, not by which app is installed (1.4.3, S-4: the iPad 2 runs palera1n and About said "Dopamine", because the old code fell back to that
// name whenever the Dopamine app was missing). Plain Foundation: StatusBar.x passes the root ("" = the iPad's own) and how to read an installed
// app's version; the Mac test (tools/test-jbinfo.sh) passes fake roots.
//  - palera1n: /var/jb/.installed_palera1n (rootless) or /.installed_palera1n (rootful), and its binpack at /cores/binpack. palera1n keeps no
//    version of its own on the iPad; its marker names the loader that set it up ("Bootstrapper-Name=palera1nLoader", "Bootstrapper-Version=2.1.1"
//    on the iPad 2), shown as "palera1n (Loader 2.1.1)". Semi-tethered: after a restart it is run again from a computer.
//  - Dopamine: /var/jb/.installed_dopamine; its version is the one running (basebin/.version, "2.4.5" on the M1), else its app's.
//  - another jailbreak that marks its root the same way (/var/jb/.installed_<name>) is named after its marker.
//  - nothing found: no name ("Unknown" in About; the Shut Down text names no jailbreak).
#pragma once
#import <Foundation/Foundation.h>
#import <unistd.h>

typedef struct { NSString *name; NSString *version; BOOL fromComputer; } MSBDJailbreak;

static NSString *MSBDJBVersionIn(NSString *text) {   // (a version as a jailbreak writes it: "2.4.5"; anything else is not shown)
    NSString *v = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (v.length < 1 || v.length > 32 || ![[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[v characterAtIndex:0]]) return nil;
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-+~"];
    return [v rangeOfCharacterFromSet:[ok invertedSet]].location == NSNotFound ? v : nil;
}
static MSBDJailbreak MSBDJailbreakAt(NSString *root, NSString *(^appVersion)(NSString *bundleID)) {
    root = root ?: @"";
    BOOL (^has)(NSString *) = ^BOOL(NSString *p) { return access([root stringByAppendingString:p].fileSystemRepresentation, F_OK) == 0; };
    NSString *(^read)(NSString *) = ^NSString *(NSString *p) { return [NSString stringWithContentsOfFile:[root stringByAppendingString:p] encoding:NSUTF8StringEncoding error:nil]; };
    MSBDJailbreak jb = { nil, nil, NO };
    if (has(@"/var/jb/.installed_palera1n") || has(@"/.installed_palera1n") || has(@"/cores/binpack")) {
        jb.name = @"palera1n"; jb.fromComputer = YES;
        NSString *marker = read(has(@"/var/jb/.installed_palera1n") ? @"/var/jb/.installed_palera1n" : @"/.installed_palera1n");
        NSString *loader = nil, *loaderVersion = nil;
        for (NSString *line in [marker componentsSeparatedByString:@"\n"]) {
            NSRange eq = [line rangeOfString:@"="];
            if (eq.location == NSNotFound) continue;
            NSString *k = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *v = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([k isEqualToString:@"Bootstrapper-Name"]) loader = v;
            else if ([k isEqualToString:@"Bootstrapper-Version"]) loaderVersion = MSBDJBVersionIn(v);
        }
        BOOL plainName = !loader.length || [loader isEqualToString:@"palera1nLoader"] || loader.length > 32;
        if (loaderVersion) jb.version = [NSString stringWithFormat:@"(%@ %@)", plainName ? @"Loader" : loader, loaderVersion];
    } else if (has(@"/var/jb/.installed_dopamine")) {
        jb.name = @"Dopamine";
        jb.version = MSBDJBVersionIn(read(@"/var/jb/basebin/.version")) ?: (appVersion ? MSBDJBVersionIn(appVersion(@"com.opa334.Dopamine")) : nil);
    } else {
        NSDictionary *known = @{ @"fugu15max": @"Fugu15 Max", @"fugu15": @"Fugu15", @"xina15": @"XinaA15", @"xina": @"XinaA15", @"nathanlr": @"NathanLR",
                                 @"serotonin": @"Serotonin", @"bootstrap": @"Bootstrap" };
        for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[root stringByAppendingString:@"/var/jb"] error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![f hasPrefix:@".installed_"] || f.length <= 11 || f.length > 40) continue;
            NSString *n = [f substringFromIndex:11];
            jb.name = known[n.lowercaseString] ?: [[n substringToIndex:1].uppercaseString stringByAppendingString:[n substringFromIndex:1]];
            break;
        }
    }
    return jb;
}
static NSString *MSBDJailbreakTitle(MSBDJailbreak jb) {   // About This iPad > Jailbreak: "Dopamine 2.4.5", "palera1n (Loader 2.1.1)", "Unknown"
    if (!jb.name) return @"Unknown";
    return jb.version ? [NSString stringWithFormat:@"%@ %@", jb.name, jb.version] : jb.name;
}
static NSString *MSBDJailbreakAfterRestart(MSBDJailbreak jb) {   // (the Shut Down question's second line)
    if (!jb.name) return @"You will need to jailbreak this iPad again after turning it back on.";
    if (jb.fromComputer) return [NSString stringWithFormat:@"You will need to run %@ from a computer again after turning it back on.", jb.name];
    return [NSString stringWithFormat:@"You will need to run %@ again after turning it back on.", jb.name];
}
