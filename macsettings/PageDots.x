// PageDots.x -- no page dots on the Home Screen (the row of small dots below the icons showing which page you're on) — macOS's own
// equivalent, Launchpad, has none either. Replicates Lynx's "hidePageDots" (on there, never changed).
// Settings > Dock > Home Screen switches it (2026-09-25; shown on new installs, updates keep it hidden; applies after a respring).
//
// SBIconListPageControl (found by a class-name search, then confirmed by its own ivar: a delegate typed <SBIconListPageControlDelegate>)
// is a SpringBoard-only subclass of the ordinary PUBLIC UIPageControl — not a private, undocumented class with its own unknown lifecycle
// (see tonight's SBFloatingDockBehaviorAssertion incident in the memory notes): this only hooks -layoutSubviews, a method the OS already
// calls naturally and repeatedly on an object IT created, to force it hidden after the fact. Nothing here is instantiated by us.
#import <UIKit/UIKit.h>
#import "../common/OtherTweaks.h"

#define PD_DOMAIN CFSTR("com.besiktasliseba.macpagedots")
static BOOL PDEnabled(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), PD_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;   // new installs show them (Settings > Dock > Show ...); an update keeps them hidden (sshtoggled --freeze-defaults)
    BOOL on = NO;   // (a boolean, or a number: an earlier Settings build stored the inverted switch as 0 / 1)
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    CFRelease(v);
    return on;
}

%hook SBIconListPageControl
- (void)layoutSubviews {
    %orig;
    if (PDEnabled() && !MSBDOtherTweakDoing(kMSBDDupPageDots, YES)) ((UIView *)self).hidden = YES;   // (Lynx hides them already: left to it)
}
%end

%ctor {
    %init;
}
