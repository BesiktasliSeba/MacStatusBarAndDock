#!/bin/bash
# Mac test of the Home Screen's swipe down and a pointer's scroll (KT, 1.8.2: "if i slide two fingers down on trackpad on the homescreen behind the
# window app library should not launch"): a trackpad's two-finger scroll moves the Home Screen search view's pan as a finger does, so Swipe Down
# Opens App Library opened the App Library for it beside a window too. With a window of ours on screen a pointer's scroll down is nothing now; a
# finger, and a scroll with no window shown, as before (dock/SwipeDownRule.h, test-swipescroll.c). Then the wiring as built (dock/Dock.x, the
# window check in statusbar/StatusBar.x), and Settings > Dock's Magnification footer (1.8.2 item 1).
set -e
cd "$(dirname "$0")"
K=../dock/Dock.x; L=../dock/SwipeDownRule.h; S=../statusbar/StatusBar.x; P=../dock/dockmagnificationprefs/Resources/Root.plist
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
clang -O2 -Wall -Wno-unused-function -o "$W/tss" test-swipescroll.c && "$W/tss" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
# the search view's hook (the file's default one, not SwipeUpFix's): from its first line to its %end
hook() { awk '/^%hook SBSearchScrollView/{n++} n==2{print} n==2&&/^%end/{exit}' "$K"; }
fns() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
check "the rule is the header's (the Mac test runs the same code): a pan with no touch is a pointer's scroll; beside a window of ours it is not the swipe down" \
  "grep -q '^#import \"SwipeDownRule.h\"' $K \
   && grep -q '^static inline int DMPanIsPointerScroll(unsigned long touches, int scrollAskable, int scrollEvent) { return scrollAskable ? scrollEvent != 0 : touches == 0; }' $L \
   && grep -q '^static inline int DMSwipeDownTakesPan(unsigned long touches, int scrollAskable, int scrollEvent, int windowOnScreen) { return !(DMPanIsPointerScroll(touches, scrollAskable, scrollEvent) && windowOnScreen); }' $L"
check "  ... what drives the pan asked of it in release builds too: UIKit's scroll event, shape-checked (code review 1.8.2, 13: a finger's deferred pan holds no touch once it has lifted)" \
  "hook | grep -q 'BOOL askable = aem && !strcmp(method_getTypeEncoding(aem) ?: \"\", \"@24@0:8q16\");' && hook | grep -q 'id scroll = askable ? ((id (\\*)(id, SEL, long long))objc_msgSend)(gesture, ae, 10) : nil;' \
   && hook | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /BOOL askable = aem/{if (d) bad=1; n++} END{exit !(n == 1 && !bad)}'"
check "the swipe down's own hook asks it, for a downward pan it would take (switch on, Spotlight button shown), after the top edge's pull and before the App Library is presented" \
  "hook | grep -q 'if (gSwipeDownOpensLibrary && DMSpotlightButtonShown() && \\[gesture isKindOfClass:\\[UIPanGestureRecognizer class\\]\\] &&' \
   && hook | awk '/if \\(CACurrentMediaTime\\(\\) - gTopPullAt < 0.5\\)/{a=NR} /if \\(!DMSwipeDownTakesPan\\(gesture.numberOfTouches, askable, scroll != nil, DMOurWindowOnScreen\\(\\)\\) && !DMSwipeScrollOld\\(\\)\\)/{b=NR} /if \\(DMPresentAppLibrary\\(\\)\\)/{c=NR} END{exit !(a && b > a && c > b)}'"
check "  ... and then does nothing: NO, so neither the App Library nor Spotlight's pull begins; its feature marker in release builds too" \
  "hook | awk '/if \\(!DMSwipeDownTakesPan\\(gesture.numberOfTouches, askable, scroll != nil, DMOurWindowOnScreen\\(\\)\\) && !DMSwipeScrollOld\\(\\)\\)/{f=1} f&&/DM_FEATURE_MARK\\(\"swipe-down-scroll-beside-window\"\\);/{m=1} f&&/^            return NO;/{r=1} f&&/^        \\}/{exit} END{exit !(m && r)}' \
   && hook | awk '/^#if DEBUG/{d=1} /^#endif/{d=0} /DM_FEATURE_MARK\\(\"swipe-down-scroll-beside-window\"\\)/{if (d) bad=1; n++} END{exit !(n == 1 && !bad)}'"
