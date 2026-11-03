#!/bin/bash
# Mac test of Keep Tailspin Off (common/TailspinGuard.h, test-tailspinguard.c; 1.7.9, KT): the rules, and below, in the code as built: the root
# helper applies them (its start, the switch's note, com.apple.da's changes, a removal), Settings' Windows & Multitasking shows the switch only
# where the helper found perfdiagsselfenabled reading the key, with the same default (the search lists it the same way), and nothing writes the
# default.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -framework CoreFoundation -o "$W/ttg" test-tailspinguard.c
"$W/ttg" "$W"
fails=0
# the helper's `tailspin disable` off its main queue (test-tailspinqueue.m: the helper's own code, a fake 1.5 s tool in the scratch folder)
mkdir -p "$W/q"
clang -O0 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreFoundation -DTG_TOOL="\"$W/q/fake-tailspin\"" -DkMSBDTailspinStateFile="\"$W/q/tailspin.plist\"" \
  -DkMSBDTailspinConfig="\"$W/q/tailspin_config.plist\"" -DESTATEDIR="\"$W/q\"" -o "$W/ttq" test-tailspinqueue.m
"$W/ttq" > "$W/ttq.out" || fails=1
grep -v '^      log:' "$W/ttq.out"
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
H=../macsettings/sshtoggled/TailspinDaemon.h; MAIN=../macsettings/sshtoggled/main.m; P=../statusbar/macstatusbarprefs/MSBRootListController.m; WP=../statusbar/macstatusbarprefs/Resources/Windows.plist
check "helper: Apple's preference by the rule -- perfdiagsselfenabled read, the switch (stored, else the RAM's default), Apple's value, our record" \
  "awk '/^static void TGApply\\(NSString \\*why\\) \\{/,/^}/' $H | grep -q 'MSBDTGAction a = MSBDTailspinDecide(supported, wantOff, apple, owned, &ownedAfter);' && awk '/^static BOOL TGSwitchOn\\(void\\) \\{/,/^}/' $H | grep -q 'return MSBDTailspinOffOn(stored, MSBDPrewarmRAM()) != 0;'"
check "  ... for user mobile in com.apple.da, through cfprefsd, as perfdiagsselfenabled reads it (no file written by hand)" \
  "awk '/^static void TGSetAppleValue/,/^}/' $H | grep -q 'CFPreferencesSetValue(CFSTR(kMSBDPDSEAllowKey), value, CFSTR(kMSBDPDSEDomain), CFSTR(\"mobile\"), kCFPreferencesAnyHost);' && ! grep -q 'writeToFile:@TG_DA_FILE' $H"
check "  ... a tailspin perfdiagsselfenabled turned on is turned off at once only where the tool is, and only when it was turned on that way" \
  "awk '/^static void TGApply/,/^}/' $H | grep -q 'if (supported && wantOff && after == 0 && MSBDTailspinOnBySelfEnablement(on, mod.UTF8String)) {' && awk '/^static void TGApply/,/^}/' $H | grep -q 'if (access(TG_TOOL, X_OK) == 0) TGTurnOff(why, mod);'"
check "  ... the tool only on a queue of its own (the main queue never waits for it), its end back on the main queue" \
  "[ \$(grep -c 'TGRunTool(' $H) = 2 ] && awk '/^static void TGTurnOff/,/^}/' $H | grep -q 'dispatch_async(q, ^{' && awk '/^static void TGTurnOff/,/^}/' $H | grep -q 'int rc = TGRunTool(\"disable\");' \
   && awk '/^static void TGTurnOff/,/^}/' $H | grep -q 'dispatch_async(dispatch_get_main_queue(), ^{' && awk '/^static void TGTurnOff/,/^}/' $H | grep -q 'DISPATCH_QUEUE_SERIAL' && ! awk '/^static void TGApply/,/^}/' $H | grep -q 'TGRunTool('"
check "  ... looks at its start, when the switch posts its change, when iPadOS's tasking changes and when com.apple.da's file changes" \
  "grep -q 'notify_register_dispatch(kMSBDTailspinChanged, &t1, dispatch_get_main_queue(), ^(int t) { TGApply(@\"the switch changed\"); });' $H && grep -q 'com.apple.da.tasking_changed' $H && grep -q 'TGApply(@\"com.apple.da changed\");' $H && grep -q '^        TGStart();$' $MAIN"
check "  ... a removal takes our false away (before the package's files go)" \
  "awk '/^static void Uninstall\\(void\\) \\{/,/^}/' $MAIN | grep -q 'TGGiveBack(@\"removal\");' && awk '/^static void TGGiveBack/,/^}/' $H | grep -q 'if (\\[TGState()\\[@\"owned\"\\] boolValue\\] && apple == 0) { TGSetAppleValue(NULL);'"
check "  ... and every other way out of a version (an upgrade, a downgrade): the prerm's --tailspin-giveback, before the daemon would start (test-prerm.sh)" \
  "grep -q 'if (argc > 1 && strcmp(argv\\[1\\], \"--tailspin-giveback\") == 0) { TGGiveBack(' $MAIN && [ \$(grep -n -- '--tailspin-giveback' $MAIN | head -1 | cut -d: -f1) -lt \$(grep -n '^        TGStart();$' $MAIN | cut -d: -f1) ] \
   && grep -q 'case \"\$1\" in remove|purge|upgrade|deconfigure) \\[ -x /var/jb/usr/libexec/sshtoggled \\] && /var/jb/usr/libexec/sshtoggled --tailspin-giveback \"\$1\" ;; esac' ../layout/DEBIAN/prerm"
