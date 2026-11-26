#!/bin/bash
# test-maclockcoexist.sh: Mac Lock Screen's coexistence verdicts (common/MacLockCoexist.h, F49 1.8.9) -- see test-maclockcoexist.m. The stand-in
# for another modification is built into a plain temporary folder, the stand-in for our own part into .../MacStatusBarAndDock/. Then made-to-fail
# copies of the header, each must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=${MLC_H:-../common/MacLockCoexist.h}
mkdir -p "$W/other" "$W/x/MacStatusBarAndDock"
clang -fobjc-arc -dynamiclib -Wall -framework Foundation -framework QuartzCore -framework AppKit -o "$W/other/libother.dylib" maclockcoexist-fixture/other.m || { echo "FAIL  the stand-in did not build"; exit 1; }
clang -fobjc-arc -dynamiclib -Wall -DOURS -framework Foundation -framework QuartzCore -framework AppKit -o "$W/x/MacStatusBarAndDock/libours.dylib" maclockcoexist-fixture/other.m || { echo "FAIL  our stand-in did not build"; exit 1; }
build() {   # $1 header, $2 out
  clang -fobjc-arc -Wall -Wno-unused-function -DMLC_HEADER="\"$1\"" -framework Foundation -framework QuartzCore -framework AppKit -o "$2" test-maclockcoexist.m 2> "$2.cc" || { cat "$2.cc"; return 99; }
  [ -s "$2.cc" ] && { echo "FAIL  warnings:"; cat "$2.cc"; return 98; }
  return 0
}
cp "$H" "$W/h.h"
build "$W/h.h" "$W/t" || { echo "FAIL  the real header did not build"; exit 1; }
"$W/t" "$W/other/libother.dylib" "$W/x/MacStatusBarAndDock/libours.dylib"; rc=$?
echo "== made-to-fail copies"
mut() {
  python3 -I -c "import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[2])>=1; open(sys.argv[3],'w').write(s.replace(sys.argv[2], sys.argv[4], 1))" "$H" "$2" "$W/m.h" "$3" 2>/dev/null || { echo "FAIL  made to fail ($1): the line to change is gone"; rc=1; return; }
  build "$W/m.h" "$W/tm" >/dev/null || { echo "FAIL  made to fail ($1): did not build"; rc=1; return; }
  if "$W/tm" "$W/other/libother.dylib" "$W/x/MacStatusBarAndDock/libours.dylib" > "$W/out" 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; rc=1; else echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$W/out") checks)"; fi
}
mut "a jailbreak folder read as iPadOS's" 'if (strstr(path, "/var/jb/") || strstr(path, "/TweakInject") || strstr(path, "/MobileSubstrate/")) return kMLKindOther;' ''
mut "no _objc_msgForward rule" 'if (MLStrip((const void *)imp) == MLStrip((const void *)_objc_msgForward)) {' 'if (0) {'
mut "blocks judged by their trampoline" 'id block = imp_getBlock(imp);' 'id block = nil;'
mut "no skip words" 'if (MLSelSkipped(sel_getName(sel), w->skip)) continue;' ''
mut "the main executable not iPadOS's" 'if (isMain) return kMLKindSystem;' ''
mut "our tag ignored" 'if (MLIsTaggedOurs(s)) continue;' ''
mut "our folder not ours" 'if (strstr(path, "/MacStatusBarAndDock/")) return kMLKindOurs;' ''
mut "an isa swizzle read as its superclass" 'if (other) return kMLKindOther;' ''
mut "outside every image read as iPadOS's" 'return m ? m->kind : kMLKindOther;' 'return m ? m->kind : kMLKindSystem;'
mut "the prominent clock's classes unwatched (rev 2's 17+ gate, 1.8.9 pass: two clocks on 16)" 'if (prominentClock) { MLADD(clock17); }' 'if (0 && prominentClock) { MLADD(clock17); }'
[ $rc = 0 ] && echo "test-maclockcoexist: all pass" || echo "test-maclockcoexist: FAILED"
exit $rc
