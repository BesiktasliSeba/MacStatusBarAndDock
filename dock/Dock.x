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
#import <dlfcn.h>   // (1.7.3: MacStatusBar's Activity Monitor in the Dock, MSBDActMonDockRemove)
#include "../common/DockSide.h"   // (Settings > Dock > Position, 1.8.2: the rules of the Dock at a screen side)
#include "../common/DockBounce.h"   // (Settings > Dock > Animate Opening Applications, 1.8.4 item 2: the bounce's rules -- Bounce.m draws it)
#include "../common/DockStyle.h"    // (Settings > Dock > Dock Style, 1.8.4 item 3: Glass Shelf and Frosted -- DockStyle.m draws them)
#include "../common/DockAutoHide.h" // (Settings > Dock > Automatically Hide and Show the Dock, 1.8.4 item 4 -- DockAutoHide.m)
#include "../common/DockAppLibrary.h"   // (Apple's Show App Library in Dock from our Dock page, at once: 1.8.4.1 item 2)
#include "../common/DockHover.h"   // (the hover magnification held through UIKit's cancel under a resting pointer: 1.8.4.1)
extern void DMDockStyleApply(UIView *platter);
extern void DMDockStyleFollow(UIView *platter);
extern void DMDockStyleSetChoice(int style);
extern void DMDockStyleRefreshAll(void);

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
static BOOL    gShowTrash = NO;         // the Trash at the Dock's right end, after Downloads, like a Mac (TrashIcon.m; Settings > Dock > Show Trash in Dock, off by default)
static BOOL    gTrashFinderRuns = NO;   // (Finder runs, so a Trash may show at all: an external display's Dock shows it even with the switch off, DMDockShowsTrash)
static BOOL DMDockShowsTrash(UIView *dockView);   // (the Trash on this Dock: below, after DMDockOnMainScreen)
static BOOL    gEscapeClosesLibrary = YES;   // pressing Escape closes the App Library
static BOOL    gLaunchpadIcon = YES;    // the App Library icon drawn like macOS Launchpad
static BOOL    gLaunchpadClassic = YES; // round rocket (YES) or the silver grid tile (NO)
static BOOL    gLaunchpadLeft = YES;    // Launchpad at the Dock's start, next to Finder, like macOS (default on for everyone, owner 2 Oct; off: at the end, as iPadOS puts the App Library)
static BOOL    gBlockSwipeUp  = YES;    // stop an upward swipe on the Home Screen from opening the App Library
static BOOL    gPortraitLarger = YES;   // in portrait the (shrunk) Dock grows to the widest size that fits the screen
static BOOL    gSwipeDownOpensLibrary = YES;   // a downward swipe on the Home Screen opens the App Library (our own replacement for Lynx's "replace Spotlight")
static BOOL    gLastPageOpensLibrary = NO;     // swiping past the last Home Screen page opens the App Library, as iPadOS does (KT, 1.7.8: off unless switched on)
static int     gDockPosition = MSBDDockBottom; // Settings > Dock > Position (1.8.2, common/DockSide.h): Left or Right apply in landscape; the bottom when the Dock part is off
int            gDockSideApplied = 0;           // the side the Dock stands on now (0: the bottom, as ever); RunningIndicator.m and Downloads.m read it too

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
static CFTimeInterval gDMDockTouchAt = -1.0;   // (the last touch SpringBoard saw begin: a hover cancel just after it is the touch's, common/DockHover.h)
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
    BOOL finderRuns = YES;
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
            if (b != want[k]) finderRuns = NO;
        }
    }
    gShowFinder = finder && finderRuns;
    // Show Trash in Dock (on unless switched off since 1.8.6 -- new installs; an update keeps it off where it was never set: the root helper's
    // OldDefaults writes NO, KT 10 Nov): the Trash is Finder's (statusbar/DockTrash.h), so it is there only while Finder runs, as Finder's icon
    BOOL trash = YES;
    CFPropertyListRef tr = DMCopyPref(CFSTR("showTrash"));
    if (tr) { if (CFGetTypeID(tr) == CFBooleanGetTypeID()) trash = CFBooleanGetValue(tr); CFRelease(tr); }
    gShowTrash = trash && finderRuns;
    gTrashFinderRuns = finderRuns;
    {
        int pos = MSBDDockBottom;
        CFPropertyListRef dp = DMCopyPref(CFSTR(kMSBDDockPositionKey));
        if (dp) {
            char b[16];
            if (CFGetTypeID(dp) == CFStringGetTypeID() && CFStringGetCString((CFStringRef)dp, b, sizeof b, kCFStringEncodingUTF8)) pos = MSBDDockPositionFromString(b);
            CFRelease(dp);
        }
        gDockPosition = tweakOn ? pos : MSBDDockBottom;
    }
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
    // Swipe Past Last Page Opens App Library (Settings > Home Screen & Dock / & App Library, KT 1.7.8): off unless switched on, for every user
    CFPropertyListRef lpl = DMCopyPref(CFSTR("lastPageOpensLibrary"));
    gLastPageOpensLibrary = lpl && CFGetTypeID(lpl) == CFBooleanGetTypeID() && CFBooleanGetValue(lpl);
    if (lpl) CFRelease(lpl);
    {   // Animate Opening Applications (1.8.4 item 2): on unless switched off, for every user (KT 7 Nov; common/DockBounce.h); with the Dock part on only
        extern void DMBounceSetOn(BOOL on);
        CFPropertyListRef ao = DMCopyPref(CFSTR(kMSBDAnimateOpeningKey));
        BOOL isBool = ao && CFGetTypeID(ao) == CFBooleanGetTypeID();
        DMBounceSetOn(MSBDAnimateOpeningOn(isBool, isBool && CFBooleanGetValue(ao)) && tweakOn);
        if (ao) CFRelease(ao);
    }
    {   // Automatically Hide and Show the Dock (1.8.4 item 4): off unless switched on (common/DockAutoHide.h); with the Dock part on only
        extern void DMDockAutoHideSetOn(BOOL on);
        CFPropertyListRef ah = DMCopyPref(CFSTR(kMSBDAutoHideKey));
        BOOL isBool = ah && CFGetTypeID(ah) == CFBooleanGetTypeID();
        DMDockAutoHideSetOn(MSBDAutoHideOn(MSBDAutoHideStored(isBool, isBool && CFBooleanGetValue(ah))) && tweakOn);
        if (ah) CFRelease(ah);
    }
    {   // Dock Style (1.8.4 item 3): "glass" or "frosted", else Default (iPadOS's own platter); Default with the Dock part off
        CFPropertyListRef ds = DMCopyPref(CFSTR(kMSBDDockStyleKey));
        char b[16] = {0};
        int style = (ds && CFGetTypeID(ds) == CFStringGetTypeID() && CFStringGetCString((CFStringRef)ds, b, sizeof b, kCFStringEncodingUTF8)) ? MSBDDockStyleFromString(b) : MSBDDockStyleDefault;
        if (ds) CFRelease(ds);
        DMDockStyleSetChoice(tweakOn ? style : MSBDDockStyleDefault);
    }

    DMLog([NSString stringWithFormat:@"[prefs] enabled=%d magnification=%.3f iconSize=%.2f bottomGap=%.1f blockSwipeUp=%d downloads=%d trash=%d launchpad=%d swipeDownOpensLibrary=%d lastPageOpensLibrary=%d", enabled, mag, gIconSize, gBottomGap, blockUp, downloads, gShowTrash, launchpad, swipeDown, gLastPageOpensLibrary]);
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
extern void DMEditProxiesApply(UIView *platter, BOOL editing, BOOL animated, BOOL launchpadIcon, BOOL launchpadClassic, BOOL logAlways);   // (EditProxy.m: Edit Home Screen, 1.8.3 item 5)
extern BOOL DMEditProxiesOn(UIView *platter);   // (that Dock editing now)
extern BOOL DMEditProxyIs(UIView *v);   // (one of those icon views)
extern void DMEditProxyMagnify(UIView *library, CGFloat s);   // (the App Library icon's magnification on its Launchpad stand-in while editing)
extern void DMEditProxiesThemeChangedAll(void);
extern NSString *const DMIconThemeChangedNotification;   // (IconTheme.m: a theme engine refreshed its pictures)
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
static CGRect gTrashSlot = {{0, 0}, {0, 0}};       // where the Trash goes: after Downloads, the Dock's right end (set by getMetrics)
extern void DMTrashAttach(UIView *platter, CGRect slot, BOOL show);
extern UIView *DMTrashIcon(UIView *platter);
#import "../common/DockTrash.h"   // (MSBDDockEndLayout: Downloads and the Trash at the Dock's end)
#import "../common/CCController.h"   // (MSBDControlCenterController: Control Center's controller -- iPadOS 18 has no shared instance)

