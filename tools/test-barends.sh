#!/bin/bash
# test-barends.sh: the menu bar's two ends never meet (1.8.8.1; the owner, 21 Nov: in portrait on the smaller iPads, do the app's menus in the bar reach
# the right side?). The real code of the bar's layout from statusbar/StatusBar.x (from the end of the traffic lights to the items' colour: the
# titles and the whole right end) with the real helpers it calls from StatusBar.x, AppMenus.h, BatteryMenu.h, WiFiMenu.h and BarUnlock.h, and
# common/BarEnds.h, built for the Mac (Mac Catalyst) and run in bars of every iPad's portrait width (744 mini, 768 Air 2 / 9.7, 810 9th gen,
# 820 Air / 10th gen, 834 11", 1024 12.9") at each Menu Bar Size, with three right ends (light, heavy, the most iPadOS 15-18 shows at once with
# ours; 1.8.8.2: and one where iPadOS's AirPods item is the first thing of it) and three sets of titles, left to right and right to left, from
# either date state (test-barends.m). With F3's AirPods button and the battery's button, the real code of both (statusbar/AirPodsMenu.h,
# statusbar/BatteryMenu.h) on iPadOS's bar as they read it: no title's touch area meets one of the right end's (C9), and both buttons stay over
# their items after the layout, the date's turn included (C10); where the tree's F3 covers the glyph alone too (the 1.8.8.1.1 rework,
# DMAPBluetoothState), a fifth right end with that glyph alone first (TB_AP_GLYPH) and a made-to-fail copy for it. BE_SB_X: another StatusBar.x (e.g.
# 1.8.8's, which must fail); BE_ENDS: another BarEnds.h; BE_BEFORE_X: 1.8.8's StatusBar.x for C3 (wherever 1.8.8's titles end a title gap or
# more before its right end, every frame as 1.8.8 lays it out); BE_TABLE=1: the numbers, per width and size. Then site checks and made-to-fail copies.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
if [ -n "$BE_KEEP" ]; then W=$BE_KEEP; mkdir -p "$W"; else W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; fi
X0=${BE_SB_X:-../statusbar/StatusBar.x}; E0=${BE_ENDS:-../common/BarEnds.h}; AP0=../statusbar/AirPodsMenu.h
AM=../statusbar/AppMenus.h; BM=../statusbar/BatteryMenu.h; WM=../statusbar/WiFiMenu.h; BU=../statusbar/BarUnlock.h
fn() { awk -v h="$2" 'f == 0 && index($0, h) == 1 { f = 1 } f { print; n = gsub(/[{]/, "{"); m = gsub(/[}]/, "}"); d += n - m; if (n > 0) o = 1; if (o && d <= 0) exit }' "$1"; }   # a function by its first line
line() { awk -v h="$2" 'index($0, h) == 1 { print; exit }' "$1"; }

