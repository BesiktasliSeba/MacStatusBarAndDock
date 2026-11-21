#!/bin/bash
# Mac test of the LNPopupController race guard (common/PopupGuard.h; appbridge/AppBridge.x MABInstallPopupGuard) -- 1.8.8.1 B68, Zebra's queue in
# a window. The library's 3-argument present only forwards to its designated present (openPopup:); Zebra calls the designated one, Sileo the
# 3-argument one. The guard (present/dismiss of the bar one at a time per controller) now takes the designated present, so Zebra's calls are
# guarded as Sileo's were. test-popupguard.m: the scenarios run MacAppBridge's guard section as cut out of AppBridge.x (TREE=<another tree> to
# run them on that tree's AppBridge.x), the units PopupGuard.h's own rules; test-popupguard-loader.c what the loader gives a recovery app; then
# the wiring, and made-to-fail copies of the header and of the loader.
# Usage: test-popupguard.sh            (this tree)
#        TREE=/path/to/tree test-popupguard.sh   (the scenarios and the loader test on that tree: before the fix, Zebra's and the loader's fail)
set -e
cd "$(dirname "$0")"
T=$(cd "${TREE:-..}" && pwd)
H=$(cd .. && pwd)/common/PopupGuard.h
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
CC="clang -fobjc-arc -fmodules -Wall -Wno-unused-function -Wno-unused-variable -framework Foundation"

# the guard section of AppBridge.x (TREE's): from its header to the next section's
cut_section() {
  awk '/^\/\/ ===== LNPopupController race guard/{p=1} /^\/\/ ===== Messages entry bar/{p=0} p' "$1/appbridge/AppBridge.x" \
    | sed "s#\#include \"../common/PopupGuard.h\"#\#include \"$1/common/PopupGuard.h\"#" > "$2"
}
cut_section "$T" "$W/guard.inc"
[ -s "$W/guard.inc" ] || { echo "FAIL  no guard section in $T/appbridge/AppBridge.x"; exit 1; }
echo "== scenarios: $T/appbridge/AppBridge.x's guard"
$CC -DGUARD_INC="\"$W/guard.inc\"" -o "$W/scen" test-popupguard.m && "$W/scen" || fails=1
echo "== the stand-in with no library class in the process (no guard installed): the race must show (else the scenarios prove nothing)"
if out=$("$W/scen" nolib 2>&1); then echo "$out" | sed 's/^/   /'; echo "FAIL  with no guard the stand-in did not show the race"; fails=1
else
  echo "$out" | grep -E 'Zebra \(designated present\)|Sileo \(3-argument present\)' | sed 's/^/   /'
  check "with no guard: Zebra's dismiss then present ends with the bar hidden (the race)" "echo \"\$out\" | grep -q '^FAIL  no library class (no guard), Zebra (designated present)'"
  check "with no guard: Sileo's ends hidden too" "echo \"\$out\" | grep -q '^FAIL  no library class (no guard), Sileo (3-argument present)'"
fi
echo "== loader: what a recovery app gets ($T/loader/Loader.c)"
# the loader's enum, its MacStatusBar parts table, MSBDRecoveryApp to MSBDRecoveryKind, cut out of a Loader.c
loader_inc() {
  { echo '#include <dlfcn.h>'; echo '#define MSBD_LINE_DOCK 0'
    awk '/^enum \{ kSpringBoard = 1/{p=1} p{print} /^typedef struct \{ const char \*name; unsigned where; \} Payload;/{exit}' "$1"
    awk '/^\/\/ MacStatusBar: everything except the Dock/{p=1} p{print} p && /^\};/{exit}' "$1"
    awk '/^static int MSBDRecoveryApp\(const char \*path\) \{/{p=1} p{print} /^static unsigned MSBDRecoveryKind\(/{k=1} k && /^\}/{exit}' "$1"
  } > "$2"
}
loader_inc "$T/loader/Loader.c" "$W/loader.inc"
if clang -Wall -Wno-unused-function -DLOADER_INC="\"$W/loader.inc\"" -o "$W/ldr" test-popupguard-loader.c 2> "$W/ldr-cc.txt"; then "$W/ldr" || fails=1
else echo "FAIL  the loader's recovery app decision did not build from $T (no MSBDRecoveryKind: every recovery app gets nothing)"; head -3 "$W/ldr-cc.txt" | sed 's/^/   /'; fails=1; fi
[ -n "$TREE" ] && { [ $fails = 0 ] && echo "test-popupguard (TREE=$T scenarios): all checks pass" || { echo "test-popupguard (TREE=$T scenarios): checks FAILED"; exit 1; }; exit 0; }

