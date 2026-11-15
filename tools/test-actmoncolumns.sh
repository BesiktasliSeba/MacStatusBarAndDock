#!/bin/bash
# Mac test of the Activity Monitor window's columns (statusbar/ActMonColumns.h, test-actmoncolumns.m): every title fits its column with the sort
# arrow, in every tab, at the window's smallest and largest widths (29 Oct: "Memory ↓" and "Network ↓" were cut off). 1.8.7.5 (audit L77 of
# 1.8.7.2): the rows' sort, the real comparator cut out of ActivityMonitor.h (actmonsort-cut.py): every column of every tab, both ways.
# ACTMON_H=<file>: another ActivityMonitor.h (e.g. the code before a fix: it must fail). Without it, made-to-fail copies follow.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
AM0=${ACTMON_H:-../statusbar/ActivityMonitor.h}
run() {   # $1 ActivityMonitor.h, $2 quiet, $3 a perl expression for the cut sort (made-to-fail); the test's exit status (2: not built)
  local d=$W/b; rm -rf "$d"; mkdir -p "$d"
  python3 -I actmonsort-cut.py "$1" ../statusbar/ProcList.h "$d" || { echo "FAIL  the rows' sort not found in ActivityMonitor.h"; return 2; }
  [ -z "$3" ] || perl -0pi -e "$3" "$d/amsort-sort.h"
  if [ -n "$2" ]; then
    clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework AppKit -DAM_SORT -iquote "$d" -o "$d/tac" test-actmoncolumns.m >/dev/null 2>&1 || return 2
    "$d/tac" >/dev/null 2>&1
  else
    clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework AppKit -DAM_SORT -iquote "$d" -o "$d/tac" test-actmoncolumns.m || return 2
    "$d/tac"
  fi
}
rc=0
run "$AM0" || rc=1
if [ -z "$ACTMON_H" ]; then
  cp "$W/b/amsort-sort.h" "$W/sort-before.h"   # (the sort as cut, to see that each copy changed it)
  mtf() {   # $1 name, $2 perl expression on the cut sort
    local r=0
    run "$AM0" quiet "$2" || r=$?
    if cmp -s "$W/b/amsort-sort.h" "$W/sort-before.h"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if [ $r = 0 ]; then echo "FAIL  made-to-fail ($1): the checks still pass"; rc=1; elif [ $r = 2 ]; then echo "FAIL  made-to-fail ($1): did not build"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  mtf "no CPU Time case: the tab's metric, % CPU (the code before the fix)" 's/\n\s*else if \(_tab == DMAMTabCPU && _sortCol == 2\) r = .*?;\n/\n/s'
  mtf "a row without figures read as 0 CPU time" 's/a\.haveStats != b\.haveStats \? \(a\.haveStats \? NSOrderedDescending : NSOrderedAscending\)\s*: !a\.haveStats \? NSOrderedSame : //s'
  mtf "CPU Time compared the wrong way round" 's/\(a\.cpuNs < b\.cpuNs \? NSOrderedAscending : a\.cpuNs > b\.cpuNs/(a.cpuNs > b.cpuNs ? NSOrderedAscending : a.cpuNs < b.cpuNs/'
  mtf "the tie-break by name and pid gone" 's/\n\s*r = \[a\.name localizedCaseInsensitiveCompare:b\.name\];\n\s*return r != NSOrderedSame \? r : .*?;\n/\n        return NSOrderedSame;\n/s'
fi
exit $rc
