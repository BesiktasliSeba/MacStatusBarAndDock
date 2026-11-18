#!/bin/bash
# test-hookframes.sh (1.8.7.7, GitHub #14): every part that runs in SpringBoard is built with -fno-optimize-sibling-calls, so each hook of ours keeps
# its own stack frame while the original runs. With tail calls (the release builds' -Os) 201 of MacStatusBarCore's 305 hooks and 38 of the Dock's
# 66 left with no frame of theirs, and a crash under one of them showed only Apple code: the crash guard could not pin it on us or on the feature
# (CrashBlame.h, CrashFeature.h). The parts are read from the loader's own table (loader/Loader.c: kSpringBoard or kUIKit), their flags from the
# Makefiles (<part>_CFLAGS). The loaders (MacStatusBar, MacDock) need no such flag: their only hand-over, the death record's (common/CrashCause.h),
# is a musttail. Then made-to-fail copies of a Makefile.
cd "$(dirname "$0")/.." || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
check() {   # $1 the tree's root: prints one line per part, returns the number of parts without the flag
  local R=$1 bad=0 n=0 part mk line
  for part in $(sed -n 's/^ *{ "\([A-Za-z0-9]*\)", \([^}]*\) },.*/\1 \2/p' "$R/loader/Loader.c" | awk '/kSpringBoard|kUIKit/ {print $1}' | sort -u); do
    n=$((n + 1))
    mk=$(/usr/bin/grep -l "^${part}_CFLAGS *=" "$R"/*/Makefile 2>/dev/null | head -1)
    line=$(/usr/bin/grep "^${part}_CFLAGS *=" "$mk" 2>/dev/null)
    if [ -n "$mk" ] && echo "$line" | /usr/bin/grep -q -- '-fno-optimize-sibling-calls'; then echo "PASS  $part (${mk#$R/}): its hooks keep their frames"
    else echo "FAIL  $part (${mk#$R/}): built without -fno-optimize-sibling-calls ($line)"; bad=$((bad + 1)); fi
  done
  [ $n -ge 19 ] || { echo "FAIL  only $n SpringBoard parts read from loader/Loader.c"; bad=$((bad + 1)); }
  return $bad
}
check . ; rc=$?
echo "== made-to-fail copies"
for part in MacStatusBarCore DockMagnification MacLockStatusBar TabMuteTweak; do
  rm -rf "$W/t"; mkdir -p "$W/t/loader"; cp loader/Loader.c "$W/t/loader/"; for d in */Makefile; do mkdir -p "$W/t/$(dirname $d)"; cp "$d" "$W/t/$d"; done
  mk=$(/usr/bin/grep -l "^${part}_CFLAGS *=" "$W"/t/*/Makefile | head -1)
  sed -i '' "s/^\(${part}_CFLAGS *=.*\) -fno-optimize-sibling-calls/\1/" "$mk"
  if check "$W/t" >/dev/null; then echo "FAIL  made to fail ($part without the flag): the check still passes"; rc=1; else echo "PASS  made to fail ($part without the flag): caught"; fi
done
[ $rc = 0 ] && echo "test-hookframes: all pass" || echo "test-hookframes: FAILED"
exit $rc
