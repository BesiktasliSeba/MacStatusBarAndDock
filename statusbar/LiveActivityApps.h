// LiveActivityApps.h -- other apps' Live Activities in the menu bar, iPadOS 17 and 18 (1.8.4 item 1; KT 6 Nov: a pill drawn by us -- the app's
// icon and name --, the card the app's own live Lock Screen view; Apple's own Now Playing and timer activities are left out, ours show them).
// Included at the end of LiveActivities.h. Research: plans/live-activities-research.md section 3.
//
// Two steps, each behind its own check, and both OFF until a device run of la_probe has read the selectors on that very iPadOS (plans/v184.md):
//  - the pills: SpringBoard's SBActivityManager observed the way its own observers are (-addObserver: with an object answering the SBActivityObserver
//    protocol; no hook), its items read for their app, start and relevance -- on the versions listed in kMSBDLAAppsListChecked only
//    (common/LiveActivities.h: Settings reads it too, for the Apps row), with every row of kDMLAAppListNeeds there with its types and every
//    required method of the protocol answered by our observer;
//  - the card's live view: ActivityUIServices' host view controller for the item's descriptor at Lock Screen metrics, made when its card opens and
//    invalidated when it closes -- on the versions in kMSBDLAAppsHostChecked only. Until then the card shows the app's icon, its name and opens it.
// The AC* / ACUIS* classes are ObjC wrappers over Swift: a wrong argument is a crash @try cannot catch, and one SpringBoard crash can put the M1
// in Safe Mode. So exact types only, read on the device first; nothing here is ever asked on 15/16, and nothing before SpringBoard is 8 s old.

// The iPadOS versions whose selectors a device run of la_probe has confirmed (exact versions: 17.5.1 is not 17.5): common/LiveActivities.h
// kMSBDLAAppsListChecked / kMSBDLAAppsHostChecked. None yet: the path is off.
static const DMLANeedRow kDMLAAppListNeeds[] = {   // (types as read in the iOS 17.0 runtime headers; to be checked against la_probe)
    { "SBActivityManager", "sharedInstance", "@16@0:8", YES, NO },
    { "SBActivityManager", "addObserver:", "v24@0:8@16", NO, NO },
    { "SBActivityManager", "removeObserver:", "v24@0:8@16", NO, NO },
    { "SBActivityManager", "itemByActivityIdentifier", "@16@0:8", NO, NO },
    { "SBActivityItem", "identifier", "@16@0:8", NO, NO },
    { "SBActivityItem", "descriptor", "@16@0:8", NO, NO },
    { "SBActivityItem", "relevanceScore", "d16@0:8", NO, NO },
    { "ACActivityDescriptor", "platterTargetBundleIdentifier", "@16@0:8", NO, NO },
};
static const DMLANeedRow kDMLAAppHostNeeds[] = {
    { "ACUISActivityHostViewControllerFactory", "activityHostViewControllerWithDescriptor:metricsRequest:", "@32@0:8@16@24", YES, NO },
    { "ACUISSizeDimensionRequest", "fixed:", "@24@0:8d16", YES, NO },
    { "ACUISSizeDimensionRequest", "initWithMinimum:maximum:", "@32@0:8d16d24", NO, NO },
    { "ACUISActivityItemMetricsRequest", "initWithWidth:height:cornerRadius:", "@40@0:8@16@24d32", NO, NO },
    { "ACUISActivityMetricsRequest", "initWithLockScreenMetrics:", "@24@0:8@16", NO, NO },
    { "ACUISActivityHostViewController", "setDelegate:", "v24@0:8@16", NO, NO },
    { "ACUISActivityHostViewController", "invalidate", "v16@0:8", NO, NO },
};
static BOOL DMLAAppsListedHere(BOOL host) {   // (this iPadOS in the listing's or the live view's list; never on 15/16)
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    return (host ? MSBDLAAppsHostListed(v.majorVersion, v.minorVersion, v.patchVersion) : MSBDLAAppsListed(v.majorVersion, v.minorVersion, v.patchVersion)) != 0;
}

