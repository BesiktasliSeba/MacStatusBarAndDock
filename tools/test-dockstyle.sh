#!/bin/bash
# Mac test of Dock Style (1.8.4 item 3): the plain C (common/DockStyle.h, test-dockstyle.c) -- every look drawn too (DOCKSTYLE_PNG=<folder> keeps
# the pictures to look at) -- and the wiring in the Dock (dock/DockStyle.m, Dock.x, RunningIndicator.m, FinderIcon.m) and Settings. The reflections'
# picture lookup runs as built (test-dockstylepicture.m; MSBD_TEST_DOCKSTYLE_M: another copy of DockStyle.m, to see it fail on it).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -framework ImageIO -framework CoreFoundation -o "$W/tds" test-dockstyle.c && "$W/tds" ${DOCKSTYLE_PNG:-} || fails=1
S=${MSBD_TEST_DOCKSTYLE_M:-../dock/DockStyle.m}; D=../dock/Dock.x; R=../dock/RunningIndicator.m; F=../dock/FinderIcon.m; P=../dock/dockmagnificationprefs/Resources/Root.plist
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
{ fn "$S" 'static BOOL DMStyleShape(id o, const char *sel, const char *enc) {'; fn "$S" 'static BOOL DMStyleIsPicture(UIView *v) {'; fn "$S" 'static BOOL DMStyleShownUnder(id v, UIView *icon) {'
  fn "$S" 'static UIView *DMStylePicture(UIView *icon) {'; fn "$S" 'static BOOL DMStyleLayerSettled(CALayer *l, int depth) {'; fn "$S" 'static BOOL DMStylePictureCommitted(UIView *pic) {'; fn "$S" 'static BOOL DMStylePictureDrawn(UIView *pic) {'; fn "$S" 'static NSString *DMStylePictureSignature(UIView *pic) {'
  grep -F 'static const void *kStyleViewKey = &kStyleViewKey' "$S"; grep -F 'static const void *kStylePicSigKey = &kStylePicSigKey;' "$S"; grep -F 'static const void *kStylePicWantKey = &kStylePicWantKey;' "$S"
  if grep -q '^void DMDockStylePictureDirty(UIView \*platter, UIView \*icon) {' "$S"; then fn "$S" 'void DMDockStylePictureDirty(UIView *platter, UIView *icon) {'
  else echo 'void DMDockStylePictureDirty(UIView *platter, UIView *icon) { (void)platter; (void)icon; }   // (not in this source: the reflection follows its value only)'; fi
  fn "$S" 'static void DMStyleSyncReflections(UIView *platter, DMDockStyleView *sv, NSArray<UIView *> *icons) {'
  if grep -q '^static void DMStyleRetake(' "$S"; then fn "$S" 'static void DMStyleRetake(DMDockStyleView *sv, NSArray<UIView *> *icons, double delay, double thenDelay) {'; fi
  fn "$S" 'static void DMStyleConfirmReflections(DMDockStyleView *sv, int tries) {'; } > "$W/dockstylepicture-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -framework CoreGraphics -o "$W/tdp" test-dockstylepicture.m && "$W/tdp" || fails=1
check "Settings > Dock: Dock Style (dockStyle: Default, Glass Shelf, Frosted; Default never written), right after Position" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('DOCK_STYLE'); s=it[i]
pos=[k for k,x in enumerate(it) if x.get('key')=='dockPosition'][0]
sys.exit(0 if s['key']=='dockStyle' and s['default']=='default' and s['cell']=='PSLinkListCell' and s['validValues']==['default','glass','frosted'] and s['validTitles']==['Default','Glass Shelf','Frosted'] and s['label']=='Dock Style' and s['defaults']=='com.besiktasliseba.dockmagnification' and s['PostNotification']=='com.besiktasliseba.dockmagnification/prefsChanged' and i==pos+2 and it[i-1]['cell']=='PSGroupCell' else 1)\""
check "the Dock reads it (MSBDDockStyleFromString), Default with the Dock part off; a change re-styles every platter at once" \
  "fn $D 'static void DMLoadPrefs(' | grep -q 'DMDockStyleSetChoice(tweakOn ? style : MSBDDockStyleDefault);' && awk '/^static void DMPrefsChanged\(/,/^}/' $D | grep -q 'DMDockStyleRefreshAll();'"
check "our look lives at the back of the platter, laid out with it (its -layoutSubviews); Default: nothing of ours, iPadOS's background and shadow given back" \
  "awk '/^%hook SBFloatingDockPlatterView/,/^%end/' $D | tr -d '\n' | grep -q -- '- (void)layoutSubviews {    %orig;    DMDockStyleApply((UIView \*)self);}' \
   && fn $S 'void DMDockStyleApply(' | grep -q 'if (sv.superview != platter) \[platter insertSubview:sv atIndex:0\];' && fn $S 'void DMDockStyleApply(' | grep -q 'DMStyleHideApple(platter, NO);'"
