#!/bin/bash
# Mac test of sticky notes on other Home Screen pages (1.8.8.2 F36): the rules (common/StickyNotes.h, test-stickypages.m) and site checks: a page's
# own layer of notes (made only for a page that holds notes), which page a note shows on and where its page went (a hidden page's notes hide with it), the press, the tap and the
# typing on any page, the turn at the screen's side (only through the root folder's own checked call) with the note riding in our menu window, Move
# to Page (which turns the Home Screen to the note's page, KT 22 Nov), Trash and Put Back keeping the page, page 1's placer and layout for page 1's notes only, jiggle mode, the desktop leaving its page.
# MSB_D, MSB_DN, MSB_N point it at copies of Desktop.h, DesktopNotes.h and StickyNotes.h.
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=1; fi; }
fnf() { awk -v s="$1" 'index($0, s) == 1 {f=1} f {print} f && /^}/ {exit}' "$2"; }
D=${MSB_D:-../statusbar/Desktop.h}; DN=${MSB_DN:-../statusbar/DesktopNotes.h}; N=${MSB_N:-../common/StickyNotes.h}; CR=crashmap-rules.txt
mkdir -p "$W/common" "$W/tools"; cp "$N" "$W/common/StickyNotes.h"; cp test-stickypages.m "$W/tools/"
clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -framework CoreGraphics -o "$W/tsp" "$W/tools/test-stickypages.m"
"$W/tsp" || fails=1
cls() { awk -v c="@implementation $1" 'index($0, c) == 1 {f=1} f && /^@end/ {exit} f' "$DN"; }
m() { fnf "$1" "$DN"; }
# ---- a page's layer ----
check "another page's layer (DMNotesPageView): its hit test answers a note or nil, so the page's empty space and app icons stay iPadOS's" \
  "cls DMNotesPageView | grep -qF 'for (UIView *v in [self.subviews reverseObjectEnumerator]) if ([v isKindOfClass:[DMNoteView class]] && !v.hidden && v.alpha > 0.01 && CGRectContainsPoint(v.frame, p)) return v;' && cls DMNotesPageView | grep -qxF '    return nil;'"
LF=$(m '- (UIView *)dm_noteLayerFor:(NSUInteger)page make:(BOOL)make {')
check "  ... made only when asked to (a note goes there), at the back of that page's icon list, framed as its page, with a tap named dm.note.tap judged as the desktop's" \
  "printf '%s\n' \"\$LF\" | grep -qF 'if (page == 0 || page >= _notes.pageIds.count) return _notes.layer;' && printf '%s\n' \"\$LF\" | grep -qF 'if (!l && make) {' \
   && printf '%s\n' \"\$LF\" | grep -qF 'if (l && l.superview != list) { [list insertSubview:l atIndex:0]; DMStickySetFrame(l, DMDesktopPageFrameIn(list), \"a page'\"'\"'s layer of notes\"); }' \
   && printf '%s\n' \"\$LF\" | grep -qF 'tap.delegate = self; tap.name = @\"dm.note.tap\";' && printf '%s\n' \"\$LF\" | grep -qF 'initWithTarget:self action:@selector(dm_noteTap:)' \
   && grep -qF 'if ([g.name isEqualToString:@\"dm.desktop.tap\"] || [g.name isEqualToString:@\"dm.note.tap\"]) { _lastTapPointer = DMDesktopPointerTouch(t, nil); [self dm_noteTapDown:t]; }' '$D'"
RP=$(m '- (void)dm_noteReadPages {')
check "the pages: the shown icon lists of page 1's scroll view in page order (right to left too), page 1 the desktop's own list, each with its own id -- else other pages are off" \
  "printf '%s\n' \"\$RP\" | grep -qF 'Class lc = objc_getClass(\"SBIconListView\");' && printf '%s\n' \"\$RP\" | grep -qF 'BOOL rtl = scroll.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;' \
   && printf '%s\n' \"\$RP\" | grep -qF 'if (lists.firstObject != list || lists.count < 2) ok = NO;' && printf '%s\n' \"\$RP\" | grep -qF 'NSString *i = DMStickyPageIdOfList(l); if (!i || [ids containsObject:i]) { ok = NO; break; }' \
   && printf '%s\n' \"\$RP\" | grep -qF '_notes.pageIds = ok ? ids : nil;'"
