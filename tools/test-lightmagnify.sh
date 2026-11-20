#!/bin/bash
# test-lightmagnify.sh: Magnify Traffic Lights' layout and pick rule (common/LightMagnify.h) -- see test-lightmagnify.c.
# 1.8.8 (KT 19 Nov, "Lets also make Traffic light magnification apply to cursor too but less"): the pointer grows the lights where they are, a little
# (design: plans/tl-pointer-magnify.md). The C test carries its rule and its state (P1-P14, T1-T15); then the sites S1-S24 below, each
# with a made-to-fail copy, and made-to-fail copies of the rule (M1-M13), each must fail. S16-S18, T13 and M9: the review of the build (19 Nov);
# S19-S21, T14 and M10: its re-review (the sendEvent: pass-through notes touches only while a set has something of the pointer's on it); S22-S24,
# T15 and M11-M13: D48 (20 Nov), the resting pointer's hold ends when iPadOS hides the pointer, as MacPointer in pointeruid says (common/PointerFade.h).
cd "$(dirname "$0")" || exit 1
OUT="${TMPDIR:-/tmp}/test-lightmagnify.$$"
W=$(mktemp -d); trap 'rm -rf "$W" "$OUT"' EXIT
rc=0
if clang -std=c11 -O1 -Wall -Werror -o "$OUT" test-lightmagnify.c 2> "$W/cc.txt"; then "$OUT" || rc=1
else cat "$W/cc.txt" | head -20; echo "FAIL  test-lightmagnify.c does not build against common/LightMagnify.h (the pointer's rule and state missing?)"; rc=1; fi
# Only a finger opens the pill: a mouse or trackpad click reaches SpringBoard as a DIRECT touch (type 0), so the press refuses a pointer's touch by
# Desktop.h's DMDesktopPointerTouch, not by its type alone (review 1.8.6, gestures: every click on a light opened the pill).
if grep -q 'else if (DMDesktopPointerTouch(touch, nil)) why = @"not a finger (pointer)";' ../statusbar/LightMagnify.h; then
  echo "PASS  the press refuses a pointer's click (a type 0 touch from the pointer): a click on a light is the light's own"
else echo "FAIL  statusbar/LightMagnify.h: the press takes a pointer's click (refused by touch type only)"; rc=1; fi

echo "== the pointer (1.8.8): the sites"
python3 -I - .. <<'PY' || rc=1
import os, re, sys
root = sys.argv[1]
names = ['statusbar/LightMagnify.h', 'statusbar/StatusBar.x', 'common/LightMagnify.h', 'tools/crashmap-rules.txt',
         'statusbar/macstatusbarprefs/Resources/Windows.plist', 'statusbar/macstatusbarprefs/MSBRootListController.m',
         'statusbar/macpointer/MacPointer.x', 'common/PointerFade.h']
real = {n: open(root + '/' + n, errors='replace').read() if os.path.exists(root + '/' + n) else '' for n in names}   # (a file not there: its checks fail)
SENT = 'With a trackpad or mouse, the button under the pointer grows a little.'

def block(text, start, end):   # from the first line starting with `start` to the next line starting with `end` (both kept); '' if none
    i = text.find('\n' + start)
    if i < 0: return ''
    j = text.find('\n' + end, i + 1)
    return text[i + 1:(j + 1 + len(end)) if j >= 0 else len(text)]
def method(text, head):   # a method or function from its first line (starting with head) to its closing brace at column 0
    i = text.find('\n' + head)
    if i < 0: return ''
    j = text.find('\n}', i + 1)
    k = text.find('\n', i + 1)
    first = text[i + 1:k]
    if first.rstrip().endswith('}') and first.count('{') == first.count('}'): return first   # (a one-line method)
    return text[i + 1:j + 2] if j >= 0 else ''
def before(text, a, b):
    i, j = text.find(a), text.find(b)
    return i >= 0 and j >= 0 and i < j

