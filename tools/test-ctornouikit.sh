#!/bin/bash
# test-ctornouikit.sh: nothing of ours asks UIKit for its screens or windows from a constructor that runs in SpringBoard (GitHub #16, 1.8.7.6).
# From 1.8.6 to 1.8.7.5 SpringBoard hung at every start on some iPads (iPad 6 on 15.7, after resprings) with Finder on and Show Trash in Dock off:
# StatusBar.x's %ctor -> DMFinderApplyPref -> DMDockTrashApplyPref -> DMDockTrashExternalDisplay -> DMDispScreens -> +[UIScreen screens]. A
# constructor runs inside dyld's loading of its part, dyld's loader lock held; UIKit's first screen set-up waited there on FrontBoard's listener
# thread, which waited on that lock, until the watchdog killed SpringBoard (120 s), and again at the next start.
#  (a) behaviour (test-ctornouikit.m, release and DEBUG): the real DMDockTrashPrefOn, DMDockTrashExternalDisplay, DMDockTrashApplyPref
#      (statusbar/DockTrash.h) and DMDispScreens (statusbar/DisplayPrefs.h) cut out and run on a UIScreen of the test's own, in a constructor as
#      StatusBar.x runs it, then one turn of the main queue: Finder on / off x Show Trash in Dock off / on / not set x no TV / a TV / a TV with its
#      own off. Pass: UIScreen never asked while the constructor runs, the bin decided by the Dock's switch then, right after one main-queue turn.
#  (b) static (ctornouikit-walk.py): every constructor of every part that runs in SpringBoard, walked through what it calls at once (blocks
#      handed to the main queue, a notification or a timer left out): no UIScreen, DMDispScreens, window made or UIWindow asked.
#  (c) behaviour (test-ctornouikit-back.m, release and DEBUG): the Mac Switcher on at the start with desktops kept from its last off
#      (statusbar/MacSwitcher.h DMMSWBringBack and what it runs, cut out, with the real MSWKept.h): no screen asked from the constructor, and after
#      one main-queue turn what it brought back from the constructor in 1.8.7.5 -- the engine as read there, nothing told, no stage or window read,
#      every kept window back, no apply -- with SpringBoard's stages half restored by then (review of the #16 fix, F1); the switch-on later as before.
#  Then site checks, and made-to-fail copies, each must fail.
# CT_ROOT: another tree (e.g. the code before the change, git archive); then no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${CT_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line

