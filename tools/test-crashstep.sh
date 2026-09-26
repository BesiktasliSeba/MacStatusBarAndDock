#!/bin/bash
# Mac tests of the crash guard's step 1b (only what crashed goes off): the lookup (common/CrashFeature.h, test-crashfeature.m), the guard's order
# (common/CrashGuard.h + CrashStep.h, test-crashstep.c) and, if a package was built, the real CrashMap.txt against the real symbols.
# Writes to the Mac's preference domains com.besiktasliseba.macstatusbaranddock and com.besiktasliseba.test-crashstep (removed at the end).
set -e
cd "$(dirname "$0")"
FIXDIR="$PWD/crash-fixtures"
W=$(mktemp -d); export FIX="$FIXDIR" REPORTS="$W/reports"
cleanup() {   # (the domains go, and their empty files)
  for d in com.besiktasliseba.macstatusbaranddock com.besiktasliseba.test-crashstep; do
    defaults delete $d >/dev/null 2>&1 || true
    defaults read $d >/dev/null 2>&1 || rm -f ~/Library/Preferences/$d.plist
  done
  rm -rf "$W"
}
if defaults read com.besiktasliseba.macstatusbaranddock >/dev/null 2>&1; then echo "the Mac has settings in com.besiktasliseba.macstatusbaranddock: not touching them"; exit 1; fi
trap cleanup EXIT
fails=0
echo "== lookup (synthetic map)"
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tcf" test-crashfeature.m
"$W/tcf" "$FIXDIR" || fails=1
echo "== guard order"
clang -fobjc-arc -dynamiclib -framework Foundation -framework CoreFoundation -DMSBD_CRASHMAP="\"$FIXDIR/test-crashmap.txt\"" -o "$W/MacCrashBlame.dylib" ../loader/CrashBlameHelper.m ../loader/CrashFeatureHelper.m
clang -Wall -Wno-unused-function -framework CoreFoundation -DMSBD_GUARD_REPORTS="\"$REPORTS\"" -DMSBD_GUARD_VERDICTS="\"$W/verdicts.txt\"" \
  -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -DMSBD_STEP_FILE="\"$W/step.txt\"" -DMSBD_CRASHMAP="\"$FIXDIR/test-crashmap.txt\"" \
  -DMSBD_GUARD_RECORD="\"$W/record.txt\"" -DMSBD_GUARD_RECENT="\"$W/recent.txt\"" \
  -o "$W/tcs" test-crashstep.c
run() {   # run <scenario> <fixture for 10:00> [<fixture for 10:01>]
  rm -rf "$REPORTS" "$W/verdicts.txt" "$W/step.txt" "$W/record.txt" "$W/recent.txt"; mkdir -p "$REPORTS"
  [ "$1" = recent ] && echo "$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-09-26 09:59:30' +%s) com.besiktasliseba.test-crashstep recentSwitch Recent Switch" > "$W/recent.txt"
  defaults delete com.besiktasliseba.macstatusbaranddock >/dev/null 2>&1 || true; defaults delete com.besiktasliseba.test-crashstep >/dev/null 2>&1 || true
  cp "$FIXDIR/$2" "$REPORTS/SpringBoard-2026-09-26-100000.ips"
  [ -n "$3" ] && cp "$FIXDIR/$3" "$REPORTS/SpringBoard-2026-09-26-100100.ips"
  echo "-- $1"; "$W/tcs" "$1" || fails=1
}
run banners step1b-core-banners.ips step1b-core-banners-exception.ips
run parts step1b-dock.ips step1b-small-part.ips
echo "-- the loaders' skip list"
defaults write com.besiktasliseba.macstatusbaranddock crashGuardAction -int 4
"$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 10 ] && echo "PASS  MixAudio not loaded while the note is there" || { echo "FAIL  MixAudio skip ($r)"; fails=1; }
"$W/tcs" skip MacStatusBarCore && r=0 || r=$?; [ $r = 20 ] && echo "PASS  MacStatusBarCore still loaded" || { echo "FAIL  MacStatusBarCore ($r)"; fails=1; }
defaults delete com.besiktasliseba.macstatusbaranddock crashGuardAction
"$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 20 ] && echo "PASS  note cleared: MixAudio loads again" || { echo "FAIL  MixAudio after clearing ($r)"; fails=1; }
[ ! -e "$W/step.txt" ] && echo "PASS  note cleared: the skip list is removed" || { echo "FAIL  skip list still there"; fails=1; }
rm -f "$W/step.txt"; "$W/tcs" skip MixAudio && r=0 || r=$?; [ $r = 20 ] && echo "PASS  no skip list: everything loads" || { echo "FAIL  no list ($r)"; fails=1; }
run apple apple-only-our-class-in-reason.ips apple-only-our-class-in-reason.ips
run mixed step1b-loader.ips step1b-dock-downloads.ips
run recent step1b-core-banners.ips step1b-core-banners.ips
run one step1b-core-banners.ips
echo "== the words (footer, notice, Report a Problem)"
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -DMSBD_GUARD_RECORD="\"$W/words-record.txt\"" -o "$W/tse" test-stepexplain.m
"$W/tse" || fails=1
# The real map of the last build (if there is one): crashes placed in real functions must find the right switch.
MAP=../.theos/_/var/jb/usr/lib/MacStatusBarAndDock/CrashMap.txt
DSYM=   # (the symbols of the build the map was made from: release or test build)
for o in ../.theos/obj ../.theos/obj/debug; do
  c=$o/arm64e/MacStatusBarCore.dylib.dSYM/Contents/Resources/DWARF/MacStatusBarCore.dylib
  [ -f "$c" ] && [ -f "$MAP" ] && grep -q "$(dwarfdump --uuid "$c" | awk '{print tolower($2)}')" "$MAP" && DSYM=$c
done
if [ -f "$MAP" ] && [ -n "$DSYM" ]; then
  echo "== the built map ($(wc -c < "$MAP" | tr -d ' ') bytes)"
  real() {   # real <name> <expected answer> <fixture args...>
    local n=$1 want=$2; shift 2
    python3 make-crash-fixture.py "$W/$n.ips" "$@" >/dev/null && "$W/tcf" "$MAP" "$W/$n.ips" "$want" || fails=1
  }
  D=com.besiktasliseba.macstatusbar
  real core-banner "pref MacStatusBarCore $D macBanners 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$MacBanners\$'
  real core-menu "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore 'DMShowMenu|DMMenuWindow|DMMenu'
  # (auto-hide is off on this Mac, as for a new user: a crash in its code can't be the switch, so Stock status bar mode instead)
  real core-autohide "pref MacStatusBarCore $D stockStatusBar 1 *" --symbol "$DSYM" MacStatusBarCore '^_DMAutoHide'
  real core-aerial "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$AerialStyle\$'
  real core-context "part MacStatusBarCore - - 0 the status bar|the Mac status bar" --symbol "$DSYM" MacStatusBarCore 'logos_method\$MacContextMenus\$'
  real core-today "pref MacStatusBarCore $D clockOpensToday 0 *" --map "$MAP" MacStatusBarCore arm64 clockOpensToday
  real dock-downloads "pref DockMagnification com.besiktasliseba.dockmagnification showDownloads 0 *" --map "$MAP" DockMagnification arm64e showDownloads
  real dock-part "part DockMagnification - - 0 the Dock|MacDock" --map "$MAP" DockMagnification arm64 part
else
  echo "== (no built map: build the package to test it)"
fi
[ $fails = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
