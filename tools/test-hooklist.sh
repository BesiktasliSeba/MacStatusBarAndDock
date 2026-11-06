#!/bin/bash
# Mac test of tools/make-hooklist.py (common/HookList.h, the hook list the untested-iPadOS diagnostics check, common/Diag.h): a hook a release build installs is
# listed, one inside #if DEBUG (a debug build's read-outs) is not -- 1.8.2.2, code review 9: the side Dock's zoom read-outs were reported missing by a release.
# Runs the generator on a small tree of its own, then checks the real list.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tools" "$W/common" "$W/part"
cp make-hooklist.py "$W/tools/"
cat > "$W/part/T.x" <<'XEOF'
%hook Shipped
- (void)always { %orig; }
#if DEBUG
- (void)debugMethod { %orig; }
#endif
%end
#if DEBUG
%group ReadOuts
%hook DebugOnly
- (id)readOut:(id)a { return %orig; }
%end
%end
#else
%hook ReleaseOnly
- (void)shipped { %orig; }
%end
#endif
#if !DEBUG
%hook NotDebug
- (void)a { %orig; }
%end
#else
%hook DebugElse
- (void)b { %orig; }
%end
#endif
#if __has_feature(ptrauth_calls)
#if DEBUG
%hook NestedDebug
- (void)c { %orig; }
%end
#endif
%hook Nested
- (void)d { %orig; }
%end
#endif
XEOF
python3 "$W/tools/make-hooklist.py" > "$W/out.txt"
L="$W/common/HookList.h"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "a release hook is listed" "grep -qF '{\"Shipped\", \"always\", \"-\", \"part/T.x\"},' $L"
check "a method inside #if DEBUG in a release hook is not" "! grep -qF 'debugMethod' $L"
check "a debug-only group's hook is not" "! grep -qF 'DebugOnly' $L"
check "the #else of #if DEBUG is release code: listed" "grep -qF '{\"ReleaseOnly\", \"shipped\", \"-\", \"part/T.x\"},' $L"
check "#if !DEBUG is release code: listed; its #else is debug: not" "grep -qF '{\"NotDebug\", \"a\", \"-\", \"part/T.x\"},' $L && ! grep -qF 'DebugElse' $L"
check "#if DEBUG nested in another condition: not listed; the other condition's own hook: listed" "! grep -qF 'NestedDebug' $L && grep -qF '{\"Nested\", \"d\", \"-\", \"part/T.x\"},' $L"
check "the count printed is the hooks listed (4)" "grep -qx '4 hooks' $W/out.txt"
R=../common/HookList.h
check "the real list: the side Dock's zoom fix is listed, its debug read-outs are not (code review 1.8.2.2, 9)" \
  "grep -qF '{\"SBFluidSwitcherViewController\", \"shouldMatchMoveIconZoomingView:\", \"-\", \"dock/Dock.x\"},' $R && ! grep -qF 'homeScreenIconFrameForAppLayout:' $R \
   && ! grep -qF 'homeScreenIconLocationForAppLayout:' $R && ! grep -qF 'matchingIconZoomingViewForIconZoomingView:' $R && ! grep -qF 'iconZoomingViewContainerForIconZoomingView:' $R"
check "the real list: the 16 / 17 zoom hook is listed too" "grep -qF '{\"SBFluidSwitcherViewController\", \"_performModifierMatchMoveToIconViewResponse:\", \"-\", \"dock/Dock.x\"},' $R"
check "the real list: other debug-only read-outs are out too (the keyboard brightness client's log, MixAudio's play traces)" \
  "! grep -qF 'KeyboardBrightnessClient' $R && ! grep -qF '{\"AVPlayer\", \"play\",' $R && grep -qF '{\"AVPlayer\", \"setVolume:\",' $R"
[ $fails = 0 ] && echo "test-hooklist: pass" || { echo "test-hooklist: FAILED"; exit 1; }