// A second divider between the recent apps and the Downloads stack, like macOS has before its Downloads/Trash end (2026-09-25). getMetrics makes
// room for it (the same gap the Dock keeps around its own divider: one icon spacing on each side of a 1 pt line) and sets its place here; it is
// drawn as a copy of SpringBoard's own divider view (same colour, blending, alpha and height, re-copied at every layout and style update). It
// only exists with Downloads or the Trash on (1.7.0: the Trash alone has it too, as on macOS). With no recents the Dock hides its own line, and
// ours is then the only line (apps | Downloads, Trash, as on macOS): there are never two lines side by side.
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
    BOOL want = native.superview && (gShowDownloads || DMDockShowsTrash(dockView)) && gDivider2Rect.size.height > 1.0 && (gDivider2Alone || !native.hidden);
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
static BOOL DMDockSideDismissTouch(id controller, UITouch *touch);   // (Settings > Dock > Position, below)
static BOOL DMDockSideControls(id controller);   // (... the controller of the Dock at a side)
static BOOL gHoverEasedByTouch = NO;   // (a touch eased the magnification out with the pointer still on the Dock: Downloads asks about the pointer, not the magnification, review 1.8.4.1 L4)
BOOL DMDockPointerHovering(void) { return gHovering || gHoverEasedByTouch; }
%hook SBFloatingDockController
// A finger on the screen outside the Dock (over a full-screen app) makes SpringBoard put the Dock away through its system "dismiss floating dock"
// gesture -- a finger scroll inside the open Downloads panel counted as that, and the Dock left with the panel (M1 regression pass, 0.3.18-14). While
// the panel is open, that gesture may not begin for a touch inside the panel; a touch anywhere else still puts the Dock (and the panel) away.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    extern BOOL DMDownloadsPanelContainsTouch(UITouch *touch);
    if (gKeepDockVisible && [self respondsToSelector:@selector(dismissFloatingDockSystemGestureRecognizer)]
        && g == ((id (*)(id, SEL))objc_msgSend)(self, @selector(dismissFloatingDockSystemGestureRecognizer)) && DMDownloadsPanelContainsTouch(touch)) return NO;
    // (Apple's answer for that gesture compares the touch's y with the Dock's top, read on 18.5: with the Dock at a side nearly every touch on the app
    //  was "on the Dock" and the Dock stayed out, and where it said yes the touch could be on the Dock's own icons -- its location means nothing across the
    //  turned view, so a tap on an icon could put the Dock away (code review 1.8.2, 9). There the rest of Apple's rule decides alone, what it asks before the
    //  y: the Dock out, no Today View, a touch on no part of the Dock)
    if (DMDockSideControls(self) && [self respondsToSelector:@selector(dismissFloatingDockSystemGestureRecognizer)]
        && g == ((id (*)(id, SEL))objc_msgSend)(self, @selector(dismissFloatingDockSystemGestureRecognizer))) return DMDockSideDismissTouch(self, touch);
    return %orig;
}
- (void)_handleDismissFloatingDockHoverGesture:(id)gesture {
    if (gKeepDockVisible) { gDockHoverDismissBlocked = YES; static int told = 0; if (told++ < 50) DMLog(@"[downloads] the pointer left the Dock while the panel is open: the Dock stays"); return; }
    // (Settings > Dock > Position: Apple's rule here is the bottom's, read on 18.5 -- the pointer more than 1.5 Dock heights above the screen's bottom edge puts the
    //  Dock away. With the Dock at a side that is a pointer anywhere above the bottom strip, on the side Dock itself too: brought out at the side's middle, it
    //  went at once. There our look at the pointer decides, with Apple's distance from the side (DMDockSidePointerSeen), and a finger's Dock stays Apple's
    //  tap-away. Code review 1.8.2, 1. A TV's Dock stays at its bottom with Apple's rule)
    if (DMDockSideControls(self)) { static int told = 0; if (told++ < 20) DMLog(@"[dockside] Apple's hover dismissal (the bottom's rule) stands down for the Dock at a side"); return; }
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
// ---- Settings > Dock > Position (1.8.2, KT 5 Nov; common/DockSide.h; plans/dock-side-build.md) ----------------------------------------------------------
// The Dock on the screen's left or right in landscape. Apple keeps the whole Dock in the Dock view controller's view: the root view controller gives that view
// its bounds and centre (-[SBFloatingDockRootViewController viewDidLayoutSubviews]: setBounds:, setCenter:, never a frame), and inside it the Dock view
// gets its place from those bounds and "away" as a plain translation (-[SBFloatingDockViewController viewDidLayoutSubviews]; read on 18.5 and 16.7.7). So
// that one view (the "host") gets the other shape's bounds and a turn: Apple's code lays the Dock out at its bottom and slides it away downwards, and
// that bottom is the screen's side. Everything along the Dock (the lists, a drop's place, the magnification: they read their own x) keeps working in its
// own coordinates. Each icon's content is turned back with its layer's sublayerTransform, which leaves the view's own transform to the magnification and to
// Apple. The App Library is not in the host and stays upright. On the bottom nothing of this runs: no hook is installed until Left or Right is chosen.
static __weak UIWindow *gDockWindow;
static BOOL DMDockOnMainScreen(UIWindow *w);
// The Trash on a given Dock (1.8.6, KT 10 Nov): the iPad's Dock follows Show Trash in Dock; an external display's Dock (a TV) shows it by default even
// with the switch off, as a Mac's desktop always has it (the per-display switch comes with 1.8.7's Display Settings). Only while Finder runs (the
// Trash is Finder's). A Dock not in a window yet counts as the iPad's.
static BOOL DMDockShowsTrash(UIView *dockView) {
    if (gShowTrash) return YES;
    if (!gTrashFinderRuns) return NO;
    UIWindow *w = dockView.window;
    return w && !DMDockOnMainScreen(w);
}
static BOOL DMIsDockIcon(UIView *icon);
static __weak UIView *gDockSideHost = nil;
static __weak UIViewController *gDockSideRoot = nil;   // (Apple's root view controller for the Dock: the Dock window's own on 16 and 18, a child of it on 15.6.1)
static BOOL gDockSideEver = NO;      // (a side was in use since SpringBoard started: icons may need their turn taken back)
static CGFloat gDockSideStep = 0;    // (the distance between neighbouring icons along the Dock: MSBDDockIconTakesTouch)
static void DMDockSidePointerArm(double seconds);
static BOOL gDockSideAsAtBottom = NO;   // (a question about the Dock as it would be at the bottom, DMDockSideHeightAtBottom)
static inline int DMDockSideOf(UIView *dockView) {
    if (!gDockSideApplied || gDockSideAsAtBottom || !gDockSideHost) return 0;
    for (UIView *v = dockView.superview; v; v = v.superview) if (v == gDockSideHost) return gDockSideApplied;
    return 0;
}
// (a view in the Dock that stands at a side, the host: never in a TV's Dock, which has a platter of its own and stays at its bottom -- code review 1.8.2, 4)
static inline BOOL DMDockSideInHost(UIView *v) { UIView *host = gDockSideHost; return host && [v isDescendantOfView:host]; }
int DMDockStylePlatterSide(UIView *platter) { return gDockSideApplied && platter && DMDockSideInHost(platter) ? gDockSideApplied : 0; }   // (DockStyle.m: Glass Shelf's side look)
static double DMDockSideBar(void) {   // (the menu bar's height: MacStatusBar's, while it runs)
    static double (*f)(void) = NULL; static int tries = 0;
    if (!f && tries < 40) { tries++; f = (double (*)(void))dlsym(RTLD_DEFAULT, "MSBDMenuBarHeightNow"); }
    double h = f ? f() : 24.0;
    return isfinite(h) && h > 0 ? h : 24.0;
}
static CATransform3D DMDockSideIconTurn(int side) { return CATransform3DMakeAffineTransform(MSBDDockSideIconTransform(side)); }
// An icon's turn is ours alone (common/DockSide.h MSBDDockSideIconTurnStep): it goes on top of what the layer has -- another tweak's value, Atria's icon scale --,
// which is kept and given back exactly; an icon we never turned is never written. Before, every icon's layout once a side had been used wrote the identity:
// KT's Atria Home Screen icons lost their 0.819 scale, at Left, Right and back at Bottom (1.8.2 engines check, M1).
static const void *kDockSideTurnUnder = &kDockSideTurnUnder, *kDockSideTurnOurs = &kDockSideTurnOurs, *kDockSideTurnSide = &kDockSideTurnSide;
// The side whose turn an icon's content carries now: ours there and still what its layer has; 0 for none (the bottom, a TV's Dock, an icon not turned yet). The
// running dot goes where the content stands upright by this (RunningIndicator.m, FinderIcon.m), so the two never part: decided apart -- the dot by the icon's
// screen and the side chosen, the turn by the icon's place in the side Dock, each at its own time -- a recents change at Right showed a Clock icon's dot under the
// icon, the Bottom place (M1 F5, 1.8.2.2), and a Handoff tile not yet turned (its badge at the bottom left).
int MSBDDockSideIconTurnSide(UIView *icon) {
    NSValue *ours = icon ? objc_getAssociatedObject(icon, kDockSideTurnOurs) : nil;
    if (!ours || !CATransform3DEqualToTransform(icon.layer.sublayerTransform, ours.CATransform3DValue)) return 0;
    return [objc_getAssociatedObject(icon, kDockSideTurnSide) intValue];
}
extern void DMUpdateRunningIndicator(UIView *iconView);
static void DMDockSideDotFollows(UIView *icon) {   // (its dot placed again for the turn it has now: an app icon's, or our own icon's -- Finder)
    if ([icon isKindOfClass:objc_getClass("SBIconView")]) DMUpdateRunningIndicator(icon);
    else if ([icon respondsToSelector:NSSelectorFromString(@"updateDot")]) ((void (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"updateDot"));
}
#if DEBUG
static BOOL gDMTurnOurs = NO;   // (debug: a write of the turn's is ours -- the turn watch, "turnwatch" in /tmp/dockmag-escape, logs every other one)
#define DM_TURN_OURS(...) do { gDMTurnOurs = YES; __VA_ARGS__ gDMTurnOurs = NO; } while (0)
#else
#define DM_TURN_OURS(...) do { __VA_ARGS__ } while (0)
#endif
static void DMDockSideStyleIcon(UIView *icon, int side) {
    if (DMEditProxyIs(icon)) return;   // (Edit Home Screen's icon views of ours: our items' are in their own view, which is turned; the Launchpad one has the App Library icon's turn, copied -- EditProxy.m EPFollow. A turn of ours on top turned them twice, on their side: audit 1.8.3 M2)
    CALayer *l = icon.layer;
    NSValue *ours = objc_getAssociatedObject(icon, kDockSideTurnOurs), *under = objc_getAssociatedObject(icon, kDockSideTurnUnder);
    BOOL turned = ours != nil, still = turned && CATransform3DEqualToTransform(l.sublayerTransform, ours.CATransform3DValue);
    switch (MSBDDockSideIconTurnStep(turned, still, side)) {
        case MSBDIconTurnApply: {
            CATransform3D below = MSBDDockSideIconTurnUnderKept(turned, still) ? (under ? under.CATransform3DValue : CATransform3DIdentity) : l.sublayerTransform;
            CATransform3D want = CATransform3DConcat(below, DMDockSideIconTurn(side));
            if (still && CATransform3DEqualToTransform(want, ours.CATransform3DValue)) return;   // (as it is)
            objc_setAssociatedObject(icon, kDockSideTurnUnder, [NSValue valueWithCATransform3D:below], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnOurs, [NSValue valueWithCATransform3D:want], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnSide, @(side), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DM_TURN_OURS(if (!CATransform3DEqualToTransform(l.sublayerTransform, want)) l.sublayerTransform = want;);
            DMDockSideDotFollows(icon);
            return;
        }
        case MSBDIconTurnGiveBack:
            DM_TURN_OURS(if (under && !CATransform3DEqualToTransform(l.sublayerTransform, under.CATransform3DValue)) l.sublayerTransform = under.CATransform3DValue;);
            objc_setAssociatedObject(icon, kDockSideTurnUnder, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnOurs, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnSide, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DMDockSideDotFollows(icon);
            return;
        case MSBDIconTurnForget:   // (its owner set another value since: theirs)
            objc_setAssociatedObject(icon, kDockSideTurnUnder, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnOurs, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(icon, kDockSideTurnSide, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DMDockSideDotFollows(icon);
            return;
        default: return;   // (never turned: not ours to write)
    }
}
// The turn a Dock icon's content has for its Dock's side now, by the rule SBIconView's layout hook turns them (below): beside a side Dock in the
// host, else none (the bottom, a TV's Dock). For EditProxy.m's Launchpad icon view in Edit Home Screen, which takes its turn from here: copied from
// the App Library icon's layer, a Dock layout caught that one without its turn and ours came out turned (M1 1.8.3.1 F-5).
CATransform3D DMDockSideTurnFor(UIView *icon) {
    return DMDockSideIconTurn(icon && gDockSideApplied && DMIsDockIcon(icon) && DMDockSideInHost(icon) ? gDockSideApplied : 0);
}
static BOOL DMDockSideIsOwnIcon(UIView *v) {
    Class own[3] = { objc_getClass("DMFinderIconView"), objc_getClass("DMDownloadsIconView"), objc_getClass("DMTrashIconView") };
    for (int i = 0; i < 3; i++) if (own[i] && [v isKindOfClass:own[i]]) return YES;
    return NO;
}
static void DMDockSideStyleAll(UIView *root, int side) {
    Class ic = objc_getClass("SBIconView");
    for (UIView *v in root.subviews) {
        if ((ic && [v isKindOfClass:ic]) || DMDockSideIsOwnIcon(v)) { DMDockSideStyleIcon(v, side); continue; }
        DMDockSideStyleAll(v, side);
    }
}
static void DMDockSideMeasureStep(UIView *platter) {   // (the shortest distance between neighbours in any row of the Dock)
    Class ic = objc_getClass("SBIconView");
    CGFloat step = 0;
    NSMutableArray<NSArray<UIView *> *> *rows = [NSMutableArray arrayWithObject:platter.subviews];
    for (UIView *v in platter.subviews) if (v.subviews.count && !(ic && [v isKindOfClass:ic]) && !DMDockSideIsOwnIcon(v)) [rows addObject:v.subviews];
    for (NSArray<UIView *> *row in rows) {
        NSMutableArray<NSNumber *> *xs = [NSMutableArray array];
        for (UIView *v in row) if (ic && [v isKindOfClass:ic] && !v.hidden) [xs addObject:@(v.center.x)];
        [xs sortUsingSelector:@selector(compare:)];
        for (NSUInteger i = 1; i < xs.count; i++) { CGFloat d = xs[i].doubleValue - xs[i - 1].doubleValue; if (d > 8.0 && (step == 0 || d < step)) step = d; }
    }
    gDockSideStep = step;
}
// The host's bounds as Apple sets them (the root's own shape, every root layout): the other shape while a side is in use. Hooked on the host's own class the
// first time a side is used: on 18.5 an SBHTouchPassThroughView, on 16.7.7 an SBFTouchPassThroughView like the root's, so the view is told apart by itself.
static void (*o_DockSideHostSetBounds)(id, SEL, CGRect);
static void DMDockSideHostSetBounds(id self, SEL _cmd, CGRect b) {
    if (gDockSideApplied && self == gDockSideHost && b.size.width > b.size.height) b.size = CGSizeMake(b.size.height, b.size.width);
    o_DockSideHostSetBounds(self, _cmd, b);
}
// A folder in the Dock opens in the Dock's own view, the host: its outer container is the host's child. Over the screen it stands upright and in the screen's shape with
// the host's turn taken back.
static void DMDockSideFoldersUpright(UIView *host, int side) {
    Class fc = objc_getClass("SBFolderContainerView");
    if (!fc) return;
    CGSize s = host.bounds.size, want = side ? CGSizeMake(s.height, s.width) : s;
    CGAffineTransform turn = MSBDDockSideIconTransform(side);
    for (UIView *v in host.subviews) {
        if (![v isKindOfClass:fc] || (CGAffineTransformEqualToTransform(v.transform, turn) && CGSizeEqualToSize(v.bounds.size, want))) continue;
        DM_FEATURE_MARK("dock-side-folder");
        [UIView performWithoutAnimation:^{
            v.transform = turn;
            v.bounds = CGRectMake(0, 0, want.width, want.height);
            v.center = CGPointMake(s.width / 2.0, s.height / 2.0);
        }];
        DMLog([NSString stringWithFormat:@"[dockside] a folder's container in the Dock's view: bounds %@, transform %@", NSStringFromCGRect(v.bounds), NSStringFromCGAffineTransform(v.transform)]);
    }
}
static void DMDockSideHomeRelayout(NSString *why);   // (the Home Screen's pages, below)
// The Dock's own view in the host (SBFloatingDockView): the host's child, or deeper in views of the host's own kind.
static UIView *DMDockSideDockViewIn(UIView *host) {
    NSMutableArray<UIView *> *look = host ? [NSMutableArray arrayWithObject:host] : [NSMutableArray array];
    while (look.count) {
        UIView *v = look.firstObject; [look removeObjectAtIndex:0];
        if ([NSStringFromClass([v class]) isEqualToString:@"SBFloatingDockView"]) return v;
        if (v == host || [v isKindOfClass:[host class]]) [look addObjectsFromArray:v.subviews];
    }
    return nil;
}
static void DMDockSideApplyToRoot(UIViewController *root) {
    if (!root.isViewLoaded) return;
    UIWindow *w = root.view.window;
    if (!w || !DMDockOnMainScreen(w)) return;   // (a TV's Dock stays at its bottom)
    SEL vcSel = NSSelectorFromString(@"floatingDockViewController");
    id dvc = [root respondsToSelector:vcSel] ? ((id (*)(id, SEL))objc_msgSend)(root, vcSel) : nil;
    UIView *host = [dvc isKindOfClass:[UIViewController class]] ? ((UIViewController *)dvc).view : nil;
    if (!host) return;
    CGRect rb = root.view.bounds;
    int side = MSBDDockSideFor(gDockPosition, rb.size.width, rb.size.height);
    BOOL changed = side != gDockSideApplied || host != gDockSideHost;
    if (!side && !changed) return;
    if (!gDockWindow) gDockWindow = w;
    // (on its class itself: under key-value observing the isa is a subclass made for the observers, and once they went the real class -- not hooked -- took
    //  Apple's landscape bounds again, the Dock laid out the wrong way until a respring; code review 1.8.2, 11)
    if (side && !o_DockSideHostSetBounds) MSHookMessageEx([host class], @selector(setBounds:), (IMP)DMDockSideHostSetBounds, (IMP *)&o_DockSideHostSetBounds);
    gDockSideHost = host; gDockSideRoot = root; gDockSideApplied = side;
    if (side) gDockSideEver = YES;
    [UIView performWithoutAnimation:^{   // (no swing across the screen when a turn asks for it inside its own animation)
        host.bounds = side ? CGRectMake(0, 0, rb.size.height, rb.size.width) : rb;
        host.center = CGPointMake(CGRectGetMidX(rb), CGRectGetMidY(rb));
        host.transform = MSBDDockSideHostTransform(side);
        if (changed) {
            DMDockSideStyleAll(host, side);
            [host setNeedsLayout]; [host layoutIfNeeded];
            // (and the Dock itself. Its layout reads the side (the platter in the room under the menu bar at a side, in the middle at the bottom; the icons'
            //  size share), and UIKit lays it out only when its bounds change. Between portrait and a side they don't: the host's bounds at a side are the
            //  other shape's, which are portrait's, so a turn changed only the host's turn and the Dock kept its other place until something laid it out
            //  again: at a side 18.5 pt high, under the bar, after a layout in portrait; in portrait off the middle by as much after one at a side. A12Z 18.5)
            UIView *dockView = DMDockSideDockViewIn(host);
            [dockView setNeedsLayout]; [dockView layoutIfNeeded];
        }
    }];
    DMDockSideFoldersUpright(host, side);
    if (changed) {
        DM_FEATURE_MARK("dock-side");
#if DEBUG
        UIView *dv = DMDockSideDockViewIn(host), *platter = nil; @try { platter = [dv valueForKey:@"mainPlatterView"]; } @catch (id e) {}
        CGRect pr = [platter isKindOfClass:[UIView class]] ? [platter convertRect:platter.bounds toView:host] : CGRectNull;   // (the host's x runs along the Dock; the screen may still have the old turn here)
        DMLog([NSString stringWithFormat:@"[dockside] side %d: host %@ bounds %@, root %@; the Dock laid out for it: its platter %.1f..%.1f along it", side, NSStringFromClass([host class]), NSStringFromCGRect(host.bounds), NSStringFromCGRect(rb), CGRectGetMinX(pr), CGRectGetMaxX(pr)]);
#endif
        if (side) DMDockSidePointerArm(0.25);
        DMDockSideHomeRelayout(side ? @"the Dock at a side" : @"the Dock at the bottom");
    }
}
// How tall the Dock would be at the bottom, for what is laid out around it there and stays put (the Home Screen's icons): Apple's own question to the Dock's view,
// for the long side, answered as at the bottom. What that answer leaves in the slots is put back (they are the side Dock's). -1: the view can't say.
static CGFloat DMDockSideHeightAtBottom(void) {
    // (the host, held for this question: it is weak, and the side stays applied until the next root layout -- a Dock view controller made again in between,
    //  a display or Stage Manager change, left it nil while the Home Screen and the desktop's files still asked: an array of nil, SpringBoard down. Code review
    //  1.8.2, 3. No host: Apple's height)
    UIView *host = gDockSideHost;
    if (!host) return -1.0;
    UIView *dockView = DMDockSideDockViewIn(host);
    SEL q = NSSelectorFromString(@"contentHeightForBounds:");
    Method m = dockView ? class_getInstanceMethod(object_getClass(dockView), q) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "d48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16")) return -1.0;
    CGSize s = host.bounds.size;
    CGRect saveF = gFinderSlot, saveD = gDownloadsSlot, saveT = gTrashSlot, saveV = gDivider2Rect; BOOL saveA = gDivider2Alone, saveO = gDownloadsOwnSlot;
    gDockSideAsAtBottom = YES;
    CGFloat h = ((CGFloat (*)(id, SEL, CGRect))objc_msgSend)(dockView, q, CGRectMake(0, 0, MAX(s.width, s.height), MIN(s.width, s.height)));
    gDockSideAsAtBottom = NO;
    gFinderSlot = saveF; gDownloadsSlot = saveD; gTrashSlot = saveT; gDivider2Rect = saveV; gDivider2Alone = saveA; gDownloadsOwnSlot = saveO;
    return isfinite(h) && h > 0.0 ? h : -1.0;
}
__attribute__((visibility("default"))) double MSBDDockHeightAtBottom(void) { return gDockSideApplied ? DMDockSideHeightAtBottom() : -1.0; }   // (MacStatusBar's desktop files: they stay where they are too)
__attribute__((visibility("default"))) int MSBDDockPositionChosen(void) { return gDockPosition; }   // (MacSettings' icon places: the bottom, also with the Dock part off -- nothing of the side Dock there)
static void DMDockSideRefresh(void) {
    Class c = objc_getClass("SBFloatingDockWindow"), rc = objc_getClass("SBFloatingDockRootViewController");
    for (UIWindow *x in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        if (!c || !rc || ![x isKindOfClass:c] || !DMDockOnMainScreen(x) || !x.rootViewController) continue;
        NSMutableArray<UIViewController *> *look = [NSMutableArray arrayWithObject:x.rootViewController];
        while (look.count) {
            UIViewController *vc = look.firstObject; [look removeObjectAtIndex:0];
            if ([vc isKindOfClass:rc]) { DMDockSideApplyToRoot(vc); [vc.view setNeedsLayout]; break; }
            [look addObjectsFromArray:vc.childViewControllers];
        }
    }
}
// ---- the Home Screen with the Dock at a side (common/DockSide.h MSBDDockSideHomeListFrame, KT 5 Nov) ----
// No Home Screen icon, folder or widget under the Dock: the room the Dock takes from its side comes out of the free space beside the icons. Each page's icon list
// is placed by SBRootFolderView's own -_iconListFrameForPageRect:atIndex: (hooked below, with a side chosen only): moved, its size kept, so iPadOS and any layout
// tweak (Atria and the like lay out inside the list, by its insets) keep their layout's shape. The room is the Dock's at rest, as the side Dock last laid out:
// its gap and its platter, so Icon Size, the gap and the apps it holds move the pages at once; the magnified icons grow over the Home Screen for a moment, as
// on a Mac, and move nothing. In portrait and at the bottom the frames are iPadOS's own (decided by each page's own shape: a turn lays the pages out for the
// new shape before the Dock hears of it).
static id DMObj(id o, NSString *sel);   // (below)
static id DMDockSideController(void);   // (below)
static CGFloat gDockSideHomeRoom = 0;    // (how far the side Dock reaches into the screen at rest; 0 until it has laid out at a side)
static BOOL gDockSideHomeHooked = NO, gDockSideHomeAsking = NO;
static UIView *DMDockSideHomeRootView(void) {
    Class c = objc_getClass("SBIconController"); SEL e = NSSelectorFromString(@"sharedInstanceIfExists");
    id ic = c && [(id)c respondsToSelector:e] ? ((id (*)(id, SEL))objc_msgSend)((id)c, e) : DMObj((id)c, @"sharedInstance");   // (17+: never made by us)
    id rfc = DMObj(DMObj(ic, @"iconManager"), @"rootFolderController");
    id v = DMObj(rfc, @"rootFolderView") ?: DMObj(rfc, @"folderView");
    return [v isKindOfClass:[UIView class]] ? v : nil;
}
#if DEBUG
static void DMDockSideHomeCheck(NSString *why);   // (the safety check, below)
#endif
// The pages placed again: the room or the side changed (a setting, the Dock's apps, a turn). SpringBoard's own frame pass for its pages, inside a short animation.
static void DMDockSideHomeRelayout(NSString *why) {
    if (!gDockSideHomeHooked) return;
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending = NO;
        UIView *rfv = DMDockSideHomeRootView();
        SEL upd = NSSelectorFromString(@"_updateIconListFrames");
        Method m = rfv ? class_getInstanceMethod(object_getClass(rfv), upd) : NULL;
        if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v16@0:8")) return;
        DM_FEATURE_MARK("dock-side-home");
        static void (*followPage)(void) = NULL; static int tries = 0;   // (MacStatusBar's desktop files: they stay on their page of the screen, StatusBar's Desktop.h)
        if (!followPage && tries < 40) { tries++; followPage = (void (*)(void))dlsym(RTLD_DEFAULT, "MSBDDesktopFollowPage"); }
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            ((void (*)(id, SEL))objc_msgSend)(rfv, upd);
            [rfv setNeedsLayout];   // (its own pass too: Edit Home Screen's buttons, DMDockSideHomeEditButtons)
            [rfv layoutIfNeeded];
            if (followPage) followPage();
        } completion:nil];
        DMLog([NSString stringWithFormat:@"[dockside] the Home Screen's pages placed again (%@): the Dock %.1f pt in from the %@", why, gDockSideHomeRoom, gDockSideApplied == MSBDDockLeft ? @"left" : gDockSideApplied == MSBDDockRight ? @"right" : @"bottom (none)"]);
#if DEBUG
        DMDockSideHomeCheck(why);
#endif
    });
}
// The Dock at rest, from its side: the distance from its view's bottom (the screen's side edge) to its platter's inner edge, by the platter's place, not its
// presentation (the magnification turns icons, never the platter). -1: not readable.
static CGFloat DMDockSideRestingRoom(UIView *dockView, UIView *platter) {
    UIView *sv = platter.superview;
    if (!sv || !dockView) return -1.0;
    CGPoint top = [sv convertPoint:CGPointMake(platter.center.x, platter.center.y - platter.bounds.size.height / 2.0) toView:dockView];
    CGFloat room = CGRectGetMaxY(dockView.bounds) - top.y;
    // (only the view's bottom counts, the screen's side edge: the view itself may be the gap and the platter exactly -- 18.5 -- or for a moment smaller than the
    //  platter, which then reaches above its top -- 16.7.7 leaving Edit Home Screen, 52 pt for 54.5. A side Dock is never a quarter of its length thick.)
    return isfinite(room) && room > 1.0 && room < dockView.bounds.size.width * 0.25 ? room : -1.0;
}
static void DMDockSideHomeRoomSeen(CGFloat room) {
    if (!(room > 0.0) || fabs(room - gDockSideHomeRoom) <= 0.25) return;
    DMLog([NSString stringWithFormat:@"[dockside] the Dock at rest reaches %.1f pt in from its side (was %.1f)", room, gDockSideHomeRoom]);
    gDockSideHomeRoom = room;
    DMDockSideHomeRelayout(@"the Dock's size");
}
// A side Dock laid out. Its size is taken while it is out; laid out while away it may be in another state -- the App Library makes it larger for drops, away
// from the screen (M1 15.6.1: 48.4 pt against 46.1, A12Z 18.5: 63 against 59.8), back when it closes --, so that size waits and is taken when the Dock is out
// again (-floatingDockRootViewControllerDidEndPresentationTransition:, below), unless it laid out again out first: a setting changed with the Dock away is
// taken then. The Home Screen behind the App Library stays put. (The first size after a start is taken at once.)
static CGFloat gDockSideHomeRoomAway = 0;
static BOOL DMDockSidePresentedNow(void) {
    id c = DMDockSideController(); SEL s = NSSelectorFromString(@"isFloatingDockPresented");
    return [c respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(c, s);
}
static void DMDockSideHomeLaidOut(CGFloat room) {
    if (!(room > 0.0)) return;
    if (DMDockSidePresentedNow() || !(gDockSideHomeRoom > 0.0)) { gDockSideHomeRoomAway = 0; DMDockSideHomeRoomSeen(room); }
    else gDockSideHomeRoomAway = room;
}
static void DMDockSideHomeDockBack(void) {
    if (!(gDockSideHomeRoomAway > 0.0) || !gDockSideApplied || !DMDockSidePresentedNow()) return;
    CGFloat room = gDockSideHomeRoomAway; gDockSideHomeRoomAway = 0;
    DMDockSideHomeRoomSeen(room);
}
// A page's icon list frame with the Dock at a side: the layout's free space read from that list's insets (as SpringBoard lays the icons out with them, Atria's
// too), the room taken from it in each side's share. As iPadOS gives it in portrait, at the bottom, and before the side Dock has laid out once.
static CGRect DMDockSideHomeFrame(UIView *rfv, CGRect f, unsigned long long index) {
    if (gDockPosition == MSBDDockBottom || !(gDockSideHomeRoom > 0.0) || gDockSideHomeAsking) return f;
    int side = MSBDDockSideFor(gDockPosition, f.size.width, f.size.height);
    if (!side || (rfv.window && !DMDockOnMainScreen(rfv.window))) return f;
    SEL at = NSSelectorFromString(@"iconListViewAtIndex:"), ins = NSSelectorFromString(@"layoutInsetsForOrientation:"), lo = NSSelectorFromString(@"layoutOrientation");
    if (![rfv respondsToSelector:at]) return f;
    gDockSideHomeAsking = YES;   // (nothing below may come back here)
    UIView *list = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(rfv, at, index);
    if (![list respondsToSelector:ins]) list = ((id (*)(id, SEL, unsigned long long))objc_msgSend)(rfv, at, 0);   // (a page not made yet: the first page's layout)
    Method m = [list isKindOfClass:[UIView class]] ? class_getInstanceMethod(object_getClass(list), ins) : NULL;
    BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{UIEdgeInsets=dddd}24@0:8q16");
    UIEdgeInsets i = UIEdgeInsetsZero;
    if (known) {
        long long o = [list respondsToSelector:lo] ? ((long long (*)(id, SEL))objc_msgSend)(list, lo) : 3;
        i = ((UIEdgeInsets (*)(id, SEL, long long))objc_msgSend)(list, ins, o == 3 || o == 4 ? o : 3);   // (the page is landscape: the landscape layout's)
    }
    gDockSideHomeAsking = NO;
    if (!known) return f;   // (nothing to keep the layout's shape by: as iPadOS gives it)
    double fl = 0, fr = 0;
    MSBDDockSideHomeFree(i.left, i.right, rfv.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft, &fl, &fr);
    return MSBDDockSideHomeListFrame(f, side, gDockSideHomeRoom, fl, fr);
}
// Edit Home Screen's own buttons (Add Widget at the top left, Done at the top right: SBRootFolderView's widgetButton and doneButton) keep out of the Dock the same
// way: the one on the Dock's side moves over by the room after SpringBoard has laid the view out, from SpringBoard's own frame for it each time (the frame it
// last had from SpringBoard is kept, so a layout that leaves it alone never moves it twice).
static const void *kDockSideHomeButtonBase = &kDockSideHomeButtonBase, *kDockSideHomeButtonSet = &kDockSideHomeButtonSet;
static void DMDockSideHomeEditButtons(UIView *rfv) {
    CGSize b = rfv.bounds.size;
    int side = gDockPosition != MSBDDockBottom && gDockSideHomeRoom > 0.0 ? MSBDDockSideFor(gDockPosition, b.width, b.height) : MSBDDockBottom;
    for (NSString *k in @[@"widgetButton", @"doneButton"]) {
        UIView *v = DMObj(rfv, k);
        if (![v isKindOfClass:[UIView class]] || v.superview != rfv) continue;
        NSValue *set = objc_getAssociatedObject(v, kDockSideHomeButtonSet), *base = objc_getAssociatedObject(v, kDockSideHomeButtonBase);
        CGRect apple = set && base && CGRectEqualToRect(v.frame, set.CGRectValue) ? base.CGRectValue : v.frame;   // (moved by us and left so: SpringBoard's is the kept one)
        CGRect f = apple;
        if (side == MSBDDockLeft && CGRectGetMinX(f) < gDockSideHomeRoom) f.origin.x += gDockSideHomeRoom;
        else if (side == MSBDDockRight && CGRectGetMaxX(f) > b.width - gDockSideHomeRoom) f.origin.x -= gDockSideHomeRoom;
        if (CGRectEqualToRect(f, v.frame)) continue;
        objc_setAssociatedObject(v, kDockSideHomeButtonBase, [NSValue valueWithCGRect:apple], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kDockSideHomeButtonSet, [NSValue valueWithCGRect:f], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.frame = f;
    }
}
#if DEBUG
// The safety check (debug builds): a moment after a Home Screen layout with the Dock at a side, every icon of every page (shown or not: the list's model, where the
// list puts it; a shown one where its view is) and the page dots, where they lie on the screen when their page shows, against the Dock at rest. Anything that
// still reaches under it is logged with its page and place (no app names); otherwise one line with the nearest distance, when that changes.
static void DMDockSideHomeCheckNow(NSString *why) {
    UIView *rfv = DMDockSideHomeRootView();
    int side = gDockSideApplied;
    if (!rfv.window || !side || !(gDockSideHomeRoom > 0.0)) return;
    UIScreen *screen = [UIScreen mainScreen]; id<UICoordinateSpace> scs = screen.coordinateSpace; CGFloat sw = screen.bounds.size.width;
    UIScrollView *scroll = nil;
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:rfv];
    for (NSUInteger k = 0; k < todo.count && k < 400 && !scroll; k++) { UIView *v = todo[k]; if ([v isKindOfClass:objc_getClass("SBIconScrollView")]) scroll = (UIScrollView *)v; else [todo addObjectsFromArray:v.subviews]; }
    CGFloat pw = scroll.bounds.size.width;
    if (!scroll || pw < 100.0) return;
    Class lc = objc_getClass("SBIconListView"), ivc = objc_getClass("SBIconView");
    SEL rfi = NSSelectorFromString(@"rectForIcon:");
    NSUInteger n = 0, pages = 0; CGFloat nearest = INFINITY;
    NSMutableString *under = [NSMutableString string];
    for (UIView *l in scroll.subviews) {
        if (!lc || ![l isKindOfClass:lc] || l.hidden) continue;
        long page = lround(l.frame.origin.x / pw);
        CGFloat dx = scroll.bounds.origin.x - page * pw;   // (where it lies when its page shows)
        NSMutableArray<NSValue *> *rects = [NSMutableArray array];
        NSMutableSet *shown = [NSMutableSet set];
        for (UIView *v in l.subviews) {
            if (!ivc || ![v isKindOfClass:ivc] || v.hidden || v.alpha < 0.01 || v.bounds.size.width < 5.0) continue;
            id icon = DMObj(v, @"icon"); if (icon) [shown addObject:icon];
            [rects addObject:[NSValue valueWithCGRect:CGRectOffset([v convertRect:v.bounds toCoordinateSpace:scs], dx, 0)]];
        }
        Method rm = class_getInstanceMethod(object_getClass(l), rfi);
        NSArray *icons = DMObj(DMObj(l, @"model"), @"icons");
        if (rm && !strcmp(method_getTypeEncoding(rm) ?: "", "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8@16") && [icons isKindOfClass:[NSArray class]])
            for (id icon in icons) if (![shown containsObject:icon]) [rects addObject:[NSValue valueWithCGRect:CGRectOffset([l convertRect:((CGRect (*)(id, SEL, id))objc_msgSend)(l, rfi, icon) toCoordinateSpace:scs], dx, 0)]];
        if (rects.count) pages++;
        NSUInteger k = 0;
        for (NSValue *rv in rects) {
            CGRect r = rv.CGRectValue; n++; k++;
            CGFloat d = side == MSBDDockLeft ? CGRectGetMinX(r) - gDockSideHomeRoom : sw - gDockSideHomeRoom - CGRectGetMaxX(r);
            nearest = MIN(nearest, d);
            if (MSBDDockSideHomeUnder(r, sw, side, gDockSideHomeRoom)) [under appendFormat:@" page %ld #%lu at x %.1f..%.1f;", page + 1, (unsigned long)k, CGRectGetMinX(r), CGRectGetMaxX(r)];
        }
    }
    [todo removeAllObjects]; [todo addObject:rfv];
    for (NSUInteger k = 0; k < todo.count && k < 600; k++) {
        UIView *v = todo[k]; NSString *cn = NSStringFromClass([v class]);
        if (([cn containsString:@"PageControl"] || [cn containsString:@"ScrollAccessory"]) && !v.hidden && v.alpha > 0.01) {
            if (MSBDDockSideHomeUnder([v convertRect:v.bounds toCoordinateSpace:scs], sw, side, gDockSideHomeRoom)) [under appendFormat:@" the page dots (%@);", cn];
            continue;
        }
        if (![v isKindOfClass:[UIScrollView class]]) [todo addObjectsFromArray:v.subviews];
    }
    NSString *line = under.length ? [NSString stringWithFormat:@"[dockside] Home Screen check: UNDER THE DOCK (%.1f pt in from the %@):%@ (%lu icons on %lu pages)", gDockSideHomeRoom, side == MSBDDockLeft ? @"left" : @"right", under, (unsigned long)n, (unsigned long)pages]
        : [NSString stringWithFormat:@"[dockside] Home Screen check: %lu icons on %lu pages clear of the Dock (%.1f pt in from the %@), the nearest %.1f pt from it", (unsigned long)n, (unsigned long)pages, gDockSideHomeRoom, side == MSBDDockLeft ? @"left" : @"right", nearest];
    static NSString *last = nil;
    if ([line isEqualToString:last]) return;
    last = line;
    DMLog([line stringByAppendingFormat:@" -- after %@", why]);
}
static void DMDockSideHomeCheck(NSString *why) {
    static BOOL pending = NO;
    if (pending || !gDockSideApplied) return;
    pending = YES;
    NSString *w = [why copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ pending = NO; DMDockSideHomeCheckNow(w); });
}
// (after every icon list's layout, with a side chosen only; outside Logos, so the debug-only hook stays out of the release diagnostics' list, common/HookList.h)
static void (*o_DockSideHomeListLayout)(id, SEL);
static void DMDockSideHomeListLayout(id self, SEL _cmd) {
    o_DockSideHomeListLayout(self, _cmd);
    if (gDockSideApplied && gDockSideHomeRoom > 0.0 && ((UIView *)self).window) DMDockSideHomeCheck(@"a Home Screen layout");
}
static void DMDockSideHomeCheckHook(void) {
    Class c = objc_getClass("SBIconListView");
    Method m = c ? class_getInstanceMethod(c, @selector(layoutSubviews)) : NULL;
    if (m && !o_DockSideHomeListLayout && !strcmp(method_getTypeEncoding(m) ?: "", "v16@0:8")) MSHookMessageEx(c, @selector(layoutSubviews), (IMP)DMDockSideHomeListLayout, (IMP *)&o_DockSideHomeListLayout);
}
#endif
// The controller of the Dock that stands at a side: the one whose Dock is on the iPad's own screen (a TV's Dock keeps its bottom, and Apple's rules there). One
// whose Dock can't be told is taken for it.
static BOOL DMDockSideControls(id controller) {
    if (!gDockSideApplied) return NO;
    SEL vcs = NSSelectorFromString(@"viewController");
    id vc = [controller respondsToSelector:vcs] ? ((id (*)(id, SEL))objc_msgSend)(controller, vcs) : nil;
    UIWindow *w = [vc isKindOfClass:[UIViewController class]] && ((UIViewController *)vc).isViewLoaded ? ((UIViewController *)vc).view.window : nil;
    return !w || DMDockOnMainScreen(w);
}
// A finger on the app with the Dock out at a side (see -gestureRecognizer:shouldReceiveTouch:): what Apple asks before its y rule, read on 18.5 and in the
// same order: the Dock is out, no Today View at the side, and the touch is on no part of the Dock.
static BOOL DMDockSideDismissTouch(id controller, UITouch *touch) {
    SEL pres = NSSelectorFromString(@"isFloatingDockPresented"), vcs = NSSelectorFromString(@"viewController");
    if (![controller respondsToSelector:pres] || !((BOOL (*)(id, SEL))objc_msgSend)(controller, pres) || ![controller respondsToSelector:vcs]) return NO;
    SEL hsc = NSSelectorFromString(@"homeScreenContextProvider"), ims = NSSelectorFromString(@"iconManager"), lead = NSSelectorFromString(@"isShowingLeadingCustomView");
    id ctx = [controller respondsToSelector:hsc] ? ((id (*)(id, SEL))objc_msgSend)(controller, hsc) : nil;
    id mgr = [ctx respondsToSelector:ims] ? ((id (*)(id, SEL))objc_msgSend)(ctx, ims) : nil;
    if ([mgr respondsToSelector:lead] && ((BOOL (*)(id, SEL))objc_msgSend)(mgr, lead)) return NO;
    id vc = ((id (*)(id, SEL))objc_msgSend)(controller, vcs);
    UIView *v = [vc isKindOfClass:[UIViewController class]] && ((UIViewController *)vc).isViewLoaded ? ((UIViewController *)vc).view : nil;
    if (!v) return YES;
    // (the touch is the system gesture window's, in the display's own turn: -locationInView: of a view in another window came out as nonsense, A12Z {940, -1636} for
    //  a touch at {1330, 470}, and a finger on an icon put the Dock away. Through the screen's space, as StatusBar.x reads such a touch)
    UIWindow *tw = touch.window;
    UIScreen *screen = v.window.screen ?: [UIScreen mainScreen];
    CGPoint sp = tw ? [tw convertPoint:[touch locationInView:tw] toCoordinateSpace:screen.coordinateSpace] : [touch locationInView:nil];
    return [v hitTest:[v convertPoint:sp fromCoordinateSpace:screen.coordinateSpace] withEvent:nil] == nil;
}
// The pointer. WORKAROUND, named: Apple's reveal is a hover gesture (-[SBFloatingDockController _presentFloatingDockIndirectPanGestureRecognizer], made for the
// bottom edge) and hover can't be sent by code on 18.5, so its side-edge form could never be proved here. So the Dock follows the pointer's PLACE instead:
// backboardd's position (BKSMousePointerService, as the auto-hiding bar reads it), which a real trackpad moves like any other pointer and which holds at the
// screen's edge. Looked at off the main thread, only with a side in use, the screen on and a pointer attached, often near the side (MSBDDockPointerInterval).
// The price against Apple's own gesture: no pull that follows the pointer, the Dock simply comes out; a person's check is in plans/dock-side-build.md. Apple's
// conditions still decide whether it may come now (its -gestureRecognizerShouldBegin:, asked below), and its bottom-edge reveal stands down at a side.
static BOOL gDockSideAskingApple = NO;
static MSBDDockPointerState gDockSidePointer;
static BOOL gDockSidePollArmed = NO;
static NSString *gDockSidePointerApp = nil;   // (the full-screen app the pointer brought the Dock out over: its Dock goes again only while that app is in front)
static NSString *DMDockSideFrontApp(void) {   // (SpringBoard's own answer, as the Downloads panel asks it; "" for the Home Screen)
    id sb = [UIApplication sharedApplication]; SEL s = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    id app = [sb respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(sb, s) : nil;
    id b = [app respondsToSelector:@selector(bundleIdentifier)] ? ((id (*)(id, SEL))objc_msgSend)(app, @selector(bundleIdentifier)) : nil;
    return [b isKindOfClass:[NSString class]] ? b : @"";
}
static id DMDockSideController(void) {
    UIViewController *root = gDockSideRoot;
    return [root respondsToSelector:@selector(delegate)] ? ((id (*)(id, SEL))objc_msgSend)(root, @selector(delegate)) : nil;
}
static BOOL DMDockSideMayCome(id ctrl) {
    SEL rs = NSSelectorFromString(@"presentFloatingDockIndirectPanGestureRecognizer"), bs = @selector(gestureRecognizerShouldBegin:);
    id g = [ctrl respondsToSelector:rs] ? ((id (*)(id, SEL))objc_msgSend)(ctrl, rs) : nil;
    if (!g || ![ctrl respondsToSelector:bs]) return YES;
    gDockSideAskingApple = YES;
    BOOL may = ((BOOL (*)(id, SEL, id))objc_msgSend)(ctrl, bs, g);
    gDockSideAskingApple = NO;
    return may;
}
// (SpringBoard's own present and dismiss, sent as the Downloads panel sends them: asked first, with an empty completion -- a missing method was an unrecognized
//  selector in SpringBoard, a completion called unchecked a crash; the reveal ran on 18.5 only. Code review 1.8.2, 8)
static void DMDockSideSend(id ctrl, NSString *name) {
    SEL s = NSSelectorFromString(name);
    if ([ctrl respondsToSelector:s]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(ctrl, s, YES, ^{});
    else { static int told = 0; if (told++ < 5) DMLog([NSString stringWithFormat:@"[dockside] the Dock's controller has no -%@ here: nothing sent", name]); }
}
static void DMDockSidePointerSeen(CGPoint native) {
    // (a look that can't be made now is made again: with the host out of its window for a moment, or no root yet, the reveal stopped until the next turn, Position
    //  change or screen sleep -- code review 1.8.2, 10. No side in use: the next one starts it)
    if (!gDockSideApplied) return;
    if (!gDockSideHost.window) { DMDockSidePointerArm(0.5); return; }
    id ctrl = DMDockSideController();
    SEL ps = NSSelectorFromString(@"isFloatingDockPresented"), hs = NSSelectorFromString(@"maximumFloatingDockHeight");
    if (![ctrl respondsToSelector:ps]) { DMDockSidePointerArm(2.0); return; }
    id app = [UIApplication sharedApplication];
    SEL aio = NSSelectorFromString(@"activeInterfaceOrientation");
    long o = [app respondsToSelector:aio] ? ((long (*)(id, SEL))objc_msgSend)(app, aio) : 3;
    if (o != 3 && o != 4) o = 3;   // (a side is in use in landscape only; a landscape iPad that answers otherwise: its usual side)
    CGSize s = gDockSideHost.window.bounds.size;
    CGPoint p = MSBDDockPointerOnScreen(native, o, CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height)));
    BOOL presented = ((BOOL (*)(id, SEL))objc_msgSend)(ctrl, ps);
    SEL hcp = NSSelectorFromString(@"homeScreenContextProvider"), menus = NSSelectorFromString(@"areAnyIconViewContextMenusShowing");
    id ctx = [ctrl respondsToSelector:hcp] ? ((id (*)(id, SEL))objc_msgSend)(ctrl, hcp) : nil;
    BOOL stay = gKeepDockVisible || ([ctx respondsToSelector:menus] && ((BOOL (*)(id, SEL))objc_msgSend)(ctx, menus));
    double h = [ctrl respondsToSelector:hs] ? ((double (*)(id, SEL))objc_msgSend)(ctrl, hs) : 90.0;
    BOOL near = gDockSideApplied == MSBDDockRight ? p.x >= s.width - kMSBDDockPointerEdge : p.x <= kMSBDDockPointerEdge;
    BOOL may = !presented && near && DMDockSideMayCome(ctrl);
    // (the pointer's Dock goes again only over the app it came out over: after Cmd-H, or an app opened from it as a window, SpringBoard keeps it out on the
    //  Home Screen or the desktop -- code review 1.8.2, 2. Asked only while it is the pointer's Dock)
    BOOL sameApp = YES;
    if (presented && gDockSidePointer.byPointer) {
        NSString *front = DMDockSideFrontApp();
        sameApp = [front isEqualToString:gDockSidePointerApp ?: @""];
        if (!sameApp) DMLog([NSString stringWithFormat:@"[dockside] %@ is in front now, not %@: the Dock out is SpringBoard's, the pointer leaving keeps it", front.length ? front : @"the Home Screen", gDockSidePointerApp.length ? gDockSidePointerApp : @"the Home Screen"]);
    }
    switch (MSBDDockPointerStep(&gDockSidePointer, gDockSideApplied, p, s, presented, may, stay, h, CACurrentMediaTime(), sameApp)) {
        case MSBDDockPointerComeOut:
            DM_FEATURE_MARK("dock-side-pointer");
            gDockSidePointerApp = [DMDockSideFrontApp() copy];
            DMLog([NSString stringWithFormat:@"[dockside] the pointer at %@ reached the Dock's side: the Dock comes out (over %@)", NSStringFromCGPoint(p), gDockSidePointerApp.length ? gDockSidePointerApp : @"the Home Screen"]);
            DMDockSideSend(ctrl, @"presentFloatingDockIfDismissedAnimated:completionHandler:");
            break;
        case MSBDDockPointerGoAway:
            DMLog([NSString stringWithFormat:@"[dockside] the pointer at %@ has left: the Dock goes", NSStringFromCGPoint(p)]);
            DMDockSideSend(ctrl, @"dismissFloatingDockIfPresentedAnimated:completionHandler:");
            break;
        default: break;
    }
    DMDockSidePointerArm(MSBDDockPointerInterval(gDockSideApplied, p, s, presented, gDockSidePointer.byPointer));
}
static void DMDockSidePointerLook(void) {
    gDockSidePollArmed = NO;
    if (!gDockSideApplied) { gDockSidePointer.atEdge = NO; gDockSidePointer.byPointer = NO; return; }   // (the next side in use starts it again)
    static int blank = 0;
    if (!blank) notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &blank, dispatch_get_main_queue(), ^(int t) { uint64_t b = 0; notify_get_state(t, &b); if (!b) DMDockSidePointerArm(0.25); });
    uint64_t off = 0; notify_get_state(blank, &off);
    if (off) return;   // (screen off: its return starts it again)
    id pm = [[UIApplication sharedApplication] respondsToSelector:NSSelectorFromString(@"mousePointerManager")] ? ((id (*)(id, SEL))objc_msgSend)([UIApplication sharedApplication], NSSelectorFromString(@"mousePointerManager")) : nil;
    SEL att = NSSelectorFromString(@"isHardwarePointingDeviceAttached");
    if ([pm respondsToSelector:att] && !((BOOL (*)(id, SEL))objc_msgSend)(pm, att)) { DMDockSidePointerArm(2.0); return; }   // (no trackpad or mouse: asked again now and then)
    static dispatch_queue_t q;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.dockside.pointer", DISPATCH_QUEUE_SERIAL);
    dispatch_async(q, ^{
        Class c = objc_getClass("BKSMousePointerService");
        id svc = c && [(id)c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)c, @selector(sharedInstance)) : nil;
        SEL gp = sel_registerName("globalPointerPosition");
        Method m = svc ? class_getInstanceMethod(object_getClass(svc), gp) : NULL;
        BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{CGPoint=dd}16@0:8");
        CGPoint n = known ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, gp) : CGPointMake(NAN, NAN);
        dispatch_async(dispatch_get_main_queue(), ^{ if (known) DMDockSidePointerSeen(n); else DMDockSidePointerArm(5.0); });
    });
}
static void DMDockSidePointerArm(double seconds) {
    if (gDockSidePollArmed || !gDockSideApplied) return;
    gDockSidePollArmed = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMDockSidePointerLook(); });
}
// The picture an icon of ours is lifted as for its menu (and the pointer's lift), with the Dock at a side: a plain copy of its picture over its place in the
// window, because a preview of the view itself is worked out through the turned view and came out as a thin line (Trash, 18.5, Right). nil on the bottom.
__attribute__((visibility("default"))) UITargetedPreview *MSBDDockSideIconPreview(UIView *icon, UIImage *picture, UIPreviewParameters *parameters) {
    if (!gDockSideApplied || !icon.window || !picture || !DMDockSideInHost(icon)) return nil;
    UIView *over = icon.window.rootViewController.view ?: icon.superview;   // (the Dock window's root view: upright, and a view in a window as UIKit asks of a target; a window itself has none)
    CGRect r = [icon convertRect:icon.bounds toView:over];
    UIImageView *copy = [[UIImageView alloc] initWithImage:picture];
    copy.bounds = CGRectMake(0, 0, r.size.width, r.size.height);
    copy.contentMode = UIViewContentModeScaleAspectFit;
    UIPreviewTarget *target = [[UIPreviewTarget alloc] initWithContainer:over center:CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r))];
    return [[UITargetedPreview alloc] initWithView:copy parameters:parameters ?: [UIPreviewParameters new] target:target];
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
    if (platter) DMTrashAttach(platter, gTrashSlot, DMDockShowsTrash((UIView *)self) && gTrashSlot.size.width > 0);
    DMReadIconCornerRatio((UIView *)self);
    if (platter) DMFinderIconAttach(platter, gFinderSlot, gShowFinder && gFinderSlot.size.width > 0);
    if (platter && DMEditProxiesOn(platter)) DMEditProxiesApply(platter, YES, NO, gLaunchpadIcon, gLaunchpadClassic, NO);   // (Edit Home Screen: the items' icon views follow this layout)
    DMSecondDividerAttach((UIView *)self);
    if (platter && gDockSideEver) {   // (the icons' turn, and each one's share of the row: new icons and a changed Dock too)
        int side = DMDockSideOf((UIView *)self);
        DMDockSideStyleAll(platter, side);
        if (side) DMDockSideMeasureStep(platter);   // (the side Dock's own rows: a TV's Dock lays out with its own, wider step)
        if (side) {   // (the Home Screen keeps out of the Dock at rest)
#if DEBUG
            CGFloat r = DMDockSideRestingRoom((UIView *)self, platter);
            if (fabs(r - gDockSideHomeRoom) > 0.25) DMLog([NSString stringWithFormat:@"[dockside] room %.1f from: dock view bounds %@ center %@ transform %@, platter %@ in %@, host bounds %@, presented %d", r, NSStringFromCGRect(((UIView *)self).bounds),
                NSStringFromCGPoint(((UIView *)self).center), NSStringFromCGAffineTransform(((UIView *)self).transform), NSStringFromCGRect(platter.frame), NSStringFromClass([platter.superview class]), NSStringFromCGRect(gDockSideHost.bounds),
                [DMDockSideController() respondsToSelector:NSSelectorFromString(@"isFloatingDockPresented")] && ((BOOL (*)(id, SEL))objc_msgSend)(DMDockSideController(), NSSelectorFromString(@"isFloatingDockPresented"))]);
#endif
            DMDockSideHomeLaidOut(DMDockSideRestingRoom((UIView *)self, platter));
        }
    }
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
    int dockSide = DMDockSideOf((UIView *)self);   // (the host has the short side as its width; the root still asks for its own, longer one: one answer for both)
    if (dockSide && bounds.size.width > gDockSideHost.bounds.size.width) bounds.size.width = gDockSideHost.bounds.size.width;
    %orig(m, bounds);
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
            MSBDDiagWrite(@"Dock", [NSString stringWithFormat:@"bounds %@\nuserList %@ recents %@ library %@ divider %@ platter %@ spacing %.1f\nshowDownloads %d showTrash %d magnify %d iconSize %.2f\nicons: %@\ndownloads %@ own %d, trash %@, finder %@",
                R(bounds), R(m->userList), R(m->recentsList), R(m->libraryIcon), R(m->divider), R(m->platter), m->spacing, gShowDownloads, gShowTrash, gEnabled, gIconSize, [k componentsJoinedByString:@", "],
                R(gDownloadsSlot), gDownloadsOwnSlot, R(gTrashSlot), R(gFinderSlot)]);   // (our slots from the last layout)
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
    // The Trash (1.7.0) comes right after Downloads, one more icon + spacing (common/DockTrash.h MSBDDockEndLayout): the Dock's right end with
    // Launchpad at the start, as on a Mac; with the App Library icon kept at the end (iPadOS's place, Next to Finder off) that icon stays the last.
    // With Downloads off the Trash takes the slot Downloads would have had. Both go after the second divider.
    CGRect slot = lpLeft ? libEnd : m->libraryIcon;
    BOOL showTrash = DMDockShowsTrash((UIView *)self);   // (this Dock's: a TV's shows it by default)
    BOOL wantEnd = gShowDownloads || showTrash;   // (the Dock's end group: Downloads and / or the Trash)
    // Without the App Library icon (its spot 0 wide) Downloads takes a whole icon's spot of the Dock's size (DMDockHiddenLibrarySide) at the end of the
    // lists, level with the apps, as the App Library icon sits when it is there. Without it iOS ends the lists at the platter's end (18.2's class
    // method: the lists carry a spacing on both sides, the platter is the icons plus a spacing at each end), so the platter grows by the icon plus the
    // one spacing after it -- iOS's own margin after the lists, if any, is taken off: measured, not assumed. Where that height is not there either,
    // everything Downloads-related in this layout is left out (no widening, no second divider, no slot): the Dock only grows for a stack it shows.
    CGFloat ownExtra = -1.0;   // (>= 0: the platter's growth for a Downloads slot of its own, instead of one icon + one spacing)
    gDownloadsOwnSlot = NO;
    if (!lpLeft && wantEnd && hiddenSide > 0.0 && slot.size.width < 1.0) {
        CGFloat listsEnd = MAX(CGRectGetMaxX(m->userList), m->recentsList.size.width >= 1.0 ? CGRectGetMaxX(m->recentsList) : 0.0);
        CGFloat after = m->platter.size.width - listsEnd;
        if (isfinite(listsEnd) && listsEnd > 0.0 && isfinite(after) && after > -1.0) {
            DM_FEATURE_MARK("dock-downloads-own-slot");
            slot = CGRectMake(listsEnd, m->userList.origin.y + (m->userList.size.height - hiddenSide) / 2.0, hiddenSide, hiddenSide);
            ownExtra = MAX(hiddenSide, hiddenSide + m->spacing - MAX(0.0, after));
            gDownloadsOwnSlot = YES;
        }
    }
    BOOL endOn = wantEnd && slot.size.width >= 1.0;
    BOOL downloadsOn = endOn && gShowDownloads, trashOn = endOn && showTrash;
    MSBDDockEnd endLayout = MSBDDockEndLayout(slot.origin.x, slot.size.width, m->spacing, ownExtra, downloadsOn, trashOn);   // (unscaled; Trash off: the Downloads slot of before)
    // The second divider (see gDivider2Rect): with Downloads. After the recents (the recents list at least half an icon wide) it is a second line;
    // with no recents the Dock hides its own line and ours is the only one, between the apps and Downloads (as on macOS). Its gap is one spacing
    // + the 1 pt line; the line's own width is not scaled below, which is corrected after scaling.
    CGRect nativeDivider = m->divider;
    CGFloat unscaledSpacing = m->spacing;
    BOOL hasRecents = m->recentsList.size.width >= slot.size.width * 0.5;
    BOOL divider2 = endOn && nativeDivider.size.width > 0.0 && nativeDivider.size.height > 1.0;
