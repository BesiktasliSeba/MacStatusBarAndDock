// MixAudio: an app that starts playing while another app's audio is already playing is made "mix with others", so a video and a song play
// together (like on a Mac) instead of the app that starts second being silent or the first one being stopped. An app that starts alone keeps
// the session it asked for, so it stays the Now Playing app (Lock Screen / Control Center player, media keys). Phone calls, alarms, Siri and other system sounds still interrupt the way they
// always do: mixing only changes how apps treat each other. Only the plain Playback category is made mixable. The PlayAndRecord category
// (calls, voice / video chat, recording apps) is never touched, so a call app keeps its own exclusive session, and Apple's Music, Podcasts and
// Books, when they ask for the long-form (AirPlay 2) route, are left alone unless they asked to mix themselves (see routeSharingPolicy below).
//
// Mac Status Bar (SpringBoard) publishes the Settings switch as notification state `com.besiktasliseba.mixaudio.disabled` (1 = off); an app that has
// never heard of it sees 0, i.e. mixing on.
//
// ---- per-app volume (Mac Status Bar's Audio menu) ----
// There is no per-app volume API on iOS the way macOS has one, so this works INSIDE each app instead: AVPlayer.volume and AVAudioPlayer.volume
// (and, as a bonus, AVAudioEngine.mainMixerNode.outputVolume) are real, public, settable per-instance properties that most apps' audio flows
// through (plus AVSampleBufferAudioRenderer and apps' own RemoteIO output, see below), and each one is scaled here by a per-bundle-ID multiplier (0.0-1.0, default 1.0 = untouched) that Mac Status Bar writes into
// CFPreferences. The multiplier is a MULTIPLIER, not a replacement value: the app's own requested volume is remembered (per player instance,
// via an associated object) and handed back unchanged to anything that reads `.volume`/`.outputVolume` back, while the REAL underlying value
// actually driving playback is `requested * multiplier`. Consequences (by design, not accident): the hardware mute switch / system silent mode
// always wins, since it is downstream of everything touched here; if the user changes the app's own volume from inside the app, that changes
// what "requested" is and the multiplier keeps applying on top automatically; our own mute toggle in the status bar is just the multiplier
// going to 0, and never touches the app's own volume state either way.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static const char *kDisabledState = "com.besiktasliseba.mixaudio.disabled";

// DEBUG-only tracing (2026-09-23): after two reverted guesses at the YouTube-silent-even-solo bug, this logs what's ACTUALLY happening
// instead of guessing a third time. Pure logging -- calls straight through unchanged, never alters behavior. Writes to this process's own
// container tmp dir (NSTemporaryDirectory(), the same sandbox-scoped location the earlier CFPreferences investigation found -- expected and
// fine for a log file, unlike for a cross-process channel: it just needs to be READ back via that exact app's container path over SSH,
// found the same way that investigation found Spotify's nowplaying plist -- by bundle ID string inside .com.apple.mobile_container_manager.metadata.plist).
#if DEBUG
static void MATraceLog(NSString *line) {
    static NSString *path; static dispatch_once_t once;
    dispatch_once(&once, ^{ path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"mixaudio-trace.log"]; });
    NSString *entry = [NSString stringWithFormat:@"[%.3f] %@\n", CFAbsoluteTimeGetCurrent(), line];
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]; fh = [NSFileHandle fileHandleForWritingAtPath:path]; }
    [fh seekToEndOfFile];
    [fh writeData:data];
    [fh closeFile];
}
static NSString *MAOptString(AVAudioSessionCategoryOptions o) {
    NSMutableArray *parts = [NSMutableArray array];
    if (o & AVAudioSessionCategoryOptionMixWithOthers) [parts addObject:@"Mix"];
    if (o & AVAudioSessionCategoryOptionDuckOthers) [parts addObject:@"Duck"];
    if (o & AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers) [parts addObject:@"InterruptSpoken"];
    if (o & AVAudioSessionCategoryOptionAllowBluetooth) [parts addObject:@"BT"];
    if (o & AVAudioSessionCategoryOptionDefaultToSpeaker) [parts addObject:@"Speaker"];
    if (o & AVAudioSessionCategoryOptionAllowAirPlay) [parts addObject:@"AirPlay"];
    if (o & AVAudioSessionCategoryOptionAllowBluetoothA2DP) [parts addObject:@"BTA2DP"];
    return parts.count ? [parts componentsJoinedByString:@"|"] : @"(none)";
}
#endif

// Own domain, read live (never cached) — CFPreferencesCopyAppValue walks the global search list and has returned a stray value for a
// generic key on this device before (the same gotcha MacStatusBar's own DMLoadPrefs works around), so only this exact domain is ever consulted.
// ROOT CAUSE FOUND LIVE (2026-09-23, real report: YouTube + Spotify genuinely mixing, Audio menu still said "no apps playing" -- the SAME
// bug reported once before and thought fixed by the periodic-refresh timer below; that fix addressed a real secondary staleness issue but
// not the actual cause). Confirmed by inspecting this exact device's Spotify container: a sandboxed app's CFPreferences write for an
// arbitrary (non-own-bundle) domain with kCFPreferencesAnyHost is silently redirected by cfprefsd into the app's OWN container
// (.../Containers/Data/Application/<uuid>/Library/Preferences/<domain>.plist) -- never the real shared /var/mobile/Library/Preferences
// location Mac Status Bar (SpringBoard, unsandboxed) actually reads from. So neither MA_NOWPLAYING_DOMAIN nor MA_VOL_DOMAIN, as a
// CFPreferences custom domain, were EVER actually visible cross-process -- confirmed empty on the SpringBoard side no matter what got
// written here. Both are now used for Darwin notify state instead (per-bundle-hashed names, see MATrackPlaybackActivity/
// MAOwnVolumeMultiplier below) -- notifyd is a real system daemon, not container-scoped, which is exactly why the existing mixAudio
// on/off toggle (a single global notify name, no per-bundle domain) never had this problem in the first place.
static uint32_t MAHash(NSString *bid) {
    uint32_t hash = 2166136261u;
    for (const char *c = bid.UTF8String; c && *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; }
    return hash;
}

