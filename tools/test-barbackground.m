// test-barbackground.m -- see test-barbackground.sh. Mac Catalyst: the bar's real code (cut out of statusbar/StatusBar.x into bb-*.inc) on a
// stand-in status bar whose style attributes are UIKit's own (+[_UIStatusBarStyleAttributes styleAttributesForStatusBar:style:], which reads the
// bar's -foregroundColor) and whose time label is UIKit's own _UIStatusBarStringView, with StatusBar.x's -setTextColor: hook body on it.
// One scenario per process: `t list`, `t <scenario>`. Each check prints PASS / FAIL.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "BarBackground.h"

static int gFails = 0;
static void check(BOOL ok, NSString *what) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); if (!ok) gFails++; }

// ---- stand-ins for what the cut code uses from elsewhere in StatusBar.x ----
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { [gLog addObject:s]; }
static BOOL gTColorBar = NO, gTNoFg = NO;
static BOOL DMColorBarActive(void) { return gTColorBar; }
static UIView *TRegion(UIView *fg) { for (UIView *v in fg.subviews) if (v.subviews.count) return v; return nil; }   // (iPadOS's region with the time: not our background or logo)
static UIView *DMTrailingContainer(UIView *fg) { return TRegion(fg); }
static UIColor *DMTrailingIconColor(UIView *trailing);   // (StatusBar.x, cut below: bb-trailing.inc)
static UIView *DMLeadingContainer(UIView *fg) { return TRegion(fg); }
static UIView *DMFirstStringView(UIView *container) { return container.subviews.firstObject; }
static UIColor *gStatusTextColor = nil;
static const void *kBackgroundKey = &kBackgroundKey;
static int gAMLabelKeys[7], gAMButtonKeys[7], gAMPillKeys[7];
#define DM_AM_LABELS (const void *)&gAMLabelKeys[0], (const void *)&gAMLabelKeys[1], (const void *)&gAMLabelKeys[2], (const void *)&gAMLabelKeys[3], (const void *)&gAMLabelKeys[4], (const void *)&gAMLabelKeys[5], (const void *)&gAMLabelKeys[6]
#define DM_AM_BUTTONS (const void *)&gAMButtonKeys[0], (const void *)&gAMButtonKeys[1], (const void *)&gAMButtonKeys[2], (const void *)&gAMButtonKeys[3], (const void *)&gAMButtonKeys[4], (const void *)&gAMButtonKeys[5], (const void *)&gAMButtonKeys[6]
#define DM_AM_PILLS (const void *)&gAMPillKeys[0], (const void *)&gAMPillKeys[1], (const void *)&gAMPillKeys[2], (const void *)&gAMPillKeys[3], (const void *)&gAMPillKeys[4], (const void *)&gAMPillKeys[5], (const void *)&gAMPillKeys[6]
static void DMSBDiagStep(NSString *step) {}
static void DMLAHidePills(UIView *fg) {}
// What is behind the bar: DesktopWallpaper.h's DMWPBarBackdrop (cut out, bb-wp*.inc) on its state as its tick leaves it -- our picture view in the
// Home Screen variant's view, in the wallpaper's window, its picture decoded and its top strip read -- and what covers the desktop
#include "bb-wptop.inc"       // (DesktopWallpaper.h: MSBDWPTop)
@interface DMWPPlane : UIImageView
@property (nonatomic) BOOL topRead;
@property (nonatomic) MSBDWPTop top;
@end
@implementation DMWPPlane
@end
static DMWPPlane *gWPPlane, *gWPTVPlane;
static __weak UIView *gWPHost, *gWPTVHost;
static BOOL gTFullScreen, gTSMEngine, gTSMFull, gTCC, gTCover, gTSwitcher;
static BOOL DMSMEngine(void) { return gTSMEngine; }
static BOOL DMSMFrontIsFullScreen(void) { return gTSMFull; }
static BOOL DMFullScreenAppInFront(void) { return gTFullScreen; }
static BOOL DMControlCenterActive(void) { return gTCC; }
static BOOL DMCoverSheetShown(void) { return gTCover; }
static BOOL DMSwitcherVisible(void) { return gTSwitcher; }
// Our own Control Center (Control Center Style Mac): the state its rule reads, as the panel leaves it -- 15-17 (CCPanel.h): in force, its host in
// Apple's overlay, the module opened expanded; 18 (CC18Shape.h): in force, editing, its material in the overlay, a module opened expanded
static BOOL gCCPOn, gCC18On, gCC18Editing, gCC18Expanded;
static UIView *gCCPHost, *gCC18Material, *gTCCOverlay;
static NSString *gCCPExpanded;
#include "bb-ccp.inc"         // (CCPanel.h DMCCPanelOwnsCCBars, DMCCPanelLeavesDesktop; CC18Shape.h DMCC18OwnsCCBars, DMCC18LeavesDesktop)
#include "bb-wp.inc"          // (DesktopWallpaper.h DMWPBarBackdrop)
static void TOurPanel15(BOOL on) {   // (15-17: the panel in force, its host in Apple's overlay view -- or nothing of it)
    gCCPOn = on; gTCCOverlay = on ? [UIView new] : nil;
    gCCPHost = on ? [UIView new] : nil; if (on) [gTCCOverlay addSubview:gCCPHost];
}
static void TOurPanel18(BOOL on) {   // (18: the Mac shape in force, our material in Apple's overlay view)
    gCC18On = on; gTCCOverlay = on ? [UIView new] : nil;
    gCC18Material = on ? [UIView new] : nil; if (on) [gTCCOverlay addSubview:gCC18Material];
}
static NSHashTable *gAllBarCopies;   // (StatusBar.x: every status bar copy that has been in a window)
static UIColor *DMBarWindowTextOn(UIScreen *scr, UIView **stripOut);   // (StatusBar.x, cut below: the full-screen window's text behind the screen's own bar)
#include "bb-wptick.inc"      // (DesktopWallpaper.h DMWPBarBackdropTick)
static UIWindow *gTWallWindow; static UIView *gTHost;
static void TOurPicture(MSBDWPTop top) {   // (a Desktop Picture set, decoded, on page 1 of the Home Screen)
    if (!gTWallWindow) { gTWallWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]; gTWallWindow.hidden = NO; }
    [gWPPlane removeFromSuperview];
    gTHost = [[UIView alloc] initWithFrame:gTWallWindow.bounds]; [gTWallWindow addSubview:gTHost]; gWPHost = gTHost;
    gWPPlane = [[DMWPPlane alloc] initWithFrame:gTHost.bounds]; [gTHost addSubview:gWPPlane];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)];
    gWPPlane.image = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [[UIColor whiteColor] setFill]; UIRectFill(CGRectMake(0, 0, 4, 4)); }];
    gWPPlane.top = top; gWPPlane.topRead = YES; gWPPlane.alpha = 1.0;
}
static void TSky(void) { TOurPicture((MSBDWPTop){ { 0.55, 0.70, 0.86 }, { 0.80, 0.88, 0.96 } }); }   // (a light sky, as KT's High Sierra)
static void TDarkPicture(void) { TOurPicture((MSBDWPTop){ { 0.02, 0.02, 0.04 }, { 0.20, 0.22, 0.28 } }); }
static BOOL DMBarDarkTextOn(UIView *fg);
#include "bb-keys.inc"        // (the item keys the cut code names)
static Class DMSBClass(const char *name);
static UIColor *DMBarForegroundFor(UIView *bar, UIColor *asked);
#include "bb-globals.inc"     // (StatusBar.x: the background's preferences, DMParseHexColor)
#include "bb-compat.inc"      // (the code before the fix: what it does not have)
// The Stage Manager engine's top bar (StatusBar.x, cut out as it is: bb-sm.inc), on iPadOS 17's bar classes or 15/16's, and the switcher
static BOOL gTSTUI = YES, gTScreenSwitcher = NO, gMSWOpen = NO;   // (gMSWOpen: MacSwitcher.h, our Mac Switcher showing)
static BOOL DMSBUseSTUI(void) { return gTSTUI; }
// (each display's own switcher: gTScreenSwitcher, whichever screen asks -- one screen; gTSwitcherOn, that screen's alone -- the TV's scenario;
//  gTSwitcher above is iPadOS's isAnySwitcherVisible, DMSwitcherVisible: up on any display)
static UIScreen *gTSwitcherOn, *gTMSWScreen;
static BOOL gTGoesHome = NO;
static BOOL DMSMScreenInSwitcher(UIScreen *screen) { return gTScreenSwitcher || (gTSwitcherOn && screen == gTSwitcherOn); }
static BOOL DMSMCardGoesHome(UIView *card) { return gTGoesHome; }   // (its display's switcher going Home, or there: common/SMBarHome.h)
static UIScreen *DMMSWScreen(void) { return gTMSWScreen ?: [UIScreen mainScreen]; }   // (MacSwitcher.h: the display our Mac Switcher works on)
static BOOL gDMHoldOwnAlpha = NO;
#include "bb-sm.inc"          // (DMSMCardIsFullSize, DMSMInFullScreenCard, DMSMMainBarOn, DMSMMainBarShown, DMSMStripIsMenuBar, DMSMStripHidden, DMSMCardOfView)