build() {   # $1 StatusBar.x, $2 BarEnds.h, $3 dir, $4 quiet, $5 statusbar/AirPodsMenu.h (default the tree's)
  local X=$1 d=$3 AP=${5:-$AP0}; mkdir -p "$d"
  if [ -f "$2" ]; then cp "$2" "$d/BarEnds.h"; else : > "$d/BarEnds.h"; fi
  awk 'index($0, "static const CGFloat kAppGap = ") == 1 { f = 1 } f { print } f && index($0, "static const CGFloat kSpotHitSlop = ") == 1 { exit }' "$X" > "$d/consts.inc"
  { awk 'index($0, "static inline BOOL DMBarRTL(") == 1 { f = 1 } f { print } f && index($0, "static inline CGFloat DMBarShiftOf(") == 1 { exit }' "$X"
    fn "$X" 'static inline CGRect DMBarUntransformed(UIView *v) {'
    line "$X" 'static BOOL gApplyingClockTransform = NO;'
    fn "$X" 'static void DMShiftLabel(UIView *fg, UIView *label, CGFloat targetLeft) {'
    fn "$X" 'static BOOL DMLabelShown(UIView *v) {'
    fn "$X" 'static UIFont *DMTabularFont(UIFont *base) {'
    fn "$X" 'static NSString *DMDateString(void) {'
    fn "$X" 'static NSString *DMTimeString(void) {'
    line "$X" '#define kTitleMinShown 30.0'
    fn "$X" 'static CGFloat DMLayoutTitle(UIView *fg, BOOL rtl, const void *labelKey, const void *buttonKey, const void *pillKey,'
    fn "$X" 'static BOOL DMLogoInkAt100(CGRect *ink) {'
    fn "$X" 'static UIImage *DMVPNGlyph(CGFloat textSize) {'
    fn "$X" 'static CGRect DMImageInkRect(UIImage *img) {'; } | sed -E 's/\[NSLocale autoupdatingCurrentLocale\]/TLocale()/g; s/\[NSDate date\]/TNow()/g' > "$d/helpers.inc"
  { line "$AM" 'static const void *kAMShownKey = &kAMShownKey;'
    fn "$AM" 'static void DMAMHideSlots(UIView *fg, NSUInteger from) {'
    fn "$AM" 'static CGFloat DMAMTitleWidth(NSString *text, UIFont *baseFont) {'; } > "$d/appmenus.inc"
  { fn "$BM" 'static UIImage *DMBattCCGlyph(CGFloat timePt) {'
    fn "$BM" 'static void DMBattCCLightCopy(UIView *fg) {'
    fn "$BM" 'static MSBDBattRightSide DMBattCCLayout(UIView *fg, BOOL rtl, CGFloat clockEdge,'; } > "$d/batt.inc"
  { fn "$WM" 'static UIImage *DMWiFiFanImage(NSInteger bars, CGFloat height) {'
    line "$WM" 'static const CGFloat kWiFiIconH = '
    fn "$WM" 'static CGFloat DMWiFiIconHeight(CGFloat k) {'
    fn "$WM" 'static UIView *DMWiFiMakeIcon(void) {'
    fn "$WM" 'static CGSize DMWiFiApplyIconState(UIView *icon, CGFloat k) {'
    fn "$WM" 'static CGFloat DMWiFiLayoutIcon(UIView *fg, CGFloat left, CGFloat midY, CGFloat k) {'; } > "$d/wifi.inc"
  { fn "$BU" 'static inline double MSBDTimeLabelWidth('
    fn "$X" 'static UIImage *DMMuteGlyph(CGFloat iconH) {'
    fn "$X" 'static UIImageView *DMMuteIcon(UIView *fg, CGFloat k) {'; } > "$d/late.inc"
  # (1.8.8.2: the right end's two buttons over iPadOS's own items, as the layout places them -- the AirPods button, F3, then the battery's --
  #  the real code, cut as test-airpodsmenu cuts it, on iPadOS's bar as their readers see it: test-barends.m TBar)
  { line "$BM" 'static const void *kBattAXWasKey = '
    fn "$BM" 'static Class DMBattItemClass(void) {'
    fn "$BM" 'static BOOL DMBattViewShown(UIView *v, UIView *fg) {'
    fn "$BM" 'static NSArray<UIView *> *DMBattItemViews(UIView *fg) {'
    fn "$BM" 'static CGRect DMBattItemRect(UIView *fg, NSArray<UIView *> *views) {'
    fn "$BM" 'static void DMBattCoverAX(UIView *fg, NSArray<UIView *> *views, BOOL cover) {'
    fn "$BM" 'static void DMBattLayoutButton(UIView *fg, CGFloat left, CGFloat k) {'
    line "$AP" 'static const void *kAPAXWasKey = '
    fn "$AP" 'static BOOL DMAPTypes(id obj, SEL sel, const char *types) {'
    fn "$AP" 'static id DMAPObj(id obj, SEL sel) {'
    fn "$AP" 'static Class DMAPItemClass(void) {'
    fn "$AP" 'static BOOL DMAPItemViews(UIView *fg, '
    # (where the tree's F3 asks the bar's data for the glyph alone -- b1882/f3's rework, 1.8.8.1.1: DMAPBluetoothState -- that real function too)
    grep -q '^static long long DMAPBluetoothState(' "$AP" && fn "$AP" 'static long long DMAPBluetoothState('
    fn "$AP" 'static void DMAPCoverAX(UIView *fg, NSArray<UIView *> *views, BOOL cover) {'
    fn "$AP" 'static CGRect DMAPUnion(UIView *fg, NSArray<UIView *> *views) {'
    fn "$AP" 'static void DMAPHideButton(UIView *fg) {'
    fn "$AP" '__attribute__((noinline)) static void DMAirPodsLayoutButton(UIView *fg, CGFloat left, CGFloat k) {'; } > "$d/buttons.inc"
  awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { b = 1 } b && s == 0 && index($0, "        lights.hidden = YES;") == 1 { s = 1; next }
       s == 1 && index($0, "    }") == 1 { s = 2; next } s == 2 && index($0, "    DMApplyBarItemColor(fg, barColor, YES);") == 1 { exit } s == 2 { print }' "$X" > "$d/region.inc"
  local n; n=$(wc -l < "$d/region.inc" | tr -d ' ')
  [ "$n" -gt 300 ] && grep -q 'CGFloat titleMaxRight = ' "$d/region.inc" && grep -q 'left = DMLALayoutPills(fg, left, timeCentre.y, k);' "$d/region.inc" \
    && grep -q 'CGFloat DMLayoutTitle(' "$d/helpers.inc" && grep -q 'DMWiFiLayoutIcon' "$d/wifi.inc" && grep -q 'DMBattCCLayout' "$d/batt.inc" && grep -q 'DMMuteIcon' "$d/late.inc" \
    && [ "$(grep -cE '^(__attribute__\(\(noinline\)\) )?static [^(]*[ *](DMBattItemClass|DMBattViewShown|DMBattItemViews|DMBattItemRect|DMBattCoverAX|DMBattLayoutButton|DMAPTypes|DMAPObj|DMAPItemClass|DMAPItemViews|DMAPCoverAX|DMAPUnion|DMAPHideButton|DMAirPodsLayoutButton)\(' "$d/buttons.inc")" = 14 ] \
    && grep -q '^static const void \*kAPAXWasKey = ' "$d/buttons.inc" && grep -q '^static const void \*kBattAXWasKey = ' "$d/buttons.inc" \
    || { echo "FAIL  the code was not found in $X ($n lines of the layout)"; return 99; }
  # (where the tree's F3 puts its button over the glyph alone too -- the 1.8.8.1.1 rework, DMAPBluetoothState --: the bars also with that item first)
  local GL=-DTB_AP_GLYPH=0; grep -q '^static long long DMAPBluetoothState(' "$AP" && GL=-DTB_AP_GLYPH=1
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc $GL -Wall -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework QuartzCore -framework CoreText -framework CoreGraphics -o "$d/t" test-barends.m 2> "$d/cc.txt" \
    || { [ -n "$4" ] || head -30 "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$4" ] && { echo "FAIL  warnings:"; head -30 "$d/cc.txt"; return 97; }
  return 0
}