static BOOL MAExcludedProcess(void) {
    static BOOL excluded, done;
    if (!done) {
        done = YES;
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"";
        for (NSString *skip in @[@"com.apple.springboard", @"com.apple.mobilephone", @"com.apple.InCallService", @"com.apple.facetime", @"com.apple.TelephonyUtilities", @"com.apple.CarPlayApp"])
            if ([bid isEqualToString:skip]) excluded = YES;
    }
    return excluded;
}
static BOOL MAEnabled(void) {
    static int token = 0; static dispatch_once_t once;
    dispatch_once(&once, ^{ notify_register_check(kDisabledState, &token); });
    uint64_t state = 0;
    return !(token != 0 && notify_get_state(token, &state) == NOTIFY_STATUS_OK && state == 1);
}
// "Audio playing apps" for Mac Status Bar's Audio menu: MPNowPlayingInfoCenter/MRMediaRemote (confirmed live on device, read-only) only ever
// track ONE current "now playing" app system-wide (MPNowPlayingInfoCenter/MRNowPlayingController each hold exactly one _nowPlayingInfo /
// _response / _representedApplicationBundleIdentifier, with no enumeration method and no "PlayerManager"/"SessionManager"-style aggregator
// class found), so they cannot list the several apps MixAudio is specifically for having play at once. This is the fallback instead: every
// time an app sets a playback-ish category (throttled to once per 2 s so a chatty app cannot spam notifyd), a timestamp is posted as Darwin
// notify state under this app's own per-bundle name (see the MAHash comment above for why -- not a shared CFPreferences domain); Mac Status
// Bar checks that exact name directly for each currently-running app and treats it as "playing" while the timestamp is recent (its own idle
// window), and separately always offers any app that already has a saved volume multiplier.
// (Audio audit F15b: the 8 s timer that used to refresh this timestamp for the whole life of every app that ever set a Playback category is gone.
// Its only reader is Mac Status Bar's fallback list for when the system's own list of playing sessions can't be read, which practically never
// happens; there an app that plays for longer than the idle window just drops out of the menu, instead of every audio app waking every 8 s.)
static void MATrackPlaybackActivity(NSString *category) {
    if (MAExcludedProcess()) return;
    BOOL playback = [category isEqualToString:AVAudioSessionCategoryPlayback];
    BOOL playAndRecord = [category isEqualToString:AVAudioSessionCategoryPlayAndRecord];
    if (!playback && !playAndRecord) return;
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (!bid.length) return;
    static CFAbsoluteTime lastWrite = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - lastWrite < 2.0) return;
    lastWrite = now;
    static int token = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.mixaudio.nowplaying.%08x", MAHash(bid));
        notify_register_check(name, &token);
    });
    if (token) notify_set_state(token, (uint64_t)now);
    char postName[64]; snprintf(postName, sizeof postName, "com.besiktasliseba.mixaudio.nowplaying.%08x", MAHash(bid));
    notify_post(postName);
}
static BOOL MAOtherAudioPlaying(void) {   // another app is playing now
    // (Not secondaryAudioShouldBeSilencedHint, which is documented as "another app's NON-mixable session plays": on the iPad 2 (iOS 16) it
    // also said YES next to YouTube after we had made YouTube mixable, so it tells no more than this, and an under-report would stop apps.)
    return [[AVAudioSession sharedInstance] isOtherAudioPlaying];
}
static AVAudioSessionCategoryOptions MAOptions(NSString *category, NSString *mode, AVAudioSessionCategoryOptions options) {
    MATrackPlaybackActivity(category);   // tracked regardless of the mixing switch below: the Audio menu's per-app sliders are a separate feature from "let apps play together"
    if (MAExcludedProcess() || !MAEnabled()) return options;
    // Only Playback. PlayAndRecord is left exactly as the app asked (audio audit F18 + F2): recording apps then behave as the header says, and
    // call apps are never mixable. The old mode check could not do that reliably: WebRTC-based apps (WhatsApp, Discord, Zoom, Teams...) set
    // the category first and switch to voice-chat mode afterwards with a separate -setMode:, so the check saw no mode and made the call mixable.
    // Cost: an app that plays through PlayAndRecord is exclusive again, which only matters against another exclusive app; every Playback app
    // we make mixable still plays along with it (iOS never interrupts a mixable session for an exclusive one).
    if (![category isEqualToString:AVAudioSessionCategoryPlayback]) return options;
    // (Audio audit F3, confirmed on the iPad 2 on 2026-09-26: a mixable session can never be the Now Playing app, so with Mix added to every
    // Playback app, Spotify playing ALONE had no Lock Screen / Control Center player and its media keys went to another app. So only a
    // NEWCOMER mixes: an app that starts while another app is already playing gets Mix and plays along; one that starts alone keeps the
    // session it asked for (exclusive, Now Playing, remote commands, as stock). Playing together still works both ways: iOS never interrupts
    // a mixable session for an exclusive one, and the exclusive first app isn't interrupted by the mixable newcomer. The choice is made again
    // right before each start (MARefreshMixBeforeActivation). Limit: an app resumed while a newcomer still plays mixes too, and then neither is
    // Now Playing until one of them starts again alone.)
    if ((options & AVAudioSessionCategoryOptionMixWithOthers) || !MAOtherAudioPlaying()) return options;
    return options | AVAudioSessionCategoryOptionMixWithOthers;
}


// ---- calls (audio audit F1) ----
// Call audio is never scaled or silenced. An app counts as "in a call" while its session is in a voice / video / game chat mode (noted from the
// app's own -setMode: / -setCategory:mode:... calls, never read back from the audio server) or while it has a voice-processing IO unit (the unit
// WebRTC and other call engines play a call through). While it is, its multiplier is 1.0 whatever the slider or the one-app rule says, and it
// tells SpringBoard so (notify state "com.besiktasliseba.mixaudio.call.<hash>" = this pid, 0 = no call), which keeps it out of the one-app rule.
// (Over-inclusive on purpose: an app that keeps a voice-processing unit for voice notes or game chat just isn't scaled while it has one.)
static volatile int gMAChatMode = 0, gMAVoiceUnits = 0;
static inline BOOL MAInCall(void) { return gMAChatMode || gMAVoiceUnits > 0; }
static BOOL MAIsChatMode(NSString *mode) {
    return [mode isEqualToString:AVAudioSessionModeVoiceChat] || [mode isEqualToString:AVAudioSessionModeVideoChat] || [mode isEqualToString:AVAudioSessionModeGameChat];
}
static void MAPublishCallState(BOOL inCall) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (!bid.length || MAExcludedProcess()) return;
    static int token = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.mixaudio.call.%08x", MAHash(bid));
        notify_register_check(name, &token);   // (kept registered, so the state lives as long as this app does)
    });
    if (token) notify_set_state(token, inCall ? (uint64_t)getpid() : 0);
}

