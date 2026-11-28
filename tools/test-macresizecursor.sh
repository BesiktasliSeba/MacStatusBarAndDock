#!/bin/bash
# Mac test of macOS's resize pointers (1.8.9, F51): common/MacResizeCursor.h's rules and glyphs against macOS's own cursors
# (test-macresizecursor.m), then the sites as built -- MacPointer.x (pointeruid: the root fix of the beam rule, the record before iPadOS's update,
# the latch, the fact's note, the glyph on the arrow's layer), statusbar/ResizeFact.h and StatusBar.x (SpringBoard: the band's fact, on with the Mac
# pointer only, the 2 s check), the crash guard's piece, the Pointer page's words; F51b: our window engines' grips (the hover on the system gestures
# window, the takers, the front-most rule, the clears, the lease, the fade, the one-way rule; pointeruid's freshness and the latch's grace);
# Settings > Pointer > Mac Resize Pointers (1.8.9, KT 25 Nov: on by default on iPadOS 18, off on 15-17): its rule in the unit test (off: 1.8.8.4's
# look, compared with 1.8.8.4's own lines), its sites, and SpringBoard's half played with it off and on (test-macresizeswitch.m, Mac Catalyst):
# off installs nothing -- that test built on 1.8.9's ResizeFact.h before the switch must fail.
# Made-to-fail copies of the header and of the sites must fail.
# Q=1: quiet (failures only). argv[1]: a folder for the glyph sheet (optional).
set -e
cd "$(dirname "$0")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAILS=0
echo "== 1. the rules and the glyphs (test-macresizecursor.m)"
# (Mac Resize Pointers off: the look of 1.8.8.4, its own two lines cut out of that release's MacPointer.x; without that commit, the test's copy)
LOOKINC=()
if git -C .. show 182a8dc7:statusbar/macpointer/MacPointer.x 2>/dev/null | grep -E '^    BOOL (thin = !CGRectIsEmpty\(sb\)|systemShape = thin \|\| type == 4;)' > "$W/look1884.inc" \
   && [ "$(grep -c . "$W/look1884.inc")" = 2 ]; then LOOKINC=(-DLOOK1884_INC="\"$W/look1884.inc\""); fi
clang -fobjc-arc -Wall -Wextra -Wno-unused-function -Wno-unused-parameter -framework AppKit "${LOOKINC[@]}" -o "$W/tmrc" test-macresizecursor.m
if "$W/tmrc" ${1:+"$1"} > "$W/out.txt"; then grep -E "^(PASS|NOTICE|glyphs:|switch:)" "$W/out.txt"; else cat "$W/out.txt" | grep -E "FAIL|NOTICE|differs"; FAILS=$((FAILS + 1)); fi

