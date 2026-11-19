// test-a5maskcommit.m -- see test-a5maskcommit.sh. Aerial 5's corner mask on a window's app holder is committed at the holder's size (1.8.7.9:
// KT's M1 recording, 18 Nov -- a Finder open or close over a Fill window, and the window behind drew its app cut 52 x 32 pt along the right and
// bottom edges for one frame, our title strip's grey showing; KT's report of a window behind that briefly shrinks as another is minimized or
// closed). The real code, cut out of statusbar/StatusBar.x: DMA5SyncHostMaskFor / DMA5SyncHostMask (/ DMA5SyncHostMaskBy), DMStageInnerView,
// DMStagePutBack, DMEnforceStageFrame, DMA5AnswerFitPass, DMA5HoldEntranceFrame, DMA5MaskStale, DMA5MasksSync, DMA5MasksAtCommit and
// DMA5CatchNewStages (its two calls), with A5FitPass.h; in a DEBUG build the [a5mask] trace too. Stand-ins:
//  - Aerial's stage (a UIView) with its 6 pt side margins and an app holder that autoresizes with it (13 pt top, 12 pt bottom: the M1's "holder
//    margins 13/6/12/6"), a scene layer host inside it so DMStageInnerView finds it; Aerial 5's fit-to-screen pass = MSBDA5FitOf on the stage;
//  - the pass before a commit (DMA5CatchNewStagesPass) in the order that matters, as built: the paused frame watcher's pass first
//    (DMA5WakeFrameWatcher -> frameBody -> DMA5SyncHostMask on every window), then the entrance holds, then each older window's fit-pass answer;
//    the watcher's tick (frameBody) on its own;
//  - the windows in a UIWindow whose layer is attached to +[CAContext localContext], so a commit really lays out and runs its phases; a
//    post-commit handler reads what the commit carried (the holder's and the mask's model sizes, and whether the mask has a bounds animation).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "A5FitPass.h"