// ---- per-app volume multiplier ----
// Reads live Darwin notify state under the SAME name MARegisterVolumeNotify already listens on for the reapply trigger (Mac Status Bar sets
// the state right before posting, one register/token pair covers both). State 0 means "never explicitly set" (default full volume, 1.0);
// every real value is stored as round(value*1e6)+1 so an explicit mute (0.0) still reads back as "was set" instead of colliding with that.
static float MAOwnVolumeMultiplier(void) {
    if (MAExcludedProcess() || MAInCall()) return 1.0f;   // (F1: a call is always at full level)
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (!bid.length) return 1.0f;
    static int token = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.mixaudio.setvolume.%08x", MAHash(bid));
        notify_register_check(name, &token);
    });
    uint64_t state = 0;
    if (token && notify_get_state(token, &state) == NOTIFY_STATUS_OK && state != 0) {
        float mult = (float)((state - 1) / 1000000.0);
        if (mult < 0.0f) mult = 0.0f; else if (mult > 1.0f) mult = 1.0f;
        return mult;
    }
    return 1.0f;
}
static const void *kMARequestedVolumeKey = &kMARequestedVolumeKey;   // per-player-instance associated object: the volume the APP asked for, unscaled
static NSLock *gMATrackLock;
static NSHashTable *gMATrackedPlayers;   // weak refs to AVPlayer/AVAudioPlayer/AVSampleBufferAudioRenderer instances touched so far, so a live multiplier
                                          // change (Darwin notification) can re-apply immediately to whatever is already playing
static void MAEnsureTracking(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gMATrackLock = [NSLock new]; gMATrackedPlayers = [NSHashTable weakObjectsHashTable]; });
}
static void MATrackPlayer(id player) {
    MAEnsureTracking();
    [gMATrackLock lock];
    [gMATrackedPlayers addObject:player];
    [gMATrackLock unlock];
}
// Fired when Mac Status Bar changes this app's multiplier: re-applies requested*multiplier to every player instance already
// touched, without waiting for the app itself to call setVolume: again (a paused-on-the-slider video would otherwise stay wrong
// until the app next set its own volume, which for many players is "never, while just sitting there playing").
static volatile float gMAOutputMult = 1.0f;   // the multiplier as the audio render thread reads it (refreshed on every change, never read via notify there)
static void MAReapplyAll(void) {
    gMAOutputMult = MAOwnVolumeMultiplier();
    MAEnsureTracking();
    [gMATrackLock lock];
    NSArray *snapshot = [gMATrackedPlayers allObjects];
    [gMATrackLock unlock];
#if DEBUG
    NSMutableArray *desc = [NSMutableArray array];
    for (id p in snapshot) [desc addObject:[NSString stringWithFormat:@"%@ %p%@", NSStringFromClass([p class]), p, [p respondsToSelector:@selector(rate)] ? [NSString stringWithFormat:@" rate %.1f", ((float (*)(id, SEL))objc_msgSend)(p, @selector(rate))] : @""]];
    MATraceLog([NSString stringWithFormat:@"[%@] reapply mult=%.3f to %lu tracked: %@", [NSBundle mainBundle].bundleIdentifier, gMAOutputMult, (unsigned long)snapshot.count, [desc componentsJoinedByString:@", "]]);
#endif
    for (id p in snapshot) {
        NSNumber *req = objc_getAssociatedObject(p, kMARequestedVolumeKey) ?: @1.0f;   // tracked without ever being set = still at the default, full volume
        if ([p respondsToSelector:@selector(setVolume:)]) ((void (*)(id, SEL, float))objc_msgSend)(p, @selector(setVolume:), req.floatValue);
    }
}
static void MARegisterVolumeNotify(void) {
    NSString *bid = [NSBundle mainBundle].bundleIdentifier;
    if (!bid.length || MAExcludedProcess()) return;
    char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.mixaudio.setvolume.%08x", MAHash(bid));
    static int token = 0;
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { MAReapplyAll(); });
}
// A call started or ended: SpringBoard is told, and the players get their level again (full during the call, the slider's after it).
static void MACallStateMaybeChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static BOOL last = NO;
        BOOL now = MAInCall();
        if (now == last) return;
        last = now;
        MAPublishCallState(now);
        MAReapplyAll();
    });
}
static void MANoteChatMode(BOOL on) {
    if (MAExcludedProcess() || (gMAChatMode != 0) == on) return;
    gMAChatMode = on ? 1 : 0;
    MACallStateMaybeChanged();
}
// What a successful category / mode change means for the call state: a chat mode only exists with PlayAndRecord; any other category ends it;
// PlayAndRecord set without a mode keeps whatever mode was set before.
static void MANoteSessionSet(NSString *category, NSString *mode, BOOL modeGiven) {
    if (![category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) MANoteChatMode(NO);
    else if (modeGiven) MANoteChatMode(MAIsChatMode(mode));
}

// ---- a mixing switch reaches apps that are already running (audio audit F12) ----
// MAOptions only runs when the app sets its category, which many apps do once, at launch. So the app's last own request is remembered, and
// right before the app activates its session again (usually: the next time it starts playing) the category is set once more, the same
// category with the app's own options, if the Mix we add no longer matches the switch. Setting the category right before activating is the
// normal order apps use themselves; only plain Playback requests that the app didn't ask to mix itself and that are not long-form are redone.
static pthread_mutex_t gMARequestLock = PTHREAD_MUTEX_INITIALIZER;
static NSString *gMALastCategory = nil;
static AVAudioSessionCategoryOptions gMALastAsked = 0;
static BOOL gMALastAddedMix = NO;
static AVAudioSessionRouteSharingPolicy gMALastPolicy = AVAudioSessionRouteSharingPolicyDefault;   // (the app's own policy; non-default = long-form)
#define MA_MIX_FLAGS (AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionDuckOthers | AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers)
static void MANoteRequest(AVAudioSession *session, NSString *category, AVAudioSessionCategoryOptions asked, AVAudioSessionCategoryOptions applied, AVAudioSessionRouteSharingPolicy policy) {
    if (session != [AVAudioSession sharedInstance]) return;
    pthread_mutex_lock(&gMARequestLock);
    gMALastCategory = [category copy];
    gMALastAsked = asked;
    gMALastAddedMix = (applied & AVAudioSessionCategoryOptionMixWithOthers) && !(asked & AVAudioSessionCategoryOptionMixWithOthers);
    gMALastPolicy = policy;
    pthread_mutex_unlock(&gMARequestLock);
}
static volatile BOOL gMAActive = NO;   // (the app's own explicit setActive: YES / NO; implicit activations are not seen)
static void MARefreshMixBeforeActivation(AVAudioSession *session) {
    if (MAExcludedProcess() || session != [AVAudioSession sharedInstance] || gMAActive) return;   // (already active = already playing: an app that
    // started alone keeps its exclusive session, and so its Now Playing controls, while a newcomer plays along with it)
    pthread_mutex_lock(&gMARequestLock);
    NSString *category = gMALastCategory;
    AVAudioSessionCategoryOptions asked = gMALastAsked;
    BOOL added = gMALastAddedMix;
    AVAudioSessionRouteSharingPolicy policy = gMALastPolicy;
    pthread_mutex_unlock(&gMARequestLock);
    if (![category isEqualToString:AVAudioSessionCategoryPlayback] || (asked & AVAudioSessionCategoryOptionMixWithOthers)) return;
    BOOL longForm = policy != AVAudioSessionRouteSharingPolicyDefault;
    if (longForm && (asked & MA_MIX_FLAGS)) return;
    BOOL join = MAEnabled() && MAOtherAudioPlaying();   // (the newcomer rule, MAOptions: Mix only while another app plays and mixing is on)
    if (join == added) return;
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] before starting: category set again (mix %d, mixing on %d)", [NSBundle mainBundle].bundleIdentifier, join, MAEnabled()]);
#endif
    if (longForm) [session setCategory:category mode:(session.mode ?: AVAudioSessionModeDefault) routeSharingPolicy:policy options:asked error:nil];   // (through the hooks below)
    else [session setCategory:category mode:(session.mode ?: AVAudioSessionModeDefault) options:asked error:nil];
}

