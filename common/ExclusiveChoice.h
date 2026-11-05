// ExclusiveChoice.h -- one choice, one of them loaded (1.8.0; plans/control-center-1.8.0.md 3.3): the choices of ours whose options include other
// tweaks, and the libraries each keeps out of SpringBoard while another option is chosen -- Window Engine (Aerial, MilkyWay4 with its
// MilkyWay3SubModule, Zetsu: since 2026-09-24, "Option A"), Control Center Style (BigSurCenter: common/CCStyle.h) and Banner Style (Destra's
// MacOSNotifications: common/BannerStyle.h, release-1.8.0.md item 2). One table for both sides that do it, so they can never disagree on a name:
// Settings (MSBRootListController.m: a pick applies it in Choicy at once, as mobile) and the root helper (macsettings/sshtoggled: at every
// SpringBoard start, after an install, at a switch-on, through iCleaner Pro's renames where Choicy is not installed, and the give-backs -- a
// switch-off, the removal). As before for the engines:
//  - Choicy: the libraries kept out go into its global "denied tweaks" list (and SpringBoard's own list where that is in force), the chosen one's
//    come out of them. Every change is recorded (MacStatusBar-ChoicyChanges.plist: list -> entry -> "added"/"removed", the net effect), so a
//    give-back undoes exactly our entries, and only where an entry is still as we left it: everything the user changes in Choicy is theirs.
//  - iCleaner Pro (no Choicy): the root helper renames <lib>.dylib to <lib>.disabled, as iCleaner does, and records it (sshtoggled-engines/renamed).
//  - A library the user switched off themselves (in Choicy or iCleaner Pro, not by us) is never chosen by a default: the default engine never
//    was, and a never-set Control Center Style is BigSurCenter only where the user has not switched it off (MSBDExUserOff). (A never-set Banner
//    Style is never Destra: ours is the default for everyone, common/BannerStyle.h.)
// Foundation only, no paths read here but by the readers at the end (Mac test tools/test-choicetable.sh).
#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    const char *choice;    // the choice's key in com.besiktasliseba.macstatusbar (Window Engine, Control Center Style, Banner Style)
    const char *value;     // the value that loads it
    const char *name;      // its name in our alerts and logs
    const char *package;   // its package; NULL: whichever package owns the library (dpkg's file lists: BigSurCenter and Destra come from more
                           // than one repository, under more than one package name)
    const char *libs[3];   // its libraries in TweakInject (without .dylib)
} MSBDExclusiveEntry;
static const MSBDExclusiveEntry kMSBDExclusive[] = {
    { "windowEngine", "aerial", "Aerial", "jp.uzra.aerial", { "Aerial" } },
    { "windowEngine", "milkyway", "MilkyWay4", "jp.akusio.milkyway4", { "MilkyWay4", "MilkyWay3SubModule" } },
    { "windowEngine", "zetsu", "Zetsu", "jp.dcsyhi.zetsu", { "Zetsu" } },
    { "controlCenterStyle", "bigsurcenter", "BigSurCenter", NULL, { "BigSurCenter" } },
    { "bannerStyle", "destra", "Destra", NULL, { "MacOSNotifications" } },   // (Jax Roth's com.jaxroth.macosnotifications, or a package repacking it)
};
#define kMSBDExclusiveCount (sizeof(kMSBDExclusive) / sizeof(kMSBDExclusive[0]))
#define kMSBDExChoicyPrefs  @"/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist"
#define kMSBDExChoicyRecord @"/var/jb/var/mobile/Library/Preferences/MacStatusBar-ChoicyChanges.plist"
#define kMSBDExRenameRecord @"/var/jb/var/lib/sshtoggled-engines/renamed"   // (the root helper's: the libraries it renamed for iCleaner Pro)
#define kMSBDExTweakDir     @"/var/jb/usr/lib/TweakInject"

