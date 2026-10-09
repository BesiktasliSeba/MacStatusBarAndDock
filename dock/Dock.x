// DockMagnification -- icons under the cursor grow, macOS style.
//
// Smoothness: the pointer only reports its position in discrete events, so writing the scales straight from those
// events makes them step. Instead the events only update a TARGET (where the cursor is, and whether it is over the
// dock), and a CADisplayLink moves the icons toward it on every screen frame with exponential smoothing: the focus
// point follows the cursor with a short lag, and the whole effect eases in when the cursor arrives and out when it
// leaves. The smoothing is frame-rate independent (it uses the real time between frames).
//
// Findings from the probe (see probe-findings/): dock icons live in
// SBFloatingDockIconListView / SBDockSuggestionsIconListView, both inside a
// single SBFloatingDockPlatterView, so the hover recognizer goes on the platter.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdio.h>
#import <unistd.h>
#import <sys/stat.h>
#import <notify.h>

// The Dock's layout numbers, as SBFloatingDockView fills them in -[getMetrics:forBounds:] (found by dumping it on the device):
// frames inside the platter for the user icons, the recents, the App Library icon and the divider, the platter itself in
// window coordinates, the icon content scale and the spacing between icons.
typedef struct {
    CGRect userList; UIEdgeInsets padding; CGRect recentsList; CGRect libraryIcon; CGRect divider; CGRect platter;
    double iconScale; double spacing;
} DMDockMetrics;

@interface UIWindow (DMPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)internal onlyVisibleWindows:(BOOL)visible;
@end

// ===== tunables ==========================================================
static const CGFloat kRange = 180.0; // px of influence either side of the cursor
static const CGFloat kFocusTau = 0.035;   // s: how quickly the focus point follows the cursor (smaller = tighter)
static const CGFloat kInTau    = 0.070;   // s: ease-in when the cursor arrives over the dock
static const CGFloat kOutTau   = 0.130;   // s: ease-out when it leaves

// ===== preferences (set in Settings > DockMagnification) ==================
#define DM_DOMAIN CFSTR("com.besiktasliseba.dockmagnification")
#define DM_NOTIFY CFSTR("com.besiktasliseba.dockmagnification/prefsChanged")
// Separate domain for the swipe-down-opens-App-Library feature (our own replacement for Lynx's "replace Spotlight"):
// kept apart from DM_DOMAIN since it is a standalone feature, not a Dock setting.
#define DM_SPOTLIGHT_DOMAIN CFSTR("com.besiktasliseba.macspotlightreplace")
static BOOL    gEnabled       = YES;
static CGFloat gMagnification = 1.22;   // scale of the icon at the cursor
static CGFloat gIconSize = 0.85;        // multiplier on the Dock's own icon size (1.0 = as the system/other tweaks set it)
static CGFloat gBottomGap = 6.0;        // points between the Dock and the bottom screen edge (stock is 20.5)
static BOOL    gTweakOn = YES;          // the Dock part's own switch (Settings > Dock Magnification): off = the Dock exactly as iPadOS draws it
static BOOL    gShowDownloads = YES;    // the Downloads stack in the Dock
static BOOL    gShowFinder = YES;       // Finder as the Dock's first item, like a Mac (FinderIcon.m)
static BOOL    gEscapeClosesLibrary = YES;   // pressing Escape closes the App Library
static BOOL    gLaunchpadIcon = YES;    // the App Library icon drawn like macOS Launchpad
static BOOL    gLaunchpadClassic = YES; // round rocket (YES) or the silver grid tile (NO)
static BOOL    gLaunchpadLeft = YES;    // Launchpad at the Dock's start, next to Finder, like macOS (default on for everyone, owner 2 Oct; off: at the end, as iPadOS puts the App Library)
static BOOL    gBlockSwipeUp  = YES;    // stop an upward swipe on the Home Screen from opening the App Library
static BOOL    gPortraitLarger = YES;   // in portrait the (shrunk) Dock grows to the widest size that fits the screen
static BOOL    gSwipeDownOpensLibrary = YES;   // a downward swipe on the Home Screen opens the App Library (our own replacement for Lynx's "replace Spotlight")

// ===== logging (no system log on this setup) ==============================
#import "DMLog.h"
#include "../common/Diag.h"
#define DM_FEATURE_MARK(name) do { static const char *const dmFeatureMark = "msbd-feature:" name; __asm__ volatile("" :: "r"(dmFeatureMark)); } while (0)   // (release-build feature marker, see statusbar/StatusBar.x)
#if DEBUG
void DMLogWrite(NSString *line) {
    FILE *f = fopen("/tmp/dockmag.log", "a");
    if (!f) return;
    fprintf(f, "%s\n", [line UTF8String]);
    fclose(f);
}
#endif

static CGFloat gInfluence = 0.0;     // 0...1: how much of the magnification is applied right now
#if DEBUG
static CFTimeInterval gDMMetricsLogUntil = 0;   // (debug, K-2: every -getMetrics:forBounds: call is logged until then -- "metricslog" in /tmp/dockmag-escape)
static BOOL gDMStockMetricsOnly = NO;           // (debug, K-2 "k2" dump: one -getMetrics:forBounds: call with SpringBoard's own numbers, none of ours)
#endif

// ===== curves ============================================================
static CGFloat DMBell(CGFloat offset) {
    if (fabs(offset) >= kRange) return 0.0;
    return 0.5 * (cos(M_PI * offset / kRange) + 1.0);
}
static CGFloat DMScale(CGFloat offset) { return 1.0 + (gMagnification - 1.0) * DMBell(offset) * gInfluence; }

// ===== state =============================================================
static CGFloat gFocusX = 0.0;        // where the cursor is (target)
static CGFloat gSmoothX = 0.0;       // where the icons are centred on right now
static BOOL gHovering = NO;
static CADisplayLink *gLink = nil;
static CFTimeInterval gLastTimestamp = 0.0;
static NSArray *gIcons = nil;        // dock icons, cached for the current hover
static NSInteger gFramesSinceRefresh = 0;
static NSInteger gStatFrames = 0;    // debug statistics for one hover
static CGFloat gStatMaxJump = 0.0, gStatLastScale = 1.0;
static BOOL gApplying = NO;          // true while our own code writes transforms
static const void *kHoverKey = &kHoverKey;
static __weak UIView *gLinkPlatter = nil;   // the platter whose link runs (or ran last): restarted from the icon transform hook below

