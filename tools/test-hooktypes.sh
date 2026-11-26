#!/bin/bash
# test-hooktypes.sh: our Lock Screen hooks are written for the types iPadOS's methods have (1.8.9, after a test build's Lock Screen crash:
# -[SBDashBoardStatusBarController setStatusBarAlpha:style:legibilitySettings:] was hooked with a double alpha where iPadOS passes an NSNumber).
# 1. common/HookTypes.h as built (test-hooktypes.m): the reduction of a type string and the check a group passes before its %init.
# 2. Every hook declaration of LockStatusBar.x and MacLockScreen.x, compiled (hooktypes.py gen), against iPadOS 15.6.1 / 16.7.7 / 17.5.1 / 18.5's
#    methods read from Apple's IPSWs (hooktypes-ipados.txt), and each guarded group's kHookSigs table against its declarations.
# 3. The wiring: every guarded group's %init behind its check. 4. Made-to-fail copies (the test build's declaration among them): each must fail.
# MSBD_TEST_LSB / MSBD_TEST_MLS / MSBD_TEST_HT: other copies of the sources.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
LSB=${MSBD_TEST_LSB:-../macsettings/LockStatusBar.x}; MLS=${MSBD_TEST_MLS:-../macsettings/MacLockScreen.x}; HT=${MSBD_TEST_HT:-../common/HookTypes.h}
DATA=hooktypes-ipados.txt
GLSB="LSBReal,LSBRealAlpha"
GMLS="MLCore,MLStatusWatch,MLPages,MLSwitcher,MLClock15,MLClock17,MLCards,MLUser,MLHint,MLHintCTA,MLHint17,MLHint17b"
wiring() {   # $1 LockStatusBar.x, $2 MacLockScreen.x: PASS / FAIL lines
  local l="$1" m="$2" g
  if [ "$(grep -c "%init(LSBRealAlpha);" "$l")" -ge 1 ] && ! grep "%init(LSBRealAlpha);" "$l" | grep -vqF "LSB_TYPES_OK(LSBRealAlpha)"; then echo "PASS  wiring: every %init(LSBRealAlpha) is behind LSB_TYPES_OK(LSBRealAlpha)"; else echo "FAIL  wiring: a %init(LSBRealAlpha) without LSB_TYPES_OK(LSBRealAlpha)"; fi
  if [ "$(grep -c '%init(LSBReal);' "$l")" = 1 ] && awk '/&& LSB_TYPES_OK\(LSBReal\)\) \{$/{a=NR} /%init\(LSBReal\);/{b=NR} END{exit !(a && b == a + 1)}' "$l"; then
    echo "PASS  wiring: %init(LSBReal) (and with it the alpha hook and the switch's note) only behind LSB_TYPES_OK(LSBReal)"
  else echo "FAIL  wiring: %init(LSBReal) not behind LSB_TYPES_OK(LSBReal)"; fi
  for g in MLStatusWatch MLPages MLSwitcher MLHint MLHintCTA MLHint17 MLHint17b; do
    if [ "$(grep -c "%init($g);" "$m")" -ge 1 ] && ! grep "%init($g);" "$m" | grep -vqF "ML_TYPES_OK($g)"; then echo "PASS  wiring: every %init($g) is behind ML_TYPES_OK($g)"; else echo "FAIL  wiring: a %init($g) without ML_TYPES_OK($g)"; fi
  done
  if [ "$(grep -c '%init(MLCore);' "$m")" = 1 ] && awk '/if \(!ML_TYPES_OK\(MLCore\)\) \{ gCoreRefused = YES; .*return YES; \}/{a=NR} /%init\(MLCore\);/{b=NR} END{exit !(a && b == a + 1)}' "$m" \
     && awk '/^static BOOL MLInstallWanted\(void\)/{f=1} f&&/if \(gCoreRefused\) return YES;/{x=1} f&&x&&/MLTableBuild\(&gTable\);/{print "ok"; exit}' "$m" | grep -q ok; then
    echo "PASS  wiring: the core goes in only behind its check; refused, nothing of Mac Lock Screen is installed in this SpringBoard life"
  else echo "FAIL  wiring: the core's %init is not behind ML_TYPES_OK(MLCore), or a refused core is tried again"; fi
  if awk '/^static BOOL MLPartTypesOK\(int p\)/{f=1} f&&/case kMLPartClock: return MLProminentClock\(\) \? ML_TYPES_OK\(MLClock17\) : ML_TYPES_OK\(MLClock15\);/{a=1} f&&/case kMLPartCards: return ML_TYPES_OK\(MLCards\);/{b=1} f&&/case kMLPartUser: return ML_TYPES_OK\(MLUser\);/{c=1} f&&/^}/{exit !(a&&b&&c)}' "$m" \
     && awk '/if \(!MLPartTypesOK\(p\)\) \{ .*gInstallWhy\[p\] = kMLWhyNone; continue; \}/{a=NR} /switch \(p\) \{/{if (a && !b) b=NR} END{exit !(a && b > a)}' "$m"; then
    echo "PASS  wiring: a part's own groups (clock, cards, user) go in only behind their checks, before the part's switch"
  else echo "FAIL  wiring: a part's group without its check"; fi
  if grep -qE 'setStatusBarAlpha:\(double\)' "$l" "$m"; then echo "FAIL  the test build's declaration (a double alpha) is still there"; else echo "PASS  no hook declares the alpha as a double"; fi
}
all() {   # $1 LockStatusBar.x, $2 MacLockScreen.x, $3 HookTypes.h, $4 dir: every check; status 0 = all pass
  mkdir -p "$4"; local rc=0 ht
  ht="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
  clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -DHT_HEADER="\"$ht\"" -framework Foundation -framework CoreGraphics -o "$4/unit" test-hooktypes.m 2> "$4/cc0" || { cat "$4/cc0"; return 99; }
  [ -s "$4/cc0" ] && { echo "FAIL  warnings:"; cat "$4/cc0"; rc=1; }
  "$4/unit" || rc=1
  python3 -I hooktypes.py gen "$4/probe.m" "$1" "$2" || return 97
  clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -DHT_HEADER="\"$ht\"" -framework Foundation -framework CoreGraphics -o "$4/probe" "$4/probe.m" 2> "$4/cc" || { cat "$4/cc"; return 99; }
  [ -s "$4/cc" ] && { echo "FAIL  probe warnings:"; cat "$4/cc"; rc=1; }
  "$4/probe" > "$4/types.txt" || { cat "$4/types.txt"; return 98; }
  python3 -I hooktypes.py check "$4/types.txt" "$DATA" "$1" "$2" --guarded "$1=$GLSB" --guarded "$2=$GMLS" --unread-ok LSBGeneric || rc=1
  wiring "$1" "$2" > "$4/wiring.txt"; cat "$4/wiring.txt"; grep -q '^FAIL' "$4/wiring.txt" && rc=1
  return $rc
}
rc=0
all "$LSB" "$MLS" "$HT" "$W/real" || rc=1
# the MSHookMessageEx hooks 1.8.9 added or changed (F51's hovered edge, GitHub #20's Stage Manager gates) check their methods' types themselves
# (statusbar/SMEngineAPI.h DMSMSigOfMethod): the types they check for are iPadOS's on every version that has the method
echo "== F51 and #20's own checks"
python3 -I - "$DATA" ../statusbar/ResizeFact.h ../statusbar/StatusBar.x <<'PY' || rc=1
import sys
sys.path.insert(0, ".")
from hooktypes import bare
data, rz, sb = sys.argv[1:4]
real = {}
for line in open(data):
    if line.strip() and not line.startswith("#"):
        p = line.rstrip("\n").split("\t")
        real.setdefault(p[1], []).append((p[0], bare(p[2])))
