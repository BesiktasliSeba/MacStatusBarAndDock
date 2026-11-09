#!/bin/bash
# Mac test of Banner Style (common/BannerStyle.h, test-bannerstyle.c; 1.8.0 item 2, KT 2 and 3 Nov): the rule itself, then the readers built on the Mac
# (common/BannerStyleNow.h: the stored style, the old Mac-Style Banners switch, Destra's library and its own Enabled switch), then, in the code as
# built, that every side reads the one rule -- Settings (the row, its page, the group's footer), SpringBoard (ours shown or not, hooked or not,
# Settings told, the start's switch) and the root helper (whether Destra loads) -- that the crash guard sets the style back, and that nothing writes
# the default.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreFoundation -o "$W/t" test-bannerstyle.c
"$W/t"
# the readers, on this Mac: a domain of our own for the old switch and Destra's own one, nothing of Destra's in TweakInject (not installed)
cat > "$W/now.m" <<'EOF'
#import <Foundation/Foundation.h>
#include "BannerStyleNow.h"
int main(int argc, char **argv) { @autoreleasepool {
    printf("%d %d %d %d\n", MSBDBannerStyleStoredFor(kCFPreferencesCurrentUser), MSBDBannerLegacyFor(kCFPreferencesCurrentUser), MSBDDestraInstalled(NO), MSBDBannerStyleNow(NO));
} return 0; }
EOF
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -I "$PWD/../common" -o "$W/now" "$W/now.m"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
check "the readers on this Mac: nothing stored, Destra not installed -- Mac (the rule's default for a new user)" "[ \"\$(\"$W/now\")\" = '0 0 0 1' ]"
# Destra's own switch from its file (its page writes the file itself, past cfprefsd): missing, its page's XML, cfprefsd's binary, a number
cat > "$W/own.m" <<'EOF2'
#import <Foundation/Foundation.h>
#include "BannerStyleNow.h"
int main(int argc, char **argv) { @autoreleasepool { printf("%d", MSBDDestraOwnOn()); } return 0; }
EOF2
clang -fobjc-arc -Wall -Wno-unused-function -framework Foundation -I "$PWD/../common" "-DkMSBDDestraPrefsFile=@\"$W/destra.plist\"" -o "$W/own" "$W/own.m"
own() {   # own <python literal or empty> <FMT_XML|FMT_BINARY>: the switch as read from that file (missing for an empty literal)
  rm -f "$W/destra.plist"
  [ -n "$1" ] && python3 -c 'import plistlib,sys,ast; plistlib.dump(ast.literal_eval(sys.argv[1]), open(sys.argv[2],"wb"), fmt=getattr(plistlib, sys.argv[3]))' "$1" "$W/destra.plist" "$2"
  "$W/own"
}
OWN="$(own '' FMT_XML)$(own "{'enabled': False, 'alignRight': '2'}" FMT_XML)$(own "{'enabled': True}" FMT_XML)$(own "{'enabled': False}" FMT_BINARY)$(own "{'enabled': 0}" FMT_XML)$(own "{'enabled': 1}" FMT_BINARY)$(own "{'enabled': 'no'}" FMT_XML)"
check "Destra's own switch, read from its file: never set on; its page's XML off / on; cfprefsd's binary off; a number 0 off, 1 on; another kind: on (its default)" "[ '$OWN' = '1010011' ]"
N=../common/BannerStyleNow.h; P=../statusbar/macstatusbarprefs/MSBRootListController.m; SB=../statusbar/StatusBar.x; B=../statusbar/BannerStyleSB.h
H=../macsettings/sshtoggled/main.m; R=../statusbar/macstatusbarprefs/Resources/Root.plist; K=../statusbar/StockBar.h; C=../common/ChoicePage.h
check "the readers: the stored style, the old switch, Destra installed (ExclusiveChoice.h) -- one rule; Destra's own switch read only when asked for (SpringBoard's style in force), the user's switch-off not at all (never set is ours, KT 3 Nov)" \
  "awk '/^static inline int MSBDBannerStyleNowFor/,/^}/' $N > \$W/nowfor && ! grep -q 'MSBDExUserOffNow' \$W/nowfor \
   && grep -q 'if (ownOn) \*ownOn = destra && MSBDDestraOwnOn();' \$W/nowfor \
   && grep -q 'return MSBDBannerStyleChosen(MSBDBannerStyleStoredFor(user), MSBDBannerLegacyFor(user), destra);' \$W/nowfor \
   && grep -q 'return MSBDExInstalled(kMSBDDestraLib);' $N && grep -q 'if (display && MSBDBannerPretendNoDestra()) return NO;' $N \
   && grep -q '#define kMSBDDestraLib    @\"MacOSNotifications\"' $N && grep -q '#define kMSBDDestraPrefsFile @\"/var/jb/var/mobile/Library/Preferences/com.jaxroth.macosnotifications.plist\"' $N \
   && grep -q 'NSDictionary \*d = \[NSDictionary dictionaryWithContentsOfFile:kMSBDDestraPrefsFile\];' $N && ! grep -q 'jaxroth.macosnotifications\")' $N \
   && grep -q '{ \"bannerStyle\", \"destra\", \"Destra\", NULL, { \"MacOSNotifications\" } },' ../common/ExclusiveChoice.h"
