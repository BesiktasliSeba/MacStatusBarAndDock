// SidebarSearch.x -- a macOS-style search field at the top of the Settings sidebar (MacStatusBar&Dock 1.4.2).
// MacSettings.x hides the sidebar's navigation bar (no large title, no bar fading in), and iPadOS keeps its Settings search in that bar
// (navigationItem.searchController), so the search went with it. This puts it back the way macOS System Settings shows it: a rounded field
// (magnifying glass, "Search", clear button) pinned above the first row; while typing, the results are listed in the sidebar; picking one opens
// that page; Esc or an empty field brings the normal sidebar back. No title and no bar come back.
//
// It is Apple's own search underneath (read in Apple's binaries of 15.6.1 19G82 and 16.7.7 20H330; the same on both):
//  - the index and the query: the list's own -updateSearchResultsForSearchController: (Spotlight's Settings index through PSCoreSpotlightIndexer),
//    reached the way Apple's own field reaches it: the text typed here is put into Apple's search bar (programmatically, the bar stays hidden),
//    and UIKit hands it to the bar's results updater, the list;
//  - the results: Apple's results controller class (SUIKSearchResultsCollectionViewController) with its cells, icons, sorting and category filter
//    (the list is its delegate, as for Apple's own instance);
//  - picking a result: the same delegate call Apple's results make (the list's -searchResultsCollectionViewController:didSelectURL:, which opens
//    the page through the app's processURL:animated:fromSearch:); where Apple then ends its search (a result that is a row of the sidebar
//    itself, such as Airplane Mode; Apple ID sign-in; a PIN) it calls -setActive:NO on its search controller, and that ends this one too.
// Ours: the field and where it sits, and a second instance of Apple's results controller shown in the sidebar. A second one because UIKit makes
// Apple's instance a child of Apple's search controller the first time that one shows (in a narrow window the bar is visible and Apple's stock
// search runs as before), so that instance is never borrowed. While this field searches, the list's searchResultsController points to the second
// instance (the list's own setter, so Apple's query code fills it) and back to Apple's afterwards.
// Keys as on Apple's search bar: Esc, Up/Down (through the results), Return (open the highlighted one); Command-F goes to the field, and so does
// Tab through Apple's own Tab command (unless the Tab-mute switch, tabmute/TabMute.x, takes Tab for Mute).
//
// Defensive like the rest of MacSettings (other tweaks change this list, see MacSettings.x): the field lives outside the table (a band in the
// list's own container view; the list moves down through additionalSafeAreaInsets, which nothing else in Settings sets -- Apple sets the table's
// contentInset itself), no table callbacks are hooked, and every private class, selector and type encoding used here is checked once at load
// (MSSCheck): anything missing or different and nothing is hooked, no field (Settings as before). Switch: Settings > Status Bar > Apple Apps >
// Search Field in Settings (com.besiktasliseba.macsettings sidebarSearch, on unless switched off; applies at once).
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>
#import "SidebarSearchCheck.h"

#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)

@interface PSUIPrefsListController : UIViewController   // (for the hooks below; every call into it goes through the checked wrappers)
@end

BOOL MSSidebarBarCanGo(UIViewController *vc);   // MacSettings.x: the sidebar is shown next to the page (its bar is hidden then)
void MSSearchSidebarChanged(UIViewController *list);

#define kMSSDomain CFSTR("com.besiktasliseba.macsettings")
#define kMSSChanged "com.besiktasliseba.macsettings/searchChanged"
static const CGFloat kMSSFieldHeight = 36.0, kMSSPadTop = 6.0, kMSSPadBottom = 10.0;   // (52 pt in all: the height of Apple's own search bar row)

