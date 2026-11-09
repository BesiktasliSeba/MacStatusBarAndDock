// CCTiles.h -- our own Control Center's Mac tiles (1.8.0 P3; plans/control-center-1.8.0.md 1.1, 2.4-2.7): Connectivity (Airplane Mode, Wi-Fi,
// Bluetooth), Display, Sound and Now Playing, drawn by us in the panel through its tile interface (CCPanel.h DMCCTile), in place of P2's
// placeholders, with their detail pages. Included once by StatusBar.x, right after CCPanel.h. Where its parts go: common/CCTileLogic.h (plain C,
// tools/test-cctiles.sh).
//  - Connectivity (2 x 2): a row each for Airplane Mode, Wi-Fi and Bluetooth (KT 3 Nov: Airplane Mode in AirDrop's place, at the top). Its round
//    button switches it (Airplane Mode as Control Center's own button does, AppSupport's RadiosPreferences, its button Apple's orange when on;
//    Wi-Fi as the Wi-Fi menu's switch does, WiFiMenu.h DMWiFiSetPower; Bluetooth as Settings' switch, BluetoothManager.framework). The rest of
//    Wi-Fi's and Bluetooth's rows opens their page: Wi-Fi's is the Wi-Fi menu's own rows (DMWiFiMenuItems, scanning only while the page is open;
//    a row closes Control Center first, DMCloseThen asks DMRowsHost), Bluetooth's the switch, the paired devices (a tap connects or disconnects)
//    and Bluetooth Settings…; Airplane Mode has no page (nor in Apple's module). A hold opens Apple's own Connectivity module expanded (AirDrop,
//    Personal Hotspot), out of the tile.
//  - Display (4 x 1): the brightness, set the way the brightness keys set it (SpringBoard's SBDisplayBrightnessController, BrightnessKey.x), read
//    from UIScreen; its chevron or a hold opens Apple's Display module expanded from the tile (Dark Mode, Night Shift, True Tone).
//  - Sound (4 x 1): the media volume (AVSystemController's active category, as the volume buttons change it); its chevron opens our Sound page,
//    the Audio menu's own rows (DMAudioMenuItems) with Sound Settings…; a hold opens Apple's volume module expanded.
//  - Now Playing (4 x 1): MediaRemote's now playing title, artist and artwork (decoded off the main thread), play / pause and next; a tap elsewhere
//    on it opens Apple's Now Playing module expanded from the tile.
// Every private class and call is asked through a table of the type encodings read on 15.6.1 and 17.5.1 (DMCCTCheck): a part whose rows are not
// all there falls back (a Bluetooth page with only its Settings row, a greyed slider whose chevron and hold still open Apple's module, ...);
// none of it can end SpringBoard. Nothing runs while Control Center is closed: the system's notifications only mark a tile's state as old, and it is read once at
// the next presentation (tileWillPresent); scans and observers that keep a page current run only while it is open; the screen going off closes
// Control Center and stops them (DMCCTScreenOff). Logs never name a network, a device or a track: a short hash or a count.
// Assistive features: each part is one element with its name, its value and what using it does (a Connectivity row switches, its "Show Details"
// action opens its page; the sliders are adjustable, 1/16 a step; the player's buttons), and the panel reads them in its order on the screen.
#pragma once
#include <os/lock.h>
#include "../common/CCTileLogic.h"

static BOOL gCCTShown = NO;          // Control Center is presented (tileWillPresent to tileDidDismiss): while not, the observers only mark states old
static NSMutableArray<dispatch_block_t> *gCCTAfterClose;   // (a row's action that waits for Control Center to have closed: DMCCTCloseThen)
static unsigned gCCTAfterCloseGen = 0;
#if DEBUG
static int gCCTFakeBT = 0;           // (tests: cct_btfake_<n> -- 1 off, 2 on with no device, 3 on with two made-up devices, one connected; 0 the real state)
static int gCCTFakeAirplane = -1;    // (tests: cct_apfake_<0|1> -- shown off / on, a tap changes only this, the radio is never asked; -1 the real state)
static int gCCTFakeNow = 0;          // (tests: cct_npfake_<n> -- 1 a made-up track playing, 2 paused; the buttons only log. 0 the real state)
#endif

// ---- the API table ---------------------------------------------------------------------------------------------------------------------------
// What the tiles ask, with the types read on 15.6.1 (M1) and 17.5.1 (17.5): the same there (1.8.0 P3 probe, 3 Nov; RadiosPreferences' rows from
// 17.5.1's own cache, 3 Nov, and the build's table on both). Each part is usable only with all of its rows (DMCCTCheck, at the panel's build: the
// frameworks are loaded then; one missing is opened once, never earlier).
typedef struct { const char *cls, *sel, *enc; BOOL meta; int part; } DMCCTNeedRow;
enum { kDMCCTPartBT = 0, kDMCCTPartBTDevices, kDMCCTPartAirplane, kDMCCTPartBright, kDMCCTPartVolume, kDMCCTParts };
static const DMCCTNeedRow kDMCCTNeeds[] = {
    { "BluetoothManager", "sharedInstance", "@16@0:8", YES, kDMCCTPartBT },
    { "BluetoothManager", "available", "B16@0:8", NO, kDMCCTPartBT },
    { "BluetoothManager", "powered", "B16@0:8", NO, kDMCCTPartBT },
    { "BluetoothManager", "enabled", "B16@0:8", NO, kDMCCTPartBT },
    { "BluetoothManager", "setPowered:", "B20@0:8B16", NO, kDMCCTPartBT },
    { "BluetoothManager", "setEnabled:", "B20@0:8B16", NO, kDMCCTPartBT },
    { "BluetoothManager", "pairedDevices", "@16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothManager", "connectedDevices", "@16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothDevice", "name", "@16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothDevice", "address", "@16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothDevice", "connected", "B16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothDevice", "connect", "v16@0:8", NO, kDMCCTPartBTDevices },
    { "BluetoothDevice", "disconnect", "v16@0:8", NO, kDMCCTPartBTDevices },
    { "RadiosPreferences", "initWithQueue:", "@24@0:8@16", NO, kDMCCTPartAirplane },
    { "RadiosPreferences", "airplaneMode", "B16@0:8", NO, kDMCCTPartAirplane },
    { "RadiosPreferences", "setAirplaneMode:", "v20@0:8B16", NO, kDMCCTPartAirplane },
    { "RadiosPreferences", "refresh", "v16@0:8", NO, kDMCCTPartAirplane },
    { "RadiosPreferences", "setDelegate:", "v24@0:8@16", NO, kDMCCTPartAirplane },
    { "SBDisplayBrightnessController", "setBrightnessLevel:animated:", "B24@0:8f16B20", NO, kDMCCTPartBright },
    { "AVSystemController", "sharedAVSystemController", "@16@0:8", YES, kDMCCTPartVolume },
    { "AVSystemController", "getActiveCategoryVolume:andName:", "B32@0:8^f16^@24", NO, kDMCCTPartVolume },
    { "AVSystemController", "setActiveCategoryVolumeTo:", "B20@0:8f16", NO, kDMCCTPartVolume },
};
static BOOL gCCTPart[kDMCCTParts];
// MediaRemote (Now Playing): C functions, looked up once.
typedef void (*DMCCTMRInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*DMCCTMRPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*DMCCTMRRegisterFn)(dispatch_queue_t);
typedef Boolean (*DMCCTMRSendFn)(uint32_t, CFDictionaryRef);
typedef void (*DMCCTMRDisplayIDFn)(dispatch_queue_t, void (^)(CFStringRef));
static struct { DMCCTMRInfoFn info; DMCCTMRPlayingFn playing; DMCCTMRRegisterFn reg; DMCCTMRSendFn send; DMCCTMRDisplayIDFn app; BOOL ok; } gCCTMR;
static NSString *gCCTMRInfoNote, *gCCTMRPlayingNote, *gCCTMRAppNote, *gCCTVolumeNote;   // (the notifications' names, from the frameworks' own constants)
enum { kDMCCTMRTogglePlayPause = 2, kDMCCTMRNextTrack = 4 };
static NSString *DMCCTFrameworkString(const char *framework, const char *symbol) {   // (an exported NSString constant, nil where it is not)
    void *h = dlopen(framework, RTLD_LAZY | RTLD_NOLOAD) ?: dlopen(framework, RTLD_LAZY);
    void **p = h ? dlsym(h, symbol) : NULL;
    id s = p ? (__bridge id)*p : nil;
    return [s isKindOfClass:[NSString class]] ? s : nil;
}
static BOOL DMCCTRowOK(const DMCCTNeedRow *r) {
    Class c = objc_getClass(r->cls);
    Method m = !c ? NULL : r->meta ? class_getClassMethod(c, sel_registerName(r->sel)) : class_getInstanceMethod(c, sel_registerName(r->sel));
    const char *t = m ? method_getTypeEncoding(m) : NULL;
    return t && !strcmp(t, r->enc);
}
// Once, at the panel's build (CCPanel.h DMCCPMakeViews, when Apple builds Control Center: its Connectivity module has loaded BluetoothManager and
// AppSupport by then; a framework not loaded yet is opened here, at that time only).
static void DMCCTCheck(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    if (!objc_getClass("BluetoothManager")) dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
    if (!objc_getClass("RadiosPreferences")) dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
    if (!objc_getClass("AVSystemController")) dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_LAZY);
    for (int p = 0; p < kDMCCTParts; p++) gCCTPart[p] = YES;
    NSMutableArray *missing = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kDMCCTNeeds) / sizeof(kDMCCTNeeds[0]); i++) {
        if (DMCCTRowOK(&kDMCCTNeeds[i])) continue;
        gCCTPart[kDMCCTNeeds[i].part] = NO;
        [missing addObject:[NSString stringWithFormat:@"%c[%s %s]", kDMCCTNeeds[i].meta ? '+' : '-', kDMCCTNeeds[i].cls, kDMCCTNeeds[i].sel]];
    }
    if (!gCCTPart[kDMCCTPartBT]) gCCTPart[kDMCCTPartBTDevices] = NO;
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    gCCTMR.info = mr ? (DMCCTMRInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    gCCTMR.playing = mr ? (DMCCTMRPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
    gCCTMR.reg = mr ? (DMCCTMRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
    gCCTMR.send = mr ? (DMCCTMRSendFn)dlsym(mr, "MRMediaRemoteSendCommand") : NULL;
    gCCTMR.app = mr ? (DMCCTMRDisplayIDFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationDisplayID") : NULL;
    const char *mrPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";
    gCCTMRInfoNote = DMCCTFrameworkString(mrPath, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
    gCCTMRPlayingNote = DMCCTFrameworkString(mrPath, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
    gCCTMRAppNote = DMCCTFrameworkString(mrPath, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
    gCCTMR.ok = gCCTMR.info && gCCTMR.playing && gCCTMR.reg && gCCTMR.send && gCCTMRInfoNote && gCCTMRPlayingNote;
    if (!gCCTMR.ok) [missing addObject:@"MediaRemote's now playing functions"];
    gCCTVolumeNote = DMCCTFrameworkString("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", "AVSystemController_SystemVolumeDidChangeNotification");   // ("SystemVolumeDidChange" on 15 and 17)
    DMLog([NSString stringWithFormat:@"[cctiles] API: Airplane Mode %d, Bluetooth %d (devices %d), brightness %d, volume %d (its notification %@), now playing %d%@", gCCTPart[kDMCCTPartAirplane],
        gCCTPart[kDMCCTPartBT], gCCTPart[kDMCCTPartBTDevices], gCCTPart[kDMCCTPartBright], gCCTPart[kDMCCTPartVolume], gCCTVolumeNote ?: @"none", gCCTMR.ok,
        missing.count ? [@"; missing: " stringByAppendingString:[missing componentsJoinedByString:@", "]] : @""]);
}

// ---- shared look ---------------------------------------------------------------------------------------------------------------------------
static UIColor *DMCCTPlatterColor(void) {   // (a tile on the panel's material, as P2's placeholders and macOS's tiles)
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
}
static UIColor *DMCCTOffCircleColor(void) {   // (a round button that is off)
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.16] : [UIColor colorWithWhite:0.0 alpha:0.09];
    }];
}
static UIView *DMCCTPlatter(void) {
    UIView *v = [UIView new];
    v.backgroundColor = DMCCTPlatterColor();
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;   // (our content stays English, left to right: our menus' rule)
    return v;
}
// The panel's size (Settings' Control Center Size, CCPanel.h gCCPSize; CCLayout.h MSBDCCSize): a tile lays its parts out at its frame's own size
// (its bounds over the size) and puts them, its text and its symbols at the size -- drawn at it, never a picture made smaller.
static CGFloat DMCCTSize(void) { return gCCPSize > 0.0 && gCCPSize <= 1.0 ? gCCPSize : 1.0; }
static CGRect DMCCTAt(CGRect r) { return MSBDCCScaleRect(r, DMCCTSize()); }
static CGFloat DMCCTCorner(void) { return MIN(18.0, round(gCCPMetrics.unit * 0.26)) * DMCCTSize(); }
// Bluetooth's rune, drawn (SF Symbols has none), as a template image for a round button, cached by height.
static UIImage *DMCCTBluetoothGlyph(CGFloat height) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%.1f", height];
    if (cache[key]) return cache[key];
    CGFloat H = height, W = ceil(H * 0.62);
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(W, H)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor blackColor] setStroke];
        UIBezierPath *p = [UIBezierPath bezierPath];
        CGFloat lw = MAX(1.4, H * 0.11), cx = W / 2.0, l = lw / 2.0 + W * 0.06, r = W - lw / 2.0 - W * 0.06;
        [p moveToPoint:CGPointMake(l, H * 0.73)];
        [p addLineToPoint:CGPointMake(r, H * 0.29)]; [p addLineToPoint:CGPointMake(cx, lw / 2.0)]; [p addLineToPoint:CGPointMake(cx, H - lw / 2.0)];
        [p addLineToPoint:CGPointMake(r, H * 0.71)]; [p addLineToPoint:CGPointMake(l, H * 0.27)];
        p.lineWidth = lw; p.lineJoinStyle = kCGLineJoinRound; p.lineCapStyle = kCGLineCapRound;
        [p stroke];
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[key] = img;
    return img;
}
// A symbol at a size, made once (the first making of a symbol reads it from the system's glyphs: 7 ms of a first presentation on the 17.5 for the
// speaker's waves, 1.8.0~t05): the same image every time after, so a view given it again changes nothing.
static UIImage *DMCCTSymbol(NSString *name, CGFloat pt, UIImageSymbolWeight w) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%.1f/%ld", name, pt, (long)w];
    UIImage *img = cache[key];
    if (!img) { img = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:pt weight:w]]; if (img) cache[key] = img; }
    return img;
}