check "Settings: the row shows the rule's style (the debug pretend only on the pages), a tap stores only a style that is not in force already" \
  "grep -q 'static int MSBBannerStyleShown(void) { return MSBDBannerStyleNow(YES); }' $P && grep -q 'isEqual:@kMSBDBannerStyleKey\\]) return @(MSBDBannerStyleValue(MSBBannerStyleShown()));' $P \
   && awk '/isEqual:@kMSBDBannerStyleKey\\]\\) \\{   \\/\\/ \\(1.8.0: Mac \\/ iPadOS \\/ Destra/,/return;$/' $P | grep -q 'if (!style || style == before) return;' \
   && grep -q 'MSBDNoteSwitch(@\"com.besiktasliseba.macstatusbar\", @kMSBDBannerStyleKey, @\"Banner Style\", before == kMSBDBannerMac, style == kMSBDBannerMac);' $P"
check "  ... the exclusivity from the real files, never in safe mode or on an untested iPadOS; the respring only when what loads changes" \
  "awk '/^- \\(void\\)msb_bannerStyleChanged:/,/^}/' $P > \$W/chg && grep -q 'if (!MSBDGateWanted()) return;' \$W/chg && grep -q 'if (!MSBDDestraInstalled(NO)) return;' \$W/chg \
   && [ \$(grep -c 'if (want != loaded) {' \$W/chg) = 2 ] && grep -q 'MSBChoicyApplyChoice(@kMSBDBannerStyleKey, @(MSBDBannerStyleValue(style)))' \$W/chg \
   && grep -q 'notify_post(\"com.besiktasliseba.msb.engines.apply\")' \$W/chg && grep -q 'BOOL want = MSBDBannerLoadsDestra(style), destraOn = MSBDDestraOwnOn();' \$W/chg"
check "  ... the page: Destra's row (always there, greyed while not installed: ChoicePage.h), the Third-Party footer when Destra is off in its own settings; the group's footer (Choicy needed where nothing can keep Destra out)" \
  "awk '/^- \\(NSDictionary \\*\\)msb_rowFor:/,/^}/' $P | grep -q 'return MSBDChoiceBannerRow(value, MSBDDestraInstalled(YES));' \
   && grep -q 'return MSBDChoiceBannerThirdPartyFooter(installed, installed && MSBDDestraOwnOn());' $P \
   && grep -q 'if (\\[spec.identifier isEqualToString:@\"BANNERS_GROUP\"\\]) \\[spec setProperty:MSBBannerGroupFooter(MSBBannerStyleShown()) forKey:@\"footerText\"\\];' $P \
   && grep -q 'BOOL installed = MSBDDestraInstalled(YES), keeper = MSBChoicyInstalled() || MSBiCleanerInstalled();' $P \
   && grep -q 'MSBDBannerRespringNote(style, installed, keeper, MSBBannerStyleSpringBoard())' $P \
   && ! grep -q 'kMSBDDupBanners' $P && grep -q 'static inline NSString \\*MSBDChoiceBannerGroupFooter(int style' $C"
