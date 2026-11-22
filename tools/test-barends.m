// test-barends.m: the menu bar's two ends (1.8.8.1; the owner, 21 Nov: in portrait, on the smaller iPads, do the app's menus in the bar meet the right
// side?). The real code of the bar's layout, cut out of statusbar/StatusBar.x by test-barends.sh (region.inc: from the end of the traffic lights to
// the bar items' colour -- the menu titles, the date, the clock, the Spotlight and Control Center icons, the status icons' shift, our Wi-Fi, VPN,
// mute and SSH icons) with the real helpers it calls (DMLayoutTitle, DMAMTitleWidth, DMBattCCLayout, DMWiFiLayoutIcon, DMMuteIcon, DMVPNGlyph,
// DMDateString, DMTimeString, ...), run on the Mac (Mac Catalyst, the real UIKit and fonts) in a bar of each iPad's portrait width and each Menu Bar
// Size. iPadOS's own status icons are views of their real sizes: UIKit's status bar artwork on the Mac (the "Black_" images iPadOS's bar draws: a
// VPN badge read there is ours too, DMVPNGlyph), the Wi-Fi, cellular and battery views' sizes for the iPad's icon size, x the size's icon scale.
// Stand-ins: the app in front, its own menus, the switches, the menus' openers. Usage: t <mode> [dump file]; modes: table (the numbers), check.
// 1.8.8.2 (with F3, the AirPods menu): the right end's two buttons over iPadOS's own items are the real code too (AirPodsMenu.h's
// DMAirPodsLayoutButton, BatteryMenu.h's DMBattLayoutButton: buttons.inc), on iPadOS's bar as they read it (TBar: its regions' display items,
// each with its item and its view; SystemStatusUI's class names, 17 and 18, which the Mac has none of; 15/16's differ only in name): the AirPods item is
// the Bluetooth item's glyph and its headset battery, the battery item its percentage and its glyph. C9: no title's touch area meets one of
// the right end's; C10: the AirPods button over its whole item and the battery's over its own, after the layout, from either date state.
// TB_AP_GLYPH (test-barends.sh sets it where the tree's F3 covers the glyph alone: the 1.8.8.1.1 rework, DMAPBluetoothState): a fifth right
// end, iPadOS's AirPods item as its glyph alone (iPadOS 17/18's AirPods, no level), the first thing of it, the bar's data saying headphones.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreText/CoreText.h>
#include <float.h>
#define DEBUG 0
#include "BarEnds.h"                    // (the tree's, a made-to-fail copy, or empty: before 1.8.8.1 there is none)
#include "../common/MenuBarSize.h"
#include "../common/BatteryMenu.h"
#include "../common/AppMenuRules.h"
#include "../common/AirPodsMenu.h"
#ifndef TB_AP_GLYPH
#define TB_AP_GLYPH 0
#endif
#define kNR (TB_AP_GLYPH ? 5 : 4)   // (the right ends: light, heavy, the most, the AirPods item first; with TB_AP_GLYPH its glyph alone first too)

