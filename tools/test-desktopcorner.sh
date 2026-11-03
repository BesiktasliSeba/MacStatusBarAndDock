#!/bin/bash
# Mac test of the desktop app icons' corners (common/DesktopAppCorner.h, test-desktopcorner.m; 1.7.9 item 4: Settings > Desktop > App Icon Corner
# Radius), then the wiring as built: the rows in Desktop.plist and the Settings search, Settings' reading and writing (moved = the user's own,
# Match Home Screen Icons = never set again), SpringBoard's corner, the Home Screen's shape it reads and publishes, and what it never touches.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -fobjc-arc -O2 -Wall -framework Foundation -framework CoreGraphics -o "$W/tdc" test-desktopcorner.m
"$W/tdc"
# (the header is plain C for every includer: compiled alone, without Foundation's macros)
printf '#include "../common/DesktopAppCorner.h"\nint main(void) { return MSBDPaintedTileFind(0, 0, 0).found + (int)MSBDTileWindow(0.2, 0.1); }\n' > "$W/plain.c"
clang -O2 -Wall -Werror -Wno-unused-function -I. -framework CoreGraphics -o "$W/plain" "$W/plain.c" && echo "PASS  common/DesktopAppCorner.h compiles as plain C (no Foundation)" || { echo "FAIL  common/DesktopAppCorner.h needs Foundation"; exit 1; }
D=../statusbar/Desktop.h; C=../statusbar/DesktopCorner.h; F=../statusbar/Finder.h; X=../statusbar/StatusBar.x
R=../statusbar/macstatusbarprefs/MSBRootListController.m; P=../statusbar/macstatusbarprefs/Resources/Desktop.plist
fails=0
# ---- the rows in the Settings search: the index (common/TweakIndex.h) read from the real Desktop page, searched as Settings searches it
mkdir -p "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle" "$W/lib/PreferenceLoader/Preferences"; cp "$P" "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle/Desktop.plist"
cp ../statusbar/macstatusbarprefs/Resources/Root.plist "$W/lib/PreferenceBundles/MacStatusBarPrefs.bundle/Root.plist"
cat > "$W/tidx.m" <<'OBJC'
#import <Foundation/Foundation.h>
#import "TweakIndex.h"
static int bad = 0;
static void Find(NSArray<MTIEntry *> *all, NSString *query, NSString *title, NSString *url) {
    MTIEntry *e = nil;
    for (MTIEntry *x in MTIMatch(all, query, 20)) if ([x.title isEqualToString:title]) { e = x; break; }
    BOOL ok = e && [e.crumb isEqualToString:@"Desktop"] && [MTIPrefsURL(e.uid) isEqualToString:url];
    if (!ok) bad = 1;
    printf("%s  the Settings search: \"%s\" finds %s (%s, %s)\n", ok ? "PASS" : "FAIL", query.UTF8String, e ? e.title.UTF8String : "nothing", e ? e.crumb.UTF8String : "-", e ? MTIPrefsURL(e.uid).UTF8String : "-");
}
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *root = @(argv[1]), *bundle = [root stringByAppendingPathComponent:@"PreferenceBundles/MacStatusBarPrefs.bundle"];
        MTIConfig *c = [MTIConfig new];
        c.plDirs = @[[root stringByAppendingPathComponent:@"PreferenceLoader/Preferences"]]; c.bundleDirs = @[[root stringByAppendingPathComponent:@"PreferenceBundles"]];
        c.supportDir = root; c.languages = @[@"en-US"]; c.cfVersion = 1953.1; c.maxPerPane = 400; c.maxTotal = 6000;
        c.own = @[@{@"id": @"MAC_STATUS_BAR", @"title": @"Status Bar", @"bundle": bundle}, @{@"id": @"MAC_DESKTOP", @"title": @"Desktop", @"bundle": bundle, @"plist": @"Desktop", @"icon": @"desktop"}];
        c.skipBundles = @[@"MacStatusBarPrefs"];
        NSArray<MTIEntry *> *all = MTIBuild(c);
        Find(all, @"radius", @"App Icon Corner Radius", @"prefs:root=MAC_DESKTOP#DESKTOP_APP_CORNER");
        Find(all, @"corner", @"App Icon Corner Radius", @"prefs:root=MAC_DESKTOP#DESKTOP_APP_CORNER");
        Find(all, @"icon radius", @"App Icon Corner Radius", @"prefs:root=MAC_DESKTOP#DESKTOP_APP_CORNER");
        Find(all, @"match home screen", @"Match Home Screen Icons", @"prefs:root=MAC_DESKTOP#DESKTOP_CORNER_MATCH");
        return bad;
    }
}
OBJC
clang -fobjc-arc -Wall -Wno-unused-function -I../common -framework Foundation -o "$W/tidx" "$W/tidx.m" && "$W/tidx" "$W/lib" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
check "the rows: App Icon Corner Radius right after Icon Size -- its group, the slider (desktopAppIconCorner, 0 to 0.5, Finder's notification), Match Home Screen Icons" \
  "python3 -I -c \"
