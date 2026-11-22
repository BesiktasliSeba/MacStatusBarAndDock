// test-airpodsmenu.m -- see test-airpodsmenu.sh. The AirPods menu's Objective-C side that decides what the bar gets, run on the Mac (Mac
// Catalyst, headless: views with no window) with the real code cut out of statusbar/AirPodsMenu.h (DMAPItemViews, DMAirPodsLayoutButton and what
// it calls, DMAirPodsLockLayout, DMAPCoverAX, DMAPMergeHeadsets, DMAPPartsCopy, DMAPReadHeadsets), statusbar/BatteryMenu.h (the battery's own
// button: DMBattLayoutButton, DMBattItemViews, DMBattCoverAX, DMBattItemClass, DMBattViewShown) and StatusBar.x (the leading-coordinate helpers),
// on a stand-in of iPadOS's bar as read in the 17.6.1 / 18.2 SystemStatusUI decompiles (regions, display items with an item, a view and an
// identifier; the Bluetooth item's +batteryDisplayIdentifier), both families' class names (15/16 UIKit's, 17+ SystemStatusUI's):
//  - the button while the Bluetooth item shows headphones (1.8.8.1.1): the glyph with their level, or the glyph alone with the bar's data saying
//    headphones (state 2: AirPods on 17/18), or the glyph alone where that data cannot be read; none for a Bluetooth indicator that is not
//    headphones' (state 0 or 1), a class that does not answer, the switch off, the Lock Screen's layout;
//  - with the battery's button laid out after it, as in the bar's layout pass: the two never overlap, at gaps of 0, 3, 8 and 20 pt (x k), left to
//    right and right to left; from 8 pt x k the AirPods button covers its whole item; neighbours only from the item's own region cut it;
//  - VoiceOver: iPadOS's views under each button are out of VoiceOver, each button's set apart -- the AirPods button going gives back only its own;
//  - the headphones the open menu lists (gone: kept, Not Connected; back; new ones); BatteryCenter's records copied with their types only, the
//    iPad's own battery dropped; Bluetooth's connected headphones (iPadOS's types 16 and 20) and devices with a battery level, their types
//    asked;
//  - DEBUG: the made-up Bluetooth item (sbfakebt_, podfake_bar_; 1.8.8.1.1) on stand-ins of both families' data: 15/16's with setters, 17/18's
//    immutable ones (an STMutable... data class, entries with instance variables only), the glyph alone and with a level, the bar's own overlay
//    back, nothing changed where no value fits.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include "../common/AirPodsMenu.h"
#include "../common/BatteryMenu.h"

#ifdef T_STUI
#define TBatteryItem STUIStatusBarBatteryItem
#define TBluetoothItem STUIStatusBarBluetoothItem
static BOOL gSTUI = YES;
#else
#define TBatteryItem _UIStatusBarBatteryItem
#define TBluetoothItem _UIStatusBarBluetoothItem
static BOOL gSTUI = NO;
#endif