// The stand-in status bar (iPadOS's: UIKit's _UIStatusBar on 15/16, STUIStatusBar on 17/18 -- not in Mac Catalyst, so the class is made here).
// Its -setForegroundColor: is StatusBar.x's hook (the site check: the hook's body is exactly this call); the bar's own setter restyles when the
// colour changes, as iPadOS's does; a restyle takes UIKit's own style attributes for the bar and gives them to the time label (UIKit's string
// view). iPadOS's own colours with no foreground colour (white for light content, black for dark content) are given by the stand-in: Mac
// Catalyst's UIKit leaves them to the label's traits.
// 1.8.7.6 (the 17.5's crash at a Notification Center pull): the bar's own constraint pass, UIKit's (the ncpull scenarios: the bar asks for
// constraint-based layout, a restyle asks for its constraints again, as SystemStatusUI's does), whose -updateConstraints is StatusBar.x's hook
// body as it is (bb-uc.inc) around the bar's own pass (TBarOwnPass): its region items placed -- the time label back in its region, its colour
// set there (our -setTextColor: hook) or its tint (our -tintColorDidChange hook), and for a copy of ours laid out without a clock, the
// _updateRegionItems hook's DMAttachIfFilled after it (DMClosedUpClockBack). UIKit then raises "The layout constraints still need update after
// sending -updateConstraints" for a write of the bar's colour inside that pass, as on the 17.5.
static BOOL gTConstraintPass = NO, gTRestyleDirties = NO, gTPlaceItems = NO, gTReAdd = NO, gTSetColour = NO, gTTintPath = NO, gTClosedUpPath = NO, gTPassRaises = NO;
static BOOL gTOurLayout = NO, gTTintHook = NO, gTBadUC = NO;
static BOOL gTDropInPass = NO;   // (a copy's layout asked for inside the bar's constraint pass is dropped, as on 18.5: StatusBar.x DMAttachIfFilledNow)
static int gTInPass = 0, gTRestylesInPass = 0, gTLayoutsInPass = 0, gTDarkInPass = -1, gTColourChangedInPass = 0;
static BOOL gTLayoutInPass = NO;   // (the copy laid out inside the bar's own pass, by iPadOS or anyone)
static int gDMBarLayoutDepth = 0, gDMBarUpdateDepth = 0;   // (StatusBar.x: a copy's layout pass running -- the -layoutSubviews hook's, below --; _updateRegionItems)
static __unsafe_unretained UIView *gDMBarLayingOut = nil;
static void TBarUpdateConstraints(UIView *bar);   // (below: StatusBar.x's hook body around the bar's own pass)
@interface _UIStatusBar : UIView
@property (nonatomic) long long style, mode;
@property (nonatomic) int restyles;
@property (nonatomic, strong) id lastAttrs;
@property (nonatomic, weak) UILabel *time;
- (UIColor *)foregroundColor;
- (void)setForegroundColor:(UIColor *)color;
@end
@implementation _UIStatusBar { UIColor *_fg; }
+ (BOOL)requiresConstraintBasedLayout { return gTConstraintPass; }
- (UIColor *)foregroundColor { return _fg; }
- (void)setForegroundColor:(UIColor *)color { [self dm_ownSetForegroundColor:DMBarForegroundFor(self, color)]; }   // (the hook)
- (void)dm_ownSetForegroundColor:(UIColor *)c { if (c == _fg || [c isEqual:_fg]) return; _fg = c; [self restyle]; }
- (void)setStyle:(long long)s { if (s == _style) return; _style = s; [self restyle]; }
- (UIColor *)ivarForeground { return _fg; }
- (void)restyle {
    self.restyles++;
    if (gTInPass) gTRestylesInPass++;
    id a = ((id (*)(id, SEL, id, long long))objc_msgSend)(objc_getClass("_UIStatusBarStyleAttributes"), sel_registerName("styleAttributesForStatusBar:style:"), self, self.style);
    self.lastAttrs = a;
    if ([a valueForKey:@"textColor"]) ((void (*)(id, SEL, id))objc_msgSend)(self.time, sel_registerName("applyStyleAttributes:"), a);
    else self.time.textColor = self.style == 1 ? [UIColor whiteColor] : [UIColor blackColor];
    if (gTRestyleDirties) [self setNeedsUpdateConstraints];   // (its items placed again in its next constraint pass)
}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"
- (void)updateConstraints { TBarUpdateConstraints(self); }   // (StatusBar.x's hook: UIKit's own -updateConstraints is in the bar's own pass, TBarOwnPass)
#pragma clang diagnostic pop
- (void)dm_ownUpdateConstraints { [super updateConstraints]; }
@end
@interface TBarNoFg : UIView   // (a bar without a foreground colour as read: the hook is not installed)
@end
@implementation TBarNoFg
@end
@interface TBarBadUC : UIView   // (a bar whose foreground colour is as read but whose -updateConstraints is not (its type): not installed either)
- (UIColor *)foregroundColor;
- (void)setForegroundColor:(UIColor *)color;
@end
@implementation TBarBadUC
- (UIColor *)foregroundColor { return nil; }
- (void)setForegroundColor:(UIColor *)color {}
@end
static void TBadUC(id self, SEL _cmd, id x) {}
static Class DMSBClass(const char *name) {
    if (!strcmp(name, "_UIStatusBar") && gTNoFg) return [TBarNoFg class];
    if (!strcmp(name, "_UIStatusBar") && gTBadUC) { class_addMethod([TBarBadUC class], @selector(updateConstraints), (IMP)TBadUC, "v24@0:8@16"); return [TBarBadUC class]; }
    return objc_getClass(name);
}
static void TLayoutCopy(UIView *fg);   // (below: -dm_layoutLogoBody as the test plays it)
@interface TFg : UIView
@property (nonatomic) int layoutsAsked, layoutsDone;
@end
@implementation TFg
- (void)setNeedsLayout { self.layoutsAsked++; if (gTInPass && gTDropInPass) return; [super setNeedsLayout]; }
- (void)layoutSubviews {   // (the ncpull scenarios: StatusBar.x's -layoutSubviews hook, our layout after iPadOS's, the copy's pass counted as there)
    [super layoutSubviews];
    self.layoutsDone++;
    if (gTInPass && ++gTLayoutsInPass > 50) [NSException raise:@"TLayoutLoop" format:@"the copy laid out again and again inside the bar's own constraint pass"];
    if (!gTOurLayout) return;
    UIView *prev = gDMBarLayingOut;
    gDMBarLayoutDepth++; gDMBarLayingOut = self;
    @try { TLayoutCopy(self); } @finally { gDMBarLayingOut = prev; gDMBarLayoutDepth--; }
}
@end

__attribute__((unused)) static BOOL DMBarItemsAskBeforeOurs(UIView *fg) { (void)fg; return NO; }   // (StatusBar.x 1.8.7.8: a held copy's items asked before the layout that makes it ours -- the copies here are ours: it asks nothing)
#include "bb-real.inc"        // (StatusBar.x: DMBackgroundWanted, DMApplyBackground, DMLabelDrawnColor, DMBarItemColor, the dark text, DMApplyBarItemColor)
#include "bb-trailing.inc"    // (StatusBar.x: DMTrailingIconColor)
static void TNarrowLayout(UIView *fg) {   // (StatusBar.x -dm_layoutLogoBody: its branch for a copy under 300 pt, as it is)
#include "bb-narrow.inc"
}
static void TDress(UIView *fg);
static void TLayoutCopy(UIView *fg) {   // (StatusBar.x -dm_layoutLogoBody as it is: a window card's strip that is not the top bar, a copy under 300 pt; then its end)
#include "bb-smstrip.inc"
#include "bb-narrow.inc"
    TDress(fg);
    UIView *container = DMLeadingContainer(fg), *time = container ? DMFirstStringView(container) : nil;
    if (time) objc_setAssociatedObject(fg, kBarClosedUpKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (the layout with a clock ends the closed-up look)
    DMApplyBarItemColor(fg, DMBarItemColor(fg, time), YES);
}
static void TApplyPrefs(void) {
#include "bb-prefs.inc"       // (StatusBar.x DMLoadPrefs: the text on a bar of this colour)
}
static void TInstall(void) {
#include "bb-init.inc"        // (StatusBar.x DMBarForegroundInit, its %init taken out)
}
// StatusBar.x's -[_UIStatusBarStringView setTextColor:] hook, on UIKit's own string view (a subclass made at run time)
static void TSuperSetTextColor(UILabel *l, UIColor *c) {
    struct objc_super s = { l, objc_getClass("_UIStatusBarStringView") };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&s, @selector(setTextColor:), c);
}
static void TStringViewSetTextColor(UILabel *self, UIColor *color) {
#include "bb-hook.inc"
}
static void TTimeSetTextColor(id me, SEL _cmd, UIColor *c) { TStringViewSetTextColor(me, c); }
// ... and its -tintColorDidChange hook (the ncpull scenarios; elsewhere the string view's own, as before)
static void TSuperTintColorDidChange(UILabel *l) {
    struct objc_super s = { l, objc_getClass("_UIStatusBarStringView") };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&s, @selector(tintColorDidChange));
}
static void TStringViewTintColorDidChange(UILabel *self) {
#include "bb-tint.inc"
}
static void TTimeTint(id me, SEL _cmd) { if (gTTintHook) TStringViewTintColorDidChange(me); else TSuperTintColorDidChange(me); }
static Class TTimeClass(void) {
    static Class c;
    if (!c) {
        c = objc_allocateClassPair(objc_getClass("_UIStatusBarStringView"), "TTimeLabel", 0);
        class_addMethod(c, @selector(setTextColor:), (IMP)TTimeSetTextColor, "v24@0:8@16");
        class_addMethod(c, @selector(tintColorDidChange), (IMP)TTimeTint, "v16@0:8");
        objc_registerClassPair(c);
    }
    return c;
}
// The closed-up copy's way back (StatusBar.x DMClosedUpClockBack, DMClockBackLayout: cut out as they are, bb-closedup.inc), with what they read
static BOOL gTLocked = NO;
static BOOL DMBarLockedNow(void) { return gTLocked; }
static BOOL DMTestFlag(const char *path) { return NO; }
static int gTAgainBeforeDraw = 0;
static __weak UIView *gTRegionBack;   // (the time label's region, while the Cover Sheet has taken the label out of it)
static void DMBarLayoutAgainBeforeDraw(UIView *fg) { gTAgainBeforeDraw++; }   // (Core Animation's pre-commit layout of the copy: counted here)
#include "BarUnlock.h"
static void DMClockBackLayout(UIView *fg);
#include "bb-closedup.inc"
static void TBarOwnPass(_UIStatusBar *bar) {   // (the bar's own -updateConstraints: UIKit's, then its region items placed)
    [bar dm_ownUpdateConstraints];
    if (gTPassRaises) { gTPassRaises = NO; [NSException raise:@"TPassRaises" format:@"a constraint pass that raises (not ours)"]; }
    if (!gTPlaceItems) return;
    gTInPass++;
    UIColor *was = [bar ivarForeground];
    UILabel *time = bar.time;
    UIView *fg = bar.subviews.lastObject;
    for (UIView *v in bar.subviews) if ([v isKindOfClass:[TFg class]]) fg = v;
    UIView *region = gTRegionBack ?: time.superview;
    if (gTReAdd && region) { [time removeFromSuperview]; [region insertSubview:time atIndex:0]; }   // (the time label into its region again)
    if (gTSetColour) {   // (its colour from the bar's style attributes, as iPadOS's item sets it: our -setTextColor: hook)
        id a = bar.lastAttrs;
        if ([a valueForKey:@"textColor"]) ((void (*)(id, SEL, id))objc_msgSend)(time, sel_registerName("applyStyleAttributes:"), a);
        else time.textColor = time.textColor;
    }
    if (gTTintPath) [time tintColorDidChange];   // (its tint: our -tintColorDidChange hook)
    if (gTLayoutInPass) { [fg setNeedsLayout]; [fg layoutIfNeeded]; }   // (the copy laid out right here: our layout decides inside the pass)
    if (gTClosedUpPath && objc_getAssociatedObject(fg, kLogoKey)) DMClosedUpClockBack(fg);   // (_updateRegionItems' hook after it: DMAttachIfFilled for ours)
    gTDarkInPass = DMBarDarkTextOn(fg);
    UIColor *now = [bar ivarForeground];
    if (!(was == now || [was isEqual:now])) gTColourChangedInPass++;
    gTInPass--;
}
static void TBarUpdateConstraints(UIView *view) {   // (StatusBar.x's -updateConstraints hook, as it is: bb-uc.inc, %orig the bar's own pass --
    _UIStatusBar *self = (_UIStatusBar *)view;      //  installed with the foreground colour's, BarForeground: not when that one is not)
    if (!gBarFgHooked) { TBarOwnPass(self); return; }
#include "bb-uc.inc"
}

