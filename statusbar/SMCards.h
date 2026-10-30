// SMCards.h -- iPadOS's App Switcher with the Stage Manager engine: one card per window, as Aerial, Zetsu and MilkyWay4 have it (1.7.1 item 6;
// KT, 30 Oct: "We don't group apps like that"). Included by StatusBar.x after SMAfterHome.h; installed by the engine's start-up check
// (DMSMCardsInstall), acts only for the engine (DMSMEngine).
// How SpringBoard draws its App Switcher (16.7.7 and 17.5.1, read on the iPads 30 Oct): the switcher's view controller (SBFluidSwitcherViewController)
// does not show its model's list (SBAppSwitcherModel: the recent stages, each an SBAppLayout) as it is -- -_rebuildCachedAdjustedAppLayouts asks its
// modifier stack for -adjustedAppLayoutsForAppLayouts: of that list ("unadjusted") and lays out what comes back ("adjusted"), and maps each window
// (leaf app layout) both to the card it is shown in (_leafAppLayoutsToAdjustedAppLayouts) and to the stage of the model it lives in
// (_leafAppLayoutsToRecencyAppLayouts). With Stage Manager on, the App Switcher's own modifier is SBAppSwitcherContinuousExposeSwitcherModifier
// ("Fluid Switcher Multitasking Modifier", under SBContinuousExposeRootSwitcherModifier), whose answer is the model's main-environment stages: a
// stage of several windows is one card. Apple's own SBSplitAllDisplayItemsSwitcherModifier answers each window of every stage as a card of its own
// (-[SBAppLayout appLayoutWithItemsPassingTest:]) on the way into App Expose, so the view controller knows cards that are a stage's window:
//  - the list: the App Switcher's answer shows each stage as its windows (DMSMCardsAdjusted, only while the App Switcher is the switcher's state,
//    DMSMCardsInSwitcher; a stage a switcher gesture holds stays whole until the gesture is over, DMSMCardsHeld), and its piles follow (below);
//  - a tap: the App Switcher modifier asks for +[SBSwitcherTransitionRequest requestForActivatingAppLayout:] of the card -- the window alone;
//    noted here (DMSMCardsTap), the transition becomes the desktop with that window in front (SMDesktop.h DMSMJoinWindowCard), a window of
//    another Mac Switcher desktop comes here or its desktop comes (MSWAppDesk.h's Bring or Go);
//  - a swipe up: -killContainer:forReason: tells the coordinator -switcherContentController:deletedDisplayItem:inAppLayout:forReason: for each
//    window of the card, with the stage it lives in -- SpringBoard's own removal of that one window (-_removeDisplayItem:forReason:...: the window
//    leaves its stage, its scene ends, its app quits), the other windows of the stage stay.
// Nothing is written to the model: the stages (our desktops), the strip, Command-Tab's own recents and Stage Manager's restore after a respring are
// untouched -- it is how the list is drawn.
// iPadOS 18 (read on the A12Z, 18.5, 30 Oct): the same calls and type encodings. Its App Switcher modifier would split the stages itself under
// Stage Manager's "additive model" (-adjustedAppLayoutsForAppLayouts: then answers each window alone, its piles are each card's own), a
// SpringBoard feature flag (SpringBoard/AdditiveModel) not declared on 18.5 -- so 18.5 answers the stages, and the piles and a card's stage come
// from the view controller (super), as on 16 and 17. Its new _currentAppLayout (the transition's toAppLayout) is only compared with a removed card
// (-handleRemovalEvent:: the App Switcher's background becomes the Home Screen when the stage it came from goes): a window's card is never equal to
// its stage, so a swipe-up keeps the desktop's other windows behind it. A tap's transition carries the display in its label (SMDeskJoin.h).
#include "SMCardPlan.h"

