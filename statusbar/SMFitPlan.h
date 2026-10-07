// SMFitPlan.h -- which windows Fit to Window tiles on a Stage Manager desktop, and where (sm-nolimit, 4 Oct 2026). Plain Foundation: StatusBar.x's
// DMSMFitTick and the Mac test tools/test-smroles.m run this very code.
// Until sm-nolimit a desktop held four windows, so the tiles (2: halves, 3: a half and two quarters, 4: quarters) always covered every window.
// With more windows the other engines' rule applies (Aerial / Zetsu / MilkyWay4, StatusBar.x: "four windows are already tiled, X opens as a
// regular window over them"): while four windows are tiled and all still open, a fifth and every one after it is a regular window over them and
// the four keep their places; before, the default arrangement was laid out again for the four NEWEST, so the new window took a quarter and the
// oldest tile lost its place. Once a tile closes, the newest windows (at most four) are tiled again in the default arrangement.
#pragma once
#import <Foundation/Foundation.h>

enum { DMSMFitDefault = 0, DMSMFitKept = 1, DMSMFitFourKept = 2 };
// slots: the arrangement kept (window key -> slot name, SMWindowKey.h: two windows of one app are two tiles), or nil; bundles: the desktop's
// windows that take part (their keys), newest first; defaults: the default slot names for MIN(4, bundles.count) windows (StatusBar.x
// DMDefaultSlotNames). Returns the plan (window key -> slot); *how: DMSMFitKept = the
// arrangement as it is (it covers exactly these windows), DMSMFitFourKept = four tiles kept and the windows past them left as they are (nothing
// to lay out), DMSMFitDefault = the default arrangement for the newest windows (the caller keeps it as the new arrangement).
static NSDictionary<NSString *, NSString *> *DMSMFitPlanDecide(NSDictionary<NSString *, NSString *> *slots, NSArray<NSString *> *bundles, NSArray<NSString *> *defaults, int *how) {
    BOOL keep = slots.count == bundles.count;
    for (NSString *b in bundles) if (!slots[b]) keep = NO;
    if (keep) { if (how) *how = DMSMFitKept; return [slots copy]; }
    if (slots.count >= 4 && bundles.count > slots.count) {
        BOOL allOpen = YES;
        for (NSString *b in slots) if (![bundles containsObject:b]) allOpen = NO;
        if (allOpen) { if (how) *how = DMSMFitFourKept; return [slots copy]; }
    }
    NSMutableDictionary *plan = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < bundles.count && i < defaults.count; i++) plan[bundles[i]] = defaults[i];
    if (how) *how = DMSMFitDefault;
    return plan;
}
// The arrangement remembered for a desktop -- keyed by its windows (their keys, sorted): another stage on screen in between (a window of its own, a
// leftover stage) used to replace or drop the one global arrangement, and back on the desktop the default arrangement was laid out again for the
// four newest -- with seven windows the three tiled before were then buried under the new tiles (1.3.6 logic test L-7). memory: key -> slots.
static NSString *DMSMFitDeskKey(NSArray<NSString *> *bundles) { return [[bundles sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"\n"]; }
// The slots to decide with: the current ones when they still cover these windows (DMSMFitPlanDecide keeps them, or keeps four tiles), else the
// arrangement remembered for exactly these windows, else the current ones (the default arrangement follows).
static NSDictionary<NSString *, NSString *> *DMSMFitSlotsFor(NSDictionary<NSString *, NSString *> *current, NSDictionary<NSString *, NSDictionary *> *memory, NSArray<NSString *> *bundles) {
    int how = DMSMFitDefault;
    DMSMFitPlanDecide(current, bundles, @[], &how);
    if (how != DMSMFitDefault) return current;
    NSDictionary *mem = memory[DMSMFitDeskKey(bundles)];
    return mem.count ? mem : current;
}
