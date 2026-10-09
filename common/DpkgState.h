// DpkgState.h -- what dpkg's status text says about a package (MacStatusBar&Dock). Foundation only: the crash guard's explanations (CrashExplain.h)
// and the engine helper (macsettings/sshtoggled) read it; tested on the Mac (tools/test-dpkgcache.m).
#pragma once
#import <Foundation/Foundation.h>

// One field of one package in dpkg's status text: the block that starts with "Package: <package>" (a line of its own at a block's start), the
// field's own line in it ("<field>: " at a line's start, so Depends never matches Pre-Depends). Searched, not split: the file has a few thousand blocks.
static inline NSString *MSBDPackageFieldIn(NSString *status, NSString *package, NSString *field) {
    if (!status.length || !package.length || !field.length) return nil;
    NSString *head = [NSString stringWithFormat:@"Package: %@\n", package];
    NSUInteger start = NSNotFound;
    if ([status hasPrefix:head]) start = 0;
    else {
        NSRange r = [status rangeOfString:[@"\n" stringByAppendingString:head]];
        while (r.location != NSNotFound) {   // (a block's first line: the line before it is empty, or it is the file's first line)
            if (r.location == 0 || [status characterAtIndex:r.location - 1] == '\n') { start = r.location + 1; break; }
            NSUInteger from = NSMaxRange(r) - 1;
            r = [status rangeOfString:[@"\n" stringByAppendingString:head] options:0 range:NSMakeRange(from, status.length - from)];
        }
    }
    if (start == NSNotFound) return nil;
    NSRange end = [status rangeOfString:@"\n\n" options:0 range:NSMakeRange(start, status.length - start)];
    NSString *block = [status substringWithRange:NSMakeRange(start, (end.location == NSNotFound ? status.length : end.location) - start)];
    NSString *want = [field stringByAppendingString:@": "];
    for (NSString *line in [block componentsSeparatedByString:@"\n"]) if ([line hasPrefix:want]) return [line substringFromIndex:want.length];
    return nil;
}

// A package whose files are on the device and are meant to stay there: installed -- or still being set up by the dpkg run in progress (unpacked,
// half-configured, its triggers pending or awaited): its library loads at the next SpringBoard start all the same. One on its way out (want
// deinstall / purge) or broken (reinstreq, half-installed) does not count. The engine helper's choice at the postinst runs INSIDE the dpkg run, so
// an engine (or Choicy) installed or upgraded in the same run (a Sileo queue) is only "unpacked" then; counted as not installed, the choice could
// keep another engine loading next to the picked one or leave the picked one out (1.4.1 logic test M-1).
// The want state may also be "hold": a package the user keeps at its version (apt-mark hold, a package manager's "ignore updates") is installed
// all the same, and dpkg -i still sets it up in a run of its own; counted as not installed, the engine helper left the picked engine out.
static inline BOOL MSBDPackageOnDisk(NSString *status, NSString *package) {
    NSArray<NSString *> *w = [MSBDPackageFieldIn(status, package, @"Status") componentsSeparatedByString:@" "];
    if (w.count != 3 || ![@[@"install", @"hold"] containsObject:w[0]] || ![w[1] isEqualToString:@"ok"]) return NO;
    return [@[@"installed", @"unpacked", @"half-configured", @"triggers-awaited", @"triggers-pending"] containsObject:w[2]];
}
