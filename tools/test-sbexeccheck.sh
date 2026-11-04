#!/bin/bash
# Mac test (1.7.9): in SpringBoard, whether a file of ours is installed is read from the file's own mode (stat), never asked with access(X_OK):
# SpringBoard's sandbox answers that exec check with EPERM on iPadOS 18.5 (/var/jb/usr/libexec/msbdcharge on the A12Z, 2 Nov: F_OK and stat fine,
# mode 755), so it read "not installed". The battery menu's Charge Limit job (BatteryMenu.h DMBattChargeJob) and the root helper the engine
# respring question waits for (StatusBar.x DMEngineHelperInstalled, the same folder). The X_OK checks left in SpringBoard's code ask a real
# permission: sbreload's before it is started (where it may not be, 18, the respring goes SpringBoard's own way), a folder's search permission
# (Finder, Downloads), and the battery menu's debug probe.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
SB=../statusbar/StatusBar.x; B=../statusbar/BatteryMenu.h
# SpringBoard's code: the status bar and Dock parts, without their Settings pages (those run in Settings, whose sandbox answers the check)
sbcode() { grep -rn "$1" ../statusbar ../dock ../common ../appbridge ../ccmodule ../spotlight ../prewarmblock ../loader --include=*.x --include=*.xm --include=*.h --include=*.m --include=*.c \
           | grep -v 'macstatusbarprefs/\|macstatusbarsettings/\|dockmagnificationprefs/\|dockmagnificationsettings/' | grep -v '^[^:]*:[0-9]*: *//'; }
check "the engine respring question waits for the root helper where it is installed, read from its file's mode" \
  "grep -q 'static BOOL DMEngineHelperInstalled(void) { struct stat st; return stat(\"/var/jb/usr/libexec/sshtoggled\", &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR); }' $SB && grep -q 'BOOL engineAsk = engines > 1 || gEngineAskNone || gEngineAskSMBack;' $SB && grep -q 'if ((engineAsk || gEngineAskCC || gEngineAskBanners) && DMEngineHelperInstalled()) {' $SB"
check "  ... and the battery menu's Charge Limit rows for the job the same way" \
  "grep -q 'static BOOL DMBattChargeJob(void) { struct stat st; return stat(MSBD_BATT_CHARGE_JOB, &st) == 0 && S_ISREG(st.st_mode) && (st.st_mode & S_IXUSR); }' $B"
check "no exec check of a file of ours in /var/jb/usr/libexec in SpringBoard's code" \
  "! sbcode 'X_OK' | grep -q 'libexec\\|MSBD_BATT_CHARGE_JOB, X_OK) =='"
check "the X_OK checks left in SpringBoard's code are the known ones (a new one: read installed files from their mode, or add it here with its reason)" \
  "[ \"\$(sbcode 'X_OK)' | cut -d: -f1 | sort | uniq -c | awk '{print \$2\"=\"\$1}' | tr '\n' ' ')\" = '../dock/Downloads.m=1 ../statusbar/BatteryMenu.h=1 ../statusbar/Finder.h=3 ../statusbar/StatusBar.x=1 ' ] \
   && grep -q 'int err = access(sbreload, X_OK) == 0 ? 0 : errno;' $SB && [ \$(grep -c 'access([^)]*R_OK | X_OK) != 0' ../statusbar/Finder.h) = 3 ] \
   && grep -q 'access(p.fileSystemRepresentation, R_OK | W_OK | X_OK) != 0' ../dock/Downloads.m && awk '/^static BOOL DMBattTrigger/,/^}/' $B | grep -q 'int x = access(MSBD_BATT_CHARGE_JOB, X_OK), ex = errno;'"
[ $fails = 0 ] && echo "test-sbexeccheck: wiring checks pass" || { echo "test-sbexeccheck: wiring checks FAILED"; exit 1; }
