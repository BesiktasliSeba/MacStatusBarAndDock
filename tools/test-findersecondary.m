// test-findersecondary.m -- Mac test (Mac Catalyst: UIKit on the Mac) of a pointer's secondary click in Finder's windows (1.8.8.1, B63): a mouse's
// right button, a trackpad's two-finger click, or its two-finger tap with Tap to Click opens the menu a hold opens there, at the pointer -- on a
// file or folder in the list and in the icons, on the folder's empty space, on a drive in the sidebar --, and a finger's press, a primary click
// and a hold work as before. KT 21 Nov: "inside finder, currently we can't do the secondary tap with trackpad to open the menu". Before: Finder's
// own taps for it allowed only Indirect Pointer touches (SpringBoard's pointer touches are Direct) and could never be offered the touch anyway
// (UIKit offers a secondary click's touch to a context menu interaction's recognizer only), and its context menu interactions answered UIKit's
// ask for that click with nothing.
// Runs, cut out of the sources by test-findersecondary.sh: NativeWindow.h's press note (gNativePressTouch, gNativePressButtons, gNativePressTaken,
// DMNativeNotePress, DMNativeTakeSecondaryPress; in fs-native.inc, a stand-in that notes nothing where the code has none) and Finder.h's
// -itemAt:in:, -contextMenuInteraction:configurationForMenuAtLocation: (UIKit's ask), -dm_sideMenuForDrive:at:, -dm_menuIn:at:,
// -dm_menuByHoldIn:at: and, where it exists, -dm_secondaryClickIn:at: (fs-finder.inc). SpringBoard's side is the stand-ins below: the native
// layer window, the press as -[SpringBoard sendEvent:] gets it (a touch and its event: phase, window, view, place, buttons), and UIKit's ask for
// the press made as UIKit makes it, from the window's own context menu interaction at the touch's place in its view.
// It also reads, on this Mac's UIKit, why the old taps never fired: which mouse buttons a tap set to the secondary button and a context menu
// interaction's own recognizer allow.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <unistd.h>
#include <signal.h>
#include <execinfo.h>
#include "../common/FinderSort.h"

static int gKFails, gKPasses, gKSkips;
static const char *gKStep = "start";   // (where the harness is, for its crash report)
#define KSTEP(s) (gKStep = (s))
static void KCheck(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (ok) gKPasses++; else gKFails++; }
static void KSkip(NSString *what) { printf("SKIP  %s\n", what.UTF8String); gKSkips++; }

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gKLog;
static void KLog(NSString *s) { [gKLog addObject:s ?: @""]; }
#define DMLog(...) KLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name)

// ---- Finder's items and the calls its menus make (stand-ins: every place can be changed and written, no app to share to, one drive)
@interface DMFinderItem : NSObject
@property (nonatomic, copy) NSString *path, *name, *kind, *app;
@property (nonatomic) BOOL dir, locked, cloud, package;
@end
@implementation DMFinderItem @end
static NSString *const kFinderTrash = @"/var/mobile/.Trash";
static NSString *const kKDrive = @"/private/var/mnt/NO NAME";
static NSMutableArray<NSString *> *gFinderClipboard;
static BOOL DMFinderCanChange(NSString *p) { return YES; }
static BOOL DMFDIsApp(DMFinderItem *it) { return it.dir && (it.app.length || [it.name hasSuffix:@".app"]); }
static BOOL DMFinderInTrash(NSString *p) { return [p hasPrefix:kFinderTrash]; }
static BOOL DMFinderInOwnTrash(NSString *p) { return [p hasPrefix:kFinderTrash]; }
static NSArray<NSString *> *DMFinderShareApps(void) { return @[]; }
static id DMCall(id o, NSString *n) { return nil; }
static id DMProxyForBundle(NSString *b) { return nil; }
@class DMFinderWindow;
static void DMFinderShareTo(NSArray<DMFinderItem *> *items, NSString *b, DMFinderWindow *w) {}
static UIMenu *DMFinderOpenWithMenu(DMFinderItem *it, DMFinderWindow *w, dispatch_block_t before) { return nil; }   // (1.8.8.1 B67's Open With: no app claims a file here; test-finderopenwith)
static BOOL DMFinderCanWriteInto(NSString *d) { return YES; }
static NSString *DMFinderOrigin(NSString *p) { return nil; }
static BOOL DMDriveCanEject(void) { return YES; }
static NSDictionary *DMFinderDriveInfo(NSString *root) { return [root isEqualToString:kKDrive] ? @{ @"p": root, @"t": @"NO NAME" } : nil; }
static NSString *DMFinderReal(NSString *p) { return p; }
static void DMDriveEject(NSString *root, NSString *name) {}
static BOOL DMDriveEjecting(NSString *root) { return NO; }
static void DMFinderOpen(NSString *path, BOOL newWindow) {}
static DMFinderItem *DMFinderItemFor(NSString *path) { DMFinderItem *it = [DMFinderItem new]; it.path = path; it.name = path.lastPathComponent; it.dir = YES; return it; }

