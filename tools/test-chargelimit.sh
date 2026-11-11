#!/bin/bash
# Mac test of the Charge Limit (1.7.8 item 5): its decisions and readings (common/ChargeLimit.h, test-chargelimit.c), then the job as built and
# packaged: chargehelper/ (msbdcharge) holds with powerd's ChargeInhibit on the SMC iPads and Apple's PredictiveChargingInhibit on the PMU ones,
# comes down with DisableInflow, clears what can outlive it first at every start and at SIGTERM, raises again what a restarted powerd forgot,
# and the package starts, stops and resets it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tcl" test-chargelimit.c
"$W/tcl"
M=../chargehelper/main.m; D=../layout/DEBIAN; PL=../layout/Library/LaunchDaemons/com.besiktasliseba.chargelimit.plist
fails=0
check() { if "${@:2}"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$M"; }   # one function of main.m, from its first line to its closing brace
has() { fn "$1" | grep -qF -- "$2"; }
line() { awk -v s="$2" -v from="$1" 'index($0, from) == 1 {f=1} f && index($0, s) {print NR; exit}' "$M"; }   # first line with $2 after the line starting with $1
built() {
  grep -q '^TOOL_NAME = msbdcharge' ../chargehelper/Makefile && grep -q '^msbdcharge_INSTALL_PATH = /usr/libexec' ../chargehelper/Makefile &&
  grep -q -- '--generate-entitlement-der' ../chargehelper/Makefile && grep -q 'com.apple.private.iokit.powersource-control' ../chargehelper/entitlements.plist &&
  grep -q '^SUBPROJECTS += chargehelper' ../Makefile
}
job() {
  plutil -lint "$PL" >/dev/null && [ "$(plutil -extract Label raw "$PL")" = com.besiktasliseba.chargelimit ] &&
  [ "$(plutil -extract ProgramArguments.0 raw "$PL")" = /var/jb/usr/libexec/msbdcharge ] && [ "$(plutil -extract KeepAlive.SuccessfulExit raw "$PL")" = false ] &&
  [ "$(plutil -extract RunAtLoad raw "$PL")" = true ]
}
hold() {
  has 'static void HoldOn(NSSet *held) {' 'if (gPMU) {' && has 'static void HoldOn(NSSet *held) {' 'SetPredictiveInhibit(YES)' &&
  has 'static void HoldOn(NSSet *held) {' 'Raise(@"ChargeInhibit"' && grep -q 'IOServiceMatching("AppleARMPMUCharger"));' "$M" &&
  grep -q 'if (gBattery) { gPMU = YES; return YES; }' "$M"
}
down() {
  has 'static void Evaluate(NSString *why) {' 'Raise(@"DisableInflow"' && has 'static void Evaluate(NSString *why) {' 'if (o.keepAwake) StayAwake(held, now); else StayAwakeOff();' &&
  has 'static void StayAwake(NSSet *held, double now) {' 'Raise(@"PreventUserIdleSystemSleep", AwakeName('
}
renew() {   # renewed every 5 minutes, overlapping: the old one let go only once powerd lists the new one (iPadOS 16-18 drop one ~10 minutes old)
  local f='static void StayAwake(NSSet *held, double now) {'
  has "$f" 'if ([held containsObject:AwakeName(gAwakeNextSlot)]) {' && has "$f" 'Lower(&gAwake); gAwake = gAwakeNext;' &&
  has "$f" 'if (now - gAwakeNextSince < 180) return;' && has "$f" 'if (now - gAwakeSince >= 300 * (gAwakeNotListed > 2 ? 3 : 1)) {' &&
  awk -v f="$f" 'index($0, f) == 1 {x=1} x && /containsObject:AwakeName\(gAwakeNextSlot\)/ && !a {a=NR} x && /Lower\(&gAwake\); gAwake = gAwakeNext;/ && !b {b=NR} END{exit !(a && b && a <= b)}' "$M"
}
rules() {
  local e='static void Evaluate(NSString *why) {'
  has "$e" 'MSBDChargeOut o = MSBDChargeDecide(in);' && has "$e" 'MSBDChargeCalibrationDue(' && has "$e" 'MSBDChargeNeedsPulse(' &&
  has "$e" 'limitOn && comeDown)) {' && has "$e" 'if (calibrating && !comeDown) {' && has "$e" 'MSBDChargeCutAllowed(now, gCutStarted, gCutMisread), comeDownTo, gHoldIgnored, gCutIgnored,' &&
  has "$e" 'comeDownTo = comeDown && holdAt == limit;' &&
  has 'static int SettingsNow(BOOL *comeDown) {' ': kMSBDChargeComeDownDefault;' &&
  has "$e" 'MSBDChargeLeverCheck(' && has "$e" 'MSBDChargeCutAllowed(now, gCutStarted, gCutMisread)' && has "$e" 'CutShown(b)' &&
  grep -q 'if (MSBDChargeStartLoop(times, n, now)) { gRunning = 0;' "$M" && grep -q 'return MSBDChargeCutShown(' "$M"
}
order() { has 'static void Evaluate(NSString *why) {' 'case kMSBDChargeHold: HoldOn(held); CutOff(now); break;'; }
cable() {
  has 'static void Evaluate(NSString *why) {' 'int plugged = MSBDChargePlugged(raw, ourCut, gCutAdapter, adapter);' &&
  has 'static void Evaluate(NSString *why) {' '|| (gOwnCutEnded > 0 && now - gOwnCutEnded < 30);' &&
  has 'static void Evaluate(NSString *why) {' 'gCutAdapter = adapter; gCutStarted = now;'
}
first() {
  local r s
  r=$(line 'int main(' 'ResetCharging(nil, NO, NO);'); s=$(line 'int main(' 'DISPATCH_SOURCE_TYPE_SIGNAL'); [ -n "$r" ] && [ -n "$s" ] && [ "$r" -lt "$s" ] &&
  has 'static void Terminate(int sig) {' 'if (gPMU) SetPredictiveInhibit(NO);' && fn 'int main(' | grep -q 'signal(sig, SIG_IGN);' &&
  fn 'int main(' | grep -q 'const int sigs\[3\] = { SIGTERM, SIGINT, SIGHUP };'
}
reset() {
  local r='static void ResetCharging(NSString *why, BOOL cuts, BOOL jobRuns) {'
  has "$r" 'if (hold) { holdLeft = YES;' && has "$r" 'if (cut) { cutLeft = YES; PulseOncePowerdAnswers(@"DisableInflow"); }' &&
  has "$r" 'if (!i && !leftCut) for (int j = 0; j < 15 && b && CutShown(b); j++)' && has "$r" 'if (!hold && !cut) break;' &&
  fn 'int main(' | grep -q 'ResetCharging(@"--reset", YES, jobRuns);' && fn 'int main(' | grep -q 'notify_set_state(t, 0); notify_post(MSBD_CHARGE_STATE);'
}
restart() {
  has 'static void HoldOn(NSSet *held) {' '![held containsObject:@"ChargeInhibit"]' && has 'static void Evaluate(NSString *why) {' '![held containsObject:@"DisableInflow"]' &&
  has 'static void StayAwake(NSSet *held, double now) {' '![held containsObject:AwakeName(gAwakeSlot)]' && grep -q 'IOPMCopyAssertionsByProcess(&all)' "$M"
}
leftcut() {
  local e='static void Evaluate(NSString *why) {'
  has "$e" 'if (!gDown && now - gOwnCutEnded >= 60 && CutShown(b)) {' && has "$e" 'if (now - gCutSeenSince >= 60 && !gCutPulsed) {'
}
pool() { grep -q '^static void Evaluate(NSString \*why) { @autoreleasepool {' "$M"; }
package() {
  awk '/--is-ipad/{i=NR} /\$L load .*chargelimit/ && !l {l=NR} END{exit !(i && l && i < l)}' "$D/postinst" &&
  [ "$(grep -c 'com.besiktasliseba.chargelimit.plist' "$D/postinst")" -ge 3 ] &&
  awk '/launchctl unload .*chargelimit/{u=NR} /msbdcharge --reset/{r=NR} END{exit !(u && r && u < r)}' "$D/prerm" &&
  grep -q 'chargelimit.plist /var/jb/var/log/msbdcharge.log' "$D/postrm"
}
release() { grep -q 'd/var/jb/usr/libexec/msbdcharge d/var/jb/Library/LaunchDaemons/com.besiktasliseba.chargelimit.plist' verify-release.sh; }
check "built as /usr/libexec/msbdcharge, codesigned with DER entitlements (the battery service's write permission for the PMU key)" built
check "a root launchd job of its own, started at load, restarted only after a crash (it ends by itself when nothing is set)" job
idle() {   # (1.8.6: nothing set, nothing running: the job ends by itself, the root helper starts it when a setting is made)
  local H=../macsettings/sshtoggled/main.m
  grep -q 'if (!ChargeWanted() && !SocKeptCount(' $M && grep -q 'if (!ChargeWanted()) EndIdle(@"settings");' $M && grep -q 'if (!ChargeWanted()) EndIdle(@"tick");' $M &&
  grep -q 'if (gHold || gDown || gAwake || gAwakeNext || gPCIOn || gSocToken || gSocLeft || (gOwnCutEnded > 0 && now - gOwnCutEnded < 30)) return;' $M &&
  grep -q 'LAUNCHCTL, "start", "com.besiktasliseba.chargelimit"' $H && grep -q 'notify_register_dispatch(MSBD_CHARGE_PREFS_CHANGED, &t8' $H && grep -q 'ChargeJobKick(@"daemon start");' $H
}
check "nothing set: the job ends by itself once nothing of its is raised; the root helper starts it when a setting is made (and at its own start)" idle
check "hold: SMC iPads powerd's ChargeInhibit assertion, PMU iPads PredictiveChargingInhibit (the chips that ignore IsCharging)" hold
check "coming down: powerd's DisableInflow assertion; kept awake when the rules say (PreventUserIdleSystemSleep)" down
check "decisions and readings only through the tested rules (decide, full charges, self-checks, cut start, cut showing, start loop); coming down off: no cut, no monthly full charge" rules
check "the hold first, then the adapter cut let go (no moment of charging between)" order
check "the cable during our cut and 30 s after: the adapter seen when it went up (the SMC iPads read the cable as out then)" cable
check "what can outlive the job (the PMU key) cleared before anything else at every start, and at SIGTERM / SIGINT / SIGHUP (on the main queue)" first
check "a reset raises a hold or a cut only where one shows, a cut only after 15 s to end by itself (each end lights the Lock Screen), and sets the published state to no job" reset
check "a restarted powerd: our assertions checked with powerd and raised again" restart
check "the stay-awake renewed every 5 minutes, overlapping: the old one let go only once powerd lists the new one (iPadOS 16-18 drop one ~10 minutes old)" renew
norestart() {   # a powerd that started again answers nothing for us: two looks without an answer -> each of ours raised anew, the new one first
  local e='static void Evaluate(NSString *why) {' r='static void RaiseAgainAfter(IOPMAssertionID *a, NSString *type, NSString *name) {'
  has "$e" 'else if (++gNoAnswer >= 2 && now - gLastRefresh >= 600) {' && has "$e" 'RaiseAgainAfter(&gDown, @"DisableInflow"' && has "$e" 'RaiseAgainAfter(&gHold, @"ChargeInhibit"' &&
  has "$e" 'RaiseAgainAfter(&gAwake, @"PreventUserIdleSystemSleep"' &&
  awk -v f="$r" 'index($0, f) == 1 {x=1} x && /fresh = Raise\(type, name\)/ && !a {a=NR} x && /IOPMAssertionRelease\(old\)/ && !b {b=NR} END{exit !(a && b && a < b)}' "$M"
}
check "a restarted powerd (no answer for our assertions twice): each raised anew, the new one before the old one goes (a cut never blinks off)" norestart
quiet() {   # the end of our cut kept quiet: the job tells SpringBoard first, SpringBoard skips the chime and the power wake by the tested rule
  local Q=../statusbar/ChargeQuiet.x SB=../statusbar/StatusBar.x
  fn 'static void CutOff(double now) {' | grep -q 'if (gDown) { notify_post(MSBD_CHARGE_CUT_ENDING); Lower(&gDown);' &&
  awk '/^static void Terminate\(int sig\) \{/{x=1} x && /notify_post\(MSBD_CHARGE_CUT_ENDING\)/ && !a {a=NR} x && /Lower\(&gDown\)/ && !b {b=NR} END{exit !(a && b && a < b)}' "$M" &&
  grep -q 'if (!MSBDChargeQuietAfterCut(since, gCQAdapterAtEnd, now)) {' $Q && grep -q -- '- (void)playChargingChimeIfAppropriate {' $Q &&
  grep -q -- '- (void)possiblyWakeForPowerStatusChangeWithUnlockSource:(long long)source {' $Q && grep -q 'if (chime) %init(CQChime);' $Q && grep -q 'if (wake) %init(CQWake);' $Q &&
  grep -q 'notify_register_dispatch(MSBD_CHARGE_CUT_ENDING' $Q && grep -q '^MacStatusBarCore_FILES = .* ChargeQuiet.x' ../statusbar/Makefile &&
  awk '/^%ctor \{/{c=1} c && /tweakEnabled/ && !t {t=NR} c && /MSBDChargeQuietInit\(\);/ && !q {q=NR} c && /if \(gStockBar\) \{ DMSpotPublishOff/ && !s {s=NR} END{exit !(t && q && s && t < q && q < s)}' $SB &&
  grep -q '^file MacStatusBarCore ^ChargeQuiet\\.x\$ part' crashmap-rules.txt
}
check "the end of our cut kept quiet: the job tells SpringBoard before it lets go; SpringBoard skips the chime and the power wake for 20 s unless another adapter is in" quiet
check "a cut nobody holds: let go once, after it has shown for a minute (not right after our own)" leftcut
check "run-loop callbacks drain their own autorelease pool (the job runs for weeks)" pool
check "the package: started after the iPad check (postinst), again after a failed upgrade/removal, stopped then reset (prerm), its files removed (postrm)" package
check "the release check knows the job's files" release
[ $fails = 0 ] && echo "test-chargelimit: wiring checks pass" || { echo "test-chargelimit: wiring checks FAILED"; exit 1; }
