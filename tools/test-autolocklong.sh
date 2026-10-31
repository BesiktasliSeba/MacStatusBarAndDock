#!/bin/bash
# Mac test of the longer Auto-Lock times' SpringBoard side (macsettings/AutoLockLongest.h): test-autolocklong.m; and the wiring: the step's hook uses
# the tested rule, goes in only with Apple's method and the descriptor's setters as expected, and Settings offers the times only while it is in.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/t" test-autolocklong.m
"$W/t"
T=../macsettings/AutoLockTimer.x; L=../macsettings/AutoLock.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the hook decides with MSAutoLockKeepsTime, after SpringBoard's own step" \
  "awk '/^- \\(BOOL\\)updateIdleTimerSettingsForAutoLockTimeout:\\(id\\)desc \\{/{f=1} f' $T | awk '/%orig/{o=1} o && /MSAutoLockKeepsTime\\(t, total\\)/{print \"ok\"; exit}' | grep -q ok"
check "  ... and gives the warn interval back as it was before the step" \
  "grep -q 'double warnBefore = MSALTInterval(desc, @selector(warnInterval));' $T && grep -q 'setWarnInterval:), warnBefore);' $T"
check "it goes in only with the step's and the descriptor's methods as on 15-18 (encodings checked)" \
  "grep -q '\"B24@0:8@16\"' $T && grep -q 'setTotalInterval:\"), \"v24@0:8d16\"' $T && grep -q 'setWarnInterval:\"), \"v24@0:8d16\"' $T && grep -q 'if (!ok) { if (token) notify_set_state(token, 0); }   // (not as on 15-18' $T && awk '/^    else \\{/{e=1} e && /%init\\(MSAutoLockTimer\\);/{print \"ok\"; exit}' $T | grep -q ok"
check "  ... and publishes this SpringBoard's pid once it is in" \
  "grep -q '%init(MSAutoLockTimer);' $T && grep -q 'notify_set_state(token, (uint64_t)getpid());' $T"
check "Settings adds 2 hours only while a running SpringBoard keeps it (30 min and 1 h: stock SpringBoard keeps them)" \
  "awk '/^static NSArray<NSNumber \\*> \\*MSLongTimes/{f=1} f && /return MSAutoLockLongTimesKept\\(\\) \\? kept : stock;/{print \"ok\"; exit}' $L | grep -q ok && grep -q 'stock = @\\[@1800, @3600\\];' $L"
check "the list's longest time is the one SpringBoard keeps (one constant)" \
  "grep -q 'kept = @\\[@1800, @3600, @((NSInteger)MS_AUTOLOCK_LONGEST)\\];' $L"
check "the step's hook is built into the Settings part SpringBoard loads (MacSettingsBadge)" \
  "grep -q '^MacSettingsBadge_FILES = Badge.x AutoLockTimer.x$' ../macsettings/Makefile"
# ---- 2 hours left behind (1.7.3, item 9) ----
G=../macsettings/AutoLockGiveBack.h; S=../macsettings/sshtoggled/main.m
check "removal: the root helper writes its \"removal\" marker, then tells SpringBoard (which may change the setting; the script may not) and gives it a moment" \
  "awk '/^static void Uninstall\\(void\\)/,/^}/' $S | awk '/fputs\\(\"removal\", m\\)/{m=1} m && /AutoLockLowerForRemoval\\(\\);/{print \"ok\"; exit}' | grep -q ok && awk '/^static void AutoLockLowerForRemoval/,/^}/' $S | grep -q 'notify_post(MS_AUTOLOCK_CHECK);'"
check "  ... and forgets an earlier switch-off's record (nothing is given back after a removal)" "grep -q 'WriteMobilePrefsKey(@MS_AUTOLOCK_DOMAIN, @MS_AUTOLOCK_RECORD, nil, NO)' $S"
check "switched off / on again: SpringBoard told right after the marker is written / removed" \
  "awk '/^static void RestoreForOff/,/^}/' $S | awk '/fopen\\(OFFMARKER/{m=1} m && /notify_post\\(MS_AUTOLOCK_CHECK\\)/{print \"ok\"; exit}' | grep -q ok && awk '/^static void PrepareForOn/,/^}/' $S | awk '/unlink\\(OFFMARKER\\)/{m=1} m && /notify_post\\(MS_AUTOLOCK_CHECK\\)/{print \"ok\"; exit}' | grep -q ok"
check "the stored setting is only ever read by the root helper (ManagedConfiguration's files are its own), never written" \
  "! grep -rn 'UserSettings.plist\\|UserConfigurationProfiles\\|ConfigurationProfiles' ../macsettings/*.x ../macsettings/*.h ../dock ../statusbar ../common && [ \$(grep -c 'EffectiveUserSettings.plist' $S) = 1 ] && ! grep -n 'EffectiveUserSettings.*writeToFile' $S"
check "SpringBoard changes it as Settings' list does (ManagedConfiguration's setter, both methods' types checked), off the main thread" \
  "grep -q '\"@24@0:8@16\") || strcmp(method_getTypeEncoding(ms), \"v32@0:8@16@24\")' $G && grep -q 'dispatch_async(q, ^{' $G && grep -q 'MSAutoLockStep step = MSAutoLockDecide(stored, kept, leaving, removing, record);' $G"
check "  ... the record written before the setting is lowered (a crash in between never loses the user's 2 hours)" \
  "awk '/MSAutoLockLowerAndRecord\\) MSALGBSetRecord\\(stored\\)/{r=1} r && /set, @\\(\\(NSInteger\\)MS_AUTOLOCK_STOCK_LONGEST\\), @\"maxInactivity\"\\)/{print \"ok\"; exit}' $G | grep -q ok"
check "  ... the marker counts only as root's own file" "grep -q 'S_ISREG(st.st_mode) || st.st_uid != 0) return NO;' $G"
check "the keeping part looks at its start and when told, with whether it keeps 2 hours here" \
  "grep -q 'notify_register_dispatch(MS_AUTOLOCK_CHECK, &check' $T && grep -q 'MSAutoLockSettle(ok, @\"MacStatusBar.s part, start\"' $T"
check "the Dock's part (it runs while MacStatusBar is off) looks only when the keeping part is not in this SpringBoard" \
  "grep -q 'MSAutoLockWatchFromDock(^(NSString \\*l) { DMLog(l); });' ../dock/Dock.x && grep -q 'if (!MSALGBKeptHere()) MSAutoLockSettle(NO, why, log);' $G"
[ $fails = 0 ] && echo "test-autolocklong: wiring checks pass" || { echo "test-autolocklong: WIRING FAILED"; exit 1; }
