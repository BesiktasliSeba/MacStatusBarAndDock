#!/bin/bash
# Mac test of the prewarm block's armed record (common/PrewarmArmed.h, test-prewarmarmed.m; 1.7.7 item 5): Settings offers Prewarm Apps only where
# the prewarm block in dasd is armed -- it showed wherever the page did, and where the block was not armed the switch silently did nothing (1.7.5
# code review, n1). Below, in the code as built: every start of the part records its verdict, and the page and the search leave the row out by it.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -fobjc-arc -framework Foundation -o "$W/tpa" test-prewarmarmed.m
"$W/tpa" ../statusbar/macstatusbarprefs/Resources
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
B=../prewarmblock/PrewarmBlock.x
check "dasd: every start that does not arm records why -- its crash-loop guard, no class or call, another shape -- before it returns" \
  "awk '/^%ctor/,/^}/' $B | grep -q 'if (SelfDisabledByCrashLoop()) { WriteArmedRecord(\"guard\"); return; }' && awk '/^%ctor/,/^}/' $B | grep 'if (!m) {' | grep -q 'WriteArmedRecord(\"missing\"); return; }' && awk '/^%ctor/,/^}/' $B | grep 'if (!DMPrewarmShapeOK(m)) {' | grep -q 'WriteArmedRecord(\"shape\"); return; }'"
check "dasd: an armed start records once its hooks are in: armed, or closure while the closure-build call is there in another shape" \
  "awk '/^%ctor/,/^}/' $B | awk '/MSHookMessageEx\\(c, sel, /{h=1} h&&/gArmed = YES;/{a=1} a&&/gArmedState = closure \\|\\| !mc \\? \"armed\" : \"closure\";/{s=1} s&&/^    RecordArmed\\(\\);/{print \"ok\"; exit}' | grep -q ok"
check "dasd: the record goes through a new file renamed over the old one (never half a line)" \
  "awk '/^static void WriteArmedRecord/,/^}/' $B | awk '/fopen\\(kMSBDPrewarmArmedFile \".new\", \"w\"\\)/{o=1} o&&/rename\\(kMSBDPrewarmArmedFile \".new\", kMSBDPrewarmArmedFile\\)/{print \"ok\"; exit}' | grep -q ok"
check "dasd: the record follows the debug test switch when SpringBoard says the set changed; release builds have no test switch (written once)" \
  "awk '/^%ctor/,/^}/' $B | grep -q 'notify_register_dispatch(kPrewarmChanged, &token, dispatch_get_main_queue(), ^(int t) { MarkQuitSetStale(); RecordArmed(); });' && awk '/^#else/{e=1} e&&/^static BOOL DebugKillSwitch\\(void\\) \\{ return NO; \\}/{print \"ok\"; exit}' $B | grep -q ok"
check "dasd, debug builds: the test switch also beside the quit set's file, which dasd reads everywhere (in /var/tmp it saw the flag on the 17.5, 17.5.1, but read no ask file on the M1, 15.6.1)" \
  "grep -q 'access(\"/var/jb/var/mobile/Library/Preferences/MacStatusBarAndDock-NoPrewarmBlock.txt\", F_OK) == 0' $B"
