#!/bin/bash
# Mac test of folder sizes in Finder (1.8.4.2 item 1): the walk and the rules (common/FolderSize.h, test-foldersize.c, on real folders made here)
# and the wiring in SpringBoard (statusbar/Finder.h): one folder at a time on a queue of its own, never the main thread; the list's rows ask,
# Get Info goes first; kept with the folder's date, checked again at each listing; dropped and stopped when the window closes or shows another
# folder, a row scrolled away leaves the line.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'chmod -R u+rwx "$W" 2>/dev/null; rm -rf "$W"' EXIT
fails=0
mkdir "$W/tree"
clang -O0 -Wall -o "$W/tfs" test-foldersize.c && "$W/tfs" "$W/tree" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
m() { awk -v h="$2" '!p && index($0, h) == 1 {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one method of a file, from its first line
H=../statusbar/Finder.h; C=../common/FolderSize.h
check "the walk: links never followed, the folder's volume only, the folder itself never a link" \
  "grep -q 'fts_open(roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, NULL)' $C && grep -q 'lstat(path, &st) != 0 || !S_ISDIR(st.st_mode)' $C"
check "Finder includes the rules" "grep -q '#include \"../common/FolderSize.h\"' $H"
check "one at a time, on a serial queue of its own at utility priority, never the main thread" \
  "fn $H 'static void DMFinderSizeNext(' | grep -q 'if (gFinderSizeWalking || !gFinderSizeLine.count) return;' \
   && fn $H 'static void DMFinderSizeNext(' | grep -q 'dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)' \
   && fn $H 'static void DMFinderSizeNext(' | grep -q 'dispatch_async(q, ^{' \
   && [ \$(grep -c 'MSBDFolderSizeWalk(' $H) = 1 ]"
check "  ... the walk with the default caps and the stop flag; kept unless stopped; the next one after" \
  "fn $H 'static void DMFinderSizeNext(' | grep -q 'MSBDFolderSizeWalk(path.fileSystemRepresentation, 0, 0, &gFinderSizeStop)' \
   && fn $H 'static void DMFinderSizeNext(' | grep -q 'if (state != MSBD_FS_CANCELLED && got != kept) {' && fn $H 'static void DMFinderSizeNext(' | grep -q 'DMFinderSizeDone(path, state, owner);' \
   && fn $H 'static void DMFinderSizeDone(' | grep -q 'if (state == MSBD_FS_CANCELLED && (__bridge const void \*)w == owner) continue;'"
check "  ... kept by the folder's date: walked only when it changed (one stat on the queue)" \
  "fn $H 'static void DMFinderSizeNext(' | grep -q 'MSBDFolderSizeFresh(kept != nil, \[kept\[@\"d\"\] doubleValue\], date, \[kept\[@\"at\"\] doubleValue\], now, kMSBDFolderSizeMaxAge)'"
check "the list's rows ask (only folders it works out, only while the Size column shows), once per listing" \
  "m $H '- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:' | grep -q 'if (it.dir && cols.size >= 0 && MSBDFolderSizeWanted(it.dir, it.alias, it.locked, it.cloud) && !\[_sizeChecked containsObject:it.path\]) DMFinderSizeAsk(it.path, self, NO);' \
   && m $H '- (void)setItems:(NSArray *)items error:(NSError *)err {' | grep -q '\[_sizeChecked removeAllObjects\];'"
check "  ... \"--\" until it is in: the Size column's text is the rule's" \
  "fn $H 'static NSString *DMFinderSizeText(' | grep -q 'MSBDFolderSizeShow(MSBDFolderSizeWanted(it.dir, it.alias, it.locked, it.cloud)' && grep -q 'static NSString \*DMFinderSize(DMFinderItem \*it) { return DMFinderSizeText(it, NO); }' $H"
check "  ... a row scrolled away leaves the line; the window closing or showing another folder drops its asks and stops its walk" \
  "m $H '- (void)tableView:(UITableView *)tv didEndDisplayingCell:' | grep -q 'if (!shown) DMFinderSizeCancel(self, gone);' \
   && grep -q '^- (void)close { \[self dm_endRename:NO\]; DMFinderSizeCancel(self, nil);' $H \
   && m $H '- (void)load:(NSString *)path {' | grep -q 'if (!\[path isEqualToString:self.path\]) DMFinderSizeCancel(self, nil);' \
   && fn $H 'static void DMFinderSizeCancel(' | grep -q 'if (!path && gFinderSizeWalking && gFinderSizeWalkingOwner == o) gFinderSizeStop = 1;'"
check "Get Info: shown at once, \"Calculating…\" until the size is in (first in line), then the sheet's message shows it" \
  "m $H '- (void)getInfo:(DMFinderItem *)it {' | grep -q 'DMFinderSizeAsk(it.path, self, YES);' && m $H '- (void)getInfo:(DMFinderItem *)it {' | grep -q 'showInfo:it sizeText:DMFinderSizeText(it, YES)' \
   && fn $H 'static void DMFinderSizeAsk(' | grep -q 'if (info) \[gFinderSizeLine insertObject:ask atIndex:0\]; else \[gFinderSizeLine addObject:ask\];' \
   && grep -q 'm.text = \[text stringByReplacingOccurrencesOfString:@\"\\\\x01\" withString:DMFinderSizeText(it, YES)\];' $H"
check "  ... asks kept per folder and window (one window's row scrolling away never drops another's), and an ask during a stopped walk is kept" \
  "fn $H 'static void DMFinderSizeAsk(' | grep -q 'isEqualToString:path\] && \[gFinderSizeLine\[k\]\[@\"o\"\] pointerValue\] == (__bridge const void \*)owner) {' \
   && fn $H 'static void DMFinderSizeAsk(' | grep -q 'if (\[gFinderSizeWalking isEqualToString:path\] && !gFinderSizeStop) return;'"
check "  ... Get Info on a folder always waits for the new size (a kept one may be old)" \
  "m $H '- (void)showInfo:(DMFinderItem *)it sizeText:(NSString *)sizeText {' | grep -q 'if (!MSBDFolderSizeWanted(it.dir, it.alias, it.locked, it.cloud)) return;'"
check "  ... no walk of its own on a global queue any more (the old 50,000-entry enumerator)" "! grep -q 'enumeratorAtPath:it.path' $H"
check "the release build carries the feature (its marker)" "fn $H 'static void DMFinderSizeAsk(' | grep -q 'DM_FEATURE_MARK(\"finder-folder-sizes\");'"
check "no em dash in the feature's files" "! grep -q \$'\\xe2\\x80\\x94' $C test-foldersize.c test-foldersize.sh && ! fn $H 'static NSString *DMFinderSizeText(' | grep -q \$'\\xe2\\x80\\x94'"
[ $fails = 0 ] && echo "test-foldersize: all checks pass" || { echo "test-foldersize: checks FAILED"; exit 1; }