// ---- what the cut code needs ---------------------------------------------------------------------------------------------------------------
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL gKill __attribute__((unused)), gTrace __attribute__((unused));   // (/tmp/msb-a5-maskold, /tmp/msb-a5-masktrace)
#define DMTestFlag(path) ((gKill && !strcmp((path), "/tmp/msb-a5-maskold")) || (gTrace && !strcmp((path), "/tmp/msb-a5-masktrace")))
static BOOL gGeom = YES;   // (Aerial 5.x our engine, themed)
static BOOL DMA5MacGeometry(void) { return gGeom; }
static CGSize gScreen = {1194, 834};
static CGSize TScreenSize(void) { return gScreen; }
static const CGFloat kMilkyWayCorner = 12.0;
static const void *kStageIntentKey = &kStageIntentKey, *kStageEnteringKey = &kStageEnteringKey, *kStageGestureKey = &kStageGestureKey;
static const void *kStageIntentSizeKey = &kStageIntentSizeKey, *kStageClosingKey = &kStageClosingKey, *kA5ChipHiddenKey = &kA5ChipHiddenKey;
static const void *kTMinimizedKey = &kTMinimizedKey;
static BOOL DMStageMinimized(UIView *stage) { return [objc_getAssociatedObject(stage, kTMinimizedKey) boolValue]; }
static NSString *DMStageBundle(UIView *stage) { return stage.accessibilityIdentifier ?: @"app"; }
static CGFloat DMAutoHideShiftOf(UIView *stage) { return 0; }
static void DMAutoHideNoteFrame(UIView *stage) {}
static CGFloat DMA5StageShift(void) { return 11.0; }   // (24 - Aerial's 13 pt top inset)
static BOOL DMA5ChipFlag(UIView *stage) { return NO; }
static BOOL DMAerial5GestureLive(UIView *stage) { return NO; }
static void DMAerial5SyncState(UIView *stage, CGRect want) {}
static BOOL gStageFrameBypass = NO, gDMScreenOff __attribute__((unused)) = NO;
static NSHashTable<UIView *> *gA5StageCache;
static BOOL gWatcherPaused = YES;   // (the frame watcher idle-paused: its pass runs before the commit)
@interface NSObject (TCATransaction)
+ (void)addCommitHandler:(void (^)(void))block forPhase:(int)phase;
@end
#include "one-mask.inc"
#include "one-putback.inc"
#include "one-hold.inc"
#include "one-fit.inc"
static void DMA5WakeFrameWatcher(void) {   // (as built, the part that matters: while paused, the watcher's pass now -- frameBody: every window's mask)
    if (!gWatcherPaused) return;
#if DEBUG
    const char *by = gA5MaskBy; gA5MaskBy = "the paused watcher's pass before the commit";
#endif
    for (UIView *st in gA5StageCache.allObjects) DMA5SyncHostMask(st);
#if DEBUG
    gA5MaskBy = by;
#endif
}
static void WatcherTick(void) { for (UIView *st in gA5StageCache.allObjects) DMA5SyncHostMask(st); }   // (the display link's frameBody, mask part)
static void DMA5CatchNewStagesPass(void) {   // (the pass before a commit, in the order that matters)
    DMA5WakeFrameWatcher();
    if (gA5HeldStages) { for (UIView *st in gA5HeldStages.allObjects) DMA5HoldEntranceFrame(st); if (!gA5HeldStages.allObjects.count) gA5HeldStages = nil; }
    CFTimeInterval now = CACurrentMediaTime();
    for (UIView *st in gA5StageCache.allObjects) if (![gA5HeldStages containsObject:st]) DMA5AnswerFitPass(st, now);
}
#include "one-commit.inc"

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the stand-ins ---------------------------------------------------------------------------------------------------------------------------
@interface TSceneLayerHost : UIView
@end
@implementation TSceneLayerHost
@end
@interface TStage : UIView   // (Aerial's stage: its app holder autoresizes; relayout: Aerial lays the holder out in the stage's own layout pass)
@property (nonatomic, strong) UIView *holder;
@property (nonatomic) CGFloat relayout;
@end
@implementation TStage
- (void)layoutSubviews { [super layoutSubviews]; if (self.relayout) self.holder.frame = CGRectMake(6, 13, self.bounds.size.width - 12 - self.relayout, self.bounds.size.height - 25); }
@end
static UIWindow *gWindow;
static TStage *MakeStage(CGRect f, NSString *name) {
    TStage *st = [[TStage alloc] initWithFrame:f];
    st.accessibilityIdentifier = name;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(6, 13, f.size.width - 12, f.size.height - 25)];
    h.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [h addSubview:[[TSceneLayerHost alloc] initWithFrame:h.bounds]];
    [st addSubview:h]; st.holder = h;
    [gWindow addSubview:st];
    objc_setAssociatedObject(st, kStageIntentKey, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (its place: DMSetStageIntent)
    if (!gA5StageCache) gA5StageCache = [NSHashTable weakObjectsHashTable];
    [gA5StageCache addObject:st];
    return st;
}
static void Reset(CGSize screen) {
    for (UIView *v in [gWindow.subviews copy]) [v removeFromSuperview];
    [gA5StageCache removeAllObjects]; gA5HeldStages = nil;
    gScreen = screen; gWindow.frame = CGRectMake(0, 0, screen.width, screen.height);
    gWatcherPaused = YES; gGeom = YES; gKill = NO; gTrace = NO; [gLog removeAllObjects];
}
static CALayer *MaskOf(TStage *st) { return objc_getAssociatedObject(st.holder, kA5MaskKey); }
// What a commit carried, read after it (a post-commit handler): the holder's and the mask's sizes, and whether the mask got a bounds animation.
typedef struct { CGSize holder, mask; BOOL hasMask, maskAnimated; double holderAnim, maskAnim; } TCommitted;
static int gPhase1Adds;
static void (*gOrigAdd)(id, SEL, id, int);
static void TCountAdd(id cls, SEL sel, id block, int phase) { if (phase == 1) gPhase1Adds++; gOrigAdd(cls, sel, block, phase); }
static BOOL (*gOrigResponds)(id, SEL, SEL);
static BOOL TNoHandlers(id cls, SEL sel, SEL asked) { return asked == NSSelectorFromString(@"addCommitHandler:forPhase:") ? NO : gOrigResponds(cls, sel, asked); }
static double AnimDur(CALayer *l) {
    for (NSString *k in l.animationKeys) { CAAnimation *a = [l animationForKey:k]; NSString *p = [a isKindOfClass:[CAPropertyAnimation class]] ? ((CAPropertyAnimation *)a).keyPath : nil; if ([p hasPrefix:@"bounds"]) return a.duration; }
    return 0;
}
// One run-loop turn: what happens in it (Aerial's pass, a move, a tick...), then our observer before the commit (DMA5CatchNewStages) unless
// skipped, then the commit; returns what the commit carried for `st`.
static TCommitted Turn(TStage *st, BOOL observer, void (^during)(void)) {
    __block TCommitted c = {0};
    [CATransaction begin];
    if (during) during();
    if (observer) DMA5CatchNewStages();
    [CATransaction addCommitHandler:^{
        CALayer *m = MaskOf(st);
        c.holder = st.holder.layer.bounds.size; c.hasMask = m != nil && st.holder.layer.mask == m; c.mask = m.bounds.size;
        c.holderAnim = AnimDur(st.holder.layer); c.maskAnim = AnimDur(m); c.maskAnimated = c.maskAnim > 0;
    } forPhase:2];
    [CATransaction commit]; [CATransaction flush];
    return c;
}
static NSString *Band(TCommitted c) {
    if (!c.hasMask) return @"no mask of ours";
    double dw = c.holder.width - c.mask.width, dh = c.holder.height - c.mask.height;
    if (fabs(dw) <= 0.5 && fabs(dh) <= 0.5) return [NSString stringWithFormat:@"holder %.1f x %.1f, mask the same", c.holder.width, c.holder.height];
    return [NSString stringWithFormat:@"holder %.1f x %.1f, mask %.1f x %.1f (band %.1f x %.1f pt)", c.holder.width, c.holder.height, c.mask.width, c.mask.height, dw, dh];
}
static BOOL NoBand(TCommitted c) { return c.hasMask && fabs(c.holder.width - c.mask.width) <= 0.5 && fabs(c.holder.height - c.mask.height) <= 0.5; }
static void Settle(TStage *st) { Turn(st, YES, nil); Turn(st, YES, ^{ WatcherTick(); }); }   // (the mask made and in step, as at rest)
static void AerialPass(TStage *st) { st.frame = MSBDA5FitOf(st.frame, gScreen); }   // (its fit-to-screen pass: the holder resizes with the stage at once)

