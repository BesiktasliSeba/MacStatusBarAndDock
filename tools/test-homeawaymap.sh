#!/bin/bash
# test-homeawaymap.sh: the crash map's answer for Home Minimizes Windows (statusbar/StatusBar.x, its section and HomeAway.h): every DMHomeAway...
# function and block is that switch's (homeMinimizes), so a crash in its code turns Home Minimizes Windows off, which stops that code, and the Mac
# menu bar stays. Up to 1.8.8 no rule named them and they fell to MacStatusBarCore's image target, Stock status bar mode (1.8.8.1, B13, found by
# the F28 skeptic). A function of it that another part's function calls (the Home button's hooks, the gesture's lift, the tick, the preferences'
# read) must stay out of line: at -Os a static function is put inside its caller, and the crash map gives a function one answer by its first line
# (tools/make-crashmap.py), so its code would take the caller's answer (the F-7 review's finding 1).
# Adapt to Trackpad & Mouse (1.8.8.1, F28): its two functions (DMHomeAdaptPointer, DMHomeAdaptMinimizes) are its switch's (homeAdapt): a crash in
# them sets Adapt off, Home Minimizes Windows alone decides as in 1.8.8, and the pointer is read no more.
# Classified with make-crashmap.py's own code (load_rules, section_of, classify) at the functions' real lines and by name; the rule's own hit count
# (the strict build stops on a rule that matches no function); the out-of-line rule read from the sources; when a package was built in this tree,
# the real CrashMap.txt against the build's symbols; HAM_OBJ=<an object of StatusBar.x compiled with -Os -g> checks that object's symbols as the
# strict map would read them. Then made-to-fail copies. HAM_RULES / HAM_SB_DIR: test other copies (the rules, the statusbar folder).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
R0=${HAM_RULES:-crashmap-rules.txt}; D0=${HAM_SB_DIR:-../statusbar}

cat > "$W/check.py" <<'PY'
import glob, os, re, subprocess, sys
rules_path, sbdir, obj = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ''
src = open('make-crashmap.py').read().rstrip()   # (make-crashmap.py's own code: its load_rules, section_of and classify, as the build runs them)
assert src.endswith('main()'); g = {'__name__': 'ham'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](rules_path)
im = images['MacStatusBarCore']['target']
bad = 0
def check(ok, what):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + what)
    if not ok: bad += 1
