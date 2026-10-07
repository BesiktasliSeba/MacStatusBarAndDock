// SMEngineAPI.h -- the Stage Manager engine's private SpringBoard API in ONE place: typed, checked wrappers + the start-up self-check (2026-09-29).
// Why: a user on an M2 iPad Pro with iPadOS 16.1-16.6 (never tested by us; everything was learned on 16.7.7) crashed SpringBoard on every tap with
// the Stage Manager engine (review plans/review-ipados16.0-crash-2026-09-29.md, S1-S7). Every private call the engine made was a raw objc_msgSend
// cast to the 16.7.7 types: a missing selector aborted SpringBoard, a changed struct or scalar was read as garbage. Now:
//  - every private call goes through a wrapper below: the receiver's class/selector is checked, and for a struct or scalar result or argument the
//    method's type encoding is compared with the C types we call it with (DMSMExpect: built from @encode of those same types), so a changed layout
//    on another iPadOS is refused instead of read; sizes, centers and times are checked for sense (finite, in range) both ways;
//  - a refusal goes through DMSMAPIFail (one log line per kind, a short record in the verdict);
//  - DMSMSelfCheck runs once at start (DMSMEngineInit, before anything of the engine runs): every class, selector and signature the engine and its
//    hooks need, then the hooks' installation. Anything missing or different: the SMEngine hooks are NOT installed, DMSMEngine() is NO (the default
//    engine runs), Stage Manager is not switched on, and the verdict is published in the preferences (common/StageManagerAvailable.h:
//    MSBDStageManagerVerdict) for the root helper (which engine loads) and Settings (the greyed row).
// Included once by StatusBar.x (after DMLog / DMCall / MSB_DOMAIN / DMTestFlag and the DMSMAttributedSize typedef).
#pragma once
#include <dlfcn.h>   // (dlsym: SpringBoard's exported layout-role functions and constants, iPadOS 17 check)
#include "SMRoles.h"   // (the window roles a stage has: DMSMPlanValid reads the highest, sm-nolimit)
#include "SMWindowKey.h"   // (one window, one key: its own scene -- M-2, sm-multiwin)

// ---- one place for refusals -------------------------------------------------------------------------------------------------------------------
static NSMutableOrderedSet<NSString *> *gSMAPIFailures;   // (each kind once: "<what>: <why>")
static BOOL gSMCheckOK = NO;          // (DMSelfCheck passed: the engine may run)
static BOOL gSMCheckDone = NO;
static NSString *gSMCheckReason;      // (why not, for the log and Settings)
static void DMSMRecordRuntimeFailure(NSString *line);
static void DMSM17DiagSoon(void);   // (iPadOS 17 layout engine only: the diagnostics record for Report a Problem, StatusBar.x)
static int DMSMLayoutGen(void);
static void DMSMAPIFail(NSString *what, NSString *why) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", what, why];
    if (!gSMAPIFailures) gSMAPIFailures = [NSMutableOrderedSet orderedSet];
    if ([gSMAPIFailures containsObject:line]) return;
    [gSMAPIFailures addObject:line];
    DMLog([NSString stringWithFormat:@"[smapi] REFUSED %@", line]);
    DMSMRecordRuntimeFailure(line);
    if (DMSMLayoutGen() == 17) DMSM17DiagSoon();
}

// ---- method signatures -------------------------------------------------------------------------------------------------------------------------
// A type encoding reduced to its shape: no frame offsets, struct names, quoted class names or qualifiers, a block ("@?") as an object. Apple's
// "{CGRect={CGPoint=dd}{CGSize=dd}}40@0:8d16" and ours built from @encode(CGRect), @encode(id), ... both become "{{dd}{dd}}@:d".
static NSString *DMSMNormEncoding(const char *e) {
    if (!e) return nil;
    NSMutableString *o = [NSMutableString string];
    for (const char *p = e; *p; p++) {
        char ch = *p;
        if (ch >= '0' && ch <= '9') continue;
        if (ch == 'r' || ch == 'n' || ch == 'N' || ch == 'o' || ch == 'O' || ch == 'R' || ch == 'V') continue;
        if (ch == '"') { p++; while (*p && *p != '"') p++; if (!*p) break; continue; }
        if (ch == '{' || ch == '(') {
            [o appendFormat:@"%c", ch];
            const char *q = p + 1;
            while (*q && *q != '=' && *q != '}' && *q != ')' && *q != '{') q++;
            if (*q == '=') p = q;
            continue;
        }
        if (ch == '?' && o.length && [o characterAtIndex:o.length - 1] == '@') continue;
        [o appendFormat:@"%c", ch];
    }
    return o;
}
// The signature we call a method with: return type, then the arguments after self and _cmd (NULL-terminated @encode strings).
static NSString *DMSMExpect(const char *ret, ...) {
    NSMutableString *s = [NSMutableString stringWithString:DMSMNormEncoding(ret) ?: @""];
    [s appendString:@"@:"];
    va_list ap; va_start(ap, ret);
    for (const char *a = va_arg(ap, const char *); a; a = va_arg(ap, const char *)) [s appendString:DMSMNormEncoding(a) ?: @""];
    va_end(ap);
    return s;
}
static NSString *DMSMSigOfMethod(Method m) { return m ? DMSMNormEncoding(method_getTypeEncoding(m)) : nil; }
// Does obj answer sel with exactly this signature? Cached per class and selector (a handful of pairs, main thread; elsewhere uncached).
typedef struct { Class cls; SEL sel; const void *want; BOOL ok; } DMSMSigCacheEntry;
static DMSMSigCacheEntry gSMSigCache[128];
static int gSMSigCacheN = 0;
static BOOL DMSMSigOK(id obj, SEL sel, NSString *want, const char *what) {
    if (!obj) return NO;
    Class c = object_getClass(obj);
    BOOL main = [NSThread isMainThread];
    if (main) for (int i = 0; i < gSMSigCacheN; i++) if (gSMSigCache[i].cls == c && gSMSigCache[i].sel == sel && gSMSigCache[i].want == (__bridge const void *)want) return gSMSigCache[i].ok;
    BOOL ok = NO; NSString *why = nil;
    Method m = class_getInstanceMethod(c, sel);
    if (!m || ![obj respondsToSelector:sel]) why = [NSString stringWithFormat:@"-[%@ %@] missing", NSStringFromClass(c), NSStringFromSelector(sel)];
    else if (want) {
        NSString *have = DMSMSigOfMethod(m);
        ok = [have isEqualToString:want];
        if (!ok) why = [NSString stringWithFormat:@"-[%@ %@] is %@, we call it as %@", NSStringFromClass(c), NSStringFromSelector(sel), have, want];
    } else ok = YES;
    if (main && gSMSigCacheN < (int)(sizeof(gSMSigCache) / sizeof(gSMSigCache[0]))) gSMSigCache[gSMSigCacheN++] = (DMSMSigCacheEntry){ c, sel, (__bridge const void *)want, ok };
    if (!ok) DMSMAPIFail(@(what), why);
    return ok;
}
// The signatures, made once (static strings: their identity is the cache key above).
#define DMSM_SIG(name, ...) static NSString *name(void) { static NSString *s; if (!s) s = DMSMExpect(__VA_ARGS__, NULL); return s; }
DMSM_SIG(DMSMSigTime, @encode(long long))                                              // -lastInteractionTime, -sizingPolicy, -layoutRoleForItem: (+arg)
DMSM_SIG(DMSMSigRole, @encode(long long), @encode(id))                                 // -[SBAppLayout layoutRoleForItem:]
DMSM_SIG(DMSMSigSize, @encode(DMSMAttributedSize))                                     // -attributedSize
DMSM_SIG(DMSMSigCenter, @encode(CGPoint))                                              // -normalizedCenter
DMSM_SIG(DMSMSigWithSize, @encode(id), @encode(DMSMAttributedSize))                    // -attributesByModifyingAttributedSize:
DMSM_SIG(DMSMSigWithCenter, @encode(id), @encode(CGPoint))                             // -attributesByModifyingNormalizedCenter:
DMSM_SIG(DMSMSigWithLong, @encode(id), @encode(long long))                             // -attributesByModifyingSizingPolicy: / LastInteractionTime: / -appLayoutByRemovingItemInLayoutRole:
DMSM_SIG(DMSMSigObj, @encode(id))                                                      // an object getter
DMSM_SIG(DMSMSigObjObj, @encode(id), @encode(id))                                      // an object from an object
DMSM_SIG(DMSMSigObjObjObj, @encode(id), @encode(id), @encode(id))                      // an object from two objects
DMSM_SIG(DMSMSigVoidObj, @encode(void), @encode(id))                                   // -requestTransitionWithBuilder:, -modifyApplicationContext:, ...
DMSM_SIG(DMSMSigVoidObjObj, @encode(void), @encode(id), @encode(id))                   // -setRequestedLayoutAttributes:forEntity:, -replaceAppLayout:withAppLayout:
DMSM_SIG(DMSMSigSetRole, @encode(void), @encode(id), @encode(long long))               // -setEntity:forLayoutRole:
DMSM_SIG(DMSMSigObjLong, @encode(id), @encode(long long))                              // -entityForLayoutRole:
DMSM_SIG(DMSMSigBool, @encode(BOOL))
DMSM_SIG(DMSMSigRect, @encode(CGRect))                                                 // -[SBSwitcherChamoisLayoutAttributes containerBounds]
DMSM_SIG(DMSMSigInBounds, @encode(CGSize), @encode(CGRect))                            // -sizeInBounds:, -centerInBounds: (16.0 / 16.1; {dd} either way)
DMSM_SIG(DMSMSigRequestOnDisplay, @encode(BOOL), @encode(unsigned long long), @encode(id), @encode(id))   // -requestTransitionWithOptions:displayConfiguration:builder: (YES = taken)
DMSM_SIG(DMSMSigRequest, @encode(BOOL), @encode(id))                                  // -requestTransitionWithBuilder: (YES = taken; B@:@? on 16.7.7)
DMSM_SIG(DMSMSigWithBool, @encode(id), @encode(BOOL))                                  // -attributesByModifyingPositionIsSystemManaged: (iPadOS 17+)

// ---- sense checks ------------------------------------------------------------------------------------------------------------------------------
static BOOL DMSMFinite(double v) { return isfinite(v); }
// A size read from Stage Manager: finite, not negative, a fraction of its reference rectangle (0 = "not set": DefaultHeight etc.).
static BOOL DMSMSizeReadSane(DMSMAttributedSize s) {
    return DMSMFinite(s.normalizedSize.width) && DMSMFinite(s.normalizedSize.height) && s.normalizedSize.width >= 0 && s.normalizedSize.height >= 0
        && s.normalizedSize.width <= 4.0 && s.normalizedSize.height <= 4.0
        && DMSMFinite(s.referenceBounds.origin.x) && DMSMFinite(s.referenceBounds.origin.y) && DMSMFinite(s.referenceBounds.size.width) && DMSMFinite(s.referenceBounds.size.height)
        && s.referenceBounds.size.width >= 0 && s.referenceBounds.size.height >= 0 && s.referenceBounds.size.width < 100000 && s.referenceBounds.size.height < 100000
        && s.type >= 0 && s.type <= 64;
}
// A size we hand to Stage Manager: all of the above, and a real window size (more than nothing, at most 1.5 of the screen) unless it is full width
// and height (type 3).
static BOOL DMSMSizeWriteSane(DMSMAttributedSize s) {
    if (!DMSMSizeReadSane(s)) return NO;
    if (s.type == 3) return YES;
    return s.normalizedSize.width > 0.001 && s.normalizedSize.height > 0.001 && s.normalizedSize.width <= 1.5 && s.normalizedSize.height <= 1.5;
}
static BOOL DMSMCenterSane(CGPoint c, BOOL write) {
    double lo = write ? -0.5 : -2.0, hi = write ? 1.5 : 3.0;
    return DMSMFinite(c.x) && DMSMFinite(c.y) && c.x >= lo && c.x <= hi && c.y >= lo && c.y <= hi;
}
static NSString *DMSMSizeText(DMSMAttributedSize s) {
    return [NSString stringWithFormat:@"%@ type %lld of %@", NSStringFromCGSize(s.normalizedSize), s.type, NSStringFromCGRect(s.referenceBounds)];
}

