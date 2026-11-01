// CCModuleList.h -- our Control Center controls' folders and identifiers added to Control Center's module lists (common/CCModuleRegister.h),
// Foundation only so the Mac test (tools/test-ccmodule.sh) runs this very code: added once, in the list's own kind (URLs or paths; a set or an
// array), nothing else touched. Two controls (1.7.6): RAM & CPU (ccmodule/, MacRAMCPU.bundle) and SSH (MacSSH.bundle), each in a folder of its
// own, so a control that is not to be offered -- SSH without OpenSSH, either one on the crash guard's step 1b skip list -- is not in Control
// Center's repository at all (never listed in Settings > Control Center, never offered in 18's gallery, its tile dropped as with any module gone).
// Also the user's own list of controls with RAM & CPU in Memory Magic's place (the status bar part's tile drawn over Memory Magic's, 1.6.2).
// (static inline: the status bar part includes this for the one function it uses)
#pragma once
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "SSHSwitch.h"   // (kMSBDSSHDaemon: OpenSSH installed)

#define kMSBDCCModuleID @"com.besiktasliseba.macstatusbaranddock.ramcpu"
#define kMSBDCCModuleDir @"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenter"
#define kMSBDCCSSHModuleID @"com.besiktasliseba.macstatusbaranddock.ssh"
#define kMSBDCCSSHModuleDir @"/var/jb/usr/lib/MacStatusBarAndDock/ControlCenterSSH"
#define kMSBDCCModuleStepFile "/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-CrashStep.txt"   // (= CrashStep.h's MSBD_STEP_FILE)
#define kMSBDMemoryMagicID @"com.sop.MemoryMagic"   // (Memory Magic, xyz.cypwn.memorymagic: the module the status bar part draws its RAM tile over)
// 18: the app each control is shown with in "Add a Control" (CCModuleRegister.h, the module settings): RAM & CPU with Activity Monitor (1.7.6 item
// 3; our App Library leaf, statusbar/AppLibraryApps.h), SSH with Settings (where its switch is, as Remote Login is in a Mac's System Settings)
#define kMSBDCCActivityMonitorID @"com.besiktasliseba.macstatusbar.activitymonitor"
#define kMSBDCCSettingsAppID @"com.apple.Preferences"
// RAM & CPU's app is Activity Monitor only while the status bar part names Activity Monitor's gallery section (statusbar/AppLibraryApps.h,
// DMALGalleryIconInit: its hook is in, whatever Show in App Library says); the part answers through this exported function, found with
// dlsym in SpringBoard (another of our dylibs, and nothing kept outside the process: a SpringBoard without that part asks again and gets no).
// Without it RAM & CPU stays with SpringBoard, as before 1.7.6: Activity Monitor is no installed app, its section would be a blank "RAM & CPU".
#define kMSBDCCActivityMonitorSectionFn "MSBDCCActivityMonitorSectionReady"
static inline NSString *MSBDCCContainerForModule(NSString *mid, BOOL activityMonitorSection) {
    if ([mid isEqualToString:kMSBDCCSSHModuleID]) return kMSBDCCSettingsAppID;
    return activityMonitorSection ? kMSBDCCActivityMonitorID : @"com.apple.springboard";
}
// Is a gallery section (SBHApplicationWidgetCollection) Activity Monitor's, to be shown with its name and picture? The gallery makes each module
// section with a bare leaf icon of a fresh UUID, no application identifier and a UUID of its own (A12Z 18.5, 1 Nov: RAM & CPU's, SSH's and
// SpringBoard's alike), so only its controls tell: Activity Monitor's holds RAM & CPU and nothing else. Never SpringBoard's own section, which
// holds every third-party control (Zetsu's, Aerial's toggles) -- RAM & CPU too where its app is SpringBoard. An icon made for an installed app
// (its application identifier) is that app's section.
static inline BOOL MSBDCCGallerySectionIsActivityMonitor(NSString *appID, NSArray *moduleIDs) {
    if ([appID isKindOfClass:[NSString class]]) return [appID isEqualToString:kMSBDCCActivityMonitorID];
    if (![moduleIDs isKindOfClass:[NSArray class]] || !moduleIDs.count) return NO;
    for (id m in moduleIDs) if (![m isEqual:kMSBDCCModuleID]) return NO;
    return YES;
}
// The package's removal (sshtoggled --uninstall, the prerm): SpringBoard takes our controls out of the user's list of controls (15-17,
// CCModuleRegister.h), as the helper does in the files
#define kMSBDCCRemovingNote "com.besiktasliseba.msbd.ccmodules.removing"
// The 15-17 lists of controls: Apple's, and CCSupport's own where it is installed (BigSurCenter reads that one itself)
#define kMSBDCCAppleListFile @"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist"
#define kMSBDCCCCSupportListFile @"/var/jb/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"
// A 15-17 list of controls (one of the files above, as a dictionary) without ours: in every one of its lists; nil when none of ours is in it.
static inline NSDictionary *MSBDCCListWithoutOurs(NSDictionary *list) {
    if (![list isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *out = [list mutableCopy]; BOOL changed = NO;
    for (NSString *key in @[@"module-identifiers", @"disabled-module-identifiers", @"userenabled-fixed-module-identifiers"]) {
        NSArray *ids = list[key];
        if (![ids isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *kept = [ids mutableCopy];
        [kept removeObjectsInArray:@[kMSBDCCModuleID, kMSBDCCSSHModuleID]];
        if (kept.count != ids.count) { out[key] = kept; changed = YES; }
    }
    return changed ? out : nil;
}

static inline NSString *MSBDCCRealPath(NSString *p) { return p.stringByStandardizingPath.stringByResolvingSymlinksInPath; }   // (/var/jb is a link)
static inline BOOL MSBDCCSameFolder(id d, NSString *dir) {   // (a folder as a list has it -- a URL or a path -- is `dir`)
    NSString *p = [d isKindOfClass:[NSURL class]] ? [(NSURL *)d path] : ([d isKindOfClass:[NSString class]] ? d : nil);
    return p && ([p.stringByStandardizingPath isEqualToString:dir] || [MSBDCCRealPath(p) isEqualToString:MSBDCCRealPath(dir)]);
}
// `dirs` with each of `ours` (folders) added once, in the list's own kind; the list itself when nothing is added.
static inline NSArray *MSBDCCWithOurDirectories(NSArray *dirs, NSArray<NSString *> *ours) {
    if (![dirs isKindOfClass:[NSArray class]]) return dirs;
    NSMutableArray *out = nil;
    for (NSString *dir in ours) {
        BOOL there = NO;
        for (id d in out ?: dirs) if (MSBDCCSameFolder(d, dir)) { there = YES; break; }
        if (there) continue;
        if (!out) out = [dirs mutableCopy];
        [out addObject:[dirs.firstObject isKindOfClass:[NSString class]] ? (id)dir : (id)[NSURL fileURLWithPath:dir isDirectory:YES]];
    }
    return out ?: dirs;
}
// An allowed list (an NSSet or NSArray) with each of `ours` (identifiers) added once; nil means no list -- everything loads, nothing to add.
static inline id MSBDCCWithOurIdentifiers(id allowed, NSArray<NSString *> *ours) {
    if ([allowed isKindOfClass:[NSSet class]]) { NSSet *more = [(NSSet *)allowed setByAddingObjectsFromArray:ours]; return more.count == [(NSSet *)allowed count] ? allowed : more; }
    if ([allowed isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = nil;
        for (NSString *i in ours) if (![out ?: allowed containsObject:i]) { if (!out) out = [allowed mutableCopy]; [out addObject:i]; }
        return out ?: allowed;
    }
    return allowed;
}
// (RAM & CPU alone, as before 1.7.6: the Mac test's first cases)
static inline NSArray *MSBDCCWithOurDirectory(NSArray *dirs) { return MSBDCCWithOurDirectories(dirs, @[kMSBDCCModuleDir]); }
static inline id MSBDCCWithOurIdentifier(id allowed) { return MSBDCCWithOurIdentifiers(allowed, @[kMSBDCCModuleID]); }
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
// Step 1b of the crash guard has this control on its skip list (the line "skip MacRAMCPU" / "skip MacSSH", common/CrashStep.h) and the guard's note
// is still there: Control Center does not load it then (common/CCModuleRegister.h), until the note is cleared. `stepFile`: the step file (the
// Mac test passes its own).
static inline BOOL MSBDCCStepListsPart(const char *stepFile, const char *part) {   // (the file has the line "skip <part>", with or without its title)
    FILE *f = stepFile && part ? fopen(stepFile, "r") : NULL;
    if (!f) return NO;   // (normally missing: the whole cost)
    char line[128]; BOOL listed = NO; size_t n = strlen(part);
    while (!listed && fgets(line, sizeof(line), f)) listed = !strncmp(line, "skip ", 5) && !strncmp(line + 5, part, n) && (line[5 + n] == ' ' || line[5 + n] == '\n' || !line[5 + n]);
    fclose(f);
    return listed;
}
static inline BOOL MSBDCCModuleSkippedIn(const char *stepFile, const char *part) {
    if (!MSBDCCStepListsPart(stepFile, part)) return NO;
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("crashGuardAction"), CFSTR("com.besiktasliseba.macstatusbaranddock"), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    int action = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &action);
    if (v) CFRelease(v);
    return action != 0;
}
static inline BOOL MSBDCCModuleSkipped(void) { return MSBDCCModuleSkippedIn(kMSBDCCModuleStepFile, "MacRAMCPU"); }   // (RAM & CPU)

// Our controls Control Center is to load now: each with its bundle in place, not on the skip list; SSH only with OpenSSH installed (as Settings'
// SSH row). `root` is put in front of every path (the Mac test's own folder; "" on the iPad). Their folders and identifiers, in the same order.
typedef struct { __unsafe_unretained NSString *identifier, *folder, *bundle; const char *part; BOOL needsSSH; } MSBDCCControl;   // (string literals)
static inline void MSBDCCActiveControls(NSString *root, const char *stepFile, NSMutableArray<NSString *> *folders, NSMutableArray<NSString *> *identifiers) {
    const MSBDCCControl controls[] = {
        { kMSBDCCModuleID, kMSBDCCModuleDir, @"MacRAMCPU.bundle", "MacRAMCPU", NO },
        { kMSBDCCSSHModuleID, kMSBDCCSSHModuleDir, @"MacSSH.bundle", "MacSSH", YES },
    };
    for (size_t i = 0; i < sizeof(controls) / sizeof(controls[0]); i++) {
        NSString *plist = [root stringByAppendingString:[controls[i].folder stringByAppendingPathComponent:[controls[i].bundle stringByAppendingPathComponent:@"Info.plist"]]];
        if (access(plist.fileSystemRepresentation, F_OK) != 0) continue;
        if (controls[i].needsSSH && access([root stringByAppendingString:@kMSBDSSHDaemon].fileSystemRepresentation, F_OK) != 0) continue;
        if (MSBDCCModuleSkippedIn(stepFile, controls[i].part)) continue;
        [folders addObject:controls[i].folder]; [identifiers addObject:controls[i].identifier];
    }
}