// Strict lookup of only our own domain. CFPreferencesCopyAppValue also walks the
// global search list and can return an unrelated value for a generic key like
// "enabled" (it returned a stray 0 on this device).
static CFPropertyListRef DMCopyPref(CFStringRef key) {
    return CFPreferencesCopyValue(key, DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}
// Same pattern, but for the separate swipe-down-opens-App-Library domain.
static CFPropertyListRef DMCopySpotlightPref(CFStringRef key) {
    return CFPreferencesCopyValue(key, DM_SPOTLIGHT_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static void DMLoadPrefs(void) {
    CFPreferencesAppSynchronize(DM_DOMAIN);
    CFPreferencesAppSynchronize(DM_SPOTLIGHT_DOMAIN);

    // Settings > Dock Magnification (the separate, minimal entry, alongside the other installed tweaks' own on/off switches): off puts the Dock back to
    // exactly how iPadOS draws it on its own — no magnification, stock icon size, no portrait widening — read live, so it takes effect right away.
    BOOL tweakOn = YES;
    CFPropertyListRef t = DMCopyPref(CFSTR("tweakEnabled"));
    if (t) { if (CFGetTypeID(t) == CFBooleanGetTypeID()) tweakOn = CFBooleanGetValue(t); CFRelease(t); }

    BOOL enabled = YES;
    CFPropertyListRef e = DMCopyPref(CFSTR("enabled"));
    if (e) {
        if (CFGetTypeID(e) == CFBooleanGetTypeID()) enabled = CFBooleanGetValue(e);
        CFRelease(e);
    }
    enabled = enabled && tweakOn;
    gTweakOn = tweakOn;

    CGFloat mag = 1.22;
    CFPropertyListRef m = DMCopyPref(CFSTR("magnification"));
    if (m) {
        if (CFGetTypeID(m) == CFNumberGetTypeID()) {
            double d = 0;
            if (CFNumberGetValue(m, kCFNumberDoubleType, &d)) mag = d;
        }
        CFRelease(m);
    }
    if (mag < 1.0) mag = 1.0;   // never shrink icons
    if (mag > 3.0) mag = 3.0;   // guard against a corrupt value

    gEnabled = enabled;
    gMagnification = mag;

    CGFloat size = 0.85;
    CFPropertyListRef s = DMCopyPref(CFSTR("dockIconSize"));
    if (s) {
        if (CFGetTypeID(s) == CFNumberGetTypeID()) { double d = 0; if (CFNumberGetValue(s, kCFNumberDoubleType, &d)) size = d; }
        CFRelease(s);
    }
    gIconSize = tweakOn ? MIN(1.5, MAX(0.4, size)) : 1.0;
    BOOL portraitLarger = YES;
    CFPropertyListRef pl = DMCopyPref(CFSTR("portraitLargerDock"));
    if (pl) { if (CFGetTypeID(pl) == CFBooleanGetTypeID()) portraitLarger = CFBooleanGetValue(pl); CFRelease(pl); }
    gPortraitLarger = portraitLarger && tweakOn;
    CGFloat gap = 6.0;
    CFPropertyListRef g = DMCopyPref(CFSTR("dockBottomGap"));
    if (g) {
        if (CFGetTypeID(g) == CFNumberGetTypeID()) { double d = 0; if (CFNumberGetValue(g, kCFNumberDoubleType, &d)) gap = d; }
        CFRelease(g);
    }
    gBottomGap = MIN(40.0, MAX(0.0, gap));
    BOOL blockUp = YES;
    CFPropertyListRef u = DMCopyPref(CFSTR("blockSwipeUpLibrary"));
    if (u) {
        if (CFGetTypeID(u) == CFBooleanGetTypeID()) blockUp = CFBooleanGetValue(u);
        CFRelease(u);
    }
    gBlockSwipeUp = blockUp;
    BOOL downloads = YES;
    CFPropertyListRef dl = DMCopyPref(CFSTR("showDownloads"));
    if (dl) {
        if (CFGetTypeID(dl) == CFBooleanGetTypeID()) downloads = CFBooleanGetValue(dl);
        CFRelease(dl);
    }
    gShowDownloads = downloads;
    BOOL finder = YES;
    CFPropertyListRef fi = DMCopyPref(CFSTR("showFinder"));
    if (fi) { if (CFGetTypeID(fi) == CFBooleanGetTypeID()) finder = CFBooleanGetValue(fi); CFRelease(fi); }
    {   // (Finder itself lives in Mac Status Bar: no icon while Finder is switched off there, Mac Status Bar is off, or the stock status bar runs --
        //  the icon did nothing then, review M8)
        CFStringRef msb = CFSTR("com.besiktasliseba.macstatusbar");
        CFPreferencesAppSynchronize(msb);
        const CFStringRef keys[] = { CFSTR("finderEnabled"), CFSTR("tweakEnabled"), CFSTR("stockStatusBar") };
        const BOOL want[] = { YES, YES, NO }, dflt[] = { YES, YES, NO };
        for (int k = 0; k < 3; k++) {
            CFPropertyListRef v = CFPreferencesCopyValue(keys[k], msb, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
            BOOL b = dflt[k];
            if (v) { if (CFGetTypeID(v) == CFBooleanGetTypeID()) b = CFBooleanGetValue(v); CFRelease(v); }
            if (b != want[k]) finder = NO;
        }
    }
    gShowFinder = finder;
    BOOL launchpad = YES;
    CFPropertyListRef lp = DMCopyPref(CFSTR("launchpadIcon"));
    if (lp) {
        if (CFGetTypeID(lp) == CFBooleanGetTypeID()) launchpad = CFBooleanGetValue(lp);
        CFRelease(lp);
    }
    gLaunchpadIcon = launchpad;
    {
        CFPropertyListRef ll = DMCopyPref(CFSTR("launchpadLeft"));
        gLaunchpadLeft = !(ll && CFGetTypeID(ll) == CFBooleanGetTypeID()) || CFBooleanGetValue(ll);   // (not set yet: on, new installs and updates alike)
        if (ll) CFRelease(ll);
    }
    BOOL escapeCloses = YES;
    CFPropertyListRef es = DMCopyPref(CFSTR("escapeClosesLibrary"));
    if (es) {
        if (CFGetTypeID(es) == CFBooleanGetTypeID()) escapeCloses = CFBooleanGetValue(es);
        CFRelease(es);
    }
    gEscapeClosesLibrary = escapeCloses;
    CFPropertyListRef ls = DMCopyPref(CFSTR("launchpadStyle"));
    NSString *style = ls ? CFBridgingRelease(ls) : nil;
    gLaunchpadClassic = ![style isEqual:@"grid"];

    // Swipe down opens the App Library: its own domain (DM_SPOTLIGHT_DOMAIN), default ON to match Lynx's
    // currently-live "replace Spotlight" setting.
    BOOL swipeDown = YES;
    CFPropertyListRef sd = DMCopySpotlightPref(CFSTR("enabled"));
    if (sd) {
        if (CFGetTypeID(sd) == CFBooleanGetTypeID()) swipeDown = CFBooleanGetValue(sd);
        CFRelease(sd);
    }
    gSwipeDownOpensLibrary = swipeDown;

    DMLog([NSString stringWithFormat:@"[prefs] enabled=%d magnification=%.3f iconSize=%.2f bottomGap=%.1f blockSwipeUp=%d downloads=%d launchpad=%d swipeDownOpensLibrary=%d", enabled, mag, gIconSize, gBottomGap, blockUp, downloads, launchpad, swipeDown]);
}

@interface SBFloatingDockView : UIView
- (void)setIconContentScale:(CGFloat)scale;
- (CGFloat)iconContentScale;
- (void)getMetrics:(DMDockMetrics *)metrics forBounds:(CGRect)bounds;
@end

// The Dock's size and distance from the screen edge come from SBFloatingDockView's own layout numbers, so changing those
// (rather than scaling icon views) keeps the platter, spacing and hit areas consistent, and the hover magnification is
// unaffected (it only adds transforms on top).
static CGRect gDownloadsSlot = {{0, 0}, {0, 0}};   // where the Downloads icon goes, in the platter's coordinates (set by getMetrics)
static CGRect gFinderSlot = {{0, 0}, {0, 0}};      // where the Finder icon goes: the Dock's first place (set by getMetrics)
extern void DMFinderIconAttach(UIView *platter, CGRect slot, BOOL show);
extern UIView *DMFinderIcon(UIView *platter);
extern CGFloat gDMIconCornerRatio;   // (FinderIcon.m: SpringBoard's app icon corner as a share of the icon's width)
// SpringBoard's app icon corner for the Dock (K-4): -[SBFloatingDockView _iconImageInfo] (15-18: {size, scale, continuous corner radius}) -- the
// Finder picture's corners follow it. Read only when the method returns exactly that structure.
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } DMIconImageInfo;
static void DMReadIconCornerRatio(UIView *dockView) {
    SEL sel = NSSelectorFromString(@"_iconImageInfo");
    Method m = class_getInstanceMethod(object_getClass(dockView), sel);
    if (!m || method_getNumberOfArguments(m) != 2) return;
    char t[128] = {0}; method_getReturnType(m, t, sizeof(t));
    static BOOL told = NO;
    if (!told) { told = YES; DMLog([NSString stringWithFormat:@"[finder] the Dock's icon image info returns %s", t]); }
    if (strcmp(t, "{SBIconImageInfo={CGSize=dd}dd}") != 0) return;
    DMIconImageInfo i = ((DMIconImageInfo (*)(id, SEL))objc_msgSend)(dockView, sel);
    if (isfinite(i.size.width) && i.size.width >= 8.0 && isfinite(i.continuousCornerRadius) && i.continuousCornerRadius > 0.0 && i.continuousCornerRadius < i.size.width / 2.0)
        gDMIconCornerRatio = i.continuousCornerRadius / i.size.width;
}
extern void DMDownloadsAttach(UIView *platter, CGRect slot, BOOL show);
extern UIView *DMDownloadsIcon(UIView *platter);

// A second divider between the recent apps and the Downloads stack, like macOS has before its Downloads/Trash end (2026-09-25). getMetrics makes
// room for it (the same gap the Dock keeps around its own divider: one icon spacing on each side of a 1 pt line) and sets its place here; it is
// drawn as a copy of SpringBoard's own divider view (same colour, blending, alpha and height, re-copied at every layout and style update). It
// only exists with Downloads on. With no recents the Dock hides its own line, and ours is then the only line (apps | Downloads, as on macOS):
// there are never two lines side by side.
static CGRect gDivider2Rect = {{0, 0}, {0, 0}};   // in the platter's coordinates, or zero for none (set by getMetrics)
static BOOL gDivider2Alone = NO;   // no recents: the Dock's own line is hidden and ours is the only one
static const void *kDivider2Key = &kDivider2Key;
static UIView *DMNativeDivider(UIView *dockView) {
    UIView *d = nil;
    @try { d = [dockView valueForKey:@"dividerView"]; } @catch (id e) {}   // (KVC on a private class: guarded)
    return [d isKindOfClass:[UIView class]] ? d : nil;
}
static void DMCopyDividerLook(UIView *from, UIView *to) {
    to.backgroundColor = from.backgroundColor;
    to.alpha = from.alpha;
    to.layer.cornerRadius = from.layer.cornerRadius;
    to.layer.filters = from.layer.filters;
    @try { [to.layer setValue:[from.layer valueForKey:@"compositingFilter"] forKey:@"compositingFilter"]; } @catch (id e) {}
    to.overrideUserInterfaceStyle = from.overrideUserInterfaceStyle;
}
static void DMSecondDividerAttach(UIView *dockView) {
    UIView *native = DMNativeDivider(dockView);
    UIView *mine = objc_getAssociatedObject(dockView, kDivider2Key);
    BOOL want = native.superview && gShowDownloads && gDivider2Rect.size.height > 1.0 && (gDivider2Alone || !native.hidden);
    if (!want) { mine.hidden = YES; return; }
    if (!mine) {
        mine = [[UIView alloc] initWithFrame:gDivider2Rect];
        mine.userInteractionEnabled = NO;
        objc_setAssociatedObject(dockView, kDivider2Key, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (mine.superview != native.superview) [native.superview insertSubview:mine aboveSubview:native];
    DMCopyDividerLook(native, mine);
    if (gDivider2Alone && mine.alpha < 0.01) mine.alpha = 1.0;   // (the Dock's own line is hidden then; its colour and blending still apply)
    mine.hidden = NO;
    mine.transform = native.transform;
    mine.frame = CGRectMake(gDivider2Rect.origin.x, native.frame.origin.y, native.frame.size.width, native.frame.size.height);   // (the height, top and width of the Dock's own)
    static CGRect logged; static CGFloat loggedNative = -1;
    if (!CGRectEqualToRect(logged, mine.frame) || fabs(loggedNative - native.frame.origin.x) > 0.01) {
        logged = mine.frame; loggedNative = native.frame.origin.x;
        DMLog([NSString stringWithFormat:@"[divider2] at %@ (the Dock's own at %@, bg %@, filter %@)", NSStringFromCGRect(mine.frame), NSStringFromCGRect(native.frame), native.backgroundColor, [native.layer valueForKey:@"compositingFilter"]]);
    }
}

// Set while something of ours (currently: the Downloads panel) needs the Dock kept visible on purpose, the same idea as what a Haptic
// Touch menu on a Dock icon gets natively — but done here at the view level instead of through SBFloatingDockController's private
// SBFloatingDockBehaviorAssertion class: probing that class's real lifecycle crashed SpringBoard once already tonight (creating and
// discarding an unregistered instance corrupted memory on dealloc — see the incident note in the ipad-tweak-dev-setup memory), and this
// needs no object lifecycle at all, just ignoring the Dock's own attempts to hide/fade itself while the flag is set — the same category of
// change (overriding a setter on a view we already safely hook elsewhere in this file) as everything else here, not a new kind of risk.
BOOL gKeepDockVisible = NO;
extern void DMDownloadsTouchBegan(UIView *view);
// With a trackpad or mouse, SpringBoard puts the Dock away as soon as the pointer leaves it (its "dismiss floating dock" hover gesture). While the
// Downloads panel is open that took the Dock -- and with it the panel (they are one unit) -- away the moment the pointer moved off the Downloads
// icon onto the panel (M1, 0.3.18-10). While the panel is open (gKeepDockVisible) that one hover dismissal is ignored; the Dock still leaves
// for everything else (the App Switcher, the Lock Screen, an app, a swipe), and the panel with it.
@interface SBFloatingDockController : NSObject
- (UIGestureRecognizer *)dismissFloatingDockSystemGestureRecognizer;
@end
BOOL gDockHoverDismissBlocked = NO;   // (a hover dismissal was ignored while the panel was open: done once the panel closes, see Downloads.m)
BOOL DMDockPointerHovering(void) { return gHovering; }
%hook SBFloatingDockController
// A finger on the screen outside the Dock (over a full-screen app) makes SpringBoard put the Dock away through its system "dismiss floating dock"
// gesture -- a finger scroll inside the open Downloads panel counted as that, and the Dock left with the panel (M1 regression pass, 0.3.18-14). While
// the panel is open, that gesture may not begin for a touch inside the panel; a touch anywhere else still puts the Dock (and the panel) away.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    extern BOOL DMDownloadsPanelContainsTouch(UITouch *touch);
    if (gKeepDockVisible && [self respondsToSelector:@selector(dismissFloatingDockSystemGestureRecognizer)]
        && g == ((id (*)(id, SEL))objc_msgSend)(self, @selector(dismissFloatingDockSystemGestureRecognizer)) && DMDownloadsPanelContainsTouch(touch)) return NO;
    return %orig;
}
- (void)_handleDismissFloatingDockHoverGesture:(id)gesture {
    if (gKeepDockVisible) { gDockHoverDismissBlocked = YES; static int told = 0; if (told++ < 50) DMLog(@"[downloads] the pointer left the Dock while the panel is open: the Dock stays"); return; }
    %orig;
}
%end
// With windows on the screen (Stage Manager), a tap brings the window under it forward (SpringBoard's "tap to bring item container forward"
// system gesture, SBFluidSwitcherGestureManager). It knows nothing of the Downloads panel above the Dock: a tap on the panel's search field
// brought the window under the field forward (iPad 2, iOS 16, 30 Sep), so the wrong app got the keyboard back after the search. The panel is
// part of the Dock, where that gesture never starts: a touch on it -- or on the on-screen keyboard while its search is typed in -- is left out.
%group DMPanelNoBringForward   // (only where SpringBoard has this method: see %ctor)
%hook SBFluidSwitcherGestureManager
- (BOOL)_shouldTapToBringItemContainerForward:(UIGestureRecognizer *)g receiveTouch:(UITouch *)touch {
    extern BOOL DMDownloadsPanelContainsTouch(UITouch *touch);
    if (gKeepDockVisible && DMDownloadsPanelContainsTouch(touch)) return NO;
    return %orig;
}
%end
%end
// Show App Library in Dock off (Settings > Home Screen & Multitasking): iOS still hands out the App Library icon's spot in the layout numbers, 0 wide
// but as tall as the Dock's icons and level with them (iPadOS 16.7.7: library {784, 11, 0 x 39} with the lists 61 tall; 17.6.1 the same; 17.0: lists
// 83 pt for 53 pt icons). That height is then the Dock's icon size, or 0 when it does not look like one (as tall as the lists: the platter's). Every
// version (1.3.3, audit M-2: before, only 17+ was measured, and 15/16 sized Finder from the list height -- a Finder icon bigger than the apps -- and
// widened the Dock for a Downloads stack that never showed: an empty tail and a stray second divider at the end).
static CGFloat DMDockHiddenLibrarySide(const DMDockMetrics *m) {
    if (m->libraryIcon.size.width >= 1.0) return 0.0;
    CGFloat h = m->libraryIcon.size.height;
    return isfinite(h) && h >= 8.0 && h < m->userList.size.height - 1.0 ? h : 0.0;
}
static BOOL gDownloadsOwnSlot;   // (the last layout gave Downloads a slot of its own -- no App Library icon in the Dock; for the diagnostics)
// K-2 (iPad mini 4, 15.8.8: app icons outside the Dock): the platter and the lists' frames, spacing and content scale all come from one
// -getMetrics:forBounds: answer, worked out for the icon counts the Dock's lists had at that moment; each list places its own icons for the count
// it has. SpringBoard keeps both on the same count through its Dock controller (a list change -> a coalesced resize -> the Dock view's layout).
// The counts are read here exactly as SpringBoard's -getMetrics:forBounds: reads them (15/16: the list's model; 17+: its displayed model; the
// user list never fewer than -minimumUserIconSpaces, which a drag over the Dock raises to make room), recorded per Dock view for the layout's own
// bounds, and checked again whenever a Dock list has just placed its icons (DMDockCheckSizedFor below).
static const void *kDMDockSizedForKey = &kDMDockSizedForKey;   // @[user count, recents count] the platter of that Dock view was last sized for
static __unsafe_unretained UIView *gDMDockInLayout = nil;   // the Dock view whose own -layoutSubviews is running: only the answer asked there sizes the
                                                            // platter (SpringBoard also asks for -contentHeight, e.g. inside its resize, before laying out)
static NSUInteger DMDockListCount(UIView *list) {
    if (![list isKindOfClass:[UIView class]]) return 0;
    id model = nil;
    @try { model = [list respondsToSelector:NSSelectorFromString(@"displayedModel")] ? [list valueForKey:@"displayedModel"] : [list valueForKey:@"model"]; } @catch (id e) { model = nil; }
    SEL n = NSSelectorFromString(@"numberOfIcons");
    return [model respondsToSelector:n] ? ((NSUInteger (*)(id, SEL))objc_msgSend)(model, n) : 0;
}
static BOOL DMDockIconCounts(UIView *dockView, NSUInteger *user, NSUInteger *recents) {
    UIView *u = nil, *r = nil;
    @try { u = [dockView valueForKey:@"userIconListView"]; r = [dockView valueForKey:@"recentIconListView"]; } @catch (id e) { return NO; }   // (KVC on a private class: guarded)
    NSUInteger uc = DMDockListCount(u);
    SEL minSel = NSSelectorFromString(@"minimumUserIconSpaces");
    if ([dockView respondsToSelector:minSel]) uc = MAX(uc, ((NSUInteger (*)(id, SEL))objc_msgSend)(dockView, minSel));
    if (user) *user = uc;
    if (recents) *recents = DMDockListCount(r);
    return YES;
}
// Right-to-left languages (1.3.3): iPadOS mirrors the Dock -- the apps from the right end, the recents and the App Library icon at the left -- and so
// does macOS (Finder at the right end, Downloads at the left). Our layout below is worked out left-to-right: the Dock's numbers are mirrored inside the
// platter first, and the result (with our slots) is mirrored back at the end. The rects are in the platter's own coordinates.
static CGRect DMDockMirrorRect(CGRect r, CGFloat w) { if (!CGRectIsEmpty(r) || r.size.height > 0.0) r.origin.x = w - r.origin.x - r.size.width; return r; }
static void DMDockMirrorMetrics(DMDockMetrics *m) {
    CGFloat w = m->platter.size.width;
    m->userList = DMDockMirrorRect(m->userList, w); m->recentsList = DMDockMirrorRect(m->recentsList, w);
    m->libraryIcon = DMDockMirrorRect(m->libraryIcon, w); m->divider = DMDockMirrorRect(m->divider, w);
    CGFloat l = m->padding.left; m->padding.left = m->padding.right; m->padding.right = l;
}
%hook SBFloatingDockView
- (void)layoutSubviews {
    UIView *outerLayout = gDMDockInLayout;
    gDMDockInLayout = (UIView *)self;   // (K-2: the counts recorded by the answer SpringBoard asks for in this layout are the platter's)
    %orig;
    gDMDockInLayout = outerLayout;
    UIView *platter = nil; @try { platter = [self valueForKey:@"mainPlatterView"]; } @catch (id e) {}   // (KVC on a private class, every layout: guarded)
    if (![platter isKindOfClass:[UIView class]]) platter = nil;
    // Our own items (Finder, Downloads, the second divider) are placed from the slots of the latest -getMetrics:forBounds: answer -- and SpringBoard
    // also asks for other bounds (-contentHeightForBounds:, -platterShadowOutsetsForBounds:), whose answers set the slots too. They are worked out
    // again here for this view's own bounds, the ones the layout above just used (K-2: a slot from another answer sits off the platter).
    { DMDockMetrics own; memset(&own, 0, sizeof(own)); [(SBFloatingDockView *)self getMetrics:&own forBounds:((UIView *)self).bounds]; }
    if (platter) DMDownloadsAttach(platter, gDownloadsSlot, gShowDownloads);
    DMReadIconCornerRatio((UIView *)self);
    if (platter) DMFinderIconAttach(platter, gFinderSlot, gShowFinder && gFinderSlot.size.width > 0);
    DMSecondDividerAttach((UIView *)self);
}
- (void)updateDividerVisualStyling {   // (light / dark and material changes restyle the Dock's own divider: the second one follows)
    %orig;
    UIView *mine = objc_getAssociatedObject(self, kDivider2Key), *native = DMNativeDivider((UIView *)self);
    if (mine && native) { DMCopyDividerLook(native, mine); if (gDivider2Alone && mine.alpha < 0.01) mine.alpha = 1.0; }
}
- (void)setHidden:(BOOL)hidden {
    if (gKeepDockVisible && hidden) return;
    %orig;
}
- (void)setAlpha:(CGFloat)alpha {
    if (gKeepDockVisible && alpha < 0.5) return;
    %orig;
}
- (CGFloat)platterVerticalMargin {
    CGFloat stock = %orig;
    return (stock > gBottomGap) ? gBottomGap : stock;
}
// Icon size: scale every number of the layout together, so the icons, the spacing and the background (platter) shrink as
// one and stay centred. The platter's bottom edge stays where it was (the gap above), so a smaller Dock never floats up.
- (void)getMetrics:(DMDockMetrics *)m forBounds:(CGRect)bounds {
    %orig;
#if DEBUG
    if (gDMStockMetricsOnly) return;
#endif
    if (m && MSBDDiagEnabled() && bounds.size.width >= 100.0 && m->platter.size.width >= 1.0 && isfinite(m->platter.origin.x)) {   // (untested iPadOS: the Dock's
        // own numbers as iOS gave them -- a real layout only, not the empty first pass -- and which kinds of icons it holds; names and numbers only)
        static CFTimeInterval lastDiag = 0;
        CFTimeInterval nowT = CACurrentMediaTime();
        if (nowT - lastDiag > 5.0) {
            lastDiag = nowT;
            NSCountedSet *kinds = [NSCountedSet set];
            NSMutableArray *stack = [NSMutableArray arrayWithObject:(UIView *)self];
            while (stack.count) {
                UIView *v = stack.lastObject; [stack removeLastObject];
                if ([NSStringFromClass([v class]) hasSuffix:@"IconView"]) { id icon = nil; @try { icon = [v valueForKey:@"icon"]; } @catch (id e) {} [kinds addObject:icon ? NSStringFromClass([icon class]) : @"(no icon)"]; continue; }
                [stack addObjectsFromArray:v.subviews];
            }
            NSMutableArray *k = [NSMutableArray array];
            for (NSString *c in kinds) [k addObject:[NSString stringWithFormat:@"%@ x%lu", c, (unsigned long)[kinds countForObject:c]]];
            #define R(r) NSStringFromCGRect(CGRectIntegral(r))
            MSBDDiagWrite(@"Dock", [NSString stringWithFormat:@"bounds %@\nuserList %@ recents %@ library %@ divider %@ platter %@ spacing %.1f\nshowDownloads %d magnify %d iconSize %.2f\nicons: %@\ndownloads %@ own %d, finder %@",
                R(bounds), R(m->userList), R(m->recentsList), R(m->libraryIcon), R(m->divider), R(m->platter), m->spacing, gShowDownloads, gEnabled, gIconSize, [k componentsJoinedByString:@", "],
                R(gDownloadsSlot), gDownloadsOwnSlot, R(gFinderSlot)]);   // (our slots from the last layout)
            #undef R
        }
    }
    if (!m || bounds.size.width < 100.0 || m->platter.size.width < 1.0) return;
    if (gDMDockInLayout == (UIView *)self && CGRectEqualToRect(bounds, ((UIView *)self).bounds)) {   // (K-2: the counts the platter is sized for; see kDMDockSizedForKey)
        NSUInteger uc = 0, rc = 0;
        if (DMDockIconCounts((UIView *)self, &uc, &rc)) objc_setAssociatedObject(self, kDMDockSizedForKey, @[@(uc), @(rc)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL rtl = ((UIView *)self).effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    if (rtl) { DM_FEATURE_MARK("dock-rtl"); DMDockMirrorMetrics(m); }   // (worked out left-to-right below, mirrored back at the end)
    // Finder: the Dock's first place, like a Mac -- one icon + one spacing in front of the apps; everything after it moves over and the platter
    // grows by as much (worked out first, so Downloads and the fit below see the Dock with Finder in it). The slot is an icon of the Dock's own
    // size (the App Library icon's, or the first app's), at the apps' start and height.
    CGRect finderSlot = CGRectZero;
    CGFloat hiddenSide = DMDockHiddenLibrarySide(m);   // (no App Library icon in the Dock: the Dock's icon size, else 0)
    {
        CGSize icon = m->libraryIcon.size.width >= 1.0 ? m->libraryIcon.size : hiddenSide > 0.0 ? CGSizeMake(hiddenSide, hiddenSide) : CGSizeMake(m->userList.size.height, m->userList.size.height);
        if (gShowFinder && icon.width >= 8.0 && m->userList.size.height >= 8.0) {
            DM_FEATURE_MARK("dock-finder-icon");
            CGFloat extra = icon.width + m->spacing;
            // (the app list starts with a leading inset of one spacing before its first icon (iPad 2: list x 0, spacing 10, first app at 10): Finder
            //  takes the first app's old place, and the apps move on by one icon + one spacing -- at x 0 the gap after Finder was two spacings)
            finderSlot = CGRectMake(m->userList.origin.x + m->spacing, m->userList.origin.y + (m->userList.size.height - icon.height) / 2.0, icon.width, icon.height);
            m->userList.origin.x += extra;
            m->divider.origin.x += extra;
            m->recentsList.origin.x += extra;
            m->libraryIcon.origin.x += extra;
            m->platter.size.width += extra;
            m->platter.origin.x -= extra / 2.0;
        }
    }
    // Launchpad next to Finder (owner, 2 Oct): the App Library / Launchpad icon moves from the Dock's end to its start -- right after Finder, or
    // at the apps' start without Finder -- and the apps, the divider and the recents move on by one icon + one spacing. The Dock keeps its width
    // (the icon only changes ends); Downloads then takes the end, where the App Library icon used to be.
    BOOL lpLeft = NO; CGRect libEnd = m->libraryIcon;
    if (gLaunchpadLeft && m->libraryIcon.size.width >= 8.0 && m->userList.size.height >= 8.0) {
        DM_FEATURE_MARK("dock-launchpad-left");
        lpLeft = YES;
        CGFloat extra = m->libraryIcon.size.width + m->spacing;
        CGFloat startX = finderSlot.size.width >= 1.0 ? CGRectGetMaxX(finderSlot) + m->spacing : m->userList.origin.x + m->spacing;
        libEnd = m->libraryIcon;
        libEnd.origin.x += extra;   // (the end moves on with the recents: Downloads sat on the last recent app, iPad 2 2 Oct)
        m->libraryIcon.origin.x = startX;
        m->userList.origin.x += extra;
        m->divider.origin.x += extra;
        m->recentsList.origin.x += extra;
    }
    // Downloads stack: one more icon slot right before the App Library icon. The slot is the App Library icon's old spot; the
    // App Library icon and the end of the platter move over by one icon + spacing. (Launchpad at the start: the slot is the end, the icon stays.)
    CGRect slot = lpLeft ? libEnd : m->libraryIcon;
    // Without the App Library icon (its spot 0 wide) Downloads takes a whole icon's spot of the Dock's size (DMDockHiddenLibrarySide) at the end of the
    // lists, level with the apps, as the App Library icon sits when it is there. Without it iOS ends the lists at the platter's end (18.2's class
    // method: the lists carry a spacing on both sides, the platter is the icons plus a spacing at each end), so the platter grows by the icon plus the
    // one spacing after it -- iOS's own margin after the lists, if any, is taken off: measured, not assumed. Where that height is not there either,
    // everything Downloads-related in this layout is left out (no widening, no second divider, no slot): the Dock only grows for a stack it shows.
    CGFloat ownExtra = -1.0;   // (>= 0: the platter's growth for a Downloads slot of its own, instead of one icon + one spacing)
    gDownloadsOwnSlot = NO;
    if (!lpLeft && gShowDownloads && hiddenSide > 0.0 && slot.size.width < 1.0) {
        CGFloat listsEnd = MAX(CGRectGetMaxX(m->userList), m->recentsList.size.width >= 1.0 ? CGRectGetMaxX(m->recentsList) : 0.0);
        CGFloat after = m->platter.size.width - listsEnd;
        if (isfinite(listsEnd) && listsEnd > 0.0 && isfinite(after) && after > -1.0) {
            DM_FEATURE_MARK("dock-downloads-own-slot");
            slot = CGRectMake(listsEnd, m->userList.origin.y + (m->userList.size.height - hiddenSide) / 2.0, hiddenSide, hiddenSide);
            ownExtra = MAX(hiddenSide, hiddenSide + m->spacing - MAX(0.0, after));
            gDownloadsOwnSlot = YES;
        }
    }
    BOOL downloadsOn = gShowDownloads && slot.size.width >= 1.0;
    // The second divider (see gDivider2Rect): with Downloads. After the recents (the recents list at least half an icon wide) it is a second line;
    // with no recents the Dock hides its own line and ours is the only one, between the apps and Downloads (as on macOS). Its gap is one spacing
    // + the 1 pt line; the line's own width is not scaled below, which is corrected after scaling.
    CGRect nativeDivider = m->divider;
    CGFloat unscaledSpacing = m->spacing;
    BOOL hasRecents = m->recentsList.size.width >= slot.size.width * 0.5;
    BOOL divider2 = downloadsOn && nativeDivider.size.width > 0.0 && nativeDivider.size.height > 1.0;
#if DEBUG
    {   // (debug: the Dock's own numbers, whenever they change)
        static NSString *lastMetrics = nil;
        NSString *mt = [NSString stringWithFormat:@"user %@ recents %@ divider %@ library %@ spacing %.2f", NSStringFromCGRect(m->userList), NSStringFromCGRect(m->recentsList), NSStringFromCGRect(nativeDivider), NSStringFromCGRect(slot), m->spacing];
        if (![mt isEqualToString:lastMetrics]) { lastMetrics = mt; DMLog([@"[metrics] " stringByAppendingString:mt]); }
    }
#endif
    if (downloadsOn) {
        CGFloat extra = (ownExtra >= 0.0 ? ownExtra : slot.size.width + m->spacing) + (divider2 ? unscaledSpacing + nativeDivider.size.width : 0.0);
        if (!lpLeft) m->libraryIcon.origin.x += extra;
        m->platter.size.width += extra;
        m->platter.origin.x -= extra / 2.0;
    }
    CGFloat f = gIconSize;
    // Auto-fit, like macOS (2026-09-25): the Icon Size is the largest the Dock gets; when the whole Dock (apps, divider, recents, Downloads, App
    // Library) would not fit the screen minus the side margins, it gets just small enough to fit -- in both orientations, re-worked out at every
    // layout (apps or recents added or removed, a turn). Room is kept at both ends for the magnification: the end icons grow in place by
    // (magnification - 1) x their width, half on each side, and must stay on the screen.
    CGFloat headroom = gEnabled ? MAX(0.0, gMagnification - 1.0) * (slot.size.width >= 1.0 ? slot.size.width : hiddenSide) : 0.0;   // (no end icon: the icon size)
    CGFloat room = (bounds.size.width - 50.0) / (m->platter.size.width + headroom);
    // Portrait: the screen is narrower, so a Dock this tweak has shrunk looks small. It grows to the widest size that still fits (at most
    // 1.2 times the stock size). Only while the tweak is shrinking the Dock at all; a size of 1.0 or more is left alone.
    // Portrait is read from the bounds asked about (the Dock spans its screen's width: narrower than the screen's long side = portrait), never from
    // the screen's current orientation: during a turn SpringBoard lays the Dock out for the new bounds while the screen still reports the old side,
    // and the same bounds must always get the same answer (K-2: the portrait size stayed on in landscape after a turn, iPad 2: 974 pt instead of 831).
    UIScreen *dockScreen = ((UIView *)self).window.windowScene.screen ?: [UIScreen mainScreen];
    BOOL portraitBounds = bounds.size.width < MAX(dockScreen.bounds.size.width, dockScreen.bounds.size.height) - 1.0;
    if (gPortraitLarger && f < 1.0 && portraitBounds) f = MIN(room, 1.2);
    if (f > room) f = room;
    static CGFloat lastF = -1; static CGFloat lastW = -1;
    if (fabs(f - lastF) > 0.001 || fabs(bounds.size.width - lastW) > 0.5) {
        lastF = f; lastW = bounds.size.width;
        DMLog([NSString stringWithFormat:@"[fit] screen %.0f, dock %.0f + %.0f magnification room at size 1: icon size %.3f (setting %.2f, fits up to %.3f)", bounds.size.width, m->platter.size.width, headroom, f, gIconSize, room]);
    }
    gFinderSlot = CGRectMake(finderSlot.origin.x * f, finderSlot.origin.y * f, finderSlot.size.width * f, finderSlot.size.height * f);
    if (!downloadsOn && fabs(f - 1.0) < 0.001) {
        if (gTweakOn && isfinite(gBottomGap)) m->platter.origin.y = CGRectGetMaxY(bounds) - gBottomGap - m->platter.size.height;   // (Gap to Screen Edge, below)
#if DEBUG
        if (CACurrentMediaTime() < gDMMetricsLogUntil) DMLog([NSString stringWithFormat:@"[metricslog] view %p bounds %@: f 1 (no Downloads), platter %@", self, NSStringFromCGRect(bounds), NSStringFromCGRect(m->platter)]);
#endif
        gDownloadsSlot = CGRectZero; gDivider2Rect = CGRectZero;
        if (rtl) { DMDockMirrorMetrics(m); if (gFinderSlot.size.width > 0.0) gFinderSlot = DMDockMirrorRect(gFinderSlot, m->platter.size.width); }
        return;
    }
    CGRect (^scaled)(CGRect) = ^CGRect(CGRect r) { return CGRectMake(r.origin.x * f, r.origin.y * f, r.size.width * f, r.size.height * f); };
    gDownloadsSlot = downloadsOn ? scaled(slot) : CGRectZero;
    gDivider2Rect = CGRectZero;
    gDivider2Alone = !hasRecents;
    if (divider2) {
        // The line goes where the Downloads icon would start (one spacing after the last recent, as the Dock's own divider is one spacing after
        // its last app); Downloads moves one spacing + the line further on. Scaled, the line stays 1 pt (not f pt), so the end of the Dock
        // moves on by the difference.
        // The Dock starts its recents a hair off the end of its line (about -0.1 pt); Downloads gets the same offset, so both lines have exactly the
        // same gaps on either side.
        CGFloat lineW = nativeDivider.size.width;
        CGFloat off = hasRecents ? m->recentsList.origin.x * f - (nativeDivider.origin.x * f + lineW) : 0.0;
        if (fabs(off) > 2.0) off = 0.0;   // (only that hair: never a big jump if the Dock's own layout ever differs)
        CGFloat pull = lineW - lineW * f + off;
        gDivider2Rect = CGRectMake(slot.origin.x * f, nativeDivider.origin.y * f, lineW, nativeDivider.size.height * f);
        gDownloadsSlot.origin.x += unscaledSpacing * f + lineW + off;
        if (!lpLeft) m->libraryIcon.origin.x += pull / f;   // (in unscaled units: scaled below; Launchpad at the start stays next to Finder)
        m->platter.size.width += pull / f;
        m->platter.origin.x -= pull / f / 2.0;
    }
    m->userList = scaled(m->userList);
    m->recentsList = scaled(m->recentsList);
    m->libraryIcon = scaled(m->libraryIcon);
    CGRect d = m->divider;
    m->divider = CGRectMake(d.origin.x * f, d.origin.y * f, d.size.width, d.size.height * f);   // stays a 1 pt line
    m->padding = UIEdgeInsetsMake(m->padding.top * f, m->padding.left * f, m->padding.bottom * f, m->padding.right * f);
    CGRect p = m->platter;
    CGFloat w = p.size.width * f, h = p.size.height * f;
    m->platter = CGRectMake(p.origin.x + (p.size.width - w) / 2.0, p.origin.y + p.size.height - h, w, h);
    m->iconScale *= f;
    m->spacing *= f;
    if (rtl) {   // (back to the mirrored Dock: the lists, the divider and our slots inside the final platter)
        CGFloat pw = m->platter.size.width;
        DMDockMirrorMetrics(m);
        if (gFinderSlot.size.width > 0.0) gFinderSlot = DMDockMirrorRect(gFinderSlot, pw);
        if (gDownloadsSlot.size.width > 0.0) gDownloadsSlot = DMDockMirrorRect(gDownloadsSlot, pw);
        if (gDivider2Rect.size.height > 0.0) gDivider2Rect = DMDockMirrorRect(gDivider2Rect, pw);
    }
    // Gap to Screen Edge: the platter's bottom this many points above the Dock view's bottom (= the screen's bottom edge), whatever iPadOS chose --
    // the platter margin hook below only ever lowered iPadOS's own margin, and on iPadOS 16 it had no effect at all (0 and 24 pt gave the same
    // Dock, iPad 2, 29 Sep). The icons are placed relative to the platter, so they move with it. Taken on every layout: a change shows at once.
    // It is its own setting (Settings: its own group, not under Magnification): applied whenever the Dock part is on, with Magnify Icons on or off -- it
    // used to wait for magnification, so with Magnify Icons off the Dock stayed at iPadOS's own height whatever the slider said (K-2 report: 18.5 pt).
    if (gTweakOn && isfinite(gBottomGap)) { DM_FEATURE_MARK("dock-bottom-gap"); m->platter.origin.y = CGRectGetMaxY(bounds) - gBottomGap - m->platter.size.height; }
#if DEBUG
    if (CACurrentMediaTime() < gDMMetricsLogUntil) {
        NSArray *st = [NSThread callStackSymbols];
        DMLog([NSString stringWithFormat:@"[metricslog] view %p bounds %@: f %.3f, platter %@, user %@, finder %@, downloads %@ | from %@ / %@", self, NSStringFromCGRect(bounds), f, NSStringFromCGRect(m->platter), NSStringFromCGRect(m->userList),
            NSStringFromCGRect(gFinderSlot), NSStringFromCGRect(gDownloadsSlot), st.count > 2 ? st[2] : @"-", st.count > 3 ? st[3] : @"-"]);
    }
#endif
}
%end

// K-2: a Dock list has just placed its icons (for the count it has now). If the platter around it was sized for other counts (see
// kDMDockSizedForKey), the Dock view lays out again: SpringBoard's own -setNeedsLayout, which its Dock controller also sends after a list change
// (a pending flag: when the controller's own animated resize follows, as it normally does, nothing extra happens). The platter, the lists' frames
// and the icons then always come from the same counts, whichever path changed a list. At most a few requests a second per Dock view (a guard
// against an endless loop if a count were ever read differently), and only for a Dock list in a Dock view on screen.
static void DMDockCheckSizedFor(UIView *list) {
    if (!list.window || list.hidden) return;
#if DEBUG
    if (access("/tmp/msb-nok2check", F_OK) == 0) return;   // (debug kill switch: the check off, for the before/after test)
#endif
    Class dockClass = objc_getClass("SBFloatingDockView");
    UIView *dock = list.superview;
    while (dock && !(dockClass && [dock isKindOfClass:dockClass])) dock = dock.superview;
    if (!dock) return;
    NSArray *sized = objc_getAssociatedObject(dock, kDMDockSizedForKey);
    NSUInteger uc = 0, rc = 0;
    if (sized.count != 2 || !DMDockIconCounts(dock, &uc, &rc)) return;
    if (uc == [sized[0] unsignedIntegerValue] && rc == [sized[1] unsignedIntegerValue]) return;
    static CFTimeInterval windowStart = 0; static int asked = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - windowStart > 1.0) { windowStart = now; asked = 0; }
    if (++asked > 4) return;
    DM_FEATURE_MARK("dock-sized-for-check");
    [dock setNeedsLayout];
    DMLog([NSString stringWithFormat:@"[dock] a Dock list placed its icons for %lu + %lu, the platter was sized for %@ + %@: the Dock lays out again",
        (unsigned long)uc, (unsigned long)rc, sized[0], sized[1]]);
}
%group DMDockListLayout   // (only where Dock lists lay out through this method: see %ctor)
%hook SBDockIconListView
- (void)layoutIconsIfNeededUsingAnimator:(id)animator options:(unsigned long long)options {
    %orig;
    DMDockCheckSizedFor((UIView *)self);
}
%end
%end

// DOCK BUG #2: a full-screen app converted to a window can extend past the Dock's own borders and gets drawn OVER it,
// because SBFloatingDockWindow's native level (25) is far below the window-engine layer's level. Confirmed via a live
// `dumpwindows` on the M1 (currently on the Aerial engine, its default/active one -- checked with `defaults read
// com.besiktasliseba.macstatusbar windowEngine` before assuming anything): `AerialWindow level=1033.0`. MilkyWay's own layer
// (AXPassthroughWindow, per the dev memory's MILKYWAY WORK note) sits at the same 1033, so this floor covers both engines
// without needing to special-case either one. Native iPadOS keeps
// the Dock always topmost when it is shown, regardless of what windows are behind it -- reusing exactly the technique
// Downloads.m already uses and has already proven safe on-device (raising SBFloatingDockWindow's window level above 1033 while
// its panel is open, see kPanelWindowLevel there): a floor, not a fixed value, so anything that legitimately wants the window
// even higher (the Downloads panel's own 1036, or a system alert) is left alone. This is a plain public UIWindow property --
// no alloc/init of a private class, no calling an unfamiliar private method; it only clamps a value on a method the OS/SpringBoard
// already calls on an object it already created, the same category of change as every other hook in this file.
static const UIWindowLevel kDockMinWindowLevel = 1034.0;   // 1 above MilkyWay/Aerial's window layer (1033), below the Downloads panel's 1036

// REFINEMENT (2026-09-23): the floor above was originally UNCONDITIONAL (always >= 1034) -- the owner then reported a Home Screen icon's
// 3D-Touch/Haptic-Touch menu going BEHIND the Dock, and separately a minimize-to-Dock animation looking buggier than before. Rather
// than guess which of tonight's several changes actually caused which symptom, made this strictly safer regardless: only raise the
// floor while it is actually needed, i.e. while a window-engine window is visible AND its frame really overlaps the Dock's own frame.
// The rest of the time (Home Screen with nothing floating over the Dock's own screen region, all windows minimized, etc.) the Dock's
// level passes through untouched, so anything else in the system that assumes the Dock's native ordering -- a context menu, the App
// Switcher, a minimize animation -- is never fought over z-order in the first place. Read-only frame/hidden/alpha checks on windows
// the OS already created; nothing here is alloc/init'd or calls anything beyond plain public UIWindow/UIView properties.
//
// CORRECTION (confirmed live via dumpwindows, not assumed): AerialWindow/AXPassthroughWindow themselves are NEVER hidden and always
// cover the full screen frame, whether or not any app is actually open inside them -- checking the CONTAINER's own hidden/alpha/frame
// is meaningless, it is always "visible" and always overlaps the Dock. What actually needs floating over is the individual STAGE (an
// AerialStage, or an AXWindowView for MilkyWay) inside that container -- so this now walks the container's own subviews for one that
// is a real stage/window, not hidden, not effectively transparent, and whose OWN frame overlaps the Dock.
// (layering audit F4) Stages are also found nested (Aerial puts them up to 4 levels down, as the status bar part's own search does), and Zetsu's
// windows count too: each is a UIWindow of its own (level <= 1002, above the Dock's 25) whose frame is the window.
static BOOL DMDockStageOverlaps(UIView *v, NSArray<Class> *stageClasses, CGRect dock, int depth) {
    for (UIView *sub in v.subviews) {
        if (sub.hidden || sub.alpha < 0.05) continue;
        BOOL isStage = NO;
        for (Class c in stageClasses) if ([sub isKindOfClass:c]) { isStage = YES; break; }
        if (isStage) { if (CGRectIntersectsRect([sub convertRect:sub.bounds toCoordinateSpace:sub.window.screen.coordinateSpace], dock)) return YES; continue; }
        if (depth < 4 && DMDockStageOverlaps(sub, stageClasses, dock, depth + 1)) return YES;
    }
    return NO;
}
// External display (iPad 2 + TV, iPadOS 16, 2026-09-26 capture): the TV has a Dock of its own (another SBFloatingDockWindow, in the TV's scene), and
// the floor raised it to 1034 because a window on the iPad "overlapped" its frame -- two screens' coordinates compared. The floor is for the iPad's
// Dock only (the window engines' windows live on the iPad): a Dock on another screen keeps SpringBoard's own level, and only windows on the Dock's
// own screen are compared. Without an external display every window is on the main screen: nothing changes.
static UIScreen *DMDockScreenOf(UIWindow *w) {
    UIScreen *s = nil;
    @try { s = w.windowScene.screen ?: w.screen; } @catch (id e) {}
    return s;
}
static BOOL DMDockOnMainScreen(UIWindow *w) {
    UIScreen *s = DMDockScreenOf(w);
    return !s || s == [UIScreen mainScreen];
}
// Where the Dock is drawn, in the screen's coordinate space: its platter (SBFloatingDockPlatterView), where it is right now (mid-slide too).
// The Dock WINDOW covers the whole screen (iPad 2, iOS 16: {{0, 0}, {1024, 768}}), so testing windows against the window's frame said "overlaps"
// for any window anywhere, and the Dock stayed raised to 1034 as long as any window was open (iPad 2, 26 Sep). CGRectNull: no Dock on the screen.
static CGRect DMDockPlatterScreenRect(UIView *dockWindow) {
    Class platterClass = objc_getClass("SBFloatingDockPlatterView");
    UIWindow *win = [dockWindow isKindOfClass:[UIWindow class]] ? (UIWindow *)dockWindow : dockWindow.window;
    if (!platterClass || !win.screen) return CGRectNull;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:dockWindow];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:platterClass] && v.window && v.superview) {
            CGFloat alpha = 1.0; for (UIView *x = v; x; x = x.superview) alpha *= (x.layer.presentationLayer ?: x.layer).opacity * (x.hidden ? 0 : 1);
            if (alpha < 0.05) return CGRectNull;
            CALayer *pl = v.layer.presentationLayer ?: v.layer;
            CGRect r = [v.superview convertRect:pl.frame toCoordinateSpace:win.screen.coordinateSpace];
            return CGRectIntersectsRect(r, win.screen.bounds) ? r : CGRectNull;
        }
        [stack addObjectsFromArray:v.subviews];
    }
    return CGRectNull;
}
static BOOL DMDockNeedsFloat(UIView *dockWindow) {
    NSMutableArray<Class> *stageClasses = [NSMutableArray array];
    for (NSString *stageName in @[@"AerialStage", @"AXWindowView"]) { Class c = objc_getClass(stageName.UTF8String); if (c) [stageClasses addObject:c]; }
    Class zetsu = objc_getClass("ZetsuWindow");
    CGRect dock = DMDockPlatterScreenRect(dockWindow);
    if (CGRectIsNull(dock)) return NO;   // (no Dock on the screen: nothing to keep above the windows)
    UIScreen *dockScreen = [dockWindow isKindOfClass:[UIWindow class]] ? DMDockScreenOf((UIWindow *)dockWindow) : nil;
    {   // (room above the platter for the magnified icons, M1 26 Sep; with magnification off, only a small margin)
        CGFloat lift = gEnabled ? MAX(12.0, dock.size.height * (MAX(gMagnification, 1.0) - 1.0) + 6.0) : 4.0;
        dock.origin.y -= lift; dock.size.height += lift;
    }
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (w.hidden || w.alpha < 0.05) continue;
        if (dockScreen) { UIScreen *ws = DMDockScreenOf(w); if (ws && ws != dockScreen) continue; }   // (an external display's Dock: only windows on its own screen count)
        if (zetsu && [w isKindOfClass:zetsu]) { if (CGRectIntersectsRect([w convertRect:w.bounds toCoordinateSpace:w.screen.coordinateSpace], dock)) return YES; continue; }
        NSString *cls = NSStringFromClass([w class]);
        if (!stageClasses.count || (![cls isEqualToString:@"AerialWindow"] && ![cls isEqualToString:@"AXPassthroughWindow"])) continue;
        if (DMDockStageOverlaps(w, stageClasses, dock, 0)) return YES;
    }
    return NO;
}
static UIWindowLevel gDockNativeLevel = -1;   // the level SpringBoard last gave the Dock (below the floor); -1: not seen yet
static BOOL gDockFloorSuppressed = NO;        // the App Switcher or Control Center is up: the Dock keeps its native place under them
static __weak UIWindow *gDockWindow = nil;
static void DMDockFloorWatchStart(void);   // (stock mode / line off: lowers the Dock again when the status bar's tick does not run)
@interface SBFloatingDockWindow : UIWindow
@end
%hook SBFloatingDockWindow
- (void)setWindowLevel:(UIWindowLevel)level {
    // (a Dock on an external display keeps the level SpringBoard gives it, see DMDockOnMainScreen)
    if (!DMDockOnMainScreen((UIWindow *)self)) {
        %orig;
        return;
    }
    gDockWindow = (UIWindow *)self;
    if (level < kDockMinWindowLevel) gDockNativeLevel = level;
    if (level < kDockMinWindowLevel && !gDockFloorSuppressed && DMDockNeedsFloat((UIView *)self)) { level = kDockMinWindowLevel; DMDockFloorWatchStart(); }
    %orig(level);
}
%end
// (layering audit F4) The floor used to be decided only when SpringBoard set the Dock's level: a window dragged over the Dock later covered it, and
// once raised the Dock stayed at 1034 after the window left (a Home Screen icon's Haptic Touch menu then opened behind the Dock). The status bar
// part calls this on its 0.25 s tick (it knows the App Switcher and Control Center): the Dock is raised while a window overlaps it, and goes back
// to SpringBoard's own level when none does, or while the App Switcher / Control Center is up. Never touched while the Downloads panel holds it
// higher (1036) or keeps it on screen.
extern BOOL gKeepDockVisible;
static CFTimeInterval gDockTickReassertAt = 0;   // the status bar's tick asked last (it does not run in stock mode or with its line off)
static void DMDockReassertLevelNow(BOOL systemUIUp);
__attribute__((visibility("default"))) void DMDockReassertLevel(BOOL systemUIUp) {   // (systemUIUp: App Switcher, Control Center or a software keyboard)
    gDockTickReassertAt = CACurrentMediaTime();
    DMDockReassertLevelNow(systemUIUp);
}
static void DMDockReassertLevelNow(BOOL systemUIUp) {
    gDockFloorSuppressed = systemUIUp;
    UIWindow *w = gDockWindow;
    if (!w) {
        Class c = objc_getClass("SBFloatingDockWindow");
        for (UIWindow *x in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) if (c && [x isKindOfClass:c] && DMDockOnMainScreen(x)) { w = gDockWindow = x; break; }
        if (!w) return;
    }
    UIWindowLevel now = w.windowLevel;
    if (gKeepDockVisible || now > kDockMinWindowLevel + 0.5) return;   // (the Downloads panel's own level)
    if (now < kDockMinWindowLevel) gDockNativeLevel = now;
    BOOL want = !systemUIUp && !w.hidden && DMDockNeedsFloat(w);
    if (want && now < kDockMinWindowLevel) {
        w.windowLevel = kDockMinWindowLevel;
        DMDockFloorWatchStart();
        DMLog([NSString stringWithFormat:@"[docklevel] a window overlaps the Dock: Dock raised from %.0f to %.0f", now, kDockMinWindowLevel]);
    } else if (!want && fabs(now - kDockMinWindowLevel) < 0.01 && gDockNativeLevel >= 0) {
        w.windowLevel = gDockNativeLevel;
        DMLog([NSString stringWithFormat:@"[docklevel] %@: Dock back to its own level %.0f", systemUIUp ? @"App Switcher / Control Center" : @"no window overlaps it", gDockNativeLevel]);
    }
}

// Stock status bar mode, or the MacStatusBar line off: the status bar's tick (which normally lowers the Dock again) does not run, so a Dock raised by
// the hook would stay at 1034 (a Home Screen icon's Haptic Touch menu then opens behind it; layering audit #4). While the Dock is raised, this
// light 0.5 s watcher of the Dock part does the tick's job whenever the tick has not asked for 1.5 s; it stops as soon as the Dock is back down
// (or the tick is running), and skips its work while the screen is off.
static BOOL DMDockSwitcherOrCCUp(void) {
    id sw = nil;
    Class vc = objc_getClass("SBMainSwitcherViewController"), co = objc_getClass("SBMainSwitcherControllerCoordinator");
    SEL shared = @selector(sharedInstance), ifExists = NSSelectorFromString(@"sharedInstanceIfExists");
    if (vc && [(id)vc respondsToSelector:shared]) sw = ((id (*)(id, SEL))objc_msgSend)((id)vc, shared);
    else if (co && [(id)co respondsToSelector:ifExists]) sw = ((id (*)(id, SEL))objc_msgSend)((id)co, ifExists);
    for (NSString *name in @[@"isAnySwitcherVisible", @"isMainSwitcherVisible"]) {
        SEL sel = NSSelectorFromString(name);
        if ([sw respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(sw, sel)) return YES;
    }
    Class ccClass = objc_getClass("SBControlCenterController");
    id cc = ccClass && [(id)ccClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)((id)ccClass, shared) : nil;
    for (NSString *name in @[@"isPresented", @"isVisible"]) {
        SEL sel = NSSelectorFromString(name);
        if ([cc respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(cc, sel)) return YES;
    }
    return NO;
}
static NSTimer *gDockFloorWatch = nil;
static void DMDockFloorWatchStart(void) {
    if (gDockFloorWatch) return;
    gDockFloorWatch = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        UIWindow *w = gDockWindow;
        BOOL raised = w && fabs(w.windowLevel - kDockMinWindowLevel) < 0.01;
        if (!raised || CACurrentMediaTime() - gDockTickReassertAt < 1.5) { [t invalidate]; gDockFloorWatch = nil; return; }   // (down again, or the tick runs)
        static int blankToken = 0; uint64_t blank = 0;
        if (!blankToken) notify_register_check("com.apple.springboard.hasBlankedScreen", &blankToken);
        if (blankToken) notify_get_state(blankToken, &blank);
        if (blank) return;   // (screen off: nothing to see)
        DMDockReassertLevelNow(DMDockSwitcherOrCCUp());
    }];
    gDockFloorWatch.tolerance = 0.1;
    [[NSRunLoop mainRunLoop] addTimer:gDockFloorWatch forMode:NSRunLoopCommonModes];
}

static void DMRelayoutDock(void) {
    Class dockClass = objc_getClass("SBFloatingDockView");
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            [stack addObjectsFromArray:v.subviews];
            if (dockClass && [v isKindOfClass:dockClass]) {
                [v setNeedsLayout];
                [v.superview setNeedsLayout];
                [v layoutIfNeeded];
                DMLog([NSString stringWithFormat:@"[relayout] dock frame %@", NSStringFromCGRect(v.frame)]);
            }
        }
    }
}

