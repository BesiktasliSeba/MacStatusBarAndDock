#!/bin/bash
# Mac test of the per-display settings (1.8.7; plans/design-1.8.7-displays.md): the rule, flat keys and the display key in plain C
# (common/DisplayPrefs.h, test-displayprefs.c), then the sites: common/DisplayIdentity.h derives the key from what each screen says of itself.
# Last, copies of the rule with one thing broken must fail the C test.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tdp" test-displayprefs.c
RECENT="$W/recent.txt" "$W/tdp"
fails=0
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
I=../common/DisplayIdentity.h; P=../common/DisplayPrefs.h
check "DisplayIdentity.h: a screen's key by the shared rule (MSBDDispKeyFrom), the iPad's own screen none" \
  "fn 'static inline NSString *MSBDDispKeyOfScreen(UIScreen *s) {' $I && grep -q 'if (!s || s == \[UIScreen mainScreen\]) return nil;' \$W/fn \
   && grep -q 'int kind = MSBDDispKeyFrom(0, hw.UTF8String, u.UTF8String, key, sizeof key);' \$W/fn && grep -q 'return kind == kMSBDDispKeyMain ? nil' \$W/fn \
   && grep -q 'if (MSBDDispScreenIsMain(s, cfg)) return nil;' \$W/fn && grep -q '#include \"DisplayPrefs.h\"' $I"
check "  ... the configuration's hardwareIdentifier first (S1: the same on the TV's three screens), the CADisplay's uniqueId only when it is nil or no id" \
  "fn 'static inline NSString *MSBDDispKeyOfScreen(UIScreen *s) {' $I && grep -q 'NSString \*hw = MSBDDispStr(MSBDDispGet(cfg, \"hardwareIdentifier\"));' \$W/fn \
   && grep -q 'NSString \*u = MSBDDispIdUsable(hw.UTF8String) ? nil : MSBDDispStr(MSBDDispGet(MSBDDispCADisplayOfConfig(cfg), \"uniqueId\"));' \$W/fn"
check "  ... a non-string or empty value is no string (the rule reads it as no id: any)" \
  "grep -qF 'static inline NSString *MSBDDispStr(id v) { return [v isKindOfClass:[NSString class]] && [(NSString *)v length] ? (NSString *)v : nil; }' $I"
check "  ... the CADisplay by its uniqueId, else its deviceName, else the only one with its name (two: none, never a guess)" \
  "fn 'static inline id MSBDDispCADisplayOfConfig(id cfg) {' $I && grep -q 'caseInsensitiveCompare:hw' \$W/fn && grep -q '\"deviceName\")) isEqualToString:dn\]' \$W/fn && grep -q 'return n == 1 ? byName : nil;' \$W/fn"
check "  ... every private call shape-checked (it answers, no argument, an object back) and in @try" \
  "fn 'static inline id MSBDDispGet(id o, const char *name) {' $I && grep -q 'method_getNumberOfArguments(m) != 2' \$W/fn && grep -q \"t\[0\] != '@'\" \$W/fn && grep -q '@try' \$W/fn && grep -q '@catch' \$W/fn \
   && ! grep -E 'objc_msgSend\)\(' $I | grep -v 'MSBDDispGet\|MSBDDispGetBool\|return ((id (\*)(id, SEL))objc_msgSend)(o, s);\|return ((BOOL (\*)(id, SEL))objc_msgSend)(o, s)' | grep -q ."
check "  ... the iPad's screen: the main screen, or a configuration that says it is not external" \
  "fn 'static inline BOOL MSBDDispScreenIsMain(UIScreen *s, id cfg) {' $I && grep -q 'int ext = MSBDDispGetBool(cfg, \"isExternal\");' \$W/fn && grep -q 'if (ext == 0) return YES;' \$W/fn"
check "DisplayPrefs.h is plain C (the loaders and the crash guard include it): no ObjC, no CoreFoundation" \
  "! grep -E '^#(import|include) <(UIKit|Foundation|CoreFoundation)' $P && ! grep -q '@interface\|@\"\|NSString\|CFString' $P"