echo "== units: PopupGuard.h"
$CC -DUNITS -I../common -o "$W/units" test-popupguard.m && "$W/units" || fails=1

echo "== wiring"
B=../appbridge/AppBridge.x
F="awk '/^static void MABInstallPopupGuard\\(void\\) \\{/,/^}/' $B"
check "MacAppBridge takes the guard from PopupGuard.h (no copy of its own left)" \
  "grep -q '^#include \"../common/PopupGuard.h\"' $B && ! grep -q 'static void MABPopupRun\\|static void (\\*oMABPresentBar)\\|static void (\\*oMABDismissBar)' $B"
check "  ... only in an app that contains the library, on UIViewController (the library's category)" \
  "$F | grep -q 'if (!NSClassFromString(@\"LNPopupBar\")) return;' && $F | grep -q 'MSBDPopupGuardInstall(\\[UIViewController class\\]);'"
check "  ... installed from the bridge's first main-queue turn, not from its constructor (the app has started; nothing asked of UIKit early)" \
  "awk '/dispatch_async\\(dispatch_get_main_queue\\(\\), \\^\\{/{d=1} d && /MABInstallPopupGuard\\(\\);/{f=1} END{exit !f}' $B && [ \$(grep -c 'MABInstallPopupGuard();' $B) = 1 ]"
check "PopupGuard.h asks nothing of UIKit (runtime and Foundation only)" "! grep -v '^ *//' $H | grep -q 'UIKit\\|UIApplication\\|UIView'"
check "the designated present is hooked when known, else the 3-argument one, never both (a forwarded call is guarded once)" \
  "awk '/^static BOOL MSBDPopupGuardInstall/,/^}/' $H | grep -q 'if (args == 4) {' && [ \$(awk '/^static BOOL MSBDPopupGuardInstall/,/^}/' $H | grep -c 'MSHookMessageEx(vc, gMSBDPopupPresentSel') = 2 ]"
check "the debug trace (popuptrace) is still debug only" "awk '/^static void MABInstallPopupTrace/{f=NR} END{exit !f}' $B && grep -q 'MABInstallPopupTrace' $B"

L=../loader/Loader.c
check "the loader: a recovery app's kind comes from MSBDRecoveryKind, the library looked for by MSBDHasPopupLibrary (MacStatusBar's line)" \
  "grep -q 'if ((kind & ~kSpotlight) == kUIKit) kind = MSBDRecoveryKind(kind, MSBDRecoveryApp(path), MSBDHasPopupLibrary);' $L"
check "  ... the MacDock line asks no library: its recovery apps get nothing (it has no such part)" \
  "grep -q 'if ((kind & ~kSpotlight) == kUIKit) kind = MSBDRecoveryKind(kind, MSBDRecoveryApp(path), NULL);' $L"
check "  ... the library looked for by name through the runtime the app has (dlsym objc_getClass; the loader links no Objective-C, asks no UIKit)" \
  "awk '/^static int MSBDHasPopupLibrary\\(void\\) \\{/,/^}/' $L | grep -q 'dlsym(RTLD_DEFAULT, \"objc_getClass\")' && ! grep -q '#import\\|objc/runtime.h' $L"
check "  ... rows only (an untested iPadOS, the crash guard's safe mode) still loads only rows: the guard is not a row" \
  "grep -q '{ \"MacPopupGuard\", kPopupGuard },' $L && grep -q 'if (rowsOnly && !(kPayloads\\[i\\].where & kRow)) continue;' $L"
P=../popupguard/PopupGuardPart.m
check "MacPopupGuard: built and shipped (Makefile SUBPROJECTS and PAYLOADS)" "grep -q '^SUBPROJECTS += popupguard$' ../Makefile && sed -n '/^PAYLOADS *=/,/^\$/p' ../Makefile | grep -q 'MacPopupGuard'"
check "  ... only the guard: PopupGuard.h installed on UIViewController in an app with the library, from the first main-queue turn" \
  "grep -q '#include \"../common/PopupGuard.h\"' $P && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{' $P && grep -q 'if (objc_getClass(\"LNPopupBar\") && vc) MSBDPopupGuardInstall(vc);' $P && [ \$(grep -c 'MSHookMessageEx\\|%hook' $P) = 0 ]"
