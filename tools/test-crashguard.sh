#!/bin/bash
# Mac test of the crash guard's counting with the real helper (MacCrashBlame, built for the Mac) and the fixtures; then with the helper missing.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); R="$W/reports"; mkdir -p "$R"
clang -fobjc-arc -dynamiclib -framework Foundation -o "$W/MacCrashBlame.dylib" ../loader/CrashBlameHelper.m
setup() {
  rm -rf "$R"/* "$W"/verdicts.txt; cp crash-fixtures/ours-in-faulting-thread.ips "$W/ours.ips"
  cp crash-fixtures/ours-in-faulting-thread.ips "$R/SpringBoard-2026-09-26-100000.ips"
  cp crash-fixtures/other-tweak.ips "$R/SpringBoard-2026-09-26-100100.ips"
  cp crash-fixtures/apple-only-our-class-in-reason.ips "$R/SpringBoard-2026-09-26-100200.ips"
  echo "garbage" > "$R/SpringBoard-2026-09-26-100300.ips"; touch -t 202001011200 "$R/SpringBoard-2026-09-26-100300.ips"
  cp crash-fixtures/ours-in-faulting-thread.ips "$R/SpringBoard.cpu_resource-2026-09-26-100400.ips"
}
D="-DMSBD_GUARD_REPORTS=\"$R\" -DMSBD_GUARD_VERDICTS=\"$W/verdicts.txt\" -DMSBD_GUARD_RECORD=\"$W/record.txt\" -DMSBD_GUARD_RECENT=\"$W/recent.txt\" -DMSBD_GUARD_NOTICE_LIB=\"$W/missing-notice.dylib\" -DMSBD_GUARD_FILE=\"$W/guard.txt\""
setup; clang -Wall -Wno-unused-function $D -DMSBD_GUARD_BLAME_LIB="\"$W/MacCrashBlame.dylib\"" -o "$W/t1" test-crashguard.c && "$W/t1"
echo "   verdict file:"; sed 's/^/      /' "$W/verdicts.txt"
setup; clang -Wall -Wno-unused-function $D -DMSBD_GUARD_BLAME_LIB="\"$W/missing.dylib\"" -DEXPECT_NO_HELPER -o "$W/t2" test-crashguard.c && "$W/t2"
defaults delete com.besiktasliseba.test-msbd >/dev/null 2>&1 || true
rm -rf "$W"
