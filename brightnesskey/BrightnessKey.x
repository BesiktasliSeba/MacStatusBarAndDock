// BrightnessKeyTweak
//
// Keyboard shortcuts for the two brightness levels, both needing Shift held:
//   Shift + Option (Alt)  ->  keyboard backlight brighter      (was: screen brighter)
//   Shift + Control       ->  keyboard backlight dimmer        (was: screen dimmer)
//   Shift + = (+)         ->  screen brighter
//   Shift + - (_)         ->  screen dimmer
//
// Loaded into every UIKit process (filter com.apple.UIKit), because plain keys such as = and - only reach the app
// that has keyboard focus:
//  - Every process: Shift + the =/+ key or the -/_ key is swallowed (down and up, so no "+" or "_" is typed) and
//    posts a Darwin notification; SpringBoard changes the screen brightness. Held keys auto-repeat, so holding
//    ramps the brightness. Combinations that also hold Control, Option or Command are left alone.
//  - SpringBoard only: the Shift + Option / Shift + Control modifier combos, which SpringBoard sees itself, change
//    the keyboard backlight through CoreBrightness' KeyboardBrightnessClient (the same client Control Center's
//    "Keyboard Brightness" slider uses).
//
// Settings > Keyboard (shown while a hardware keyboard is attached) has one switch per function (both off for a new install). SpringBoard reads
// the switches and publishes them as Darwin notification STATE (1 = on; unset = off); every process checks
// the state on each key press, so a switch takes effect at once, in every app, with no respring. A switched-off
// combination is not touched at all: the key reaches the app as usual (so + and _ type normally again).
//
// Debug: `touch /tmp/brightnesskey-debug` makes SpringBoard write /tmp/brightnesskey.log (keys seen, backlight state
// after each change, and any call Control Center makes to the keyboard brightness client).

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <notify.h>
#include <sys/stat.h>

@interface UIPhysicalKeyboardEvent : UIEvent
- (long long)_modifierFlags;
- (unsigned short)_keyCode;
- (BOOL)_isKeyDown;
@end

@interface UIDevice (Category)
@property float _backlightLevel;
@end

@interface SBDisplayBrightnessController : NSObject
- (void)setBrightnessLevel:(float)arg1 animated:(BOOL)animated;
@end

#define SHIFT_FLAG   0x20000
#define CONTROL_FLAG 0x40000
#define OPTION_FLAG  0x80000
#define COMMAND_FLAG 0x100000
#define CONTROL_KEYCODE 224   // left Control
#define OPTION_KEYCODE  226   // left Option
#define KEY_MINUS  45         // HID 0x2D  - and _
#define KEY_EQUALS 46         // HID 0x2E  = and +
#define BRIGHTNESS_STEP 0.0625f
#define BACKLIGHT_STEP  0.0625f

#define kScreenUp   "com.besiktasliseba.brightnesskeytweak.screen.up"
#define kScreenOnState     "com.besiktasliseba.brightnesskeytweak.screen.enabled"       // notification state: 1 = switched on in Settings (unset = off)
#define kBacklightOnState  "com.besiktasliseba.brightnesskeytweak.backlight.enabled"
#define kPrefsChanged      "com.besiktasliseba.brightnesskeytweak/prefsChanged"          // posted by the Settings switches
#define kPrefsDomain       CFSTR("com.besiktasliseba.brightnesskeytweak")
#define kScreenDown "com.besiktasliseba.brightnesskeytweak.screen.down"

static BOOL InSpringBoard(void) {
    static BOOL v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ v = strcmp(getprogname(), "SpringBoard") == 0; });
    return v;
}

// Is this function switched off in Settings? Checked on every key press, in whichever process sees the key.
static BOOL SwitchedOff(const char *stateName, int *token) {   // (off unless SpringBoard has published "on": a new install starts off)
    if (*token == 0) notify_register_check(stateName, token);
    uint64_t state = 0;
    return !(*token != 0 && notify_get_state(*token, &state) == NOTIFY_STATUS_OK && state == 1);
}
static BOOL ScreenKeysOff(void)   { static int t = 0; return SwitchedOff(kScreenOnState, &t); }
static BOOL BacklightKeysOff(void) { static int t = 0; return SwitchedOff(kBacklightOnState, &t); }

#if DEBUG   // (the /tmp/brightnesskey-debug log exists only in debug builds; in a release build the calls and their arguments compile away)
static void DebugWrite(NSString *line) {
    if (access("/tmp/brightnesskey-debug", F_OK) != 0) return;
    FILE *f = fopen("/tmp/brightnesskey.log", "a");
    if (f) { fprintf(f, "%.3f %s\n", CACurrentMediaTime(), line.UTF8String); fclose(f); }
}
#define Debug(...) DebugWrite(__VA_ARGS__)
#else
#define Debug(...) do { if (0) { (void)(__VA_ARGS__); } } while (0)
#endif

// ---- screen brightness (SpringBoard) --------------------------------------------------------------------
static SBDisplayBrightnessController *gBrightnessController = nil;

