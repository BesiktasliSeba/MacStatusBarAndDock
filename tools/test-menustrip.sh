#!/bin/bash
# test-menustrip.sh: Scroll Menus That Don't Fit (1.8.8.2; the owner, 21 Nov: "And going forward maybe we can make them scrollable in portrait with a
# toggle in settings"). (1) common/MenuStrip.h's numbers on many strips (test-menustrip.c, R1-R11): which titles show from each first, the
# chevrons, a page on and back, a wheel's notch, a swipe, reveal; (2) the sites: the switch in Settings > Status Bar and its read, the crash guard's
# rule, the bar's layout calling the strip, the strip's room as ours, the chevrons in every list of the bar's items, the gestures (fingers only for a
# swipe, never under an open menu, never locked), every function the layout or a gesture calls out of line; (3) made-to-fail copies of
# common/MenuStrip.h. The real layout with this code, every bar with the switch off and on: test-barends.sh (S0-S8).
cd "$(dirname "$0")" || exit 1
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
MC=../common/MenuStrip.h; MS=../statusbar/MenuStrip.h; SB=../statusbar/StatusBar.x; P=../statusbar/macstatusbarprefs/Resources/Root.plist; R=crashmap-rules.txt
[ -f "$MC" ] && [ -f "$MS" ] || { echo "FAIL  no common/MenuStrip.h or statusbar/MenuStrip.h"; echo "test-menustrip: FAILED"; exit 1; }
run() {   # $1 common/MenuStrip.h, $2 dir: builds test-menustrip.c on it and runs it
  mkdir -p "$2"; cp "$1" "$2/MenuStripC.h"
  clang -Wall -Werror -I"$2" -o "$2/t" test-menustrip.c 2> "$2/cc.txt" || return 98
  "$2/t"
}
out=$(run "$MC" "$W/real"); rc=$?
echo "$out" | tail -32
[ $rc = 0 ] || fails=1
fn() { awk -v h="$2" 'f == 0 && index($0, h) == 1 { f = 1 } f { print; n = gsub(/[{]/, "{"); m = gsub(/[}]/, "}"); d += n - m; if (n > 0) o = 1; if (o && d <= 0) exit }' "$1"; }

# the switch: Settings > Status Bar, right under Show Apps' Own Menus, on by default, its group's words; read in DMLoadPrefs, on unless switched off
check "Settings: Scroll Menus That Don't Fit, a switch on by default, right under Show Apps' Own Menus, posting the bar's prefsChanged" \
  "plutil -convert json -o - $P | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; i=[n for n,x in enumerate(it) if x.get(\"key\")==\"scrollMenus\"]; a=[n for n,x in enumerate(it) if x.get(\"key\")==\"appOwnMenus\"]; r=it[i[0]] if len(i)==1 else {}; sys.exit(0 if len(i)==1 and len(a)==1 and i[0]==a[0]+1 and r.get(\"cell\")==\"PSSwitchCell\" and r.get(\"default\") is True and r.get(\"label\")==\"Scroll Menus That Don\x27t Fit\" and r.get(\"defaults\")==\"com.besiktasliseba.macstatusbar\" and r.get(\"PostNotification\")==\"com.besiktasliseba.macstatusbar/prefsChanged\" and r.get(\"id\")==\"SCROLL_MENUS\" else 1)'"
check "  ... its group's footer says what it does and what off does" \
  "plutil -convert json -o - $P | python3 -I -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=[x for x in it if x.get(\"id\")==\"APP_OWN_MENUS_GROUP\"]; t=g[0].get(\"footerText\",\"\") if g else \"\"; sys.exit(0 if \"Scroll Menus That Don’t Fit\" in t and \"Off, the last menus are left out.\" in t else 1)'"
check "  ... read with the other preferences: on unless switched off (gScrollMenus)" \
  "grep -qF 'CFPreferencesCopyValue(CFSTR(\"scrollMenus\"), MSB_DOMAIN' $SB && grep -qxF 'static BOOL gScrollMenus = YES;   // (Settings > Status Bar > Scroll Menus That Don'\\''t Fit: on unless switched off, DMLoadPrefs)' $SB && grep -qF '        gScrollMenus = scroll;' $SB && [ \$(grep -c 'gScrollMenus = ' $SB) = 2 ]"