# the features: the prefix of their functions, the crash map target, its switch (domain, key, off, default) and the functions there must be
FEATURES = [
    ('DMHomeAway', 'homeMinimizes', ['pref', 'com.besiktasliseba.macstatusbar', 'homeMinimizesWindows', '0', '1'],
     ['Run', 'Lift', 'Press', 'PressCovered', 'Covered', 'DismissTap', 'HookDismissTap', 'KeysHome', 'HookKeys', 'KeysOther', 'ScanKeys']),
    # Adapt to Trackpad & Mouse (1.8.8.1, F28): the pointer's read and the rule that asks it (called from the run and SMHome.h)
    ('DMHomeAdapt', 'homeAdapt', ['pref', 'com.besiktasliseba.macstatusbar', 'homeMinimizesAdapt', '0', '1'], ['Pointer', 'Minimizes']),
]
HEAD = re.compile(r'^(__attribute__\(\(noinline\)\) )?static [^;=(]*?\b(\w+)\((.*)\)\s*\{')   # (a function's first line, at column 0)
files = [os.path.join(sbdir, 'StatusBar.x')] + sorted(glob.glob(os.path.join(sbdir, '*.h')))
text = {f: open(f, errors='replace').read().split('\n') for f in files}
sbx = files[0]
for prefix, target, spec, names in FEATURES:
    # where StatusBar.x defines them (their first lines are what the build's line table gives make-crashmap.py)
    defs = {}
    for i, t in enumerate(text[sbx]):
        m = HEAD.match(t)
        if m and m.group(2).startswith(prefix): defs.setdefault(m.group(2), []).append((i + 1, bool(m.group(1))))
    want = sorted(prefix + n for n in names)
    check(sorted(defs) == want and all(len(v) == 1 for v in defs.values()),
          '%s: StatusBar.x defines %s, each once (found: %s)' % (target, ', '.join(want), ', '.join('%s:%s' % (n, [l for l, _ in v]) for n, v in sorted(defs.items()))))
    # by their real place: file StatusBar.x, the section their first line sits under (make-crashmap.py's section_of), their blocks too
    hits = [0] * len(rules)
    wrong = []
    for n, v in sorted(defs.items()):
        sec = g['section_of'](os.path.dirname(os.path.abspath(sbx)), os.path.basename(sbx), v[0][0])
        for s in ('_' + n, '___' + n + '_block_invoke', '___' + n + '_block_invoke_2'):
            t = g['classify']('MacStatusBarCore', s, os.path.basename(sbx), sec, rules, im, hits)
            if t != target: wrong.append('%s -> %s [%s]' % (s, t, sec[:40]))
    check(defs and not wrong, '%s: every one of them and its blocks is %s at its real place in StatusBar.x, not Stock status bar mode' % (prefix, target) + (' -- not: ' + '; '.join(wrong) if wrong else ''))
    byname = sorted(set(g['classify']('MacStatusBarCore', '_' + n, '', '', rules, im, [0] * len(rules)) for n in defs))
    check(byname == [target], '  ... by name alone (no section, no file): %s (got %s)' % (target, byname))
    first = next((k for k, r in enumerate(rules) if r[0] == 'sym' and r[1] == 'MacStatusBarCore' and r[2].search('_' + prefix + names[0])), None)
    check(first is not None and rules[first][3] == target and hits[first] > 0,
          '  ... the first sym rule naming them is %s\'s and make-crashmap.py counts it a match (%s)' % (target, ('"%s" %d hits' % (rules[first][2].pattern, hits[first])) if first is not None else 'none'))
    near = [g['classify']('MacStatusBarCore', s, '', '', rules, im, [0] * len(rules)) for s in ('_X' + prefix + 'Run', '_' + prefix + 'er', '_' + prefix, '_DMHomeIsOurs', '_DMHomeFromKeys', '_DMOwnHome')]
    check(target not in near, '  ... only them: _X%sRun, _%ser, _%s and Home\'s marks used by the window code too (DMHomeIsOurs, DMHomeFromKeys, DMOwnHome) are not %s (got %s)' % (prefix, prefix, prefix, target, near))
    check(targets.get(target, [])[:5] == spec, '  ... %s is the switch itself: %s (got %s)' % (target, ' '.join(spec), ' '.join(targets.get(target, []))))
    # Called from another part's function: out of line. A call's function is the one whose first line comes last before it (or on its line).
    callers = {}
    for f in files:
        cur = None
        for i, t in enumerate(text[f]):
            m = HEAD.match(t)
            if m: cur = m.group(2)
            elif re.match(r'^(%hook|%end|%group|%subclass|[-+] ?\()', t): cur = None   # (Logos: a hook's method is no function of ours)
            code = t.split('//')[0]   # (a comment that names one is no call)
            for c in re.finditer(r'\b(' + prefix + r'\w+)\(', code):
                n = c.group(1)
                if n not in defs or (m and m.group(2) == n): continue
                if code.rstrip().endswith(';') and re.match(r'^static [^(]*\b' + n + r'\(', code): continue   # (a prototype)
                callers.setdefault(n, set()).add('%s %s' % (os.path.basename(f), cur or '(no function of ours)'))
            if t.startswith('}'): cur = None
    outside = {n: sorted(c for c in cs if not c.split(' ', 1)[1].startswith(prefix)) for n, cs in callers.items()}
    outside = {n: cs for n, cs in outside.items() if cs}
    inl = sorted(n for n in outside if not defs[n][0][1])
    check(outside and not inl, '%s: those another part\'s function calls are out of line (noinline): %s' % (prefix, '; '.join('%s from %s' % (n, ', '.join(cs)) for n, cs in sorted(outside.items())))
          + (' -- NOT out of line: ' + ', '.join(inl) if inl else ''))
    # A release-flag object of StatusBar.x (-Os -g), if given: its symbols as the strict map reads them
    if obj:
        rows = g['line_rows'](obj); syms, end = g['functions'](obj)
        got = {}
        for start, n in syms:
            if not re.match(r'^_*' + prefix, n): continue
            fname, line = rows.get(start, ('', 0))
            sec = g['section_of'](os.path.dirname(os.path.abspath(sbx)), fname, line) if fname else ''
            got[n] = g['classify']('MacStatusBarCore', n, fname, sec, rules, im, [0] * len(rules))
        miss = sorted(n for n in outside if '_' + n not in got)
        wrongo = sorted('%s -> %s' % (n, t) for n, t in got.items() if t != target)
        check(got and not miss and not wrongo, '  ... the release-flag object (%s): %d symbols of theirs, every one %s, and every one another part calls is a symbol of its own%s'
              % (os.path.basename(obj), len(got), target, (' -- inlined: ' + ', '.join(miss) if miss else '') + (' -- wrong: ' + ', '.join(wrongo) if wrongo else '')))