static void DMRelayoutDock(void);
extern void DMLaunchpadRefresh(UIView *iconView, BOOL enabled, BOOL classic);
// Switching Launchpad style (rocket/grid) or the feature's own on/off needed a respring before this: DMRelayoutDock only forces the Dock's
// own view to lay out again, which does not cascade into a fresh -layoutSubviews for the App Library icon specifically unless its frame
// actually changes (it does not, only its look does) — DMLaunchpadRefresh (which draws the overlay) is only ever called FROM that icon's own
// -layoutSubviews, so nothing actually asked for one. Found the icon directly here instead of waiting for one to happen on its own.
static void DMRefreshLaunchpadIcons(void) {
    SEL iconSel = NSSelectorFromString(@"icon");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
#pragma clang diagnostic pop
        NSMutableArray *stack = [NSMutableArray arrayWithObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            [stack addObjectsFromArray:v.subviews];
            if (![v respondsToSelector:iconSel]) continue;
            id icon = ((id (*)(id, SEL))objc_msgSend)(v, iconSel);
            if ([NSStringFromClass([icon class]) isEqualToString:@"SBHLibraryPodIndicatorIcon"]) DMLaunchpadRefresh(v, gLaunchpadIcon, gLaunchpadClassic);
        }
    }
}
static void DMPrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n,
                           const void *obj, CFDictionaryRef info) {
    DMLoadPrefs();
    DMRelayoutDock();
    DMRefreshLaunchpadIcons();
}