static void AdjustScreenBrightness(float delta) {
    // Hardening: the private class and both calls are checked before use (an iPadOS build without them: the keys do nothing instead of crashing).
    Class bc = NSClassFromString(@"SBDisplayBrightnessController");
    if (!bc || ![bc instancesRespondToSelector:@selector(setBrightnessLevel:animated:)] || ![[UIDevice currentDevice] respondsToSelector:@selector(_backlightLevel)]) return;
    if (!gBrightnessController) gBrightnessController = [bc new];
    float current = [[%c(UIDevice) currentDevice] _backlightLevel];
    float target = current + delta;
    if (target < 0.0f) target = 0.0f;
    if (target > 1.0f) target = 1.0f;
    [gBrightnessController setBrightnessLevel:target animated:NO];
    Debug([NSString stringWithFormat:@"[screen] %.4f -> %.4f", current, target]);
}

// ---- keyboard backlight (SpringBoard) -------------------------------------------------------------------
static id gKBClient = nil;
static unsigned long long gKBID = 0;
static float gKBLevel = -1.0f;      // the level we last asked for; -1 = not known yet
static BOOL gKBAutoOff = NO;

static NSString *KBState(void) {
    for (NSString *n in @[@"brightnessForKeyboard:", @"isAutoBrightnessEnabledForKeyboard:", @"isBacklightDimmedOnKeyboard:", @"isBacklightSuppressedOnKeyboard:"])
        if (![gKBClient respondsToSelector:NSSelectorFromString(n)]) return @"(state not readable)";
    float b = ((float (*)(id, SEL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"brightnessForKeyboard:"), gKBID);
    BOOL a = ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"isAutoBrightnessEnabledForKeyboard:"), gKBID);
    BOOL d = ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"isBacklightDimmedOnKeyboard:"), gKBID);
    BOOL s = ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"isBacklightSuppressedOnKeyboard:"), gKBID);
    return [NSString stringWithFormat:@"brightness=%.4f auto=%d dimmed=%d suppressed=%d", b, a, d, s];
}

static BOOL EnsureKeyboardClient(void) {
    if (gKBClient) return gKBID != 0;
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
    Class c = NSClassFromString(@"KeyboardBrightnessClient");
    // Hardening: every private call the backlight keys make is checked once; if one is missing, the client is never created.
    if (!c) return NO;
    for (NSString *n in @[@"copyKeyboardBacklightIDs", @"brightnessForKeyboard:", @"enableAutoBrightness:forKeyboard:", @"setBrightness:forKeyboard:"])
        if (![c instancesRespondToSelector:NSSelectorFromString(n)]) return NO;
    gKBClient = [[c alloc] init];
    if (!gKBClient) return NO;
    id ids = ((id (*)(id, SEL))objc_msgSend)(gKBClient, NSSelectorFromString(@"copyKeyboardBacklightIDs"));
    if ([ids isKindOfClass:[NSArray class]] && [ids count]) gKBID = [[ids firstObject] unsignedLongLongValue];
    Debug([NSString stringWithFormat:@"[kb] client ready, keyboard id %llu", gKBID]);
    return gKBID != 0;
}

// The strategy while I find out what works: /tmp/brightnesskey-mode says "manual" (turn auto-brightness off the first
// time, then set levels) or "auto" (leave auto-brightness on and just set levels). Default: manual.
static BOOL WantManualMode(void) {
#if !DEBUG
    return YES;   // (release: the default, manual; the /tmp switch is a debug-only experiment)
#endif
    NSString *m = [NSString stringWithContentsOfFile:@"/tmp/brightnesskey-mode" encoding:NSUTF8StringEncoding error:nil];
    return ![m hasPrefix:@"auto"];
}

static void AdjustKeyboardBacklight(float delta) {
    if (!EnsureKeyboardClient()) { Debug(@"[kb] no keyboard backlight available"); return; }
    if (gKBLevel < 0.0f) {
        gKBLevel = ((float (*)(id, SEL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"brightnessForKeyboard:"), gKBID);
        Debug([NSString stringWithFormat:@"[kb] starting level read as %.4f", gKBLevel]);
    }
    if (WantManualMode() && !gKBAutoOff) {
        ((void (*)(id, SEL, BOOL, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"enableAutoBrightness:forKeyboard:"), NO, gKBID);
        gKBAutoOff = YES;
    }
    float target = gKBLevel + delta;
    if (target < 0.0f) target = 0.0f;
    if (target > 1.0f) target = 1.0f;
    gKBLevel = target;
    BOOL ok = ((BOOL (*)(id, SEL, float, unsigned long long))objc_msgSend)(gKBClient, NSSelectorFromString(@"setBrightness:forKeyboard:"), target, gKBID);
    Debug([NSString stringWithFormat:@"[kb] asked for %.4f (ok=%d) | right away: %@", target, ok, KBState()]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Debug([NSString stringWithFormat:@"[kb]   0.5 s later for %.4f: %@", target, KBState()]);
    });
}

// ---- keys ------------------------------------------------------------------------------------------------
static unsigned short gLastCode = 0;
static unsigned long long gLastFlags = 0;

// Hardening: the private key-event getters are checked once per process before they are ever called.
static BOOL KeyEventAPIPresent(void) {
    static BOOL ok;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"UIPhysicalKeyboardEvent");
        ok = c && [c instancesRespondToSelector:@selector(_keyCode)] && [c instancesRespondToSelector:@selector(_modifierFlags)] && [c instancesRespondToSelector:@selector(_isKeyDown)];
    });
    return ok;
}

