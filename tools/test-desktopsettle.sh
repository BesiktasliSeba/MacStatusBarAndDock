#!/bin/bash
# Mac test of the Desktop's icons for items still arriving (1.8.4.2, KT 9 Nov: an app dragged from Finder showed white until the next icon was added):
# the rule (common/DesktopSettle.h, test-desktopsettle.c) and the wiring in statusbar/Desktop.h, Finder.h, DesktopCorner.h.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O0 -Wall -o "$W/t" test-desktopsettle.c && "$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
D=../statusbar/Desktop.h; F=../statusbar/Finder.h; C=../statusbar/DesktopCorner.h
check "the desktop includes the rule" "grep -qF '#include \"../common/DesktopSettle.h\"' $D"
check "each listing notes which .app has no Info.plist saying which app it is yet" "grep -qF 'NSMutableSet *noBundle = [NSMutableSet set];' $D && grep -qF 's->_noBundle = noBundle;' $D"
check "an app drawn without its bundle is drawn again once it has come, whatever its date" "grep -qF 'if (!noBundle && [_drawnNoBundle containsObject:it.name]) { newItem = YES;' $D"
check "after every listing it lists again while something is arriving, through the rule, once at a time" \
  "grep -qF '[self dm_listAgainWhileArriving];' $D && grep -qF 'if (MSBDDesktopStillArriving(now, date, app, whole, since ? mono - since.doubleValue : 0, writtenFor, grew)) arriving = YES;' $D && grep -qF 'if (!arriving || _arrivingPending) return;' $D"
check "the end of a Finder move or copy reads the desktop's folder again" \
  "grep -qF 'if (gFinderDesktopFoldersChanged) gFinderDesktopFoldersChanged(want);' $F && grep -qF 'gFinderDesktopFoldersChanged = DMDesktopFoldersChanged;' $D"
check "a missing bundle id is not remembered: the corner path asks again" "! grep -qF '[ids setObject:bid ?: (id)[NSNull null] forKey:appPath];' $C && grep -qF 'if (bid) [ids setObject:bid forKey:appPath];' $C"
exit $fails
