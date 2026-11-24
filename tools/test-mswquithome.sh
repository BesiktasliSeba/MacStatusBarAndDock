#!/bin/bash
# test-mswquithome.sh: Swipe Up to Quit keeps the Mac Switcher's view open, on every engine (1.8.8.4) -- the rule in statusbar/MSWFlick.h
# (test-mswquithome.c), the real Home tick run through state sequences (test-mswquithome.m: DMMSWHomeTick cut out of MacSwitcherButton.h;
# HT_BUTTON_H: another copy, e.g. the code before the fix) and the wiring: the quit marks its app as quit from the view and sends the flight to the
# render server before the quit's own work; the Home tick asks the rule with the app seen in front last; the marks end with the view.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d "${TMPDIR:-/tmp}/test-mswquithome.XXXXXX") || exit 1
trap 'rm -rf "$W"' EXIT
clang -std=c11 -O1 -Wall -Werror -o "$W/rule" test-mswquithome.c || exit 1
"$W/rule"; rc=$?
f=../statusbar/MacSwitcher.h; h=../statusbar/MacSwitcherButton.h
awk '/^static void DMMSWHomeTick\(void\) \{/,/^\}/' "${HT_BUTTON_H:-$h}" > "$W/hometick.inc"
if [ -s "$W/hometick.inc" ] && clang -O1 -fobjc-arc -Wall -Wno-unused-function -I"$W" -framework Foundation -o "$W/tick" test-mswquithome.m; then
  "$W/tick" || rc=1
else echo "FAIL  the Home tick (DMMSWHomeTick) could not be cut out of ${HT_BUTTON_H:-$h} and built"; rc=1; fi
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; rc=1; }
# the quit (both gestures: the finger's flick and the trackpad's two-finger swipe end in DMMSWFlickQuit)
q=$(awk '/^__attribute__\(\(noinline\)\) static void DMMSWFlickQuit\(DMMSWTile \*t, NSString \*how\) \{/,/^\}/' "$f")
# (the release build's code: the debug-only blocks taken out)
r=$(echo "$q" | awk '/^#if DEBUG/ {d=1; next} d && /^#(else|endif)/ {d=0; next} !d {print}')
ln() { echo "$r" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }
lay=$(ln 'DMMSWLayOutTiles();'); fl=$(ln '[CATransaction flush];'); mk=$(ln '[gMSWQuitHere addObject:b];'); af=$(ln 'DMMSWAfter(flight, ^{'); fq=$(ln 'DMForceQuitBundle(b);')
if [ -n "$lay" ] && [ -n "$fl" ] && [ -n "$mk" ] && [ -n "$af" ] && [ -n "$fq" ] && [ "$lay" -lt "$fl" ] && [ "$fl" -lt "$af" ] && [ "$mk" -lt "$af" ] && [ "$af" -lt "$fq" ]; then
  pass "DMMSWFlickQuit: the flight and the close-up go to the render server and the app is marked as quit from the view; the quit comes after the flight"
else fail "$f: DMMSWFlickQuit does not flush, mark, then quit after the flight (layout $lay, flush $fl, mark $mk, after $af, quit $fq)"; fi
[ "$(echo "$r" | grep -c 'DMForceQuitBundle(')" = 1 ] && pass "DMMSWFlickQuit quits once (release code)" || fail "$f: DMMSWFlickQuit's release code quits more or less than once"
if echo "$q" | grep -qF 'double flight = MSBReduceMotion() ? 0.15 : 0.28;' && echo "$q" | grep -qF '[UIView animateWithDuration:flight delay:0 '; then
  pass "the quit waits exactly the flight's own time (0.28 s, 0.15 s with Reduce Motion)"
else fail "$f: the flight's time and the quit's wait are not the same value"; fi
if echo "$q" | grep -qF 'if (DMTestFlag("/tmp/msw-quitold")) {' && ! echo "$r" | grep -q 'msw-quitold'; then
  pass "the old way only behind the debug builds' test flag (release builds: never)"