static void DMCollectIcons(UIView *root, Class iconClass, NSMutableArray *out) {
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:iconClass]) [out addObject:v];
        else DMCollectIcons(v, iconClass, out);
    }
}

static BOOL DMIsDockIcon(UIView *icon) {
    Class platter = objc_getClass("SBFloatingDockPlatterView");
    for (UIView *v = icon.superview; v; v = v.superview) {
        if ([v isKindOfClass:platter]) return YES;
    }
    return NO;
}

@interface SBFloatingDockPlatterView : UIView
- (void)dm_hover:(UIHoverGestureRecognizer *)gesture;
- (void)dm_apply;
- (void)dm_tick:(CADisplayLink *)link;
- (void)dm_startLink;
- (void)dm_stopLink;
@end

%hook SBFloatingDockPlatterView

- (void)setHidden:(BOOL)hidden {
    if (gKeepDockVisible && hidden) return;
    %orig;
}
- (void)setAlpha:(CGFloat)alpha {
    if (gKeepDockVisible && alpha < 0.5) return;
    %orig;
}
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (objc_getAssociatedObject(self, kHoverKey)) return; // attach once

    UIHoverGestureRecognizer *hover =
        [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(dm_hover:)];
    [self addGestureRecognizer:hover];
    objc_setAssociatedObject(self, kHoverKey, hover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMLog([NSString stringWithFormat:@"[attach] hover recognizer on platter %p, window=%@",
           self, NSStringFromClass([self.window class])]);
}

%new
- (void)dm_hover:(UIHoverGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            CGFloat x = [gesture locationInView:self].x;
            if (!gHovering) {
                DMLog(@"[hover] began");
                gStatFrames = 0; gStatMaxJump = 0.0;
                if (gInfluence < 0.01) gSmoothX = x;   // arriving fresh: start under the cursor, do not slide in from where it last was
            }
            gHovering = YES;
            gFocusX = x;
            [self dm_startLink];
            break;
        }
        default:   // ended / cancelled / failed: the cursor left the dock; the display link eases the effect out
            DMLog([NSString stringWithFormat:@"[hover] ended (state %ld) after %ld frames, largest scale change between frames %.4f",
                   (long)gesture.state, (long)gStatFrames, gStatMaxJump]);
            gHovering = NO;
            [self dm_startLink];
            break;
    }
}

%new
- (void)dm_startLink {
    if (gLink) return;
    gLastTimestamp = 0.0;
    gLinkPlatter = self;
    gLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(dm_tick:)];
    if ([gLink respondsToSelector:@selector(setPreferredFrameRateRange:)])
        gLink.preferredFrameRateRange = CAFrameRateRangeMake(60.0, 120.0, 120.0);
    [gLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

%new
- (void)dm_stopLink {
    [gLink invalidate];
    gLink = nil;
    gIcons = nil;
}

%new
- (void)dm_tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    CGFloat dt = gLastTimestamp > 0.0 ? (CGFloat)(now - gLastTimestamp) : (CGFloat)(1.0 / 60.0);
    gLastTimestamp = now;
    if (dt < 1.0 / 240.0) dt = 1.0 / 240.0;
    if (dt > 1.0 / 20.0) dt = 1.0 / 20.0;     // a hitch must not make the icons jump

    BOOL want = gEnabled && gHovering;
    gSmoothX += (gFocusX - gSmoothX) * (1.0 - exp(-dt / kFocusTau));
    gInfluence += ((want ? 1.0 : 0.0) - gInfluence) * (1.0 - exp(-dt / (want ? kInTau : kOutTau)));

    [self dm_apply];

    if (!want && gInfluence < 0.002) {   // finished easing out: leave every icon exactly untouched
        gInfluence = 0.0;
        [self dm_apply];
        [self dm_stopLink];
    } else if (want && fabs(gFocusX - gSmoothX) < 0.05 && gInfluence > 0.998) {
        // Battery (layering audit F2): the pointer resting on the Dock kept this link running every frame (120 Hz on the M1) with nothing moving.
        // Settled: the icons are put exactly on the target and the link stops; the next pointer movement (the hover recognizer's "changed") or a
        // foreign transform write on a Dock icon (the SBIconView hook) starts it again, and the hover ending eases out as before.
        gSmoothX = gFocusX; gInfluence = 1.0;
        [self dm_apply];
        [self dm_stopLink];
    }
}

%new
- (void)dm_apply {
    // The icon list only changes when the dock does; refresh it now and then instead of walking the views every frame.
    if (!gIcons || ++gFramesSinceRefresh > 60) {
        NSMutableArray *icons = [NSMutableArray array];
        DMCollectIcons(self, objc_getClass("SBIconView"), icons);
        UIView *downloads = DMDownloadsIcon(self);   // the Downloads stack magnifies like the app icons
        if (downloads) [icons addObject:downloads];
        UIView *finderIcon = DMFinderIcon(self);     // (and Finder)
        if (finderIcon) [icons addObject:finderIcon];
        gIcons = icons;
        gFramesSinceRefresh = 0;
    }

    __block CGFloat centreScale = 1.0;
    gApplying = YES;
    [UIView performWithoutAnimation:^{
        for (UIView *icon in gIcons) {
            CGAffineTransform t = CGAffineTransformIdentity;
            if (gInfluence > 0.0 && !icon.hidden && icon.superview) {
                // A view's centre is unaffected by its own transform, so centre (converted into the platter's space)
                // is a stable measuring stick.
                CGPoint c = [icon.superview convertPoint:icon.center toView:self];
                CGFloat s = DMScale(gSmoothX - c.x);
                if (s > centreScale) centreScale = s;
                t = CGAffineTransformMakeScale(s, s);
            }
            icon.transform = t;
        }
    }];
    gApplying = NO;

    gStatFrames++;
    CGFloat jump = fabs(centreScale - gStatLastScale);
    if (gStatFrames > 1 && jump > gStatMaxJump) gStatMaxJump = jump;
    gStatLastScale = centreScale;
}

%end

extern void DMLaunchpadRefresh(UIView *iconView, BOOL enabled, BOOL classic);
// Diagnostic: anything OTHER than our code writing a dock icon's transform
// while we are hovering is what would fight us (system pointer effect, layout).
extern void DMUpdateRunningIndicator(UIView *iconView);
extern void DMStartRunningIndicatorPoll(void);
%hook SBIconView
- (void)layoutSubviews {
    %orig;
    DMLaunchpadRefresh((UIView *)self, gLaunchpadIcon, gLaunchpadClassic);   // only acts on the App Library icon
    DMUpdateRunningIndicator((UIView *)self);   // only acts on Dock icons (checks internally)
}
- (void)setTransform:(CGAffineTransform)t {
    %orig;
    if (gHovering && !gApplying && !gLink && DMIsDockIcon((UIView *)self)) {
        // (the link rests while the pointer rests on the Dock: something else reset a magnified icon, so it runs again and puts the scale back)
        dispatch_async(dispatch_get_main_queue(), ^{ if (gHovering && !gLink) [(SBFloatingDockPlatterView *)gLinkPlatter dm_startLink]; });
    }
    static int external = 0;
    if (gHovering && !gApplying && external < 40 && DMIsDockIcon((UIView *)self)) {
        external++;
        DMLog([NSString stringWithFormat:@"[foreign setTransform] a=%.3f d=%.3f tx=%.1f ty=%.1f",
               t.a, t.d, t.tx, t.ty]);
        DMLog([NSString stringWithFormat:@"    %@", [[NSThread callStackSymbols] subarrayWithRange:NSMakeRange(1, 5)]]);
    }
}
%end

// Swipe up opening the App Library: Lynx (with "replace Spotlight" on) hooks -[SBSearchScrollView gestureRecognizerShouldBegin:]
// and presents the App Library as soon as ANY vertical drag on the Home Screen begins, up as well as down. This hook refuses
// upward drags before Lynx's code runs (swipe down still does whatever it did). It must be installed AFTER Lynx's hook so it
// is the outer one, and Lynx.dylib loads after this library, hence the delayed %init in %ctor.
%group SwipeUpFix
%hook SBSearchScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gBlockSwipeUp && [gesture isKindOfClass:[UIPanGestureRecognizer class]]) {
        UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)gesture;
        CGPoint velocity = [pan velocityInView:(UIView *)self];
        CGPoint moved = [pan translationInView:(UIView *)self];
        if (velocity.y < -1.0 || (fabs(velocity.y) <= 1.0 && moved.y < -1.0)) {
            static int logged = 0;
            if (logged++ < 20) DMLog([NSString stringWithFormat:@"[swipe-up] blocked an upward drag (velocity.y %.0f, moved.y %.1f)", velocity.y, moved.y]);
            return NO;
        }
    }
    return %orig;
}
%end
%end