// ---- the menu that would be shown (DMFinderShowMenu draws ours at that screen point)
static NSMutableArray<NSDictionary *> *gKShown;
static void DMFinderShowMenu(UIMenu *menu, CGPoint screenPoint) { [gKShown addObject:@{ @"m": menu ?: [NSNull null], @"p": [NSValue valueWithCGPoint:screenPoint] }]; }
static void KTitles(UIMenuElement *e, NSMutableArray<NSString *> *out) {
    if ([e isKindOfClass:[UIMenu class]]) { UIMenu *m = (UIMenu *)e; if (m.title.length) [out addObject:m.title]; for (UIMenuElement *c in m.children) KTitles(c, out); }
    else if ([e isKindOfClass:[UIAction class]]) [out addObject:e.title ?: @""];
}

// ---- the native layer and its windows
static UIWindow *gNativeLayer;
@interface DMNativeWindow : UIView @end
@implementation DMNativeWindow @end

#include "fs-native.inc"

// ---- the list (rows 40 pt), the icons (100 x 100, 4 a row) and the sidebar (rows 30 pt): plain views that find their rows as Finder's table and
// collection views do (the methods the real code asks), so no table or collection view has to run here without an app
@interface KList : UIView @property (nonatomic) NSInteger kRows; - (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)p; @end
@implementation KList
- (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)p { NSInteger r = (NSInteger)floor(p.y / 40.0); return p.y >= 0 && r < _kRows ? [NSIndexPath indexPathForRow:r inSection:0] : nil; }
@end
@interface KGrid : UIView @property (nonatomic) NSInteger kItems; - (NSIndexPath *)indexPathForItemAtPoint:(CGPoint)p; @end
@implementation KGrid
- (NSIndexPath *)indexPathForItemAtPoint:(CGPoint)p {
    if (p.x < 0 || p.y < 0 || p.x >= 400) return nil;
    NSInteger i = (NSInteger)floor(p.y / 100.0) * 4 + (NSInteger)floor(p.x / 100.0);
    return i < _kItems ? [NSIndexPath indexPathForItem:i inSection:0] : nil;
}
@end
@interface KSide : UIView @property (nonatomic) NSInteger kRows; - (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)p; @end
@implementation KSide
- (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)p { NSInteger r = (NSInteger)floor(p.y / 30.0); return p.y >= 0 && r < _kRows ? [NSIndexPath indexPathForRow:r inSection:0] : nil; }
@end

