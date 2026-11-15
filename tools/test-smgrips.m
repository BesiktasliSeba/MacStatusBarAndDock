// test-smgrips.m -- Mac test (Mac Catalyst: UIKit on the Mac) of the Stage Manager engine's resize handles on an open window (1.8.7.5, audit L41
// and L42 of 1.8.7.2). L41: our two corner grips were placed again only when the card's size, its window or its scale changed (DMSMChrome's change
// check), so the layout a settings change asks for (DMSMRefreshBars) left them as they were: Resize Handles switched to Stage Manager's showed
// both sets of handles (or none the other way), Tint Resize Handles, a late app tint or Dark Mode did not reach them, until a resize. Now the
// grips' look (Stage Manager's own handles, the App Switcher, or the colour they get) is compared too, and Dark Mode lays the card out again (the
// title bar's own trait change). L42: the grabber hook recorded every alpha as Apple's wish, our own "hide" too: a grabber Apple had shown, hidden
// for our handles, stayed invisible when Stage Manager's own handles came back. Now our writes are marked (DMSMGrabberAlphaOurs).
// Runs the real DMSMPlaceGrips, DMMakeResizeGrip, DMResizeGripColor, DMSMChrome's change check, DMSMReapplyGrabbers, DMSMGrabberAlphaOurs, the
// SBAppResizeGrabberView hook's -setAlpha: and -layoutSubviews (on a stand-in class of that name: %orig is super's) and the title bar's
// -traitCollectionDidChange:, cut out of statusbar/StatusBar.x by test-smgrips.sh into smg-real.inc, on real UIKit views. The app's tint as
// MacAppBridge reports it (DMResizeGripColorFor) is the stand-in below.
// GRIPS (1.8.7.5, the iPad 2's check of 1.8.7.5~a02): SpringBoard puts its own views of a window card back over ours when it updates the card --
// on iPadOS 16.7.7 the content (the swipe-to-close scroll view with the window's page) at each change of the front window --, and only our title
// bar was raised again: the grips stayed under the window's content, unseen, until a settings change placed them again. The card as 16.7.7 has it
// (read with its view tree on the iPad 2, 15 Nov) is the stand-in KCard16 below; DMSMChrome's last word on the order (the lines between the bar's
// frame and its lights) and DMSMChromeOnTop are cut out too (KOnTop).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#define DM_FEATURE_MARK(name) do { } while (0)
static BOOL gKEngine = YES;
static BOOL DMSMEngine(void) { return gKEngine; }
static BOOL DMNewOS(void) { return NO; }
@interface KCard : UIView
@property (nonatomic) int layoutsAsked;
@end
@implementation KCard
- (void)setNeedsLayout { self.layoutsAsked++; [super setNeedsLayout]; }
@end
static UIView *DMSMCardOfView(UIView *v) { for (UIView *x = v; x; x = x.superview) if ([x isKindOfClass:[KCard class]]) return x; return nil; }
static NSString *DMSMCardBundle(UIView *card) { return @"com.apple.mobilenotes"; }
static UIView *gKPage;
static UIView *DMSMPageViewOf(UIView *card) { return gKPage; }
@interface SBAppResizeGrabberView : UIView
@end
@interface MTLumaDodgePillView : UIView   // (Apple's white arc in the grabber)
@end
@implementation MTLumaDodgePillView
@end
@interface KBar : UIView
@property (nonatomic, weak) UIView *card;
@end
static void DMSMReapplyGrabbers(UIView *card);
static UIColor *DMResizeGripColorFor(NSString *bundleID, BOOL dark);   // (the stand-in below)
static NSMutableArray<NSString *> *gKLog;
static void DMLog(NSString *line) { if (!gKLog) gKLog = [NSMutableArray array]; [gKLog addObject:line]; }
#include "smg-real.inc"
// (the app's tint as MacAppBridge reports it, nil while none has come in; the real one reads notify state -- StatusBar.x DMResizeGripColorFor --
//  with the same rule: Tint Resize Handles off, or no tint, the neutral grip; else the tint held back)
static UIColor *gKAppTint;
static UIColor *DMResizeGripColorFor(NSString *bundleID, BOOL dark) {
    if (!gTintGrips || !bundleID.length || !gKAppTint) return DMResizeGripColor(dark);
    return [gKAppTint colorWithAlphaComponent:(dark ? 0.62 : 0.55)];
}

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