echo "== made-to-fail copies of PopupGuard.h (each must make a check fail)"
mtf() {   # mtf <name> <perl substitution> <scenario|units>
  local d="$W/mtf-$1"; mkdir -p "$d/appbridge" "$d/common"
  perl -0pe "$2" "$H" > "$d/common/PopupGuard.h"
  if cmp -s "$H" "$d/common/PopupGuard.h"; then echo "FAIL  made-to-fail $1: the change did not apply"; fails=1; return; fi
  cp ../appbridge/AppBridge.x "$d/appbridge/"
  cut_section "$d" "$d/guard.inc"
  if [ "$3" = units ]; then
    if $CC -DUNITS -I"$d/common" -o "$d/t" test-popupguard.m 2>/dev/null && "$d/t" >/dev/null 2>&1; then echo "FAIL  made-to-fail $1: not caught"; fails=1; else echo "PASS  made-to-fail $1: caught"; fi
  else
    if $CC -DGUARD_INC="\"$d/guard.inc\"" -o "$d/t" test-popupguard.m 2>/dev/null && "$d/t" >/dev/null 2>&1; then echo "FAIL  made-to-fail $1: not caught"; fails=1; else echo "PASS  made-to-fail $1: caught"; fi
  fi
}
mtf "the 3-argument present taken although the designated one is known (1.8.8's choice)" 's/if \(m && MSBDPopupTypesAre\(method_getTypeEncoding\(m\), "v\@:\@BB\@\?"\)\) return 4;/(void)m;/' scenario
mtf "no wait while one is animating" 's/if \(objc_getAssociatedObject\(vc, &kMSBDPopupBusy\)\) \{/if (0) {/' scenario
mtf "a replaced request's completion dropped" 's/if \(oldCompletion\) oldCompletion\(\); //' scenario
mtf "the open flag lost on the way" 's/oMSBDPresentBar4\(vc, gMSBDPopupPresentSel, content, open, animated, done\)/oMSBDPresentBar4(vc, gMSBDPopupPresentSel, content, NO, animated, done)/' scenario
mtf "any argument types accepted" 's/if \(c != \*want\) return NO;/(void)c;/' units
echo "== made-to-fail copies of Loader.c (each must make the loader test fail)"
mtfl() {   # mtfl <name> <perl substitution>
  local d="$W/mtfl-$1"; mkdir -p "$d"
  perl -0pe "$2" ../loader/Loader.c > "$d/Loader.c"
  if cmp -s ../loader/Loader.c "$d/Loader.c"; then echo "FAIL  made-to-fail $1: the change did not apply"; fails=1; return; fi
  loader_inc "$d/Loader.c" "$d/loader.inc"
  if clang -Wall -Wno-unused-function -DLOADER_INC="\"$d/loader.inc\"" -o "$d/t" test-popupguard-loader.c 2>/dev/null && "$d/t" >/dev/null 2>&1; then echo "FAIL  made-to-fail $1: not caught"; fails=1; else echo "PASS  made-to-fail $1: caught"; fi
}
mtfl "a recovery app with the library gets every app-side part" 's/return askLibrary && askLibrary\(\) \? kPopupGuard : 0;/return askLibrary \&\& askLibrary() ? kind : 0;/'
mtfl "the library looked for in every app" 's/(static unsigned MSBDRecoveryKind\(unsigned kind, int recoveryApp, int \(\*askLibrary\)\(void\)\) \{\n)/$1    if (askLibrary) askLibrary();\n/'
mtfl "the guard loaded as a row (an untested iPadOS, safe mode)" 's/\{ "MacPopupGuard", kPopupGuard \},/{ "MacPopupGuard", kPopupGuard | kRow },/'
mtfl "the guard in a recovery app without the library" 's/return askLibrary && askLibrary\(\) \? kPopupGuard : 0;/return kPopupGuard;/'

[ $fails = 0 ] && echo "test-popupguard: all checks pass" || { echo "test-popupguard: checks FAILED"; exit 1; }