// ---- the world: a bar of ours (logo, time label), the preferences ----
typedef struct { _UIStatusBar *bar; TFg *fg; UILabel *time, *logo; } TWorld;
static TWorld TMake(long long style, UIColor *theirs) {
    TWorld w;
    w.bar = [[_UIStatusBar alloc] initWithFrame:CGRectMake(0, 0, 1024, 24)];
    w.fg = [[TFg alloc] initWithFrame:w.bar.bounds];
    [w.bar addSubview:w.fg];
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(900, 0, 120, 24)];
    [w.fg addSubview:container];
    w.time = [[TTimeClass() alloc] initWithFrame:CGRectMake(0, 0, 60, 24)];
    [container addSubview:w.time];
    w.bar.time = w.time;
    w.bar.style = style;                              // (iPadOS's style, then its own foreground colour if it asked for one: before ours)
    if (theirs) [w.bar setForegroundColor:theirs];
    w.logo = [UILabel new];                           // (a bar of ours: its logo, the mark its restyle hook looks for)
    [w.fg addSubview:w.logo];
    objc_setAssociatedObject(w.fg, kLogoKey, w.logo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return w;
}
static void TPrefs(NSString *mode, NSString *hex, double opacity) {
    gBgMode = [mode isEqual:@"on"] ? DMBackgroundOn : [mode isEqual:@"off"] ? DMBackgroundOff : DMBackgroundAuto;
    gBgColor = DMParseHexColor(hex);
    gBgOpacity = opacity;
    TApplyPrefs();
}
static void TLayout(TWorld w) {   // (the end of the bar's layout, -dm_layoutLogoBody: its colour from the time label, on every item)
    UIColor *barColor = DMBarItemColor(w.fg, w.time);
    DMApplyBarItemColor(w.fg, barColor, YES);
}
static void TSettle(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]]; }
static BOOL TSame(UIColor *a, UIColor *b) {
    CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
    if (!a || !b) return a == b;
    if (![a getRed:&r1 green:&g1 blue:&b1 alpha:&a1] || ![b getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) < 0.002 && fabs(g1 - g2) < 0.002 && fabs(b1 - b2) < 0.002 && fabs(a1 - a2) < 0.002;
}
static NSString *TName(UIColor *c) {
    CGFloat r, g, b, a;
    if (!c) return @"none";
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return c.description;
    return [NSString stringWithFormat:@"%.2f %.2f %.2f a %.2f", r, g, b, a];
}
static UIView *TBackground(TWorld w) { return objc_getAssociatedObject(w.fg, kBackgroundKey); }
// The colours given to one background view (watched while gTBgWatched is set): -[UIView setBackgroundColor:] seen for it
static __weak UIView *gTBgWatched; static NSMutableArray<UIColor *> *gTBgSeen;
static void (*gTOrigSetBg)(id, SEL, UIColor *);
static void TSetBg(UIView *self, SEL _cmd, UIColor *c) { if (self == gTBgWatched && c) [gTBgSeen addObject:c]; gTOrigSetBg(self, _cmd, c); }
__attribute__((constructor)) static void TWatchBgInit(void) {
    Method m = class_getInstanceMethod([UIView class], @selector(setBackgroundColor:));
    gTOrigSetBg = (void (*)(id, SEL, UIColor *))method_getImplementation(m);
    method_setImplementation(m, (IMP)TSetBg);
}
static UIColor *TBlack(void) { return [UIColor colorWithRed:0 green:0 blue:0 alpha:1]; }
static UIColor *TWhite(void) { return [UIColor colorWithRed:1 green:1 blue:1 alpha:1]; }
static BOOL TLogHas(NSString *part) { for (NSString *l in gLog) if ([l containsString:part]) return YES; return NO; }
static void TText(TWorld w, UIColor *want, NSString *where) {
    check(TSame(w.time.textColor, want), [NSString stringWithFormat:@"%@: the time (iPadOS's item) is drawn in %@ (is %@)", where, TName(want), TName(w.time.textColor)]);
    check(TSame(w.logo.textColor, want), [NSString stringWithFormat:@"%@: our items (the logo) are drawn in %@ (is %@)", where, TName(want), TName(w.logo.textColor)]);
}
static void TBack(TWorld w, UIColor *want, NSString *where) {
    UIView *bg = TBackground(w);
    if (!want) { check(!bg || bg.hidden, [NSString stringWithFormat:@"%@: no background of ours", where]); return; }
    check(bg && !bg.hidden && TSame(bg.backgroundColor, want), [NSString stringWithFormat:@"%@: the background is %@ (is %@)", where, TName(want), bg && !bg.hidden ? TName(bg.backgroundColor) : @"none"]);
}

// ---- scenarios ----
static void SKT(void) {   // KT's 17.5 prefs: Automatic, #FFFFFF, 0.36; iPadOS's light text (its dark wallpaper behind our light desktop picture)
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    check(TSame(w.time.textColor, TWhite()), @"before our layout: iPadOS's light text (white)");
    TLayout(w);
    TText(w, TBlack(), @"after the layout");
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.36], @"after the layout");
    check(TSame([w.bar ivarForeground], TBlack()), [NSString stringWithFormat:@"the bar's own foreground colour is black (is %@)", TName([w.bar ivarForeground])]);
    id a = w.bar.lastAttrs;
    check(TSame([a valueForKey:@"textColor"], TBlack()) && TSame([a valueForKey:@"imageTintColor"], TBlack()),
          [NSString stringWithFormat:@"UIKit's own style attributes for the bar: text %@, icons %@ (black, black)", TName([a valueForKey:@"textColor"]), TName([a valueForKey:@"imageTintColor"])]);
    check(w.fg.layoutsAsked >= 1, [NSString stringWithFormat:@"the bar is laid out again after the change (the battery's number takes the new colour): %d asked", w.fg.layoutsAsked]);
    TSettle();
    check(w.fg.layoutsAsked >= 2, @"... and once more after the bar's own restyle");
    check(TLogHas(@"text and icons black on our light background") && TLogHas(@"the time is drawn in 0.00 0.00 0.00 a 1.00"), @"the log says so, and how the time is drawn after it");
    int restyles = w.bar.restyles;
    TLayout(w); TLayout(w);
    check(w.bar.restyles == restyles, @"further layouts write nothing (no restyle)");
}
static void SKTDark(void) {   // the same prefs where iPadOS's text is dark (a light app): the chosen colour stays, the text black
    TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();   // (no picture of ours behind: iPadOS's text is for the app, and black already)
    TWorld w = TMake(3, nil);
    TLayout(w);
    TText(w, TBlack(), @"dark content");
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.36], @"dark content: the chosen colour, not the light grey");
}
static void SFlip(void) {   // iPadOS restyles the bar while ours is in force: a style request (its foreground colour none), light and dark content
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    [w.bar setForegroundColor:nil]; w.bar.style = 3; w.bar.style = 1;
    TText(w, TBlack(), @"after iPadOS's requests (none, dark content, light content)");
    check(TSame([w.bar ivarForeground], TBlack()), @"the bar's foreground colour stays ours");
    TLayout(w);
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.36], @"after iPadOS's requests");
}
static void SDefault(void) {   // the default dark colour: as before (the colour under light text, the light grey under dark text, iPadOS's text)
    TPrefs(@"auto", @"#242225", 0.70); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"default colour, light content");
    TBack(w, [DMParseHexColor(@"#242225") colorWithAlphaComponent:0.70], @"default colour, light content");
    w.bar.style = 3;
    TText(w, TBlack(), @"default colour, dark content");
    TBack(w, [UIColor colorWithWhite:0.96 alpha:0.70], @"default colour, dark content (the light grey)");
    check([w.bar ivarForeground] == nil, @"the bar's foreground colour is never written");
}
static void SFaint(void) {   // a light colour too faint to make the bar light (white at 0.2 over a dark backdrop is a dark grey): iPadOS's text
    TPrefs(@"on", @"#FFFFFF", 0.20); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"white at 0.2, light content");
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.20], @"white at 0.2, light content");
    w.bar.style = 3;
    TText(w, TBlack(), @"white at 0.2, dark content");
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.20], @"white at 0.2, dark content: the chosen colour");
    check([w.bar ivarForeground] == nil, @"the bar's foreground colour is never written");
}
static void SOff(void) {   // Background Off: nothing of ours; switched off while ours was in force: iPadOS's text again
    TPrefs(@"off", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"Background Off");
    TBack(w, nil, @"Background Off");
    TWorld v = TMake(1, nil);
    TPrefs(@"on", @"#FFFFFF", 0.36); TLayout(v);
    TPrefs(@"off", @"#FFFFFF", 0.36); TLayout(v);
    TText(v, TWhite(), @"switched to Off after Always On");
    TBack(v, nil, @"switched to Off after Always On");
    check([v.bar ivarForeground] == nil, @"the bar's own foreground colour (none) is back");
}
static void SColorBar(void) {   // ColorBar15 running: Automatic stays out of its way (no background, no dark text); Always On is ours
    gTColorBar = YES; TSky();
    TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"ColorBar15 with Automatic");
    TBack(w, nil, @"ColorBar15 with Automatic");
    TPrefs(@"on", @"#FFFFFF", 0.36);
    TLayout(w);
    TText(w, TBlack(), @"ColorBar15 with Always On");
}
static void STheirs(void) {   // a foreground colour iPadOS asked for is kept while ours is in force, and is back after
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, [UIColor redColor]);
    check(TSame(w.time.textColor, [UIColor redColor]), @"before: iPadOS's own foreground colour (red)");
    TLayout(w);
    TText(w, TBlack(), @"ours over iPadOS's red");
    [w.bar setForegroundColor:[UIColor blueColor]];
    TText(w, TBlack(), @"iPadOS asks for blue while ours is in force");
    TPrefs(@"off", @"#FFFFFF", 0.36); TLayout(w);
    TText(w, [UIColor blueColor], @"ours ended: iPadOS's latest (blue)");
}
static void SLock(void) {   // the Lock Screen's layout (no background of its own): black text only where our background shows
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    DMApplyBarItemColor(w.fg, DMBarItemColor(w.fg, nil), NO);
    check(TSame(w.time.textColor, TWhite()) && TBackground(w) == nil, @"a bar laid out only the Lock Screen's way: iPadOS's text, no background");
    TLayout(w);
    DMApplyBarItemColor(w.fg, DMBarItemColor(w.fg, nil), NO);
    TText(w, TBlack(), @"the Lock Screen's layout of a bar with our background");
    TPrefs(@"off", @"#FFFFFF", 0.36);   // (switched Off while only the Lock Screen's layout runs on it)
    DMApplyBarItemColor(w.fg, DMBarItemColor(w.fg, nil), NO);
    TText(w, TWhite(), @"Background switched Off, then the Lock Screen's layout: iPadOS's text again");
    TBack(w, nil, @"Background switched Off, then the Lock Screen's layout");
}
static void SToDark(void) {   // a light colour changed to a dark one: iPadOS's text again and the dark colour under it at once (no light grey, no fade)
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    UIWindow *win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];   // (in a window: where a flip of iPadOS's text cross-fades)
    [win addSubview:w.bar];
    TLayout(w);
    TText(w, TBlack(), @"white at 0.36 over the sky");
    TPrefs(@"on", @"#242225", 0.70);
    gTBgSeen = [NSMutableArray array]; gTBgWatched = TBackground(w);
    TLayout(w);
    gTBgWatched = nil;
    BOOL grey = NO; for (UIColor *c in gTBgSeen) grey |= TSame(c, [UIColor colorWithWhite:0.96 alpha:0.70]);
    check(!grey, [NSString stringWithFormat:@"changed to a dark colour: the background never given the light grey, not even for a moment (given %lu colours)", (unsigned long)gTBgSeen.count]);
    TText(w, TWhite(), @"changed to a dark colour");
    TBack(w, [DMParseHexColor(@"#242225") colorWithAlphaComponent:0.70], @"changed to a dark colour");
    check(TBackground(w).layer.animationKeys.count == 0, [NSString stringWithFormat:@"changed to a dark colour: set at once, no cross-fade from a light grey (animations: %@)",
                                                          [TBackground(w).layer.animationKeys componentsJoinedByString:@", "] ?: @"none"]);
    w.bar.style = 3;   // (iPadOS's own flip afterwards: still cross-faded, as before)
    check(TBackground(w).layer.animationKeys.count > 0 && TSame(TBackground(w).backgroundColor, [UIColor colorWithWhite:0.96 alpha:0.70]),
          @"... and iPadOS's own flip to dark text afterwards: the light grey, cross-faded as before");
}
static void SDarkApp(void) {   // KT's prefs over a dark app in full screen (no picture of ours behind): iPadOS's light text, which reads best there
    TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"white at 0.36 over a dark app (a dark grey bar)");
    TBack(w, [UIColor colorWithRed:1 green:1 blue:1 alpha:0.36], @"white at 0.36 over a dark app");
    check([w.bar ivarForeground] == nil, @"the bar's foreground colour is not written");
    TPrefs(@"auto", @"#FFFFFF", 0.70); TLayout(w);
    TText(w, TBlack(), @"white at 0.70 (a light bar even over black)");
    TPrefs(@"auto", @"#FFFFFF", 0.36); TLayout(w);
    TText(w, TWhite(), @"back to 0.36: iPadOS's text again");
}
static void SDarkPicture(void) {   // KT's prefs over a dark Desktop Picture of ours: the bar a dark grey, iPadOS's text
    TDarkPicture(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TWhite(), @"white at 0.36 over a dark picture of ours");
}
static void SBehindChanges(void) {   // what is behind the bar changes (the tick lays the bar out): our sky on the Home Screen, then what covers it
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TBlack(), @"the Home Screen page 1, our sky behind");
    struct { BOOL *flag; NSString *what; } covers[] = { { &gTFullScreen, @"a dark app in full screen" }, { &gTCC, @"Control Center over the desktop" },
        { &gTCover, @"the Cover Sheet over it" }, { &gTSwitcher, @"the App Switcher" } };
    for (unsigned i = 0; i < sizeof covers / sizeof covers[0]; i++) {
        *covers[i].flag = YES; TLayout(w);
        TText(w, TWhite(), covers[i].what);
        *covers[i].flag = NO; TLayout(w);
        TText(w, TBlack(), [NSString stringWithFormat:@"... %@ gone: our sky again", covers[i].what]);
    }
    gTSMEngine = YES; gTSMFull = NO; TLayout(w);
    TText(w, TBlack(), @"Stage Manager, windows on the desktop: our sky behind the bar");
    gTSMFull = YES; TLayout(w);
    TText(w, TWhite(), @"Stage Manager, its front window in full screen");
    gTSMEngine = gTSMFull = NO;
    gWPPlane.alpha = 0.0; TLayout(w);
    TText(w, TWhite(), @"page 2 (ours faded out: iPadOS's own wallpaper there)");
    gWPPlane.alpha = 1.0; gTWallWindow.hidden = YES; TLayout(w);
    TText(w, TWhite(), @"the wallpaper's window hidden (an app in full screen)");
    gTWallWindow.hidden = NO; gWPPlane.topRead = NO; TLayout(w);
    TText(w, TWhite(), @"the picture's strip not read (yet): iPadOS's text");
    gWPPlane.topRead = YES; [gWPPlane removeFromSuperview]; TLayout(w);
    TText(w, TWhite(), @"our picture view out of its place (None): iPadOS's text");
}
static void SCCMac(void) {   // CCMAC: Control Center open with our own panel (Control Center Style Mac) leaves our sky behind the bar
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TBlack(), @"the Home Screen page 1, our sky behind");
    TOurPanel15(YES); gTCC = YES; [w.bar setForegroundColor:[UIColor whiteColor]]; TLayout(w);   // (iPadOS asks for its white text for Control Center)
    TText(w, TBlack(), @"CCMAC: our Mac panel open (15-17): the desktop stays behind the bar, its black text stays (iPadOS's white asked for)");
    gCCPExpanded = @"com.apple.control-center.ConnectivityModule"; TLayout(w);
    TText(w, TWhite(), @"CCMAC: ... a module of it opened expanded (our backdrop of Control Center's material behind the bar): iPadOS's text");
    gCCPExpanded = nil; TLayout(w);
    TText(w, TBlack(), @"CCMAC: ... the module closed, the panel still open: black again");
    gTCC = NO; [w.bar setForegroundColor:nil]; TLayout(w);
    TText(w, TBlack(), @"... Control Center closed: black (as before)");
    TOurPanel15(NO); gTCC = YES; TLayout(w);
    TText(w, TWhite(), @"iPadOS's own Control Center (another style, or Mac's check failed): its material behind the bar, iPadOS's text (as before)");
    gCCPOn = YES; TLayout(w);
    TText(w, TWhite(), @"our panel in force but not in Control Center's overlay (Apple's own look shows): iPadOS's text");
    gCCPOn = NO; gTCC = NO; TLayout(w);
    TText(w, TBlack(), @"... closed: black");
    TOurPanel18(YES); gTCC = YES; TLayout(w);
    TText(w, TBlack(), @"CCMAC: our Mac panel open on iPadOS 18 (Apple's backdrop hidden): black stays");
    gCC18Expanded = YES; TLayout(w);
    TText(w, TWhite(), @"CCMAC: ... 18, a module opened expanded (Apple's backdrop behind it): iPadOS's text");
    gCC18Expanded = NO; gCC18Editing = YES; TLayout(w);
    TText(w, TWhite(), @"CCMAC: ... 18, edit mode (Apple's whole look): iPadOS's text");
    gCC18Editing = NO; TLayout(w);
    TText(w, TBlack(), @"CCMAC: ... 18, the panel back: black");
    gTCover = YES; TLayout(w);
    TText(w, TWhite(), @"our panel over the Lock Screen (the Cover Sheet behind the bar): iPadOS's text (as before)");
    gTCover = NO; gTCC = NO; TOurPanel18(NO); TLayout(w);
    TText(w, TBlack(), @"... all closed: black");
    TOurPanel15(YES); gTSMEngine = YES; gTSMFull = YES; gTCC = YES; TLayout(w);
    TText(w, TWhite(), @"our panel over a full-screen window: no picture of ours behind the bar, iPadOS's text (as before)");
}
static void STick(void) {   // the tick: every bar laid out again when what is behind the bars changes, none while it does not
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld a = TMake(1, nil), b = TMake(1, nil);
    UIWindow *win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];   // (bars on the iPad's screen)
    [win addSubview:a.bar]; [win addSubview:b.bar];
    gAllBarCopies = [NSHashTable weakObjectsHashTable]; [gAllBarCopies addObject:a.fg]; [gAllBarCopies addObject:b.fg];
    DMWPBarBackdropTick();
    int la = a.fg.layoutsAsked, lb = b.fg.layoutsAsked;
    DMWPBarBackdropTick(); DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la && b.fg.layoutsAsked == lb, @"nothing changed: no layout asked at the next ticks");
    gTCC = YES; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 1 && b.fg.layoutsAsked == lb + 1, @"Control Center shown: every bar laid out again at the next tick");
    gTCC = NO; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 2 && b.fg.layoutsAsked == lb + 2, @"... and when it goes");
    TOurPanel15(YES); gTCC = YES; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 2 && b.fg.layoutsAsked == lb + 2, @"CCMAC: our Mac panel opened: nothing behind the bars changed, no layout asked");
    gCCPExpanded = @"m"; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 3 && b.fg.layoutsAsked == lb + 3, @"CCMAC: a module of it opened expanded: every bar laid out again");
    gCCPExpanded = nil; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 4 && b.fg.layoutsAsked == lb + 4, @"CCMAC: ... closed: laid out again");
    gTCC = NO; TOurPanel15(NO); DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 4, @"CCMAC: our panel closed: no layout asked");
    la += 2; lb += 2;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 4)];
    gWPPlane.image = [r imageWithActions:^(UIGraphicsImageRendererContext *c) { [[UIColor blackColor] setFill]; UIRectFill(CGRectMake(0, 0, 4, 4)); }];
    DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 3, @"another picture of ours decoded: laid out again (its strip is another)");
    gWPPlane.alpha = 0.0; DMWPBarBackdropTick();
    check(a.fg.layoutsAsked == la + 4, @"a page turn away from page 1: laid out again");
}
static void SNarrow(void) {   // a copy with our black text collapses under 300 pt (an app card being dismissed), then its time label restyles
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    TText(w, TBlack(), @"before: our background, black");
    w.fg.frame = CGRectMake(0, 0, 200, 24);
    TNarrowLayout(w.fg);
    TBack(w, nil, @"collapsed");
    check(TSame(w.time.textColor, TWhite()), [NSString stringWithFormat:@"collapsed: iPadOS's text again (is %@)", TName(w.time.textColor)]);
    w.bar.style = 3; w.bar.style = 1;   // (iPadOS restyles it: the time label's hook lays our items out)
    TBack(w, nil, @"collapsed, restyled");
    check(TSame(w.time.textColor, TWhite()), [NSString stringWithFormat:@"collapsed, restyled: iPadOS's text (is %@)", TName(w.time.textColor)]);
}
static void SNotHooked(void) {   // the bar's foreground colour not as read: not hooked, iPadOS's text, and the log says why
    gTNoFg = YES;
    TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    gTNoFg = NO;
    TWorld w = TMake(1, nil);
    TLayout(w);
    check(TSame(w.time.textColor, TWhite()) && [w.bar ivarForeground] == nil, @"not hooked: iPadOS's text, nothing written");
    check(TLogHas(@"has no foreground colour as read"), @"the log says the foreground colour was not as read");
}
static void SBattery(void) {   // Battery Percentage in Icon's inks: from the battery's own colour (the bar's icon tint), over the empty part
    TSky(); TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    TLayout(w);
    UIColor *icon = [w.bar.lastAttrs valueForKey:@"imageTintColor"] ?: (w.bar.style == 1 ? TWhite() : TBlack());
    CGFloat r = 1, g = 1, b = 1, a = 1; [icon getRed:&r green:&g blue:&b alpha:&a];
    MSBDBattInsideInks k = MSBDBattInsideInksFor(r, g, b, r, g, b, a);
    check(k.emptyDark, [NSString stringWithFormat:@"the battery is drawn in %@: the number over the empty part is black on the light bar", TName(icon)]);
}
static CGImageRef TPicture(int w, int h, void (^paint)(CGContextRef c)) {   // (a picture as decoded: sRGB, its top row first)
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef c = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs, kCGImageAlphaPremultipliedLast);
    CGContextTranslateCTM(c, 0, h); CGContextScaleCTM(c, 1, -1);   // (y down, as the picture's rows)
    paint(c);
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c); CGColorSpaceRelease(cs);
    return img;
}
static void SRule(void) {   // common/BarBackground.h: the rule
#ifdef MSBD_BAR_STRIP_COLUMNS
    static const double black[3] = { 0, 0, 0 };
    check(!MSBDBarTextDarkAnywhere(1, 1, 1, 0.36), @"white at 0.36 (KT's) over black: a dark grey, iPadOS's text");
    check(MSBDBarTextDarkAnywhere(1, 1, 1, 1.0) && MSBDBarTextDarkAnywhere(1, 1, 1, 0.7), @"white at 1.0 and 0.7: light even over black, black text");
    int first = -1, back = 0;
    for (int i = 0; i <= 100; i++) { int d = MSBDBarTextDarkAnywhere(1, 1, 1, i / 100.0); if (d && first < 0) first = i; if (!d && first >= 0) back = 1; }
    check(first == 47 && !back, [NSString stringWithFormat:@"white over black: black text from an opacity of 0.47 on, never back (from %.2f)", first / 100.0]);
    double kb = MSBDBattInsideContrast(MSBDBattInsideLuminance(0.36, 0.36, 0.36), 0), kw = MSBDBattInsideContrast(MSBDBattInsideLuminance(0.36, 0.36, 0.36), 1);
    check(fabs(kb - 3.14) < 0.01 && fabs(kw - 6.70) < 0.02, [NSString stringWithFormat:@"KT's 0.36 over a dark app: black %.2f:1 against iPadOS's white %.2f:1", kb, kw]);
    MSBDWPTop sky = { { 0.55, 0.70, 0.86 }, { 0.80, 0.88, 0.96 } }, dark = { { 0.02, 0.02, 0.04 }, { 0.20, 0.22, 0.28 } };
    check(MSBDBarTextDarkOver(1, 1, 1, 0.36, sky.darkest, sky.lightest), @"white at 0.36 over a light sky: black text");
    check(!MSBDBarTextDarkOver(1, 1, 1, 0.36, dark.darkest, dark.lightest), @"white at 0.36 over a dark picture: iPadOS's text");
    check(MSBDBarTextDarkOver(1, 1, 1, 0.36, black, black) == MSBDBarTextDarkAnywhere(1, 1, 1, 0.36), @"anywhere = over black");
    static const double grey30[3] = { 0.3, 0.3, 0.3 };
    check(!MSBDBarTextDarkOver(1, 1, 1, 0.36, black, grey30) && MSBDBarTextDarkOver(1, 1, 1, 0.36, grey30, grey30),
          @"white at 0.36 over a strip from black to a dark grey: iPadOS's text (its darkest part counts); over the dark grey alone: black");
    UIColor *def = DMParseHexColor(@"#242225"); CGFloat r, g, b; [def getRed:&r green:&g blue:&b alpha:NULL];
    BOOL anyDark = NO; for (int i = 0; i <= 100; i++) anyDark |= MSBDBarTextDarkAnywhere(r, g, b, i / 100.0) || MSBDBarTextDarkOver(r, g, b, i / 100.0, sky.darkest, sky.lightest);
    check(!MSBDBarColorIsLight(r, g, b) && !anyDark, @"the default #242225: a dark colour, never black text");
    check(!MSBDBarColorIsLight(0.45, 0.45, 0.45) && MSBDBarColorIsLight(0.47, 0.47, 0.47), @"a grey is light from about sRGB 0.46 (luminance 0.18)");
    // where iPadOS puts dark text the backdrop is light (sRGB 0.5 .. 1): there a light colour's bar takes black anyway
    int bad = 0;
    for (int c = 0; c <= 20; c++) for (int i = 1; i <= 20; i++) for (int k = 0; k <= 10; k++) {
        double v = 0.45 + c * 0.0275, al = i / 20.0, behind = 0.5 + k * 0.05;
        if (!MSBDBarColorIsLight(v, v, v)) continue;
        double y = MSBDBattInsideLuminance(MSBDBarOver(v, al, behind), MSBDBarOver(v, al, behind), MSBDBarOver(v, al, behind));
        if (!MSBDBattInsideDarkReads(y)) bad++;
    }
    check(bad == 0, [NSString stringWithFormat:@"a light colour over a light backdrop always reads black best (%d not)", bad]);
    check(MSBDBarBackgroundChosen(1, 0) && MSBDBarBackgroundChosen(1, 1) && MSBDBarBackgroundChosen(0, 1) && !MSBDBarBackgroundChosen(0, 0), @"the background: a light colour always, a dark one under light text");
    // the picture's strip under the bar, read from a picture as decoded
    CGImageRef p1 = TPicture(200, 400, ^(CGContextRef c) {   // a light sky over the top fifth, dark ground below
        CGContextSetRGBFillColor(c, 0.80, 0.88, 0.96, 1); CGContextFillRect(c, CGRectMake(0, 0, 200, 80));
        CGContextSetRGBFillColor(c, 0.05, 0.05, 0.05, 1); CGContextFillRect(c, CGRectMake(0, 80, 200, 320));
    });
    double d1[3] = { -1, -1, -1 }, l1[3] = { -1, -1, -1 };
    int ok1 = MSBDBarTopStrip(p1, 20, d1, l1);
    check(ok1 && MSBDBattInsideLuminance(d1[0], d1[1], d1[2]) > 0.6 && MSBDBattInsideLuminance(l1[0], l1[1], l1[2]) > 0.6,
          [NSString stringWithFormat:@"a light sky over dark ground: the strip under the bar is the sky (darkest %.2f %.2f %.2f, lightest %.2f %.2f %.2f)", d1[0], d1[1], d1[2], l1[0], l1[1], l1[2]]);
    CGImageRef p2 = TPicture(200, 400, ^(CGContextRef c) {   // the top: light on the left half, dark on the right
        CGContextSetRGBFillColor(c, 0.95, 0.95, 0.95, 1); CGContextFillRect(c, CGRectMake(0, 0, 100, 400));
        CGContextSetRGBFillColor(c, 0.05, 0.05, 0.10, 1); CGContextFillRect(c, CGRectMake(100, 0, 100, 400));
    });
    double d2[3], l2[3];
    int ok2 = MSBDBarTopStrip(p2, 20, d2, l2);
    check(ok2 && MSBDBattInsideLuminance(d2[0], d2[1], d2[2]) < 0.02 && MSBDBattInsideLuminance(l2[0], l2[1], l2[2]) > 0.8,
          [NSString stringWithFormat:@"half light, half dark under the bar: both read (darkest %.2f, lightest %.2f)", MSBDBattInsideLuminance(d2[0], d2[1], d2[2]), MSBDBattInsideLuminance(l2[0], l2[1], l2[2])]);
    check(!MSBDBarTopStrip(NULL, 20, d2, l2) && !MSBDBarTopStrip(p2, 0, d2, l2), @"no picture, or no rows: not read");
    CGImageRelease(p1); CGImageRelease(p2);
#else
    check(NO, @"the rule over what is behind the bar is not in BarBackground.h");
#endif
}

