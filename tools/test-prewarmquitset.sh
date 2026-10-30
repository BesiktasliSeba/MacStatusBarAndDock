#!/bin/bash
# Mac test of the quit set's file (common/PrewarmQuitSet.h, test-prewarmquitset.m): SpringBoard's write read back as dasd reads it, damaged files,
# and the file stamp that has the set read again when the file changed (iPad 2, palera1n, 29 Oct). 1.7.1: the file is also the block's switch --
# dasd decides from it alone (no notify state SpringBoard publishes at its start: a dasd started before that let its first prewarms through), and
# the loader removes it in a SpringBoard without the status bar part; checked below in the code as built.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tpq" test-prewarmquitset.m
"$W/tpq"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
# the loader is plain C: the header gives it the path, and only the path
printf '#include "%s/../common/PrewarmQuitSet.h"\n#include <stdio.h>\nint main(void) { puts(kMSBDPrewarmQuitSetFile); return 0; }\n' "$PWD" > "$W/c.c"
check "the header in plain C (the loader): the same path, nothing of Foundation" \
  "clang -x c -Wall -Werror -o '$W/c' '$W/c.c' && [ \"\$('$W/c')\" = /var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-PrewarmQuitSet.plist ]"
check "dasd: no notify state decides any more (no prewarm.enabled, no BlockOn)" \
  "! grep -n 'prewarm.enabled\|BlockOn\|gEnabledToken' ../prewarmblock/PrewarmBlock.x"
check "dasd: refused only for an app in the file's set; the file's absence logged as the block off" \
  "grep -q 'if (QuitSetContains(bundleID, &kept))' ../prewarmblock/PrewarmBlock.x && grep -q 'block off: no quit set kept' ../prewarmblock/PrewarmBlock.x"
check "dasd: the file is looked at on every prewarm (its stamp), so a file that went is an empty set at once" \
  "awk '/^static BOOL QuitSetContains/{f=1} f&&/stat\\(kMSBDPrewarmQuitSetFile/{print \"ok\"; exit}' ../prewarmblock/PrewarmBlock.x | grep -q ok"
check "SpringBoard: no notify state published (the file is the switch)" \
  "! grep -n 'prewarm.enabled\|MSB_PREWARM_ENABLED' ../statusbar/StatusBar.x"
check "SpringBoard: the file is written at every start of the status bar part, and goes with Use Stock Status Bar" \
  "awk '/^static void DMPrewarmQuitLoad/{f=1} f&&/DMPrewarmQuitWriteFile\\(\\)/{print \"ok\"; exit}' ../statusbar/StatusBar.x | grep -q ok && awk '/^static void DMPrewarmBlockOff/{f=1} f&&/unlink\\(kMSBDPrewarmQuitSetFile\\)/{print \"ok\"; exit}' ../statusbar/StatusBar.x | grep -q ok && grep -q 'DMPrewarmBlockOff(@\"Use Stock Status Bar\")' ../statusbar/StatusBar.x"
check "SpringBoard: Mac Status Bar switched off its old way (tweakEnabled) turns the block off too, before it returns (the file would outlive reboots)" \
  "awk '/if \\(!enabled\\) \\{   \\/\\/ switched off/{f=1} f&&/DMPrewarmBlockOff\\(@\"Mac Status Bar is switched off\"\\)/{ok=1} f&&/return;/{print ok ? \"ok\" : \"no\"; exit}' ../statusbar/StatusBar.x | grep -q ok"
check "the loader: the file removed in a SpringBoard whose status bar part did not load (MacStatusBar line only)" \
  "awk '/^#if !MSBD_LINE_DOCK/{f=1} /^#else|^#endif/{f=0} f&&/if \\(\\(kind & kSpringBoard\\) && !coreLoaded\\) quitSetGone = unlink\\(kMSBDPrewarmQuitSetFile\\) == 0;/{print \"ok\"}' ../loader/Loader.c | grep -q ok"
check "the loader: coreLoaded is set only by a loaded MacStatusBarCore" \
  "grep -q 'if (dlopen(lib, RTLD_NOW)) { loaded++; if (strcmp(kPayloads\\[i\\].name, \"MacStatusBarCore\") == 0) coreLoaded = 1; }' ../loader/Loader.c"
# the postinst's first copy of the file (code review, 30 Oct): only for a SpringBoard that keeps a set -- the helper answers with MSBDPrewarmQuitSetKept
# (tested above) from the switches as SpringBoard reads them
check "the helper: --quit-set-kept answers from tweakEnabled and stockStatusBar of our domain (as mobile) and whether the tweak runs" \
  "awk '/^static BOOL QuitSetKept\\(void\\) \\{/{f=1} f&&/CFPreferencesCopyValue\\(CFSTR\\(\"tweakEnabled\"\\), d, CFSTR\\(\"mobile\"\\)/{e=1} f&&/CFPreferencesCopyValue\\(CFSTR\\(\"stockStatusBar\"\\), d, CFSTR\\(\"mobile\"\\)/{s=1} f&&/MSBDPrewarmQuitSetKept\\(\\(__bridge id\\)e, \\(__bridge id\\)s, TweakMeantToRun\\(\\)\\)/{k=1} f&&/^}/{print (e && s && k) ? \"ok\" : \"no\"; exit}' ../macsettings/sshtoggled/main.m | grep -q ok && grep -q 'CFStringRef d = CFSTR(\"com.besiktasliseba.macstatusbar\");' ../macsettings/sshtoggled/main.m && grep -q 'strcmp(argv\\[1\\], \"--quit-set-kept\") == 0) return MSBDIsIPad() && QuitSetKept() ? 0 : 1;' ../macsettings/sshtoggled/main.m"
check "  ... read the way SpringBoard reads them (tweakEnabled: none or YES on; stockStatusBar: YES on)" \
  "grep -q 'BOOL enabled = !v || (CFGetTypeID(v) == CFBooleanGetTypeID() && CFBooleanGetValue(v));' ../statusbar/StatusBar.x && awk '/^static BOOL DMStockBarSwitch\\(void\\)/{f=1} f&&/CFSTR\\(\"stockStatusBar\"\\)/{k=1} f&&/BOOL on = v && CFGetTypeID\\(v\\) == CFBooleanGetTypeID\\(\\) && CFBooleanGetValue\\(v\\);/{o=1} f&&/^}/{print (k && o) ? \"ok\" : \"no\"; exit}' ../statusbar/StatusBar.x | grep -q ok"
check "the postinst: the first copy only when the helper says a set is kept, and a file for a SpringBoard that keeps none goes" \
  "awk '/kept=2; \\[ -x \"\\\$H\" \\] && \\{ \"\\\$H\" --quit-set-kept; kept=\\\$\\?; \\}/{a=1} a&&/if \\[ \"\\\$kept\" = 0 \\]; then/{b=1} b&&/if \\[ ! -e \"\\\$QS\" \\] && \\[ -f \"\\\$QP\" \\]; then cp \"\\\$QP\" \"\\\$QS\"/{c=1} c&&/elif \\[ \"\\\$kept\" = 1 \\]; then rm -f \"\\\$QS\"; fi/{print \"ok\"; exit}' ../layout/DEBIAN/postinst | grep -q ok"
[ $fails = 0 ] && echo "test-prewarmquitset: switch wiring checks pass" || { echo "test-prewarmquitset: switch wiring checks FAILED"; exit 1; }
