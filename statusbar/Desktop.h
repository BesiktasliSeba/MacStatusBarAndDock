// Desktop.h -- the Mac desktop on the Home Screen (2026-10-03), included into StatusBar.x after Finder.h.
// The files of the folder "Desktop" in On My iPad (DMFinderDesktopFolder) are icons on the Home Screen's FIRST page, like a Mac's desktop behind
// its windows:
//  - The view lives inside page 1's icon list (SBIconListView), behind the app icons: it scrolls away with the page, is never on another page,
//    in the App Library or the Today View, and app windows and full-screen apps cover it as they cover the Home Screen. Jiggle mode: hidden.
//  - Free placement: an icon goes where it is dropped, kept by name in our own plist (com.besiktasliseba.macstatusbar.desktop), as a fraction of
//    the page's free area (so a turn keeps the arrangement). Icons never leave the page's area (below the menu bar, above the Dock) and never
//    cover an app icon or widget: dropped on one, an icon slides to the nearest free spot. New icons take the next free spot from the top right,
//    as on a Mac; with no free spot left, further icons are stacked on the last free one (DesktopPlace.h). A rename -- here, in Finder or in
//    the Files app -- keeps the place (the file's inode is followed).
//  - Mac actions: tap / click selects, double tap / double click opens (a folder in a Finder window, a file as Finder opens it), a held finger or
//    a right click opens the menu (Open, Quick Look, Get Info, Rename, Move to Trash; on the empty desktop with a pointer: New Folder, Paste,
//    Undo), a pointer drag on the empty desktop selects with a rectangle, the keys of a Mac's desktop while it was clicked last.
//  - Every file change is Finder's (DMFinderOps: the policy -- only the user's own places --, Undo); every drag is Finder's own drag (into
//    Finder windows, onto folders here, the Dock's Downloads stack, app windows; and from them onto the desktop).
// One DMDesktop is one desktop -- its folder, its places, its view -- so a later Spaces feature can keep one per desktop.
#define kDesktopDomain CFSTR("com.besiktasliseba.macstatusbar.desktop")
#include "../common/DesktopCheck.h"   // (iPadOS 17+: the check's verdict, read by Settings -- DMDesktopNewOSReady)
#include "DesktopPlace.h"   // (where the icons go: the free spots, the grid, no room -- plain C, tested on the Mac)

@interface DMDesktopItemView : UIView
@property (nonatomic, strong) DMFinderItem *item;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UIView *back, *labelBack;   // (the selection: a dark rounded square behind the icon, a blue capsule behind the name)
@property (nonatomic, strong) UILabel *label;
@property (nonatomic) BOOL selected, dropTarget;
@property (nonatomic) CGFloat side;
@property (nonatomic, strong) UIColor *textColor;   // (the name's colour when not selected: the Home Screen's label colour)
- (void)dm_setDropHover:(BOOL)on;   // (Finder's drag over a folder here, Finder.h DMFDIconHover)
@end
static void DMDesktopAXOpen(DMDesktopItemView *v);   // (below, with DMDesktop)
@implementation DMDesktopItemView
// Assistive features (1.3.7, audit M-3): an icon is one element -- its name, its kind ("Folder", "PDF document"), a button, selected when it is in the
// desktop's selection --; using it opens it, as a double tap does (a single tap only selects, which VoiceOver's double tap would otherwise do).
- (BOOL)isAccessibilityElement { return YES; }
- (NSString *)accessibilityLabel { return self.item.display.length ? self.item.display : self.label.text; }
- (NSString *)accessibilityValue { return MSBDAXItemValue(self.item.kind, nil, nil); }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitButton | (self.selected ? UIAccessibilityTraitSelected : 0); }
- (BOOL)accessibilityActivate { DM_FEATURE_MARK("ax-desktop-icons"); DMDesktopAXOpen(self); return YES; }
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _back = [UIView new]; _back.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28]; _back.layer.cornerRadius = 8.0; _back.layer.cornerCurve = kCACornerCurveContinuous; _back.hidden = YES;
    _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeScaleAspectFit; _icon.accessibilityIgnoresInvertColors = YES;   // (Smart Invert leaves pictures as they are, like Apple's own icons: 1.3.3, audit L-3)
    _labelBack = [UIView new]; _labelBack.backgroundColor = [UIColor systemBlueColor]; _labelBack.hidden = YES;
    _label = [UILabel new]; _label.textAlignment = NSTextAlignmentCenter; _label.lineBreakMode = NSLineBreakByTruncatingTail; _label.numberOfLines = 1;
    for (UIView *v in @[_back, _icon, _labelBack, _label]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, s = self.side;
    _icon.frame = CGRectMake((w - s) / 2.0, 2.0, s, s);
    _back.frame = CGRectInset(_icon.frame, -4.0, -4.0);
    CGFloat lh = ceil(_label.font.lineHeight) + 2.0;
    CGFloat tw = MIN(w - 2.0, ceil([_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, lh)].width) + 10.0);
    _label.frame = CGRectMake(1.0, CGRectGetMaxY(_icon.frame) + 4.0, w - 2.0, lh);
    _labelBack.frame = CGRectMake((w - tw) / 2.0, _label.frame.origin.y, tw, lh);
    _labelBack.layer.cornerRadius = lh / 2.0;
}
- (void)setSelected:(BOOL)sel { _selected = sel; [self dm_look]; }
- (void)dm_setDropHover:(BOOL)on { _dropTarget = on; [self dm_look]; }
- (void)dm_look {   // (selected, or a folder taking a drag: as a Mac's desktop shows it)
    BOOL lit = _selected || _dropTarget;
    _back.hidden = !lit;
    _labelBack.hidden = !_selected;
    _label.layer.shadowOpacity = _selected ? 0.0 : 1.0;
    _label.textColor = _selected ? [UIColor whiteColor] : (_textColor ?: [UIColor whiteColor]);
}
@end

// A pointer's click, whatever type its touch has: here a mouse / trackpad click reaches SpringBoard as a DIRECT touch (type 0, from the pointer's
// own HID sender, M1 3 Oct) -- held to a finger's rule (hold first) a click-drag on the empty desktop never drew the rectangle. The event says it:
// a pressed button in -[UIEvent buttonMask] (pointer events only), or the touch's own -_isPointerTouch.
static NSInteger DMDesktopButtons(UIEvent *e) { if (@available(iOS 13.4, *)) return (NSInteger)e.buttonMask; return 0; }
static BOOL DMDesktopHIDFromPointer(UIEvent *e) {   // (the touch's raw HID event carries a pointer event as a child: type 17, see DMHIDTouchDesc)
    static CFArrayRef (*kids)(void *); static uint32_t (*type)(void *); static dispatch_once_t once;
    dispatch_once(&once, ^{ void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY); kids = dlsym(iokit, "IOHIDEventGetChildren"); type = dlsym(iokit, "IOHIDEventGetType"); });
    SEL hs = NSSelectorFromString(@"_hidEvent");
    void *h = e && [e respondsToSelector:hs] ? ((void *(*)(id, SEL))objc_msgSend)(e, hs) : NULL;
    if (!h || !kids || !type) return NO;
    CFArrayRef k = kids(h);
    for (CFIndex i = 0; k && i < CFArrayGetCount(k) && i < 8; i++) if (type((void *)CFArrayGetValueAtIndex(k, i)) == 17) return YES;
    return NO;
}
static BOOL DMDesktopPointerTouch(UITouch *t, UIEvent *e) {
    if (t.type == UITouchTypeIndirectPointer || DMDesktopButtons(e) != 0 || DMDesktopHIDFromPointer(e)) return YES;
    SEL s = NSSelectorFromString(@"_isPointerTouch");
    BOOL p = NO; @try { if ([t respondsToSelector:s]) p = ((BOOL (*)(id, SEL))objc_msgSend)(t, s); } @catch (NSException *x) {}
    return p;
}
@class DMDesktop;
static DMDesktop *gDesktop;
static BOOL gDesktopOn = YES;   // (Settings > Mac Status Bar > Show Desktop Icons; with Finder on)
// (for the untested-iPadOS diagnostics, DMDesktopDiag: what the last measure read from the Home Screen -- 1 the names' font, 2 their colours,
//  4 an app icon view to read them from, 8 the picture size from an icon view -- and where the folders' picture came from: 4 drawn, the folder
//  icon of 1.4 (1-3 were the Files app's Home Screen icon, iOS's own Files icon, none, before it was drawn))
static int gDesktopLookRead, gDesktopFolderFrom;
@interface DMDesktop : UIView <UIGestureRecognizerDelegate, UITextFieldDelegate, UIContextMenuInteractionDelegate>
@property (nonatomic, copy) NSString *folder;
- (instancetype)initWithFolder:(NSString *)folder;
- (void)dm_tick;
- (void)dm_detach;
- (void)dm_teardown;
- (BOOL)dm_shownAt:(CGPoint)sp;
- (DMDesktopItemView *)dm_itemViewAtScreen:(CGPoint)sp;
- (void)dm_takeDrop:(DMFDrag *)d at:(CGPoint)sp into:(NSString *)dest ontoFolder:(BOOL)ontoFolder;
- (void)dm_touchBegan:(UITouch *)t;
- (void)dm_event:(UIEvent *)e;
- (BOOL)dm_hasKeys;
- (BOOL)dm_handleKey:(UIKey *)key;
- (void)dm_made:(NSArray<NSString *> *)paths;
- (void)dm_fitRenameField;
- (NSString *)dm_placeStringFor:(NSString *)path;
- (NSString *)dm_diagLine;   // (untested iPadOS diagnostics, DMDesktopDiag: where it sits and what it found there; names and numbers only)
- (void)dm_axOpen:(DMDesktopItemView *)v;
#if DEBUG
- (void)dm_debug:(NSString *)spec;
#endif
@end

// SpringBoard's keyboard focus while a name is edited on the desktop (the Home Screen has no keyboard of its own), as the Dock's Downloads search
// takes it: given back when the editing ends.
static id gDesktopFocusLock;
static void DMKeyboardDockWatch(void);
static void DMDesktopFocus(BOOL take) {
    if (take) DMKeyboardDockWatch();
    if (!take) { id l = gDesktopFocusLock; gDesktopFocusLock = nil; if ([l respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(l, @selector(invalidate)); return; }
    if (gDesktopFocusLock) return;
    id ws = nil; Class wsc = objc_getClass("SBMainWorkspace");
    if (wsc && [(id)wsc respondsToSelector:@selector(sharedInstance)]) ws = ((id (*)(id, SEL))objc_msgSend)((id)wsc, @selector(sharedInstance));
    id kfc = DMCall(ws, @"keyboardFocusController");
    SEL l16 = NSSelectorFromString(@"lockFocusToSpringBoardWindowScene:forReason:"), l15 = NSSelectorFromString(@"lockFocusToSpringBoardForReason:");
    UIWindowScene *scene = gDesktop.window.windowScene;
    @try {
        if ([kfc respondsToSelector:l16] && scene) gDesktopFocusLock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, l16, scene, @"MacStatusBar Desktop");
        else if ([kfc respondsToSelector:l15]) gDesktopFocusLock = ((id (*)(id, SEL, id))objc_msgSend)(kfc, l15, @"MacStatusBar Desktop");
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[desktop] keyboard focus lock threw %@", e.reason]); }
}

// The Dock's window under the Home Screen's, for as long as any reason holds (a desktop menu is up, our own on-screen keyboard is up); its own
// level back when the last one goes, unless SpringBoard changed it meanwhile.
static NSMutableSet<NSString *> *gDockUnderReasons;
static __weak UIWindow *gDockLowered; static CGFloat gDockLevelWas, gDockLevelLow;
static void DMDesktopDockUnder(NSString *reason, BOOL on, CGFloat low) {
    if (!gDockUnderReasons) gDockUnderReasons = [NSMutableSet set];
    if (on) [gDockUnderReasons addObject:reason]; else [gDockUnderReasons removeObject:reason];
    if (gDockUnderReasons.count) {
        if (gDockLowered) return;
        for (UIWindow *w in DMAllWindows()) if ([NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"] && !w.hidden && w.windowLevel > low) {
            gDockLowered = w; gDockLevelWas = w.windowLevel; gDockLevelLow = low; w.windowLevel = low;
            DMLog([NSString stringWithFormat:@"[desktop] %@: the Dock's window from level %.0f to %.0f, under the Home Screen's, as for an app icon's menu", reason, gDockLevelWas, low]);
            break;
        }
        return;
    }
    UIWindow *w = gDockLowered; gDockLowered = nil;
    if (w && fabs(w.windowLevel - gDockLevelLow) < 0.01) { w.windowLevel = gDockLevelWas; DMLog([NSString stringWithFormat:@"[desktop] %@ gone: the Dock's window back to level %.0f", reason, gDockLevelWas]); }
}
// A context menu in this window, open or still closing (UIKit's container stays until its close has played).
static BOOL DMDesktopMenuShown(UIWindow *w) {
    if (!w) return NO;
    NSMutableArray *names = [NSMutableArray array];
    DMCollectClassNames(w, 0, names);
    return [names containsObject:@"_UIContextMenuContainerView"];
}
// SpringBoard's own keyboard (a text window, Finder's fields, a name edited on the desktop) is put just above the window being typed in, so for
// our windows -- the Home Screen's (-2), the native windows' (6 when active) -- it was UNDER the Dock (25): the Dock's icons covered the
// keyboard's bottom row, its space bar included (iPad 2, iPadOS 16, measured with winlist: keyboard windows at 7 / 8). When an app shows its
// keyboard, the Dock goes away (Stage Manager hides the in-app Dock for it; a full-screen app has no Dock); for ours the Dock goes under the
// Home Screen while a docked on-screen keyboard is up for one of our fields (SpringBoard holding the keyboard focus for them, gNativeFocusLock /
// gDesktopFocusLock), and comes back as it hides. A hardware keyboard's bar, a floating or a split keyboard leave the Dock alone.
static BOOL DMDesktopOwnKeyboard(void) { return gNativeFocusLock != nil || gDesktopFocusLock != nil; }
static NSString *DMDesktopPlaceFor(NSString *path);
static void DMDesktopKeyboardMoved(void);  // (a name being edited stays above it: -dm_fitRenameField)
static void DMKeyboardDockWatch(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            NSValue *v = n.userInfo[UIKeyboardFrameEndUserInfoKey];
            CGRect f = [v isKindOfClass:[NSValue class]] ? v.CGRectValue : CGRectZero;
            // (SpringBoard is told the frame in the screen's fixed, portrait space: in landscape it read {360, 0, 408, 1024} on the iPad 2)
            UIScreen *screen = [UIScreen mainScreen]; CGSize scr = screen.bounds.size;
            CGRect g = [screen.fixedCoordinateSpace convertRect:f toCoordinateSpace:screen.coordinateSpace];
            BOOL (^isDocked)(CGRect) = ^BOOL(CGRect r) { return r.size.width >= scr.width - 1.0 && CGRectGetMaxY(r) >= scr.height - 1.0 && r.size.height > 150.0; };
            BOOL docked = isDocked(f) || isDocked(g);
            if (docked && DMDesktopOwnKeyboard()) DMDesktopDockUnder(@"keyboard", YES, -3.0);   // (-3: the level SpringBoard itself gives it under an icon menu)
            else DMDesktopDockUnder(@"keyboard", NO, -3.0);
            CGRect bounds = CGRectMake(0, 0, scr.width, scr.height);
            gOwnKeyboardFrame = DMDesktopOwnKeyboard() ? (CGRectContainsRect(CGRectInset(bounds, -1.0, -1.0), f) ? f : g) : CGRectZero;
            DMDesktopKeyboardMoved();
        }];
        [nc addObserverForName:UIKeyboardWillHideNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            DMDesktopDockUnder(@"keyboard", NO, -3.0);
            gOwnKeyboardFrame = CGRectZero;
            DMDesktopKeyboardMoved();
        }];
    });
}
@implementation DMDesktop {
    __weak UIView *_list;                                  // page 1's icon list (SBIconListView), our superview
    NSArray<DMFinderItem *> *_items;
    NSMutableDictionary<NSString *, DMDesktopItemView *> *_views;   // by name
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *_places; // by name: @[fx, fy], the icon's centre as a fraction of the free area
    NSDictionary<NSString *, NSNumber *> *_inodes;         // by name, from the last listing (a rename keeps the place)
    NSSet<NSString *> *_fresh;                             // names new in the last listing
    NSMutableSet<NSString *> *_back;                       // names back from the Trash in the last listing (placed last)
    NSMutableOrderedSet<NSString *> *_sel;                 // selected paths
    dispatch_source_t _watch; BOOL _watchPending, _listing, _relist;
    CGFloat _side, _cellW, _cellH; UIFont *_font; UIColor *_textColor, *_shadowColor;
    UIImage *_folderImage; CGFloat _folderImageSide;
    NSString *_iconSig; CFTimeInterval _sigAt, _listAt;
    BOOL _placeDirty; CGRect _placedArea; CGSize _placedCell; NSInteger _piled;   // (a layout pass only when what it depends on changed, see -dm_placeAgain)
    BOOL _syncPending; NSUInteger _saveGen;
    BOOL _folderMissing; dev_t _watchDev; ino_t _watchIno; CFTimeInterval _watchCheckedAt;   // (the folder watched: which one, see -dm_tick)
    BOOL _editing, _hasKeys, _renameNew;
    NSString *_lastTapPath; CFTimeInterval _lastTapAt; BOOL _lastTapPointer;
    // an icon lifted by a drag (see -dm_event:)
    DMDesktopItemView *_armed; BOOL _lifted;
    NSArray<DMDesktopItemView *> *_dragViews; CGPoint _dragGrab; CGRect _dragUnion;
    // the selection rectangle on the empty desktop: a pointer's drag, or a finger held 0.35 s and then moved
    UIView *_band; CGPoint _bandStart; NSOrderedSet<NSString *> *_bandBase;
    // a finger on the desktop, followed from SpringBoard's events (-dm_event:): held, then moved -- an icon's drag, or the rectangle
    __weak UITouch *_track; __weak DMDesktopItemView *_trackView; CGPoint _trackDown, _trackLast; CFTimeInterval _trackAt; int _trackMode; BOOL _trackPointer;   // (1 drag, 2 rectangle)
    NSInteger _trackFinger; NSTimeInterval _trackStamp;   // (the finger behind it, and the time of the last report of it used: see DMDesktopTouchFinger)
    // Haptic Touch menus (UIKit's, in our Mac look like the app icons' -- StatusBar.x's context menu theme): on each icon, and on the empty desktop
    UIContextMenuInteraction *_bgMenu; UIView *_bgAnchor;
    NSHashTable<UIGestureRecognizer *> *_menuGRs;           // (the menus' own gestures: never held up or cancelled by ours)
    __weak UIContextMenuInteraction *_menuOpen;
    __weak UIContextMenuInteraction *_menuClosing; CFTimeInterval _menuClosingAt;   // (a menu whose close is still playing, since when: -dm_menuLetsGo:)
    // icons that arrive soon after a drop or New Folder: placed where it happened
    CGPoint _arrivePoint; CFTimeInterval _arriveUntil; NSInteger _arriveLeft;
    NSArray<NSString *> *_selectWhenListed; NSString *_renameWhenListed;
    UITextField *_renameField; NSString *_renamePath; __weak UIWindow *_keyBefore; CGRect _renameHome;
}
- (instancetype)initWithFolder:(NSString *)folder {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    DM_FEATURE_MARK("desktop-icons");
    _folder = [folder copy];
    _views = [NSMutableDictionary dictionary]; _sel = [NSMutableOrderedSet orderedSet];
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CFPreferencesAppSynchronize(kDesktopDomain);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("places"), kDesktopDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *stored = v ? CFBridgingRelease(v) : nil;
    _places = [NSMutableDictionary dictionary];
    if ([stored isKindOfClass:[NSDictionary class]]) for (NSString *k in stored) { NSArray *p = stored[k]; if ([k isKindOfClass:[NSString class]] && [p isKindOfClass:[NSArray class]] && p.count == 2) _places[k] = p; }
    // icons: tap / double tap, a finger's hold-and-move (drag; holding still opens the Haptic Touch menu), a pointer's drag
    _menuGRs = [NSHashTable weakObjectsHashTable];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_tap:)];
    tap.delegate = self; tap.name = @"dm.desktop.tap";
    if (@available(iOS 13.4, *)) tap.buttonMaskRequired = UIEventButtonMaskPrimary;
    [self addGestureRecognizer:tap];
    // (a finger's hold-and-move is followed from SpringBoard's events, -dm_event: -- a long press of ours could never begin next to UIKit's menu)
    // the empty desktop (gestures on the icon list itself, only for touches on its empty space): the selection rectangle -- a pointer's drag, or a
    // finger held 0.35 s and moved (a quicker swipe still turns the page) -- and its Haptic Touch menu (a held finger, or a right click)
    _bgMenu = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    [self dm_watch];
    [self dm_list];
    return self;
}