static void MSSLog(NSString *line) {   // (debug builds only: release builds write no /tmp log)
#if DEBUG
    if (access("/tmp/macsettings-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "[search] %s\n", line.UTF8String); fclose(f);
#endif
}

// ---- the check (once, at load: macsettings/SidebarSearchCheck.h) -------------------------------------------------------------------------------
static Class gMSSList, gMSSApple, gMSSResults;   // PSUIPrefsListController, PSKeyboardNavigationSearchController, SUIKSearchResultsCollectionViewController
static BOOL gMSSOK = NO;
static NSString *gMSSWhy;                        // (what the check found, for the log)
static BOOL MSSCheck(void) {
    NSMutableArray *why = [NSMutableArray array];
    gMSSList = objc_getClass("PSUIPrefsListController");
    gMSSApple = objc_getClass("PSKeyboardNavigationSearchController");
    gMSSResults = objc_getClass("SUIKSearchResultsCollectionViewController");
    MSSCheckClasses(gMSSList, gMSSApple, gMSSResults, why);
    gMSSWhy = why.count ? [why componentsJoinedByString:@"; "] : nil;
    return why.count == 0;
}

// ---- the checked calls (only ever made after MSSCheck passed) ---------------------------------------------------------------------------------
static UITableView *MSSTable(UIViewController *list) {
    id t = ((id (*)(id, SEL))objc_msgSend)(list, sel_registerName("table"));
    return [t isKindOfClass:[UITableView class]] ? t : nil;
}
// Apple's search controller of this list, if it is wired the way Apple's own field uses it (the list is its results updater, the bar a search bar);
// nil before it exists (it comes with the list's first asynchronous load) or when it is built some other way.
static UISearchController *MSSApple(UIViewController *list) {
    id sc = ((id (*)(id, SEL))objc_msgSend)(list, sel_registerName("spotlightSearchController"));
    if (![sc isKindOfClass:gMSSApple]) return nil;
    UISearchController *c = sc;
    if ((id)c.searchResultsUpdater != (id)list || ![c.searchBar isKindOfClass:[UISearchBar class]]) return nil;
    return c;
}
static id MSSListResults(UIViewController *list) { return ((id (*)(id, SEL))objc_msgSend)(list, sel_registerName("searchResultsController")); }
static void MSSSetListResults(UIViewController *list, id results) { ((void (*)(id, SEL, id))objc_msgSend)(list, sel_registerName("setSearchResultsController:"), results); }
static void MSSResultsDo(id results, const char *sel) { if ([results isKindOfClass:gMSSResults]) ((void (*)(id, SEL))objc_msgSend)(results, sel_registerName(sel)); }

// ---- the switch -------------------------------------------------------------------------------------------------------------------------------
static BOOL gMSSEnabled = YES;
static BOOL MSSReadEnabled(void) {
    CFPreferencesAppSynchronize(kMSSDomain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sidebarSearch"), kMSSDomain);
    BOOL on = YES;   // (never set: on)
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (v && CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 1; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    if (v) CFRelease(v);
    return on;
}

// ---- the field and its state --------------------------------------------------------------------------------------------------------------------
@class MSBDSidebarSearchState;
@interface MSBDSidebarSearchField : UISearchTextField
@property (nonatomic, weak) MSBDSidebarSearchState *owner;
@end
@interface MSBDSidebarSearchState : NSObject <UITextFieldDelegate>
@property (nonatomic, weak) UIViewController *list;
@property (nonatomic, strong) UIView *band;                          // the field's band at the top of the sidebar
@property (nonatomic, strong) MSBDSidebarSearchField *field;
@property (nonatomic, strong) UIView *resultsHost;                   // under the band while the field searches
@property (nonatomic, strong) UICollectionViewController *results;   // our instance of Apple's results controller
@property (nonatomic, strong) id appleResults;                       // Apple's own, while ours stands in for it in the list
@property (nonatomic) CGFloat inset;                                 // what was added to the list's additionalSafeAreaInsets.top
@property (nonatomic) BOOL searching, tableAXWasHidden;
@end
static const void *kMSSStateKey = &kMSSStateKey;
static MSBDSidebarSearchState *MSSStateOf(UIViewController *list) { return list ? objc_getAssociatedObject(list, kMSSStateKey) : nil; }
static __weak UIViewController *gMSSCurrentList;   // (the sidebar list last seen: the switch and Apple's controller arriving re-check it)
static NSString *gMSSPendingTerm;                  // (a Spotlight "search in Settings" term that came before the field)
static int gMSSUpdates = 0;                        // (calls of the list's results updater: did UIKit pass the text on)
static int gMSSIgnoreAppleEnd = 0;
static void MSSQuery(UIViewController *list, NSString *text);
static void MSSEnd(UIViewController *list, NSString *why);
static void MSSEscape(UIViewController *list);
static BOOL MSSMove(UIViewController *list, BOOL down);
static void MSSOpenHighlighted(UIViewController *list);
static void MSSLayout(UIViewController *list);

@implementation MSBDSidebarSearchField
// Esc and the arrows, as Apple's search bar has them (PSKeyboardNavigationSearchBar: priority over the text field's own use of them).
- (NSArray<UIKeyCommand *> *)keyCommands {
    NSMutableArray *k = [NSMutableArray arrayWithArray:[super keyCommands] ?: @[]];
    for (NSString *input in @[UIKeyInputEscape, UIKeyInputUpArrow, UIKeyInputDownArrow]) {
        UIKeyCommand *c = [UIKeyCommand keyCommandWithInput:input modifierFlags:0 action:@selector(msbd_key:)];
        if ([c respondsToSelector:@selector(setWantsPriorityOverSystemBehavior:)]) c.wantsPriorityOverSystemBehavior = YES;
        [k addObject:c];
    }
    return k;
}
- (void)msbd_key:(UIKeyCommand *)command {
    UIViewController *list = self.owner.list;
    if (!list) return;
    if ([command.input isEqualToString:UIKeyInputEscape]) MSSEscape(list);
    else MSSMove(list, [command.input isEqualToString:UIKeyInputDownArrow]);
}
@end

@implementation MSBDSidebarSearchState
- (void)msbd_textChanged { UIViewController *l = self.list; if (l) MSSQuery(l, self.field.text ?: @""); }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { UIViewController *l = self.list; if (l) MSSOpenHighlighted(l); return NO; }
- (BOOL)textFieldShouldClear:(UITextField *)textField {   // (the clear button: the normal sidebar again once the text is gone)
    __weak MSBDSidebarSearchState *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ MSBDSidebarSearchState *s = weakSelf; UIViewController *l = s.list; if (l && !s.field.text.length) MSSEnd(l, @"cleared"); });
    return YES;
}
@end

// ---- showing the field --------------------------------------------------------------------------------------------------------------------------
// The band coming or going moves where the rows start; a list shown from its first row keeps showing it from there. Noted before the inset
// changes, applied in the layout pass in which the table's adjusted inset has taken the change (a nested layout from inside one is avoided).
static const void *kMSSKeepTopKey = &kMSSKeepTopKey;
static BOOL MSSKeepTopNoted(UIViewController *list) {
    UITableView *t = MSSTable(list);
    BOOL atTop = t && t.contentOffset.y <= -t.adjustedContentInset.top + 0.5;
    objc_setAssociatedObject(list, kMSSKeepTopKey, atTop ? @(t.adjustedContentInset.top) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return atTop;
}
static void MSSKeepTop(UIViewController *list) {
    NSNumber *before = objc_getAssociatedObject(list, kMSSKeepTopKey);
    UITableView *t = before ? MSSTable(list) : nil;
    if (!t || fabs(t.adjustedContentInset.top - before.doubleValue) < 0.5) return;   // (not taken yet: a later pass)
    objc_setAssociatedObject(list, kMSSKeepTopKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (t.isDragging || t.isDecelerating) return;
    [t setContentOffset:CGPointMake(t.contentOffset.x, -t.adjustedContentInset.top) animated:NO];
}
static void MSSFocusField(MSBDSidebarSearchState *st) {
    if (!st.field.window) return;
    [st.field becomeFirstResponder];
    if (st.field.text.length) [st.field selectAll:nil];   // (Command-F on the Mac selects what is in the field)
}
static BOOL MSSContinueNow(UIViewController *list, NSString *term);
static void MSSInstall(UIViewController *list, UISearchController *apple) {
    DM_FEATURE_MARK("settings-search");
    MSBDSidebarSearchState *st = [MSBDSidebarSearchState new];
    st.list = list;
    UIView *band = [UIView new];
    band.accessibilityIdentifier = @"MSBDSidebarSearchBand";
    MSBDSidebarSearchField *f = [MSBDSidebarSearchField new];
    f.owner = st;
    f.delegate = st;
    f.placeholder = apple.searchBar.placeholder;      // (Apple's own, in the device's language: "Search")
    f.clearButtonMode = UITextFieldViewModeAlways;    // (the clear button whenever there is text, as on the Mac)
    f.returnKeyType = UIReturnKeySearch;
    [f addTarget:st action:@selector(msbd_textChanged) forControlEvents:UIControlEventEditingChanged];
    [band addSubview:f];
    st.band = band; st.field = f;
    st.inset = kMSSPadTop + kMSSFieldHeight + kMSSPadBottom;
    objc_setAssociatedObject(list, kMSSStateKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL atTop = MSSKeepTopNoted(list);
    UIEdgeInsets a = list.additionalSafeAreaInsets;
    a.top += st.inset;
    list.additionalSafeAreaInsets = a;   // (the list's rows start under the band; the table's own insets stay Apple's)
    [list.view addSubview:band];
    [list.view setNeedsLayout];
    MSSLog([NSString stringWithFormat:@"field shown (band %.0f pt, list at its top: %d)", st.inset, atTop]);
    if (gMSSPendingTerm.length) { NSString *term = gMSSPendingTerm; gMSSPendingTerm = nil; MSSContinueNow(list, term); }
}
static void MSSUninstall(UIViewController *list, NSString *why) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return;
    MSSEnd(list, why);
    if (st.field.isFirstResponder) [st.field resignFirstResponder];
    MSSKeepTopNoted(list);
    [st.band removeFromSuperview];
    UIEdgeInsets a = list.additionalSafeAreaInsets;
    a.top = MAX(0, a.top - st.inset);
    list.additionalSafeAreaInsets = a;
    objc_setAssociatedObject(list, kMSSStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [list.view setNeedsLayout];
    MSSLog([NSString stringWithFormat:@"field removed (%@)", why]);
}
// The field is shown exactly while MacSettings has the sidebar's bar hidden (the bar holds Apple's own field otherwise), the switch is on and
// Apple's search controller is there to search with. Called when the sidebar appears or goes (MacSettings.x), on its layout, when Apple's
// controller arrives and when the switch changes.
void MSSearchSidebarChanged(UIViewController *list) {
    if (!gMSSOK || ![list isKindOfClass:gMSSList]) return;
    gMSSCurrentList = list;
    MSBDSidebarSearchState *st = MSSStateOf(list);
    UISearchController *apple = nil;
    BOOL want = gMSSEnabled && list.isViewLoaded && MSSidebarBarCanGo(list) && list.navigationController.isNavigationBarHidden && (apple = MSSApple(list));
    if (want && !st.band) MSSInstall(list, apple);
    else if (!want && st.band) MSSUninstall(list, !gMSSEnabled ? @"switched off" : !MSSidebarBarCanGo(list) ? @"sidebar not beside the page" : !list.navigationController.isNavigationBarHidden ? @"bar shown" : @"Apple's search gone");
}

// The sidebar's own background (the table's, else its container's; an opaque one, so no row shows through the band).
static UIColor *MSSSidebarColor(UIViewController *list, UITableView *t) {
    for (UIColor *c in @[t.backgroundColor ?: [UIColor clearColor], list.view.backgroundColor ?: [UIColor clearColor]])
        if (CGColorGetAlpha([c resolvedColorWithTraitCollection:list.traitCollection].CGColor) > 0.99) return c;
    return [UIColor systemGroupedBackgroundColor];
}
// The band's place: over the top of the sidebar down to where its rows start; the field lines up with the rows (their rounded groups), as Apple's
// own field lines up with them in the bar. The band takes the table's own background, so it follows light and dark mode with it.
static void MSSLayout(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return;
    UIView *v = list.view;
    CGFloat w = v.bounds.size.width, top = v.safeAreaInsets.top;   // (top includes the band)
    st.band.frame = CGRectMake(0, 0, w, top);
    UITableView *t = MSSTable(list);
    CGFloat left = MAX(v.safeAreaInsets.left, 16.0), right = MAX(v.safeAreaInsets.right, 16.0);
    for (UITableViewCell *c in t.visibleCells) {
        if (c.hidden || c.bounds.size.width < 100) continue;
        CGRect r = [c convertRect:c.bounds toView:v];
        left = CGRectGetMinX(r); right = w - CGRectGetMaxX(r);
        break;
    }
    st.field.frame = CGRectMake(left, top - st.inset + kMSSPadTop, MAX(0.0, w - left - right), kMSSFieldHeight);
    // (while results show, the band joins them: Apple's result rows are plain list cells on the system background -- white in light mode, where
    //  the sidebar itself is grey; in dark mode the two are the same colour anyway)
    UIColor *bg = st.searching ? [UIColor systemBackgroundColor] : MSSSidebarColor(list, t);
    if (st.band.backgroundColor != bg) st.band.backgroundColor = bg;
    if (st.resultsHost) {
        st.resultsHost.frame = v.bounds;
        if (st.resultsHost.backgroundColor != bg) st.resultsHost.backgroundColor = bg;
    }
    if (v.subviews.lastObject != st.band) [v bringSubviewToFront:st.band];
}

// ---- searching ----------------------------------------------------------------------------------------------------------------------------------
static BOOL MSSBegin(UIViewController *list, UISearchController *apple) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return NO;
    if (apple.isActive) { gMSSIgnoreAppleEnd++; apple.active = NO; gMSSIgnoreAppleEnd--; }   // (cannot be with its bar hidden; never two searches)
    if (!st.results) {
        UICollectionViewController *r = [[gMSSResults alloc] init];   // (as Apple makes its own: init, then the list as its delegate)
        if (!r) return NO;
        ((void (*)(id, SEL, id))objc_msgSend)(r, sel_registerName("setDelegate:"), list);
        st.results = r;
    }
    id current = MSSListResults(list);
    if (current != st.results) { st.appleResults = current; MSSSetListResults(list, st.results); }
    MSSResultsDo(st.results, "searchQueryStarted");   // (Apple's own reset: nothing old shows while the first new results come)
    UIView *host = [[UIView alloc] initWithFrame:list.view.bounds];
    host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [list addChildViewController:st.results];
    st.results.view.frame = host.bounds;
    st.results.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host addSubview:st.results.view];
    [st.results didMoveToParentViewController:list];
    st.resultsHost = host;
    [list.view insertSubview:host belowSubview:st.band];
    UITableView *t = MSSTable(list);
    st.tableAXWasHidden = t.accessibilityElementsHidden;
    t.accessibilityElementsHidden = YES;   // (VoiceOver reads the results, not the rows under them)
    st.searching = YES;
    MSSLayout(list);
    MSSLog(@"results shown");
    return YES;
}
static void MSSQuery(UIViewController *list, NSString *text) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    UISearchController *apple = MSSApple(list);
    if (!st.band || !apple) return;
    if (!text.length) { MSSEnd(list, @"empty"); return; }
    if (!st.searching && !MSSBegin(list, apple)) return;
    gMSSUpdates = 0;
    apple.searchBar.text = text;   // -> UIKit -> the list's -updateSearchResultsForSearchController: -> Apple's index -> our results
    if (!gMSSUpdates) ((void (*)(id, SEL, id))objc_msgSend)(list, sel_registerName("updateSearchResultsForSearchController:"), apple);   // (UIKit did not pass it on: asked as UIKit would)
    MSSLog([NSString stringWithFormat:@"query (%lu characters, %@)", (unsigned long)text.length, gMSSUpdates ? @"through Apple's bar" : @"asked directly"]);
}
static void MSSEnd(UIViewController *list, NSString *why) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.searching) return;
    st.searching = NO;
    UISearchController *apple = MSSApple(list);
    if (apple.searchBar.text.length) apple.searchBar.text = @"";   // (Apple's own path for an empty field: our results are cleared, still in the list)
    if (MSSListResults(list) == st.results) MSSSetListResults(list, st.appleResults);
    st.appleResults = nil;
    [st.results willMoveToParentViewController:nil];
    [st.results.view removeFromSuperview];
    [st.results removeFromParentViewController];
    [st.resultsHost removeFromSuperview];
    st.resultsHost = nil;
    MSSTable(list).accessibilityElementsHidden = st.tableAXWasHidden;
    if (st.field.text.length) st.field.text = @"";   // (Apple ended it, or the field goes: the normal sidebar with an empty field)
    MSSLayout(list);   // (the band back in the sidebar's colour)
    MSSLog([NSString stringWithFormat:@"results gone (%@)", why]);
}
// After Esc or Return the list takes the keys again, as Apple's own field hands them back (-searchBarTextDidEndEditing:): Tab, the arrows.
static void MSSHandBack(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (st.field.isFirstResponder) [st.field resignFirstResponder];
    if (!list.isFirstResponder && list.view.window) [list becomeFirstResponder];
}
static void MSSEscape(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return;
    if (st.field.text.length) st.field.text = @"";
    MSSEnd(list, @"Esc");
    MSSHandBack(list);
}
static BOOL MSSMove(UIViewController *list, BOOL down) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.searching) return NO;
    MSSResultsDo(st.results, down ? "selectNextSearchResult" : "selectPreviousSearchResult");
    return YES;
}
static void MSSOpenHighlighted(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.searching) return;
    if (st.results.isViewLoaded && st.results.collectionView.indexPathsForSelectedItems.count) MSSResultsDo(st.results, "showSelectedSearchResult");
    MSSHandBack(list);
}
// A page was opened from our results (Apple's delegate call has run): the keys go back to the list, the results stay (Apple keeps them too,
// except for a row of the sidebar itself, where it ends its search: -setActive:NO below).
static void MSSPicked(UIViewController *list, id controller) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.searching || controller != st.results) return;
    MSSLog(@"result opened");
    MSSHandBack(list);
}
static void MSSAppleEnded(UISearchController *sc) {
    if (gMSSIgnoreAppleEnd) return;
    UIViewController *list = gMSSCurrentList;
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.searching || MSSApple(list) != sc) return;
    MSSEnd(list, @"Apple ended its search");
    MSSHandBack(list);
}
// Tab and Command-F: into the field (Apple's Tab puts the keys into its own field, hidden here).
static BOOL MSSFocus(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return NO;
    MSSFocusField(st);
    return YES;
}
// Spotlight's "Search in Settings": the term goes into this field (Apple's would activate its hidden controller).
static BOOL MSSContinueNow(UIViewController *list, NSString *term) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return NO;
    st.field.text = term;
    MSSQuery(list, term);
    MSSFocusField(st);
    MSSLog([NSString stringWithFormat:@"Spotlight term (%lu characters) in the field", (unsigned long)term.length]);
    return YES;
}
static BOOL MSSContinue(UIViewController *list, NSString *term) {
    if (![term isKindOfClass:[NSString class]] || !term.length || !gMSSEnabled || !MSSidebarBarCanGo(list)) return NO;   // (Apple's own field takes it)
    if (MSSContinueNow(list, term)) return YES;
    gMSSPendingTerm = [term copy];   // (the field is not there yet: it takes the term when it comes)
    return YES;
}
static NSArray *MSSKeyCommands(UIViewController *list, NSArray *apple) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    if (!st.band) return apple;
    NSMutableArray *k = [NSMutableArray arrayWithArray:apple ?: @[]];
    NSString *title = st.field.placeholder.length ? st.field.placeholder : @"Search";
    [k addObject:[UIKeyCommand commandWithTitle:title image:nil action:NSSelectorFromString(@"msbd_searchFind:") input:@"f" modifierFlags:UIKeyModifierCommand propertyList:nil]];
    if (st.searching) {   // (the field has given the keys back but its results are still shown)
        [k addObject:[UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:NSSelectorFromString(@"msbd_searchEscape:")]];
        [k addObject:[UIKeyCommand keyCommandWithInput:@"\r" modifierFlags:0 action:NSSelectorFromString(@"msbd_searchOpen:")]];
    }
    return k;
}