// ---- rows that close Control Center (DMCloseThen, StatusBar.x) -----------------------------------------------------------------------------
// A row of a page (a menu's own row: Wi-Fi's networks, Settings links) closes Control Center instead of a menu, and its action runs once Apple's
// dismissal is done (-_didDismiss: DMCCTPanelDidDismiss) -- our password sheet, Settings: our menu window lies under Control Center's, and Settings
// would open behind it. A close that never comes (Control Center already on its way away) runs them a second later.
static void DMCCTRunAfterClose(NSString *why) {
    NSArray<dispatch_block_t> *todo = gCCTAfterClose;
    gCCTAfterClose = nil;
    if (!todo.count) return;
    DMLog([NSString stringWithFormat:@"[cctiles] %lu row action(s) after Control Center closed (%@)", (unsigned long)todo.count, why]);
    for (dispatch_block_t b in todo) b();
}
static dispatch_block_t DMCCTCloseThen(dispatch_block_t action) {
    dispatch_block_t a = [action copy];
    return ^{
        if (!gCCTAfterClose) gCCTAfterClose = [NSMutableArray array];
        if (a) [gCCTAfterClose addObject:a];
        unsigned gen = ++gCCTAfterCloseGen;
        DMLog(@"[cctiles] a row of a page: Control Center closes first");
        DMCCPanelDismiss();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gen == gCCTAfterCloseGen) DMCCTRunAfterClose(@"no close seen in 1 s"); });
    };
}
// The rows of a page, made by a menu's own builder with DMCloseThen closing Control Center (and, on the Lock Screen, the rows that need Settings
// or our menu window greyed: DMRowsHostLocked).
static NSArray *DMCCTRows(NSArray *(^builder)(void)) {
    int was = gDMRowsHost;
    gDMRowsHost = DMCCPanelLocked() ? kDMRowsHostCCLocked : kDMRowsHostCC;
    NSArray *items = builder();
    gDMRowsHost = was;
    return items;
}

// ---- a page: a menu's rows in the panel --------------------------------------------------------------------------------------------------
// Rows as the menus have them (DMRow, DMSliderRow, switch rows; NSNull a divider), each its menu height (DMPanelItemHeight), without the menu's
// material (the panel has its own). Filled again in place when what it shows changed (the page's height follows: DMCCPanelDetailResized).
@interface DMCCTPageView : UIView
- (void)dm_fill:(NSArray *)items;
@end
@implementation DMCCTPageView
- (void)dm_fill:(NSArray *)items {
    for (UIView *v in [self.subviews copy]) [v removeFromSuperview];
    CGFloat w = self.bounds.size.width, y = 0;
    for (id it in items) {
        CGFloat rh = DMPanelItemHeight(it);
        if (it == [NSNull null]) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectMake(8.0, y + (rh - kDividerH) / 2.0, w - 16.0, kDividerH)];
            line.backgroundColor = DMMenuDividerColor();
            [self addSubview:line];
        } else {
            UIView *row = it;
            row.frame = CGRectMake(0, y, w, rh);
            [self addSubview:row];
        }
        y += rh;
    }
    CGRect f = self.frame; f.size.height = y; self.frame = f;
    DMForceLeftToRight(self, 0);   // (our rows stay left to right in a right-to-left language, as the menus)
}
@end
static DMCCTPageView *DMCCTPageMake(NSArray *items, CGFloat width) {
    DMCCTPageView *p = [[DMCCTPageView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
    [p dm_fill:items];
    return p;
}
// A switch row of ours ("Bluetooth"), as the Wi-Fi menu's first row.
@interface DMCCTSwitchRow : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UISwitch *toggle;
@end
@implementation DMCCTSwitchRow
- (instancetype)initWithTitle:(NSString *)title on:(BOOL)on enabled:(BOOL)enabled onChange:(void (^)(BOOL))onChange {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _label = [UILabel new];
    _label.text = title; _label.font = [UIFont systemFontOfSize:DMMenuTextPt() weight:UIFontWeightSemibold]; _label.textColor = [UIColor labelColor];
    _label.isAccessibilityElement = NO;   // (the switch carries the name)
    [self addSubview:_label];
    _toggle = [UISwitch new];
    _toggle.accessibilityLabel = title; _toggle.on = on; _toggle.enabled = enabled; _toggle.onTintColor = [UIColor systemBlueColor];
    _toggle.transform = CGAffineTransformMakeScale(0.72, 0.72);
    void (^change)(BOOL) = [onChange copy];
    __weak UISwitch *weakToggle = _toggle;
    [_toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (weakToggle && change) change(weakToggle.on); }] forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];
    return self;
}
- (CGFloat)dmRowHeight { return MSBDMenuRowScaled(gDMBarSize, kWiFiSwitchRowH); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.toggle.bounds.size;
    self.toggle.center = CGPointMake(self.bounds.size.width - 12.0 - s.width * 0.72 / 2.0, self.bounds.size.height / 2.0);
    self.label.frame = CGRectMake(16.0, 0.0, self.bounds.size.width - 32.0 - s.width * 0.72, self.bounds.size.height);
}
@end

// ---- Wi-Fi's state (WiFiMenu.h: SpringBoard's own cached values) -----------------------------------------------------------------------
static BOOL DMCCTWiFiPageShown(void);
static void DMCCTWiFiToggle(void) {
#if DEBUG
    if (gWiFiFakeState) { gWiFiFakeState = gWiFiFakeState == 1 ? 3 : 1; DMLog([NSString stringWithFormat:@"[cctiles] Wi-Fi button (test state now %d): nothing switched", gWiFiFakeState]); DMWiFiListChanged(); return; }
#endif
    DMWiFiSetPower(!DMWiFiPowered());   // (the Wi-Fi menu's own switch: real on / off, as Settings' -- not Control Center's "until tomorrow")
}

// ---- Bluetooth (BluetoothManager.framework: Settings' Bluetooth switch and its device list) ------------------------------------------------
// The manager is SpringBoard's own (it shows Bluetooth in the status bar): +sharedInstance, asked only once our panel exists. Its daemon attaches
// after a start (-available NO until then: "Unavailable").
#if DEBUG
@interface DMCCTFakeDevice : NSObject
@property (nonatomic, copy) NSString *name, *address;
@property (nonatomic) BOOL connected;
@end
@implementation DMCCTFakeDevice
@end
static NSArray *gCCTFakeDevices;
#endif
static id DMCCTBT(void) {
    if (!gCCTPart[kDMCCTPartBT]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("BluetoothManager"), NSSelectorFromString(@"sharedInstance"));
}
static BOOL DMCCTBTBool(NSString *sel) { id bt = DMCCTBT(); return bt && ((BOOL (*)(id, SEL))objc_msgSend)(bt, NSSelectorFromString(sel)); }
static BOOL DMCCTBTAvailable(void) {
#if DEBUG
    if (gCCTFakeBT) return YES;
#endif
    return DMCCTBTBool(@"available");
}
static BOOL DMCCTBTPowered(void) {
#if DEBUG
    if (gCCTFakeBT) return gCCTFakeBT >= 2;
#endif
    return DMCCTBTBool(@"powered");
}
static NSArray *DMCCTBTDevices(BOOL connectedOnly) {   // (paired, the connected ones first, then by name)
#if DEBUG
    if (gCCTFakeBT) {
        if (gCCTFakeBT < 3) return @[];
        if (!gCCTFakeDevices) {
            DMCCTFakeDevice *a = [DMCCTFakeDevice new]; a.name = @"Test Headphones"; a.address = @"00:00:00:00:00:01"; a.connected = YES;
            DMCCTFakeDevice *b = [DMCCTFakeDevice new]; b.name = @"Test Keyboard With A Very Long Name"; b.address = @"00:00:00:00:00:02";
            gCCTFakeDevices = @[a, b];
        }
        return connectedOnly ? [gCCTFakeDevices filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"connected == YES"]] : gCCTFakeDevices;
    }
#endif
    id bt = DMCCTBT();
    if (!bt || !gCCTPart[kDMCCTPartBTDevices]) return @[];
    NSArray *list = ((id (*)(id, SEL))objc_msgSend)(bt, NSSelectorFromString(connectedOnly ? @"connectedDevices" : @"pairedDevices"));
    if (![list isKindOfClass:[NSArray class]]) return @[];
    Class dc = objc_getClass("BluetoothDevice");
    NSMutableArray *out = [NSMutableArray array];
    for (id d in list) if ([d isKindOfClass:dc]) [out addObject:d];
    return [out sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        BOOL ca = ((BOOL (*)(id, SEL))objc_msgSend)(a, @selector(connected)), cb = ((BOOL (*)(id, SEL))objc_msgSend)(b, @selector(connected));
        if (ca != cb) return ca ? NSOrderedAscending : NSOrderedDescending;
        NSString *na = DMCall(a, @"name"), *nb = DMCall(b, @"name");
        return [([na isKindOfClass:[NSString class]] ? na : @"") localizedCaseInsensitiveCompare:[nb isKindOfClass:[NSString class]] ? nb : @""];
    }];
}
static BOOL DMCCTBTDeviceConnected(id d) {
#if DEBUG
    if ([d isKindOfClass:[DMCCTFakeDevice class]]) return ((DMCCTFakeDevice *)d).connected;
#endif
    return ((BOOL (*)(id, SEL))objc_msgSend)(d, @selector(connected));
}
static NSString *DMCCTBTDeviceName(id d) { id n = DMCall(d, @"name"); return [n isKindOfClass:[NSString class]] && [n length] ? MSBDShotBTName(n) : @"Unnamed Device"; }
static void DMCCTStateChanged(int what);
static void DMCCTBTSetPower(BOOL on) {
#if DEBUG
    if (gCCTFakeBT) { gCCTFakeBT = on ? 3 : 1; DMLog([NSString stringWithFormat:@"[cctiles] Bluetooth switched %@ (test state %d): nothing switched", on ? @"on" : @"off", gCCTFakeBT]); DMCCTStateChanged(kMSBDCCTRowBluetooth); return; }
#endif
    id bt = DMCCTBT();
    if (!bt) return;
    // (Settings' switch: the user's setting and the radio's power, as Bluetooth switches elsewhere do it -- not Control Center's "until tomorrow")
    BOOL e = ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(bt, NSSelectorFromString(@"setEnabled:"), on);
    BOOL p = ((BOOL (*)(id, SEL, BOOL))objc_msgSend)(bt, NSSelectorFromString(@"setPowered:"), on);
    DMLog([NSString stringWithFormat:@"[cctiles] Bluetooth switched %@ (enabled %d, powered %d)", on ? @"on" : @"off", e, p]);
}
static void DMCCTBTConnect(id d, BOOL connect) {
#if DEBUG
    if ([d isKindOfClass:[DMCCTFakeDevice class]]) { ((DMCCTFakeDevice *)d).connected = connect; DMLog([NSString stringWithFormat:@"[cctiles] test device %@ %@: nothing sent", DMWiFiTag(DMCCTBTDeviceName(d)), connect ? @"connected" : @"disconnected"]); DMCCTStateChanged(kMSBDCCTRowBluetooth); return; }
#endif
    DMLog([NSString stringWithFormat:@"[cctiles] Bluetooth device %@: %@", DMWiFiTag(DMCCTBTDeviceName(d)), connect ? @"connect" : @"disconnect"]);
    ((void (*)(id, SEL))objc_msgSend)(d, connect ? @selector(connect) : @selector(disconnect));
}

