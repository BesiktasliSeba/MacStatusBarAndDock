// CCProbe.h -- DEBUG BUILDS ONLY (included under #if DEBUG): what iPadOS's Control Center module repositories hold, what 18's "Add a Control"
// gallery hands to the add sheet, and a few read-only walkers used to find out how a module of ours can be offered there (1.6.0 research).
// Nothing here changes what SpringBoard does: the hooks log and return the original answer.
static NSHashTable *gCCPRepos;
static NSString *DMCCPShort(id o, NSUInteger max) {
    NSString *d = [o description] ?: @"(nil)";
    d = [[d componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return d.length > max ? [[d substringToIndex:max] stringByAppendingString:@"..."] : d;
}
static id DMCCPIvar(id obj, NSString *name) {   // (an object ivar by its exact name, nil when there is none or it is not an object)
    if (!obj) return nil;
    for (Class c = object_getClass(obj); c; c = class_getSuperclass(c)) {
        Ivar iv = class_getInstanceVariable(c, name.UTF8String);
        if (!iv) continue;
        const char *t = ivar_getTypeEncoding(iv);
        if (!t || t[0] != '@') return nil;
        return object_getIvar(obj, iv);
    }
    return nil;
}
static void DMCCPLogRepo(id repo, NSString *why) {
    NSArray *urls = DMCCPIvar(repo, @"_directoryURLs");
    NSSet *allowed = DMCCPIvar(repo, @"_allowedModuleIdentifiers"), *loadable = DMCCPIvar(repo, @"_loadableModuleIdentifiers"), *available = DMCCPIvar(repo, @"_availableModuleIdentifiers");
    NSDictionary *all = DMCCPIvar(repo, @"_allModuleMetadataByIdentifier");
    Ivar ig = class_getInstanceVariable(object_getClass(repo), "_ignoreAllowedList");
    BOOL ignore = ig ? *(BOOL *)((uint8_t *)(__bridge void *)repo + ivar_getOffset(ig)) : NO;
    NSMutableArray *third = [NSMutableArray array];
    for (NSString *k in all) if (![k hasPrefix:@"com.apple."]) [third addObject:k];
    DMLog([NSString stringWithFormat:@"[ccprobe] repository %p (%@): dirs %@; allowed %lu, ignore allowed list %d; all %lu (not Apple's: %@); available %lu; loadable %lu (MemoryMagic %d)",
        repo, why, [[urls valueForKey:@"path"] componentsJoinedByString:@", "], (unsigned long)allowed.count, ignore, (unsigned long)all.count, [third componentsJoinedByString:@","],
        (unsigned long)available.count, (unsigned long)loadable.count, [loadable containsObject:@"com.sop.MemoryMagic"]]);
}
static id (*gCCPOrigRepoInit)(id, SEL, NSArray *, NSSet *);
static id DMCCPRepoInit(id self, SEL _cmd, NSArray *urls, NSSet *allowed) {
    id r = gCCPOrigRepoInit(self, _cmd, urls, allowed);
    if (!gCCPRepos) gCCPRepos = [NSHashTable weakObjectsHashTable];
    if (r) [gCCPRepos addObject:r];
    NSArray *stack = [NSThread callStackSymbols];
    DMLog([NSString stringWithFormat:@"[ccprobe] repository %p made: dirs %@, allowed %lu; called from %@", r, [[urls valueForKey:@"path"] componentsJoinedByString:@", "], (unsigned long)allowed.count,
        DMCCPShort([[stack subarrayWithRange:NSMakeRange(1, MIN((NSUInteger)6, stack.count - 1))] componentsJoinedByString:@" | "], 700)]);
    return r;
}
// The gallery (ControlCenterUIServices.ControlsGalleryManager, Swift with @objc delegate methods): what it gives SpringBoardHome's add sheet.
static id (*gCCPOrigCollections)(id, SEL, id);
static id DMCCPCollections(id self, SEL _cmd, id mgr) {
    id r = gCCPOrigCollections(self, _cmd, mgr);
    NSArray *cols = [r isKindOfClass:[NSArray class]] ? r : nil;
    DMLog([NSString stringWithFormat:@"[ccprobe] gallery collections: %lu (%@)", (unsigned long)cols.count, NSStringFromClass([r class])]);
    for (id c in cols) {
        NSArray *ds = [c respondsToSelector:NSSelectorFromString(@"widgetDescriptors")] ? DMCall(c, @"widgetDescriptors") : nil;
        id first = ds.firstObject;
        SEL pgs = NSSelectorFromString(@"preferredGallerySizeClass");
        if ([NSStringFromClass([first class]) isEqualToString:@"CCUIModuleIconElement"] && [first respondsToSelector:pgs]) {
            // (an integer -- the size class number --, never an object: read through its signature; reading it as an object crashed SpringBoard twice)
            NSMethodSignature *sig = [first methodSignatureForSelector:pgs];
            const char *rt = sig.methodReturnType;
            NSString *pref = rt && rt[0] == '@' ? [NSString stringWithFormat:@"%@", ((id (*)(id, SEL))objc_msgSend)(first, pgs)]
                : (sig.methodReturnLength == 8 ? [NSString stringWithFormat:@"%lld", ((long long (*)(id, SEL))objc_msgSend)(first, pgs)] : [NSString stringWithFormat:@"(type %s)", rt]);
            NSString *mid = [first respondsToSelector:NSSelectorFromString(@"moduleIdentifier")] ? DMCall(first, @"moduleIdentifier") : @"?";
            if ([mid hasPrefix:@"com.besiktasliseba"] || [mid isEqualToString:@"com.apple.FocusUIModule"] || [mid isEqualToString:@"jp.dcsyhi.cczetsu"] || [mid isEqualToString:@"com.apple.control-center.FlashlightModule"])
                DMLog([NSString stringWithFormat:@"[ccprobe]   element %@ preferred gallery size %@", mid, pref]);
        }
        DMLog([NSString stringWithFormat:@"[ccprobe]   %@ id %@ type %@ container %@ vendor %@: %lu descriptors, first %@", NSStringFromClass([c class]),
            DMCCPIvar(c, @"_collectionIdentifier"), DMCCPIvar(c, @"_typeIdentifier"), DMCCPIvar(c, @"_containerName"), DMCCPIvar(c, @"_vendorName"), (unsigned long)ds.count,
            ds.count ? [NSString stringWithFormat:@"%@: %@", NSStringFromClass([ds.firstObject class]), DMCCPShort(ds.firstObject, 400)] : @"-"]);
    }
    return r;
}
static BOOL (*gCCPOrigSupported)(id, SEL, id, id);
static BOOL DMCCPSupported(id self, SEL _cmd, id mgr, id descriptor) {
    BOOL r = gCCPOrigSupported(self, _cmd, mgr, descriptor);
    static int n = 0;
    if (n++ < 40) DMLog([NSString stringWithFormat:@"[ccprobe] gallery: descriptor %@ supported %d: %@", NSStringFromClass([descriptor class]), r, DMCCPShort(descriptor, 300)]);
    return r;
}
static void DMCCProbeInit(void) {
    Class rc = objc_getClass("CCSModuleRepository");
    SEL ri = NSSelectorFromString(@"_initWithDirectoryURLs:allowedModuleIdentifiers:");
    if (rc && class_getInstanceMethod(rc, ri)) MSHookMessageEx(rc, ri, (IMP)DMCCPRepoInit, (IMP *)&gCCPOrigRepoInit);
    Class g = objc_getClass("ControlCenterUIServices.ControlsGalleryManager");
    SEL cs = NSSelectorFromString(@"customApplicationWidgetCollectionsForAddWidgetSheetConfigurationManager:"), ss = NSSelectorFromString(@"addWidgetSheetConfigurationManager:isDescriptorSupported:");
    if (g && class_getInstanceMethod(g, cs)) MSHookMessageEx(g, cs, (IMP)DMCCPCollections, (IMP *)&gCCPOrigCollections);
    if (g && class_getInstanceMethod(g, ss)) MSHookMessageEx(g, ss, (IMP)DMCCPSupported, (IMP *)&gCCPOrigSupported);
    DMLog([NSString stringWithFormat:@"[ccprobe] installed (repository %d, gallery manager %d)", objc_getClass("CCSModuleRepository") != nil, g != nil]);
}
static void DMCCProbeRepos(void) {
    for (id r in gCCPRepos.allObjects) DMCCPLogRepo(r, @"now");
    if (!gCCPRepos.count) DMLog(@"[ccprobe] no repository seen since the start");
}
// ivpath_<Class>|<ivar or getter>.<...>: walk from the class's sharedInstance (or the class) by exact ivar names, else zero-argument getters
static void DMCCProbeIvarPath(NSString *spec) {
    NSArray *q = [spec componentsSeparatedByString:@"|"];
    Class c = objc_getClass([q.firstObject UTF8String]);
    id o = c && [(id)c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)c, @selector(sharedInstance)) : (id)c;
    NSMutableString *out = [NSMutableString stringWithFormat:@"[ivpath] %@ = %@", q.firstObject, o ? NSStringFromClass(object_getClass(o)) : @"nil"];
    for (NSString *step in q.count > 1 ? [q[1] componentsSeparatedByString:@"."] : @[]) {
        if (!o) break;
        id next = DMCCPIvar(o, step);
        if (!next && [o respondsToSelector:NSSelectorFromString(step)]) {
            NSMethodSignature *sig = [o methodSignatureForSelector:NSSelectorFromString(step)];
            if (sig.numberOfArguments == 2 && sig.methodReturnType[0] == '@') next = ((id (*)(id, SEL))objc_msgSend)(o, NSSelectorFromString(step));
        }
        o = next;
        [out appendFormat:@" .%@ -> %@", step, o ? NSStringFromClass(object_getClass(o)) : @"nil"];
    }
    if (o) [out appendFormat:@": %@", DMCCPShort(o, 1500)];
    DMLog(out);
}
static void DMCCProbeOpen(BOOL show) {   // (18: Control Center through its coordinator; SBControlCenterController has no shared instance there)
    id co = DMCall(objc_getClass("SBControlCenterCoordinator"), @"sharedInstance");
    SEL s = NSSelectorFromString(show ? @"presentAnimated:" : @"dismissAnimated:");
    if ([co respondsToSelector:s]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(co, s, YES); DMLog([NSString stringWithFormat:@"[ccprobe] Control Center %@ through %@", show ? @"shown" : @"put away", NSStringFromClass([co class])]); }
    else DMLog(@"[ccprobe] no Control Center coordinator");
}
// protomethods_<Protocol>: every method a protocol declares (required / optional, instance / class), read-only
static void DMCCProbeProtocol(NSString *name) {
    Protocol *p = objc_getProtocol(name.UTF8String);
    if (!p) { DMLog([NSString stringWithFormat:@"[protomethods] %@: no such protocol", name]); return; }
    NSMutableString *out = [NSMutableString stringWithFormat:@"[protomethods] %@:", name];
    for (int req = 1; req >= 0; req--) for (int inst = 1; inst >= 0; inst--) {
        unsigned n = 0; struct objc_method_description *m = protocol_copyMethodDescriptionList(p, req, inst, &n);
        for (unsigned i = 0; i < n; i++) [out appendFormat:@" %@%s%s(%s)", req ? @"" : @"?", inst ? "-" : "+", sel_getName(m[i].name), m[i].types ?: ""];
        free(m);
    }
    unsigned pc = 0; Protocol * __unsafe_unretained *ps = protocol_copyProtocolList(p, &pc);
    for (unsigned i = 0; i < pc; i++) [out appendFormat:@" <%s>", protocol_getName(ps[i])];
    free(ps);
    DMLog(out);
}
// The gallery's module entries: every CCUIModuleIconElement made (module, its sizes) and who made it; and module instances made or refused.
static id (*gCCPOrigIconInit)(id, SEL, id, id, id, id, BOOL);
static id DMCCPIconInit(id self, SEL _cmd, id uid, id module, id container, id sizes, BOOL expands) {
    id r = gCCPOrigIconInit(self, _cmd, uid, module, container, sizes, expands);
    NSArray *stack = [NSThread callStackSymbols];
    DMLog([NSString stringWithFormat:@"[ccprobe] icon element %@ (container %@): sizes %@ %@ expands %d; from %@", module, container, NSStringFromClass([sizes class]), DMCCPShort(sizes, 200), expands,
        DMCCPShort([[stack subarrayWithRange:NSMakeRange(1, MIN((NSUInteger)4, stack.count - 1))] componentsJoinedByString:@" | "], 500)]);
    return r;
}
static id (*gCCPOrigInstantiate)(id, SEL, id, id);
static id DMCCPInstantiate(id self, SEL _cmd, id metadata, id uid) {
    id r = gCCPOrigInstantiate(self, _cmd, metadata, uid);
    NSString *mid = [metadata respondsToSelector:@selector(moduleIdentifier)] ? [metadata performSelector:@selector(moduleIdentifier)] : @"?";
    if (![mid hasPrefix:@"com.apple."]) DMLog([NSString stringWithFormat:@"[ccprobe] module instance for %@: %@ (module %@, prototype size %@)", mid, r ? NSStringFromClass([r class]) : @"NONE",
        r && [r respondsToSelector:@selector(module)] ? NSStringFromClass([[r performSelector:@selector(module)] class]) : @"-",
        r && [r respondsToSelector:NSSelectorFromString(@"prototypeModuleSize")] ? @"(struct)" : @"-"]);
    return r;
}
static void DMCCProbeInit2(void) {
    Class ie = objc_getClass("CCUIModuleIconElement");
    SEL is = NSSelectorFromString(@"initWithUniqueIdentifier:moduleIdentifier:containerBundleIdentifier:standardSupportedGridSizeClasses:expandsGridSizeClassesForAccessibility:");
    if (ie && class_getInstanceMethod(ie, is)) MSHookMessageEx(ie, is, (IMP)DMCCPIconInit, (IMP *)&gCCPOrigIconInit);
    Class mm = objc_getClass("CCUIModuleInstanceManager");
    SEL ms = NSSelectorFromString(@"_instantiateModuleWithMetadata:uniqueIdentifier:");
    if (mm && class_getInstanceMethod(mm, ms)) MSHookMessageEx(mm, ms, (IMP)DMCCPInstantiate, (IMP *)&gCCPOrigInstantiate);
    DMLog([NSString stringWithFormat:@"[ccprobe] icon element hook %d, instance hook %d", ie && class_getInstanceMethod(ie, is), mm && class_getInstanceMethod(mm, ms)]);
}
// ccsizes: every module instance Control Center has made: its class, its 18 grid size classes (supportedGridSizeClasses, a bit mask) and its
// prototype layout size; and the grid size class its content view controller has now
static void DMCCProbeSizes(void) {
    id co = DMCall(objc_getClass("SBControlCenterCoordinator"), @"sharedInstance");
    id cc = DMCCPIvar(co, @"_embeddedDisplayControlCenterController");
    id vc = DMCCPIvar(cc, @"_viewController");
    id mgr = DMCCPIvar(vc, @"_moduleInstanceManager");
    NSArray *instances = [mgr respondsToSelector:NSSelectorFromString(@"moduleInstances")] ? DMCall(mgr, @"moduleInstances") : nil;
    if ([instances isKindOfClass:[NSSet class]]) instances = [(NSSet *)instances allObjects];
    if ([instances isKindOfClass:[NSDictionary class]]) instances = [(NSDictionary *)instances allValues];
    DMLog([NSString stringWithFormat:@"[ccsizes] manager %@: %lu instances", mgr ? NSStringFromClass([mgr class]) : @"none", (unsigned long)instances.count]);
    for (id inst in instances) {
        id meta = [inst respondsToSelector:NSSelectorFromString(@"metadata")] ? DMCall(inst, @"metadata") : nil;
        id mod = [inst respondsToSelector:NSSelectorFromString(@"module")] ? DMCall(inst, @"module") : nil;
        NSString *mid = [meta respondsToSelector:NSSelectorFromString(@"moduleIdentifier")] ? DMCall(meta, @"moduleIdentifier") : @"?";
        SEL sg = NSSelectorFromString(@"supportedGridSizeClasses");
        NSString *mask = [mod respondsToSelector:sg] ? [NSString stringWithFormat:@"0x%llx", (unsigned long long)((unsigned long (*)(id, SEL))objc_msgSend)(mod, sg)] : @"-";
        struct { unsigned long w, h; } proto = {0, 0};
        SEL ps = NSSelectorFromString(@"prototypeModuleSize");
        if ([inst respondsToSelector:ps]) {
            NSMethodSignature *sig = [inst methodSignatureForSelector:ps];
            if (sig.methodReturnLength == sizeof(proto)) {
                NSInvocation *iv = [NSInvocation invocationWithMethodSignature:sig]; iv.selector = ps; [iv invokeWithTarget:inst]; [iv getReturnValue:&proto];
            }
        }
        id cvc = [mod respondsToSelector:@selector(contentViewController)] ? [mod performSelector:@selector(contentViewController)] : nil;
        SEL gs = NSSelectorFromString(@"gridSizeClass");
        NSString *grid = [cvc respondsToSelector:gs] ? [NSString stringWithFormat:@"%ld", ((long (*)(id, SEL))objc_msgSend)(cvc, gs)] : @"-";
        DMLog([NSString stringWithFormat:@"[ccsizes] %@ (%@): supported %@, prototype %lux%lu, content %@ grid %@", mid, mod ? NSStringFromClass([mod class]) : @"-", mask, proto.w, proto.h, cvc ? NSStringFromClass([cvc class]) : @"-", grid]);
    }
}
// CCUIGridSizeClassForSBHIconGridSizeClass (ControlCenterUIServices): what SpringBoardHome's grid size class is when Control Center turns it into
// its own -- 18's gallery search threw in it for RAM & CPU (SpringBoard crashed, 22:20). Debug only: logged, and an exception is caught and logged
// (answer: smallWide) instead of taking SpringBoard down, so the cause can be read.
static long long (*gCCPOrigGridConv)(void *);
static long long DMCCPGridConv(void *arg) {
    uintptr_t raw = (uintptr_t)arg;
    NSString *what = raw > 0x100000000ull ? [NSString stringWithFormat:@"%@ %@", NSStringFromClass(object_getClass((__bridge id)arg)), DMCCPShort((__bridge id)arg, 120)] : [NSString stringWithFormat:@"raw %lu", (unsigned long)raw];
    long long r = -1;
    @try { r = gCCPOrigGridConv(arg); }
    @catch (NSException *e) {
        DMLog([NSString stringWithFormat:@"[ccprobe] grid size conversion THREW for %@: %@ -- %@; from %@", what, e.name, e.reason,
            DMCCPShort([[[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(1, 6)] componentsJoinedByString:@" | "], 900)]);
        return 2;
    }
    static int n = 0;
    if (n++ < 60) DMLog([NSString stringWithFormat:@"[ccprobe] grid size conversion %@ -> %lld", what, r]);
    return r;
}
static void DMCCProbeInit3(void) {
    void *h = dlopen("/System/Library/PrivateFrameworks/ControlCenterUIServices.framework/ControlCenterUIServices", RTLD_LAZY | RTLD_NOLOAD);
    void *f = h ? dlsym(h, "CCUIGridSizeClassForSBHIconGridSizeClass") : NULL;
    if (f) MSHookFunction(f, (void *)DMCCPGridConv, (void **)&gCCPOrigGridConv);
    DMLog([NSString stringWithFormat:@"[ccprobe] grid size conversion hook %d", f != NULL]);
}
// ccsettings: Control Center's module settings (CCUIModuleSettingsManager -moduleSettingsForModuleIdentifier:) for a few modules, ours among them
static void DMCCProbeSettings(void) {
    id co = DMCall(objc_getClass("SBControlCenterCoordinator"), @"sharedInstance");
    id vc = DMCCPIvar(DMCCPIvar(co, @"_embeddedDisplayControlCenterController"), @"_viewController");
    id sm = DMCCPIvar(vc, @"_moduleSettingsManager");
    SEL q = NSSelectorFromString(@"moduleSettingsForModuleIdentifier:");
    for (NSString *mid in @[@"com.besiktasliseba.macstatusbaranddock.ramcpu", @"com.apple.FocusUIModule", @"com.apple.control-center.FlashlightModule", @"jp.dcsyhi.cczetsu", @"com.apple.control-center.MuteModule"]) {
        id s = [sm respondsToSelector:q] ? ((id (*)(id, SEL, id))objc_msgSend)(sm, q, mid) : nil;
        id g = [s respondsToSelector:NSSelectorFromString(@"gridSizeClass")] ? DMCall(s, @"gridSizeClass") : nil;
        DMLog([NSString stringWithFormat:@"[ccsettings] %@: %@ grid %@ (%p) container %@", mid, s ? NSStringFromClass([s class]) : @"nil", g, (__bridge void *)g,
            [s respondsToSelector:NSSelectorFromString(@"moduleContainerBundleIdentifier")] ? DMCall(s, @"moduleContainerBundleIdentifier") : @"-"]);
    }
    void *sw = dlsym(RTLD_DEFAULT, "CCUIIconGridSizeClassSmallWide");
    DMLog([NSString stringWithFormat:@"[ccsettings] exported CCUIIconGridSizeClassSmallWide %@", sw ? [NSString stringWithFormat:@"%@ (%p)", *(__unsafe_unretained NSString **)sw, (__bridge void *)*(__unsafe_unretained NSString **)sw] : @"not found"]);
}