# the part's build ID follows the record's header (an install then restarts dasd, so a changed record reaches the running dasd)
mkdir -p "$W/tree/prewarmblock" "$W/tree/common" "$W/tree/tools"
cp ../prewarmblock/* "$W/tree/prewarmblock/"; cp ../common/*.h "$W/tree/common/"; cp prewarm-part-id.sh "$W/tree/tools/"
id1=$("$W/tree/tools/prewarm-part-id.sh" "$W/tree/prewarmblock" d); echo '// a change' >> "$W/tree/common/PrewarmArmed.h"
check "the part's build ID counts the record's header (a change to it restarts dasd at the install)" "[ -n '$id1' ] && [ \"\$('$W/tree/tools/prewarm-part-id.sh' '$W/tree/prewarmblock' d)\" != '$id1' ]"
P=../statusbar/macstatusbarprefs/MSBRootListController.m
check "Settings: Windows & Multitasking leaves out the Prewarm Apps row (its sentence goes from Advanced's footer with it, 1.8.6) while the block is not armed, by the state read as the list is built" \
  "grep -q '_msbPrewarmShown = MSBDPrewarmAppsShown() != 0;' $P && grep -qF 'for (PSSpecifier *sp in _specifiers) if (_msbPrewarmShown || ![sp.identifier isEqualToString:kMSBDPrewarmRowID]) [kept addObject:sp];' $P && grep -qF '@\"prewarmApps\": @\"Prewarm Apps:' $P"
check "  ... back on the page, built again when the state changed since (a dasd started again)" \
  "awk '/^@implementation MSBWindowsListController/,/^@end/' $P | grep -q '\\[self msb_prewarmMaybeChanged\\];' && awk '/^- \\(void\\)msb_prewarmMaybeChanged \\{/,/^}/' $P | grep -q '(MSBDPrewarmAppsShown() != 0) == _msbPrewarmShown) return;'"
check "Windows.plist: the switch is in Advanced (1.8.6) with Keep Tailspin Off, hidden on its own with the stock status bar (the row's stockHides; the group has none: Keep Tailspin Off stays)" \
  "plutil -convert json -o - ../statusbar/macstatusbarprefs/Resources/Windows.plist | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; i=[n for n,x in enumerate(it) if x.get(\"id\")==\"PREWARM_APPS\"]; g=[x for x in it[:i[0]] if x.get(\"cell\")==\"PSGroupCell\"][-1] if len(i)==1 else {}; sys.exit(0 if len(i)==1 and g.get(\"id\")==\"ADVANCED_GROUP\" and not g.get(\"stockHides\") and it[i[0]].get(\"stockHides\") is True and \"Prewarm Apps:\" in g.get(\"footerText\",\"\") else 1)'"
S=../common/TweakSpotlight.h
check "search: MTSShownRows leaves out MAC_WINDOWS's PREWARM_APPS exactly while the page does (MSBDPrewarmAppsShown)" \
  "grep -q 'if (rows.count && !MSBDPrewarmAppsShown()) rows = MTIWithout(rows, @\"MAC_WINDOWS\", @\"PREWARM_APPS\");' $S"
check "  ... the Settings search lists only those (its cap after them), Spotlight's Tweak Settings donates only those (Settings and SpringBoard)" \
  "grep -q 'for (MTIEntry \\*e in MTSShownRows(MTIListed(MTIMatch(MTSIndex(), q, 0), gMTSOwnOn, atomic_load(&gMTSTweaksOn)))) { if (added >= kMTSMaxResults) break;' ../macsettings/TweakSearch.x && grep -q 'MTSSyncSpotlight(spot ? MTSShownRows(same ? all : MTIBuild(donated)) : nil, spot, why);' ../macsettings/TweakSearch.x && grep -q 'NSArray<MTIEntry \\*> \\*all = MTSShownRows(MTIBuild(MTSBaseConfig()));' ../statusbar/SpotlightFiles.x"
F=../statusbar/SpotlightFiles.x
check "dasd says when it wrote a record (after the rename: the new record is there), and SpringBoard follows it: Spotlight's Tweak Settings rows made again when Prewarm Apps' row comes or goes (1.7.7 review: a later first record)" \
  "awk '/^static void WriteArmedRecord/,/^}/' $B | awk '/rename\\(kMSBDPrewarmArmedFile \".new\", kMSBDPrewarmArmedFile\\)/{r=1} r&&/if \\(ok\\) notify_post\\(kMSBDPrewarmArmedNote\\);/{print \"ok\"; exit}' | grep -q ok \
   && grep -q 'notify_register_dispatch(kMSBDPrewarmArmedNote, &t4, dispatch_get_main_queue(), ^(int t) { SFArmedChanged(); });' $F \
   && awk '/^static void SFArmedChanged\\(void\\) \\{/,/^}/' $F | grep -q 'if (gSFArmedSeen < 0 || now == gSFArmedSeen) return;' && awk '/^static void SFTweakRefresh\\(NSString \\*why\\) \\{/,/^}/' $F | grep -q 'gSFArmedSeen = MSBDPrewarmAppsShown();' \
   && grep -q '#define kMSBDPrewarmArmedNote \"com.besiktasliseba.macstatusbar.prewarm.armed\"' ../common/PrewarmArmed.h"
check "  ... event-driven only: no timer or poll for it (SpringBoard's debug test poll aside)" \
  "! awk '/^static void SFArmedChanged/,/^}/' $F | grep -q -E 'dispatch_after|NSTimer|DISPATCH_SOURCE_TYPE_TIMER'"
[ $fails = 0 ] && echo "test-prewarmarmed: wiring checks pass" || { echo "test-prewarmarmed: wiring checks FAILED"; exit 1; }
