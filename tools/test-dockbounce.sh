#!/bin/bash
# Mac test of Animate Opening Applications (1.8.4 item 2): the plain C (common/DockBounce.h, test-dockbounce.c) and the wiring in the Dock
# (dock/Bounce.m, Dock.x, RunningIndicator.m) and Settings (the switch, off by default).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -framework CoreGraphics -o "$W/tdb" test-dockbounce.c && "$W/tdb" || fails=1
B=../dock/Bounce.m; D=../dock/Dock.x; R=../dock/RunningIndicator.m; P=../dock/dockmagnificationprefs/Resources/Root.plist
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
check "Settings > Dock: Animate Opening Applications (animateOpening, on by default: KT 7 Nov), just before Recent Apps" \
  "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('ANIMATE_OPENING'); s=it[i]
j=[k for k,x in enumerate(it) if x.get('cell')=='PSGroupCell' and x.get('label')=='Recent Apps'][0]
sys.exit(0 if s['key']=='animateOpening' and s['default'] is True and s['cell']=='PSSwitchCell' and s['label']=='Animate Opening Applications' and s['defaults']=='com.besiktasliseba.dockmagnification' and s['PostNotification']=='com.besiktasliseba.dockmagnification/prefsChanged' and it[i-1]['cell']=='PSGroupCell' and j==i+1 else 1)\""
check "the Dock reads it as stored (MSBDAnimateOpeningOn), with the Dock part on only" \
  "fn $D 'static void DMLoadPrefs(' | grep -q 'DMBounceSetOn(MSBDAnimateOpeningOn(isBool, isBool && CFBooleanGetValue(ao)) && tweakOn);'"
check "the tap: -[SBIconView tapGestureDidChange:] hooked only in its 15-18 shape (v@:@), asked before the tap goes on, started after" \
  "grep -q 'if (!strcmp(shape, \"v@:@\")) %init(DMBounceTap);' $D && awk '/^%group DMBounceTap/,/^%end\$/' $D | tr -d '\n' | grep -q 'NSString \*bid = DMBounceTapWanted((UIView \*)self, g);    %orig;    DMBounceTapped((UIView \*)self, bid);'"
check "only a Dock icon of an app with no process yet, without Reduce Motion, not while editing, not a folder" \
  "fn $B 'NSString *DMBounceTapWanted(' | grep -q 'MSBDBounceWanted(gBounceOn, UIAccessibilityIsReduceMotionEnabled(), app != nil && known, pid > 0, DMBounceEditing());' \
   && fn $B 'NSString *DMBounceTapWanted(' | grep -q 'if (!DMBounceIsDockIcon(iconView)) return nil;' && fn $B 'NSString *DMBounceTapWanted(' | grep -q 'if (DMBounceBool(icon, \"isFolderIcon\")) return nil;'"
check "the bounce is one additive Core Animation loop on the icon's position (the magnification's transform and the side turn are left alone)" \
  "fn $B 'static CAKeyframeAnimation *DMBounceAnimation(' | grep -q 'animationWithKeyPath:@\"position.y\"' && fn $B 'static CAKeyframeAnimation *DMBounceAnimation(' | grep -q 'a.additive = YES;' \
   && ! grep -q '\\.transform = ' $B && ! grep -q 'sublayerTransform' $B"
check "  ... it lands at the end of a bounce from the same start (MSBDBounceEndsAt); its look runs only while an icon bounces" \
  "fn $B 'static void DMBounceLook(' | grep -q 'MSBDBounceEndsAt(b.start, now, fg, b.launched, gone, MSBD_BOUNCE_PERIOD, MSBD_BOUNCE_CAP, MSBD_BOUNCE_NO_LAUNCH);' \
   && fn $B 'static void DMBounceLook(' | grep -q 'DMBounceAnimation(-b.height, b.layerStart, cycles)' && fn $B 'static void DMBounceLook(' | grep -q 'dispatch_source_cancel(gBounceLook); gBounceLook = nil;'"
