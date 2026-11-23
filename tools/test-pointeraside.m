// test-pointeraside.m: Mac test (Mac Catalyst) of the Mac pointer's look at another pointer (statusbar/macpointer/MPAside.h) and of its words for
// SpringBoard, Settings > Pointer and Report a Problem (common/MacPointerStatus.h), 1.8.8.2, GitHub #17. Until 1.8.8.1.1 any other jailbreak
// library with a method on pointeruid's pointer classes turned the Mac pointer off for the whole run, also a hook that draws nothing, and nothing
// said so. Here: pointeruid's three classes are faked with the ivars MacPointer reads; the other library is a real library of its own under a
// "/var/jb/" path (OTHER_LIB, test-pointeraside-other.m), loaded as a tweak is. Built by tools/test-pointeraside.sh (MPASIDE_H: the header, or a
// made-to-fail copy).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include MPASIDE_H
#ifdef OLD_RULE_INC   // (1.8.8.1.1's stand-down rule, cut out of its MacPointer.x by the .sh)
static void MPLog(NSString *line) { (void)line; }   // (its debug log line: not kept here)
#include OLD_RULE_INC
#endif

static int fails = 0, passes = 0;
static void Check(BOOL ok, NSString *what, NSString *detail) {
    if (ok) { passes++; printf("PASS  %s\n", what.UTF8String); }
    else { fails++; printf("FAIL  %s%s%s\n", what.UTF8String, detail.length ? ": " : "", detail.length ? detail.UTF8String : ""); }
}

// pointeruid's classes, with the ivars and methods MacPointer uses (their names as on the iPads; the types as MacPointer reads them).
@interface PUIDPointerShapeView : UIView {
@public
    UIView *_pointerView, *_axColorStroke, *_axCenterDot;
    id _pointerShape;
    __unsafe_unretained id _gone;   // (an unretained ivar that may point at an object already gone: never to be messaged)
}
@end
@implementation PUIDPointerShapeView
- (void)setPointerShape:(id)shape animated:(BOOL)animated completion:(id)completion { (void)shape; (void)animated; (void)completion; }
@end
@interface PUIDPointerRenderingRootViewController : UIViewController {
@public
    UIView *_pointerShapeView, *_pointerRootView;
    long long _visibilityState;
    CALayer *_specularLayer;
}
@end
@implementation PUIDPointerRenderingRootViewController
- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error { (void)state; (void)options; (void)collection; (void)error; return YES; }
- (void)hidePointer {}
@end
@interface PUIDPointerController : NSObject
@end
@implementation PUIDPointerController
- (void)_handleAccessibilityPointerSizePreferencesDidChange {}
@end
// Another layout of the same classes (an iPadOS that renamed things): for the missing parts.
@interface OldShapeView : UIView { id _shape; }
@end
@implementation OldShapeView
@end
@interface OldRootVC : UIViewController
@end
@implementation OldRootVC
@end

typedef struct { PUIDPointerShapeView *view; PUIDPointerRenderingRootViewController *vc; UIView *root; CAShapeLayer *ours; NSMutableArray *weHid; } Pointer;
static CAShapeLayer *Arrow(void) {
    CAShapeLayer *a = [CAShapeLayer layer];
    CGMutablePathRef p = CGPathCreateMutable(); CGPathMoveToPoint(p, NULL, 0, 0); CGPathAddLineToPoint(p, NULL, 0, 17); CGPathAddLineToPoint(p, NULL, 12, 12); CGPathCloseSubpath(p);
    a.path = p; CGPathRelease(p); a.fillColor = [UIColor blackColor].CGColor; a.strokeColor = [UIColor whiteColor].CGColor; a.lineWidth = 1.25;
    return a;
}
// A pointer as pointeruid builds it: the controller's root view holding the pointer view, which holds the round pointer, the accessibility ring (a
// shape layer inside its view) and dot, each kept in an ivar; the Mac pointer's arrow on the pointer view when `withOurs`.
static Pointer MakePointer(BOOL withOurs) {
    Pointer p = {0};
    p.vc = [PUIDPointerRenderingRootViewController new];
    p.root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    p.view = [[PUIDPointerShapeView alloc] initWithFrame:CGRectMake(100, 100, 19, 19)];
    [p.root addSubview:p.view];
    p.vc->_pointerRootView = p.root; p.vc->_pointerShapeView = p.view;
    UIView *round = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 19, 19)]; round.backgroundColor = [UIColor grayColor]; round.layer.cornerRadius = 9.5;
    UIView *ring = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 19, 19)]; CAShapeLayer *rl = Arrow(); rl.fillColor = nil; [ring.layer addSublayer:rl];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 3, 3)]; dot.backgroundColor = [UIColor whiteColor];
    for (UIView *v in @[round, ring, dot]) [p.view addSubview:v];
    p.view->_pointerView = round; p.view->_axColorStroke = ring; p.view->_axCenterDot = dot;
    p.weHid = [NSMutableArray array];
    if (withOurs) { p.ours = Arrow(); [p.view.layer addSublayer:p.ours]; }
    return p;
}
static unsigned Seen(Pointer p) { return MPAsideSeen(p.view, p.vc, p.root, p.ours, p.weHid); }
static NSString *Bits(unsigned s) { return [NSString stringWithFormat:@"seen %u", s]; }