fails=0
build "$X0" "$E0" "$W/real" || exit 1
[ -n "$BE_TABLE" ] && { echo "== the numbers ($X0): the right end's leading edge, the titles' end, the gap (minus: they overlap)"; "$W/real/t" table; "$W/real/t" dates; }
"$W/real/t" check "$W/real/dump.txt"; [ $? = 0 ] || fails=1

# C3: before / after, where the rule has nothing to do (1.8.8's titles end a title gap or more before its right end): every frame as 1.8.8's
if [ -n "$BE_BEFORE_X" ]; then
  if build "$BE_BEFORE_X" /nonexistent "$W/before" q; then
    "$W/before/t" check "$W/before/dump.txt" > "$W/before/check.txt" 2>&1
    r=$(python3 -I - "$W/before/dump.txt" "$W/real/dump.txt" <<'EOF'
import re, sys
def rows(p):
    d = {}
    for l in open(p):
        tag, nums, frames = l.rstrip('\n').split(' | ')
        d[tag] = (nums, frames)
    return d
b, a = rows(sys.argv[1]), rows(sys.argv[2])
same = diff = bad = 0; ex = []
for tag, (nb, fb) in b.items():
    na, fa = a[tag]
    m = dict(re.findall(r'(lead|titles|gap|date|n) (-?[0-9.]+)', nb))
    size = int(re.search(r'size (\d)', tag).group(1)); k = [1.0, 1.125, 1.25][size]
    w = float(re.search(r'^w (\d+)', tag).group(1)); half = w / 2 - 24
    dw = float(re.search(r'dw (-?[0-9.]+)', nb).group(1))
    # (free: the date stays where it shows (a title gap, half a point either way), and a copy that had given it up takes it back only from half
    #  a point past the gap: BarEnds.h MSBDBarDateShows, so it does not switch at every layout)
    free = float(m['gap']) >= 16 * k + (0.5 if tag.endswith('from off') else -0.5) - 1e-6 or int(m['n']) == 0
    if fa == fb: same += 1
    else: diff += 1
    if 'region 1' not in tag and free and fa != fb:
        bad += 1; ex.append(tag)
print(same, diff, bad, ex[:5])
EOF
)
    set -- $r
    if [ "$3" = 0 ]; then echo "PASS  C3 before / after: every frame as 1.8.8's wherever its titles ended a title gap or more before its right end ($1 bars the same, $2 changed: where the two met)"
    else echo "FAIL  C3 before / after: $3 bars changed where the rule had nothing to do: ${*:4}"; fails=1; fi
    echo "   (1.8.8's code here: $(tail -1 "$W/before/check.txt" | cut -c1-90)...; $(grep -c '^FAIL  C1' "$W/before/check.txt") C1 lines shown)"
  else echo "FAIL  C3: $BE_BEFORE_X did not build"; fails=1; fi
