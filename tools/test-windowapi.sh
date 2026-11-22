#!/bin/bash
# Mac test of the window API V1 (1.8.3 item 1: KeyPilot's bridge, wanghuangjie's names and codes; statusbar/WindowAPIRule.h, test-windowapi.c), then the
# sites in the code as built: the three functions exported from MacStatusBarCore with default visibility (and the build's check that they are), main
# thread only, each check his bridge had against the code today, the layouts the Window menu's own (our window in front too), Home the user's Home
# with Home Minimizes Windows on every engine, the environment read only, and the debug caller that calls them as KeyPilot does. Last (B79): the
# build's check run in a loop as Theos runs it, never failing at random with the names there.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/twa" test-windowapi.c
"$W/twa"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
A=../statusbar/WindowAPI.h; S=../statusbar/StatusBar.x; M=../Makefile
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
check "the three functions, his names and signatures, default visibility (KeyPilot's dlsym finds them)" \
  "grep -q '^__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotLayoutV1(const char \*layout) {' $A \
   && grep -q '^__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotHomeV1(void) {' $A \
   && grep -q '^__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotHomeEnvironmentV1(void) {' $A"
exportline() {   # $1 a Makefile: the build's check of the three names in both slices, grep reading nm's whole output (B79), and no reader
                 # in a recipe's pipe that leaves before its writer ends (Theos' pipefail: the writer dies of SIGPIPE and the recipe fails)
  grep -q 'for s in MSBDKeyPilotLayoutV1 MSBDKeyPilotHomeV1 MSBDKeyPilotHomeEnvironmentV1; do for a in arm64 arm64e; do' "$1" \
  && grep -q 'nm -gU -arch \$\$a "\$\$P/MacStatusBarCore\.dylib" | grep " T _\$\$s\$\$" > /dev/null ||' "$1" \
  && ! grep -v '^[[:space:]]*#' "$1" | grep -E '\|[[:space:]]*(grep[[:space:]]+-[A-Za-z]*[qm]|head([[:space:]]|$))' > /dev/null
}
check "  ... in MacStatusBarCore (StatusBar.x's own translation unit, at its end), and the build fails when one is not exported in either slice" \
  "tail -12 $S | grep -q '#include \"WindowAPI.h\"' && exportline $M"
sed 's/| grep " T _\$\$s\$\$" > \/dev\/null ||/| grep -q " T _$$s$$" ||/' $M > "$W/Makefile.q"
sed 's/| sed -n /| head -1 | sed -n /' $M > "$W/Makefile.head"
check "  ... made to fail (B79): that check refuses the 1.8.3 form (nm | grep -q) and a reader that leaves early in another of the recipe's pipes" \
  "! cmp -s $M \$W/Makefile.q && ! exportline \$W/Makefile.q && ! cmp -s $M \$W/Makefile.head && ! exportline \$W/Makefile.head"
check "the layout: the rule's codes in its order, nothing of SpringBoard's read off the main thread, the Window menu's own way when dispatched" \
  "fn '__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotLayoutV1(const char *layout) {' $A && grep -q 'MSBDWinAPIFacts f = { .mainThread = \[NSThread isMainThread\] };' \$W/fn \
   && grep -q 'if (f.mainThread && MSBDWinAPILayoutIndex(layout) >= 0) {' \$W/fn && grep -q 'int status = MSBDWinAPILayoutStatus(layout, f);' \$W/fn \
   && grep -q 'if (!f.mainThread) return status;' \$W/fn && grep -q 'DMLayoutFrontWindow(@(layout), @\"the window API\");' \$W/fn"
check "  ... his checks today: an engine (any of ours, Stage Manager too), the active app, a full-screen-only app (the Window menu's greyed rows)" \
  "grep -q 'f.engine = DMActiveEngine() != DMEngineNone || DMSMEngine();' $A && grep -q 'f.fullScreenOnly = f.activeApp && DMAppNeedsFullScreen(bundle);' $A \
   && fn 'static void DMOpenWindowMenu(UIButton *btn) {' $S && grep -qE 'BOOL enabled = \(DMActiveEngine\(\) != DMEngineNone \|\| DMSMEngine\(\)\) && DMActiveApp\(\) != nil( && !otherBar)?;' \$W/fn"
