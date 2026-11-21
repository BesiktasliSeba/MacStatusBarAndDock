#!/bin/bash
# test-appmenusready.sh: B12 (KT 19 Nov: "App status bar menus come too late sometimes, in reynard for example they can take like a minute to
# appear, or only when status bar is touched"). At a cold launch SpringBoard's ask comes before MacAppBridge can hear it (M1 20 Nov: 7 of 7
# cold launches); now the app says when it can answer ("menushere", once per process) and SpringBoard asks it again at once while it is the app
# in front. Then B12's thin first answer (p07 rows, M1 / iPad 2 / A12Z, 20 Nov): that answer is right for its moment, but what the app offers
# grows after it with nothing to say so (Maps: File, Edit, View at ~1 s; its home card's Bookmarks and Actions later; Files: Actions, later File,
# View, Actions), and the bar kept the thin set until a tap. Now the app looks again after its own activity and says "menuschanged" when what its
# titles rest on moved (where its commands start, the responders from there, their key commands, its main menu's rebuild); SpringBoard asks it
# 1 s later, not while one of our menus is open. Its independent review: a word no answer follows (not the bar's app, or one of our menus
# open over it) backs the looks off as an answer that showed nothing does, one word out at a time; with the switch off a look stops before it
# reads anything; and any answer no look asked for (a switch, a tap) puts the looks back to once a second. Its review (1.8.8.1): so does the first
# answer after a word no answer followed (brought forward with no tap within 3 s of that word, it kept the 8 s back-off: frontafterword). The real code of both sides (AMR_SB = statusbar/AppMenus.h, AMR_APP = appbridge/AppMenus.h:
# another copy, e.g. 1.8.8 RC 2's) on real Darwin notifications and the real main run loop, one scenario per process (test-appmenusready.m), the
# app's snapshot the real one; release and (for the lines p08 reads) DEBUG; then site checks and made-to-fail copies, each must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
if [ -n "$AMR_KEEP" ]; then W=$AMR_KEEP; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi   # (AMR_KEEP=<dir>: the builds kept there)
SB0=${AMR_SB:-../statusbar/AppMenus.h}; APP0=${AMR_APP:-../appbridge/AppMenus.h}; RULES=${AMR_RULES:-../common/AppMenuRules.h}
fnst() { awk -v n="$2(" '(index($0, "static ") == 1 || index($0, "__attribute__((noinline)) static ") == 1) && index($0, n) {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # a static function by its name
SCEN="cold warm early notfront off once partial relaunch grows moves filesrebuild filesstart steady idle nomenus flap openmenu away offlater flapnotfront flapmenu offstill backswitch backtap frontafterword frontlate fronttap focustap plaintap menuopenclose"
DSCEN="grows flapnotfront offstill backswitch frontafterword"   # (DEBUG: the lines p08 and p10 read)

build() {   # $1 SpringBoard's AppMenus.h, $2 the app's, $3 dir, $4 quiet
  local d=$3 fl; mkdir -p "$d"; cp "$RULES" "$d/AppMenuRules.h"
  # (the names under this run's prefix; the app's bundle id and its tmp folder are the test's)
  # (the switch's name per process: the scenarios run side by side, and one of them publishes it off)
  local sub='s/"com\.besiktasliseba\.appbridge\.appmenus"/TSwitchName()/g; s/"com\.besiktasliseba\.appbridge\./TPFX "/g; s/\[NSBundle mainBundle\]\.bundleIdentifier/TBundle()/g'
  awk '/^static BOOL gAMOn = YES;/ {f=1} f {print} f && /^static void DMAMFrontSeen\(SBApplication \*app\) \{/ {g=1} g && /^[}]/ {exit}' "$1" | sed -E "$sub" > "$d/sb-block.inc"
  fnst "$1" DMAMApplyPref | sed -E "$sub" >> "$d/sb-block.inc"
  # (the app's whole file but for the four stand-ins: where it finds its key window, its first responder, its main menu, and the pick)
  awk 'BEGIN { n = split("MABMenuKeyWindow MABMenuStart MABMenuRoot MABMenuPerform", a, " ") }
       !skip && index($0, "static ") == 1 && /\{$/ { for (i = 1; i <= n; i++) if (index($0, "*" a[i] "(") || index($0, " " a[i] "(")) skip = 1 }
       skip { if ($0 ~ /^[}]/) skip = 0; next } { print }' "$2" \
    | sed -E "$sub"'; s#^\#include "\.\./common/AppMenuRules\.h"#\#include "AppMenuRules.h"#; s/NSTemporaryDirectory\(\)/TTmp()/g' > "$d/app-block.inc"
  grep -q 'DMAMFrontSeen' "$d/sb-block.inc" && grep -q 'static void MABRegisterMenus(void) {' "$d/app-block.inc" && grep -q 'static BOOL MABMenuSnapshot(void) {' "$d/app-block.inc" \
    && ! grep -q 'static UIWindow \*MABMenuKeyWindow(void) {' "$d/app-block.inc" && ! grep -q 'static UIMenu \*MABMenuRoot(void) {' "$d/app-block.inc" \
    || { echo "FAIL  the code was not found in $1 / $2"; return 99; }
  for fl in t td; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -DTPFX="\"test.b12.$$.$RANDOM.\"" -I"$d" $([ $fl = td ] && echo -DDEBUG=1) \
          -framework UIKit -framework QuartzCore -o "$d/$fl" test-appmenusready.m 2> "$d/cc-$fl.txt" || { [ -n "$4" ] || cat "$d/cc-$fl.txt"; echo "FAIL  the real code did not build ($fl)"; return 99; }
    [ -s "$d/cc-$fl.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings ($fl):"; cat "$d/cc-$fl.txt"; return 1; }
  done
  return 0
}
runall() {   # $1 dir, $2 quiet: the number of scenarios that fail (all side by side: each waits on its timers, not the CPU)
  local d=$1 n=0 s
  for s in $SCEN; do ( "$d/t" "$s" > "$d/out-$s.txt" 2>&1; echo $? > "$d/rc-$s" ) & done
  for s in $DSCEN; do ( "$d/td" "$s" > "$d/out-d-$s.txt" 2>&1; echo $? > "$d/rc-d-$s" ) & done; wait
  for s in $SCEN; do [ -n "$2" ] || cat "$d/out-$s.txt"; [ "$(cat "$d/rc-$s")" = 0 ] || n=$((n + 1)); done
  for s in $DSCEN; do [ -n "$2" ] || { echo "(DEBUG build)"; cat "$d/out-d-$s.txt"; }; [ "$(cat "$d/rc-d-$s")" = 0 ] || n=$((n + 1)); done
  echo "$n"
}

fails=0
build "$SB0" "$APP0" "$W/real" || exit 1
runall "$W/real" > "$W/real.txt"; sed '$d' "$W/real.txt"; [ "$(tail -1 "$W/real.txt")" = 0 ] || fails=1

# site checks (what the scenarios can't see: the order in the app, one name on both sides, where the looks start, what they read, the crash map)
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the app's word comes after both of its handlers are registered (an ask sent for it then reaches them), with the switch on" \
  "fnst $APP0 MABRegisterMenus | awk '/notify_register_dispatch\\(name, &tokenAsk/{a=NR} /notify_register_dispatch\\(name, &tokenAct/{b=NR} /if \\(MABMenusOn\\(\\)\\) \\{/{c=NR} /notify_post\\(here\\);/{p=NR} END{exit !(a && b && c && p && a < p && b < p && c < p && p == c + 2)}'"
check "one name on both sides: menushere.<hash>" \
  "[ \$(grep -cF '\"com.besiktasliseba.appbridge.menushere.%08x\"' $APP0) = 1 ] && [ \$(grep -cF '\"com.besiktasliseba.appbridge.menushere.%08x\"' $SB0) = 1 ]"
check "SpringBoard listens for it with the app's other names (once per app, when it first asks it), and asks at once, forced, only while it is the app in front" \
  "awk '/if \\(!gAMReadyTokens\\[bundle\\]\\) \\{/{f=1} f && /\\^\\(int t\\) \\{ if \\(gAMOn && \\[\\[DMActiveApp\\(\\) bundleIdentifier\\] isEqualToString:b\\]\\) DMAMAsk\\(b, YES\\); \\}\\);/{ok=1} f && /^    \\}/{exit !ok} END{exit !ok}' $SB0"
check "the crash guard: both new blocks are in AppMenus.h, whose crash turns Show Apps' Own Menus off (the switch's publishing kept out of line: -Os put it in DMLoadPrefs)" \
  "grep -qxF 'file MacStatusBarCore ^AppMenus\\.h\$ appOwnMenus' crashmap-rules.txt && grep -qxF 'file MacAppBridge ^AppMenus\\.h\$ appOwnMenus' crashmap-rules.txt && grep -qxF '__attribute__((noinline)) static void DMAMApplyPref(BOOL on) {' $SB0"
check "the looks start only with an answer written (once per process), never at the registration or from a constructor" \
  "fnst $APP0 MABMenuSnapshot | grep -qxF '    if (wrote) MABMenusAnswered(start, keyCmds, chain, ordered);   // (B12: what it rests on, for the looks)' && [ \$(grep -c 'MABMenusAnswered(' $APP0) = 2 ] && [ \$(grep -c 'MABMenusWatch()' $APP0) = 1 ] && fnst $APP0 MABMenusAnswered | grep -qF '    MABMenusWatch();' && ! fnst $APP0 MABRegisterMenus | grep -qE 'MABMenusWatch|MABMenusLook|CFRunLoop' && ! grep -qE 'MABMenusWatch|MABMenusLook|MABMenusAnswered' ../appbridge/AppBridge.x"
check "a look reads only where the commands start and their key commands: no canPerformAction:, no validation, no pasteboard, no file, no snapshot" \
  "fnst $APP0 MABMenusLook | grep -qF 'MABMenuPrintOf(start, MABMenuKeyCommandsFrom(start, &chain), chain)' && ! { fnst $APP0 MABMenusLook; fnst $APP0 MABMenuPrintOf; fnst $APP0 MABMenuKeyCommandsFrom; } | grep -qE 'targetForAction|validateCommand|canPerformAction|UIPasteboard|writeToFile|MABMenuSnapshot|MABMenuRoot'"
check "one walk of the responders for the answer and the looks (at most 64, L8); the print leaves the titles out" \
  "[ \$(grep -c 'x.keyCommands' $APP0) = 1 ] && fnst $APP0 MABMenuKeyCommandsFrom | grep -qF 'for (UIResponder *x = start; x && depth < 64; x = x.nextResponder, depth++) {' && fnst $APP0 MABMenuSnapshot | grep -qF 'NSArray<UIKeyCommand *> *keyCmds = MABMenuKeyCommandsFrom(start, &chain);' && ! fnst $APP0 MABMenuPrintOf | grep -qE 'title\\.hash|title\\]|discoverabilityTitle\\.hash'"
check "the looks: as the main run loop is about to wait (its default mode, after UIKit's layout of the turn at 2000000), at most once a second, every 2, 4, then 8 s after answers that said the same" \
  "fnst $APP0 MABMenusWatch | grep -qF 'kCFRunLoopBeforeWaiting, YES, 2147483000,' && fnst $APP0 MABMenusWatch | grep -qF 'due = last + (double)(1 << gMABLookIdle);' && fnst $APP0 MABMenusAnswered | grep -qF 'gMABLookIdle < 3) gMABLookIdle++;' && [ \$(fnst $APP0 MABMenusWatch | grep -c 'kCFRunLoopDefaultMode') = 2 ] && ! grep -q 'kCFRunLoopCommonModes' $APP0"
check "the main menu's rebuild heard by UIKit's exported name, where there is one, for the main menu system only" \
  "fnst $APP0 MABMenusWatch | grep -qF 'dlsym(RTLD_DEFAULT, \"_UIMenuSystemShouldRebuildNotification\")' && fnst $APP0 MABMenusWatch | grep -qF 'if (rebuild && *rebuild && sys)' && fnst $APP0 MABMenusWatch | grep -qF 'addObserverForName:*rebuild object:sys '"
check "SpringBoard never asks under one of our open menus after a tap, a menuschanged or a thin answer (asked once it is closed)" \
  "awk '/^static void DMAMAskSoon\\(NSString \\*bundle, double delay\\) \\{/{f=1} f{print} f && /^[}]/{exit}' $SB0 | grep -qxF '        if (gOverlay) { DMAMAskSoon(b, 1.0); return; }'"
check "a look reads the switch before anything else (off: no walk of the responders, no key window), and stops the looks there" \
  "fnst $APP0 MABMenusLook | sed -n 2,3p | tr -d '\\n' | grep -qF '    if (!MABMenusOn()) {   // (switched off since its answer: no looking, not even a walk, until the next answer, which needs it on)        gMABLooking = NO;'"
check "one word out at a time: held while the answer to the last can still come (SpringBoard asks 1 s after a word; held under 2.5 s, within the 3 s an answer counts as the word's), counted toward the back-off after, and the next answer then puts the looks back" \
  "fnst $APP0 MABMenusLook | grep -qxF '        if (CACurrentMediaTime() - gMABLookSaidAt < 2.5) return;' && fnst $APP0 MABMenusAnswered | grep -qxF '    BOOL lookAsked = !gMABLookUnheard && gMABLookSaidAt > gMABAnsweredAt && now - gMABLookSaidAt < 3.0;' && fnst $APP0 MABMenusLook | grep -qxF '    if (gMABLookSaidAt > gMABAnsweredAt) {' && fnst $APP0 MABMenusLook | grep -qxF '        gMABLookUnheard = YES;' && grep -F 'notify_register_dispatch(changed, &changedToken' $SB0 | grep -qF 'DMAMAskSoon(b, 1.0); });' && fnst $APP0 MABMenusAnswered | grep -qxF '    gMABAnsweredAt = now; gMABLookUnheard = NO;' && [ \$(grep -c 'gMABLookUnheard' $APP0) = 4 ]"
check "the lines p08 and p10 read are debug only (the look's, the snapshot's sources, UIKit's words and focus, the looks stopped by the switch)" \
  "awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /^#else/{d=0} /what it offers moved since its answer|appmenus: snapshot: of them|appmenus: heard %@|no more looks \\(at /{ if (!d) bad=1; n++ } END{exit !(n == 4 && !bad)}' $APP0"
check "the switch: SpringBoard posts it as it publishes it, and the app reads its state only after a post (notify_check), the first time and when the check cannot tell (review note 3)" \
  "fnst $SB0 DMAMApplyPref | grep -qF '{ notify_set_state(token, want); notify_post(kDMAMSwitchName); published = want; }' && fnst $APP0 MABMenusOn | grep -qxF '    else if (notify_check(token, &moved) != NOTIFY_STATUS_OK) moved = 1;' && fnst $APP0 MABMenusOn | grep -qxF '    if (token && moved) notify_get_state(token, &state);' && [ \$(grep -c 'notify_post(kDMAMSwitchName)' $SB0) = 1 ]"
check "no em dash in the test" "! grep -q \$'\\xe2\\x80\\x94' test-appmenusready.m test-appmenusready.sh"

# made-to-fail copies: each must make at least one scenario fail
mtf() {   # $1 what, $2 file (sb|app), $3 sed
  local d="$W/m$((++mi))" s=$SB0 a=$APP0
  mkdir -p "$d"
  if [ "$2" = sb ]; then sed -E "$3" "$SB0" > "$d/AppMenus-sb.h"; s="$d/AppMenus-sb.h"; cmp -s "$s" "$SB0" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }
  else sed -E "$3" "$APP0" > "$d/AppMenus-app.h"; a="$d/AppMenus-app.h"; cmp -s "$a" "$APP0" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }; fi
  build "$s" "$a" "$d/b" q || { echo "PASS  made-to-fail ($1): caught (does not build)"; return; }
  local k; k=$(runall "$d/b" q | tail -1)
  if [ "$k" -gt 0 ]; then echo "PASS  made-to-fail ($1): caught ($k scenarios fail)"; else echo "FAIL  made-to-fail ($1): not caught"; fails=1; fi
}
mi=0
mtf "the app says nothing at its registration (1.8.7.9)" app '/^        notify_post\(here\);$/d'
mtf "SpringBoard doesn't listen for the app's word" sb '/notify_register_dispatch\(here, &hereToken/d'
mtf "SpringBoard asks after the word whatever app is in front" sb 's/\^\(int t\) \{ if \(gAMOn && \[\[DMActiveApp\(\) bundleIdentifier\] isEqualToString:b\]\) DMAMAsk\(b, YES\); \}/^(int t) { if (gAMOn) DMAMAsk(b, YES); }/'
mtf "SpringBoard's ask after the word is not forced (within 2 s of the front change: skipped)" sb 's/isEqualToString:b\]\) DMAMAsk\(b, YES\); \}\);$/isEqualToString:b]) DMAMAsk(b, NO); });/'
mtf "the word is posted with the switch off" app 's/^    if \(MABMenusOn\(\)\) \{$/    if (1) {/'
mtf "the word on every window or scene change too" app 's/usingBlock:\^\(NSNotification \*n\) \{ MABMenusChanged\(\); \}\];/usingBlock:^(NSNotification *n) { MABMenusChanged(); char h2[96]; snprintf(h2, sizeof h2, "com.besiktasliseba.appbridge.menushere.%08x", hash); notify_post(h2); }];/'
mtf "SpringBoard waits 1 s after the word, as for a tap" sb 's/isEqualToString:b\]\) DMAMAsk\(b, YES\); \}\);$/isEqualToString:b]) DMAMAskSoon(b, 1.0); });/'
mtf "the two sides' names differ" app 's/appbridge\.menushere\.%08x/appbridge.menuhere.%08x/'
# (B12's thin first answer)
mtf "the app never looks again after its answer (1.8.8 RC 2)" app 's/^    if \(wrote\) MABMenusAnswered\(start, keyCmds, chain, ordered\);/    if (0) MABMenusAnswered(start, keyCmds, chain, ordered);/'
mtf "a look that sees a move says nothing" app '/^    gMABSaidPrint = p; gMABLookSaidAt = CACurrentMediaTime\(\);$/{n;d;}'
mtf "the print leaves out the key commands" app 's/^        p\.cmds \+= h; p\.count\+\+;/        (void)h;/'
mtf "the print leaves out where the commands start and the responders from there" app 's/MABMenuPrint p = \{ \(uintptr_t\)\(__bridge void \*\)start, chain, 0, 0, gMABMenuGen \};/MABMenuPrint p = { 0, 0, 0, 0, gMABMenuGen }; (void)start; (void)chain;/'
mtf "the print counts the titles too (Play / Pause)" app 's/^        p\.cmds \+= h; p\.count\+\+;/        h = (h ^ (uint64_t)c.title.hash) * 1099511628211ull; p.cmds += h; p.count++;/'
mtf "the main menu's rebuild not heard" app '/addObserverForName:\*rebuild object:sys /d; s/if \(rebuild && \*rebuild && sys\)$/(void)sys; (void)rebuild;/'
mtf "a look at every turn of the run loop (not once a second)" app 's/due = last \+ \(double\)\(1 << gMABLookIdle\);/due = last;/'
mtf "no wake for the look due after the last activity" app 's/^        \} else if \(!armed\) \{ armed = YES; CFRunLoopTimerSetNextFireDate\(wake, CFAbsoluteTimeGetCurrent\(\) \+ \(due - now\)\); \}/        }/'
mtf "a look arms the wake again (an idle app woken every second)" app 's/^            @autoreleasepool \{ MABMenusLook\(\); \}$/            @autoreleasepool { MABMenusLook(); } armed = YES; CFRunLoopTimerSetNextFireDate(wake, CFAbsoluteTimeGetCurrent() + 1.0);/'
mtf "no back-off for looks whose answers said the same" app 's/due = last \+ \(double\)\(1 << gMABLookIdle\);/due = last + 1.0;/'
mtf "it looks with no window of it in front" app 's/^    if \(!win \|\| win\.windowScene\.activationState != UISceneActivationStateForegroundActive\) return;   \/\/ \(no window of it in front\)$/    (void)0;/'
mtf "the switch read only after a move (8cd44f8a: off, it walked its responders once a second)" app 's/^    if \(!MABMenusOn\(\)\) \{   \/\/ \(switched off since.*$/    if (0) {/; s/^(    if \(MABMenuPrintSame\(p, gMABAnswerPrint\) \|\| MABMenuPrintSame\(p, gMABSaidPrint\)\) return;)$/\1 if (!MABMenusOn()) { gMABLooking = NO; return; }/'
mtf "it goes on looking after the switch is seen off" app '/^        gMABLooking = NO;$/d'
mtf "the app reads the switch's state at every look (1.8.8: a round trip to notifyd each)" app 's/^    if \(token && moved\) notify_get_state\(token, &state\);$/    if (token) notify_get_state(token, \&state);/'
mtf "SpringBoard sets the switch without posting it (the apps never see it go off)" sb 's/ notify_post\(kDMAMSwitchName\);//'
mtf "the answer's print not kept" app '/^    gMABAnswerPrint = MABMenuPrintOf\(start, kcs, chain\);$/d'
mtf "a word no answer follows does not back the looks off (8cd44f8a: a window beside the bar's app said it every second)" app '/^        if \(gMABLookIdle < 3\) gMABLookIdle\+\+;$/d'
mtf "two words out at once (a look says it again before the last one's answer can have come)" app '/^        if \(CACurrentMediaTime\(\) - gMABLookSaidAt < 2\.5\) return;$/d'
mtf "an answer no look asked for leaves the looks backed off (8cd44f8a)" app 's/^    if \(sig != gMABAnswerSig \|\| !lookAsked\) gMABLookIdle = 0;$/    if (sig != gMABAnswerSig) gMABLookIdle = 0; else if (!lookAsked) {}/'
mtf "every answer puts the looks back to once a second (no back-off)" app 's/^    BOOL lookAsked = !gMABLookUnheard && gMABLookSaidAt > gMABAnsweredAt && now - gMABLookSaidAt < 3\.0;$/    BOOL lookAsked = NO;/'
mtf "an answer after a word no answer followed counts as that word's (1.8.8: brought forward with no tap, the looks stayed at 8 s)" app '/^        gMABLookUnheard = YES;$/d'
mtf "a word no answer followed, once, puts the looks back at every answer after it (its mark never cleared)" app 's/^    gMABAnsweredAt = now; gMABLookUnheard = NO;$/    gMABAnsweredAt = now;/'
mtf "SpringBoard asks under one of our open menus" sb '/^        if \(gOverlay\) \{ DMAMAskSoon\(b, 1\.0\); return; \}$/d'
[ "$fails" = 0 ] && echo "test-appmenusready: all pass" || { echo "test-appmenusready: FAILED"; exit 1; }
