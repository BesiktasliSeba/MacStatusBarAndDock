#!/bin/bash
# Mac test of GitHub #12 (plans/rootcause-issue12.md): a stage a switcher gesture's modifier still holds, once its transaction is over, counts as held; what waits for the
# gesture waits for the modifier too; the guard on iPadOS 16's snapshot cache and its install (1.8.7: by the method's argument types -- the whole encoding
# compared before never matched the compiler's, so the guard was never in). Runs test-smgesturemodifier.m on the code as built, then the wiring, then
# made-to-fail copies of SMGestureHook.h that must fail the run.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=../statusbar/SMGestureHook.h; G=../statusbar/SMGestureHold.h; D=../statusbar/SMDesktop.h; A=../statusbar/SMEngineAPI.h
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }
gen() {   # gen <SMGestureHook.h>: the guard and its install as built, the install's iPadOS version and class made the test's
  local h="$1"
  grep -q 'gSMGestureEndedAt = 0;' $G || { echo 'static CFTimeInterval gSMGestureEndedAt;   // (not in this source)'; echo 'static const CFTimeInterval kSMModifierHoldMax = 5.0;   // (not in this source)'; }
  echo 'static BOOL DMSMSigOK(id o, SEL s, NSString *sig, const char *name) { (void)sig; (void)name; return [o respondsToSelector:s]; }'
  fn $A 'static NSString *DMSMNormEncoding(const char *e) {'
  fn $A 'static NSString *DMSMExpect(const char *ret, ...) {'
  grep -F 'static NSString *DMSMSigOfMethod(Method m) {' $A
  grep -F '#define DMSM_SIG(name, ...) ' $A
  grep -F 'DMSM_SIG(DMSMSigObj, @encode(id))' $A
  echo 'static int gSMAPIFails = 0; static void DMSMAPIFail(NSString *what, NSString *why) { (void)what; (void)why; gSMAPIFails++; }'
  echo 'static int gTestMajor = 16; static const char *gTestClass = "SBSwitcherModifier"; static int gHooks = 0;'
  echo 'static void MSHookMessageEx(Class c, SEL s, IMP r, IMP *o) { Method m = class_getInstanceMethod(c, s); gHooks++; *o = method_setImplementation(m, r); }'
  echo '#define _cmd_stub ((SEL)sel_registerName("appLayoutsToCacheSnapshotsWithVisibleRange:numberOfSnapshotsToCache:biasForward:"))'
  if grep -q '^static id DMSMCacheRange(' "$h"; then
    grep -F 'static id (*o_SMCacheRange)(id, SEL, NSRange, unsigned long long, BOOL);' "$h"
    grep -q '^static SEL gSMCacheList;' "$h" && echo 'static SEL gSMCacheList;' || echo 'static SEL gSMCacheList;   // (not in this source)'
    fn "$h" 'static id DMSMCacheRange(id self, SEL _cmd, NSRange visible, unsigned long long count, BOOL biasForward) {'
    fn "$h" 'static void DMSMCacheRangeInstall(void) {' | sed -e 's/\[NSProcessInfo processInfo\]\.operatingSystemVersion\.majorVersion/gTestMajor/' -e 's/objc_getClass("SBSwitcherModifier")/objc_getClass(gTestClass)/'
  else
    echo 'static id (*o_SMCacheRange)(id, SEL, NSRange, unsigned long long, BOOL); static SEL gSMCacheList;'
    echo 'static id DMSMCacheRange(id self, SEL _cmd, NSRange visible, unsigned long long count, BOOL biasForward) { return o_SMCacheRange(self, _cmd, visible, count, biasForward); }   // (not in this source: no guard)'
    echo 'static void DMSMCacheRangeInstall(void) { }   // (not in this source)'
  fi
}
run() {   # run <SMGestureHook.h> <dir>: the test built on that source; its exit code
  mkdir -p "$2"; gen "$1" > "$2/smgesturemodifier-gen.h"
  clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-undefined-internal -I"$2" -framework Foundation -framework QuartzCore -o "$2/t" test-smgesturemodifier.m || return 2
  "$2/t"
}
fails=0
run $H "$W/as-built" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the transaction's end hook notes the end the modifier's few seconds count from" "fn $H 'static void DMSMGTDidComplete(id self, SEL _cmd) {' | grep -qF 'gSMGestureEndedAt = CACurrentMediaTime();'"
check "the card's own write of the desktop (DMSMCardWriteDesk) leaves it to the join rule while a gesture holds a stage: the check first" \
  "fn $D 'static BOOL DMSMCardWriteDesk(id ctx,' | sed -n 4p | grep -qF 'if (DMSMGestureCtx(ctx)) {'"