// ---- what the cut code needs ----
static NSMutableArray<NSString *> *gLog;
static void DMLog(NSString *s) { if (!gLog) gLog = [NSMutableArray array]; [gLog addObject:s]; }
static BOOL DMSBUseSTUI(void) { return gSTUI; }
static BOOL gBattMenuOn = YES, gAirPodsMenuOn = YES;
static const void *kBattButtonKey = &kBattButtonKey, *kAirPodsButtonKey = &kAirPodsButtonKey;
static const void *kBattAXWasKey = &kBattAXWasKey;
static const void *kAPAXWasKey = &kAPAXWasKey, *kAPCoveredKey = &kAPCoveredKey, *kAPShownKey = &kAPShownKey;
static BOOL gAPSourcesStarted = NO, gAPPart[3] = { YES, YES, YES };
static int gAPStarts = 0, gAPOpens = 0, gAPFailed = 0;
enum { kDMAPPartHeadset = 0, kDMAPPartParts, kDMAPPartNoise };
static void DMAPPartFailed(int part, NSException *e) { (void)part; (void)e; gAPFailed++; }
static void DMAPCheck(void) {}
static void DMAPStartSources(void) { gAPStarts++; }
static NSString *DMAPAXValue(void) { return @"(value)"; }
static unsigned gAPReadCount = 0, gAPBattDevices = 0, gAPAppleAudio = 0, gAPHeadphoneTypes = 0;
#if DEBUG
static int gAPFake = 0;
static NSMutableArray *gAPFakeHeadsets;
static BOOL gAPFakeGlyphOnly = NO;
static NSHashTable *gCopies;
static const void *kLogoKey = &kLogoKey;
static id DMCall(id obj, NSString *name) { SEL s = NSSelectorFromString(name); return [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil; }
#endif
static CGFloat DMBarCopyHeight(UIView *fg) { return fg.bounds.size.height; }
static BOOL DMButtonPointerEffects(void) { return NO; }
static UIView *DMTrailingContainer(UIView *fg) { return fg; }
@interface DMAXButton : UIButton
@property (nonatomic, copy) NSString *(^axValue)(void);
@end
@implementation DMAXButton
@end
static void DMOpenBatteryMenu(UIButton *btn) { (void)btn; }
static NSString *DMBattAXValue(void) { return @"(battery)"; }
#include "ap-bar.inc"        // (StatusBar.x: DMBarRTL, DMBarRect, DMBarLead, DMBarTrail)
#include "ap-batt.inc"       // (BatteryMenu.h: DMBattItemClass, DMBattViewShown, DMBattItemViews, DMBattItemRect, DMBattCoverAX, DMBattLayoutButton)
#include "ap-types.inc"      // (AirPodsMenu.h: DMAPTypes, DMAPObj, DMAPStr, DMAPCopyStr, the headphones' record)
static NSMutableArray *gAPMenuHeadsets = nil;
@class DMAPHeadsetRec;
static void DMOpenAirPodsMenu(UIButton *btn) { (void)btn; gAPOpens++; }
#include "ap-button.inc"     // (AirPodsMenu.h: DMAPItemClass, DMAPItemViews, DMAPCoverAX, DMAPUnion, DMAPHideButton, DMAirPodsLayoutButton, DMAirPodsLockLayout)
#include "ap-data.inc"       // (AirPodsMenu.h: DMAPMergeHeadsets, DMAPPartsCopy, DMAPReadHeadsets)
#if DEBUG
#include "ap-fake.inc"       // (AirPodsMenu.h: DMAPFakeSet, DMAPFakeFlag, DMAPFakeClass, DMAPFakeReadBack, DMAPFakeBarItem, DMAPFakeShowItem)
#endif

static int gFails, gChecks;
static void Check(BOOL ok, NSString *what) { gChecks++; if (!ok) gFails++; printf("%s  %s\n", ok ? "PASS" : "FAIL", what.UTF8String); }

// ---- the bar (iPadOS's, as read) ----
@interface TItem : NSObject
@end
@implementation TItem
@end
@interface TBatteryItem : TItem
@end
@implementation TBatteryItem
@end
static NSString *gBattIDString;
@interface TBluetoothItem : TItem
@end
@implementation TBluetoothItem
#ifndef T_NOBATTID
+ (NSString *)batteryDisplayIdentifier { return gBattIDString; }
#endif
+ (NSString *)defaultDisplayIdentifier { return @"defaultDisplayIdentifier"; }
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
@interface TBTEntry : NSObject   // (the bar's merged data, as read: -currentAggregatedData's -bluetoothEntry's -state)
@property (nonatomic) long long state;
@end
@implementation TBTEntry
@end
@interface TBarData : NSObject
@property (nonatomic, strong) TBTEntry *bluetoothEntry;
@end
@implementation TBarData
@end
static long long gBTState = 2;   // (connected headphones, as iPadOS gives them; 0 or 1: its plain Bluetooth indicator)
static BOOL gBTNoData = NO;      // (a bar whose data cannot be read)
@interface TBar : UIView
@property (nonatomic, strong) NSDictionary *regions;
@end
@implementation TBar
- (id)currentAggregatedData {
    if (gBTNoData) return nil;
    TBarData *d = [TBarData new]; d.bluetoothEntry = [TBTEntry new]; d.bluetoothEntry.state = gBTState; return d;
}
@end
typedef struct { CGFloat gap, k; BOOL rtl, battShown, glyphShown, otherRegionNeighbour, sameIDObject; } TSetup;
static UIView *View(UIView *fg, CGFloat lead, CGFloat w, BOOL rtl) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(rtl ? fg.bounds.size.width - lead - w : lead, 4, w, 16)];
    [fg addSubview:v]; v.isAccessibilityElement = YES;
    return v;
}
static TDisplayItem *DI(NSString *ident, id item, UIView *v) { TDisplayItem *d = [TDisplayItem new]; d.identifier = ident; d.item = item; d.view = v; return d; }
// Landscape 1194 x 24: the status icons start at 850 (left); iPadOS's Wi-Fi item 860..884; the AirPods item: its glyph 890..906 and its headset
// battery 908..918 (x k from 890); then `gap` (x k); the battery's percentage (30 x k) and glyph (26 x k, 2 x k after it).
typedef struct { TBar *bar; UIView *fg, *wifi, *glyph, *hbatt, *pct, *batt, *far; CGFloat left, itemLead, itemTrail, battLead; } TWorld;
static TWorld MakeWorld(TSetup s) {
    TWorld w = { nil };
    TBar *bar = [[TBar alloc] initWithFrame:CGRectMake(0, 0, 1194, 24)];
    if (s.rtl) bar.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    UIView *fg = [[UIView alloc] initWithFrame:bar.bounds]; [bar addSubview:fg];
    if (s.rtl) fg.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    CGFloat k = s.k, x = 890;
    w.left = 850; w.itemLead = x;
    w.wifi = View(fg, 860, 24, s.rtl);
    w.glyph = View(fg, x, 16 * k, s.rtl); x += 18 * k;
    w.hbatt = View(fg, x, 10 * k, s.rtl); x += 10 * k;
    w.itemTrail = x; x += s.gap * k;
    w.battLead = x;
    w.pct = View(fg, x, 30 * k, s.rtl); x += 32 * k;
    w.batt = View(fg, x, 26 * k, s.rtl);
    w.far = View(fg, w.itemTrail + 1, 4, s.rtl);   // (a view of another region, right after the item: never a neighbour)
    if (!s.glyphShown) w.glyph.alpha = 0;
    if (!s.battShown) w.hbatt.hidden = YES;
    NSString *bid = s.sameIDObject ? gBattIDString : [NSString stringWithFormat:@"%@", [gBattIDString mutableCopy]];   // (an equal string, another object)
    TBluetoothItem *bt = [TBluetoothItem new]; TBatteryItem *bi = [TBatteryItem new];
    TRegion *icons = [TRegion new];
    icons.displayItems = @[DI(@"wifi", [TItem new], w.wifi), DI(@"defaultDisplayIdentifier", bt, w.glyph), DI(bid, bt, w.hbatt), DI(@"percent", bi, w.pct), DI(@"icon", bi, w.batt)];
    TRegion *other = [TRegion new];
    other.displayItems = s.otherRegionNeighbour ? @[DI(@"pill", [TItem new], w.far)] : @[];
    if (!s.otherRegionNeighbour) w.far.hidden = YES;
    bar.regions = @{ @"trailing": icons, @"other": other };
    w.bar = bar; w.fg = fg;
    return w;
}
static CGRect Lead(UIView *fg, CGRect r) { return DMBarRect(fg, DMBarRTL(fg), r); }   // (a frame in leading coordinates)
static void Layout(TWorld w, CGFloat k) { DMAirPodsLayoutButton(w.fg, w.left, k); DMBattLayoutButton(w.fg, w.left, k); }   // (the bar's order: the AirPods button, then the battery's)
static UIButton *APButton(TWorld w) { return objc_getAssociatedObject(w.fg, kAirPodsButtonKey); }
static UIButton *BattButton(TWorld w) { return objc_getAssociatedObject(w.fg, kBattButtonKey); }