check "  ... locked or busy: his Lock Screen and transition, and what keeps the Window menu out of reach (the switchers, Control Center, our menus, Guided Access)" \
  "fn 'static NSString *DMWindowAPIBusyWhyPassing(BOOL *passing) {' $A && grep -q 'if (DMSMHomeUILocked()) return @\"locked\";' \$W/fn && grep -q 'if (DMCoverSheetShown())' \$W/fn \
   && grep -q 'if (!DMWorkspaceIdle()) return @\"a workspace transition\";' \$W/fn && grep -q 'if (DMSwitcherVisible())' \$W/fn && grep -q 'if (gMSWOpen)' \$W/fn \
   && grep -q 'if (DMControlCenterActive())' \$W/fn && grep -q 'if (gOverlay)' \$W/fn && grep -q 'if (MSBDGuidedAccessActive())' \$W/fn"
check "  ... and whatever of ours is about to place the windows itself (review 1.8.3 F6): a Mac Switcher slide, the restore after a respring, a turn being applied, Stage Manager's gesture and settling" \
  "fn 'static NSString *DMWindowAPIBusyWhyPassing(BOOL *passing) {' $A && grep -q 'if (gMSWSwitching) return' \$W/fn && grep -q 'if (gRestoringWindowsFlag()) return' \$W/fn \
   && grep -q 'if (DMSMGestureLive()) return' \$W/fn && grep -q 'if (DMSMTurnSettling()) return' \$W/fn && grep -q '} else if (DMLayoutNotesHeld()) return' \$W/fn \
   && grep -q 'static NSString \*DMWindowAPIBusyWhy(void) { return DMWindowAPIBusyWhyPassing(NULL); }' $A"
check "  ... the states that pass by themselves (a transition, a desktop sliding in, the restore, a turn) told apart from the rest, which come first (a title bar's double tap waits for the first, never for the rest)" \
  "fn 'static NSString *DMWindowAPIBusyWhyPassing(BOOL *passing) {' $A && awk '/if \\(passing\\) \\*passing = YES;/ {y=NR} /if \\(gOverlay\\) return/ {o=NR} /if \\(!DMWorkspaceIdle\\(\\)\\) return/ {w=NR} END {exit !(o && y && w && o < y && y < w)}' \$W/fn"
check "a Home that waited reads the lock and Guided Access again at every step and does nothing once either holds (review 1.8.3 P2-6)" \
  "fn 'static void DMWindowAPIHomeWhenFree(NSString *why, int tries) {' $A && grep -q 'BOOL locked = DMSMHomeUILocked() || MSBDGuidedAccessActive();' \$W/fn && grep -q 'int step = MSBDWinAPIHomeStep(locked, busy, atHome, tries);' \$W/fn \
   && awk '/if \\(step == kMSBDWinHomeLockedNow\\)/{l=NR} /DMWindowAPIMinimizeAll\\(why\\);/{m=NR} END{exit !(l && m && l < m)}' \$W/fn"
check "the front window: our own (Finder) as the Window menu lays it out, else the Window menu's DMWindowLayout -- one way for its rows, the API and the keys" \
  "fn 'static void DMLayoutFrontWindow(NSString *name, NSString *why) {' $A && grep -q 'if (nw) { DMNativeLayout(nw, name); return; }' \$W/fn && grep -q 'DMWindowLayout(name);' \$W/fn \
   && grep -q '\[items addObject:R(e\[0\], nil, ^{ DMNativeLayout(w, name); })\];' $S"
check "Home: dispatched only on the main thread and unlocked; every engine's windows minimized -- Stage Manager's marked, as its Home rule does for Home Minimizes Windows -- then a real Home" \
  "fn '__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotHomeV1(void) {' $A && grep -q 'int status = MSBDWinAPIHomeStatus(main, main && (DMSMHomeUILocked() || MSBDGuidedAccessActive()));' \$W/fn \
   && fn 'static void DMWindowAPIHome(NSString *why) {' $A && grep -q 'DMSMSetMinimized(k, YES);' \$W/fn && grep -q 'DMSMGoHomeForReal(why);' \$W/fn \
   && grep -q 'DMMinimizeAllWindows();' \$W/fn && grep -q 'DMMinimize();' \$W/fn"