S=../statusbar/StatusBar.x; L=../statusbar/DisplayPrefs.h
# (commit 3) the layer in SpringBoard's status bar part: the registry, the caches and the getters, and no reader converted yet
# (the getters' callers since commit 5, each reader asking with its screen: test-displayreaders.sh)
check "  ... the getters return the iPad's value for the iPad's own screen (or none) at once: no key, no lookup" \
  "for g in 'static BOOL DMDispBool(UIScreen *s,' 'static double DMDispNum(UIScreen *s,' 'static id DMDispValue(UIScreen *s,' 'static BOOL DMDispBoolForIdentity(id identity,' 'static double DMDispNumForIdentity(id identity,' 'static id DMDispValueForIdentity(id identity,'; do grep -A1 -F \"__attribute__((unused, noinline)) \$g\" $L | tail -1 | grep -q 'if (!s || s == \[UIScreen mainScreen\]) return ipad;\|if (!identity || (!gDMDispLayerOn \&\& !MSBDDispDisplayDefault(part, key, NULL))) return ipad;' || exit 1; done \
   && for g in DMDispBoolForKey DMDispNumForKey DMDispValueForKey; do grep -A1 \"^__attribute__((noinline)) static [A-Za-z]* *\**\$g(\" $L | grep -q 'if (!display) return ipad;' || exit 1; done"
check "  ... a display resolves by the shared rule from the cache (layer switch, override and its type, the display default)" \
  "fn 'static id DMDispResolveFor(' $L && grep -q 'BOOL typeOK = MSBDDispTypeOK(want, got, num, hasRange, lo, hi);' \$W/fn && grep -q 'int hasDef = MSBDDispDisplayDefault(part, key, def);' \$W/fn \
   && grep -q '\*from = MSBDDispResolve(0, gDMDispLayerOn, ov != nil, typeOK, hasDef);' \$W/fn && grep -q 'ov = gDMDispCache\[display\]\[fk\];' \$W/fn"
check "  ... the cache: the master switch (absent or true: on) and every remembered display's overrides, from the displays domain" \
  "fn '__attribute__((noinline)) static void DMDispReload(void) {' $L && grep -q 'gDMDispLayerOn = !\[master isKindOfClass:\[NSNumber class\]\] || \[master boolValue\];' \$W/fn \
   && grep -q 'if (!mine) cache\[d\] = mine = \[NSMutableDictionary dictionary\];' \$W/fn && grep -q 'MSBDDispFlatSplit(flat.UTF8String, display' \$W/fn \
   && grep -q '#define MSBD_DISP_MASTER_KEY \"displaySettings\"' $P"
check "  ... rebuilt on the displays domain's prefsChanged and the iPad's own (both parts), and with every registry update" \
  "fn 'static void DMDispInit(void) {' $L && grep -q 'MSBD_DISP_NOTIFY, \"com.besiktasliseba.macstatusbar/prefsChanged\", \"com.besiktasliseba.dockmagnification/prefsChanged\"' \$W/fn \
   && grep -q 'notify_register_dispatch(names\[i\], &tokens\[i\], dispatch_get_main_queue(), ^(int tok) {' \$W/fn && grep -q '        DMDispReload();' \$W/fn \
   && fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString \*why) {' $L && grep -q 'DMDispReload();' \$W/fn"
check "the registry: written on connect and disconnect (one update 0.6 s after the last note) and once after the start; nowhere else (switched off: only its connected list let go)" \
  "fn 'static void DMDispInit(void) {' $L && grep -q 'UIScreenDidConnectNotification object:nil queue:\[NSOperationQueue mainQueue\] usingBlock:^(NSNotification \*n) { if (gDMDispLayerOn) DMDispScheduleUpdate(' \$W/fn \
   && grep -q 'UIScreenDidDisconnectNotification object:nil queue:\[NSOperationQueue mainQueue\] usingBlock:^(NSNotification \*n) { if (gDMDispLayerOn) DMDispScheduleUpdate(' \$W/fn \
   && grep -q 'DMDispRegistryUpdate(@\"SpringBoard started\");' \$W/fn && [ \$(grep -c 'DMDispRegistryUpdate(' $L) = 4 ] && grep -q 'if (was && !gDMDispLayerOn) DMDispRegistryUpdate(@\"Display Settings switched off\");' \$W/fn \
   && fn 'static void DMDispScheduleUpdate(NSString \*why) {' $L && grep -q '0.6 \* NSEC_PER_SEC' \$W/fn && grep -q 'if (mine == gen) DMDispRegistryUpdate(why);' \$W/fn"
check "  ... only into the displays domain (KT's domains are never written by the layer)" \
  "! grep -n 'CFPreferencesSet\|CFPreferencesSetMultiple\|CFPreferencesSetAppValue' $L | grep -v 'CFSTR(MSBD_DISP_DOMAIN)\|, dom, kCFPreferencesCurrentUser' | grep -q . \
   && [ \$(grep -c 'CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);' $L) -ge 3 ] && ! grep -q 'MSB_DOMAIN\|CFSTR(\"com.besiktasliseba.macstatusbar\")\|CFSTR(\"com.besiktasliseba.dockmagnification\")' $L"