sites() {   # sites <root>: 0 when every site is as built
python3 -I - "$1" <<'PY'
import sys, re
R = sys.argv[1]
def rd(p): return open(R + '/' + p, errors='replace').read()
M, S, F, C, P, H = rd('statusbar/macpointer/MacPointer.x'), rd('statusbar/StatusBar.x'), rd('statusbar/ResizeFact.h'), rd('tools/crashmap-rules.txt'), rd('macsettings/PointerSettings.x'), rd('common/MacResizeCursor.h')
def fn(src, head):
    i = src.find(head)
    if i < 0: return ''
    j = src.find('\n}', i)
    k = src.find('\n%end', i)
    ends = [e for e in (j, k) if e >= 0]
    return src[i:min(ends) + 2] if ends else src[i:]
def before(src, a, b): return a in src and b in src and src.find(a) < src.find(b)
fails = 0
def check(name, ok):
    global fails
    if not ok: fails += 1
    if not ok or not __import__('os').environ.get('Q'): print(('PASS  ' if ok else 'FAIL  ') + name)
up = fn(M, 'static void MPUpdate(PUIDPointerShapeView *view) {')
check('M1 MacPointer.x: the rules from common/MacResizeCursor.h', '#include "../../common/MacResizeCursor.h"' in M)
check('M2 the root fix: on 18 the beam only for a beam\'s shape (MSBDPointerBeamShape), on 15-17 any type 4 too (as before); never with arrows (MSBDPointerLook)',
      'look = MSBDPointerLook(beamShape, accessories, factHere, evidence, held);' in up
      and 'BOOL beamShape = MPBeamRuleFrom18() ? MSBDPointerBeamShape(type, sb.size.width, sb.size.height) : (MSBDPointerBeamShape(type, sb.size.width, sb.size.height) || type == 4);' in up
      and 'if (v < 0) v = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){18, 0, 0}] ? 1 : 0;' in fn(M, 'static BOOL MPBeamRuleFrom18(void) {')
      and 'BOOL systemShape = look == MSBD_PTR_BEAM;' in up and before(up, 'BOOL enabled = MPEnabled();', 'look = MSBDPointerLook('))
check('M3 the fact read only when there is one (nothing more at rest), the evidence from iPadOS\'s shape and arrows',
      'if (fact.kind && !held) {' in up and before(up, 'if (fact.kind && !held) {', 'factHere = (fact.display == 1) == !MPOnOwnDisplay(view);')
      and 'evidence = MSBDResizeEvidence(fact, type, sb.size.width, sb.size.height, n, known ? si->angles : NULL, known ? si->nAngles : 0);' in up)
check('M9 the arrows: none when the state\'s getter answers nil (B0 18.5); the views counted only when the state has no accessories at all, only with a fact, only as evidence, never over a beam',
      'i->count = known ? (int)acc.count : -1;' in fn(M, 'static MPStateInfo *MPRecordState(UIViewController *c, id state) {') and '*known = g.imp != NULL || g.ivar >= 0;' in M
      and 'int accessories = si && si->count > 0 ? si->count : 0;' in up and 'int n = known ? si->count : (!beamShape && ctl ? MPAccessoryViewsShown(ctl) : 0);' in up
      and up.count('MPAccessoryViewsShown(') == 1 and before(up, 'if (fact.kind && !held) {', 'MPAccessoryViewsShown('))
sps = fn(M, '- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error {')
check('M4 iPadOS\'s arrows and button recorded, and the latch stepped, BEFORE iPadOS\'s own update (MPUpdate runs inside it)',
      before(sps, 'MPStateInfo *si = MPResizeOn() ? MPRecordState((UIViewController *)self, state) : nil;', 'BOOL r = %orig;')
      and before(sps, 'MSBDResizeLatchStepAt(&gMPResizeLatch, si->pressed, gMPAutoHidden, si->shownWord != 0, MSBDResizeUnpack(si->shownWord), CACurrentMediaTime());', 'BOOL r = %orig;')
      and 'if (si && enabled && (systemShape || !sysHid)) si->shownWord = glyph && !MSBDResizeLatchGraceOnly(&gMPResizeLatch, now) ? MSBDResizePack(fact) : 0;' in up and 'gMPResizeShownWord' not in M
      and before(sps, 'if (![ownNow isKindOfClass:[UIView class]] || !MPHiddenBySystem(ownNow))', 'MSBDResizeLatchStepAt('))
check('M5 the state\'s change signature counts the arrows and the latch (the equal-shape early return never keeps a stale look)',
      '| (si ? ((NSUInteger)((si->count + 1) & 0xF) << 10) | (gMPResizeLatch.live ? (1u << 14) : 0) : 0);' in sps)
check('M6 the glyph on the arrow\'s own layer: the path and the shadow path swapped together by the glyph\'s key (Core Animation copies a path: never compared by pointer), "settled" only with it',
      'a.path = wantPath; a.shadowPath = wantPath;' in up and '&& hasKey == wantKey)' in up and 'if (hasKey != wantKey) {' in up and 'CGPathRef wantPath = glyph ?: MPCursorPath();' in up
      and 'objc_setAssociatedObject(a, kMPGlyphKeyKey, @(wantKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);' in up and not re.search(r'\.path\s*[!=]=', M)
      and 'CGPathRef glyph = (want && look == MSBD_PTR_RESIZE) ? MPResizeGlyph(fact) : NULL;' in up)
ct = M[M.find('%ctor {'):]
check('M7 SpringBoard\'s fact kept from its note (one dispatch registration, every pointer view updated at a change), read once at the start',
      'notify_register_dispatch(MSBD_RZ_NOTE, &resizeToken, dispatch_get_main_queue(), ^(int t) {' in ct and 'if (w == gMPResizeWord) return;' in ct
      and 'MPUpdateAll();' in ct and '}) == NOTIFY_STATUS_OK) notify_get_state(resizeToken, &gMPResizeWord);' in ct)
check('M8 the getters found once per class (a method, else the ivar; no key-value lookup with the pointer\'s updates)',
      'static void MPGetterFind(MPGetter *g, Class c, const char *sel, const char *ivarName, char want) {' in M and 'valueForKey' not in fn(M, 'static MPStateInfo *MPRecordState(UIViewController *c, id state) {')
      and 'valueForKey' not in fn(M, 'static NSArray *MPStateAccessories(id state) {') and 'valueForKey' not in fn(M, 'static BOOL MPStatePressed(id state) {'))
# SpringBoard
check('S1 StatusBar.x: ResizeFact.h right after SMResizeEdges.h; DMRZFollow declared before its use',
      before(S, '#include "SMResizeEdges.h"', '#include "ResizeFact.h"') and S.find('#include "ResizeFact.h"') - S.find('#include "SMResizeEdges.h"') < 200
      and before(S, 'static void DMRZFollow(BOOL styleMac);', 'DMRZFollow(on);'))
tick = fn(S, 'static void DMPointerBridgeTick(void) {')
check('S2 on / off with the Mac pointer: at once after a Pointer Style change and every 2 s at either pace, inside the MacPointer bridge',
      'gDMPtrStyleMac = on; gDMPtrResizeOn = resize; DMPointerAnimTick();' in tick and before(tick, 'gDMPtrStyleMac = on; gDMPtrResizeOn = resize; DMPointerAnimTick();', 'DMRZFollow(on);')
      and 'if (CACurrentMediaTime() - lastResizeFollow > 1.9) { lastResizeFollow = CACurrentMediaTime(); DMRZFollow(gDMPtrStyleMac); }' in tick
      and S.find('// ===== MacPointer bridge') < S.find('static void DMPointerBridgeTick(void) {') < S.find('// ===== end MacPointer bridge'))
fo = fn(F, 'static void DMRZFollow(BOOL styleMac) {')
check('S3 on only with Mac Resize Pointers, Pointer Style Mac, a trackpad or mouse, MacPointer drawing and the crash guard\'s piece not off (the switch read before anything else); the hook goes in at the first switch-on; each switch says 0 first (off: the fact goes; on: an earlier SpringBoard\'s word goes)',
      'BOOL on = styleMac && gDMPtrResizeOn && gDMPointerAttached && !DMRZSkipped() && MSBDMPVerdictDraws(MSBDMPVerdict(DMRZPointerStatus()));' in fo
      and 'static uint64_t gRZSaid = UINT64_MAX;' in F and 'started' not in fo
      and 'if (!cleared && gDMPtrResizeOn) { cleared = YES; DMRZSay(0); }' in fo and before(fo, 'if (!cleared && gDMPtrResizeOn) { cleared = YES; DMRZSay(0); }', 'BOOL on = styleMac')
      and before(fo, 'gRZOn = on;\n        DMRZSay(0);', 'if (on) DMRZInstall(); else gRZOwner = nil;') and F.count('DMRZInstall();') == 1
      and 'static BOOL DMRZSkipped(void) { static int s = -1; if (s < 0) s = MSBDCrashSkipped(MSBD_RZ_PIECE); return s != 0; }' in F and '#define MSBD_RZ_PIECE "resizePointers"' in F)
he = fn(F, 'static void DMRZHoverEdge(id self, SEL _cmd, unsigned long long edge) {')
check('S4 the hovered edge: iPadOS\'s own first, straight through while off, a change only (every pointer move calls it), edge 0 clears only its own fact',
      before(he, 'o_RZHoverEdge(self, _cmd, edge);', 'if (!gRZOn) return;')
      and 'if (self == lastC && edge == lastE && (!edge || (gRZOwner == self && CGRectEqualToRect(fr, lastF)))) return;' in he
      and 'if (!pos || ![self isKindOfClass:[UIView class]]) { DMRZClear(self); return; }' in he and 'if (owner && cur && owner != cur) return;' in fn(F, 'static void DMRZClear(id owner) {'))
ins = fn(F, 'static void DMRZInstall(void) {')
check('S5 the hook only with the signature written for (v@:Q), else nothing (logged): the Mac arrow at the edges',
      "if (![DMSMSigOfMethod(m) isEqualToString:DMSMExpect(@encode(void), @encode(unsigned long long), NULL)]) {" in ins and 'MSHookMessageEx(ic, s, (IMP)DMRZHoverEdge, (IMP *)&o_RZHoverEdge);' in ins)
bd = fn(F, 'static unsigned DMRZBandDirections(UIView *c, unsigned pos) {')
check('S10 one-way: no claim for a scaled window; the screen\'s limits only when the container\'s parent is the whole window, never the top',
      'if (!sup || !CGAffineTransformIsIdentity(c.transform)) return MSBD_RZ_ALL;' in bd and 'area = CGRectNull;' in bd and 'area.origin.y -= 100000.0; area.size.height += 100000.0;' in bd)
check('S6 a gone owner\'s fact cleared at the 2 s check; the word said only at a change',
      "if (!o || ([o isKindOfClass:[UIView class]] && !((UIView *)o).window)) DMRZClear(nil);" in fo and 'if (w == gRZSaid) return;' in fn(F, 'static void DMRZSay(uint64_t w) {'))
check('S7 the crash guard: the piece resizePointers (not the switch: its default is per iPadOS) and ResizeFact.h\'s file rule',
      "target resizePointers piece the resize pointers|macOS's resize pointers at window edges and corners" in C.split('\n') and 'file MacStatusBarCore ^(ResizeFact|MacResizeCursor)\\.h$ resizePointers' in C.split('\n'))
own = fn(P, 'NSArray *MSPointerOwnSpecifiers(id target, BOOL onApplePage) {')
mac = own[own.find('if ([MSPointerStyle() isEqualToString:@"mac"]) {'):]
check('S8 the Pointer page says it only where it is known true, under its switch: Stage Manager windows on iPadOS 18; our engines\' resize corners everywhere',
      "[gr setProperty:osMajor >= 18 ? @\"Shows macOS's resize pointers at the edges and corners of Stage Manager windows and at the resize corners of Aerial, Zetsu and MilkyWay4 windows.\"" in mac
      and ": @\"Shows macOS's resize pointers at the resize corners of Aerial, Zetsu and MilkyWay4 windows.\" forKey:@\"footerText\"];" in mac
      and 'static long osMajor = 0; if (!osMajor) osMajor = (long)[[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;' in mac
      and "resize pointers" not in own[:own.find('if ([MSPointerStyle() isEqualToString:@"mac"]) {')])
gsec = F[F.find("// ---- our window engines' grips"):F.find('// ---- on / off')]
check('S9 no pointer interaction or holder on the grips (B0: the pointer never reaches them on 15.6.1); nothing of the engines hooked by the grips\' part',
      'UIPointerInteraction' not in F and len(gsec) > 1000 and 'MSHookMessageEx' not in gsec and '%hook' not in F)
# F51b: the engines' grips (SpringBoard, ResizeFact.h)
gf = fn(F, 'static void DMRZGripsFollow(void) {')
PR = rd('statusbar/PointerRegion.h')
check('G1 the hover is watched on each display\'s system gestures window by PointerRegion.h\'s recognizer (prevents nothing, prevented by nothing), its own key; only while the Mac pointer draws and an engine has a shown grip; removed when off',
      'h = [[DMPtrHoverRecognizer alloc] initWithTarget:sink action:@selector(hover:)];' in gf and 'h.cancelsTouchesInView = NO; h.delaysTouchesBegan = NO; h.delaysTouchesEnded = NO;' in gf
      and "if (![NSStringFromClass([w class]) isEqualToString:@\"_UISystemGestureWindow\"]) continue;" in gf and 'objc_getAssociatedObject(w, kDMRZHoverKey)' in gf
      and 'if (!gRZOn || DMActiveEngine() == DMEngineNone) want = NO;' in gf and 'want = ts.count > 0;' in gf and '[w removeGestureRecognizer:h];' in gf
      and 'else { DMRZGripClear(); DMRZGripTimerSet(NO); gRZTakers = nil; gRZGripDragging = NO; }' in gf
      and '- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }' in PR and '- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }' in PR
      and before(S, '#include "PointerRegion.h"', '#include "ResizeFact.h"'))
fo2 = fn(F, 'static void DMRZFollow(BOOL styleMac) {')
check('G2 the grips follow the Mac pointer\'s switch at once and every 2 s (while on)', fo2.count('DMRZGripsFollow();') == 2 and before(fo2, 'if (on) DMRZInstall(); else gRZOwner = nil;', 'DMRZGripsFollow();')
      and before(fo2, 'if (!gRZOn) return;', 'if (gRZSaid) {'))
gh = fn(F, 'static void DMRZGripHover(UIHoverGestureRecognizer *g) {')
check('G3 a hover\'s point only from Began / Changed (a Cancelled one has none: B0 {0, 834}), in its own screen\'s space; the takers made again at a Began or after 0.5 s; every hover decides (a hover off every grip clears)',
      'if (s && (st == UIGestureRecognizerStateBegan || st == UIGestureRecognizerStateChanged)) {' in gh and 'CGPoint p = [v convertPoint:lp toCoordinateSpace:s.coordinateSpace];' in gh
      and 'UIWindow *w = DMRZWindowOf(v);' in gh and 'if (st == UIGestureRecognizerStateBegan || now - gRZTakersAt > 0.5) {' in gh and 'DMRZGripDecide(p, s, YES, NO);' in gh
      and 'case MSBD_RZ_GRIP_CLEAR: DMRZGripClear(); DMRZGripTimerSet(NO); return;' in fn(F, 'static void DMRZGripDecide(CGPoint p, UIScreen *s, BOOL again, BOOL full) {'))
ga = fn(F, 'static DMRZTaker *DMRZGripAt(CGPoint p, UIScreen *s, BOOL full) {')
cv = fn(F, 'static BOOL DMRZCoveredAt(CGPoint p, UIScreen *s, CGFloat level) {')
check('G4 the front-most grip only: its own window\'s hit test gives it (or the handle it hands to), no window above takes the point (that screen\'s only, the native layer counted, keyboard hosts never the answer: the keyboard\'s height is); the fast answer inside the same grip at most 0.05 s old',
      'if (!hit || !(hit == v || [hit isDescendantOfView:v] || (h && hit == h))) { gRZCovered = t; gRZGripFullAt = now; continue; }' in ga and 'if (DMRZCoveredAt(p, s, w.windowLevel)) { gRZCovered = t; return nil; }' in ga
      and 'if (!full && now - gRZGripFullAt < 0.05) { if (t == gRZGripShown) return t; if (t == gRZCovered) continue; }' in ga
      and 'if (w.hidden || w.screen != s || w.windowLevel <= level || w.alpha < 0.01) continue;' in cv and 'gNativeLayer' not in cv
      and '[hc containsString:@"Keyboard"]' in cv and 'if (s == [UIScreen mainScreen] && gSoftKeyboardH > 1.0 && p.y >= s.bounds.size.height - gSoftKeyboardH) return YES;' in cv)
tf = fn(F, 'static NSArray<DMRZTaker *> *DMRZTakersFind(void) {')
check('G5 the takers: the desktop on screen\'s shown windows only (not minimized, closing or flying in); Aerial 5.x\'s box and its handle, Aerial 3.0\'s handle, Zetsu\'s box, MilkyWay4\'s handle once ours',
      'for (UIView *w in DMAerialStages()) {' in tf and 'DMStageMinimized(w)' in tf and 'kStageClosingKey' in tf and 'kStageEnteringKey' in tf
      and 'UIWindow *ww = DMRZWindowOf(w);' in tf and 'if (!ww || ww.hidden || w.hidden' in tf and 'static UIWindow *DMRZWindowOf(UIView *v) { return [v isKindOfClass:[UIWindow class]] ? (UIWindow *)v : v.window; }' in F
      and 'kA5GripBLKey' in tf and '_handleBL' in tf and 'kZetsuGripLKey' in tf and 'objc_getAssociatedObject(sc, kMWGripKey)' in tf)
dt = fn(F, 'static void DMRZGripDecide(CGPoint p, UIScreen *s, BOOL again, BOOL full) {')
tm = fn(F, 'static void DMRZGripTimerSet(BOOL on) {')
check('G6 the clears and the lease: while a grip\'s fact stands the last point checked in full every 0.2 s (no cap) and the fact said again every 0.5 s or at a hover inside it; the fade clears; off clears',
      'switch (MSBDResizeGripAction(t != nil, same, again, CACurrentMediaTime() - gRZSaidAt, DMRZGripFactStands())) {' in dt and 'case MSBD_RZ_GRIP_SAY_AGAIN: DMRZSetAgain(t->view, f, YES); break;' in dt
      and 'case MSBD_RZ_GRIP_SAY: DMRZSetAgain(t->view, f, NO); break;' in dt and before(dt, 'gRZGripShown = t;', 'DMRZGripTimerSet(YES);')
      and 'timerWithTimeInterval:MSBD_RZ_GRIP_CHECK repeats:YES' in tm and 'DMRZGripDecide(gRZGripLast, s, NO, YES);' in tm
      and 'MSBDResizeGripCheckKeeps(CGRectEqualToRect(s.bounds, gRZGripLastBounds), MSBDResizeUnpack(gRZSaid).display, CACurrentMediaTime() - gRZHoverAt)' in tm
      and 'v == MSBDPointerFadeHidden && gRZGripsOn) { DMRZGripClear(); DMRZGripTimerSet(NO); }' in fn(F, 'static void DMRZGripWatchFade(void) {')
      and 'if (!again && gRZOwner == owner && gRZSaid && MSBDResizeSamePlace(MSBDResizeUnpack(gRZSaid), f)) return;' in F)
gd = fn(F, 'static unsigned DMRZGripDirections(DMRZTaker *t) {')
check('G7 one-way only where our own drag keeps the limit: inward on Zetsu only (the screen), Aerial\'s minimum only where its handle is watched, no claim for a scaled window',
      "if (t->kind == DMRZKindZetsu) { mn = MSBDWindowMinSize();" in gd and 'area = s.bounds;' in gd and gd.count('area = ') == 2
      and 'if (objc_getAssociatedObject(h, &kA5MinWatchedKey) && DMA5CornerOffsetAt(w) && DMA5ResizeStartAt(w)) mn = DMEngineWindowMin();' in gd
      and 'if (!w || !CGAffineTransformIsIdentity(w.transform)) return MSBD_RZ_ALL;' in gd)
gdr = fn(F, 'static void DMRZGripDrag(CGPoint p, UIScreen *s, UIGestureRecognizerState st) {')
check('G8 a grip\'s drag feeds its own point (no hovers then) from our three engines\' drag code, only for a drag that began with a grip\'s fact; its end decides at the release point (review F51b finding 1)',
      'if (st == UIGestureRecognizerStateBegan) gRZGripDragging = DMRZGripFactStands();' in gdr and before(gdr, 'gRZGripDragging = NO;', 'DMRZGripDecide(p, s, NO, YES);')
      and 'DMRZGripPointSet(p, s);' in gdr
      and 'DMRZGripDrag(p, w.screen, g.state);' in fn(S, '- (void)pan:(UIPanGestureRecognizer *)g {')
      and 'if (sc) DMRZGripDrag([sup convertPoint:[g locationInView:sup] toCoordinateSpace:sc.coordinateSpace], sc, s);' in fn(S, '- (void)step:(UIPanGestureRecognizer *)g {')
      and 'DMRZGripDrag([g.view convertPoint:[g locationInView:g.view] toCoordinateSpace:me.window.screen.coordinateSpace], me.window.screen, g.state);' in S
      and 'static void DMRZGripDrag(CGPoint p, UIScreen *s, UIGestureRecognizerState st);' in S)
check('G9 cost: most hovers end at the quick no in the window\'s own space (no conversion); the follow walks no windows at rest (on: only after a hover; off: only with windows)',
      'if (!near && !DMRZGripFactStands()) { gRZGripShown = nil; DMRZGripTimerSet(NO); }' in gh and before(gh, 'CGRectContainsPoint(CGRectInset(t->local, -4.0, -4.0), lp)', 'CGPoint p = [v convertPoint:lp toCoordinateSpace:s.coordinateSpace];')
      and 'else if (!gRZGripsOn ? DMWindowWorkNeeded() : gRZHoverAt > lookedAt) {' in gf)
check('G10 another tweak\'s hit test that throws: caught, counted as covered (finding 7)', '@try { return [w hitTest:[w convertPoint:p fromCoordinateSpace:s.coordinateSpace] withEvent:nil]; } @catch (id x) { if (threw) *threw = YES; }' in F
      and 'if (threw) return YES;' in cv and '[w hitTest:' not in cv and '[w hitTest:' not in ga)
check('M14 a press during a released drag\'s grace never latches its glyph (finding 3)',
      'si->shownWord = glyph && !MSBDResizeLatchGraceOnly(&gMPResizeLatch, now) ? MSBDResizePack(fact) : 0;' in up)
# F51b: pointeruid
check('M10 a grip\'s fact drawn only while fresh (its lease, no change of iPadOS\'s shape since its word)',
      'if (factHere && fact.source == MSBD_RZ_SRC_GRIP && !MSBDResizeGripFresh(now, gMPResizeGripAt, gMPShapeSeq, gMPResizeGripSeq)) factHere = NO;' in up
      and before(up, 'factHere = (fact.display == 1) == !MPOnOwnDisplay(view);', 'MSBDResizeGripFresh('))
sh = fn(M, '- (void)setPointerShape:(id)shapeObj animated:(BOOL)animated completion:(id)completion {')
check('M11 the shape count goes up at a real change of iPadOS\'s shape only (not the same shape again), before the update',
      before(sh, 'if (before && [before isEqual:shapeObj]) return;', 'gMPShapeSeq++;') and before(sh, 'gMPShapeSeq++;', 'MPUpdate((PUIDPointerShapeView *)self);'))
nv = fn(M, 'static NSArray<UIView *> *MPNativeViews(UIView *view) {')
A = rd('statusbar/macpointer/MPAside.h')
pc = fn(A, 'static inline BOOL MPAsideClassIsPUID(Class c) {')
check('M15 iPadOS 18\'s morphing shape view under resize bands is hidden with the round pointer (ivar and PUID subviews, never another library\'s) and restored before a real shape change',
      '"_pointerShapeMorphingView"' in nv and 'MPAsideHeldBy(view, [UIView class], held, 0, 64)' in nv and 'MPAsideClassIsPUID(object_getClass(sub))' in nv
      and 'MPAsideClassIsOther(object_getClass(sub))' in nv and '!strncmp(cn, "PUID", 4)' in pc and 'MPAsideClassIsOther(c)' in pc
      and before(sh, 'for (UIView *v in hid) v.layer.hidden = NO;', '%orig(shapeObj, morph, completion);')
      and before(sh, 'if (main && (!before || ![before isEqual:shapeObj])) {', 'for (UIView *v in hid) v.layer.hidden = NO;'))
check('M12 a grip\'s word starts its lease and draws again when it ends with no newer word; any word ends a drag\'s grace',
      'gMPResizeGripAt = CACurrentMediaTime(); gMPResizeGripSeq = gMPShapeSeq;' in ct and 'if (gMPResizeWord == w) MPUpdateAll();   // (no newer word: the lease is over)' in ct
      and 'MSBDResizeLatchWord(&gMPResizeLatch);' in ct and before(ct, 'gMPResizeWord = w;', 'MSBDResizeLatchWord(&gMPResizeLatch);'))
check('M13 the latch\'s grace after the button-up holds the glyph until SpringBoard\'s word, and its end draws again',
      'held = MSBDResizeLatchHolds(&gMPResizeLatch, now);' in up and 'look = MSBDPointerLook(beamShape, accessories, factHere, evidence, held);' in up
      and 'dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((MSBD_RZ_LATCH_GRACE + 0.02) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MPUpdateAll(); });' in sps)
check('S11 rzinfo (debug): the grips, the recognizers, the fact', 'else if ([cmd isEqualToString:@"rzinfo"]) DMRZInfo();' in S and '#if DEBUG\nstatic void DMRZInfo(void);' in S)
# Settings > Pointer > Mac Resize Pointers (1.8.9, KT 25 Nov): on by default on iPadOS 18, off on 15-17; off, nothing of F51 / F51b runs
ro = fn(M, 'static void MPResizeRead(void) {')
rf = fn(M, 'static void MPResizeForget(void) {')
off = up[up.find('if (!rzOn) look = MSBDPointerLook1884(type, sb);'):]
offb = up[:up.find('    int look;')] if '    int look;' in up else ''
onb = up[up.find('    else {', up.find('if (!rzOn) look = MSBDPointerLook1884(type, sb);')):up.find('    BOOL systemShape = look == MSBD_PTR_BEAM;')]
check('W1 pointeruid: the switch from SpringBoard\'s config word (bit 4), read at the start and at each "changed" note (never per pointer update); switched off, the drag\'s latch and every controller\'s record go at once',
      'BOOL on = (MPState(gMPConfigToken) & MSBD_RZ_CONFIG_BIT) != 0;' in ro and before(ro, 'if (on == gMPResizeOnNow) return;', 'if (!on) MPResizeForget();')
      and 'static BOOL MPResizeOn(void) { return gMPResizeOnNow; }' in M and M.count('MPResizeRead();') == 2
      and before(ct, 'notify_register_check("com.besiktasliseba.macpointer.config", &gMPConfigToken);', 'MPResizeRead();')
      and '^(int t) { MPResizeRead(); MPUpdateAll(); MPApplyVisibility(); MPPublishPresence(); });' in ct and 'MPState(gMPConfigToken) & MSBD_RZ_CONFIG_BIT' not in up
      and 'memset(&gMPResizeLatch, 0, sizeof gMPResizeLatch);' in rf and rf.count('objc_setAssociatedObject(') == 2 and 'kMPStateInfoKey, nil' in rf
      and 'static BOOL gMPResizeOnNow = NO;' in M)
check('W2 pointeruid off: MPUpdate\'s look is 1.8.8.4\'s (MSBDPointerLook1884) and nothing of F51 is read -- the record, the beam rule, the latch, the fact, the evidence only in the on branch',
      'BOOL rzOn = MPResizeOn();' in up and 'MPStateInfo *si = rzOn && ctl ? objc_getAssociatedObject(ctl, kMPStateInfoKey) : nil;' in up
      and 'if (!rzOn) look = MSBDPointerLook1884(type, sb);' in up and len(onb) > 500
      and all(x in onb for x in ['MPBeamRuleFrom18()', 'MSBDResizeLatchHolds(', 'MSBDResizeUnpack(gMPResizeWord)', 'MSBDResizeEvidence(', 'MSBDPointerLook(', 'MPAccessoryViewsShown('])
      and all(x not in offb for x in ['MPBeamRuleFrom18()', 'MSBDResizeLatchHolds(', 'gMPResizeWord', 'MSBDResizeEvidence(', 'MSBDPointerLook(', 'MPAccessoryViewsShown(', 'gMPResizeLatch'])
      and up.count('MSBDPointerLook1884(') == 1 and up.count('MPResizeOn()') == 1 and before(up, 'BOOL enabled = MPEnabled();', 'BOOL rzOn = MPResizeOn();')
      and 'si->shownWord = glyph' in up and 'if (si && enabled && (systemShape || !sysHid)) si->shownWord' in up)
check('W3 pointeruid off: -setPointerState:... records nothing and steps no latch; its change signature is 1.8.8.4\'s (no arrows, no latch bits)',
      'MPStateInfo *si = MPResizeOn() ? MPRecordState((UIViewController *)self, state) : nil;' in sps and 'if (si) {   // (only the display the pointer is on' in sps
      and before(sps, 'if (si) {   // (only the display the pointer is on', 'MSBDResizeLatchStepAt(') and sps.count('MPRecordState(') == 1
      and '(si ? ((NSUInteger)((si->count + 1) & 0xF) << 10)' in sps)
check('W4 pointeruid off: SpringBoard\'s word kept, never drawn (no lease, no grace, no redraw)',
      before(ct, 'gMPResizeWord = w;', 'if (!MPResizeOn()) return;') and before(ct, 'if (!MPResizeOn()) return;', 'MSBDResizeLatchWord(&gMPResizeLatch);')
      and before(ct, 'if (!MPResizeOn()) return;', 'gMPResizeGripAt = CACurrentMediaTime();'))
check('W5 SpringBoard: the switch read with Pointer Style (never set: per iPadOS; a choice made wins), live at every settings change, said to pointeruid in bit 4 of the config word, before the follow',
      'v = CFPreferencesCopyValue(CFSTR(MSBD_RZ_PREF_KEY), MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);' in tick
      and 'BOOL resize = MSBDResizePointersOn(MSBDResizePointersStored(v), osMajor);' in tick and 'osMajor = (long)[[NSProcessInfo processInfo] operatingSystemVersion].majorVersion;' in tick
      and '| (on && resize ? MSBD_RZ_CONFIG_BIT : 0);' in tick and before(tick, 'BOOL resize = MSBDResizePointersOn(', 'gDMPtrResizeOn = resize;') and before(tick, 'gDMPtrResizeOn = resize;', 'DMRZFollow(on);')
      and before(tick, 'if (gDMPointerPrefsStale || CACurrentMediaTime() - lastPrefs > 30.0) {', 'BOOL resize = ') and 'static BOOL gDMPtrResizeOn = NO;' in S
      and before(S, '#include "../common/MacResizeCursor.h"', 'static void DMPointerBridgeTick(void) {') and before(S, 'static BOOL gDMPtrResizeOn = NO;', '#include "ResizeFact.h"'))
check('W6 SpringBoard off: the follow ends before anything is read, said or walked (off from the start: no word, no hook, no recognizer)',
      'if (!gRZOn) return;   // (off: nothing more' in fo and before(fo, 'if (!gRZOn) return;', 'if (gRZSaid) {') and before(fo, 'return;\n    }\n    if (!gRZOn) return;', 'DMRZGripsFollow();   // (F51b: an engine window'))
rz = mac[mac.find('PSSpecifier *gr = [PSSpecifier groupSpecifierWithName:nil];'):mac.find('if (MSBDHypervisorCapable()) {')]
check('W7 Settings: the Mac Resize Pointers switch on the pointer page, with the Mac pointer only, after Pointer Style\'s note and before Hide in Virtual Mac; our preferences, the prefsChanged note (live), the default per iPadOS by the same rule as SpringBoard\'s',
      '[PSSpecifier preferenceSpecifierNamed:@"Mac Resize Pointers" target:target set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:kCellSwitch edit:nil];' in rz
      and '[rz setProperty:@MSBD_RZ_PREF_KEY forKey:@"key"];' in rz and '[rz setProperty:MP_DOMAIN forKey:@"defaults"];' in rz
      and '[rz setProperty:@(MSBDResizePointersDefault(osMajor)) forKey:@"default"];' in rz and '[rz setProperty:MP_NOTIFY forKey:@"PostNotification"];' in rz
      and '[rz setIdentifier:@"MAC_RESIZE_POINTERS"];' in rz and before(mac, 'NSString *note = MSPointerStatusNoteIs(&noteKind);', 'PSSpecifier *gr = [PSSpecifier groupSpecifierWithName:nil];')
      and '#include "../common/MacResizeCursor.h"' in P and P.count('Mac Resize Pointers" target') == 1
      and '#define MP_NOTIFY @"com.besiktasliseba.macstatusbar/prefsChanged"' in P and '#define MP_DOMAIN @"com.besiktasliseba.macstatusbar"' in P)
sys.exit(1 if fails else 0)
PY
}
echo "== 2. sites"
R=$(cd .. && pwd)
if sites "$R"; then :; else FAILS=$((FAILS + 1)); fi
echo "== 3. made-to-fail copies (each must fail)"
mtf() {   # mtf <label> <file> <perl substitution>: a copy of the tree with that change must fail the sites (or, for the header, the unit test)
  local d="$W/m"; rm -rf "$d"; mkdir -p "$d/statusbar/macpointer" "$d/common" "$d/tools" "$d/macsettings"
  cp ../statusbar/macpointer/MacPointer.x ../statusbar/macpointer/MPAside.h "$d/statusbar/macpointer/"; cp ../statusbar/StatusBar.x ../statusbar/ResizeFact.h ../statusbar/PointerRegion.h "$d/statusbar/"; cp ../tools/crashmap-rules.txt "$d/tools/"
  cp ../macsettings/PointerSettings.x "$d/macsettings/"; cp ../common/MacResizeCursor.h "$d/common/"
  perl -0pi -e "$3" "$d/$2"
  if cmp -s "$d/$2" "../$2"; then echo "FAIL  made-to-fail ($1): the change did not apply"; FAILS=$((FAILS + 1)); return; fi
  if Q=1 sites "$d" > /dev/null 2>&1; then echo "FAIL  made-to-fail ($1): not caught"; FAILS=$((FAILS + 1)); else [ -n "$Q" ] || echo "PASS  made-to-fail ($1): caught"; fi
}
mtf "the old beam rule (any type 4 is text) on 18 too" statusbar/macpointer/MacPointer.x 's/look = MSBDPointerLook\(beamShape,/look = MSBDPointerLook(beamShape || type == 4,/'
mtf "the arrows recorded after iPadOS's update" statusbar/macpointer/MacPointer.x 's/(    MPStateInfo \*si = MPResizeOn\(\) \? MPRecordState\(\(UIViewController \*\)self, state\) : nil;\n)((?:.*\n){0,14}?)(    BOOL r = %orig;\n)/$2$3$1/'
mtf "the fact read at rest" statusbar/macpointer/MacPointer.x 's/if \(fact.kind && !held\) \{/if (!held) {/'
mtf "the shadow left on the arrow's path" statusbar/macpointer/MacPointer.x 's/a.path = wantPath; a.shadowPath = wantPath;/a.path = wantPath;/'
mtf "the fact's note never registered" statusbar/macpointer/MacPointer.x 's/notify_register_dispatch\(MSBD_RZ_NOTE, &resizeToken/notify_register_check(MSBD_RZ_NOTE, &resizeToken/'
mtf "the 2 s follow left out" statusbar/StatusBar.x 's/ DMRZFollow\(gDMPtrStyleMac\); \}/ }/'
mtf "on whatever MacPointer says" statusbar/ResizeFact.h 's/ && MSBDMPVerdictDraws\(MSBDMPVerdict\(DMRZPointerStatus\(\)\)\);/;/'
mtf "on with no trackpad or mouse (reads at rest)" statusbar/ResizeFact.h 's/ && gDMPointerAttached && !DMRZSkipped\(\)/ \&\& !DMRZSkipped()/'
mtf "edge 0 clears another window's fact" statusbar/ResizeFact.h 's/    if \(owner && cur && owner != cur\) return;\n//'
mtf "the crash piece left out" tools/crashmap-rules.txt 's/target resizePointers piece [^\n]*\n//'
mtf "the Pointer page's words on every iPadOS" macsettings/PointerSettings.x 's/osMajor >= 18 \?/osMajor >= 15 ?/'
mtf "the path compared by pointer" statusbar/macpointer/MacPointer.x 's/&& hasKey == wantKey\)/\&\& a.path == wantPath)/'
mtf "the views counted over a beam" statusbar/macpointer/MacPointer.x 's/\(!beamShape && ctl \? MPAccessoryViewsShown\(ctl\) : 0\)/(ctl ? MPAccessoryViewsShown(ctl) : 0)/'
mtf "iPadOS 18's morphing shape view left shown behind the resize glyph" statusbar/macpointer/MacPointer.x 's/if \(MPAsideIn\(\(__bridge const void \*\)sub, held, nh\) \|\| MPAsideClassIsPUID\(object_getClass\(sub\)\)\) \[m addObject:sub\];/(void)held; (void)nh;/'
mtf "previously hidden native views not given back to iPadOS before a shape change" statusbar/macpointer/MacPointer.x 's/            for \(UIView \*v in hid\) v\.layer\.hidden = NO;\n            \[hid removeAllObjects\];\n//'
mtf "the new beam rule on 15-17 too" statusbar/macpointer/MacPointer.x 's/\(NSOperatingSystemVersion\)\{18, 0, 0\}\] \? 1 : 0;/(NSOperatingSystemVersion){15, 0, 0}] ? 1 : 0;/'
mtf "the last SpringBoard's word left" statusbar/ResizeFact.h 's/    if \(!cleared && gDMPtrResizeOn\) \{ cleared = YES; DMRZSay\(0\); \}\n//'
mtf "Mac Resize Pointers: off says 0 only, on says nothing" statusbar/ResizeFact.h 's/        gRZOn = on;\n        DMRZSay\(0\);[^\n]*\n        if \(on\) DMRZInstall\(\); else gRZOwner = nil;/        gRZOn = on;\n        if (on) DMRZInstall(); else { DMRZSay(0); gRZOwner = nil; }/'
mtf "inward-only from any parent's bounds" statusbar/ResizeFact.h 's/ area = CGRectNull;/ area = area;/'
mtf "F51b: a grip's fact drawn without its lease" statusbar/macpointer/MacPointer.x 's/        if \(factHere && fact.source == MSBD_RZ_SRC_GRIP && !MSBDResizeGripFresh\([^\n]*\n//'
mtf "F51b: the shape count never goes up" statusbar/macpointer/MacPointer.x 's/    gMPShapeSeq\+\+;[^\n]*\n//'
mtf "F51b: the lease's end never drawn" statusbar/macpointer/MacPointer.x 's/if \(gMPResizeWord == w\) MPUpdateAll\(\);/(void)w;/'
mtf "F51b: the grace's end never drawn" statusbar/macpointer/MacPointer.x 's/\^\{ MPUpdateAll\(\); \}\);/^{ });/'
mtf "F51b: a recognizer that can stop iPadOS's gestures" statusbar/ResizeFact.h 's/h = \[\[DMPtrHoverRecognizer alloc\]/h = [[UIHoverGestureRecognizer alloc]/'
mtf "F51b: no check while a grip's fact stands" statusbar/ResizeFact.h 's/    gRZGripShown = t;\n    DMRZGripTimerSet\(YES\);/    gRZGripShown = t;/'
mtf "F51b: the lease never said again" statusbar/ResizeFact.h 's/case MSBD_RZ_GRIP_SAY_AGAIN: DMRZSetAgain\(t->view, f, YES\); break;/case MSBD_RZ_GRIP_SAY_AGAIN: break;/'
mtf "F51b: the fade does not clear" statusbar/ResizeFact.h 's/v == MSBDPointerFadeHidden && gRZGripsOn\) \{ DMRZGripClear\(\); DMRZGripTimerSet\(NO\); \}/v == MSBDPointerFadeHidden \&\& gRZGripsOn) { }/'
mtf "F51b: a covered grip shows" statusbar/ResizeFact.h 's/if \(DMRZCoveredAt\(p, s, w.windowLevel\)\) \{ gRZCovered = t; return nil; \}//'
mtf "F51b: Zetsu's drag point not fed" statusbar/StatusBar.x 's/    DMRZGripDrag\(p, w.screen, g.state\);[^\n]*\n//'
mtf "F51b: a drag's end not decided" statusbar/ResizeFact.h 's/        gRZGripDragging = NO;\n        DMRZGripDecide\(p, s, NO, YES\);/        gRZGripDragging = NO;/'
mtf "F51b: a finger's drag fed too" statusbar/ResizeFact.h 's/gRZGripDragging = DMRZGripFactStands\(\);/gRZGripDragging = YES;/'
mtf "F51b: a throwing hit test not caught" statusbar/ResizeFact.h 's/        if \(threw\) return YES;\n//'
mtf "F51b: the turn not checked" statusbar/ResizeFact.h 's/MSBDResizeGripCheckKeeps\(CGRectEqualToRect\(s.bounds, gRZGripLastBounds\)/MSBDResizeGripCheckKeeps(YES/'
mtf "F51b: hit tests on every move in a grip" statusbar/ResizeFact.h 's/now - gRZGripFullAt < 0.05\)/now - gRZGripFullAt < 5.0)/'
mtf "F51b: the takers walked at rest" statusbar/ResizeFact.h 's/else if \(!gRZGripsOn \? DMWindowWorkNeeded\(\) : gRZHoverAt > lookedAt\) \{/else if (YES) {/'
mtf "F51b: Zetsu's windows dropped (a UIWindow's -window is nil)" statusbar/ResizeFact.h 's/UIWindow \*ww = DMRZWindowOf\(w\);/UIWindow *ww = w.window;/'
mtf "F51b: a released drag's grace latched again" statusbar/macpointer/MacPointer.x 's/si->shownWord = glyph && !MSBDResizeLatchGraceOnly\(&gMPResizeLatch, now\) \?/si->shownWord = glyph ?/'
mtf "F51b: a keyboard host covers every grip" statusbar/ResizeFact.h 's/ \|\| \[hc containsString:\@"Keyboard"\]//'
mtf "F51b: the grips followed with no engine window" statusbar/ResizeFact.h 's/want = ts.count > 0;/want = YES;/'
mtf "F51b: inward at the edges on every engine" statusbar/ResizeFact.h 's/if \(isWin && s\) area = s.bounds; \}/} area = w.superview.bounds;/'
mtf "F51b: a Cancelled hover's point used" statusbar/ResizeFact.h 's/if \(s && \(st == UIGestureRecognizerStateBegan \|\| st == UIGestureRecognizerStateChanged\)\) \{/if (s) {/'
mtf "F51b: minimized windows' grips" statusbar/ResizeFact.h 's/ \|\| DMStageMinimized\(w\)//'
# Mac Resize Pointers (1.8.9)
mtf "Mac Resize Pointers: the follow does not read the switch" statusbar/ResizeFact.h 's/BOOL on = styleMac && gDMPtrResizeOn && gDMPointerAttached/BOOL on = styleMac \&\& gDMPointerAttached/'
mtf "Mac Resize Pointers: off walks on after the transition" statusbar/ResizeFact.h 's/    if \(!gRZOn\) return;   \/\/ \(off: nothing more[^\n]*\n//'
mtf "Mac Resize Pointers: not said to pointeruid" statusbar/StatusBar.x 's/ \| \(on && resize \? MSBD_RZ_CONFIG_BIT : 0\);/;/'
mtf "Mac Resize Pointers: read once, not live" statusbar/StatusBar.x 's/gDMPtrStyleMac = on; gDMPtrResizeOn = resize;/gDMPtrStyleMac = on; static BOOL rzOnce; if (!rzOnce) { rzOnce = YES; gDMPtrResizeOn = resize; }/'
mtf "Mac Resize Pointers: the default ignores the iPadOS" statusbar/StatusBar.x 's/MSBDResizePointersOn\(MSBDResizePointersStored\(v\), osMajor\)/MSBDResizePointersOn(MSBDResizePointersStored(v), 18)/'
mtf "Mac Resize Pointers: pointeruid's off look not 1.8.8.4's" statusbar/macpointer/MacPointer.x 's/if \(!rzOn\) look = MSBDPointerLook1884\(type, sb\);/if (!rzOn) look = MSBDPointerLook(MSBDPointerBeamShape(type, sb.size.width, sb.size.height), 0, NO, NO, NO);/'
mtf "Mac Resize Pointers: the record kept while off" statusbar/macpointer/MacPointer.x 's/MPStateInfo \*si = MPResizeOn\(\) \? MPRecordState\(\(UIViewController \*\)self, state\) : nil;/MPStateInfo *si = MPRecordState((UIViewController *)self, state);/'
mtf "Mac Resize Pointers: nothing forgotten when switched off" statusbar/macpointer/MacPointer.x 's/    if \(!on\) MPResizeForget\(\);\n//'
mtf "Mac Resize Pointers: pointeruid never reads a change" statusbar/macpointer/MacPointer.x 's/\^\(int t\) \{ MPResizeRead\(\); MPUpdateAll\(\);/^(int t) { MPUpdateAll();/'
mtf "Mac Resize Pointers: a word drawn while off" statusbar/macpointer/MacPointer.x 's/            if \(!MPResizeOn\(\)\) return;[^\n]*\n//'
mtf "Mac Resize Pointers: the latch read while off" statusbar/macpointer/MacPointer.x 's/    BOOL held = NO;\n/    BOOL held = MSBDResizeLatchHolds(&gMPResizeLatch, now);\n/'
mtf "Mac Resize Pointers: Settings' default the same on every iPadOS" macsettings/PointerSettings.x 's/\[rz setProperty:\@\(MSBDResizePointersDefault\(osMajor\)\) forKey:\@"default"\];/[rz setProperty:\@YES forKey:\@"default"];/'
mtf "Mac Resize Pointers: Settings not live" macsettings/PointerSettings.x 's/    \[rz setProperty:MP_NOTIFY forKey:\@"PostNotification"\];\n//'
mtf "Mac Resize Pointers: the row with the iPadOS pointer too" macsettings/PointerSettings.x 's/(        \[s addObject:style\];\n)(.*?)(            \/\/ \(1\.8\.9: Mac Resize Pointers.*?\[s addObject:rz\];\n)/$1$3$2/s'
# the header made to fail: the unit test must catch it
hmtf() {
  local d="$W/h"; rm -rf "$d"; mkdir -p "$d/common" "$d/tools"; cp ../common/MacResizeCursor.h "$d/common/"; cp test-macresizecursor.m "$d/tools/"
  perl -0pi -e "$2" "$d/common/MacResizeCursor.h"
  if cmp -s "$d/common/MacResizeCursor.h" ../common/MacResizeCursor.h && [ -z "$3" ]; then echo "FAIL  made-to-fail ($1): the change did not apply"; FAILS=$((FAILS + 1)); return; fi
  if ! clang -fobjc-arc -w -framework AppKit $3 -o "$d/t" "$d/tools/test-macresizecursor.m" 2>/dev/null; then echo "FAIL  made-to-fail ($1): did not compile (not a test of the rule)"; FAILS=$((FAILS + 1)); return; fi
  if "$d/t" > /dev/null 2>&1; then echo "FAIL  made-to-fail ($1): not caught"; FAILS=$((FAILS + 1)); else [ -n "$Q" ] || echo "PASS  made-to-fail ($1): caught"; fi
}
hmtf "a type 4 resize shape taken for the beam" 's/    return type == 4 && \(!sized \|\| fmin\(w, h\) < 6.0\);/    return type == 4;/'
hmtf "accessories no longer stop the beam" 's/if \(beamShape && accessories <= 0\) return MSBD_PTR_BEAM;/if (beamShape) return MSBD_PTR_BEAM;/'
hmtf "a shape alone (any type) as the evidence" 's/    if \(type != 4 \|\| w < 6.0 \|\| h < 6.0\) return false;/    if (w < 6.0 || h < 6.0) return false;/'
hmtf "the shape not matched to the place" 's/return c == 1 \? r >= 2.0 : c == 2 \? r <= 1.3 : false;/return c != 0;/'
hmtf "a corner one-way when the axes disagree" 's/if \(h && v\) return a == b \? a : MSBD_RZ_ALL;/if (h \&\& v) return a;/'
hmtf "the latch from any pressed update" 's/else if \(!l->wasPressed && showingResize/else if (showingResize/'
hmtf "F51b: a grip's fact at any position" 's/if \(f.source == MSBD_RZ_SRC_GRIP\) return want == 2;/if (f.source == MSBD_RZ_SRC_GRIP) return true;/'
hmtf "F51b: a grip's word that never expires" 's/ && now - arrivedAt <= MSBD_RZ_GRIP_LEASE//'
hmtf "F51b: a grip trusted past a shape change" 's/ && shapeSeqNow == shapeSeqAtArrival;/;/'
hmtf "F51b: no grace after the button-up" 's/ && l->fact.source == MSBD_RZ_SRC_GRIP\) l->graceUntil = now \+ MSBD_RZ_LATCH_GRACE;/) l->graceUntil = 0;/'
hmtf "F51b: the grace on a band's drag too" 's/ && l->fact.source == MSBD_RZ_SRC_GRIP\) l->graceUntil/) l->graceUntil/'
hmtf "F51b: a grip's fact never said again" 's/return \(again \|\| since >= MSBD_RZ_GRIP_RESAY - 0.01\) \? MSBD_RZ_GRIP_SAY_AGAIN : MSBD_RZ_GRIP_NOTHING;/return MSBD_RZ_GRIP_NOTHING;/'
hmtf "F51b: a turn keeps the old point" 's/    if \(!boundsSame\) return false;\n//'
hmtf "F51b: another display's grip never ends" 's/return !\(display == 1 && sinceHover > MSBD_RZ_GRIP_OTHER_REST\);/return true;/'
hmtf "F51b: the lease said again too seldom" 's/#define MSBD_RZ_GRIP_RESAY 0.4 /#define MSBD_RZ_GRIP_RESAY 0.6 /'
hmtf "F51b: a word that does not end the grace" 's/static inline void MSBDResizeLatchWord\(MSBDResizeLatch \*l\) \{ l->graceUntil = 0; \}/static inline void MSBDResizeLatchWord(MSBDResizeLatch *l) { (void)l; }/'
hmtf "a glyph turned the wrong way" 's/^$//' "-DMSBD_RZ_FAIL_GLYPH"
hmtf "Mac Resize Pointers: on by default on 15-17 too" 's/static inline bool MSBDResizePointersDefault\(long osMajor\) \{ return osMajor >= 18; \}/static inline bool MSBDResizePointersDefault(long osMajor) { return osMajor >= 15; }/'
hmtf "Mac Resize Pointers: the user's choice ignored" 's/return stored < 0 \? MSBDResizePointersDefault\(osMajor\) : stored != 0;/return MSBDResizePointersDefault(osMajor);/'
hmtf "Mac Resize Pointers: a text taken as on" 's/    return -1;\n\}\nstatic inline bool MSBDResizePointersOn/    return 1;\n}\nstatic inline bool MSBDResizePointersOn/'
hmtf "Mac Resize Pointers: off is not 1.8.8.4's look (a 4 pt shape)" 's/ : sb.size.height\) <= 4.0;/ : sb.size.height) < 4.0;/'
hmtf "Mac Resize Pointers: off is not 1.8.8.4's look (an empty sized shape)" 's/    bool thin = !CGRectIsEmpty\(sb\) && /    bool thin = /'
echo "== 4. Mac Resize Pointers in SpringBoard (test-macresizeswitch.m, Mac Catalyst): off installs nothing"
SDK=$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)
FW="$SDK/System/iOSSupport/System/Library/Frameworks"
CCAT() { clang -target "$(uname -m)-apple-ios14.0-macabi" -isysroot "$SDK" -iframework "$FW" -F "$FW" -L"$SDK/System/iOSSupport/usr/lib" -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
            -Wno-unused-function -Werror=implicit-function-declaration -framework UIKit -framework QuartzCore -framework CoreGraphics "$@"; }