build() {   # $1 tree, $2 dir, $3 quiet: the behaviour test built on that tree's code, release (t) and DEBUG (td)
  local R=$1 d=$2 fl
  mkdir -p "$d"
  awk '/^static BOOL gDockTrashOn = NO;/ {f=1} f {print} f && /^static BOOL DMDockTrashPrefOn\(void\) \{/ {g=1} g && /^[}]/ {exit}' "$R/statusbar/DockTrash.h" > "$d/ct-pref.inc"
  fn "$R/statusbar/DisplayPrefs.h" 'static NSArray<UIScreen *> *DMDispScreens(void) {' > "$d/ct-screens.inc"
  awk '/^\/\/ A connected display \(a TV\) whose Dock shows the Trash/ {f=1} f {print} f && /^static void DMDockTrashApplyPref\(void\) \{/ {g=1} g && /^[}]/ {exit}' "$R/statusbar/DockTrash.h" > "$d/ct-apply.inc"
  grep -q '^static BOOL DMDockTrashPrefOn(void) {' "$d/ct-pref.inc" && grep -q '\[UIScreen screens\]' "$d/ct-screens.inc" \
    && grep -q '^static BOOL DMDockTrashExternalDisplay(void) {' "$d/ct-apply.inc" && grep -q '^static void DMDockTrashApplyPref(void) {' "$d/ct-apply.inc" \
    || { echo "FAIL  the code was not found in $R"; return 99; }
  for fl in t td; do
    clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $([ $fl = td ] && echo -DDEBUG=1) -framework Foundation \
          -o "$d/$fl" test-ctornouikit.m 2> "$d/cc-$fl.txt" || { [ -n "$3" ] || cat "$d/cc-$fl.txt"; echo "FAIL  the real code did not build ($fl)"; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$3" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; return 1; }
  done
  return 0
}

build_back() {   # $1 tree, $2 dir, $3 quiet: (c) built on that tree's code, release (b) and DEBUG (bd)
  local R=$1 d=$2 fl
  mkdir -p "$d"
  awk '/^static void DMMSWBringBack/ {f=1} /^\/\/ A window without a picture, where it is/ {exit} f {print}' "$R/statusbar/MacSwitcher.h" > "$d/ct-back.inc"
  cp "$R/statusbar/MSWKept.h" "$R/statusbar/SMWindowKey.h" "$d/" 2>/dev/null
  grep -q '^static void DMMSWBringBack(void) {' "$d/ct-back.inc" && grep -q 'MSWKeptBringBack(st, sm, told,' "$d/ct-back.inc" && [ -s "$d/MSWKept.h" ] \
    || { echo "FAIL  the Mac Switcher's bring-back was not found in $R"; return 99; }
  for fl in b bd; do
    clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" $([ $fl = bd ] && echo -DDEBUG=1) -framework Foundation \
          -o "$d/$fl" test-ctornouikit-back.m 2> "$d/cc-$fl.txt" || { [ -n "$3" ] || cat "$d/cc-$fl.txt"; echo "FAIL  the bring-back did not build ($fl)"; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$3" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; return 1; }
  done
  return 0
}

sites() {   # $1 tree, $2 quiet: the number of site checks that fail
  local R=$1 q=$2 n=0 T=$1/statusbar/DockTrash.h S=$1/statusbar/StatusBar.x
  # the observers that apply it again later stay as they were: a TV that connects or goes, a display's own switch, the Dock's settings
  if fn "$T" 'static void DMDockTrashInit(void) {' > "$W/init" \
     && grep -qF 'notify_register_dispatch("com.besiktasliseba.dockmagnification/prefsChanged", &t3, dispatch_get_main_queue(), ^(int t) { DMDockTrashApplyPref(); });' "$W/init" \
     && grep -qF 'for (NSString *n in @[UIScreenDidConnectNotification, UIScreenDidDisconnectNotification])' "$W/init" \
     && grep -qF '[[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { DMDockTrashApplyPref(); }];' "$W/init" \
     && grep -qF 'notify_register_dispatch(MSBD_DISP_NOTIFY, &t4, dispatch_get_main_queue(), ^(int t) { DMDispReload(); DMDockTrashApplyPref(); });' "$W/init" \
     && [ "$(tail -2 "$W/init" | head -1)" = '    DMDockTrashApplyPref();' ]; then
    [ -n "$q" ] || echo "PASS  DockTrash.h: the connect, display and prefs observers apply the bin again as before (DMDockTrashInit)"
  else [ -n "$q" ] || echo "FAIL  DockTrash.h: DMDockTrashInit's observers changed"; n=$((n + 1)); fi
  # the order the test runs: Finder's switch applied, then the bin (DMFinderApplyPref), from the constructor, its Dock init first
  if fn "$S" 'static void DMFinderApplyPref(void) {' > "$W/fap" && grep -A1 -xF '    gFinderOn = on;' "$W/fap" | grep -qxF '    DMDockTrashApplyPref();   // (the Dock'"'"'s Trash follows Finder: DockTrash.h)' \
     && awk '/DMFinderDockInit\(\);/ {a=NR} /    gFinderOn = on;/ {b=NR} END {exit !(a && b > a)}' "$W/fap" \
     && fn "$(dirname "$T")/Finder.h" 'static void DMFinderDockInit(void) {' | grep -qF '    DMDockTrashInit();'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: Finder's start as the test runs it (the Dock's Trash set up with Finder not on yet, then Finder's switch, then the bin)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: Finder's start is not the order the test runs"; n=$((n + 1)); fi
  # the constructor calls Finder's start and the settings' first read itself, with the flag set (the walk checks it is set first, cleared at
  # every way out)
  if awk '/^%ctor \{/ {c=1} c && /^    DMFinderApplyPref\(\);/ {f=1} c && /DMLoadPrefs\(\);/ {l=1} c && /^}/ {exit} END {exit !(f && l)}' "$S"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the constructor runs Finder's start and the settings' first read itself (both walked)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the constructor no longer calls DMFinderApplyPref / DMLoadPrefs as the walk expects"; n=$((n + 1)); fi
  # (c)'s way in: the Mac Switcher's switch on (DMLoadPrefs at the start) loads the desktops, then brings the kept ones back
  if fn "$(dirname "$T")/MacSwitcher.h" 'static void DMMSWApplyPref(BOOL want) {' | grep -qF '    if (on) { DMMSWHookKeys(); DMMSWHookGestures(); DMMSWHookStockPaths(); DMMSWWatchMemory(); DMMSWLoad(); DMMSWBringBack(); DMMSWWatchDisplays(); }'; then
    [ -n "$q" ] || echo "PASS  MacSwitcher.h: the switch's on loads the desktops, then DMMSWBringBack (the way (c) runs it)"
  else [ -n "$q" ] || echo "FAIL  MacSwitcher.h: DMMSWApplyPref no longer reaches DMMSWBringBack as (c) runs it"; n=$((n + 1)); fi
  return $n
}