PI=$(m '__attribute__((noinline)) static NSString *DMStickyPageIdOfList(UIView *list) {')
check "  ... a page's id: its icon list's model's uniqueIdentifier, only where both answer as object getters (DMStickyObjGet), a string of a key's length" \
  "printf '%s\n' \"\$PI\" | grep -qF '@try { u = DMStickyObjGet(DMStickyObjGet(list, @\"model\"), @\"uniqueIdentifier\"); } @catch (NSException *x) { u = nil; }' \
   && printf '%s\n' \"\$PI\" | grep -qF 'return MSBDStickyPageKey(u) ? u : nil;' && ! printf '%s\n' \"\$PI\" | grep -qF 'objc_msgSend'"
# (1.8.8.2 review: the pages' SpringBoard getters -- a list's model, a model's id, the root folder's folder and its lists -- are called only as
#  getters of an object, their shape checked as the page turn's and -isHidden are: DMStickyObjGet, cut out of DesktopNotes.h and run here)
fnf '__attribute__((noinline)) static id DMStickyObjGet(id obj, NSString *name) {' "$DN" > "$W/objget.h"
cat > "$W/objget.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>
#include "objget.h"
static int ran = 0;
@interface TModel : NSObject @end
@implementation TModel
- (NSString *)uniqueIdentifier { return @"MSB-TEST-page"; }
@end
@interface TList : NSObject @end
@implementation TList
- (id)model { return [TModel new]; }
- (long long)count { ran = 1; return 7; }
- (BOOL)isHidden { ran = 1; return YES; }
- (id)withArg:(id)a { ran = 1; return a; }
- (void (^)(void))block { ran = 1; return ^{}; }
@end
#define T(c, msg) do { if (c) printf("PASS    %s\n", msg); else { printf("FAIL    %s\n", msg); fails = 1; } } while (0)
int main(void) { @autoreleasepool {
    int fails = 0;
    TList *l = [TList new];
    T([DMStickyObjGet(l, @"model") isKindOfClass:[TModel class]] && [DMStickyObjGet(DMStickyObjGet(l, @"model"), @"uniqueIdentifier") isEqualToString:@"MSB-TEST-page"], "... an object's getter: called, its object back");
    ran = 0; T(!DMStickyObjGet(l, @"count") && !DMStickyObjGet(l, @"isHidden") && !ran, "... a number's or a BOOL's getter: never called, nil");
    ran = 0; T(!DMStickyObjGet(l, @"withArg:") && !DMStickyObjGet(l, @"block") && !ran, "... a method with an argument, or one that gives a block: never called, nil");
    T(!DMStickyObjGet(l, @"noSuchGetter") && !DMStickyObjGet(nil, @"model"), "... a getter that is not there, or no object: nil");
    return fails;
} }
EOF
check "the pages' SpringBoard getters (a list's model and id, the root folder's folder and lists) are called only as getters of an object: no argument, an object back (DMStickyObjGet)" \
  "[ -s '$W/objget.h' ] && clang -O2 -fobjc-arc -Wall -Wno-unused-function -framework Foundation -I'$W' -o '$W/objget' '$W/objget.m' && '$W/objget'"
