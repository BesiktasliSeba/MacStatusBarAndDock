// TabMuteTweak — the Tab key on a hardware keyboard toggles Mute, systemwide.
//
// Loaded into every UIKit process (filter com.apple.UIKit, like GraveEscapeTweak), in two parts:
//
//  1. Every app (and SpringBoard itself): a plain Tab press arrives in -[UIApplication sendEvent:] as a
//     UIPhysicalKeyboardEvent with _keyCode 43 (HID usage 0x2B). We swallow the key-down and key-up so the app never
//     sees Tab, and on the first key-down (not on auto-repeat) post a Darwin notification.
//  2. SpringBoard only: on that notification, flip ONE shared "muted" state and apply it everywhere:
//       - the sound: -[AVSystemController toggleActiveCategoryMuted] (set, not toggled, so it never gets out of step);
//       - the ringer mute (-[SBRingerControl setRingerMuted:]), which is what SingleMute's status bar icon and Control
//         Center's mute control show, so they always agree with the Tab key;
//       - the volume HUD, shown with the muted look (crossed-out speaker, empty bar) or the normal look. The HUD reads its
//         level from -[SBVolumeControl elasticValueViewControllerCurrentValue:]; while we are showing "muted" that
//         returns 0, exactly what the stock HUD does at volume 0.
//     The other direction: when the ringer mute is changed by something else (Control Center, SingleMute, the mute
//     switch) the sound mute follows. SpringBoard also restores the saved ringer state a moment after every respring;
//     that is ignored (first ReadyDelay seconds, and only real changes count), or every respring would mute the audio.
//     The apps cannot do any of this themselves; these controllers belong to SpringBoard.
//
// Only a bare Tab is taken. With Shift, Control, Option or Command held (Shift+Tab, Cmd+Tab app switching, Ctrl+Tab in
// browsers) the key is left alone. Caps Lock is ignored.
//
// The Settings switch (Settings > Keyboard, shown while a hardware keyboard is attached; off for a new install): apps cannot easily read
// Settings' data, so SpringBoard reads the switch and publishes it as Darwin notification state (kEnabledState, 1 = on; unset = off); every app
// checks that on each Tab press. Flipping the switch therefore takes effect at once, in every app, with no respring.
//
// Apps that need Tab (a terminal, a virtual machine) can be excluded below.

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <notify.h>

#define kHIDTab 43                // HID keyboard usage 0x2B
#define kBlockingModifiers 0x1E0000   // Shift 0x20000, Control 0x40000, Option 0x80000, Command 0x100000
#define kToggleNotification "com.besiktasliseba.tabmutetweak.toggle"
#define kEnabledState       "com.besiktasliseba.tabmutetweak.enabled"        // notification state: 1 = switched on in Settings (unset = off)
#define kPrefsChanged       "com.besiktasliseba.tabmutetweak/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain        CFSTR("com.besiktasliseba.tabmutetweak")

// Bundle identifiers of apps in which Tab keeps working as Tab.
static NSArray<NSString *> *ExcludedApps(void) { return @[]; }

@interface UIPhysicalKeyboardEvent : UIEvent
- (long long)_keyCode;
- (long long)_modifierFlags;
- (BOOL)_isKeyDown;
- (BOOL)_isARepeat;
@end

static BOOL InSpringBoard(void) {
    static BOOL v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ v = strcmp(getprogname(), "SpringBoard") == 0; });
    return v;
}

static BOOL TabMuteSwitchedOff(void) {   // (off unless SpringBoard has published "on": a new install starts off)
    static int token = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ notify_register_check(kEnabledState, &token); });
    uint64_t state = 0;
    return !(token != 0 && notify_get_state(token, &state) == NOTIFY_STATUS_OK && state == 1);
}

static BOOL AppIsExcluded(void) {
    static BOOL excluded;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ excluded = [ExcludedApps() containsObject:NSBundle.mainBundle.bundleIdentifier ?: @""]; });
    return excluded;
}

// Hardening: the four private key-event getters are checked once (per process) before they are ever called; on an iPadOS build without them
// Tab simply passes through untouched instead of crashing every app.
static BOOL KeyEventAPIPresent(void) {
    static BOOL ok;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"UIPhysicalKeyboardEvent");
        ok = c && [c instancesRespondToSelector:@selector(_keyCode)] && [c instancesRespondToSelector:@selector(_modifierFlags)]
            && [c instancesRespondToSelector:@selector(_isKeyDown)] && [c instancesRespondToSelector:@selector(_isARepeat)];
    });
    return ok;
}