static UIWindow *gWin; static KCard *gCard; static KBar *gBar; static SBAppResizeGrabberView *gG1, *gG2;
static NSString *const kBundle = @"com.apple.mobilenotes";
static void Setup(BOOL appleHandles, BOOL tint, UIColor *appTint) {
    gKEngine = YES; gSMAppleHandles = appleHandles; gTintGrips = tint; gKAppTint = appTint;
    gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1366, 1024)];
    gWin.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    gCard = [[KCard alloc] initWithFrame:CGRectMake(300, 200, 600, 400)]; [gWin addSubview:gCard];
    gKPage = [[UIView alloc] initWithFrame:gCard.bounds]; [gCard addSubview:gKPage];
    gG1 = [[SBAppResizeGrabberView alloc] initWithFrame:CGRectMake(560, 360, 40, 40)]; [gKPage addSubview:gG1];
    gG2 = [[SBAppResizeGrabberView alloc] initWithFrame:CGRectMake(0, 360, 40, 40)]; [gKPage addSubview:gG2];
    for (UIView *g in @[gG1, gG2]) [g addSubview:[[MTLumaDodgePillView alloc] initWithFrame:g.bounds]];
    gBar = [[KBar alloc] initWithFrame:CGRectMake(0, -30, 600, 30)]; gBar.card = gCard; [gCard addSubview:gBar];
}
static UIView *Grip(int side) { return objc_getAssociatedObject(gCard, side == 0 ? &kSMGripLKey : &kSMGripRKey); }
static BOOL GripsShown(void) { return Grip(0) && Grip(1) && !Grip(0).hidden && !Grip(1).hidden; }
static BOOL GripsHidden(void) { return (!Grip(0) || Grip(0).hidden) && (!Grip(1) || Grip(1).hidden); }
static BOOL GripsColour(UIColor *c) { return GripsShown() && [Grip(0).backgroundColor isEqual:c] && [Grip(1).backgroundColor isEqual:c]; }
static void CardLayout(BOOL wasShown, BOOL scaled) { KChangeCheck(gCard, kBundle, wasShown, NO, scaled); [gG1 layoutSubviews]; [gG2 layoutSubviews]; }
static void SettingsChanged(void) { DMSMReapplyGrabbers(gCard); CardLayout(YES, NO); }   // (DMSMRefreshBars: the grabbers put back, every card laid out)
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.001; }
static void Dark(void) {   // (Dark Mode switched: the window's style, the views' traits brought up to date as UIKit does before its next pass)
    gWin.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    for (UIView *v in @[gWin, gCard, gBar]) if ([v respondsToSelector:@selector(updateTraitsIfNeeded)]) [v performSelector:@selector(updateTraitsIfNeeded)];
    [gWin layoutIfNeeded];
}

