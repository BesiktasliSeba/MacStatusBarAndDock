// LiveActivities.h -- Live Activities in the menu bar (MacStatusBar&Dock 1.8.4 item 1, as macOS 27.3 shows them), included into StatusBar.x after
// CC18Tiles.h. Plan: plans/release-1.8.4.md, plans/live-activities-research.md (KT's answers, 6 Nov). The rules: common/LiveActivities.h (plain C,
// tools/test-liveactivities.sh).
//
// A small black pill each, left of the menu bar's status icons (and of our own Wi-Fi, VPN, mute and SSH icons), in KT's order: a call (its time),
// a timer (its countdown), Now Playing (the artwork and moving bars), then other apps' Live Activities (17/18: LiveActivityApps.h). What does not
// fit before the bar's middle goes into a "+N" pill. A tap opens a card under the pill, in our menus' window, drawn by us: Now Playing's artwork,
// title, artist, scrubber and back / play-pause / forward; a timer's countdown with pause / resume and cancel; a call's name and time with mute and
// end; an app's activity. The card's title opens the app. An activity that ended (a timer that rang, a call hung up, music paused) stays greyed and
// tappable for MSBD_LA_ENDED_KEEP, then goes; one ended from its own card goes at once.
// Settings > Status Bar > Live Activities in Menu Bar (on unless switched off) with its page: Now Playing, Timers, Calls, Apps (each on unless off).
//
// Where each kind comes from (the same on iPadOS 15-18):
//  - Now Playing: MediaRemote, as our Control Center's Now Playing tile reads it (CCTiles.h), its info and whether it plays asked on our queue, the
//    artwork decoded there; the scrubber seeks with MRMediaRemoteSetElapsedTime. Its change notifications only mark it to be read again.
//  - Timers: MobileTimer's MTTimerManager (the client SpringBoard's own Lock Screen timer uses), our own instance, made once SpringBoard is up and
//    kept for its life (never freed: a private object's -dealloc can assume a life we never gave it -- the 22 Sep incident); its timers asked
//    through their NAFuture, read again on its change notifications. Pause / resume / cancel act on the current timer (-pauseCurrentTimer ...);
//    another timer's card opens the Clock app instead.
//  - Calls: TelephonyUtilities' TUCallCenter (as MixAudio's call check reads it, StatusBar.x DMAudioCallBundleIDs): the current calls with this iPad
//    as their end, read again on its call notifications; mute is the call's own -setUplinkMuted:, end -disconnectCall:. iOS's own call icon stays.
// Every private class and method is asked through a table of the exact types it was read with (DMLATypesOK): a part whose rows are not all there
// stays off, with a line in the log, and none of it is asked before SpringBoard has been up 8 s. Nothing runs while the switch is off; with the
// screen off the 1 s clock and the card's refresh stop (DMGateTimer). Logs never name a track, a caller or a timer: kinds, counts and short ids.
// Every engine and the side Dock: the pills are in the bar's copies and the card in our menus' window, as every other menu of the bar.
#pragma once
#include "../common/LiveActivities.h"

@class DMLAPill;
static void DMLAMenuGone(NSString *why);
static void DMLAChanged(NSString *why);
static void DMLARefreshPillsOf(NSString *uid);   // (an item's pills redrawn in place: below, with the pills)
static void DMLAStartSources(void);
static void DMLAOpenCard(DMLAPill *pill);
static BOOL DMLAAppsLive(void);           // (LiveActivityApps.h: the 17/18 path runs on this iPad)
static void DMLAAppsApply(BOOL on);
static void DMLAAppsOpen(NSString *uid);
static UIView *DMLAAppsHostedView(NSString *uid, CGFloat width, CGFloat *height);
static void DMLAAppsCardGone(void);
static void DMLAAppsHostsKeep(NSSet<NSString *> *uids);   // (LiveActivityApps.h: the live views no section of the open card holds any more go)
static void DMLAAppsHostTearDown(NSString *uid);          // (... one activity's live view goes now)
static void DMLAAppsHostsAppear(void);                     // (... and those now on the screen are told so)
enum { kDMLASrcNowPlaying = 0, kDMLASrcTimers, kDMLASrcCalls, kDMLASrcs };
static void DMLASrcChanged(int src, double delay, double minGap);   // (a source's change notification: read again, see below)

// ---- state -------------------------------------------------------------------------------------------------------------------------------------
static BOOL gLAOn = NO;                       // Settings > Status Bar > Live Activities in Menu Bar (DMLAApplyPrefs)
static BOOL gLAKindOn[kMSBDLAKinds];          // its page: Calls, Timers, Now Playing, Apps
static BOOL gLAApplied = NO;                  // (the switches applied once SpringBoard is up: DMLAApplyPrefs)
static double gLAKeep = MSBD_LA_ENDED_KEEP;   // (tests: la_keep_<s>)
static const void *kLAPillsKey = &kLAPillsKey;   // per bar copy: its pills (NSMutableArray<DMLAPill *>), direct subviews of the copy as our other items
static __weak DMLAPill *gLACardPill = nil;    // the pill whose card is open
static __weak UIView *gLACard = nil;          // the open card
static NSTimer *gLAClock = nil;               // 1 s while a pill shows a running clock (a timer, a connected call)
static NSTimer *gLACardTimer = nil;           // 0.5 s while a card is open
static NSMutableSet<NSString *> *gLAGoneAtOnce;   // uids ended from their own card: removed at once when their source drops them
static BOOL gLACardRebuildPending = NO;       // (a rebuild of the open card waits for a scrubber's drag to end: review 1.8.4 L6)
static void DMLARebuildOpenCard(void);

@interface DMLAItem : NSObject
@property (nonatomic) int kind;
@property (nonatomic, copy) NSString *uid, *bundleID, *title, *subtitle;
@property (nonatomic) double endedAt;         // CACurrentMediaTime of its end (0: live)
@property (nonatomic) double rank;            // the order in its kind (common/LiveActivities.h MSBDLACompare)
@property (nonatomic) BOOL fake;              // (tests: la_fake_ -- its buttons only log)
// a timer
@property (nonatomic) int timerState;         // kMSBDLATimerRunning / Paused / Ringing
@property (nonatomic) double fireAt;          // running: CACurrentMediaTime when it rings
@property (nonatomic) double left;            // paused: seconds left
@property (nonatomic) BOOL current;           // MobileTimer's current timer: the card's buttons act on it (where a timer can't be acted on by itself)
@property (nonatomic, strong) id timerObj;    // (its MTTimer as last read: 17's card buttons act on it -- DMLATimerActsOn)
// a call
@property (nonatomic) BOOL connected, held, incoming, muted, video;
@property (nonatomic) BOOL onThisDevice;      // (its end is this iPad, as TelephonyUtilities says: only then mute and end -- review 1.8.4 L7)
@property (nonatomic) double callStart;       // CACurrentMediaTime of the call's start, from its duration
@property (nonatomic, strong) id call;        // (TUCall: its mute and end; never logged)
// Now Playing
@property (nonatomic) BOOL playing;
@property (nonatomic) double pausedAt;        // when it was first seen paused (MSBDLANowPlayingEnded)
@property (nonatomic, strong) UIImage *art;
@property (nonatomic, copy) NSString *artKey;
@property (nonatomic) double elapsed, elapsedStamp, rate, duration;   // the position at elapsedStamp (CACurrentMediaTime), its rate, the length
@end
@implementation DMLAItem
@end
static NSMutableDictionary<NSString *, DMLAItem *> *gLAItems;   // uid -> item (live and ended)
static NSArray<DMLAItem *> *gLAShownCache = nil;                 // (the shown ones in order, until the next change)

static dispatch_queue_t DMLAQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.liveactivities", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0)); });
    return q;
}
// A method of exactly these types (a class method with meta); every private call of this file is made only with the types it was read with.
static BOOL DMLATypes(Class c, const char *sel, const char *types, BOOL meta) {
    Method m = !c ? NULL : meta ? class_getClassMethod(c, sel_registerName(sel)) : class_getInstanceMethod(c, sel_registerName(sel));
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    return t && !strcmp(t, types);
}
// own: the class must define the method itself -- an inherited one can have the same types (NSObject's -init is "@16@0:8" too, so a row for a
// class's own -init would pass with no -init of its own: review 1.8.4 M1).
typedef struct { const char *cls, *sel, *enc; BOOL meta, optional, own; } DMLANeedRow;
static BOOL DMLAOwnMethod(Class c, SEL s) {   // (in c's own method list, not a superclass's)
    unsigned n = 0;
    Method *ms = c ? class_copyMethodList(c, &n) : NULL;
    BOOL found = NO;
    for (unsigned i = 0; i < n && !found; i++) found = method_getName(ms[i]) == s;
    free(ms);
    return found;
}
// Every row of `rows` there with its types (an optional row may be missing); the missing ones named in *missing.
static BOOL DMLATypesOK(const DMLANeedRow *rows, size_t n, NSMutableArray<NSString *> *missing) {
    BOOL ok = YES;
    for (size_t i = 0; i < n; i++) {
        Class c = objc_getClass(rows[i].cls);
        BOOL there = DMLATypes(c, rows[i].sel, rows[i].enc, rows[i].meta);
        if (there && rows[i].own && !DMLAOwnMethod(rows[i].meta ? object_getClass((id)c) : c, sel_registerName(rows[i].sel))) there = NO;   // (inherited only)
        if (there) continue;
        if (!rows[i].optional) ok = NO;
        [missing addObject:[NSString stringWithFormat:@"%@%c[%s %s]", rows[i].optional ? @"(optional) " : @"", rows[i].meta ? '+' : '-', rows[i].cls, rows[i].sel]];
    }
    return ok;
}
// ---- what runs where it has been seen to work ----
// The parts of this feature that start something in SpringBoard no release of ours started before -- MobileTimer's timer manager of our own, and
// MediaRemote's seek -- run only on the exact iPadOS versions where the device pass has seen them work (plans/v184.md: a real Clock timer, a real
// seek): common/LiveActivities.h kMSBDLATimersChecked / kMSBDLASeekChecked, which Settings asks too (the Timers row). Empty lists: off everywhere,
// Live Activities on by default included (review 1.8.4 M1); the apps' path's lists are there too (kMSBDLAAppsListChecked, kMSBDLAAppsHostChecked).
// Now Playing's reads are the ones our Control Center has made since 1.8.0; the calls' are read only once TelephonyUtilities itself has posted a
// call notification (its call center there already), never made by us.
#if DEBUG
static BOOL gLATimersForced = NO, gLASeekForced = NO;   // (the device pass on a debug build: la_timers_try, la_seek_try)
#endif
static BOOL DMLATimersAllowed(void) {
#if DEBUG
    if (gLATimersForced) return YES;
#endif
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    return MSBDLATimersListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;
}
static BOOL DMLASeekAllowed(void) {
#if DEBUG
    if (gLASeekForced) return YES;
#endif
    NSOperatingSystemVersion v = [NSProcessInfo processInfo].operatingSystemVersion;
    return MSBDLASeekListed(v.majorVersion, v.minorVersion, v.patchVersion) != 0;
}
static NSString *DMLAShort(NSString *s) { return s.length ? [NSString stringWithFormat:@"%08x", (unsigned)(s.hash & 0xffffffff)] : @"-"; }   // (a short id in logs)
static NSString *DMLAAppName(NSString *bid) {
    if (!bid.length) return nil;
    id name = DMCall(DMProxyForBundle(bid), @"localizedName");
    return [name isKindOfClass:[NSString class]] && [name length] ? name : nil;
}

// ---- the shown items --------------------------------------------------------------------------------------------------------------------------
static int DMLAOrder(DMLAItem *a, DMLAItem *b) {
    MSBDLAOrderKey x = { a.kind, a.endedAt > 0, a.rank, a.uid.UTF8String }, y = { b.kind, b.endedAt > 0, b.rank, b.uid.UTF8String };
    return MSBDLACompare(&x, &y);
}
static NSArray<DMLAItem *> *DMLAShownItems(void) {
    if (gLAShownCache) return gLAShownCache;
    double now = CACurrentMediaTime();
    NSMutableArray<DMLAItem *> *out = [NSMutableArray array];
    if (gLAOn) for (DMLAItem *it in gLAItems.allValues)
        if (it.kind >= 0 && it.kind < kMSBDLAKinds && gLAKindOn[it.kind] && MSBDLAShown(it.endedAt, now, gLAKeep)) [out addObject:it];
    [out sortUsingComparator:^NSComparisonResult(DMLAItem *a, DMLAItem *b) { return (NSComparisonResult)DMLAOrder(a, b); }];
    gLAShownCache = [out copy];
    return gLAShownCache;
}
// Ended ones past their time go (each end schedules one look at its time; this also runs with every change).
static void DMLAPrune(void) {
    double now = CACurrentMediaTime();
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    for (DMLAItem *it in gLAItems.allValues) if (!MSBDLAShown(it.endedAt, now, gLAKeep)) [gone addObject:it.uid];
    if (!gone.count) return;
    [gLAItems removeObjectsForKeys:gone];
    DMLAChanged([NSString stringWithFormat:@"%lu ended past their time", (unsigned long)gone.count]);
}
static void DMLAEnd(DMLAItem *it, NSString *why) {
    if (!it || it.endedAt > 0) return;
    if ([gLAGoneAtOnce containsObject:it.uid]) {   // (ended from its own card: no greyed stay)
        [gLAGoneAtOnce removeObject:it.uid];
        [gLAItems removeObjectForKey:it.uid];
        DMLog([NSString stringWithFormat:@"[liveact] %@ %@ ended from its card: gone", it.kind == kMSBDLACall ? @"call" : @"timer", DMLAShort(it.uid)]);
        return;
    }
    it.endedAt = CACurrentMediaTime();
    if (it.kind == kMSBDLAApp) DMLAAppsHostTearDown(it.uid);   // (its live view goes now, also while its card stays open, greyed: review 1.8.4 P2-L2)
    DMLog([NSString stringWithFormat:@"[liveact] kind %d %@ ended (%@): greyed for %.0f s", it.kind, DMLAShort(it.uid), why, gLAKeep]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((gLAKeep + 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMLAPrune(); });
}
static BOOL DMLANeedsClock(void) {
    double now = CACurrentMediaTime();   // (a timer past its end counts no more: 0:00 stays without the clock -- review 1.8.4 L5)
    for (DMLAItem *it in DMLAShownItems())
        if (it.endedAt <= 0 && ((it.kind == kMSBDLATimer && it.timerState == kMSBDLATimerRunning && it.fireAt > now) || (it.kind == kMSBDLACall && it.connected && !it.held))) return YES;
    return NO;
}
static void DMLAClockTick(void);
static void DMLAClockApply(void) {
    BOOL want = gLAOn && DMLANeedsClock();
    if (want == (gLAClock != nil)) return;
    if (!want) { [gLAClock invalidate]; gLAClock = nil; return; }
    gLAClock = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) { DMLAClockTick(); }];
    gLAClock.tolerance = 0.1;
    [[NSRunLoop mainRunLoop] addTimer:gLAClock forMode:NSRunLoopCommonModes];
    DMGateTimer(gLAClock);   // (with the screen off it waits)
}
static void DMLARebuildOpenCard(void);
// Something changed (an item came, went, ended or changed its state): the bars are laid out again, the clock and an open card follow.
static void DMLAChanged(NSString *why) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMLAChanged(why); }); return; }
    gLAShownCache = nil;
    for (UIView *fg in gCopies.allObjects) [fg setNeedsLayout];
    DMLAClockApply();
    DMLARebuildOpenCard();
    if (why && DMTestFlag("/tmp/macstatusbar-debug")) DMLog([NSString stringWithFormat:@"[liveact] %@: %lu shown", why, (unsigned long)DMLAShownItems().count]);
}
static void DMLAUpsert(DMLAItem *it, NSString *why) {
    if (!gLAItems) gLAItems = [NSMutableDictionary dictionary];
    BOOL fresh = gLAItems[it.uid] == nil;
    gLAItems[it.uid] = it;
    if (fresh) DMLog([NSString stringWithFormat:@"[liveact] kind %d %@ shown (%@)", it.kind, DMLAShort(it.uid), why]);
    DMLAChanged(nil);
}
static void DMLADropKind(int kind) {
    NSMutableArray *gone = [NSMutableArray array];
    for (DMLAItem *it in gLAItems.allValues) if (it.kind == kind) [gone addObject:it.uid];
    [gLAItems removeObjectsForKeys:gone];
}