static void Geometry(void) {
    const CGFloat gaps[] = { 0, 3, 8, 20 }, ks[] = { 1.0, 1.25 };
    int bad = 0, cases = 0;
    for (int gi = 0; gi < 4; gi++) for (int ki = 0; ki < 2; ki++) for (int rtl = 0; rtl < 2; rtl++) for (int battOn = 0; battOn < 2; battOn++) {
        TSetup s = { gaps[gi], ks[ki], (BOOL)rtl, YES, YES, NO, YES };
        gBattMenuOn = battOn;
        TWorld w = MakeWorld(s);
        Layout(w, s.k);
        UIButton *a = APButton(w), *b = BattButton(w);
        CGRect fa = Lead(w.fg, a.frame), fb = b && !b.hidden ? Lead(w.fg, b.frame) : CGRectNull;
        CGFloat k = s.k, wifiMid = (884 + w.itemLead) / 2.0, gapMid = (w.itemTrail + w.battLead) / 2.0;
        BOOL ok = a && !a.hidden && fa.size.height == 24;
        ok = ok && CGRectGetMinX(fa) >= MAX(w.left - 2 * k, wifiMid) - 1e-6;                                   // (not over our Wi-Fi area, not past the gap's middle before it)
        ok = ok && CGRectGetMaxX(fa) <= MIN(w.itemTrail + 4 * k, s.gap > 0 ? gapMid : w.itemTrail) + 1e-6;    // (not past the gap's middle after it)
        if (battOn) ok = ok && b && !b.hidden && CGRectGetMaxX(fa) <= CGRectGetMinX(fb) + 1e-6;                // (never over the battery's button)
        if (s.gap * k >= 8 * k - 1e-6) ok = ok && CGRectGetMinX(fa) <= w.itemLead + 1e-6 && CGRectGetMaxX(fa) >= w.itemTrail - 1e-6;
        cases++;
        if (!ok) { bad++; printf("   case gap %.0f k %.2f rtl %d battery menu %d: airpods %s battery %s (item %.1f..%.1f)\n", s.gap, k, rtl, battOn, NSStringFromCGRect(fa).UTF8String,
                                 NSStringFromCGRect(fb).UTF8String, w.itemLead, w.itemTrail); }
    }
    gBattMenuOn = YES;
    Check(!bad, [NSString stringWithFormat:@"%@: the AirPods button, then the battery's, as the bar lays them out (%d cases: gaps 0, 3, 8, 20 pt x k 1 and 1.25, left to right and right to left, Battery Menu on and off): "
                                           "never over the battery's button or our Wi-Fi area, never past a gap's middle, the whole item from a gap of 8 pt x k", gSTUI ? @"17+" : @"15/16", cases]);
    TSetup s = { 20, 1, NO, YES, YES, YES, YES };
    TWorld w = MakeWorld(s); Layout(w, 1);
    Check(CGRectGetMaxX(Lead(w.fg, APButton(w).frame)) >= w.itemTrail + 4 - 1e-6, @"  ... a view of another region right after the item (a pill): not a neighbour, the full 4 pt pad");
    TSetup e = { 20, 1, NO, YES, YES, NO, NO };
    w = MakeWorld(e); Layout(w, 1);
    Check(APButton(w) && !APButton(w).hidden, @"  ... the battery display item's identifier an equal string, another object: matched (isEqual)");
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];   // (the main queue's turn: the first placement's block)
    Check(gAPStarts == 1, [NSString stringWithFormat:@"  ... the sources started once, at the first placement, outside the layout (%d)", gAPStarts]);
}
static void GlyphAlone(void) {   // (1.8.8.1.1: iPadOS 17/18 show AirPods as the glyph alone; 1.8.8.1 gave that no button: KT's AirPods on 18.5)
    const CGFloat ks[] = { 1.0, 1.25 };
    int bad = 0, cases = 0;
    for (int ki = 0; ki < 2; ki++) for (int rtl = 0; rtl < 2; rtl++) for (int battOn = 0; battOn < 2; battOn++) {
        TSetup s = { 6.3, ks[ki], (BOOL)rtl, NO, YES, NO, YES };   // (18.5's gap: 6.3 pt from the glyph to the battery)
        gBattMenuOn = battOn;
        TWorld w = MakeWorld(s);
        Layout(w, s.k);
        UIButton *a = APButton(w), *b = BattButton(w);
        CGRect fa = Lead(w.fg, a.frame), fb = b && !b.hidden ? Lead(w.fg, b.frame) : CGRectNull, fg = Lead(w.fg, w.glyph.frame);
        BOOL ok = a && !a.hidden && fa.size.height == 24 && CGRectGetMinX(fa) <= CGRectGetMinX(fg) + 1e-6 && CGRectGetMaxX(fa) >= CGRectGetMaxX(fg) - 1e-6;   // (the whole glyph)
        ok = ok && CGRectGetMinX(fa) >= MAX(w.left - 2 * s.k, (884 + w.itemLead) / 2.0) - 1e-6;
        if (battOn) ok = ok && b && !b.hidden && CGRectGetMaxX(fa) <= CGRectGetMinX(fb) + 1e-6;
        ok = ok && !w.glyph.isAccessibilityElement;
        cases++;
        if (!ok) { bad++; printf("   glyph alone k %.2f rtl %d battery menu %d: airpods %s battery %s glyph %s\n", s.k, rtl, battOn, NSStringFromCGRect(fa).UTF8String, NSStringFromCGRect(fb).UTF8String, NSStringFromCGRect(fg).UTF8String); }
    }
    gBattMenuOn = YES;
    Check(!bad, [NSString stringWithFormat:@"%@: the headphones glyph alone (state 2, no level: AirPods on 17/18) gets the button over the whole glyph, never over the battery's button or our Wi-Fi area, the glyph out of VoiceOver (%d cases)", gSTUI ? @"17+" : @"15/16", cases]);
    TSetup s = { 20, 1, NO, NO, YES, NO, YES };
    gBTState = 0; TWorld w = MakeWorld(s); Layout(w, 1);
    BOOL off0 = !APButton(w) || APButton(w).hidden;
    gBTState = 1; Layout(w, 1);
    BOOL off1 = !APButton(w) || APButton(w).hidden;
    Check(off0 && off1 && w.glyph.isAccessibilityElement, @"  ... a Bluetooth indicator that is not headphones' (state 0 or 1, the regions' regulatory one): no button, iPadOS's view as it is");
    gBTState = 2; Layout(w, 1);
    BOOL back = APButton(w) && !APButton(w).hidden;
    gBTState = 0; Layout(w, 1);
    Check(back && APButton(w).hidden && w.glyph.isAccessibilityElement, @"  ... the state going 2 then 0 with no other change: the button comes, then goes (each layout reads the data)");
    gBTState = 2; gBTNoData = YES; w = MakeWorld(s); Layout(w, 1);
    Check(APButton(w) && !APButton(w).hidden, @"  ... the glyph alone where the bar's data cannot be read: the button (the shown item taken as the headphones')");
    gBTNoData = NO;
    BOOL logged = NO; for (NSString *l in gLog) if ([l containsString:@"the glyph alone"]) logged = YES;
    Check(logged, @"  ... the log says it is the glyph alone");
}
static void WhenNot(void) {
    TSetup s = { 20, 1, NO, NO, YES, NO, YES };   // (the glyph alone, not headphones' by the data: a plain Bluetooth indicator)
    gBTState = 1;
    TWorld w = MakeWorld(s); Layout(w, 1);
    gBTState = 2;
    Check(!APButton(w) || APButton(w).hidden, @"a Bluetooth glyph that is not headphones' (the battery display item not shown, state 1): no button");
    TSetup t = { 20, 1, NO, YES, NO, NO, YES };   // (the headset battery alone, the glyph faded)
    w = MakeWorld(t); Layout(w, 1);
    Check(APButton(w) && !APButton(w).hidden && CGRectGetMinX(Lead(w.fg, APButton(w).frame)) >= w.itemLead + 18 - 4 - 1e-6, @"the headset battery shown, its glyph not: the button over the shown view only");
    TSetup u = { 20, 1, NO, YES, YES, NO, YES };
    w = MakeWorld(u); gAirPodsMenuOn = NO; Layout(w, 1);
    Check(!APButton(w) || APButton(w).hidden, @"the switch off: no button");
    gAirPodsMenuOn = YES; Layout(w, 1);
    BOOL shown = APButton(w) && !APButton(w).hidden;
    gAirPodsMenuOn = NO; Layout(w, 1);
    Check(shown && APButton(w).hidden && w.glyph.isAccessibilityElement && w.hbatt.isAccessibilityElement, @"  ... switched off with the button shown: hidden at the next layout, iPadOS's views back in VoiceOver");
    gAirPodsMenuOn = YES; Layout(w, 1);
    DMAirPodsLockLayout(w.fg);
    Check(APButton(w).hidden && w.glyph.isAccessibilityElement && w.hbatt.isAccessibilityElement, @"the Lock Screen's layout: hidden, iPadOS's views back in VoiceOver");
    Layout(w, 1);
    DMAirPodsLayoutButton(w.fg, CGFLOAT_MAX, 1);
    Check(APButton(w).hidden, @"where the status icons start unknown: hidden");
}
static void VoiceOver(void) {
    TSetup s = { 20, 1, NO, YES, YES, NO, YES };
    TWorld w = MakeWorld(s); Layout(w, 1);
    BOOL both = !w.glyph.isAccessibilityElement && !w.hbatt.isAccessibilityElement && !w.pct.isAccessibilityElement && !w.batt.isAccessibilityElement && w.wifi.isAccessibilityElement;
    w.hbatt.hidden = YES; w.glyph.hidden = YES;   // (AirPods gone: iPadOS takes its item off, the glyph and its battery display item)
    Layout(w, 1);
    BOOL apBack = APButton(w).hidden && w.glyph.isAccessibilityElement && w.hbatt.isAccessibilityElement;
    BOOL battStays = !w.pct.isAccessibilityElement && !w.batt.isAccessibilityElement && BattButton(w) && !BattButton(w).hidden;
    Check(both, @"VoiceOver: iPadOS's AirPods views and battery views both out of VoiceOver under their buttons (Wi-Fi's stays)");
    Check(apBack && battStays, @"  ... the AirPods going gives back its own views only: the battery's stay covered (its own set, not DMBattCoverAX's)");
    w.hbatt.hidden = NO; w.glyph.hidden = NO; Layout(w, 1);
    gBattMenuOn = NO; Layout(w, 1);
    Check(w.pct.isAccessibilityElement && w.batt.isAccessibilityElement && !w.glyph.isAccessibilityElement && !w.hbatt.isAccessibilityElement,
          @"  ... Battery Menu off: the battery's views back, the AirPods' still covered");
    gBattMenuOn = YES;
}

