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

// ---- one place for refusals -------------------------------------------------------------------------------------------------------------------
static NSMutableOrderedSet<NSString *> *gSMAPIFailures;   // (each kind once: "<what>: <why>")
static BOOL gSMCheckOK = NO;          // (DMSelfCheck passed: the engine may run)
static BOOL gSMCheckDone = NO;
static NSString *gSMCheckReason;      // (why not, for the log and Settings)
static void DMSMRecordRuntimeFailure(NSString *line);
static void DMSMAPIFail(NSString *what, NSString *why) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", what, why];
    if (!gSMAPIFailures) gSMAPIFailures = [NSMutableOrderedSet orderedSet];
    if ([gSMAPIFailures containsObject:line]) return;
    [gSMAPIFailures addObject:line];
    DMLog([NSString stringWithFormat:@"[smapi] REFUSED %@", line]);
    DMSMRecordRuntimeFailure(line);
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
static DMSMSigCacheEntry gSMSigCache[96];
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
DMSM_SIG(DMSMSigRequestOnDisplay, @encode(BOOL), @encode(unsigned long long), @encode(id), @encode(id))   // -requestTransitionWithOptions:displayConfiguration:builder: (YES = taken)
DMSM_SIG(DMSMSigRequest, @encode(BOOL), @encode(id))                                  // -requestTransitionWithBuilder: (YES = taken; B@:@? on 16.7.7)

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
static BOOL DMSMAttrAttributedSize(id attrs, DMSMAttributedSize *out) {
    if (!DMSMIsAttrs(attrs)) return NO;
    SEL sel = NSSelectorFromString(@"attributedSize");
    if (!DMSMSigOK(attrs, sel, DMSMSigSize(), "attributedSize")) return NO;
    DMSMAttributedSize s = ((DMSMAttributedSize (*)(id, SEL))objc_msgSend)(attrs, sel);
    if (!DMSMSizeReadSane(s)) { DMSMAPIFail(@"attributedSize", [@"not a size: " stringByAppendingString:DMSMSizeText(s)]); return NO; }
    if (out) *out = s;
    return YES;
}
static BOOL DMSMAttrCenter(id attrs, CGPoint *out) {
    if (!DMSMIsAttrs(attrs)) return NO;
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
    SEL sel = NSSelectorFromString(@"attributesByModifyingAttributedSize:");
    if (!DMSMSigOK(attrs, sel, DMSMSigWithSize(), "attributesByModifyingAttributedSize:")) return nil;
    id r = ((id (*)(id, SEL, DMSMAttributedSize))objc_msgSend)(attrs, sel, s);
    return DMSMIsAttrs(r) ? r : nil;
}
static id DMSMAttrWithCenter(id attrs, CGPoint c) {
    if (!DMSMIsAttrs(attrs)) return nil;
    if (!DMSMCenterSane(c, YES)) { DMSMAPIFail(@"attributesByModifyingNormalizedCenter:", [@"refused to hand over " stringByAppendingString:NSStringFromCGPoint(c)]); return nil; }
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
    return a;
}

