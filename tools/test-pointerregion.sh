#!/bin/bash
# Mac test of the pointer's place while another display shares it (1.8.7, the iPad 2's AirPlay B pass: rows 14 and 6.6): common/PointerRegion.h's rules
# (test-pointerregion.c), then the sites in the code as built -- the iPad's hidden menu bar reads the pointer in the iPad's own region, the menu bar over
# a full-screen app and the Dock part too, the hovers that learn it, and the Mac Switcher leaving a push from another display alone. Made-to-fail copies
# of the header and of the sites must fail.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -o "$W/tpr" test-pointerregion.c
"$W/tpr"
# the lift of a push from another display: its stay comes before Home and the App Switcher go through (1, 2, 3 and 4), SpringBoard given 0 there
fromother_lift() {
  awk '/^static id DMMSWActivateWith\(.*\{$/{f=1}
    f && index($0, "if (!inside && eff >= 1 && eff <= 4 && gMSWGestHooked && DMMSWGesturesOn() && DMMSWFromOtherNow()) {") {b=NR}
    f && b && !o && NR > b && index($0, "orig(self, _cmd,") {o = index($0, "        id r = orig(self, _cmd, 0);") ? NR : -1}
    f && index($0, "if (inside || (eff != 3 && eff != 1 && eff != 2) || !gMSWGestHooked || !DMMSWGesturesOn()) return orig(self, _cmd, dest);") {a=NR}
    f && index($0, "if (DMMSWFromOtherNow()) {") {old=NR}
    f && /^}/ {print (a && b && o > 0 && b < o && o < a && !old) ? "ok" : "no"; exit}' "$1"
}
sites() {   # sites <root>: 0 when every site is as it must be
  local R="$1" S="$1/statusbar/StatusBar.x" P="$1/statusbar/PointerRegion.h" M="$1/statusbar/MacSwitcher.h" B="$1/statusbar/BarReveal.h" D="$1/dock/Dock.x" f=0
  fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }
  c() { if eval "$2"; then [ -n "$Q" ] || echo "PASS  $1"; else [ -n "$Q" ] || echo "FAIL  $1"; f=1; fi; }
  c "the iPad's hidden bar: the poll reads the pointer in the iPad's own region, 1.8.6's drop of every negative place gone" \
    "grep -qF 'int on = p.x == -1 && p.y == -1 ? 0 : DMPtrIPadNative(p, &n);' $S && grep -qF '            if (on < 0) return;' $S && grep -qF '            CGFloat y = DMAutoHidePointerY(n);' $S && ! grep -qF 'if (p.x < 0 || p.y < 0) { DMAutoHideSetZone(0); return; }' $S"
  c "  ... until the region is learned, the iPad's own hover sets the zone (only then, only while auto-hide is on)" \
    "awk '/^static void DMAutoHideIPadHover\\(CGPoint n, BOOL inside\\) \\{/{f=1} f&&/if \\(gDMPtrRegion.known \\|\\| !DMAutoHideActive\\(\\)\\) return;/{a=1} f&&/if \\(!inside\\) \\{ DMAutoHideSetZone\\(0\\); return; \\}/{b=1} f&&/DMAutoHideSetZone\\(y <= 6.0 \\? 1 : \\(y <= 26.0 \\? 2 : 3\\)\\);/{d=1} f&&/^}/{print (a&&b&&d) ? \"ok\" : \"no\"; exit}' $S | grep -q ok"
  c "the menu bar over a full-screen app: the same region" \
    "grep -qF 'int z = known && DMPtrIPadNative(p, &n) > 0 ? MSBDRevealZone(DMAutoHidePointerY(n), DMMenuBarHeight()) : 0;' $B && ! grep -qF '(p.x < 0 || p.y < 0) ? 0' $B"
  c "the Dock part: the side Dock's reveal and the hover hold read through MacStatusBar's region (looked up, as before when it is not there)" \
    "grep -qF 'dlsym(RTLD_DEFAULT, \"MSBDPointerOnIPad\")' $D && grep -qF '    if (!f) { *n = g; return 1; }' $D && grep -qF 'if (DMDockPointerOnIPad(n, &m) <= 0) { CGSize f = [UIScreen mainScreen].fixedCoordinateSpace.bounds.size; m = CGPointMake(f.width / 2.0, f.height / 2.0); }' $D && grep -qF 'if (known && onIPad && DMDockPointerOnIPad(n, &m) <= 0) m = CGPointMake(NAN, NAN);' $D && grep -qF '__attribute__((visibility(\"default\"))) int MSBDPointerOnIPad(double gx, double gy, double *nx, double *ny) {' $P"
  c "the region learned only from a reading of a pointer that did not move (no newer hover), off the main thread, of the known shape" \
    "grep -qF 'if (gDMPtrAnyAt != t0 || isnan(g.x) || !gDMPtrRegion.other) return;' $P && grep -qF '    gDMPtrAnyAt = now;' $P && grep -qF 'if (MSBDPtrRegionLearn(&gDMPtrRegion, g.x, g.y, n0.x, n0.y))' $P && grep -qF 'BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: \"\", \"{CGPoint=dd}16@0:8\");' $P && grep -qF '    dispatch_async(q, ^{' $P"
  c "the hovers: on each display's system gestures window only while another display has one, removed with the iPad alone; the other display's sets when the pointer was there" \
    "grep -qF 'if (!w.screen || ![NSStringFromClass([w class]) isEqualToString:@\"_UISystemGestureWindow\"]) continue;' $P && grep -qF '        if (other && !h) {' $P && grep -qF '        } else if (!other && h) {' $P && grep -qF 'if (s != [UIScreen mainScreen]) { gDMPtrSeen[1]++; gDMPtrOtherAt = now; return; }' $P && grep -qF 'h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;' $P"
  c "the iPad's own bar copies and its top-edge strip feed the same (they see the pointer where the bar is shown or hidden; the strip brings the bar until the region is learned)" \
    "grep -qF '    DMPtrHoverSeen(g, NO);   // (1.8.7: the iPad' $S && grep -qF -e '- (void)hover:(UIHoverGestureRecognizer *)g { DMPtrHoverSeen(g, NO); }' $S && grep -qF -e '- (void)hover:(UIHoverGestureRecognizer *)g { DMPtrHoverSeen(g, YES); }' $P && grep -qF '    if (!learn) return;' $P && grep -qF 'UIWindow *w = [v isKindOfClass:[UIWindow class]] ? (UIWindow *)v : v.window;' $P && grep -qF '[strip addGestureRecognizer:[[UIHoverGestureRecognizer alloc] initWithTarget:sink action:@selector(hover:)]]; }   // (1.8.7, PointerRegion.h)' $S"
  c "the hovers on the system gestures windows can prevent none of iPadOS's gestures there (ours on the iPad's window kept the pointer's bottom-edge push from beginning, d21-d23)" \
    "grep -qF -e '- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }' $P && grep -qF -e '- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }' $P && grep -qF 'h = [[DMPtrHoverRecognizer alloc] initWithTarget:sink action:@selector(hover:)];' $P && ! grep -qF '[[UIHoverGestureRecognizer alloc] initWithTarget:sink action:@selector(hover:)];' $P"
  c "a reading only after the pointer has rested 0.2 s (backboardd runs ahead of the hover while it moves)" \
    "grep -qF 'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gDMPtrAnyAt == now) DMPtrLearnRead(); });' $P && [ \$(grep -c 'DMPtrLearnRead();' $P) = 2 ]"
  c "a display that came or went: the region learned again (the origin with the iPad alone)" \
    "grep -qF '    if (screensChanged || (other ? 1 : 0) != gDMPtrRegion.other) {' $P && grep -qF '        MSBDPtrRegionReset(&gDMPtrRegion, other);' $P && grep -qF 'static MSBDPtrRegion gDMPtrRegion = { 1, 0, 0.0, 0.0, 0, 0.0, 0.0 };' $P"
  c "a piece for the crash guard: off, nothing of it runs (the start, the hovers, the readings)" \
    "[ \$(grep -c 'DMPtrSkipped()' $P) -ge 3 ] && grep -qF 'if (started || DMPtrSkipped()) return;' $P && grep -qF '    if (DMPtrSkipped()) return;' $P && grep -qF 'if (busy || DMPtrSkipped() ||' $P && grep -q '^target pointerRegion piece ' $R/tools/crashmap-rules.txt && grep -qF 'file MacStatusBarCore ^PointerRegion\\.h\$ pointerRegion' $R/tools/crashmap-rules.txt"
  c "started with the status bar, included before the Mac Switcher" \
    "grep -qF '^{ DMPtrStart(); });' $S && [ \$(grep -n '#include \"PointerRegion.h\"' $S | cut -d: -f1) -lt \$(grep -n '#include \"MacSwitcher.h\"' $S | cut -d: -f1) ]"
  c "the Mac Switcher: a gesture that is iPadOS's pointer push (its indirect bottom-edge pan) and began right after the pointer left another display is not followed" \
    "grep -qF 'iv = class_getInstanceVariable(c, \"_indirectBottomEdgePanGestureRecognizer\");' $M && grep -qF 'BOOL other = !gMSWGestureScreen && DMMSWGesturesOn() && MSBDPtrArrivedFromOther(DMPtrOtherDisplayAt(), now) && DMMSWPointerPush(self);' $M && grep -qF '        if (!other && !gMSWGestureScreen && DMMSWForMain()) @try { DMMSWTrackBegin(gesture); }' $M"
  c "  ... only a push at the iPad's own bottom edge: another display's own (its gesture manager, its pan on its screen) is that display's (review)" \
    "fn $M 'static BOOL DMMSWPointerPush(id manager) {' | grep -qF 'UIScreen *on = ((UIGestureRecognizer *)g).view.window.screen;' && fn $M 'static BOOL DMMSWPointerPush(id manager) {' | grep -qF 'if (on && on != [UIScreen mainScreen]) return NO;' \
     && awk '/gMSWGestureScreen = DMMSWGesturesOn\\(\\) \\? DMMSWGestureScreen\\(self\\) : nil;/{a=NR} /BOOL other = !gMSWGestureScreen/{b=NR} END{exit !(a && b > a)}' $M"
  c "  ... and at its lift nothing of ours runs, nor iPadOS's App Switcher, app switch or Home (row 6.6, d39: Home too): SpringBoard is told stay" \
    "fromother_lift $M | grep -q ok && grep -qF 'if (gesture && gesture == gMSWFromOther && gMSWFromOtherAt > 0) gMSWFromOtherEnd = CACurrentMediaTime();' $M"
  return $f
}
sites ..
echo "-- made-to-fail copies:"
mk() { rm -rf "$W/r"; mkdir -p "$W/r/statusbar" "$W/r/dock" "$W/r/tools" "$W/r/common"; cp ../statusbar/StatusBar.x ../statusbar/PointerRegion.h ../statusbar/MacSwitcher.h ../statusbar/BarReveal.h "$W/r/statusbar/"; cp ../dock/Dock.x "$W/r/dock/"; cp crashmap-rules.txt "$W/r/tools/"; }
mtf() {   # mtf <name> <file> <perl substitution>: that change must make the sites fail
  mk; perl -0pi -e "$3" "$W/r/$2"
  cmp -s "../$2" "$W/r/$2" && { echo "made-to-fail copy $1: the change did not apply"; exit 1; }
  if Q=1 sites "$W/r"; then echo "made-to-fail copy $1 PASSED (it must fail)"; exit 1; else echo "made-to-fail copy $1 fails, as it must"; fi
}
mtf "1.8.6's drop of negative places" statusbar/StatusBar.x 's/int on = p\.x == -1 && p\.y == -1 \? 0 : DMPtrIPadNative\(p, &n\);/int on = (p.x < 0 || p.y < 0) ? 0 : 1; n = p;/'
mtf "the reveal over a full-screen app reading the space's origin" statusbar/BarReveal.h 's/known && DMPtrIPadNative\(p, &n\) > 0 \?/known \&\& p.x >= 0 ?/'
mtf "a reading taken while the pointer moved" statusbar/PointerRegion.h 's/if \(gDMPtrAnyAt != t0 \|\| isnan\(g\.x\)/if (isnan(g.x)/'
mtf "the hovers left on with the iPad alone" statusbar/PointerRegion.h 's/        \} else if \(!other && h\) \{/        } else if (0 \&\& h) {/'
mtf "the push followed whatever display it came from" statusbar/MacSwitcher.h 's/        if \(!other && !gMSWGestureScreen && DMMSWForMain\(\)\) \@try \{ DMMSWTrackBegin/        if (!gMSWGestureScreen \&\& DMMSWForMain()) \@try { DMMSWTrackBegin/'
mtf "review: the TV's own push (its gesture manager) taken for one from another display" statusbar/MacSwitcher.h 's/BOOL other = !gMSWGestureScreen && DMMSWGesturesOn\(\)/BOOL other = DMMSWGesturesOn()/'
mtf "review: the TV's own push (its pan on the TV) taken for one from another display" statusbar/MacSwitcher.h 's/    if \(on && on != \[UIScreen mainScreen\]\) return NO;\n//'
mtf "the Mac Switcher opened at the lift of a push from another display" statusbar/MacSwitcher.h 's/ && DMMSWGesturesOn\(\) && DMMSWFromOtherNow\(\)\) \{/ \&\& DMMSWGesturesOn() \&\& 0) {/'
mtf "row 6.6 (d39): a push from another display that iPadOS ends on Home took the iPad Home" statusbar/MacSwitcher.h 's/if \(!inside && eff >= 1 && eff <= 4 && gMSWGestHooked/if (!inside \&\& eff >= 1 \&\& eff <= 3 \&\& gMSWGestHooked/'
mtf "the stay after Home and the App Switcher went through (1.8.7 d27's place)" statusbar/MacSwitcher.h 's/(    if \(!inside && eff >= 1 && eff <= 4 && gMSWGestHooked.*?\n    \}\n)(    if \(inside \|\| \(eff != 3.*?\n)/$2$1/s'
mtf "the strip not watched" statusbar/StatusBar.x 's/\[strip addGestureRecognizer:\[\[UIHoverGestureRecognizer alloc\] initWithTarget:sink action:\@selector\(hover:\)\]\]; \}/}/'
mtf "a system gestures window's hover dropped (its -window is nil)" statusbar/PointerRegion.h 's/UIWindow \*w = \[v isKindOfClass:\[UIWindow class\]\] \? \(UIWindow \*\)v : v\.window;/UIWindow *w = v.window;/'
mtf "the turned strip's point taken for a reading" statusbar/PointerRegion.h 's/    if \(!learn\) return;\n//'
mtf "a plain hover on a system gestures window" statusbar/PointerRegion.h 's/h = \[\[DMPtrHoverRecognizer alloc\]/h = [[UIHoverGestureRecognizer alloc]/'
mtf "a reading while the pointer moves" statusbar/PointerRegion.h 's/\^\{ if \(gDMPtrAnyAt == now\) DMPtrLearnRead\(\); \}\);/^{}); DMPtrLearnRead();/'
mtf "the Dock's side reveal reading the space's origin" dock/Dock.x 's/if \(DMDockPointerOnIPad\(n, &m\) <= 0\) \{ CGSize f/if (0) { CGSize f/'
mkdir -p "$W/h/common" "$W/h/tools"; cp test-pointerregion.c "$W/h/tools/"
for m in origin agree arrival; do
  cp ../common/PointerRegion.h "$W/h/common/"
  case $m in
    origin) perl -pi -e 's/double x = gx - r->ox, y = gy - r->oy;/double x = gx, y = gy;/' "$W/h/common/PointerRegion.h" ;;
    agree) perl -pi -e 's/if \(r->cand && fabs/if (1 || fabs/' "$W/h/common/PointerRegion.h" ;;
    arrival) perl -pi -e 's/began - lastOtherAt < kMSBDPtrArrivalWindow/began - lastOtherAt < 10.0/' "$W/h/common/PointerRegion.h" ;;
  esac
  cmp -s ../common/PointerRegion.h "$W/h/common/PointerRegion.h" && { echo "made-to-fail header $m: the change did not apply"; exit 1; }
  clang -O2 -Wall -o "$W/h/t" "$W/h/tools/test-pointerregion.c" 2>/dev/null
  if "$W/h/t" >/dev/null 2>&1; then echo "made-to-fail header $m PASSED (it must fail)"; exit 1; else echo "made-to-fail header $m fails, as it must"; fi
done
echo "test-pointerregion: all passed"