fi

# site checks (what the bars can't see)
S=$X0; E=$E0
fnb() { awk 'index($0, "- (void)dm_layoutLogoBody {") == 1 { f = 1 } f { print } f && /^[}]/ { exit }' "$S"; }
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the titles are laid out after the right end (its icons and ours), before the items' colour; the left half's line as before (D62)" \
  "fnb | awk '/left = DMLALayoutPills\\(fg, left, timeCentre.y, k\\);/{a=NR} /^    titleMaxRight = MSBDBarTitlesEnd\\(titleMaxRight, dateOff \\? rightLead : rightLeadOther, endsGap\\);/{b=NR} /CGFloat appRight = DMLayoutTitle\\(/{c=NR} /^    DMApplyBarItemColor\\(fg, barColor, YES\\);/{e=NR} END{exit !(a && a < b && b < c && c < e)}' && [ \$(grep -cF 'CGFloat titleMaxRight = locked ? 0.0 : fg.bounds.size.width / 2.0 - 24.0;   // stay in the left half' $S) = 1 ]"
check "the date's turn lays the copy out again once, at once (never from inside that layout), and clears its mark on the way out" \
  "fnb | grep -qxF '        if (!gDMBarDateTurn) {' && fnb | grep -qxF '            @try { [self dm_layoutLogoBody]; } @finally { gDMBarDateTurn = NO; }' && [ \$(grep -c 'gDMBarDateTurn = YES;' $S) = 1 ] && [ \$(grep -c 'dm_layoutLogoBody\\]' $S) = 2 ]"
check "the copy's date mark: set in one place (the turn), read in one (the clock), only while the time shows" \
  "[ \$(grep -c 'objc_setAssociatedObject(fg, kBarDateOffKey' $S) = 1 ] && [ \$(grep -c 'kBarDateOffKey' $S) = 3 ] && grep -qF 'BOOL dateOff = tw > 0 && [objc_getAssociatedObject(fg, kBarDateOffKey) boolValue];' $S"
check "at the turn the status icons move at once (a slide went over the date), every other big move slides as before" \
  "grep -qF '        if (gDMBarDateTurn) [trailing.layer removeAnimationForKey:@\"transform\"];' $S && grep -qF '        if (!gDMBarDateTurn && fabs(DMBarShiftOf(rtl, trailing.transform) - want) > 20.0 && fg.window && !fg.window.hidden && !lookWasLocked && ![trailing.layer animationForKey:@\"transform\"])' $S"
check "F3's AirPods button, then the battery's, placed after the status icons' move and before the right end's start is read, in every layout (the date's turn too): one call each" \
  "fnb | awk '/^        else trailing.transform = DMBarShift\\(rtl, want\\);/{a=NR} /^        DMAirPodsLayoutButton\\(fg, left, k\\);/{b=NR} /^        DMBattLayoutButton\\(fg, left, k\\);/{c=NR} /^            rightLead = MSBDBarEndLead\\(iconsEnd, trailLead, regionLead, ours, 0\\.0\\);/{e=NR} END{exit !(a && a < b && b < c && c < e)}' && [ \$(grep -c 'DMAirPodsLayoutButton(fg, ' $S) = 1 ] && [ \$(grep -c 'DMBattLayoutButton(fg, ' $S) = 1 ]"
check "BarEnds.h is plain C (the Mac test runs its numbers) and StatusBar.x includes it" \
  "! grep -qE '@|UIKit|UIView|NSString' $E && grep -qF '#include \"../common/BarEnds.h\"' $S"
check "no em or en dash in the test or BarEnds.h" "! grep -q \$'\\xe2\\x80\\x94\\|\\xe2\\x80\\x93' test-barends.m test-barends.sh $E"

