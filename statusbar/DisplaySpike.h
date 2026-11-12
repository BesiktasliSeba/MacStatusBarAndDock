// DisplaySpike.h -- 1.8.7 commit 1, DEBUG ONLY (plans/design-1.8.7-displays.md section 10 row 1): the spike triggers S1-S6 for the per-display
// settings and the Mac Switcher on the TV. Included from StatusBar.x inside the test machinery (#if DEBUG): never in a release build.
// Nothing here writes a preference. What acts, and how it is undone:
//  - dispscale_set_<n>: Apple's own per-display scale (SBSExternalDisplayService, what Settings calls), refused unless iPadOS lists that scale for
//    the display and it is not the one in use; dispscale_restore sets the scale read before back the same way;
//  - tvdesk_empty_<a|b|c>: one transition on the TV's display (its windows' roles empty); the TV's windows come back from its Dock;
//  - dockhide_tv_<0|1|2>: an in-memory answer of the in-app Dock question (StatusBar.x, the switcher modifier's hook), 0 or a respring clears it;
//  - tvhover_on: hover recognizers on SpringBoard's windows on the TV, logging only; tvhover_off (or a respring) removes them.
// Triggers:
//  dispinfo / dispinfo_methods   S1, S6: CADisplay (uniqueId, name, deviceName, modes, overscan), each UIScreen's display configuration (fields,
//                                hardwareIdentifier against the CADisplay uniqueId), the identity, SpringBoard's own connected-display info, the
//                                stored SBDisplayModeSettings keys (read only), the key 1.8.7 would derive, each bar copy's visual provider class
//  dispscale_read / _set_<n> / _restore   S2: the scales iPadOS lists (bitmask decoded, Apple's own names), set one, put the old one back
//  dispscale_shape / dispscale_shape_call  the setter's real shape (review of commit 13): its completion block's parameters and the class its
//                                forDisplay: takes, from the extended type encodings of every protocol that names it (nothing called); _call
//                                also calls it with the scale already in use (listed, so no assertion; nothing changes) and a block that takes two
//                                raw pointers and logs them and their classes (only a pointer that is an object is looked into)
//  tvdesk_state / tvdesk_empty_<a|b|c>    S3: the TV's layout state and stages; an empty TV desktop asked with the stages kept
//  dockhide_tv_<0|1|2> / dockhide_state   S5: the in-app Dock answer forced for the TV's stage only (1) or the iPad's only (2); each Dock's place
//  tvhover_on / tvhover_off               S4: does hover reach SpringBoard's windows on the TV; backboardd's pointer with each sample
#if DEBUG
static BOOL DMSMStageShownOnDisplay(id al, id identity);
static id DMSMFrontStageOnDisplay(id identity);

static NSString *DMDSLine(id o) {
    NSString *d = o ? [o description] : @"(nil)";
    d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    while ([d containsString:@"  "]) d = [d stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    return d;
}
// A no-argument getter's value (KVC boxes scalars and structs), only when the object answers it: "<none>" when it does not.
static id DMDSGet(id o, NSString *name) {
    if (!o) return @"(nil)";
    if (!name.length || [name containsString:@":"] || [name isEqualToString:@"isa"]) return @"<refused>";
    SEL s = NSSelectorFromString(name);
    if (![o respondsToSelector:s]) return @"<none>";
    Method m = class_getInstanceMethod(object_getClass(o), s);
    if (!m || method_getNumberOfArguments(m) != 2) return @"<args>";
    @try { id v = [o valueForKey:name]; return v ?: @"(nil)"; } @catch (NSException *e) { return [NSString stringWithFormat:@"<%@>", e.reason]; }
}
// A real string value: DMDSGet's own words for nil or no getter are not one (the iPad's nil uniqueId and nil hardwareIdentifier were "equal", 11 Nov d01).
static NSString *DMDSStr(id v) {
    if (![v isKindOfClass:[NSString class]] || ![v length]) return nil;
    for (NSString *w in @[@"(nil)", @"<none>", @"<args>", @"<refused>"]) if ([v isEqualToString:w]) return nil;
    return [v hasPrefix:@"<"] && [v hasSuffix:@">"] ? nil : v;
}
static NSString *DMDSFields(id o, NSArray<NSString *> *names) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *n in names) {
        id v = DMDSGet(o, n);
        if ([v isKindOfClass:[NSString class]] && [v isEqualToString:@"<none>"]) continue;
        [out addObject:[NSString stringWithFormat:@"%@=%@", n, DMDSLine(v)]];
    }
    return [out componentsJoinedByString:@"; "];
}
static NSString *DMDSPropertyNames(Class c) {
    NSMutableArray *names = [NSMutableArray array];
    for (Class k = c; k && k != [NSObject class]; k = class_getSuperclass(k)) {
        unsigned int n = 0; objc_property_t *ps = class_copyPropertyList(k, &n);
        for (unsigned int i = 0; i < n; i++) [names addObject:[NSString stringWithUTF8String:property_getName(ps[i])]];
        free(ps);
    }
    return [names componentsJoinedByString:@","];
}
static NSString *DMDSMethods(const char *cn, NSString *filter) {
    Class k = objc_getClass(cn);
    if (!k) return [NSString stringWithFormat:@"class %s: absent", cn];
    NSMutableArray *names = [NSMutableArray array];
    for (int meta = 0; meta < 2; meta++) {
        unsigned int n = 0; Method *ms = class_copyMethodList(meta ? object_getClass(k) : k, &n);
        for (unsigned int j = 0; j < n; j++) {
            NSString *s = [NSString stringWithUTF8String:sel_getName(method_getName(ms[j]))];
            if (filter.length && [s rangeOfString:filter options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location == NSNotFound) continue;
            [names addObject:[NSString stringWithFormat:@"%@%@ %s", meta ? @"+" : @"-", s, method_getTypeEncoding(ms[j]) ?: ""]];
        }
        free(ms);
    }
    return [NSString stringWithFormat:@"class %s: %lu methods%@: %@", cn, (unsigned long)names.count, filter.length ? [NSString stringWithFormat:@" matching %@", filter] : @"", [names componentsJoinedByString:@" | "]];
}
static NSArray *DMDSCADisplays(void) {
    Class CAD = objc_getClass("CADisplay");
    SEL s = sel_registerName("displays");
    id all = CAD && [CAD respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(CAD, s) : nil;
    return [all isKindOfClass:[NSArray class]] ? all : @[];
}
// The display key as 1.8.7 would make it (design section 2): u-<CADisplay uniqueId, upper case>, else "any".
static NSString *DMDSKeyOf(id uniqueId) {
    NSString *u = DMDSStr(uniqueId);
    return u ? [@"u-" stringByAppendingString:[u uppercaseString]] : @"any";
}
static id DMDSCADisplayFor(id cfg) {   // the CADisplay a display configuration stands for: its hardwareIdentifier = uniqueId, else the same name / deviceName
    id hw = DMDSGet(cfg, @"hardwareIdentifier"), nm = DMDSGet(cfg, @"name"), dn = DMDSGet(cfg, @"deviceName");
    for (id d in DMDSCADisplays()) {
        id u = DMDSGet(d, @"uniqueId");
        if (DMDSStr(hw) && DMDSStr(u) && [hw caseInsensitiveCompare:u] == NSOrderedSame) return d;
    }
    for (id d in DMDSCADisplays()) {
        id n = DMDSGet(d, @"name"), e = DMDSGet(d, @"deviceName");
        if ((DMDSStr(dn) && [dn isEqual:e]) || (DMDSStr(nm) && [nm isEqual:n])) return d;
    }
    return nil;
}
static NSString *DMDSScaleBits(unsigned long long mask) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 16; i++) if (mask & (1ULL << i)) [a addObject:@(i)];
    return a.count ? [a componentsJoinedByString:@","] : @"none";
}
static id gDMDSClient;   // (SpringBoard's own client of the external display service, kept while its answer is pending)
static void DMDSConnectedInfo(void (^done)(NSArray *infos)) {
    Class K = objc_getClass("SBSExternalDisplayService");
    SEL g = sel_registerName("getConnectedDisplayInfoWithCompletionHandler:");
    if (!gDMDSClient && K) gDMDSClient = [K new];
    if (!gDMDSClient || ![gDMDSClient respondsToSelector:g]) { DMLog(@"[dispinfo] no SBSExternalDisplayService -getConnectedDisplayInfoWithCompletionHandler:"); if (done) done(@[]); return; }
    Method m = class_getInstanceMethod(object_getClass(gDMDSClient), g);
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v24@0:8@?16")) { DMLog([NSString stringWithFormat:@"[dispinfo] getConnectedDisplayInfo: unexpected types %s", m ? method_getTypeEncoding(m) : "-"]); if (done) done(@[]); return; }
    void (^copy)(NSArray *) = [done copy];
    ((void (*)(id, SEL, id))objc_msgSend)(gDMDSClient, g, ^(NSArray *infos, id err) {
        if (err) DMLog([NSString stringWithFormat:@"[dispinfo] connected display info error: %@", DMDSLine(err)]);
        NSArray *list = [infos isKindOfClass:[NSArray class]] ? infos : @[];
        dispatch_async(dispatch_get_main_queue(), ^{ if (copy) copy(list); });
    });
}

