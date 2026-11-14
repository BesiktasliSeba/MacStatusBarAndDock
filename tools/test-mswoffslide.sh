#!/bin/bash
# test-mswoffslide.sh: the Mac Switcher switched off during a desktop slide (1.8.7.3, audit L81). Settings off makes the iPad's desktops one
# (DMMSWCollapse); a switch still on its way then read the desktop places it began with in the one desktop left -- gMSWDesks[1] raised
# NSRangeException in DMMSWChangeDesktop (the other engines) or DMMSWSMAimChange (Stage Manager) and SpringBoard crashed. The off block now ends
# the running switch first (DMMSWGiveUpSwitch): its slide goes, both engines' aims are given up, and every later step of the switch -- a left
# picture still on its way, the change, the wait, the reveal's end -- checks the aim it belongs to and does nothing.
# The real switch of both paths, the off block and the give-up are cut out of statusbar/MacSwitcher.h and MacSwitcherSM.h (MSW_H / MSW_SM_H:
# other copies, e.g. the code before the fix) and run on the Mac (Mac Catalyst) on a clock of the test's own -- see test-mswoffslide.m; then two
# site checks; then made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
M0=${MSW_H:-../statusbar/MacSwitcher.h}; SM0=${MSW_SM_H:-../statusbar/MacSwitcherSM.h}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

OS_M=('static void DMMSWSwitchRun(NSUInteger to, NSString *why, CGFloat v, void (^done)(void)) {' 'static void DMMSWRunPendingLaunch(NSString *why) {'
      'static void DMMSWSwAim(CGFloat v, BOOL wasOpen) {'
      'static void DMMSWSwitchGo(NSUInteger to, NSString *why, CGFloat v, void (^done)(void), BOOL fromGesture, CFTimeInterval t0, UIView *old) {'
      'static void DMMSWSwChange(NSUInteger gen, CFTimeInterval since) {'
      'static void DMMSWSwWait(NSUInteger gen, NSString *fs, NSString *quiet, BOOL retry, NSString *head, CFTimeInterval t3) {'
      'static void DMMSWSwEnd(void) {' 'static void DMMSWCollapse(void) {' 'static void DMMSWApplyPref(BOOL want) {')
OS_M_NEW='static void DMMSWGiveUpSwitch(NSString *why) {'   # (cut out when there: the code before the fix has none)
OS_SM=('static void DMMSWSMSwitch(NSUInteger to, NSString *why, NSString *launching, CGFloat v, void (^done)(void)) {'
       'static void DMMSWSMSwitchEnd(NSInteger toId) {' 'static void DMMSWSMAbort(void) {' 'static void DMMSWSMAimChange(NSUInteger gen) {')

run() {   # $1 MacSwitcher.h, $2 MacSwitcherSM.h, $3 work dir, $4 quiet; the number of failed checks
  local M=$1 SM=$2 d=$3 q=$4 n=0 h out
  mkdir -p "$d"
  for h in "${OS_M[@]}"; do [ -n "$(fn "$M" "$h")" ] || { echo "FAIL  $M: no function starting \"$h\""; return 99; }; done
  for h in "${OS_SM[@]}"; do [ -n "$(fn "$SM" "$h")" ] || { echo "FAIL  $SM: no function starting \"$h\""; return 99; }; done
  { for h in "${OS_M[@]}"; do [ "$h" = 'static void DMMSWApplyPref(BOOL want) {' ] && fn "$M" "$OS_M_NEW"; fn "$M" "$h"; done
    for h in "${OS_SM[@]}"; do fn "$SM" "$h"; done; } > "$d/msw-real.inc"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t" test-mswoffslide.m || { echo "FAIL  the real code did not build"; return 99; }
  out=$("$d/t"); n=$?
  [ -n "$q" ] || echo "$out"
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  # (the test's stand-in for DMMSWChangeDesktop begins as the real one does: both desktop places read, the audit's crash site)
  c "DMMSWChangeDesktop begins by reading both desktop places (as its stand-in in the test does)" \
    "fn '$M' 'static NSString *DMMSWChangeDesktop(NSUInteger from, NSUInteger to) {' | sed -n 2p | grep -qxF '    NSInteger fromId = gMSWDesks[from].integerValue, toId = gMSWDesks[to].integerValue;'"
  # (no other way makes the desktops one under a running switch: the off block is DMMSWCollapse's only caller)
  c "the desktops become one only in the off block (DMMSWCollapse has no other caller)" \
    "[ \$(cat ../statusbar/*.h ../statusbar/*.x | grep -cF 'DMMSWCollapse();') = 1 ] && fn '$M' 'static void DMMSWApplyPref(BOOL want) {' | grep -qF 'DMMSWCollapse();'"
  return $n
}

