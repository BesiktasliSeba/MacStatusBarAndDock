#!/bin/bash
# Mac test of B74 (1.8.8.2): the desktop's typing (a sticky note, or a name) ends at a layout transition SpringBoard begins when Spotlight is
# presented (Cmd-Space with no touch: the keys went to Spotlight while the note stayed typed in) or the iPad's display goes to a full-screen window
# or app (smfull_, Globe-F: the editor and the keyboard stayed over the full-screen app until Home). The rule is common/StickyNotes.h's
# MSBDStickyTypingAt; the real DMDesktopTypingGet, DMDesktopTypingAtTransition, DMDesktopTypingPass and DMDesktopTypingWatch are cut out of
# statusbar/Desktop.h, with the signature helpers cut out of statusbar/SMEngineAPI.h, and run on a model of SpringBoard's objects
# (test-typingends.m: the same class names, selectors and type encodings); then site checks, then made-to-fail copies of each file read here
# (each must be caught). A file read can be given as a copy: MSB_D (Desktop.h), MSB_N (StickyNotes.h), MSB_API (SMEngineAPI.h), MSB_CR
# (crashmap-rules.txt).
cd "$(dirname "$0")" || exit 1
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
# model <Desktop.h> <StickyNotes.h> <SMEngineAPI.h> <dir>: builds the three models from these files and runs them; prints their lines
model() {
  local D=$1 N=$2 API=$3 O=$4 rc=0 v
  mkdir -p "$O/common" "$O/tools"; cp "$N" "$O/common/StickyNotes.h"; cp test-typingends.m "$O/tools/"
  { fnf 'static NSString *DMSMNormEncoding(const char *e) {' "$API"; fnf 'static NSString *DMSMExpect(const char *ret, ...) {' "$API"
    grep '^static NSString \*DMSMSigOfMethod(Method m) {' "$API"; grep '^#define DMSM_SIG(name, \.\.\.)' "$API"; grep '^DMSM_SIG(DMSMSigTime, \|^DMSM_SIG(DMSMSigObj, ' "$API"
    fnf 'static id DMDesktopTypingGet(id o, const char *name) {' "$D"; fnf '__attribute__((noinline)) static void DMDesktopTypingAtTransition(id tx) {' "$D"
    grep '^static void (\*o_DMDesktopTypingPass)(id, SEL, id);' "$D"; fnf 'static void DMDesktopTypingPass(id self, SEL _cmd, id tx) {' "$D"
    fnf 'static void DMDesktopTypingWatch(void) {' "$D"; } > "$O/tools/cut.h"
  for v in main TE_ODD TE_NONE; do
    local def=""; [ $v != main ] && def="-D$v"
    if ! clang -O1 -fobjc-arc -Wall -Wno-unused-function $def -I"$O/tools" -framework Foundation -o "$O/t-$v" "$O/tools/test-typingends.m" > "$O/cc-$v.txt" 2>&1; then
      echo "FAIL  the model ($v) builds from the cut-out code"; sed 's/^/      /' "$O/cc-$v.txt" | head -20; rc=1; continue
    fi
    if [ -s "$O/cc-$v.txt" ]; then echo "FAIL  the model ($v) builds without a warning"; sed 's/^/      /' "$O/cc-$v.txt" | head -20; rc=1; fi
    "$O/t-$v" || rc=1
  done
  return $rc
}
# sites <Desktop.h> <crashmap-rules.txt>: the places the fix plugs into
sites() {
  local D=$1 CR=$2 rc=0
  ck() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; rc=1; fi; }
  ck "the watch goes in with the first typing: DMDesktopFocus taking the lock (a note's begin and a name's) asks for it, before the lock is taken" \
    "fnf 'static void DMDesktopFocus(BOOL take) {' $D | sed -n 2p | grep -qxF '    if (take) { DMKeyboardDockWatch(); DMDesktopTypingWatch(); }' && grep -qxF 'static void DMDesktopTypingWatch(void);   // (below: SpringBoard'\"'\"'s layout transitions end the typing for Spotlight and full screen, 1.8.8.2 B74)' $D"
  ck "  ... a note's begin and a name's both take that lock (DMDesktopFocus(YES))" \
    "grep -qF 'DMDesktopFocus(YES);   // (the rename'\"'\"'s lock' ../statusbar/DesktopNotes.h && fnf '- (void)dm_beginRename:(NSString *)path {' $D | grep -qxF '    DMDesktopFocus(YES);'"
  ck "the hook is SpringBoard's begin of every layout transition, checked by its signature, put in once" \
    "fnf 'static void DMDesktopTypingWatch(void) {' $D | grep -qF 'Class c = objc_getClass(\"SBLayoutStateTransitionCoordinator\");' && fnf 'static void DMDesktopTypingWatch(void) {' $D | grep -qF 'SEL s = sel_registerName(\"beginTransitionForWorkspaceTransaction:\");' \
     && fnf 'static void DMDesktopTypingWatch(void) {' $D | grep -qF 'if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(id), NULL)]) {' && fnf 'static void DMDesktopTypingWatch(void) {' $D | grep -qF 'MSHookMessageEx(c, s, (IMP)DMDesktopTypingPass, (IMP *)&o_DMDesktopTypingPass);'"
  ck "the ends go through DMDesktopTypingEnd (a note's text saved and a name kept as typed, as for the Mac Switcher), with the rule's reason" \
    "fnf '__attribute__((noinline)) static void DMDesktopTypingAtTransition(id tx) {' $D | grep -qxF '    DMDesktopTypingEnd(MSBDStickyTypingWhy(end));' && fnf '- (void)dm_typingEnd:(NSString *)why {' $D | grep -qF '[self dm_noteEnd:why];' && fnf '- (void)dm_typingEnd:(NSString *)why {' $D | grep -qF '[self dm_endRename:YES];'"
  ck "the rule is StickyNotes.h's, included by Desktop.h before the decision" \
    "awk '/^#include \"..\\/common\\/StickyNotes.h\"/{a=NR} /^__attribute__\\(\\(noinline\\)\\) static void DMDesktopTypingAtTransition\\(id tx\\) \\{/{b=NR} END{exit !(a && b > a)}' $D && fnf '__attribute__((noinline)) static void DMDesktopTypingAtTransition(id tx) {' $D | grep -qF 'MSBDStickyTypingEnd end = MSBDStickyTypingAt(spot, read, onIPad, mode, sm, full);'"
  ck "the crash guard: the decision is the desktop's (a DMDesktopTyping name, out of line); the pass-through is transparent, its rule before the desktop's" \
    "grep -q '^__attribute__((noinline)) static void DMDesktopTypingAtTransition(id tx) {' $D && grep -q '^static void DMDesktopTypingPass(id self, SEL _cmd, id tx) {' $D && grep -q '^static void DMDesktopTypingWatch(void) {' $D \
     && awk '/^sym MacStatusBarCore \\^_\\*DMDesktopTypingPass\\$ transparent$/{a=NR} /^sym MacStatusBarCore \\^_\\?DMDesktop\\[A-Z\\] desktopIcons$/{b=NR} END{exit !(a && b > a)}' $CR"
  ck "the tick's ends and the touches' are left as they were (the fix adds ends, it does not move them)" \
    "fnf '- (void)dm_noteTick {' ../statusbar/DesktopNotes.h | grep -qF 'else if (![[DMActiveApp() bundleIdentifier] ?: @\"\" isEqualToString:_notes.editFront ?: @\"\"]) why = @\"another app came to the front\";' \
     && fnf '- (void)dm_noteTick {' ../statusbar/DesktopNotes.h | grep -qF 'else if (DMSBTextInputTypingBut(gDesktopRenameWindow, nil)) why = @\"another text field has the typing\";' && fnf '- (void)dm_noteTouchBegan:(UITouch *)t {' ../statusbar/DesktopNotes.h | grep -qF '[self dm_noteEnd:@\"a touch elsewhere\"];'"
  return $rc
}
fails=0
D=${MSB_D:-../statusbar/Desktop.h}; N=${MSB_N:-../common/StickyNotes.h}; API=${MSB_API:-../statusbar/SMEngineAPI.h}; CR=${MSB_CR:-crashmap-rules.txt}
echo "== the rule, and the real code on a model of SpringBoard's objects"
model "$D" "$N" "$API" "$W/real" || fails=1
echo "== the sites"
sites "$D" "$CR" || fails=1
echo "== made-to-fail copies (each must be caught)"
mtf() {   # mtf <what> <file to copy> <which: D|N|CR> <python replace: old> <new>
  local what=$1 src=$2 which=$3 old=$4 new=$5 C="$W/mtf/$(echo "$what" | tr -c 'A-Za-z0-9' '_')"
  mkdir -p "$C"; cp "$src" "$C/copy"
  if ! python3 -I -c 'import sys; p,o,n=sys.argv[1:4]; s=open(p).read(); assert s.count(o)==1, "not once: "+o; open(p,"w").write(s.replace(o,n))' "$C/copy" "$old" "$new" 2>"$C/py.txt"; then
    echo "FAIL  made to fail ($what): the mutation does not apply"; fails=1; return
  fi
  local d=$D n=$N cr=$CR
  case $which in D) d="$C/copy";; N) n="$C/copy";; CR) cr="$C/copy";; esac
  if model "$d" "$n" "$API" "$C/m" > "$C/out.txt" 2>&1 && sites "$d" "$cr" >> "$C/out.txt" 2>&1; then echo "FAIL  made to fail ($what): the test still passes"; fails=1
  else echo "PASS  made to fail ($what): caught ($(grep -c '^FAIL' "$C/out.txt") check(s) fail, the first: $(grep -m1 '^FAIL' "$C/out.txt" | cut -c7-))"; fi
}
mtf "Spotlight not looked for" "$D" D '        spot = [DMDesktopTypingGet(DMDesktopTypingGet(DMDesktopTypingGet(req, "transientOverlayContext"), "transientOverlay"), "viewController") isKindOfClass:spotlight];' '        spot = NO;'
mtf "Spotlight's dismissal taken for its presentation" "$D" D 'if (present && spotlight && [tx isKindOfClass:present])' 'if (present && spotlight)'
mtf "any overlay taken for Spotlight" "$D" D 'isKindOfClass:spotlight];' 'isKindOfClass:[NSObject class]];'
mtf "the display not asked (a TV window full screen ends the iPad's typing)" "$D" D 'BOOL onIPad = !where || !mine || [where isEqual:mine];' 'BOOL onIPad = YES;'
mtf "the iPad's own identity unreadable taken for another display" "$D" D 'BOOL onIPad = !where || !mine || [where isEqual:mine];' 'BOOL onIPad = !where || [where isEqual:mine];'
mtf "Stage Manager's stage not asked (every window ends it)" "$D" D 'if (DMSMAttrsFullScreen(map[it])) { full = YES; break; }' '{ full = YES; break; }'
mtf "the mode's signature not checked" "$D" D '[DMSMSigOfMethod(class_getInstanceMethod(object_getClass(state), em)) isEqualToString:DMSMSigTime()]' 'YES'
mtf "a getter's signature not checked" "$D" D '![DMSMSigOfMethod(class_getInstanceMethod(object_getClass(o), s)) isEqualToString:DMSMSigObj()]' 'NO'
mtf "the decision before SpringBoard's own begin" "$D" D '    o_DMDesktopTypingPass(self, _cmd, tx);
    if (DMDesktopTypingNow()) DMDesktopTypingAtTransition(tx);' '    if (DMDesktopTypingNow()) DMDesktopTypingAtTransition(tx);
    o_DMDesktopTypingPass(self, _cmd, tx);'
