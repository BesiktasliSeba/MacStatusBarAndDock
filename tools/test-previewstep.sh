#!/bin/bash
# Mac test of moving between previews (1.8.4.2 item 3): the step rule (common/PreviewStep.h, test-previewstep.c) and the wiring in SpringBoard
# (statusbar/Finder.h): Quick Look's arrows and swipes move the Finder window's selection; the preview follows the selection whatever moved it;
# Quick Look's multi-item data source is the Finder window's files; Space or Esc closes, Space in Finder toggles it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/tps" test-previewstep.c && "$W/tps" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
m() { awk -v h="$2" '!p && index($0, h) == 1 {p=1} p {print} p && /^}/ {exit}' "$1"; }
H=../statusbar/Finder.h
QK='- (BOOL)dm_handleKey:(UIKey *)key {   // (Space, Esc or Command-W close it again, as on a Mac; the arrows'
check "Finder includes the rule" "grep -q '#include \"../common/PreviewStep.h\"' $H"
check "Quick Look's keys: the four arrows, no modifier, step through the Finder window" \
  "m $H \"\$QK\" | grep -q 'int move = c == UIKeyboardHIDUsageKeyboardUpArrow ? MSBD_STEP_UP : c == UIKeyboardHIDUsageKeyboardDownArrow ? MSBD_STEP_DOWN' \
   && m $H \"\$QK\" | grep -q ': c == UIKeyboardHIDUsageKeyboardLeftArrow ? MSBD_STEP_LEFT : c == UIKeyboardHIDUsageKeyboardRightArrow ? MSBD_STEP_RIGHT : 0;' \
   && m $H \"\$QK\" | grep -q 'if (move) return \[self dm_step:move\];'"
check "  ... Space, Esc (and Command-W) still close it, back to the Finder window it came from" \
  "m $H \"\$QK\" | grep -q 'c == UIKeyboardHIDUsageKeyboardSpacebar || c == UIKeyboardHIDUsageKeyboardEscape' && m $H \"\$QK\" | grep -qF '(DMNativeWindow *)b : b ? nil : (DMNativeWindow *)DMFinderFront();'"
check "the Finder window moves its selection by the rule (the icon view by its columns) and scrolls to it" \
  "m $H '- (NSString *)dm_previewStep:(int)move {' | grep -q 'long to = MSBDPreviewStep(move, _icons, _icons ? (long)\[self dm_gridColumns\] : 1, (long)i, (long)_items.count);' \
   && m $H '- (NSString *)dm_previewStep:(int)move {' | grep -q '\[self dm_setSelection:@\[p\] anchor:p\];' && m $H '- (NSString *)dm_previewStep:(int)move {' | grep -q '\[self dm_scrollToPath:p\];'"
check "the preview follows the selection, whatever moved it (one item selected)" \
  "m $H '- (void)dm_showSelection {' | grep -q 'if (n == 1) \[\[self dm_quickLookWindow\] dm_follow:\[self dm_selectedItem\].path\];' \
   && m $H '- (void)dm_follow:(NSString *)path {' | grep -q '\[self dm_show:path\];'"
check "  ... Quick Look from a Finder window knows it (one Quick Look window per Finder window)" \
  "grep -q '^- (void)quickLook:(DMFinderItem \*)it { if (it.cloud) { \[self dm_download:it\]; return; } DMQuickLookOpenFrom(it.path, self); }' $H \
   && fn $H 'static void DMQuickLookOpenFrom(' | grep -q 'if (!(browser && q.browser == browser) && !\[q.file isEqualToString:path\]) continue;' \
   && fn $H 'static void DMQuickLookOpenFrom(' | grep -q 'initWithFile:path browser:browser'"
check "  ... Space in Finder while it is open closes it, as on a Mac" \
  "m $H '- (void)dm_quickLookSelected {' | grep -q 'if (q) { \[q close\]; \[self activate\]; return; }'"
check "swipes: left and right on the content, never over a control or content that scrolls sideways; with Quick Look's viewer, only if it didn't page itself" \
  "m $H '- (instancetype)initWithFile:(NSString *)path browser:' | grep -q '@\[@(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)\]' \
   && m $H '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {' | grep -q 'if (\[v isKindOfClass:\[UIControl class\]\]) return NO;' \
   && m $H '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {' | grep -q 's.contentSize.width > s.bounds.size.width + 1.0' \
   && m $H '- (void)dm_swipe:(UISwipeGestureRecognizer *)g {' | grep -q 'if (!s || s->_qlPagedAt >= at - 0.2) return;'"
check "  ... only our two swipes change: every other recognizer keeps UIKit's defaults" \
  "m $H '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {' | grep -q 'if (!\[g.name isEqualToString:kDMQLSwipe\]) return YES;' \
   && grep -q 'shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer \*)o { return \[g.name isEqualToString:kDMQLSwipe\]; }' $H"
check "Quick Look's multi-item data source: the Finder window's files (never a folder or an app); its own paging moves the selection" \
  "m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q 'for (NSString \*p in \[self.browser dm_previewPaths\] ?: @\[\])' \
   && m $H '- (NSArray<NSString *> *)dm_previewPaths {' | grep -q '(!it.dir || (it.package && !\[it.name.pathExtension.lowercaseString isEqualToString:@\"app\"\])) && !it.cloud && !it.app' \
   && m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q 'addObserver:self forKeyPath:@\"currentPreviewItemIndex\"' \
   && m $H '- (void)dm_quickLookPaged {' | grep -q '\[self.browser dm_previewSelect:p\];'"
check "  ... our own moves of its index are not taken for its paging; the observer goes with the viewer" \
  "m $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -q '_qlSetting = YES;' && m $H '- (void)observeValueForKeyPath:' | grep -q 'if (_qlSetting) return;' \
   && m $H '- (void)dm_quickLookRemove {' | grep -q 'removeObserver:self forKeyPath:@\"currentPreviewItemIndex\" context:&kDMQLIndexContext'"
check "the Finder's own keys are as before (its arrows still move by one)" \
  "fn $H '- (void)dm_selectStep:(NSInteger)d {' | grep -q 'i = MAX(0, MIN((NSInteger)_items.count - 1, i < 0 ? 0 : i + d));'"
check "the first file of a window builds the viewer's list (a nil list answers 0, not NSNotFound: Quick Look had nothing to show)" \
  "fn $H '- (UIView *)dm_quickLookView:(NSString *)path {' | grep -qF 'NSUInteger i = _qlItems ? [_qlItems indexOfObject:u] : NSNotFound;'"
check "no em dash in the feature's files" "! grep -q \$'\\xe2\\x80\\x94' ../common/PreviewStep.h test-previewstep.c test-previewstep.sh"
[ $fails = 0 ] && echo "test-previewstep: all checks pass" || { echo "test-previewstep: checks FAILED"; exit 1; }