// ---- where it is: page 1 of the Home Screen ----
// Page 1's icon list: the root folder view's own first icon list (-iconListViewAtIndex:0; the Today View page, when it is a page, is no icon list).
// Where that is not answered, the icon list (SBIconListView) in the root folder's scroll view (SBIconScrollView) nearest the start: the leftmost, the
// rightmost in a right-to-left language, where iPadOS lays the pages out from the right (iPad 2, Hebrew: page 1 at x 3072, page 4 at x 768 -- before
// 1.3.3 the desktop went on the last page there). Found once, checked on every tick (cheap), looked for again when it is gone.
// (SBIconController through DMSBManager: +sharedInstance on 15/16, as before; iPadOS 17+ only once SpringBoard has made it, +sharedInstanceIfExists
//  -- nil until then, and the next tick looks again)
static UIView *DMDesktopFindPageOne(void) {
    id ic = DMSBManager("SBIconController");
    UIViewController *rfc = DMCall(DMCall(ic, @"iconManager"), @"rootFolderController");
    if (![rfc isKindOfClass:[UIViewController class]] || !rfc.isViewLoaded) return nil;
    Class sc = objc_getClass("SBIconScrollView"), lc = objc_getClass("SBIconListView");
    if (!sc || !lc) return nil;
    {
        SEL rootView = NSSelectorFromString(@"rootFolderView"), folderView = NSSelectorFromString(@"folderView"), atIndex = NSSelectorFromString(@"iconListViewAtIndex:");
        id rfv = [rfc respondsToSelector:rootView] ? ((id (*)(id, SEL))objc_msgSend)(rfc, rootView) : [rfc respondsToSelector:folderView] ? ((id (*)(id, SEL))objc_msgSend)(rfc, folderView) : nil;
        UIView *first = [rfv respondsToSelector:atIndex] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(rfv, atIndex, 0) : nil;
        if ([first isKindOfClass:lc] && !first.hidden && [first.superview isKindOfClass:sc]) return first;
    }
    NSMutableArray *todo = [NSMutableArray arrayWithObject:rfc.view];
    UIView *scroll = nil;
    for (int depth = 0; depth < 8 && todo.count && !scroll; depth++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in todo) { if ([v isKindOfClass:sc]) { scroll = v; break; } [next addObjectsFromArray:v.subviews]; }
        todo = next;
    }
    UIView *first = nil;
    BOOL rtl = scroll.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (UIView *l in scroll.subviews) if ([l isKindOfClass:lc] && !l.hidden && (!first || (rtl ? l.frame.origin.x > first.frame.origin.x : l.frame.origin.x < first.frame.origin.x))) first = l;
    return first;
}
static BOOL DMDesktopEditing(void) {
    id im = DMCall(DMSBManager("SBIconController"), @"iconManager");
    return [im respondsToSelector:@selector(isEditing)] && ((BOOL (*)(id, SEL))objc_msgSend)(im, @selector(isEditing));
}
- (void)dm_detach {
    [self dm_endRename:NO];
    if (_bgMenu.view) { [_menuOpen dismissMenu]; [_bgMenu.view removeInteraction:_bgMenu]; }
    [self removeFromSuperview];
    _list = nil;
}
// Gone for good (Show Desktop Icons or Finder off): the folder's watch is cancelled -- a source released without it keeps its descriptor and its
// kernel event -- and the Dock is never left under the Home Screen for a menu of ours.
- (void)dm_teardown {
    [self dm_detach];
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    DMDesktopDockUnder(@"menu", NO, 0);
}
- (void)dealloc { if (_watch) dispatch_source_cancel(_watch); }
- (void)dm_tick {
    UIView *list = _list;
    BOOL ok = list && self.superview == list && list.window && list.superview;
    if (ok) {   // (still page 1: no list further left in the same scroll view -- a page was added, moved or hidden)
        static CFTimeInterval checked; if (CACurrentMediaTime() - checked > 2.0) { checked = CACurrentMediaTime();
            for (UIView *o in list.superview.subviews) if (o != list && [o isKindOfClass:[list class]] && !o.hidden && o.frame.origin.x < list.frame.origin.x) ok = NO; }
    }
    if (!ok) {
        UIView *found = DMDesktopFindPageOne();
        if (found && found != list) {
            [self dm_detach];
            _list = found;
            self.frame = found.bounds;
            [found insertSubview:self atIndex:0];   // (behind the app icons and widgets)
            [self dm_addMenu:_bgMenu to:found];
            _iconSig = nil;
            DMLog([NSString stringWithFormat:@"[desktop] on page 1 (%@ %@), %lu icons", NSStringFromClass([found class]), NSStringFromCGRect(found.bounds), (unsigned long)_items.count]);
            [self dm_placeAgain];
        }
        if (!found) return;
    }
    // (jiggle mode: the desktop steps aside, the Home Screen is being arranged; the same while a Guided Access session keeps the iPad in one app --
    //  the files would open in other apps, and Guided Access does not know our icons: 1.3.7, audit M-7)
    BOOL guided = MSBDGuidedAccessActive();
    BOOL editing = DMDesktopEditing() || guided;
    if (editing != _editing) {
        _editing = editing;
        if (editing) { [self dm_endRename:YES]; [_sel removeAllObjects]; [self dm_showSelection]; }
        self.userInteractionEnabled = !editing;
        for (UIGestureRecognizer *m in _menuGRs) if (m.view == _list) m.enabled = !editing;   // (jiggle mode: the empty page's long press is the Home Screen's again)
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = editing ? 0.0 : 1.0; }];
        static BOOL asideForGuided = NO; if (editing) asideForGuided = guided;   // (the reason it began, for the line that says it ended)
        DMLog([NSString stringWithFormat:@"[desktop] %@ %@: icons %@", asideForGuided ? @"Guided Access" : @"stepping aside (Home Screen editing)", editing ? @"began" : @"ended", editing ? @"hidden" : @"back"]);
    }
    // (never left under the Home Screen for a menu that is gone: a close whose completion never came -- an interaction taken off its view while its
    //  menu closed, -dm_detach -- kept the Dock's window low until the next desktop menu closed; the same safety as the Home Screen icon menus')
    if (!_menuOpen && self.window && [gDockUnderReasons containsObject:@"menu"] && !(_menuClosing && CACurrentMediaTime() - _menuClosingAt < 1.0)
        && !DMDesktopMenuShown(self.window)) { DMDesktopDockUnder(@"menu", NO, 0); DMLog(@"[desktop] a menu went without its close finishing: the Dock back (safety reset)"); }
    if (!CGRectEqualToRect(self.frame, _list.bounds)) self.frame = _list.bounds;
    if (CACurrentMediaTime() - _sigAt > 1.0) {   // (an app icon or widget added, moved or removed on page 1: icons that would be under it move)
        _sigAt = CACurrentMediaTime();
        NSString *sig = [self dm_iconSignature];
        if (![sig isEqualToString:_iconSig]) { _iconSig = sig; [self dm_placeAgain]; }
    }
    if (_placeDirty && !_editing && [self dm_pageShowing]) [self setNeedsLayout];   // (a pass held back while page 1 wasn't showing, or in jiggle mode)
    if (CACurrentMediaTime() - _watchCheckedAt > 2.0) {   // (the folder made again -- by the Files app, after it was removed elsewhere: watched and read again)
        _watchCheckedAt = CACurrentMediaTime();
        struct stat st;
        if (lstat(_folder.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_dev != _watchDev || st.st_ino != _watchIno)) {
            DMLog(@"[desktop] the Desktop folder is there again: watched and read again");
            [self dm_watch]; [self dm_list];
            _watchDev = st.st_dev; _watchIno = st.st_ino;   // (tried for this folder: not again every 2 s if it can't be watched)
        }
    }
}
- (NSArray<NSValue *> *)dm_occupied {   // page 1's app icons, folders and widgets (icon views), a little larger: never under a desktop icon
    NSMutableArray *a = [NSMutableArray array];
    Class iv = objc_getClass("SBIconView");   // (not the list's invisible focus guides: they pushed icons off where they were dropped)
    for (UIView *v in _list.subviews) if (v != self && !v.hidden && v.alpha > 0.01 && v.bounds.size.width > 8.0 && ((iv && [v isKindOfClass:iv]) || [NSStringFromClass([v class]) containsString:@"Widget"]))
        [a addObject:[NSValue valueWithCGRect:CGRectInset(v.frame, -4.0, -4.0)]];
    // the page dots (SpringBoard's scroll accessory, above the Dock): it is above the desktop and takes the touches there -- an icon placed on it
    // could not be pressed, a long press started the Home Screen's editing instead (iPad 2 landscape, dots at {444, 622, 136.5, 40})
    UIView *root = _list.superview;
    while (root && ![NSStringFromClass([root class]) containsString:@"RootFolderView"]) root = root.superview;
    NSMutableArray<UIView *> *todo = root ? [NSMutableArray arrayWithArray:root.subviews] : [NSMutableArray array];
    for (NSUInteger k = 0; k < todo.count && k < 60; k++) {
        UIView *x = todo[k];
        if (x.hidden || x.alpha < 0.01) continue;
        if ([NSStringFromClass([x class]) containsString:@"ScrollAccessoryView"]) { if (x.bounds.size.width > 8.0) [a addObject:[NSValue valueWithCGRect:CGRectInset([x convertRect:x.bounds toView:_list], -4.0, -4.0)]]; continue; }
        if (![x isKindOfClass:[UIScrollView class]]) [todo addObjectsFromArray:x.subviews];   // (not into the pages themselves)
    }
    return a;
}
- (NSString *)dm_iconSignature {
    NSMutableString *s = [NSMutableString stringWithFormat:@"%.0fx%.0f|", _list.bounds.size.width, _list.bounds.size.height];
    for (NSValue *r in [self dm_occupied]) { CGRect f = r.CGRectValue; [s appendFormat:@"%.0f,%.0f,%.0f,%.0f;", f.origin.x, f.origin.y, f.size.width, f.size.height]; }
    return s;
}
// The free area: the page minus the menu bar and the Dock (the native windows' desktop, which is the screen's: page 1 fills the screen).
- (CGRect)dm_area {
    CGRect d = DMNativeDesktop(), b = self.bounds;
    CGRect a = CGRectIntersection(CGRectInset(d, 6.0, 4.0), b);
    return CGRectIsNull(a) || a.size.height < 100.0 ? CGRectInset(b, 6.0, 30.0) : a;
}