// ---- S1 / S6: dispinfo ----------------------------------------------------------------------------------------------------------------------------
static void DMDSInfo(BOOL methods) {
    NSArray *cads = DMDSCADisplays();
    for (id d in cads) {
        id modes = DMDSGet(d, @"availableModes");
        DMLog([NSString stringWithFormat:@"[dispinfo] CADisplay %@ (%@): uniqueId %@, displayId %@, key %@, route %@; current %@, preferred %@, %lu modes; %@",
               DMDSGet(d, @"name"), DMDSGet(d, @"deviceName"), DMDSGet(d, @"uniqueId"), DMDSGet(d, @"displayId"), DMDSKeyOf(DMDSGet(d, @"uniqueId")),
               [[DMDSGet(d, @"deviceName") description] hasPrefix:@"wireless"] ? @"encoded" : ([[DMDSGet(d, @"deviceName") description] isEqualToString:@"primary"] ? @"(the iPad)" : @"direct"),
               DMDSLine(DMDSGet(d, @"currentMode")), DMDSLine(DMDSGet(d, @"preferredMode")), (unsigned long)([modes isKindOfClass:[NSArray class]] ? [modes count] : 0),
               DMDSFields(d, @[@"isOverscanned", @"overscanAmount", @"overscanAdjustment", @"productName", @"isExternal", @"type", @"tag", @"connectionSeed", @"processId", @"isCloned", @"cloningSupported", @"uniqueIdentifier", @"hardwareIdentifier"])]);
    }
    NSArray *cfgFields = @[@"name", @"deviceName", @"hardwareIdentifier", @"uniqueId", @"uniqueIdentifier", @"displayID", @"identity", @"pointScale", @"bounds", @"pixelSize",
                           @"currentMode", @"preferredMode", @"isExternal", @"isMainDisplay", @"isMainRootDisplay", @"isRootDisplay", @"isCarDisplay", @"isCarInstrumentsDisplay",
                           @"isAirPlayDisplay", @"isContinuityDisplay", @"isHiddenDisplay", @"isMusicOnlyDisplay", @"isUIKitMainLike", @"isCloningSupported", @"isConnected",
                           @"isMirroringSupported", @"overscanned", @"isOverscanned", @"overscanCompensation", @"safeOverscanRatio", @"tags", @"productName", @"seed",
                           @"renderingCenter", @"type", @"connectionType", @"colorGamut", @"refreshRate"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIScreen *s in [UIScreen screens]) {
        id cfg = [s respondsToSelector:NSSelectorFromString(@"displayConfiguration")] ? DMCall(s, @"displayConfiguration") : nil;
        id cad = cfg ? DMDSCADisplayFor(cfg) : nil;
        id hw = DMDSGet(cfg, @"hardwareIdentifier"), u = cad ? DMDSGet(cad, @"uniqueId") : nil;
        BOOL hwIsUnique = DMDSStr(hw) && DMDSStr(u) && [hw caseInsensitiveCompare:u] == NSOrderedSame;
        DMLog([NSString stringWithFormat:@"[dispinfo] screen %p%@ %@ scale %.2f native %@ @%.2f: configuration %@ -> CADisplay %@; hardwareIdentifier %@ the uniqueId; key %@",
               s, s == [UIScreen mainScreen] ? @" (main)" : @"", NSStringFromCGRect(s.bounds), s.scale, NSStringFromCGRect(s.nativeBounds), s.nativeScale,
               cfg ? NSStringFromClass([cfg class]) : @"none", cad ? DMDSGet(cad, @"name") : @"none", hwIsUnique ? @"EQUALS" : @"is NOT", DMDSKeyOf(hwIsUnique ? hw : u)]);
        if (cfg) DMLog([NSString stringWithFormat:@"[dispinfo]   configuration fields: %@", DMDSFields(cfg, cfgFields)]);
        id ident = cfg ? DMCall(cfg, @"identity") : nil;
        if (ident) DMLog([NSString stringWithFormat:@"[dispinfo]   identity %@: %@ (%@)", NSStringFromClass([ident class]), DMDSLine(ident),
                          DMDSFields(ident, @[@"displayID", @"type", @"rootIdentity", @"isRootIdentity", @"isExternal", @"isMainDisplay", @"connectionType", @"expectsSecureRendering", @"isCarDisplay"])]);
        if (methods && cfg) DMLog([NSString stringWithFormat:@"[dispinfo]   %@ properties: %@", NSStringFromClass([cfg class]), DMDSPropertyNames([cfg class])]);
        if (methods && ident) DMLog([NSString stringWithFormat:@"[dispinfo]   %@ properties: %@", NSStringFromClass([ident class]), DMDSPropertyNames([ident class])]);
    }
#pragma clang diagnostic pop
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIScreen *scr = ((UIWindowScene *)sc).screen;
        DMLog([NSString stringWithFormat:@"[dispinfo] scene %@ %p on screen %p%@ %@", NSStringFromClass([sc class]), sc, scr, scr == [UIScreen mainScreen] ? @" (main)" : @"", NSStringFromCGRect(scr.bounds)]);
    }
    id stored = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SBDisplayModeSettings"), CFSTR("com.apple.springboard"));
    DMLog([NSString stringWithFormat:@"[dispinfo] SpringBoard's stored SBDisplayModeSettings (read only): %@", [stored isKindOfClass:[NSDictionary class]] ? DMDSLine(stored) : @"none"]);
    // (S6: each bar copy's visual provider: the TV's on 18.5 is SystemStatusUI's, its name read here; 16.7.7's is UIKit's _ExternalPad)
    NSMutableSet *seen = [NSMutableSet set];
    for (NSHashTable *copies in @[gCopies ?: [NSHashTable weakObjectsHashTable], gAllBarCopies ?: [NSHashTable weakObjectsHashTable]]) for (UIView *fg in copies.allObjects) {
        UIScreen *scr = fg.window.screen;
        id bar = fg.superview, vp = bar ? DMBarSizeObjectOf(bar, "visualProvider") : nil;
        Class vc = vp ? object_getClass(vp) : Nil;
        NSString *line = [NSString stringWithFormat:@"%@ | %@ | %@", scr == [UIScreen mainScreen] ? @"iPad" : @"TV", bar ? NSStringFromClass([bar class]) : @"-", vc ? NSStringFromClass(vc) : @"no provider"];
        if ([seen containsObject:line]) continue;
        [seen addObject:line];
        NSMutableArray *chain = [NSMutableArray array];
        for (Class k = vc ? class_getSuperclass(vc) : Nil; k && k != [NSObject class] && chain.count < 4; k = class_getSuperclass(k)) [chain addObject:NSStringFromClass(k)];
        Method hm = vc ? class_getClassMethod(vc, sel_registerName("height")) : NULL;
        double h = hm && !strcmp(method_getTypeEncoding(hm) ?: "", "d16@0:8") ? ((double (*)(id, SEL))objc_msgSend)((id)vc, sel_registerName("height")) : -1;
        DMLog([NSString stringWithFormat:@"[dispinfo] bar on the %@: bar %@, provider %@ (%@), +height %.1f, copy height %.1f, screen %@", scr == [UIScreen mainScreen] ? @"iPad" : @"TV",
               bar ? NSStringFromClass([bar class]) : @"-", vc ? NSStringFromClass(vc) : @"none", [chain componentsJoinedByString:@" < "], h, fg.bounds.size.height, scr ? NSStringFromCGRect(scr.bounds) : @"none"]);
    }
    if (methods) {
        const char *const classes[] = { "SBSExternalDisplayService", "SBSConnectedDisplayInfo", "SBSDisplayModeSettings", "SBExternalDisplayService", "FBSDisplayConfiguration", "CADisplay" };
        for (size_t c = 0; c < sizeof(classes) / sizeof(classes[0]); c++) DMLog([NSString stringWithFormat:@"[dispinfo] %@", DMDSMethods(classes[c], nil)]);
        DMLog([NSString stringWithFormat:@"[dispinfo] %@", DMDSMethods("BKSMousePointerService", @"isplay|osition")]);
    }
    DMDSConnectedInfo(^(NSArray *infos) {
        for (id i in infos) {
            id ident = DMDSGet(i, @"identifier"), st = DMDSGet(i, @"displayModeSettings"), mask = DMDSGet(i, @"supportedScales");
            NSString *match = @"no CADisplay";
            for (id d in DMDSCADisplays()) { id u = DMDSGet(d, @"uniqueId"); if (DMDSStr(u) && DMDSStr(ident) && [u caseInsensitiveCompare:ident] == NSOrderedSame) match = [NSString stringWithFormat:@"= CADisplay %@'s uniqueId", DMDSGet(d, @"name")]; }
            DMLog([NSString stringWithFormat:@"[dispinfo] SpringBoard's connected display: identifier %@ (%@), displayName %@, deviceName %@, size %@, mirrored %@, supportedScales %@ (bits %@), settings %@ (scale %@, overscanCompensation %@), arrangement %@",
                   ident, match, DMDSGet(i, @"displayName"), DMDSGet(i, @"deviceName"), DMDSLine(DMDSGet(i, @"size")), DMDSGet(i, @"mirrored"), mask,
                   [mask isKindOfClass:[NSNumber class]] ? DMDSScaleBits([mask unsignedLongLongValue]) : @"?", DMDSLine(st), DMDSGet(st, @"scale"), DMDSGet(st, @"overscanCompensation"), DMDSLine(DMDSGet(i, @"arrangement"))]);
        }
        DMLog([NSString stringWithFormat:@"[dispinfo] %lu connected display(s) in SpringBoard's own info; %lu CADisplay(s); %lu screen(s)", (unsigned long)infos.count, (unsigned long)DMDSCADisplays().count, (unsigned long)[UIScreen screens].count]);
    });
}