def sites(F):
    L, S, C = F['statusbar/LightMagnify.h'], F['statusbar/StatusBar.x'], F['common/LightMagnify.h']
    R = {}
    grp = block(S, '@implementation DMLightGroup', '@end')
    hov = method(grp, '- (void)hover:(UIHoverGestureRecognizer *)g {')
    R['S1'] = (before(hov, 'CGPoint p = [g locationInView:self.container];', 'if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {')
               and before(hov, 'BOOL held = DMLightMagnifyHover(self.container, g, over, p);', 'self.lit = over || held;') and 'self.lit = over;' not in hov,
               "S1 the lights' hover (DMLightGroup -hover:) hands its place to the magnifier before it lights them: -apply's look then sees the new state")
    opn = method(L, '- (void)openAt:(CGPoint)p {')
    first = opn.split('\n')[1].strip() if opn.count('\n') > 1 else ''
    R['S3'] = (first == 'if (_lp.grown || _lp.held) { _lp.held = 0; [self pointerRest:NO why:@"a finger"]; }   // (1.8.8: a finger after the pointer: the lights at their own size first, its animation gone, so the pill opens from their size)'
               and before(opn, '[self pointerRest:NO why:@"a finger"]', 'CGRect fr = [first convertRect:first.bounds toView:c];'),
               "S3 a finger after the pointer: openAt's first statement puts the pointer's sizes back at once, before it reads the first light's size")
    m0, m1 = L.find('// ---- the pointer (1.8.8)'), L.find('// ---- end of the pointer')
    ptr = L[m0:m1] if 0 <= m0 < m1 else ''
    bad = [w for w in ('.frame =', '.bounds =', '.center =', '.alpha =', 'UIHoverGestureRecognizer alloc', 'addGestureRecognizer') if w in ptr]
    R['S4'] = (ptr != '' and L.count('// ---- the pointer (1.8.8)') == 1 and L.count('// ---- end of the pointer') == 1 and not bad and '.transform = ' in ptr,
               "S4 the pointer's block writes only the lights' transforms: no frame, bounds, centre or alpha, no recognizer of its own" + (' -- found: ' + ', '.join(bad) if bad else ''))
    defs = ['__attribute__((noinline)) static BOOL DMLightMagnifyHover(UIView *container, UIHoverGestureRecognizer *g, BOOL over, CGPoint p) {',
            '__attribute__((noinline)) static void DMLightMagnifyClick(UIView *container, BOOL down) {',
            '__attribute__((noinline)) static void DMLightMagnifyCheck(UIView *container) {',
            '__attribute__((noinline)) static void DMLightMagnifyTouchNote(UIEvent *event) {',
            '__attribute__((noinline)) static void DMLightMagnifySendEvent(id self, SEL _cmd, UIEvent *event) {']
    R['S5'] = (all(L.count('\n' + d) == 1 for d in defs) and L.find(defs[0]) > L.find('static void DMLightMagnifyAttach('),
               "S5 the entry points from the light group and SpringBoard's touches, out of line in LightMagnify.h (a crash in them is Magnify Traffic Lights')")
    app = method(grp, '- (void)apply {')
    R['S6'] = (app.rstrip().endswith('DMLightMagnifyCheck(self.container);   // (Magnify Traffic Lights, 1.8.8: a set grown under the pointer goes back at once when its window moved, hid or went -- LightMagnify.h)\n}')
               and '\n- (void)down { DMLightMagnifyClick(self.container, YES); self.lit = YES; }\n' in grp
               and '\n- (void)up { DMLightMagnifyClick(self.container, NO); self.lit = NO; }\n' in grp,
               "S6 -apply ends with the magnifier's look; a light's touch down and up tell it (a pointer click keeps the sizes)")
    W, P = F['statusbar/macstatusbarprefs/Resources/Windows.plist'], F['statusbar/macstatusbarprefs/MSBRootListController.m']
    full = "Magnify Traffic Lights: touching a window's buttons with a finger makes them bigger, so you can pick one. Slide to another, lift to use it, or lift away to cancel. " + SENT
    R['S7'] = (full + '</string>' in W and '@"magnifyTrafficLights": @"' + full + '",' in P
               and 'a finger or the pointer on the lights grows them' in S,
               "S7 Settings says so, the same in the footer and in the search (one switch for the finger and the pointer)")
    shd = method(L, '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {')
    mark = '\n    MSBDLightPtrMark(&_lp, touch.type == UITouchTypeIndirectPointer || [why isEqualToString:@"not a finger (pointer)"], CACurrentMediaTime());'
    R['S12'] = (before(shd, 'if (why && gLightMagnify) DMLog(', mark) and before(shd, mark, 'return why == nil;'),
                "S12 the press marks each touch it sees as the pointer's or not, after its refusal (line 56 unchanged): only the pointer's click puts sizes back")
    snd = method(L, defs[4][:-2])
    wat = method(L, 'static void DMLightMagnifyWatchTouches(void) {')
    note = method(L, defs[3][:-2])
    sl = snd.strip().split('\n')
    R['S9'] = (len(sl) >= 3 and sl[-2].strip() == 'o_DMLightMagnifySendEvent(self, _cmd, event);' and 'return' not in snd
               and 'if (gLightMagnify && !gGALightsInert && gLightPtrLive && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);' in snd
               and 'static BOOL done = NO;' in wat and 'MSHookMessageEx(sb, s, (IMP)DMLightMagnifySendEvent, (IMP *)&o_DMLightMagnifySendEvent);' in wat
               and 't.phase == UITouchPhaseBegan && t.type != UITouchTypeIndirect' in note and 'gLightPtrTouchAt = CACurrentMediaTime();' in note
               and 'DMLightMagnifyWatchTouches();' in ptr,
               "S9 SpringBoard's touches noted (any but a finger on the trackpad) from the first hover over a set of lights: hooked once, every event passed on")
    pho = method(L, '- (BOOL)pointerHover:(UIHoverGestureRecognizer *)g over:(BOOL)over at:(CGPoint)p {')
    look = method(L, '- (void)pointerHoldLook:(unsigned)gen {')
    R['S10'] = ('MSBDLightPtrHoverOff(&_lp, (long)g.state, [self pointerClicking], shown, own, self.outer != nil, now, gLightPtrTouchAt)' in pho
                and 'BOOL own = (!sc || sc == [UIScreen mainScreen]) && gLightPtrTouchesNoted;' in pho and '#include "DockHover.h"' in C
                and all(w in look for w in ('dispatch_async(q, ^{', '"{CGPoint=dd}16@0:8"', 'DMPtrIPadNative(', 'fromCoordinateSpace:[UIScreen mainScreen].fixedCoordinateSpace',
                                            'MSBDHoverHoldStep(', 'MSBDHoverHoldInterval(', 'if (!m || !m->_lp.held || gen != m.ptrHoldGen', 'if (!_lp.held || gen != self.ptrHoldGen) return;')),
                "S10 a resting pointer (H): UIKit's cancel held by the Dock's rules on the iPad only, backboardd's place read off the main thread in its shape, in the iPad's own region")
    rst = method(L, '- (void)pointerRest:(BOOL)animated why:(NSString *)why {')
    R['S11'] = ('performWithoutAnimation:' in rst and 'removeAnimationForKey:' in rst and 'hasPrefix:@"transform"' in rst,
                "S11 back to rest at once also takes the running grow animations off (a leftover one kept drawing the grow)")
    clk = method(L, '- (BOOL)pointerClicking {')
    R['S13'] = ('.isTracking' in clk and 'ptrClick' not in L.replace('pointerClick', ''),
                "S13 a click in progress is read live (a button of the set tracking a pointer's touch), never a stored flag a missed touch up would leave set")
    pat = method(L, '- (void)pointerAt:(CGPoint)p {')
    chk = method(L, '- (void)pointerCheck {')
    vis = method(L, '- (BOOL)pointerVisible {')
    R['S14'] = ('toCoordinateSpace:sc.fixedCoordinateSpace' in pat and 'fromCoordinateSpace:sc.fixedCoordinateSpace' in chk and 'MSBDLightPtrButtonAt(' in chk
                and 'MSBDLightPtrCheck(&_lp,' in chk and 'for (UIView *v = c; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;' in vis
                and 'MSBDLightPtrScales(' in pat,
                "S14 a stale grow: the pointer's last place kept in its screen's space, -apply's look rests a set when it is no longer on one of its buttons or hidden")
    dec = ['static BOOL DMLightMagnifyHover(UIView *container, UIHoverGestureRecognizer *g, BOOL over, CGPoint p);',
           'static void DMLightMagnifyClick(UIView *container, BOOL down);', 'static void DMLightMagnifyCheck(UIView *container);']
    R['S15'] = (all(before(S, d, '@implementation DMLightGroup') for d in dec),
                "S15 StatusBar.x declares the three entry points before the light group that calls them")
    # The review of the build (19 Nov): S16 a hold that ends in its own first look leaves the lights unlit; S17 the window box taken again at each visit
    # to the lights; S18 a move off the lights with nothing on them answered at once (MSBDLightPtrIdle; the C test's T13: HoverOff would do nothing).
    R['S16'] = ('\n        case MSBDLightPtrHold:\n            [self pointerHoldStart];\n            return _lp.held != 0;' in pho,
                "S16 a hold its own first look ends at once (the lights hidden or gone, the screen off or locked) leaves the lights unlit: the hover hears that nothing holds them")
    R['S17'] = ('\n    BOOL shown = self.ptrOver || _lp.grown;\n    self.ptrOver = NO;\n    self.ptrBoxValid = NO;' in pho and before(pho, '\n    if (over) {', '\n    self.ptrBoxValid = NO;')
                and before(pho, '\n    self.ptrBoxValid = NO;', 'switch (MSBDLightPtrHoverOff(') and 'self.ptrBoxValid = NO;' in rst,
                "S17 the window box is taken again at each visit to the lights: the hover leaving them lets it go (a rest too), so a set moved against it since gets its own")
    body = [x.strip() for x in pho.split('\n')[1:6]]
    R['S18'] = (len(body) == 5 and body[0] == 'double now = CACurrentMediaTime();' and body[1] == '[self pointerLogState:g.state over:over now:now];'
                and body[2].startswith('if (MSBDLightPtrIdle(&_lp, over, self.ptrOver)) return NO;') and body[3] == 'self.ptrHover = g;' and body[4] == 'if (over) {'
                and 'static inline int MSBDLightPtrIdle(const MSBDLightPtr *s, int over, int shown) {' in C,
                "S18 a move off the lights with nothing of the pointer's on them (over a title bar round them) is answered right after the state's log: no screen, click or store work per move")
    # The re-review (19 Nov), finding 1: the pass-through stays in for SpringBoard's life, so it looks at an event only through plain C loads first
    # (S19); a set turns them on where it starts to have something of the pointer's on it (S20) and off, its own only, where nothing is left (S21).
    sb = [x.strip() for x in snd.strip().split('\n')[1:-1]]
    R['S19'] = (sb == ['if (gLightMagnify && !gGALightsInert && gLightPtrLive && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);',
                       'o_DMLightMagnifySendEvent(self, _cmd, event);']
                and 'static BOOL gLightPtrLive = NO;' in L and 'static BOOL gLightMagnify = YES;' in L and 'static BOOL gGALightsInert = NO;' in S,
                "S19 the sendEvent: pass-through looks at an event only after plain loads (switched on, not Guided Access, a set with something of the pointer's on it), then passes every event on")
    lon = method(L, '- (void)pointerLiveOn {')
    reg = method(L, '- (void)pointerRegrow {')
    hst = method(L, '- (void)pointerHoldStart {')
    R['S20'] = ('\n        if (gLightMagnify && !gGALightsInert) { [self pointerLiveOn]; DMLightMagnifyWatchTouches(); }\n        [self pointerAt:p];' in pho
                and before(reg, '{ _lp.grown = 0; return; }', '[self pointerLiveOn];') and before(reg, '[self pointerLiveOn];', '[self pointerDraw:')
                and before(hst, 'gLightPtrHolder = self;', '[self pointerLiveOn];') and before(hst, '[self pointerLiveOn];', '[self pointerHoldLook:')
                and before(look, '[m pointerLiveOn];', '[m pointerAt:p];') and before(look, 'case MSBDLightPtrKeep: {', '[m pointerLiveOn];')
                and 'gLightPtrLive = YES; gLightPtrLiveSet = self;' in lon
                and L.count('gLightPtrLive = YES') == 1 and L.count('gLightPtrLiveSet = self') == 1,
                "S20 a set turns SpringBoard's touches on where it starts to have something of the pointer's on it: each report over the lights, a grow put back for a click, a hold's start and each look that keeps it")
    lof = method(L, '- (void)pointerLiveOff {')
    wnt = method(L, '- (BOOL)pointerWantsTouches {')
    sw = pho[pho.find('    if (!gLightMagnify || gGALightsInert) {'):pho.find('    UIScreen *sc = self.container.window.screen;')]
    R['S21'] = ('if (!gLightPtrLive || gLightPtrLiveSet != self || [self pointerWantsTouches]) return;' in lof and 'gLightPtrLive = NO; gLightPtrLiveSet = nil;' in lof
                and 'MSBDLightPtrWantsTouches(&_lp, self.ptrOver)' in wnt
                and 'static inline int MSBDLightPtrWantsTouches(const MSBDLightPtr *s, int shown) { return shown || s->grown || s->held; }' in C
                and before(rst, '_lp.grown = 0;', '[self pointerLiveOff];')
                and before(sw, "if (_lp.grown) [self pointerRest:YES why:@\"switched off\"];", '[self pointerLiveOff];') and before(sw, '[self pointerLiveOff];', 'return NO;')
                and '\n        default:\n            [self pointerLiveOff];' in pho
                and note.split('\n')[1].strip() == 'if (![gLightPtrLiveSet pointerWantsTouches]) {' and before(note, 'gLightPtrLive = NO; gLightPtrLiveSet = nil;', 'for (UITouch *t in event.allTouches)')
                and before(note, 'return;', 'for (UITouch *t in event.allTouches)')
                and L.count('gLightPtrLive = NO; gLightPtrLiveSet = nil;') == 2,
                "S21 ... and off, by the set that turned them on only, once it has nothing of the pointer's left (a rest, the hover off the lights); the note turns them off when that set went or wants nothing")
    # D48 (20 Nov): the resting pointer's hold ends when iPadOS hides the pointer. Each look reads pointeruid's word after UIKit's own check and before
    # backboardd's place, heard from the hold's start (S22); the moment the word changes the set held then hears it (S23); MacPointer in pointeruid says
    # it, in release builds too, only when it changes, whatever the Pointer Style (S24).
    fad = '    if (MSBDLightPtrFade(&_lp, NO, DMLightPtrFadeState(), CACurrentMediaTime()) == MSBDLightPtrUnhold) { [self pointerHoldDone:@"the pointer faded"]; return; }'
    R['S22'] = (fad in look and before(look, 'if ([self pointerHovering]) { MSBDLightPtrHoldLook(&_lp, MSBDHoverHoldUIKit,', fad) and before(look, fad, 'dispatch_async(q, ^{')
                and before(look, 'if (gone) {', fad)
                and before(hst, '[self pointerLiveOn];', 'DMLightMagnifyWatchFade();') and before(hst, 'DMLightMagnifyWatchFade();', '[self pointerHoldLook:')
                and 'static inline int MSBDLightPtrFade(MSBDLightPtr *s, int hovering, unsigned long long fade, double now) {' in C and '#include "PointerFade.h"' in C,
                "S22 a hold ends when the pointer fades: each look reads pointeruid's word after UIKit's own check and before backboardd's place, heard from the hold's start (D48)")
    fno = method(L, '- (void)pointerFadeNote {')
    wfd = method(L, 'static void DMLightMagnifyWatchFade(void) {')
    fst = method(L, 'static unsigned long long DMLightPtrFadeState(void) {')
    R['S23'] = ('if (MSBDLightPtrFade(&_lp, [self pointerHovering], DMLightPtrFadeState(), CACurrentMediaTime()) == MSBDLightPtrUnhold) [self pointerHoldDone:@"the pointer faded"];' in fno
                and 'static BOOL done = NO;' in wfd and before(wfd, 'if (done) return;', 'notify_register_dispatch(')
                and 'notify_register_dispatch(kMSBDPointerFadeNote, &gLightPtrFadeToken, dispatch_get_main_queue(), ^(int t) {' in wfd and '[gLightPtrHolder pointerFadeNote];' in wfd
                and 'if (gLightPtrFadeHeard && notify_get_state(gLightPtrFadeToken, &v) != NOTIFY_STATUS_OK) v = MSBDPointerFadeUnsaid;' in fst
                and L.count('DMLightMagnifyWatchFade();') == 1 and 'DMLightMagnifyWatchFade();' in hst and 'DMLightMagnifyWatchFade' not in S,
                "S23 ... and the moment pointeruid's word changes, the set held then hears it (unless its hover began again); the word heard once, from the first hold, never at a constructor")
    M, PF = F['statusbar/macpointer/MacPointer.x'], F['common/PointerFade.h']
    sps = method(M, '- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error {')
    rd = 'gMPAutoHidden = [[state valueForKey:@"pointerAutoHidden"] boolValue];'
    gate = 'if (MPDisplayInfoFor(own).reason == 0) {'
    pub = 'if (fadeOK && fade != fadeSaid) { fadeSaid = fade; notify_set_state(fadeToken, fade); notify_post(kMSBDPointerFadeNote); }'
    span = sps[sps.find(gate):sps.find(pub)] if gate in sps and pub in sps else ''
    head = sps[:sps.find(gate)] if gate in sps else ''
    code = [x for x in PF.split('\n') if x.strip() and not x.strip().startswith('//')]
    R['S24'] = ('#include "../../common/PointerFade.h"' in M and '%hook PUIDPointerRenderingRootViewController' in M and before(sps, rd, 'BOOL r = %orig;')
                and before(sps, 'BOOL r = %orig;', gate) and before(sps, 'if (!last || last.unsignedIntegerValue != sig) {', gate) and before(sps, '            MPUpdate(own);', gate)
                and before(sps, gate, pub) and span != '' and head.count('#if') == head.count('#endif')
                and '#if' not in span and 'MPEnabled' not in span and 'gMPStandDown' not in span and 'uint64_t fade = MSBDPointerFadeOf(gMPAutoHidden);' in span
                and 'if (!fadeTried) { fadeTried = YES; fadeOK = notify_register_check(kMSBDPointerFadeNote, &fadeToken) == NOTIFY_STATUS_OK; }' in span
                and '#define kMSBDPointerFadeNote "com.besiktasliseba.macpointer.faded"' in PF and all(x.startswith('#') for x in code),
                "S24 MacPointer in pointeruid says iPadOS's hide of the pointer (pointerAutoHidden) to SpringBoard for the iPad's own display, in release builds too, only when that display's state changed, whatever the Pointer Style; PointerFade.h macros only")
    # S8: the crash map. Every function of the pointer's is Magnify Traffic Lights' (the file rule: no sym rule takes its name, no sec rule its section);
    # the pass-through of -[SpringBoard sendEvent:] (on every touch stack once a set of lights was hovered) is transparent, as the other sendEvent: hooks.
    sym, sec, fil = [], [], []
    for raw in F['tools/crashmap-rules.txt'].split('\n'):
        line = re.split(r'\s+#', raw, 1)[0].strip(); f = line.split()
        if len(f) == 4 and f[0] in ('sym', 'sec', 'file') and f[1] == 'MacStatusBarCore':
            (sym if f[0] == 'sym' else sec if f[0] == 'sec' else fil).append((re.compile(f[2]), f[3]))
    first = lambda rules, s: next((t for rx, t in rules if rx.search(s)), None)
    meths = []
    for m in re.finditer(r'^- \([^)]*\)([^{\n]*)\{', ptr, re.M):
        sig = m.group(1)
        meths.append(''.join(x + ':' for x in re.findall(r'(\w+):', sig)) if ':' in sig else sig.strip())
    syms = []
    for sel in meths:
        syms += ['-[DMLightMagnifier %s]' % sel, '__36-[DMLightMagnifier %s]_block_invoke' % sel, '__36-[DMLightMagnifier %s]_block_invoke_2' % sel]
    cfun = ['DMLightMagnifyHover', 'DMLightMagnifyClick', 'DMLightMagnifyCheck', 'DMLightMagnifyTouchNote', 'DMLightMagnifyWatchTouches',
            'DMLightPtrFadeState', 'DMLightMagnifyWatchFade']
    syms += ['_' + n for n in cfun] + ['___' + n + '_block_invoke' for n in cfun]
    taken = [s for s in syms if first(sym, s) is not None]
    heads = [h.strip() for t in (L, C) for h in re.findall(r'^//\s?(?:====|----).*$', t, re.M)]
    hsec = [h for h in heads if first(sec, h) is not None]
    R['S8'] = (len(meths) >= 12 and not taken and not hsec and first(fil, 'LightMagnify.h') == 'magnifyTrafficLights'
               and first(sym, '_DMLightMagnifySendEvent') == 'transparent' and first(sym, 'DMLightMagnifySendEvent') == 'transparent'
               and first(sym, '_DMLightMagnifySendEventX') != 'transparent',
               "S8 the crash map: the pointer's %d methods and its C functions (their blocks too) Magnify Traffic Lights' by their file, no section of theirs another's; the sendEvent: pass-through transparent" % len(meths)
               + (' -- by name: ' + ', '.join(taken) if taken else '') + (' -- sections: ' + ', '.join(hsec) if hsec else ''))
    return R

