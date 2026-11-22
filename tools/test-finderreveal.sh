#!/bin/bash
# test-finderreveal.sh: a Finder window's selection as it is SHOWN (1.8.8.2, B73). 1.8.8.1's device pass: Show in Enclosing Folder from the Dock's
# Downloads stack opened a new Finder window on the folder, but the item was not highlighted (with that window already open it was). UIKit drops the
# list's and the icons' own selection (the highlight) for every row it reloads; a new window's first listing could land before its first layout,
# whose reload took the highlight away, and the same followed a resize and a thumbnail coming in. See test-finderreveal.m: the real code is cut
# out of statusbar/Finder.h (FR_FINDER_H: another copy, e.g. the code before the fix) and run on the Mac (Mac Catalyst) on real UIKit tables and
# collection views. Also read: every reload of the list and the icons shows the selection again, the listing's hop to the main queue (the order
# Show in Enclosing Folder relies on), NativeWindow.h's -show (FR_NATIVE_H; the harness's model of it), and the crash map's place of the new
# methods. Then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
F0=${FR_FINDER_H:-../statusbar/Finder.h}; N0=${FR_NATIVE_H:-../statusbar/NativeWindow.h}; R0=crashmap-rules.txt

# One method of the Finder window (win: inside "@implementation DMFinderWindow {" only) or one function of the file, from its first line: to the
# line that closes it, or that first line alone when the method is written on one line.
fn() {
  awk -v h="$2" -v win="$3" '
    /^@implementation DMFinderWindow \{/ { inwin = 1 }
    inwin && /^@end/ { inwin = 0 }
    !f && index($0, h) == 1 && (win == "" || inwin) { f = 1; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); print; if (o > 0 && o == c) exit; next }
    f { print }
    f && /^[}]/ { exit }' "$1"
}
M=('- (void)go:(NSString *)path {' '- (void)load:(NSString *)path {' '- (void)dm_list {' '- (void)setItems:(NSArray *)items error:(NSError *)err {'
   '- (void)applySearch {' '- (void)reload {' '- (void)refresh {' '- (void)layoutSubviews {' '- (void)dm_showSelection {'
   '- (void)dm_selectPathsWhenListed:(NSArray<NSString *> *)paths {' '- (void)dm_renameWhenListed:(NSString *)path {'
   '- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {' '- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {'
   '- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s {'
   '- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {'
   '- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {'
   '- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {'
   '- (void)dm_setSelection:(NSArray<NSString *> *)paths anchor:(NSString *)anchor {' '- (DMFinderItem *)dm_selectedItem {'
   '- (NSArray<DMFinderItem *> *)dm_selectedItems {' '- (void)dm_scrollToPath:(NSString *)path {' '- (BOOL)dm_beginInlineRename:(NSString *)path {')
M_NEW=('- (void)dm_reload:(UIScrollView *)v rows:(NSArray<NSIndexPath *> *)rows {' '- (void)dm_showSelectionAt:(NSInteger)i in:(UIScrollView *)v {')
FUN=('static DMFinderWindow *DMFinderFront(void) {' 'static void DMFinderOpen(NSString *path, BOOL newWindow) {' 'static void DMFinderStackReveal(NSString *path, BOOL rename) {')
COLS='static DMFinderCols DMFinderColumns(CGFloat w) {'

