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
   && grep -q 'DMEditProxiesApply(platter ?: box.anyObject, editing, animated, gLaunchpadIcon, gLaunchpadClassic, YES);' \$W/fn && grep -q '    DMEditHook();' $D"
check "  ... and followed at every Dock layout while that Dock edits" "grep -q 'if (platter && DMEditProxiesOn(platter)) DMEditProxiesApply(platter, YES, NO, gLaunchpadIcon, gLaunchpadClassic, NO);' $D"
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
check "audit 1.8.3 L7: the App Library icon gets our Launchpad stand-in only while our Launchpad picture is on (the switch passed from the Dock); off, it edits as Apple's own, one covered before given back" \
  "fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadIcon, BOOL launchpadClassic, BOOL logAlways) {' $E \
   && grep -q 'if (launchpadIcon) EPCoverLibrary(library, MSBDEditIconItem(kMSBDEditLaunchpad, launchpadClassic, full), editing, animated, platter);' \$W/fn \
   && grep -q 'else if (library && (objc_getAssociatedObject(library, kEPProxyKey) || \[objc_getAssociatedObject(library, kEPHidKey) boolValue\])) EPUndoLibrary(library);' \$W/fn \
   && [ \"\$(grep -c 'DMEditProxiesApply(.*gLaunchpadIcon, gLaunchpadClassic' $D)\" = 2 ]"
check "audit 1.8.3 L6: set aside already and now with nothing to keep (its own jiggle after a stand-in): what the stand-in had hidden shows again, and is not shown twice later" \
  "fn 'static void EPQuiet(UIView *v, BOOL quiet, UIView *keep, UIView *keepToo) {' $E && awk '/if \\(saved\\) \\{/{a=NR} /if \\(!keep\\) \\{ for \\(UIView \\*s in saved\\[@\"hidden\"\\]\\) s.hidden = NO; saved\\[@\"hidden\"\\] = @\\[\\]; \\}/{b=NR} END{exit !(a && b > a)}' \$W/fn"
check "  ... SpringBoard's icon view inside our view (it moves, grows and turns with it), editing; the App Library icon hidden under ours beside it" \
  "fn 'static void EPCoverOurs(UIView *v, int view, int item, UIView *model, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q '\[v addSubview:proxy\];' \$W/fn && grep -q 'EPEditing(proxy, YES, animated);' \$W/fn \
   && fn 'static void EPCoverLibrary(UIView *library, int item, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q '\[library.superview insertSubview:proxy aboveSubview:library\];' \$W/fn && grep -q 'library.hidden = YES;' \$W/fn \
   && fn 'static void EPUndoLibrary(UIView *library) {' $E && grep -q 'library.hidden = NO;' \$W/fn"
check "the end of editing puts back every view it changed from what was kept of it (weakly), with the platter its controller had when none is found then -- the App Library icon shown again only if we hid it (review 1.8.3 P2-7); only that Dock's: another Dock still editing keeps its own, and each Dock's edit state is its own (review P3-1)" \
  "fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadIcon, BOOL launchpadClassic, BOOL logAlways) {' $E && ! grep -q 'if (!platter) return;' \$W/fn \
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
  "fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadIcon, BOOL launchpadClassic, BOOL logAlways) {' $E && grep -q 'if (!editing && was) DMIconThemeAskAgain(@\"Edit Home Screen ended\");' \$W/fn \
   && fn 'void DMIconThemeAskAgain(NSString *why) {' $T && grep -q 'gMSBDIconGeneration++;' \$W/fn"
check "a theme engine reloading one of our icons' pictures itself (SnowBoard's per-icon menu, no refresh note): every library's views told, live" \
  "grep -q 'MSBDIconAddIf(k, app, @\"reloadIconImage\", @\"v@:\", (IMP)MSBDIconReload);' ../common/IconTheme.h && grep -q 'notify_post(kMSBDIconThemeReloaded);' ../common/IconTheme.h \
   && grep -q 'if (!reloadToken) notify_register_dispatch(kMSBDIconThemeReloaded, &reloadToken, dispatch_get_main_queue(), ^(int t) {' ../common/IconTheme.h"