check "  ... once (review 1.8.3 F10): again within a second, or while one waits, is the same Home; SpringBoard busy (iPadOS's own Cmd-H among it), it waits; at Home already, the windows only" \
  "fn '__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotHomeV1(void) {' $A && grep -q 'if (gWinAPIHomeWaiting || MSBDWinAPIHomeAgain(now - gWinAPIHomeAt)) {' \$W/fn \
   && grep -q 'DMWindowAPIHomeWhenFree(@\"the window API.s Home\", 0);' \$W/fn \
   && fn 'static void DMWindowAPIHomeWhenFree(NSString *why, int tries) {' $A && grep -q 'BOOL busy = !locked && (!DMWorkspaceIdle() || DMHomeFromKeys() || DMHomeIsOurs() || (DMSMEngine() && DMSMGestureLive()));' \$W/fn \
   && grep -q 'int step = MSBDWinAPIHomeStep(locked, busy, atHome, tries);' \$W/fn && grep -q 'if (step == kMSBDWinHomeMinimizeOnly) DMWindowAPIMinimizeAll(why);' \$W/fn \
   && grep -q 'else if (step == kMSBDWinHomeFull) DMWindowAPIHome(why);' \$W/fn"
check "the environment: read only, SpringBoard's own word on every engine and iPadOS -- the switcher's current mode (15's controller, 16-18's for the iPad's scene), else its layout state -- -2 locked, -1 off the main thread" \
  "fn '__attribute__((visibility(\"default\"), used)) int MSBDKeyPilotHomeEnvironmentV1(void) {' $A && grep -q 'BOOL read = !locked && DMWindowAPIEnvironmentRead(&env);' \$W/fn \
   && grep -q 'return MSBDWinAPIEnvironment(YES, locked, read, env);' \$W/fn && grep -q 'if (!main) return MSBDWinAPIEnvironment(NO, NO, NO, 0);' \$W/fn \
   && fn 'static BOOL DMWindowAPIEnvironmentRead(long long *env) {' $A && grep -q 'id sw = objc_getClass(\"SBMainSwitcherControllerCoordinator\") ? DMSMHomeSwitcherController() : DMSwitcherController();' \$W/fn \
   && grep -q 'SEL mode = NSSelectorFromString(@\"_currentUnlockedEnvironmentMode\");' \$W/fn && grep -q 'return DMSMHomeStateOf(DMSMHomeCurrentState(), env, &stage);' \$W/fn"
check "the debug caller: as KPWindowController.m -- the library by its path with RTLD_NOLOAD, dlsym, RTLD_DEFAULT too; debug builds only" \
  "awk '/^#if DEBUG/{d=1} d && /^static void DMWindowAPITestCall\(NSString \*what\) \{/{f=1} END{exit !f}' $A \
   && grep -q 'void \*h = dlopen(\"/var/jb/usr/lib/MacStatusBarAndDock/MacStatusBarCore.dylib\", RTLD_LAZY | RTLD_NOLOAD);' $A \
   && grep -q 'dlsym(RTLD_DEFAULT, \"MSBDKeyPilotLayoutV1\")' $A && grep -q 'kpapi_' $S"

# B79 (1.8.8.1.1): the build's export check never fails with the names there. Its block is cut out of the Makefile as make hands it to the
# shell and run as make runs that recipe when Theos shows the commands (messages=yes: set -o pipefail, then the recipe's set -e), on a
# MacStatusBarCore.dylib made here (arm64 and arm64e: the three names, then 20000 more that nm lists after them, so nm still writes about
# 700 KB once the names are read; the built one writes 17.6 KB, the names in its first 2.3 KB, and the 1.8.3 form failed 45 of 1200 there).
awk 'index($0, "\tfor s in MSBDKeyPilotLayoutV1 MSBDKeyPilotHomeV1 MSBDKeyPilotHomeEnvironmentV1; do for a in arm64 arm64e; do") == 1 {f=1}
     f {l = $0; sub(/^\t/, "", l); gsub(/\$\$/, "$", l); if (index($0, "\tdone; done;") == 1) {sub(/; *\\$/, "", l); print l; exit} print l}' $M > "$W/block"