// ---- Airplane Mode (AppSupport's RadiosPreferences: what Control Center's own Airplane Mode button uses) ---------------------------------------
// As Apple's Connectivity module does it (CCUIConnectivityAirplaneViewController, read in 17.5.1's own cache, 3 Nov): one RadiosPreferences made
// with a serial queue (-initWithQueue:) and every call on that queue; while Control Center shows it tells of a change (-refresh, then
// -setDelegate:, its -airplaneModeChanged on that queue) and is asked once, while closed it tells nothing (-setDelegate: nil); the round button
// sets -setAirplaneMode: to the opposite of what shows (RadiosPreferences itself mirrors it to a paired watch where that is on, as for Apple's
// button). The queue is the tiles' own (DMCCTQueue): no call into configd on SpringBoard's main thread. The row shows the last answer.
@protocol DMCCTRadios <NSObject>   // (RadiosPreferences' calls we make, with kDMCCTNeeds' types: declared for ARC's init ownership)
- (id)initWithQueue:(dispatch_queue_t)queue;
- (BOOL)airplaneMode;
- (void)setAirplaneMode:(BOOL)on;
- (void)refresh;
- (void)setDelegate:(id)delegate;
@end
@interface DMCCTAirplaneDelegate : NSObject
@end
static dispatch_queue_t DMCCTQueue(void);
static id<DMCCTRadios> gCCTRadios;        // (our queue only)
static DMCCTAirplaneDelegate *gCCTAirplaneDelegate;
static int gCCTAirplaneOn = -1;           // (the last answer, the main thread's: -1 none yet, 0 off, 1 on)
static void DMCCTAirplaneRead(NSString *why);
// (it answers only what it implements: -airplaneModeChanged, the one delegate method Apple's own button has -- CCUIConnectivityAirplaneViewController,
//  17.5.1's cache. It used to answer every selector with a no-argument void signature and drop the message: a call that returns a value would have
//  read garbage, and an unknown one never raised -- code review 1.8.0, 10)
@implementation DMCCTAirplaneDelegate
- (void)airplaneModeChanged { DMCCTAirplaneRead(@"it changed"); }
@end
static id<DMCCTRadios> DMCCTRadiosNow(void) {   // (our queue only: made the first time, kept)
    if (gCCTRadios || !gCCTPart[kDMCCTPartAirplane]) return gCCTRadios;
    @try {
        gCCTRadios = [(id<DMCCTRadios>)[objc_getClass("RadiosPreferences") alloc] initWithQueue:DMCCTQueue()];
        if (gCCTRadios && !gCCTAirplaneDelegate) gCCTAirplaneDelegate = [DMCCTAirplaneDelegate new];
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode's preferences not made: %@", e.reason]); gCCTRadios = nil; }
    DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode's preferences %@", gCCTRadios ? @"made" : @"NOT made"]);
    return gCCTRadios;
}
static int DMCCTAirplaneState(void) {   // (-1 not known)
#if DEBUG
    if (gCCTFakeAirplane >= 0) return gCCTFakeAirplane;
#endif
    return gCCTPart[kDMCCTPartAirplane] ? gCCTAirplaneOn : -1;
}
// An answer, on the main thread: the row shows it at once while Control Center shows, else at the next presentation.
static void DMCCTConnShow(void);
static void DMCCTAirplaneGot(int on, NSString *why) {
    if (on == gCCTAirplaneOn) return;
    gCCTAirplaneOn = on;
    DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode %@ (%@)", on ? @"on" : @"off", why]);
    DMCCTConnShow();
}
static void DMCCTAirplaneRead(NSString *why) {   // (any thread: asked on our queue)
    if (!gCCTPart[kDMCCTPartAirplane]) return;
    dispatch_async(DMCCTQueue(), ^{
        id<DMCCTRadios> p = DMCCTRadiosNow();
        if (!p) return;
        int on = [p airplaneMode] ? 1 : 0;
        dispatch_async(dispatch_get_main_queue(), ^{ DMCCTAirplaneGot(on, why); });
    });
}
// Control Center shows: told of a change from now on (what changed while it was closed first: -refresh) and asked once (Apple's
// -startObservingStateChanges and -_updateState); closed: told nothing (its -stopObservingStateChanges).
static void DMCCTAirplaneWatch(BOOL watch) {
    if (!gCCTPart[kDMCCTPartAirplane]) return;
    dispatch_async(DMCCTQueue(), ^{
        id<DMCCTRadios> p = DMCCTRadiosNow();
        if (!p) return;
        if (!watch) { [p setDelegate:nil]; return; }
        [p refresh];
        [p setDelegate:gCCTAirplaneDelegate];
        int on = [p airplaneMode] ? 1 : 0;
        dispatch_async(dispatch_get_main_queue(), ^{ DMCCTAirplaneGot(on, @"Control Center shows"); });
    });
}
// The round button (Apple's -_toggleState): the opposite of what shows, shown at once; the answer follows (its delegate tells, and it is asked again).
static void DMCCTAirplaneSet(BOOL on) {
#if DEBUG
    if (gCCTFakeAirplane >= 0) { gCCTFakeAirplane = on ? 1 : 0; DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode %@ (test state): nothing switched", on ? @"on" : @"off"]); DMCCTConnShow(); return; }
#endif
    if (!gCCTPart[kDMCCTPartAirplane] || gCCTAirplaneOn < 0) return;
    DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode switched %@", on ? @"on" : @"off"]);
    gCCTAirplaneOn = on ? 1 : 0;
    dispatch_async(DMCCTQueue(), ^{
        id<DMCCTRadios> p = DMCCTRadiosNow();
        if (!p) return;
        [p setAirplaneMode:on];
        int now = [p airplaneMode] ? 1 : 0;
        dispatch_async(dispatch_get_main_queue(), ^{ DMCCTAirplaneGot(now, @"switched"); });
    });
}

// ---- the brightness and the volume -------------------------------------------------------------------------------------------------------
static id gCCTBrightCtl;
static double DMCCTBrightness(void) { return [UIScreen mainScreen].brightness; }
static void DMCCTSetBrightness(double v) {
    if (!gCCTPart[kDMCCTPartBright]) return;
    if (!gCCTBrightCtl) gCCTBrightCtl = [objc_getClass("SBDisplayBrightnessController") new];
    ((BOOL (*)(id, SEL, float, BOOL))objc_msgSend)(gCCTBrightCtl, NSSelectorFromString(@"setBrightnessLevel:animated:"), (float)MSBDCCTClamp01(v), NO);
}
// The volume: asked and set on a queue of ours, never on the main thread (each is a call into mediaserverd: 7.8 ms on the 17.5, 1.8.0~t01), so a
// presentation shows the last level known (the system's own notification, or the last answer) and asks again behind it; a slider's drag sends
// only its latest value, one call at a time.
static dispatch_queue_t DMCCTQueue(void);
static double gCCTVolume = -1;           // (the last level known; -1 none yet)
static double gCCTVolumeWant = -1;       // (a level to send; -1 none waiting)
static BOOL gCCTVolumeSending = NO;
static id DMCCTAV(void) { return gCCTPart[kDMCCTPartVolume] ? ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("AVSystemController"), NSSelectorFromString(@"sharedAVSystemController")) : nil; }
static double DMCCTVolumeNow(BOOL *ok) {   // (our queue only)
    id av = DMCCTAV(); float v = 0; NSString *name = nil;
    BOOL got = av && ((BOOL (*)(id, SEL, float *, NSString **))objc_msgSend)(av, NSSelectorFromString(@"getActiveCategoryVolume:andName:"), &v, &name);
    if (ok) *ok = got;
    return got ? v : 0.0;
}
static void DMCCTVolumeAsk(void (^done)(double v, BOOL ok)) {
    dispatch_async(DMCCTQueue(), ^{
        BOOL ok = NO; double v = DMCCTVolumeNow(&ok);
        dispatch_async(dispatch_get_main_queue(), ^{ if (ok) gCCTVolume = v; if (done) done(v, ok); });
    });
}
static double DMCCTVolume(BOOL *ok) { if (ok) *ok = gCCTVolume >= 0; return gCCTVolume >= 0 ? gCCTVolume : 0.0; }
static os_unfair_lock gCCTVolumeLock = OS_UNFAIR_LOCK_INIT;   // (gCCTVolumeWant and gCCTVolumeSending, between the main thread and our queue)
static void DMCCTSetVolume(double v) {
    double want = MSBDCCTClamp01(v);
    gCCTVolume = want;
    os_unfair_lock_lock(&gCCTVolumeLock);
    BOOL start = !gCCTVolumeSending;
    gCCTVolumeWant = want;
    if (start) gCCTVolumeSending = YES;
    os_unfair_lock_unlock(&gCCTVolumeLock);
    if (!start) return;   // (the call under way sends this one next)
    dispatch_async(DMCCTQueue(), ^{
        for (;;) {
            os_unfair_lock_lock(&gCCTVolumeLock);
            double next = gCCTVolumeWant; gCCTVolumeWant = -1;
            if (next < 0) gCCTVolumeSending = NO;
            os_unfair_lock_unlock(&gCCTVolumeLock);
            if (next < 0) return;
            id av = DMCCTAV();
            if (av) ((BOOL (*)(id, SEL, float))objc_msgSend)(av, NSSelectorFromString(@"setActiveCategoryVolumeTo:"), (float)next);
        }
    });
}

// ---- the slider (Display, Sound) -----------------------------------------------------------------------------------------------------------
// macOS's: a capsule track, the white fill up to a white knob as tall as the track, a symbol at its leading end. A drag moves it by the distance
// moved (the knob does not jump), a tap sets it where tapped. Its drag is one of the panel's blocking gestures: the panel's swipe up and its scroll
// wait for it. For assistive features it is one adjustable element (its tile's name, the value in per cent, 1/16 a step) with a Show Details action.
@interface DMCCTSlider : UIView <UIGestureRecognizerDelegate>
@property (nonatomic) double value;
@property (nonatomic, readonly) BOOL tracking;
@property (nonatomic, copy) void (^onChange)(double value, BOOL done);
@property (nonatomic, copy) NSString *axName;
@property (nonatomic, copy) void (^onDetails)(void);
@property (nonatomic, strong) UIImageView *symbolView;
@property (nonatomic, strong) UIPanGestureRecognizer *drag;
- (void)dm_setValue:(double)v;
@end
@implementation DMCCTSlider {
    UIView *_track, *_fill, *_knob;
    double _startValue;
    BOOL _tracking;
}
- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    _track = [UIView new]; _fill = [UIView new]; _knob = [UIView new];
    _track.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1.0 alpha:0.16] : [UIColor colorWithWhite:0.0 alpha:0.10];
    }];
    _fill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    _knob.backgroundColor = [UIColor whiteColor];
    _knob.layer.shadowColor = [UIColor blackColor].CGColor; _knob.layer.shadowOpacity = 0.28; _knob.layer.shadowRadius = 2.0; _knob.layer.shadowOffset = CGSizeMake(0, 0.5);
    for (UIView *v in @[_track, _fill, _knob]) { v.userInteractionEnabled = NO; v.layer.cornerCurve = kCACornerCurveCircular; [self addSubview:v]; }
    _track.clipsToBounds = YES; [_fill removeFromSuperview]; [_track addSubview:_fill];
    _symbolView = [UIImageView new]; _symbolView.contentMode = UIViewContentModeCenter; _symbolView.userInteractionEnabled = NO;
    [self addSubview:_symbolView];   // (above the knob: at the low end the symbol sits in it, as macOS's)
    _drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dm_drag:)]; _drag.delegate = self; _drag.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:_drag];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dm_tap:)];
    [self addGestureRecognizer:tap];
    self.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    self.isAccessibilityElement = YES;
    return self;
}
- (BOOL)tracking { return _tracking; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    _track.frame = b; _track.layer.cornerRadius = b.size.height / 2.0;
    _knob.bounds = CGRectMake(0, 0, b.size.height, b.size.height); _knob.layer.cornerRadius = b.size.height / 2.0;
    CGSize s = _symbolView.image.size;
    _symbolView.frame = CGRectMake(b.size.height * 0.30, (b.size.height - s.height) / 2.0, MAX(s.width, 1), s.height);
    [self dm_place];
}
- (void)dm_place {
    CGRect b = self.bounds;
    double d = b.size.height, kx = MSBDCCTSliderKnobX(_value, 0, b.size.width, d);
    _knob.center = CGPointMake(kx, b.size.height / 2.0);
    _fill.frame = CGRectMake(0, 0, MIN(b.size.width, kx + d / 2.0), b.size.height);
    _fill.layer.cornerRadius = d / 2.0;
    BOOL covered = kx + d / 2.0 > _symbolView.frame.origin.x;   // (the white fill or knob under the symbol: dark, else on the track: the label's)
    _symbolView.tintColor = covered ? [UIColor colorWithWhite:0.0 alpha:0.55] : [UIColor secondaryLabelColor];
}
- (void)dm_setValue:(double)v {   // (from the system: not while a finger moves it)
    if (_tracking) return;
    _value = MSBDCCTClamp01(v);
    [self dm_place];
}
- (void)dm_set:(double)v done:(BOOL)done {
    _value = MSBDCCTClamp01(v);
    [self dm_place];
    if (self.onChange) self.onChange(_value, done);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (g != _drag) return YES;
    CGPoint v = [_drag velocityInView:self];
    return fabs(v.x) >= fabs(v.y);   // (sideways: the slider's; up or down: the panel's swipe and scroll)
}
- (void)dm_drag:(UIPanGestureRecognizer *)g {
    CGFloat w = self.bounds.size.width, d = self.bounds.size.height;
    if (g.state == UIGestureRecognizerStateBegan) { _tracking = YES; _startValue = _value; }
    double v = MSBDCCTSliderDragged(_startValue, [g translationInView:self].x, 0, w, d);
    BOOL end = g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed;
    if (end) _tracking = NO;
    [self dm_set:v done:end];
}
- (void)dm_tap:(UITapGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    [self dm_set:MSBDCCTSliderValueAt([g locationInView:self].x, 0, self.bounds.size.width, self.bounds.size.height) done:YES];
}
- (NSString *)accessibilityLabel { return self.axName; }
- (NSString *)accessibilityValue { return [NSString stringWithFormat:@"%d%%", MSBDCCTPercent(_value)]; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitAdjustable; }
- (void)accessibilityIncrement { [self dm_set:MSBDCCTSliderStep(_value, 1, 16) done:YES]; }
- (void)accessibilityDecrement { [self dm_set:MSBDCCTSliderStep(_value, 0, 16) done:YES]; }
- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {
    if (!self.onDetails) return nil;
    __weak DMCCTSlider *weakSelf = self;
    return @[[[UIAccessibilityCustomAction alloc] initWithName:@"Show Details" actionHandler:^BOOL(UIAccessibilityCustomAction *a) { if (weakSelf.onDetails) weakSelf.onDetails(); return YES; }]];
}
@end

// ---- the tiles: shared ---------------------------------------------------------------------------------------------------------------------
@interface DMCCTTile : NSObject <DMCCTile>
@property (nonatomic) int role;
@property (nonatomic, copy) NSString *tid;
@property (nonatomic, strong) UIView *view;
@property (nonatomic) BOOL old;      // its state changed while Control Center was closed: read at the next presentation
@property (nonatomic) BOOL locked;
@property (nonatomic) CGFloat scale;
- (void)dm_refresh;                  // its state read and shown (at a presentation, and while it shows when something changed)
@end
@implementation DMCCTTile
- (int)tileRole { return _role; }
- (NSString *)tileID { return _tid; }
- (UIView *)tileView { return _view; }
- (void)dm_refresh {}
// Read at each presentation: SpringBoard's own cached Wi-Fi values, BluetoothManager's, Airplane Mode's last answer (asked again then, off the main
// thread), the brightness and the volume change without a word to us now and then (Auto-Brightness, another app); Now Playing only when told it
// changed (its answer comes from mediaremoted).
- (void)tileWillPresent { [self dm_refresh]; _old = NO; }
- (void)tileLockedChanged:(BOOL)locked { _locked = locked; }
@end
static NSHashTable<DMCCTTile *> *gCCTTiles;   // (ours, weak: CCPanel.h's gCCPTiles holds them)
static DMCCTTile *DMCCTTileOf(int role) { for (DMCCTTile *t in gCCTTiles) if (t.role == role) return t; return nil; }
// (15-17: one tile of a role. 18: one per module instance -- CC18Tiles.h --, the gallery's preview of it too: each is told)
static NSArray<DMCCTTile *> *DMCCTTilesOf(int role) { NSMutableArray *a = [NSMutableArray array]; for (DMCCTTile *t in gCCTTiles) if (t.role == role) [a addObject:t]; return a; }