// ---- the data ----
static DMAPHeadsetRec *H(NSString *name, NSString *addr, int level) {
    DMAPHeadsetRec *h = [DMAPHeadsetRec new]; h.name = name; h.address = addr; h.level = level; h.connected = YES; return h;
}
static void Merge(void) {
    gAPMenuHeadsets = nil;
    DMAPMergeHeadsets(@[H(@"A", @"aa", 50), H(@"B", @"bb", 60)]);
    DMAPMergeHeadsets(@[H(@"B", @"bb", 61)]);
    DMAPHeadsetRec *a = gAPMenuHeadsets[0], *b = gAPMenuHeadsets[1];
    Check(gAPMenuHeadsets.count == 2 && [a.name isEqualToString:@"A"] && !a.connected && b.connected && b.level == 61,
          @"the open menu's headphones: one gone stays listed, not connected; the other read again");
    DMAPMergeHeadsets(@[H(@"A", @"aa", 40), H(@"B", @"bb", 61), H(@"C", @"cc", 70)]);
    a = gAPMenuHeadsets[0];
    Check(gAPMenuHeadsets.count == 3 && a.connected && a.level == 40 && [((DMAPHeadsetRec *)gAPMenuHeadsets[2]).name isEqualToString:@"C"], @"  ... back: connected again in its place; a new one added at the end");
    DMAPMergeHeadsets(@[H(@"D", @"dd", 1), H(@"E", @"ee", 2)]);
    Check(gAPMenuHeadsets.count == MSBD_AP_MAX_HEADSETS, @"  ... at most four");
    gAPMenuHeadsets = nil;
}
@interface TBCBatteryDevice : NSObject   // (BatteryCenter's BCBatteryDevice, as read)
@property (nonatomic) unsigned long long parts;
@property (nonatomic) long long percentCharge, productIdentifier;
@property (nonatomic) bool isCharging, isInternal;
@property (nonatomic, copy) NSString *groupName, *matchIdentifier;
@end
@implementation TBCBatteryDevice
@end
@interface TOtherTypesDevice : TBCBatteryDevice   // (a subclass whose percentCharge is another type: asked on its own class, skipped -- added in Parts())
@end
@implementation TOtherTypesDevice
@end
static int TFive(id self, SEL _cmd) { (void)self; (void)_cmd; return 5; }
static TBCBatteryDevice *BC(Class c, unsigned long long parts, long long pct, bool chg, bool internal, NSString *group, NSString *match) {
    TBCBatteryDevice *d = [c new]; d.parts = parts; d.percentCharge = pct; d.isCharging = chg; d.isInternal = internal; d.groupName = group; d.matchIdentifier = match; d.productIdentifier = 0x200e;
    return d;
}
static void Parts(void) {
    Class B = [TBCBatteryDevice class];
    class_addMethod([TOtherTypesDevice class], @selector(percentCharge), (IMP)TFive, "i16@0:8");
    unsigned internal = 9;
    NSArray *list = @[BC(B, 3, 75, false, false, @"My AirPods Pro", @"G1"), BC(B, 4, 40, true, false, @"Case", @"G1"), BC(B, 0, 88, true, true, @"iPad", nil),
                      BC([TOtherTypesDevice class], 1, 10, false, false, @"x", @"G2"), (id)@"not a device", BC(B, 2, 5000, false, false, nil, nil)];
    NSData *d = DMAPPartsCopy(list, &internal);
    const MSBDAPPart *p = d.bytes; NSUInteger n = d.length / sizeof(MSBDAPPart);
    Check(n == 3 && p[0].parts == 3 && p[0].percent == 75 && !strcmp(p[0].groupName, "My AirPods Pro") && !strcmp(p[0].matchId, "G1") && p[0].productId == 0x200e
          && p[1].parts == 4 && p[1].charging && p[2].percent == 1000 && !p[2].groupName[0] && internal == 1,
          [NSString stringWithFormat:@"BatteryCenter's records copied with their types only (%lu): the iPad's own dropped and counted (%u), a class with other types and a non-device skipped, a level kept in range, no name read as empty", (unsigned long)n, internal]);
    NSString *longName = [@"" stringByPaddingToLength:100 withString:@"\u00e9" startingAtIndex:0];   // (200 bytes of UTF-8)
    NSData *ld = DMAPPartsCopy(@[BC(B, 3, 50, false, false, longName, @"G3")], &internal);
    const MSBDAPPart *lp = ld.bytes;
    Check(ld.length == sizeof(MSBDAPPart) && strlen(lp->groupName) == 126 && [NSString stringWithUTF8String:lp->groupName] != nil,
          @"  ... a name longer than the record's room cut before a whole character (still a string)");
    NSMutableArray *many = [NSMutableArray array]; for (int i = 0; i < 20; i++) [many addObject:BC(B, 1, i, false, false, @"x", @"y")];
    Check(DMAPPartsCopy(many, &internal).length / sizeof(MSBDAPPart) == MSBD_AP_MAX_PARTS && DMAPPartsCopy((id)@"x", &internal).length == 0, @"  ... at most 16 records; a list that is not one: none");
}
@interface TBluetoothDevice : NSObject   // (BluetoothManager.framework's BluetoothDevice, as read: the Mac's own is loaded with UIKit)
@property (nonatomic, copy) NSString *name, *address;
@property (nonatomic) bool connected, supportsBatteryLevel, isAppleAudioDevice;
@property (nonatomic) int batteryLevel, type;
@property (nonatomic) unsigned productId;
@end
@implementation TBluetoothDevice
@end
@interface TOldDevice : TBluetoothDevice   // (a device whose batteryLevel is another type here: skipped -- added in Headsets())
@end
@implementation TOldDevice
@end
static long long TOne(id self, SEL _cmd) { (void)self; (void)_cmd; return 1; }
static NSArray *gConnected;
@interface TBluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)connectedDevices;
@end
@implementation TBluetoothManager
+ (instancetype)sharedInstance { static TBluetoothManager *m; if (!m) m = [TBluetoothManager new]; return m; }
- (NSArray *)connectedDevices { return gConnected; }
@end
static TBluetoothDevice *BT(Class c, NSString *name, bool batt, int level, bool apple) {
    TBluetoothDevice *d = [c new]; d.name = name; d.address = [name stringByAppendingString:@"-addr"]; d.connected = true; d.supportsBatteryLevel = batt; d.batteryLevel = level;
    d.isAppleAudioDevice = apple; d.productId = apple ? 0x200e : 0;
    return d;
}
static void Headsets(void) {
    Class D = [TBluetoothDevice class];
    class_addMethod([TOldDevice class], @selector(batteryLevel), (IMP)TOne, "q16@0:8");
    TBluetoothDevice *gone = BT(D, @"Gone", true, 10, true); gone.connected = false;
    gConnected = @[BT(D, @"AirPods", true, 80, true), BT(D, @"Keyboard", false, -1, false), BT([TOldDevice class], @"Old", true, 50, true), gone, BT(D, @"Studio", true, 55, false)];
    NSArray *got = DMAPReadHeadsets();
    DMAPHeadsetRec *a = got.firstObject, *s = got.lastObject;
    Check(got.count == 2 && [a.name isEqualToString:@"AirPods"] && a.level == 80 && a.productId == 0x200e && a.apple && a.device && [s.name isEqualToString:@"Studio"] && !s.apple && gAPBattDevices == 2 && gAPAppleAudio == 1,
          [NSString stringWithFormat:@"Bluetooth's connected devices with a battery level (%lu: no level and not headphones, other types, not connected left out), counted for the probe", (unsigned long)got.count]);
    TBluetoothDevice *cheap = BT(D, @"Cheap", false, 0, false); cheap.type = 16;   // (headphones that report no level: listed, level unknown)
    TBluetoothDevice *pods = BT(D, @"Pods", false, 0, true); pods.type = 20;
    TBluetoothDevice *kb = BT(D, @"Keys", false, 0, false); kb.type = 0;
    gConnected = @[cheap, kb, pods];
    got = DMAPReadHeadsets();
    a = got.firstObject; s = got.lastObject;
    Check(got.count == 2 && [a.name isEqualToString:@"Cheap"] && a.level == -1 && [s.name isEqualToString:@"Pods"] && s.level == -1 && s.apple && gAPHeadphoneTypes == 2 && gAPBattDevices == 0,
          [NSString stringWithFormat:@"  ... connected headphones by iPadOS's type (16, 20) that report no battery level: listed, level unknown; a keyboard with none: not (%lu)", (unsigned long)got.count]);
    gAPPart[kDMAPPartHeadset] = NO;
    Check(DMAPReadHeadsets().count == 0, @"  ... the Bluetooth part off here: nothing asked");
    gAPPart[kDMAPPartHeadset] = YES;
}