// ---- a Finder window: the ivars and the calls the real methods use; what it is asked is recorded
@interface DMFinderWindow : DMNativeWindow <UIContextMenuInteractionDelegate> {
@public
    UITableView *_list; UICollectionView *_grid; UITableView *_sidebar;
    NSArray<NSDictionary *> *_places; NSArray<DMFinderItem *> *_items;
    BOOL _menuByHold, _dragLifted, _hidden, _icons;
    UITextField *_renameField; UIView *_dragCell;
    NSMutableOrderedSet<NSString *> *_sel; NSString *_selected;
}
@property (nonatomic, copy) NSString *path;
@end
@implementation DMFinderWindow
- (BOOL)dm_isSelected:(DMFinderItem *)it { return it && [_sel containsObject:it.path]; }
- (NSArray<DMFinderItem *> *)dm_selectedItems { NSMutableArray *a = [NSMutableArray array]; for (DMFinderItem *it in _items) if ([_sel containsObject:it.path]) [a addObject:it]; return a; }
- (void)dm_setSelection:(NSArray<NSString *> *)paths anchor:(NSString *)anchor { _sel = [NSMutableOrderedSet orderedSetWithArray:paths ?: @[]]; _selected = anchor; }
- (void)dm_endRename:(BOOL)keep { if (!_renameField) return; KLog(keep ? @"rename ended, name kept" : @"rename ended"); [_renameField removeFromSuperview]; _renameField = nil; }
- (void)dm_openSelected {} - (void)dm_duplicateItems:(NSArray *)p {} - (BOOL)dm_canWriteHere { return YES; } - (void)dm_putBackItems:(NSArray *)p {}
- (void)dm_deleteItems:(NSArray *)p {} - (void)dm_trashItems:(NSArray *)p {} - (void)open:(DMFinderItem *)it {} - (void)go:(NSString *)p {}
- (void)quickLook:(DMFinderItem *)it {} - (void)getInfo:(DMFinderItem *)it {} - (void)dm_rename:(DMFinderItem *)it {} - (void)dm_duplicate:(DMFinderItem *)it {}
- (void)dm_download:(DMFinderItem *)it {} - (void)trash:(DMFinderItem *)it {} - (void)newFolder {} - (void)dm_newTextFile {} - (void)paste {} - (void)refresh {}
- (void)toggleView {} - (MSBDSortChoice)dm_sort { return kMSBDSortDefault; } - (void)dm_sortBy:(int)key {} - (BOOL)dm_canUndo { return NO; }
- (NSString *)dm_undoTitle { return @"Undo"; } - (void)dm_undo {} - (void)emptyTrash {}
- (UITargetedPreview *)dm_previewFor:(UIContextMenuInteraction *)i config:(UIContextMenuConfiguration *)c { return nil; }
#include "fs-finder.inc"
@end

// ---- a press as SpringBoard's -sendEvent: gets it: a touch (its phase, window, view, place in the window) and its event's buttons
@interface KTouch : UITouch
@property (nonatomic) UITouchPhase kPhase; @property (nonatomic, weak) UIWindow *kWindow; @property (nonatomic, weak) UIView *kView; @property (nonatomic) CGPoint kAt;
@end
@implementation KTouch
- (UITouchPhase)phase { return _kPhase; } - (UIWindow *)window { return _kWindow; } - (UIView *)view { return _kView; } - (UITouchType)type { return UITouchTypeDirect; }
- (CGPoint)locationInView:(UIView *)v { return v ? [_kWindow convertPoint:_kAt toView:v] : _kAt; }
@end
@interface KEvent : UIEvent @property (nonatomic) NSInteger kButtons; @property (nonatomic, copy) NSSet<UITouch *> *kTouches; @end
@implementation KEvent
- (UIEventButtonMask)buttonMask { return (UIEventButtonMask)_kButtons; } - (NSSet<UITouch *> *)allTouches { return _kTouches; } - (UIEventType)type { return UIEventTypeTouches; }
@end

