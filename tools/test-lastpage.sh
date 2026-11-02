#!/bin/bash
# Mac test of the App Library's last page (KT, 1.7.8 item 7): swiping past the last Home Screen page no longer opens the App Library unless switched on
# (dock/Dock.x: the root folder's trailing page left out of its page count and of its index, dock/LastPageRule.h), the switch in the Home Screen
# page's own group next to Apple's App Library rows (dock/dockmagnificationsettings/DockSettingsRow.x), and the Settings search's row
# (common/TweakSpotlight.h). As built. test-lastpage.c runs the rule against iPadOS's page arithmetic (15-18, read from SpringBoardHome),
# including Edit Home Screen on the last page (1.7.8 regression R-8: with the count alone, 15-17 moved to edit mode's empty page).
set -e
cd "$(dirname "$0")"
K=../dock/Dock.x; R=../dock/dockmagnificationsettings/DockSettingsRow.x; T=../common/TweakSpotlight.h; L=../dock/LastPageRule.h
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/tlp" test-lastpage.c && "$W/tlp" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnk() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$K"; }
check "off unless switched on, for every user: never set, or anything but a boolean true, is off" \
  "grep -q '^static BOOL    gLastPageOpensLibrary = NO;' $K && grep -q 'gLastPageOpensLibrary = lpl && CFGetTypeID(lpl) == CFBooleanGetTypeID() && CFBooleanGetValue(lpl);' $K && grep -q 'DMCopyPref(CFSTR(\"lastPageOpensLibrary\"))' $K"
check "the trailing page leaves the page count only while off, and only when every trailing page is the App Library's" \
  "fnk 'static BOOL DMTrailingLeftOut(id rootFolderView, unsigned long long iosCount) {' | grep -q 'return DMLastPageMayLeaveOut(iosCount, gLastPageOpensLibrary) && DMTrailingIsLibraryOnly(rootFolderView);' \
   && grep -q 'static inline int DMLastPageMayLeaveOut(unsigned long long iosCount, int switchedOn) { return iosCount != 0 && !switchedOn; }' $L \
   && fnk 'static unsigned long long DMTrailingPages(id self, SEL _cmd) {' | grep -q 'BOOL out = DMTrailingLeftOut(self, n);' \
   && fnk 'static unsigned long long DMTrailingPages(id self, SEL _cmd) {' | grep -q 'return DMLastPageCount(n, out);' \
   && grep -q 'static inline unsigned long long DMLastPageCount(unsigned long long iosCount, int leftOut) { return leftOut ? 0 : iosCount; }' $L \
   && fnk 'static BOOL DMTrailingIsLibraryOnly(id rootFolderView) {' | grep -q 'for (id vc in pages) if (!\\[vc isKindOfClass:gDMLibraryPageClass\\]) return NO;' \
   && fnk 'static BOOL DMTrailingIsLibraryOnly(id rootFolderView) {' | grep -q 'if (!pages.count) return NO;'"
check "  ... and of its index (R-8): -trailingCustomViewPageIndex says no trailing page (NSIntegerMax) while the page is left out, from the same test as the count -- 15-17 work it out from the trailing view, not the count" \
  "fnk 'static long long DMTrailingPageIndex(id self, SEL _cmd) {' | grep -q 'BOOL out = DMTrailingLeftOut(self, o_DMTrailingPages(self, gDMTrailingCountSel));' \
   && fnk 'static long long DMTrailingPageIndex(id self, SEL _cmd) {' | grep -q '^    if (i == LLONG_MAX) return i;' \
   && fnk 'static long long DMTrailingPageIndex(id self, SEL _cmd) {' | tail -2 | grep -q '^    return DMLastPageIndex(i, out);' \
   && grep -q 'static inline long long DMLastPageIndex(long long iosIndex, int leftOut) { return leftOut ? LLONG_MAX : iosIndex; }' $L \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'gDMTrailingCountSel = count;'"