%hook AVAudioSession
// TRIED AND REVERTED (2026-09-23): spoofing isOtherAudioPlaying/secondaryAudioShouldBeSilencedHint to NO, theorizing YouTube self-mutes
// via one of Apple's own documented "defer to the other app" properties. The owner's follow-up test (YouTube still fully silent even with
// Spotify PAUSED, i.e. genuinely nothing else playing) rules this theory out on its own -- if it were the real cause, pausing Spotify
// should have unmuted YouTube by itself, override or not, since the real property would already read NO at that point. Reverted rather
// than leave an unconfirmed, unnecessary override in place; real cause is still to be found via live evidence, not more guessing.
- (BOOL)setCategory:(NSString *)category error:(NSError **)outError {
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] setCategory: cat=%@", [NSBundle mainBundle].bundleIdentifier, category]);
#endif
    AVAudioSessionCategoryOptions mixed = MAOptions(category, nil, 0);
    if (mixed) {
        BOOL ok = [self setCategory:category withOptions:mixed error:outError];
        if (ok) MANoteRequest(self, category, 0, mixed, AVAudioSessionRouteSharingPolicyDefault);   // (after the inner call noted Mix as asked: the app asked for no options)
        return ok;
    }
    BOOL ok = %orig;
    if (ok) { MANoteSessionSet(category, nil, NO); MANoteRequest(self, category, 0, 0, AVAudioSessionRouteSharingPolicyDefault); }
    return ok;
}
- (BOOL)setCategory:(NSString *)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    AVAudioSessionCategoryOptions mixed = MAOptions(category, nil, options);
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] setCategory:withOptions: cat=%@ before=%@ after=%@", [NSBundle mainBundle].bundleIdentifier, category, MAOptString(options), MAOptString(mixed)]);
#endif
    NSError *err = nil;
    BOOL ok = %orig(category, mixed, &err);
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@]   -> ok=%d err=%@", [NSBundle mainBundle].bundleIdentifier, ok, err]);
#endif
    if (ok) { MANoteSessionSet(category, nil, NO); MANoteRequest(self, category, options, mixed, AVAudioSessionRouteSharingPolicyDefault); }
    if (outError) *outError = err;
    return ok;
}
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    AVAudioSessionCategoryOptions mixed = MAOptions(category, mode, options);
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] setCategory:mode:options: cat=%@ mode=%@ before=%@ after=%@", [NSBundle mainBundle].bundleIdentifier, category, mode, MAOptString(options), MAOptString(mixed)]);
#endif
    NSError *err = nil;
    BOOL ok = %orig(category, mode, mixed, &err);
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@]   -> ok=%d err=%@", [NSBundle mainBundle].bundleIdentifier, ok, err]);
#endif
    if (ok) { MANoteSessionSet(category, mode, YES); MANoteRequest(self, category, options, mixed, AVAudioSessionRouteSharingPolicyDefault); }
    if (outError) *outError = err;
    return ok;
}
// REAL ROOT CAUSE, FOUND VIA LIVE TRACE (2026-09-23, Spotify-first-then-YouTube order-dependent silence): YouTube's OWN call to this exact
// method already requests Mix|InterruptSpoken on its own -- it never needed help from us. But with policy=1 (AVAudioSessionRouteSharing-
// PolicyLongFormAudio) and Spotify already active, the trace shows six consecutive calls fail outright with OSStatus -50 (paramErr) --
// this is AVFoundation itself rejecting a non-default route sharing policy combined with a mix option while another session already holds
// the route, not a bug in either app. YouTube then falls back to requesting NO options at all, which succeeds but leaves it not actually
// cooperating -- consistent with the silence the owner saw. When YouTube starts FIRST, it never needs to request that failing combination
// (nothing else is active yet), which is exactly why that order worked. An earlier attempt at a fix (see prior revert note, no longer
// here) guessed at making this unconditional and made things worse -- this is instead a surgical fix for the SPECIFIC confirmed-failing
// combination: only when a non-default policy is being combined with a mix-family option is the policy itself dropped to Default (which
// the trace confirms is valid: Spotify's own successful calls all used Default). A non-default policy on its own (no mixing requested) is
// left completely untouched, so Control Center/AirPlay-multiroom integration for an app playing solo is unaffected.
// (Audio audit F6: that last promise was broken, because MAOptions ALWAYS added Mix to Playback, so every long-form app -- Music, Podcasts --
// lost its AirPlay 2 long-form route while mixing was on. Now the policy is only dropped when the APP ITSELF asked for a mix flag (the YouTube
// case above); an app that asks for long-form without mixing is left completely alone -- no Mix added, policy kept -- and behaves as stock.
// It stays exclusive, which only matters against another exclusive app: mixable apps still play along with it.)
// (iOS 16 device test T2, 2026-09-26: "another exclusive app" is common: YouTube asks for long-form WITHOUT a mix flag when it plays on its
// own, and Safari's web media (WebKit's GPU process) does the same, so with mixing on YouTube and Safari still stopped each other. Now a
// long-form app follows the newcomer rule in MAOptions like every Playback app: started while another app plays, it joins the old way --
// Mix added, policy Default -- and started alone it keeps long-form, its AirPlay 2 route and its Now Playing controls.)
- (BOOL)setCategory:(NSString *)category mode:(NSString *)mode routeSharingPolicy:(AVAudioSessionRouteSharingPolicy)policy options:(AVAudioSessionCategoryOptions)options error:(NSError **)outError {
    AVAudioSessionCategoryOptions mixed = MAOptions(category, mode, options);   // tracked the same as the other 3 signatures now, not skipped
    AVAudioSessionRouteSharingPolicy effectivePolicy = policy;
    if (!MAExcludedProcess() && MAEnabled() && policy != AVAudioSessionRouteSharingPolicyDefault && (mixed & MA_MIX_FLAGS)) effectivePolicy = AVAudioSessionRouteSharingPolicyDefault;
#if DEBUG
    BOOL longFormSolo = policy != AVAudioSessionRouteSharingPolicyDefault && !(options & MA_MIX_FLAGS);
    BOOL joins = longFormSolo && (mixed & AVAudioSessionCategoryOptionMixWithOthers);   // (MAOptions only adds Mix while another app plays; only logged)
    MATraceLog([NSString stringWithFormat:@"[%@] setCategory:mode:routeSharingPolicy:options: cat=%@ mode=%@ policy=%ld->%ld before=%@ after=%@%@", [NSBundle mainBundle].bundleIdentifier, category, mode, (long)policy, (long)effectivePolicy, MAOptString(options), MAOptString(mixed), joins ? @" (joins the audio already playing)" : @""]);
#endif
    NSError *err = nil;
    BOOL ok = %orig(category, mode, effectivePolicy, mixed, &err);
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@]   -> ok=%d err=%@", [NSBundle mainBundle].bundleIdentifier, ok, err]);
#endif
    if (ok) { MANoteSessionSet(category, mode, YES); MANoteRequest(self, category, options, mixed, policy); }
    if (outError) *outError = err;
    return ok;
}
// WebRTC-style call engines set the category first and the voice-chat mode afterwards, here (F1/F2).
- (BOOL)setMode:(NSString *)mode error:(NSError **)outError {
    BOOL ok = %orig;
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] setMode: %@ -> ok=%d", [NSBundle mainBundle].bundleIdentifier, mode, ok]);
#endif
    if (ok) MANoteChatMode(MAIsChatMode(mode));
    return ok;
}
- (BOOL)setActive:(BOOL)active error:(NSError **)outError {
    if (active) MARefreshMixBeforeActivation(self);
#if DEBUG
    BOOL wasOtherPlaying = self.otherAudioPlaying;
    MATraceLog([NSString stringWithFormat:@"[%@] setActive:%d (otherAudioPlaying before=%d, exclusive other %d, cat=%@)", [NSBundle mainBundle].bundleIdentifier, active, wasOtherPlaying, self.secondaryAudioShouldBeSilencedHint, self.category]);
#endif
    BOOL ok = %orig;
    if (self == [AVAudioSession sharedInstance] && (ok || !active)) gMAActive = active && ok;
    return ok;
}
- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)outError {
    if (active) MARefreshMixBeforeActivation(self);
#if DEBUG
    BOOL wasOtherPlaying = self.otherAudioPlaying;
    MATraceLog([NSString stringWithFormat:@"[%@] setActive:%d withOptions: (otherAudioPlaying before=%d, exclusive other %d, cat=%@)", [NSBundle mainBundle].bundleIdentifier, active, wasOtherPlaying, self.secondaryAudioShouldBeSilencedHint, self.category]);
#endif
    BOOL ok = %orig;
    if (self == [AVAudioSession sharedInstance] && (ok || !active)) gMAActive = active && ok;
    return ok;
}
%end