// ---- S2: dispscale ----------------------------------------------------------------------------------------------------------------------------
static id gDMDSScaleOld;            // (the settings read before our set: what restore puts back)
static NSString *gDMDSScaleDisplay; // (the display they belong to: SpringBoard's identifier)
static void DMDSScaleApply(id settings, NSString *display, NSString *why) {
    SEL set = sel_registerName("setSettings:forDisplay:options:completionHandler:");
    Method m = gDMDSClient ? class_getInstanceMethod(object_getClass(gDMDSClient), set) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v48@0:8@16@24Q32@?40")) { DMLog([NSString stringWithFormat:@"[dispscale] %@: no setter of the read types (%s)", why, m ? method_getTypeEncoding(m) : "-"]); return; }
    DMLog([NSString stringWithFormat:@"[dispscale] %@: asking SpringBoard for %@ on %@", why, DMDSLine(settings), display]);
    ((void (*)(id, SEL, id, id, unsigned long long, id))objc_msgSend)(gDMDSClient, set, settings, display, 0ULL, ^{   // (its parameters never read: none taken -- dispscale_shape reads them)
        dispatch_async(dispatch_get_main_queue(), ^{ DMLog([NSString stringWithFormat:@"[dispscale] %@: answered", why]); });
    });
}
// A raw pointer an unknown block was called with, described without taking it for an object unless it is one: NULL, a small value, a tagged pointer
// (its class), a heap block (its class), else not looked into.
static NSString *DMDSRawArg(void *p) {
    uintptr_t v = (uintptr_t)p;
    if (!p) return @"NULL";
    if ((intptr_t)v < 0) return [NSString stringWithFormat:@"%p (a tagged pointer, %s)", p, object_getClassName((__bridge id)p)];
    if (v < 0x100000000ULL) return [NSString stringWithFormat:@"%p (a small value: not an object)", p];
    if (!malloc_zone_from_ptr(p) || malloc_size(p) < 16) return [NSString stringWithFormat:@"%p (not a heap block of an object's size: not looked into)", p];
    uintptr_t isa = *(uintptr_t *)p & 0x0000000ffffffff8ULL;   // (arm64's isa mask: the class pointer, never followed before it is found among the classes)
    unsigned n = 0; BOOL known = NO;
    Class *all = objc_copyClassList(&n);
    for (unsigned i = 0; i < n && !known; i++) if ((uintptr_t)(__bridge void *)all[i] == isa) known = YES;
    free(all);
    if (!known) return [NSString stringWithFormat:@"%p (a heap block whose first word is no class: not an object)", p];
    id o = (__bridge id)p;
    return [NSString stringWithFormat:@"%p (%s: %@)", p, object_getClassName(o), DMDSLine(o)];
}
// The setter's shape as declared: every protocol whose name has ExternalDisplay and declares -setSettings:forDisplay:options:completionHandler:, with
// its extended type encoding (the classes of its objects and its completion block's own parameters), the runtime's private reader through dlsym.
static void DMDSScaleShape(BOOL call) {
    SEL set = sel_registerName("setSettings:forDisplay:options:completionHandler:");
    const char *(*ext)(Protocol *, SEL, BOOL, BOOL) = (const char *(*)(Protocol *, SEL, BOOL, BOOL))dlsym(RTLD_DEFAULT, "_protocol_getMethodTypeEncoding");
    unsigned n = 0, found = 0;
    Protocol * __unsafe_unretained *list = objc_copyProtocolList(&n);
    for (unsigned i = 0; i < n; i++) {
        const char *name = protocol_getName(list[i]);
        if (!strstr(name, "ExternalDisplay")) continue;
        for (int req = 1; req >= 0; req--) {
            struct objc_method_description d = protocol_getMethodDescription(list[i], set, req, YES);
            if (!d.name) continue;
            found++;
            DMLog([NSString stringWithFormat:@"[dispscale] shape: <%s> (%s) -setSettings:forDisplay:options:completionHandler: %s | extended: %s", name, req ? "required" : "optional", d.types ?: "?", ext ? (ext(list[i], set, req, YES) ?: "none") : "no reader"]);
        }
    }
    free(list);
    Method m = gDMDSClient ? class_getInstanceMethod(object_getClass(gDMDSClient), set) : class_getInstanceMethod(objc_getClass("SBSExternalDisplayService"), set);
    DMLog([NSString stringWithFormat:@"[dispscale] shape: %u protocol(s) declare the setter; the client's method %s", found, m ? method_getTypeEncoding(m) : "missing"]);
    if (!call) return;
    DMDSConnectedInfo(^(NSArray *infos) {
        Class SC = objc_getClass("SBSDisplayModeSettings");
        SEL init = sel_registerName("initWithScale:overscanCompensation:");
        Method im = SC ? class_getInstanceMethod(SC, init) : NULL;
        Method sm = gDMDSClient ? class_getInstanceMethod(object_getClass(gDMDSClient), set) : NULL;
        if (!im || strcmp(method_getTypeEncoding(im) ?: "", "@32@0:8Q16q24") || !sm || strcmp(method_getTypeEncoding(sm) ?: "", "v48@0:8@16@24Q32@?40")) { DMLog(@"[dispscale] shape call: the settings or the setter not of the read shape: nothing asked"); return; }
        for (id i in infos) {
            id ident = DMDSGet(i, @"identifier"), st = DMDSGet(i, @"displayModeSettings"), mask = DMDSGet(i, @"supportedScales"), cur = DMDSGet(st, @"scale"), ov = DMDSGet(st, @"overscanCompensation");
            unsigned long long bits = [mask isKindOfClass:[NSNumber class]] ? [mask unsignedLongLongValue] : 0;
            int now = [cur isKindOfClass:[NSNumber class]] ? [cur intValue] : -1;
            if (!DMDSStr(ident) || ![ov isKindOfClass:[NSNumber class]] || now < 1 || now > 15 || !(bits & (1ULL << now))) { DMLog([NSString stringWithFormat:@"[dispscale] shape call: %@: the scale in use (%@) is not listed (%llu): nothing asked", ident, cur, bits]); continue; }
            id same = nil;
            @try { same = ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([SC alloc], init, (unsigned long long)now, [ov longLongValue]); } @catch (NSException *e) { continue; }
            DMLog([NSString stringWithFormat:@"[dispscale] shape call: %@ (forDisplay: we pass a %@; SpringBoard's info identifier is a %@): the scale in use, %d, asked again", ident, NSStringFromClass([ident class]), NSStringFromClass([DMDSGet(i, @"identifier") class]), now]);
            void (^shape)(void *, void *) = ^(void *a, void *b) {
                NSString *line = [NSString stringWithFormat:@"[dispscale] shape call: answered with %@ and %@ (%s thread)", DMDSRawArg(a), DMDSRawArg(b), pthread_main_np() ? "main" : "other"];
                dispatch_async(dispatch_get_main_queue(), ^{ DMLog(line); });
            };
            ((void (*)(id, SEL, id, id, unsigned long long, id))objc_msgSend)(gDMDSClient, set, same, ident, 0ULL, (id)shape);
        }
    });
}
static void DMDSScale(NSString *arg) {
    BOOL setting = [arg hasPrefix:@"set_"], restoring = [arg isEqualToString:@"restore"];
    int want = setting ? [[arg substringFromIndex:4] intValue] : -1;
    if (restoring) {
        if (!gDMDSScaleOld || !gDMDSScaleDisplay.length) { DMLog(@"[dispscale] restore: nothing was set by dispscale_set in this SpringBoard"); return; }
        DMDSScaleApply(gDMDSScaleOld, gDMDSScaleDisplay, @"restore");
        gDMDSScaleOld = nil; gDMDSScaleDisplay = nil;
        return;
    }
    DMDSConnectedInfo(^(NSArray *infos) {
        Class SC = objc_getClass("SBSDisplayModeSettings");
        SEL init = sel_registerName("initWithScale:overscanCompensation:");
        Method im = SC ? class_getInstanceMethod(SC, init) : NULL;
        BOOL canMake = im && !strcmp(method_getTypeEncoding(im) ?: "", "@32@0:8Q16q24");
        for (id i in infos) {
            id ident = DMDSGet(i, @"identifier"), st = DMDSGet(i, @"displayModeSettings"), mask = DMDSGet(i, @"supportedScales");
            unsigned long long bits = [mask isKindOfClass:[NSNumber class]] ? [mask unsignedLongLongValue] : 0;
            id cur = DMDSGet(st, @"scale"), ov = DMDSGet(st, @"overscanCompensation");
            // (Apple's own names: only the scales iPadOS lists for this display are made and described, nothing set. A value it does not list
            //  -- 0 -- fails SpringBoardServices' assertion in -initWithScale:overscanCompensation: and aborted SpringBoard: A12Z 18.5, d01, 08:55)
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned long long v = 1; canMake && v < 16; v++) {
                if (!(bits & (1ULL << v))) continue;
                @try {
                    id o = ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([SC alloc], init, v, 0LL);
                    [names addObject:[NSString stringWithFormat:@"%llu=%@", v, DMDSLine(DMDSGet(o, @"description"))]];
                } @catch (NSException *e) { [names addObject:[NSString stringWithFormat:@"%llu=<%@>", v, e.reason]]; }
            }
            DMLog([NSString stringWithFormat:@"[dispscale] %@ (%@): supportedScales %llu = scales %@ (Apple's names: %@); in use %@ (scale %@, overscan %@)", ident, DMDSGet(i, @"displayName"), bits, DMDSScaleBits(bits),
                   names.count ? [names componentsJoinedByString:@" | "] : (canMake ? @"none listed" : @"SBSDisplayModeSettings not of the read shape"), DMDSLine(st), cur, ov]);
            if (!setting) continue;
            if (want < 0 || want > 15 || !(bits & (1ULL << want))) { DMLog([NSString stringWithFormat:@"[dispscale] set %d on %@: REFUSED, iPadOS does not list it (scales %@)", want, ident, DMDSScaleBits(bits)]); continue; }
            if ([cur isKindOfClass:[NSNumber class]] && [cur intValue] == want) { DMLog([NSString stringWithFormat:@"[dispscale] set %d on %@: already in use, nothing asked", want, ident]); continue; }
            if (!canMake || !DMDSStr(ident) || ![ov isKindOfClass:[NSNumber class]]) { DMLog(@"[dispscale] set: the settings or the display can't be read whole: nothing asked"); continue; }
            gDMDSScaleOld = st; gDMDSScaleDisplay = ident;
            id now = nil;
            @try { now = ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([SC alloc], init, (unsigned long long)want, [ov longLongValue]); }
            @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[dispscale] set %d: SpringBoardServices refused the settings (%@): nothing asked", want, e.reason]); gDMDSScaleOld = nil; gDMDSScaleDisplay = nil; continue; }
            DMDSScaleApply(now, ident, [NSString stringWithFormat:@"set %d", want]);
        }
        if (!infos.count) DMLog(@"[dispscale] no connected display in SpringBoard's info");
    });
}

