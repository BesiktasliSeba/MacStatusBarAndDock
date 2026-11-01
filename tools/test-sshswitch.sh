#!/bin/bash
# Mac test of SSH's one logic (common/SSHSwitch.h, test-sshswitch.m, 1.7.6 item 1): the root helper's state line and what every switch reads from
# it, the answer to a request, the reasons, the address; then the wiring: one stored value and one notification for Settings' row, the menu bar's
# icon and the Control Center control, every switch asking the same way, and the test-only back-on flag in debug builds only.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreFoundation -o "$W/tss" test-sshswitch.m
"$W/tss"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
H=../macsettings/sshtoggled/main.m
check "the helper writes the state line, then posts the one notification" \
  "awk '/^static void writeStateAnswer\\(/{f=1} f&&/writeStateNew\\(on, wish, result\\)/{a=1} f&&a&&/notify_post\\(kMSBDSSHStateNote\\)/{print \"ok\"; exit} f&&/^}/{exit}' $H | grep -q ok"
check "  ... with the wish it acted on and its result after every switch" \
  "awk '/^static void apply\\(int on\\)/{f=1} f&&/writeStateAnswer\\(now, on \\? 1 : 0, result\\)/{print \"ok\"; exit} f&&/^}/{exit}' $H | grep -q ok"
check "  ... a failed write takes the older new-format line away (readers fall back to the legacy file, which has the new state; review n1)" \
  "[ \$(awk '/^static BOOL writeStateNew\\(/{f=1} f&&/unlink\\(STATE_FILE_NEW\\); return NO;/{n++} f&&/^}/{exit} END{print n+0}' $H) = 2 ] && awk '/^static BOOL writeStateNew\\(/{f=1} f&&/return NO;/&&!/unlink\\(STATE_FILE_NEW\\)/{bad=1} f&&/^}/{exit} END{exit bad}' $H"
check "  ... and the notification goes out when only the legacy file was written" \
  "grep -q 'if (writeStateLegacy(on) || written) notify_post(kMSBDSSHStateNote);' $H"
check "Settings' row follows the notification" "grep -q 'notify_register_dispatch(kMSBDSSHStateNote' ../macsettings/MacSettings.x"
check "the menu bar's icon follows the notification" "grep -q 'notify_register_dispatch(kMSBDSSHStateNote' ../statusbar/StatusBar.x"
check "the Control Center control follows the notification" "grep -q 'notify_register_dispatch(kMSBDSSHStateNote' ../ccmodule/MSBDSSHModule.m"
check "every switch asks through MSBDSSHAsk (no wish written anywhere else but the helper's debug back-on)" \
  "[ -z \"\$(grep -rln --include='*.x' --include='*.m' --include='*.h' 'CFSTR(\"sshWanted\")' .. | grep -v -e 'common/SSHSwitch.h' -e 'sshtoggled/main.m')\" ] && grep -q 'MSBDSSHAsk(on)' ../macsettings/MacSettings.x && grep -q 'MSBDSSHAsk(0)' ../statusbar/StatusBar.x && grep -q 'MSBDSSHAsk(want)' ../ccmodule/MSBDSSHModule.m"
check "the back-on test flag (/tmp/msb-ssh-backon) exists in debug builds only" \
  "awk '/^#if DEBUG/{d=1} /^#else/{d=0} /^#endif/{d=0} /msb-ssh-backon/{ if (!d) bad=1; seen=1 } END{exit !(seen && !bad)}' $H"
check "the control shows the helper's state (or the wish while it waits), never one of its own" \
  "awk '/^- \\(BOOL\\)showsOn/{f=1} f&&/MSBDSSHReadState\\(\\)/{print \"ok\"; exit} f&&/^}/{exit}' ../ccmodule/MSBDSSHModule.m | grep -q ok"
[ $fails = 0 ] && echo "test-sshswitch: wiring checks pass" || { echo "test-sshswitch: wiring checks FAILED"; exit 1; }