ST=$(m '- (void)dm_noteStoreChanged {')
check "each note's view in its page's layer (page 1's when its page went; none while it is hidden), on every store pass, a new view too" \
  "printf '%s\n' \"\$ST\" | grep -qF '[self dm_noteReadPages];' && [ \$(printf '%s\n' \"\$ST\" | grep -cF '[self dm_notePlace:v of:e];') = 2 ] \
   && printf '%s\n' \"\$ST\" | grep -qF '[self dm_notePlace:v of:e];   // (its page' && m '- (NSUInteger)dm_notePageOf:(NSDictionary *)e {' | grep -qF 'return MSBDStickyPageOrHidden(e[@\"page\"], _notes.pageIds, _notes.hiddenIds);'"
PL=$(m '- (void)dm_notePlace:(DMNoteView *)v of:(NSDictionary *)e {')
check "  ... a hidden page's notes hide with it (KT 22 Nov): their views out of every layer while it is hidden, back in its layer when it is shown again" \
  "printf '%s\n' \"\$PL\" | grep -qF 'if (page == MSBD_NOTE_PAGE_HIDDEN) { if (v.superview) { [v removeFromSuperview];' && printf '%s\n' \"\$PL\" | grep -qF 'UIView *home = [self dm_noteLayerFor:page make:YES];' \
   && printf '%s\n' \"\$PL\" | grep -qF 'if (v.superview != home) { [home addSubview:v];' && m '- (void)dm_notePagesTick {' | grep -qF 'if (moved) { for (NSDictionary *e in gNotes) [self dm_notePlace:_notes.views[e[@\"id\"]] of:e];' \
   && m '- (void)dm_notePagesTick {' | grep -qF '|| !(hiddenBefore == _notes.hiddenIds || [hiddenBefore isEqualToSet:_notes.hiddenIds]);' && m '- (void)dm_noteReadPages {' | grep -qF '_notes.hiddenIds = list ? DMStickyHiddenPageIds() : nil;'"
HI=$(m '__attribute__((noinline)) static NSSet<NSString *> *DMStickyHiddenPageIds(void) {')
check "  ... the hidden pages: the root folder's own lists (-folder, -lists: object getters) whose -isHidden (no argument, a BOOL, checked) says so; any other shape: nil (page 1, never lost)" \
  "printf '%s\n' \"\$HI\" | grep -qF '@try { lists = DMStickyObjGet(DMStickyObjGet(rfc, @\"folder\"), @\"lists\"); } @catch (NSException *x) { return nil; }' && printf '%s\n' \"\$HI\" | grep -qF 'if (![lists isKindOfClass:[NSArray class]]) return nil;' \
   && printf '%s\n' \"\$HI\" | grep -qF 'id u = DMStickyObjGet(m, @\"uniqueIdentifier\");' && ! printf '%s\n' \"\$HI\" | grep -qF 'id (*)(id, SEL))objc_msgSend' \
   && printf '%s\n' \"\$HI\" | grep -qF 'if (!g || g.numberOfArguments != 2 || (strcmp(g.methodReturnType, \"B\") && strcmp(g.methodReturnType, \"c\"))) return nil;' && printf '%s\n' \"\$HI\" | grep -qF '} @catch (NSException *x) { return nil; }'"
PT=$(m '- (void)dm_notePagesTick {')
check "every tick: nothing at all unless a note has a page or a layer is there; a layer whose page went (or is page 1 now) or that holds no note gives its notes to page 1 and goes" \
  "printf '%s\n' \"\$PT\" | grep -qF 'if (!wanted) return;' && printf '%s\n' \"\$PT\" | grep -qF 'if (page == NSNotFound || page == 0 || empty) {' \
   && printf '%s\n' \"\$PT\" | grep -qF 'if (e) [self dm_notePlace:(DMNoteView *)v of:e];' && printf '%s\n' \"\$PT\" | grep -qF 'if (v.superview == l) [_notes.layer addSubview:v];   // (never left in a layer that goes)' \
   && printf '%s\n' \"\$PT\" | grep -qF '[l removeFromSuperview]; [_notes.pageLayers removeObjectForKey:pid];'"
