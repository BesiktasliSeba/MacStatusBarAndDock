#!/bin/bash
# test-barbackground.sh: Status Bar Background, the text follows the bar (1.8.7.5 WHITEBAR, KT 14 Nov on the 17.5: "if I make the status bar
# white, the text doesnt go black so it becomes a white bar"; prefs Automatic, #FFFFFF, 0.36). See test-barbackground.m. The real code is cut out
# of statusbar/StatusBar.x (BB_SB_X: another copy, e.g. the code before the fix, which has no dark text: what it lacks is stood in by "as before")
# with common/BarBackground.h (BB_HDR) and run on the Mac (Mac Catalyst: UIKit's own status bar style attributes and string view); then site
# checks (the hook, its install, the order in DMApplyBarItemColor, the footer, the crash map); then made-to-fail copies, each must fail.
# What is behind the bar takes our own Control Center's rule from statusbar/CCPanel.h and CC18Shape.h (BB_CCP_H, BB_CC18_H: the code before CCMAC
# has none: there Control Center counted whatever showed it).
# 1.8.7.6 FULLBAR (the 17.5's trace of 16 Nov): the Stage Manager engine's top bar rule (DMSMCardIsFullSize, DMSMInFullScreenCard,
# DMSMMainBarOn, DMSMStripIsMenuBar) and -dm_layoutLogoBody's branch for a window card's strip that is not the top bar are cut out too, as they
# are, so the 17.5's sequence is played on the screen's own bar (SBStatusBarWindow) and the window cards' strips (SBMainSwitcherWindow): a dark
# app in full screen alone, back, Settings in full screen with Clock's window beside it, Control Center opened and closed, Background Off.
# Round 1 (the review): the real DMTrailingIconColor and DMSMCardOfView too, and a second display (the A12Z's TV: windows on a screen of their
# own) for what is over a window, asked for its own screen.
# 1.8.7.6, the 17.5's crash at a Notification Center pull (release-1.8.7.6.md "NC-pull crash ... ROOT CAUSE"): the stand-in bar runs UIKit's own
# constraint pass, whose -updateConstraints is StatusBar.x's hook (the count, gDMBarConstraintDepth) around the bar's own pass, which places the
# time label again (our -setTextColor: and -tintColorDidChange hooks) and, for a closed-up copy, DMClosedUpClockBack and DMClockBackLayout as they
# are: ncpull (our black ends as the Cover Sheet comes, and comes back), ncpullfull (over a full-screen window: DMBarWindowText), ncpullclosedup
# (the way back of a copy laid out without a clock), ncpullinlayout (the copy laid out inside the pass), nothookeduc. The code before the fix raises UIKit's "The layout constraints still need update
# after sending -updateConstraints" there, as on the 17.5. Site checks: every write of a status bar's colour of ours in the tree consults the pass
# first; the hook's install; the crash map.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# (1.8.7.6's site checks, run by sites(): the constraint pass's code in its sections of StatusBar.x, and every writer of a status bar's colour)
cat > "$W/bb-crashsec.py" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bb'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
g['_paths'] = {'StatusBar.x': sys.argv[2]}; lines = open(sys.argv[2], errors='replace').read().split('\n')
def line_of(head, after=None):
    a = lines.index(after) if after in lines else 0
    for i in range(a, len(lines)):
        if lines[i].startswith(head): return i + 1
    return 0
for name, head, after in [('_DMBarDecideNextTurn', 'static void DMBarDecideNextTurn(', None), ('___DMBarDecideNextTurn_block_invoke', 'static void DMBarDecideNextTurn(', None),
                          ('__logos_method$BarForeground$_UIStatusBar$updateConstraints', '- (void)updateConstraints {', '%group BarForeground'),
                          ('_DMBarForegroundInit', 'static void DMBarForegroundInit(', None), ('_DMClockBackLayout', 'static void DMClockBackLayout(UIView *fg) {', None)]:
    n = line_of(head, after)
    print(g['classify']('MacStatusBarCore', name, 'StatusBar.x', g['section_of']('', 'StatusBar.x', n) if n else '', rules, im, hits) if n else 'none', end=' ')
EOF
cat > "$W/bb-writers.py" <<'EOF'
import os, re, sys
x, root = sys.argv[1], sys.argv[2]
files = [x]
for d, ds, fs in os.walk(root):
    ds[:] = [k for k in ds if k not in ('tools', 'third_party', 'packages') and not k.startswith('.')]
    for f in fs:
        q = os.path.join(d, f)
        if f.endswith(('.x', '.xm', '.h', '.m', '.mm')) and os.path.realpath(q) != os.path.realpath(os.path.join(root, 'statusbar', 'StatusBar.x')): files.append(q)
write = re.compile(r'@selector\(_?(setForegroundColor|setStyleAttributes|setStyleRequest|requestStyle)[A-Za-z]*:\)|\[[^\[\]]*\s_?(setForegroundColor|setStyleAttributes|setStyleRequest|requestStyle)[A-Za-z]*:|\.foregroundColor\s*=[^=]|forKey:@"foregroundColor"')
notwrite = re.compile(r'class_getInstanceMethod|instancesRespondToSelector|respondsToSelector|method_getTypeEncoding|MSHookMessage|class_replaceMethod|class_addMethod')
gate = re.compile(r'^    if \(gDMBarConstraintDepth > 0\) \{ DMBarDecideNextTurn\(fg, .*\); return( NO)?; \}')
ok, bad = [], []
for q in files:
    try: lines = open(q, errors='replace').read().split('\n')
    except OSError: continue
    for i, l in enumerate(lines):
        code = l.split('//')[0]
        if not write.search(code) or notwrite.search(code) or re.match(r'\s*[-+]\s*\(', code): continue
        j = i
        while j > 0 and not (re.match(r'(static |[-+] \()', lines[j]) and lines[j].split('//')[0].rstrip().endswith('{')): j -= 1
        m = re.search(r'([A-Za-z_][A-Za-z0-9_]*)\(', lines[j]); where = '%s %s' % (os.path.basename(q), m.group(1) if m else lines[j][:30])
        (ok if any(gate.match(k) for k in lines[j:i]) else bad).append(where)