run() {   # $1 Finder.h, $2 NativeWindow.h, $3 work dir, $4 quiet; the number of failed checks (99: not built)
  local F=$1 N=$2 d=$3 q=$4 h out n=0 s=0 body
  mkdir -p "$d"
  for h in "${M[@]}"; do [ -n "$(fn "$F" "$h" win)" ] || { echo "FAIL  $F: no Finder window method \"$h\""; return 99; }; done
  for h in "${FUN[@]}" "$COLS"; do [ -n "$(fn "$F" "$h")" ] || { echo "FAIL  $F: no function \"$h\""; return 99; }; done
  { for h in "${M[@]}" "${M_NEW[@]}"; do fn "$F" "$h" win; done; } > "$d/fr-finder.inc"
  { grep -m1 '^typedef struct { CGFloat date, size, kind, nameW; } DMFinderCols;' "$F"; fn "$F" "$COLS"; } > "$d/fr-cols.inc"
  for h in "${FUN[@]}"; do fn "$F" "$h"; done > "$d/fr-funcs.inc"
  ck() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; s=$((s + 1)); fi; }
  # ---- the source: every reload of the list or the icons shows the selection again (in -reload, or through -dm_reload:rows:)
  body=$(awk '/^@implementation DMFinderWindow \{/{f=1} f&&/^@end/{exit} f' "$F")
  local stray
  stray=$(printf '%s\n' "$body" | grep -n 'reloadData\]\|reloadRowsAtIndexPaths:\|reloadItemsAtIndexPaths:' | grep -v '\[_sidebar reloadData\]\|\[_ql reloadData\]' \
          | grep -v -F -- '- (void)reload { if (!_resortShownOnly || !_icons) [_list reloadData]; if (!_resortShownOnly || _icons) [_grid reloadData]; [self dm_showSelection]; }' \
          | grep -v -F -- 'if (v == _list) { if (rows) [_list reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone]; else [_list reloadData]; }' \
          | grep -v -F -- 'else if (v == _grid) { if (rows) [_grid reloadItemsAtIndexPaths:rows]; else [_grid reloadData]; }' | wc -l | tr -d ' ')
  ck "Finder.h: every reload of a Finder window's list or icons is -reload's or -dm_reload:rows:'s, both show the selection again ($stray other)" "[ \"$stray\" = 0 ]"
  local rl; rl=$(fn "$F" '- (void)dm_reload:(UIScrollView *)v rows:(NSArray<NSIndexPath *> *)rows {' win)
  ck "  ... -dm_reload:rows: shows _sel again in the rows it reloaded, and in the whole view after a full reload" \
     "printf '%s\n' \"\$rl\" | grep -qF 'if (rows) { for (NSIndexPath *ip in rows) [self dm_showSelectionAt:ip.item in:v]; return; }' && printf '%s\n' \"\$rl\" | grep -qF 'if ([_sel containsObject:_items[i].path]) [self dm_showSelectionAt:i in:v];'"
  local lay; lay=$(fn "$F" '- (void)setItems:(NSArray *)items error:(NSError *)err {' win | grep -v '^ *//' | sed -n 2p)
  ck "Finder.h: -setItems:error: lays the window out before anything else (a listing is shown in a window with its size)" "[ \"\$lay\" = '    [self layoutIfNeeded];' ]"
  local dl; dl=$(fn "$F" '- (void)dm_list {' win)
  ck "Finder.h: -dm_list reads on a background queue and shows the listing from the main queue (Show in Enclosing Folder's pending selection, set in the same turn as the window's opening, is always there first)" \
     "printf '%s\n' \"\$dl\" | grep -qF 'dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{' && printf '%s\n' \"\$dl\" | grep -qF 'dispatch_async(dispatch_get_main_queue(), ^{' && printf '%s\n' \"\$dl\" | grep -qF '[s setItems:items error:err];' && ! grep -n 'setItems:' \"$F\" | grep -v 'setItems:items error:err\]\|^[0-9]*:- (void)setItems:\|dm_setItems' | grep -q ."
  local show; show=$(awk '/^@implementation DMNativeWindow \{/{f=1} f&&/^- \(void\)show \{/{g=1} g{print} g&&/^}/{exit}' "$N")
  ck "NativeWindow.h: -show lays out only a hidden layer (with another native window on the screen a new window waits for the screen's update: this test's model)" \
     "printf '%s\n' \"\$show\" | grep -qF 'if (gNativeLayer.hidden) { gNativeLayer.hidden = NO; [gNativeLayer layoutIfNeeded]; }' && [ \"\$(printf '%s\n' \"\$show\" | grep -c 'layoutIfNeeded')\" = 1 ]"
  # ---- the crash map: with make-crashmap.py's own code, the new methods' place (Finder's switch, as the rest of Finder.h)
  local cm
  cm=$(python3 - "$R0" "$F" <<'PY'
import os, sys
rules_path, fh = sys.argv[1:3]
src = open('make-crashmap.py').read().rstrip(); assert src.endswith('main()')
g = {'__name__': 'frmap'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](rules_path)
hits = [0] * len(rules)
def where(path, head):
    for i, t in enumerate(open(path, errors='replace'), 1):
        if t.startswith(head): return i
    return 0
bad = 0
for sym, head in (('-[DMFinderWindow dm_reload:rows:]', '- (void)dm_reload:(UIScrollView *)v rows:'), ('-[DMFinderWindow dm_showSelectionAt:in:]', '- (void)dm_showSelectionAt:(NSInteger)i in:'),
                  ('-[DMFinderWindow setItems:error:]', '- (void)setItems:(NSArray *)items error:'), ('_DMFinderStackReveal', 'static void DMFinderStackReveal(')):
    n = where(fh, head)
    if not n: print('MISSING %s' % sym); bad += 1; continue
    g['_paths'] = {'Finder.h': fh}; g['_headers'].pop('Finder.h', None)
    t = g['classify']('MacStatusBarCore', sym, 'Finder.h', g['section_of'](os.path.dirname(fh), 'Finder.h', n), rules, images['MacStatusBarCore']['target'], hits)
    if t != 'finder': print('WRONG %s -> %s' % (sym, t)); bad += 1
print('BAD %d' % bad)
PY
)
  ck "crashmap-rules.txt: -dm_reload:rows:, -dm_showSelectionAt:in: (new), -setItems:error: and DMFinderStackReveal fall under Finder ($(printf '%s' "$cm" | tr '\n' ' '))" \
     "printf '%s\n' \"\$cm\" | grep -qx 'BAD 0'"
  # ---- the real code, run
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-const-variable -Werror=implicit-function-declaration -Werror=objc-method-access -I"$d" \
        -framework UIKit -framework CoreGraphics -o "$d/t" test-finderreveal.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  warnings building the real code"; s=$((s + 1)); }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  [ $n -ge 99 ] && return 99
  return $((n + s))
}