check "  ... iPadOS's background and shadow read only in their getter's shape, hidden by our mask and given back exactly (L3)" \
  "fn $S 'static UIView *DMStyleGet(' | grep -q 'if (!DMStyleShape(o, sel, \"@16@0:8\")) return nil;' && fn $S 'static void DMStyleHideApple(' | grep -q 'view.layer.mask = ours;'"
check "  ... at a side the look is the side's (Glass Shelf: the dark panel), from the platter's own place in the turned view" \
  "grep -q '^int DMDockStylePlatterSide(UIView \*platter) { return gDockSideApplied && platter && DMDockSideInHost(platter) ? gDockSideApplied : 0; }' $D \
   && grep -q 'static int DMStyleLookFor(UIView \*platter) { return MSBDDockStyleLook(gDockStyle, DMDockStylePlatterSide(platter)); }' $S"
check "nothing of ours takes a touch, moves an icon or changes a transform of Apple's views (magnification, the side turn, the bounce stay as they are)" \
  "grep -q 'self.userInteractionEnabled = NO;' $S && ! grep -E 'icon\\.transform|icon\\.frame *=|sublayerTransform|icon\\.layer\\.position' $S"
check "the reflections follow the magnification frame by frame (Dock.x dm_apply), and are taken again only when the Dock lays out" \
  "grep -q '    DMDockStyleFollow(self);   // (Glass Shelf: the reflections follow' $D && fn $S 'void DMDockStyleFollow(' | grep -q 'DMStylePlaceReflections(sv);' \
   && fn $S 'void DMDockStyleApply(' | grep -q 'DMStyleSyncReflections(platter, sv, icons);'"
check "the open apps' lights: each running dot drawn as its Dock's look draws it (apps' and Finder's), today's dot back with Default and Frosted" \
  "grep -q '    DMDockStyleDot(dot, iconView, d);' $R && grep -q '    DMDockStyleDot(self.dot, self, d);' $F && fn $S 'void DMDockStyleDot(' | grep -q 'if (dot.layer.contents) { dot.layer.contents = nil; dot.backgroundColor = \[UIColor labelColor\]; }'"
check "L1 (review 1.8.4): a crash in Dock Style's code (DockStyle.m) sets only Dock Style back to Default -- not the whole Dock" \
  "grep -q '^file DockMagnification ^DockStyle\\\\.m\$ dockStyle\$' crashmap-rules.txt"
check "P2-L1 (review 1.8.4): with Default stored (\"default\") or nothing stored, Dock Style counts as off (offtext=default): such a crash is not pinned on it" \
  "grep -q '^target dockStyle pref com.besiktasliseba.dockmagnification dockStyle 0 0 offtext=default Dock Style|' crashmap-rules.txt"
check "  ... the platter's layout hook (every user's Dock runs through it) is transparent: a crash in Apple's code under it is never Dock Style's" \
  "grep -q '^sym DockMagnification \\\\\$SBFloatingDockPlatterView\\\\\$layoutSubviews\$ transparent\$' crashmap-rules.txt"
check "L2 (review 1.8.4): with Default and nothing of ours ever put on a platter, its layout asks nothing (it returns before any read)" \
  "fn $S 'void DMDockStyleApply(' | awk '/if \\(gDockStyle == MSBDDockStyleDefault && !objc_getAssociatedObject\\(platter, kStyleViewKey\\) && !objc_getAssociatedObject\\(platter, kStyleHidKey\\)\\) return;/{a=NR} /DMStyleLookFor\\(|DMStyleGet\\(|DMStyleHideApple\\(/{if(!b)b=NR} END{exit !(a && b && a < b)}'"
check "  ... and once everything is given back (Default again), the record goes, so the next layouts ask nothing either" \
  "fn $S 'static void DMStyleHideApple(' | grep -q 'if (!hide && was) objc_setAssociatedObject(platter, kStyleHidKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);'"
check "L3 (review 1.8.4): iPadOS's background and shadow are hidden by an empty mask of ours, never by their alpha (iPadOS's own, never read or put back)" \
  "! fn $S 'static void DMStyleHideApple(' | grep -q 'alpha' && fn $S 'static void DMStyleHideApple(' | grep -q 'view.layer.mask = ours;'"
check "  ... the mask they had (normally none) is kept -- or the one iPadOS sets meanwhile -- and is what Default gives back" \
  "fn $S 'static void DMStyleHideApple(' | grep -q 'was\\[key\\] = view.layer.mask ?: \\[NSNull null\\];' && fn $S 'static void DMStyleHideApple(' | grep -q 'if (view.layer.mask == ours) view.layer.mask = own == \\[NSNull null\\] ? nil : own;'"