// ---- Escape closes the App Library ----------------------------------------------------------------------------------
// The iPad's App Library is presented by an SBHModalLibraryPresenter, which the icon manager owns. Escape reaches SpringBoard as a
// key press that climbs the responder chain (like GraveEscapeTweak relies on), so a hook on UIResponder sees it whichever view has
// the keyboard focus (the App Library's search field, say). The presenter is found by looking through the icon controller's and
// icon manager's instance variables once, then remembered.
static __weak id gLibraryPresenter = nil;
static id DMSearchForPresenter(id object, Class target, int depth) {
    if (!object || depth > 2) return nil;
    unsigned count = 0;
    for (Class c = [object class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        Ivar *ivars = class_copyIvarList(c, &count);
        for (unsigned i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            id value = object_getIvar(object, ivars[i]);
            if (!value) continue;
            if ([value isKindOfClass:target]) { free(ivars); return value; }
            if (depth < 2 && [NSStringFromClass([value class]) hasPrefix:@"SB"]) {
                id found = DMSearchForPresenter(value, target, depth + 1);
                if (found) { free(ivars); return found; }
            }
        }
        free(ivars);
    }
    return nil;
}
static id DMLibraryPresenter(void) {
    if (gLibraryPresenter) return gLibraryPresenter;
    Class target = objc_getClass("SBHModalLibraryPresenter");
    Class controllerClass = objc_getClass("SBIconController");
    if (!target || !controllerClass) return nil;
    id controller = [controllerClass respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)controllerClass, @selector(sharedInstance)) : nil;
    id found = DMSearchForPresenter(controller, target, 0);
    if (!found) {
        id manager = [controller respondsToSelector:NSSelectorFromString(@"iconManager")] ? ((id (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"iconManager")) : nil;
        found = DMSearchForPresenter(manager, target, 0);
    }
    gLibraryPresenter = found;
    DMLog([NSString stringWithFormat:@"[escape] App Library presenter %@", found ? @"found" : @"NOT found"]);
    return found;
}
BOOL DMDismissAppLibraryIfShowing(void) {
    id presenter = DMLibraryPresenter();
    SEL showing = NSSelectorFromString(@"isPresentingLibrary");
    if (![presenter respondsToSelector:showing] || !((BOOL (*)(id, SEL))objc_msgSend)(presenter, showing)) return NO;
    for (NSString *name in @[@"dismissLibraryWithAnimation:completion:", @"dismissLibraryAnimated:completion:"]) {
        SEL s = NSSelectorFromString(name);
        if ([presenter respondsToSelector:s]) { DMLog([NSString stringWithFormat:@"[escape] closing the App Library via %@", name]); ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, s, YES, nil); return YES; }
    }
    SEL toggle = NSSelectorFromString(@"toggleLibraryPresentedInForegroundWithAnimation:completion:");
    if ([presenter respondsToSelector:toggle]) { DMLog(@"[escape] closing the App Library via toggle"); ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, toggle, YES, nil); return YES; }
    return NO;
}
// Same presenter, the other direction: used by the swipe-down-opens-App-Library feature below.
BOOL DMPresentAppLibrary(void) {
    id presenter = DMLibraryPresenter();
    SEL present = NSSelectorFromString(@"presentLibraryWithAnimation:completion:");
    if (![presenter respondsToSelector:present]) { DMLog(@"[swipe-down] presenter has no presentLibraryWithAnimation:completion:"); return NO; }
    DMLog(@"[swipe-down] presenting the App Library");
    ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, present, YES, nil);
    return YES;
}
// Both hooks below call this; the same key press is seen more than once (each responder, and the application), so act once per press.
static void DMHandleEscapePresses(NSSet<UIPress *> *presses) {
    if (!gEscapeClosesLibrary) return;
    for (UIPress *press in presses) {
        if (!press.key || press.key.keyCode != 41 || press.phase != UIPressPhaseBegan) continue;   // 41 = Escape (HID usage)
        static NSTimeInterval handled = -1.0;
        if (press.timestamp != handled) { handled = press.timestamp; DMDismissAppLibraryIfShowing(); }
        return;
    }
}
%hook UIResponder
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    DMHandleEscapePresses(presses);
    %orig;
}
%end
// The application also sees every key press before any responder does, so Escape works even when a text field (the App Library's
// search bar) would otherwise keep it.
%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    if (event.type == UIEventTypePresses) DMHandleEscapePresses([(UIPressesEvent *)event allPresses]);
    // (the Downloads panel closes on a touch anywhere else in SpringBoard's windows)
    if (event.type == UIEventTypeTouches) for (UITouch *t in event.allTouches) if (t.phase == UITouchPhaseBegan) { DMDownloadsTouchBegan(t.view); break; }
    %orig;
}
%end

// ---- Swipe down opens the App Library (our own feature, standalone -- no dependency on Lynx) --------------------
// This is the real, independent replacement for Lynx's "replace Spotlight" feature: it detects a genuine downward
// drag starting on the Home Screen's search scroll view and presents the App Library itself, via the same
// DMLibraryPresenter()/objc_msgSend mechanism already proven by the Escape-closes-Library feature just above --
// nothing here is instantiated, only an existing OS object (found by DMLibraryPresenter's ivar search) is asked to
// present itself, exactly the codebase's established safe pattern.
//
// Direction detection is the mirror of the up-swipe detection in the %group SwipeUpFix block earlier in this file
// (same velocity check, falling back to the pan's translation while velocity is still ~0 right as the drag begins),
// just flipped to fire on DOWN instead of blocking UP.
//
// This hook is deliberately in the file's default (ungrouped) %hook set, %init'd immediately in %ctor -- NOT in the
// delayed %group SwipeUpFix, and not dependent on it in any way. Because it installs at load time, it ends up as the
// innermost layer on -gestureRecognizerShouldBegin: relative to Lynx's own hook (Lynx's dylib, and its hook, loads
// after this one) and relative to SwipeUpFix's hook (delayed 4s to load after Lynx's). Practical effect:
//   - Lynx installed, "replace Spotlight" ON: Lynx's own (outer) hook keeps presenting the App Library on any
//     vertical drag exactly as it does today; this inner hook normally never even runs for that gesture, since
//     Lynx's handler does not call down to %orig. No behaviour change, no conflict.
//   - Lynx removed entirely: there is nothing above this hook any more, so IT alone detects the downward drag and
//     presents the App Library. Verified by reading (not assuming) that DMLibraryPresenter()/present selectors are
//     already working, and that this hook's %orig chain still reaches the real SBSearchScrollView implementation
//     with Lynx absent -- this hook does not reference Lynx or anything Lynx provides anywhere.
static BOOL DMSwipeIsDownward(UIPanGestureRecognizer *pan, UIView *in) {
    CGPoint velocity = [pan velocityInView:in];
    CGPoint moved = [pan translationInView:in];
    return velocity.y > 1.0 || (fabs(velocity.y) <= 1.0 && moved.y > 1.0);
}
// Only while the Mac status bar shows its Spotlight button (Mac mode, MacStatusBar line on, Show Spotlight Search on): otherwise the swipe is the
// only touch way into Spotlight, so it stays iPadOS's own. StatusBar.x publishes this SpringBoard's pid while the button is shown.
static BOOL DMSpotlightButtonShown(void) {
    static int token = 0;
    if (!token && notify_register_check("com.besiktasliseba.macstatusbar.spotlightshown", &token) != NOTIFY_STATUS_OK) { token = 0; return NO; }
    uint64_t state = 0;
    notify_get_state(token, &state);
    return state != 0 && state == (uint64_t)getpid();
}
// A drag that started on an icon of the desktop (Mac Status Bar's, statusbar/Desktop.h, found by its class) is the icon's, never a swipe down.
static BOOL DMPanStartedOnDesktopIcon(UIGestureRecognizer *gesture) {
    Class c = NSClassFromString(@"DMDesktopItemView");
    UIWindow *w = gesture.view.window;
    if (!c || !w || ![gesture isKindOfClass:[UIPanGestureRecognizer class]]) return NO;
    CGPoint p = [gesture locationInView:w], t = [(UIPanGestureRecognizer *)gesture translationInView:w];
    for (UIView *v = [w hitTest:CGPointMake(p.x - t.x, p.y - t.y) withEvent:nil]; v; v = v.superview) if ([v isKindOfClass:c]) return YES;
    return NO;
}
%hook SBSearchScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (DMPanStartedOnDesktopIcon(gesture)) { DMLog(@"[swipe-down] a drag from a desktop icon: not a swipe"); return NO; }
    if (gSwipeDownOpensLibrary && DMSpotlightButtonShown() && [gesture isKindOfClass:[UIPanGestureRecognizer class]] &&
        DMSwipeIsDownward((UIPanGestureRecognizer *)gesture, (UIView *)self)) {
        static int logged = 0;
        if (logged++ < 20) DMLog(@"[swipe-down] genuine downward drag on the Home Screen search view -> opening the App Library");
        DMPresentAppLibrary();
        return NO;   // do not let Spotlight's own scroll view begin dragging open underneath us
    }
    return %orig;
}
%end

#if DEBUG
extern void DMDownloadsStartDebugPolling(void);
#endif

// ===== Recent Apps: how many recent / open apps the Dock shows after the divider (2026-09-24) ======================
// Replicates Lynx's "Recent Icons" (com.mtac.lynxtwo dockSuggestions, a count 0-10; the owner uses 4): the Dock's right-hand section is SpringBoard's own
// SBFloatingDockSuggestionsModel (recently used and currently open apps, kept up to date by SpringBoard itself, force quits included), and its size is
// the "maximum number of suggestions" it is created with. We hand it our count instead (Settings > Dock > Recent Apps, default 3 for new installs, 4 before; 0 = none). The model is
// made once when SpringBoard starts, so a new count applies after a respring (like Lynx). iOS 15 and 16 have slightly different initialisers.
static long DMRecentsCount(void) {
    CFPropertyListRef v = CFPreferencesCopyValue(CFSTR("dockRecentsCount"), DM_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    long n = 3;   // (an update keeps 4 where untouched: sshtoggled --freeze-defaults)
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)v, kCFNumberLongType, &n);
    else if (v && CFGetTypeID(v) == CFStringGetTypeID()) n = [(__bridge NSString *)v integerValue];
    if (v) CFRelease(v);
    return MAX(0, MIN(10, n));
}
// "None" (0) must never reach SpringBoard as a maximum: iOS 16 crash-loops into Safe Mode when a Handoff/continuity suggestion arrives with a
// maximum of 0 (-[SBFloatingDockSuggestionsModel _updateCurrentDisplayItemsAfterContinuityChange:notifyDelegate:] removes an item at index -1).
// So for "None" the model keeps SpringBoard's own maximum and we switch its recents off instead (what the stock "Show Suggested and Recent Apps in
// Dock" switch does), which empties the section safely. Counts 1-10 are passed through (a maximum of 1 or more is always safe).
@interface SBFloatingDockSuggestionsModel : NSObject
- (void)_setRecentsEnabled:(BOOL)enabled;
- (unsigned long long)maxSuggestions;
@end
static BOOL gDMRecentsNone = NO;
static __weak id gDMSuggestionsModel = nil;   // (the Dock's recents model, for the debug dump)
// Apps used in windows: SpringBoard only counts an app as used when it opens full screen (a main-display layout transition), so an app used in a
// window never showed up in the Dock's recents. Mac Status Bar calls this whenever a window comes to the front (or opens); it is handed to the recents
// controller the same way a touch in a full-screen app is ("user touched application"), so SpringBoard's own list moves it to the front -- its own
// order, de-duplication, count and "not already in the Dock" rule apply unchanged, and it survives a respring like any recent.
static __weak id gDMRecentsController = nil;
static NSString *gDMWindowedAdd = nil;   // (set only during our own add: the app used in a window)
static BOOL DMAppInUserDock(NSString *bundleID) {   // the Dock's own (left-hand) icons: SBIconController > iconManager > rootFolder > dock
    @try {
        Class icc = objc_getClass("SBIconController");
        id ic = (icc && [(id)icc respondsToSelector:@selector(sharedInstance)]) ? ((id (*)(id, SEL))objc_msgSend)((id)icc, @selector(sharedInstance)) : nil;
        id dock = [[[ic valueForKey:@"iconManager"] valueForKey:@"rootFolder"] valueForKey:@"dock"];
        for (id icon in [dock valueForKey:@"icons"]) {
            NSString *b = [icon respondsToSelector:NSSelectorFromString(@"applicationBundleID")] ? [icon valueForKey:@"applicationBundleID"] : nil;
            if ([b isEqualToString:bundleID]) return YES;
        }
    } @catch (id e) { return YES; }   // (unsure: treated as in the Dock, nothing added)
    return NO;
}
__attribute__((visibility("default"))) void DMDockNoteWindowedApp(NSString *bundleID) {
    id rc = gDMRecentsController;
    if (!rc || !bundleID.length || gDMRecentsNone) return;
    Class acClass = objc_getClass("SBApplicationController");
    id ac = (acClass && [(id)acClass respondsToSelector:@selector(sharedInstance)]) ? ((id (*)(id, SEL))objc_msgSend)((id)acClass, @selector(sharedInstance)) : nil;
    SEL appSel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    id app = [ac respondsToSelector:appSel] ? ((id (*)(id, SEL, id))objc_msgSend)(ac, appSel, bundleID) : nil;
    if (!app) return;
    // SpringBoard's recents list (SBRecentDisplayItemsController) keeps SBDisplayItems: the app's own item is moved to the front if it is there,
    // or a new one for the app's main scene is added at the front -- the list's own add/move, which tells the Dock's model through its delegate
    // (so the count, the order and "not already in the Dock" stay SpringBoard's). ("user touched application" alone did not add it: tried.)
    @try {
        NSOrderedSet *items = [rc respondsToSelector:@selector(recentDisplayItems)] ? ((id (*)(id, SEL))objc_msgSend)(rc, @selector(recentDisplayItems)) : nil;
        id existing = nil;
        for (id it in items) { NSString *b = [it respondsToSelector:@selector(bundleIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(it, @selector(bundleIdentifier)) : nil; if ([b isEqualToString:bundleID]) { existing = it; break; } }
        if (existing && [items indexOfObject:existing] == 0) return;   // (already the most recent)
        SEL addMove = NSSelectorFromString(@"_addOrMoveDisplayItemToFront:");
        if (![rc respondsToSelector:addMove]) return;
        id item = existing;
        if (!item) {
            Class di = objc_getClass("SBDisplayItem");
            SEL make = NSSelectorFromString(@"applicationDisplayItemWithBundleIdentifier:sceneIdentifier:");
            if (![(id)di respondsToSelector:make]) return;
            item = ((id (*)(id, SEL, id, id))objc_msgSend)((id)di, make, bundleID, [NSString stringWithFormat:@"sceneID:%@-default", bundleID]);
        }
        if (!item) return;
        gDMWindowedAdd = bundleID;   // (the Dock's model refuses items outside its own transitions: this one is let through, see its shouldAddItem hook)
        ((void (*)(id, SEL, id))objc_msgSend)(rc, addMove, item);
        gDMWindowedAdd = nil;
        NSOrderedSet *after = ((id (*)(id, SEL))objc_msgSend)(rc, @selector(recentDisplayItems));
        DMLog([NSString stringWithFormat:@"[recents] %@ used in a window: %@ the Dock's recents (item %@; list %lu -> %lu, first %@)", bundleID, existing ? @"moved to the front of" : @"added to", item, (unsigned long)items.count, (unsigned long)after.count, after.firstObject]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recents] %@: %@", bundleID, e.reason]); }
}
// Why "4" used to show 3 (found 2026-09-25 on the M1): the model stores the maximum it is created with (-maxSuggestions is a plain getter), but
// another tweak that hooks the same initialiser (Lynx: its own "dockSuggestions" count, 3) replaces the number on the way, and ours runs first, so
// its value won. Our count is now also written into the model right after it is made (DMForceRecentsMax), so N means N whatever else is installed.
static void DMForceRecentsMax(id model, unsigned long long m) {   // the model's own maximum (ivar _maxSuggestions, read back by -maxSuggestions)
    if (!model || m < 1) return;   // (never 0: see above)
    Ivar iv = class_getInstanceVariable([model class], "_maxSuggestions");
    const char *type = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!iv || !type || (strcmp(type, "Q") && strcmp(type, "q"))) { DMLog(@"[recents] the model's maximum was not found: left as it is"); return; }
    unsigned long long before = *(unsigned long long *)((uint8_t *)(__bridge void *)model + ivar_getOffset(iv));
    if (before != m) *(unsigned long long *)((uint8_t *)(__bridge void *)model + ivar_getOffset(iv)) = m;
    DMLog([NSString stringWithFormat:@"[recents] the model has %llu places after the divider (it was made with %llu)", m, before]);
}
// The model's maximum is the number of PLACES after the divider, shared by the recents and a suggested app (Siri suggestion / Handoff), which takes
// the last place when there is one (seen: 4 places = 3 recents + Notes suggested). So N recent apps get N + 1 places, and every step that builds or
// trims the recents list itself sees N (DMRecentsScope): N recents, plus the suggestion when there is one.
static unsigned long long *DMRecentsMaxIvar(id model) {
    static ptrdiff_t off = -1;
    if (off < 0) { Ivar iv = class_getInstanceVariable([model class], "_maxSuggestions"); const char *t = iv ? ivar_getTypeEncoding(iv) : NULL; off = (iv && t && (!strcmp(t, "Q") || !strcmp(t, "q"))) ? ivar_getOffset(iv) : 0; }
    return off > 0 ? (unsigned long long *)((uint8_t *)(__bridge void *)model + off) : NULL;
}
// While the recents list itself is built or trimmed, the model's maximum is N (the places minus the suggestion's), and back to N + 1 after.
// The steps call each other (didAddItem:andDropItem: -> _handleNewRecentItem: -> _moveOrAddRecentThenCull:), so only the OUTERMOST one lowers the
// maximum: each nested step lowered it once more (N+1 -> N -> N-1 -> N-2) and SpringBoard's own check in _moveOrAddRecentThenCull: threw -- a
// SpringBoard crash when an app not yet in the recents opened (M1, iOS 15, 2026-09-25 05:37, opening a game full screen).
static int gDMRecentsScopeDepth = 0;
static unsigned long long DMRecentsScopeBegin(id model) {
    if (gDMRecentsScopeDepth++ > 0) return 0;   // (nested: the outer step already did it; 0 = nothing to put back)
    unsigned long long *mx = gDMRecentsNone ? NULL : DMRecentsMaxIvar(model);
    unsigned long long was = mx ? *mx : 0;
    if (mx && was > 1) *mx = was - 1;
    return was;
}
static void DMRecentsScopeEnd(id model, unsigned long long was) {
    if (gDMRecentsScopeDepth > 0) gDMRecentsScopeDepth--;
    unsigned long long *mx = gDMRecentsNone ? NULL : DMRecentsMaxIvar(model);
    if (mx && was > 1) *mx = was;
}
// Why the Dock showed one recent app too few while (and after) a window was open (iPad 2, Zetsu, 2026-09-25): when an app is used in a window, the
// recents model swaps it in (e.g. Books -> App Store) and tells the Dock's recents view controller, which removes the old icon at once but PARKS the
// new icon's insert in its deferredIconUpdates. SpringBoard runs the parked updates only when a full-screen layout transition ends, and windows
// (Zetsu/Aerial/MilkyWay) never make one, so the Dock sat at N - 1 until the next full-screen app switch (recorded per frame: "deferred 1", 3 icons
// with the model holding 4). So after every recents change the parked updates are run here -- the same no-argument call SpringBoard makes at a
// transition's end -- unless a real transition is running then (its own end runs them, as before). Coalesced; kill switch /tmp/msb-nodockflush (debug builds only).
static __weak id gDMSuggestionsVC = nil;   // (the Dock's recents view controller, from its initialiser)
static BOOL DMDockIconFading(id vc) {   // an icon of the recents list still fading in or out (its own animation must end first)
    SEL listSel = NSSelectorFromString(@"listView");
    UIView *list = [vc respondsToSelector:listSel] ? ((id (*)(id, SEL))objc_msgSend)(vc, listSel) : nil;
    if (![list isKindOfClass:[UIView class]]) return NO;
    NSMutableArray *todo = [NSMutableArray arrayWithObject:@[list, @0]];
    while (todo.count) {   // (the icon views and three levels inside them: the fade runs on an inner layer)
        NSArray *e = todo.lastObject; [todo removeLastObject];
        UIView *v = e[0]; int d = [e[1] intValue];
        if (v != list && v.layer.animationKeys.count) return YES;
        if (d < 4) for (UIView *sub in v.subviews) [todo addObject:@[sub, @(d + 1)]];
    }
    return NO;
}
static void DMFlushDeferredDockIconsAfter(NSString *why, double delay, int tries);
static void DMFlushDeferredDockIcons(NSString *why) { DMFlushDeferredDockIconsAfter(why, 0.2, 0); }
static void DMFlushDeferredDockIconsAfter(NSString *why, double delay, int tries) {
    static BOOL queued = NO;
    if (queued && tries == 0) return;
#if DEBUG   // (test kill switch: never in a release build)
    if (access("/tmp/msb-nodockflush", F_OK) == 0) return;
#endif
    queued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id vc = gDMSuggestionsVC;
        if (vc && tries < 20 && DMDockIconFading(vc)) { DMFlushDeferredDockIconsAfter(why, 0.05, tries + 1); return; }   // (the removed icon's fade-out first)
        queued = NO;
        SEL pendingSel = NSSelectorFromString(@"deferredIconUpdates"), perform = NSSelectorFromString(@"_performDeferredIconUpdates");
        SEL coordSel = NSSelectorFromString(@"layoutStateTransitionCoordinator"), busySel = NSSelectorFromString(@"isTransitioning");
        if (!vc || ![vc respondsToSelector:pendingSel] || ![vc respondsToSelector:perform]) return;
        @try {
            NSArray *pending = ((id (*)(id, SEL))objc_msgSend)(vc, pendingSel);
            if (![pending isKindOfClass:[NSArray class]] || !pending.count) return;
            id coord = [vc respondsToSelector:coordSel] ? ((id (*)(id, SEL))objc_msgSend)(vc, coordSel) : nil;
            if (coord && [coord respondsToSelector:busySel] && ((BOOL (*)(id, SEL))objc_msgSend)(coord, busySel)) { DMLog([NSString stringWithFormat:@"[recents] %lu parked Dock icon update(s) left to the running transition (%@)", (unsigned long)pending.count, why]); return; }
            NSUInteger n = pending.count;
            ((void (*)(id, SEL))objc_msgSend)(vc, perform);
            DMLog([NSString stringWithFormat:@"[recents] %lu parked Dock icon update(s) run now: no full-screen transition to run them (%@)", (unsigned long)n, why]);
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recents] parked updates: %@", e.reason]); }
    });
}
static unsigned long long DMRecentsPlaces(void) { long n = DMRecentsCount(); return n > 0 ? (unsigned long long)n + 1 : 0; }
static unsigned long long DMRecentsMaxFor(unsigned long long stockMax) {
    long n = DMRecentsCount();
    gDMRecentsNone = (n == 0);
    unsigned long long m = gDMRecentsNone ? MAX(1ULL, stockMax) : (unsigned long long)MAX(1L, n) + 1;
    DMLog([NSString stringWithFormat:@"[recents] Dock recent apps: %llu -> %ld (maximum passed %llu%@)", stockMax, n, m, gDMRecentsNone ? @", recents switched off" : @""]);
    return m;
}
%hook SBFloatingDockSuggestionsModel
- (id)initWithMaximumNumberOfSuggestions:(unsigned long long)max iconController:(id)ic recentsController:(id)rc recentsDataStore:(id)ds recentsDefaults:(id)rd floatingDockDefaults:(id)fd appSuggestionManager:(id)am analyticsClient:(id)ac applicationController:(id)apc {
    gDMRecentsController = rc;
    unsigned long long m = DMRecentsMaxFor(max);
    id r = %orig(m, ic, rc, ds, rd, fd, am, ac, apc);
    gDMSuggestionsModel = r;
    if (r && !gDMRecentsNone) DMForceRecentsMax(r, m);
    if (r && gDMRecentsNone && [r respondsToSelector:@selector(_setRecentsEnabled:)]) [(SBFloatingDockSuggestionsModel *)r _setRecentsEnabled:NO];
    return r;
}
- (id)initWithMaximumNumberOfSuggestions:(unsigned long long)max iconController:(id)ic recentsController:(id)rc recentsDataStore:(id)ds recentsDefaults:(id)rd floatingDockDefaults:(id)fd appSuggestionManager:(id)am applicationController:(id)apc {
    gDMRecentsController = rc;
    unsigned long long m = DMRecentsMaxFor(max);
    id r = %orig(m, ic, rc, ds, rd, fd, am, apc);
    gDMSuggestionsModel = r;
    if (r && !gDMRecentsNone) DMForceRecentsMax(r, m);
    if (r && gDMRecentsNone && [r respondsToSelector:@selector(_setRecentsEnabled:)]) [(SBFloatingDockSuggestionsModel *)r _setRecentsEnabled:NO];
    return r;
}
- (BOOL)recentDisplayItemsController:(id)controller shouldAddItem:(id)item {
    BOOL r = %orig;
    if (!r && gDMWindowedAdd && [item respondsToSelector:@selector(bundleIdentifier)] && [((id (*)(id, SEL))objc_msgSend)(item, @selector(bundleIdentifier)) isEqualToString:gDMWindowedAdd]
        && !DMAppInUserDock(gDMWindowedAdd)) return YES;   // (never an app already in the Dock itself: the model's own rule)
    return r;
}
- (void)_setRecentsEnabled:(BOOL)enabled {
    BOOL e = enabled && !gDMRecentsNone;
    %orig(e);
}
- (void)setRecentsEnabled:(BOOL)enabled {
    BOOL e = enabled && !gDMRecentsNone;
    %orig(e);
}
- (BOOL)recentsEnabled {
    BOOL r = %orig;
    return r && !gDMRecentsNone;
}
- (id)_filterRecentDisplayItems:(id)items filteredOutItems:(id *)filtered {
    // (the recents part: always N, also when it is called from inside the shown list's build below, which sees N + 1)
    unsigned long long was = DMRecentsScopeBegin(self);
    unsigned long long *mx = gDMRecentsNone ? NULL : DMRecentsMaxIvar(self), places = DMRecentsPlaces(), before = mx ? *mx : 0;
    if (mx && places > 1) *mx = places - 1;
    id r = %orig;
    if (mx && places > 1) *mx = before;
    DMRecentsScopeEnd(self, was);
    return r;
}

