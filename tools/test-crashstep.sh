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
  # the Stage Manager engine (its functions, its hook groups, the window fit and the stage-area hook, 1.3.2): Windowing off, the Mac status bar stays
  real core-sm-zoom "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMToggleZoom$'
  real core-sm-fit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMAttrsFitScreen'
  real core-sm-hook16 "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMConstrainEdges16'
  real core-sm-group "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$SMLayout16\$'
  # force quit: the Apple menu's and the app icons' (MSBDForceQuitApp, 1.3.5): Windowing off, not the traffic lights or the whole part (R2-L1)
  real core-forcequit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMForceQuitBundle$'
  real core-forcequit-export "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDForceQuitApp$'
  real core-appswithwindows "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?MSBDAppsWithWindows$'
  # (its blocks -- the kill and the switcher clean-up after the window closed -- fell to their section before, 1.3.5 round 2 R3-L3; a DMSM function's
  #  block in StatusBar.x the same way)
  real core-forcequit-block "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMForceQuitBundle_block_invoke'
  real core-sm-block "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMWindowAction_block_invoke'
  # (the menu-closing wait of window changes and its poll's block, which closes SpringBoard's icon menu after 2 s: Windowing, not "part" -- L-3)
  real core-ctxwait "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMWaitForMenuToClose$'
  real core-ctxpoll "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMContextMenuPoll_block_invoke'
  # (sm-desktop: the Home Screen behind the windows, the desktop join of SpringBoard's own transitions and its rule's blocks, the strip gate)
  real core-sm-desk "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDeskHomeBehind$'
  real core-sm-joinasked "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMJoinStageAsked$'
  real core-sm-joinblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMDeskJoinPlan_block_invoke'
  real core-sm-apiblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMRequestPlan_block_invoke'
  real core-sm-strip "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMStripRevealBegin$'
  # Stage Manager held off / given back (1.3.4): Control Center's button and its installer, SpringBoard's switch handler that waits
  real core-sm-button "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$StageManagerButton\$'
  real core-sm-buttonhook "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMInitStageManagerButtonHook$'
  real core-sm-offwait "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDefaultChangeHook$'
  # (sm-nolimit: Apple's window limit answered by us, the role table, the Fit plan for more than four windows)
  real core-sm-limit "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMMaxAppsOnStage$'
  real core-sm-roles "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRolesDerive$'
  real core-sm-fitplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMFitPlanDecide$'
  # (1.3.6: one window, one role -- the context put right before SpringBoard reads it, and its rule)
  real core-sm-rolerepair "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRepairRoles$'
  real core-sm-rolerepairplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRoleRepairPlan$'
  # (sm-free: the windows stay at Home -- the rewrite, its rule, the Home gesture's blur answer)
  real core-sm-home "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomeKeepsDesktop$'
  real core-sm-homeplan "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomePlan$'
  real core-sm-homeblur "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHGBlurProgress$'
  # (1.3.8 logic test fixes: the App Switcher's bookkeeping after finalize, our own real Home request, the desktop choice of the joins and the restore)
  real core-sm-homenote "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHomeNoteResult$'
  real core-sm-realhome "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMRequestRealHome$'
  real core-sm-desktopfor "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMDesktopFor$'
  # (1.3.9: the windows keep still during a Home gesture with Reduce Motion off -- the decision the gesture's frame and scale answers read)
  real core-sm-homestill "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMHGStill$'
  # (sm-multiwin, M-2: each window known by its own scene -- the window's entity, its lookup by key, a card's key on every card layout, the window
  #  keys' own header, force quit's later closes of the app's other windows)
  real core-sm-winentity "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMEntityForStageItem$'
  real core-sm-winitem "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMItemFor$'
  real core-sm-cardkey "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMCardKey$'
  real core-sm-keyset "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMSMKeySetHas$'
  real core-sm-fqblock "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^___DMSMForceQuitWindows_block_invoke'
  # every Stage Manager hook group of this build (%group SM...): Windowing off -- 16.0's SMLayout160 / SMGrid160 fell to the image's target in the
  # first 1.3.4 build (the stock status bar instead, logic test); a new SM group must not
  smgroups=$(nm -s __TEXT __text "$DSYM" | grep -oE 'logos_method\$SM[A-Za-z0-9]*\$' | sed 's/^logos_method\$//; s/\$$//' | sort -u)
  n=$(echo "$smgroups" | grep -c . || true)
  [ "$n" -ge 7 ] && echo "PASS  $n Stage Manager hook groups in the build: $(echo $smgroups)" || { echo "FAIL  only $n Stage Manager hook groups found: $(echo $smgroups)"; fails=1; }
  for g in $smgroups; do
    real "core-sm-group-$g" "pref MacStatusBarCore $D windowingEnabled 0 *" --symbol "$DSYM" MacStatusBarCore "logos_method\\\$${g}\\\$"
  done
  real core-context "part MacStatusBarCore - - 0 the status bar|the Mac status bar" --symbol "$DSYM" MacStatusBarCore 'logos_method\$MacContextMenus\$'
  real core-today "pref MacStatusBarCore $D clockOpensToday 0 *" --map "$MAP" MacStatusBarCore arm64 clockOpensToday
  real dock-downloads "pref DockMagnification com.besiktasliseba.dockmagnification showDownloads 0 *" --map "$MAP" DockMagnification arm64e showDownloads
  real dock-part "part DockMagnification - - 0 the Dock|MacDock" --map "$MAP" DockMagnification arm64 part
  # Finder (Finder.h / NativeWindow.h / its glue in StatusBar.x): Finder's own switch, not the whole status bar; FinderIcon.m: the Dock's Finder
  real core-finder-window "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^-\[DMFinderWindow dm_run'
  real core-finder-native "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMNativeTouchBegan'
  real core-finder-glue "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMOpenFinderFileMenu'
  real core-finder-icontap "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore 'logos_method\$DMNativeHooks\$SBIconView'
  real core-finder-drag "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMFinderDragMove'
  real core-finder-keys "pref MacStatusBarCore $D finderEnabled 0 *" --symbol "$DSYM" MacStatusBarCore '^_?DMNativeHandlePress'
  real dock-finder "pref DockMagnification com.besiktasliseba.dockmagnification showFinder 0 *" --map "$MAP" DockMagnification arm64e showFinder
else
  echo "== (no built map: build the package to test it)"
fi
[ $fails = 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
