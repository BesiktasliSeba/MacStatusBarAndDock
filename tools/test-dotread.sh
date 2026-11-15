#!/bin/bash
# test-dotread.sh: the Dock's running dots read the running apps once per step of the main run loop, not once per icon (1.8.7.4, audit O5 of
# 1.8.7.2). Each Dock icon's layout read SpringBoard's running apps with their process states and MacStatusBar's window sets for itself: 12-15 reads
# of the same answer when the Dock laid out its icons together, twice per icon with a side Dock. Now the first layout of a step reads, the others use
# that read, and it is forgotten at the run loop's next activity; the 0.75 s poll reads anew. See test-dotread.m. The real code is dock/
# RunningIndicator.m (DR_RI_M: another copy, e.g. the code before the fix), run on the Mac (Mac Catalyst) on the real main run loop, release and
# DEBUG; then site checks; then made-to-fail copies (each takes one part out and must fail); then the code before the fix (the new checks fail
# there, the as-before ones pass); then the proof that the dots are the same: random worlds run on this code and on the code before the fix
# (DR_REF_M, else this file with the fix taken out) give the same dots and the same remembered processes at every look.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
R0=${DR_RI_M:-../dock/RunningIndicator.m}
STEP='static NSSet<NSString *> *RIRunningForStep(BOOL fresh) {'
# one function of a file, from its first line to its closing brace
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1 } f { print } f && /^[}]/ { exit }' "$1"; }

cut() {   # $1 RunningIndicator.m, $2 dir: the file from its first declaration to its end
  sed -n '/^@interface UIWindow (DMPrivate)/,$p' "$1" > "$2/dotread-real.inc"
  grep -qF 'void DMUpdateRunningIndicator(UIView *iconView) {' "$2/dotread-real.inc" && grep -qF 'static void RIResyncDock(void) {' "$2/dotread-real.inc" &&
    grep -qF 'static NSSet<NSString *> *RIRunningBundleIDs(void) {' "$2/dotread-real.inc"
}
build() {   # $1 dir, $2 binary, $3 extra flags
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration $3 -I"$1" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$1/$2" test-dotread.m 2> "$1/$2.cc.txt"
}
sites() {   # $1 RunningIndicator.m, $2 quiet: the number of site checks that fail
  local R=$1 q=$2 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "RunningIndicator.m: a Dock icon's layout takes the step's read; the poll's pass (and a Dock Style change) reads anew" \
    "fn $R 'static void RIUpdate(UIView *iconView, NSSet<NSString *> *running) {' | grep -qF 'if (!running) running = RIRunningForStep(NO);' &&
     fn $R 'static void RIResyncDock(void) {' | grep -qF 'NSSet *running = RIWanted() ? RIRunningForStep(YES) : nil;'"
  c "  ... the running apps are read only there and in the debug dump (DMRunningDotsDebug)" \
    "[ \$(grep -c 'RIRunningBundleIDs()' $R) = 2 ] && fn $R '$STEP' | grep -qF 'RIRunningBundleIDs()' && fn $R 'void DMRunningDotsDebug(void) {' | grep -qF 'RIRunningBundleIDs()'"
  c "  ... forgotten at the main run loop's next activity of any kind, first among its observers (before the commit's layout)" \
    "fn $R '$STEP' | grep -qF 'CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, kCFRunLoopAllActivities, false, 0,' &&
     fn $R '$STEP' | grep -qF 'CFRunLoopAddObserver(main, next, kCFRunLoopCommonModes);'"
  return $n
}