check "  ... the rest put back in their lists (SpringBoard makes lists again), hidden in jiggle mode and with the switch off, laid out again when their area, icons or notes changed while their page shows" \
  "printf '%s\n' \"\$PT\" | grep -qF 'if (l.superview != list) { [list insertSubview:l atIndex:0];' && printf '%s\n' \"\$PT\" | grep -qF 'BOOL shown = DMStickyShown() && !_editing;' \
   && printf '%s\n' \"\$PT\" | grep -qF 'if (l.hidden != !shown) l.hidden = !shown;' && printf '%s\n' \"\$PT\" | grep -qF 'if (!shown || ![self dm_notePageShowing:page]) continue;' \
   && printf '%s\n' \"\$PT\" | grep -qF 'if ([_notes.pageLaidOut[pid] isEqualToString:sig]) continue;' && printf '%s\n' \"\$PT\" | grep -qF '[self dm_noteLayoutPage:page layer:l];' \
   && m '- (void)dm_noteTick {' | grep -qF '[self dm_notePagesTick];'"
check "  ... a page's notes keep clear of that page's own app icons, widgets and page dots (-dm_occupiedIn:into:, page 1's -dm_occupied the same code)" \
  "m '- (void)dm_noteLayoutPage:(NSUInteger)page layer:(UIView *)layer {' | grep -qF 'NSArray<NSValue *> *occ = [self dm_occupiedIn:[self dm_noteListOfPage:page] into:layer];' \
   && grep -qF -e '- (NSArray<NSValue *> *)dm_occupied { return [self dm_occupiedIn:_list into:self]; }' '$D' && fnf '- (NSArray<NSValue *> *)dm_occupiedIn:(UIView *)list into:(UIView *)space {' '$D' | grep -qF 'for (UIView *v in list.subviews) if (v != self'"
check "page 1's icons' placer and page 1's layout take page 1's notes only" \
  "m '- (void)dm_noteTakeInto:(DMPlacer *)pl {' | grep -qF 'if (v.superview == _notes.layer && v != _notes.dragging) DMPlacerTake(pl, v.frame);' \
   && m '- (void)dm_noteLayoutIn:(CGRect)area {' | grep -qF 'if (!v || v == _notes.dragging || v.superview != _notes.layer) continue;'"
# ---- press, tap, typing on any page ----
check "a press on a note of any page is followed (one of ours by its id, not only inside the desktop's view); its tap is judged in its own layer" \
  "m '- (BOOL)dm_noteTrackBegin:(UIView *)at at:(CGPoint)sp {' | grep -qF '_notes.views[((DMNoteView *)at).noteId ?: @\"\"] == at && !at.hidden' && ! m '- (BOOL)dm_noteTrackBegin:(UIView *)at at:(CGPoint)sp {' | grep -q 'isDescendantOfView:self' \
   && m '- (void)dm_noteTap:(UITapGestureRecognizer *)g {' | grep -qF 'BOOL other = [g.view isKindOfClass:[DMNotesPageView class]];' && m '- (void)dm_noteTap:(UITapGestureRecognizer *)g {' | grep -qF 'DMNoteView *v = (DMNoteView *)(other ? [g.view hitTest:p withEvent:nil] : [self dm_noteHitAt:p]);'"
check "  ... VoiceOver and the focus guides find a note of any page" \
  "grep -qF -e '- (BOOL)accessibilityActivate { DMDesktop *d = gDesktop; return d && [d dm_noteAXActivate:self]; }' '$DN' && m '- (BOOL)dm_noteAXActivate:(UIView *)v {' | grep -qF '_notes.views[((DMNoteView *)v).noteId ?: @\"\"] != v' \
   && m '- (BOOL)dm_noteAtScreen:(CGPoint)sp {' | grep -qF 'for (DMNotesPageView *l in _notes.pageLayers.allValues) if (l.window && [l hitTest:[l convertPoint:sp fromCoordinateSpace:scr] withEvent:nil]) return YES;'"