// ---- looks: the Home Screen's own icon size and label ----
- (void)dm_measure {
    UIView *sample = nil;
    Class iv = objc_getClass("SBIconView");
    CGFloat best = 0;
    for (UIView *v in _list.subviews) {   // (an app icon's picture: the smallest square one -- a widget's is larger; it sits inside a container or two)
        if (!iv || ![v isKindOfClass:iv]) continue;
        NSMutableArray *q = [NSMutableArray arrayWithArray:v.subviews];
        for (NSUInteger k = 0; k < q.count && k < 40; k++) {
            UIView *c = q[k];
            if (![NSStringFromClass([c class]) containsString:@"IconImageView"]) { [q addObjectsFromArray:c.subviews]; continue; }
            CGSize z = c.bounds.size;
            if (fabs(z.width - z.height) < 1.0 && z.width > 20.0 && (!best || z.width < best)) { best = z.width; sample = v; }
            break;
        }
    }
    if (!best) { SEL s = NSSelectorFromString(@"iconImageSize"); if ([_list respondsToSelector:s]) best = ((CGSize (*)(id, SEL))objc_msgSend)(_list, s).width; }
    _side = best > 20.0 ? best : (_side ?: 64.0);
    UIFont *font = nil; UIColor *text = nil, *shadow = nil;
    @try {   // (the app names' own font and legibility colours, from an app icon of the page -- they follow the wallpaper, as the names do;
             //  asked from the icon view, not its label: with the names hidden the label has no parameters, M1 3 Oct)
        id f = DMCall(sample, @"displayedLabelFont") ?: DMCall(sample, @"labelFont");
        id params = DMCall(sample, @"_labelImageParameters") ?: DMCall(DMCall(sample, @"labelView"), @"imageParameters");
        if (![f isKindOfClass:[UIFont class]]) f = DMCall(params, @"font");
        if ([f isKindOfClass:[UIFont class]]) font = f;
        SEL legSel = NSSelectorFromString(@"_legibilitySettingsWithParameters:");
        id leg = params && [sample respondsToSelector:legSel] ? ((id (*)(id, SEL, id))objc_msgSend)(sample, legSel, params) : DMCall(DMCall(sample, @"labelView"), @"legibilitySettings");
        id pc = DMCall(leg, @"primaryColor"); if ([pc isKindOfClass:[UIColor class]]) text = pc;
        id sc = DMCall(leg, @"shadowColor"); if ([sc isKindOfClass:[UIColor class]]) shadow = sc;
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[desktop] the app names' look could not be read: %@", e.reason]); }
    { static BOOL told; if (!told && sample) { told = YES; DMLog([NSString stringWithFormat:@"[desktop] the app names' look: font %@, colours %@", font ? @"read" : @"not readable (a stand-in)", text ? @"read" : @"stand-ins"]); } }
    if (sample) gDesktopLookRead = (font ? 1 : 0) | (text ? 2 : 0) | 4 | (best > 20.0 ? 8 : 0);
    _font = font ?: _font ?: [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _textColor = text ?: _textColor ?: [UIColor whiteColor];
    _shadowColor = shadow ?: _shadowColor ?: [UIColor colorWithWhite:0 alpha:0.5];
    _cellW = MAX(_side + 30.0, 84.0);
    _cellH = 2.0 + _side + 4.0 + ceil(_font.lineHeight) + 2.0 + 4.0;
}
// A folder's icon on the desktop, drawn the same on every iPad (not the Files app's icon, which a theme or iOS itself changes): a macOS folder,
// light blue, its darker tab and back behind, two folds near the bottom (y down, s = the icon's side, laid out on a 256 grid)
static void DMDesktopFolderFill(CGContextRef c, CGPathRef p, CGFloat k, int n, const CGFloat *ys, const unsigned *rgbs) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[24], locs[6];
    for (int i = 0; i < n; i++) {
        comps[i * 4] = (rgbs[i] >> 16 & 0xFF) / 255.0; comps[i * 4 + 1] = (rgbs[i] >> 8 & 0xFF) / 255.0; comps[i * 4 + 2] = (rgbs[i] & 0xFF) / 255.0; comps[i * 4 + 3] = 1;
        locs[i] = (ys[i] - ys[0]) / (ys[n - 1] - ys[0]);
    }
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, n);
    CGContextSaveGState(c); CGContextAddPath(c, p); CGContextClip(c);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, ys[0] * k), CGPointMake(0, ys[n - 1] * k), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(c); CGGradientRelease(g); CGColorSpaceRelease(cs);
}
static void DMDesktopDrawFolder(CGContextRef c, CGFloat s) {
    CGFloat k = s / 256.0;
    CGPathRef front = CGPathCreateWithRoundedRect(CGRectMake(26 * k, 68 * k, 209 * k, 145.5 * k), 12.5 * k, 12.5 * k, NULL);
    // back: the tab and the panel behind the front
    CGMutablePathRef back = CGPathCreateMutable();
    CGPathMoveToPoint(back, NULL, 26 * k, 80 * k);
    CGPathAddLineToPoint(back, NULL, 26 * k, 49 * k);
    CGPathAddArcToPoint(back, NULL, 26 * k, 37.5 * k, 37.5 * k, 37.5 * k, 11.5 * k);
    CGPathAddLineToPoint(back, NULL, 85 * k, 37.5 * k);
    CGPathAddCurveToPoint(back, NULL, 98 * k, 37.5 * k, 103 * k, 54.3 * k, 117 * k, 54.3 * k);
    CGPathAddLineToPoint(back, NULL, 223.5 * k, 54.3 * k);
    CGPathAddArcToPoint(back, NULL, 235 * k, 54.3 * k, 235 * k, 66 * k, 11.5 * k);
    CGPathAddLineToPoint(back, NULL, 235 * k, 80 * k);
    CGPathCloseSubpath(back);
    DMDesktopFolderFill(c, back, k, 3, (const CGFloat[]){ 38, 52, 68 }, (const unsigned[]){ 0x41A2D6, 0x2F96D2, 0x007AC9 });
    // (its soft shadow all around -- no offset, which UIKit and Core Graphics turn opposite ways --, then its colours over it)
    CGContextSaveGState(c); CGContextSetShadowWithColor(c, CGSizeZero, 5 * k, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    CGContextAddPath(c, front); CGContextSetRGBFillColor(c, 0.31, 0.71, 0.91, 1); CGContextFillPath(c); CGContextRestoreGState(c);
    DMDesktopFolderFill(c, front, k, 5, (const CGFloat[]){ 68, 76, 188, 194, 213 }, (const unsigned[]){ 0x6CC9F6, 0x74CFFB, 0x70CDF9, 0x64C4F0, 0x50B6E8 });
    // the two folds near the bottom
    CGContextSaveGState(c); CGContextAddPath(c, front); CGContextClip(c);
    CGContextSetRGBFillColor(c, 0, 0.3, 0.55, 0.08);
    CGContextFillRect(c, CGRectMake(26 * k, 195 * k, 209 * k, 1.5 * k)); CGContextFillRect(c, CGRectMake(26 * k, 203.5 * k, 209 * k, 1.5 * k));
    CGContextSetRGBFillColor(c, 1, 1, 1, 0.14);
    CGContextFillRect(c, CGRectMake(26 * k, 193.5 * k, 209 * k, 1.5 * k)); CGContextFillRect(c, CGRectMake(26 * k, 202 * k, 209 * k, 1.5 * k));
    CGContextRestoreGState(c);
    CGPathRelease(front); CGPathRelease(back);
}
- (UIImage *)dm_folderImage {   // (made once per icon size)
    if (_folderImage && fabs(_folderImageSide - _side) < 0.5) return _folderImage;
    CGFloat s = _side;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    _folderImage = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) { DMDesktopDrawFolder(ctx.CGContext, s); }];
    _folderImageSide = s;
    gDesktopFolderFrom = 4;   // (drawn: for the untested-iPadOS diagnostics, DMDesktopDiag)
    return _folderImage;
}
- (UIImage *)dm_imageFor:(DMFinderItem *)it view:(DMDesktopItemView *)v {
    if (it.dir && !it.package && ![it.name hasSuffix:@".app"]) return [self dm_folderImage];
    __weak DMDesktopItemView *wv = v; DMFinderItem *wit = it; CGFloat side = _side;
    UIImage *thumb = DMFinderThumb(it, side, ^{ DMDesktopItemView *x = wv; if (x && x.item == wit) x.icon.image = DMFinderThumb(wit, side, nil) ?: x.icon.image; });
    return thumb ?: DMFinderIconWithAlias(it, side);
}

// ---- the folder: listed, watched ----
- (void)dm_watch {
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    int fd = open(_folder.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) return;
    struct stat st; if (fstat(fd, &st) == 0) { _watchDev = st.st_dev; _watchIno = st.st_ino; }
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_LINK | DISPATCH_VNODE_EXTEND, dispatch_get_main_queue());
    if (!src) { close(fd); return; }
    __weak DMDesktop *ws = self;
    dispatch_source_set_event_handler(src, ^{   // (live: a change made by Finder, the Files app or any app shows at once; several in a row are read once)
        DMDesktop *s = ws; if (!s || s->_watchPending) return;
        s->_watchPending = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DMDesktop *s2 = ws; if (!s2) return;
            s2->_watchPending = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:s2.folder]) { DMLog(@"[desktop] the Desktop folder is gone"); s2->_watchDev = 0; s2->_watchIno = 0; [s2 dm_watch]; }   // (watched again when it is back, -dm_tick)
            [s2 dm_list];
        });
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    _watch = src;
}
- (void)dm_list {
    if (_listing) { _relist = YES; return; }
    _listing = YES;
    NSString *folder = _folder;
    __weak DMDesktop *ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        struct stat fst; BOOL missing = lstat(folder.fileSystemRepresentation, &fst) != 0 || !S_ISDIR(fst.st_mode);
        NSArray<DMFinderItem *> *items = missing ? @[] : DMFinderList(folder, NO, NULL) ?: @[];
        NSMutableDictionary *inodes = [NSMutableDictionary dictionary], *returned = [NSMutableDictionary dictionary];
        for (DMFinderItem *it in items) {
            struct stat st; if (lstat(it.path.fileSystemRepresentation, &st) == 0) inodes[it.name] = @((unsigned long long)st.st_ino);
            char buf[64]; ssize_t n = getxattr(it.path.fileSystemRepresentation, kFinderDesktopPlaceAttr, buf, sizeof buf - 1, 0, XATTR_NOFOLLOW);   // (back from the Trash)
            if (n > 0) { buf[n] = 0; NSArray *q = [[NSString stringWithUTF8String:buf] componentsSeparatedByString:@","];
                if (q.count == 2) returned[it.name] = @[@(MAX(0.0, MIN(1.0, [q[0] doubleValue]))), @(MAX(0.0, MIN(1.0, [q[1] doubleValue])))]; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            DMDesktop *s = ws; if (!s) return;
            s->_listing = NO;
            // (a Haptic Touch menu up or fading: its icon must stay in the window until it is gone -- UIKit raises otherwise, see
            //  DMWaitForContextMenu; the folder is read again then. SpringBoard's own app icon menus don't count: their icons are not ours)
            if (DMWaitForOwnMenus(@"desktop-list", ^{ [ws dm_list]; })) return;
            if (missing != s->_folderMissing) DMLog(missing ? @"[desktop] the Desktop folder is missing: no icons, their places kept" : @"[desktop] the Desktop folder is back");
            s->_folderMissing = missing;
            [s dm_setItems:items inodes:inodes returned:returned];
            if (s->_relist) { s->_relist = NO; [s dm_list]; }
        });
    });
}
- (void)dm_setItems:(NSArray<DMFinderItem *> *)items inodes:(NSDictionary *)inodes returned:(NSDictionary *)returned {
    NSSet *names = [NSSet setWithArray:[items valueForKey:@"name"]];
    // (a rename, wherever it was made: the same file -- its inode -- under a new name keeps its place)
    NSMutableDictionary *byInode = [NSMutableDictionary dictionary];
    for (NSString *old in _inodes) if (![names containsObject:old] && _places[old]) byInode[_inodes[old]] = old;
    BOOL changed = NO;
    for (DMFinderItem *it in items) {
        if (_places[it.name] || !inodes[it.name]) continue;
        NSString *old = byInode[inodes[it.name]];
        if (old) { _places[it.name] = _places[old]; [_places removeObjectForKey:old]; changed = YES; DMLog(@"[desktop] a renamed icon keeps its place"); }
    }
    NSSet *before = [NSSet setWithArray:[_items valueForKey:@"name"] ?: @[]];
    NSMutableSet *fresh = [NSMutableSet set]; for (NSString *n in names) if (_items && ![before containsObject:n]) [fresh addObject:n];
    // (back from the Trash -- Undo, Put Back --: the place it had when it went, or the nearest free spot to it; the note is removed)
    for (NSString *n in returned) {
        if (![names containsObject:n]) continue;
        _places[n] = returned[n]; [fresh removeObject:n]; changed = YES;
        if (!_back) _back = [NSMutableSet set];
        [_back addObject:n];   // (placed after the icons already there: its old spot only if still free)
        NSString *path = [_folder stringByAppendingPathComponent:n];
        dispatch_async(DMFinderFileQueue(), ^{ removexattr(path.fileSystemRepresentation, kFinderDesktopPlaceAttr, XATTR_NOFOLLOW); });
        DMLog(@"[desktop] an icon back from the Trash takes its old place");
    }
    _fresh = fresh;   // (new since the last listing: a drop's icons go where it was dropped, even where an old place was kept for the name)
    _inodes = inodes;
    _items = items;
    for (NSString *n in [_views allKeys]) if (![names containsObject:n]) { [_views[n] removeFromSuperview]; [_views removeObjectForKey:n]; }
    NSSet *paths = [NSSet setWithArray:[items valueForKey:@"path"]];
    for (NSString *p in [_sel array]) if (![paths containsObject:p]) [_sel removeObject:p];
    if (_selectWhenListed.count) {   // (after a drop, New Folder, Undo: what was made is the selection, as on a Mac)
        NSMutableArray *got = [NSMutableArray array]; for (NSString *p in _selectWhenListed) if ([paths containsObject:p]) [got addObject:p];
        if (got.count) { _selectWhenListed = nil; [_sel removeAllObjects]; [_sel addObjectsFromArray:got]; }
    }
    if (changed || ![before isEqualToSet:names]) [self dm_savePlaces];   // (renames, arrivals and removals kept at once: a respring finds them)
    [self dm_measure];
    for (DMFinderItem *it in items) {
        DMDesktopItemView *v = _views[it.name];
        if (!v) {
            v = [[DMDesktopItemView alloc] initWithFrame:CGRectMake(0, 0, _cellW, _cellH)]; _views[it.name] = v; [self addSubview:v];
            [self dm_addMenu:[[UIContextMenuInteraction alloc] initWithDelegate:self] to:v];
            v.alpha = 0; [UIView animateWithDuration:0.2 animations:^{ v.alpha = 1; }];
        }
        BOOL newItem = v.item == nil || ![v.item.path isEqualToString:it.path] || ![v.item.date isEqual:it.date];
        v.item = it; v.side = _side;
        v.label.font = _font; v.label.text = it.display;
        v.textColor = _textColor;
        v.label.layer.shadowColor = _shadowColor.CGColor; v.label.layer.shadowOffset = CGSizeMake(0, 1); v.label.layer.shadowRadius = 2.0;
        if (newItem || !v.icon.image) v.icon.image = [self dm_imageFor:it view:v];
        v.selected = [_sel containsObject:it.path];
    }
    _placeDirty = YES;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (_renameWhenListed && _views[_renameWhenListed.lastPathComponent]) { NSString *r = _renameWhenListed; _renameWhenListed = nil; [self dm_beginRename:r]; }
}