check "  ... and its state for Settings: the answer whether perfdiagsselfenabled reads the key, written by the look itself" \
  "awk '/^static void TGApply/,/^}/' $H | grep -q '@\"supported\": @(supported)' && awk '/^static void TGApply/,/^}/' $H | grep -q 'TGWriteState(@{' && awk '/^static void TGWriteState/,/^}/' $H | grep -q 'writeToFile:@kMSBDTailspinStateFile atomically:YES'"
check "Settings: Windows.plist has Keep Tailspin Off after Prewarm Apps, the only row of its own group (no stockHides), in our domain, posting the change the helper takes" \
  "plutil -convert json -o - $WP | python3 -c 'import json,sys; it=json.load(sys.stdin)[\"items\"]; g=[n for n,x in enumerate(it) if x.get(\"id\")==\"TAILSPIN_GROUP\"]; p=[n for n,x in enumerate(it) if x.get(\"id\")==\"PREWARM_APPS\"]; x=it[g[0]+1] if len(g)==1 and g[0]+1<len(it) else {}; sys.exit(0 if len(g)==1 and p and g[0]==p[0]+1 and it[g[0]].get(\"cell\")==\"PSGroupCell\" and it[g[0]].get(\"footerText\") and not it[g[0]].get(\"stockHides\") and x.get(\"id\")==\"KEEP_TAILSPIN_OFF\" and x.get(\"key\")==\"keepTailspinOff\" and x.get(\"cell\")==\"PSSwitchCell\" and x.get(\"defaults\")==\"com.besiktasliseba.macstatusbar\" and x.get(\"PostNotification\")==\"com.besiktasliseba.tailspin.changed\" and (g[0]+2==len(it) or it[g[0]+2].get(\"cell\")==\"PSGroupCell\") else 1)'"
check "  ... the switch shows the rule (stored, else the RAM's default), not the plist's placeholder" \
  "awk '/^- \\(id\\)readPreferenceValue:/,/^}/' $P | grep -q 'isEqual:@kMSBDTailspinKey\\]) return @(MSBTailspinOffInForce());' && awk '/^static BOOL MSBTailspinOffInForce\\(void\\) \\{/,/^}/' $P | grep -q 'return MSBDTailspinOffOn(stored, MSBDPrewarmRAM()) != 0;'"
check "  ... its group is left out where the helper's state says perfdiagsselfenabled does not read the key; back on the page, built again when that changed" \
  "grep -q '_msbTailspinShown = MSBDTailspinRowShown() != 0;' $P && grep -q 'if (sp.cellType == PSGroupCell) hiding = !_msbTailspinShown && \\[sp.identifier isEqualToString:@\"TAILSPIN_GROUP\"\\];' $P && awk '/^@implementation MSBWindowsListController/,/^@end/' $P | grep -q '\\[self msb_tailspinMaybeChanged\\];' && awk '/^- \\(void\\)msb_tailspinMaybeChanged \\{/,/^}/' $P | grep -q '(MSBDTailspinRowShown() != 0) == _msbTailspinShown) return;'"
check "  ... and stays under the page's note with the stock status bar or MacStatusBar off (the helper applies it whatever the bar does)" \
  "awk '/^- \\(NSMutableArray \\*\\)msb_windowsPageNotes:/,/^}/' $P | grep -q 'if (sp.cellType == PSGroupCell) tailspin = MSBDBarOffKeepsGroup(sp.identifier);' && grep -q 'static inline BOOL MSBDBarOffKeepsGroup(NSString \\*groupID) { return \\[groupID isEqualToString:kMSBDTailspinGroupID\\]; }' ../common/OwnPageRows.h && grep -q '#define kMSBDTailspinGroupID @\"TAILSPIN_GROUP\"' ../common/OwnPageRows.h && awk '/^- \\(NSMutableArray \\*\\)msb_windowsPageNotes:/,/^}/' $P | grep -q 'if (tailspin) \\[kept addObject:sp\\];'"
check "search: MTSShownRows leaves out MAC_WINDOWS's KEEP_TAILSPIN_OFF exactly while the page does; Spotlight's rows follow the helper's state" \
  "grep -q 'if (rows.count && !MSBDTailspinRowShown()) rows = MTIWithout(rows, @\"MAC_WINDOWS\", @\"KEEP_TAILSPIN_OFF\");' ../common/TweakSpotlight.h && grep -q 'notify_register_dispatch(kMSBDTailspinUpdated, &t5, dispatch_get_main_queue(), ^(int t) { SFTailspinChanged(); });' ../statusbar/SpotlightFiles.x && awk '/^static void SFTailspinChanged/,/^}/' ../statusbar/SpotlightFiles.x | grep -q 'if (gSFTailspinSeen < 0 || now == gSFTailspinSeen) return;'"
check "nothing writes the default: keepTailspinOff is never set in code (only a tap on the switch stores one)" \
  "! grep -rn 'CFPreferencesSet[A-Za-z]*Value(CFSTR(kMSBDTailspinKey)\\|CFPreferencesSet[A-Za-z]*Value(CFSTR(\"keepTailspinOff\")' ../macsettings ../statusbar ../common"
check "removal: the postrm takes the helper's state file with the others (test-postrm.sh: the folder goes)" \
  "grep -q 'rm -f \"\$S/tailspin.plist\"' ../layout/DEBIAN/postrm"
[ $fails = 0 ] && echo "test-tailspinguard: wiring checks pass" || { echo "test-tailspinguard: wiring checks FAILED"; exit 1; }
