// test-dockremove.m -- Mac test (Mac Catalyst: UIKit on the Mac) of Remove from Dock and an app dropped on the Dock's Trash (1.8.7.3, audit M6 of
// 1.8.7.2): both follow the Dock part's own switch, not Magnify Icons. Both used to ask the magnification switch ("enabled", a leftover from when it
// was the Dock's main switch), so with Magnify Icons off a kept Dock app's menu had no Remove from Dock, and the Trash took an app dropped on it (the
// bin lit, the app shrank into it) and then left it in the Dock; Activity Monitor's icon too. The bin's drop side never asked any switch, so with the
// Dock part off it took a drop the removal then refused.
// And (1.8.7.4) iPadOS 15's icon drag: an app dragged from the Dock onto the Trash stayed in the Dock (the M1, 15.6.1: "[trash] an icon drag over the
// bin: 1 icon(s), app 0, folder 0, from the Dock 1, kept in the Dock 0 -> not taken"). 15's drag takes the icon out of its list and puts a placeholder
// (SBPlaceholderIcon) in its place, and its context can name that placeholder, not the app; 15 has no -isManagingTemporarilyRemovedIcon:. The drag
// shapes below: 16 to 18's (the icon named, kept in the Dock's list or taken out of it with the drag manager's record) and 15's (15.5's SpringBoardHome).
// And (1.8.7.5, TRASH15B: the M1's 15.6.1 trace) the removal on 15: -[SBFolder insertIcon:atGridPath:options:] places the app and returns nil, so the
// add after it placed the app a second time; where the add went to another page the app was on the Home Screen twice ([2][23] and [3][3], SpringBoard's
// numberOfIcons 78 -> 79). And Edit Home Screen, which SpringBoard turns on as the icon drag begins, stayed on for 30 s after a drop on the bin. The
// Home Screen below is pages with room (the root folder's -lists), SpringBoard's list insert taking a copy out of its own list only, its add going
// to the first free place, and an icon manager whose Edit Home Screen the drag's begin turns on.
// Runs the real code, cut out of the sources by test-dockremove.sh: dock/Dock.x's globals and DMLoadPrefs (the settings as the Dock reads them), the
// menu's Remove from Dock (-applicationShortcutItems, +activateShortcut:...), the removal (DMTrashRemoveIconFromDock, DMRemoveFromDock and the icon
// model's look-ups), what SpringBoard's icon drag carries (DMTrashIconDragInfo), the drag's begin (-[SBIconView dragInteraction:sessionWillBegin:]
// as hooked) and Edit Home Screen's end (DMTrashDragTurnedEditingOn, DMTrashEndDragEditing) where the file has them, and dock/TrashIcon.m's drop side
// (canHandleSession, performDrop, sessionDidEnd), with the real common/DockTrash.h rules. SpringBoard's side (its icon model, its icon drag, the
// settings) is the stand-ins below.
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
void DMDockColorLoad(BOOL tweakOn) {}   // (Dock Background, 1.8.8.1: DMLoadPrefs reads its keys in DockColor.m)
static void DMDispReload(void) {}