// ---- placing the icons (DesktopPlace.h) ----
// One placer per pass, made once from page 1's app icons, widgets and page dots (and, outside a layout pass, the icons that stay put).
- (void)dm_placer:(DMPlacer *)pl area:(CGRect)area {
    NSArray<NSValue *> *occ = [self dm_occupied];
    CGRect *r = malloc(sizeof(CGRect) * MAX(1, occ.count));
    for (NSUInteger k = 0; k < occ.count; k++) r[k] = occ[k].CGRectValue;
    // (a right-to-left language: placed as a Mac does then, new icons from the top left -- the Home Screen's own icons start at the right there)
    DMPlacerInitDir(pl, area, _cellW, _cellH, r, (int)occ.count, self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft);
    free(r);
}
- (CGPoint)dm_pointFor:(NSArray<NSNumber *> *)f area:(CGRect)a { return CGPointMake(a.origin.x + f[0].doubleValue * a.size.width, a.origin.y + f[1].doubleValue * a.size.height); }
- (NSArray<NSNumber *> *)dm_fractionFor:(CGPoint)c area:(CGRect)a { return @[@(MAX(0.0, MIN(1.0, (c.x - a.origin.x) / MAX(1.0, a.size.width)))), @(MAX(0.0, MIN(1.0, (c.y - a.origin.y) / MAX(1.0, a.size.height))))]; }
// The icons are placed again when something a pass depends on changed -- the files, page 1's app icons and widgets, the page's size, an icon's
// size, a drag that ended --, not on every layout UIKit asks for (adding the selection rectangle, the rename field or a menu's anchor lays the
// view out too). Never while the Home Screen is being arranged (the icons are hidden) or while page 1 isn't showing: then when it shows again
// (-dm_tick). Several changes in a row are one pass (UIKit's own coalescing of -setNeedsLayout).
- (void)dm_placeAgain { _placeDirty = YES; [self setNeedsLayout]; }
- (BOOL)dm_pageShowing {
    UIView *list = _list, *scroll = list.superview;
    if (!list.window || !scroll) return NO;
    return CGRectIntersectsRect([list convertRect:list.bounds toView:scroll], scroll.bounds);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_list || !_items) return;
    CGRect area = [self dm_area];
    if (!_placeDirty && CGRectEqualToRect(area, _placedArea) && _placedCell.width == _cellW && _placedCell.height == _cellH) return;
    if (_editing || ![self dm_pageShowing]) { _placeDirty = YES; return; }
    _placeDirty = NO; _placedArea = area; _placedCell = CGSizeMake(_cellW, _cellH);
    DMPlacer pl; [self dm_placer:&pl area:area];
    BOOL save = NO; NSInteger piled = 0;
    // (placed icons first, in name order -- the same result every time --, then the new ones: next to a drop, or the next free spot)
    NSMutableArray<DMFinderItem *> *placed = [NSMutableArray array], *fresh = [NSMutableArray array];
    BOOL arriving = _arriveLeft > 0 && CACurrentMediaTime() < _arriveUntil, cleared = NO;
    for (DMFinderItem *it in _items) [_places[it.name] && !(arriving && [_fresh containsObject:it.name]) ? placed : fresh addObject:it];
    _fresh = nil;
    NSMutableArray<DMFinderItem *> *back = [NSMutableArray array];   // (back from the Trash: after the icons that stayed, which keep their spots)
    for (DMFinderItem *it in [placed copy]) if ([_back containsObject:it.name]) { [placed removeObject:it]; [back addObject:it]; }
    _back = nil;
    [placed addObjectsFromArray:back];
    for (DMFinderItem *it in [placed arrayByAddingObjectsFromArray:fresh]) {
        DMDesktopItemView *v = _views[it.name];
        if (!v) continue;
        v.bounds = CGRectMake(0, 0, _cellW, _cellH); v.side = _side;
        CGPoint c; int fits = 1;
        NSArray *f = [fresh containsObject:it] ? nil : _places[it.name];
        if (f) {
            c = DMPlacerPlaceNear(&pl, [self dm_pointFor:f area:area], &fits);
            if (fits && [back containsObject:it]) { _places[it.name] = [self dm_fractionFor:c area:area]; save = YES; }   // (where it really went is its place now)
        } else {
            c = arriving ? DMPlacerPlaceNear(&pl, _arrivePoint, &fits) : DMPlacerPlaceNext(&pl, &fits);
            if (arriving) { if (!cleared) { cleared = YES; [_sel removeAllObjects]; [self dm_showSelection]; } [_sel addObject:it.path]; v.selected = YES; }   // (dropped here: the selection, as on a Mac)
            if (arriving && --_arriveLeft <= 0) arriving = NO;
            if (fits) { _places[it.name] = [self dm_fractionFor:c area:area]; save = YES; }   // (in the pile: no place, a free spot as soon as there is one)
        }
        if (!fits) piled++;
        if ([_dragViews containsObject:v]) continue;   // (being dragged: stays put; its spot is taken all the same)
        v.center = c;
        [v setNeedsLayout];
    }
    DMPlacerFree(&pl);
    if (piled != _piled) { _piled = piled; DMLog([NSString stringWithFormat:@"[desktop] %ld icon(s) found no free spot on page 1: stacked on the last free one", (long)piled]); }
    if (save) [self dm_savePlaces];
}
- (NSString *)dm_placeStringFor:(NSString *)path {   // ("fx,fy": where an item of the desktop is, for Move to Trash; nil if it isn't one)
    if (![DMFinderReal(path.stringByDeletingLastPathComponent) isEqualToString:DMFinderReal(_folder)]) return nil;
    NSArray *f = _places[path.lastPathComponent];
    return f.count == 2 ? [NSString stringWithFormat:@"%.5f,%.5f", [f[0] doubleValue], [f[1] doubleValue]] : nil;
}
- (void)dm_savePlaces {
    NSSet *names = [NSSet setWithArray:[_items valueForKey:@"name"] ?: @[]];
    // (gone from the desktop: forgotten, as on a Mac -- not while the folder itself is missing: its icons come back to their places with it)
    if (!_folderMissing) for (NSString *n in [_places allKeys]) if (_items && ![names containsObject:n]) [_places removeObjectForKey:n];
    CFPreferencesSetValue(CFSTR("places"), (__bridge CFPropertyListRef)[_places copy], kDesktopDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    _saveGen++;
    if (!_syncPending) { _syncPending = YES; [self dm_syncPlaces]; }   // (written out off the main thread, once for a burst of saves)
}
- (void)dm_syncPlaces {
    NSUInteger gen = _saveGen; __weak DMDesktop *ws = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        CFPreferencesSynchronize(kDesktopDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        dispatch_async(dispatch_get_main_queue(), ^{
            DMDesktop *s = ws; if (!s) return;
            if (s->_saveGen != gen) [s dm_syncPlaces]; else s->_syncPending = NO;   // (saved again meanwhile: once more)
        });
    });
}

// ---- touches ----
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {   // (only the icons take touches: the empty desktop is the Home Screen's)
    if (self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return nil;
    if (_renameField && CGRectContainsPoint(CGRectInset(_renameField.frame, -4, -4), p)) return [_renameField hitTest:[self convertPoint:p toView:_renameField] withEvent:e] ?: _renameField;
    for (UIView *v in [self.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMDesktopItemView class]] && !v.hidden && v.alpha > 0.01 && CGRectContainsPoint(v.frame, p)) return v;
    return nil;
}
- (DMDesktopItemView *)dm_viewAt:(CGPoint)p {
    for (UIView *v in [self.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMDesktopItemView class]] && !v.hidden && CGRectContainsPoint(v.frame, p)) return (DMDesktopItemView *)v;
    return nil;
}
- (DMDesktopItemView *)dm_itemViewAtScreen:(CGPoint)sp { return [self dm_viewAt:[self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace]]; }
- (CGPoint)dm_screen:(CGPoint)p { return [self convertPoint:p toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace]; }
// Is the desktop what is under this screen point (page 1 showing there, in its free area, nothing of the Home Screen's own over it)?
- (BOOL)dm_shownAt:(CGPoint)sp {
    if (!_list || !self.window || self.window.hidden || self.hidden || self.alpha < 0.01 || !self.userInteractionEnabled) return NO;
    CGPoint p = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    if (!CGRectContainsPoint([self dm_area], p)) return NO;
    UIView *h = [self.window hitTest:[self.window convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] withEvent:nil];
    return h && ([h isDescendantOfView:_list] || [self isDescendantOfView:h]);   // (page 1 there -- its empty space, an icon of ours, or an app icon
}                                                                                 //  or widget, which the drop slides away from -- not a folder or the App Library over it)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    if ([g.name isEqualToString:@"dm.desktop.tap"]) _lastTapPointer = DMDesktopPointerTouch(t, nil);   // (a click: a Mac's click rules, not a finger's)
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (UIKeyModifierFlags)dm_flags:(UIGestureRecognizer *)g { if (@available(iOS 13.4, *)) return g.modifierFlags; return 0; }
- (void)dm_select:(NSArray<NSString *> *)paths { [_sel removeAllObjects]; [_sel addObjectsFromArray:paths]; [self dm_showSelection]; }
- (void)dm_showSelection { for (NSString *n in _views) { DMDesktopItemView *v = _views[n]; v.selected = [_sel containsObject:v.item.path]; } }
- (NSArray<DMFinderItem *> *)dm_selectedItems { NSMutableArray *a = [NSMutableArray array]; for (DMFinderItem *it in _items) if ([_sel containsObject:it.path]) [a addObject:it]; return a; }
- (void)dm_tap:(UITapGestureRecognizer *)g {
    DMDesktopItemView *v = [self dm_viewAt:[g locationInView:self]];
    if (!v) return;
    // (VoiceOver: a tap that reaches an icon is VoiceOver's double tap -- a finger's own touches are VoiceOver's -- and that means "open". It comes
    //  as a tap, not through accessibilityActivate, since SpringBoard's accessibility finds Home Screen icons through its icon model, which ours are
    //  not part of; read as a tap it only selected the icon: logic test 6 Oct, both iPads)
    if (UIAccessibilityIsVoiceOverRunning()) { [self dm_axOpen:v]; return; }
    [self dm_endRename:YES];
    _hasKeys = YES;
    UIKeyModifierFlags m = [self dm_flags:g];
    NSString *p = v.item.path;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL twice = [_lastTapPath isEqualToString:p] && now - _lastTapAt < 0.45;
    _lastTapPath = twice ? nil : p; _lastTapAt = now;
    if (twice) { if (![_sel containsObject:p]) [_sel addObject:p]; [self dm_showSelection]; DMLog(@"[desktop] double tap: open"); [self dm_openItems:@[v.item]]; return; }
    if (m & UIKeyModifierCommand) { if ([_sel containsObject:p]) [_sel removeObject:p]; else [_sel addObject:p]; }   // (Command-click: one more, or one less)
    else if (m & UIKeyModifierShift) [_sel addObject:p];                                                                // (Shift-click: one more)
    else if (!(_lastTapPointer || ({ BOOL b = NO; if (@available(iOS 13.4, *)) b = g.buttonMask != 0; b; })) && _sel.count && !([_sel containsObject:p] && _sel.count == 1)) {   // (a finger, while a selection exists: adds or removes)
        if ([_sel containsObject:p]) [_sel removeObject:p]; else [_sel addObject:p];
    }
    else { [_sel removeAllObjects]; [_sel addObject:p]; }                                                          // (a plain click / first tap: only it)
    [self dm_showSelection];
}
// A menu interaction's own gestures, noted when it is added (they are the ones the view did not have before): ours never hold them up.
- (void)dm_addMenu:(UIContextMenuInteraction *)i to:(UIView *)v {
    NSArray *before = [v.gestureRecognizers copy] ?: @[];
    [v addInteraction:i];
    for (UIGestureRecognizer *g in v.gestureRecognizers) if (![before containsObject:g]) [_menuGRs addObject:g];
}
// A Haptic Touch menu that has not opened yet must never open over a drag or a selection rectangle. Switching its gestures off and on does not stop
// UIKit's own presentation on iPadOS 15 (M1, 3 Oct: a finger held 0.72 s, just short of the menu's time, then moved; the icon lifted, the menu
// opened 40 ms later over the drag, and the finger's lift chose the row under it -- Move to Trash). Taking the interaction off its view is what
// calls that press off in UIKit; it goes straight back on for the next press. v: the icon's view, or nil for the empty desktop's menu.
- (void)dm_menuLetsGo:(UIView *)v {
    UIContextMenuInteraction *mi = nil;
    if (v) { for (id<UIInteraction> x in v.interactions) if ([x isKindOfClass:[UIContextMenuInteraction class]]) { mi = (UIContextMenuInteraction *)x; break; } }
    else mi = _bgMenu;
    UIView *host = mi.view;
    if (!mi || !host || mi == _menuOpen) return;
    // (its menu still closing -- a pointer drag can start at once after the click that closed it: no press of it can be pending then, and taking it
    //  off its view could cut UIKit's close short, whose completion is what puts the Dock back, 1.3.1 logic test; bounded: a close never lasts 1 s)
    if (mi == _menuClosing && CACurrentMediaTime() - _menuClosingAt < 1.0 && DMDesktopMenuShown(self.window)) return;   // (its close really still playing)
    [host removeInteraction:mi];
    [self dm_addMenu:mi to:host];
}
- (void)dm_liftAt:(CGPoint)sp held:(DMDesktopItemView *)held option:(BOOL)option {
    DM_FEATURE_MARK("desktop-drag");
    _lifted = YES;
    held.transform = CGAffineTransformIdentity;
    NSMutableArray<DMDesktopItemView *> *views = [NSMutableArray array];
    for (DMFinderItem *it in [self dm_selectedItems]) { DMDesktopItemView *v = _views[it.name]; if (v) [views addObject:v]; }
    if (![views containsObject:held]) views = [NSMutableArray arrayWithObject:held];
    CGRect u = CGRectNull; for (UIView *v in views) u = CGRectUnion(u, v.frame);
    UIView *pic = [[UIView alloc] initWithFrame:CGRectMake(0, 0, u.size.width, u.size.height)];   // (the icons themselves ride on the finger, as on a Mac)
    for (UIView *v in views) { UIView *snap = [v snapshotViewAfterScreenUpdates:NO]; if (!snap) continue; snap.frame = CGRectOffset(v.frame, -u.origin.x, -u.origin.y); [pic addSubview:snap]; }
    pic.alpha = 0.85;
    CGPoint lp = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    _dragGrab = CGPointMake(lp.x - CGRectGetMidX(u), lp.y - CGRectGetMidY(u)); _dragUnion = u;
    _dragViews = views;
    gFDCustomTile = pic; gFDCustomGrab = _dragGrab;
    NSMutableArray *items = [NSMutableArray array]; for (DMDesktopItemView *v in views) [items addObject:v.item];
    DMFinderOps().path = _folder;
    DMFinderDragBegin(DMFinderOps(), items, sp);
    for (UIView *v in views) v.alpha = 0.35;   // (ghosts stay where they were until the drop)
    DMLog([NSString stringWithFormat:@"[desktop] %lu icon(s) lifted", (unsigned long)views.count]);
}
- (void)dm_dragEnded {
    NSArray *views = _dragViews; _dragViews = nil; _lifted = NO;
    for (UIView *v in views) [UIView animateWithDuration:0.15 animations:^{ v.alpha = 1.0; }];
    [self dm_placeAgain];
}
// A drop on the desktop (Finder.h DMFinderDragEnd): icons already on it move to the drop point; anything else comes into the folder by Finder's
// rules (moved, or copied with Option / from a read-only place) and its icons appear where it was dropped.
- (void)dm_takeDrop:(DMFDrag *)d at:(CGPoint)sp into:(NSString *)dest ontoFolder:(BOOL)ontoFolder {
    DM_FEATURE_MARK("desktop-drop");
    BOOL copy = DMFDCopies(d, dest), here = !ontoFolder && !copy;
    NSString *real = DMFinderReal(_folder);
    for (DMFinderItem *it in d.items) if (![DMFinderReal(it.path.stringByDeletingLastPathComponent) isEqualToString:real]) here = NO;
    CGPoint p = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    if (here) {   // (moved on the desktop: new places, nothing changes on the disk)
        DMFDFinish(d, YES);
        CGRect area = [self dm_area];
        DMPlacer pl; [self dm_placer:&pl area:area];
        NSSet *moving = [NSSet setWithArray:[d.items valueForKey:@"name"]];
        for (NSString *n in _views) if (![moving containsObject:n]) DMPlacerTake(&pl, _views[n].frame);
        CGPoint uc = CGPointMake(p.x - (_dragViews ? _dragGrab.x : 0), p.y - (_dragViews ? _dragGrab.y : 0));   // (the picture's new centre)
        NSInteger k = 0;
        for (DMFinderItem *it in d.items) {
            DMDesktopItemView *v = _views[it.name];
            if (!v) continue;
            CGPoint want = _dragViews ? CGPointMake(uc.x + v.center.x - CGRectGetMidX(_dragUnion), uc.y + v.center.y - CGRectGetMidY(_dragUnion)) : CGPointMake(p.x, p.y + k * (_cellH + 6.0));
            int fits = 1; CGPoint c = DMPlacerPlaceNear(&pl, want, &fits);
            if (!fits) { k++; continue; }   // (no room anywhere: it stays where it was)
            _places[it.name] = [self dm_fractionFor:c area:area];
            [UIView animateWithDuration:0.2 animations:^{ v.center = c; }];
            k++;
        }
        DMPlacerFree(&pl);
        [self dm_savePlaces];
        DMLog([NSString stringWithFormat:@"[desktop] %ld icon(s) moved on the desktop", (long)k]);
        return;
    }
    if (!ontoFolder) { _arrivePoint = p; _arriveUntil = CACurrentMediaTime() + 6.0; _arriveLeft = (NSInteger)d.items.count; }
    DMFinderOps().path = _folder;
    DMFDDropInto(d, dest, DMFDFromFinderWindow(d) ? d.from : DMFinderOps(), ontoFolder ? @"a folder on the desktop" : @"the desktop");
}

