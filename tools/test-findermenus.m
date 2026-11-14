// test-findermenus.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the menu bar's Finder menus (1.8.7.3, audit M7 of 1.8.7.2): File, View and
// Go's Finder rows are Finder's own. They are there while Finder is the app the bar names (a Finder window or Finder's Quick Look active), not
// while TextEdit, Activity Monitor or Display Settings is (native windows too), and every row acts on the Finder window the menu was opened for
// while that is still open and not minimized. Before: a file opened from Finder made the bar read "TextEdit File Edit View Go Window", and File >
// Close Window closed the Finder window behind (even a minimized one), Move to Trash trashed its selection and Go > Back moved a hidden window.
// Runs the real DMNativeActiveApp (statusbar/NativeWindow.h), DMFinderFront and, where they exist, DMFinderNamedInBar, DMFinderMenuCanAct and
// DMFinderMenuWindow (statusbar/Finder.h), DMDriveEjectTitle and DMDriveEjectMenuWith (statusbar/DriveEject.h), DMFinderRow, DMOpenFinderFileMenu,
// DMOpenFinderViewMenu, DMOpenFinderEditMenu, DMOpenGoMenu and the bar's finderTitles line (statusbar/StatusBar.x), cut out of the sources by
// test-findermenus.sh into fm-real.inc. SpringBoard's side is the stand-ins below: the native windows with NativeWindow.h's order and active-window
// rules (front last; show and activate bring a window to the end and make it active; minimize hides it and makes the last visible one active;
// close takes it out of the list and makes the last one active if it is visible; the layer hides with no visible window), a Finder window that
// records what it is asked, the menus' rows and the menu that would be shown.
#import <UIKit/UIKit.h>
#include "../common/FinderSort.h"

// ---- what the real code logs
static NSMutableArray<NSString *> *gKLog;
static void KLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DMLog(...) KLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name)

// ---- the menus: a row (title, enabled, handler, hint) and the menu that would be shown
@interface DMRow : NSObject
@property (nonatomic, copy) NSString *title, *hint;
@property (nonatomic, assign) BOOL enabled, checked, getBadge;
@property (nonatomic, copy) dispatch_block_t handler;
- (instancetype)initWithTitle:(NSString *)title enabled:(BOOL)enabled handler:(dispatch_block_t)handler;
@end
@implementation DMRow
- (instancetype)initWithTitle:(NSString *)title enabled:(BOOL)enabled handler:(dispatch_block_t)handler {
    if ((self = [super init])) { _title = [title copy]; _enabled = enabled; _handler = [handler copy]; }
    return self;
}
@end
static dispatch_block_t DMCloseThen(dispatch_block_t action) { return action; }   // (the real one closes the menu first, then runs the row's action)
static BOOL DMTitleTapWithMenuOpen(UIButton *btn) { return NO; }
static const void *kFileLabelKey = &kFileLabelKey, *kFilePillKey = &kFilePillKey, *kViewLabelKey = &kViewLabelKey, *kViewPillKey = &kViewPillKey,
                  *kEditLabelKey = &kEditLabelKey, *kEditPillKey = &kEditPillKey, *kGoLabelKey = &kGoLabelKey, *kGoPillKey = &kGoPillKey;
static NSArray *gKMenu;
static void DMPresentMenu(UIButton *btn, const void *labelKey, const void *pillKey, NSArray *items) { gKMenu = items; }