check "  ... shape checks before the hooks: SBRootFolderView's count (15-17 and 18 names, Q16@0:8), its index (q16@0:8), its trailing pages' getter (@16@0:8), the page's class -- else iPadOS's own page; the count and the index hooked together, never one alone" \
  "fnk 'static void DMLastPageInit(void) {' | grep -q 'for (NSString \\*name in @\\[@\"_trailingCustomPageCount\", @\"trailingCustomPageCount\"\\])' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'strcmp(method_getTypeEncoding(m), \"Q16@0:8\")' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'for (NSString \\*name in @\\[@\"trailingCustomViewControllers\", @\"trailingCustomViewController\"\\])' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'strcmp(method_getTypeEncoding(m), \"@16@0:8\")' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'SEL index = NSSelectorFromString(@\"trailingCustomViewPageIndex\");' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'else if (!im || strcmp(method_getTypeEncoding(im), \"q16@0:8\")) why = ' \
   && fnk 'static void DMLastPageInit(void) {' | awk '/if \\(why\\) \\{/{a=NR} /MSHookMessageEx\\(view, count, \\(IMP\\)DMTrailingPages, \\(IMP \\*\\)&o_DMTrailingPages\\);/{b=NR} /MSHookMessageEx\\(view, index, \\(IMP\\)DMTrailingPageIndex, \\(IMP \\*\\)&o_DMTrailingPageIndex\\);/{c=NR} END{exit !(a && b > a && c == b + 1)}' \
   && grep -q 'objc_getClass(\"SBHLibraryOverscrollViewController\")' $K"
check "  ... installed after the switch is read; a change lays the Home Screen's pages out at once (no respring)" \
  "awk '/^%ctor \\{/{f=1} f&&/DMLoadPrefs\\(\\);/&&!a{a=NR} f&&/DMLastPageInit\\(\\);/{b=NR} END{exit !(a && b > a)}' $K \
   && fnk 'static void DMPrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n,' | grep -q 'if (lastPage != gLastPageOpensLibrary) DMLastPageApply(@\"switched in Settings\");' \
   && fnk 'static void DMLastPageApply(NSString *why) {' | grep -q '\\[v setNeedsLayout\\]; \\[v layoutIfNeeded\\];'"
check "only the page: the App Library's other ways (its Dock icon, the swipe down, search, Spotlight) are never touched by this switch" \
  "! grep -n 'gLastPageOpensLibrary' $K | grep -v -E 'static BOOL    gLastPageOpensLibrary|gLastPageOpensLibrary = lpl|lastPageOpensLibrary=%d|BOOL lastPage = gLastPageOpensLibrary|lastPage != gLastPageOpensLibrary|DMTrailingPages|gLastPageOpensLibrary \\? @|if \\(!gLastPageOpensLibrary\\) dispatch_async|return DMLastPageMayLeaveOut\\(iosCount, gLastPageOpensLibrary\\) && DMTrailingIsLibraryOnly\\(rootFolderView\\);|if \\(presented && !gLastPageOpensLibrary\\) \\{' | grep -q ."
check "  ... a fling from the page before the last (its scroll's target the trailing page's) too: the icon manager's overscroll library is presented only while switched on, its dismissal always goes on" \
  "fnk 'static void DMOverscrollLibrary(id self, SEL _cmd, BOOL presented) {' | grep -q '^    if (presented && !gLastPageOpensLibrary) {' \
   && fnk 'static void DMOverscrollLibrary(id self, SEL _cmd, BOOL presented) {' | tail -2 | grep -q '^    o_DMOverscrollLibrary(self, _cmd, presented);' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'BOOL gate = om && !strcmp(method_getTypeEncoding(om), \"v20@0:8B16\");' \
   && fnk 'static void DMLastPageInit(void) {' | grep -q 'if (gate) MSHookMessageEx(mgr, NSSelectorFromString(@\"_updateOverscrollModalLibraryForScrollToPresented:\"), (IMP)DMOverscrollLibrary, (IMP \\*)&o_DMOverscrollLibrary);'"
check "  ... the modal presenter (the Dock icon, the swipe down, search) never gated: hooked only in debug builds, to log who presents" \
  "fnk 'static void DMLastPageInit(void) {' | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /presentLibraryWithAnimation:completion:.*MSHookMessageEx|MSHookMessageEx.*presentLibraryWithAnimation:completion:/{if (!d) bad=1; n++} END{exit !(n == 1 && !bad)}' \
   && fnk 'static void DMDbgPresentLib(id self, SEL _cmd, BOOL animated, id completion) {' | grep -q '^    o_DMDbgPresentLib(self, _cmd, animated, completion);' \
   && ! fnk 'static void DMDbgPresentLib(id self, SEL _cmd, BOOL animated, id completion) {' | grep -q 'return;'"
