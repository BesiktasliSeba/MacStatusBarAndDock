#!/bin/bash
# Mac test of the display a switcher gesture belongs to (1.8.7, iPad 2 16.7.7 d41 07:46:54: a pointer push at the TV's bottom edge with no TV stage
# under it, while the iPad showed a window, crashed SpringBoard into Safe Mode). The Stage Manager engine's "the gesture takes the desktop on screen"
# (statusbar/SMGestureHook.h DMSMGestureTakes) gives SpringBoard the iPad's stage only for the iPad's own gesture; another display's keeps
# SpringBoard's own pick. The rule (test-smgesturedisplay.c on the code as built), the reads and the hook (site checks), then made-to-fail copies.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=../statusbar/SMGestureHook.h
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }
rule() {   # rule <SMGestureHook.h> <dir>: the C test built on that file's rule; its exit code
  mkdir -p "$2"; fn "$1" 'static BOOL DMSMGestureTakesOnIPad(int controller, int request, int screen, BOOL otherDisplay) {' > "$2/smgesturedisplay-gen.h"
  [ -s "$2/smgesturedisplay-gen.h" ] || { echo "FAIL  the rule is not in this source"; return 1; }
  clang -Wall -Werror -Wno-unused-function -I"$2" -o "$2/t" test-smgesturedisplay.c || return 2
  "$2/t"
}
sites() {   # sites <SMGestureHook.h>: 0 when every site is as it must be
  local h="$1" f=0
  c() { if eval "$2"; then [ -n "$Q" ] || echo "PASS  $1"; else [ -n "$Q" ] || echo "FAIL  $1"; f=1; fi; }
  fn "$h" 'static id DMSMGestureTakes(id self, SEL _cmd, id recognizer) {' > "$W/takes"
  c "the hook reads the gesture's display (its switcher, its request's display, its recognizer's screen) and asks the rule" \
    "grep -qF 'int ctl = DMSMGestureReadController(self), req = DMSMGestureReadRequest(self), scr = DMSMGestureReadScreen(recognizer);' $W/takes \
     && grep -qF 'BOOL other = DMSMGestureOtherDisplay();' $W/takes && grep -qF 'if (!DMSMGestureTakesOnIPad(ctl, req, scr, other)) {' $W/takes"
  c "  ... another display's gesture: SpringBoard's own pick, before the iPad's stage is read or given (the only return of the desktop after it)" \
    "awk '/if \\(!DMSMGestureTakesOnIPad\\(ctl, req, scr, other\\)\\) \\{/{a=NR} a && !r && /            return taken;/{r=NR} /id desk = DMSMShownMainStage\\(\\);/{d=NR} /return desk;/{n++; g=NR} END{exit !(a && r > a && d > r && n == 1 && g > d)}' $W/takes"
  c "the switcher read: the transaction's -switcherController, matched to a window scene's switcher (the coordinator's), that scene's screen" \
    "fn $h 'static int DMSMGestureReadController(id tx) {' > $W/rc && grep -qF 'NSSelectorFromString(@\"switcherController\")' $W/rc && grep -qF 'DMSMSigOK(tx, s, DMSMSigObj(), \"switcherController\")' $W/rc \
     && grep -qF '((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, sc) != its) continue;' $W/rc && grep -qF 'return !on ? -1 : (on == [UIScreen mainScreen] ? 1 : 0);' $W/rc"
  c "the request read: -transitionRequest's -displayConfiguration identity, the iPad's screen's or another screen's (else not read)" \
    "fn $h 'static int DMSMGestureReadRequest(id tx) {' > $W/rr && grep -qF 'if ([ident isEqual:mainIdent]) return 1;' $W/rr \
     && grep -qF 'for (UIScreen *s in DMDispScreens()) if (s != [UIScreen mainScreen] && [ident isEqual:DMSMIdentityOfScreen(s)]) return 0;' $W/rr && grep -qF 'if (!ident || !mainIdent) return -1;' $W/rr"
  c "the screen read: the recognizer's window's screen" \
    "fn $h 'static int DMSMGestureReadScreen(id recognizer) {' | grep -qF '((UIGestureRecognizer *)recognizer).view.window.screen'"
  c "the hook is installed as before (the transaction's -selectedAppLayoutForGestureRecognizer:, its shape checked)" \
    "grep -qF 'if (m && [DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(id), @encode(id), NULL)]) MSHookMessageEx(t, s, (IMP)DMSMGestureTakes, (IMP *)&o_SMGestureTakes);' $h"
  return $f
}
fails=0
rule $H "$W/as-built" || fails=1
sites $H || fails=1
echo "-- made-to-fail copies (each must fail):"
mtf() {   # mtf <name> <rule|sites> <perl substitution>
  local d="$W/mtf$((++n))"; mkdir -p "$d"; cp $H "$d/SMGestureHook.h"; perl -0pi -e "$3" "$d/SMGestureHook.h"
  cmp -s $H "$d/SMGestureHook.h" && { echo "FAIL  made-to-fail copy $1: the change did not apply"; fails=1; return; }
  if [ "$2" = rule ]; then rule "$d/SMGestureHook.h" "$d" > "$d/out" 2>&1 && ok=1 || ok=0; else Q=1 sites "$d/SMGestureHook.h" && ok=1 || ok=0; fi
  if [ $ok = 1 ]; then echo "FAIL  made-to-fail copy $1 PASSED (it must fail)"; fails=1; else echo "PASS  made-to-fail copy $1 fails, as it must"; fi
}
n=0
mtf "1.8.6 / d41: the hook gives the iPad's stage to any display's gesture (no display check)" sites \
  's/        int ctl = DMSMGestureReadController\(self\).*?\n        \}\n(        id desk = DMSMShownMainStage\(\);)/$1/s'
mtf "the rule: a read of the iPad's wins over one of another display" rule \
  's/(    if \(controller == 0 \|\| request == 0 \|\| screen == 0\) return NO;\n)(    if \(controller == 1 \|\| request == 1 \|\| screen == 1\) return YES;\n)/$2$1/'
mtf "the rule: nothing read with a TV there takes the desktop" rule 's/    return !otherDisplay;/    return YES;/'
mtf "the rule: only the switcher read counts" rule 's/controller == 0 \|\| request == 0 \|\| screen == 0/controller == 0/'
mtf "the check after the iPad's stage is read" sites \
  's/(        int ctl = DMSMGestureReadController\(self\).*?\n        \}\n)(        id desk = DMSMShownMainStage\(\);[^\n]*\n)/$2$1/s'
[ $fails = 0 ] && echo "test-smgesturedisplay: all pass" || { echo "test-smgesturedisplay: FAILED"; exit 1; }
