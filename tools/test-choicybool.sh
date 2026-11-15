#!/bin/bash
# test-choicybool.sh: Choicy's switches read without an exception (1.8.7.5, audit L23 of 1.8.7.2). If Choicy's SpringBoard block held an array,
# a dictionary, data or a date under customTweakConfigurationEnabled, tweakInjectionDisabled or overwriteGlobalTweakConfiguration (a damaged
# file, another package's write), -boolValue raised in the root helper 3 s after each of its starts, so launchd restarted it in a loop: SSH
# switching, ejects, iCleaner, engine exclusivity, Sleep Guard and Keep Tailspin Off all stopped. One reader now, common/ExclusiveChoice.h
# MSBDExChoicyBool: a number or a string reads as Choicy reads it (-boolValue), anything else is off.
# 1. test-choicybool.m on the real code: ExclusiveChoice.h (CB_X: another copy, e.g. the code before the fix) and sshtoggled's
#    MacStatusBarSwitchedOff cut out of main.m (CB_SSH_M), each switch with every kind of value;
# 2. site checks: every read of those switches in main.m and ExclusiveChoice.h goes through the reader, no -boolValue of a Choicy value left;
# 3. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${CB_X:-../common/ExclusiveChoice.h}; M0=${CB_SSH_M:-../macsettings/sshtoggled/main.m}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

compiled() {   # $1 ExclusiveChoice.h, $2 main.m, $3 quiet: the scenarios built on them and run; 0 when every check passes
  local d=$W/c$RANDOM; mkdir -p "$d/dir"; cp "$1" "$d/ExclusiveChoice.h"
  { grep -F 'static BOOL IsRegular(NSString *path) {' "$2"; grep -F 'static BOOL Exists(NSString *path) {' "$2"
    fn "$2" 'static NSInteger ChoicyMode(NSDictionary *sb) {'; fn "$2" 'static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how) {'; } > "$d/cut.inc"
  if ! clang -fobjc-arc -fobjc-arc-exceptions -Wall -Wno-unused-function -I"$d" -DCB_X="\"$d/ExclusiveChoice.h\"" -DCB_DIR="\"$d/dir\"" \
         -framework Foundation -o "$d/t" test-choicybool.m > "$d/build.txt" 2>&1; then
    [ -n "$3" ] || { echo "(test-choicybool.m does not build against $1 / $2:)"; grep -m 3 'error:' "$d/build.txt"; }; return 1
  fi
  if [ -n "$3" ]; then "$d/t" > /dev/null 2>&1; else "$d/t"; fi
}

sites() {   # $1 ExclusiveChoice.h, $2 main.m, $3 quiet; the number of failed checks
  local X=$1 M=$2 q=$3 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "the reader: a number or a string's -boolValue, anything else off" \
    "fn $X 'static inline BOOL MSBDExChoicyBool(id v) {' | grep -qxF '    return ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) && [v boolValue];'"
  c "MSBDExChoicyApply: the custom configuration and the deny list's override through it" \
    "fn $X 'static inline BOOL MSBDExChoicyApply(' | grep -qF 'if (!MSBDExChoicyBool(sb[@\"customTweakConfigurationEnabled\"])) return changed;' \
     && fn $X 'static inline BOOL MSBDExChoicyApply(' | grep -qF 'MSBDExSetMembership(list, MSBDExChoicyBool(sb[@\"overwriteGlobalTweakConfiguration\"]) ? deny : @[], keep, rk, record)'"
  c "MSBDExUserOff: the custom configuration through it" \
    "fn $X 'static inline BOOL MSBDExUserOff(' | grep -qF 'NSInteger mode = MSBDExChoicyBool(sb[@\"customTweakConfigurationEnabled\"]) ? MSBDExChoicyMode(sb) : 0;'"
  c "the root helper's MacStatusBarSwitchedOff: both switches through it" \
    "fn $M 'static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how) {' | grep -qF '[sb isKindOfClass:[NSDictionary class]] && MSBDExChoicyBool(sb[@\"customTweakConfigurationEnabled\"])) {' \
     && fn $M 'static BOOL MacStatusBarSwitchedOff(NSString *status, NSString **how) {' | grep -qF 'if (MSBDExChoicyBool(sb[@\"tweakInjectionDisabled\"])) return NO;'"
  c "no -boolValue of a value left in the root helper or the table but the reader's own (and no respondsToSelector: guard of its own)" \
    "! grep -q 'boolValue\\]' $M && [ \$(grep -c 'boolValue\\]' $X) = 1 ] && ! grep -q 'respondsToSelector:@selector(boolValue)' $X"
  return $n
}