check "L4 (review 1.8.4): a style change draws every running dot again at once (the apps' and Finder's), not at the next running-apps change" \
  "fn $S 'void DMDockStyleRefreshAll(' | grep -q 'DMRunningIndicatorResyncAll();' && fn $S 'void DMDockStyleRefreshAll(' | grep -q 'updateDot' \
   && grep -q '^void DMRunningIndicatorResyncAll(void) { RIResyncDock(); }' $R"
check "L10 (review 1.8.4): a magnification frame only moves the reflections it has (no walk of the Dock's views); a layout snapshots a picture again only when it changed" \
  "! fn $S 'void DMDockStyleFollow(' | grep -q 'DMStyleIcons(' && fn $S 'void DMDockStyleFollow(' | grep -q 'DMStylePlaceReflections(sv);' \
   && fn $S 'static void DMStyleSyncReflections(' | grep -q 'DMStylePictureSignature(pic)'"
check "P2-M1 (review 1.8.4): a layout records no picture's value (it only wants one, MSBDReflectionAtLayout); the confirm records it, from a snapshot it takes of a drawn picture" \
  "! fn $S 'static void DMStyleSyncReflections(' | grep -q 'kStylePicSigKey, sig' && fn $S 'static void DMStyleSyncReflections(' | grep -q 'int act = MSBDReflectionAtLayout(pic != nil, recordedSame, wantedSame, drawn);' \
   && fn $S 'static void DMStyleSyncReflections(' | grep -q 'BOOL drawn = pic && !recordedSame && !wantedSame && DMStylePictureDrawn(pic);' \
   && fn $S 'static void DMStyleConfirmReflections(' | grep -q 'int act = MSBDReflectionAtConfirm(pic != nil, pic && DMStylePictureDrawn(pic), tries, pic && DMStylePictureCommitted(pic));' \
   && fn $S 'static void DMStyleConfirmReflections(' | grep -q 'if (act == MSBDReflRecord && !DMStyleReflectionTake(holder, pic))' \
   && fn $S 'static void DMStyleConfirmReflections(' | grep -q 'objc_setAssociatedObject(holder, kStylePicSigKey, DMStylePictureSignature(pic), OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \
   && fn $S 'static BOOL DMStylePictureCommitted(' | grep -q 'return pic.window != nil && pic.layer.presentationLayer != nil && DMStyleLayerSettled(pic.layer, 2);' \
   && fn $S 'static BOOL DMStylePictureDrawn(' | grep -q 'return DMStylePictureCommitted(pic);'"
check "no snapshot ever forces the screen's updates (a forced one put a black band on the TV for one frame: regression 1.8.4, A12Z TV rows): the screen as it is, at a layout and at a confirm; the behaviour is test-dockstylepicture.m's, through the confirm as built" \
  "fn $S 'static BOOL DMStyleReflectionTake(' | grep -q 'UIView \\*snap = \\[pic snapshotViewAfterScreenUpdates:NO\\];' && ! grep -v '^ *//' $S | grep -q 'snapshotViewAfterScreenUpdates:YES\\|snapshotViewAfterScreenUpdates:afterUpdates' \
   && fn $S 'static void DMStyleSyncReflections(' | grep -q 'if (act & MSBDReflTakeNow) DMStyleReflectionTake(holder, pic);'"
check "  ... and no confirm while the screen is asleep (a blank snapshot recorded for good): it runs again when the screen comes on" \
  "fn $S 'static void DMStyleConfirmReflections(' | awk '/if \\(DMStyleScreenOff\\(sv\\)\\) return;/{a=NR} /performWithoutAnimation/{if(!b)b=NR} END{exit !(a && b > a)}' \
   && fn $S 'static BOOL DMStyleScreenOff(' | grep -q 'notify_register_dispatch(\"com.apple.springboard.hasBlankedScreen\"' && fn $S 'static BOOL DMStyleScreenOff(' | grep -q 'for (DMDockStyleView \\*v in waiting) DMStyleConfirmSoon(v, 0);'"
check "  ... the confirm runs on the main run loop's next turn (the layout's commit has drawn the icons), again later while one waits, the last asked only" \
  "fn $S 'static void DMStyleConfirmSoon(' | grep -q 'if (tries <= 0) dispatch_async(dispatch_get_main_queue(), run);' && fn $S 'static void DMStyleConfirmSoon(' | grep -q 'MSBDReflectionRetryDelay(tries)' \
   && fn $S 'static void DMStyleConfirmSoon(' | grep -q 'if (s && s.confirmGen == gen) DMStyleConfirmReflections(s, tries);' && fn $S 'static void DMStyleConfirmReflections(' | grep -q 'if (waiting && tries + 1 < MSBD_REFLECTION_TRIES) DMStyleConfirmSoon(sv, tries + 1);'"