walk() {   # $1 tree, $2 quiet
  local out r
  out=$(python3 -I ctornouikit-walk.py "$1"); r=$?
  if [ -n "$2" ]; then :; else echo "$out" | grep -v ' reached at once$'; echo "$out" | grep -c ' reached at once$' | sed 's/^/   (constructors walked: /; s/$/)/'; fi
  return $r
}

run() {   # $1 tree, $2 work dir, $3 quiet: the number of checks that fail
  local q=$3 n=0 s fl out r
  build "$1" "$2" "$q"; r=$?; [ $r = 99 ] && return 99; n=$r
  for fl in t td; do
    for s in $("$2/$fl" list); do
      out=$("$2/$fl" "$s" 2>/dev/null); r=$?
      [ -n "$q" ] || echo "-- $([ $fl = t ] && echo release || echo DEBUG): $s"; [ -n "$q" ] || echo "$out"
      n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
    done
  done
  build_back "$1" "$2" "$q"; r=$?; [ $r = 99 ] && return 99; n=$((n + r))
  for fl in b bd; do
    for s in $("$2/$fl" list); do
      out=$("$2/$fl" "$s" 2>/dev/null); r=$?
      [ -n "$q" ] || echo "-- (c) $([ $fl = b ] && echo release || echo DEBUG): $s"; [ -n "$q" ] || echo "$out"
      n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
    done
  done
  [ -n "$q" ] || echo "-- (b) the constructors' walk"
  walk "$1" "$q"; r=$?; n=$((n + r))
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$q"; n=$((n + $?)); [ $n -ge 99 ] && n=98
  return $n
}