// ---- Now Playing (MediaRemote) ----------------------------------------------------------------------------------------------------------------
typedef void (*DMLAMRInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*DMLAMRPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*DMLAMRRegisterFn)(dispatch_queue_t);
typedef Boolean (*DMLAMRSendFn)(uint32_t, CFDictionaryRef);
typedef void (*DMLAMRDisplayIDFn)(dispatch_queue_t, void (^)(CFStringRef));
typedef void (*DMLAMRSeekFn)(double);
static struct { DMLAMRInfoFn info; DMLAMRPlayingFn playing; DMLAMRRegisterFn reg; DMLAMRSendFn send; DMLAMRDisplayIDFn app; DMLAMRSeekFn seek; BOOL ok, started; } gLAMR;
enum { kDMLAMRPlay = 0, kDMLAMRPause = 1, kDMLAMRToggle = 2, kDMLAMRNext = 4, kDMLAMRPrevious = 5 };   // (MRMediaRemoteSendCommand's commands)
static unsigned gLANPGen = 0;
#if DEBUG
static int gLAFakeNP = 0;   // (tests: la_fake_np_<1|2> -- a made-up track playing / paused; 0 the real one)
#endif
static void DMLANowPlayingApply(NSString *bid, NSString *title, NSString *line, BOOL playing, UIImage *art, NSString *artKey, double elapsed, double age, double rate, double duration) {
    if (!gLAOn || !gLAKindOn[kMSBDLANowPlaying]) return;
    DMLAItem *it = gLAItems[@"np"];
    double now = CACurrentMediaTime();
    BOOL hasApp = bid.length > 0 || title.length > 0;
    double ended = MSBDLANowPlayingEnded(hasApp, title.length > 0 || bid.length > 0, playing, (it && it.endedAt <= 0) ? 0.0 : it.pausedAt, now);
    if (ended < 0) {   // (no app now: a pill that was there ends)
        if (it && it.endedAt <= 0) { it.playing = NO; DMLAEnd(it, @"no app plays"); DMLAChanged(nil); }
        return;
    }
    BOOL fresh = !it;
    if (fresh && !playing) return;   // (a player first seen paused -- left paused before a respring -- gets no pill until it plays)
    if (fresh) { it = [DMLAItem new]; it.kind = kMSBDLANowPlaying; it.uid = @"np"; }
    BOOL wasEnded = it.endedAt > 0, wasPlaying = it.playing;
    it.bundleID = bid; it.title = title.length ? title : DMLAAppName(bid); it.subtitle = line;
    it.playing = playing;
    if (artKey) { if (art) it.art = art; else if (![artKey isEqual:it.artKey]) it.art = nil; it.artKey = artKey; } else { it.art = nil; it.artKey = nil; }   // (a new picture that could not be read: none)
    it.elapsed = elapsed; it.elapsedStamp = now - (age > 0 ? age : 0); it.rate = playing ? rate : 0.0; it.duration = duration;
    if (ended > 0) {   // (paused: ended from the pause on, unless it plays again)
        if (!wasEnded) {
            it.pausedAt = ended; it.endedAt = ended;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((gLAKeep + 0.2) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMLAPrune(); });
            DMLog(@"[liveact] Now Playing paused: greyed until it plays again or its time is up");
        }
    } else { it.pausedAt = 0; it.endedAt = 0; }
    if (fresh) { if (!MSBDLAShown(it.endedAt, now, gLAKeep)) return; DMLAUpsert(it, playing ? @"playing" : @"paused"); return; }
    if (wasEnded != (it.endedAt > 0) || wasPlaying != playing) DMLAChanged(nil);
    else {   // (the same state: its pills redrawn in place, a copy laid out only when one now needs another width; an open card -- review 1.8.4 L9)
        DMLARefreshPillsOf(@"np");
        DMLARebuildOpenCard();
    }
}
static void DMLANowPlayingRead(void) {
#if DEBUG
    if (gLAFakeNP) {
        static UIImage *fake;
        if (!fake) fake = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(96, 96)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [[UIColor systemIndigoColor] setFill]; UIRectFill(CGRectMake(0, 0, 96, 96)); [[UIColor systemPinkColor] setFill]; UIRectFill(CGRectMake(0, 48, 96, 48));
        }];
        DMLANowPlayingApply(@"com.apple.Music", @"Test Track With A Long Title", @"Test Artist", gLAFakeNP == 1, fake, @"fake", 42.0, 0, 1.0, 215.0);
        return;
    }
