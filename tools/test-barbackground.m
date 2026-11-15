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
static UIView *DMTrailingContainer(UIView *fg) { return fg.subviews.firstObject; }
static UIColor *DMTrailingIconColor(UIView *trailing) {   // (iPadOS's status icons: drawn in the bar's colour, as its time is)
    UILabel *time = [trailing.subviews.firstObject isKindOfClass:[UILabel class]] ? trailing.subviews.firstObject : nil;
    return time.textColor;
}
static UIView *DMLeadingContainer(UIView *fg) { return fg.subviews.firstObject; }
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

// The stand-in status bar (iPadOS's: UIKit's _UIStatusBar on 15/16, STUIStatusBar on 17/18 -- not in Mac Catalyst, so the class is made here).
// Its -setForegroundColor: is StatusBar.x's hook (the site check: the hook's body is exactly this call); the bar's own setter restyles when the
// colour changes, as iPadOS's does; a restyle takes UIKit's own style attributes for the bar and gives them to the time label (UIKit's string
// view). iPadOS's own colours with no foreground colour (white for light content, black for dark content) are given by the stand-in: Mac
// Catalyst's UIKit leaves them to the label's traits.
@interface _UIStatusBar : UIView
@property (nonatomic) long long style, mode;
@property (nonatomic) int restyles;
@property (nonatomic, strong) id lastAttrs;
@property (nonatomic, weak) UILabel *time;
- (UIColor *)foregroundColor;
- (void)setForegroundColor:(UIColor *)color;
@end
@implementation _UIStatusBar { UIColor *_fg; }
- (UIColor *)foregroundColor { return _fg; }
- (void)setForegroundColor:(UIColor *)color { [self dm_ownSetForegroundColor:DMBarForegroundFor(self, color)]; }   // (the hook)
- (void)dm_ownSetForegroundColor:(UIColor *)c { if (c == _fg || [c isEqual:_fg]) return; _fg = c; [self restyle]; }
- (void)setStyle:(long long)s { if (s == _style) return; _style = s; [self restyle]; }
- (UIColor *)ivarForeground { return _fg; }
- (void)restyle {
    self.restyles++;
    id a = ((id (*)(id, SEL, id, long long))objc_msgSend)(objc_getClass("_UIStatusBarStyleAttributes"), sel_registerName("styleAttributesForStatusBar:style:"), self, self.style);
    self.lastAttrs = a;
    if ([a valueForKey:@"textColor"]) ((void (*)(id, SEL, id))objc_msgSend)(self.time, sel_registerName("applyStyleAttributes:"), a);
    else self.time.textColor = self.style == 1 ? [UIColor whiteColor] : [UIColor blackColor];
}
@end
@interface TBarNoFg : UIView   // (a bar without a foreground colour as read: the hook is not installed)
@end
@implementation TBarNoFg
@end
static Class DMSBClass(const char *name) { return gTNoFg && !strcmp(name, "_UIStatusBar") ? [TBarNoFg class] : objc_getClass(name); }
@interface TFg : UIView
@property (nonatomic) int layoutsAsked;
@end
@implementation TFg
- (void)setNeedsLayout { self.layoutsAsked++; [super setNeedsLayout]; }
@end

#include "bb-real.inc"        // (StatusBar.x: DMBackgroundWanted, DMApplyBackground, DMLabelDrawnColor, DMBarItemColor, the dark text, DMApplyBarItemColor)
static void TNarrowLayout(UIView *fg) {   // (StatusBar.x -dm_layoutLogoBody: its branch for a copy under 300 pt, as it is)
#include "bb-narrow.inc"
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
static Class TTimeClass(void) {
    static Class c;
    if (!c) {
        c = objc_allocateClassPair(objc_getClass("_UIStatusBarStringView"), "TTimeLabel", 0);
        class_addMethod(c, @selector(setTextColor:), (IMP)TTimeSetTextColor, "v24@0:8@16");
        objc_registerClassPair(c);
    }
    return c;
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

int main(int argc, char **argv) {
    @autoreleasepool {
        gLog = [NSMutableArray array];
        NSDictionary<NSString *, void (^)(void)> *all = @{ @"kt": ^{ SKT(); }, @"ktdark": ^{ SKTDark(); }, @"flip": ^{ SFlip(); }, @"default": ^{ SDefault(); },
            @"faint": ^{ SFaint(); }, @"off": ^{ SOff(); }, @"colorbar": ^{ SColorBar(); }, @"theirs": ^{ STheirs(); }, @"lock": ^{ SLock(); },
            @"todark": ^{ SToDark(); }, @"nothooked": ^{ SNotHooked(); }, @"battery": ^{ SBattery(); }, @"rule": ^{ SRule(); },
            @"darkapp": ^{ SDarkApp(); }, @"ccmac": ^{ SCCMac(); }, @"darkpicture": ^{ SDarkPicture(); }, @"behindchanges": ^{ SBehindChanges(); }, @"narrow": ^{ SNarrow(); }, @"tick": ^{ STick(); } };
        if (argc < 2 || !strcmp(argv[1], "list")) { for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) printf("%s\n", k.UTF8String); return 0; }
        void (^s)(void) = all[@(argv[1])];
        if (!s) { printf("FAIL  no scenario %s\n", argv[1]); return 1; }
        s();
    }
    return gFails ? 1 : 0;
}
