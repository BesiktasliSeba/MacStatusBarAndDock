// test-finderreveal.m: Mac test (Mac Catalyst: UIKit on the Mac) of a Finder window's selection as it is SHOWN (1.8.8.2, B73). 1.8.8.1's device
// pass: Show in Enclosing Folder from the Dock's Downloads stack opened a new Finder window on the folder, but the item was not highlighted (with that
// window already open it was). What a Finder window shows as selected is UIKit's own selection in its list and icons, a copy of _sel, and UIKit
// drops it for every row it reloads. A new window's first listing can land before its first layout (another native window on the screen: -show lays
// nothing out), and that first layout reloaded the list (its width changed from none): the highlight was gone, the item still in _sel. A resize
// of the list and a thumbnail coming in (pictures, PDFs) dropped it the same way; and the early listing scrolled to the item and started a pending
// rename in a list with no size.
// Runs, cut out of statusbar/Finder.h by test-finderreveal.sh (fr-finder.inc, fr-funcs.inc): the Finder window's -go:, -load:, -dm_list,
// -setItems:error:, -applySearch, -reload, -refresh, -layoutSubviews, the list's and the icons' data source (cells with their thumbnail
// callbacks), -dm_showSelection (and, where they exist, -dm_reload:rows: and -dm_showSelectionAt:in:), -dm_setSelection:anchor:,
// -dm_selectedItems, -dm_selectedItem, -dm_scrollToPath:, -dm_beginInlineRename:, -dm_selectPathsWhenListed:, -dm_renameWhenListed:, and the
// functions DMFinderColumns (fr-cols.inc), DMFinderFront, DMFinderOpen, DMFinderStackReveal. On REAL UIKit table and collection views; the listing is the real
// asynchronous one (a background queue, then the main queue). The rest are stand-ins below: the native window and its -show as NativeWindow.h's
// (on the layer; the layer laid out at once only when it was hidden: test-finderreveal.sh reads that from NativeWindow.h), the folders' items,
// the thumbnails (asked, then delivered when a case says so). The screen's next update is the layer's layout, done by each case where it comes.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <os/lock.h>
#include <unistd.h>
#include <signal.h>
#include <execinfo.h>
#include "../common/FinderSort.h"

static int gKFails, gKPasses;
static const char *gKStep = "start";
#define KSTEP(s) (gKStep = (s))
static void KCheck(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (ok) gKPasses++; else gKFails++; }

// ---- what the real code logs and marks
static NSMutableArray<NSString *> *gKLog;
static void KLog(NSString *s) { @synchronized (gKLog) { [gKLog addObject:s ?: @""]; } }
#define DMLog(...) KLog(__VA_ARGS__)
#define DM_FEATURE_MARK(name)