// ---- the native windows (NativeWindow.h's rules, see the top)
static NSMutableArray<NSMutableString *> *gKDone;   // what the windows were asked, "<title> <action>"
@interface DMNativeWindow : UIView
@property (nonatomic, copy) NSString *title, *appName;
- (instancetype)initWithTitle:(NSString *)title;
- (void)show; - (void)activate; - (void)minimize; - (void)close;
@end
static NSMutableArray<DMNativeWindow *> *gNativeWindows;   // front last
static DMNativeWindow *gNativeActive;
static UIWindow *gNativeLayer;
static void KLayerLevel(void) { BOOL any = NO; for (DMNativeWindow *w in gNativeWindows) if (!w.hidden) any = YES; gNativeLayer.hidden = !any; }
static void KSetActive(DMNativeWindow *w) {
    gNativeActive = w;
    if (w) { [gNativeWindows removeObjectIdenticalTo:w]; [gNativeWindows addObject:w]; }
    KLayerLevel();
}
@implementation DMNativeWindow
- (instancetype)initWithTitle:(NSString *)title { if ((self = [super initWithFrame:CGRectMake(0, 0, 400, 300)])) { _title = [title copy]; _appName = @"Finder"; } return self; }
- (void)show { if (![gNativeWindows containsObject:self]) [gNativeWindows addObject:self]; self.hidden = NO; KSetActive(self); }
- (void)activate { KSetActive(self); }
- (void)minimize { self.hidden = YES; DMNativeWindow *next = nil; for (DMNativeWindow *w in gNativeWindows) if (!w.hidden) next = w; KSetActive(next); }
- (void)close {
    [gKDone addObject:[NSMutableString stringWithFormat:@"%@ close", self.title]];
    [gNativeWindows removeObjectIdenticalTo:self];
    DMNativeWindow *next = gNativeWindows.lastObject;
    KSetActive(next && !next.hidden ? next : nil);
}
@end
@interface DMTextWindow : DMNativeWindow @end
@implementation DMTextWindow @end
@interface DMActivityMonitorWindow : DMNativeWindow @end
@implementation DMActivityMonitorWindow @end
@interface DMDispSettingsWindow : DMNativeWindow @end
@implementation DMDispSettingsWindow @end
@interface DMQuickLookWindow : DMNativeWindow
@property (nonatomic, weak) id browser;   // (the Finder window it was opened from; the desktop, or nothing)
@end
@implementation DMQuickLookWindow @end
@interface KDesktop : NSObject @end   // (Finder's desktop: a Quick Look browser that is no window)
@implementation KDesktop @end

// ---- a Finder window: its folder and selection, and what it is asked
@interface DMFinderItem : NSObject @end
@implementation DMFinderItem @end
static NSMutableArray<NSString *> *gFinderClipboard;
@interface DMFinderWindow : DMNativeWindow
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BOOL selected;
@end
@implementation DMFinderWindow
- (void)did:(NSString *)what { [gKDone addObject:[NSMutableString stringWithFormat:@"%@ %@", self.title, what]]; }
- (DMFinderItem *)dm_selectedItem { return self.selected ? [DMFinderItem new] : nil; }
- (NSArray<DMFinderItem *> *)dm_selectedItems { return self.selected ? @[[DMFinderItem new]] : @[]; }
- (BOOL)dm_canChangeSelection { return YES; }
- (BOOL)dm_canWriteHere { return YES; }
- (void)dm_newFolder { [self did:@"new folder"]; }
- (void)dm_newTextFile { [self did:@"new text file"]; }
- (void)dm_openSelected { [self did:@"open"]; }
- (void)dm_quickLookSelected { [self did:@"quick look"]; }
- (void)dm_infoSelected { [self did:@"get info"]; }
- (void)dm_renameSelected { [self did:@"rename"]; }
- (void)dm_duplicateSelected { [self did:@"duplicate"]; }
- (void)dm_trashSelected { [self did:@"trash"]; }
- (void)dm_setIcons:(BOOL)icons { [self did:icons ? @"icons" : @"list"]; }
- (MSBDSortChoice)dm_sort { return kMSBDSortDefault; }
- (void)dm_sortBy:(int)key { [self did:[NSString stringWithFormat:@"sort %d", key]]; }
- (BOOL)dm_showsHidden { return NO; }
- (void)dm_toggleHidden { [self did:@"hidden files"]; }
- (NSString *)dm_undoTitle { return @"Undo"; }
- (BOOL)dm_canUndo { return NO; }
- (void)dm_undo { [self did:@"undo"]; }
- (void)dm_keyCopy:(id)s { [self did:@"copy"]; }
- (void)dm_keyPaste:(id)s { [self did:@"paste"]; }
- (void)dm_keyFind:(id)s { [self did:@"find"]; }
- (void)goBack { [self did:@"back"]; }
- (void)goForward { [self did:@"forward"]; }
- (void)goUp { [self did:@"up"]; }
- (void)dm_goToFolder { [self did:@"go to folder"]; }
@end
static BOOL DMFinderInOwnTrash(NSString *p) { return NO; }
static void DMFinderOpen(NSString *path, BOOL newWindow) { [gKDone addObject:[NSMutableString stringWithFormat:@"finder open %@%@", path ?: @"(home)", newWindow ? @" new" : @""]]; }

