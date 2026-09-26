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
static BOOL    gShowDownloads = YES;    // the Downloads stack in the Dock
static BOOL    gEscapeClosesLibrary = YES;   // pressing Escape closes the App Library
static BOOL    gLaunchpadIcon = YES;    // the App Library icon drawn like macOS Launchpad
static BOOL    gLaunchpadClassic = YES; // round rocket (YES) or the silver grid tile (NO)
static BOOL    gBlockSwipeUp  = YES;    // stop an upward swipe on the Home Screen from opening the App Library
static BOOL    gPortraitLarger = YES;   // in portrait the (shrunk) Dock grows to the widest size that fits the screen
static BOOL    gSwipeDownOpensLibrary = YES;   // a downward swipe on the Home Screen opens the App Library (our own replacement for Lynx's "replace Spotlight")

// ===== logging (no system log on this setup) ==============================
#import "DMLog.h"
#if DEBUG
void DMLogWrite(NSString *line) {
    FILE *f = fopen("/tmp/dockmag.log", "a");
    if (!f) return;
    fprintf(f, "%s\n", [line UTF8String]);
    fclose(f);
}
#endif

static CGFloat gInfluence = 0.0;     // 0...1: how much of the magnification is applied right now

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
    BOOL launchpad = YES;
    CFPropertyListRef lp = DMCopyPref(CFSTR("launchpadIcon"));
    if (lp) {
        if (CFGetTypeID(lp) == CFBooleanGetTypeID()) launchpad = CFBooleanGetValue(lp);
        CFRelease(lp);
    }
    gLaunchpadIcon = launchpad;
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
@end

// The Dock's size and distance from the screen edge come from SBFloatingDockView's own layout numbers, so changing those
// (rather than scaling icon views) keeps the platter, spacing and hit areas consistent, and the hover magnification is
// unaffected (it only adds transforms on top).
static CGRect gDownloadsSlot = {{0, 0}, {0, 0}};   // where the Downloads icon goes, in the platter's coordinates (set by getMetrics)
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
%hook SBFloatingDockView
- (void)layoutSubviews {
    %orig;
    UIView *platter = nil; @try { platter = [self valueForKey:@"mainPlatterView"]; } @catch (id e) {}   // (KVC on a private class, every layout: guarded)
    if (![platter isKindOfClass:[UIView class]]) platter = nil;
    if (platter) DMDownloadsAttach(platter, gDownloadsSlot, gShowDownloads);
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
    if (!m || bounds.size.width < 100.0 || m->platter.size.width < 1.0) return;
    // Downloads stack: one more icon slot right before the App Library icon. The slot is the App Library icon's old spot; the
    // App Library icon and the end of the platter move over by one icon + spacing.
    CGRect slot = m->libraryIcon;
    // The second divider (see gDivider2Rect): with Downloads. After the recents (the recents list at least half an icon wide) it is a second line;
    // with no recents the Dock hides its own line and ours is the only one, between the apps and Downloads (as on macOS). Its gap is one spacing
    // + the 1 pt line; the line's own width is not scaled below, which is corrected after scaling.
    CGRect nativeDivider = m->divider;
    CGFloat unscaledSpacing = m->spacing;
    BOOL hasRecents = m->recentsList.size.width >= slot.size.width * 0.5;
    BOOL divider2 = gShowDownloads && nativeDivider.size.width > 0.0 && nativeDivider.size.height > 1.0;
#if DEBUG
    {   // (debug: the Dock's own numbers, whenever they change)
        static NSString *lastMetrics = nil;
        NSString *mt = [NSString stringWithFormat:@"user %@ recents %@ divider %@ library %@ spacing %.2f", NSStringFromCGRect(m->userList), NSStringFromCGRect(m->recentsList), NSStringFromCGRect(nativeDivider), NSStringFromCGRect(slot), m->spacing];
        if (![mt isEqualToString:lastMetrics]) { lastMetrics = mt; DMLog([@"[metrics] " stringByAppendingString:mt]); }
    }
#endif
    // iPadOS 17+ (untested versions, a tester on 18.7.2): the App Library icon's spot is 0 wide while that icon is not in the Dock, so there is no
    // slot for Downloads -- its icon stays hidden, and widening the Dock left an empty tail on the right. No slot, no widening there (15/16: as before).
    BOOL noSlotOnNewOS = [NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 17 && slot.size.width < 1.0;
    if (gShowDownloads && !noSlotOnNewOS) {
        CGFloat extra = slot.size.width + m->spacing + (divider2 ? unscaledSpacing + nativeDivider.size.width : 0.0);
        m->libraryIcon.origin.x += extra;
        m->platter.size.width += extra;
        m->platter.origin.x -= extra / 2.0;
    }
    CGFloat f = gIconSize;
    // Auto-fit, like macOS (2026-09-25): the Icon Size is the largest the Dock gets; when the whole Dock (apps, divider, recents, Downloads, App
    // Library) would not fit the screen minus the side margins, it gets just small enough to fit -- in both orientations, re-worked out at every
    // layout (apps or recents added or removed, a turn). Room is kept at both ends for the magnification: the end icons grow in place by
    // (magnification - 1) x their width, half on each side, and must stay on the screen.
    CGFloat headroom = gEnabled ? MAX(0.0, gMagnification - 1.0) * slot.size.width : 0.0;
    CGFloat room = (bounds.size.width - 50.0) / (m->platter.size.width + headroom);
    // Portrait: the screen is narrower, so a Dock this tweak has shrunk looks small. It grows to the widest size that still fits (at most
    // 1.2 times the stock size). Only while the tweak is shrinking the Dock at all; a size of 1.0 or more is left alone.
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (gPortraitLarger && f < 1.0 && screen.width < screen.height) f = MIN(room, 1.2);
    if (f > room) f = room;
    static CGFloat lastF = -1; static CGFloat lastW = -1;
    if (fabs(f - lastF) > 0.001 || fabs(bounds.size.width - lastW) > 0.5) {
        lastF = f; lastW = bounds.size.width;
        DMLog([NSString stringWithFormat:@"[fit] screen %.0f, dock %.0f + %.0f magnification room at size 1: icon size %.3f (setting %.2f, fits up to %.3f)", bounds.size.width, m->platter.size.width, headroom, f, gIconSize, room]);
    }
    if (!gShowDownloads && fabs(f - 1.0) < 0.001) { gDownloadsSlot = CGRectZero; gDivider2Rect = CGRectZero; return; }
    CGRect (^scaled)(CGRect) = ^CGRect(CGRect r) { return CGRectMake(r.origin.x * f, r.origin.y * f, r.size.width * f, r.size.height * f); };
    gDownloadsSlot = gShowDownloads ? scaled(slot) : CGRectZero;
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
        m->libraryIcon.origin.x += pull / f;   // (in unscaled units: scaled below)
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
}
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
%hook SBSearchScrollView
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
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
