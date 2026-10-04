// No large titles in Apple's own apps (Notes, Reminders, Mail, Calendar, Files, ...): the giant bold app-name header at the top of the list is not
// something a Mac app shows (its window already carries the app name, in our status bar's per-app menu). Turning this off leaves the ordinary compact
// title bar in its place, with the same buttons, the same back button, just without the oversized title row above them. Runs in every app; only Apple's
// own apps are touched, so a third-party app's own choice of look is left alone. The same idea as Mac Settings' own large "Settings" title being hidden.
#import <UIKit/UIKit.h>
#import <notify.h>

// Settings > Status Bar > Apple Apps > Hide Large Titles (on unless switched off: 1.3.3, audit L-1). The apps cannot read our preferences (sandbox),
// so SpringBoard reads the switch and publishes it as notify state "com.besiktasliseba.maclargetitles.state" (1 on, 2 off; 0, not published yet,
// counts as on, as before the switch existed). An app decides once, when it starts: switching it takes effect the next time an app opens.
#define LT_DOMAIN CFSTR("com.besiktasliseba.maclargetitles")
#define LT_STATE "com.besiktasliseba.maclargetitles.state"
static BOOL LTSwitchOn(void) {
    static int token = 0; uint64_t state = 0;
    if (!token && notify_register_check(LT_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
    if (token) notify_get_state(token, &state);
    return state != 2;
}
static void LTPublish(void) {   // (SpringBoard only)
    CFPreferencesAppSynchronize(LT_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), LT_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || CFGetTypeID(v) != CFBooleanGetTypeID() || CFBooleanGetValue(v);
    if (v) CFRelease(v);
    static int token = 0;
    if (!token && notify_register_check(LT_STATE, &token) != NOTIFY_STATUS_OK) token = 0;
    if (token) notify_set_state(token, on ? 1 : 2);
}

static BOOL DMIsStockApp(void) {
    static int cached = -1;
    if (cached < 0) {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier;
        // Notes builds its back button and toolbar into its own custom large-title view; forcing the large title off there loses the back button
        // entirely instead of shrinking to an ordinary bar, so it is left as it is (a fix waits until that can be worked around, not shipped broken).
        NSArray *exceptions = @[@"com.apple.mobilenotes"];
        cached = (bid.length && [bid hasPrefix:@"com.apple."] && ![bid isEqualToString:@"com.apple.springboard"] && ![exceptions containsObject:bid] && LTSwitchOn()) ? 1 : 0;
    }
    return cached;
}

// The translucent "scrolled past the top" backdrop (its own appearance, separate from the ordinary bar background) still showed up now and again in Settings
// even with the large title itself gone — a leftover blur bar with nothing above it to blur. Once the two appearances are the same, there is nothing left
// for the scroll position to change, so it never shows up unannounced.
static const void *kUnifiedAppearanceKey = &kUnifiedAppearanceKey;
%hook UINavigationBar
- (void)setPrefersLargeTitles:(BOOL)prefersLargeTitles {
    %orig(DMIsStockApp() ? NO : prefersLargeTitles);
}
- (void)layoutSubviews {
    %orig;
    if (!DMIsStockApp() || objc_getAssociatedObject(self, kUnifiedAppearanceKey)) return;
    if (![self respondsToSelector:@selector(standardAppearance)] || !self.standardAppearance) return;
    objc_setAssociatedObject(self, kUnifiedAppearanceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.scrollEdgeAppearance = self.standardAppearance;
    self.compactAppearance = self.standardAppearance;
}
%end

%hook UINavigationItem
- (void)setLargeTitleDisplayMode:(UINavigationItemLargeTitleDisplayMode)largeTitleDisplayMode {
    %orig(DMIsStockApp() ? UINavigationItemLargeTitleDisplayModeNever : largeTitleDisplayMode);
}
%end

%ctor {
    %init;
    if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {   // (publishes the switch for the apps)
        LTPublish();
        int token = 0;
        notify_register_dispatch("com.besiktasliseba.maclargetitles/prefsChanged", &token, dispatch_get_main_queue(), ^(int t) { LTPublish(); });
    }
}