// ---- S3: tvdesk ----------------------------------------------------------------------------------------------------------------------------------
// The TV's screen that SpringBoard's own scene is on (its shell UI: bar, Dock, windows). UIKit lists three screens for one TV on 18.5 (AirPlay[2-3],
// its shellui one and its noninteractive one, A12Z d01): the first of them held no scene and the TV read as "no stages" (11 Nov, 08:58).
static UIScreen *DMDSTV(void) {
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes)
        if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen && ((UIWindowScene *)sc).screen != [UIScreen mainScreen]) return ((UIWindowScene *)sc).screen;
    for (UIScreen *sc in [UIScreen screens]) if (sc != [UIScreen mainScreen]) return sc;
    return nil;
}
static void DMDSTVState(NSString *label) {
    UIScreen *tv = DMDSTV();
    if (!tv) { DMLog([NSString stringWithFormat:@"[tvdesk] %@: no TV connected", label]); return; }
    id identity = DMSMIdentityOfScreen(tv);
    id coord = DMSMCoordinator();
    SEL forScene = NSSelectorFromString(@"switcherControllerForWindowScene:");
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]] || ((UIWindowScene *)sc).screen != tv) continue;
        id ctl = [coord respondsToSelector:forScene] && DMSMSigOK(coord, forScene, DMSMSigObjObj(), "switcherControllerForWindowScene:") ? ((id (*)(id, SEL, id))objc_msgSend)(coord, forScene, sc) : nil;
        id state = DMCall(DMCall(DMCall(ctl, @"contentViewController"), @"layoutContext"), @"layoutState");
        long long env = -1; id shown = nil;
        BOOL read = state && DMSMHomeStateOf(state, &env, &shown);
        NSMutableArray *names = [NSMutableArray array];
        for (id it in DMSMStageItemsMap(shown)) [names addObject:DMSMKeyText(DMSMItemKey(it)) ?: @"?"];
        DMLog([NSString stringWithFormat:@"[tvdesk] %@: TV scene %p, switcher %@, layout state %@ (read %d): environment %lld, stage %@", label, sc, ctl ? NSStringFromClass([ctl class]) : @"none",
               state ? NSStringFromClass([state class]) : @"none", read, env, shown ? [names componentsJoinedByString:@", "] : @"none"]);
    }
    NSUInteger n = 0, on = 0;
    id front = DMSMFrontStageOnDisplay(identity);
    for (id al in DMSMRecentStages()) {
        id sid = DMSMStageDisplayIdentity(al);
        if (DMSMIsMainIdentity(sid)) continue;
        n++;
        BOOL shownNow = DMSMStageShownOnDisplay(al, identity);
        if (shownNow) on++;
        NSMutableArray *names = [NSMutableArray array];
        for (id it in DMSMStageItemsMap(al)) [names addObject:DMSMKeyText(DMSMItemKey(it)) ?: @"?"];
        DMLog([NSString stringWithFormat:@"[tvdesk] %@: TV stage %lu (display %@%@): %@ -- shown %d%@", label, (unsigned long)n, DMDSLine(sid), [sid isEqual:identity] ? @", the TV screen's own" : @", NOT the TV screen's identity",
               [names componentsJoinedByString:@", "], shownNow, al == front ? @", the TV's front stage" : @""]);
    }
    DMLog([NSString stringWithFormat:@"[tvdesk] %@: %lu stage(s) on the TV kept in Stage Manager's model, %lu shown (TV screen %@, identity %@)", label, (unsigned long)n, (unsigned long)on, NSStringFromCGRect(tv.bounds), DMDSLine(identity)]);
}
// a: every window role on the TV's display set to the empty entity (role 1 too); b: a + the empty entity as the activating one; c: a + Home's
// environment mode (1). 1.8.6 asked only the activating entity (Home Screen's or the empty one) and the mode, which changed nothing on the TV.
static void DMDSTVEmpty(NSString *how) {
    UIScreen *tv = DMDSTV();
    id identity = tv ? DMSMIdentityOfScreen(tv) : nil, cfg = tv && [tv respondsToSelector:NSSelectorFromString(@"displayConfiguration")] ? DMCall(tv, @"displayConfiguration") : nil;
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance"), empty = DMSMEmptyEntity();
    SEL sel = NSSelectorFromString(@"requestTransitionWithOptions:displayConfiguration:builder:");
    if (!tv || !identity || !cfg || !empty || ![ws respondsToSelector:sel] || !DMSMSigOK(ws, sel, DMSMSigRequestOnDisplay(), "requestTransitionWithOptions:displayConfiguration:builder:")) {
        DMLog([NSString stringWithFormat:@"[tvdesk] empty_%@: not asked (TV %d, identity %d, configuration %d, empty entity %d)", how, tv != nil, identity != nil, cfg != nil, empty != nil]);
        return;
    }
    DMDSTVState([NSString stringWithFormat:@"before empty_%@", how]);
    NSMutableArray<NSNumber *> *roles = [NSMutableArray arrayWithObjects:@1, @2, @4, nil];
    size_t nr = 0; const long long *list = DMSMRepairRoleList(&nr);
    for (size_t i = 0; i < nr; i++) if (list[i] != 3 && ![roles containsObject:@(list[i])]) [roles addObject:@(list[i])];
    [roles sortUsingSelector:@selector(compare:)];
    BOOL act = [how isEqualToString:@"b"], mode = [how isEqualToString:@"c"];
    __block BOOL built = NO, wrote = NO;
    __block NSString *what = @"-";
    void (^builder)(id) = ^(id req) {
        built = YES;
        SEL lab = NSSelectorFromString(@"setEventLabel:"), mod = NSSelectorFromString(@"modifyApplicationContext:");
        if ([req respondsToSelector:lab] && DMSMSigOK(req, lab, DMSMSigVoidObj(), "setEventLabel:")) ((void (*)(id, SEL, id))objc_msgSend)(req, lab, @"MSBDSpikeTVEmpty");
        if (![req respondsToSelector:mod] || !DMSMSigOK(req, mod, DMSMSigVoidObj(), "modifyApplicationContext:")) return;
        ((void (*)(id, SEL, id))objc_msgSend)(req, mod, ^(id ctx) {
            if (!DMSMCtxCanWrite(ctx)) return;
            SEL setE = NSSelectorFromString(@"setEntity:forLayoutRole:");
            NSMutableArray *done = [NSMutableArray array];
            @try {
                for (NSNumber *r in roles) { ((void (*)(id, SEL, id, long long))objc_msgSend)(ctx, setE, empty, r.longLongValue); [done addObject:r]; }
                SEL setAct = NSSelectorFromString(@"setActivatingEntity:"), setMode = NSSelectorFromString(@"setRequestedUnlockedEnvironmentMode:");
                if (act && [ctx respondsToSelector:setAct] && DMSMSigOK(ctx, setAct, DMSMSigVoidObj(), "setActivatingEntity:")) ((void (*)(id, SEL, id))objc_msgSend)(ctx, setAct, empty);
                if (mode && [ctx respondsToSelector:setMode] && DMSMSigOK(ctx, setMode, DMSMSigVoidLong(), "setRequestedUnlockedEnvironmentMode:")) ((void (*)(id, SEL, long long))objc_msgSend)(ctx, setMode, 1LL);
                DMSMCtxMarkOurs(ctx);
                wrote = YES;
            } @catch (NSException *x) { DMLog([NSString stringWithFormat:@"[tvdesk] empty_%@: a write raised %@", how, x.reason]); }
            what = [NSString stringWithFormat:@"roles %@ empty%@%@", [done componentsJoinedByString:@","], act ? @", the empty entity activating" : @"", mode ? @", environment mode 1" : @""];
        });
    };
    @try {
        BOOL taken = ((BOOL (*)(id, SEL, unsigned long long, id, id))objc_msgSend)(ws, sel, 0ULL, cfg, builder);
        DMLog([NSString stringWithFormat:@"[tvdesk] empty_%@ on the TV: taken %d, built %d, written %d (%@)", how, taken, built, wrote, what]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[tvdesk] empty_%@: the request raised %@", how, e.reason]); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMDSTVState([NSString stringWithFormat:@"1.5 s after empty_%@", how]); });
}

// ---- S5: dockhide_tv ---------------------------------------------------------------------------------------------------------------------------
static void DMDSDockState(NSString *label) {
    Class dw = objc_getClass("SBFloatingDockWindow");
    for (UIWindow *w in DMAllWindows()) {
        if (!dw || ![w isKindOfClass:dw]) continue;
        UIView *dock = nil;
        NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w];
        for (NSUInteger i = 0; i < todo.count && i < 300 && !dock; i++) {
            UIView *v = todo[i];
            if ([NSStringFromClass([v class]) hasSuffix:@"FloatingDockView"]) dock = v; else [todo addObjectsFromArray:v.subviews];
        }
        UIScreen *scr = w.screen;
        CGRect on = dock ? [dock convertRect:dock.bounds toCoordinateSpace:(scr ?: [UIScreen mainScreen]).coordinateSpace] : CGRectNull;
        CALayer *pl = dock.layer.presentationLayer ?: dock.layer;
        BOOL off = dock && scr && CGRectGetMinY(on) >= CGRectGetMaxY(scr.bounds) - 1;
        DMLog([NSString stringWithFormat:@"[dockhide] %@: Dock window on the %@ (%@): hidden %d alpha %.2f; dock view %@ at %@ (presented %@), alpha %.2f hidden %d -> %@", label,
               scr == [UIScreen mainScreen] ? @"iPad" : @"TV", NSStringFromCGRect(scr.bounds), w.hidden, w.alpha, dock ? NSStringFromClass([dock class]) : @"none",
               NSStringFromCGRect(on), NSStringFromCGRect(pl.frame), dock.alpha, dock.hidden, !dock ? @"?" : (w.hidden || dock.hidden || dock.alpha < 0.05 || off ? @"HIDDEN" : @"shown")]);
    }
    for (UIScreen *sc in [UIScreen screens]) {
        CGSize size = CGSizeZero;
        CGRect a = DMSMUsableAreaForIdentity(DMSMIdentityOfScreen(sc), &size);
        DMLog([NSString stringWithFormat:@"[dockhide] %@: our stage area on the %@: %@ of %@", label, sc == [UIScreen mainScreen] ? @"iPad" : @"TV", NSStringFromCGRect(a), NSStringFromCGSize(size)]);
    }
}
static void DMDSDockHide(int how) {
    gDMDockHideTVTest = how;
    DMLog([NSString stringWithFormat:@"[dockhide] the in-app Dock answer forced %@", how == 1 ? @"YES for a stage on the TV only" : how == 2 ? @"YES for the iPad's stage only" : @"off (as built)"]);
    DMDockAutoHideSMPass();   // (the iPad's stage laid out again: its modifier asked anew)
    UIScreen *tv = DMDSTV();
    id identity = tv ? DMSMIdentityOfScreen(tv) : nil, front = identity ? DMSMFrontStageOnDisplay(identity) : nil;
    NSString *key = nil;
    for (id it in DMSMStageItemsMap(front)) { key = DMSMItemKey(it); if (key) break; }
    if (key) DMLog([NSString stringWithFormat:@"[dockhide] the TV's stage laid out again through %@: %d", DMSMKeyText(key), DMSMRequestWindow(key, nil, -1)]);
    else DMLog(@"[dockhide] no window on the TV to lay its stage out again");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMDSDockState([NSString stringWithFormat:@"1.5 s after dockhide_tv_%d", how]); });
}

