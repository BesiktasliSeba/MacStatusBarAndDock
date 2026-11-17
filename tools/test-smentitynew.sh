#!/bin/bash
# test-smentitynew.sh: DMSMEntityNew (statusbar/SMEngineAPI.h) gives the object Apple's init made back exactly once, whether the init succeeds or
# fails: no second free when it fails (see test-smentitynew.m). The real DMSMIsEntity and DMSMEntityNew are cut out of SMEngineAPI.h (SEN_H: another
# copy, e.g. the code before the fix), built with ARC as in the tweak, release and DEBUG, against a stand-in entity built without ARC that counts.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=${SEN_H:-../statusbar/SMEngineAPI.h}
fndef() {   # a static function's definition, whole, by its braces (the first line has its name and "{")
  awk -v n="$2" '
    !f && $0 ~ ("^static [^(=]*[ *]" n "\\(") && index($0, "{") { f = 1 }
    f { print; t = $0; o = gsub(/\{/, "", t); t = $0; c = gsub(/\}/, "", t); d += o - c; if (d <= 0) exit }
  ' "$1"
}
{ fndef "$H" DMSMIsEntity; fndef "$H" DMSMEntityNew; } > "$W/sen-cut.inc"
/usr/bin/grep -q 'initWithApplicationForMainDisplay:' "$W/sen-cut.inc" && /usr/bin/grep -q 'initWithApplication:sceneHandleProvider:displayIdentity:' "$W/sen-cut.inc" ||
  { echo "FAIL  $H: DMSMEntityNew with both inits not found"; echo "test-smentitynew: FAILED"; exit 1; }
fails=0
clang -fno-objc-arc -DSEN_STANDIN -Wall -c -o "$W/standin.o" test-smentitynew.m || { echo "FAIL  the stand-in did not build"; exit 1; }
for dbg in 0 1; do
  D="-DNDEBUG -O2"; [ $dbg = 1 ] && D="-DDEBUG=1 -O0"
  clang -fobjc-arc $D -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$W" -framework Foundation -o "$W/t$dbg" test-smentitynew.m "$W/standin.o" 2> "$W/cc.txt" ||
    { cat "$W/cc.txt"; echo "FAIL  the real code did not build (DEBUG $dbg)"; fails=1; continue; }
  [ -s "$W/cc.txt" ] && { echo "FAIL  warnings (DEBUG $dbg):"; cat "$W/cc.txt"; fails=1; }
  echo "-- DEBUG $dbg"
  "$W/t$dbg" || fails=1
done
[ $fails = 0 ] && echo "test-smentitynew: all pass" || { echo "test-smentitynew: FAILED"; exit 1; }