#endif
    if (!gLAMR.ok) return;
    unsigned gen = ++gLANPGen;
    NSString *haveKey = gLAItems[@"np"].artKey;
    dispatch_async(DMLAQueue(), ^{ gLAMR.playing(DMLAQueue(), ^(Boolean playing) {
        gLAMR.info(DMLAQueue(), ^(CFDictionaryRef infoRef) {
            NSDictionary *info = [(__bridge NSDictionary *)infoRef copy] ?: @{};
            NSString *(^str)(NSString *) = ^NSString *(NSString *k) { id v = info[k]; return [v isKindOfClass:[NSString class]] ? v : nil; };
            double (^num)(NSString *) = ^double(NSString *k) { id v = info[k]; return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0.0; };
            NSString *title = str(@"kMRMediaRemoteNowPlayingInfoTitle"), *artist = str(@"kMRMediaRemoteNowPlayingInfoArtist"), *album = str(@"kMRMediaRemoteNowPlayingInfoAlbum");
            double duration = num(@"kMRMediaRemoteNowPlayingInfoDuration"), elapsed = num(@"kMRMediaRemoteNowPlayingInfoElapsedTime");
            double rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] ? num(@"kMRMediaRemoteNowPlayingInfoPlaybackRate") : 1.0;
            id stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
            double age = [stamp isKindOfClass:[NSDate class]] ? -[(NSDate *)stamp timeIntervalSinceNow] : 0.0;
            NSData *data = [info[@"kMRMediaRemoteNowPlayingInfoArtworkData"] isKindOfClass:[NSData class]] ? info[@"kMRMediaRemoteNowPlayingInfoArtworkData"] : nil;
            id ident = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
            NSString *key = data ? ([ident isKindOfClass:[NSString class]] ? ident : [NSString stringWithFormat:@"%lu.%lu", (unsigned long)data.length, (unsigned long)data.hash]) : nil;
            UIImage *art = nil;
            if (data && ![key isEqual:haveKey]) { UIImage *full = [UIImage imageWithData:data]; art = [full imageByPreparingThumbnailOfSize:CGSizeMake(128, 128)] ?: full; }   // (another picture: decoded here)
            NSString *line = artist.length ? artist : album;
            void (^show)(NSString *) = ^(NSString *bid) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (gen != gLANPGen) return;
                    DMLANowPlayingApply(bid, title, line, playing, art, key, elapsed, age, rate, duration);
                });
            };
            if (!gLAMR.app) { show(nil); return; }
            gLAMR.app(DMLAQueue(), ^(CFStringRef bid) { show(bid ? [(__bridge NSString *)bid copy] : nil); });
        });
    }); });   // (MediaRemote's first ask on our queue too: its connection is made on the calling thread)
}
static void DMLANowPlayingStart(void) {
    if (gLAMR.started) return;
    gLAMR.started = YES;
    const char *path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";
    void *mr = dlopen(path, RTLD_LAZY);
    gLAMR.info = mr ? (DMLAMRInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    gLAMR.playing = mr ? (DMLAMRPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    gLAMR.reg = mr ? (DMLAMRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    gLAMR.send = mr ? (DMLAMRSendFn)dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
    gLAMR.app = mr ? (DMLAMRDisplayIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    gLAMR.seek = mr ? (DMLAMRSeekFn)dlsym(mr, "MRMediaRemoteSetElapsedTime") : NULL;
    NSString *infoNote = DMCCTFrameworkString(path, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    NSString *playingNote = DMCCTFrameworkString(path, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    NSString *appNote = DMCCTFrameworkString(path, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
    gLAMR.ok = gLAMR.info && gLAMR.playing && gLAMR.reg && gLAMR.send && infoNote && playingNote;
    DMLog([NSString stringWithFormat:@"[liveact] Now Playing: MediaRemote %@ (seek %d, app %d)", gLAMR.ok ? @"ready" : @"not all there: off", gLAMR.seek != NULL, gLAMR.app != NULL]);
    if (!gLAMR.ok) return;
    gLAMR.reg(dispatch_get_main_queue());   // (the same queue as our Control Center's tile asks for: CCTiles.h DMCCTObserve)
    // (the player starting or stopping is read at once; its info -- a player that updates it every second -- at most once a second)
    [[NSNotificationCenter defaultCenter] addObserverForName:playingNote object:nil queue:nil usingBlock:^(NSNotification *note) { DMLASrcChanged(kDMLASrcNowPlaying, 0.15, 0.0); }];
    for (NSString *n in @[infoNote, appNote ?: infoNote])
        [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) { DMLASrcChanged(kDMLASrcNowPlaying, 0.15, 1.0); }];
    DMLANowPlayingRead();
}
static void DMLANowPlayingSend(DMLAItem *it, uint32_t cmd) {
    DMLog([NSString stringWithFormat:@"[liveact] Now Playing: command %u", cmd]);
#if DEBUG
    if (it.fake) { if (cmd == kDMLAMRToggle) gLAFakeNP = gLAFakeNP == 1 ? 2 : 1; DMLANowPlayingRead(); return; }
#endif
    if (gLAMR.ok) gLAMR.send(cmd, NULL);
}
static void DMLANowPlayingSeek(DMLAItem *it, double to) {
    if (!DMLASeekAllowed()) return;   // (not seen to work on this iPadOS yet: the scrubber only shows, review 1.8.4 M1)
    DMLog([NSString stringWithFormat:@"[liveact] Now Playing: seek to %.0f s", to]);
    if (it.fake || !gLAMR.seek) return;
    gLAMR.seek(to);
    it.elapsed = to; it.elapsedStamp = CACurrentMediaTime();   // (shown at once; MediaRemote's own answer follows)
}

// ---- timers (MobileTimer) ---------------------------------------------------------------------------------------------------------------------
// The types read in the iOS 17 runtime headers (MTTimerManager, MTTimer, NetAppsUtilities' NAFuture) -- to be confirmed on each iPad by la_probe
// (plans/v184.md): a timer is read only where every required row is there with these types.
static const DMLANeedRow kDMLATimerNeeds[] = {
    { "MTTimerManager", "init", "@16@0:8", NO, NO, YES },   // (its own -init: NSObject's has the same types)
    { "MTTimerManager", "timers", "@16@0:8", NO, YES },          // (all timers: 17+ runs several; else the current one)
    { "MTTimerManager", "currentTimer", "@16@0:8", NO, NO },
    { "MTTimerManager", "pauseCurrentTimer", "@16@0:8", NO, YES },
    { "MTTimerManager", "resumeCurrentTimer", "@16@0:8", NO, YES },
    { "MTTimerManager", "stopCurrentTimer", "@16@0:8", NO, YES },
    { "MTTimer", "isActiveTimer:", "B24@0:8@16", YES, NO },
    { "MTTimer", "remainingTime", "d16@0:8", NO, NO },
    { "MTTimer", "fireDate", "@16@0:8", NO, NO },
    { "MTTimer", "timerID", "@16@0:8", NO, NO },
    { "MTTimer", "isFiring", "B16@0:8", NO, YES },
    { "MTTimer", "isCurrentTimer", "B16@0:8", NO, YES },
    { "MTTimer", "displayTitle", "@16@0:8", NO, YES },
    // (17 and later: a timer acted on by itself -- the Clock's timers are not MobileTimer's "current timer" there, 17.5.1 device pass: its card
    //  had no buttons; the states by their names, +descriptionForState:, read on 17.5.1 as 1 Stopped, 2 Paused, 3 Running)
    { "MTTimer", "timerByUpdatingWithState:", "@24@0:8Q16", NO, YES },
    { "MTTimer", "descriptionForState:", "@24@0:8Q16", YES, YES },
    { "MTTimerManager", "updateTimer:", "@24@0:8@16", NO, YES },
};
static id gLATimerMgr = nil;   // (ours, kept for SpringBoard's life)
// MobileTimer's state numbers by their names (+[MTTimer descriptionForState:]; -1: not found): a timer acted on by itself needs all three.
static long long gLATimerStopped = -1, gLATimerPaused = -1, gLATimerRunning = -1;
static void DMLATimerStatesRead(void) {
    if (!DMLATypes(objc_getClass("MTTimer"), "descriptionForState:", "@24@0:8Q16", YES)) return;
    for (unsigned long long st = 0; st < 8; st++) {
        id d = ((id (*)(id, SEL, unsigned long long))objc_msgSend)((id)objc_getClass("MTTimer"), sel_registerName("descriptionForState:"), st);
        if (![d isKindOfClass:[NSString class]]) continue;
        if ([d isEqualToString:@"Stopped"] && gLATimerStopped < 0) gLATimerStopped = (long long)st;
        else if ([d isEqualToString:@"Paused"] && gLATimerPaused < 0) gLATimerPaused = (long long)st;
        else if ([d isEqualToString:@"Running"] && gLATimerRunning < 0) gLATimerRunning = (long long)st;
    }
}
// A timer of the card acted on by itself (MTTimer -timerByUpdatingWithState:, then MTTimerManager -updateTimer:): 17 and later, every row as read.
static BOOL DMLATimerActsOn(DMLAItem *it) {
    return it.timerObj && gLATimerStopped >= 0 && gLATimerPaused >= 0 && gLATimerRunning >= 0
        && DMLATypes(objc_getClass("MTTimer"), "timerByUpdatingWithState:", "@24@0:8Q16", NO) && DMLATypes(objc_getClass("MTTimerManager"), "updateTimer:", "@24@0:8@16", NO);
}
// The card's buttons: a fake, a timer acted on by itself, else only MobileTimer's current timer.
static BOOL DMLATimerHasButtons(DMLAItem *it) { return it.fake || DMLATimerActsOn(it) || it.current; }
static BOOL gLATimersStarted = NO, gLATimersOK = NO;
static unsigned gLATimerGen = 0;
static BOOL DMLATimerHas(const char *cls, const char *sel, const char *types, BOOL meta) { return DMLATypes(objc_getClass(cls), sel, types, meta); }
// The soonest running timer's end is looked at once, a second after it is due -- read again, and the clock let go -- also when MobileTimer's
// notification of it does not come (review 1.8.4 L5). A later read schedules it again; an older look that is not the last does nothing.
static unsigned gLATimerEndGen = 0;
static void DMLATimerEndLook(void) {
    double now = CACurrentMediaTime(), soonest = 0;
    for (DMLAItem *it in gLAItems.allValues)
        if (it.kind == kMSBDLATimer && it.endedAt <= 0 && it.timerState == kMSBDLATimerRunning && it.fireAt > now && (!soonest || it.fireAt < soonest)) soonest = it.fireAt;
    unsigned gen = ++gLATimerEndGen;
    if (!soonest) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((soonest - now + 1.0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != gLATimerEndGen) return;
        DMLASrcChanged(kDMLASrcTimers, 0.0, 0.0);
        DMLAClockApply();
    });
}
static void DMLATimersApply(NSArray *timers) {
    if (!gLAOn || !gLAKindOn[kMSBDLATimer]) return;
    double now = CACurrentMediaTime();
    Class tc = objc_getClass("MTTimer");
    BOOL hasFiring = DMLATimerHas("MTTimer", "isFiring", "B16@0:8", NO), hasCurrent = DMLATimerHas("MTTimer", "isCurrentTimer", "B16@0:8", NO);
    BOOL hasTitle = DMLATimerHas("MTTimer", "displayTitle", "@16@0:8", NO);
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    BOOL changed = NO;
    for (id t in timers) {
        if (![t isKindOfClass:tc]) continue;
        BOOL active = ((BOOL (*)(id, SEL, id))objc_msgSend)((id)tc, sel_registerName("isActiveTimer:"), t);
        BOOL firing = hasFiring && ((BOOL (*)(id, SEL))objc_msgSend)(t, sel_registerName("isFiring"));
        id fire = ((id (*)(id, SEL))objc_msgSend)(t, sel_registerName("fireDate"));
        double fireIn = [fire isKindOfClass:[NSDate class]] ? [(NSDate *)fire timeIntervalSinceNow] : -1.0;
        if ([fire isKindOfClass:[NSDate class]] && fireIn < 0) { firing = active; fireIn = -1.0; }   // (its time has come: it rings)
        double remaining = ((double (*)(id, SEL))objc_msgSend)(t, sel_registerName("remainingTime"));
        double left = 0;
        int state = MSBDLATimerState(active, firing, fireIn, remaining, &left);
        id tid = ((id (*)(id, SEL))objc_msgSend)(t, sel_registerName("timerID"));
        NSString *uid = [@"timer:" stringByAppendingString:[tid isKindOfClass:[NSUUID class]] ? [(NSUUID *)tid UUIDString] : [tid description] ?: @"?"];
        if (state == kMSBDLATimerNone || (state == kMSBDLATimerRinging && !gLAItems[uid])) continue;   // (one first seen ringing gets no pill)
        [seen addObject:uid];
        DMLAItem *it = gLAItems[uid];
        BOOL fresh = !it;
        if (fresh) { it = [DMLAItem new]; it.kind = kMSBDLATimer; it.uid = uid; it.bundleID = @"com.apple.mobiletimer"; }
        int was = it.timerState;
        it.timerState = state;
        it.fireAt = state == kMSBDLATimerRunning ? now + left : 0;
        it.left = state == kMSBDLATimerPaused ? left : 0;
        it.rank = state == kMSBDLATimerRunning ? left : state == kMSBDLATimerPaused ? 1e6 + left : 0;   // (the next to ring first; paused ones after)
        it.current = hasCurrent ? ((BOOL (*)(id, SEL))objc_msgSend)(t, sel_registerName("isCurrentTimer")) : timers.count == 1;
        it.timerObj = t;
        id title = hasTitle ? ((id (*)(id, SEL))objc_msgSend)(t, sel_registerName("displayTitle")) : nil;
        it.title = [title isKindOfClass:[NSString class]] && [title length] ? title : @"Timer";
        if (state == kMSBDLATimerRinging) { if (it.endedAt <= 0) DMLAEnd(it, @"it rang"); }
        else if (it.endedAt > 0) it.endedAt = 0;   // (restarted: live again)
        if (fresh) { DMLAUpsert(it, state == kMSBDLATimerRunning ? @"running" : @"paused"); continue; }
        if (was != state) changed = YES;
    }
    for (DMLAItem *it in [gLAItems.allValues copy]) {   // (a timer no longer running or paused: ended -- stopped, or dismissed after it rang)
        if (it.kind != kMSBDLATimer || it.fake || [seen containsObject:it.uid]) continue;
        if (it.endedAt <= 0) { DMLAEnd(it, @"stopped"); changed = YES; }
        else if ([gLAGoneAtOnce containsObject:it.uid]) { [gLAGoneAtOnce removeObject:it.uid]; [gLAItems removeObjectForKey:it.uid]; changed = YES; }
    }
    if (changed) DMLAChanged(nil);
    else {   // (no timer changed its state: their pills redrawn in place -- review 1.8.4 L9)
        for (DMLAItem *x in gLAItems.allValues) if (x.kind == kMSBDLATimer) DMLARefreshPillsOf(x.uid);
        DMLARebuildOpenCard();
    }
    DMLATimerEndLook();
}
static void DMLATimersRead(void) {
    if (!gLATimersOK || !gLAOn || !gLAKindOn[kMSBDLATimer]) return;
    BOOL all = DMLATimerHas("MTTimerManager", "timers", "@16@0:8", NO);
    id future = ((id (*)(id, SEL))objc_msgSend)(gLATimerMgr, sel_registerName(all ? "timers" : "currentTimer"));
    if (!future || !DMLATypes(object_getClass(future), "addCompletionBlock:", "@24@0:8@?16", NO)) {
        static BOOL told = NO; if (!told) { told = YES; DMLog(@"[liveact] timers: the answer is not a future we know: timers stay off"); }
        return;
    }
    unsigned gen = ++gLATimerGen;
    void (^done)(id, NSError *) = ^(id result, NSError *error) {
        NSArray *list = [result isKindOfClass:[NSArray class]] ? [result copy] : result ? @[result] : @[];
        dispatch_async(dispatch_get_main_queue(), ^{ if (gen == gLATimerGen) DMLATimersApply(list); });
    };
    ((id (*)(id, SEL, id))objc_msgSend)(future, sel_registerName("addCompletionBlock:"), done);
}
static void DMLATimersStart(void) {
    if (gLATimersStarted) return;
    if (!DMLATimersAllowed()) {   // (nothing of MobileTimer is asked, made or loaded where a real timer has not been seen to work: review 1.8.4 M1)
        static BOOL told = NO;
        if (!told) { told = YES; DMLog(@"[liveact] timers: this iPadOS version is not one the device pass has confirmed: timers stay off"); }
        return;
    }
    gLATimersStarted = YES;
    if (!objc_getClass("MTTimerManager")) dlopen("/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer", RTLD_LAZY);
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    gLATimersOK = DMLATypesOK(kDMLATimerNeeds, sizeof kDMLATimerNeeds / sizeof kDMLATimerNeeds[0], missing);
    DMLog([NSString stringWithFormat:@"[liveact] timers: MobileTimer %@%@", gLATimersOK ? @"ready" : @"not all there: off",
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
    if (!gLATimersOK) return;
    Class mc = objc_getClass("MTTimerManager");
    gLATimerMgr = [[mc alloc] init];   // (-init with the types above: its connection to the timer server, as every client of MobileTimer makes it)
    if (!gLATimerMgr) { gLATimersOK = NO; DMLog(@"[liveact] timers: no timer manager made: off"); return; }
    DMLATimerStatesRead();
    DMLog([NSString stringWithFormat:@"[liveact] timers: states by name: stopped %lld, paused %lld, running %lld (a card's timer acted on by itself: %@)", gLATimerStopped, gLATimerPaused, gLATimerRunning,
        gLATimerStopped >= 0 && gLATimerPaused >= 0 && gLATimerRunning >= 0 && DMLATypes(objc_getClass("MTTimer"), "timerByUpdatingWithState:", "@24@0:8Q16", NO) && DMLATypes(objc_getClass("MTTimerManager"), "updateTimer:", "@24@0:8@16", NO) ? @"yes" : @"no, the current timer only"]);
    const char *path = "/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer";
    for (NSString *sym in @[@"MTTimerManagerTimersChanged", @"MTTimerManagerNextTimerChanged", @"MTTimerManagerStateReset", @"MTTimerManagerTimerFired",
                            @"MTTimerManagerFiringTimerChanged", @"MTTimerManagerFiringTimerDismissed"]) {
        NSString *name = DMCCTFrameworkString(path, sym.UTF8String);
        if (!name) continue;
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { DMLASrcChanged(kDMLASrcTimers, 0.2, 0.0); }];
    }
    DMLATimersRead();
}
// The card's buttons: on that very timer where it can be acted on by itself (17 and later), else on the current timer (MobileTimer's own calls;
// the answer is a future we do not wait for -- the change notification comes).
static void DMLATimerAct(DMLAItem *it, NSString *what) {
    DMLog([NSString stringWithFormat:@"[liveact] timer %@: %@", DMLAShort(it.uid), what]);
    if (it.fake) {
        if ([what isEqualToString:@"stopCurrentTimer"]) { [gLAItems removeObjectForKey:it.uid]; DMLAChanged(@"fake timer cancelled"); return; }
        BOOL pause = [what isEqualToString:@"pauseCurrentTimer"];
        double left = pause ? MAX(0, it.fireAt - CACurrentMediaTime()) : it.left;
        it.timerState = pause ? kMSBDLATimerPaused : kMSBDLATimerRunning; it.left = pause ? left : 0; it.fireAt = pause ? 0 : CACurrentMediaTime() + left;
        DMLAChanged(nil);
        return;
    }
    if (!gLATimersOK) return;
    if (DMLATimerActsOn(it)) {
        long long st = [what isEqualToString:@"pauseCurrentTimer"] ? gLATimerPaused : [what isEqualToString:@"resumeCurrentTimer"] ? gLATimerRunning : gLATimerStopped;
        id next = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(it.timerObj, sel_registerName("timerByUpdatingWithState:"), (unsigned long long)st);
        if (![next isKindOfClass:objc_getClass("MTTimer")]) { DMLog(@"[liveact] timer: MobileTimer gave no timer for the new state: nothing done"); return; }
        if (st == gLATimerStopped) { if (!gLAGoneAtOnce) gLAGoneAtOnce = [NSMutableSet set]; [gLAGoneAtOnce addObject:it.uid]; }
        ((id (*)(id, SEL, id))objc_msgSend)(gLATimerMgr, sel_registerName("updateTimer:"), next);
        return;
    }
    if (!it.current || !DMLATimerHas("MTTimerManager", what.UTF8String, "@16@0:8", NO)) return;
    if ([what isEqualToString:@"stopCurrentTimer"]) { if (!gLAGoneAtOnce) gLAGoneAtOnce = [NSMutableSet set]; [gLAGoneAtOnce addObject:it.uid]; }
    ((id (*)(id, SEL))objc_msgSend)(gLATimerMgr, sel_registerName(what.UTF8String));
}

// ---- calls (TelephonyUtilities) ---------------------------------------------------------------------------------------------------------------
static const DMLANeedRow kDMLACallNeeds[] = {
    { "TUCallCenter", "sharedInstance", "@16@0:8", YES, NO },
    { "TUCallCenter", "currentCalls", "@16@0:8", NO, NO },
    { "TUCallCenter", "disconnectCall:", "v24@0:8@16", NO, NO },
    { "TUCall", "uniqueProxyIdentifier", "@16@0:8", NO, NO },
    { "TUCall", "isConnected", "B16@0:8", NO, NO },
    { "TUCall", "isOnHold", "B16@0:8", NO, NO },
    { "TUCall", "isIncoming", "B16@0:8", NO, NO },
    { "TUCall", "callDuration", "d16@0:8", NO, NO },
    { "TUCall", "displayName", "@16@0:8", NO, NO },
    { "TUCall", "isUplinkMuted", "B16@0:8", NO, NO },
    { "TUCall", "setUplinkMuted:", "v20@0:8B16", NO, NO },
    { "TUCall", "isVideo", "B16@0:8", NO, YES },
    { "TUCall", "provider", "@16@0:8", NO, YES },
    { "TUCall", "isEndpointOnCurrentDevice", "B16@0:8", NO, YES },   // (a call on the iPhone this iPad only shows: not ours)
};
static BOOL gLACallsStarted = NO, gLACallsOK = NO;
static BOOL gLACallsHeard = NO;   // (TelephonyUtilities has posted a call notification: its call center is there -- never made by us, review 1.8.4 M1)
static BOOL DMLACallBool(id call, const char *sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(call, sel_registerName(sel)); }
static void DMLACallsRead(void) {
    if (!gLACallsOK || !gLAOn || !gLAKindOn[kMSBDLACall]) return;
    if (!gLACallsHeard) return;   // (until TelephonyUtilities posts, there is no call to show, and +sharedInstance could make its call center)
    Class cc = objc_getClass("TUCallCenter"), callClass = objc_getClass("TUCall");
    id center = ((id (*)(id, SEL))objc_msgSend)((id)cc, sel_registerName("sharedInstance"));
    id calls = center ? ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("currentCalls")) : nil;
    BOOL hasEnd = DMLATypes(callClass, "isEndpointOnCurrentDevice", "B16@0:8", NO), hasVideo = DMLATypes(callClass, "isVideo", "B16@0:8", NO);
    BOOL hasProvider = DMLATypes(callClass, "provider", "@16@0:8", NO);
    double now = CACurrentMediaTime();
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    BOOL changed = NO;
    if ([calls isKindOfClass:[NSArray class]]) for (id call in (NSArray *)calls) {
        if (![call isKindOfClass:callClass] || (hasEnd && !DMLACallBool(call, "isEndpointOnCurrentDevice"))) continue;
        id ident = ((id (*)(id, SEL))objc_msgSend)(call, sel_registerName("uniqueProxyIdentifier"));
        if (![ident isKindOfClass:[NSString class]] || ![ident length]) continue;
        NSString *uid = [@"call:" stringByAppendingString:ident];
        [seen addObject:uid];
        DMLAItem *it = gLAItems[uid];
        BOOL fresh = !it;
        if (fresh) { it = [DMLAItem new]; it.kind = kMSBDLACall; it.uid = uid; }
        BOOL wasConnected = it.connected, wasHeld = it.held, wasMuted = it.muted;
        it.call = call;
        it.connected = DMLACallBool(call, "isConnected"); it.held = DMLACallBool(call, "isOnHold"); it.incoming = DMLACallBool(call, "isIncoming");
        it.muted = DMLACallBool(call, "isUplinkMuted"); it.video = hasVideo && DMLACallBool(call, "isVideo");
        it.onThisDevice = hasEnd;   // (the calls not on this iPad were left out above; without that question none is known to be ours)
        double dur = ((double (*)(id, SEL))objc_msgSend)(call, sel_registerName("callDuration"));
        it.callStart = now - (isfinite(dur) && dur > 0 ? dur : 0);
        if (fresh) it.rank = now;   // (the older call first)
        id name = ((id (*)(id, SEL))objc_msgSend)(call, sel_registerName("displayName"));
        it.title = [name isKindOfClass:[NSString class]] && [name length] ? name : @"Call";
        id provider = hasProvider ? ((id (*)(id, SEL))objc_msgSend)(call, sel_registerName("provider")) : nil;
        id pb = DMCall(provider, @"bundleIdentifier");
        it.bundleID = [pb isKindOfClass:[NSString class]] && [pb length] && DMLAAppName(pb) ? pb : @"com.apple.facetime";
        it.subtitle = DMLAAppName(it.bundleID) ?: (it.video ? @"FaceTime" : @"Phone");
        if (it.endedAt > 0) { it.endedAt = 0; changed = YES; }
        if (fresh) { DMLAUpsert(it, it.connected ? @"connected" : it.incoming ? @"incoming" : @"calling"); continue; }
        if (wasConnected != it.connected || wasHeld != it.held || wasMuted != it.muted) changed = YES;
    }
    for (DMLAItem *it in [gLAItems.allValues copy]) {   // (a call no longer current: ended)
        if (it.kind != kMSBDLACall || it.fake || [seen containsObject:it.uid]) continue;
        if (it.endedAt <= 0) { it.call = nil; DMLAEnd(it, @"hung up"); changed = YES; }
    }
    if (changed) DMLAChanged(nil);
}
static void DMLACallsStart(void) {
    if (gLACallsStarted) return;
    gLACallsStarted = YES;
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    gLACallsOK = DMLATypesOK(kDMLACallNeeds, sizeof kDMLACallNeeds / sizeof kDMLACallNeeds[0], missing);
    DMLog([NSString stringWithFormat:@"[liveact] calls: TelephonyUtilities %@%@", gLACallsOK ? @"ready" : @"not all there: off",
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
    if (!gLACallsOK) return;
    const char *path = "/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities";
    for (NSString *sym in @[@"TUCallCenterCallStatusChangedNotification", @"TUCallCenterCallConnectedNotification", @"TUCallIsOnHoldChangedNotification",
                            @"TUCallIsUplinkMutedChangedNotification"]) {
        NSString *name = DMCCTFrameworkString(path, sym.UTF8String);
        if (!name) continue;
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { gLACallsHeard = YES; DMLASrcChanged(kDMLASrcCalls, 0.25, 0.0); }];
    }
    // (no read now: a call shows from its first notification on; one already going on at SpringBoard's start shows at its next change)
}
static void DMLACallAct(DMLAItem *it, NSString *what) {
    DMLog([NSString stringWithFormat:@"[liveact] call %@: %@", DMLAShort(it.uid), what]);
    if (it.fake) {
        if ([what isEqualToString:@"end"]) { [gLAItems removeObjectForKey:it.uid]; DMLAChanged(@"fake call ended"); }
        else { it.muted = !it.muted; DMLAChanged(nil); }
        return;
    }
    id call = it.call;
    if (!gLACallsOK || !call || it.endedAt > 0) return;
    // (only a call whose end is this iPad, asked again now: never one going on on the iPhone this iPad only shows -- review 1.8.4 L7)
    if (!DMLATypes(object_getClass(call), "isEndpointOnCurrentDevice", "B16@0:8", NO) || !DMLACallBool(call, "isEndpointOnCurrentDevice")) return;
    if ([what isEqualToString:@"end"]) {
        id center = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("TUCallCenter"), sel_registerName("sharedInstance"));
        if (!center) return;
        if (!gLAGoneAtOnce) gLAGoneAtOnce = [NSMutableSet set];
        [gLAGoneAtOnce addObject:it.uid];
        ((void (*)(id, SEL, id))objc_msgSend)(center, sel_registerName("disconnectCall:"), call);
        return;
    }
    BOOL mute = !it.muted;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(call, sel_registerName("setUplinkMuted:"), mute);
    it.muted = mute;   // (shown at once; the call's notification follows)
    DMLAChanged(nil);
}

// ---- the sources' notifications -------------------------------------------------------------------------------------------------------------------
// A source's change notification: a burst of them is read once, `delay` after the first, and never sooner than `minGap` after the last read; with the
// screen off nothing is read -- the source is marked and read when the screen comes on (DMLAScreenOn, StatusBar.x DMScreenPowerResume), so a
// player that updates its info every second costs nothing while the iPad sleeps.
static BOOL gLASrcPending[kDMLASrcs], gLASrcDirty[kDMLASrcs];
static CFTimeInterval gLASrcLast[kDMLASrcs];
static void DMLASrcRead(int src) {
    if (!gLAOn) return;
    if (src == kDMLASrcNowPlaying) { if (gLAKindOn[kMSBDLANowPlaying]) DMLANowPlayingRead(); }
    else if (src == kDMLASrcTimers) DMLATimersRead();
    else DMLACallsRead();
}
static void DMLASrcChanged(int src, double delay, double minGap) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMLASrcChanged(src, delay, minGap); }); return; }
    if (src < 0 || src >= kDMLASrcs || !gLAOn) return;
    if (gDMScreenOff) { gLASrcDirty[src] = YES; return; }
    if (gLASrcPending[src]) return;
    gLASrcPending[src] = YES;
    double wait = MAX(delay, gLASrcLast[src] + minGap - CACurrentMediaTime());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gLASrcPending[src] = NO; gLASrcLast[src] = CACurrentMediaTime();
        DMLASrcRead(src);
    });
}
static void DMLAScreenOn(void) {
    for (int src = 0; src < kDMLASrcs; src++) if (gLASrcDirty[src]) { gLASrcDirty[src] = NO; DMLASrcChanged(src, 0.3, 0.0); }
}