// The libraries of one option (value) of a choice, or of all its options (value nil); empty for none.
static inline NSArray<NSString *> *MSBDExLibs(NSString *choice, NSString *value) {
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < kMSBDExclusiveCount; i++) {
        if (![choice isEqualToString:@(kMSBDExclusive[i].choice)] || (value && ![value isEqualToString:@(kMSBDExclusive[i].value)])) continue;
        for (size_t k = 0; k < 3 && kMSBDExclusive[i].libs[k]; k++) [out addObject:@(kMSBDExclusive[i].libs[k])];
    }
    return out;
}
// The options of a choice that are other tweaks: value -> its libraries (the engines' table of before: {aerial: [Aerial], ...}).
static inline NSDictionary<NSString *, NSArray<NSString *> *> *MSBDExValues(NSString *choice) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < kMSBDExclusiveCount; i++) if ([choice isEqualToString:@(kMSBDExclusive[i].choice)]) out[@(kMSBDExclusive[i].value)] = MSBDExLibs(choice, @(kMSBDExclusive[i].value));
    return out;
}
// ... value -> its package, where the table names one.
static inline NSDictionary<NSString *, NSString *> *MSBDExPackages(NSString *choice) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < kMSBDExclusiveCount; i++) if ([choice isEqualToString:@(kMSBDExclusive[i].choice)] && kMSBDExclusive[i].package) out[@(kMSBDExclusive[i].value)] = @(kMSBDExclusive[i].package);
    return out;
}
// Every library of the table: the only entries a record of ours may name, and the only ones a give-back touches.
static inline NSArray<NSString *> *MSBDExAllLibs(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (size_t i = 0; i < kMSBDExclusiveCount; i++) for (size_t k = 0; k < 3 && kMSBDExclusive[i].libs[k]; k++) [out addObject:@(kMSBDExclusive[i].libs[k])];
    return out;
}
// A library's option in words ("MilkyWay3SubModule" is MilkyWay4), nil for a library not in the table.
static inline NSString *MSBDExNameOf(NSString *lib) {
    for (size_t i = 0; i < kMSBDExclusiveCount; i++) for (size_t k = 0; k < 3 && kMSBDExclusive[i].libs[k]; k++)
        if ([lib isEqualToString:@(kMSBDExclusive[i].libs[k])]) return @(kMSBDExclusive[i].name);
    return nil;
}

