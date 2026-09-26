// IconLabels.x -- no text labels under Home Screen icons, folders keep theirs. Replicates Lynx's "hideIconLabels".
// Settings > Dock > Home Screen switches it (2026-09-25; shown on new installs, updates keep it hidden; applies after a respring).
//
// SBIconLabelImageParametersBuilder builds the (text, iconLocation, font, ...) that get composited into the label's own rendered image
// (SBIconLabelImage, a UIImage subclass — the label is baked into a bitmap, not a separate view, presumably for Home Screen scroll
// performance) — confirmed by dumping its real methods, not guessed from ivar names alone. -buildParameters is hooked, not -setText:,
// because it runs last, after every property the caller set (in whatever order) is already in place — this DEBUG BUILD ONLY first logs
// what -iconLocation actually reads for a Home Screen icon vs. a folder's icon, since that string's exact value is not documented anywhere;
// the real conditional hide is added once that is confirmed on-device.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#if DEBUG
#define MSTestFlag(path) (access((path), F_OK) == 0)   // a /tmp test switch (debug builds only; a release build behaves as if none existed)
#else
#define MSTestFlag(path) 0
#endif
#import <unistd.h>
#import "../common/OtherTweaks.h"

// Each of these small sub-tweaks is its own separate dylib (a separate TWEAK_NAME target), so MLog from Tweak.x is not reachable here by a
// plain extern — this is its own copy, same pattern, same debug flag file and log as the rest of MacSettings.
#if DEBUG   // (only the DEBUG-only log below uses it: a release build would stop on an unused function)
static void MLog(NSString *line) {
    if (!MSTestFlag("/tmp/macsettings-debug")) return;
    FILE *f = fopen("/tmp/macsettings.log", "a"); if (!f) return;
    fprintf(f, "%s\n", line.UTF8String); fclose(f);
}
#endif

#define IL_DOMAIN CFSTR("com.besiktasliseba.maciconlabels")
static BOOL ILEnabled(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("enabled"), IL_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) return NO;   // new installs show them (Settings > Dock > Show ...); an update keeps them hidden (sshtoggled --freeze-defaults)
    BOOL on = NO;   // (a boolean, or a number: an earlier Settings build stored the inverted switch as 0 / 1)
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) on = CFBooleanGetValue(v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); on = n != 0; }
    CFRelease(v);
    return on;
}

@interface SBIconLabelImageParametersBuilder : NSObject
- (NSString *)text;
- (void)setText:(NSString *)text;
- (id)iconLocation;
@end
@interface NSObject (ILIconView)
- (long long)currentLabelAccessoryType;
- (id)location;
- (id)icon;
- (BOOL)isFolderIcon;
@end

// -buildParameters (not -setText:) is hooked deliberately: it runs last, after every property the caller set — in whatever order — is
// already in place, so clearing the text here can never race a caller that sets iconLocation after text.
%hook SBIconLabelImageParametersBuilder
- (id)buildParameters {
    id location = [self iconLocation];
#if DEBUG
    static int logged = 0;
    if (logged < 200) { logged++; MLog([NSString stringWithFormat:@"[iconlabels] location=%@ text=\"%@\"", location, [self text]]); }
#endif
    // SBIconLocationAppLibrary confirmed live (App Library's own category labels went through here); SBIconLocationHomeScreen is the
    // same naming pattern, not yet independently confirmed (real Home Screen icon labels are cached from boot and never rebuilt during
    // ordinary testing) — low risk either way: a wrong guess just leaves labels showing, same as the feature being off.
    // iPadOS 15 names the Home Screen pages "SBIconLocationRoot" (M1 log, 2026-09-25: every Home Screen label came through as Root), so both.
    if (ILEnabled() && !MSBDOtherTweakDoing(kMSBDDupIconLabels, YES) && [location isKindOfClass:[NSString class]]
        && ([(NSString *)location isEqualToString:@"SBIconLocationHomeScreen"] || [(NSString *)location isEqualToString:@"SBIconLocationRoot"])) {
        [self setText:@""];
    }
    return %orig;
}
%end

// With the names gone, iOS still drew the label's accessory dot (orange = beta / TestFlight-style app, blue = recently updated) on its own,
// left of the icon's middle where the name used to start (M1, 2026-09-26: an orange dot under a sideloaded emulator's icon; iconinfo_ showed
// SBIconBetaLabelAccessoryView), which looked like a stray dot. So it goes with the names: the accessory type reads as none (Home Screen
// icons only; folders keep their labels and anything they show).
%group ILAccessory
%hook SBIconView
- (long long)currentLabelAccessoryType {   // (0 = none; -shouldShowLabelAccessoryView alone is not consulted when the dot is set up)
    if (!ILEnabled() || MSBDOtherTweakDoing(kMSBDDupIconLabels, YES)) return %orig;
    id me = self;
    id location = [me respondsToSelector:@selector(location)] ? [me valueForKey:@"location"] : nil;
    if (![location isKindOfClass:[NSString class]] || !([(NSString *)location isEqualToString:@"SBIconLocationHomeScreen"] || [(NSString *)location isEqualToString:@"SBIconLocationRoot"])) return %orig;
    id icon = [me respondsToSelector:@selector(icon)] ? [me valueForKey:@"icon"] : nil;
    if ([icon respondsToSelector:@selector(isFolderIcon)] && ((BOOL (*)(id, SEL))objc_msgSend)(icon, @selector(isFolderIcon))) return %orig;
    return 0;
}
%end
%end

%ctor {
    %init;
    Class iv = objc_getClass("SBIconView");
    Method m = iv ? class_getInstanceMethod(iv, @selector(currentLabelAccessoryType)) : NULL;
    char ret[8] = {0}; if (m) method_getReturnType(m, ret, sizeof(ret));
    if (m && ret[0] == 'q' && class_getInstanceMethod(iv, @selector(location)) && class_getInstanceMethod(iv, @selector(icon))) %init(ILAccessory);
}
