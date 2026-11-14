// test-dockremove.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Remove from Dock and an app dropped on the Dock's Trash (1.8.7.3, audit M6 of
// 1.8.7.2): both follow the Dock part's own switch, not Magnify Icons. Both used to ask the magnification switch ("enabled", a leftover from when it
// was the Dock's main switch), so with Magnify Icons off a kept Dock app's menu had no Remove from Dock, and the Trash took an app dropped on it (the
// bin lit, the app shrank into it) and then left it in the Dock; Activity Monitor's icon too. The bin's drop side never asked any switch, so with the
// Dock part off it took a drop the removal then refused.
// Runs the real code, cut out of the sources by test-dockremove.sh: dock/Dock.x's globals and DMLoadPrefs (the settings as the Dock reads them), the
// menu's Remove from Dock (-applicationShortcutItems, +activateShortcut:...), the removal (DMTrashRemoveIconFromDock, DMRemoveFromDock and the icon
// model's look-ups), what SpringBoard's icon drag carries (DMTrashIconDragInfo), and dock/TrashIcon.m's drop side (canHandleSession, performDrop,
// sessionDidEnd), with the real common/DockTrash.h rules. SpringBoard's side (its icon model, its icon drag, the settings) is the stand-ins below.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include "../common/DockSide.h"
#include "../common/DockBounce.h"
#include "../common/DockStyle.h"
#include "../common/DockAutoHide.h"
#include "../common/DockTrash.h"

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gDRLog;
#define DMLog(...) [gDRLog addObject:(__VA_ARGS__) ?: @""]
#define DM_FEATURE_MARK(name) do {} while (0)

// ---- the settings, as the device keeps them (com.besiktasliseba.dockmagnification, the spotlight domain, Mac Status Bar's)
#define DM_DOMAIN CFSTR("com.besiktasliseba.dockmagnification")
#define DM_SPOTLIGHT_DOMAIN CFSTR("com.besiktasliseba.macspotlightreplace")
static NSMutableDictionary *gDRDock, *gDRMSB;
static CFPropertyListRef DMCopyPref(CFStringRef key) { id v = gDRDock[(__bridge NSString *)key]; return v ? CFBridgingRetain(v) : NULL; }
static CFPropertyListRef DMCopySpotlightPref(CFStringRef key) { return NULL; }
static CFPropertyListRef DRCopyValue(CFStringRef key, CFStringRef domain) {
    id v = [(__bridge NSString *)domain isEqualToString:@"com.besiktasliseba.macstatusbar"] ? gDRMSB[(__bridge NSString *)key] : nil;
    return v ? CFBridgingRetain(v) : NULL;
}
#define CFPreferencesCopyValue(k, d, u, h) DRCopyValue((k), (d))
#define CFPreferencesAppSynchronize(d) ((void)(d))
void DMBounceSetOn(BOOL on) {}
void DMDockAutoHideSetOn(BOOL on) {}
void DMDockStyleSetChoice(int style) {}
static void DMDispReload(void) {}

