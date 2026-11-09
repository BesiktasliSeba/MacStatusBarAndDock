#!/bin/bash
# Mac test of GitHub #12 (plans/rootcause-issue12.md): a stage a switcher gesture's modifier still holds, once its transaction is over, counts as held; what waits for the
# gesture waits for the modifier too; the guard on iPadOS 16's snapshot cache. Runs test-smgesturemodifier.m on the code as built, then the wiring.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=../statusbar/SMGestureHook.h; G=../statusbar/SMGestureHold.h; D=../statusbar/SMDesktop.h
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }
{
  grep -q 'gSMGestureEndedAt = 0;' $G || { echo 'static CFTimeInterval gSMGestureEndedAt;   // (not in this source)'; echo 'static const CFTimeInterval kSMModifierHoldMax = 5.0;   // (not in this source)'; }
  echo 'static BOOL DMSMSigOK(id o, SEL s, NSString *sig, const char *name) { (void)sig; (void)name; return [o respondsToSelector:s]; }'
  echo 'static NSString *DMSMSigObj(void) { return @""; }'
  echo 'static int gSMAPIFails = 0; static void DMSMAPIFail(NSString *what, NSString *why) { (void)what; (void)why; gSMAPIFails++; }'
  echo '#define _cmd_stub ((SEL)sel_registerName("appLayoutsToCacheSnapshotsWithVisibleRange:numberOfSnapshotsToCache:biasForward:"))'
  if grep -q '^static id DMSMCacheRange(' $H; then
    grep -F 'static id (*o_SMCacheRange)(id, SEL, NSRange, unsigned long long, BOOL);' $H
    fn $H 'static id DMSMCacheRange(id self, SEL _cmd, NSRange visible, unsigned long long count, BOOL biasForward) {'
  else
    echo 'static id (*o_SMCacheRange)(id, SEL, NSRange, unsigned long long, BOOL);'
    echo 'static id DMSMCacheRange(id self, SEL _cmd, NSRange visible, unsigned long long count, BOOL biasForward) { return o_SMCacheRange(self, _cmd, visible, count, biasForward); }   // (not in this source: no guard)'
  fi
} > "$W/smgesturemodifier-gen.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-undefined-internal -I"$W" -framework Foundation -framework QuartzCore -o "$W/t" test-smgesturemodifier.m
fails=0
"$W/t" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the transaction's end hook notes the end the modifier's few seconds count from" "fn $H 'static void DMSMGTDidComplete(id self, SEL _cmd) {' | grep -qF 'gSMGestureEndedAt = CACurrentMediaTime();'"
check "the card's own write of the desktop (DMSMCardWriteDesk) leaves it to the join rule while a gesture holds a stage: the check first" \
  "fn $D 'static BOOL DMSMCardWriteDesk(id ctx,' | sed -n 4p | grep -qF 'if (DMSMGestureCtx(ctx)) {'"
check "the guard's install: iPadOS 16 only, the method in its exact shape, at the engine's start" \
  "fn $H 'static void DMSMCacheRangeInstall(void) {' | grep -qF 'operatingSystemVersion.majorVersion != 16) return;' \
   && fn $H 'static void DMSMCacheRangeInstall(void) {' | grep -qF '\"@48@0:8{_NSRange=QQ}16Q32B40\"' \
   && fn $H 'static void DMSMGestureHoldInstall(void) {' | grep -qF 'DMSMCacheRangeInstall();'"
check "a crash in Apple's code under the guard is not pinned on the engine (transparent), and the guard leaves a release build's record" \
  "grep -q '^sym MacStatusBarCore ^_?DMSMCacheRange\$ transparent\$' crashmap-rules.txt && fn $H 'static id DMSMCacheRange(id self,' | grep -qF 'DM_FEATURE_MARK(\"sm-snapshot-cache-guard\");' \
   && fn $H 'static id DMSMCacheRange(id self,' | grep -qF 'DMSMAPIFail('"
[ $fails = 0 ] && echo "test-smgesturemodifier: all pass" || { echo "test-smgesturemodifier: FAILED"; exit 1; }