// ---- Connectivity --------------------------------------------------------------------------------------------------------------------------
// A row: its round button (the switch), its name, its line and, with a page, a chevron; a tap on the button switches, a tap elsewhere opens its
// page -- a row without a page (Airplane Mode) takes only its button's touches, as Apple's. One assistive element: "Wi-Fi", "On, <network>", a
// button that switches; its Show Details action opens the page ("Airplane Mode", "On": no action).
@interface DMCCTConnRow : UIControl
@property (nonatomic) int kind;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UIImageView *glyph, *chevron;
@property (nonatomic, strong) UILabel *title, *line;
@property (nonatomic) BOOL on, usable;
@property (nonatomic) MSBDCCTConnRow frames;
@property (nonatomic, copy) void (^onToggle)(void);
@property (nonatomic, copy) void (^onDetails)(void);
@end
@implementation DMCCTConnRow {
    BOOL _inCircle;
}
- (instancetype)initWithKind:(int)kind {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _kind = kind; _usable = YES;
    _circle = [UIView new]; _circle.userInteractionEnabled = NO;
    _glyph = [UIImageView new]; _glyph.contentMode = UIViewContentModeCenter; _glyph.userInteractionEnabled = NO;
    _title = [UILabel new]; _title.text = kind == kMSBDCCTRowAirplane ? @"Airplane Mode" : kind == kMSBDCCTRowWiFi ? @"Wi-Fi" : @"Bluetooth";
    _title.adjustsFontSizeToFitWidth = YES; _title.minimumScaleFactor = 0.75;   // (the block's names share one size, MSBDCCTTextFit: this only below its floor)
    _line = [UILabel new]; _line.lineBreakMode = NSLineBreakByTruncatingTail;
    _chevron = [UIImageView new]; _chevron.contentMode = UIViewContentModeCenter; _chevron.userInteractionEnabled = NO;
    _chevron.hidden = !MSBDCCTRowHasPage(kind);
    for (UIView *v in @[_circle, _title, _line, _chevron]) [self addSubview:v];
    [_circle addSubview:_glyph];
    [self addTarget:self action:@selector(dm_up:forEvent:) forControlEvents:UIControlEventTouchUpInside];
    self.isAccessibilityElement = YES;
    return self;
}
// Its parts: f at size 1 in the block's space (MSBDCCTConnLayout), put at the panel's size s; k Menu Bar Size's scale, fit the names' and lines'
// share of their size (MSBDCCTTextFit).
- (void)dm_layoutWith:(MSBDCCTConnRow)f scale:(CGFloat)k fit:(CGFloat)fit size:(CGFloat)s {
    _frames = f;
    CGFloat y0 = f.row.origin.y;
    _circle.frame = MSBDCCScaleRect(CGRectOffset(f.circle, 0, -y0), s); _circle.layer.cornerRadius = _circle.frame.size.width / 2.0;
    _glyph.frame = _circle.bounds;
    _title.frame = MSBDCCScaleRect(CGRectOffset(f.title, 0, -y0), s); _line.frame = MSBDCCScaleRect(CGRectOffset(f.line, 0, -y0), s);
    _chevron.frame = MSBDCCScaleRect(CGRectOffset(f.chevron, 0, -y0), s);
    _title.font = [UIFont systemFontOfSize:round(13.0 * k) * fit * s weight:UIFontWeightSemibold];
    _line.font = [UIFont systemFontOfSize:round(11.0 * k) * MSBDCCTLineFit(fit) * s];
    _chevron.image = MSBDCCTRowHasPage(_kind) ? DMCCTSymbol(@"chevron.right", round(9.0 * k) * s, UIImageSymbolWeightSemibold) : nil;
    CGFloat gh = round(f.circle.size.height * 0.5) * s;
    _glyph.image = _kind == kMSBDCCTRowBluetooth ? DMCCTBluetoothGlyph(gh) : DMCCTSymbol(_kind == kMSBDCCTRowAirplane ? @"airplane" : @"wifi", round(gh * 0.82), UIImageSymbolWeightSemibold);
    [self dm_look];
}
- (void)dm_look {
    UIColor *onColor = MSBDCCTRowTint(_kind) == kMSBDCCTTintOrange ? [UIColor systemOrangeColor] : [UIColor systemBlueColor];   // (Airplane Mode: Apple's orange)
    _circle.backgroundColor = _on ? onColor : DMCCTOffCircleColor();
    _glyph.tintColor = _on ? [UIColor whiteColor] : [UIColor labelColor];
    _title.textColor = [UIColor labelColor]; _line.textColor = [UIColor secondaryLabelColor]; _chevron.tintColor = [UIColor tertiaryLabelColor];
    self.alpha = self.highlighted ? 0.6 : 1.0;
}
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self dm_look]; }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {   // (a row without a page: only its button, the rest of it is the block's -- a hold there)
    if (MSBDCCTRowHasPage(_kind)) return [super pointInside:p withEvent:e];
    return CGRectContainsPoint(CGRectInset(_circle.frame, -6.0, -6.0), p);
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    CGRect c = CGRectInset(_circle.frame, -6.0, -6.0);
    _inCircle = CGRectContainsPoint(c, [t locationInView:self]);
    return [super beginTrackingWithTouch:t withEvent:e];
}
- (void)dm_up:(id)sender forEvent:(UIEvent *)e {
    DMLog([NSString stringWithFormat:@"[cctiles] %@ row tapped (%@)", _title.text, _inCircle ? @"its button" : @"its page"]);
    if (_inCircle) { if (self.onToggle) self.onToggle(); }
    else if (self.onDetails) self.onDetails();
}
- (NSString *)accessibilityLabel { return _title.text; }
- (NSString *)accessibilityValue { return _line.text.length ? (_on && ![_line.text isEqualToString:@"On"] ? [NSString stringWithFormat:@"On, %@", _line.text] : _line.text) : nil; }
- (UIAccessibilityTraits)accessibilityTraits { return UIAccessibilityTraitButton | (_usable ? 0 : UIAccessibilityTraitNotEnabled); }
- (NSString *)accessibilityHint { return [NSString stringWithFormat:@"Switches %@ on or off.", _title.text]; }
- (BOOL)accessibilityActivate { if (!_usable || !self.onToggle) return NO; self.onToggle(); return YES; }
- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {
    if (!self.onDetails) return nil;   // (no page)
    __weak DMCCTConnRow *weakSelf = self;
    return @[[[UIAccessibilityCustomAction alloc] initWithName:@"Show Details" actionHandler:^BOOL(UIAccessibilityCustomAction *a) { if (weakSelf.onDetails) weakSelf.onDetails(); return weakSelf.onDetails != nil; }]];
}
@end

