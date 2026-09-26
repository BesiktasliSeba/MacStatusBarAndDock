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

@interface AVSystemController : NSObject
+ (id)sharedAVSystemController;
- (BOOL)changeVolumeBy:(float)delta forCategory:(NSString *)category;
@end

#define GLOBE_FLAG 0x800000
#define OPTION_KEYCODE 226
#define CONTROL_KEYCODE 224
#define VOLUME_STEP 0.0625

static unsigned short lastKeyCode = 0;
static unsigned long long lastFlags = 0;

%hook UIApplication

- (void)sendEvent:(UIEvent *)event {
    if (gEnabled && [event isKindOfClass:%c(UIPhysicalKeyboardEvent)]) {
        UIPhysicalKeyboardEvent *kbEvent = (UIPhysicalKeyboardEvent *)event;
        unsigned long long flags = (unsigned long long)[kbEvent _modifierFlags];
        unsigned short keyCode = [kbEvent _keyCode];

        BOOL isDuplicate = (keyCode == lastKeyCode && flags == lastFlags);
        lastKeyCode = keyCode;
        lastFlags = flags;

        if (!isDuplicate && (flags & GLOBE_FLAG)) {
            AVSystemController *avc = [%c(AVSystemController) sharedAVSystemController];

            if (keyCode == OPTION_KEYCODE) {
                [avc changeVolumeBy:VOLUME_STEP forCategory:@"Audio/Video"];
                return; // swallow event, don't call %orig
            }
            if (keyCode == CONTROL_KEYCODE) {
                [avc changeVolumeBy:-VOLUME_STEP forCategory:@"Audio/Video"];
                return; // swallow event, don't call %orig
            }
        }
    }
    %orig;
}

%end

%hook UIKeyShortcutHUDService

- (BOOL)_canSummonHUDWithModifierFlag:(unsigned long long)flag {
    return gEnabled ? NO : %orig;
}

%end

%ctor {
    %init;
    ReadSwitch();
    static int token = 0;
    notify_register_dispatch(kPrefsChanged, &token, dispatch_get_main_queue(), ^(int t) { ReadSwitch(); });
}