# made-to-fail copies: each must fail (a bar check, or not build)
mtf() {   # $1 what, $2 file (sbx|ends|ap: statusbar/AirPodsMenu.h), $3 sed
  local d="$W/m$((++mi))" x=$X0 e=$E0 a=$AP0
  mkdir -p "$d"
  if [ "$2" = sbx ]; then x="$d/StatusBar.x"; sed -E "$3" "$X0" > "$x"; cmp -s "$x" "$X0" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }
  elif [ "$2" = ap ]; then a="$d/AirPodsMenu.h"; sed -E "$3" "$AP0" > "$a"; cmp -s "$a" "$AP0" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }
  else e="$d/BarEnds.h"; sed -E "$3" "$E0" > "$e"; cmp -s "$e" "$E0" && { echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; }; fi
  build "$x" "$e" "$d/b" q "$a" || { echo "PASS  made-to-fail ($1): caught (does not build)"; return; }
  local out; out=$(TB_FIRST=1 "$d/b/t" check 2>&1)
  if [ $? != 0 ]; then echo "PASS  made-to-fail ($1): caught ($(echo "$out" | grep -o '^FAIL  C[0-9]*' | sort | uniq -c | awk '{printf "%s%s x%s", s, $3, $1; s=", "}'))"
  else echo "FAIL  made-to-fail ($1): not caught"; fails=1; fi
}
mi=0
mtf "the titles' room without the right end (1.8.8)" sbx '/^    titleMaxRight = MSBDBarTitlesEnd\(titleMaxRight, dateOff \? rightLead : rightLeadOther, endsGap\);$/d'
mtf "the date never gives way" sbx 's/^    if \(MSBDBarDateShows\(/    if (0 \&\& MSBDBarDateShows(/'
mtf "the date always gives way" ends 's/^    return shown \? need <= leadWithDate \+ 0\.5 : need <= leadWithDate - 0\.5;$/    return 0;/'
mtf "no layout again at the turn" sbx 's/^            @try \{ \[self dm_layoutLogoBody\]; \} @finally \{ gDMBarDateTurn = NO; \}$/            gDMBarDateTurn = NO;/'
mtf "no gap kept before the right end" ends 's/^    double e = leadNoDate - gap;$/    double e = leadNoDate;/'
mtf "our icons not counted in the right end" ends '/^    if \(icons < DBL_MAX\) icons -= ours;$/d'
mtf "iPadOS's other region's items not counted" sbx '/^                if \(x > fg\.bounds\.size\.width \/ 2\.0 && x < regionLead\) regionLead = x;$/d'
mtf "the date's room without the gap before the time" sbx 's/^            CGFloat dateRoom = tw > 0 && proxyW > 0 \? proxyW \+ kClockGap \* k : 0\.0;$/            CGFloat dateRoom = tw > 0 \&\& proxyW > 0 ? proxyW : 0.0;/'
mtf "the left half wider (D62 is the owner's)" sbx 's|^    CGFloat titleMaxRight = locked \? 0\.0 : fg\.bounds\.size\.width / 2\.0 - 24\.0;|    CGFloat titleMaxRight = locked ? 0.0 : fg.bounds.size.width / 2.0 + 24.0;|'
mtf "the date hidden but still taking its room" sbx 's/^    CGFloat dw = dateOff \? 0\.0 : needProxy/    CGFloat dw = 0 ? 0.0 : needProxy/'
mtf "the AirPods button not placed again in the date's turn layout (F3's button left where the icons were)" sbx 's/^        DMAirPodsLayoutButton\(fg, left, k\);$/        if (!gDMBarDateTurn) DMAirPodsLayoutButton(fg, left, k);/'
mtf "the AirPods button reaching 12 pt x k before its item (into a title's touch area)" ap 's/MSBDAirPodsButtonSpan\(lead, trail, 4\.0 \* k, left - 2\.0 \* k, /MSBDAirPodsButtonSpan(lead, trail, 12.0 * k, left - 12.0 * k, /'
# (the tree's F3 covers the glyph alone: the bars with it first are built and checked -- its button taken away there must be caught)
grep -q '^static long long DMAPBluetoothState(' "$AP0" && mtf "the AirPods glyph alone left without its button (F3's glyph-alone bars)" ap 's/long long state = views\.count && !battShown \? DMAPBluetoothState\(fg, &stateRead\) : MSBD_AP_BT_HEADPHONES;/long long state = views.count \&\& !battShown ? 0 : MSBD_AP_BT_HEADPHONES; stateRead = views.count \&\& !battShown;/'
[ "$fails" = 0 ] && echo "test-barends: all pass" || { echo "test-barends: FAILED"; exit 1; }