// Full Keyboard Access (Settings > Accessibility > Keyboards) moves around with Tab: while it is on, Tab is left to it (1.3.3, audit L-10). Asked
// through the accessibility library's own switch; where that is not there, nothing changes.
static BOOL FullKeyboardAccessOn(void) {
    static Boolean (*fn)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ void *h = dlopen("/usr/lib/libAccessibility.dylib", RTLD_LAZY); if (h) fn = (Boolean (*)(void))dlsym(h, "_AXSFullKeyboardAccessEnabled"); });
    return fn && fn();
}
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if ([event isKindOfClass:%c(UIPhysicalKeyboardEvent)] && KeyEventAPIPresent() && !AppIsExcluded() && !TabMuteSwitchedOff()) {
        UIPhysicalKeyboardEvent *key = (UIPhysicalKeyboardEvent *)event;
        if ([key _keyCode] == kHIDTab && ([key _modifierFlags] & kBlockingModifiers) == 0 && !FullKeyboardAccessOn()) {
            if ([key _isKeyDown] && ![key _isARepeat]) notify_post(kToggleNotification);
            return;   // swallowed: the app never sees this Tab
        }
    }
    %orig;
}
%end

// ---- SpringBoard: do the muting ---------------------------------------------------------------------------
#define kReadyDelay 20.0   // seconds after launch during which ringer changes are treated as the startup restore

static id gVolumeControl = nil;      // SBVolumeControl, captured when SpringBoard creates it
static id gRingerControl = nil;      // SBRingerControl, likewise
static BOOL gMuted = NO;             // our shared "muted" state
static BOOL gIgnoreRingerChange = NO;
static BOOL gHUDShowsMuted = NO;
static NSInteger gHUDGeneration = 0;
static CFTimeInterval gReadyAt = 0;
static int gLastRinger = -1;

#if DEBUG   // (the /tmp/tabmute-debug log exists only in debug builds; in a release build the calls and their arguments compile away)
static void DebugWrite(NSString *line) {
    if (access("/tmp/tabmute-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/tabmute.log", "a");
    if (f) { fprintf(f, "%.3f %s\n", CACurrentMediaTime(), line.UTF8String); fclose(f); }
}
#define Debug(...) DebugWrite(__VA_ARGS__)
#else
#define Debug(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#endif

static id AVController(void) {
    dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY);
    Class av = NSClassFromString(@"AVSystemController");
    return av ? ((id (*)(id, SEL))objc_msgSend)((id)av, NSSelectorFromString(@"sharedAVSystemController")) : nil;
}

// Makes the sound mute equal to `want`. Only toggles when it differs, so calling it twice is harmless.
// (While nothing is playing the system has no sound to mute and ignores this; the ringer and HUD still follow.)
static void SetSoundMuted(BOOL want) {
    id av = AVController();
    SEL getter = NSSelectorFromString(@"getActiveCategoryMuted:"), toggle = NSSelectorFromString(@"toggleActiveCategoryMuted");
    if (!av || ![av respondsToSelector:getter] || ![av respondsToSelector:toggle]) return;
    BOOL now = NO;
    ((BOOL (*)(id, SEL, BOOL *))objc_msgSend)(av, getter, &now);
    if (now != want) ((void (*)(id, SEL))objc_msgSend)(av, toggle);
}

static void SetRingerMuted(BOOL want) {
    SEL setMuted = NSSelectorFromString(@"setRingerMuted:");
    if (!gRingerControl || ![gRingerControl respondsToSelector:setMuted]) return;
    gIgnoreRingerChange = YES;   // this is our own change, not one to mirror back
    ((void (*)(id, SEL, BOOL))objc_msgSend)(gRingerControl, setMuted, want);
    gIgnoreRingerChange = NO;
    gLastRinger = want ? 1 : 0;
}

