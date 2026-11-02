#!/bin/bash
# Mac test of SpringBoard's start-up assertion given back (statusbar/StartupAssertion.h, battery drain F1b): only our own process's assertion of
# exactly that name is released, by its id from powerd's own list; SpringBoard does it a minute after it starts (whatever bar shows: planned
# before the start's returns for Use Stock Status Bar and Mac Status Bar off) and before any respring of ours (Safe Mode's respring included),
# so a later death of SpringBoard leaves no SystemIsActive behind.
set -e
cd "$(dirname "$0")"
H=../statusbar/StartupAssertion.h; SB=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the name is BacklightServices' start-up assertion, exactly" "grep -q '#define kMSBDStartupAssertionName @\"BacklightServices.backlightActiveOn.startup\"' $H"
check "only our own process's list is read (powerd's list keyed by our pid)" "grep -q 'NSArray \\*mine = ((__bridge NSDictionary \\*)all)\\[@(getpid())\\];' $H"
check "  ... only assertions of that name are released" "grep -q 'if (!\\[a isKindOfClass:\\[NSDictionary class\\]\\] || !\\[a\\[@\"AssertName\"\\] isEqual:kMSBDStartupAssertionName\\]) continue;' $H"
check "  ... by the id powerd lists, with IOPMAssertionRelease (the one call that changes anything)" \
  "grep -q 'int r = rel(\\[idv unsignedIntValue\\]);' $H && [ \$(grep -c 'rel(' $H) = 1 ]"
check "our Respring gives it back before sbreload is started or the relaunch asked for" \
  "awk '/^static void DMRespring\\(void\\) \\{/,/^}/' $SB | awk '/DMGiveBackStartupAssertionNow\\(@\"before our respring\"\\);/{a=NR} /posix_spawn\\(/{b=NR} /MSBDRelaunchLikeSbreload\\(\\)/{c=NR} END{exit !(a && b > a && c > a)}'"
check "  ... Safe Mode's respring goes through it" "awk '/^static void DMEnterSafeMode\\(void\\) \\{/,/^}/' $SB | grep -q 'if (ok) DMRespring();'"
CT="awk '/^%ctor \\{/,/^}/' $SB"
check "a minute after SpringBoard's start, planned once" \
  "$CT | grep -q 'if (!DMCtorSkip(\"power\")) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 \\* NSEC_PER_SEC)), dispatch_get_main_queue(), ^{' && [ \$(grep -c 'DMGiveBackStartupAssertionNow(@\"a minute after the start\");' $SB) = 1 ]"
check "  ... planned before any return of the start (Use Stock Status Bar on, Mac Status Bar switched off: SpringBoard's leak all the same)" \
  "$CT | awk '/DMGiveBackStartupAssertionNow\\(@\"a minute after the start\"\\);/{a=NR} /return;/&&!r{r=NR} END{exit !(a && r && a < r)}' && $CT | grep -q 'if (!enabled) {' && $CT | grep -q 'if (gStockBar) {.*return; }'"
check "a release feature marker when one was given back" "awk '/^static void DMGiveBackStartupAssertionNow\\(NSString \\*when\\) \\{/,/^}/' $SB | grep -q 'DM_FEATURE_MARK(\"startup-assertion-given-back\")'"
[ $fails = 0 ] && echo "test-startupassertion: all checks pass" || { echo "test-startupassertion: checks FAILED"; exit 1; }