// ---- Finder's items and folders (stand-ins: the folders the cases list, every place can be written)
@interface DMFinderItem : NSObject
@property (nonatomic, copy) NSString *path, *name, *display, *kind, *app;
@property (nonatomic) BOOL dir, locked, package, alias, cloud;
@property (nonatomic) unsigned long long size;
@property (nonatomic, strong) NSDate *date;
@end
@implementation DMFinderItem @end
static NSString *const kFinderTrash = @"/var/mobile/.Trash";
static NSString *const kKDocs = @"/var/mobile/Documents";
static NSDictionary<NSString *, NSArray<NSString *> *> *gKFolders;   // (folder -> its items' names; a name ending in "/" is a folder)
static DMFinderItem *KItemAt(NSString *folder, NSString *n) {
    DMFinderItem *it = [DMFinderItem new];
    BOOL dir = [n hasSuffix:@"/"]; NSString *name = dir ? [n substringToIndex:n.length - 1] : n;
    it.name = name; it.display = name; it.path = [folder stringByAppendingPathComponent:name]; it.dir = dir; it.kind = dir ? @"Folder" : @"Document"; it.size = 2;
    it.date = [NSDate dateWithTimeIntervalSince1970:1700000000];
    return it;
}
static NSArray *DMFinderList(NSString *path, BOOL hidden, NSError **err) {   // (on the background queue, as the real one)
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *n in gKFolders[path]) [a addObject:KItemAt(path, n)];
    return a;
}
static DMFinderItem *DMFinderItemFor(NSString *path) {
    NSString *folder = path.stringByDeletingLastPathComponent;
    for (NSString *n in gKFolders[folder]) { DMFinderItem *it = KItemAt(folder, n); if ([it.path isEqualToString:path]) return it; }
    return nil;
}
static NSString *DMFinderNorm(NSString *p) { return p; }
static void DMFinderSizeCancel(id w, NSString *p) {}
static MSBDSortChoice DMFinderSortFor(NSString *p) { return kMSBDSortDefault; }
static NSArray *DMFinderSorted(NSArray *items, MSBDSortChoice s) { return items; }
static NSString *DMFinderContainerName(NSString *p) { return nil; }
static NSDictionary *DMFinderAppFolderAt(NSString *p) { return nil; }
static NSString *DMFinderOnMyIPad(void) { return kKDocs; }
static unsigned long long DMFinderFreeSpace(NSString *p) { return ULLONG_MAX; }
static NSUInteger DMDockTrashCountNow(void) { return 0; }
static os_unfair_lock gFinderAppFoldersLock = OS_UNFAIR_LOCK_INIT;
static NSArray *gFinderAppFoldersCache;
static BOOL DMFinderCanWriteInto(NSString *p) { return YES; }
static BOOL DMFinderInOwnTrash(NSString *p) { return NO; }
static UIImage *DMFinderIconWithAlias(DMFinderItem *it, CGFloat side) { return nil; }
static NSString *DMFinderDate(NSDate *d) { return @"Today"; }
static NSString *DMFinderSize(DMFinderItem *it) { return @"2 bytes"; }
static BOOL MSBDFolderSizeWanted(BOOL dir, BOOL alias, BOOL locked, BOOL cloud) { return NO; }
static void DMFinderSizeAsk(NSString *p, id w, BOOL first) {}
static const void *kFinderCellSizePathKey = &kFinderCellSizePathKey;
static BOOL DMDriveCanEject(void) { return NO; }
static BOOL DMDriveEjecting(NSString *root) { return NO; }
static void DMDriveEject(NSString *root, NSString *name) {}
static void DMICleanOpenPanel(void) {}
static BOOL gFinderOn = YES;
static BOOL DMGARefuses(NSString *what) { return NO; }
static CGRect DMNativeDesktop(void) { return CGRectMake(0, 0, 1366, 1024); }
static void DMFinderOpenWithIndex(BOOL now) {}

#include "fr-cols.inc"   // (the list's columns: DMFinderColumns)

// ---- thumbnails: a picture's (.jpg) or a PDF's is made in the background the first time it is asked, then its row's callback runs
static NSMutableDictionary<NSString *, id> *gKThumbAsks;   // (key -> the callback of the first ask, while it is being made)
static NSMutableSet<NSString *> *gKThumbMade;
static UIImage *gKThumbImage;
static UIImage *DMFinderThumb(DMFinderItem *it, CGFloat side, void (^done)(void)) {
    NSString *ext = it.path.pathExtension.lowercaseString;
    if (it.dir || !([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"pdf"])) return nil;
    NSString *key = [NSString stringWithFormat:@"%@|%.0f", it.path, side];
    if ([gKThumbMade containsObject:key]) return gKThumbImage;
    if (!gKThumbAsks[key]) gKThumbAsks[key] = done ? [done copy] : [NSNull null];
    return nil;
}
static int KDeliverThumbs(CGFloat side) {   // (the thumbnails of that size being made are in: their callbacks run on the main queue, as the real ones)
    int n = 0;
    for (NSString *key in [gKThumbAsks allKeys]) {
        if (![key hasSuffix:[NSString stringWithFormat:@"|%.0f", side]]) continue;
        id done = gKThumbAsks[key]; [gKThumbAsks removeObjectForKey:key]; [gKThumbMade addObject:key];
        if ([done isKindOfClass:[NSNull class]]) continue;
        ((void (^)(void))done)(); n++;
    }
    return n;
}