import plistlib,sys,re
items=plistlib.load(open('$P','rb'))['items']
h=open('../common/DesktopAppCorner.h').read()
mx=float(re.search(r'#define MSBD_DESKTOP_CORNER_MAX ([0-9.]+)',h).group(1))
ids=[x.get('id') for x in items]
i=ids.index('DESKTOP_APP_CORNER'); g=items[i-1]; s=items[i]; m=items[i+1]
ok=ids.index('DESKTOP_CORNER_GROUP')==ids.index('DESKTOP_ICON_SIZE')+1 and g.get('cell')=='PSGroupCell' and g.get('label')=='App Icon Corner Radius' and 'desktop only' in g.get('footerText','')
ok=ok and s.get('cell')=='PSSliderCell' and s.get('key')=='desktopAppIconCorner' and s.get('defaults')=='com.besiktasliseba.macstatusbar' and float(s.get('min'))==0 and float(s.get('max'))==mx
ok=ok and s.get('PostNotification')=='com.besiktasliseba.macstatusbar.finder.pref' and not s.get('showValue') and not s.get('label')
ok=ok and m.get('cell')=='PSButtonCell' and m.get('label')=='Match Home Screen Icons' and m.get('action')=='msb_matchHomeScreenCorners:'
ok=ok and chr(0x2014) not in str(items)
sys.exit(0 if ok else 1)\""
check "  ... the key and the notification state are the header's (Settings and SpringBoard read one name)" \
  "grep -q '#define MSBD_DESKTOP_CORNER_KEY \"desktopAppIconCorner\"' ../common/DesktopAppCorner.h && grep -q 'CFSTR(MSBD_DESKTOP_CORNER_KEY)' $C && grep -q 'CFSTR(MSBD_DESKTOP_CORNER_KEY)' $R \
   && grep -q 'notify_register_check(MSBD_DESKTOP_THEMECORNER_STATE, &token)' $C && grep -q 'notify_register_check(MSBD_DESKTOP_THEMECORNER_STATE, &token)' $R"
check "Settings shows the corner in force: the stored one, else the Home Screen's shape as SpringBoard published it" \
  "grep -q 'isEqual:@MSBD_DESKTOP_CORNER_KEY\]) return @(MSBDesktopCornerShownNow());' $R && fn 'static double MSBDesktopCornerShownNow(void) {' $R | grep -q 'return MSBDDesktopCornerShown(n != nil, n.doubleValue, MSBDesktopThemeCornerNow());'"
check "a moved slider always stores the user's own corner, on a 1 % step, once per step -- even where the Home Screen's shape is (KT 2 Nov)" \
  "awk '/isEqual:@MSBD_DESKTOP_CORNER_KEY\]\) \{   \/\/ \(1.7.9/{f=1} f{print} f && /^	}/{exit}' $R > $W/set.txt && grep -q 'MSBDDesktopCornerSnap(\[value doubleValue\])' $W/set.txt \
   && grep -q 'if (corner == gMSBDesktopCornerWritten) return;' $W/set.txt && grep -q '\[super setPreferenceValue:@(corner) specifier:specifier\];' $W/set.txt && ! grep -q 'NULL' $W/set.txt"
