// WiFiMenu.h -- the Wi-Fi menu (2 Oct 2026), included into StatusBar.x. Settings > Status Bar > Wi-Fi Menu (pref wifiMenu, on unless switched off where the iPad supports it (DMWiFiSupported);
// iPadOS 15/16 only): our own Wi-Fi icon in the menu bar, nearest the status icons (iOS's own Wi-Fi item is left out of our bars then, see
// DMHideStockWiFi), and a Mac-style drop-down: the Wi-Fi switch, the current network (tick, lock, bars), the networks nearby (a known one is
// joined; an unknown secured one opens its page in Settings), Other Networks… and Wi-Fi Settings….
// The list comes from WiFiKit's WFNetworkListController, the same list Control Center's own Wi-Fi module drives (CCUIWiFiMenuModuleViewController):
// our DMWiFiListing plays its view controller. It scans only while the menu is open; every close path stops it (DMWiFiMenuGone), and a watchdog
// stops it 30 s after the menu was opened. Logs never name a network: "<ssid>" or a short hash only.

static const void *kWiFiMenuLabelKey = &kWiFiMenuLabelKey, *kWiFiMenuPillKey = &kWiFiMenuPillKey;
static const CGFloat kWiFiHeaderH = 24.0, kWiFiSwitchRowH = 34.0;
static NSMutableArray<NSString *> *gWiFiMenuOrder = nil;   // (the nearby networks in the order the open menu shows them, DMWiFiMenuItems)
static NSArray<NSString *> *gWiFiLastOrder = nil;          // (the order the last menu built showed them)

// A short hash of a network's name, for the log (FNV-1a, 32 bits).
static NSString *DMWiFiTag(NSString *ssid) {
    if (!ssid.length) return @"<none>";
    uint32_t h = 2166136261u;
    const char *u = ssid.UTF8String;
    if (u) for (const char *p = u; *p; p++) { h ^= (uint8_t)*p; h *= 16777619u; }
    else for (NSUInteger i = 0; i < ssid.length; i++) {   // (no UTF-8 form -- a lone surrogate --: its UTF-16 units)
        unichar c = [ssid characterAtIndex:i];
        h ^= (uint8_t)(c & 0xff); h *= 16777619u; h ^= (uint8_t)(c >> 8); h *= 16777619u;
    }
    return [NSString stringWithFormat:@"<ssid %08x>", h];
}

// ---- SpringBoard's own Wi-Fi state (cached values, cheap on the main thread) ----
static id DMWiFiSB(void) {
    Class c = objc_getClass("SBWiFiManager");
    return [c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance)) : nil;
}
#if DEBUG
static int gWiFiFakeState = 0;   // (tests: wififakestate_<n> -- 1 shown as off, 2 as on but not joined, 3/4 joined with one/two bars; 0 the real state. Nothing is switched.)
#endif
static BOOL DMWiFiSBBool(NSString *sel) {
    id sb = DMWiFiSB(); SEL s = NSSelectorFromString(sel);
    return [sb respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(sb, s);
}
static BOOL DMWiFiPowered(void) {
#if DEBUG
    if (gWiFiFakeState == 1) return NO;
#endif
    return DMWiFiSBBool(@"isPowered");
}
static BOOL DMWiFiAssociated(void) {
#if DEBUG
    if (gWiFiFakeState == 2) return NO;
#endif
    return DMWiFiPowered() && DMWiFiSBBool(@"isAssociated");
}
static NSInteger DMWiFiBars(void) {
#if DEBUG
    if (gWiFiFakeState >= 3) return gWiFiFakeState - 2;   // (wififakestate_3 / _4: one / two bars)
#endif
    id sb = DMWiFiSB(); SEL s = NSSelectorFromString(@"signalStrengthBars");
    NSInteger b = [sb respondsToSelector:s] ? ((int (*)(id, SEL))objc_msgSend)(sb, s) : 3;
    return MAX(1, MIN(3, b));   // (associated: at least one bar, like the stock icon)
}
static NSString *DMWiFiCurrentName(void) {
    id n = DMCall(DMWiFiSB(), @"currentNetworkName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}
static id DMWiFiClient(void) {
    Class c = objc_getClass("WFClient");
    return [c respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(c, @selector(sharedInstance)) : nil;
}

// ---- a scan record (WFNetworkScanRecord, or a test record from wififake_): every property asked defensively ----
static BOOL DMWiFiRecBool(id r, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    return [r respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(r, s);
}
static NSString *DMWiFiRecSSID(id r) { id s = DMCall(r, @"ssid"); return [s isKindOfClass:[NSString class]] ? s : nil; }
// A name that shows nothing (only spaces, control characters or NULs: some access points hide their name that way, and iPadOS 16 lists them)
// is treated like no name: no blank row in the menu.
static BOOL DMWiFiNameBlank(NSString *n) {
    static NSCharacterSet *invisible = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [set formUnionWithCharacterSet:[NSCharacterSet controlCharacterSet]];
        [set addCharactersInString:@"\u200B\u200C\u200D\u2060\uFEFF"];   // (zero-width characters)
        invisible = set;
    });
    return [n stringByTrimmingCharactersInSet:invisible].length == 0;
}
static BOOL DMWiFiRecSecure(id r) { return DMWiFiRecBool(r, @"isSecure") || DMWiFiRecBool(r, @"isEnterprise"); }
static BOOL DMWiFiRecKnown(id r) { return DMWiFiRecBool(r, @"isKnown") || DMCall(r, @"matchingKnownNetworkProfile") != nil; }
static float DMWiFiRecScaled(id r) {
    return [r respondsToSelector:@selector(scaledRSSI)] ? ((float (*)(id, SEL))objc_msgSend)(r, @selector(scaledRSSI)) : 0.0f;
}
static NSInteger DMWiFiRecBars(id r) {
    // (WFNetworkScanRecord -signalBars, 1-3; otherwise from the scaled strength, 0...1, as Control Center's menu does)
    SEL s = NSSelectorFromString(@"signalBars");
    if ([r respondsToSelector:s]) return MAX(1, MIN(3, ((long long (*)(id, SEL))objc_msgSend)(r, s)));
    float f = DMWiFiRecScaled(r);
    return f >= 0.66f ? 3 : (f >= 0.33f ? 2 : 1);
}

#if DEBUG
// (tests: wififake_<n> -- n made-up networks, for the layout without the radio; tapping one only logs)
@interface DMWiFiFakeRecord : NSObject
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, assign) BOOL isSecure, isKnown, isEnterprise, isCaptive;
@property (nonatomic, assign) long long signalBars;
@property (nonatomic, assign) float scaledRSSI;
@end
@implementation DMWiFiFakeRecord
@end
static NSArray *gWiFiFake = nil;
@interface DMWiFiFakeErrorContext : NSObject   // (tests: wifictxerror -- what the error report reads)
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) id network;
@end
@implementation DMWiFiFakeErrorContext
- (void)cancel { DMLog(@"[wifictx] the test error was dismissed (-cancel)"); }
@end
#endif

static id DMWiFiCredentialsRequested(id ctx);   // (the password sheet, below)
static void DMWiFiErrorReported(id ctx);
// ---- the listing: WFNetworkListController's "view controller" (never shown). Only what Control Center's module answers is implemented. ----
static void DMWiFiListChanged(void);
@interface DMWiFiListing : UIViewController
@property (nonatomic, strong) NSArray *records;   // the last scan's networks
@property (nonatomic, strong) id current;         // the current network's record (nil: not associated)
@property (nonatomic, assign) float scaledRSSI;
@property (nonatomic, assign) unsigned long long signalBars;
@property (nonatomic, assign) long long networkState, capability;
@property (nonatomic, assign) BOOL showOther, isScanning, hasPower, everScanned;
@property (nonatomic, weak) id listDelegate;
@end
@implementation DMWiFiListing
- (id)currentNetwork { return self.current; }
- (void)setCurrentNetwork:(id)n { dispatch_async(dispatch_get_main_queue(), ^{ self.current = n; DMWiFiListChanged(); }); }
- (float)currentNetworkScaledRSSI { return self.scaledRSSI; }
- (void)setCurrentNetworkScaledRSSI:(float)v { self.scaledRSSI = v; }
- (unsigned long long)currentNetworkSignalBars { return self.signalBars; }
- (void)setCurrentNetworkSignalBars:(unsigned long long)b { dispatch_async(dispatch_get_main_queue(), ^{ self.signalBars = b; DMWiFiListChanged(); }); }
- (long long)currentNetworkState { return self.networkState; }
- (void)setCurrentNetworkState:(long long)s { self.networkState = s; }
- (long long)deviceCapability { return self.capability; }
- (void)setDeviceCapability:(long long)c { self.capability = c; }
- (BOOL)showOtherNetwork { return self.showOther; }
- (void)setShowOtherNetwork:(BOOL)b { self.showOther = b; }
- (void)powerStateDidChange:(BOOL)on { dispatch_async(dispatch_get_main_queue(), ^{ self.hasPower = on; DMWiFiListChanged(); }); }
- (void)setScanning:(BOOL)on { dispatch_async(dispatch_get_main_queue(), ^{ self.isScanning = on; }); }
- (void)refresh { dispatch_async(dispatch_get_main_queue(), ^{ DMWiFiListChanged(); }); }
- (void)setNetworks:(id)networks {
    NSArray *list = [networks isKindOfClass:[NSSet class]] ? [(NSSet *)networks allObjects] : ([networks isKindOfClass:[NSArray class]] ? networks : @[]);
    dispatch_async(dispatch_get_main_queue(), ^{ self.records = list; self.everScanned = YES; DMWiFiListChanged(); });
}
// (the view provider: a password the controller asks for is typed in our own sheet, DMWiFiCredentialsRequested; an error goes into that sheet)
- (id)credentialsViewControllerWithContext:(id)ctx { return DMWiFiCredentialsRequested(ctx); }
- (id)certificateViewControllerWithContext:(id)ctx { DMLog(@"[wifi] the list asks for a certificate sheet: Settings opened instead"); DMOpenURL(@"prefs:root=WIFI", @"wifi settings (certificate)"); return [UIViewController new]; }
- (id)networkErrorViewControllerWithContext:(id)ctx { DMWiFiErrorReported(ctx); return [UIViewController new]; }
- (id)networkDetailsViewControllerWithContext:(id)ctx { DMLog([NSString stringWithFormat:@"[wifi] the list asks for a details page (%@)", NSStringFromClass([ctx class])]); return [UIViewController new]; }
- (void)presentNetworkViewController:(id)vc forContext:(id)ctx { DMLog([NSString stringWithFormat:@"[wifi] the list wants to show %@ (not shown)", NSStringFromClass([ctx class])]); }
- (void)dismissNetworkViewController:(id)vc forContext:(id)ctx {}
// Anything else the controller sends without asking first: logged, answered with zero (an unanswered selector would end SpringBoard).
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    if (sig) return sig;
    for (NSString *pn in @[@"WFNetworkListing", @"WFNetworkViewProvider"]) {
        Protocol *p = objc_getProtocol(pn.UTF8String);
        if (!p) continue;
        for (int req = 0; req < 2; req++) {
            struct objc_method_description d = protocol_getMethodDescription(p, sel, req == 0, YES);
            if (d.types) return [NSMethodSignature signatureWithObjCTypes:d.types];
        }
    }
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    DMLog([NSString stringWithFormat:@"[wifi] the list sent %@, not answered", NSStringFromSelector(inv.selector)]);
    NSUInteger n = inv.methodSignature.methodReturnLength;
    if (n) { void *zero = calloc(1, n); [inv setReturnValue:zero]; free(zero); }
}
@end

