#!/bin/bash
# test-downloadsstack.sh: the Dock's Downloads stack (1.8.8.1, KT 21 Nov) -- the newest item at the bottom, as a Mac's Downloads stack sorted by
# Date Added, and a menu on every item (Open, Quick Look, Show in Enclosing Folder, Get Info, Rename, Share, Move to Trash) by a finger's hold or a
# pointer's secondary click. See test-downloadsstack.m: the real code is cut out of dock/Downloads.m and statusbar/Finder.h (DS_DL_M / DS_FINDER_H /
# DS_DOCK_X: other copies, e.g. the code before the fix) and run on the Mac, over folders of made-up files of its own. The wiring is read from
# Downloads.m, Dock.x's -[UIApplication sendEvent:] hook, Finder.h, and the crash map's rules (with make-crashmap.py's own code). Then made-to-fail
# copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
D0=${DS_DL_M:-../dock/Downloads.m}; F0=${DS_FINDER_H:-../statusbar/Finder.h}; X0=${DS_DOCK_X:-../dock/Dock.x}; R0=crashmap-rules.txt
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function or method of a file, from its first line
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                    # one line of a file (a global, a one-line function)
has() { grep -qF -- "$2" "$1"; }

run() {   # $1 Downloads.m, $2 Finder.h, $3 Dock.x, $4 work dir, $5 quiet; the number of failed checks (99: not built)
  local D=$1 F=$2 X=$3 d=$4 q=$5 out n=0 s=0 defs="" body
  mkdir -p "$d/run"
  [ -n "$(fn "$D" 'static NSArray<DMDownload *> *DMScan(')" ] || { echo "FAIL  $D: no DMScan"; return 99; }
  {   # the model and the listings
    awk 'index($0, "@interface DMDownload : NSObject") == 1 {f=1} f {print} f && index($0, "@implementation DMDownloadSource") == 1 {g=1; next} g && /^@end/ {exit}' "$D"
    if [ -n "$(fn "$D" 'static NSDate *DMDownloadDate(')" ]; then
      fn "$D" 'static NSArray<NSURLResourceKey> *DMDownloadKeys('; fn "$D" 'static NSDate *DMDownloadDate('; fn "$D" 'static NSComparisonResult DMDownloadNewerFirst('
      line "$D" 'static CGFloat DMDownloadRowTop('
    fi
    fn "$D" 'static NSArray<DMDownload *> *DMScan('
    line "$D" 'static const NSUInteger kSearchCap'; line "$D" 'static const CGFloat kSearchRowH'; fn "$D" 'static NSString *DMFold('; fn "$D" 'static NSArray<DMDownload *> *DMSearchIndex('
  } > "$d/run/ds-model.inc"
  [ -n "$(fn "$D" 'static NSDate *DMDownloadDate(')" ] || defs="$defs -DDS_NO_ORDER"
  if [ -n "$(fn "$D" 'static int DMDLPressTake(')" ]; then
    { line "$D" 'static const double kDMDLHoldMenu'; line "$D" 'static const long kDMDLSecondaryButton'; fn "$D" 'static int DMDLPressTake('
      line "$D" 'static int DMDLReleaseOpens('; line "$D" 'static int DMDLHoldEndOpens('; } > "$d/run/ds-press.inc"
  else : > "$d/run/ds-press.inc"; defs="$defs -DDS_NO_PRESS"; fi
  if [ -n "$(fn "$F" 'static int DMFinderStackMenuRows(')" ]; then
    { line "$F" 'enum { kDMFSMDivider'; line "$F" 'enum { kDMFSMDir'; fn "$F" 'static int DMFinderStackMenuRows('; fn "$F" 'static const char *DMFinderStackMenuTitle('; } > "$d/run/ds-finder.inc"
  else : > "$d/run/ds-finder.inc"; defs="$defs -DDS_NO_FINDER"; fi

  # ---- the wiring
  ck() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; s=$((s + 1)); fi; }
  hasin() { printf '%s\n' "$1" | grep -qF -- "$2"; }   # (a piece of code holds this text)
  order() { local t=$1 last=0 ln p; shift; for p in "$@"; do ln=$(printf '%s\n' "$t" | grep -nF -m1 -- "$p" | cut -d: -f1); [ -n "$ln" ] && [ "$ln" -gt "$last" ] || return 1; last=$ln; done; }
  local fill present ask click tapped press note touch contains esc dismiss menu hook fmenu names=1 nm closes
  fill=$(fn "$D" '- (NSArray<UIView *> *)fillList:(NSArray<DMDownload *> *)items {')
  present=$(fn "$D" '- (void)presentItems:(NSArray<DMDownload *> *)items sources:(NSArray<DMDownloadSource *> *)sources fromIcon:(UIView *)icon {')
  ask=$(fn "$D" '- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)i configurationForMenuAtLocation:(CGPoint)loc {')
  click=$(fn "$D" '- (void)dm_secondaryClickIn:(UIView *)v at:(CGPoint)loc {')
  tapped=$(fn "$D" '- (void)rowTapped:(DMDownloadRow *)row event:(UIEvent *)event {')
  press=$(fn "$D" '- (void)rowPress:(UILongPressGestureRecognizer *)g {')
  note=$(fn "$D" 'void DMDownloadsNotePress(UIEvent *event) {')
  touch=$(fn "$D" '- (void)touchBeganOnView:(UIView *)v {')
  contains=$(fn "$D" 'BOOL DMDownloadsPanelContainsTouch(UITouch *touch) {')
  esc=$(fn "$D" '__attribute__((visibility("default"))) BOOL MSBDDownloadsPanelEscape(void) {')
  dismiss=$(fn "$D" '- (void)dismissAnimated:(BOOL)animated {')
  menu=$(fn "$D" '- (BOOL)openItemMenu:(DMDownloadRow *)row at:(CGPoint)sp how:(NSString *)how {')
  hook=$(awk '/^%hook UIApplication$/{f=1} f&&/^- \(void\)sendEvent:\(UIEvent \*\)event \{/{g=1} g{print} g&&/^}/{exit}' "$X")
  fmenu=$(fn "$F" '__attribute__((visibility("default"))) BOOL MSBDFinderStackItemMenu(NSString *path, CGPoint sp, UIView *from, dispatch_block_t open, dispatch_block_t closeStack) {')
  for nm in MSBDFinderStackItemMenu MSBDFinderStackMenuIsOpen MSBDFinderStackMenuClose; do
    has "$D" "dlsym(RTLD_DEFAULT, \"$nm\")" && grep -q "^__attribute__((visibility(\"default\"))) [A-Za-z]* $nm(" "$F" || names=0
  done
  closes=$(printf '%s\n' "$fmenu" | grep -cF ', ^{ close(); ')
  ck "Downloads.m -fillList:: item k at DMDownloadRowTop (the newest at the bottom), its release to -rowTapped:event:" \
     'hasin "$fill" "row.frame = CGRectMake(0, DMDownloadRowTop(k, items.count, rowH), rowW, rowH);" && hasin "$fill" "[row addTarget:self action:@selector(rowTapped:event:) forControlEvents:UIControlEventTouchUpInside];"'
  ck "  ... the hold stays a 0.25 s press that may move (the item still comes out of the stack)" \
     'hasin "$fill" "lp.minimumPressDuration = 0.25; lp.allowableMovement = CGFLOAT_MAX;"'
  ck "-presentItems:: the list gets a context menu interaction with the panel as delegate (a secondary click's only way in), with Finder's menu here; the last press is forgotten" \
     'hasin "$present" "if (DMDLItemMenuFn()) [scroll addInteraction:[[UIContextMenuInteraction alloc] initWithDelegate:self]];" && hasin "$present" "gDLPressTouch = nil; gDLPressButtons = 0; gDLPressTaken = 0;"'
  ck "UIKit's ask hands the press to -dm_secondaryClickIn:at: and answers nil (UIKit's own menu never opens)" \
     'hasin "$ask" "[self dm_secondaryClickIn:i.view at:loc];" && hasin "$ask" "return nil;" && ! hasin "$ask" "configurationWithIdentifier"'
  ck "-dm_secondaryClickIn:at:: only the press DMDLPressTake takes (once), on a row; the menu opens once UIKit is done with the press" \
     'order "$click" "BOOL mine = DMDLPressTake(gDLPressButtons, &taken, down, inList);" "gDLPressTaken = taken;" "if (!mine) return;" "dispatch_async(dispatch_get_main_queue(), ^{" "[p openItemMenu:r at:sp how:@\"secondary click\"];"'
  ck "-rowTapped:event:: a secondary click's release opens nothing (DMDLReleaseOpens), the rest open as before" \
     'order "$tapped" "if (!DMDLReleaseOpens(gDLPressButtons, event != nil))" "[self openDownload:row.download];"'
  ck "-rowPress:: held still kDMDLHoldMenu after the hold, the same press, not carried out: the item's menu" \
     'order "$press" "dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDMDLHoldMenu * NSEC_PER_SEC))" "p.holdSerial != serial || p.dragRow != r || p.dragLifted" "p.holdMenuOpened = [p openItemMenu:r at:at how:@\"held still\"];"'
  ck "  ... moved with the menu open: the menu closes before the item comes out" \
     'order "$press" "if (self.holdMenuOpened) {" "DMDLItemMenuClose();" "MSBDFinderDragBeginPaths"'
  ck "  ... let go: the item opens only when its menu did not (DMDLHoldEndOpens)" \
     'hasin "$press" "} else if (held && DMDLHoldEndOpens(menu, drop)) [self rowTapped:held event:nil];"'
  ck "DMDownloadsNotePress: a press that begins in the open panel's window (not the system gestures' copy), with its event's buttons, a new take each time" \
     'order "$note" "if (![p isOpen]) return;" "if (t.phase != UITouchPhaseBegan || !w || t.window != w) continue;" "b = (long)event.buttonMask;" "gDLPressTouch = t; gDLPressButtons = b; gDLPressTaken = 0;"'
  ck "Dock.x: SpringBoard's -[UIApplication sendEvent:] notes it before UIKit handles the event" \
     'order "$hook" "    if (event.type == UIEventTypeTouches) DMDownloadsNotePress(event);" "    %orig;"'
  ck "an item's menu open over the panel: a touch on it does not close the panel, the Dock does not take it, Esc closes the menu first" \
     'hasin "$touch" "if (DMDLItemMenuOpen()) return;" && hasin "$contains" "if (DMDLItemMenuOpen()) return YES;" && order "$esc" "if (DMDLItemMenuOpen()) return NO;" "searchField.text.length"'
  ck "  ... and the panel closing for any reason closes it" 'hasin "$dismiss" "DMDLItemMenuClose();"'
  ck "-openItemMenu:at:how:: Finder's menu, its Open the stack's own, every other row closing the panel" \
     'hasin "$menu" "ok = menu(d.url.path, sp, row, open, close);" && hasin "$menu" "dispatch_block_t open = ^{ [[DMDownloadsPanel shared] openDownload:d]; };" && hasin "$menu" "[p dismissAnimated:YES];"'
  ck "the names Downloads.m asks for are the ones Finder.h exports" '[ $names = 1 ]'
  ck "Finder.h MSBDFinderStackItemMenu: none with Finder off; the rows DMFinderStackMenuRows gives; the stack's display's menu window" \
     'hasin "$fmenu" "if (!gFinderOn ||" && hasin "$fmenu" "DMFinderStackMenuRows(what, rows, usable, 16)" && hasin "$fmenu" "UIView *host = (UIView *)DMExtMenuWindowFor(from) ?: DMMenuHost();" && hasin "$fmenu" "DMFinderShowMenuIn(host, [UIMenu menuWithTitle:@\"\" children:groups], sp);" && hasin "$fmenu" "gFinderStackMenu = gOverlay;"'
  ck "  ... Open is the stack's own; every other row closes the stack first, then does Finder's own action ($closes rows close first)" \
     'hasin "$fmenu" "e = A(r, nil, ^{ if (open) open(); });" && [ "$closes" = 5 ] && hasin "$fmenu" "^(UIAction *x) { close(); DMFinderShareTo(@[it], b, DMFinderOps()); }" && hasin "$fmenu" "[ops dm_trashItems:@[it.path]]" && hasin "$fmenu" "[ops getInfo:it]" && hasin "$fmenu" "DMQuickLookOpen(it.path)" && hasin "$fmenu" "DMFinderStackReveal(it.path, YES)" && hasin "$fmenu" "DMFinderStackReveal(it.path, NO)"'
  local show; show=$(fn "$F" 'static void DMFinderShowMenuIn(UIView *host, UIMenu *menu, CGPoint screenPoint) {')
  ck "Finder.h DMFinderShowMenuIn: the point read on the host's own screen (a window's -window is nil: the TV's menu window is on the TV)" \
     'order "$show" "UIScreen *scr = ([host isKindOfClass:[UIWindow class]] ? ((UIWindow *)host).screen : host.window.screen) ?: [UIScreen mainScreen];" "fromCoordinateSpace:scr.coordinateSpace];"'
  ck "  ... a row the rules grey is greyed, Move to Trash shows as destructive" \
     'hasin "$fmenu" "((UIAction *)e).attributes = !usable[k] ? UIMenuElementAttributesDisabled : r == kDMFSMTrash ? UIMenuElementAttributesDestructive : 0;"'
  local dbg; dbg=$(fn "$D" '        else if ([cmd isEqualToString:@"order"]) {')
  ck "debug only: the order line names a row only when its item lies inside the test folder /tmp/dockmag-dlfolder names (never the user's downloads, also with that file empty)" \
     'hasin "$dbg" "*inside = tf.length > 1 ? [tf stringByAppendingString:@\"/\"] : nil;" && hasin "$dbg" "BOOL own = inside && [r.download.url.path.stringByStandardizingPath hasPrefix:inside]; [out addObject:own ?"'
  # ---- the crash map: with make-crashmap.py's own code, each new function's place by its name, file and section
  local cm
  cm=$(python3 - "$R0" "$D" "$F" <<'PY'
import os, re, sys
rules_path, dl, fh = sys.argv[1:4]
src = open('make-crashmap.py').read().rstrip(); assert src.endswith('main()')
g = {'__name__': 'dsmap'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](rules_path)
hits = [0] * len(rules)
def where(path, head):
    for i, t in enumerate(open(path, errors='replace'), 1):
        if t.startswith(head): return i
    return 0
bad = 0
for image, path, want, names in (('DockMagnification', dl, 'showDownloads', [('_DMDownloadsNotePress', 'void DMDownloadsNotePress('), ('_DMDLPressTake', 'static int DMDLPressTake('),
                                    ('_DMDLItemMenuOpen', 'static BOOL DMDLItemMenuOpen('), ('_DMDLItemMenuClose', 'static void DMDLItemMenuClose('), ('_DMDLItemMenuLook', 'static void DMDLItemMenuLook('),
                                    ('_DMDownloadDate', 'static NSDate *DMDownloadDate('), ('_DMDownloadNewerFirst', 'static NSComparisonResult DMDownloadNewerFirst('),
                                    ('-[DMDownloadsPanel dm_secondaryClickIn:at:]', '- (void)dm_secondaryClickIn:'), ('-[DMDownloadsPanel openItemMenu:at:how:]', '- (BOOL)openItemMenu:')]),
                                   ('MacStatusBarCore', fh, 'finder', [('_MSBDFinderStackItemMenu', '__attribute__((visibility("default"))) BOOL MSBDFinderStackItemMenu('),
                                    ('_MSBDFinderStackMenuIsOpen', '__attribute__((visibility("default"))) BOOL MSBDFinderStackMenuIsOpen('),
                                    ('_MSBDFinderStackMenuClose', '__attribute__((visibility("default"))) void MSBDFinderStackMenuClose('),
                                    ('_DMFinderStackMenuRows', 'static int DMFinderStackMenuRows('), ('_DMFinderStackReveal', 'static void DMFinderStackReveal(')])):
    fname = {'DockMagnification': 'Downloads.m', 'MacStatusBarCore': 'Finder.h'}[image]
    for sym, head in names:
        n = where(path, head)
        if not n: print('MISSING %s' % sym); bad += 1; continue
        g['_paths'] = {fname: path}; g['_headers'].pop(fname, None)
        t = g['classify'](image, sym, fname, g['section_of'](os.path.dirname(path), fname, n), rules, images[image]['target'], hits)
        if t != want: print('WRONG %s -> %s' % (sym, t)); bad += 1
print('BAD %d' % bad)
PY
)
  ck "crashmap-rules.txt: the new functions of Downloads.m fall under Show Downloads in Dock, Finder.h's under Finder ($(printf '%s' "$cm" | tr '\n' ' '))" \
     "printf '%s\n' \"\$cm\" | grep -qx 'BAD 0'"
  # ---- the real code, run
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-const-variable -Wno-unused-variable -Werror=implicit-function-declaration $defs -I"$d/run" \
        -framework Foundation -framework CoreGraphics -o "$d/t" test-downloadsstack.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  mkdir -p "$d/files"
  out=$("$d/t" "$d/files"); n=$?
  [ -n "$q" ] || echo "$out"
  return $((n + s))
}