// Video players (and most audio-only apps that don't roll their own AVAudioEngine graph) ultimately set their volume here. The getter is
// hooked too, so the app always reads back exactly what IT asked for — our multiplier only ever changes what actually comes out of the
// speaker, never what the app believes its own volume state is (see the file header: no double-bookkeeping, nothing to reconcile).
//
// REVERTED (2026-09-23): tried a one-time self-seed on -play (call self.volume = self.volume to start tracking players that never call
// setVolume: themselves) to explain "slider present but no audible effect". Sliders STILL didn't work after this, so it wasn't the (or
// wasn't the whole) cause -- and it carries a real risk of its own: if a player's real volume reads as 0 at the exact moment -play first
// fires (e.g. a deliberate silent-start-then-fade-in pattern, or before media is actually ready), this would have PERMANENTLY pinned
// "requested" to 0 for that player instance, which no slider position could ever undo. Reverted rather than layering another guess on an
// already-uncertain fix; the volume-multiplier gap needs real evidence (does the target app even call setVolume: on AVPlayer/AVAudioPlayer
// at all, or use its own audio pipeline like Spotify is known to for track decoding) before trying again.
// Players that never call setVolume: themselves (Reddit, traced live: 20 x -play, 0 x setVolume:) were never tracked, so the slider could not
// reach them. They are now tracked as soon as playback starts, WITHOUT seeding "requested" from a read (the reverted attempt described above):
// a player whose app never set a volume is at AVPlayer's default of 1.0 by definition, so the multiplier is applied to 1.0 until the app sets its
// own value, which then takes over through -setVolume: as before. Nothing is applied while the multiplier is 1.0.
static void MATrackStartedPlayer(id player) {
    MATrackPlayer(player);
    if (!objc_getAssociatedObject(player, kMARequestedVolumeKey)) {
        float mult = MAOwnVolumeMultiplier();
        if (mult < 0.999f) ((void (*)(id, SEL, float))objc_msgSend)(player, @selector(setVolume:), 1.0f);   // goes through our -setVolume: below: real = 1.0 * mult
    }
}
%hook AVPlayer
- (void)setVolume:(float)volume {
    objc_setAssociatedObject(self, kMARequestedVolumeKey, @(volume), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MATrackPlayer(self);
    float mult = MAOwnVolumeMultiplier();
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] AVPlayer %p setVolume: requested=%.3f mult=%.3f -> real=%.3f (item %p, muted %d, rate %.1f)", [NSBundle mainBundle].bundleIdentifier, self, volume, mult, volume * mult, self.currentItem, self.muted, self.rate]);
#endif
    %orig(volume * mult);
}
// (Traced live in Reddit and Twitter: with a plain -volume override the player that was actually playing got setVolume: with the scaled value
// every time the slider moved, yet nothing could be heard changing. The likely reason is that AVPlayer reads its own -volume back internally (on
// rate or item changes) and re-applies it, and the override made it read the app's unscaled 1.0 and undo the multiplier. So Apple's own code
// keeps reading the real, scaled volume. Audio audit F9: the APP's own code now reads back what it asked for, so an app that does
// `player.volume = player.volume` (route change, end of a duck, fade loops waiting for 1.0) no longer compounds our level (50% -> 25% -> 12%...).
// "The app's own code" = the caller is not in a system image (/System, /usr/lib); decided from the return address, nothing else changes.)
- (float)volume {
    NSNumber *req = objc_getAssociatedObject(self, kMARequestedVolumeKey);
    if (!req) return %orig;
    Dl_info info;
    void *caller = __builtin_return_address(0);
#if __has_feature(ptrauth_calls)
    caller = ptrauth_strip(caller, ptrauth_key_return_address);   // (arm64e: the return address carries a signature)
#endif
    if (dladdr(caller, &info) && info.dli_fname && strncmp(info.dli_fname, "/System/", 8) != 0 && strncmp(info.dli_fname, "/usr/lib/", 9) != 0) return req.floatValue;
    return %orig;
}
- (BOOL)isMuted {
    BOOL m = %orig;
#if DEBUG
    static BOOL logged; if (!logged) { logged = YES; MATraceLog([NSString stringWithFormat:@"[%@] AVPlayer isMuted read: %d", [NSBundle mainBundle].bundleIdentifier, m]); }
#endif
    return m;
}
- (void)replaceCurrentItemWithPlayerItem:(id)item {
    %orig;
    MATrackStartedPlayer(self);
}
- (void)setRate:(float)rate {
    if (rate != 0.0f && self.rate == 0.0f) MARefreshMixBeforeActivation([AVAudioSession sharedInstance]);   // (apps that let the player activate the session itself)
    %orig;
    if (rate != 0.0f) MATrackStartedPlayer(self);
}
%end

