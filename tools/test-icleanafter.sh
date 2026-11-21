#!/bin/bash
# test-icleanafter.sh: Clean and Respring's result after the respring (1.8.8.1). Finder's iCleaner panel resprang as soon as iCleaner answered, so
# what Clean and Respring freed was never seen (KT, 21 Nov). Now the answer is kept in our own preferences just before our respring is asked, taken
# by the SpringBoard that respring starts and shown once in the panel, after the unlock (common/ICleaner.h, statusbar/ICleanerPanel.h).
# 1. test-icleanafter.m: common/ICleaner.h's rules as they are, and the glue cut out of statusbar/ICleanerPanel.h (from gICleanAfterLine to the end
#    of DMFinderICleanAfterTick, without the five functions that reach outside: the preferences' read and write, the two clocks, the crash look)
#    over simulated SpringBoards; built at -Os (as a release build) and -O0 DEBUG, no warnings.
# 2. site checks: the wiring in StatusBar.x and the panel, what the cut leaves out, and the crash map's classes of the code it runs.
# 3. made-to-fail copies: each takes one part of the change out and must fail.
# IA_ROOT: another tree (e.g. the code before the change); then no made-to-fail copies.
cd "$(dirname "$0")" || exit 1
R0=$(cd "${IA_ROOT:-..}" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# The crash map's classes of the code this runs, by make-crashmap.py's own rules code (as a release build's map makes them): every name before the
# bar is Finder's, every name after it the status bar's (the image's target), as before.
cat > "$W/ia-classify.py" <<'EOF'
import sys
src = open('make-crashmap.py').read().rstrip()
assert src.endswith('main()'); g = {'__name__': 'ia'}; exec(compile(src[:-len('main()')], 'make-crashmap.py', 'exec'), g)
targets, images, rules, titles = g['load_rules'](sys.argv[1]); hits = [0] * len(rules); im = images['MacStatusBarCore']['target']
c = lambda name, fname: g['classify']('MacStatusBarCore', name, fname, '', rules, im, hits)
finder = [('_DMFinderICleanAfterTick', 'ICleanerPanel.h'), ('___DMFinderICleanRespring_block_invoke_2', 'ICleanerPanel.h'), ('_DMFinderICleanAfterBlocker', 'StatusBar.x'),
          ('_DMICleanShowPanel', 'ICleanerPanel.h'), ('___DMICleanShowPanel_block_invoke_3', 'ICleanerPanel.h'), ('_DMICleanRun', 'ICleanerPanel.h'), ('_DMICleanRun.cold.1', ''),
          ('_MSBDICleanParseAnswer', 'ICleaner.h'), ('_MSBDICleanResultText', 'ICleaner.h')]
bar = [('_DMRespringCheckedOr', 'StatusBar.x'), ('___DMRespringWarnThenOr_block_invoke_2', 'StatusBar.x'), ('_DMRespring', 'StatusBar.x'), ('_DMTickBody', 'StatusBar.x')]
print(' '.join(c(n, f) for n, f in finder) + ' | ' + ' '.join(c(n, f) for n, f in bar))
EOF
fn() { awk -v h="$2" 'index($0, h) == 1 {f=1} f {print} f && /^[}]/ {exit}' "$1"; }   # one function of a file, from its first line
cut_glue() {   # $1 tree: the glue, without the five functions the test stands in for
  awk '/^static NSString \*gICleanAfterLine = nil;/ {f=1}
       !f {next}
       skip { if (/^[}]/) skip = 0; next }
       /^static (id DMFinderICleanStoreRead|void DMFinderICleanStoreWrite|BOOL DMFinderICleanCrashSince)\(/ { skip = 1; out++; next }
       /^static double DMFinderIClean(Now|Started)\(void\) \{.*\}/ { out++; next }
       { print }
       /^__attribute__\(\(noinline\)\) static void DMFinderICleanAfterTick\(void\) \{/ {t=1}
       t && /^[}]/ { exit }
       END { if (out != 5) print "#error the five stood-in functions were not all found (" out ")" }' "$1/statusbar/ICleanerPanel.h"
}

compiled() {   # $1 tree, $2 quiet: the scenarios built on its code and run; 0 when every check passes
  local R=$1 d=$W/c$RANDOM$RANDOM fl r; mkdir -p "$d"
  cut_glue "$R" > "$d/ia-glue.inc"
  if ! grep -q '^__attribute__((noinline)) static void DMFinderICleanAfterTick(void) {' "$d/ia-glue.inc" || ! grep -q '^static NSString \*gICleanAfterLine = nil;' "$d/ia-glue.inc"; then
    [ -n "$2" ] || echo "(the glue was not found in $R/statusbar/ICleanerPanel.h)"; return 1
  fi
  for fl in rel dbg; do
    if ! clang -fobjc-arc -Wall -Wno-unused-function -Werror=implicit-function-declaration $([ $fl = rel ] && echo -Os || echo -O0 -DDEBUG=1) -I"$d" -I"$R" \
         -framework Foundation -framework CoreFoundation -o "$d/t-$fl" test-icleanafter.m > "$d/cc-$fl.txt" 2>&1; then
      [ -n "$2" ] || { echo "(test-icleanafter.m does not build against $R ($fl):)"; grep -m 4 'error' "$d/cc-$fl.txt"; }; return 1
    fi
    if [ -s "$d/cc-$fl.txt" ]; then [ -n "$2" ] || { echo "(warnings ($fl):)"; cat "$d/cc-$fl.txt"; }; return 1; fi
    "$d/t-$fl" > "$d/out-$fl.txt" 2>&1; r=$?
    [ -n "$2" ] || { echo "[$fl]"; cat "$d/out-$fl.txt"; }
    [ $r = 0 ] || return 1
  done
  return 0
}

sites() {   # $1 tree, $2 quiet: the number of failed checks
  local R=$1 q=$2 n=0 S=$1/statusbar/StatusBar.x P=$1/statusbar/ICleanerPanel.h C=$1/common/ICleaner.h M=$1/tools/crashmap-rules.txt
  c() { if (eval "$2") >/dev/null 2>&1; then [ -n "$q" ] || echo "PASS  $1"; else [ -n "$q" ] || echo "FAIL  $1"; n=$((n + 1)); fi; }
  c "Clean and Respring goes through DMFinderICleanRespring (the result kept), no longer straight to the respring" \
    "fn $P 'static void DMICleanRun(BOOL thenRespring) {' > \$W/run && grep -qF 'if (thenRespring) { DMCloseOverlay(); DMFinderICleanRespring(line); return; }' \$W/run && ! grep -q 'DMRespringChecked' \$W/run"
  c "  ... our respring with its VPN warning: kept just before it is asked, held when it is not done" \
    "fn $P '__attribute__((noinline)) static void DMFinderICleanRespring(NSString *line) {' | grep -qF 'DMRespringCheckedOr(^{ DMFinderICleanKeep(l); }, ^{ DMFinderICleanHold(l); });'"
  c "our respring runs \`first\` before it is asked; Respring everywhere else is the same call as before" \
    "fn $S 'static void DMRespringCheckedOr(dispatch_block_t first, dispatch_block_t otherwise) {' | grep -qF 'DMRespringWarnThenOr(^{ if (first) first(); gOwnRespringAt = CACurrentMediaTime(); DMRespring(); }, otherwise);' \
     && grep -qxF 'static void DMRespringChecked(void) { DMRespringCheckedOr(nil, nil); }' $S && grep -qxF 'static void DMRespringWarnThen(dispatch_block_t go) { DMRespringWarnThenOr(go, nil); }' $S"
  c "the VPN warning's Cancel, VPN Settings, its put-away by a lock and a warning already up run \`otherwise\`; only Respring Anyway and no warning run \`go\`" \
    "fn $S 'static void DMRespringWarnThenOr(dispatch_block_t go, dispatch_block_t otherwise) {' > \$W/w && [ \$(grep -o 'if (otherwise) otherwise();' \$W/w | wc -l) = 4 ] \
     && grep -qF 'DMLog(@\"[vpnwarn] cancelled\"); if (otherwise) otherwise(); });' \$W/w && grep -qF 'if (!a) { if (!gVPNWarnWindow) go(); else if (otherwise) otherwise(); return; }' \$W/w \
     && grep -qF 'MSBDAlertCloseOnLock(w, ^{ if (gVPNWarnWindow == w) gVPNWarnWindow = nil; if (otherwise) otherwise(); });' \$W/w && [ \$(grep -o 'go()' \$W/w | wc -l) = 2 ]"
  c "the record: one key in our own preferences (kMSBDEjectDomain), written synchronized (it must be there for the next SpringBoard), read fresh" \
    "grep -qF '#define kMSBDICleanAfterKey \"icleanAfterRespring\"' $C && fn $P 'static void DMFinderICleanStoreWrite(NSDictionary *rec) {' > \$W/sw \
     && grep -qF 'CFStringRef dom = CFSTR(kMSBDEjectDomain);' \$W/sw && grep -qF 'CFPreferencesSetValue(CFSTR(kMSBDICleanAfterKey), (__bridge CFPropertyListRef)rec, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \$W/sw \
     && grep -qF 'CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \$W/sw && fn $P 'static id DMFinderICleanStoreRead(void) {' > \$W/sr \
     && grep -qF 'CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' \$W/sr && grep -qF 'CFPreferencesCopyValue(CFSTR(kMSBDICleanAfterKey), dom,' \$W/sr \
     && [ \$(grep -c 'kMSBDICleanAfterKey' $P) = 2 ]"
  c "the stood-in clocks and crash look are what the test takes them for: now and the start (from the process's age) in seconds since 1970; the crash guard's report folder; the test crash only in debug builds" \
    "grep -qxF 'static double DMFinderICleanNow(void) { return [[NSDate date] timeIntervalSince1970]; }' $P \
     && grep -qF 'static double DMFinderICleanStarted(void) { return DMFinderICleanNow() - DMProcessAge(); }' $P \
     && fn $P 'static BOOL DMFinderICleanCrashSince(double since) {' > \$W/cs && grep -qF 'MSBDICleanCrashSince(MSBD_GUARD_REPORTS, since, name, sizeof(name))' \$W/cs \
     && grep -qF 'if (DMTestFlag(\"/tmp/msb-iclean-fakecrash\"))' \$W/cs && grep -q '^#define MSBD_GUARD_REPORTS \"/var/mobile/Library/Logs/CrashReporter\"' $R/common/CrashGuard.h"
  c "the tick runs it (after the notices); nothing of it from a constructor" \
    "fn $S 'static void DMTickBody(void) {' | grep -A1 -F 'DMCheckAerialNote();' | grep -qF 'DMFinderICleanAfterTick();' \
     && ! awk '/^%ctor \\{/,/^}/' $S | grep -q 'DMFinderIClean'"
  c "it waits for the unlock and for what would close its panel at once (the tick's closes), with the notes' waits" \
    "fn $S 'static NSString *DMFinderICleanAfterBlocker(void) {' > \$W/b && grep -qF 'if (DMProcessAge() < 10.0) return @\"SpringBoard starting\";' \$W/b \
     && grep -qF 'if (!DMScreenOnAndUnlocked() || DMCoverSheetShown() || MSBDAlertLockedOrCovered()) return @\"locked or covered\";' \$W/b \
     && grep -qF 'if (DMSwitcherVisible() || DMControlCenterActive() || DMSpotlightShown())' \$W/b && grep -qF 'if (gOverlay || (gMenuWindow && !gMenuWindow.hidden) || DMExtMenuVisible())' \$W/b \
     && grep -qF 'if (gWelcomeWindow || gEngineWarningWindow || gExtNoticeWindow || gRestoringWindows || MSBDAlertBusy(nil))' \$W/b && grep -qF 'if (!DMMenuHost())' \$W/b"
  c "shown in the panel (DMMenuHost: the iPad's own screen), with the release build's feature mark" \
    "fn $P '__attribute__((noinline)) static void DMFinderICleanAfterTick(void) {' > \$W/t && grep -qF 'DM_FEATURE_MARK(\"finder-icleaner-after-respring\");' \$W/t \
     && grep -qF 'DMICleanShowPanel(2, MSBDICleanResultText(freed, deleted), respring && !resprung);' \$W/t && fn $P 'static void DMICleanShowPanel(int state, NSString *text, BOOL offerRespring) {' | grep -qF 'UIView *host = DMMenuHost();'"
  c "Finder's in the crash map: the five out of line (a release build keeps their own ranges), named DMFinderIClean..., their blocks too; the panel it opens at a SpringBoard start (DMIClean...) and the answer's words (MSBDIClean...) Finder's too; the respring and the tick the bar's, as before" \
    "[ \$(grep -c '^__attribute__((noinline)) static void DMFinderIClean\\(Keep\\|Hold\\|Respring\\|Look\\|AfterTick\\)(.*) {\$' $P) = 5 ] \
     && grep -qxF 'sym MacStatusBarCore ^_*(DM(Finder)?IClean|MSBDIClean)[A-Z] finder' $M && grep -q '^target finder pref com.besiktasliseba.macstatusbar finderEnabled 0 1 ' $M \
     && [ \"\$(python3 -I \$W/ia-classify.py $M)\" = 'finder finder finder finder finder finder finder finder finder | stock stock stock stock' ]"
  c "the test trigger (icleanafter_respring) is in debug builds only" \
    "awk '/icleanafter_respring/ {print d; exit} /^#if DEBUG/ {d=1} /^#endif/ {d=0}' $S | grep -qx 1"
  return $n
}

rc=0
if compiled "$R0"; then echo "PASS  the rules and the scenarios (test-icleanafter.m against $R0)"; else echo "FAIL  the rules and the scenarios (test-icleanafter.m against $R0)"; rc=1; fi
sites "$R0" || rc=1
if [ -z "$IA_ROOT" ]; then
  mtf() {   # $1 name, $2 file (relative to the tree), $3 perl expression (the whole file at once): one part of the change taken out
    local m=$W/m$RANDOM$RANDOM
    mkdir -p "$m/common" "$m/statusbar" "$m/tools"
    cp ../common/ICleaner.h ../common/DriveEject.h ../common/CrashGuard.h "$m/common/"; cp ../statusbar/ICleanerPanel.h ../statusbar/StatusBar.x "$m/statusbar/"; cp crashmap-rules.txt "$m/tools/"
    perl -0pi -e "$3" "$m/$2"
    if cmp -s "$m/$2" "../$2"; then echo "FAIL  made-to-fail ($1): the copy did not change"; rc=1; return; fi
    local sc=0 sf; compiled "$m" quiet || sc=1; sites "$m" quiet; sf=$?
    if [ $sc = 0 ] && [ $sf = 0 ]; then echo "FAIL  made-to-fail ($1): still passes"; rc=1
    else echo "PASS  made-to-fail ($1): caught by $([ $sc = 1 ] && echo "the scenarios")$([ $sc = 1 ] && [ $sf != 0 ] && echo " and ")$([ $sf != 0 ] && echo "$sf site check(s)")"; fi
  }
  mtf "the record left in our preferences when taken (seen again by the next SpringBoard)" statusbar/ICleanerPanel.h 's/\n    DMFinderICleanStoreWrite\(nil\);   \/\/ \(taken or dropped[^\n]*//'
  mtf "the result not let go as it is shown (shown twice)" statusbar/ICleanerPanel.h 's/\n    gICleanAfterLine = nil;   \/\/ \(let go as it is shown[^\n]*//'
  mtf "no wait for the unlock (shown over the Lock Screen)" statusbar/ICleanerPanel.h 's/NSString \*blocker = DMFinderICleanAfterBlocker\(\);/NSString *blocker = nil;/'
  mtf "kept for ever (no 10 minutes)" common/ICleaner.h 's/kMSBDICleanAfterKeep = 600\.0;/kMSBDICleanAfterKeep = 1e9;/'
  mtf "any later start takes it (no start window)" common/ICleaner.h 's/kMSBDICleanAfterStart = 90\.0;/kMSBDICleanAfterStart = 1e9;/'
  mtf "no look at the crash reports" statusbar/ICleanerPanel.h 's/if \(resprung && DMFinderICleanCrashSince\(gICleanAfterAt\)\)/if (0)/'
  mtf "the asking SpringBoard shows it at once (before its respring)" common/ICleaner.h 's/\n        if \(age < kMSBDICleanAfterLate\) return kMSBDICleanAfterWait;//'
  mtf "Respring offered right after the respring" statusbar/ICleanerPanel.h 's/respring && !resprung\);/respring);/'
  mtf "Finder off still runs it" statusbar/ICleanerPanel.h 's/    if \(!gFinderOn\) \{   \/\/ \(Finder.s own/    if (0) {   \/\/ (Finder own/'
  mtf "Clean and Respring straight to the respring again" statusbar/ICleanerPanel.h 's/DMCloseOverlay\(\); DMFinderICleanRespring\(line\); return; \}/DMCloseOverlay(); DMRespringChecked(); return; }/'
  mtf "the result kept after the respring is asked" statusbar/StatusBar.x 's/\^\{ if \(first\) first\(\); gOwnRespringAt = CACurrentMediaTime\(\); DMRespring\(\); \}/^{ gOwnRespringAt = CACurrentMediaTime(); DMRespring(); if (first) first(); }/'
  mtf "the VPN warning's Cancel loses it" statusbar/StatusBar.x 's/DMLog\(\@"\[vpnwarn\] cancelled"\); if \(otherwise\) otherwise\(\); \}\);/DMLog(\@"[vpnwarn] cancelled"); });/'
  mtf "not in the tick" statusbar/StatusBar.x 's/\n    DMFinderICleanAfterTick\(\);[^\n]*//'
  mtf "the panel and the answer left to the status bar's target in the crash map" tools/crashmap-rules.txt 's/\Q^_*(DM(Finder)?IClean|MSBDIClean)[A-Z] finder\E/^_*DMFinderIClean[A-Z] finder/'
  mtf "the record in another place" statusbar/ICleanerPanel.h 's/CFPreferencesSetValue\(CFSTR\(kMSBDICleanAfterKey\), \(__bridge CFPropertyListRef\)rec, dom,/CFPreferencesSetValue(CFSTR(kMSBDICleanAfterKey), (__bridge CFPropertyListRef)rec, CFSTR("com.example.other"),/'
fi
[ $rc = 0 ] && echo "test-icleanafter: all pass" || echo "test-icleanafter: FAILED"
exit $rc