check "a theme refreshed while editing: each icon view shows the new picture" \
  "fn 'void DMEditProxiesThemeChanged(UIView *platter) {' $E && grep -q 'EPObj(proxy, @\"setIcon:\", icon);' \$W/fn && grep -q 'DMEditProxiesThemeChangedAll();   // (SnowBoard refreshed' $D && grep -q 'void DMEditProxiesThemeChangedAll(void) { for (UIView \*p in \[gEPEditingPlatters allObjects\]) DMEditProxiesThemeChanged(p); }' $E"
check "beside a side Dock each icon view of ours is turned once: the side Dock's turn passes our items' icon views by (their own views turn them already) and leaves the Launchpad one the App Library icon's turn, copied (audit 1.8.3 M2: they were turned twice, lying on their side)" \
  "grep -q 'BOOL DMEditProxyIs(UIView \*v) { return v && objc_getAssociatedObject(v, kEPItemKey) != nil; }' $E && grep -q 'extern BOOL DMEditProxyIs(UIView \*v);' $D \
   && fn 'static void DMDockSideStyleIcon(UIView *icon, int side) {' $D && sed -n 2p \$W/fn | grep -q 'if (DMEditProxyIs(icon)) return;' \
   && [ \$(grep -c 'sublayerTransform' $E) = 1 ] && fn 'static void EPFollow(UIView *proxy, UIView *library) {' $E && grep -q 'proxy.layer.sublayerTransform = DMDockSideTurnFor(library);' \$W/fn"
check "the Launchpad icon view's turn by the Dock's side (the rule every Dock icon's turn has), never copied from the App Library icon's layer; its size from that icon's picture as drawn (the Dock's scale over it), measured once the Dock's layout is done, never in the middle of one (1.8.3.1 F-5, M1: a Dock layout while editing caught that icon without its turn, ours came out turned and too big; its iconImageFrame is the whole 61 pt icon, twice the 30 pt picture)" \
  "fn 'static void EPFollow(UIView *proxy, UIView *library) {' $E && grep -q 'proxy.layer.sublayerTransform = DMDockSideTurnFor(library);' \$W/fn \
   && ! grep -q 'library.layer.sublayerTransform' \$W/fn && ! grep -q 'NSSelectorFromString(@\"iconImageFrame\")' \$W/fn \
   && grep -q 'UIView \*drawn = DMLaunchpadOverlayOf(library);' \$W/fn && grep -q 'CGRect r = \[img convertRect:img.bounds toView:library\];' \$W/fn && grep -q 'EPFit(proxy, want, t);' \$W/fn \
   && grep -q 'extern CATransform3D DMDockSideTurnFor(UIView \*icon);' $E \
   && fn 'static void EPFollowSettled(UIView *proxy, UIView *library) {' $E && grep -q 'dispatch_async(dispatch_get_main_queue(), \^{' \$W/fn && grep -q 'EPFollow(p, l);' \$W/fn \
   && fn 'static void EPCoverLibrary(UIView *library, int item, BOOL editing, BOOL animated, UIView *platter) {' $E \
   && grep -q 'if (made) EPFollow(proxy, library);   // (placed at once when it is new' \$W/fn && grep -q 'EPFollowSettled(proxy, library);' \$W/fn \
   && fn 'CATransform3D DMDockSideTurnFor(UIView *icon) {' $D && grep -q 'return DMDockSideIconTurn(icon && gDockSideApplied && DMIsDockIcon(icon) && DMDockSideInHost(icon) ? gDockSideApplied : 0);' \$W/fn \
   && grep -q 'BOOL dock = gDockSideApplied && DMIsDockIcon((UIView \*)self) && DMDockSideInHost((UIView \*)self);' $D"