run() {   # $1 RunningIndicator.m, $2 work dir, $3 quiet: the number of failed checks (99: not built)
  local R=$1 d=$2 q=$3 n=0 s r out dn=0 ds=0
  mkdir -p "$d"
  cut "$R" "$d" || { echo "FAIL  $R: the code was not found"; return 99; }
  build "$d" t "" || { [ -n "$q" ] || cat "$d/t.cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  build "$d" td "-DDEBUG=1" || { [ -n "$q" ] || cat "$d/td.cc.txt"; echo "FAIL  the real code did not build (DEBUG)"; return 99; }
  for s in $("$d/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$("$d/t" "$s"); r=$?
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; r=1; }
    n=$((n + r))
    "$d/td" "$s" > /dev/null; r=$?; [ $r -ge 128 ] && r=1
    dn=$((dn + r)); ds=$((ds + 1))
  done
  if [ $dn = 0 ]; then [ -n "$q" ] || echo "PASS  the same $ds scenarios in a DEBUG build"; else [ -n "$q" ] || echo "FAIL  $dn check(s) fail in a DEBUG build"; n=$((n + dn)); fi
  [ -n "$q" ] || echo "-- site checks"
  sites "$R" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-dotread: all pass" || echo "test-dotread: FAILED ($rc check(s))"
[ -n "$DR_RI_M" ] && exit $rc

# the code before the fix: every layout reads for itself, the poll reads with RIRunningBundleIDs (byte-identical to 1.8.7.4's file before O5)
unfix() { perl -0777 -pe '
  $n = 0;
  $n += s/\Q(the 0.75 s poll while the screen is on, and the Dock'"'"'s icon layouts: RIRunningForStep); an app that is no longer running is forgotten. Main\E\n\Q\/\/ thread only.\E\n/(the 0.75 s poll while the screen is on, and each Dock icon'"'"'s layout); an app that is no longer running is forgotten. Main thread only.\n/;
  $n += s/\n\/\/ The running set the Dock'"'"'s icons are laid out with: .*?\nstatic NSSet<NSString \*> \*gRIStepRunning;.*?\n    gRIStepRunning = running;\n    return running;\n\}\n/\n/s;
  $n += s/\Qor nil = this step'"'"'s)\E/or nil = read it here)/;
  $n += s/\Qif (!running) running = RIRunningForStep(NO);\E/if (!running) running = RIRunningBundleIDs();/;
  $n += s/\QRIWanted() ? RIRunningForStep(YES) : nil;   \/\/ (read anew, once per pass, not once per icon)\E/RIWanted() ? RIRunningBundleIDs() ?: [NSSet set] : nil;   \/\/ (once per pass, not once per icon)/;
  END { exit($n == 5 ? 0 : 1) }' "$1"; }

echo "-- made-to-fail copies (each must fail)"
k=0
mtf() {   # $1 what, $2 perl expression on RunningIndicator.m (the whole file at once), or "unfix"
  local d="$W/m$((++k))" c
  mkdir -p "$d"; c="$d/RunningIndicator.m"
  if [ "$2" = unfix ]; then unfix "$R0" > "$c"; else perl -0777 -pe "$2" "$R0" > "$c"; fi
  cmp -s "$c" "$R0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
  run "$c" "$d/w" q; local n=$?
  if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
}
mtf "the code before the fix (every layout reads for itself)" unfix
mtf "the step's read never used (each layout reads)" 's/\n    if \(gRIStepRunning && !fresh\) return gRIStepRunning;//'
mtf "the step's read never forgotten (the observer not added)" 's/\n        CFRunLoopAddObserver\(main, next, kCFRunLoopCommonModes\);\n        CFStringRef mode = [^\n]*\n        if \(mode\) [^\n]*//'
mtf "forgotten by a main-queue block instead of at the run loop's next activity" 's/        CFRunLoopRef main = CFRunLoopGetMain\(\);\n.*?CFRelease\(next\);[^\n]*\n/        dispatch_async(dispatch_get_main_queue(), ^{ gRIStepRunning = nil; });\n/s'
mtf "forgotten after the commit has laid out (an order after Core Animation's)" 's/kCFRunLoopAllActivities, false, 0,/kCFRunLoopAllActivities, false, 2500000,/'
mtf "not forgotten while the run loop is in a mode of its own" 's/\n        CFStringRef mode = [^\n]*\n        if \(mode\) [^\n]*//'
mtf "the poll takes the step's read instead of reading anew" 's/RIRunningForStep\(YES\)/RIRunningForStep(NO)/'
mtf "the poll's read not kept for what is laid out after it in the step" 's/\n    gRIStepRunning = running;\n/\n    if (!fresh || !gRIStepRunning) gRIStepRunning = running;\n/'

REF=$DR_REF_M
if [ -z "$REF" ]; then
  REF="$W/ref/RunningIndicator.m"; mkdir -p "$W/ref"
  unfix "$R0" > "$REF" || { echo "FAIL  the fix could not be taken out of this copy (pass DR_REF_M=<RunningIndicator.m before the fix>)"; exit 1; }
  echo "-- the code before the fix: this file with the fix taken out"
else echo "-- the code before the fix: $REF"; fi
mkdir -p "$W/old" "$W/new"
cut "$REF" "$W/old" && build "$W/old" t "" || { cat "$W/old/t.cc.txt"; echo "FAIL  the code before the fix did not build"; exit 1; }
cut "$R0" "$W/new" && build "$W/new" t "" || { echo "FAIL  this code did not build for the traces"; exit 1; }
total=0; bad=0; badlist=""
for s in $("$W/old/t" list); do
  out=$("$W/old/t" "$s")
  total=$((total + $(printf '%s\n' "$out" | grep -c '^PASS\|^FAIL')))
  f=$(printf '%s\n' "$out" | grep -c '^FAIL'); bad=$((bad + f))
  [ "$f" -gt 0 ] && badlist="$badlist $s($f)"
done
# the checks of the new behaviour: the reads (docklayout 2, sidedock 1, nextstep 1, poll 1) and the same-step case by design (samestep 1)
if [ "$bad" = 6 ] && [ "$badlist" = " docklayout(2) sidedock(1) nextstep(1) poll(1) samestep(1)" ]; then
  echo "PASS  the code before the fix: $bad of $total checks fail, the new ones:$badlist; every as-before check passes there"
else echo "FAIL  the code before the fix: $bad of $total fail:$badlist (expected the read counts and the same-step case only)"; rc=1; fi

echo "-- the same dots: random worlds on this code and on the code before the fix"
"$W/new/t" trace 1874 300 > "$W/new/trace.txt" || { echo "FAIL  this code ended badly in the random worlds"; exit 1; }
"$W/old/t" trace 1874 300 > "$W/old/trace.txt" || { echo "FAIL  the code before the fix ended badly in the random worlds"; exit 1; }
grep '^L' "$W/new/trace.txt" > "$W/new/looks.txt"; grep '^L' "$W/old/trace.txt" > "$W/old/looks.txt"
looks=$(wc -l < "$W/new/looks.txt" | tr -d ' ')
shown=$(grep -c '[0-9]\.[0-9][0-9],[0-9]' "$W/new/looks.txt")
# R w<n> reads <n> asks <n> commits <n> steps <n>
res=$(paste -d'|' "$W/old/trace.txt" "$W/new/trace.txt" | awk -F'|' '$1 ~ /^R / { split($1, o, " "); split($2, m, " "); w++; ro += o[4]; rn += m[4]; ao += o[6]; an += m[6]; st += m[10]
    if (m[4] > o[4] || o[2] != m[2]) more++ } END { printf "%d %d %d %d %d %d %d\n", w, ro, rn, ao, an, st, more }')
read -r worlds ro rn ao an steps more <<< "$res"
if cmp -s "$W/new/looks.txt" "$W/old/looks.txt" && [ "$worlds" = 300 ] && [ "$looks" -gt 20000 ] && [ "$shown" -gt 1000 ] && [ "$more" = 0 ] && [ "$rn" -lt "$ro" ]; then
  echo "PASS  300 random worlds, $steps steps (events in a timer, the run loop's blocks, a version 0 source or the main queue; polls; switch and Lynx changes), $looks looks: the same dots and the same remembered processes at every look; reads of the running apps $ro -> $rn, MacStatusBar's sets asked $ao -> $an, no world reads more"
else
  diff "$W/old/looks.txt" "$W/new/looks.txt" | head -4
  echo "FAIL  the random worlds: $worlds worlds, $looks looks ($shown with a dot), $more worlds read more, reads $ro -> $rn"; rc=1
fi
exit $rc
