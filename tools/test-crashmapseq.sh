#!/bin/bash
# test-crashmapseq.sh: the crash map (tools/make-crashmap.py) gives each function the file its own first instruction is in, also the first function
# of a file linked right after another one (1.8.8.1). A line table's end_sequence row is the address just past a sequence's last instruction, with
# that last line; arm64 code is packed, so it is often the next file's first function's address, and read as a row it gave that function the file
# before it (in 1.8.8's map DMRunningDotOf was Launchpad.m's, DMTrashIconView's -initWithFrame: FinderIcon.m's, DMBounceSetOn EditProxy.m's,
# MSBDChargeQuietInit VersionGate.h's; Dock Background's DockColor.m before DockAutoHide.m gave MSBDDockAutoHides Dock Background's target).
# A two-file arm64 dylib built here (clang, dsymutil), run through make-crashmap.py end to end with a rules file of its own (CRASHMAP_PY: another
# copy, e.g. the code before the fix), then the real rules on the same functions' names; then a copy made to fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
PY=${CRASHMAP_PY:-make-crashmap.py}
fails=0
mkdir -p "$W/src" "$W/obj/arm64" "$W/part"
printf 'int ay_one(int x) {\n    return x * 3 + 1;\n}\nint ay_last(int x) {\n    return x - 7;\n}\n' > "$W/src/first.c"
printf 'int bee_first(int x) {\n    return x * 5;\n}\nint bee_two(int x) {\n    return x + 9;\n}\n' > "$W/src/second.c"
for f in first second; do clang -target arm64-apple-macos11 -isysroot "$SDK" -g -Os -c "$W/src/$f.c" -o "$W/$f.o" || { echo "FAIL  $f.c did not build"; exit 1; }; done
clang -target arm64-apple-macos11 -isysroot "$SDK" -dynamiclib "$W/first.o" "$W/second.o" -o "$W/part/Fake.dylib" && dsymutil "$W/part/Fake.dylib" -o "$W/obj/arm64/Fake.dylib.dSYM" \
  || { echo "FAIL  the dylib or its symbols did not build"; exit 1; }
D="$W/obj/arm64/Fake.dylib.dSYM/Contents/Resources/DWARF/Fake.dylib"
# (the case itself: the first file's end_sequence row at the second file's first function, with a line of its own)
start=$(nm -n "$D" | awk '$3 == "_bee_first" {print $1}')
if dwarfdump --debug-line "$D" | grep -q "^0x$start .*end_sequence$" && [ "$(dwarfdump --debug-line "$D" | grep "^0x$start .*end_sequence$" | awk '{print $2}')" != 0 ]; then
  echo "PASS  the case: first.c's line table ends (end_sequence, line $(dwarfdump --debug-line "$D" | grep "^0x$start .*end_sequence$" | awk '{print $2}')) at bee_first's address 0x$start"
else echo "FAIL  the case did not come about (no end_sequence row with a line at bee_first's address): nothing tested"; exit 1; fi
cat > "$W/rules.txt" <<'EOF'
target part part
target ay pref com.example.test ay 0 1 Ay|the first file
target bee pref com.example.test bee 0 1 Bee|the second file
image Fake part map
file Fake ^first\.c$ ay
file Fake ^second\.c$ bee
EOF
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
run() {   # $1 make-crashmap.py: the map's function ranges, "start target" per R line
  python3 -I "$1" "$W/rules.txt" "$W/obj" "$W/part" "$W/src" "$W/map.txt" > "$W/run.txt" 2>&1 || { cat "$W/run.txt"; return 1; }
  awk '$1 == "R" {print $2, $3}' "$W/map.txt" | tr '\n' ' '
}
a=$(nm -n "$D" | awk '$3 == "_ay_one" {print $1}' | sed 's/^0*//'); b=$(echo "$start" | sed 's/^0*//')
got=$(run "$PY")
check "each file's functions take its own target: ay from ay_one (0x$a), bee from bee_first (0x$b), the second file's first function" "echo \"$got\" | grep -Eq \"^$a ay $b bee [0-9a-f]+ - \$\""
echo "      map: $got"
# the real rules: the functions the old reading gave the file before them, by their own files now (make-crashmap.py's own code)
got2=$(python3 -I - "$PY" crashmap-rules.txt <<'PYEOF'
import sys
src = open(sys.argv[1]).read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'cs'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[2]); hits = [0] * len(rules)
def t(im, n, f): return g['classify'](im, n, f, '', rules, images[im]['target'], hits)
print(t('DockMagnification', '_DMRunningDotOf', 'RunningIndicator.m'), t('DockMagnification', '-[DMTrashIconView initWithFrame:]', 'TrashIcon.m'),
      t('DockMagnification', '_DMBounceSetOn', 'Bounce.m'), t('DockMagnification', '_MSBDDockAutoHides', 'DockAutoHide.m'), t('MacStatusBarCore', '_MSBDChargeQuietInit', 'ChargeQuiet.x'))
PYEOF
)
check "  ... with the real rules, those functions by their own files: the running dot, the Trash icon, the launch bounce, Automatically Hide the Dock, the charge quiet part" \
  "[ \"$got2\" = 'runningIndicator showTrash animateOpening autoHideDock part' ]"
if [ -z "$CRASHMAP_PY" ]; then
  perl -0pe 's/if m and not l\.rstrip\(\)\.endswith\(.end_sequence.\):/if m:/' make-crashmap.py > "$W/old.py"
  if cmp -s make-crashmap.py "$W/old.py"; then echo "FAIL  made to fail (end_sequence rows read again): the change did not apply"; fails=1
  elif [ "$(run "$W/old.py")" = "$got" ]; then echo "FAIL  made to fail (end_sequence rows read again): not caught"; fails=1
  else echo "PASS  made to fail (end_sequence rows read again): caught (map: $(run "$W/old.py"))"; fi
fi
[ $fails = 0 ] && echo "test-crashmapseq: all checks pass" || { echo "test-crashmapseq: checks FAILED"; exit 1; }