// ---- GRIPS: iPadOS 16.7.7's window card (SBReusableSnapshotItemContainer, read on the iPad 2): the views added to it go into an inner clipping
// view (_SBFActualClippingView), which takes -bringSubviewToFront: for them too, while the card's own -subviews is that inner view; SpringBoard's
// content (SBFluidSwitcherTouchPassThroughScrollView with the window's SBAppSwitcherPageView, its frame reaching from half a card above the card
// to its bottom) is in the inner view, and SpringBoard brings it to the front when it updates the card (each change of the front window).
@interface KInner : UIView
@property (nonatomic) int raises;
@end
@implementation KInner
- (void)bringSubviewToFront:(UIView *)v { self.raises++; [super bringSubviewToFront:v]; }
@end
@interface KCard16 : KCard
@property (nonatomic, strong) KInner *inner;
@end
@implementation KCard16
- (void)addSubview:(UIView *)v { if (!self.inner || v == self.inner) [super addSubview:v]; else [self.inner addSubview:v]; }
- (void)bringSubviewToFront:(UIView *)v { if (self.inner && v.superview == self.inner) [self.inner bringSubviewToFront:v]; else [super bringSubviewToFront:v]; }
@end
static KCard16 *gCard16; static KInner *gKInner; static UIView *gKContent;   // (SpringBoard's scroll view: a plain view here, UIScrollView needs an application)
static void Setup16(BOOL appleHandles, BOOL tint, UIColor *appTint) {
    gKEngine = YES; gSMAppleHandles = appleHandles; gTintGrips = tint; gKAppTint = appTint;
    gWin = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    gWin.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    gCard16 = [[KCard16 alloc] initWithFrame:CGRectMake(515, 44, 509, 653)]; [gWin addSubview:gCard16];
    gKInner = [[KInner alloc] initWithFrame:gCard16.bounds]; gCard16.inner = gKInner; [gCard16 addSubview:gKInner];
    gKContent = [[UIView alloc] initWithFrame:CGRectMake(0, -326.5, 509, 979.5)]; [gKInner addSubview:gKContent];
    gKPage = [[UIView alloc] initWithFrame:CGRectMake(0, 326.5, 509, 653)]; gKPage.backgroundColor = [UIColor blackColor]; [gKContent addSubview:gKPage];
    gG1 = [[SBAppResizeGrabberView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)]; [gKPage addSubview:gG1];
    gG2 = [[SBAppResizeGrabberView alloc] initWithFrame:CGRectMake(493, 637, 16, 16)]; [gKPage addSubview:gG2];
    gBar = [[KBar alloc] initWithFrame:CGRectMake(0, -24, 509, 24)]; gBar.card = gCard16; [gCard16 addSubview:gBar];   // (DMSMChrome's own add)
    gCard = gCard16;
    [gKLog removeAllObjects];
}
static void Layout16(BOOL wasShown) { KChangeCheck(gCard16, kBundle, wasShown, NO, NO); KOnTop(gCard16, gBar); }   // (DMSMChrome: the change check, then its last word on the order)
static void FrontChange16(void) { [gKInner bringSubviewToFront:gKContent]; Layout16(YES); }   // (SpringBoard's content on top, then the card's layout DMSMRefreshBars asks for)
static void SettingsChanged16(void) { DMSMReapplyGrabbers(gCard16); Layout16(YES); }
static NSUInteger InnerIndex(UIView *v) { return v ? [gKInner.subviews indexOfObjectIdenticalTo:v] : NSNotFound; }
static BOOL GripsOverContent(void) { NSUInteger c = InnerIndex(gKContent); return InnerIndex(Grip(0)) != NSNotFound && InnerIndex(Grip(1)) != NSNotFound && InnerIndex(Grip(0)) > c && InnerIndex(Grip(1)) > c; }
static BOOL BarOverContent(void) { return InnerIndex(gBar) != NSNotFound && InnerIndex(gBar) > InnerIndex(gKContent); }
static BOOL OursLastInOrder(void) { NSArray *s = gKInner.subviews; NSUInteger n = s.count; return n >= 3 && s[n - 3] == gBar && s[n - 2] == Grip(0) && s[n - 1] == Grip(1); }
static UIView *DrawnAt(int side) {   // (the top view of the card's inner view drawn at that grip's centre: the window's content where its page is)
    CGPoint p = Grip(side).center;
    for (UIView *v in gKInner.subviews.reverseObjectEnumerator) {
        if (v.hidden || v.alpha < 0.01) continue;
        if (v == gKContent) { if (CGRectContainsPoint([gKContent convertRect:gKPage.frame toView:gKInner], p)) return v; continue; }
        if (CGRectContainsPoint(v.frame, p)) return v;
    }
    return nil;
}
static NSString *Who(UIView *v) { return v == Grip(0) || v == Grip(1) ? @"our grip" : v == gKContent ? @"the window's content" : v == gBar ? @"the title bar" : v ? NSStringFromClass([v class]) : @"nothing"; }
static BOOL LogHas(NSString *part) { for (NSString *l in gKLog) if ([l containsString:part]) return YES; return NO; }

