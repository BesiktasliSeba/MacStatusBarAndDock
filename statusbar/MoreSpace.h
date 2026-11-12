// MoreSpace.h -- More Space: a display's scale, as iPadOS offers it (MacStatusBar&Dock 1.8.7 commit 13; plans/design-1.8.7-displays.md sections 4
// and 8). Included by StatusBar.x before DisplaySettings.h. The rules are plain C (common/DisplayScale.h, tools/test-displayscale.c).
//  - Apple's own call, no hooks: SpringBoard's external display service (SBSExternalDisplayService, what Settings' own display page uses) lists each
//    connected display's scales and the one in use; they are written into the display's info in the registry (scales, scaleNow, scaleNames, overscan),
//    read when SpringBoard starts, when a display connects and after a change. Only a scale iPadOS lists is ever made (SpringBoardServices asserts on
//    any other: S2, 11 Nov). The A12Z's 4K TV and the iPad 2's 1080p TV list one: no Resolution row there, the code below only reads.
//  - A choice (the Display menu, the Display Settings window, Settings' page by a request key the page writes) is set through the same service, then
//    kept or reverted: a question on the iPad's screen (the display that changed may go dark or reconnect while it changes) that reverts by itself
//    after 15 s. Before the change SpringBoard keeps what it was ("<display>/disp/scalePending" = {old, new, at}); a start within 2 min of a change
//    never kept or reverted sets the old one back; the record goes when the change is kept or reverted, or after 60 s.
//  - Its own switch (displayScale in the displays domain, the crash guard's target): off, or Display Settings off, nothing here runs but the start's
//    revert of a change never kept.
//  - Review fixes: one client of Apple's service per call, kept by its own answer (a shared one, let go by whichever answer came first, could lose a
//    pending set or revert); the set's completion takes no parameters (their shape was never read: no display here lists two scales) and the outcome
//    is read back from the display's scale in use; the start's revert keeps its record until it is taken (or nothing is left to take back, or the
//    2 minutes are over), trying again when a display connects; the question closes only its own card and comes back if another menu took its place.
#pragma once
#include "../common/DisplayScale.h"