check "  ... only Match Home Screen Icons removes it (never set again: the Home Screen's shape, followed), and the slider goes back to that shape" \
  "fn '- (void)msb_matchHomeScreenCorners:(PSSpecifier \*)spec {' $R | grep -q 'CFPreferencesSetAppValue(CFSTR(MSBD_DESKTOP_CORNER_KEY), NULL, kMSBBarDomain);' \
   && fn '- (void)msb_matchHomeScreenCorners:(PSSpecifier \*)spec {' $R | grep -q 'notify_post(\"com.besiktasliseba.macstatusbar.finder.pref\");' \
   && fn '- (void)msb_matchHomeScreenCorners:(PSSpecifier \*)spec {' $R | grep -q 'reloadSpecifier:slider animated:YES' && [ \$(grep -c 'MSBD_DESKTOP_CORNER_KEY), NULL' $R) = 1 ]"
check "  ... Match Home Screen Icons greyed while nothing is stored; the rows greyed with the desktop's others (Finder or Show Desktop Icons off)" \
  "fn '- (void)msb_updateDesktopNamesRow:(BOOL)reload {' $R | grep -q '\[self msb_setCornerMatchRow:MSBDesktopCornerStored() != nil reload:reload\];' \
   && fn '- (void)msb_setCornerMatchRow:(BOOL)stored reload:(BOOL)reload {' $R | grep -q 'stored && slider && (!rows || \[rows boolValue\])' \
   && fn '- (void)msb_updateDesktopNamesRow:(BOOL)reload {' $R | grep -q 'isEqualToString:@\"DESKTOP_APP_CORNER\"'"
check "  ... the slider's first move lights that row alone: the slider's own cell is never reloaded while it is dragged (that ended the drag, r03)" \
  "grep -q 'if (first) \[self msb_setCornerMatchRow:YES reload:YES\];' $R && ! grep -q 'msb_updateDesktopNamesRow' $W/set.txt"
check "  ... live while dragged (a continuous slider, as Icon Size), a square and a circle at its ends, left out where the desktop is (17+ check)" \
  "grep -q 'isEqual:@MSBD_DESKTOP_ICON_KEY\] || \[\[sp propertyForKey:@\"key\"\] isEqual:@MSBD_DESKTOP_CORNER_KEY\]' $R && grep -q 'systemImageNamed:@\"square\"' $R && grep -q 'systemImageNamed:@\"circle\"' $R \
   && grep -q '@\"DESKTOP_CORNER_GROUP\", @\"DESKTOP_APP_CORNER\", @\"DESKTOP_CORNER_MATCH\"\] containsObject:ident' ../common/OwnPageRows.h && grep -q 'MSBDDesktopCheckRow(\[spec propertyForKey:@\"key\"\], spec.identifier)' $R"
check "SpringBoard reads it as Settings writes it (never set: -1) with Finder's notification, and draws the app icons again when it changed" \
  "fn 'static double DMDesktopCornerPref(void) {' $C | grep -q 'MSBDDesktopCornerInForce(num, num ?' && fn 'static void DMDesktopApplyPref(void) {' $D | grep -q 'if (corner != gDesktopAppCorner) { gDesktopAppCorner = corner;' \
   && fn 'static void DMDesktopApplyPref(void) {' $D | grep -q '\[gDesktop dm_appIconsRedraw\]'"
check "  ... never set: every desktop icon exactly as before (the corner's picture only once a corner is set); only .app items change" \
  "fn '- (UIImage *)dm_imageFor:(DMFinderItem *)it view:(DMDesktopItemView *)v {' $D | grep -q 'if (gDesktopAppCorner >= 0) { UIImage \*corner = DMDesktopAppCornerIcon(it, _side, gDesktopAppCorner); if (corner) return corner; }' \
   && fn 'static UIImage *DMDesktopAppCornerIcon(DMFinderItem *it, CGFloat side, double fraction) {' $C | grep -q 'if (!\[it.name hasSuffix:@\".app\"\]' \
   && fn '- (void)dm_appIconsRedraw {' $D | grep -q 'if (!\[it.name hasSuffix:@\".app\"\]) continue;'"