// ---- the selection rectangle on the empty desktop: a pointer's drag, or a finger held 0.35 s and then moved ----
// (a translucent fill and a border, as Finder's; the icons it touches are selected as it grows; Command / Shift add to the selection)
- (void)dm_bandBeginAt:(CGPoint)p add:(BOOL)add {
    DM_FEATURE_MARK("desktop-selection-rectangle");
    _bandStart = p;
    _bandBase = add ? [_sel copy] : [NSOrderedSet orderedSet];
    _band = [UIView new]; _band.userInteractionEnabled = NO;
    _band.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    _band.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.6].CGColor; _band.layer.borderWidth = 1.0;
    [self addSubview:_band];
    _hasKeys = YES;
}
- (void)dm_bandTo:(CGPoint)p {
    if (!_band) return;
    CGRect r = CGRectMake(MIN(p.x, _bandStart.x), MIN(p.y, _bandStart.y), fabs(p.x - _bandStart.x), fabs(p.y - _bandStart.y));
    _band.frame = r;
    NSMutableOrderedSet *sel = [_bandBase mutableCopy] ?: [NSMutableOrderedSet orderedSet];
    for (NSString *n in _views) if (CGRectIntersectsRect(r, _views[n].frame)) [sel addObject:_views[n].item.path];
    [_sel removeAllObjects]; [_sel unionOrderedSet:sel]; [self dm_showSelection];
}
- (void)dm_bandEnd {
    if (!_band) return;
    [_band removeFromSuperview]; _band = nil; _bandBase = nil;
    DMLog([NSString stringWithFormat:@"[desktop] selection rectangle: %lu selected", (unsigned long)_sel.count]);
}
- (void)dm_touchBegan:(UITouch *)t {   // (any touch elsewhere -- not on a desktop icon -- ends the desktop's selection and keys, as a click elsewhere does)
    if (t.type == UITouchTypeIndirect) return;
    UIView *v = t.view;
    if (v && ([v isDescendantOfView:self] || v == self)) return;
    if (gOverlay && [v isDescendantOfView:gOverlay]) return;   // (our own menu: its row acts on the selection)
    if (DMAnyContextMenuVC(NULL) || _band) return;              // (a Haptic Touch menu: its rows act on the selection; the rectangle being drawn)
    // (judged by where it is on the screen: SpringBoard's system gesture window sees every touch first, with a view of its own -- a press on a
    //  selected icon cleared the selection before the press began, M1 3 Oct)
    CGPoint sp = t.window ? [t.window convertPoint:[t locationInView:nil] toCoordinateSpace:t.window.screen.coordinateSpace] : [t locationInView:nil];
    if (_renameField && DMPointOnOwnKeyboard(sp)) return;   // (typing the new name on the on-screen keyboard)
    if ([NSStringFromClass([t.window class]) isEqualToString:@"_UISystemGestureWindow"] || (gOverlay && gOverlay.window == t.window)) {
        if ([self dm_shownAt:sp] && [self dm_itemViewAtScreen:sp]) return;
        if (gOverlay) return;
        if (_renameField && CGRectContainsPoint(CGRectInset(_renameField.frame, -4, -4), [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace])) return;
    }
    if (_renameField) [self dm_endRename:YES];
    _hasKeys = NO;
    if (_sel.count && !_band) { [_sel removeAllObjects]; [self dm_showSelection]; }
}
// ---- actions (Finder's) ----
- (void)dm_openItems:(NSArray<DMFinderItem *> *)items newWindow:(BOOL)newWindow {
    for (DMFinderItem *it in items) {
        if (it.dir && !it.package && ![it.name hasSuffix:@".app"]) DMFinderOpen(it.path, newWindow || items.count > 1);   // (a folder: in Finder)
        else { DMFinderOps().path = _folder; [(DMFinderWindow *)DMFinderOps() open:it]; }   // (a file: as Finder opens it -- Quick Look)
    }
}
- (void)dm_openItems:(NSArray<DMFinderItem *> *)items { [self dm_openItems:items newWindow:NO]; }
- (void)dm_axOpen:(DMDesktopItemView *)v {   // (an assistive feature used an icon: it becomes the selection and opens, as a double tap does)
    if (!v.item || _editing || !self.userInteractionEnabled) return;
    [self dm_endRename:YES];
    [_sel removeAllObjects]; [_sel addObject:v.item.path]; [self dm_showSelection];
    DMLog(@"[desktop] icon opened by an assistive feature");
    [self dm_openItems:@[v.item]];
}
- (void)dm_trash:(NSArray<DMFinderItem *> *)items { if (!items.count) return; DMFinderOps().path = _folder; [DMFinderOps() dm_trashItems:[items valueForKey:@"path"]]; }
- (void)dm_arriveAt:(CGPoint)p count:(NSInteger)n { _arrivePoint = p; _arriveUntil = CACurrentMediaTime() + 6.0; _arriveLeft = n; }   // (self's coordinates)
- (void)dm_duplicate:(NSArray<DMFinderItem *> *)items {   // (the copies appear next to the originals and become the selection, as on a Mac)
    if (!items.count) return;
    DMDesktopItemView *v = _views[items.firstObject.name];
    if (v) [self dm_arriveAt:v.center count:(NSInteger)items.count];
    DMFinderOps().path = _folder; [DMFinderOps() dm_duplicateItems:[items valueForKey:@"path"]];
}
- (void)dm_newFolderAt:(CGPoint)sp {
    DMFinderWindow *ops = DMFinderOps();
    ops.path = _folder;
    [self dm_arriveAt:[self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] count:1];
    _renameNew = YES;
    [ops newFolder];
}
- (void)dm_newTextFileAt:(CGPoint)sp {   // (at the pressed spot, or the nearest free one; selected and named in place)
    DMFinderWindow *ops = DMFinderOps();
    ops.path = _folder;
    [self dm_arriveAt:[self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] count:1];
    _renameNew = YES;
    [ops dm_newTextFile];
}
- (void)dm_made:(NSArray<NSString *> *)paths {   // (DMFinderOpsHost: what an operation made here becomes the selection; a new folder is named at once)
    _selectWhenListed = [paths copy];
    if (_renameNew && paths.count == 1) _renameWhenListed = paths.firstObject;
    _renameNew = NO;
}
// Clean Up: every icon into the grid of free spots, from the top right (the top left in a right-to-left language), in the order they are now
// (column by column), never over an app icon or widget -- as a Mac's desktop Clean Up.
- (void)dm_cleanUp {
    DM_FEATURE_MARK("desktop-clean-up");
    CGRect area = [self dm_area];
    DMPlacer pl; [self dm_placer:&pl area:area];
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;   // (mirrored: columns left to right)
    NSArray<DMDesktopItemView *> *views = [[_views allValues] sortedArrayUsingComparator:^NSComparisonResult(DMDesktopItemView *a, DMDesktopItemView *b) {
        CGFloat ca = round(a.center.x / 40.0), cb = round(b.center.x / 40.0);   // (columns right to left, then top to bottom)
        if (rtl) { ca = -ca; cb = -cb; }
        if (ca != cb) return ca > cb ? NSOrderedAscending : NSOrderedDescending;
        return a.center.y < b.center.y ? NSOrderedAscending : a.center.y > b.center.y ? NSOrderedDescending : NSOrderedSame;
    }];
    for (DMDesktopItemView *v in views) {
        int fits = 1; CGPoint c = DMPlacerPlaceNext(&pl, &fits);
        if (fits) _places[v.item.name] = [self dm_fractionFor:c area:area]; else [_places removeObjectForKey:v.item.name];   // (no room: the pile, no place)
        [UIView animateWithDuration:0.25 animations:^{ v.center = c; }];
    }
    DMPlacerFree(&pl);
    [self dm_savePlaces];
    DMLog([NSString stringWithFormat:@"[desktop] Clean Up: %lu icons", (unsigned long)views.count]);
}
// The Haptic Touch menus (a held finger, or a right click), in the order a Mac's desktop has them; for several selected icons they act on all.
- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {
    DM_FEATURE_MARK("desktop-menus");
    __weak DMDesktop *ws = self;
    UIAction *(^A)(NSString *, NSString *, void (^)(void)) = ^UIAction *(NSString *t, NSString *img, void (^h)(void)) { return [UIAction actionWithTitle:t image:img ? [UIImage systemImageNamed:img] : nil identifier:nil handler:^(UIAction *a) { h(); }]; };
    NSMutableArray *top = [NSMutableArray array], *end = [NSMutableArray array];
    DMFinderWindow *ops = DMFinderOps();
    NSString *folder = _folder;
    if (v) {
        NSArray<DMFinderItem *> *sel = [self dm_selectedItems];
        if (![sel containsObject:v.item]) sel = @[v.item];
        BOOL many = sel.count > 1, canChange = YES, dirs = YES;
        for (DMFinderItem *x in sel) { canChange = canChange && DMFinderCanChange(x.path); dirs = dirs && x.dir && !x.package && ![x.name hasSuffix:@".app"]; }
        [top addObject:A(@"Open", nil, ^{ [ws dm_openItems:sel newWindow:NO]; })];
        if (dirs) [top addObject:A(@"Open in New Window", @"macwindow.badge.plus", ^{ [ws dm_openItems:sel newWindow:YES]; })];
        [top addObject:A(@"Quick Look", @"eye", ^{ DMQuickLookOpen(sel.firstObject.path); })];
        [top addObject:A(@"Get Info", @"info.circle", ^{ for (DMFinderItem *x in sel) [ops getInfo:x]; })];
        if (!many) { UIAction *rn = A(@"Rename", @"pencil", ^{ [ws dm_beginRename:v.item.path]; }); if (!canChange) rn.attributes = UIMenuElementAttributesDisabled; [top addObject:rn]; }
        UIAction *du = A(@"Duplicate", @"plus.square.on.square", ^{ [ws dm_duplicate:sel]; }); if (!DMFinderCanWriteInto(folder)) du.attributes = UIMenuElementAttributesDisabled; [top addObject:du];
        NSMutableArray *targets = [NSMutableArray array];   // (Finder's Share: handed to the app the way a drop on its window is -- a folder as a zip)
        for (NSString *b in DMFinderShareApps()) [targets addObject:[UIAction actionWithTitle:DMCall(DMProxyForBundle(b), @"localizedName") ?: b image:nil identifier:nil handler:^(UIAction *x) { DMFinderShareTo(sel, b, DMFinderOps()); }]];
        UIMenu *share = [UIMenu menuWithTitle:@"Share…" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil options:0 children:targets];
        if (targets.count) [top addObject:share];
        else { UIAction *none = A(@"Share…", @"square.and.arrow.up", ^{}); none.attributes = UIMenuElementAttributesDisabled; [top addObject:none]; }
        UIAction *t = A(many ? [NSString stringWithFormat:@"Move %lu Items to Trash", (unsigned long)sel.count] : @"Move to Trash", @"trash", ^{ [ws dm_trash:sel]; });
        t.attributes = canChange ? UIMenuElementAttributesDestructive : UIMenuElementAttributesDisabled;
        [end addObject:t];
    } else {
        UIAction *nf = A(@"New Folder", @"folder.badge.plus", ^{ [ws dm_newFolderAt:sp]; }); if (!DMFinderCanWriteInto(folder)) nf.attributes = UIMenuElementAttributesDisabled; [top addObject:nf];
        UIAction *nt = A(@"New Text File", @"doc.badge.plus", ^{ [ws dm_newTextFileAt:sp]; }); if (!DMFinderCanWriteInto(folder)) nt.attributes = UIMenuElementAttributesDisabled; [top addObject:nt];
        [top addObject:A(@"Clean Up", @"square.grid.3x3", ^{ [ws dm_cleanUp]; })];
        [top addObject:A(@"Show in Finder", @"folder", ^{ DMFinderOpen(folder, NO); })];
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (NSArray *g in @[top, end]) if (g.count) [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:g]];
    return [UIMenu menuWithTitle:@"" children:groups];
}
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)loc {
    if (_lifted || _trackMode || _band || _editing || !self.userInteractionEnabled) return nil;
    CGPoint sp = [i.view convertPoint:loc toCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
    DMDesktopItemView *v = nil;
    if (i == _bgMenu) {   // (the empty desktop only: an app icon, a widget or one of our icons has its own menu)
        UIView *h = [_list hitTest:[_list convertPoint:loc fromView:i.view] withEvent:nil];
        if (h != _list || ![self dm_shownAt:sp]) return nil;
        if (!_bgAnchor) { _bgAnchor = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 2, 2)]; _bgAnchor.userInteractionEnabled = NO; _bgAnchor.backgroundColor = [UIColor clearColor]; }
        _bgAnchor.center = [self convertPoint:loc fromView:i.view];
        if (_bgAnchor.superview != self) [self addSubview:_bgAnchor];
        [_sel removeAllObjects]; [self dm_showSelection];
    } else {
        v = (DMDesktopItemView *)i.view;
        if (![v isKindOfClass:[DMDesktopItemView class]] || !v.item) return nil;
        if (![_sel containsObject:v.item.path]) [self dm_select:@[v.item.path]];   // (as a Mac's right click: the icon is selected, unless it is part of the selection)
        _hasKeys = YES;
    }
    __weak DMDesktop *ws = self; __weak DMDesktopItemView *wv = v;
    return [UIContextMenuConfiguration configurationWithIdentifier:v ? v.item.path : @"desktop" previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        DMDesktop *s = ws; if (!s) return nil;
        return [s dm_menuFor:wv at:sp];
    }];
}
- (UITargetedPreview *)dm_previewFor:(UIContextMenuInteraction *)i {
    UIPreviewParameters *pp = [UIPreviewParameters new];
    pp.backgroundColor = [UIColor clearColor];
    if (i == _bgMenu) return _bgAnchor.window ? [[UITargetedPreview alloc] initWithView:_bgAnchor parameters:pp] : nil;
    DMDesktopItemView *v = (DMDesktopItemView *)i.view;
    if (!v.window) return nil;
    [v layoutIfNeeded];
    pp.visiblePath = [UIBezierPath bezierPathWithRoundedRect:CGRectUnion(CGRectInset(v.icon.frame, -6.0, -6.0), v.labelBack.frame) cornerRadius:10.0];   // (the icon and its name lift, like an app icon)
    return [[UITargetedPreview alloc] initWithView:v parameters:pp];
}
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForHighlightingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_previewFor:i]; }
- (UITargetedPreview *)contextMenuInteraction:(UIContextMenuInteraction *)i previewForDismissingMenuWithConfiguration:(UIContextMenuConfiguration *)c { return [self dm_previewFor:i]; }
// While a Home Screen icon's menu is open SpringBoard puts the Dock's window under the Home Screen's (a window level assertion on its floating
// Dock controller: level -3 instead of 25, measured with winlist), so the menu -- in the Home Screen's window -- is above the Dock. Ours are not
// icon menus, so no such assertion is taken: a desktop icon's menu near the Dock opened behind it (owner, M1 3 Oct). The same level is set here
// while our menu is up, and the Dock's own level comes back when it has gone (unless SpringBoard changed it meanwhile). No assertion object is
// made: creating SpringBoard's private Dock assertions crashed it before (dock/Downloads.m).
- (void)dm_dockUnderMenu:(BOOL)under { DMDesktopDockUnder(@"menu", under, self.window.windowLevel - 1.0); }
- (void)contextMenuInteraction:(UIContextMenuInteraction *)i willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)c animator:(id<UIContextMenuInteractionAnimating>)a {
    _menuOpen = i;
    [self dm_dockUnderMenu:YES];
    DMDesktopItemView *v = i == _bgMenu ? nil : (DMDesktopItemView *)i.view;
    v.transform = CGAffineTransformIdentity;   // (a finger still down that moves on now: the menu goes and the icon is dragged, -dm_event:)
    DMLog([NSString stringWithFormat:@"[desktop] Haptic Touch menu: %@", v ? @"an icon's" : @"the desktop's"]);
}
- (void)contextMenuInteraction:(UIContextMenuInteraction *)i willEndForConfiguration:(UIContextMenuConfiguration *)c animator:(id<UIContextMenuInteractionAnimating>)a {
    if (_menuOpen == i) _menuOpen = nil;
    // (the menu stops counting as a Home Screen menu over everything now that it is going, not when its fade has ended: a window its own row
    //  opened -- Quick Look -- became active and the next tick sent it away for the still-fading menu, so it showed grey and took no keys)
    if (gHomeMenuOpen) { gHomeMenuOpen = NO; DMLog(@"[desktop] menu going: no longer a Home Screen menu over the windows"); DMSyncWindowFade(); }
    __weak DMDesktop *wd = self; __weak UIContextMenuInteraction *wi = i;
    if (a) {
        _menuClosing = i; _menuClosingAt = CACurrentMediaTime();   // (its close plays until the completion: -dm_menuLetsGo: leaves it alone meanwhile)
        [a addCompletion:^{ DMDesktop *d = wd; if (d && d->_menuClosing == wi) d->_menuClosing = nil; if (!d || !d->_menuOpen) DMDesktopDockUnder(@"menu", NO, 0); }];
    } else [self dm_dockUnderMenu:NO];   // (the desktop gone meanwhile: the Dock back all the same)
    if (i == _bgMenu) { UIView *anchor = _bgAnchor; if (a) [a addCompletion:^{ [anchor removeFromSuperview]; }]; else [anchor removeFromSuperview]; }
}
// Which finger a touch is (-[UITouch _pathIndex], the same for every window's copy of one finger), or -1.
static NSInteger DMDesktopTouchFinger(UITouch *t) {
    SEL s = NSSelectorFromString(@"_pathIndex");
    if (![t respondsToSelector:s]) return -1;
    @try { return (NSInteger)((char (*)(id, SEL))objc_msgSend)(t, s); } @catch (NSException *x) { return -1; }
}
// SpringBoard's events (-[SpringBoard sendEvent:]): a finger on the desktop, followed. Held still (0.3 s on an icon, 0.35 s on the empty desktop --
// or until the Haptic Touch menu opened) and then moved: it is ours -- every other gesture on that touch lets go (the page never turns, the menu
// closes) and an icon is dragged, or the empty desktop's selection rectangle is drawn. Moved sooner: a swipe, the page's. Our own long press
// could never begin: UIKit's menu on the same spot makes every other long press wait for it (M1 3 Oct).
- (void)dm_event:(UIEvent *)e {
    // The finger being followed can stop coming in the Home Screen's window: held long enough, the empty desktop's Haptic Touch menu takes its
    // touch, and once that menu has gone UIKit sends that touch nowhere any more -- only the system gesture window's copy of the same finger keeps
    // coming (iPad 2, 3 Oct: the finger's rectangle stopped growing 0.65 s in, until the finger lifted). Then that copy is followed instead.
    UITouch *copy = nil;
    if ((_track || _trackMode) && _trackFinger >= 0 && (!_track || _track.timestamp <= _trackStamp)) {   // (_track is weak: UIKit may have let it go)
        for (UITouch *o in e.allTouches)
            if (o != _track && o.type == UITouchTypeDirect && o.phase != UITouchPhaseBegan && o.timestamp > _trackStamp && DMDesktopTouchFinger(o) == _trackFinger) { copy = o; break; }   // (never a new finger: its Began is its own)
    }
    for (UITouch *t in e.allTouches) {
        if (t.type != UITouchTypeDirect && t.type != UITouchTypeIndirectPointer) continue;   // (a finger, or a pointer's click)
        if (t.phase == UITouchPhaseBegan) {
            BOOL pointer = DMDesktopPointerTouch(t, e);
#if DEBUG
            // (every touch that begins in the Home Screen's window, for the pointer's path: how it arrives -- type, buttons, the private pointer
            //  flag, radius --, where, and what the desktop does with it)
            if (t.window == self.window && DMTestFlag("/tmp/macstatusbar-debug")) {
                SEL ip = NSSelectorFromString(@"_isPointerTouch"); BOOL flag = NO; @try { if ([t respondsToSelector:ip]) flag = ((BOOL (*)(id, SEL))objc_msgSend)(t, ip); } @catch (NSException *x) {}
                DMLog([NSString stringWithFormat:@"[desktop] touch began: type %ld, pointer %d (buttons %ld, _isPointerTouch %d), radius %.1f, view %@, at %@; tracking %d lifted %d band %d editing %d",
                    (long)t.type, pointer, (long)DMDesktopButtons(e), flag, t.majorRadius, t.view ? NSStringFromClass([t.view class]) : @"nil",
                    NSStringFromCGPoint([t locationInView:nil]), _track != nil, _lifted, _band != nil, _editing]);
            }
#endif
            if (_trackMode && t != _track) {
                // The finger followed was lost without an end -- neither copy reported one. A new finger touching down tells: iOS gives a lost
                // finger's number to the next one (that one's copy must never end the old drag: its lift would drop the files where it tapped), or
                // another finger lands on the desktop while the followed one has said nothing for half a second (a second finger while the first
                // still moves leaves it alone). Its rectangle or drag ends without a drop, and the new touch is taken as usual.
                NSInteger f = DMDesktopTouchFinger(t);
                BOOL reused = f >= 0 && f == _trackFinger;
                BOOL silent = !_track && t.window == self.window && t.timestamp - _trackStamp > 0.5;
                if (reused || silent) {
                    int mode = _trackMode; _trackMode = 0; _trackView = nil; _track = nil;
                    if (mode == 1) { _armed = nil; DMFinderDragEnd(_trackLast, NO, NO); [self dm_dragEnded]; } else if (mode == 2) [self dm_bandEnd];
                }
            }
            if (_track || _trackMode || _lifted || _band || _editing || !self.userInteractionEnabled || t.window != self.window) continue;
            CGPoint sp = [t.window convertPoint:[t locationInView:nil] toCoordinateSpace:t.window.screen.coordinateSpace];
            // (by place, not only by the touch's view: a pointer's click on the empty page came with no view at all, M1 3 Oct)
            UIView *at = t.view ?: [self.window hitTest:[self.window convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] withEvent:nil];
            BOOL onIcon = at && [at isKindOfClass:[DMDesktopItemView class]] && [at isDescendantOfView:self];
            if (!onIcon && at != _list) continue;
            if (!onIcon && ![self dm_shownAt:sp]) continue;
            _track = t; _trackView = onIcon ? (DMDesktopItemView *)at : nil; _trackDown = sp; _trackLast = sp; _trackAt = CACurrentMediaTime(); _trackMode = 0;
            _trackFinger = DMDesktopTouchFinger(t); _trackStamp = t.timestamp;
            _trackPointer = pointer;
            continue;
        }
        if (t != _track && t != copy) continue;
        if (t == _track && copy) continue;   // (no news of it in this event: its copy speaks for it)
        _trackStamp = MAX(_trackStamp, t.timestamp);
        // (the touch's own window can be gone once UIKit's menu took it: then where it was last seen counts)
        CGPoint sp = t.window ? [t.window convertPoint:[t locationInView:nil] toCoordinateSpace:(t.window.screen ?: [UIScreen mainScreen]).coordinateSpace] : _trackLast;
        _trackLast = sp;
        BOOL option = NO; if (@available(iOS 13.4, *)) option = (e.modifierFlags & UIKeyModifierAlternate) != 0;
        option = option || DMTestFlag("/tmp/msb-fdrag-option");
        if (t.phase == UITouchPhaseMoved || t.phase == UITouchPhaseStationary) {
            if (t.phase == UITouchPhaseStationary) continue;
            if (!_trackMode) {
                if (hypot(sp.x - _trackDown.x, sp.y - _trackDown.y) <= (_trackPointer ? 4.0 : 10.0)) continue;
                CFTimeInterval held = CACurrentMediaTime() - _trackAt;
                // (a finger that moved at once: a swipe -- the page turns. A pointer drags an icon or draws the rectangle at once, as on a Mac)
                if (!_trackPointer && held < (_trackView ? 0.3 : 0.35) && !_menuOpen) {
#if DEBUG
                    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[desktop] moved %.2f s after touching down, as a finger: a swipe, left to the page", held]);
#endif
                    _track = nil; continue;
                }
                BOOL menuUp = _menuOpen != nil;
                [_menuOpen dismissMenu];   // (an open menu closes the way UIKit closes it; one not open yet never opens: its gestures let go below)
                for (UIGestureRecognizer *o in [t.gestureRecognizers copy]) if (![o.name hasPrefix:@"dm."] && o.enabled && !(menuUp && [_menuGRs containsObject:o])) { o.enabled = NO; o.enabled = YES; }   // (it is ours now)
                if (!menuUp) [self dm_menuLetsGo:_trackView];   // (and the menu of this press, not open yet, is called off in UIKit itself)
                for (UIView *v = self.superview; v; v = v.superview) if ([v isKindOfClass:[UIScrollView class]]) { UIPanGestureRecognizer *pan = ((UIScrollView *)v).panGestureRecognizer; pan.enabled = NO; pan.enabled = YES; }
                DMDesktopItemView *v = _trackView;
                if (v && v.window) {
                    _trackMode = 1; _hasKeys = YES;
                    if (![_sel containsObject:v.item.path]) [self dm_select:@[v.item.path]];
                    DMLog([NSString stringWithFormat:@"[desktop] %@ on an icon%@: the icon lifts", _trackPointer ? @"a pointer drag" : [NSString stringWithFormat:@"a finger held %.2f s and moved", held], menuUp ? @" (its menu goes)" : @""]);
                    _armed = v;
                    [self dm_liftAt:sp held:v option:option];
                } else if (!v) {
                    _trackMode = 2;
                    DMLog([NSString stringWithFormat:@"[desktop] %@ on the empty desktop: the selection rectangle", _trackPointer ? @"a pointer drag" : [NSString stringWithFormat:@"a finger held %.2f s and moved", held]]);
                    BOOL add = NO; if (@available(iOS 13.4, *)) add = (e.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift)) != 0;
                    [self dm_bandBeginAt:[self convertPoint:_trackDown fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] add:add];
                } else { _track = nil; continue; }
            }
            if (_trackMode == 1) DMFinderDragMove(sp, option);
            else if (_trackMode == 2) [self dm_bandTo:[self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace]];
        } else if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) {
            int mode = _trackMode;
            _track = nil; _trackView = nil; _trackMode = 0;
            if (mode == 1) { _armed = nil; DMFinderDragEnd(sp, t.phase == UITouchPhaseEnded, option); [self dm_dragEnded]; }
            else if (mode == 2) [self dm_bandEnd];
        }
    }
}
// ---- rename in place ----
- (void)dm_beginRename:(NSString *)path {
    DM_FEATURE_MARK("desktop-rename");
    [self dm_endRename:YES];
    DMDesktopItemView *v = _views[path.lastPathComponent];
    if (!v || !DMFinderCanChange(path)) return;
    [self dm_select:@[path]];
    CGRect lf = [v convertRect:v.label.frame toView:self];
    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(CGRectGetMidX(lf) - MAX(lf.size.width, 140.0) / 2.0, lf.origin.y - 2.0, MAX(lf.size.width, 140.0), lf.size.height + 4.0)];
    tf.font = _font ?: [UIFont systemFontOfSize:12.0]; tf.textAlignment = NSTextAlignmentCenter;
    tf.backgroundColor = [UIColor systemBackgroundColor]; tf.textColor = [UIColor labelColor];
    tf.layer.borderColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8].CGColor; tf.layer.borderWidth = 1.5; tf.layer.cornerRadius = 3.0;
    tf.autocorrectionType = UITextAutocorrectionTypeNo; tf.autocapitalizationType = UITextAutocapitalizationTypeNone; tf.spellCheckingType = UITextSpellCheckingTypeNo;
    tf.smartQuotesType = UITextSmartQuotesTypeNo; tf.smartDashesType = UITextSmartDashesTypeNo; tf.returnKeyType = UIReturnKeyDone;
    tf.text = v.item.name; tf.delegate = self;
    [self addSubview:tf];
    _renameField = tf; _renamePath = path; _renameHome = tf.frame;
    DMDesktopFocus(YES);
    UIWindow *key = nil; for (UIWindow *w in self.window.windowScene.windows) if (w.isKeyWindow) key = w;
    _keyBefore = key;
    if (!self.window.isKeyWindow) [self.window makeKeyWindow];
    [tf becomeFirstResponder];
    NSString *base = (!v.item.dir && v.item.name.pathExtension.length && v.item.name.stringByDeletingPathExtension.length) ? v.item.name.stringByDeletingPathExtension : v.item.name;
    UITextPosition *start = tf.beginningOfDocument, *end = [tf positionFromPosition:start offset:(NSInteger)base.length];
    if (end) tf.selectedTextRange = [tf textRangeFromPosition:start toPosition:end];
    [self dm_fitRenameField];
    DMLog([NSString stringWithFormat:@"[desktop] rename in place (first responder %d)", tf.isFirstResponder]);
}
// The on-screen keyboard covers the lower part of the screen: a name edited there (an icon low on the desktop, a New Text File made where the
// finger was) stood hidden under it (iPad 2, landscape). The field moves up above the keyboard while it is up, and back under its icon after.
- (void)dm_fitRenameField {
    UITextField *tf = _renameField;
    if (!tf) return;
    CGRect f = _renameHome;
    if (!CGRectIsEmpty(gOwnKeyboardFrame)) {
        CGRect kb = [self convertRect:gOwnKeyboardFrame fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
        if (CGRectGetMaxY(f) > CGRectGetMinY(kb) - 8.0) f.origin.y = CGRectGetMinY(kb) - 8.0 - f.size.height;
    }
    if (CGRectEqualToRect(f, tf.frame)) return;
    [UIView animateWithDuration:0.2 animations:^{ tf.frame = f; }];
    DMLog([NSString stringWithFormat:@"[desktop] rename field %@ (keyboard %@)", CGRectEqualToRect(f, _renameHome) ? @"back under its icon" : @"above the keyboard", NSStringFromCGRect(gOwnKeyboardFrame)]);
}
- (void)dm_endRename:(BOOL)commit {
    UITextField *tf = _renameField; NSString *path = _renamePath;
    if (!tf) return;
    _renameField = nil; _renamePath = nil;
    NSString *t = [tf.text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    [tf resignFirstResponder]; [tf removeFromSuperview];
    DMDesktopFocus(NO);
    UIWindow *before = _keyBefore; _keyBefore = nil;
    if (before && before != self.window && !before.hidden) [before makeKeyWindow];
    if (commit && t.length && ![t isEqualToString:path.lastPathComponent]) {
        NSArray *f = _places[path.lastPathComponent]; if (f && !_places[t]) _places[t] = f;   // (the new name takes the place at once)
        _selectWhenListed = @[[path.stringByDeletingLastPathComponent stringByAppendingPathComponent:t]];   // (and stays selected, as on a Mac)
        DMFinderOps().path = _folder;
        [DMFinderOps() dm_renameItem:path to:t];
    }
    DMLog([NSString stringWithFormat:@"[desktop] rename in place ended: %@", commit ? @"kept the typing" : @"name kept"]);
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { if (tf == _renameField) { [self dm_endRename:YES]; return NO; } return YES; }
- (void)textFieldDidEndEditing:(UITextField *)tf { if (tf == _renameField) [self dm_endRename:YES]; }

// ---- keys (a hardware keyboard, while the desktop was clicked last) ----
// (the desktop has the keys when it was clicked last, or when nothing is in front of it: no Finder window active, no app in front)
- (BOOL)dm_hasKeys { return (_hasKeys || _renameField || (!gNativeActive && !DMActiveApp())) && self.window && self.userInteractionEnabled && !_editing; }
- (BOOL)dm_handleKey:(UIKey *)key {
    UIKeyModifierFlags m = key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierShift | UIKeyModifierAlternate | UIKeyModifierControl);
    BOOL cmd = m == UIKeyModifierCommand, cmdShift = m == (UIKeyModifierCommand | UIKeyModifierShift), none = m == 0;
    long c = (long)key.keyCode;
    if (_renameField) {
        if (c == UIKeyboardHIDUsageKeyboardEscape && none) { [self dm_endRename:NO]; return YES; }
        if (c == UIKeyboardHIDUsageKeyboardReturnOrEnter && none) { [self dm_endRename:YES]; return YES; }
        return NO;
    }
    NSArray<DMFinderItem *> *sel = [self dm_selectedItems];
    DMFinderWindow *ops = DMFinderOps();
    switch (c) {
        case UIKeyboardHIDUsageKeyboardSpacebar: if (none && sel.count) { DMQuickLookOpen(sel.firstObject.path); return YES; } break;
        case UIKeyboardHIDUsageKeyboardReturnOrEnter: if (none && sel.count == 1) { [self dm_beginRename:sel.firstObject.path]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardO: if (cmd && sel.count) { [self dm_openItems:sel]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardDownArrow: if (cmd && sel.count) { [self dm_openItems:sel]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardDeleteOrBackspace: if (cmd && sel.count) { [self dm_trash:sel]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardI: if (cmd && sel.count) { for (DMFinderItem *x in sel) [ops getInfo:x]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardZ: if (cmd && [ops dm_canUndo]) { ops.path = _folder; [ops dm_undo]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardA: if (cmd) { [self dm_select:[_items valueForKey:@"path"]]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardC: if (cmd && sel.count) { gFinderClipboard = [[sel valueForKey:@"path"] mutableCopy]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardN: if (cmdShift) { [self dm_newFolderAt:[self dm_screen:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))]]; return YES; } break;
        case UIKeyboardHIDUsageKeyboardD: if (cmdShift) { DMFinderOpen(_folder, YES); return YES; } break;
        case UIKeyboardHIDUsageKeyboardEscape: if (none && sel.count) { [self dm_select:@[]]; return YES; } break;
        default: break;
    }
    return NO;
}

// One line for the untested-iPadOS diagnostics (DMDesktopDiag): page 1's list (class, size), whether page 1 shows, jiggle mode, how many of our
// icons, and what lies on the page (app icons / widgets kept free, the list's focus guides, the page dots) -- the facts that tell, from a report,
// whether the Home Screen still has the shape this desktop expects. Names and numbers only (no file names).
- (NSString *)dm_diagLine {
    UIView *list = _list;
    NSUInteger icons = 0, widgets = 0, guides = 0;
    Class iv = objc_getClass("SBIconView"), fg = objc_getClass("SBHFocusGuideView");
    for (UIView *v in list.subviews) {
        if (v == self) continue;
        if (iv && [v isKindOfClass:iv]) { if ([NSStringFromClass([v class]) containsString:@"Widget"]) widgets++; else icons++; }
        else if ([NSStringFromClass([v class]) containsString:@"Widget"]) widgets++;
        else if (fg && [v isKindOfClass:fg]) guides++;
    }
    NSUInteger occupied = [self dm_occupied].count;
    return [NSString stringWithFormat:@"page1 %@ %.0fx%.0f shown %d editing %d alpha %.1f; items %lu; on page: icons %lu widgets %lu guides %lu, kept free %lu",
            list ? NSStringFromClass([list class]) : @"none", list.bounds.size.width, list.bounds.size.height, [self dm_pageShowing], _editing, self.alpha,
            (unsigned long)_items.count, (unsigned long)icons, (unsigned long)widgets, (unsigned long)guides, (unsigned long)occupied];
}

#if DEBUG
// desk_<what>[:<arg>] (StatusBar.x trigger): the desktop's state and actions for tests -- names only of the test items.
- (void)dm_debug:(NSString *)spec {
    NSRange r = [spec rangeOfString:@":"];
    NSString *act = r.location == NSNotFound ? spec : [spec substringToIndex:r.location], *arg = r.location == NSNotFound ? nil : [spec substringFromIndex:r.location + 1];
    DMDesktopItemView *v = arg ? _views[arg] : nil;
    if ([act isEqualToString:@"state"]) {
        DMLog([NSString stringWithFormat:@"[desktop] test state: list %@ %@, items %lu, side %.1f cell %.0fx%.0f font %@ %.1f, editing %d, alpha %.2f, area %@, selected %lu, keys %d",
               _list ? NSStringFromClass([_list class]) : @"none", NSStringFromCGRect(_list.frame), (unsigned long)_items.count, _side, _cellW, _cellH, _font.fontName, _font.pointSize, _editing, self.alpha,
               NSStringFromCGRect([self dm_area]), (unsigned long)_sel.count, _hasKeys]);
        for (NSString *n in _views) if ([n hasPrefix:@"MSB"]) DMLog([NSString stringWithFormat:@"[desktop] test icon %@ at %@ (screen %@) selected %d", n, NSStringFromCGRect(_views[n].frame), NSStringFromCGPoint([self dm_screen:_views[n].center]), _views[n].selected]);
        NSUInteger hits = 0; for (NSValue *o in [self dm_occupied]) for (NSString *n in _views) if (CGRectIntersectsRect(o.CGRectValue, _views[n].frame)) hits++;
        DMLog([NSString stringWithFormat:@"[desktop] test occupied: %lu icon views", (unsigned long)[self dm_occupied].count]);
        DMLog([NSString stringWithFormat:@"[desktop] test: %lu icon(s) over an app icon or widget", (unsigned long)hits]);
    }
    else if ([act isEqualToString:@"select"] && v) [self dm_select:@[v.item.path]];
    else if ([act isEqualToString:@"selectall"]) [self dm_select:[_items valueForKey:@"path"]];
    else if ([act isEqualToString:@"edit"]) {   // edit:<0|1>: the Home Screen's jiggle mode on / off (the icon manager's own switch)
        id im = DMCall(DMSBManager("SBIconController"), @"iconManager");
        if ([im respondsToSelector:@selector(setEditing:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(im, @selector(setEditing:), [arg boolValue]);
    }
    else if ([act isEqualToString:@"open"] && v) [self dm_openItems:@[v.item]];
    else if ([act isEqualToString:@"menutitles"]) {   // menutitles[:<name>]: the menu's rows for that icon (with the selection), or the empty desktop's
        UIMenu *m = [self dm_menuFor:v at:CGPointZero]; NSMutableArray *t = [NSMutableArray array];
        for (UIMenuElement *g in m.children) { if ([g isKindOfClass:[UIMenu class]]) { for (UIMenuElement *x in ((UIMenu *)g).children) [t addObject:[NSString stringWithFormat:@"%@%@", x.title, [x isKindOfClass:[UIAction class]] && (((UIAction *)x).attributes & UIMenuElementAttributesDisabled) ? @" (off)" : [x isKindOfClass:[UIAction class]] && (((UIAction *)x).attributes & UIMenuElementAttributesDestructive) ? @" (red)" : @""]]; [t addObject:@"|"]; } }
        DMLog([NSString stringWithFormat:@"[desktop] test menu: %@", [t componentsJoinedByString:@" "]]); }
    else if ([act isEqualToString:@"cleanup"]) [self dm_cleanUp];
    else if ([act isEqualToString:@"dup"] && v) [self dm_duplicate:@[v.item]];
    else if ([act isEqualToString:@"rename"] && v) [self dm_beginRename:v.item.path];
    else if ([act isEqualToString:@"renameto"]) { NSArray *q = [arg componentsSeparatedByString:@"|"]; DMDesktopItemView *x = q.count == 2 ? _views[q[0]] : nil; if (x) { DMFinderOps().path = _folder; [DMFinderOps() dm_renameItem:x.item.path to:q[1]]; } }
    else if ([act isEqualToString:@"trash"] && v) [self dm_trash:@[v.item]];
    else if ([act isEqualToString:@"newfolder"]) [self dm_newFolderAt:[self dm_screen:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))]];
    else if ([act isEqualToString:@"newtext"]) { NSArray *q = [arg componentsSeparatedByString:@","];   // newtext[:<x>,<y>]: New Text File at that screen point
        [self dm_newTextFileAt:q.count == 2 ? CGPointMake([q[0] doubleValue], [q[1] doubleValue]) : [self dm_screen:CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds))]]; }
    else if ([act isEqualToString:@"undo"]) { DMFinderOps().path = _folder; [DMFinderOps() dm_undo]; }
    else if ([act isEqualToString:@"endrename"]) [self dm_endRename:[arg isEqualToString:@"1"]];
    else if ([act isEqualToString:@"type"] && _renameField) _renameField.text = arg;
    else if ([act isEqualToString:@"place"]) { NSArray *q = [arg componentsSeparatedByString:@","]; DMDesktopItemView *x = q.count == 3 ? _views[q[0]] : nil;   // place:<name>,<x>,<y>: as if dropped there (screen point)
        if (x) { CGRect area = [self dm_area]; CGPoint p = [self convertPoint:CGPointMake([q[1] doubleValue], [q[2] doubleValue]) fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
                 DMPlacer pl; [self dm_placer:&pl area:area]; for (NSString *n in _views) if (_views[n] != x) DMPlacerTake(&pl, _views[n].frame);
                 int fits = 1; CGPoint c = DMPlacerPlaceNear(&pl, p, &fits); DMPlacerFree(&pl);
                 if (fits) _places[x.item.name] = [self dm_fractionFor:c area:area];
                 [self dm_savePlaces]; [self dm_placeAgain]; } }
    else if ([act isEqualToString:@"folderimage"]) { _folderImage = nil; [self dm_list]; }
    else if ([act isEqualToString:@"at"]) {   // at:<x>,<y>: what the desktop's drop test sees at that screen point
        NSArray *q = [arg componentsSeparatedByString:@","]; if (q.count != 2) return;
        CGPoint sp = CGPointMake([q[0] doubleValue], [q[1] doubleValue]);
        UIView *h = [self.window hitTest:[self.window convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace] withEvent:nil];
        NSMutableString *chain = [NSMutableString string]; for (UIView *x = h; x && chain.length < 400; x = x.superview) [chain appendFormat:@"%@ < ", NSStringFromClass([x class])];
        CGPoint p = [self convertPoint:sp fromCoordinateSpace:(self.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
        DMLog([NSString stringWithFormat:@"[desktop] test at %@: local %@ in area %d, shown %d, hit %@", NSStringFromCGPoint(sp), NSStringFromCGPoint(p), CGRectContainsPoint([self dm_area], p), [self dm_shownAt:sp], chain]);
    }
    else if ([act isEqualToString:@"files"]) {   // where the Files app's icon view is
        Class iv = objc_getClass("SBIconView");
        for (UIWindow *w in DMAllWindows()) { NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
            while (todo.count) { UIView *x = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:x.subviews];
                if (iv && [x isKindOfClass:iv]) { id bid = nil; @try { bid = DMCall(DMCall(x, @"icon"), @"applicationBundleID"); } @catch (NSException *e) {}
                    if ([bid isEqual:@"com.apple.DocumentsApp"]) { NSMutableString *ch = [NSMutableString string]; for (UIView *y = x.superview; y && ch.length < 500; y = y.superview) [ch appendFormat:@"%@%@ < ", NSStringFromClass([y class]), y.hidden ? @"(hidden)" : @""];
                        DMLog([NSString stringWithFormat:@"[desktop] test: Files icon view in %@: %@", NSStringFromClass([w class]), ch]); } } } }
        { id im = DMCall(DMSBManager("SBIconController"), @"iconManager"); unsigned n = 0; Method *ms = class_copyMethodList([im class], &n); NSMutableArray *hits = [NSMutableArray array];
          for (unsigned i = 0; i < n; i++) { NSString *m = NSStringFromSelector(method_getName(ms[i])); if ([m containsString:@"iconViewFor"] || [m containsString:@"IconViewFor"]) [hits addObject:m]; } free(ms);
          DMLog([NSString stringWithFormat:@"[desktop] test: icon manager %@: %@", NSStringFromClass([im class]), [hits componentsJoinedByString:@" "]]); }
        id label = nil; for (UIView *x in _list.subviews) if ([x isKindOfClass:iv]) { label = DMCall(x, @"labelView"); break; }
        DMLog([NSString stringWithFormat:@"[desktop] test: label view %@, params %@", label ? NSStringFromClass([label class]) : @"none", DMCall(label, @"imageParameters") ? NSStringFromClass([DMCall(label, @"imageParameters") class]) : @"none"]);
        for (NSString *cn in @[@"SBIconView", @"SBIconLegibilityLabelView", @"SBIconLabelImageParameters", @"SBIconLabelImageParametersBuilder"]) {   // (which methods name the label's font)
            Class c = objc_getClass(cn.UTF8String); if (!c) { DMLog([NSString stringWithFormat:@"[desktop] test: no class %@", cn]); continue; }
            unsigned n = 0; Method *ms = class_copyMethodList(c, &n); NSMutableArray *hits = [NSMutableArray array];
            for (unsigned i = 0; i < n; i++) { NSString *m = NSStringFromSelector(method_getName(ms[i])); if ([m.lowercaseString containsString:@"font"] || [m.lowercaseString containsString:@"param"] || [m.lowercaseString containsString:@"legib"]) [hits addObject:m]; }
            free(ms);
            DMLog([NSString stringWithFormat:@"[desktop] test: %@: %@", cn, [hits componentsJoinedByString:@" "]]);
        }
    }
}
#endif
@end

// ---- for Finder.h's drag ----
static NSString *DMDesktopFolderAt(CGPoint sp, UIView **icon) {
    if (icon) *icon = nil;
    DMDesktop *dk = gDesktop;
    if (!dk || ![dk dm_shownAt:sp]) return nil;
    DMDesktopItemView *v = [dk dm_itemViewAtScreen:sp];
    if (v && v.alpha > 0.5 && v.item.dir && !v.item.locked && !v.item.package && ![v.item.name hasSuffix:@".app"]) { if (icon) *icon = v; return v.item.path; }
    return dk.folder;
}
static void DMDesktopTakeDrop(DMFDrag *d, CGPoint sp, NSString *dest, BOOL ontoFolderIcon) {
    if (gDesktop) [gDesktop dm_takeDrop:d at:sp into:dest ontoFolder:ontoFolderIcon];
    else DMFDDropInto(d, dest, DMFDFromFinderWindow(d) ? d.from : DMFinderOps(), @"the desktop");
}

// ---- switched on and off ----
// Settings > Mac Status Bar > Show Desktop Icons (desktopIcons, on unless set; with Finder on). iPadOS 17 (untested, "Enable Anyway"): the same
// switch, and the desktop goes up only once its check of the Home Screen parts it uses has passed (DMDesktopNewOSReady, in DMDesktopTick).
// iPadOS 18+: off, as before 1.4 (only 17 was ported and read; the Wi-Fi menu and the Mac Switcher stop at 17 the same way).
static BOOL DMDesktopPrefOn(void) {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 18) return NO;
    CFPreferencesAppSynchronize(MSB_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("desktopIcons"), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : (CFGetTypeID(v) == CFNumberGetTypeID() ? [(__bridge NSNumber *)v boolValue] : YES));
    if (v) CFRelease(v);
    return on;
}
static void DMDesktopApplyPref(void) {
    gDesktopOn = DMDesktopPrefOn();
    DMLog([NSString stringWithFormat:@"[desktop] Show Desktop Icons %@", gDesktopOn ? @"on" : @"off"]);
}
// SpringBoard's focus guides (SBHFocusGuideView: invisible strips beside the Home Screen's icon rows, there for keyboard focus) lie in front of
// the desktop and took the touch from a desktop icon they cross: a tap on that part of the icon did nothing (iPad 2, 3 Oct: a 12 pt strip down
// the left column in portrait). Over a desktop icon they let the touch through; everywhere else they answer as before.
static UIView *(*gFocusGuideHitTestOrig)(id, SEL, CGPoint, UIEvent *);
// It must never hit-test a window itself: that comes back here (-dm_shownAt: hit-tests the Home Screen's window, whose focus guides answer through
// this very method -- endless, SpringBoard crashed on a touch, iPad 2 3 Oct, 1.3 logic re-check). Only the desktop's own icon frames are asked,
// and a call made while one is already running goes straight to the original.
static UIView *DMFocusGuideHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e) {
    static BOOL inside = NO;
    DMDesktop *dk = gDesktop;
    if (!inside && dk && dk.window && !dk.window.hidden && !dk.hidden && dk.alpha > 0.01 && dk.userInteractionEnabled) {
        inside = YES;
        UIView *v = (UIView *)self;
        CGPoint sp = [v convertPoint:p toCoordinateSpace:(v.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
        BOOL over = [dk dm_itemViewAtScreen:sp] != nil;
        inside = NO;
        if (over) return nil;
    }
    return gFocusGuideHitTestOrig ? gFocusGuideHitTestOrig(self, _cmd, p, e) : nil;
}
static void DMDesktopHookFocusGuides(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    Class c = objc_getClass("SBHFocusGuideView");
    Method m = c ? class_getInstanceMethod(c, @selector(hitTest:withEvent:)) : NULL;
    if (!m) return;
    // (its own method, or the one it inherits: added on the class so only focus guides change)
    if (class_addMethod(c, @selector(hitTest:withEvent:), (IMP)DMFocusGuideHitTest, method_getTypeEncoding(m))) gFocusGuideHitTestOrig = (void *)method_getImplementation(m);
    else gFocusGuideHitTestOrig = (void *)method_setImplementation(m, (IMP)DMFocusGuideHitTest);
}
// ---- iPadOS 17+ (untested versions, "Enable Anyway"; 2026-10-03) ----
// 1.3 left the desktop off on 17+ only because it had not been tried there. Every class and method it uses was checked against iPadOS 17.0.3's
// runtime headers and 17.6.1's SpringBoardHome (also 18.2's): the same shapes as on 16 -- page 1 is the leftmost SBIconListView in the root
// folder's SBIconScrollView, the list itself only acts on the icon views added to it (-didAddSubview:), the focus guides still inherit UIView's hit
// test, the names' font and legibility come from the icon view as on 16. On the iPad it is checked again, once, when the desktop is first wanted
// (SpringBoard is up by then; runtime lookups only -- nothing is messaged or made): the parts it cannot do without, and the extras that only cost
// a look (a stand-in font or colour, the focus-guide fix; the folders' picture is drawn and needs nothing of SpringBoard's). A part it needs
// missing: the desktop stays off, Settings leaves its switch out on this iPadOS build (common/DesktopCheck.h) and the diagnostics say which part
// (Report a Problem). 15/16: never asked.
typedef struct { const char *cls, *sel; BOOL meta, must; } DMDesktopNeed;
static const DMDesktopNeed kDMDesktopNeeds[] = {
    {"SBIconController", "sharedInstance", YES, YES}, {"SBIconController", "iconManager", NO, YES},
    {"SBHIconManager", "rootFolderController", NO, YES}, {"SBHIconManager", "isEditing", NO, YES},
    {"SBIconScrollView", NULL, NO, YES}, {"SBIconListView", NULL, NO, YES}, {"SBIconView", "icon", NO, YES},
    {"SBIconView", "displayedLabelFont", NO, NO}, {"SBIconView", "_labelImageParameters", NO, NO}, {"SBIconView", "_legibilitySettingsWithParameters:", NO, NO},
    {"SBIconListView", "iconImageSize", NO, NO},
    {"SBHFocusGuideView", NULL, NO, NO}, {"SBFolderScrollAccessoryView", NULL, NO, NO},
};
static int gDesktopCheck = -1;                         // (17+: 1 ready, 0 a part it needs is missing, -1 not checked yet)
static NSString *gDesktopCheckWhy, *gDesktopCheckSoft;  // (17+: the parts it needs that are missing; the extras that are missing)
static BOOL DMDesktopNewOSReady(void) {
    if (gDesktopCheck >= 0) return gDesktopCheck == 1;
    NSMutableArray *hard = [NSMutableArray array], *soft = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kDMDesktopNeeds) / sizeof(kDMDesktopNeeds[0]); i++) {
        const DMDesktopNeed *n = &kDMDesktopNeeds[i];
        Class c = objc_getClass(n->cls);
        if (c && (!n->sel || class_respondsToSelector(n->meta ? object_getClass(c) : c, sel_registerName(n->sel)))) continue;   // (no +initialize run)
        [n->must ? hard : soft addObject:n->sel ? [NSString stringWithFormat:@"%s[%s %s]", n->meta ? "+" : "-", n->cls, n->sel] : @(n->cls)];
    }
    gDesktopCheck = hard.count ? 0 : 1;
    gDesktopCheckWhy = hard.count ? [hard componentsJoinedByString:@", "] : nil;
    gDesktopCheckSoft = soft.count ? [soft componentsJoinedByString:@", "] : nil;
    DMLog([NSString stringWithFormat:@"[desktop] iPadOS %ld: %@%@", (long)[NSProcessInfo processInfo].operatingSystemVersion.majorVersion,
           hard.count ? [@"not on, missing " stringByAppendingString:gDesktopCheckWhy] : @"the Home Screen has everything the desktop needs",
           soft.count ? [@"; extras missing " stringByAppendingString:gDesktopCheckSoft] : @""]);
    // (the verdict for Settings, per iPadOS build, as the Stage Manager engine's: written once per start)
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"build"] = MSBDOSBuild() ?: @"";
    v[@"ok"] = @(gDesktopCheck == 1);
    if (gDesktopCheckWhy) v[@"reason"] = gDesktopCheckWhy;
    CFPreferencesSetValue(MSBD_DESKTOP_CHECK_KEY, (__bridge CFPropertyListRef)v, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return gDesktopCheck == 1;
}
// The "Finder" record of the untested-iPadOS diagnostics (common/Diag.h; 17+ with Enable Anyway): the desktop's check and where it sits, and the
// native windows' layer (Finder's windows, the text window, the desktop's menus' keyboard). At most every 10 s, written only when it changed.
// Names and numbers only: no file or folder names, no app names.
static void DMDesktopDiag(void) {
    if (!MSBDDiagEnabled()) return;
    static CFTimeInterval last = -100; if (CACurrentMediaTime() - last < 10.0) return; last = CACurrentMediaTime();
    NSMutableString *t = [NSMutableString string];
    [t appendFormat:@"desktop: check %@%@%@; finder %d switch %d folder %d\n", gDesktopCheck < 0 ? @"not run" : gDesktopCheck ? @"ok" : @"failed",
        gDesktopCheckWhy ? [@", missing " stringByAppendingString:gDesktopCheckWhy] : @"", gDesktopCheckSoft ? [@"; extras missing " stringByAppendingString:gDesktopCheckSoft] : @"",
        gFinderOn, gDesktopOn, DMFinderDesktopFolder(NO) != nil];
    if (gDesktop) [t appendFormat:@"%@; look %d folder icon %d guides %d rename lock %@\n", [gDesktop dm_diagLine], gDesktopLookRead, gDesktopFolderFrom,
        gFocusGuideHitTestOrig != NULL, gDesktopFocusLock ? NSStringFromClass([gDesktopFocusLock class]) : @"-"];
    UIWindow *l = gNativeLayer;
    [t appendFormat:@"windows: layer %@ level %.1f scene %d key %d, %lu open, active %d, focus lock %@", l ? NSStringFromClass([l class]) : @"none", l.windowLevel,
        l.windowScene != nil, l.isKeyWindow, (unsigned long)gNativeWindows.count, gNativeActive != nil, gNativeFocusLock ? NSStringFromClass([gNativeFocusLock class]) : @"-"];
    MSBDDiagWrite(@"Finder", t);
}
// Every tick (DMNativeTick): made when wanted (and its folder with it), kept on page 1, gone when switched off.
static void DMDesktopTick(void) {
    DMDesktopDiag();
    BOOL want = gFinderOn && gDesktopOn && !DMCtorSkip("desktop");
    if (want && DMNewOS() && !DMDesktopNewOSReady()) want = NO;   // (iPadOS 17+: only with every Home Screen part it needs, checked once)
    if (!want) { if (gDesktop) { [gDesktop dm_teardown]; gDesktop = nil; DMLog(@"[desktop] off: icons removed"); } return; }
    if (!gDesktop) {
        static CFTimeInterval tried; if (CACurrentMediaTime() - tried < 5.0) return; tried = CACurrentMediaTime();
        NSString *folder = DMFinderDesktopFolder(YES);
        if (!folder) return;
        gDesktop = [[DMDesktop alloc] initWithFolder:folder];
        DMDesktopHookFocusGuides();
        gFinderDesktopPlaceFor = DMDesktopPlaceFor;
        DMFinderOpsHost *ops = (DMFinderOpsHost *)DMFinderOps();
        ops.path = folder;
        __weak DMDesktop *wd = gDesktop;
        ops.madeItems = ^(NSArray<NSString *> *paths) { [wd dm_made:paths]; };
    }
    [gDesktop dm_tick];
}
// ---- the desktop right after a respring (1.3.6) ----
// The desktop was made by the 0.2 s watcher's tick (DMNativeTick), which starts 8 s after SpringBoard does (with the windows' restore): page 1's
// app icons had been on screen for seconds before the desktop's came. From the start a light look -- every 0.1 s, the windows only: no SpringBoard
// object is asked for or made -- waits for page 1's icon list in the Home Screen's window; the desktop is then made and put there at once (the
// tick's own call, DMDesktopTick), the same moment as the app icons. It stops once the desktop is there (or after 20 s: the watcher's tick goes on
// trying as before). debug /tmp/msb-desk-late: the old timing (only the moment page 1 shows is logged), to compare.
static NSTimer *gDeskEarlyTimer;
static CFTimeInterval gDeskEarlyStart = 0;
static BOOL DMDesktopPageOneOnScreen(void) {   // (an icon list laid out in the Home Screen's scroll view, in a window)
    Class sc = objc_getClass("SBIconScrollView"), lc = objc_getClass("SBIconListView");
    if (!sc || !lc) return NO;
    for (UIWindow *w in DMAllWindows()) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBHomeScreenWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        for (int depth = 0; depth < 12 && todo.count; depth++) {
            NSMutableArray *next = [NSMutableArray array];
            for (UIView *v in todo) {
                if ([v isKindOfClass:sc]) { for (UIView *l in v.subviews) if ([l isKindOfClass:lc] && !l.hidden && l.window && !CGRectIsEmpty(l.bounds)) return YES; continue; }
                [next addObjectsFromArray:v.subviews];
            }
            todo = next;
        }
    }
    return NO;
}
static void DMDesktopEarlyStop(NSString *why) {
    [gDeskEarlyTimer invalidate];
    gDeskEarlyTimer = nil;
    DMLog([NSString stringWithFormat:@"[desktop] start-up look stopped %.2f s after it began: %@", CACurrentMediaTime() - gDeskEarlyStart, why]);
}
static void DMDesktopEarlyTick(void) {
    static BOOL pageSeen = NO, upLogged = NO;
    CFTimeInterval since = CACurrentMediaTime() - gDeskEarlyStart;
    if (gDesktop.window) {   // (kept in place -- page 1 may still be laid out again while SpringBoard starts -- until the watcher's tick takes over)
        if (!upLogged) { upLogged = YES; DMLog([NSString stringWithFormat:@"[desktop] icons up %.2f s after the start-up look began", since]); }
        if (gDMWatcherStarted || since > 20.0) { DMDesktopEarlyStop(@"the desktop is on page 1, the watcher keeps it there"); return; }
        DMDesktopTick();
        return;
    }
    if (since > 20.0) { DMDesktopEarlyStop(@"page 1 not found yet (the watcher goes on)"); return; }
    if (!gFinderOn || !gDesktopOn || DMCtorSkip("desktop")) { DMDesktopEarlyStop(@"Show Desktop Icons or Finder is off"); return; }
    if (!DMDesktopPageOneOnScreen()) return;
    BOOL late = NO;
#if DEBUG
    late = DMTestFlag("/tmp/msb-desk-late");
#endif
    if (!pageSeen) { pageSeen = YES; DMLog([NSString stringWithFormat:@"[desktop] page 1 of the Home Screen is on screen %.2f s after the start-up look began%@", since, late ? @" (debug /tmp/msb-desk-late: the desktop waits for the watcher, as before)" : @": the desktop now"]); }
    if (late) { DMDesktopEarlyStop(@"debug /tmp/msb-desk-late"); return; }
    DM_FEATURE_MARK("desktop-at-start");
    DMDesktopTick();   // (made and put on page 1 -- or tried again on the next look)
}
// From the start (MacStatusBar's %ctor, on the first main-queue turn): only while Show Desktop Icons and Finder are on.
static void DMDesktopStartEarly(void) {
    if (gDeskEarlyTimer || gDesktop || !gFinderOn || !gDesktopOn || DMCtorSkip("desktop")) return;
    gDeskEarlyStart = CACurrentMediaTime();
    gDeskEarlyTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { DMDesktopEarlyTick(); }];
    [[NSRunLoop mainRunLoop] addTimer:gDeskEarlyTimer forMode:NSRunLoopCommonModes];
}
static void DMDesktopKeyboardMoved(void) { [gDesktop dm_fitRenameField]; }
static void DMDesktopAXOpen(DMDesktopItemView *v) { DMDesktop *d = (DMDesktop *)v.superview; if ([d isKindOfClass:[DMDesktop class]]) [d dm_axOpen:v]; }
static NSString *DMDesktopPlaceFor(NSString *path) { return [gDesktop dm_placeStringFor:path]; }   // (Finder.h gFinderDesktopPlaceFor)