run "$F0" "$N0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-finderreveal: all checks pass" || echo "test-finderreveal: $rc check(s) FAILED"
if [ -z "$FR_FINDER_H$FR_NATIVE_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0; bad=0
  mtf() {   # $1 what, $2 perl expression (whole Finder.h)
    local d="$W/m$((++k))" c="$W/m$k/Finder.h"
    mkdir -p "$d"
    perl -0pe "$2" "$F0" > "$c"
    cmp -s "$c" "$F0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; bad=1; return; }
    run "$c" "$N0" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; bad=1; fi
  }
  mtf "a listing shown in a window not laid out yet (no layout first)" 's/\n    \[self layoutIfNeeded\];\n    _all = DMFinderSorted/\n    _all = DMFinderSorted/'
  mtf "the width's reload without the selection shown again" 's/if \(widthChanged\) \[self dm_reload:_list rows:nil\];/if (widthChanged) [_list reloadData];/'
  mtf "a list thumbnail's row reloaded without the selection" 's/\[ws dm_reload:t rows:\@\[ip\]\];/[t reloadRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationNone];/'
  mtf "an icon's thumbnail reloaded without the selection" 's/\[ws dm_reload:c rows:\@\[ip\]\];/[c reloadItemsAtIndexPaths:@[ip]];/'
  mtf "-dm_reload:rows: shows nothing again after a row's reload" 's/    if \(rows\) \{ for \(NSIndexPath \*ip in rows\) \[self dm_showSelectionAt:ip\.item in:v\]; return; \}\n/    if (rows) return;\n/'
  mtf "-dm_reload:rows: shows nothing again after a full reload" 's/if \(\[_sel containsObject:_items\[i\]\.path\]\) \[self dm_showSelectionAt:i in:v\];/(void)i;/'
  mtf "-dm_showSelectionAt:in: shows every row selected" 's/(- \(void\)dm_showSelectionAt:\(NSInteger\)i in:\(UIScrollView \*\)v \{\n    if \(i < 0 \|\| i >= \(NSInteger\)_items\.count\) return;\n    BOOL on = )\[_sel containsObject:_items\[i\]\.path\];/$1YES;/'
  mtf "-dm_showSelection no longer shows the icons" 's/\{ \[self dm_showSelectionAt:i in:_list\]; \[self dm_showSelectionAt:i in:_grid\]; \}/{ [self dm_showSelectionAt:i in:_list]; }/'
  mtf "Show in Enclosing Folder's new window without its pending selection" 's/f = DMFinderFront\(\); if \(!\[f\.path isEqualToString:folder\]\) f = nil; \[f dm_selectPathsWhenListed:\@\[it\.path\]\];/f = DMFinderFront(); if (![f.path isEqualToString:folder]) f = nil;/'
  [ $bad = 0 ] || rc=1
fi
exit $rc
