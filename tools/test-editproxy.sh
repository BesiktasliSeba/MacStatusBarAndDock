#!/bin/bash
# Mac test of the Dock's own items in Edit Home Screen (1.8.3 item 5; dock/EditProxyRule.h, test-editproxy.c), then the sites: the Dock controller's
# edit mode hooked on its exact type; SpringBoard's icon view made as the Dock's own (its provider and location), showing the item's own app icon
# (the identifier SnowBoard keeps a choice by), editing, no close box, no drag, no delegate; our views' taps, double taps and menus set aside while
# editing and given back; the App Library icon hidden under ours; the icon views following every Dock layout while editing.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tep" test-editproxy.c
"$W/tep"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
E=../dock/EditProxy.m; D=../dock/Dock.x; M=../dock/Makefile; T=../dock/IconTheme.m
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "built into the Dock's library" "grep -q '^DockMagnification_FILES = .* EditProxy.m' $M"
check "the Dock controller's edit mode, on its exact type only, then our items covered or given back" \
  "fn 'static void DMEditHook(void) {' $D && grep -q 'if (!m || strcmp(method_getTypeEncoding(m) ?: \"\", \"v24@0:8B16B20\"))' \$W/fn \
   && grep -q 'MSHookMessageEx(c, @selector(setEditing:animated:), (IMP)DMDockSetEditing, (IMP \*)&o_DockSetEditing);' \$W/fn \
   && fn 'static void DMDockSetEditing(id self, SEL _cmd, BOOL editing, BOOL animated) {' $D && grep -q 'o_DockSetEditing(self, _cmd, editing, animated);' \$W/fn \
   && grep -q 'DMEditProxiesApply(platter ?: box.anyObject, editing, animated, gLaunchpadClassic, YES);' \$W/fn && grep -q '    DMEditHook();' $D"
check "  ... and followed at every Dock layout while that Dock edits" "grep -q 'if (platter && DMEditProxiesOn(platter)) DMEditProxiesApply(platter, YES, NO, gLaunchpadClassic, NO);' $D"
check "SpringBoard's icon view as the Dock's own: its init's exact type, the provider and location of an Apple icon of the Dock, the item's own app icon" \
  "fn 'static UIView *EPMakeProxy(int item, UIView *model) {' $E && grep -q 'strcmp(method_getTypeEncoding(m) ?: \"\", \"@32@0:8Q16@24\")' \$W/fn \
   && grep -q 'id icon = DMIconThemeIcon((MSBDIconItem)item);' \$W/fn && grep -q 'id provider = EPGet(model, @\"listLayoutProvider\"), location = EPGet(model, @\"location\");' \$W/fn \
   && grep -q 'EPObj(v, @\"setLocation:\", location)' \$W/fn && grep -q 'EPObj(v, @\"setIcon:\", icon)' \$W/fn \
   && fn 'id DMIconThemeIcon(MSBDIconItem item) {' $T && grep -q 'return ident ? \[MSBDIconFor(ident) firstObject\] : nil;' \$W/fn"
check "  ... no label, no close box, the jiggle allowed, its picture the item's size; no delegate (nothing set); its drag switched off" \
  "fn 'static UIView *EPMakeProxy(int item, UIView *model) {' $E && grep -q 'EPNoLabel(v);' \$W/fn && grep -q 'EPBool(v, @\"setAllowsCloseBox:\", MSBDEditCloseBox());' \$W/fn \
   && grep -q 'EPBool(v, @\"setAllowsEditingAnimation:\", YES);' \$W/fn && grep -q 'EPBool(v, @\"setIconContentScalingEnabled:\", NO);' \$W/fn && ! grep -q 'setDelegate' $E \
   && fn 'static void EPFit(UIView *proxy, CGRect want, CGAffineTransform over) {' $E && grep -q 'proxy.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(k, k), over);' \$W/fn \
   && fn 'static void EPNoDrag(UIView *v) {' $E && grep -q '((UIDragInteraction \*)i).enabled = MSBDEditDrag();' \$W/fn"
check "our views while editing: their recognizers off, their menus out, their picture under SpringBoard's (Finder's running dot kept); all given back after" \
  "fn 'static void EPQuiet(UIView *v, BOOL quiet, UIView *keep, UIView *keepToo) {' $E && grep -q 'g.enabled = NO;' \$W/fn && grep -q '\[v removeInteraction:i\];' \$W/fn \
   && grep -q '((UIGestureRecognizer \*)p\[0\]).enabled = \[p\[1\] boolValue\];' \$W/fn && grep -q 'if (!\[v.interactions containsObject:i\]) \[v addInteraction:i\];' \$W/fn \
   && grep -q 'for (UIView \*s in saved\[@\"hidden\"\]) s.hidden = NO;' \$W/fn"