check "Settings: the switch in the Home Screen group, next to Apple's App Library rows, off by default, applied at once; the group's footer says it" \
  "grep -q 'DMHSSwitch(@\"Swipe Past Last Page Opens App Library\", @\"MSBD_LAST_PAGE_LIBRARY\", @\"com.besiktasliseba.dockmagnification\", @\"lastPageOpensLibrary\", NO, NO, @\"com.besiktasliseba.dockmagnification/prefsChanged\")' $R \
   && grep -q 'Without Swipe Past Last Page, the Home Screen' $R && grep -q 'if (\\[ident isEqualToString:@\"APP_DOWNLOADS_GO_TO\"\\]) return i;' $R"
check "  ... on 17/18 (the group on our Dock page) its footer says where the App Library's own options are: Apple's Home Screen & App Library" \
  "awk '/\\+ \\(NSArray \\*\\)msbdHomeScreenSpecifiersForOwnPage \\{/{f=1} f&&/The App Library.s own options are in Settings > Home Screen & App Library./{print \"ok\"; exit} f&&/^}/{exit}' $R | grep -q ok"
check "the Settings search finds it, at its row: Apple's Home Screen page on 15/16, our Dock page's Home Screen group on 17/18" \
  "grep -q 'c.ownRows = MTSOwnRows();' $T && grep -q 'NSString \\*pane = os >= 17 ? @\"DOCK_MAGNIFICATION\" : @\"HOME_SCREEN_DOCK\"' $T && grep -q '@\"row\": @\"MSBD_LAST_PAGE_LIBRARY\", @\"title\": @\"Swipe Past Last Page Opens App Library\"' $T"
check "  ... only while the Dock part runs (review m1): no row of ours in the index unless MSBDMacDockActive(), the check its page builds the row by (MacDock off, an untested iPadOS without Enable Anyway: no result for a page without the row)" \
  "awk '/^static NSArray<NSDictionary \\*> \\*MTSOwnRows\\(void\\) \\{/{f=1; n=0} f{n++} f&&n==2&&/^    if \\(!MSBDMacDockActive\\(\\)\\) return @\\[\\];/{ok=1} f&&/^}/{exit} END{exit !ok}' $T \
   && awk '/^static NSArray \\*DMHSSpecifiers\\(void\\) \\{/{f=1} f&&/BOOL dock = MSBDMacDockActive\\(\\)/{a=1} f&&/if \\(dock\\) \\{/{b=1} f&&b&&/MSBD_LAST_PAGE_LIBRARY/{c=1} f&&/^}/{exit} END{exit !(a && b && c)}' $R \
   && grep -q '^#import \"LineSwitch.h\"' $T && grep -q '^#import \"MacDockActive.h\"' $T \
   && awk '/^#import \"LineSwitch.h\"/{a=NR} /^#import \"MacDockActive.h\"/{b=NR} END{exit !(a && b > a)}' $T"
check "  ... its page's name on 15 is the one shown then: Apple's Home Screen & Dock is called Home Screen while the Dock part runs (its row and title), and the row is there only then" \
  "grep -q 'os == 16 ? @\"Home Screen & Multitasking\" : @\"Home Screen\";' $T \
   && awk '/^static void DMRenameHomeScreenRow\\(/{f=1} f&&/if \\(!MSBDMacDockActive\\(\\)\\) return;/{a=1} f&&/hasSuffix:@\" & Dock\"/{b=1} f&&/^}/{exit} END{exit !(a && b)}' $R \
   && grep -q 'if (\\[t hasSuffix:@\" & Dock\"\\]) self.title = \\[t substringToIndex:t.length - 7\\];' $R"
check "  ... from Dock.x's constructor (inside SpringBoard's start): classes only, nothing of SpringBoard's asked for (its icon controller does not exist yet)" \
  "! fnk 'static void DMLastPageInit(void) {' | grep -q -E 'DMRootFolderView|DMLastPageApply|sharedInstance|dispatch_async'"
[ $fails = 0 ] && echo "test-lastpage: all checks pass" || { echo "test-lastpage: checks FAILED"; exit 1; }