check "  ... the corner is a fraction of the icon's side (Icon Size keeps the look), drawn with the header's shape -- the one this test runs" \
  "fn 'static void DMDesktopCornerRender(' $C | grep -q 'CGPathRef shape = MSBDDesktopCornerPathCreate(side, fraction);' && fn 'static void DMDesktopCornerModel(' $C | grep -q 'DMDesktopCornerRender(c, n, fraction, nil, kDMDesktopWhole,' \
   && fn 'static UIImage *DMDesktopAppCornerIcon(DMFinderItem *it, CGFloat side, double fraction) {' $C | grep -q 'DMDesktopCornerRender(ctx.CGContext, side, fraction, base, part, NULL);' && ! grep -q 'bezierPathWithRoundedRect\|cornerCurve' $C"
check "  ... the picture before the mask: SpringBoard's own app icon for the app (an icon theme's picture), else the .app's own icon files" \
  "fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q 'NSSelectorFromString(@\"unmaskedIconImageWithInfo:\")' && fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q 'MSBDIconTypesAre(method_getTypeEncoding(mu), MSBDIconImageMethodTypes())' \
   && fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q 'img = DMDesktopAppBundleArtwork(appPath);'"
check "  ... a theme's painted frame (KT 2 Nov): only the engine's picture is read for a tile -- never the .app's own files, never an app's own icon without an engine" \
  "awk '/if \\(img && DMDesktopEngineShapes\\(\\)\\) t = DMDesktopTileOf\\(img\\);/{a=NR} /if \\(!img && force != 2\\) \\{ img = DMDesktopAppBundleArtwork\\(appPath\\);/{b=NR} END{exit !(a && b && a < b)}' $C \
   && fn 'static MSBDPaintedTile DMDesktopTileOf(UIImage *img) {' $C | grep -q 't = MSBDPaintedTileFind(px, n, n \\* 4);'"
check "  ... where SpringBoard's picture before the mask does not show what the Home Screen shows (the live Clock: Apple's), the Home Screen's picture" \
  "fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q 'UIImage \\*home = DMFinderIcon(plain, MSBD_DESKTOP_ICON_MAX);' \
   && fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q 'if (home && diff >= MSBD_DESKTOP_PICTURE_SAME) {' && fn 'static double DMDesktopPictureDifference(' $C | grep -q 'return MSBDPictureDifference(a, b, n);'"
check "  ... drawn as the part of the tile that stays inside it at that corner; the Home Screen's picture (no picture before the mask) drawn whole" \
  "fn 'static UIImage *DMDesktopAppCornerIcon(DMFinderItem *it, CGFloat side, double fraction) {' $C | grep -q 'CGRect part = base ? DMDesktopTileWindow(tile, fraction, base.size.width \\* base.scale) : kDMDesktopWhole;' \
   && awk '/CGRect part = base \\? DMDesktopTileWindow/{a=NR} /base = DMFinderIcon\\(plain, side\\);/{b=NR} END{exit !(a && b && a < b)}' $C \
   && fn 'static UIImage *DMDesktopAppCornerIcon(DMFinderItem *it, CGFloat side, double fraction) {' $C | grep -q 'DMDesktopCornerRender(ctx.CGContext, side, fraction, base, part, NULL);' \
   && fn 'static CGRect DMDesktopTileWindow(' $C | grep -q 'if (!t.found) return kDMDesktopWhole;' && fn 'static CGRect DMDesktopTileWindow(' $C | grep -q 'MSBDTileWindow(t.fraction, fraction)'"
check "the Home Screen's shape: read with an app icon of our own an engine shapes (only when it asked for the unmasked picture), else SpringBoard's corner" \
  "fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'double f = home.continuousCornerRadius / home.size.width' && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'if (pic && engine) {' \
   && fn 'static UIImage *DMDesktopCornerProbe(' $C | grep -q 'gDesktopProbeAsked |= masked ? 1 : 2;' && fn 'static double DMDesktopReadEngineMask(' $C | grep -q 'MSBDCornerFit(a, n, DMDesktopCornerModel, NULL, s, &gap)'"
check "  ... iPadOS 18 (no app icon of our own: the probe gives no picture): the Home Screen's own app icons read, their median, iPadOS's own mask told from an engine's" \
  "fn 'static void DMDesktopThemeCornerRead(' $C | grep -q '} else if (!pic) {' && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'int n = DMDesktopReadHomeApps(home, r, 7, said);' \
   && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'MSBDCornerReading m = MSBDCornerMedian(r, n);' && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'if (MSBDCornerIsSpringBoards(m, f))' \
   && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'gDesktopHomeEngine = engine;' && [ \$(grep -c 'gDesktopHomeEngine = ' $C) = 1 ]"