int main(void) {
    @autoreleasepool {
        UIColor *red = [UIColor colorWithRed:0.9 green:0.2 blue:0.1 alpha:1.0], *blue = [UIColor colorWithRed:0.1 green:0.3 blue:0.9 alpha:1.0];

        // Resize Handles: Mac -> Stage Manager -> Mac on a window laid out (Apple's grabbers never set by Apple: their own alpha 1)
        Setup(NO, NO, nil);
        CardLayout(NO, NO);
        Check(GripsShown() && Near(gG1.alpha, 0) && Near(gG2.alpha, 0), @"Mac: our two corner grips, Stage Manager's grabbers hidden (as before)");
        gSMAppleHandles = YES; SettingsChanged();
        Check(GripsHidden(), @"L41: switched to Stage Manager's: our grips go at once (no resize needed)");
        Check(Near(gG1.alpha, 1) && Near(gG2.alpha, 1), @"L42: ... and Stage Manager's own grabbers come back at Apple's alpha (not our 0)");
        gSMAppleHandles = NO; SettingsChanged();
        Check(GripsShown() && Near(gG1.alpha, 0) && Near(gG2.alpha, 0), @"L41: back to Mac: our grips at once, Apple's hidden");
        [gG1 setAlpha:0.4];   // (Apple's own wish while ours show: it pops a grabber up on a touch)
        Check(Near(gG1.alpha, 0), @"Apple's alpha while ours show: still hidden (as before)");
        gSMAppleHandles = YES; SettingsChanged();
        Check(Near(gG1.alpha, 0.4) && Near(gG2.alpha, 1), @"L42: Stage Manager's again: each grabber as Apple last asked");

        // L42: a grabber Apple showed before Stage Manager was the engine, then hidden for our handles
        Setup(NO, NO, nil);
        gKEngine = NO; [gG1 setAlpha:1.0]; [gG2 setAlpha:1.0];
        gKEngine = YES; CardLayout(NO, NO);
        Check(Near(gG1.alpha, 0) && Near(gG2.alpha, 0), @"the engine on with our handles: Apple's grabbers hidden (as before)");
        gSMAppleHandles = YES; SettingsChanged();
        Check(Near(gG1.alpha, 1) && Near(gG2.alpha, 1), @"L42: switched to Stage Manager's: Apple's grabbers shown as Apple had them");

        // Tint Resize Handles off and on; the app's tint coming in late
        Setup(NO, NO, red);
        CardLayout(NO, NO);
        Check(GripsColour(DMResizeGripColor(NO)), @"Tint Resize Handles off: the neutral grips (as before)");
        gTintGrips = YES; SettingsChanged();
        Check(GripsColour([red colorWithAlphaComponent:0.55]), @"L41: Tint Resize Handles on: the grips take the app's tint at once");
        gTintGrips = NO; SettingsChanged();
        Check(GripsColour(DMResizeGripColor(NO)), @"L41: ... and off again: neutral at once");
        Setup(NO, YES, nil);
        CardLayout(NO, NO);
        Check(GripsColour(DMResizeGripColor(NO)), @"the app's tint not in yet: neutral grips");
        gKAppTint = blue; CardLayout(YES, NO);   // (the card's next layout -- a front-window change, a refresh)
        Check(GripsColour([blue colorWithAlphaComponent:0.55]), @"L41: the app's tint coming in late reaches the grips at the card's next layout");

        // Dark Mode
        Setup(NO, YES, red);
        CardLayout(NO, NO);
        Check(GripsColour([red colorWithAlphaComponent:0.55]), @"light: the grips in the light shade");
        gCard.layoutsAsked = 0;
        UITraitCollection *light = [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
        [gBar traitCollectionDidChange:light];
        Check(gCard.layoutsAsked == 0, @"a trait change that keeps the style: the card is not laid out again for it");
        Dark();
        gCard.layoutsAsked = 0;
        [gBar traitCollectionDidChange:light];   // (UIKit's call for the switch)
        Check(gCard.layoutsAsked >= 1, @"L41: Dark Mode switched: the window card is laid out again");
        CardLayout(YES, NO);
        Check(GripsColour([red colorWithAlphaComponent:0.62]), @"L41: ... and its grips take the dark shade");
        Setup(NO, NO, nil);
        CardLayout(NO, NO);
        Dark(); [gBar traitCollectionDidChange:light]; CardLayout(YES, NO);
        Check(GripsColour(DMResizeGripColor(YES)), @"L41: Dark Mode, untinted: the dark neutral grips");

        // nothing changed: no re-placing on every layout (every frame of a drag); the old reasons still re-place
        Setup(NO, YES, red);
        CardLayout(NO, NO);
        Grip(0).center = CGPointMake(-99, -99);
        for (int i = 0; i < 5; i++) CardLayout(YES, NO);
        Check(Near(Grip(0).center.x, -99), @"unchanged inputs: the grips are not placed again (as before)");
        gCard.bounds = CGRectMake(0, 0, 500, 400); CardLayout(YES, NO);
        Check(!Near(Grip(0).center.x, -99) && Near(Grip(1).center.x, 500 - kSMCornerR), @"a resize: placed again (as before)");
        CardLayout(YES, YES);
        Check(GripsHidden(), @"in the App Switcher (scaled): no grips (as before)");
        CardLayout(YES, NO);
        Check(GripsShown(), @"out of it: the grips again (as before)");

        // GRIPS: the card as iPadOS 16.7.7 has it, SpringBoard's content put back over ours at each change of the front window
        Setup16(NO, YES, red);
        Layout16(NO);
        Check(GripsShown() && GripsOverContent() && BarOverContent(), @"a window opened: its grips and title bar over the window's content (as before)");
        Check(DrawnAt(0) == Grip(0) && DrawnAt(1) == Grip(1), @"... what is drawn at each bottom corner is our grip");
        FrontChange16();
        Check(BarOverContent(), @"a front change: the title bar over the window's content again (as before)");
        Check(GripsShown() && GripsOverContent(), @"GRIPS: a front change: the grips over the window's content again, not left under it");
        Check(DrawnAt(0) == Grip(0) && DrawnAt(1) == Grip(1), [NSString stringWithFormat:@"GRIPS: ... what is drawn at the corners is our grips (is %@, %@)", Who(DrawnAt(0)), Who(DrawnAt(1))]);
        Check(OursLastInOrder(), @"GRIPS: ours are the last of the card's views, in the order the grips were placed in (the bar, then the two grips)");
        Check(LogHas(@"SpringBoard's own views were over its resize grips"), @"GRIPS: the log says SpringBoard's views were over the grips");
        for (int i = 0; i < 3; i++) FrontChange16();
        Check(GripsShown() && GripsOverContent() && DrawnAt(0) == Grip(0), @"GRIPS: three more front changes: the grips over the content each time");
        gKInner.raises = 0; [gKLog removeAllObjects];
        for (int i = 0; i < 5; i++) Layout16(YES);
        Check(gKInner.raises == 0, [NSString stringWithFormat:@"GRIPS: nothing moved at the layouts while ours are on top (every frame of a drag): %d raise(s)", gKInner.raises]);
        Check(gKLog.count == 0, @"GRIPS: ... and nothing logged");
        gCard16.bounds = CGRectMake(0, 0, 400, 653); Layout16(YES);   // (Fill and back: a resize, then the live window over ours after it)
        FrontChange16();
        Check(GripsShown() && GripsOverContent() && Near(Grip(1).center.x, 400 - kSMCornerR), @"GRIPS: a resize, then SpringBoard's content on top: the grips at the new corners, over the content");
        gSMAppleHandles = YES; SettingsChanged16(); FrontChange16(); [gKLog removeAllObjects]; FrontChange16();
        Check(GripsHidden() && BarOverContent(), @"Stage Manager's own handles: no grips of ours, the bar over the content (as before)");
        Check(gKLog.count == 0, @"GRIPS: hidden grips under the content are not logged as covered");
        gSMAppleHandles = NO; SettingsChanged16(); FrontChange16();
        Check(GripsShown() && GripsOverContent(), @"back to Mac, then a front change: the grips over the content");
        // a card that keeps the views added to it itself (the Mac's plain view; iPadOS's other card shapes): the same
        Setup(NO, YES, red);
        UIView *content = [[UIView alloc] initWithFrame:gCard.bounds]; content.backgroundColor = [UIColor blackColor];
        [gCard insertSubview:content atIndex:0];
        CardLayout(NO, NO); KOnTop(gCard, gBar);
        [gCard bringSubviewToFront:content];   // (SpringBoard's content put back on top)
        CardLayout(YES, NO); KOnTop(gCard, gBar);
        NSUInteger ic = [gCard.subviews indexOfObjectIdenticalTo:content];
        Check([gCard.subviews indexOfObjectIdenticalTo:Grip(0)] > ic && [gCard.subviews indexOfObjectIdenticalTo:Grip(1)] > ic && [gCard.subviews indexOfObjectIdenticalTo:gBar] > ic,
              @"GRIPS: a card that keeps its views itself: grips and bar over SpringBoard's content after it came back on top");
    }
    printf("%d checks, %d failed\n", gChecks, gFails);
    return gFails;
}