static id (*o_SMCardsAdjusted)(id, SEL, id);
static BOOL gSMCardsOn = NO;           // (the App Switcher's answer is ours)
static NSString *gSMCardsLast;         // (debug: the last answer shown, so the log tells only changes)
static NSHashTable *gSMCardsLeaves;    // (the windows the last split showed alone: a pile asks for them while they are shown, DMSMCardsPile)
static BOOL gSMCardsBailed = NO;       // (the App Switcher's last answer could not be split: its stages shown whole -- their piles stay whole too, DMSMCardsIdsOf)
static BOOL DMSMCardsWanted(void) {
    if (!gSMCardsOn) return NO;   // (the hooks are all in: DMSMCardsInstall)
#if DEBUG
    if (DMTestFlag("/tmp/msb-smcards-off")) return NO;   // (debug: Apple's stage cards, to compare)
#endif
    return DMSMEngine();
}
static NSString *DMSMCardsText(NSArray *layouts) {   // (debug: each card as its windows' apps, "Clock+Tips | Maps")
    NSMutableArray *parts = [NSMutableArray array];
    for (id al in layouts) {
        NSMutableArray *bs = [NSMutableArray array];
        id items = [al respondsToSelector:NSSelectorFromString(@"allItems")] ? DMCall(al, @"allItems") : nil;
        if ([items isKindOfClass:[NSArray class]]) for (id it in (NSArray *)items) [bs addObject:[[DMSMItemBundle(it) ?: @"?" componentsSeparatedByString:@"."] lastObject]];
        long long env = [al respondsToSelector:NSSelectorFromString(@"environment")] ? ((long long (*)(id, SEL))objc_msgSend)(al, NSSelectorFromString(@"environment")) : -1;
        [parts addObject:[NSString stringWithFormat:@"%@%@", [bs componentsJoinedByString:@"+"], env == 1 ? @"" : [NSString stringWithFormat:@" (env %lld)", env]]];
    }
    return [parts componentsJoinedByString:@" | "];
}
// ---- what a switcher gesture holds stays one card until the gesture is over ----
// SpringBoard's gesture modifiers keep the stage under the finger (SBGestureRootSwitcherModifier / SBHomeGestureSwitcherModifier /
// SBReduceMotionHomeGestureSwitcherModifier _selectedAppLayout, SBHomeGestureToSwitcherSwitcherModifier _appLayout, ...) and look it up in the
// shown list: -[SBHomeGestureToSwitcherSwitcherModifier appLayoutsToCacheSnapshots] takes [appLayouts indexOfObject:_appLayout] as a range's
// start without a not-found check. With that stage shown as its windows it raised (NSRangeException in -[NSArray subarrayWithRange:]) and
// SpringBoard went down at the end of a hold into the App Switcher (iPad 2, sm07, Mac Switcher off). So every stage a gesture modifier of the main
// switcher's modifier tree holds is shown whole while it does -- the stage the finger moves -- and as its windows once that modifier has gone (the
// switcher rebuilds its list after every modifier change: -_performEventResponse: -> -_rebuildCachedAdjustedAppLayouts). 18.5 holds it in
// SBContinuousExposeHomeGesture(Root)SwitcherModifier and SBHomeGestureToSwitcherSwitcherModifier _selectedAppLayout, whose
// -appLayoutsToCacheFullsizeSnapshots now takes [appLayouts indexOfObject:] of it (A12Z: three holds into the App Switcher, the stage whole until
// each gesture was over).
static Ivar gSMCardsRootIvar;   // (SBFluidSwitcherViewController._rootModifier)
static NSMutableDictionary<NSString *, NSArray<NSValue *> *> *gSMCardsHeldIvars;   // (per modifier class: its gesture classes' SBAppLayout ivars)
static NSArray<NSValue *> *DMSMCardsHeldIvarsOf(Class c) {
    NSString *name = NSStringFromClass(c);
    NSArray<NSValue *> *have = gSMCardsHeldIvars[name];
    if (have) return have;
    NSMutableArray<NSValue *> *out = [NSMutableArray array];
    for (Class k = c; k; k = class_getSuperclass(k)) {
        if (![NSStringFromClass(k) containsString:@"Gesture"]) continue;   // (the gestures' own modifiers; a card's own removal / insertion holds a card of the list)
        unsigned n = 0; Ivar *iv = class_copyIvarList(k, &n);
        for (unsigned i = 0; i < n; i++) { const char *t = ivar_getTypeEncoding(iv[i]); if (t && !strcmp(t, "@\"SBAppLayout\"")) [out addObject:[NSValue valueWithPointer:iv[i]]]; }
        free(iv);
    }
    if (!gSMCardsHeldIvars) gSMCardsHeldIvars = [NSMutableDictionary dictionary];
    gSMCardsHeldIvars[name] = out;
    return out;
}
static NSString *gSMCardsHeldLast;   // (debug: the last held set logged)
static NSSet *DMSMCardsHeld(void) {   // (the stages the main switcher's gesture modifiers hold now; nil: none)
    id vc = DMMainSwitcherContent();
    if (!vc) return nil;
    if (!gSMCardsRootIvar) gSMCardsRootIvar = class_getInstanceVariable(object_getClass(vc), "_rootModifier");
    id root = gSMCardsRootIvar ? object_getIvar(vc, gSMCardsRootIvar) : nil;
    if (!root) return nil;
    NSMutableSet *held = nil;
    NSMutableArray *todo = [NSMutableArray arrayWithObject:root];
    SEL en = NSSelectorFromString(@"enumerateChildModifiersWithBlock:");
    BOOL dbg = DMTestFlag("/tmp/msb-smcards-tree");   // (debug: the main switcher's modifier tree and every stage each modifier holds, on each change)
    NSMutableArray *treeText = dbg ? [NSMutableArray array] : nil;
    for (int n = 0; todo.count && n < 96; n++) {
        id m = todo.lastObject; [todo removeLastObject];
        if (dbg) {
            NSMutableString *t = [NSMutableString stringWithString:NSStringFromClass([m class])];
            for (Class k = object_getClass(m); k && k != [NSObject class]; k = class_getSuperclass(k)) {
                unsigned ni = 0; Ivar *iv = class_copyIvarList(k, &ni);
                for (unsigned i = 0; i < ni; i++) { const char *ty = ivar_getTypeEncoding(iv[i]); if (ty && !strcmp(ty, "@\"SBAppLayout\"")) { id al = object_getIvar(m, iv[i]); if (al) [t appendFormat:@" %s=%@", ivar_getName(iv[i]), DMSMCardsText(@[al])]; } }
                free(iv);
            }
            [treeText addObject:t];
        }
        for (NSValue *v in DMSMCardsHeldIvarsOf(object_getClass(m))) {
            id al = object_getIvar(m, (Ivar)v.pointerValue);
            if (!DMSMIsStage(al)) continue;
            if (!held) held = [NSMutableSet set];
            [held addObject:al];
        }
        if ([m respondsToSelector:en]) ((void (*)(id, SEL, id))objc_msgSend)(m, en, ^(id child, BOOL *stop) { if (child) [todo addObject:child]; });
    }
    if (dbg) {
        static NSString *lastTree;
        NSString *tt = [treeText componentsJoinedByString:@" / "];
        if (![tt isEqualToString:lastTree ?: @""]) { lastTree = tt; DMLog([NSString stringWithFormat:@"[smcards] tree: %@", tt]); }
    }
    if (DMTestFlag("/tmp/macstatusbar-debug")) {
        NSString *now = held.count ? DMSMCardsText(held.allObjects) : @"";
        if (![now isEqualToString:gSMCardsHeldLast ?: @""]) { gSMCardsHeldLast = now; DMLog([NSString stringWithFormat:@"[smcards] held by a switcher gesture (shown whole): %@", now.length ? now : @"none"]); }
    }
    return held;
}
// The App Switcher's own moments only: the main switcher's layout state is (or is going to) its App Switcher, environment 2. Its modifier is a
// child of the root in every environment and is asked along with the others; in application mode (the desktop on screen), at the Home Screen and
// in the transitions there (a desktop switch, an app-to-app swipe: SBContinuousExposeAppToAppModifier holds both stages) every list stays
// SpringBoard's own.
// Read from the main switcher's own layout context (SBFluidSwitcherLayoutContext): where its transition is going, from the transition's start
// (-transitioningToLayoutState -- the App Switcher's first layout is then already one card per window, so its scroll position is set for those
// cards), else its layout state. Until the code review of 30 Oct this was the environment of the last switcher transition event SpringBoard made
// (gEnvMode), which every switcher sends -- an external display's too -- and nothing clears: a TV's App Switcher, or a mode left from a transition
// that ended otherwise, could split the main App Switcher modifier's answer while the iPad's own display showed a desktop, where modifiers other
// than the gestures' (DMSMCardsHeld) may look a whole stage up in that list (the sm07 crash kind). The layout context's calls are type-checked; one
// that is not there (another iPadOS): its layout state alone, later by the length of the transition (DMSMCardsNoteShown scrolls once the cards
// became more).
static id DMSMCardsCtxState(id ctx, NSString *name) {
    SEL s = NSSelectorFromString(name);
    return [ctx respondsToSelector:s] && DMSMSigOK(ctx, s, DMSMSigObj(), name.UTF8String) ? ((id (*)(id, SEL))objc_msgSend)(ctx, s) : nil;
}
static BOOL DMSMCardsInSwitcher(void) {
    id ctx = DMSMCardsCtxState(DMMainSwitcherContent(), @"layoutContext");
    id going = DMSMCardsCtxState(ctx, @"transitioningToLayoutState"), state = going ?: DMSMCardsCtxState(ctx, @"layoutState");
    long long env = 0; id stage = nil;
    BOOL in = DMSMHomeStateOf(state, &env, &stage) && env == 2;
#if DEBUG
    if (DMTestFlag("/tmp/macstatusbar-debug")) {   // (each change: where the decision came from, beside the last event of any switcher it no longer follows)
        static NSString *last;
        NSString *now = [NSString stringWithFormat:@"%@ environment %lld (the last transition event of any switcher: %lld)", going ? @"going to" : @"at", env, gEnvMode];
        if (![now isEqualToString:last ?: @""]) { last = now; DMLog([NSString stringWithFormat:@"[smcards] the main switcher: %@ -> %@", now, in ? @"a card per window" : @"SpringBoard's own lists"]); }
    }
#endif
    return in;
}
// The main switcher's own App Switcher modifier (not the TV's: its switcher has a modifier tree of its own).
static BOOL DMSMCardsMainTree(id mod) {
    id vc = DMMainSwitcherContent();
    if (!vc) return NO;
    if (!gSMCardsRootIvar) gSMCardsRootIvar = class_getInstanceVariable(object_getClass(vc), "_rootModifier");
    id root = gSMCardsRootIvar ? object_getIvar(vc, gSMCardsRootIvar) : nil;
    SEL p = NSSelectorFromString(@"parentModifier");
    for (int n = 0; mod && n < 16; n++) {
        if (mod == root) return YES;
        mod = [mod respondsToSelector:p] ? ((id (*)(id, SEL))objc_msgSend)(mod, p) : nil;
    }
    return NO;
}
// ---- the App Switcher's scroll position when its cards become more ----
// The App Switcher scrolls to its newest card as it comes (the newest pile at the right end, the oldest cut off at the left when they don't
// fit: 17.5 portrait, five piles, Apple's own). Its scroll position is set for the cards of that moment; when a stage became its windows only later
// -- the stage a hold into the App Switcher held, once the gesture is over -- there were more piles, the content grew past the screen and the
// newest pile was cut off at the right (17.5, sm12). So when the cards become more with the same stages (not an app opened or quit), the switcher
// is asked to scroll to its newest card again, its own way: -[SBFluidSwitcherViewController _scrollToAppLayout:animated:alignment:completion:]
// (the content size updated, the root modifier's -contentOffsetForIndex:alignment:), with the alignment SpringBoard's gesture-to-switcher uses
// for the card it comes from when that is the first (-[SBHomeGestureToSwitcherSwitcherModifier _appLayoutAlignmentToScrollToDuringTransition]: 2).
static NSArray *gSMCardsLastIn;            // (the stages the App Switcher's answer last had, and how many cards it showed for them)
static NSUInteger gSMCardsLastOutCount = 0;
static long long DMSMCardsAlignment(void) {
#if DEBUG
    NSString *a = [NSString stringWithContentsOfFile:@"/tmp/msb-smcards-align" encoding:NSUTF8StringEncoding error:nil];   // (debug: another alignment, to compare)
    if (a.length) return a.longLongValue;
#endif
    return 2;
}
static void DMSMCardsScrollToNewest(int tries) {
    if (!DMMainSwitcherVisible()) return;   // (gone meanwhile: nothing to do)
    if (DMWinCardBusy()) {   // (a transition or gesture still runs: once it is over, up to 2 s)
        if (tries < 20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMSMCardsScrollToNewest(tries + 1); });
        return;
    }
    id vc = DMMainSwitcherContent();
    SEL sc = NSSelectorFromString(@"_scrollToAppLayout:animated:alignment:completion:");
    if (!vc || !DMSMSigOK(vc, sc, DMSMExpect(@encode(void), @encode(id), @encode(BOOL), @encode(long long), @encode(id), NULL), "_scrollToAppLayout:animated:alignment:completion:")) return;
    id first = [DMCall(vc, @"appLayouts") firstObject];
    if (!DMSMIsStage(first)) return;
    @try { ((void (*)(id, SEL, id, BOOL, long long, id))objc_msgSend)(vc, sc, first, YES, DMSMCardsAlignment(), nil); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[smcards] scrolling to the newest card failed: %@", e.reason]); return; }
    DM_FEATURE_MARK("sm-switcher-cards-rescroll");
    if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smcards] the App Switcher's cards became more: scrolled to its newest card again (%@)", DMSMCardsText(@[first])]);
}
static BOOL gSMCardsSessionScrolled = NO;   // (this App Switcher's first answer with a window shown alone has asked for its scroll position)
// (each switcher transition event: anywhere but the App Switcher, the next App Switcher is a new one -- its modifier is not always asked outside it,
//  so the answers alone missed the end of one and the second App Switcher kept the first's scroll: iPad 2, sm15, rotations)
static void DMSMCardsSwitcherEnv(long long mode) { if (mode != 2) gSMCardsSessionScrolled = NO; }
static void DMSMCardsNoteShown(NSArray *in, NSUInteger shown, BOOL inSwitcher) {   // (each answer of the main App Switcher modifier: in -> how many cards)
    BOOL grew = gSMCardsLastIn && shown > gSMCardsLastOutCount && [in isEqualToArray:gSMCardsLastIn];
    gSMCardsLastIn = in; gSMCardsLastOutCount = shown;
    // (the App Switcher's own scroll to its newest card came with the stages' piles: as it comes up over a desktop of several windows its newest
    //  pile was cut off at the right, its oldest had the margin -- 17.5 portrait, five cards, sm14, Show App Switcher. Once per App Switcher, and
    //  whenever the cards became more for the same stages)
    BOOL first = inSwitcher && shown > in.count && !gSMCardsSessionScrolled;
    if (!inSwitcher) gSMCardsSessionScrolled = NO;
    if (first) gSMCardsSessionScrolled = YES;
    if (grew || first) dispatch_async(dispatch_get_main_queue(), ^{ DMSMCardsScrollToNewest(0); });
}
// (a split that cannot be made -- a window that cannot be shown alone, an exception --: the stages whole, and nothing of a split left behind. Code
//  review, 30 Oct: the windows of the split before stayed in gSMCardsLeaves and the piles were split all the same -- piles and cards disagreed)
static id DMSMCardsBail(NSArray *in, NSString *why) {
    gSMCardsLeaves = nil; gSMCardsBailed = YES;
    DMSMCardsNoteShown(in, in.count, YES);
    static NSString *last;
    if (![why isEqualToString:last ?: @""]) { last = why; DMLog([NSString stringWithFormat:@"[smcards] the App Switcher's cards could not be split (%@): the stages as SpringBoard shows them, their piles too", why]); }
    return in;
}
static id DMSMCardsSplitList(id self, id r) {   // (the App Switcher modifier's answer r, its stages shown as their windows)
    if (![r isKindOfClass:[NSArray class]] || [(NSArray *)r count] == 0 || !DMSMCardsWanted() || !DMSMCardsMainTree(self)) return r;
    if (!DMSMCardsInSwitcher()) { gSMCardsBailed = NO; DMSMCardsNoteShown(r, [(NSArray *)r count], NO); return r; }
    NSArray *in = r;
    @try {
        NSSet *held = DMSMCardsHeld();   // (the stage a switcher gesture moves: whole until it is over)
        SEL allS = NSSelectorFromString(@"allItems"), envS = NSSelectorFromString(@"environment");
        NSMutableArray<NSDictionary *> *cards = [NSMutableArray arrayWithCapacity:in.count];
        NSMutableArray<NSArray *> *itemsOf = [NSMutableArray arrayWithCapacity:in.count];
        for (id al in in) {
            NSArray *items = DMSMIsStage(al) ? ((id (*)(id, SEL))objc_msgSend)(al, allS) : nil;
            if (![items isKindOfClass:[NSArray class]]) items = @[];
            [itemsOf addObject:items];
            long long env = DMSMIsStage(al) ? ((long long (*)(id, SEL))objc_msgSend)(al, envS) : 0;
            if (items.count < 2 || env != 1 || [held containsObject:al]) { [cards addObject:@{@"env": @(env), @"t": @[]}]; continue; }   // (whole)
            NSDictionary *map = DMSMStageItemsMap(al);
            NSMutableArray *t = [NSMutableArray arrayWithCapacity:items.count];
            for (id it in items) { long long v = 0; id a = map[it]; [t addObject:a && DMSMAttrLastInteractionTime(a, &v) ? @(v) : (id)[NSNull null]]; }
            [cards addObject:@{@"env": @(env), @"t": t}];
        }
        NSArray<NSArray<NSNumber *> *> *plan = MSBDSMCardsSplit(cards);
        if (!plan) { gSMCardsLeaves = nil; gSMCardsBailed = NO; DMSMCardsNoteShown(in, in.count, YES); return r; }   // (no stage of several windows: SpringBoard's own list)
        SEL leafS = NSSelectorFromString(@"leafAppLayoutForItem:");
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:plan.count];
        for (NSArray<NSNumber *> *p in plan) {
            NSUInteger c = p[0].unsignedIntegerValue; NSInteger w = p[1].integerValue;
            if (w < 0) { [out addObject:in[c]]; continue; }
            id leaf = ((id (*)(id, SEL, id))objc_msgSend)(in[c], leafS, itemsOf[c][(NSUInteger)w]);
            if (!DMSMIsStage(leaf)) return DMSMCardsBail(in, @"a window that cannot be shown alone");   // (the whole list as SpringBoard has it)
            [out addObject:leaf];
        }
        NSHashTable *leaves = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];   // (the windows shown alone now: their piles, DMSMCardsPile)
        for (NSUInteger i = 0; i < plan.count; i++) if (plan[i][1].integerValue >= 0) [leaves addObject:out[i]];
        gSMCardsLeaves = leaves; gSMCardsBailed = NO;
        DMSMCardsNoteShown(in, out.count, YES);
        DM_FEATURE_MARK("sm-switcher-card-per-window");
        if (DMTestFlag("/tmp/macstatusbar-debug")) {
            NSString *now = DMSMCardsText(out);
            if (![now isEqualToString:gSMCardsLast]) { gSMCardsLast = now; DMLog([NSString stringWithFormat:@"[smcards] %@: %@ shown as %@", NSStringFromClass([self class]), DMSMCardsText(in), now]); }
        }
        return out;
    } @catch (NSException *e) {
        return DMSMCardsBail(in, e.reason ?: @"an exception");
    }
}
static id DMSMCardsAdjusted(id self, SEL _cmd, id layouts) {
    id r = o_SMCardsAdjusted(self, _cmd, layouts), out = r;
    DM_PERF("t-smcards-list", out = DMSMCardsSplitList(self, r));   // (its cost per answer, in the debug [perf] summary)
    return out;
}
// ---- the App Switcher's piles ----
// SpringBoard's Stage Manager App Switcher lays its cards out in piles, one per "continuous expose identifier" (the stage's apps, "com.apple.tips&
// com.apple.mobiletimer"; a one-window stage's is its app's): the identifiers in the switcher come from the App Switcher modifier's
// -adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip: (each shown card counted under the stage that
// holds it, -appLayoutContainingAppLayout:), and a pile's cards from the view controller's -appLayoutsForContinuousExposeIdentifier: (the model's
// stages of that identifier, -_unadjustedAppLayouts). A window shown alone belongs to no pile there: it was drawn at full size, off the screen
// (iPad 2, sm01). So a split stage's identifier stands for its windows' own (in the order they are shown), and a window's own identifier's pile has
// the windows of split stages with that identifier besides the stages SpringBoard has for it -- two windows of one app are one pile, as two
// one-window stages of an app are in Apple's App Switcher.
static id (*o_SMCardsIds)(id, SEL, id, id);
static id (*o_SMCardsPile)(id, SEL, id);
// The split of the model's main-display stages (the windows' leaf layouts in the split's order) by the stage's identifier -- none at all when a
// window cannot be shown alone, as the list's split (DMSMCardsSplitList) gives up then.
static NSDictionary<NSString *, NSArray *> *DMSMCardsSplitByIdentifier(void) {
    NSMutableDictionary<NSString *, NSMutableArray *> *out = [NSMutableDictionary dictionary];
    NSSet *held = DMSMCardsHeld();   // (shown whole while a switcher gesture holds it: its own pile)
    SEL cidS = NSSelectorFromString(@"continuousExposeIdentifier"), leafS = NSSelectorFromString(@"leafAppLayoutForItem:");
    for (id al in DMSMRecentStages() ?: @[]) {
        if (!DMSMIsMainIdentity(DMSMStageDisplayIdentity(al))) continue;
        NSArray *items = DMCall(al, @"allItems");
        long long env = ((long long (*)(id, SEL))objc_msgSend)(al, NSSelectorFromString(@"environment"));
        if (![items isKindOfClass:[NSArray class]] || items.count < 2 || env != 1 || [held containsObject:al]) continue;
        NSDictionary *map = DMSMStageItemsMap(al);
        NSMutableArray *t = [NSMutableArray array];
        for (id it in items) { long long v = 0; id a = map[it]; [t addObject:a && DMSMAttrLastInteractionTime(a, &v) ? @(v) : (id)[NSNull null]]; }
        NSArray<NSArray<NSNumber *> *> *plan = MSBDSMCardsSplit(@[@{@"env": @1, @"t": t}]);
        NSString *cid = ((id (*)(id, SEL))objc_msgSend)(al, cidS);
        if (!plan || ![cid isKindOfClass:[NSString class]]) continue;
        NSMutableArray *leaves = out[cid] ?: [NSMutableArray array];
        for (NSArray<NSNumber *> *p in plan) { id leaf = ((id (*)(id, SEL, id))objc_msgSend)(al, leafS, items[p[1].unsignedIntegerValue]); if (!DMSMIsStage(leaf)) return nil; [leaves addObject:leaf]; }
        out[cid] = leaves;
    }
    return out;
}
static id DMSMCardsIdsOf(id self, id r) {
    if (![r isKindOfClass:[NSArray class]] || gSMCardsBailed || !DMSMCardsWanted() || !DMSMCardsInSwitcher() || !DMSMCardsMainTree(self)) return r;
    @try {
        NSDictionary<NSString *, NSArray *> *split = DMSMCardsSplitByIdentifier();
        if (!split.count) return r;
        NSMutableOrderedSet *out = [NSMutableOrderedSet orderedSet];
        SEL cidS = NSSelectorFromString(@"continuousExposeIdentifier");
        for (id cid in (NSArray *)r) {
            NSArray *leaves = [cid isKindOfClass:[NSString class]] ? split[cid] : nil;
            if (!leaves.count) { [out addObject:cid]; continue; }
            for (id leaf in leaves) { id lc = ((id (*)(id, SEL))objc_msgSend)(leaf, cidS); if ([lc isKindOfClass:[NSString class]]) [out addObject:lc]; }
        }
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smcards] piles: %@ -> %@", [(NSArray *)r componentsJoinedByString:@", "], [out.array componentsJoinedByString:@", "]]);
        return out.array;
    } @catch (NSException *e) { return r; }
}
static id DMSMCardsIds(id self, SEL _cmd, id prev, id strip) {
    id r = o_SMCardsIds(self, _cmd, prev, strip), out = r;
    DM_PERF("t-smcards-piles", out = DMSMCardsIdsOf(self, r));
    return out;
}
static id DMSMCardsPileOf(id self, id cid, id r) {
    if (!gSMCardsLeaves.count || ![cid isKindOfClass:[NSString class]] || !DMSMCardsWanted() || self != DMMainSwitcherContent()) return r;
    @try {
        NSArray *shown = DMCall(self, @"appLayouts");   // (what the switcher shows now: our split only while the App Switcher's answer is in)
        if (![shown isKindOfClass:[NSArray class]]) return r;
        SEL cidS = NSSelectorFromString(@"continuousExposeIdentifier");
        NSMutableArray *out = nil;
        for (id al in shown) {
            if (![gSMCardsLeaves containsObject:al]) continue;
            id lc = ((id (*)(id, SEL))objc_msgSend)(al, cidS);
            if (![lc isEqual:cid]) continue;
            if (!out) out = [NSMutableArray array];
            [out addObject:al];
        }
        if (!out) return r;
        for (id al in ([r isKindOfClass:[NSArray class]] ? r : @[])) if (![out containsObject:al]) [out addObject:al];   // (the app's one-window stages: the same pile)
        return out;
    } @catch (NSException *e) { return r; }
}
static id DMSMCardsPile(id self, SEL _cmd, id cid) {
    id r = o_SMCardsPile(self, _cmd, cid), out = r;
    if (gSMCardsLeaves.count) DM_PERF("t-smcards-pile", out = DMSMCardsPileOf(self, cid, r));   // (nothing to add while no window is shown alone)
    return out;
}
// ---- a tap on a window's card ----
// SpringBoard activates the tapped card's layout: for a window shown alone, that window by itself (role 1, every other window role emptied), and
// the desktop's other windows left the screen (iPad 2, sm02: Clock's card, Tips gone). The App Switcher modifier's own tap answer
// (-handleTapAppLayoutEvent:, +[SBSwitcherTransitionRequest requestForActivatingAppLayout:] of the event's card) notes the window here first, and
// the transition it makes is turned into the desktop with that window in front (SMDesktop.h DMSMJoinStageAsked, SMDeskJoin.h DMSMDeskCardPlan) --
// as a click on the window. A window of another Mac Switcher desktop comes here (Bring) or its desktop comes (Go), MSWAppDesk.h; one in no
// desktop's stage (Mac Switcher off: a stage left behind) joins the desktop, as a launch does.
static id (*o_SMCardsTap)(id, SEL, id);
static NSString *gSMCardsTapKey;    // (the window whose card was tapped last, and when: DMSMCardsTappedKey)
static CFTimeInterval gSMCardsTapAt = 0;
static id DMSMCardsTap(id self, SEL _cmd, id event) {
    @try {
        SEL al = NSSelectorFromString(@"appLayout");
        id leaf = gSMCardsLeaves.count && [event respondsToSelector:al] && DMSMSigOK(event, al, DMSMSigObj(), "appLayout") ? ((id (*)(id, SEL))objc_msgSend)(event, al) : nil;
        if (DMSMIsStage(leaf) && [gSMCardsLeaves containsObject:leaf] && DMSMCardsWanted()) {
            NSArray *items = DMCall(leaf, @"allItems");
            NSString *k = [items isKindOfClass:[NSArray class]] && items.count == 1 ? DMSMItemKey(items.firstObject) : nil;
            if (k.length) {
                gSMCardsTapKey = k; gSMCardsTapAt = CACurrentMediaTime();
                DMLog([NSString stringWithFormat:@"[smcards] the card of %@ (a window of a desktop, shown alone) tapped: it comes to the front of the desktop on screen", DMSMKeyText(k)]);
            }
        }
    } @catch (NSException *e) {}
    return o_SMCardsTap(self, _cmd, event);
}
static NSString *DMSMCardsTappedKey(void) {   // (a window's card tapped in the last 2 s: that window's key)
    return gSMCardsTapKey && CACurrentMediaTime() - gSMCardsTapAt < 2.0 ? gSMCardsTapKey : nil;
}
static void DMSMCardsTapDone(void) { gSMCardsTapKey = nil; }
static void DMSMCardsInstall(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    NSInteger major = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion;
    BOOL anyOS = NO;
#if DEBUG
    anyOS = DMTestFlag("/tmp/msb-smcards-anyos");   // (debug: try it on a version not checked yet)
#endif
    if (!anyOS && !MSBDSMCardsOSChecked(major)) { DMLog([NSString stringWithFormat:@"[smcards] iPadOS %ld: the App Switcher's cards stay as iPadOS has them (not checked on this iPadOS yet)", (long)major]); return; }
    Class m = objc_getClass("SBAppSwitcherContinuousExposeSwitcherModifier"), al = objc_getClass("SBAppLayout");
    SEL adj = sel_registerName("adjustedAppLayoutsForAppLayouts:");
    Method ma = m ? class_getInstanceMethod(m, adj) : NULL;
    Method ml = al ? class_getInstanceMethod(al, sel_registerName("leafAppLayoutForItem:")) : NULL, mi = al ? class_getInstanceMethod(al, sel_registerName("allItems")) : NULL;
    Method me = al ? class_getInstanceMethod(al, sel_registerName("environment")) : NULL, mm = al ? class_getInstanceMethod(al, sel_registerName("itemsToLayoutAttributesMap")) : NULL;
    NSString *objObj = DMSMExpect(@encode(id), @encode(id), NULL), *obj = DMSMExpect(@encode(id), NULL);
    BOOL ok = ma && ml && mi && me && mm && [DMSMSigOfMethod(ma) isEqualToString:objObj] && [DMSMSigOfMethod(ml) isEqualToString:objObj]
           && [DMSMSigOfMethod(mi) isEqualToString:obj] && [DMSMSigOfMethod(mm) isEqualToString:obj]
           && [DMSMSigOfMethod(me) isEqualToString:DMSMExpect(@encode(long long), NULL)];
    if (!ok) { DMLog(@"[smcards] the App Switcher's stage cards are not as read on 16.7.7 / 17.5.1 / 18.5: they stay as iPadOS has them (a stage of several windows is one card)"); return; }
    SEL ids = sel_registerName("adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:"), pile = sel_registerName("appLayoutsForContinuousExposeIdentifier:");
    Class vc = objc_getClass("SBFluidSwitcherViewController");
    Method mids = class_getInstanceMethod(m, ids), mp = vc ? class_getInstanceMethod(vc, pile) : NULL;
    if (!mids || !mp || ![DMSMSigOfMethod(mids) isEqualToString:DMSMExpect(@encode(id), @encode(id), @encode(id), NULL)] || ![DMSMSigOfMethod(mp) isEqualToString:objObj]) {
        DMLog(@"[smcards] the App Switcher's piles are not as read on 16.7.7 / 17.5.1 / 18.5: a stage of several windows stays one card"); return;
    }
    SEL tap = sel_registerName("handleTapAppLayoutEvent:");
    Method mt = class_getInstanceMethod(m, tap);
    if (!mt || ![DMSMSigOfMethod(mt) isEqualToString:objObj]) { DMLog(@"[smcards] the App Switcher's tap is not as read on 16.7.7 / 17.5.1 / 18.5: a stage of several windows stays one card"); return; }
    MSHookMessageEx(m, tap, (IMP)DMSMCardsTap, (IMP *)&o_SMCardsTap);
    MSHookMessageEx(m, ids, (IMP)DMSMCardsIds, (IMP *)&o_SMCardsIds);
    MSHookMessageEx(vc, pile, (IMP)DMSMCardsPile, (IMP *)&o_SMCardsPile);
    MSHookMessageEx(m, adj, (IMP)DMSMCardsAdjusted, (IMP *)&o_SMCardsAdjusted);
    // (all four or none: the split without its piles drew the windows full size off the screen, sm01 -- a hook that did not take leaves every one
    //  of them passing SpringBoard's answers through, DMSMCardsWanted)
    gSMCardsOn = o_SMCardsAdjusted && o_SMCardsIds && o_SMCardsPile && o_SMCardsTap
              && method_getImplementation(class_getInstanceMethod(m, adj)) == (IMP)DMSMCardsAdjusted && method_getImplementation(class_getInstanceMethod(m, ids)) == (IMP)DMSMCardsIds
              && method_getImplementation(class_getInstanceMethod(vc, pile)) == (IMP)DMSMCardsPile && method_getImplementation(class_getInstanceMethod(m, tap)) == (IMP)DMSMCardsTap;
    DMLog(gSMCardsOn ? @"[smcards] iPadOS's App Switcher shows each window of a desktop as a card of its own" : @"[smcards] the App Switcher's answer could not be replaced: a stage of several windows stays one card");
}

