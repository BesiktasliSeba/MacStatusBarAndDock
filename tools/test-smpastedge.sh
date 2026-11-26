#!/bin/bash
# test-smpastedge.sh: with our Stage Manager engine a window can be moved partly past the screen's left, right and bottom edges, as Zetsu's and
# MilkyWay4's windows can (1.8.8.3, GitHub #19) -- see test-smpastedge.m. The rule is statusbar/SMPastEdge.h; the real code is cut out of
# statusbar/StatusBar.x (SPE_SB_X / SPE_H: other copies, e.g. the code before the change) and run on the Mac (Mac Catalyst), in a release and a DEBUG
# build: the title bar's drag and drop, the record and its lookup, our requests' fit, a resize by hand's follow, iPadOS 16's before / after around
# Stage Manager's own constraint (iPadOS 17 and 18's pass: test-smlayout17.sh). Then site checks (the resize's begin in SMResizeAnchor.h too); then
# made-to-fail copies: each breaks one part and must fail.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
X0=${SPE_SB_X:-../statusbar/StatusBar.x}; H0=${SPE_H:-../statusbar/SMPastEdge.h}; E0=../statusbar/SMEngineAPI.h; C0=crashmap-rules.txt; A0=../statusbar/SMResizeAnchor.h
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }      # one function or method of a file, from its first line
blk() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^@end/ {exit}' "$1"; }   # an @interface, to its @end
line() { awk -v h="$2" 'index($0, h) == 1 {print; exit}' "$1"; }                        # one line of a file (a global)

IFACE='@interface DMSMTitleBar : UIView <UIGestureRecognizerDelegate>'
DECL=('static const CGFloat kSMBarH = ' 'static CFTimeInterval gSMDragUntil = 0;' 'static NSMutableSet<NSString *> *gSMBehindDock;'
      'static NSMutableDictionary<NSString *, NSNumber *> *gSMDockHeightBySize;')
GLUE_LINES=('static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMPastEdge;' 'static NSMutableArray<NSString *> *gSMPastEdgeOrder;'
            'static NSString *gSMPastEdgeResizeKey; static CGRect gSMPastEdgeResizeFrom;' 'static CGRect gSMPastEdgeDesk; static CGSize gSMPastEdgeScreen;'
            'static NSMutableDictionary<NSString *, NSValue *> *gSMGridFirstBySize;'
            'static id gSMDragItem16;' 'static NSString *gSMAppleDragKey;' 'static CFTimeInterval gSMAppleDragToldAt;')   # (1.8.9, B114: Stage Manager's own drag)
GLUE_FN=('static CGSize DMSMPastEdgeGridFirst(CGSize scr) {' 'static CGSize DMSMPastEdgeLaid(CGSize s, CGSize scr) {' 'static void DMSMPastEdgeGridNote(CGSize container, int axis, id list) {'
         'static BOOL DMSMPastEdgeAllowedOn(CGSize scr) {' 'static void DMSMPastEdgeRemove(NSString *key) {' 'static BOOL DMSMPastEdgeHeld(CGPoint c, CGSize s, CGSize scr) {'
         'static void DMSMPastEdgeResizeBegan(unsigned dragged, CGRect start) {'
         'static BOOL DMSMPastEdgeKeepIn(CGPoint *cp, CGSize pts, CGSize scr, CGRect u) {' 'static CGRect DMSMPastEdgeDeskOn(UIScreen *s, CGSize size) {'
         'static BOOL DMSMPastEdgeHeldAt(CGPoint c, CGSize s, CGSize scr, CGPoint *keep) {' 'static void DMSMPastEdgeDragBegin(UIView *card) {'
         'static CGPoint DMSMPastEdgeDragKept(UIView *card, CGPoint t) {'
         'static void DMSMPastEdgeSet(NSString *key, CGPoint centre, CGSize size, CGSize S, BOOL prune) {'
         'static void DMSMPastEdgeDropped(NSString *key, UIScreen *scn, CGRect droppedOnScreen, BOOL snapped, CGPoint at, CGPoint plain) {'
         'static BOOL DMSMWindowDragLive(void) {' 'static BOOL DMSMAppleDragNote(NSString *key, CGPoint *c, CGSize s, CGSize scr) {'
         'static BOOL DMSMAppleDragPass17(id item, CGPoint *p, CGSize z, CGSize container) {'
         'static CGRect DMSMCardDesk(CGRect u, CGSize scr, BOOL behindDock) {' 'static void DMSMJoinOwnPlace(NSString *key, CGSize *pts, CGPoint *cp, CGSize scr, CGRect u) {'
         'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {'
         'static NSArray<NSArray *> *DMSMPastEdgeBefore16(id m, CGRect area) {' 'static void DMSMPastEdgeAfter16(id m, NSArray<NSArray *> *held) {'
         'static void DMSMPastEdgeMoved(CGRect was, CGRect now, CGSize scr) {')
PAN='- (void)dm_pan:(UIPanGestureRecognizer *)g {'
TOUCH='- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {'   # (the bar's: where a touch goes down, 1.8.8.3)