%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if ([event isKindOfClass:%c(UIPhysicalKeyboardEvent)] && KeyEventAPIPresent()) {
        UIPhysicalKeyboardEvent *key = (UIPhysicalKeyboardEvent *)event;
        unsigned long long flags = (unsigned long long)[key _modifierFlags];
        unsigned short code = [key _keyCode];

        // Shift + = / Shift + -: screen brightness, in every process (swallowed so nothing is typed)
        if ((code == KEY_EQUALS || code == KEY_MINUS) && (flags & SHIFT_FLAG) && !(flags & (CONTROL_FLAG | OPTION_FLAG | COMMAND_FLAG)) && !ScreenKeysOff()) {
            if ([key _isKeyDown]) notify_post(code == KEY_EQUALS ? kScreenUp : kScreenDown);
            return;
        }

        // Shift + Option / Shift + Control: keyboard backlight, seen by SpringBoard
        if (InSpringBoard() && !BacklightKeysOff()) {
            BOOL isDuplicate = (code == gLastCode && flags == gLastFlags);
            gLastCode = code;
            gLastFlags = flags;
            if (!isDuplicate && (flags & SHIFT_FLAG)) {
                if (code == OPTION_KEYCODE) {
                    Debug(@"[key] Shift+Option -> keyboard backlight up");
                    AdjustKeyboardBacklight(BACKLIGHT_STEP);
                    return;
                }
                if (code == CONTROL_KEYCODE) {
                    Debug(@"[key] Shift+Control -> keyboard backlight down");
                    AdjustKeyboardBacklight(-BACKLIGHT_STEP);
                    return;
                }
            }
        }
    }
    %orig;
}
%end

// What Control Center's own Keyboard Brightness slider does (debug only): log every call to the client.
// (Compiled and installed only in DEBUG builds: a named group whose %init is also under DEBUG, see the release hardening plan.)
#if DEBUG
%group KBClientLogging
%hook KeyboardBrightnessClient
- (BOOL)setBrightness:(float)b forKeyboard:(unsigned long long)k {
    BOOL r = %orig;
    Debug([NSString stringWithFormat:@"[client] setBrightness:%.4f forKeyboard -> %d", b, r]);
    return r;
}
- (BOOL)setBrightness:(float)b fadeSpeed:(int)speed commit:(BOOL)commit forKeyboard:(unsigned long long)k {
    BOOL r = %orig;
    Debug([NSString stringWithFormat:@"[client] setBrightness:%.4f fadeSpeed:%d commit:%d -> %d", b, speed, commit, r]);
    return r;
}
- (BOOL)enableAutoBrightness:(BOOL)on forKeyboard:(unsigned long long)k {
    BOOL r = %orig;
    Debug([NSString stringWithFormat:@"[client] enableAutoBrightness:%d -> %d", on, r]);
    return r;
}
- (BOOL)suspendIdleDimming:(BOOL)on forKeyboard:(unsigned long long)k {
    BOOL r = %orig;
    Debug([NSString stringWithFormat:@"[client] suspendIdleDimming:%d -> %d", on, r]);
    return r;
}
%end
%end
#endif

static void PublishSwitches(void) {
    static int screenToken = 0, backlightToken = 0;
    if (!screenToken) notify_register_check(kScreenOnState, &screenToken);
    if (!backlightToken) notify_register_check(kBacklightOnState, &backlightToken);
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL screenOn = NO, backlightOn = NO;   // off until switched on (Settings > Keyboard)
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("screenKeysEnabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) screenOn = CFBooleanGetValue(v); CFRelease(v); }
    v = CFPreferencesCopyValue(CFSTR("backlightKeysEnabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) backlightOn = CFBooleanGetValue(v); CFRelease(v); }
    notify_set_state(screenToken, screenOn ? 1 : 0);
    notify_set_state(backlightToken, backlightOn ? 1 : 0);
    Debug([NSString stringWithFormat:@"[prefs] screen keys %@, backlight keys %@", screenOn ? @"on" : @"off", backlightOn ? @"on" : @"off"]);
}

%ctor {
    %init;
    if (!InSpringBoard()) return;
    static int upToken = 0, downToken = 0, prefsToken = 0;
    notify_register_dispatch(kPrefsChanged, &prefsToken, dispatch_get_main_queue(), ^(int t) { PublishSwitches(); });
    PublishSwitches();
    notify_register_dispatch(kScreenUp, &upToken, dispatch_get_main_queue(), ^(int t) { AdjustScreenBrightness(BRIGHTNESS_STEP); });
    notify_register_dispatch(kScreenDown, &downToken, dispatch_get_main_queue(), ^(int t) { AdjustScreenBrightness(-BRIGHTNESS_STEP); });
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
#if DEBUG
    if (NSClassFromString(@"KeyboardBrightnessClient")) { %init(KBClientLogging); }
#endif
}
