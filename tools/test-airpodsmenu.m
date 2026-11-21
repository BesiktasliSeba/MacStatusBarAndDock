// test-airpodsmenu.m -- see test-airpodsmenu.sh. The AirPods menu's Objective-C side that decides what the bar gets, run on the Mac (Mac
// Catalyst, headless: views with no window) with the real code cut out of statusbar/AirPodsMenu.h (DMAPItemViews, DMAirPodsLayoutButton and what
// it calls, DMAirPodsLockLayout, DMAPCoverAX, DMAPMergeHeadsets, DMAPPartsCopy, DMAPReadHeadsets), statusbar/BatteryMenu.h (the battery's own
// button: DMBattLayoutButton, DMBattItemViews, DMBattCoverAX, DMBattItemClass, DMBattViewShown) and StatusBar.x (the leading-coordinate helpers),
// on a stand-in of iPadOS's bar as read in the 17.6.1 / 18.2 SystemStatusUI decompiles (regions, display items with an item, a view and an
// identifier; the Bluetooth item's +batteryDisplayIdentifier), both families' class names (15/16 UIKit's, 17+ SystemStatusUI's):
//  - the button only while the Bluetooth item's battery display item shows; none for a bare glyph, a class that does not answer, the switch off,
//    the Lock Screen's layout;
//  - with the battery's button laid out after it, as in the bar's layout pass: the two never overlap, at gaps of 0, 3, 8 and 20 pt (x k), left to
//    right and right to left; from 8 pt x k the AirPods button covers its whole item; neighbours only from the item's own region cut it;
//  - VoiceOver: iPadOS's views under each button are out of VoiceOver, each button's set apart -- the AirPods button going gives back only its own;
//  - the headphones the open menu lists (gone: kept, Not Connected; back; new ones); BatteryCenter's records copied with their types only, the
//    iPad's own battery dropped; Bluetooth's devices with a battery level only, their types asked.
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
static unsigned gAPReadCount = 0, gAPBattDevices = 0, gAPAppleAudio = 0;
#if DEBUG
static int gAPFake = 0;
static NSMutableArray *gAPFakeHeadsets;
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
@interface TBar : UIView
@property (nonatomic, strong) NSDictionary *regions;
@end
@implementation TBar
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
static void WhenNot(void) {
    TSetup s = { 20, 1, NO, NO, YES, NO, YES };   // (a bare Bluetooth glyph: no headset battery)
    TWorld w = MakeWorld(s); Layout(w, 1);
    Check(!APButton(w) || APButton(w).hidden, @"a bare Bluetooth glyph (the battery display item not shown): no button");
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
    w.hbatt.hidden = YES;   // (AirPods gone: iPadOS takes its battery display item off)
    Layout(w, 1);
    BOOL apBack = APButton(w).hidden && w.glyph.isAccessibilityElement && w.hbatt.isAccessibilityElement;
    BOOL battStays = !w.pct.isAccessibilityElement && !w.batt.isAccessibilityElement && BattButton(w) && !BattButton(w).hidden;
    Check(both, @"VoiceOver: iPadOS's AirPods views and battery views both out of VoiceOver under their buttons (Wi-Fi's stays)");
    Check(apBack && battStays, @"  ... the AirPods going gives back its own views only: the battery's stay covered (its own set, not DMBattCoverAX's)");
    w.hbatt.hidden = NO; Layout(w, 1);
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
@property (nonatomic) int batteryLevel;
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
          [NSString stringWithFormat:@"Bluetooth's connected devices with a battery level only (%lu: no level, other types, not connected left out), counted for the probe", (unsigned long)got.count]);
    gAPPart[kDMAPPartHeadset] = NO;
    Check(DMAPReadHeadsets().count == 0, @"  ... the Bluetooth part off here: nothing asked");
    gAPPart[kDMAPPartHeadset] = YES;
}

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
        WhenNot();
        VoiceOver();
        Merge();
        Parts();
        Headsets();
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
