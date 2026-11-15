// test-menubarsizeguard.m -- Menu Bar Size and the crash guard's step 1 (1.8.7.5, audit L62 of 1.8.7.2), for tools/test-menubarsizeguard.sh.
// The real Menu Bar Size branch of -[MSBRootListController setPreferenceValue:specifier:] and MSBMenuBarSizeStored (Settings' reader), SpringBoard's
// reader DMBarSizeStored (StatusBar.x), LineSwitch.h's MSBDNoteSwitch (all cut out by the script, Mac Status Bar's domain made a test one) and the
// real guard's step 1 (CrashGuard.h MSBDGuardSwitchOffRecent) on a scratch RecentlyOn list (MSBD_GUARD_RECENT). A stand-in for the list
// controller's own store (PSListController's -setPreferenceValue:specifier:: the value into the domain) and its respring offer. Review of 1.8.7.5:
// LineSwitch.h's -msbd_guardNoteMaybeGone (cut out by the script) on a stand-in page (its rows by id), after a size pick that ends the guard's note.
#ifndef MSBD_TEST_EXPLAIN_H
#define MSBD_TEST_EXPLAIN_H "../common/CrashExplain.h"
#endif
#import MSBD_TEST_EXPLAIN_H
#include "../common/MenuBarSize.h"
#define MSBD_DOMAIN CFSTR("com.besiktasliseba.macstatusbaranddock")   // (LineSwitch.h's)
#include MSBD_TEST_LINESWITCH_CUT   // (MSBDGuardAction ... MSBDNoteSwitch)
#include MSBD_TEST_SIZE_STORED      // (Settings: MSBMenuBarSizeStored)
#include MSBD_TEST_SB_STORED        // (SpringBoard: DMBarSizeStored)
#define TDOM "com.besiktasliseba.test-menubarsizeguard"
@interface SizeSpec : NSObject
- (id)propertyForKey:(NSString *)key;
@end
@implementation SizeSpec
- (id)propertyForKey:(NSString *)key { return [key isEqualToString:@"key"] ? @kMSBDMenuBarSizeKey : nil; }
@end
@interface SizeListBase : NSObject
- (void)setPreferenceValue:(id)value specifier:(id)specifier;
@end
@implementation SizeListBase
- (void)setPreferenceValue:(id)value specifier:(id)specifier {   // (as PSListController: the value into the row's domain)
    CFPreferencesSetValue(CFSTR(kMSBDMenuBarSizeKey), (__bridge CFPropertyListRef)value, CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
@end
@interface SizeList : SizeListBase
@property int offered;   // (the respring offered for this size; -1 none)
@property NSMutableSet<NSString *> *shown;   // (the page's rows by id: the guard's footer group, its buttons)
@property int untestedReloads;
- (void)msbd_guardNoteMaybeGone;
@end
@implementation SizeList
- (void)msb_menuBarSizeChanged:(int)size { self.offered = size; }
- (id)specifierForID:(NSString *)ident { return [self.shown containsObject:ident] ? ident : nil; }   // (PSListController's, on the stand-in rows)
- (void)removeSpecifierID:(NSString *)ident animated:(BOOL)animated { [self.shown removeObject:ident]; }
- (void)msbd_reloadUntestedFooter { self.untestedReloads++; }
#include MSBD_TEST_PAGE_REFRESH
- (void)setPreferenceValue:(id)value specifier:(SizeSpec *)specifier {
#include MSBD_TEST_SIZE_BRANCH
}
@end
static int fails = 0, total = 0;
static void Check(NSString *what, BOOL ok, NSString *got) {
    total++; if (!ok) fails++;
    printf("%s  %s%s%s\n", ok ? "PASS" : "FAIL", what.UTF8String, got ? "\n      " : "", got ? got.UTF8String : "");
}
static NSString *Recent(void) { return [NSString stringWithContentsOfFile:@MSBD_GUARD_RECENT encoding:NSUTF8StringEncoding error:nil] ?: @""; }
static long NoteTime(int *lines) {   // the RecentlyOn line of Menu Bar Size: its time (-1: none), and how many there are
    long t = -1; int n = 0;
    for (NSString *l in [Recent() componentsSeparatedByString:@"\n"])
        if ([l hasSuffix:@" " TDOM " menuBarSize Menu Bar Size"]) { t = (long)[l longLongValue]; n++; }
    if (lines) *lines = n;
    return t;
}
static BOOL StoredFalse(void) {
    CFPreferencesSynchronize(CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR(kMSBDMenuBarSizeKey), CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL f = v && CFGetTypeID(v) == CFBooleanGetTypeID() && !CFBooleanGetValue(v);
    if (v) CFRelease(v);
    return f;
}
static int Stored(void) { CFPreferencesSynchronize(CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost); return MSBMenuBarSizeStored(); }
static void SetNote(int action) {
    CFPreferencesSetValue(CFSTR(MSBD_GUARD_ACTION_KEY), action ? (__bridge CFNumberRef)@(action) : NULL, MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSBD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
static void RunMain(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]]; }   // (the page's dispatch_async to the main queue)
static NSString *Rows(NSSet *s) { return [[[s allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]; }
int main(void) {
    @autoreleasepool {
        if (MSBDGuardAction()) { printf("FAIL  the Mac has a crash guard note (crashGuardAction): not touching it\n"); return 1; }
        SizeList *c = [SizeList new]; SizeSpec *sp = [SizeSpec new];
        long now = (long)time(NULL); int lines = 0;
        c.offered = -1; [c setPreferenceValue:@2 specifier:sp];
        Check(@"Small -> Large: stored 2, the respring offered", Stored() == MSBDMenuBarLarge && c.offered == MSBDMenuBarLarge, nil);
        long t = NoteTime(&lines);
        Check(@"  noted for the crash guard as Menu Bar Size turned on (now)", lines == 1 && t >= now && t <= (long)time(NULL), Recent());
        char rec[1536] = "";
        int n = MSBDGuardSwitchOffRecent((long)time(NULL) - 120, rec, sizeof rec);
        Check(@"two crashes within 2 min: step 1 sets it back (one)", n == 1, @(rec));
        Check(@"  its record line names Menu Bar Size (the footer's words)", strstr(rec, "switch " TDOM " menuBarSize Menu Bar Size\n") != NULL, nil);
        Check(@"  stored false, as a switch's off", StoredFalse(), nil);
        Check(@"  read as Small by Settings (MSBMenuBarSizeStored) and by SpringBoard (DMBarSizeStored)", Stored() == MSBDMenuBarSmall && DMBarSizeStored() == MSBDMenuBarSmall, nil);
        Check(@"  the list used up", access(MSBD_GUARD_RECENT, F_OK) != 0, nil);
        c.offered = -1; [c setPreferenceValue:@1 specifier:sp];
        Check(@"from the guard's false (Small) -> Medium: stored 1, noted", Stored() == MSBDMenuBarMedium && NoteTime(&lines) >= now && lines == 1 && c.offered == MSBDMenuBarMedium, Recent());
        [[NSString stringWithFormat:@"%ld " TDOM " menuBarSize Menu Bar Size\n", (long)time(NULL) - 300] writeToFile:@MSBD_GUARD_RECENT atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [c setPreferenceValue:@2 specifier:sp];
        Check(@"Medium -> Large (the note 5 min old): noted again, now (step 1 looks 2 min back)", Stored() == MSBDMenuBarLarge && NoteTime(&lines) >= now && lines == 1, Recent());
        t = NoteTime(NULL);
        [c setPreferenceValue:@1 specifier:sp];
        Check(@"Large -> Medium: the note kept as it was (still larger than Small)", Stored() == MSBDMenuBarMedium && NoteTime(&lines) == t && lines == 1, Recent());
        [c setPreferenceValue:@0 specifier:sp];
        Check(@"Medium -> Small: the note taken out", Stored() == MSBDMenuBarSmall && NoteTime(&lines) == -1 && lines == 0, Recent());
        c.offered = -1; [c setPreferenceValue:@0 specifier:sp];
        Check(@"Small tapped again: nothing (no respring offered, nothing noted)", c.offered == -1 && NoteTime(NULL) == -1, nil);
        [c setPreferenceValue:@2 specifier:sp]; [c setPreferenceValue:@0 specifier:sp];
        Check(@"Small -> Large -> Small: no note left", NoteTime(NULL) == -1 && Stored() == MSBDMenuBarSmall, Recent());
        n = MSBDGuardSwitchOffRecent((long)time(NULL) - 120, rec, sizeof rec);
        Check(@"  step 1 then has nothing of it to set back", n == 0 && Stored() == MSBDMenuBarSmall && !StoredFalse(), @(rec));
        MSBDNoteSwitch(@TDOM, @"otherSwitch", @"Other Switch", NO, YES);
        [c setPreferenceValue:@2 specifier:sp]; [c setPreferenceValue:@0 specifier:sp];
        Check(@"Large -> Small takes out its own note only (another switch's stays)", NoteTime(NULL) == -1 && [Recent() containsString:@" " TDOM " otherSwitch Other Switch"], Recent());
        unlink(MSBD_GUARD_RECENT);
        CFPreferencesSetValue(CFSTR(kMSBDMenuBarSizeKey), NULL, CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Check(@"never set: Small (both readers)", MSBMenuBarSizeStored() == MSBDMenuBarSmall && DMBarSizeStored() == MSBDMenuBarSmall, nil);
        Check(@"the crash guard's note was never touched", MSBDGuardAction() == 0, nil);
        // (review of 1.8.7.5) a size pick that ends the guard's note (step 1's, on a tested iPadOS: a change on the page ends it, LineSwitch.h) takes
        // its footer and Report a Problem off the page at once, as a switch change does; with a part still off (L104) the note and its rows stay
        NSString *noteRec = [NSString stringWithFormat:@"time %ld\naction 1\ntested 1\nios 16.5\nbuild 1\nverdict 2\nblamed Apple_code_only\nswitch " TDOM " otherSwitch Other Switch\n", (long)time(NULL)];
        [noteRec writeToFile:@MSBD_GUARD_RECORD atomically:YES encoding:NSUTF8StringEncoding error:nil];
        SetNote(1);
        c.shown = [NSMutableSet setWithArray:@[@"MSBD_SAFE_GROUP", @"MSBD_GUARD_REPORT", @"OTHER_ROW"]];
        Check(@"(step 1's note on a tested iPadOS: its footer is on the page)", MSBDVersionTested() && MSBDGuardAction() == 1 && MSBDSafeModeFooter() != nil, MSBDSafeModeFooter());
        [c setPreferenceValue:@2 specifier:sp]; RunMain();
        Check(@"Small -> Large under step 1's note: the note ends, as with a switch change", MSBDGuardAction() == 0 && Stored() == MSBDMenuBarLarge, nil);
        Check(@"  ... and its footer and Report a Problem leave the page at once (the other rows stay)", [c.shown isEqualToSet:[NSSet setWithObject:@"OTHER_ROW"]], Rows(c.shown));
        [c setPreferenceValue:@0 specifier:sp]; RunMain();
        Check(@"  back to Small with no note: nothing else leaves", [c.shown isEqualToSet:[NSSet setWithObject:@"OTHER_ROW"]] && MSBDGuardAction() == 0, Rows(c.shown));
        [[noteRec stringByAppendingString:@"part DockMagnification the Dock|the Dock\n"] writeToFile:@MSBD_GUARD_RECORD atomically:YES encoding:NSUTF8StringEncoding error:nil];
        SetNote(1);
        c.shown = [NSMutableSet setWithArray:@[@"MSBD_SAFE_GROUP", @"MSBD_SAFE_ON", @"MSBD_GUARD_REPORT"]];
        [c setPreferenceValue:@2 specifier:sp]; RunMain();
        Check(@"step 1's note with a part still off: a size pick leaves the note and its rows (Turn Back On)", MSBDGuardAction() == 1 && c.shown.count == 3, Rows(c.shown));
        [c setPreferenceValue:@0 specifier:sp]; RunMain();
        Check(@"  ... back to Small too", MSBDGuardAction() == 1 && c.shown.count == 3 && c.untestedReloads == 0, Rows(c.shown));
        SetNote(0); unlink(MSBD_GUARD_RECORD); unlink(MSBD_GUARD_RECENT);
        CFPreferencesSetValue(CFSTR(kMSBDMenuBarSizeKey), NULL, CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(CFSTR(TDOM), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        Check(@"the test's note taken away again", MSBDGuardAction() == 0, nil);
    }
    printf("%d/%d passed\n", total - fails, total);
    return fails ? 1 : 0;
}
