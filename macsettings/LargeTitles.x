// No large titles in Apple's own apps (Notes, Reminders, Mail, Calendar, Files, ...): the giant bold app-name header at the top of the list is not
// something a Mac app shows (its window already carries the app name, in our status bar's per-app menu). Turning this off leaves the ordinary compact
// title bar in its place, with the same buttons, the same back button, just without the oversized title row above them. Runs in every app; only Apple's
// own apps are touched, so a third-party app's own choice of look is left alone. The same idea as Mac Settings' own large "Settings" title being hidden.
#import <UIKit/UIKit.h>

static BOOL DMIsStockApp(void) {
    static int cached = -1;
    if (cached < 0) {
        NSString *bid = [NSBundle mainBundle].bundleIdentifier;
        // Notes builds its back button and toolbar into its own custom large-title view; forcing the large title off there loses the back button
        // entirely instead of shrinking to an ordinary bar, so it is left as it is (a fix waits until that can be worked around, not shipped broken).
        NSArray *exceptions = @[@"com.apple.mobilenotes"];
        cached = (bid.length && [bid hasPrefix:@"com.apple."] && ![bid isEqualToString:@"com.apple.springboard"] && ![exceptions containsObject:bid]) ? 1 : 0;
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
}
