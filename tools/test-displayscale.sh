#!/bin/bash
# Mac test of More Space (1.8.7 commit 13; plans/design-1.8.7-displays.md sections 4 and 8): the rules in plain C (common/DisplayScale.h,
# test-displayscale.c), then the sites -- only listed scales are ever made, the registry keeps what was read, the row and the menu's choices only with a
# choice, a change kept or reverted, the record before a change and the start's revert, the overscan tip, the crash map -- then made-to-fail copies.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
clang -O2 -Wall -Wno-unused-function -o "$W/tds" test-displayscale.c
"$W/tds"
fails=0
check() { if (eval "$2"); then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fn() { awk -v head="$1" 'index($0, head) == 1 {f=1} f {print} f && /^}/ {exit}' $2 > "$W/fn"; }
C=../common/DisplayScale.h; MS=../statusbar/MoreSpace.h; ST=../common/DisplayRowStore.h; D=../statusbar/DisplaySettings.h; L=../statusbar/DisplayPrefs.h
M=../statusbar/macstatusbarprefs/MSBRootListController.m; S=../statusbar/StatusBar.x; R=../common/DisplayRows.h
check "DisplayScale.h is plain C: no ObjC, no CoreFoundation" "! grep -E '^#(import|include) <(UIKit|Foundation|CoreFoundation)' $C && ! grep -q '@interface\|@\"\|NSString' $C"
check "only a listed scale is ever made (SpringBoardServices asserts on any other: S2), its initializer shape-checked, in @try" \
  "fn 'static id DMMoreSpaceMake(unsigned long long mask, int scale, long long overscan) {' $MS && grep -q 'if (!MSBDDispScaleIsListed(mask, scale)) return nil;' \$W/fn \
   && grep -q 'strcmp(method_getTypeEncoding(im) ?: \"\", \"@32@0:8Q16q24\") != 0' \$W/fn && grep -q '@try' \$W/fn \
   && [ \$(grep -c 'initWithScale:overscanCompensation:' $MS) = 1 ] && ! grep -rn 'initWithScale:overscanCompensation:' ../statusbar/*.h ../statusbar/StatusBar.x | grep -v 'MoreSpace.h\|DisplaySpike.h' | grep -q ."
check "  ... names made only for a choice (one scale listed -- the A12Z's and the iPad 2's TVs -- makes none: only read)" \
  "fn 'static void DMMoreSpaceRead(NSString *why) {' $MS && grep -q 'for (int k = 0; k < n && n >= 2; k++) {' \$W/fn && grep -q 'DMMoreSpaceMake(mask, listed\[k\], ov)' \$W/fn"
check "  ... a set only when listed and not in use (MSBDDispScaleCanSet), through Apple's setter of the read shape" \
  "fn 'static void DMMoreSpaceApply(NSString *display, int want, BOOL record, DMMoreSpaceThen then) {' $MS && grep -q 'id settings = MSBDDispScaleCanSet(mask, cur, want) ? DMMoreSpaceMake(mask, want, ov) : nil;' \$W/fn \
   && grep -q '\"v48@0:8@16@24Q32@?40\"' \$W/fn"
check "the record before a change ({old, new, at}), dropped after 60 s; a change asked is kept or reverted (15 s, reverting by itself)" \
  "fn 'static void DMMoreSpaceApply(NSString *display, int want, BOOL record, DMMoreSpaceThen then) {' $MS && grep -q 'DMMoreSpacePending(display, @{ @\"old\": @(cur), @\"new\": @(want), @\"at\": @(at) });' \$W/fn \
   && grep -q 'MSBDDispScaleDropNow((long)time(NULL), at)' \$W/fn \
   && awk '/DMMoreSpacePending\(display, @\{/{a=NR} /objc_msgSend\)\(client, set, settings, ident, 0ULL, answered\)/{b=NR} END{exit !(a && b > a)}' \$W/fn \
   && fn '__attribute__((noinline)) static void DMMoreSpaceSet(NSString *display, int want) {' $MS && grep -q 'if (took) DMMoreSpaceAsk(display, was); else DMMoreSpacePending(display, nil);' \$W/fn \
   && fn 'static void DMMoreSpaceAsk(NSString *display, int old) {' $MS && grep -q 'if (MSBDDispScaleRevertsNow(answered, now, asked)) { finish(NO); return; }' \$W/fn && grep -q 'DMMoreSpaceApply(display, old, NO, ^(BOOL took, BOOL listed, unsigned long long mask, int was) {' \$W/fn"
check "  ... at the start: a change never kept, within 2 min, set back; an older record dropped" \
  "fn 'static void DMMoreSpaceInit(void) {' $MS && grep -q 'int what = MSBDDispScaleAtStart(rec != nil, now, \[rec\[@\"at\"\] longValue\]);' \$W/fn && grep -q 'gDMMoreSpaceStartReverts\[display\] = rec;' \$W/fn \
   && fn 'static void DMMoreSpaceStartRevert(NSString *why) {' $MS && grep -q 'DMMoreSpaceApply(display, old, NO,' \$W/fn \
   && grep -q 'if (!DMCtorSkip(\"morespace\")) DMMoreSpaceInit();' $S"
check "review: one client of Apple's service per call, held by its own answer (no shared client another answer could let go)" \
  "! grep -q 'gDMMoreSpaceClient' $MS && fn 'static void DMMoreSpaceInfos(void (^done)(NSArray *infos, id client)) {' $MS && grep -q 'id client = nil;' \$W/fn \
   && grep -q 'dispatch_async(dispatch_get_main_queue(), ^{ done(list, client); });' \$W/fn \
   && fn 'static void DMMoreSpaceApply(NSString *display, int want, BOOL record, DMMoreSpaceThen then) {' $MS && grep -q 'Method m = client ? class_getInstanceMethod(object_getClass(client), set) : NULL;' \$W/fn && grep -q '(void)keep;' \$W/fn"
check "  ... the set's completion takes no parameters (their shape never read) and the outcome is read back from the scale in use" \
  "fn 'static void DMMoreSpaceApply(NSString *display, int want, BOOL record, DMMoreSpaceThen then) {' $MS && grep -q 'void (^answered)(void) = ^{' \$W/fn && grep -q 'DMMoreSpaceReadBack(display, want, cur, 0, then);' \$W/fn \
   && ! grep -q '\^(id err)' $MS ../statusbar/DisplaySpike.h && ! grep -q 'err == nil' $MS \
   && fn 'static void DMMoreSpaceReadBack(NSString *display, int want, int was, int tries, DMMoreSpaceThen then) {' $MS && grep -q 'BOOL took = MSBDDispScaleSetTook(info != nil, now, want);' \$W/fn \
   && grep -q 'dispscale_shape' ../statusbar/DisplaySpike.h && grep -q '_protocol_getMethodTypeEncoding' ../statusbar/DisplaySpike.h"
check "  ... the start's revert keeps its record until taken (or nothing to take back, or 2 min over), tried again when a display connects" \
  "fn 'static void DMMoreSpaceStartRevert(NSString *why) {' $MS && grep -q 'if (MSBDDispScaleStartRevertDrop(took, listed, mask, was, old, (long)time(NULL), at)) {' \$W/fn \
   && [ \$(grep -c 'DMMoreSpaceDropRecord(display, at)' \$W/fn) = 2 ] && ! grep -q 'DMMoreSpacePending(display, nil)' \$W/fn \
   && fn 'static void DMMoreSpaceInit(void) {' $MS && grep -q 'DMMoreSpaceStartRevert(@\"a display connected\"); DMMoreSpaceRead(@\"a display connected\");' \$W/fn \
   && grep -q 'DMMoreSpaceStartRevert(@\"SpringBoard started\");' \$W/fn && grep -q 'DMMoreSpaceStartRevert(@\"2 min since the change\");' \$W/fn"
check "  ... the keep-or-revert question closes only its own card, and shows again if another menu took its place" \
  "fn 'static void DMMoreSpaceAsk(NSString *display, int old) {' $MS && grep -q 'if (q && gOverlay == q) DMCloseOverlay();' \$W/fn && [ \$(grep -c 'DMCloseOverlay()' \$W/fn) = 1 ] \
   && grep -q 'if (!answered && !gDMMoreSpaceQuestion.superview && !gOverlay) {' \$W/fn && grep -q 'gDMMoreSpaceQuestion = o; wc = count;' \$W/fn"
check "its own switch (displayScale) and Display Settings' gate the reads, the row and the sets; Settings asks by a request key SpringBoard takes" \
  "fn 'static inline BOOL MSBDDispStoreScaleOn(NSDictionary *all) {' $ST && grep -q 'MSBDDispStoreSwitchOn(all, MSBD_DISP_SCALE_SWITCH_KEY)' \$W/fn && grep -q '#define MSBD_DISP_SCALE_SWITCH_KEY \"displayScale\"' $ST && grep -q 'MSBDDispStoreLayerOn(all)' \$W/fn \
   && grep -q 'static BOOL DMMoreSpaceOn(void) { return MSBDDispStoreScaleOn(MSBDDispStoreAll()); }' $MS && grep -q 'if (!DMMoreSpaceOn()) return;' $MS \
   && grep -q 'MSBDDispStoreWrite(_display, \"disp\", MSBD_DISP_SCALE_REQUEST_KEY, value, NO, nil);' $M && fn 'static void DMMoreSpaceRequests(void) {' $MS && grep -q 'MSBD_DISP_SCALE_REQUEST_KEY, nil, NO, nil);' \$W/fn"
check "the registry keeps what was read across its updates (scales, in use, Apple's names, overscan)" \
  "grep -q 'for (NSString \*f in @\[@\"scales\", @\"scaleNow\", @\"scaleNames\", @\"overscan\"\]) if (old\[f\]) info\[f\] = old\[f\];' $L"
check "the Resolution row only with a choice (the window, the page and the menu by the store's choices: empty with one scale)" \
  "grep -q '\"RESOLUTION\", \"Resolution\",' $R && grep -q 'kMSBDRowNeedsScales, 16' $R \
   && fn 'static inline NSArray<NSArray *> *MSBDDispStoreScaleChoices(NSDictionary *all, NSDictionary *info, int *now) {' $ST && grep -q 'if (!MSBDDispScaleRowWanted(mask) || !MSBDDispStoreScaleOn(all)) return @\[\];' \$W/fn \
   && grep -q 'c.scales = (int)MSBDDispStoreScaleChoices(all, MSBDDispStoreInfo(all, display), NULL).count;' $D && grep -q 'c.scales = (int)MSBDDispStoreScaleChoices(all, info, NULL).count;' $M \
   && grep -q 'NSArray<NSArray \*> \*scales = extended ? MSBDDispStoreScaleChoices(MSBDDispStoreAll(), info, &scaleNow) : @\[\];' $D"
check "the overscan tip where iPadOS reads .None, in the window and on the page" \
  "grep -q 'if (ctx.extended && MSBDDispStoreOverscanTip(info)) {' $D && grep -q 'if (ctx.extended && MSBDDispStoreOverscanTip(info)) topText = ' $M && grep -q 'MSBDDispOverscanTip(\[o UTF8String\])' $ST"
check "crash map: More Space's file and functions are its own switch's (displayScale)" \
  "grep -q '^sym MacStatusBarCore ^_\*DMMoreSpace\[A-Z\] displayScale' crashmap-rules.txt && grep -q '^file MacStatusBarCore ^(MoreSpace|DisplayScale)\\\\.h\$ displayScale' crashmap-rules.txt \
   && ! grep -E '^(static|__attribute__).*\b(DM[A-Za-z]+)\(' $MS | grep -v 'DMMoreSpace[A-Z]' | grep -q ."
mutant() {
  local M2="$W/m-$1"; mkdir -p "$M2/common" "$M2/tools"; cp test-displayscale.c "$M2/tools/"
  python3 -I -c 'import sys; s=open(sys.argv[1]).read(); assert s.count(sys.argv[3])==1, "mutant site not found"; open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4]))' \
    $C "$M2/common/DisplayScale.h" "$2" "$3" || return 1
  clang -O2 -Wall -Wno-unused-function -o "$M2/t" "$M2/tools/test-displayscale.c" 2>/dev/null || return 1
  ! bash -c '"$0" > "$1" 2>&1' "$M2/t" "$M2/out" 2>/dev/null   # (a copy may crash: that is a failure too)
}
check "made to fail: scale 0 listed (SpringBoardServices' assertion)" "mutant zero 'for (int v = 1; v <= MSBD_DISP_SCALE_MAX; v++)' 'for (int v = 0; v <= MSBD_DISP_SCALE_MAX; v++)'"
check "made to fail: a row with one scale" "mutant one 'return MSBDDispScaleListed(mask, NULL, 0) >= 2;' 'return MSBDDispScaleListed(mask, NULL, 0) >= 1;'"
check "made to fail: an unlisted scale set" "mutant unlisted 'return MSBDDispScaleIsListed(mask, want) && want != current;' 'return want != current;'"
check "made to fail: the start reverts a change of any age" "mutant age 'return (age >= 0 && age <= MSBD_DISP_SCALE_CRASH_WINDOW) ? kMSBDDispScaleStartRevert : kMSBDDispScaleStartDrop;' 'return kMSBDDispScaleStartRevert;'"
check "made to fail: no revert without an answer" "mutant noanswer 'return !answered && now - asked >= MSBD_DISP_SCALE_KEEP_SECONDS;' 'return 0;'"
check "made to fail: .Standard not named Default" "mutant standard 'if (strcmp(appleName, \"Standard\") == 0) return \"Default\";' ''"
check "made to fail: the overscan tip with iPadOS's own compensation" "mutant overscan 'return overscanName && strcmp(overscanName, \"None\") == 0;' 'return overscanName != NULL;'"
check "made to fail: a set counted as taken whatever the scale read back" "mutant took 'static inline bool MSBDDispScaleSetTook(int listed, int now, int want) { return !listed || now == want; }' 'static inline bool MSBDDispScaleSetTook(int listed, int now, int want) { return 1; }'"
check "made to fail: the start's record dropped while the display is not listed yet" "mutant notlisted '    return took || (listed && (!MSBDDispScaleIsListed(mask, old) || current == old));' '    return took || !listed || !MSBDDispScaleIsListed(mask, old) || current == old;'"
check "made to fail: the start's record kept past 2 min" "mutant window '    return MSBDDispScaleRevertDone(took, listed, mask, current, old) || MSBDDispScaleAtStart(1, now, at) != kMSBDDispScaleStartRevert;' '    return MSBDDispScaleRevertDone(took, listed, mask, current, old);'"
[ $fails = 0 ] && echo "test-displayscale: wiring checks pass" || { echo "test-displayscale: wiring checks FAILED"; exit 1; }