else fail "$f: DMMSWFlickQuit's test flag is not debug-only"; fi
body() { awk -v s="$2" 'index($0, s) == 1 { f = 1 } f { print } f && /^\}/ { exit }' "$1"; }
for g in DMMSWFlickEnd DMMSWScrollPan; do
  case $g in DMMSWFlickEnd) sig='__attribute__((noinline)) static BOOL DMMSWFlickEnd(UIPanGestureRecognizer *g) {';; *) sig='__attribute__((noinline)) static void DMMSWScrollPan(UIPanGestureRecognizer *g) {';; esac
  body "$f" "$sig" | grep -q 'DMMSWFlickQuit(t, ' && pass "$g quits through DMMSWFlickQuit" || fail "$f: $g does not quit through DMMSWFlickQuit"
done
# the mark lives while the view is open
t=$(awk '/^static void DMMSWTeardown\(void\) \{/,/^\}/' "$f")
echo "$t" | grep -qF '[gMSWQuitHere removeAllObjects];' && pass "DMMSWTeardown ends the marks (a later Home by another way closes the next view)" || fail "$f: DMMSWTeardown keeps gMSWQuitHere"
# (every way a view ends clears them -- the teardown and the close under a desktop switch's slide: a mark kept past its view made the next view
#  over that app stay at a Home by the gesture or at the app quitting by itself; 1.8.8.4 review)
ends=$(awk '/^(static|__attribute__)/ && /\{ *$/ {body=""; name=$0; inf=1} inf {body = body "\n" $0} inf && /^\}/ {inf=0; if (body ~ /gMSWOpen = NO;/) print (body ~ /\[gMSWQuitHere removeAllObjects\];/ ? "clears" : "KEEPS") "|" name}' "$f")
if [ "$(echo "$ends" | grep -c '^clears|')" -ge 2 ] && ! echo "$ends" | grep -q '^KEEPS|'; then
  pass "every way the view ends clears the marks ($(echo "$ends" | grep -c '^clears|') places: $(echo "$ends" | sed 's/.*static void \([A-Za-z]*\).*/\1/' | tr '\n' ' '))"
else fail "$f: a place that ends the view keeps gMSWQuitHere: $(echo "$ends" | grep '^KEEPS|' | cut -d'|' -f2 | tr '\n' ' ')"; fi
[ "$(grep -c 'gMSWQuitHere addObject' "$f" "$h" ../statusbar/*.x | awk -F: '{s+=$2} END {print s}')" = 1 ] && pass "only Swipe Up to Quit marks an app as quit from the view" || fail "gMSWQuitHere is added to elsewhere"
# the Home tick
k=$(awk '/^static void DMMSWHomeTick\(void\) \{/,/^\}/' "$h")
if echo "$k" | grep -qF 'BOOL quitHere = was.length && [gMSWQuitHere containsObject:was];' && echo "$k" | grep -qF 'NSString *was = lastFront;' \
   && echo "$k" | grep -qF 'if (front.length) lastFront = front;'; then
  pass "DMMSWHomeTick: the app seen in front last, and whether the view quit it"
else fail "$h: DMMSWHomeTick does not read the app seen in front last against gMSWQuitHere"; fi
if echo "$k" | grep -qF 'if (MSBDMSWHomeCloses(frontAtOpen.length > 0, front.length > 0, gMSWSwitching, own, quitHere)) {' \
   && [ "$(echo "$k" | grep -c 'DMMSWClose(')" = 1 ] \
   && [ "$(echo "$k" | grep -n -F 'DMMSWClose(nil, NO);' | cut -d: -f1)" -gt "$(echo "$k" | grep -n -F 'MSBDMSWHomeCloses(' | cut -d: -f1)" ]; then
  pass "DMMSWHomeTick closes the view only on MSWFlick.h's rule"
else fail "$h: DMMSWHomeTick closes the view outside MSBDMSWHomeCloses"; fi
echo "$k" | grep -qF 'DMMSWFocusAgain(' && pass "the view takes the keyboard focus again after the Home a quit from it brought" || fail "$h: no DMMSWFocusAgain after the quit's Home"
echo "$k" | grep -qF 'BOOL own = CACurrentMediaTime() - gMSWOwnHomeAt < 3.0;' && pass "the view's own Home (3 s) unchanged" || fail "$h: the own-Home window changed"
exit $rc