// ---- the list controller: made at the first menu, kept; scanning only while the menu is open ----
static DMWiFiListing *gWiFiListing = nil;
static id gWiFiList = nil;   // WFNetworkListController
static BOOL gWiFiScanning = NO;
static CFTimeInterval gWiFiOpenedAt = 0;
static NSTimer *gWiFiWatchdog = nil;
static __weak UIView *gWiFiPanel = nil;   // the open Wi-Fi menu's panel (nil: none open)
static id DMWiFiListController(void) {
    if (gWiFiList) return gWiFiList;
    static BOOL tried = NO;
    if (tried) return nil;
    tried = YES;
    Class lc = objc_getClass("WFNetworkListController");
    id client = DMWiFiClient();
    SEL init3 = NSSelectorFromString(@"initWithViewController:viewProvider:client:");
    if (!lc || !client || ![lc instancesRespondToSelector:init3]) { DMLog(@"[wifi] WFNetworkListController not usable: the menu shows the state only"); return nil; }
    gWiFiListing = [DMWiFiListing new];
    gWiFiListing.hasPower = DMWiFiPowered();
    for (NSString *pn in @[@"WFNetworkListing", @"WFNetworkViewProvider"]) { Protocol *p = objc_getProtocol(pn.UTF8String); if (p) class_addProtocol([DMWiFiListing class], p); }
    @try { gWiFiList = ((id (*)(id, SEL, id, id, id))objc_msgSend)([lc alloc], init3, gWiFiListing, gWiFiListing, client); }
    @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wifi] list controller failed: %@", e.name]); gWiFiList = nil; }
    DMLog([NSString stringWithFormat:@"[wifi] list controller %@", gWiFiList ? @"made" : @"NOT made"]);
    return gWiFiList;
}
static void DMWiFiStopScanning(NSString *why) {
    [gWiFiWatchdog invalidate]; gWiFiWatchdog = nil;
    if (!gWiFiScanning) return;
    gWiFiScanning = NO;
    if ([gWiFiList respondsToSelector:@selector(stopScanning)]) ((void (*)(id, SEL))objc_msgSend)(gWiFiList, @selector(stopScanning));
    DMLog([NSString stringWithFormat:@"[wifi] scanning stopped (%@)", why]);
}
static void DMWiFiStartScanning(void) {
    gWiFiOpenedAt = CACurrentMediaTime();
    id list = DMWiFiListController();
    if (!gWiFiScanning && [list respondsToSelector:@selector(startScanning)] && DMWiFiPowered()) {
        ((void (*)(id, SEL))objc_msgSend)(list, @selector(startScanning));
        gWiFiScanning = YES;
        DMLog(@"[wifi] scanning started");
    }
    // the watchdog: a scan never outlives its menu (a close path missed), and never runs longer than 30 s after the menu was opened
    if (!gWiFiWatchdog) {
        gWiFiWatchdog = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
            if (!gWiFiPanel.window) { DMWiFiStopScanning(@"watchdog: the menu is gone"); return; }
            if (CACurrentMediaTime() - gWiFiOpenedAt > 30.0) DMWiFiStopScanning(@"watchdog: 30 s");
        }];
        gWiFiWatchdog.tolerance = 0.5;
        [[NSRunLoop mainRunLoop] addTimer:gWiFiWatchdog forMode:NSRunLoopCommonModes];
    }
}
// Every menu close comes here (DMCloseOverlay, DMRemoveOverlayNow -- another title, the screen going off, ...): the Wi-Fi menu's scan stops with it.
static void DMWiFiSheetDropped(NSString *why);   // (the password sheet, below)
static void DMWiFiMenuGone(NSString *why) {
    DMWiFiSheetDropped(why);
    gWiFiMenuOrder = nil;
    if (!gWiFiPanel && !gWiFiScanning) return;
    gWiFiPanel = nil;
    DMWiFiStopScanning([@"menu " stringByAppendingString:why]);
}

// ---- the glyphs ----
// The Wi-Fi fan, 0-3 bars lit (unlit bars faint), as a template image: the rows' signal glyph, and the menu bar icon if iOS's own signal view is missing.
static UIImage *DMWiFiFanImage(NSInteger bars, CGFloat height) {
    static NSMutableDictionary<NSString *, UIImage *> *cache = nil;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%ld/%.1f", (long)bars, height];
    if (cache[key]) return cache[key];
    CGFloat R = height - 1.0, w = ceil(R * 2.0 * 0.7071) + 2.0;
    CGSize size = CGSizeMake(w, height);
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGPoint c = CGPointMake(w / 2.0, height - 0.5);
        CGFloat a0 = M_PI * 1.25, a1 = M_PI * 1.75;
        CGFloat edges[3][2] = { { 0.0, 0.36 }, { 0.48, 0.68 }, { 0.80, 1.0 } };
        for (int i = 0; i < 3; i++) {
            UIBezierPath *p = [UIBezierPath bezierPath];
            CGFloat ri = edges[i][0] * R, ro = edges[i][1] * R;
            if (ri <= 0.0) { [p moveToPoint:c]; [p addArcWithCenter:c radius:ro startAngle:a0 endAngle:a1 clockwise:YES]; [p closePath]; }
            else { [p addArcWithCenter:c radius:ro startAngle:a0 endAngle:a1 clockwise:YES]; [p addArcWithCenter:c radius:ri startAngle:a1 endAngle:a0 clockwise:NO]; [p closePath]; }
            [[UIColor colorWithWhite:0.0 alpha:(i < bars ? 1.0 : 0.25)] setFill];
            [p fill];
        }
    }];
    img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cache[key] = img;
    return img;
}

// ---- the menu bar icon: the Wi-Fi fan, drawn (DMWiFiFanImage) at the stock icon's size (14 x 10 pt on the iPad's bar), tinted like the other
// icons: the lit bars when joined, every bar faint when Wi-Fi is off or not joined (the Mac's empty fan). (iOS's own _UIStatusBarWifiSignalView
// was tried first: outside a status bar item it never redrew after its bars or colours changed -- seen on the M1.) ----
static UIView *DMWiFiMakeIcon(void) {
    UIImageView *iv = [UIImageView new];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.userInteractionEnabled = NO;
    return iv;
}
static CGSize DMWiFiApplyIconState(UIView *icon, UIColor *tint) {
    UIImageView *iv = (UIImageView *)icon;
    UIImage *img = DMWiFiFanImage(DMWiFiAssociated() ? DMWiFiBars() : 0, 10.0);
    if (iv.image != img) iv.image = img;
    if (tint && ![iv.tintColor isEqual:tint]) iv.tintColor = tint;
    return img.size;
}
// Places our Wi-Fi icon just left of `left` (where the status icons start) in a status bar copy, and returns the new left edge. Hidden while
// the Wi-Fi Menu switch is off: the bar is then exactly as before. (`left` in leading coordinates, DMBarRTL: right of the icons right-to-left.)
static CGFloat DMWiFiLayoutIcon(UIView *fg, CGFloat left, CGFloat midY, UIColor *tint) {
    UIView *icon = objc_getAssociatedObject(fg, kWiFiIconKey);
    UIButton *btn = objc_getAssociatedObject(fg, kWiFiButtonKey);
    if (!gWiFiMenuOn || left == CGFLOAT_MAX) { icon.hidden = btn.hidden = YES; return left; }
    if (!icon) {
        icon = DMWiFiMakeIcon();
        [fg addSubview:icon];
        objc_setAssociatedObject(fg, kWiFiIconKey, icon, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.pointerInteractionEnabled = YES;
        __weak UIButton *weakBtn = btn;
        [btn addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (weakBtn) DMOpenWiFiMenu(weakBtn); }] forControlEvents:UIControlEventTouchUpInside];
        [fg addSubview:btn];
        objc_setAssociatedObject(fg, kWiFiButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGSize s = DMWiFiApplyIconState(icon, tint);
    CGFloat w = ceil(s.width), h = ceil(s.height);
    left -= 8.0 + w;
    BOOL rtl = DMBarRTL(fg);
    icon.frame = DMBarRect(fg, rtl, CGRectMake(left, round(midY - h / 2.0), w, h));
    btn.frame = DMBarRect(fg, rtl, CGRectMake(left - 6.0, 0, w + 12.0, fg.bounds.size.height));
    icon.hidden = btn.hidden = NO;
    [fg bringSubviewToFront:icon]; [fg bringSubviewToFront:btn];
    return left;
}
// (the Lock Screen layout only moves our icons along: the bars are brought up to date here)
static void DMWiFiRefreshIcon(UIView *fg, UIColor *tint) {
    UIView *icon = objc_getAssociatedObject(fg, kWiFiIconKey);
    if (!icon || icon.hidden) return;
    if (!gWiFiMenuOn) { icon.hidden = YES; ((UIView *)objc_getAssociatedObject(fg, kWiFiButtonKey)).hidden = YES; return; }
    DMWiFiApplyIconState(icon, tint);
}

// ---- the menu's own rows ----
@interface DMRow (DMWiFiRow)
- (void)refresh;
- (void)fire:(id)sender forEvent:(UIEvent *)event;
@end
// A section heading ("Known Networks"): small, grey, not a tap target.
@interface DMWiFiHeaderRow : DMRow
@end
@implementation DMWiFiHeaderRow
- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithTitle:title enabled:NO handler:nil];
    if (self) self.label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    return self;
}
- (CGFloat)dmRowHeight { return kWiFiHeaderH; }
- (void)refresh { [super refresh]; self.label.textColor = [UIColor secondaryLabelColor]; }
@end
// "Wi-Fi" with its switch, like the first row of a Mac's Wi-Fi menu.
@interface DMWiFiSwitchRow : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UISwitch *toggle;
@end
@implementation DMWiFiSwitchRow
- (instancetype)initWithOn:(BOOL)on enabled:(BOOL)enabled onChange:(void (^)(BOOL))onChange {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _label = [UILabel new];
    _label.text = @"Wi-Fi";
    _label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    _label.textColor = [UIColor labelColor];
    [self addSubview:_label];
    _toggle = [UISwitch new];
    _toggle.on = on;
    _toggle.enabled = enabled;   // (off when a profile or restriction locks Wi-Fi: WFClient -isPowerModificationDisabled)
    _toggle.onTintColor = [UIColor systemBlueColor];
    _toggle.transform = CGAffineTransformMakeScale(0.72, 0.72);
    void (^change)(BOOL) = [onChange copy];
    __weak UISwitch *weakToggle = _toggle;
    [_toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *a) { if (weakToggle && change) change(weakToggle.on); }] forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];
    return self;
}
- (CGFloat)dmRowHeight { return kWiFiSwitchRowH; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.toggle.bounds.size;   // (unscaled; the transform shrinks it around its centre)
    self.toggle.center = CGPointMake(self.bounds.size.width - 12.0 - s.width * 0.72 / 2.0, self.bounds.size.height / 2.0);
    self.label.frame = CGRectMake(16.0, 0.0, self.bounds.size.width - 32.0 - s.width * 0.72, self.bounds.size.height);
}
@end
// A network: its name (a tick when it is the current one), a lock when it is secured, and its signal bars at the right.
@interface DMWiFiNetworkRow : DMRow
@property (nonatomic, strong) UIImageView *lockView, *barsView;
@property (nonatomic, copy) NSString *logTag;
@end
@implementation DMWiFiNetworkRow
- (instancetype)initWithName:(NSString *)name secure:(BOOL)secure bars:(NSInteger)bars handler:(dispatch_block_t)handler {
    self = [super initWithTitle:name enabled:YES handler:handler];
    if (!self) return nil;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    _logTag = DMWiFiTag(name);
    if (secure) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:9.0 weight:UIImageSymbolWeightSemibold];
        _lockView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill" withConfiguration:cfg]];
        _lockView.contentMode = UIViewContentModeCenter;
        _lockView.userInteractionEnabled = NO;
        [self addSubview:_lockView];
    }
    _barsView = [[UIImageView alloc] initWithImage:DMWiFiFanImage(bars, 10.0)];
    _barsView.contentMode = UIViewContentModeCenter;
    _barsView.userInteractionEnabled = NO;
    [self addSubview:_barsView];
    [self refresh];
    return self;
}
// (DMRow logs the tapped row's title; a network's name never goes to the log)
- (void)fire:(id)sender forEvent:(UIEvent *)event {
    DMLog([NSString stringWithFormat:@"[wifi] network row tapped %@", self.logTag]);
    if (self.handler) self.handler();
}
- (void)refresh {
    [super refresh];
    BOOL lit = self.enabled && (self.hovering || self.highlighted);
    UIColor *c = lit ? [UIColor whiteColor] : [UIColor secondaryLabelColor];
    self.lockView.tintColor = c;
    self.barsView.tintColor = lit ? [UIColor whiteColor] : [UIColor labelColor];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat H = self.bounds.size.height, x = self.bounds.size.width - 14.0;
    CGSize bs = self.barsView.image.size;
    x -= bs.width; self.barsView.frame = CGRectMake(x, (H - bs.height) / 2.0, bs.width, bs.height);
    if (self.lockView) { x -= 6.0 + 9.0; self.lockView.frame = CGRectMake(x, 0.0, 9.0, H); }
    CGRect f = self.label.frame;
    f.size.width = MAX(20.0, x - 8.0 - f.origin.x);
    self.label.frame = f;
}
@end