check "Root.plist: Banner Style first in the Notifications group (mac / stock / destra, the shared choice page, no default); no Mac-Style Banners switch left" \
  "plutil -convert json -o - $R | python3 -c '
import json,sys
it=json.load(sys.stdin)[\"items\"]
g=[i for i,x in enumerate(it) if x.get(\"id\")==\"BANNERS_GROUP\"][0]
r=it[g+1]
ok=r.get(\"id\")==\"BANNER_STYLE\" and r.get(\"key\")==\"bannerStyle\" and r.get(\"validValues\")==[\"mac\",\"stock\",\"destra\"] and r.get(\"validTitles\")==[\"Mac\",\"iPadOS\",\"Destra\"]
ok=ok and r.get(\"shortTitles\")==[\"Mac\",\"iPadOS\",\"Destra\"] and r.get(\"detail\")==\"MSBChoiceListController\" and \"default\" not in r and r.get(\"cell\")==\"PSLinkListCell\"
ok=ok and r.get(\"PostNotification\")==\"com.besiktasliseba.macstatusbar/prefsChanged\" and it[g+2].get(\"cell\")==\"PSGroupCell\"
ok=ok and not [x for x in it if x.get(\"key\")==\"macBanners\"] and it[g].get(\"footerText\")==\"Only the chosen banner style is loaded.\"
sys.exit(0 if ok else 1)'"
check "SpringBoard: ours shown only with Mac in force (Destra still loaded and on when it loaded: ours steps aside), the style from the real files (no pretend)" \
  "grep -q '^static BOOL DMBannersOn(void) { return DMBannerStyleInForceNow() == kMSBDBannerMac; }$' $SB && ! grep -q 'kMSBDDupBanners' $SB ../common/OtherTweaks.h \
   && grep -q 'int chosen = MSBDBannerStyleNowFor(kCFPreferencesCurrentUser, NO, &installed, &ownOn);' $B && grep -q 'if (loaded && gDMBannerDestraOnAtLoad < 0) gDMBannerDestraOnAtLoad = ownOn;' $B \
   && grep -q 'int inForce = MSBDBannerInForce(chosen, loaded, loaded && gDMBannerDestraOnAtLoad == 1);' $B && grep -q 'gDMBannerChosen = chosen; gDMBannerInForce = inForce;' $B \
   && grep -q 'notify_set_state(token, state)' $B && grep -q '#include \"BannerStyleSB.h\" ' $SB"
check "  ... Destra's own settings not followed (they decide nothing now: never set is ours, KT 3 Nov); a burst of our changes is one look, when the stored style or the old switch changed" \
  "awk '/^static void DMBannerStyleChanged/,/^}/' $B > \$W/chd && grep -q 'if (MSBDBannerStyleStoredFor(kCFPreferencesCurrentUser) != gDMBannerStored || MSBDBannerLegacyFor(kCFPreferencesCurrentUser) != gDMBannerLegacy)' \$W/chd \
   && grep -q 'DMBannerStyleLook(@\"our settings changed\");' \$W/chd \
   && ! grep -q 'macosnotifications.reloadprefs' $B $SB && ! grep -q 'DMBannerStyleDestraChanged' $B $SB"
check "  ... a change of what should load while running (a pick) asks the root helper at once" \
  "grep -q 'if (gDMBannerChosen != kMSBDBannerNone && installed && MSBDBannerLoadsDestra(chosen) != MSBDBannerLoadsDestra(gDMBannerChosen))' $B \
   && awk '/^static void DMBannerStyleLook/,/^}/' $B | grep -q 'notify_post(\"com.besiktasliseba.msb.engines.apply\");'"
check "  ... our banners hooked only while Destra is not the style, with either status bar style (the start, StockBar.h); followed as our settings change" \
  "grep -q 'if (gDMBannerHooksAllowed && !MSBDBannerLoadsDestra(chosen)) DMBannersInit();' $B && grep -q 'DMBannerStyleInit(!DMCtorSkip(\"banners\"));' $SB \
   && grep -q 'DMBannerStyleInit(YES);' $K && ! grep -q 'DMBannersInit();' $K && [ \$(grep -c 'DMBannersInit();' $SB) = 0 ] \
   && grep -q 'CFSTR(\"com.besiktasliseba.macstatusbar/prefsChanged\")' $B"
check "  ... at the start: the helper's word awaited when Destra loaded the wrong way, the question only for what the helper changed (4), Destra's own words" \
  "grep -q 'gEngineAskBanners = DMBannerStyleSwitchDue();' $SB && grep -q 'if ((engineAsk || gEngineAskCC || gEngineAskBanners) && DMEngineHelperInstalled()) {' $SB \
   && grep -q '| ((what & 4) && gEngineAskBanners ? 4 : 0);' $SB && grep -q 'if (gEngineAskWhat & 4) {' $SB \
   && grep -q 'NSString \\*bn = DMBannerStyleSwitchText(choicy ? @\"Choicy\" : @\"iCleaner Pro\");' $SB"
check "the root helper: the style read for mobile by the same rule; Destra kept or kept out with Choicy and with iCleaner Pro's renames, SpringBoard told (4)" \
  "awk '/^static int ChosenBannerStyle/,/^}/' $H > \$W/hb && grep -q 'return MSBDBannerStyleChosen(MSBDBannerStyleStoredFor(CFSTR(\"mobile\")), MSBDBannerLegacyFor(CFSTR(\"mobile\")), installed);' \$W/hb \
   && ! grep -q 'MSBDExUserOffNow' \$W/hb && ! grep -q 'MSBDDestraOwnOn' \$W/hb \
   && grep -q 'NSString \\*owner = there ? LibraryOwner(@\"MacOSNotifications\") : nil;' \$W/hb \
   && grep -q 'else \\[MSBDBannerLoadsDestra(banners) ? keep : deny addObject:@\"MacOSNotifications\"\\];' $H && grep -q 'if (!destra) \\[notInstalled addObject:@\"MacOSNotifications\"\\];' $H \
   && grep -q 'if (destra && MSBDBannerLoadsDestra(banners)) EnableOurs(@\"MacOSNotifications\", record, @\"Destra is the Banner Style\");' $H \
   && grep -q 'enum { kChangedEngines = 1, kChangedCCStyle = 2, kChangedBanners = 4 };' $H && [ \$(grep -c 'kChangedBanners;' $H) = 2 ]"
check "the crash guard: a crash in our banners (their hooks, DMBanner..., BannerStyleSB.h) sets Banner Style back to iPadOS's, not the old switch; \"stock\" stored counts as off (offtext)" \
  "grep -q '^target macBanners pref com.besiktasliseba.macstatusbar bannerStyle 0 1 offtext=stock Banner Style|the Mac-style banners$' crashmap-rules.txt \
   && grep -q '^file MacStatusBarCore \\^BannerStyleSB\\\\\\.h\\$ macBanners$' crashmap-rules.txt && grep -q '^sym MacStatusBarCore \\^_?DMBanner macBanners$' crashmap-rules.txt"
check "nothing writes the default: no bannerStyle or macBanners written by SpringBoard, the helper or our Settings code (only the row's own store, at a tap)" \
  "! grep -n 'CFPreferencesSet[A-Za-z]*Value(CFSTR(\"bannerStyle\")\\|CFPreferencesSet[A-Za-z]*Value(CFSTR(kMSBDBannerStyleKey)\\|CFPreferencesSet[A-Za-z]*Value(CFSTR(\"macBanners\")\\|CFPreferencesSet[A-Za-z]*Value(CFSTR(kMSBDBannerLegacyKey)' $SB $B $H $P $K ../common/*.h"
[ $fails = 0 ] && echo "test-bannerstyle: wiring checks pass" || { echo "test-bannerstyle: wiring checks FAILED"; exit 1; }