// ---- S4: tvhover -------------------------------------------------------------------------------------------------------------------------------
@interface MSBDSpikeHoverSink : NSObject
- (void)hover:(UIHoverGestureRecognizer *)g;
@end
@implementation MSBDSpikeHoverSink
- (void)hover:(UIHoverGestureRecognizer *)g {
    static CFTimeInterval last = 0; static long lastState = -1; static void *lastView = NULL;
    CFTimeInterval now = CACurrentMediaTime();
    if ((long)g.state == lastState && (__bridge void *)g.view == lastView && now - last < 0.5) return;
    last = now; lastState = (long)g.state; lastView = (__bridge void *)g.view;
    UIView *v = g.view;
    CGPoint p = [g locationInView:v];
    UIScreen *scr = v.window.screen;
    CGPoint s = scr ? [v convertPoint:p toCoordinateSpace:scr.coordinateSpace] : p;
    id svc = DMCall(objc_getClass("BKSMousePointerService"), @"sharedInstance");
    SEL gp = sel_registerName("globalPointerPosition");
    Method m = svc ? class_getInstanceMethod(object_getClass(svc), gp) : NULL;
    CGPoint gpos = m && !strcmp(method_getTypeEncoding(m) ?: "", "{CGPoint=dd}16@0:8") ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, gp) : CGPointMake(-1, -1);
    DMLog([NSString stringWithFormat:@"[tvhover] %@ on the %@: state %ld at %.0f,%.0f (screen points %.0f,%.0f of %.0f x %.0f); backboardd's global pointer %.0f,%.0f",
           NSStringFromClass([v class]), scr == [UIScreen mainScreen] ? @"iPad" : @"TV", (long)g.state, p.x, p.y, s.x, s.y, scr.bounds.size.width, scr.bounds.size.height, gpos.x, gpos.y]);
}
@end
static NSMutableArray<UIHoverGestureRecognizer *> *gDMDSHovers;
static MSBDSpikeHoverSink *gDMDSHoverSink;
static void DMDSHover(BOOL on) {
    for (UIHoverGestureRecognizer *g in gDMDSHovers) [g.view removeGestureRecognizer:g];
    NSUInteger removed = gDMDSHovers.count;
    gDMDSHovers = [NSMutableArray array];
    if (!on) { DMLog([NSString stringWithFormat:@"[tvhover] off: %lu recognizer(s) removed", (unsigned long)removed]); return; }
    if (!gDMDSHoverSink) gDMDSHoverSink = [MSBDSpikeHoverSink new];
    NSMutableArray *names = [NSMutableArray array];
    for (UIWindow *w in DMAllWindows()) {
        if (!w.screen || w.screen == [UIScreen mainScreen] || w.hidden) continue;
        UIHoverGestureRecognizer *g = [[UIHoverGestureRecognizer alloc] initWithTarget:gDMDSHoverSink action:@selector(hover:)];
        g.cancelsTouchesInView = NO; g.delaysTouchesBegan = NO; g.delaysTouchesEnded = NO;
        [w addGestureRecognizer:g];
        [gDMDSHovers addObject:g];
        [names addObject:[NSString stringWithFormat:@"%@ %@ level %.0f", NSStringFromClass([w class]), NSStringFromCGRect(w.frame), w.windowLevel]];
    }
    DMLog([NSString stringWithFormat:@"[tvhover] on: %lu SpringBoard window(s) on the TV watched: %@", (unsigned long)names.count, [names componentsJoinedByString:@" | "]]);
    DMLog([NSString stringWithFormat:@"[tvhover] %@", DMDSMethods("BKSMousePointerService", @"isplay|osition")]);
}