// Our observer: the SBActivityObserver methods of the 17.0 headers that carry an activity's life; what it hears is copied on the calling thread
// (plain values) and used on the main thread. It claims only the items we show (shouldHandleActivityItem:) and takes none of the activities'
// alerts: it has no -presentAlert: / -dismissAlert: (one the protocol requires would leave the path off: DMLAAppsObserverCovers). A message it
// does not know -- a selector past the 17.0 header that the manager sends without asking -- is taken and dropped, not an exception in the
// manager's frames (review 1.8.4 L8). How the manager uses shouldHandleActivityItem: is still to be read on the device (plans/v184.md).
static void DMLAAppsHeard(id item, int what);   // 0 started / updated, 1 ended, 2 dismissed
static BOOL gLAAppsOn = NO;         // the Apps kind applied (DMLAAppsApply)
static BOOL DMLAAppsSkipped(NSString *bid);
static BOOL DMLAAppsClaims(id item) {   // (an item we show: an app's, with the Apps kind on; read in the shapes the listing's check confirmed)
    if (!gLAAppsOn || !gLAOn || !gLAKindOn[kMSBDLAApp] || ![item isKindOfClass:objc_getClass("SBActivityItem")]) return NO;
    id desc = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("descriptor"));
    id bid = [desc isKindOfClass:objc_getClass("ACActivityDescriptor")] ? ((id (*)(id, SEL))objc_msgSend)(desc, sel_registerName("platterTargetBundleIdentifier")) : nil;
    return [bid isKindOfClass:[NSString class]] && !DMLAAppsSkipped(bid);
}
@interface DMLAActivityObserver : NSObject
@end
@implementation DMLAActivityObserver
- (BOOL)shouldHandleActivityItem:(id)item { return DMLAAppsClaims(item); }
- (void)activityDidStart:(id)item { DMLAAppsHeard(item, 0); }
- (void)activityDidUpdate:(id)item { DMLAAppsHeard(item, 0); }
- (void)activityDidEnd:(id)item { DMLAAppsHeard(item, 1); }
- (void)activityDidDismiss:(id)item { DMLAAppsHeard(item, 2); }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *own = [super methodSignatureForSelector:sel];
    if (own) return own;
    NSMutableString *types = [NSMutableString stringWithString:@"@@:"];   // (an object's worth back, nil: the caller reads no garbage)
    for (const char *c = sel_getName(sel); *c; c++) if (*c == ':') [types appendString:@"@"];
    return [NSMethodSignature signatureWithObjCTypes:types.UTF8String];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    DMLog([NSString stringWithFormat:@"[liveact] apps: the activity manager sent our observer %@, which it does not know: dropped", NSStringFromSelector(inv.selector)]);
}
@end
static DMLAActivityObserver *gLAObserver = nil;
static int gLAAppsVerdict = -1;     // the listing's check: -1 not made yet, 0 off, 1 on
#if DEBUG
static BOOL gLAAppsForced = NO;     // (tests on a debug build: la_apps_try -- the listing on, where every row and the protocol check out, before its version is listed)
#endif
// Every required method of SpringBoard's observer protocol answered by ours (the manager may call any of them).
static BOOL DMLAAppsObserverCovers(Protocol *proto, NSMutableArray<NSString *> *missing) {
    if (!proto) { [missing addObject:@"protocol SBActivityObserver"]; return NO; }
    unsigned n = 0;
    struct objc_method_description *req = protocol_copyMethodDescriptionList(proto, YES, YES, &n);
    BOOL ok = YES;
    for (unsigned i = 0; i < n; i++) {
        if ([DMLAActivityObserver instancesRespondToSelector:req[i].name]) continue;
        ok = NO;
        [missing addObject:[NSString stringWithFormat:@"required -%s (%s)", sel_getName(req[i].name), req[i].types ?: "?"]];
    }
    free(req);
    return ok;
}
static BOOL DMLAAppsCheck(void) {
    if (gLAAppsVerdict >= 0) return gLAAppsVerdict == 1;
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17) { gLAAppsVerdict = 0; return NO; }
    BOOL listed = DMLAAppsListedHere(NO);