%hook AVAudioPlayer
- (BOOL)play {
    if (!self.playing) MARefreshMixBeforeActivation([AVAudioSession sharedInstance]);   // (as AVPlayer -setRate: above)
    return %orig;
}
- (void)setVolume:(float)volume {
    objc_setAssociatedObject(self, kMARequestedVolumeKey, @(volume), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MATrackPlayer(self);
    float mult = MAOwnVolumeMultiplier();
#if DEBUG
    MATraceLog([NSString stringWithFormat:@"[%@] AVAudioPlayer setVolume: requested=%.3f mult=%.3f -> real=%.3f", [NSBundle mainBundle].bundleIdentifier, volume, mult, volume * mult]);
#endif
    %orig(volume * mult);
}
- (float)volume {
    NSNumber *req = objc_getAssociatedObject(self, kMARequestedVolumeKey);
    return req ? req.floatValue : %orig;
}
%end

// (The AVAudioMixerNode.outputVolume hook that used to be here is gone: AVAudioEngine plays through an in-process RemoteIO unit, which the
// output scaling below already covers, so scaling the mixer as well would have applied the multiplier twice.)

#if DEBUG
// Log-only, added 2026-09-23 alongside the -play tracing above: if a real app's audio graph starts here instead of through
// AVPlayer/AVAudioPlayer, this is where it would show up (Spotify is known industry-wide to use a custom decoder/audio pipeline rather
// than AVFoundation's own player classes for its actual track playback, which would explain why its setVolume calls were always
// requested=0.000 -- incidental, not the real music).
// (A named group, initialised only under DEBUG in the %ctor: an ungrouped %hook inside #if DEBUG breaks the release build, because Logos puts its
// registration in the plain %init outside the #if.)
%group MADebugEngine
%hook AVPlayer   // (the debug-only AVPlayer/AVAudioPlayer -play traces moved into this group too, for the same reason)
// Log-only, added 2026-09-23 specifically to answer: does this app's REAL playback even go through AVPlayer.setVolume: at all? (Two
// concrete findings so far: YouTube's trace has ZERO setVolume/play entries under any hook so far, and Spotify's setVolume calls are
// all requested=0.000, i.e. some other incidental player, not the real track.) Calls straight through unchanged either way.
- (void)play {
    MATraceLog([NSString stringWithFormat:@"[%@] AVPlayer %p play() called, self.volume=%.3f, self.muted=%d, rate=%.2f", [NSBundle mainBundle].bundleIdentifier, self, self.volume, self.muted, self.rate]);
    %orig;
    MATrackStartedPlayer(self);
}
// -play came back with ZERO hits for YouTube -- these are the other two real ways AVPlayer starts real playback (a modern app very
// plausibly uses one of these instead, for finer buffering/rate control), added to find out which one YouTube actually uses.
- (void)playImmediatelyAtRate:(float)rate {
    MATraceLog([NSString stringWithFormat:@"[%@] AVPlayer %p playImmediatelyAtRate:%.2f called, self.volume=%.3f, self.muted=%d", [NSBundle mainBundle].bundleIdentifier, self, rate, self.volume, self.muted]);
    %orig(rate);
    MATrackStartedPlayer(self);
}
%end
%hook AVAudioPlayer
- (BOOL)play {
    MATraceLog([NSString stringWithFormat:@"[%@] AVAudioPlayer play() called, self.volume=%.3f", [NSBundle mainBundle].bundleIdentifier, self.volume]);
    return %orig;
}
%end
%hook AVAudioEngine
- (BOOL)startAndReturnError:(NSError **)outError {
    MATraceLog([NSString stringWithFormat:@"[%@] AVAudioEngine startAndReturnError called, mainMixerNode.outputVolume=%.3f", [NSBundle mainBundle].bundleIdentifier, self.mainMixerNode.outputVolume]);
    return %orig;
}
%end
%end
#endif

#if DEBUG
// Debug builds only: the app tells SpringBoard about its lifecycle events (Darwin notification "com.besiktasliseba.appstate.<n>", state = FNV-1a hash of the bundle id),
// to find out what makes an app (a video player) pause when its window is hidden or the App Switcher is used. Apps cannot write files or log where
// SpringBoard can be read, so this is the way out.
static void MAReport(int code) {
    static uint32_t hash; static dispatch_once_t once;
    dispatch_once(&once, ^{ hash = 2166136261u; for (const char *c = ([NSBundle mainBundle].bundleIdentifier ?: @"").UTF8String; *c; c++) { hash ^= (uint8_t)*c; hash *= 16777619u; } });
    char name[48]; snprintf(name, sizeof name, "com.besiktasliseba.appstate.%d", code);
    int token = 0; notify_register_check(name, &token);
    notify_set_state(token, hash); notify_post(name);
    notify_cancel(token);
}
static void MAObserve(void) {
    if (MAExcludedProcess()) return;
    struct { NSString *name; int code; } events[] = {
        { @"UIApplicationWillResignActiveNotification", 1 }, { @"UIApplicationDidBecomeActiveNotification", 2 }, { @"UIApplicationDidEnterBackgroundNotification", 3 },
        { @"UIApplicationWillEnterForegroundNotification", 4 }, { @"UISceneWillDeactivateNotification", 5 }, { @"UISceneDidActivateNotification", 6 },
        { @"UISceneDidEnterBackgroundNotification", 7 }, { @"UISceneWillEnterForegroundNotification", 8 }, { @"AVAudioSessionInterruptionNotification", 9 } };
    for (size_t i = 0; i < sizeof events / sizeof events[0]; i++) {
        int code = events[i].code;
        [[NSNotificationCenter defaultCenter] addObserverForName:events[i].name object:nil queue:nil usingBlock:^(NSNotification *n) { MAReport(code); }];
    }
}
#endif


// YouTube (traced live) plays through AVSampleBufferAudioRenderer, a public player class with its own per-instance .volume -- same
// requested x multiplier scheme as AVPlayer/AVAudioPlayer, tracked from creation since YouTube sets its volume once, early.
%hook AVSampleBufferAudioRenderer
- (instancetype)init {
    id r = %orig;
    if (r) { MATrackPlayer(r); if (MAOwnVolumeMultiplier() < 0.999f) ((void (*)(id, SEL, float))objc_msgSend)(r, @selector(setVolume:), 1.0f); }
    return r;
}
- (void)setVolume:(float)volume {
    objc_setAssociatedObject(self, kMARequestedVolumeKey, @(volume), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MATrackPlayer(self);
    %orig(volume * MAOwnVolumeMultiplier());
}
- (float)volume {
    NSNumber *req = objc_getAssociatedObject(self, kMARequestedVolumeKey);
    return req ? req.floatValue : %orig;
}
%end

// ---- apps with their own audio pipeline (Spotify, games, AVAudioEngine) ----
// Spotify (traced live) never uses a player class for its music: it builds its own graph ending in a RemoteIO unit (auou/rioc), the unit
// that hands an app's samples to the system. Every RemoteIO / voice-processing unit the app creates gets a render notification; after each
// render of the OUTPUT element (bus 0 -- bus 1 is the microphone and is never touched) the samples are multiplied in place. The client format
// (float, 16- or 32-bit integer) is read once per unit outside the render thread's hot path and cached. Gain ramps across each buffer from the
// last value used, so dragging the slider doesn't click. At multiplier 1.0 nothing is done at all.
#define MA_MAX_UNITS 16
typedef struct { AudioUnit unit; AudioStreamBasicDescription fmt; BOOL known; float lastGain; BOOL voice; } MAUnitState;   // voice: a voice-processing unit (a call), never scaled
static MAUnitState gMAUnits[MA_MAX_UNITS];
static pthread_mutex_t gMAUnitsLock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;   // (F17: our own lock -- recursive, like the @synchronized it replaces -- not one on a process-wide object other code may lock too)
#if DEBUG
static volatile uint64_t gMAScaledBuffers = 0;
static void MAStartUnitTrace(void) {   // every 5 s while it changes: how many output units have the render notify, and how many buffers were scaled
    static dispatch_source_t t; if (t) return;
    t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        static uint64_t last = UINT64_MAX; uint64_t n = gMAScaledBuffers; if (n == last) return; last = n;
        int units = 0; for (int i = 0; i < MA_MAX_UNITS; i++) if (gMAUnits[i].unit) units++;
        MATraceLog([NSString stringWithFormat:@"[%@] output units with the render notify: %d, buffers scaled so far: %llu (multiplier %.3f)", [NSBundle mainBundle].bundleIdentifier, units, n, gMAOutputMult]);
    });
    dispatch_resume(t);
}
#endif
static MAUnitState *MAStateFor(AudioUnit unit) {
    for (int i = 0; i < MA_MAX_UNITS; i++) if (gMAUnits[i].unit == unit) return &gMAUnits[i];
    return NULL;
}
static OSStatus MARenderNotify(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus, UInt32 frames, AudioBufferList *io) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !io) return noErr;
    MAUnitState *st = (MAUnitState *)ref;
    float target = MAInCall() ? 1.0f : gMAOutputMult;   // (F1: read here too, so a call is at full level from its first buffer)
    if (target >= 0.999f && st->lastGain >= 0.999f) return noErr;
    if (!st->known) {
        UInt32 size = sizeof st->fmt;
        if (AudioUnitGetProperty(st->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &st->fmt, &size) != noErr) return noErr;
        st->known = YES;
    }
    float from = st->lastGain;
    st->lastGain = target;