sites() {   # $1 StatusBar.x, $2 SMEngineAPI.h, $3 crashmap-rules.txt, $4 quiet, $5 SMResizeAnchor.h: the number of site checks that fail
  local X=$1 E=$2 C=$3 q=$4 A=${5:-$A0} n=0 t
  # the drag: held at every move after its start (the desktop read at the start), before the move is drawn; the drop recorded after its snap and the
  # behind-the-Dock mark, before the place is asked for
  t=$(fn "$X" "$PAN")
  # (1.8.8.4: the drag's start on a title bar slid down with the menu bar moves the window down to it first: the travel carries it from there on,
  #  added to the travel the follow worked out -- 1.8.8.3's, before it: the follow sets the travel anew from the touch-down)
  if echo "$t" | awk '/NSString \*w = _key \?: _bundle;/{w=NR} /^    BOOL followed = _follows;$/{f=NR} /^    if \(g.state == UIGestureRecognizerStateBegan\) gSMDragSlid = DMAutoHideSMBake\(self\);$/{z=NR} /^    t.y \+= gSMDragSlid;$/{y=NR}
       /^    if \(g.state == UIGestureRecognizerStateBegan\) DMSMPastEdgeDragBegin\(card\);$/{b=NR} /^    else t = DMSMPastEdgeDragKept\(card, t\);$/{k=NR}
       /card.transform = CGAffineTransformMakeTranslation\(t.x, t.y\);/{if(!m)m=NR} /BOOL snapped = DMSMSnapMoveTarget\(w, card, t, &at\);/{s=NR} /if \(endsAt > line \+ 4.0\)/{e=NR}
       /DMSMPastEdgeDropped\(w, scn, droppedOnScreen, snapped, at, /{d=NR} /DMSMSetWindowGeometry\(w, /{if(!g)g=NR}
       END{exit !(w && f > w && z > f && y == z + 1 && b == y + 3 && b - f < 45 && k == b + 1 && m > k && s > m && e > s && d > e && g > d)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: -dm_pan: holds the drag at every move after its start, and records the drop after its snap and the Dock's mark, before the place is asked"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: -dm_pan: does not hold the drag or record the drop where it should"; n=$((n + 1)); fi
  # the follow (1.8.8.3): the bar's touch filter notes where a touch goes down after the pointer's resize band (never for a touch it refuses); the
  # drag's travel is the finger's whole way from there, worked out before the hold, so the hold, the drop and its record all read it
  local tt; tt=$(fn "$X" "$TOUCH")
  if echo "$tt" | awk '/^    if \(t.type == UITouchTypeIndirectPointer && DMSMPointerOnResizeEdge\(_card\)\) return NO;$/{r=NR} /_downTouch = t; _downWindow = t.window; _downAt = \[t locationInView:nil\];/{n=NR} /^    return YES;$/{y=NR} END{exit !(r && n > r && y > n)}' \
     && echo "$t" | awk '/^    CGPoint t = \[g translationInView:sup\];$/{a=NR} /^    if \(g.state == UIGestureRecognizerStateBegan\) \{$/{if(!b)b=NR} /_follows = YES; _followTouch = dt; _panBegan = _lastAt = now; _panBefore = before;/{f=NR} /t = CGPointMake\(since.x \+ b.x \* _caught, since.y \+ b.y \* _caught\);/{t=NR}
       /^    else t = DMSMPastEdgeDragKept\(card, t\);$/{k=NR} END{exit !(a && b > a && f > b && t > f && k > t)}'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the bar notes where a touch goes down (after the pointer's resize band) and -dm_pan: follows from there before the hold"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the bar's drag does not follow the finger from where it went down as built"; n=$((n + 1)); fi
  # our requests: a recorded window kept by the rule, every other fitted inside as before
  t=$(fn "$X" 'static id DMSMAttrsFitScreen(id attrs, id identity, BOOL behindDock, NSString *bundle) {')
  if echo "$t" | grep -qxF '    if (DMSMPastEdgeHeld(cp, pts, scr)) { if (!DMSMPastEdgeKeepIn(&cp, pts, scr, u)) return attrs; }' \
     && echo "$t" | grep -qxF '    else if (!DMSMFitInDesk(&pts, &cp, DMSMCardDesk(u, scr, behindDock))) return attrs;'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMAttrsFitScreen keeps a recorded window by the rule and fits any other inside"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMAttrsFitScreen does not ask for a recorded window"; n=$((n + 1)); fi
  # a window joining a desktop at its own place (minimized and opened again, back from full screen): where the user left it (DMSMJoinOwnPlace); a new
  # window fitted inside above the Dock as before (1.8.8.3)
  t=$(fn "$X" 'static id DMSMJoinAttributesOn(NSString *key, id frontAttrs, BOOL windowed, long newest, id stage, id identity) {')
  if echo "$t" | grep -qxF '            if (!CGRectIsEmpty(u) && !CGRectIsNull(u)) { if (fresh) DMSMFitInDesk(&pts, &cp, DMSMCardDesk(u, scr, NO)); else DMSMJoinOwnPlace(key, &pts, &cp, scr, u); }' \
     && echo "$t" | grep -qxF '        BOOL fresh = !DMSMAttrsOwnSize(own);' && [ "$(echo "$t" | grep -c 'DMSMFitInDesk(')" = 1 ] && [ "$(grep -c 'DMSMJoinOwnPlace(key, ' "$X")" = 1 ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMSMJoinAttributesOn puts a window at its own place where the user left it (DMSMJoinOwnPlace), a new one inside as before"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMSMJoinAttributesOn fits a window at its own place inside the desktop"; n=$((n + 1)); fi
  # iPadOS 16: before Apple's step, then Apple's, then the top-and-left rule, then ours, on both axes
  if grep -qxF 'static void DMSMConstrainV16(id self, SEL _cmd, id m, CGRect area) { NSArray *held = DMSMPastEdgeBefore16(m, area); o_SMConstrainV(self, _cmd, m, area); DMSMConstrainEdges16(m, area, 1); DMSMPastEdgeAfter16(m, held); }' "$X" \
     && grep -qxF 'static void DMSMConstrainH16(id self, SEL _cmd, id m, CGRect area) { NSArray *held = DMSMPastEdgeBefore16(m, area); o_SMConstrainH(self, _cmd, m, area); DMSMConstrainEdges16(m, area, 0); DMSMPastEdgeAfter16(m, held); }' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: iPadOS 16's constraint hooks read the recorded windows before Apple's step and put them back after it"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: iPadOS 16's constraint hooks do not keep a recorded window"; n=$((n + 1)); fi
  # iPadOS 17 and 18: the hook hands the pass the lookup between its begin and its end; the pass keeps such a window where the lookup keeps it (not a
  # full-screen one, its top under the area)
  if awk '/^- \(CGRect\)_performAutoLayoutWithSpace:\(id\)space configuration:\(id\)cfg stageInset:\(UIEdgeInsets\)inset \{/{f=1} f&&/DMSM17Pass pass = DMSM17PassBegin\(space, haveContainer, container\);/{b=NR}
          f&&/^    pass.kept = DMSMPastEdgeHeldAt;/{k=NR} f&&/int moved = DMSM17PassEnd\(&pass, area\);/{e=NR} f&&/^}/{exit} END{exit !(b && k == b + 1 && e > k)}' "$X" \
     && grep -qF "BOOL past = ![en[3] boolValue] && pass->kept && pass->container.width > 0 && pass->container.height > 0 && pass->kept(p, z, pass->container, &keep) && isfinite(keep.x) && isfinite(keep.y) && keep.y - z.height / 2.0 >= CGRectGetMinY(area) - 0.5;" "$E" \
     && grep -qF 'CGPoint want = [en[3] boolValue] ? p : past ? keep : DMSMClampCenter(p, z, area);' "$E"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x / SMEngineAPI.h: iPadOS 17 and 18's pass gets the lookup and keeps a recorded window (not full screen, its top under the area)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x / SMEngineAPI.h: iPadOS 17 and 18's pass does not keep a recorded window as built"; n=$((n + 1)); fi
  # 1.8.9 (B114): Stage Manager's own window drag. iPadOS 16's two pass hooks (16.1's and 16.0's) name the pass's dragging item around Apple's pass and
  # give the one before back after it; 17 and 18's hook hands the pass the dragged question right after the lookup, and the pass asks it for each
  # window before its keep (the place it hands back is the one kept)
  if [ "$(awk '/^    id wasDrag = gSMDragItem16; gSMDragItem16 = d;$/{a=NR} /^    id out = %orig;$/{if (a && NR == a + 1) b=NR} /^    gSMDragItem16 = wasDrag;$/{if (b && NR == b + 1) {n++; a=0; b=0}} END{print n+0}' "$X")" = 2 ] \
     && awk '/^- \(CGRect\)_performAutoLayoutWithSpace:\(id\)space configuration:\(id\)cfg stageInset:\(UIEdgeInsets\)inset \{/{f=1} f&&/^    pass.kept = DMSMPastEdgeHeldAt;/{k=NR} f&&/^    pass.dragged = DMSMAppleDragPass17;/{d=NR} f&&/^}/{exit} END{exit !(k && d == k + 1)}' "$X" \
     && awk '/if \(pass->dragged && !\[en\[3\] boolValue\] && pass->container.width > 0 && pass->container.height > 0 && pass->dragged\(en\[0\], &p, z, pass->container\)\) keep = p;/{d=NR} /BOOL past = !\[en\[3\] boolValue\] && pass->kept/{p=NR} END{exit !(d && p > d && p <= d + 3)}' "$E"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x / SMEngineAPI.h: iPadOS 16's passes name their dragging item; 17 and 18's pass asks for the window under Stage Manager's own drag before its keep"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x / SMEngineAPI.h: Stage Manager's own drag is not handed to the layout passes as built"; n=$((n + 1)); fi
  # a resize by hand: the gesture hook (16, 17 and 18) tells the glue where each resize begins -- the sides its edge drags, the card as it began --
  # after Apple's own handling of the event, as it reads them for the title bar's record; unread: it says so (nothing followed)
  t=$(fn "$A" 'static id DMSMRAGesture(id self, SEL _cmd, id event) {')
  if echo "$t" | awk '/^    id r = o_SMRAGesture\(self, _cmd, event\);$/{r=NR} /^    if \(read && phase == 1\) \{$/{p=NR}
       /^            DMSMPastEdgeResizeBegan\(\(sd.left \? kDMSMPastEdgeLeft : 0\) \| \(sd.right \? kDMSMPastEdgeRight : 0\) \| \(sd.top \? kDMSMPastEdgeTop : 0\) \| \(sd.bottom \? kDMSMPastEdgeBottom : 0\), st\);$/{b=NR}
       /^        \} else DMSMPastEdgeResizeBegan\(0, CGRectNull\);$/{e=NR} END{exit !(r && p > r && b == p + 4 && e == b + 1)}'; then
    [ -n "$q" ] || echo "PASS  SMResizeAnchor.h: the resize gesture's hook tells the glue where each resize begins (its dragged sides, the card), after Apple's handling"
  else [ -n "$q" ] || echo "FAIL  SMResizeAnchor.h: the resize gesture's hook does not tell the glue where a resize begins"; n=$((n + 1)); fi
  # 1.8.9 (GitHub #20): the size lists' hooks note the first entry of each list they hand Stage Manager (the smallest window it lays out there), for
  # the record and every lookup to know a window by its laid-out size
  if awk '/^- \(id\)gridWidths \{/{w=1} w&&/^    id l = DMSMFineGrid\(v, CGRectGetWidth\(cb\), 0\);$/{a=NR} w&&/^    DMSMPastEdgeGridNote\(cb.size, 0, l\);/{b=NR} w&&/^    return l;$/{c=NR; w=0}
          /^- \(id\)gridHeights \{/{h=1} h&&/^    id l = DMSMFineGrid\(v, CGRectGetHeight\(cb\), 1\);$/{d=NR} h&&/^    DMSMPastEdgeGridNote\(cb.size, 1, l\);/{e=NR} h&&/^    return l;$/{f=NR; h=0}
          END{exit !(a && b == a + 1 && c == b + 1 && d && e == d + 1 && f == e + 1)}' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the gridWidths / gridHeights hooks note the first width and height of the lists they hand over"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the size lists' hooks do not note their lists' first sizes"; n=$((n + 1)); fi
  # the rule's header right after SMFit.h; no timer, poll or delayed work in the glue (the chip cost: a few comparisons per move and per pass)
  t=$(for h in "${GLUE_FN[@]}"; do fn "$X" "$h"; done)
  if grep -A1 -F '#include "SMFit.h" ' "$X" | grep -q '^#include "SMPastEdge.h" ' && ! echo "$t" | grep -qE 'NSTimer|dispatch_after|CADisplayLink|performSelector:.*afterDelay|scheduledTimer'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: SMPastEdge.h is included after SMFit.h; no timer, poll or delayed work in the past-edge code"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the rule's header is not included as built, or the past-edge code waits or polls"; n=$((n + 1)); fi
  # the crash map: every new function is the Stage Manager engine's (windowingEnabled, the first sym rule that matches), the header in the engine's file rule
  local bad=0
  for f in DMSMJoinOwnPlace DMSMPastEdgeAllowedOn DMSMPastEdgeRemove DMSMPastEdgeHeld DMSMPastEdgeResizeBegan DMSMPastEdgeKeepIn DMSMPastEdgeDeskOn DMSMPastEdgeHeldAt DMSMPastEdgeDragBegin \
           DMSMPastEdgeDragKept DMSMPastEdgeDropped DMSMPastEdgeBefore16 DMSMPastEdgeAfter16 DMSMPastEdgeKeep DMSMPastEdgeCardCenter DMSMPastEdgeOut DMSMPastEdgeSame \
           DMSMPastEdgeTurnedAway DMSMPastEdgeFiniteRect DMSMPastEdgeSameCard DMSMPastEdgeResized DMSMPastEdgeLaidOut DMSMPastEdgeGridFirst DMSMPastEdgeLaid DMSMPastEdgeGridNote \
           DMSMPastEdgeSet DMSMWindowDragLive DMSMAppleDragNote DMSMAppleDragPass17 DMSMAppleDragBegins; do
    [ "$(python3 -I -c 'import re, sys
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 4 and p[0] == "sym" and p[1] == "MacStatusBarCore" and re.search(p[2], "_" + sys.argv[2]): print(p[3]); break' "$C" "$f")" = windowingEnabled ] || bad=$((bad + 1))
  done
  if [ $bad = 0 ] && python3 -I -c 'import re, sys
ok = any(len(p) >= 4 and p[0] == "file" and p[1] == "MacStatusBarCore" and p[3] == "windowingEnabled" and re.search(p[2], "SMPastEdge.h") for p in (l.split() for l in open(sys.argv[1])))
sys.exit(0 if ok else 1)' "$C"; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: every past-edge function is under the Stage Manager engine's rule (windowingEnabled), SMPastEdge.h in its file rule"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: $bad past-edge function(s) not under windowingEnabled, or SMPastEdge.h not in the engine's file rule"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 SMPastEdge.h, $3 work dir, $4 quiet; the number of failed checks (99: the code could not be cut out or built)
  local X=$1 H=$2 d=$3 q=$4 n=0 h out dbg
  mkdir -p "$d"
  cp "$H" "$d/SMPastEdge.h" || { echo "FAIL  no $H"; return 99; }
  [ -n "$(blk "$X" "$IFACE")" ] || { echo "FAIL  $X: no \"$IFACE\""; return 99; }
  for h in "${DECL[@]}" "${GLUE_LINES[@]}"; do [ -n "$(line "$X" "$h")" ] || { echo "FAIL  $X: no line starting \"$h\""; return 99; }; done
  for h in "${GLUE_FN[@]}"; do [ -n "$(fn "$X" "$h")" ] || { echo "FAIL  $X: no function \"$h\""; return 99; }; done
  [ "$(grep -cF -e "$PAN" "$X")" = 1 ] || { echo "FAIL  $X: not one \"$PAN\""; return 99; }
  [ "$(grep -cF -e "$TOUCH" "$X")" = 1 ] || { echo "FAIL  $X: not one \"$TOUCH\""; return 99; }
  { for h in "${DECL[@]}"; do line "$X" "$h"; done; blk "$X" "$IFACE"; } > "$d/spe-decl.inc"
  # (UIKit's main screen asked as the test's TMainScreen(): the iPad's screen of each case, which UIKit's own would not be)
  { for h in "${GLUE_LINES[@]}"; do line "$X" "$h"; done; for h in "${GLUE_FN[@]}"; do fn "$X" "$h"; done; } | sed 's/\[UIScreen mainScreen\]/TMainScreen()/g' > "$d/spe-glue.inc"
  { fn "$X" "$TOUCH"; fn "$X" "$PAN"; } | sed 's/\[UIScreen mainScreen\]/TMainScreen()/g' > "$d/spe-pan.inc"
  for dbg in 0 1; do
    clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
          -DDEBUG=$dbg -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d" -I../statusbar \
          -framework UIKit -framework CoreGraphics -framework QuartzCore -o "$d/t$dbg" test-smpastedge.m 2>"$d/cc$dbg.txt" \
      || { [ -n "$q" ] || cat "$d/cc$dbg.txt"; [ -n "$q" ] || echo "FAIL  the real code did not build (DEBUG=$dbg)"; return 99; }
    [ -n "$q" ] || cat "$d/cc$dbg.txt"
  done
  out=$("$d/t0"); n=$?
  [ -n "$q" ] || echo "$out"
  out=$("$d/t1"); h=$?
  if [ $h != $n ]; then [ -n "$q" ] || { echo "FAIL  the DEBUG build answers otherwise ($h failed checks, release $n)"; echo "$out" | grep '^FAIL'; }; n=$((n + 1))
  else [ -n "$q" ] || echo "PASS  the DEBUG build answers the same"; fi
  return $n
}

[ -f "$H0" ] || { echo "FAIL  no statusbar/SMPastEdge.h: a window let go past the screen's edge is not kept there"; exit 1; }
run "$X0" "$H0" "$W/real"; rc=$?
sites "$X0" "$E0" "$C0"; s=$?
[ $s -gt 0 ] && rc=1
if [ -z "$SPE_SB_X$SPE_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  mtf() {   # $1 what, $2 which file (X StatusBar.x, H SMPastEdge.h, E SMEngineAPI.h, C crashmap-rules.txt, A SMResizeAnchor.h), $3 perl expression on it (-0777: the whole file)
    local d="$W/m$((++k))" x=$X0 h=$H0 e=$E0 c=$C0 a=$A0 f out m r
    mkdir -p "$d"
    case $2 in X) f=$X0; out="$d/StatusBar.x"; x=$out;; H) f=$H0; out="$d/SMPastEdge.h.src"; h=$out;; E) f=$E0; out="$d/SMEngineAPI.h"; e=$out;; C) f=$C0; out="$d/crashmap-rules.txt"; c=$out;; A) f=$A0; out="$d/SMResizeAnchor.h"; a=$out;; esac
    perl -0777 -pe "$3" "$f" > "$out"
    cmp -s "$out" "$f" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$x" "$h" "$d/w" q; r=$?
    sites "$x" "$e" "$c" q "$a"; m=$?
    if { [ $r -gt 0 ] && [ $r -lt 99 ]; } || [ $m -gt 0 ]; then echo "PASS  caught: $1 ($r check(s), $m site check(s) fail)"; else echo "FAIL  not caught: $1 ($r, $m)"; rc=1; fi
  }
  k=0
  mtf "a grab area held at the sides (112 pt of the window kept on the screen)" H 's/return CGRectMake\(w.origin.x, fmax\(w.origin.y, CGRectGetMinY\(desk\)\), w.size.width, w.size.height\);/return CGRectMake(fmax(fmin(w.origin.x, CGRectGetMaxX(desk) - 112.0), CGRectGetMinX(desk) + 112.0 - w.size.width), fmax(w.origin.y, CGRectGetMinY(desk)), w.size.width, w.size.height);/'
  mtf "the title bar held above the Dock (44 pt above the desktop's bottom)" H 's/return CGRectMake\(w.origin.x, fmax\(w.origin.y, CGRectGetMinY\(desk\)\),/return CGRectMake(w.origin.x, fmax(fmin(w.origin.y, CGRectGetMaxY(desk) - 44.0), CGRectGetMinY(desk)),/'
  mtf "the top let over the menu bar" H 's/return CGRectMake\(w.origin.x, fmax\(w.origin.y, CGRectGetMinY\(desk\)\),/return CGRectMake(w.origin.x, w.origin.y,/'
  mtf "past the top counted as past an edge" H 's/ \|\| CGRectGetMaxY\(w\) > CGRectGetMaxY\(screen\) \+ 0.5;/ || CGRectGetMaxY(w) > CGRectGetMaxY(screen) + 0.5 || CGRectGetMinY(w) < CGRectGetMinY(screen) - 0.5;/'
  mtf "the same place in any screen size" H 's/return fabs\(scr.width - rscr.width\) < 0.5 && fabs\(scr.height - rscr.height\) < 0.5 && /return /'
  mtf "the drag not held (it goes over the menu bar)" X 's/^    else t = DMSMPastEdgeDragKept\(card, t\);\n//m'
  mtf "the drag by UIKit's translation alone (from where its pan began: the finger's first 12 pt lost)" X 's/^    BOOL followed = _follows;$/    BOOL followed = NO;/m'
  mtf "the way before the pan taken in at once (a jump as the window starts to move)" X 's/_caught = end \? 1.0 : MAX\(_caught, MIN\(1.0, hypot\(since.x, since.y\) \/ MAX\(24.0, 2.0 \* hypot\(b.x, b.y\)\)\)\);/_caught = 1.0;/'
  mtf "the way before the pan never taken in during the drag (only at the let go)" X 's/_caught = end \? 1.0 : MAX\(_caught, MIN\(1.0, hypot\(since.x, since.y\) \/ MAX\(24.0, 2.0 \* hypot\(b.x, b.y\)\)\)\);/_caught = end ? 1.0 : 0.0;/'
  mtf "the way before the pan never taken in (not at the let go either)" X 's/_caught = end \? 1.0 : MAX\(_caught, MIN\(1.0, hypot\(since.x, since.y\) \/ MAX\(24.0, 2.0 \* hypot\(b.x, b.y\)\)\)\);/_caught = 0.0;/'
  mtf "the way taken in given back as the finger turns back (read from its distance alone)" X 's/_caught = end \? 1.0 : MAX\(_caught, MIN\(1.0, /_caught = end ? 1.0 : MAX(0.0, MIN(1.0, /'
  mtf "the lifted finger still followed while another goes on (no hand-over to UIKit's translation)" X 's/if \(!end && \(!ft \|\| ft.phase == UITouchPhaseEnded \|\| ft.phase == UITouchPhaseCancelled\)\) \{/if (0) {/'
  mtf "the touch put down last followed, not the drag's own finger" X 's/UITouch \*ft = _followTouch;/UITouch *ft = _downTouch;/'
  mtf "a two-finger pan followed from the first finger" X 's/if \(dt && !_downTwo && _downWindow && _downWindow == sup.window && g.numberOfTouches == 1 && /if (dt \&\& _downWindow \&\& _downWindow == sup.window \&\& /'
  mtf "a touch-down followed after its touch ended" X 's/ && g.numberOfTouches == 1 && dt.phase != UITouchPhaseEnded && dt.phase != UITouchPhaseCancelled\) \{/ \&\& g.numberOfTouches == 1) {/'
  mtf "the pan's point followed (the middle of its touches: a second finger moves the window)" X 's/CGPoint now = ft \? \[ft locationInView:sup\] : _lastAt, since/CGPoint now = [g locationInView:sup], since/'
  mtf "a touch-down followed however far from where the pan began" X 's/ && hypot\(before.x, before.y\) < 60.0\) \{ _follows = YES;/) { _follows = YES;/'
  mtf "a touch-down in another window followed" X 's/ && _downWindow && _downWindow == sup.window && / \&\& /'
  mtf "a window back at its own place fitted inside (the join as before)" X 's/else DMSMJoinOwnPlace\(key, &pts, &cp, scr, u\); \}/else DMSMFitInDesk(\&pts, \&cp, DMSMCardDesk(u, scr, NO)); }/'
  mtf "a window back at its own place kept past an edge without the rule (its top over a taller menu bar)" X 's/    if \(DMSMPastEdgeHeldAt\(\*cp, \*pts, scr, &keep\)\) \{\n        DM_FEATURE_MARK\("sm-past-edge-join"\);/    if (DMSMPastEdgeHeld(*cp, *pts, scr)) {\n        DM_FEATURE_MARK("sm-past-edge-join");/'
  mtf "a window put behind the Dock fitted above it when it comes back" X 's/DMSMFitInDesk\(pts, cp, DMSMCardDesk\(u, scr, DMSMKeySetHas\(gSMBehindDock, key\)\)\);/DMSMFitInDesk(pts, cp, DMSMCardDesk(u, scr, NO));/'
  mtf "the drop not recorded" X 's/^        DMSMPastEdgeDropped\(w, scn, droppedOnScreen, snapped, at, [^\n]*\n//m'
  mtf "the drop recorded before its snap (the card as let go)" X 's/(CGPoint asked = snapped \? at : plain;)/$1 snapped = NO; asked = plain;/'
  mtf "a drop inside the screen keeps the old record" X 's/^    DMSMPastEdgeRemove\(key\);\n    if \(!past\) \{/    if (!past) {/m'
  mtf "the record's size from the card, not the attributes Stage Manager lays out" X 's/if \(p.width > 0 && p.height > 0\) size = p;/(void)p;/'
  mtf "the Dock at a side not asked" X 's/return !ipad \|\| DMDockSideNow\(scr\) == MSBDDockBottom;/return YES;/'
  mtf "the other shape's records kept after a turn" X 's/if \(DMSMPastEdgeTurnedAway\(rscr, main\)\) \{/if (0) {/'
  mtf "no cap on the records" X 's/while \(gSMPastEdgeOrder.count >= 16\)/while (gSMPastEdgeOrder.count >= 1000)/'
  mtf "gone windows' records not dropped" X 's/if \(present && !DMSMKeysHold\(present, k\)\) DMSMPastEdgeRemove\(k\);/(void)present;/'
  mtf "an app key's record taken for gone" X 's/if \(present && !DMSMKeysHold\(present, k\)\) DMSMPastEdgeRemove\(k\);/if (present \&\& ![present containsObject:k]) DMSMPastEdgeRemove(k);/'
  mtf "our requests fit a recorded window inside" X 's/    if \(DMSMPastEdgeHeld\(cp, pts, scr\)\) \{ if \(!DMSMPastEdgeKeepIn\(&cp, pts, scr, u\)\) return attrs; \}\n    else if/    if/'
  mtf "our requests keep a recorded window without the rule (its top over a taller menu bar)" X 's/CGPoint k = DMSMPastEdgeCardCenter\(\*cp, pts, u, kSMBarH\);/CGPoint k = *cp;/'
  mtf "the record not following our keep" X 's/            gSMPastEdge\[key\] = @\[\[NSValue valueWithCGPoint:k\], r\[1\], r\[2\]\];/            (void)key;/'
  mtf "16: the vertical hook does not put it back" X 's/static void DMSMConstrainV16\(id self, SEL _cmd, id m, CGRect area\) \{ NSArray \*held = DMSMPastEdgeBefore16\(m, area\); o_SMConstrainV\(self, _cmd, m, area\); DMSMConstrainEdges16\(m, area, 1\); DMSMPastEdgeAfter16\(m, held\); \}/static void DMSMConstrainV16(id self, SEL _cmd, id m, CGRect area) { o_SMConstrainV(self, _cmd, m, area); DMSMConstrainEdges16(m, area, 1); }/'
  mtf "16: the recorded window not put back after Apple's step" X 's/(        CGPoint want = \[e\[1\] CGPointValue\], now = )/        continue;\n$1/'
  mtf "16: a window with its kept top above the area kept there" X 's/ \|\| k\.y - s\.height \/ 2\.0 < CGRectGetMinY\(area\) - 0\.5\) continue;/) continue;/'
  mtf "16: a window recorded at the top edge (the bar hiding itself then) not kept under the bar again (1.8.8.3's gate)" X 's/if \(!isfinite\(c\.x\) \|\| !isfinite\(c\.y\) \|\| !DMSMPastEdgeHeldAt/if (!isfinite(c.x) || !isfinite(c.y) || c.y - s.height \/ 2.0 < CGRectGetMinY(area) - 0.5 || !DMSMPastEdgeHeldAt/'
  mtf "16: the lone window's flag left down" X 's/        gSMLoneCenterNext = lone;\n        DM_FEATURE_MARK\("sm-past-edge-kept16"\);/        DM_FEATURE_MARK("sm-past-edge-kept16");/'
  mtf "17: the pass not handed the lookup" X 's/^    pass.kept = DMSMPastEdgeHeldAt;[^\n]*\n//m'
  mtf "17: a full-screen window asked too" E 's/BOOL past = !\[en\[3\] boolValue\] && pass->kept/BOOL past = pass->kept/'
  mtf "17: a recorded window still clamped" E 's/CGPoint want = \[en\[3\] boolValue\] \? p : past \? keep : DMSMClampCenter\(p, z, area\);/CGPoint want = [en[3] boolValue] ? p : DMSMClampCenter(p, z, area);/'
  mtf "17: kept at the recorded place, not where the lookup keeps it" E 's/CGPoint want = \[en\[3\] boolValue\] \? p : past \? keep : /CGPoint want = ([en[3] boolValue] || past) ? p : /'
  mtf "the passes keep a recorded window without the rule (its top over a taller menu bar)" X 's/if \(DMSMPastEdgeFiniteRect\(u\)\) \(void\)DMSMPastEdgeKeepIn\(&k, s, scr, u\);/(void)u;/'
  mtf "16: the recorded place put back, not where the lookup keeps it" X 's/\[held addObject:@\[it, \[NSValue valueWithCGPoint:k\]\]\];/[held addObject:@[it, [NSValue valueWithCGPoint:c]]];/'
  mtf "a TV whose display is not read held to the iPad's desktop" X 's/return CGSizeEqualToSize\(got, size\) \? u : CGRectNull;/return u;/'
  mtf "a resize by hand not followed (the window at its new size fitted inside)" X 's/    if \(!hit && rr.count == 3 && /    if (0 \&\& rr.count == 3 \&\& /'
  mtf "the record not following the resize" X 's/            gSMPastEdge\[gSMPastEdgeResizeKey\] = @\[\[NSValue valueWithCGPoint:c\], \[NSValue valueWithCGSize:s\], rr\[2\]\];\n//'
  mtf "a resize followed on any screen" X 's/ && fabs\(scr.width - rrs.width\) < 0.5 && fabs\(scr.height - rrs.height\) < 0.5 && DMSMPastEdgeResized/ \&\& DMSMPastEdgeResized/'
  mtf "the follow not ended by a drag" X 's/    gSMPastEdgeStopped = NO;\n    gSMPastEdgeResizeKey = nil;\n/    gSMPastEdgeStopped = NO;\n/'
  mtf "two records at one card followed" X 's/    if \(n != 1\) return;/    if (n < 1) return;/'
  mtf "a resized window followed with its held sides moved" H 's/    return \(\(dragged & kDMSMPastEdgeLeft\) \|\| /    return 1 || ((dragged \& kDMSMPastEdgeLeft) || /'
  mtf "a resize followed on any card (no record's)" H 's/    return fabs\(CGRectGetMinX\(start\) - \(rc.x - rs.width \/ 2.0\)\) < 3.0/    return 1 || fabs(CGRectGetMinX(start) - (rc.x - rs.width \/ 2.0)) < 3.0/'
  mtf "the resize's begin not told (the gesture hook)" A 's/^            DMSMPastEdgeResizeBegan\(\(sd.left[^\n]*\n//m'
  mtf "#20: the record keeps the size asked (1.8.8.4's)" X 's/^    size = DMSMPastEdgeLaid\(size, S\);[^\n]*\n//m'
  mtf "#20: a lookup by the size asked (our requests and the join)" X 's/^    s = DMSMPastEdgeLaid\(s, scr\);[^\n]*\n//m'
  mtf "#20: our request keeps the top of the size asked" X 's/^    pts = DMSMPastEdgeLaid\(pts, scr\);[^\n]*\n//m'
  mtf "#20: the laid-out size never raised (the rule)" H 's/if \(isfinite\(first.height\) && first.height > s.height\) s.height = first.height;//'
  mtf "#20: the grid's heights not noted" X 's/^    DMSMPastEdgeGridNote\(cb.size, 1, l\);[^\n]*\n//m'
  mtf "#20: the menu bar's retop compares by the size asked" X 's/CGSize s0 = DMSMPastEdgeLaid\(CGSizeMake\(was.size.width, was.size.height - kSMBarH\), scr\), s1 = DMSMPastEdgeLaid\(CGSizeMake\(now.size.width, now.size.height - kSMBarH\), scr\);/CGSize s0 = CGSizeMake(was.size.width, was.size.height - kSMBarH), s1 = CGSizeMake(now.size.width, now.size.height - kSMBarH);/'
  mtf "#20: one size list for every screen" X 's/NSValue \*v = gSMGridFirstBySize\[NSStringFromCGSize\(scr\)\];/NSValue *v = gSMGridFirstBySize.allValues.firstObject;/'
  mtf "B114: Stage Manager's own drag not noted in iPadOS 16's pass (the code before)" X 's/^        if \(dragged && \[it isEqual:dragged\]\) \(void\)DMSMAppleDragNote\([^\n]*\n//m'
  mtf "B114: 16's passes not naming their dragging item" X 's/gSMDragItem16 = d;/gSMDragItem16 = nil;/g'
  mtf "B114: the dragged window's place recorded without the rule (its top over the menu bar)" X 's/CGPoint k = DMSMPastEdgeFiniteRect\(u\) \? DMSMPastEdgeCardCenter\(\*c, laid, u, kSMBarH\) : \*c;/CGPoint k = *c;/'
  mtf "B114: any drag taken for Stage Manager's own window drag" X 's/    if \(!c \|\| !gSMGestureTxs.count\) return NO;/    return YES;/'
  mtf "B114: a window dragged back inside keeps its record" X 's/if \(r\) \{ DMSMPastEdgeRemove\(key\); DMLog/if (0) { DMSMPastEdgeRemove(key); DMLog/'
  mtf "B114: our full screen noted (taken for past the bottom)" X 's/^    if \(s.width >= scr.width - 1.0 && s.height >= scr.height - 1.0\) return NO;[^\n]*\n//m'
  mtf "B114: a completed drag still counted" X 's/        if \(DMSMGTGetter\(t, done, .B.\) && \(\(BOOL \(\*\)\(id, SEL\)\)objc_msgSend\)\(t, done\)\) continue;[^\n]*\n//'
  mtf "B114, 17: another window's item taken for the dragged one" X 's/return \[k isEqualToString:gSMAppleDragKey\] && DMSMAppleDragNote/return k \&\& DMSMAppleDragNote/'
  mtf "B114, 17: the hook hands the pass no dragged question" X 's/^    pass.dragged = DMSMAppleDragPass17;[^\n]*\n//m'
  mtf "B114, 17: the pass does not ask it (SMEngineAPI.h)" E 's/^        if \(pass->dragged && [^\n]*\n//m'
  mtf "the crash map: the header out of the engine's file rule" C 's/\^\(SMEngineAPI\|SMFit\|SMPastEdge\|/^(SMEngineAPI|SMFit|/'
fi
exit $rc
