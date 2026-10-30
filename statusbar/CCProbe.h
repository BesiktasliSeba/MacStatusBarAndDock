// CCProbe.h -- DEBUG BUILDS ONLY (included under #if DEBUG): read-only walkers for Control Center, run only when a test asks for them (the
// ivpath_, protomethods_, ccopen_, ccsizes and ccsettings triggers). Nothing here is hooked.
// (Until 1.7.1 this file also hooked Control Center at every start of a debug build -- its module repositories, 18's "Add a Control" gallery, the
// module icon elements and instances, and CCUIGridSizeClassForSBHIconGridSizeClass -- for the 1.6.0 RAM & CPU module research, which is done
// (common/CCModuleRegister.h). The last of those hooks passed one argument to a function that takes two, and iPadOS 18 dropped the tiles of
// Control Center's full-page modules -- KT's Now Playing and Connectivity pages, A12Z, 30 Oct. Debug builds run on KT's iPads, so the hooks went.)
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