check "the guard's install: iPadOS 16 only, the method's argument types (no whole-encoding compare), at the engine's start" \
  "fn $H 'static void DMSMCacheRangeInstall(void) {' | grep -qF 'operatingSystemVersion.majorVersion != 16) return;' \
   && fn $H 'static void DMSMCacheRangeInstall(void) {' | grep -qF 'DMSMExpect(@encode(id), @encode(NSRange), @encode(unsigned long long), @encode(BOOL), NULL)' \
   && ! fn $H 'static void DMSMCacheRangeInstall(void) {' | grep -q 'strcmp\|method_getTypeEncoding' \
   && fn $H 'static void DMSMGestureHoldInstall(void) {' | grep -qF 'DMSMCacheRangeInstall();'"
# (the fact the 1.8.4-1.8.7 install missed: the iOS compiler writes this method's encoding with a frame size of 44, not 48 -- a BOOL argument counts 4)
SDK=~/theos/sdks/iPhoneOS16.5.sdk
if [ -d "$SDK" ]; then
  printf '#import <Foundation/Foundation.h>\n@interface M : NSObject @end\n@implementation M\n- (id)appLayoutsToCacheSnapshotsWithVisibleRange:(NSRange)r numberOfSnapshotsToCache:(unsigned long long)n biasForward:(BOOL)b { return nil; }\n@end\n' > "$W/enc.m"
  check "the iOS arm64 compiler's encoding of the method is @44@0:8{_NSRange=QQ}16Q32B40 (the old install's @48... never matched it)" \
    "clang -fobjc-arc -target arm64-apple-ios15.0 -isysroot $SDK -c $W/enc.m -o $W/enc.o 2>/dev/null && strings $W/enc.o | grep -qxF '@44@0:8{_NSRange=QQ}16Q32B40' && ! strings $W/enc.o | grep -qF '@48@0:8'"
else echo "SKIP  the iOS compiler's encoding (no iPhoneOS16.5.sdk here)"; fi
check "a crash in Apple's code under the guard is not pinned on the engine (transparent), and the guard leaves a release build's record" \
  "grep -q '^sym MacStatusBarCore ^_?DMSMCacheRange\$ transparent\$' crashmap-rules.txt && fn $H 'static id DMSMCacheRange(id self,' | grep -qF 'DM_FEATURE_MARK(\"sm-snapshot-cache-guard\");' \
   && fn $H 'static id DMSMCacheRange(id self,' | grep -qF 'DMSMAPIFail('"
echo "-- made-to-fail copies of SMGestureHook.h (each must fail the run):"
mtf() {   # mtf <name> <perl substitution>
  local d="$W/mtf$((++n))"; mkdir -p "$d"; cp $H "$d/SMGestureHook.h"; perl -0pi -e "$2" "$d/SMGestureHook.h"
  cmp -s $H "$d/SMGestureHook.h" && { echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; }
  if run "$d/SMGestureHook.h" "$d" > "$d/out" 2>&1; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1; else echo "PASS  made-to-fail copy $1 fails, as it must"; fi
}
n=0
mtf "the 1.8.4-1.8.7 install (the whole encoding, @48)" 's/    if \(!\[have isEqualToString:want\] \|\| !\[listHave isEqualToString:DMSMSigObj\(\)\]\) \{/    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "\@48\@0:8{_NSRange=QQ}16Q32B40")) {/'
mtf "the install with no version check (17 and 18 hooked too)" 's/    if \(\[NSProcessInfo processInfo\]\.operatingSystemVersion\.majorVersion != 16\) return;\n(    Class c = objc_getClass\("SBSwitcherModifier"\);)/$1/'
mtf "the install never sets the list the guard reads" 's/    gSMCacheList = list;\n//'
mtf "the install with no shape check at all" 's/ \|\| !\[listHave isEqualToString:DMSMSigObj\(\)\]\) \{/) {/; s/    if \(!\[have isEqualToString:want\]\) \{/    if (!m) {/'
[ $fails = 0 ] && echo "test-smgesturemodifier: all pass" || { echo "test-smgesturemodifier: FAILED"; exit 1; }
