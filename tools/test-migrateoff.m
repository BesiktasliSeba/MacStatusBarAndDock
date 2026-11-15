// test-migrateoff.m -- Mac test of the move from the old separate packages' on/off entries (1.8.7.5, audit L106 of 1.8.7.2): the old
// MacStatusBarToggle / DockMagnificationToggle wrote tweakEnabled = NO, which the parts still read but no Settings page shows; the migration
// switches that line off the way Choicy (or iCleaner Pro) does and clears tweakEnabled. With Choicy installed but never configured (no settings
// file yet) it left the part off the old way, for good, while Settings showed it on; and a device migrated so before 1.8.7.5 kept it behind the
// "migrated" marker, so the move is looked at again at every later install. Run on the real move (MigrateOldOnOff, onoff.inc), the real Migrate
// (migrate.inc), both cut out of sshtoggled's main.m by tools/test-migrateoff.sh, and its RecordLineChange, with stand-ins for what they ask of the
// system: Choicy installed or not, mobile's preferences (cfprefsd), the writes as mobile, the log, the notification, the rest of the migration.
// Choicy's file, our record and the migration's folder are in a scratch folder (MO_DIR).
#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include <unistd.h>

// ---- stand-ins ----
static NSMutableDictionary<NSString *, NSMutableDictionary *> *gPrefs;   // (mobile's preferences: domain -> keys, as cfprefsd has them)
static BOOL gChoicy = YES, gSane = NO;
static int gAsMobile = 0, gNotified = 0;   // (gAsMobile: the calls of AsMobile that wrote a file -- Choicy's or the record)
static NSMutableArray<NSString *> *gLog;
static CFPropertyListRef TCopy(NSString *k, NSString *d) { id v = gPrefs[d][k]; return v ? CFBridgingRetain(v) : NULL; }
#define CFPreferencesSynchronize(d, u, h) ((void)(d))
#define CFPreferencesCopyValue(k, d, u, h) TCopy((__bridge NSString *)(k), (__bridge NSString *)(d))
#define notify_post(n) (gNotified++)
static void ELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ELog(NSString *fmt, ...) { va_list ap; va_start(ap, fmt); [gLog addObject:[[NSString alloc] initWithFormat:fmt arguments:ap]]; va_end(ap); }
static NSString *DpkgStatus(void) { return @""; }
static BOOL ChoicyInstalled(NSString *status) { return gChoicy; }
static BOOL TweakFolderIsSane(void) { return gSane; }
static BOOL IsRegular(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode); }
static BOOL Exists(NSString *path) { struct stat st; return lstat(path.fileSystemRepresentation, &st) == 0; }
static NSString *Stamp(void);
static BOOL AsMobile(BOOL (^work)(void)) { NSString *b = Stamp(); BOOL ok = work(); if (![Stamp() isEqualToString:b]) gAsMobile++; return ok; }
static BOOL WriteMobilePrefsKey(NSString *domain, NSString *key, id value, BOOL onlyIfAbsent) {
    if (!gPrefs[domain]) gPrefs[domain] = [NSMutableDictionary dictionary];
    if (gPrefs[domain][key] && onlyIfAbsent) return NO;
    gPrefs[domain][key] = value;
    return YES;
}
#define CHOICYPREFS MO_DIR "/com.opa334.choicyprefs.plist"
#define LINERECORD MO_DIR "/MacStatusBar-LineChanges.plist"
#define TWEAKDIR MO_DIR "/TweakInject"
static NSString *Stamp(void) {   // (Choicy's file and the record as they are on disk: an atomic write gives a new inode)
    NSMutableString *out = [NSMutableString string];
    for (NSString *f in @[@CHOICYPREFS, @LINERECORD]) {
        struct stat st;
        if (lstat(f.fileSystemRepresentation, &st) != 0) [out appendString:@"none/"];
        else [out appendFormat:@"%llu.%ld.%ld/", (unsigned long long)st.st_ino, (long)st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec];
    }
    return out;
}
#include "reader.inc"   // (the helper's reader of mobile's files, where the code has one: test-mobilereads.sh tests it)
#include "record.inc"
#define MIGDIR MO_DIR "/mig"
static int gMigSteps = 0;   // (the rest of the move from the old packages: done only at a first migration)
static void MigratePrefFiles(void) { gMigSteps++; }
static NSSet<NSString *> *MigrateChoicy(void) { gMigSteps++; return [NSSet set]; }
static NSSet<NSString *> *MigrateICleaner(void) { gMigSteps++; return [NSSet set]; }
static NSDictionary<NSString *, NSArray *> *MigSmallFeatures(void) { return @{}; }
#include "onoff.inc"     // (MigrateOldOnOff: the move of the old on/off entries; for the code before, its loop cut out of Migrate)
#include "migrate.inc"   // (the real Migrate)
static void OldOnOff(void) { MigrateOldOnOff(); }
static void Marked(void) {   // (a device migrated before: the "migrated" marker there)
    [[NSFileManager defaultManager] createDirectoryAtPath:@MIGDIR withIntermediateDirectories:YES attributes:nil error:nil];
    [@"1" writeToFile:@MIGDIR "/migrated" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static int gN = 0, gFail = 0;
static void Expect(BOOL ok, NSString *what) { gN++; if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } else printf("  ok   %s\n", what.UTF8String); }
static void Reset(NSDictionary *msb, NSDictionary *dock) {
    [[NSFileManager defaultManager] removeItemAtPath:@MO_DIR error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:@MO_DIR withIntermediateDirectories:YES attributes:nil error:nil];
    gPrefs = [NSMutableDictionary dictionary];
    if (msb) gPrefs[@"com.besiktasliseba.macstatusbar"] = [msb mutableCopy];
    if (dock) gPrefs[@"com.besiktasliseba.dockmagnification"] = [dock mutableCopy];
    gChoicy = YES; gSane = NO; gAsMobile = 0; gNotified = 0; gMigSteps = 0; gLog = [NSMutableArray array];
}
static NSDictionary *File(const char *p) { return [NSDictionary dictionaryWithContentsOfFile:@(p)]; }
static BOOL Logged(NSString *s) { for (NSString *l in gLog) if ([l containsString:s]) return YES; return NO; }
static id Pref(NSString *d, NSString *k) { return gPrefs[d][k]; }
#define MSB @"com.besiktasliseba.macstatusbar"
#define DOCK @"com.besiktasliseba.dockmagnification"

int main(void) {
    @autoreleasepool {
        printf("Choicy installed, never configured (no settings file), both parts switched off the old way:\n");
        Reset(@{@"tweakEnabled": @NO, @"windowEngine": @"aerial"}, @{@"tweakEnabled": @NO});
        OldOnOff();
        NSDictionary *c = File(CHOICYPREFS), *r = File(LINERECORD);
        Expect([c isEqual:(@{@"preferenceVersion": @1, @"globalDeniedTweaks": @[@"MacStatusBar", @"MacDock"]})], @"Choicy's settings file made: both lines switched off in its global list, preferenceVersion 1");
        Expect([r isEqual:(@{@"globalDeniedTweaks": @{@"MacStatusBar": @"added", @"MacDock": @"added"}})], @"  ... both recorded as ours (\"added\"): the removal takes them out again");
        Expect(!Pref(MSB, @"tweakEnabled") && !Pref(DOCK, @"tweakEnabled") && [Pref(MSB, @"windowEngine") isEqual:@"aerial"], @"  ... tweakEnabled gone from both domains, the rest kept");
        Expect(gAsMobile == 2 && gNotified == 2, @"  ... written as mobile, Choicy told (each line)");
        Expect(Logged(@"migrate: com.besiktasliseba.macstatusbar was switched off with the old on/off entry -> MacStatusBar switched off in Choicy / iCleaner Pro instead")
               && Logged(@"-> MacDock switched off in Choicy / iCleaner Pro instead") && !Logged(@"left switched off the old way"), @"  ... logged as switched off in Choicy, nothing left the old way");

        printf("no settings file, only the Dock switched off the old way:\n");
        Reset(@{@"tweakEnabled": @YES}, @{@"tweakEnabled": @NO});
        OldOnOff();
        Expect([File(CHOICYPREFS) isEqual:(@{@"preferenceVersion": @1, @"globalDeniedTweaks": @[@"MacDock"]})]
               && [File(LINERECORD) isEqual:(@{@"globalDeniedTweaks": @{@"MacDock": @"added"}})], @"only MacDock in Choicy's new file, and recorded");
        Expect([Pref(MSB, @"tweakEnabled") isEqual:@YES] && !Pref(DOCK, @"tweakEnabled"), @"  ... the Dock's tweakEnabled gone, Mac Status Bar's on as it was");

        printf("no settings file, nothing switched off the old way (as before):\n");
        Reset(@{@"tweakEnabled": @YES}, nil);
        OldOnOff();
        Expect(access(CHOICYPREFS, F_OK) != 0 && access(LINERECORD, F_OK) != 0 && gAsMobile == 0, @"no Choicy file made, no record, nothing written");
        Reset(@{@"tweakEnabled": @0}, @{@"tweakEnabled": @"NO"});
        OldOnOff();
        Expect(access(CHOICYPREFS, F_OK) != 0 && [Pref(MSB, @"tweakEnabled") isEqual:@0], @"  ... a tweakEnabled that is no boolean is not the old switch-off: nothing done");

        printf("a settings file that is there but can't be read (as before):\n");
        Reset(@{@"tweakEnabled": @NO}, nil);
        NSData *junk = [NSData dataWithBytes:"\x00\x01not a plist" length:13];
        [junk writeToFile:@CHOICYPREFS atomically:NO];
        OldOnOff();
        Expect([[NSData dataWithContentsOfFile:@CHOICYPREFS] isEqual:junk] && access(LINERECORD, F_OK) != 0, @"left as it is, no record written");
        Expect([Pref(MSB, @"tweakEnabled") isEqual:@NO] && Logged(@"left switched off the old way"), @"  ... the part stays switched off the old way (said so)");
        Reset(@{@"tweakEnabled": @NO}, nil);
        [@[@"MacStatusBar"] writeToFile:@CHOICYPREFS atomically:YES];
        OldOnOff();
        Expect([File(CHOICYPREFS) isKindOfClass:[NSDictionary class]] == NO && [[NSArray arrayWithContentsOfFile:@CHOICYPREFS] isEqual:@[@"MacStatusBar"]] && [Pref(MSB, @"tweakEnabled") isEqual:@NO],
               @"  ... one that is no dictionary: left too");

        printf("an existing settings file (as before):\n");
        Reset(@{@"tweakEnabled": @NO}, nil);
        NSDictionary *mine = @{@"preferenceVersion": @1, @"globalDeniedTweaks": @[@"Zetsu"], @"appSettings": @{@"com.apple.mobilesafari": @{@"tweakInjectionDisabled": @YES}}};
        [mine writeToFile:@CHOICYPREFS atomically:YES];
        OldOnOff();
        Expect([File(CHOICYPREFS) isEqual:(@{@"preferenceVersion": @1, @"globalDeniedTweaks": @[@"Zetsu", @"MacStatusBar"], @"appSettings": @{@"com.apple.mobilesafari": @{@"tweakInjectionDisabled": @YES}}})],
               @"MacStatusBar added to the user's global list, everything else kept");
        Expect([File(LINERECORD) isEqual:(@{@"globalDeniedTweaks": @{@"MacStatusBar": @"added"}})] && !Pref(MSB, @"tweakEnabled") && !Logged(@"no settings file yet"),
               @"  ... recorded, tweakEnabled gone, no \"no settings file\" line");
        Reset(@{@"tweakEnabled": @NO}, nil);
        [@{@"globalDeniedTweaks": @[@"MacStatusBar"]} writeToFile:@CHOICYPREFS atomically:YES];
        [@{@"globalDeniedTweaks": @{@"MacDock": @"added"}} writeToFile:@LINERECORD atomically:YES];
        OldOnOff();
        Expect([File(CHOICYPREFS)[@"globalDeniedTweaks"] isEqual:@[@"MacStatusBar"]] && [File(LINERECORD) isEqual:(@{@"globalDeniedTweaks": @{@"MacDock": @"added"}})] && !Pref(MSB, @"tweakEnabled"),
               @"  ... already listed by the user: not added twice, not recorded as ours, tweakEnabled gone");

        printf("Choicy not installed (as before):\n");
        Reset(@{@"tweakEnabled": @NO}, nil);
        gChoicy = NO;
        OldOnOff();
        Expect(access(CHOICYPREFS, F_OK) != 0 && [Pref(MSB, @"tweakEnabled") isEqual:@NO], @"no Choicy file made; without a sane tweak folder the part stays off the old way");
        Reset(@{@"tweakEnabled": @NO}, nil);
        gChoicy = NO; gSane = YES;
        [[NSFileManager defaultManager] createDirectoryAtPath:@TWEAKDIR withIntermediateDirectories:YES attributes:nil error:nil];
        [@"x" writeToFile:@TWEAKDIR "/MacStatusBar.dylib" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        OldOnOff();
        Expect(IsRegular(@TWEAKDIR "/MacStatusBar.disabled") && !Exists(@TWEAKDIR "/MacStatusBar.dylib") && !Pref(MSB, @"tweakEnabled") && access(CHOICYPREFS, F_OK) != 0,
               @"  ... iCleaner Pro's way: MacStatusBar.dylib renamed to .disabled, tweakEnabled gone, no Choicy file");

        printf("an update on a device migrated before (its \"migrated\" marker there), Choicy with no settings file, the Dock left off the old way:\n");
        Reset(@{@"tweakEnabled": @YES}, @{@"tweakEnabled": @NO});
        Marked();
        Migrate();
        Expect([File(CHOICYPREFS) isEqual:(@{@"preferenceVersion": @1, @"globalDeniedTweaks": @[@"MacDock"]})] && [File(LINERECORD) isEqual:(@{@"globalDeniedTweaks": @{@"MacDock": @"added"}})]
               && !Pref(DOCK, @"tweakEnabled") && [Pref(MSB, @"tweakEnabled") isEqual:@YES], @"moved now: MacDock switched off in Choicy's new file and recorded, the Dock's tweakEnabled gone");
        Expect(gMigSteps == 0 && Logged(@"migrate: done before -- nothing") && !Logged(@"migrate: finished") && Exists(@MIGDIR "/migrated"),
               @"  ... nothing else of the move from the old packages done again, the marker kept");
        NSString *was = Stamp(); int writes = gAsMobile, notes = gNotified;
        Migrate();
        Expect([Stamp() isEqualToString:was] && gAsMobile == writes && gNotified == notes && gMigSteps == 0, @"  ... the next update: nothing left, nothing written");

        printf("an update on a device migrated before, nothing left switched off the old way:\n");
        Reset(@{@"tweakEnabled": @YES, @"windowEngine": @"stage"}, nil);
        Marked();
        Migrate();
        Expect(access(CHOICYPREFS, F_OK) != 0 && access(LINERECORD, F_OK) != 0 && gAsMobile == 0 && gNotified == 0 && gMigSteps == 0 && [Pref(MSB, @"tweakEnabled") isEqual:@YES],
               @"no Choicy file made, nothing written, nothing else done");
        Reset(nil, nil);
        Marked();
        [mine writeToFile:@CHOICYPREFS atomically:YES];
        was = Stamp();
        Migrate();
        Expect([Stamp() isEqualToString:was] && [File(CHOICYPREFS) isEqual:mine] && gAsMobile == 0, @"  ... the user's Choicy file untouched");

        printf("a first migration (no marker yet), as before, and the next update:\n");
        Reset(@{@"tweakEnabled": @NO}, nil);
        Migrate();
        Expect(gMigSteps == 3 && Exists(@MIGDIR "/migrated") && Logged(@"migrate: finished") && [File(CHOICYPREFS)[@"globalDeniedTweaks"] isEqual:@[@"MacStatusBar"]] && !Pref(MSB, @"tweakEnabled"),
               @"the whole move: Mac Status Bar switched off in Choicy, tweakEnabled gone, the marker written");
        was = Stamp(); writes = gAsMobile;
        Migrate();
        Expect([Stamp() isEqualToString:was] && gAsMobile == writes && gMigSteps == 3, @"  ... the next update: nothing done again");
    }
    [[NSFileManager defaultManager] removeItemAtPath:@MO_DIR error:nil];
    printf("test-migrateoff (compiled): %d checks, %d failed\n", gN, gFail);
    return gFail ? 1 : 0;
}