// ---- the look's clock (1.8.8.2, after a device pass on iPadOS 17.5.1: with the other pointer hidden the Mac pointer never came back) ----
// An iPadOS 17.5.1 pointer as MacPointer's debug log showed it on a device, replayed: a test library's red layer on the pointer shown, hidden
// from 45 s to 90 s, shown again. Trace A: plain moves, two pointer updates in 109 s. Trace B: at a window's edge the text beam and the round
// pointer take turns (a beam update, the round pointer's 9 ms later, again 0.58 s on, every 1.93 s), and iPadOS keeps its round pointer hidden for
// a moment after each change back (the "round hidden" seen there). Trace C: the pointer left still (auto-hidden at 67 s), moved at 72 s, still
// again at 90 s. Played with the rule before this fix (as this test plays it: a look only a main-queue turn after an update, at most every 2 s counted from
// the last try, a try that is not on a plain pointer spent) and with the header's clock (MSBDMPAsideTimerWanted, MSBDMPAsideLookDelay,
// MSBDMPAsideCanLook, as MacPointer.x calls them: a 2 s timer while aside and in use, a request kept for its time, a look once the shape settled).
typedef struct { double t; int shape, hover, autoHidden; } PTUpdate;
static int PTTrace(char which, PTUpdate *u, int max) {
    int n = 0;
    #define PTU(T, S, H, A) do { if (n < max) u[n++] = (PTUpdate){ (T), (S), (H), (A) }; } while (0)
    PTU(0.0, 1, 0, 0); PTU(2.5, 1, 0, 0);
    if (which == 'B') for (double c = 5.0; c < 100.0; c += 1.934) { PTU(c, 4, 1, 0); PTU(c + 0.009, 1, 0, 0); PTU(c + 0.584, 4, 1, 0); PTU(c + 0.592, 1, 0, 0); }
    if (which == 'C') { PTU(67.0, 1, 0, 1); PTU(72.0, 1, 0, 0); PTU(90.0, 1, 0, 1); }
    if (which == 'R') { PTU(95.0, 3, 1, 0); PTU(95.5, 1, 0, 0); }   // (trace A, then the pointer over a button and off it: an update)
    #undef PTU
    return n;
}
typedef struct { double back, asideAgain; int looks; } PTResult;
static PTResult PTPlay(char which, int newRule) {
    PTUpdate u[256]; int n = PTTrace(which, u, 256);
    PTResult r = { -1, -1, 0 };
    unsigned verdict = MSBD_MP_V_ASIDE; int clean = 0;   // (the first look at the start saw the red layer: standing aside)
    int shape = 1, hover = 0, autoHidden = 0, k = 0;
    double shapeAt = -10, toRoundAt = -10, lastTry = 0.003, lastLooked = 0.003;
    int timerOn = newRule, queued = 0; double tick = 2.003, queuedAt = 0;
    for (long step = 0; step <= 100000; step++) {
        double t = step * 0.001;
        int updated = 0;
        while (k < n && u[k].t <= t + 1e-9) {
            if (u[k].shape != shape) { shapeAt = t; if (u[k].shape == 1) toRoundAt = t; }
            shape = u[k].shape; hover = u[k].hover; autoHidden = u[k].autoHidden; k++; updated = 1;
        }
        int plain = shape == 1 && !hover && !autoHidden;
        // (another library's pointer: its red layer; iPadOS's round pointer hidden for 0.3 s after a change back to it)
        unsigned seen = ((t < 45.0 || t >= 90.0) ? MSBD_MP_SEEN_LAYER : 0) | (t - toRoundAt < 0.3 ? MSBD_MP_SEEN_ROUND_HIDDEN : 0);
        int lookNow = 0;
        if (!newRule) {
            if (updated && !queued && t - lastTry >= (verdict == MSBD_MP_V_WAITING ? 0.25 : 2.0)) { queued = 1; queuedAt = t + 0.001; }
            if (queued && t >= queuedAt - 1e-9) { queued = 0; lastTry = t; lookNow = plain; }
        } else {
            if (updated) {
                if (verdict == MSBD_MP_V_ASIDE) { int want = MSBDMPAsideTimerWanted(verdict, autoHidden); if (want && !timerOn) tick = t + MSBD_MP_LOOK_EVERY; timerOn = want; }
                else if (!queued) { queued = 1; queuedAt = t + 0.001 + MSBDMPAsideLookDelay(verdict, t, lastLooked); }
            }
            double wait = -2;
            if (timerOn && t >= tick - 1e-9) {
                tick += MSBD_MP_LOOK_EVERY;
                if (!MSBDMPAsideTimerWanted(verdict, autoHidden)) timerOn = 0;
                else { wait = MSBDMPAsideCanLook(plain, t, shapeAt); if (wait > 0 && wait < MSBD_MP_LOOK_EVERY && !queued) { queued = 1; queuedAt = t + wait; } }
            } else if (queued && t >= queuedAt - 1e-9) {
                queued = 0; wait = MSBDMPAsideCanLook(plain, t, shapeAt);
                if (wait > 0) { queued = 1; queuedAt = t + wait; }
            }
            lookNow = wait < 0 && wait > -1.5;
        }
        if (!lookNow) continue;
        r.looks++; lastLooked = t;
        unsigned was = verdict;
        verdict = MSBDMPAsideNext(verdict, seen != 0, &clean);
        if (newRule && verdict != was) timerOn = MSBDMPAsideTimerWanted(verdict, autoHidden), tick = t + MSBD_MP_LOOK_EVERY;
        if (was == MSBD_MP_V_ASIDE && verdict == MSBD_MP_V_SHARED && r.back < 0) r.back = t;
        if (was == MSBD_MP_V_SHARED && verdict == MSBD_MP_V_ASIDE && t >= 90.0 && r.asideAgain < 0) r.asideAgain = t;
    }
    return r;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        (void)argc; (void)argv;
        printf("== the words (common/MacPointerStatus.h)\n");
        uint64_t w = MSBDMPPack(4242, MSBD_MP_V_ASIDE, MSBD_MP_SEEN_LAYER | MSBD_MP_SEEN_ROUND_HIDDEN, MSBD_MP_MISS_VISIBILITY | MSBD_MP_MISS_SHAPEVIEW, MSBD_MP_NOW_ASIDE);
        Check(MSBDMPPid(w) == 4242 && MSBDMPVerdict(w) == MSBD_MP_V_ASIDE && MSBDMPSeen(w) == (MSBD_MP_SEEN_LAYER | MSBD_MP_SEEN_ROUND_HIDDEN) && MSBDMPMissing(w) == (MSBD_MP_MISS_VISIBILITY | MSBD_MP_MISS_SHAPEVIEW) && MSBDMPNow(w) == MSBD_MP_NOW_ASIDE,
              @"the status word packs and unpacks every field", nil);
        w = MSBDMPPack(0xFFFFFFFFu, 0xF, 0xF, 0xFFF, 0xF);
        Check(MSBDMPPid(w) == 0xFFFFFFFFu && MSBDMPVerdict(w) == 0xF && MSBDMPSeen(w) == 0xF && MSBDMPMissing(w) == 0xFFF && MSBDMPNow(w) == 0xF && (w >> 56) == 0, @"  ... the fields never run into each other (all bits set: bits 56-63 stay clear)", nil);
        // the verdict after each look
        int clean = 0;
        Check(MSBDMPAsideNext(MSBD_MP_V_ALONE, 1, &clean) == MSBD_MP_V_ALONE && MSBDMPAsideNext(MSBD_MP_V_NONE, 1, &clean) == MSBD_MP_V_NONE, @"no other library (ALONE) or not looked yet: a look changes nothing", nil);
        Check(MSBDMPAsideNext(MSBD_MP_V_WAITING, 0, &clean) == MSBD_MP_V_SHARED, @"another library changes the pointer, the first look sees nothing of it: the Mac pointer draws (SHARED; 1.8.8.1.1 stood down)", nil);
        Check(MSBDMPAsideNext(MSBD_MP_V_WAITING, 1, &clean) == MSBD_MP_V_ASIDE, @"  ... the first look sees another pointer: standing aside", nil);
        Check(MSBDMPAsideNext(MSBD_MP_V_SHARED, 1, &clean) == MSBD_MP_V_ASIDE, @"drawing, then another pointer shows: standing aside at once", nil);
        clean = 0; unsigned v = MSBD_MP_V_ASIDE;
        v = MSBDMPAsideNext(v, 0, &clean); BOOL one = v == MSBD_MP_V_ASIDE;
        v = MSBDMPAsideNext(v, 0, &clean);
        Check(one && v == MSBD_MP_V_SHARED && clean == 0, @"standing aside: back to drawing only after two clean looks in a row", nil);
        clean = 0; v = MSBD_MP_V_ASIDE; v = MSBDMPAsideNext(v, 0, &clean); v = MSBDMPAsideNext(v, 1, &clean); v = MSBDMPAsideNext(v, 0, &clean);
        Check(v == MSBD_MP_V_ASIDE, @"  ... a look that sees it again starts the count over (no fight with a pointer that flickers)", nil);
        Check(MSBDMPVerdictDraws(MSBD_MP_V_ALONE) && MSBDMPVerdictDraws(MSBD_MP_V_SHARED) && !MSBDMPVerdictDraws(MSBD_MP_V_ASIDE) && !MSBDMPVerdictDraws(MSBD_MP_V_WAITING) && !MSBDMPVerdictDraws(MSBD_MP_V_NONE),
              @"the Mac pointer draws only ALONE or SHARED (waiting: the round pointer is left as it is)", nil);
        // the look's clock (1.8.8.2, after a device pass on iPadOS 17.5.1)
        Check(MSBDMPAsideTimerWanted(MSBD_MP_V_ASIDE, 0) && !MSBDMPAsideTimerWanted(MSBD_MP_V_ASIDE, 1) && !MSBDMPAsideTimerWanted(MSBD_MP_V_SHARED, 0) && !MSBDMPAsideTimerWanted(MSBD_MP_V_ALONE, 0)
              && !MSBDMPAsideTimerWanted(MSBD_MP_V_WAITING, 0) && !MSBDMPAsideTimerWanted(MSBD_MP_V_NONE, 0),
              @"the look's own 2 s timer: only standing aside with the pointer in use (at rest: none; drawing, waiting, no other library: none)", nil);
        Check(MSBDMPAsideLookDelay(MSBD_MP_V_WAITING, 100.0, -10.0) == 0.0 && fabs(MSBDMPAsideLookDelay(MSBD_MP_V_SHARED, 100.0, 99.5) - 1.5) < 1e-9 && MSBDMPAsideLookDelay(MSBD_MP_V_SHARED, 100.0, 97.0) == 0.0
              && fabs(MSBDMPAsideLookDelay(MSBD_MP_V_WAITING, 100.0, 99.9) - 0.15) < 1e-9,
              @"  ... after an update: at once while waiting; drawing beside other hooks, 2 s after the last look, a request inside that time kept for its end", nil);
        Check(MSBDMPAsideCanLook(0, 100.0, -10.0) == 0.0 && MSBDMPAsideCanLook(1, 100.0, 50.0) == -1.0 && fabs(MSBDMPAsideCanLook(1, 100.0, 99.8) - 0.3) < 1e-9,
              @"  ... a look looks only at a plain pointer whose shape has been left alone 0.5 s (else: wait for its update, or ask again once settled)", nil);
        for (int c = 0; c < 3; c++) {
            char w = "ABC"[c];
            PTResult o = PTPlay(w, 0), m = PTPlay(w, 1);
            NSString *what = [NSString stringWithFormat:@"17.5.1's trace %c (%@), the red layer hidden at 45 s: the rule before never draws again by 90 s; the clock draws again by %d s", w,
                              c == 0 ? @"plain moves, two updates in 109 s" : c == 1 ? @"the text beam and the round pointer taking turns at a window's edge" : @"left still at 67 s, moved at 72 s",
                              c == 1 ? 55 : 51];
            Check((o.back < 0 || o.back >= 90.0) && m.back >= 45.0 && m.back < (c == 1 ? 55.0 : 51.0), what,
                  [NSString stringWithFormat:@"the rule before: back at %.3f (%d looks); clock: back at %.3f (%d looks)", o.back, o.looks, m.back, m.looks]);
        }
        PTResult rr = PTPlay('R', 1);
        Check(rr.back >= 45.0 && rr.back < 51.0 && rr.asideAgain >= 95.0 && rr.asideAgain < 97.0,
              @"  ... drawing again, the other pointer shown again: aside at the pointer's next update (no timer while drawing)", [NSString stringWithFormat:@"back %.3f, aside again %.3f", rr.back, rr.asideAgain]);
        // SpringBoard's word on the pointer process
        Check(MSBDMPProcessWord(0, 77, 1, 77, 60, 77) == 0, @"process word: no trackpad or mouse: 0", nil);
        Check(MSBDMPProcessWord(1, 77, 1, 0, 0, 0) == 77, @"  ... MacPointer's pid is the pointeruid that runs: that pid", nil);
        Check(MSBDMPProcessWord(1, 0, 0, 88, 6, 0) == 88 && MSBDMPProcessWord(1, 77, 0, 88, 30, 77) == 88, @"  ... a pointeruid that has run 5 s or more without MacPointer's word: its pid", nil);
        Check(MSBDMPProcessWord(1, 0, 0, 88, 2, 0) == 0 && MSBDMPProcessWord(1, 77, 0, 88, 2, 77) == 77, @"  ... a pointeruid started under 5 s ago: the word as it was (MacPointer says its pid as it loads)", nil);
        Check(MSBDMPProcessWord(1, 77, 0, 0, 0, 77) == 0, @"  ... no pointeruid found: 0", nil);
        // Settings > Pointer's note
        uint64_t aside = MSBDMPPack(500, MSBD_MP_V_ASIDE, MSBD_MP_SEEN_LAYER, 0, MSBD_MP_NOW_ASIDE);
        Check(MSBDMPNoteFor(0, aside, 500) == MSBD_MP_NOTE_NONE && MSBDMPNoteFor(0, 0, 900) == MSBD_MP_NOTE_NONE, @"note: Pointer Style iPadOS: nothing, whatever the words", nil);
        Check(MSBDMPNoteFor(1, aside, 500) == MSBD_MP_NOTE_ASIDE && MSBDMPNoteFor(1, aside, 0) == MSBD_MP_NOTE_ASIDE, @"  ... standing aside: said", nil);
        Check(MSBDMPNoteFor(1, aside, 501) == MSBD_MP_NOTE_NOT_RUNNING && MSBDMPNoteFor(1, 0, 501) == MSBD_MP_NOTE_NOT_RUNNING, @"  ... the pointeruid that runs is not the one MacPointer said (or none said): not running", nil);
        Check(MSBDMPNoteFor(1, 0, 0) == MSBD_MP_NOTE_NONE, @"  ... nothing said and no pointeruid seen: nothing (never a guess)", nil);
        Check(MSBDMPNoteFor(1, MSBDMPPack(500, MSBD_MP_V_LOADFAIL, 0, 0, 0), 500) == MSBD_MP_NOTE_LOAD_FAILED && MSBDMPNoteFor(1, MSBDMPPack(500, MSBD_MP_V_HELD, 0, 0, 0), 500) == MSBD_MP_NOTE_NONE,
              @"  ... our loader there: its file did not open: said; held back (rows only): nothing", nil);
        Check(MSBDMPNoteFor(1, MSBDMPPack(500, MSBD_MP_V_ALONE, 0, MSBD_MP_MISS_SHAPEVIEW, MSBD_MP_NOW_SHOWN), 500) == MSBD_MP_NOTE_CANNOT_DRAW && MSBDMPNoteFor(1, MSBDMPPack(500, MSBD_MP_V_ALONE, 0, MSBD_MP_MISS_ROUNDVIEW, 1), 500) == MSBD_MP_NOTE_CANNOT_DRAW,
              @"  ... the pointer view or its round pointer not found on this iPadOS: said", nil);
        BOOL quiet = YES;
        for (unsigned m = 1; m < 0x800; m <<= 1) if (!(m & MSBD_MP_MISS_CANNOT_DRAW) && MSBDMPNoteFor(1, MSBDMPPack(500, MSBD_MP_V_ALONE, 0, m, 1), 500) != MSBD_MP_NOTE_NONE) quiet = NO;
        for (unsigned vv = 0; vv < 7; vv++) if (vv != MSBD_MP_V_ASIDE && vv != MSBD_MP_V_LOADFAIL && MSBDMPNoteFor(1, MSBDMPPack(500, vv, 0, 0, 1), 500) != MSBD_MP_NOTE_NONE) quiet = NO;
        Check(quiet, @"  ... drawing, waiting, a part only Report a Problem needs: nothing on the page", nil);
        NSArray *texts = @[MSBDMPNoteText(MSBD_MP_NOTE_ASIDE, @"17.7.11"), MSBDMPNoteText(MSBD_MP_NOTE_NOT_RUNNING, @"17.7.11"), MSBDMPNoteText(MSBD_MP_NOTE_LOAD_FAILED, @"17.7.11"), MSBDMPNoteText(MSBD_MP_NOTE_CANNOT_DRAW, @"17.7.11")];
        BOOL plain = MSBDMPNoteText(MSBD_MP_NOTE_NONE, @"17.7.11") == nil;
        for (NSString *t in texts) if ([t rangeOfString:@"--"].location != NSNotFound || [t rangeOfString:@"\u2014"].location != NSNotFound || [t rangeOfString:@"\u2013"].location != NSNotFound
                                     || [t rangeOfString:@"dylib"].location != NSNotFound || [t rangeOfString:@"/"].location != NSNotFound || ![t hasSuffix:@"."] || t.length > 330) plain = NO;
        Check(plain, @"  ... every note: plain words, no dash, no library or path named, one short paragraph", [texts componentsJoinedByString:@" | "]);
        Check([texts[0] containsString:@"another tweak draws its own pointer"] && [texts[0] containsString:@"set Pointer Style to iPadOS"] && [texts[0] containsString:@"turn the other pointer off"],
              @"  ... standing aside: why (another tweak's pointer, two at once) and both ways out (the other pointer off, or Pointer Style iPadOS)", texts[0]);
        Check([texts[1] containsString:@"pointeruid"] && [texts[1] containsString:@"Report a Problem"] && [texts[2] containsString:@"Report a Problem"] && [texts[3] containsString:@"iPadOS 17.7.11"] && [texts[3] containsString:@"Report a Problem"],
              @"  ... not running: where and what to do; could not start, does not fit iPadOS 17.7.11: Report a Problem", nil);
        Check([texts[1] containsString:@"turn them back on, then tap Restart Pointer"] && ![texts[1] containsString:@"reinstall"], @"  ... not running: turn tweaks back on for pointeruid and tap Restart Pointer (no reinstall)", texts[1]);
        // Restart Pointer: offered with the not-running and could-not-start notes only; the root helper's rules
        BOOL offered = YES;
        for (int n = MSBD_MP_NOTE_NONE; n <= MSBD_MP_NOTE_CANNOT_DRAW; n++) if (MSBDMPNoteHasRestart(n) != (n == MSBD_MP_NOTE_NOT_RUNNING || n == MSBD_MP_NOTE_LOAD_FAILED)) offered = NO;
        Check(offered, @"Restart Pointer: offered with the not-running and could-not-start notes, with no other (standing aside, does not fit, nothing)", nil);
        Check(MSBDMPRestartTarget("pointeruid", "/usr/libexec/pointeruid") && MSBDMPRestartTarget("pointeruid", "/System/Library/CoreServices/pointeruid"),
              @"  ... the root helper stops the system's pointeruid", nil);
        Check(!MSBDMPRestartTarget("pointeruid", "/var/jb/usr/libexec/pointeruid") && !MSBDMPRestartTarget("pointeruid", "/private/preboot/ABC/jb-1/procursus/usr/bin/pointeruid")
              && !MSBDMPRestartTarget("pointeruid", "") && !MSBDMPRestartTarget("pointeruid", NULL) && !MSBDMPRestartTarget("pointeruid", "pointeruid")
              && !MSBDMPRestartTarget("pointeruid", "/usr/libexec/notpointeruid") && !MSBDMPRestartTarget("pointerui", "/usr/libexec/pointeruid") && !MSBDMPRestartTarget(NULL, "/usr/libexec/pointeruid"),
              @"  ... never a jailbreak's file, a process it cannot read the path of, or another name", nil);
        double last = 0;
        BOOL r1 = MSBDMPRestartNow(1000.0, &last), r2 = MSBDMPRestartNow(1003.0, &last), r3 = MSBDMPRestartNow(1005.5, &last), r4 = MSBDMPRestartNow(900.0, &last);
        Check(r1 && !r2 && r3 && r4, @"  ... at most one request every 5 s (a repeated or foreign request restarts the pointer once at most); a clock set back does not block it", nil);
        // (1.8.8.2 review) where iPadOS has its pointer process (ps on 18.5), and when the helper takes a request at all: only while the words say what
        // the row is offered for (the request carries no sender: anyone can post it)
        Check(MSBDMPRestartTarget("pointeruid", "/System/Library/PrivateFrameworks/PointerUIServices.framework/Support/pointeruid"), @"  ... the system's pointeruid where iPadOS keeps it (PointerUIServices.framework/Support)", nil);
        uint64_t well = MSBDMPPack(500, MSBD_MP_V_ALONE, 0, 0, MSBD_MP_NOW_SHOWN), failed = MSBDMPPack(500, MSBD_MP_V_LOADFAIL, 0, 0, 0);
        Check(MSBDMPRestartWanted(well, 501) && MSBDMPRestartWanted(0, 501) && MSBDMPRestartWanted(failed, 500) && MSBDMPRestartWanted(failed, 0),
              @"  ... a request is taken while MacPointer is not running in the pointer process that runs, or could not start there (the two notes with the row)", nil);
        Check(!MSBDMPRestartWanted(well, 500) && !MSBDMPRestartWanted(well, 0) && !MSBDMPRestartWanted(aside, 500) && !MSBDMPRestartWanted(MSBDMPPack(500, MSBD_MP_V_ALONE, 0, MSBD_MP_MISS_SHAPEVIEW, 1), 500)
              && !MSBDMPRestartWanted(MSBDMPPack(500, MSBD_MP_V_HELD, 0, 0, 0), 500) && !MSBDMPRestartWanted(0, 0),
              @"  ... and left while all is well, standing aside, does not fit, held back or nothing said (a request posted by anyone else: no restart)", nil);
        // Report a Problem's words
        NSString *r = MSBDMPReportWords(1, aside, 500, @"OtherPointer.dylib");
        Check([r hasPrefix:@"standing aside (another pointer: OtherPointer.dylib; seen: a layer)"] && [r hasSuffix:@"; now: standing aside"], @"report: standing aside, the other library's file name and what was seen", r);
        Check([MSBDMPReportWords(1, MSBDMPPack(500, MSBD_MP_V_SHARED, 0, 0, 1), 500, @"Harmless.dylib") isEqualToString:@"drawing (other hooks on the pointer draw nothing: Harmless.dylib)"]
              && [MSBDMPReportWords(1, MSBDMPPack(500, MSBD_MP_V_ALONE, 0, 0, 1), 500, nil) isEqualToString:@"drawing"], @"  ... drawing, with and without other hooks", nil);
        Check([MSBDMPReportWords(1, aside, 501, nil) isEqualToString:@"not running in pointeruid; now: standing aside"] && [MSBDMPReportWords(0, aside, 500, nil) isEqualToString:@"Pointer Style iPadOS"]
              && [MSBDMPReportWords(1, 0, 0, nil) isEqualToString:@"no word from pointeruid (not seen running)"], @"  ... not running, Pointer Style iPadOS, nothing said", nil);
        r = MSBDMPReportWords(1, MSBDMPPack(500, MSBD_MP_V_ALONE, 0, MSBD_MP_MISS_VISIBILITY | MSBD_MP_MISS_HIDE, MSBD_MP_NOW_SYSTEM_HID), 500, nil);
        Check([r isEqualToString:@"drawing; missing: hidePointer visibility; now: hidden by iPadOS"], @"  ... the parts not found and why the arrow is not shown now", r);
        Check(MSBDMPCleanName("Other.dylib", 11) && [MSBDMPCleanName("Other.dylib", 11) isEqualToString:@"Other.dylib"] && !MSBDMPCleanName("/var/x", 6) && !MSBDMPCleanName("a b", 3) && !MSBDMPCleanName("", 0)
              && [MSBDMPCleanName("abcdefghijklmnopqrstuvwxyz0123456789", 36) length] == 31, @"  ... the file name only as letters, digits and . _ + - (never a path), at most 31", nil);

        printf("== the other library\n");
        const char *lib = getenv("OTHER_LIB");
        void *h = lib ? dlopen(lib, RTLD_NOW) : NULL;
        Class otherView = NSClassFromString(@"PointerOtherArrowView"), otherLayer = NSClassFromString(@"PointerOtherLayer");
        IMP hook = h ? (IMP)dlsym(h, "PointerOtherHook") : NULL;
        CAShapeLayer *(*shapeLayer)(void) = h ? (CAShapeLayer *(*)(void))dlsym(h, "PointerOtherShapeLayer") : NULL;
        Check(h && otherView && otherLayer && hook && shapeLayer, @"the other library loads from its \"/var/jb/\" path", lib ? @(lib) : @"OTHER_LIB not set");
        if (!h || !otherView || !otherLayer || !hook || !shapeLayer) { printf("test-pointeraside: %d passed, %d FAILED\n", passes, fails + 1); return 1; }
        Check(MPAsideClassIsOther(otherView) && MPAsideClassIsOther(otherLayer) && !MPAsideClassIsOther([PUIDPointerShapeView class]) && !MPAsideClassIsOther([UIView class]) && !MPAsideClassIsOther([CAShapeLayer class]),
              @"its classes are another library's; pointeruid's (here: this test's own image), UIKit's and Core Animation's are not", nil);

        printf("== the hooks (read once a run)\n");
        char path[512];
        unsigned hooks = MPAsideOtherHooks(path, sizeof path, nil);
        Check(hooks == 0 && path[0] == 0, @"no other library on the pointer's classes: none (ALONE: never looked at again)", [NSString stringWithFormat:@"%u %s", hooks, path]);
#ifdef OLD_RULE_INC
        Check(!MPOtherPointerTweak(), @"1.8.8.1.1's own rule, no other library: the Mac pointer draws", nil);
#endif
        method_setImplementation(class_getInstanceMethod([PUIDPointerController class], @selector(_handleAccessibilityPointerSizePreferencesDidChange)), hook);
        hooks = MPAsideOtherHooks(path, sizeof path, nil);
        Check(hooks == 1 && strstr(path, "/var/jb/") && strstr(path, "PointerOther"), @"a hook of the other library on PUIDPointerController: found, with its library's path", [NSString stringWithFormat:@"%u %s", hooks, path]);
#ifdef OLD_RULE_INC
        Check(MPOtherPointerTweak(), @"  ... 1.8.8.1.1's own rule on it: the Mac pointer stands down for the run, though the hook draws nothing (GitHub #17's round pointer)", nil);
#endif
        class_addMethod([PUIDPointerShapeView class], NSSelectorFromString(@"otherAdded"), hook, "v@:");
        __block unsigned told = 0; __block BOOL toldRight = YES;
        hooks = MPAsideOtherHooks(path, sizeof path, ^(const char *cls, SEL sel, const char *p) { told++; if (!strstr(p, "PointerOther") || (strcmp(cls, "PUIDPointerShapeView") && strcmp(cls, "PUIDPointerController"))) toldRight = NO; });
        Check(hooks == 2 && told == 2 && toldRight, @"  ... a method it added to the pointer view: found too; each one told with its class and library (the debug log)", nil);

        printf("== one look at the pointer (MPAsideSeen)\n");
        Pointer p = MakePointer(YES);
        Check(Seen(p) == 0, @"pointeruid's own pointer (round pointer, ring, dot: held in its ivars) and the Mac pointer's own arrow on it: nothing seen", Bits(Seen(p)));
        Check(MSBDMPAsideNext(MSBD_MP_V_WAITING, Seen(p) != 0, &clean) == MSBD_MP_V_SHARED, @"  ... so with that harmless hook the Mac pointer draws (1.8.8.1.1: stood down for the run)", nil);
        CAShapeLayer *their = shapeLayer(); [p.view.layer addSublayer:their];
        Check(Seen(p) == MSBD_MP_SEEN_LAYER, @"the other library's shape layer added on the pointer view (the usual other arrow, a system class): seen", Bits(Seen(p)));
        their.hidden = YES; BOOL hid = Seen(p) == 0; their.hidden = NO; their.opacity = 0; BOOL clear = Seen(p) == 0; their.opacity = 1;
        CGPathRef keep = CGPathRetain(their.path); their.path = NULL; BOOL nopath = Seen(p) == 0; their.path = keep; CGPathRelease(keep);
        their.fillColor = nil; BOOL nopaint = Seen(p) == 0; their.fillColor = [UIColor blackColor].CGColor;
        Check(hid && clear && nopath && nopaint && Seen(p) == MSBD_MP_SEEN_LAYER, @"  ... hidden, see-through, without a path or without paint: not seen (it shows nothing); shown again: seen", nil);
        [their removeFromSuperlayer];
        UIImageView *img = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 19, 19)];
        img.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)] imageWithActions:^(UIGraphicsImageRendererContext *c) { [[UIColor redColor] setFill]; UIRectFill(CGRectMake(0, 0, 4, 4)); }];
        [p.view addSubview:img];
        Check(Seen(p) == MSBD_MP_SEEN_LAYER, @"an image view with a cursor image added on the pointer view (a system class, held by no ivar of pointeruid's): seen", Bits(Seen(p)));
        img.image = nil; Check(Seen(p) == 0, @"  ... with no image: not seen", Bits(Seen(p))); [img removeFromSuperview];
        CALayer *spec = [CALayer layer]; spec.backgroundColor = [UIColor whiteColor].CGColor; [p.view.layer addSublayer:spec]; p.vc->_specularLayer = spec;
        Check(Seen(p) == 0, @"a layer on the pointer view that pointeruid's controller holds in an ivar (its own effect): not seen", Bits(Seen(p)));
        p.vc->_specularLayer = nil; Check(Seen(p) == MSBD_MP_SEEN_LAYER, @"  ... the same layer held by nobody: seen", Bits(Seen(p))); [spec removeFromSuperlayer];
        UIView *ov = [[otherView alloc] initWithFrame:CGRectMake(300, 300, 20, 20)]; ov.backgroundColor = [UIColor blackColor]; [p.root addSubview:ov];
        Check(Seen(p) == MSBD_MP_SEEN_CLASS, @"a view of the other library's own class in the pointer's root view, showing: seen", Bits(Seen(p)));
        ov.hidden = YES; Check(Seen(p) == 0, @"  ... hidden: not seen", Bits(Seen(p))); [ov removeFromSuperview];
        CALayer *ol = [otherLayer layer]; [p.root.layer addSublayer:ol];
        Check(Seen(p) == 0, @"a layer of the other library's class that shows nothing (a helper of a harmless tweak): not seen", Bits(Seen(p)));
        UIImage *dotImage = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2, 2)] imageWithActions:^(UIGraphicsImageRendererContext *c) { UIRectFill(CGRectMake(0, 0, 2, 2)); }];
        ol.contents = (__bridge id)dotImage.CGImage;
        Check(Seen(p) == MSBD_MP_SEEN_CLASS, @"  ... the same layer with an image: seen", Bits(Seen(p))); [ol removeFromSuperlayer];
        p.view->_pointerView.hidden = YES;
        Check(Seen(p) == MSBD_MP_SEEN_ROUND_HIDDEN, @"iPadOS's round pointer hidden by someone else: seen", Bits(Seen(p)));
        p.view->_pointerView.hidden = NO; p.view->_pointerView.layer.hidden = YES; [p.weHid addObject:p.view->_pointerView];
        Check(Seen(p) == 0, @"  ... hidden by the Mac pointer itself (the views it hid): not seen", Bits(Seen(p)));
        [p.weHid removeAllObjects]; Check(Seen(p) == MSBD_MP_SEEN_ROUND_HIDDEN, @"  ... the same hidden layer not in the Mac pointer's list: seen", Bits(Seen(p))); p.view->_pointerView.layer.hidden = NO;
        @autoreleasepool { NSObject *o = [NSObject new]; p.view->_gone = o; }   // (now points at an object that is gone)
        Check(Seen(p) == 0, @"an unretained ivar pointing at an object already gone: read by address only, nothing messaged (no crash), nothing seen", Bits(Seen(p)));
        p.view->_gone = nil;
        Pointer bare = MakePointer(NO);
        Check(Seen(bare) == 0 && MPAsideSeen(bare.view, nil, nil, nil, nil) == 0 && MPAsideSeen(nil, nil, nil, nil, nil) == 0, @"no Mac pointer arrow, no controller or root, no view: nothing seen", nil);
        CAShapeLayer *their2 = shapeLayer(); [bare.view.layer addSublayer:their2];
        Check(MPAsideSeen(bare.view, nil, nil, nil, nil) == MSBD_MP_SEEN_LAYER, @"  ... the other shape layer with no controller known: still seen (the pointer view's own ivars)", nil);
        UIView *deep = bare.root; for (int i = 0; i < 600; i++) { UIView *d = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)]; [deep addSubview:d]; deep = d; }
        UIView *far = [[otherView alloc] initWithFrame:CGRectMake(0, 0, 5, 5)]; far.backgroundColor = [UIColor blackColor]; [deep addSubview:far];
        CFTimeInterval t0 = CACurrentMediaTime(); unsigned s = MPAsideSeen(bare.view, bare.vc, bare.root, nil, nil); double ms = (CACurrentMediaTime() - t0) * 1000.0;
        Check(!(s & MSBD_MP_SEEN_CLASS) && ms < 50.0, @"a tree 600 views deep: the look stops at its depth and layer budget (a bounded look on pointeruid's main thread)", [NSString stringWithFormat:@"seen %u, %.2f ms", s, ms]);

        printf("== the parts of iPadOS's pointer (MPAsideMissingIn)\n");
        Check(MPAsideMissing() == 0 && MPAsideMissingIn([PUIDPointerShapeView class], [PUIDPointerRenderingRootViewController class], [PUIDPointerController class]) == 0, @"every part found in the classes as the iPads have them: nothing missing", [NSString stringWithFormat:@"0x%x", MPAsideMissing()]);
        unsigned m = MPAsideMissingIn([OldShapeView class], [OldRootVC class], [PUIDPointerController class]);
        Check(m == (MSBD_MP_MISS_SETSHAPE | MSBD_MP_MISS_ROUNDVIEW | MSBD_MP_MISS_SHAPE | MSBD_MP_MISS_SETSTATE | MSBD_MP_MISS_HIDE | MSBD_MP_MISS_MAINVIEW | MSBD_MP_MISS_VISIBILITY | MSBD_MP_MISS_ROOTVIEW),
              @"classes without those ivars and methods: each part said missing", [NSString stringWithFormat:@"0x%x", m]);
        Check((MPAsideMissingIn(nil, nil, nil) & 0x7FF) == 0x7FF && (MPAsideMissingIn(nil, [PUIDPointerRenderingRootViewController class], [PUIDPointerController class]) & MSBD_MP_MISS_CANNOT_DRAW) == MSBD_MP_MISS_CANNOT_DRAW,
              @"no pointer classes at all: everything missing, the Mac pointer cannot draw", nil);
        printf("test-pointeraside: %d passed, %d failed\n", passes, fails);
        return fails ? 1 : 0;
    }
}