check "  ... info (name, route, px, points, scale, firstSeen, lastSeen) for each connected display, the ones gone seen until now, connected, the 8 limit" \
  "fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString \*why) {' $L && grep -q 'info\[@\"firstSeen\"\] = ' \$W/fn && grep -q 'info\[@\"lastSeen\"\] = @(t);' \$W/fn \
   && grep -q 'if (!\[was isEqualToArray:now\]) write\[@MSBD_DISP_CONNECTED_KEY\] = now;' \$W/fn && grep -q 'int pick = MSBDDispForgetPick(list, n, MSBD_DISP_REMEMBER_MAX);' \$W/fn \
   && grep -q 'if (\[k isKindOfClass:\[NSString class\]\] && \[k hasPrefix:prefix\]) { \[remove addObject:k\]; keys++; }' \$W/fn && grep -q 'notify_post(MSBD_DISP_NOTIFY);' \$W/fn \
   && fn 'static NSMutableDictionary \*DMDispInfoNow(NSString \*display, NSArray<UIScreen \*> \*screens) {' $L && for f in name route px points scale; do grep -q \"info\[@\\\"\$f\\\"\] = \" \$W/fn || exit 1; done"
check "  ... the 8 limit forgets the plain ones first (review of 1.8.7): each remembered display's hasOwn from its own settings, a More Space record or Mac Switcher desktops of its own" \
  "fn '__attribute__((noinline)) static void DMDispRegistryUpdate(NSString \*why) {' $L && grep -qF 'list[i].hasOwn = DMDispHasOwn(all, remembered[i], mswOwn);' \$W/fn \
   && grep -qF 'NSSet<NSString *> *mswOwn = (int)remembered.count > MSBD_DISP_REMEMBER_MAX ? DMDispMSWOwn() : nil;' \$W/fn \
   && fn 'static BOOL DMDispHasOwn(NSDictionary *all, NSString *display, NSSet<NSString *> *mswOwn) {' $L && grep -qF 'if (MSBDDispStoreHasOwn(all, display) || [mswOwn containsObject:display]) return YES;' \$W/fn \
   && grep -qF 'MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, \"disp\", MSBD_DISP_SCALE_PENDING_KEY) && all[@(flat)] != nil;' \$W/fn"
check "  ... the Mac Switcher's desktops of a display from its file (its models are not loaded while it is off), by the shared rule (MSBDDispMSWBusy)" \
  "fn 'static NSSet<NSString *> *DMDispMSWOwn(void) {' $L && grep -qF 'stringByAppendingPathComponent:@MSBD_MSW_STATE_FILE]' \$W/fn && grep -qF 'if (MSBDDispMSWBusy((int)desks.count, records)) [out addObject:k];' \$W/fn \
   && grep -qF 'st[@\"displays\"]' \$W/fn && grep -qF 'st[@\"windows\"]' \$W/fn \
   && grep -qF '#define MSBD_MSW_STATE_FILE \"Library/Preferences/com.besiktasliseba.macstatusbar.desktops.plist\"' $P \
   && grep -qF 'static NSString *DMMSWStatePath(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@MSBD_MSW_STATE_FILE]; }' ../statusbar/MacSwitcher.h"
check "  ... the route from the matched CADisplay's deviceName only (never FBS names, never the idle wireless list); the display by its desktop screen (S1: SpringBoard's window scene)" \
  "fn 'static NSMutableDictionary \*DMDispInfoNow(NSString \*display, NSArray<UIScreen \*> \*screens) {' $L && grep -q 'const char \*route = MSBDDispRouteOf(MSBDDispStr(MSBDDispGet(cad, \"deviceName\")).UTF8String);' \$W/fn \
   && grep -q 'id cfg = MSBDDispConfigOfScreen(s), cad = MSBDDispCADisplayOfConfig(cfg);' \$W/fn && grep -q 'UIScreen \*s = DMDispDesktopScreen(display, screens);' \$W/fn \
   && fn '__attribute__((noinline)) static UIScreen \*DMDispDesktopScreen(NSString \*display, NSArray<UIScreen \*> \*screens) {' $L && grep -q 'connectedScenes' \$W/fn"
check "  ... SpringBoard's own name of the display (SBSConnectedDisplayInfo, by its identifier), its call shape-checked" \
  "fn 'static void DMDispAskNames(void) {' $L && grep -q 'strcmp(method_getTypeEncoding(m) ?: \"\", \"v24@0:8@?16\") != 0' \$W/fn && grep -q 'MSBDDispGet(i, \"identifier\")' \$W/fn && grep -q 'MSBDDispGet(i, \"displayName\")' \$W/fn"