// ---- the 17.5's sequence (1.8.7.6 FULLBAR, the trace of 16 Nov): the Stage Manager engine on iPadOS 17, KT's prefs ----
// The screen's own bar: SpringBoard's status bar window (SBStatusBarWindow), its wrapper (iPadOS fades it out over a window alone in full screen),
// the bar, its contents view (a new one after each such fade, and at each open and close of our Control Center). A window card
// (SBFluidSwitcherItemContainer in SBMainSwitcherWindow) has its app's own bar strip, styled for that app, which our layout holds hidden unless
// it is the top bar (bb-smstrip.inc). iPadOS asks the screen's bar for light content with white (KT's dark wallpaper), every time.
// A second display (the A12Z's TV): its windows say they are on a screen of their own (-screen of the window classes made here: a UIScreen set
// on the window, else UIKit's own), which is all the cut code asks of a screen.
static const void *kTScreenKey = &kTScreenKey;
static UIScreen *gTTV;
static id TWindowScreen(UIWindow *self, SEL _cmd) {
    id s = objc_getAssociatedObject(self, kTScreenKey);
    if (s) return s;
    struct objc_super sup = { self, [UIWindow class] };
    return ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}
static Class TClassNamed(const char *name, Class super) {
    Class c = objc_getClass(name);
    if (!c) {
        c = objc_allocateClassPair(super, name, 0);
        if ([super isSubclassOfClass:[UIWindow class]]) class_addMethod(c, @selector(screen), (IMP)TWindowScreen, "@16@0:8");
        objc_registerClassPair(c);
    }
    return c;
}
typedef struct { UIView *card; _UIStatusBar *bar; TFg *fg; UILabel *time; } TStrip;
static UIWindow *gTSBWin, *gTSwWin;
static UIView *gTWrapper;
static _UIStatusBar *gTScreenBar;
static TFg *gTScreenFg;
static TFg *TContents(_UIStatusBar *bar) {   // (a contents view as iPadOS makes one: its region with the time, styled as the bar is)
    TFg *fg = [[TFg alloc] initWithFrame:bar.bounds];
    fg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [bar addSubview:fg];
    UIView *region = [[UIView alloc] initWithFrame:CGRectMake(20, 0, 120, 24)];
    [fg addSubview:region];
    UILabel *time = [[TTimeClass() alloc] initWithFrame:CGRectMake(0, 0, 60, 24)];
    [region addSubview:time];
    bar.time = time;
    [bar restyle];
    if (!gAllBarCopies) gAllBarCopies = [NSHashTable weakObjectsHashTable];
    [gAllBarCopies addObject:fg];   // (-didMoveToWindow)
    return fg;
}
static void TDress(UIView *fg) {   // (our layout's items: the logo, which the time label's restyle hook looks for)
    if (objc_getAssociatedObject(fg, kLogoKey)) return;
    UILabel *logo = [[UILabel alloc] initWithFrame:CGRectMake(4, 0, 12, 24)];
    [fg addSubview:logo];
    objc_setAssociatedObject(fg, kLogoKey, logo, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void TScreenNew(void) {   // (iPadOS gives the screen's bar a new contents view; the old one goes)
    [gTScreenFg removeFromSuperview];
    gTScreenFg = TContents(gTScreenBar);
}
static void TReplayWorld(long long iPadOSStyle, UIColor *iPadOSColor) {
    gTSMEngine = YES; gTSTUI = YES; gTSMFull = NO; gTCC = NO; gTSwitcher = NO; gTScreenSwitcher = NO;
    gTSBWin = [[TClassNamed("SBStatusBarWindow", [UIWindow class]) alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]; gTSBWin.hidden = NO;
    gTSwWin = [[TClassNamed("SBMainSwitcherWindow", [UIWindow class]) alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]; gTSwWin.hidden = NO;
    gTWrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1024, 24)];
    [gTSBWin addSubview:gTWrapper];
    gTScreenBar = [[_UIStatusBar alloc] initWithFrame:gTWrapper.bounds];
    [gTWrapper addSubview:gTScreenBar];
    gTScreenBar.style = iPadOSStyle;
    gTScreenFg = TContents(gTScreenBar);
    if (iPadOSColor) [gTScreenBar setForegroundColor:iPadOSColor];
    TDress(gTScreenFg);
}
static TStrip TCardIn(UIWindow *sw, long long appStyle) {   // (a window of an app: its card, small, in front, with the app's own bar strip)
    TStrip c;
    c.card = [[TClassNamed("SBFluidSwitcherItemContainer", [UIView class]) alloc] initWithFrame:CGRectMake(150, 120, 600, 450)];
    [sw addSubview:c.card];
    c.bar = [[_UIStatusBar alloc] initWithFrame:CGRectMake(0, 0, 600, 24)];
    c.bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [c.card addSubview:c.bar];
    c.bar.style = appStyle;
    c.fg = TContents(c.bar);
    c.time = c.bar.time;
    return c;
}
static TStrip TCard(long long appStyle) { return TCardIn(gTSwWin, appStyle); }   // (on the iPad's screen)
static void TFull(TStrip c, BOOL full) {   // (the window in full screen -- its card as big as the screen, in front -- or a window again)
    c.card.frame = full ? c.card.superview.bounds : CGRectMake(150, 120, 600, 450);
    if (full) [c.card.superview bringSubviewToFront:c.card];
}
static void TLayoutAll(void) {   // (what the tick and iPadOS's layouts do: every copy laid out; the strip that is the top bar shown -- DMSMRefreshBars)
    for (int pass = 0; pass < 2; pass++)
        for (UIView *fg in gAllBarCopies.allObjects) {
            if (!fg.window) continue;
            if ([NSStringFromClass([fg.window class]) isEqualToString:@"SBMainSwitcherWindow"] && DMSMStripIsMenuBar(fg) && fg.alpha < 1.0) fg.alpha = 1.0;
            TLayoutCopy(fg);
        }
}
static BOOL TShows(UIView *v) {
    for (UIView *x = v; x; x = x.superview) if (x.hidden || x.alpha < 0.01) return NO;
    return v.window != nil;
}
static int TLayersAtTop(void) {   // (views of ours with a background, showing, over the top of the screen: each is one more layer of the colour)
    int n = 0;
    NSMutableArray<UIView *> *todo = [NSMutableArray arrayWithObjects:gTSBWin, gTSwWin, nil];
    while (todo.count) {
        UIView *v = todo.lastObject; [todo removeLastObject]; [todo addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[UIWindow class]] || !v.backgroundColor || CGColorGetAlpha(v.backgroundColor.CGColor) <= 0.0 || !TShows(v)) continue;
        if (CGRectContainsPoint([v convertRect:v.bounds toView:nil], CGPointMake(512, 5))) n++;
    }
    return n;
}
static UILabel *TTopTime(void) {   // (the time label of the bar on top: the screen's own while it shows, else the strip that is the top bar)
    if (TShows(gTScreenFg)) return gTScreenBar.time;
    for (UIView *fg in gAllBarCopies.allObjects)
        if ([NSStringFromClass([fg.window class]) isEqualToString:@"SBMainSwitcherWindow"] && TShows(fg) && CGRectContainsPoint([fg convertRect:fg.bounds toView:nil], CGPointMake(512, 5)))
            return ((_UIStatusBar *)fg.superview).time;
    return nil;
}
static void TTop(UIColor *want, int layers, NSString *where) {
    UILabel *t = TTopTime();
    check(t && TSame(t.textColor, want), [NSString stringWithFormat:@"%@: the bar on top (%@) is drawn in %@ (is %@)", where, !t ? @"none" : t == gTScreenBar.time ? @"the screen's own" : @"the window's strip",
                                          TName(want), TName(t.textColor)]);
    UILabel *logo = t ? objc_getAssociatedObject(t.superview.superview, kLogoKey) : nil;
    if (logo) check(TSame(logo.textColor, want), [NSString stringWithFormat:@"%@: our items on it too (is %@)", where, TName(logo.textColor)]);
    int n = TLayersAtTop();
    check(n == layers, [NSString stringWithFormat:@"%@: %d layer(s) of our background over the top of the screen (is %d)", where, layers, n]);
}
static UIColor *TKT(void) { return [UIColor colorWithRed:1 green:1 blue:1 alpha:1]; }
static void SFullBar(void) {   // the 17.5's sequence, KT's prefs (Automatic, #FFFFFF at 0.3635, High Sierra's sky): A white on white, B the layers
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TLayoutAll();
    TTop(TBlack(), 1, @"Home Screen over our sky");
    TStrip clock = TCard(1);   // (Clock: light content, white)
    TLayoutAll();
    TTop(TBlack(), 1, @"Clock's window from the Dock");
    check(clock.fg.alpha < 0.01, @"... its own strip held hidden (not the top bar)");
    TFull(clock, YES); gTSMFull = YES; gTWrapper.alpha = 0.0;   // (alone in its stage: iPadOS fades the screen's bar out)
    TLayoutAll();
    TTop(TWhite(), 1, @"Clock in full screen alone: its strip is the top bar, Clock's own white");
    TFull(clock, NO); gTSMFull = NO; gTWrapper.alpha = 1.0; TScreenNew();
    TLayoutAll();
    TTop(TBlack(), 1, @"back to a window (the screen's bar has new contents)");
    TStrip settings = TCard(3);   // (Settings: dark content, its own black)
    TFull(settings, YES); gTSMFull = YES;   // (Clock's window beside it in the stage: the screen's bar stays on top, styled for iPadOS's wallpaper)
    TLayoutAll();
    TTop(TBlack(), 1, @"Settings in full screen, Clock's window beside it: Settings' own black, not iPadOS's white");
    check(settings.fg.alpha < 0.01, @"... Settings' own strip held hidden under the screen's bar");
    check(TSame(objc_getAssociatedObject(gTScreenBar, kBarTheirFgKey), TWhite()), @"... iPadOS's own colour for the bar kept (white): back after");
    check(TLogHas(@"the text of the full-screen window behind it"), @"... the log says the screen's bar takes the window's text");
    for (int cycle = 2; cycle <= 3; cycle++) {
        TFull(settings, NO); gTSMFull = NO; TLayoutAll();
        TTop(TBlack(), 1, [NSString stringWithFormat:@"cycle %d: back to a window", cycle]);
        TFull(clock, YES); gTSMFull = YES; TLayoutAll();
        TTop(TWhite(), 1, [NSString stringWithFormat:@"cycle %d: Clock in full screen, Settings' window beside it: Clock's own white", cycle]);
        TFull(clock, NO); gTSMFull = NO; TLayoutAll();
        TTop(TBlack(), 1, [NSString stringWithFormat:@"cycle %d: back", cycle]);
        TFull(settings, YES); gTSMFull = YES; TLayoutAll();
        TTop(TBlack(), 1, [NSString stringWithFormat:@"cycle %d: Settings in full screen, Clock's window beside it", cycle]);
    }
    TFull(settings, NO); gTSMFull = NO;
    [clock.card removeFromSuperview]; [settings.card removeFromSuperview];   // (Home: both windows go with it)
    TLayoutAll();
    TTop(TBlack(), 1, @"Home pressed, both windows gone");
    [gTSwWin addSubview:settings.card]; TFull(settings, YES); gTSMFull = YES; gTWrapper.alpha = 0.0;   // (Settings alone, from the Dock, then full screen)
    TLayoutAll();
    TTop(TBlack(), 1, @"Settings in full screen alone after Home: its strip is the top bar, Settings' own black");
    TFull(settings, NO); gTSMFull = NO; gTWrapper.alpha = 1.0; TScreenNew();
    TLayoutAll();
    TTop(TBlack(), 1, @"back to a window");
    [settings.card removeFromSuperview]; TLayoutAll();
    for (int i = 1; i <= 3; i++) {   // (our Control Center opened and closed from the bar: the screen's bar gets new contents each time)
        TOurPanel15(YES); gTCC = YES; gTWrapper.alpha = 0.0; TLayoutAll();
        TOurPanel15(NO); gTCC = NO; gTWrapper.alpha = 1.0; TScreenNew(); TLayoutAll();
        TTop(TBlack(), 1, [NSString stringWithFormat:@"our Control Center opened and closed %d time(s)", i]);
    }
    TPrefs(@"off", @"#FFFFFF", 0.3635); TLayoutAll();
    TTop(TWhite(), 0, @"Background Off on the Home Screen (iPadOS's text, as before; no background of ours anywhere)");
    [gTSwWin addSubview:clock.card]; [gTSwWin addSubview:settings.card]; TFull(settings, YES); gTSMFull = YES;
    int asked = gTScreenFg.layoutsAsked; TLayoutAll();
    TTop(TBlack(), 0, @"Background Off, Settings in full screen with Clock's window: Settings' own black (iPadOS's white was for its wallpaper)");
    check(gTScreenFg.layoutsAsked > asked, @"... the bar laid out again after it (the battery's number takes the new colour)");
    TFull(settings, NO); gTSMFull = NO; TLayoutAll();
    TTop(TWhite(), 0, @"Background Off, back to a window: iPadOS's text again");
    TPrefs(@"auto", @"#FFFFFF", 0.3635); TLayoutAll();
    TTop(TBlack(), 1, @"Background back to Automatic");
    TFull(clock, YES); gTSMFull = NO; [gTSwWin bringSubviewToFront:settings.card]; TLayoutAll();   // (Clock in full screen behind Settings' window: the front window is a window)
    TTop(TWhite(), 1, @"Clock in full screen with Settings' window in front of it: what is under the bar is Clock, its own white (not our sky's black)");
}
static void SFullBarLightWall(void) {   // iPadOS's light wallpaper (it asks for dark content) under a dark app in full screen beside another window
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(3, nil);
    TStrip settings = TCard(3), clock = TCard(1);
    TFull(clock, YES); gTSMFull = YES; TLayoutAll();
    TTop(TWhite(), 1, @"Clock in full screen, Settings' window beside it, iPadOS's black asked for: Clock's own white");
    TPrefs(@"auto", @"#242225", 0.70); TLayoutAll();
    TTop(TWhite(), 1, @"... the default dark colour: Clock's own white on it");
    check(TSame(objc_getAssociatedObject(gTScreenFg, kBackgroundKey) ? ((UIView *)objc_getAssociatedObject(gTScreenFg, kBackgroundKey)).backgroundColor : nil,
                [DMParseHexColor(@"#242225") colorWithAlphaComponent:0.70]), @"... and the chosen dark colour under it (it follows the text)");
    TFull(clock, NO); gTSMFull = NO; TFull(settings, YES); gTSMFull = YES; TLayoutAll();
    TTop(TBlack(), 1, @"... Settings in full screen instead: its own black, the light grey under it");
    (void)settings;
}
static void SFullBarElse(void) {   // where the screen's bar keeps iPadOS's text, as before: 15/16, the other engines, the App Switcher, Control Center
    TSky(); TPrefs(@"off", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TStrip clock = TCard(1), settings = TCard(3);
    TFull(settings, YES); gTSMFull = YES; TLayoutAll();
    TTop(TBlack(), 0, @"Settings in full screen beside Clock's window (17, Stage Manager engine)");
    gTSwitcher = YES; gTSwitcherOn = [UIScreen mainScreen]; TLayoutAll();
    TTop(TWhite(), 0, @"... the App Switcher up (on this screen): its material behind the bar, iPadOS's text");
    gTSwitcher = NO; gTSwitcherOn = nil; gTScreenSwitcher = YES; TLayoutAll();
    TTop(TWhite(), 0, @"... that screen's App Switcher (its own display's): iPadOS's text");
    gTScreenSwitcher = NO; gMSWOpen = YES; TLayoutAll();
    TTop(TWhite(), 0, @"... our Mac Switcher open over it: iPadOS's text, as before");
    gMSWOpen = NO;
    gTScreenSwitcher = NO; gTCC = YES; TLayoutAll();
    TTop(TWhite(), 0, @"... iPadOS's Control Center over it: iPadOS's text");
    gTCC = NO; TLayoutAll();
    TTop(TBlack(), 0, @"... all gone: Settings' own black again");
    gTSTUI = NO; TLayoutAll();
    TTop(TWhite(), 0, @"iPadOS 15/16's bar classes (iPadOS fades its bar out over every full screen there): nothing of this, iPadOS's text");
    gTSTUI = YES; gTSMEngine = NO; TLayoutAll();
    TTop(TWhite(), 0, @"another engine (its full screen is iPadOS's own): iPadOS's text");
    gTSMEngine = YES; TLayoutAll();
    TFull(settings, NO); TFull(clock, NO); gTSMFull = NO; TLayoutAll();
    TTop(TWhite(), 0, @"windows only (no full-screen window): iPadOS's text");
}
static void SFullBarTick(void) {   // the tick: the bars laid out again when the window behind the screen's bar changes, with no picture of ours too
    TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();   // (Desktop Picture None: nothing of ours behind any bar)
    TReplayWorld(1, TKT());
    TStrip clock = TCard(1), settings = TCard(3);
    TLayoutAll();
    DMWPBarBackdropTick(); DMWPBarBackdropTick();
    int l0 = gTScreenFg.layoutsAsked;
    DMWPBarBackdropTick();
    check(gTScreenFg.layoutsAsked == l0, @"nothing changed: no layout asked");
    TFull(settings, YES); gTSMFull = YES; DMWPBarBackdropTick();
    check(gTScreenFg.layoutsAsked > l0, @"Settings in full screen beside Clock's window (None): the screen's bar laid out again at the next tick");
    int l1 = gTScreenFg.layoutsAsked;
    TLayoutAll(); l1 = gTScreenFg.layoutsAsked; DMWPBarBackdropTick();
    check(gTScreenFg.layoutsAsked == l1, @"... nothing more while it stays");
    settings.bar.style = 1; DMWPBarBackdropTick();   // (its app takes the other style)
    check(gTScreenFg.layoutsAsked > l1, @"... its app asks for the other style: laid out again");
    TLayoutAll();
    TTop(TWhite(), 1, @"... and the bar takes it (its white)");
    int l2 = gTScreenFg.layoutsAsked;
    TFull(settings, NO); gTSMFull = NO; DMWPBarBackdropTick();
    check(gTScreenFg.layoutsAsked > l2, @"back to a window: laid out again");
    (void)clock;
}
static void SNewContents(void) {   // the screen's bar given new contents, again and again: one background of ours, and it follows the preferences
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TLayoutAll();
    for (int i = 0; i < 6; i++) { TScreenNew(); TLayoutAll(); }
    TTop(TBlack(), 1, @"six new contents views");
    TPrefs(@"on", @"#FF0000", 0.50); TLayoutAll();
    int n = 0; for (UIView *v in gTScreenBar.subviews) for (UIView *x in [@[v] arrayByAddingObjectsFromArray:v.subviews]) if (x.backgroundColor && CGColorGetAlpha(x.backgroundColor.CGColor) > 0.0 && TShows(x)) n++;
    check(n == 1, [NSString stringWithFormat:@"another colour: one background in the bar, in it (is %d)", n]);
    TPrefs(@"off", @"#FF0000", 0.50); TLayoutAll();
    check(TLayersAtTop() == 0, @"Background Off: none left");
    gTScreenFg.alpha = 0.0; TPrefs(@"on", @"#FFFFFF", 0.3635); TLayoutAll();
    check(TLayersAtTop() == 0, @"a copy hidden by its opacity (held, or by another tweak): its background hidden with it");
    gTScreenFg.alpha = 1.0;
    check(TLayersAtTop() == 1, @"... shown again: with it");
}
// ---- 1.8.7.6 FULLBAR round 1 (the review) ----
// A second display (the A12Z's TV): its own bar (SBStatusBarWindow) and its own windows (SBMainSwitcherWindow), on a screen of their own.
typedef struct { UIWindow *sbWin, *swWin; UIView *wrapper; _UIStatusBar *bar; TFg *fg; } TDisplay;
static TDisplay TTVWorld(long long iPadOSStyle, UIColor *iPadOSColor) {
    if (!gTTV) gTTV = class_createInstance([UIScreen class], 0);
    TDisplay d;
    CGRect tv = CGRectMake(0, 0, 1920, 1080);
    d.sbWin = [[TClassNamed("SBStatusBarWindow", [UIWindow class]) alloc] initWithFrame:tv];
    d.swWin = [[TClassNamed("SBMainSwitcherWindow", [UIWindow class]) alloc] initWithFrame:tv];
    objc_setAssociatedObject(d.sbWin, kTScreenKey, gTTV, OBJC_ASSOCIATION_RETAIN_NONATOMIC); d.sbWin.hidden = NO;
    objc_setAssociatedObject(d.swWin, kTScreenKey, gTTV, OBJC_ASSOCIATION_RETAIN_NONATOMIC); d.swWin.hidden = NO;
    d.wrapper = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1920, 24)];
    [d.sbWin addSubview:d.wrapper];
    d.bar = [[_UIStatusBar alloc] initWithFrame:d.wrapper.bounds];
    [d.wrapper addSubview:d.bar];
    d.bar.style = iPadOSStyle;
    d.fg = TContents(d.bar);
    if (iPadOSColor) [d.bar setForegroundColor:iPadOSColor];
    TDress(d.fg);
    return d;
}
static void TTVText(TDisplay d, UIColor *want, NSString *where) {
    UILabel *logo = objc_getAssociatedObject(d.fg, kLogoKey);
    check(d.fg.window.screen == gTTV && TSame(d.bar.time.textColor, want) && TSame(logo.textColor, want),
          [NSString stringWithFormat:@"%@: the TV's own bar is drawn in %@ (is %@, our items %@)", where, TName(want), TName(d.bar.time.textColor), TName(logo.textColor)]);
}
static void SFullBarTV(void) {   // what is over a full-screen window is asked for its own screen: the iPad's states are the iPad's, the TV's the TV's
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());                   // (the iPad: its Home Screen over our sky)
    TDisplay tv = TTVWorld(1, TKT());         // (the TV: its own bar, iPadOS's white for its wallpaper, no picture of ours)
    TStrip tvClock = TCardIn(tv.swWin, 1), tvSettings = TCardIn(tv.swWin, 3);
    TFull(tvSettings, YES); TLayoutAll();
    TTVText(tv, TBlack(), @"the TV: Settings in full screen beside Clock's window, Settings' own black");
    TTop(TBlack(), 1, @"... the iPad's Home Screen meanwhile, over our sky");
    struct { BOOL *flag; NSString *what; } ipad[] = { { &gTCC, @"iPadOS's Control Center on the iPad" }, { &gTCover, @"the Cover Sheet on the iPad" } };
    for (unsigned i = 0; i < sizeof ipad / sizeof ipad[0]; i++) {
        *ipad[i].flag = YES; TLayoutAll();
        TTVText(tv, TBlack(), [NSString stringWithFormat:@"%@: the TV's bar keeps Settings' black (not iPadOS's white on Settings' white)", ipad[i].what]);
        *ipad[i].flag = NO;
    }
    gTSwitcher = YES; gTSwitcherOn = [UIScreen mainScreen]; TLayoutAll();
    TTVText(tv, TBlack(), @"the iPad's App Switcher up: the TV's bar keeps Settings' black");
    gTSwitcherOn = gTTV; TLayoutAll();
    TTVText(tv, TWhite(), @"the TV's own App Switcher up: its material behind the TV's bar, iPadOS's text");
    gTSwitcher = NO; gTSwitcherOn = nil;
    gMSWOpen = YES; gTMSWScreen = [UIScreen mainScreen]; TLayoutAll();
    TTVText(tv, TBlack(), @"our Mac Switcher open on the iPad: the TV's bar keeps Settings' black");
    gTMSWScreen = gTTV; TLayoutAll();
    TTVText(tv, TWhite(), @"our Mac Switcher open on the TV: iPadOS's text on the TV's bar, as before");
    gMSWOpen = NO; gTMSWScreen = nil; TLayoutAll();
    TTVText(tv, TBlack(), @"... closed: Settings' black again");
    TStrip clock = TCard(1), settings = TCard(3);   // (the other way round: a full screen on the iPad beside a window, the TV's states)
    TFull(settings, YES); gTSMFull = YES; TLayoutAll();
    TTop(TBlack(), 1, @"the iPad: Settings in full screen beside Clock's window, Settings' own black");
    gTSwitcher = YES; gTSwitcherOn = gTTV; TLayoutAll();
    TTop(TBlack(), 1, @"... the TV's App Switcher up: the iPad's bar keeps Settings' black");
    gMSWOpen = YES; gTMSWScreen = gTTV; TLayoutAll();
    TTop(TBlack(), 1, @"... and our Mac Switcher open on the TV: the iPad's bar keeps it");
    gMSWOpen = NO; gTMSWScreen = nil; gTSwitcherOn = [UIScreen mainScreen]; TLayoutAll();
    TTop(TWhite(), 1, @"... the iPad's own App Switcher: iPadOS's text on the iPad's bar");
    gTSwitcher = NO; gTSwitcherOn = nil; gTCC = YES; TLayoutAll();
    TTop(TWhite(), 1, @"... iPadOS's Control Center on the iPad: iPadOS's text on the iPad's bar");
    TTVText(tv, TBlack(), @"... while the TV's bar keeps Settings' black");
    gTCC = NO;
    (void)tvClock; (void)clock;
}
static void SFullBarHeld(void) {   // a strip that stops being the top bar while our black is on it (a colour light even over black), then Off, 0.36
    TPrefs(@"auto", @"#FFFFFF", 0.60); TInstall();   // (white at 0.6: light even over black, our black on every bar it shows on; Desktop Picture None)
    TReplayWorld(1, TKT());
    TStrip settings = TCard(3);
    TFull(settings, YES); gTSMFull = YES; gTWrapper.alpha = 0.0;   // (Settings alone in its stage, in full screen: iPadOS fades the screen's bar out)
    TLayoutAll();
    TTop(TBlack(), 1, @"white at 0.6, Settings in full screen alone: its strip is the top bar, black");
    check(DMBarDarkTextOn(settings.fg), @"... our black on its strip (light even over black)");
    TStrip clock = TCard(1); gTWrapper.alpha = 1.0; TScreenNew();   // (Clock's window opened into its stage: the screen's bar back, new contents)
    TLayoutAll();
    TTop(TBlack(), 1, @"... Clock's window opened into the stage: the screen's bar on top");
    check(settings.fg.alpha < 0.01 && !DMBarDarkTextOn(settings.fg), @"... Settings' strip held hidden, and our black on it ended with it");
    settings.bar.style = 1; settings.bar.style = 3;   // (iPadOS restyles the hidden strip: its time label's hook lays our items out)
    check(!DMBarDarkTextOn(settings.fg), @"... a restyle of the hidden strip does not bring our black back");
    TPrefs(@"off", @"#FFFFFF", 0.60); TLayoutCopy(gTScreenFg);
    TTop(TBlack(), 0, @"... Background Off: the screen's bar takes Settings' own black (not iPadOS's white on Settings' white)");
    TPrefs(@"auto", @"#FFFFFF", 0.3635); TLayoutAll();
    TTop(TBlack(), 1, @"... then KT's white at 0.36: Settings' own black");
    (void)clock;
}
static void SFullBarHidden(void) {   // a full-size card that does not show (left in the tree), or whose display goes Home: not behind the bar
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TStrip clock = TCard(1), settings = TCard(3);
    TFull(clock, YES); gTSMFull = YES; TLayoutAll();
    TTop(TWhite(), 1, @"Clock in full screen beside Settings' window: Clock's own white");
    gTSMFull = NO;   // (Home, or its desktop left: nothing in front is in full screen)
    NSArray<NSString *> *what = @[ @"Clock's full-size card left hidden in the tree", @"... left faded out", @"... left off the screen",
                                   @"... its display going Home (the windows zoom into their icons)" ];
    for (NSUInteger i = 0; i < what.count; i++) {
        if (i == 0) clock.card.hidden = YES; else if (i == 1) clock.card.alpha = 0.0; else if (i == 2) clock.card.frame = CGRectOffset(gTSwWin.bounds, 1100, 0); else gTGoesHome = YES;
        TLayoutAll();
        TTop(TBlack(), 1, [NSString stringWithFormat:@"%@: the Home Screen's bar over our sky stays black (not Clock's white)", what[i]]);
        check(DMBarWindowTextOn([UIScreen mainScreen], NULL) == nil, [NSString stringWithFormat:@"%@: no window's text for the screen's bar", what[i]]);
        clock.card.hidden = NO; clock.card.alpha = 1.0; clock.card.frame = gTSwWin.bounds; gTGoesHome = NO;
    }
    check(TSame(DMBarWindowTextOn([UIScreen mainScreen], NULL), TWhite()), @"... Clock's card showing again: its white is the window's text");
    (void)settings;
}
static TStrip TCardBuilding(long long appStyle) {   // (a window just opened: its strip has its region, a status icon not shown yet, no time)
    TStrip c;
    c.card = [[TClassNamed("SBFluidSwitcherItemContainer", [UIView class]) alloc] initWithFrame:CGRectMake(150, 120, 600, 450)];
    [gTSwWin addSubview:c.card];
    c.bar = [[_UIStatusBar alloc] initWithFrame:CGRectMake(0, 0, 600, 24)];
    c.bar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [c.card addSubview:c.bar];
    c.bar.style = appStyle;
    c.fg = [[TFg alloc] initWithFrame:c.bar.bounds];
    [c.bar addSubview:c.fg];
    UIView *region = [[UIView alloc] initWithFrame:CGRectMake(20, 0, 120, 24)];
    [c.fg addSubview:region];
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
    icon.hidden = YES;
    [region addSubview:icon];
    [gAllBarCopies addObject:c.fg];
    c.time = nil;
    return c;
}
static void SFullBarBuilding(void) {   // a full-screen window's strip still being built: its text not known (not the colour last seen on screen)
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TLayoutAll();
    TTop(TBlack(), 1, @"Home Screen over our sky: black");
    TStrip settings = TCard(3), clock = TCardBuilding(1);
    TFull(clock, YES); gTSMFull = YES; TLayoutAll();
    TTop(TWhite(), 1, @"Clock in full screen beside Settings' window, its strip still being built: iPadOS's text, not the black last on screen");
    check(!TLogHas(@"the text of the full-screen window behind it, 0.00 0.00 0.00"), @"... the log never says the window's text is black");
    UILabel *time = [[TTimeClass() alloc] initWithFrame:CGRectMake(0, 0, 60, 24)];   // (its time comes, in Clock's own style)
    [TRegion(clock.fg) insertSubview:time atIndex:0];
    clock.bar.time = time; [clock.bar restyle];
    TLayoutAll();
    TTop(TWhite(), 1, @"... its time shown: Clock's own white");
    check(TLogHas(@"the text of the full-screen window behind it, 1.00 1.00 1.00"), @"... the log says the screen's bar takes the window's text");
    (void)settings;
}

