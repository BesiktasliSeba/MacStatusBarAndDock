#!/bin/bash
# Mac test of the layouts noted for windows across a respring (1.8.2.1, plans/v1821-f1.md; regression 1.8.2 M1 F1): a window not shown keeps the layout it had
# when it was last on screen, and only its view held it, so after a respring a Fill window of another desktop was in no layout and a Position round left it
# 1142 wide at the bottom. The code as built, cut out of statusbar/StatusBar.x: Aerial, Zetsu and MilkyWay4's window state entry (DMSaveWindowState) and what
# the restore does with it where it places the window (DMRestoreStep), the note's checks (DMStageLayoutNote, DMStageSetLayoutNote); Stage Manager's state file
# (DMSMStateWrite, DMSMTurnLayouts, DMSMTurnLayoutsFrom) and where a closed window's records go with it (DMSMTurnForget, DMSMTurnForgetClosed, DMSMForgetApp;
# code review 1.8.2.1, layout notes, findings 1-4). Run with stand-ins by test-layoutnote.m; then the wiring. MSBD_TEST_SRC: another statusbar folder, to see
# these checks fail on an old one (what is not in it is stood in for by what that code did: no layout saved, none put back, in memory only, nothing forgotten).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SRC=${MSBD_TEST_SRC:-../statusbar}
S=$SRC/StatusBar.x
H=$SRC/SMHome.h
fn() { awk -v s="$2" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$1"; }   # one function of a file, from its first line
cutfn() { awk -v s="$2" '!f && index($0, s) == 1 {f=1} f {print; n += gsub(/\{/, "{"); n -= gsub(/\}/, "}"); if (n <= 0) exit}' "$1"; }   # the same, by its braces (a one-line function too)
has() { grep -qF "$2" "$1"; }
{
  cp "$SRC/TurnPlace.h" "$W/TurnPlace.h"
  has "$W/TurnPlace.h" 'MSBDTurnLayoutNamed' || echo 'static inline int MSBDTurnLayoutNamed(const char *name) { (void)name; return -1; }   // (not in this source)'
  grep -F 'static const void *kStageLayoutNameKey = &kStageLayoutNameKey;' "$S"
  if has "$S" 'static NSString *DMStageLayoutNote(UIView *st) {'; then
    fn "$S" 'static NSString *DMStageLayoutNote(UIView *st) {'
    fn "$S" 'static void DMStageSetLayoutNote(UIView *st, id saved) {'
  else
    echo 'static NSString *DMStageLayoutNote(UIView *st) { (void)st; return nil; }   // (not in this source)'
    echo 'static void DMStageSetLayoutNote(UIView *st, id saved) { (void)st; (void)saved; }   // (not in this source)'
  fi
  # the window state's entry for one window, as DMSaveWindowState makes it (its lines from the layout noted to the entry added)
  echo 'static NSDictionary *DMTestSavedEntry(UIView *st, NSString *b, CGRect f, BOOL minimized) {'
  echo '    NSMutableArray *wins = [NSMutableArray array];'
  fn "$S" 'static void DMSaveWindowState(void) {' | grep -F -e 'NSString *lay = DMStageLayoutNote(st);' -e '[wins addObject:'
  echo '    return wins.lastObject;'
  echo '}'
  # what the restore does with the saved entry where it places the window (DMRestoreStep's lines that name the entry's layout)
  echo 'static void DMTestRestorePlaced(UIView *stage, NSDictionary *w) {'
  fn "$S" 'static void DMRestoreStep(NSArray *wins, NSUInteger i, NSDictionary *state, int waited) {' | grep -F 'w[@"layout"]' || true
  echo '}'
  # Stage Manager: the notes, the state file, a closed window's records
  grep -F 'static NSMutableDictionary<NSString *, NSString *> *gSMTurnLayout;' "$S"
  grep -F 'static NSMutableDictionary<NSString *, NSDictionary<NSString *, NSValue *> *> *gSMTurnFrames;' "$S"
  grep -F 'static NSMutableDictionary<NSString *, NSValue *> *gSMTurnPlaced;' "$S"
  echo 'static void DMSMStateWrite(void);'
  # (1.8.4 F2: the Dock's room the windows are placed for, as the source has it; an older source: none)
  if has "$S" 'static int gDMWindowsRoomPending = -1;'; then grep -F 'static int gDMWindowsRoomPending = -1;' "$S"; grep -F 'static int DMDockRoomSaved(void) { return' "$S"
  else echo 'static int gDMWindowsRoomPending = -1;   // (not in this source)'; echo 'static int DMDockRoomSaved(void) { return -1; }   // (not in this source: none saved)'; fi
  if has "$S" 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) {'; then
    grep -F 'static NSDictionary<NSString *, NSString *> *gSMTurnLayoutWritten;' "$S"
    fn "$S" 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayoutsFrom(NSDictionary *st) {'
    fn "$S" 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) {'
  else
    echo 'static NSDictionary<NSString *, NSString *> *gSMTurnLayoutWritten;   // (not in this source)'
    echo 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayoutsFrom(NSDictionary *st) { (void)st; return [NSMutableDictionary dictionary]; }   // (not in this source)'
    echo 'static NSMutableDictionary<NSString *, NSString *> *DMSMTurnLayouts(void) { if (!gSMTurnLayout) gSMTurnLayout = [NSMutableDictionary dictionary]; return gSMTurnLayout; }   // (not in this source: in memory only)'
  fi
  fn "$SRC/SMFitPlan.h" 'static NSSet<NSString *> *DMSMFitClosedKeys(id<NSFastEnumeration> keys, NSSet<NSString *> *present, NSSet<NSString *> *pending) {'
  if has "$S" 'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) {'; then
    fn "$S" 'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) {'
    fn "$S" 'static NSSet<NSString *> *DMSMWindowKeysIn(NSArray *stages) {'
    grep -F 'static BOOL gSMTurnStartSettled = NO;' "$S"
    fn "$S" 'static void DMSMTurnForgetClosed(void) {'
  else
    echo 'static void DMSMTurnForget(NSSet<NSString *> *keys, NSString *why) { (void)keys; (void)why; }   // (not in this source: nothing forgotten)'
    echo 'static BOOL gSMTurnStartSettled = NO;   // (not in this source)'
    echo 'static void DMSMTurnForgetClosed(void) { }   // (not in this source: a closed window'"'"'s note stays)'
  fi
  if has "$S" 'static dispatch_queue_t DMSMStateWriteQueue(void) {'; then fn "$S" 'static dispatch_queue_t DMSMStateWriteQueue(void) {'
  else echo 'static dispatch_queue_t DMSMStateWriteQueue(void) { static dispatch_queue_t q; static dispatch_once_t once; dispatch_once(&once, ^{ q = dispatch_queue_create("old", DISPATCH_QUEUE_SERIAL); }); return q; }   // (not in this source: written at once)'; fi
  fn "$S" 'static void DMSMStateWrite(void) {'
  fn "$S" 'static void DMSMForgetApp(NSString *bundle) {'
  # (1.8.4 F2 and the review of its fixes, H1 and M1: the start's step for Stage Manager, and Stage Manager's start tick, as the source has them)
  if has "$S" 'static BOOL DMDockRoomChangedSinceSave(void) {'; then cutfn "$S" 'static BOOL DMDockRoomChangedSinceSave(void) {'
  else echo 'static BOOL DMDockRoomChangedSinceSave(void) { return NO; }   // (not in this source)'; fi
  if has "$S" 'static void DMSMRoomWaitLift(void) {'; then   # (1.8.4.1 item 8: the windows placed while the room waits)
    grep -F 'static NSMutableDictionary<NSString *, id> *gSMRoomWaitLayouts;' "$S"
    fn "$S" 'static NSDictionary<NSString *, NSString *> *DMSMRoomWaitMerged(NSDictionary<NSString *, NSString *> *notes) {'
    fn "$S" 'static void DMSMRoomWaitLift(void) {'
  fi
  if has "$S" 'static void DMDockRoomAfterStartSMTry(int tries) {'; then
    echo 'static void DMDockRoomAfterStartSMTry(int tries);'
    fn "$S" 'static void DMDockRoomAfterStartSM(void) {'
    fn "$S" 'static void DMDockRoomAfterStartSMTry(int tries) {'
  else echo 'static void DMDockRoomAfterStartSMTry(int tries) { (void)tries; }   // (not in this source: nothing follows the room)'; echo 'static void DMDockRoomAfterStartSM(void) { }   // (not in this source)'; fi
  if has "$H" 'static void DMSMRoomTick(void) {'; then fn "$H" 'static void DMSMRoomTick(void) {'
  else   # (1.8.4 b had its tick's room step inline in DMSMRestoreDesktopTick: it is stood in for by what it did; an older source: none)
    if has "$H" 'if (!DMSMFree()) gDMWindowsRoomPending = -1;'; then echo 'static void DMSMRoomTick(void) { if (gDMWindowsRoomPending >= 0 && (!gSMHomeOn || !DMSMFree()) && !DMSMFree()) gDMWindowsRoomPending = -1; }   // (1.8.4 b, inline)'
    else echo 'static void DMSMRoomTick(void) { }   // (not in this source)'; fi
  fi
} > "$W/layoutnote-gen.h"
cp "$SRC/SMWindowKey.h" "$W/SMWindowKey.h"
clang -fobjc-arc -Wall -Wno-unused-function -Wno-unused-variable -I"$W" -framework Foundation -framework CoreGraphics -o "$W/t" test-layoutnote.m
fails=0
"$W/t" "$W/state.plist" || fails=1
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
save() { fn "$S" 'static void DMSaveWindowState(void) {'; }
write() { fn "$S" 'static void DMSMStateWrite(void) {'; }
note() { fn "$S" 'static void DMSMTurnNote(void) {'; }
check "the window state saves the layout noted: each entry from DMStageLayoutNote, also of a window on another desktop or minimized (every one of DMAerialStagesAll)" \
  "save | grep -qF 'NSString *lay = DMStageLayoutNote(st);' && save | grep -qF '@\"layout\": lay}' && save | grep -c 'for (UIView \*st in DMAerialStagesAll())' | grep -q 2"
check "  ... a change of the note alone is saved at the next tick (the save's signature counts it)" \
  "save | grep -qF '[objc_getAssociatedObject(st, kStageIntentKey) hash] + [objc_getAssociatedObject(st, kStageLayoutNameKey) hash];'"
check "the restore puts it back where it places the window, after the place and the minimize, before the next app (one away or minimized is not noted again until it is shown)" \
  "fn $S 'static void DMRestoreStep(NSArray *wins, NSUInteger i, NSDictionary *state, int waited) {' | awk '/else DMAerialMoveStage\(stage, place, nil\);/{a=NR} /if \(minimizedAgain\) \{ Class mwc = objc_getClass\(\"AXWindowView\"\);/{b=NR} /DMStageSetLayoutNote\(stage, w\[@\"layout\"\]\);/{c=NR} /DMRestoreAfterScene\(bundle, 0, \^\{ DMRestoreStep\(wins, i \+ 1, state, 0\); \}\);   \/\/ \(one app/{d=NR} END{exit !(a && b && c && d && a < b && b < c && c < d)}'"
check "N1 (regression 1.8.4, iPad 2 Aerial 5.1): a window the restore minimizes again keeps the place it is given there as where it comes back, Aerial's remembered frame with it and no hold (opened later it came back at the frame Aerial's fit-to-screen pass had shrunk it to, out of its layout)" \
  "fn $S 'static void DMRestoreStep(NSArray *wins, NSUInteger i, NSDictionary *state, int waited) {' | awk '/DMSetStageFrameSafe\(stage, place\)/{a=NR} /if \(minimizedAgain\) DMKeepStagePlace\(stage, place\);/{b=NR} /DMMinimizeStage\(stage\);/{c=NR} END{exit !(a && b > a && c > b)}' \
   && fn $S 'static void DMKeepStagePlace(UIView *stage, CGRect frame) {' | grep -qF 'DMAerial5SyncState(stage, frame);' \
   && fn $S 'static void DMKeepStagePlace(UIView *stage, CGRect frame) {' | grep -qF 'objc_setAssociatedObject(stage, kStageIntentKey, [NSValue valueWithCGRect:frame], OBJC_ASSOCIATION_RETAIN_NONATOMIC);' \
   && ! fn $S 'static void DMKeepStagePlace(UIView *stage, CGRect frame) {' | grep -qF 'DMA5HoldStageAt' \
   && fn $S 'static void DMSetStageIntent(UIView *stage, CGRect frame) {' | awk '/DMA5HoldStageAt\(stage, frame/{a=NR} /DMKeepStagePlace\(stage, frame\);/{b=NR} END{exit !(a && b > a)}'"
check "  ... the notes are taken from the windows on screen only, as before (the rule that leaves a window not shown with what it had)" \
  "fn $S 'static void DMNoteWindowLayouts(void) {' | grep -qF 'NSArray<UIView *> *stages = DMAerialStages();' && fn $S 'static void DMNoteWindowLayouts(void) {' | grep -qF 'if (st.hidden || DMStageMinimized(st) ||'"
check "Stage Manager: the layouts written with the state file when they change, read once at the start (both readers, the turn and the Position change, ask the accessor)" \
  "note | grep -qF 'if (![gSMTurnLayout isEqualToDictionary:gSMTurnLayoutWritten ?: @{}]) DMSMStateWrite();' \
   && note | grep -qF '(void)DMSMTurnLayouts();' && note | grep -qF 'if (!gSMTurnFrames) gSMTurnFrames = [NSMutableDictionary dictionary];' \
   && grep -qF 'NSDictionary<NSString *, NSString *> *layouts = [DMSMRoomWaitMerged(DMSMTurnLayouts()) copy];   // (the shape before the turn' $S \
   && fn $S 'static void DMDockPositionMoved(NSDictionary<NSString *, NSString *> *layouts) {' | grep -qF 'NSMutableDictionary<NSString *, NSString *> *noted = [DMSMTurnLayouts() mutableCopy];' \
   && ! grep -qE '\[gSMTurnLayout (copy\] \?: @\{\}|mutableCopy\] \?:)' $S"
check "review findings 1, 3, 4: the writer writes the notes as memory has them (no look at the stages of its own), made on the main thread (a call from another thread sent there), written on a serial queue" \
  "write | grep -qF 'if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMSMStateWrite(); }); return; }' && write | grep -qF 'gSMTurnLayoutWritten = [DMSMTurnLayouts() copy];' \
   && write | grep -qF 'dispatch_async(DMSMStateWriteQueue(), ^{ [out writeToFile:path atomically:YES]; });' && ! write | grep -qE 'DMSMRecentStages|DMSMKeysGone|DMSMStageItemsMap'"
check "review findings 1, 2: a closed window's records go with it, memory and the file together -- after the start (where the minimized marks of gone windows go), when the stages show it closed (nothing moving), at its app's force quit, past 64" \
  "fn $H 'static void DMSMRestoreDesktopTick(void) {' | awk '/DMSMMinimizedDrop\(gone\);/{a=NR} /gSMTurnStartSettled = YES;/{b=NR} /if \(notesHere\) DMSMTurnForget\(DMSMFitClosedKeys\(\[NSSet setWithArray:DMSMTurnLayouts\(\).allKeys\], notesHere, nil\), @\"after the start\"\);/{c=NR} END{exit !(a && b && c && a < b && b < c)}' \
   && grep -qF 'if (!turnPending && !DMSwitcherVisible() && !gMSWSwitching && !DMSMGestureLive() && !DMSMWorkspaceBusy()) DMSMTurnForgetClosed();' $S \
   && fn $S 'static void DMSMForgetApp(NSString *bundle) {' | grep -qF 'DMSMTurnForget(mine, @\"its app quit\");' \
   && note | grep -qF 'if (present) DMSMTurnForget(DMSMFitClosedKeys(keys, present, nil), @\"more than 64 windows kept\");' && note | grep -qF 'gSMTurnStartSettled = YES;'"
check "no em dashes in the new files" "! grep -n \$'\\xe2\\x80\\x94' test-layoutnote.m test-layoutnote.sh"
[ $fails = 0 ] && echo "test-layoutnote: all pass" || { echo "test-layoutnote: FAILED"; exit 1; }