check "SpringBoard: the layer started after the prefs are read (with the Mac status bar; never with Mac Status Bar off or the stock bar); extinfo prints each screen's key" \
  "grep -q '#include \"DisplayPrefs.h\"' $S && grep -q 'if (!DMCtorSkip(\"dispprefs\")) DMDispInit();' $S \
   && [ \$(grep -n 'if (!DMCtorSkip(\"dispprefs\")) DMDispInit();' $S | cut -d: -f1) -gt \$(grep -n 'if (gStockBar) { DMSpotPublishOff();' $S | cut -d: -f1) ] \
   && grep -q 'main %d display key %@\", s, NSStringFromCGRect(s.bounds), s.scale, s == \[UIScreen mainScreen\], DMDispKeyOfScreen(s)' $S && grep -q 'DM_FEATURE_MARK(\"display-prefs\");' $L"
# (commit 4) the crash guard: a switch turned on for a display noted by its flat key; step 1b clears every display's override of a switch it sets
C=../common/CrashStep.h
check "SpringBoard: a change for one display (DMDispWrite) goes through the one writer (common/DisplayRowStore.h, Settings' page writes through it too), then the cache" \
  "fn '__attribute__((unused)) static BOOL DMDispWrite(NSString *display, const char *part, const char *key, id value, BOOL wasOn, NSString *title) {' $L \
   && grep -q 'NSString \*fk = MSBDDispStoreWrite(display, part, key, value, wasOn, title);' \$W/fn && grep -q 'DMDispReload();' \$W/fn && ! grep -q 'CFPreferencesSet' \$W/fn \
   && grep -q '#include \"../common/DisplayRowStore.h\"' $L"
check "  ... the writer: the override into the displays domain (deleted for a reset), a switch turned on noted for the guard by its flat key, the domain posted" \
  "fn 'static inline NSString *MSBDDispStoreWrite(NSString *display, const char *part, const char *key, id value, BOOL wasOn, NSString *title) {' ../common/DisplayRowStore.h \
   && grep -q 'if (!display || !MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, part, key)) return nil;' \$W/fn && grep -q 'CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);' \$W/fn \
   && grep -q 'CFPreferencesSetValue((__bridge CFStringRef)fk, (__bridge CFPropertyListRef)value, dom,' \$W/fn \
   && grep -q 'if ((isSwitch || !value) && on != wasOn) MSBDDispNoteRecent(MSBD_GUARD_RECENT, (long)time(NULL), flat, title.UTF8String, on);' \$W/fn && grep -q 'notify_post(MSBD_DISP_NOTIFY);' \$W/fn"
check "  ... its only caller in SpringBoard: the Display Settings window (commit 11, DisplaySettings.h)" "[ \$(grep -rn --include='*.x' --include='*.h' --include='*.m' 'DMDispWrite(' .. | grep -v '^\.\./statusbar/DisplayPrefs\.h:' | grep -v '^\.\./statusbar/DisplaySettings\.h:' | wc -l) = 0 ] \
   && [ \$(grep -c 'DMDispWrite(_display, r->part, r->key,' ../statusbar/DisplaySettings.h) = 2 ]"
check "the guard's step 1b: a switch it sets in KT's domain also loses every display's override of it (*/part/key), then the record line as before" \
  "fn 'static inline int MSBDGuardStepFeature(' $C && awk '/MSBDGuardSetPref\(domain, key, kMSBDBool, value\);/{a=NR} /MSBDGuardDispClear\(domain, key, value\);/{b=NR} /\"feature %s %s %d %s\\\\n\"/{c=NR} END{exit !(a && b > a && c > b)}' \$W/fn \
   && fn 'static inline int MSBDGuardDispClear(const char *domain, const char *key, int value) {' $C && grep -q 'const char \*part = MSBDDispPartOfDomain(domain);' \$W/fn \
   && grep -q 'if (!MSBDDispFlatIs(flat, part, key)) continue;' \$W/fn && grep -q 'set(k, offValue, d, \*user, \*host);' \$W/fn \
   && grep -q 'int def = 0, setOff = MSBDDispDisplayDefault(part, key, &def) && (def != 0) != (value != 0);' \$W/fn && grep -q 'const void \*offValue = setOff ? (value ? \*yes : \*no) : NULL;' \$W/fn && grep -q 'notify_post(MSBD_DISP_NOTIFY);' \$W/fn \
   && grep -q 'const void \*d = mk(NULL, MSBD_DISP_DOMAIN, 0x08000100);' \$W/fn && grep -q '#include \"DisplayPrefs.h\"' $C"
