// test-milkywayrow.m -- Mac test of MilkyWay4's "Launch As Window" row while it is our engine (statusbar/MilkyWayRow.h): kept where it opens a window that
// shows (the Dock, the Home Screen), gone from every place of the App Library (a category's icons opened the app full screen; an expanded category's and the
// search list's put the window behind the App Library). Run by test-milkywayrow.sh.
#import <Foundation/Foundation.h>
#import "../statusbar/MilkyWayRow.h"

@interface FakeItem : NSObject
@property (nonatomic, copy) NSString *type;
@end
@implementation FakeItem @end
static FakeItem *Item(NSString *type) { FakeItem *i = [FakeItem new]; i.type = type; return i; }

static int gFail = 0, gN = 0;
static void Check(BOOL ok, NSString *what) {
    gN++;
    if (!ok) { gFail++; printf("  FAIL %s\n", what.UTF8String); } else printf("  ok   %s\n", what.UTF8String);
}
int main(void) {
    @autoreleasepool {
        // the M1's names on 15.6.1 (Root, FloatingDock, ...CategoryPod, ...CategoryPodExpanded, ...AppLibrarySearch), and their neighbours in SpringBoard's list
        for (NSString *where in @[@"SBIconLocationRoot", @"SBIconLocationFloatingDock", @"SBIconLocationDock", @"SBIconLocationFloatingDockSuggestions", @"SBIconLocationFolder", @"SBIconLocationRootWithWidgets"])
            Check(DMMilkyRowOpensWindowAt(where), [where stringByAppendingString:@": the row stays"]);
        for (NSString *where in @[@"SBIconLocationAppLibrary", @"SBIconLocationAppLibraryCategoryPod", @"SBIconLocationAppLibraryCategoryPodExpanded", @"SBIconLocationAppLibrarySearch", @"SBIconLocationFloatingDockLibraryPod"])
            Check(!DMMilkyRowOpensWindowAt(where), [where stringByAppendingString:@": the row goes"]);
        Check(DMMilkyRowOpensWindowAt(nil) && DMMilkyRowOpensWindowAt(@7), @"no location to read: the menu is left alone");

        FakeItem *size = Item(@"com.besiktasliseba.appsizemenu.size"), *row = Item(kDMMilkyLaunchRowType), *dock = Item(@"com.besiktasliseba.macdock.removefromdock");
        NSArray *all = @[size, row, dock], *none = @[size, dock];
        Check([DMMilkyRowsWithoutLaunch(all) isEqualToArray:none], @"the row goes, the other rows stay, in their order");
        Check(DMMilkyRowsWithoutLaunch(none) == none, @"no row: the same list");
        Check([DMMilkyRowsWithoutLaunch(@[row]) count] == 0, @"only the row: an empty list");
        Check(DMMilkyRowsWithoutLaunch(nil) == nil, @"no list: none");
        NSArray *odd = @[@"not an item", row];
        Check([DMMilkyRowsWithoutLaunch(odd) isEqualToArray:@[@"not an item"]], @"something that has no type is left alone");
        Check([kDMMilkyLaunchRowType isEqualToString:@"jp.yuri.milkyway3.launchinwindow"], @"the row's type, as DMLaunchAsWindow sends it to MilkyWay4");
        printf("%d checks, %d failed\n", gN, gFail);
    }
    return gFail ? 1 : 0;
}