@interface DMCCTConnectivityTile : DMCCTTile
@property (nonatomic, strong) NSArray<DMCCTConnRow *> *rows;
@property (nonatomic) int page;                 // the page open (or about to): a row's kind; -1 none
@property (nonatomic, strong) DMCCTPageView *pageView;
@property (nonatomic, copy) NSString *pageSig;  // (what the open page shows: filled again only when this changes)
- (void)dm_openPage:(int)kind;
- (void)dm_pageChanged;
@end
static __weak DMCCTConnectivityTile *gCCTConn;
static BOOL gCCTPageRebuildDue = NO;
static unsigned gCCTChanged = 0;   // (what changed since the last look, 1 << a row's kind: its page is made again only then)
static void DMCCTWiFiPageItems(NSArray **itemsOut, NSString **sigOut) {
    __block NSString *sig = nil;
    *itemsOut = DMCCTRows(^NSArray *{ return DMWiFiMenuItems(&sig); });
    *sigOut = sig;
}
// A device's row: DMRow logs the tapped row's title; a device's name never goes to the log (a short hash, as a network's).
@interface DMCCTDeviceRow : DMRow
@end
@implementation DMCCTDeviceRow
- (void)fire:(id)sender forEvent:(UIEvent *)event {
    DMLog([NSString stringWithFormat:@"[row] device row tapped %@", DMWiFiTag(self.label.text)]);
    if (self.handler) self.handler();
}
@end
// Bluetooth's page: the switch, the paired devices (connected ones ticked; a tap connects or disconnects, the page stays), Bluetooth Settings….
static NSArray *DMCCTBTPageItems(NSString **sigOut) {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableString *sig = [NSMutableString string];
    BOOL powered = DMCCTBTPowered(), avail = DMCCTBTAvailable();
    if (gCCTPart[kDMCCTPartBT]) [items addObject:[[DMCCTSwitchRow alloc] initWithTitle:@"Bluetooth" on:powered enabled:avail onChange:^(BOOL on) { DMCCTBTSetPower(on); }]];   // (without the manager: only Settings' row)
    [sig appendFormat:@"p%d%d|", powered, avail];
    NSArray *devices = powered ? DMCCTBTDevices(NO) : @[];
    if (devices.count) {
        [items addObject:[NSNull null]];
        [items addObject:[[DMWiFiHeaderRow alloc] initWithTitle:@"Devices"]];
        for (id d in devices) {
            BOOL c = DMCCTBTDeviceConnected(d);
            NSString *name = DMCCTBTDeviceName(d);
            DMRow *r = [[DMCCTDeviceRow alloc] initWithTitle:name enabled:YES handler:^{ DMCCTBTConnect(d, !DMCCTBTDeviceConnected(d)); }];
            r.checked = c;
            [items addObject:r];
            [sig appendFormat:@"%@%d|", name, c];
        }
    } else if (powered && !gCCTPart[kDMCCTPartBTDevices]) [sig appendString:@"nodev|"];
    if (items.count) [items addObject:[NSNull null]];
    [items addObject:[[DMRow alloc] initWithTitle:@"Bluetooth Settings…" enabled:!DMRowsHostLocked() handler:DMCloseThen(^{ DMOpenURL(@"prefs:root=Bluetooth", @"bluetooth settings"); })]];
    if (sigOut) *sigOut = sig;
    return items;
}
@implementation DMCCTConnectivityTile
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.role = MSBDCCRoleTileConnectivity; self.tid = @"mac.connectivity"; self.page = -1;
    self.view = DMCCTPlatter();
    NSMutableArray *rows = [NSMutableArray array];
    __weak DMCCTConnectivityTile *weakSelf = self;
    for (int k = 0; k < kMSBDCCTRows; k++) {
        DMCCTConnRow *r = [[DMCCTConnRow alloc] initWithKind:k];
        r.onToggle = ^{ [weakSelf dm_toggle:k]; };
        if (MSBDCCTRowHasPage(k)) r.onDetails = ^{ [weakSelf dm_openPage:k]; };
        [self.view addSubview:r];
        [rows addObject:r];
    }
    self.rows = rows;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dm_hold:)];
    hold.minimumPressDuration = 0.45;
    [self.view addGestureRecognizer:hold];
    return self;
}
// Laid out at size 1 (the tile's bounds over the panel's size) and put at the size; the three names at the one size that fits the longest
// (MSBDCCTTextFit: measured at their own size, 13 pt x k).
- (void)tileLayoutInBounds:(CGRect)b scale:(CGFloat)k {
    self.scale = k;
    self.view.layer.cornerRadius = DMCCTCorner();
    CGFloat s = DMCCTSize();
    double w = b.size.width / s, h = b.size.height / s;
    MSBDCCTConnRow f[kMSBDCCTRows];
    MSBDCCTConnLayout(w, h, k, 1.0, f);
    double natural[kMSBDCCTRows];
    UIFont *font = [UIFont systemFontOfSize:round(13.0 * k) weight:UIFontWeightSemibold];
    for (int i = 0; i < kMSBDCCTRows; i++) natural[i] = ceil([self.rows[i].title.text sizeWithAttributes:@{ NSFontAttributeName: font }].width);
    double fit = MSBDCCTTextFit(natural, f);
    if (fit < 1.0) MSBDCCTConnLayout(w, h, k, fit, f);
    for (int i = 0; i < kMSBDCCTRows; i++) { self.rows[i].frame = DMCCTAt(f[i].row); [self.rows[i] dm_layoutWith:f[i] scale:k fit:fit size:s]; }
#if DEBUG
    DMLog([NSString stringWithFormat:@"[cctiles] Connectivity laid out: %.0f x %.0f at size %.2f, the names at %.2f of %.0f pt (Airplane Mode %.0f pt for %.0f)", b.size.width, b.size.height, s, fit, round(13.0 * k),
        f[kMSBDCCTRowAirplane].title.size.width, natural[kMSBDCCTRowAirplane]]);
#endif
}
- (void)dm_hold:(UILongPressGestureRecognizer *)g {   // (Apple's own Connectivity module expanded: AirDrop, Cellular, Personal Hotspot, Airplane Mode)
    if (g.state != UIGestureRecognizerStateBegan) return;
    BOOL opened = DMCCPanelExpandModule(@"com.apple.control-center.ConnectivityModule");
    DMLog([NSString stringWithFormat:@"[cctiles] Connectivity held: Apple's module %@", opened ? @"opened from it" : @"not there"]);
}
- (void)dm_refresh {
    CFTimeInterval t0 = CACurrentMediaTime();
    DMCCTConnRow *a = self.rows[kMSBDCCTRowAirplane], *w = self.rows[kMSBDCCTRowWiFi], *b = self.rows[kMSBDCCTRowBluetooth];
    int ap = DMCCTAirplaneState();   // (the last answer: no call here, CCTiles.h's Airplane Mode)
    int al = MSBDCCTAirplaneLine(ap >= 0, ap == 1);
    a.on = al == 1; a.usable = al != 3;
    a.line.text = al == 1 ? @"On" : al == 0 ? @"Off" : @"Unavailable";
    CFTimeInterval ta = CACurrentMediaTime();
    BOOL pw = DMWiFiPowered(), as = pw && DMWiFiAssociated();
    NSString *net = as ? DMWiFiCurrentName() : nil;
    CFTimeInterval tw = CACurrentMediaTime();
    int wl = MSBDCCTWiFiLine(pw, as, net.length > 0);
    w.on = pw; w.usable = YES;
    w.line.text = wl == 2 ? MSBDShotWiFiName(net) : wl == 1 ? @"Not Connected" : @"Off";
    int bl = MSBDCCTBluetoothLine(gCCTPart[kDMCCTPartBT] && DMCCTBTAvailable(), DMCCTBTPowered());
    b.on = bl == 1; b.usable = bl != 3;
    b.line.text = bl == 1 ? @"On" : bl == 0 ? @"Off" : @"Unavailable";
    CFTimeInterval tb = CACurrentMediaTime();
    for (DMCCTConnRow *r in self.rows) [r dm_look];
    CFTimeInterval tr = CACurrentMediaTime();
    unsigned changed = gCCTChanged; gCCTChanged = 0;
    if (self.page >= 0 && self.pageView && (changed & (1u << self.page))) [self dm_pageChanged];   // (a page follows a change of its own kind only)
#if DEBUG
    static NSString *lastSig;   // (logged when what it shows changed: a log line costs more than the reads, debug builds)
    NSString *sig = [NSString stringWithFormat:@"%d%d%d%@%@", ap, pw, as, DMWiFiTag(net), b.line.text];
    if (![sig isEqualToString:lastSig]) {
        lastSig = sig;
        DMLog([NSString stringWithFormat:@"[cctiles] Connectivity: Airplane Mode %@, Wi-Fi %d/%d %@, Bluetooth %@ (%.2f ms, its rows %.2f: Airplane Mode %.2f, Wi-Fi %.2f, Bluetooth %.2f)", a.line.text, pw, as, DMWiFiTag(net), b.line.text,
            (CACurrentMediaTime() - t0) * 1000.0, (tr - t0) * 1000.0, (ta - t0) * 1000.0, (tw - ta) * 1000.0, (tb - tw) * 1000.0]);
    }
#else
    (void)t0; (void)tr; (void)tw; (void)tb; (void)ta;
#endif
}
- (void)dm_toggle:(int)k {
    if (k == kMSBDCCTRowAirplane) {
        int now = DMCCTAirplaneState();
        if (now < 0) {   // (not read on this iPadOS, or not yet: Apple's own button, in its module)
            BOOL opened = DMCCPanelExpandModule(@"com.apple.control-center.ConnectivityModule");
            DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode not known here: Apple's Connectivity %@", opened ? @"opened instead" : @"not there"]);
            return;
        }
        DMCCTAirplaneSet(!now);
    } else if (k == kMSBDCCTRowWiFi) DMCCTWiFiToggle();
    else {
        if (!gCCTPart[kDMCCTPartBT]) { [self dm_openPage:k]; return; }   // (no switch of ours here: the page's Settings row)
        if (DMCCTBTAvailable()) DMCCTBTSetPower(!DMCCTBTPowered());
    }
    [self dm_refresh];
}
- (void)dm_openPage:(int)kind {
    if (!MSBDCCTRowHasPage(kind) || gCCPDetail || gCCPExpanded) return;   // (a row without one; a page or one of Apple's expanded modules is open: one at a time)
    if (kind == kMSBDCCTRowWiFi && !(gWiFiMenuOn && DMWiFiSupported())) {   // (the Wi-Fi menu switched off, or its list not here: Apple's own module)
        BOOL opened = DMCCPanelExpandModule(@"com.apple.control-center.ConnectivityModule");
        DMLog([NSString stringWithFormat:@"[cctiles] Wi-Fi page: the Wi-Fi Menu is off here, Apple's Connectivity %@", opened ? @"opened instead" : @"not there"]);
        return;
    }
    self.page = kind;
    gCCTConn = self;   // (the tile with the page: the scan's watchdog and the list's changes ask it)
    DMCCPanelOpenDetail(self);
    if (!self.pageView) self.page = -1;   // (not opened: a module expanded, another page open)
}
- (UIView *)tileDetailViewForWidth:(CGFloat)width {
    NSArray *items = nil; NSString *sig = nil;
    if (self.page == kMSBDCCTRowWiFi) {
        DMWiFiListController();   // (made at the first page, as at the first menu: its cached results show at once)
        if (!gWiFiListing.records.count && [DMCall(gWiFiList, @"networks") isKindOfClass:[NSSet class]]) gWiFiListing.records = [DMCall(gWiFiList, @"networks") allObjects];
        gWiFiMenuOrder = nil; gWiFiLastOrder = nil;
        DMCCTWiFiPageItems(&items, &sig);
        gWiFiMenuOrder = [gWiFiLastOrder mutableCopy] ?: [NSMutableArray array];   // (the rows keep the order they opened in, as the menu's)
    } else if (self.page == kMSBDCCTRowBluetooth) items = DMCCTRows(^NSArray *{ NSString *s = nil; NSArray *i = DMCCTBTPageItems(&s); self.pageSig = s; return i; });
    if (!items) return nil;
    if (sig) self.pageSig = sig;
    self.pageView = DMCCTPageMake(items, width);
    if (self.page == kMSBDCCTRowWiFi) {
        DMWiFiStartScanning();   // (the watchdog keeps it only while the page shows, DMCCTWiFiPageShown, and 30 s at most)
        DMWiFiLogMenu(@"opened in Control Center");
    }
    DMLog([NSString stringWithFormat:@"[cctiles] %@ page made (%lu rows, %.0f pt)", [self tileDetailTitle], (unsigned long)items.count, self.pageView.frame.size.height]);
    return self.pageView;
}
- (NSString *)tileDetailTitle { return self.page == kMSBDCCTRowWiFi ? @"Wi-Fi" : @"Bluetooth"; }
- (BOOL)tileDetailNeedsUnlock { return NO; }   // (each page works on the Lock Screen; its rows that need Settings or our menu window are greyed there)
- (void)tileDetailDidClose {
    if (self.page == kMSBDCCTRowWiFi) { DMWiFiStopScanning(@"Control Center's Wi-Fi page closed"); gWiFiMenuOrder = nil; }
    self.page = -1; self.pageView = nil; self.pageSig = nil;
}
// What the open page shows changed (a scan's results, the switch, a device): filled again in place when its rows would differ.
- (void)dm_pageChanged {
    DMCCTPageView *pv = self.pageView;
    if (!pv.window || self.page < 0) return;
    NSArray *items = nil; __block NSString *sig = nil;
    CFTimeInterval t0 = CACurrentMediaTime();
    if (self.page == kMSBDCCTRowWiFi) {
        if (!gWiFiScanning && DMWiFiPowered() && CACurrentMediaTime() - gWiFiOpenedAt < 30.0) DMWiFiStartScanning();   // (Wi-Fi switched on from the page: the scan starts now)
        DMCCTWiFiPageItems(&items, &sig);
    } else if (self.page == kMSBDCCTRowBluetooth) items = DMCCTRows(^NSArray *{ NSString *s = nil; NSArray *i = DMCCTBTPageItems(&s); sig = s; return i; });
    else return;
    CFTimeInterval t1 = CACurrentMediaTime();
    if ([sig isEqualToString:self.pageSig]) { DMLog([NSString stringWithFormat:@"[cctiles] %@ page as it was (its rows made in %.2f ms)", [self tileDetailTitle], (t1 - t0) * 1000.0]); return; }
    self.pageSig = sig;
    CGFloat was = pv.frame.size.height;
    [pv dm_fill:items];
    CFTimeInterval t2 = CACurrentMediaTime();
    if (fabs(pv.frame.size.height - was) > 0.5) DMCCPanelDetailResized();
    DMLog([NSString stringWithFormat:@"[cctiles] %@ page updated (%lu rows: made %.2f ms, put in %.2f ms, the panel's height %.2f ms)", [self tileDetailTitle], (unsigned long)items.count,
        (t1 - t0) * 1000.0, (t2 - t1) * 1000.0, (CACurrentMediaTime() - t2) * 1000.0]);
}
- (void)tileDidDismiss { self.page = -1; }
@end
static BOOL DMCCTWiFiPageShown(void) { DMCCTConnectivityTile *c = gCCTConn; return c.page == kMSBDCCTRowWiFi && c.pageView.window != nil; }
// WiFiMenu.h's DMWiFiListChanged (the list, SpringBoard's Wi-Fi state): the open Wi-Fi page follows (at most once per 0.3 s, as the menu), the
// Connectivity row too while Control Center shows; closed, it only marks the tile's state old.
static void DMCCTWiFiListChanged(void) { DMCCTStateChanged(kMSBDCCTRowWiFi); }
// Airplane Mode's answer (its row has no page): shown at once while Control Center shows; closed, at the next presentation.
static void DMCCTConnShow(void) {
    for (DMCCTTile *c in DMCCTTilesOf(MSBDCCRoleTileConnectivity)) {
        if (!gCCTShown) { c.old = YES; continue; }
        [c dm_refresh];
    }
}
static void DMCCTStateChanged(int what) {   // (what: a row's kind, CCTileLogic.h kMSBDCCTRow... -- the Connectivity tile)
    NSArray<DMCCTTile *> *conn = DMCCTTilesOf(MSBDCCRoleTileConnectivity);
    if (!conn.count) return;
    if (!gCCTShown) { for (DMCCTTile *c in conn) c.old = YES; return; }
    gCCTChanged |= 1u << what;
    if (gCCTPageRebuildDue) return;
    gCCTPageRebuildDue = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        gCCTPageRebuildDue = NO;
        if (!gCCTShown) return;
        unsigned changed = gCCTChanged;   // (each tile takes it once: the one with a page follows it)
        for (DMCCTTile *c in DMCCTTilesOf(MSBDCCRoleTileConnectivity)) { gCCTChanged = changed; [c dm_refresh]; }
    });
}

// ---- Display and Sound -------------------------------------------------------------------------------------------------------------------
static NSArray *DMCC18DisplayRows(void);   // (iPadOS 18: Display's page, CC18Tiles.h)
// A wide tile: its title and chevron above the slider. Display's chevron and hold: Apple's Display module expanded from the tile; Sound's chevron:
// our Sound page, its hold Apple's volume module expanded.
@interface DMCCTWideTile : DMCCTTile
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UIImageView *chevronGlyph;
@property (nonatomic, strong) UIControl *chevron;   // (its touch area, larger than the glyph)
@property (nonatomic, strong) DMCCTSlider *slider;
@property (nonatomic, copy) NSString *module;   // the Apple module it stands for (its expanded view)
@property (nonatomic) BOOL usable;
@property (nonatomic, strong) DMCCTPageView *pageView;
@property (nonatomic, copy) NSString *pageSig;
@property (nonatomic) CFTimeInterval lastSet;
@property (nonatomic) int loggedPercent;   // (debug: the last level logged)
@property (nonatomic) BOOL warmed;         // (Sound: its four speakers made at the layout)
@end
@implementation DMCCTWideTile
- (instancetype)initWithRole:(int)role {
    if (!(self = [super init])) return nil;
    BOOL display = role == MSBDCCRoleTileDisplay;
    self.role = role; self.tid = display ? @"mac.display" : @"mac.sound";
    self.module = display ? @"com.apple.control-center.DisplayModule" : @"com.apple.mediaremote.controlcenter.audio";
    self.usable = gCCTPart[display ? kDMCCTPartBright : kDMCCTPartVolume];
    self.view = DMCCTPlatter();
    _title = [UILabel new]; _title.text = display ? @"Display" : @"Sound"; _title.textColor = [UIColor labelColor]; _title.isAccessibilityElement = NO;
    [self.view addSubview:_title];
    _chevronGlyph = [UIImageView new]; _chevronGlyph.contentMode = UIViewContentModeCenter; _chevronGlyph.userInteractionEnabled = NO; _chevronGlyph.tintColor = [UIColor secondaryLabelColor];
    [self.view addSubview:_chevronGlyph];
    _chevron = [UIControl new];
    _chevron.isAccessibilityElement = NO;   // (the slider's Show Details action stands for it)
    _chevron.accessibilityLabel = [_title.text stringByAppendingString:@" Details"];   // (Full Keyboard Access focuses the control itself: its name)
    __weak DMCCTWideTile *weakSelf = self;
    [_chevron addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf dm_details]; }] forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_chevron];
    _slider = [DMCCTSlider new];
    _slider.axName = _title.text;
    _slider.onChange = ^(double v, BOOL done) { [weakSelf dm_slid:v done:done]; };
    _slider.onDetails = ^{ [weakSelf dm_details]; };
    [self.view addSubview:_slider];
    DMCCPanelAddBlocking(_slider.drag);
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dm_hold:)];
    hold.minimumPressDuration = 0.45;
    [self.view addGestureRecognizer:hold];
    return self;
}
- (BOOL)dm_display { return self.role == MSBDCCRoleTileDisplay; }
- (void)tileLayoutInBounds:(CGRect)b scale:(CGFloat)k {   // (laid out at size 1, put at the panel's size: DMCCTSize)
    self.scale = k;
    self.view.layer.cornerRadius = DMCCTCorner();
    CGFloat s = DMCCTSize();
    MSBDCCTWideLayout L = MSBDCCTWideFrames(b.size.width / s, b.size.height / s, k);
    _title.frame = DMCCTAt(L.title); _title.font = [UIFont systemFontOfSize:round(13.0 * k) * s weight:UIFontWeightSemibold];
    _chevronGlyph.frame = DMCCTAt(L.chevron); _chevronGlyph.image = DMCCTSymbol(@"chevron.right", round(10.0 * k) * s, UIImageSymbolWeightSemibold);
    _chevron.frame = DMCCTAt(L.chevronHit);
    _slider.frame = DMCCTAt(L.slider);
    [self dm_symbol];
}
- (void)dm_symbol {
    CGFloat pt = MAX(8.0, round(_slider.bounds.size.height * 0.5));
    NSArray<NSString *> *speakers = @[@"speaker.slash.fill", @"speaker.wave.1.fill", @"speaker.wave.2.fill", @"speaker.wave.3.fill"];
    if (![self dm_display] && !self.warmed && _slider.bounds.size.height > 0) {   // (all four made at the layout, while the panel is hidden: none at a presentation)
        self.warmed = YES;
        for (NSString *n in speakers) (void)DMCCTSymbol(n, pt, UIImageSymbolWeightSemibold);
    }
    NSString *name = [self dm_display] ? @"sun.max.fill" : speakers[MSBDCCTVolumeWaves(_slider.value)];
    UIImage *img = DMCCTSymbol(name, pt, UIImageSymbolWeightSemibold);
    if (_slider.symbolView.image != img) { _slider.symbolView.image = img; [_slider setNeedsLayout]; }
}
- (void)dm_refresh {
    CFTimeInterval t0 = CACurrentMediaTime();
    BOOL ok = YES;
    double v = [self dm_display] ? DMCCTBrightness() : DMCCTVolume(&ok);
    if (![self dm_display] && gCCTPart[kDMCCTPartVolume]) {   // (the level known now; asked again off the main thread, the slider follows)
        __weak DMCCTWideTile *weakSelf = self;
        DMCCTVolumeAsk(^(double now, BOOL fine) { DMCCTWideTile *me = weakSelf; if (!me || !fine || me.slider.tracking || CACurrentMediaTime() - me.lastSet < 0.4) return; [me.slider dm_setValue:now]; [me dm_symbol]; });
        ok = YES;
    }
    if (!ok) self.usable = NO;
    _slider.userInteractionEnabled = self.usable;
    _slider.alpha = self.usable ? 1.0 : 0.45;
    [_slider dm_setValue:v];
    [self dm_symbol];
#if DEBUG
    if (MSBDCCTPercent(v) != self.loggedPercent) { self.loggedPercent = MSBDCCTPercent(v); DMLog([NSString stringWithFormat:@"[cctiles] %@: %d%% (%.2f ms)", self.tid, MSBDCCTPercent(v), (CACurrentMediaTime() - t0) * 1000.0]); }
#else
    (void)t0;
#endif
}
- (void)dm_slid:(double)v done:(BOOL)done {
    if (!self.usable) return;
#if DEBUG
    CFTimeInterval t0 = CACurrentMediaTime();
#endif
    if ([self dm_display]) DMCCTSetBrightness(v);
    else DMCCTSetVolume(v);
#if DEBUG
    static int logged = 0; if (logged++ < 6) DMLog([NSString stringWithFormat:@"[cctiles] %@ set on the main thread: %.2f ms", self.tid, (CACurrentMediaTime() - t0) * 1000.0]);
#endif
    self.lastSet = CACurrentMediaTime();
    [self dm_symbol];
    if (done) DMLog([NSString stringWithFormat:@"[cctiles] %@ set to %d%%", self.tid, MSBDCCTPercent(v)]);
}
- (void)dm_hold:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || _slider.tracking) return;
    if (DMCC18TilesAreOurs()) { [self dm_details]; return; }   // (iPadOS 18: its page; Apple's module is no tile of the Mac layout)
    BOOL opened = DMCCPanelExpandModule(self.module);
    DMLog([NSString stringWithFormat:@"[cctiles] %@ held: Apple's %@ %@", self.tid, self.module, opened ? @"opened from it" : @"not there"]);
}
- (void)dm_details {
    if (![self dm_display] || DMCC18TilesAreOurs()) { DMCCPanelOpenDetail(self); return; }   // (Sound's page; iPadOS 18: Display's too, CC18Tiles.h)
    BOOL opened = DMCCPanelExpandModule(self.module);
    DMLog([NSString stringWithFormat:@"[cctiles] Display's details: Apple's module %@", opened ? @"opened from it" : @"not there, Settings"]);
    if (!opened && !DMCCPanelLocked()) DMCCTCloseThen(^{ DMOpenURL(@"prefs:root=DISPLAY", @"display settings"); })();
}
// Sound's page: the Audio menu's rows (Audio Mixing, the apps that play), Sound Settings…; as the open menu, its rows are those of when it
// opened (an app's row follows whether it can be adjusted: DMAudioRefreshOpenRows).
- (NSArray *)dm_pageItems:(NSString **)sigOut {
    if ([self dm_display]) return DMCCTRows(^NSArray *{ return DMCC18DisplayRows(); });   // (iPadOS 18 only: tileDetailViewForWidth:)
    __block NSUInteger n = 0;
    NSArray *items = DMCCTRows(^NSArray *{
        NSMutableArray *it = [DMAudioMenuItems(&n) mutableCopy];
        [it addObject:[NSNull null]];
        [it addObject:[[DMRow alloc] initWithTitle:@"Sound Settings…" enabled:!DMRowsHostLocked() handler:DMCloseThen(^{ DMOpenURL(@"prefs:root=Sounds", @"sound settings"); })]];
        return it;
    });
    if (sigOut) *sigOut = [NSString stringWithFormat:@"%d|%@", DMMixAudioOn(), [DMAudioCandidateBundleIDs() componentsJoinedByString:@","]];
    return items;
}
- (UIView *)tileDetailViewForWidth:(CGFloat)width {
    if ([self dm_display] && !DMCC18TilesAreOurs()) return nil;
    NSString *sig = nil;
    NSArray *items = [self dm_pageItems:&sig];
    self.pageSig = sig;
    self.pageView = DMCCTPageMake(items, width);
    DMLog([NSString stringWithFormat:@"[cctiles] %@ page made (%lu rows)", [self tileDetailTitle], (unsigned long)items.count]);
    return self.pageView;
}
- (NSString *)tileDetailTitle { return [self dm_display] ? @"Display" : @"Sound"; }
- (void)tileDetailDidClose { self.pageView = nil; self.pageSig = nil; }
@end
// The system changed the brightness or the volume while Control Center shows (the keys, Auto-Brightness, another app): the slider follows,
// unless a finger is on it; closed, the tile is only marked old (it is read at each presentation anyway).
static void DMCCTLevelChanged(int role, double v, BOOL known) {
    for (DMCCTWideTile *t in (NSArray<DMCCTWideTile *> *)DMCCTTilesOf(role)) {
        if (CACurrentMediaTime() - t.lastSet < 0.4) continue;   // (our own set coming back)
        if (role == MSBDCCRoleTileSound) {   // (asked; the answer kept for the next presentation, shown now if Control Center shows)
            __weak DMCCTWideTile *weak = t;
            DMCCTVolumeAsk(^(double now, BOOL fine) { DMCCTWideTile *me = weak; if (fine && gCCTShown && me && !me.slider.tracking) { [me.slider dm_setValue:now]; [me dm_symbol]; } });
            continue;
        }
        if (!gCCTShown) { t.old = YES; continue; }
        [t.slider dm_setValue:known ? v : DMCCTBrightness()];
        [t dm_symbol];
    }
}