int main(int argc, char **argv) {
    @autoreleasepool {
        Method am = class_getClassMethod([CATransaction class], @selector(addCommitHandler:forPhase:));
        if (!am) { printf("FAIL  no +[CATransaction addCommitHandler:forPhase:] on this Mac\n"); return 1; }
        gOrigAdd = (void (*)(id, SEL, id, int))method_setImplementation(am, (IMP)TCountAdd);
        gWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1194, 834)];
        id ctx = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"CAContext"), NSSelectorFromString(@"localContext"));
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setLayer:"), gWindow.layer);
        const char *only = argc > 1 ? argv[1] : NULL;
#define CASE(name) if ((!only && strcmp(name, "T15")) || (only && !strcmp(only, name)))
        const CGRect kFillM1 = {{-6, 30}, {1206, 736.4}};

        CASE("T1") {   // KT's band: a Fill window on the M1, the watcher idle, Aerial's pass (a Finder open or close), our observer, the commit
            Reset(CGSizeMake(1194, 834));
            TStage *st = MakeStage(kFillM1, @"T1"); Settle(st);
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); });
            Check(NoBand(c), [NSString stringWithFormat:@"T1 M1 Fill, watcher idle, Aerial's fit pass put back: %@", Band(c)]);
            Check(CGRectEqualToRect(st.frame, kFillM1), @"T1 ... the window put back at its place");
        }
        CASE("T2") {   // the iPad 2's shape
            Reset(CGSizeMake(768, 1024));
            CGRect fill = CGRectMake(-6, 30, 780, 919);
            TStage *st = MakeStage(fill, @"T2"); Settle(st);
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); });
            Check(NoBand(c), [NSString stringWithFormat:@"T2 iPad 2 portrait Fill, watcher idle, Aerial's fit pass put back: %@", Band(c)]);
        }
        CASE("T3") {   // the watcher running, its tick between Aerial's pass and our observer in the same turn
            Reset(CGSizeMake(1194, 834)); gWatcherPaused = NO;
            TStage *st = MakeStage(kFillM1, @"T3"); Settle(st);
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); WatcherTick(); });
            Check(NoBand(c), [NSString stringWithFormat:@"T3 watcher running, a tick between Aerial's pass and the put-back: %@", Band(c)]);
        }
        CASE("T4") {   // a holder changed inside the commit's own layout pass, after our observer
            Reset(CGSizeMake(1194, 834)); gWatcherPaused = NO;
            TStage *st = MakeStage(kFillM1, @"T4"); Settle(st);
            int adds = gPhase1Adds;
            TCommitted c = Turn(st, YES, ^{ st.relayout = 100; [st setNeedsLayout]; });
            Check(NoBand(c), [NSString stringWithFormat:@"T4 the holder laid out again in the commit (the window needs layout at the observer): %@", Band(c)]);
            Check(gPhase1Adds - adds == 1, [NSString stringWithFormat:@"T4 ... one pre-commit handler for it (%d)", gPhase1Adds - adds]);
            st.relayout = 0;
        }
        CASE("T5") {   // an animated Fit move with the watcher running: the mask moves with the holder in the same commit
            Reset(CGSizeMake(1194, 834)); gWatcherPaused = NO;
            TStage *st = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"T5"); Settle(st);
            CGRect to = CGRectMake(-6, 30, 1206, 736.4);
            objc_setAssociatedObject(st, kStageIntentKey, [NSValue valueWithCGRect:to], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            TCommitted c = Turn(st, YES, ^{ [UIView animateWithDuration:0.3 animations:^{ st.frame = to; [st layoutIfNeeded]; }]; });
            Check(NoBand(c) && c.maskAnimated && fabs(c.maskAnim - c.holderAnim) < 0.001, [NSString stringWithFormat:@"T5 an animated Fit move (0.3 s), watcher running: %@; the mask's bounds animation %.2f s, the holder's %.2f s",
                  Band(c), c.maskAnim, c.holderAnim]);
        }
        CASE("T6") {   // a half window: the pass leaves it alone
            Reset(CGSizeMake(1194, 834));
            TStage *st = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"T6"); Settle(st);
            int adds = gPhase1Adds; [gLog removeAllObjects];
            CGRect before = st.frame;
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); });
            Check(CGRectEqualToRect(st.frame, before) && NoBand(c) && gPhase1Adds == adds && !gLog.count, [NSString stringWithFormat:@"T6 a half window: the pass leaves it, no put-back, no handler: %@", Band(c)]);
        }
        CASE("T7") {   // 100 quiet turns with three windows: nothing written, no handler
            Reset(CGSizeMake(1194, 834));
            TStage *a = MakeStage(kFillM1, @"a"), *b = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"b"), *c3 = MakeStage(CGRectMake(594, 30, 606, 736.4), @"c");
            Settle(a); Settle(b); Settle(c3);
            int adds = gPhase1Adds, mut = gA5FrameMutations;
            for (int i = 0; i < 100; i++) Turn(a, YES, nil);
            Check(gPhase1Adds == adds && gA5FrameMutations == mut, [NSString stringWithFormat:@"T7 100 quiet turns, 3 windows: %d mask writes, %d handlers", gA5FrameMutations - mut, gPhase1Adds - adds]);
            gWatcherPaused = NO;
            for (int i = 0; i < 100; i++) Turn(a, YES, nil);
            Check(gPhase1Adds == adds && gA5FrameMutations == mut, @"T7 ... the same with the watcher running");
        }
        CASE("T8") {   // Aerial 3.0, Zetsu, MilkyWay4, Stage Manager, no engine: no mask of ours, no write, no handler
            Reset(CGSizeMake(1194, 834)); gGeom = NO;
            TStage *st = MakeStage(kFillM1, @"T8"); Settle(st);
            int adds = gPhase1Adds, mut = gA5FrameMutations;
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); });
            Turn(st, YES, ^{ st.frame = CGRectMake(-6, 30, 900, 700); });
            Check(!MaskOf(st) && !c.hasMask && gPhase1Adds == adds && gA5FrameMutations == mut, [NSString stringWithFormat:@"T8 not Aerial 5 (DMA5MacGeometry NO): %@, %d writes, %d handlers",
                  Band(c), gA5FrameMutations - mut, gPhase1Adds - adds]);
        }
        CASE("T9") {   // a minimized window and one hidden for Aerial's round icon: left as the watcher left them
            Reset(CGSizeMake(1194, 834));
            TStage *m = MakeStage(kFillM1, @"min"), *ch = MakeStage(kFillM1, @"chip"); Settle(m); Settle(ch);
            objc_setAssociatedObject(m, kTMinimizedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); m.hidden = YES;
            objc_setAssociatedObject(ch, kA5ChipHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); ch.hidden = YES;
            gWatcherPaused = NO;
            CGSize mm = MaskOf(m).bounds.size, cm = MaskOf(ch).bounds.size;
            Turn(m, YES, ^{ m.holder.frame = CGRectMake(6, 13, 500, 500); ch.holder.frame = CGRectMake(6, 13, 500, 500); });
            Check(CGSizeEqualToSize(MaskOf(m).bounds.size, mm) && CGSizeEqualToSize(MaskOf(ch).bounds.size, cm), @"T9 a minimized and a chip-hidden window: their masks left as they were");
        }
        CASE("T10") {   // the kill switch: 1.8.7.8's order in a DEBUG build, nothing in a release
            Reset(CGSizeMake(1194, 834)); gKill = YES;
            TStage *st = MakeStage(kFillM1, @"T10"); Settle(st);
            TCommitted c = Turn(st, YES, ^{ AerialPass(st); });
#if DEBUG
            Check(!NoBand(c) && fabs(c.holder.width - c.mask.width - 52.0) < 0.5, [NSString stringWithFormat:@"T10 (debug) /tmp/msb-a5-maskold: 1.8.7.8's order back, KT's band: %@", Band(c)]);
#else
            Check(NoBand(c), [NSString stringWithFormat:@"T10 (release) /tmp/msb-a5-maskold is no switch in a release: %@", Band(c)]);
#endif
        }
        CASE("T11") {   // the entrance hold's put-back brings the mask too
            Reset(CGSizeMake(1194, 834));
            TStage *st = MakeStage(kFillM1, @"T11"); Settle(st);
            objc_setAssociatedObject(st, kA5EntranceTargetKey, [NSValue valueWithCGRect:kFillM1], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(st, kA5EntranceUntilKey, @(CACurrentMediaTime() + 5.0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            gA5HeldStages = [NSHashTable weakObjectsHashTable]; [gA5HeldStages addObject:st];
            TCommitted c = Turn(st, YES, ^{ st.frame = CGRectMake(-6, 30, 1000, 600); });
            Check(NoBand(c) && CGRectEqualToRect(st.frame, kFillM1), [NSString stringWithFormat:@"T11 a window flying in, Aerial resized it, the hold put it back: %@", Band(c)]);
        }
        CASE("T12") {   // a put-back alone, with a commit before any pass of ours (Aerial 3.0's hooks put back the same way; a flush)
            Reset(CGSizeMake(1194, 834));
            TStage *st = MakeStage(kFillM1, @"T12"); Settle(st);
            TCommitted c = Turn(st, NO, ^{ AerialPass(st); WatcherTick(); DMEnforceStageFrame(st, @"a test"); });
            Check(NoBand(c), [NSString stringWithFormat:@"T12 a put-back committed before our pass: %@", Band(c)]);
        }
        CASE("T13") {   // KT report 2: a window behind grows (our Fit re-tile, no animation) in a turn of its own, the watcher running
            Reset(CGSizeMake(1194, 834)); gWatcherPaused = NO;
            TStage *st = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"T13"); Settle(st);
            TCommitted c = Turn(st, YES, ^{ [UIView performWithoutAnimation:^{ st.frame = kFillM1; [st layoutIfNeeded]; }];
                                            objc_setAssociatedObject(st, kStageIntentKey, [NSValue valueWithCGRect:kFillM1], OBJC_ASSOCIATION_RETAIN_NONATOMIC); });
            Check(NoBand(c), [NSString stringWithFormat:@"T13 a window behind grown by a re-tile between two ticks: %@", Band(c)]);
        }
        if (only && !strcmp(only, "T15")) {   // an iOS without pre-commit handlers (own process: the answer is read once): the end of the pass alone
            Method rs = class_getClassMethod([CATransaction class], @selector(respondsToSelector:));
            gOrigResponds = (BOOL (*)(id, SEL, SEL))method_setImplementation(rs, (IMP)TNoHandlers);
            Reset(CGSizeMake(1194, 834)); gWatcherPaused = NO;
            TStage *st = MakeStage(CGRectMake(-6, 30, 606, 736.4), @"T15"); Settle(st);
            int adds = gPhase1Adds;
            TCommitted c = Turn(st, YES, ^{ [UIView performWithoutAnimation:^{ st.frame = kFillM1; [st layoutIfNeeded]; }];
                                            objc_setAssociatedObject(st, kStageIntentKey, [NSValue valueWithCGRect:kFillM1], OBJC_ASSOCIATION_RETAIN_NONATOMIC); });
            Check(NoBand(c) && gPhase1Adds == adds, [NSString stringWithFormat:@"T15 no pre-commit handlers (an iOS without them): a re-tile between two ticks, set at the end of the pass: %@", Band(c)]);
            Reset(CGSizeMake(1194, 834));
            TStage *s2 = MakeStage(kFillM1, @"T15b"); Settle(s2);
            c = Turn(s2, YES, ^{ AerialPass(s2); });
            Check(NoBand(c), [NSString stringWithFormat:@"T15 ... KT's band (T1) without handlers: %@", Band(c)]);
        }
#if DEBUG
        CASE("T14") {   // the trace: who set the mask, and what a commit carried
            Reset(CGSizeMake(1194, 834)); gTrace = YES;
            TStage *st = MakeStage(kFillM1, @"T14"); Settle(st); [gLog removeAllObjects];
            Turn(st, YES, ^{ AerialPass(st); });
            NSString *all = [gLog componentsJoinedByString:@"\n"];
            Check([all containsString:@"by the paused watcher's pass before the commit"] && [all containsString:@"by the put-back"] && ![all containsString:@"COMMITTED"],
                  @"T14 (debug) [a5mask] lines: the paused watcher's write, then the put-back's; no COMMITTED line");
            gKill = YES; [gLog removeAllObjects];
            Turn(st, YES, ^{ AerialPass(st); });
            all = [gLog componentsJoinedByString:@"\n"];
            Check([all containsString:@"[a5mask] COMMITTED T14: holder {1194, 711"] && [all containsString:@"mask {1142, 679"],
                  [NSString stringWithFormat:@"T14 (debug) with the kill switch: a COMMITTED line names the band (%@)", [[all componentsSeparatedByString:@"\n"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS 'COMMITTED'"]].firstObject ?: @"none"]);
        }
#endif
    }
    return gFails ? 1 : 0;
}
