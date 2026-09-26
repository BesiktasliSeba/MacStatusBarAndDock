#!/bin/bash
# test-postrm.sh: runs layout/DEBIAN/postrm on the Mac with /var/jb and /var/mobile pointing into a scratch folder, and checks what it removes and
# what it keeps.
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-postrm.XXXXXX")
trap 'rm -rf "$W"' EXIT
J="$W/root/var/jb"; M="$W/root/var/mobile"
sed -e "s#/var/jb#$J#g" -e "s#/var/mobile/Library/Caches#$M/Library/Caches#g" layout/DEBIAN/postrm > "$W/postrm"; chmod +x "$W/postrm"
S="$J/var/lib/sshtoggled-engines"; P="$J/var/mobile/Library/Preferences"
GONE="$S/msb-off-restored $S/msb-off-alert $S/msb-config $S/ssh-state $S/.ssh-state.Ab12Cd
$P/MacStatusBarAndDock-CrashGuard.txt $P/MacStatusBarAndDock-RecentlyOn.txt $P/MacStatusBarAndDock-CrashRecord.txt $P/MacStatusBarAndDock-CrashTweakName.txt
$P/MacStatusBarAndDock-CrashVerdicts.txt $P/MacStatusBarAndDock-CrashStep.txt $P/MacStatusBar-ChoicyBackup.plist
$J/var/log/sshtoggled-engines.log $J/var/log/sshtoggled-engines.log.old $J/var/mobile/.sshtoggle-state
$M/Library/Caches/com.besiktasliseba.macsettings.landscapeicons.plist"
KEPT="$P/com.besiktasliseba.macstatusbaranddock.plist $P/com.besiktasliseba.macstatusbar.plist $P/com.opa334.choicyprefs.plist $J/var/lib/macstatusbaranddock/migrated
$J/var/log/other.log $M/Library/Caches/other.plist"
setup() {
    rm -rf "$W/root"
    for f in $GONE $KEPT; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done
}
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok    $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
for action in remove purge; do
    setup; "$W/postrm" $action; rc=$?
    [ $rc = 0 ] && ok "$action: exit 0" || bad "$action: exit $rc"
    left=""; for f in $GONE; do [ -e "$f" ] && left="$left ${f#$W/root}"; done
    [ -z "$left" ] && ok "$action: every leftover removed" || bad "$action: still there:$left"
    [ ! -d "$S" ] && ok "$action: the helper's empty folder removed" || bad "$action: the helper's folder stays"
    lost=""; for f in $KEPT; do
        case "$f" in *macstatusbaranddock/migrated) [ "$action" = purge ] && continue;; esac
        [ -e "$f" ] || lost="$lost ${f#$W/root}"
    done
    [ -z "$lost" ] && ok "$action: settings and other files kept" || bad "$action: removed too much:$lost"
done
setup; "$W/postrm" purge; [ ! -e "$J/var/lib/macstatusbaranddock" ] && ok "purge: migration record removed" || bad "purge: migration record kept"
setup; echo Aerial > "$S/renamed"; "$W/postrm" remove
[ -f "$S/renamed" ] && ok "remove: a record of engines still renamed is kept (folder stays)" || bad "remove: the renamed record was lost"
setup; "$W/postrm" upgrade 1.0.1; [ -e "$S/ssh-state" ] && [ -e "$P/MacStatusBarAndDock-CrashRecord.txt" ] && ok "upgrade: nothing removed" || bad "upgrade removed files"
setup; "$W/postrm" abort-install; [ -e "$S/ssh-state" ] && ok "abort-install: nothing removed" || bad "abort-install removed files"
echo "postrm: $pass passed, $fail failed"
[ "$fail" = 0 ]