check "  ... the first app icons of its pages in their order (the icon model: page 1 may be the desktop's empty page), SpringBoard's own picture at the Home Screen's size and corner, shape-checked" \
  "fn 'static int DMDesktopReadHomeApps(' $C | grep -q '@\"iconModel\"), @\"rootFolder\"), @\"icons\");' && fn 'static int DMDesktopReadHomeApps(' $C | grep -q 'MSBDIconTypesAre(method_getTypeEncoding(ma), @\"B@:\")' && fn 'static int DMDesktopReadHomeApps(' $C | grep -q 'MSBDIconTypesAre(method_getTypeEncoding(mi), MSBDIconImageMethodTypes())' \
   && fn 'static int DMDesktopReadHomeApps(' $C | grep -q 'objc_msgSend)(icon, image, info);' && fn 'static int DMDesktopReadHomeApps(' $C | grep -q 'DMDesktopReadEngineMask(img, &gap);'"
check "  ... no app icon to read yet: SpringBoard's corner, read again at the next look; a reading once made is kept" \
  "fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'gDesktopThemeGen = NSUIntegerMax;' && fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'if (toldNone || readOnce) return;'"
check "  ... the painted tile looked for where an engine shapes the app icons, as the probe (15-17) or the Home Screen's icons (18) tell; pictures read again when that changes" \
  "fn 'static BOOL DMDesktopEngineShapes(void) {' $C | grep -q 'return gDesktopProbeEngine || gDesktopHomeEngine;' \
   && fn 'static UIImage *DMDesktopAppArtwork(' $C | grep -q '(unsigned long)gDesktopCornerGen, force, DMDesktopEngineShapes()\];' \
   && grep -q 'if (from) DMDesktopThemeCornerRead(home, from);' $D && grep -q 'if (gDesktopHomeEngine != engine && gDesktopAppCorner >= 0) \[self dm_appIconsRedraw\];' $D"
check "  ... published for Settings, read again after a theme engine's refresh (SnowBoard's refreshComplete) -- which draws the app icons again too" \
  "fn 'static void DMDesktopThemeCornerRead(' $C | grep -q 'notify_set_state(token, MSBDDesktopThemeCornerState(f, custom));' && fn 'static void DMDesktopCornerWatch(void) {' $D | grep -q 'notify_register_dispatch(kMSBDIconThemeSnowBoardRefreshed' \
   && fn 'static void DMDesktopCornerWatch(void) {' $D | grep -q 'gDesktopCornerGen++; gFinderAppIconGen++;' && fn '- (void)dm_themeRefreshed {' $D | grep -q '\[self dm_appIconsRedraw\];' \
   && grep -q 'NSString \*ck = \[NSString stringWithFormat:@\"%@|%.0f|%lu\", it.path, side, (unsigned long)gFinderAppIconGen\];' $F"
check "the user's corner is never changed by SpringBoard (only a debug trigger writes it) -- a theme change leaves it alone (KT 2 Nov)" \
  "[ \$(grep -c 'CFPreferencesSetValue(CFSTR(MSBD_DESKTOP_CORNER_KEY)' $X) = 1 ] && awk '/deskcorner_/{f=1} f' $X | head -3 | grep -q 'CFPreferencesSetValue(CFSTR(MSBD_DESKTOP_CORNER_KEY)' \
   && ! grep -q 'CFPreferencesSet[A-Za-z]*(CFSTR(MSBD_DESKTOP_CORNER_KEY)' $D $C"
check "Home Screen app icons are never touched by it (no app icon view's picture or layer is changed by the desktop)" \
  "! grep -nE 'SBIconView.*(setImage|layer\\.(cornerRadius|mask))|iconImageView.*setImage' $D $C"
check "the crash guard: a crash in the corner's code turns the desktop off, as any of its code" \
  "grep -q '^file MacStatusBarCore ^Desktop(Names|Corner)?\\\\.h\$ desktopIcons$' crashmap-rules.txt"
[ $fails = 0 ] && echo "test-desktopcorner: wiring checks pass" || { echo "test-desktopcorner: wiring checks FAILED"; exit 1; }