// ---- actions ----
static void DMWiFiOpenSettings(NSString *ssid) {
    if (!ssid.length) { DMOpenURL(@"prefs:root=WIFI", @"wifi settings"); return; }
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&=+#?/"];
    NSString *enc = [ssid stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    DMOpenURL(enc.length ? [@"prefs:root=WIFI&path=" stringByAppendingString:enc] : @"prefs:root=WIFI", [NSString stringWithFormat:@"wifi settings for %@", DMWiFiTag(ssid)]);
}
// Joining: exactly what a tap in Control Center's list does (the controller joins with the saved password, or opens nothing for an open network).
static void DMWiFiJoin(id record) {
#if DEBUG
    if ([record isKindOfClass:[DMWiFiFakeRecord class]]) { DMLog([NSString stringWithFormat:@"[wifi] test network %@ tapped: nothing joined", DMWiFiTag(DMWiFiRecSSID(record))]); return; }
#endif
    SEL tap = NSSelectorFromString(@"networkListViewController:didTapRecord:");
    id list = DMWiFiListController();
    if (![list respondsToSelector:tap]) { DMLog(@"[wifi] join: the list controller cannot join here, Settings opened"); DMWiFiOpenSettings(DMWiFiRecSSID(record)); return; }
    DMLog([NSString stringWithFormat:@"[wifi] joining %@ (known %d, secure %d)", DMWiFiTag(DMWiFiRecSSID(record)), DMWiFiRecKnown(record), DMWiFiRecSecure(record)]);
    ((void (*)(id, SEL, id, id))objc_msgSend)(list, tap, gWiFiListing, record);
}
// The switch: the list's own power switch (the one Settings' Wi-Fi switch uses -- real on/off, not Control Center's "disconnect until tomorrow").
// Without the list controller, SpringBoard's own manager does it; that is a synchronous call to the Wi-Fi daemon, so it goes off the main thread.
static void DMWiFiSetPower(BOOL on) {
    DMLog([NSString stringWithFormat:@"[wifi] Wi-Fi switched %@ from the menu", on ? @"on" : @"off"]);
    id list = DMWiFiListController();
    SEL power = NSSelectorFromString(@"networkListViewController:userDidChangePower:");
    if ([list respondsToSelector:power]) { ((void (*)(id, SEL, id, BOOL))objc_msgSend)(list, power, gWiFiListing, on); return; }
    static dispatch_queue_t q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.besiktasliseba.macstatusbar.wifipower", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(q, ^{
        id sb = DMWiFiSB(); SEL s = NSSelectorFromString(@"setWiFiEnabled:");
        if ([sb respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(sb, s, on);
        else DMLog(@"[wifi] no way to switch Wi-Fi found");
    });
}


// ---- what a tap on a network does ----
// Known (or open): joined at once, as Control Center does -- an open network that signs in through a web page (a captive network: hotel, cafe)
// gets iOS's own sign-in sheet from the system's captive network support (captiveagent), whoever joined it. Unknown and secured: our password
// sheet. Enterprise (802.1X: a user name, certificates): Settings, which has the forms for that.
typedef NS_ENUM(NSInteger, DMWiFiRoute) { DMWiFiRouteNone, DMWiFiRouteJoin, DMWiFiRoutePassword, DMWiFiRouteSettings };
static BOOL DMWiFiRecEnterprise(id r) { return DMWiFiRecBool(r, @"isEnterprise"); }
static BOOL DMWiFiRecCaptive(id r) { return DMWiFiRecBool(r, @"isCaptive") || DMWiFiRecBool(DMCall(r, @"matchingKnownNetworkProfile"), @"isCaptive"); }
static DMWiFiRoute DMWiFiRouteFor(id r, BOOL current) {
    if (current) return DMWiFiRouteNone;
    if (DMWiFiRecKnown(r)) return DMWiFiRouteJoin;
    if (DMWiFiRecEnterprise(r)) return DMWiFiRouteSettings;
    return DMWiFiRecSecure(r) ? DMWiFiRoutePassword : DMWiFiRouteJoin;
}
static NSString *DMWiFiRouteName(DMWiFiRoute k) { return @[@"nothing (current)", @"join", @"password sheet", @"Settings (enterprise)"][k]; }

// ---- the password sheet: a Mac-style "join this network" dialog in the menu window ----
// Joining goes through the list controller exactly as SpringBoard's own Wi-Fi picker does (WiFiKit's WFPickerViewProvider, read on the M1):
// a tap on the network (-networkListViewController:didTapRecord:) makes the controller ask its view provider for a password with a
// WFCredentialsContext; the answer is an object with -password / -username / -TLSIdentity (the context's provider), then
// -gatherCredentials:nil; Cancel is -cancel. The controller then joins and saves the network like any other join. A wrong password comes back as
// an error context (its message -- "Incorrect password" -- is shown in the sheet; -cancel dismisses it, as the picker's alert does) or as a new
// password request; the sheet stays for another try.
// The password lives here only until the context has read it (-gatherCredentials: reads it at once): then it is cleared, and on every way
// the sheet ends; the field's own text goes with the sheet.
@interface DMWiFiCredentials : UIViewController
@property (nonatomic, copy) NSString *password, *username;
@property (nonatomic, assign) BOOL passwordRead;
@end
@implementation DMWiFiCredentials
- (NSString *)password { if (_password) _passwordRead = YES; return _password; }
- (struct __SecIdentity *)TLSIdentity { return NULL; }
- (void)resetFirstResponder {}
- (void)setActivityString:(id)s {}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [super methodSignatureForSelector:sel] ?: [NSMethodSignature signatureWithObjCTypes:"v@:"]; }
- (void)forwardInvocation:(NSInvocation *)inv {
    DMLog([NSString stringWithFormat:@"[wifi] the password request sent %@, not answered", NSStringFromSelector(inv.selector)]);
    NSUInteger n = inv.methodSignature.methodReturnLength;
    if (n) { void *zero = calloc(1, n); [inv setReturnValue:zero]; free(zero); }
}
@end

@interface DMWiFiPasswordField : UITextField
@property (nonatomic, copy) dispatch_block_t onEscape;
@end
@implementation DMWiFiPasswordField
- (NSArray<UIKeyCommand *> *)keyCommands {   // (Esc = Cancel with a hardware keyboard; Return is the field's own return key = Join)
    UIKeyCommand *esc = [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(dm_escape)];
    if (@available(iOS 15.0, *)) esc.wantsPriorityOverSystemBehavior = YES;
    return @[esc];
}
- (void)dm_escape { if (self.onEscape) self.onEscape(); }
@end