// ---- the switches (StatusBar.x DMLoadPrefs) -----------------------------------------------------------------------------------------------------
// Applied once SpringBoard has been up 8 s (the sources are asked only then); later changes at once. A kind switched off loses its pills at once.
static void DMLAApplyPrefs(BOOL on, BOOL np, BOOL timers, BOOL calls, BOOL apps) {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ DMLAApplyPrefs(on, np, timers, calls, apps); }); return; }
    double age = DMProcessAge();
    if (age < 8.0) {
        static BOOL queued = NO;
        static BOOL want[5];
        want[0] = on; want[1] = np; want[2] = timers; want[3] = calls; want[4] = apps;
        if (!queued) {
            queued = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((8.2 - age) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMLAApplyPrefs(want[0], want[1], want[2], want[3], want[4]); });
        }
        return;
    }
    BOOL kinds[kMSBDLAKinds] = { calls, timers, np, apps };
    BOOL changed = !gLAApplied || on != gLAOn;
    for (int k = 0; k < kMSBDLAKinds; k++) if (kinds[k] != gLAKindOn[k]) changed = YES;
    if (!changed) return;
    gLAApplied = YES;
    gLAOn = on;
    for (int k = 0; k < kMSBDLAKinds; k++) { gLAKindOn[k] = kinds[k]; if (!on || !kinds[k]) DMLADropKind(k); }
    DMLog([NSString stringWithFormat:@"[liveact] Live Activities in Menu Bar %@ (Now Playing %d, Timers %d, Calls %d, Apps %d)", on ? @"on" : @"off", np, timers, calls, apps]);
    if (on) DMLAStartSources();
    DMLAAppsApply(on && apps);
    if (!on && gLACard) DMCloseOverlay();
    DMLAChanged(nil);
}
static void DMLAStartSources(void) {
    if (!gLAOn) return;
    DM_FEATURE_MARK("live-activities");
    // (debug builds: /tmp/msb-ctorskip words la-nowplaying, la-timers, la-calls leave a source out, for a device run that bisects)
    if (gLAKindOn[kMSBDLANowPlaying] && !DMCtorSkip("la-nowplaying")) { if (!gLAMR.started) DMLANowPlayingStart(); else DMLANowPlayingRead(); }
    if (gLAKindOn[kMSBDLATimer] && !DMCtorSkip("la-timers")) { if (!gLATimersStarted) DMLATimersStart(); else DMLATimersRead(); }
    if (gLAKindOn[kMSBDLACall] && !DMCtorSkip("la-calls")) { if (!gLACallsStarted) DMLACallsStart(); else DMLACallsRead(); }
}

// ---- the pills ----------------------------------------------------------------------------------------------------------------------------------
// Now Playing's moving bars: four thin bars, each going up and down at its own pace while it plays (Core Animation, at most 20 frames a second;
// still with Reduce Motion, and while paused).
@interface DMLABars : UIView
@property (nonatomic) BOOL moving;
- (void)dm_layoutWithScale:(CGFloat)k;
@end
@implementation DMLABars
- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.userInteractionEnabled = NO;
    for (int i = 0; i < 4; i++) { CALayer *b = [CALayer layer]; b.backgroundColor = [UIColor whiteColor].CGColor; [self.layer addSublayer:b]; }
    return self;
}
- (void)dm_layoutWithScale:(CGFloat)k {
    CGFloat w = MAX(1.5, round(2.0 * k * 2.0) / 2.0), gap = MAX(1.0, round(1.5 * k * 2.0) / 2.0), H = self.bounds.size.height;
    static const CGFloat rest[4] = { 0.35, 0.6, 0.45, 0.3 };
    NSArray<CALayer *> *bars = self.layer.sublayers;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];   // (the bars' own layers: placed, never animated into place)
    for (NSUInteger i = 0; i < bars.count && i < 4; i++) {
        CALayer *b = bars[i];
        b.anchorPoint = CGPointMake(0.5, 1.0);   // (grows from the bottom)
        b.bounds = CGRectMake(0, 0, w, H);
        b.position = CGPointMake(i * (w + gap) + w / 2.0, H);
        b.cornerRadius = w / 2.0;
        BOOL anim = self.moving && !MSBReduceMotion();
        if (!anim) { [b removeAnimationForKey:@"dm"]; b.transform = CATransform3DMakeScale(1, rest[i], 1); continue; }
        if ([b animationForKey:@"dm"]) continue;
        b.transform = CATransform3DMakeScale(1, rest[i], 1);
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
        a.fromValue = @(0.25 + 0.1 * (i % 2)); a.toValue = @(1.0 - 0.12 * (i % 3));
        a.duration = 0.32 + 0.09 * i; a.autoreverses = YES; a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        a.timeOffset = 0.13 * i;
        if (@available(iOS 15.0, *)) a.preferredFrameRateRange = CAFrameRateRangeMake(10, 20, 20);
        [b addAnimation:a forKey:@"dm"];
    }
    [CATransaction commit];
}
+ (CGFloat)widthForScale:(CGFloat)k { CGFloat w = MAX(1.5, round(2.0 * k * 2.0) / 2.0), gap = MAX(1.0, round(1.5 * k * 2.0) / 2.0); return 4 * w + 3 * gap; }
@end

