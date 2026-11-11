#!/bin/bash
# test-postrm.sh: runs layout/DEBIAN/postrm on the Mac with /var/jb and /var/mobile pointing into a scratch folder, and checks what it removes and
# what it keeps; then the prerm the same way, with stand-ins for launchctl and the helpers, for what it stops and in which order (the Charge
# Limit's job unloaded first, then charging handed back to iPadOS with msbdcharge --reset, on removal and on an upgrade alike).
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-postrm.XXXXXX")
trap 'rm -rf "$W"' EXIT
J="$W/root/var/jb"; M="$W/root/var/mobile"
sed -e "s#/var/jb#$J#g" -e "s#/var/mobile/Library/Caches#$M/Library/Caches#g" -e "s#/var/mobile/Library/ControlCenter#$M/Library/ControlCenter#g" layout/DEBIAN/postrm > "$W/postrm"; chmod +x "$W/postrm"
S="$J/var/lib/sshtoggled-engines"; P="$J/var/mobile/Library/Preferences"
GONE="$S/msb-off-restored $S/msb-off-alert $S/msb-config $S/ssh-state $S/.ssh-state.Ab12Cd $S/eject-answer $S/.eject-answer.Xy34Zw $S/eject-dryrun
$S/tailspin.plist $S/sleepguard.plist $J/var/log/msbd-sleepguard.log $J/var/log/msbd-sleepguard.log.old
$P/MacStatusBarAndDock-CrashGuard.txt $P/MacStatusBarAndDock-RecentlyOn.txt $P/MacStatusBarAndDock-CrashRecord.txt $P/MacStatusBarAndDock-CrashTweakName.txt
$P/MacStatusBarAndDock-CrashVerdicts.txt $P/MacStatusBarAndDock-CrashStep.txt $P/MacStatusBar-ChoicyBackup.plist
$J/var/log/sshtoggled-engines.log $J/var/log/sshtoggled-engines.log.old $J/var/mobile/.sshtoggle-state
$M/Library/Caches/com.besiktasliseba.macsettings.landscapeicons.plist
$P/com.besiktasliseba.macstatusbar.prewarm.plist $P/com.besiktasliseba.macstatusbar.prewarm.diag.plist $P/MacStatusBarAndDock-PrewarmQuitSet.plist
$P/MacStatusBarAndDock-PrewarmBlockOff.txt $P/MacStatusBarAndDock-PrewarmBlockStarts.txt $P/MacStatusBarAndDock-CCTile.plist $P/MacStatusBarAndDock-CCTile-SSH.plist
$P/MacStatusBarAndDock-PrewarmBlockArmed.txt $P/MacStatusBarAndDock-PrewarmBlockArmed.txt.new $P/MacStatusBarAndDock-NoPrewarmBlock.txt
$J/var/lib/macstatusbaranddock/chargelimit.plist $J/var/log/msbdcharge.log $J/var/log/msbdcharge.log.old"
KEPT="$P/com.besiktasliseba.macstatusbaranddock.plist $P/com.besiktasliseba.macstatusbar.plist $P/com.opa334.choicyprefs.plist $J/var/lib/macstatusbaranddock/migrated
$J/var/log/other.log $M/Library/Caches/other.plist"
setup() {
    rm -rf "$W/root"
    for f in $GONE $KEPT; do mkdir -p "$(dirname "$f")"; echo x > "$f"; done
}
# (18: the Mac panel's own layout of tiles goes with the package, iPadOS's own layout stays)
GONE="$GONE $M/Library/ControlCenter/MacStatusBarAndDock-ControlsIconState.plist $M/Library/ControlCenter/MacStatusBarAndDock-ControlsDesiredIconState.plist"
KEPT="$KEPT $M/Library/ControlCenter/ControlsIconState.plist $M/Library/ControlCenter/ModuleConfiguration.plist"
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
# the prerm
X="$W/prerm-root/var/jb"; mkdir -p "$X/usr/bin" "$X/usr/libexec"
sed "s#/var/jb#$X#g" layout/DEBIAN/prerm > "$W/prerm"; chmod +x "$W/prerm"
for t in usr/bin/launchctl usr/libexec/sshtoggled usr/libexec/msbdcharge; do printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "${t##*/}" "$W/prerm-calls" > "$X/$t"; chmod +x "$X/$t"; done
order() { awk -v a="$1" -v b="$2" 'index($0, a) && !x {x=NR} index($0, b) && !y {y=NR} END{exit !(x && y && x < y)}' "$W/prerm-calls"; }
for action in remove upgrade; do
    : > "$W/prerm-calls"; "$W/prerm" $action 1.7.8; rc=$?
    [ $rc = 0 ] && ok "prerm $action: exit 0" || bad "prerm $action: exit $rc"
    order "launchctl unload $X/Library/LaunchDaemons/com.besiktasliseba.chargelimit.plist" "msbdcharge --reset" &&
        ok "prerm $action: the Charge Limit's job unloaded, then charging handed back (--reset)" || bad "prerm $action: $(tr '\n' ';' < "$W/prerm-calls")"
    grep -q "launchctl unload $X/Library/LaunchDaemons/com.besiktasliseba.sshtoggled.plist" "$W/prerm-calls" && ok "prerm $action: the root helper stopped" || bad "prerm $action: the root helper not stopped"
done
: > "$W/prerm-calls"; "$W/prerm" remove; grep -q "sshtoggled --uninstall" "$W/prerm-calls" && order "msbdcharge --reset" "sshtoggled --uninstall" && ok "prerm remove: our changes given back after the reset" || bad "prerm remove: no --uninstall after the reset"
: > "$W/prerm-calls"; "$W/prerm" upgrade 1.7.8; ! grep -q -- "--uninstall" "$W/prerm-calls" && ok "prerm upgrade: nothing given back" || bad "prerm upgrade ran --uninstall"
rm -f "$X/usr/libexec/msbdcharge"; : > "$W/prerm-calls"; "$W/prerm" remove; rc=$?
[ $rc = 0 ] && ! grep -q msbdcharge "$W/prerm-calls" && ok "prerm remove from a version without the job: exit 0, no reset" || bad "prerm without msbdcharge: exit $rc"
echo "postrm: $pass passed, $fail failed"
[ "$fail" = 0 ]