sys.exit(1 if bad else 0)
PY

fails=0
echo "== the rules and the sources (make-crashmap.py's own code)"
python3 -I "$W/check.py" "$R0" "$D0" ${HAM_OBJ:+"$HAM_OBJ"} || fails=1

# The real map of the last build in this tree, if there is one: the functions' addresses in the build's own symbols fall in their target's ranges.
echo "== the built map"
MAP=../.theos/_/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt
if [ -z "$HAM_RULES$HAM_SB_DIR" ] && [ -f "$MAP" ]; then
  seen=0
  for o in ../.theos/obj ../.theos/obj/debug; do
    for a in arm64 arm64e; do
      c=$o/$a/MacStatusBarCore.dylib.dSYM/Contents/Resources/DWARF/MacStatusBarCore.dylib
      [ -f "$c" ] || continue
      u=$(dwarfdump --uuid "$c" | awk -v a="($a)" '$3 == a {print tolower($2)}')
      grep -q "^U MacStatusBarCore $u $a\$" "$MAP" || continue   # (symbols of another build than the map's)
      seen=$((seen + 1))
      nm -s __TEXT __text "$c" | python3 -I -c '
import re, sys
mp, u, a = sys.argv[1], sys.argv[2], sys.argv[3]
want = {"DMHomeAway": "homeMinimizes", "DMHomeAdapt": "homeAdapt"}
syms = {}
for l in sys.stdin:
    m = re.match(r"([0-9a-f]+) [tT] (_+(DMHomeAway|DMHomeAdapt)\w*)$", l.strip())
    if m: syms[m.group(2)] = (int(m.group(1), 16), want[m.group(3)])
rs, on = [], False
for l in open(mp):
    f = l.split()
    if f[0] == "U": on = f[1:] == ["MacStatusBarCore", u, a]
    elif f[0] == "R" and on: rs.append((int(f[1], 16), f[2]))
bad = [n for n, (ad, t) in sorted(syms.items()) if [x for s, x in rs if s <= ad][-1:] != [t]]
print(("PASS  " if syms and not bad else "FAIL  ") + "the built map (%s): %d functions and blocks of Home Minimizes Windows and Adapt to Trackpad & Mouse, each in its own target%s" % (a, len(syms), " -- not: " + ", ".join(bad) if bad else ""))
sys.exit(1 if bad or not syms else 0)' "$MAP" "$u" "$a" || fails=1
    done
  done
  [ $seen -gt 0 ] || echo "SKIP  the built map: no symbols of the build it was made from"
else echo "SKIP  no built map in this tree (build the package to test it)"; fi