check "the crash guard: a crash in statusbar/MenuStrip.h turns the switch off (0), not the whole status bar" \
  "grep -qxF \"target scrollMenus pref com.besiktasliseba.macstatusbar scrollMenus 0 1 Scroll Menus That Don't Fit|the scrolling menus in the menu bar\" $R && grep -qxF 'file MacStatusBarCore ^MenuStrip\\.h\$ scrollMenus' $R"
check "  ... MenuStrip.h has no section headers (the guard's sec rules read those) and every function the layout or a gesture calls is its own (noinline)" \
  "! grep -qE '^// (====|----)' $MS && for f in DMStripChevron DMStripOff DMStripInRoom DMStripLayout DMStripGo DMStripReveal DMStripMoved DMStripWheel DMStripBeganAt DMStripCanBegin DMStripAttach; do grep -qE \"^__attribute__\\(\\(noinline\\)\\) static [A-Za-z]+ \\\\*?\$f\\(\" $MS || exit 1; done"
# the layout: the strip after the two ends' rule laid the titles out (test-barends.sh checks the place in the layout); the room is ours
check "the bar's layout calls the strip once, the chevrons hidden with every other item of the bar (locked, collapsing) and coloured with them" \
  "[ \$(grep -c 'DMStripLayout(fg, ' $SB) = 1 ] && fn $SB 'static void DMHideAppBarItemsOf(UIView *fg) {' | grep -qF '&kStripPrevIconKey, &kStripPrevButtonKey, &kStripNextIconKey, &kStripNextButtonKey' && grep -qF '        DMStripOff(fg);   // (and the scrolling titles' \''chevrons, the strip'\''s record with them: MenuStrip.h)' $SB && fn $SB 'static void DMApplyBarItemColor(UIView *fg, UIColor *c, BOOL background) {' | grep -qF 'kCCIconKey, kStripPrevIconKey, kStripNextIconKey };' && fn $SB 'static NSArray<NSValue *> *DMBarFadeBackKeys(void) {' | grep -qF '[NSValue valueWithPointer:kStripPrevIconKey], [NSValue valueWithPointer:kStripNextIconKey]'"
check "  ... the strip's room is ours: iPadOS's region actions never start there (DMPointOverOurControl), never on a copy locked or collapsing" \
  "fn $SB 'static BOOL DMPointOverOurControl(UIView *bar, UIGestureRecognizer *g) {' | grep -qF 'if (DMStripInRoom(fg, p)) return YES;' && fn $MS '__attribute__((noinline)) static BOOL DMStripInRoom(UIView *fg, CGPoint p) {' | grep -qF 'fg.bounds.size.width < 300.0 || [objc_getAssociatedObject(fg, kBarLookLockedKey) boolValue]) return NO;'"
check "  ... only with the switch on, an app in front showing its own menus, and the rule having left one or more of them out" \
  "fn $MS '__attribute__((noinline)) static BOOL DMStripLayout(' | grep -qF 'if (!gScrollMenus || !bundle.length || appRight <= 0 || !amWant.count || amShown.count >= amWant.count || display < 0 || display > 1) { DMStripOff(fg); return NO; }'"
check "  ... each display's own place, for its app: another app in front starts at its start, with a strip or without one (before any way out)" \
  "fn $MS '__attribute__((noinline)) static BOOL DMStripLayout(' > $W/sl.txt && grep -qF 'if (bundle.length && display >= 0 && display <= 1 && ![gStripBundle[display] isEqualToString:bundle]) { gStripBundle[display] = [bundle copy]; gStripFirst[display] = nil; }' $W/sl.txt \
   && [ \$(grep -n 'gStripFirst\[display\] = nil; }' $W/sl.txt | head -1 | cut -d: -f1) -lt \$(grep -n 'DMStripOff(fg); return NO; }' $W/sl.txt | head -1 | cut -d: -f1) ] && [ \$(grep -c 'gStripFirst\[display\] = nil' $W/sl.txt) = 1 ] && grep -qF 'amBundle, barTV ? 1 : 0, amWant' $SB"