#if DEBUG
    listed = listed || gLAAppsForced;
#endif
    if (!listed) {
        gLAAppsVerdict = 0;
        DMLog(@"[liveact] apps: this iPadOS version is not one la_probe has confirmed: other apps' Live Activities stay off");
        return NO;
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    BOOL ok = DMLATypesOK(kDMLAAppListNeeds, sizeof kDMLAAppListNeeds / sizeof kDMLAAppListNeeds[0], missing);
    ok = DMLAAppsObserverCovers(objc_getProtocol("SBActivityObserver"), missing) && ok;
    gLAAppsVerdict = ok ? 1 : 0;
    DMLog([NSString stringWithFormat:@"[liveact] apps: SpringBoard's activity manager %@%@", ok ? @"checks out: listed" : @"not as read: off",
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
    return ok;
}
static BOOL DMLAAppsLive(void) { return gLAAppsOn && gLAObserver != nil; }
static id DMLAAppsManager(void) {
    Class c = objc_getClass("SBActivityManager");
    return c ? ((id (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("sharedInstance")) : nil;
}
static BOOL DMLAAppsSkipped(NSString *bid) {   // (Apple's own Now Playing and the Clock's timer activities: our own pills show them)
#if DEBUG
    if (DMTestFlag("/tmp/msb-la-noskip")) return !bid.length;   // (the device check: an iPad may have no other app's activity -- Apple's show as apps then)
#endif
    // (the Clock's timer activity is com.apple.ClockAngel's on 17.5.1 -- its platterTargetBundleIdentifier, 7 Nov device pass: it showed as a second
    //  "Clock" pill beside our timer's --, com.apple.mobiletimer's where an iPadOS names the app itself)
    return !bid.length || [bid isEqualToString:@"com.apple.MediaRemoteUI"] || [bid isEqualToString:@"com.apple.mobiletimer"] || [bid isEqualToString:@"com.apple.ClockAngel"];
}
static void DMLAAppsUse(NSString *ident, NSString *bid, double relevance, int what) {
    if (!DMLAAppsLive() || !gLAOn || !gLAKindOn[kMSBDLAApp] || !ident.length || DMLAAppsSkipped(bid)) return;
    NSString *uid = [@"app:" stringByAppendingString:ident];
    DMLAItem *it = gLAItems[uid];
    if (what == 2) { DMLAAppsHostTearDown(uid); if (it) { [gLAItems removeObjectForKey:uid]; DMLAChanged(@"an app's activity dismissed"); } return; }   // (its live view goes now: review 1.8.4 P2-L2)
    if (what == 1) { if (it && it.endedAt <= 0) { DMLAEnd(it, @"its app ended it"); DMLAChanged(nil); } return; }
    BOOL fresh = !it;
    if (fresh) { it = [DMLAItem new]; it.kind = kMSBDLAApp; it.uid = uid; }
    it.bundleID = bid; it.title = DMLAAppName(bid) ?: bid; it.rank = -relevance; it.endedAt = 0;
    if (fresh) DMLAUpsert(it, @"an app's activity"); else DMLAChanged(nil);
}
static void DMLAAppsHeard(id item, int what) {
    if (!item || !gLAAppsOn || ![item isKindOfClass:objc_getClass("SBActivityItem")]) return;
    id ident = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("identifier"));
    id desc = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("descriptor"));
    id bid = [desc isKindOfClass:objc_getClass("ACActivityDescriptor")] ? ((id (*)(id, SEL))objc_msgSend)(desc, sel_registerName("platterTargetBundleIdentifier")) : nil;
    double rel = ((double (*)(id, SEL))objc_msgSend)(item, sel_registerName("relevanceScore"));
    NSString *i = [ident isKindOfClass:[NSString class]] ? [ident copy] : nil, *b = [bid isKindOfClass:[NSString class]] ? [bid copy] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{ DMLAAppsUse(i, b, isfinite(rel) ? rel : 0.0, what); });
}
// The Apps kind on or off (DMLAApplyPrefs): our observer added to SpringBoard's manager where the check passed, removed again when off.
static void DMLAAppsApply(BOOL on) {
    if (on == gLAAppsOn) return;
    if (on && !DMLAAppsCheck()) return;
    id mgr = DMLAAppsManager();
    if (!mgr) return;
    gLAAppsOn = on;
    if (on) {
        if (!gLAObserver) {
            gLAObserver = [DMLAActivityObserver new];
            Protocol *p = objc_getProtocol("SBActivityObserver");
            if (p) class_addProtocol([DMLAActivityObserver class], p);
        }
        ((void (*)(id, SEL, id))objc_msgSend)(mgr, sel_registerName("addObserver:"), gLAObserver);
        id items = ((id (*)(id, SEL))objc_msgSend)(mgr, sel_registerName("itemByActivityIdentifier"));
        NSUInteger n = 0;
        if ([items isKindOfClass:[NSDictionary class]]) for (id item in [(NSDictionary *)items allValues]) { DMLAAppsHeard(item, 0); n++; }
        DMLog([NSString stringWithFormat:@"[liveact] apps: observing SpringBoard's activities (%lu now)", (unsigned long)n]);
    } else {
        if (gLAObserver) ((void (*)(id, SEL, id))objc_msgSend)(mgr, sel_registerName("removeObserver:"), gLAObserver);
        DMLADropKind(kMSBDLAApp);
        DMLog(@"[liveact] apps: no longer observed");
    }
}
static void DMLAAppsOpen(NSString *uid) {
    DMLAItem *it = gLAItems[uid];
    if (it.bundleID.length && !it.fake) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMOpenApp(it.bundleID); });
}

