#!/bin/bash
# test-pointeraside.sh: the Mac pointer stands aside only for another pointer that really shows, and says what it is doing (1.8.8.2, GitHub #17: a
# user's Mac pointer did not come on, the round pointer showed, Settings still said Mac). Until 1.8.8.1.1 MacPointer (pointeruid) stood down for the
# whole run as soon as any other jailbreak library had a method on pointeruid's pointer classes, also a hook that draws nothing, and nothing told the
# user. Now that is only the reason to look (statusbar/macpointer/MPAside.h), and MacPointer, our loader there and SpringBoard say the state that
# Settings > Pointer and Report a Problem put in words (common/MacPointerStatus.h).
# 1. test-pointeraside.m on the Mac (Mac Catalyst), against the real headers: the words, the look on fake pointer views with another library of its
#    own under a "/var/jb/" path (test-pointeraside-other.m), the hook scan, the parts of iPadOS's pointer; release and DEBUG builds.
# 2. site checks: MacPointer.x, PointerSettings.x, StatusBar.x, CrashExplain.h, Loader.c use them as the test plays them.
# 3. made-to-fail copies: each takes one part out and must fail.
# POINTERASIDE_TREE=<folder>: another tree (e.g. the code before the fix: then it must fail).
cd "$(dirname "$0")" || exit 1
T=${POINTERASIDE_TREE:-..}
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
[ -d "$FW/UIKit.framework" ] || { echo "FAIL  no Mac Catalyst UIKit in $SDK"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
CC() { clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" -fobjc-arc -Wall -Wno-unused-function \
          -Werror=implicit-function-declaration -framework UIKit -framework QuartzCore -framework CoreGraphics "$@"; }

# the other library, where a tweak's is on the iPad (a rootless jailbreak's /var/jb); the test itself where MacPointer is, also under /var/jb, so
# "another library" must also mean "not ours"
LIBDIR="$W/var/jb/usr/lib/TweakInject"; OURS="$W/var/jb/usr/lib/MacStatusBarAndDock"; mkdir -p "$LIBDIR" "$OURS"
CC -dynamiclib -install_name "$LIBDIR/PointerOther.dylib" -o "$LIBDIR/PointerOther.dylib" test-pointeraside-other.m 2> "$W/other-cc.txt" || { cat "$W/other-cc.txt"; echo "FAIL  the other library did not build"; exit 1; }

# 1.8.8.1.1's own stand-down rule (MPOtherPointerTweak), cut out of that release's MacPointer.x, played on the same pointer as the new look: it stands
# the Mac pointer down for a hook that draws nothing (GitHub #17's look). Without git history here: not played (a note, not a failure).
OLDINC=""
if git -C .. show e068b0c671007d043a671829ea392cf887bb305f:statusbar/macpointer/MacPointer.x 2>/dev/null | awk '/^static BOOL MPOtherPointerTweak\(void\) \{/{f=1} f{print} f && /^}/{exit}' > "$W/oldrule.inc" \
   && grep -q '^static BOOL MPOtherPointerTweak(void) {' "$W/oldrule.inc"; then OLDINC="-DOLD_RULE_INC=\"$W/oldrule.inc\""
else echo "note: 1.8.8.1.1's MacPointer.x is not in this checkout's history: its rule is not played"; fi
run() {   # $1 folder holding statusbar/macpointer/MPAside.h and common/MacPointerStatus.h, $2 quiet: the test built on them (release and DEBUG) and run
  local d=$1 q=$2 rc=0 dbg
  for dbg in 0 1; do
    if ! CC -DDEBUG=$dbg -DMPASIDE_H="\"$d/statusbar/macpointer/MPAside.h\"" $OLDINC -o "$OURS/t$dbg" test-pointeraside.m 2> "$W/cc$dbg.txt"; then
      [ -n "$q" ] || { head -5 "$W/cc$dbg.txt"; echo "FAIL  the test did not build on $d (DEBUG=$dbg)"; }; return 1
    fi
    [ -s "$W/cc$dbg.txt" ] && { [ -n "$q" ] || { echo "FAIL  warnings (DEBUG=$dbg):"; cat "$W/cc$dbg.txt"; }; rc=1; }
    [ -n "$q" ] || echo "== DEBUG=$dbg"
    if [ -n "$q" ]; then OTHER_LIB="$LIBDIR/PointerOther.dylib" "$OURS/t$dbg" > /dev/null 2>&1 || rc=1
    else OTHER_LIB="$LIBDIR/PointerOther.dylib" "$OURS/t$dbg" || rc=1; fi
  done
  return $rc
}
echo "== 1. the look and the words (Mac Catalyst)"
if [ -f "$T/statusbar/macpointer/MPAside.h" ] && [ -f "$T/common/MacPointerStatus.h" ]; then
  mkdir -p "$W/real/statusbar/macpointer" "$W/real/common"; cp "$T/statusbar/macpointer/MPAside.h" "$W/real/statusbar/macpointer/"; cp "$T/common/MacPointerStatus.h" "$W/real/common/"
  run "$W/real" || fails=1
else echo "FAIL  no statusbar/macpointer/MPAside.h or common/MacPointerStatus.h in $T (the stand-down rule of 1.8.8.1.1: any other hook turns the Mac pointer off, nothing said)"; fails=1; fi

echo "== 2. site checks"
sites() {   # $1 tree, $2 quiet: the number of failed site checks
  python3 - "$1" "$2" <<'PY'
import os, re, sys
root, quiet = sys.argv[1], sys.argv[2] == '1'
def rd(p):
    try: return open(os.path.join(root, p)).read()
    except OSError: return ''
M, P, S, C, L = rd('statusbar/macpointer/MacPointer.x'), rd('macsettings/PointerSettings.x'), rd('statusbar/StatusBar.x'), rd('common/CrashExplain.h'), rd('loader/Loader.c')
H = rd('macsettings/sshtoggled/main.m')
def fn(text, head):   # one function or method, from its first line, by its braces
    i = text.find(head)
    if i < 0: return ''
    j = text.find('{', i); d = 0
    for k in range(j, len(text)):
        if text[k] == '{': d += 1
        elif text[k] == '}':
            d -= 1
            if d == 0: return text[i:k + 1]
    return ''
def debug_only(text, needle):   # is the line holding needle inside an "#if DEBUG" (and not its #else)?
    st = []
    for line in text.split('\n'):
        s = line.strip()
        if s.startswith('#if DEBUG'): st.append(1); continue
        if s.startswith('#if'): st.append(0); continue
        if s.startswith('#else') and st: st[-1] = 2 if st[-1] == 1 else st[-1]; continue
        if s.startswith('#endif') and st: st.pop(); continue
        if needle in line: return 1 in st
    return None
def before(text, a, b): return a in text and b in text and text.find(a) < text.find(b)
R = []
def check(name, ok): R.append((name, bool(ok)))
csd = fn(M, 'static void MPCheckStandDown(void) {')
check('S1 MacPointer.x: MPAside.h included; the hook scan (MPAsideOtherHooks) only decides whether to look: WAITING with other hooks, ALONE without; no old rule left',
      '#include "MPAside.h"' in M and 'MPOtherPointerTweak' not in M and 'unsigned hooks = MPAsideOtherHooks(gMPOtherPath, sizeof gMPOtherPath,' in csd
      and 'MPSetAside(hooks ? MSBD_MP_V_WAITING : MSBD_MP_V_ALONE, 0);' in csd and 'gMPMissing = MPAsideMissing();' in csd and csd.find('gMPStandDownChecked = YES;') < csd.find('MPAsideOtherHooks'))
sa = fn(M, 'static void MPSetAside(unsigned verdict, unsigned seen) {')
check('S2 gMPStandDown follows the verdict in one place (MPSetAside: drawn only ALONE or SHARED); the word is said there',
      len(re.findall(r'(?<!BOOL )\bgMPStandDown = ', M)) == 1 and 'gMPStandDown = !MSBDMPVerdictDraws(verdict);' in sa and 'MPPublishStatus();' in sa and 'if (was != MSBD_MP_V_NONE) MPPublishPresence();' in sa)
check('S3 MPEnabled as before: the setting, the bridge and the verdict',
      'return !gMPStandDown && c != 0 && (c & 1) && MPState(gMPOrientToken) != 0;' in fn(M, 'static BOOL MPEnabled(void) {') and 'MPCheckStandDown();' in fn(M, 'static BOOL MPEnabled(void) {'))
pp = fn(M, 'static void MPPublishPresence(void) {')
check('S4 SpringBoard is told 1 or 2 only once the pointer was looked at (not while WAITING)',
      before(pp, 'MPCheckStandDown();', 'if (gMPAside == MSBD_MP_V_WAITING) return;') and before(pp, 'if (gMPAside == MSBD_MP_V_WAITING) return;', 'uint64_t want = gMPStandDown ? 2 : 1, cur = 0;'))
av = fn(M, 'static void MPApplyVisibility(void) {')
check('S5 Hide in Virtual Mac: standing aside (it can now begin mid-run) gives the root view back, never hides it',
      'UIViewController *c = gMPController; if (!c) return;' in av and 'BOOL hide = !gMPStandDown && MPState(gMPHideToken) == 1;' in av and 'gMPStandDown) return' not in av)
up = fn(M, 'static void MPUpdate(PUIDPointerShapeView *view) {')
want = ['    BOOL enabled = MPEnabled();', '    BOOL sysHid = enabled && !systemShape && MPHiddenBySystem(view);', '    BOOL vmHid = enabled && !systemShape && !sysHid && MPState(gMPHideToken) == 1;',
        '    BOOL want = enabled && !systemShape && !sysHid && !vmHid;', '    MPSayNow(view, enabled, sysHid, vmHid);', '    MPAsideMaybeLook();']
check('S6 MPUpdate: the arrow wanted from the same reads in the same order as 1.8.8.1.1, then the word on why not shown, then the look',
      all(x in up for x in want) and all(before(up, want[i], want[i + 1]) for i in range(len(want) - 1)) and 'MPHiddenBySystem' not in up.replace(want[1], '') and up.count('MPEnabled()') == 1)
lk = fn(M, 'static double MPAsideLook(void) {')
ml = fn(M, 'static void MPAsideMaybeLook(void) {')
check('S7 the look: on a plain pointer the user sees once its shape settled (MSBDMPAsideCanLook), MSBDMPAsideNext, then every pointer view and the root view again; never for ALONE',
      'BOOL plain = !(shape && shape.shapeType != 1) && !gMPHovering && !MPAtRest();' in lk and 'double can = MSBDMPAsideCanLook(plain, CACurrentMediaTime(), gMPShapeAt);' in lk
      and before(lk, 'if (can >= 0.0) return can;', 'unsigned seen = MPAsideSeen(') and 'unsigned next = MSBDMPAsideNext(gMPAside, seen != 0, &gMPAsideClean);' in lk
      and before(lk, 'MPSetAside(next, next == MSBD_MP_V_ASIDE ? seen : 0);', 'MPUpdateAll();') and before(lk, 'MPUpdateAll();', 'MPApplyVisibility();')
      and 'return !view || !view.window || gMPAutoHidden || MPHiddenBySystem(view) || MPState(gMPHideToken) == 1;' in fn(M, 'static BOOL MPAtRest(void) {')
      and 'if (gMPAside != MSBD_MP_V_WAITING && gMPAside != MSBD_MP_V_SHARED) return;' in ml)
# (1.8.8.2, after a device pass on iPadOS 17.5.1: the look on its own 2 s timer while standing aside, a request after an update kept for its time)
tk, ts, li = fn(M, 'static void MPAsideTick(void) {'), fn(M, 'static void MPAsideTimerSet(BOOL on) {'), fn(M, 'static void MPAsideLookIn(double delay) {')
sp = fn(M, '- (void)setPointerShape:(id)shapeObj animated:(BOOL)animated completion:(id)completion {')
check('S19 standing aside: a look every 2 s on a timer of its own while the pointer is in use (MSBDMPAsideTimerWanted), started and stopped with the verdict and at each update; stopped at rest',
      'MPAsideTimerFollow();' in sa and before(sa, 'MPPublishStatus();', 'MPAsideTimerFollow();')
      and 'static void MPAsideTimerFollow(void) { MPAsideTimerSet(MSBDMPAsideTimerWanted(gMPAside, MPAtRest())); }' in M
      and 'if (gMPAside == MSBD_MP_V_ASIDE) { MPAsideTimerFollow(); return; }' in ml and before(ml, 'if (gMPLooking) return;', 'MPAsideTimerFollow();')
      and before(tk, 'if (!MSBDMPAsideTimerWanted(gMPAside, MPAtRest())) { MPAsideTimerSet(NO); return; }', 'double r = MPAsideLook();')
      and 'dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)every), every, NSEC_PER_SEC / 5);' in ts and 'uint64_t every = (uint64_t)(MSBD_MP_LOOK_EVERY * NSEC_PER_SEC);' in ts
      and 'dispatch_source_cancel(t);' in ts and M.count('MPAsideTimerSet(YES)') == 0 and M.count('dispatch_source_create(') == 1)
check('S20 after an update (waiting or drawing beside other hooks): the look queued for MSBDMPAsideLookDelay (a request inside the 2 s kept, never dropped); one settling asks again; the shape\'s change time kept',
      'MPAsideLookIn(MSBDMPAsideLookDelay(gMPAside, CACurrentMediaTime(), gMPLookedAt));' in ml and 'if (r > 0.0) MPAsideLookIn(r);' in li and 'if (queued) return;' in li
      and 'gMPLookedAt = CACurrentMediaTime();' in lk and before(lk, 'if (can >= 0.0) return can;', 'gMPLookedAt = CACurrentMediaTime();')
      and before(sp, 'if (before && [before isEqual:shapeObj]) return;', 'gMPShapeAt = CACurrentMediaTime();') and M.count('gMPShapeAt = CACurrentMediaTime()') == 1
      and 'dispatch_async(dispatch_get_main_queue(), ^{ queued = NO; last = CACurrentMediaTime(); MPAsideLook(); });' not in M)
check('S8 the release log lines (standing aside, drawing again, a harmless hook, parts not found) are not debug only',
      all(debug_only(M, x) is False for x in ['NSLog(@"[MacPointer] standing aside: another pointer is drawn', 'NSLog(@"[MacPointer] drawing again: the other pointer is no longer shown");',
                                               'NSLog(@"[MacPointer] another library changes the pointer (%s) but draws no pointer: the Mac pointer draws", base);', 'if (gMPMissing) NSLog(@"[MacPointer] parts of iPadOS']))
ct = fn(M, '%ctor {')
check('S9 MacPointer says its word (its pid) as it loads, in release builds too',
      ct.split('\n')[1].strip().startswith('MPPublishStatus();') and debug_only(M, '    MPPublishStatus();   // (1.8.8.2: "loaded in this pointeruid"') is False
      and 'uint64_t w = MSBDMPPack((uint32_t)getpid(), gMPAside, gMPAsideSeen, gMPMissing, gMPNow);' in fn(M, 'static void MPPublishStatus(void) {'))
own = fn(P, 'NSArray *MSPointerOwnSpecifiers(id target, BOOL onApplePage) {')
mac = own[own.find('if ([MSPointerStyle() isEqualToString:@"mac"]) {'):]
check('S10 Settings > Pointer: the note right under Pointer Style, only with the Mac style and only when there is something to say; from both words',
      before(mac, 'NSString *note = MSPointerStatusNoteIs(&noteKind);', 'if (MSBDHypervisorCapable()) {') and '[gn setIdentifier:@"MAC_POINTER_STATUS"];' in mac and '[gn setProperty:note forKey:@"footerText"];' in mac
      and 'int n = MSBDMPNoteFor(YES, MSBDMPReadState(MSBD_MP_STATUS), MSBDMPReadState(MSBD_MP_PROCESS));' in P and 'return MSBDMPNoteText(n, [UIDevice currentDevice].systemVersion);' in P
      and own.count('MSPointerStatusNote') == 1)
check('S11 ... the open page follows both words, listening only while it is shown, built again only when the note changes',
      'notify_register_dispatch(MSBD_MP_STATUS, &_msStatusToken' in fn(P, '- (void)viewDidAppear:(BOOL)animated {') and 'notify_register_dispatch(MSBD_MP_PROCESS, &_msProcessToken' in fn(P, '- (void)viewDidAppear:(BOOL)animated {')
      and '[self msStopPointerStatus];' in fn(P, '- (void)viewDidDisappear:(BOOL)animated {') and '[self msStopPointerStatus];' in fn(P, '- (void)dealloc {')
      and before(fn(P, '- (void)msPointerStatusChanged {'), 'if (now == _msNote || [now isEqualToString:_msNote]) return;', '[self reloadSpecifiers];'))
bs, be = S.find('// ===== MacPointer bridge'), S.find('// ===== end MacPointer bridge')
pc = fn(S, 'static void DMMacPointerProcessCheck(void) {')
check('S12 SpringBoard: the pointer process word at every 2 s device check, inside the MacPointer bridge (the crash map answers it as the bridge tick around it)',
      'DMPointerDeviceCheck(); DMPointerAnimTick(); DMMacPointerProcessCheck(); }   // every 2 s, at either pace' in S and S.count('DMMacPointerProcessCheck();') == 1
      and bs < S.find('static void DMMacPointerProcessCheck(void) {') < be and bs < S.find('static BOOL DMPointerProcRead(int pid') < be and bs < S.find('static int DMPointerProcFind(void) {') < be
      and 'uint64_t want = MSBDMPProcessWord(gDMPointerAttached, mp, mpRuns, mpRuns ? 0 : procPid, age, said);' in pc and 'if (CACurrentMediaTime() - lastFind >= 10.0)' in pc)
rp = fn(C, 'static inline NSURL *MSBDReportProblemURL(NSString *engine) {')
check('S13 Report a Problem: the Mac pointer line in the part that is never shortened',
      '- MacStatusBar&Dock: %@\\n- Mac pointer: %@\\n",' in rp and 'NSString *pointer = MSBDMPReportWords(MSBDMPStyleMac(), MSBDMPReadState(MSBD_MP_STATUS), MSBDMPReadState(MSBD_MP_PROCESS), MSBDMPOtherName());' in rp
      and rp.find('NSString *pointer =') < rp.find('NSString *base =') < rp.find('for (int i = 0; i < 4; i++) {') and '#include "MacPointerStatus.h"' in C)
lp = fn(L, '__attribute__((constructor)) static void MSBDLoad(void) {')
check('S14 the loader: in pointeruid, MacPointer held back (rows only) or not opened is said; any part that does not open goes to the system log, release builds too',
      'if (kind & kPointerUID) MSBDPointerProcessWord(MSBD_MP_V_LOADFAIL);' in lp and 'if ((kind & kPointerUID) && rowsOnly) MSBDPointerProcessWord(MSBD_MP_V_HELD);' in lp
      and debug_only(L, 'os_log_error(OS_LOG_DEFAULT, "MacStatusBar&Dock: %{public}s did not load: %{public}s"') is False
      and before(lp, 'if (dlopen(lib, RTLD_NOW)) {', 'MSBDPointerProcessWord(MSBD_MP_V_LOADFAIL)') and 'notify_set_state(token, MSBDMPPack((uint32_t)getpid(), verdict, 0, 0, 0));' in fn(L, 'static void MSBDPointerProcessWord(unsigned verdict) {'))
own2 = own[own.find('if (note) {'):]
check('S15 Settings > Pointer: Restart Pointer in the note\'s group, only for the notes that offer it (MSBDMPNoteHasRestart), its own target posting the request',
      before(own2, '[s addObject:gn];', 'if (MSBDMPNoteHasRestart(noteKind)) {') and before(own2, 'if (MSBDMPNoteHasRestart(noteKind)) {', '[rb setButtonAction:@selector(msRestartPointer:)];')
      and 'PSSpecifier *rb = [PSSpecifier preferenceSpecifierNamed:@"Restart Pointer" target:gMSPointerRestart set:NULL get:NULL detail:Nil cell:kCellButton edit:Nil];' in own2
      and '- (void)msRestartPointer:(id)specifier { notify_post(MSBD_MP_RESTART); }' in P and own.count('Restart Pointer') == 1 and 'kCellButton = 13' in P)
pr = fn(H, 'static void PointerRestartRequest(void) {')
check('S16 the root helper: listens for the request and stops only the system pointeruid with SIGKILL, at most once every 5 s, logged',
      'notify_register_dispatch(MSBD_MP_RESTART, &t9, dispatch_get_main_queue(), ^(int t) { PointerRestartRequest(); });' in H and H.count('PointerRestartRequest();') == 1
      and before(pr, 'if (!MSBDMPRestartNow(CFAbsoluteTimeGetCurrent(), &last))', 'kill(pid, SIGKILL)') and before(pr, 'if (!MSBDMPRestartTarget(comm, path)) {', 'kill(pid, SIGKILL)')
      and pr.count('kill(') == 1 and '#include "../../common/MacPointerStatus.h"' in H)
# (1.8.8.2 review) the request carries no sender: the helper takes it only while the words ask for it, after the 5 s limit and before the process
# list is read; a burst writes one log line per 5 s. SpringBoard with no trackpad or mouse and its word 0 (most iPads at rest) reads nothing.
check('S17 the root helper: a request is taken only while MacPointer\'s and SpringBoard\'s words ask for it (MSBDMPRestartWanted), checked before the process list; one "again" line per 5 s',
      before(pr, 'if (!MSBDMPRestartNow(CFAbsoluteTimeGetCurrent(), &last)) { if (!toldAgain++) ELog(', 'uint64_t status = MSBDMPReadState(MSBD_MP_STATUS), process = MSBDMPReadState(MSBD_MP_PROCESS);')
      and before(pr, 'uint64_t status = MSBDMPReadState(MSBD_MP_STATUS), process = MSBDMPReadState(MSBD_MP_PROCESS);', 'if (!MSBDMPRestartWanted(status, process)) {')
      and before(pr, 'if (!MSBDMPRestartWanted(status, process)) {', 'int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };') and 'toldAgain = 0;' in pr)
check('S18 SpringBoard: with no trackpad or mouse and the process word already 0, the 2 s check returns before any read',
      before(pc, 'if (!gDMPointerAttached && !said) return;', 'notify_register_check(MSBD_MP_PROCESS, &token)') and before(pc, 'if (!gDMPointerAttached && !said) return;', 'MSBDMPReadState(MSBD_MP_STATUS)'))
bad = 0
for name, ok in R:
    if not ok: bad += 1
    if not quiet: print(('PASS  ' if ok else 'FAIL  ') + name)
print('SITES-FAILED %d' % bad) if quiet else None
sys.exit(min(bad, 100))
PY
}
sites "$T" 0 || fails=1

echo "== 3. made-to-fail copies (each must fail)"
mut_h() {   # $1 what, $2 file (MPAside.h or MacPointerStatus.h), $3 perl substitution: the test on a copy with it applied must fail
  local d="$W/m$RANDOM"; mkdir -p "$d/statusbar/macpointer" "$d/common"; cp "$W/real/statusbar/macpointer/MPAside.h" "$d/statusbar/macpointer/"; cp "$W/real/common/MacPointerStatus.h" "$d/common/"
  local f="$d/statusbar/macpointer/MPAside.h"; [ "$2" = MacPointerStatus.h ] && f="$d/common/MacPointerStatus.h"
  cp "$f" "$f.orig"; perl -0pi -e "$3" "$f"
  if cmp -s "$f" "$f.orig"; then echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; fi
  if run "$d" quiet; then echo "FAIL  made-to-fail ($1): the test still passes"; fails=1; else echo "PASS  made-to-fail ($1): caught"; fi
}
mut_s() {   # $1 what, $2 file of the tree, $3 perl substitution: the site checks on a copy with it applied must fail
  local d="$W/s$RANDOM"; mkdir -p "$d"
  for f in statusbar/macpointer/MacPointer.x macsettings/PointerSettings.x statusbar/StatusBar.x common/CrashExplain.h loader/Loader.c macsettings/sshtoggled/main.m; do mkdir -p "$d/$(dirname $f)"; cp "$T/$f" "$d/$f"; done
  cp "$d/$2" "$d/$2.orig"; perl -0pi -e "$3" "$d/$2"
  if cmp -s "$d/$2" "$d/$2.orig"; then echo "FAIL  made-to-fail ($1): the change did not apply"; fails=1; return; fi
  if sites "$d" 1 > /dev/null; then echo "FAIL  made-to-fail ($1): the site checks still pass"; fails=1; else echo "PASS  made-to-fail ($1): caught"; fi
}
if [ -d "$W/real" ]; then
  mut_h "pointeruid's own views not told apart (nothing held)" MPAside.h 's/if \(MPAsideIn\(\(__bridge const void \*\)l, held, n\) \|\| MPAsideIn\(\(__bridge const void \*\)d, held, n\)\) continue;/(void)held;/'
  mut_h "pointeruid's morphing shape subview counted as another pointer" MPAside.h 's/        if \(\[d isKindOfClass:\[UIView class\]\] && MPAsideClassIsPUID\(object_getClass\(d\)\)\) continue;\n//'
  mut_h "a hidden layer counted" MPAside.h 's/if \(!l \|\| l\.hidden \|\| l\.opacity < 0\.01f \|\| depth > 6\) return NO;/if (!l || depth > 6) return NO;/'
  mut_h "the round pointer the Mac pointer hid itself counted" MPAside.h 's/ && !\[weHid containsObject:round\]//'
  mut_h "another library's classes not looked for" MPAside.h 's/BOOL other = MPAsideOtherImageOf\(\(__bridge const void \*\)c\) != NULL;/BOOL other = NO;/'
  mut_h "our own library counted as another" MPAside.h 's/ \|\| di\.dli_fbase == me\)/)/'
  mut_h "drawing again after one clean look" MacPointerStatus.h 's/if \(\+\+\*clean < 2\) return MSBD_MP_V_ASIDE;/if (++*clean < 1) return MSBD_MP_V_ASIDE;/'
  mut_h "a harmless hook still stands the Mac pointer aside" MacPointerStatus.h 's/    \*clean = 0;\n    return MSBD_MP_V_SHARED;/    *clean = 0;\n    return MSBD_MP_V_ASIDE;/'
  mut_h "a note with Pointer Style iPadOS" MacPointerStatus.h 's/if \(!styleMac\) return MSBD_MP_NOTE_NONE;\n/\n/'
  mut_h "another tweak named on the page" MacPointerStatus.h 's/another tweak draws its own pointer/OtherPointer.dylib draws its own pointer/'
  mut_h "Restart Pointer offered with every note" MacPointerStatus.h 's/static inline int MSBDMPNoteHasRestart\(int note\) \{ return note == MSBD_MP_NOTE_NOT_RUNNING \|\| note == MSBD_MP_NOTE_LOAD_FAILED; \}/static inline int MSBDMPNoteHasRestart(int note) { return note != MSBD_MP_NOTE_NONE; }/'
  mut_h "a jailbreak's pointeruid stopped" MacPointerStatus.h 's/return !strstr\(path, "\/var\/jb\/"\) && !strstr\(path, "\/private\/preboot\/"\);/return 1;/'
  mut_h "no limit on restart requests" MacPointerStatus.h 's/if \(\*last > 0 && now - \*last < 5\.0 && now >= \*last\) return 0;//'
  mut_h "the look's timer also while drawing (a look every 2 s for a harmless hook)" MacPointerStatus.h 's/\{ return verdict == MSBD_MP_V_ASIDE && !atRest; \}/{ return (verdict == MSBD_MP_V_ASIDE || verdict == MSBD_MP_V_SHARED) \&\& !atRest; }/'
  mut_h "the look's timer at rest too" MacPointerStatus.h 's/\{ return verdict == MSBD_MP_V_ASIDE && !atRest; \}/{ (void)atRest; return verdict == MSBD_MP_V_ASIDE; }/'
  mut_h "a look before the shape settled (the round pointer iPadOS hides while it morphs counted)" MacPointerStatus.h 's/#define MSBD_MP_SETTLE 0\.5/#define MSBD_MP_SETTLE 0.0/'
  mut_h "a look on a pointer that is not plain" MacPointerStatus.h 's/    if \(!plain\) return 0\.0;\n//'
  mut_h "a restart request taken whatever the words say" MacPointerStatus.h 's/\{ return MSBDMPNoteHasRestart\(MSBDMPNoteFor\(1, status, process\)\); \}/{ (void)status; (void)process; return 1; }/'
fi
mut_s "the old rule: any other hook stands the Mac pointer aside for the run" statusbar/macpointer/MacPointer.x 's/MPSetAside\(hooks \? MSBD_MP_V_WAITING : MSBD_MP_V_ALONE, 0\);/MPSetAside(hooks ? MSBD_MP_V_ASIDE : MSBD_MP_V_ALONE, 0);/'
mut_s "SpringBoard told while waiting" statusbar/macpointer/MacPointer.x 's/    if \(gMPAside == MSBD_MP_V_WAITING\) return;\n//'
mut_s "Hide in Virtual Mac keeps the root hidden when standing aside" statusbar/macpointer/MacPointer.x 's/UIViewController \*c = gMPController; if \(!c\) return;\n    BOOL hide = !gMPStandDown && /UIViewController *c = gMPController; if (!c || gMPStandDown) return;\n    BOOL hide = /'
mut_s "the standing-aside log line debug only" statusbar/macpointer/MacPointer.x 's/(    \/\/ \(release builds too: one line at each change)/#if DEBUG\n$1/; s/(#if DEBUG\n    MPLog\(\[NSString stringWithFormat:@"%.3f aside: verdict)/#endif\n$1/'
mut_s "no note on the page" macsettings/PointerSettings.x 's/\[gn setProperty:note forKey:@"footerText"\];//'
mut_s "the process word never said" statusbar/StatusBar.x 's/ DMMacPointerProcessCheck\(\); \}   \/\/ every 2 s/ }   \/\/ every 2 s/'
mut_s "no Mac pointer line in Report a Problem" common/CrashExplain.h 's/\\n- Mac pointer: %@\\n",/\\n",/'
mut_s "Restart Pointer posts nothing" macsettings/PointerSettings.x 's/- \(void\)msRestartPointer:\(id\)specifier \{ notify_post\(MSBD_MP_RESTART\); \}/- (void)msRestartPointer:(id)specifier { }/'
mut_s "the root helper does not listen for Restart Pointer" macsettings/sshtoggled/main.m 's/\^\(int t\) \{ PointerRestartRequest\(\); \}\);/^(int t) { });/'
mut_s "the root helper stops any pointeruid" macsettings/sshtoggled/main.m 's/        if \(!MSBDMPRestartTarget\(comm, path\)\) \{[^\n]*\n//'
mut_s "the root helper restarts whatever the words say" macsettings/sshtoggled/main.m 's/    if \(!MSBDMPRestartWanted\(status, process\)\) \{\n[^\n]*\n        return;\n    \}\n//'
mut_s "SpringBoard reads the words with no pointer attached" statusbar/StatusBar.x 's/    if \(!gDMPointerAttached && !said\) return;[^\n]*\n//'
mut_s "no timer of its own while standing aside (looks only after updates)" statusbar/macpointer/MacPointer.x 's/    MPAsideTimerFollow\(\);   \/\/ \(standing aside: its own look[^\n]*\n//'
mut_s "an update's look dropped inside the 2 s" statusbar/macpointer/MacPointer.x 's/    MPAsideLookIn\(MSBDMPAsideLookDelay\(gMPAside, CACurrentMediaTime\(\), gMPLookedAt\)\);/    if (MSBDMPAsideLookDelay(gMPAside, CACurrentMediaTime(), gMPLookedAt) > 0) return; MPAsideLookIn(0);/'
mut_s "the shape's change time never kept" statusbar/macpointer/MacPointer.x 's/    gMPShapeAt = CACurrentMediaTime\(\);[^\n]*\n//'
mut_s "the loader silent when MacPointer does not open" loader/Loader.c 's/            if \(kind & kPointerUID\) MSBDPointerProcessWord\(MSBD_MP_V_LOADFAIL\);[^\n]*\n//'

[ $fails = 0 ] && echo "test-pointeraside: all checks pass" || { echo "test-pointeraside: FAILED"; exit 1; }