@interface DMLAPill : DMAXButton
@property (nonatomic, copy) NSString *uid;           // the item's, or "+" for the "+N" pill
@property (nonatomic, copy) NSArray<NSString *> *uids;   // the "+N" pill: the items it holds
@property (nonatomic, strong) UIView *capsule;
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) DMLABars *bars;
@property (nonatomic, copy) NSString *shape;         // (the text's shape when laid out: MSBDLATextShape)
@property (nonatomic) BOOL lit;
@property (nonatomic) CGFloat layoutH, layoutK;   // (the height and the bar's scale it was laid out at: DMLARefreshPillsOf draws it again at them)
@end
@implementation DMLAPill
- (void)setLit:(BOOL)lit { _lit = lit; self.capsule.backgroundColor = lit ? [UIColor colorWithWhite:0.26 alpha:1.0] : [UIColor blackColor]; }
@end
static UIColor *DMLAKindColor(int kind) {
    return kind == kMSBDLACall ? [UIColor systemGreenColor] : kind == kMSBDLATimer ? [UIColor systemOrangeColor] : [UIColor whiteColor];
}
static UIFont *DMLAPillFont(CGFloat k) { return [UIFont monospacedDigitSystemFontOfSize:round(11.5 * k * 2.0) / 2.0 weight:UIFontWeightSemibold]; }
static CGFloat DMLATextWidth(NSString *s, UIFont *f) {
    static NSMutableDictionary<NSString *, NSNumber *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%.1f", s ?: @"", f.pointSize];
    NSNumber *n = cache[key];
    if (n) return n.doubleValue;
    CGFloat w = ceil([s ?: @"" sizeWithAttributes:@{NSFontAttributeName: f}].width);
    if (cache.count > 200) [cache removeAllObjects];
    cache[key] = @(w);
    return w;
}
// The pill's words now (a clock, or a word); shape: what its width is made for.
static NSString *DMLAPillText(DMLAItem *it) {
    char buf[32];
    double now = CACurrentMediaTime();
    if (it.kind == kMSBDLATimer) {
        double left = it.endedAt > 0 ? 0 : it.timerState == kMSBDLATimerRunning ? it.fireAt - now : it.left;
        MSBDLAClockText(left, 1, buf, sizeof buf);
        return @(buf);
    }
    if (it.kind == kMSBDLACall) {
        if (it.endedAt > 0) return @"Ended";
        const char *word = "";
        if (MSBDLACallText(it.connected, it.held, it.incoming, &word)) { MSBDLAClockText(now - it.callStart, 0, buf, sizeof buf); return @(buf); }
        return @(word);
    }
    if (it.kind == kMSBDLAApp) return it.title ?: @"";
    return @"";
}
static NSString *DMLAShapeOf(NSString *text) { char buf[64]; MSBDLATextShape(text.UTF8String, buf, sizeof buf); return @(buf); }
static UIImage *DMLAGlyph(NSString *name, CGFloat pt) {
    return [DMCCTSymbol(name, pt, UIImageSymbolWeightSemibold) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
static UIImage *DMLAAppIconSmall(NSString *bid) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (!bid.length) return nil;
    UIImage *img = cache[bid];
    if (!img) { img = DMAppIcon(bid); if (img) { if (cache.count > 32) [cache removeAllObjects]; cache[bid] = img; } }
    return img;
}
// One pill's look and width for its item (or the "+N" pill for `plus` > 0), at height H and the bar's scale k.
static CGFloat DMLAConfigurePill(DMLAPill *p, DMLAItem *it, int plus, CGFloat H, CGFloat k) {
    CGFloat pad = round(7.0 * k), gap = round(4.0 * k);
    UIFont *font = DMLAPillFont(k);
    p.label.font = font;
    BOOL ended = it && it.endedAt > 0;
    CGFloat contentAlpha = ended ? 0.42 : 1.0;
    p.glyph.alpha = p.label.alpha = p.bars.alpha = contentAlpha;
    p.glyph.layer.cornerRadius = 0; p.glyph.clipsToBounds = NO;
    if (plus > 0) {
        char buf[16]; MSBDLAPlusText(plus, buf, sizeof buf);
        p.label.text = @(buf); p.label.textColor = [UIColor whiteColor];
        p.glyph.hidden = YES; p.bars.hidden = YES; p.label.hidden = NO;
        p.shape = DMLAShapeOf(p.label.text);
        CGFloat tw = DMLATextWidth(p.shape, font);
        p.label.frame = CGRectMake(pad, 0, tw, H);
        return pad * 2 + tw;
    }
    UIColor *color = DMLAKindColor(it.kind);
    p.glyph.tintColor = color; p.label.textColor = it.kind == kMSBDLAApp ? [UIColor whiteColor] : color;
    if (it.kind == kMSBDLANowPlaying) {
        CGFloat art = H - round(6.0 * k), bw = [DMLABars widthForScale:k], bh = round(9.0 * k);
        p.glyph.hidden = NO; p.label.hidden = YES; p.bars.hidden = NO;
        p.glyph.image = it.art ?: DMLAGlyph(@"music.note", round(9.0 * k));
        p.glyph.contentMode = it.art ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        p.glyph.clipsToBounds = YES; p.glyph.layer.cornerRadius = round(3.0 * k);
        p.glyph.backgroundColor = it.art ? nil : [UIColor colorWithWhite:0.25 alpha:1.0];
        p.glyph.frame = CGRectMake(pad - round(3.0 * k), (H - art) / 2.0, art, art);
        p.bars.frame = CGRectMake(CGRectGetMaxX(p.glyph.frame) + round(6.0 * k), (H - bh) / 2.0, bw, bh);
        p.bars.moving = it.playing && !ended;
        [p.bars dm_layoutWithScale:k];
        p.shape = @"np";
        return CGRectGetMaxX(p.bars.frame) + pad;
    }
    p.bars.hidden = YES; p.bars.moving = NO; [p.bars dm_layoutWithScale:k];
    p.glyph.backgroundColor = nil;
    NSString *text = DMLAPillText(it);
    p.label.text = text; p.label.hidden = NO;
    CGFloat iconW;
    if (it.kind == kMSBDLAApp) {
        iconW = H - round(5.0 * k);
        p.glyph.image = DMLAAppIconSmall(it.bundleID); p.glyph.contentMode = UIViewContentModeScaleAspectFit;
        p.glyph.clipsToBounds = YES; p.glyph.layer.cornerRadius = round(iconW * 0.225);
    } else {
        p.glyph.image = DMLAGlyph(it.kind == kMSBDLACall ? (it.video ? @"video.fill" : @"phone.fill") : @"timer", round(10.0 * k));
        p.glyph.contentMode = UIViewContentModeCenter;
        iconW = round(12.0 * k);
    }
    p.glyph.hidden = p.glyph.image == nil;
    CGFloat x = pad;
    if (!p.glyph.hidden) { p.glyph.frame = CGRectMake(x, (H - iconW) / 2.0, iconW, iconW); x += iconW + gap; }
    p.shape = it.kind == kMSBDLAApp ? text : DMLAShapeOf(text);
    CGFloat tw = MIN(DMLATextWidth(p.shape, font), it.kind == kMSBDLAApp ? round(68.0 * k) : CGFLOAT_MAX);
    p.label.frame = CGRectMake(x, 0, tw, H);
    p.label.lineBreakMode = NSLineBreakByTruncatingTail;
    return x + tw + pad;
}
static NSString *DMLAAXLabel(DMLAItem *it) {
    switch (it.kind) {
        case kMSBDLACall: return @"Call";
        case kMSBDLATimer: return @"Timer";
        case kMSBDLANowPlaying: return @"Now Playing";
        default: return it.title.length ? it.title : @"Live Activity";
    }
}
static DMLAPill *DMLAMakePill(UIView *fg) {
    DMLAPill *p = [DMLAPill buttonWithType:UIButtonTypeCustom];
    p.pointerInteractionEnabled = DMButtonPointerEffects();   // (iPadOS's highlight and pull only with its own pointer)
    p.capsule = [UIView new]; p.capsule.userInteractionEnabled = NO; p.capsule.backgroundColor = [UIColor blackColor];
    p.capsule.layer.cornerCurve = kCACornerCurveContinuous;
    p.glyph = [UIImageView new]; p.glyph.userInteractionEnabled = NO;
    p.label = [UILabel new]; p.label.userInteractionEnabled = NO; p.label.isAccessibilityElement = NO;
    p.bars = [DMLABars new];
    for (UIView *v in @[p.capsule, p.glyph, p.label, p.bars]) [p addSubview:v];
    p.accessibilityHint = @"Shows its Live Activity.";
    __weak DMLAPill *weakP = p;
    [p addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMLAPill *q = weakP; if (q) DMLAOpenCard(q); }] forControlEvents:UIControlEventTouchUpInside];
    [fg addSubview:p];
    return p;
}
static void DMLAMirrorPill(DMLAPill *p, CGFloat w) {   // (a right-to-left bar: the pill's parts mirrored inside it)
    for (UIView *v in @[p.glyph, p.label, p.bars]) v.frame = CGRectMake(w - CGRectGetMaxX(v.frame), v.frame.origin.y, v.frame.size.width, v.frame.size.height);
}
// The pills of a bar copy, laid out in the bar's right end just before `left` (the leftmost of the status icons and our icons, leading
// coordinates); returns where they start (the new left: the keyboard pill and Control Center's pull region go by it). midY: the clock's middle.
static CGFloat DMLALayoutPills(UIView *fg, CGFloat left, CGFloat midY, CGFloat k) {
    NSMutableArray<DMLAPill *> *pills = objc_getAssociatedObject(fg, kLAPillsKey);
    NSArray<DMLAItem *> *items = (gLAOn && left < CGFLOAT_MAX) ? DMLAShownItems() : @[];
    if (!items.count) { for (DMLAPill *p in pills) p.hidden = YES; return left; }
    if (!pills) { pills = [NSMutableArray array]; objc_setAssociatedObject(fg, kLAPillsKey, pills, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    BOOL rtl = DMBarRTL(fg);
    CGFloat H = MIN(round(18.0 * k), fg.bounds.size.height - 4.0);
    if (H < 10.0) { for (DMLAPill *p in pills) p.hidden = YES; return left; }
    // (each item's pill, made or reused by its uid; their widths)
    NSMutableDictionary<NSString *, DMLAPill *> *byUid = [NSMutableDictionary dictionary];
    for (DMLAPill *p in pills) if (p.uid) byUid[p.uid] = p;
    NSMutableArray<DMLAPill *> *use = [NSMutableArray array];
    double widths[64]; int n = (int)MIN(items.count, (NSUInteger)64);
    for (int i = 0; i < n; i++) {
        DMLAItem *it = items[i];
        DMLAPill *p = byUid[it.uid];
        if (!p) { p = DMLAMakePill(fg); p.uid = it.uid; [pills addObject:p]; p.hidden = YES; }
        widths[i] = DMLAConfigurePill(p, it, 0, H, k);
        p.layoutH = H; p.layoutK = k;
        p.accessibilityLabel = DMLAAXLabel(it);
        __weak DMLAItem *weakIt = it;
        p.axValue = ^NSString *{ DMLAItem *x = weakIt; if (!x) return @""; NSString *t = DMLAPillText(x); return x.endedAt > 0 ? [@"Ended " stringByAppendingString:t] : t; };
        [use addObject:p];
    }
    DMLAPill *plusPill = byUid[@"+"];
    if (!plusPill) { plusPill = DMLAMakePill(fg); plusPill.uid = @"+"; plusPill.accessibilityLabel = @"More Live Activities"; [pills addObject:plusPill]; plusPill.hidden = YES; }
    double plusW = DMLAConfigurePill(plusPill, nil, n > 9 ? 99 : 9, H, k);   // (its width for the count's digits)
    CGFloat gap = round(6.0 * k), end = left - round(10.0 * k);
    int plus = 0, shown = MSBDLAFit(widths, n, MSBDLARoom(end, fg.bounds.size.width, round(12.0 * k)), gap, plusW, &plus);
    double total = 0;
    for (int i = 0; i < shown; i++) total += widths[i] + (i ? gap : 0);
    if (plus) { plusW = DMLAConfigurePill(plusPill, nil, plus, H, k); total += plusW + (shown ? gap : 0); }
    __block CGFloat x = end - total;   // (the next pill's start: the block below reads it as it moves)
    BOOL onScreen = fg.window && !fg.window.hidden && fg.bounds.size.width > 300.0;
    void (^place)(DMLAPill *, CGFloat) = ^(DMLAPill *p, CGFloat w) {
        BOOL appear = p.hidden;
        p.frame = DMBarRect(fg, rtl, CGRectMake(x, round(midY - H / 2.0), w, H));
        p.capsule.frame = p.bounds; p.capsule.layer.cornerRadius = H / 2.0;
        if (rtl) DMLAMirrorPill(p, w);
        p.hidden = NO;
        [fg bringSubviewToFront:p];
        if (appear && onScreen) { p.alpha = 0.0; [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ p.alpha = 1.0; } completion:nil]; }
        else if (!appear && p.alpha < 1.0 && ![p.layer animationForKey:@"opacity"]) p.alpha = 1.0;
    };
    for (int i = 0; i < shown; i++) { place(use[i], widths[i]); x += widths[i] + gap; }
    NSMutableArray<NSString *> *rest = [NSMutableArray array];
    for (int i = shown; i < n; i++) [rest addObject:items[i].uid];
    BOOL restChanged = ![plusPill.uids ?: @[] isEqualToArray:rest];
    plusPill.uids = rest;
    if (plus) place(plusPill, plusW); else plusPill.hidden = YES;
    if (restChanged && gLACardPill == plusPill) dispatch_async(dispatch_get_main_queue(), ^{ DMLARebuildOpenCard(); });   // (its open card follows what it holds)
    NSMutableSet<DMLAPill *> *kept = [NSMutableSet setWithArray:[use subarrayWithRange:NSMakeRange(0, shown)]];
    if (plus) [kept addObject:plusPill];
    for (DMLAPill *p in [pills copy]) {   // (every other pill hidden; one whose item went is removed)
        if ([kept containsObject:p]) continue;
        p.hidden = YES;
        if (p == plusPill || (p.uid && gLAItems[p.uid])) continue;
        [p removeFromSuperview]; [pills removeObject:p];
    }
    return (shown || plus) ? end - total : left;
}
// An item's pills drawn again in place, its state the same (Now Playing's art or words, a timer read again): each shown one at the size it was laid
// out at; a copy lays out again only when one of its pills now needs another width (review 1.8.4 L9).
static void DMLARefreshPillsOf(NSString *uid) {
    DMLAItem *it = uid ? gLAItems[uid] : nil;
    if (!it || !gLAOn) return;
    for (UIView *fg in gCopies.allObjects) {
        BOOL relayout = NO;
        for (DMLAPill *p in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey)) {
            if (p.hidden || ![p.uid isEqualToString:uid] || p.layoutH < 1.0) continue;
            CGFloat w = DMLAConfigurePill(p, it, 0, p.layoutH, p.layoutK);
            if (fabs(w - p.bounds.size.width) > 0.5) relayout = YES;
            else if (DMBarRTL(fg)) DMLAMirrorPill(p, p.bounds.size.width);
        }
        if (relayout) [fg setNeedsLayout];
    }
}
// The Lock Screen's layout of a copy (StatusBar.x DMLayoutWithoutClock: passive icons only), and a copy that collapsed: no pills.
static void DMLAHidePills(UIView *fg) { for (DMLAPill *p in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey)) p.hidden = YES; }
// The 1 s clock: the pills' words in place; a pill whose words took another shape (9:59 -> 10:00) makes its copy lay out again.
static void DMLAClockTick(void) {
    if (!gLAOn) return;
    for (UIView *fg in gCopies.allObjects) {
        if (!fg.window || fg.window.hidden) continue;
        BOOL relayout = NO;
        for (DMLAPill *p in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey)) {
            if (p.hidden || [p.uid isEqualToString:@"+"]) continue;
            DMLAItem *it = gLAItems[p.uid];
            if (!it || it.kind == kMSBDLANowPlaying || it.kind == kMSBDLAApp) continue;
            NSString *t = DMLAPillText(it);
            if ([t isEqualToString:p.label.text]) continue;
            p.label.text = t;
            if (![DMLAShapeOf(t) isEqualToString:p.shape]) relayout = YES;
        }
        if (relayout) [fg setNeedsLayout];
    }
    DMLAClockApply();   // (a timer that has run out stops it)
}
// Our controls in the bar, for the status bar's own touch rules (StatusBar.x DMPointOverOurControl, DMBarControlAtScreenPoint, the menu switch,
// Control Center's pull region): the pill at a point of the copy, if any.
static DMLAPill *DMLAPillAt(UIView *fg, CGPoint p) {
    for (DMLAPill *pill in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey))
        if (!pill.hidden && pill.alpha > 0.05 && CGRectContainsPoint(pill.frame, p)) return pill;
    return nil;
}
// The leading edge of the copy's shown pills (leading coordinates of the main screen are the caller's), for Control Center's pull region.
static BOOL DMLAPillsEdge(UIView *fg, UIWindow *w, BOOL rtl, CGFloat *edge) {
    BOOL any = NO;
    for (DMLAPill *p in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey)) {
        if (p.hidden || p.alpha < 0.05 || p.window != w) continue;
        CGRect f = [p convertRect:p.bounds toCoordinateSpace:[UIScreen mainScreen].coordinateSpace];
        if (!(f.size.width >= 1.0)) continue;
        *edge = any ? (rtl ? MAX(*edge, CGRectGetMaxX(f)) : MIN(*edge, CGRectGetMinX(f))) : (rtl ? CGRectGetMaxX(f) : CGRectGetMinX(f));
        any = YES;
    }
    return any;
}

