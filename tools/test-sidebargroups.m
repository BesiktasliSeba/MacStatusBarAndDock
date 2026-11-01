// Mac test of the sidebar's groups (common/SidebarGroups.h; 1.7.5 item 2): which rows make "Notifications & Sounds" and "Focus & Screen Time" in
// the main lists of 15.6.1, 16.7.7 and 17.5.1 as MacSettings logged them, what stays as Apple has it, and how links to Apple's grouped pages are
// sent through our rows.
#import <Foundation/Foundation.h>
#include "../common/SidebarGroups.h"
static int fails = 0, checks = 0;
static void Check(BOOL ok, NSString *what) { checks++; if (!ok) { fails++; printf("FAIL %s\n", what.UTF8String); } }
static NSArray *Ids(NSString *s) { return [s componentsSeparatedByString:@" "]; }
// A stand-in for Settings' sidebar: its specifiers change IN PLACE through the same two calls Apple's list has (as PSListController's do), so
// MSSGApplyPlan runs here exactly as on the iPad -- the second group's rows must be found after the first group's two rows became one.
@interface FakeSpec : NSObject
@property (nonatomic, copy) NSString *identifier;
@end
@implementation FakeSpec
@end
@interface FakeList : NSObject
@property (nonatomic, strong) NSMutableArray *specifiers;
@property (nonatomic) int calls;
@end
@implementation FakeList
- (void)replaceContiguousSpecifiers:(NSArray *)old withSpecifiers:(NSArray *)specs animated:(BOOL)animated {
    self.calls++;
    NSUInteger at = [self.specifiers indexOfObjectIdenticalTo:old.firstObject];
    if (at == NSNotFound) [NSException raise:NSRangeException format:@"not in the list"];
    for (NSUInteger k = 0; k < old.count; k++) if (at + k >= self.specifiers.count || self.specifiers[at + k] != old[k]) [NSException raise:NSRangeException format:@"not contiguous"];
    [self.specifiers replaceObjectsInRange:NSMakeRange(at, old.count) withObjectsFromArray:specs];
}
- (void)removeSpecifier:(id)spec animated:(BOOL)animated {
    self.calls++;
    NSUInteger at = [self.specifiers indexOfObjectIdenticalTo:spec];
    if (at == NSNotFound) [NSException raise:NSRangeException format:@"not in the list"];
    [self.specifiers removeObjectAtIndex:at];
}
@end
static FakeList *List(NSArray *ids) {
    FakeList *l = [FakeList new]; l.specifiers = [NSMutableArray array];
    for (NSString *i in ids) { FakeSpec *sp = [FakeSpec new]; sp.identifier = i; [l.specifiers addObject:sp]; }
    return l;
}
static NSArray *IdsOf(FakeList *l) { NSMutableArray *o = [NSMutableArray array]; for (FakeSpec *sp in l.specifiers) [o addObject:sp.identifier ?: @""]; return o; }
static NSMutableDictionary *gMade;
static NSArray *Apply(NSArray *ids) {   // (the real MSSGApplyPlan on a stand-in list)
    FakeList *l = List(ids);
    gMade = [NSMutableDictionary dictionary];
    MSSGApplyPlan(l, ^id(int g, NSArray *members) { FakeSpec *r = [FakeSpec new]; r.identifier = @(kMSSGGroups[g].ident); return r; },
                  ^(int g, NSArray *members) { gMade[@(g)] = [members valueForKey:@"identifier"]; });
    return IdsOf(l);
}
static void Link(NSString *link, BOOL grouped0, BOOL grouped1, NSString *want) {
    NSString *got = MSSGRewrite(link, ^BOOL(int g) { return g == 0 ? grouped0 : grouped1; });
    Check(got == want || [got isEqualToString:want], [NSString stringWithFormat:@"%@ -> %@ (want %@)", link, got, want]);
}
int main(void) {
    @autoreleasepool {
        // the main lists as logged (MacSettings "list ids"), with our own rows and Apple's later Ethernet / VPN rows
        NSString *m1 = @"PRIMARY_APPLE_ACCOUNT_GROUP APPLE_ACCOUNT WIRELESS_GROUP AIRPLANE_MODE WIFI Bluetooth SSH_TOGGLE HOMEBAR_TOGGLE MAC_POINTER MAC_KEYBOARD VPN NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME GENERAL_GROUP General ControlCenter DISPLAY HOME_SCREEN_DOCK MAC_SETTINGS_ACCESSIBILITY_GROUP ACCESSIBILITY";
        NSString *i2 = @"PRIMARY_APPLE_ACCOUNT_GROUP APPLE_ACCOUNT WIRELESS_GROUP AIRPLANE_MODE WIFI Bluetooth SSH_TOGGLE MOBILE_DATA_SETTINGS_ID VPN NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME GENERAL_GROUP General ControlCenter DISPLAY HOME_SCREEN_DOCK";
        NSString *s17 = @"PRIMARY_APPLE_ACCOUNT_GROUP APPLE_ACCOUNT WIRELESS_GROUP AIRPLANE_MODE WIFI Bluetooth SSH_TOGGLE VPN NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME GENERAL_GROUP General ControlCenter DISPLAY HOME_SCREEN com.apple.MultitaskingAndGesturesSettings";
        for (NSString *list in @[m1, i2, s17]) {
            NSArray *after = Apply(Ids(list));
            NSUInteger g = [after indexOfObject:@"NOTIFICATIONS_GROUP_ID"];
            Check(g != NSNotFound && [after[g + 1] isEqual:@"MAC_NOTIFICATIONS_SOUNDS"] && [after[g + 2] isEqual:@"MAC_FOCUS_SCREEN_TIME"] && [after[g + 3] isEqual:@"GENERAL_GROUP"],
                  [NSString stringWithFormat:@"the group of four becomes our two rows: %@", [after componentsJoinedByString:@" "]]);
            Check(after.count == Ids(list).count - 2, @"two rows fewer, nothing else changed");
            for (NSString *x in @[@"NOTIFICATIONS_ID", @"Sounds", @"DO_NOT_DISTURB", @"SCREEN_TIME"]) Check(![after containsObject:x], [NSString stringWithFormat:@"%@ leaves the list", x]);
            Check(MSSGPlan(after).count == 0, @"grouped once: the grouped list has nothing left to do");
            Check([gMade[@0] isEqualToArray:@[@"NOTIFICATIONS_ID", @"Sounds"]] && [gMade[@1] isEqualToArray:@[@"DO_NOT_DISTURB", @"SCREEN_TIME"]], [NSString stringWithFormat:@"each page keeps Apple's own two rows, in Apple's order: %@", gMade]);
            Check([after containsObject:@"GENERAL_GROUP"] && [after indexOfObject:@"GENERAL_GROUP"] == [after indexOfObject:@"General"] - 1, @"General's own group header stays (the 1.7.5 review's case)");
        }
        // the second group found after the first one's two rows became one, also when Screen Time is the very last row (no row after it)
        Check([Apply(Ids(@"G NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME")) isEqualToArray:Ids(@"G MAC_NOTIFICATIONS_SOUNDS MAC_FOCUS_SCREEN_TIME")], @"Screen Time last: both groups, nothing out of range");
        // a row gone between the plan and its call (another tweak's change meanwhile): that group left as it is, no exception
        {
            FakeList *l = List(Ids(@"G NOTIFICATIONS_ID Sounds DO_NOT_DISTURB SCREEN_TIME X"));
            __block BOOL once = NO;
            NSUInteger made = MSSGApplyPlan(l, ^id(int g, NSArray *members) {
                if (!once) { once = YES; [l.specifiers removeObjectAtIndex:4]; }   // (Screen Time taken out by someone else right now)
                FakeSpec *r = [FakeSpec new]; r.identifier = @(kMSSGGroups[g].ident); return r;
            }, nil);
            Check(made == 1 && [IdsOf(l) isEqualToArray:Ids(@"G MAC_NOTIFICATIONS_SOUNDS DO_NOT_DISTURB X")], [NSString stringWithFormat:@"a row gone meanwhile: %@ (%lu made)", [IdsOf(l) componentsJoinedByString:@" "], (unsigned long)made]);
        }
        // a group with one of its rows missing stays as Apple has it (Screen Time not there: Focus alone)
        NSArray *noST = Apply(Ids(@"NOTIFICATIONS_GROUP_ID NOTIFICATIONS_ID Sounds DO_NOT_DISTURB GENERAL_GROUP General"));
        Check([noST isEqualToArray:Ids(@"NOTIFICATIONS_GROUP_ID MAC_NOTIFICATIONS_SOUNDS DO_NOT_DISTURB GENERAL_GROUP General")], [NSString stringWithFormat:@"Focus alone stays: %@", [noST componentsJoinedByString:@" "]]);
        // not next to each other (another tweak put a row between): our row at the first one's place, the second goes
        NSArray *apart = Apply(Ids(@"G NOTIFICATIONS_ID OTHER Sounds X"));
        Check([apart isEqualToArray:Ids(@"G MAC_NOTIFICATIONS_SOUNDS OTHER X")], [NSString stringWithFormat:@"apart: %@", [apart componentsJoinedByString:@" "]]);
        NSDictionary *st = MSSGPlan(Ids(@"G NOTIFICATIONS_ID OTHER Sounds X")).firstObject;
        Check(![st[@"adjacent"] boolValue] && [MSSGPlan(Ids(@"G NOTIFICATIONS_ID Sounds")).firstObject[@"adjacent"] boolValue], @"adjacent told apart (one replace, or a replace and a remove)");
        // in the other order (Sounds first): our row where the first of them was
        Check([Apply(Ids(@"G Sounds NOTIFICATIONS_ID X")) isEqualToArray:Ids(@"G MAC_NOTIFICATIONS_SOUNDS X")], @"the other order: our row at the first one's place");
        int m = -1;
        Check(MSSGGroupOfApple(@"SOUNDS", &m) == 0 && m == 1 && MSSGGroupOfApple(@"screen_time", &m) == 1 && m == 1 && MSSGGroupOfApple(@"General", &m) < 0, @"Apple's rows matched without case; others not");
        Check(MSSGGroupOfOurs(@"MAC_FOCUS_SCREEN_TIME") == 1 && MSSGGroupOfOurs(@"mac_focus_screen_time") < 0, @"our rows by their exact identifier");
        // our row already there: nothing planned (Apple's row coming back is SidebarGroups.x's own case)
        Check(MSSGPlan(Ids(@"MAC_NOTIFICATIONS_SOUNDS NOTIFICATIONS_ID Sounds")).count == 0, @"our row there: no second one");

        // links (KT: prefs:root=SOUNDS / NOTIFICATIONS_ID / DO_NOT_DISTURB / SCREEN_TIME keep working)
        Link(@"prefs:root=SOUNDS", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds");
        Link(@"prefs:root=Sounds", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds");
        Link(@"prefs:root=NOTIFICATIONS_ID", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=NOTIFICATIONS_ID");
        Link(@"prefs:root=NOTIFICATIONS_ID&path=com.apple.mobiletimer", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=NOTIFICATIONS_ID/com.apple.mobiletimer");
        Link(@"prefs:root=DO_NOT_DISTURB", YES, YES, @"prefs:root=MAC_FOCUS_SCREEN_TIME&path=DO_NOT_DISTURB");
        Link(@"prefs:root=SCREEN_TIME&path=SCREEN_TIME_SUMMARY", YES, YES, @"prefs:root=MAC_FOCUS_SCREEN_TIME&path=SCREEN_TIME/SCREEN_TIME_SUMMARY");
        Link(@"prefs:root=Sounds#KEYBOARD_CLICKS", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds#KEYBOARD_CLICKS");
        Link(@"prefs:root=Sounds%23KEYBOARD_CLICKS", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds%23KEYBOARD_CLICKS");
        Link(@"prefs:root=Sounds&path=A/B#R", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds/A/B#R");
        Link(@"prefs:root=SCREEN_TIME&other=1&path=X", YES, YES, @"prefs:root=MAC_FOCUS_SCREEN_TIME&path=SCREEN_TIME/X&other=1");
        Link(@"App-prefs:root=DO_NOT_DISTURB", YES, YES, @"prefs:root=MAC_FOCUS_SCREEN_TIME&path=DO_NOT_DISTURB");
        Link(@"app-prefs:Root=Sounds", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds");
        // the form without "root=" (App-prefs:SOUNDS, prefs:NOTIFICATIONS_ID&path=X): the same, written as prefs:root= for Settings (an
        // App-prefs: link is always written as prefs:: Settings takes all after "App-prefs:" as the root, 1.7.5 R1 on 15.6.1)
        Link(@"App-prefs:SOUNDS", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds");
        Link(@"prefs:NOTIFICATIONS_ID&path=com.apple.mobiletimer", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=NOTIFICATIONS_ID/com.apple.mobiletimer");
        Link(@"prefs:SCREEN_TIME#X", YES, YES, @"prefs:root=MAC_FOCUS_SCREEN_TIME&path=SCREEN_TIME#X");
        Link(@"prefs:path=Sounds", YES, YES, @"prefs:path=Sounds");
        Link(@"prefs:General", YES, YES, @"prefs:General");
        // a group that is not in the sidebar (one row missing, or not grouped on this iPad): Apple's link as it is
        Link(@"prefs:root=DO_NOT_DISTURB", YES, NO, @"prefs:root=DO_NOT_DISTURB");
        Link(@"prefs:root=Sounds", NO, YES, @"prefs:root=Sounds");
        // everything else as it is: other pages, ours, a page whose name only starts the same, junk
        Link(@"prefs:root=General&path=About", YES, YES, @"prefs:root=General&path=About");
        Link(@"prefs:root=SoundsX", YES, YES, @"prefs:root=SoundsX");
        Link(@"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds", YES, YES, @"prefs:root=MAC_NOTIFICATIONS_SOUNDS&path=Sounds");
        Link(@"prefs:root=MAC_STATUS_BAR", YES, YES, @"prefs:root=MAC_STATUS_BAR");
        Link(@"https://example.com/root=Sounds", YES, YES, @"https://example.com/root=Sounds");
        Link(@"prefs:", YES, YES, @"prefs:");
        Link(nil, YES, YES, nil);
        // rewritten once only: our link is not rewritten again
        NSString *once = MSSGRewrite(@"prefs:root=Sounds", nil);
        Check([MSSGRewrite(once, nil) isEqualToString:once], @"a rewritten link stays as it is (the one-argument and four-argument handlers both see it)");
    }
    printf("%d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
