#!/bin/bash
# Mac test of a removal's cfprefsd domains (1.7.8, 1.7.7 fix-round finding): the prewarm quit set's domain and the debug builds' prewarm diagnostics
# are emptied THROUGH cfprefsd, as mobile, by the prerm's helper (common/PrefsForget.h, test-prefsforget.m against the Mac's own cfprefsd), not only
# rm'd by the postrm -- then the wiring in the helper and the scripts.
set -e
cd "$(dirname "$0")"
# The test's scratch domain is this script's own, and goes again at the end, also after a failure: defaults delete makes cfprefsd write the emptied
# domain now (it did a few seconds after the test ended, an empty plist each run), and the file is removed after it.
PD=com.besiktasliseba.msbdtest.prefsforget.$$
PF="$HOME/Library/Preferences/$PD.plist"
cleanpf() { defaults delete "$PD" >/dev/null 2>&1 || true; rm -f "$PF"; }
W=$(mktemp -d); trap 'rm -rf "$W"; cleanpf' EXIT
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -o "$W/tpf" test-prefsforget.m
if ! "$W/tpf" "$PD" > "$W/out"; then cat "$W/out"; exit 1; fi
cat "$W/out"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
cleanpf; python3 -c 'import time; time.sleep(3)'   # (cfprefsd's late write came about 2.5 s after the test)
check "the scratch domain is this script's own and leaves no file in ~/Library/Preferences, cfprefsd's late write of the emptied domain included" \
  "grep -qx \"scratch domain: $PD\" \"$W/out\" && [ ! -e \"$PF\" ]"
cleanpf
H=../macsettings/sshtoggled/main.m; R=../layout/DEBIAN/postrm; Q=../layout/DEBIAN/prerm
check "the removal (the prerm's --uninstall) empties the prewarm domains through cfprefsd" \
  "awk '/^static void Uninstall\(void\) \{/{f=1} f&&/ForgetPrewarmPrefs\(@\"removal\"\);/{print \"ok\"; exit}' $H | grep -q ok && grep -q 'sshtoggled --uninstall' $Q"
check "  ... in a child of the helper that is mobile from its first line (its group list, group and user), before any preference is touched" \
  "awk '/^static int ForgetPrewarmPrefsAsMobile\(const char \*testDomain\) \{/{f=1} f&&/setgroups\(1, &g\) != 0 \|\| setgid\(501\) != 0 \|\| setuid\(501\) != 0/{s=1} f&&s&&/MSBDForgetPrefsDomain\(d, &l\)/{print \"ok\"; exit}' $H | grep -q ok \
   && grep -q 'if (argc > 1 && strcmp(argv\[1\], \"--forget-prewarm-prefs\") == 0) return ForgetPrewarmPrefsAsMobile(argc > 2 ? argv\[2\] : NULL);' $H"
check "  ... the child is dispatched first in main, before the iPad check or anything that reads preferences as root" \
  "awk '/^int main\(int argc, char \*\*argv\) \{/{f=1} f&&/--forget-prewarm-prefs/{print \"ok\"; exit} f&&/MSBDIsIPad\(\)/{exit}' $H | grep -q ok"
check "  ... as the domains are used: the current user (mobile), never root's view of mobile's" \
  "grep -q 'CFPreferencesSetMultiple(NULL, keys, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' ../common/PrefsForget.h && ! awk '/^static int ForgetPrewarmPrefsAsMobile/{f=1} f&&/CFSTR\(\"mobile\"\)/{print \"bad\"} f&&/^}/{exit}' $H | grep -q bad"
check "  ... a time limit: a package removal never hangs on it" \
  "awk '/^static void ForgetPrewarmPrefs\(NSString \*why\) \{/{f=1} f&&/for \(int i = 0; i < 100 && \(done = waitpid\(pid, &status, WNOHANG\)\) == 0; i\+\+\) usleep\(50000\);/{print \"ok\"; exit}' $H | grep -q ok"
check "  ... a scratch domain instead only in a debug build, and only one of ours for tests (a release build always empties the two real domains)" \
  "awk '/^static int ForgetPrewarmPrefsAsMobile/{f=1} f&&/^#if DEBUG\$/{d=1} f&&d&&/strncmp\(testDomain, \"com.besiktasliseba.msbdtest.\", 28\) == 0\) n = 1; else testDomain = NULL;/{a=1} f&&a&&/^#else\$/{e=1} f&&e&&/^    testDomain = NULL;\$/{print \"ok\"; exit}' $H | grep -q ok"
check "the helper's domains are exactly the cfprefsd domains whose files the postrm removes (one list, nothing forgotten)" \
  "for d in \$(grep -o 'kPrewarmPrefDomains\[\] = {[^}]*}' $H | grep -o '\"com[^\"]*\"' | tr -d '\"'); do grep -q \"\\\$P/\$d.plist\" $R || exit 1; done; \
   [ \$(grep -o 'kPrewarmPrefDomains\[\] = {[^}]*}' $H | grep -o '\"com[^\"]*\"' | wc -l) = 2 ]"
check "the postrm still removes their files (a removal without the helper), and says why both" \
  "grep -q 'emptied them through it already' $R && grep -q 'com.besiktasliseba.macstatusbar.prewarm.plist' $R"
[ $fails = 0 ] && echo "test-prefsforget: site checks pass" || { echo "test-prefsforget: site checks FAILED"; exit 1; }