- (id)_moveOrAddRecentThenCull:(id)item {
    unsigned long long was = DMRecentsScopeBegin(self);
    id r = %orig;
    DMRecentsScopeEnd(self, was);
    return r;
}
- (void)_handleNewRecentItem:(id)item {
    unsigned long long was = DMRecentsScopeBegin(self);
    %orig;
    DMRecentsScopeEnd(self, was);
}
- (void)recentDisplayItemsController:(id)c didAddItem:(id)item {
    unsigned long long was = DMRecentsScopeBegin(self);
    %orig;
    DMRecentsScopeEnd(self, was);
    DMFlushDeferredDockIcons(@"a recent added");
}
- (void)recentDisplayItemsController:(id)c didAddItem:(id)item andDropItem:(id)dropped {
    unsigned long long was = DMRecentsScopeBegin(self);
    %orig;
    DMRecentsScopeEnd(self, was);
    DMFlushDeferredDockIcons(@"a recent added, one dropped");
}
- (void)recentDisplayItemsController:(id)c didMoveItemToFront:(id)item {
    unsigned long long was = DMRecentsScopeBegin(self);
    %orig;
    DMRecentsScopeEnd(self, was);
    DMFlushDeferredDockIcons(@"a recent moved to the front");
}
%end
%group DMShownListFix   // (only where the method has exactly this type encoding: see %ctor)
%hook SBFloatingDockSuggestionsModel
// The shown list (recents + the suggestion) is built here -- and SpringBoard builds it from INSIDE the steps that add a recent, where the maximum is
// lowered to N for the recents list (DMRecentsScope). With a suggestion showing (a Handoff app), that left N places for both: N - 1 recents + the
// suggestion, so "4" showed 3 until the next rebuild (iPad 2, 2026-09-25: after a window's app was added, recorded "shown(Clock,Settings,Books,Notes)"
// with 4 recents held). While it builds, the maximum is the N + 1 places; its recents part (-_filterRecentDisplayItems:, above) still sees N.
- (void)_updateCurrentDisplayItemsAfterContinuityChange:(BOOL)continuity notifyDelegate:(BOOL)notify {   // (v24@0:8B16B20, read on iOS 16)
    unsigned long long *mx = gDMRecentsNone ? NULL : DMRecentsMaxIvar(self), places = DMRecentsPlaces(), before = mx ? *mx : 0;
    if (mx && places > 1) *mx = places;
    %orig;
    if (mx && places > 1) *mx = before;
}
%end
%end

// The icons themselves: the Dock's recents list (SBDockSuggestionsIconListView) has a model of its own whose capacity is the "number of recents" the
// suggestions view controller is made with -- SpringBoard's own count (3), whatever the recents model holds. This was the real reason "4" (ours, or
// Lynx's) showed 3: the model held 4, the list only had room for 3. Found 2026-09-25 on the M1 (list model maxNumberOfIcons 3 with the model at 4).
// iPadOS 18 names of the two recents initialisers above (homeScreenContextProvider: instead of iconController:, and no analyticsClient:), from the
// 18.2 SpringBoard: the same work, installed only where these methods exist (15/16 do not have them: never installed there).
%group DMRecentsModel18
%hook SBFloatingDockSuggestionsModel
- (id)initWithMaximumNumberOfSuggestions:(unsigned long long)max homeScreenContextProvider:(id)hp recentsController:(id)rc recentsDataStore:(id)ds recentsDefaults:(id)rd floatingDockDefaults:(id)fd appSuggestionManager:(id)am applicationController:(id)apc {
    gDMRecentsController = rc;
    unsigned long long m = DMRecentsMaxFor(max);
    id r = %orig(m, hp, rc, ds, rd, fd, am, apc);
    gDMSuggestionsModel = r;
    if (r && !gDMRecentsNone) DMForceRecentsMax(r, m);
    if (r && gDMRecentsNone && [r respondsToSelector:@selector(_setRecentsEnabled:)]) [(SBFloatingDockSuggestionsModel *)r _setRecentsEnabled:NO];
    return r;
}
%end
%end
%group DMRecentsList18
%hook SBFloatingDockSuggestionsViewController
- (id)initWithNumberOfRecents:(unsigned long long)n homeScreenContextProvider:(id)hp applicationController:(id)ac layoutStateTransitionCoordinator:(id)lc suggestionsModel:(id)sm iconViewProvider:(id)ivp {
    unsigned long long places = DMRecentsPlaces();
    unsigned long long use = places > 0 ? places : n;
    DMLog([NSString stringWithFormat:@"[recents] (18) the Dock's recents list has room for %llu (SpringBoard asked for %llu)", use, n]);
    id r = %orig(use, hp, ac, lc, sm, ivp);
    gDMSuggestionsVC = r;
    return r;
}
%end
%end
%group DMRecentsList
%hook SBFloatingDockSuggestionsViewController
- (id)initWithNumberOfRecents:(unsigned long long)n iconController:(id)ic applicationController:(id)ac layoutStateTransitionCoordinator:(id)lc suggestionsModel:(id)sm iconViewProvider:(id)ivp {
    unsigned long long places = DMRecentsPlaces();
    unsigned long long use = places > 0 ? places : n;   // (N recents + the suggestion's place; "None": SpringBoard's own count, the recents are switched off instead)
    DMLog([NSString stringWithFormat:@"[recents] the Dock's recents list has room for %llu (SpringBoard asked for %llu)", use, n]);
    id r = %orig(use, ic, ac, lc, sm, ivp);
    gDMSuggestionsVC = r;
    return r;
}
%end
// ... and its grid: the list's flow layout (location SBIconLocationFloatingDockSuggestions) has 3 columns, so a 4th recent wrapped onto a second row.
// Its layout configuration gets as many columns as places (never fewer than SpringBoard's own), before the list lays out its icons.
static BOOL DMWidenRecentsLayout(id layout) {   // YES if it had to be widened
    long c = (long)DMRecentsPlaces();
    if (c <= 3 || !layout) return NO;   // (SpringBoard's own 3 columns already fit 1-3 places)
    @try {
        id cfg = [layout respondsToSelector:NSSelectorFromString(@"layoutConfiguration")] ? [layout valueForKey:@"layoutConfiguration"] : nil;
        SEL get = NSSelectorFromString(@"numberOfPortraitColumns"), set = NSSelectorFromString(@"setNumberOfPortraitColumns:");
        if (![cfg respondsToSelector:get] || ![cfg respondsToSelector:set]) return NO;
        unsigned long long now = ((unsigned long long (*)(id, SEL))objc_msgSend)(cfg, get);
        if (now >= (unsigned long long)c) return NO;
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(cfg, set, (unsigned long long)c);
        DMLog([NSString stringWithFormat:@"[recents] the recents grid: %llu -> %ld columns", now, c]);
        return YES;
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recents] the recents grid: %@", e.reason]); }
    return NO;
}
static void DMWidenRecentsGrid(UIView *list) {
    @try {
        id loc = [list valueForKey:@"iconLocation"], prov = [list valueForKey:@"layoutProvider"];
        SEL lf = NSSelectorFromString(@"layoutForIconLocation:");
        id layout = [prov respondsToSelector:lf] ? ((id (*)(id, SEL, id))objc_msgSend)(prov, lf, loc) : nil;
        if (DMWidenRecentsLayout(layout)) {   // (widened after the list had already worked out its grid: it lays its icons out again)
            SEL need = NSSelectorFromString(@"setIconsNeedLayout");
            if ([list respondsToSelector:need]) ((void (*)(id, SEL))objc_msgSend)(list, need);
        }
    } @catch (NSException *e) {}
}
// A new layout provider (Settings > Home Screen > Use Large App Icons makes SpringBoard build new ones) hands out the recents' layout with 3 columns
// again: it is widened as it is handed out.
%hook SBHDefaultIconListLayoutProvider
- (id)layoutForIconLocation:(NSString *)location {
    id r = %orig;
    if ([location isKindOfClass:[NSString class]] && [location isEqualToString:@"SBIconLocationFloatingDockSuggestions"]) DMWidenRecentsLayout(r);
    return r;
}
%end
%hook SBDockSuggestionsIconListView
- (void)layoutSubviews {
    DMWidenRecentsGrid((UIView *)self);
    %orig;
}
%end
%end

