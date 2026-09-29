#!/bin/bash
# verify-release.sh <deb>: the release gate. Unpacks the package and checks that it is a release build of THIS tree's current commit, complete, and
# free of test machinery. Prints every check and ends with "RESULT: GO" (exit 0) or "RESULT: NO-GO" (exit 1). sileo-repo/update-repo.sh runs it too.
#   MSBD_TREE=<folder>  the source tree to compare with (default: the tree this script is in)
#   KEEP=1              keep the unpacked copy (its folder is printed)
set -u
DEB="${1:?usage: verify-release.sh <path-to-the-.deb>}"
case "$DEB" in /*) ;; *) DEB="$PWD/$DEB";; esac
TREE="${MSBD_TREE:-$(cd "$(dirname "$0")/.." && pwd)}"
W=$(mktemp -d "${TMPDIR:-/tmp}/msbd-verify.XXXXXX")
[ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$W"' EXIT
problems=0
bad() { problems=$((problems+1)); echo "  NO-GO: $*"; }
ok() { echo "  ok: $*"; }
[ -f "$DEB" ] || { echo "not a file: $DEB"; echo "RESULT: NO-GO"; exit 1; }
cd "$W" && ar x "$DEB" && mkdir d c && tar -xf data.tar.* -C d && tar -xf control.tar.* -C c || { echo "cannot unpack $DEB"; echo "RESULT: NO-GO"; exit 1; }
field() { sed -n "s/^$1: //p" "$2" | head -1; }

echo "== package and version"
V=$(field Version c/control); TV=$(field Version "$TREE/control")
if [[ "$V" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then ok "Version $V is a plain release version"; else bad "Version '$V' is not a release version (a '+debug' or '-N' build: build with FINALPACKAGE=1)"; fi
case "$(basename "$DEB")" in *+debug*) bad "the file name says debug build";; esac
[ "$V" = "$TV" ] && ok "Version matches the tree's control ($TV)" || bad "Version $V, but the tree's control says $TV"
for f in Package Name Architecture Description Maintainer Author Section Depends Conflicts Replaces Provides; do
    [ "$(field $f c/control)" = "$(field $f "$TREE/control")" ] || bad "control field $f differs from the tree's control"
done
ok "control fields compared with the tree's control"

echo "== built from this tree's current commit"
HEAD=$(git -C "$TREE" rev-parse HEAD 2>/dev/null)
BI=d/var/jb/usr/lib/MacStatusBarAndDock/BuildInfo.txt
if [ ! -f "$BI" ]; then
    bad "no BuildInfo.txt in the package: it was built before build stamping existed (stale) -- build again with FINALPACKAGE=1"
else
    C=$(sed -n 's/^commit //p' "$BI")
    [ -n "$HEAD" ] && [ "$C" = "$HEAD" ] && ok "built from $HEAD (the tree's HEAD)" || bad "built from ${C:-?}, but the tree is at ${HEAD:-?} (stale package: build again with FINALPACKAGE=1)"
    [ "$(sed -n 's/^dirty //p' "$BI")" = 0 ] && ok "built from a clean tree" || bad "built with uncommitted changes in the tree (commit first, then build)"
    [ "$(sed -n 's/^debug //p' "$BI")" = 0 ] && ok "not a debug build" || bad "a DEBUG build (test code compiled in): build with FINALPACKAGE=1"
fi
[ -z "$(git -C "$TREE" status --porcelain --untracked-files=no 2>/dev/null)" ] || echo "  note: the tree has uncommitted changes now (the package is compared with HEAD)"

echo "== maintainer scripts = the tree's layout/DEBIAN at HEAD"
for s in preinst postinst prerm postrm; do
    if [ ! -f "c/$s" ]; then bad "$s missing"
    elif git -C "$TREE" show "HEAD:layout/DEBIAN/$s" 2>/dev/null | cmp -s - "c/$s"; then ok "$s"
    else bad "$s differs from HEAD's layout/DEBIAN/$s (stale package)"; fi
done

echo "== every part is there"
L=d/var/jb/Library/MobileSubstrate/DynamicLibraries; P=d/var/jb/usr/lib/MacStatusBarAndDock
need="$L/MacStatusBar.dylib $L/MacStatusBar.plist $L/MacDock.dylib $L/MacDock.plist $P/MacCrashBlame.dylib $P/MacCrashNotice.dylib $P/CrashMap.txt
      d/var/jb/usr/libexec/sshtoggled d/var/jb/Library/LaunchDaemons/com.besiktasliseba.sshtoggled.plist"
for n in $(sed -n '/^PAYLOADS *=/,/^$/p' "$TREE/Makefile" | sed 's/PAYLOADS *=//; s/\\//g'); do need="$need $P/$n.dylib"; done
missing=""; for f in $need; do [ -s "$f" ] || missing="$missing ${f#d}"; done
[ -z "$missing" ] && ok "$(echo $need | wc -w | tr -d ' ') files" || bad "missing or empty:$missing"
extra=$(ls "$L" | grep -v -E '^(MacStatusBar|MacDock)\.(dylib|plist)$')
[ -z "$extra" ] || bad "unexpected files in the tweak folder: $extra"
# the crash guard's map must belong to THESE binaries (a map from another build would blame the wrong features)
if [ -s "$P/CrashMap.txt" ]; then
    mapok=1
    for img in MacStatusBarCore DockMagnification; do
        for arch in arm64 arm64e; do
            want=$(dwarfdump --uuid --arch "$arch" "$P/$img.dylib" 2>/dev/null | awk '{print tolower($2)}')
            grep -q "^U $img $want $arch\$" "$P/CrashMap.txt" || { mapok=0; bad "CrashMap.txt has no function map for $img ($arch, UUID ${want:-?})"; }
        done
    done
    [ $mapok = 1 ] && ok "CrashMap.txt matches the shipped MacStatusBarCore and DockMagnification (arm64 + arm64e)"
fi

echo "== test machinery left in the binaries"
# Every /tmp path and debug-only name. A release build must have none, except these, which are real release features (allowed, only in
# MacStatusBarCore.dylib): /tmp/macstatusbar-restore-guard, /tmp/macstatusbar-menuwindow-guard, /tmp/macstatusbar-aerial5-probation -- the
# status bar's own crash-loop guards (they must live in /tmp so a reboot clears them; StatusBar.x).
PAT='unlockpass_|tapsys|dragsys|devorient_|memdump_|mpdump_|a5trace_|keys_|macstatusbar-trigger|macstatusbar-debug|/tmp/|dockmag\.log|macsettings-debug|tabmute-debug|brightnesskey-debug|msb-engine-notinstalled|sshtoggled-pretend|pretend-nochoicy|macpointer\.(cmd|pagereq)|appbridge\.(dumpcls|dumpctrl|keycmds|testnotif|typetest)|fakeversion|fakemodel|fakecrash|--dry-run-choicy|--dpkg-busy|appstate\.|\[trigger\]|\[debug\]|skiplock|DM_LOCK_BYPASS'
ALLOW_CORE='^/tmp/macstatusbar-(restore-guard|menuwindow-guard|aerial5-probation)$'
while IFS= read -r f; do
    file "$f" | grep -q Mach-O || continue
    printf "  %9d  %-66s %s\n" "$(stat -f %z "$f")" "${f#d/}" "$(lipo -archs "$f" 2>/dev/null)"
    hits=$(strings -a "$f" | grep -E "$PAT" | sort -u)
    [ "$(basename "$f")" = MacStatusBarCore.dylib ] && hits=$(echo "$hits" | grep -v -E "$ALLOW_CORE")
    [ -n "$hits" ] && while IFS= read -r h; do bad "${f##*/}: $h"; done <<< "$hits"
