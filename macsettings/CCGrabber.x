// CCGrabber.x -- hides the small grabber/handle line in the top-right corner of Control Center's panel (a thin rounded-rect pill,
// visible while CC is open). Replicates Lynx's "hideCCGrabber" (the owner has it on; confirmed by reading Lynx.dylib itself, not guessed:
// its own Settings page names this exact switch "CC Grabber" with subtitle "Hide line in right corner", domain com.mtac.lynxtwo, pref
// key hideCCGrabber, default off in Lynx's own shipped defaults -- the owner has turned it on).
//
// CCUIHeaderPocketView (ControlCenterUIKit's own header chrome view for the CC panel -- holds a chevron, a sensor-privacy indicator,
// and, per its own ivar, a plain "_headerLineView" of type UIView, exactly the "line" Lynx's subtitle names) was found by a class-name
// search for "headerpocket" over SSH (MacStatusBar's classearch_ trigger), then confirmed real -- not guessed -- with methsearch_: it has
// an ordinary -layoutSubviews like any UIView subclass. This is a SpringBoard/ControlCenterUIKit-only UIView subclass, never a private
// class we alloc/init ourselves: this only hooks -layoutSubviews, a method the OS already calls repeatedly on an object IT created (same
// pattern as PageDots.x/SBIconListPageControl), to force the line hidden after the fact. The class was already registered in a
// completely fresh SpringBoard process checked before Control Center had ever been opened once this boot, so -- like
// SBIconListPageControl -- it is core CC chrome loaded at launch, not one of the lazily-loaded per-toggle CC module bundles (see
// EthernetFix.x for why that distinction matters), so hooking it by name directly is safe.
#import <UIKit/UIKit.h>
#import "../common/OtherTweaks.h"

// No Settings UI row yet (same as PageDots.x/IconLabels.x): default ON (hidden), matching Lynx's own switch as the owner currently has it
// set, not Lynx's shipped default (which ships off). Read live, not cached, in case a UI row and CFPreferencesSetValue calls are added later.
#define CCG_DOMAIN CFSTR("com.besiktasliseba.macccgrabber")
static BOOL CCGEnabled(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), CCG_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return YES;   // default on (hidden), matching the owner's current live Lynx setting
    BOOL on = CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : YES;
    CFRelease(v);
    return on;
}

@interface CCUIHeaderPocketView : UIView
@end

%hook CCUIHeaderPocketView
- (void)layoutSubviews {
    %orig;
    if (!CCGEnabled() || MSBDOtherTweakDoing(kMSBDDupCCGrabber, YES)) return;   // (Lynx hides it already: left to it)
    // _headerLineView is a plain private ivar (no public accessor was found on this class), read the same defensive way the rest of
    // this project reads undocumented OS object state (see Tweak.x's scroll-view search): valueForKey wrapped in a try/catch, never a
    // hard crash if a future OS version renames or removes it.
    @try {
        UIView *line = [self valueForKey:@"_headerLineView"];
        if ([line isKindOfClass:[UIView class]]) line.hidden = YES;
    } @catch (NSException *e) {}
}
%end

%ctor {
    %init;
}