check "  ... only there: paging left and right (the icon scroll view's own pan), the swipe up, the last page and the finger's paths do not ask it" \
  "[ \$(grep -c 'DMSwipeDownTakesPan(' $K) = 1 ] && [ \$(grep -c 'DMOurWindowOnScreen()' $K | tr -d ' ') -ge 2 ] \
   && ! awk '/^%group SwipeUpFix/{f=1} f&&/DMSwipeDownTakesPan|DMOurWindowOnScreen/{bad=1} f&&/^%end/&&++e==2{exit} END{exit !bad}' $K \
   && ! grep -n 'DMSwipeDownTakesPan\\|DMOurWindowOnScreen' $K | grep -q -i 'IconScrollView\\|FolderScrollView\\|Overscroll\\|TrailingPage'"
check "  ... the debug builds' comparison switch (/tmp/msb-swipescroll-old: as before 1.8.2) is not in release builds: there it always answers NO" \
  "awk '/^#if DEBUG/{d=1; next} /^#else/{if (d) e=1; next} /^#endif/{d=0; e=0; next} d&&!e&&/^static BOOL DMSwipeScrollOld\\(void\\) \\{ return access\\(\"\\/tmp\\/msb-swipescroll-old\", F_OK\\) == 0; \\}/{a=1} e&&/^static BOOL DMSwipeScrollOld\\(void\\) \\{ return NO; \\}/{b=1} END{exit !(a && b)}' $K"
check "a window of ours is MacStatusBar's answer, found with dlsym (it may load after the Dock; without it, no window of ours)" \
  "awk '/^static BOOL DMOurWindowOnScreen\\(void\\) \\{/{f=1} f&&/dlsym\\(RTLD_DEFAULT, \"MSBDWindowOnScreen\"\\)/{a=1} f&&/return shown && shown\\(\\);/{b=1} f&&/^}/{exit} END{exit !(a && b)}' $K"
check "MacStatusBar's answer: the engine's windows on the desktop shown (Stage Manager's window keys, else the top shown stage of Aerial, Zetsu, MilkyWay4), or a native window while their layer is shown; on the iPad's own screen only (code review 1.8.2, 13)" \
  "grep -q '^__attribute__((visibility(\"default\"))) BOOL MSBDWindowOnScreen(void) {' $S \
   && fns '__attribute__((visibility(\"default\"))) BOOL MSBDWindowOnScreen(void) {' | grep -q 'if (DMSMEngine() ? DMSMWindowKeysOn(main).count > 0 : DMTopStageOn(main) != nil) return YES;' \
   && fns '__attribute__((visibility(\"default\"))) BOOL MSBDWindowOnScreen(void) {' | grep -q 'if (!gNativeLayer || gNativeLayer.hidden || gNativeAway || DMSnapScreenOf(gNativeLayer) != main) return NO;' \
   && fns '__attribute__((visibility(\"default\"))) BOOL MSBDWindowOnScreen(void) {' | grep -q 'for (DMNativeWindow \\*w in gNativeWindows) if (!w.hidden) return YES;'"
check "  ... minimized, hidden and closing stages and full-screen Stage Manager windows are not windows on screen (the helpers it asks leave them out), nor those on another screen" \
  "fns 'static UIView *DMTopStageOn(UIScreen *screen) {' | grep -q 'if (!s.hidden && s.alpha > 0.05 && !DMStageMinimized(s) && DMStageBundle(s).length && !\\[objc_getAssociatedObject(s, kStageClosingKey) boolValue\\] && (!screen || DMSnapScreenOf(s) == screen)) top = s;' \
   && fns 'static NSArray<NSString *> *DMSMWindowKeysOn(UIScreen *screen) {' | grep -q 'if (k && card.window && !card.window.hidden && card.alpha > 0.01 && !DMSMCardIsFullSize(card) && (!screen || DMSnapScreenOf(card) == screen)) \\[out addObject:k\\];' \
   && grep -q '^static UIView \\*DMTopStage(void) { return DMTopStageOn(nil); }' $S && grep -q '^static NSArray<NSString \\*> \\*DMSMWindowKeys(void) { return DMSMWindowKeysOn(nil); }' $S"
check "Settings > Dock: the Magnification group's footer says it needs a trackpad or mouse (no em dash, never MacDock)" \
  "plutil -convert json -o - $P | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=[n for n,x in enumerate(it) if x.get(\"cell\")==\"PSGroupCell\" and x.get(\"label\")==\"Magnification\"]; f=it[g[0]].get(\"footerText\",\"\") if len(g)==1 else \"\"; sys.exit(0 if f==\"Magnification shows with a trackpad or mouse.\" and it[g[0]+1].get(\"key\")==\"enabled\" and it[g[0]+2].get(\"key\")==\"magnification\" and \"\\u2014\" not in f and \"MacDock\" not in f else 1)'"
[ $fails = 0 ] && echo "test-swipescroll: all checks pass" || { echo "test-swipescroll: checks FAILED"; exit 1; }
