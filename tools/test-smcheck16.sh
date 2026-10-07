#!/bin/bash
# Mac test of the Stage Manager engine's self-check against real iPadOS 16 builds' API tables (tools/smcheck-fixtures, made from each build's
# dyld_shared_cache by tools/make-smcheck-fixture.py), the ways it picks on 16.0 / 16.1 (sized window model, 16.0's layout pass and size grid), the
# cut-back choice and the Settings / Report a Problem texts. One process per build.
# Expected per build: the core rows that fail (engine off), the optional rows missing, the features left with no alternative, the cut-back path, the
# version shown, the other ways the check must choose (never run on a device), the fraction edge of Apple's "sized" model there (0 = not that
# model), and how Settings offers the engine: "untested" = "Stage Manager (Untested)" + its note (iPadOS 16.0 only), "normal" = as on 16.2+ (16.1
# too: the owner, 4 Oct 2026), "off" = not offered.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d)
clang -fobjc-arc -Wall -Wno-unused-function -U__OBJC_BOOL_IS_BOOL -D__OBJC_BOOL_IS_BOOL=1 -DDEBUG=1 -framework Foundation -framework CoreGraphics -o "$W/t" test-smcheck16.m
R="-[SBAppLayout appLayoutByRemovingItemInLayoutRole:] missing"
IV="ivar SBSwitcherChamoisLayoutAttributes._containerBounds missing"
CAPS="window size caps from the stage's own container (else the largest screen)"
P160="auto layout: 16.0|size grid: grid object|window model: sized"
P161="window model: sized"
fail=0
run() { "$W/t" "smcheck-fixtures/$1.txt" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" || fail=1; }
# verified: the rows of the ways in use found there -- 16.2+: 102 (77 + sm-free's 17 Home rows + 1.3.8's 8 logic-test rows) minus the optional rows not
# there; 16.1: the sized window model (4 rows for the attributed 4) with 2 optional rows gone = 100; 16.0: also its own pass (12 rows for 16.1's 9) and
# grid object (2 for 3) = 102
#   build     core  optional  features off  cut     version  other ways  edge  offered   verified
run 20A371    ""    "$R|$IV"  "$CAPS"       leaf    16.0     "$P160"     1     untested  102
run 20A5349b  ""    "$R|$IV"  "$CAPS"       leaf    16.0     "$P160"     1     untested  102
run 20B82     ""    "$R|$IV"  "$CAPS"       leaf    16.1     "$P161"     10    normal    100
run 20B101    ""    "$R|$IV"  "$CAPS"       leaf    16.1.1   "$P161"     10    normal    100
run 20C65     ""    "$R"      ""            leaf    16.2     ""          0     normal    101
run 20D47     ""    "$R"      ""            leaf    16.3     ""          0     normal    101
run 20D67     ""    "$R"      ""            leaf    16.3.1   ""          0     normal    101
run 20E246    ""    ""        ""            remove  16.4     ""          0     normal    102
run 20E252    ""    ""        ""            remove  16.4.1   ""          0     normal    102
run 20F66     ""    ""        ""            remove  16.5     ""          0     normal    102
run 20F75     ""    ""        ""            remove  16.5.1   ""          0     normal    102
run 20G75     ""    ""        ""            remove  16.6     ""          0     normal    102
run 20G81     ""    ""        ""            remove  16.6.1   ""          0     normal    102
run 20H19     ""    ""        ""            remove  16.7     ""          0     normal    102
run 20H330    ""    ""        ""            remove  16.7.7   ""          0     normal    102
rm -rf "$W"
[ $fail = 0 ] && echo "test-smcheck16: ALL PASS (15 builds)" || echo "test-smcheck16: FAILURES"
exit $fail