sed 's/| grep " T _\$s\$" > \/dev\/null ||/| grep -q " T _$s$" ||/' "$W/block" > "$W/block.q"
mkdir "$W/api" "$W/miss" "$W/none"
awk 'BEGIN { print ".text"; n = split("MSBDKeyPilotLayoutV1 MSBDKeyPilotHomeV1 MSBDKeyPilotHomeEnvironmentV1", s, " ")
             for (i = 1; i <= n; i++) printf ".globl _%s\n_%s:\n", s[i], s[i]
             for (i = 0; i < 20000; i++) printf ".globl _zz_more_%05d\n_zz_more_%05d:\n", i, i
             print "ret" }' > "$W/api.s"
grep -v '_MSBDKeyPilotHomeV1' "$W/api.s" > "$W/miss.s"
clang -dynamiclib -arch arm64 -arch arm64e -install_name @rpath/MacStatusBarCore.dylib -o "$W/api/MacStatusBarCore.dylib" "$W/api.s"
clang -dynamiclib -arch arm64 -install_name @rpath/MacStatusBarCore.dylib -o "$W/miss64.dylib" "$W/api.s"
clang -dynamiclib -arch arm64e -install_name @rpath/MacStatusBarCore.dylib -o "$W/miss64e.dylib" "$W/miss.s"
lipo -create "$W/miss64.dylib" "$W/miss64e.dylib" -output "$W/miss/MacStatusBarCore.dylib"
runs() {   # $1 a block, $2 the folder of MacStatusBarCore.dylib, $3 runs: prints how many failed (the last run's output in $W/run.out)
  { echo 'set -o pipefail; ('; echo "set -e; P=\"$2\";"; cat "$1"; echo ')'; } > "$W/run.sh"
  local n=0 i=0; while [ $i -lt $3 ]; do bash "$W/run.sh" > "$W/run.out" 2>&1 || n=$((n + 1)); i=$((i + 1)); done; echo $n
}
blockok() {
  [ "$(wc -l < "$W/block" | tr -d ' ')" = 3 ] && grep -qF 'for s in MSBDKeyPilotLayoutV1 MSBDKeyPilotHomeV1 MSBDKeyPilotHomeEnvironmentV1; do for a in arm64 arm64e; do \' "$W/block" \
  && grep -qF '  nm -gU -arch $a "$P/MacStatusBarCore.dylib" | grep " T _$s$" > /dev/null || { echo "the window API'"'"'s $s is not exported' "$W/block" \
  && [ "$(tail -1 "$W/block")" = 'done; done' ] && ! cmp -s "$W/block" "$W/block.q" && grep -qF '| grep -q " T _$s$" ||' "$W/block.q"
}
libok() {
  local a; [ "$(lipo -archs "$W/api/MacStatusBarCore.dylib")" = "arm64 arm64e" ] || return 1
  for a in arm64 arm64e; do
    nm -gU -arch $a "$W/api/MacStatusBarCore.dylib" > "$W/nm.$a"
    [ "$(sed -n '1,3s/^[0-9a-f]* T //p' "$W/nm.$a" | tr '\n' ' ')" = "_MSBDKeyPilotHomeEnvironmentV1 _MSBDKeyPilotHomeV1 _MSBDKeyPilotLayoutV1 " ] || return 1
    [ "$(sed '1,3d' "$W/nm.$a" | wc -c | tr -d ' ')" -gt 600000 ] || return 1
  done
}
check "B79: the build's export check cut out of the Makefile (3 lines: grep with no -q reads nm's whole output), and its 1.8.3 form (grep -q)" "blockok"
check "  ... the library made here: arm64 and arm64e, the three names listed first, then over 600 KB of nm's lines" "libok"
check "  ... run 100 times as Theos runs the recipe (set -o pipefail, set -e): it never fails with the names there" "[ \"\$(runs \$W/block \$W/api 100)\" = 0 ]"
check "  ... made to fail: the 1.8.3 form fails there (grep -q leaves at the first name, nm's next write dies of SIGPIPE, pipefail fails the recipe)" \
  "[ \"\$(runs \$W/block.q \$W/api 10)\" -ge 1 ]"
check "  ... a slice without one of the names: the build stops, naming the name and the slice; no library: the build stops" \
  "[ \"\$(runs \$W/block \$W/miss 1)\" = 1 ] && grep -qx \"the window API's MSBDKeyPilotHomeV1 is not exported from MacStatusBarCore (arm64e): KeyPilot finds it by that name (statusbar/WindowAPI.h)\" \$W/run.out \
   && [ \"\$(runs \$W/block \$W/none 1)\" = 1 ]"
exit $fails