check "every screen conversion of a note's own place goes through its layer, never the desktop's view: the typing's fit, the resize, the move, the lift, the drag, the drop" \
  "ok=1; for f in '- (void)dm_noteFit {' '- (void)dm_noteResize:(UIPanGestureRecognizer *)g {' '- (void)dm_noteMove:(UIPanGestureRecognizer *)g {' '- (BOOL)dm_noteLiftAt:(CGPoint)sp {' '- (void)dm_noteDragTo:(CGPoint)sp {' '- (void)dm_noteDropAt:(CGPoint)sp {' '- (NSArray<NSValue *> *)dm_noteOccupiedIn:(UIView *)host {'; do m \"\$f\" | grep -qE '\\[self convert(Rect|Point):' && ok=0; done; [ \$ok = 1 ] \
   && m '- (void)dm_noteFit {' | grep -qF 'UIView *lay = nv.superview ?: self;' && m '- (void)dm_noteResize:(UIPanGestureRecognizer *)g {' | grep -qF 'UIView *lay = [self dm_noteLayerOfEditor];'"
check "  ... the typing ends when its page no longer shows (page 1's or another's); its note comes to the front in its own layer" \
  "m '- (void)dm_noteTick {' | grep -qF 'else if (![self dm_notePageShowing:[self dm_notePageOfLayer:[self dm_noteLayerOfEditor]]]) why = @\"its page no longer shows\";' && m '- (void)dm_noteBegin:(DMNoteView *)nv at:(CGPoint)sp {' | grep -qF '[nv.superview bringSubviewToFront:nv];'"
# ---- the turn at the screen's side ----
check "a dragged note at the screen's side: the side by MSBDStickyEdgeSide (only with two pages or more, never in jiggle mode), the time by MSBDStickyEdgeTurnDue, looked at every 0.1 s while it stays" \
  "m '- (void)dm_noteDragTo:(CGPoint)sp {' | grep -qF '[self dm_noteEdgeAt:sp];' && m '- (void)dm_noteEdgeAt:(CGPoint)sp {' | grep -qF 'if (_notes.pageIds.count >= 2 && _notes.dragging && !_editing) {' \
   && m '- (void)dm_noteEdgeAt:(CGPoint)sp {' | grep -qF 'side = MSBDStickyEdgeSide(sp.x,' && m '- (void)dm_noteEdgeTick {' | grep -qF 'if (MSBDStickyEdgeTurnDue(CACurrentMediaTime() - _notes.edgeSince, _notes.edgeTurns)) {' \
   && m '- (void)dm_noteEdgeTick {' | grep -qF '(int64_t)(0.1 * NSEC_PER_SEC)'"
check "  ... the turn: only the root folder's own -setCurrentPageIndex:animated: (its index getters and that call checked: q; q, B), to MSBDStickyTurnTarget's page; never a scroll offset written" \
  "m '- (void)dm_noteEdgeTick {' | grep -qF 'long to = rfc ? MSBDStickyTurnTarget(cur, _notes.edgeSide, scroll.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft, first, last) : -1;' \
   && m '- (void)dm_noteEdgeTick {' | grep -qF 'DMStickyTurnTo(rfc, to);' && m '__attribute__((noinline)) static id DMStickyRootFolder(void) {' | grep -qF 'if (!m || m.numberOfArguments != 2 || strcmp(m.methodReturnType, \"q\")) return nil;' \
   && m '__attribute__((noinline)) static id DMStickyRootFolder(void) {' | grep -qF 'if (!m || m.numberOfArguments != 4 || strcmp([m getArgumentTypeAtIndex:2], \"q\") || strcmp([m getArgumentTypeAtIndex:3], \"B\")) return nil;' \
   && ! grep -qE 'setContentOffset|contentOffset *=' '$DN' && [ \$(grep -v '^//' '$DN' | grep -c 'setCurrentPageIndex:animated:') = 2 ]"