// ---- Choicy's lists, recorded --------------------------------------------------------------------------------------------------------------
// One change in the record: two opposite changes cancel out (back to the user's own state).
static inline void MSBDExRecordChange(NSMutableDictionary *record, NSString *listKey, NSString *entry, BOOL added) {
    NSMutableDictionary *l = [record[listKey] isKindOfClass:[NSDictionary class]] ? [record[listKey] mutableCopy] : [NSMutableDictionary dictionary];
    NSString *before = l[entry];
    if ((added && [before isEqual:@"removed"]) || (!added && [before isEqual:@"added"])) [l removeObjectForKey:entry];
    else l[entry] = added ? @"added" : @"removed";
    if (l.count) record[listKey] = l; else [record removeObjectForKey:listKey];
}
static inline BOOL MSBDExSetMembership(NSMutableArray *list, NSArray *add, NSArray *remove, NSString *listKey, NSMutableDictionary *record) {
    BOOL changed = NO;
    for (NSString *n in add) if (![list containsObject:n]) { [list addObject:n]; changed = YES; MSBDExRecordChange(record, listKey, n, YES); }
    for (NSString *n in remove) if ([list containsObject:n]) { while ([list containsObject:n]) [list removeObject:n]; changed = YES; MSBDExRecordChange(record, listKey, n, NO); }
    return changed;
}
// Choicy's allow/deny mode for SpringBoard's own list: 1 (allow list) or 2 (deny list); missing = 1; anything else = 0 (unknown: left alone).
static inline NSInteger MSBDExChoicyMode(NSDictionary *sb) {
    id m = [sb isKindOfClass:[NSDictionary class]] ? sb[@"allowDenyMode"] : nil;
    if (!m) return 1;
    if (![m isKindOfClass:[NSNumber class]]) return 0;
    NSInteger v = [m integerValue];
    return (v == 1 || v == 2) ? v : 0;
}
// Choicy's settings (prefs, changed in place) so that `keep` loads and `deny` does not: its global list, and SpringBoard's own list where that is
// in force (an allow list keeps `keep` listed; a deny list takes `keep` out, and lists `deny` only where it overrides the global list). takeBack:
// libraries not installed any more -- an entry of ours for one is taken out of the global list again. Every change goes into the record. log: what
// was done, for the helper's log (may be nil). YES if Choicy's settings changed.
static inline BOOL MSBDExChoicyApply(NSMutableDictionary *prefs, NSMutableDictionary *record, NSArray *keep, NSArray *deny, NSArray *takeBack, NSMutableArray *log) {
    NSMutableArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? [prefs[@"globalDeniedTweaks"] mutableCopy] : [NSMutableArray array];
    BOOL changed = MSBDExSetMembership(global, deny, keep, @"globalDeniedTweaks", record);
    NSDictionary *ours = [record[@"globalDeniedTweaks"] isKindOfClass:[NSDictionary class]] ? record[@"globalDeniedTweaks"] : @{};
    NSMutableArray *undo = [NSMutableArray array];
    for (NSString *n in takeBack) if ([ours[n] isEqual:@"added"] && [global containsObject:n]) [undo addObject:n];
    if (undo.count && MSBDExSetMembership(global, @[], undo, @"globalDeniedTweaks", record)) {
        changed = YES;
        [log addObject:[NSString stringWithFormat:@"not installed, our entries taken out again: %@", [undo componentsJoinedByString:@", "]]];
    }
    prefs[@"globalDeniedTweaks"] = global;
    NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
    NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
    if (![sb[@"customTweakConfigurationEnabled"] boolValue]) return changed;
    NSInteger mode = MSBDExChoicyMode(sb);
    if (!mode) { [log addObject:@"Choicy's SpringBoard mode is unknown -- its SpringBoard list left as it is"]; return changed; }
    NSString *listKey = mode == 2 ? @"deniedTweaks" : @"allowedTweaks";
    NSMutableArray *list = [sb[listKey] isKindOfClass:[NSArray class]] ? [sb[listKey] mutableCopy] : [NSMutableArray array];
    NSString *rk = [@"springboard." stringByAppendingString:listKey];
    BOOL c = mode == 2 ? MSBDExSetMembership(list, [sb[@"overwriteGlobalTweakConfiguration"] boolValue] ? deny : @[], keep, rk, record)
                       : MSBDExSetMembership(list, keep, deny, rk, record);
    if (c) { sb[listKey] = list; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps; changed = YES; }
    return changed;
}
// What Choicy's settings say of these libraries -- each one's place in the global list and in SpringBoard's own lists --, comparable: what loads
// changed for them when this did. (Not our record: an entry of ours the user took out of Choicy and the helper put back is the same record and a
// different list -- the start's respring question must still come, sshtoggled ChoicyApplyChoices.)
static inline NSString *MSBDExChoicyEntriesOf(NSDictionary *prefs, NSArray<NSString *> *libs) {
    NSArray *global = [prefs[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? prefs[@"globalDeniedTweaks"] : @[];
    NSDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? prefs[@"appSettings"] : nil;
    NSDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? apps[@"com.apple.springboard"] : nil;
    NSArray *allowed = [sb[@"allowedTweaks"] isKindOfClass:[NSArray class]] ? sb[@"allowedTweaks"] : @[], *denied = [sb[@"deniedTweaks"] isKindOfClass:[NSArray class]] ? sb[@"deniedTweaks"] : @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *l in libs) [out addObject:[NSString stringWithFormat:@"%@ %d%d%d", l, [global containsObject:l], [allowed containsObject:l], [denied containsObject:l]]];
    return [out componentsJoinedByString:@","];
}
// One of the lists a record names, from prefs (mutable, stored back into prefs): "globalDeniedTweaks" or "springboard.<key>"; nil when not there
// (and not to be made).
static inline NSMutableArray *MSBDExChoicyList(NSMutableDictionary *prefs, NSString *listKey, BOOL create) {
    if ([listKey isEqualToString:@"globalDeniedTweaks"]) {
        NSMutableArray *l = [prefs[listKey] isKindOfClass:[NSArray class]] ? [prefs[listKey] mutableCopy] : (create ? [NSMutableArray array] : nil);
        if (l) prefs[listKey] = l;
        return l;
    }
    NSString *key = [listKey hasPrefix:@"springboard."] ? [listKey substringFromIndex:12] : nil;
    if (!key) return nil;
    NSMutableDictionary *apps = [prefs[@"appSettings"] isKindOfClass:[NSDictionary class]] ? [prefs[@"appSettings"] mutableCopy] : nil;
    NSMutableDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? [apps[@"com.apple.springboard"] mutableCopy] : nil;
    if (!sb) return nil;
    NSMutableArray *l = [sb[key] isKindOfClass:[NSArray class]] ? [sb[key] mutableCopy] : (create ? [NSMutableArray array] : nil);
    if (!l) return nil;
    sb[key] = l; apps[@"com.apple.springboard"] = sb; prefs[@"appSettings"] = apps;
    return l;
}
// The give-back (a switch-off, the removal): every change the record names undone in prefs, for the table's libraries only and only where the entry
// is still as we left it. Returns what was done, a line each.
static inline NSArray<NSString *> *MSBDExChoicyUndo(NSMutableDictionary *prefs, NSDictionary *record) {
    NSMutableArray *log = [NSMutableArray array];
    NSArray *libs = MSBDExAllLibs();
    for (NSString *listKey in record) {
        NSDictionary *entries = [record[listKey] isKindOfClass:[NSDictionary class]] ? record[listKey] : nil;
        for (NSString *entry in entries) {
            if (![libs containsObject:entry]) { [log addObject:[NSString stringWithFormat:@"%@ %@: not one of the choices' libraries -- left alone", listKey, entry]]; continue; }
            NSString *did = entries[entry];
            NSMutableArray *l = MSBDExChoicyList(prefs, listKey, [did isEqual:@"removed"]);
            BOOL present = [l containsObject:entry];
            if ([did isEqual:@"added"]) {
                if (present) { while ([l containsObject:entry]) [l removeObject:entry]; [log addObject:[NSString stringWithFormat:@"%@: removed %@ (we had added it)", listKey, entry]]; }
                else [log addObject:[NSString stringWithFormat:@"%@: %@ already gone -- left as the user has it", listKey, entry]];
            } else if ([did isEqual:@"removed"]) {
                if (!present && l) { [l addObject:entry]; [log addObject:[NSString stringWithFormat:@"%@: added %@ back (we had removed it)", listKey, entry]]; }
                else [log addObject:[NSString stringWithFormat:@"%@: %@ is back already -- left as the user has it", listKey, entry]];
            }
        }
    }
    return log;
}
// The give-back of some libraries only, the rest of our entries kept: MSBDExChoicyUndo for `libs`, and their entries taken out of the record (not
// ours any more, undone or left as the user has them; a list left with none goes). A downgrade to a version before 1.8.0 gives back BigSurCenter's
// and Destra's (the older version knows only the engines' entries and goes on managing them: sshtoggled --giveback-styles), safe mode and an
// untested iPadOS every library's (sshtoggled ApplyEngines). Returns what was done, a line each.
static inline NSArray<NSString *> *MSBDExChoicyUndoOnly(NSMutableDictionary *prefs, NSMutableDictionary *record, NSArray<NSString *> *libs) {
    NSMutableDictionary *given = [NSMutableDictionary dictionary];
    for (NSString *listKey in [record allKeys]) {
        NSDictionary *entries = [record[listKey] isKindOfClass:[NSDictionary class]] ? record[listKey] : nil;
        NSMutableDictionary *kept = [entries mutableCopy], *mine = [NSMutableDictionary dictionary];
        for (NSString *entry in entries) if ([libs containsObject:entry]) { mine[entry] = entries[entry]; [kept removeObjectForKey:entry]; }
        if (!mine.count) continue;
        given[listKey] = mine;
        if (kept.count) record[listKey] = kept; else [record removeObjectForKey:listKey];
    }
    return MSBDExChoicyUndo(prefs, given);
}
// The user switched lib off themselves, not us: in Choicy's global list without an "added" of ours; in SpringBoard's own list where Choicy's
// custom configuration for SpringBoard is on -- named in its deny list (mode 2) without an "added" of ours, or left out of its allow list (mode 1)
// without a "removed" of ours: BigSurCenter and Destra load only in SpringBoard, so that is where a user turns them off, and the update took it as
// not off and switched BigSurCenter back on (code review 1.8.0, 2; an unknown mode says nothing, as MSBDExChoicyApply leaves that list alone) --;
// or iCleaner Pro's .disabled (and no .dylib) without our rename. choicy, record: Choicy's settings and our record (nil: none); renamed: the helper's
// renames; dylib / disabled: which of <lib>.dylib and <lib>.disabled are in TweakInject.
static inline BOOL MSBDExUserOff(NSString *lib, NSDictionary *choicy, NSDictionary *record, NSArray<NSString *> *renamed, BOOL dylib, BOOL disabled) {
    NSArray *denied = [choicy isKindOfClass:[NSDictionary class]] && [choicy[@"globalDeniedTweaks"] isKindOfClass:[NSArray class]] ? choicy[@"globalDeniedTweaks"] : @[];
    NSDictionary *ours = [record isKindOfClass:[NSDictionary class]] && [record[@"globalDeniedTweaks"] isKindOfClass:[NSDictionary class]] ? record[@"globalDeniedTweaks"] : @{};
    if ([denied containsObject:lib] && ![ours[lib] isEqual:@"added"]) return YES;
    NSDictionary *apps = [choicy isKindOfClass:[NSDictionary class]] && [choicy[@"appSettings"] isKindOfClass:[NSDictionary class]] ? choicy[@"appSettings"] : nil;
    NSDictionary *sb = [apps[@"com.apple.springboard"] isKindOfClass:[NSDictionary class]] ? apps[@"com.apple.springboard"] : nil;
    id custom = sb[@"customTweakConfigurationEnabled"];
    NSInteger mode = [custom respondsToSelector:@selector(boolValue)] && [custom boolValue] ? MSBDExChoicyMode(sb) : 0;   // (SpringBoard reads this too: no exception on odd values)
    if (mode) {
        NSString *listKey = mode == 2 ? @"deniedTweaks" : @"allowedTweaks";
        NSArray *list = [sb[listKey] isKindOfClass:[NSArray class]] ? sb[listKey] : @[];
        id rec = [record isKindOfClass:[NSDictionary class]] ? record[[@"springboard." stringByAppendingString:listKey]] : nil;
        NSDictionary *sbOurs = [rec isKindOfClass:[NSDictionary class]] ? rec : @{};
        if (mode == 2 ? ([list containsObject:lib] && ![sbOurs[lib] isEqual:@"added"]) : (![list containsObject:lib] && ![sbOurs[lib] isEqual:@"removed"])) return YES;
    }
    if (!dylib && disabled && ![renamed containsObject:lib]) return YES;
    return NO;
}
// An engine's library may be the engines' default (sshtoggled EngineToKeep, when no engine is picked): there to load -- its .dylib, or a .disabled
// (iCleaner Pro's: ours, or the user's) -- and not switched off by the user, by the same reader as Control Center Style's BigSurCenter (above). The
// default had its own copy of the rule, which read Choicy's global list and iCleaner Pro only: an engine switched off for SpringBoard alone (Choicy's
// custom configuration) could be made the default and loaded anyway (code review 1.8.0, note a; 1.8.1 item 3).
static inline BOOL MSBDExEngineCanBeDefault(NSString *lib, NSDictionary *choicy, NSDictionary *record, NSArray<NSString *> *renamed, BOOL dylib, BOOL disabled) {
    return (dylib || disabled) && !MSBDExUserOff(lib, choicy, record, renamed, dylib, disabled);
}
// The helper's record of its renames (one library a line; only the table's libraries count).
static inline NSArray<NSString *> *MSBDExRenamesIn(NSString *text) {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *libs = MSBDExAllLibs();
    for (NSString *l in [text componentsSeparatedByString:@"\n"]) if (l.length && [libs containsObject:l] && ![out containsObject:l]) [out addObject:l];
    return out;
}

// ---- the readers (Settings and SpringBoard as mobile, the root helper as root: the same files) --------------------------------------------------
// <lib>.dylib / <lib>.disabled in TweakInject (MobileSubstrate's DynamicLibraries is the same folder).
static inline BOOL MSBDExLibraryFile(NSString *lib, NSString *ext) {
    return [[NSFileManager defaultManager] fileExistsAtPath:[[kMSBDExTweakDir stringByAppendingPathComponent:lib] stringByAppendingPathExtension:ext]];
}
// Installed: its .dylib, or iCleaner Pro's .disabled.
static inline BOOL MSBDExInstalled(NSString *lib) { return MSBDExLibraryFile(lib, @"dylib") || MSBDExLibraryFile(lib, @"disabled"); }
// The user switched it off themselves, read from the files.
static inline BOOL MSBDExUserOffNow(NSString *lib) {
    NSDictionary *choicy = [NSDictionary dictionaryWithContentsOfFile:kMSBDExChoicyPrefs], *record = [NSDictionary dictionaryWithContentsOfFile:kMSBDExChoicyRecord];
    NSString *renames = [NSString stringWithContentsOfFile:kMSBDExRenameRecord encoding:NSUTF8StringEncoding error:nil];
    return MSBDExUserOff(lib, choicy, record, MSBDExRenamesIn(renames ?: @""), MSBDExLibraryFile(lib, @"dylib"), MSBDExLibraryFile(lib, @"disabled"));
}