src = open(rz).read() + open(sb).read()
fails = 0
for key, want, line in [
    ("-[SBFluidSwitcherItemContainer _updateForPointerHoveringOverEdge:]", "v@:Q", "DMSMExpect(@encode(void), @encode(unsigned long long), NULL)"),
    ("-[SBFluidSwitcherGestureManager _shouldBeginTapToBringItemContainerForwardGesture:]", "B@:@", "NSString *want = DMSMExpect(@encode(BOOL), @encode(id), NULL);"),
    ("-[SBFluidSwitcherGestureManager _shouldBeginClickDownToBringItemContainerForwardGesture:]", "B@:@", "NSString *want = DMSMExpect(@encode(BOOL), @encode(id), NULL);"),
    ("-[SBFluidSwitcherGestureManager _shouldBeginLiveWindowResizeGesture:]", "B@:@", "NSString *want = DMSMExpect(@encode(BOOL), @encode(id), NULL);"),
    ("-[SBFluidSwitcherGestureManager _shouldTapToBringItemContainerForward:receiveTouch:]", "B@:@@", "DMSMExpect(@encode(BOOL), @encode(id), @encode(id), NULL)")]:
    rows = real.get(key, [])
    ok = bool(rows) and all(b == want for _, b in rows) and line in src
    if not ok:
        fails += 1
    print("%s  %s checks for %s: iPadOS's on %s" % ("PASS" if ok else "FAIL", key, want, ", ".join(v for v, _ in rows) or "no version"))