#if DEBUG
    gMAScaledBuffers++;   // (debug: proof the app's own output really passes through here -- traced from MAStartUnitTrace, never from the render thread)
#endif
    BOOL isFloat = (st->fmt.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    UInt32 bits = st->fmt.mBitsPerChannel;
    for (UInt32 b = 0; b < io->mNumberBuffers; b++) {
        AudioBuffer *buf = &io->mBuffers[b];
        if (!buf->mData || !buf->mDataByteSize) continue;
        if (isFloat && bits == 32) {
            float *x = (float *)buf->mData; UInt32 n = buf->mDataByteSize / sizeof(float);
            for (UInt32 i = 0; i < n; i++) x[i] *= from + (target - from) * ((float)i / (float)n);
        } else if (!isFloat && bits == 16) {
            SInt16 *x = (SInt16 *)buf->mData; UInt32 n = buf->mDataByteSize / sizeof(SInt16);
            for (UInt32 i = 0; i < n; i++) x[i] = (SInt16)((float)x[i] * (from + (target - from) * ((float)i / (float)n)));
        } else if (!isFloat && bits == 32) {
            SInt32 *x = (SInt32 *)buf->mData; UInt32 n = buf->mDataByteSize / sizeof(SInt32);
            for (UInt32 i = 0; i < n; i++) x[i] = (SInt32)((double)x[i] * (from + (target - from) * ((float)i / (float)n)));
        }
    }
    return noErr;
}
%group MAOutput
%hookf(OSStatus, AudioComponentInstanceNew, AudioComponent component, AudioComponentInstance *outInstance) {
    OSStatus r = %orig;
    if (r != noErr || !outInstance || !*outInstance) return r;
    AudioComponentDescription d = {0};
    AudioComponentGetDescription(component, &d);
    if (d.componentType != kAudioUnitType_Output || (d.componentSubType != kAudioUnitSubType_RemoteIO && d.componentSubType != kAudioUnitSubType_VoiceProcessingIO)) return r;
    pthread_mutex_lock(&gMAUnitsLock);
    {
        for (int i = 0; i < MA_MAX_UNITS; i++) {
            if (gMAUnits[i].unit) continue;
            BOOL voice = d.componentSubType == kAudioUnitSubType_VoiceProcessingIO;
            gMAUnits[i] = (MAUnitState){ *outInstance, {0}, NO, 1.0f, voice };
            if (voice) { gMAVoiceUnits++; MACallStateMaybeChanged(); }   // (F1: call audio -- counted, never given the render notify)
            else AudioUnitAddRenderNotify(*outInstance, MARenderNotify, &gMAUnits[i]);
#if DEBUG
            MATraceLog([NSString stringWithFormat:@"[%@] output unit %p created (subtype %08x): render notify added", [NSBundle mainBundle].bundleIdentifier, *outInstance, (unsigned)d.componentSubType]);
            MAStartUnitTrace();
#endif
            break;
        }
    }
    pthread_mutex_unlock(&gMAUnitsLock);
    return r;
}
%hookf(OSStatus, AudioComponentInstanceDispose, AudioComponentInstance unit) {
    pthread_mutex_lock(&gMAUnitsLock);
    {
        MAUnitState *st = MAStateFor(unit);
        if (st) {
            if (st->voice) { gMAVoiceUnits--; MACallStateMaybeChanged(); }
            else AudioUnitRemoveRenderNotify(unit, MARenderNotify, st);
            memset(st, 0, sizeof *st);
        }
    }
    pthread_mutex_unlock(&gMAUnitsLock);
    return %orig;
}
%hookf(OSStatus, AudioUnitSetProperty, AudioUnit unit, AudioUnitPropertyID prop, AudioUnitScope scope, AudioUnitElement elem, const void *data, UInt32 size) {
    OSStatus r = %orig;
    if (prop == kAudioUnitProperty_StreamFormat) { MAUnitState *st = MAStateFor(unit); if (st) st->known = NO; }   // re-read on the next render
    return r;
}
%end