// ---- the card's live view (hosting) ----
// The app's own Lock Screen view, as CoverSheet and the activity banner host it: ActivityUIServices' factory with the item's descriptor and Lock
// Screen metrics (our card's width, a height between 60 and 220 pt, the card's corner). Made only while its card is open; invalidated with it.
@interface DMLAHostDelegate : NSObject
@property (nonatomic, copy) NSString *uid;
@end
@implementation DMLAHostDelegate
- (void)activityHostViewController:(id)host requestsLaunchWithAction:(id)action { NSString *u = self.uid; dispatch_async(dispatch_get_main_queue(), ^{ DMCloseOverlay(); DMLAAppsOpen(u); }); }
- (void)activityHostViewController:(id)host didSetIdleTimerDisabled:(BOOL)disabled {}
- (void)activityHostViewControllerBackgroundTintColorDidChange:(id)host {}
- (void)activityHostViewControllerHostShouldCancelTouches:(id)host {}
- (void)activityHostViewControllerAudioCategoriesDisablingVolumeHUDDidChange:(id)host {}
@end
// One live view per activity while its card is open (review 1.8.4 M2): made at the card that first shows it, moved into every rebuild of that card,
// torn down when the card no longer has the activity or closes. The host is a child view controller of a controller of ours whose view is the
// slot it shows in (our menus' window has no controller of its own), and is told when it appears and goes.
@interface DMLAHostRecord : NSObject
@property (nonatomic, strong) UIViewController *host, *parent;
@property (nonatomic, strong) DMLAHostDelegate *delegate;
@property (nonatomic, strong) UIView *slot;
@property (nonatomic) BOOL appeared;
@end
@implementation DMLAHostRecord
@end
static NSMutableDictionary<NSString *, DMLAHostRecord *> *gLAHosts = nil;   // uid -> its live view, while its card is open
static int gLAHostVerdict = -1;
#if DEBUG
static BOOL gLAHostForced = NO;   // (tests on a debug build: la_host_try -- the live view tried where its rows check out, before its version is listed)
#endif
static BOOL DMLAAppsHostOK(void) {
    if (gLAHostVerdict >= 0) return gLAHostVerdict == 1;
    BOOL listed = DMLAAppsListedHere(YES);
#if DEBUG
    listed = listed || (gLAHostForced && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17);
#endif
    if (!listed) { gLAHostVerdict = 0; return NO; }
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    BOOL ok = DMLATypesOK(kDMLAAppHostNeeds, sizeof kDMLAAppHostNeeds / sizeof kDMLAAppHostNeeds[0], missing);
    gLAHostVerdict = ok ? 1 : 0;
    DMLog([NSString stringWithFormat:@"[liveact] apps: the live view %@%@", ok ? @"checks out" : @"not as read: icon and name only",
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
    return ok;
}
static CGFloat DMLAAppsHostHeight(UIViewController *host) {   // (its own wish, kept between 60 and 220 pt; 160 without one)
    CGSize pref = host.preferredContentSize;
    return (isfinite(pref.height) && pref.height >= 1.0) ? MIN(220.0, MAX(60.0, pref.height)) : 160.0;
}
static UIView *DMLAAppsHostedView(NSString *uid, CGFloat width, CGFloat *height) {
    if (!DMLAAppsLive() || ![uid hasPrefix:@"app:"] || !DMLAAppsHostOK()) return nil;
    DMLAHostRecord *r = gLAHosts[uid];
    if (r) {   // (this card's view already: moved into the rebuilt section, at its size now)
        *height = DMLAAppsHostHeight(r.host);
        r.slot.frame = CGRectMake(0, 0, width, *height);
        return r.slot;
    }
    id mgr = DMLAAppsManager();
    id items = mgr ? ((id (*)(id, SEL))objc_msgSend)(mgr, sel_registerName("itemByActivityIdentifier")) : nil;
    id item = [items isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)items)[[uid substringFromIndex:4]] : nil;
    id desc = [item isKindOfClass:objc_getClass("SBActivityItem")] ? ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("descriptor")) : nil;
    if (![desc isKindOfClass:objc_getClass("ACActivityDescriptor")]) return nil;
    Class dim = objc_getClass("ACUISSizeDimensionRequest"), itemReq = objc_getClass("ACUISActivityItemMetricsRequest"), req = objc_getClass("ACUISActivityMetricsRequest");
    id w = ((id (*)(id, SEL, double))objc_msgSend)((id)dim, sel_registerName("fixed:"), width);
    id h = ((id (*)(id, SEL, double, double))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)((id)dim, sel_registerName("alloc")), sel_registerName("initWithMinimum:maximum:"), 60.0, 220.0);
    id im = (w && h) ? ((id (*)(id, SEL, id, id, double))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)((id)itemReq, sel_registerName("alloc")), sel_registerName("initWithWidth:height:cornerRadius:"), w, h, 12.0) : nil;
    id metrics = im ? ((id (*)(id, SEL, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)((id)req, sel_registerName("alloc")), sel_registerName("initWithLockScreenMetrics:"), im) : nil;
    id host = metrics ? ((id (*)(id, SEL, id, id))objc_msgSend)((id)objc_getClass("ACUISActivityHostViewControllerFactory"), sel_registerName("activityHostViewControllerWithDescriptor:metricsRequest:"), desc, metrics) : nil;
    if (![host isKindOfClass:[UIViewController class]]) return nil;
    DMLAHostDelegate *d = [DMLAHostDelegate new]; d.uid = uid;
    ((void (*)(id, SEL, id))objc_msgSend)(host, sel_registerName("setDelegate:"), d);
    r = [DMLAHostRecord new];
    r.host = host; r.delegate = d;
    r.slot = [UIView new]; r.slot.clipsToBounds = YES;
    r.parent = [UIViewController new]; r.parent.view = r.slot;
    *height = DMLAAppsHostHeight(host);
    r.slot.frame = CGRectMake(0, 0, width, *height);
    [r.parent addChildViewController:host];
    UIViewController *vc = host;
    vc.view.frame = r.slot.bounds; vc.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [r.slot addSubview:vc.view];
    [host didMoveToParentViewController:r.parent];
    if (!gLAHosts) gLAHosts = [NSMutableDictionary dictionary];
    gLAHosts[uid] = r;
    DMLog([NSString stringWithFormat:@"[liveact] apps: live view made for %@ (%.0f pt high)", DMLAShort(uid), *height]);
    return r.slot;
}
static void DMLAAppsHostsAppear(void) {   // (the live views now in a card on the screen: their appearance, once each)
    for (DMLAHostRecord *r in gLAHosts.allValues) {
        if (r.appeared || !r.slot.window) continue;
        [r.parent beginAppearanceTransition:YES animated:NO]; [r.parent endAppearanceTransition];
        r.appeared = YES;
    }
}
static void DMLAAppsHostTearDown(NSString *uid) {
    DMLAHostRecord *r = gLAHosts[uid];
    if (!r) return;
    if (r.appeared) [r.parent beginAppearanceTransition:NO animated:NO];
    [r.host willMoveToParentViewController:nil];
    [r.host.view removeFromSuperview];
    [r.host removeFromParentViewController];
    if (r.appeared) [r.parent endAppearanceTransition];
    ((void (*)(id, SEL))objc_msgSend)(r.host, sel_registerName("invalidate"));
    [gLAHosts removeObjectForKey:uid];
    DMLog([NSString stringWithFormat:@"[liveact] apps: the live view of %@ invalidated", DMLAShort(uid)]);
}
static void DMLAAppsHostsKeep(NSSet<NSString *> *uids) {   // (after a rebuild of the open card: those no section of it holds go)
    for (NSString *uid in gLAHosts.allKeys) if (![uids containsObject:uid]) DMLAAppsHostTearDown(uid);
}
static void DMLAAppsCardGone(void) {
    for (NSString *uid in gLAHosts.allKeys) DMLAAppsHostTearDown(uid);
}