check "  ... the test's look at a refused strip is nothing in the product (MSBD_STRIP_REFUSED defined empty, never by StatusBar.x)" \
  "grep -qxF '#define MSBD_STRIP_REFUSED(fg, in)   // (the Mac test'\\''s look at a strip refused for its room: tools/test-barends.m; nothing here)' $MS && ! grep -q 'MSBD_STRIP_REFUSED' $SB"
check "  ... no room beside ours: ours join the strip, the same ones the room kept for them counts (Window while windowing, Display, Audio)" \
  "grep -qF '    if (DMActiveEngine() != DMEngineNone || DMSMEngine() || DMNativeActiveApp()) amReserve += MAX(DMAMTitleWidth(@\"Window\", timeFont), kTitleMinShown) + amGap;' $SB && grep -qF '    if (DMDispMenuWanted()) amReserve += ' $SB && grep -qF '    if (gAudioTabShown) amReserve += ' $SB && grep -qF '    return 1 | ((DMActiveEngine() != DMEngineNone || DMSMEngine() || DMNativeActiveApp()) ? 2 : 0) | (DMDispMenuWanted() ? 4 : 0) | (gAudioTabShown ? 8 : 0);' $MS"
check "  ... a menu asked to open whose title the strip does not show: the strip shows it first (AppMenus.h)" \
  "grep -qF '        if ((!b || b.hidden) && DMStripReveal(f, menu)) {' ../statusbar/AppMenus.h && grep -qF 'static BOOL DMStripReveal(UIView *fg, NSString *title);' $SB"
# the gestures
check "the gestures: a finger's swipe (fingers and the Pencil, never the pointer's click and drag; a tap ends at once), a two-finger scroll, a wheel's notches" \
  "fn $MS '__attribute__((noinline)) static void DMStripAttach(UIView *fg) {' > $W/att.txt; grep -qF 'touch.allowedTouchTypes = @[@(UITouchTypeDirect), @(UITouchTypePencil)];' $W/att.txt && grep -qF 'touch.delaysTouchesEnded = NO;' $W/att.txt && grep -qF 'swipe.allowedTouchTypes = @[];' $W/att.txt && grep -qF 'swipe.allowedScrollTypesMask = UIScrollTypeMaskContinuous;' $W/att.txt && grep -qF 'wheel.allowedTouchTypes = @[];' $W/att.txt && grep -qF 'wheel.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;' $W/att.txt && grep -qF 'objc_setAssociatedObject(fg, kStripHandlerKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);' $W/att.txt"
check "  ... made once per copy, only the first time it has a strip; a touch outside the strip's room is never looked at" \
  "grep -qF 'if (objc_getAssociatedObject(fg, kStripHandlerKey)) return;' $MS && [ \$(grep -c 'DMStripAttach(fg);' $MS) = 1 ] && grep -qF 'return fg && DMStripInRoom(fg, [touch locationInView:fg]);' $MS"
check "  ... never under one of our menus open on that screen (F-7), never locked, a finger only sideways (up and down are iPadOS's pulls); a trackpad scroll from where the pointer is (DMStripBeganAt: its location less its translation), a wheel's location as UIKit gives it, inside the room itself" \
  "fn $MS '__attribute__((noinline)) static BOOL DMStripCanBegin(UIView *fg, CGPoint p, CGPoint velocity, BOOL finger) {' > $W/cb.txt; grep -qF 'if (!DMStripInRoom(fg, p) || DMBarLockedNow() || fg.hidden || !fg.window) return NO;' $W/cb.txt && grep -qF 'if (gOverlay && (fg.window.screen ?: ms) == (gOverlay.window.screen ?: ms)) return NO;' $W/cb.txt && grep -qF 'return !finger || fabs(velocity.x) > fabs(velocity.y);' $W/cb.txt && grep -qF 'if (!DMStripCanBegin(fg, DMStripBeganAt(fg, (UIPanGestureRecognizer *)g, g == self.swipe), v, finger)) return NO;' $MS \
   && grep -qF 'if (lead < st->in.start || lead > st->in.end) return NO;' $W/cb.txt && fn $MS '__attribute__((noinline)) static CGPoint DMStripBeganAt(UIView *fg, UIPanGestureRecognizer *g, BOOL moving) {' > $W/ba.txt && grep -qF 'if (!moving) return p;' $W/ba.txt && grep -qF 'return CGPointMake(p.x - t.x, p.y - t.y);' $W/ba.txt"
