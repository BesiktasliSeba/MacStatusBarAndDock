#!/bin/bash
# Mac test of where a touch goes around our native windows (statusbar/NativeWindow.h, statusbar/StatusBar.x), as built. 1.7.7 fix round:
# - the layer's hit test gives no touch to a native window while the windows are faded out of the way (App Library, an icon menu, the App
#   Switcher, Guided Access): the layer sits over the Home Screen's window, and every App Library tap over a native window went nowhere (iPad 2
#   16.7.7, M1 15.6.1);
# - the Dock's window lets the band above its platter go to an active native window, but never a touch while a Dock icon's menu is open: its
#   rows over Activity Monitor's own window, and a tap beside the menu, went to that window and the menu stayed open (iPad 2 16.7.7);
# - while a Dock icon's menu is open, an active native window stands just under the Dock's window that holds it, on every engine: on Aerial it
#   stood at 1034, over the Dock's window (25), and Activity Monitor's own Dock menu opened behind its window, its rows and a tap beside it going
#   to the window (M1 15.6.1, 1.7.7 RC); the native windows are placed after the engine's windows, so the menu's close puts them back over them.
set -e
cd "$(dirname "$0")"
N=../statusbar/NativeWindow.h; S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$N"; }
fns() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
check "the layer's hit test: faded out of the way, no window takes a touch -- before any window is asked" \
  "fnn 'static id DMNativeLayerHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {' | awk '/if \\(gNativeAway\\) return nil;/&&!a{a=NR} /for \\(DMNativeWindow \\*w in \\[gNativeWindows reverseObjectEnumerator\\]\\)/{b=NR} END{exit !(a && b > a)}'"
check "  ... a Finder item menu or a sheet presented over the windows keeps its touches (asked first, as before)" \
  "fnn 'static id DMNativeLayerHitTest(UIWindow *self, SEL _cmd, CGPoint p, UIEvent *e) {' | awk '/if \\(gOverlay && gOverlay.superview/{a=NR} /if \\(self.rootViewController.presentedViewController\\)/{b=NR} /if \\(gNativeAway\\) return nil;/&&!c{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... the away state is the one the fade sets with the windows' own touches off (DMNativeTick)" \
  "grep -q '^static BOOL gNativeAway = NO;' $S && grep -q 'gNativeRotator.userInteractionEnabled = !away;' $S && [ \$(grep -n '^static BOOL gNativeAway = NO;' $S | cut -d: -f1) -lt \$(grep -n '#include \"NativeWindow.h\"' $S | cut -d: -f1) ]"
check "the Dock's window keeps every touch while a Dock icon's menu is open (its rows, UIKit's fallback view that closes it), before it lets the band above its platter go" \
  "awk '/^%hook SBFloatingDockWindow/{f=1} f&&/if \\(gDockMenuOpen\\) return h;/{a=NR} f&&/return DMNativeWindowAtScreenPoint\\(sp\\) \\? nil : h;/{c=NR} f&&/^%end/{exit} END{exit !(a && c > a)}' $S && grep -q '^static BOOL gDockMenuOpen = NO;' $S && grep -q 'if (!gDockMenuOpen) { gDockMenuOpen = YES; DMLog(@\"\\[lights\\] dock menu opened' $S"
check "a Dock icon's menu, open: the native windows' level is capped just under the Dock's window that holds it (DMNativeFrontLevel)" \
  "fnn 'static CGFloat DMNativeFrontLevel(void) {' | awk '/UIWindow \\*dockMenuHost = gDockMenuOpen \\? gDockMenuWindow : nil;/{a=NR} /if \\(dockMenuHost && dockMenuHost != gNativeLayer\\) want = MIN\\(want, dockMenuHost.windowLevel - 0.5\\);/{b=NR} /return want;/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... the menu's window is recorded before the levels are applied when it opens, and forgotten when it closes (and by the safety reset)" \
  "awk '/^%hook _UIContextMenuContainerView/{f=1} f&&/gDockMenuWindow = w;/{a=NR} f&&/DMApplyWindowLevel\\(\\);/&&!b{b=NR} f&&/gDockMenuOpen = NO; gDockMenuWindow = nil;/{c=NR} f&&/^%end/{exit} END{exit !(a && b > a && c > b)}' $S && grep -q 'if (!present) { gDockMenuOpen = NO; gDockMenuWindow = nil;' $S && [ \$(grep -n '^static __weak UIWindow \\*gDockMenuWindow = nil;' $S | cut -d: -f1) -lt \$(grep -n '#include \"NativeWindow.h\"' $S | cut -d: -f1) ]"
check "  ... the native windows are placed after the engine's windows (Zetsu's, Aerial's or MilkyWay's layer), once" \
  "fns 'static void DMApplyWindowLevel(void) {' | awk '/DMZetsuApplyLevels\\(\\);/{a=NR} /layer.windowLevel = want;/{b=NR} /DMNativeApplyLevel\\(\\);/{c=NR; n++} END{exit !(a && b && c > a && c > b && n == 1)}'"
[ $fails = 0 ] && echo "test-nativetouch: all checks pass" || { echo "test-nativetouch: checks FAILED"; exit 1; }