# Made to fail: the rule with one thing broken (the iPad's screen resolving an override, the display default ignored, an override of the wrong
# type taken, a 128-character flat key let through, a placeholder taken as an id, the key left in lower case; commit 3: a connected or the newest
# display forgotten, a route from any name; commit 4: the guard's note keeping a switch's old line or stale lines, a title cut inside a
# character; review of 1.8.7: a display with something of the user's own forgotten before the plain ones, or never) must fail the C test.
mutant() {
  local M="$W/m-$1"; mkdir -p "$M/common" "$M/tools"; cp test-displayprefs.c "$M/tools/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    $P "$M/common/DisplayPrefs.h" "$2" "$3" || return 1
  clang -O2 -Wall -Wno-unused-function -o "$M/t" "$M/tools/test-displayprefs.c" || return 1
  ! RECENT="$M/recent.txt" "$M/t" > "$M/out"
}
check "made to fail: the iPad's screen resolving an override" "mutant main '    if (isMain) return kMSBDDispFromIPad;' '    (void)isMain;'"
check "made to fail: the display default ignored (the TV's Trash would follow the iPad's off)" "mutant default '    return rowHasDisplayDefault ? kMSBDDispFromDefault : kMSBDDispFromIPad;
}' '    return kMSBDDispFromIPad;
}'"
check "made to fail: an override of the wrong type taken" "mutant type 'if (hasOverride && typeOK) return kMSBDDispFromOverride;' 'if (hasOverride) return kMSBDDispFromOverride;'"
check "made to fail: a number out of range taken (clamping or no range check)" "mutant range '(!hasRange || (num >= lo && num <= hi))' '1'"
check "made to fail: a 128-character flat key let through (the guard's sscanf would cut it)" "mutant length 'if (len > MSBD_DISP_FLAT_MAX || len + 1 > n) return 0;' 'if (len > MSBD_DISP_FLAT_MAX + 1 || len + 1 > n) return 0;'"
check "made to fail: a placeholder word taken as an id" "mutant placeholder 'if (strcasecmp(id, words[w]) == 0) return false;' '(void)words[w];'"
check "made to fail: the key left in the case it was read (two keys for one display)" "mutant case \"out[k++] = (*c >= 'a' && *c <= 'z') ? (char)(*c - 'a' + 'A') : *c;\" 'out[k++] = *c;'"
check "made to fail: a connected display forgotten (the 9th forgets the TV in use)" "mutant connected '        if (list[i].connected || !list[i].key) continue;' '        if (!list[i].key) continue;'"
check "made to fail: the display seen most recently forgotten instead" "mutant newest 'if (pick < 0 || list[i].lastSeen < list[pick].lastSeen) pick = i;' 'if (pick < 0 || list[i].lastSeen > list[pick].lastSeen) pick = i;'"
check "made to fail: the 9th by lastSeen alone (the customized TV forgotten before 7 plain copies of it)" "mutant ownfirst '            if (pass == 0 && list[i].hasOwn) continue;   // (the plain ones first)' '            (void)pass;'"
check "made to fail: a display with its own settings never forgotten (more than 8 kept when every one has some)" "mutant ownnever 'for (int pass = 0; pass < 2 && pick < 0; pass++)' 'for (int pass = 0; pass < 1 && pick < 0; pass++)'"
check "made to fail: a route read from any name with wireless in it" "mutant route 'if (strncmp(deviceName, \"wireless\", 8) == 0) return \"encoded\";' 'if (strstr(deviceName, \"ir\")) return \"encoded\";'"
check "made to fail: the guard's note keeps a switch's old line (turned on twice, two lines)" "mutant twice '(strcmp(domain, MSBD_DISP_DOMAIN) == 0 && strcmp(key, flat) == 0)' '0'"
check "made to fail: the guard's note keeps lines older than 10 min" "mutant stale 'if (now - t >= 600 ||' 'if (now - t >= 600000 ||'"
check "made to fail: a title cut inside a character" "mutant utf8 'while (n > 0 && ((unsigned char)src[n] & 0xC0) == 0x80) n--;' '(void)0;'"
check "made to fail: */part/key matching another part's key (step 1b would clear what did not crash)" "mutant flatis 'MSBDDispFlatSplit(flat, NULL, 0, p, sizeof p, k, sizeof k) && strcmp(p, part) == 0 && strcmp(k, key) == 0' 'MSBDDispFlatSplit(flat, NULL, 0, p, sizeof p, k, sizeof k) && strcmp(k, key) == 0'"
[ $fails = 0 ] && echo "test-displayprefs: wiring checks pass" || { echo "test-displayprefs: wiring checks FAILED"; exit 1; }
