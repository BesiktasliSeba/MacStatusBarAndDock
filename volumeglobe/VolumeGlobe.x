#include <unistd.h>
#include <stdio.h>
// VolumeGlobeTweak (SpringBoard) -- Globe + Option raises and Globe + Control lowers the volume, and the Globe key's shortcut overlay is kept from
// appearing while it is held. The Settings switch (Settings > Keyboard, shown while a hardware keyboard is attached) is off for a new install.
#import <UIKit/UIKit.h>
#include <notify.h>

#define kPrefsChanged "com.besiktasliseba.volumeglobetweak/prefsChanged"   // posted by the Settings switch
#define kPrefsDomain  CFSTR("com.besiktasliseba.volumeglobetweak")
static BOOL gEnabled = NO;
static void ReadSwitch(void) {
    CFPreferencesAppSynchronize(kPrefsDomain);
    BOOL enabled = NO;   // off until switched on
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), kPrefsDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(v); CFRelease(v); }
    gEnabled = enabled;
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
static BOOL DMGlobeVolumePress(UIPress *p) {
    UIKey *key = p.key;
    if (!key || !((unsigned long long)key.modifierFlags & GLOBE_FLAG)) return NO;
    float step = 0;
    if (key.keyCode == OPTION_KEYCODE) step = VOLUME_STEP;
    else if (key.keyCode == CONTROL_KEYCODE) step = -VOLUME_STEP;
    else return NO;
    [[%c(AVSystemController) sharedAVSystemController] changeVolumeBy:step forCategory:@"Audio/Video"];
#if DEBUG
    if (access("/tmp/macstatusbar-debug", F_OK) == 0) { FILE *f = fopen("/tmp/volumeglobe.log", "a"); if (f) { fprintf(f, "volume %+.4f (key %ld)\n", step, (long)key.keyCode); fclose(f); } }
#endif
    return YES;
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
    static int token = 0;
    notify_register_dispatch(kPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) { ReadSwitch(); });
}
