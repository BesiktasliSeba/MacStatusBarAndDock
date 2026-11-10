#!/bin/bash
# Mac test of sorting in Finder (1.8.4.2 item 4): the rules (common/FinderSort.h, test-findersort.c) and the wiring in SpringBoard (statusbar/
# Finder.h, StatusBar.x) and Settings (Root.plist): a list column's header sorts by it, again the other way round, with the chevron; View > Sort By
# (the menu bar's View menu, the window's menu on empty space) for the icons too; the choice kept per folder; Keep Folders on Top in Settings > Finder;
# sorting by size works out every folder's size and follows them as they come in, the first item on screen kept in its place.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/tfso" test-findersort.c && "$W/tfso" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
m() { awk -v h="$2" '!p && index($0, h) == 1 {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one method of a file, from its first line
H=../statusbar/Finder.h; X=../statusbar/StatusBar.x; C=../common/FinderSort.h; P=../statusbar/macstatusbarprefs/Resources/Root.plist
check "Finder includes the rules" "grep -q '#include \"../common/FinderSort.h\"' $H"
check "the listing: Date Created and Date Added read with the rest; each item's place in the folder's own order (None) and by name kept on it" \
  "fn $H 'static NSArray<DMFinderItem *> *DMFinderList(NSString *path, BOOL hidden, NSError **err) {' | grep -q 'NSURLIsSymbolicLinkKey, NSURLCreationDateKey, NSURLAddedToDirectoryDateKey\];' \
   && [ \$(fn $H 'static NSArray<DMFinderItem *> *DMFinderList(NSString *path, BOOL hidden, NSError **err) {' | grep -c 'it.created = v\[NSURLCreationDateKey\]; it.added = v\[NSURLAddedToDirectoryDateKey\];') = 3 ] \
   && fn $H 'static NSArray<DMFinderItem *> *DMFinderList(NSString *path, BOOL hidden, NSError **err) {' | awk '/\.order = \(NSInteger\)i;/{a=NR} /localizedStandardCompare:b.display/{b=NR} /\.nameRank = \(NSInteger\)i;/{c=NR} END{exit !(a && b && c && a < b && b < c)}'"
check "a window shows its folder in the folder's order: read when it shows a folder, applied to every listing" \
  "m $H '- (void)load:(NSString *)path {' | grep -q '_sort = DMFinderSortFor(path); \[self dm_showSort\];' \
   && m $H '- (void)setItems:(NSArray *)items error:(NSError *)err {' | grep -q '_all = DMFinderSorted(items ?: @\[\], _sort);' \
   && fn $H 'static NSArray<DMFinderItem *> *DMFinderSorted(NSArray<DMFinderItem *> *items, MSBDSortChoice c) {' | grep -q 'MSBDSortOrder(s, n, c, gFinderFoldersOnTop, order)'"
check "  ... names come ranked from the listing, kinds ranked as Finder compares names (no name compared again on the main thread)" \
  "fn $H 'static NSArray<DMFinderItem *> *DMFinderSorted(NSArray<DMFinderItem *> *items, MSBDSortChoice c) {' | grep -q 's\[i\].index = (long)it.order; s\[i\].nameRank = (long)it.nameRank;' \
   && fn $H 'static NSArray<DMFinderItem *> *DMFinderSorted(NSArray<DMFinderItem *> *items, MSBDSortChoice c) {' | grep -q 'localizedStandardCompare:b\]' \
   && fn $H 'static NSArray<DMFinderItem *> *DMFinderSorted(NSArray<DMFinderItem *> *items, MSBDSortChoice c) {' | grep -q 's\[i\].folder = it.dir && !it.package;'"
check "a click on a list column's header sorts by it (again: the other way round), the chevron in it" \
  "grep -q 'initWithTarget:self action:@selector(dm_headerTap:)\];' $H \
   && m $H '- (void)dm_headerTap:(UITapGestureRecognizer *)g {' | grep -q '\[self dm_setSort:MSBDSortClick(_sort, MSBDSortColumnKey((int)col))\];' \
   && m $H '- (void)dm_showSort {' | grep -q 'NSInteger on = MSBDSortChevronColumn(_sort);' \
   && m $H '- (void)dm_showSort {' | grep -q '_sort.ascending ? @\"chevron.up\" : @\"chevron.down\"' \
   && m $H '- (void)dm_showSort {' | grep -q 'h.accessibilityValue = active ? (_sort.ascending ? @\"Sorted ascending\" : @\"Sorted descending\") : nil;'"
check "  ... the headers keep their places (tags 21-24, the layout still skips only the line)" \
  "grep -q 'h.tag = 21 + hcol++;' $H && grep -q 'if (v.tag == 9) { v.frame = CGRectMake(0, hh - 0.5, w, 0.5); continue; }' $H"
check "the choice is kept per folder (Name A to Z not stored), every window showing the folder follows" \
  "m $H '- (void)dm_setSort:(MSBDSortChoice)c {' | grep -q 'DMFinderSortKeep(self.path, c);' \
   && m $H '- (void)dm_setSort:(MSBDSortChoice)c {' | grep -q 'isEqualToString:self.path\]) \[(DMFinderWindow \*)w dm_applySort:c\];' \
   && fn $H 'static void DMFinderSortKeep(NSString *folder, MSBDSortChoice c) {' | grep -q 'if (MSBDSortIsDefault(c) || !MSBDSortStore(c, buf, sizeof buf)) \[gFinderSortViews removeObjectForKey:folder\];' \
   && fn $H 'static void DMFinderSortKeep(NSString *folder, MSBDSortChoice c) {' | grep -q 'CFPreferencesSetValue(CFSTR(\"finderSortViews\")' \
   && fn $H 'static MSBDSortChoice DMFinderSortFor(NSString *folder) {' | grep -q 'return MSBDSortRead(s.UTF8String);'"
check "View > Sort By in the menu bar: every key, the folder's ticked, for the icons too" \
  "fn $X 'static void DMOpenFinderViewMenu(UIButton *btn) {' | grep -q 'initWithTitle:@\"Sort By\" enabled:NO handler:nil' \
   && fn $X 'static void DMOpenFinderViewMenu(UIButton *btn) {' | grep -q 'for (int k = 0; k < MSBD_SORT_MENU_COUNT; k++) {' \
   && fn $X 'static void DMOpenFinderViewMenu(UIButton *btn) {' | grep -q 'DMFinderRow(@(MSBDSortTitle(key)), nil, f != nil, ^(DMFinderWindow \*w) { \[w dm_sortBy:key\]; });' \
   && fn $X 'static void DMOpenFinderViewMenu(UIButton *btn) {' | grep -q 'r.checked = f != nil && now.key == key;' \
   && fn $X 'static void DMOpenFinderViewMenu(UIButton *btn) {' | grep -q 'Hide Hidden Files' \
   && m $H '- (void)dm_sortBy:(int)key {' | grep -q 'dm_setSort:MSBDSortPick(_sort, key)'"
check "  ... and the Mac's Sort By submenu in the window's menu on empty space, its choice ticked" \
  "grep -q 'menuWithTitle:@\"Sort By\" image:\[UIImage systemImageNamed:@\"arrow.up.arrow.down\"\]' $H \
   && grep -q 's.state = now.key == key ? UIMenuElementStateOn : UIMenuElementStateOff;' $H \
   && fn $H 'static NSArray *DMFinderMenuRows(UIMenu *menu, UIControl *o) {' | grep -q 'if (a.state == UIMenuElementStateOn) r.checked = YES;'"
check "Keep Folders on Top: Settings > Finder, off by default, right after Finder's own switch; posted as Finder's settings" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('FINDER_FOLDERS_ON_TOP'); s=it[i]; sys.exit(0 if s['key']=='finderFoldersOnTop' and s['default'] is False and s['cell']=='PSSwitchCell' and s['label']=='Keep Folders on Top' and s['defaults']=='com.besiktasliseba.macstatusbar' and s['PostNotification']=='com.besiktasliseba.macstatusbar.finder.pref' and ids[i-1]=='FINDER' and ids[i-2]=='FINDER_GROUP' else 1)\""
check "  ... SpringBoard reads it with Finder's settings and sorts every window again" \
  "fn $H 'static void DMFinderSortReadPrefs(void) {' | grep -q 'CFPreferencesCopyValue(CFSTR(\"finderFoldersOnTop\"), MSB_DOMAIN' \
   && fn $X 'static void DMFinderApplyPref(void) {' | awk '/DMFinderSortChanged\(\);/{a=NR} /if \(on == gFinderOn\) return;/{b=NR} END{exit !(a && b && a < b)}' \
   && fn $H 'static void DMFinderSortChanged(void) {' | grep -q '\[(DMFinderWindow \*)w dm_sortAgain\];'"
check "Size: a folder's worked-out size (never a guess), every folder of the window asked, and kept in the line while scrolled away" \
  "fn $H 'static BOOL DMFinderSortSize(DMFinderItem *it, unsigned long long *bytes) {' | grep -q '\[kept\[@\"s\"\] intValue\] != MSBD_FS_DONE) return NO;' \
   && m $H '- (void)dm_sortSizesSoon {' | grep -q 'DMFinderSizeAsk(it.path, s, NO);' && m $H '- (void)setItems:(NSArray *)items error:(NSError *)err {' | grep -q '\[self dm_sortSizesSoon\];' \
   && m $H '- (void)tableView:(UITableView *)tv didEndDisplayingCell:' | grep -q 'if (!shown) DMFinderSizeCancel(self, gone);' \
   && m $H '- (void)tableView:(UITableView *)tv didEndDisplayingCell:' | grep -q 'NSString \*gone = objc_getAssociatedObject(cell, kFinderCellSizePathKey);' && m $H '- (void)tableView:(UITableView *)tv didEndDisplayingCell:' | grep -q 'if (tv == _list && _sort.key != MSBD_SORT_SIZE) {' \
   && grep -q '|| _sort.key == MSBD_SORT_SIZE)) DMFinderSizeAsk(path, self, NO);' $H"
check "  ... sorted again as sizes come in (once for several), never under a scroll, a rename, a band or a drag" \
  "grep -q 'if (_sort.key == MSBD_SORT_SIZE) { if (!_sizeArrived) _sizeArrived = \[NSMutableSet set\]; \[_sizeArrived addObject:path\]; \[self dm_resortSoon\]; }   // (sorted by size: the folder takes its place' $H \
   && m $H '- (void)dm_resortSoon {' | grep -q '\[s dm_resortKeepingPlace:YES\];   // (any order' \
   && m $H '- (void)dm_resortSoon {' | grep -q 'if (_sortPending) return;' \
   && m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q 'if (keep && (sv.isTracking || sv.isDecelerating)) { \[self dm_resortSoon\]; return; }' \
   && m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q 'if (keep && (_renameField || _band || _dragLifted)) { \[self dm_resortSoon\]; return; }'"
check "  ... the first item on screen stays where it was (the selection is by path: it stays)" \
  "m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q 'anchor = _items\[first.item\].path; dy = \[self dm_rectOfIndex:first.item\].origin.y - sv.contentOffset.y;' \
   && m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q 'sv.contentOffset = CGPointMake(sv.contentOffset.x, MIN(MAX(\[self dm_rectOfIndex:i\].origin.y - dy, top), maxY));' \
   && m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q 'if (\[sorted isEqualToArray:_all\]) { \[_sizeArrived removeAllObjects\]; return; }' \
   && m $H '- (void)dm_resortKeepingPlace:(BOOL)keep {' | grep -q '!\[_sizeArrived containsObject:_items\[ip.item\].path\]) { first = ip; break; }'"
check "  ... leaving Sort by Size: the window's folders leave the walking line, before the reload's rows ask again (Get Info's stay)" \
  "m $H '- (void)dm_applySort:(MSBDSortChoice)c {' | grep -q 'if (leftSize) DMFinderSizeCancelRows(self);' \
   && fn $H 'static void DMFinderSizeCancelRows(id owner) {' | grep -q '!\[a\[@\"i\"\] boolValue\]'"
check "the size rows still ask as before (only while the Size column shows)" \
  "m $H '- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:' | grep -q 'if (it.dir && cols.size >= 0 && MSBDFolderSizeWanted(it.dir, it.alias, it.locked, it.cloud) && !\[_sizeChecked containsObject:it.path\]) DMFinderSizeAsk(it.path, self, NO);'"
check "Date Last Opened is not offered (iPadOS keeps no such date)" "! grep -q '\"Date Last Opened\"' $C && ! grep -q 'Last Opened' $X"
check "the debug command (sort:<key>[-]): debug builds only" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /isEqualToString:@\"sort\"\]/{f=1; exit !d} END{if (!f) exit 1}' $H"
check "no em dash and no \"MacDock\" in the feature's files and words" \
  "! grep -q \$'\\xe2\\x80\\x94' $C test-findersort.c test-findersort.sh && ! grep -q 'MacDock' $C \
   && ! grep 'Keep Folders on Top' $P | grep -q \$'\\xe2\\x80\\x94' && ! m $H '- (void)dm_showSort {' | grep -q \$'\\xe2\\x80\\x94'"
[ $fails = 0 ] && echo "test-findersort: all checks pass" || { echo "test-findersort: checks FAILED"; exit 1; }
