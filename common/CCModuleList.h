// CCModuleList.h -- RAM & CPU's folder and identifier added to Control Center's module lists (common/CCModuleRegister.h), Foundation only so the
// Mac test (tools/test-ccmodule.sh) runs this very code: added once, in the list's own kind (URLs or paths; a set or an array), nothing else touched.
// Also the user's own list of controls with RAM & CPU in Memory Magic's place (the status bar part's tile drawn over Memory Magic's, 1.6.2).
// (static inline: the status bar part includes this for the one function it uses)
#pragma once
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

#define kMSBDCCModuleID @"com.besiktasliseba.macstatusbaranddock.ramcpu"
#define kMSBDCCModuleDir @"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenter"
#define kMSBDCCModuleStepFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashStep.txt"   // (= CrashStep.h's MSBD_STEP_FILE)
#define kMSBDMemoryMagicID @"com.sop.MemoryMagic"   // (Memory Magic, xyz.cypwn.memorymagic: the module the status bar part draws its RAM tile over)

static inline NSString *MSBDCCRealPath(NSString *p) { return p.stringByStandardizingPath.stringByResolvingSymlinksInPath; }   // (/var/jb is a link)
static inline NSArray *MSBDCCWithOurDirectory(NSArray *dirs) {
    if (![dirs isKindOfClass:[NSArray class]]) return dirs;
    NSString *ourReal = MSBDCCRealPath(kMSBDCCModuleDir);
    for (id d in dirs) {
        NSString *p = [d isKindOfClass:[NSURL class]] ? [(NSURL *)d path] : ([d isKindOfClass:[NSString class]] ? d : nil);
        if (p && ([p.stringByStandardizingPath isEqualToString:kMSBDCCModuleDir] || [MSBDCCRealPath(p) isEqualToString:ourReal])) return dirs;
    }
    id ours = [dirs.firstObject isKindOfClass:[NSString class]] ? (id)kMSBDCCModuleDir : (id)[NSURL fileURLWithPath:kMSBDCCModuleDir isDirectory:YES];
    return [dirs arrayByAddingObject:ours];
}
static inline id MSBDCCWithOurIdentifier(id allowed) {   // (an NSSet or NSArray; nil means no list -- everything loads, nothing to add)
    if ([allowed isKindOfClass:[NSSet class]]) return [(NSSet *)allowed containsObject:kMSBDCCModuleID] ? allowed : [(NSSet *)allowed setByAddingObject:kMSBDCCModuleID];
    if ([allowed isKindOfClass:[NSArray class]]) return [(NSArray *)allowed containsObject:kMSBDCCModuleID] ? allowed : [(NSArray *)allowed arrayByAddingObject:kMSBDCCModuleID];
    return allowed;
}
// The user's enabled controls in their order (Control Center's -orderedUserEnabledModuleIdentifiers) with RAM & CPU where `replaced` was: the same
// place, every other control kept in its order; RAM & CPU found elsewhere in the list moves there (it is never in a list twice). nil when
// `replaced` is not in the list (nothing to do).
static inline NSArray *MSBDCCInPlaceOf(NSArray *enabled, NSString *replaced) {
    if (![enabled isKindOfClass:[NSArray class]] || !replaced) return nil;
    NSUInteger at = [enabled indexOfObject:replaced];
    if (at == NSNotFound) return nil;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:enabled.count];
    for (NSUInteger i = 0; i < enabled.count; i++) {
        id m = enabled[i];
        if (i == at) [out addObject:kMSBDCCModuleID];
        else if (![m isEqual:kMSBDCCModuleID] && ![m isEqual:replaced]) [out addObject:m];
    }
    return out;
}
// Step 1b of the crash guard has RAM & CPU on its skip list (the line "skip MacRAMCPU") and the guard's note is still there: Control Center does
// not load it then (common/CCModuleRegister.h), until the note is cleared.
static inline BOOL MSBDCCModuleSkipped(void) {
    FILE *f = fopen(kMSBDCCModuleStepFile, "r");
    if (!f) return NO;   // (normally missing: the whole cost)
    char line[128]; BOOL listed = NO;
    while (!listed && fgets(line, sizeof(line), f)) listed = strncmp(line, "skip MacRAMCPU", 14) == 0;
    fclose(f);
    if (!listed) return NO;
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("crashGuardAction"), CFSTR("com.besiktasliseba.macstatusbaranddock"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    int action = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &action);
    if (v) CFRelease(v);
    return action != 0;
}