// ---- Now Playing -------------------------------------------------------------------------------------------------------------------------
// The artwork, the title and the artist (CCTileLogic.h MSBDCCTNowLines), play / pause and next. MediaRemote's answers come on a queue of ours;
// the artwork is decoded there (never on the main thread) and only when it is another picture (MediaRemote's artwork identifier, else its size).
@interface DMCCTNowPlayingTile : DMCCTTile
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *title, *line;
@property (nonatomic, strong) UIButton *play, *next;
@property (nonatomic, strong) UIControl *info;
@property (nonatomic) BOOL playing, hasApp, fetched;
@property (nonatomic, copy) NSString *artKey;
@property (nonatomic) unsigned gen;
@end
static dispatch_queue_t DMCCTQueue(void) {
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.cctiles", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)); });
    return q;
}
static UIImage *DMCCTArtPlaceholder(CGFloat side) {
    UIImage *n = DMCCTSymbol(@"music.note", round(side * 0.42), UIImageSymbolWeightMedium);
    return [n imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}
@implementation DMCCTNowPlayingTile
- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.role = MSBDCCRoleTileNowPlaying; self.tid = @"mac.nowplaying";
    self.view = DMCCTPlatter();
    _info = [UIControl new];
    _info.isAccessibilityElement = YES; _info.accessibilityTraits = UIAccessibilityTraitButton;
    _info.accessibilityHint = @"Opens the player.";
    __weak DMCCTNowPlayingTile *weakSelf = self;
    [_info addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf dm_open]; }] forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_info];
    _art = [UIImageView new]; _art.contentMode = UIViewContentModeCenter; _art.clipsToBounds = YES; _art.layer.cornerRadius = 6.0; _art.layer.cornerCurve = kCACornerCurveContinuous;
    _art.backgroundColor = DMCCTOffCircleColor(); _art.userInteractionEnabled = NO;
    _title = [UILabel new]; _line = [UILabel new];
    for (UILabel *l in @[_title, _line]) { l.lineBreakMode = NSLineBreakByTruncatingTail; l.userInteractionEnabled = NO; l.isAccessibilityElement = NO; }
    for (UIView *v in @[_art, _title, _line]) [_info addSubview:v];
    _play = [UIButton buttonWithType:UIButtonTypeSystem]; _next = [UIButton buttonWithType:UIButtonTypeSystem];
    for (UIButton *b in @[_play, _next]) { b.tintColor = [UIColor labelColor]; [self.view addSubview:b]; }
    _next.accessibilityLabel = @"Next Track";
    [_play addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf dm_send:kDMCCTMRTogglePlayPause]; }] forControlEvents:UIControlEventTouchUpInside];
    [_next addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { [weakSelf dm_send:kDMCCTMRNextTrack]; }] forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dm_hold:)];
    hold.minimumPressDuration = 0.45;
    [_info addGestureRecognizer:hold];
    [self dm_show:nil line:nil art:nil artKey:nil app:NO playing:NO];
    return self;
}
- (void)tileLayoutInBounds:(CGRect)b scale:(CGFloat)k {   // (laid out at size 1, put at the panel's size: DMCCTSize)
    self.scale = k;
    self.view.layer.cornerRadius = DMCCTCorner();
    CGFloat s = DMCCTSize();
    MSBDCCTNowLayout L = MSBDCCTNowFrames(b.size.width / s, b.size.height / s, k);
    _info.frame = DMCCTAt(L.info);
    _art.frame = DMCCTAt(L.art); _title.frame = DMCCTAt(L.title); _line.frame = DMCCTAt(L.line);
    _art.layer.cornerRadius = 6.0 * s;
    _play.frame = DMCCTAt(L.play); _next.frame = DMCCTAt(L.next);
    _title.font = [UIFont systemFontOfSize:round(13.0 * k) * s weight:UIFontWeightSemibold];
    _line.font = [UIFont systemFontOfSize:round(12.0 * k) * s];
    [self dm_buttons];
    if (!self.artKey) _art.image = DMCCTArtPlaceholder(_art.frame.size.height);
}
- (void)dm_buttons {
    CGFloat pt = round(19.0 * (self.scale > 0 ? self.scale : 1.0)) * DMCCTSize();
    [_play setImage:DMCCTSymbol(self.playing ? @"pause.fill" : @"play.fill", pt, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [_next setImage:DMCCTSymbol(@"forward.fill", pt, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    _play.accessibilityLabel = self.playing ? @"Pause" : @"Play";
    _play.enabled = _next.enabled = self.hasApp;
    _play.alpha = _next.alpha = self.hasApp ? 1.0 : 0.35;
}
- (void)dm_show:(NSString *)title line:(NSString *)line art:(UIImage *)art artKey:(NSString *)artKey app:(BOOL)app playing:(BOOL)playing {
    self.hasApp = app; self.playing = playing;
    _title.text = title.length ? title : @"Not Playing";
    _line.text = line;
    _title.textColor = title.length ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    _line.textColor = [UIColor secondaryLabelColor];
    if (![artKey isEqual:self.artKey] || (!art && self.artKey)) {
        self.artKey = art ? artKey : nil;
        _art.image = art ?: DMCCTArtPlaceholder(MAX(_art.bounds.size.height, 30.0));
        _art.contentMode = art ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;   // (the note at its own size in the middle; a picture fills the square)
    }
    _info.accessibilityLabel = @"Now Playing";
    _info.accessibilityValue = title.length ? (line.length ? [NSString stringWithFormat:@"%@, %@", title, line] : title) : @"Not Playing";
    [self dm_buttons];
}
// Read once now (a presentation, or a change while it shows): MediaRemote's info and whether it plays, on our queue; the app's name only when the
// title needs it; the artwork decoded there when it is another one. Shown on the main thread; an older answer than the last asked is dropped.
- (void)dm_refresh {
#if DEBUG
    if (gCCTFakeNow) {
        static UIImage *fake;
        if (!fake) fake = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(120, 120)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [[UIColor systemIndigoColor] setFill]; UIRectFill(CGRectMake(0, 0, 120, 120)); [[UIColor systemPinkColor] setFill]; UIRectFill(CGRectMake(0, 60, 120, 60));
        }];
        [self dm_show:@"Test Track With A Long Title" line:@"Test Artist" art:fake artKey:@"fake" app:YES playing:gCCTFakeNow == 1];
        return;
    }
#endif
    if (!gCCTMR.ok) return;
    self.fetched = YES;
    unsigned gen = ++self.gen;
    __weak DMCCTNowPlayingTile *weakSelf = self;
    CFTimeInterval t0 = CACurrentMediaTime();
    NSString *haveKey = self.artKey;
    dispatch_async(DMCCTQueue(), ^{ gCCTMR.playing(DMCCTQueue(), ^(Boolean playing) {
        gCCTMR.info(DMCCTQueue(), ^(CFDictionaryRef infoRef) {
            NSDictionary *info = (__bridge NSDictionary *)infoRef;
            NSString *title = [info[@"kMRMediaRemoteNowPlayingInfoTitle"] isKindOfClass:[NSString class]] ? info[@"kMRMediaRemoteNowPlayingInfoTitle"] : nil;
            NSString *artist = [info[@"kMRMediaRemoteNowPlayingInfoArtist"] isKindOfClass:[NSString class]] ? info[@"kMRMediaRemoteNowPlayingInfoArtist"] : nil;
            NSString *album = [info[@"kMRMediaRemoteNowPlayingInfoAlbum"] isKindOfClass:[NSString class]] ? info[@"kMRMediaRemoteNowPlayingInfoAlbum"] : nil;
            NSData *data = [info[@"kMRMediaRemoteNowPlayingInfoArtworkData"] isKindOfClass:[NSData class]] ? info[@"kMRMediaRemoteNowPlayingInfoArtworkData"] : nil;
            id ident = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
            NSString *key = data ? ([ident isKindOfClass:[NSString class]] ? ident : [NSString stringWithFormat:@"%lu.%lu", (unsigned long)data.length, (unsigned long)data.hash]) : nil;
            UIImage *art = nil;
            if (data && ![key isEqual:haveKey]) {   // (another picture: decoded here, at the size it shows)
                UIImage *full = [UIImage imageWithData:data];
                art = [full imageByPreparingThumbnailOfSize:CGSizeMake(128, 128)] ?: full;
            }
            void (^show)(NSString *) = ^(NSString *appName) {
                int f = 0, s = 0;
                MSBDCCTNowLines(appName.length > 0 || info.count > 0, title.length > 0, artist.length > 0, album.length > 0, &f, &s);
                NSString *l1 = f == 1 ? title : f == 4 ? appName : nil;
                NSString *l2 = s == 2 ? artist : s == 3 ? album : s == 4 ? appName : nil;
                BOOL app = info.count > 0 || appName.length > 0;
                dispatch_async(dispatch_get_main_queue(), ^{
                    DMCCTNowPlayingTile *me = weakSelf;
                    if (!me || gen != me.gen) return;
                    UIImage *a = art ?: ([key isEqual:me.artKey] ? me.art.image : nil);
                    [me dm_show:l1 line:l2 art:a artKey:key app:app playing:playing];
                    DMLog([NSString stringWithFormat:@"[cctiles] Now Playing: app %d, playing %d, title %lu chars, artwork %@ (%.1f ms after asking)", app, playing, (unsigned long)l1.length,
                        art ? @"decoded" : key ? @"the same" : @"none", (CACurrentMediaTime() - t0) * 1000.0]);
                });
            };
            if (title.length || !gCCTMR.app) { show(nil); return; }
            gCCTMR.app(DMCCTQueue(), ^(CFStringRef bid) {   // (no title: the app's name stands in)
                NSString *name = bid ? DMCall(DMProxyForBundle((__bridge NSString *)bid), @"localizedName") : nil;
                show([name isKindOfClass:[NSString class]] ? name : nil);
            });
        });
    }); });   // (even MediaRemote's first ask goes through our queue: its connection to mediaremoted is made on the calling thread)
}
- (void)dm_send:(uint32_t)cmd {
    DMLog([NSString stringWithFormat:@"[cctiles] Now Playing: %@", cmd == kDMCCTMRNextTrack ? @"next" : @"play / pause"]);
#if DEBUG
    if (gCCTFakeNow) { if (cmd == kDMCCTMRTogglePlayPause) gCCTFakeNow = gCCTFakeNow == 1 ? 2 : 1; DMLog(@"[cctiles] (test state: nothing sent)"); [self dm_refresh]; return; }
#endif
    if (!gCCTMR.ok || !self.hasApp) return;
    gCCTMR.send(cmd, NULL);
}
- (void)dm_open {
    BOOL opened = DMCCPanelExpandModule(@"com.apple.mediaremote.controlcenter.nowplaying");
    DMLog([NSString stringWithFormat:@"[cctiles] Now Playing tapped: Apple's player %@", opened ? @"opened from it" : @"not there"]);
}
- (void)dm_hold:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) [self dm_open]; }
- (void)tileWillPresent { if (self.old || !self.fetched) [self dm_refresh]; self.old = NO; }
@end