check "  ... from the first turn the note's picture rides in our menu window under the finger (no touches), the note hidden in its layer until let go" \
  "m '- (BOOL)dm_noteRide {' | grep -qF 'UIView *host = DMMenuHost();' && m '- (BOOL)dm_noteRide {' | grep -qF 'rd.userInteractionEnabled = NO; rd.isAccessibilityElement = NO;' && m '- (BOOL)dm_noteRide {' | grep -qF '_notes.rider = rd; v.hidden = YES;' \
   && m '- (void)dm_noteStoreChanged {' | grep -qF 'v.hidden = _notes.rider && v == _notes.dragging;'"
DR=$(m '- (void)dm_noteDropAt:(CGPoint)sp {')
check "  ... let go: on the page its last turn went to (MSBDStickyDropPage: also mid slide, as on iPadOS 17.5.1; the one it came from when no page turned), placed clear of that page's icons, its page key set (none on page 1), saved" \
  "printf '%s\n' \"\$DR\" | grep -qF 'NSUInteger page = rd ? MSBDStickyDropPage(turnedTo, [self dm_notePageNow], _notes.pageLists.count) : [self dm_notePageOfLayer:from];' \
   && printf '%s\n' \"\$DR\" | grep -qF 'long turnedTo = _notes.turnedTo; _notes.turnedTo = -1;' && m '- (void)dm_noteEdgeTick {' | awk '/DMStickyTurnTo\(rfc, to\);/{a=NR} /_notes.turnedTo = to - first;/{b=NR} END{exit !(a && b == a + 1)}' \
   && m '- (BOOL)dm_noteLiftAt:(CGPoint)sp {' | grep -qF '_notes.turnedTo = -1;' && printf '%s\n' \"\$DR\" | grep -qF 'UIView *layer = rd ? [self dm_noteLayerFor:page make:YES] : from;' \
   && printf '%s\n' \"\$DR\" | grep -qF 'NSArray<NSValue *> *occ = layer == _notes.layer ? [self dm_occupied] : [self dm_occupiedIn:[self dm_noteListOfPage:page] into:layer];' \
   && printf '%s\n' \"\$DR\" | grep -qF 'if (key) e[@\"page\"] = key; else [e removeObjectForKey:@\"page\"];' && printf '%s\n' \"\$DR\" | grep -qF 'DMStickyChanged(0.3);' && printf '%s\n' \"\$DR\" | grep -qF '[rd removeFromSuperview]; v.hidden = NO;'"
# ---- every page's notes against the free area it settled at (1.8.8.2, seen on iPadOS 17.5.1) ----
TK=$(fnf '- (void)dm_tick {' "$D")
check "the desktop's pass (page 1's notes and the icons) once the free area changed and held (MSBDStickyAreaSettled, in the tick's 1 s look), as another page's notes follow it when shown" \
  "printf '%s\n' \"\$TK\" | grep -qF 'if (MSBDStickyAreaSettled([self dm_area], &_areaSeen, &_areaSeenAt, _sigAt, _placedArea) && !_placeDirty) {' \
   && printf '%s\n' \"\$TK\" | awk '/_sigAt = CACurrentMediaTime\(\);/{a=NR} /MSBDStickyAreaSettled\(/{b=NR} /_placeDirty = YES;/{c=NR} /if \(_placeDirty && !_editing && \[self dm_pageShowing\]\) \[self setNeedsLayout\];/{d=NR} END{exit !(a && b > a && c > b && d > c)}' \
   && grep -qF 'CGRect _areaSeen; CFTimeInterval _areaSeenAt;' '$D' && m '- (void)dm_notePagesTick {' | grep -qF 'NSStringFromCGRect([self dm_area])'"