res = sites(real)
bad = 0
for k in sorted(res, key=lambda x: int(x[1:])):
    ok, what = res[k]
    print(('PASS  ' if ok else 'FAIL  ') + what)
    bad += not ok
print('== the sites, made to fail (each copy must fail its check)')
def mut(name, a, b, count=1):
    F = dict(real)
    if F[name].count(a) < 1: return None
    F[name] = F[name].replace(a, b, count)
    return F
copies = [
    ('S1', 'the hover lights them before the magnifier sees it', mut('statusbar/StatusBar.x', '    BOOL held = DMLightMagnifyHover(self.container, g, over, p);',
        '    self.lit = over;\n    BOOL held = DMLightMagnifyHover(self.container, g, over, p);')),
    ('S3', "openAt reads the first light's size before the rest", mut('statusbar/LightMagnify.h', '    if (_lp.grown || _lp.held) { _lp.held = 0; [self pointerRest:NO why:@"a finger"]; }', '')),
    ('S4', 'the pointer block sets an alpha', mut('statusbar/LightMagnify.h', '// ---- end of the pointer', '- (void)x { self.dots.firstObject.alpha = 1.0; }\n// ---- end of the pointer')),
    ('S5', 'the hover entry point inlined', mut('statusbar/LightMagnify.h', '__attribute__((noinline)) static BOOL DMLightMagnifyHover(', 'static BOOL DMLightMagnifyHover(')),
    ('S6', "-apply without the magnifier's look", mut('statusbar/StatusBar.x', '    DMLightMagnifyCheck(self.container);   // (Magnify', '    // (Magnify')),
    ('S6', 'a touch up not told', mut('statusbar/StatusBar.x', '- (void)up { DMLightMagnifyClick(self.container, NO); self.lit = NO; }', '- (void)up { self.lit = NO; }')),
    ('S7', 'the search text without the pointer', mut('statusbar/macstatusbarprefs/MSBRootListController.m', ' ' + SENT + '",', '",')),
    ('S8', 'the sendEvent: pass-through not transparent', mut('tools/crashmap-rules.txt', '^_*DMLightMagnifySendEvent$ transparent', '^_*DMLightMagnifySendEventNot$ transparent')),
    ('S8', "a section of the pointer's taken by the traffic lights' rule", mut('statusbar/LightMagnify.h', '// ---- the pointer (1.8.8)', '// ---- the pointer (1.8.8) of the traffic lights')),
    ('S8', "a name of the pointer's taken by another rule", mut('tools/crashmap-rules.txt', '\nfile MacStatusBarCore ^LightMagnify\\.h$ magnifyTrafficLights', '\nsym MacStatusBarCore pointerAt windowingEnabled\nfile MacStatusBarCore ^LightMagnify\\.h$ magnifyTrafficLights')),
    ('S9', 'the pass-through holds a touch back', mut('statusbar/LightMagnify.h', ' && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);', ' && event.type == UIEventTypeTouches) { DMLightMagnifyTouchNote(event); return; }')),
    ('S9', 'a finger on the trackpad counted as a touch', mut('statusbar/LightMagnify.h', 't.phase == UITouchPhaseBegan && t.type != UITouchTypeIndirect', 't.phase == UITouchPhaseBegan')),
    ('S10', "the hold reads backboardd's place outside the iPad's own region", mut('statusbar/LightMagnify.h', 'DMPtrIPadNative(', 'DMPtrAnyNative(', 2)),
    ('S10', 'the hold on any screen', mut('statusbar/LightMagnify.h', 'BOOL own = (!sc || sc == [UIScreen mainScreen]) && gLightPtrTouchesNoted;', 'BOOL own = YES;')),
    ('S11', 'the rest leaves the running animation', mut('statusbar/LightMagnify.h', 'removeAnimationForKey:', 'animationForKey:')),
    ('S12', 'no mark for the pointer', mut('statusbar/LightMagnify.h', '    MSBDLightPtrMark(&_lp, touch.type', '    if (0) MSBDLightPtrMark(&_lp, touch.type')),
    ('S13', 'a stored click flag', mut('statusbar/LightMagnify.h', '.isTracking', '.ptrClicking')),
    ('S14', "-apply's look without the pointer's place", mut('statusbar/LightMagnify.h', 'fromCoordinateSpace:sc.fixedCoordinateSpace', 'fromCoordinateSpace:sc.coordinateSpace')),
    ('S14', 'a hidden ancestor not seen', mut('statusbar/LightMagnify.h', 'for (UIView *v = c; v; v = v.superview) if (v.hidden || v.alpha < 0.01) return NO;', 'if (c.hidden) return NO;')),
    ('S15', 'the entry points declared after the light group', mut('statusbar/StatusBar.x', 'static void DMLightMagnifyCheck(UIView *container);', '')),
    ('S16', 'a hold ended in its first look still answered as kept', mut('statusbar/LightMagnify.h', '            return _lp.held != 0;', '            return YES;')),
    ('S17', 'the window box kept across visits', mut('statusbar/LightMagnify.h', '\n    self.ptrOver = NO;\n    self.ptrBoxValid = NO;', '\n    self.ptrOver = NO;')),
    ('S18', 'no answer at once off the lights', mut('statusbar/LightMagnify.h', '    if (MSBDLightPtrIdle(&_lp, over, self.ptrOver)) return NO;', '    if (0) return NO;')),
    ('S18', 'the screen looked up before the answer', mut('statusbar/LightMagnify.h', '    if (MSBDLightPtrIdle(&_lp, over, self.ptrOver)) return NO;',
        '    UIScreen *sc0 = self.container.window.screen; (void)sc0;\n    if (MSBDLightPtrIdle(&_lp, over, self.ptrOver)) return NO;')),
    ('S19', 'the gate dropped (every touch event noted)', mut('statusbar/LightMagnify.h', '    if (gLightMagnify && !gGALightsInert && gLightPtrLive && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);',
        '    if (event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);')),
    ('S19', 'a message before the gate', mut('statusbar/LightMagnify.h', '    if (gLightMagnify && !gGALightsInert && gLightPtrLive && event.type == UIEventTypeTouches) DMLightMagnifyTouchNote(event);',
        '    if (event.type == UIEventTypeTouches && gLightMagnify && !gGALightsInert && gLightPtrLive) DMLightMagnifyTouchNote(event);')),
    ('S20', 'the report over the lights not turning it on', mut('statusbar/LightMagnify.h', '{ [self pointerLiveOn]; DMLightMagnifyWatchTouches(); }', 'DMLightMagnifyWatchTouches();')),
    ("S20", "a hold's start not turning it on", mut('statusbar/LightMagnify.h', '    gLightPtrHolder = self;\n    [self pointerLiveOn];\n', '    gLightPtrHolder = self;\n')),
    ('S20', 'a grow put back for a click not turning it on', mut('statusbar/LightMagnify.h', '{ _lp.grown = 0; return; }\n    [self pointerLiveOn];\n', '{ _lp.grown = 0; return; }\n')),
    ('S21', 'a rest not turning it off', mut('statusbar/LightMagnify.h', '    [self pointerLiveOff];\n    NSArray<UIView *> *dots = self.dots;', '    NSArray<UIView *> *dots = self.dots;')),
    ('S21', "another set's turning it off", mut('statusbar/LightMagnify.h', 'if (!gLightPtrLive || gLightPtrLiveSet != self || [self pointerWantsTouches]) return;', 'if (!gLightPtrLive || [self pointerWantsTouches]) return;')),
    ('S21', 'the hover off the lights with nothing left not turning it off', mut('statusbar/LightMagnify.h', '        default:\n            [self pointerLiveOff];', '        default:')),
    ('S21', 'the note without its check', mut('statusbar/LightMagnify.h', '    if (![gLightPtrLiveSet pointerWantsTouches]) {', '    if (0) {')),
    ('S22', "a look blind to the pointer's fade", mut('statusbar/LightMagnify.h', '    if (MSBDLightPtrFade(&_lp, NO, DMLightPtrFadeState(), CACurrentMediaTime()) == MSBDLightPtrUnhold) { [self pointerHoldDone:@"the pointer faded"]; return; }', '')),
    ('S22', "the fade's word not heard at a hold's start", mut('statusbar/LightMagnify.h', '    DMLightMagnifyWatchFade();   // (once', '    // (once')),
    ('S23', 'the fade ending a hold whose hover began again', mut('statusbar/LightMagnify.h', 'MSBDLightPtrFade(&_lp, [self pointerHovering], DMLightPtrFadeState()', 'MSBDLightPtrFade(&_lp, NO, DMLightPtrFadeState()')),
    ('S23', 'the change not told to the set held', mut('statusbar/LightMagnify.h', '        [gLightPtrHolder pointerFadeNote];\n', '')),
    ('S23', 'the watch made again at each hold', mut('statusbar/LightMagnify.h', '    if (done) return;\n    done = YES;\n    gLightPtrFadeHeard', '    done = YES;\n    gLightPtrFadeHeard')),
    ('S23', 'the watch made at a constructor', mut('statusbar/StatusBar.x', '%ctor {', '%ctor {\n    DMLightMagnifyWatchFade();')),
    ('S24', 'said only in debug builds', mut('statusbar/macpointer/MacPointer.x', '            if (MPDisplayInfoFor(own).reason == 0) {', '#if DEBUG\n            if (MPDisplayInfoFor(own).reason == 0) {')),
    ('S24', 'said for every display', mut('statusbar/macpointer/MacPointer.x', '            if (MPDisplayInfoFor(own).reason == 0) {', '            if (1) {')),
    ('S24', 'said only with the Mac pointer drawn', mut('statusbar/macpointer/MacPointer.x', '        uint64_t fade = MSBDPointerFadeOf(gMPAutoHidden);', '        uint64_t fade = MSBDPointerFadeOf(gMPAutoHidden && MPEnabled());')),
    ('S24', 'said at every update', mut('statusbar/macpointer/MacPointer.x', 'if (fadeOK && fade != fadeSaid) { fadeSaid = fade;', 'if (fadeOK) { fadeSaid = fade;')),
    ('S24', 'a function in PointerFade.h', mut('common/PointerFade.h', '#pragma once\n', '#pragma once\nstatic inline int MSBDPointerFadeX(void) { return 0; }\n')),
]
for k, what, F in copies:
    if F is None: print('FAIL  made to fail (%s, %s): the text to change was not found' % (k, what)); bad += 1; continue
    ok = sites(F)[k][0]
    print(('FAIL  made to fail (%s, %s): its check still passes' if ok else 'PASS  made to fail (%s, %s): caught') % (k, what))
    bad += ok