check "  ... its window shown = SpringBoard's process state of the app turning foreground, read only in its shapes" \
  "fn $B 'static BOOL DMBounceProcess(' | grep -q 'DMBounceShape(object_getClass(st), \"isForeground\", \"B16@0:8\", NO)' && fn $B 'static BOOL DMBounceProcess(' | grep -q 'DMBounceShape(object_getClass(app), \"processState\", \"@16@0:8\", NO)'"
check "  ... the running dot holds still under it (RunningIndicator.m gives it)" \
  "grep -q '^UIView \*DMRunningDotOf(UIView \*iconView) { return iconView ? objc_getAssociatedObject(iconView, kDotKey) : nil; }' $R && fn $B 'static void DMBounceHoldDot(' | grep -q 'DMBounceAnimation(b.height, begin'"
check "M3 (review 1.8.4): an entry dropped without landing takes its bounce off the icon's layer and the dot's (kept in the entry: the view may be gone)" \
  "grep -q '@property (nonatomic, strong) CALayer \\*iconLayer, \\*dotLayer;' $B && fn $B 'static void DMBounceDrop(' | grep -q '\\[b.iconLayer removeAnimationForKey:kDMBounceKey\\];' \
   && fn $B 'static void DMBounceDrop(' | grep -q '\\[b.dotLayer removeAnimationForKey:kDMBounceKey\\];'"
check "  ... dropped when the icon leaves its window, and when the view now shows another app (SpringBoard reuses icon views)" \
  "fn $B 'static void DMBounceLook(' | grep -q 'if (!icon || !icon.window) { DMBounceDrop(b, @\"its icon left the window\"); continue; }' \
   && fn $B 'static void DMBounceLook(' | grep -q 'DMBounceDrop(b, @\"its icon view shows another app now\");'"
check "  ... and every bounce goes when the switch goes off" "fn $B 'void DMBounceSetOn(' | grep -q 'if (!on) DMBounceDropAll(@\"the switch went off\");'"
check "L4 (review 1.8.4 Pass 4): an app whose process came and went before its window showed (it crashed while opening) stops its bounce, as on a Mac" \
  "fn $B 'static void DMBounceLook(' | grep -q 'BOOL gone = b.launched && pid == 0;' && fn $B 'static void DMBounceLook(' | grep -q 'gone ? @\"its app quit before its window showed\"'"
check "L1 (review 1.8.4): a crash in the bounce's code (Bounce.m) turns only Animate Opening Applications off -- not the whole Dock" \
  "grep -q '^target animateOpening pref com.besiktasliseba.dockmagnification animateOpening 0 1 Animate Opening Applications|' crashmap-rules.txt && grep -q '^file DockMagnification ^Bounce\\\\.m\$ animateOpening\$' crashmap-rules.txt"
check "P2-L1 (review 1.8.4): the icon tap hook (every icon tap runs through it) is transparent: a crash in Apple's code under it is decided by the frame below, never the bounce's" \
  "grep -q '^sym DockMagnification \\\\\$SBIconView\\\\\$tapGestureDidChange\\\\\$\$ transparent\$' crashmap-rules.txt"
check "Bounce.m is built into the Dock part; a release-build feature marker on its start" \
  "grep -q '^DockMagnification_FILES = .* Bounce.m' ../dock/Makefile && fn $B 'static void DMBounceStart(' | grep -q 'DM_FEATURE_MARK(\"dock-launch-bounce\");'"
check "no em dash in its code, test or Settings text" "! grep -q \$'\\xe2\\x80\\x94' $B ../common/DockBounce.h test-dockbounce.c && ! grep -q \$'\\xe2\\x80\\x94' $P"
[ $fails = 0 ] && echo "test-dockbounce: all checks pass" || { echo "test-dockbounce: checks FAILED"; exit 1; }
