#!/bin/bash
# test-airpodsownicon.sh: our own headphones icon where iPadOS draws no item for connected headphones (1.8.8.2). iPadOS 15.6.1 shows no
# Bluetooth item at all for real AirPods, so the AirPods button over iPadOS's item (1.8.8.1.1) had nothing to sit on there: the bar now draws a
# headphones icon of its own where the status icons start, the same button over it, never two icons (common/AirPodsMenu.h MSBDAirPodsOwnIcon,
# statusbar/AirPodsMenu.h DMAirPodsLayoutOwnIcon). The review: never on 17/18 (SpringBoard draws its own glyph for them there), and on 15/16
# only once the headphones have been connected a moment (iPadOS's own item first, where it draws one); the count follows Bluetooth's power and
# the manager's attach too.
#  (1) the rules (plain C, -Wall -Wextra -Werror): when our icon shows, which connected devices count as headphones;
#  (2) the wiring: StatusBar.x lays it out right after the battery's button and before our Wi-Fi icon, with its key in the colour, narrow-copy
#      lists; AirPodsMenu.h: the button lets go of it when iPadOS's item shows, the Lock Screen's layout hides it, Bluetooth's events are
#      watched from the first layout (on the next main-queue turn, no timer), the sources once, the headphones counted by the rule, the debug
#      fake's "no item" shape (podfake_bar_none), the crash guard's names;
#  then made-to-fail copies, each must fail. Its behaviour in the bar (place, button, never two icons, the switch, the Lock Screen, right to
#  left, one line per showing) is checked by test-airpodsmenu.m (OwnIconRows) on the real code.
# AO_ROOT: another tree (e.g. the code before it): run on it, no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${AO_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
nocomments() { sed -E 's://.*$::' "$1"; }
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
ifdebug() {   # $1 file, $2 text: is every line holding it inside an "#if DEBUG" (not its #else)?
  awk -v s="$2" '
    /^#if DEBUG/ { st[++n] = 1; next } /^#if/ { st[++n] = 0; next } /^#else/ { if (st[n] == 1) st[n] = 2; next } /^#endif/ { n--; next }
    index($0, s) { seen = 1; ok = 0; for (i = 1; i <= n; i++) if (st[i] == 1) ok = 1; if (!ok) bad = 1 }
    END { print (seen && !bad) ? "yes" : "no" }
  ' "$1"
}

# ---- (1) the rules ----
plainc() {   # $1 common/AirPodsMenu.h, $2 dir, $3 quiet: rc
  mkdir -p "$2/common"
  cp "$1" "$2/common/AirPodsMenu.h" 2>/dev/null || { [ -n "$3" ] || echo "FAIL  no common/AirPodsMenu.h"; return 1; }
  cat > "$2/t.c" <<'C'
#include <stdio.h>
#include <string.h>
#include "common/AirPodsMenu.h"
static int fails, checks;
static void ck(int ok, const char *what) { checks++; if (!ok) fails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what); }
int main(void) {
    ck(MSBDAirPodsOwnIcon(1, 0, 1, 0, 1, 60), "rule: the switch on, UIKit's bar (15/16), iPadOS's item read with none of its views shown, headphones connected: our icon");
    ck(MSBDAirPodsOwnIcon(1, 0, 1, 0, 2, 60), "  ... two sets of headphones: one icon of ours (it is a yes or no)");
    ck(!MSBDAirPodsOwnIcon(0, 0, 1, 0, 1, 60), "  ... AirPods Menu off: none");
    ck(!MSBDAirPodsOwnIcon(1, 0, 0, 0, 1, 60), "  ... iPadOS's item not readable here (its class does not answer): none (never two icons)");
    ck(!MSBDAirPodsOwnIcon(1, 0, 1, 1, 1, 60) && !MSBDAirPodsOwnIcon(1, 0, 1, 2, 1, 60), "  ... any view of iPadOS's item shown (headphones, or a plain Bluetooth indicator): none");
    ck(!MSBDAirPodsOwnIcon(1, 0, 1, 0, 0, 60), "  ... no headphones connected: none");
    ck(!MSBDAirPodsOwnIcon(1, 1, 1, 0, 1, 60) && !MSBDAirPodsOwnIcon(1, 1, 1, 0, 2, 1e9),
       "  ... SystemStatusUI's bar (17/18), where SpringBoard draws its own glyph for them: none, however long they are connected (review)");
    ck(!MSBDAirPodsOwnIcon(1, 0, 1, 0, 1, 0) && !MSBDAirPodsOwnIcon(1, 0, 1, 0, 1, MSBD_AP_OWN_SETTLE - 0.05) && MSBDAirPodsOwnIcon(1, 0, 1, 0, 1, MSBD_AP_OWN_SETTLE)
       && MSBD_AP_OWN_SETTLE >= 1.0 && MSBD_AP_OWN_SETTLE <= 3.0,
       "  ... 15/16: only once they have been connected MSBD_AP_OWN_SETTLE s (1 to 3 s), so iPadOS's own item shows first where it draws one (review)");
    ck(MSBDAirPodsCountsAsHeadphones(1, MSBD_AP_BT_TYPE_HEADSET, 0) && MSBDAirPodsCountsAsHeadphones(1, MSBD_AP_BT_TYPE_HEADPHONES, 1),
       "headphones: iPadOS's own types 16 and 20, Apple's or not");
    ck(!MSBDAirPodsCountsAsHeadphones(1, 0, 0) && !MSBDAirPodsCountsAsHeadphones(1, 0, 1) && !MSBDAirPodsCountsAsHeadphones(1, 5, 0),
       "  ... another type read: not headphones, even an Apple audio device (iPadOS's rule decides where it can be asked)");
    ck(MSBDAirPodsCountsAsHeadphones(0, 0, 1) && !MSBDAirPodsCountsAsHeadphones(0, 0, 0), "  ... the type not readable here: Apple's audio devices only");
    ck(MSBDAirPodsListsDevice(1, 1, 1, 0) && !MSBDAirPodsCountsAsHeadphones(1, 0, 0), "  ... a device the menu lists only for its battery level (a keyboard) is not headphones");
    printf("test-airpodsownicon (plain C): %d checks, %d fail\n", checks, fails);
    return fails ? 1 : 0;
}
C
  clang -O2 -Wall -Wextra -Werror -I"$2" -o "$2/t" "$2/t.c" > "$2/cc.txt" 2>&1 || { [ -n "$3" ] || { head -20 "$2/cc.txt"; echo "FAIL  the rules did not build"; }; return 1; }
  if [ -n "$3" ]; then "$2/t" > /dev/null; else "$2/t"; fi
}