#if DEBUG
    {   // (debug: the Dock's own numbers, whenever they change)
        static NSString *lastMetrics = nil;
        NSString *mt = [NSString stringWithFormat:@"user %@ recents %@ divider %@ library %@ spacing %.2f end %d+%d", NSStringFromCGRect(m->userList), NSStringFromCGRect(m->recentsList), NSStringFromCGRect(nativeDivider), NSStringFromCGRect(slot), m->spacing, downloadsOn, trashOn];
        if (![mt isEqualToString:lastMetrics]) { lastMetrics = mt; DMLog([@"[metrics] " stringByAppendingString:mt]); }
    }
#endif
    if (endOn) {
        CGFloat extra = endLayout.growth + (divider2 ? unscaledSpacing + nativeDivider.size.width : 0.0);
        if (!lpLeft) m->libraryIcon.origin.x += extra;
        m->platter.size.width += extra;
        m->platter.origin.x -= extra / 2.0;
    }
    CGFloat f = gIconSize;
    if (dockSide) {
        // (Settings > Dock > Position: the host's short width gets Apple's smaller Dock, A12Z 46 pt icons against 62 at the long width. Icon Size means the same icon as at
        //  the bottom: Apple's answer for the long width gives the share, and the fit below takes over when a Dock that big doesn't fit)
        DMDockMetrics longDock; memset(&longDock, 0, sizeof(longDock));
        CGRect longBounds = CGRectMake(0, 0, gDockSideHost.bounds.size.height, gDockSideHost.bounds.size.width);
        %orig(&longDock, longBounds);
        CGFloat share = m->userList.size.height >= 8.0 ? longDock.userList.size.height / m->userList.size.height : 1.0;
        if (isfinite(share) && share > 1.0 && share < 2.0) f *= share;
    }
    // Auto-fit, like macOS (2026-09-25): the Icon Size is the largest the Dock gets; when the whole Dock (apps, divider, recents, Downloads, App
    // Library) would not fit the screen minus the side margins, it gets just small enough to fit -- in both orientations, re-worked out at every
    // layout (apps or recents added or removed, a turn). Room is kept at both ends for the magnification: the end icons grow in place by
    // (magnification - 1) x their width, half on each side, and must stay on the screen.
    CGFloat headroom = gEnabled ? MAX(0.0, gMagnification - 1.0) * (slot.size.width >= 1.0 ? slot.size.width : hiddenSide) : 0.0;   // (no end icon: the icon size)
    CGFloat room = (dockSide ? MSBDDockSideLength(bounds.size.width, DMDockSideBar()) : bounds.size.width - 50.0) / (m->platter.size.width + headroom);
    // Portrait: the screen is narrower, so a Dock this tweak has shrunk looks small. It grows to the widest size that still fits (at most
    // 1.2 times the stock size). Only while the tweak is shrinking the Dock at all; a size of 1.0 or more is left alone.
    // Portrait is read from the bounds asked about (the Dock spans its screen's width: narrower than the screen's long side = portrait), never from
    // the screen's current orientation: during a turn SpringBoard lays the Dock out for the new bounds while the screen still reports the old side,
    // and the same bounds must always get the same answer (K-2: the portrait size stayed on in landscape after a turn, iPad 2: 974 pt instead of 831).
    UIScreen *dockScreen = ((UIView *)self).window.windowScene.screen ?: [UIScreen mainScreen];
    BOOL portraitBounds = bounds.size.width < MAX(dockScreen.bounds.size.width, dockScreen.bounds.size.height) - 1.0;
    if (dockSide) portraitBounds = NO;   // (the short side of a landscape screen is no portrait Dock)
    if (gPortraitLarger && f < 1.0 && portraitBounds) f = MIN(room, 1.2);
    if (f > room) f = room;
    static CGFloat lastF = -1; static CGFloat lastW = -1;
    if (fabs(f - lastF) > 0.001 || fabs(bounds.size.width - lastW) > 0.5) {
        lastF = f; lastW = bounds.size.width;
        DMLog([NSString stringWithFormat:@"[fit] screen %.0f, dock %.0f + %.0f magnification room at size 1: icon size %.3f (setting %.2f, fits up to %.3f)", bounds.size.width, m->platter.size.width, headroom, f, gIconSize, room]);
    }
    gFinderSlot = CGRectMake(finderSlot.origin.x * f, finderSlot.origin.y * f, finderSlot.size.width * f, finderSlot.size.height * f);
    if (!endOn && fabs(f - 1.0) < 0.001) {
        if (gTweakOn && isfinite(gBottomGap)) m->platter.origin.y = CGRectGetMaxY(bounds) - gBottomGap - m->platter.size.height;   // (Gap to Screen Edge, below)
#if DEBUG
        if (CACurrentMediaTime() < gDMMetricsLogUntil) DMLog([NSString stringWithFormat:@"[metricslog] view %p bounds %@: f 1 (no Downloads, no Trash), platter %@", self, NSStringFromCGRect(bounds), NSStringFromCGRect(m->platter)]);
#endif
        gDownloadsSlot = CGRectZero; gTrashSlot = CGRectZero; gDivider2Rect = CGRectZero;
        if (rtl) { DMDockMirrorMetrics(m); if (gFinderSlot.size.width > 0.0) gFinderSlot = DMDockMirrorRect(gFinderSlot, m->platter.size.width); }
        if (dockSide) m->platter.origin.x = MSBDDockSidePlatterX(bounds.size.width, DMDockSideBar(), m->platter.size.width);
        return;
    }
    CGRect (^scaled)(CGRect) = ^CGRect(CGRect r) { return CGRectMake(r.origin.x * f, r.origin.y * f, r.size.width * f, r.size.height * f); };
    CGRect slotD = slot, slotT = slot;
    slotD.origin.x = endLayout.downloadsX; slotT.origin.x = endLayout.trashX;
    gDownloadsSlot = downloadsOn ? scaled(slotD) : CGRectZero;
    gTrashSlot = trashOn ? scaled(slotT) : CGRectZero;
    if (trashOn) DM_FEATURE_MARK("dock-trash-slot");
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
        if (downloadsOn) gDownloadsSlot.origin.x += unscaledSpacing * f + lineW + off;
        if (trashOn) gTrashSlot.origin.x += unscaledSpacing * f + lineW + off;
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
        if (gTrashSlot.size.width > 0.0) gTrashSlot = DMDockMirrorRect(gTrashSlot, pw);
        if (gDivider2Rect.size.height > 0.0) gDivider2Rect = DMDockMirrorRect(gDivider2Rect, pw);
    }
    // Gap to Screen Edge: the platter's bottom this many points above the Dock view's bottom (= the screen's bottom edge), whatever iPadOS chose --
    // the platter margin hook below only ever lowered iPadOS's own margin, and on iPadOS 16 it had no effect at all (0 and 24 pt gave the same
    // Dock, iPad 2, 29 Sep). The icons are placed relative to the platter, so they move with it. Taken on every layout: a change shows at once.
    // It is its own setting (Settings: its own group, not under Magnification): applied whenever the Dock part is on, with Magnify Icons on or off -- it
    // used to wait for magnification, so with Magnify Icons off the Dock stayed at iPadOS's own height whatever the slider said (K-2 report: 18.5 pt).
    if (gTweakOn && isfinite(gBottomGap)) { DM_FEATURE_MARK("dock-bottom-gap"); m->platter.origin.y = CGRectGetMaxY(bounds) - gBottomGap - m->platter.size.height; }
    if (dockSide) m->platter.origin.x = MSBDDockSidePlatterX(bounds.size.width, DMDockSideBar(), m->platter.size.width);   // (in the room under the menu bar)