swrun() {   # swrun <tree> <label> <quiet>: the harness built on that tree's ResizeFact.h (release and DEBUG), run; 0 when it passes
  local t=$1 rc=0 dbg
  for dbg in 0 1; do
    if ! CCAT -DDEBUG=$dbg -I"$t" -DRZ_FACT_H="\"$t/statusbar/ResizeFact.h\"" -o "$W/sw$dbg" test-macresizeswitch.m 2> "$W/swcc$dbg.txt"; then
      [ -n "$3" ] || { head -5 "$W/swcc$dbg.txt"; echo "FAIL  the switch test did not build on $2 (DEBUG=$dbg)"; }; return 2
    fi
    [ -s "$W/swcc$dbg.txt" ] && { [ -n "$3" ] || { echo "FAIL  warnings ($2, DEBUG=$dbg):"; cat "$W/swcc$dbg.txt"; }; rc=1; }
    if [ -n "$3" ]; then "$W/sw$dbg" > /dev/null 2>&1 || rc=1
    elif [ -n "$Q" ]; then "$W/sw$dbg" > "$W/swout.txt" 2>&1 || { grep FAIL "$W/swout.txt"; rc=1; }
    else echo "-- $2, DEBUG=$dbg"; "$W/sw$dbg" || rc=1; fi
  done
  return $rc
}
if [ ! -d "$FW/UIKit.framework" ]; then echo "FAIL  no Mac Catalyst UIKit in $SDK"; FAILS=$((FAILS + 1))
else
  mkdir -p "$W/now/statusbar" "$W/now/common"; cp ../statusbar/ResizeFact.h "$W/now/statusbar/"; cp ../common/MacResizeCursor.h ../common/PointerFade.h ../common/MacPointerStatus.h "$W/now/common/"
  swrun "$W/now" "this tree" || FAILS=$((FAILS + 1))
  RZT_SKIPPED=1 swrun "$W/now" "this tree, the crash guard's piece off" || FAILS=$((FAILS + 1))
  # made-to-fail: no clear of an earlier SpringBoard's word while the piece is off (pointeruid would draw it: the switch's review, finding 1)
  mkdir -p "$W/nc/statusbar"; cp -R "$W/now/common" "$W/nc/"; cp ../statusbar/ResizeFact.h "$W/nc/statusbar/"
  perl -0pi -e 's/    if \(!cleared && gDMPtrResizeOn\) \{ cleared = YES; DMRZSay\(0\); \}\n//' "$W/nc/statusbar/ResizeFact.h"
  if cmp -s "$W/nc/statusbar/ResizeFact.h" ../statusbar/ResizeFact.h; then echo "FAIL  made-to-fail (no clear with the piece off): the change did not apply"; FAILS=$((FAILS + 1))
  elif RZT_SKIPPED=1 swrun "$W/nc" "no clear with the piece off" 1; then echo "FAIL  made-to-fail (no clear with the piece off): not caught"; FAILS=$((FAILS + 1))
  else [ -n "$Q" ] || echo "PASS  made-to-fail (no clear of an earlier SpringBoard's word with the crash guard's piece off): caught"; fi
  # the follow before the switch (1.8.9's F51b head): its off rows must fail; without that commit here, a note
  if git -C .. show 8303088d:statusbar/ResizeFact.h > "$W/old.h" 2>/dev/null && grep -q 'static void DMRZFollow(BOOL styleMac) {' "$W/old.h"; then
    mkdir -p "$W/old/statusbar"; cp -R "$W/now/common" "$W/old/"; cp "$W/old.h" "$W/old/statusbar/ResizeFact.h"
    r=0; swrun "$W/old" "1.8.9 before the switch" 1 || r=$?
    if [ $r = 1 ]; then [ -n "$Q" ] || echo "PASS  made-to-fail (1.8.9's follow before the switch, 8303088d): its off rows fail"
    else echo "FAIL  made-to-fail (1.8.9's follow before the switch): not caught (rc $r)"; FAILS=$((FAILS + 1)); fi
  else echo "NOTICE 1.8.9's ResizeFact.h before the switch (8303088d) is not in this checkout's history: not played"; fi
  # made-to-fail: the switch read after MacPointer's word (it must stop the follow before anything is read)
  mkdir -p "$W/late/statusbar"; cp -R "$W/now/common" "$W/late/"; cp ../statusbar/ResizeFact.h "$W/late/statusbar/"
  perl -0pi -e 's/BOOL on = styleMac && gDMPtrResizeOn && gDMPointerAttached && !DMRZSkipped\(\) && MSBDMPVerdictDraws\(MSBDMPVerdict\(DMRZPointerStatus\(\)\)\);/BOOL on = styleMac \&\& gDMPointerAttached \&\& !DMRZSkipped() \&\& MSBDMPVerdictDraws(MSBDMPVerdict(DMRZPointerStatus())) \&\& gDMPtrResizeOn;/' "$W/late/statusbar/ResizeFact.h"
  if cmp -s "$W/late/statusbar/ResizeFact.h" ../statusbar/ResizeFact.h; then echo "FAIL  made-to-fail (the switch read last): the change did not apply"; FAILS=$((FAILS + 1))
  elif swrun "$W/late" "the switch read last" 1; then echo "FAIL  made-to-fail (the switch read last): not caught"; FAILS=$((FAILS + 1))
  else [ -n "$Q" ] || echo "PASS  made-to-fail (the switch read last, MacPointer's word read while off): caught"; fi
fi
if [ "$FAILS" = 0 ]; then echo "test-macresizecursor: all checks pass"; else echo "test-macresizecursor: FAILED ($FAILS)"; exit 1; fi