static DMFinderWindow *gW;
static UIWindow *gKOther;   // (the system gestures' window: SpringBoard's copy of a touch)
static UIContextMenuInteraction *KMenuOf(UIView *v) { for (id<UIInteraction> i in v.interactions) if ([(NSObject *)i isKindOfClass:[UIContextMenuInteraction class]]) return (UIContextMenuInteraction *)i; return nil; }
static void KSpin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }
static KTouch *KTouchAt(UIView *in, CGPoint p, UIWindow *win, UIView *hit) {
    KTouch *t = [KTouch new];
    t.kPhase = UITouchPhaseBegan; t.kWindow = win ?: gNativeLayer; t.kView = hit ?: in; t.kAt = [in convertPoint:p toView:nil];
    return t;
}
// A press in that view at that point with those buttons: SpringBoard's -sendEvent: (the real press note), then UIKit's ask from the view's own
// context menu interaction (the real delegate method). The configuration UIKit got back, through *config.
static void KPress(KTouch *t, NSInteger buttons, NSArray<UITouch *> *also, UIView *askedBy, UIContextMenuConfiguration **config) {
    const char *was = gKStep;
    KSTEP("a press: its event"); KEvent *e = [KEvent new]; e.kButtons = buttons;
    NSMutableSet *all = [NSMutableSet setWithObject:t]; if (also) [all addObjectsFromArray:also]; e.kTouches = all;
    KSTEP("a press: the press note"); DMNativeNotePress(e);
    KSTEP("a press: UIKit's ask"); UIContextMenuInteraction *cmi = KMenuOf(askedBy);
    UIContextMenuConfiguration *c = cmi ? [gW contextMenuInteraction:cmi configurationForMenuAtLocation:[t locationInView:askedBy]] : nil;
    if (config) *config = c;
    KSTEP("a press: the main queue after it"); KSpin();
    KSTEP(was);
}
static NSArray<NSString *> *KShownTitles(NSUInteger i) { NSMutableArray *a = [NSMutableArray array]; if (i < gKShown.count && [gKShown[i][@"m"] isKindOfClass:[UIMenu class]]) KTitles(gKShown[i][@"m"], a); return a; }
static BOOL KHasAll(NSArray<NSString *> *have, NSArray<NSString *> *want) { for (NSString *s in want) if (![have containsObject:s]) return NO; return YES; }
static BOOL KShownAt(NSUInteger i, CGPoint p) { if (i >= gKShown.count) return NO; CGPoint q = [gKShown[i][@"p"] CGPointValue]; return fabs(q.x - p.x) < 0.5 && fabs(q.y - p.y) < 0.5; }
static DMFinderItem *KItem(NSString *name, BOOL dir) { DMFinderItem *it = [DMFinderItem new]; it.name = name; it.path = [@"/var/mobile/Documents" stringByAppendingPathComponent:name]; it.dir = dir; it.kind = dir ? @"Folder" : @"Document"; return it; }
static void KReset(void) { [gKShown removeAllObjects]; [gKLog removeAllObjects]; gW->_sel = [NSMutableOrderedSet orderedSet]; gW->_selected = nil; gW->_menuByHold = NO; gW->_dragLifted = NO; }

