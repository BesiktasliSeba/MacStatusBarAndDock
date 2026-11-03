#!/bin/bash
# Mac test of the Settings search's rule for our own rows (macsettings/TweakSearch.x; 1.7.9, KT): our own pages and rows (the Status Bar, Desktop,
# Windows & Multitasking and Dock pages, our rows of the main list and on Apple's pages) are always listed, "Include Tweak Settings" only adds
# other tweaks' pages; Spotlight's Tweak Settings stays as it was (its own switch, for both). The rule itself is TweakIndex.h's MTIListed and
# MTIGuardKind (test-tweakindex.m); here, in the code as built: who reads which switch, what the index reads, what the loop guard does.
set -e
cd "$(dirname "$0")"
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
T=../macsettings/TweakSearch.x; S=../common/TweakSpotlight.h; F=../statusbar/SpotlightFiles.x
check "other tweaks' pages: only with Search Field in Settings and Include Tweak Settings (the rule as before)" \
  "grep -q '^    atomic_store(&gMTSTweaksOn, MTSBool(CFSTR(\"sidebarSearch\"), kMTSSettingsDomain, YES) && MTSBool(CFSTR(\"sidebarTweaks\"), kMTSSettingsDomain, NO));' $T"
check "  ... Include Tweak Settings is read nowhere else (the guard only switches it off)" \
  "[ \$(grep -rn 'sidebarTweaks' ../macsettings ../common ../statusbar ../dock --include=*.x --include=*.h --include=*.m --include=*.c | wc -l) = 2 ] && grep -q 'if (deaths >= 2 && kind == 2) CFPreferencesSetAppValue(CFSTR(\"sidebarTweaks\"), kCFBooleanFalse, kMTSSettingsDomain);' $T"
check "our own pages and rows: always -- set once at load, after the loop guard's look, where the search's hooks are in, unless the guard left them out" \
  "awk '/^%ctor/,/^}/' $T | awk '/MTSGuardAtStart\\(\\);/{g=1} g&&/gMTSOwnOn = MTSOwnListedAtStart\\(\\);/{print \"ok\"; exit}' | grep -q ok && awk '/^static BOOL MTSOwnListedAtStart\\(void\\) \\{/,/^}/' $T | grep -q 'return gMTSResultsOK && !off;' && ! awk '/^static BOOL MTSOwnListedAtStart\\(void\\) \\{/,/^}/' $T | grep -q 'sidebar' && [ \$(grep -c 'gMTSOwnOn = ' $T) = 1 ]"
check "the search hands over the matches listed by that rule (MTIListed), the rows their page leaves out taken away after (MTSShownRows), its cap after them" \
  "grep -q 'for (MTIEntry \\*e in MTSShownRows(MTIListed(MTIMatch(MTSIndex(), q, 0), gMTSOwnOn, atomic_load(&gMTSTweaksOn)))) { if (added >= kMTSMaxResults) break;' $T && awk '/^static NSArray \\*MTSMerge/,/^}/' $T | grep -q 'if (MTSListsAny() && q.length) {'"
check "  ... our sections shown, the search run again and an empty hand-over made whenever the search lists any of ours" \
  "grep -q 'static BOOL MTSListsAny(void) { return gMTSOwnOn || atomic_load(&gMTSTweaksOn); }' $T && grep -q 'if (MTSIsOurs(category)) return MTSListsAny();' $T && awk '/^static void MTSCompleted/,/^}/' $T | grep -c 'MTSListsAny()' | grep -q '^2$' && awk '/^static void MTSRequery/,/^}/' $T | grep -q '(!force && !MTSListsAny())) return;' && ! grep -q 'gMTSSearchOn' $T"
check "  ... a switch change runs it again only for other tweaks' rows (ours stay)" \
  "awk '/^%ctor/,/^}/' $T | grep -q 'if (tweaks != atomic_load(&gMTSTweaksOn)) MTSRequery(YES);'"
check "  ... the debug match command lists what the search lists" \
  "grep -q 'NSArray<MTIEntry \\*> \\*hits = MTSShownRows(MTIListed(MTIMatch(MTSIndex(), \\[c substringFromIndex:6\\], 0), gMTSOwnOn, atomic_load(&gMTSTweaksOn)));' $T"
