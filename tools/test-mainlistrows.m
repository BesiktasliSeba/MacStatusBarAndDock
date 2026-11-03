// Mac test of where our rows go in Settings' main list (common/MainListRows.h; 1.7.9): the Status Bar, Desktop, Windows & Multitasking and Dock
// rows' places in the main lists of 15.6.1 and 17.5.1 as MacSettings logged them, the fallback near the top, the Accessibility section's group
// row -- a row whose identifier is not read (NSNull) never taken for any row -- and, on stand-ins for Settings' list and rows, the row Settings
// fills in on its loading queue (the list's -_appleAccountSpecifier) never read at all, the list read as it is now (its _specifiers).
#import <Foundation/Foundation.h>
#include "../common/MainListRows.h"
// A stand-in for a PSSpecifier: counts every read of its identifier and cell type.
@interface FakeSpec : NSObject
@property (nonatomic, copy) NSString *ident;
@property (nonatomic) long long type;
@property (nonatomic) int reads;
@end
@implementation FakeSpec
- (NSString *)identifier { self.reads++; return self.ident; }
- (long long)cellType { self.reads++; return self.type; }
@end
// A stand-in for PSUIPrefsListController: its own _specifiers and Apple's Apple Account row getter.
@interface FakeRoot : NSObject { NSMutableArray *_specifiers; }
@property (nonatomic, strong) id account;
@end
@implementation FakeRoot
- (id)_appleAccountSpecifier { return self.account; }
- (void)setRows:(NSMutableArray *)rows { _specifiers = rows; }
@end
@interface FakePage : NSObject { NSMutableArray *_specifiers; }   // (another page: no Apple Account row of its own)
@end
@implementation FakePage
- (void)setRows:(NSMutableArray *)rows { _specifiers = rows; }
@end
static NSMutableArray *Rows(NSString *s) {   // ("name:type", type 0 = a group row)
    NSMutableArray *o = [NSMutableArray array];
    for (NSString *p in [s componentsSeparatedByString:@" "]) {
        NSArray *q = [p componentsSeparatedByString:@":"];
        FakeSpec *sp = [FakeSpec new]; sp.ident = q[0]; sp.type = q.count > 1 ? [q[1] longLongValue] : 1; [o addObject:sp];
    }
    return o;
}
static int fails = 0, checks = 0;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static NSArray *Ids(NSString *s) {   // ("-" = a row whose identifier is not read)
    NSMutableArray *o = [NSMutableArray array];
    for (NSString *p in [s componentsSeparatedByString:@" "]) [o addObject:[p isEqualToString:@"-"] ? [NSNull null] : p];
    return o;
}
static NSString *At(NSArray *ids, NSInteger i) { return i == NSNotFound ? @"(none)" : i >= (NSInteger)ids.count ? @"(end)" : [ids[i] isKindOfClass:[NSString class]] ? ids[i] : @"(unread)"; }
int main(void) {
    @autoreleasepool {
        NSString *m1 = @"PRIMARY_APPLE_ACCOUNT_GROUP APPLE_ACCOUNT WIRELESS_GROUP AIRPLANE_MODE WIFI Bluetooth SSH_TOGGLE HOMEBAR_TOGGLE MAC_POINTER MAC_KEYBOARD VPN NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME GENERAL_GROUP General ControlCenter DISPLAY HOME_SCREEN_DOCK MAC_SETTINGS_ACCESSIBILITY_GROUP ACCESSIBILITY";
        NSString *s17 = @"PRIMARY_APPLE_ACCOUNT_GROUP APPLE_ACCOUNT WIRELESS_GROUP AIRPLANE_MODE WIFI Bluetooth SSH_TOGGLE VPN NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME GENERAL_GROUP General ControlCenter DISPLAY HOME_SCREEN com.apple.MultitaskingAndGesturesSettings MAC_SETTINGS_ACCESSIBILITY_GROUP ACCESSIBILITY";
        for (NSString *list in @[m1, s17]) {
            NSArray *ids = Ids(list);
            // Status Bar: in front of the Dock row when it is there, else in front of Control Center
            NSInteger sb = MSBDMLAnchor(ids, @"DOCK_MAGNIFICATION", nil);
            Check([At(ids, sb) isEqualToString:@"ControlCenter"], [NSString stringWithFormat:@"Status Bar first: in front of Control Center (got %@)", At(ids, sb)]);
            NSMutableArray *withSB = [ids mutableCopy]; [withSB insertObject:@"MAC_STATUS_BAR" atIndex:(NSUInteger)sb];
            [withSB insertObject:@"MAC_DESKTOP" atIndex:(NSUInteger)sb + 1]; [withSB insertObject:@"MAC_WINDOWS" atIndex:(NSUInteger)sb + 2];
            // Dock: right after Windows & Multitasking (else Desktop, else Status Bar)
            NSInteger dock = MSBDMLAnchor(withSB, nil, @"MAC_WINDOWS");
            Check(dock == sb + 3 && [At(withSB, dock) isEqualToString:@"ControlCenter"], [NSString stringWithFormat:@"Dock after Windows & Multitasking (got %ld)", (long)dock]);
            // Dock first, Status Bar second: Status Bar goes in front of the Dock row
            NSMutableArray *withDock = [ids mutableCopy]; [withDock insertObject:@"DOCK_MAGNIFICATION" atIndex:(NSUInteger)MSBDMLAnchor(ids, nil, @"MAC_STATUS_BAR")];
            NSInteger sb2 = MSBDMLAnchor(withDock, @"DOCK_MAGNIFICATION", nil);
            Check([At(withDock, sb2) isEqualToString:@"DOCK_MAGNIFICATION"], [NSString stringWithFormat:@"Status Bar in front of the Dock row (got %@)", At(withDock, sb2)]);
        }
        // no Control Center: right after General; neither: in front of Accessibility; none of them: NSNotFound
        Check(MSBDMLAnchor(Ids(@"GENERAL_GROUP General DISPLAY ACCESSIBILITY"), nil, @"MAC_STATUS_BAR") == 2, @"no Control Center: right after General");
        Check(MSBDMLAnchor(Ids(@"DISPLAY HOME_SCREEN ACCESSIBILITY"), nil, nil) == 2, @"no Control Center, no General: in front of Accessibility");
        Check(MSBDMLAnchor(Ids(@"DISPLAY HOME_SCREEN"), nil, nil) == NSNotFound, @"no known row: none");
        Check(MSBDMLAnchor(Ids(@"general controlcenter accessibility"), nil, nil) == 1, @"Apple's rows in any case");
        // a row whose identifier is not read is never taken for one (Settings filling it in on another thread)
        Check(MSBDMLAnchor(Ids(@"PRIMARY_APPLE_ACCOUNT_GROUP - GENERAL_GROUP General ControlCenter"), nil, nil) == 4, @"an unread row is skipped");
        Check(MSBDMLAnchor(Ids(@"- - -"), @"DOCK_MAGNIFICATION", @"MAC_WINDOWS") == NSNotFound, @"unread rows only: none");
        Check(MSBDMLIndexOf(Ids(@"PRIMARY_APPLE_ACCOUNT_GROUP - WIFI Bluetooth"), @"BLUETOOTH", YES) == 3, @"Bluetooth found in any case, past an unread row");
        Check(MSBDMLIndexOf(Ids(@"PRIMARY_APPLE_ACCOUNT_GROUP - WIFI"), @"BLUETOOTH", YES) == NSNotFound, @"an unread row is not Bluetooth");
        Check(MSBDMLIndexOf(Ids(@"SSH_TOGGLE"), @"ssh_toggle", NO) == NSNotFound && MSBDMLIndexOf(Ids(@"SSH_TOGGLE"), @"SSH_TOGGLE", NO) == 0, @"our rows: exact identifier");
        Check(MSBDMLLastIndexOf(Ids(@"MAC_STATUS_BAR General MAC_STATUS_BAR -"), @"MAC_STATUS_BAR") == 2 && MSBDMLLastIndexOf(Ids(@"- General"), @"MAC_STATUS_BAR") == NSNotFound && MSBDMLLastIndexOf(Ids(@"mac_status_bar"), @"MAC_STATUS_BAR") == NSNotFound, @"the last row of an identifier (exact), past unread rows");
        // the top fallback: the start of the second block (the row after the first group row past the first row), else 1
        Check(MSBDMLTop(@[@0, @1, @0, @1, @1]) == 3, @"top: after the second group row");
        Check(MSBDMLTop(@[@0, @1, @1]) == 1 && MSBDMLTop(@[]) == 0, @"top: no second group row: 1; an empty list: 0");
        // the Accessibility section's group row: only the Status Bar and Dock rows go in front of it
        NSArray *acc = Ids(@"General ControlCenter DISPLAY MAC_SETTINGS_ACCESSIBILITY_GROUP ACCESSIBILITY Wallpaper");
        NSString *gid = @"MAC_SETTINGS_ACCESSIBILITY_GROUP";
        Check(MSBDMLGoesBeforeAccessibilityGroup(@[@"DOCK_MAGNIFICATION"]) && MSBDMLGoesBeforeAccessibilityGroup(@[@"MAC_STATUS_BAR"]) && MSBDMLGoesBeforeAccessibilityGroup(@[@"MAC_STATUS_BAR", @"DOCK_MAGNIFICATION"]), @"the Status Bar and Dock rows go in front of the group row");
        Check(!MSBDMLGoesBeforeAccessibilityGroup(@[@"VPN"]) && !MSBDMLGoesBeforeAccessibilityGroup(@[@"MAC_STATUS_BAR", @"VPN"]) && !MSBDMLGoesBeforeAccessibilityGroup(@[[NSNull null]]) && !MSBDMLGoesBeforeAccessibilityGroup(@[]), @"another row, ours with another, an unread row, nothing: as they are");
        Check(MSBDMLAccessibilityGroupIndex(acc, 4, gid) == 3, @"in front of Accessibility: in front of the group row");
        Check(MSBDMLAccessibilityGroupIndex(acc, 1, gid) == 1, @"in front of Control Center: as it is");
        Check(MSBDMLAccessibilityGroupIndex(acc, 5, gid) == 5, @"after Accessibility: as it is");
        Check(MSBDMLAccessibilityGroupIndex(acc, 3, gid) == 3, @"in front of the group row already: as it is");
        Check(MSBDMLAccessibilityGroupIndex(Ids(@"General DISPLAY ACCESSIBILITY"), 2, gid) == 2, @"no group row: as it is");
        Check(MSBDMLAccessibilityGroupIndex(Ids(@"General MAC_SETTINGS_ACCESSIBILITY_GROUP - ACCESSIBILITY"), 3, gid) == 1, @"an unread row between the group row and Accessibility is not Accessibility");
        Check(MSBDMLAccessibilityGroupIndex(Ids(@"General MAC_SETTINGS_ACCESSIBILITY_GROUP -"), 2, gid) == 2, @"an unread row is not Accessibility: as it is");

        // ---- on stand-ins for Settings' list and rows ----
        FakeRoot *root = [FakeRoot new];
        NSMutableArray *rows = Rows(@"PRIMARY_APPLE_ACCOUNT_GROUP:0 APPLE_ACCOUNT WIRELESS_GROUP:0 WIFI Bluetooth SSH_TOGGLE VPN GENERAL_GROUP:0 General ControlCenter DISPLAY MAC_SETTINGS_ACCESSIBILITY_GROUP:0 ACCESSIBILITY");
        FakeSpec *account = rows[1];
        [root setRows:rows]; root.account = account;
        NSArray *ids = MSBDMLIdentifiers(root, rows);
        Check(account.reads == 0, @"the row Settings fills in is never read (identifiers)");
        Check(ids.count == rows.count && ids[1] == [NSNull null] && [ids[4] isEqual:@"Bluetooth"], @"identifiers: the filled row NSNull, the others as they are");
        Check(MSBDMLAnchor(ids, nil, nil) == 9 && MSBDMLIndexOf(ids, @"BLUETOOTH", YES) == 4, @"places found past the filled row");
        NSArray *types = MSBDMLCellTypes(root, rows);
        Check(account.reads == 0 && [types[1] longLongValue] == -1 && [types[2] longLongValue] == 0, @"cell types: the filled row -1, never read");
        Check(MSBDMLTop(types) == 3, @"the top fallback skips the filled row (-1 is not a group row)");
        Check(MSBDMLRowFor(root, rows, @"APPLE_ACCOUNT", NO) == nil && account.reads == 0, @"the filled row is never found by its identifier (never read for it)");
        Check(MSBDMLRowFor(root, rows, @"general", YES) == rows[8], @"another row found by its identifier, any case");
        Check(!MSBDMLReadable(root, account) && MSBDMLReadable(root, rows[4]) && !MSBDMLReadable(root, nil), @"readable: every row but the filled one");
        Check(MSBDMLLive(root) == rows, @"the list as it is now: the controller's own _specifiers");
        NSMutableArray *newer = [rows mutableCopy]; [root setRows:newer];
        Check(MSBDMLLive(root) == newer && MSBDMLLive(root) != rows, @"... the new list once Settings replaces it (never a copy kept from before)");
        root.account = nil; (void)MSBDMLIdentifiers(root, rows);
        Check(account.reads == 1, @"no Apple Account row: every row read (as before)");
        FakePage *page = [FakePage new]; NSMutableArray *prow = Rows(@"A B"); [page setRows:prow];
        Check([MSBDMLIdentifiers(page, prow) isEqual:@[@"A", @"B"]] && MSBDMLFilledRow(page) == nil && MSBDMLLive(page) == prow, @"a page without the call: every row read, nothing left out");
        Check(MSBDMLFilledRow(nil) == nil && MSBDMLLive(nil) == nil && MSBDMLIdentifiers(nil, @[]).count == 0, @"no list: nothing");
        NSObject *plain = [NSObject new];
        Check(MSBDMLLive(plain) == nil && [MSBDMLIdentifiers(plain, @[plain]) isEqual:@[[NSNull null]]], @"no _specifiers, a row without an identifier: nil, NSNull");
    }
    printf("test-mainlistrows: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