sys.exit(1 if bad else 0)
PY

echo "== the pointer's rule and state, made to fail (common/LightMagnify.h copies: each must fail the C test)"
mtf() {   # $1 id, $2 what, $3 the text to change, $4 what it becomes, $5 the check that must fail
  python3 -I - ../common/LightMagnify.h "$W/LightMagnify.h" "$3" "$4" <<'PY' || { echo "FAIL  made to fail ($1, $2): the text to change was not found"; rc=1; return; }
import sys
t = open(sys.argv[1]).read()
if sys.argv[3] not in t: sys.exit(1)
open(sys.argv[2], 'w').write(t.replace(sys.argv[3], sys.argv[4], 1))
PY
  if ! clang -std=c11 -O1 -Wall -Werror -iquote ../common -DMSBD_LIGHTMAG_H="\"$W/LightMagnify.h\"" -o "$W/t" test-lightmagnify.c 2>/dev/null; then
    echo "FAIL  made to fail ($1, $2): the copy does not build"; rc=1
  elif "$W/t" | grep -q "^FAIL  $5"; then
    echo "PASS  made to fail ($1, $2): $5 caught"
  else echo "FAIL  made to fail ($1, $2): $5 still passes"; rc=1; fi
}
mtf M1 'the finger'"'"'s 0.5 for the pointer' '#define kMSBDLightPtrSwell   0.40' '#define kMSBDLightPtrSwell   0.50' 'P1 '
mtf M2 'no cap' '    if (!(s <= cap)) s = cap;' '    (void)cap;' 'P7 '
mtf M3 'grown in the ring round the buttons' '    if (under < 0) return -1;' '    if (under < 0) under = -2;' 'P5b only inside'
mtf M4 'any touch down puts the sizes back' '        && s->markPointer && s->markAt > 0 && now - s->markAt <= kMSBDLightPtrMarkIn' '' 'T4 '
mtf M5 'a cancel right after a touch held' '    if (ownScreen && MSBDHoverHoldsAfter(state, shown != 0, touchAt > 0 ? now - touchAt : -1.0)) {' '    if (ownScreen && state == 4 && shown) {' 'T11 '
mtf M6 "-apply's look blind to the pointer's place" '|| (s->grown && !onButton)' '' 'T9 '
mtf M7 'a click not held' '    if (clicking && s->grown) return MSBDLightPtrKeep;' '' 'T3 '
mtf M8 'a greyed light grows' '        if (!r->usable[i]) { out[i] = 1.0; continue; }' '' 'P14 '
mtf M9 'a grown set answered at once off the lights' 'return !over && !s->grown && !s->held && !shown;' 'return !over && !s->held && !shown;' 'T13 '
mtf M10 'a held set not wanting touches' 'return shown || s->grown || s->held; }' 'return shown || s->grown; }' 'T14 '
mtf M11 'the hold ended when the pointer shows too' 'fade != MSBDPointerFadeHidden) return MSBDLightPtrNothing;' 'fade == MSBDPointerFadeUnsaid) return MSBDLightPtrNothing;' 'T15 '
mtf M12 'the fade ends a hold whose hover began again' 'if (!s->held || hovering || fade' 'if (!s->held || fade' 'T15 '
mtf M13 'the fade never ends a hold' 'fade != MSBDPointerFadeHidden) return MSBDLightPtrNothing;' 'fade != 99ULL) return MSBDLightPtrNothing;' 'T15 '
[ $rc = 0 ] && echo "test-lightmagnify: all pass" || echo "test-lightmagnify: FAILED"
exit $rc