// ---- 1.8.7.6: the 17.5's crash at a Notification Center pull (KT's white at 0.36): nothing of the bar's colour written inside its own
// constraint pass (StatusBar.x gDMBarConstraintDepth). The code before the fix raises UIKit's exception in these passes. ----
static UIWindow *TPassWindow(TWorld w) { UIWindow *win = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)]; win.hidden = NO; [win addSubview:w.bar]; return win; }
static int TLogCount(NSString *part) { int n = 0; for (NSString *l in gLog) if ([l containsString:part]) n++; return n; }
static BOOL TPass(_UIStatusBar *bar, UIWindow *win, NSString *what) {   // (the bar's constraint pass as UIKit runs it: asked for, then the window's layout)
    gTRestylesInPass = 0; gTLayoutsInPass = 0; gTDarkInPass = -1; gTColourChangedInPass = 0;
    [bar setNeedsUpdateConstraints];
    @try { [win layoutIfNeeded]; }
    @catch (NSException *e) { check(NO, [NSString stringWithFormat:@"%@: the bar's constraint pass raised %@: %.140s", what, e.name, e.reason.UTF8String]); return NO; }
    check(YES, [NSString stringWithFormat:@"%@: the bar's constraint pass, no exception", what]);
    check(gTRestylesInPass == 0 && gTColourChangedInPass == 0, [NSString stringWithFormat:@"%@: nothing of the bar's colour written inside its constraint pass (restyles there %d, colour changes %d)",
                                                              what, gTRestylesInPass, gTColourChangedInPass]);
    return YES;
}
static void SNCPull(void) {   // the 17.5's pull: our black ends as the Cover Sheet comes, decided by the time label's colour and its tint inside the pass
    gTConstraintPass = YES; gTOurLayout = YES; gTTintHook = YES; gTDropInPass = YES;   // (18.5's way: only the next turn lays the copy out)
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    UIWindow *win = TPassWindow(w);
    TLayout(w); TSettle();
    TText(w, TBlack(), @"before the pull: our black over the sky");
    gTRestyleDirties = YES; gTPlaceItems = YES; gTSetColour = YES; gTTintPath = YES;
    TPass(w.bar, win, @"a pass with nothing changed");
    check(!TLogHas(@"deferred"), @"... nothing deferred");
    gTCover = YES;   // (Notification Center pulled down: the Cover Sheet behind the bar, iPadOS's text)
    if (TPass(w.bar, win, @"the pull")) {
        check(gTDarkInPass == 1, @"the pull: inside the pass our black's state is kept (no state changed there)");
        check(TLogCount(@"(our black ends) deferred") == 1 && TLogCount(@"deferred") == 1,
              [NSString stringWithFormat:@"the pull: the log says deferred, once for the copy (asked by the label's colour and by its tint: %d line(s))", TLogCount(@"deferred")]);
    }
    TSettle();
    TText(w, TWhite(), @"after the next turn: iPadOS's text over the Cover Sheet");
    check(TLogHas(@"the bar's own text colour again") && [w.bar ivarForeground] == nil, @"... the log says our black ended, and the bar's own colour (none) is back");
    gTCover = NO; gTSetColour = NO;   // (the Cover Sheet goes up: our sky behind the bar again; the tint alone this time)
    if (TPass(w.bar, win, @"the Cover Sheet gone (the tint's hook)")) {
        check(gTDarkInPass == 0, @"... inside the pass the state is kept (not black yet)");
        check(TLogCount(@"our black text deferred") == 1, @"... the log says deferred");
    }
    TSettle();
    TText(w, TBlack(), @"after the next turn: our black again");
    // a pass that raises (another cause): it passes through, the count goes back, and our writes go on at once after it
    int deferred = TLogCount(@"deferred");
    gTPassRaises = YES;
    @try { [w.bar updateConstraints]; check(NO, @"the raising pass did not raise"); }
    @catch (NSException *e) { check([e.name isEqual:@"TPassRaises"], @"a constraint pass that raises: its exception passes through"); }
    check(gDMBarConstraintDepth == 0, [NSString stringWithFormat:@"... the count is back to 0 after it (is %d)", gDMBarConstraintDepth]);
    gTCover = YES; TLayout(w);
    TText(w, TWhite(), @"... after it, our layout outside any pass ends our black at once");
    check(TLogCount(@"deferred") == deferred, @"... with nothing deferred");
}
static void SNCPullFull(void) {   // the same pull over a full-screen window (FULLBAR: DMBarWindowText), Settings in full screen beside Clock's window
    gTConstraintPass = YES; gTOurLayout = YES; gTTintHook = YES;
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.3635); TInstall();
    TReplayWorld(1, TKT());
    TStrip clock = TCard(1), settings = TCard(3);
    TFull(settings, YES); gTSMFull = YES; TLayoutAll(); TSettle();
    TTop(TBlack(), 1, @"Settings in full screen beside Clock's window: the screen's bar in Settings' own black");
    gTRestyleDirties = YES; gTPlaceItems = YES; gTSetColour = YES; gTTintPath = YES;
    TPass(gTScreenBar, gTSBWin, @"a pass with nothing changed");
    gTCover = YES;   // (Notification Center pulled down: the Cover Sheet, not Settings, behind the screen's bar)
    if (TPass(gTScreenBar, gTSBWin, @"the pull over the full-screen window"))
        check(TLogCount(@"iPadOS's text for the bar again deferred") == 1 && TLogCount(@"deferred") == 1,
              [NSString stringWithFormat:@"the pull: the log says deferred, once for the copy (%d line(s))", TLogCount(@"deferred")]);
    TSettle();
    TTop(TWhite(), 1, @"after the next turn: iPadOS's text over the Cover Sheet");
    gTCover = NO;   // (the Cover Sheet goes up: Settings behind the bar again)
    if (TPass(gTScreenBar, gTSBWin, @"the Cover Sheet gone"))
        check(TLogCount(@"the full-screen window's text deferred") == 1, @"... the log says deferred");
    TSettle();
    TTop(TBlack(), 1, @"after the next turn: Settings' own black again");
    (void)clock;
}
static void SNCPullClosedUp(void) {   // the way back after a pull: a copy of ours laid out without a clock gets its time label in the bar's own pass
    gTConstraintPass = YES; gTOurLayout = YES;
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    UIWindow *win = TPassWindow(w);
    TLayout(w); TSettle();
    TText(w, TBlack(), @"before: our black over the sky");
    gTCover = YES;   // (the Cover Sheet down: the time label out of its region, our layout without a clock -- the copy closed up --, iPadOS's text)
    gTRegionBack = w.time.superview; [w.time removeFromSuperview];
    objc_setAssociatedObject(w.fg, kBarClosedUpKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    DMApplyBarItemColor(w.fg, DMBarItemColor(w.fg, nil), NO);   // (DMLayoutWithoutClock's colour step)
    TSettle();
    check(!DMBarDarkTextOn(w.fg), @"the Cover Sheet down, the copy closed up: our black ended");
    gTCover = NO;   // (the unlock: the Cover Sheet goes up; the bar's own pass puts the time label back, then DMAttachIfFilled finds the copy closed up)
    gTRestyleDirties = YES; gTPlaceItems = YES; gTReAdd = YES; gTClosedUpPath = YES;
    int again = gTAgainBeforeDraw;
    if (TPass(w.bar, win, @"the time label back in the bar's own pass")) {
        check(gTLayoutsInPass == 0, [NSString stringWithFormat:@"... the copy is not laid out inside the pass (our layout decides the bar's colour: %d layout(s) there)", gTLayoutsInPass]);
        check(TLogCount(@"the layout for its time label deferred") == 1, @"... its layout deferred to the next turn (the log says so)");
        check(gTAgainBeforeDraw == again + 1, [NSString stringWithFormat:@"... and asked once more before the frame is drawn, as before (%d time(s))", gTAgainBeforeDraw - again]);
    }
    TSettle();
    TText(w, TBlack(), @"after the next turn: our black again, with the clock back");
}
static void SNCPullInLayout(void) {   // the copy laid out inside the bar's own pass (by iPadOS's pass or anyone): our layout defers once, no layout without end
    gTConstraintPass = YES; gTOurLayout = YES;
    TSky(); TPrefs(@"auto", @"#FFFFFF", 0.36); TInstall();
    TWorld w = TMake(1, nil);
    UIWindow *win = TPassWindow(w);
    TLayout(w); TSettle();
    TText(w, TBlack(), @"before the pull: our black over the sky");
    gTRestyleDirties = YES; gTPlaceItems = YES; gTLayoutInPass = YES;
    gTCover = YES;
    if (TPass(w.bar, win, @"the pull, the copy laid out inside the pass")) {
        check(gTLayoutsInPass == 1, [NSString stringWithFormat:@"... our layout ran once there (is %d)", gTLayoutsInPass]);
        check(gTDarkInPass == 1 && TLogCount(@"(our black ends) deferred") == 1, @"... it kept the state and deferred, once");
    }
    TSettle();
    TText(w, TWhite(), @"after the next turn: iPadOS's text over the Cover Sheet");
    gTCover = NO;
    if (TPass(w.bar, win, @"the Cover Sheet gone, the copy laid out inside the pass")) check(gTLayoutsInPass == 1, [NSString stringWithFormat:@"... our layout ran once there (is %d)", gTLayoutsInPass]);
    TSettle();
    TText(w, TBlack(), @"after the next turn: our black again");
}
static void SNotHookedUC(void) {   // the bar's -updateConstraints not as read (its type): nothing hooked, no dark text (it needs the pass counted)
    gTBadUC = YES; TSky();   // (over our sky: black text if it were hooked)
    TPrefs(@"on", @"#FFFFFF", 0.36); TInstall();
    gTBadUC = NO;
    TWorld w = TMake(1, nil);
    TLayout(w);
    check(TSame(w.time.textColor, TWhite()) && [w.bar ivarForeground] == nil, @"its constraint pass not as read: not hooked, iPadOS's text, nothing written");
    check(TLogHas(@"has no foreground colour as read") && TLogHas(@"its constraint pass v24@0:8@16"), @"the log says the constraint pass was not as read");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        gLog = [NSMutableArray array];
        NSDictionary<NSString *, void (^)(void)> *all = @{ @"kt": ^{ SKT(); }, @"ktdark": ^{ SKTDark(); }, @"flip": ^{ SFlip(); }, @"default": ^{ SDefault(); },
            @"faint": ^{ SFaint(); }, @"off": ^{ SOff(); }, @"colorbar": ^{ SColorBar(); }, @"theirs": ^{ STheirs(); }, @"lock": ^{ SLock(); },
            @"todark": ^{ SToDark(); }, @"nothooked": ^{ SNotHooked(); }, @"battery": ^{ SBattery(); }, @"rule": ^{ SRule(); },
            @"darkapp": ^{ SDarkApp(); }, @"ccmac": ^{ SCCMac(); }, @"darkpicture": ^{ SDarkPicture(); }, @"behindchanges": ^{ SBehindChanges(); }, @"narrow": ^{ SNarrow(); }, @"tick": ^{ STick(); },
            @"fullbar": ^{ SFullBar(); }, @"fullbarlightwall": ^{ SFullBarLightWall(); }, @"fullbarelse": ^{ SFullBarElse(); }, @"fullbartick": ^{ SFullBarTick(); }, @"newcontents": ^{ SNewContents(); },
            @"fullbartv": ^{ SFullBarTV(); }, @"fullbarheld": ^{ SFullBarHeld(); }, @"fullbarhidden": ^{ SFullBarHidden(); }, @"fullbarbuilding": ^{ SFullBarBuilding(); },
            @"ncpull": ^{ SNCPull(); }, @"ncpullfull": ^{ SNCPullFull(); }, @"ncpullclosedup": ^{ SNCPullClosedUp(); }, @"ncpullinlayout": ^{ SNCPullInLayout(); },
            @"nothookeduc": ^{ SNotHookedUC(); } };
        if (argc < 2 || !strcmp(argv[1], "list")) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); return 0; }
        void (^s)(void) = all[@(argv[1])];
        if (!s) { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
        s();
    }
    return gFails ? 1 : 0;
}