# ---- (2) the wiring ----
pins() {   # $1 StatusBar.x, $2 statusbar/AirPodsMenu.h, $3 crashmap-rules.txt, $4 quiet: the number that fail
  local X=$1 A=$2 R=$3 q=$4 n=0
  ok() { [ -n "$q" ] || echo "PASS  $1"; }
  no() { [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); }
  ck() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
  ck "StatusBar.x: the icon's key next to the button's" "grep -qxF 'static const void *kAirPodsIconKey = &kAirPodsIconKey;   // (our own headphones icon where iPadOS shows no item for them, 1.8.8.2: AirPodsMenu.h DMAirPodsLayoutOwnIcon)' $X"
  ck "  ... laid out after the AirPods button and the battery's (the status icons' start as they left it), right before our Wi-Fi icon, which follows its left edge" \
     "awk 'index(\$0, \"        DMBattLayoutButton(fg, left, k);\") == 1 { a = NR } index(\$0, \"        left = DMAirPodsLayoutOwnIcon(fg, left, timeCentre.y, k);\") == 1 { b = NR } index(\$0, \"        left = DMWiFiLayoutIcon(fg, left, timeCentre.y, k);\") == 1 { c = NR } END { exit !(a && b > a && c == b + 3) }' $X"
  ck "  ... called once" "[ \$(nocomments $X | grep -c 'DMAirPodsLayoutOwnIcon(') = 1 ]"
  ck "  ... drawn in the bar's colour with our other icons (DMApplyBarItemColor)" \
     "fn $X 'static void DMApplyBarItemColor(' | grep -qF '        UIView *v = objc_getAssociatedObject(fg, kAirPodsIconKey);' && fn $X 'static void DMApplyBarItemColor(' | grep -A1 -F 'objc_getAssociatedObject(fg, kAirPodsIconKey);' | grep -qF '![v.tintColor isEqual:c]) v.tintColor = c;'"
  ck "  ... hidden with our other views in a collapsed copy (right after the Live Activities' pills)" \
     "awk 'index(\$0, \"        ((UIView *)objc_getAssociatedObject(fg, kAirPodsIconKey)).hidden = YES;\") == 1 { n++; if (index(prev, \"        DMLAHidePills(fg);\") == 1) ok++ } { prev = \$0 } END { exit !(n == 1 && ok == 1) }' $X"
  ck "AirPodsMenu.h: the layout entry point stays a function of its own in a release build (noinline), returns the next left edge" \
     "grep -qxF '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(UIView *fg, CGFloat left, CGFloat midY, CGFloat k) {' $A"
  ck "  ... shown only by the rule, on this copy's reading of iPadOS's item, at the Wi-Fi fan's height" \
     "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF 'MSBDAirPodsOwnIcon(gAirPodsMenuOn, drawsOwn, seen != nil, seen.intValue, gAPHeadphonesOn, CACurrentMediaTime() - gAPHeadphonesSince)' && fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qxF '        ? DMAPOwnGlyph(DMWiFiIconHeight(k)) : nil;'"
  ck "  ... never on SystemStatusUI's bar (17/18): the rule told by DMSBUseSTUI(), and nothing of it started there from the layout (review)" \
     "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qxF '    BOOL drawsOwn = DMSBUseSTUI();' && fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qxF '    if (gAirPodsMenuOn && !drawsOwn && !gAPWatchStarted) {'"
  ck "  ... the wait: the count's rise from none noted, and the bars laid out once after it (one dispatch_after, no repeating timer) (review)" \
     "fn $A 'static void DMAPOwnRefresh(' | awk 'index(\$0, \"    if (!gAPHeadphonesOn) {\") == 1 { a = NR } index(\$0, \"        gAPHeadphonesSince = CACurrentMediaTime();\") == 1 && a && NR == a + 1 { b = NR } index(\$0, \"        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MSBD_AP_OWN_SETTLE + 0.1) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout]; });\") == 1 && b && NR == b + 1 { c = NR } index(\$0, \"    gAPHeadphonesOn = n;\") == 1 && c { d = NR } END { exit !(a && b && c && d) }'"
  ck "  ... the count follows Bluetooth turned off or on and the manager's attach (BluetoothManager's own notifications) (review)" \
     "fn $A 'static void DMAPWatchStart(' | grep -qF '@\"BluetoothPowerChangedNotification\", @\"BluetoothAvailabilityChangedNotification\"])'"
  ck "  ... the button over it is the AirPods button (the one opener, DMOpenAirPodsMenu)" \
     "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF '    UIButton *btn = DMAPButton(fg);' && fn $A 'static UIButton *DMAPButton(' | grep -qF 'DMOpenAirPodsMenu(weakBtn)' && fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF '    UIButton *btn = DMAPButton(fg);'"
  ck "  ... iPadOS's item reading kept per copy by the button's layout, before any return" \
     "fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF '{ DMAPItemSeen(fg, nil); DMAPHideButton(fg); return; }' && fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF '    DMAPItemSeen(fg, @(views.count));'"
  ck "  ... never two icons: the button lets go of our icon when iPadOS's item shows, and leaves the button to it while no item view shows" \
     "fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF '    if (DMAPOwnHolds(fg)) DMAPOwnLetGo(fg, NO);' && fn $A '__attribute__((noinline)) static void DMAirPodsLayoutButton(' | grep -qF '{ if (!views.count && DMAPOwnHolds(fg)) return; DMAPHideButton(fg); return; }'"
  ck "  ... the Lock Screen's layout hides it (iPadOS's own Lock Screen)" \
     "grep -qxF '__attribute__((noinline)) static void DMAirPodsLockLayout(UIView *fg) { DMAPHideButton(fg); DMAPItemSeen(fg, nil); DMAPOwnLetGo(fg, YES); }' $A"
  ck "  ... not a VoiceOver element itself (the button is read: Headphones)" "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF '        icon.isAccessibilityElement = NO;'"
  ck "  ... Bluetooth's events watched from the first layout with the switch on, on the next main-queue turn, once" \
     "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF 'if (!asked) { asked = YES; dispatch_async(dispatch_get_main_queue(), ^{ DMAPWatchStart(); }); }' && [ \$(nocomments $A | grep -c 'DMAPWatchStart();') = 2 ] && fn $A 'static void DMAPWatchStart(' | grep -qF '    if (gAPWatchStarted) return;'"
  ck "  ... the Bluetooth notifications registered in DMAPWatchStart only (DMAPStartSources starts it), never twice" \
     "[ \$(nocomments $A | grep -c 'BluetoothDeviceConnectSuccessNotification') = 1 ] && fn $A 'static void DMAPWatchStart(' | grep -qF 'BluetoothDeviceConnectSuccessNotification' && fn $A 'static void DMAPStartSources(' | grep -qF '    DMAPWatchStart();'"
  ck "  ... every Bluetooth event, open menu or not, counts the headphones again (DMAPSourceSaid before its open-menu return)" \
     "fn $A 'static void DMAPSourceSaid(' | awk 'index(\$0, \"    if (headsets) DMAPOwnRefresh();\") == 1 { a = NR } index(\$0, \"    if (!gAPMenuOpen) return;\") == 1 { b = NR } END { exit !(a && b == a + 1) }'"
  ck "  ... the headphones counted by the rule, the bars laid out again only when the count changes" \
     "fn $A 'static NSArray<DMAPHeadsetRec *> *DMAPReadHeadsets(' | grep -qF '            h.phones = MSBDAirPodsCountsAsHeadphones(typeRead, type, h.apple);' && fn $A 'static void DMAPOwnRefresh(' | grep -qF '    if (n == gAPHeadphonesOn) return;'"
  ck "  ... no timer, no hook in it" "! nocomments $A | grep -qE 'NSTimer|%hook|MSHookMessageEx'"
  ck "  ... the menu's sources once, at its first showing, outside the layout pass" \
     "fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF '        dispatch_async(dispatch_get_main_queue(), ^{ DMAPStartSources(); });' && fn $A '__attribute__((noinline)) static CGFloat DMAirPodsLayoutOwnIcon(' | grep -qF '    if (!gAPSourcesStarted) {'"
  ck "the debug fake: podfake_bar_none, debug only, shows no item of iPadOS's for the made-up headphones" \
     "[ \"\$(ifdebug $A 'gAPFakeNoItem')\" = yes ] && fn $A 'static void DMAPFakeShowItem(' | grep -qF 'if (!on || !gAPFake || gAPFakeNoItem) { DMAPFakeBarItem(@\"off\"); return; }' && grep -qF 'gAPFakeNoItem = [[cmd substringFromIndex:12] isEqualToString:@\"none\"];' $A"
  ck "  ... the made-up headphones count as headphones" "fn $A 'static DMAPHeadsetRec *DMAPFakeHeadset(' | grep -qF 'h.phones = YES;'"
  ck "the crash guard: its new names are the AirPods Menu's (the sym rule)" \
     "python3 -I -c \"import re,sys; rx=[re.compile(l.split()[2]) for l in open('$R') if l.startswith('sym MacStatusBarCore') and l.split()[3]=='airpodsMenu']; n=['_DMAirPodsLayoutOwnIcon','_DMAPOwnGlyph','_DMAPWatchStart','_DMAPOwnRefresh','_DMAPOwnLetGo','_DMAPButton','___DMAirPodsLayoutOwnIcon_block_invoke','___DMAPWatchStart_block_invoke','_MSBDAirPodsOwnIcon']; sys.exit(0 if rx and all(any(r.search(x) for r in rx) for x in n) else 1)\""
  ck "no em or en dash in its code or this test" "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $A test-airpodsownicon.sh"
  return $n
}