// ---- the tiles' life ---------------------------------------------------------------------------------------------------------------------
static void DMCCTMarkOld(int role) {
    for (DMCCTTile *t in DMCCTTilesOf(role)) {
        if (!gCCTShown) { t.old = YES; continue; }
        [t dm_refresh];
    }
}
// The system's notifications, once (at the panel's build): they only mark a tile's state old while Control Center is closed.
static void DMCCTObserve(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    void (^conn)(NSNotification *) = ^(NSNotification *n) { dispatch_async(dispatch_get_main_queue(), ^{ DMCCTStateChanged(kMSBDCCTRowWiFi); }); };
    for (NSString *n in @[@"SBWifiManagerLinkDidChangeNotification", @"SBWifiManagerPowerStateDidChangeNotification"]) [nc addObserverForName:n object:nil queue:nil usingBlock:conn];
    if (gCCTPart[kDMCCTPartBT])
        for (NSString *n in @[@"BluetoothPowerChangedNotification", @"BluetoothAvailabilityChangedNotification", @"BluetoothDeviceConnectSuccessNotification",
                              @"BluetoothDeviceDisconnectSuccessNotification", @"BluetoothConnectionStatusChangedNotification", @"BluetoothPairedStatusChangedNotification",
                              @"BluetoothDeviceUnpairedNotification"])
            [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMCCTStateChanged(kMSBDCCTRowBluetooth); }); }];
    // (the volume's own notification names one category's level, not always the active one: the active level is asked again, off the main thread,
    //  so the next presentation shows it at once -- one ask per change of the volume, which only a person or an app makes)
    if (gCCTVolumeNote) [nc addObserverForName:gCCTVolumeNote object:nil queue:nil usingBlock:^(NSNotification *n) {
        dispatch_async(dispatch_get_main_queue(), ^{ DMCCTLevelChanged(MSBDCCRoleTileSound, 0, NO); });
    }];
    [nc addObserverForName:UIScreenBrightnessDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        dispatch_async(dispatch_get_main_queue(), ^{ DMCCTLevelChanged(MSBDCCRoleTileDisplay, 0, NO); });
    }];
    if (gCCTMR.ok) {
        gCCTMR.reg(dispatch_get_main_queue());
        for (NSString *n in @[gCCTMRInfoNote, gCCTMRPlayingNote, gCCTMRAppNote ?: gCCTMRInfoNote])
            [nc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(), ^{ DMCCTMarkOld(MSBDCCRoleTileNowPlaying); }); }];
    }
}
// CCPanel.h's DMCCPMakeViews, when Apple builds Control Center: our tiles in place of the placeholders (a tile that cannot be made leaves its
// placeholder, which opens Apple's module).
static void DMCCTMakeTiles(void) {
    DMCCTCheck();
    if (!gCCTTiles) gCCTTiles = [NSHashTable weakObjectsHashTable];
    DMCCTConnectivityTile *c = [DMCCTConnectivityTile new];
    gCCTConn = c;
    NSArray<DMCCTTile *> *tiles = @[c, [[DMCCTWideTile alloc] initWithRole:MSBDCCRoleTileDisplay], [[DMCCTWideTile alloc] initWithRole:MSBDCCRoleTileSound], [DMCCTNowPlayingTile new]];
    for (DMCCTTile *t in tiles) { [gCCTTiles addObject:t]; t.old = YES; DMCCPanelAddTile(t); }
    DMCCTObserve();
    DMCCTBT();   // (made now, while Control Center is built and hidden: a first presentation's ms otherwise)
    DMCCTAirplaneRead(@"the panel's build");   // (Airplane Mode's preferences made and asked once, on our queue: the first presentation shows it)
    if (gCCTPart[kDMCCTPartVolume]) DMCCTVolumeAsk(nil);
    DM_FEATURE_MARK("cc-mac-tiles");
    DMLog([NSString stringWithFormat:@"[cctiles] %lu Mac tiles made", (unsigned long)tiles.count]);
}
// iPadOS 18 (CC18Tiles.h): a tile of a role for a module's host, as many as Control Center makes module instances (the gallery's previews too); what
// the panel's build does here, once, at the first one (Control Center's build, hidden).
static DMCCTTile *DMCCTMakeTileForRole(int role) {
    DMCCTCheck();
    if (!gCCTTiles) gCCTTiles = [NSHashTable weakObjectsHashTable];
    DMCCTTile *t = nil;
    if (role == MSBDCCRoleTileConnectivity) { DMCCTConnectivityTile *c = [DMCCTConnectivityTile new]; if (!gCCTConn) gCCTConn = c; t = c; }
    else if (role == MSBDCCRoleTileDisplay || role == MSBDCCRoleTileSound) t = [[DMCCTWideTile alloc] initWithRole:role];
    else if (role == MSBDCCRoleTileNowPlaying) t = [DMCCTNowPlayingTile new];
    if (!t) return nil;
    [gCCTTiles addObject:t]; t.old = YES;
    static BOOL first = YES;
    if (first) {
        first = NO;
        DMCCTObserve();
        DMCCTBT();
        DMCCTAirplaneRead(@"the first tile on 18");
        if (gCCTPart[kDMCCTPartVolume]) DMCCTVolumeAsk(nil);
        DM_FEATURE_MARK("cc-mac-tiles-18");
    }
    return t;
}
// Control Center about to show (CCPanel.h, before each tile's tileWillPresent) and closed (after each one's tileDidDismiss).
static void DMCCTPanelWillPresent(void) { gCCTShown = YES; DMCCTAirplaneWatch(YES); }
static void DMCCTPanelDidDismiss(void) {
    gCCTShown = NO;
    DMCCTAirplaneWatch(NO);
    if (gWiFiScanning && !gWiFiPanel.window) DMWiFiStopScanning(@"Control Center closed");   // (never past Control Center; a menu of the bar keeps its own)
    DMCCTRunAfterClose(@"Control Center closed");
}
// The screen went off (StatusBar.x DMCloseOverlaysForScreenOff): Control Center goes away with it; nothing of ours keeps going meanwhile.
static void DMCCTScreenOff(void) {
    if (!gCCTTiles.count) return;
    if (gWiFiScanning && !gWiFiPanel.window) DMWiFiStopScanning(@"the screen went off");
    if (gCCTShown) DMLog(@"[cctiles] the screen went off while Control Center showed");
}