%ctor {
    dlopen("/System/Library/Frameworks/AVFAudio.framework/AVFAudio", RTLD_LAZY);      // AVAudioSession, AVAudioPlayer, AVAudioEngine/AVAudioMixerNode live here
    dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY);   // AVPlayer lives in the umbrella framework itself, not AVFAudio -- both must be loaded before %init installs the hooks below
    %init;
    MARegisterVolumeNotify();
    MAPublishCallState(NO);   // (a fresh process is in no call: clears a state an earlier instance of this app may have left)
    if (!MAExcludedProcess() && [NSBundle mainBundle].bundleIdentifier.length) {
        // "MixAudio runs in this app": notify state com.besiktasliseba.mixaudio.alive.<hash> = this pid, held for the app's life. The Audio menu
        // greys out the controls of a playing app whose current pid never said so (Choicy-excluded, launched without tweaks, system apps; F13).
        static int aliveToken = 0;
        char name[64]; snprintf(name, sizeof name, "com.besiktasliseba.mixaudio.alive.%08x", MAHash([NSBundle mainBundle].bundleIdentifier));
        if (notify_register_check(name, &aliveToken) == NOTIFY_STATUS_OK) notify_set_state(aliveToken, (uint64_t)getpid());
    }
    gMAOutputMult = MAOwnVolumeMultiplier();
    if (!MAExcludedProcess())   // (an interruption deactivates the session without a -setActive:NO: the next start decides mixing again)
        [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
            if ([n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) gMAActive = NO;
        }];
    if (!MAExcludedProcess()) %init(MAOutput);   // "com.besiktasliseba.mixaudio.setvolume.<hash of this app's own bundle id>" -- Mac Status Bar's per-app bridge, same pattern as MacAppBridge
#if DEBUG
    MAObserve();
    %init(MADebugEngine);
#endif
}