check "  ... a wheel: one title a notch; the chevrons are buttons an assistive feature uses as well (More Menus, Previous Menus)" \
  "grep -qF 'if (now - self.wheelAt < 0.08) return;' $MS && grep -qF 'b.accessibilityLabel = before ? @\"Previous Menus\" : @\"More Menus\";' $MS && grep -qF 'DMAXButton *b = [DMAXButton buttonWithType:UIButtonTypeCustom];' $MS"
check "  ... a move lays that copy out again at once and the other copies of its display at their next pass; the slide honours Reduce Motion" \
  "fn $MS '__attribute__((noinline)) static void DMStripGo(UIView *fg, int f, NSString *why) {' | grep -qF 'if (c != fg && (DMExternalScreenOf(c) != nil) == (d == 1)) [c setNeedsLayout];' && grep -qF 'BOOL still = MSBReduceMotion();' $MS"
check "common/MenuStrip.h is plain C (this test runs it), statusbar/MenuStrip.h is included by StatusBar.x, and no em or en dash in the new files" \
  "! grep -qE '@|UIKit|UIView|NSString' $MC && grep -qF '#include \"MenuStrip.h\"   // (Scroll Menus That Don'\\''t Fit, 1.8.8.2' $SB && ! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' $MC $MS test-menustrip.c test-menustrip.sh && ! LC_ALL=C grep -q '[^ -~	]' $MC $MS test-menustrip.c"

# made-to-fail copies of common/MenuStrip.h: each must fail R1-R11 (or not build)
mi=0
mtf() {   # $1 what, $2 sed
  local d="$W/m$((++mi))"; mkdir -p "$d"
  sed -E "$2" "$MC" > "$d/in.h"; cmp -s "$d/in.h" "$MC" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }
  local o; o=$(run "$d/in.h" "$d/b"); local r=$?
  if [ $r = 98 ]; then echo "PASS  made-to-fail ($1): caught (does not build)"
  elif [ $r != 0 ]; then echo "PASS  made-to-fail ($1): caught ($(echo "$o" | grep -o '^FAIL  R[0-9]*' | sort | uniq -c | awk '{printf "%s%s x%s", s, $3, $1; s=", "}'))"
  else echo "FAIL  made-to-fail ($1): not caught"; fails=1; fi
}
mtf "no room kept for the chevron after the titles" 's/^    double limit = s->end - s->gap - s->chev;(.*)$/    double limit = s->end;\1/'
mtf "the room without the chevrons" 's/s->end - s->start >= 2\.0 \* \(s->chev \+ s->gap\) \+ s->minShown/s->end - s->start >= s->minShown/'
mtf "the last first one too early" 's/^        if \(MSBDStripFitsFrom\(s, f, s->start \+ s->chev \+ s->gap\)\) last = f;$/        if (MSBDStripFitsFrom(s, f, s->start)) last = f;/'
mtf "no chevron before the titles" 's/^    if \(first > 0\) \{ o\.prev = 1; o\.prevX = x; x \+= s->chev \+ s->gap; \}$/    if (first > 0) { o.prev = 0; o.prevX = x; }/'
mtf "a page back to the title before only" 's/^    int want = o\.first - 1, best = want;$/    int want = o.first - 1, best = want; return best;/'
mtf "a swipe the wrong way" 's/^    double want = MSBDStripOffsetOf\(s, first\) - moved, maxO = MSBDStripOffsetOf\(s, last\);$/    double want = MSBDStripOffsetOf(s, first) + moved, maxO = MSBDStripOffsetOf(s, last);/'
mtf "a first title too wide never cut short (nothing shows)" 's/^    if \(o\.count == 0 && limit - x >= s->minShown - 1e-6\) \{.*$/    if (0) {/'
mtf "reveal of a title after the strip stops short" 's/^    for \(int f = o\.first \+ 1; f <= last; f\+\+\) \{ MSBDStripOut p = MSBDStripAt\(s, f\); if \(i < f \+ p\.count\) return f; \}$/    return o.first;/'
[ "$fails" = 0 ] && echo "test-menustrip: all pass" || { echo "test-menustrip: FAILED"; exit 1; }