check "  ... SpringBoard's icon view inside our view (it moves, grows and turns with it), editing; the App Library icon hidden under ours beside it" \
  "fn 'static void EPCoverOurs(UIView *v, int view, int item, UIView *model, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q '\[v addSubview:proxy\];' \$W/fn && grep -q 'EPEditing(proxy, YES, animated);' \$W/fn \
   && fn 'static void EPCoverLibrary(UIView *library, int item, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q '\[library.superview insertSubview:proxy aboveSubview:library\];' \$W/fn && grep -q 'library.hidden = YES;' \$W/fn \
   && fn 'static void EPUndoLibrary(UIView *library) {' $E && grep -q 'library.hidden = NO;' \$W/fn"
check "the end of editing puts back every view it changed from what was kept of it (weakly), with the platter its controller had when none is found then -- the App Library icon shown again only if we hid it (review 1.8.3 P2-7); only that Dock's: another Dock still editing keeps its own, and each Dock's edit state is its own (review P3-1)" \
  "fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadClassic, BOOL logAlways) {' $E && ! grep -q 'if (!platter) return;' \$W/fn \
   && grep -q 'for (UIView \*v in \[EPChanged(platter, kEPOursKey, NO) allObjects\]) EPUndoOurs(v);' \$W/fn && grep -q 'for (UIView \*l in \[EPChanged(platter, kEPLibraryKey, NO) allObjects\]) EPUndoLibrary(l);' \$W/fn \
   && grep -q 'objc_setAssociatedObject(platter, kEPEditingKey, editing ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \$W/fn && ! grep -q 'gEPOurs\|gEPLibrary\|gEPEditing\b' $E \
   && grep -q 'BOOL DMEditProxiesOn(UIView \*platter) { return platter && \[objc_getAssociatedObject(platter, kEPEditingKey) boolValue\]; }' $E \
   && fn 'static void DMDockSetEditing(id self, SEL _cmd, BOOL editing, BOOL animated) {' $D && grep -q 'objc_setAssociatedObject(self, kDMEditPlatterKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \$W/fn && ! grep -q 'gDMEditPlatter' $D \
   && fn 'static void EPCoverLibrary(UIView *library, int item, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q 'if (!library.hidden) { library.hidden = YES; objc_setAssociatedObject(library, kEPHidKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }' \$W/fn \
   && fn 'static void EPUndoLibrary(UIView *library) {' $E && grep -q 'if (\[objc_getAssociatedObject(library, kEPHidKey) boolValue\]) { library.hidden = NO;' \$W/fn"
check "  ... where none can be made: the view jiggles itself (and still takes no tap)" \
  "fn 'static void EPCoverOurs(UIView *v, int view, int item, UIView *model, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q 'else EPOwnJiggle(v, view, YES);' \$W/fn"
check "  ... no label on them (the Dock's icons have none); the App Library's stand-in as big as our Launchpad picture is drawn" \
  "fn 'static void EPNoLabel(UIView *v) {' $E && grep -q 'EPBool(v, @\"configureForLabelAllowed:\", NO);' \$W/fn && grep -q 'EPDouble(v, @\"setIconLabelAlpha:\", 0.0);' \$W/fn \
   && grep -q 'UIView \*drawn = DMLaunchpadOverlayOf(library);' $E && grep -q '^UIView \*DMLaunchpadOverlayOf(UIView \*iconView) {' ../dock/Launchpad.m"
check "editing ended: every item's picture asked again (SnowBoard's per-icon menu changes one without its refresh note)" \
  "fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadClassic, BOOL logAlways) {' $E && grep -q 'if (!editing && was) DMIconThemeAskAgain(@\"Edit Home Screen ended\");' \$W/fn \
   && fn 'void DMIconThemeAskAgain(NSString *why) {' $T && grep -q 'gMSBDIconGeneration++;' \$W/fn"
check "a theme engine reloading one of our icons' pictures itself (SnowBoard's per-icon menu, no refresh note): every library's views told, live" \
  "grep -q 'MSBDIconAddIf(k, app, @\"reloadIconImage\", @\"v@:\", (IMP)MSBDIconReload);' ../common/IconTheme.h && grep -q 'notify_post(kMSBDIconThemeReloaded);' ../common/IconTheme.h \
   && grep -q 'if (!reloadToken) notify_register_dispatch(kMSBDIconThemeReloaded, &reloadToken, dispatch_get_main_queue(), ^(int t) {' ../common/IconTheme.h"
check "a theme refreshed while editing: each icon view shows the new picture" \
  "fn 'void DMEditProxiesThemeChanged(UIView *platter) {' $E && grep -q 'EPObj(proxy, @\"setIcon:\", icon);' \$W/fn && grep -q 'DMEditProxiesThemeChangedAll();   // (SnowBoard refreshed' $D && grep -q 'void DMEditProxiesThemeChangedAll(void) { for (UIView \*p in \[gEPEditingPlatters allObjects\]) DMEditProxiesThemeChanged(p); }' $E"
exit $fails