check "  ... a reflection is kept (hidden) when its picture is missing at a layout, and put back in the shelf when it left it" \
  "fn $S 'static void DMStyleSyncReflections(' | grep -q 'if (act & MSBDReflHide) { holder.hidden = YES; confirm = YES; continue; }' \
   && fn $S 'static void DMStyleSyncReflections(' | grep -q 'if (holder.superview != sv.reflections) \\[sv.reflections addSubview:holder\\];' && ! fn $S 'static void DMStyleSyncReflections(' | grep -q 'if (!pic) continue;'"
L=../dock/Launchpad.m; TR=../dock/TrashIcon.m
check "F1 (regression 1.8.4, D-1 on the A12Z): one of our items with a new picture lays the Dock out again for it -- with Glass Shelf the platter (its layout reads every picture again), while the Home Screen is edited the Dock (the stand-ins)" \
  "fn $D 'void DMDockItemPictureChanged(' | grep -q 'if (platter && DMDockStyleReflects(platter)) { DMDockStylePictureDirty(platter, item); \[platter setNeedsLayout\]; }' \
   && fn $D 'void DMDockItemPictureChanged(' | grep -q 'if (platter && dock && DMEditProxiesOn(platter)) \[dock setNeedsLayout\];' \
   && fn $S 'BOOL DMDockStyleReflects(' | grep -q 'return sv && sv.look == MSBDDockLookShelf;' && grep -q '^void DMDockItemPictureChanged(UIView \*item);' ../dock/DMIconTheme.h"
check "  ... the Launchpad tile (Launchpad Icon switched in Settings, a theme engine's reload): what it shows read before and after each drawing, a change told" \
  "fn $L 'void DMLaunchpadRefresh(' | awk '/DMLaunchpadShown before = DMLaunchpadShownNow\(imageView\);/{a=NR} /DMLaunchpadDraw\(imageView, overlay, enabled, classic\);/{b=NR} /if \(!DMLaunchpadShownSame\(before, DMLaunchpadShownNow\(imageView\)\)\) DMDockItemPictureChanged\(iconView\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $L 'static DMLaunchpadShown DMLaunchpadShownNow(' | grep -q 'o.superview == imageView, imageView.layer.masksToBounds, hidden.count,'"
check "  ... the Trash (filled, emptied, Eject, a theme): told once its new picture is in -- after a cross-fade at its end (a reflection taken during one keeps a mix)" \
  "awk '/^- \(void\)dm_refreshLook:\(BOOL\)animated \{/,/^\}/' $TR | grep -q 'completion:\^(BOOL finished) { DMDockItemPictureChanged(self); }' \
   && awk '/^- \(void\)dm_refreshLook:\(BOOL\)animated \{/,/^\}/' $TR | grep -q 'else { self.image.image = want; DMDockItemPictureChanged(self); }'"
check "  ... Finder and Downloads: a picture their own layout changed (a theme engine's reload) told" \
  "( for f in $F ../dock/Downloads.m; do grep -B2 -A3 -F 'UIImage *was = self.image.image;' \$f | tr -d '\n' | grep -q -- '- (void)layoutSubviews {    \[super layoutSubviews\];    UIImage \*was = self.image.image;    \[self dm_layoutPicture\];    if (self.image.image != was) DMDockItemPictureChanged(self);' || exit 1; done )"
check "Settings > Dock: the Portrait group's footer says what Larger Dock in Portrait does to Icon Size (KT 9 Nov: the slider seemed to do nothing in portrait)" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; i=[k for k,x in enumerate(it) if x.get('key')=='portraitLargerDock'][0]; g=it[i-1]
sys.exit(0 if g.get('cell')=='PSGroupCell' and g.get('label')=='Portrait' and g.get('footerText')=='In portrait, the Dock uses all its room. Icon Size applies in landscape, or with this switch off.' else 1)\""
check "DockStyle.m is built into the Dock part; a release-build feature marker on its look" \
  "grep -q '^DockMagnification_FILES = .* DockStyle.m' ../dock/Makefile && fn $S 'void DMDockStyleApply(' | grep -q 'DM_FEATURE_MARK(\"dock-style\");'"
check "no Apple picture: no image file read or shipped for the styles (everything drawn in code)" "! grep -E 'imageNamed|imageWithContentsOfFile|\\.png' $S ../common/DockStyle.h"
check "no em dash in the styles' code, test or Settings text" "! grep -q \$'\\xe2\\x80\\x94' $S ../common/DockStyle.h test-dockstyle.c test-dockstylepicture.m && ! grep -q \$'\\xe2\\x80\\x94' $P"
[ $fails = 0 ] && echo "test-dockstyle: all checks pass" || { echo "test-dockstyle: checks FAILED"; exit 1; }