// ---- File > Eject (DriveEject.h's targets and eject: stand-ins; a window whose folder is on a drive has one)
static BOOL DMDriveCanEject(void) { return YES; }
static NSArray<NSDictionary *> *DMDriveEjectTargets(DMFinderWindow *f) { return [f.path hasPrefix:@"/var/mobile/Library/LiveFiles/"] ? @[@{@"t": @"USB", @"p": f.path}] : @[]; }
static void DMDriveEjectFromWindow(DMFinderWindow *f) { [gKDone addObject:[NSMutableString stringWithFormat:@"%@ eject", f.title]]; }

// ---- the Go menu's other rows
static BOOL gFinderOn = YES;
static NSArray<NSDictionary *> *DMFinderSidebar(void) { return @[@{@"rows": @[@{@"t": @"Documents", @"p": @"/var/mobile/Documents"}, @{@"t": @"Trash", @"p": @"/var/mobile/.Trash"}]}]; }
static void DMOpenURL(NSString *url, NSString *tag) {}
static void DMActivityMonitorOpen(void) {}
static NSArray<NSString *> *DMGoAppBundleIDs(void) { return @[]; }
#define kDMTerminalToken @"@terminal"
#define kDMTerminalApps (@[@"ws.hbang.Terminal"])
#define kDMReynardBundle @"com.minh-ton.Reynard"
#define kDMReynardPage @"https://example.invalid/reynard"
static BOOL DMAppInstalled(NSString *b) { return NO; }
static id DMProxyForBundle(NSString *b) { return nil; }
static id DMCall(id o, NSString *n) { return nil; }
static void DMOpenApp(NSString *b) {}
static void DMOpenStatusBarSettings(uint32_t t) {}

#include "fm-real.inc"

// ---- the checks
static int gFails = 0;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }
static void reset(void) {
    for (DMNativeWindow *w in [gNativeWindows copy]) [gNativeWindows removeObjectIdenticalTo:w];
    gNativeActive = nil; gNativeLayer.hidden = YES;
    [gKDone removeAllObjects]; [gKLog removeAllObjects]; gKMenu = nil;
}
static DMFinderWindow *finder(NSString *title, NSString *path, BOOL selected) { DMFinderWindow *f = [[DMFinderWindow alloc] initWithTitle:title]; f.path = path; f.selected = selected; [f show]; return f; }
static DMNativeWindow *other(Class c, NSString *name) { DMNativeWindow *w = [[c alloc] initWithTitle:name]; w.appName = name; [w show]; return w; }
static DMRow *row(NSString *title) { for (id r in gKMenu) if ([r isKindOfClass:[DMRow class]] && [((DMRow *)r).title isEqualToString:title]) return r; return nil; }
static BOOL fire(NSString *title) { DMRow *r = row(title); if (!r || !r.enabled || !r.handler) return NO; r.handler(); return YES; }   // (a tap: a greyed row does nothing)
static NSString *done(void) { return [gKDone componentsJoinedByString:@", "]; }
static UIButton *btn(void) { return [UIButton new]; }

