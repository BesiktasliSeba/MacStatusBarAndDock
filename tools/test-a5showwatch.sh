#!/bin/bash
# Mac test of Aerial 5's watch of a new window, as built (statusbar/StatusBar.x DMA5WatchSceneHost; no plain logic to run here, its wiring in text): a window kept
# invisible until its app's picture is in (DMA5HideUntilShown, alpha 0.02) is shown by this watch and by nothing else, so the watch must not end while the window is
# there. Asked among the current desktop's windows, first found, it ended at once for a restored window of another desktop (DMMSWNewStage marks it away first) and for a
# window opened again while the one it replaces was still on its way out: invisible for good, a real Dock tap did not bring it back (M1, Aerial 5.1, 5 Nov).
cd "$(dirname "$0")"
S=../statusbar/StatusBar.x
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$S"; }
WATCH='static void DMA5WatchSceneHost(UIView *stage, NSString *bundle, int tick, CFTimeInterval readyAt) {'
ADOPT='static void DMAerial5AdoptNewStage(UIView *stage) {'
SHOW='static void DMA5ShowNow(UIView *stage, NSString *why) {'
HIDE='static void DMA5HideUntilShown(UIView *stage) {'
check "the watch looks its window up among every desktop's windows, and takes the last, back to front" \
  "fn '$WATCH' | grep -qF 'for (UIView *s in DMAerialStagesAll()) if ([DMStageBundle(s) isEqualToString:bundle]) mine = s;'"
check "  ... that lookup ends no watch: only a close does, nothing else returns before the wait's mark is dealt with (the one it replaces raised over a reopened window, on its way out: review 1.8.1.2, finding 3)" \
  "fn '$WATCH' | grep -qF 'if (!stage.superview || [objc_getAssociatedObject(stage, kStageClosingKey) boolValue]) return;' \
   && [ \"\$(fn '$WATCH' | sed -n '1,/DMA5HasSceneHostView(stage)) {/p' | grep -c 'return;')\" = 2 ] \
   && ! fn '$WATCH' | grep -qF 'DMStageForBundle('"
check "  ... the lookup comes before anything else the watch does" \
  "[ \"\$(fn '$WATCH' | grep -nF 'mine = s;' | cut -d: -f1)\" -lt \"\$(fn '$WATCH' | grep -nF 'CACurrentMediaTime()' | head -1 | cut -d: -f1)\" ]"
check "a window on another desktop, or with another window of its app in front of it, goes on being watched, once a second, and is opened again only once it is back" \
  "fn '$WATCH' | grep -qF 'BOOL away = mine != stage || DMStageMinimized(stage) || [objc_getAssociatedObject(stage, kMSWAwayKey) boolValue] || stage.alpha < 0.01;' \
   && [ \"\$(fn '$WATCH' | grep -nF 'if (away) {' | cut -d: -f1)\" -lt \"\$(fn '$WATCH' | grep -nF 'closeAerialForBundle:' | cut -d: -f1)\" ]"
check "its picture in and drawn shows it, with or without its desktop: alpha is what the watch owes, hidden is the desktop's" \
  "fn '$WATCH' | grep -qF 'if (content == 2 || now - since.doubleValue > 20.0) { DMA5ShowNow(stage,' \
   && fn '$WATCH' | grep -qF 'if (since && now - since.doubleValue > 20.0) DMA5ShowNow(stage,' \
   && ! fn '$SHOW' | grep -qF 'stage.hidden' && ! fn '$SHOW' | grep -qF 'kMSWAwayKey'"
check "the wait's mark and the alpha are set together, and only DMA5ShowNow lets it go" \
  "fn '$HIDE' | grep -qF 'objc_setAssociatedObject(stage, kA5WaitShowKey, @(CACurrentMediaTime())' && fn '$HIDE' | grep -qF 'stage.alpha = 0.02;' \
   && fn '$SHOW' | grep -qF 'objc_setAssociatedObject(stage, kA5WaitShowKey, nil' && [ \"\$(grep -cF 'kA5WaitShowKey, nil' $S)\" = 1 ]"
check "a new window: marked away first, then watched, then kept invisible (a restored one) or kept invisible, then watched (one opened again)" \
  "[ \"\$(fn '$ADOPT' | grep -nF 'DMMSWNewStage(stage, bundle);' | cut -d: -f1)\" -lt \"\$(fn '$ADOPT' | grep -nF 'DMA5WatchSceneHost(stage, bundle, 0, 0);' | head -1 | cut -d: -f1)\" ] \
   && [ \"\$(fn '$ADOPT' | grep -cF 'DMA5HideUntilShown(stage);')\" = 2 ] && [ \"\$(fn '$ADOPT' | grep -cF 'DMA5WatchSceneHost(stage, bundle, 0, 0);')\" = 2 ]"
[ $fails = 0 ] && echo "test-a5showwatch: site checks pass" || { echo "test-a5showwatch: site checks FAILED"; exit 1; }