// ---- the card ---------------------------------------------------------------------------------------------------------------------------------
// Each item's part of a card: a section drawn from its item, refreshed in place every 0.5 s while the card is open (DMLACardTimer), built again
// when its item's state changes (its signature).
// What a section shows that only building it again can change -- its kind's state, its texts, its picture (review 1.8.4 M2: an open card is
// compared by this before anything is built; the live values -- seconds, position -- are refreshed in place).
static NSString *DMLAItemSignature(DMLAItem *it) {
    BOOL ended = it.endedAt > 0;
    switch (it.kind) {
        case kMSBDLANowPlaying: return [NSString stringWithFormat:@"np|%@|%@|%@|%@", it.title, it.subtitle, it.artKey, it.bundleID];
        case kMSBDLATimer: return [NSString stringWithFormat:@"timer|%d|%d|%d|%@", it.timerState, ended, DMLATimerHasButtons(it), it.title];
        case kMSBDLACall: return [NSString stringWithFormat:@"call|%d|%d|%d|%d|%@", ended, it.connected, it.held, it.muted, it.title];
        default: return [NSString stringWithFormat:@"app|%d|%@|%@", ended, it.title, it.bundleID];
    }
}
static NSString *DMLACardSignatureOf(NSArray<NSString *> *uids) {
    NSMutableString *sig = [NSMutableString string];
    for (NSString *uid in uids) { DMLAItem *it = gLAItems[uid]; if (it) [sig appendFormat:@"%@#%@;", uid, DMLAItemSignature(it)]; }
    return sig;
}
@interface DMLASection : UIView
@property (nonatomic, copy) NSString *uid;
@property (nonatomic, copy) NSString *signature;
- (void)dm_refresh;
@end
@implementation DMLASection
- (void)dm_refresh {}
@end
// The card's sizes follow Menu Bar Size as our menus' do (MenuBarSize.h MSBDMenuTextScaled: 300 pt wide at Small, x 15/14 at Medium, x 16/14 at
// Large): every size of a section is its Small size x the card's scale, to the half point (set by DMLAMakeCard before it builds the sections).
static CGFloat gLAZ = 1.0;
static inline CGFloat LZ(CGFloat v) { return round(v * gLAZ * 2.0) / 2.0; }
static UIButton *DMLARoundButton(NSString *symbol, CGFloat side, UIColor *bg, UIColor *tint, NSString *ax, void (^action)(void)) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, side, side);
    b.backgroundColor = bg; b.layer.cornerRadius = side / 2.0; b.tintColor = tint;
    [b setImage:DMLAGlyph(symbol, round(side * 0.42)) forState:UIControlStateNormal];
    b.accessibilityLabel = ax;
    b.pointerInteractionEnabled = YES;
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { action(); }] forControlEvents:UIControlEventTouchUpInside];
    return b;
}
static UIButton *DMLAPlainButton(NSString *symbol, CGFloat pt, NSString *ax, void (^action)(void)) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:DMLAGlyph(symbol, pt) forState:UIControlStateNormal];
    b.tintColor = [UIColor labelColor];
    b.accessibilityLabel = ax;
    b.pointerInteractionEnabled = YES;
    [b addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { action(); }] forControlEvents:UIControlEventTouchUpInside];
    return b;
}
// The title line opens the item's app (KT: as a Mac's double click on the activity), after the card closes.
static UIControl *DMLATitleControl(DMLAItem *it, NSString *ax) {
    UIControl *c = [UIControl new];
    c.isAccessibilityElement = YES; c.accessibilityTraits = UIAccessibilityTraitButton;
    c.accessibilityLabel = ax; c.accessibilityHint = @"Opens the app.";
    NSString *bid = it.bundleID, *uid = it.uid; BOOL fake = it.fake;
    [c addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        DMLog([NSString stringWithFormat:@"[liveact] card title: opening the app of %@", DMLAShort(uid)]);
        DMCloseOverlay();
        if (fake || !bid.length) return;
        if ([uid hasPrefix:@"app:"] && DMLAAppsLive()) { DMLAAppsOpen(uid); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMOpenApp(bid); });
    }] forControlEvents:UIControlEventTouchUpInside];
    return c;
}
static UILabel *DMLALabel(CGFloat pt, UIFontWeight w, UIColor *color, BOOL mono) {
    UILabel *l = [UILabel new];
    l.font = mono ? [UIFont monospacedDigitSystemFontOfSize:pt weight:w] : [UIFont systemFontOfSize:pt weight:w];
    l.textColor = color; l.lineBreakMode = NSLineBreakByTruncatingTail; l.userInteractionEnabled = NO;
    return l;
}

// Now Playing: the artwork, the title and the artist (a tap opens the app), the scrubber with its two times, back / play-pause / forward.
@interface DMLAScrubber : UIControl
@property (nonatomic) double duration, position;   // seconds
@property (nonatomic) BOOL dragging;
@property (nonatomic, strong) UIView *track, *fill, *knob;
@end
@implementation DMLAScrubber
- (instancetype)init {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _track = [UIView new]; _fill = [UIView new]; _knob = [UIView new];
    _track.backgroundColor = [UIColor tertiaryLabelColor]; _fill.backgroundColor = [UIColor labelColor];
    _knob.backgroundColor = [UIColor labelColor];
    for (UIView *v in @[_track, _fill, _knob]) { v.userInteractionEnabled = NO; [self addSubview:v]; }
    self.isAccessibilityElement = YES; self.accessibilityLabel = @"Track Position"; self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = 4.0, y = (self.bounds.size.height - h) / 2.0;
    double f = self.duration > 0 ? MIN(1.0, MAX(0.0, self.position / self.duration)) : 0.0;
    self.track.frame = CGRectMake(0, y, w, h); self.track.layer.cornerRadius = h / 2.0;
    self.fill.frame = CGRectMake(0, y, round(w * f), h); self.fill.layer.cornerRadius = h / 2.0;
    CGFloat ks = self.dragging ? 12.0 : 0.0;
    self.knob.frame = CGRectMake(round(w * f) - ks / 2.0, (self.bounds.size.height - ks) / 2.0, ks, ks); self.knob.layer.cornerRadius = ks / 2.0;
    self.alpha = self.duration > 0 ? 1.0 : 0.4;
}
- (void)dm_track:(UITouch *)t {
    if (!(self.duration > 0)) return;
    CGFloat x = [t locationInView:self].x, w = MAX(1.0, self.bounds.size.width);
    self.position = MIN(1.0, MAX(0.0, x / w)) * self.duration;
    [self setNeedsLayout];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { if (!(self.duration > 0)) return NO; self.dragging = YES; [self dm_track:t]; return YES; }
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self dm_track:t]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { if (t) [self dm_track:t]; self.dragging = NO; [self setNeedsLayout]; [self sendActionsForControlEvents:UIControlEventEditingDidEnd]; }
- (void)cancelTrackingWithEvent:(UIEvent *)e { self.dragging = NO; [self setNeedsLayout]; }
- (void)accessibilityIncrement { if (self.duration > 0) { self.position = MIN(self.duration, self.position + 15.0); [self sendActionsForControlEvents:UIControlEventEditingDidEnd]; } }
- (void)accessibilityDecrement { if (self.duration > 0) { self.position = MAX(0.0, self.position - 15.0); [self sendActionsForControlEvents:UIControlEventEditingDidEnd]; } }
- (NSString *)accessibilityValue { char a[32], b[32]; MSBDLAClockText(self.position, 0, a, sizeof a); MSBDLAClockText(self.duration, 0, b, sizeof b); return [NSString stringWithFormat:@"%s of %s", a, b]; }
@end

@interface DMLANowSection : DMLASection
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *title, *line, *from, *to;
@property (nonatomic, strong) DMLAScrubber *scrub;
@property (nonatomic, strong) UIButton *play;
@end
@implementation DMLANowSection
- (void)dm_refresh {
    DMLAItem *it = gLAItems[self.uid];
    if (!it) return;
    double pos = MSBDLAElapsedNow(it.elapsed, CACurrentMediaTime() - it.elapsedStamp, it.playing ? it.rate : 0.0, it.duration);
    if (!self.scrub.dragging) { self.scrub.duration = it.duration; self.scrub.position = pos; [self.scrub setNeedsLayout]; }
    double shown = self.scrub.dragging ? self.scrub.position : pos;
    char a[32], b[32];
    MSBDLAClockText(shown, 0, a, sizeof a); MSBDLAClockText(MAX(0.0, it.duration - shown), 1, b, sizeof b);
    self.from.text = it.duration > 0 ? @(a) : @"";
    self.to.text = it.duration > 0 ? [@"-" stringByAppendingString:@(b)] : @"";
    [self.play setImage:DMLAGlyph(it.playing ? @"pause.fill" : @"play.fill", LZ(24.0)) forState:UIControlStateNormal];
    self.play.accessibilityLabel = it.playing ? @"Pause" : @"Play";
    self.alpha = 1.0;
}
@end
static DMLASection *DMLANowSectionFor(DMLAItem *it, CGFloat W) {
    DMLANowSection *s = [DMLANowSection new];
    s.uid = it.uid;
    CGFloat pad = LZ(14.0), art = LZ(52.0), y = pad;
    UIControl *head = DMLATitleControl(it, [NSString stringWithFormat:@"%@, %@", it.title ?: @"Now Playing", it.subtitle ?: @""]);
    head.frame = CGRectMake(pad, y, W - 2 * pad, art);
    [s addSubview:head];
    s.art = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, art, art)];
    s.art.layer.cornerRadius = LZ(8.0); s.art.layer.cornerCurve = kCACornerCurveContinuous; s.art.clipsToBounds = YES;
    s.art.image = it.art ?: DMLAGlyph(@"music.note", LZ(22.0)); s.art.tintColor = [UIColor secondaryLabelColor];
    s.art.contentMode = it.art ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    s.art.backgroundColor = it.art ? nil : [UIColor tertiarySystemFillColor];
    [head addSubview:s.art];
    CGFloat tx = art + LZ(12.0), tw = W - 2 * pad - tx;
    s.title = DMLALabel(LZ(14.0), UIFontWeightSemibold, [UIColor labelColor], NO); s.title.frame = CGRectMake(tx, LZ(7.0), tw, LZ(19.0)); s.title.text = it.title ?: @"Not Playing";
    s.line = DMLALabel(LZ(13.0), UIFontWeightRegular, [UIColor secondaryLabelColor], NO); s.line.frame = CGRectMake(tx, LZ(27.0), tw, LZ(18.0)); s.line.text = it.subtitle;
    [head addSubview:s.title]; [head addSubview:s.line];
    y += art + LZ(10.0);
    s.scrub = [DMLAScrubber new];
    s.scrub.frame = CGRectMake(pad, y, W - 2 * pad, LZ(16.0));
    s.scrub.userInteractionEnabled = DMLASeekAllowed();   // (the seek not seen to work on this iPadOS: the position only shows -- review 1.8.4 M1)
    if (!s.scrub.userInteractionEnabled) s.scrub.accessibilityTraits = UIAccessibilityTraitStaticText;
    NSString *uid = it.uid;
    __weak DMLANowSection *weakS = s;
    [s.scrub addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakS dm_refresh]; }] forControlEvents:UIControlEventValueChanged];
    [s.scrub addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) {
        // (the position is the control's own -- its section may have been rebuilt away meanwhile: then no seek, never one to 0 -- review 1.8.4 L6)
        DMLAScrubber *sc = [a.sender isKindOfClass:[DMLAScrubber class]] ? (DMLAScrubber *)a.sender : nil;
        DMLANowSection *sec = weakS;
        if (sc && sec && sec.window) { DMLAItem *x = gLAItems[uid]; if (x) DMLANowPlayingSeek(x, sc.position); [sec dm_refresh]; }
        if (gLACardRebuildPending) { gLACardRebuildPending = NO; DMLARebuildOpenCard(); }   // (the rebuild that waited for the drag)
    }] forControlEvents:UIControlEventEditingDidEnd];
    [s addSubview:s.scrub];
    y += LZ(16.0);
    s.from = DMLALabel(LZ(11.0), UIFontWeightMedium, [UIColor secondaryLabelColor], YES); s.from.frame = CGRectMake(pad, y, LZ(80.0), LZ(14.0));
    s.to = DMLALabel(LZ(11.0), UIFontWeightMedium, [UIColor secondaryLabelColor], YES); s.to.frame = CGRectMake(W - pad - LZ(80.0), y, LZ(80.0), LZ(14.0)); s.to.textAlignment = NSTextAlignmentRight;
    [s addSubview:s.from]; [s addSubview:s.to];
    y += LZ(18.0);
    UIButton *back = DMLAPlainButton(@"backward.fill", LZ(20.0), @"Previous Track", ^{ DMLAItem *x = gLAItems[uid]; if (x) DMLANowPlayingSend(x, kDMLAMRPrevious); });
    s.play = DMLAPlainButton(@"play.fill", LZ(24.0), @"Play", ^{ DMLAItem *x = gLAItems[uid]; if (x) DMLANowPlayingSend(x, kDMLAMRToggle); });
    UIButton *next = DMLAPlainButton(@"forward.fill", LZ(20.0), @"Next Track", ^{ DMLAItem *x = gLAItems[uid]; if (x) DMLANowPlayingSend(x, kDMLAMRNext); });
    CGFloat bw = LZ(44.0), bh = LZ(34.0), cx = W / 2.0;
    back.frame = CGRectMake(cx - bw * 1.5 - LZ(16.0), y, bw, bh); s.play.frame = CGRectMake(cx - bw / 2.0, y, bw, bh); next.frame = CGRectMake(cx + bw / 2.0 + LZ(16.0), y, bw, bh);
    for (UIButton *b in @[back, s.play, next]) [s addSubview:b];
    y += bh + LZ(10.0);
    s.frame = CGRectMake(0, 0, W, y);
    s.signature = DMLAItemSignature(it);
    [s dm_refresh];
    return s;
}