// ---- SBDisplayItemLayoutAttributes (a window's place, size, order) ------------------------------------------------------------------------------
static Class DMSMAttrClass(void) { static Class c; if (!c) c = objc_getClass("SBDisplayItemLayoutAttributes"); return c; }
static BOOL DMSMIsAttrs(id a) { Class c = DMSMAttrClass(); return a && c && [a isKindOfClass:c]; }
static BOOL DMSMAttrLong(id attrs, NSString *name, long long *out) {
    if (!DMSMIsAttrs(attrs)) return NO;
    SEL sel = NSSelectorFromString(name);
    if (!DMSMSigOK(attrs, sel, DMSMSigTime(), name.UTF8String)) return NO;
    long long v = ((long long (*)(id, SEL))objc_msgSend)(attrs, sel);
    if (out) *out = v;
    return YES;
}
// The window's place in the stage's order (Stage Manager: newest = in front).
static BOOL DMSMAttrLastInteractionTime(id attrs, long long *out) { return DMSMAttrLong(attrs, @"lastInteractionTime", out); }
static long long DMSMAttrTimeOr(id attrs, long long dflt) { long long t = dflt; return DMSMAttrLastInteractionTime(attrs, &t) ? t : dflt; }
// 0 snap-to-grid, 1 free, 2 maximized (full screen).
static BOOL DMSMAttrSizingPolicy(id attrs, long long *out) { return DMSMAttrLong(attrs, @"sizingPolicy", out); }
// ---- iPadOS 16.0 / 16.1: the "sized" window model (sm-160) ----
// There a window's attributes hold a plain size and centre (no attributed size, no reference rectangle): -sizeInBounds: / -centerInBounds: hand a
// value back as a FRACTION of the bounds asked for while both parts are small enough (16.0: up to 1; 16.1: up to 10 -- DMSMProbeSizedThreshold), else
// as POINTS (decompiled from 20A371 and 20B82). The engine keeps its one model (DMSMAttributedSize, fractions of a reference rectangle) and these
// wrappers translate: a value read in a 1 x 1 rectangle comes back as stored either way and is turned into fractions of the screen as it is now (the
// bounds Apple's layout reads it in); a value handed over is the fraction itself while both parts are at most 1 -- a fraction in either reading --
// else points (one part is then longer than the screen, never taken for a fraction). Which model the iPad has is the check's finding
// (DMSMVariantIs "window model"), never the version number.
static BOOL DMSMSizedModel(void);
static double DMSMSizedReadThreshold(void);
#if defined(__x86_64__)
#define DMSM_MSG_STRET objc_msgSend_stret   // (the Mac tests run on Intel: a struct over 16 bytes comes back through this entry point there; arm64 has one)
#else
#define DMSM_MSG_STRET objc_msgSend
#endif
static CGRect DMSMMainScreenBounds(void) {   // (looked up at run time: also builds where UIScreen is only a stand-in)
    Class c = objc_getClass("UIScreen");
    SEL ms = sel_registerName("mainScreen"), bs = sel_registerName("bounds");
    id scr = c && [c respondsToSelector:ms] ? ((id (*)(id, SEL))objc_msgSend)(c, ms) : nil;
    CGRect r = scr && [scr respondsToSelector:bs] ? ((CGRect (*)(id, SEL))DMSM_MSG_STRET)(scr, bs) : CGRectZero;
    return isfinite(r.size.width) && isfinite(r.size.height) && r.size.width >= 100.0 && r.size.height >= 100.0 ? r : CGRectZero;
}
static CGSize DMSMSizedFraction(CGSize raw, CGSize scr) {   // (a stored value -> a fraction of the screen)
    double t = MAX(1.0, DMSMSizedReadThreshold());
    return raw.width <= t && raw.height <= t ? raw : CGSizeMake(raw.width / scr.width, raw.height / scr.height);
}
static CGSize DMSMSizedValue(CGSize f, CGSize scr) {        // (a fraction of the screen -> the value to store)
    return f.width <= 1.0 && f.height <= 1.0 ? f : CGSizeMake(f.width * scr.width, f.height * scr.height);
}
// ---- Stage Manager switched back off after being the engine (1.3.4 logic test, the 11:58 abort) ----
// When the engine changes (or Mac Status Bar goes off) Stage Manager, on only for our engine, goes back off. SpringBoard's own reaction to that switch
// (-[SBFluidSwitcherViewController _chamoisWindowingUIEnabledDefaultChangeHandler], 16.7.7 disassembled): with an app in front it makes a transition
// that keeps the windows of roles 1-2 and empties 5-9, and its Dosido modifier looks the stage up among the switcher's app layouts (-visibleAppLayouts:
// -indexOfObject: of the from and to layouts, then -subarrayWithRange:) -- a stage of three windows is not among them, NSNotFound, NSRangeException,
// SpringBoard aborted (iPad 2, 4 Oct 11:58: engine set to Aerial, no respring, three Fit windows; our watcher switched Stage Manager off 10 s later;
// the same code since 1.1.x). With no app in front (Home Screen, App Library, App Switcher) the handler makes no transition. So the switch-off waits
// until no app is in front or the stage in front has one window, and every multi-window stage is cut back to its primary window first
// (DMSMFlattenStages), as the other switch-off already did afterwards. What DMStageManagerWatch does now, from what it sees (Mac test:
// tools/test-smcheck16.m): sinceSeen = seconds since Stage Manager was first seen not to be the engine (< 0: not yet seen), msbOff = Mac Status Bar
// switched off or removed (no 10 s start-up wait), smOn = Stage Manager is on, appInFront / frontWindows = an app in front and the windows of the
// iPad's stage in front.
enum { DMSMOffWait = 0, DMSMOffNow = 1, DMSMOffForget = 2 };   // (wait; cut back + switch off now; already off: only forget that it was ours)
static int DMSMEngineOffStep(double sinceSeen, BOOL msbOff, BOOL smOn, BOOL appInFront, NSUInteger frontWindows) {
    if (!msbOff && (sinceSeen < 0 || sinceSeen < 10.0)) return DMSMOffWait;   // (not during start-up, before the engine is known)
    if (!smOn) return DMSMOffForget;
    if (appInFront && frontWindows > 1) return DMSMOffWait;   // (SpringBoard's switch-off transition would have to drop windows: not now)
    return DMSMOffNow;
}
// SpringBoard's own handler of the switch (DMSMDefaultChangeHook, StatusBar.x) with our engine's ownership: 0 run Apple's handler, 1 wait (a switch-off
// that would drop windows: an app in front with more than one window), 2 nothing to switch (the setting is back as SpringBoard shows it).
// known = the switcher's state could be read; ours = Stage Manager's UI went on for our engine in this SpringBoard (DMSMOwnsStageUI).
enum { DMSMHandlerRun = 0, DMSMHandlerWait = 1, DMSMHandlerSkip = 2 };
static int DMSMHandlerStep(BOOL known, BOOL ours, BOOL settingOn, BOOL uiOn, BOOL appMode, NSUInteger windows) {
    if (!known || !ours) return DMSMHandlerRun;
    if (!settingOn && uiOn) return DMSMEngineOffStep(10, YES, YES, appMode, windows) == DMSMOffWait ? DMSMHandlerWait : DMSMHandlerRun;
    if (settingOn == uiOn) return DMSMHandlerSkip;
    return DMSMHandlerRun;
}
// Whose Stage Manager UI it is (1.3.4 re-check F1): SpringBoard runs its handler as a later main-queue block, after the new value is readable -- the
// watcher's 0.4 s tick can come in between and read the setting as off: then our engine counted as off (it needs the setting on) and the watcher had
// already dropped its ownership key, so the hook let Apple's handler run with three windows in front (the abort again, about 1 in 6 tries for an
// outside writer: Mac Status Bar switched off or removed, the engine changed and Stage Manager switched off). Ownership is a flag of this SpringBoard
// now: noted whenever the engine runs or the key says Stage Manager was on for it, and kept until the respring -- never hung on the watcher's latest
// reading of the setting that just changed. Keeping it longer costs nothing: it only lets a switch-off that would drop windows wait for a safe moment.
static BOOL gSMOwnsStageUI = NO;
static void DMSMNoteOwnStageUI(void) { gSMOwnsStageUI = YES; }
static BOOL DMSMOwnsStageUIWith(BOOL engineNow, BOOL keyPresent) {
    if (engineNow || keyPresent) gSMOwnsStageUI = YES;
    return gSMOwnsStageUI;
}
// ---- iPadOS 16.0: the group shift after the layout pass (sm-160 follow-up, 1.3.4 logic test) ----
// Right after its layout pass (-modelForPreferredModel:...), iPadOS 16.0's calculator (-[SBDisplayItemLayoutAttributesCalculator
// _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...], a block run through -modelByModifyingModelWithBlock:, decompiled from 20A371 / 20A5349b)
// moves the whole group of windows sideways: left-to-right by min(0, max(stage x, container centre - group width / 2) - group x), right-to-left by
// max(0, min(stage max x, container centre + group width / 2) - group max x), through -setBoundingBox: and every window's -setCenter:forItem:. With
// our full-width stage frame that pulls a group lying right of the centred place back to the middle (a lone window in the right half: 208 pt on an
// 11" iPad in portrait). 16.1+ has no such block. Our engine keeps windows where they are put: while that block runs (the calculator running, its
// pass over) a centre keeps its x and so does the bounding box. SMLayout160's hooks and SMLayout16's -setCenter:forItem: call these; the Mac test
// (tools/test-smcheck16.m) plays the calculator's decoded order on stand-ins.
static int gSMCalc160Depth = 0;     // (the 16.0 calculator's auto layout is running)
static BOOL gSMPostPass160 = NO;    // (... and its layout pass is over: what moves now is the group shift)
static void DMSMCalc160Enter(void) { gSMCalc160Depth++; gSMPostPass160 = NO; }
static void DMSMCalc160Exit(void) { if (gSMCalc160Depth > 0) gSMCalc160Depth--; gSMPostPass160 = NO; }
static void DMSMPass160Begin(void) { gSMPostPass160 = NO; }
static void DMSMPass160End(void) { gSMPostPass160 = gSMCalc160Depth > 0; }
// The x a centre or the bounding box gets: its own while the group shift runs and our engine places windows freely, else the one asked for.
static CGFloat DMSMShift160X(BOOL freePlacement, CGFloat asked, CGFloat own) { return gSMPostPass160 && freePlacement && isfinite(own) ? own : asked; }
static BOOL DMSMAttrAttributedSize(id attrs, DMSMAttributedSize *out) {
    if (!DMSMIsAttrs(attrs)) return NO;
    if (DMSMSizedModel()) {
        SEL get = NSSelectorFromString(@"sizeInBounds:");
        if (!DMSMSigOK(attrs, get, DMSMSigInBounds(), "sizeInBounds:")) return NO;
        CGRect scr = DMSMMainScreenBounds();
        if (CGRectIsEmpty(scr)) { DMSMAPIFail(@"sizeInBounds:", @"no screen to read it in"); return NO; }
        CGSize raw = ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(attrs, get, CGRectMake(0, 0, 1, 1));
        DMSMAttributedSize s = { DMSMSizedFraction(raw, scr.size), CGRectMake(0, 0, scr.size.width, scr.size.height), 0 };
        if (!DMSMSizeReadSane(s)) { DMSMAPIFail(@"sizeInBounds:", [@"not a size: " stringByAppendingString:DMSMSizeText(s)]); return NO; }
        if (out) *out = s;
        return YES;
    }
    SEL sel = NSSelectorFromString(@"attributedSize");
    if (!DMSMSigOK(attrs, sel, DMSMSigSize(), "attributedSize")) return NO;
    DMSMAttributedSize s = ((DMSMAttributedSize (*)(id, SEL))objc_msgSend)(attrs, sel);
    if (!DMSMSizeReadSane(s)) { DMSMAPIFail(@"attributedSize", [@"not a size: " stringByAppendingString:DMSMSizeText(s)]); return NO; }
    if (out) *out = s;
    return YES;
}
static BOOL DMSMAttrCenter(id attrs, CGPoint *out) {
    if (!DMSMIsAttrs(attrs)) return NO;
    if (DMSMSizedModel()) {
        SEL get = NSSelectorFromString(@"centerInBounds:");
        if (!DMSMSigOK(attrs, get, DMSMSigInBounds(), "centerInBounds:")) return NO;
        CGRect scr = DMSMMainScreenBounds();
        if (CGRectIsEmpty(scr)) { DMSMAPIFail(@"centerInBounds:", @"no screen to read it in"); return NO; }
        CGPoint raw = ((CGPoint (*)(id, SEL, CGRect))objc_msgSend)(attrs, get, CGRectMake(0, 0, 1, 1));
        CGSize f = DMSMSizedFraction(CGSizeMake(raw.x, raw.y), scr.size);
        CGPoint c = CGPointMake(f.width, f.height);
        if (!DMSMCenterSane(c, NO)) { DMSMAPIFail(@"centerInBounds:", [@"not a center: " stringByAppendingString:NSStringFromCGPoint(c)]); return NO; }
        if (out) *out = c;
        return YES;
    }
    SEL sel = NSSelectorFromString(@"normalizedCenter");
    if (!DMSMSigOK(attrs, sel, DMSMSigCenter(), "normalizedCenter")) return NO;
    CGPoint c = ((CGPoint (*)(id, SEL))objc_msgSend)(attrs, sel);
    if (!DMSMCenterSane(c, NO)) { DMSMAPIFail(@"normalizedCenter", [@"not a center: " stringByAppendingString:NSStringFromCGPoint(c)]); return NO; }
    if (out) *out = c;
    return YES;
}
// The attributesByModifying... family: a copy with one thing changed; nil (nothing changed anywhere) when refused.
static id DMSMAttrWithSize(id attrs, DMSMAttributedSize s) {
    if (!DMSMIsAttrs(attrs)) return nil;
    if (!DMSMSizeWriteSane(s)) { DMSMAPIFail(@"attributesByModifyingAttributedSize:", [@"refused to hand over " stringByAppendingString:DMSMSizeText(s)]); return nil; }
    if (DMSMSizedModel()) {   // (fractions of the screen as it is now: full width and height (type 3) = 1 x 1, a size of another reference rescaled)
        CGRect scr = DMSMMainScreenBounds();
        if (CGRectIsEmpty(scr)) { DMSMAPIFail(@"attributesByModifyingSize:", @"no screen to measure it in"); return nil; }
        CGSize f = s.normalizedSize;
        if (s.type == 3) f = CGSizeMake(1.0, 1.0);
        else if (s.referenceBounds.size.width > 0 && s.referenceBounds.size.height > 0)
            f = CGSizeMake(s.normalizedSize.width * s.referenceBounds.size.width / scr.size.width, s.normalizedSize.height * s.referenceBounds.size.height / scr.size.height);
        SEL put = NSSelectorFromString(@"attributesByModifyingSize:");
        if (!DMSMSigOK(attrs, put, DMSMSigWithCenter(), "attributesByModifyingSize:")) return nil;
        id r = ((id (*)(id, SEL, CGSize))objc_msgSend)(attrs, put, DMSMSizedValue(f, scr.size));
        return DMSMIsAttrs(r) ? r : nil;
    }
    SEL sel = NSSelectorFromString(@"attributesByModifyingAttributedSize:");
    if (!DMSMSigOK(attrs, sel, DMSMSigWithSize(), "attributesByModifyingAttributedSize:")) return nil;
    id r = ((id (*)(id, SEL, DMSMAttributedSize))objc_msgSend)(attrs, sel, s);
    return DMSMIsAttrs(r) ? r : nil;
}
static id DMSMAttrWithCenter(id attrs, CGPoint c) {
    if (!DMSMIsAttrs(attrs)) return nil;
    if (!DMSMCenterSane(c, YES)) { DMSMAPIFail(@"attributesByModifyingNormalizedCenter:", [@"refused to hand over " stringByAppendingString:NSStringFromCGPoint(c)]); return nil; }
    if (DMSMSizedModel()) {
        CGRect scr = DMSMMainScreenBounds();
        if (CGRectIsEmpty(scr)) { DMSMAPIFail(@"attributesByModifyingCenter:", @"no screen to measure it in"); return nil; }
        CGSize v = DMSMSizedValue(CGSizeMake(c.x, c.y), scr.size);
        SEL put = NSSelectorFromString(@"attributesByModifyingCenter:");
        if (!DMSMSigOK(attrs, put, DMSMSigWithCenter(), "attributesByModifyingCenter:")) return nil;
        id r = ((id (*)(id, SEL, CGPoint))objc_msgSend)(attrs, put, CGPointMake(v.width, v.height));
        return DMSMIsAttrs(r) ? r : nil;
    }
    SEL sel = NSSelectorFromString(@"attributesByModifyingNormalizedCenter:");
    if (!DMSMSigOK(attrs, sel, DMSMSigWithCenter(), "attributesByModifyingNormalizedCenter:")) return nil;
    id r = ((id (*)(id, SEL, CGPoint))objc_msgSend)(attrs, sel, c);
    return DMSMIsAttrs(r) ? r : nil;
}
static id DMSMAttrWithLong(id attrs, NSString *name, long long v, long long lo, long long hi) {
    if (!DMSMIsAttrs(attrs)) return nil;
    if (v < lo || v > hi) { DMSMAPIFail(name, [NSString stringWithFormat:@"refused to hand over %lld", v]); return nil; }
    SEL sel = NSSelectorFromString(name);
    if (!DMSMSigOK(attrs, sel, DMSMSigWithLong(), name.UTF8String)) return nil;
    id r = ((id (*)(id, SEL, long long))objc_msgSend)(attrs, sel, v);
    return DMSMIsAttrs(r) ? r : nil;
}
static id DMSMAttrWithSizingPolicy(id attrs, long long p) { return DMSMAttrWithLong(attrs, @"attributesByModifyingSizingPolicy:", p, 0, 8); }
static id DMSMAttrWithLastInteractionTime(id attrs, long long t) { return DMSMAttrWithLong(attrs, @"attributesByModifyingLastInteractionTime:", t, 0, LLONG_MAX / 2); }
// iPadOS 17+: who decides a window's place. A window Stage Manager opened at its default place is "system managed" (SBDisplayItemLayoutAttributes
// -isPositionSystemManaged, new in 17: ivar _positionIsSystemManaged in every 17.0-18.6 SpringBoard.tbd); a window the user dragged is not
// (-[SBContinuousExposeWindowDragDestinationSwitcherModifier ...] sets NO when a lone window is put down, 17.6.1). 17's auto-layout only moves
// system-managed windows on its own: it re-centres a lone one and, with the window set unchanged, folds them back towards the middle
// (-[SBContinuousExposeAutoLayoutController _performAutoLayoutWithSpace:...] / -spaceByPerformingAutoLayoutWithSpace:..., 17.6.1). Every window our
// engine places is a window the user placed, so it is handed over as such (DMSMAttrWith, DMSMSetWindowGeometry): Stage Manager itself then leaves
// it where it is -- the cause, not the effect (the SMLayout17 hooks stay for the windows Stage Manager places itself). Only on the 17 table.
static unsigned gSMPlacedByUser = 0;   // (how many attributes went out marked "placed by the user": the diagnostics record)
static BOOL DMSMAttrSystemManaged(id attrs, BOOL *out) {
    SEL sel = NSSelectorFromString(@"isPositionSystemManaged");
    if (!DMSMIsAttrs(attrs) || !DMSMSigOK(attrs, sel, DMSMSigBool(), "isPositionSystemManaged")) return NO;
    BOOL v = ((BOOL (*)(id, SEL))objc_msgSend)(attrs, sel);
    if (out) *out = v;
    return YES;
}
static id DMSMAttrWithSystemManaged(id attrs, BOOL managed) {
    SEL sel = NSSelectorFromString(@"attributesByModifyingPositionIsSystemManaged:");
    if (!DMSMIsAttrs(attrs) || !DMSMSigOK(attrs, sel, DMSMSigWithBool(), "attributesByModifyingPositionIsSystemManaged:")) return nil;
    id r = ((id (*)(id, SEL, BOOL))objc_msgSend)(attrs, sel, managed);
    return DMSMIsAttrs(r) ? r : nil;
}
// The window as placed by the user (17 table only; 16 has no such flag). Never fatal: refused, the attributes go out as they were.
static id DMSMAttrPlacedByUser(id attrs) {
    if (!attrs || DMSMLayoutGen() != 17) return attrs;
    BOOL managed = NO;
    if (DMSMAttrSystemManaged(attrs, &managed) && !managed) return attrs;   // (already the user's)
    id a = DMSMAttrWithSystemManaged(attrs, NO);
    if (!a) return attrs;
    if (gSMPlacedByUser < 100000) gSMPlacedByUser++;
    if (gSMPlacedByUser == 1 || gSMPlacedByUser == 50) DMSM17DiagSoon();   // (the diagnostics record says it happens)
    return a;
}
// New, empty attributes (a window with no earlier place).
static id DMSMAttrNew(void) {
    Class c = DMSMAttrClass();
    if (!c || ![c instancesRespondToSelector:@selector(init)]) return nil;
    id a = nil;
    @try { a = [[c alloc] init]; } @catch (NSException *e) { DMSMAPIFail(@"SBDisplayItemLayoutAttributes init", e.reason ?: @"exception"); a = nil; }
    return DMSMIsAttrs(a) ? a : nil;
}
// Size + center + policy (+ interaction time when >= 0) in one go: nil if any step is refused (never a half-changed copy).
static id DMSMAttrWith(id attrs, DMSMAttributedSize s, CGPoint c, long long policy, long long time) {
    id a = DMSMAttrWithSize(attrs, s);
    a = a ? DMSMAttrWithCenter(a, c) : nil;
    a = a ? DMSMAttrWithSizingPolicy(a, policy) : nil;
    if (a && time >= 0) a = DMSMAttrWithLastInteractionTime(a, time);
    return DMSMAttrPlacedByUser(a);   // (iPadOS 17+: placed by the user, Stage Manager keeps it there; 16: unchanged)
}

