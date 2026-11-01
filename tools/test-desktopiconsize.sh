#!/bin/bash
# Mac test of the desktop icons' size (common/DesktopIconSize.h, test-desktopiconsize.c; 1.7.5 item 4: Settings > Desktop > Icon Size), then the
# wiring as built: the slider in Desktop.plist, Settings' reading and writing of it, SpringBoard's side, cell and live change, places kept.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tdis" test-desktopiconsize.c
"$W/tdis"
D=../statusbar/Desktop.h
R=../statusbar/macstatusbarprefs/MSBRootListController.m
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "the slider: desktopIconSize in Mac Status Bar's domain, the header's range, under an Icon Size group, posting the Finder notification as its rows do" \
  "python3 -c \"
import plistlib,sys,re
items=plistlib.load(open('../statusbar/macstatusbarprefs/Resources/Desktop.plist','rb'))['items']
h=open('../common/DesktopIconSize.h').read()
mn=float(re.search(r'#define MSBD_DESKTOP_ICON_MIN ([0-9.]+)',h).group(1)); mx=float(re.search(r'#define MSBD_DESKTOP_ICON_MAX ([0-9.]+)',h).group(1))
i=[k for k,x in enumerate(items) if x.get('key')=='desktopIconSize'][0]; s=items[i]; g=items[i-1]
ok=s.get('cell')=='PSSliderCell' and s.get('defaults')=='com.besiktasliseba.macstatusbar' and float(s.get('min'))==mn and float(s.get('max'))==mx and s.get('id')=='DESKTOP_ICON_SIZE'
ok=ok and s.get('PostNotification')=='com.besiktasliseba.macstatusbar.finder.pref' and g.get('cell')=='PSGroupCell' and g.get('label')=='Icon Size' and not s.get('showValue')
sys.exit(0 if ok else 1)\""
check "Settings shows the size in force (the stored step, else the Home Screen's as SpringBoard published it)" \
  "grep -q 'isEqual:@MSBD_DESKTOP_ICON_KEY\]) return @(MSBDesktopIconShownNow());' $R && fn 'static uint64_t MSBDesktopHomeState(void) {' $R | grep -q 'notify_register_check(MSBD_DESKTOP_HOMESIDE_STATE, &token)' && fn 'static double MSBDesktopIconShownNow(void) {' $R | grep -q 'return MSBDDesktopIconShown(n != nil, n.doubleValue, MSBDesktopHomeState());'"
check "Settings writes a 4 pt step, and only a new one (one notification per step while the slider is dragged; the store read once, not per move)" \
  "grep -q 'double side = \[value respondsToSelector:@selector(doubleValue)\] ? MSBDDesktopIconSnap(\[value doubleValue\]) : 0.0;' $R && grep -q 'if (want == gMSBDesktopIconWritten) return;' $R && grep -q 'if (want > 0.0) { \[super setPreferenceValue:@(want) specifier:specifier\]; return; }' $R && grep -q 'if (gMSBDesktopIconWritten < 0) { NSNumber \*n = MSBDesktopIconStored();' $R && grep -q '	gMSBDesktopIconWritten = -1;' $R"
check "  ... the Home Screen's own step is 'the same as the Home Screen' again: nothing stored (the way back to never set)" \
  "grep -q 'double want = home > 0.0 && MSBDDesktopIconSnap(home) == side ? 0.0 : side;' $R && grep -q 'CFPreferencesSetAppValue(CFSTR(MSBD_DESKTOP_ICON_KEY), NULL, kMSBBarDomain);' $R"
check "  ... greyed while Finder or Show Desktop Icons is off, as Hide Desktop Icon Names" \
  "fn '- (void)msb_updateDesktopNamesRow:(BOOL)reload {' $R | grep -q 'isEqualToString:@\"DESKTOP_ICON_SIZE\"'"
check "SpringBoard reads it with the Finder notification (snapped; 0 = never set) and changes the desktop live" \
  "fn 'static double DMDesktopIconSizePref(void) {' $D | grep -q 'MSBDDesktopIconSnap(' && fn 'static void DMDesktopApplyPref(void) {' $D | grep -q 'if (size != gDesktopIconSize) { gDesktopIconSize = size; \[gDesktop dm_iconSizeChanged\]; }'"
check "the side: Settings' size when set, else the Home Screen's as always; the Home Screen's published for Settings; the cell from the same formula" \
  "fn '- (void)dm_measure {' $D | grep -q '_side = MSBDDesktopIconSide(gDesktopIconSize > 0, gDesktopIconSize, best, _side);' && fn '- (void)dm_measure {' $D | grep -q 'notify_set_state(homeToken, st)' && fn '- (void)dm_measure {' $D | grep -q 'MSBDDesktopIconCell(_side, _font.lineHeight, &cw, &ch);' && ! fn '- (void)dm_measure {' $D | grep -q '_cellW = MAX('"
check "a size change keeps every stored place (nothing written to the places; the placing pass finds where each icon fits now)" \
  "fn '- (void)dm_iconSizeChanged {' $D | grep -q '\[self dm_placeAgain\];' && ! fn '- (void)dm_iconSizeChanged {' $D | grep -qE '_places|dm_savePlaces|dm_fractionFor'"
check "  ... the pictures drawn again at the new size once the slider rests (0.3 s after the last step)" \
  "fn '- (void)dm_iconSizeChanged {' $D | grep -q '(0.3 \* NSEC_PER_SEC)' && fn '- (void)dm_iconSizeChanged {' $D | grep -q 'v.icon.image = \[s dm_imageFor:it view:v\]'"
check "  ... and the placing pass gives every icon the new cell (its bounds) and side" \
  "awk '/^- \\(void\\)layoutSubviews \\{/{n++} n == 2 {print} n == 2 && /^}/ {exit}' $D | grep -q 'v.bounds = CGRectMake(0, 0, _cellW, _cellH); v.side = _side;'"
check "Home Screen app icons are never touched by it (no app icon view is resized by the desktop)" \
  "! grep -nE 'SBIconView.*(setFrame|setBounds|iconImageSize.*=)' $D"
[ $fails = 0 ] && echo "test-desktopiconsize: wiring checks pass" || { echo "test-desktopiconsize: wiring checks FAILED"; exit 1; }