@interface DMWiFiPasswordSheet : NSObject <UITextFieldDelegate>
@property (nonatomic, strong) id record;                    // the network (a WFNetworkScanRecord, or a test record)
@property (nonatomic, copy) NSString *ssid;
@property (nonatomic, strong) id context;                   // the controller's WFCredentialsContext waiting for an answer (nil: none yet)
@property (nonatomic, strong) DMWiFiCredentials *credentials;
@property (nonatomic, copy) NSString *pending;              // typed and Join pressed, waiting for the controller to ask
@property (nonatomic, assign) BOOL joining;
@property (nonatomic, assign) int attempt;
@property (nonatomic, weak) UIView *overlay;
@property (nonatomic, strong) UIView *box;
@property (nonatomic, strong) DMWiFiPasswordField *field;
@property (nonatomic, strong) UILabel *errorLabel, *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *joinButton, *cancelButton, *showButton;
@property (nonatomic, weak) UIWindow *previousKey;          // (the key window before the sheet: it gets the keys back)
@property (nonatomic, strong) id focusLock;                 // (SpringBoard's hold on the keyboard focus while the sheet is up, DMWiFiSheetFocus)
@property (nonatomic, assign) BOOL fake;                    // (tests: wifipwsheet -- the first try is "wrong", the second joins; nothing is sent)
@end
static DMWiFiPasswordSheet *gWiFiSheet = nil;
// The keys come to a field in SpringBoard only while SpringBoard holds the keyboard focus; with an app in front the app holds it (iPad 2,
// Stage Manager, Settings in front: the focus target was Settings' scene). The focus is held while the sheet is up, the way Finder's windows
// and the desktop's rename hold it: -lockFocusToSpringBoardWindowScene:forReason: on iPadOS 16, -lockFocusToSpringBoardForReason: on iPadOS 15;
// given back when it closes (measured: the focus went back to Settings). (A secure field's keyboard is left out of screen captures: a capture
// of the sheet shows no keyboard although it is up -- with "Show password" ticked it shows.)
static void DMWiFiSheetFocus(DMWiFiPasswordSheet *sh, UIWindow *win, BOOL take) {
    if (!take) {
        id l = sh.focusLock; sh.focusLock = nil;
        if ([l respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(l, @selector(invalidate));
        return;
    }
    if (sh.focusLock) return;
    id ws = DMCall(objc_getClass("SBMainWorkspace"), @"sharedInstance");
    id kfc = [ws respondsToSelector:NSSelectorFromString(@"keyboardFocusController")] ? DMCall(ws, @"keyboardFocusController") : nil;
    SEL l16 = NSSelectorFromString(@"lockFocusToSpringBoardWindowScene:forReason:"), l15 = NSSelectorFromString(@"lockFocusToSpringBoardForReason:");
    @try {
        if ([kfc respondsToSelector:l16] && win.windowScene) sh.focusLock = ((id (*)(id, SEL, id, id))objc_msgSend)(kfc, l16, win.windowScene, @"MacStatusBar Wi-Fi password");
        else if ([kfc respondsToSelector:l15]) sh.focusLock = ((id (*)(id, SEL, id))objc_msgSend)(kfc, l15, @"MacStatusBar Wi-Fi password");
    } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wifi] password sheet: the keyboard focus lock threw %@", e.reason]); }
}
static void DMWiFiSheetClose(NSString *why, BOOL cancelContext);
static BOOL DMWiFiMenuWindowKeyable(id self, SEL _cmd) { return gWiFiSheet != nil; }   // (the menu window takes the keys only while the sheet is up)
@implementation DMWiFiPasswordSheet
- (void)dm_refreshButtons {
    BOOL can = !self.joining && self.field.text.length > 0;
    self.joinButton.enabled = can;
    self.joinButton.alpha = can ? 1.0 : 0.45;
    self.field.enabled = !self.joining;
    self.showButton.enabled = !self.joining;
    self.statusLabel.hidden = !self.joining;
    if (self.joining) [self.spinner startAnimating]; else [self.spinner stopAnimating];
}
- (void)dm_showError:(NSString *)text {
    self.joining = NO;
    self.errorLabel.text = text;
    self.errorLabel.hidden = !text.length;
    [self dm_refreshButtons];
    if (self.overlay.window) { [self.field becomeFirstResponder]; [self.field selectAll:nil]; }
    // (a little shake, like a Mac's password field)
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.values = @[@0, @-8, @8, @-6, @6, @-3, @3, @0]; shake.duration = 0.35;
    if (text.length && !MSBReduceMotion()) [self.box.layer addAnimation:shake forKey:@"shake"];   // (Reduce Motion: no shake, the message says it -- 1.3.3, audit L-5)
}
- (void)dm_toggleShow {
    BOOL show = self.field.secureTextEntry;
    self.field.secureTextEntry = !show;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightRegular];
    [self.showButton setImage:[UIImage systemImageNamed:show ? @"checkmark.square.fill" : @"square" withConfiguration:cfg] forState:UIControlStateNormal];
}
- (void)dm_join {
    NSString *pw = self.field.text;
    if (self.joining || !pw.length) return;
    self.attempt++;
    self.joining = YES;
    self.errorLabel.hidden = YES;
    [self dm_refreshButtons];
    DMLog([NSString stringWithFormat:@"[wifi] password sheet: join %@ (try %d)", DMWiFiTag(self.ssid), self.attempt]);
    if (self.fake) {
        int a = self.attempt;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gWiFiSheet != self) return;
            if (a == 1) { DMLog(@"[wifi] password sheet test: wrong password"); [self dm_showError:@"Incorrect password"]; }
            else DMWiFiSheetClose(@"test join done", NO);
        });
        return;
    }
    // a password request already waiting (a retry): answered now; otherwise the network is tapped and the request answered when it comes
    if (self.context) [self dm_answer:self.context password:pw];
    else { self.pending = pw; DMWiFiJoin(self.record); }
    int a = self.attempt;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gWiFiSheet == self && self.joining && self.attempt == a) { DMLog(@"[wifi] password sheet: no answer in 45 s"); self.pending = nil; self.credentials.password = nil; [self dm_showError:@"Couldn't join this network."]; }
    });
}
- (void)dm_answer:(id)ctx password:(NSString *)pw {
    self.context = nil;
    self.pending = nil;
    self.credentials.passwordRead = NO;
    self.credentials.password = pw;
    if (DMCall(ctx, @"provider") != self.credentials && [ctx respondsToSelector:NSSelectorFromString(@"setProvider:")])   // (where the context reads the password)
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setProvider:"), self.credentials);
    SEL gather = NSSelectorFromString(@"gatherCredentials:");
    if (![ctx respondsToSelector:gather]) { DMLog(@"[wifi] password sheet: the request cannot take a password here"); [self dm_showError:@"Couldn't join this network."]; return; }
    // (its argument is an optional callback block; the picker passes nil -- `mov x2, #0` before the call, 15.6.1 -- and so do we: the result
    // comes back as a new request, an error context, or the iPad on the network)
    ((void (*)(id, SEL, id))objc_msgSend)(ctx, gather, nil);
    // (kept until the sheet ends -- joined, Cancel, error, timeout -- not cleared after the first read: WiFiKit may read it again while it joins
    //  and saves the network, and a join must never fail for it; the sheet's every end clears it, 1.3 logic re-check R1)
    DMLog([NSString stringWithFormat:@"[wifi] password sheet: password handed to the list controller (%@)", self.credentials.passwordRead ? @"read" : @"not read yet"]);
}
- (void)dm_cancel { DMWiFiSheetClose(@"Cancel", YES); }
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self dm_join]; return NO; }
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)r replacementString:(NSString *)str {
    dispatch_async(dispatch_get_main_queue(), ^{ if (!self.errorLabel.hidden && !self.joining) self.errorLabel.hidden = YES; [self dm_refreshButtons]; });
    return YES;
}
@end
static UIView *DMWiFiSheetHost(void) {
    for (UIView *fg in gCopies.allObjects) {
        UIButton *b = objc_getAssociatedObject(fg, kWiFiButtonKey);
        if (b && !b.hidden && fg.window && !fg.window.hidden) return DMHostFor(fg);
    }
    for (UIView *fg in gCopies.allObjects) if (fg.window && !fg.window.hidden && objc_getAssociatedObject(fg, kLogoKey)) return DMHostFor(fg);
    return nil;
}
static void DMWiFiSheetClose(NSString *why, BOOL cancelContext) {
    DMWiFiPasswordSheet *sh = gWiFiSheet;
    if (!sh) return;
    if (!cancelContext && sh.context && !sh.joining) cancelContext = YES;   // (a request still waiting is never left open)
    gWiFiSheet = nil;
    sh.credentials.password = nil; sh.pending = nil; sh.field.text = nil;   // (the password goes with the sheet)
    id ctx = sh.context; sh.context = nil;
    if (cancelContext && ctx && [ctx respondsToSelector:@selector(cancel)]) ((void (*)(id, SEL))objc_msgSend)(ctx, @selector(cancel));
    [sh.field resignFirstResponder];
    DMWiFiSheetFocus(sh, nil, NO);
    UIWindow *back = sh.previousKey;
    if (back && !back.hidden && !back.isKeyWindow) [back makeKeyWindow];
    if (sh.overlay && sh.overlay == gOverlay) DMCloseOverlay();
    DMLog([NSString stringWithFormat:@"[wifi] password sheet closed (%@)", why]);
}
// Its overlay went another way (the screen off, another menu...): the sheet goes with it; a password request still waiting is cancelled.
static void DMWiFiSheetDropped(NSString *why) {
    DMWiFiPasswordSheet *sh = gWiFiSheet;
    if (!sh || (sh.overlay && sh.overlay != gOverlay)) return;
    gWiFiSheet = nil;
    sh.credentials.password = nil; sh.pending = nil; sh.field.text = nil;   // (the password goes with the sheet)
    id ctx = sh.context; sh.context = nil;
    if (ctx && !sh.joining && [ctx respondsToSelector:@selector(cancel)]) ((void (*)(id, SEL))objc_msgSend)(ctx, @selector(cancel));
    [sh.field resignFirstResponder];
    DMWiFiSheetFocus(sh, nil, NO);
    UIWindow *back = sh.previousKey;
    if (back && !back.hidden && !back.isKeyWindow) [back makeKeyWindow];
    DMLog([NSString stringWithFormat:@"[wifi] password sheet closed with its overlay (%@)", why]);
}
// iPadOS 16: the menu window is not turned with the screen, and DMMenuHost builds menus in a container turned back (gMenuRotator). Once the
// window is the key window, SpringBoard does turn it (measured, iPad 2 landscape: the window went from 768x1024 to 1024x768 after
// -makeKeyWindow), and the container then turned the sheet a second time, out of view (only the keyboard was seen). While the sheet is up the
// container is fitted again to how the window lies now, measured as DMMenuHost measures it, at once and whenever the window lays out.
static void DMWiFiRefitMenuRotator(void) {
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 16) return;   // (iPadOS 15: the window always turns itself, no container)
    UIView *r = gMenuRotator; UIWindow *w = gMenuWindow;
    if (!r || !w || r.superview != w || !r.subviews.count) return;
    CGSize screen = [UIScreen mainScreen].bounds.size, win = w.bounds.size;
    id<UICoordinateSpace> scr = [UIScreen mainScreen].coordinateSpace;
    CGPoint o = [w convertPoint:CGPointZero toCoordinateSpace:scr], x = [w convertPoint:CGPointMake(100, 0) toCoordinateSpace:scr];
    if (hypot(x.x - o.x, x.y - o.y) < 50.0) return;
    CGFloat angle = -round(atan2(x.y - o.y, x.x - o.x) / M_PI_2) * M_PI_2;
    CGFloat now = atan2(r.transform.b, r.transform.a);
    BOOL same = fabs(remainder(now - angle, 2.0 * M_PI)) < 0.01 && CGSizeEqualToSize(r.bounds.size, screen) && hypot(r.center.x - win.width / 2.0, r.center.y - win.height / 2.0) < 0.5;
    if (same) return;
    r.transform = CGAffineTransformIdentity;
    r.bounds = CGRectMake(0, 0, screen.width, screen.height);
    r.center = CGPointMake(win.width / 2.0, win.height / 2.0);
    r.transform = CGAffineTransformMakeRotation(angle);
    DMLog([NSString stringWithFormat:@"[wifi] password sheet: the menu window lies differently now (window %@, turn %.0f deg): its container fitted again, frame %@",
           NSStringFromCGSize(win), angle * 180.0 / M_PI, NSStringFromCGRect(r.frame)]);
}
static void DMWiFiMenuWindowLayout(UIWindow *self, SEL _cmd) {
    struct objc_super sup = { self, class_getSuperclass(objc_getClass("MSBMenuWindow")) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    if (gWiFiSheet) DMWiFiRefitMenuRotator();
}
// The sheet over everything, like the confirm dialogs (the menu window), its field focused: the hardware keyboard types into it, or the
// on-screen keyboard comes up (the menu window is made the key window, as Finder's sheets do with theirs).
static void DMWiFiShowPasswordSheet(id record, BOOL fake) {
    UIView *host = DMWiFiSheetHost();
    if (!host) { DMLog(@"[wifi] password sheet: no menu bar on the screen, Settings opened"); DMWiFiOpenSettings(DMWiFiRecSSID(record)); return; }
    { id lm = DMSBManager("SBLockScreenManager"); if (DMLockUp(lm)) { DMLog(@"[wifi] password sheet: locked, not shown"); return; } }
    DMWiFiSheetClose(@"replaced", YES);
#if DEBUG
    if ([record isKindOfClass:[DMWiFiFakeRecord class]]) fake = YES;   // (a test network from wififake_: nothing is ever sent)
#endif
    DMWiFiPasswordSheet *sh = [DMWiFiPasswordSheet new];
    sh.record = record; sh.ssid = DMWiFiRecSSID(record) ?: @""; sh.fake = fake;
    sh.credentials = [DMWiFiCredentials new];
    UIControl *o = DMMakeOverlay(host, 0.30);   // (dimmed; a tap outside does nothing, like the confirm dialogs)
    sh.overlay = o;

    const CGFloat W = 320.0, pad = 20.0;
    UIVisualEffectView *box = DMMakeBlur(14.0);
    CGFloat y = 18.0;
    UIImageView *icon = [[UIImageView alloc] initWithImage:DMWiFiFanImage(3, 24.0)];
    icon.tintColor = [UIColor systemBlueColor];
    icon.frame = CGRectMake((W - icon.image.size.width) / 2.0, y, icon.image.size.width, icon.image.size.height);
    [box.contentView addSubview:icon]; y = CGRectGetMaxY(icon.frame) + 10.0;
    UILabel *t = [UILabel new];
    t.text = sh.ssid; t.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]; t.textColor = [UIColor labelColor];
    t.textAlignment = NSTextAlignmentCenter; t.numberOfLines = 2; t.lineBreakMode = NSLineBreakByTruncatingMiddle;
    CGFloat th = ceil([t sizeThatFits:CGSizeMake(W - 2 * pad, 60)].height);
    t.frame = CGRectMake(pad, y, W - 2 * pad, th); [box.contentView addSubview:t]; y += th + 4.0;
    UILabel *m = [UILabel new];
    m.text = @"Enter the password for this Wi-Fi network."; m.font = [UIFont systemFontOfSize:12.0]; m.textColor = [UIColor secondaryLabelColor];
    m.textAlignment = NSTextAlignmentCenter; m.numberOfLines = 0;
    CGFloat mh = ceil([m sizeThatFits:CGSizeMake(W - 2 * pad, 60)].height);
    m.frame = CGRectMake(pad, y, W - 2 * pad, mh); [box.contentView addSubview:m]; y += mh + 14.0;

    DMWiFiPasswordField *f = [DMWiFiPasswordField new];
    f.placeholder = @"Password"; f.secureTextEntry = YES; f.borderStyle = UITextBorderStyleRoundedRect; f.font = [UIFont systemFontOfSize:13.0];
    f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.textContentType = UITextContentTypePassword; f.returnKeyType = UIReturnKeyJoin; f.enablesReturnKeyAutomatically = YES; f.delegate = sh;
    __weak DMWiFiPasswordSheet *weakSheet = sh;
    f.onEscape = ^{ [weakSheet dm_cancel]; };
    f.frame = CGRectMake(pad, y, W - 2 * pad, 28.0); [box.contentView addSubview:f]; y += 28.0 + 8.0;
    sh.field = f;

    UIButton *show = [UIButton buttonWithType:UIButtonTypeSystem];
    [show setTitle:@" Show password" forState:UIControlStateNormal];
    show.titleLabel.font = [UIFont systemFontOfSize:12.0];
    [show setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    show.tintColor = [UIColor systemBlueColor];
    [show setImage:[UIImage systemImageNamed:@"square" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13.0 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
    show.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    show.frame = CGRectMake(pad, y, 150.0, 22.0);
    [show addTarget:sh action:@selector(dm_toggleShow) forControlEvents:UIControlEventTouchUpInside];
    [box.contentView addSubview:show]; sh.showButton = show; y += 22.0 + 6.0;

    UILabel *err = [UILabel new];
    err.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]; err.textColor = [UIColor systemRedColor]; err.numberOfLines = 2;
    err.frame = CGRectMake(pad, y, W - 2 * pad, 30.0); err.hidden = YES; [box.contentView addSubview:err]; sh.errorLabel = err;
    UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spin.hidesWhenStopped = YES; spin.frame = CGRectMake(pad, y + 5.0, 20.0, 20.0); [box.contentView addSubview:spin]; sh.spinner = spin;
    UILabel *st = [UILabel new];
    st.text = @"Joining…"; st.font = [UIFont systemFontOfSize:12.0]; st.textColor = [UIColor secondaryLabelColor];
    st.frame = CGRectMake(pad + 26.0, y, W - 2 * pad - 26.0, 30.0); st.hidden = YES; [box.contentView addSubview:st]; sh.statusLabel = st;
    y += 30.0 + 8.0;

    CGFloat bw = (W - 2 * pad - 10.0) / 2.0;
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem], *join = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal]; [join setTitle:@"Join" forState:UIControlStateNormal];
    for (UIButton *b in @[cancel, join]) { b.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:b == join ? UIFontWeightSemibold : UIFontWeightRegular]; b.layer.cornerRadius = 6.0; b.clipsToBounds = YES; [box.contentView addSubview:b]; }
    cancel.backgroundColor = [UIColor tertiarySystemFillColor]; [cancel setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    join.backgroundColor = [UIColor systemBlueColor]; [join setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancel.frame = CGRectMake(pad, y, bw, 28.0); join.frame = CGRectMake(pad + bw + 10.0, y, bw, 28.0);
    [cancel addTarget:sh action:@selector(dm_cancel) forControlEvents:UIControlEventTouchUpInside];
    [join addTarget:sh action:@selector(dm_join) forControlEvents:UIControlEventTouchUpInside];
    sh.cancelButton = cancel; sh.joinButton = join;
    y += 28.0 + 18.0;

    // (near the top, so the on-screen keyboard never covers it)
    box.frame = CGRectMake(round((o.bounds.size.width - W) / 2.0), MIN(110.0, MAX(40.0, o.bounds.size.height * 0.12)), W, y);
    box.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [o addSubview:box];
    sh.box = box;
    gWiFiSheet = sh;
    [sh dm_refreshButtons];
    box.alpha = 0.0;
    [UIView animateWithDuration:0.15 animations:^{ box.alpha = 1.0; }];
    UIWindow *win = o.window;
    // (the menu window's class -- SpringBoard's orientation window -- refuses to become the key window, and a field in a window that isn't key
    //  never gets the keys: it is allowed to, as Finder's layer window is, but only while the sheet is up)
    Class wc = object_getClass(win);
    if (win && [NSStringFromClass(wc) hasPrefix:@"MSB"]) {
        class_addMethod(wc, @selector(canBecomeKeyWindow), (IMP)DMWiFiMenuWindowKeyable, "B@:");
        class_addMethod(wc, NSSelectorFromString(@"_canBecomeKeyWindow"), (IMP)DMWiFiMenuWindowKeyable, "B@:");
        if ([NSStringFromClass(wc) isEqualToString:@"MSBMenuWindow"]) class_addMethod(wc, @selector(layoutSubviews), (IMP)DMWiFiMenuWindowLayout, "v@:");
    }
    for (UIWindow *w in DMAllWindows()) if (w.isKeyWindow && w != win) { sh.previousKey = w; break; }
    if (win && !win.isKeyWindow) [win makeKeyWindow];
    DMWiFiRefitMenuRotator();
    DMWiFiSheetFocus(sh, win, YES);
    BOOL focused = [f becomeFirstResponder];
    DMLog([NSString stringWithFormat:@"[wifi] password sheet shown for %@ (field focused %d, key window %d, focus lock %@, hardware keyboard %d)%@", DMWiFiTag(sh.ssid), focused, win.isKeyWindow,
           sh.focusLock ? NSStringFromClass([sh.focusLock class]) : @"none", DMHardwareKeyboardAttached(), fake ? @" -- test" : @""]);
}
// The controller asks for a password (after a tap on an unknown secured network, or a known one whose password no longer works).
static id DMWiFiCredentialsRequested(id ctx) {
    if (![NSThread isMainThread]) {   // (never seen: the controller asks on the main thread; handled there, its provider set when the password is handed over)
        dispatch_async(dispatch_get_main_queue(), ^{ DMWiFiCredentialsRequested(ctx); });
        return [UIViewController new];
    }
    id net = DMCall(ctx, @"network");
    NSString *ssid = DMWiFiRecSSID(net);
    if (DMWiFiRecBool(ctx, @"isEnterprise") || DMWiFiRecEnterprise(net)) {   // (a user name, certificates: Settings has the forms)
        DMLog([NSString stringWithFormat:@"[wifi] %@ is an enterprise network: Settings opened", DMWiFiTag(ssid)]);
        DMWiFiSheetClose(@"enterprise", NO);
        dispatch_async(dispatch_get_main_queue(), ^{ if ([ctx respondsToSelector:@selector(cancel)]) ((void (*)(id, SEL))objc_msgSend)(ctx, @selector(cancel)); DMWiFiOpenSettings(ssid); });
        return [UIViewController new];
    }
    DMWiFiPasswordSheet *sh = gWiFiSheet;
    if (!sh || ![sh.ssid isEqualToString:ssid ?: @""]) {   // (no sheet for it yet: shown now, waiting for the password)
        DMWiFiShowPasswordSheet(net, NO);
        sh = gWiFiSheet;
        if (!sh) { if ([ctx respondsToSelector:@selector(cancel)]) dispatch_async(dispatch_get_main_queue(), ^{ ((void (*)(id, SEL))objc_msgSend)(ctx, @selector(cancel)); }); return [UIViewController new]; }
        sh.context = ctx;
        DMLog([NSString stringWithFormat:@"[wifi] the list asks for the password of %@", DMWiFiTag(ssid)]);
        return sh.credentials;
    }
    if (sh.pending) {   // Join was pressed: answered right after the controller has finished presenting it (as the picker does, from the main queue)
        NSString *pw = sh.pending;
        DMLog([NSString stringWithFormat:@"[wifi] the list asks for the password of %@: answered with the typed one", DMWiFiTag(ssid)]);
        dispatch_async(dispatch_get_main_queue(), ^{ if (gWiFiSheet == sh) [sh dm_answer:ctx password:pw]; });
        return sh.credentials;
    }
    // asked again while joining: the password was not accepted
    sh.context = ctx;
    DMLog([NSString stringWithFormat:@"[wifi] the list asks again for the password of %@ (joining %d)", DMWiFiTag(ssid), sh.joining]);
    if (sh.joining) [sh dm_showError:@"Incorrect password"];
    return sh.credentials;
}
// The controller reports a failed join: shown in the sheet when it is about the sheet's network, then dismissed (-cancel) as the picker's alert does.
static void DMWiFiErrorReported(id ctx) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *e = DMCall(ctx, @"error");
        NSString *ssid = DMWiFiRecSSID(DMCall(ctx, @"network"));
        DMLog([NSString stringWithFormat:@"[wifi] join error for %@: domain %@ code %ld", DMWiFiTag(ssid), [e isKindOfClass:[NSError class]] ? e.domain : @"?", [e isKindOfClass:[NSError class]] ? (long)e.code : 0L]);
        DMWiFiPasswordSheet *sh = gWiFiSheet;
        if (sh && (!ssid.length || [sh.ssid isEqualToString:ssid])) {
            NSString *text = [e isKindOfClass:[NSError class]] && e.localizedDescription.length < 80 ? e.localizedDescription : nil;
            sh.pending = nil; sh.context = nil; sh.credentials.password = nil;
            [sh dm_showError:text.length ? text : @"Incorrect password"];
        }
        if ([ctx respondsToSelector:@selector(cancel)]) ((void (*)(id, SEL))objc_msgSend)(ctx, @selector(cancel));
    });
}
// (joined: the sheet goes once the iPad is on the network it was for)
static void DMWiFiSheetCheckJoined(void) {
    DMWiFiPasswordSheet *sh = gWiFiSheet;
    if (!sh || !sh.joining || sh.fake) return;
    if (DMWiFiAssociated() && [DMWiFiCurrentName() isEqualToString:sh.ssid]) DMWiFiSheetClose(@"joined", NO);
}