#import "../common/OffAlert.h"
// ---- "Remove from Dock" in a Dock app's Haptic Touch menu (2026-09-29) ----
// Like a Mac's Dock: an app kept in the Dock can be taken out of it from its own menu, without the Home Screen in view (windows up, Stage
// Manager). The app goes to the first free place on the Home Screen, the same place iPadOS gives an app it adds itself. Only apps kept in
// the Dock (the root folder's Dock list), not its recent/suggested apps and not a folder.
static NSString * const kDMRemoveFromDockType = @"com.besiktasliseba.dock.removefromdock";
static id DMObj(id o, NSString *sel) { SEL s = NSSelectorFromString(sel); return [o respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static id DMIconModelRoot(id *mgrOut, id *modelOut) {
    id mgr = DMObj(DMObj((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    id model = DMObj(mgr, @"iconModel");
    if (mgrOut) *mgrOut = mgr;
    if (modelOut) *modelOut = model;
    return DMObj(model, @"rootFolder");
}
static BOOL DMIconKeptInDock(id icon) {   // (in the Dock list itself: a kept app, not a recent)
    id dock = DMObj(DMIconModelRoot(NULL, NULL), @"dock");
    SEL has = NSSelectorFromString(@"directlyContainsIcon:");
    return icon && [dock respondsToSelector:has] && ((BOOL (*)(id, SEL, id))objc_msgSend)(dock, has, icon);
}
static void DMRemoveFromDock(id icon) {
    DM_FEATURE_MARK("dock-remove-from-dock");
    id mgr = nil, model = nil;
    id root = DMIconModelRoot(&mgr, &model);
    id dock = DMObj(root, @"dock");
    NSArray *icons = DMObj(dock, @"icons");
    if (!root || !dock || ![icons isKindOfClass:[NSArray class]] || ![icons containsObject:icon]) return;
    NSUInteger oldIndex = [icons indexOfObject:icon];
    SEL optsSel = NSSelectorFromString(@"gridCellInfoOptions"), freeSel = NSSelectorFromString(@"gridPathForFirstFreeSlotAvoidingFirstList:listGridCellInfoOptions:");
    SEL insertSel = NSSelectorFromString(@"insertIcon:atGridPath:options:"), addSel = NSSelectorFromString(@"addIcon:options:listGridCellInfoOptions:");
    SEL removeSel = NSSelectorFromString(@"removeIcons:"), putBackSel = NSSelectorFromString(@"insertIcons:atIndex:options:");
    if (![dock respondsToSelector:removeSel]) return;
    unsigned long long opts = [mgr respondsToSelector:optsSel] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(mgr, optsSel) : 0;
    id path = [root respondsToSelector:freeSel] ? ((id (*)(id, SEL, BOOL, unsigned long long))objc_msgSend)(root, freeSel, NO, opts) : nil;
    ((void (*)(id, SEL, id))objc_msgSend)(dock, removeSel, @[icon]);
    id placed = nil;
    @try {
        if (path && [root respondsToSelector:insertSel]) placed = ((id (*)(id, SEL, id, id, unsigned long long))objc_msgSend)(root, insertSel, icon, path, 0);
        if (!placed && [root respondsToSelector:addSel]) placed = ((id (*)(id, SEL, id, unsigned long long, unsigned long long))objc_msgSend)(root, addSel, icon, 0, opts);
    } @catch (NSException *e) { placed = nil; }
    if (!placed) {   // (nowhere to put it: it stays in the Dock where it was, nothing lost)
        if ([dock respondsToSelector:putBackSel]) ((void (*)(id, SEL, id, NSUInteger, unsigned long long))objc_msgSend)(dock, putBackSel, @[icon], oldIndex, 0);
        DMLog(@"[dock] Remove from Dock: no free place on the Home Screen, kept in the Dock");
        return;
    }
    if ([model respondsToSelector:NSSelectorFromString(@"markIconStateDirty")]) ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"markIconStateDirty"));
    if ([model respondsToSelector:NSSelectorFromString(@"saveIconStateIfNeeded")]) ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
    DMLog([NSString stringWithFormat:@"[dock] Remove from Dock: %@ moved to the Home Screen at %@", DMObj(icon, @"applicationBundleID"), path]);
}
%hook SBIconView
- (NSArray *)applicationShortcutItems {
    NSArray *orig = %orig;
    Class itemClass = objc_getClass("SBSApplicationShortcutItem");
    id icon = DMObj(self, @"icon");
    NSString *location = DMObj(self, @"location");
    if (!gEnabled || !itemClass || ![location isKindOfClass:[NSString class]] || ![location containsString:@"Dock"] || [location containsString:@"Suggestions"]) return orig;
    if (!DMIconKeptInDock(icon) || ![DMObj(icon, @"applicationBundleID") isKindOfClass:[NSString class]]) return orig;
    id item = [[itemClass alloc] init];
    [item setValue:kDMRemoveFromDockType forKey:@"type"];
    [item setValue:@"Remove from Dock" forKey:@"localizedTitle"];
    [item setValue:DMObj(icon, @"applicationBundleID") forKey:@"bundleIdentifierToLaunch"];
    static NSData *png;
    if (!png) png = UIImagePNGRepresentation([UIImage systemImageNamed:@"minus.circle"]);
    Class iconClass = objc_getClass("SBSApplicationShortcutCustomImageIcon");
    SEL initSel = NSSelectorFromString(@"initWithImageData:dataType:isTemplate:");
    if (png && iconClass && [iconClass instancesRespondToSelector:initSel])
        [item setValue:((id (*)(id, SEL, id, long long, BOOL))objc_msgSend)([iconClass alloc], initSel, png, 0, YES) forKey:@"icon"];
    return [orig isKindOfClass:[NSArray class]] ? [orig arrayByAddingObject:item] : @[item];
}
+ (void)activateShortcut:(id)item withBundleIdentifier:(NSString *)bundleID forIconView:(id)iconView {
    if ([DMObj(item, @"type") isEqual:kDMRemoveFromDockType]) {
        id icon = DMObj(iconView, @"icon");
        dispatch_async(dispatch_get_main_queue(), ^{ DMRemoveFromDock(icon); });   // (after the menu has closed)
        return;
    }
    %orig;
}
%end

#if DEBUG
// ---- debug (K-2): "k2" in /tmp/dockmag-escape -- the whole Dock layout in one dump: SpringBoard's own layout numbers (our changes bypassed for that
// one call) and ours, the Dock view's own sizes, and per icon list its model (count / maximum), columns, insets mode, spacing, content scale, metrics
// and every icon view (frame, picture, hidden, alpha, the icon's place in the model). Names of apps are never written (index and class only).
typedef struct { CGSize size; CGFloat scale; CGFloat continuousCornerRadius; } DMK2IconImageInfo;
static char DMK2Ret(id o, SEL s) {   // the return type's first character of an instance method, 0 if none
    Method m = o ? class_getInstanceMethod(object_getClass(o), s) : NULL;
    if (!m) return 0;
    char t[64] = {0}; method_getReturnType(m, t, sizeof(t));
    return t[0] == 'r' || t[0] == 'n' || t[0] == 'N' || t[0] == 'o' || t[0] == 'O' || t[0] == 'R' || t[0] == 'V' ? t[1] : t[0];
}
static BOOL DMK2RetIs(id o, SEL s, const char *prefix) {
    Method m = o ? class_getInstanceMethod(object_getClass(o), s) : NULL;
    if (!m) return NO;
    char t[256] = {0}; method_getReturnType(m, t, sizeof(t));
    return strncmp(t, prefix, strlen(prefix)) == 0;
}
static NSString *DMK2Num(id o, NSString *name) {   // a number/BOOL getter, as text ("-" when missing)
    SEL s = NSSelectorFromString(name); char r = DMK2Ret(o, s);
    if (!r || method_getNumberOfArguments(class_getInstanceMethod(object_getClass(o), s)) != 2) return @"-";
    switch (r) {
        case 'd': return [NSString stringWithFormat:@"%.3f", ((double (*)(id, SEL))objc_msgSend)(o, s)];
        case 'f': return [NSString stringWithFormat:@"%.3f", ((float (*)(id, SEL))objc_msgSend)(o, s)];
        case 'q': case 'l': case 'i': return [NSString stringWithFormat:@"%lld", (long long)((long long (*)(id, SEL))objc_msgSend)(o, s)];
        case 'Q': case 'L': case 'I': return [NSString stringWithFormat:@"%llu", (unsigned long long)((unsigned long long (*)(id, SEL))objc_msgSend)(o, s)];
        case 'B': case 'c': case 'C': return ((BOOL (*)(id, SEL))objc_msgSend)(o, s) ? @"Y" : @"N";
        case '@': { id v = ((id (*)(id, SEL))objc_msgSend)(o, s); return v ? [[v description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "] : @"nil"; }
        case '{': {
            if (DMK2RetIs(o, s, "{CGSize=")) return NSStringFromCGSize(((CGSize (*)(id, SEL))objc_msgSend)(o, s));
            if (DMK2RetIs(o, s, "{CGRect=")) return NSStringFromCGRect(((CGRect (*)(id, SEL))objc_msgSend)(o, s));
            if (DMK2RetIs(o, s, "{UIEdgeInsets=")) return NSStringFromUIEdgeInsets(((UIEdgeInsets (*)(id, SEL))objc_msgSend)(o, s));
            if (DMK2RetIs(o, s, "{SBIconImageInfo=")) { DMK2IconImageInfo i = ((DMK2IconImageInfo (*)(id, SEL))objc_msgSend)(o, s); return [NSString stringWithFormat:@"{%@ scale %.1f radius %.2f}", NSStringFromCGSize(i.size), i.scale, i.continuousCornerRadius]; }
            char t[96] = {0}; method_getReturnType(class_getInstanceMethod(object_getClass(o), s), t, sizeof(t)); return [NSString stringWithFormat:@"(struct %s)", t];
        }
    }
    return [NSString stringWithFormat:@"(type %c)", r];
}
static NSString *DMK2Metrics(DMDockMetrics m) {
    return [NSString stringWithFormat:@"user %@ pad %@ recents %@ library %@ divider %@ platter %@ scale %.4f spacing %.3f", NSStringFromCGRect(m.userList), NSStringFromUIEdgeInsets(m.padding),
        NSStringFromCGRect(m.recentsList), NSStringFromCGRect(m.libraryIcon), NSStringFromCGRect(m.divider), NSStringFromCGRect(m.platter), m.iconScale, m.spacing];
}
static void DMK2Dump(void) {
    Class dockClass = objc_getClass("SBFloatingDockView");
    long long orient = 0;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) if ([s isKindOfClass:[UIWindowScene class]]) { orient = (long long)((UIWindowScene *)s).interfaceOrientation; break; }
    DMLog([NSString stringWithFormat:@"[k2] ==== dump: screen %@, orientation %lld, iOS %@, prefs: iconSize %.2f magnify %d (%.2f) finder %d launchpad %d left %d downloads %d portraitLarger %d gap %.1f recents %ld",
        NSStringFromCGSize([UIScreen mainScreen].bounds.size), orient, [UIDevice currentDevice].systemVersion, gIconSize, gEnabled, gMagnification, gShowFinder, gLaunchpadIcon, gLaunchpadLeft, gShowDownloads, gPortraitLarger, gBottomGap, DMRecentsCount()]);
    @try {
        id ic = DMObj((id)objc_getClass("SBIconController"), @"sharedInstance");
        id dockList = [[[ic valueForKey:@"iconManager"] valueForKey:@"rootFolder"] valueForKey:@"dock"];
        DMLog([NSString stringWithFormat:@"[k2] root folder Dock list %@: %@ icons, max %@", NSStringFromClass([dockList class]), DMK2Num(dockList, @"numberOfIcons"), DMK2Num(dockList, @"maxNumberOfIcons")]);
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[k2] root folder Dock list: %@", e.reason]); }
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (![NSStringFromClass([w class]) containsString:@"FloatingDock"]) continue;
        DMLog([NSString stringWithFormat:@"[k2] window %@ %@ level %.0f hidden %d alpha %.2f", NSStringFromClass([w class]), NSStringFromCGRect(w.frame), w.windowLevel, w.hidden, w.alpha]);
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            [todo addObjectsFromArray:v.subviews];
            NSString *cn = NSStringFromClass([v class]);
            if (dockClass && [v isKindOfClass:dockClass]) {
                DMLog([NSString stringWithFormat:@"[k2] dock view %@ bounds %@ frame-in-window %@ transform %@ hidden %d alpha %.2f", cn, NSStringFromCGRect(v.bounds), NSStringFromCGRect([v.superview convertRect:v.frame toView:w]), NSStringFromCGAffineTransform(v.transform), v.hidden, v.alpha]);
                NSMutableString *sz = [NSMutableString string];
                for (NSString *k in @[@"iconContentScale", @"minimumUserIconSpaces", @"paddingEdgeInsets", @"isEditing", @"platterVerticalMargin", @"maximumIconSize", @"_referenceIconSize", @"_referenceInterIconSpacing", @"maximumInterIconSpacing", @"interIconSpacing", @"maximumPlatterHeight", @"maximumEditingIconSize", @"_shouldDisplayAccessoryIconView", @"isAccessoryIconViewVisible", @"contentHeight", @"platterFrame"])
                    [sz appendFormat:@" %@=%@", k, DMK2Num(v, k)];
                DMLog([NSString stringWithFormat:@"[k2] dock sizes:%@", sz]);
                SEL gm = @selector(getMetrics:forBounds:);
                if ([v respondsToSelector:gm]) {
                    DMDockMetrics stock = {0}, ours = {0};
                    gDMStockMetricsOnly = YES;
                    @try { ((void (*)(id, SEL, DMDockMetrics *, CGRect))objc_msgSend)(v, gm, &stock, v.bounds); } @finally { gDMStockMetricsOnly = NO; }
                    ((void (*)(id, SEL, DMDockMetrics *, CGRect))objc_msgSend)(v, gm, &ours, v.bounds);
                    DMLog([@"[k2] SpringBoard's metrics: " stringByAppendingString:DMK2Metrics(stock)]);
                    DMLog([@"[k2] our metrics:          " stringByAppendingString:DMK2Metrics(ours)]);
                    DMLog([NSString stringWithFormat:@"[k2] our slots: finder %@ downloads %@ (own %d) divider2 %@", NSStringFromCGRect(gFinderSlot), NSStringFromCGRect(gDownloadsSlot), gDownloadsOwnSlot, NSStringFromCGRect(gDivider2Rect)]);
                }
                SEL cs = NSSelectorFromString(@"iconContentScaleForNumberOfUserIcons:");
                if ([v respondsToSelector:cs] && DMK2Ret(v, cs) == 'd') {
                    NSMutableString *o = [NSMutableString string];
                    for (unsigned long n = 8; n <= 18; n++) [o appendFormat:@" %lu:%.3f", n, ((double (*)(id, SEL, unsigned long))objc_msgSend)(v, cs, n)];
                    DMLog([NSString stringWithFormat:@"[k2] SpringBoard's content scale for n user icons (its own numbers, not ours):%@", o]);
                }
            }
            if ([cn isEqualToString:@"SBFloatingDockPlatterView"]) {
                NSMutableString *ours = [NSMutableString string];
                for (UIView *sv in v.subviews) [ours appendFormat:@" %@ %@%@ a%.2f", NSStringFromClass([sv class]), NSStringFromCGRect([v convertRect:sv.frame toView:w]), sv.hidden ? @"(hidden)" : @"", sv.alpha];
                DMLog([NSString stringWithFormat:@"[k2] platter %@ in window (presentation %@); subviews:%@", NSStringFromCGRect([v.superview convertRect:v.frame toView:w]), NSStringFromCGRect([v.superview convertRect:(v.layer.presentationLayer ?: v.layer).frame toView:w]), ours]);
            }
            if ([cn hasSuffix:@"IconListView"]) {
                id model = nil, shown = nil; @try { model = [v valueForKey:@"model"]; } @catch (NSException *e) {}
                if ([v respondsToSelector:NSSelectorFromString(@"displayedModel")]) @try { shown = [v valueForKey:@"displayedModel"]; } @catch (NSException *e) {}
                NSMutableString *p = [NSMutableString string];
                for (NSString *k in @[@"iconLocation", @"iconContentScale", @"iconSpacing", @"effectiveIconSpacing", @"layoutInsetsMode", @"automaticallyAdjustsLayoutMetricsToFit", @"allowsGaps", @"isLayoutReversed", @"layoutOrientation", @"orientation", @"iconColumnsForCurrentOrientation", @"iconRowsForCurrentOrientation", @"maximumIconCount", @"alignmentIconSize", @"iconImageSize", @"additionalLayoutInsets", @"isEditing", @"layoutScale", @"numberOfDisplayedIconViews"])
                    [p appendFormat:@" %@=%@", k, DMK2Num(v, k)];
                DMLog([NSString stringWithFormat:@"[k2] list %@ frame-in-window %@ bounds %@ model %@ %@/%@ displayed %@ %@:%@", cn, NSStringFromCGRect([v.superview convertRect:v.frame toView:w]), NSStringFromCGRect(v.bounds),
                    NSStringFromClass([model class]), DMK2Num(model, @"numberOfIcons"), DMK2Num(model, @"maxNumberOfIcons"), shown == model ? @"(same)" : NSStringFromClass([shown class]), shown && shown != model ? DMK2Num(shown, @"numberOfIcons") : @"", p]);
                @try {
                    id prov = [v valueForKey:@"layoutProvider"], loc = [v valueForKey:@"iconLocation"];
                    SEL lf = NSSelectorFromString(@"layoutForIconLocation:");
                    id layout = [prov respondsToSelector:lf] ? ((id (*)(id, SEL, id))objc_msgSend)(prov, lf, loc) : nil;
                    NSMutableString *l = [NSMutableString string];
                    for (NSNumber *o in @[@1, @3]) {
                        SEL cols = NSSelectorFromString(@"numberOfColumnsForOrientation:"), rows = NSSelectorFromString(@"numberOfRowsForOrientation:"), ins = NSSelectorFromString(@"layoutInsetsForOrientation:");
                        if ([layout respondsToSelector:cols]) [l appendFormat:@" o%@ cols %llu", o, ((unsigned long long (*)(id, SEL, long long))objc_msgSend)(layout, cols, o.longLongValue)];
                        if ([layout respondsToSelector:rows]) [l appendFormat:@" rows %llu", ((unsigned long long (*)(id, SEL, long long))objc_msgSend)(layout, rows, o.longLongValue)];
                        if ([layout respondsToSelector:ins] && DMK2RetIs(layout, ins, "{UIEdgeInsets=")) [l appendFormat:@" insets %@", NSStringFromUIEdgeInsets(((UIEdgeInsets (*)(id, SEL, long long))objc_msgSend)(layout, ins, o.longLongValue))];
                    }
                    DMLog([NSString stringWithFormat:@"[k2]   layout %@ (provider %@ screenType %@ options %@): iconImageInfo %@%@", NSStringFromClass([layout class]), NSStringFromClass([prov class]), DMK2Num(prov, @"screenType"), DMK2Num(prov, @"layoutOptions"), DMK2Num(layout, @"iconImageInfo"), l]);
                    SEL lm = NSSelectorFromString(@"layoutMetrics");
                    if (DMK2Ret(v, lm) == '@') DMLog([NSString stringWithFormat:@"[k2]   layoutMetrics %@", [[((id (*)(id, SEL))objc_msgSend)(v, lm) description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]]);
                    else DMLog([NSString stringWithFormat:@"[k2]   layoutMetrics: return type %c", DMK2Ret(v, lm) ?: '-']);
                } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[k2]   layout: %@", e.reason]); }
                SEL idxSel = NSSelectorFromString(@"indexForIcon:"), imgSel = NSSelectorFromString(@"iconImageFrame");
                NSMutableString *icons = [NSMutableString string];
                for (UIView *iv in v.subviews) {
                    if (![NSStringFromClass([iv class]) hasSuffix:@"IconView"]) continue;
                    id icon = DMObj(iv, @"icon");
                    long long idx = -1; if (model && icon && [model respondsToSelector:idxSel]) idx = (long long)((unsigned long long (*)(id, SEL, id))objc_msgSend)(model, idxSel, icon);
                    CGRect img = [iv respondsToSelector:imgSel] ? ((CGRect (*)(id, SEL))objc_msgSend)(iv, imgSel) : CGRectZero;
                    [icons appendFormat:@"\n[k2]     #%lld %@ frame %@ img %@ hidden %d alpha %.2f t %.2f%@", idx, NSStringFromClass([icon class]), NSStringFromCGRect([v convertRect:iv.frame toView:w]), NSStringFromCGRect([iv convertRect:img toView:w]), iv.hidden, iv.alpha, iv.transform.a, iv.superview == v ? @"" : @" (other parent)"];
                }
                DMLog([NSString stringWithFormat:@"[k2]   icon views:%@", icons]);
            }
        }
    }
    DMLog(@"[k2] ==== end");
}
// The verdict alone: per Dock icon list, its model count, the columns its layout used, its frame and the platter's, and whether every icon's picture
// (the view's centre, the list's content scale) lies inside the platter -- "INSIDE" or "OUTSIDE" with the worst overhang in points.
static NSString *DMK2Verdict(void) {
    NSMutableString *out = [NSMutableString string];
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"] || w.hidden) continue;
        UIView *platter = nil; NSMutableArray *lists = [NSMutableArray array], *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
            NSString *cn = NSStringFromClass([v class]);
            if ([cn isEqualToString:@"SBFloatingDockPlatterView"]) platter = v;
            else if ([cn hasSuffix:@"IconListView"]) [lists addObject:v];
        }
        if (!platter) continue;
        CGRect pr = [platter.superview convertRect:platter.frame toView:w];
        [out appendFormat:@"platter %.1f..%.1f (w %.1f)", CGRectGetMinX(pr), CGRectGetMaxX(pr), pr.size.width];
        for (UIView *l in lists) {
            id model = nil; @try { model = [l valueForKey:@"model"]; } @catch (NSException *e) {}
            NSString *used = @"?";
            SEL lm = NSSelectorFromString(@"layoutMetrics");
            if (DMK2Ret(l, lm) == '@') { id m = ((id (*)(id, SEL))objc_msgSend)(l, lm); used = DMK2Num(m, @"columnsUsedForLayout"); }
            CGFloat scale = 1.0; SEL cs = NSSelectorFromString(@"iconContentScale"); if (DMK2Ret(l, cs) == 'd') scale = ((double (*)(id, SEL))objc_msgSend)(l, cs);
            CGFloat worst = 0.0, minX = CGFLOAT_MAX, maxX = -CGFLOAT_MAX; int n = 0;
            for (UIView *iv in l.subviews) {
                if (![NSStringFromClass([iv class]) hasSuffix:@"IconView"] || iv.hidden || iv.alpha < 0.05) continue;
                CGPoint c = [l convertPoint:iv.center toView:w]; CGFloat half = iv.bounds.size.width * scale / 2.0;
                minX = MIN(minX, c.x - half); maxX = MAX(maxX, c.x + half); n++;
                worst = MAX(worst, MAX(CGRectGetMinX(pr) - (c.x - half), (c.x + half) - CGRectGetMaxX(pr)));
            }
            CGRect lr = [l.superview convertRect:l.frame toView:w];
            [out appendFormat:@" | %@ model %@ used %@ views %d frame %.1f..%.1f icons %.1f..%.1f %@", [NSStringFromClass([l class]) hasPrefix:@"SBDockSuggestions"] ? @"recents" : @"user", DMK2Num(model, @"numberOfIcons"), used, n,
                CGRectGetMinX(lr), CGRectGetMaxX(lr), n ? minX : 0, n ? maxX : 0, !n ? @"-" : worst > 1.0 ? [NSString stringWithFormat:@"OUTSIDE by %.1f", worst] : @"INSIDE"];
        }
    }
    return out.length ? out : @"(no Dock window)";
}
#endif

%ctor {
    %init;
    MSBDWatchMacStatusBarOff();   // ("MacStatusBar Is Off": this line runs while MacStatusBar is off, see OffAlert.h)
    {
        Method m = class_getInstanceMethod(objc_getClass("SBFloatingDockSuggestionsModel"), NSSelectorFromString(@"_updateCurrentDisplayItemsAfterContinuityChange:notifyDelegate:"));
        const char *enc = m ? method_getTypeEncoding(m) : NULL;
        if (enc && !strcmp(enc, "v24@0:8B16B20")) %init(DMShownListFix);
        else DMLog([NSString stringWithFormat:@"[recents] the shown-list build is not the known one (%s): left alone", enc ?: "missing"]);
    }
    if ([objc_getClass("SBFloatingDockSuggestionsViewController") instancesRespondToSelector:NSSelectorFromString(@"initWithNumberOfRecents:iconController:applicationController:layoutStateTransitionCoordinator:suggestionsModel:iconViewProvider:")]) %init(DMRecentsList);
    else DMLog(@"[recents] this iOS has no -[SBFloatingDockSuggestionsViewController initWithNumberOfRecents:...]: the list keeps SpringBoard's size");
    if ([objc_getClass("SBFluidSwitcherGestureManager") instancesRespondToSelector:NSSelectorFromString(@"_shouldTapToBringItemContainerForward:receiveTouch:")]) %init(DMPanelNoBringForward);
    if ([objc_getClass("SBDockIconListView") instancesRespondToSelector:NSSelectorFromString(@"layoutIconsIfNeededUsingAnimator:options:")]) %init(DMDockListLayout);   // (K-2, every version with that method: 15-18)
    else DMLog(@"[dock] this iOS has no -[SBDockIconListView layoutIconsIfNeededUsingAnimator:options:]: the Dock's count check is off");
    if ([objc_getClass("SBFloatingDockSuggestionsModel") instancesRespondToSelector:NSSelectorFromString(@"initWithMaximumNumberOfSuggestions:homeScreenContextProvider:recentsController:recentsDataStore:recentsDefaults:floatingDockDefaults:appSuggestionManager:applicationController:")]) %init(DMRecentsModel18);
    if ([objc_getClass("SBFloatingDockSuggestionsViewController") instancesRespondToSelector:NSSelectorFromString(@"initWithNumberOfRecents:homeScreenContextProvider:applicationController:layoutStateTransitionCoordinator:suggestionsModel:iconViewProvider:")]) %init(DMRecentsList18);
#if DEBUG   // (the /tmp/dockmag-* test helpers exist only in debug builds)
    if (access("/tmp/dockmag-debug", F_OK) == 0) dispatch_async(dispatch_get_main_queue(), ^{
        DMDownloadsStartDebugPolling();
        // `echo present > /tmp/dockmag-escape` opens the App Library, `echo escape > ...` runs the Escape action (no key injection here)
        static dispatch_source_t escapeTimer;
        static time_t lastEscape = 0;
        escapeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(escapeTimer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 1 * NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(escapeTimer, ^{
            struct stat st;
            if (stat("/tmp/dockmag-escape", &st) != 0 || st.st_mtimespec.tv_sec == lastEscape) return;
            lastEscape = st.st_mtimespec.tv_sec;
            char word[16] = {0}; FILE *f = fopen("/tmp/dockmag-escape", "r"); if (f) { if (fscanf(f, "%15s", word) != 1) word[0] = 0; fclose(f); }
            if (!strcmp(word, "present")) {
                id presenter = DMLibraryPresenter();
                SEL present = NSSelectorFromString(@"presentLibraryWithAnimation:completion:");
                DMLog([NSString stringWithFormat:@"[escape] debug: presenting the library (presenter %@)", presenter ? @"found" : @"missing"]);
                if ([presenter respondsToSelector:present]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, present, YES, nil);
            } else if (!strncmp(word, "size=", 5)) {   // debug: size=<n> tries an Icon Size in memory only (not saved); size=off reads the setting again
                if (!strcmp(word + 5, "off")) DMLoadPrefs(); else gIconSize = atof(word + 5);
                DMLog([NSString stringWithFormat:@"[fit] debug: icon size setting %.2f", gIconSize]);
                DMRelayoutDock();
            } else if (!strcmp(word, "k2")) {   // debug (K-2): the whole Dock layout in one dump (DMK2Dump)
                DMK2Dump();
                DMLog([@"[k2] verdict: " stringByAppendingString:DMK2Verdict()]);
            } else if (!strcmp(word, "k2v")) {   // debug (K-2): the verdict line only
                DMLog([@"[k2] verdict: " stringByAppendingString:DMK2Verdict()]);
            } else if (!strcmp(word, "k2move") || !strcmp(word, "k2back")) {   // debug (K-2): an icon into the Dock through the icon model (what a drop does), or the last moved one back
                static NSMutableArray *moved = nil; if (!moved) moved = [NSMutableArray array];   // (entries: @[icon, page, index])
                id root = DMIconModelRoot(NULL, NULL), dock = DMObj(root, @"dock");
                SEL rm = NSSelectorFromString(@"removeIcons:"), ins = NSSelectorFromString(@"insertIcons:atIndex:options:");
                @try {
                    if (!strcmp(word, "k2move")) {
                        NSArray *lists = DMObj(root, @"lists"); id page = [lists lastObject]; NSArray *icons = DMObj(page, @"icons"); id icon = [icons lastObject];
                        if (icon && [page respondsToSelector:rm] && [dock respondsToSelector:ins]) {
                            NSUInteger idx = icons.count - 1, at = [DMObj(dock, @"icons") count];
                            ((void (*)(id, SEL, id))objc_msgSend)(page, rm, @[icon]);
                            ((void (*)(id, SEL, id, NSUInteger, unsigned long long))objc_msgSend)(dock, ins, @[icon], at, 0);
                            [moved addObject:@[icon, page, @(idx)]];
                            DMLog([NSString stringWithFormat:@"[k2] moved the last icon of the last page (index %lu) into the Dock at %lu: Dock %@ icons", (unsigned long)idx, (unsigned long)at, DMK2Num(dock, @"numberOfIcons")]);
                        } else DMLog(@"[k2] move: no icon / methods missing");
                    } else if (moved.count) {
                        NSArray *e = moved.lastObject; [moved removeLastObject];
                        ((void (*)(id, SEL, id))objc_msgSend)(dock, rm, @[e[0]]);
                        ((void (*)(id, SEL, id, NSUInteger, unsigned long long))objc_msgSend)(e[1], ins, @[e[0]], [e[2] unsignedIntegerValue], 0);
                        DMLog([NSString stringWithFormat:@"[k2] moved back to index %@ of its page: Dock %@ icons", e[2], DMK2Num(dock, @"numberOfIcons")]);
                    } else DMLog(@"[k2] back: nothing moved");
                } @catch (NSException *ex) { DMLog([NSString stringWithFormat:@"[k2] move: %@", ex.reason]); }
            } else if (!strcmp(word, "k2unobs") || !strcmp(word, "k2reobs")) {   // debug (K-2): SpringBoard's Dock controller stops / starts watching its Dock list (a list change it then misses = no resize)
                Class vcClass = objc_getClass("SBFloatingDockViewController"), dockClass = objc_getClass("SBFloatingDockView");
                id vc = nil;
                for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
                    if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
                    NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
                    while (todo.count && !vc) {
                        UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
                        if (!(dockClass && [v isKindOfClass:dockClass])) continue;
                        for (UIResponder *r = v; r && !vc; r = r.nextResponder) if (vcClass && [r isKindOfClass:vcClass]) vc = r;
                    }
                }
                id model = nil; @try { model = [vc valueForKey:@"dockListModel"]; } @catch (NSException *e) {}
                SEL sel = NSSelectorFromString(word[2] == 'u' ? @"removeListObserver:" : @"addListObserver:");
                if (vc && [model respondsToSelector:sel]) ((void (*)(id, SEL, id))objc_msgSend)(model, sel, vc);
                DMLog([NSString stringWithFormat:@"[k2] Dock controller %@ (%@) %s its Dock list %@", vc ? @"found" : @"missing", NSStringFromClass([vc class]), word[2] == 'u' ? "stopped watching" : "watches again", NSStringFromClass([model class])]);
            } else if (!strcmp(word, "k2edit1") || !strcmp(word, "k2edit0")) {   // debug (K-2): the Home Screen's edit mode on / off (the Dock's editing size changes with it)
                id mgr = DMObj(DMObj((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
                SEL se = NSSelectorFromString(@"setEditing:");
                if ([mgr respondsToSelector:se]) ((void (*)(id, SEL, BOOL))objc_msgSend)(mgr, se, word[6] == '1');
                DMLog([NSString stringWithFormat:@"[k2] edit mode %s (%@)", word[6] == '1' ? "on" : "off", mgr ? @"icon manager" : @"no icon manager"]);
            } else if (!strcmp(word, "metricslog")) {   // debug (K-2): every Dock layout-number call for the next 6 s (bounds, our scale and slots, the caller)
                gDMMetricsLogUntil = CACurrentMediaTime() + 6.0;
                DMLog(@"[metricslog] on for 6 s");
                DMRelayoutDock();
            } else if (!strcmp(word, "dockcap")) {   // debug (K-2): every Dock icon list -- how many icons its model holds and may hold, the view's own maximum,
                // its frame in the Dock window and each icon's frame there -- and the platter's frame, to see icons outside the Dock and a full Dock
                NSMutableArray *todo = [NSMutableArray array];
                for (UIWindow *w in [[UIApplication sharedApplication] valueForKey:@"windows"]) if ([NSStringFromClass([w class]) containsString:@"FloatingDock"]) [todo addObject:w];
                while (todo.count) {
                    UIView *v = todo.lastObject; [todo removeLastObject];
                    NSString *cn = NSStringFromClass([v class]);
                    if ([cn isEqualToString:@"SBFloatingDockPlatterView"]) {
                        NSMutableString *ours = [NSMutableString string];   // (our own views in it: Finder, Downloads, the second divider -- where they are)
                        for (UIView *sv in v.subviews) if (![NSStringFromClass([sv class]) hasPrefix:@"SB"] && ![NSStringFromClass([sv class]) hasPrefix:@"_"] && ![NSStringFromClass([sv class]) hasPrefix:@"MTMaterial"])
                            [ours appendFormat:@" %@ %@%@", NSStringFromClass([sv class]), NSStringFromCGRect(CGRectIntegral([v convertRect:sv.frame toView:v.window])), sv.hidden ? @"(hidden)" : @""];
                        DMLog([NSString stringWithFormat:@"[dockcap] platter %@ in its window; ours:%@", NSStringFromCGRect([v.superview convertRect:v.frame toView:v.window]), ours]);
                    }
                    if ([cn hasSuffix:@"IconListView"]) {
                        id lm = nil; @try { lm = [v valueForKey:@"model"]; } @catch (NSException *e) {}
                        NSString *mx = @"?", *cnt = @"?", *ic = @"?", *cols = @"?", *loc = @"?";
                        @try { mx = [[lm valueForKey:@"maxNumberOfIcons"] description]; } @catch (NSException *e) {}
                        @try { cnt = [[lm valueForKey:@"numberOfIcons"] description]; } @catch (NSException *e) {}
                        @try { ic = [[v valueForKey:@"maximumIconCount"] description]; } @catch (NSException *e) {}
                        @try { cols = [[v valueForKey:@"iconColumnsForCurrentOrientation"] description]; } @catch (NSException *e) {}
                        @try { loc = [[v valueForKey:@"iconLocation"] description]; } @catch (NSException *e) {}
                        NSMutableString *icons = [NSMutableString string];
                        for (UIView *iv in v.subviews) if ([NSStringFromClass([iv class]) hasSuffix:@"IconView"]) [icons appendFormat:@" %@%@", NSStringFromCGRect(CGRectIntegral([v convertRect:iv.frame toView:v.window])), iv.hidden ? @"(hidden)" : @""];
                        DMLog([NSString stringWithFormat:@"[dockcap] %@ (%@) model %@ holds %@ of max %@, view max %@, columns %@, frame %@ in its window; icons:%@", cn, loc, NSStringFromClass([lm class]), cnt, mx, ic, cols, NSStringFromCGRect([v.superview convertRect:v.frame toView:v.window]), icons]);
                    }
                    [todo addObjectsFromArray:v.subviews];
                }
            } else if (!strcmp(word, "recents")) {   // debug: what the Dock's recents model holds
                id m = gDMSuggestionsModel;
                NSMutableString *o = [NSMutableString stringWithFormat:@"[recents] debug: model %p", m];
                for (NSString *k in @[@"maxSuggestions", @"recentsEnabled", @"currentDisplayItems", @"currentRecentDisplayItems", @"currentAppSuggestion", @"requestedSuggestedApplication", @"recentsController.recentDisplayItems"]) {
                    id v = nil; @try { v = [m valueForKeyPath:k]; } @catch (NSException *e) { v = e.reason; }
                    [o appendFormat:@"\n  %@ = %@", k, [[v description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
                }
                // the recents' icon list (its own model decides how many icons it holds)
                NSMutableArray *todo = [NSMutableArray array];
                for (UIWindow *w in [[UIApplication sharedApplication] valueForKey:@"windows"]) if ([NSStringFromClass([w class]) containsString:@"FloatingDock"]) [todo addObject:w];
                while (todo.count) {
                    UIView *v = todo.lastObject; [todo removeLastObject];
                    if ([NSStringFromClass([v class]) containsString:@"SuggestionsIconListView"]) {
                        id lm = nil; @try { lm = [v valueForKey:@"model"]; } @catch (NSException *e) {}
                        NSString *mx = @"?", *cnt = @"?", *ic = @"?";
                        @try { mx = [[lm valueForKey:@"maxNumberOfIcons"] description]; } @catch (NSException *e) {}
                        @try { cnt = [[lm valueForKey:@"numberOfIcons"] description]; } @catch (NSException *e) {}
                        @try { ic = [[v valueForKey:@"maximumIconCount"] description]; } @catch (NSException *e) {}
                        DMLog([NSString stringWithFormat:@"[recents] debug: list view %@ model %@ maxNumberOfIcons %@ numberOfIcons %@ view max %@", NSStringFromClass([v class]), NSStringFromClass([lm class]), mx, cnt, ic]);
                        @try {
                            id loc = [v valueForKey:@"iconLocation"], prov = [v valueForKey:@"layoutProvider"];
                            SEL lf = NSSelectorFromString(@"layoutForIconLocation:");
                            id layout = [prov respondsToSelector:lf] ? ((id (*)(id, SEL, id))objc_msgSend)(prov, lf, loc) : nil;
                            id cfg = [layout respondsToSelector:NSSelectorFromString(@"layoutConfiguration")] ? [layout valueForKey:@"layoutConfiguration"] : nil;
                            DMLog([NSString stringWithFormat:@"[recents] debug: location %@ provider %@ layout %@ config %@ columns-now %@", loc, NSStringFromClass([prov class]), layout, [[cfg description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "], [v valueForKey:@"iconColumnsForCurrentOrientation"]]);
                        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recents] debug: layout: %@", e.reason]); }
                    }
                    [todo addObjectsFromArray:v.subviews];
                }
                DMLog(o);
            } else DMLog([NSString stringWithFormat:@"[escape] debug: escape action -> %d", DMDismissAppLibraryIfShowing()]);
        });
        dispatch_resume(escapeTimer);
    });   // test helpers only when this flag file exists
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ %init(SwipeUpFix); });
    DMLoadPrefs();
    DMStartRunningIndicatorPoll();   // periodic dot resync (RunningIndicator.m) -- catches Force Quit All / 3D-Touch quit / App Switcher, not just layoutSubviews
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    DMPrefsChanged, DM_NOTIFY, NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}