// ---- stand-ins: SpringBoard's app, our button class, the switches and what the layout asks ----
@interface SBApplication : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier, *displayName;
@end
@implementation SBApplication
@end
@interface DMAXButton : UIButton
@property (nonatomic, copy) NSString *(^axLabel)(void);
@property (nonatomic, copy) NSString *(^axValue)(void);
@end
@implementation DMAXButton
@end
static void DMLog(NSString *s) { (void)s; }
static BOOL DMButtonPointerEffects(void) { return NO; }
static CGFloat gK = 1.0, gBarH = 24.0;
static CGFloat DMBarItemScale(UIView *fg) { return gK; }
static CGFloat DMBarCopyHeight(UIView *fg) { return gBarH; }
static NSString *MSBDAXJoin(NSArray *a) { return [a componentsJoinedByString:@", "]; }
static NSString *MSBDAXWiFiDetails(BOOL a, NSInteger b, NSInteger c) { return @""; }
static BOOL gAMOn = YES, gShowSpotlight = YES, gClockOpensToday = YES, gVPNActive = NO, gSSHActive = NO, gAudioTabShown = NO, gBattMenuOn = YES;
static BOOL gAirPodsMenuOn = YES, gAPSourcesStarted = NO;
static BOOL gWiFiMenuOn = YES, gMuteOn = NO, gDispWanted = NO, gShowSeconds = YES, gMuteIconShown = NO, gCCIconLit = NO;
static NSString *gVPNConfigName = @"";
static CGFloat gStatusIconsLeft = 0;
static unsigned gDMLocaleGen = 0;
static NSLocale *gLocale; static NSDate *gNow;
static NSLocale *TLocale(void) { return gLocale; }
static NSDate *TNow(void) { return gNow; }
typedef enum { DMEngineNone = 0, DMEngineAerial = 1 } DMEngine;
static DMEngine DMActiveEngine(void) { return DMEngineAerial; }   // (windowing on: Window is one of our titles)
static BOOL DMSMEngine(void) { return NO; }
static id DMNativeActiveApp(void) { return nil; }
static BOOL DMFinderNamedInBar(void) { return NO; }
static BOOL DMDispMenuWanted(void) { return gDispWanted; }
static BOOL DMCCPanelWanted(void) { return NO; }
static BOOL DMMuteIconWanted(void) { return gMuteOn; }
static void DMReadRingerState(void) {}
static BOOL DMSSHSessionActive(void) { return NO; }
static BOOL DMWiFiAssociated(void) { return YES; }
static NSInteger DMWiFiBars(void) { return 3; }
static BOOL DMWiFiPowered(void) { return YES; }
static NSString *DMWiFiCurrentName(void) { return @"net"; }
static NSArray<NSString *> *gAppMenus;
static void DMAMFrontSeen(SBApplication *app) {}
static void DMAMFrontSeenOn(SBApplication *app, int display) {}   // (B69, 1.8.8.2: each display's bar asks for its own app; unused before it)
static NSArray<NSString *> *DMAMTitlesToLay(UIView *fg, NSString *bundle) { return bundle.length ? gAppMenus : @[]; }
static void DMOpenAppMenu(UIButton *b) {} static void DMOpenAppOwnMenu(UIButton *b) {} static void DMOpenEditMenu(UIButton *b) {}
static void DMOpenGoMenu(UIButton *b) {} static void DMOpenWindowMenu(UIButton *b) {} static void DMDispMenuOpen(UIButton *b) {}
static void DMOpenAudioMenu(UIButton *b) {} static void DMOpenFinderFileMenu(UIButton *b) {} static void DMOpenFinderViewMenu(UIButton *b) {}
static void DMOpenSpotlight(void) {} static void DMToggleTodayViewFrom(UIButton *b) {} static void DMOpenVPNMenu(UIButton *b) {}
static void DMOpenSSHMenu(UIButton *b) {} static void DMOpenWiFiMenu(UIButton *b) {} static void DMBattOpenControlCenter(UIButton *b) {}
static void DMBattInsideBar(UIView *fg) {}
static void DMBattHoldBar(UIView *fg) {}
static CGFloat DMLALayoutPills(UIView *fg, CGFloat left, CGFloat midY, CGFloat k) { return left; }   // (theirs: never before 12 pt past the middle, MSBDLARoom)
static BOOL DMSBUseSTUI(void) { return YES; }   // (SystemStatusUI's names: the Mac has none of them, so the stand-ins below are the only ones)
static void DMAPCheck(void) {} static void DMAPStartSources(void) {} static void DMOpenAirPodsMenu(UIButton *b) {} static void DMOpenBatteryMenu(UIButton *b) {}
static NSString *DMAPAXValue(void) { return @""; } static NSString *DMBattAXValue(void) { return @""; }
static void DMAMTitleTouchEnded(void) {}   // (F-7b: a title's touch ended: test-appmenushold)
#define KEY(n) static const void *n = &n;
KEY(kAppLabelKey) KEY(kAppButtonKey) KEY(kAppPillKey) KEY(kFileLabelKey) KEY(kFileButtonKey) KEY(kFilePillKey) KEY(kEditLabelKey) KEY(kEditButtonKey)
KEY(kEditPillKey) KEY(kViewLabelKey) KEY(kViewButtonKey) KEY(kViewPillKey) KEY(kGoLabelKey) KEY(kGoButtonKey) KEY(kGoPillKey) KEY(kWinLabelKey)
KEY(kWinButtonKey) KEY(kWinPillKey) KEY(kDispLabelKey) KEY(kDispButtonKey) KEY(kDispPillKey) KEY(kAudioLabelKey) KEY(kAudioButtonKey)
KEY(kAudioPillKey) KEY(kDateProxyKey) KEY(kClockButtonKey) KEY(kSpotIconKey) KEY(kSpotButtonKey) KEY(kSpotLockHidKey) KEY(kShiftedKey)
KEY(kTrailShiftKey) KEY(kClockShiftKey) KEY(kVPNIconKey) KEY(kVPNButtonKey) KEY(kSSHIconKey) KEY(kSSHButtonKey) KEY(kIconsStartKey)
KEY(kIconsRecheckKey) KEY(kIconsBornKey) KEY(kIconsSlowLookKey) KEY(kCCIconKey) KEY(kCCButtonKey) KEY(kCCPillKey) KEY(kWiFiIconKey) KEY(kWiFiButtonKey)
KEY(kMuteIconKey) KEY(kBarDateOffKey) KEY(kAMTitleButtonsKey) KEY(kAirPodsButtonKey) KEY(kBattButtonKey)
static BOOL gDMBarDateTurn = NO;
static char gAMLabelKeys[kMSBDAppMenuSlots], gAMButtonKeys[kMSBDAppMenuSlots], gAMPillKeys[kMSBDAppMenuSlots];
@interface UIView (TBarEnds)
- (void)dm_layoutLogoBody;
@end

// ---- iPadOS's bar as the buttons read it (as test-airpodsmenu.m's stand-in of the 17.6.1 / 18.2 SystemStatusUI decompiles) ----
@interface TStatusItem : NSObject
@end
@implementation TStatusItem
@end
@interface STUIStatusBarBatteryItem : TStatusItem
@end
@implementation STUIStatusBarBatteryItem
@end
@interface STUIStatusBarBluetoothItem : TStatusItem
@end
@implementation STUIStatusBarBluetoothItem
+ (NSString *)batteryDisplayIdentifier { return @"batteryDisplayIdentifier"; }
@end
@interface TDisplayItem : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, strong) id item;
@property (nonatomic, strong) UIView *view;
@end
@implementation TDisplayItem
@end
@interface TRegion : NSObject
@property (nonatomic, copy) NSArray *displayItems;
@end
@implementation TRegion
@end
#if TB_AP_GLYPH
@interface TBTEntry : NSObject   // (the bar's merged data, as F3's DMAPBluetoothState reads it: -currentAggregatedData's -bluetoothEntry's -state)
@property (nonatomic) long long state;
@end
@implementation TBTEntry
@end
@interface TBarData : NSObject
@property (nonatomic, strong) TBTEntry *bluetoothEntry;
@end
@implementation TBarData
@end
#endif
@interface TBar : UIView
@property (nonatomic, strong) NSDictionary *regions;
@end
@implementation TBar
#if TB_AP_GLYPH
- (id)currentAggregatedData {   // (connected headphones, 2, as iPadOS gives them: AirPodsMenu.h MSBD_AP_BT_HEADPHONES)
    TBarData *d = [TBarData new]; d.bluetoothEntry = [TBTEntry new]; d.bluetoothEntry.state = MSBD_AP_BT_HEADPHONES; return d;
}
#endif
@end

// ---- the real code (test-barends.sh cuts it out) ----
#include "consts.inc"
#include "helpers.inc"
#include "appmenus.inc"
#include "batt.inc"
#include "wifi.inc"
#include "late.inc"