#if DEBUG
    if (CACurrentMediaTime() < gDMMetricsLogUntil) {
        NSArray *st = [NSThread callStackSymbols];
        DMLog([NSString stringWithFormat:@"[metricslog] view %p bounds %@: f %.3f, platter %@, user %@, finder %@, downloads %@, trash %@ | from %@ / %@", self, NSStringFromCGRect(bounds), f, NSStringFromCGRect(m->platter), NSStringFromCGRect(m->userList),
            NSStringFromCGRect(gFinderSlot), NSStringFromCGRect(gDownloadsSlot), NSStringFromCGRect(gTrashSlot), st.count > 2 ? st[2] : @"-", st.count > 3 ? st[3] : @"-"]);
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
        int side = gDockSideApplied && [dockWindow isKindOfClass:[UIWindow class]] && DMDockOnMainScreen((UIWindow *)dockWindow) ? gDockSideApplied : 0;   // (a Dock at a side: on the screen's side of it)
        CGFloat lift = gEnabled ? MAX(12.0, (side ? dock.size.width : dock.size.height) * (MAX(gMagnification, 1.0) - 1.0) + 6.0) : 4.0;
        if (side == MSBDDockRight) { dock.origin.x -= lift; dock.size.width += lift; }
        else if (side == MSBDDockLeft) dock.size.width += lift;
        else { dock.origin.y -= lift; dock.size.height += lift; }
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
// (or the tick is running), and while the screen is off: the screen's return starts it again if the Dock is still raised (it used to keep firing
// twice a second all night with nothing to do; battery drain F5).
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
    id cc = MSBDControlCenterController();   // (iPadOS 18: the main scene's -- no shared instance there, CCController.h)
    for (NSString *name in @[@"isPresented", @"isVisible"]) {
        SEL sel = NSSelectorFromString(name);
        if ([cc respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(cc, sel)) return YES;
    }
    return NO;
}
static NSTimer *gDockFloorWatch = nil;
static int gDockBlankToken = 0;   // (com.apple.springboard.hasBlankedScreen, state 1 = blank)
static BOOL DMDockScreenBlank(void) { uint64_t b = 0; if (gDockBlankToken) notify_get_state(gDockBlankToken, &b); return b != 0; }
static BOOL DMDockFloorWatchNeeded(void) {   // (raised, and the status bar's tick has not asked for 1.5 s)
    UIWindow *w = gDockWindow;
    return w && fabs(w.windowLevel - kDockMinWindowLevel) < 0.01 && CACurrentMediaTime() - gDockTickReassertAt >= 1.5;
}
static void DMDockFloorWatchStart(void) {
    if (!gDockBlankToken)
        notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &gDockBlankToken, dispatch_get_main_queue(), ^(int tok) {
            if (!DMDockScreenBlank() && DMDockFloorWatchNeeded()) DMDockFloorWatchStart();   // (the screen back on, the Dock still raised)
        });
    if (gDockFloorWatch || DMDockScreenBlank()) return;   // (screen off: not now -- its return starts it)
    gDockFloorWatch = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        // (down again, or the tick runs, or the screen went off: stopped)
        if (!DMDockFloorWatchNeeded() || DMDockScreenBlank()) { [t invalidate]; gDockFloorWatch = nil; return; }
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
// One of our Dock items changed its picture with no layout of the Dock to follow (the Trash filled or emptied, the Launchpad tile switched in
// Settings, a theme engine's new picture): the Dock lays out again where something shows that picture -- Glass Shelf's reflection (the platter's
// layout, DockStyle.m) and, while the Home Screen is edited, the item's stand-in (the Dock's layout, EditProxy.m). Both kept the old picture until
// some later layout (regression 1.8.4: D-1 on the A12Z, W-1 on the iPad 2). Called once the new picture is set (after a cross-fade: at its end).
extern BOOL DMDockStyleReflects(UIView *platter);
extern void DMDockStylePictureDirty(UIView *platter, UIView *icon);
void DMDockItemPictureChanged(UIView *item) {
    Class dc = objc_getClass("SBFloatingDockView"), pc = objc_getClass("SBFloatingDockPlatterView");
    UIView *platter = nil, *dock = nil;
    for (UIView *v = item.superview; v && !dock; v = v.superview) {
        if (!platter && pc && [v isKindOfClass:pc]) platter = v;
        if (dc && [v isKindOfClass:dc]) dock = v;
    }
    // (its reflection taken again at the platter's next layout, whatever its picture's value says: DockStyle.m, the review of the fixes M2)
    if (platter && DMDockStyleReflects(platter)) { DMDockStylePictureDirty(platter, item); [platter setNeedsLayout]; }
    if (platter && dock && DMEditProxiesOn(platter)) [dock setNeedsLayout];   // (the stand-ins follow each Dock layout while editing: DMEditProxiesApply)
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
static void DMLastPageApply(NSString *why);   // (below, with the App Library's last page)
static void DMDockSideChoose(void);   // (Position: below, with its hooks)
static void DMPrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n,
                           const void *obj, CFDictionaryRef info) {
    BOOL lastPage = gLastPageOpensLibrary;
#if DEBUG
#define DM_PREFS_STEP(name) DMLog(@"[prefs-step] " name)   // (debug: which step of a settings change cancels an active hover)
#else
#define DM_PREFS_STEP(name) do {} while (0)
#endif
    DM_PREFS_STEP("load");
    DMLoadPrefs();
    DM_PREFS_STEP("side");
    DMDockSideChoose();
    DM_PREFS_STEP("relayout");
    DMRelayoutDock();
    DM_PREFS_STEP("style");
    DMDockStyleRefreshAll();   // (Dock Style: every platter takes the look now)
    DM_PREFS_STEP("launchpad");
    DMRefreshLaunchpadIcons();
    DM_PREFS_STEP("done");
    if (lastPage != gLastPageOpensLibrary) DMLastPageApply(@"switched in Settings");
}

static void DMCollectIcons(UIView *root, Class iconClass, NSMutableArray *out) {
    for (UIView *v in root.subviews) {
        if (DMEditProxyIs(v)) continue;   // (Edit Home Screen's icon views: each keeps the size and place EditProxy.m fits it to, our items' scale with their own view -- a magnification of their own replaced that, full size and off centre: audit 1.8.3 M1)
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

#if DEBUG
// (debug, review 1.8.4 Pass 4's watch item: a hover that ends within frames of its start while the pointer stands still -- the Dock moving under it? At
//  UIKit's Began and at the end: the pointer in the window, the platter's frame (model) and as drawn (the presentation tree), what UIKit hit-tests there and
//  whether that is in the platter, and whether this Dock counts as presented)
extern NSArray *DMDockAutoHideControllers(void);   // (DockAutoHide.m)
static void DMHoverDebugLine(UIView *platter, UIGestureRecognizer *g) {
    UIWindow *w = platter.window;
    CGPoint p = [g locationInView:nil];
    UIView *hit = w ? [w hitTest:p withEvent:nil] : nil;
    CALayer *pl = platter.layer.presentationLayer;
    CGRect pres = pl ? [pl convertRect:pl.bounds toLayer:nil] : CGRectNull;
    int presented = -1;
    for (id ctrl in DMDockAutoHideControllers()) {
        SEL fw = sel_registerName("floatingDockWindow"), ip = sel_registerName("isFloatingDockPresented");
        Method mw = class_getInstanceMethod(object_getClass(ctrl), fw), mp = class_getInstanceMethod(object_getClass(ctrl), ip);
        if (!mw || !mp || strcmp(method_getTypeEncoding(mw) ?: "", "@16@0:8") || strcmp(method_getTypeEncoding(mp) ?: "", "B16@0:8")) continue;
        if (((id (*)(id, SEL))objc_msgSend)(ctrl, fw) != w) continue;
        presented = ((BOOL (*)(id, SEL))objc_msgSend)(ctrl, ip);
        break;
    }
    DMLog([NSString stringWithFormat:@"[hover] %ld t %.3f p %@ frame %@ pres %@ hit %@ inside %d presented %d", (long)g.state, CACurrentMediaTime(), NSStringFromCGPoint(p),
           NSStringFromCGRect([platter convertRect:platter.bounds toView:nil]), NSStringFromCGRect(pres), hit ? NSStringFromClass([hit class]) : @"nil",
           hit ? (int)[hit isDescendantOfView:platter] : 0, presented]);
    if (g.state == UIGestureRecognizerStateCancelled) {   // (who cancelled it: a Dock settings change did, 6 of 6 on the M1 -- the frames above this one)
        NSArray<NSString *> *st = [NSThread callStackSymbols];
        NSMutableString *o = [NSMutableString stringWithString:@"[hover] cancelled from:"];
        for (NSUInteger i = 2; i < st.count && i < 22; i++) [o appendFormat:@"\n  %@", [st[i] substringFromIndex:MIN((NSUInteger)4, st[i].length)]];
        DMLog(o);
    }
}
#endif

// ---- the hover held through UIKit's cancel while the pointer rests over the platter (1.8.4.1, spec item 4; the rules and why: common/DockHover.h) ----
// A Dock layout of SpringBoard's own (its recents, a Handoff tile) or a Dock setting under a resting pointer: UIKit cancels the platter's hover and the
// magnification eased out until the pointer moved. Held instead: backboardd's place of the pointer is read (off the main thread, as the side Dock's reveal
// reads it) and, while it is over the platter, the magnification stays there; UIKit's own hover beginning again takes over; elsewhere, unknown, no pointing
// device, the screen off or the Dock gone, it eases out as before.
static BOOL gHoverHeld = NO;
static int gHoverHoldLooks = 0;
static unsigned gHoverHoldGen = 0;   // (each hold's own chain of looks: a look of an earlier hold's stops -- one backboardd read at a time, review 1.8.4.1 L3)
static __weak UIView *gHoverHoldPlatter = nil;
static void DMDockHoverLook(unsigned gen);
static void DMDockHoverHoldEnd(UIView *platter, NSString *why) {
    gHoverHeld = NO;
    DMLog([NSString stringWithFormat:@"[hover] held after UIKit's cancel: ends (%@)", why]);
    gHovering = NO;
    if (platter) [(SBFloatingDockPlatterView *)platter dm_startLink];   // (the link eases the magnification out)
}
static BOOL DMDockHoverTracking(UIView *platter) {
    UIGestureRecognizer *g = objc_getAssociatedObject(platter, kHoverKey);
    return g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged;
}
static void DMDockHoverLook(unsigned gen) {
    UIView *platter = gHoverHoldPlatter;
    if (!gHoverHeld || gen != gHoverHoldGen) return;   // (ended, or a later hold has its own looks)
    if (!platter.window) { DMDockHoverHoldEnd(platter, @"the Dock is gone"); return; }
    if (DMDockScreenBlank()) { DMDockHoverHoldEnd(platter, @"the screen is off"); return; }
    if (DMDockHoverTracking(platter)) { gHoverHeld = NO; DMLog(@"[hover] UIKit has the pointer again"); return; }
    id app = [UIApplication sharedApplication];
    SEL pms = NSSelectorFromString(@"mousePointerManager"), att = NSSelectorFromString(@"isHardwarePointingDeviceAttached"), aio = NSSelectorFromString(@"activeInterfaceOrientation");
    id pm = [app respondsToSelector:pms] ? ((id (*)(id, SEL))objc_msgSend)(app, pms) : nil;
    BOOL attached = ![pm respondsToSelector:att] || ((BOOL (*)(id, SEL))objc_msgSend)(pm, att);
    long o = [app respondsToSelector:aio] ? ((long (*)(id, SEL))objc_msgSend)(app, aio) : 1;
    CGSize s = platter.window.bounds.size, native = CGSizeMake(MIN(s.width, s.height), MAX(s.width, s.height));
    static dispatch_queue_t q;
    if (!q) q = dispatch_queue_create("com.besiktasliseba.dock.hoverhold", DISPATCH_QUEUE_SERIAL);
    dispatch_async(q, ^{
        Class c = objc_getClass("BKSMousePointerService");
        id svc = c && [(id)c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)((id)c, @selector(sharedInstance)) : nil;
        SEL gp = sel_registerName("globalPointerPosition");
        Method m = svc ? class_getInstanceMethod(object_getClass(svc), gp) : NULL;
        BOOL known = m && !strcmp(method_getTypeEncoding(m) ?: "", "{CGPoint=dd}16@0:8");   // (as the side Dock's reveal reads it: that shape only)
        CGPoint n = known ? ((CGPoint (*)(id, SEL))objc_msgSend)(svc, gp) : CGPointMake(NAN, NAN);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *pl = gHoverHoldPlatter;
            if (!gHoverHeld || gen != gHoverHoldGen || pl != platter || !pl.window) return;
            CGPoint p = CGPointMake(NAN, NAN);
            if (known) p = [pl convertPoint:MSBDDockPointerOnScreen(n, o, native) fromCoordinateSpace:(pl.window.screen ?: [UIScreen mainScreen]).coordinateSpace];
            switch (MSBDHoverHoldStep(DMDockHoverTracking(pl), known, attached, MSBDHoverInside(p, pl.bounds))) {
                case MSBDHoverHoldUIKit: gHoverHeld = NO; DMLog(@"[hover] UIKit has the pointer again"); break;
                case MSBDHoverHoldKeep: {
                    DM_FEATURE_MARK("dock-hover-held");
                    gFocusX = p.x;
                    if (!gLink) [(SBFloatingDockPlatterView *)pl dm_startLink];   // (the icons put back at the pointer, then the link rests again)
                    double next = MSBDHoverHoldInterval(gHoverHoldLooks++);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(next * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ DMDockHoverLook(gen); });
                    break;
                }
                default: DMDockHoverHoldEnd(pl, known ? @"the pointer is no longer over the Dock" : @"the pointer's place can't be read here"); break;
            }
        });
    });
}
// A touch SpringBoard sees (the UIApplication hook below): a finger hides the pointer and a click is the user's. A cancel just after it is not held, a hold
// already running is over (the cancel and the touch reach SpringBoard in either order), and the magnification eases out even where UIKit doesn't cancel the
// hover for it (a click on a Dock icon, the 17.5 on Stage Manager); the pointer moving brings it back.
static void DMDockHoverTouchBegan(void) {
    gDMDockTouchAt = CACurrentMediaTime();
    if (gHoverHeld) { gHoverEasedByTouch = YES; DMDockHoverHoldEnd(gHoverHoldPlatter, @"a touch or a click"); return; }
    if (gHovering && gEnabled && gLinkPlatter) {
        DMLog(@"[hover] a touch or a click with the magnification on: eases out");
        gHovering = NO;
        gHoverEasedByTouch = YES;
        [(SBFloatingDockPlatterView *)gLinkPlatter dm_startLink];
    }
}
// UIKit ended the platter's hover: YES when that is held (a cancel with no touch just before it, with the magnification on, on the iPad's own screen -- backboardd's place is the iPad's).
static BOOL DMDockHoverHold(UIView *platter, UIGestureRecognizer *g) {
    if (!MSBDHoverHoldsAfter((long)g.state, gHovering && gEnabled, gDMDockTouchAt < 0 ? -1.0 : CACurrentMediaTime() - gDMDockTouchAt) || !platter.window) return NO;
    if (platter.window.screen && platter.window.screen != [UIScreen mainScreen]) return NO;
    gHoverHeld = YES; gHoverHoldLooks = 0; gHoverHoldPlatter = platter; gHoverHoldGen++;
    DMLog([NSString stringWithFormat:@"[hover] cancelled by UIKit with the magnification on, %.3f s after the last touch: held while the pointer is over the Dock", gDMDockTouchAt < 0 ? -1.0 : CACurrentMediaTime() - gDMDockTouchAt]);
    DMDockHoverLook(gHoverHoldGen);
    return YES;
}
// (EditProxy.m EPFollow: a Dock layout while editing put the Launchpad stand-in back at its rest size under a resting pointer -- review 1.8.4 L1-L4 L-1 --:
//  one more pass of the link puts the magnification back on it, as a reset icon's transform is, the SBIconView hook below)
void DMDockHoverReapply(void) {
    UIView *pl = gLinkPlatter;
    if (gHovering && !gLink && pl.window) [(SBFloatingDockPlatterView *)pl dm_startLink];
}

%hook SBFloatingDockPlatterView

// Dock Style (1.8.4 item 3): our look at the back of the platter, laid out with it; Default: nothing of ours (DockStyle.m)
- (void)layoutSubviews {
    %orig;
    DMDockStyleApply((UIView *)self);
}
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
#if DEBUG
            if (gesture.state == UIGestureRecognizerStateBegan) DMHoverDebugLine(self, gesture);
#endif
            CGFloat x = [gesture locationInView:self].x;
            gHoverHeld = NO;   // (UIKit has the pointer again: a hold after its cancel ends here)
            gHoverEasedByTouch = NO;
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
            if (DMDockHoverHold(self, gesture)) break;   // (UIKit's cancel under a resting pointer -- a Dock layout or setting: held while the pointer is over the Dock)
            DMLog([NSString stringWithFormat:@"[hover] ended (state %ld) after %ld frames, largest scale change between frames %.4f",
                   (long)gesture.state, (long)gStatFrames, gStatMaxJump]);
#if DEBUG
            DMHoverDebugLine(self, gesture);
