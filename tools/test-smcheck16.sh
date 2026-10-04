#!/bin/bash
# Mac test of the Stage Manager engine's self-check against real iPadOS 16 builds' API tables (tools/smcheck-fixtures, made from each build's
# dyld_shared_cache by tools/make-smcheck-fixture.py), the cut-back choice and the Settings / Report a Problem texts. One process per build.
# Expected per build: the core rows that fail (engine off), the optional rows missing, the features left with no alternative, the cut-back path.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -DDEBUG=1 -framework Foundation -framework CoreGraphics -o "$W/t" test-smcheck16.m
R="-[SBAppLayout appLayoutByRemovingItemInLayoutRole:] missing"
CORE161="-[SBDisplayItemLayoutAttributes attributedSize] missing|-[SBDisplayItemLayoutAttributes normalizedCenter] missing|-[SBDisplayItemLayoutAttributes attributesByModifyingAttributedSize:] missing|-[SBDisplayItemLayoutAttributes attributesByModifyingNormalizedCenter:] missing"
IV="ivar SBSwitcherChamoisLayoutAttributes._containerBounds missing"
CAPS="window size caps from the stage's own container (else the largest screen)"
fail=0
run() { "$W/t" "smcheck-fixtures/$1.txt" "$2" "$3" "$4" "$5" "$6" || fail=1; }
#   build   core      optional      features off  cut     version
run 20B82  "$CORE161" "$R|$IV"      "$CAPS"       leaf    16.1
run 20B101 "$CORE161" "$R|$IV"      "$CAPS"       leaf    16.1.1
run 20C65  ""         "$R"          ""            leaf    16.2
run 20D47  ""         "$R"          ""            leaf    16.3
run 20D67  ""         "$R"          ""            leaf    16.3.1
run 20E246 ""         ""            ""            remove  16.4
run 20E252 ""         ""            ""            remove  16.4.1
run 20F66  ""         ""            ""            remove  16.5
run 20F75  ""         ""            ""            remove  16.5.1
run 20G75  ""         ""            ""            remove  16.6
run 20G81  ""         ""            ""            remove  16.6.1
run 20H19  ""         ""            ""            remove  16.7
run 20H330 ""         ""            ""            remove  16.7.7
rm -rf "$W"
[ $fail = 0 ] && echo "test-smcheck16: ALL PASS (13 builds)" || echo "test-smcheck16: FAILURES"
exit $fail