// ---- the menu ----
static NSArray *DMWiFiRecords(void) {
#if DEBUG
    if (gWiFiFake) return gWiFiFake;
#endif
    return gWiFiListing.records ?: @[];
}
static NSString *gWiFiMenuSignature = nil;   // (what the open menu shows: rebuilt only when this changes)
static NSArray *DMWiFiMenuItems(NSString **signatureOut) {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableString *sig = [NSMutableString string];
    BOOL powered = DMWiFiPowered();
#if DEBUG
    if (gWiFiFake && gWiFiFakeState != 1) powered = YES;
#endif
    BOOL locked = DMWiFiRecBool(DMWiFiClient(), @"isPowerModificationDisabled");
    [items addObject:[[DMWiFiSwitchRow alloc] initWithOn:powered enabled:!locked onChange:^(BOOL on) { DMWiFiSetPower(on); }]];
    [sig appendFormat:@"p%d%d|", powered, locked];
    if (powered) {
        // the current network: the controller's record (it knows the lock), else SpringBoard's own name and bars
        NSString *curName = nil; BOOL curSecure = NO; NSInteger curBars = 0;
        if (DMWiFiAssociated()) {
            id rec = gWiFiListing.current ?: DMCall(DMWiFiClient(), @"currentNetwork");
            curName = DMWiFiRecSSID(rec) ?: DMWiFiCurrentName();
            curSecure = rec ? DMWiFiRecSecure(rec) : NO;
            curBars = DMWiFiBars();
        }
#if DEBUG
        if (gWiFiFake.count) { id f = gWiFiFake.firstObject; curName = DMWiFiRecSSID(f); curSecure = DMWiFiRecSecure(f); curBars = DMWiFiRecBars(f); }
#endif
        if (curName.length) {
            [items addObject:[NSNull null]];
            DMWiFiNetworkRow *row = [[DMWiFiNetworkRow alloc] initWithName:curName secure:curSecure bars:curBars handler:DMCloseThen(^{})];   // (the current one: like a Mac, nothing to do)
            row.checked = YES;
            [items addObject:row];
            [sig appendFormat:@"c%@%d%ld|", curName, curSecure, (long)curBars];
        }
        // the networks nearby (not the current one; one row per name, the strongest; hidden or nameless ones left out), strongest first
        NSMutableDictionary<NSString *, id> *best = [NSMutableDictionary dictionary];
        for (id r in DMWiFiRecords()) {
            NSString *n = DMWiFiRecSSID(r);
            if (DMWiFiNameBlank(n) || [n isEqualToString:curName] || DMWiFiRecBool(r, @"isHidden") || DMWiFiRecBool(r, @"isUnconfiguredAccessory")) continue;
            if (!best[n] || DMWiFiRecScaled(r) > DMWiFiRecScaled(best[n])) best[n] = r;
        }
        NSArray *sorted = [best.allValues sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            float fa = DMWiFiRecScaled(a), fb = DMWiFiRecScaled(b);
            if (fa != fb) return fa > fb ? NSOrderedAscending : NSOrderedDescending;
            return [DMWiFiRecSSID(a) localizedCaseInsensitiveCompare:DMWiFiRecSSID(b)];
        }];
        // (while the menu is open its rows keep the order it first showed -- signal changes update a row in place, a network that appears is added
        //  at the end --: the scan's results arrive in parts, and a row that moved between seeing and tapping it joined another network)
        if (gWiFiMenuOrder) {
            NSMutableArray<NSString *> *order = gWiFiMenuOrder;
            for (id r in sorted) { NSString *n = DMWiFiRecSSID(r); if (![order containsObject:n]) [order addObject:n]; }
            sorted = [sorted sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSUInteger ia = [order indexOfObject:DMWiFiRecSSID(a)], ib = [order indexOfObject:DMWiFiRecSSID(b)];
                return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
            }];
        }
        NSMutableArray *names = [NSMutableArray array]; for (id r in sorted) [names addObject:DMWiFiRecSSID(r)];
        gWiFiLastOrder = names;
        NSMutableArray *known = [NSMutableArray array], *other = [NSMutableArray array];
        for (id r in sorted) [(DMWiFiRecKnown(r) ? known : other) addObject:r];
        // (as many rows as fit on the screen under the menu bar: the rest are in Settings, "Other Networks…")
        CGFloat room = [UIScreen mainScreen].bounds.size.height - 40.0 - 12.0 - 2.0 * kPanelPad - kWiFiSwitchRowH - 2.0 * kSepH - 2.0 * kRowH - (curName.length ? kRowH + kSepH : 0.0);
        NSInteger fit = MAX(2, (NSInteger)floor((room - 2.0 * kWiFiHeaderH) / kRowH));
        if (known.count + other.count > (NSUInteger)fit) {
            NSUInteger k = MIN(known.count, (NSUInteger)MAX(1, fit / 2));
            if (other.count < (NSUInteger)(fit - k)) k = MIN(known.count, (NSUInteger)fit - other.count);
            [known removeObjectsInRange:NSMakeRange(k, known.count - k)];
            if (other.count > (NSUInteger)(fit - k)) [other removeObjectsInRange:NSMakeRange(fit - k, other.count - (fit - k))];
        }
        if (known.count || other.count) [items addObject:[NSNull null]];
        for (int section = 0; section < 2; section++) {
            NSArray *list = section == 0 ? known : other;
            if (!list.count) continue;
            [items addObject:[[DMWiFiHeaderRow alloc] initWithTitle:section == 0 ? @"Known Networks" : @"Nearby Networks"]];
            for (id r in list) {
                NSString *n = DMWiFiRecSSID(r);
                BOOL secure = DMWiFiRecSecure(r), isKnown = DMWiFiRecKnown(r);
                NSInteger bars = DMWiFiRecBars(r);
                // (DMWiFiRouteFor: joined, the password sheet, or Settings for an enterprise network)
                DMWiFiRoute route = DMWiFiRouteFor(r, NO);
                dispatch_block_t act = route == DMWiFiRoutePassword ? ^{ DMWiFiShowPasswordSheet(r, NO); }
                                     : route == DMWiFiRouteSettings ? ^{ DMLog([NSString stringWithFormat:@"[wifi] %@ is an enterprise network: Settings opened", DMWiFiTag(n)]); DMWiFiOpenSettings(n); }
                                     : ^{ DMWiFiJoin(r); };
                (void)isKnown;
                [items addObject:[[DMWiFiNetworkRow alloc] initWithName:n secure:secure bars:bars handler:DMCloseThen(act)]];
                [sig appendFormat:@"%d%@%d%ld|", section, n, secure, (long)bars];
            }
        }
        if (!known.count && !other.count && !gWiFiListing.everScanned && gWiFiList) {
            [items addObject:[NSNull null]];
            [items addObject:[[DMRow alloc] initWithTitle:@"Scanning…" enabled:NO handler:nil]];
            [sig appendString:@"s|"];
        }
    }
    [items addObject:[NSNull null]];
    if (powered) [items addObject:[[DMRow alloc] initWithTitle:@"Other Networks…" enabled:YES handler:DMCloseThen(^{ DMWiFiOpenSettings(nil); })]];
    [items addObject:[[DMRow alloc] initWithTitle:@"Wi-Fi Settings…" enabled:YES handler:DMCloseThen(^{ DMWiFiOpenSettings(nil); })]];
    if (signatureOut) *signatureOut = sig;
    return items;
}
static void DMWiFiLogMenu(NSString *what) {
    NSArray *recs = DMWiFiRecords();
    NSUInteger secure = 0, known = 0;
    for (id r in recs) { if (DMWiFiRecSecure(r)) secure++; if (DMWiFiRecKnown(r)) known++; }
    DMLog([NSString stringWithFormat:@"[wifi] menu %@: powered %d, associated %d, bars %ld, %lu nearby (%lu secure, %lu known), scanning %d", what, DMWiFiPowered(),
           DMWiFiAssociated(), (long)(DMWiFiAssociated() ? DMWiFiBars() : 0), (unsigned long)recs.count, (unsigned long)secure, (unsigned long)known, gWiFiScanning]);
}
// The open menu is rebuilt in place when what it shows changes (a scan's results arrive in parts: at most once per 0.3 s), at the same place.
static BOOL gWiFiRebuildPending = NO;
static void DMWiFiRebuildOpenMenu(void) {
    UIView *old = gWiFiPanel;
    if (!old.window || !old.superview) return;
    // (Wi-Fi switched on from the menu: the scan starts now, within the open menu's 30 s)
    if (!gWiFiScanning && DMWiFiPowered() && CACurrentMediaTime() - gWiFiOpenedAt < 30.0 && [gWiFiList respondsToSelector:@selector(startScanning)]) {
        ((void (*)(id, SEL))objc_msgSend)(gWiFiList, @selector(startScanning));
        gWiFiScanning = YES;
        DMLog(@"[wifi] scanning started (Wi-Fi on)");
    }
    NSString *sig = nil;
    NSArray *items = DMWiFiMenuItems(&sig);
    if ([sig isEqualToString:gWiFiMenuSignature]) return;
    gWiFiMenuSignature = sig;
    UIView *panel = DMMakePanel(items);
    CGRect f = panel.frame; f.origin = old.frame.origin;
    if ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) f.origin.x = CGRectGetMaxX(old.frame) - f.size.width;   // (hung from its title's right edge: that edge stays)
    panel.frame = f;
    [old.superview insertSubview:panel aboveSubview:old];
    [old removeFromSuperview];
    gWiFiPanel = panel;
    DMWiFiLogMenu(@"updated");
}
static void DMWiFiListChanged(void) {
    DMWiFiSheetCheckJoined();
    for (UIView *fg in gCopies.allObjects) if (objc_getAssociatedObject(fg, kWiFiIconKey)) [fg setNeedsLayout];
    if (!gWiFiPanel || gWiFiRebuildPending) return;
    gWiFiRebuildPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ gWiFiRebuildPending = NO; DMWiFiRebuildOpenMenu(); });
}
static void DMOpenWiFiMenu(UIButton *btn) {
    if (DMTitleTapWithMenuOpen(btn)) return;
    DM_FEATURE_MARK("wifi-menu");
    DMWiFiListController();   // (made at the first menu: its cached results show at once)
    if (!gWiFiListing.records.count && [DMCall(gWiFiList, @"networks") isKindOfClass:[NSSet class]]) gWiFiListing.records = [DMCall(gWiFiList, @"networks") allObjects];
    gWiFiMenuOrder = nil; gWiFiLastOrder = nil;
    NSString *sig = nil;
    NSArray *items = DMWiFiMenuItems(&sig);
    DMPresentMenu(btn, kWiFiMenuLabelKey, kWiFiMenuPillKey, items);
    UIView *panel = gOverlay.subviews.lastObject;
    if (!gOverlay || !panel) return;   // (not opened: the Lock Screen)
    gWiFiPanel = panel;
    gWiFiMenuSignature = sig;
    gWiFiMenuOrder = [gWiFiLastOrder mutableCopy] ?: [NSMutableArray array];   // (strongest first as it opened; kept while it is open)
    DMWiFiStartScanning();
    DMWiFiLogMenu(@"opened");
}