// A timer: its name (a tap opens Clock), its countdown, pause / resume and cancel on the current one; another timer's card opens Clock.
@interface DMLATimerSection : DMLASection
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) UIButton *toggle;
@end
@implementation DMLATimerSection
- (void)dm_refresh {
    DMLAItem *it = gLAItems[self.uid];
    if (!it) return;
    self.countLabel.text = DMLAPillText(it);
    if (self.toggle) {
        BOOL running = it.timerState == kMSBDLATimerRunning;
        [self.toggle setImage:DMLAGlyph(running ? @"pause.fill" : @"play.fill", round(self.toggle.bounds.size.width * 0.42)) forState:UIControlStateNormal];
        self.toggle.accessibilityLabel = running ? @"Pause" : @"Resume";
    }
}
@end
static DMLASection *DMLATimerSectionFor(DMLAItem *it, CGFloat W) {
    DMLATimerSection *s = [DMLATimerSection new];
    s.uid = it.uid;
    BOOL ended = it.endedAt > 0;
    CGFloat pad = LZ(14.0), side = LZ(40.0);
    UIControl *head = DMLATitleControl(it, it.title ?: @"Timer");
    BOOL buttons = !ended && DMLATimerHasButtons(it);
    head.frame = CGRectMake(pad, pad, W - 2 * pad - (buttons ? 2 * side + LZ(10.0) : 0), LZ(60.0));
    [s addSubview:head];
    UIImageView *g = [[UIImageView alloc] initWithImage:DMLAGlyph(@"timer", LZ(13.0))];
    g.tintColor = [UIColor systemOrangeColor]; g.frame = CGRectMake(0, LZ(1), LZ(16), LZ(16)); g.contentMode = UIViewContentModeCenter;
    UILabel *name = DMLALabel(LZ(13.0), UIFontWeightSemibold, [UIColor secondaryLabelColor], NO);
    name.frame = CGRectMake(LZ(21), 0, head.bounds.size.width - LZ(21), LZ(18)); name.text = ended ? [NSString stringWithFormat:@"%@ ended", it.title ?: @"Timer"] : it.title;
    s.countLabel = DMLALabel(LZ(30.0), UIFontWeightMedium, ended ? [UIColor tertiaryLabelColor] : [UIColor systemOrangeColor], YES);
    s.countLabel.frame = CGRectMake(0, LZ(20), head.bounds.size.width, LZ(38));
    for (UIView *v in @[g, name, s.countLabel]) [head addSubview:v];
    if (buttons) {
        NSString *uid = it.uid;
        s.toggle = DMLARoundButton(@"pause.fill", side, [[UIColor systemOrangeColor] colorWithAlphaComponent:0.22], [UIColor systemOrangeColor], @"Pause", ^{
            DMLAItem *x = gLAItems[uid]; if (x) DMLATimerAct(x, x.timerState == kMSBDLATimerRunning ? @"pauseCurrentTimer" : @"resumeCurrentTimer");
        });
        UIButton *cancel = DMLARoundButton(@"xmark", side, [UIColor tertiarySystemFillColor], [UIColor labelColor], @"Cancel Timer", ^{
            DMLAItem *x = gLAItems[uid]; if (x) DMLATimerAct(x, @"stopCurrentTimer");
        });
        cancel.frame = CGRectMake(W - pad - side, pad + LZ(18), side, side);
        s.toggle.frame = CGRectMake(CGRectGetMinX(cancel.frame) - LZ(10.0) - side, pad + LZ(18), side, side);
        [s addSubview:s.toggle]; [s addSubview:cancel];
    }
    s.frame = CGRectMake(0, 0, W, pad + LZ(60.0) + pad);
    s.signature = DMLAItemSignature(it);
    [s dm_refresh];
    return s;
}

// A call: the name and its app (a tap opens the app), its time, mute and end.
@interface DMLACallSection : DMLASection
@property (nonatomic, strong) UILabel *status;
@end
@implementation DMLACallSection
- (void)dm_refresh {
    DMLAItem *it = gLAItems[self.uid];
    if (!it) return;
    NSString *t = DMLAPillText(it);
    self.status.text = it.subtitle.length ? [NSString stringWithFormat:@"%@ · %@", it.subtitle, t] : t;
}
@end
static DMLASection *DMLACallSectionFor(DMLAItem *it, CGFloat W) {
    DMLACallSection *s = [DMLACallSection new];
    s.uid = it.uid;
    BOOL ended = it.endedAt > 0;
    CGFloat pad = LZ(14.0), side = LZ(40.0);
    UIControl *head = DMLATitleControl(it, it.title ?: @"Call");
    head.frame = CGRectMake(pad, pad, W - 2 * pad - (ended || !it.onThisDevice ? 0 : 2 * side + LZ(10.0)), side);
    [s addSubview:head];
    UIImageView *g = [[UIImageView alloc] initWithImage:DMLAGlyph(it.video ? @"video.fill" : @"phone.fill", LZ(13.0))];
    g.tintColor = ended ? [UIColor tertiaryLabelColor] : [UIColor systemGreenColor]; g.frame = CGRectMake(0, LZ(2), LZ(16), LZ(16)); g.contentMode = UIViewContentModeCenter;
    UILabel *name = DMLALabel(LZ(14.0), UIFontWeightSemibold, ended ? [UIColor secondaryLabelColor] : [UIColor labelColor], NO);
    name.frame = CGRectMake(LZ(21), 0, head.bounds.size.width - LZ(21), LZ(19)); name.text = it.title;
    s.status = DMLALabel(LZ(12.0), UIFontWeightRegular, [UIColor secondaryLabelColor], YES); s.status.frame = CGRectMake(LZ(21), LZ(20), head.bounds.size.width - LZ(21), LZ(17));
    for (UIView *v in @[g, name, s.status]) [head addSubview:v];
    if (!ended && it.onThisDevice) {
        NSString *uid = it.uid;
        UIButton *mute = DMLARoundButton(it.muted ? @"mic.slash.fill" : @"mic.fill", side, it.muted ? [UIColor labelColor] : [UIColor tertiarySystemFillColor],
                                         it.muted ? [UIColor systemBackgroundColor] : [UIColor labelColor], it.muted ? @"Unmute" : @"Mute", ^{ DMLAItem *x = gLAItems[uid]; if (x) DMLACallAct(x, @"mute"); });
        UIButton *end = DMLARoundButton(@"phone.down.fill", side, [UIColor systemRedColor], [UIColor whiteColor], @"End Call", ^{ DMLAItem *x = gLAItems[uid]; if (x) DMLACallAct(x, @"end"); });
        end.frame = CGRectMake(W - pad - side, pad, side, side);
        mute.frame = CGRectMake(CGRectGetMinX(end.frame) - LZ(10.0) - side, pad, side, side);
        [s addSubview:mute]; [s addSubview:end];
    }
    s.frame = CGRectMake(0, 0, W, pad + side + pad);
    s.signature = DMLAItemSignature(it);
    [s dm_refresh];
    return s;
}

