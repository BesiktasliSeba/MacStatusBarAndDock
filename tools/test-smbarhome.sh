#!/bin/bash
# Mac test of which window title bars leave with their windows going Home (Stage Manager engine, 1.8.7; KT 11 Nov, A12Z with the 4K TV: a
# centered window on the TV had no title bar and no traffic lights while the iPad sat at its Home Screen). The rule (common/SMBarHome.h): a
# title bar fades only when ITS display's switcher goes Home; the last transition event of any switcher (gEnvMode) is the fallback for a window
# on the iPad alone, when its switcher can't be read. The App Switcher's reads of the same global (a card scaled in it, a touch on the menu bar,
# a touch on a full-screen window under windows) follow the same rule (MSBDSMInSwitcher). Then its sites in statusbar/StatusBar.x as built, and
# copies of those sites made to fail (the old global reads put back one at a time): each must fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
cat > "$W/t.c" <<'C'
#include <stdio.h>
#include "SMBarHome.h"
static int fails = 0, n = 0;
static void expect(int got, int want, const char *what) { n++; if (got != want) { fails++; printf("FAIL  %s (got %d)\n", what, got); } else printf("PASS  %s\n", what); }
int main(void) {
    // (read: its display's switcher read; own: its environment; last: the last event of any switcher; main: the window on the iPad)
    expect(MSBDSMBarGoesHome(1, 1, 1, 1), 1, "the iPad goes Home: a window on the iPad leaves with its bar (24 Oct, no line over the icon)");
    expect(MSBDSMBarGoesHome(1, 3, 1, 0), 0, "the iPad goes Home: a window on the TV, whose switcher shows its desktop, keeps its bar (KT 11 Nov)");
    expect(MSBDSMBarGoesHome(1, 3, 1, 0), 0, "  ... and keeps it on every later layout while the iPad stays at Home (the last event still 1)");
    expect(MSBDSMBarGoesHome(1, 1, 1, 0), 1, "the TV's own switcher goes Home (its empty desktop): a window on the TV leaves with its bar");
    expect(MSBDSMBarGoesHome(1, 3, 1, 1), 0, "the TV went Home last: a window on the iPad's desktop keeps its bar");
    expect(MSBDSMBarGoesHome(1, 1, 3, 1), 1, "the iPad going Home while the TV's event came last: the iPad's window still leaves with its bar");
    expect(MSBDSMBarGoesHome(1, 2, 1, 1), 0, "its switcher in the App Switcher (2): no Home fade");
    expect(MSBDSMBarGoesHome(1, 3, 3, 1), 0, "a desktop on both: nothing fades");
    expect(MSBDSMBarGoesHome(1, 0, 1, 1), 0, "its switcher read with environment 0 (none): no fade");
    expect(MSBDSMBarGoesHome(0, 0, 1, 1), 1, "its switcher not read: a window on the iPad as before (the last event 1)");
    expect(MSBDSMBarGoesHome(0, 0, 3, 1), 0, "  ... (the last event 3): keeps its bar");
    expect(MSBDSMBarGoesHome(0, 0, 1, 0), 0, "its switcher not read: a window on another display keeps its bar");
    expect(MSBDSMBarGoesHome(0, 0, 2, 0), 0, "  ... whatever the last event");
    // the App Switcher (2), each display by its own switcher
    expect(MSBDSMInSwitcher(1, 2, 2, 1), 1, "the iPad's App Switcher up: the iPad's cards and menu bar are the App Switcher's");
    expect(MSBDSMInSwitcher(1, 3, 2, 0), 0, "the iPad's App Switcher up: the TV, at its desktop, keeps its menu bar's and full-screen window's touches");
    expect(MSBDSMInSwitcher(1, 2, 3, 0), 1, "the TV's App Switcher up, an iPad event after it: the TV's cards are still the App Switcher's");
    expect(MSBDSMInSwitcher(1, 3, 2, 1), 0, "the TV's App Switcher up last: the iPad's shrunk background window keeps its bar's taps and grips");
    expect(MSBDSMInSwitcher(1, 1, 2, 1), 0, "its switcher at Home: not the App Switcher");
    expect(MSBDSMInSwitcher(0, 0, 2, 1), 1, "its switcher not read: the iPad as before (the last event 2)");
    expect(MSBDSMInSwitcher(0, 0, 3, 1), 0, "  ... (the last event 3)");
    expect(MSBDSMInSwitcher(0, 0, 2, 0), 0, "its switcher not read: another display not by the last event");
    expect(MSBDSMOwnEnvIs(1, 3, 1, 1, 3), 1, "the rule for any environment: its own (3 == 3)");
    expect(MSBDSMOwnEnvIs(0, 0, 3, 1, 3), 1, "  ... not read, on the iPad: the last event (3 == 3)");
    printf("%d / %d C cases\n", n - fails, n);
    return fails != 0;
}
C
clang -O2 -Wall -Werror -I ../common -o "$W/t" "$W/t.c"
"$W/t"
fails=0
# sites <StatusBar.x>: the number of site checks that fail on that file (printed with PASS / FAIL when $2 is "show")
sites() {
  local S="$1" show="$2" f=0
  fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' "$S" > "$W/fn"; }
  ck() { if eval "$2"; then [ "$show" = show ] && echo "PASS  $1"; else [ "$show" = show ] && echo "FAIL  $1"; f=$((f+1)); fi; return 0; }
  ck "the rule is included in StatusBar.x ahead of the title bars' Home fade" \
    "grep -q '^#include \"../common/SMBarHome.h\"' '$S' && awk '/^#include \"..\/common\/SMBarHome.h\"/{i=NR} /^static void DMSMFadeBar\(/{d=NR} END{exit !(i && d > i)}' '$S'"
  ck "a window scene's switcher: the coordinator's switcher for that scene, its layout context, where its transition goes before its state" \
    "fn 'static BOOL DMSwitcherEnvOfScene(UIWindowScene *scene, long long *env) {' \
     && grep -qF 'DMSMSigOK(c, forScene, DMSMSigObjObj(), \"switcherControllerForWindowScene:\")' \$W/fn \
     && grep -qF 'id state = DMSwitcherObjCall(lc, @\"transitioningToLayoutState\") ?: DMSwitcherObjCall(lc, @\"layoutState\");' \$W/fn \
     && grep -qF 'return DMSMHomeStateOf(state, env, &stage);' \$W/fn && ! grep -q 'gEnvMode\|MSBDMainWindowScene\|mainScreen' \$W/fn"
  ck "  ... a view's: its own window's scene" \
    "fn 'static BOOL DMSwitcherEnvOfView(UIView *v, long long *env) {' && grep -qF 'UIWindowScene *scene = v.window.windowScene;' \$W/fn \
     && grep -qF 'return DMSwitcherEnvOfScene(scene, env);' \$W/fn && ! grep -q 'gEnvMode\|MSBDMainWindowScene' \$W/fn"
  ck "  ... a screen's: a window scene on that very screen" \
    "fn 'static BOOL DMSwitcherEnvOfScreen(UIScreen *screen, long long *env) {' \
     && grep -qF '(((UIWindowScene *)sc).screen ?: [UIScreen mainScreen]) != screen) continue;' \$W/fn \
     && grep -qF 'if (DMSwitcherEnvOfScene((UIWindowScene *)sc, env)) return YES;' \$W/fn && ! grep -q 'gEnvMode\|MSBDMainWindowScene' \$W/fn"
  ck "  ... its getters type-checked" \
    "fn 'static id DMSwitcherObjCall(id obj, NSString *name) {' && grep -qF 'DMSMSigOK(obj, s, DMSMSigObj(), name.UTF8String)' \$W/fn"
  ck "a card goes Home by its own display's switcher, the last event only the rule's fallback, the iPad's screen by the card's own" \
    "fn 'static BOOL DMSMCardGoesHome(UIView *card) {' && grep -qF 'BOOL read = card.window && DMSwitcherEnvOfView(card, &env);' \$W/fn \
     && grep -qF 'return MSBDSMBarGoesHome(read, env, gEnvMode, DMSnapScreenOf(card) == [UIScreen mainScreen]);' \$W/fn"
  ck "an event of environment 1 fades only the title bars whose display goes Home" \
    "fn 'static void DMSMBarsForEnvironment(long long mode) {' && grep -qF 'BOOL goes = DMSMCardGoesHome(bar.card);' \$W/fn && grep -qF 'if (goes) DMSMFadeBar(bar);' \$W/fn \
     && ! grep -qF 'for (UIView *bar in gSMBars.allObjects) DMSMFadeBar(bar);' \$W/fn"
  ck "  ... and the fade's end hides a bar only while its display is at Home" \
    "fn 'static void DMSMFadeBar(DMSMTitleBar *bar) {' && grep -qF 'if (DMSMCardGoesHome(bar.card)) bar.hidden = YES;' \$W/fn && ! grep -q 'gEnvMode' \$W/fn"
  ck "every layout of a window card (DMSMChrome) fades its bar only for its own display's Home, never by the last event of any switcher" \
    "fn 'static void DMSMChrome(UIView *card) {' && grep -qF 'if (want && DMSMCardGoesHome(card)) { DMSMFadeBar(bar); return; }' \$W/fn && ! grep -q 'gEnvMode == 1' \$W/fn"
  ck "no other title bar site reads the last event as Home" \
    "! grep -n 'gEnvMode == 1' '$S' | grep -q ."
  ck "a card in the App Switcher by its own display's switcher, the last event only the rule's fallback" \
    "fn 'static BOOL DMSMCardInSwitcher(UIView *card) {' && grep -qF 'BOOL read = card.window && DMSwitcherEnvOfView(card, &env);' \$W/fn \
     && grep -qF 'return MSBDSMInSwitcher(read, env, gEnvMode, DMSnapScreenOf(card) == [UIScreen mainScreen]);' \$W/fn"
  ck "  ... a screen in the App Switcher by that screen's own switcher" \
    "fn 'static BOOL DMSMScreenInSwitcher(UIScreen *screen) {' && grep -qF 'BOOL read = DMSwitcherEnvOfScreen(screen, &env);' \$W/fn \
     && grep -qF 'return MSBDSMInSwitcher(read, env, gEnvMode, screen == [UIScreen mainScreen]);' \$W/fn"
  ck "a card is scaled in the App Switcher (its bar the card's) only by its own display's App Switcher" \
    "fn 'static void DMSMChrome(UIView *card) {' && grep -qF '> 0.05) && DMSMCardInSwitcher(card);' \$W/fn && ! grep -q 'gEnvMode' \$W/fn"
  ck "a touch on the menu bar is the bar's except in that screen's own App Switcher" \
    "fn 'static BOOL DMSMScreenPointOnMenuBar(CGPoint sp, UIScreen *screen) {' && grep -qF '|| DMSMScreenInSwitcher(screen)) return NO;' \$W/fn && ! grep -q 'gEnvMode' \$W/fn"
  ck "a touch on the full-screen window under windows is its own except in its display's own App Switcher" \
    "fn 'static BOOL DMSMFullScreenOwnAt(CGPoint sp, UIScreen *screen) {' && grep -qF '!= screen || DMSMCardInSwitcher(card)) return NO;' \$W/fn && ! grep -q 'gEnvMode' \$W/fn"
  echo "$f"
}
r=$(sites ../statusbar/StatusBar.x show); echo "$r" | sed '$d'; nf=$(echo "$r" | tail -1)
[ "$nf" = 0 ] || fails=1
# made-to-fail copies: each old global read (or a lost piece of the new one) put back alone must fail a check
S=../statusbar/StatusBar.x
mutate() {   # mutate <label> <perl substitution>
  perl -0pe "$2" "$S" > "$W/m.x"
  if cmp -s "$S" "$W/m.x"; then echo "FAIL  made-to-fail copy '$1': the substitution changed nothing"; fails=1; return; fi
  local k; k=$(sites "$W/m.x" | tail -1)
  if [ "$k" -gt 0 ]; then echo "PASS  made-to-fail copy '$1' fails ($k check(s))"; else echo "FAIL  made-to-fail copy '$1' passed every check"; fails=1; fi
}
mutate "DMSMChrome by the last event" 's/if \(want && DMSMCardGoesHome\(card\)\) \{ DMSMFadeBar\(bar\); return; \}/if (want && gEnvMode == 1) { DMSMFadeBar(bar); return; }/'
mutate "every bar faded on any Home event" 's/            if \(goes\) DMSMFadeBar\(bar\);/            DMSMFadeBar(bar);/'
mutate "the fade's end by the last event" 's/if \(DMSMCardGoesHome\(bar\.card\)\) bar\.hidden = YES;/if (gEnvMode == 1) bar.hidden = YES;/'
mutate "the main switcher read for every display" 's/UIWindowScene \*scene = v\.window\.windowScene;/UIWindowScene *scene = MSBDMainWindowScene();/'
mutate "the layout state only (not where the transition goes)" 's/id state = DMSwitcherObjCall\(lc, @"transitioningToLayoutState"\) \?: DMSwitcherObjCall\(lc, @"layoutState"\);/id state = DMSwitcherObjCall(lc, @"layoutState");/'
mutate "the rule's fallback on every display" 's/return MSBDSMBarGoesHome\(read, env, gEnvMode, DMSnapScreenOf\(card\) == \[UIScreen mainScreen\]\);/return MSBDSMBarGoesHome(read, env, gEnvMode, YES);/'
mutate "the rule not included" 's/^#include "..\/common\/SMBarHome.h"\n//m'
mutate "DMSMChrome's scaled by the last event" 's/scaled = \(fabs\(tr\.a - 1\.0\) > 0\.02 \|\| fabs\(card\.layer\.presentationLayer\.transform\.m11 - 1\.0\) > 0\.05\) && DMSMCardInSwitcher\(card\);/scaled = gEnvMode == 2 && (fabs(tr.a - 1.0) > 0.02 || fabs(card.layer.presentationLayer.transform.m11 - 1.0) > 0.05);/'
mutate "the menu bar's touch by the last event" 's/if \(!screen \|\| DMTestFlag\("\/tmp\/msb-sm-bartouch-asbuilt"\) \|\| DMSMScreenInSwitcher\(screen\)\) return NO;/if (gEnvMode == 2 || !screen || DMTestFlag("\/tmp\/msb-sm-bartouch-asbuilt")) return NO;/'
mutate "the full-screen window's own touch by the last event" 's/!= screen \|\| DMSMCardInSwitcher\(card\)\) return NO;/!= screen || gEnvMode == 2) return NO;/'
mutate "a screen's switcher read from the iPad's scene" 's/\(\(\(UIWindowScene \*\)sc\)\.screen \?: \[UIScreen mainScreen\]\) != screen\) continue;/0) continue;/'
mutate "the App Switcher's fallback on every display" 's/return MSBDSMInSwitcher\(read, env, gEnvMode, screen == \[UIScreen mainScreen\]\);/return MSBDSMInSwitcher(read, env, gEnvMode, YES);/'
# and the header made to fail: the last event read first; another display by the last event when not read
mkdir -p "$W/common"
mhead() {   # mhead <label> <perl substitution>
  perl -0pe "$2" ../common/SMBarHome.h > "$W/common/SMBarHome.h"
  if cmp -s ../common/SMBarHome.h "$W/common/SMBarHome.h"; then echo "FAIL  made-to-fail header '$1': the substitution changed nothing"; fails=1; return; fi
  if clang -O2 -Wall -Werror -I "$W/common" -o "$W/tm" "$W/t.c" 2>/dev/null && ! "$W/tm" > /dev/null; then echo "PASS  made-to-fail header '$1' fails its C cases"; else echo "FAIL  made-to-fail header '$1' passed"; fails=1; fi
}
mhead "the last event first" 's/if \(ownRead\) return ownEnv == mode;/if (lastEventEnv == mode) return 1; if (ownRead) return ownEnv == mode;/'
mhead "the last event on every display when not read" 's/return onMain && lastEventEnv == mode;/return lastEventEnv == mode;/'
mhead "the App Switcher read as Home" 's/MSBDSMOwnEnvIs\(ownRead, ownEnv, lastEventEnv, onMain, kMSBDEnvSwitcher\)/MSBDSMOwnEnvIs(ownRead, ownEnv, lastEventEnv, onMain, kMSBDEnvHome)/'
[ $fails = 0 ] && echo "test-smbarhome: all passed" || { echo "test-smbarhome: FAILED"; exit 1; }