// ---- SBAppLayout (a stage), its items (SBDisplayItem), the switcher's list of stages ---------------------------------------------------------------
static id DMSMCoordinator(void) {
    Class c = objc_getClass("SBMainSwitcherControllerCoordinator");
    // (iPadOS 17+: only the coordinator that already exists -- +sharedInstance makes it when it is not there yet, and our hooks that read the stages
    //  run inside SpringBoard's switcher set-up: making it from in there is the recursive-singleton crash of the 18 audit (issue #1, Lock Screen
    //  manager). +sharedInstanceIfExists is on 17.0.3 and 18.2; not there yet = no stages, every caller handles nil. 16: unchanged.)
    if (c && DMSMLayoutGen() == 17 && [(id)c respondsToSelector:NSSelectorFromString(@"sharedInstanceIfExists")]) return DMCall(c, @"sharedInstanceIfExists");
    return c ? DMCall(c, @"sharedInstance") : nil;
}
static NSArray *DMSMRecentStages(void) {
    id l = DMCall(DMSMCoordinator(), @"recentAppLayouts");
    return [l isKindOfClass:[NSArray class]] ? l : nil;
}
static BOOL DMSMIsStage(id s) { Class c = objc_getClass("SBAppLayout"); return s && c && [s isKindOfClass:c]; }
// The stage's windows: item -> attributes (only pairs of the expected kinds).
static NSDictionary *DMSMStageItemsMap(id stage) {
    if (!DMSMIsStage(stage)) return nil;
    SEL sel = NSSelectorFromString(@"itemsToLayoutAttributesMap");
    if (!DMSMSigOK(stage, sel, DMSMSigObj(), "itemsToLayoutAttributesMap")) return nil;
    id m = ((id (*)(id, SEL))objc_msgSend)(stage, sel);
    if (![m isKindOfClass:[NSDictionary class]]) return nil;
    for (id k in m) if (!DMSMIsAttrs(((NSDictionary *)m)[k])) { DMSMAPIFail(@"itemsToLayoutAttributesMap", [NSString stringWithFormat:@"a value of class %@", NSStringFromClass([((NSDictionary *)m)[k] class])]); return nil; }
    return m;
}
static NSString *DMSMItemBundle(id item) {
    id b = DMCall(item, @"bundleIdentifier");
    return [b isKindOfClass:[NSString class]] ? b : nil;
}
// The window's own identifier: its scene's ("sceneID:<bundle>-<suffix>"; SMWindowKey.h). nil when it can't be read as expected.
static NSString *DMSMItemUid(id item) {
    SEL u = NSSelectorFromString(@"uniqueIdentifier");
    if (!item || ![item respondsToSelector:u] || !DMSMSigOK(item, u, DMSMSigObj(), "uniqueIdentifier")) return nil;
    id s = ((id (*)(id, SEL))objc_msgSend)(item, u);
    return [s isKindOfClass:[NSString class]] && [s length] ? s : nil;
}
// The window's layout role in its stage (1 primary, 2 side, 4 centre, 5-9 additional sides 0-4 -- read on 16.7.7; SMRoles.h).
static BOOL DMSMStageRoleOfItem(id stage, id item, long long *out) {
    if (!DMSMIsStage(stage) || !item) return NO;
    SEL sel = NSSelectorFromString(@"layoutRoleForItem:");
    if (!DMSMSigOK(stage, sel, DMSMSigRole(), "layoutRoleForItem:")) return NO;
    long long r = ((long long (*)(id, SEL, id))objc_msgSend)(stage, sel, item);
    if (r < 0 || r > 64) { DMSMAPIFail(@"layoutRoleForItem:", [NSString stringWithFormat:@"not a role: %lld", r]); return NO; }
    if (out) *out = r;
    return YES;
}
static id DMSMStageDisplayIdentity(id stage) { return DMSMIsStage(stage) ? DMCall(stage, @"preferredDisplayIdentity") : nil; }
static id DMSMStageWithAttrs(id stage, id attrs, id item) {
    if (!DMSMIsStage(stage) || !DMSMIsAttrs(attrs) || !item) return nil;
    SEL sel = NSSelectorFromString(@"appLayoutByModifyingLayoutAttributes:forItem:");
    if (!DMSMSigOK(stage, sel, DMSMSigObjObjObj(), "appLayoutByModifyingLayoutAttributes:forItem:")) return nil;
    id r = ((id (*)(id, SEL, id, id))objc_msgSend)(stage, sel, attrs, item);
    return DMSMIsStage(r) ? r : nil;
}
static id DMSMStageWithoutRole(id stage, long long role) {
    if (!DMSMIsStage(stage)) return nil;
    SEL sel = NSSelectorFromString(@"appLayoutByRemovingItemInLayoutRole:");
    if (!DMSMSigOK(stage, sel, DMSMSigWithLong(), "appLayoutByRemovingItemInLayoutRole:")) return nil;
    id r = ((id (*)(id, SEL, long long))objc_msgSend)(stage, sel, role);
    return DMSMIsStage(r) ? r : nil;
}
// The window in that role as a stage of its own: Apple's leaf app layout (that item with its attributes, configuration full, the stage's
// environment, hidden state and display). iPadOS 16.2 and 16.3 have no -appLayoutByRemovingItemInLayoutRole: (it came in 16.4); this gives the
// same single-window stage in one step (DMSMStageCutToPrimary).
static id DMSMStageLeaf(id stage, long long role) {
    if (!DMSMIsStage(stage)) return nil;
    SEL sel = NSSelectorFromString(@"leafAppLayoutForRole:");
    if (!DMSMSigOK(stage, sel, DMSMSigWithLong(), "leafAppLayoutForRole:")) return nil;
    id r = ((id (*)(id, SEL, long long))objc_msgSend)(stage, sel, role);
    return DMSMIsStage(r) ? r : nil;
}
// The switcher's model of stages, and a stage replaced in it (a window's attributes changed in place).
static id DMSMSwitcherModel(void) {
    id m = nil; @try { m = [DMSMCoordinator() valueForKey:@"_mainSwitcherModel"]; } @catch (id e) { m = nil; }
    return m;
}
// (StatusBar.x keeps the front window for one tick: told here whenever our code changes the stage model or asks for a transition)
static void (*gDMSMModelChanged)(void) = NULL;
static BOOL DMSMReplaceStage(id stage, id newStage) {
    if (gDMSMModelChanged) gDMSMModelChanged();
    id model = DMSMSwitcherModel();
    SEL sel = NSSelectorFromString(@"replaceAppLayout:withAppLayout:");
    if (!DMSMIsStage(stage) || !DMSMIsStage(newStage) || !DMSMSigOK(model, sel, DMSMSigVoidObjObj(), "replaceAppLayout:withAppLayout:")) return NO;
    @try { ((void (*)(id, SEL, id, id))objc_msgSend)(model, sel, stage, newStage); }
    @catch (NSException *e) { DMSMAPIFail(@"replaceAppLayout:withAppLayout:", e.reason ?: @"exception"); return NO; }
    return YES;
}

// ---- entities and workspace transitions (how a window is asked for) -----------------------------------------------------------------------------
static BOOL DMSMIsEntity(id e) { Class c = objc_getClass("SBDeviceApplicationSceneEntity"); return e && c && [e isKindOfClass:c]; }
static id DMSMApplication(NSString *bundle) {
    id ac = DMCall(objc_getClass("SBApplicationController"), @"sharedInstance");
    SEL sel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (!bundle.length || !DMSMSigOK(ac, sel, DMSMSigObjObj(), "applicationWithBundleIdentifier:")) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(ac, sel, bundle);
}
// An app entity for the iPad's own display, or for another display through its scene manager.
static id DMSMEntityNew(id app, id provider, id identity) {
    Class c = objc_getClass("SBDeviceApplicationSceneEntity");
    if (!c || !app) return nil;
    id e = nil;
    @try {
        if (provider && identity) {
            SEL init = NSSelectorFromString(@"initWithApplication:sceneHandleProvider:displayIdentity:");
            if ([c instancesRespondToSelector:init]) e = ((id (*)(id, SEL, id, id, id))objc_msgSend)([c alloc], init, app, provider, identity);
        } else {
            SEL init = NSSelectorFromString(@"initWithApplicationForMainDisplay:");
            if ([c instancesRespondToSelector:init] && [DMSMSigOfMethod(class_getInstanceMethod(c, init)) isEqualToString:DMSMSigObjObj()]) e = ((id (*)(id, SEL, id))objc_msgSend)([c alloc], init, app);
            else DMSMAPIFail(@"initWithApplicationForMainDisplay:", @"missing or another signature");
        }
    } @catch (NSException *x) { DMSMAPIFail(@"SBDeviceApplicationSceneEntity init", x.reason ?: @"exception"); e = nil; }
    return DMSMIsEntity(e) ? e : nil;
}
// A workspace entity's window: its scene's identifier (-[SBWorkspaceEntity uniqueIdentifier], the same string as its display item's). nil when none.
static NSString *DMSMEntityUid(id e) {
    SEL u = NSSelectorFromString(@"uniqueIdentifier");
    if (!e || ![e respondsToSelector:u] || !DMSMSigOK(e, u, DMSMSigObj(), "uniqueIdentifier")) return nil;
    id s = ((id (*)(id, SEL))objc_msgSend)(e, u);
    return [s isKindOfClass:[NSString class]] && [s length] ? s : nil;
}
static id DMSMEntityForItem(id item, id identity) {   // (Apple's own: the entity of that window on that display)
    id coord = DMSMCoordinator();
    SEL sel = NSSelectorFromString(@"_entityForDisplayItem:displayIdentity:");
    if (!item || ![coord respondsToSelector:sel] || !DMSMSigOK(coord, sel, DMSMSigObjObjObj(), "_entityForDisplayItem:displayIdentity:")) return nil;
    id e = nil;
    @try { e = ((id (*)(id, SEL, id, id))objc_msgSend)(coord, sel, item, identity); } @catch (NSException *x) { e = nil; }
    return DMSMIsEntity(e) ? e : nil;
}
// A transition context (SBWorkspaceApplicationSceneTransitionContext): what is in a role, and our writes.
static id DMSMCtxEntityForRole(id ctx, long long role, BOOL *ok) {
    SEL sel = NSSelectorFromString(@"entityForLayoutRole:");
    if (!DMSMSigOK(ctx, sel, DMSMSigObjLong(), "entityForLayoutRole:")) { if (ok) *ok = NO; return nil; }
    if (ok) *ok = YES;
    return ((id (*)(id, SEL, long long))objc_msgSend)(ctx, sel, role);
}
static BOOL DMSMCtxCanWrite(id ctx) {
    return DMSMSigOK(ctx, NSSelectorFromString(@"setEntity:forLayoutRole:"), DMSMSigSetRole(), "setEntity:forLayoutRole:")
        && DMSMSigOK(ctx, NSSelectorFromString(@"setRequestedLayoutAttributes:forEntity:"), DMSMSigVoidObjObj(), "setRequestedLayoutAttributes:forEntity:");
}
// The window a transition brings forward is also the stage's frontmost (keyboard focus): optional, set when Apple has it.
static void DMSMCtxMarkFrontmost(id ctx, id entity) {
    SEL sel = NSSelectorFromString(@"_setRequestedFrontmostEntity:");
    if (entity && [ctx respondsToSelector:sel] && DMSMSigOK(ctx, sel, DMSMSigVoidObj(), "_setRequestedFrontmostEntity:")) ((void (*)(id, SEL, id))objc_msgSend)(ctx, sel, entity);
}
// A PLAN = every window a transition names: @[entity, role, attributes] each. Checked as a whole BEFORE anything is written (review S2): entities of
// the entity class, roles in range and each used once, attributes of the attributes class with a sane size and center. Then written in one go;
// if a write throws anyway, the roles already written are emptied again, so Apple's context is left as it was (the roles we write into were empty
// or are rewritten by the same plan). allowed: the roles a NEW window may take (nil = any role up to the highest window role, at least 8 as before
// sm-nolimit: 1..9 on 16.7.7 -- for windows asked for again in their own).
#if DEBUG
static int gSMSimulateWriteFail = -1;   // (debug /tmp/msb-sm-simulate-writefail: the Nth write throws, to test the roll-back)
#endif
// A context our plan was written into is marked (and so is a request of ours by its "MSBD..." event label): the desktop join in its -finalize
// leaves those alone and takes every other context with roles set as SpringBoard's own (SMDesktop.h DMSMJoinStageAsked).
static char kSMOwnCtxKey;
static void DMSMCtxMarkOurs(id ctx) { if (ctx) objc_setAssociatedObject(ctx, &kSMOwnCtxKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL DMSMCtxIsOurs(id ctx) {
    if (!ctx) return NO;
    if (objc_getAssociatedObject(ctx, &kSMOwnCtxKey)) return YES;
    SEL rq = NSSelectorFromString(@"request"), lb = NSSelectorFromString(@"eventLabel");
    id req = [ctx respondsToSelector:rq] && DMSMSigOK(ctx, rq, DMSMSigObj(), "request") ? ((id (*)(id, SEL))objc_msgSend)(ctx, rq) : nil;
    id label = [req respondsToSelector:lb] && DMSMSigOK(req, lb, DMSMSigObj(), "eventLabel") ? ((id (*)(id, SEL))objc_msgSend)(req, lb) : nil;
    return [label isKindOfClass:[NSString class]] && [label hasPrefix:@"MSBD"];
}
// (M-2: also each WINDOW once -- two entities of one scene are one window in two roles, the layout state SpringBoard's orientation check aborts on
//  as "out of sync", 1.3.6's crash class; the engine named the app's default scene for each of an app's windows)
static BOOL DMSMPlanValid(NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, NSString **why) {
    NSMutableSet *roles = [NSMutableSet set], *entities = [NSMutableSet set], *windows = [NSMutableSet set];
    if (!plan.count) { if (why) *why = @"empty plan"; return NO; }
    for (NSArray *en in plan) {
        if (![en isKindOfClass:[NSArray class]] || en.count != 3) { if (why) *why = @"malformed entry"; return NO; }
        id e = en[0]; long long role = [en[1] longLongValue]; id a = en[2];
        if (!DMSMIsEntity(e)) { if (why) *why = [NSString stringWithFormat:@"not an app entity: %@", NSStringFromClass([e class])]; return NO; }
        if (role < 1 || role > MAX(8LL, DMSMRoleTop()) || (allowed && ![allowed containsObject:@(role)])) { if (why) *why = [NSString stringWithFormat:@"role %lld not allowed", role]; return NO; }
        if ([roles containsObject:@(role)]) { if (why) *why = [NSString stringWithFormat:@"role %lld twice", role]; return NO; }
        if ([entities containsObject:[NSValue valueWithNonretainedObject:e]]) { if (why) *why = @"one entity twice"; return NO; }
        [roles addObject:@(role)]; [entities addObject:[NSValue valueWithNonretainedObject:e]];
        NSString *w = DMSMEntityUid(e);
        if (w && [windows containsObject:w]) { if (why) *why = [NSString stringWithFormat:@"one window twice (%@)", w]; return NO; }
        if (w) [windows addObject:w];
        if (!DMSMIsAttrs(a)) { if (why) *why = [NSString stringWithFormat:@"not attributes: %@", NSStringFromClass([a class])]; return NO; }
        DMSMAttributedSize s; CGPoint c; long long t = 0, p = 0;
        if (!DMSMAttrAttributedSize(a, &s) || !DMSMAttrCenter(a, &c) || !DMSMAttrLastInteractionTime(a, &t) || !DMSMAttrSizingPolicy(a, &p)) { if (why) *why = @"attributes unreadable"; return NO; }
    }
    return YES;
}
static BOOL DMSMWritePlan(id ctx, NSArray<NSArray *> *plan, id frontEntity) {
    if (!DMSMCtxCanWrite(ctx)) return NO;
    SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:"), setA = NSSelectorFromString(@"setRequestedLayoutAttributes:forEntity:");
    NSMutableArray<NSNumber *> *written = [NSMutableArray array];
    @try {
        int n = 0;
        for (NSArray *en in plan) {
#if DEBUG
            if (gSMSimulateWriteFail >= 0 && n++ == gSMSimulateWriteFail) [NSException raise:@"DMSMSimulated" format:@"simulated write failure (debug)"];
#else
            (void)n;
#endif
            [written addObject:en[1]];
            ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, en[0], [en[1] longLongValue]);
            ((void (*)(id, SEL, id, id))objc_msgSend)(ctx, setA, en[2], en[0]);
        }
        DMSMCtxMarkOurs(ctx);   // (our plan: the desktop join leaves this context alone)
        if (frontEntity) DMSMCtxMarkFrontmost(ctx, frontEntity);
    } @catch (NSException *x) {
        for (NSNumber *r in written) @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, nil, r.longLongValue); } @catch (id y) {}
        DMSMAPIFail(@"transition plan", [NSString stringWithFormat:@"a write failed (%@): %lu role(s) emptied again", x.reason, (unsigned long)written.count]);
        return NO;
    }
    return YES;
}
// A workspace transition on a display (the iPad: nil identity) that names the plan's windows. YES when SpringBoard took the request. The plan is
// checked before the request is made: a refused plan asks for nothing (no half request).
// A plan that names a WHOLE stage (a Mac Switcher desktop: whole = YES). A role a transition's context leaves unset means "as it was": Stage Manager
// lays the requested windows over the stage on screen (and over the launched app's own stage) and keeps the windows in every other role -- a
// desktop asked for from a fuller one took the extra windows along (iPad 2, 3 Oct: Tips and Books went with Desktop 2, then back, each switch;
// emptying the context's roles with nil did nothing: they were already unset). SpringBoard empties a role with an SBEmptyWorkspaceEntity (+entity,
// read on 16.7.7), so every window role the plan does not name gets one (the side role 2, the centre role 4 and every additional side SpringBoard
// has -- 5 to 9 on 16.7.7 since 1.3.6's seven windows per desktop (SMRoles.h): with only 2 4 5 6 emptied, a desktop asked for from one of seven
// kept the left desktop's windows of roles 7-9; role 1 is always in a plan; role 3, the floating app, is not a window of a stage and stays). The
// engine's own requests add to the stage on screen and rely on the kept roles: whole = NO. (An emptied role whose window in the stage on screen the
// same plan names in another role takes that window out of the new stage: iPad 2, 4 Oct -- see DMMSWSMPlan.)
static id DMSMEmptyEntity(void) {
    Class c = objc_getClass("SBEmptyWorkspaceEntity");
    SEL s = NSSelectorFromString(@"entity");
    if (!c || ![c respondsToSelector:s] || !DMSMSigOK(c, s, DMSMSigObj(), "+entity")) return nil;
    id e = nil;
    @try { e = ((id (*)(id, SEL))objc_msgSend)(c, s); } @catch (NSException *x) { e = nil; }
    return [e isKindOfClass:c] ? e : nil;
}
static void DMSMCtxClearOtherRoles(id ctx, NSArray<NSArray *> *plan) {
    NSMutableSet *mine = [NSMutableSet set];
    for (NSArray *en in plan) [mine addObject:@([en[1] longLongValue])];
    SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
    if (!DMSMCtxCanWrite(ctx)) return;
    NSMutableArray *cleared = [NSMutableArray array];
    // (SpringBoard's own window roles when they were read -- also after the engine's table fell back to four, while a desktop of seven may still be
    //  on screen, as the role repair reads them -- else the engine's table; with the centre role 4)
    size_t nRoles = 0;
    const long long *list = DMSMRepairRoleList(&nRoles);
    NSMutableArray<NSNumber *> *roles = [NSMutableArray arrayWithObject:@4];
    for (size_t i = 0; i < nRoles; i++) if (list[i] != 1 && ![roles containsObject:@(list[i])]) [roles addObject:@(list[i])];
    [roles sortUsingSelector:@selector(compare:)];
    for (NSNumber *r in roles) {
        if ([mine containsObject:r]) continue;
        id empty = DMSMEmptyEntity();
        if (!empty) { DMSMAPIFail(@"SBEmptyWorkspaceEntity +entity", @"missing: the roles a whole stage does not name keep their windows"); return; }
        @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, empty, r.longLongValue); [cleared addObject:r]; }
        @catch (NSException *x) { DMSMAPIFail(@"setEntity:<empty> forLayoutRole:", x.reason ?: @"exception"); return; }
    }
    if (cleared.count && DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smapi] whole stage: roles %@ set empty", [cleared componentsJoinedByString:@", "]]);
}
static BOOL DMSMRequestPlan(id identity, BOOL onMain, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity, BOOL whole) {
    if (gDMSMModelChanged) gDMSMModelChanged();
    NSString *why = nil;
    if (!DMSMPlanValid(plan, allowed, &why)) { DMSMAPIFail(@"transition plan", [NSString stringWithFormat:@"%@ refused before asking: %@", label, why]); return NO; }
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    __block BOOL wrote = NO, built = NO;
    void (^builder)(id) = ^(id req) {
        built = YES;
        SEL lab = NSSelectorFromString(@"setEventLabel:");
        // (always a label of ours: the desktop join recognises our own transitions by it when the context mark does not reach SpringBoard's final
        //  context -- unlabelled Fit requests showed up there as "no label", 1.3.5 logic test L3)
        NSString *ourLabel = label.length ? label : @"MSBDRequest";
        if ([req respondsToSelector:lab] && DMSMSigOK(req, lab, DMSMSigVoidObj(), "setEventLabel:")) ((void (*)(id, SEL, id))objc_msgSend)(req, lab, ourLabel);
        SEL mod = NSSelectorFromString(@"modifyApplicationContext:");
        if (!DMSMSigOK(req, mod, DMSMSigVoidObj(), "modifyApplicationContext:")) return;
        ((void (*)(id, SEL, id))objc_msgSend)(req, mod, ^(id ctx) { @try { wrote = DMSMWritePlan(ctx, plan, frontEntity); if (wrote && whole) DMSMCtxClearOtherRoles(ctx, plan); } @catch (id e) {} });
    };
    @try {
        if (!onMain) {
            id cfg = nil;
            for (UIScreen *sc in [UIScreen screens]) {
                id c = [sc respondsToSelector:NSSelectorFromString(@"displayConfiguration")] ? DMCall(sc, @"displayConfiguration") : nil;
                if (c && [DMCall(c, @"identity") isEqual:identity]) cfg = c;
            }
            SEL sel = NSSelectorFromString(@"requestTransitionWithOptions:displayConfiguration:builder:");
            if (cfg && [ws respondsToSelector:sel] && DMSMSigOK(ws, sel, DMSMSigRequestOnDisplay(), "requestTransitionWithOptions:displayConfiguration:builder:")) {
                BOOL taken = ((BOOL (*)(id, SEL, unsigned long long, id, id))objc_msgSend)(ws, sel, 0ULL, cfg, builder);
                if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smapi] %@ (display): taken %d, builder ran %d, plan written %d", label ?: @"request", taken, built, wrote]);
                return built ? wrote : YES;
            }
        }
        SEL sel = NSSelectorFromString(@"requestTransitionWithBuilder:");
        if (!DMSMSigOK(ws, sel, DMSMSigRequest(), "requestTransitionWithBuilder:")) return NO;
        BOOL taken = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, sel, builder);
        if (!taken) DMLog([NSString stringWithFormat:@"[smapi] %@: the workspace did not take the request", label ?: @"request"]);
        if (DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[smapi] %@: taken %d, builder ran %d, plan written %d", label ?: @"request", taken, built, wrote]);
        return built ? wrote : YES;   // (the answer is logged only: what NO means was not studied, and the builder normally runs inside the request; if SpringBoard runs it later, the plan was checked already)
    } @catch (NSException *e) { DMSMAPIFail(@"requestTransitionWithBuilder:", [NSString stringWithFormat:@"%@: %@", label, e.reason]); return NO; }
}