// ---- one bar ----
typedef struct {
    double w; int size; int home;      // the bar's width (pt), Menu Bar Size 0 Default 1 Medium 2 Large, a Home-button iPad (a 20 pt bar at Default)
    int right;                         // the right end: 0 light, 1 heavy, 2 the most iPadOS 15-18 shows at once with ours, 3 the AirPods item first, 4 its glyph alone first (TB_AP_GLYPH)
    int left;                          // the titles: 0 Home Screen (Finder, Edit, Go, Window), 1 an app with 4 menus, 2 a full-screen app, its 7 menus, Display, Audio
    int rtl, region, startOff;         // right to left; an item in iPadOS's other region in the right half; the copy starting with its date given up
    const char *locale;                // the date's and time's language and region
} TScene;
typedef struct { double rightLead, titlesEnd, leftEnd, half, dateW, room, timeLead, timeSlack; int dateShown, titles, oursCut, amShown; char names[400];
                 double titleBtnEnd, rightBtnLead; const char *rightBtn;                      // (C9: the titles' touch areas' end, the right end's first touch area and whose)
                 int apItem, apBtn, apCovers, battBtn, battCovers, apOverBatt; double apA, apB, itemA, itemB; } TResult;   // (C10: the two buttons over their items)
static TScene gS;
static double gLeftEnd;   // (where the left end stops without titles: the logo, or the traffic lights)
static UIView *gTrailing, *gContainer, *gTimeLabel, *gRegion;
static UIView *gAPGlyph, *gAPBatt, *gBattPct, *gBattBody;   // (iPadOS's AirPods item, its glyph and headset battery; the battery item's two views)
static TBar *gBar;
static UIView *DMTrailingContainer(UIView *fg) { return gTrailing; }
#include "buttons.inc"

static UIImage *TArt(NSString *n) { return ((id (*)(id, SEL, id))objc_msgSend)([UIImage class], NSSelectorFromString(@"kitImageNamed:"), [@"Black_" stringByAppendingString:n]); }
static CGSize TStatusSize(const char *cls, const char *sel, long bars) {   // (UIKit's status bar views' sizes for the iPad's icon size, 14)
    Class c = objc_getClass(cls); SEL s = sel_registerName(sel);
    if (!c || ![c respondsToSelector:s]) return CGSizeZero;
    if (bars) return ((CGSize (*)(id, SEL, long, long))objc_msgSend)(c, s, bars, 14);
    return ((CGSize (*)(id, SEL, long))objc_msgSend)(c, s, 14);
}
static UIFont *TBarFont(void) { return [UIFont systemFontOfSize:12.0 * gK weight:UIFontWeightMedium]; }
static UIView *TItem(double w, double h) { UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)]; return v; }
static UIView *TText(NSString *s) { UILabel *l = [UILabel new]; l.font = TBarFont(); l.text = s; [l sizeToFit]; return l; }
static UIView *TArtItem(NSString *n) { UIImage *i = TArt(n); return TItem(i ? i.size.width * gK : 12.0 * gK, i ? i.size.height * gK : 10.0 * gK); }
// iPadOS's status icons, leading to trailing, as its trailing region holds them (the stock Wi-Fi item is ours while Wi-Fi Menu is on: hidden).
// The AirPods item (iPadOS's Bluetooth item while it shows a headset's battery: F3's AirPods button goes over it) is two views, its glyph and the
// headset battery (10 x 5 pt x k, as test-airpodsmenu's world), right before the battery item's percentage and glyph. Level 3: the AirPods item is
// the first thing of the right end (Wi-Fi off with Wi-Fi Menu off, none of ours): its button is the right end's first touch area.
static UIView *TAirPods(NSMutableArray *a) { gAPGlyph = TArtItem(@"BTHeadphones"); [a addObject:gAPGlyph]; gAPBatt = TItem(10.0 * gK, 5.0 * gK); [a addObject:gAPBatt]; return gAPGlyph; }
static NSArray<UIView *> *TStatusIcons(int level) {
    NSMutableArray *a = [NSMutableArray array];
    CGSize batt = TStatusSize("_UIStatusBarBatteryView", "_batterySizeForIconSize:", 0), cell = TStatusSize("_UIStatusBarCellularSignalView", "_intrinsicContentSizeForNumberOfBars:iconSize:", 4);
    gAPGlyph = gAPBatt = nil;
    if (level == 2) {
        [a addObject:TArtItem(@"Location")]; [a addObject:TArtItem(@"Alarm")]; [a addObject:TItem(15.0 * gK, 10.0 * gK)];   // (a Focus glyph: Sleep's bed, wider than Do Not Disturb's moon)
        [a addObject:TArtItem(@"RotationLock")]; [a addObject:TArtItem(@"AirPlay")]; TAirPods(a); [a addObject:TArtItem(@"DataTypeiOSHotspot")];
        [a addObject:TText(@"Carrier Name")]; [a addObject:TItem(cell.width * gK, cell.height * gK)]; [a addObject:TText(@"5G")];
    } else if (level == 1) {
        [a addObject:TArtItem(@"Location")]; [a addObject:TArtItem(@"Alarm")]; [a addObject:TArtItem(@"QuietMode")]; [a addObject:TArtItem(@"RotationLock")]; TAirPods(a);
    } else if (level == 3) TAirPods(a);
    else if (level == 4) { gAPGlyph = TArtItem(@"BTHeadphones"); [a addObject:gAPGlyph]; }   // (the glyph alone, no headset battery: the bar's data says headphones, TBar)
    gBattPct = TText(@"100%"); [a addObject:gBattPct];
    gBattBody = TItem((batt.width + 2.5) * gK, batt.height * gK); [a addObject:gBattBody];   // (the body and its pin: 26.5 x 12 at Default, MenuBarSize.h)
    if (level == 2) [a addObject:TItem(6.0 * gK, 6.0 * gK)];   // (the camera / microphone dot)
    return a;
}
static TDisplayItem *TDI(NSString *ident, id item, UIView *v) { TDisplayItem *d = [TDisplayItem new]; d.identifier = ident; d.item = item; d.view = v; return d; }
static void TSetLocale(const char *l) { gLocale = [NSLocale localeWithLocaleIdentifier:@(l)]; gDMLocaleGen++; }

