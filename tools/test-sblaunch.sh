#!/bin/bash
# Mac test of -[SpringBoard launchApplicationWithIdentifier:suspended:] with Aerial, Zetsu or MilkyWay4 (1.8.0 item 8, GitHub #10: InstaLauncher 2):
# the rule (statusbar/SBLaunchRule.h, test-sblaunch.c), then the hook as built in StatusBar.x -- Zetsu's repeat check first, the rule with the
# caller's image, then the same decision as an open request from outside (its window forward, or a new window with Open Apps as Windows).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -Wall -Wno-unused-function -o "$W/tsl" test-sblaunch.c
"$W/tsl"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
S=../statusbar/StatusBar.x
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $S > "$W/fn"; [ -s "$W/fn" ]; }
awk '/^- \(BOOL\)launchApplicationWithIdentifier:\(id\)identifier suspended:\(BOOL\)suspended \{/{f=1} f {print} f && /^}/ {exit}' $S > "$W/hook"
check "the hook: Zetsu's own repeats first (one scene kept), then the launch as every other one -- the engine found from its caller's address, not a guess" \
  "awk '/const char \*engine = DMSBLaunchEngineFrom\(ra\);/{e=NR} /DMSwallowZetsuRelaunch\(identifier, engine\)\) return YES;/{z=NR} /DMSBLaunchOpensWindow\(identifier, suspended, engine\)\) return YES;/{w=NR} /return %orig;/{o=NR} END{exit !(e && z > e && w > z && o > w)}' $W/hook \
   && grep -q 'void \*ra = __builtin_return_address(0);' $W/hook"
check "  ... the engine up the callers (review 8): the call stack from the hook's return address (unsigned on arm64e, found wherever this is inlined, else that caller alone), SBLaunchRule.h's walk with dladdr's images and our own image; Zetsu's repeat check takes the same engine" \
  "fn 'const char *DMSBLaunchEngineFrom(void *caller) {' && grep -q 'caller = ptrauth_strip(caller, ptrauth_key_return_address);' \$W/fn && grep -q 'int n = backtrace(stack, kMSBDSBLaunchCallerDepth + 4), i = 0;' \$W/fn && grep -q 'while (i < n && stack\[i\] != caller) i++;' \$W/fn \
   && grep -q 'if (i == n) { stack\[0\] = caller; i = 0; n = 1; }' \$W/fn && grep -q 'return MSBDSBLaunchEngineCaller(stack + i, n - i, DMSBLaunchImageOf, ours);' \$W/fn \
   && grep -q 'if (!ours) ours = DMSBLaunchImageOf((const void \*)DMSBLaunchEngineFrom);' \$W/fn && grep -q '^static const char \*DMSBLaunchImageOf(const void \*a) { Dl_info di; return a && dladdr(a, &di) ? di.dli_fname : NULL; }' $S \
   && fn 'BOOL DMSwallowZetsuRelaunch(NSString *bundleID, const char *engine) {' && grep -q 'if (!engine || !strstr(engine, \"/Zetsu.dylib\")) return NO;' \$W/fn && ! grep -q 'dladdr' \$W/fn"
check "  ... in the window launch group, which every window engine installs (WindowLaunch)" \
  "awk '/^%group WindowLaunch\$/{g=NR} /^- \(BOOL\)launchApplicationWithIdentifier:\(id\)identifier suspended:\(BOOL\)suspended \{/{h=NR} END{exit !(g && h > g)}' $S && grep -q '%init(WindowLaunch)' $S"
check "the decision: SBLaunchRule.h with the engine making the call and the Lock Screen / Cover Sheet (review 6), on the main thread; then an open request's own: its window (here or on another desktop), else a new window when it may open as one" \
  "fn 'BOOL DMSBLaunchOpensWindow(NSString *bundleID, BOOL suspended, const char *engine) {' && grep -q 'if (!MSBDSBLaunchToWindow(suspended, gForceFullScreenLaunch, locked, DMSMEngine(), DMActiveEngine() != DMEngineNone, engine)) return NO;' \$W/fn \
   && grep -q 'BOOL locked = DMLockUp(DMSBManager(\"SBLockScreenManager\")) || DMCoverSheetShown();' \$W/fn && grep -q '!pthread_main_np()' \$W/fn \
   && grep -q 'BOOL hasWindow = DMHasWindowFor(bundleID) || DMMSWWindowElsewhere(bundleID);' \$W/fn && grep -q 'BOOL windowable = !DMActivationNeedsIcon(bundleID) && DMWindowedLaunchEligible(bundleID);' \$W/fn \
   && grep -q 'BOOL done = DMWindowedLaunch(bundleID);' \$W/fn && grep -q 'return done;' \$W/fn && grep -q '#include \"SBLaunchRule.h\"' $S"
check "  ... the same decision as the open requests from outside (SBMainWorkspace's hook): its window, or a new window" \
  "grep -q 'BOOL hasWindow = !isAirDrop && !background && bundleID.length && (DMHasWindowFor(bundleID) || DMMSWWindowElsewhere(bundleID));' $S && grep -q 'BOOL windowable = !isAirDrop && !background && bundleID.length && !DMActivationNeedsIcon(bundleID) && DMWindowedLaunchEligible(bundleID);' $S"
check "our own full-screen launch goes through it marked (gForceFullScreenLaunch around SpringBoard's call), the window launch's own marks keep a launch we started from opening twice" \
  "fn 'static void DMOpenFullScreen(NSString *bundleID) {' && awk '/gForceFullScreenLaunch = YES;/{y=NR} /launchApplicationWithIdentifier:bundleID suspended:NO/{l=NR} /gForceFullScreenLaunch = NO;/{n=NR} END{exit !(y && l > y && n > l)}' \$W/fn"
check "debug only: the call as built (/tmp/msb-sblaunch-asbuilt) and every caller logged" \
  "fn 'BOOL DMSBLaunchOpensWindow(NSString *bundleID, BOOL suspended, const char *engine) {' && grep -q 'DMTestFlag(\"/tmp/msb-sblaunch-asbuilt\")' \$W/fn && grep -q '\[sblaunch\] launch call for' $W/hook"
[ $fails = 0 ] && echo "test-sblaunch wiring: all passed" || { echo "test-sblaunch wiring: FAILED"; exit 1; }