// ---- the start-up self-check ---------------------------------------------------------------------------------------------------------------------
// One row per class / method the engine needs: the signature we call it with (nil = only that it exists; hooks: the signature our hook is written
// for -- a hook of a method whose arguments changed would pass garbage on even to %orig). Keep in step with %group SMEngine and the wrappers above.
// alt: another name the same method has on some iPadOS (hooked under whichever exists); layout: 0 = both layout engines, 16 = only with iPadOS 16's
// SBChamoisOverlappingController, 17 = only with iPadOS 17's SBContinuousExposeAutoLayoutController (DMSMLayoutGen).
// need: core (every row that does not say otherwise) = missing or different keeps the engine off; optional = only `feature` depends on it, the
// engine runs without it -- rows with the same feature are alternatives (one is enough; the code asks DMSMRowPassed which one to use), and a
// missing optional row is logged once and listed in the verdict ("optional") and in Report a Problem. ivar: the row is an instance variable
// (sel = its name) whose type encoding must start with this.
// variant: "<group>/<name>" -- the same job done by another set of methods on other iPadOS versions (sm-160: iPadOS 16.0 and 16.1 keep a window's
// size and centre as plain values, and 16.0 has its own layout pass and size grid). A group is there when ALL rows of one of its variants are; the
// first variant in table order that is there is the one used (the one built and tested on 16.7.7 comes first, so 16.2+ always use it), the others
// are adapters. No variant there = the first variant's rows are the core problems. The code asks DMSMVariantIs which variant the check chose --
// never the iPadOS version; and only the chosen variant's hooks are installed and checked to have gone in.
enum { DMSMNeedCore = 0, DMSMNeedOptional = 1 };
typedef struct { const char *cls; const char *sel; BOOL classMethod; BOOL hooked; NSString *(*sig)(void); const char *alt; int layout; int need; const char *feature; const char *ivar; const char *variant; } DMSMNeed;
DMSM_SIG(DMSMSigVoid, @encode(void))
DMSM_SIG(DMSMSigDouble, @encode(double))
DMSM_SIG(DMSMSigVoidBool, @encode(void), @encode(BOOL))
DMSM_SIG(DMSMSigVoidDouble, @encode(void), @encode(double))
DMSM_SIG(DMSMSigVoidULL, @encode(void), @encode(unsigned long long))
DMSM_SIG(DMSMSigULL, @encode(unsigned long long))
DMSM_SIG(DMSMSigStageArea, @encode(CGRect), @encode(id), @encode(id), @encode(double), @encode(CGRect), @encode(BOOL), @encode(BOOL), @encode(double))
DMSM_SIG(DMSMSigAutoLayout, @encode(id), @encode(id), @encode(id), @encode(id), @encode(id), @encode(double), @encode(CGRect), @encode(double), @encode(BOOL), @encode(BOOL), @encode(UIEdgeInsets))
DMSM_SIG(DMSMSigVoid3, @encode(void), @encode(id), @encode(id), @encode(id))
DMSM_SIG(DMSMSigExpandH, @encode(void), @encode(id), @encode(id), @encode(id), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigExpandV, @encode(void), @encode(id), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigCenterH, @encode(void), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigCenterV, @encode(void), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigDodge, @encode(void), @encode(id), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigSetCenter, @encode(void), @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigCenterFor, @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigSizeFor, @encode(CGSize), @encode(id))                                     // -[SBChamoisOverlappingModel sizeForItem:] (optional edge rule, DMSMHookConstrain16)
DMSM_SIG(DMSMSigPointInside, @encode(BOOL), @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigHitTest, @encode(id), @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigGridSize, @encode(CGSize), @encode(CGSize), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigStripHidden, @encode(BOOL), @encode(id), @encode(long long))
// (iPadOS 16.0 / 16.1, from their dyld_shared_caches: 20A371 and 20A5349b for 16.0, 20B82 for 16.1 -- sm-160)
DMSM_SIG(DMSMSigInitialStageFrame, @encode(CGRect), @encode(id), @encode(long long), @encode(id), @encode(double), @encode(double), @encode(CGRect), @encode(BOOL), @encode(BOOL))
DMSM_SIG(DMSMSigPreferredModel, @encode(id), @encode(id), @encode(CGRect), @encode(id), @encode(id), @encode(id))   // -modelForPreferredModel:initialStageFrame:...
DMSM_SIG(DMSMSigVoid5, @encode(void), @encode(id), @encode(id), @encode(id), @encode(id), @encode(id))
DMSM_SIG(DMSMSigGridObject, @encode(CGSize), @encode(CGSize), @encode(CGRect), @encode(long long), @encode(id), @encode(double), @encode(id))   // -[SBDisplayItemLayoutGrid nearestGridSizeForProposedSize:...]
DMSM_SIG(DMSMSigMinGrid, @encode(CGSize), @encode(CGRect), @encode(long long), @encode(id), @encode(double), @encode(id))   // -[SBDisplayItemLayoutGrid minGridSizeForBounds:...]
DMSM_SIG(DMSMSigAutoLayoutIfNeeded, @encode(id), @encode(id), @encode(long long), @encode(id), @encode(double), @encode(double), @encode(id), @encode(id), @encode(CGRect), @encode(BOOL), @encode(BOOL))   // -[SBDisplayItemLayoutAttributesCalculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...]
DMSM_SIG(DMSMSigVoidRect, @encode(void), @encode(CGRect))                              // -[SBChamoisOverlappingModel setBoundingBox:]
// (iPadOS 17 layout engine, SBContinuousExposeAutoLayout*: signatures as in the 17.0.3 runtime headers, MTACS/iOS-17-Runtime-Headers)
DMSM_SIG(DMSMSigCGSize, @encode(CGSize))                                                                 // -[SBContinuousExposeAutoLayoutItem size]
DMSM_SIG(DMSMSigVoidPoint, @encode(void), @encode(CGPoint))                                              // -setPosition:
DMSM_SIG(DMSMSigStageArea17, @encode(CGRect), @encode(id), @encode(id))                                  // -stageAreaForSpace:configuration:
DMSM_SIG(DMSMSigAutoLayout17, @encode(id), @encode(id), @encode(id), @encode(id), @encode(unsigned long long))   // -spaceByPerformingAutoLayoutWithSpace:previousSpace:configuration:options:
DMSM_SIG(DMSMSigPerform17, @encode(CGRect), @encode(id), @encode(id), @encode(UIEdgeInsets))             // -_performAutoLayoutWithSpace:configuration:stageInset:
DMSM_SIG(DMSMSigSnap17, @encode(void), @encode(id), @encode(CGRect), @encode(id))                        // -snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:
// (sm-free: the Home rule and the Home gesture)
DMSM_SIG(DMSMSigVoidLong, @encode(void), @encode(long long))                                             // -setRequestedUnlockedEnvironmentMode:
// (1.3.9: the windows keep still during a Home gesture with Reduce Motion off)
DMSM_SIG(DMSMSigRectIndex, @encode(CGRect), @encode(unsigned long long))                                 // -[SBHomeGestureSwitcherModifier frameForIndex:]
DMSM_SIG(DMSMSigDoubleIndex, @encode(double), @encode(unsigned long long))                               // -scaleForIndex:
DMSM_SIG(DMSMSigBoolIndex, @encode(BOOL), @encode(unsigned long long))                                   // -_isSelectedAppLayoutAtIndex:
static const DMSMNeed kSMNeeds[] = {
    // the stage model: a window's attributes, the stage, its items
    {"SBDisplayItemLayoutAttributes", "init", NO, NO, NULL},
    {"SBDisplayItemLayoutAttributes", "lastInteractionTime", NO, NO, DMSMSigTime},
    {"SBDisplayItemLayoutAttributes", "sizingPolicy", NO, NO, DMSMSigTime},
    {"SBDisplayItemLayoutAttributes", "attributedSize", NO, NO, DMSMSigSize, NULL, 0, 0, NULL, NULL, "window model/attributed"},
    {"SBDisplayItemLayoutAttributes", "normalizedCenter", NO, NO, DMSMSigCenter, NULL, 0, 0, NULL, NULL, "window model/attributed"},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingAttributedSize:", NO, NO, DMSMSigWithSize, NULL, 0, 0, NULL, NULL, "window model/attributed"},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingNormalizedCenter:", NO, NO, DMSMSigWithCenter, NULL, 0, 0, NULL, NULL, "window model/attributed"},
    // (iPadOS 16.0 / 16.1: a plain size and centre, each a fraction of the bounds it is read in when small enough, else points -- DMSMAttr*)
    {"SBDisplayItemLayoutAttributes", "sizeInBounds:", NO, NO, DMSMSigInBounds, NULL, 0, 0, NULL, NULL, "window model/sized"},
    {"SBDisplayItemLayoutAttributes", "centerInBounds:", NO, NO, DMSMSigInBounds, NULL, 0, 0, NULL, NULL, "window model/sized"},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingSize:", NO, NO, DMSMSigWithCenter, NULL, 0, 0, NULL, NULL, "window model/sized"},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingCenter:", NO, NO, DMSMSigWithCenter, NULL, 0, 0, NULL, NULL, "window model/sized"},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingSizingPolicy:", NO, NO, DMSMSigWithLong},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingLastInteractionTime:", NO, NO, DMSMSigWithLong},
    {"SBAppLayout", "itemsToLayoutAttributesMap", NO, NO, DMSMSigObj},
    {"SBAppLayout", "layoutRoleForItem:", NO, NO, DMSMSigRole},
    {"SBAppLayout", "preferredDisplayIdentity", NO, NO, DMSMSigObj},
    {"SBAppLayout", "appLayoutByModifyingLayoutAttributes:forItem:", NO, NO, DMSMSigObjObjObj},
    // (leaving Stage Manager, a stage of several windows is cut back to its primary window: 16.4+ removes the others, 16.2-16.3 take the leaf)
    {"SBAppLayout", "appLayoutByRemovingItemInLayoutRole:", NO, NO, DMSMSigWithLong, NULL, 0, DMSMNeedOptional, "multi-window stages cut back when another engine takes over"},
    {"SBAppLayout", "leafAppLayoutForRole:", NO, NO, DMSMSigWithLong, NULL, 0, DMSMNeedOptional, "multi-window stages cut back when another engine takes over"},
    {"SBDisplayItem", "bundleIdentifier", NO, NO, DMSMSigObj},
    {"SBMainSwitcherControllerCoordinator", "sharedInstance", YES, NO, NULL},
    {"SBMainSwitcherControllerCoordinator", "recentAppLayouts", NO, NO, DMSMSigObj},
    {"SBAppSwitcherModel", "replaceAppLayout:withAppLayout:", NO, NO, DMSMSigVoidObjObj},
    // asking for windows: the workspace transition every launch uses
    {"SBMainWorkspace", "sharedInstance", YES, NO, NULL},
    {"SBMainWorkspace", "requestTransitionWithBuilder:", NO, NO, DMSMSigRequest},
    {"SBMainWorkspaceTransitionRequest", "modifyApplicationContext:", NO, NO, DMSMSigVoidObj},
    {"SBWorkspaceApplicationSceneTransitionContext", "setEntity:forLayoutRole:", NO, NO, DMSMSigSetRole},
    {"SBWorkspaceApplicationSceneTransitionContext", "setRequestedLayoutAttributes:forEntity:", NO, NO, DMSMSigVoidObjObj},
    {"SBWorkspaceApplicationSceneTransitionContext", "entityForLayoutRole:", NO, NO, DMSMSigObjLong},
    {"SBWorkspaceApplicationSceneTransitionContext", "activatingEntity", NO, NO, DMSMSigObj},
    {"SBWorkspaceApplicationSceneTransitionContext", "displayIdentity", NO, NO, DMSMSigObj},
    {"SBDeviceApplicationSceneEntity", "initWithApplicationForMainDisplay:", NO, NO, DMSMSigObjObj},
    {"SBDeviceApplicationSceneEntity", "application", NO, NO, DMSMSigObj},
    {"SBApplicationController", "sharedInstance", YES, NO, NULL},
    {"SBApplicationController", "applicationWithBundleIdentifier:", NO, NO, DMSMSigObjObj},
    // (the size grid's and the caps' container: read from this ivar, never through -containerBounds, issue #2 -- without it the largest screen,
    //  DMSMContainerBoundsOf in StatusBar.x; the -containerBounds row checked a method the engine stopped calling in 1.1.6)
    {"SBSwitcherChamoisLayoutAttributes", "_containerBounds", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "window size caps from the stage's own container (else the largest screen)", "{CGRect="},
    {"SBMutableChamoisOverlappingModel", "centerForItem:", NO, NO, DMSMSigCenterFor, NULL, 16},
    {"SBTopAffordanceViewController", "closeAction", NO, NO, DMSMSigObj},
    {"SBTopAffordanceViewController", "removeFromSetAction", NO, NO, DMSMSigObj},
    // (sm-free: the windows stay on screen at Home -- SMHome.h rewrites SpringBoard's Home transition into the desktop's windows. Every row is needed,
    //  so each has its own feature name: rows of one feature name are alternatives to the check. All 15 16.x builds have them, the 17.0.3 headers too.)
    {"SBWorkspaceApplicationSceneTransitionContext", "setActivatingEntity:", NO, NO, DMSMSigVoidObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (the context's front app)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "requestedUnlockedEnvironmentMode", NO, NO, DMSMSigTime, NULL, 0, DMSMNeedOptional, "windows stay at Home (the mode asked for)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "setRequestedUnlockedEnvironmentMode:", NO, NO, DMSMSigVoidLong, NULL, 0, DMSMNeedOptional, "windows stay at Home (asking for the windows)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "previousLayoutState", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (where Home starts)"},
    {"SBMainDisplayLayoutState", "unlockedEnvironmentMode", NO, NO, DMSMSigTime, NULL, 0, DMSMNeedOptional, "windows stay at Home (what is on screen)"},
    {"SBMainDisplayLayoutState", "appLayout", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (the stage on screen)"},
    {"SBWorkspaceEntity", "isHomeScreenEntity", NO, NO, DMSMSigBool, NULL, 0, DMSMNeedOptional, "windows stay at Home (the Home Screen asked for)"},
    {"SBEmptyWorkspaceEntity", "entity", YES, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (an emptied role)"},
    {"SBMainSwitcherControllerCoordinator", "_entityForDisplayItem:displayIdentity:", NO, NO, DMSMSigObjObjObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (each window's own scene)"},
    {"SBDisplayItem", "uniqueIdentifier", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (each window's identifier)"},
    // (1.3.8 logic test fixes: where SpringBoard went -- the App Switcher's bookkeeping; a real Home of our own; the gates the rule reads)
    {"SBWorkspaceApplicationSceneTransitionContext", "layoutState", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (where SpringBoard went)"},
    {"SBHomeScreenEntity", "entity", YES, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (a real Home of our own)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "request", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (whose transition it is)"},
    {"SBWorkspaceTransitionRequest", "eventLabel", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (our own transitions' label)"},
    {"SBWorkspaceTransitionRequest", "setEventLabel:", NO, NO, DMSMSigVoidObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (labelling our real Home)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "isBackground", NO, NO, DMSMSigBool, NULL, 0, DMSMNeedOptional, "windows stay at Home (a background activation)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "entitiesWithRemovalContexts", NO, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (a window being closed)"},
    {"SBWorkspaceApplicationSceneTransitionContext", "_setRequestedFrontmostEntity:", NO, NO, DMSMSigVoidObj, NULL, 0, DMSMNeedOptional, "windows stay at Home (the front window)"},
    // (... the Home Screen's own Home press for a person already on the Home Screen behind the windows: close a folder, the App Library, jiggle mode)
    {"SBIconController", "sharedInstance", YES, NO, DMSMSigObj, NULL, 0, DMSMNeedOptional, "the Home Screen's own Home press under the windows"},
    {"SBIconController", "handleHomeButtonTap", NO, NO, DMSMSigVoid, NULL, 0, DMSMNeedOptional, "the Home Screen's own Home press under the windows (its action)"},
    // (... and the Home Screen keeps its look behind the windows during a Home gesture: SpringBoard's gesture blurs it as if an app had covered it)
    {"SBHomeGestureSwitcherModifier", "homeScreenBackdropBlurType", NO, NO, DMSMSigTime, NULL, 0, DMSMNeedOptional, "the Home Screen stays sharp under a Home gesture (blur kind)"},
    {"SBHomeGestureSwitcherModifier", "homeScreenBackdropBlurProgress", NO, NO, DMSMSigDouble, NULL, 0, DMSMNeedOptional, "the Home Screen stays sharp under a Home gesture (blur amount)"},
    {"SBHomeGestureSwitcherModifier", "_startingEnvironmentMode", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "the Home Screen stays sharp under a Home gesture (where it starts)", "q"},
    {"SBReduceMotionHomeGestureSwitcherModifier", "homeScreenBackdropBlurType", NO, NO, DMSMSigTime, NULL, 0, DMSMNeedOptional, "the Home Screen stays sharp under a Home gesture (Reduce Motion's blur kind)"},
    {"SBReduceMotionHomeGestureSwitcherModifier", "_startingEnvironmentMode", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "the Home Screen stays sharp under a Home gesture (Reduce Motion's start)", "q"},
    // (... and, with Reduce Motion off, the windows keep still during a Home gesture until it becomes the App Switcher: 1.3.9, SMHome.h B2)
    {"SBHomeGestureSwitcherModifier", "frameForIndex:", NO, NO, DMSMSigRectIndex, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (frame)"},
    {"SBHomeGestureSwitcherModifier", "scaleForIndex:", NO, NO, DMSMSigDoubleIndex, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (scale)"},
    {"SBHomeGestureSwitcherModifier", "_isSelectedAppLayoutAtIndex:", NO, NO, DMSMSigBoolIndex, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (the stage it took)"},
    {"SBHomeGestureSwitcherModifier", "_selectedAppLayout", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (its stage)", "@"},
    {"SBHomeGestureSwitcherModifier", "_gestureHoldTimer", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (App Switcher asked for)", "q"},
    {"SBHomeGestureSwitcherModifier", "_translation", NO, NO, NULL, NULL, 0, DMSMNeedOptional, "windows keep still in a Home gesture (the finger's way)", "{CGPoint="},
    // what our hooks replace (%group SMEngine)
    {"SpringBoard", "sendEvent:", NO, YES, DMSMSigVoidObj},
    {"SBIconView", "_handleTap", NO, YES, DMSMSigVoid},
    {"SBFullScreenContinuousExposeSwitcherModifier", "shouldConfigureInAppDockHiddenAssertion", NO, YES, DMSMSigBool},
    {"SBFluidSwitcherViewController", "_keyboardWillShow:", NO, YES, DMSMSigVoidObj},
    {"SBFluidSwitcherViewController", "_keyboardWillHide:", NO, YES, DMSMSigVoidObj},
    {"SBFluidSwitcherViewController", "_updateSoftwareKeyboardVisibleWithKeyboardShowing:", NO, YES, DMSMSigVoidBool},
    {"SBFluidSwitcherViewController", "prefersStripHidden", NO, YES, DMSMSigBool},
    {"SBSwitcherChamoisLayoutAttributes", "gridWidths", NO, YES, DMSMSigObj, NULL, 0, 0, NULL, NULL, "size grid/lists"},
    {"SBSwitcherChamoisLayoutAttributes", "gridHeights", NO, YES, DMSMSigObj, NULL, 0, 0, NULL, NULL, "size grid/lists"},
    {"SBSwitcherChamoisLayoutAttributes", "stageOccludedAppScale", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "stageOcclusionDodgingPeekScale", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "stageCornerRaddii", NO, YES, DMSMSigDouble, "stageCornerRadii", 0},   // (renamed stageCornerRadii in 18.2)
    {"SBSwitcherChamoisLayoutAttributes", "maximumWindowWidthForOverlapping", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "maximumWindowHeightWithDock", NO, YES, DMSMSigDouble},
    {"SBChamoisOverlappingController", "_stageAreaForModel:chamoisLayoutAttributes:floatingDockHeight:bounds:prefersStripHidden:prefersDockHidden:widthThresholdToHideContinuousExposeStrip:", NO, YES, DMSMSigStageArea, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_modelByPerformingAutoLayoutForModel:chamoisLayoutAttributes:draggingItem:modelBeforeDragging:floatingDockHeight:bounds:screenScale:prefersStripHidden:prefersDockHidden:stageInset:", NO, YES, DMSMSigAutoLayout, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_compactSpacingHorizontallyForModel:withColumns:chamoisLayoutAttributes:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_compactSpacingVerticallyForModel:withColumns:chamoisLayoutAttributes:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_expandSpacingHorizontallyForModel:withColumns:modelBeforeDragging:chamoisLayoutAttributes:draggingItem:stageArea:", NO, YES, DMSMSigExpandH, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_expandSpacingVerticallyForModel:withColumns:chamoisLayoutAttributes:stageArea:", NO, YES, DMSMSigExpandV, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_horizontallyCenterModel:stageArea:", NO, YES, DMSMSigCenterH, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_verticallyCenterModel:withColumns:stageArea:", NO, YES, DMSMSigCenterV, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_dodgeFullyOccludedWindowsToNearestVisibleEdgeInModel:chamoisLayoutAttributes:draggingItem:bounds:", NO, YES, DMSMSigDodge, NULL, 16, 0, NULL, NULL, "auto layout/16.1"},
    {"SBChamoisOverlappingController", "_snapPositionToNearestEdgesIfNecessary:draggingItem:", NO, YES, DMSMSigVoidObjObj, NULL, 16},
    {"SBMutableChamoisOverlappingModel", "setCenter:forItem:", NO, YES, DMSMSigSetCenter, NULL, 16},
    // (iPadOS 16.0's layout pass, %group SMLayout160: the same steps under other names and argument lists, the stage frame from the calculator)
    {"SBDisplayItemLayoutAttributesCalculator", "initialStageFrameForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:", NO, YES, DMSMSigInitialStageFrame, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "modelForPreferredModel:initialStageFrame:layoutAttributes:draggingItem:modelBeforeDragging:", NO, YES, DMSMSigPreferredModel, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_compactSpacingHorizontallyForModel:withColumns:layoutAttributes:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_compactSpacingVerticallyForModel:withColumns:layoutAttributes:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_expandSpacingHorizontallyForModel:withColumns:previousResolvedModelIfAny:layoutAttributes:draggingItem:", NO, YES, DMSMSigVoid5, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_expandSpacingVerticallyForModel:withColumns:layoutAttributes:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_horizontallyCenterModel:", NO, YES, DMSMSigVoidObj, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_verticallyCenterModel:withColumns:", NO, YES, DMSMSigVoidObjObj, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingController", "_dodgeFullyOccludedWindowsToNearestVisibleEdgeInModel:layoutAttributes:draggingItem:", NO, YES, DMSMSigVoid3, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    // (... and 16.0's group shift after that pass: the calculator's run, the bounding box it moves -- DMSMShift160X)
    {"SBDisplayItemLayoutAttributesCalculator", "_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:", NO, YES, DMSMSigAutoLayoutIfNeeded, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingModel", "setBoundingBox:", NO, YES, DMSMSigVoidRect, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBChamoisOverlappingModel", "boundingBox", NO, NO, DMSMSigRect, NULL, 16, 0, NULL, NULL, "auto layout/16.0"},
    {"SBWorkspaceApplicationSceneTransitionContext", "finalize", NO, YES, DMSMSigVoid},
    {"SBAppResizeGrabberView", "setAlpha:", NO, YES, DMSMSigVoidDouble},
    {"SBAppResizeGrabberView", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBAppSwitcherPageView", "setMaskedCorners:", NO, YES, DMSMSigVoidULL},
    {"SBAppSwitcherPageView", "maskedCorners", NO, NO, DMSMSigULL},
    {"SBAppSwitcherPageView", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBFluidSwitcherItemContainer", "layoutSubviews", NO, YES, DMSMSigVoid},
    // (both bottom corners take a touch with our resize handles: hooked in SMEngine since 1.1.7, a row since 1.3.4 -- 16.0-16.7.7 all have it, 1.3.4 re-check F3;
    //  a row of both layout tables since 1.3.6: SMEngine hooks it on iPadOS 17 too, where the 17.0.3 headers have it with the same type)
    {"SBFluidSwitcherItemContainer", "allowedTouchResizeCorners", NO, YES, DMSMSigULL},
    {"SBReusableSnapshotItemContainer", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBReusableSnapshotItemContainer", "setAccessibilityIdentifier:", NO, YES, DMSMSigVoidObj},
    {"SBReusableSnapshotItemContainer", "didMoveToWindow", NO, YES, DMSMSigVoid},
    {"SBReusableSnapshotItemContainer", "pointInside:withEvent:", NO, YES, DMSMSigPointInside},
    {"SBReusableSnapshotItemContainer", "hitTest:withEvent:", NO, YES, DMSMSigHitTest},
    {"SBTopAffordanceDotsView", "setAlpha:", NO, YES, DMSMSigVoidDouble},
    {"SBSwitcherChamoisSettings", "_nearestGridSizeForSize:gridWidths:gridHeights:bounds:", NO, YES, DMSMSigGridSize, NULL, 0, 0, NULL, NULL, "size grid/lists"},
    // (iPadOS 16.0: the window sizes are rounded by a grid object instead -- %group SMGrid160)
    {"SBDisplayItemLayoutGrid", "nearestGridSizeForProposedSize:inBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:", NO, YES, DMSMSigGridObject, NULL, 0, 0, NULL, NULL, "size grid/grid object"},
    {"SBDisplayItemLayoutGrid", "minGridSizeForBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:", NO, NO, DMSMSigMinGrid, NULL, 0, 0, NULL, NULL, "size grid/grid object"},
    {"SBSwitcherChamoisSettings", "_statusBarHeight", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisSettings", "_shouldPreferStripHiddenForWindowScene:interfaceOrientation:", NO, YES, DMSMSigStripHidden},
    // iPadOS 17's layout engine (%group SMLayout17): the objects our hooks read and write, then the hooks. Read from the 17.0.3 headers and the
    // 17.6.1 decompile (SuperChaoM/iPhone15-3_17.6.1_21G101_Restore); never run on a device by us.
    {"SBContinuousExposeAutoLayoutConfiguration", "containerBounds", NO, NO, DMSMSigRect, NULL, 17},
    {"SBContinuousExposeAutoLayoutConfiguration", "dockHeightWithBottomEdgePadding", NO, NO, DMSMSigDouble, NULL, 17},
    {"SBContinuousExposeAutoLayoutConfiguration", "chamoisLayoutAttributes", NO, NO, DMSMSigObj, NULL, 17},
    {"SBContinuousExposeAutoLayoutSpace", "items", NO, NO, DMSMSigObj, NULL, 17},
    {"SBContinuousExposeAutoLayoutItem", "position", NO, NO, DMSMSigCenter, NULL, 17},
    {"SBContinuousExposeAutoLayoutItem", "setPosition:", NO, NO, DMSMSigVoidPoint, NULL, 17},
    {"SBContinuousExposeAutoLayoutItem", "size", NO, NO, DMSMSigCGSize, NULL, 17},
    {"SBContinuousExposeAutoLayoutItem", "isInDefaultPosition", NO, NO, DMSMSigBool, NULL, 17},
    {"SBContinuousExposeAutoLayoutItem", "setInDefaultPosition:", NO, NO, DMSMSigVoidBool, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "stageAreaForSpace:configuration:", NO, YES, DMSMSigStageArea17, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "spaceByPerformingAutoLayoutWithSpace:previousSpace:configuration:options:", NO, YES, DMSMSigAutoLayout17, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "_performAutoLayoutWithSpace:configuration:stageInset:", NO, YES, DMSMSigPerform17, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "_compactSpacingBetweenItemsInSpace:configuration:", NO, YES, DMSMSigVoidObjObj, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "dodgeFullyOccludedWindowsToNearestVisibleEdgeForSpace:configuration:", NO, YES, DMSMSigVoidObjObj, NULL, 17},
    {"SBContinuousExposeAutoLayoutController", "snapPositionToNearestEdgesIfNecessaryForSpace:stageArea:configuration:", NO, YES, DMSMSigSnap17, NULL, 17},
    // iPadOS 17's "position is system managed" flag of a window's attributes: our windows go out as placed by the user (DMSMAttrPlacedByUser).
    // 17.0.3 headers: -(bool)isPositionSystemManaged, -(id)attributesByModifyingPositionIsSystemManaged:(bool); 17.6.1 and 18.2 decompiles too.
    {"SBDisplayItemLayoutAttributes", "isPositionSystemManaged", NO, NO, DMSMSigBool, NULL, 17},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingPositionIsSystemManaged:", NO, NO, DMSMSigWithBool, NULL, 17},
};
static const size_t kSMNeedsCount = sizeof(kSMNeeds) / sizeof(kSMNeeds[0]);
// Which layout engine this iPadOS has, so which rows count: 16 = SBChamoisOverlappingController (iPadOS 16, where the engine was built and is
// tested), 17 = SBContinuousExposeAutoLayoutController (iPadOS 17 replaced the whole layout engine; the rest of Stage Manager's API is the same).
// Chosen by the iPadOS major version, not by which classes exist (a build with both, or neither, is judged by its own version's table, and a
// missing class then fails that table's check). simulate (debug): "layout16" / "layout17" pick that table instead.
static int gSMLayoutGen = 0;   // (0 = not chosen yet)
static int DMSMLayoutGenFor(NSString *simulate) {
    if ([simulate isEqualToString:@"layout17"]) return 17;
    if ([simulate isEqualToString:@"layout16"]) return 16;
    return [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17 ? 17 : 16;
}
static int DMSMLayoutGen(void) { return gSMLayoutGen ?: DMSMLayoutGenFor(nil); }
static NSString *DMSMLayoutName(int gen) { return gen == 17 ? @"17 (SBContinuousExposeAutoLayoutController)" : @"16 (SBChamoisOverlappingController)"; }
static BOOL DMSMRowActive(const DMSMNeed *n, int gen) { return n->layout == 0 || n->layout == gen; }
// The row's method, under its own name or its other one (alt); *name: the name found (or the row's own when neither exists).
static Method DMSMRowMethod(const DMSMNeed *n, const char **name) {
    Class c = objc_getClass(n->cls);
    if (name) *name = n->sel;
    if (!c) return NULL;
    Method m = n->classMethod ? class_getClassMethod(c, sel_registerName(n->sel)) : class_getInstanceMethod(c, sel_registerName(n->sel));
    if (!m && n->alt) {
        m = n->classMethod ? class_getClassMethod(c, sel_registerName(n->alt)) : class_getInstanceMethod(c, sel_registerName(n->alt));
        if (m && name) *name = n->alt;
    }
    return m;
}
// The start-up check's answer per row, for the code that has to choose between optional alternatives (DMSMRowPassed). Filled by the live check
// only (DMSMCheckAPILive: the self-check, the read-only check); the debug trigger's re-runs with a simulated difference leave it alone.
static BOOL gSMRowPassed[sizeof(kSMNeeds) / sizeof(kSMNeeds[0])];
static BOOL gSMRowsKnown = NO;
static NSArray<NSString *> *gSMCheckOptional;   // (the live check's optional rows that are missing or different, each "<row problem> (<feature>)")
static NSArray<NSString *> *gSMFeaturesOff;     // (optional features none of whose alternatives is here)
static NSDictionary<NSString *, NSString *> *gSMVariants;   // (group -> the variant the live check chose; before it ran: each group's first variant)
static double gSMSizedThreshold = 0;   // (window model "sized": the largest value Apple reads as a fraction of its bounds -- 1 on 16.0, 10 on 16.1; probed)
// "<group>/<name>" -> its parts.
static NSString *DMSMVariantGroup(const char *v) { const char *sl = strchr(v, '/'); return sl ? [[NSString alloc] initWithBytes:v length:(NSUInteger)(sl - v) encoding:NSUTF8StringEncoding] : @(v); }
static NSString *DMSMVariantName(const char *v) { const char *sl = strchr(v, '/'); return sl ? @(sl + 1) : @""; }
// The group's first variant in table order: the one built and tested on 16.7.7.
static NSString *DMSMFirstVariant(NSString *group) {
    for (size_t i = 0; i < kSMNeedsCount; i++) if (kSMNeeds[i].variant && [DMSMVariantGroup(kSMNeeds[i].variant) isEqualToString:group]) return DMSMVariantName(kSMNeeds[i].variant);
    return nil;
}
// The variant the check chose for this group (before the live check: the group's first one).
static NSString *DMSMVariantOf(NSString *group) { return gSMVariants[group] ?: DMSMFirstVariant(group); }
static BOOL DMSMVariantIs(const char *group, const char *name) { return [DMSMVariantOf(@(group)) isEqualToString:@(name)]; }
static BOOL gSMSizedChosen = NO;   // (DMSMVariantIs "window model" "sized", kept by the live check: the wrappers ask on every size and centre)
static BOOL DMSMSizedModel(void) { return gSMSizedChosen; }
static double DMSMSizedReadThreshold(void) { return gSMSizedThreshold; }
// A row of this layout engine that is in use: not one of a group's variants the check did not choose.
static BOOL DMSMRowInUse(const DMSMNeed *n, int gen) {
    if (!DMSMRowActive(n, gen)) return NO;
    return !n->variant || [DMSMVariantOf(DMSMVariantGroup(n->variant)) isEqualToString:DMSMVariantName(n->variant)];
}
// Window model "sized" (iPadOS 16.0 / 16.1): what Apple's own methods make of a value, asked of a fresh attributes object (no other effect). A size
// of 0.5 x 0.25 read in 100 x 100 bounds must give 50 x 25 (a fraction), 200 x 300 must stay 200 x 300 (points), and 5 x 5 tells the edge: 500 x 500
// when 5 still counts as a fraction (16.1 reads up to 10 so), 5 x 5 when it counts as points (16.0: up to 1). The centre the same way. Anything
// else: 0, and the variant is not used.
static double DMSMProbeSizedThreshold(void) {
    Class c = objc_getClass("SBDisplayItemLayoutAttributes");
    SEL ws = sel_registerName("attributesByModifyingSize:"), wc = sel_registerName("attributesByModifyingCenter:");
    SEL gs = sel_registerName("sizeInBounds:"), gc = sel_registerName("centerInBounds:");
    if (!c || ![c instancesRespondToSelector:ws] || ![c instancesRespondToSelector:wc] || ![c instancesRespondToSelector:gs] || ![c instancesRespondToSelector:gc]) return 0;
    double t = 0;
    @try {
        id a = [[c alloc] init];
        if (!a) return 0;
        CGRect b = CGRectMake(0, 0, 100, 100);
        id (*withSize)(id, SEL, CGSize) = (id (*)(id, SEL, CGSize))objc_msgSend;
        id (*withCenter)(id, SEL, CGPoint) = (id (*)(id, SEL, CGPoint))objc_msgSend;
        CGSize (*sizeIn)(id, SEL, CGRect) = (CGSize (*)(id, SEL, CGRect))objc_msgSend;
        CGPoint (*centerIn)(id, SEL, CGRect) = (CGPoint (*)(id, SEL, CGRect))objc_msgSend;
        BOOL (^near)(double, double) = ^BOOL(double x, double want) { return isfinite(x) && fabs(x - want) < 0.001; };
        CGSize sf = sizeIn(withSize(a, ws, CGSizeMake(0.5, 0.25)), gs, b), sp = sizeIn(withSize(a, ws, CGSizeMake(200, 300)), gs, b), s5 = sizeIn(withSize(a, ws, CGSizeMake(5, 5)), gs, b);
        CGPoint cf = centerIn(withCenter(a, wc, CGPointMake(0.5, 0.25)), gc, b), cp = centerIn(withCenter(a, wc, CGPointMake(200, 300)), gc, b), c5 = centerIn(withCenter(a, wc, CGPointMake(5, 5)), gc, b);
        BOOL plain = near(sf.width, 50) && near(sf.height, 25) && near(sp.width, 200) && near(sp.height, 300) && near(cf.x, 50) && near(cf.y, 25) && near(cp.x, 200) && near(cp.y, 300);
        if (plain && near(s5.width, 500) && near(s5.height, 500) && near(c5.x, 500) && near(c5.y, 500)) t = 10;
        else if (plain && near(s5.width, 5) && near(s5.height, 5) && near(c5.x, 5) && near(c5.y, 5)) t = 1;
    } @catch (id e) { t = 0; }
    return t;
}
// One row: nil when it is there as we use it, else what is wrong ("-[cls sel] missing", "... is X, we use Y", "ivar ... missing").
// *compared: the row's method (or ivar) was found and its type looked at (what the "verified" count has always counted).
static NSString *DMSMRowProblem(const DMSMNeed *n, NSString *simulate, BOOL *compared) {
    if (compared) *compared = NO;
    Class c = objc_getClass(n->cls);
    if (!c) return [NSString stringWithFormat:@"class %s missing", n->cls];
    if (n->ivar) {
        Ivar iv = class_getInstanceVariable(c, n->sel);
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        if (!t) return [NSString stringWithFormat:@"ivar %s.%s missing", n->cls, n->sel];
        if (compared) *compared = YES;
        if (strncmp(t, n->ivar, strlen(n->ivar))) return [NSString stringWithFormat:@"ivar %s.%s is %s, we read %s...", n->cls, n->sel, t, n->ivar];
        return nil;
    }
    const char *name = n->sel;
    Method m = DMSMRowMethod(n, &name);
    if (!strcmp(n->sel, "attributesByModifyingAttributedSize:") && [simulate isEqualToString:@"selector"]) { m = NULL; name = "attributesByModifyingAttributedSize_simulatedMissing:"; }
    if (!strcmp(n->sel, "appLayoutByRemovingItemInLayoutRole:") && [simulate isEqualToString:@"optional"]) m = NULL;   // (as on iPadOS 16.2-16.3)
    if (!m) return [NSString stringWithFormat:@"%c[%s %s] missing", n->classMethod ? '+' : '-', n->cls, name];
    if (compared) *compared = YES;
    if (n->sig) {
        NSString *have = DMSMSigOfMethod(m), *want = n->sig();
        if (!strcmp(n->sel, "attributedSize") && [simulate isEqualToString:@"encoding"]) have = DMSMNormEncoding("{SBDisplayItemAttributedSize={CGSize=dd}q}16@0:8");   // (a layout without referenceBounds, review S3)
        if (![have isEqualToString:want]) return [NSString stringWithFormat:@"-[%s %s] is %@, we use %@", n->cls, name, have, want];
    }
    return nil;
}
// iPadOS 17+: the layout roles the engine writes -- 1 primary, 2 side, 5 and 6 the next windows ("additional side" 0 and 1) -- asked of SpringBoard
// itself. They were read on 16.7.7, and 17.6.1's -[SBAppLayout layoutRoleForItem:] gives the same (item 0 -> SBLayoutRolePrimary, 1 ->
// SBLayoutRoleSide, item n >= 2 -> n + 3); here SpringBoard's exported SBLayoutRoleIsValid() and its role constants (in every 16.5-18.6 tbd) are
// asked on the device. A role SpringBoard does not take, or a constant with another value: the check fails (the engine stays off on that build,
// as for a missing method). A symbol that is not exported: noted only (the roles are 17.6.1's own). The values go into the diagnostics record.
static NSString *gSMRolesNote;   // (what the roles check saw, for the diagnostics record)
static void DMSMCheckRoles17(NSMutableArray *bad, NSString *simulate) {
    BOOL (*isValid)(long long) = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "SBLayoutRoleIsValid");
    const long long *primary = (const long long *)dlsym(RTLD_DEFAULT, "SBLayoutRolePrimary");
    const long long *side = (const long long *)dlsym(RTLD_DEFAULT, "SBLayoutRoleSide");
    const long long *center = (const long long *)dlsym(RTLD_DEFAULT, "SBLayoutRoleCenter");
    const long long *addMin = (const long long *)dlsym(RTLD_DEFAULT, "SBLayoutRoleAdditionalSideRangeMin");
    const long long *addMax = (const long long *)dlsym(RTLD_DEFAULT, "SBLayoutRoleAdditionalSideRangeMax");
    NSMutableArray<NSString *> *note = [NSMutableArray array];
    BOOL ok = YES;
    if (isValid) {
        NSMutableArray *refused = [NSMutableArray array];
        for (long long r = 1; r <= 6; r++) {
            if (r == 3 || r == 4) continue;   // (floating and centre: never written by us)
            BOOL valid = isValid(r);
            if ([simulate isEqualToString:@"roles"] && r == 6) valid = NO;   // (debug: a role SpringBoard would not take)
            if (!valid) [refused addObject:@(r)];
        }
        if (refused.count) { ok = NO; [bad addObject:[NSString stringWithFormat:@"layout roles %@ not valid for SpringBoard", [refused componentsJoinedByString:@","]]]; }
        [note addObject:refused.count ? @"roles refused" : @"roles 1,2,5,6 valid"];
    } else [note addObject:@"SBLayoutRoleIsValid not exported"];
    if (primary && *primary != 1) { ok = NO; [bad addObject:[NSString stringWithFormat:@"SBLayoutRolePrimary is %lld, we use 1", *primary]]; }
    if (side && *side != 2) { ok = NO; [bad addObject:[NSString stringWithFormat:@"SBLayoutRoleSide is %lld, we use 2", *side]]; }
    [note addObject:[NSString stringWithFormat:@"primary %@, side %@, centre %@, additional %@..%@", primary ? @(*primary) : @"-", side ? @(*side) : @"-",
        center ? @(*center) : @"-", addMin ? @(*addMin) : @"-", addMax ? @(*addMax) : @"-"]];
    gSMRolesNote = [NSString stringWithFormat:@"%@: %@", ok ? @"ok" : @"DIFFERENT", [note componentsJoinedByString:@"; "]];
}
// Checks every row of this iPadOS's layout engine (and the rows both share): the classes and methods are there, with the signatures we use.
// Returns the CORE rows that are missing or different (empty = the engine can run); optional rows go to *optional (with the feature they serve),
// features left with none of their alternatives to *featuresOff, each row's answer to rowPassed (NULL: not wanted). simulate (debug):
// "selector" / "encoding" pretend one core row is missing / different, "optional" that -appLayoutByRemovingItemInLayoutRole: is missing (as on
// iPadOS 16.2-16.3); "layout16" / "layout17" check that layout engine's table; "roles" pretends role 6 is refused (17 table, DMSMCheckRoles17).
static NSArray<NSString *> *DMSMCheckAPIFull(NSString *simulate, NSUInteger *checked, NSArray<NSString *> **optional, NSArray<NSString *> **featuresOff, BOOL *rowPassed,
                                             NSDictionary<NSString *, NSString *> **variants, double *sizedThreshold) {
    NSMutableArray *bad = [NSMutableArray array], *opt = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *feature = [NSMutableDictionary dictionary];   // (feature -> one of its alternatives passed)
    NSMutableArray<NSString *> *featureOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groupVariants = [NSMutableDictionary dictionary];   // (group -> its variants, table order)
    NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *variantOK = [NSMutableDictionary dictionary];   // ("group/variant" -> all its rows there so far)
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *variantProblems = [NSMutableDictionary dictionary];
    if (sizedThreshold) *sizedThreshold = 0;
    int gen = [simulate hasPrefix:@"layout"] ? DMSMLayoutGenFor(simulate) : DMSMLayoutGen();
    BOOL comparedRow[sizeof(kSMNeeds) / sizeof(kSMNeeds[0])];   // (each row found and its type looked at: counted below for the ways in use only)
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        DMSMNeed n = kSMNeeds[i];
        comparedRow[i] = NO;
        if (rowPassed) rowPassed[i] = NO;
        if (!DMSMRowActive(&n, gen)) continue;
        BOOL compared = NO;
        NSString *problem = DMSMRowProblem(&n, simulate, &compared);
        comparedRow[i] = compared;
        if (rowPassed) rowPassed[i] = problem == nil;
        if (n.variant) {   // (one of a group's variants: judged as a whole below)
            NSString *key = @(n.variant), *g = DMSMVariantGroup(n.variant), *vn = DMSMVariantName(n.variant);
            if (!groupVariants[g]) { groupVariants[g] = [NSMutableArray array]; [groupOrder addObject:g]; }
            if (![groupVariants[g] containsObject:vn]) [groupVariants[g] addObject:vn];
            if (!variantOK[key]) variantOK[key] = @YES;
            if (problem) {
                variantOK[key] = @NO;
                if (!variantProblems[key]) variantProblems[key] = [NSMutableArray array];
                [variantProblems[key] addObject:problem];
            }
        } else if (n.need == DMSMNeedOptional) {
            NSString *f = n.feature ? @(n.feature) : @(n.sel);
            if (!feature[f]) [featureOrder addObject:f];
            feature[f] = @(feature[f].boolValue || problem == nil);
            if (problem) [opt addObject:[NSString stringWithFormat:@"%@ (%@)", problem, f]];
        } else if (problem && ![bad containsObject:problem]) [bad addObject:problem];
    }
    NSMutableArray *off = [NSMutableArray array];
    for (NSString *f in featureOrder) if (!feature[f].boolValue) [off addObject:f];
    if (optional) *optional = opt;
    if (featuresOff) *featuresOff = off;
    // each group: the first variant (table order) whose rows are all there -- for the "sized" window model also Apple's reading of its values; none:
    // the first variant's problems are core problems
    NSMutableDictionary<NSString *, NSString *> *chosen = [NSMutableDictionary dictionary];
    for (NSString *g in groupOrder) {
        NSString *pick = nil;
        for (NSString *vn in groupVariants[g]) {
            NSString *key = [NSString stringWithFormat:@"%@/%@", g, vn];
            BOOL ok = [variantOK[key] boolValue];
            if (ok && [key isEqualToString:@"window model/sized"]) {
                double t = DMSMProbeSizedThreshold();
                if (sizedThreshold) *sizedThreshold = t;
                if (t <= 0) { ok = NO; variantProblems[key] = [NSMutableArray arrayWithObject:@"window model sized: Apple's size and centre do not read back as expected"]; }
            }
            if (ok) { pick = vn; break; }
        }
        if (pick) { chosen[g] = pick; continue; }
        NSString *first = [NSString stringWithFormat:@"%@/%@", g, groupVariants[g].firstObject];
        for (NSString *p in variantProblems[first]) if (![bad containsObject:p]) [bad addObject:p];
    }
    if (variants) *variants = chosen;
    // (the count: the rows of the ways this iPad's engine uses -- every row without variants, the chosen variant's, or the first variant's where none
    //  is complete -- found and their type looked at. Rows of the other ways are checked but not counted, so the number keeps its meaning whatever
    //  other ways the table knows: 16.7.7 counts 76 as in 1.3.3; the first 1.3.4 builds counted 78 and 81 there through 16.0's rows 16.7.7 also has)
    if (checked) {
        NSUInteger c = 0;
        for (size_t i = 0; i < kSMNeedsCount; i++) {
            if (!comparedRow[i]) continue;
            const char *v = kSMNeeds[i].variant;
            if (v) {
                NSString *g = DMSMVariantGroup(v), *use = chosen[g] ?: groupVariants[g].firstObject;
                if (![use isEqualToString:DMSMVariantName(v)]) continue;
            }
            c++;
        }
        *checked = c;
    }
    // (the struct we read and hand back by value: its size in the method signature matches ours -- the byte count, on top of the shape above)
    Class ac = objc_getClass("SBDisplayItemLayoutAttributes");
    Method sm = ac ? class_getInstanceMethod(ac, sel_registerName("attributedSize")) : NULL;
    if (sm) {
        NSUInteger size = 0, align = 0;
        char ret[256] = ""; method_getReturnType(sm, ret, sizeof(ret));
        @try { NSGetSizeAndAlignment(ret, &size, &align); } @catch (id e) { size = 0; }
        if (size != sizeof(DMSMAttributedSize)) [bad addObject:[NSString stringWithFormat:@"attributedSize is %lu bytes, ours %lu", (unsigned long)size, (unsigned long)sizeof(DMSMAttributedSize)]];
    }
    if (gen == 17) DMSMCheckRoles17(bad, simulate);   // (iPadOS 17+: the roles' meaning too, not only the methods' names)
    return bad;
}
// The core rows' problems only, nothing recorded (the debug trigger's re-runs, the Mac tests).
static __attribute__((unused)) NSArray<NSString *> *DMSMCheckAPI(NSString *simulate, NSUInteger *checked) { return DMSMCheckAPIFull(simulate, checked, NULL, NULL, NULL, NULL, NULL); }
// The groups where the check chose another variant than the first (the tested) one: "group: variant", e.g. "window model: sized" (iPadOS 16.0 /
// 16.1). Empty on 16.2 and later. None of these ways has run on a device; Report a Problem names them (sm-160).
static NSArray<NSString *> *DMSMOtherWays(NSDictionary<NSString *, NSString *> *variants) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *g in [variants.allKeys sortedArrayUsingSelector:@selector(compare:)]) if (![variants[g] isEqualToString:DMSMFirstVariant(g)]) [a addObject:[NSString stringWithFormat:@"%@: %@", g, variants[g]]];
    return a;
}
// The other ways Settings offers like the tested ones, without the "(Untested)" label and its note: iPadOS 16.1, whose only other way is its window
// model, is offered like 16.2 and 16.3 (the owner's decision, 4 Oct 2026). Any other way -- 16.0's layout pass and size grid -- marks Stage Manager
// untested, and so would a way added later until it is decided otherwise.
static const char *const kSMWaysOfferedNormally[] = {"window model/sized"};
// YES when the check chose a way Settings must offer as untested (iPadOS 16.0).
static BOOL DMSMWaysUntested(NSDictionary<NSString *, NSString *> *variants) {
    for (NSString *g in variants) {
        if ([variants[g] isEqualToString:DMSMFirstVariant(g)]) continue;
        NSString *way = [NSString stringWithFormat:@"%@/%@", g, variants[g]];
        BOOL normal = NO;
        for (size_t i = 0; i < sizeof(kSMWaysOfferedNormally) / sizeof(kSMWaysOfferedNormally[0]); i++) if ([way isEqualToString:@(kSMWaysOfferedNormally[i])]) normal = YES;
        if (!normal) return YES;
    }
    return NO;
}
// The chosen ways in the verdict record (common/StageManagerAvailable.h): "paths" = the jobs done another iPadOS's way (iPadOS 16.0 / 16.1; Report a
// Problem names them), "untested" = one of them is not offered normally (iPadOS 16.0: Settings' "Stage Manager (Untested)" and its note).
static void DMSMRecordWays(NSMutableDictionary *v, NSDictionary<NSString *, NSString *> *variants) {
    NSArray *paths = DMSMOtherWays(variants);
    if (paths.count) v[@"paths"] = paths;
    if (DMSMWaysUntested(variants)) v[@"untested"] = @YES;
}
// The start-up check (self-check or read-only): also records each row's answer and the optional rows' state for the code and the verdict.
static NSArray<NSString *> *DMSMCheckAPILive(NSString *simulate, NSUInteger *checked) {
    NSArray *opt = nil, *off = nil; NSDictionary *vars = nil; double t = 0;
    NSArray *bad = DMSMCheckAPIFull(simulate, checked, &opt, &off, gSMRowPassed, &vars, &t);
    gSMRowsKnown = YES; gSMCheckOptional = opt; gSMFeaturesOff = off; gSMVariants = vars; gSMSizedThreshold = t;
    gSMSizedChosen = DMSMVariantIs("window model", "sized");
    for (NSString *l in opt) DMLog([@"[smcheck] optional, not here: " stringByAppendingString:l]);
    for (NSString *f in off) DMLog([NSString stringWithFormat:@"[smcheck] without it: %@ is off on this iPadOS", f]);
    NSArray *paths = DMSMOtherWays(vars);
    if (paths.count) DMLog([NSString stringWithFormat:@"[smcheck] another iPadOS's way here (never run on a device): %@%@; Settings offers Stage Manager %@", [paths componentsJoinedByString:@"; "],
                            DMSMVariantIs("window model", "sized") ? [NSString stringWithFormat:@" (values up to %.0f read as fractions)", t] : @"",
                            DMSMWaysUntested(vars) ? @"as untested" : @"normally"]);
    return bad;
}
// Whether one row (by class and name) is there as we use it: the start-up check's answer; before any check ran (where none runs: no Stage Manager)
// the row is looked up now, without a log line.
static BOOL DMSMRowPassed(const char *cls, const char *sel) {
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        if (strcmp(kSMNeeds[i].cls, cls) || strcmp(kSMNeeds[i].sel, sel)) continue;
        if (gSMRowsKnown) return gSMRowPassed[i];
        BOOL compared = NO;
        return DMSMRowProblem(&kSMNeeds[i], nil, &compared) == nil;
    }
    return NO;
}
// Windows told apart by their own scene (M-2, SMWindowKey.h): the window's identifier and Apple's entity for one window are there as we use them
// (optional rows, on every 16.x build read and the 17.0.3 headers). Else every key is an app key: the engine works by app, as before. Worked out
// once the start-up check has run (the same answer for the whole SpringBoard run: keys made earlier stay comparable). debug: /tmp/msb-sm-bybundle.
static int gSMPerWindow = -1;
static BOOL DMSMPerWindow(void) {
    if (gSMPerWindow >= 0) return gSMPerWindow == 1;
    BOOL on = DMSMRowPassed("SBDisplayItem", "uniqueIdentifier") && DMSMRowPassed("SBMainSwitcherControllerCoordinator", "_entityForDisplayItem:displayIdentity:");
#if DEBUG
    if (on && DMTestFlag("/tmp/msb-sm-bybundle")) on = NO;
#endif
    if (gSMRowsKnown) {
        gSMPerWindow = on ? 1 : 0;
        DMLog(on ? @"[smwin] windows are told apart by their own scene (two windows of one app are two windows)" : @"[smwin] windows are told apart by app here (as before): the window identifier rows are not as expected");
    }
    return on;
}
// The hooked methods' current implementations (to see afterwards that our hooks really went in): this layout engine's rows.
static NSArray<NSValue *> *DMSMHookedIMPs(void) {
    NSMutableArray *a = [NSMutableArray array];
    int gen = DMSMLayoutGen();
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        if (!kSMNeeds[i].hooked || !DMSMRowInUse(&kSMNeeds[i], gen)) continue;
        Method m = DMSMRowMethod(&kSMNeeds[i], NULL);
        [a addObject:[NSValue valueWithPointer:m ? (const void *)method_getImplementation(m) : NULL]];
    }
    return a;
}
static NSArray<NSString *> *DMSMHooksNotInstalled(NSArray<NSValue *> *before, BOOL simulate) {
    NSArray *after = DMSMHookedIMPs();
    NSMutableArray *bad = [NSMutableArray array];
    NSUInteger k = 0;
    int gen = DMSMLayoutGen();
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        if (!kSMNeeds[i].hooked || !DMSMRowInUse(&kSMNeeds[i], gen)) continue;
        const char *name = kSMNeeds[i].sel;
        DMSMRowMethod(&kSMNeeds[i], &name);
        BOOL same = k < before.count && k < after.count && [before[k] isEqual:after[k]];
        if (same || (simulate && k == 0)) [bad addObject:[NSString stringWithFormat:@"hook on -[%s %s] not installed", kSMNeeds[i].cls, name]];
        k++;
    }
    return bad;
}
// The name the windows' corner radius getter has here (stageCornerRaddii, sic, through 17; stageCornerRadii in 18.2), or NULL.
static const char *DMSMCornerRadiusSelector(void) {
    for (size_t i = 0; i < kSMNeedsCount; i++) if (kSMNeeds[i].alt && !strcmp(kSMNeeds[i].sel, "stageCornerRaddii")) {
        const char *name = NULL;
        return DMSMRowMethod(&kSMNeeds[i], &name) ? name : NULL;
    }
    return NULL;
}
// The verdict for the other processes (common/StageManagerAvailable.h): this iPadOS build, passed or not, a short reason, the list.
static void DMSMPublishVerdict(BOOL ok, NSString *reason, NSArray<NSString *> *details) {
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"build"] = MSBDOSBuild() ?: @"";
    v[@"os"] = [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"";
    v[@"ok"] = @(ok);
    v[@"layout"] = @(DMSMLayoutGen());   // (which layout engine's table was checked: 16 or 17)
    if (reason) v[@"reason"] = reason;
    if (details.count) v[@"details"] = details.count > 16 ? [details subarrayWithRange:NSMakeRange(0, 16)] : details;
    // (optional rows not here, and features left without any of their alternatives: Report a Problem shows them, nothing is greyed for them)
    if (gSMCheckOptional.count) v[@"optional"] = gSMCheckOptional.count > 8 ? [gSMCheckOptional subarrayWithRange:NSMakeRange(0, 8)] : gSMCheckOptional;
    if (gSMFeaturesOff.count) v[@"featuresOff"] = gSMFeaturesOff;
    DMSMRecordWays(v, gSMVariants);
    CFPreferencesSetValue(MSBD_SM_CHECK_KEY, (__bridge CFPropertyListRef)v, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// A call the start-up check had verified failed anyway (an object of another class than expected, a value that made no sense): kept with the verdict
// for reports (at most 8), the engine stays on (the wrappers refused the call, nothing was read or written).
static void DMSMRecordRuntimeFailure(NSString *line) {
    static int n = 0;
    if (!gSMCheckDone || n >= 8) return;
    n++;
    id cur = (__bridge_transfer id)CFPreferencesCopyValue(MSBD_SM_CHECK_KEY, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSMutableDictionary *v = [cur isKindOfClass:[NSDictionary class]] ? [cur mutableCopy] : nil;
    if (!v) return;
    NSMutableArray *r = [v[@"runtime"] isKindOfClass:[NSArray class]] ? [v[@"runtime"] mutableCopy] : [NSMutableArray array];
    [r addObject:line];
    v[@"runtime"] = r;
    CFPreferencesSetValue(MSBD_SM_CHECK_KEY, (__bridge CFPropertyListRef)v, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// The diagnostics' hook list (StatusBar.x DMDiagHooks, iPadOS 17+): the engine's hooks written for the OTHER layout engine (iPadOS 16's
// SBChamoisOverlappingController / SBMutableChamoisOverlappingModel on 17) and the corner radius under the name this iPadOS does not use
// (stageCornerRaddii through 17, stageCornerRadii from 18) are missing by design, not news: left out of the "missing" lists.
static BOOL DMSMHookNotForThisOS(const char *cls, const char *sel) {
    if (!cls || !sel) return NO;
    int gen = DMSMLayoutGen();
    if (gen == 17 && (!strcmp(cls, "SBChamoisOverlappingController") || !strcmp(cls, "SBMutableChamoisOverlappingModel"))) return YES;
    if (gen == 16 && !strcmp(cls, "SBContinuousExposeAutoLayoutController")) return YES;
    if (!strcmp(cls, "SBSwitcherChamoisLayoutAttributes") && (!strcmp(sel, "stageCornerRaddii") || !strcmp(sel, "stageCornerRadii"))) {
        Class c = objc_getClass(cls);
        return c && ![c instancesRespondToSelector:sel_registerName(sel)];   // (the name that is not here: the other one is hooked)
    }
    return NO;
}
static long long DMSMRoleOr(id stage, id item, long long dflt) { long long r = dflt; return DMSMStageRoleOfItem(stage, item, &r) ? r : dflt; }
static long long DMSMPolicyOr(id attrs, long long dflt) { long long p = dflt; return DMSMAttrSizingPolicy(attrs, &p) ? p : dflt; }
// A stage of several windows cut back to its primary window (another engine takes over: without Stage Manager a multi-window stage is a multi-app
// layout, which iPadOS shows as Split View). iPadOS 16.4 and later: the other windows taken out one by one (roles re-read after each removal:
// Stage Manager renumbers them -- reading them from the original stage left a two-app layout behind, logic test SM-6). 16.2-16.3 have no
// -appLayoutByRemovingItemInLayoutRole:, so the primary window's leaf stage, the same single-window stage in one step. nil: nothing to cut (one
// window), or neither way is here (*unsupported then YES).
static id DMSMStageCutToPrimary(id stage, BOOL *unsupported) {
    if (unsupported) *unsupported = NO;
    if (DMSMStageItemsMap(stage).count < 2) return nil;
    if (DMSMRowPassed("SBAppLayout", "appLayoutByRemovingItemInLayoutRole:")) {
        id single = stage;
        for (int guard = 0; guard < DMSM_ROLES_MAX + 2; guard++) {   // (one removal per window: covers a desktop as large as the role table allows, not just the old four)
            NSDictionary *left = DMSMStageItemsMap(single);
            if (left.count < 2) break;
            long drop = 0;
            for (id item in left) { long role = (long)DMSMRoleOr(single, item, 0); if (role > 1) { drop = role; break; } }
            if (!drop) break;
            id next = DMSMStageWithoutRole(single, drop);
            if (!next || next == single) break;
            single = next;
        }
        return single != stage ? single : nil;
    }
    if (DMSMRowPassed("SBAppLayout", "leafAppLayoutForRole:")) {
        id leaf = DMSMStageLeaf(stage, 1);
        return leaf && leaf != stage && DMSMStageItemsMap(leaf).count == 1 ? leaf : nil;
    }
    if (unsupported) *unsupported = YES;
    return nil;
}

// ---- iPadOS 17: the auto-layout engine's objects (SBContinuousExposeAutoLayout*, %group SMLayout17) ---------------------------------------------
// A layout pass (SBContinuousExposeAutoLayoutController) works on a SPACE (the stage's windows as ITEMS: a center "position" and a "size" in points
// of the container, and whether the item is in its default, system-managed place) with a CONFIGURATION (the container bounds, the Dock's height
// with its bottom padding, the stage's SBSwitcherChamoisLayoutAttributes). Read with the same checks as everything above: class, selector and
// signature first; values that make no sense are refused (nil / NO), and a refused read makes the hook leave Apple's result as it is.
static BOOL DMSMIsKind(id o, const char *cls) { Class c = objc_getClass(cls); return o && c && [o isKindOfClass:c]; }
static BOOL DMSMRectSane(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) && isfinite(r.size.width) && isfinite(r.size.height)
        && r.size.width >= 100.0 && r.size.height >= 100.0 && r.size.width < 20000.0 && r.size.height < 20000.0
        && fabs(r.origin.x) < 20000.0 && fabs(r.origin.y) < 20000.0;
}
static BOOL DMSMCfgBounds(id cfg, CGRect *out) {
    if (!DMSMIsKind(cfg, "SBContinuousExposeAutoLayoutConfiguration")) return NO;
    SEL sel = NSSelectorFromString(@"containerBounds");
    if (!DMSMSigOK(cfg, sel, DMSMSigRect(), "auto-layout configuration containerBounds")) return NO;
    CGRect r = ((CGRect (*)(id, SEL))objc_msgSend)(cfg, sel);
    if (!DMSMRectSane(r)) { DMSMAPIFail(@"auto-layout configuration containerBounds", [@"not a container: " stringByAppendingString:NSStringFromCGRect(r)]); return NO; }
    if (out) *out = r;
    return YES;
}
static BOOL DMSMCfgDock(id cfg, double *out) {
    if (!DMSMIsKind(cfg, "SBContinuousExposeAutoLayoutConfiguration")) return NO;
    SEL sel = NSSelectorFromString(@"dockHeightWithBottomEdgePadding");
    if (!DMSMSigOK(cfg, sel, DMSMSigDouble(), "dockHeightWithBottomEdgePadding")) return NO;
    double d = ((double (*)(id, SEL))objc_msgSend)(cfg, sel);
    if (!isfinite(d) || d < 0 || d > 1000.0) { DMSMAPIFail(@"dockHeightWithBottomEdgePadding", [NSString stringWithFormat:@"not a height: %g", d]); return NO; }
    if (out) *out = d;
    return YES;
}
// A BOOL of the configuration's Stage Manager attributes (prefersDockHidden / prefersStripHidden: in the 17.0.3 headers; optional, NO when not there).
static BOOL DMSMCfgChamoisFlag(id cfg, NSString *name) {
    if (!DMSMIsKind(cfg, "SBContinuousExposeAutoLayoutConfiguration")) return NO;
    SEL get = NSSelectorFromString(@"chamoisLayoutAttributes");
    if (!DMSMSigOK(cfg, get, DMSMSigObj(), "auto-layout configuration chamoisLayoutAttributes")) return NO;
    id a = ((id (*)(id, SEL))objc_msgSend)(cfg, get);
    SEL sel = NSSelectorFromString(name);
    if (!DMSMIsKind(a, "SBSwitcherChamoisLayoutAttributes") || ![a respondsToSelector:sel] || !DMSMSigOK(a, sel, DMSMSigBool(), name.UTF8String)) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(a, sel);
}
// The space's items (nil when anything is not what the headers say: then nothing is changed).
static NSArray *DMSMSpaceItems(id space) {
    if (!DMSMIsKind(space, "SBContinuousExposeAutoLayoutSpace")) return nil;
    SEL sel = NSSelectorFromString(@"items");
    if (!DMSMSigOK(space, sel, DMSMSigObj(), "auto-layout space items")) return nil;
    id items = ((id (*)(id, SEL))objc_msgSend)(space, sel);
    if (![items isKindOfClass:[NSArray class]]) return nil;
    for (id it in items) if (!DMSMIsKind(it, "SBContinuousExposeAutoLayoutItem")) { DMSMAPIFail(@"auto-layout space items", [NSString stringWithFormat:@"an item of class %@", NSStringFromClass([it class])]); return nil; }
    return items;
}
static BOOL DMSMItemPosition(id item, CGPoint *out) {
    SEL sel = NSSelectorFromString(@"position");
    if (!DMSMIsKind(item, "SBContinuousExposeAutoLayoutItem") || !DMSMSigOK(item, sel, DMSMSigCenter(), "auto-layout item position")) return NO;
    CGPoint p = ((CGPoint (*)(id, SEL))objc_msgSend)(item, sel);
    if (!isfinite(p.x) || !isfinite(p.y) || fabs(p.x) > 40000.0 || fabs(p.y) > 40000.0) return NO;
    if (out) *out = p;
    return YES;
}
static BOOL DMSMItemSize(id item, CGSize *out) {
    SEL sel = NSSelectorFromString(@"size");
    if (!DMSMIsKind(item, "SBContinuousExposeAutoLayoutItem") || !DMSMSigOK(item, sel, DMSMSigCGSize(), "auto-layout item size")) return NO;
    CGSize z = ((CGSize (*)(id, SEL))objc_msgSend)(item, sel);
    if (!isfinite(z.width) || !isfinite(z.height) || z.width < 1.0 || z.height < 1.0 || z.width > 20000.0 || z.height > 20000.0) return NO;
    if (out) *out = z;
    return YES;
}
static BOOL DMSMItemSetPosition(id item, CGPoint p) {
    SEL sel = NSSelectorFromString(@"setPosition:");
    if (!isfinite(p.x) || !isfinite(p.y) || fabs(p.x) > 40000.0 || fabs(p.y) > 40000.0) { DMSMAPIFail(@"auto-layout item setPosition:", [@"refused to hand over " stringByAppendingString:NSStringFromCGPoint(p)]); return NO; }
    if (!DMSMIsKind(item, "SBContinuousExposeAutoLayoutItem") || !DMSMSigOK(item, sel, DMSMSigVoidPoint(), "auto-layout item setPosition:")) return NO;
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(item, sel, p);
    return YES;
}
static BOOL DMSMItemInDefaultPosition(id item, BOOL *out) {
    SEL sel = NSSelectorFromString(@"isInDefaultPosition");
    if (!DMSMIsKind(item, "SBContinuousExposeAutoLayoutItem") || !DMSMSigOK(item, sel, DMSMSigBool(), "auto-layout item isInDefaultPosition")) return NO;
    if (out) *out = ((BOOL (*)(id, SEL))objc_msgSend)(item, sel);
    return YES;
}
static BOOL DMSMItemSetInDefaultPosition(id item, BOOL on) {
    SEL sel = NSSelectorFromString(@"setInDefaultPosition:");
    if (!DMSMIsKind(item, "SBContinuousExposeAutoLayoutItem") || !DMSMSigOK(item, sel, DMSMSigVoidBool(), "auto-layout item setInDefaultPosition:")) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(item, sel, on);
    return YES;
}
// A window's center kept inside `area`: its whole frame in the area; where the window is larger than the area, its top and left edges win (the
// title bar and traffic lights stay reachable, like a Mac; Apple's own clamp lets the bottom/right win).
static CGPoint DMSMClampCenter(CGPoint c, CGSize s, CGRect area) {
    CGFloat x = c.x, y = c.y;
    x = MIN(x, CGRectGetMaxX(area) - s.width / 2.0);  x = MAX(x, CGRectGetMinX(area) + s.width / 2.0);
    y = MIN(y, CGRectGetMaxY(area) - s.height / 2.0); y = MAX(y, CGRectGetMinY(area) + s.height / 2.0);
    return CGPointMake(x, y);
}
// One iPadOS 17 layout pass, around Apple's -_performAutoLayoutWithSpace:configuration:stageInset: (%group SMLayout17, StatusBar.x). Kept here
// (checked wrappers only, no Logos) so the Mac test can run it around a stand-in of 17.6.1's own pass (tools/test-smlayout17.m).
//  begin: each window's place and size before Apple's pass -- none for a window with no place yet ((0,0): Apple centres it) -- and a LONE window's
//         "default position" flag hidden from this pass (Apple centres a lone system-managed window; our windows are not system managed anyway,
//         DMSMAttrPlacedByUser);
//  end:   the lone window's flag put back, and every remembered window at its own place again, kept inside `area` (our stage area, what Apple's
//         pass returns: -stageAreaForSpace:configuration:, hooked) instead of Apple's container inset by its screen edge padding.
// A window as big as the container (our full screen inside the stage, sizing policy 2) goes back to the container's centre: Apple's padding clamp
// pushes a window bigger than the padded container to its far edges (17.6.1: x = min(max(x, minX + w/2), maxX - w/2) of the container inset by
// the screen edge padding -- a 1194 pt window ends 48 pt left and up), and only re-centres it when it is the stage's only window. Apple's own full
// screen is a stage of its own; ours shares the stage with the windows (they can come in front of it), so with windows around it ours was moved.
// Anything unreadable is left out (Apple's result stays for that window).
typedef struct { NSArray *before; id lone; BOOL loneHidden; } DMSM17Pass;
static DMSM17Pass DMSM17PassBegin(id space, BOOL haveContainer, CGRect container) {
    DMSM17Pass pass = { nil, nil, NO };
    NSArray *items = DMSMSpaceItems(space);
    NSMutableArray *before = [NSMutableArray array];
    for (id it in items) {
        CGPoint p; CGSize z;
        BOOL keep = haveContainer && DMSMItemPosition(it, &p) && DMSMItemSize(it, &z) && !(p.x == 0 && p.y == 0);
        BOOL full = keep && z.width >= container.size.width - 1.0 && z.height >= container.size.height - 1.0;
        if (full) p = CGPointMake(CGRectGetMidX(container), CGRectGetMidY(container));
        [before addObject:keep ? @[it, [NSValue valueWithCGPoint:p], [NSValue valueWithCGSize:z], @(full)] : [NSNull null]];
    }
    pass.before = before;
    if (items.count == 1 && before.firstObject != [NSNull null] && ![before.firstObject[3] boolValue]) {
        BOOL def = NO;
        if (DMSMItemInDefaultPosition(items.firstObject, &def) && def && DMSMItemSetInDefaultPosition(items.firstObject, NO)) { pass.lone = items.firstObject; pass.loneHidden = YES; }
    }
    return pass;
}
// Returns how many windows were put back at their place (-1: the area was not a rectangle, nothing moved).
static int DMSM17PassEnd(DMSM17Pass *pass, CGRect area) {
    if (pass->loneHidden) { DMSMItemSetInDefaultPosition(pass->lone, YES); pass->loneHidden = NO; }
    if (!DMSMRectSane(area)) return -1;
    int moved = 0;
    for (id e in pass->before) {
        if (e == [NSNull null]) continue;
        NSArray *en = e;
        CGPoint p = [en[1] CGPointValue], want = [en[3] boolValue] ? p : DMSMClampCenter(p, [en[2] CGSizeValue], area), now;   // (full screen: the container's centre, not clamped into the stage area)
        if (!DMSMItemPosition(en[0], &now) || (fabs(now.x - want.x) < 0.5 && fabs(now.y - want.y) < 0.5)) continue;
        if (DMSMItemSetPosition(en[0], want)) moved++;
    }
    return moved;
}

// ---- the window sizes Stage Manager allows (-[SBSwitcherChamoisLayoutAttributes gridWidths / gridHeights], %group SMEngine) ----------------------------
// (the window sizes Stage Manager allows, a list of widths and one of heights ~10 pt apart up to 48 pt short of the edges; a size is rounded to them.
//  Our engine: every whole point up to the screen size -- one cached list per length, so exact sizes cost nothing)
// iPadOS 17+: the shortest window. 17.6.1 builds the height list from 480 pt up (-[SBSwitcherChamoisSettings layoutAttributesForContainerBounds:...]:
// _gridHeightsForSafeHeight:minimumHeight:480.0 ...; widths from 320), and its flexible grid (_SBDisplayItemFlexibleGrid) only ever picks a height
// from that list -- so a window was never shorter than 480 pt: Fit to Window's quarters and the Top/Bottom Half layouts in landscape (an 11" iPad's
// quarter is 321 pt, an iPad Air's 314) came out 480 pt tall and overlapped. On 16.7.7 the engine ran with TrollPad's list (from 150: TrollPad
// -setGridHeights:), which hid this. 17+: the height list starts at 300 pt (every iPad with Stage Manager has quarters of at least 314 pt); Apple's
// own list is kept where it starts lower (TrollPad's 150). 16: Apple's minimum, as before. The diagnostics record shows Apple's first sizes.
static const CGFloat kSM17MinWindowHeight = 300.0;
static double gSMAppleGridLo[2];   // (the smallest width / height in Apple's lists, as last seen: the iPadOS 17 diagnostics record)
static NSArray<NSNumber *> *DMSMFineGrid(NSArray *orig, CGFloat full, int axis) {   // axis: 0 widths, 1 heights
    static NSMutableDictionary<NSString *, NSArray *> *cache;
    if (![orig isKindOfClass:[NSArray class]] || orig.count == 0 || !isfinite(full) || full < 100.0 || full > 20000.0) return orig;
    // (only a list of numbers, as on 16.7.7: anything else -- boxed values, objects of another kind -- is Apple's as it is; a KVC @min over it
    //  threw inside Stage Manager's layout pass, review S6)
    CGFloat lo = CGFLOAT_MAX;
    for (id x in orig) { if (![x isKindOfClass:[NSNumber class]]) return orig; lo = MIN(lo, [x doubleValue]); }
    if (!isfinite(lo) || lo < 1.0 || lo > full) return orig;
    if (axis >= 0 && axis < 2) gSMAppleGridLo[axis] = lo;
    if (axis == 1 && DMSMLayoutGen() == 17 && lo > kSM17MinWindowHeight && kSM17MinWindowHeight < full) lo = kSM17MinWindowHeight;   // (iPadOS 17+, see above)
    NSString *key = [NSString stringWithFormat:@"%.0f-%.0f", lo, full];
    NSArray *hit = cache[key];
    if (hit) return hit;
    NSMutableArray *a = [NSMutableArray arrayWithCapacity:(NSUInteger)(full - lo + 1)];
    for (CGFloat v = ceil(lo); v <= full; v += 1.0) [a addObject:@(v)];
    if (!cache) cache = [NSMutableDictionary dictionary];
    cache[key] = a;
    DMLog([NSString stringWithFormat:@"[sm] size grid %.0f..%.0f (Apple's: %lu sizes, %@ .. %@)", lo, full, (unsigned long)orig.count, orig.firstObject, orig.lastObject]);
    return a;
}
