#!/bin/bash
# Mac test of the per-process %CPU maths and the process names behind the Activity Monitor feature (common/ProcSample.h, test-procsample.c).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreFoundation -o "$W/tps" test-procsample.c
"$W/tps"
# wiring: where the window reads the snapshot, and its names
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
A=../statusbar/ActivityMonitor.h; P=../statusbar/ProcList.h
check "the window reads the snapshot on its own serial queue, never on the main thread, one at a time; it takes it on the main thread" \
  "[ \$(grep -c 'DMProcListSnapshot()' $A) = 1 ] && awk '/^- \\(void\\)dm_sample \\{/,/^}/' $A | awk '/if \\(_sampling\\) return;/{g=1} g && /dispatch_async\\(DMAMSampleQueue\\(\\)/{q=1} q && /DMProcListSnapshot\\(\\)/{s=1} s && /dispatch_get_main_queue/{print \"ok\"; exit}' | grep -q ok && grep -q 'DISPATCH_QUEUE_SERIAL' $A"
check "a process's name comes from the never-refused UTF-8 reading, and its getter is never nil" \
  "grep -q 'MSBDProcNameUTF8(bytes' $P && grep -q 'return _name.length ? _name : \\[NSString stringWithFormat:@\"(%d)\", _pid\\];' $P && ! grep -q 'e.name = @(' $P"
[ $fails = 0 ] && echo "test-procsample: all wiring checks pass" || { echo "test-procsample: wiring checks FAILED"; exit 1; }