#if DEBUG
// ---- debug read-outs and triggers (cct_*) --------------------------------------------------------------------------------------------------
// The selectors one of Apple's methods sends, read-only (cct_api: what Apple's own Airplane Mode button calls on this iPadOS; 17.5.1's cache:
// -_toggleState sends -setAirplaneMode: to its RadiosPreferences in a block on its queue, its invoke right after the method): its first n
// instructions decoded for an ADRP and an LDR or ADD that load a selector (a selector reference, or the selector itself), and for calls into a
// selector stub (objc_msgSend$...: its first two instructions load it). Every read goes through vm_read_overwrite; a word is a selector only
// when the runtime's own one for its text is that very word.
static BOOL DMCCTPeek(uintptr_t a, void *buf, size_t n) { vm_size_t got = 0; return vm_read_overwrite(mach_task_self(), (vm_address_t)a, n, (vm_address_t)buf, &got) == KERN_SUCCESS && got == n; }
static NSString *DMCCTSelAt(uintptr_t v) {
    char b[96] = {0};
    if (!v || !DMCCTPeek(v, b, sizeof b - 1)) return nil;
    size_t n = strnlen(b, sizeof b - 1);
    if (n == 0 || n >= sizeof b - 1) return nil;
    for (size_t i = 0; i < n; i++) if ((unsigned char)b[i] < 0x20 || (unsigned char)b[i] > 0x7e) return nil;
    return (uintptr_t)sel_getName(sel_getUid(b)) == v ? @(b) : nil;   // (a selector is its uniqued name)
}
static NSString *DMCCTSelsOf(Class cls, NSString *selName, int n) {
    Method m = cls ? class_getInstanceMethod(cls, NSSelectorFromString(selName)) : NULL;
    if (!m) return @" (no such method)";
    uintptr_t pc = (uintptr_t)ptrauth_strip((void *)method_getImplementation(m), ptrauth_key_asia);
    uint32_t code[128];
    n = MIN(n, 128);
    if (!DMCCTPeek(pc, code, n * 4)) return @" (unreadable)";
    uintptr_t page[32] = {0};
    NSMutableOrderedSet *seen = [NSMutableOrderedSet orderedSet];
    for (int i = 0; i < n; i++) {
        uint32_t c = code[i]; uintptr_t at = pc + 4 * i;
        if ((c & 0x9F000000) == 0x90000000) {   // adrp
            int64_t imm = (int64_t)((((c >> 5) & 0x7FFFF) << 2) | ((c >> 29) & 3)); if (imm & (1 << 20)) imm -= 1 << 21;
            page[c & 31] = (at & ~(uintptr_t)0xFFF) + (uintptr_t)(imm << 12);
        } else if ((c & 0xFFC00000) == 0xF9400000 && page[(c >> 5) & 31]) {   // ldr x, [x, #imm]: a selector reference
            uintptr_t slot = page[(c >> 5) & 31] + ((c >> 10) & 0xFFF) * 8, v = 0;
            NSString *sel = DMCCTPeek(slot, &v, 8) ? DMCCTSelAt(v) : nil;
            if (sel) [seen addObject:sel];
        } else if ((c & 0xFF800000) == 0x91000000 && page[(c >> 5) & 31]) {   // add x, x, #imm: a selector itself
            NSString *sel = DMCCTSelAt(page[(c >> 5) & 31] + ((c >> 10) & 0xFFF));
            if (sel) [seen addObject:sel];
        } else if ((c & 0xFC000000) == 0x94000000 || (c & 0xFC000000) == 0x14000000) {   // bl / b: a selector stub's selector
            int64_t imm = c & 0x3FFFFFF; if (imm & (1 << 25)) imm -= 1 << 26;
            uintptr_t t = at + (uintptr_t)(imm * 4); uint32_t st[2];
            if (!DMCCTPeek(t, st, 8) || (st[0] & 0x9F000000) != 0x90000000 || (st[0] & 31) != 1 || (st[1] & 0xFFC00000) != 0xF9400000) continue;
            int64_t si = (int64_t)((((st[0] >> 5) & 0x7FFFF) << 2) | ((st[0] >> 29) & 3)); if (si & (1 << 20)) si -= 1 << 21;
            uintptr_t slot = (t & ~(uintptr_t)0xFFF) + (uintptr_t)(si << 12) + ((st[1] >> 10) & 0xFFF) * 8, v = 0;
            NSString *sel = DMCCTPeek(slot, &v, 8) ? DMCCTSelAt(v) : nil;
            if (sel) [seen addObject:sel];
        }
    }
    return seen.count ? [@" " stringByAppendingString:[seen.array componentsJoinedByString:@", "]] : @" (none found)";
}
static NSString *DMCCTColorText(UIColor *c, UITraitCollection *tc) {   // ("rgb(255,159,10)": a colour as it resolves there)
    CGFloat r = 0, g = 0, b = 0, a = 0;
    UIColor *x = tc ? [c resolvedColorWithTraitCollection:tc] : c;
    if (![x getRed:&r green:&g blue:&b alpha:&a]) return @"rgb(?)";
    return [NSString stringWithFormat:@"rgb(%.0f,%.0f,%.0f)%@", r * 255.0, g * 255.0, b * 255.0, a < 0.999 ? [NSString stringWithFormat:@" a%.2f", a] : @""];
}
static void DMCCTAPIReport(void) {   // cct_api: every row as this iPadOS has it, and the parts in force
    for (size_t i = 0; i < sizeof(kDMCCTNeeds) / sizeof(kDMCCTNeeds[0]); i++) {
        const DMCCTNeedRow *r = &kDMCCTNeeds[i]; Class c = objc_getClass(r->cls);
        Method m = !c ? NULL : r->meta ? class_getClassMethod(c, sel_registerName(r->sel)) : class_getInstanceMethod(c, sel_registerName(r->sel));
        DMLog([NSString stringWithFormat:@"[cctiles] api %c[%s %s] %s (we use %s)%@", r->meta ? '+' : '-', r->cls, r->sel, m ? method_getTypeEncoding(m) : "MISSING", r->enc, DMCCTRowOK(r) ? @"" : @" -- NOT AS EXPECTED"]);
    }
    Class apc = objc_getClass("CCUIConnectivityAirplaneViewController");   // (Apple's own button: loaded with its Connectivity module)
    NSMutableString *iv = [NSMutableString string];
    unsigned ni = 0; Ivar *ivs = apc ? class_copyIvarList(apc, &ni) : NULL;
    for (unsigned i = 0; i < ni; i++) [iv appendFormat:@" %s %s", ivar_getName(ivs[i]), ivar_getTypeEncoding(ivs[i]) ?: ""];
    free(ivs);
    DMLog([NSString stringWithFormat:@"[cctiles] api: Apple's Airplane Mode button %@:%@; -_toggleState sends%@; -buttonTapped: sends%@", apc ? NSStringFromClass(apc) : @"not loaded", iv.length ? iv : @" (no ivars)",
        DMCCTSelsOf(apc, @"_toggleState", 96), DMCCTSelsOf(apc, @"buttonTapped:", 32)]);
    CFTimeInterval ta0 = CACurrentMediaTime();
    __block int ap = -1; __block BOOL made = NO;
    if (gCCTPart[kDMCCTPartAirplane]) dispatch_sync(DMCCTQueue(), ^{ id<DMCCTRadios> p = DMCCTRadiosNow(); made = p != nil; if (p) ap = [p airplaneMode] ? 1 : 0; });   // (debug: read-only)
    DMLog([NSString stringWithFormat:@"[cctiles] api: RadiosPreferences made %d, -airplaneMode %d (%.2f ms on our queue, asked from the main thread), shown %d", made, ap, (CACurrentMediaTime() - ta0) * 1000.0, gCCTAirplaneOn]);
    Method bc = class_getInstanceMethod(objc_getClass("SBDisplayBrightnessController"), NSSelectorFromString(@"setBrightnessLevel:animated:"));
    DMLog([NSString stringWithFormat:@"[cctiles] api: brightness set %s; MediaRemote %d; volume note %@; BluetoothManager made %d", bc ? method_getTypeEncoding(bc) : "MISSING", gCCTMR.ok, gCCTVolumeNote, DMCCTBT() != nil]);
}
static void DMCCTState(void) {   // cct_state: what each tile shows (names hashed)
    DMCCTConnectivityTile *c = gCCTConn;
    for (DMCCTConnRow *r in c.rows) DMLog([NSString stringWithFormat:@"[cctiles] state %@: on %d usable %d line %@ frame %@", r.title.text, r.on, r.usable,
        r.kind == kMSBDCCTRowWiFi ? DMWiFiTag(r.line.text) : r.line.text, NSStringFromCGRect(r.frame)]);
    NSArray *devs = DMCCTBTDevices(NO);
    NSUInteger con = 0; for (id d in devs) if (DMCCTBTDeviceConnected(d)) con++;
    DMLog([NSString stringWithFormat:@"[cctiles] state Bluetooth: available %d powered %d, %lu paired, %lu connected; Airplane Mode %d (answer %d, test state %d); page %d", DMCCTBTAvailable(), DMCCTBTPowered(),
        (unsigned long)devs.count, (unsigned long)con, DMCCTAirplaneState(), gCCTAirplaneOn, gCCTFakeAirplane, c.page]);
    for (DMCCTConnRow *r in c.rows) DMLog([NSString stringWithFormat:@"[cctiles] state %@: circle %@ %@, font %.2f / %.2f pt, chevron %d", r.title.text, NSStringFromCGRect(r.circle.frame), DMCCTColorText(r.circle.backgroundColor, r.circle.traitCollection),
        r.title.font.pointSize, r.line.font.pointSize, !r.chevron.hidden]);
    for (int role = MSBDCCRoleTileDisplay; role <= MSBDCCRoleTileSound; role++) {
        DMCCTWideTile *t = (DMCCTWideTile *)DMCCTTileOf(role);
        DMLog([NSString stringWithFormat:@"[cctiles] state %@: slider %d%% usable %d, system %d%%, frame %@", t.tid, MSBDCCTPercent(t.slider.value), t.usable,
            MSBDCCTPercent(role == MSBDCCRoleTileDisplay ? DMCCTBrightness() : DMCCTVolume(NULL)), NSStringFromCGRect(t.slider.frame)]);
    }
    DMCCTNowPlayingTile *n = (DMCCTNowPlayingTile *)DMCCTTileOf(MSBDCCRoleTileNowPlaying);
    DMLog([NSString stringWithFormat:@"[cctiles] state Now Playing: app %d playing %d, title %lu chars, artwork %d; shown %d", n.hasApp, n.playing, (unsigned long)n.title.text.length, n.artKey != nil, gCCTShown]);
}
static void DMCCTAXDump(UIView *v, int depth, int *count) {   // cct_ax: the panel's elements in VoiceOver's order (names hashed where they are a network's)
    if (!v || depth > 12 || *count > 80) return;
    if (v.isAccessibilityElement) {
        (*count)++;
        BOOL names = ([v isKindOfClass:[DMCCTConnRow class]] && ((DMCCTConnRow *)v).kind != kMSBDCCTRowAirplane) || ([v isKindOfClass:[UIControl class]] && ![v isKindOfClass:[DMCCTConnRow class]]);   // (a network's or a track's name in the value: hashed; Airplane Mode's On / Off is none)
        DMLog([NSString stringWithFormat:@"[cctiles] ax %d: %@ \"%@\" value \"%@\" traits 0x%llx actions %lu", *count, NSStringFromClass([v class]), v.accessibilityLabel, names && ![v isKindOfClass:[DMCCTSlider class]] ? DMWiFiTag(v.accessibilityValue) : v.accessibilityValue,
            (unsigned long long)v.accessibilityTraits, (unsigned long)v.accessibilityCustomActions.count]);
        return;
    }
    NSArray *kids = v.accessibilityElements.count ? v.accessibilityElements : v.subviews;
    for (id k in kids) if ([k isKindOfClass:[UIView class]] && !((UIView *)k).hidden && ((UIView *)k).alpha > 0.01) DMCCTAXDump(k, depth + 1, count);
}
static BOOL DMCCTDebugTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"cct_api"]) { DMCCTAPIReport(); return YES; }
    if ([cmd isEqualToString:@"cct_state"]) { DMCCTState(); return YES; }
    if ([cmd isEqualToString:@"cct_rowtime"]) {   // what a page's rows cost to make: plain rows, network rows, the Wi-Fi menu's whole builder, the records' own answers
        CFTimeInterval t0 = CACurrentMediaTime();
        for (int i = 0; i < 15; i++) (void)[[DMRow alloc] initWithTitle:@"Row" enabled:YES handler:^{}];
        CFTimeInterval t1 = CACurrentMediaTime();
        for (int i = 0; i < 15; i++) (void)[[DMWiFiNetworkRow alloc] initWithName:@"Row" secure:YES bars:3 handler:^{}];
        CFTimeInterval t2 = CACurrentMediaTime();
        NSString *sig = nil; NSArray *items = DMWiFiMenuItems(&sig);
        CFTimeInterval t3 = CACurrentMediaTime();
        int known = 0; for (id r in DMWiFiRecords()) known += DMWiFiRecKnown(r);
        CFTimeInterval t4 = CACurrentMediaTime();
        DMLog([NSString stringWithFormat:@"[cctiles] rows: 15 plain %.2f ms, 15 network %.2f ms, the Wi-Fi builder (%lu items) %.2f ms, %lu records' known %.2f ms (%d)", (t1 - t0) * 1000.0, (t2 - t1) * 1000.0,
            (unsigned long)items.count, (t3 - t2) * 1000.0, (unsigned long)DMWiFiRecords().count, (t4 - t3) * 1000.0, known]);
        return YES;
    }
    if ([cmd isEqualToString:@"cct_ax"]) { int n = 0; DMCCTAXDump(gCCPScroll, 0, &n); DMLog([NSString stringWithFormat:@"[cctiles] ax: %d elements", n]); return YES; }
    if ([cmd hasPrefix:@"cct_btfake_"]) { gCCTFakeBT = [[cmd substringFromIndex:11] intValue]; gCCTFakeDevices = nil; DMLog([NSString stringWithFormat:@"[cctiles] Bluetooth test state %d", gCCTFakeBT]); DMCCTStateChanged(kMSBDCCTRowBluetooth); return YES; }
    if ([cmd hasPrefix:@"cct_apfake_"]) {   // cct_apfake_<-1|0|1>: Airplane Mode shown off / on (look only: the radio is never asked), -1 the real state again
        int v = [[cmd substringFromIndex:11] intValue]; gCCTFakeAirplane = v == 0 || v == 1 ? v : -1;
        DMLog([NSString stringWithFormat:@"[cctiles] Airplane Mode test state %d", gCCTFakeAirplane]); DMCCTConnShow(); return YES;
    }
    if ([cmd hasPrefix:@"cct_npfake_"]) { gCCTFakeNow = [[cmd substringFromIndex:11] intValue]; DMLog([NSString stringWithFormat:@"[cctiles] Now Playing test state %d", gCCTFakeNow]); DMCCTMarkOld(MSBDCCRoleTileNowPlaying); return YES; }
    if ([cmd hasPrefix:@"cct_page_"]) {   // cct_page_<wifi|bt|ap|sound>: a page opens as its row's tap or the chevron opens it (Airplane Mode has none)
        NSString *k = [cmd substringFromIndex:9];
        if ([k isEqualToString:@"sound"]) DMCCPanelOpenDetail(DMCCTTileOf(MSBDCCRoleTileSound));
        else [gCCTConn dm_openPage:[k isEqualToString:@"wifi"] ? kMSBDCCTRowWiFi : [k isEqualToString:@"bt"] ? kMSBDCCTRowBluetooth : kMSBDCCTRowAirplane];
        return YES;
    }
    if ([cmd hasPrefix:@"cct_tap_"]) {   // cct_tap_<wifi|bt|ap>: its round button, ONLY on a test state (a real radio is never switched from a trigger)
        NSString *k = [cmd substringFromIndex:8];
        int kind = [k isEqualToString:@"wifi"] ? kMSBDCCTRowWiFi : [k isEqualToString:@"bt"] ? kMSBDCCTRowBluetooth : kMSBDCCTRowAirplane;
        BOOL fake = kind == kMSBDCCTRowWiFi ? gWiFiFakeState != 0 : kind == kMSBDCCTRowBluetooth ? gCCTFakeBT != 0 : gCCTFakeAirplane >= 0;
        if (!fake) { DMLog(@"[cctiles] cct_tap_ refused: no test state set (it would switch the radio)"); return YES; }
        [gCCTConn dm_toggle:kind];
        return YES;
    }
    if ([cmd hasPrefix:@"cct_level_"]) {   // cct_level_<display|sound>_<0..1>: the slider moved there, as a drag ends (the real brightness / volume)
        NSArray *p = [[cmd substringFromIndex:10] componentsSeparatedByString:@"_"];
        DMCCTWideTile *t = (DMCCTWideTile *)DMCCTTileOf([p[0] isEqualToString:@"display"] ? MSBDCCRoleTileDisplay : MSBDCCRoleTileSound);
        if (p.count == 2 && t) { [t.slider dm_setValue:[p[1] doubleValue]]; [t dm_slid:t.slider.value done:YES]; }
        return YES;
    }
    if ([cmd hasPrefix:@"cct_axstep_"]) {   // cct_axstep_<display|sound>_<up|down>: VoiceOver's swipe on the slider
        NSArray *p = [[cmd substringFromIndex:11] componentsSeparatedByString:@"_"];
        DMCCTWideTile *t = (DMCCTWideTile *)DMCCTTileOf([p[0] isEqualToString:@"display"] ? MSBDCCRoleTileDisplay : MSBDCCRoleTileSound);
        if (p.count == 2 && t) { if ([p[1] isEqualToString:@"up"]) [t.slider accessibilityIncrement]; else [t.slider accessibilityDecrement]; DMLog([NSString stringWithFormat:@"[cctiles] %@ ax step: %@", t.tid, t.slider.accessibilityValue]); }
        return YES;
    }
    if ([cmd hasPrefix:@"cct_np_"]) {   // cct_np_<play|next>: the player's buttons, ONLY on a test state (never KT's music)
        if (!gCCTFakeNow) { DMLog(@"[cctiles] cct_np_ refused: no test state set"); return YES; }
        [(DMCCTNowPlayingTile *)DMCCTTileOf(MSBDCCRoleTileNowPlaying) dm_send:[cmd hasSuffix:@"next"] ? kDMCCTMRNextTrack : kDMCCTMRTogglePlayPause];
        return YES;
    }
    if ([cmd hasPrefix:@"cct_details_"]) {   // cct_details_<display|sound>: the chevron
        DMCCTWideTile *t = (DMCCTWideTile *)DMCCTTileOf([[cmd substringFromIndex:12] isEqualToString:@"display"] ? MSBDCCRoleTileDisplay : MSBDCCRoleTileSound);
        [t dm_details];
        return YES;
    }
    if ([cmd isEqualToString:@"cct_nowopen"]) { [(DMCCTNowPlayingTile *)DMCCTTileOf(MSBDCCRoleTileNowPlaying) dm_open]; return YES; }
    if ([cmd hasPrefix:@"cct_row_"]) {   // cct_row_<n>: the open page's n-th row used (its action, as a tap); a network's row only with test networks (wififake_)
        int n = [[cmd substringFromIndex:8] intValue], i = 0;
        UIView *page = gCCPDetail;
        NSMutableArray *rows = [NSMutableArray array];
        NSMutableArray *todo = [NSMutableArray arrayWithObject:page ?: [UIView new]];
        while (todo.count) { UIView *v = todo.firstObject; [todo removeObjectAtIndex:0]; if ([v isKindOfClass:[DMRow class]]) [rows addObject:v]; else [todo addObjectsFromArray:v.subviews]; }
        DMRow *r = n >= 0 && n < (int)rows.count ? rows[n] : nil;
        int kind = gCCTConn.page;
        BOOL network = [r isKindOfClass:[DMWiFiNetworkRow class]], settings = [r.label.text hasSuffix:@"Settings…"] || [r.label.text isEqualToString:@"Other Networks…"];
        BOOL real = !settings && ((network && !gWiFiFake) || (kind == kMSBDCCTRowBluetooth && !gCCTFakeBT));
        for (DMRow *x in rows) DMLog([NSString stringWithFormat:@"[cctiles] row %d: %@%@%@", i++, DMWiFiTag(x.label.text), x.checked ? @" (ticked)" : @"", x.enabled ? @"" : @" (greyed)"]);
        if (!r || real) { DMLog([NSString stringWithFormat:@"[cctiles] cct_row_%d: %@", n, r ? @"refused (it would join a network or switch a device: use a test state)" : @"no such row"]); return YES; }
        DMLog([NSString stringWithFormat:@"[cctiles] row %d used", n]);
        [r sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    return NO;
}
#endif