rc=0
if compiled "$X0" "$M0"; then echo "PASS  the scenarios (test-choicybool.m against $X0 and $M0)"; else echo "FAIL  the scenarios (test-choicybool.m against $X0 and $M0)"; rc=1; fi
sites "$X0" "$M0" || rc=1
if [ -z "$CB_X$CB_SSH_M" ]; then
  mtf() {   # $1 name, $2 x|m (the file the filter changes), $3 a filter (stdin to stdout) that takes one part of the fix out
    local x=$X0 m=$M0
    if [ "$2" = x ]; then "$3" < "$X0" > "$W/x.h"; x=$W/x.h; else "$3" < "$M0" > "$W/m.m"; m=$W/m.m; fi
    if cmp -s "$x" "$X0" && cmp -s "$m" "$M0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if compiled "$x" "$m" quiet && sites "$x" "$m" quiet; then echo "FAIL  made-to-fail ($1): still passes"; rc=1
    elif compiled "$x" "$m" quiet; then echo "FAIL  made-to-fail ($1): caught by the site checks only"; rc=1
    else echo "PASS  made-to-fail ($1): caught by the scenarios"; fi
  }
  untyped() { sed -e 's/return (\[v isKindOfClass:\[NSNumber class\]\] || \[v isKindOfClass:\[NSString class\]\]) \&\& \[v boolValue\];/return [v boolValue];/'; }
  numbers_only() { sed -e 's/return (\[v isKindOfClass:\[NSNumber class\]\] || \[v isKindOfClass:\[NSString class\]\]) \&\& \[v boolValue\];/return [v isKindOfClass:[NSNumber class]] \&\& [v boolValue];/'; }
  apply_custom() { sed -e 's/if (!MSBDExChoicyBool(sb\[@"customTweakConfigurationEnabled"\])) return changed;/if (![sb[@"customTweakConfigurationEnabled"] boolValue]) return changed;/'; }
  apply_overwrite() { sed -e 's/MSBDExChoicyBool(sb\[@"overwriteGlobalTweakConfiguration"\]) ? deny/[sb[@"overwriteGlobalTweakConfiguration"] boolValue] ? deny/'; }
  helper_custom() { sed -e 's/\[sb isKindOfClass:\[NSDictionary class\]\] \&\& MSBDExChoicyBool(sb\[@"customTweakConfigurationEnabled"\])) {/[sb isKindOfClass:[NSDictionary class]] \&\& [sb[@"customTweakConfigurationEnabled"] boolValue]) {/'; }
  helper_injection() { sed -e 's/if (MSBDExChoicyBool(sb\[@"tweakInjectionDisabled"\])) return NO;/if ([sb[@"tweakInjectionDisabled"] boolValue]) return NO;/'; }
  mtf "the reader without its type check" x untyped
  mtf "the reader taking numbers only (a hand edit's \"1\" read as off)" x numbers_only
  mtf "MSBDExChoicyApply's custom configuration read unchecked" x apply_custom
  mtf "MSBDExChoicyApply's deny-list override read unchecked" x apply_overwrite
  mtf "the helper's custom configuration read unchecked" m helper_custom
  mtf "the helper's tweakInjectionDisabled read unchecked" m helper_injection
fi
[ $rc = 0 ] && echo "test-choicybool: all pass" || echo "test-choicybool: FAILED"
exit $rc