// The stock volume HUD, with the muted look while gHUDShowsMuted is set.
static void ShowVolumeHUD(BOOL muted) {
    SEL present = NSSelectorFromString(@"_presentVolumeHUDWithVolume:");
    SEL effective = NSSelectorFromString(@"_effectiveVolume");
    if (![gVolumeControl respondsToSelector:present] || (!muted && ![gVolumeControl respondsToSelector:effective])) return;   // (no HUD rather than a wrong one)
    gHUDShowsMuted = muted;
    NSInteger generation = ++gHUDGeneration;
    float volume = muted ? 0.0f : ((float (*)(id, SEL))objc_msgSend)(gVolumeControl, effective);
    ((void (*)(id, SEL, float))objc_msgSend)(gVolumeControl, present, volume);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == gHUDGeneration) gHUDShowsMuted = NO;   // the HUD is gone by now; back to real levels
    });
}

// Audio audit F14: whether things are muted right now, read at the key press instead of trusting gMuted, which starts NO after a respring (the
// ringer may still be muted, and the first Tab only "muted" again) and stays YES after a volume-up cleared the sound mute. The ringer mute is the
// state Control Center and the mute icon show; while something plays and its sound is not muted (volume-up), it counts as not muted, so the press
// mutes what is heard. Falls back to gMuted when the system can't be asked.
static BOOL CurrentlyMuted(void) {
    BOOL muted = gMuted;
    SEL isMuted = NSSelectorFromString(@"isRingerMuted");
    if (gRingerControl && [gRingerControl respondsToSelector:isMuted]) muted = ((BOOL (*)(id, SEL))objc_msgSend)(gRingerControl, isMuted);
    if (!muted) return NO;
    id av = AVController();
    SEL getter = NSSelectorFromString(@"getActiveCategoryMuted:"), attr = NSSelectorFromString(@"attributeForKey:");
    if (!av || ![av respondsToSelector:getter] || ![av respondsToSelector:attr]) return YES;
    id playing = ((id (*)(id, SEL, id))objc_msgSend)(av, attr, @"AVSystemController_AudioIsPlayingSomewhereAttribute");
    if (![playing respondsToSelector:@selector(boolValue)] || ![playing boolValue]) return YES;
    BOOL soundMuted = YES;
    ((BOOL (*)(id, SEL, BOOL *))objc_msgSend)(av, getter, &soundMuted);
    return soundMuted;
}

static void ToggleMute(void) {
    gMuted = !CurrentlyMuted();
    Debug([NSString stringWithFormat:@"[tab] muted -> %d", gMuted]);
    SetSoundMuted(gMuted);
    SetRingerMuted(gMuted);
    ShowVolumeHUD(gMuted);
}

%group SpringBoardHooks

%hook SBVolumeControl
- (id)initWithHUDController:(id)hud ringerControl:(id)ringer telephonyManager:(id)telephony conferenceManager:(id)conference {
    id me = %orig;
    gVolumeControl = me;
    return me;
}
- (float)elasticValueViewControllerCurrentValue:(id)controller {
    return gHUDShowsMuted ? 0.0f : %orig;
}
%end

%hook SBRingerControl
- (id)initWithHUDController:(id)hud soundController:(id)sound {
    id me = %orig;
    gRingerControl = me;
    return me;
}
- (void)setRingerMuted:(BOOL)muted {
    %orig;
    int now = muted ? 1 : 0;
    BOOL changed = (now != gLastRinger);
    gLastRinger = now;
    if (gIgnoreRingerChange || !changed || CACurrentMediaTime() < gReadyAt || TabMuteSwitchedOff()) return;   // (switched off: the ringer is left to itself)
    // Someone else (Control Center, SingleMute, the mute switch) changed the ringer mute: the sound follows.
    Debug([NSString stringWithFormat:@"[ringer] changed elsewhere -> %d, sound follows", now]);
    gMuted = muted;
    SetSoundMuted(muted);
}
%end

%end

static void PublishSwitch(void) {
    static int token = 0;
    if (!token) notify_register_check(kEnabledState, &token);
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = NO;   // off until switched on (Settings > Keyboard)
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v);
        CFRelease(v);
    }
    notify_set_state(token, enabled ? 1 : 0);
}

%ctor {
    %init;   // the UIApplication hook, in every process
    if (!InSpringBoard()) return;
    %init(SpringBoardHooks);
    gReadyAt = CACurrentMediaTime() + kReadyDelay;
    static int toggleToken = 0, prefsToken = 0;
    notify_register_dispatch(kToggleNotification, &toggleToken, dispatch_get_main_queue(), ^(int t) { ToggleMute(); });
    notify_register_dispatch(kPrefsChanged, &prefsToken, dispatch_get_main_queue(), ^(int t) { PublishSwitch(); });
    PublishSwitch();
}