run "$R0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-ctornouikit: all pass" || echo "test-ctornouikit: FAILED ($rc check(s))"
if [ -z "$CT_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mkdir -p "$W/tree"; for d in statusbar dock common loader macsettings appbridge mixaudio forcequitmenu graveescape tabmute volumeglobe brightnesskey; do cp -R "$R0/$d" "$W/tree/"; done
  cp "$R0/Makefile" "$W/tree/"
  mtf() {   # $1 what, $2 file in the tree, $3 perl expression (the whole file at once)
    local d="$W/m$((++k))" c
    cp -R "$W/tree" "$d"; c="$d/$2"
    perl -0777 -pi -e "$3" "$c"
    cmp -s "$c" "$R0/$2" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; rm -rf "$d"; return; }
    run "$d" "$d/w" q; local n=$?
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
    rm -rf "$d"
  }
  k=0
  mtf "the displays asked at the start again (issue #16 as shipped)" statusbar/DockTrash.h 's/\(!gDMInCtor && DMDockTrashExternalDisplay\(\)\)/DMDockTrashExternalDisplay()/'
  mtf "no apply after the start (a TV's bin left off)" statusbar/DockTrash.h 's/if \(!queued\) \{ queued = YES; dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMDockTrashApplyPref\(\); \}\); \}/(void)queued;/'
  mtf "the apply after the start run inside the constructor" statusbar/DockTrash.h 's/dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMDockTrashApplyPref\(\); \}\);/gDMInCtor = NO; DMDockTrashApplyPref(); gDMInCtor = YES;/'
  mtf "the backstop gone (DMDispScreens asks UIKit during the constructor)" statusbar/DisplayPrefs.h 's/    if \(gDMInCtor\) \{\n        DMLog\(\@"\[dispprefs\] the screens were asked[^\n]*\n        return \@\[\];\n    \}\n//'
  mtf "(debug) the backstop says nothing" statusbar/DisplayPrefs.h 's/        DMLog\(\@"\[dispprefs\] the screens were asked[^\n]*\n//'
  mtf "the flag never set by the constructor" statusbar/StatusBar.x 's/= gDMInCtor = YES;   \/\/ \(SpringBoard.s start/= NO;   \/\/ (SpringBoard'"'"'s start/'
  mtf "the flag never cleared" statusbar/StatusBar.x 's/static void DMCtorOver\(BOOL \*inCtor\) \{ gDMInCtor = NO; \}/static void DMCtorOver(BOOL *inCtor) { }/'
  mtf "the Mac Switcher's desktops brought back from the constructor" statusbar/MacSwitcher.h 's/(static void DMMSWBringBack\(void\) \{\n)    if \(gDMInCtor\) \{\n.*?\n        return;\n    \}\n/$1/s'
  mtf "the engine read from the constructor at every start, a kept copy or not" statusbar/MacSwitcher.h 's/BOOL sm = \[st isKindOfClass:\[NSDictionary class\]\] && gMSWDesks.count <= 1 && DMSMEngine\(\);/BOOL sm = ((void)st, DMSMEngine());/'
  mtf "the start's bring-back reads SpringBoard's stages at the first turn and can tell (review F1)" statusbar/MacSwitcher.h 's/DMMSWBringBackAt\(YES, sm\)/DMMSWBringBackAt(NO, sm)/'
  mtf "the start's engine read at the first turn, not as the constructor read it" statusbar/MacSwitcher.h 's/BOOL sm = start \? startSM : DMSMEngine\(\), told = NO;/BOOL sm = DMSMEngine(), told = NO;/'
  mtf "the side Dock refreshed from the Dock's constructor" dock/Dock.x 's/    if \(gDMInCtor\) return;   \/\/ \(the constructor: no Dock window exists yet[^\n]*\n//'
  mtf "a start guard gone (our Control Center looks for Apple's at the start)" statusbar/CCPanel.h 's/UIViewController \*ov = gCCPInConstructor \? nil : DMCCPFindOverlay\(\);/UIViewController *ov = DMCCPFindOverlay();/'
  mtf "a new screen ask from the constructor (the display settings' start)" statusbar/DisplayPrefs.h 's/(static void DMDispInit\(void\) \{\n)/$1    (void)[UIScreen mainScreen].bounds;\n/'
  mtf "a window made from another part's constructor (the Dock)" dock/Dock.x 's/(    DMLastPageInit\(\);)/    (void)[[UIWindow alloc] initWithFrame:CGRectZero];\n$1/'
fi
exit $rc
