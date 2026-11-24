#!/bin/bash
# Mac test of the crash guard's counting with the real helper (MacCrashBlame, built for the Mac) and the fixtures; then with the helper missing.
# (1.8.7.7: the real reports of issue #14 and our own -- strong, weak and other tweaks' crashes, the causes kept. CRASHGUARD_ROOT=<tree>: the guard
#  and its helper from there, e.g. the code before the fix, run on the real reports only: those checks must fail.)
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); R="$W/reports"; mkdir -p "$R" "$W/tweaks"
ROOT=${CRASHGUARD_ROOT:-$PWD/..}
HD="-DMSBD_CAUSE_FILE=\"$W/causes.txt\" -DMSBD_CHOICY_PREFS=\"$W/choicy.plist\" -DMSBD_BLAME_TWEAK_DIR=\"$W/tweaks\""   # (no tweak installed on the Mac)
clang -fobjc-arc -dynamiclib -framework Foundation $HD -o "$W/MacCrashBlame.dylib" "$ROOT/loader/CrashBlameHelper.m"
# (review of 1.8.7.7: another tweak's library that loads after ours -- the class a crash's reason names, not there when the start judges)
mkdir -p "$W/late"; printf '#import <Foundation/Foundation.h>\n@interface OtherTweakLateListener : NSObject\n@end\n@implementation OtherTweakLateListener\n@end\n' > "$W/late/late.m"
clang -fobjc-arc -dynamiclib -framework Foundation -o "$W/late/OtherTweakLate.dylib" "$W/late/late.m"
setup() {
  rm -rf "$R"/* "$W"/verdicts.txt; cp crash-fixtures/ours-in-faulting-thread.ips "$W/ours.ips"
  cp crash-fixtures/ours-in-faulting-thread.ips "$R/SpringBoard-2026-09-26-100000.ips"
  cp crash-fixtures/other-tweak.ips "$R/SpringBoard-2026-09-26-100100.ips"
  cp crash-fixtures/apple-only-our-class-in-reason.ips "$R/SpringBoard-2026-09-26-100200.ips"
  echo "garbage" > "$R/SpringBoard-2026-09-26-100300.ips"; touch -t 202001011200 "$R/SpringBoard-2026-09-26-100300.ips"
  cp crash-fixtures/ours-in-faulting-thread.ips "$R/SpringBoard.cpu_resource-2026-09-26-100400.ips"
}
# (1.8.7: the displays domain is a test one; the guard writes into it, so CoreFoundation is linked: the guard finds it loaded)
D="-DMSBD_DISP_DOMAIN=\"com.besiktasliseba.test-msbd.displays\" -DMSBD_GUARD_REPORTS=\"$R\" -DMSBD_GUARD_VERDICTS=\"$W/verdicts.txt\" -DMSBD_GUARD_RECORD=\"$W/record.txt\" -DMSBD_GUARD_RECENT=\"$W/recent.txt\" -DMSBD_GUARD_NOTICE_LIB=\"$W/missing-notice.dylib\" -DMSBD_GUARD_FILE=\"$W/guard.txt\" -DMSBD_CAUSE_FILE=\"$W/causes.txt\" -DMSBD_STEP_FILE=\"$W/step.txt\" -DMSBD_CRASHMAP=\"$W/missing-crashmap.txt\" -iquote $ROOT/common -DMSBD_TEST_GUARD_H=\"$ROOT/common/CrashGuard.h\" -DMSBD_TEST_LATE_LIB=\"$W/late/OtherTweakLate.dylib\""
setup; clang -Wall -Wno-unused-function -framework CoreFoundation $D -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -o "$W/t1" test-crashguard.c && ${CRASHGUARD_ROOT:+env CRASHGUARD_REAL_ONLY=1} "$W/t1"
echo "   verdict file:"; sed 's/^/      /' "$W/verdicts.txt"
if [ -z "$CRASHGUARD_ROOT" ]; then
  setup; clang -Wall -Wno-unused-function -framework CoreFoundation $D -DMSBD_GUARD_BLAME_LIB="\"$W/missing.dylib\"" -DEXPECT_NO_HELPER -o "$W/t2" test-crashguard.c && "$W/t2"
fi
defaults delete com.besiktasliseba.test-msbd >/dev/null 2>&1 || true
for d in com.besiktasliseba.test-msbd com.besiktasliseba.test-msbd.displays; do defaults read $d >/dev/null 2>&1 || rm -f ~/Library/Preferences/$d.plist; done
defaults delete com.besiktasliseba.test-msbd.displays >/dev/null 2>&1 || true; rm -f ~/Library/Preferences/com.besiktasliseba.test-msbd.displays.plist
rm -rf "$W"