// R6 (row 8.1, 1.8.7 commit 8): what sizes a TV's status bar on 18.5. The TV's text and items take the TV's own Menu Bar Size but its bar copy
// keeps the iPad's height; the TV provider's +height is not what sizes it. dispbarh: each window scene's status bar manager (its class chain and what
// its height getters answer), the methods that could size a bar, and every bar copy on another display with its ancestors up to its window (class,
// frame, autoresizing, who lays it out). dispbarh_trace: the same getters asked again for the TV with every provider +height call's caller named
// (DMDSBarHTrace, from the provider hooks); dispbarh_watch_<s>: for s seconds, every +height call's caller chain once (and from SpringBoard's start
// when /tmp/msb-barhtrace was there at the first ask: read once). Read-only: nothing is set, nothing is answered differently. The callers seen are
// kept on the main thread only: a +height asked on another thread hands its callers over to the main queue (review: an NSMutableSet changed from any
// thread while the trigger replaced it could crash SpringBoard in exactly the reading the rows run).
static int gDMDSBarHTraceNow = 0;
static CFTimeInterval gDMDSBarHWatchUntil = 0;
static NSMutableSet<NSString *> *gDMDSBarHSeen;   // (main thread only)
static int gDMDSBarHFlag = -1;   // (/tmp/msb-barhtrace, read once: no file look on every +height)
static void DMDSBarHTrace(Class c, double stock, double answer) {
    BOOL mainThread = pthread_main_np() != 0;
    BOOL now = gDMDSBarHTraceNow > 0 && mainThread;
    if (!now) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ gDMDSBarHFlag = DMTestFlagNow("/tmp/msb-barhtrace") ? 1 : 0; });
        if (!(CACurrentMediaTime() < gDMDSBarHWatchUntil || gDMDSBarHFlag == 1)) return;
    }
    NSArray<NSNumber *> *ret = [NSThread callStackReturnAddresses];
    NSMutableString *sig = [NSMutableString stringWithFormat:@"%s", class_getName(c)];
    for (NSUInteger i = 1; i < ret.count && i < 10; i++) [sig appendFormat:@" %llx", ret[i].unsignedLongLongValue];
    NSString *head = [NSString stringWithFormat:@"[barhtrace] %@+[%s height] iOS %.1f, answered %.1f (%s thread); callers:", now ? @"" : @"(watch) ", class_getName(c), stock, answer, mainThread ? "main" : "other"];
    if (now) { DMLog(head); for (NSUInteger i = 1; i < ret.count && i < 13; i++) DMSymbolize(ret[i].unsignedLongLongValue); return; }
    NSString *key = [sig copy];
    dispatch_async(dispatch_get_main_queue(), ^{   // (the set is touched here only)
        if (!gDMDSBarHSeen) gDMDSBarHSeen = [NSMutableSet set];
        if ([gDMDSBarHSeen containsObject:key] || gDMDSBarHSeen.count >= 80) return;
        [gDMDSBarHSeen addObject:key];
        DMLog(head); for (NSUInteger i = 1; i < ret.count && i < 13; i++) DMSymbolize(ret[i].unsignedLongLongValue);
    });
}
// A getter's answer as text, its types read first: a double, a CGRect, a BOOL / integer, an object (its class); "<none>" when it does not answer.
static NSString *DMDSCall(id o, const char *name, long arg) {
    if (!o) return @"(nil)";
    SEL s = sel_registerName(name);
    Method m = class_getInstanceMethod(object_getClass(o), s);
    if (!m) return @"<none>";
    const char *t = method_getTypeEncoding(m) ?: "";
    unsigned args = method_getNumberOfArguments(m);
    @try {
        if (args == 2 && t[0] == 'd') return [NSString stringWithFormat:@"%.2f", ((double (*)(id, SEL))objc_msgSend)(o, s)];
        if (args == 3 && t[0] == 'd' && strstr(t, "q16")) return [NSString stringWithFormat:@"%.2f", ((double (*)(id, SEL, long))objc_msgSend)(o, s, arg)];
        if (args == 2 && !strncmp(t, "{CGRect=", 8)) return NSStringFromCGRect(((CGRect (*)(id, SEL))objc_msgSend)(o, s));
        if (args == 3 && !strncmp(t, "{CGRect=", 8) && strstr(t, "q")) return NSStringFromCGRect(((CGRect (*)(id, SEL, long))objc_msgSend)(o, s, arg));
        if (args == 3 && !strncmp(t, "{CGRect=", 8) && strstr(t, "d")) return NSStringFromCGRect(((CGRect (*)(id, SEL, double))objc_msgSend)(o, s, (double)arg));
        if (args == 2 && !strncmp(t, "{CGSize=", 8)) return NSStringFromCGSize(((CGSize (*)(id, SEL))objc_msgSend)(o, s));
        if (args == 2 && (t[0] == 'B' || t[0] == 'c' || t[0] == 'q' || t[0] == 'Q' || t[0] == 'i')) return [NSString stringWithFormat:@"%ld", ((long (*)(id, SEL))objc_msgSend)(o, s)];
        if (args == 2 && t[0] == '@') { id v = ((id (*)(id, SEL))objc_msgSend)(o, s); return v ? [NSString stringWithFormat:@"<%@ %p>", NSStringFromClass([v class]), v] : @"(nil)"; }
    } @catch (NSException *e) { return [NSString stringWithFormat:@"<%@>", e.reason]; }
    return [NSString stringWithFormat:@"<types %s>", t];
}
static NSString *DMDSClassChain(id o) {
    NSMutableArray *a = [NSMutableArray array];
    for (Class k = o ? object_getClass(o) : Nil; k && k != [NSObject class]; k = class_getSuperclass(k)) [a addObject:NSStringFromClass(k)];
    return [a componentsJoinedByString:@" < "];
}
static void DMDSBarHeights(BOOL trace) {
    UIScreen *main = [UIScreen mainScreen];
    id tvMgr = nil; UIView *tvBar = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *ws = (UIWindowScene *)sc;
        BOOL tv = ws.screen && ws.screen != main;
        id mgr = nil; @try { mgr = ws.statusBarManager; } @catch (id e) {}
        if (tv && mgr && !tvMgr && [NSStringFromClass([ws class]) hasPrefix:@"SB"]) tvMgr = mgr;
        NSMutableArray *vals = [NSMutableArray array];
        for (NSString *n in @[@"statusBarHeight", @"statusBarFrame", @"isStatusBarHidden", @"statusBarWindow", @"statusBarWindowFrame", @"statusBar", @"statusBarOrientation", @"_isEmbeddedDisplay", @"layoutManager", @"reusePool", @"defaultStatusBarHeightInOrientation:", @"_defaultStatusBarHeightInOrientation:", @"statusBarHeightForOrientation:"])
            [vals addObject:[NSString stringWithFormat:@"%@=%@", n, DMDSCall(mgr, n.UTF8String, 3)]];
        DMLog([NSString stringWithFormat:@"[barh] scene %@ %p on %@ %@ | manager %@ | %@", NSStringFromClass([ws class]), ws, tv ? @"the TV" : (ws.screen == main ? @"the iPad" : @"no screen"), NSStringFromCGRect(ws.screen.bounds), DMDSClassChain(mgr), [vals componentsJoinedByString:@"; "]]);
    }
    if (!trace) {
        for (NSString *cn in @[@"UIStatusBarManager", @"SBWindowSceneStatusBarManager", @"STUIStatusBar_Wrapper", @"STUIStatusBar", @"UIStatusBar_Base", @"UIStatusBar_Modern", @"STUIStatusBarVisualProvider_ExternalPad", @"STUIStatusBarVisualProvider_Pad", @"SBStatusBarReusePool", @"_UIStatusBarVisualProvider_ExternalPad"])
            DMLog([NSString stringWithFormat:@"[barh] %@", DMDSMethods(cn.UTF8String, @"eight|ize|rame|rovider|creen|ayout")]);
    }
    for (UIView *fg in gAllBarCopies.allObjects) {
        UIWindow *w = fg.window;
        if (!w || !w.screen || w.screen == main) continue;
        UIView *bar = fg.superview;
        if (!tvBar) tvBar = bar;
        id vp = bar ? DMBarSizeObjectOf(bar, "visualProvider") : nil;
        NSMutableArray *chain = [NSMutableArray array];
        for (UIView *v = fg; v; v = v.superview)
            [chain addObject:[NSString stringWithFormat:@"%@ %@ ar%lu tamic%d", NSStringFromClass([v class]), NSStringFromCGRect(v.frame), (unsigned long)v.autoresizingMask, v.translatesAutoresizingMaskIntoConstraints]];
        DMLog([NSString stringWithFormat:@"[barh] TV copy %p in %@ (level %.0f, scene %p): provider %@ (+height %@), bar intrinsic %@ | %@", fg, NSStringFromClass([w class]), w.windowLevel, w.windowScene,
               vp ? NSStringFromClass([vp class]) : @"-", vp ? DMDSCall((id)[vp class], "height", 0) : @"-", bar ? NSStringFromCGSize(bar.intrinsicContentSize) : @"-", [chain componentsJoinedByString:@" < "]]);
        for (UIView *v = bar; v && v != w; v = v.superview) {
            NSString *cn = NSStringFromClass([v class]);
            if (![cn containsString:@"StatusBar"]) continue;
            DMLog([NSString stringWithFormat:@"[barh]   %@: %@", cn, DMDSFields(v, @[@"statusBar", @"styleRequest", @"orientation", @"_statusBarHeight", @"currentHeight", @"targetScreen", @"_targetScreen", @"visualProviderInfo", @"_effectiveTargetScreen", @"statusBarFrame"])]);
        }
    }
    if (!trace) return;
    gDMDSBarHTraceNow++;
    @try {
        DMLog([NSString stringWithFormat:@"[barhtrace] the TV's manager %p (%@): statusBarHeight", tvMgr, tvMgr ? NSStringFromClass([tvMgr class]) : @"none"]);
        DMLog([NSString stringWithFormat:@"[barhtrace] = %@", DMDSCall(tvMgr, "statusBarHeight", 0)]);
        DMLog(@"[barhtrace] the TV's manager: defaultStatusBarHeightInOrientation: 3");
        DMLog([NSString stringWithFormat:@"[barhtrace] = %@", DMDSCall(tvMgr, "defaultStatusBarHeightInOrientation:", 3)]);
        DMLog(@"[barhtrace] the TV's manager: statusBarFrame");
        DMLog([NSString stringWithFormat:@"[barhtrace] = %@", DMDSCall(tvMgr, "statusBarFrame", 0)]);
        DMLog([NSString stringWithFormat:@"[barhtrace] the TV's bar %@: intrinsicContentSize", tvBar ? NSStringFromClass([tvBar class]) : @"none"]);
        DMLog([NSString stringWithFormat:@"[barhtrace] = %@", tvBar ? NSStringFromCGSize(tvBar.intrinsicContentSize) : @"-"]);
    } @finally {
        gDMDSBarHTraceNow--;
    }
}