print('%s | %s' % (', '.join(ok), ', '.join(bad)))
EOF
X0=${BB_SB_X:-../statusbar/StatusBar.x}; H0=${BB_HDR:-../common/BarBackground.h}; P0=${BB_PLIST:-../statusbar/macstatusbarprefs/Resources/Root.plist}
WP0=${BB_WP_H:-../statusbar/DesktopWallpaper.h}
CCP0=${BB_CCP_H:-../statusbar/CCPanel.h}; C180=${BB_CC18_H:-../statusbar/CC18Shape.h}
fn() { awk -v h="$2" 'index($0, h) == 1 { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }   # one function, by its first line
fn1() { awk -v h="$2" '!f && index($0, h) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # one function, by its braces
fnany() { awk -v h="$2" 'index($0, "static ") == 1 && index($0, h) { f = 1; print; next } f { print } f && /^[}]/ { exit }' "$1"; }   # by a part of it
FOOTER='A light color turns the status bar text and icons dark, as on a Mac, unless its opacity is too low to make the bar light. A dark color is used while the text is light, and a light background goes behind dark text.'

build() {   # $1 StatusBar.x, $2 BarBackground.h, $3 dir, $4 quiet (DesktopWallpaper.h: $TWP, a made-to-fail copy's, else WP0; CCPanel.h and
            # CC18Shape.h: $TCCP / $TC18 the same way)
  local X=$1 d=$3 q=$4 WP=${TWP:-$WP0} CCP=${TCCP:-$CCP0} C18=${TC18:-$C180}
  mkdir -p "$d"; cp "$2" "$d/BarBackground.h"; cp ../common/BatteryInside.h "$d/BatteryInside.h"
  { awk 'index($0, "typedef NS_ENUM(int, DMBackgroundMode)") == 1 { f = 1 } f && /^$/ { exit } f { print }' "$X"; fn "$X" 'static UIColor *DMParseHexColor(NSString *text) {'; } > "$d/bb-globals.inc"
  {
    fn "$X" 'static BOOL DMBackgroundWanted(void) {'
    grep -F 'static const void *kBackgroundLightKey = &kBackgroundLightKey;' "$X"
    fnany "$X" 'DMApplyBackground(UIView *fg, UIColor *textColor) {'
    fn "$X" 'static UIColor *DMLabelDrawnColor(UILabel *l) {'
    fn "$X" 'static UIColor *DMBarItemColor(UIView *fg, UIView *timeLabel) {'
    awk 'index($0, "static BOOL gBarFgHooked = NO;") == 1 { f = 1 } index($0, "// background: our bar") == 1 { exit } f { print }' "$X"
    fn "$X" 'static void DMApplyBarItemColor(UIView *fg, UIColor *c, BOOL background) {'
  } > "$d/bb-real.inc"
  grep -q 'DMApplyBarItemColor' "$d/bb-real.inc" && grep -q 'DMApplyBackground' "$d/bb-real.inc" && grep -q 'gBgOpacity' "$d/bb-globals.inc" || { echo "FAIL  the bar's code was not found in $X"; return 99; }
  # our layout's branch for a copy collapsed under 300 pt (-dm_layoutLogoBody), run as it is
  awk 'index($0, "    if (fg.bounds.size.width < 300.0) {") == 1 { f = 1 } f { print } f && $0 == "    }" { exit }' "$X" > "$d/bb-narrow.inc"
  grep -q 'DMLAHidePills(fg);' "$d/bb-narrow.inc" || { echo "FAIL  the layout's narrow branch was not found in $X"; return 99; }
  # ... and its branch before it, for a window card's strip that is not the top bar (the Stage Manager engine), and the top bar rule it asks
  awk 'index($0, "    if (DMSMStripHidden(fg)) {") == 1 || index($0, "    if (DMSMEngine() && [NSStringFromClass([fg.window class]) isEqualToString:") == 1 { f = 1 } f { print } f && $0 == "    }" { exit }' "$X" > "$d/bb-smstrip.inc"
  { fn "$X" 'static BOOL DMSMCardIsFullSize(UIView *card) {'; fn "$X" 'static BOOL DMSMInFullScreenCard(UIView *v) {'
    fn "$X" 'static UIView *DMSMMainBarOn(UIScreen *scr, UIView *strip) {'
    grep -F 'static BOOL DMSMMainBarShown(UIView *strip) {' "$X"; grep -F 'static BOOL DMSMStripIsMenuBar(UIView *strip) {' "$X"
    fn "$X" 'static BOOL DMSMStripHidden(UIView *strip) {'; fn "$X" 'static UIView *DMSMCardOfView(UIView *v) {'; } > "$d/bb-sm.inc"
  # the status icons' colour, for a copy with no time label (the real one: what it gives when none of them shows)
  fn "$X" 'static UIColor *DMTrailingIconColor(UIView *trailing) {' > "$d/bb-trailing.inc"
  grep -q 'pending addObjectsFromArray' "$d/bb-trailing.inc" && grep -qF 'static UIView *DMSMCardOfView(UIView *v) {' "$d/bb-sm.inc" || { echo "FAIL  DMTrailingIconColor or DMSMCardOfView was not found in $X"; return 99; }
  grep -q 'gDMHoldOwnAlpha = YES; fg.alpha = 0.0;' "$d/bb-smstrip.inc" && grep -q 'DMSMMainBarShown(strip)' "$d/bb-sm.inc" && grep -q 'kHoldWantAlphaKey' "$d/bb-sm.inc" \
    || { echo "FAIL  the Stage Manager engine's top bar rule was not found in $X"; return 99; }
  # what is behind the bar: DesktopWallpaper.h's DMWPBarBackdrop and its type (the code before the fix has none: no picture of ours behind any bar)
  grep -F 'typedef struct { double darkest[3], lightest[3]; } MSBDWPTop;' "$WP" > "$d/bb-wptop.inc" || echo 'typedef struct { double darkest[3], lightest[3]; } MSBDWPTop;' > "$d/bb-wptop.inc"
  fn "$WP" 'static BOOL DMWPBarBackdrop(UIView *fg, MSBDWPTop *top) {' > "$d/bb-wp.inc"
  [ -s "$d/bb-wp.inc" ] || echo 'static BOOL DMWPBarBackdrop(UIView *fg, MSBDWPTop *top) { return NO; }' > "$d/bb-wp.inc"
  fn "$WP" 'static void DMWPBarBackdropTick(void) {' > "$d/bb-wptick.inc"
  # our own Control Center's rule: the panel leaves the desktop behind the bar (15-17 CCPanel.h, 18 CC18Shape.h); none before CCMAC
  { fn1 "$C18" 'static BOOL DMCC18OwnsCCBars(void) {'; fn1 "$C18" 'static BOOL DMCC18LeavesDesktop(void) {'
    fn1 "$CCP" 'static BOOL DMCCPanelOwnsCCBars(void) {'; fn1 "$CCP" 'static BOOL DMCCPanelLeavesDesktop(void) {'; } > "$d/bb-ccp.inc"
  grep -q 'DMCCPanelLeavesDesktop' "$d/bb-ccp.inc" || echo 'static BOOL DMCCPanelLeavesDesktop(void) { return NO; }   /* (before CCMAC: none) */' >> "$d/bb-ccp.inc"
  [ -s "$d/bb-wptick.inc" ] || echo 'static void DMWPBarBackdropTick(void) {}' > "$d/bb-wptick.inc"
  cat "$d/bb-real.inc" "$d/bb-narrow.inc" "$d/bb-smstrip.inc" "$d/bb-sm.inc" | grep -oE '\bk[A-Z][A-Za-z0-9]*Key\b' | sort -u | while read -r k; do
    [ "$k" = kBackgroundKey ] && continue
    grep -qF "static const void *$k = &$k" "$d/bb-real.inc" || echo "static const void *$k = &$k;"
  done > "$d/bb-keys.inc"
  awk 'index($0, "    {   // (the text on a bar of this colour") == 1 { f = 1 } f { print } f && /^    [}]$/ { exit }' "$X" > "$d/bb-prefs.inc"
  awk 'index($0, "static void DMBarForegroundInit(void) {") == 1 { f = 1; next } f && /^[}]/ { exit } f { print }' "$X" | sed 's/%init(BarForeground, _UIStatusBar = bar);/\/* %init *\//' > "$d/bb-init.inc"
  awk 'index($0, "- (void)setTextColor:(UIColor *)color {") == 1 { f = 1; next } f && /^[}]/ { exit } f { print }' "$X" | sed 's/^    %orig;$/    TSuperSetTextColor(self, color);/' > "$d/bb-hook.inc"
  grep -q 'TSuperSetTextColor(self, color);' "$d/bb-hook.inc" && grep -q 'DMApplyBarItemColor(fg, DMBarItemColor(fg, me), YES);' "$d/bb-hook.inc" || { echo "FAIL  the time label's restyle hook was not found in $X"; return 99; }
  # 1.8.7.6 (the 17.5's crash at a Notification Center pull): the time label's -tintColorDidChange hook; the bar's own constraint pass counted
  # (-updateConstraints' hook in BarForeground, its %orig the stand-in bar's own pass: the code before the fix has none, the pass alone); the
  # closed-up copy's way back (DMClosedUpClockBack, DMClockBackLayout, with BarUnlock.h's rule)
  awk 'index($0, "- (void)tintColorDidChange {") == 1 { f = 1; next } f && /^[}]/ { exit } f { print }' "$X" | sed 's/^    %orig;$/    TSuperTintColorDidChange(self);/' > "$d/bb-tint.inc"
  grep -q 'TSuperTintColorDidChange(self);' "$d/bb-tint.inc" && grep -q 'DMApplyBarItemColor(fg, DMBarItemColor(fg, me), YES);' "$d/bb-tint.inc" || { echo "FAIL  the time label's tint hook was not found in $X"; return 99; }
  awk '/^%group BarForeground$/ { g = 1 } g && !f && /^%end$/ && ++e == 2 { exit } g && index($0, "- (void)updateConstraints {") == 1 { f = 1; next } f && /^[}]/ { exit } f { print }' "$X" \
    | sed 's/^\( *\)%orig;$/\1TBarOwnPass(self);/' > "$d/bb-uc.inc"
  if [ -s "$d/bb-uc.inc" ]; then grep -q '^ *TBarOwnPass(self);$' "$d/bb-uc.inc" || { echo "FAIL  the bar's constraint pass hook is not as the test plays it in $X"; return 99; }
  else echo '    TBarOwnPass(self);   /* (the code before the fix: no hook of the pass) */' > "$d/bb-uc.inc"; fi
  { grep -F 'static BOOL DMBarLayingOut(UIView *fg) {' "$X"; fn "$X" 'static void DMClosedUpClockBack(UIView *fg) {'; fn "$X" 'static void DMClockBackLayout(UIView *fg) {'; } > "$d/bb-closedup.inc"
  grep -q 'MSBDClosedUpBarLaidOutAgain' "$d/bb-closedup.inc" && grep -q 'DMBarLayoutAgainBeforeDraw(fg);' "$d/bb-closedup.inc" || { echo "FAIL  the closed-up copy's way back was not found in $X"; return 99; }
  cp "$(dirname "$X")/BarUnlock.h" "$d/BarUnlock.h" 2>/dev/null || cp ../statusbar/BarUnlock.h "$d/BarUnlock.h"
  grep -oE '\bk[A-Z][A-Za-z0-9]*Key\b' "$d/bb-closedup.inc" | sort -u | while read -r k; do
    grep -qF "static const void *$k = &$k" "$d/bb-real.inc" "$d/bb-keys.inc" || echo "static const void *$k = &$k;"
  done >> "$d/bb-keys.inc"
  {   # the code before the fix: what it does not have, as it was (no dark text: the bar takes what it is asked for)
    grep -q 'gBgTextDark' "$d/bb-globals.inc" || echo 'static BOOL gBgColorLight = NO, gBgTextDark = NO;'
    grep -q 'static UIColor \*DMBarForegroundFor(' "$d/bb-real.inc" || echo 'static UIColor *DMBarForegroundFor(UIView *bar, UIColor *asked) { return asked; }'
    grep -q 'static BOOL DMBarDarkTextOn(UIView \*fg) {' "$d/bb-real.inc" || echo 'static BOOL DMBarDarkTextOn(UIView *fg) { return NO; }'
    grep -q '^static BOOL gBarFgHooked = NO;' "$d/bb-real.inc" || echo 'static BOOL gBarFgHooked = NO;'
    grep -q '^static int gDMBarConstraintDepth = 0;' "$d/bb-real.inc" || echo 'static int gDMBarConstraintDepth = 0;   /* (before the 1.8.7.6 fix: the pass not counted) */'
  } > "$d/bb-compat.inc"
  [ -s "$d/bb-compat.inc" ] && [ -z "$q" ] && echo "   (the code before the fix: $(wc -l < "$d/bb-compat.inc" | tr -d ' ') part(s) as before)"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Werror=implicit-function-declaration -I"$d" \
        -framework UIKit -framework QuartzCore -framework CoreGraphics -o "$d/t" test-barbackground.m 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the real code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}

sites() {   # $1 StatusBar.x, $2 Root.plist, $3 quiet: the number of site checks that fail
  local X=$1 P=$2 q=$3 n=0 o
  # the hook: every write of SpringBoard's bar's foreground colour goes through DMBarForegroundFor (the stand-in bar's setter is this call)
  if awk '/^%group BarForeground$/ {g = 1} g && /^%hook _UIStatusBar$/ {h = 1} h && index($0, "- (void)setForegroundColor:(UIColor *)color {") == 1 {m = NR}
          m && NR == m + 1 && $0 == "    %orig(DMBarForegroundFor((UIView *)self, color));" {ok = 1} m && NR == m + 2 && $0 == "}" {ok2 = 1} END {exit !(ok && ok2)}' "$X" \
     && fn "$X" 'static void DMBarForegroundInit(void) {' | grep -qF 'Class bar = DMSBClass("_UIStatusBar");' \
     && fn "$X" 'static void DMBarForegroundInit(void) {' | grep -qF '%init(BarForeground, _UIStatusBar = bar);'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: -setForegroundColor: of SpringBoard's bar class (DMSBClass: 15/16 UIKit's, 17/18 SystemStatusUI's) passes DMBarForegroundFor's colour on, nothing else"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the foreground colour hook is not as the test plays it"; n=$((n + 1)); fi
  # installed with the bar's hooks, after the Stock style's return (never with Status Bar Style Stock)
  if awk 'index($0, "    if (gStockBar) {") == 1 && index($0, "return; }") {s = NR} index($0, "    if (!DMCtorSkip(\"barfg\")) DMBarForegroundInit();") == 1 {b = NR} END {exit !(s && b > s)}' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: the hook goes on after the Stock style's return (not with Status Bar Style Stock)"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the hook's install is not after the Stock style's return"; n=$((n + 1)); fi
  # DMApplyBarItemColor: the dark text last (its restyle comes back through the time label's hook with the bar's new colour), from the background
  o=$(fn "$X" 'static void DMApplyBarItemColor(UIView *fg, UIColor *c, BOOL background) {' | tail -2 | head -1)
  if [ "$o" = '    DMBarDarkText(fg, shown && dark);   // (last: a change restyles the bar, whose time label brings it back here in its new colour)' ]; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMApplyBarItemColor sets the bar's text last, only with our background shown"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: DMApplyBarItemColor's last step is not the bar's text ($o)"; n=$((n + 1)); fi
  # what the menu bar is over, asked every tick: DMNativeTick calls DMWPBarBackdropTick right after DMWPTick (whichever way that ended), nothing else
  if [ "$(grep -c 'DMWPBarBackdropTick();' "$X")" = 1 ] && fn "$X" 'static void DMNativeTick(void) {' | grep -A1 -F '    DMWPTick();' | grep -qF '    DMWPBarBackdropTick();' \
     && ! fn "${TWP:-$WP0}" 'static void DMWPTick(void) {' | grep -qF 'DMWPBarBackdropTick'; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: DMNativeTick asks what the menu bar is over every tick, right after DMWPTick"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: what the menu bar is over is not asked every tick from DMNativeTick"; n=$((n + 1)); fi
  # the footer says what the colour does
  if python3 -I -c 'import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
f = [i.get("footerText") for i in d["items"] if i.get("label") == "Status Bar Background"]
sys.exit(0 if f == [sys.argv[2]] else 1)' "$P" "$FOOTER"; then
    [ -n "$q" ] || echo "PASS  Root.plist: the Status Bar Background footer says what the colour does now"
  else [ -n "$q" ] || echo "FAIL  Root.plist: the Status Bar Background footer is not the new text"; n=$((n + 1)); fi
  # the crash map: the new code is the bar's (a crash in it turns Status Bar Style to Stock, as for the rest of the bar's code)
  o=$(python3 -I - crashmap-rules.txt <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'bb'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
for name in ['_DMBarDarkText', '_DMBarForegroundFor', '_DMBarColorText', '_DMBarForegroundInit', '___DMBarDarkText_block_invoke', '_DMApplyBackground', '__logos_method$BarForeground$_UIStatusBar$setForegroundColor$', '_DMBarTextDarkFor', '_DMBarDarkTextOn', '_DMBarWindowTextOn', '_DMBarWindowTextUnder', '_DMBarWindowText']:
    print(g['classify']('MacStatusBarCore', name, 'StatusBar.x', '', rules, im, hits), end=' ')
EOF
)
  if [ "$o" = "stock stock stock stock stock stock stock stock stock stock stock stock " ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the new code is the bar's (Status Bar Style; classified with make-crashmap.py's own code)"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the new code classifies as: $o"; n=$((n + 1)); fi
  # 1.8.7.6: the deferral's code is the bar's too, each name in its own section of StatusBar.x (make-crashmap.py's section_of); the count's hook only
  # passes the call on: transparent, as the other pass-through hooks (a crash in Apple's code under it is decided by the frame below)
  o=$(python3 -I "$W/bb-crashsec.py" crashmap-rules.txt "$X")
  if [ "$o" = "stock stock transparent stock stock " ]; then
    [ -n "$q" ] || echo "PASS  crashmap-rules.txt: the deferral and the closed-up copy's layout are the bar's (Status Bar Style), in their sections; the pass's count (a pass-through hook) is transparent"
  else [ -n "$q" ] || echo "FAIL  crashmap-rules.txt: the constraint pass's code classifies as: $o"; n=$((n + 1)); fi
  # the hook of the pass goes on with the foreground colour's, after its type check (v16@0:8): without it, no dark text (nothookeduc)
  if fn "$X" 'static void DMBarForegroundInit(void) {' | grep -qF '    Method uc = bar ? class_getInstanceMethod(bar, @selector(updateConstraints)) : NULL;' \
     && fn "$X" 'static void DMBarForegroundInit(void) {' | grep -qF ' && !strcmp(ue, "v16@0:8")) {' \
     && awk '/^%group BarForeground$/ { g = 1 } g && /^%end$/ && ++e == 2 { exit } g && index($0, "- (void)updateConstraints {") == 1 { ok = 1 } END { exit !ok }' "$X"; then
    [ -n "$q" ] || echo "PASS  StatusBar.x: -updateConstraints' hook is in BarForeground (one %init with -setForegroundColor:'s), after its type check v16@0:8"
  else [ -n "$q" ] || echo "FAIL  StatusBar.x: the constraint pass's hook is not in BarForeground or not type-checked"; n=$((n + 1)); fi
  # every write of a status bar's colour or style of ours, in every source of the tree (StatusBar.x: the one given), consults the bar's constraint
  # pass first: in its function, before the write, "if (gDMBarConstraintDepth > 0) { DMBarDecideNextTurn(fg, ...); return ...; }"
  o=$(python3 -I "$W/bb-writers.py" "$X" ..)
  if [ "$o" = "StatusBar.x DMBarWindowText, StatusBar.x DMBarDarkText | " ]; then
    [ -n "$q" ] || echo "PASS  every write of a status bar's colour of ours (2: DMBarWindowText, DMBarDarkText) consults the bar's constraint pass first"
  else [ -n "$q" ] || echo "FAIL  a write of a status bar's colour that does not consult the bar's constraint pass, or a writer this test does not know: $o"; n=$((n + 1)); fi
  return $n
}

run() {   # $1 StatusBar.x, $2 BarBackground.h, $3 Root.plist, $4 dir, $5 quiet: the number of checks that fail (99: not built)
  local q=$5 n=0 s out r
  build "$1" "$2" "$4" "$q"; r=$?; [ $r = 99 ] && return 99; n=$r
  for s in $("$4/t" list); do
    [ -n "$q" ] || echo "-- $s"
    out=$(perl -e 'alarm 120; exec @ARGV' "$4/t" "$s" 2>/dev/null); r=$?   # (a scenario that hangs ends by signal 14 after 2 min)
    [ -n "$q" ] || echo "$out"
    [ $r -ge 128 ] && { [ -n "$q" ] || echo "FAIL  $s ended by signal $((r - 128))"; }
    n=$((n + $(echo "$out" | grep -c '^FAIL'))); [ $r != 0 ] && [ -z "$(echo "$out" | grep '^FAIL')" ] && n=$((n + 1))
  done
  [ -n "$q" ] || echo "-- site checks"
  sites "$1" "$3" "$q"; s=$?
  n=$((n + s)); [ $n -ge 99 ] && n=98
  return $n
}

run "$X0" "$H0" "$P0" "$W/real"; rc=$?
[ $rc = 0 ] && echo "test-barbackground: all pass" || echo "test-barbackground: FAILED ($rc check(s))"
if [ -z "$BB_SB_X$BB_HDR$BB_PLIST$BB_WP_H$BB_CCP_H$BB_CC18_H" ]; then
  echo "-- made-to-fail copies (each must fail)"
  k=0
  mtf() {   # $1 what, $2 which file (x: StatusBar.x, h: BarBackground.h, p: Root.plist, w: DesktopWallpaper.h, c: CCPanel.h, e: CC18Shape.h), $3 perl expression on it (the whole file at once)
    local d="$W/m$((++k))" c x=$X0 h=$H0 p=$P0 src
    mkdir -p "$d"; TWP=; TCCP=; TC18=
    case $2 in x) src=$X0; c="$d/StatusBar.x"; x=$c;; h) src=$H0; c="$d/BarBackground.h"; h=$c;; p) src=$P0; c="$d/Root.plist"; p=$c;; w) src=$WP0; c="$d/DesktopWallpaper.h"; TWP=$c;;
               c) src=$CCP0; c="$d/CCPanel.h"; TCCP=$c;; e) src=$C180; c="$d/CC18Shape.h"; TC18=$c;; esac
    perl -0777 -pe "$3" "$src" > "$c"
    cmp -s "$c" "$src" && { echo "FAIL  made-to-fail copy \"$1\": nothing changed"; rc=1; return; }
    run "$x" "$h" "$p" "$d/w" q; local n=$?; TWP=; TCCP=; TC18=
    if [ $n -gt 0 ] && [ $n -lt 99 ]; then echo "PASS  caught: $1 ($n check(s) fail)"; else echo "FAIL  not caught: $1 ($n)"; rc=1; fi
  }
  mtf "a light colour's background follows iPadOS's text again (the light grey under dark text)" x 's/MSBDBarBackgroundChosen\(gBgColorLight, lightText\) \?/lightText ?/'
  mtf "no dark text (the bar keeps iPadOS's)" x 's/    DMBarDarkText\(fg, shown && dark\);/    DMBarDarkText(fg, NO);/'
  mtf "dark text without our background (Off, ColorBar15)" x 's/    DMBarDarkText\(fg, shown && dark\);/    DMBarDarkText(fg, dark || DMBarTextDarkFor(fg, under));/'
  mtf "one guess for every place again (black over a dark app at 0.36)" x 's/    return gBgTextDark;\n\}/    return 1;\n}/'
  mtf "our Desktop Picture not looked at (iPadOS's text over KT's sky)" x 's/    if \(DMWPBarBackdrop\(fg, &top\)\) return MSBDBarTextDarkOver/    if (0) return MSBDBarTextDarkOver/'
  mtf "the override not ended first (the background from our black: a fade)" x 's/    if \(!dark && DMBarDarkTextOn\(fg\)\) \{/    if (0) {/'
  mtf "our black kept as iPadOS's text (its end faded as a flip)" x 's/BOOL ours = DMBarDarkTextOn\(fg\);/BOOL ours = NO;/'
  mtf "a collapsed copy keeps the dark text" x 's/        DMBarDarkText\(fg, NO\);   \/\/ \(and our dark text with our background[^\n]*\n//'
  mtf "a collapsed copy given our background again by a restyle" x 's/ \|\| fg.bounds.size.width < 300.0\) \{ bg.hidden = YES; return NO; \}/) { bg.hidden = YES; return NO; }/'
  mtf "the Lock Screen's layout leaves black text with no background of ours" x 's/    DMBarDarkText\(fg, shown && dark\);/    if (background) DMBarDarkText(fg, shown \&\& dark);/'
  mtf "the Lock Screen's layout keeps black text after Background Off" x 's/    BOOL dark = DMBackgroundWanted\(\) && \(/    BOOL dark = (/'
  mtf "the hook passes iPadOS's colour on (ours never reaches the bar)" x 's/    if \(\[objc_getAssociatedObject\(bar, kBarDarkTextKey\) boolValue\]\) return gBarDarkInk;\n//'
  mtf "iPadOS's own colour not kept (not back after ours)" x 's/    if \(asked != gBarDarkInk\) objc_setAssociatedObject\(bar, kBarTheirFgKey[^\n]*\n//'
  mtf "the state set after the bar's restyle (it comes back here first)" x 's/(    objc_setAssociatedObject\(bar, kBarDarkTextKey, dark \? \@YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC\);[^\n]*\n)(    \(\(void \(\*\)\(id, SEL, id\)\)objc_msgSend\)\(bar, \@selector\(setForegroundColor:\)[^\n]*\n)/$2$1/'
  mtf "no layout after the change (the battery's number keeps the old colour)" x 's/    \[fg setNeedsLayout\];   \/\/ \(our items and the battery[^\n]*\n//'
  mtf "the hook installed whatever the methods' types" x 's/if \(se && ge && ue && !strcmp\(se, "v24\@0:8\@16"\) && !strcmp\(ge, "\@16\@0:8"\) && !strcmp\(ue, "v16\@0:8"\)\) \{/if (1) {/'
  # 1.8.7.6: the bar's own constraint pass (the 17.5's crash at a Notification Center pull)
  mtf "DMBarDarkText writes inside the bar's own constraint pass (its check of the pass taken out)" x 's/    if \(gDMBarConstraintDepth > 0\) \{ DMBarDecideNextTurn\(fg, dark \?[^\n]*\n//'
  mtf "DMBarWindowText writes inside the bar's own constraint pass (its check of the pass taken out)" x 's/    if \(gDMBarConstraintDepth > 0\) \{ DMBarDecideNextTurn\(fg, ink \?[^\n]*\n//'
  mtf "the closed-up copy laid out inside the bar's own constraint pass (DMClockBackLayout's check taken out)" x 's/BOOL later = now && gDMBarConstraintDepth > 0;/BOOL later = NO;/'
  mtf "the bar's constraint pass not counted (its hook passes the call on only)" x 's/    gDMBarConstraintDepth\+\+;\n    \@try \{\n        %orig;\n    \} \@finally \{\n        gDMBarConstraintDepth--;\n    \}\n/    %orig;\n/'
  mtf "the count left raised by a pass that raises (no \@finally)" x 's/    \@try \{\n        %orig;\n    \} \@finally \{\n        gDMBarConstraintDepth--;\n    \}\n/    %orig;\n    gDMBarConstraintDepth--;\n/'
  mtf "the copy's own layout asks for itself again inside the pass (laid out again and again, without end)" x 's/    if \(!DMBarLayingOut\(fg\)\) \[fg setNeedsLayout\];/    [fg setNeedsLayout];/'
  mtf "more than one decision at the next turn for one copy" x 's/    if \(objc_getAssociatedObject\(fg, kBarDecideNextTurnKey\)\) return;   \/\/ \(one per copy\)\n//'
  mtf "no decision at the next turn (the old colour stays until something else lays the copy out)" x 's/        \[f setNeedsLayout\];\n        \[f layoutIfNeeded\];\n    \}\);\n\}\nstatic const void \*kBarWindowInkKey/    });\n}\nstatic const void *kBarWindowInkKey/'
  mtf "the state changed inside the pass (only the write waits)" x 's/(    if \(gDMBarConstraintDepth > 0\) \{ DMBarDecideNextTurn\(fg, dark \?[^\n]*\n)((?:[^\n]*\n){2})(    objc_setAssociatedObject\(bar, kBarDarkTextKey[^\n]*\n)/$3$1$2/'
  mtf "the constraint pass's hook installed whatever -updateConstraints' type" x 's/ && !strcmp\(ue, "v16\@0:8"\)//'
  mtf "the text dark only on an opaque bar (the opacity read wrongly)" h 's/a = MSBDBarOpacity\(a\);/a = MSBDBarOpacity(a) >= 0.99 ? 1 : 0;/'
  mtf "the opacity ignored (white at 0.2 turns the text black over a dark backdrop)" h 's/if \(a <= 0 \|\| !MSBDBarColorIsLight\(r, g, b\)\) return 0;/if (a <= 0 || !MSBDBarColorIsLight(r, g, b)) return 0; return 1;/'
  mtf "the picture's strip read from the whole picture" h 's/CGRectMake\(0, 0, w, rows < h \? rows : h\)/CGRectMake(0, 0, w, h)/'
  mtf "the darkest part of what is behind not counted" h 's/double overDark = MSBDBattInsideLuminance\(MSBDBarOver\(r, a, darkest\[0\]\), MSBDBarOver\(g, a, darkest\[1\]\), MSBDBarOver\(b, a, darkest\[2\]\)\);/double overDark = MSBDBattInsideLuminance(MSBDBarOver(r, a, lightest[0]), MSBDBarOver(g, a, lightest[1]), MSBDBarOver(b, a, lightest[2]));/'
  mtf "our picture taken as behind a full-screen app" w 's/    if \(!tv && \(DMSMEngine\(\) \? DMSMFrontIsFullScreen\(\) : DMFullScreenAppInFront\(\)\)\) return NO;\n//'
  mtf "our picture taken as behind Control Center, the Cover Sheet, the App Switcher" w 's/    if \(!tv && \(\(DMControlCenterActive\(\) && !DMCCPanelLeavesDesktop\(\)\) \|\| DMCoverSheetShown\(\) \|\| DMSwitcherVisible\(\)\)\) return NO;\n//'
  mtf "our Mac panel taken as covering the desktop, as before CCMAC (iPadOS's white on KT's light bar)" w 's/\(DMControlCenterActive\(\) && !DMCCPanelLeavesDesktop\(\)\)/DMControlCenterActive()/'
  mtf "a module opened expanded in our panel not counted (15-17: our backdrop of Control Center's material)" c 's/\(DMCCPanelOwnsCCBars\(\) && !gCCPExpanded\)/DMCCPanelOwnsCCBars()/'
  mtf "our panel counted before it is in Control Center's overlay (15-17)" c 's/static BOOL DMCCPanelLeavesDesktop\(void\) \{ return \(DMCCPanelOwnsCCBars\(\)/static BOOL DMCCPanelLeavesDesktop(void) { return (gCCPOn/'
  mtf "18's panel left out" c 's/ \|\| DMCC18LeavesDesktop\(\); \}/; }/'
  mtf "18: a module opened expanded not counted (Apple's backdrop behind it)" e 's/return DMCC18OwnsCCBars\(\) && !gCC18Expanded;/return DMCC18OwnsCCBars();/'
  mtf "18: edit mode taken for the panel (Apple's whole look)" e 's/static BOOL DMCC18LeavesDesktop\(void\) \{ return DMCC18OwnsCCBars\(\) && /static BOOL DMCC18LeavesDesktop(void) { return gCC18On \&\& /'
  mtf "our picture taken on page 2 (faded out)" w 's/ \|\| p\.alpha < 0\.5\) return NO;/) return NO;/'
  mtf "our picture taken with the wallpaper's window hidden" w 's/ \|\| p\.window\.hidden \|\| / || /'
  mtf "the bars not laid out when what is behind them changes" w 's/    if \(now == was && [^\n]*\) return;/    return;/'
  mtf "the bars not laid out for another picture of ours" w 's/ && \(!\(now & 1\) \|\| image == wasImage\)//'
  # 1.8.7.6 FULLBAR: the background inside its copy, the screen's own bar over a full-screen window taking that window's text
  mtf "the background in the bar beside its copy again (a layer more for each new contents view, and shown under a strip held hidden)" x 's/\[fg insertSubview:bg atIndex:0\];/[bar insertSubview:bg belowSubview:fg];/g'
  mtf "the screen's bar keeps iPadOS's text over a full-screen window (white on Settings' white)" x 's/    return objc_getAssociatedObject\(bar, kBarWindowInkKey\) \?: asked;/    return asked;/'
  mtf "the window's text never looked for" x 's/    if \(!scr \|\| !DMSBUseSTUI\(\) \|\| !DMSMEngine\(\)\) return nil;/    return nil;/'
  mtf "the window's text taken from a card that is not in full screen (Clock's window beside the desktop)" x 's/ \|\| !DMSMInFullScreenCard\(s\)\) continue;/) continue;/'
  mtf "the window's text taken under the App Switcher or our Mac Switcher" x 's/        if \(DMSMScreenInSwitcher\(scr\) \|\| DMSMCardGoesHome\(card\) \|\| \(gMSWOpen && DMMSWScreen\(\) == scr\)\n            \|\| /        if (/'
  mtf "the window's text only with our background (Background Off: white on Settings' white)" x 's/    BOOL again = DMBarWindowText\(fg, under, strip\);/    BOOL again = DMBarWindowText(fg, DMBackgroundWanted() ? under : nil, strip);/'
  mtf "the window's text ended only at the bar's next own layout (not right away)" x 's/    if \(was == ink \|\| \[was isEqual:ink\]\) return NO;/    if (!ink || was == ink || [was isEqual:ink]) return NO;/'
  mtf "our picture taken as behind the screen's bar over a full-screen window" x 's/    if \(under\) return gBgTextDark;[^\n]*\n//'
  mtf "no layout after the window's text is taken (the battery's number keeps the old colour)" x 's/    \[fg setNeedsLayout\];   \/\/ \(the battery.s number and our items[^\n]*\n//'
  mtf "the bars not laid out when the window behind the screen's bar changes" w 's/ && \(ink == wasInk \|\| \[ink isEqual:wasInk\]\)//'
  # 1.8.7.6 FULLBAR round 1 (the review): each display's own states, a card that shows, a strip held hidden without our black, a strip not built yet
  mtf "the iPad's Control Center and Cover Sheet asked for the TV's bar too" x 's/ \|\| \(iPad && \(\(DMControlCenterActive\(\)/ || (((DMControlCenterActive()/'
  mtf "any display's App Switcher taken for the bar's own (isAnySwitcherVisible)" x 's/        if \(DMSMScreenInSwitcher\(scr\) \|\| DMSMCardGoesHome\(card\)/        if (DMSwitcherVisible() || DMSMCardGoesHome(card)/'
  mtf "our Mac Switcher counted on every display" x 's/ \|\| \(gMSWOpen && DMMSWScreen\(\) == scr\)/ || gMSWOpen/'
  mtf "a full-size card that does not show taken as the window behind the bar" x 's/        if \(!shows\) continue;[^\n]*\n//'
  mtf "a card off its screen taken as showing" x 's/BOOL shows = card && CGRectIntersectsRect\(\[card convertRect:card.bounds toView:nil\], w.bounds\);/BOOL shows = card != nil;/'
  mtf "the window's text kept while its display goes Home" x 's/ \|\| DMSMCardGoesHome\(card\)//'
  mtf "a strip that stops being the top bar keeps our black" x 's/        DMBarDarkText\(fg, NO\);   \/\/ \(and our dark text with it[^\n]*\n//'
  mtf "a restyle of a strip held hidden brings our black back" x 's/ && !DMSMStripHidden\(fg\) && DMBarTextDarkFor\(fg, under\);/ \&\& DMBarTextDarkFor(fg, under);/'
  mtf "the status icons' colour, none showing, is the colour last on screen again" x 's/(\[pending addObjectsFromArray:v.subviews\];\n    \}\n)    return nil;/$1    return gStatusTextColor;/'
  mtf "the footer's old text" p 's/A light color turns the status bar text and icons dark[^<]*</The color is used while the status bar text is light.</'
fi
exit $rc