#if DEBUG
// smcards: the main App Switcher's model list (unadjusted) and what it shows (adjusted), each card as its windows' apps; the root modifier
// (read-only). smcards_leaf: for each stage of several windows, whether its -leafAppLayouts are the windows our split shows (equal, same hash).
static BOOL DMSMCardsTrigger(NSString *cmd) {
    id vc = DMMainSwitcherContent();
    if ([cmd isEqualToString:@"smcards"]) {
        NSArray *un = [vc respondsToSelector:NSSelectorFromString(@"_unadjustedAppLayouts")] ? DMCall(vc, @"_unadjustedAppLayouts") : nil;
        NSArray *adj = [vc respondsToSelector:NSSelectorFromString(@"appLayouts")] ? DMCall(vc, @"appLayouts") : nil;
        id root = nil; @try { root = [vc valueForKey:@"_rootModifier"]; } @catch (id e) { root = nil; }
        DMLog([NSString stringWithFormat:@"[smcards] engine %d, hook %d, switcher shown %d; %@: model %lu: %@", DMSMEngine(), gSMCardsOn, DMMainSwitcherVisible(), vc ? NSStringFromClass([vc class]) : @"no content", (unsigned long)un.count, DMSMCardsText(un)]);
        DMLog([NSString stringWithFormat:@"[smcards] shown %lu: %@; root %@", (unsigned long)adj.count, DMSMCardsText(adj), root ? NSStringFromClass([root class]) : @"none"]);
        return YES;
    }
    if ([cmd isEqualToString:@"smcards_scroll"]) { DMSMCardsScrollToNewest(0); return YES; }   // smcards_scroll: the App Switcher to its newest card now (/tmp/msb-smcards-align: another alignment)
    if ([cmd isEqualToString:@"smcards_leaf"]) {
        for (id al in DMSMRecentStages() ?: @[]) {
            NSArray *items = DMCall(al, @"allItems");
            if (![items isKindOfClass:[NSArray class]] || items.count < 2) continue;
            NSArray *leaves = DMCall(al, @"leafAppLayouts");
            for (id it in items) {
                id mine = ((id (*)(id, SEL, id))objc_msgSend)(al, NSSelectorFromString(@"leafAppLayoutForItem:"), it);
                BOOL found = NO; for (id l in ([leaves isKindOfClass:[NSArray class]] ? leaves : @[])) if ([l isEqual:mine] && [l hash] == [mine hash]) found = YES;
                NSArray *own = DMCall(mine, @"leafAppLayouts");
                DMLog([NSString stringWithFormat:@"[smcards] %@: its window alone is one of the stage's leaves %d; its own leaves %lu, equal %d", DMSMItemBundle(it), found, (unsigned long)[own count], [own count] == 1 && [own.firstObject isEqual:mine]]);
            }
        }
        return YES;
    }
    return NO;
}
#endif