if [ -z "$HAM_RULES$HAM_SB_DIR" ]; then
  echo "== made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 r (the rules) or x (StatusBar.x), $3 perl expression on that file (the whole file at once)
    local d="$W/m$((++k))" r=$R0 x=$D0; mkdir -p "$d"
    if [ "$2" = r ]; then r=$d/crashmap-rules.txt; perl -0777 -pe "$3" "$R0" > "$r"; cmp -s "$r" "$R0" && { echo "FAIL  made to fail ($1): the copy did not change"; fails=1; return; }
    else x=$d/sb; mkdir -p "$x"; cp "$D0"/*.h "$x/"; perl -0777 -pe "$3" "$D0/StatusBar.x" > "$x/StatusBar.x"; cmp -s "$x/StatusBar.x" "$D0/StatusBar.x" && { echo "FAIL  made to fail ($1): the copy did not change"; fails=1; return; }; fi
    if python3 -I "$W/check.py" "$r" "$x" > "$d/out.txt" 2>&1; then echo "FAIL  made to fail ($1): still passes"; fails=1
    else echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$d/out.txt") check(s) fail)"; fi
  }
  k=0
  mtf "the rules without Home Minimizes Windows' rule (1.8.8's)" r 's/^sym MacStatusBarCore \^_\*DMHomeAway\[A-Z\] homeMinimizes\n//m'
  mtf "the rule's target Stock status bar mode" r 's/^(sym MacStatusBarCore \^_\*DMHomeAway\[A-Z\]) homeMinimizes$/$1 stock/m'
  mtf "the rule unanchored (it takes longer names)" r 's/^(sym MacStatusBarCore )\^_\*(DMHomeAway\[A-Z\] homeMinimizes)$/$1$2/m'
  mtf "the target set on (1) after a crash" r 's/^(target homeMinimizes pref com\.besiktasliseba\.macstatusbar homeMinimizesWindows) 0 1 /$1 1 1 /m'
  mtf "the target never set read as off" r 's/^(target homeMinimizes pref com\.besiktasliseba\.macstatusbar homeMinimizesWindows) 0 1 /$1 0 0 /m'
  mtf "the Home button's cover read inlined into its hooks" x 's/^__attribute__\(\(noinline\)\) (static BOOL DMHomeAwayPressCovered\(void\) \{)/$1/m'
  mtf "the key scan inlined into the tick" x 's/^__attribute__\(\(noinline\)\) (static void DMHomeAwayScanKeys\(void\) \{)/$1/m'
  mtf "the hooks' install inlined into the preferences' read" x 's/^__attribute__\(\(noinline\)\) (static void DMHomeAwayHookKeys\(void\) \{)/$1/m'
  mtf "the gesture's lift inlined into the Mac Switcher's" x 's/^__attribute__\(\(noinline\)\) (static void DMHomeAwayLift\(void\) \{)/$1/m'
  mtf "a new function of it (the tick calls it), not in the list" x 's/^(static void DMTickBody\(void\) \{\n)/static void DMHomeAwayNewOne(void) { }\n$1    DMHomeAwayNewOne();\n/m'
  mtf "the rules without Adapt to Trackpad & Mouse's rule" r 's/^sym MacStatusBarCore \^_\*DMHomeAdapt\[A-Z\] homeAdapt\n//m'
  mtf "Adapt's rule taking Home Minimizes Windows' target" r 's/^(sym MacStatusBarCore \^_\*DMHomeAdapt\[A-Z\]) homeAdapt$/$1 homeMinimizes/m'
  mtf "Adapt's target never set read as off" r 's/^(target homeAdapt pref com\.besiktasliseba\.macstatusbar homeMinimizesAdapt) 0 1 /$1 0 0 /m'
  mtf "Adapt's target on another key" r 's/^(target homeAdapt pref com\.besiktasliseba\.macstatusbar) homeMinimizesAdapt /$1 homeMinimizesWindows /m'
  mtf "the rule's read inlined into the run and the Stage Manager engine's Home" x 's/^__attribute__\(\(noinline\)\) (static BOOL DMHomeAdaptMinimizes\(int \*pointer\) \{)/$1/m'
fi
[ $fails = 0 ] && echo "test-homeawaymap: all pass" || echo "test-homeawaymap: FAILED"
exit $fails