mtf "the decision asked with nothing typed" "$D" D '    if (DMDesktopTypingNow()) DMDesktopTypingAtTransition(tx);' '    DMDesktopTypingAtTransition(tx);'
mtf "the watch's signature check gone" "$D" D 'if (!m || ![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(id), NULL)]) {' 'if (!m) {'
mtf "the watch put in more than once" "$D" D '    if (done) return;
    done = YES;
    Class c = objc_getClass("SBLayoutStateTransitionCoordinator");' '    Class c = objc_getClass("SBLayoutStateTransitionCoordinator");'
mtf "the watch not asked for at the first typing" "$D" D '    if (take) { DMKeyboardDockWatch(); DMDesktopTypingWatch(); }' '    if (take) DMKeyboardDockWatch();'
mtf "the rule: any mode ends it" "$N" N 'if (!stateRead || !onIPad || mode != 3) return MSBDStickyTypingGoesOn;' 'if (!stateRead || !onIPad) return MSBDStickyTypingGoesOn;'
mtf "the rule: Stage Manager's windows end it" "$N" N 'return (!smEngine || stageFull) ? MSBDStickyTypingFullScreen : MSBDStickyTypingGoesOn;' 'return MSBDStickyTypingFullScreen;'
mtf "the rule: the other engines' full-screen app keeps it" "$N" N 'return (!smEngine || stageFull) ? MSBDStickyTypingFullScreen : MSBDStickyTypingGoesOn;' 'return stageFull ? MSBDStickyTypingFullScreen : MSBDStickyTypingGoesOn;'
mtf "the rule: Spotlight only on the iPad" "$N" N '    if (spotlight) return MSBDStickyTypingSpotlight;' '    if (spotlight && onIPad) return MSBDStickyTypingSpotlight;'
mtf "the pass-through's transparent rule gone" "$CR" CR 'sym MacStatusBarCore ^_*DMDesktopTypingPass$ transparent
' ''
[ $fails = 0 ] && echo "test-typingends: all pass" || echo "test-typingends: FAILED"
exit $fails