static BOOL DMDispSpikeTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"dispbarh"] || [cmd isEqualToString:@"dispbarh_trace"]) { DMDSBarHeights([cmd hasSuffix:@"_trace"]); return YES; }
    if ([cmd hasPrefix:@"dispbarh_watch_"]) {
        double s = MAX(1.0, MIN(120.0, [[cmd substringFromIndex:15] doubleValue]));
        gDMDSBarHSeen = [NSMutableSet set]; gDMDSBarHWatchUntil = CACurrentMediaTime() + s;
        DMLog([NSString stringWithFormat:@"[barhtrace] watching every provider +height call's callers for %.0f s", s]);
        return YES;
    }
    if ([cmd isEqualToString:@"dispinfo"] || [cmd isEqualToString:@"dispinfo_methods"]) { DMDSInfo([cmd hasSuffix:@"_methods"]); return YES; }
    if ([cmd isEqualToString:@"dispscale_shape"] || [cmd isEqualToString:@"dispscale_shape_call"]) { DMDSScaleShape([cmd hasSuffix:@"_call"]); return YES; }
    if ([cmd hasPrefix:@"dispscale_"]) { DMDSScale([cmd substringFromIndex:10]); return YES; }
    if ([cmd isEqualToString:@"tvdesk_state"]) { DMDSTVState(@"now"); return YES; }
    if ([cmd hasPrefix:@"tvdesk_empty_"]) {
        NSString *how = [cmd substringFromIndex:13];
        if ([@[@"a", @"b", @"c"] containsObject:how]) DMDSTVEmpty(how); else DMLog(@"[tvdesk] empty_<a|b|c>");
        return YES;
    }
    if ([cmd isEqualToString:@"dockhide_state"]) { DMDSDockState(@"now"); return YES; }
    if ([cmd hasPrefix:@"dockhide_tv_"]) { DMDSDockHide(MAX(0, MIN(2, [[cmd substringFromIndex:12] intValue]))); return YES; }
    if ([cmd isEqualToString:@"tvhover_on"] || [cmd isEqualToString:@"tvhover_off"]) { DMDSHover([cmd hasSuffix:@"_on"]); return YES; }
    return NO;
}
#endif
