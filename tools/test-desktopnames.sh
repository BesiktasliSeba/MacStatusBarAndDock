#!/bin/bash
# Mac test of the desktop icons' names (statusbar/DesktopNames.h, test-desktopnames.m; 1.7.2 item 16): an icon's own Hide Name kept by name --
# a move on the desktop, a respring, a rename here or elsewhere --, forgotten when the item leaves the desktop; Settings' switch for every name.
# Then the wiring as built: where Desktop.h reads, follows and writes the record, what hiding a name changes (the name only), the menu's row,
# the Settings row.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tdn" test-desktopnames.m
"$W/tdn"
D=../statusbar/Desktop.h
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$D"; }
check "the record: read once from the desktop's plist (hiddenNames), written with the places (off the main thread, -dm_syncPlaces)" \
  "grep -q 'CFPreferencesCopyValue(CFSTR(\"hiddenNames\"), kDesktopDomain' $D && fn '- (void)dm_saveNames {' | grep -q 'CFPreferencesSetValue(CFSTR(\"hiddenNames\"), (__bridge CFPropertyListRef)DMNamesHiddenToStore(_hiddenNames), kDesktopDomain' && fn '- (void)dm_saveNames {' | grep -q 'dm_syncPlaces'"
check "every listing: renames made elsewhere followed by inode, items gone forgotten -- against the last listing's inodes, before they are replaced; a failed listing forgets nothing" \
  "fn '- (void)dm_setItems:(NSArray<DMFinderItem *> *)items inodes:(NSDictionary *)inodes returned:(NSDictionary *)returned {' | awk '/DMNamesHiddenFollowListing\\(_hiddenNames, names, inodes, _inodes, _folderMissing \\|\\| _listFailed\\)\\) \\[self dm_saveNames\\];/{a=NR} /_inodes = inodes;/{b=NR} END{exit !(a && b && a < b)}'"
check "the desktop's own rename: the new name at once (DMNamesHiddenRenaming, with the names there now)" \
  "fn '- (void)dm_endRename:(BOOL)commit {' | grep -q 'DMNamesHiddenRenaming(_hiddenNames, path.lastPathComponent, t, '"
check "each icon: its name shown or not from the record and Settings' switch, on every listing and when either changes" \
  "fn '- (void)dm_setItems:(NSArray<DMFinderItem *> *)items inodes:(NSDictionary *)inodes returned:(NSDictionary *)returned {' | grep -q 'v.nameHidden = !DMNameShows(_hiddenNames, it.name, gDesktopHideNames);' && grep -q '^- (void)dm_applyNames { for (NSString \\*n in _views) _views\\[n\\].nameHidden = !DMNameShows(_hiddenNames, n, gDesktopHideNames); }' $D"
check "a hidden name: the name and its selection capsule only -- the frame (its place, its touch area) is never changed by it" \
  "fn '- (void)dm_look {' | grep -q '_label.hidden = _nameHidden;' && fn '- (void)dm_look {' | grep -q '_labelBack.hidden = !_selected || _nameHidden;' && ! fn '- (void)layoutSubviews {' | grep -q 'nameHidden'"
check "  ... VoiceOver still reads the name (the item's own, not the label's visibility)" \
  "grep -q '^- (NSString \\*)accessibilityLabel { return self.item.display.length ? self.item.display : self.label.text; }' $D"
check "  ... the lifted preview: the icon alone when its name is hidden" \
  "fn '- (UITargetedPreview *)dm_previewFor:(UIContextMenuInteraction *)i {' | grep -q 'if (!v.nameHidden) shape = CGRectUnion(shape, v.labelBack.frame);'"
check "the menu: Hide Name / Show Name (Names for a selection), greyed while Settings hides every name" \
  "fn '- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {' | grep -q '@\"Show Names\" : @\"Show Name\") : (many ? @\"Hide Names\" : @\"Hide Name\")' && fn '- (UIMenu *)dm_menuFor:(DMDesktopItemView *)v at:(CGPoint)sp {' | grep -q 'if (gDesktopHideNames) hn.attributes = UIMenuElementAttributesDisabled;'"
check "Settings' switch: read with Show Desktop Icons (the Finder notification), off unless set, applied to the icons at once" \
  "fn 'static BOOL DMDesktopHideNamesPref(void) {' | grep -q 'CFSTR(\"desktopHideNames\")' && fn 'static void DMDesktopApplyPref(void) {' | grep -q '\\[gDesktop dm_applyNames\\];' && grep -q '^static BOOL gDesktopHideNames = NO;' $D"
check "  ... the row: Hide Desktop Icon Names, right after Show Desktop Icons, off by default, the same notification" \
  "python3 -c \"
import plistlib,sys
items=plistlib.load(open('../statusbar/macstatusbarprefs/Resources/Root.plist','rb'))['items']
i=[k for k,x in enumerate(items) if x.get('key')=='desktopIcons'][0]; r=items[i+1]
sys.exit(0 if r.get('key')=='desktopHideNames' and r.get('label')=='Hide Desktop Icon Names' and r.get('default') is False and r.get('defaults')=='com.besiktasliseba.macstatusbar' and r.get('PostNotification')==items[i].get('PostNotification') and r.get('cell')=='PSSwitchCell' else 1)\""
check "  ... left out with Show Desktop Icons where the desktop's 17+ check failed; greyed while Finder or Show Desktop Icons is off" \
  "grep -q 'isEqual:@\"desktopIcons\"\\] || \\[\\[spec propertyForKey:@\"key\"\\] isEqual:@\"desktopHideNames\"\\]' ../statusbar/macstatusbarprefs/MSBRootListController.m && grep -q 'for (NSString \\*k in @\\[@\"finderEnabled\", @\"desktopIcons\"\\])' ../statusbar/macstatusbarprefs/MSBRootListController.m"
check "a crash in DesktopNames.h is the desktop's (its switch), as Desktop.h's" \
  "grep -qxF 'file MacStatusBarCore ^Desktop(Names)?\\.h\$ desktopIcons' crashmap-rules.txt"
[ $fails = 0 ] && echo "test-desktopnames: wiring checks pass" || { echo "test-desktopnames: wiring checks FAILED"; exit 1; }
