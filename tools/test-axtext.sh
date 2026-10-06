#!/bin/bash
# Mac test of the words our UI gives assistive features (common/AXText.h, test-axtext.m). The menus' shortcut hints are read from the sources
# (every `.hint = @"..."`, DMFinderRow / DMShortcutRow / R(...) second argument), so a new hint must get its words in the test's table too.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tax" test-axtext.m
HINTS=()
while IFS= read -r h; do [ -n "$h" ] && HINTS+=("$h"); done < <(grep -o -h -E 'hint = @"[^"]*"|DMFinderRow\(@"[^"]*", @"[^"]*"|DMShortcutRow\(@"[^"]*", @"[^"]*"|R\(@"[^"]*", @"[^"]*"' ../statusbar/*.x ../statusbar/*.h | sed -E 's/.*@"([^"]*)"$/\1/' | sort -u)
[ ${#HINTS[@]} -ge 10 ] || { echo "FAIL: only ${#HINTS[@]} menu hints found in the sources"; exit 1; }
"$W/tax" "${HINTS[@]}"