sys.exit(1 if fails else 0)
PY
echo "== made-to-fail copies"
mut() {   # $1 name, $2 which (l|m|h), then old / new pairs (each old must be there)
  rm -rf "$W/m"; mkdir -p "$W/m"
  local name="$1" src l="$LSB" m="$MLS" h="$HT"
  case "$2" in l) src="$LSB"; l="$W/m/$(basename "$LSB")";; m) src="$MLS"; m="$W/m/$(basename "$MLS")";; h) src="$HT"; h="$W/m/$(basename "$HT")";; esac
  shift 2
  python3 -I -c "
import sys
s = open(sys.argv[1]).read()
for i in range(3, len(sys.argv), 2):
    assert s.count(sys.argv[i]) >= 1, 'gone'
    s = s.replace(sys.argv[i], sys.argv[i + 1], 1)
open(sys.argv[2], 'w').write(s)" "$src" "$W/m/$(basename "$src")" "$@" 2>/dev/null \
    || { echo "FAIL  made to fail ($name): the line to change is gone"; rc=1; return; }
  set -- "$name"
  if all "$l" "$m" "$h" "$W/m/b" > "$W/m/out" 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; rc=1; else echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$W/m/out") checks)"; fi
}
mut "the test build's declaration in Hide Status Bar on Lock Screen (a double alpha)" l '- (void)setStatusBarAlpha:(id)alpha style:(long long)style legibilitySettings:(id)ls {' '- (void)setStatusBarAlpha:(double)alpha style:(long long)style legibilitySettings:(id)ls {'
mut "the test build's declaration in Mac Lock Screen (a double alpha)" m '- (void)setStatusBarAlpha:(id)alpha style:(long long)style legibilitySettings:(id)ls {' '- (void)setStatusBarAlpha:(double)alpha style:(long long)style legibilitySettings:(id)ls {'
mut "the test build's declaration with its table written to match it (iPadOS's own types still catch it)" l '- (void)setStatusBarAlpha:(id)alpha style:(long long)style legibilitySettings:(id)ls {' '- (void)setStatusBarAlpha:(double)alpha style:(long long)style legibilitySettings:(id)ls {' \
  '{"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:@q@"},' '{"SBDashBoardStatusBarController", "setStatusBarAlpha:style:legibilitySettings:", "v@:dq@"},'
mut "an int argument declared long long (-setInScreenOffMode:forAutoUnlock:fromUnlockSource:)" m '- (void)setInScreenOffMode:(BOOL)off forAutoUnlock:(BOOL)autoUnlock fromUnlockSource:(int)source {' '- (void)setInScreenOffMode:(BOOL)off forAutoUnlock:(BOOL)autoUnlock fromUnlockSource:(long long)source {'
mut "a table's types not the declaration's" m '{"SBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:B@"},' '{"SBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:q@"},'
mut "a hooked method missing from its group's table" m '    {"SBDashBoardStatusBarController", "setStatusBarHidden:forReason:", "v@:B@"},
' ''
mut "the alpha hook's %init without its check" l '&& LSB_TYPES_OK(LSBRealAlpha)) %init(LSBRealAlpha);' ') %init(LSBRealAlpha);'
mut "the status watch's %init without its check" m ' && ML_TYPES_OK(MLStatusWatch)) %init(MLStatusWatch);' ') %init(MLStatusWatch);'
mut "a part's groups without their check" m '        if (!MLPartTypesOK(p)) {' '        if (0 && !MLPartTypesOK(p)) {'
mut "a refused core tried again at each settings change" m '    if (gCoreRefused) return YES;
' ''
mut "a block argument not folded into an object" h '        if (ch == '"'"'?'"'"' && k > 0 && out[k - 1] == '"'"'@'"'"') continue;
' ''
mut "a missing method taken for a refusal" h '        if (!m) continue;   // (not there: Logos hooks nothing for it)' '        if (!m) return @"missing";'
mut "a declaration whose { is on the next line passed over" m '- (void)setStatusBarHidden:(BOOL)hidden forReason:(id)reason {' '- (void)setStatusBarHidden:(BOOL)hidden forReason:(id)reason
{'
mut "an array's length dropped" h '        if (ch >= '"'"'0'"'"' && ch <= '"'"'9'"'"' && !arrayLength) continue;' '        if (ch >= '"'"'0'"'"' && ch <= '"'"'9'"'"') continue;'
mut "offsets kept" h '        if (ch >= '"'"'0'"'"' && ch <= '"'"'9'"'"' && !arrayLength) continue;' ''
[ $rc = 0 ] && echo "test-hooktypes: all pass" || echo "test-hooktypes: FAILED"
exit $rc
