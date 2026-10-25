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
// The desktop brought back after a respring, laid out for another screen shape (the iPad turned while SpringBoard restarted): its windows'
// sizes are of the old shape, but where they sit against each other is kept, and that names their tiles -- one window: the whole space; two:
// side by side (left / right) or one above the other (top / bottom), whichever way they are further apart; three: the side with one window is
// its half, the other side's two are its quarters, top and bottom (Fit's three-window arrangement); four: the quarters. centres: window key ->
// @[x, y], its centre as fractions of the screen. nil when they do not read as distinct tiles (Fit then lays them out as a new set).
static inline NSDictionary<NSString *, NSString *> *DMSMFitTilesFromCentres(NSDictionary<NSString *, NSArray<NSNumber *> *> *centres) {
    NSArray<NSString *> *keys = [centres.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger n = keys.count;
    if (!n || n > 4) return nil;
    for (NSString *k in keys) {
        NSArray *p = centres[k];
        if (![p isKindOfClass:[NSArray class]] || p.count != 2) return nil;
        double x = [p[0] doubleValue], y = [p[1] doubleValue];
        if (!(x >= -0.25 && x <= 1.25) || !(y >= -0.25 && y <= 1.25)) return nil;   // (not finite, or far off the screen)
    }
    double (^X)(NSString *) = ^double(NSString *k) { return [centres[k][0] doubleValue]; };
    double (^Y)(NSString *) = ^double(NSString *k) { return [centres[k][1] doubleValue]; };
    if (n == 1) return @{ keys[0]: @"fill" };
    if (n == 2) {
        NSString *a = keys[0], *b = keys[1];
        double dx = fabs(X(a) - X(b)), dy = fabs(Y(a) - Y(b));
        if (dx < 0.05 && dy < 0.05) return nil;   // (one on the other: no tiles to read)
        if (dx >= dy) return X(a) < X(b) ? @{ a: @"left", b: @"right" } : @{ a: @"right", b: @"left" };
        return Y(a) < Y(b) ? @{ a: @"top", b: @"bottom" } : @{ a: @"bottom", b: @"top" };
    }
    NSMutableArray<NSString *> *left = [NSMutableArray array], *right = [NSMutableArray array];
    for (NSString *k in keys) [(X(k) < 0.5 ? left : right) addObject:k];
    NSComparisonResult (^byY)(NSString *, NSString *) = ^NSComparisonResult(NSString *a, NSString *b) { return Y(a) < Y(b) ? NSOrderedAscending : (Y(a) > Y(b) ? NSOrderedDescending : [a compare:b]); };
    NSMutableDictionary<NSString *, NSString *> *plan = [NSMutableDictionary dictionary];
    if (n == 3) {
        if (left.count == 1 && right.count == 2) { [right sortUsingComparator:byY]; plan[left[0]] = @"left"; plan[right[0]] = @"topright"; plan[right[1]] = @"bottomright"; }
        else if (left.count == 2 && right.count == 1) { [left sortUsingComparator:byY]; plan[right[0]] = @"right"; plan[left[0]] = @"topleft"; plan[left[1]] = @"bottomleft"; }
        else return nil;
        return plan;
    }
    if (left.count != 2 || right.count != 2) return nil;   // (four: two on each side)
    [left sortUsingComparator:byY]; [right sortUsingComparator:byY];
    if (fabs(Y(left[0]) - Y(left[1])) < 0.05 || fabs(Y(right[0]) - Y(right[1])) < 0.05) return nil;
    plan[left[0]] = @"topleft"; plan[left[1]] = @"bottomleft"; plan[right[0]] = @"topright"; plan[right[1]] = @"bottomright";
    return plan;
}