static UIView *TBuild(void) {
    gK = MSBDMenuBarSizeScale(gS.size);
    gBarH = gS.size ? MSBDMenuBarSizeHeight(gS.size, 0) : (gS.home ? 20.0 : 24.0);
    gVPNActive = gS.right == 2; gSSHActive = gS.right == 2; gMuteOn = gS.right == 1 || gS.right == 2; gWiFiMenuOn = gS.right < 3;
    gDispWanted = gS.left >= 2; gAudioTabShown = gS.left >= 2;
    gAppMenus = gS.left >= 2 ? @[@"File", @"View", @"Insert", @"Format", @"Arrange", @"Bookmarks", @"Help"] : gS.left == 1 ? @[@"File", @"View", @"History", @"Bookmarks"] : @[];
    TSetLocale(gS.locale);
    double inset = gS.home ? 12.0 : 20.0;   // (the bar's own edge room, either end)
    gBar = [[TBar alloc] initWithFrame:CGRectMake(0, 0, gS.w, gBarH)];   // (the status bar; the copy, fg, its foreground view)
    UIView *fg = [[UIView alloc] initWithFrame:gBar.bounds]; [gBar addSubview:fg];
    if (gS.rtl) gBar.semanticContentAttribute = fg.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    BOOL rtl = gS.rtl;
    // iPadOS's leading region: the time (its date label hidden: ours is drawn); its trailing region: the status icons, right-aligned, 6 pt apart
    gContainer = [[UIView alloc] initWithFrame:DMBarRect(fg, rtl, CGRectMake(inset, 0, gS.w / 2.0 - inset, gBarH))];
    gContainer.semanticContentAttribute = fg.semanticContentAttribute;
    UILabel *time = [UILabel new]; time.font = DMTabularFont(TBarFont()); time.text = DMTimeString(); [time sizeToFit];
    time.frame = DMBarRect(gContainer, rtl, CGRectMake(0, (gBarH - time.bounds.size.height) / 2.0, time.bounds.size.width, time.bounds.size.height));
    [gContainer addSubview:time]; gTimeLabel = time;
    if (gS.right == 2) {   // (screen recording: a red pill around the time, in the time's region -- the clock keeps the icons clear of it)
        UIView *pill = [[UIView alloc] initWithFrame:CGRectInset(time.frame, -6.0 * gK, 0)]; [gContainer addSubview:pill];
    }
    [fg addSubview:gContainer];
    gTrailing = [[UIView alloc] initWithFrame:DMBarRect(fg, rtl, CGRectMake(gS.w / 2.0, 0, gS.w / 2.0 - inset, gBarH))];
    NSArray<UIView *> *icons = TStatusIcons(gS.right);
    double x = gTrailing.bounds.size.width;
    for (UIView *v in [icons reverseObjectEnumerator]) {
        x -= v.bounds.size.width;
        v.frame = DMBarRect(gTrailing, rtl, CGRectMake(x, (gBarH - v.bounds.size.height) / 2.0, v.bounds.size.width, v.bounds.size.height));
        [gTrailing addSubview:v];
        x -= 6.0;
    }
    [fg addSubview:gTrailing];
    NSMutableArray *dis = [NSMutableArray array];   // (the trailing region's display items: the AirPods item's two, the battery's two, a plain item each other icon)
    STUIStatusBarBluetoothItem *bt = [STUIStatusBarBluetoothItem new]; STUIStatusBarBatteryItem *bi = [STUIStatusBarBatteryItem new];
    for (UIView *v in icons) {
        if (v == gAPGlyph) [dis addObject:TDI(@"defaultDisplayIdentifier", bt, v)];
        else if (v == gAPBatt) [dis addObject:TDI(@"batteryDisplayIdentifier", bt, v)];
        else if (v == gBattPct) [dis addObject:TDI(@"percentDisplayIdentifier", bi, v)];
        else if (v == gBattBody) [dis addObject:TDI(@"iconDisplayIdentifier", bi, v)];
        else [dis addObject:TDI(@"item", [TStatusItem new], v)];
    }
    TRegion *trailRegion = [TRegion new]; trailRegion.displayItems = dis;
    TRegion *otherRegion = [TRegion new]; otherRegion.displayItems = @[];
    gRegion = nil;
    if (gS.region) {   // (iPadOS's other region: a temporary item placed by iPadOS itself, 2 pt right of the bar's middle; ours never move it)
        UIView *reg = [[UIView alloc] initWithFrame:fg.bounds]; reg.userInteractionEnabled = NO;
        UIView *item = TItem(40.0 * gK, 12.0 * gK); item.frame = DMBarRect(fg, rtl, CGRectMake(gS.w / 2.0 + 2.0, (gBarH - 12.0 * gK) / 2.0, 40.0 * gK, 12.0 * gK));
        [reg addSubview:item]; [fg addSubview:reg]; gRegion = item;
        otherRegion.displayItems = @[TDI(@"item", [TStatusItem new], item)];
    }
    gBar.regions = @{ @"trailing": trailRegion, @"other": otherRegion };
    if (gS.startOff) objc_setAssociatedObject(fg, kBarDateOffKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return fg;
}

@implementation UIView (TBarEnds)
- (void)dm_layoutLogoBody {
    UIView *fg = self;
    BOOL rtl = DMBarRTL(fg);
    UIView *container = gContainer, *trailing = gTrailing, *timeLabel = gTimeLabel, *dateLabel = nil;
    UIFont *timeFont = TBarFont(), *tabular = DMTabularFont(timeFont);
    ((UILabel *)timeLabel).font = tabular; ((UILabel *)timeLabel).text = DMTimeString();
    CGFloat k = gK, barH = gBarH;
    CGFloat baseLeft = DMBarLead(fg, rtl, DMBarUntransformed(container));
    CGPoint timeCentre = [timeLabel.superview convertPoint:timeLabel.center toView:fg];
    BOOL locked = NO, lookWasLocked = NO;
    // (the logo as the layout sizes it, MenuBarSize.h; the traffic lights while an app is full screen)
    CGRect ink100; CGFloat logoSize = timeFont.pointSize + 3.5;
    if (DMLogoInkAt100(&ink100)) logoSize = MSBDMenuBarLogoInk(gS.size, barH, timeFont.pointSize) / (ink100.size.height / 100.0);
    UILabel *logo = [UILabel new]; logo.text = [NSString stringWithFormat:@"%C", (unichar)0xF8FF]; logo.font = [UIFont systemFontOfSize:logoSize weight:UIFontWeightSemibold]; [logo sizeToFit];
    CGRect lf = CGRectMake(baseLeft, 0, logo.bounds.size.width, logo.bounds.size.height);
    BOOL wantLights = gS.left >= 2;
    CGRect lightsL = CGRectZero;
    CGFloat titlesStart = CGRectGetMaxX(lf) + kAppGap * k;
    if (wantLights) { lightsL = CGRectMake(CGRectGetMaxX(lf) + (kAppGap - 4.0) * k, 0, 20.0 * k * 3.0, barH); titlesStart = CGRectGetMaxX(lightsL) + (kAppGap - 4.0) * k; }
    gLeftEnd = wantLights ? CGRectGetMaxX(lightsL) - 4.0 * k : CGRectGetMaxX(lf);
    SBApplication *frontApp = nil;
    if (gS.left) { frontApp = [SBApplication new]; frontApp.bundleIdentifier = @"com.example.app"; frontApp.displayName = gS.left >= 2 ? @"Microsoft PowerPoint" : @"Safari"; }
    NSString *appName = frontApp ? frontApp.displayName : @"Finder";
    UIScreen *barTV = nil;   // (B69, 1.8.8.2: the bar's TV, none: the iPad's own bar; unused before it)
#include "region.inc"
}
@end

// ---- what was laid out, in leading coordinates ----
static CGFloat TLead(UIView *fg, UIView *v) { CGRect r = [v.superview convertRect:v.frame toView:fg]; return DMBarLead(fg, DMBarRTL(fg), r); }
static CGFloat TTrail(UIView *fg, UIView *v) { CGRect r = [v.superview convertRect:v.frame toView:fg]; return DMBarTrail(fg, DMBarRTL(fg), r); }
static BOOL TShown(UIView *v) { return v && !v.hidden && v.alpha > 0.01 && v.bounds.size.width >= 1.0; }
static TResult TMeasure(UIView *fg) {
    TResult r; memset(&r, 0, sizeof r);
    r.rightLead = DBL_MAX; r.titlesEnd = 0; r.half = gS.w / 2.0 - 24.0;
    const void *titleKeys[] = { kAppLabelKey, kFileLabelKey, kEditLabelKey, kViewLabelKey, &gAMLabelKeys[0], &gAMLabelKeys[1], &gAMLabelKeys[2], &gAMLabelKeys[3],
                                &gAMLabelKeys[4], &gAMLabelKeys[5], &gAMLabelKeys[6], kGoLabelKey, kWinLabelKey, kDispLabelKey, kAudioLabelKey };
    NSMutableArray<UILabel *> *shown = [NSMutableArray array];
    for (unsigned i = 0; i < sizeof titleKeys / sizeof titleKeys[0]; i++) {
        UILabel *l = objc_getAssociatedObject(fg, titleKeys[i]);
        if (!TShown(l)) continue;
        r.titles++; r.titlesEnd = MAX(r.titlesEnd, TTrail(fg, l));
        [shown addObject:l];
    }
    [shown sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) { return TLead(fg, a) < TLead(fg, b) ? NSOrderedAscending : NSOrderedDescending; }];
    NSMutableArray *names = [NSMutableArray array];
    for (UILabel *l in shown) {
        CGFloat natural = ceil([l.text sizeWithAttributes:@{NSFontAttributeName: l.font}].width);
        [names addObject:[NSString stringWithFormat:@"%@%@", l.text, l.bounds.size.width + 0.5 < natural ? @"~" : @""]];   // (~: cut short)
    }
    for (unsigned i = 0; i < kMSBDAppMenuSlots; i++) if (TShown(objc_getAssociatedObject(fg, &gAMLabelKeys[i]))) r.amShown++;
    const void *ours[] = { kGoLabelKey, kWinLabelKey, kDispLabelKey, kAudioLabelKey };
    BOOL oursWanted[] = { YES, YES, gDispWanted, gAudioTabShown };
    for (int i = 0; i < 4 && gS.left; i++) {
        if (!oursWanted[i]) continue;
        UILabel *l = objc_getAssociatedObject(fg, ours[i]);
        CGFloat natural = l.text ? ceil([l.text sizeWithAttributes:@{NSFontAttributeName: l.font ?: TBarFont()}].width) : 1e9;
        if (!TShown(l) || l.bounds.size.width + 0.5 < natural) r.oursCut = 1;
    }
    snprintf(r.names, sizeof r.names, "%s", [[names componentsJoinedByString:@","] UTF8String]);
    if (r.titles == 0) r.titlesEnd = 0;
    r.leftEnd = r.titles ? r.titlesEnd : gLeftEnd;
    // the right end: every item of it that shows (ours and iPadOS's), the Live Activities' pills apart
    NSMutableArray<UIView *> *right = [NSMutableArray array];
    const void *rk[] = { kDateProxyKey, kSpotIconKey, kCCIconKey, kWiFiIconKey, kVPNIconKey, kMuteIconKey, kSSHIconKey };
    for (int i = 0; i < 7; i++) { UIView *v = objc_getAssociatedObject(fg, rk[i]); if (TShown(v)) [right addObject:v]; }
    [right addObject:gTimeLabel];
    for (UIView *v in gTrailing.subviews) if (TShown(v)) [right addObject:v];
    for (UIView *v in gContainer.subviews) if (TShown(v)) [right addObject:v];
    if (gRegion) [right addObject:gRegion];
    for (UIView *v in right) r.rightLead = MIN(r.rightLead, TLead(fg, v));
    UILabel *date = objc_getAssociatedObject(fg, kDateProxyKey);
    r.dateShown = TShown(date);
    r.dateW = date ? date.bounds.size.width : 0;
    // the touch areas (C9): every title's button, every button of the right end (ours and the two over iPadOS's items)
    const void *titleBtns[] = { kAppButtonKey, kFileButtonKey, kEditButtonKey, kViewButtonKey, &gAMButtonKeys[0], &gAMButtonKeys[1], &gAMButtonKeys[2], &gAMButtonKeys[3],
                                &gAMButtonKeys[4], &gAMButtonKeys[5], &gAMButtonKeys[6], kGoButtonKey, kWinButtonKey, kDispButtonKey, kAudioButtonKey };
    r.titleBtnEnd = -DBL_MAX;
    for (unsigned i = 0; i < sizeof titleBtns / sizeof titleBtns[0]; i++) { UIView *b = objc_getAssociatedObject(fg, titleBtns[i]); if (TShown(b)) r.titleBtnEnd = MAX(r.titleBtnEnd, TTrail(fg, b)); }
    const void *rightBtns[] = { kAirPodsButtonKey, kBattButtonKey, kWiFiButtonKey, kVPNButtonKey, kSSHButtonKey, kSpotButtonKey, kCCButtonKey, kClockButtonKey };
    const char *rightNames[] = { "AirPods", "battery", "Wi-Fi", "VPN", "SSH", "Spotlight", "Control Center", "clock" };
    r.rightBtnLead = DBL_MAX; r.rightBtn = "none";
    for (int i = 0; i < 8; i++) { UIView *b = objc_getAssociatedObject(fg, rightBtns[i]); if (TShown(b) && TLead(fg, b) < r.rightBtnLead) { r.rightBtnLead = TLead(fg, b); r.rightBtn = rightNames[i]; } }
    // the AirPods button and the battery's over their items (C10), in leading coordinates
    UIView *ap = objc_getAssociatedObject(fg, kAirPodsButtonKey), *bb = objc_getAssociatedObject(fg, kBattButtonKey);
    r.apItem = gAPGlyph != nil; r.apBtn = TShown(ap); r.battBtn = TShown(bb);
    if (r.apItem) { r.itemA = TLead(fg, gAPGlyph); r.itemB = TTrail(fg, gAPGlyph); }
    if (r.apItem && gAPBatt) { r.itemA = MIN(r.itemA, TLead(fg, gAPBatt)); r.itemB = MAX(r.itemB, TTrail(fg, gAPBatt)); }
    if (r.apBtn) { r.apA = TLead(fg, ap); r.apB = TTrail(fg, ap); }
    r.apCovers = r.apItem && r.apBtn && r.apA <= r.itemA + 1e-6 && r.apB >= r.itemB - 1e-6;
    r.battCovers = r.battBtn && TLead(fg, bb) <= MIN(TLead(fg, gBattPct), TLead(fg, gBattBody)) + 1e-6 && TTrail(fg, bb) >= MAX(TTrail(fg, gBattPct), TTrail(fg, gBattBody)) - 1e-6;
    r.apOverBatt = r.apBtn && r.battBtn && r.apB > TLead(fg, bb) + 1e-6 && r.apA < TTrail(fg, bb) - 1e-6;
    // (the time label's place, and how much wider than the label its slot is: the text's width rounded up, BarUnlock.h MSBDTimeLabelWidth)
    UILabel *tl = (UILabel *)gTimeLabel;
    r.timeLead = TLead(fg, tl);
    r.timeSlack = MSBDTimeLabelWidth(tl.bounds.size.width, ceil([tl sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)].width)) - tl.bounds.size.width;
    return r;
}
// every frame of ours and the status icons' places, for the before / after comparison and right to left (maskTime: the time label's width only,
// its place apart: C6)
static NSString *TFramesM(UIView *fg, BOOL maskTime) {
    NSMutableArray *rows = [NSMutableArray array], *views = [NSMutableArray array];
    for (UIView *v in fg.subviews) if (v != gContainer && v != gTrailing && (!gRegion || v != gRegion.superview)) [views addObject:v];
    [views addObjectsFromArray:gTrailing.subviews]; [views addObjectsFromArray:gContainer.subviews];
    for (UIView *v in views) {
        if (!TShown(v)) continue;
        NSString *what = [v isKindOfClass:[UILabel class]] ? ((UILabel *)v).text : NSStringFromClass([v class]);
        if (maskTime && v == gTimeLabel) [rows addObject:[NSString stringWithFormat:@"%@@T+%.2f", what, TTrail(fg, v) - TLead(fg, v)]];
        else [rows addObject:[NSString stringWithFormat:@"%@@%.2f+%.2f", what, TLead(fg, v), TTrail(fg, v) - TLead(fg, v)]];
    }
    [rows sortUsingSelector:@selector(compare:)];
    return [rows componentsJoinedByString:@" "];
}
static NSString *TFrames(UIView *fg) { return TFramesM(fg, NO); }