// Another app's Live Activity (17/18, LiveActivityApps.h): the app's own Lock Screen view where that path hosts it, else its icon, its name and Open.
@interface DMLAAppSection : DMLASection
@property (nonatomic) BOOL hostsLive;   // (it holds its activity's live view: DMLAMakeCard tells the rebuild which to keep)
@end
@implementation DMLAAppSection
@end
static DMLASection *DMLAAppSectionFor(DMLAItem *it, CGFloat W) {
    DMLAAppSection *s = [DMLAAppSection new];
    s.uid = it.uid;
    BOOL ended = it.endedAt > 0;
    CGFloat pad = LZ(14.0), icon = LZ(36.0), y = pad;
    UIControl *head = DMLATitleControl(it, it.title ?: @"Live Activity");
    head.frame = CGRectMake(pad, y, W - 2 * pad, icon);
    [s addSubview:head];
    UIImageView *iv = [[UIImageView alloc] initWithImage:DMLAAppIconSmall(it.bundleID)];
    iv.frame = CGRectMake(0, 0, icon, icon); iv.layer.cornerRadius = round(icon * 0.225); iv.layer.cornerCurve = kCACornerCurveContinuous; iv.clipsToBounds = YES;
    iv.alpha = ended ? 0.5 : 1.0;
    UILabel *name = DMLALabel(LZ(14.0), UIFontWeightSemibold, [UIColor labelColor], NO); name.frame = CGRectMake(icon + LZ(10), 0, head.bounds.size.width - icon - LZ(10), LZ(19)); name.text = it.title;
    UILabel *what = DMLALabel(LZ(12.0), UIFontWeightRegular, [UIColor secondaryLabelColor], NO); what.frame = CGRectMake(icon + LZ(10), LZ(19), head.bounds.size.width - icon - LZ(10), LZ(17));
    what.text = ended ? @"Ended" : @"Live Activity";
    for (UIView *v in @[iv, name, what]) [head addSubview:v];
    y += icon;
    CGFloat hostedH = 0;
    UIView *hosted = ended ? nil : DMLAAppsHostedView(it.uid, W - 2 * pad, &hostedH);
    if (hosted) { y += LZ(10.0); hosted.frame = CGRectMake(pad, y, W - 2 * pad, hostedH); [s addSubview:hosted]; y += hostedH; s.hostsLive = YES; }
    s.frame = CGRectMake(0, 0, W, y + pad);
    s.signature = DMLAItemSignature(it);
    return s;
}
static DMLASection *DMLASectionFor(DMLAItem *it, CGFloat W) {
    DMLASection *s = it.kind == kMSBDLANowPlaying ? DMLANowSectionFor(it, W) : it.kind == kMSBDLATimer ? DMLATimerSectionFor(it, W)
                   : it.kind == kMSBDLACall ? DMLACallSectionFor(it, W) : DMLAAppSectionFor(it, W);
    if (it.endedAt > 0 && it.kind != kMSBDLANowPlaying) s.alpha = 0.85;
    return s;
}
// The card: one section (a pill's), or the sections of the "+N" pill's items stacked, divided by lines; taller than the room under the bar, it
// scrolls. W: our menus' width for a card (300 pt at Small, Menu Bar Size's).
static CGFloat DMLACardWidth(void) { return MSBDMenuTextScaled(gDMBarSize, 300.0); }
// hosting: the uids whose section holds its activity's live view (an ended one's does not), for the rebuild to keep those only.
static UIView *DMLAMakeCard(NSArray<NSString *> *uids, CGFloat maxH, NSString **signature, NSSet<NSString *> **hosting) {
    CGFloat W = DMLACardWidth();
    gLAZ = W / 300.0;   // (the sections' sizes: Small's x this)
    NSMutableArray<DMLASection *> *sections = [NSMutableArray array];
    NSMutableSet<NSString *> *live = [NSMutableSet set];
    for (NSString *uid in uids) {
        DMLAItem *it = gLAItems[uid];
        if (!it) continue;
        DMLASection *s = DMLASectionFor(it, W);
        [sections addObject:s];
        if ([s isKindOfClass:[DMLAAppSection class]] && ((DMLAAppSection *)s).hostsLive) [live addObject:uid];
    }
    if (signature) *signature = DMLACardSignatureOf(uids);
    if (hosting) *hosting = live;
    if (!sections.count) return nil;
    CGFloat h = 0;
    for (DMLASection *s in sections) h += s.frame.size.height;
    h += (sections.count - 1) * 1.0;
    CGFloat shownH = MIN(h, MAX(120.0, maxH));
    UIView *host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, shownH)];
    host.layer.shadowColor = [UIColor blackColor].CGColor; host.layer.shadowOpacity = 0.35; host.layer.shadowRadius = 16.0; host.layer.shadowOffset = CGSizeMake(0, 8);
    UIVisualEffectView *blur = DMMakeBlur(14.0);
    blur.frame = host.bounds;
    [host addSubview:blur];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:blur.bounds];
    scroll.contentSize = CGSizeMake(W, h); scroll.showsHorizontalScrollIndicator = NO; scroll.alwaysBounceVertical = NO;
    [blur.contentView addSubview:scroll];
    CGFloat y = 0;
    for (NSUInteger i = 0; i < sections.count; i++) {
        if (i) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(14.0, y, W - 28.0, 1.0)];
            line.backgroundColor = DMMenuDividerColor();
            [scroll addSubview:line];
            y += 1.0;
        }
        DMLASection *s = sections[i];
        s.frame = CGRectMake(0, y, W, s.frame.size.height);
        [scroll addSubview:s];
        y += s.frame.size.height;
    }
    host.accessibilityLabel = uids.count > 1 ? @"Live Activities" : @"Live Activity";
    host.accessibilityContainerType = UIAccessibilityContainerTypeSemanticGroup;
    if ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) DMForceLeftToRight(host, 0);   // (our menus' rule)
    return host;
}
static NSArray<NSString *> *DMLACardUids(DMLAPill *pill) { return [pill.uid isEqualToString:@"+"] ? pill.uids ?: @[] : pill.uid ? @[pill.uid] : @[]; }
static NSString *gLACardSignature = nil;
static void DMLACardRefresh(void) {
    UIView *card = gLACard;
    if (!card) return;
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:card];
    for (NSUInteger i = 0; i < views.count && i < 400; i++) {
        UIView *v = views[i];
        if ([v isKindOfClass:[DMLASection class]]) [(DMLASection *)v dm_refresh];
        else [views addObjectsFromArray:v.subviews];
    }
}
// Where a card goes: under its pill, centred on it, kept on the screen (6 pt from its edges), 4 pt under the bar; maxH: the room down to the bottom.
static CGRect DMLACardFrame(UIView *host, CGRect anchor, CGSize size) {
    CGFloat hostW = DMIsMenuWindowHost(host) ? DMMenuHostWidth(host) : host.bounds.size.width;
    CGFloat x = MAX(6.0, MIN(CGRectGetMidX(anchor) - size.width / 2.0, hostW - size.width - 6.0));
    return CGRectMake(x, CGRectGetMaxY(anchor) + 4.0, size.width, size.height);
}
static BOOL DMLACardDragging(UIView *card) {   // (a scrubber of the card is being dragged now)
    NSMutableArray<UIView *> *views = card ? [NSMutableArray arrayWithObject:card] : [NSMutableArray array];
    for (NSUInteger i = 0; i < views.count && i < 400; i++) {
        UIView *v = views[i];
        if ([v isKindOfClass:[DMLAScrubber class]] && ((DMLAScrubber *)v).dragging) return YES;
        [views addObjectsFromArray:v.subviews];
    }
    return NO;
}
static void DMLARebuildOpenCard(void) {
    DMLAPill *pill = gLACardPill;
    UIView *old = gLACard;
    if (!old || !old.superview) return;
    if (!pill || !pill.superview || pill.hidden) { DMLog(@"[liveact] the open card's pill went: closed"); DMCloseOverlay(); return; }
    NSArray<NSString *> *uids = DMLACardUids(pill);
    NSString *sig = DMLACardSignatureOf(uids);   // (the items' state alone: nothing is built when it is the same -- review 1.8.4 M2)
    if (!sig.length) { DMLog(@"[liveact] the open card has nothing left: closed"); DMCloseOverlay(); return; }
    if ([sig isEqualToString:gLACardSignature]) { DMLACardRefresh(); return; }
    if (DMLACardDragging(old)) { gLACardRebuildPending = YES; return; }   // (not under a finger that drags: built when it lets go)
    gLACardRebuildPending = NO;
    UIView *host = old.superview;
    CGFloat maxH = host.bounds.size.height - old.frame.origin.y - 8.0;
    NSSet<NSString *> *hosting = nil;
    UIView *card = DMLAMakeCard(uids, maxH, NULL, &hosting);
    if (!card) { DMLog(@"[liveact] the open card has nothing left: closed"); DMCloseOverlay(); return; }
    gLACardSignature = sig;
    CGFloat top = old.center.y - old.bounds.size.height / 2.0;   // (its place without the opening's scale, if that still runs: top-aligned, the same middle)
    card.transform = CGAffineTransformIdentity;
    card.center = CGPointMake(old.center.x, top + card.bounds.size.height / 2.0);
    [host insertSubview:card aboveSubview:old];
    [old removeFromSuperview];
    gLACard = card;
    DMLAAppsHostsKeep(hosting ?: [NSSet set]);   // (a live view moved into the new card stays; one no section holds now goes -- its activity left the card or ended: review 1.8.4 P2-L2)
    DMLAAppsHostsAppear();
}
static void DMLAOpenCard(DMLAPill *pill) {
    if (DMTitleTapWithMenuOpen(pill)) return;
    { id lm = DMSBManager("SBLockScreenManager"); if (DMLockUp(lm) || DMCoverSheetShown()) { DMLog(@"[liveact] the Lock Screen or Cover Sheet is up: card not opened"); return; } }
    if (DMGARefuses(@"Live Activity")) return;
    UIView *fg = pill.superview;
    UIView *host = fg ? DMHostFor(fg) : nil;
    if (!host) return;
    DM_FEATURE_MARK("live-activity-card");
    NSArray<NSString *> *uids = DMLACardUids(pill);
    BOOL anyItem = NO;
    for (NSString *uid in uids) if (gLAItems[uid]) { anyItem = YES; break; }
    if (!anyItem) return;   // (nothing to show: no overlay is made for it)
    // (the overlay first, then the place, as every menu: on iPadOS 15 the menu window turns itself only once it is shown, and hidden it keeps its old shape. Measured before, the
    //  first card of a SpringBoard took the pill's place in the portrait shape: y 824 in landscape, off the bottom of the screen -- M1, Zetsu and MilkyWay4, 9 Nov)
    UIControl *o = DMMakeOverlayFor(host, 0.0, YES);
    [o addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { DMCloseOverlay(); }] forControlEvents:UIControlEventTouchUpInside];
    DMAttachMenuHover(o, fg, host, pill);
    CGRect anchor = DMConvertToHost(fg, pill.frame, host);
    NSString *sig = nil;
    UIView *card = DMLAMakeCard(uids, host.bounds.size.height - CGRectGetMaxY(anchor) - 12.0, &sig, NULL);
    if (!card) { DMRemoveOverlayNow(); return; }   // (the whole of what the overlay did undone: focus, keys, the menu window hidden again, the window levels)
    card.frame = DMLACardFrame(host, anchor, card.frame.size);
    [o addSubview:card];
    gLACard = card; gLACardPill = pill; gLACardSignature = sig;
    DMLAAppsHostsAppear();   // (an app's live view in it: on the screen now)
    pill.lit = YES;
    [gLACardTimer invalidate];
    gLACardTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        if (!gLACard) { [t invalidate]; if (gLACardTimer == t) gLACardTimer = nil; return; }
        DMLAPill *p = gLACardPill;
        if (!p || p.hidden || !p.superview) { DMLARebuildOpenCard(); return; }   // (its pill went: the card closes)
        if (gLACardRebuildPending && !DMLACardDragging(gLACard)) { DMLARebuildOpenCard(); return; }   // (a drag that ended without its action: cancelled)
        DMLACardRefresh();
    }];
    DMGateTimer(gLACardTimer);
    card.alpha = 0.0;
    if (MSBReduceMotion()) [UIView animateWithDuration:0.12 animations:^{ card.alpha = 1.0; }];
    else {
        card.transform = CGAffineTransformMakeScale(0.96, 0.96);
        [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{ card.alpha = 1.0; card.transform = CGAffineTransformIdentity; } completion:nil];
    }
    DMLog([NSString stringWithFormat:@"[liveact] card opened: %lu item(s)%@", (unsigned long)uids.count, [pill.uid isEqualToString:@"+"] ? @" (the +N pill)" : @""]);
}
static void DMLAMenuGone(NSString *why) {
    if (!gLACard && !gLACardTimer && !gLACardPill) return;
    gLACard = nil; gLACardSignature = nil; gLACardRebuildPending = NO;
    gLACardPill.lit = NO; gLACardPill = nil;
    [gLACardTimer invalidate]; gLACardTimer = nil;
    DMLAAppsCardGone();   // (hosted views end with the card)
    DMLog([NSString stringWithFormat:@"[liveact] card %@", why]);
}

#include "LiveActivityApps.h"   // (other apps' Live Activities on iPadOS 17/18: SpringBoard's activity manager, behind its own check)

#if DEBUG
// ---- debug triggers (la_state, la_read, la_fake_call, la_fake_timer_<s>, la_fake_np_<0|1|2>, la_fake_app_<bundle>, la_fake_end_<uid>,
// la_fake_clear, la_open_<n>, la_open_plus, la_close, la_keep_<s>; la_probe, la_probe_items: LiveActivityApps.h) ----
static BOOL DMLATrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"la_state"]) {
        NSMutableString *s = [NSMutableString stringWithFormat:@"[liveact] state: %@, kinds call %d timer %d np %d apps %d (apps path %d); timers %d (allowed %d), calls %d (heard %d), MediaRemote %d (seek allowed %d); items:",
                              gLAOn ? @"on" : @"off", gLAKindOn[0], gLAKindOn[1], gLAKindOn[2], gLAKindOn[3], DMLAAppsLive(), gLATimersOK, DMLATimersAllowed(), gLACallsOK, gLACallsHeard, gLAMR.ok, DMLASeekAllowed()];
        for (DMLAItem *it in DMLAShownItems()) [s appendFormat:@" [kind %d %@%@ \"%@\"]", it.kind, DMLAShort(it.uid), it.endedAt > 0 ? @" ended" : @"", DMLAPillText(it)];
        for (UIView *fg in gCopies.allObjects) {
            if (!fg.window || fg.window.hidden) continue;
            [s appendFormat:@"\n  copy %p in %@:", fg, NSStringFromClass([fg.window class])];
            for (DMLAPill *p in (NSArray *)objc_getAssociatedObject(fg, kLAPillsKey))
                if (!p.hidden) [s appendFormat:@" {%@ x %.1f..%.1f y %.1f h %.1f \"%@\"%@}", [p.uid isEqualToString:@"+"] ? @"+N" : DMLAShort(p.uid), p.frame.origin.x, CGRectGetMaxX(p.frame), p.frame.origin.y, p.frame.size.height, p.label.hidden ? @"" : p.label.text, p.lit ? @" lit" : @""];
        }
        if (gLACard) [s appendFormat:@"\n  card %@ in %@", NSStringFromCGRect(gLACard.frame), NSStringFromClass([gLACard.window class])];
        DMLog(s);
        return YES;
    }
    if ([cmd isEqualToString:@"la_read"]) { DMLAStartSources(); return YES; }
    if ([cmd isEqualToString:@"la_timers_try"]) { gLATimersForced = YES; DMLAStartSources(); DMLog([NSString stringWithFormat:@"[liveact] timers: tried on this build (%@)", gLATimersOK ? @"reading" : @"not all there: see above"]); return YES; }
    if ([cmd isEqualToString:@"la_seek_try"]) { gLASeekForced = YES; DMLAChanged(@"seek tried"); DMLog(@"[liveact] Now Playing: the scrubber seeks on this build (the next card)"); return YES; }
    if ([cmd hasPrefix:@"la_keep_"]) { gLAKeep = MAX(2.0, [[cmd substringFromIndex:8] doubleValue]); DMLog([NSString stringWithFormat:@"[liveact] ended ones stay %.0f s", gLAKeep]); return YES; }
    if ([cmd isEqualToString:@"la_fake_call"]) {
        DMLAItem *it = [DMLAItem new]; it.kind = kMSBDLACall; it.uid = @"fake:call"; it.fake = YES; it.connected = YES; it.onThisDevice = YES; it.callStart = CACurrentMediaTime() - 61;
        it.title = @"Test Caller"; it.subtitle = @"FaceTime"; it.bundleID = @"com.apple.facetime"; it.rank = CACurrentMediaTime();
        DMLAUpsert(it, @"test"); return YES;
    }
    if ([cmd hasPrefix:@"la_fake_timer_"]) {
        double secs = MAX(1.0, [[cmd substringFromIndex:14] doubleValue]);
        DMLAItem *it = [DMLAItem new]; it.kind = kMSBDLATimer; it.uid = [NSString stringWithFormat:@"fake:timer%.0f", secs]; it.fake = YES; it.current = YES;
        it.timerState = kMSBDLATimerRunning; it.fireAt = CACurrentMediaTime() + secs; it.rank = secs; it.title = @"Timer"; it.bundleID = @"com.apple.mobiletimer";
        DMLAUpsert(it, @"test"); return YES;
    }
    if ([cmd hasPrefix:@"la_fake_np_"]) { gLAFakeNP = [[cmd substringFromIndex:11] intValue]; if (!gLAFakeNP) [gLAItems removeObjectForKey:@"np"]; DMLANowPlayingRead(); DMLAChanged(@"fake Now Playing"); return YES; }
    if ([cmd hasPrefix:@"la_fake_app_"]) {
        NSString *bid = [cmd substringFromIndex:12];
        DMLAItem *it = [DMLAItem new]; it.kind = kMSBDLAApp; it.uid = [@"fake:app:" stringByAppendingString:bid]; it.fake = YES; it.bundleID = bid;
        it.title = DMLAAppName(bid) ?: bid; it.rank = -0.5;
        DMLAUpsert(it, @"test"); return YES;
    }
    if ([cmd hasPrefix:@"la_fake_end_"]) {
        NSString *uid = [cmd substringFromIndex:12];
        DMLAItem *it = gLAItems[uid] ?: gLAItems[[@"fake:" stringByAppendingString:uid]];
        if (it.kind == kMSBDLATimer) it.timerState = kMSBDLATimerRinging;
        DMLAEnd(it, @"test"); DMLAChanged(@"fake end"); return YES;
    }
    if ([cmd isEqualToString:@"la_fake_clear"]) {
        for (DMLAItem *it in [gLAItems.allValues copy]) if (it.fake) [gLAItems removeObjectForKey:it.uid];
        gLAFakeNP = 0; DMLANowPlayingRead(); DMLAChanged(@"fakes cleared"); return YES;
    }
    if ([cmd hasPrefix:@"la_open_"]) {
        NSString *which = [cmd substringFromIndex:8];
        for (UIView *fg in gCopies.allObjects) {
            if (!fg.window || fg.window.hidden || fg.bounds.size.width < 300.0) continue;
            NSArray<DMLAPill *> *shown = [[(NSArray *)objc_getAssociatedObject(fg, kLAPillsKey) filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DMLAPill *p, id b) { return !p.hidden; }]]
                                          sortedArrayUsingComparator:^NSComparisonResult(DMLAPill *a, DMLAPill *b) { return [@(DMBarLead(fg, DMBarRTL(fg), a.frame)) compare:@(DMBarLead(fg, DMBarRTL(fg), b.frame))]; }];
            DMLAPill *p = nil;
            if ([which isEqualToString:@"plus"]) { for (DMLAPill *q in shown) if ([q.uid isEqualToString:@"+"]) p = q; }
            else { int i = which.intValue; if (i >= 0 && (NSUInteger)i < shown.count) p = shown[i]; }
            if (p) { DMLAOpenCard(p); return YES; }
        }
        DMLog(@"[liveact] la_open_: no such pill on a bar that shows");
        return YES;
    }
    if ([cmd isEqualToString:@"la_close"]) { if (gLACard) DMCloseOverlay(); return YES; }
    return DMLAAppsTrigger(cmd);
}
#endif