check "the hover magnification passes Edit Home Screen's icon views by: each keeps the size and place it is fitted to (EPFit), and our items' scale with their own view; their own writes start no magnification again (audit 1.8.3 M1: they jumped to full icon size, off centre)" \
  "fn 'static void DMCollectIcons(UIView *root, Class iconClass, NSMutableArray *out) {' $D && sed -n 3p \$W/fn | grep -q 'if (DMEditProxyIs(v)) continue;' \
   && fn '- (void)setTransform:(CGAffineTransform)t {' $D && grep -q 'BOOL dockIcon = DMIsDockIcon((UIView \*)self) && !DMEditProxyIs((UIView \*)self);' \$W/fn \
   && [ \$(grep -c 'gHovering && !gApplying.*&& dockIcon' \$W/fn) = 2 ] && ! grep -q 'DMIsDockIcon((UIView \*)self)) {' \$W/fn"
check "L1 (review 1.8.3.1): in Edit Home Screen the Launchpad stand-in magnifies on hover, from the hidden App Library icon's centre, over its fit" \
  "fn 'static void EPFit(UIView *proxy, CGRect want, CGAffineTransform over) {' $E && grep -q 'objc_setAssociatedObject(proxy, kEPFitKey, \\[NSValue valueWithBytes:&fit objCType:@encode(EPFitInfo)\\]' \$W/fn \
   && grep -q 'MSBDEditProxyCentre(fit.mid.x, fit.off.x, k, 1.0)' \$W/fn \
   && fn 'void DMEditProxyMagnify(UIView *library, CGFloat s) {' $E && grep -q 'CGAffineTransformMakeScale(f.k \\* s, f.k \\* s), f.over' \$W/fn && grep -q 'MSBDEditProxyCentre(f.mid.x, f.off.x, f.k, s)' \$W/fn \
   && fn 'static void EPFollow(UIView *proxy, UIView *library) {' $E && grep -q 'CGAffineTransform t = CGAffineTransformIdentity;' \$W/fn \
   && fn '- (void)dm_apply {' $D && grep -q 'if (gInfluence > 0.0) { CGPoint c = \\[icon.superview convertPoint:icon.center toView:self\\]; s = DMScale(gSmoothX - c.x); }' \$W/fn \
   && grep -q 'DMEditProxyMagnify(icon, s);' \$W/fn"
TR=../dock/TrashIcon.m
check "N2 (regression 1.8.4, W-1 on the iPad 2): the Trash filled or emptied while the Home Screen is edited shows its new picture on its stand-in at once -- the count draws the bin again, its new picture lays the Dock out again while editing, and that layout makes the stand-in again for the Trash's new item" \
  "awk '/^- \(void\)dm_setCount:\(NSUInteger\)n \{/,/^\}/' $TR | grep -q '\[self dm_refreshLook:YES\]' \
   && awk '/^- \(void\)dm_refreshLook:\(BOOL\)animated \{/,/^\}/' $TR | grep -q 'completion:\^(BOOL finished) { DMDockItemPictureChanged(self); }' \
   && fn 'void DMDockItemPictureChanged(UIView *item) {' $D && grep -q 'if (dc && \[v isKindOfClass:dc\]) dock = v;' \$W/fn && grep -q 'if (platter && dock && DMEditProxiesOn(platter)) \[dock setNeedsLayout\];' \$W/fn \
   && grep -q 'if (platter && DMEditProxiesOn(platter)) DMEditProxiesApply(platter, YES, NO, gLaunchpadIcon, gLaunchpadClassic, NO);' $D \
   && fn 'void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadIcon, BOOL launchpadClassic, BOOL logAlways) {' $E && grep -q 'BOOL full = \[EPGet(trash, @\"count\") integerValue\] > 0;' \$W/fn \
   && grep -q 'if (trash) EPCoverOurs(trash, kMSBDEditTrash, MSBDEditIconItem(kMSBDEditTrash, launchpadClassic, full), model, editing, animated, platter);' \$W/fn \
   && fn 'static void EPCoverOurs(UIView *v, int view, int item, UIView *model, BOOL editing, BOOL animated, UIView *platter) {' $E && grep -q 'if (proxy && editing && \[objc_getAssociatedObject(proxy, kEPItemKey) intValue\] != item) {' \$W/fn"
exit $fails