// ---- debug builds: a test channel (echo '<command>' > /tmp/macsettings-searchtest, with /tmp/macsettings-debug present) ----------------------
#if DEBUG
static NSString *MSSFrame(CGRect r) { return [NSString stringWithFormat:@"{%.0f,%.0f %.0fx%.0f}", r.origin.x, r.origin.y, r.size.width, r.size.height]; }
static void MSSDumpState(UIViewController *list) {
    MSBDSidebarSearchState *st = MSSStateOf(list);
    UITableView *t = MSSTable(list);
    UISearchController *apple = MSSApple(list);
    NSMutableString *s = [NSMutableString stringWithFormat:@"state: check %@, switch %d, list %@, beside page %d, bar hidden %d, apple %@ (active %d, bar text %lu)",
        gMSSOK ? @"ok" : gMSSWhy, gMSSEnabled, list ? NSStringFromClass([list class]) : @"none", list ? MSSidebarBarCanGo(list) : -1, list.navigationController.isNavigationBarHidden,
        apple ? NSStringFromClass([apple class]) : @"none", apple.isActive, (unsigned long)apple.searchBar.text.length];
    [s appendFormat:@"; field %@ %@ text %lu first responder %d; searching %d", st.band ? @"shown" : @"none", st.field ? MSSFrame([st.field convertRect:st.field.bounds toView:list.view]) : @"-", (unsigned long)st.field.text.length, st.field.isFirstResponder, st.searching];
    [s appendFormat:@"; band %@ bg %@; view %@ safe %.0f/%.0f/%.0f/%.0f extra top %.0f", st.band ? MSSFrame(st.band.frame) : @"-", st.band.backgroundColor, MSSFrame(list.view.bounds),
        list.view.safeAreaInsets.top, list.view.safeAreaInsets.left, list.view.safeAreaInsets.bottom, list.view.safeAreaInsets.right, list.additionalSafeAreaInsets.top];
    [s appendFormat:@"; table %@ offset %.0f adjusted top %.0f inset top %.0f bg %@ style %ld cells %lu", MSSFrame(t.frame), t.contentOffset.y, t.adjustedContentInset.top, t.contentInset.top, t.backgroundColor, (long)t.style, (unsigned long)t.visibleCells.count];
    if (t.visibleCells.count) [s appendFormat:@" first cell %@", MSSFrame([t.visibleCells.firstObject convertRect:[t.visibleCells.firstObject bounds] toView:list.view])];
    id listResults = MSSListResults(list);
    [s appendFormat:@"; list results %@ (%@)", listResults == st.results && st.results ? @"ours" : listResults == st.appleResults && st.appleResults ? @"Apple's (kept)" : @"Apple's", listResults ? NSStringFromClass([listResults class]) : @"none"];
    if (st.results.isViewLoaded) {
        UICollectionView *cv = st.results.collectionView;
        NSMutableString *n = [NSMutableString string];
        for (NSInteger i = 0; i < cv.numberOfSections; i++) [n appendFormat:@"%@%ld", i ? @"+" : @"", (long)[cv numberOfItemsInSection:i]];
        [s appendFormat:@"; our results: sections %ld items %@ frame %@ adjusted top %.0f offset %.0f bg %@ selected %lu", (long)cv.numberOfSections, n, MSSFrame([cv convertRect:cv.bounds toView:list.view]), cv.adjustedContentInset.top, cv.contentOffset.y, cv.backgroundColor, (unsigned long)cv.indexPathsForSelectedItems.count];
    }
    MSSLog(s);
}
static void MSSDumpTree(UIView *v, int depth, int maxDepth, NSMutableString *out) {
    [out appendFormat:@"\n%*s%@ %@%@%@", depth * 2, "", NSStringFromClass([v class]), MSSFrame(v.frame), v.hidden ? @" hidden" : @"", v.alpha < 1 ? [NSString stringWithFormat:@" alpha %.2f", v.alpha] : @""];
    if (depth >= maxDepth) { if (v.subviews.count) [out appendFormat:@" (+%lu)", (unsigned long)v.subviews.count]; return; }
    for (UIView *s in v.subviews) MSSDumpTree(s, depth + 1, maxDepth, out);
}
static void MSSTestCommand(NSString *cmd) {
    UIViewController *list = gMSSCurrentList;
    MSBDSidebarSearchState *st = MSSStateOf(list);
    MSSLog([NSString stringWithFormat:@"test: %@", [cmd componentsSeparatedByString:@" "].firstObject]);
    if ([cmd isEqualToString:@"state"]) MSSDumpState(list);
    else if ([cmd isEqualToString:@"check"]) MSSLog([NSString stringWithFormat:@"check: %@", gMSSOK ? @"ok" : gMSSWhy]);
    else if ([cmd hasPrefix:@"tree"]) {
        NSMutableString *out = [NSMutableString string];
        MSSDumpTree(list.navigationController.view ?: list.view, 0, [cmd isEqualToString:@"tree"] ? 4 : 7, out);
        MSSLog([@"tree:" stringByAppendingString:out]);
    } else if ([cmd hasPrefix:@"type "]) { st.field.text = [cmd substringFromIndex:5]; [st msbd_textChanged]; }   // (as typing: the field's change handler)
    else if ([cmd isEqualToString:@"clear"]) { st.field.text = @""; [st msbd_textChanged]; }
    else if ([cmd isEqualToString:@"esc"]) MSSEscape(list);
    else if ([cmd isEqualToString:@"down"] || [cmd isEqualToString:@"up"]) MSSMove(list, [cmd isEqualToString:@"down"]);
    else if ([cmd isEqualToString:@"ret"]) MSSOpenHighlighted(list);
    else if ([cmd isEqualToString:@"focus"]) MSSFocus(list);
    else if ([cmd isEqualToString:@"resign"]) [st.field resignFirstResponder];
    else if ([cmd hasPrefix:@"pick "]) {   // pick <n>: the n-th result, the way a tap selects it
        UICollectionView *cv = st.results.isViewLoaded ? st.results.collectionView : nil;
        NSInteger want = [[cmd substringFromIndex:5] integerValue], seen = 0;
        for (NSInteger sct = 0; cv && sct < cv.numberOfSections; sct++) for (NSInteger i = 0; i < [cv numberOfItemsInSection:sct]; i++, seen++) {
            if (seen != want) continue;
            ((void (*)(id, SEL, id, id))objc_msgSend)(st.results, sel_registerName("collectionView:didSelectItemAtIndexPath:"), cv, [NSIndexPath indexPathForItem:i inSection:sct]);
            return;
        }
        MSSLog(@"test: no such result");
    } else if ([cmd hasPrefix:@"results"]) {   // the results' titles (Apple's Settings item names) and subtitles' lengths
        UICollectionView *cv = st.results.isViewLoaded ? st.results.collectionView : nil;
        NSMutableString *out = [NSMutableString string];
        for (UICollectionViewCell *c in [cv.visibleCells sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) { return [@(a.frame.origin.y) compare:@(b.frame.origin.y)]; }]) {
            id cfg = [c isKindOfClass:[UICollectionViewListCell class]] ? ((UICollectionViewListCell *)c).contentConfiguration : nil;
            NSString *title = [cfg isKindOfClass:[UIListContentConfiguration class]] ? (((UIListContentConfiguration *)cfg).text ?: ((UIListContentConfiguration *)cfg).attributedText.string) : nil;
            [out appendFormat:@" | %@ y%.0f", title ?: @"?", c.frame.origin.y];
        }
        MSSLog([@"results:" stringByAppendingString:out]);
    } else if ([cmd isEqualToString:@"urls"]) {   // each result's URL, as a pick would open it (Apple's: the item's uniqueIdentifier), without opening it
        UICollectionView *cv = st.results.isViewLoaded ? st.results.collectionView : nil;
        id ds = [st.results respondsToSelector:sel_registerName("diffableDataSource")] ? ((id (*)(id, SEL))objc_msgSend)(st.results, sel_registerName("diffableDataSource")) : nil;
        NSMutableString *out = [NSMutableString string];
        NSInteger seen = 0;
        for (NSInteger sct = 0; cv && sct < cv.numberOfSections; sct++) for (NSInteger i = 0; i < [cv numberOfItemsInSection:sct]; i++, seen++) {
            id item = [ds respondsToSelector:@selector(itemIdentifierForIndexPath:)] ? [ds itemIdentifierForIndexPath:[NSIndexPath indexPathForItem:i inSection:sct]] : nil;
            NSString *u = [item respondsToSelector:sel_registerName("uniqueIdentifier")] ? ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("uniqueIdentifier")) : nil;
            [out appendFormat:@" | %ld %@", (long)seen, u ?: @"?"];
        }
        MSSLog([@"urls:" stringByAppendingString:out]);
    } else if ([cmd hasPrefix:@"cont "]) ((void (*)(id, SEL, id))objc_msgSend)(list, sel_registerName("continueSearchInSettingsWithTerm:"), [cmd substringFromIndex:5]);
    else if ([cmd isEqualToString:@"tab"]) ((void (*)(id, SEL))objc_msgSend)(list, sel_registerName("_tabKeyPressed"));
    else if ([cmd isEqualToString:@"applecancel"]) [MSSApple(list) setActive:NO];   // (as Apple ends its search after a sidebar row is picked)
    else if ([cmd isEqualToString:@"relayout"]) { MSSearchSidebarChanged(list); [list.view setNeedsLayout]; [list.view layoutIfNeeded]; }
    // dark / light / unstyle: this Settings window only, drawn dark or light (no setting is changed; unstyle = the device's own look again)
    else if ([cmd isEqualToString:@"dark"] || [cmd isEqualToString:@"light"] || [cmd isEqualToString:@"unstyle"]) {
        list.view.window.overrideUserInterfaceStyle = [cmd isEqualToString:@"dark"] ? UIUserInterfaceStyleDark : [cmd isEqualToString:@"light"] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified;
        MSSLog([NSString stringWithFormat:@"test: window style %ld", (long)list.view.window.overrideUserInterfaceStyle]);
    }
    // switch 0 / 1 / del: our own switch written as its Settings row writes it (del = never set again), then its notification
    else if ([cmd hasPrefix:@"switch "]) {
        NSString *v = [cmd substringFromIndex:7];
        CFPreferencesSetAppValue(CFSTR("sidebarSearch"), [v isEqualToString:@"del"] ? NULL : ([v boolValue] ? kCFBooleanTrue : kCFBooleanFalse), kMSSDomain);
        CFPreferencesAppSynchronize(kMSSDomain);
        notify_post(kMSSChanged);
    }
    else MSSLog(@"test: unknown command");
}
static void MSSTestPoll(void) {
    static time_t last = -1;   // (-1: the first look adopts a leftover command without running it)
    struct stat sb;
    if (access("/tmp/macsettings-debug", F_OK) != 0 || stat("/tmp/macsettings-searchtest", &sb) != 0) { if (last == -1) last = 0; return; }
    if (sb.st_mtime == last) return;
    BOOL first = last == -1;
    last = sb.st_mtime;
    if (first) return;
    NSString *cmd = [[NSString stringWithContentsOfFile:@"/tmp/macsettings-searchtest" encoding:NSUTF8StringEncoding error:nil] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *one in [cmd componentsSeparatedByString:@";"]) {   // (several in one write, run in order)
        NSString *c = [one stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (c.length) MSSTestCommand(c);
    }
}
#endif

%group MSSHooks
%hook PSUIPrefsListController
- (void)viewDidLayoutSubviews {
    %orig;
    MSSearchSidebarChanged((UIViewController *)self);   // (a narrow window collapses the sidebar into the page: the field follows the bar)
    MSSLayout((UIViewController *)self);
    MSSKeepTop((UIViewController *)self);
}
- (void)_tabKeyPressed {
    if (MSSFocus((UIViewController *)self)) return;
    %orig;
}
- (void)_upArrowKeyPressed {
    if (MSSMove((UIViewController *)self, NO)) return;   // (results shown: through them, not through the rows hidden under them)
    %orig;
}
- (void)_downArrowKeyPressed {
    if (MSSMove((UIViewController *)self, YES)) return;
    %orig;
}
- (void)continueSearchInSettingsWithTerm:(NSString *)term {
    if (MSSContinue((UIViewController *)self, term)) return;
    %orig;
}
- (NSArray *)keyCommands {
    NSArray *apple = %orig;
    return MSSKeyCommands((UIViewController *)self, apple);
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    gMSSUpdates++;
    %orig;
}
- (void)searchResultsCollectionViewController:(id)controller didSelectURL:(NSURL *)url {
    %orig;
    MSSPicked((UIViewController *)self, controller);
}
%new
- (void)msbd_searchFind:(UIKeyCommand *)command { MSSFocus((UIViewController *)self); }
%new
- (void)msbd_searchEscape:(UIKeyCommand *)command { MSSEscape((UIViewController *)self); }
%new
- (void)msbd_searchOpen:(UIKeyCommand *)command { MSSOpenHighlighted((UIViewController *)self); }
%end
// Apple ends its search (a sidebar row picked from the results, Apple ID sign-in, a PIN entered): ours ends with it. Only Apple's controller of the sidebar
// counts (MSSAppleEnded); every other search controller in Settings passes straight through.
%hook UISearchController
- (void)setActive:(BOOL)active {
    %orig;
    if (!active) MSSAppleEnded(self);
}
%end
%end

%ctor {
    gMSSOK = MSSCheck();
    if (!gMSSOK) { MSSLog([NSString stringWithFormat:@"check failed, no search field: %@", gMSSWhy]); return; }
    %init(MSSHooks);
    gMSSEnabled = MSSReadEnabled();
    int token = 0;
    notify_register_dispatch(kMSSChanged, &token, dispatch_get_main_queue(), ^(int t) {   // (the switch, from our Settings page in this same app)
        gMSSEnabled = MSSReadEnabled();
        UIViewController *list = gMSSCurrentList;
        MSSLog([NSString stringWithFormat:@"switch %@", gMSSEnabled ? @"on" : @"off"]);
        if (list) { MSSearchSidebarChanged(list); [list.view setNeedsLayout]; }
    });
    // Apple's search controller comes with the list's first asynchronous load (setupDaemonsIfNeeded), often just after the sidebar appeared.
    [[NSNotificationCenter defaultCenter] addObserverForName:@"SpotlightSearchControllerInitialized" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        UIViewController *list = [n.object isKindOfClass:gMSSList] ? n.object : gMSSCurrentList;
        MSSLog(@"Apple's search controller is ready");
        if (list) { MSSearchSidebarChanged(list); [list.view setNeedsLayout]; }
    }];
    MSSLog(@"check ok");
#if DEBUG
    static dispatch_source_t poll;
    poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(poll, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(poll, ^{ MSSTestPoll(); });
    dispatch_resume(poll);
#endif
}