// ---- the switch (DMLoadPrefs) and keeping the icon current ----
// What the menu needs from this iPad: SpringBoard's Wi-Fi manager and WiFiKit's network list controller with the calls Control Center's own Wi-Fi
// list makes (checked once, nothing created). The Wi-Fi Menu is on by default only where all of them are there (owner, 3 Oct: "on if it works
// on the installed device"); elsewhere iOS's own Wi-Fi item stays.
static BOOL DMWiFiSupported(void) {
    static BOOL supported = NO;   // (only a yes is kept: a no is asked again, in case WiFiKit was not loaded yet)
    if (supported) return YES;
    Class sb = objc_getClass("SBWiFiManager"), lc = objc_getClass("WFNetworkListController");
    BOOL ok = sb && [sb respondsToSelector:@selector(sharedInstance)] && lc && objc_getClass("WFClient");
    for (NSString *sel in @[@"initWithViewController:viewProvider:client:", @"startScanning", @"stopScanning", @"networkListViewController:didTapRecord:", @"networkListViewController:userDidChangePower:"])
        if (ok && ![lc instancesRespondToSelector:NSSelectorFromString(sel)]) { ok = NO; DMLog([NSString stringWithFormat:@"[wifi] not supported here: WFNetworkListController lacks %@", sel]); }
    if (!ok) DMLog([NSString stringWithFormat:@"[wifi] not supported here (Wi-Fi manager %d, list controller %d, client %d)", sb != Nil, lc != Nil, objc_getClass("WFClient") != Nil]);
    supported = ok;
    return ok;
}
static void DMWiFiApplyPref(BOOL want) {
    BOOL on = want && [NSProcessInfo processInfo].operatingSystemVersion.majorVersion < 17;   // (iPadOS 17+: not checked there, stock behaviour)
    if (on == gWiFiMenuOn) return;
    gWiFiMenuOn = on;
    DMLog([NSString stringWithFormat:@"[wifi] Wi-Fi Menu %@", on ? @"on" : @"off"]);
    static BOOL observing = NO;
    if (on && !observing) {
        observing = YES;
        // (SpringBoard's Wi-Fi manager posts these from its own thread: the views are touched on the main thread)
        for (NSString *n in @[@"SBWifiManagerLinkDidChangeNotification", @"SBWifiManagerPowerStateDidChangeNotification"])
            [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ if (gWiFiMenuOn) DMWiFiListChanged(); });
            }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gWiFiMenuOn) DMWiFiSheetClose(@"Wi-Fi Menu off", YES);   // (the password sheet too, its request cancelled)
        if (!gWiFiMenuOn && gWiFiPanel) DMCloseOverlay();
        for (UIView *fg in gCopies.allObjects) {
            if (objc_getAssociatedObject(fg, kLogoKey)) DMStockVPNRecheck(fg);   // (iOS's own Wi-Fi item asked again: out, or back)
            [fg setNeedsLayout];
        }
    });
}