run "$M0" "$SM0" "$W/real"; rc=$?
if [ -z "$MSW_H$MSW_SM_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 file (m|sm), $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" M=$M0 SM=$SM0 c
    mkdir -p "$d"
    if [ "$2" = m ]; then c="$d/MacSwitcher.h"; perl -0777 -pe "$3" "$M0" > "$c"; M=$c; cmp -s "$c" "$M0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    else c="$d/MacSwitcherSM.h"; perl -0777 -pe "$3" "$SM0" > "$c"; SM=$c; cmp -s "$c" "$SM0" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }; fi
    run "$M" "$SM" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1"; rc=1; fi
  }
  k=0
  mtf "a give-up that does nothing on the iPad (the review's case: an early return as its first line)" m 's/(static void DMMSWGiveUpSwitch\(NSString \*why\) \{\n)/$1    if (DMMSWIsMain()) return;\n/'
  mtf "the off block without the give-up" m 's/\n        DMMSWGiveUpSwitch\(\@"the Mac Switcher went off"\);[^\n]*//'
  mtf "the other engines' aim kept" m 's/        gMSWSwRun\+\+; gMSWSwGen\+\+;\n/        gMSWSwRun++;\n/'
  mtf "Stage Manager's aim kept" m 's/\n        DMMSWSMAbort\(\);\n        gMSWSwOld = nil;/\n        gMSWSwOld = nil;/'
  mtf "the switch still marked as running" m 's/(DMMSWCutLetGo\(\);\n)        gMSWSwitching = NO;\n(    \}\n    gMSWPendingSide = 0;)/$1$2/'
  mtf "a side request made on the way kept" m 's/\n    gMSWPendingSide = 0; gMSWSwQueued = 0;\n    DMMSWRunPendingLaunch\(why\);/\n    gMSWSwQueued = 0;\n    DMMSWRunPendingLaunch(why);/'
  mtf "an app opened on the way not opened at the off" m 's/\n    gMSWPendingSide = 0; gMSWSwQueued = 0;\n    DMMSWRunPendingLaunch\(why\);/\n    gMSWPendingSide = 0; gMSWSwQueued = 0;/'
  mtf "a left picture on its way not checked (the view open: drawn from its parts)" m 's/\n            if \(run != gMSWSwRun\) return;[^\n]*\n            DMMSWMark\(\[NSString stringWithFormat:\@"left picture: drawn from its parts/\n            DMMSWMark([NSString stringWithFormat:\@"left picture: drawn from its parts/'
  mtf "a left picture on its way not checked (the screen's picture)" m 's/\n            if \(run != gMSWSwRun\) return;[^\n]*\n            if \(!pic\) pic = DMMSWDeskPicture/\n            if (!pic) pic = DMMSWDeskPicture/'
  mtf "the other engines' reveal end not checked" m 's/\^\{ if \(gen == gMSWSwGen\) DMMSWSwEnd\(\); \}/^{ DMMSWSwEnd(); }/'
  mtf "Stage Manager's end not checked" sm 's/\^\{ if \(gen == gMSWSMAimGen\) DMMSWSMSwitchEnd\(toId\); \}/^{ DMMSWSMSwitchEnd(toId); }/'
fi
[ $rc = 0 ] && echo "test-mswoffslide: all pass" || echo "test-mswoffslide: FAILED"
exit $rc