check "index: other tweaks' files read only for a switch that lists them (Include Tweak Settings, Spotlight's Tweak Settings), else our own rows alone; nothing built when nothing lists" \
  "awk '/^static void MTSRebuild/,/^}/' $T | grep -q 'if (!gMTSOwnOn && !tweaks && !spot) { dispatch_async(gMTSQueue, ^{ MTSSyncSpotlight(nil, NO, why); }); return; }' && awk '/^static void MTSRebuild/,/^}/' $T | grep -q 'BOOL others = tweaks || spot;' && awk '/^static void MTSRebuild/,/^}/' $T | grep -q 'if (!others) cfg.plDirs = @\\[\\];'"
check "  ... the guard's mark says which kind of build runs (1 ours alone, 2 other tweaks' pages too), taken away when it is done" \
  "awk '/^static void MTSRebuild/,/^}/' $T | grep -q 'MTSGuardMark(others ? 2 : 1);' && awk '/^static void MTSRebuild/,/^}/' $T | grep -q 'MTSGuardMark(0);' && awk '/^static void MTSGuardMark/,/^}/' $T | grep -q 'kind ? (__bridge CFNumberRef)@(kind) : NULL'"
check "loop guard: a start that ended in a build with other tweaks' pages counts as before (two in a row: Include Tweak Settings and Spotlight's Tweak Settings off)" \
  "awk '/^static void MTSGuardAtStart/,/^}/' $T | grep -q 'int kind = MTIGuardKind((__bridge id)m);' && awk '/^static void MTSGuardAtStart/,/^}/' $T | grep -q 'CFStringRef counter = kind == 1 ? CFSTR(\"tweakIndexOwnDeaths\") : CFSTR(\"tweakIndexDeaths\");' && awk '/^static void MTSGuardAtStart/,/^}/' $T | awk '/if \\(kind == 1\\) \\{ MTSLog/{k=1} k&&/CFPreferencesSetValue\\(CFSTR\\(\"spotlightTweakSettings\"\\), kCFBooleanFalse/{print \"ok\"; exit}' | grep -q ok"
check "  ... one in a build of our own rows alone counts apart: two in a row leave them out of the Settings search for this build of the part only" \
  "awk '/^static void MTSGuardAtStart/,/^}/' $T | grep -q 'if (deaths >= 2 && kind == 1) CFPreferencesSetAppValue(CFSTR(\"tweakIndexOwnOff\"), (__bridge CFStringRef)MTSPartStamp(), kMTSSettingsDomain);' && awk '/^static BOOL MTSOwnListedAtStart/,/^}/' $T | grep -q 'if (off && !\\[off isEqualToString:MTSPartStamp()\\]) {' && awk '/^static NSString \\*MTSPartStamp/,/^}/' $T | grep -q 'stat(di.dli_fname, &st)'"
check "  ... a finished build clears both counts" \
  "awk '/^static void MTSGuardMark/,/^}/' $T | grep -q 'if (!kind) { CFPreferencesSetAppValue(CFSTR(\"tweakIndexDeaths\"), NULL, kMTSSettingsDomain); CFPreferencesSetAppValue(CFSTR(\"tweakIndexOwnDeaths\"), NULL, kMTSSettingsDomain); }'"
check "Spotlight's Tweak Settings as it was: its own switch (with our status bar in use), our rows and other tweaks' alike, in Settings and SpringBoard" \
  "grep -q 'static BOOL MTSSpotlightSwitch(void) { return MTSBarInUse() && MTSBool(CFSTR(\"spotlightTweakSettings\"), kMTSBarDomain, NO); }' $S && grep -q 'MTSSyncSpotlight(spot ? MTSShownRows(same ? all : MTIBuild(donated)) : nil, spot, why);' $T && grep -q 'NSArray<MTIEntry \\*> \\*all = MTSShownRows(MTIBuild(MTSBaseConfig()));' $F && ! grep -q 'MTIListed' $S $F"
[ $fails = 0 ] && echo "test-searchown: wiring checks pass" || { echo "test-searchown: wiring checks FAILED"; exit 1; }