#if DEBUG
// ---- debug triggers (wifiprobe, wifimenu, wifidump, wifiscan, wifiscanstop, wififake_<n>, wifipref_<on|off>, wifisettings[_current]) ----
static BOOL DMWiFiTrigger(NSString *cmd) {
    if ([cmd isEqualToString:@"wifiprobe"]) {   // which of the private calls this iPadOS has (names and booleans only)
        NSMutableString *o = [NSMutableString stringWithString:@"[wifiprobe]"];
        NSDictionary *sels = @{
            @"WFNetworkListController": @[@"initWithViewController:viewProvider:client:", @"startScanning", @"stopScanning", @"networks", @"networkListViewController:didTapRecord:", @"networkListViewController:userDidChangePower:", @"networkListViewControllerDidAppear:"],
            @"WFNetworkScanRecord": @[@"ssid", @"isSecure", @"isEnterprise", @"isKnown", @"matchingKnownNetworkProfile", @"signalBars", @"scaledRSSI", @"isHidden", @"isUnconfiguredAccessory"],
            @"WFClient": @[@"currentNetwork", @"isPowerModificationDisabled", @"powered", @"interface"],
            @"WFCredentialsContext": @[@"network", @"provider", @"setProvider:", @"gatherCredentials:", @"cancel", @"isEnterprise", @"finishWithError:forNetwork:profile:"],
            @"WFErrorContext": @[@"error", @"network", @"cancel"],
            @"WFNetworkProfile": @[@"isCaptive"],
            @"WFPasswordPromptOperation": @[@"password", @"username", @"TLSIdentity", @"credentialsProviderContext"],
            @"SBWiFiManager": @[@"isPowered", @"isAssociated", @"signalStrengthBars", @"currentNetworkName", @"setWiFiEnabled:", @"wiFiEnabled"],
            @"_UIStatusBarWifiSignalView": @[@"setNumberOfBars:", @"setNumberOfActiveBars:", @"setActiveColor:", @"setInactiveColor:", @"setSignalMode:", @"setIconSize:", @"iconSize"],
        };
        for (NSString *cn in sels) {
            Class c = objc_getClass(cn.UTF8String);
            [o appendFormat:@"\n  %@ %@:", cn, c ? @"present" : @"MISSING"];
            for (NSString *s in sels[cn]) {
                Method m = class_getInstanceMethod(c, NSSelectorFromString(s));
                [o appendFormat:@" %@=%@", s, m ? [NSString stringWithUTF8String:method_getTypeEncoding(m)] : @"NO"];
            }
        }
        for (NSString *pn in @[@"WFNetworkListing", @"WFNetworkViewProvider"]) {
            Protocol *p = objc_getProtocol(pn.UTF8String);
            [o appendFormat:@"\n  protocol %@ %@:", pn, p ? @"present" : @"MISSING"];
            for (int req = 1; req >= 0 && p; req--) {
                unsigned n = 0; struct objc_method_description *d = protocol_copyMethodDescriptionList(p, req, YES, &n);
                [o appendFormat:@" [%@]", req ? @"required" : @"optional"];
                for (unsigned i = 0; i < n; i++) [o appendFormat:@" %@=%s%@", NSStringFromSelector(d[i].name), d[i].types, [DMWiFiListing instancesRespondToSelector:d[i].name] ? @"" : @"(not answered)"];
                free(d);
            }
        }
        Class cc = objc_getClass("CCUIWiFiMenuModuleViewController");
        for (NSString *s in @[@"setCurrentNetworkScaledRSSI:", @"setCurrentNetworkSignalBars:", @"setCurrentNetworkState:", @"powerStateDidChange:", @"setScanning:", @"setNetworks:", @"setDeviceCapability:"]) {
            Method m = class_getInstanceMethod(cc, NSSelectorFromString(s));
            [o appendFormat:@"\n  Control Center's %@ = %s", s, m ? method_getTypeEncoding(m) : "none"];
        }
        // iOS's own Wi-Fi signal views in our bars (size class, bars, size)
        Class sv = objc_getClass("_UIStatusBarWifiSignalView");
        for (UIView *fg in gCopies.allObjects) {
            NSMutableArray *pending = [NSMutableArray arrayWithObject:fg];
            while (pending.count) {
                UIView *v = pending.lastObject; [pending removeLastObject]; [pending addObjectsFromArray:v.subviews];
                if (!sv || ![v isKindOfClass:sv]) continue;
                [o appendFormat:@"\n  signal view in %p: size %@ intrinsic %@ hidden %d window %d", fg,
                    NSStringFromCGSize(v.bounds.size), NSStringFromCGSize(v.intrinsicContentSize), v.hidden, v.window != nil];
                if ([v respondsToSelector:@selector(iconSize)]) [o appendFormat:@" iconSize=%lld", ((long long (*)(id, SEL))objc_msgSend)(v, @selector(iconSize))];
                if ([v respondsToSelector:NSSelectorFromString(@"numberOfActiveBars")]) [o appendFormat:@" active=%lld", ((long long (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"numberOfActiveBars"))];
                if ([v respondsToSelector:NSSelectorFromString(@"signalMode")]) [o appendFormat:@" mode=%lld", ((long long (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"signalMode"))];
            }
        }
        [o appendFormat:@"\n  Wi-Fi Menu %d, client %d, list %d", gWiFiMenuOn, DMWiFiClient() != nil, gWiFiList != nil];
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"wifimenu"]) {   // open the Wi-Fi menu from the visible status bar
        for (UIView *fg in gCopies.allObjects) {
            UIButton *b = objc_getAssociatedObject(fg, kWiFiButtonKey);
            if (b && !b.hidden && fg.window && !fg.window.hidden) { DMOpenWiFiMenu(b); return YES; }
        }
        DMLog(@"[wifi] wifimenu: no Wi-Fi icon on the screen (switch off?)");
        return YES;
    }
    if ([cmd isEqualToString:@"wifidump"]) {   // the state, network names hashed
        id cur = gWiFiListing.current ?: DMCall(DMWiFiClient(), @"currentNetwork");
        NSMutableString *o = [NSMutableString stringWithFormat:@"[wifidump] menu on %d, powered %d, associated %d, bars %ld, current %@ (secure %d known %d), list %d, listing current %d, power %d, scanning %d (list says %d), panel open %d, icons:",
            gWiFiMenuOn, DMWiFiPowered(), DMWiFiAssociated(), (long)DMWiFiBars(), DMWiFiTag(DMWiFiCurrentName()), DMWiFiRecSecure(cur), DMWiFiRecKnown(cur), gWiFiList != nil,
            gWiFiListing.current != nil, gWiFiListing.hasPower, gWiFiScanning, gWiFiListing.isScanning, gWiFiPanel.window != nil];
        for (UIView *fg in gCopies.allObjects) {
            UIView *icon = objc_getAssociatedObject(fg, kWiFiIconKey);
            if (icon) [o appendFormat:@" %p %@ %@ hidden %d;", fg, NSStringFromClass([icon class]), NSStringFromCGRect(icon.frame), icon.hidden];
        }
        for (id r in DMWiFiRecords()) [o appendFormat:@"\n  %@ secure %d known %d bars %ld scaled %.2f hidden %d blank %d length %lu", DMWiFiTag(DMWiFiRecSSID(r)), DMWiFiRecSecure(r), DMWiFiRecKnown(r), (long)DMWiFiRecBars(r), DMWiFiRecScaled(r), DMWiFiRecBool(r, @"isHidden"), DMWiFiNameBlank(DMWiFiRecSSID(r)), (unsigned long)DMWiFiRecSSID(r).length];
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"wifiscan"]) {   // a 10 s scan without the menu, then the counts
        DMWiFiListController();
        BOOL was = gWiFiScanning;
        if (!was && [gWiFiList respondsToSelector:@selector(startScanning)]) { ((void (*)(id, SEL))objc_msgSend)(gWiFiList, @selector(startScanning)); gWiFiScanning = YES; gWiFiOpenedAt = CACurrentMediaTime(); }
        DMLog([NSString stringWithFormat:@"[wifi] test scan started (list %d)", gWiFiList != nil]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DMWiFiLogMenu(@"test scan, after 10 s");
            if (!gWiFiPanel) DMWiFiStopScanning(@"test scan over");
        });
        return YES;
    }
    if ([cmd isEqualToString:@"wifiscanstop"]) {   // is a scan still running?
        DMLog([NSString stringWithFormat:@"[wifi] scanning now: ours %d, the list says %d, watchdog %d, menu open %d", gWiFiScanning, gWiFiListing.isScanning, gWiFiWatchdog != nil, gWiFiPanel.window != nil]);
        return YES;
    }
    if ([cmd hasPrefix:@"wififake_"]) {   // wififake_<n>: n made-up networks (long names, every bar count, locks); wififake_0 back to the real ones
        int n = [[cmd substringFromIndex:9] intValue];
        if (n <= 0) gWiFiFake = nil;
        else {
            NSMutableArray *fake = [NSMutableArray array];
            for (int i = 0; i < n; i++) {
                DMWiFiFakeRecord *r = [DMWiFiFakeRecord new];
                r.ssid = i % 7 == 3 ? [NSString stringWithFormat:@"Test Network With A Very Long Name Number %d", i] : [NSString stringWithFormat:@"Test Network %d", i];
                r.isSecure = i % 3 != 2; r.isKnown = i % 4 == 0; r.signalBars = 1 + i % 3; r.scaledRSSI = 1.0f - i * 0.02f;
                r.isEnterprise = i % 5 == 1 && r.isSecure && !r.isKnown;   // (every fifth: an 802.1X network)
                r.isCaptive = i % 3 == 2;                                    // (the open ones sign in through a web page)
                if (r.isEnterprise) r.ssid = [r.ssid stringByAppendingString:@" Enterprise"];
                if (r.isCaptive) r.ssid = [r.ssid stringByAppendingString:@" Open"];
                [fake addObject:r];
            }
            gWiFiFake = fake;
        }
        DMLog([NSString stringWithFormat:@"[wifi] test networks: %d", n]);
        DMWiFiListChanged();
        return YES;
    }
    if ([cmd isEqualToString:@"wifiroute"]) {   // what a tap on each listed network would do (no tap is made)
        NSMutableString *o = [NSMutableString stringWithString:@"[wifiroute]"];
        for (id r in DMWiFiRecords()) [o appendFormat:@"\n  %@ secure %d known %d enterprise %d captive %d -> %@", DMWiFiTag(DMWiFiRecSSID(r)), DMWiFiRecSecure(r), DMWiFiRecKnown(r), DMWiFiRecEnterprise(r), DMWiFiRecCaptive(r), DMWiFiRouteName(DMWiFiRouteFor(r, NO))];
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"wifipwsheet"]) {   // the password sheet for a test network: the first Join is "wrong", the second "joins" (nothing is sent)
        DMWiFiFakeRecord *r = [DMWiFiFakeRecord new]; r.ssid = @"Test Network"; r.isSecure = YES; r.signalBars = 3; r.scaledRSSI = 0.9f;
        DMWiFiShowPasswordSheet(r, YES);
        return YES;
    }
    if ([cmd hasPrefix:@"wifipwerror"]) {   // the open sheet shows a join error (wifipwerror: the wrong-password text)
        [gWiFiSheet dm_showError:@"Incorrect password"];
        return YES;
    }
    if ([cmd isEqualToString:@"wifictxtest"]) {   // a real WFCredentialsContext, as the controller makes it, for an unknown secured network of the last scan.
        // Its completion handler is our own and only logs what the controller would read through the context (the typed password's length):
        // nothing is joined, the radio is not used. (WFNetworkScanRecord cannot be made by hand: -init throws -- 2 Oct, M1.)
        @try {
            id rec = nil;
            for (id r in gWiFiListing.records) if (DMWiFiRouteFor(r, NO) == DMWiFiRoutePassword) { rec = r; break; }
            Class cc = objc_getClass("WFCredentialsContext");
            SEL init = NSSelectorFromString(@"initWithNetwork:profile:");
            if (!rec || ![cc instancesRespondToSelector:init]) { DMLog(@"[wifictx] no unknown secured network in the last scan (open the menu first)"); return YES; }
            id profile = [objc_getClass("WFNetworkProfile") instancesRespondToSelector:@selector(initWithNetwork:)] ? ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("WFNetworkProfile") alloc], @selector(initWithNetwork:), rec) : nil;   // (as the controller makes one for a network it doesn't know)
            id ctx = ((id (*)(id, SEL, id, id))objc_msgSend)([cc alloc], init, rec, profile);
            __weak id weakCtx = ctx;
            void (^done)(void *, void *, void *) = ^(void *a, void *b, void *c) {
                id p = DMCall(weakCtx, @"provider");
                DMLog([NSString stringWithFormat:@"[wifictx] completion handler called (args %d %d): provider is our credentials %d, password set %d", a != NULL, b != NULL,
                       [p isKindOfClass:[DMWiFiCredentials class]], [DMCall(p, @"password") length] > 0]);
            };
            void (^cancelled)(void) = ^{ DMLog(@"[wifictx] cancellation handler called"); };
            ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setCompletionHandler:"), done);
            ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setCancellationHandler:"), cancelled);
            id vc = [gWiFiListing credentialsViewControllerWithContext:ctx];                          // (as the controller asks)
            ((void (*)(id, SEL, id))objc_msgSend)(ctx, NSSelectorFromString(@"setProvider:"), vc);     // (and then sets, see -_promptCredentialsForNetwork:profile:)
            if (gWiFiSheet) gWiFiSheet.fake = NO;
            objc_setAssociatedObject([DMWiFiListing class], &kWiFiMenuLabelKey, ctx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // (kept alive for the test)
            DMLog([NSString stringWithFormat:@"[wifictx] context made for %@, answered with %@", DMWiFiTag(DMWiFiRecSSID(rec)), NSStringFromClass([vc class])]);
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wifictx] exception %@", e.name]); }
        return YES;
    }
    if ([cmd isEqualToString:@"wifictxerror"]) {   // the controller's error report for the sheet's network, with a stand-in context (error, network, cancel)
        @try {
            DMWiFiFakeErrorContext *ctx = [DMWiFiFakeErrorContext new];
            ctx.error = [NSError errorWithDomain:@"WFTestDomain" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Incorrect password"}];
            ctx.network = gWiFiSheet.record;
            [gWiFiListing ?: [DMWiFiListing new] networkErrorViewControllerWithContext:ctx];
        } @catch (NSException *e) { DMLog([NSString stringWithFormat:@"[wifictx] exception %@", e.name]); }
        return YES;
    }
    if ([cmd isEqualToString:@"wifipwtap_show"]) { [gWiFiSheet dm_toggleShow]; return YES; }   // (the Show password box, as a tap does)
    if ([cmd isEqualToString:@"wifikbwins"]) {   // every window's level and render state (context id, layer hidden / opacity, scene): where the keyboard went (read-only)
        NSMutableString *o = [NSMutableString stringWithString:@"[wifikbwins]"];
        for (UIWindow *w in DMAllWindows()) {
            unsigned ctx = [w respondsToSelector:NSSelectorFromString(@"_contextId")] ? ((unsigned (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"_contextId")) : 0;
            [o appendFormat:@"\n  %@ level %.1f hidden %d alpha %.2f layer hidden %d opacity %.2f context %u scene %p screen %p key %d", NSStringFromClass([w class]), w.windowLevel, w.hidden, w.alpha,
                w.layer.hidden, w.layer.opacity, ctx, w.windowScene, w.screen, w.isKeyWindow];
        }
        DMLog(o);
        return YES;
    }
    if ([cmd isEqualToString:@"wifisheetstate"]) {   // the sheet as it is now (never its text)
        DMWiFiPasswordSheet *sh = gWiFiSheet;
        UIResponder *first = nil; @try { first = [sh.field.window valueForKey:@"firstResponder"]; } @catch (id e) {}
        DMLog(sh ? [NSString stringWithFormat:@"[wifisheet] %@: %lu characters typed, hidden %d, joining %d, error shown %d, join enabled %d, field focused %d, window key %d, waiting request %d, test %d",
                    DMWiFiTag(sh.ssid), (unsigned long)sh.field.text.length, sh.field.secureTextEntry, sh.joining, !sh.errorLabel.hidden, sh.joinButton.enabled, sh.field.isFirstResponder, sh.field.window.isKeyWindow, sh.context != nil, sh.fake]
                 : @"[wifisheet] no sheet");
        (void)first;
        return YES;
    }
    if ([cmd hasPrefix:@"wififakestate_"]) {   // wififakestate_<0|1|2>: draw the icon and menu as real / Wi-Fi off / on but not joined (the radio is not touched)
        gWiFiFakeState = [[cmd substringFromIndex:14] intValue];
        DMLog([NSString stringWithFormat:@"[wifi] test state %d", gWiFiFakeState]);
        DMWiFiListChanged();
        return YES;
    }
    if ([cmd hasPrefix:@"wifipref_"]) {   // wifipref_on / wifipref_off: the Settings switch, as Settings writes it
        BOOL on = [cmd hasSuffix:@"on"];
        CFPreferencesSetValue(CFSTR("wifiMenu"), on ? kCFBooleanTrue : kCFBooleanFalse, MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize(MSB_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        notify_post("com.besiktasliseba.macstatusbar/prefsChanged");
        return YES;
    }
    if ([cmd hasPrefix:@"wifiurl_"]) {   // wifiurl_<path|current>[_handle]: how WiFiKit's own URL handling reads prefs:root=WIFI&path=<path> (keys only; _handle also runs it on our list)
        NSArray *q = [[cmd substringFromIndex:8] componentsSeparatedByString:@"_"];
        NSString *path = [q[0] isEqualToString:@"current"] ? (DMWiFiCurrentName() ?: @"") : q[0];
        NSString *enc = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
        NSURL *url = [NSURL URLWithString:[@"prefs:root=WIFI&path=" stringByAppendingString:enc]];
        id list = DMWiFiListController();
        SEL kv = NSSelectorFromString(@"keyValueDictionaryForURL:"), hu = NSSelectorFromString(@"handleURL:");
        id dict = [list respondsToSelector:kv] ? ((id (*)(id, SEL, id))objc_msgSend)(list, kv, url) : nil;
        NSMutableString *o = [NSMutableString stringWithFormat:@"[wifiurl] path %@: dictionary %@ with", [q[0] isEqualToString:@"current"] ? DMWiFiTag(path) : path, NSStringFromClass([dict class])];
        if ([dict isKindOfClass:[NSDictionary class]]) for (id k in dict) [o appendFormat:@" %@=%@", k, [dict[k] isEqual:path] ? @"<the path>" : ([dict[k] isKindOfClass:[NSString class]] ? DMWiFiTag(dict[k]) : NSStringFromClass([dict[k] class]))];
        DMLog(o);
        if (q.count > 1 && [q[1] isEqualToString:@"handle"] && [list respondsToSelector:hu]) {
            ((void (*)(id, SEL, id))objc_msgSend)(list, hu, url);
            DMLog(@"[wifiurl] handleURL: sent to our list");
        }
        return YES;
    }
    if ([cmd isEqualToString:@"wifisettings"]) { DMWiFiOpenSettings(nil); return YES; }   // Wi-Fi Settings…
    if ([cmd isEqualToString:@"wifisettings_current"]) { DMWiFiOpenSettings(DMWiFiCurrentName()); return YES; }   // the current network's page (path=<name>)
    return NO;
}
#endif