// ---- SpringBoard's icon model: the Dock's own list and the Home Screen
@interface TDRIcon : NSObject
@property (nonatomic, copy) NSString *applicationBundleID, *leafIdentifier;
@property (nonatomic) BOOL isFolderIcon;
@end
@implementation TDRIcon
@end
static NSMutableArray *gDRDockIcons, *gDRHome;
@interface TDRDockList : NSObject
@end
@implementation TDRDockList
- (NSArray *)icons { return [gDRDockIcons copy]; }
- (BOOL)directlyContainsIcon:(id)icon { return [gDRDockIcons containsObject:icon]; }
- (void)removeIcons:(NSArray *)icons { [gDRDockIcons removeObjectsInArray:icons]; }
- (void)insertIcons:(NSArray *)icons atIndex:(NSUInteger)i options:(unsigned long long)o { [gDRDockIcons insertObjects:icons atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, icons.count)]]; }
@end
@interface TDRRoot : NSObject
@property (nonatomic, strong) TDRDockList *dock;
@end
@implementation TDRRoot
- (id)gridPathForFirstFreeSlotAvoidingFirstList:(BOOL)avoid listGridCellInfoOptions:(unsigned long long)o { return @"page 1, place 3"; }
- (id)insertIcon:(id)icon atGridPath:(id)path options:(unsigned long long)o { [gDRHome addObject:icon]; return icon; }
@end
@interface TDRModel : NSObject
@property (nonatomic, strong) TDRRoot *rootFolder;
@property (nonatomic) int saves;
@end
@implementation TDRModel
- (void)markIconStateDirty {}
- (BOOL)saveIconStateIfNeeded { self.saves++; return YES; }
@end
// SpringBoard's icon drag: the session's context names the dragged icons and the icon view it began on
@interface TDRIconView : NSObject
@property (nonatomic, strong) id icon;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, strong) NSArray *origItems;   // (SpringBoard's own items of its menu)
@end
@implementation TDRIconView
@end
@interface TDRDragContext : NSObject
@property (nonatomic, strong) NSSet *draggedIcons;
@property (nonatomic, strong) TDRIconView *primaryIconView;
@end
@implementation TDRDragContext
@end
@interface TDRSession : NSObject
@property (nonatomic, strong) TDRDragContext *context;
@end
@implementation TDRSession
@end
@interface TDRDrags : NSObject
@end
@implementation TDRDrags
- (id)iconDragContextForDropSession:(TDRSession *)s { return s.context; }
- (BOOL)isManagingTemporarilyRemovedIcon:(id)icon { return NO; }
@end
@interface TDRManager : NSObject
@property (nonatomic, strong) TDRModel *iconModel;
@property (nonatomic, strong) TDRDrags *iconDragManager;
@end
@implementation TDRManager
- (unsigned long long)gridCellInfoOptions { return 0; }
@end
static TDRManager *gDRManager;
@interface SBIconController : NSObject
@end
@implementation SBIconController
+ (id)sharedInstance { return self; }
+ (id)iconManager { return gDRManager; }
@end
// the menu's item (SBSApplicationShortcutItem: the real code fills it by key)
@interface SBSApplicationShortcutItem : NSObject
@property (nonatomic, copy) NSString *type, *localizedTitle, *bundleIdentifierToLaunch;
@property (nonatomic, strong) id icon;
@end
@implementation SBSApplicationShortcutItem
@end
// SBIconView: the hooked class (its own -applicationShortcutItems is SpringBoard's: DROrig)
@interface SBIconView : TDRIconView
@end
@implementation SBIconView
@end
static id DROrig(id me) {
    if (object_isClass(me)) { [gDRLog addObject:@"(SpringBoard's own shortcut)"]; return nil; }
    return ((TDRIconView *)me).origItems;
}
// MacStatusBar's Activity Monitor in the Dock (ActMonDock.h): found with dlsym, as on the device
static int gDRActMonRemoved;
__attribute__((visibility("default"), used)) BOOL MSBDActMonDockRemove(void) { gDRActMonRemoved++; return YES; }

// ---- the bin (TrashIcon.m's DMTrashIconView: its drop side, the rest stands in)
@interface DMTrashIconView : NSObject
@property (nonatomic) BOOL hover;
@property (nonatomic, strong) id pendingIcon;
- (void)dm_setDropHover:(BOOL)on;
@end

#include "dr-globals.inc"   // (Dock.x's settings, with their defaults)
#include "dr-dock.inc"      // (the real DMObj ... DMRemoveFromDock, DMIsOwnAppIcon, the shared test where the file has it, DMTrashRemoveIconFromDock,
                            //  DMTrashIconDragInfo, DMLoadPrefs)
@implementation SBIconView (DRHook)
#include "dr-menu.inc"      // (the real -applicationShortcutItems and +activateShortcut:withBundleIdentifier:forIconView:)
@end
@implementation DMTrashIconView
- (void)dm_setDropHover:(BOOL)on { self.hover = on; }
#include "dr-trash.inc"     // (the real canHandleSession, performDrop, sessionDidEnd)
@end

