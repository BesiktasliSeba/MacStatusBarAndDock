#!/bin/bash
# Mac test of the sticky notes' store across releases (1.8.8.2): a note's optional "page" (F36) and "name" (F37) keys and a later release's keys are
# kept and written back; 1.8.8.1's notes need no migration (read and written back with the keys they had, version 1); the downgrade: 1.8.8.1's and
# 1.8.8.1.1's own StickyNotes.h (git history) read a 1.8.8.2 store with every note there, all on page 1, and back on 1.8.8.2 nothing is lost.
# MSB_N points it at a copy of common/StickyNotes.h (made-to-fail copies must each fail).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
N=${MSB_N:-../common/StickyNotes.h}
mkdir -p "$W/new/common" "$W/data"; cp "$N" "$W/new/common/StickyNotes.h"
check "the store stays version 1 (an older release reads it; version 2 would show it no note at all)" "grep -qxF '#define MSBD_NOTES_VERSION 1' '$N'"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -I"$W/new" -framework Foundation -o "$W/tss" test-stickystore.m
"$W/tss" new "$W/data" || fails=1
for rel in 56d9461b:1.8.8.1 e068b0c6:1.8.8.1.1; do
  c=${rel%%:*}; name=${rel#*:}
  mkdir -p "$W/$c/common"
  if git -C .. show "$c:common/StickyNotes.h" > "$W/$c/common/StickyNotes.h" 2>/dev/null; then
    clang -O2 -fobjc-arc -Wall -Wno-unused-function -DT_OLD -I"$W/$c" -framework Foundation -o "$W/tss-$c" test-stickystore.m
    echo "INFO  $name ($c): its StickyNotes.h reads this release's store"
    "$W/tss-$c" old "$W/data" || fails=1
    "$W/tss" back "$W/data" || fails=1
  else echo "FAIL  $name's StickyNotes.h ($c) is not in the git history here"; fails=1; fi
done
[ $fails = 0 ] && echo "test-stickystore: all passed" || echo "test-stickystore: FAILED"
exit $fails
