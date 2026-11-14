#!/bin/bash
# test-ownpackagehold.sh: our own package on dpkg hold (1.8.7.3, audit M11 of 1.8.7.2). A user who keeps MacStatusBar&Dock at its version (apt-mark
# hold, a package manager's "ignore updates") has "Status: hold ok installed" in dpkg's status file. The root helper (macsettings/sshtoggled) looked
# for "install ok installed" with a rule of its own (PackageInstalled), so it took the held package for not installed: every apply gave back the
# engines it kept from loading (several engines loaded together), the iCleaner Pro line switches did nothing, and the switch-off watcher and its
# slow fallback stopped giving back what a switch-off gives back. Our own package is now asked with DpkgState.h's MSBDPackageInstalled
# ("installed", want install or hold), still only once DpkgBusy says no dpkg run is in progress; the want word and the flag are read by the one
# rule MSBDPackageOnDisk uses too (MSBDPackageKeptState).
# 1. the rules, in the code as built (test-dpkgcache.m against common/, or OWN_COMMON: another copy, e.g. the code before the fix);
# 2. site checks on sshtoggled's main.m (OWN_SSH_M: another copy);
# 3. made-to-fail copies: each takes one part of the fix out and must fail.
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
C0=${OWN_COMMON:-../common}; M0=${OWN_SSH_M:-../macsettings/sshtoggled/main.m}
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
lineof() { fn "$1" "$2" | grep -nF -- "$3" | head -1 | cut -d: -f1; }                  # the line of a text in that function (empty: none)

rules() {   # $1 a copy of common/ (DpkgState.h, CrashExplain.h, ...), $2 quiet: test-dpkgcache.m built against it and run; 0 when every check passes
  local d=$W/r$RANDOM; mkdir -p "$d/tools" "$d/x"; cp -R "$1" "$d/common"; cp test-dpkgcache.m "$d/tools/"
  local D="-DDEBUG=1 -DMSBD_GUARD_RECORD=\"$d/x/record.txt\" -DMSBD_GUARD_VERDICTS=\"$d/x/verdicts.txt\" -DMSBD_DPKG_DIR=\"$d/x/dpkg\" -DMSBD_DPKG_STATUS=\"$d/x/status\""
  if ! clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable $D -framework Foundation -o "$d/t" "$d/tools/test-dpkgcache.m" > "$d/build.txt" 2>&1; then
    [ -n "$2" ] || { echo "(test-dpkgcache.m does not build against $1:)"; grep -m 3 'error:' "$d/build.txt"; }; return 1
  fi
  if [ -n "$2" ]; then "$d/t" > /dev/null 2>&1; else "$d/t"; fi
}

checks() {   # $1 main.m, $2 quiet; the number of failed checks
  local M=$1 q=$2 n=0
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  local AE='static void ApplyEngines(NSString *reason) {' CO='static void CheckMacStatusBarOff(NSString *reason) {' \
        EV='static void EvaluateMacStatusBarConfig(NSString *source) {' AL='static void ApplyLines(NSString *why) {' P='"com.besiktasliseba.macstatusbaranddock"'
  c "the engines' apply asks MSBDPackageInstalled for our package (a held one is not given back as \"not installed\")" \
    "fn $M '$AE' | grep -qF 'if (!MSBDPackageInstalled(status, @$P)) { GiveBackAll(@\"Mac Status Bar is not installed\");'"
  c "the slow switch-off fallback asks MSBDPackageInstalled" \
    "fn $M '$CO' | grep -qxF '    if (!MSBDPackageInstalled(status, @$P)) return;'"
  c "the switch-off watcher asks MSBDPackageInstalled" \
    "fn $M '$EV' | grep -qF 'if (statusCache != seen) { seen = statusCache; installed = MSBDPackageInstalled(statusCache, @$P); }'"
  c "the iCleaner Pro line switches ask MSBDPackageInstalled" \
    "fn $M '$AL' | grep -qF 'if (!MSBDPackageInstalled(status, OURPKG) || ChoicyInstalled(status) || !ICleanerInstalled(status)) return;'"
  c "  ... each only once no dpkg run is in progress (DpkgBusy before it: mid-run our package is only unpacked or half-configured)" \
    "for f in '$AE' '$CO' '$EV' '$AL'; do b=\$(lineof $M \"\$f\" 'if (DpkgBusy())'); i=\$(lineof $M \"\$f\" 'MSBDPackageInstalled('); [ -n \"\$b\" ] && [ -n \"\$i\" ] && [ \$b -lt \$i ] || exit 1; done"
  c "our package's dpkg state is asked nowhere else, and with nothing else (4 asks, all MSBDPackageInstalled)" \
    "[ \$(grep -oE '[A-Za-z0-9_]+\\((status|statusCache|DpkgStatus\\(\\)), (@$P|OURPKG)\\)' $M | wc -l) -eq 4 ] \
     && ! grep -oE '[A-Za-z0-9_]+\\((status|statusCache|DpkgStatus\\(\\)), (@$P|OURPKG)\\)' $M | grep -vq '^MSBDPackageInstalled('"
  c "no rule of its own left: the old \"install ok installed\" look only in the debug dry run's old rule (--dry-run-engines --old)" \
    "awk '/^#if DEBUG   \\/\\/ \\(--dry-run-engines --old:/{d=1} d && /^#endif/{d=0; next} !d' $M > \$W/rel && ! grep -qF 'containsString:@\"Status: ' \$W/rel \
     && ! grep -qE '(^|[^A-Za-z0-9_])PackageInstalled(Before141)?\\(' \$W/rel && [ \$(grep -cF 'containsString:@\"Status: install ok installed\"' $M) -eq 1 ] \
     && grep -qF '#define MSBDPackageOnDisk(s, p) (gDryOldRule ? PackageInstalledBefore141((s), (p)) : MSBDPackageOnDisk((s), (p)))' $M"
  return $n
}