// ---- the checks
static int gFails;
static void ok(BOOL c, NSString *what) { printf("%s  %s\n", c ? "PASS" : "FAIL", what.UTF8String); if (!c) gFails++; }
static void runFor(double s) {   // (the main queue: the removal 0.35 s after the drag, the menu's action after the menu)
    CFTimeInterval end = CACurrentMediaTime() + s;
    while (CACurrentMediaTime() < end) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
}
static TDRIcon *gNotes, *gAppMail, *gActMon, *gMaps;
// The settings (nil: never set) read the way the Dock reads them, and a Dock with Notes, Mail and Activity Monitor kept in it; Maps on the Home Screen.
static void reset(id partSwitch, id magnifyIcons) {
    gDRLog = [NSMutableArray array]; gDRActMonRemoved = 0;
    gDRDock = [NSMutableDictionary dictionary]; gDRMSB = [NSMutableDictionary dictionary];
    if (partSwitch) gDRDock[@"tweakEnabled"] = partSwitch;
    if (magnifyIcons) gDRDock[@"enabled"] = magnifyIcons;
    DMLoadPrefs();
    gNotes = [TDRIcon new]; gNotes.applicationBundleID = gNotes.leafIdentifier = @"com.apple.mobilenotes";
    gAppMail = [TDRIcon new]; gAppMail.applicationBundleID = gAppMail.leafIdentifier = @"com.apple.mobilemail";
    gActMon = [TDRIcon new]; gActMon.leafIdentifier = @"com.besiktasliseba.macstatusbar.activitymonitor";
    gMaps = [TDRIcon new]; gMaps.applicationBundleID = gMaps.leafIdentifier = @"com.apple.Maps";
    gDRDockIcons = [@[gNotes, gAppMail, gActMon] mutableCopy]; gDRHome = [@[gMaps] mutableCopy];
    gDRManager = [TDRManager new]; gDRManager.iconModel = [TDRModel new]; gDRManager.iconModel.rootFolder = [TDRRoot new];
    gDRManager.iconModel.rootFolder.dock = [TDRDockList new]; gDRManager.iconDragManager = [TDRDrags new];
}
static SBIconView *iconView(TDRIcon *icon, NSString *location) {
    SBIconView *v = [SBIconView new]; v.icon = icon; v.location = location;
    SBSApplicationShortcutItem *share = [SBSApplicationShortcutItem new]; share.type = @"com.apple.springboardhome.application-shortcut-item.share"; share.localizedTitle = @"Share App";
    v.origItems = @[share];
    return v;
}
static SBSApplicationShortcutItem *removeItem(SBIconView *v) {   // (the menu's Remove from Dock, if it has one)
    for (SBSApplicationShortcutItem *it in [v applicationShortcutItems]) if ([it.type isEqual:kDMRemoveFromDockType]) return it;
    return nil;
}
// The menu's Remove from Dock chosen (as SpringBoard calls it), the main queue run: the app has left the Dock for the Home Screen
static BOOL chooseRemove(SBIconView *v) {
    SBSApplicationShortcutItem *it = removeItem(v);
    if (!it) return NO;
    [SBIconView activateShortcut:it withBundleIdentifier:it.bundleIdentifierToLaunch forIconView:v];
    runFor(0.2);
    return ![gDRDockIcons containsObject:v.icon] && [gDRHome containsObject:v.icon];
}
// One of SpringBoard's icon drags, begun on that icon at that location, dropped on the bin; its answer to the drag over it in *took
static void dropOnBin(TDRIcon *icon, NSString *location, BOOL *took) {
    TDRSession *s = [TDRSession new]; s.context = [TDRDragContext new];
    s.context.draggedIcons = [NSSet setWithObject:icon]; s.context.primaryIconView = [TDRIconView new];
    s.context.primaryIconView.icon = icon; s.context.primaryIconView.location = location;
    DMTrashIconView *bin = [DMTrashIconView new];
    BOOL yes = [bin dropInteraction:nil canHandleSession:(id)s];
    if (took) *took = yes;
    if (yes) [bin dropInteraction:nil performDrop:(id)s];   // (UIKit performs a drop only on a bin that takes the session)
    [bin dropInteraction:nil sessionDidEnd:(id)s];
    runFor(0.6);
}
static BOOL leftForHome(TDRIcon *icon) { return ![gDRDockIcons containsObject:icon] && [gDRHome containsObject:icon]; }
#define DOCK @"SBIconLocationFloatingDock"