X0=$R0/statusbar/StatusBar.x; A0=$R0/statusbar/AirPodsMenu.h; C0=$R0/common/AirPodsMenu.h; RR0=$R0/tools/crashmap-rules.txt
echo "== (1) the rules (plain C)"
plainc "$C0" "$W/c" "" || fails=1
echo "== (2) the wiring"
pins "$X0" "$A0" "$RR0" "" || fails=1

if [ -z "$AO_ROOT" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mk() {   # $1 what, $2 file key (X A C), $3 perl substitution
    local src; case $2 in X) src=$X0;; A) src=$A0;; C) src=$C0;; esac
    local d="$W/m"; rm -rf "$d"; mkdir -p "$d"; cp "$src" "$d/f"
    perl -0pi -e "$3" "$d/f"
    cmp -s "$d/f" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; fails=1; return; }
    local x=$X0 a=$A0 c=$C0 n=0
    case $2 in X) x=$d/f;; A) a=$d/f;; C) c=$d/f;; esac
    plainc "$c" "$d/c" q || n=$((n + 1))
    pins "$x" "$a" "$RR0" q; n=$((n + $?))
    if [ $n -gt 0 ]; then echo "PASS  caught: $1 ($n)"; else echo "FAIL  not caught: $1"; fails=1; fi
  }
  mk "rule: our icon beside a shown view of iPadOS's item" C 's/ && itemViewsShown == 0 && headphones > 0 / \&\& headphones > 0 /'
  mk "rule: our icon where iPadOS's item cannot be read" C 's/ && itemReadable && itemViewsShown == 0/ \&\& itemViewsShown == 0/'
  mk "rule: our icon on 17/18 too (review)" C 's/return menuOn && !barDrawsHeadphones && /return menuOn \&\& /'
  mk "rule: no wait after the headphones come (review)" C 's/ && connectedFor >= MSBD_AP_OWN_SETTLE;/;/'
  mk "the layout tells the rule UIKit's bar everywhere (review)" A 's/MSBDAirPodsOwnIcon\(gAirPodsMenuOn, drawsOwn, /MSBDAirPodsOwnIcon(gAirPodsMenuOn, NO, /'
  mk "Bluetooth's events watched from the layout on 17/18 too (review)" A 's/    if \(gAirPodsMenuOn && !drawsOwn && !gAPWatchStarted\) \{/    if (gAirPodsMenuOn \&\& !gAPWatchStarted) {/'
  mk "the rise not noted (review)" A 's/        gAPHeadphonesSince = CACurrentMediaTime\(\);\n//'
  mk "no layout after the wait (review)" A 's/        dispatch_after\(dispatch_time\(DISPATCH_TIME_NOW, \(int64_t\)\(\(MSBD_AP_OWN_SETTLE \+ 0\.1\)[^\n]*\n//'
  mk "Bluetooth's power and availability not followed (review)" A 's/, \@"BluetoothPowerChangedNotification", \@"BluetoothAvailabilityChangedNotification"\]/]/'
  mk "rule: any listed device counted as headphones" C 's/return typeRead \? MSBDAirPodsIsHeadphonesType\(typeRead, type\) : appleAudio != 0;/return 1;/'
  mk "not laid out" X 's/        left = DMAirPodsLayoutOwnIcon\(fg, left, timeCentre\.y, k\);\n//'
  mk "laid out after our Wi-Fi icon" X 's/(        \/\/ Our own headphones icon[^\n]*\n        left = DMAirPodsLayoutOwnIcon\(fg, left, timeCentre\.y, k\);\n)([^\n]*\n[^\n]*\n        left = DMWiFiLayoutIcon\(fg, left, timeCentre\.y, k\);\n)/$2$1/'
  mk "not in the bar's colour" X 's/(    \{   \/\/ \(our own headphones icon, as our other icons[^\n]*\n        UIView \*v = objc_getAssociatedObject\(fg, kAirPodsIconKey\);\n)[^\n]*\n/$1/'
  mk "not hidden in a collapsed copy" X 's/        \(\(UIView \*\)objc_getAssociatedObject\(fg, kAirPodsIconKey\)\)\.hidden = YES;[^\n]*\n//'
  mk "two icons: the button does not let go of ours" A 's/    if \(DMAPOwnHolds\(fg\)\) DMAPOwnLetGo\(fg, NO\);[^\n]*\n//'
  mk "the button hidden and shown again at every layout" A 's/\{ if \(!views\.count && DMAPOwnHolds\(fg\)\) return; DMAPHideButton\(fg\); return; \}/{ DMAPHideButton(fg); return; }/'
  mk "shown on the Lock Screen" A 's/ DMAPItemSeen\(fg, nil\); DMAPOwnLetGo\(fg, YES\); \}/ }/'
  mk "Bluetooth's events watched in the layout pass" A 's/if \(!asked\) \{ asked = YES; dispatch_async\(dispatch_get_main_queue\(\), \^\{ DMAPWatchStart\(\); \}\); \}/if (!asked) { asked = YES; DMAPWatchStart(); }/'
  mk "the notifications registered twice" A 's/(    DMAPWatchStart\(\);   \/\/ \(Bluetooth)/    [nc addObserverForName:\@"BluetoothDeviceConnectSuccessNotification" object:nil queue:nil usingBlock:^(NSNotification *note) {}];\n$1/'
  mk "the count only while the menu is open" A 's/    if \(headsets\) DMAPOwnRefresh\(\);[^\n]*\n//'
  mk "a timer" A 's/(static int gAPHeadphonesOn = 0;)/$1\nstatic NSTimer *gAPOwnTimer = nil;/'
  mk "the made-up item still shown for _none" A 's/if \(!on \|\| !gAPFake \|\| gAPFakeNoItem\) \{/if (!on || !gAPFake) {/'
  mk "noinline off" A 's/__attribute__\(\(noinline\)\) static CGFloat DMAirPodsLayoutOwnIcon\(/static CGFloat DMAirPodsLayoutOwnIcon(/'
fi
[ $fails = 0 ] && echo "test-airpodsownicon: all pass" || { echo "test-airpodsownicon: FAILED"; exit 1; }
