#!/bin/bash
# Mac test of a module's own size change in our 15-17 Control Center (1.8.2.1, plans/v1821-uptime.md): Uptime's Module Size control sends Apple's
# -_updateModuleControllers to the overlay's last child, our panel's controller with Mac as the style. The controller as built, cut out of statusbar/CCPanel.h
# (and DMCCTypes out of StatusBar.x), run with stand-ins (test-ccmoduleupdate.m); then the wiring: the table's optional row and its part, the controller after
# Apple's grid, an expanded module's new frame kept for Apple's close. MSBD_TEST_CCPANEL: another copy of CCPanel.h, to see these checks fail on the old one.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
P=${MSBD_TEST_CCPANEL:-../statusbar/CCPanel.h}
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
{
  fn ../statusbar/StatusBar.x 'static BOOL DMCCTypes(id target, NSString *sel, const char *types) {'
  awk '/^@interface DMCCPPanelController : UIViewController$/{f=1} f{print} f&&/^@implementation DMCCPPanelController$/{g=1} g&&/^@end$/{exit}' "$P"
  fn "$P" 'static void DMCCPDidFinish(id self, SEL _cmd, id grid, id module) {'
} > "$W/ccmoduleupdate-gen.h"
grep -q '^static void DMCCPDidFinish' "$W/ccmoduleupdate-gen.h" \
  || echo 'static void DMCCPDidFinish(id self, SEL _cmd, id grid, id module) { o_DMCCPDidFinish(self, _cmd, grid, module); }   // (not hooked in this source: Apple'"'"'s own only)' >> "$W/ccmoduleupdate-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -o "$W/t" test-ccmoduleupdate.m
fails=0
"$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the table: Apple's grid's -_updateModuleControllers an optional row with Apple's types (v16@0:8), its own part (missing: only that part is left out)" \
  "grep -qF '{ kDMCCPGrid, \"_updateModuleControllers\", \"v16@0:8\", NO, YES, NO, ' $P \
   && fn $P 'static NSArray<NSString *> *DMCCPCheckAPI(' | grep -qF 'else if (!strcmp(r->sel, \"_updateModuleControllers\")) update = NO;' \
   && fn $P 'static NSArray<NSString *> *DMCCPCheckAPI(' | grep -qF 'gCCPHaveUpdate = update;'"
check "the case it answers: our controller joins Apple's overlay with -addChildViewController:, so after Apple's grid (its last child)" \
  "fn $P 'static void DMCCPEnsurePanel(UIViewController *overlay) {' | grep -qF '[overlay addChildViewController:gCCPVC];'"
check "an expanded module laid out while Apple has it: its new frame kept for Apple's close (-compactModeFrame..., DMCCPCompact), placed when it is back" \
  "fn $P 'static void DMCCPLayout(NSString *why) {' | awk '/gCCPFrames\[key\] = \[NSValue valueWithCGRect:items\[i\].frame\];/{a=NR} /if \(cv.superview != gCCPScroll\) \{ gCCPLaidSkipped = YES; continue; \}/{b=NR} END{exit !(a && b && a < b)}' \
   && fn $P 'static CGRect DMCCPCompact(id self, SEL _cmd, id containerVC) {' | grep -qF 'NSValue *f = mid ? gCCPFrames[mid] : nil;' \
   && fn $P 'static void DMCCPDidClose(id self, SEL _cmd, id grid, id module) {' | grep -qF 'if (gCCPLaidSkipped || gCCPSize < 0.999) DMCCPLayout(@\"an expanded module back\");'"
check "a container whose frame Apple holds (ignoreFrameUpdates: a press, its expanded view) is passed by the layout and marked for later, as one Apple has taken out" \
  "fn $P 'static void DMCCPLayout(NSString *why) {' | grep -qF '((BOOL (*)(id, SEL))objc_msgSend)(cv, ig)) { gCCPLaidSkipped = YES; continue; }'"
check "  ... Apple letting go of it hooked on the overlay as the other delegate calls, an optional part (Apple's types v32@0:8@16@24; missing: only that part left out)" \
  "grep -qF '{ kDMCCPOverlay, \"moduleCollectionViewController:didFinishInteractionWithModule:\", \"v32@0:8@16@24\", (void *)DMCCPDidFinish, (void **)&o_DMCCPDidFinish, kDMCCPPartFinish, ' $P \
   && fn $P 'static BOOL DMCCPHookPartHere(int part) {' | grep -qF '(part == kDMCCPPartFinish && gCCPHaveFinish)' \
   && fn $P 'static NSArray<NSString *> *DMCCPCheckAPI(' | grep -qF 'else if (part == kDMCCPPartFinish) finish = NO;' \
   && fn $P 'static NSArray<NSString *> *DMCCPCheckAPI(' | grep -qF 'gCCPHaveFinish = finish;'"
check "only the grid's own questions and actions go on to it: a setter (-setDelegate: ...) sent to our controller raises as before, and Apple's original is asked only when it is there (code review 1.8.2.1, 1 and 2)" \
  "awk '/^- \\(id\\)forwardingTargetForSelector:\\(SEL\\)s \\{/{f=1} f{print} f&&/^}/{exit}' $P | grep -qF '![NSStringFromSelector(s) hasPrefix:@\"set\"] && [g respondsToSelector:s] ? g :' \
   && fn $P 'static void DMCCPDidFinish(id self, SEL _cmd, id grid, id module) {' | grep -qF 'if (o_DMCCPDidFinish) o_DMCCPDidFinish(self, _cmd, grid, module);'"
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' test-ccmoduleupdate.m test-ccmoduleupdate.sh"
exit $fails
