#include <unistd.h>
#include <stdio.h>
// VolumeGlobeTweak (SpringBoard) -- Globe + Option raises and Globe + Control lowers the volume, and the Globe key's shortcut overlay is kept from
// appearing while it is held. The Settings switch (Settings > Keyboard, shown while a hardware keyboard is attached) is off for a new install.
#import <UIKit/UIKit.h>
#include <notify.h>
#include "../common/ModifierTap.h"   // (1.8.3: while Window Tiling Keys are offered, the chords act at their key's release, never inside a Globe-Control shortcut)
#include "../common/KeyboardChords.h"   // (1.8.7: the same while one of your own shortcuts starts with Globe + Option / Control: kMSBDKCYoursState)

#define kPrefsChanged "com.besiktasliseba.volumeglobetweak/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain  CFSTR("com.besiktasliseba.volumeglobetweak")
static BOOL gEnabled = NO;
static BOOL gDefer = NO;   // (Window Tiling Keys offered, or a shortcut of yours starting with this very chord -- common/ModifierTap.h, KeyboardChords.h)
static BOOL gOffered = NO, gYoursWait = NO;
static MSBDModTap gTap;
static void ReadSwitch(void) {
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = NO;   // off until switched on
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v); CFRelease(v); }
    gEnabled = enabled;
}
// Whether SpringBoard offers the window keys now (their switch on and a window engine of ours running: MacStatusBarCore sets the state): only then
// does the chord wait for its key's release. Not offered -- the switch off, Window Engine None, MacStatusBarCore not running -- it acts as its key
// goes down, as in 1.8.2.2.
static void ReadOffered(int token) {
    uint64_t st = 0;
    BOOL offered = token && notify_get_state(token, &st) == NOTIFY_STATUS_OK && MSBDWindowKeysOfferedIn(st, getpid());
    gOffered = offered;
    gDefer = gOffered || gYoursWait;
    if (!gDefer) gTap.armed = false;
}
// One of your own shortcuts (Custom Shortcuts, KeyPilot's) starts with Globe + Option or Globe + Control (SpringBoard's state for the key tweaks,
// common/KeyboardChords.h): the chord waits for its release as with the window keys, so Globe-Option-J opens what it opens and the volume stays.
static void ReadYours(int token) {
    uint64_t st = 0;
    gYoursWait = token && notify_get_state(token, &st) == NOTIFY_STATUS_OK && (st & kMSBDKCYoursVolumeWaits);
    gDefer = gOffered || gYoursWait;
    if (!gDefer) gTap.armed = false;
}

@interface UIPhysicalKeyboardEvent : UIEvent
- (long long)_modifierFlags;
- (UIKeyModifierFlags)modifierFlags;
- (unsigned short)_keyCode;
@end
@interface SpringBoard : UIApplication
@end

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)changeVolumeBy:(float)delta forCategory:(NSString *)category;
@end

#define GLOBE_FLAG 0x800000
#define OPTION_KEYCODE 226
#define CONTROL_KEYCODE 224
#define VOLUME_STEP 0.0625