rc=0
if [ -z "$OWN_SSH_M" ] || [ -n "$OWN_COMMON" ]; then
  if rules "$C0"; then echo "PASS  the rules (test-dpkgcache.m against $C0)"; else echo "FAIL  the rules (test-dpkgcache.m against $C0)"; rc=1; fi
fi
if [ -z "$OWN_COMMON" ] || [ -n "$OWN_SSH_M" ]; then checks "$M0" || rc=1; fi
if [ -z "$OWN_COMMON$OWN_SSH_M" ]; then
  mtfm() {   # $1 name, $2 a filter (a function, stdin to stdout) on main.m that takes one part of the fix out
    "$2" < "$M0" > "$W/m.m"
    if cmp -s "$W/m.m" "$M0"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if checks "$W/m.m" quiet; then echo "FAIL  made-to-fail ($1): the checks still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  mtfc() {   # $1 name, $2 a filter on DpkgState.h
    rm -rf "$W/c"; cp -R "$C0" "$W/c"; "$2" < "$C0/DpkgState.h" > "$W/c/DpkgState.h"
    if cmp -s "$W/c/DpkgState.h" "$C0/DpkgState.h"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    if rules "$W/c" quiet; then echo "FAIL  made-to-fail ($1): the rules still pass"; rc=1; else echo "PASS  made-to-fail ($1): caught"; fi
  }
  own_rule() { sed -e 's/if (!MSBDPackageInstalled(status, @"com.besiktasliseba.macstatusbaranddock")) { GiveBackAll(/if (!PackageInstalledBefore141(status, @"com.besiktasliseba.macstatusbaranddock")) { GiveBackAll(/'; }
  on_disk() { sed -e 's/installed = MSBDPackageInstalled(statusCache,/installed = MSBDPackageOnDisk(statusCache,/'; }
  busy_after() { awk '/^static void ApplyLines\(NSString \*why\) \{/ {a = 1} a && /if \(DpkgBusy\(\)\)/ {h = $0; next} a && /MSBDPackageInstalled\(status, OURPKG\)/ {print; print h; a = 0; next} {print}'; }
  old_rule_out() { awk '/^#if DEBUG   \/\/ \(--dry-run-engines --old:/ {next} /^#define MSBDPackageOnDisk\(s, p\) \(gDryOldRule/ {print "#if DEBUG"} {print}'; }
  no_hold() { sed -e 's/@\[@"install", @"hold"\]/@[@"install"]/'; }
  half_set_up() { sed -e 's/return \[MSBDPackageKeptState(status, package) isEqualToString:@"installed"\];/return MSBDPackageOnDisk(status, package);/'; }
  old_look() { sed -e 's/return \[MSBDPackageKeptState(status, package) isEqualToString:@"installed"\];/return [MSBDPackageFieldIn(status, package, @"Status") isEqualToString:@"install ok installed"];/'; }
  mtfm "the engines' apply back on a rule of its own" own_rule
  mtfm "the watcher taking a half-set-up package for installed (MSBDPackageOnDisk)" on_disk
  mtfm "the line switches asking before DpkgBusy" busy_after
  mtfm "the old rule outside the debug build" old_rule_out
  mtfc "hold no longer a want word to keep" no_hold
  mtfc "our package counted while still being set up" half_set_up
  mtfc "our package back on the old look (\"install ok installed\" only)" old_look
fi
[ $rc = 0 ] && echo "test-ownpackagehold: all pass" || echo "test-ownpackagehold: FAILED"
exit $rc