# ---- Move to Page ----
check "its menu: Move to Page with two pages or more (each page, its own ticked); there at the same spot or the nearest free place, its typing ended first, saved" \
  "m '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' | grep -qF 'if (_notes.pageIds.count >= 2) {' && m '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' | grep -qF 'if (i == here) a.state = UIMenuElementStateOn;' \
   && m '- (UIMenu *)dm_noteMenuFor:(DMNoteView *)v {' | grep -qF '[UIMenu menuWithTitle:@\"Move to Page\"' && m '- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {' | grep -qF 'if ([_notes.editor.noteId isEqualToString:noteId]) [self dm_noteEnd:@\"Move to Page\"];' \
   && m '- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {' | grep -qF 'CGRect anchor, f = DMStickyPlaceFit(DMStickyAtItsSize(e, v.frame, area), area, r, (int)occ.count, &anchor, noteId);' \
   && m '- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {' | grep -qF 'DMStickyChanged(0.3);'"
check "  ... and the Home Screen turns to that page with it (KT 22 Nov): after the note is placed and saved, only through the root folder's own checked call, MSBDStickyPageTurnIndex's page, never in jiggle mode" \
  "m '- (void)dm_noteToPage:(NSUInteger)page of:(NSString *)noteId {' | awk '/DMStickyChanged\(0.3\);/{a=NR} /\[self dm_noteShowPage:page\];/{b=NR} END{exit !(a && b > a)}' \
   && m '- (void)dm_noteShowPage:(NSUInteger)page {' | grep -qF 'id rfc = _editing ? nil : DMStickyRootFolder();' \
   && m '- (void)dm_noteShowPage:(NSUInteger)page {' | grep -qF 'long to = rfc ? MSBDStickyPageTurnIndex((long)page, (long)_notes.pageLists.count, first, last) : -1;' \
   && m '- (void)dm_noteShowPage:(NSUInteger)page {' | grep -qF 'DMStickyTurnTo(rfc, to);'"
# ---- Trash, the desktop leaving, the crash map ----
check "Move to Trash keeps the page as an attribute; Put Back and Undo put it back on that page while it is shown (else page 1: never into a hidden page)" \
  "m '__attribute__((noinline)) static void DMStickyTrash(NSMutableDictionary *e) {' | grep -qF 'if (ok && pageKey) ok = setxattr(tmp.fileSystemRepresentation, MSBD_NOTE_TRASH_PAGE_ATTR, pageKey.UTF8String, strlen(pageKey.UTF8String), 0, XATTR_NOFOLLOW) == 0;' \
   && m '__attribute__((noinline)) static void DMStickyPutBack(NSString *path, void (^done)(NSError *e)) {' | grep -qF 'if (pageKey && [gDesktop dm_notePageShownFor:pageKey]) e[@\"page\"] = pageKey;' \
   && m '- (BOOL)dm_notePageShownFor:(NSString *)key {' | grep -qF 'return p != MSBD_NOTE_PAGE_HIDDEN && p > 0;' && grep -qF '#define MSBD_NOTE_TRASH_PAGE_ATTR \"com.besiktasliseba.stickynote.page\"' '$N'"
check "the desktop taken off its page takes the other pages' layers with it (the next tick puts them back); New Sticky Note stays page 1's" \
  "fnf '- (void)dm_detach {' '$D' | awk '/\\[self dm_noteEnd:@\"the desktop was taken off its page\"\\];/{a=NR} /\\[self dm_notePagesOff\\];/{b=NR} END{exit !(a && b == a + 1)}' \
   && m '- (void)dm_notePagesOff {' | grep -qF 'for (DMNotesPageView *l in _notes.pageLayers.allValues) [l removeFromSuperview];' && m '- (void)dm_noteNewAt:(CGPoint)sp {' | grep -qF '[gNotes addObject:e];' && ! m '- (void)dm_noteNewAt:(CGPoint)sp {' | grep -q 'page'"
check "the crash map: another page's layer is the notes' (stickyNotes) by name" "grep -qF 'DMNote(View|TextView|Editor|sState|Bar|NameField|sPageView)[\\s(]' '$CR'"
[ $fails = 0 ] && echo "test-stickypages: all passed" || echo "test-stickypages: FAILED"
exit $fails