int main(void) {
    @autoreleasepool {
        gKLog = [NSMutableArray array]; gKDone = [NSMutableArray array]; gNativeWindows = [NSMutableArray array]; gFinderClipboard = [NSMutableArray array];
        gNativeLayer = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 100, 100)]; gNativeLayer.hidden = YES;

        // 1. The audit's case: a text file opened from a Finder window -- TextEdit active in front of it.
        reset();
        DMFinderWindow *F = finder(@"Docs", @"/var/mobile/Documents", YES);
        other([DMTextWindow class], @"TextEdit");
        check(!KFinderTitles(40), @"TextEdit active over a Finder window: no File or View in the bar (Finder's titles)");
        DMOpenGoMenu(btn());
        check(!row(@"Back") && !row(@"Go to Folder…") && row(@"Documents") && row(@"Battery"), @"  ... its Go menu has no Back, Forward, Enclosing Folder or Go to Folder (the places and the rest stay)");
        DMOpenFinderFileMenu(btn());
        fire(@"Close Window"); fire(@"Move to Trash");
        check([gNativeWindows containsObject:F] && gKDone.count == 0, [NSString stringWithFormat:@"  ... no File row acts on the Finder window behind (asked: %@)", done()]);
        check(row(@"New Finder Window").enabled && !row(@"Close Window").enabled && !row(@"Move to Trash").enabled, @"  ... File's rows for a window are greyed, New Finder Window stays");

        // 2. The Finder window minimized, TextEdit active: nothing acts on the hidden window.
        reset();
        F = finder(@"Docs", @"/var/mobile/Documents", YES);
        DMNativeWindow *T = other([DMTextWindow class], @"TextEdit");
        [F activate]; [F minimize];
        check(gNativeActive == T && F.hidden, @"(set-up) the Finder window minimized, TextEdit active");
        check(!KFinderTitles(40), @"TextEdit active, the Finder window minimized: no File or View");
        DMOpenGoMenu(btn()); fire(@"Back"); fire(@"Go to Folder…");
        DMOpenFinderFileMenu(btn()); fire(@"Close Window");
        DMOpenFinderViewMenu(btn()); fire(@"as List");
        check(gKDone.count == 0 && [gNativeWindows containsObject:F], [NSString stringWithFormat:@"  ... Go, File and View never act on the minimized window (asked: %@)", done()]);

        // 3. Activity Monitor, no Finder window at all.
        reset();
        other([DMActivityMonitorWindow class], @"Activity Monitor");
        check(!KFinderTitles(40), @"Activity Monitor active: no File or View");
        DMOpenGoMenu(btn());
        check(!row(@"Back") && !row(@"Enclosing Folder") && row(@"Activity Monitor"), @"  ... no Finder rows in Go (before: enabled and doing nothing)");

        // 4. Display Settings over a Finder window.
        reset();
        F = finder(@"Docs", @"/var/mobile/Documents", YES);
        other([DMDispSettingsWindow class], @"Display Settings");
        check(!KFinderTitles(40), @"Display Settings active over a Finder window: no File or View");
        DMOpenGoMenu(btn()); fire(@"Back");
        check(!row(@"Back") && gKDone.count == 0, @"  ... no Back in Go, nothing asked of the Finder window");

        // 5. A Finder window active (unchanged): its titles and every menu act on it.
        reset();
        DMFinderWindow *F1 = finder(@"One", @"/var/mobile/Documents", YES);
        F = finder(@"Two", @"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/USB", YES);
        check(KFinderTitles(40) && !KFinderTitles(0), @"a Finder window active: File and View shown (none when the app title had no room)");
        DMOpenFinderFileMenu(btn()); fire(@"Move to Trash"); fire(@"Eject “USB”");
        DMOpenFinderViewMenu(btn()); fire(@"as List");
        DMOpenGoMenu(btn()); fire(@"Back");
        DMOpenFinderEditMenu(btn(), F); fire(@"Copy");
        check([done() isEqualToString:@"Two trash, Two eject, Two list, Two back, Two copy"], [NSString stringWithFormat:@"  ... File, File > Eject, View, Go and Edit act on the active window, not the one behind (asked: %@)", done()]);
        [gKDone removeAllObjects];
        DMOpenFinderFileMenu(btn()); fire(@"Close Window");
        check([done() isEqualToString:@"Two close"] && [gNativeWindows containsObject:F1] && gNativeActive == F1, @"  ... File > Close Window closes the active window; the one behind becomes active");

        // 6. Quick Look from a Finder window (unchanged): Finder's titles, and the rows act on the Finder window it was opened from.
        reset();
        F = finder(@"Docs", @"/var/mobile/Documents", YES);
        DMQuickLookWindow *Q = (DMQuickLookWindow *)[[DMQuickLookWindow alloc] initWithTitle:@"a.png"]; Q.browser = F; [Q show];
        check(KFinderTitles(40), @"Quick Look from a Finder window: File and View stay (Finder's Quick Look)");
        DMOpenFinderFileMenu(btn()); fire(@"Move to Trash");
        DMOpenGoMenu(btn()); fire(@"Enclosing Folder");
        check([done() isEqualToString:@"Docs trash, Docs up"], [NSString stringWithFormat:@"  ... File and Go act on the Finder window it was opened from (asked: %@)", done()]);

        // 7. ... and that Finder window minimized meanwhile (Quick Look active again): greyed, nothing acts on the hidden window.
        [gKDone removeAllObjects];
        [F activate]; [F minimize];
        check(gNativeActive == Q && F.hidden, @"(set-up) the Finder window minimized, its Quick Look active");
        DMOpenFinderFileMenu(btn()); fire(@"Close Window");
        DMOpenGoMenu(btn()); fire(@"Back");
        check(gKDone.count == 0 && [gNativeWindows containsObject:F] && row(@"Back") && !row(@"Back").enabled,
              [NSString stringWithFormat:@"  ... File > Close Window and Go > Back never act on the minimized window, Go's Finder rows greyed (asked: %@)", done()]);

        // 8. Quick Look from the desktop, a Finder window minimized: Finder's titles, nothing acts on the hidden window.
        reset();
        F = finder(@"Docs", @"/var/mobile/Documents", YES); [F minimize];
        KDesktop *desk = [KDesktop new];
        Q = (DMQuickLookWindow *)[[DMQuickLookWindow alloc] initWithTitle:@"b.pdf"]; Q.browser = (id)desk; [Q show];
        check(KFinderTitles(40), @"Quick Look from the desktop: File and View stay");
        DMOpenFinderFileMenu(btn()); fire(@"Close Window"); fire(@"Move to Trash");
        BOOL fileOK = row(@"New Finder Window").enabled && !row(@"Close Window").enabled;
        DMOpenFinderViewMenu(btn()); fire(@"as Icons");
        check(gKDone.count == 0 && fileOK, [NSString stringWithFormat:@"  ... no row acts on the minimized Finder window; New Finder Window stays (asked: %@)", done()]);

        // 9. A menu opened for one Finder window, that window closed or minimized before the row fires: nothing, never another window.
        reset();
        F1 = finder(@"One", @"/var/mobile/Documents", YES);
        F = finder(@"Two", @"/var/mobile/Library/LiveFiles/com.apple.filesystems.userfsd/USB", YES);
        DMOpenFinderFileMenu(btn());
        DMRow *trash = row(@"Move to Trash"), *eject = row(@"Eject “USB”");
        [gNativeWindows removeObjectIdenticalTo:F]; KSetActive(F1);   // (Two closed by its red light meanwhile; One active)
        if (trash.enabled) trash.handler();
        if (eject.enabled) eject.handler();
        check(gKDone.count == 0, [NSString stringWithFormat:@"File menu opened for a window closed before the row fired: Move to Trash and Eject do nothing (asked: %@)", done()]);
        check([[gKLog componentsJoinedByString:@"\n"] containsString:@"[finder] Move to Trash: its Finder window was closed or minimized meanwhile, nothing done"], @"  ... and the log says so");
        reset();
        F1 = finder(@"One", @"/var/mobile/Documents", YES);
        F = finder(@"Two", @"/var/mobile/Documents/Two", YES);
        DMOpenGoMenu(btn());
        DMRow *back = row(@"Back");
        [F minimize];
        if (back.enabled) back.handler();
        check(gKDone.count == 0, [NSString stringWithFormat:@"Go menu opened for a window minimized before Back fired: nothing (asked: %@)", done()]);

        // 10. No native window active (an app or the Home Screen in front): no File or View, no Finder rows in Go -- as before.
        reset();
        F = finder(@"Docs", @"/var/mobile/Documents", YES);
        KSetActive(nil);
        check(!KFinderTitles(40), @"no native window active: no File or View");
        DMOpenGoMenu(btn());
        check(!row(@"Back") && row(@"Documents"), @"  ... no Finder rows in Go, the places stay");
        fire(@"Documents");
        check([done() isEqualToString:@"finder open /var/mobile/Documents"], @"  ... Go > Documents opens in Finder, as before");
    }
    return gFails;
}