// The keys come as presses (-[SpringBoard pressesBegan:withEvent:], UIPress.key) on iPadOS 15 and 16 alike: the Globe key is bit 0x800000 of the
// key's modifier flags while it is held. The old path (-[UIApplication sendEvent:] with a UIPhysicalKeyboardEvent) only ever saw them on iPadOS 16:
// on the M1's iPadOS 15 SpringBoard received Globe + Option / Control only as presses, so the volume never moved (30 Sep; its debug log stayed empty).
static void DMGlobeVolumeStep(float step) { [[%c(AVSystemController) sharedAVSystemController] changeVolumeBy:step forCategory:@"Audio/Video"]; }
static BOOL DMGlobeVolumePress(UIPress *p) {
    UIKey *key = p.key;
    BOOL chord = key && ((unsigned long long)key.modifierFlags & GLOBE_FLAG) && (key.keyCode == OPTION_KEYCODE || key.keyCode == CONTROL_KEYCODE);
    // (Window Tiling Keys offered: the chord waits for its key's release, and any other key -- the arrow of Globe-Control-Left -- ends it: ModifierTap.h)
    // (the other chord key held too -- Globe-Control-Option -- told by this press's own flags: no tap of either, however often it is handed over)
    int tap = MSBDModTapDown(&gTap, key ? (int)key.keyCode : 0, chord, key && MSBDModTapOtherHeld((int)key.keyCode, (unsigned long long)key.modifierFlags), gDefer);
    if (!chord) return NO;
    if (tap == kMSBDModTapWait) {
#if DEBUG
        if (access("/tmp/macstatusbar-debug", F_OK) == 0) { FILE *f = fopen("/tmp/volumeglobe.log", "a"); if (f) { fprintf(f, "key %ld down (flags 0x%llx): waits for its release (Window Tiling Keys offered, or a shortcut of yours starts with it)\n", (long)key.keyCode, (unsigned long long)key.modifierFlags); fclose(f); } }
#endif
        return YES;
    }
    // Only a chord that acts now steps (the keys not offered: at its key's press, as in 1.8.2.2). The other chord key going down while one waits --
    // Option of Globe-Control-Option-Shift-Left, a window key's -- is no tap of either (ModifierTap.h: kMSBDModTapNothing): swallowed as the chord's
    // keys always are, the volume left alone (1.8.3 regression F1, iPad 2: each such arrangement raised the volume one step; BrightnessKey.x the same;
    // on the M1, where each press comes twice, the second Option is no tap either: ModifierTap.h, MSBDModTapOtherHeld).
    if (tap != kMSBDModTapActNow) {
#if DEBUG
        if (access("/tmp/macstatusbar-debug", F_OK) == 0) { FILE *f = fopen("/tmp/volumeglobe.log", "a"); if (f) { fprintf(f, "key %ld down (flags 0x%llx) with the other chord key held: no tap, no step\n", (long)key.keyCode, (unsigned long long)key.modifierFlags); fclose(f); } }
#endif
        return YES;
    }
    float step = key.keyCode == OPTION_KEYCODE ? VOLUME_STEP : -VOLUME_STEP;
    // Once per press: with an app in front SpringBoard is handed the same press twice (17.5.1, 24 Oct: one Globe + Option raised the volume two
    // steps, one Globe + Control lowered it two; with SpringBoard itself in front, once). The second delivery is swallowed, not acted on again.
    // Told by the press's time and key, never by the press object: UIKit hands the same object out again for a later press, and a second tap
    // was taken for the first one handed over again and dropped (iPad 2, 16.7.7, 1.8.3 device check: two taps, one step; the M1 got one step a
    // tap only because each press came twice there).
    static NSTimeInterval lastTime = -1;
    static long lastCode = -1;
    BOOL again = p.timestamp == lastTime && (long)key.keyCode == lastCode;
#if DEBUG
    if (access("/tmp/macstatusbar-debug", F_OK) == 0) { FILE *f = fopen("/tmp/volumeglobe.log", "a"); if (f) { fprintf(f, "volume %+.4f (key %ld, press %p at %.4f)%s\n", step, (long)key.keyCode, (__bridge void *)p, p.timestamp, again ? " -- the same press again: not acted on" : ""); fclose(f); } }
#endif
    if (again) return YES;
    lastTime = p.timestamp; lastCode = (long)key.keyCode;
    DMGlobeVolumeStep(step);
    return YES;
}
// A key came up: the chord that waited for it, now (once).
static void DMGlobeVolumeRelease(UIPress *p) {
    UIKey *key = p.key;
    if (!key || MSBDModTapUp(&gTap, (int)key.keyCode) != kMSBDModTapActOnRelease) return;
    float step = key.keyCode == OPTION_KEYCODE ? VOLUME_STEP : -VOLUME_STEP;
#if DEBUG
    if (access("/tmp/macstatusbar-debug", F_OK) == 0) { FILE *f = fopen("/tmp/volumeglobe.log", "a"); if (f) { fprintf(f, "volume %+.4f at key %ld's release (a tap)\n", step, (long)key.keyCode); fclose(f); } }
#endif
    DMGlobeVolumeStep(step);
}
%hook SpringBoard
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (gEnabled) {
        BOOL all = presses.count > 0;
        for (UIPress *p in presses) if (!DMGlobeVolumePress(p)) all = NO;
        if (all) return;   // (only Globe + Option / Control: swallowed, like before)
    }
    %orig;
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (gEnabled && gDefer) for (UIPress *p in presses) DMGlobeVolumeRelease(p);
    %orig;
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (gEnabled && gDefer) gTap.armed = false;
    %orig;
}
%end

%hook UIKeyShortcutHUDService

- (BOOL)_canSummonHUDWithModifierFlag:(unsigned long long)flag {
    // (only the Globe key's overlay is kept away: holding Command still shows the app's keyboard shortcuts -- 1.3.3, audit L-9: every modifier's
    //  overlay was refused while the switch was on)
    return (gEnabled && (flag & GLOBE_FLAG)) ? NO : %orig;
}

%end

%ctor {
    %init;
    ReadSwitch();
    static int token = 0, offeredToken = 0, usedToken = 0, yoursToken = 0;
    notify_register_dispatch(kPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) { ReadSwitch(); });
    if (notify_register_dispatch(kMSBDWindowKeysOfferedNote, &offeredToken, dispatch_get_main_queue(), ^(int t) { ReadOffered(t); }) == NOTIFY_STATUS_OK) ReadOffered(offeredToken);   // (the window keys offered or not)
    notify_register_dispatch(kMSBDModTapUsedNote, &usedToken, dispatch_get_main_queue(), ^(int t) { MSBDModTapUsed(&gTap); });   // (a window key ran: no tap)
    if (notify_register_dispatch(kMSBDKCYoursState, &yoursToken, dispatch_get_main_queue(), ^(int t) { ReadYours(t); }) == NOTIFY_STATUS_OK) ReadYours(yoursToken);   // (a shortcut of yours starts with the chord)
}