done < <(find d -type f | sort)

echo "== release features (tools/verify-release-features.sh)"
# every DM_FEATURE_MARK in the source must be in these binaries: a feature compiled only into debug builds never ships silently (1.1.0/1.1.1)
fout=$(MSBD_TREE="$TREE" bash "$TREE/tools/verify-release-features.sh" d 2>&1); frc=$?
echo "$fout" | grep -v '^FEATURES:' | sed 's/^  */  /'
[ $frc = 0 ] && ok "$(echo "$fout" | grep '^FEATURES:')" || bad "feature markers missing from the release binaries (listed above)"

echo "== personal name"
# Allowed: the old package IDs (com.kaan.*) in the control's Conflicts/Replaces/Provides and in the maintainer scripts (the migration from the old
# packages), and the string "kaan." in sshtoggled (MigOldPrefix: the old preference domains' prefix, only read for the one-time migration).
for f in c/*; do
    left=$(sed -E 's/com\.kaan\.[a-z]+//g' "$f" | grep -i -n kaan)
    [ -z "$left" ] || bad "${f#c/}: $left"
done
while IFS= read -r f; do
    if [ "$f" = d/var/jb/usr/libexec/sshtoggled ]; then left=$(strings -a "$f" | grep -i kaan | grep -v -x 'kaan\.')
    else left="found"; fi
    [ -z "$left" ] || bad "${f#d/}: $(echo $left | head -c 200)"
done < <(grep -r -a -i -l kaan d)
ok "personal-name scan done"

echo
if [ $problems = 0 ]; then echo "RESULT: GO ($(basename "$DEB"), commit ${HEAD:0:7})"; exit 0
else echo "RESULT: NO-GO ($problems problem(s))"; exit 1; fi