static void KCrashed(int sig) {   // (a crash in the harness or the code it runs: where, on stderr, and the step it was in; then out)
    void *f[48]; int n = backtrace(f, 48);
    fprintf(stderr, "CRASH signal %d in step: %s\n", sig, gKStep);
    backtrace_symbols_fd(f, n, 2);
    _exit(99);   // (counted as "not run": a made-to-fail copy that crashes is not caught)
}
int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);   // (every line out at once: a crash still shows how far it got)
    signal(SIGSEGV, KCrashed); signal(SIGBUS, KCrashed); signal(SIGILL, KCrashed); signal(SIGTRAP, KCrashed); signal(SIGABRT, KCrashed);
    @autoreleasepool {
        gKLog = [NSMutableArray array]; gKShown = [NSMutableArray array]; gFinderClipboard = [NSMutableArray array];

        // ---- this Mac's UIKit: which mouse buttons a recognizer is offered (the old taps; a context menu interaction's own)
        SEL allowed = NSSelectorFromString(@"_defaultAllowedMouseButtons");
        UITapGestureRecognizer *oldTap = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
        oldTap.buttonMaskRequired = UIEventButtonMaskSecondary; oldTap.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        if ([oldTap respondsToSelector:allowed]) {
            NSInteger m = ((NSInteger (*)(id, SEL))objc_msgSend)(oldTap, allowed);
            KCheck(!(m & UIEventButtonMaskSecondary), [NSString stringWithFormat:@"UIKit: a tap set to the secondary button is still offered the primary button's touches only (allowed mouse buttons %ld): a secondary click's touch never reaches it", (long)m]);
        } else KSkip(@"UIKit: this UIKit has no -_defaultAllowedMouseButtons (the buttons a recognizer is offered)");
        {
            UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
            [v addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:(id<UIContextMenuInteractionDelegate>)[NSObject new]]];
            BOOL takes = NO, known = NO;
            for (UIGestureRecognizer *g in v.gestureRecognizers) {
                if (![g respondsToSelector:allowed]) continue;
                known = YES;
                NSInteger m = ((NSInteger (*)(id, SEL))objc_msgSend)(g, allowed);
                if ((m & UIEventButtonMaskSecondary) && [g.allowedTouchTypes containsObject:@(UITouchTypeDirect)]) takes = YES;
            }
            if (known) KCheck(takes, @"UIKit: a context menu interaction puts a recognizer on its view that is offered a secondary click's touch, Direct ones too (its menu's ask comes from it)");
            else KSkip(@"UIKit: a context menu interaction's recognizers do not say which mouse buttons they are offered");
        }

        // ---- the native layer, a Finder window in it, and that window's list, icons and sidebar with their context menu interactions (as Finder.h's init)
        KSTEP("the windows");
        gNativeLayer = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        gKOther = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        gW = [[DMFinderWindow alloc] initWithFrame:CGRectMake(100, 80, 800, 500)];
        [gNativeLayer addSubview:gW];
        KSTEP("the views and their interactions");
        KList *list = [[KList alloc] initWithFrame:CGRectMake(190, 30, 610, 470)];
        KGrid *grid = [[KGrid alloc] initWithFrame:CGRectMake(190, 30, 610, 470)];
        KSide *side = [[KSide alloc] initWithFrame:CGRectMake(0, 22, 190, 478)];
        for (UIView *v in @[list, grid, side]) { [gW addSubview:v]; [v addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:gW]]; }
        gW->_list = (UITableView *)list; gW->_grid = (UICollectionView *)grid; gW->_sidebar = (UITableView *)side; gW.path = @"/var/mobile/Documents";
        gW->_items = @[KItem(@"Notes.txt", NO), KItem(@"Photos", YES), KItem(@"Budget.numbers", NO)];
        list.kRows = 3; grid.kItems = 3;
        gW->_places = @[ @{ @"rows": @[ @{ @"p": @"/var/mobile/Documents", @"t": @"Documents" }, @{ @"p": kKDrive, @"t": @"NO NAME", @"drive": @YES } ] } ];
        side.kRows = 2;
        UIView *rowView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 610, 40)]; [list addSubview:rowView];   // (a row's own view: the touch's view is in the list)
        UIContextMenuConfiguration *c = nil;
        NSArray *fileRows = @[@"Open", @"Quick Look", @"Get Info", @"Rename", @"Duplicate", @"Copy", @"Move to Trash"];

        // 1. a file in the list
        KSTEP("1. a file in the list");
        KReset();
        KTouch *t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        KCheck(c == nil && gKShown.count == 1, [NSString stringWithFormat:@"a secondary click on a file in the list: our menu opens, once (%lu), and UIKit's own does not (configuration %@)", (unsigned long)gKShown.count, c ? @"given" : @"nil"]);
        KCheck(KHasAll(KShownTitles(0), fileRows), [NSString stringWithFormat:@"  ... the file's menu, as a hold gives it (%@)", [KShownTitles(0) componentsJoinedByString:@", "]]);
        KCheck(KShownAt(0, [list convertPoint:CGPointMake(120, 20) toView:nil]), @"  ... at the pointer");
        KCheck([gW->_sel.array isEqual:@[gW->_items[0].path]], @"  ... and the file is selected first, as a Mac's right click selects it");
        t.kPhase = UITouchPhaseEnded;

        // 2. a folder in the icons
        KSTEP("2. a folder in the icons");
        KReset(); gW->_icons = YES;
        t = KTouchAt(grid, CGPointMake(150, 50), nil, grid);
        KPress(t, UIEventButtonMaskSecondary, nil, grid, &c);
        NSArray *g2 = KShownTitles(0);
        KCheck(c == nil && gKShown.count == 1 && [g2 containsObject:@"Open"] && [g2 containsObject:@"Get Info"] && ![g2 containsObject:@"Quick Look"] && KShownAt(0, [grid convertPoint:CGPointMake(150, 50) toView:nil]),
               [NSString stringWithFormat:@"a secondary click on a folder in the icons: the folder's menu at the pointer (%@)", [g2 componentsJoinedByString:@", "]]);
        KCheck([gW->_sel.array isEqual:@[gW->_items[1].path]], @"  ... the folder selected");
        t.kPhase = UITouchPhaseEnded; gW->_icons = NO;

        // 3. the folder's empty space
        KReset();
        t = KTouchAt(list, CGPointMake(300, 400), nil, list);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        NSArray *g3 = KShownTitles(0);
        KCheck(c == nil && gKShown.count == 1 && KHasAll(g3, @[@"New Folder", @"New Text File", @"Sort By", @"Copy Path"]) && KShownAt(0, [list convertPoint:CGPointMake(300, 400) toView:nil]),
               [NSString stringWithFormat:@"a secondary click on the folder's empty space: the folder's menu at the pointer (%@)", [g3 componentsJoinedByString:@", "]]);
        KCheck(gW->_sel.count == 0, @"  ... nothing selected");
        t.kPhase = UITouchPhaseEnded;

        // 4. a drive in the sidebar
        KSTEP("4. a drive in the sidebar");
        KReset();
        t = KTouchAt(side, CGPointMake(60, 45), nil, side);
        KPress(t, UIEventButtonMaskSecondary, nil, side, &c);
        NSArray *g4 = KShownTitles(0);
        BOOL eject = NO; for (NSString *s in g4) if ([s hasPrefix:@"Eject "] && [s containsString:@"NO NAME"]) eject = YES;
        KCheck(c == nil && gKShown.count == 1 && KHasAll(g4, @[@"Open", @"Open in New Window", @"Get Info"]) && eject && KShownAt(0, [side convertPoint:CGPointMake(60, 45) toView:nil]),
               [NSString stringWithFormat:@"a secondary click on a drive in the sidebar: the drive's menu, Eject in it, at the pointer (%@)", [g4 componentsJoinedByString:@", "]]);
        t.kPhase = UITouchPhaseEnded;

        // 5. another place in the sidebar
        KReset();
        t = KTouchAt(side, CGPointMake(60, 15), nil, side);
        KPress(t, UIEventButtonMaskSecondary, nil, side, &c);
        KCheck(c == nil && gKShown.count == 0, @"a secondary click on another place in the sidebar: no menu (a place has none of its own, as with a hold)");
        t.kPhase = UITouchPhaseEnded;

        // 6. 7. a finger, a primary click
        KReset();
        t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        KPress(t, 0, nil, list, &c);
        KCheck(c == nil && gKShown.count == 0 && gW->_sel.count == 0, @"a finger's press on a file: no menu at UIKit's ask (a finger's menu opens from our hold, as before)");
        t.kPhase = UITouchPhaseEnded;
        KReset();
        t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        KPress(t, UIEventButtonMaskPrimary, nil, list, &c);
        KCheck(c == nil && gKShown.count == 0 && gW->_sel.count == 0, @"a primary click on a file: no menu at UIKit's ask (a click held still opens it from our hold, as before)");
        t.kPhase = UITouchPhaseEnded;
        KReset();
        t = KTouchAt(side, CGPointMake(60, 45), nil, side);
        KPress(t, 0, nil, side, &c);
        KCheck(c == nil && gKShown.count == 0, @"a finger's press on a drive in the sidebar: no menu at UIKit's ask (the hold opens it, -dm_sideDragPress:)");
        t.kPhase = UITouchPhaseEnded;

        // 8. asked twice for one press; a new press after it
        KReset();
        t = KTouchAt(list, CGPointMake(120, 60), nil, list);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:[t locationInView:list]]; KSpin();
        KCheck(gKShown.count == 1, [NSString stringWithFormat:@"UIKit asks twice for the same press: one menu (%lu)", (unsigned long)gKShown.count]);
        t.kPhase = UITouchPhaseEnded;
        t = KTouchAt(list, CGPointMake(120, 100), nil, list);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        KCheck(gKShown.count == 2 && [gW->_sel.array isEqual:@[gW->_items[2].path]], @"  ... and the next secondary click opens its own");
        t.kPhase = UITouchPhaseEnded;

        // 9. a press already over; 10. a press in another view
        KReset();
        t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        { KEvent *e = [KEvent new]; e.kButtons = UIEventButtonMaskSecondary; e.kTouches = [NSSet setWithObject:t]; DMNativeNotePress(e); }
        t.kPhase = UITouchPhaseEnded;
        [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:CGPointMake(120, 20)]; KSpin();
        KCheck(gKShown.count == 0, @"an ask after the press is over: no menu");
        KReset();
        t = KTouchAt(side, CGPointMake(60, 45), nil, side);
        { KEvent *e = [KEvent new]; e.kButtons = UIEventButtonMaskSecondary; e.kTouches = [NSSet setWithObject:t]; DMNativeNotePress(e); }
        [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:CGPointMake(120, 20)]; KSpin();
        KCheck(gKShown.count == 0 && gW->_sel.count == 0, @"a secondary click in the sidebar, asked about by the list's interaction: no menu from the list");
        t.kPhase = UITouchPhaseEnded;

        // 11. SpringBoard's copy of the touch in the system gestures' window (an event of its own, before or after the touch itself)
        KReset();
        t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        KTouch *copy = KTouchAt(list, CGPointMake(120, 20), gKOther, nil); copy.kView = nil;
        KEvent *ce = [KEvent new]; ce.kButtons = UIEventButtonMaskSecondary; ce.kTouches = [NSSet setWithObject:copy];
        { KEvent *e = [KEvent new]; e.kButtons = UIEventButtonMaskSecondary; e.kTouches = [NSSet setWithObject:t]; DMNativeNotePress(e); }
        DMNativeNotePress(ce);
        [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:[t locationInView:list]]; KSpin();
        KCheck(gKShown.count == 1, @"SpringBoard's copy of the press in the system gestures' window, coming after it: the press is still the layer's touch, its menu opens");
        t.kPhase = UITouchPhaseEnded;
        KReset();
        t = KTouchAt(list, CGPointMake(120, 20), nil, rowView);
        DMNativeNotePress(ce);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        KCheck(gKShown.count == 1, @"  ... coming before it: the same");
        t.kPhase = UITouchPhaseEnded;
        KReset();
        DMNativeNotePress(ce);
        [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:CGPointMake(120, 20)]; KSpin();
        KCheck(gKShown.count == 0, @"  ... and the copy alone is no press of the layer's: no menu");

        // 12. one of several selected
        KReset();
        gW->_sel = [NSMutableOrderedSet orderedSetWithArray:@[gW->_items[0].path, gW->_items[2].path]];
        t = KTouchAt(list, CGPointMake(120, 100), nil, list);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        NSArray *g12 = KShownTitles(0);
        KCheck(gKShown.count == 1 && [g12 containsObject:@"Copy 2 Items"] && gW->_sel.count == 2, [NSString stringWithFormat:@"a secondary click on one of two selected files: the menu acts on both and the selection stays (%@)", [g12 componentsJoinedByString:@", "]]);
        t.kPhase = UITouchPhaseEnded;

        // 13. a name being edited
        KReset();
        gW->_renameField = [[UITextField alloc] initWithFrame:CGRectMake(40, 40, 200, 30)]; [list addSubview:gW->_renameField];
        t = KTouchAt(list, CGPointMake(100, 55), nil, gW->_renameField);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        KCheck(gKShown.count == 0 && gW->_renameField != nil, @"a secondary click in the name being edited: no Finder menu, the name stays in edit (the field's own)");
        t.kPhase = UITouchPhaseEnded;
        KReset();
        t = KTouchAt(list, CGPointMake(300, 20), nil, rowView);
        KPress(t, UIEventButtonMaskSecondary, nil, list, &c);
        KCheck(gKShown.count == 1 && gW->_renameField == nil && [gKLog containsObject:@"rename ended, name kept"], @"  ... elsewhere: the rename ends with its new name, and the menu opens");
        t.kPhase = UITouchPhaseEnded;

        // 14. the hold, as before
        KSTEP("14. the hold");
        KReset();
        [gW dm_menuByHoldIn:list at:CGPointMake(120, 20)];
        KCheck(gKShown.count == 1 && KHasAll(KShownTitles(0), fileRows) && KShownAt(0, [list convertPoint:CGPointMake(120, 20) toView:nil]) && [gW->_sel.array isEqual:@[gW->_items[0].path]],
               @"a finger's hold that stays still on a file: its menu at the finger, the file selected (as before)");
        KReset();
        [gW dm_menuByHoldIn:list at:CGPointMake(300, 400)];
        KCheck(gKShown.count == 1 && [KShownTitles(0) containsObject:@"New Folder"], @"  ... on the empty space: the folder's menu (as before)");
        KReset();
        gW->_menuByHold = YES;
        c = [gW contextMenuInteraction:KMenuOf(list) configurationForMenuAtLocation:CGPointMake(120, 20)];
        gW->_menuByHold = NO;
        KCheck(c != nil && gKShown.count == 0, @"  ... the hold's own ask still gets the menu's configuration, and opens nothing by itself");
        printf("%d PASS, %d FAIL, %d SKIP\n", gKPasses, gKFails, gKSkips);
        fflush(stdout);
        _exit(gKFails > 98 ? 98 : gKFails);   // (no teardown: UIKit's windows and interactions here have no app or scene to go away with)
    }
    return 0;
}
