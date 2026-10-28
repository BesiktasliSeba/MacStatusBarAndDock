// CCModuleList.h -- RAM & CPU's folder and identifier added to Control Center's module lists (common/CCModuleRegister.h), Foundation only so the
// Mac test (tools/test-ccmodule.sh) runs this very code: added once, in the list's own kind (URLs or paths; a set or an array), nothing else touched.
#pragma once
#import <Foundation/Foundation.h>

#define kMSBDCCModuleID @"com.besiktasliseba.macstatusbaranddock.ramcpu"
#define kMSBDCCModuleDir @"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenter"

static NSString *MSBDCCRealPath(NSString *p) { return p.stringByStandardizingPath.stringByResolvingSymlinksInPath; }   // (/var/jb is a link)
static NSArray *MSBDCCWithOurDirectory(NSArray *dirs) {
    if (![dirs isKindOfClass:[NSArray class]]) return dirs;
    NSString *ourReal = MSBDCCRealPath(kMSBDCCModuleDir);
    for (id d in dirs) {
        NSString *p = [d isKindOfClass:[NSURL class]] ? [(NSURL *)d path] : ([d isKindOfClass:[NSString class]] ? d : nil);
        if (p && ([p.stringByStandardizingPath isEqualToString:kMSBDCCModuleDir] || [MSBDCCRealPath(p) isEqualToString:ourReal])) return dirs;
    }
    id ours = [dirs.firstObject isKindOfClass:[NSString class]] ? (id)kMSBDCCModuleDir : (id)[NSURL fileURLWithPath:kMSBDCCModuleDir isDirectory:YES];
    return [dirs arrayByAddingObject:ours];
}
static id MSBDCCWithOurIdentifier(id allowed) {   // (an NSSet or NSArray; nil means no list -- everything loads, nothing to add)
    if ([allowed isKindOfClass:[NSSet class]]) return [(NSSet *)allowed containsObject:kMSBDCCModuleID] ? allowed : [(NSSet *)allowed setByAddingObject:kMSBDCCModuleID];
    if ([allowed isKindOfClass:[NSArray class]]) return [(NSArray *)allowed containsObject:kMSBDCCModuleID] ? allowed : [(NSArray *)allowed arrayByAddingObject:kMSBDCCModuleID];
    return allowed;
}