#if DEBUG
// ---- the device step before any of it is turned on (plans/v184.md): read-only logs of the classes, methods and protocols this path and the
// timers and calls use, on the 17.5 and the A12Z (and 15.6.1 / 16.7.7 for MobileTimer and TelephonyUtilities) ----
// la_probe: no call into any of these classes -- only the runtime's lists of their methods with their types, and the protocols' method lists.
// la_probe_items (17+): also SpringBoard's manager as it is (+sharedInstance, -isActivitySupported, -itemByActivityIdentifier: each item's id as a
// short hash, its app, relevance and start) and, where our timer manager runs, each timer's state word (+[MTTimer descriptionForState:]).
static void DMLAAppsProbeClass(NSMutableString *out, const char *name, NSArray<NSString *> *words) {
    Class c = objc_getClass(name);
    if (!c) { [out appendFormat:@"\n  %s: not there", name]; return; }
    Dl_info info; const char *img = dladdr((__bridge void *)c, &info) && info.dli_fname ? strrchr(info.dli_fname, '/') : NULL;
    [out appendFormat:@"\n  %s : %s (%s)", name, class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "-", img ? img + 1 : "?"];
    for (int meta = 1; meta >= 0; meta--) {
        unsigned n = 0;
        Method *ms = class_copyMethodList(meta ? object_getClass((id)c) : c, &n);
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (unsigned i = 0; i < n; i++) {
            NSString *s = NSStringFromSelector(method_getName(ms[i]));
            if (words) { BOOL hit = NO; for (NSString *w in words) if ([s rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; } if (!hit) continue; }
            [lines addObject:[NSString stringWithFormat:@"%c%@ %s", meta ? '+' : '-', s, method_getTypeEncoding(ms[i]) ?: "?"]];
        }
        free(ms);
        [lines sortUsingSelector:@selector(compare:)];
        for (NSString *l in lines) [out appendFormat:@"\n    %@", l];
    }
}
static void DMLAAppsProbeProtocol(NSMutableString *out, const char *name) {
    Protocol *p = objc_getProtocol(name);
    if (!p) { [out appendFormat:@"\n  protocol %s: not there", name]; return; }
    [out appendFormat:@"\n  protocol %s", name];
    for (int req = 1; req >= 0; req--) {
        unsigned n = 0;
        struct objc_method_description *d = protocol_copyMethodDescriptionList(p, req, YES, &n);
        for (unsigned i = 0; i < n; i++) [out appendFormat:@"\n    %@ -%s %s", req ? @"required" : @"optional", sel_getName(d[i].name), d[i].types ?: "?"];
        free(d);
    }
}
static void DMLAAppsProbeNeeds(NSMutableString *out, NSString *title, const DMLANeedRow *rows, size_t n) {
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    BOOL ok = DMLATypesOK(rows, n, missing);
    [out appendFormat:@"\n  %@: %@%@", title, ok ? @"every required row as read" : @"NOT as read", missing.count ? [@" -- " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""];
}
static BOOL DMLAAppsTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"la_probe"]) {
        NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
        NSMutableString *out = [NSMutableString stringWithFormat:@"[laprobe] iPadOS %ld.%ld.%ld (read-only: method lists and protocols, nothing called)", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
        static const char *const classes[] = { "SBActivityManager", "SBActivityItem", "SBActivityCoverSheetObserver", "SBActivityBannerObserver", "SBActivityViewController",
                                               "SBActivityBannerViewController", "SBLiveActivitySettings", "ACActivityDescriptor", "ACActivityContentUpdate", "ACActivityContent",
                                               "ACActivityCenter", "ACUISActivityHostViewControllerFactory", "ACUISActivityHostViewController", "ACUISActivityMetricsRequest",
                                               "ACUISActivityItemMetricsRequest", "ACUISSizeDimensionRequest", "ACUISSystemApertureMetricsRequest", "ACUISSystemApertureSceneHandle",
                                               "CSActivityManager", "CSListItemActivityProvider", "CSActivityItemViewController", "MTTimerManager", "MTTimer" };
        for (size_t i = 0; i < sizeof classes / sizeof classes[0]; i++) DMLAAppsProbeClass(out, classes[i], nil);
        NSArray *callWords = @[@"sharedInstance", @"currentCalls", @"disconnectCall", @"uniqueProxyIdentifier", @"isConnected", @"isOnHold", @"isIncoming",
                               @"callDuration", @"displayName", @"UplinkMuted", @"isVideo", @"provider", @"isEndpointOnCurrentDevice"];
        DMLAAppsProbeClass(out, "TUCallCenter", callWords);
        DMLAAppsProbeClass(out, "TUCall", callWords);
        DMLAAppsProbeClass(out, "TUCallProvider", @[@"bundleIdentifier"]);
        static const char *const protocols[] = { "SBActivityObserver", "SBActivityObservable", "ACUISActivityHostViewControllerDelegate", "SBActivityBannerViewControllerDelegate" };
        for (size_t i = 0; i < sizeof protocols / sizeof protocols[0]; i++) DMLAAppsProbeProtocol(out, protocols[i]);
        DMLAAppsProbeNeeds(out, @"timers (kDMLATimerNeeds)", kDMLATimerNeeds, sizeof kDMLATimerNeeds / sizeof kDMLATimerNeeds[0]);
        DMLAAppsProbeNeeds(out, @"calls (kDMLACallNeeds)", kDMLACallNeeds, sizeof kDMLACallNeeds / sizeof kDMLACallNeeds[0]);
        DMLAAppsProbeNeeds(out, @"apps' pills (kDMLAAppListNeeds)", kDMLAAppListNeeds, sizeof kDMLAAppListNeeds / sizeof kDMLAAppListNeeds[0]);
        DMLAAppsProbeNeeds(out, @"apps' live view (kDMLAAppHostNeeds)", kDMLAAppHostNeeds, sizeof kDMLAAppHostNeeds / sizeof kDMLAAppHostNeeds[0]);
        { NSMutableArray *m = [NSMutableArray array]; BOOL covers = DMLAAppsObserverCovers(objc_getProtocol("SBActivityObserver"), m);
          [out appendFormat:@"\n  our observer answers every required method: %@%@", covers ? @"yes" : @"NO", m.count ? [@" -- " stringByAppendingString:[m componentsJoinedByString:@", "]] : @""]; }
        DMLog(out);
        return YES;
    }
    if ([cmd isEqualToString:@"la_probe_items"]) {
        NSMutableString *out = [NSMutableString stringWithString:@"[laprobe] items:"];
        if (gLATimersOK && gLATimerMgr && DMLATypes(objc_getClass("MTTimer"), "descriptionForState:", "@24@0:8Q16", YES)) {
            Class tc = objc_getClass("MTTimer");
            [out appendString:@"\n  MTTimer states:"];
            for (unsigned long long s = 0; s <= 6; s++) {
                id d = ((id (*)(id, SEL, unsigned long long))objc_msgSend)((id)tc, sel_registerName("descriptionForState:"), s);
                [out appendFormat:@" %llu=%@", s, d ?: @"-"];
            }
        }
        if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17 || DMProcessAge() < 30.0) { [out appendString:@"\n  (SpringBoard's activities: 17+, 30 s after the start)"]; DMLog(out); return YES; }
        NSMutableArray *missing = [NSMutableArray array];
        if (!DMLATypesOK(kDMLAAppListNeeds, sizeof kDMLAAppListNeeds / sizeof kDMLAAppListNeeds[0], missing)) { [out appendFormat:@"\n  not asked: %@", [missing componentsJoinedByString:@", "]]; DMLog(out); return YES; }
        id mgr = DMLAAppsManager();
        if (DMLATypes(object_getClass(mgr), "isActivitySupported", "B16@0:8", NO)) [out appendFormat:@"\n  isActivitySupported %d", ((BOOL (*)(id, SEL))objc_msgSend)(mgr, sel_registerName("isActivitySupported"))];
        id items = mgr ? ((id (*)(id, SEL))objc_msgSend)(mgr, sel_registerName("itemByActivityIdentifier")) : nil;
        [out appendFormat:@"\n  itemByActivityIdentifier: %@ with %lu item(s)", items ? NSStringFromClass([items class]) : @"nil", (unsigned long)([items isKindOfClass:[NSDictionary class]] ? [(NSDictionary *)items count] : 0)];
        if ([items isKindOfClass:[NSDictionary class]]) for (id item in [(NSDictionary *)items allValues]) {
            if (![item isKindOfClass:objc_getClass("SBActivityItem")]) { [out appendFormat:@"\n    (a %@, not an item: not asked)", NSStringFromClass([item class])]; continue; }
            id ident = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("identifier"));
            id desc = ((id (*)(id, SEL))objc_msgSend)(item, sel_registerName("descriptor"));
            id bid = [desc isKindOfClass:objc_getClass("ACActivityDescriptor")] ? ((id (*)(id, SEL))objc_msgSend)(desc, sel_registerName("platterTargetBundleIdentifier")) : nil;
            double rel = ((double (*)(id, SEL))objc_msgSend)(item, sel_registerName("relevanceScore"));
            [out appendFormat:@"\n    %@ (%@) app %@ relevance %.3f descriptor %@", DMLAShort([ident description]), NSStringFromClass([item class]), bid ?: @"-", rel, desc ? NSStringFromClass([desc class]) : @"nil"];
        }
        DMLog(out);
        return YES;
    }
    if ([cmd isEqualToString:@"la_host_try"]) {   // (a debug build only, after la_probe showed the live view's rows and la_apps_try lists: the next card hosts the app's view)
        gLAHostForced = YES; gLAHostVerdict = -1;
        DMLog([NSString stringWithFormat:@"[liveact] apps: the live view will be tried in the next card (%@)", DMLAAppsHostOK() ? @"its rows check out" : @"its rows do NOT check out: not tried"]);
        return YES;
    }
    if ([cmd isEqualToString:@"la_apps_try"]) {   // (a debug build only, after la_probe showed every row: the listing on this iPad now, before its version is listed)
        gLAAppsForced = YES; gLAAppsVerdict = -1;
        DMLAAppsApply(NO); DMLAAppsApply(gLAOn && gLAKindOn[kMSBDLAApp]);
        DMLog([NSString stringWithFormat:@"[liveact] apps: tried on this build: %@", DMLAAppsLive() ? @"observing" : @"not on (see the check above)"]);
        return YES;
    }
    return NO;
}
#endif