// ---- SBAppLayout (a stage), its items (SBDisplayItem), the switcher's list of stages ---------------------------------------------------------------
static id DMSMCoordinator(void) {
    Class c = objc_getClass("SBMainSwitcherControllerCoordinator");
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
// The window's layout role in its stage (1 primary, 2 side, 4 centre, 5/6 additional sides -- read on 16.7.7).
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
// The switcher's model of stages, and a stage replaced in it (a window's attributes changed in place).
static id DMSMSwitcherModel(void) {
    id m = nil; @try { m = [DMSMCoordinator() valueForKey:@"_mainSwitcherModel"]; } @catch (id e) { m = nil; }
    return m;
}
static BOOL DMSMReplaceStage(id stage, id newStage) {
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
// or are rewritten by the same plan). allowed: the roles a NEW window may take (nil = any role 1..8, for windows asked for again in their own).
#if DEBUG
static int gSMSimulateWriteFail = -1;   // (debug /tmp/msb-sm-simulate-writefail: the Nth write throws, to test the roll-back)
#endif
static BOOL DMSMPlanValid(NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, NSString **why) {
    NSMutableSet *roles = [NSMutableSet set], *entities = [NSMutableSet set];
    if (!plan.count) { if (why) *why = @"empty plan"; return NO; }
    for (NSArray *en in plan) {
        if (![en isKindOfClass:[NSArray class]] || en.count != 3) { if (why) *why = @"malformed entry"; return NO; }
        id e = en[0]; long long role = [en[1] longLongValue]; id a = en[2];
        if (!DMSMIsEntity(e)) { if (why) *why = [NSString stringWithFormat:@"not an app entity: %@", NSStringFromClass([e class])]; return NO; }
        if (role < 1 || role > 8 || (allowed && ![allowed containsObject:@(role)])) { if (why) *why = [NSString stringWithFormat:@"role %lld not allowed", role]; return NO; }
        if ([roles containsObject:@(role)]) { if (why) *why = [NSString stringWithFormat:@"role %lld twice", role]; return NO; }
        if ([entities containsObject:[NSValue valueWithNonretainedObject:e]]) { if (why) *why = @"one entity twice"; return NO; }
        [roles addObject:@(role)]; [entities addObject:[NSValue valueWithNonretainedObject:e]];
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
static BOOL DMSMRequestPlan(id identity, BOOL onMain, NSString *label, NSArray<NSArray *> *plan, NSSet<NSNumber *> *allowed, id frontEntity) {
    NSString *why = nil;
    if (!DMSMPlanValid(plan, allowed, &why)) { DMSMAPIFail(@"transition plan", [NSString stringWithFormat:@"%@ refused before asking: %@", label, why]); return NO; }
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    __block BOOL wrote = NO, built = NO;
    void (^builder)(id) = ^(id req) {
        built = YES;
        SEL lab = NSSelectorFromString(@"setEventLabel:");
        if (label && [req respondsToSelector:lab] && DMSMSigOK(req, lab, DMSMSigVoidObj(), "setEventLabel:")) ((void (*)(id, SEL, id))objc_msgSend)(req, lab, label);
        SEL mod = NSSelectorFromString(@"modifyApplicationContext:");
        if (!DMSMSigOK(req, mod, DMSMSigVoidObj(), "modifyApplicationContext:")) return;
        ((void (*)(id, SEL, id))objc_msgSend)(req, mod, ^(id ctx) { @try { wrote = DMSMWritePlan(ctx, plan, frontEntity); } @catch (id e) {} });
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
typedef struct { const char *cls; const char *sel; BOOL classMethod; BOOL hooked; NSString *(*sig)(void); } DMSMNeed;
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
DMSM_SIG(DMSMSigPointInside, @encode(BOOL), @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigHitTest, @encode(id), @encode(CGPoint), @encode(id))
DMSM_SIG(DMSMSigGridSize, @encode(CGSize), @encode(CGSize), @encode(id), @encode(id), @encode(CGRect))
DMSM_SIG(DMSMSigStripHidden, @encode(BOOL), @encode(id), @encode(long long))
static const DMSMNeed kSMNeeds[] = {
    // the stage model: a window's attributes, the stage, its items
    {"SBDisplayItemLayoutAttributes", "init", NO, NO, NULL},
    {"SBDisplayItemLayoutAttributes", "lastInteractionTime", NO, NO, DMSMSigTime},
    {"SBDisplayItemLayoutAttributes", "sizingPolicy", NO, NO, DMSMSigTime},
    {"SBDisplayItemLayoutAttributes", "attributedSize", NO, NO, DMSMSigSize},
    {"SBDisplayItemLayoutAttributes", "normalizedCenter", NO, NO, DMSMSigCenter},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingAttributedSize:", NO, NO, DMSMSigWithSize},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingNormalizedCenter:", NO, NO, DMSMSigWithCenter},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingSizingPolicy:", NO, NO, DMSMSigWithLong},
    {"SBDisplayItemLayoutAttributes", "attributesByModifyingLastInteractionTime:", NO, NO, DMSMSigWithLong},
    {"SBAppLayout", "itemsToLayoutAttributesMap", NO, NO, DMSMSigObj},
    {"SBAppLayout", "layoutRoleForItem:", NO, NO, DMSMSigRole},
    {"SBAppLayout", "preferredDisplayIdentity", NO, NO, DMSMSigObj},
    {"SBAppLayout", "appLayoutByModifyingLayoutAttributes:forItem:", NO, NO, DMSMSigObjObjObj},
    {"SBAppLayout", "appLayoutByRemovingItemInLayoutRole:", NO, NO, DMSMSigWithLong},
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
    {"SBSwitcherChamoisLayoutAttributes", "containerBounds", NO, NO, DMSMSigRect},
    {"SBMutableChamoisOverlappingModel", "centerForItem:", NO, NO, DMSMSigCenterFor},
    {"SBTopAffordanceViewController", "closeAction", NO, NO, DMSMSigObj},
    {"SBTopAffordanceViewController", "removeFromSetAction", NO, NO, DMSMSigObj},
    // what our hooks replace (%group SMEngine)
    {"SpringBoard", "sendEvent:", NO, YES, DMSMSigVoidObj},
    {"SBIconView", "_handleTap", NO, YES, DMSMSigVoid},
    {"SBFullScreenContinuousExposeSwitcherModifier", "shouldConfigureInAppDockHiddenAssertion", NO, YES, DMSMSigBool},
    {"SBFluidSwitcherViewController", "_keyboardWillShow:", NO, YES, DMSMSigVoidObj},
    {"SBFluidSwitcherViewController", "_keyboardWillHide:", NO, YES, DMSMSigVoidObj},
    {"SBFluidSwitcherViewController", "_updateSoftwareKeyboardVisibleWithKeyboardShowing:", NO, YES, DMSMSigVoidBool},
    {"SBFluidSwitcherViewController", "prefersStripHidden", NO, YES, DMSMSigBool},
    {"SBSwitcherChamoisLayoutAttributes", "gridWidths", NO, YES, DMSMSigObj},
    {"SBSwitcherChamoisLayoutAttributes", "gridHeights", NO, YES, DMSMSigObj},
    {"SBSwitcherChamoisLayoutAttributes", "stageOccludedAppScale", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "stageOcclusionDodgingPeekScale", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "stageCornerRaddii", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "maximumWindowWidthForOverlapping", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisLayoutAttributes", "maximumWindowHeightWithDock", NO, YES, DMSMSigDouble},
    {"SBChamoisOverlappingController", "_stageAreaForModel:chamoisLayoutAttributes:floatingDockHeight:bounds:prefersStripHidden:prefersDockHidden:widthThresholdToHideContinuousExposeStrip:", NO, YES, DMSMSigStageArea},
    {"SBChamoisOverlappingController", "_modelByPerformingAutoLayoutForModel:chamoisLayoutAttributes:draggingItem:modelBeforeDragging:floatingDockHeight:bounds:screenScale:prefersStripHidden:prefersDockHidden:stageInset:", NO, YES, DMSMSigAutoLayout},
    {"SBChamoisOverlappingController", "_compactSpacingHorizontallyForModel:withColumns:chamoisLayoutAttributes:", NO, YES, DMSMSigVoid3},
    {"SBChamoisOverlappingController", "_compactSpacingVerticallyForModel:withColumns:chamoisLayoutAttributes:", NO, YES, DMSMSigVoid3},
    {"SBChamoisOverlappingController", "_expandSpacingHorizontallyForModel:withColumns:modelBeforeDragging:chamoisLayoutAttributes:draggingItem:stageArea:", NO, YES, DMSMSigExpandH},
    {"SBChamoisOverlappingController", "_expandSpacingVerticallyForModel:withColumns:chamoisLayoutAttributes:stageArea:", NO, YES, DMSMSigExpandV},
    {"SBChamoisOverlappingController", "_horizontallyCenterModel:stageArea:", NO, YES, DMSMSigCenterH},
    {"SBChamoisOverlappingController", "_verticallyCenterModel:withColumns:stageArea:", NO, YES, DMSMSigCenterV},
    {"SBChamoisOverlappingController", "_dodgeFullyOccludedWindowsToNearestVisibleEdgeInModel:chamoisLayoutAttributes:draggingItem:bounds:", NO, YES, DMSMSigDodge},
    {"SBChamoisOverlappingController", "_snapPositionToNearestEdgesIfNecessary:draggingItem:", NO, YES, DMSMSigVoidObjObj},
    {"SBMutableChamoisOverlappingModel", "setCenter:forItem:", NO, YES, DMSMSigSetCenter},
    {"SBWorkspaceApplicationSceneTransitionContext", "finalize", NO, YES, DMSMSigVoid},
    {"SBAppResizeGrabberView", "setAlpha:", NO, YES, DMSMSigVoidDouble},
    {"SBAppResizeGrabberView", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBAppSwitcherPageView", "setMaskedCorners:", NO, YES, DMSMSigVoidULL},
    {"SBAppSwitcherPageView", "maskedCorners", NO, NO, DMSMSigULL},
    {"SBAppSwitcherPageView", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBFluidSwitcherItemContainer", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBReusableSnapshotItemContainer", "layoutSubviews", NO, YES, DMSMSigVoid},
    {"SBReusableSnapshotItemContainer", "setAccessibilityIdentifier:", NO, YES, DMSMSigVoidObj},
    {"SBReusableSnapshotItemContainer", "didMoveToWindow", NO, YES, DMSMSigVoid},
    {"SBReusableSnapshotItemContainer", "pointInside:withEvent:", NO, YES, DMSMSigPointInside},
    {"SBReusableSnapshotItemContainer", "hitTest:withEvent:", NO, YES, DMSMSigHitTest},
    {"SBTopAffordanceDotsView", "setAlpha:", NO, YES, DMSMSigVoidDouble},
    {"SBSwitcherChamoisSettings", "_nearestGridSizeForSize:gridWidths:gridHeights:bounds:", NO, YES, DMSMSigGridSize},
    {"SBSwitcherChamoisSettings", "_statusBarHeight", NO, YES, DMSMSigDouble},
    {"SBSwitcherChamoisSettings", "_shouldPreferStripHiddenForWindowScene:interfaceOrientation:", NO, YES, DMSMSigStripHidden},
};
static const size_t kSMNeedsCount = sizeof(kSMNeeds) / sizeof(kSMNeeds[0]);
// Checks every row: the classes and methods are there, with the signatures we use. Returns the list of what is missing or different (empty = all
// there). simulate (debug): "selector" / "encoding" pretend one row is missing / different.
static NSArray<NSString *> *DMSMCheckAPI(NSString *simulate, NSUInteger *checked) {
    NSMutableArray *bad = [NSMutableArray array];
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        DMSMNeed n = kSMNeeds[i];
        Class c = objc_getClass(n.cls);
        if (!c) { NSString *s = [NSString stringWithFormat:@"class %s missing", n.cls]; if (![bad containsObject:s]) [bad addObject:s]; continue; }
        SEL sel = sel_registerName(n.sel);
        if (!strcmp(n.sel, "attributesByModifyingAttributedSize:") && [simulate isEqualToString:@"selector"]) sel = sel_registerName("attributesByModifyingAttributedSize_simulatedMissing:");
        Method m = n.classMethod ? class_getClassMethod(c, sel) : class_getInstanceMethod(c, sel);
        if (!m) { [bad addObject:[NSString stringWithFormat:@"%c[%s %s] missing", n.classMethod ? '+' : '-', n.cls, sel_getName(sel)]]; continue; }
        if (n.sig) {
            NSString *have = DMSMSigOfMethod(m), *want = n.sig();
            if (!strcmp(n.sel, "attributedSize") && [simulate isEqualToString:@"encoding"]) have = DMSMNormEncoding("{SBDisplayItemAttributedSize={CGSize=dd}q}16@0:8");   // (a layout without referenceBounds, review S3)
            if (![have isEqualToString:want]) [bad addObject:[NSString stringWithFormat:@"-[%s %s] is %@, we use %@", n.cls, n.sel, have, want]];
        }
        if (checked) (*checked)++;
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
    return bad;
}
// The hooked methods' current implementations (to see afterwards that our hooks really went in).
static NSArray<NSValue *> *DMSMHookedIMPs(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        if (!kSMNeeds[i].hooked) continue;
        Class c = objc_getClass(kSMNeeds[i].cls);
        Method m = c ? class_getInstanceMethod(c, sel_registerName(kSMNeeds[i].sel)) : NULL;
        [a addObject:[NSValue valueWithPointer:m ? (const void *)method_getImplementation(m) : NULL]];
    }
    return a;
}
static NSArray<NSString *> *DMSMHooksNotInstalled(NSArray<NSValue *> *before, BOOL simulate) {
    NSArray *after = DMSMHookedIMPs();
    NSMutableArray *bad = [NSMutableArray array];
    NSUInteger k = 0;
    for (size_t i = 0; i < kSMNeedsCount; i++) {
        if (!kSMNeeds[i].hooked) continue;
        BOOL same = k < before.count && k < after.count && [before[k] isEqual:after[k]];
        if (same || (simulate && k == 0)) [bad addObject:[NSString stringWithFormat:@"hook on -[%s %s] not installed", kSMNeeds[i].cls, kSMNeeds[i].sel]];
        k++;
    }
    return bad;
}
// The verdict for the other processes (common/StageManagerAvailable.h): this iPadOS build, passed or not, a short reason, the list.
static void DMSMPublishVerdict(BOOL ok, NSString *reason, NSArray<NSString *> *details) {
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"build"] = MSBDOSBuild() ?: @"";
    v[@"os"] = [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"";
    v[@"ok"] = @(ok);
    if (reason) v[@"reason"] = reason;
    if (details.count) v[@"details"] = details.count > 16 ? [details subarrayWithRange:NSMakeRange(0, 16)] : details;
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
static long long DMSMRoleOr(id stage, id item, long long dflt) { long long r = dflt; return DMSMStageRoleOfItem(stage, item, &r) ? r : dflt; }
static long long DMSMPolicyOr(id attrs, long long dflt) { long long p = dflt; return DMSMAttrSizingPolicy(attrs, &p) ? p : dflt; }