// ---- the native layer and its windows (NativeWindow.h's, as far as these cases need them)
static NSMutableArray *gNativeWindows;
static UIView *gKHost;          // (the layer's container; a plain view: a table in a window here needs an app)
static BOOL gKLayerHidden;      // (no native window on the screen: the layer is hidden)
@interface KLayer : UIWindow @end
@implementation KLayer - (BOOL)isKeyWindow { return YES; } - (void)makeKeyWindow {} @end
static KLayer *gNativeLayer;
@interface DMNativeWindow : UIView { @public UIView *_content; }
@property (nonatomic, copy) NSString *title;
@property (nonatomic) CGFloat titleBarHeight;
@property (nonatomic) BOOL fullSizeContent, showsTitle;
@property (nonatomic) CGSize minSize;
@property (nonatomic, readonly) UIView *contentView;
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame;
- (void)show; - (void)activate;
@end
@implementation DMNativeWindow
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    self = [super initWithFrame:frame]; if (!self) return nil;
    _content = [[UIView alloc] initWithFrame:self.bounds]; [self addSubview:_content];
    self.title = title;
    return self;
}
- (UIView *)contentView { return _content; }
- (void)layoutSubviews { [super layoutSubviews]; _content.frame = self.bounds; }
// (NativeWindow.h's -show: in the windows' list, on the layer, shown; the layer is laid out at once only when it was hidden)
- (void)show {
    if (![gNativeWindows containsObject:self]) [gNativeWindows addObject:self];
    if (self.superview != gKHost) [gKHost addSubview:self];
    self.hidden = NO;
    if (gKLayerHidden) { gKLayerHidden = NO; [gKHost layoutIfNeeded]; }
}
- (void)activate {}
@end
@interface DMQuickLookWindow : DMNativeWindow - (void)dm_follow:(NSString *)path; @end
@implementation DMQuickLookWindow - (void)dm_follow:(NSString *)path {} @end
@interface KSearch : UIView @property (nonatomic, copy) NSString *text; @end
@implementation KSearch @end