// (portrait: 744 the mini, 768 Air 2 / 9.7", 810 9th gen, 820 Air / 10th gen, 834 11" / 10.5", 1024 12.9"; landscape: 1133, 1180, 1194, 1366; a TV: 1920)
static const double kWidths[] = { 744, 768, 810, 820, 834, 1024, 1133, 1180, 1194, 1366, 1920 };
#define kNW 11
#define kNPortrait 6
static int TRun(TScene s, TResult *out, NSString **frames, NSString **masked, int layouts) {
    gS = s;
    UIView *fg = TBuild();
    for (int i = 0; i < layouts; i++) [fg dm_layoutLogoBody];
    *out = TMeasure(fg);
    if (frames) *frames = TFrames(fg);
    if (masked) *masked = TFramesM(fg, YES);
    return 0;
}
static int gFails = 0, gTight = 0, gBand = 0, gAPBars = 0, gAPGlyphBars = 0;
static double gTightGap = 1e9; static NSString *gTightAt;
static void TCheck(BOOL ok, NSString *what) {   // (TB_FIRST: stop at the first failure -- the made-to-fail copies)
    if (ok) return;
    gFails++; if (gFails <= 40) printf("FAIL  %s\n", what.UTF8String);
    if (getenv("TB_FIRST")) { fflush(stdout); exit(1); }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *mode = argc > 1 ? argv[1] : "check";
        FILE *dump = argc > 2 ? fopen(argv[2], "w") : NULL;
        // the time: 10:58:58 PM (two hour digits, seconds on), a Wednesday in November (the widest English date of the year: below)
        NSDateComponents *c = [NSDateComponents new]; c.year = 2026; c.month = 11; c.day = 25; c.hour = 22; c.minute = 58; c.second = 58;
        gNow = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:c];
        if (!strcmp(mode, "dates")) {   // the widest date the bar's own format gives over a year, per language and region (at Default's 12 pt)
            gK = 1.0; UIFont *f = DMTabularFont(TBarFont());
            NSDate *keep = gNow; double best = 0; NSString *bestL = nil, *bestS = nil, *en = nil; double enW = 0;
            for (NSString *lid in [NSLocale availableLocaleIdentifiers]) {
                TSetLocale(lid.UTF8String);
                for (int d = 0; d < 366; d += 1) {
                    gNow = [keep dateByAddingTimeInterval:86400.0 * d];
                    NSString *t = DMDateString(); double w = [t sizeWithAttributes:@{NSFontAttributeName: f}].width;
                    if (w > best) { best = w; bestL = lid; bestS = t; }
                    if ([lid isEqualToString:@"en_US"] && w > enW) { enW = w; en = t; }
                }
            }
            gNow = keep;
            printf("widest date: %s \"%s\" %.1f pt; en_US \"%s\" %.1f pt\n", bestL.UTF8String, bestS.UTF8String, best, en.UTF8String, enW);
            return 0;
        }
        // (the clock's language: English (US) for the light and heavy right ends; for the most, Chinese (Taiwan), whose date and 12-hour time with
        //  seconds are the widest of iPadOS's own languages together, 163 pt at Default: "10\u670810\u65e5 \u9031\u65e5" and "\u4e0a\u534810:58:58")
        const char *locs[] = { "en_US", "en_US", "zh_TW", "en_US", "en_US" };
        int fails0 = 0;
        for (int size = 0; size < 3; size++) for (int wi = 0; wi < kNW; wi++) for (int right = 0; right < kNR; right++) for (int left = 0; left < 3; left++)
        for (int home = 0; home < 2; home++) for (int rtl = 0; rtl < 2; rtl++) for (int region = 0; region < 2; region++) for (int startOff = 0; startOff < 2; startOff++) {
            TScene s = { kWidths[wi], size, home, right, left, rtl, region, startOff, locs[right] };
            TResult r; NSString *fr = nil; TRun(s, &r, &fr, NULL, 1);
            double k = MSBDMenuBarSizeScale(size), gap = r.titles ? r.rightLead - r.titlesEnd : r.rightLead;
            NSString *tag = [NSString stringWithFormat:@"w %.0f size %d home %d right %d left %d rtl %d region %d from %s", s.w, size, home, right, left, rtl, region, startOff ? "off" : "on"];
            if (dump) fprintf(dump, "%s | lead %.2f titles %.2f gap %.2f date %d n %d dw %.2f [%s] | %s\n", tag.UTF8String, r.rightLead, r.titlesEnd, gap, r.dateShown, r.titles, r.dateW, r.names, fr.UTF8String);
            if (!strcmp(mode, "table")) {
                if (wi >= kNPortrait) { if (!rtl && !region && !startOff && !home && right == 2 && left == 2) printf("%-5.0f %-7s (landscape or a TV) most / full: right end from %7.1f, titles to %7.1f: gap %7.1f pt  date %s\n", s.w, size == 0 ? "Default" : size == 1 ? "Medium" : "Large", r.rightLead, r.titlesEnd, gap, r.dateShown ? "shown" : "GONE"); continue; }
                if (!rtl && !region && !startOff && (home ? (s.w == 768 || s.w == 810 || s.w == 834 || s.w == 1024) : (s.w == 744 || s.w == 820 || s.w == 834 || s.w == 1024)))
                    printf("%-5.0f %-7s %-6s %-5s right end from %7.1f, titles to %7.1f (half %6.1f): gap %7.1f pt  date %s  titles %s\n", s.w, size == 0 ? "Default" : size == 1 ? "Medium" : "Large",
                           right == 0 ? "light" : right == 1 ? "heavy" : right == 2 ? "most" : right == 3 ? "airpods" : "glyph", left == 0 ? "home" : left == 1 ? "app" : "full", r.rightLead, r.titlesEnd, r.half, gap, r.dateShown ? "shown" : "GONE", r.names);
                continue;
            }
            // C1: the two ends never meet: a title gap (16 pt x the size's scale; half a point of the date's slack) between the last title and the right end
            TCheck(!r.titles || gap >= 16.0 * k - 0.5 - 1e-6, [NSString stringWithFormat:@"C1 the titles reach the right end: %@ (titles to %.1f, right end from %.1f, gap %.1f)", tag, r.titlesEnd, r.rightLead, gap]);
            // C2: the left half, as before (D62)
            TCheck(r.titlesEnd <= r.half + 1e-6, [NSString stringWithFormat:@"C2 past the left half: %@ (%.1f > %.1f)", tag, r.titlesEnd, r.half]);
            // C4: the date goes only when the titles need its room (with it, they would reach the right end), and the time stays
            if (!r.dateShown && !region) TCheck(r.leftEnd + 16.0 * k > (r.rightLead - r.dateW - 10.0 * k) - 0.5 - 1e-6,
                                                [NSString stringWithFormat:@"C4 the date gone with room for it: %@ (titles or the logo / lights to %.1f, with the date the right end from %.1f)", tag, r.leftEnd, r.rightLead - r.dateW - 10.0 * k]);
            // (nothing of the left end left to give way -- no title, the date gone -- and the right end still within a title gap of the logo or the
            //  lights: the right end alone wider than the bar leaves; not this rule's to solve, counted and shown)
            if (!r.titles && !region && r.rightLead - r.leftEnd < 16.0 * k - 0.5) { gTight++; if (r.rightLead - r.leftEnd < gTightGap) { gTightGap = r.rightLead - r.leftEnd; gTightAt = tag; } }
            TCheck(TShown(gTimeLabel), [NSString stringWithFormat:@"C4 the time gone: %@", tag]);
            // C5: ours go last: one of ours cut or left out, then none of the app's own menus
            TCheck(!r.oursCut || r.amShown == 0, [NSString stringWithFormat:@"C5 one of ours cut while %d of the app's own show: %@ [%s]", r.amShown, tag, r.names]);
            // C9: no title's touch area meets one of the right end's (a title's button ends 8 pt x k past it; the AirPods and battery buttons start at
            //  most 2 pt x k before iPadOS's icons, ours 6 pt x k before theirs, the clock 4 pt x k: the title gap leaves room between any two)
            TCheck(!r.titles || r.titleBtnEnd <= r.rightBtnLead + 1e-6, [NSString stringWithFormat:@"C9 a title's touch area meets the %s button's: %@ (the titles' buttons to %.1f, the %s button from %.1f)", r.rightBtn, tag, r.titleBtnEnd, r.rightBtn, r.rightBtnLead]);
            // C10: the AirPods button over its whole item (F3) and the battery's over its own, after the layout from either date state (a date's turn
            //  moves the status icons: the buttons with them), the AirPods button never over the battery's; no AirPods button without the item
            TCheck(r.apItem ? r.apCovers : !r.apBtn, [NSString stringWithFormat:@"C10 the AirPods button not over its item: %@ (button %s%.1f..%.1f, item %.1f..%.1f)", tag, r.apBtn ? "" : "hidden ", r.apA, r.apB, r.itemA, r.itemB]);
            TCheck(r.battCovers && !r.apOverBatt, [NSString stringWithFormat:@"C10 the battery's button not over its item, or under the AirPods button: %@", tag]);
            if (r.apItem) gAPBars++;
            if (r.apItem && !gAPBatt) gAPGlyphBars++;
            // C7: a second layout changes nothing (the date does not switch back and forth)
            {
                UIView *fg = TBuild(); [fg dm_layoutLogoBody]; NSString *f1 = TFrames(fg); [fg dm_layoutLogoBody]; NSString *f2 = TFrames(fg);
                TCheck([f1 isEqualToString:f2], [NSString stringWithFormat:@"C7 a second layout moved something: %@", tag]);
            }
            fails0++;
        }
        if (!strcmp(mode, "table")) return 0;
        // C6: right to left, every frame mirrored; C8: from either date state the same bar after one layout
        for (int size = 0; size < 3; size++) for (int wi = 0; wi < kNW; wi++) for (int right = 0; right < kNR; right++) for (int left = 0; left < 3; left++) for (int home = 0; home < 2; home++) {
            TScene a = { kWidths[wi], size, home, right, left, 0, 0, 0, locs[right] }, b = a, o = a; b.rtl = 1; o.startOff = 1;
            TResult ra, rb, ro; NSString *fa, *fb, *fo, *ma, *mb; TRun(a, &ra, &fa, &ma, 1); TRun(b, &rb, &fb, &mb, 1); TRun(o, &ro, &fo, NULL, 1);
            NSString *tag = [NSString stringWithFormat:@"w %.0f size %d home %d right %d left %d", a.w, size, home, right, left];
            // (C6: every frame mirrored; the time label within its slot's slack: 1.8.8's own placing, unchanged here -- StatusBar.x DMShiftLabel puts
            //  the label's left edge where the slot starts, the slot as wide as the text rounded up, so right to left a label of a fractional width,
            //  85.5 pt at Medium on a 2x screen, sits that much toward the slot's other end)
            double dt = rb.timeLead - ra.timeLead, slack = MAX(ra.timeSlack, rb.timeSlack);
            TCheck([ma isEqualToString:mb] && fabs(dt) <= slack + 1e-6, [NSString stringWithFormat:@"C6 right to left is not the mirror: %@ (the time %.2f apart, its slot's slack %.2f)\n   ltr %@\n   rtl %@", tag, dt, slack, fa, fb]);
            // (C8: from either date state one layout gives the same bar; only within the date's half point either way (BarEnds.h MSBDBarDateShows,
            //  so it does not switch at every layout) does each state hold -- then the titles are the same from either and the date kept as it was)
            double k = MSBDMenuBarSizeScale(size), margin = ra.rightLead - (ra.leftEnd + 16.0 * k);
            BOOL band = ![fa isEqualToString:fo] && ra.dateShown && !ro.dateShown && margin >= -0.5 - 1e-6 && margin < 0.5 + 1e-6
                        && !strcmp(ra.names, ro.names) && ra.titlesEnd == ro.titlesEnd;
            if (band) gBand++;
            TCheck([fa isEqualToString:fo] || band, [NSString stringWithFormat:@"C8 one layout from the other date state gives another bar: %@ (the date's margin %.2f)\n   from on  %@\n   from off %@", tag, margin, fa, fo]);
        }
        if (gBand) printf("NOTE  %d bars within the date's half point either way: each date state held, the titles the same from either (C8)\n", gBand);
        if (gTight) printf("NOTE  %d bars with no title left and the date gone where the right end still comes within a title gap of the logo or the traffic lights (closest %.1f pt: %s)\n", gTight, gTightGap, gTightAt.UTF8String);
        char glyph[80] = "";   // (TB_AP_GLYPH: how many of those show the AirPods item as its glyph alone)
        if (TB_AP_GLYPH) snprintf(glyph, sizeof glyph, ", %d of them its glyph alone", gAPGlyphBars);
        printf("%s  %d bars (11 widths: 6 portrait, 4 landscape, a TV x 3 sizes x %d right ends x 3 title sets x Home button or not x right to left x from either date state, + iPadOS's other-region item): C1 never meet, C2 left half, C4 the date only when needed and the time stays, C5 ours last, C9 no two touch areas meet, C10 the AirPods and battery buttons over their items (%d bars with the AirPods item%s), C7 a second layout the same; C6 mirrored, C8 one layout from either state\n",
               gFails ? "FAIL" : "PASS", fails0, kNR, gAPBars, glyph);
        if (dump) fclose(dump);
        return gFails ? 1 : 0;
    }
}
