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
#import <objc/runtime.h>
#import "../common/OtherTweaks.h"

// Settings > Status Bar > Control Center > Hide Grabber (1.3.3, audit L-2): on unless switched off -- the line stays hidden for everyone who had it
// hidden before the switch existed. Read once and again after the switch posts its notification; switching it off shows the line again (the
// header view is kept and laid out again each time Control Center opens).
#define CCG_DOMAIN CFSTR("com.besiktasliseba.macccgrabber")
static int gCCGOn = -1;
static BOOL CCGEnabled(void) {
    if (gCCGOn >= 0) return gCCGOn;
    CFPreferencesAppSynchronize(CCG_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), CCG_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    BOOL on = !v || CFGetTypeID(v) != CFBooleanGetTypeID() || CFBooleanGetValue(v);   // default on (hidden)
    if (v) CFRelease(v);
    gCCGOn = on;
    return on;
}
static void CCGPrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef u) { gCCGOn = -1; }

@interface CCUIHeaderPocketView : UIView
@end

static const void *kCCGHiddenByUsKey = &kCCGHiddenByUsKey;
%hook CCUIHeaderPocketView
- (void)layoutSubviews {
    %orig;
    BOOL hide = CCGEnabled() && !MSBDOtherTweakDoing(kMSBDDupCCGrabber, YES);   // (Lynx hides it already: left to it)
    // _headerLineView is a plain private ivar (no public accessor was found on this class), read the same defensive way the rest of
    // this project reads undocumented OS object state (see Tweak.x's scroll-view search): valueForKey wrapped in a try/catch, never a
    // hard crash if a future OS version renames or removes it.
    @try {
        UIView *line = [self valueForKey:@"_headerLineView"];
        if (![line isKindOfClass:[UIView class]]) return;
        if (hide) { line.hidden = YES; objc_setAssociatedObject(line, kCCGHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        else if (objc_getAssociatedObject(line, kCCGHiddenByUsKey)) { line.hidden = NO; objc_setAssociatedObject(line, kCCGHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }   // (switched off: shown again)
    } @catch (NSException *e) {}
}
%end

%ctor {
    %init;
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCGPrefsChanged, CFSTR("com.besiktasliseba.macccgrabber/prefsChanged"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