// ---- SpringBoard's icon model: the Dock's own list and the Home Screen
@interface TDRIcon : NSObject
@property (nonatomic, copy) NSString *applicationBundleID, *leafIdentifier;
@property (nonatomic) BOOL isFolderIcon;
@end
@implementation TDRIcon
- (BOOL)isPlaceholder { return NO; }   // (SBIcon's own, 15 to 18)
@end
// iPadOS 15's placeholder for an icon a drag took out of its list (15.5's SBPlaceholderIcon: an SBIcon, so SBIcon's -applicationBundleID (nil) and
// -isFolderIcon; -referencedIcon, the icon it stands for)
@interface SBPlaceholderIcon : NSObject
@property (nonatomic, strong) id referencedIcon;
@end
@implementation SBPlaceholderIcon
- (NSString *)applicationBundleID { return nil; }
- (NSString *)leafIdentifier { return nil; }
- (BOOL)isFolderIcon { return NO; }
- (BOOL)isPlaceholder { return YES; }
@end
static NSMutableArray *gDRDockIcons;
@interface TDRDockList : NSObject
@end
@implementation TDRDockList
- (NSArray *)icons { return [gDRDockIcons copy]; }
- (unsigned long long)numberOfIcons { return gDRDockIcons.count; }
- (BOOL)directlyContainsIcon:(id)icon { return [gDRDockIcons containsObject:icon]; }
- (void)removeIcons:(NSArray *)icons { [gDRDockIcons removeObjectsInArray:icons]; }
- (void)insertIcons:(NSArray *)icons atIndex:(NSUInteger)i options:(unsigned long long)o { [gDRDockIcons insertObjects:icons atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(i, icons.count)]]; }
@end
// The Home Screen's pages (the root folder's -lists, IconState's iconLists): each with its room (the M1: the desktop page 16, the others 24)
@interface TDRPage : NSObject
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic) NSUInteger room;
@end
@implementation TDRPage
- (NSArray *)icons { return [self.items copy]; }
- (unsigned long long)numberOfIcons { return self.items.count; }
@end
static NSMutableArray<TDRPage *> *gDRPages;
@interface TDRPath : NSObject   // (SBIconGridPath: a page and a place on it)
@property (nonatomic) NSUInteger page, cell;
@end
@implementation TDRPath
- (NSString *)description { return [NSString stringWithFormat:@"page %lu, place %lu", (unsigned long)self.page, (unsigned long)self.cell]; }
@end
static BOOL gDRInsertAnswersNil;      // (iPadOS 15: -[SBFolder insertIcon:atGridPath:options:] places the icon and returns nil -- the M1's 15.6.1 trace)
static BOOL gDRInsertPlacesNothing;   // (an insert that places nothing: the add's own case)
static int gDRPlacements;             // (inserts of the app into a page, by any path)
// SpringBoard's list insert (-[SBIconListModel insertIcon:atGridCellIndex:...]): a copy this page holds already is taken out of it first
// (-removeIconFromOtherPositionsInHierarchy:forInsertingAtIndex:removeIfAlreadyContained:, the trace's 6 drops); another page's copy is not (1.8.7.4's
// device check: [2][23] and [3][3], 79 icons)
static void DRPageInsert(TDRPage *page, id icon, NSUInteger cell) {
    [page.items removeObjectIdenticalTo:icon];
    [page.items insertObject:icon atIndex:MIN(cell, page.items.count)];
    gDRPlacements++;
}
@interface TDRRoot : NSObject
@property (nonatomic, strong) TDRDockList *dock;
@end
@implementation TDRRoot
- (NSArray *)lists { return [gDRPages copy]; }
- (id)gridPathForFirstFreeSlotAvoidingFirstList:(BOOL)avoid listGridCellInfoOptions:(unsigned long long)o {
    for (NSUInteger i = avoid ? 1 : 0; i < gDRPages.count; i++) if (gDRPages[i].items.count < gDRPages[i].room) {
        TDRPath *p = [TDRPath new]; p.page = i; p.cell = gDRPages[i].items.count; return p;
    }
    return nil;
}
- (id)insertIcon:(id)icon atGridPath:(TDRPath *)path options:(unsigned long long)o {
    if (gDRInsertPlacesNothing || ![path isKindOfClass:[TDRPath class]] || path.page >= gDRPages.count) return nil;
    DRPageInsert(gDRPages[path.page], icon, path.cell);
    return gDRInsertAnswersNil ? nil : icon;
}
// SpringBoard's add: the first free place as the pages are now (the app's own copy counted), its own list insert
- (id)addIcon:(id)icon options:(unsigned long long)o listGridCellInfoOptions:(unsigned long long)g {
    TDRPath *p = [self gridPathForFirstFreeSlotAvoidingFirstList:NO listGridCellInfoOptions:g];
    if (!p) return nil;
    DRPageInsert(gDRPages[p.page], icon, p.cell);
    return icon;
}
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
static BOOL gDRDragTurnsEditingOn = YES;   // (SpringBoard's drag begin: -[SBIconDragManager iconViewWillBeginDrag:session:] -> -setEditing:fromIconView: YES)
@class TDRManager;
static TDRManager *gDRManager;
static void DRSpringBoardDragBegins(void);
@interface TDRIconView : NSObject
@property (nonatomic, strong) id icon;
@property (nonatomic, copy) NSString *location;
@property (nonatomic, strong) NSArray *origItems;   // (SpringBoard's own items of its menu)
@end
@implementation TDRIconView
- (void)dragInteraction:(id)interaction sessionWillBegin:(id)session { DRSpringBoardDragBegins(); }   // (SpringBoard's own: Edit Home Screen on)
@end
@interface TDRDragSession : NSObject   // (UIKit's drag session, the drop session's -localDragSession)
@end
@implementation TDRDragSession
@end
@interface TDRDragContext : NSObject
@property (nonatomic, strong) NSSet *draggedIcons;
@property (nonatomic, strong) TDRIconView *primaryIconView;
@end
@implementation TDRDragContext
@end
@interface TDRSession : NSObject
@property (nonatomic, strong) TDRDragContext *context;
@property (nonatomic, strong) id localDragSession;
@end
@implementation TDRSession
@end
static BOOL gDRDragBusy;   // (SpringBoard's drag manager tracks another icon drag)
@interface TDRDrags : NSObject   // (16 to 18: the icons a drag took out of their list, while it lasts)
@property (nonatomic, strong) NSMutableSet *temporarilyRemoved;
@end
@implementation TDRDrags
- (id)iconDragContextForDropSession:(TDRSession *)s { return s.context; }
- (BOOL)isManagingTemporarilyRemovedIcon:(id)icon { return [self.temporarilyRemoved containsObject:icon]; }
- (bool)isTrackingActiveOrDroppingIconDrags { return gDRDragBusy; }
@end
@interface TDRDrags15 : NSObject   // (iPadOS 15's drag manager, 15.5's SpringBoardHome: no -isManagingTemporarilyRemovedIcon:)
@end
@implementation TDRDrags15
- (id)iconDragContextForDropSession:(TDRSession *)s { return s.context; }
- (bool)isTrackingActiveOrDroppingIconDrags { return gDRDragBusy; }
@end
static int gDREditingEnded;   // (-setEditing: NO calls)
@interface TDRManager : NSObject   // (SBHIconManager: Edit Home Screen's switch in its 15-18 type, v20@0:8B16)
@property (nonatomic, strong) TDRModel *iconModel;
@property (nonatomic, strong) id iconDragManager;
@property (nonatomic) bool editingOn;
@end
@implementation TDRManager
- (unsigned long long)gridCellInfoOptions { return 0; }
- (bool)isEditing { return self.editingOn; }
- (void)setEditing:(bool)editing { self.editingOn = editing; if (!editing) gDREditingEnded++; }
@end
static void DRSpringBoardDragBegins(void) { if (gDRDragTurnsEditingOn) gDRManager.editingOn = YES; }
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
@property (nonatomic) BOOL pendingEndsEditing;
- (void)dm_setDropHover:(BOOL)on;
@end

