#!/bin/bash
# test-prerm.sh: runs layout/DEBIAN/prerm on the Mac with /var/jb pointing into a scratch folder, launchctl and the root helper as stubs that write
# down how they were called, for every way dpkg runs a prerm, and checks what it asks: the helper stopped first; Keep Tailspin Off's false given
# back on every way out of the version (an upgrade or a downgrade too, so an older version never inherits it: code review), never on
# failed-upgrade (the helper on disk is the old version's then, which would take an unknown flag for its daemon start); the full give-back only
# on removal. Then dpkg's order for 1.7.9 -> an older version -> its removal, with the helper's give-back acted out on a stand-in for com.apple.da.
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-prerm.XXXXXX")
trap 'rm -rf "$W"' EXIT
J="$W/root/var/jb"
sed -e "s#/var/jb#$J#g" layout/DEBIAN/prerm > "$W/prerm"; chmod +x "$W/prerm"
sed -e "s#/var/jb#$J#g" layout/DEBIAN/postrm > "$W/postrm"; chmod +x "$W/postrm"
CALLS="$W/calls"; DA="$W/da-key"; STATE="$J/var/lib/sshtoggled-engines/tailspin.plist"
setup() {
    rm -rf "$W/root"; : > "$CALLS"
    mkdir -p "$J/usr/bin" "$J/usr/libexec" "$J/var/lib/sshtoggled-engines"
    printf '#!/bin/sh\necho "launchctl $*" >> "%s"\n' "$CALLS" > "$J/usr/bin/launchctl"
    # the 1.7.9 helper: --tailspin-giveback / --uninstall take our false away when the state says it is ours (TailspinDaemon.h TGGiveBack)
    printf '#!/bin/sh\necho "helper $*" >> "%s"\ncase "$1" in --tailspin-giveback|--uninstall) [ -f "%s" ] && grep -q owned "%s" && rm -f "%s"; rm -f "%s" ;; esac\n' "$CALLS" "$STATE" "$STATE" "$DA" "$STATE" > "$J/usr/libexec/sshtoggled"
    chmod +x "$J/usr/bin/launchctl" "$J/usr/libexec/sshtoggled"
    echo false > "$DA"; echo owned > "$STATE"   # (the 2 GB iPad: the helper wrote the false, ours)
}
pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok    $1"; }
bad() { fail=$((fail+1)); echo "FAIL  $1"; }
for action in upgrade remove purge deconfigure; do
    setup; "$W/prerm" $action 1.7.8.2 >/dev/null 2>&1; rc=$?
    [ $rc = 0 ] && ok "$action: exit 0" || bad "$action: exit $rc"
    first=$(head -1 "$CALLS")
    case "$first" in "launchctl unload "*com.besiktasliseba.sshtoggled.plist) ok "$action: the helper is stopped first" ;; *) bad "$action: first call was: $first" ;; esac
    grep -q "^helper --tailspin-giveback $action\$" "$CALLS" && ok "$action: Keep Tailspin Off's false given back" || bad "$action: no tailspin give-back"
    [ ! -e "$DA" ] && [ ! -e "$STATE" ] && ok "$action: com.apple.da without our false, and no state file left" || bad "$action: our false or the state file stays"
    case "$action" in
        remove|purge) grep -q '^helper --uninstall$' "$CALLS" && ok "$action: everything else given back (--uninstall)" || bad "$action: no --uninstall" ;;
        *) ! grep -q -- '--uninstall' "$CALLS" && ok "$action: no full give-back (only a removal does that)" || bad "$action: --uninstall on $action" ;;
    esac
done
setup; "$W/prerm" failed-upgrade 1.7.9 >/dev/null 2>&1
! grep -q '^helper' "$CALLS" && ok "failed-upgrade: the helper is not run (the one on disk is the old version's)" || bad "failed-upgrade ran the helper: $(grep '^helper' "$CALLS" | tr '\n' ' ')"
[ -e "$DA" ] && ok "failed-upgrade: nothing given back (the old version's postinst abort-upgrade starts its helper again)" || bad "failed-upgrade: the false went"
setup; echo someone-else > "$STATE"; "$W/prerm" upgrade 1.7.8.2 >/dev/null 2>&1
[ -e "$DA" ] && ok "upgrade: a false that is not ours stays (only our record's)" || bad "upgrade: someone else's false was taken"

# dpkg's order for a downgrade (1.7.9 -> 1.7.8.2) and then the removal of 1.7.8.2: 1.7.9's prerm upgrade, 1.7.8.2's preinst, the unpack,
# 1.7.9's postrm upgrade, 1.7.8.2's postinst configure (its helper knows nothing of the key); then 1.7.8.2's prerm remove, files out, its postrm remove
setup
"$W/prerm" upgrade 1.7.8.2 >/dev/null 2>&1
"$W/postrm" upgrade 1.7.8.2 >/dev/null 2>&1
printf '#!/bin/sh\necho "old helper $*" >> "%s"\n' "$CALLS" > "$J/usr/libexec/sshtoggled"; chmod +x "$J/usr/libexec/sshtoggled"   # (1.7.8.2's: no tailspin code)
[ ! -e "$DA" ] && ok "downgrade: after 1.7.9's prerm and postrm, com.apple.da has no false of ours (the older version never knew it)" || bad "downgrade: our false stays"
[ ! -e "$STATE" ] && ok "downgrade: no tailspin.plist left for the older version, which would never take it away" || bad "downgrade: tailspin.plist stays"
# (1.7.8.2's prerm as published; its postrm knows nothing of tailspin.plist: what is left then stays for good)
cat > "$W/old-prerm" <<OLD
#!/bin/sh
$J/usr/bin/launchctl unload $J/Library/LaunchDaemons/com.besiktasliseba.sshtoggled.plist 2>/dev/null
if [ "\$1" = "remove" ] || [ "\$1" = "purge" ]; then
    [ -x $J/usr/libexec/sshtoggled ] && $J/usr/libexec/sshtoggled --uninstall
fi
exit 0
OLD
chmod +x "$W/old-prerm"
"$W/old-prerm" remove >/dev/null 2>&1; rm -f "$J/usr/libexec/sshtoggled" "$J/usr/bin/launchctl"
grep -q '^old helper --uninstall$' "$CALLS" && ok "then 1.7.8.2 removed: its own prerm ran its own helper's --uninstall (which knows nothing of the key)" || bad "1.7.8.2's prerm did not run its helper"
[ ! -e "$DA" ] && [ ! -e "$STATE" ] && ok "  ... and after it iPadOS's default is in com.apple.da, no state file of ours" || bad "after the removal: the false or the state file stays"
echo "prerm: $pass passed, $fail failed"
[ "$fail" = 0 ]