run "$D0" "$F0" "$X0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-downloadsstack: all checks pass" || echo "test-downloadsstack: $rc check(s) FAILED"
if [ -z "$DS_DL_M$DS_FINDER_H$DS_DOCK_X" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0; bad=0
  mtf() {   # $1 what, $2 file (dl|fh|dx), $3 perl expression (whole file)
    local d="$W/m$((++k))" D=$D0 F=$F0 X=$X0 c src
    mkdir -p "$d"
    case $2 in dl) src=$D0; c="$d/Downloads.m"; D=$c;; fh) src=$F0; c="$d/Finder.h"; F=$c;; dx) src=$X0; c="$d/Dock.x"; X=$c;; esac
    perl -0pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; bad=1; return; }
    run "$D" "$F" "$X" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; bad=1; fi
  }
  mtf "the date read back as Date Modified first (the old order)" dl 's/for \(NSURLResourceKey k in \@\[NSURLAddedToDirectoryDateKey, NSURLCreationDateKey, NSURLContentModificationDateKey\]\)/for (NSURLResourceKey k in @[NSURLContentModificationDateKey, NSURLCreationDateKey, NSURLAddedToDirectoryDateKey])/'
  mtf "the listings no longer ask for the Date Added" dl 's/return \[\@\[NSURLAddedToDirectoryDateKey, NSURLCreationDateKey, NSURLContentModificationDateKey\]/return [@[NSURLCreationDateKey, NSURLContentModificationDateKey]/'
  mtf "the search index keeps the old date" dl 's/(d\.url = u; d\.source = where; d\.viaFiles = src\.viaFiles;\n            d\.date = )DMDownloadDate\(v\);/$1v[NSURLContentModificationDateKey] ?: [NSDate distantPast];/'
  mtf "oldest first" dl 's/NSComparisonResult r = \[b\.date compare:a\.date\];/NSComparisonResult r = [a.date compare:b.date];/'
  mtf "the newest at the top of the list" dl 's/return k < n \? \(CGFloat\)\(n - 1 - k\) \* rowH : 0\.0;/return (CGFloat)k * rowH;/'
  mtf "a press taken whatever its buttons (a finger's, a primary click)" dl 's/ \|\| !\(buttons & kDMDLSecondaryButton\) \|\| !down/ || !down/'
  mtf "a press taken again at every ask" dl 's/\n    \*taken = 1;\n/\n/'
  mtf "a secondary click's release opens the item too" dl 's/return !withEvent \|\| !\(buttons & kDMDLSecondaryButton\);/return 1;/'
  mtf "a hold let go after its menu still opens the item" dl 's/return letGo && !menuOpened;/return letGo;/'
  mtf "the list without its context menu interaction" dl 's/    if \(DMDLItemMenuFn\(\)\) \[scroll addInteraction:\[\[UIContextMenuInteraction alloc\] initWithDelegate:self\]\];\n//'
  mtf "UIKit's ask answered without opening ours" dl 's/    \[self dm_secondaryClickIn:i\.view at:loc\];\n//'
  mtf "Dock.x's hook no longer notes the press" dx 's/\n    if \(event\.type == UIEventTypeTouches\) DMDownloadsNotePress\(event\);//'
  mtf "the system gestures' copy of a touch noted as the panel's press" dl 's/ \|\| !w \|\| t\.window != w\) continue;/) continue;/'
  mtf "a touch on the item's menu closes the panel" dl 's/\n    if \(DMDLItemMenuOpen\(\)\) return;   \/\/[^\n]*//'
  mtf "the Dock's dismissal takes a touch on the item's menu" dl 's/\n    if \(DMDLItemMenuOpen\(\)\) return YES;[^\n]*//'
  mtf "Esc closes the panel under the item's menu" dl 's/\n    if \(DMDLItemMenuOpen\(\)\) return NO;[^\n]*//'
  mtf "the hold opens no menu" dl 's/p\.holdMenuOpened = \[p openItemMenu:r at:at how:\@"held still"\];/(void)at;/'
  mtf "a move with the menu open leaves the menu" dl 's/                DMDLItemMenuClose\(\);\n//'
  mtf "debug: the order line names every row (the user's downloads too)" dl 's/BOOL own = inside && \[r\.download\.url\.path\.stringByStandardizingPath hasPrefix:inside\]; \[out addObject:own \?/BOOL own = YES; [out addObject:own ?/'
  mtf "Finder: a folder's menu with Quick Look" fh 's/    if \(!\(what & kDMFSMDir\)\) DMFSM_ROW\(kDMFSMQuickLook, 1\);/    DMFSM_ROW(kDMFSMQuickLook, 1);/'
  mtf "Finder: no Share row" fh 's/DMFSM_ROW\(kDMFSMShare, what & kDMFSMShareApps\);/(void)0;/'
  mtf "Finder: Rename never greyed" fh 's/DMFSM_ROW\(kDMFSMRename, what & kDMFSMCanChange\);/DMFSM_ROW(kDMFSMRename, 1);/'
  mtf "Finder: Move to Trash without closing the stack first" fh 's/\^\{ close\(\); DMFinderWindow \*ops = DMFinderOps\(\); ops\.path = folder; \[ops dm_trashItems:/^{ DMFinderWindow *ops = DMFinderOps(); ops.path = folder; [ops dm_trashItems:/'
  mtf "Finder: a menu window's point read in the iPad's screen again" fh 's/\(\[host isKindOfClass:\[UIWindow class\]\] \? \(\(UIWindow \*\)host\)\.screen : host\.window\.screen\)/host.window.screen/'
  mtf "Finder: its menu with Finder switched off" fh 's/    if \(!gFinderOn \|\| !\[path isKindOfClass:\[NSString class\]\]/    if (![path isKindOfClass:[NSString class]]/'
  [ $bad = 0 ] || rc=1
fi
exit $rc
