// test-milkywayrow.m -- Mac test of MilkyWay4's "Launch As Window" row while it is our engine (statusbar/MilkyWayRow.h): kept where it opens a window that
// shows (the Dock, the Home Screen), gone from every place of the App Library (a category's icons opened the app full screen; an expanded category's and the
// search list's put the window behind the App Library), and (1.8.7.5, audit L31 of 1.8.7.2) gone for an app that has a MilkyWay window already: MilkyWay4
// made a second window on the app's one scene. The hook of -effectiveApplicationShortcutItems as built (mwrow-hook.inc, cut out of StatusBar.x) runs on
// a stand-in icon view with a stand-in window finder. Run by test-milkywayrow.sh.
#import <Foundation/Foundation.h>
#import "MilkyWayRow.h"

@interface FakeItem : NSObject
@property (nonatomic, copy) NSString *type;
@end
@implementation FakeItem @end
static FakeItem *Item(NSString *type) { FakeItem *i = [FakeItem new]; i.type = type; return i; }
// ---- the hook as built, on a stand-in icon view (its place, its app) with a stand-in window finder
typedef enum { DMEngineNone = 0, DMEngineMilkyWay, DMEngineAerial, DMEngineZetsu } DMEngine;
static DMEngine gKEngine = DMEngineMilkyWay;
static DMEngine DMActiveEngine(void) { return gKEngine; }
static BOOL DMTestFlag(const char *path) { return NO; }
static void DMLog(NSString *s) { }
#define DM_FEATURE_MARK(name) do { } while (0)
static id DMCall(id o, NSString *sel) { return [o valueForKey:sel]; }
@interface KIconView : NSObject
@property (nonatomic, strong) NSArray *kItems;
@property (nonatomic, strong) id location;
@property (nonatomic, copy) NSString *app;
- (NSArray *)effectiveApplicationShortcutItems;
@end
static NSString *DMIconViewApp(id iconView) { return ((KIconView *)iconView).app; }
static NSMutableSet<NSString *> *gKWindows;   // (the apps with a MilkyWay window: here, minimized or on another desktop -- not one on its way out)
static id DMFindMilkyWayWindow(NSString *bundleID) { return [gKWindows containsObject:bundleID] ? [NSObject new] : nil; }
@implementation KIconView
#include "mwrow-hook.inc"
@end
static NSArray *Menu(NSString *app, NSString *where, NSArray *items) { KIconView *v = [KIconView new]; v.app = app; v.location = where; v.kItems = items; return [v effectiveApplicationShortcutItems]; }

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

        // L31: an app that has a MilkyWay window already: no row at any place (MilkyWay4 made a second window); without one, as before
        NSArray *places = @[@"SBIconLocationRoot", @"SBIconLocationFloatingDock", @"SBIconLocationDock", @"SBIconLocationFloatingDockSuggestions", @"SBIconLocationFolder", @"SBIconLocationRootWithWidgets",
                            @"SBIconLocationAppLibrary", @"SBIconLocationAppLibraryCategoryPod", @"SBIconLocationAppLibraryCategoryPodExpanded", @"SBIconLocationAppLibrarySearch", @"SBIconLocationFloatingDockLibraryPod"];
        BOOL noneWith = YES, sameWithout = YES;
        for (NSString *where in places) { if (DMMilkyRowKept(where, YES)) noneWith = NO; if (DMMilkyRowKept(where, NO) != DMMilkyRowOpensWindowAt(where)) sameWithout = NO; }
        Check(noneWith && !DMMilkyRowKept(nil, YES), @"L31: the app has a window: the row is left out everywhere (the Home Screen, the Dock, folders, the App Library)");
        Check(sameWithout && DMMilkyRowKept(nil, NO), @"no window yet: where the row stays is as before (the App Library rule unchanged)");
        gKWindows = [NSMutableSet set];
        Check([Menu(@"com.apple.mobilenotes", @"SBIconLocationRoot", all) isEqualToArray:all], @"the hook: Notes without a window, on the Home Screen: the row stays (as before)");
        [gKWindows addObject:@"com.apple.mobilenotes"];
        Check([Menu(@"com.apple.mobilenotes", @"SBIconLocationRoot", all) isEqualToArray:none], @"L31: the hook: Notes with a window, on the Home Screen: no row, the other rows stay");
        Check([Menu(@"com.apple.mobilenotes", @"SBIconLocationFloatingDock", all) isEqualToArray:none], @"L31: the hook: ... in the Dock: no row");
        Check([Menu(@"com.apple.Maps", @"SBIconLocationFloatingDock", all) isEqualToArray:all], @"the hook: another app without a window keeps its row");
        Check([Menu(@"com.apple.Maps", @"SBIconLocationAppLibrarySearch", all) isEqualToArray:none], @"the hook: the App Library without a window: no row (as before)");
        Check([Menu(nil, @"SBIconLocationRoot", all) isEqualToArray:all], @"the hook: an icon of no app (ours): as before");
        gKEngine = DMEngineAerial;
        Check([Menu(@"com.apple.mobilenotes", @"SBIconLocationRoot", all) isEqualToArray:all], @"the hook: another engine: the menu as it is (as before)");
        gKEngine = DMEngineMilkyWay;
        printf("%d checks, %d failed\n", gN, gFail);
    }
    return gFail ? 1 : 0;
}
