#!/bin/bash
# test-preinst.sh: runs layout/DEBIAN/preinst on the Mac against sample /var/lib/dpkg/status contents, one per dependency state, and checks that it
# goes on or refuses as it should. dpkg is not installed on the Mac, so a small stand-in answers `dpkg-query -W -f='${db:Status-Status}' <pkg>` from
# the sample status file (the third word of the package's "Status:" line; nothing and exit 1 for an unknown package, as dpkg-query does). The
# preinst runs unchanged except that /var/jb points into a scratch folder.
set -u
cd "$(dirname "$0")/.."
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-preinst.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root/var/jb/usr/bin" "$W/root/var/jb/var/lib" "$W/root/var/jb/var/log/apt"
cat > "$W/root/var/jb/usr/bin/dpkg-query" <<'EOF'
#!/bin/sh
# stand-in: dpkg-query -W -f='${db:Status-Status}' <pkg>, read from $MSBD_STATUS
pkg=""; for a in "$@"; do pkg="$a"; done
out=$(awk -v p="$pkg" '/^Package: / { name=substr($0,10) } /^Status: / && name==p { print $4; found=1 } END { exit found ? 0 : 1 }' "$MSBD_STATUS")
rc=$?
[ $rc -ne 0 ] && { echo "dpkg-query: no packages found matching $pkg" >&2; exit 1; }
printf %s "$out"
EOF
chmod +x "$W/root/var/jb/usr/bin/dpkg-query"
sed "s#/var/jb#$W/root/var/jb#g" layout/DEBIAN/preinst > "$W/preinst"
chmod +x "$W/preinst"

stanza() {   # stanza <package> <want> <flag> <state>
    printf 'Package: %s\nStatus: %s %s %s\nVersion: 1.0\nArchitecture: iphoneos-arm64\n\n' "$1" "$2" "$3" "$4"
}
pass=0; fail=0
check() {   # check <name> <expected exit> <status file contents>
    printf %s "$3" > "$W/status"
    rm -rf "$W/root/var/jb/var/lib/macstatusbaranddock"
    out=$(MSBD_STATUS="$W/status" "$W/preinst" install 2>&1); rc=$?
    if [ "$rc" = "$2" ]; then pass=$((pass+1)); printf 'ok    %-58s exit %s\n' "$1" "$rc"
    else fail=$((fail+1)); printf 'FAIL  %-58s exit %s (expected %s): %s\n' "$1" "$rc" "$2" "$out"; fi
}
ALT=$(stanza com.opa334.altlist install ok installed)
CHO=$(stanza com.opa334.choicy install ok installed)
# Choicy in every dpkg state (AltList installed)
for st in installed unpacked half-configured triggers-awaited triggers-pending; do
    check "Choicy $st -> goes on" 0 "$ALT
$(stanza com.opa334.choicy install ok $st)"
done
for st in half-installed config-files not-installed; do
    check "Choicy $st -> refused" 1 "$ALT
$(stanza com.opa334.choicy install ok $st)"
done
check "Choicy absent from the status file -> refused" 1 "$ALT"
check "no status file entries at all -> refused" 1 ""
# iCleaner Pro instead of Choicy (both package names)
check "iCleaner Pro (exile90) unpacked -> goes on" 0 "$ALT
$(stanza com.exile90.icleanerpro install ok unpacked)"
check "iCleaner Pro (cypwn) installed -> goes on" 0 "$ALT
$(stanza xyz.cypwn.icleanerpro install ok installed)"
check "Choicy config-files, iCleaner Pro installed -> goes on" 0 "$ALT
$(stanza com.opa334.choicy deinstall ok config-files)
$(stanza xyz.cypwn.icleanerpro install ok installed)"
# AltList (finding 9)
for st in installed unpacked half-configured triggers-awaited triggers-pending; do
    check "AltList $st -> goes on" 0 "$CHO
$(stanza com.opa334.altlist install ok $st)"
done
for st in half-installed config-files; do
    check "AltList $st -> refused" 1 "$CHO
$(stanza com.opa334.altlist install ok $st)"
done
check "AltList absent -> refused" 1 "$CHO"
# apt's usual order for a first install from Sileo: Choicy and AltList unpacked in this run, not configured yet
check "same apt run: Choicy + AltList both unpacked -> goes on" 0 "$(stanza com.opa334.altlist install ok unpacked)
$(stanza com.opa334.choicy install ok unpacked)"
# an upgrade takes the same path
printf %s "$ALT
$CHO" > "$W/status"
MSBD_STATUS="$W/status" "$W/preinst" upgrade 1.0.0 >/dev/null 2>&1 && { pass=$((pass+1)); echo "ok    upgrade with both installed -> goes on"; } || { fail=$((fail+1)); echo "FAIL  upgrade with both installed"; }
# a refusal changes nothing (no state folder created)
printf %s "$ALT" > "$W/status"; rm -rf "$W/root/var/jb/var/lib/macstatusbaranddock"
MSBD_STATUS="$W/status" "$W/preinst" install >/dev/null 2>&1
[ ! -e "$W/root/var/jb/var/lib/macstatusbaranddock" ] && { pass=$((pass+1)); echo "ok    a refusal writes nothing"; } || { fail=$((fail+1)); echo "FAIL  a refusal wrote the state folder"; }
echo "preinst: $pass passed, $fail failed"
[ "$fail" = 0 ]