#endif
            gHovering = NO;
            gHoverEasedByTouch = NO;
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
        UIView *trashIcon = DMTrashIcon(self);       // (and the Trash)
        if (trashIcon) [icons addObject:trashIcon];
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
            if (icon.hidden && icon.superview) {   // (Edit Home Screen: the App Library icon hides under our Launchpad stand-in, which takes the
                                                   //  magnification it would get, from its own centre -- review 1.8.3.1 L1; no other icon has one)
                CGFloat s = 1.0;
                if (gInfluence > 0.0) { CGPoint c = [icon.superview convertPoint:icon.center toView:self]; s = DMScale(gSmoothX - c.x); }
                DMEditProxyMagnify(icon, s);
            }
        }
    }];
    gApplying = NO;
    DMDockStyleFollow(self);   // (Glass Shelf: the reflections follow the icons' scale)

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
    if (gDockSideEver) {   // (Position: a side Dock icon's content stands upright; one that left the Dock, or a Dock back at the bottom, gets back what it had; others are not touched)
        BOOL dock = gDockSideApplied && DMIsDockIcon((UIView *)self) && DMDockSideInHost((UIView *)self);   // (a TV's Dock icon: upright as its Dock)
        DMDockSideStyleIcon((UIView *)self, dock ? gDockSideApplied : 0);   // (first: the dot below goes where the content stands)
    }
    DMUpdateRunningIndicator((UIView *)self);   // only acts on Dock icons (checks internally)
}
- (void)setTransform:(CGAffineTransform)t {
    %orig;
    BOOL dockIcon = DMIsDockIcon((UIView *)self) && !DMEditProxyIs((UIView *)self);   // (Edit Home Screen's icon views set their own fit: not a magnified icon reset, audit 1.8.3 M1)
    if (gHovering && !gApplying && !gLink && dockIcon) {
        // (the link rests while the pointer rests on the Dock: something else reset a magnified icon, so it runs again and puts the scale back)
        dispatch_async(dispatch_get_main_queue(), ^{ if (gHovering && !gLink) [(SBFloatingDockPlatterView *)gLinkPlatter dm_startLink]; });
    }
    static int external = 0;
    if (gHovering && !gApplying && external < 40 && dockIcon) {
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

// ---- Swiping past the last Home Screen page opens the App Library: off unless switched on (KT, 1.7.8) ------------------------------------
// iPadOS keeps an empty page after the last Home Screen page -- the root folder's trailing custom page, SBHLibraryOverscrollViewController (read
// on the M1, 15.6.1: 4 icon pages and a page count of 5, the trailing page's index the last icon page's + 1) -- and scrolling into it presents
// the App Library over everything (the icon manager's overscroll library). While the switch is off that page is left out (LastPageRule.h): of
// the root folder's page count (SBRootFolderView: -_trailingCustomPageCount on 15-17, -trailingCustomPageCount on 18) and of its index
// (-trailingCustomViewPageIndex answers NSIntegerMax, iPadOS's own "no trailing page"). Both, as one: 15-17 work the index out from the trailing
// view, not from the count, so with the count alone they took the last icon page for the App Library's (Edit Home Screen there moved to edit
// mode's empty page after it: 1.7.8 regression R-8). The pages end at the last one, which then bounces at its edge as the first page does -- no
// empty page to scroll into, nothing presented. Only the page: the App Library is still reached the other ways -- its Dock icon (our Launchpad),
// the swipe down, its search, Spotlight, an icon dragged to the edge in edit mode --, which present it from the icon manager, not through it.
// Shape checks first (the class, the count and the index and their types, the page's class, the getter of the trailing pages); anything else:
// iPadOS's own page. 18 can have several trailing pages: left out only while every one of them is the App Library's.
#import "LastPageRule.h"
static id DMObj(id o, NSString *sel);   // (below)
static unsigned long long (*o_DMTrailingPages)(id, SEL);
static long long (*o_DMTrailingPageIndex)(id, SEL);
static SEL gDMTrailingCountSel;   // (_trailingCustomPageCount on 15-17, trailingCustomPageCount on 18)
static Class gDMLibraryPageClass;
static NSString *gDMTrailingGetter;   // (trailingCustomViewControllers on 18, trailingCustomViewController on 15-17)
static BOOL DMTrailingIsLibraryOnly(id rootFolderView) {
    id got = nil;
    @try { got = ((id (*)(id, SEL))objc_msgSend)(rootFolderView, NSSelectorFromString(gDMTrailingGetter)); } @catch (NSException *e) { return NO; }
    NSArray *pages = [got isKindOfClass:[NSArray class]] ? got : got ? @[got] : @[];
    if (!pages.count) return NO;
    for (id vc in pages) if (![vc isKindOfClass:gDMLibraryPageClass]) return NO;
    return YES;
}
// The one test both hooks answer from, given iPadOS's own count: the page is left out while the switch is off and every trailing page is the
// App Library's. (So the count and the index can never disagree.)
static BOOL DMTrailingLeftOut(id rootFolderView, unsigned long long iosCount) {
    return DMLastPageMayLeaveOut(iosCount, gLastPageOpensLibrary) && DMTrailingIsLibraryOnly(rootFolderView);
}
static unsigned long long DMTrailingPages(id self, SEL _cmd) {
    unsigned long long n = o_DMTrailingPages(self, _cmd);
    BOOL out = DMTrailingLeftOut(self, n);
    if (out) DM_FEATURE_MARK("last-page-no-library");
    return DMLastPageCount(n, out);
}
// The trailing page's index (SBRootFolderController's asks this one): NSIntegerMax while the page is left out, so every user of it sees no
// trailing page, as iPadOS has it without one -- -isOnTrailingCustomPage, edit mode's -[SBRootFolderController
// _updateFolderRequiredTrailingEmptyListCount], -viewControllersForPageIndex:, the page state transitions, the library overlay's swipe-to-dismiss
// and its scroll back to the last page, Focus (SBHFocusModeManager) -- and the unused trailing view is laid out at that index's offset, far
// off-screen. 18 already answers this from the count (-firstTrailingCustomPageIndex): there it comes back as NSIntegerMax by itself.
static long long DMTrailingPageIndex(id self, SEL _cmd) {
    long long i = o_DMTrailingPageIndex(self, _cmd);
    if (i == LLONG_MAX) return i;   // (iPadOS's own "no trailing page")
    BOOL out = DMTrailingLeftOut(self, o_DMTrailingPages(self, gDMTrailingCountSel));
#if DEBUG
    static int logged = 0;
    if (out && logged++ < 10) DMLog([NSString stringWithFormat:@"[lastpage] the trailing page's index: none (iPadOS had %lld, its last icon page's)", i]);
#endif
    return DMLastPageIndex(i, out);
}
// The App Library a page swipe brings is the icon manager's "overscroll" library: presented when a scroll ends where the trailing page would be
// (-[SBHIconManager _updateOverscrollModalLibraryForScrollToPresented:], every version 15-18). With the page left out, a fling from the page before
// the last still landed there: the scroll's target, worked out from its speed, was the trailing page's index, and the library came (M1 15.6.1,
// debug ui02: from page 3 of 4, not from page 4 itself). So while the switch is off that presentation is refused too -- only the page swipe's: the
// Dock icon, the swipe down, search and Spotlight present it through the modal presenter, never through this. Its dismissal (NO) always goes on.
static void (*o_DMOverscrollLibrary)(id, SEL, BOOL);
static void DMOverscrollLibrary(id self, SEL _cmd, BOOL presented) {
#if DEBUG
    if (access("/tmp/msb-lastpage-nogate", F_OK) == 0) { DMLog([NSString stringWithFormat:@"[lastpage] overscroll library %d (debug: not gated)", presented]); o_DMOverscrollLibrary(self, _cmd, presented); return; }
#endif
    if (presented && !gLastPageOpensLibrary) {
        DM_FEATURE_MARK("last-page-no-overscroll-library");
        static int logged = 0;
        if (logged++ < 20) DMLog(@"[lastpage] a scroll past the last page asked for the App Library: not opened (Swipe Past Last Page is off)");
        return;
    }
    o_DMOverscrollLibrary(self, _cmd, presented);
}
#if DEBUG
// (debug: who presents the App Library, and the scroll's page targets -- 1.7.8 item 7)
static void (*o_DMDbgPresentLib)(id, SEL, BOOL, id);
static void DMDbgPresentLib(id self, SEL _cmd, BOOL animated, id completion) {
    NSArray *st = [NSThread callStackSymbols];
    DMLog([NSString stringWithFormat:@"[lastpage] debug: the modal presenter presents the App Library; called from %@", [[st subarrayWithRange:NSMakeRange(1, MIN((NSUInteger)6, st.count - 1))] componentsJoinedByString:@" | "]]);
    o_DMDbgPresentLib(self, _cmd, animated, completion);
}
static void (*o_DMDbgWillScroll)(id, SEL, long long, BOOL);
static void DMDbgWillScroll(id self, SEL _cmd, long long page, BOOL animated) {
    DMLog([NSString stringWithFormat:@"[lastpage] debug: the root folder will scroll to page %lld (animated %d)", page, animated]);
    o_DMDbgWillScroll(self, _cmd, page, animated);
}
static void (*o_DMDbgOverscroll)(id, SEL, id, double);
static void DMDbgOverscroll(id self, SEL _cmd, id rfc, double amount) {
    static CFTimeInterval last = 0;
    if (CACurrentMediaTime() - last > 0.3) { last = CACurrentMediaTime(); DMLog([NSString stringWithFormat:@"[lastpage] debug: overscroll on the last page by %.1f", amount]); }
    o_DMDbgOverscroll(self, _cmd, rfc, amount);
}
#endif
static id DMRootFolderView(void) {
    id mgr = DMObj(DMObj((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    id v = DMObj(DMObj(mgr, @"rootFolderController"), @"contentView");
    return [NSStringFromClass([v class]) containsString:@"RootFolderView"] ? v : nil;
}
// The switch changed: the Home Screen lays its pages out again, so the page comes or goes at once (not at the next respring).
static void DMLastPageApply(NSString *why) {
    if (!o_DMTrailingPages) return;
    UIView *v = DMRootFolderView();
    if (!v) return;
    [v setNeedsLayout]; [v layoutIfNeeded];
    SEL dots = NSSelectorFromString(@"_updatePageControlNumberOfPages");
    if ([v respondsToSelector:dots]) ((void (*)(id, SEL))objc_msgSend)(v, dots);
    DMLog([NSString stringWithFormat:@"[lastpage] %@: swiping past the last page %@ (%@ pages now)", why, gLastPageOpensLibrary ? @"opens the App Library" : @"ends at the last page",
           [v respondsToSelector:NSSelectorFromString(@"pageCount")] ? [v valueForKey:@"pageCount"] : @"?"]);
}
static void DMLastPageInit(void) {
    Class view = objc_getClass("SBRootFolderView");
    gDMLibraryPageClass = objc_getClass("SBHLibraryOverscrollViewController");
    SEL count = NULL; NSString *why = nil;
    for (NSString *name in @[@"_trailingCustomPageCount", @"trailingCustomPageCount"]) {   // (15-17, 18)
        Method m = view ? class_getInstanceMethod(view, NSSelectorFromString(name)) : NULL;
        if (m && !strcmp(method_getTypeEncoding(m), "Q16@0:8")) { count = NSSelectorFromString(name); break; }
    }
    for (NSString *name in @[@"trailingCustomViewControllers", @"trailingCustomViewController"]) {   // (18, 15-17)
        Method m = view ? class_getInstanceMethod(view, NSSelectorFromString(name)) : NULL;
        if (m && !strcmp(method_getTypeEncoding(m), "@16@0:8")) { gDMTrailingGetter = name; break; }
    }
    SEL index = NSSelectorFromString(@"trailingCustomViewPageIndex");   // (every version 15-18: q16@0:8)
    Method im = view ? class_getInstanceMethod(view, index) : NULL;
    if (!view) why = @"no SBRootFolderView";
    else if (!count) why = @"its trailing page count is not the known one";
    else if (!im || strcmp(method_getTypeEncoding(im), "q16@0:8")) why = @"its trailing page's index is not the known one";
    else if (!gDMTrailingGetter) why = @"its trailing pages' getter is not the known one";
    else if (!gDMLibraryPageClass) why = @"no SBHLibraryOverscrollViewController";
    if (why) { DMLog([NSString stringWithFormat:@"[lastpage] %@: the last page opens the App Library as iPadOS has it", why]); return; }
    gDMTrailingCountSel = count;
    MSHookMessageEx(view, count, (IMP)DMTrailingPages, (IMP *)&o_DMTrailingPages);
    MSHookMessageEx(view, index, (IMP)DMTrailingPageIndex, (IMP *)&o_DMTrailingPageIndex);   // (the count and the index together, never one alone)
    Class mgr = objc_getClass("SBHIconManager");
    Method om = mgr ? class_getInstanceMethod(mgr, NSSelectorFromString(@"_updateOverscrollModalLibraryForScrollToPresented:")) : NULL;
    BOOL gate = om && !strcmp(method_getTypeEncoding(om), "v20@0:8B16");
    if (gate) MSHookMessageEx(mgr, NSSelectorFromString(@"_updateOverscrollModalLibraryForScrollToPresented:"), (IMP)DMOverscrollLibrary, (IMP *)&o_DMOverscrollLibrary);
    else DMLog(@"[lastpage] the icon manager's overscroll library call is not the known one: only the page is left out");
#if DEBUG
    Class pres = objc_getClass("SBHModalLibraryPresenter");
    Method pm = pres ? class_getInstanceMethod(pres, NSSelectorFromString(@"presentLibraryWithAnimation:completion:")) : NULL;
    if (pm && !strcmp(method_getTypeEncoding(pm), "v28@0:8B16@?20")) MSHookMessageEx(pres, NSSelectorFromString(@"presentLibraryWithAnimation:completion:"), (IMP)DMDbgPresentLib, (IMP *)&o_DMDbgPresentLib);
    Method wm = class_getInstanceMethod(view, NSSelectorFromString(@"_willScrollToPageIndex:animated:"));
    if (wm && !strcmp(method_getTypeEncoding(wm), "v28@0:8q16B24")) MSHookMessageEx(view, NSSelectorFromString(@"_willScrollToPageIndex:animated:"), (IMP)DMDbgWillScroll, (IMP *)&o_DMDbgWillScroll);
    Method dm = mgr ? class_getInstanceMethod(mgr, NSSelectorFromString(@"rootFolderController:didOverscrollOnLastPageByAmount:")) : NULL;
    if (dm && !strcmp(method_getTypeEncoding(dm), "v32@0:8@16d24")) MSHookMessageEx(mgr, NSSelectorFromString(@"rootFolderController:didOverscrollOnLastPageByAmount:"), (IMP)DMDbgOverscroll, (IMP *)&o_DMDbgOverscroll);
#endif
    // (in our constructor, before SpringBoard builds its Home Screen: its first layout counts the pages through the hook -- nothing to lay out again,
    //  and nothing of SpringBoard's asked for here, where its icon controller does not exist yet)
    DMLog([NSString stringWithFormat:@"[lastpage] -[SBRootFolderView %@] and -trailingCustomViewPageIndex hooked (pages from -%@): swiping past the last page %@", NSStringFromSelector(count), gDMTrailingGetter,
           gLastPageOpensLibrary ? @"opens the App Library (switched on)" : @"ends at the last page"]);
}

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
static BOOL DMDismissLibraryOf(id presenter, NSString *where) {
    SEL showing = NSSelectorFromString(@"isPresentingLibrary");
    if (![presenter respondsToSelector:showing] || !((BOOL (*)(id, SEL))objc_msgSend)(presenter, showing)) return NO;
    for (NSString *name in @[@"dismissLibraryWithAnimation:completion:", @"dismissLibraryAnimated:completion:"]) {
        SEL s = NSSelectorFromString(name);
        if ([presenter respondsToSelector:s]) { DMLog([NSString stringWithFormat:@"[escape] closing the App Library (%@) via %@", where, name]); ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, s, YES, nil); return YES; }
    }
    SEL toggle = NSSelectorFromString(@"toggleLibraryPresentedInForegroundWithAnimation:completion:");
    if ([presenter respondsToSelector:toggle]) { DMLog([NSString stringWithFormat:@"[escape] closing the App Library (%@) via toggle", where]); ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, toggle, YES, nil); return YES; }
    return NO;
}
BOOL DMDismissAppLibraryIfShowing(void) {
    id presenter = DMLibraryPresenter();
    BOOL closed = DMDismissLibraryOf(presenter, @"the iPad's");
    // (1.8.6, tv-parity row 39: another display (the TV) has its own App Library -- each SBWindowScene's -modalLibraryController and its
    //  -libraryPresenter (-[SBIconController createModalLibraryControllerForWindowScene:], 18.5). Only the iPad's was ever asked, so Escape never
    //  closed the TV's. Every other window scene's presenter is asked the same way; the iPad's own is the one found above)
    SEL mlc = NSSelectorFromString(@"modalLibraryController"), lp = NSSelectorFromString(@"libraryPresenter");
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (![sc isKindOfClass:[UIWindowScene class]] || ((UIWindowScene *)sc).screen == [UIScreen mainScreen] || ![sc respondsToSelector:mlc]) continue;
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(sc, mlc);
        id other = [ctrl respondsToSelector:lp] ? ((id (*)(id, SEL))objc_msgSend)(ctrl, lp) : nil;
        if (other && other != presenter && DMDismissLibraryOf(other, @"another display's")) closed = YES;
    }
    return closed;
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
    // (a finger or Pencil on the screen, a click; never a finger on the trackpad or a scroll, UITouchTypeIndirect: the pointer stays where it is, review 1.8.4.1 pass 2 H1)
    if (event.type == UIEventTypeTouches) for (UITouch *t in event.allTouches) if (t.phase == UITouchPhaseBegan && t.type != UITouchTypeIndirect) { DMDockHoverTouchBegan(); break; }
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
// 1.7.5 items 12 and 16: a pull down from the screen's top edge is Notification Center's or Control Center's (iPadOS's own pulls, SBGrabberTongue), never
// a swipe down. One that started just under the menu bar outside the windows -- or anywhere from the top while the auto-hiding bar is hidden -- also
// reached the Home Screen's search view and opened the App Library behind Notification Center (A12Z 18.5: from y 28; 16 / 17: y 6-20 with the bar
// hidden); after Notification Center closed it was still there, the windows faded away behind it (Stage Manager: the stage hidden) until a Home
// press. The start of a top-edge pull is noted (the tongue's -_pullGestureBegan:): a swipe down within half a second of it is the pull's, and an
// App Library the swipe down opened just before the pull began (the other order) is closed again at once, behind Notification Center.
static CFTimeInterval gTopPullAt = -10.0, gSwipeLibraryAt = -10.0;
static ptrdiff_t gTongueEdgeIvar = -2;   // (iPadOS 15: no -screenEdge, only the _screenEdge ivar)
static BOOL DMTongueOnTopEdge(id tongue) {
    if ([tongue respondsToSelector:NSSelectorFromString(@"screenEdge")]) {
        Method m = class_getInstanceMethod(object_getClass(tongue), NSSelectorFromString(@"screenEdge"));
        const char *enc = m ? method_getTypeEncoding(m) : NULL;
        if (enc && !strcmp(enc, "Q16@0:8")) return ((NSUInteger (*)(id, SEL))objc_msgSend)(tongue, NSSelectorFromString(@"screenEdge")) == UIRectEdgeTop;
    }
    if (gTongueEdgeIvar == -2) { Ivar iv = class_getInstanceVariable(objc_getClass("SBGrabberTongue"), "_screenEdge"); const char *e = iv ? ivar_getTypeEncoding(iv) : NULL; gTongueEdgeIvar = e && !strcmp(e, "Q") ? ivar_getOffset(iv) : -1; }
    return gTongueEdgeIvar >= 0 && *(NSUInteger *)((uint8_t *)(__bridge void *)tongue + gTongueEdgeIvar) == UIRectEdgeTop;
}
%group TopPullYield
%hook SBGrabberTongue
- (void)_pullGestureBegan:(id)gesture {
    %orig;
    if (!DMTongueOnTopEdge(self)) return;
    CFTimeInterval now = CACurrentMediaTime();
    gTopPullAt = now;
    if (now - gSwipeLibraryAt < 0.5) {   // (the swipe down came first: its App Library goes again, behind the pull's panel)
        gSwipeLibraryAt = -10.0;
        DM_FEATURE_MARK("swipe-down-yields-to-top-pull");
        DMLog([NSString stringWithFormat:@"[swipe-down] that drag is a pull from the top edge (Notification Center / Control Center): the App Library closes again (%d)", DMDismissAppLibraryIfShowing()]);
    }
}
%end
%end
// A touch the desktop has taken (MacStatusBar's, statusbar/Desktop.h -dm_touchIsOursFor:: held there long enough that a move draws its selection
// rectangle or drags an icon) is never a swipe down, nor this view's own pull: a finger held 0.35-0.45 s on the empty desktop and then moved down
// opened the App Library under the rectangle (1.7.7 fix round, both iPads). Found with dlsym (MacStatusBar may load after the Dock; without it, no
// desktop).
static BOOL DMDesktopTakesTouch(UIGestureRecognizer *gesture) {
    static BOOL (*ours)(UIGestureRecognizer *) = NULL; static int tries = 0;
    if (!ours && tries < 40) { tries++; ours = (BOOL (*)(UIGestureRecognizer *))dlsym(RTLD_DEFAULT, "MSBDDesktopTouchIsOurs"); }
    return ours && ours(gesture);
}
// The swipe down fired for this touch: the desktop is told, and lets that touch go -- whose a touch is is decided once (statusbar/DesktopHold.h,
// 1.7.8; the 1.7.7 fix-round review's N1: a pan that began just before the desktop's hold time opened the App Library, and the same finger's move a
// moment later drew the desktop's rectangle under it).
static void DMDesktopTouchGivenAway(UIGestureRecognizer *gesture) {
    static void (*given)(UIGestureRecognizer *) = NULL; static int tries = 0;
    if (!given && tries < 40) { tries++; given = (void (*)(UIGestureRecognizer *))dlsym(RTLD_DEFAULT, "MSBDDesktopTouchGivenAway"); }
    if (given) given(gesture);
}
// KT, 1.8.2: a trackpad's two-finger scroll down over the Home Screen beside a window opened the App Library -- the scroll moves this view's pan
// as a finger does (SwipeDownRule.h). With a window of ours on screen it is nothing now, as on a Mac's desktop; a finger, and a scroll with no
// window shown, as before. A window of ours: MacStatusBar's (MSBDWindowOnScreen: the window engine's on the desktop on screen, or a native one),
// found with dlsym (MacStatusBar may load after the Dock; without it, no window of ours).
#import "SwipeDownRule.h"
static BOOL DMOurWindowOnScreen(void) {
    static BOOL (*shown)(void) = NULL; static int tries = 0;
    if (!shown && tries < 40) { tries++; shown = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDWindowOnScreen"); }
    return shown && shown();
}
#if DEBUG
static BOOL DMSwipeScrollOld(void) { return access("/tmp/msb-swipescroll-old", F_OK) == 0; }   // (tests: as before 1.8.2, to compare)
#else
static BOOL DMSwipeScrollOld(void) { return NO; }
#endif
%hook SBSearchScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (DMPanStartedOnDesktopIcon(gesture)) { DMLog(@"[swipe-down] a drag from a desktop icon: not a swipe"); return NO; }
    if (DMDesktopTakesTouch(gesture)) {
        static int logged = 0;
        if (logged++ < 20) {
            CGPoint moved = [gesture isKindOfClass:[UIPanGestureRecognizer class]] ? [(UIPanGestureRecognizer *)gesture translationInView:(UIView *)self] : CGPointZero;
            DMLog([NSString stringWithFormat:@"[swipe-down] the desktop's touch (held there, then moved %.1f pt: its rectangle or an icon's drag): not a swipe", hypot(moved.x, moved.y)]);
        }
        return NO;
    }
    if (gSwipeDownOpensLibrary && DMSpotlightButtonShown() && [gesture isKindOfClass:[UIPanGestureRecognizer class]] &&
        DMSwipeIsDownward((UIPanGestureRecognizer *)gesture, (UIView *)self)) {
        if (CACurrentMediaTime() - gTopPullAt < 0.5) {   // (Notification Center's / Control Center's pull from the top edge: theirs, not a swipe down)
            DM_FEATURE_MARK("swipe-down-yields-to-top-pull");
            DMLog(@"[swipe-down] a pull from the top edge (Notification Center / Control Center) reached the Home Screen too: not a swipe down");
            return NO;
        }
        // (what drives the pan: UIKit's own scroll event on it, where -_activeEventOfType: is as on 17.6.1 -- UIEventTypeScroll, 10 --, else its touches)
        SEL ae = NSSelectorFromString(@"_activeEventOfType:");
        Method aem = class_getInstanceMethod([gesture class], ae);
        BOOL askable = aem && !strcmp(method_getTypeEncoding(aem) ?: "", "@24@0:8q16");
        id scroll = askable ? ((id (*)(id, SEL, long long))objc_msgSend)(gesture, ae, 10) : nil;
#if DEBUG
        DMLog([NSString stringWithFormat:@"[swipe-down] debug: a downward pan on the search view: touches %lu, scroll event %@, a window of ours on screen %d",
               (unsigned long)gesture.numberOfTouches, scroll ? NSStringFromClass([scroll class]) : (askable ? @"none" : @"(not askable)"), DMOurWindowOnScreen()]);
#endif
        if (!DMSwipeDownTakesPan(gesture.numberOfTouches, askable, scroll != nil, DMOurWindowOnScreen()) && !DMSwipeScrollOld()) {   // (a pointer's scroll beside a window of ours: nothing)
            DM_FEATURE_MARK("swipe-down-scroll-beside-window");
            static int skipped = 0;
            if (skipped++ < 20) DMLog(@"[swipe-down] a pointer's scroll down over the Home Screen with a window of ours on screen: not a swipe down, no App Library");
            return NO;   // (nor Spotlight's pull)
        }
        static int logged = 0;
        if (logged++ < 20) DMLog(@"[swipe-down] genuine downward drag on the Home Screen search view -> opening the App Library");
        if (DMPresentAppLibrary()) { gSwipeLibraryAt = CACurrentMediaTime(); DMDesktopTouchGivenAway(gesture); }
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
// MacStatusBar's Activity Monitor in the recents (1.7.7, statusbar/ActMonDock.h: its running entry): its own changes of the shown list are run the
// same way (found with dlsym).
__attribute__((visibility("default"))) void MSBDDockRecentsFlush(NSString *why) { DMFlushDeferredDockIcons(why); }
// ---- Apple's "Show App Library in Dock" from our Dock page, at once (1.8.4.1 item 2; common/DockAppLibrary.h) ----
// Our page posts kMSBDDockAppLibraryNote once Apple's own switch has written its value. Each of the Dock's view controllers that has icon updates parked
// runs them -- the no-argument call SpringBoard makes when a full-screen layout transition ends, which window engines never make (15.6.1: the App
// Library icon stayed until a respring) --, unless a transition is running (its own end runs them); then the Dock is laid out again. Only Apple's two
// methods, in their shapes, on the view controllers of the Dock's windows; nothing is made or changed of Apple's. The recents' own are left to their own
// step above (DMFlushDeferredDockIcons: once the fade of an icon they removed has ended -- a recent swapped in by a window just opened, then the switch
// flipped within the fade: run during it, review 1.8.4.1 L2).
static void DMDockRunParkedUpdates(NSString *why) {
    SEL pendingSel = sel_registerName("deferredIconUpdates"), perform = sel_registerName("_performDeferredIconUpdates");
    SEL coordSel = sel_registerName("layoutStateTransitionCoordinator"), busySel = sel_registerName("isTransitioning");
    NSMutableArray *todo = [NSMutableArray array];
    id sugg = gDMSuggestionsVC;
    DMFlushDeferredDockIcons(why);   // (the recents', after any fade)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO])
        if ([NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"] && w.rootViewController) [todo addObject:w.rootViewController];
#pragma clang diagnostic pop
    NSHashTable *seen = [NSHashTable weakObjectsHashTable];
    while (todo.count) {
        UIViewController *vc = todo.lastObject; [todo removeLastObject];
        if (![vc isKindOfClass:[UIViewController class]] || [seen containsObject:vc]) continue;
        [seen addObject:vc];
        [todo addObjectsFromArray:vc.childViewControllers];
        if (vc == sugg) continue;   // (the recents': above, after any fade)
        Method mp = class_getInstanceMethod(object_getClass(vc), pendingSel), mr = class_getInstanceMethod(object_getClass(vc), perform);
        const char *ep = mp ? method_getTypeEncoding(mp) : NULL, *er = mr ? method_getTypeEncoding(mr) : NULL;
        if (!ep || !er || strcmp(ep, "@16@0:8") || strcmp(er, "v16@0:8")) continue;   // (only Apple's two methods, in their shapes)
        @try {
            id list = ((id (*)(id, SEL))objc_msgSend)(vc, pendingSel);
            long pending = [list isKindOfClass:[NSArray class]] ? (long)[(NSArray *)list count] : -1;
            id coord = [vc respondsToSelector:coordSel] ? ((id (*)(id, SEL))objc_msgSend)(vc, coordSel) : nil;
            BOOL busy = coord && [coord respondsToSelector:busySel] && ((BOOL (*)(id, SEL))objc_msgSend)(coord, busySel);
            if (MSBDDockRunParked(pending, busy)) {
                ((void (*)(id, SEL))objc_msgSend)(vc, perform);
                DM_FEATURE_MARK("dock-app-library-live");
                DMLog([NSString stringWithFormat:@"[applib] %@: %@ ran its %ld parked icon update(s)", why, NSStringFromClass([vc class]), pending]);
            } else if (pending > 0) DMLog([NSString stringWithFormat:@"[applib] %@: %@ has %ld parked, left to the running transition", why, NSStringFromClass([vc class]), pending]);
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[applib] %@: %@: %@", why, NSStringFromClass([vc class]), e.reason]); }
    }
}
#if DEBUG
// (debug: the switch as SpringBoard's own defaults answer it, and the App Library icon in the Dock -- there, its place, shown -- at each pass: on 15.6.1
//  this tells whether SpringBoard heard the change and whether running its parked updates put it in, the device check of item 2)
static void DMAppLibraryDebugLine(NSString *why) {
    NSMutableString *o = [NSMutableString stringWithFormat:@"[applib] %@:", why];
    Class d = objc_getClass("SBDefaults");
    id local = d && [(id)d respondsToSelector:@selector(localDefaults)] ? ((id (*)(id, SEL))objc_msgSend)((id)d, @selector(localDefaults)) : nil;
    id fd = [local respondsToSelector:NSSelectorFromString(@"floatingDockDefaults")] ? ((id (*)(id, SEL))objc_msgSend)(local, NSSelectorFromString(@"floatingDockDefaults")) : nil;
    if ([fd respondsToSelector:NSSelectorFromString(@"appLibraryEnabled")]) [o appendFormat:@" SpringBoard's floating Dock defaults say %d;", ((BOOL (*)(id, SEL))objc_msgSend)(fd, NSSelectorFromString(@"appLibraryEnabled"))];   // (a defaults object's property is added when first asked: responds, no method to look up before)
    else [o appendString:@" no appLibraryEnabled getter;"];
    int found = 0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
#pragma clang diagnostic pop
        if (![NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"]) continue;
        NSMutableArray *todo = [NSMutableArray arrayWithObject:w];
        while (todo.count) {
            UIView *v = todo.lastObject; [todo removeLastObject];
            id icon = [v respondsToSelector:NSSelectorFromString(@"icon")] ? ((id (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"icon")) : nil;
            if ([NSStringFromClass([icon class]) isEqualToString:@"SBHLibraryPodIndicatorIcon"]) {
                found++;
                [o appendFormat:@" icon view %p in %@ at %@ hidden %d alpha %.2f;", v, NSStringFromClass([v.superview class]), NSStringFromCGRect([v convertRect:v.bounds toView:w]), v.hidden, v.alpha];
                continue;
            }
            [todo addObjectsFromArray:v.subviews];
        }
    }
    if (!found) [o appendString:@" no App Library icon view in the Dock"];
    // (what the Dock's own view controller makes of it: read only, BOOL getters in their shape. On 15.6.1 the row wrote the key, the icon stayed and no update was parked)
    NSMutableArray *vcs = [NSMutableArray array];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO])
        if ([NSStringFromClass([w class]) isEqualToString:@"SBFloatingDockWindow"] && w.rootViewController) [vcs addObject:w.rootViewController];
#pragma clang diagnostic pop
    while (vcs.count) {
        UIViewController *vc = vcs.lastObject; [vcs removeLastObject];
        [vcs addObjectsFromArray:vc.childViewControllers];
        if (![NSStringFromClass([vc class]) isEqualToString:@"SBFloatingDockViewController"]) continue;
        for (NSString *name in @[@"isLibraryPodIconEnabled", @"isLibraryPodIconVisible", @"isLibraryPodIconEffectivelyVisible"]) {
            Method bm = class_getInstanceMethod(object_getClass(vc), NSSelectorFromString(name));
            const char *be = bm ? method_getTypeEncoding(bm) : NULL;
            if (be && !strcmp(be, "B16@0:8")) [o appendFormat:@" %@ %d;", name, ((BOOL (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(name))];
            else [o appendFormat:@" no %@;", name];
        }
    }
    DMLog(o);
}
#endif
static void DMAppLibraryInDockChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef info) {
    for (int i = 0; i < kMSBDDockAppLibraryPassCount; i++) {
        int pass = i + 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMSBDDockAppLibraryPassAt[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *why = [NSString stringWithFormat:@"Show App Library in Dock changed in Settings (pass %d)", pass];
            DMDockRunParkedUpdates(why);
            DMRelayoutDock();   // (Finder, Downloads, the Trash, a side Dock's room and Edit Home Screen's stand-ins follow this layout)
            DMRefreshLaunchpadIcons();
#if DEBUG
            DMAppLibraryDebugLine(why);
#endif
        });
    }
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
%end
// ... and its grid: the list's flow layout (location SBIconLocationFloatingDockSuggestions) has 3 columns, so a 4th recent wrapped onto a second row.
// Its layout configuration gets as many columns as places (never fewer than SpringBoard's own), in both orientations, before the list lays out its
// icons. Its own group, on every version that has the grid (15-18): these hooks sat in the 15-17 list group above, which iPadOS 18 never installs
// (its recents list is made with homeScreenContextProvider:, DMRecentsList18) -- on 18 the Dock made room for 4 (the metrics: recents 282 -> 369.5
// pt wide) while the list kept 3 columns, and a Handoff suggestion as the 4th item went UNDER the three recents, a second row lifting the Dock
// (A12Z 18.5, 13 and 25 Oct).
static BOOL DMWidenRecentsLayout(id layout) {   // YES if it had to be widened
    long c = (long)DMRecentsPlaces();
    if (c <= 3 || !layout) return NO;   // (SpringBoard's own 3 columns already fit 1-3 places)
    BOOL widened = NO;
    @try {
        id cfg = [layout respondsToSelector:NSSelectorFromString(@"layoutConfiguration")] ? [layout valueForKey:@"layoutConfiguration"] : nil;
        for (NSString *o in @[@"Portrait", @"Landscape"]) {   // (the Dock is one row either way; which one the list reads depends on the version)
            SEL get = NSSelectorFromString([NSString stringWithFormat:@"numberOf%@Columns", o]), set = NSSelectorFromString([NSString stringWithFormat:@"setNumberOf%@Columns:", o]);
            if (![cfg respondsToSelector:get] || ![cfg respondsToSelector:set]) continue;
            Method gm = class_getInstanceMethod(object_getClass(cfg), get), sm = class_getInstanceMethod(object_getClass(cfg), set);
            if (!gm || !sm || strcmp(method_getTypeEncoding(gm), "Q16@0:8") != 0 || strcmp(method_getTypeEncoding(sm), "v24@0:8Q16") != 0) continue;
            unsigned long long now = ((unsigned long long (*)(id, SEL))objc_msgSend)(cfg, get);
            if (now == 0 || now >= (unsigned long long)c) continue;   // (0: no count of its own -- 18's landscape takes the portrait one)
            ((void (*)(id, SEL, unsigned long long))objc_msgSend)(cfg, set, (unsigned long long)c);
            DMLog([NSString stringWithFormat:@"[recents] the recents grid (%@): %llu -> %ld columns", o.lowercaseString, now, c]);
            widened = YES;
        }
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[recents] the recents grid: %@", e.reason]); }
    return widened;
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
%group DMRecentsGrid
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
#import "../macsettings/AutoLockGiveBack.h"   // (1.7.3: a stored 2 hours lowered while MacStatusBar's part that keeps it is not here)
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
static BOOL DMRemoveFromDock(id icon) {   // (YES: it left the Dock for the Home Screen)
    DM_FEATURE_MARK("dock-remove-from-dock");
    id mgr = nil, model = nil;
    id root = DMIconModelRoot(&mgr, &model);
    id dock = DMObj(root, @"dock");
    NSArray *icons = DMObj(dock, @"icons");
    if (!root || !dock || ![icons isKindOfClass:[NSArray class]] || ![icons containsObject:icon]) return NO;
    NSUInteger oldIndex = [icons indexOfObject:icon];
    SEL optsSel = NSSelectorFromString(@"gridCellInfoOptions"), freeSel = NSSelectorFromString(@"gridPathForFirstFreeSlotAvoidingFirstList:listGridCellInfoOptions:");
    SEL insertSel = NSSelectorFromString(@"insertIcon:atGridPath:options:"), addSel = NSSelectorFromString(@"addIcon:options:listGridCellInfoOptions:");
    SEL removeSel = NSSelectorFromString(@"removeIcons:"), putBackSel = NSSelectorFromString(@"insertIcons:atIndex:options:");
    if (![dock respondsToSelector:removeSel]) return NO;
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
        return NO;
    }
    if ([model respondsToSelector:NSSelectorFromString(@"markIconStateDirty")]) ((void (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"markIconStateDirty"));
    if ([model respondsToSelector:NSSelectorFromString(@"saveIconStateIfNeeded")]) ((BOOL (*)(id, SEL))objc_msgSend)(model, NSSelectorFromString(@"saveIconStateIfNeeded"));
    DMLog([NSString stringWithFormat:@"[dock] Remove from Dock: %@ moved to the Home Screen at %@", DMObj(icon, @"applicationBundleID"), path]);
    return YES;
}
// Our own apps kept in the Dock (1.7.3: Activity Monitor, MacStatusBar's ActMonDock.h): an icon of SpringBoard's with our identifier and no
// app; it leaves the Dock through MacStatusBar (back to the App Library, nothing on the Home Screen), found with dlsym.
static BOOL DMIsOwnAppIcon(id icon) { return [DMObj(icon, @"leafIdentifier") isEqual:@"com.besiktasliseba.macstatusbar.activitymonitor"]; }
// The Trash (TrashIcon.m): an app dragged off the Dock and dropped on the bin leaves the Dock the same way, once SpringBoard's drag has ended.
BOOL DMTrashRemoveIconFromDock(id icon) {
    if (gEnabled && DMIsOwnAppIcon(icon)) {
        static BOOL (*own)(void) = NULL; if (!own) own = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "MSBDActMonDockRemove");
        return own && own();
    }
    if (!gEnabled || !DMIconKeptInDock(icon) || ![DMObj(icon, @"applicationBundleID") isKindOfClass:[NSString class]]) return NO;
    return DMRemoveFromDock(icon);
}
// What one of SpringBoard's own icon drags carries, for a drop on the bin (common/DockTrash.h MSBDTrashRemovesFromDock): SpringBoard's icon drag
// manager knows the drag by its session (-iconDragContextForDropSession:); its context names the icons and the icon view the drag began on (its
// location: the Dock's own list, its recents, the Home Screen). NO when the session is not an icon drag of SpringBoard's.
BOOL DMTrashIconDragInfo(id session, MSBDTrashIconDrag *info, id *iconOut) {
    if (!session || !info) return NO;
    memset(info, 0, sizeof(*info));
    if (iconOut) *iconOut = nil;
    id mgr = DMObj(DMObj((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    id drags = DMObj(mgr, @"iconDragManager");
    SEL ctxSel = NSSelectorFromString(@"iconDragContextForDropSession:");
    if (![drags respondsToSelector:ctxSel]) return NO;
    id ctx = nil;
    @try { ctx = ((id (*)(id, SEL, id))objc_msgSend)(drags, ctxSel, session); } @catch (NSException *e) { ctx = nil; }
    if (!ctx) return NO;
    id dragged = DMObj(ctx, @"draggedIcons");
    info->count = [dragged respondsToSelector:@selector(count)] ? [dragged count] : 0;
    UIView *view = DMObj(ctx, @"primaryIconView");
    id icon = DMObj(view, @"icon");
    if (!icon && [dragged respondsToSelector:@selector(anyObject)]) icon = [dragged anyObject];
    info->isApp = [DMObj(icon, @"applicationBundleID") isKindOfClass:[NSString class]] || DMIsOwnAppIcon(icon);   // (Activity Monitor too, 1.7.3)
    SEL folderSel = NSSelectorFromString(@"isFolderIcon");
    info->isFolder = [icon respondsToSelector:folderSel] && ((BOOL (*)(id, SEL))objc_msgSend)(icon, folderSel);
    info->fromDock = MSBDTrashLocationIsDock(DMObj(view, @"location"));
    SEL tempSel = NSSelectorFromString(@"isManagingTemporarilyRemovedIcon:");   // (an icon dragged out of its list is taken out of it while the drag lasts)
    BOOL taken = icon && [drags respondsToSelector:tempSel] && ((BOOL (*)(id, SEL, id))objc_msgSend)(drags, tempSel, icon);
    info->keptInDock = DMIconKeptInDock(icon) || (taken && info->fromDock);
    if (iconOut) *iconOut = icon;
    return YES;
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
                    DMLog([NSString stringWithFormat:@"[k2] our slots: finder %@ downloads %@ (own %d) trash %@ divider2 %@", NSStringFromCGRect(gFinderSlot), NSStringFromCGRect(gDownloadsSlot), gDownloadsOwnSlot, NSStringFromCGRect(gTrashSlot), NSStringFromCGRect(gDivider2Rect)]);
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

// Position's hooks (see above): installed the first time Left or Right is chosen, never on the bottom.
%group DockSideRoot
%hook SBFloatingDockRootViewController
- (void)viewDidLayoutSubviews {
    %orig;
    DMDockSideApplyToRoot((UIViewController *)self);
}
%end
%end
%group DockSidePointer
%hook SBFloatingDockController
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    // (Apple's reveal at the bottom edge stands down at a side; our look at the pointer asks Apple's conditions through here)
    if (gDockSideApplied && !gDockSideAskingApple) {
        SEL rs = NSSelectorFromString(@"presentFloatingDockIndirectPanGestureRecognizer");
        if ([self respondsToSelector:rs] && g == ((id (*)(id, SEL))objc_msgSend)(self, rs)) return NO;
    }
    return %orig;
}
%end
%end
// (the Home Screen's icons stay where they are, KT 5 Nov: their rows are spaced by the Dock's height, and at a side that is another height than at the bottom)
%group DockSideHome
%hook SBHIconManager
- (double)externalDockHeightForRootFolderController:(id)c {
    CGFloat h = gDockSideApplied ? DMDockSideHeightAtBottom() : -1.0;
    double apple = %orig;
#if DEBUG
    static double lastH = -2, lastApple = -2;
    if (h != lastH || apple != lastApple) { lastH = h; lastApple = apple; DMLog([NSString stringWithFormat:@"[dockside] the Home Screen asks the Dock's height: Apple's %.1f, as at the bottom %.1f", apple, h]); }
#endif
    return h > 0.0 ? h : apple;
}
- (double)maxExternalDockHeightForRootFolderController:(id)c {
    CGFloat h = gDockSideApplied ? DMDockSideHeightAtBottom() : -1.0;
    double apple = %orig;
#if DEBUG
    static double lastH = -2, lastApple = -2;
    if (h != lastH || apple != lastApple) { lastH = h; lastApple = apple; DMLog([NSString stringWithFormat:@"[dockside] the Home Screen asks the Dock's greatest height: Apple's %.1f, as at the bottom %.1f", apple, h]); }
#endif
    return h > 0.0 ? h : apple;
}
%end
%end
// (the Dock out again after it was away: a size it laid out with meanwhile is taken now, DMDockSideHomeLaidOut)
%group DockSideHomeBack
%hook SBFloatingDockController
- (void)floatingDockRootViewControllerDidEndPresentationTransition:(id)root {
    %orig;
    DMDockSideHomeDockBack();
}
%end
%end
// (each page's icon list placed beside the Dock: DMDockSideHomeFrame above)
%group DockSideHomeLists
%hook SBRootFolderView
- (CGRect)_iconListFrameForPageRect:(CGRect)page atIndex:(unsigned long long)index {
    CGRect f = %orig;
    return DMDockSideHomeFrame((UIView *)self, f, index);
}
%end
%end
%group DockSideHomeButtons   // (Edit Home Screen's buttons beside the Dock: DMDockSideHomeEditButtons above)
%hook SBRootFolderView
- (void)_layoutSubviews {
    %orig;
    DMDockSideHomeEditButtons((UIView *)self);
}
%end
%end
%group DockSideFolder
%hook SBFolderContainerView
- (void)didMoveToSuperview {
    %orig;
    UIView *me = (UIView *)self;
    if (gDockSideHost && me.superview == gDockSideHost) DMDockSideFoldersUpright(gDockSideHost, gDockSideApplied);
}
%end
%end
// (Settings > Dock > Position: the zoom of an app going Home into its side Dock icon -- Stage Manager's Home for the desktop's last window minimized, a full-screen
//  app's Home --. SpringBoard's fluid switcher works out the icon picture's place right (-homeScreenIconFrameForAppLayout:, 18.5: the drawn 38.2 pt picture at the
//  icon's middle), then match-moves the zoom to the icon's own layer (-shouldMatchMoveIconZoomingView: YES): a layer inside the turned Dock view, so the match takes
//  the Dock's turn as well -- a mirror at Right, a rotation at Left -- and the window flew into the top-right corner at Right and off the bottom-left at Left (17.5 F1,
//  A12Z F2, 1.8.2.2). An icon of the side Dock is not match-moved: the zoom goes to the place SpringBoard worked out. Shape-checked, hooked with Left or Right chosen
//  only; any other icon as SpringBoard decides.)
@interface SBFluidSwitcherViewController : UIViewController
@end
%group DockSideZoom
%hook SBFluidSwitcherViewController
- (BOOL)shouldMatchMoveIconZoomingView:(UIView *)iconView {
    BOOL r = %orig;
    if (!r || !gDockSideApplied || ![iconView isKindOfClass:[UIView class]] || !iconView.window || !DMIsDockIcon(iconView) || !DMDockSideInHost(iconView)) return r;
    DM_FEATURE_MARK("dock-side-icon-zoom");
    DMLog(@"[dockside] an app goes into its side Dock icon: zoomed to the place SpringBoard worked out, not match-moved to the turned icon");
    return NO;
}
%end
%end
// (15, 16 and 17 match-move by a switcher modifier's response (SBMatchMoveToIconViewSwitcherEventResponse: an app layout, active to start it, not active to end
//  it), with no -shouldMatchMoveIconZoomingView: to ask: the hook above was not installed there, and the desktop's last window minimized still flew into a corner --
//  iPad 2 16.7.7, the top-right one at Right, as on the 17.5, code review 1.8.2.2, 2. The same answer: for an app whose zoom goes into the Dock (the switcher's
//  own icon location for it) while the Dock stands at a side, on the main screen's switcher, the match-move is not started, and its end not sent for one that never
//  started. The apps left out are a set, and an app's new start begins its cycle anew (DockSide.h MSBDZoomLeaveOut): a zoom cut short may never send its end, and a
//  record kept from it swallowed that app's next end, at the bottom too -- code review 1.8.2.2, second pass 1. 15.6.1 has the response too: hooked there as well.)
static NSMutableSet *gDMZoomLeftOut = nil;   // (the app layouts whose match-move was left out: their ends are left out too)
static BOOL DMDockSideZoomLeavesOut(id switcher, id response) {
    static Class rc = Nil;
    if (!rc) rc = objc_getClass("SBMatchMoveToIconViewSwitcherEventResponse");
    if (!rc || ![response isKindOfClass:rc]) return NO;   // (only the response the install read: second pass 2)
    id layout = ((id (*)(id, SEL))objc_msgSend)(response, NSSelectorFromString(@"appLayout"));
    BOOL active = ((BOOL (*)(id, SEL))objc_msgSend)(response, NSSelectorFromString(@"isActive"));
    if (!layout) return NO;
    BOOL recorded = [gDMZoomLeftOut containsObject:layout], into = NO;
    if (active && gDockSideApplied) {
        // (the main screen's switcher only, as the 18 hook's icon in our turned host: a Stage Manager display's own switcher zooms into its own Dock at its bottom,
        //  second pass 3)
        UIViewController *vc = [switcher isKindOfClass:[UIViewController class]] ? (UIViewController *)switcher : nil;
        UIWindow *w = vc.isViewLoaded ? vc.view.window : nil;
        id loc = w && w.screen == [UIScreen mainScreen] ? ((id (*)(id, SEL, id))objc_msgSend)(switcher, NSSelectorFromString(@"homeScreenIconLocationForAppLayout:"), layout) : nil;
        into = [loc isKindOfClass:[NSString class]] && MSBDZoomLocationIsDock([(NSString *)loc UTF8String]);
        DMLog([NSString stringWithFormat:@"[dockside] the switcher match-moves a zoom into its icon (location %@, main screen %d) with the Dock at a side", loc, w.screen == [UIScreen mainScreen]]);
    }
    int op = 0;
    BOOL leave = MSBDZoomLeaveOut(active, recorded, into, &op) != 0;
    if (op > 0) { if (!gDMZoomLeftOut) gDMZoomLeftOut = [NSMutableSet set]; if (gDMZoomLeftOut.count > 16) [gDMZoomLeftOut removeAllObjects]; [gDMZoomLeftOut addObject:layout]; }
    else if (op < 0) [gDMZoomLeftOut removeObject:layout];
    if (op < 0 && !leave) DMLog(@"[dockside] a match-move start of an app left out before (its zoom cut short): SpringBoard's own now, the old record gone");
#if DEBUG
    static BOOL told = NO;   // (once per SpringBoard: that the 15-17 hook acted here at all -- the M1's 15.6.1 too, second pass 8)
    if (leave && !told) { told = YES; DMLog([NSString stringWithFormat:@"[dockside] the switcher's match-move response hook acted on this iPadOS (%@)", [UIDevice currentDevice].systemVersion]); }
#endif
    return leave;
}
%group DockSideZoom17
%hook SBFluidSwitcherViewController
- (void)_performModifierMatchMoveToIconViewResponse:(id)response {
    if (DMDockSideZoomLeavesOut(self, response)) {
        DM_FEATURE_MARK("dock-side-icon-zoom");
        DMLog([NSString stringWithFormat:@"[dockside] an app goes into its side Dock icon: %@ match-move left out, zoomed to the place SpringBoard worked out", ((BOOL (*)(id, SEL))objc_msgSend)(response, NSSelectorFromString(@"isActive")) ? @"the" : @"the end of the"]);
        return;
    }
    %orig;
}
%end
%end
#if DEBUG
// (debug: what the switcher's zoom into a Dock icon asks, read while the Dock is at a side -- which of its questions carries the place)
static NSString *DMZoomViewText(UIView *v) {
    if (![v isKindOfClass:[UIView class]]) return v ? NSStringFromClass([v class]) : @"nil";
    CGRect s = v.window ? [v convertRect:v.bounds toCoordinateSpace:[UIScreen mainScreen].coordinateSpace] : CGRectNull;
    return [NSString stringWithFormat:@"%@ %p in %@ on screen %@ transform %@", NSStringFromClass([v class]), v, NSStringFromClass([v.window class]), NSStringFromCGRect(s), NSStringFromCGAffineTransform(v.transform)];
}
%group DockSideZoomDebug
%hook SBFluidSwitcherViewController
- (CGRect)homeScreenIconFrameForAppLayout:(id)layout {
    CGRect r = %orig;
    DMLog([NSString stringWithFormat:@"[zoomdebug] homeScreenIconFrameForAppLayout -> %@", NSStringFromCGRect(r)]);
    return r;
}
- (id)homeScreenIconLocationForAppLayout:(id)layout {
    id r = %orig;
    DMLog([NSString stringWithFormat:@"[zoomdebug] homeScreenIconLocationForAppLayout -> %@", r]);
    return r;
}
- (id)matchingIconZoomingViewForIconZoomingView:(UIView *)v {
    id r = %orig;
    DMLog([NSString stringWithFormat:@"[zoomdebug] matchingIconZoomingViewForIconZoomingView %@ -> %@", DMZoomViewText(v), DMZoomViewText(r)]);
    return r;
}
- (id)iconZoomingViewContainerForIconZoomingView:(UIView *)v {
    id r = %orig;
    DMLog([NSString stringWithFormat:@"[zoomdebug] iconZoomingViewContainerForIconZoomingView %@ -> %@", DMZoomViewText(v), DMZoomViewText(r)]);
    return r;
}
%end
%end
#endif
%group DockSideTouches
%hook SBIconView
// (an icon view that comes into the side Dock without a layout of its own -- built and laid out before it was added, a recents change, a Handoff tile -- is turned
//  upright as it arrives, its dot with it; one that leaves gets back what it had. Before, its content stood mirrored until its next layout: M1 F5, 1.8.2.2)
- (void)didMoveToWindow {
    %orig;
    if (!gDockSideEver || !((UIView *)self).window) return;
    BOOL dock = gDockSideApplied && DMIsDockIcon((UIView *)self) && DMDockSideInHost((UIView *)self);
    DMDockSideStyleIcon((UIView *)self, dock ? gDockSideApplied : 0);
}
- (void)didMoveToSuperview {
    %orig;
    if (!gDockSideEver || !((UIView *)self).window) return;
    BOOL dock = gDockSideApplied && DMIsDockIcon((UIView *)self) && DMDockSideInHost((UIView *)self);
    DMDockSideStyleIcon((UIView *)self, dock ? gDockSideApplied : 0);
}
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    BOOL r = %orig;
    if (!r || !gDockSideApplied || gDockSideStep <= 0 || !DMIsDockIcon((UIView *)self) || !DMDockSideInHost((UIView *)self)) return r;   // (a TV's Dock icon: its whole view)
    return MSBDDockIconTakesTouch(p, ((UIView *)self).bounds, gDockSideStep);
}
%end
%end
// A recents icon fading in (-[SBFloatingDockSuggestionsViewController _fadeInIcon:isReplacing:completion:]: a Handoff tile coming, the app's own
// icon back when the tile goes, a recents change) has its layer's sublayerTransform set again inside that call by Atria, which lays its icon
// scale there -- read on the M1 with the turn watch (1.8.3 item 7, regression-1.8.2.2-m1.md F1): set to the identity by Atria.dylib, under
// -_fadeInIcon:isReplacing:completion: from -dockSuggestionsModel:didInsertItem:atIndex:involvesContinuity:, after our arrival hooks had turned
// it. Our turn goes on top of what is under it (DMDockSideStyleIcon), so once that call is over the recents' icons are turned again, over the
// value just written, and once more on the next turn of the main loop for a write made right after it. Hooked on that exact type only.
static void (*o_DockFadeIn)(id, SEL, id, BOOL, id);
static void DMDockFadeIn(id self, SEL _cmd, id icon, BOOL replacing, id completion) {
    o_DockFadeIn(self, _cmd, icon, replacing, completion);
    if (!gDockSideApplied) return;
    UIViewController *vc = self;
    UIView *root = [vc isViewLoaded] ? vc.view : nil;
    if (!root) return;
    DMDockSideStyleAll(root, gDockSideApplied);
    __weak UIView *weakRoot = root;
    dispatch_async(dispatch_get_main_queue(), ^{ UIView *r = weakRoot; if (r && gDockSideApplied) DMDockSideStyleAll(r, gDockSideApplied); });
}
static void DMDockSideHookFadeIn(void) {
    Class c = objc_getClass("SBFloatingDockSuggestionsViewController");
    SEL sel = NSSelectorFromString(@"_fadeInIcon:isReplacing:completion:");
    Method m = c ? class_getInstanceMethod(c, sel) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v36@0:8@16B24@?28")) { DMLog(@"[dockside] the recents' fade-in is not as read here: a recents icon is turned at its next layout"); return; }
    MSHookMessageEx(c, sel, (IMP)DMDockFadeIn, (IMP *)&o_DockFadeIn);
}
static void DMDockSideChoose(void) {
    if (gDockPosition != MSBDDockBottom) {
        static BOOL installed = NO;
        if (!installed) {
            installed = YES;
            DM_FEATURE_MARK("dock-side-hooks");
            DMDockSideHookFadeIn();
            if (objc_getClass("SBFloatingDockRootViewController")) %init(DockSideRoot);
            if ([objc_getClass("SBFloatingDockController") instancesRespondToSelector:@selector(gestureRecognizerShouldBegin:)]) %init(DockSidePointer);
            %init(DockSideTouches);
            if (objc_getClass("SBFolderContainerView")) %init(DockSideFolder);
            Class swc = objc_getClass("SBFluidSwitcherViewController"), mmr = objc_getClass("SBMatchMoveToIconViewSwitcherEventResponse");
            Method zm = class_getInstanceMethod(swc, NSSelectorFromString(@"shouldMatchMoveIconZoomingView:"));
            Method zp = class_getInstanceMethod(swc, NSSelectorFromString(@"_performModifierMatchMoveToIconViewResponse:")), zl = class_getInstanceMethod(swc, NSSelectorFromString(@"homeScreenIconLocationForAppLayout:"));
            Method ra = class_getInstanceMethod(mmr, NSSelectorFromString(@"appLayout")), rk = class_getInstanceMethod(mmr, NSSelectorFromString(@"isActive"));
            if (zm && !strcmp(method_getTypeEncoding(zm) ?: "", "B24@0:8@16")) %init(DockSideZoom);   // (18)
            else if (zp && zl && ra && rk && !strcmp(method_getTypeEncoding(zp) ?: "", "v24@0:8@16") && !strcmp(method_getTypeEncoding(zl) ?: "", "@24@0:8@16")
                     && !strcmp(method_getTypeEncoding(ra) ?: "", "@16@0:8") && !strcmp(method_getTypeEncoding(rk) ?: "", "B16@0:8")) {   // (15, 16, 17)
                %init(DockSideZoom17);
                DMLog([NSString stringWithFormat:@"[dockside] the switcher's match-move response is hooked for the side Dock's zoom (iPadOS %@)", [UIDevice currentDevice].systemVersion]);
            }
            else DMLog(@"[dockside] the switcher's icon zoom is not as expected here: an app's zoom into a side Dock icon stays SpringBoard's");
#if DEBUG
            {
                Class sw = objc_getClass("SBFluidSwitcherViewController");
                const char *want[][2] = { {"homeScreenIconFrameForAppLayout:", "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8@16"}, {"homeScreenIconLocationForAppLayout:", "@24@0:8@16"},
                    {"matchingIconZoomingViewForIconZoomingView:", "@24@0:8@16"}, {"iconZoomingViewContainerForIconZoomingView:", "@24@0:8@16"} };
                BOOL all = sw != Nil;
                for (int i = 0; i < 4 && all; i++) { Method m = class_getInstanceMethod(sw, sel_registerName(want[i][0])); all = m && !strcmp(method_getTypeEncoding(m) ?: "", want[i][1]); }
                if (all) %init(DockSideZoomDebug);
            }
#endif
            Class hm = objc_getClass("SBHIconManager");
            Method hm1 = hm ? class_getInstanceMethod(hm, NSSelectorFromString(@"externalDockHeightForRootFolderController:")) : NULL, hm2 = hm ? class_getInstanceMethod(hm, NSSelectorFromString(@"maxExternalDockHeightForRootFolderController:")) : NULL;
            if (hm1 && hm2 && !strcmp(method_getTypeEncoding(hm1) ?: "", "d24@0:8@16") && !strcmp(method_getTypeEncoding(hm2) ?: "", "d24@0:8@16")) %init(DockSideHome);
            else DMLog(@"[dockside] the Home Screen's Dock height is not as expected here: its icons may move a little with the Dock at a side");
            Class rv = objc_getClass("SBRootFolderView");
            Method lf = rv ? class_getInstanceMethod(rv, NSSelectorFromString(@"_iconListFrameForPageRect:atIndex:")) : NULL;
            if (lf && !strcmp(method_getTypeEncoding(lf) ?: "", "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16Q48")) { %init(DockSideHomeLists); gDockSideHomeHooked = YES; }
            else DMLog(@"[dockside] the Home Screen's page frames are not as expected here: its icons stay where they are with the Dock at a side");
            Method lay = rv ? class_getInstanceMethod(rv, NSSelectorFromString(@"_layoutSubviews")) : NULL;
            if (gDockSideHomeHooked && lay && !strcmp(method_getTypeEncoding(lay) ?: "", "v16@0:8")) %init(DockSideHomeButtons);
            Method back = class_getInstanceMethod(objc_getClass("SBFloatingDockController"), NSSelectorFromString(@"floatingDockRootViewControllerDidEndPresentationTransition:"));
            if (gDockSideHomeHooked && back && !strcmp(method_getTypeEncoding(back) ?: "", "v24@0:8@16")) %init(DockSideHomeBack);
            else if (gDockSideHomeHooked) DMLog(@"[dockside] the Dock's presentation end is not as expected here: a size it takes while away waits for its next layout");
#if DEBUG
            DMDockSideHomeCheckHook();
#endif
        }
    }
    if (gDockPosition != MSBDDockBottom || gDockSideApplied) DMDockSideRefresh();
}
// ---- Edit Home Screen (1.8.3 item 5): our items as Apple's Dock icons while the Home Screen is in edit mode (EditProxy.m, EditProxyRule.h) ----
// The Dock's own controller is told when editing starts and ends (-[SBFloatingDockViewController setEditing:animated:], 15-18): its Dock's
// platter then covers our items with icon views of SpringBoard's own. Hooked on that exact type only.
static void (*o_DockSetEditing)(id, SEL, BOOL, BOOL);
static UIView *DMEditPlatterOf(UIViewController *vc) {
    Class pc = objc_getClass("SBFloatingDockPlatterView");
    UIView *root = [vc isViewLoaded] ? vc.view : nil;
    NSMutableArray<UIView *> *todo = root ? [NSMutableArray arrayWithObject:root] : [NSMutableArray array];
    while (todo.count) { UIView *v = todo.lastObject; [todo removeLastObject]; if (pc && [v isKindOfClass:pc]) return v; [todo addObjectsFromArray:v.subviews]; }
    return nil;
}
static const void *kDMEditPlatterKey = &kDMEditPlatterKey;   // (on a Dock controller: its platter, weakly -- the end of editing undoes that Dock's only)
static void DMDockSetEditing(id self, SEL _cmd, BOOL editing, BOOL animated) {
    o_DockSetEditing(self, _cmd, editing, animated);
    extern void DMDockAutoHideSetEditing(BOOL editing);   // (DockAutoHide.m: a Dock that hides itself shows while the Home Screen is edited)
    DMDockAutoHideSetEditing(editing);
    UIView *platter = DMEditPlatterOf(self);
    NSHashTable *box = objc_getAssociatedObject(self, kDMEditPlatterKey);
    if (platter) { box = [NSHashTable weakObjectsHashTable]; [box addObject:platter]; objc_setAssociatedObject(self, kDMEditPlatterKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    DMEditProxiesApply(platter ?: box.anyObject, editing, animated, gLaunchpadIcon, gLaunchpadClassic, YES);   // (not found now: the one this controller had; the end puts back what it changed there)
}
static void DMEditHook(void) {
    Class c = objc_getClass("SBFloatingDockViewController");
    Method m = c ? class_getInstanceMethod(c, @selector(setEditing:animated:)) : NULL;
    if (!m || strcmp(method_getTypeEncoding(m) ?: "", "v24@0:8B16B20")) { DMLog(@"[editmode] the Dock's controller is not as read here: our items stay as they are in Edit Home Screen"); return; }
    MSHookMessageEx(c, @selector(setEditing:animated:), (IMP)DMDockSetEditing, (IMP *)&o_DockSetEditing);
    [[NSNotificationCenter defaultCenter] addObserverForName:DMIconThemeChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        DMEditProxiesThemeChangedAll();   // (SnowBoard refreshed: every editing Dock's icon views show the new pictures at once)
    }];
}
// Animate Opening Applications (1.8.4 item 2, Bounce.m): a Dock icon's tap, where every icon tap starts (before 15/16's -_handleTap and 17's
// -_handleTapWithModifierFlags:, and the engines' hooks on those). Asked before the tap goes on -- the app is not running yet --, started after it.
// Installed only where the method has its 15-18 shape (%ctor).
extern NSString *DMBounceTapWanted(UIView *iconView, UIGestureRecognizer *g);
extern void DMBounceTapped(UIView *iconView, NSString *bid);
%group DMBounceTap
%hook SBIconView
- (void)tapGestureDidChange:(UIGestureRecognizer *)g {
    NSString *bid = DMBounceTapWanted((UIView *)self, g);
    %orig;
    DMBounceTapped((UIView *)self, bid);
}
%end
%end
%ctor {
    %init;
    DMEditHook();
    {   // (Animate Opening Applications: the icon tap's recognizer action, in its 15-18 shape -- v@:@ with any frame sizes)
        Method m = class_getInstanceMethod(objc_getClass("SBIconView"), NSSelectorFromString(@"tapGestureDidChange:"));
        char shape[32] = {0}; size_t n = 0;
        for (const char *e = m ? method_getTypeEncoding(m) : ""; e && *e && n + 1 < sizeof shape; e++) if (*e < '0' || *e > '9') shape[n++] = *e;
        if (!strcmp(shape, "v@:@")) %init(DMBounceTap);
        else DMLog([NSString stringWithFormat:@"[bounce] -[SBIconView tapGestureDidChange:] is %s here: Dock icons do not bounce", m ? shape : "missing"]);
    }
    {   // (1.7.5 items 12 / 16: a pull from the top edge is never a swipe down -- where the tongue's pull start is as on 15-18)
        Method m = class_getInstanceMethod(objc_getClass("SBGrabberTongue"), NSSelectorFromString(@"_pullGestureBegan:"));
        const char *enc = m ? method_getTypeEncoding(m) : NULL;
        if (enc && !strcmp(enc, "v24@0:8@16")) %init(TopPullYield);
        else DMLog([NSString stringWithFormat:@"[swipe-down] the top edge's pull start is not the known one (%s): a swipe down is not told from a pull", enc ?: "missing"]);
    }
    MSBDWatchMacStatusBarOff();   // ("MacStatusBar Is Off": this line runs while MacStatusBar is off, see OffAlert.h)
    MSAutoLockWatchFromDock(^(NSString *l) { DMLog(l); });   // (Auto-Lock 2 hours left behind: likewise, AutoLockGiveBack.h)
    {
        Method m = class_getInstanceMethod(objc_getClass("SBFloatingDockSuggestionsModel"), NSSelectorFromString(@"_updateCurrentDisplayItemsAfterContinuityChange:notifyDelegate:"));
        const char *enc = m ? method_getTypeEncoding(m) : NULL;
        if (enc && !strcmp(enc, "v24@0:8B16B20")) %init(DMShownListFix);
        else DMLog([NSString stringWithFormat:@"[recents] the shown-list build is not the known one (%s): left alone", enc ?: "missing"]);
    }
    if ([objc_getClass("SBFloatingDockSuggestionsViewController") instancesRespondToSelector:NSSelectorFromString(@"initWithNumberOfRecents:iconController:applicationController:layoutStateTransitionCoordinator:suggestionsModel:iconViewProvider:")]) %init(DMRecentsList);
    else DMLog(@"[recents] this iOS has no -[SBFloatingDockSuggestionsViewController initWithNumberOfRecents:...]: the list keeps SpringBoard's size");
    {   // (the recents grid, every version that has it: 15-17 and 18 -- DMWidenRecentsLayout)
        Method lm = class_getInstanceMethod(objc_getClass("SBHDefaultIconListLayoutProvider"), NSSelectorFromString(@"layoutForIconLocation:"));
        if (lm && !strcmp(method_getTypeEncoding(lm), "@24@0:8@16") && objc_getClass("SBDockSuggestionsIconListView")) %init(DMRecentsGrid);
        else DMLog(@"[recents] the recents grid is not the known one here: its columns are left as SpringBoard has them");
    }
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
            char word[96] = {0}; FILE *f = fopen("/tmp/dockmag-escape", "r"); if (f) { if (fscanf(f, "%95s", word) != 1) word[0] = 0; fclose(f); }
            if (!strcmp(word, "present")) {
                id presenter = DMLibraryPresenter();
                SEL present = NSSelectorFromString(@"presentLibraryWithAnimation:completion:");
                DMLog([NSString stringWithFormat:@"[escape] debug: presenting the library (presenter %@)", presenter ? @"found" : @"missing"]);
                if ([presenter respondsToSelector:present]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(presenter, present, YES, nil);
            } else if (!strncmp(word, "size=", 5)) {   // debug: size=<n> tries an Icon Size in memory only (not saved); size=off reads the setting again
                if (!strcmp(word + 5, "off")) DMLoadPrefs(); else gIconSize = atof(word + 5);
                DMLog([NSString stringWithFormat:@"[fit] debug: icon size setting %.2f", gIconSize]);
                DMRelayoutDock();
            } else if (!strncmp(word, "trash:", 6)) {   // debug (1.7.0): the Dock's Trash -- trash:tap, trash:empty, trash:hover1/0, trash:eject1/0, trash:state, trash:removeicon_<bundle>
                extern void DMTrashDebug(NSString *cmd);
                DMTrashDebug([NSString stringWithUTF8String:word + 6]);
            } else if (!strcmp(word, "ithm")) {   // debug (1.7.5 item 7): the items' app-icon pictures, asked and on screen (IconTheme.m)
                extern void DMIconThemeDebug(void);
                DMIconThemeDebug();
            } else if (!strncmp(word, "bounce_", 7)) {   // debug (1.8.4 item 2): bounce_<bundle> -- that app's Dock icon bounces as if tapped while it opens (Bounce.m)
                extern void DMBounceDebug(NSString *bid);
                DMBounceDebug([NSString stringWithUTF8String:word + 7]);
            } else if (!strcmp(word, "dots")) {   // debug (1.7.8.1): every running app as the running dot's rule reads it (RunningIndicator.m)
                extern void DMRunningDotsDebug(void);
                DMRunningDotsDebug();
            } else if (!strcmp(word, "turnwatch") || !strcmp(word, "turnwatch0")) {   // debug (1.8.3 item 7): every write of a Dock icon's turn that is not ours, and who wrote it
                extern void DMDockTurnWatch(BOOL on);
                DMDockTurnWatch(!strcmp(word, "turnwatch"));
            } else if (!strcmp(word, "turns")) {   // debug (1.8.3 item 7): every icon view in the Dock window, where it is, and its turn
                extern void DMDockTurnsDump(void);
                DMDockTurnsDump();
            } else if (!strcmp(word, "stylepics")) {   // debug (1.8.4 device pass): each Dock icon's picture as Glass Shelf's reflections see it
                extern void DMDockStylePicsDebug(void);
                DMDockStylePicsDebug();
            } else if (!strcmp(word, "dockasserts")) {   // debug (1.8.4 item 4): the Dock controllers' behavior assertions by level, read only
                extern void DMDockAssertsDebug(void);
                DMDockAssertsDebug();
            } else if (!strcmp(word, "dockask")) {   // debug (1.8.4 item 4): what Apple's rules answer now for the pointer's reveal (its should-begin, the home gesture's owner), read only
                extern void DMDockAskDebug(void);
                DMDockAskDebug();
            } else if (!strcmp(word, "smdock")) {   // debug (1.8.4 item 4): Stage Manager's Dock tick as SpringBoard holds it now (its defaults, the switcher's prefersDockHidden), read only
                extern void DMSMDockDebug(void);
                DMSMDockDebug();
            } else if (!strcmp(word, "smdockset0") || !strcmp(word, "smdockset1")) {   // debug (1.8.4 item 4): Stage Manager's Dock tick set through SpringBoard's own defaults (setChamoisHideDock:)
                extern void DMSMDockSetDebug(BOOL hide);
                DMSMDockSetDebug(word[9] == '1');
            } else if (!strcmp(word, "editprobe")) {   // debug (1.8.3 item 5): each icon view of the Dock in Edit Home Screen -- its editing, jitter, location, delegate
                extern void DMDockEditProbe(void);
                DMDockEditProbe();
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
    if (gDockPosition != MSBDDockBottom) DMDockSideChoose();   // (Position: its hooks before the Dock is laid out)
    DMLastPageInit();   // (after the switch is read: the App Library's last page, KT 1.7.8)
    DMStartRunningIndicatorPoll();   // periodic dot resync (RunningIndicator.m) -- catches Force Quit All / 3D-Touch quit / App Switcher, not just layoutSubviews
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    DMPrefsChanged, DM_NOTIFY, NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,   // (Apple's App Library switch on our Dock page: 1.8.4.1 item 2)
                                    DMAppLibraryInDockChanged, CFSTR(kMSBDDockAppLibraryNote), NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}

#if DEBUG
// ---- debug (1.8.4 item 4): dockasserts, read only ----
// Each SBFloatingDockController (the one of each Dock window) with what it shows (presented, fully, gesture possible, by the pointer, the active
// assertion) and every SBFloatingDockBehaviorAssertion it holds, level by level (its _floatingDockBehaviorAssertionsByLevel pointer array, each
// entry a collection of assertions or one): level, progress, gesture possible, reason. Only Apple's getters, in their shapes; nothing is created.
void DMDockAssertsDebug(void) {
    BOOL (^shape)(id, const char *, const char *) = ^BOOL(id o, const char *sel, const char *enc) {
        Method m = o ? class_getInstanceMethod(object_getClass(o), sel_registerName(sel)) : NULL;
        return m && method_getTypeEncoding(m) && !strcmp(method_getTypeEncoding(m), enc);
    };
    NSString *(^one)(id) = ^NSString *(id a) {
        if (!a) return @"-";
        unsigned long long lv = shape(a, "level", "Q16@0:8") ? ((unsigned long long (*)(id, SEL))objc_msgSend)(a, sel_registerName("level")) : 999;
        double pr = shape(a, "progress", "d16@0:8") ? ((double (*)(id, SEL))objc_msgSend)(a, sel_registerName("progress")) : -1;
        BOOL gp = shape(a, "gesturePossible", "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(a, sel_registerName("gesturePossible"));
        id rs = shape(a, "reason", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(a, sel_registerName("reason")) : nil;
        return [NSString stringWithFormat:@"%@ %p level %llu progress %.2f gesture %d reason \"%@\"", NSStringFromClass([a class]), a, lv, pr, gp, rs ?: @"-"];
    };
    int n = 0;
    extern NSArray *DMDockAutoHideControllers(void);   // (DockAutoHide.m: each Dock window's controller, and the icon controller's on 15)
    for (id ctrl in DMDockAutoHideControllers()) {
        UIWindow *w = shape(ctrl, "floatingDockWindow", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("floatingDockWindow")) : nil;
        n++;
        BOOL (^b)(const char *) = ^BOOL(const char *sel) { return shape(ctrl, sel, "B16@0:8") && ((BOOL (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName(sel)); };
        id active = shape(ctrl, "activeAssertion", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("activeAssertion")) : nil;
        NSMutableString *o = [NSMutableString stringWithFormat:@"[dockasserts] %@ %p (screen %@, window level %.0f): presented %d fully %d gesture possible %d by pointer %d; active %@",
            NSStringFromClass([ctrl class]), ctrl, NSStringFromCGSize(w.screen.bounds.size), w.windowLevel, b("isFloatingDockPresented"), b("isFloatingDockFullyPresented"),
            b("isGesturePossible"), b("wasFloatingDockPresentedByPointer"), one(active)];
        Ivar iv = class_getInstanceVariable(object_getClass(ctrl), "_floatingDockBehaviorAssertionsByLevel");
        const char *t = iv ? ivar_getTypeEncoding(iv) : NULL;
        int levels = MSBDAutoHideLevelsOf(t);   // (0: not exactly that shape, not read -- DockAutoHide.h, as DockAutoHide.m)
        if (levels > 0) {
            // (a C array of pointer arrays, one per level, in the controller itself: read at the ivar's offset, as ivar_getTypeEncoding has it)
            __unsafe_unretained id *byLevel = (__unsafe_unretained id *)(void *)((char *)(__bridge void *)ctrl + ivar_getOffset(iv));
            for (int i = 0; i < levels; i++) {
                id e = byLevel[i];
                if (![e isKindOfClass:[NSPointerArray class]]) continue;
                NSPointerArray *pa = e;
                for (NSUInteger k = 0; k < pa.count; k++) { id a = (__bridge id)[pa pointerAtIndex:k]; if (a) [o appendFormat:@"\n  [%d] %@", i, one(a)]; }
            }
        } else [o appendFormat:@"\n  (no _floatingDockBehaviorAssertionsByLevel as expected here: %s)", t ?: "absent"];
        for (NSString *name in @[@"_activeGestureFloatingDockBehaviorAssertion", @"_todayViewFloatingDockBehaviorAssertion", @"_openFolderOverHomeScreenFloatingDockBehaviorAssertion"]) {
            Ivar v2 = class_getInstanceVariable(object_getClass(ctrl), name.UTF8String);
            const char *t2 = v2 ? ivar_getTypeEncoding(v2) : NULL;
            if (t2 && t2[0] == '@') [o appendFormat:@"\n  %@: %@", name, one(object_getIvar(ctrl, v2))];
        }
        DMLog(o);
    }
    if (!n) DMLog(@"[dockasserts] no Dock controller found");
}
// dockask: each Dock controller's answers now -- gesture possible, Apple's _allowGestureRecognizers and _canPresentFloatingDock, its z-stack participant's
// ownsHomeGesture (the pointer's reveal needs it) and its description, and the should-begin of the pointer's reveal (as DMDockSideMayCome asks it). Read only.
void DMDockAskDebug(void) {
    BOOL (^shape)(id, const char *, const char *) = ^BOOL(id o, const char *sel, const char *enc) {
        Method m = o ? class_getInstanceMethod(object_getClass(o), sel_registerName(sel)) : NULL;
        return m && method_getTypeEncoding(m) && !strcmp(method_getTypeEncoding(m), enc);
    };
    extern NSArray *DMDockAutoHideControllers(void);
    for (id ctrl in DMDockAutoHideControllers()) {
        UIWindow *w = shape(ctrl, "floatingDockWindow", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("floatingDockWindow")) : nil;
        int (^b)(id, const char *) = ^int(id o, const char *sel) { return shape(o, sel, "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : -1; };
        Ivar zi = class_getInstanceVariable(object_getClass(ctrl), "_zStackParticipant");
        id zp = zi && ivar_getTypeEncoding(zi) && ivar_getTypeEncoding(zi)[0] == '@' ? object_getIvar(ctrl, zi) : nil;
        id pan = shape(ctrl, "presentFloatingDockIndirectPanGestureRecognizer", "@16@0:8") ? ((id (*)(id, SEL))objc_msgSend)(ctrl, sel_registerName("presentFloatingDockIndirectPanGestureRecognizer")) : nil;
        int begin = pan && shape(ctrl, "gestureRecognizerShouldBegin:", "B24@0:8@16") ? ((BOOL (*)(id, SEL, id))objc_msgSend)(ctrl, @selector(gestureRecognizerShouldBegin:), pan) : -1;
        NSString *zd = [[zp description] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        DMLog([NSString stringWithFormat:@"[dockask] %@ %p (screen %@): presented %d gesture possible %d allow gestures %d can present %d; pointer reveal should begin %d; z-stack %@ owns home gesture %d: %@",
            NSStringFromClass([ctrl class]), ctrl, NSStringFromCGSize(w.screen.bounds.size), b(ctrl, "isFloatingDockPresented"), b(ctrl, "isGesturePossible"), b(ctrl, "_allowGestureRecognizers"),
            b(ctrl, "_canPresentFloatingDock"), begin, zp ? NSStringFromClass([zp class]) : @"-", b(zp, "ownsHomeGesture"), zd.length > 700 ? [zd substringToIndex:700] : (zd ?: @"-")]);
    }
}
// smdock: Stage Manager's Dock tick as SpringBoard holds it -- +[SBDefaults localDefaults]'s app switcher defaults (chamoisHideDock, as its own getter
// answers), the stored value (CFPreferences), and each SBFluidSwitcherViewController found under the windows' view controllers (prefersDockHidden). Read only.
void DMSMDockDebug(void) {
    NSMutableString *o = [NSMutableString stringWithString:@"[smdock]"];
    CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("SBChamoisHideDock"), CFSTR("com.apple.springboard"));
    [o appendFormat:@" stored %@;", v ? (__bridge id)v : @"(absent)"];
    if (v) CFRelease(v);
    Class d = objc_getClass("SBDefaults");
    id local = d && [(id)d respondsToSelector:@selector(localDefaults)] ? ((id (*)(id, SEL))objc_msgSend)((id)d, @selector(localDefaults)) : nil;
    for (NSString *name in @[@"appSwitcherDefaults", @"switcherDefaults", @"chamoisDefaults", @"floatingDockDefaults"]) {
        SEL s = NSSelectorFromString(name);
        id dom = [local respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(local, s) : nil;
        if (!dom) continue;
        [o appendFormat:@" %@ %@", name, NSStringFromClass([dom class])];
        for (NSString *g in @[@"chamoisHideDock", @"chamoisHideDockExternal", @"chamoisHideStrips"]) {
            Method m = class_getInstanceMethod(object_getClass(dom), NSSelectorFromString(g));
            const char *e = m ? method_getTypeEncoding(m) : NULL;
            if (e && (!strcmp(e, "B16@0:8") || !strcmp(e, "B@:"))) [o appendFormat:@" %@ %d", g, ((BOOL (*)(id, SEL))objc_msgSend)(dom, NSSelectorFromString(g))];   // (a defaults domain's getter)
            else if (e) [o appendFormat:@" %@ (%s)", g, e];
        }
        [o appendString:@";"];
    }
    {   // (Stage Manager's settings: +[SBAppSwitcherDomain rootSettings].chamoisSettings, its cached ticks)
        Class dc = objc_getClass("SBAppSwitcherDomain");
        id rs = dc && [(id)dc respondsToSelector:NSSelectorFromString(@"rootSettings")] ? ((id (*)(id, SEL))objc_msgSend)((id)dc, NSSelectorFromString(@"rootSettings")) : nil;
        id cs = [rs respondsToSelector:NSSelectorFromString(@"chamoisSettings")] ? ((id (*)(id, SEL))objc_msgSend)(rs, NSSelectorFromString(@"chamoisSettings")) : nil;
        [o appendFormat:@" chamoisSettings %@ %p", cs ? NSStringFromClass([cs class]) : @"-", cs];
        for (NSString *iv in @[@"_cachedChamoisHideDock", @"_cachedChamoisHideDockExternal", @"_cachedChamoisHideStrips"]) {
            Ivar i = cs ? class_getInstanceVariable(object_getClass(cs), iv.UTF8String) : NULL;
            const char *t = i ? ivar_getTypeEncoding(i) : NULL;
            if (t && !strcmp(t, "B")) [o appendFormat:@" %@ %d", iv, *((BOOL *)(void *)((char *)(__bridge void *)cs + ivar_getOffset(i)))];
        }
        [o appendString:@";"];
    }
    NSMutableArray *stack = [NSMutableArray array];
    for (UIWindow *w in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) if (w.rootViewController) [stack addObject:w.rootViewController];
    Class fs = objc_getClass("SBFluidSwitcherViewController");
    int seen = 0;
    while (stack.count && seen < 2000) {
        UIViewController *vc = stack.lastObject; [stack removeLastObject]; seen++;
        if (fs && [vc isKindOfClass:fs]) {
            Method m = class_getInstanceMethod(object_getClass(vc), sel_registerName("prefersDockHidden"));
            const char *e = m ? method_getTypeEncoding(m) : NULL;
            UIWindowScene *scene = vc.viewIfLoaded.window.windowScene;
            [o appendFormat:@" %@ %p (scene %p, screen %@) prefersDockHidden %d;", NSStringFromClass([vc class]), vc, scene, scene ? NSStringFromCGSize(scene.screen.bounds.size) : @"-",
                e && !strcmp(e, "B16@0:8") ? ((BOOL (*)(id, SEL))objc_msgSend)(vc, sel_registerName("prefersDockHidden")) : -1];
        }
        [stack addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [stack addObject:vc.presentedViewController];
    }
    DMLog(o);
}
// smdockset0 / smdockset1: Stage Manager's own Dock tick set through SpringBoard's setter, as Control Center's Stage Manager options set it (a device test of
// "Apple's tick moved: our switch follows", StatusBar.x DMDockAutoHideSyncSM). Debug only.
static id DMSMAppSwitcherDefaultsDebug(void) {
    Class d = objc_getClass("SBDefaults");
    id local = d && [(id)d respondsToSelector:@selector(localDefaults)] ? ((id (*)(id, SEL))objc_msgSend)((id)d, @selector(localDefaults)) : nil;
    return [local respondsToSelector:NSSelectorFromString(@"appSwitcherDefaults")] ? ((id (*)(id, SEL))objc_msgSend)(local, NSSelectorFromString(@"appSwitcherDefaults")) : nil;
}
void DMSMDockSetDebug(BOOL hide) {
    id dom = DMSMAppSwitcherDefaultsDebug();
    SEL s = NSSelectorFromString(@"setChamoisHideDock:");
    if (![dom respondsToSelector:s]) { DMLog(@"[smdock] no -setChamoisHideDock: here"); return; }
    DMLog([NSString stringWithFormat:@"[smdock] setChamoisHideDock:%d through SpringBoard's defaults", hide]);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(dom, s, hide);
    DMSMDockDebug();
}
// ---- debug (1.8.3 item 7): a side Dock icon left unturned (a Handoff tile at Right on Aerial, regression-1.8.2.2-m1.md F1) ----
// turnwatch: CALayer's -setSublayerTransform: watched for the Dock window's icon views; each write that is not the turn's own (DM_TURN_OURS) is
// logged with its value and the calls that made it. turnwatch0: off. Hooked only on the first "turnwatch": nothing of this in a release build.
static void (*o_DMTurnWatchSet)(CALayer *, SEL, CATransform3D);
static BOOL gDMTurnWatchOn = NO;
static void DMTurnWatchSet(CALayer *self, SEL _cmd, CATransform3D t) {
    o_DMTurnWatchSet(self, _cmd, t);
    if (!gDMTurnWatchOn || gDMTurnOurs) return;
    id d = self.delegate;
    Class ic = objc_getClass("SBIconView");
    if (!ic || ![d isKindOfClass:ic]) return;
    UIView *v = d;
    if (!v.window || ![NSStringFromClass([v.window class]) containsString:@"FloatingDock"]) return;
    NSArray<NSString *> *calls = [NSThread callStackSymbols];
    NSMutableString *by = [NSMutableString string];
    for (NSUInteger i = 1; i < calls.count && i < 12; i++) [by appendFormat:@"\n    %@", calls[i]];
    id icon = nil; @try { icon = [v valueForKey:@"icon"]; } @catch (id e) {}
    id ident = nil; @try { ident = [icon valueForKey:@"applicationBundleID"] ?: [icon valueForKey:@"leafIdentifier"]; } @catch (id e) {}
    DMLog([NSString stringWithFormat:@"[turnwatch] %@ (%@, %@) sublayerTransform set to {%.2f %.2f %.2f %.2f}, in the platter %d, in the host %d, by:%@", NSStringFromClass([v class]),
           NSStringFromClass([icon class]), ident ?: @"?", t.m11, t.m12, t.m21, t.m22, DMIsDockIcon(v), DMDockSideInHost(v), by]);
}
void DMDockTurnWatch(BOOL on) {
    if (on && !o_DMTurnWatchSet) MSHookMessageEx([CALayer class], @selector(setSublayerTransform:), (IMP)DMTurnWatchSet, (IMP *)&o_DMTurnWatchSet);
    gDMTurnWatchOn = on;
    DMLog([NSString stringWithFormat:@"[turnwatch] %@", on ? @"on: writes of a Dock icon's turn that are not ours are logged" : @"off"]);
}
// turns: each SBIconView (and our own icons) in the Dock window: its class, its icon's, the views up to the Dock's, whether it counts as a side Dock
// icon, the side its turn is for, and its sublayerTransform.
void DMDockTurnsDump(void) {
    UIWindow *w = gDockWindow;
    if (!w) { DMLog(@"[turns] no Dock window"); return; }
    Class ic = objc_getClass("SBIconView");
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w], *icons = [NSMutableArray array];
    while (todo.count) { UIView *v = todo.lastObject; [todo removeLastObject]; if ((ic && [v isKindOfClass:ic]) || DMDockSideIsOwnIcon(v)) [icons addObject:v]; else [todo addObjectsFromArray:v.subviews]; }
    NSMutableString *o = [NSMutableString stringWithFormat:@"[turns] side %d, host %@: %lu icon views", gDockSideApplied, gDockSideHost ? NSStringFromClass([gDockSideHost class]) : @"none", (unsigned long)icons.count];
    for (UIView *v in icons) {
        id icon = nil; @try { icon = [v valueForKey:@"icon"]; } @catch (id e) {}
        id ident = nil; @try { ident = [icon valueForKey:@"applicationBundleID"] ?: [icon valueForKey:@"leafIdentifier"]; } @catch (id e) {}
        NSMutableString *up = [NSMutableString string];
        for (UIView *s = v.superview; s && s != gDockSideHost; s = s.superview) [up appendFormat:@" < %@", NSStringFromClass([s class])];
        CATransform3D t = v.layer.sublayerTransform;
        [o appendFormat:@"\n  %@ (%@ %@) hidden %d alpha %.2f: platter %d, host %d, turn side %d, sublayer {%.2f %.2f %.2f %.2f}%@", NSStringFromClass([v class]), NSStringFromClass([icon class]), ident ?: @"-",
         v.hidden, v.alpha, DMIsDockIcon(v), DMDockSideInHost(v), MSBDDockSideIconTurnSide(v), t.m11, t.m12, t.m21, t.m22, up];
    }
    DMLog(o);
}
// editprobe: each SBIconView (and our own icons) in the Dock window: its class, its icon's, editing, the jitter animations on its layer and its image
// view's, its location, delegate, list layout provider, close box, superview -- what Edit Home Screen does to the Dock's icons (1.8.3 item 5).
void DMDockEditProbe(void) {
    UIWindow *w = gDockWindow;
    if (!w) { DMLog(@"[editprobe] no Dock window"); return; }
    Class ic = objc_getClass("SBIconView");
    id mgr = DMObj(DMObj((id)objc_getClass("SBIconController"), @"sharedInstance"), @"iconManager");
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObject:w], *icons = [NSMutableArray array];
    while (todo.count) { UIView *v = todo.lastObject; [todo removeLastObject]; if ((ic && [v isKindOfClass:ic]) || DMDockSideIsOwnIcon(v)) [icons addObject:v]; [todo addObjectsFromArray:v.subviews]; }
    BOOL editing = [mgr respondsToSelector:@selector(isEditing)] && ((BOOL (*)(id, SEL))objc_msgSend)(mgr, @selector(isEditing));
    NSMutableString *o = [NSMutableString stringWithFormat:@"[editprobe] icon manager %@ editing %d: %lu icon views", NSStringFromClass([mgr class]), editing, (unsigned long)icons.count];
    for (UIView *v in icons) {
        id icon = nil, loc = nil, del = nil, prov = nil; BOOL ed = NO, allows = NO, box = NO;
        @try { icon = [v valueForKey:@"icon"]; } @catch (id e) {}
        @try { loc = [v valueForKey:@"location"]; } @catch (id e) {}
        @try { del = [v valueForKey:@"delegate"]; } @catch (id e) {}
        @try { prov = [v valueForKey:@"listLayoutProvider"]; } @catch (id e) {}
        if ([v respondsToSelector:@selector(isEditing)]) ed = ((BOOL (*)(id, SEL))objc_msgSend)(v, @selector(isEditing));
        SEL ae = NSSelectorFromString(@"allowsEditingAnimation"), cb = NSSelectorFromString(@"allowsCloseBox");
        if ([v respondsToSelector:ae]) allows = ((BOOL (*)(id, SEL))objc_msgSend)(v, ae);
        if ([v respondsToSelector:cb]) box = ((BOOL (*)(id, SEL))objc_msgSend)(v, cb);
        UIView *img = nil; SEL iv = NSSelectorFromString(@"_iconImageView"); if ([v respondsToSelector:iv]) img = ((id (*)(id, SEL))objc_msgSend)(v, iv);
        if (!img) { @try { id i2 = [v valueForKey:@"image"]; if ([i2 isKindOfClass:[UIView class]]) img = i2; } @catch (id e) {} }   // (our own views' picture)
        CGRect onScreen = [v convertRect:v.bounds toView:nil], imgOnScreen = img ? [img convertRect:img.bounds toView:nil] : CGRectNull;
        [o appendFormat:@"\n  %@ (%@) editing %d allowsEditingAnimation %d closeBox %d loc %@ delegate %@ provider %@ super %@; anims %@ / image %@; at %@, picture at %@%@",
         NSStringFromClass([v class]), NSStringFromClass([icon class]), ed, allows, box, loc, NSStringFromClass([del class]), NSStringFromClass([prov class]), NSStringFromClass([v.superview class]),
         [v.layer.animationKeys componentsJoinedByString:@","] ?: @"-", [img.layer.animationKeys componentsJoinedByString:@","] ?: @"-",
         NSStringFromCGRect(CGRectIntegral(onScreen)), NSStringFromCGRect(CGRectIntegral(imgOnScreen)), v.hidden ? @" HIDDEN" : @""];
    }
    DMLog(o);
}
#endif

