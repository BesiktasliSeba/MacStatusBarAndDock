#!/bin/bash
# Mac test of the Home Screen folders in the Finder menu (1.7.9 item 3): the record and the rows (common/FinderFolders.h, test-finderfolders.m) and
# the wiring in SpringBoard -- the folder's Haptic Touch row (statusbar/FinderFolders.h, from the icon menu hook in StatusBar.x), the Finder menu's
# rows after the jailbreak folder, one opener for both.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -fobjc-arc -Wall -framework Foundation -o "$W/tff" test-finderfolders.m && "$W/tff" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
H=../statusbar/FinderFolders.h; X=../statusbar/StatusBar.x
check "a folder's identity is its folder's -uniqueIdentifier (the one IconState keeps), read only with the types read (@@:)" \
  "fn $H 'static NSString *DMFFUID(' | grep -q 'if (!DMFFHas(folder, @\"uniqueIdentifier\", \"@@:\")) return nil;'"
check "the record: our domain's finderFolders, read strictly, written and synchronized, removed when empty" \
  "fn $H 'static NSArray<NSString *> *DMFFRecord(' | grep -q 'CFPreferencesCopyValue(CFSTR(MSBD_FINDER_FOLDERS_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \
   && fn $H 'static void DMFFSetAttached(' | grep -q 'after.count ? (__bridge CFPropertyListRef)after : NULL' && fn $H 'static void DMFFSetAttached(' | grep -q 'CFPreferencesSynchronize(MSB_DOMAIN'"
check "  ... a deleted folder is dropped only when the Home Screen's model is there (every folder: hidden pages and the Dock too)" \
  "fn $H 'static void DMFFSetAttached(' | grep -q 'NSSet \\*known = DMFFModelReady() ? present : nil;' && fn $H 'static NSArray<NSDictionary \\*> \\*DMFFFolders(' | grep -q 'DMCall(DMCall(root, @\"dock\"), @\"icons\")'"
check "the row in a folder's menu: folders on a page or in the Dock, not the App Library, not the jailbreak folder (listed by itself)" \
  "fn $H 'static id DMFFMenuFolder(' | grep -q '\\[loc containsString:@\"AppLibrary\"\\]' && fn $H 'static id DMFFMenuFolder(' | grep -q 'isEqualToString:@\"SBIconLocationRoot\"\\] && !\\[loc containsString:@\"Dock\"\\]' \
   && fn $H 'static id DMFFMenuFolder(' | grep -q 'DMFFUID(DMFindJailbreakFolderIcon(NULL))'"
check "  ... from the icon menu hook, whatever the menu's look (Mac or Stock): the action provider wrapped, the row put in" \
  "fn $X '- (id)contextMenuInteraction:(id)interaction configurationForMenuAtLocation:(CGPoint)location {' | grep -q 'id folder = DMFFMenuFolder((UIView \\*)self);' \
   && fn $X '- (id)contextMenuInteraction:(id)interaction configurationForMenuAtLocation:(CGPoint)location {' | grep -q 'm = DMFFMenuWithRow(m, f);'"
check "  ... its title from the record (Show / Remove), and a tap flips it" \
  "fn $H 'static UIMenu *DMFFMenuWithRow(' | grep -q 'MSBDFinderFolderMenuTitle(attached)' && fn $H 'static UIMenu *DMFFMenuWithRow(' | grep -q 'DMFFSetAttached(uid, !attached);'"
check "the Finder menu: the attached folders' rows right after the jailbreak folder, in their own section only without it" \
  "fn $X 'static void DMOpenFinderMenu(' | grep -q 'NSArray<DMRow \\*> \\*folders = DMFFRows(jbFolder);' && fn $X 'static void DMOpenFinderMenu(' | grep -q 'for (NSArray \\*section in @\\[apps, jailbreak, folders\\])' \
   && fn $X 'static void DMOpenFinderMenu(' | grep -q 'if (items.count && !(section == folders && jbFolder)) \\[items addObject:\\[NSNull null\\]\\];'"
check "  ... a row opens its folder found again by its identity, the way the jailbreak folder's row does (one opener)" \
  "fn $H 'static NSArray<DMRow \\*> \\*DMFFRows(' | grep -q 'DMOpenHomeFolder(icon, @\"an attached folder\");' && grep -q '^static void DMOpenJailbreakFolder(void) { DMOpenHomeFolder(DMFindJailbreakFolderIcon(NULL), @\"the jailbreak folder\"); }' $X"
check "  ... a folder in the Dock opens from the Dock (the floating Dock's own call), one on a page after its page is shown" \
  "fn $X 'static void DMOpenHomeFolder(' | grep -q 'directlyContainsIcon:\"' && fn $X 'static void DMOpenHomeFolder(' | grep -q '{ DMFFOpenDockFolder(icon, what); return; }' \\
   && fn $H 'static BOOL DMFFOpenDockFolder(' | grep -q 'DMFFHas(ctrl, @\"presentFolderForIcon:location:animated:completion:\", \"v@:@@B@?\")' \\
   && fn $X 'static void DMOpenHomeFolder(' | grep -q 'objc_msgSend)(mgr, open, icon, @\"SBIconLocationRoot\", YES, nil);'"
check "  ... the folder's row at the end of its menu, a section of its own, once (iPadOS's rows have no fixed identifiers to place it by)" \
  "fn $H 'static UIMenu *DMFFMenuWithRow(' | grep -q 'identifier:@\"com.besiktasliseba.finderfolders\" options:UIMenuOptionsDisplayInline children:@\[ours\]' \
   && fn $H 'static UIMenu *DMFFMenuWithRow(' | grep -q 'return \[m menuByReplacingChildren:\[m.children arrayByAddingObject:section\]\];'"
check "a Home Screen folder open: the windows step aside as for the icon menus (the engines' windows, Stage Manager's, ours), every way it opens" \
  "fn $X 'static void DMSyncWindowFade(' | grep -q 'BOOL want = DMLibraryVisible() || gHomeMenuOpen || folder;' && fn $X 'static void DMSyncWindowFade(' | grep -q 'BOOL folder = DMHomeFolderShowing();' \
   && grep -q '(DMLibraryVisible() || gHomeMenuOpen || folder) && !DMSwitcherVisible()' ../statusbar/SMDesktop.h \
   && fn $X 'static void DMNativeTick(' | grep -q 'BOOL away = DMLibraryVisible() || gHomeMenuOpen || DMHomeFolderShowing() || DMSwitcherVisible()'"   # (until it closes or an app comes to the front: test-homefolder.sh)
check "the release build carries the feature (its marker in the record's write)" "fn $H 'static void DMFFSetAttached(' | grep -q 'DM_FEATURE_MARK(\"finder-menu-folders\");'"
check "the debug triggers are compiled into debug builds only" "awk '/^#if DEBUG/{d=1} /DMFFTrigger\\(NSString \\*cmd\\)/{print d} /^#endif/{d=0}' $H | grep -q '^1$'"
check "no em dash in the feature's files" "! grep -q \$'\\xe2\\x80\\x94' $H ../common/FinderFolders.h test-finderfolders.m test-finderfolders.sh"
[ $fails = 0 ] && echo "test-finderfolders: all checks pass" || { echo "test-finderfolders: checks FAILED"; exit 1; }