#if DEBUG
// ---- the made-up Bluetooth item: the bar's data as each family has it ----
@interface STTestEntry : NSObject { @public BOOL _enabled; }   // (17/18: SystemStatus's entries, immutable: getters, instance variables)
- (BOOL)isEnabled;
@end
@implementation STTestEntry
- (BOOL)isEnabled { return _enabled; }
@end
@interface STTestBatteryEntry : STTestEntry { @public long long _capacity; }
- (long long)capacity;
@end
@implementation STTestBatteryEntry
- (long long)capacity { return _capacity; }
@end
@interface STTestBluetoothEntry : STTestEntry { @public long long _state; STTestBatteryEntry *_batteryEntry; }
- (long long)state;
- (STTestBatteryEntry *)batteryEntry;
@end
@implementation STTestBluetoothEntry
- (long long)state { return _state; }
- (STTestBatteryEntry *)batteryEntry { return _batteryEntry; }
@end
@interface STTestData : NSObject <NSMutableCopying> { @public STTestBluetoothEntry *_bluetoothEntry; STTestBatteryEntry *_mainBatteryEntry; }
- (STTestBluetoothEntry *)bluetoothEntry;
- (STTestBatteryEntry *)mainBatteryEntry;
@end
@interface STMutableTestData : STTestData   // (STMutableStatusBarData: the setters)
- (void)setBluetoothEntry:(STTestBluetoothEntry *)e;
@end
@implementation STTestData
- (STTestBluetoothEntry *)bluetoothEntry { return _bluetoothEntry; }
- (STTestBatteryEntry *)mainBatteryEntry { return _mainBatteryEntry; }
- (id)mutableCopyWithZone:(NSZone *)zone { (void)zone; STMutableTestData *m = [STMutableTestData new]; m->_bluetoothEntry = _bluetoothEntry; m->_mainBatteryEntry = _mainBatteryEntry; return m; }
@end
@implementation STMutableTestData
- (void)setBluetoothEntry:(STTestBluetoothEntry *)e { _bluetoothEntry = e; }
@end
@interface TUIEntry : NSObject   // (15/16: UIKit's entries, with setters)
@property (nonatomic, getter=isEnabled) BOOL enabled;
@end
@implementation TUIEntry
@end
@interface TUIBatteryEntry : TUIEntry
@property (nonatomic) long long capacity;
@end
@implementation TUIBatteryEntry
@end
@interface TUIBluetoothEntry : TUIEntry
@property (nonatomic) long long state;
@property (nonatomic, strong) TUIBatteryEntry *batteryEntry;
@end
@implementation TUIBluetoothEntry
@end
@interface TUIData : NSObject
@property (nonatomic, strong) TUIBluetoothEntry *bluetoothEntry;
@property (nonatomic, strong) TUIBatteryEntry *mainBatteryEntry;
@end
@implementation TUIData
@end
@interface TOddEntry : NSObject   // (an entry with neither a setter nor an instance variable for the state: nothing is guessed)
- (BOOL)isEnabled;
@end
@implementation TOddEntry
- (BOOL)isEnabled { return YES; }
@end
@interface TOddData : NSObject
@property (nonatomic, strong) TOddEntry *bluetoothEntry;
@property (nonatomic, strong) TOddEntry *mainBatteryEntry;
@end
@implementation TOddData
@end
@interface TDataBar : UIView   // (the bar: its data, its overlay, the two merged as the bar draws them)
@property (nonatomic, strong) id currentData, overlayData;
@property (nonatomic, weak) UIView *foregroundView;
@end
@implementation TDataBar
- (id)currentAggregatedData {
    id o = self.overlayData, e = [o respondsToSelector:@selector(bluetoothEntry)] ? [o bluetoothEntry] : nil;
    if (!e) return self.currentData;
    STMutableTestData *m = [STMutableTestData new]; m->_bluetoothEntry = e; return m;   // (only the Bluetooth entry is read back)
}
@end
static TDataBar *DataBar(id data) {
    TDataBar *bar = [[TDataBar alloc] initWithFrame:CGRectMake(0, 0, 1194, 24)];
    UIView *fg = [[UIView alloc] initWithFrame:bar.bounds]; [bar addSubview:fg];
    objc_setAssociatedObject(fg, kLogoKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    bar.currentData = data; bar.foregroundView = fg;
    gCopies = [NSHashTable weakObjectsHashTable]; [gCopies addObject:fg];
    return bar;
}
static void FakeItem(void) {
    // 17/18: STStatusBarData has no setters, its entries none either
    STTestData *d = [STTestData new]; d->_bluetoothEntry = [STTestBluetoothEntry new]; d->_mainBatteryEntry = [STTestBatteryEntry new];
    TDataBar *bar = DataBar(d); id own = [NSObject new]; bar.overlayData = own;
    [gLog removeAllObjects];
    DMAPFakeBarItem(@"2_-1");
    STMutableTestData *o = bar.overlayData; STTestBluetoothEntry *e = [o isKindOfClass:[STMutableTestData class]] ? o.bluetoothEntry : nil;
    Check([o isKindOfClass:[STMutableTestData class]] && [e isKindOfClass:[STTestBluetoothEntry class]] && e.state == 2 && e.isEnabled && (!e.batteryEntry || !e.batteryEntry.isEnabled)
          && [[gLog componentsJoinedByString:@"\n"] containsString:@"state ivar"],
          @"17/18 data (immutable): sbfakebt_2_-1 gives the bar overlay data of the mutable class, a Bluetooth entry of the bar's own class, state 2, enabled, no level (the glyph alone), through its instance variables");
    DMAPFakeBarItem(@"2_80");
    o = bar.overlayData; e = o.bluetoothEntry;
    Check(e.state == 2 && e.isEnabled && e.batteryEntry.isEnabled && e.batteryEntry.capacity == 80 && [e.batteryEntry isKindOfClass:[STTestBatteryEntry class]],
          @"  ... sbfakebt_2_80: the glyph and their level, 80 %, a battery entry of the bar's own class");
    DMAPFakeBarItem(@"2_150");
    Check(((STMutableTestData *)bar.overlayData).bluetoothEntry.batteryEntry.capacity == 100, @"  ... a level over 100 given as 100");
    DMAPFakeBarItem(@"off");
    Check(bar.overlayData == own, @"  ... sbfakebt_off: the bar's own overlay back");
    // 15/16: UIKit's data and entries with setters
    TUIData *u = [TUIData new]; u.bluetoothEntry = [TUIBluetoothEntry new]; u.mainBatteryEntry = [TUIBatteryEntry new];
    bar = DataBar(u); bar.overlayData = nil;
    [gLog removeAllObjects];
    DMAPFakeBarItem(@"2_55");
    TUIData *uo = bar.overlayData;
    Check([uo isKindOfClass:[TUIData class]] && uo.bluetoothEntry.state == 2 && uo.bluetoothEntry.isEnabled && uo.bluetoothEntry.batteryEntry.isEnabled && uo.bluetoothEntry.batteryEntry.capacity == 55
          && [[gLog componentsJoinedByString:@"\n"] containsString:@"state set"], @"15/16 data (setters): sbfakebt_2_55 through the setters, as 1.8.8.1");
    DMAPFakeBarItem(@"2_-1");
    uo = bar.overlayData;
    Check(uo.bluetoothEntry.state == 2 && uo.bluetoothEntry.batteryEntry && !uo.bluetoothEntry.batteryEntry.isEnabled, @"  ... sbfakebt_2_-1: a battery entry that is off (the glyph alone), as 1.8.8.1");
    DMAPFakeBarItem(@"off");
    Check(bar.overlayData == nil, @"  ... sbfakebt_off: no overlay again");
    // neither fits: nothing changes
    TOddData *x = [TOddData new]; x.bluetoothEntry = [TOddEntry new]; x.mainBatteryEntry = [TOddEntry new];
    bar = DataBar(x); bar.overlayData = own;
    [gLog removeAllObjects];
    DMAPFakeBarItem(@"2_80");
    Check(bar.overlayData == own && [[gLog componentsJoinedByString:@"\n"] containsString:@"not as expected, nothing changed"], @"data whose entries take neither a setter nor an instance variable: nothing changed, said");
    // the made-up headphones choose the shape (podfake_bar_)
    bar = DataBar(d); bar.overlayData = nil;
    DMAPHeadsetRec *h = [DMAPHeadsetRec new]; h.level = 75; h.connected = YES;
    gAPFakeHeadsets = [NSMutableArray arrayWithObject:h]; gAPFake = 1;
    gAPFakeGlyphOnly = YES; DMAPFakeShowItem();
    e = ((STMutableTestData *)bar.overlayData).bluetoothEntry;
    BOOL glyph = e.state == 2 && (!e.batteryEntry || !e.batteryEntry.isEnabled);
    gAPFakeGlyphOnly = NO; DMAPFakeShowItem();
    e = ((STMutableTestData *)bar.overlayData).bluetoothEntry;
    BOOL lvl = e.state == 2 && e.batteryEntry.isEnabled && e.batteryEntry.capacity == 75;
    h.connected = NO; DMAPFakeShowItem();
    Check(glyph && lvl && bar.overlayData == nil, @"the made-up headphones: the glyph alone (podfake_bar_glyph), with their level 75 % (podfake_bar_level), gone when they disconnect");
    gAPFakeHeadsets = nil; gAPFake = 0;
    // iPadOS replaces the bar's overlay with its own (the Cover Sheet's) while the item is on: put back at the next turn, over iPadOS's
    bar = DataBar(d); bar.overlayData = nil;
    DMAPFakeBarItem(@"2_-1");
    STTestData *theirs = [STTestData new]; theirs->_mainBatteryEntry = [STTestBatteryEntry new]; theirs->_mainBatteryEntry->_capacity = 33;
    bar.overlayData = theirs;
    DMAPFakeBarRecheck(bar);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    STMutableTestData *back = bar.overlayData;
    Check([back isKindOfClass:[STMutableTestData class]] && back != theirs && back.bluetoothEntry.state == 2 && (!back.bluetoothEntry.batteryEntry || !back.bluetoothEntry.batteryEntry.isEnabled)
          && back.mainBatteryEntry.capacity == 33, @"iPadOS's own overlay set over the made-up item (the Cover Sheet's): the item put back at the next turn, over iPadOS's overlay (its entries kept)");
    DMAPFakeBarRecheck(bar);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(bar.overlayData == back, @"  ... the merged data as asked: nothing done again");
    DMAPFakeBarItem(@"off");
    Check(bar.overlayData == theirs, @"  ... sbfakebt_off gives iPadOS's own overlay back (the one it set)");
    bar.overlayData = nil; DMAPFakeBarRecheck(bar);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    Check(bar.overlayData == nil, @"  ... off: never put back");
}
#endif

int main(int argc, char **argv) {
    @autoreleasepool {
        (void)argc; (void)argv;
        gBattIDString = [NSString stringWithFormat:@"%@", @"batteryDisplayIdentifier"];
#ifdef T_NOBATTID
        TSetup s = { 20, 1, NO, YES, YES, NO, YES };
        TWorld w = MakeWorld(s); Layout(w, 1);
        Check(!APButton(w) || APButton(w).hidden, @"an item class with no +batteryDisplayIdentifier (unknown on 15/16 until D0): no button");
#else
        Geometry();
        GlyphAlone();
        WhenNot();
        VoiceOver();
        Merge();
        Parts();
        Headsets();
#if DEBUG
        FakeItem();
#endif
#endif
        printf("test-airpodsmenu (%s%s, %s): %d checks, %d fail\n", gSTUI ? "17+" : "15/16",
#ifdef T_NOBATTID
               ", no battery identifier",
#else
               "",
#endif
#if DEBUG
               "DEBUG",
#else
               "release",
#endif
               gChecks, gFails);
        return gFails ? 1 : 0;
    }
}