#include "dr-globals.inc"   // (Dock.x's settings, with their defaults)
#include "dr-dock.inc"      // (the real DMObj ... DMRemoveFromDock, DMIsOwnAppIcon, the shared test where the file has it, DMTrashRemoveIconFromDock,
                            //  DMTrashIconDragInfo, DMLoadPrefs)
@implementation SBIconView (DRHook)
#include "dr-menu.inc"      // (the real -applicationShortcutItems and +activateShortcut:withBundleIdentifier:forIconView:)
#include "dr-drag.inc"      // (the real -dragInteraction:sessionWillBegin: as hooked, where the file has it; SpringBoard's own begin is its %orig)
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
// The Home Screen's pages, as the M1's in 1.8.7.4's device check: the desktop page full (16 of 16, Maps among them), 24 of 24, then page 2 with
// one place left (23 of 24) and the last page with 3 -- the first free place is page 2's last (ours, "gridCellIndex: 23") and the add after it
// finds the last page's end (the second copy at [3][3]). lastPageFirst: page 2 full too, so ours goes to the last page and an add after it to the
// same page (the trace's drops 3 to 6).
static void layoutPages(BOOL lastPageFirst) {
    gDRPages = [NSMutableArray array];
    NSArray *fill = @[@16, @24, lastPageFirst ? @24 : @23, @3], *room = @[@16, @24, @24, @24];
    int k = 0;
    for (NSUInteger i = 0; i < fill.count; i++) {
        TDRPage *pg = [TDRPage new]; pg.room = [room[i] unsignedIntegerValue]; pg.items = [NSMutableArray array];
        for (NSUInteger j = 0; j < [fill[i] unsignedIntegerValue]; j++) {
            if (i == 0 && j == 4) { [pg.items addObject:gMaps]; continue; }
            TDRIcon *f = [TDRIcon new]; f.applicationBundleID = f.leafIdentifier = [NSString stringWithFormat:@"app.%d", k++]; [pg.items addObject:f];
        }
        [gDRPages addObject:pg];
    }
}
static NSUInteger homeCount(id icon) {   // (the icon's places on the Home Screen's pages)
    NSUInteger n = 0;
    for (TDRPage *pg in gDRPages) for (id x in pg.items) if (x == icon) n++;
    return n;
}
static NSUInteger numberOfIcons(void) {   // (SpringBoard's own count: every page's -numberOfIcons and the Dock's)
    NSUInteger n = gDRDockIcons.count;
    for (TDRPage *pg in gDRPages) n += pg.items.count;
    return n;
}
static NSString *placesOf(id icon) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSUInteger i = 0; i < gDRPages.count; i++) [gDRPages[i].items enumerateObjectsUsingBlock:^(id x, NSUInteger j, BOOL *stop) { if (x == icon) [a addObject:[NSString stringWithFormat:@"[%lu][%lu]", (unsigned long)i, (unsigned long)j]]; }];
    if ([gDRDockIcons containsObject:icon]) [a addObject:@"Dock"];
    return a.count ? [a componentsJoinedByString:@" "] : @"nowhere";
}
// The settings (nil: never set) read the way the Dock reads them, and a Dock with Notes, Mail and Activity Monitor kept in it; Maps on the Home Screen.
static void reset(id partSwitch, id magnifyIcons) {
    gDRLog = [NSMutableArray array]; gDRActMonRemoved = 0;
    gDRInsertAnswersNil = gDRInsertPlacesNothing = gDRDragBusy = NO; gDRDragTurnsEditingOn = YES; gDRPlacements = gDREditingEnded = 0;
    gDRDock = [NSMutableDictionary dictionary]; gDRMSB = [NSMutableDictionary dictionary];
    if (partSwitch) gDRDock[@"tweakEnabled"] = partSwitch;
    if (magnifyIcons) gDRDock[@"enabled"] = magnifyIcons;
    DMLoadPrefs();
    gNotes = [TDRIcon new]; gNotes.applicationBundleID = gNotes.leafIdentifier = @"com.apple.mobilenotes";
    gAppMail = [TDRIcon new]; gAppMail.applicationBundleID = gAppMail.leafIdentifier = @"com.apple.mobilemail";
    gActMon = [TDRIcon new]; gActMon.leafIdentifier = @"com.besiktasliseba.macstatusbar.activitymonitor";
    gMaps = [TDRIcon new]; gMaps.applicationBundleID = gMaps.leafIdentifier = @"com.apple.Maps";
    gDRDockIcons = [@[gNotes, gAppMail, gActMon] mutableCopy];
    layoutPages(NO);
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
    return ![gDRDockIcons containsObject:v.icon] && homeCount(v.icon) == 1;
}
// The shape of SpringBoard's icon drag while it is over the bin: what its context names, where the icon is, what the drag manager answers
typedef NS_ENUM(int, DRShape) {
    DR16Kept,     // 16 to 18: the icon view and the drag's icons name the icon, still in its list
    DR16Taken,    // 16 to 18: ... taken out of its list while the drag lasts, the drag manager's record says so
    DR15View,     // 15: the icon view names the placeholder put in the icon's place, the drag's icons the icon; the placeholder left the Dock's list
                  //     with the drag (the M1's log: "app 0 ... kept in the Dock 0")
    DR15Set,      // 15: the icon view names nothing, the drag's icons the placeholder; the placeholder left the Dock's list with the drag
    DR15InList,   // 15: the icon view and the drag's icons name the placeholder, still in the icon's place in its list
};
static NSString *shapeName(DRShape s) {
    return @[@"16-18, the icon in its list", @"16-18, the icon taken out of its list", @"15, the icon view names the placeholder",
             @"15, the drag's icons name the placeholder", @"15, the placeholder still in the Dock's list"][s];
}
static BOOL gDRPendingWasApp;   // (the bin's drop kept the app itself for the removal, not a placeholder)
static BOOL gDREditingBefore;      // (Edit Home Screen was on before the drag began: the user's own)
static BOOL gDRDragUnseen;         // (a drop whose drag session is not the one whose begin was seen)
static BOOL gDRBusyAtEnd;          // (another icon drag under way when the bin's removal runs)
static NSUInteger gDRCountBefore;  // (SpringBoard's numberOfIcons before the drag)
static NSMutableArray *listHolding(id icon) {
    if ([gDRDockIcons containsObject:icon]) return gDRDockIcons;
    for (TDRPage *pg in gDRPages) if ([pg.items containsObject:icon]) return pg.items;
    return nil;
}
// One of SpringBoard's icon drags of that shape, begun on that icon at that location, dropped on the bin; its answer to the drag over it in *took.
// The drag begins on the icon view (SpringBoard turns Edit Home Screen on there). At the drag's end SpringBoard puts a taken icon back in its place
// (on 15 the placeholder's place) before the bin's removal runs. iPadOS 15's shapes: its insert answers nil (the M1's trace).
static void dropOnBinShaped(TDRIcon *icon, NSString *location, DRShape shape, BOOL *took) {
    TDRSession *s = [TDRSession new]; s.context = [TDRDragContext new];
    SBIconView *view = [SBIconView new]; view.location = location; view.icon = icon;
    s.context.primaryIconView = view;
    gDRInsertAnswersNil = shape >= DR15View;
    gDRCountBefore = numberOfIcons();
    gDRManager.editingOn = gDREditingBefore;
    TDRDragSession *drag = [TDRDragSession new];
    [view dragInteraction:nil sessionWillBegin:drag];   // (the drag begins: SpringBoard's own begin, under ours where the file hooks it)
    s.localDragSession = gDRDragUnseen ? [TDRDragSession new] : drag;
    view.icon = nil;   // (what the context's icon view names: below, by shape)
    NSMutableArray *list = listHolding(icon);
    NSUInteger at = list ? [list indexOfObject:icon] : NSNotFound;
    if (shape == DR16Kept || shape == DR16Taken) {
        s.context.primaryIconView.icon = icon; s.context.draggedIcons = [NSSet setWithObject:icon];
        if (shape == DR16Taken) { [list removeObject:icon]; ((TDRDrags *)gDRManager.iconDragManager).temporarilyRemoved = [NSMutableSet setWithObject:icon]; }
    } else {
        gDRManager.iconDragManager = [TDRDrags15 new];
        SBPlaceholderIcon *ph = [SBPlaceholderIcon new]; ph.referencedIcon = icon;
        if (list && at != NSNotFound) { if (shape == DR15InList) list[at] = ph; else [list removeObjectAtIndex:at]; }
        s.context.primaryIconView.icon = shape == DR15Set ? nil : ph;
        s.context.draggedIcons = [NSSet setWithObject:shape == DR15View ? icon : ph];
    }
    DMTrashIconView *bin = [DMTrashIconView new];
    BOOL yes = [bin dropInteraction:nil canHandleSession:(id)s];
    if (took) *took = yes;
    if (yes) [bin dropInteraction:nil performDrop:(id)s];   // (UIKit performs a drop only on a bin that takes the session)
    gDRPendingWasApp = bin.pendingIcon == icon;
    if (shape != DR16Kept && list && at != NSNotFound) {   // (SpringBoard's drag ends: the icon back in its place)
        if (shape == DR15InList) list[at] = icon; else [list insertObject:icon atIndex:MIN(at, list.count)];
        if ([gDRManager.iconDragManager isKindOfClass:[TDRDrags class]]) [((TDRDrags *)gDRManager.iconDragManager).temporarilyRemoved removeAllObjects];
    }
    gDRDragBusy = gDRBusyAtEnd;
    [bin dropInteraction:nil sessionDidEnd:(id)s];
    runFor(0.6);
    gDRDragBusy = NO;
}
static void dropOnBin(TDRIcon *icon, NSString *location, BOOL *took) { dropOnBinShaped(icon, location, DR16Kept, took); }
static BOOL leftForHome(TDRIcon *icon) { return ![gDRDockIcons containsObject:icon] && homeCount(icon) == 1; }   // (one place: 1.8.7.5)
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
    ok([gDRDockIcons containsObject:gAppMail] && !homeCount(gAppMail), @"  ... the app stays in the Dock");
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
    ok(!took && homeCount(gMaps) == 1, @"a Home Screen app dragged onto the Trash is not taken");

    // 6. iPadOS 15's icon drag (1.8.7.4): its context names SpringBoard's placeholder for the app -- Magnify Icons off and on
    NSString *const leftLine = @"[trash] the app dropped on the bin left the Dock (to the Home Screen)";
    NSString *const phLine = @"[trash] the drag names SpringBoard's placeholder, not the icon (iPadOS 15): read as the icon it stands for (TDRIcon)";
    for (int mag = 0; mag < 2; mag++) {
        printf("-- iPadOS 15's icon drag, Magnify Icons %s\n", mag ? "on" : "off");
        for (DRShape sh = DR15View; sh <= DR15InList; sh++) {
            if (mag) reset(@YES, @YES); else reset(nil, @NO);
            dropOnBinShaped(gAppMail, DOCK, sh, &took);
            NSString *seen = gDRLog.count ? [gDRLog firstObject] : @"(no line)";
            for (NSString *l in gDRLog) if ([l hasPrefix:@"[trash] an icon drag over the bin"]) seen = l;
            ok(took && gDRPendingWasApp && leftForHome(gAppMail) && [gDRLog containsObject:leftLine] && [gDRLog containsObject:phLine],
               [NSString stringWithFormat:@"%@: the Trash takes the Dock app, keeps the app itself (not the placeholder), and it leaves the Dock for the Home Screen (%@)", shapeName(sh), seen]);
        }
    }
    reset(nil, @NO);
    dropOnBinShaped(gActMon, DOCK, DR15View, &took);
    ok(took && gDRActMonRemoved == 1, @"15: Activity Monitor kept in the Dock, dropped on the Trash: taken, and it leaves the Dock");
    reset(nil, @NO);
    dropOnBinShaped(gMaps, @"SBIconLocationRoot", DR15View, &took);
    ok(!took && homeCount(gMaps) == 1, @"15: a Home Screen app dragged onto the Trash is not taken (it stays on the Home Screen)");
    reset(nil, @NO);
    dropOnBinShaped(gAppMail, @"SBIconLocationFloatingDockSuggestions", DR15View, &took);
    ok(!took && [gDRDockIcons containsObject:gAppMail], @"15: an app dragged from the Dock's recents is not taken");
    reset(@NO, @YES);
    dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
    ok(!took && [gDRDockIcons containsObject:gAppMail] && !homeCount(gAppMail), @"15, the Dock part off: not taken, the app stays in the Dock");
    bad = [NSMutableArray array];
    for (id p in parts) for (id m in mags) {
        reset(p == [NSNull null] ? nil : p, m == [NSNull null] ? nil : m);
        dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
        BOOL left = leftForHome(gAppMail);
        if (took != left || left != gTweakOn) [bad addObject:[NSString stringWithFormat:@"part %@ magnify %@: taken %d, left %d, Dock part %d", p, m, took, left, gTweakOn]];
    }
    ok(!bad.count, [NSString stringWithFormat:@"15: a drop the bin takes is one the app leaves the Dock with, exactly while the Dock part is on (%@)", bad.count ? [bad componentsJoinedByString:@"; "] : @"9 of 9"]);

    // 7. Unchanged: 16 to 18's drag (the icon named; kept in its list, or taken out of it with the drag manager's record)
    printf("-- unchanged: 16 to 18's icon drag\n");
    for (int mag = 0; mag < 2; mag++) for (DRShape sh = DR16Kept; sh <= DR16Taken; sh++) {
        if (mag) reset(@YES, @YES); else reset(nil, @NO);
        dropOnBinShaped(gAppMail, DOCK, sh, &took);
        BOOL noPh = YES;
        for (NSString *l in gDRLog) if ([l containsString:@"placeholder"]) noPh = NO;
        ok(took && gDRPendingWasApp && leftForHome(gAppMail) && noPh, [NSString stringWithFormat:@"%@, Magnify Icons %@: taken, and the app leaves the Dock for the Home Screen (no placeholder read)", shapeName(sh), mag ? @"on" : @"off"]);
    }
    reset(nil, @NO);
    dropOnBinShaped(gMaps, @"SBIconLocationRoot", DR16Taken, &took);
    ok(!took && homeCount(gMaps) == 1, @"16-18: a Home Screen app taken out of its page by the drag is not taken");

    // 8. (1.8.7.5, TRASH15B) one icon in one place, numberOfIcons unchanged, Edit Home Screen off after the drop -- 15's removal (its insert answers nil)
    NSString *const offLine = @"[trash] Edit Home Screen, turned on by the drag, ended after the drop on the bin";
    for (int lastFirst = 0; lastFirst < 2; lastFirst++) {
        printf("-- 1.8.7.5: iPadOS 15's drop on the Trash, %s\n", lastFirst ? "ours on the last page, an add after it in the same page (the trace's drops)" : "ours fills page 2's last place, an add after it on the last page (1.8.7.4's device check)");
        NSMutableArray *twice = [NSMutableArray array], *count = [NSMutableArray array], *once = [NSMutableArray array], *edit = [NSMutableArray array], *line = [NSMutableArray array];
        for (int mag = 0; mag < 2; mag++) for (DRShape sh = DR15View; sh <= DR15InList; sh++) {
            if (mag) reset(@YES, @YES); else reset(nil, @NO);
            layoutPages(lastFirst);
            dropOnBinShaped(gAppMail, DOCK, sh, &took);
            NSString *c = [NSString stringWithFormat:@"%@, Magnify Icons %@", shapeName(sh), mag ? @"on" : @"off"];
            if (!took || !leftForHome(gAppMail)) [twice addObject:[NSString stringWithFormat:@"%@: %@", c, placesOf(gAppMail)]];
            if (numberOfIcons() != gDRCountBefore) [count addObject:[NSString stringWithFormat:@"%@: %lu -> %lu", c, (unsigned long)gDRCountBefore, (unsigned long)numberOfIcons()]];
            if (gDRPlacements != 1) [once addObject:[NSString stringWithFormat:@"%@: %d", c, gDRPlacements]];
            if (gDRManager.editingOn || ![gDRLog containsObject:offLine] || ![gDRLog containsObject:@"[trash] Edit Home Screen as the drag began: off; now on"]) [edit addObject:c];
            NSString *want = [NSString stringWithFormat:@"[dock] Remove from Dock: com.apple.mobilemail moved to the Home Screen at page %d, place %d", lastFirst ? 3 : 2, lastFirst ? 3 : 23];
            if (![gDRLog containsObject:want]) [line addObject:c];
            for (NSString *l in gDRLog) if ([l hasSuffix:@" times"]) [line addObject:l];
        }
        ok(!twice.count, [NSString stringWithFormat:@"the app is on the Home Screen once, out of the Dock (%@)", twice.count ? [twice componentsJoinedByString:@"; "] : @"6 of 6"]);
        ok(!count.count, [NSString stringWithFormat:@"  ... SpringBoard's numberOfIcons unchanged (%@)", count.count ? [count componentsJoinedByString:@"; "] : @"6 of 6"]);
        ok(!once.count, [NSString stringWithFormat:@"  ... placed once: no add after the insert that placed it (%@)", once.count ? [once componentsJoinedByString:@"; "] : @"6 of 6"]);
        ok(!edit.count, [NSString stringWithFormat:@"  ... Edit Home Screen, which the drag turned on, off after the drop, with its line (%@)", edit.count ? [edit componentsJoinedByString:@"; "] : @"6 of 6"]);
        ok(!line.count, [NSString stringWithFormat:@"  ... the log names the place ours chose, and never more than one (%@)", line.count ? [line componentsJoinedByString:@"; "] : @"6 of 6"]);
    }
    printf("-- 1.8.7.5: the menu's Remove from Dock on iPadOS 15 (the same removal)\n");
    for (int lastFirst = 0; lastFirst < 2; lastFirst++) {
        reset(nil, @NO); layoutPages(lastFirst); gDRInsertAnswersNil = YES;
        NSUInteger before = numberOfIcons();
        BOOL left = chooseRemove(iconView(gNotes, DOCK));
        ok(left && gDRPlacements == 1 && numberOfIcons() == before && !gDREditingEnded,
           [NSString stringWithFormat:@"%@: Notes once on the Home Screen (%@), placed once (%d), numberOfIcons %lu -> %lu, Edit Home Screen not touched", lastFirst ? @"ours on the last page" : @"ours fills page 2", placesOf(gNotes), gDRPlacements, (unsigned long)before, (unsigned long)numberOfIcons()]);
    }
    reset(nil, @NO); gDRInsertAnswersNil = YES;
    for (TDRPage *pg in gDRPages) while (pg.items.count < pg.room) { TDRIcon *f = [TDRIcon new]; f.applicationBundleID = f.leafIdentifier = @"app.fill"; [pg.items addObject:f]; }
    NSUInteger full = numberOfIcons();
    BOOL leftFull = chooseRemove(iconView(gNotes, DOCK));
    ok(!leftFull && [gDRDockIcons indexOfObject:gNotes] == 0 && !homeCount(gNotes) && numberOfIcons() == full && [gDRLog containsObject:@"[dock] Remove from Dock: no free place on the Home Screen, kept in the Dock"],
       @"no free place on any page: Notes stays in the Dock at its place, nothing added (unchanged)");
    reset(nil, @NO); gDRInsertAnswersNil = YES; gDRInsertPlacesNothing = YES;
    NSUInteger beforeAdd = numberOfIcons();
    BOOL leftAdd = chooseRemove(iconView(gNotes, DOCK));
    ok(leftAdd && gDRPlacements == 1 && numberOfIcons() == beforeAdd, [NSString stringWithFormat:@"an insert that places nothing: SpringBoard's add places Notes, once (%@; unchanged)", placesOf(gNotes)]);
    ok([gDRLog containsObject:@"[dock] Remove from Dock: com.apple.mobilenotes moved to the Home Screen at the place SpringBoard adds an app to"], @"  ... and the log says the add placed it, not the free place asked first");

    printf("-- 1.8.7.5: Edit Home Screen and the drop on the Trash (ours on the last page: one copy before the fix too)\n");
    reset(nil, @NO); layoutPages(YES); gDREditingBefore = YES;
    dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
    gDREditingBefore = NO;
    ok(took && leftForHome(gAppMail) && gDRManager.editingOn && !gDREditingEnded, @"Edit Home Screen the user had on before the drag stays on after the drop (the app leaves the Dock)");
    ok([gDRLog containsObject:@"[trash] Edit Home Screen as the drag began: on; now on"], @"  ... the log says it was on as the drag began");
    reset(nil, @NO); layoutPages(YES);
    dropOnBinShaped(gMaps, @"SBIconLocationRoot", DR15View, &took);
    ok(!took && gDRManager.editingOn && !gDREditingEnded, @"a drop the bin does not take (a Home Screen app): Edit Home Screen as SpringBoard leaves it");
    reset(nil, @NO); layoutPages(YES); gDRBusyAtEnd = YES;
    dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
    gDRBusyAtEnd = NO;
    ok(took && leftForHome(gAppMail) && gDRManager.editingOn && !gDREditingEnded && [gDRLog containsObject:@"[trash] another icon drag is under way: Edit Home Screen stays on"],
       @"another icon drag under way when the removal runs: Edit Home Screen stays on (ending it would cancel that drag)");
    reset(nil, @NO); layoutPages(YES); gDRDragUnseen = YES;
    dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
    gDRDragUnseen = NO;
    ok(took && leftForHome(gAppMail) && gDRManager.editingOn && !gDREditingEnded, @"a drop whose drag's begin was not seen: the app leaves the Dock, Edit Home Screen left as it is");
    ok([gDRLog containsObject:@"[trash] Edit Home Screen as the drag began: not seen; now on"], @"  ... the log says the drag's begin was not seen");
    reset(nil, @NO); layoutPages(YES);
    dropOnBinShaped(gActMon, DOCK, DR15View, &took);
    ok(took && gDRActMonRemoved == 1 && !gDRManager.editingOn && gDREditingEnded == 1, @"Activity Monitor dropped on the Trash: Edit Home Screen its drag turned on ends too");
    reset(nil, @NO); layoutPages(YES); gDRDragTurnsEditingOn = NO;
    dropOnBinShaped(gAppMail, DOCK, DR15View, &took);
    ok(took && leftForHome(gAppMail) && !gDRManager.editingOn && !gDREditingEnded, @"a drag that does not turn Edit Home Screen on: nothing ended, nothing changed");

    printf("-- 1.8.7.5: 16 to 18's drop on the Trash (the insert answers the icon, as this stand-in always had it)\n");
    NSMutableArray *moved = [NSMutableArray array], *ended = [NSMutableArray array];
    for (int mag = 0; mag < 2; mag++) for (DRShape sh = DR16Kept; sh <= DR16Taken; sh++) {
        if (mag) reset(@YES, @YES); else reset(nil, @NO);
        dropOnBinShaped(gAppMail, DOCK, sh, &took);
        NSString *c = [NSString stringWithFormat:@"%@, Magnify Icons %@", shapeName(sh), mag ? @"on" : @"off"];
        if (!(took && leftForHome(gAppMail) && gDRPlacements == 1 && numberOfIcons() == gDRCountBefore && [gDRLog containsObject:@"[dock] Remove from Dock: com.apple.mobilemail moved to the Home Screen at page 2, place 23"]))
            [moved addObject:[NSString stringWithFormat:@"%@: %@, placed %d times", c, placesOf(gAppMail), gDRPlacements]];
        if (gDRManager.editingOn || ![gDRLog containsObject:offLine]) [ended addObject:c];
    }
    ok(!moved.count, [NSString stringWithFormat:@"the removal unchanged: once at the first free place [2][23], placed once, numberOfIcons unchanged, the same line (%@)", moved.count ? [moved componentsJoinedByString:@"; "] : @"4 of 4"]);
    ok(!ended.count, [NSString stringWithFormat:@"Edit Home Screen, where their drag turns it on, off after the drop: the same rule as 15 (%@)", ended.count ? [ended componentsJoinedByString:@"; "] : @"4 of 4"]);
    return gFails;
}}