// ---- a Finder window: its views as Finder.h's init makes them (the parts the real methods lay out and read), the real methods, stand-ins for the rest
@interface DMFinderWindow : DMNativeWindow <UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UITextFieldDelegate> {
@public
    UITableView *_sidebar, *_list;
    UICollectionView *_grid;
    UIView *_toolbar, *_toolbarBack, *_sideBack, *_header, *_trashBar;
    UIButton *_back, *_fwd, *_viewSwitch, *_selectButton, *_emptyButton;
    UILabel *_folderLabel, *_status, *_empty;
    KSearch *_search;
    NSArray<NSDictionary *> *_places;
    NSArray<DMFinderItem *> *_all, *_items;
    NSMutableArray<NSString *> *_history; NSInteger _hpos;
    BOOL _icons, _hidden, _resortShownOnly;
    NSString *_selected, *_statusBase, *_lastClickPath;
    NSMutableOrderedSet<NSString *> *_sel;
    UITextField *_renameField; NSString *_renamePath, *_renameWhenListed;
    NSArray<NSString *> *_selectWhenListed;
    NSUInteger _watchApps, _trashCount, _sizeListing;
    unsigned long long _free;
    NSMutableSet<NSString *> *_sizeChecked;
    MSBDSortChoice _sort;
}
@property (nonatomic, copy) NSString *path;
@end
@implementation DMFinderWindow
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    self = [super initWithTitle:title frame:frame]; if (!self) return nil;
    self.minSize = CGSizeMake(520.0, 320.0); self.titleBarHeight = 52.0; self.fullSizeContent = YES;
    _history = [NSMutableArray array]; _hpos = -1; _places = @[]; _sel = [NSMutableOrderedSet orderedSet]; _sort = kMSBDSortDefault;
    UIView *c = self.contentView;
    _sideBack = [UIView new]; _sidebar = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _toolbarBack = [UIView new]; _toolbar = [UIView new];
    for (UIView *v in @[_sideBack, _sidebar, _toolbarBack, _toolbar]) [c addSubview:v];
    _back = [UIButton buttonWithType:UIButtonTypeSystem]; _fwd = [UIButton buttonWithType:UIButtonTypeSystem];
    _viewSwitch = [UIButton buttonWithType:UIButtonTypeSystem]; _selectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _folderLabel = [UILabel new]; _search = [KSearch new];
    for (UIView *v in @[_back, _fwd, _folderLabel, _viewSwitch, _selectButton, _search]) [_toolbar addSubview:v];
    _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _list.dataSource = self; _list.delegate = self; _list.rowHeight = 26.0; _list.separatorStyle = UITableViewCellSeparatorStyleNone;
    [c addSubview:_list];
    _header = [UIView new];
    for (NSString *t in @[@"Name", @"Date Modified", @"Size", @"Kind"]) { UILabel *h = [UILabel new]; h.text = t; [_header addSubview:h]; }
    UIView *line = [UIView new]; line.tag = 9; [_header addSubview:line];
    [c addSubview:_header];
    _trashBar = [UIView new]; _trashBar.hidden = YES; _emptyButton = [UIButton buttonWithType:UIButtonTypeSystem]; [_emptyButton setTitle:@"Empty" forState:UIControlStateNormal];
    UIView *trashLine = [UIView new]; trashLine.tag = 9; for (UIView *v in @[_emptyButton, trashLine]) [_trashBar addSubview:v];
    [c addSubview:_trashBar];
    UICollectionViewFlowLayout *fl = [UICollectionViewFlowLayout new];
    fl.itemSize = CGSizeMake(96.0, 96.0); fl.minimumInteritemSpacing = 8.0; fl.minimumLineSpacing = 12.0; fl.sectionInset = UIEdgeInsetsMake(14, 14, 14, 14);
    _grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:fl];
    _grid.dataSource = self; _grid.delegate = self;
    [_grid registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"i"];
    [c addSubview:_grid];
    _list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    if (@available(iOS 15.0, *)) _list.sectionHeaderTopPadding = 0;
    _grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _status = [UILabel new]; [c addSubview:_status];
    _empty = [UILabel new]; [c addSubview:_empty];
    _list.allowsMultipleSelection = YES; _grid.allowsMultipleSelection = YES;
    return self;
}
- (void)dm_showSort {}
- (void)dm_watch:(NSString *)path {}
- (void)dm_sortSizesSoon {}
- (void)dm_endRename:(BOOL)commit { [_renameField removeFromSuperview]; _renameField = nil; _renamePath = nil; }
- (DMQuickLookWindow *)dm_quickLookWindow { return nil; }
- (void)dm_axItemCell:(UIView *)cell item:(DMFinderItem *)it {}
#include "fr-finder.inc"
@end

#include "fr-funcs.inc"

// ---- the cases
static void KSpin(double s) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static NSString *KFolder(NSString *n) { return [kKDocs stringByAppendingPathComponent:n]; }
static BOOL KListed(DMFinderWindow *w, NSString *folder) {   // (the main queue runs until that window shows that folder's listing: the real -dm_list's hop)
    for (int i = 0; i < 200; i++) {
        if ([w.path isEqualToString:folder] && w->_all && w->_all.count == gKFolders[folder].count) return YES;
        KSpin(0.01);
    }
    return NO;
}
static void KScreenUpdate(void) { [gKHost layoutIfNeeded]; }   // (the screen's next update: the layer and the windows in it are laid out)
static NSInteger KRowOf(DMFinderWindow *w, NSString *path) { for (NSInteger i = 0; i < (NSInteger)w->_items.count; i++) if ([w->_items[i].path isEqualToString:path]) return i; return NSNotFound; }
// The item is shown selected in the view on the screen (the list, or the icons): in UIKit's own selection, and its row's cell (made by the
// view's layout) is drawn selected. The model (_sel) is checked apart.
static BOOL KShown(DMFinderWindow *w, NSString *path) {
    NSInteger i = KRowOf(w, path); if (i == NSNotFound) return NO;
    if (w->_icons) {
        [w->_grid layoutIfNeeded];
        NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:0];
        UICollectionViewCell *c = [w->_grid cellForItemAtIndexPath:ip];
        return [w->_grid.indexPathsForSelectedItems containsObject:ip] && c && c.selected;
    }
    [w->_list layoutIfNeeded];
    NSIndexPath *ip = [NSIndexPath indexPathForRow:i inSection:0];
    UITableViewCell *c = [w->_list cellForRowAtIndexPath:ip];
    return [w->_list.indexPathsForSelectedRows containsObject:ip] && c && c.selected;
}
static NSUInteger KShownCount(DMFinderWindow *w) { [w->_list layoutIfNeeded]; [w->_grid layoutIfNeeded]; return w->_icons ? w->_grid.indexPathsForSelectedItems.count : w->_list.indexPathsForSelectedRows.count; }
static BOOL KInView(DMFinderWindow *w, NSString *path) {   // (its row wholly inside the list's visible part)
    NSInteger i = KRowOf(w, path); if (i == NSNotFound) return NO;
    [w->_list layoutIfNeeded];
    return CGRectContainsRect(w->_list.bounds, [w->_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]]);
}
static BOOL KLogged(NSString *line) { @synchronized (gKLog) { return [gKLog containsObject:line]; } }
static void KReset(BOOL layerHidden) {   // (no window open; the layer hidden or not; no thumbnail made)
    for (UIView *v in [gKHost.subviews copy]) [v removeFromSuperview];
    [gNativeWindows removeAllObjects];
    gKLayerHidden = layerHidden;
    [gKThumbAsks removeAllObjects]; [gKThumbMade removeAllObjects];
    @synchronized (gKLog) { [gKLog removeAllObjects]; }
}
static DMFinderWindow *KOpenOther(void) {   // (a Finder window on another folder: a native window on the screen, laid out)
    DMFinderOpen(KFolder(@"other"), YES);
    DMFinderWindow *o = DMFinderFront();
    KListed(o, KFolder(@"other")); KScreenUpdate();
    return o;
}