static BOOL DMMoreSpaceOn(void) { return MSBDDispStoreScaleOn(MSBDDispStoreAll()); }
// SpringBoard's connected displays' infos (SBSConnectedDisplayInfo), on the main queue, with the client that asked. One client of Apple's service per
// call: its completion holds it until the answer (never a shared one that another call's answer could let go). The call shape-checked; this getter's
// answer (an array, then an error) was read on 16.7.7 and 18.5.
static void DMMoreSpaceInfos(void (^done)(NSArray *infos, id client)) {
    Class K = objc_getClass("SBSExternalDisplayService");
    SEL g = sel_registerName("getConnectedDisplayInfoWithCompletionHandler:");
    id client = nil;
    if (K) { @try { client = [K new]; } @catch (NSException *e) {} }
    Method m = client ? class_getInstanceMethod(object_getClass(client), g) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v24@0:8@?16") != 0) { DMLog(@"[morespace] no SBSExternalDisplayService -getConnectedDisplayInfoWithCompletionHandler: as expected: no scales read"); done(@[], nil); return; }
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(client, g, ^(NSArray *infos, id err) {
            NSArray *list = [infos isKindOfClass:[NSArray class]] ? [infos copy] : @[];
            dispatch_async(dispatch_get_main_queue(), ^{ done(list, client); });   // (the client lives until here: this block holds it)
        });
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[morespace] asking the displays: %@", e.reason]); done(@[], nil); }
}
// SBSDisplayModeSettings for a listed scale (nil when the class or its initializer is not of the read shape, or the scale is not listed).
static id DMMoreSpaceMake(unsigned long long mask, int scale, long long overscan) {
    if (!MSBDDispScaleIsListed(mask, scale)) return nil;
    Class SC = objc_getClass("SBSDisplayModeSettings");
    SEL init = sel_registerName("initWithScale:overscanCompensation:");
    Method im = SC ? class_getInstanceMethod(SC, init) : NULL;
    if (!im || strcmp(method_getTypeEncoding(im) ?: "", "@32@0:8Q16q24") != 0) return nil;
    @try { return ((id (*)(id, SEL, unsigned long long, long long))objc_msgSend)([SC alloc], init, (unsigned long long)scale, overscan); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[morespace] scale %d refused by SpringBoardServices: %@", scale, e.reason]); return nil; }
}
static NSString *DMMoreSpaceKeyOf(id info) {
    NSString *ident = MSBDDispStr(MSBDDispGet(info, "identifier"));
    char key[96];
    return ident && MSBDDispKeyFrom(0, ident.UTF8String, NULL, key, sizeof key) == kMSBDDispKeyId ? @(key) : nil;
}
static id DMMoreSpaceInfoOf(NSArray *infos, NSString *display) {
    for (id i in infos) if ([DMMoreSpaceKeyOf(i) isEqualToString:display]) return i;
    return nil;
}
// What iPadOS offers each connected display, into its info (only what was read; written when it changed).
static void DMMoreSpaceRead(NSString *why) {
    if (!DMMoreSpaceOn()) return;
    DMMoreSpaceInfos(^(NSArray *infos, id client) {
        CFStringRef dom = CFSTR(MSBD_DISP_DOMAIN);
        NSDictionary *all = MSBDDispStoreAll();
        BOOL wrote = NO;
        for (id i in infos) {
            NSString *d = DMMoreSpaceKeyOf(i);
            NSDictionary *old = MSBDDispStoreInfo(all, d);
            if (!d || !old) continue;   // (a display the registry has not written yet: the next read has it)
            unsigned long long mask = DMDispGetUnsigned(i, "supportedScales");
            id st = MSBDDispGet(i, "displayModeSettings");
            long long ov = (long long)DMDispGetUnsigned(st, "overscanCompensation");
            int now = (int)DMDispGetUnsigned(st, "scale");
            char name[32];
            NSMutableDictionary *info = [old mutableCopy], *names = [NSMutableDictionary dictionary];
            info[@"scales"] = @(mask); info[@"scaleNow"] = @(now);
            NSString *desc = MSBDDispStr(MSBDDispGet(st, "description"));
            if (desc && MSBDDispScaleFieldName(desc.UTF8String, "overscan", name, sizeof name)) info[@"overscan"] = @(name);
            int listed[MSBD_DISP_SCALE_MAX];
            int n = MSBDDispScaleListed(mask, listed, MSBD_DISP_SCALE_MAX);
            for (int k = 0; k < n && n >= 2; k++) {   // (Apple's names, only for a choice; only listed scales are made)
                NSString *dsc = MSBDDispStr(MSBDDispGet(DMMoreSpaceMake(mask, listed[k], ov), "description"));
                if (dsc && MSBDDispScaleFieldName(dsc.UTF8String, "scale", name, sizeof name)) names[[NSString stringWithFormat:@"%d", listed[k]]] = @(name);
            }
            if (names.count) info[@"scaleNames"] = names; else [info removeObjectForKey:@"scaleNames"];
            if ([info isEqualToDictionary:old]) continue;
            CFPreferencesSetValue((__bridge CFStringRef)[d stringByAppendingString:@MSBD_DISP_INFO_SUFFIX], (__bridge CFPropertyListRef)info, dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            wrote = YES;
            DMLog([NSString stringWithFormat:@"[morespace] %@ (%@): scales %llu (%d listed%@), in use %d, overscan %@", d, why, mask, n, n >= 2 ? @": a Resolution row" : @": no row", now, info[@"overscan"] ?: @"?"]);
        }
        if (wrote) { CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); notify_post(MSBD_DISP_NOTIFY); }
    });
}
// (A display's choices for the menu, the window and Settings' page: common/DisplayRowStore.h MSBDDispStoreScaleChoices.)
static void DMMoreSpacePending(NSString *display, NSDictionary *record) {   // (nil: the record goes)
    MSBDDispStoreWrite(display, "disp", MSBD_DISP_SCALE_PENDING_KEY, record, NO, nil);
}
// The record goes only while it is still the one made at `at` (a newer change keeps its own).
static BOOL DMMoreSpaceDropRecord(NSString *display, long at) {
    char flat[MSBD_DISP_FLAT_MAX + 1];
    NSDictionary *rec = display && MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, "disp", MSBD_DISP_SCALE_PENDING_KEY) ? MSBDDispStoreAll()[@(flat)] : nil;
    if (![rec isKindOfClass:[NSDictionary class]] || [rec[@"at"] longValue] != at) return NO;
    DMMoreSpacePending(display, nil);
    return YES;
}
// A set's outcome, on the main queue: took (the display reads the scale asked for, or could not be read: DisplayScale.h MSBDDispScaleSetTook), listed
// (the display was in SpringBoard's info), its scales, and its scale in use before the set (or now, when no set was made).
typedef void (^DMMoreSpaceThen)(BOOL took, BOOL listed, unsigned long long mask, int was);
// The scale in use read back after a set's answer (a new client each read): a display not listed yet (it may reconnect after a scale change) is read
// again 1.5 s later, up to three reads.
static void DMMoreSpaceReadBack(NSString *display, int want, int was, int tries, DMMoreSpaceThen then) {
    DMMoreSpaceInfos(^(NSArray *infos, id client) {
        id info = DMMoreSpaceInfoOf(infos, display);
        if (!info && tries < 2) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMoreSpaceReadBack(display, want, was, tries + 1, then); });
            return;
        }
        unsigned long long mask = DMDispGetUnsigned(info, "supportedScales");
        int now = (int)DMDispGetUnsigned(MSBDDispGet(info, "displayModeSettings"), "scale");
        BOOL took = MSBDDispScaleSetTook(info != nil, now, want);
        DMLog([NSString stringWithFormat:@"[morespace] %@: scale %d asked, read back %@", display, want, info ? [NSString stringWithFormat:@"%d in use%@", now, took ? @"" : @" (not taken)"] : @"never (the display not listed: taken as done)"]);
        if (then) then(took, info != nil, mask, was);
        DMMoreSpaceRead(@"after a change");
    });
}
// Sets a scale through Apple's service (it must be listed and not in use), with the client that answered the info: the set's completion holds it until
// it is called. That completion is taken as "answered" only and takes no parameters: their shape was never read (no display here lists two scales,
// so the call never ran; calling a block with more arguments than it takes is harmless on arm64), so nothing of Apple's answer is kept or printed.
// Whether the scale took is read back (DMMoreSpaceReadBack). `then` on the main queue.
static void DMMoreSpaceApply(NSString *display, int want, BOOL record, DMMoreSpaceThen then) {
    DMMoreSpaceInfos(^(NSArray *infos, id client) {
        id info = DMMoreSpaceInfoOf(infos, display);
        unsigned long long mask = DMDispGetUnsigned(info, "supportedScales");
        id st = MSBDDispGet(info, "displayModeSettings");
        int cur = (int)DMDispGetUnsigned(st, "scale");
        long long ov = (long long)DMDispGetUnsigned(st, "overscanCompensation");
        NSString *ident = MSBDDispStr(MSBDDispGet(info, "identifier"));
        id settings = MSBDDispScaleCanSet(mask, cur, want) ? DMMoreSpaceMake(mask, want, ov) : nil;
        SEL set = sel_registerName("setSettings:forDisplay:options:completionHandler:");
        Method m = client ? class_getInstanceMethod(object_getClass(client), set) : NULL;
        if (!settings || !ident || !m || strcmp(method_getTypeEncoding(m) ?: "", "v48@0:8@16@24Q32@?40") != 0) {
            DMLog([NSString stringWithFormat:@"[morespace] %@: scale %d not set (%@listed %llu, in use %d, setter %s)", display, want, info ? @"" : @"the display not listed; ", mask, cur, m ? "as read" : "missing"]);
            if (then) then(NO, info != nil, mask, cur); return;
        }
        long at = (long)time(NULL);
        if (record) {
            DMMoreSpacePending(display, @{ @"old": @(cur), @"new": @(want), @"at": @(at) });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MSBD_DISP_SCALE_DROP_AFTER * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{   // (still unresolved after 60 s, SpringBoard running: dropped)
                if (MSBDDispScaleDropNow((long)time(NULL), at) && DMMoreSpaceDropRecord(display, at)) DMLog([NSString stringWithFormat:@"[morespace] %@: the change's record dropped (60 s)", display]);
            });
        }
        DMLog([NSString stringWithFormat:@"[morespace] %@: scale %d -> %d asked", display, cur, want]);
        id keep = client;
        void (^answered)(void) = ^{   // (no parameters: see above)
            dispatch_async(dispatch_get_main_queue(), ^{
                (void)keep;   // (the client kept until its answer)
                DMLog([NSString stringWithFormat:@"[morespace] %@: scale %d answered", display, want]);
                DMMoreSpaceReadBack(display, want, cur, 0, then);
            });
        };
        @try {
            ((void (*)(id, SEL, id, id, unsigned long long, id))objc_msgSend)(client, set, settings, ident, 0ULL, answered);
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[morespace] %@: the set refused: %@", display, e.reason]); if (record) DMMoreSpaceDropRecord(display, at); if (then) then(NO, YES, mask, cur); }
    });
}
// Keep or revert, on the iPad's screen: reverts by itself after 15 s. The question closes only its own card (a menu or dialog opened over it since stays
// open), and comes back once nothing else is open if another one took its place; the time keeps running.
static NSTimer *gDMMoreSpaceTimer;
static __weak UIView *gDMMoreSpaceQuestion;   // (the question's own overlay while it shows)
static void DMMoreSpaceAsk(NSString *display, int old) {
    __block BOOL answered = NO;
    long asked = (long)time(NULL);
    void (^finish)(BOOL) = ^(BOOL keep) {
        if (answered) return;
        answered = YES;
        [gDMMoreSpaceTimer invalidate]; gDMMoreSpaceTimer = nil;
        UIView *q = gDMMoreSpaceQuestion;
        gDMMoreSpaceQuestion = nil;
        if (q && gOverlay == q) DMCloseOverlay();   // (only its own card)
        DMLog([NSString stringWithFormat:@"[morespace] %@: %@", display, keep ? @"kept" : @"reverted"]);
        char flat[MSBD_DISP_FLAT_MAX + 1];
        NSDictionary *rec = MSBDDispFlatKey(flat, sizeof flat, display.UTF8String, "disp", MSBD_DISP_SCALE_PENDING_KEY) ? MSBDDispStoreAll()[@(flat)] : nil;
        long at = [rec isKindOfClass:[NSDictionary class]] ? [rec[@"at"] longValue] : 0;
        if (keep) { if (at) DMMoreSpaceDropRecord(display, at); return; }
        DMMoreSpaceApply(display, old, NO, ^(BOOL took, BOOL listed, unsigned long long mask, int was) {   // (not taken back: the record stays for its 60 s, and a crash meanwhile reverts at the start)
            if (at && MSBDDispScaleRevertDone(took, listed, mask, was, old)) DMMoreSpaceDropRecord(display, at);
        });
    };
    __block __weak UILabel *wc = nil;
    void (^show)(void) = ^{
        UIView *host = DMMenuHost();
        if (!host) return;
        UIControl *o = DMMakeOverlay(host, 0.25);
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 130)];
        card.center = CGPointMake(CGRectGetMidX(o.bounds), CGRectGetMidY(o.bounds));
        card.backgroundColor = [UIColor systemBackgroundColor]; card.layer.cornerRadius = 12; card.layer.cornerCurve = kCACornerCurveContinuous;
        card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, 268, 22)];
        t.text = @"Keep this resolution?"; t.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; t.textAlignment = NSTextAlignmentCenter;
        [card addSubview:t];
        UILabel *count = [[UILabel alloc] initWithFrame:CGRectMake(16, 40, 268, 20)];
        count.font = [UIFont systemFontOfSize:12]; count.textColor = [UIColor secondaryLabelColor]; count.textAlignment = NSTextAlignmentCenter;
        count.text = [NSString stringWithFormat:@"It goes back in %ld seconds.", MAX(0L, MSBD_DISP_SCALE_KEEP_SECONDS - ((long)time(NULL) - asked))];
        [card addSubview:count];
        NSArray *titles = @[@"Revert", @"Keep"];
        for (int i = 0; i < 2; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(16 + i * 140, 76, 128, 36);
            [b setTitle:titles[i] forState:UIControlStateNormal];
            b.titleLabel.font = [UIFont systemFontOfSize:15 weight:i ? UIFontWeightSemibold : UIFontWeightRegular];
            BOOL keep = i == 1;
            [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { finish(keep); }] forControlEvents:UIControlEventTouchUpInside];
            [card addSubview:b];
        }
        [o addSubview:card];
        gDMMoreSpaceQuestion = o; wc = count;
    };
    show();
    [gDMMoreSpaceTimer invalidate];
    gDMMoreSpaceTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *tm) {
        long now = (long)time(NULL);
        wc.text = [NSString stringWithFormat:@"It goes back in %ld seconds.", MAX(0L, MSBD_DISP_SCALE_KEEP_SECONDS - (now - asked))];
        if (MSBDDispScaleRevertsNow(answered, now, asked)) { finish(NO); return; }
        if (!answered && !gDMMoreSpaceQuestion.superview && !gOverlay) { DMLog([NSString stringWithFormat:@"[morespace] %@: the question shown again (another menu or dialog had taken its place)", display]); show(); }
    }];
}
// The start's revert of a change never kept, while it is still to be taken (display -> its record): tried 3 s after the start and again whenever a
// display connects, until it is taken, nothing is left to take back, or the record's 2 minutes are over (DisplayScale.h MSBDDispScaleStartRevertDrop).
static NSMutableDictionary<NSString *, NSDictionary *> *gDMMoreSpaceStartReverts;
static NSMutableSet<NSString *> *gDMMoreSpaceStartTrying;
static void DMMoreSpaceStartRevert(NSString *why) {
    for (NSString *display in [gDMMoreSpaceStartReverts.allKeys copy]) {
        if ([gDMMoreSpaceStartTrying containsObject:display]) continue;
        NSDictionary *rec = gDMMoreSpaceStartReverts[display];
        int old = [rec[@"old"] intValue];
        long at = [rec[@"at"] longValue];
        if (MSBDDispScaleAtStart(1, (long)time(NULL), at) != kMSBDDispScaleStartRevert) {
            [gDMMoreSpaceStartReverts removeObjectForKey:display];
            if (DMMoreSpaceDropRecord(display, at)) DMLog([NSString stringWithFormat:@"[morespace] %@: scale %d never set back (2 min since the change): the record dropped", display, old]);
            continue;
        }
        if (!gDMMoreSpaceStartTrying) gDMMoreSpaceStartTrying = [NSMutableSet set];
        [gDMMoreSpaceStartTrying addObject:display];
        DMMoreSpaceApply(display, old, NO, ^(BOOL took, BOOL listed, unsigned long long mask, int was) {
            [gDMMoreSpaceStartTrying removeObject:display];
            if (gDMMoreSpaceStartReverts[display] != rec) return;   // (a new choice since: it has its own record)
            if (MSBDDispScaleStartRevertDrop(took, listed, mask, was, old, (long)time(NULL), at)) {
                [gDMMoreSpaceStartReverts removeObjectForKey:display];
                DMMoreSpaceDropRecord(display, at);
                DMLog([NSString stringWithFormat:@"[morespace] %@ (%@): %@", display, why, took ? [NSString stringWithFormat:@"scale %d set back", old] : @"nothing to set back: the record dropped"]);
            } else DMLog([NSString stringWithFormat:@"[morespace] %@ (%@): scale %d not set back yet (%@): tried again when a display connects", display, why, old, listed ? @"the set refused" : @"the display not listed yet"]);
        });
    }
}
// A scale chosen (the Display menu, the window, Settings' page): set, then kept or reverted.
__attribute__((noinline)) static void DMMoreSpaceSet(NSString *display, int want) {
    if (!display || !DMMoreSpaceOn()) return;
    DM_FEATURE_MARK("more-space");
    [gDMMoreSpaceStartReverts removeObjectForKey:display];   // (a new choice: the start's revert of an older one is no longer wanted)
    DMMoreSpaceApply(display, want, YES, ^(BOOL took, BOOL listed, unsigned long long mask, int was) {
        if (took) DMMoreSpaceAsk(display, was); else DMMoreSpacePending(display, nil);
    });
}
// Settings' page asks by a request key (it has no screens and no service): set here, the key deleted.
static void DMMoreSpaceRequests(void) {
    NSDictionary *all = MSBDDispStoreAll();
    for (NSString *k in all) {
        char d[128], p[128], key[128];
        if (![k isKindOfClass:[NSString class]] || !MSBDDispFlatSplit(k.UTF8String, d, sizeof d, p, sizeof p, key, sizeof key)) continue;
        if (strcmp(p, "disp") != 0 || strcmp(key, MSBD_DISP_SCALE_REQUEST_KEY) != 0) continue;
        id v = all[k];
        MSBDDispStoreWrite(@(d), "disp", MSBD_DISP_SCALE_REQUEST_KEY, nil, NO, nil);
        if ([v isKindOfClass:[NSNumber class]]) { DMLog([NSString stringWithFormat:@"[morespace] %s: Settings asks for scale %@", d, v]); DMMoreSpaceSet(@(d), [v intValue]); }
    }
}
// The start: a change never kept or reverted (SpringBoard went down within 2 min of it) is taken back -- 3 s in, and again as displays connect, its
// record kept until then --; then the scales read, and read again with each display that connects; Settings' requests followed.
static void DMMoreSpaceInit(void) {
    NSDictionary *all = MSBDDispStoreAll();
    long now = (long)time(NULL);
    for (NSString *k in all) {
        char d[128];
        if (![k isKindOfClass:[NSString class]] || !MSBDDispFlatSplit(k.UTF8String, d, sizeof d, NULL, 0, NULL, 0) || ![k hasSuffix:@"/disp/" MSBD_DISP_SCALE_PENDING_KEY]) continue;
        NSDictionary *rec = [all[k] isKindOfClass:[NSDictionary class]] ? all[k] : nil;
        NSString *display = @(d);
        int what = MSBDDispScaleAtStart(rec != nil, now, [rec[@"at"] longValue]);
        if (what == kMSBDDispScaleStartRevert && [rec[@"old"] isKindOfClass:[NSNumber class]]) {
            DMLog([NSString stringWithFormat:@"[morespace] %@: SpringBoard started %ld s after a scale change never kept: scale %d to be set back", display, now - [rec[@"at"] longValue], [rec[@"old"] intValue]]);
            if (!gDMMoreSpaceStartReverts) gDMMoreSpaceStartReverts = [NSMutableDictionary dictionary];
            gDMMoreSpaceStartReverts[display] = rec;
            long left = [rec[@"at"] longValue] + MSBD_DISP_SCALE_CRASH_WINDOW - now + 1;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(1L, left) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMoreSpaceStartRevert(@"2 min since the change"); });
        } else { DMLog([NSString stringWithFormat:@"[morespace] %@: an old scale record dropped", display]); DMMoreSpacePending(display, nil); }
    }
    if (gDMMoreSpaceStartReverts.count) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMoreSpaceStartRevert(@"SpringBoard started"); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMoreSpaceRead(@"SpringBoard started"); DMMoreSpaceRequests(); });
    [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenDidConnectNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMMoreSpaceStartRevert(@"a display connected"); DMMoreSpaceRead(@"a display connected"); });
    }];
    static int token = 0;
    notify_register_dispatch(MSBD_DISP_NOTIFY, &token, dispatch_get_main_queue(), ^(int t) { if (DMMoreSpaceOn()) DMMoreSpaceRequests(); });
}