int main(void) { @autoreleasepool {
    BOOL took = NO;
    // 1. Magnify Icons off, the Dock part on (its switch never set: on) -- the audit's case
    printf("-- Settings > Dock > Magnify Icons off, the Dock part on\n");
    reset(nil, @NO);
    ok(!gEnabled && gTweakOn, @"the settings read as the device has them: no magnification, the Dock part on");
    SBIconView *notes = iconView(gNotes, DOCK);
    SBSApplicationShortcutItem *rm = removeItem(notes);
    ok(rm && [rm.localizedTitle isEqualToString:@"Remove from Dock"] && [rm.bundleIdentifierToLaunch isEqualToString:@"com.apple.mobilenotes"] && [notes applicationShortcutItems].count == 2,
       @"a kept Dock app's menu has Remove from Dock, after SpringBoard's own items");
    ok(chooseRemove(notes) && gDRManager.iconModel.saves == 1, @"  ... choosing it moves the app to the Home Screen (the icon state saved)");
    reset(nil, @NO);
    dropOnBin(gAppMail, DOCK, &took);
    ok(took, @"the Trash takes a kept Dock app dragged onto it");
    ok(leftForHome(gAppMail) && [gDRLog containsObject:@"[trash] the app dropped on the bin left the Dock (to the Home Screen)"],
       @"  ... and the app dropped on it leaves the Dock for the Home Screen, as the bin showed");
    reset(nil, @NO);
    dropOnBin(gActMon, DOCK, &took);
    ok(took && gDRActMonRemoved == 1, @"Activity Monitor kept in the Dock, dropped on the Trash: taken, and it leaves the Dock (Mac Status Bar's own removal)");

    // 2. Unchanged: Magnify Icons on
    printf("-- unchanged: Magnify Icons on, the Dock part on\n");
    reset(@YES, @YES);
    ok(chooseRemove(iconView(gNotes, DOCK)), @"the menu's Remove from Dock moves the app to the Home Screen");
    reset(@YES, @YES);
    dropOnBin(gAppMail, DOCK, &took);
    ok(took && leftForHome(gAppMail), @"an app dropped on the Trash leaves the Dock for the Home Screen");

    // 3. The Dock part off (its own switch stored off): the Dock as iPadOS has it, nothing of ours; the bin takes no drop it would refuse
    printf("-- the Dock part off (its own switch), Magnify Icons on in its settings\n");
    reset(@NO, @YES);
    ok(!gTweakOn, @"the settings read as the device has them: the Dock part off");
    ok(!removeItem(iconView(gNotes, DOCK)) && [iconView(gNotes, DOCK) applicationShortcutItems].count == 1, @"no Remove from Dock in the menu: SpringBoard's own items only");
    dropOnBin(gAppMail, DOCK, &took);
    ok(!took, @"the Trash does not take the app's drag (it used to: the bin lit and took the app, then the removal refused it)");
    ok([gDRDockIcons containsObject:gAppMail] && ![gDRHome containsObject:gAppMail], @"  ... the app stays in the Dock");
    reset(@NO, @YES);
    DMTrashIconView *bin = [DMTrashIconView new];
    TDRSession *s = [TDRSession new]; s.context = [TDRDragContext new]; s.context.draggedIcons = [NSSet setWithObject:gAppMail];
    s.context.primaryIconView = [TDRIconView new]; s.context.primaryIconView.icon = gAppMail; s.context.primaryIconView.location = DOCK;
    [bin dropInteraction:nil performDrop:(id)s];
    ok(!bin.pendingIcon, @"  ... and a drop handed to it all the same keeps nothing to remove (it used to keep the app, then refuse it)");

    // 4. The bin and the removal agree, for every way the two switches can be set
    printf("-- the bin's answer and the removal agree\n");
    NSArray *parts = @[[NSNull null], @YES, @NO], *mags = @[[NSNull null], @YES, @NO];
    NSMutableArray *bad = [NSMutableArray array];
    for (id p in parts) for (id m in mags) {
        reset(p == [NSNull null] ? nil : p, m == [NSNull null] ? nil : m);
        dropOnBin(gAppMail, DOCK, &took);
        BOOL left = leftForHome(gAppMail);
        if (took != left) [bad addObject:[NSString stringWithFormat:@"part %@ magnify %@: taken %d, left %d", p, m, took, left]];
        if (left != gTweakOn) [bad addObject:[NSString stringWithFormat:@"part %@ magnify %@: left %d with the Dock part %d", p, m, left, gTweakOn]];
    }
    ok(!bad.count, [NSString stringWithFormat:@"a drop the bin takes is one the app leaves the Dock with, and it leaves exactly while the Dock part is on (%@)", bad.count ? [bad componentsJoinedByString:@"; "] : @"9 of 9"]);

    // 5. Unchanged, with Magnify Icons off: only an app kept in the Dock itself
    printf("-- unchanged: only an app kept in the Dock itself (Magnify Icons off)\n");
    reset(nil, @NO);
    ok(!removeItem(iconView(gMaps, @"SBIconLocationRoot")), @"a Home Screen app's menu has no Remove from Dock");
    ok(!removeItem(iconView(gMaps, @"SBIconLocationFloatingDockSuggestions")), @"a recent app's menu (the Dock's suggestions) has none");
    dropOnBin(gMaps, @"SBIconLocationRoot", &took);
    ok(!took && [gDRHome containsObject:gMaps], @"a Home Screen app dragged onto the Trash is not taken");
    return gFails;
}}