static void KCrashed(int sig) {
    void *f[48]; int n = backtrace(f, 48);
    fprintf(stderr, "CRASH signal %d in step: %s\n", sig, gKStep);
    backtrace_symbols_fd(f, n, 2);
    _exit(99);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGSEGV, KCrashed); signal(SIGBUS, KCrashed); signal(SIGILL, KCrashed); signal(SIGTRAP, KCrashed); signal(SIGABRT, KCrashed);
    @autoreleasepool {
        KSTEP("setup");
        gKLog = [NSMutableArray array]; gNativeWindows = [NSMutableArray array];
        gKThumbAsks = [NSMutableDictionary dictionary]; gKThumbMade = [NSMutableSet set];
        gKThumbImage = [[UIImage alloc] init];
        gNativeLayer = [[KLayer alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        gKHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
        NSMutableArray *longNames = [NSMutableArray array]; for (int i = 0; i < 60; i++) [longNames addObject:[NSString stringWithFormat:@"f%02d.txt", i]];
        gKFolders = @{ KFolder(@"MSBD-dltest"): @[@"test-first2.txt", @"test-folder/", @"test-later.txt", @"test-newest.txt", @"photo.jpg"],
                       KFolder(@"long"): longNames,
                       KFolder(@"other"): @[@"a.txt", @"b.txt"] };
        NSString *dl = KFolder(@"MSBD-dltest"), *newest = [dl stringByAppendingPathComponent:@"test-newest.txt"], *photo = [dl stringByAppendingPathComponent:@"photo.jpg"];
        NSString *later = [dl stringByAppendingPathComponent:@"test-later.txt"];

        // ---- R1: the device pass's case. Another Finder window is on the screen; Show in Enclosing Folder opens a new window; its listing lands
        //      before the screen's next update (a small folder), then the update lays the new window out.
        KSTEP("R1");
        KReset(NO); KOpenOther();
        DMFinderStackReveal(newest, NO);
        DMFinderWindow *w = DMFinderFront();
        KCheck(w && [w.path isEqualToString:dl] && gNativeWindows.count == 2 && KLogged(@"[finder] Downloads stack: Show in Enclosing Folder in a Finder window"),
               @"R1 Show in Enclosing Folder, another Finder window open: a NEW Finder window on the item's folder (\"in a Finder window\")");
        KCheck(KListed(w, dl), @"R1 ... its listing lands (background queue, then the main queue) before the screen's next update");
        KCheck([w->_sel containsObject:newest] && !w->_selectWhenListed, @"R1 ... the listing selected the item (_sel), the pending selection used");
        KScreenUpdate();
        KCheck(KShown(w, newest), @"R1 ... after the screen's update (the window's first layout): test-newest.txt SHOWN selected in the list (the pass's FAIL)");
        KCheck(KShownCount(w) == 1, @"R1 ... and only it");

        // ---- R2: no other native window (the layer hidden: -show lays it out at once), the listing after
        KSTEP("R2");
        KReset(YES);
        DMFinderStackReveal(newest, NO); w = DMFinderFront();
        KCheck(KListed(w, dl), @"R2 no native window open: a new window, its listing lands");
        KScreenUpdate();
        KCheck(KShown(w, newest) && KShownCount(w) == 1, @"R2 ... test-newest.txt shown selected, only it");

        // ---- R3: a window on the folder already open: it comes forward, listed again
        KSTEP("R3");
        KReset(NO); KOpenOther();
        DMFinderOpen(dl, YES); DMFinderWindow *open = DMFinderFront(); KListed(open, dl); KScreenUpdate();
        DMFinderOpen(KFolder(@"other"), YES); KListed(DMFinderFront(), KFolder(@"other")); KScreenUpdate();   // (another window in front of it)
        NSUInteger before = gNativeWindows.count;
        @synchronized (gKLog) { [gKLog removeAllObjects]; }
        open->_all = nil;   // (to see its new listing land)
        DMFinderStackReveal(newest, NO);
        KCheck(gNativeWindows.count == before && KLogged(@"[finder] Downloads stack: Show in Enclosing Folder in a Finder window"), @"R3 a window on the folder open: no new window, that one used");
        KListed(open, dl); KScreenUpdate();
        KCheck(KShown(open, newest) && KShownCount(open) == 1, @"R3 ... test-newest.txt shown selected (the pass's PASS)");

        // ---- R4: Rename from the stack, new window, the listing before the first layout: the name edited in place in the real row
        KSTEP("R4");
        KReset(NO); KOpenOther();
        DMFinderStackReveal(later, YES); w = DMFinderFront();
        KListed(w, dl);
        UITextField *tf = w->_renameField;
        NSInteger row = KRowOf(w, later);
        CGRect rr = row == NSNotFound ? CGRectNull : [w->_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]];
        KCheck(tf && tf.superview == w->_list && [tf.text isEqualToString:@"test-later.txt"], @"R4 Rename, new window, listing first: the name is edited in place (a field in the list)");
        KCheck(tf && w->_list.bounds.size.width > 400 && tf.frame.size.width >= 150 && tf.frame.size.height >= 18 && !CGRectIsNull(rr) && CGRectContainsRect(rr, tf.frame),
               [NSString stringWithFormat:@"R4 ... in a list with its size, the field on the item's row with room for the name (list %.0f wide, field %@)", w->_list.bounds.size.width, tf ? NSStringFromCGRect(tf.frame) : @"none"]);
        KScreenUpdate();
        KCheck(w->_renameField == tf && KShown(w, later), @"R4 ... after the screen's update: still editing, the row shown selected");

        // ---- R5: a long folder: the item revealed is scrolled into view (the listing before the first layout)
        KSTEP("R5");
        KReset(NO); KOpenOther();
        NSString *f30 = [KFolder(@"long") stringByAppendingPathComponent:@"f30.txt"];
        DMFinderStackReveal(f30, NO); w = DMFinderFront();
        KListed(w, KFolder(@"long")); KScreenUpdate();
        KCheck(KInView(w, f30), [NSString stringWithFormat:@"R5 a 60-item folder, f30.txt revealed in a new window: its row in view (list offset %.0f, row at %.0f)", w->_list.contentOffset.y, 30 * 26.0]);
        KCheck(KShown(w, f30), @"R5 ... and shown selected");

        // ---- R6: a resize of the window in list view keeps the highlight (the list reloads for its new width)
        KSTEP("R6");
        KReset(YES);
        DMFinderOpen(dl, YES); w = DMFinderFront(); KListed(w, dl); KScreenUpdate();
        [w dm_setSelection:@[later] anchor:later];
        KCheck(KShown(w, later), @"R6 an item selected by a click: shown selected");
        CGRect fr = w.frame; fr.size.width += 140.0; w.frame = fr; KScreenUpdate();
        KCheck(KShown(w, later) && KShownCount(w) == 1, @"R6 ... the window made wider (the list reloads for its width): still shown selected, only it");
        fr.size.width -= 200.0; w.frame = fr; KScreenUpdate();
        KCheck(KShown(w, later) && KShownCount(w) == 1, @"R6 ... and narrower: still shown selected");
        [w dm_setSelection:@[] anchor:nil];
        fr.size.width += 60.0; w.frame = fr; KScreenUpdate();
        KCheck(KShownCount(w) == 0, @"R6 ... nothing selected, then a resize: nothing shown selected");

        // ---- R7: a picture revealed in a new window: its thumbnail comes in after the listing, its row reloads, it stays selected
        KSTEP("R7");
        KReset(NO); KOpenOther();
        DMFinderStackReveal(photo, NO); w = DMFinderFront();
        KListed(w, dl); KScreenUpdate();
        KCheck(KShown(w, photo), @"R7 photo.jpg revealed in a new window: shown selected");
        int got = KDeliverThumbs(18.0);
        KCheck(got == 1, [NSString stringWithFormat:@"R7 ... its list thumbnail was asked and comes in (%d callback)", got]);
        KCheck(KShown(w, photo) && KShownCount(w) == 1, @"R7 ... after its row's reload: still shown selected, only it");

        // ---- R8: the icons: a selected picture's thumbnail comes in
        KSTEP("R8");
        KReset(YES);
        DMFinderOpen(dl, YES); w = DMFinderFront(); KListed(w, dl);
        w->_icons = YES; [w setNeedsLayout]; KScreenUpdate(); [w reload];
        [w dm_setSelection:@[photo] anchor:photo];
        KCheck(KShown(w, photo), @"R8 icon view, photo.jpg selected: shown selected");
        got = KDeliverThumbs(56.0);
        KCheck(got == 1 && KShown(w, photo) && KShownCount(w) == 1, [NSString stringWithFormat:@"R8 ... its icon's thumbnail comes in (%d callback), the icon reloads: still shown selected, only it", got]);

        // ---- R9: a thumbnail for an item NOT selected leaves it unselected (another item selected; then none)
        KSTEP("R9");
        KReset(YES);
        DMFinderOpen(dl, YES); w = DMFinderFront(); KListed(w, dl); KScreenUpdate(); KShown(w, later);
        [w dm_setSelection:@[later] anchor:later];
        KDeliverThumbs(18.0);
        KCheck(KShown(w, later) && !KShown(w, photo) && KShownCount(w) == 1, @"R9 test-later.txt selected, photo.jpg's thumbnail comes in: photo not shown selected, the other still is");
        KReset(YES);
        DMFinderOpen(dl, YES); w = DMFinderFront(); KListed(w, dl); KScreenUpdate(); KShown(w, later);
        KDeliverThumbs(18.0);
        KCheck(KShownCount(w) == 0, @"R9 ... nothing selected, a thumbnail comes in: nothing shown selected");

        // ---- R10: a click's selection (-dm_setSelection:anchor:, -dm_showSelection) as before: several, then one, then none, list and icons
        KSTEP("R10");
        [w dm_setSelection:@[newest, later] anchor:later];
        BOOL two = KShown(w, newest) && KShown(w, later) && KShownCount(w) == 2 && [w->_status.text isEqualToString:@"2 of 5 selected"];
        [w dm_setSelection:@[newest] anchor:newest];
        BOOL one = KShown(w, newest) && !KShown(w, later) && KShownCount(w) == 1;
        w->_icons = YES; [w setNeedsLayout]; KScreenUpdate();
        BOOL icons = KShown(w, newest) && KShownCount(w) == 1;
        [w dm_setSelection:@[] anchor:nil];
        BOOL none = KShownCount(w) == 0; w->_icons = NO; [w setNeedsLayout]; KScreenUpdate(); none = none && KShownCount(w) == 0;
        KCheck(two && one && icons && none, @"R10 a click's selection shown as before: two (\"2 of 5 selected\"), then one, the icons the same, then none");
    }
    printf("%d passed, %d failed\n", gKPasses, gKFails);
    return gKFails;
}
