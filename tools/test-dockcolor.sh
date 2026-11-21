#!/bin/bash
# Mac test of Dock Background (1.8.8.1 DOCKCOLOR, KT 15 Nov: "lets also add ability to color the dock"): common/DockColor.h -- the stored
# choice, the colour and the first time it is taken, and the marks rule (critique B2) over the Dock material measured on the M1 (15.6.1), the
# iPad 2 (16.7.7), the 17.5 (17.5.1) and the A12Z (18.5), checked against a reckoning of its own over every opacity (test-dockcolor.m "rule", from
# its table kTMaterial, one row per iPad; copies of that table made to fail check that a row the rule does not cover is caught). Then the Dock (Mac Catalyst): the real
# dock/DockColor.m and dock/DockStyle.m with the dividers' code cut out of dock/Dock.x, against stand-ins for SpringBoard's Dock, one scenario per
# run (test-dockcolor.m TScenario): our view inside Apple's material (B1), Frosted (P5), Glass Shelf (P8), Automatic as stock, back to Automatic,
# the marks on the dots and the dividers (B3), the light colorChanged path (B4), the first time, the TV's Dock; a release and a debug build. Then the
# wiring in Dock.x, DockStyle.m and the Makefile. Then copies made to fail: each must fail. Settings: the rows' text, then (review of DOCKCOLOR) the
# page's code run, test-dockcolorpage.m (Mac Catalyst): the colour well, the Background row and the slider storing, switching and telling the Dock,
# and choosing Color noted for the crash guard's step 1, whose real code then sets it back to Automatic.
# Another copy to test: MSBD_TEST_DOCKCOLOR_H (common/DockColor.h), MSBD_TEST_DOCKCOLOR_M (dock/DockColor.m), MSBD_TEST_DOCKSTYLE_M (dock/DockStyle.m),
# MSBD_TEST_DOCK_X (dock/Dock.x), MSBD_TEST_DOCK_PAGE (the Dock page's DMRootListController.m), MSBD_TEST_DOCK_PLIST (its Root.plist): e.g. the code before.
cd "$(dirname "$0")" || exit 1
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
# (the scratch preference domains are this script's own, removed at the end, also after a failure: test-prefsforget.sh's way)
PD=com.besiktasliseba.msbdtest.dockcolor.$$; PB=com.besiktasliseba.msbdtest.dockcolorbar.$$
PG=com.besiktasliseba.msbdtest.dockcolorpage.$$; PGB=com.besiktasliseba.msbdtest.dockcolorpagebar.$$   # (the page's test: test-dockcolorpage.m)
cleanpf() { for d in "$PD" "$PB" "$PG" "$PGB"; do defaults delete "$d" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$d.plist"; done; }
W=$(mktemp -d); trap 'rm -rf "$W"; cleanpf' EXIT
H0=${MSBD_TEST_DOCKCOLOR_H:-../common/DockColor.h}; C0=${MSBD_TEST_DOCKCOLOR_M:-../dock/DockColor.m}; S0=${MSBD_TEST_DOCKSTYLE_M:-../dock/DockStyle.m}; X0=${MSBD_TEST_DOCK_X:-../dock/Dock.x}
fails=0
fn() { awk -v h="$2" '!p && index($0, h) == 1 && /\{ *(\/\/.*)?$/ {p=1} p {print} p && /^}/ {exit}' "$1"; }   # one function, by its first line

build() {   # $1 DockColor.h, $2 dir, $3 quiet, $4 the test's source (test-dockcolor.m): the rule's binary in $2/t
  local h=$1 d=$2 q=$3 m=${4:-test-dockcolor.m}
  mkdir -p "$d/inc"
  [ -f "$h" ] || { echo "FAIL  no common/DockColor.h ($h): the code before"; return 99; }
  cp "$h" "$d/inc/DockColor.h"; cp ../common/BarBackground.h ../common/BatteryInside.h "$d/inc/"
  clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -I"$d/inc" -framework Foundation -framework CoreGraphics \
        -o "$d/t" "$m" 2> "$d/cc.txt" || { [ -n "$q" ] || cat "$d/cc.txt"; echo "FAIL  the rule did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}
builddock() {   # $1 DockColor.h, $2 DockColor.m, $3 DockStyle.m, $4 Dock.x, $5 dir, $6 debug (1/0), $7 quiet: the Dock's binary in $5/td
  local h=$1 c=$2 s=$3 x=$4 d=$5 dbg=$6 q=$7
  mkdir -p "$d/dock" "$d/common"
  for f in "$h" "$c" "$s" "$x"; do [ -f "$f" ] || { [ -n "$q" ] || echo "FAIL  no $f: the code before"; return 99; }; done
  cp ../common/*.h "$d/common/"; cp "$h" "$d/common/DockColor.h"; cp ../dock/DMLog.h "$d/dock/"; cp "$c" "$d/dock/DockColor.m"; cp "$s" "$d/dock/DockStyle.m"
  {   # the dividers' code of Dock.x, as it is there (its statics given here as Dock.x has them)
    printf '#import <UIKit/UIKit.h>\n#import <objc/runtime.h>\n#import "DMLog.h"\nCGRect gDivider2Rect; BOOL gDivider2Alone; static BOOL gShowDownloads = YES;\n'
    printf 'static BOOL DMDockShowsTrash(UIView *dockView) { return YES; }\nstatic const void *kDivider2Key = &kDivider2Key;\n'
    printf 'extern BOOL DMDockColorSecondLook(UIView *dockView, UIView *mine, BOOL shown);\n'
    fn "$x" 'static UIView *DMNativeDivider(UIView *dockView) {'
    fn "$x" 'static void DMCopyDividerLook(UIView *from, UIView *to) {'
    fn "$x" 'static void DMSecondDividerLookOf(UIView *dockView, UIView *native, UIView *mine) {'
    grep -F 'UIView *DMDockNativeDivider(UIView *dockView) {' "$x"; grep -F 'UIView *DMDockSecondDivider(UIView *dockView) {' "$x"
    fn "$x" 'void DMDockSecondDividerLook(UIView *dockView) {'
    fn "$x" 'static void DMSecondDividerAttach(UIView *dockView) {' | sed 's/^static void DMSecondDividerAttach/void DMSecondDividerAttach/'
  } > "$d/dock/dockx-cut.m"
  grep -q 'void DMSecondDividerAttach(UIView \*dockView) {' "$d/dock/dockx-cut.m" && grep -q 'DMCopyDividerLook(UIView \*from' "$d/dock/dockx-cut.m" || { echo "FAIL  the dividers' code was not found in $x"; return 99; }
  local D="-DNDEBUG"; [ "$dbg" = 1 ] && D="-DDEBUG=1"
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -Wno-objc-bool-constant-conversion -Werror=implicit-function-declaration $D -DTDC_DOCK=1 \
        -DTDC_DOMAIN="\"$PD\"" -DTDC_BAR_DOMAIN="\"$PB\"" -DMSBD_DOCK_COLOR_DOMAIN="\"$PD\"" -DMSBD_DOCK_COLOR_BAR_DOMAIN="\"$PB\"" \
        -I"$d/common" -I"$d/dock" -framework UIKit -framework QuartzCore -framework CoreGraphics \
        -o "$d/td" test-dockcolor.m "$d/dock/DockColor.m" "$d/dock/DockStyle.m" "$d/dock/dockx-cut.m" 2> "$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; [ -n "$q" ] || echo "FAIL  the Dock's code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}
rundock() {   # $1 binary, $2 quiet: every scenario, each in its own run; the number that fail
  local b=$1 q=$2 n=0 s
  for s in $("$b" list); do
    if [ -n "$q" ]; then "$b" "$s" > /dev/null 2>&1 || n=$((n + 1)); else "$b" "$s" || n=$((n + 1)); fi
  done
  return $n
}

echo "== the rule (common/DockColor.h)"
if build "$H0" "$W/real"; then "$W/real/t" rule || fails=1; else fails=1; fi
for v in release debug; do
  echo "== the Dock ($v build: the real DockColor.m and DockStyle.m, Dock.x's dividers' code)"
  dbg=0; [ $v = debug ] && dbg=1
  if builddock "$H0" "$C0" "$S0" "$X0" "$W/dock-$v" $dbg; then
    [ "$("$W/dock-$v/td" list | wc -l | tr -d ' ')" -ge 11 ] || { echo "FAIL  scenarios missing"; fails=1; }
    rundock "$W/dock-$v/td" || { echo "FAIL  $? scenario(s) failed ($v)"; fails=1; }
  else fails=1; fi
done

echo "== copies of the header made to fail (each must fail)"
mut() {   # $1 name, $2 perl substitution on DockColor.h
  local d="$W/m-$1"; mkdir -p "$d"
  perl -0pe "$2" "$H0" > "$d/DockColor.h"
  if cmp -s "$H0" "$d/DockColor.h"; then echo "FAIL  made to fail ($1): the change did not apply"; fails=1; return; fi
  if build "$d/DockColor.h" "$d/b" q && "$d/b/t" rule > "$d/out.txt" 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; fails=1
  else echo "PASS  made to fail ($1): caught ($(grep -c '^FAIL' "$d/out.txt" 2>/dev/null || echo 0) check(s) fail)"; fi
}
if [ -f "$H0" ]; then
  mut lightgate 's/    a = MSBDBarOpacity\(a\);\n    MSBDDockUnder u/    a = MSBDBarOpacity(a);\n    if (!MSBDBarColorIsLight(r, g, b)) return 0;\n    MSBDDockUnder u/'
  mut modebound 's/else \{ u\.darkest = darkMode \? 37 : 58; u\.lightest = darkMode \? 210 : 246; \}/else { u.darkest = darkMode ? 37 : 200; u.lightest = darkMode ? 60 : 246; }/'
  mut nofrosted 's/if \(under == MSBDDockUnderFrosted\) \{[^}]*\}\n    else \{/{/'
  mut oneend 's/return MSBDBattInsideContrast\(overDark, 0\) >= MSBDBattInsideContrast\(overLight, 1\);/return MSBDBattInsideContrast(overDark, 0) >= MSBDBattInsideContrast(overDark, 1);/'
  mut inverted 's/return MSBDBattInsideContrast\(overDark, 0\) >= MSBDBattInsideContrast\(overLight, 1\);/return MSBDBattInsideContrast(overDark, 0) < MSBDBattInsideContrast(overLight, 1);/'
  mut alwaysours 's/return dark == !darkMode \? MSBDDockMarksApple : dark;/return dark;/'
  mut shownignored 's/    if \(!shown\) return MSBDDockMarksApple;\n//'
  mut nostart 's/    if \(MSBDDockColorParse\(dockHex, rgb\)\) return 1;\n    if \(!MSBDDockColorParse\(barHex, rgb\)\) /    if (MSBDDockColorParse(dockHex, rgb)) return 1;\n    if (1) /'
  mut opacity 's/return stored \? MSBDBarOpacity\(a\) : MSBD_DOCK_COLOR_OPACITY;/return stored ? a : MSBD_DOCK_COLOR_OPACITY;/'
  mut firstalways 's/    if \(MSBDDockColorStart\(dockHex, barHex, rgb\)\) return 0;\n    MSBDDockColorFormat/    MSBDDockColorStart(NULL, barHex, rgb);\n    MSBDDockColorFormat/'
fi
echo "== copies of the measured table made to fail on this rule (a row it does not cover, a row one range no longer serves, an iPadOS missing, a picture's material outside)"
tmut() {   # $1 name, $2 perl substitution on test-dockcolor.m's kTMaterial: it must still build, and some check must fail on the real header
  local d="$W/t-$1"; mkdir -p "$d"
  perl -0pe "$2" test-dockcolor.m > "$d/test-dockcolor.m"
  if cmp -s test-dockcolor.m "$d/test-dockcolor.m"; then echo "FAIL  table made to fail ($1): the change did not apply"; fails=1; return; fi
  if ! build "$H0" "$d/b" q "$d/test-dockcolor.m"; then echo "FAIL  table made to fail ($1): it did not build"; fails=1
  elif "$d/b/t" rule > "$d/out.txt" 2>&1; then echo "FAIL  table made to fail ($1): the test still passes"; fails=1
  else echo "PASS  table made to fail ($1): caught ($(grep -c '^FAIL' "$d/out.txt") check(s) fail)"; fi
}
if [ -f "$H0" ]; then
  tmut darker15 's/(\{ "15\.6\.1", "the M1, Reduce Transparency off", 0, \{ )58,/${1}50,/'
  tmut lighter17 's/(\{ "17\.5\.1", "the 17\.5, Reduce Transparency on", 0, \{ 59, 246 \}, \{ 37, )210/${1}220/'
  tmut frostedwider 's/(\{ "18\.5", "the A12Z", 1, \{ 142, 245 \}, \{ 31, )126/${1}140/'
  tmut own17 's/(\{ "17\.5\.1", "the 17\.5, Reduce Transparency on", 0, \{ )59,/${1}90,/'
  tmut no17 's/    \{ "17\.5\.1", "the 17\.5, Reduce Transparency on"[^\n]*\n//'
  tmut picturedarker 's/(\{ "15\.6\.1", "the M1", 1, \{ )27, 40, 36/${1}12, 24, 20/'
  tmut pictureshade 's/(\{ "15\.6\.1", "the M1", 1, \{ )27, 40, 36/${1}0, 50, 0/'
fi
echo "== copies of the Dock's code made to fail (each must fail; the release build)"
dmut() {   # $1 name, $2 which (c DockColor.m, s DockStyle.m, x Dock.x), $3 perl substitution
  local d="$W/dm-$1" src; mkdir -p "$d"
  case $2 in c) src=$C0;; s) src=$S0;; x) src=$X0;; esac
  perl -0pe "$3" "$src" > "$d/src"
  if cmp -s "$src" "$d/src"; then echo "FAIL  made to fail ($1): the change did not apply"; fails=1; return; fi
  local c=$C0 s=$S0 x=$X0
  case $2 in c) c=$d/src;; s) s=$d/src;; x) x=$d/src;; esac
  if builddock "$H0" "$c" "$s" "$x" "$d/b" 0 q && rundock "$d/b/td" q; then echo "FAIL  made to fail ($1): the test still passes"; fails=1
  else echo "PASS  made to fail ($1): caught"; fi
}
if [ -f "$C0" ]; then
  dmut automaticdraws c 's/    if \(!gDCOn && !st\) return;[^\n]*\n//; s/int shown = !gDCOn \? 0 : look == MSBDDockLookDefault/int shown = look == MSBDDockLookDefault/'
  dmut sibling c 's/    if \(cv\.superview != bg\) \[bg addSubview:cv\];/    if (cv.superview != bg.superview) [bg.superview insertSubview:cv aboveSubview:bg];/'
  dmut nomask c 's/        native\.layer\.mask = ours;\n//'
  dmut maskkept c 's/        if \(ours && native\.layer\.mask == ours\) \{[^\n]*\n//'
  dmut bysetting c 's/return MSBDDockMarks\(shown != 0,/return MSBDDockMarks(gDCOn,/'
  dmut frostedasmaterial c 's/shown == 2 \? MSBDDockUnderFrosted : MSBDDockUnderMaterial/MSBDDockUnderMaterial/'
  dmut lightwalks c 's/NSArray<UIView \*> \*platters = gDCOn && !was \? DCAllPlatters\(\) : gDCSeen\.allObjects;/NSArray<UIView *> *platters = DCAllPlatters();/'
  dmut dotevery c 's/    if \(had && had\.intValue == marks\) return;\n//'
  dmut notrait c 's/    UIView \*platter = DCPlatterOf\(self\.superview\);\n    if \(platter\) DCMarksAgain\(platter\);\n//'
  dmut nobar c 's/            DCString\(CFSTR\(kMSBDBarColorKey\), DC_BAR_DOMAIN, bar, sizeof bar\);\n//'
  dmut secondkept c 's/    if \(change\) DMDockSecondDividerLook\(dockView\);[^\n]*\n//'
  dmut secondcopiedover x 's/    if \(DMDockColorSecondLook\(dockView, mine, gDivider2Alone \|\| native\.alpha >= 0\.01\)\) return;[^\n]*\n//'
  dmut secondweaker c 's/    if \(v\.alpha != \(shown \? 1\.0 : 0\.0\)\) v\.alpha = shown \? 1\.0 : 0\.0;\n//'
  dmut lookwrittenalways c 's/    if \(!\[v\.backgroundColor getWhite:&w alpha:&a\] \|\| fabs\(w - g\) > 1e-6 \|\| fabs\(a - al\) > 1e-6\) v\.backgroundColor/    v.backgroundColor/'
  dmut nocolorchange c 's/    if \(cv\.r == gDCRGB\[0\] && cv\.g == gDCRGB\[1\] && cv\.b == gDCRGB\[2\] && cv\.a == gDCAlpha && cv\.backgroundColor\) return;/    if (cv.backgroundColor) return;/'
  dmut tintkept s 's/    if \(sv && sv\.draw\.noTint != noTint\) \{ sv\.draw\.noTint = noTint; \[sv\.draw setNeedsDisplay\]; \}\n//'
  dmut frostedinmaterial s 's/    BOOL frosted = sv && sv\.superview == platter && sv\.look == MSBDDockLookFrosted;/    BOOL frosted = NO;/'
  dmut nocolorinwalk s 's/                DMDockColorApply\(v\);[^\n]*\n//'
  dmut nodotcolor s 's/    DMDockColorDot\(dot, platter, reset\);[^\n]*\n//'
  dmut secondnocopy x 's/    DMCopyDividerLook\(native, mine\);\n//'
fi

echo "== Settings > Dock > Dock Background (the page's rows and code, the crash guard's rule); then copies made to fail"
P0=${MSBD_TEST_DOCK_PLIST:-../dock/dockmagnificationprefs/Resources/Root.plist}; R0=${MSBD_TEST_DOCK_PAGE:-../dock/dockmagnificationprefs/DMRootListController.m}; K0=crashmap-rules.txt
settings() {   # $1 Root.plist, $2 DMRootListController.m, $3 crashmap-rules.txt, $4 quiet: the number of checks that fail
  local P=$1 R=$2 K=$3 q=$4 n=0
  sc() { if eval "$2"; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  sc "the Dock Background group right after Dock Style: Background (Automatic / Color, Automatic never written), Color (the colour well), the opacity slider (0 to 1, 0.7)" \
    "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; ids=[x.get('id') for x in it]; i=ids.index('DOCK_STYLE'); g,b,c,o=it[i+1:i+5]; D='com.besiktasliseba.dockmagnification'
ok = g.get('cell')=='PSGroupCell' and g.get('id')=='DOCK_BACKGROUND_GROUP' and g.get('label')=='Dock Background' \\
 and b.get('id')=='DOCK_BACKGROUND' and b.get('cell')=='PSLinkListCell' and b.get('key')=='dockBackground' and b.get('default')=='auto' and b.get('defaults')==D and b.get('label')=='Background' \\
 and b.get('validValues')==['auto','color'] and b.get('validTitles')==['Automatic','Color'] and b.get('PostNotification')==D+'/prefsChanged' and b.get('detail')=='PSListItemsController' \\
 and c.get('id')=='DOCK_BACKGROUND_COLOR' and c.get('cell')=='PSStaticTextCell' and c.get('cellClass')=='DMDockColorCell' and c.get('label')=='Color' and 'key' not in c \\
 and o.get('id')=='DOCK_BACKGROUND_OPACITY' and o.get('cell')=='PSSliderCell' and o.get('key')=='dockBackgroundOpacity' and o.get('defaults')==D and o.get('default')==0.7 and o.get('min')==0 and o.get('max')==1 \\
 and it[i+5].get('label')=='Magnification'
sys.exit(0 if ok else 1)\""
  sc "  ... the footer in plain words: what Color does, where the colour starts, the marks, Glass Shelf keeping its glass; no em dash" \
    "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; g=[x for x in it if x.get('id')=='DOCK_BACKGROUND_GROUP'][0]
sys.exit(0 if g.get('footerText')=='Color puts your color on the Dock, from see-through to solid. It starts as your Status Bar Background color. The dots under open apps and the dividers turn dark or light to stay readable. Glass Shelf keeps its own glass.' else 1)\" \
     && ! grep -q \$'\\xe2\\x80\\x94' $P"
  sc "B6/P9: the slider posts nothing itself and has no isContinuous (the page makes it live, SliderCells.h: a plist YES would be taken as its own setting); the page tells the Dock with the light note, at most every 0.15 s, the last value always told" \
    "python3 -I -c \"import plistlib,sys; it=plistlib.load(open('$P','rb'))['items']; o=[x for x in it if x.get('id')=='DOCK_BACKGROUND_OPACITY'][0]; sys.exit(0 if not any('isContinuous' in x for x in it) and 'PostNotification' not in o else 1)\" \
     && awk '/^- \\(void\\)setPreferenceValue:\\(id\\)value specifier:\\(PSSpecifier \\*\\)specifier \\{/,/^}/' $R | tr -d '\\n\\t' | grep -q 'if (\\[key isEqual:@kMSBDDockBackgroundOpacityKey\\]) {   // (the slider, while dragged: the light note, Color if it was Automatic)BOOL switched = DMDockColorChooseColor();DMDockColorPost();' \
     && fn $R 'static void DMDockColorPost(void) {' | tr -d '\\n\\t' | grep -q 'if (pending) return;pending = YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 \\* NSEC_PER_SEC)), dispatch_get_main_queue(), ^{pending = NO;CFPreferencesSynchronize(kDMDockDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);notify_post(kMSBDDockColorNote);'"
  sc "the colour well writes the Dock's own key in the Dock's domain (never Status Bar Background's), switches Automatic to Color, tells the Dock with the light note" \
    "grep -q '^#define kDMDockDomain CFSTR(\"com.besiktasliseba.dockmagnification\")' $R && fn $R '- (void)dm_colorChanged {' | grep -q 'CFPreferencesSetValue(CFSTR(kMSBDDockBackgroundColorKey), (__bridge CFStringRef)@(hex), kDMDockDomain,' \
     && fn $R '- (void)dm_colorChanged {' | tr -d '\\n\\t' | grep -q 'BOOL switched = DMDockColorChooseColor();DMDockColorPost();if (switched) DMDockBackgroundRowAgain(self.specifier.target);' \
     && ! grep -E 'CFPreferencesSet(App)?Value\\(CFSTR\\(kMSBDBarColorKey\\)|kMSBDBarColorDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost\\);' $R | grep -q Set && grep -q '_well.supportsAlpha = NO;' $R"
  sc "decision 3: the well shows the colour the Dock draws (its own, else Status Bar Background's); the first time Color is chosen (the row, the well, the slider) that colour is stored as the Dock's own" \
    "fn $R 'static UIColor *DMDockShownColor(void) {' | grep -q 'MSBDDockColorStart(DMDockPrefString(CFSTR(kMSBDDockBackgroundColorKey), kDMDockDomain).UTF8String, DMDockBarColor().UTF8String, rgb);' \
     && fn $R 'static void DMDockColorStoreFirst(void) {' | grep -q 'if (MSBDDockColorFirstStore(DMDockPrefString(CFSTR(kMSBDDockBackgroundColorKey), kDMDockDomain).UTF8String, DMDockBarColor().UTF8String, hex))' \
     && fn $R 'static BOOL DMDockColorChooseColor(void) {' | awk '/DMDockColorStoreFirst\\(\\);/{a=NR} /CFSTR\\(\"color\"\\)/{b=NR} END{exit !(a && b > a)}' \
     && awk '/^- \\(void\\)setPreferenceValue:\\(id\\)value specifier:\\(PSSpecifier \\*\\)specifier \\{/,/^}/' $R | awk '/\\t\\tif \\(on\\) DMDockColorStoreFirst\\(\\);/{a=NR} /\\[super setPreferenceValue:value specifier:specifier\\];/{b=NR} END{exit !(a && b > a)}'"
  sc "crash guard: a crash in Dock Background's code (DockColor.m) sets it back to Automatic (\"auto\" stored, as Settings stores it); Automatic or nothing stored counts as off" \
    "grep -q '^target dockBackground pref com.besiktasliseba.dockmagnification dockBackground 0 0 offtext=auto Dock Background|' $K && grep -q '^file DockMagnification ^DockColor\\\\.m\$ dockBackground\$' $K \
     && grep -q '^sym DockMagnification \\\\\$SBFloatingDockPlatterView\\\\\$layoutSubviews\$ transparent\$' $K"
  sc "  ... (1.8.8.1) the Dock's divider helpers DockColor.m calls are passed over (the frame that called them decides), DockColor.m's functions and the Dock's own as before (make-crashmap.py's own code)" \
    "[ \"\$(python3 -I - $K <<'PYEOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'dc'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['DockMagnification']['target']
print(' '.join(g['classify']('DockMagnification', n, f, '', rules, im, hits) for n, f in [('_DMNativeDivider', 'Dock.x'), ('_DMDockNativeDivider', 'Dock.x'), ('_DMDockSecondDivider', 'Dock.x'),
      ('_DMDockSecondDividerLook', 'Dock.x'), ('_DMSecondDividerLookOf', 'Dock.x'), ('_DMSecondDividerAttach', 'Dock.x'), ('_DMDockColorDividers', 'DockColor.m'), ('_DMDockColorNote', 'Dock.x')]))
PYEOF
)\" = 'transparent transparent transparent transparent transparent part dockBackground part' ]"
  return $n
}
settings "$P0" "$R0" "$K0" || fails=1
smut() {   # $1 name, $2 which (p plist, r page, k rules), $3 perl substitution
  local d="$W/sm-$1" src; mkdir -p "$d"
  case $2 in p) src=$P0;; r) src=$R0;; k) src=$K0;; esac
  perl -0pe "$3" "$src" > "$d/src"
  if cmp -s "$src" "$d/src"; then echo "FAIL  made to fail ($1): the change did not apply"; fails=1; return; fi
  local p=$P0 r=$R0 k=$K0
  case $2 in p) p=$d/src;; r) r=$d/src;; k) k=$d/src;; esac
  if settings "$p" "$r" "$k" q; then echo "FAIL  made to fail ($1): the checks still pass"; fails=1; else echo "PASS  made to fail ($1): caught"; fi
}
if [ -f "$R0" ] && grep -q DOCK_BACKGROUND "$P0"; then
  smut barkey r 's/CFPreferencesSetValue\(CFSTR\(kMSBDDockBackgroundColorKey\), \(__bridge CFStringRef\)@\(hex\), kDMDockDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost\);\n\tBOOL switched/CFPreferencesSetValue(CFSTR(kMSBDBarColorKey), (__bridge CFStringRef)@(hex), CFSTR(kMSBDBarColorDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);\n\tBOOL switched/'
  smut sliderposts p 's/(<string>DOCK_BACKGROUND_OPACITY<\/string>\n)/$1\t\t\t<key>PostNotification<\/key>\n\t\t\t<string>com.besiktasliseba.dockmagnification\/prefsChanged<\/string>\n/'
  smut plistcontinuous p 's/(<string>DOCK_BACKGROUND_OPACITY<\/string>\n)/$1\t\t\t<key>isContinuous<\/key>\n\t\t\t<true\/>\n/'
  smut unthrottled r 's/\tif \(pending\) return;\n\tpending = YES;\n//'
  smut nofirststore r 's/\t\tif \(on\) DMDockColorStoreFirst\(\);\n//'
  smut norule k 's/^file DockMagnification \^DockColor[^\n]*\n//m'
  smut nodividerpass k 's/^sym DockMagnification \^_\*\(DMNativeDivider[^\n]*\n//m'
  smut ruledefault k 's/dockBackground 0 0 offtext=auto /dockBackground 0 1 offtext=auto /'
  smut emdash p 's/Glass Shelf keeps its own glass\./Glass Shelf \xe2\x80\x94 keeps its own glass./'
fi

echo "== Settings > Dock > Dock Background: the page's code run (test-dockcolorpage.m), then copies made to fail"
# (review of DOCKCOLOR: the checks above read the page's text only, and a page that stored nothing passed them. The real Dock Background block, the
#  list controller's read and set and LineSwitch.h's MSBDNoteSwitch, cut out with scratch domains, on stand-ins for the Preferences framework; the
#  crash guard's real step 1 on a scratch list)
buildpage() {   # $1 DMRootListController.m, $2 dir, $3 quiet, $4 a folder whose SliderCells.h is taken first (a copy made to fail): the page's binary in $2/tp
  local r=$1 d=$2 q=$3 h=${4:-../common}
  mkdir -p "$d"
  awk '/^\/\/ ---- Dock Background \(1\.8\.8\.1 DOCKCOLOR\)/{p=1} /^@implementation DMRootListController \{/{p=0} p' "$r" | sed 's|CFSTR("com.besiktasliseba.dockmagnification")|CFSTR(TDP_DOMAIN)|g' > "$d/block.h"
  fn "$r" 'static BOOL DMStockRecentsOff(void) {' > "$d/recents.h"
  fn "$r" '- (id)readPreferenceValue:(PSSpecifier *)specifier {' > "$d/read.h"
  fn "$r" '- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {' > "$d/set.h"
  fn "$r" '- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {' > "$d/cell.h"   # (DOCKSLIDER: the slider rows)
  grep -q '@implementation DMDockColorCell' "$d/block.h" && [ -s "$d/read.h" ] && [ -s "$d/set.h" ] && [ -s "$d/cell.h" ] || { [ -n "$q" ] || echo "FAIL  the page's Dock Background code was not found in $r (the code before?)"; return 99; }
  ! grep -Eq 'com\.besiktasliseba\.(dockmagnification|macstatusbar)"' "$d/block.h" "$d/read.h" "$d/set.h" || { echo "FAIL  a real domain is left in the page's code as cut"; return 99; }
  python3 -I crashstep-pagescut.py ../common/LineSwitch.h ../statusbar/macstatusbarprefs/MSBRootListController.m "$d/ls.h" "$d/picker.h" || { echo "FAIL  LineSwitch.h's lines not found"; return 99; }
  perl -0pi -e 's/\tif \(MSBDGuardNoteEndsOnChange\(\)\) \{/\tif (0) {   \/\/ (test: the part that ends the guard note left out)/' "$d/ls.h"
  grep -q 'if (0) {   // (test: the part that ends the guard note left out)' "$d/ls.h" || { echo "FAIL  LineSwitch.h's note-ending part not found"; return 99; }
  clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" \
        -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration -iquote "$h" -iquote ../common -I../common \
        -DTDP_DOMAIN="\"$PG\"" -DTDP_BAR_DOMAIN="\"$PGB\"" -DMSBD_GUARD_RECENT="\"$d/recent.txt\"" -DMSBD_GUARD_RECORD="\"$d/record.txt\"" \
        -DTDP_LINESWITCH_CUT="\"$d/ls.h\"" -DTDP_BLOCK="\"$d/block.h\"" -DTDP_RECENTS="\"$d/recents.h\"" -DTDP_READ="\"$d/read.h\"" -DTDP_SET="\"$d/set.h\"" -DTDP_CELL="\"$d/cell.h\"" \
        -framework UIKit -framework CoreGraphics -o "$d/tp" test-dockcolorpage.m 2> "$d/cc.txt" \
    || { [ -n "$q" ] || cat "$d/cc.txt"; [ -n "$q" ] || echo "FAIL  the page's code did not build"; return 99; }
  [ -s "$d/cc.txt" ] && [ -z "$q" ] && { echo "FAIL  warnings:"; cat "$d/cc.txt"; return 1; }
  return 0
}
if buildpage "$R0" "$W/page"; then "$W/page/tp" "$P0" || fails=1; else fails=1; fi
pmut() {   # $1 name, $2 perl substitution on DMRootListController.m
  local d="$W/pm-$1"; mkdir -p "$d"
  perl -0pe "$2" "$R0" > "$d/src"
  if cmp -s "$R0" "$d/src"; then echo "FAIL  made to fail ($1): the change did not apply"; fails=1; return; fi
  if buildpage "$d/src" "$d/b" q && "$d/b/tp" "$P0" > /dev/null 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; fails=1; else echo "PASS  made to fail ($1): caught"; fi
}
if [ -f "$R0" ] && grep -q DOCK_BACKGROUND "$P0"; then
  # (the review's four, which the text checks let through)
  pmut nofirststored 's/(\t\tCFPreferencesSetValue\(CFSTR\(kMSBDDockBackgroundColorKey\), \(__bridge CFStringRef\)\@\(hex\), kDMDockDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost\);\n\}\nstatic BOOL DMDockColorChooseColor)/\t\tif (0)\n$1/'
  pmut nocolorchosen 's/(\tCFPreferencesSetValue\(CFSTR\(kMSBDDockBackgroundKey\), CFSTR\("color"\))/\tif (0)\n$1/'
  pmut norowagain 's/(static void DMDockBackgroundRowAgain\(id controller\) \{[^\n]*\n).*?\n(\})/$1$2/s'
  pmut nowellcolor 's/\t_well\.selectedColor = DMDockShownColor\(\);\n//'
  # (the crash guard's note)
  pmut nonote 's/(static void DMDockBackgroundNote\(BOOL was, BOOL on\) \{\n)[^\n]*\n/$1/'
  pmut nonotewell 's/\tDMDockBackgroundNote\(NO, YES\);\n//'
  pmut falseshown 's/\tif \(\[\[specifier propertyForKey:\@"key"\] isEqual:\@kMSBDDockBackgroundKey\]\)[^\n]*\n[^\n]*\n//'
  # (DOCKSLIDER: the slider rows)
  pmut notlive 's/\t\tMSBDSliderCellContinuous\(cell, [^\n]*\n//'
  pmut everylive 's/MSBDSliderCellContinuous\(cell, \[sp isKindOfClass[^\n]*\);/MSBDSliderCellContinuous(cell, YES);/'
  pmut nofit 's/\t\tMSBDFitValueLabels\(cell\);\n//'
  pmut nolatefit 's/\t\tdispatch_async\(dispatch_get_main_queue\(\), \^\{ MSBDFitValueLabels\(cell\); \}\);[^\n]*\n//'
  pmut notslidercells 's/containsString:\@"Slider"\]/containsString:\@"Switch"]/'
  hmut() {   # $1 name, $2 perl substitution on common/SliderCells.h
    local d="$W/hm-$1"; mkdir -p "$d"
    perl -0pe "$2" ../common/SliderCells.h > "$d/SliderCells.h"
    if cmp -s ../common/SliderCells.h "$d/SliderCells.h"; then echo "FAIL  made to fail ($1): the change did not apply"; fails=1; return; fi
    if buildpage "$R0" "$d/b" q "$d" && "$d/b/tp" "$P0" > /dev/null 2>&1; then echo "FAIL  made to fail ($1): the test still passes"; fails=1; else echo "PASS  made to fail ($1): caught"; fi
  }
  hmut norestore 's/\t\t\} else if \(own\) \{\n\t\t\ts\.continuous = own\.boolValue;/\t\t} else if (own) {\n/'
  hmut restoreno 's/s\.continuous = own\.boolValue;/s.continuous = NO;/'
  hmut noscale 's/l\.minimumScaleFactor = 0\.6;/l.minimumScaleFactor = 1.0;/'
  hmut toplevel 's/\[views addObjectsFromArray:v\.subviews\]; continue;/continue;/'
  # (review of 7fbb1318: the opacity row's isContinuous back in Root.plist, run by the page's code with a Settings that takes it)
  d="$W/pp-plistcontinuous"; mkdir -p "$d"
  perl -0pe 's/(<string>DOCK_BACKGROUND_OPACITY<\/string>\n)/$1\t\t\t<key>isContinuous<\/key>\n\t\t\t<true\/>\n/' "$P0" > "$d/Root.plist"
  if cmp -s "$P0" "$d/Root.plist"; then echo "FAIL  made to fail (page plistcontinuous): the change did not apply"; fails=1
  elif "$W/page/tp" "$d/Root.plist" > /dev/null 2>&1; then echo "FAIL  made to fail (page plistcontinuous): the test still passes"; fails=1; else echo "PASS  made to fail (page plistcontinuous): caught"; fi
fi

echo "== site checks"
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "BarBackground.h is used as it is (its blend and opacity), not copied or changed for the Dock" \
  "grep -q '#include \"BarBackground.h\"' $H0 && grep -q 'MSBDBarOver(r, a, u.darkest)' $H0 && ! grep -q 'DockColor\\|dockBackground' ../common/BarBackground.h"
check "the platter's layout hook: Dock Style's look, then Dock Background (the hook stays a pass-through: Apple's layout, then our two calls)" \
  "awk '/^%hook SBFloatingDockPlatterView/,/^%end/' $X0 | tr -d '\n' | grep -q -- '- (void)layoutSubviews {    %orig;    DMDockStyleApply((UIView \*)self);    DMDockColorApply((UIView \*)self);}'"
check "  ... the Dock view's layout: the second divider placed (its look given), then the dividers' marks; Apple's restyle the same" \
  "awk '/^%hook SBFloatingDockView\$/,/^%end/' $X0 | awk '/^- \\(void\\)layoutSubviews \\{/{f=1} f&&/    DMSecondDividerAttach\\(\\(UIView \\*\\)self\\);/{a=NR} f&&/    DMDockColorDividers\\(\\(UIView \\*\\)self\\);/{b=NR; exit} END{exit !(a && b == a + 1)}' \
   && awk '/^- \\(void\\)updateDividerVisualStyling \\{/,/^}/' $X0 | tr -d '\n' | grep -q '    %orig;    DMSecondDividerLookOf((UIView \*)self, DMNativeDivider((UIView \*)self), objc_getAssociatedObject(self, kDivider2Key));    DMDockColorDividers((UIView \*)self);'"
check "  ... the second divider has one writer: ours while our marks are on that Dock (asked first), else Apple's look copied; nothing else in Dock.x copies onto it" \
  "fn $X0 'static void DMSecondDividerLookOf(UIView *dockView, UIView *native, UIView *mine) {' | awk '/if \\(DMDockColorSecondLook\\(dockView, mine, gDivider2Alone \\|\\| native\\.alpha >= 0\\.01\\)\\) return;/{a=NR} /DMCopyDividerLook\\(native, mine\\);/{b=NR} END{exit !(a && b > a)}' \
   && [ \"\$(grep -c 'DMCopyDividerLook(native, mine)' $X0)\" = 1 ] && fn $X0 'static void DMSecondDividerAttach(UIView *dockView) {' | grep -q '    DMSecondDividerLookOf(dockView, native, mine);'"
check "DMLoadPrefs reads Dock Background with the Dock part's switch (Automatic with it off); a prefsChanged applies every platter (the Dock Style walk)" \
  "fn $X0 'static void DMLoadPrefs(' | grep -q '    DMDockColorLoad(tweakOn);' && awk '/^static void DMPrefsChanged\\(/,/^}/' $X0 | grep -q 'DMDockStyleRefreshAll();' \
   && fn $S0 'void DMDockStyleRefreshAll(' | tr -d '\n' | grep -q 'DMDockStyleApply(v);                DMDockColorApply(v);'"
check "B4: the light note colorChanged calls only DMDockColorChanged: no DMLoadPrefs, no relayout, no Dock Style walk" \
  "grep -q 'DMDockColorNote, CFSTR(kMSBDDockColorNote), NULL,' $X0 && grep -q '^static void DMDockColorNote(CFNotificationCenterRef c, void \*o, CFNotificationName n, const void \*obj, CFDictionaryRef info) { DMDockColorChanged(); }' $X0 \
   && ! sed 's|//.*||' $C0 | grep -Eq 'DMLoadPrefs|DMRelayoutDock|DMDockStyleRefreshAll|setNeedsLayout|layoutIfNeeded'"
check "P7: Automatic -- the platter's call returns before any read when nothing of ours was ever on it; the dots' and the dividers' calls read nothing before our colour was ever drawn" \
  "fn $C0 'void DMDockColorApply(UIView *platter) {' | awk '/if \\(!gDCOn && !st\\) return;/{a=NR} /DMDockStyleLookOn\\(|DCBackground\\(|traitCollection/{if(!b)b=NR} END{exit !(a && b && a < b)}' \
   && fn $C0 'void DMDockColorDividers(UIView *dockView) {' | awk 'NR==2 && /if \\(!gDCEver \\|\\| !dockView\\) return;/{a=1} /DMDockNativeDivider/{if(!b)b=NR} END{exit !(a && b > 3)}' \
   && fn $C0 'void DMDockColorDot(UIView *dot, UIView *platter, BOOL reset) {' | awk 'NR==2 && /if \\(!gDCEver \\|\\| !dot\\) return;/{a=1} END{exit !a}'"
check "B3: Apple's divider is never restyled (no colour, filter or styling call of ours on it: only our empty mask, given back)" \
  "! sed 's|//.*||' $C0 | grep -Eq 'native\\.(backgroundColor|alpha|hidden|transform|frame|layer\\.filters|layer\\.compositingFilter|layer\\.cornerRadius) *=|\\[native(\\.layer)? setValue|updateDividerVisualStyling' && fn $C0 'static void DCLineOver(UIView *native, int marks) {' | grep -q 'native.layer.mask = ours;'"
check "the running dots take the marks through Dock Style's one dot function, after today's dot is put back (the apps' and Finder's)" \
  "fn $S0 'void DMDockStyleDot(' | tr -d '\n' | grep -q 'BOOL reset = dot.layer.contents != nil;    if (dot.layer.contents) { dot.layer.contents = nil; dot.backgroundColor = \[UIColor labelColor\]; }   // (Default and Frosted: today.s dot)    extern void DMDockColorDot(UIView \*dot, UIView \*platter, BOOL reset);    DMDockColorDot(dot, platter, reset);'"
check "  ... DockStyle.m's two declarations, each with its own note" \
  "grep -q '^extern void DMRunningIndicatorResyncAll(void);   // (RunningIndicator.m: every app icon.s dot placed and drawn again)\$' $S0 && grep -q '^extern void DMDockColorApply(UIView \\*platter);   // (DockColor.m: Dock Background on this platter, or given back)\$' $S0"
check "the TV's Dock takes the iPad's colour (decision 4): no display of its own is asked (nothing of DisplayPrefs.h)" "! grep -Eq 'DMDisp|DisplayPrefs' $C0"
check "DockColor.m is built into the Dock part, with its release-build feature marker; the debug word in the Dock's debug poll" \
  "grep -q '^DockMagnification_FILES = .* DockStyle.m DockColor.m' ../dock/Makefile && fn $C0 'void DMDockColorApply(UIView *platter) {' | grep -q 'DM_FEATURE_MARK(\"dock-color\");' \
   && grep -q '} else if (!strncmp(word, \"dockcolor\", 9)) {' $X0 \
   && awk '/if \\(access\\(\"\\/tmp\\/dockmag-debug\", F_OK\\) == 0\\) dispatch_async/{f=1} f&&/DMDockColorDebug\\(word\\);/{ok=1} f&&/dispatch_resume\\(escapeTimer\\);/{exit} END{exit !ok}' $X0"
check "DOCKSLIDER: one slider rule for our pages (common/SliderCells.h), the Status Bar page's and the Dock page's: no copy of it left in either page" \
  "grep -qF '#import \"../../common/SliderCells.h\"' $R0 && grep -qF '#import \"../../common/SliderCells.h\"' ../statusbar/macstatusbarprefs/MSBRootListController.m \
   && grep -qF 'MSBDSliderCellContinuous(cell, live);' ../statusbar/macstatusbarprefs/MSBRootListController.m && grep -qF 'MSBDFitValueLabels(cell);' ../statusbar/macstatusbarprefs/MSBRootListController.m \
   && ! grep -Eq 'continuous = YES|static void MSBFitValueLabels' $R0 ../statusbar/macstatusbarprefs/MSBRootListController.m"
check "no em dash in the rule, the Dock's code, its test or its words" "! grep -q \$'\\xe2\\x80\\x94' $H0 $C0 test-dockcolor.m test-dockcolor.sh test-dockcolorpage.m ../common/SliderCells.h"
[ $fails = 0 ] && echo "test-dockcolor: all checks pass" || { echo "test-dockcolor: checks FAILED"; exit 1; }
